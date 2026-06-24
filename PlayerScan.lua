----------------------------------------------------------------------
-- VoidScout PlayerScan module
--
-- Silent background player scanner. Captures everything we can about
-- every player we encounter — nameplates, group/raid, mouseover/target,
-- LFG applicants, and tooltip enrichments (Archon WCL, RIO M+).
--
-- Lives under VoidScoutDB.playerScan so the data shares storage with
-- the rest of VoidScout (single SavedVars). Public API:
--
--   VoidScout.PlayerScan:GetByName(name, realm)  → player record or nil
--   VoidScout.PlayerScan:GetByGUID(guid)         → player record or nil
--   VoidScout.PlayerScan:GetBadges(name, realm)  → table of {label,kind}
--   VoidScout.PlayerScan:Stats()                 → snapshot of counters
--
-- Combat-aware: pauses inspect + tooltip scrape during combat, pauses
-- everything (including identity capture) inside instance combat.
--
-- Migrated from the standalone VoidScan addon — preserves any existing
-- VoidScanDB on first run, then VoidScout owns the data going forward.
----------------------------------------------------------------------

VoidScout = VoidScout or {}
VoidScout.PlayerScan = VoidScout.PlayerScan or {}
local PlayerScan = VoidScout.PlayerScan

local DEBUG = false   -- toggle via /vs scan debug

-- ============================================================
-- Combat / instance pause state
-- ============================================================
local inCombat   = false
local inInstance = false

-- ============================================================
-- Storage helpers (must be declared before any function that uses them
-- since Lua locals don't hoist).
-- ============================================================
local function DB()
    return VoidScoutDB.playerScan
end

local function Players()
    return DB().players
end

local function Stats()
    return DB().stats
end

-- ============================================================
-- Naming convention normalization (matches RIO / WCL / Archon / Carried)
--
--   Region: lowercase  ("us", "eu", "kr", "tw", "cn")
--   Realm:  display name kept; slug = lowercase + spaces/apostrophes/dashes stripped
--   Name:   original Blizzard casing preserved
--   Slug:   "{name-lower}-{realm-slug}-{region}"  (URL-safe, stable lookup key)
--
-- Connected realms aren't special-cased — char's home realm is what matters.
-- Cross-realm chars: UnitName returns "Name-Realm" — caller should split before passing.
-- ============================================================
local REGION_BY_ID = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw", [5] = "cn" }

local function CurrentRegion()
    local id = GetCurrentRegion and GetCurrentRegion()
    return REGION_BY_ID[id] or "us"
end

local function RealmSlug(realmName)
    if not realmName or realmName == "" then return "" end
    -- Strip apostrophes, dashes, spaces, then lowercase
    local s = realmName:gsub("['%-%s]", "")
    return s:lower()
end

-- Normalize name/realm into canonical form. Returns table with:
--   { name, realm, realm_slug, region, slug, display }
-- `region` defaults to current region if not specified.
function PlayerScan.Normalize(name, realm, region)
    if not name or name == "" then return nil end
    -- Handle "Name-Realm" form (cross-realm)
    local n, r = name:match("^([^-]+)-(.+)$")
    if n and r then
        name  = n
        realm = realm or r
    end
    realm  = (realm and realm ~= "") and realm or GetRealmName()
    region = (region and region ~= "") and region:lower() or CurrentRegion()
    local realmSlug = RealmSlug(realm)
    return {
        name       = name,
        realm      = realm,
        realm_slug = realmSlug,
        region     = region,
        slug       = (name:lower() .. "-" .. realmSlug .. "-" .. region),
        display    = name .. "-" .. realm .. " (" .. region:upper() .. ")",
    }
end

-- ============================================================
-- ArchonTooltipDB capture — REMOVED (May 28 2026)
--
-- We used to hook ArchonTooltip.AddProviderV2 to intercept Archon's
-- bundled DB at load time. That gave us per-player WCL data without
-- the user mouseovering each player. Functional but a gray-zone use
-- of Archon's internal Lua structures (not their published API).
--
-- For legal cleanliness we now source per-boss raid kill data from
-- Blizzard's official Battle.net API server-side. The addon no longer
-- intercepts Archon's data registration.
--
-- We still scrape tooltip TEXT when the user actively hovers a player
-- (separate ScrapeTooltip function below) — that's reading UI text
-- already visually displayed, not their internal data structures.
-- ============================================================
local archonProviders = {}
local archonHookInstalled = false

local function ForceLoadArchonDBs() end   -- no-op kept so Init doesn't break

-- Compatibility stub: callers used to get parse data here. Now always nil.
-- Server-side Blizzard API provides the equivalent per-boss data.
local function ArchonLookup(name, realm)
    return nil
end

PlayerScan.ArchonLookup = ArchonLookup

-- ============================================================
-- Midnight S1 dungeon whitelist. RIO's sortedDungeons returns
-- entries for ALL dungeons the player has scored in (current +
-- historical seasons), so we filter to ONLY the active 8 to keep
-- the "top timed keys" display relevant.
-- Source: midnight-12-content-pool memory + RIO db_dungeons.lua.
-- ============================================================
local MIDNIGHT_S1_MAP_IDS = {
    [658]=true, [1209]=true, [1753]=true, [2526]=true,
    [2805]=true, [2811]=true, [2874]=true, [2915]=true,
}
local MIDNIGHT_S1_SHORTS = {
    POS=true, SR=true, SEAT=true, AA=true,
    WS=true, MT=true, MC=true, NPX=true,
}
local MIDNIGHT_S1_NAMES = {
    ["Pit of Saron"]=true, ["Skyreach"]=true,
    ["Seat of the Triumvirate"]=true, ["Algeth'ar Academy"]=true,
    ["Windrunner Spire"]=true, ["Magisters' Terrace"]=true,
    ["Maisara Caverns"]=true, ["Nexus-Point Xenas"]=true,
}

local function is_midnight_s1_dungeon(d)
    if not d then return false end
    if d.instance_map_id and MIDNIGHT_S1_MAP_IDS[d.instance_map_id] then return true end
    if d.keystone_instance and d.instance_map_ids then
        for _, mid in ipairs(d.instance_map_ids) do
            if MIDNIGHT_S1_MAP_IDS[mid] then return true end
        end
    end
    if d.shortName and MIDNIGHT_S1_SHORTS[d.shortName] then return true end
    if d.name and MIDNIGHT_S1_NAMES[d.name] then return true end
    return false
end

-- ============================================================
-- Enrichment — pull RIO + Archon data for a player and cache it
-- on the player record. Cheap: both are in-memory lookups.
-- Called at first capture + when stale (>1h).
-- ============================================================
local ENRICH_TTL = 3600
-- Bump this whenever EnrichPlayer captures a NEW field that existing
-- records don't have. Records with schema < current force a re-enrich
-- regardless of TTL — otherwise users never see fields added post-install.
-- v3 (2026-06-01): top_keys now filtered to Midnight S1 only.
local ENRICH_SCHEMA = 3

local function EnrichPlayer(guid, force)
    local p = guid and Players()[guid]
    if not p or not p.name or not p.realm then return end
    local now = time()
    local schema_ok = (p.enrich_schema or 0) >= ENRICH_SCHEMA
    if not force and schema_ok and p.enriched_at and (now - p.enriched_at) < ENRICH_TTL then return end

    -- RaiderIO — note: function call (not method), passes name+realm
    if _G.RaiderIO and _G.RaiderIO.GetProfile then
        local ok, profile = pcall(_G.RaiderIO.GetProfile, p.name, p.realm)
        if ok and profile then
            local mp = profile.mythicKeystoneProfile
            if mp then
                p.rio_score      = mp.currentScore or mp.previousScore
                p.rio_score_prev = mp.previousScore
                -- Extract top 3 timed keys from sortedDungeons. RIO sorts by
                -- level desc; chests > 0 means timed (key completed within
                -- timer). We take the top 3 so a single lucky carry doesn't
                -- inflate the apparent skill level.
                if mp.sortedDungeons then
                    local timed = {}
                    for _, d in ipairs(mp.sortedDungeons) do
                        if (d.chests or 0) > 0 and (d.level or 0) > 0
                           and is_midnight_s1_dungeon(d.dungeon) then
                            table.insert(timed, {
                                level = d.level,
                                dungeon = (d.dungeon and (d.dungeon.shortName or d.dungeon.name)) or "?",
                            })
                        end
                    end
                    table.sort(timed, function(a, b) return a.level > b.level end)
                    p.top_keys = { timed[1], timed[2], timed[3] }
                    p.best_key_level   = timed[1] and timed[1].level   or nil
                    p.best_key_dungeon = timed[1] and timed[1].dungeon or nil
                end
            end
            local rp = profile.raidProfile
            if rp and rp.summary then p.rio_raid_summary = rp.summary end
        end
    end

    -- Archon enrichment REMOVED (May 28 2026). Per-boss raid data now
    -- sourced server-side from Blizzard's official API. ArchonLookup is
    -- a no-op stub; this block stays for future reactivation if needed.

    p.enriched_at = now
    p.enrich_schema = ENRICH_SCHEMA
end

PlayerScan.EnrichPlayer = EnrichPlayer

-- Trickle-enrich the whole DB every few seconds (low-priority background work).
-- Avoids stalling the frame: one player per tick.
local enrichCursor = nil
local function TrickleEnrich()
    if inCombat then return end
    local players = Players()
    local picked
    local nextCursor
    for guid in pairs(players) do
        if enrichCursor == nil or (guid > enrichCursor and not picked) then
            picked = guid
            nextCursor = guid
            break
        end
    end
    if not picked then
        enrichCursor = nil   -- wrap
        return
    end
    enrichCursor = nextCursor
    pcall(EnrichPlayer, picked)
end

-- ============================================================
-- Boss-kill achievement auto-discovery
-- Walks the achievement DB once and builds a map from achievement ID
-- to (raid, difficulty, boss) so we can probe exact mythic kill counts.
-- Result lives at VoidScoutDB.playerScan.boss_kill_ids and survives
-- reloads.
-- ============================================================
local BOSS_KEYWORDS = {
    Voidspire = {
        "averzian", "salhadaar", "vanguard", "vorasius",
        "vaelgor", "ezzorak", "crown of the cosmos",
    },
    Dreamrift = { "chimaerus" },
    MQD       = { "belo'ren", "beloren", "midnight falls" },
}
local DIFF_KEYWORDS = { M = "mythic", H = "heroic", N = "normal" }
-- Reverse map: boss name → raid
local BOSS_TO_RAID = {}
for raid, bosses in pairs(BOSS_KEYWORDS) do
    for _, bn in ipairs(bosses) do
        BOSS_TO_RAID[bn] = raid
    end
end

-- Blizzard's AchievementFrameComparison registers INSPECT_ACHIEVEMENT_READY
-- and crashes inside its OnEvent on 12.0.5 (calls GetCategoryNumAchievements
-- with categoryID="summary" — broken arg). We never show their comparison
-- UI; we use the API directly.
--
-- CRITICAL: installed at FILE LOAD (not gated behind any function) so the
-- patch is in place no matter what. Previously this lived inside
-- AutoDiscoverBossKills which returned early on subsequent /reloads after
-- first-time discovery — letting the crash recur.
local function _scrubAchievementUI()
    if AchievementFrameComparison and AchievementFrameComparison.UnregisterEvent then
        pcall(AchievementFrameComparison.UnregisterEvent,
              AchievementFrameComparison, "INSPECT_ACHIEVEMENT_READY")
    end
    if _G.AchievementFrameComparison_UpdateStatusBars and not _G._VS_StatusBarsPatched then
        local _orig = _G.AchievementFrameComparison_UpdateStatusBars
        _G.AchievementFrameComparison_UpdateStatusBars = function(id, ...)
            -- Blizzard's own code passes "summary" sometimes which crashes.
            -- Only forward when id is a real numeric category.
            if type(id) ~= "number" then return end
            return _orig(id, ...)
        end
        _G._VS_StatusBarsPatched = true
    end
end
_scrubAchievementUI()
-- Watch for Blizzard_AchievementUI loading later (load-on-demand) and
-- re-patch then in case Blizzard re-registers the event handler.
if not _G._VS_AchUIWatcher then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(_, event, addonName)
        if event == "ADDON_LOADED" and addonName == "Blizzard_AchievementUI" then
            _scrubAchievementUI()
        elseif event == "PLAYER_LOGIN" then
            -- After all addons loaded, run once more to catch anything
            _scrubAchievementUI()
        end
    end)
    _G._VS_AchUIWatcher = f
end


local function AutoDiscoverBossKills(force)
    local d = DB()
    if d.boss_kill_ids and next(d.boss_kill_ids) and not force then return end

    -- Force-load Blizzard_AchievementUI — GetCategoryList returns empty
    -- until that addon is loaded (same gotcha as Blizzard_LookingForGroupUI).
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_AchievementUI")
    elseif LoadAddOn then
        LoadAddOn("Blizzard_AchievementUI")
    end

    -- Re-run the scrub after loading the AchievementUI (in case it just loaded)
    _scrubAchievementUI()

    d.boss_kill_ids = {}     -- [achID] = "M_Voidspire_salhadaar"

    local cats = GetCategoryList and GetCategoryList() or {}
    if #cats == 0 then
        print("|cffff8080VoidScout:|r AutoDiscoverBossKills got 0 categories — Blizzard_AchievementUI failed to load")
        return
    end
    for _, catID in ipairs(cats) do
        -- Category name often encodes the difficulty (e.g. "Heroic Raid Bosses")
        local catName = ""
        if GetCategoryInfo then
            local cn = GetCategoryInfo(catID)
            if type(cn) == "string" then catName = cn:lower() end
        end
        local catDiff
        for diff, kw in pairs(DIFF_KEYWORDS) do
            if catName:find(kw, 1, true) then catDiff = diff; break end
        end

        local n = GetCategoryNumAchievements and GetCategoryNumAchievements(catID) or 0
        for i = 1, n do
            local achID, achName = GetAchievementInfo(catID, i)
            if achID and achName then
                local lower = achName:lower()
                -- Find boss
                local matchedBoss
                for bn in pairs(BOSS_TO_RAID) do
                    if lower:find(bn, 1, true) then matchedBoss = bn; break end
                end
                if matchedBoss then
                    -- Difficulty: prefer name, fall back to category
                    local matchedDiff
                    for diff, kw in pairs(DIFF_KEYWORDS) do
                        if lower:find(kw, 1, true) then matchedDiff = diff; break end
                    end
                    matchedDiff = matchedDiff or catDiff
                    if matchedDiff then
                        local raid = BOSS_TO_RAID[matchedBoss]
                        local key = matchedDiff .. "_" .. raid .. "_" .. matchedBoss
                        if not d.boss_kill_ids[achID] then
                            d.boss_kill_ids[achID] = key
                        end
                    end
                end
            end
        end
    end
    local count = 0
    for _ in pairs(d.boss_kill_ids) do count = count + 1 end
    print(("|cff00c7ffVoidScout|r auto-discovered %d boss-kill achievements"):format(count))
end

PlayerScan.AutoDiscoverBossKills = AutoDiscoverBossKills

-- ============================================================
-- Achievement probe list — Midnight Season 1 (verified IDs)
-- ============================================================
local ACHIEVEMENTS_TO_PROBE = {
    [61624] = "AOTC_Voidspire",
    [61625] = "CE_Voidspire",
    [61491] = "AOTC_Dreamrift",
    [61492] = "CE_Dreamrift",
    [61626] = "AOTC_MQD",
    [61627] = "CE_MQD",
    [61366] = "The_Voidspire",
    [61380] = "Glory_Midnight_Raider",
    [61255] = "KS_Conqueror_S1",
    [61256] = "KS_Master_S1",
    [61257] = "KS_Hero_S1",
    [61258] = "KS_Legend_S1",
    [63097] = "KS_Myth_S1",
}

-- ============================================================
-- DB init
-- ============================================================
local function InitDB()
    VoidScoutDB = VoidScoutDB or {}
    VoidScoutDB.playerScan = VoidScoutDB.playerScan or {}
    local d = VoidScoutDB.playerScan
    d.players = d.players or {}
    d.stats = d.stats or {
        total_seen     = 0,
        deep_inspected = 0,
        achievements_pulled = 0,
        tooltip_scrapes = 0,
        inspect_attempts = 0,
        inspect_failed_caninspect = 0,
        inspect_failed_no_unit = 0,
        skipped_combat = 0,
        skipped_instance_combat = 0,
        session_started = time(),
    }
    -- Backfill any missing counters
    for _, k in ipairs({
        "inspect_attempts","inspect_failed_caninspect","inspect_failed_no_unit",
        "skipped_combat","skipped_instance_combat"
    }) do
        d.stats[k] = d.stats[k] or 0
    end

    -- One-time cleanup: wipe scraped_wcl / scraped_archon / scraped_rio fields
    -- from existing player records. We stopped scraping tooltip text (May 29
    -- 2026) for legal cleanliness. Removing the fields means uploader won't
    -- re-send stale data to the server.
    if not d.scrapedFieldsCleanupV1 then
        local cleared = 0
        for _, p in pairs(d.players) do
            if p.scraped_wcl or p.scraped_archon or p.scraped_rio or p.scraped_at then
                p.scraped_wcl    = nil
                p.scraped_archon = nil
                p.scraped_rio    = nil
                p.scraped_at     = nil
                cleared = cleared + 1
            end
        end
        d.scrapedFieldsCleanupV1 = true
        if cleared > 0 then
            print(("|cff00c7ffVoidScout|r cleared scraped tooltip fields from %d records"):format(cleared))
        end
    end

    -- One-time backfill: stamp canonical slug on records captured before
    -- the slug system existed.
    if not d.slugBackfillDone then
        local n = 0
        for _, p in pairs(d.players) do
            if not p.slug and p.name and p.realm then
                local norm = PlayerScan.Normalize(p.name, p.realm)
                if norm then
                    p.slug       = norm.slug
                    p.realm_slug = norm.realm_slug
                    p.region     = norm.region
                    n = n + 1
                end
            end
        end
        d.slugBackfillDone = true
        if n > 0 then
            print(("|cff00c7ffVoidScout|r backfilled %d slugs"):format(n))
        end
    end

    -- One-time migration from legacy standalone VoidScanDB
    if not d.migratedFromVoidScan and _G.VoidScanDB then
        local legacy = _G.VoidScanDB
        local migrated_players = 0
        if type(legacy.players) == "table" then
            for guid, p in pairs(legacy.players) do
                if not d.players[guid] then
                    d.players[guid] = p
                    migrated_players = migrated_players + 1
                end
            end
        end
        if type(legacy.stats) == "table" then
            for k, v in pairs(legacy.stats) do
                if type(v) == "number" and d.stats[k] then
                    d.stats[k] = math.max(d.stats[k], v)
                end
            end
        end
        d.migratedFromVoidScan = true
        if migrated_players > 0 then
            print(("|cff00c7ffVoidScout|r migrated %d players from standalone VoidScan addon"):format(migrated_players))
        end
    end
end

-- ============================================================
-- Inspect queue — single in-flight serialization
-- ============================================================
local inspectQueue       = {}
local queuedSet          = {}
local lastInspected      = {}
local attemptCounts      = {}
local inFlightGuid       = nil
local inFlightStartedAt  = 0
local INSPECT_TIMEOUT    = 2.5
local INSPECT_INTERVAL   = 1
local DEEP_TTL           = 86400
local RETRY_THROTTLE     = 30
local STALE_THROTTLE     = 300

local function ShouldQueue(guid)
    if not guid or guid == "" then return false end
    if queuedSet[guid] then return false end
    if guid == inFlightGuid then return false end
    local p = Players()[guid]
    local got_inspect = p and p.deep_inspected and p.inspected_at
    local got_ach     = p and p.achievements_at
    local fully_done  = got_inspect and got_ach
       and (time() - p.inspected_at) < DEEP_TTL
       and (time() - p.achievements_at) < DEEP_TTL
    if fully_done then return false end
    local last = lastInspected[guid] or 0
    local back = (attemptCounts[guid] or 0) >= 3 and STALE_THROTTLE or RETRY_THROTTLE
    if (GetTime() - last) < back then return false end
    return true
end

local function QueueDeepInspect(guid)
    if not ShouldQueue(guid) then return end
    table.insert(inspectQueue, guid)
    queuedSet[guid] = true
end

local function QueueDeepInspectPriority(guid)
    if not ShouldQueue(guid) then return end
    table.insert(inspectQueue, 1, guid)
    queuedSet[guid] = true
end

local function FireInspect(unit, guid, source)
    if InspectFrame and InspectFrame:IsShown() then return false end
    inFlightGuid       = guid
    inFlightStartedAt  = GetTime()
    lastInspected[guid] = GetTime()
    attemptCounts[guid] = (attemptCounts[guid] or 0) + 1
    Stats().inspect_attempts = (Stats().inspect_attempts or 0) + 1
    if DEBUG then
        print(("|cff00c7ffVS-scan|r NotifyInspect [%s] → %s"):format(source, UnitName(unit) or "?"))
    end
    pcall(NotifyInspect, unit)
    if SetAchievementComparisonUnit then
        pcall(SetAchievementComparisonUnit, unit)
    end
    return true
end

local function ClearInFlight()
    inFlightGuid      = nil
    inFlightStartedAt = 0
end

local function ProcessInspectQueue()
    if inCombat then
        if #inspectQueue > 0 then
            Stats().skipped_combat = (Stats().skipped_combat or 0) + 1
        end
        return
    end
    if inFlightGuid and (GetTime() - inFlightStartedAt) > INSPECT_TIMEOUT then
        Stats().inspect_failed_no_unit = (Stats().inspect_failed_no_unit or 0) + 1
        ClearInFlight()
    end
    if inFlightGuid then return end
    if InspectFrame and InspectFrame:IsShown() then return end
    if #inspectQueue == 0 then return end

    while #inspectQueue > 0 do
        local guid = table.remove(inspectQueue, 1)
        queuedSet[guid] = nil
        local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid)
        if unit and UnitExists(unit) and UnitIsPlayer(unit) then
            FireInspect(unit, guid, "queue")
            return
        else
            Stats().inspect_failed_no_unit = (Stats().inspect_failed_no_unit or 0) + 1
        end
    end
end

local function TryInspectImmediate(unit)
    if inCombat then return end
    if not unit or not UnitExists(unit) then return end
    if not UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    QueueDeepInspectPriority(guid)
    if not inFlightGuid then ProcessInspectQueue() end
end

-- ============================================================
-- Identity capture (TIER 1)
-- ============================================================
local function CaptureBasic(unit)
    -- Consent gate. In local-only or no-choice mode we do not capture
    -- new player profile rows into VoidScoutDB.playerScan.players (so
    -- the Go uploader has nothing to drain to /api/profile/batch).
    -- Existing rows remain — we just stop populating new ones.
    if VoidScout_IsUploadAllowed and not VoidScout_IsUploadAllowed() then
        return
    end
    if inCombat and inInstance then
        Stats().skipped_instance_combat = (Stats().skipped_instance_combat or 0) + 1
        return
    end
    if not unit or not UnitExists(unit) then return end
    if not UnitIsPlayer(unit) then return end

    local guid = UnitGUID(unit)
    if not guid or not guid:find("^Player%-") then return end

    local name, realm = UnitName(unit)
    if not name then return end
    realm = (realm and realm ~= "") and realm or GetRealmName()

    local _, classFile  = UnitClass(unit)
    local _, raceFile   = UnitRace(unit)
    local level         = UnitLevel(unit)
    local faction       = UnitFactionGroup(unit)
    local guildName     = GetGuildInfo(unit)
    local zone          = GetRealZoneText()
    local subzone       = GetSubZoneText()

    local p = Players()[guid] or {}
    local was_new = not p.name

    p.name        = name
    p.realm       = realm
    p.class       = classFile or p.class
    p.race        = raceFile or p.race
    p.level       = (level and level > 0) and level or p.level
    p.faction     = faction or p.faction
    if guildName then p.guild = guildName end
    p.last_seen   = time()
    p.first_seen  = p.first_seen or time()
    p.sightings   = (p.sightings or 0) + 1
    p.last_zone   = zone
    p.last_subzone = subzone

    -- Canonical slug for cross-source lookup / website URL
    local norm = PlayerScan.Normalize(name, realm)
    if norm then
        p.slug       = norm.slug
        p.realm_slug = norm.realm_slug
        p.region     = norm.region
    end

    Players()[guid] = p
    if was_new then
        Stats().total_seen = (Stats().total_seen or 0) + 1
        -- Enrich brand-new players immediately (RIO + Archon are local in-memory
        -- lookups, very cheap). Stale players get refreshed by TrickleEnrich.
        pcall(EnrichPlayer, guid)
    end

    QueueDeepInspect(guid)
end

local function SafeCapture(unit) pcall(CaptureBasic, unit) end

-- ============================================================
-- Inspect results
-- ============================================================
local function OnInspectReady(guid)
    if not guid or guid == "" then return end
    local p = Players()[guid]
    if not p then return end

    local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid)
    if not unit or not UnitExists(unit) then return end

    local equipped_total, equipped_count = 0, 0
    p.gear = p.gear or {}
    for slot = 1, 17 do
        if slot ~= 4 then
            local link = GetInventoryItemLink(unit, slot)
            if link then
                local _, _, _, itemLevel = GetItemInfo(link)
                if itemLevel and itemLevel > 0 then
                    equipped_total = equipped_total + itemLevel
                    equipped_count = equipped_count + 1
                end
                p.gear[tostring(slot)] = link
            end
        end
    end
    if equipped_count > 0 then
        p.ilvl = math.floor(equipped_total / equipped_count + 0.5)
    end

    if GetInspectSpecialization then
        local specID = GetInspectSpecialization(unit)
        if specID and specID > 0 then
            p.spec_id = specID
            if GetSpecializationInfoByID then
                local _, specName = GetSpecializationInfoByID(specID)
                if specName then p.spec = specName end
            end
        end
    end

    p.deep_inspected = true
    p.inspected_at = time()
    attemptCounts[guid] = nil
    Stats().deep_inspected = (Stats().deep_inspected or 0) + 1
    -- Don't release the inspect lock if the player has an inspect frame open —
    -- Blizzard holds a single inspect target, so clearing here would evict THEIR
    -- visible inspect (Chonky/default) and blank it. Matches the IsShown() guards
    -- used when starting a scan (see lines ~547/580).
    if ClearInspectPlayer and not (InspectFrame and InspectFrame:IsShown()) then
        pcall(ClearInspectPlayer)
    end
    if guid == inFlightGuid then ClearInFlight() end
end

local function OnAchievementInspectReady(guid)
    if not guid then return end
    local p = Players()[guid]
    if not p then return end

    p.achievements = p.achievements or {}
    if GetAchievementComparisonInfo then
        for achID, label in pairs(ACHIEVEMENTS_TO_PROBE) do
            local ok, completed = pcall(GetAchievementComparisonInfo, achID)
            if ok and completed then
                p.achievements[label] = true
            end
        end
        -- Per-boss kill achievements
        p.boss_kills = p.boss_kills or {}
        local d = DB()
        if d.boss_kill_ids then
            for achID, key in pairs(d.boss_kill_ids) do
                local ok, completed = pcall(GetAchievementComparisonInfo, achID)
                if ok and completed then
                    p.boss_kills[key] = true
                end
            end
        end
    end
    if GetComparisonAchievementPoints then
        local pts = GetComparisonAchievementPoints()
        if pts and pts > 0 then p.achievement_points = pts end
    end
    p.achievements_at = time()
    Stats().achievements_pulled = (Stats().achievements_pulled or 0) + 1
    if ClearAchievementComparisonUnit then pcall(ClearAchievementComparisonUnit) end
end

-- ============================================================
-- Tooltip injection — append a "VoidScout" section showing the most
-- decision-useful fields (achievements, best key, Midnight zone progress,
-- parse avg) onto any player tooltip. Coexists with Archon/RIO sections.
-- ============================================================

-- Shared appender — builds + adds the VoidScout section to `tooltip` for the
-- player identified by `p` (the in-memory player record). `bundled` (optional)
-- is the matching VoidScoutBundle row, used as a fallback for players we
-- haven't personally encountered. Returns true if anything was appended.
-- Combat-paused and silent when there's no data.
-- Consolidated 7-line tooltip section.
-- Pulls from BOTH local p (freshest scan) AND bundled (server-derived
-- shipping data), preferring local where the two overlap. Suppresses
-- empty lines so the section is always tight.
--
-- Layout (any line skipped when empty):
--   1. badges      e.g. "CE Voidspire   AOTC Dreamrift   KS Legend"
--   2. Mythic kills per raid + total       "Mythic:  3/9 bosses  (18 kills)"
--   3. Heroic kills per raid + total       "Heroic:  9/9 bosses  (47 kills)"
--   4. Top keys + RIO                      "+20 AA  +20 WS  +19 POS    RIO 3805"
--   5. Timed bracket counts                "Timed: 4@+20-21  8@+18-19  12@+15-17"
--   6. Util Score + 3 highlights           "Util Score: 73 (Kicks 89, ...)  n=72"
--
-- Mythic raid order: Voidspire (6) + Dreamrift (1) + MQD (2) = 9 total bosses.
local RAID_BOSS_TOTALS = { Voidspire = 6, Dreamrift = 1, MQD = 2 }
local RAID_LETTERS     = { Voidspire = "V", Dreamrift = "D", MQD = "Q" }
local RAID_ORDER       = { "Voidspire", "Dreamrift", "MQD" }
local TOTAL_BOSSES     = 9

-- Returns {unique_bosses_killed, total_kill_count} for a given difficulty
-- key ("M"/"H"/"N"). Prefers local archon data when available, falls back
-- to bundle's mk (mythic unique only) + mkn (totals per raid+diff).
local function GetTierStats(p, bundled, diff)
    local uniq = 0       -- unique bosses killed across all 3 raids
    local total = 0      -- sum of completed_count

    -- Local archon zone-wide aggregate has progress (= unique) + raw count
    -- isn't there, so we'll rely on bundle's mkn for totals.
    local arch = p and p.archon or {}
    if arch[diff] and arch[diff].progress then
        uniq = arch[diff].progress or 0
    elseif diff == "M" and bundled and bundled.mk then
        for _, raid in ipairs(RAID_ORDER) do
            local n = bundled.mk[raid]
            if n and n > 0 then uniq = uniq + n end
        end
    elseif bundled and bundled.mkn then
        -- For H/N when no local archon data: infer unique bosses by
        -- assuming the player killed each unique boss at LEAST once
        -- (mkn is total — we don't know unique counts for H/N). Cap at
        -- per-raid boss total when total ≥ that count.
        for _, raid in ipairs(RAID_ORDER) do
            local letter = RAID_LETTERS[raid]
            local key = letter .. "_" .. diff
            local n = bundled.mkn[key]
            if n and n > 0 then
                uniq = uniq + math.min(n, RAID_BOSS_TOTALS[raid])
            end
        end
    end

    -- Total kill count from bundle's mkn map.
    if bundled and bundled.mkn then
        for _, raid in ipairs(RAID_ORDER) do
            local letter = RAID_LETTERS[raid]
            local key = letter .. "_" .. diff
            local n = bundled.mkn[key]
            if n then total = total + n end
        end
    end

    return uniq, total
end

local function AppendLinesForPlayer(tooltip, p, bundled)
    if not tooltip then return false end
    if inCombat then return false end
    if not p and not bundled then return false end
    p = p or {}

    local lines = {}

    -- ===== LINE 1: Achievement badges =====
    local a = p.achievements or {}
    local badges = {}
    if a.CE_Voidspire    then table.insert(badges, "|cffffa500CE Voidspire|r") end
    if a.CE_Dreamrift    then table.insert(badges, "|cffffa500CE Dreamrift|r") end
    if a.CE_MQD          then table.insert(badges, "|cffffa500CE MQD|r") end
    if not a.CE_Voidspire and a.AOTC_Voidspire then table.insert(badges, "|cffccccccAOTC Voidspire|r") end
    if not a.CE_Dreamrift and a.AOTC_Dreamrift then table.insert(badges, "|cffccccccAOTC Dreamrift|r") end
    if not a.CE_MQD       and a.AOTC_MQD       then table.insert(badges, "|cffccccccAOTC MQD|r") end
    if a.KS_Myth_S1      then table.insert(badges, "|cff40ff80KS Myth|r")
    elseif a.KS_Legend_S1 then table.insert(badges, "|cff40ff80KS Legend|r")
    elseif a.KS_Hero_S1   then table.insert(badges, "|cff40ff80KS Hero|r")
    elseif a.KS_Master_S1 then table.insert(badges, "|cff40ff80KS Master|r")
    end
    -- Bundle fallback when we have no local achievement data.
    if #badges == 0 and bundled and bundled.hr and bundled.hrr then
        local color
        if bundled.hr == "CE" or bundled.hr == "MProg" then color = "ffffa500"
        elseif bundled.hr == "AOTC" then color = "ffcccccc"
        else color = "ff888888"
        end
        table.insert(badges, ("|c%s%s %s|r"):format(color, bundled.hr, bundled.hrr))
    end
    if #badges > 0 then table.insert(lines, table.concat(badges, "   ")) end

    -- ===== GEAR QUALITY LINE (eye-catch) =====
    -- Live override: if this is the player themselves AND CaptureSelf has
    -- computed live_gear (which happens on every PLAYER_EQUIPMENT_CHANGED
    -- / SOCKET_INFO_UPDATE), use that instead of the 6h-stale bundle.
    -- Same logic applies to p.live_gear for any locally-scanned player.
    local ge = (p and p.live_gear) or (bundled and bundled.ge)
    if ge and ge.l and ge.l ~= "" then
        local color, bullet
        local lbl = ge.l
        -- No bullet glyph — WoW's default font (FRIZQT) doesn't have ●
        -- and renders it as an empty square. The colored label is enough.
        bullet = ""
        if lbl == "Pristine"     then color = "ff40ff80"
        elseif lbl == "Geared"   then color = "ffffd700"
        elseif lbl == "Partial"  then color = "ffff9933"
        else                          color = "ffff5050"
        end
        local breakdown = {}
        if ge.e and ge.e ~= "0/0" then
            table.insert(breakdown, ge.e .. " ench")
        end
        if ge.g and ge.g ~= "0/0" then
            table.insert(breakdown, ge.g .. " gems")
        end
        if ge.t and ge.t > 0 then
            table.insert(breakdown, ge.t .. "pc tier")
        end
        local prefix = (bullet ~= "" and (bullet .. " ")) or ""
        local line = ("|c%s%s%s|r"):format(color, prefix, lbl)
        if #breakdown > 0 then
            -- · U+00B7 middle-dot = UTF-8 0xC2 0xB7 = 194 183 (Lua 5.1 decimal escapes)
            line = line .. "  |cff888888" .. table.concat(breakdown, " \194\183 ") .. "|r"
        end
        table.insert(lines, line)
    end

    -- ===== LINES 2-3: Per-difficulty progression =====
    -- Mythic line: "|cffa335eeMythic:|r 3/9 bosses (18 kills)"
    -- Skip if zero kills on that diff.
    local diffLabels = {
        { d = "M", label = "Mythic", color = "ffa335ee" },
        { d = "H", label = "Heroic", color = "ffff8000" },
    }
    for _, info in ipairs(diffLabels) do
        local uniq, total = GetTierStats(p, bundled, info.d)
        if uniq > 0 or total > 0 then
            -- Cap uniq at TOTAL_BOSSES (sanity guard in case bundle/inspect inflates).
            uniq = math.min(uniq, TOTAL_BOSSES)
            local line
            if total > 0 then
                line = ("|c%s%s:|r %d/%d bosses  (%d kills)"):format(
                    info.color, info.label, uniq, TOTAL_BOSSES, total)
            else
                line = ("|c%s%s:|r %d/%d bosses"):format(
                    info.color, info.label, uniq, TOTAL_BOSSES)
            end
            table.insert(lines, line)
        end
    end
    -- Raid-only util score (statistically meaningful = sample >= 3)
    if bundled and bundled.usr and (not bundled.usrs or bundled.usrs >= 3) then
        local sample_str = bundled.usrs and (" |cff888888(" .. bundled.usrs .. " pulls)|r") or ""
        table.insert(lines, ("|cffa335ee  Raid Score:|r %d%s"):format(bundled.usr, sample_str))
    end

    -- ===== LINE 4: Top keys + RIO/M+ score =====
    local topLine = {}
    if p.top_keys and p.top_keys[1] then
        local parts = {}
        for i = 1, 3 do
            local k = p.top_keys[i]
            if k then table.insert(parts, "+" .. k.level .. " " .. (k.dungeon or "?")) end
        end
        if #parts > 0 then table.insert(topLine, table.concat(parts, "  ")) end
    elseif bundled and bundled.tk and bundled.tk[1] then
        table.insert(topLine, table.concat(bundled.tk, "  "))
    end
    if p.rio_score then
        table.insert(topLine, ("|cff40ff80RIO %d|r"):format(math.floor(p.rio_score)))
    elseif bundled and bundled.mp then
        table.insert(topLine, ("|cff40ff80RIO %d|r"):format(bundled.mp))
    end
    if #topLine > 0 then
        table.insert(lines, table.concat(topLine, "    "))
    end

    -- M+-only util score (statistically meaningful = sample >= 3)
    if bundled and bundled.usm and (not bundled.usms or bundled.usms >= 3) then
        local sample_str = bundled.usms and (" |cff888888(" .. bundled.usms .. " pulls)|r") or ""
        table.insert(lines, ("|cff40ff80  M+ Score:|r %d%s"):format(bundled.usm, sample_str))
    end

    -- ===== LINE 5: Timed bracket counts =====
    -- Bundle ships tb={['20+']=4,['18-19']=8,...}. Display label maps:
    --   20+   -> +20-21 (with the actual top key from tk if known)
    --   18-19 -> +18-19
    --   15-17 -> +15-17
    --   10-14 -> +10-14
    -- We display only the non-zero ones. Don't redundantly show brackets
    -- already covered by the top-keys line — just show the COUNTS.
    if bundled and bundled.tb then
        local order = {"20+", "18-19", "15-17", "10-14", "5-9", "2-4"}
        local parts = {}
        for _, k in ipairs(order) do
            local v = bundled.tb[k]
            if v and v > 0 then
                -- Format: "20+ x8" — bracket label first, then count.
                -- No leading + (avoids "+20+" double-plus).
                table.insert(parts, ("%s x%d"):format(k, v))
            end
        end
        if #parts > 0 then
            table.insert(lines, "|cffaaaaaaTimed:|r " .. table.concat(parts, "   "))
        end
    end

    -- ===== LINE 6: Util Score (THE moat) =====
    -- Only shown when sample size >= 3 (statistically meaningful).
    if bundled and bundled.us and (not bundled.ss or bundled.ss >= 3) then
        local pickAxes = {"Interrupts", "Dispels", "Avoidance", "Teamwork", "Activity", "Survival"}
        local highlights = {}
        if bundled.ua then
            local pairs_list = {}
            for _, ax in ipairs(pickAxes) do
                local v = bundled.ua[ax]
                if v then table.insert(pairs_list, { ax = ax, v = v }) end
            end
            table.sort(pairs_list, function(a_, b_) return a_.v > b_.v end)
            for i = 1, math.min(3, #pairs_list) do
                table.insert(highlights, ("%s %d"):format(pairs_list[i].ax, pairs_list[i].v))
            end
        end
        local line = ("|cffa335eeUtil Score:|r %d"):format(bundled.us)
        if #highlights > 0 then
            line = line .. "  (" .. table.concat(highlights, ", ") .. ")"
        end
        if bundled.ss then
            line = line .. ("  |cff888888(%d pulls)|r"):format(bundled.ss)
        end
        table.insert(lines, line)
    end

    -- ===== LINE 7: Session enrichment (the differentiator) =====
    -- bundled.e = { ic=<percentile>, ns=<90d kick count> } — present when the player
    -- has interrupts logged on the server. ic is the player's 90-day interrupt-VOLUME
    -- percentile vs the whole cohort. That's the clean signal: a true coverage% (kicks
    -- / interruptible casts) is uncomputable for M+ (no interruptible-cast data for
    -- trash) and a share% is polluted (encounter_id pools every group's runs).
    -- rcd/mh/uh (raid-CD alignment, marked/unmarked avoidable hits) were REMOVED — not
    -- computable from current data (no per-hit damage, per-mob markers, or avoidable
    -- classification), so we don't fake them.
    --   ic   — interrupt-volume percentile (0-100)
    --   ns   — 90-day kick count feeding the signal (also the >=3 confidence gate)
    if bundled and bundled.e and bundled.e.ic and bundled.e.ns and bundled.e.ns >= 3 then
        local e = bundled.e
        -- green >=80, yellow 50-79, red <50
        local color = (e.ic >= 80) and "40ff80" or ((e.ic >= 50) and "ffd700" or "ff6060")
        local line = ("|cffa335eeBehavior:|r |cff%skick %d%%|r"):format(color, e.ic)
        line = line .. ("  |cff888888(%d kicks, 90d)|r"):format(e.ns)
        table.insert(lines, line)
    end

    if #lines == 0 then return false end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cffa335eeVoidScout|r")
    for _, line in ipairs(lines) do
        tooltip:AddLine(line, 1, 1, 1, true)
    end
    return true
end

-- World/unit tooltip injector — resolves unit→guid→player from the tooltip.
local function InjectVoidScoutTooltip(tooltip)
    if tooltip ~= GameTooltip then return end
    if inCombat then return end
    pcall(function()
        local _, unit = tooltip:GetUnit()
        if not unit or unit == "" or not UnitIsPlayer(unit) then return end
        local guid = UnitGUID(unit)
        if not guid then return end
        local p = Players()[guid]
        -- Bundle lookup — even players we've never personally scanned
        -- get a tooltip section if they're in the shipped bundle.
        local bundled
        local name, realm = UnitName(unit)
        if name then
            local norm = PlayerScan.Normalize(name, realm)
            if norm then bundled = PlayerScan:GetBundled(norm.slug) end
        end
        if not p and not bundled then return end
        if AppendLinesForPlayer(tooltip, p, bundled) then
            tooltip:Show()
        end
    end)
end

PlayerScan.InjectVoidScoutTooltip = InjectVoidScoutTooltip

-- Public injector for non-unit contexts (LFG search entry, applicant member).
-- Looks the player up by name+realm + falls back to bundled data for any
-- player not in the local scan. Silent if neither has anything.
-- LFG callers pass live_rio = info.leaderOverallDungeonScore so we can
-- show the LIVE rating instead of our cached bundle value. Without the
-- live override, leaders who climbed M+ since our last backfill would
-- show stale numbers (e.g. bundle says 3020, live says 3108).
function PlayerScan:AppendTooltipLines(tooltip, name, realm, live_rio)
    if not tooltip or not name or name == "" then return false end
    if inCombat then return false end
    -- Strip "Name-Realm" if caller passed full name as `name`
    if not realm or realm == "" then
        local n, r = name:match("^([^-]+)-(.+)$")
        if n and r then name, realm = n, r end
    end
    local p = self:GetByName(name, realm)
    local bundled
    local norm = PlayerScan.Normalize(name, realm)
    if norm then bundled = self:GetBundled(norm.slug) end
    if not p and not bundled then return false end
    -- If we have a live RIO from the LFG context, clone bundled and
    -- override mp so the tooltip uses fresh data. Don't mutate the
    -- cached bundled table — other tooltips would see the override.
    if live_rio and live_rio > 0 then
        local b2 = bundled and {} or nil
        if b2 then
            for k, v in pairs(bundled) do b2[k] = v end
            b2.mp = live_rio
            bundled = b2
        end
    end
    local added
    pcall(function() added = AppendLinesForPlayer(tooltip, p, bundled) end)
    if added then
        pcall(function() tooltip:Show() end)
        return true
    end
    return false
end

-- ============================================================
-- Tooltip scraper REMOVED (May 29 2026).
-- Used to read parse %, M+ score, best key from Archon/RIO tooltip text.
-- Removed for maximum legal cleanliness — we now source equivalent data
-- from sanctioned Blizzard API (server-side) + RIO public API (client).
-- Stub kept so PostCall registration in Init doesn't error.
-- ============================================================
local function ScrapeTooltip(_) end

-- ============================================================
-- Encounter kill tracking (for SELF, via ENCOUNTER_END).
-- WoW's combat log fires ENCOUNTER_END with success=1 on every boss kill,
-- including the exact difficulty. We use this to give exact N/H/M kill
-- counts for the player's own character — no achievement guessing.
--
-- For OTHER players, this requires them to be running VoidScout. Until
-- the server-side WCL fetch is wired, others fall back to mythic-only
-- achievement probe + meta-achievement inference.
-- ============================================================
-- Map ENCOUNTER_END encounterName → (raid, bossKey)
-- Boss keys must match the BOSS_TO_RAID keys above (lowercase substring).
local ENCOUNTER_NAME_KEYWORDS = {
    -- Voidspire
    ["imperator averzian"]    = { raid = "Voidspire", boss = "averzian" },
    ["averzian"]              = { raid = "Voidspire", boss = "averzian" },
    ["fallen-king salhadaar"] = { raid = "Voidspire", boss = "salhadaar" },
    ["salhadaar"]             = { raid = "Voidspire", boss = "salhadaar" },
    ["lightblinded vanguard"] = { raid = "Voidspire", boss = "vanguard" },
    ["vorasius"]              = { raid = "Voidspire", boss = "vorasius" },
    ["vaelgor"]               = { raid = "Voidspire", boss = "vaelgor" },
    ["ezzorak"]               = { raid = "Voidspire", boss = "vaelgor" },
    ["crown of the cosmos"]   = { raid = "Voidspire", boss = "crown of the cosmos" },
    -- Dreamrift
    ["chimaerus"]             = { raid = "Dreamrift", boss = "chimaerus" },
    -- MQD
    ["belo'ren"]              = { raid = "MQD",       boss = "belo'ren" },
    ["beloren"]               = { raid = "MQD",       boss = "belo'ren" },
    ["midnight falls"]        = { raid = "MQD",       boss = "midnight falls" },
}
-- WoW raid difficulty IDs: 14=Normal, 15=Heroic, 16=Mythic, 17=LFR
local DIFF_ID_TO_KEY = { [14] = "N", [15] = "H", [16] = "M" }

local function OnEncounterEnd(encounterID, encounterName, difficultyID, _, success)
    if success ~= 1 then return end                       -- wipe
    local diff = DIFF_ID_TO_KEY[difficultyID]
    if not diff then return end                           -- LFR / not raid
    if not encounterName then return end
    local lower = encounterName:lower()
    local match
    for kw, info in pairs(ENCOUNTER_NAME_KEYWORDS) do
        if lower:find(kw, 1, true) then match = info; break end
    end
    if not match then return end

    local guid = UnitGUID("player")
    if not guid then return end
    local p = Players()[guid] or {}
    p.boss_kills = p.boss_kills or {}
    local key = diff .. "_" .. match.raid .. "_" .. match.boss
    if not p.boss_kills[key] then
        p.boss_kills[key] = true
        print(("|cff00c7ffVoidScout|r recorded %s kill: %s"):format(diff, encounterName))
    end
    Players()[guid] = p
end

-- ============================================================
-- Lockout-based boss kill capture (self only).
-- GetSavedInstanceInfo + GetSavedInstanceEncounterInfo expose this week's
-- per-boss-per-difficulty kill status, character-specific (not account-wide).
-- We mark p.boss_kills as true on first sighting and NEVER remove — so the
-- Tuesday reset wiping the lockout data doesn't erase what we captured.
-- Combined with the live ENCOUNTER_END handler, this seeds historical kills
-- the very first time the addon runs (assuming the user re-killed bosses
-- this week, which most active raiders do).
-- ============================================================
local function CaptureSelfLockouts()
    local guid = UnitGUID("player")
    if not guid then return end
    local p = Players()[guid]
    if not p then return end
    p.boss_kills = p.boss_kills or {}

    local n = GetNumSavedInstances and GetNumSavedInstances() or 0
    local seeded = 0
    for i = 1, n do
        local name, _, _, diffID, _, _, _, isRaid, _, _, numEncounters = GetSavedInstanceInfo(i)
        if isRaid and DIFF_ID_TO_KEY[diffID] and numEncounters then
            local diffKey = DIFF_ID_TO_KEY[diffID]
            for ei = 1, numEncounters do
                local encName, _, isKilled = GetSavedInstanceEncounterInfo(i, ei)
                if isKilled and encName then
                    local lower = encName:lower()
                    for kw, info in pairs(ENCOUNTER_NAME_KEYWORDS) do
                        if lower:find(kw, 1, true) then
                            local key = diffKey .. "_" .. info.raid .. "_" .. info.boss
                            if not p.boss_kills[key] then
                                p.boss_kills[key] = true
                                seeded = seeded + 1
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    if seeded > 0 then
        print(("|cff00c7ffVoidScout|r seeded %d boss kills from this week's raid lockouts"):format(seeded))
    end
end

-- ============================================================
-- Self capture — direct API, no inspect throttle.
-- Achievements for the player's own character come from GetAchievementInfo,
-- ilvl from GetAverageItemLevel, spec from GetSpecializationInfo.
-- Fires at login + on ACHIEVEMENT_EARNED so newly-unlocked CE/AOTC
-- shows up immediately.
-- ============================================================
local function CaptureSelf()
    local guid = UnitGUID("player")
    if not guid then return end

    local name, realm = UnitName("player")
    realm = (realm and realm ~= "") and realm or GetRealmName()
    local _, classFile = UnitClass("player")
    local _, raceFile  = UnitRace("player")
    local faction = UnitFactionGroup("player")
    local guildName = GetGuildInfo("player")

    local p = Players()[guid] or {}
    p.name      = name or p.name
    p.realm     = realm or p.realm
    p.class     = classFile or p.class
    p.race      = raceFile or p.race
    p.faction   = faction or p.faction
    p.level     = UnitLevel("player") or p.level
    if guildName then p.guild = guildName end
    p.last_seen  = time()
    p.first_seen = p.first_seen or time()
    p.is_self    = true

    -- ilvl + spec from own APIs (no inspect)
    -- GetAverageItemLevel returns (overall, equipped, pvp). The in-game
    -- character pane shows OVERALL (counts higher-ilvl items in bags too),
    -- which is what users mean when they say "I'm ilvl X". Use that to
    -- match expectations.
    local overall = GetAverageItemLevel()
    if overall and overall > 0 then
        p.ilvl = math.floor(overall + 0.5)
    end
    local specIdx = GetSpecialization()
    if specIdx then
        local id, specName = GetSpecializationInfo(specIdx)
        if id then p.spec_id = id end
        if specName then p.spec = specName end
    end
    -- Mark inspect-equivalent so re-queue logic doesn't try to NotifyInspect us
    p.deep_inspected = true
    p.inspected_at = time()

    -- LIVE M+ rating from Blizzard's client API. Same number Blizzard
    -- shows in your LFG group listing + tooltip. Updates the instant
    -- you finish a key, before our 6h bundle refresh catches up.
    -- Sets p.rio_score (existing field; takes precedence over bundle in
    -- AppendLinesForPlayer) so YOUR own tooltip always reflects your
    -- CURRENT score.
    if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
        local ok_s, score = pcall(C_ChallengeMode.GetOverallDungeonScore)
        if ok_s and score and score > 0 then
            p.rio_score = score
        end
    end

    -- LIVE GEAR QUALITY — recomputed from current equipped items every
    -- time CaptureSelf fires (which includes PLAYER_EQUIPMENT_CHANGED).
    -- Mirror of server's equipment summary algo so the player NEVER sees
    -- stale gear data for themselves. Tier-piece detection is best-effort
    -- (we can't easily check set bonuses client-side without per-item
    -- lookups); we fall back to the bundle's t value when present.
    local ENCH_SLOTS = {16, 17, 5, 7, 8, 11, 12}  -- mainhand, offhand, chest, legs, feet, ring1, ring2
    local GEAR_SLOTS = {1, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17}
    local enchants_have, enchants_max = 0, 0
    local gems_have, gems_max = 0, 0
    for _, slot in ipairs(ENCH_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            enchants_max = enchants_max + 1
            -- Item link format: |Hitem:itemID:enchantID:gem1:gem2:gem3:gem4:...
            local _, enchantID = link:match("|Hitem:(%d+):(%d+)")
            if enchantID and enchantID ~= "0" then
                enchants_have = enchants_have + 1
            end
        end
    end
    for _, slot in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            -- Empty sockets via GetItemStats (returns EMPTY_SOCKET_* keys)
            local empty = 0
            local ok_st, stats = pcall(GetItemStats, link)
            if ok_st and stats then
                for k, v in pairs(stats) do
                    if type(k) == "string" and k:find("EMPTY_SOCKET_") then
                        empty = empty + (v or 0)
                    end
                end
            end
            -- Filled gems via link parse (positions 3-6 after itemID)
            local g1, g2, g3, g4 = link:match("|Hitem:%d+:%d+:(%d+):(%d+):(%d+):(%d+)")
            local filled = 0
            for _, g in ipairs({g1, g2, g3, g4}) do
                if g and g ~= "0" and g ~= "" then filled = filled + 1 end
            end
            gems_have = gems_have + filled
            gems_max = gems_max + filled + empty
        end
    end
    -- Composite quality 0-100 (matches server formula).
    -- Tier: keep last-known value from previous capture or bundle until
    -- we add client-side tier detection.
    local existing_tier = (p.live_gear and p.live_gear.t) or 0
    local enchant_pct = enchants_max > 0 and (enchants_have / enchants_max * 40) or 40
    local socket_pct  = gems_max > 0     and (gems_have / gems_max * 30)         or 30
    local tier_score  = math.min(existing_tier / 4, 1.0) * 30
    local quality = math.floor(enchant_pct + socket_pct + tier_score + 0.5)
    local label
    if     quality >= 90 then label = "Pristine"
    elseif quality >= 70 then label = "Geared"
    elseif quality >= 40 then label = "Partial"
    else                       label = "Lazy" end
    p.live_gear = {
        q = quality,
        l = label,
        e = enchants_have .. "/" .. enchants_max,
        g = gems_have     .. "/" .. gems_max,
        t = existing_tier,
    }

    -- Achievements via direct API. Use wasEarnedByMe (13th return) instead
    -- of completed (4th return) to avoid account-wide achievement leaks —
    -- e.g. an alt who hit KS Myth would otherwise show as Myth on Vede too.
    p.achievements = p.achievements or {}
    for achID, label in pairs(ACHIEVEMENTS_TO_PROBE) do
        local _, _, _, _, _, _, _, _, _, _, _, _, wasEarnedByMe = GetAchievementInfo(achID)
        if wasEarnedByMe then
            p.achievements[label] = true
        else
            p.achievements[label] = nil
        end
    end

    -- Per-boss kill achievements (auto-discovered map).
    -- Use wasEarnedByMe to avoid alt-leak. Important here too — an alt who
    -- killed Mythic Salhadaar would otherwise add false kills to Vede's record.
    -- NOTE: never unset boss_kills (ratchet-only); other sources like lockout
    -- + ENCOUNTER_END can have set them true even when this achievement is
    -- character-mismatched.
    p.boss_kills = p.boss_kills or {}
    local d = DB()
    if d.boss_kill_ids then
        for achID, key in pairs(d.boss_kill_ids) do
            local _, _, _, _, _, _, _, _, _, _, _, _, wasEarnedByMe = GetAchievementInfo(achID)
            if wasEarnedByMe then
                p.boss_kills[key] = true
            end
        end
    end

    if GetTotalAchievementPoints then
        local pts = GetTotalAchievementPoints()
        if pts and pts > 0 then p.achievement_points = pts end
    end
    p.achievements_at = time()

    local norm = PlayerScan.Normalize(name, realm)
    if norm then
        p.slug       = norm.slug
        p.realm_slug = norm.realm_slug
        p.region     = norm.region
    end

    Players()[guid] = p
    pcall(EnrichPlayer, guid)   -- own RIO + Archon data
end

-- ============================================================
-- Public API
-- ============================================================
-- ============================================================
-- Raid progress inference from achievements
-- Midnight Season 1: 3 raids (Voidspire 6, Dreamrift 1, MQD 2)
--   AOTC_X = killed end boss on Heroic → infer full H clear
--   CE_X   = killed end boss on Mythic → ≥1 mythic kill (often more)
--   The_Voidspire = killed every Voidspire boss on some difficulty
-- TODO: per-boss kill achievement IDs would give exact M counts.
-- TODO: server-side WCL scrape will overlay real parse data when ready.
-- ============================================================
local RAIDS = {
    { name = "Voidspire", bosses = 6 },
    { name = "Dreamrift", bosses = 1 },
    { name = "MQD",       bosses = 2 },
}

local function ProgressString(killed, total)
    if not killed then return "-" end
    return tostring(killed) .. "/" .. tostring(total)
end

-- Count per-boss kills via the auto-discovered map. Falls back to meta-ach
-- inference when boss_kills hasn't been populated yet (legacy data, applicants
-- we haven't deep-inspected).
local function CountKills(p, diff, raid)
    if not p.boss_kills then return nil end
    local n = 0
    local prefix = diff .. "_" .. raid .. "_"
    for key in pairs(p.boss_kills) do
        if key:sub(1, #prefix) == prefix then n = n + 1 end
    end
    return n > 0 and n or nil
end

function PlayerScan:GetRaidProgress(name, realm)
    local p = self:GetByName(name, realm)
    if not p then return nil end

    local a = p.achievements or {}
    local arch = p.archon or {}    -- { N={progress,total,avg,asp,rank,encounters}, H={}, M={} }
    local out = {}

    -- Per-raid resolver: per-boss kill achievements > meta-achievement inference.
    -- TODO: when we have encounter_id → raid mapping, prefer Archon per-encounter
    -- data here for exact per-raid kill counts on Heroic/Normal too.
    local function resolve(raid, total, aotc, ce)
        local function pick(diff, infer)
            local k = CountKills(p, diff, raid)
            if k ~= nil then return k end
            return infer
        end
        return {
            N = pick("N", aotc and total or nil),
            H = pick("H", aotc and total or nil),
            M = pick("M", ce   and ">=1" or nil),
        }
    end

    out.Voidspire = resolve("Voidspire", 6, a.AOTC_Voidspire or a.The_Voidspire, a.CE_Voidspire)
    out.Dreamrift = resolve("Dreamrift", 1, a.AOTC_Dreamrift, a.CE_Dreamrift)
    out.MQD       = resolve("MQD",       2, a.AOTC_MQD,       a.CE_MQD)

    -- Archon zone-wide aggregate (Midnight = 9 bosses across 3 raids).
    -- Real data source — exact kill count + parse avg per difficulty.
    out.archon = {
        N = arch.N and arch.N.progress and {
            progress = arch.N.progress, total = arch.N.total, avg = arch.N.avg,
        } or nil,
        H = arch.H and arch.H.progress and {
            progress = arch.H.progress, total = arch.H.total, avg = arch.H.avg,
        } or nil,
        M = arch.M and arch.M.progress and {
            progress = arch.M.progress, total = arch.M.total, avg = arch.M.avg,
        } or nil,
    }

    -- Parse avg: prefer Archon (real data) > tooltip scrape fallback.
    -- Take the best across difficulties.
    local best_parse
    for _, d in ipairs({"M", "H", "N"}) do
        local sec = arch[d]
        if sec and sec.avg and sec.avg > (best_parse or 0) then
            best_parse = sec.avg
        end
    end
    out.parse_avg = best_parse
    return out
end

function PlayerScan:GetByGUID(guid)
    if not guid then return nil end
    return Players()[guid]
end

-- ============================================================
-- Bundle accessor — server-generated player data shipped IN THE ADDON
-- (same model as RaiderIO/Archon's bundled DB). VoidScoutBundle.lua is
-- generated by seeder/generate_bundle.py and pushed via CurseForge.
--
-- Lookups are by canonical slug ("vede-elune-us"). Returns the compact
-- short-field-name record:
--   { n=name, r=realm, c=class, s=spec, i=ilvl, mp=mplus_score,
--     tk={top keys}, mk={mythic kills per raid},
--     hr=highest_tier_code, hrr=raid_for_highest_tier,
--     us=util_score, ua={util_axes}, ss=util_sample_size, la=last_active }
-- Or nil if the slug isn't in the bundle.
-- ============================================================
function PlayerScan:GetBundled(slug)
    if not slug or not _G.VoidScoutBundle then return nil end
    local players = _G.VoidScoutBundle.players
    return players and players[slug] or nil
end

-- Lookup by canonical slug ("vede-elune-us"). Faster than GetByName for
-- repeated calls — we keep a slug→guid index in memory.
local slugIndex = nil
local function RebuildSlugIndex()
    slugIndex = {}
    for guid, p in pairs(Players()) do
        if p.slug then slugIndex[p.slug] = guid end
    end
end

function PlayerScan:GetBySlug(slug)
    if not slug then return nil end
    if not slugIndex then RebuildSlugIndex() end
    local guid = slugIndex[slug]
    if not guid then return nil end
    local p = Players()[guid]
    -- Stale guid (player wiped or slug-conflict): rebuild + retry once
    if not p or p.slug ~= slug then
        RebuildSlugIndex()
        guid = slugIndex[slug]
        p = guid and Players()[guid]
    end
    return p
end

function PlayerScan:GetByName(name, realm)
    if not name then return nil end
    -- Player records are GUID-keyed; scan linearly. With ~1k players this
    -- is microseconds. For larger DBs we can add a name→guid index later.
    local target_realm = realm and realm ~= "" and realm or nil
    for _, p in pairs(Players()) do
        if p.name == name then
            if not target_realm or p.realm == target_realm then
                return p
            end
        end
    end
    return nil
end

-- Returns a short list of badges for UI use.
-- Each badge: { label = "CE Voidspire", kind = "ce|aotc|key|score" }
function PlayerScan:GetBadges(name, realm)
    local p = self:GetByName(name, realm)
    if not p then return nil end
    local out = {}
    local a = p.achievements or {}
    if a.CE_Voidspire    then table.insert(out, { label = "CE Voidspire",    kind = "ce" }) end
    if a.CE_Dreamrift    then table.insert(out, { label = "CE Dreamrift",    kind = "ce" }) end
    if a.CE_MQD          then table.insert(out, { label = "CE MQD",          kind = "ce" }) end
    if a.AOTC_Voidspire and not a.CE_Voidspire then table.insert(out, { label = "AOTC Voidspire", kind = "aotc" }) end
    if a.AOTC_Dreamrift and not a.CE_Dreamrift then table.insert(out, { label = "AOTC Dreamrift", kind = "aotc" }) end
    if a.AOTC_MQD       and not a.CE_MQD       then table.insert(out, { label = "AOTC MQD",       kind = "aotc" }) end
    if a.KS_Myth_S1      then table.insert(out, { label = "KS Myth",      kind = "key" })
    elseif a.KS_Legend_S1 then table.insert(out, { label = "KS Legend",   kind = "key" })
    elseif a.KS_Hero_S1   then table.insert(out, { label = "KS Hero",     kind = "key" })
    elseif a.KS_Master_S1 then table.insert(out, { label = "KS Master",   kind = "key" })
    end
    return out
end

-- Diagnostic dump: pull everything we can from RaiderIO + Archon for a player.
-- Prints to chat. Returns the data table too.
function PlayerScan:Probe(name, realm)
    name = name or UnitName("player")
    realm = (realm and realm ~= "") and realm or GetRealmName()
    local out = { name = name, realm = realm }
    print(("|cff00c7ffVoidScout probe|r %s-%s"):format(name, realm))

    -- RaiderIO — note: GetProfile is a regular function, NOT a method.
    -- Call with (name, realm) — passing self produces "no profile" silently.
    if _G.RaiderIO and _G.RaiderIO.GetProfile then
        local ok, profile = pcall(_G.RaiderIO.GetProfile, name, realm)
        if ok and profile then
            out.rio = profile
            local mp = profile.mythicKeystoneProfile
            if mp then
                print(("  RIO M+:   curr=%s  prev=%s  mainCurr=%s"):format(
                    tostring(mp.currentScore or "-"),
                    tostring(mp.previousScore or "-"),
                    tostring(mp.mainCurrentScore or "-")))
                if mp.sortedDungeons then
                    for _, d in ipairs(mp.sortedDungeons) do
                        if d.dungeon and (d.level or 0) > 0 then
                            print(("    %s  +%d  %s"):format(
                                d.dungeon.shortName or d.dungeon.name or "?",
                                d.level or 0,
                                d.chests and (d.chests .. "/3") or ""))
                        end
                    end
                end
            end
            local rp = profile.raidProfile
            if rp then
                print("  RIO Raid: " .. (profile.raidProfile.summary or "<no summary>"))
            end
            local pp = profile.profile
            if pp then
                print(("  RIO Profile: %s-%s  class=%s  faction=%s"):format(
                    pp.name or "?", pp.realm or "?",
                    tostring(pp.class or "-"), tostring(pp.faction or "-")))
            end
        else
            print("  RaiderIO: |cffff8080no profile for this player|r")
        end
    else
        print("  RaiderIO: |cffff8080addon not loaded|r")
    end

    -- Archon section removed from probe (May 28 2026). Per-boss raid data
    -- now sourced server-side from Blizzard's official API. Use the website
    -- (voidscout.io/character/...) to see Blizzard-sourced raid_progress.

    return out
end

function PlayerScan:Stats()
    local s = Stats()
    local total = 0
    for _ in pairs(Players()) do total = total + 1 end
    return {
        total = total,
        deep_inspected = s.deep_inspected or 0,
        attempts = s.inspect_attempts or 0,
        achievements_pulled = s.achievements_pulled or 0,
        tooltip_scrapes = s.tooltip_scrapes or 0,
        skipped_combat = s.skipped_combat or 0,
        in_combat = inCombat,
        in_instance = inInstance,
    }
end

function PlayerScan:SetDebug(on)
    DEBUG = on and true or false
    print(("|cff00c7ffVoidScout PlayerScan|r debug = %s"):format(DEBUG and "ON" or "OFF"))
end

-- ============================================================
-- Init — called from Core.lua at PLAYER_LOGIN
-- ============================================================
function PlayerScan:Init()
    InitDB()

    -- Report bundle load status so the user can see at a glance that the
    -- shipped data is in memory. Bundle ships in the addon (RIO/Archon
    -- model) — no HTTP fetch, no SavedVar merge, just `require`-style load.
    if _G.VoidScoutBundle and _G.VoidScoutBundle.players then
        local n = 0
        for _ in pairs(_G.VoidScoutBundle.players) do n = n + 1 end
        local genTS = _G.VoidScoutBundle.generated_at or 0
        local genStr = (genTS > 0) and date("%Y-%m-%d", genTS) or "stub"
        local ver = _G.VoidScoutBundle.version or 0
        if n > 0 then
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("INSPECT_READY")
    f:RegisterEvent("INSPECT_ACHIEVEMENT_READY")
    f:RegisterEvent("ACHIEVEMENT_EARNED")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    f:RegisterEvent("ENCOUNTER_END")
    -- M+ score events — refresh self snapshot the instant a key completes
    f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    f:RegisterEvent("MYTHIC_PLUS_NEW_WEEKLY_RECORD")
    f:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    -- Bag/socket changes — gem changes don't fire PLAYER_EQUIPMENT_CHANGED reliably
    f:RegisterEvent("SOCKET_INFO_UPDATE")
    f:SetScript("OnEvent", function(_, event, arg1, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
        elseif event == "PLAYER_ENTERING_WORLD" then
            inInstance = (IsInInstance and IsInInstance()) and true or false
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            SafeCapture(arg1)
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            SafeCapture("mouseover")
            pcall(TryInspectImmediate, "mouseover")
        elseif event == "PLAYER_TARGET_CHANGED" then
            SafeCapture("target")
            pcall(TryInspectImmediate, "target")
        elseif event == "GROUP_ROSTER_UPDATE" then
            for i = 1, 40 do SafeCapture("raid"..i) end
            for i = 1, 4  do SafeCapture("party"..i) end
            SafeCapture("player")
        elseif event == "INSPECT_READY" then
            pcall(OnInspectReady, arg1)
        elseif event == "INSPECT_ACHIEVEMENT_READY" then
            pcall(OnAchievementInspectReady, arg1)
        elseif event == "ACHIEVEMENT_EARNED" then
            pcall(CaptureSelf)
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            pcall(CaptureSelf)
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            pcall(CaptureSelf)
        elseif event == "ENCOUNTER_END" then
            -- Args: encounterID, encounterName, difficultyID, groupSize, success
            local name, diff, _, success = ...
            pcall(OnEncounterEnd, arg1, name, diff, nil, success)
        elseif event == "CHALLENGE_MODE_COMPLETED"
            or event == "MYTHIC_PLUS_NEW_WEEKLY_RECORD"
            or event == "WEEKLY_REWARDS_UPDATE"
            or event == "SOCKET_INFO_UPDATE" then
            -- Refresh self snapshot so the LIVE M+ rating / gear data
            -- is current for the tooltip render path. CaptureSelf reads
            -- all the relevant client APIs and updates Players()[self_guid].
            pcall(CaptureSelf)
        end
    end)

    -- Archon hook removed (May 28 2026) — see ArchonLookup stub. Per-boss
    -- raid data now comes from server-side Blizzard API.

    -- Discover all boss-kill achievement IDs from the achievement DB.
    -- Runs once; result saved in VoidScoutDB.playerScan.boss_kill_ids.
    C_Timer.After(0.3, function()
        local ok, err = pcall(AutoDiscoverBossKills, false)
        if not ok then
            print("|cffff8080VoidScout:|r AutoDiscoverBossKills error: " .. tostring(err))
        end
    end)

    -- Seed our own record immediately (own APIs, no inspect throttle).
    -- Done after discovery so CaptureSelf can probe the boss_kill_ids map.
    C_Timer.After(0.8, function()
        local ok, err = pcall(CaptureSelf)
        if not ok then
            print("|cffff8080VoidScout:|r CaptureSelf error: " .. tostring(err))
        end
    end)

    -- Then seed boss_kills from current-week raid lockouts. Runs after
    -- CaptureSelf so the player record exists.
    C_Timer.After(1.5, function()
        local ok, err = pcall(CaptureSelfLockouts)
        if not ok then
            print("|cffff8080VoidScout:|r CaptureSelfLockouts error: " .. tostring(err))
        end
    end)

    C_Timer.NewTicker(INSPECT_INTERVAL, ProcessInspectQueue)

    -- Background enrichment: one player per 2s. Refreshes stale records
    -- and back-fills any captured before Archon DB was loaded.
    C_Timer.NewTicker(2, TrickleEnrich)

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, ScrapeTooltip)
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, InjectVoidScoutTooltip)
        -- Suppress RaiderIO's tooltip lines — we render equivalent data in
        -- our VoidScout section. RIO addon stays ENABLED (we still call
        -- :GetProfile() to read their bundled data); only the visual tooltip
        -- output is hidden. Opt-out via VoidScoutDB.suppressRIOTooltip=false.
        pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tooltip)
            if tooltip ~= GameTooltip then return end
            if VoidScoutDB and VoidScoutDB.suppressRIOTooltip == false then return end
            for i = 1, tooltip:NumLines() do
                local lL = _G["GameTooltipTextLeft" .. i]
                local lR = _G["GameTooltipTextRight" .. i]
                local txtL = lL and lL:GetText() or ""
                local txtR = lR and lR:GetText() or ""
                -- CRITICAL: tooltip text from cross-realm/unknown players
                -- is kstring (secret). Calling :find() on a kstring throws
                -- "attempt to index local '...' (a secret string value)"
                -- AND taints us. Skip lines where either side is secret —
                -- we can't suppress them, but at least we don't crash and
                -- propagate taint into the tooltip pipeline.
                local secretL = _G.issecretvalue and issecretvalue(txtL)
                local secretR = _G.issecretvalue and issecretvalue(txtR)
                if not secretL and not secretR
                   and type(txtL) == "string" and type(txtR) == "string"
                   and (txtL:find("[Rr]aider%.?[Ii][Oo]") or txtR:find("[Rr]aider%.?[Ii][Oo]")
                        or txtL:find("[Bb]est [Rr]un")
                        or txtL:find("[Tt]imed%s*%+?%d")
                        or txtL:find("VS/DR/MQD")         or txtL:find("Mythic VS")
                        or txtL:find("Heroic VS")         or txtL:find("Warcraft Logs")
                        or txtL:find("[Aa]rchon")         or txtR:find("[Aa]rchon")) then
                    if lL then lL:SetText("") end
                    if lR then lR:SetText("") end
                end
            end
        end)
    end
end
