----------------------------------------------------------------------
-- VoidScout TrashDiscovery
--
-- Auto-populates trash mob casts from observed UNIT_SPELLCAST_START
-- events on enemy nameplates inside M+ dungeons. The seed config in
-- MechanicConfigs.TRASH_MECHANICS is empty by design — this module
-- builds the catalog one run at a time, persists to SavedVariables,
-- and uploads aggregates so the server can derive consensus across
-- many players.
--
-- WHY NOT CLEU: COMBAT_LOG_EVENT_UNFILTERED is BANNED in 12.0.5 — it
-- propagates secret-value taint from enemy GUIDs/spell IDs through any
-- field access. UNIT_SPELLCAST_START on nameplate units is the same
-- data without the taint.
--
-- WHY NOT JES: JES (JournalEncounterSection) only covers BOSS abilities.
-- Trash casts aren't in DBC. Observed-cast discovery is the only path.
----------------------------------------------------------------------

VoidScout = VoidScout or {}
local mod = {}
VoidScout.TrashDiscovery = mod

-- Static lookup of the 8 Midnight S1 dungeon mapIDs
local M_PLUS_MAPS = {
    [658]=true, [1209]=true, [1753]=true, [2526]=true,
    [2805]=true, [2811]=true, [2874]=true, [2915]=true,
}

local function in_mplus_instance()
    if not IsInInstance then return false end
    local _, instanceType, difficultyID = IsInInstance()
    if instanceType ~= "party" then return false end
    -- difficultyID 8 = Mythic Keystone in 12.0.5; sometimes 23 for Mythic-non-keystone
    return difficultyID == 8 or difficultyID == 23
end

local function current_map()
    if not C_Map or not C_Map.GetBestMapForUnit then return 0 end
    return C_Map.GetBestMapForUnit("player") or 0
end

local function ensure_db()
    VoidScoutDB = VoidScoutDB or {}
    VoidScoutDB.trash_discovery = VoidScoutDB.trash_discovery or {}
    return VoidScoutDB.trash_discovery
end

-- Record an observed enemy cast keyed by mapID + spellID.
local function record_cast(map_id, spell_id, spell_name, npc_id, npc_name)
    if not map_id or not spell_id or spell_id == 0 then return end
    local db = ensure_db()
    local map = db[map_id]
    if not map then map = {}; db[map_id] = map end
    local entry = map[spell_id]
    if not entry then
        entry = {
            name = spell_name or "?",
            npc_ids = {},
            count = 0,
            interrupts = 0,
            first_seen = time(),
        }
        map[spell_id] = entry
    end
    entry.count = entry.count + 1
    entry.last_seen = time()
    if npc_id and npc_name then
        entry.npc_ids[npc_id] = npc_name
    end
end

local function npc_id_from_guid(guid)
    if not guid then return nil end
    -- Standard Blizzard GUID format: "Creature-0-0-0-0-NPCID-..."
    local kind, _, _, _, _, npc_id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then
        return tonumber(npc_id)
    end
    return nil
end

-- Active hostile casts keyed by castGUID. Lets UNIT_SPELLCAST_INTERRUPTED
-- (whose spellID arg is taint-poisoned for enemies) recover the clean
-- spellID captured at START time via UnitCastingInfo.
local active_casts = {}  -- [castGUID] = { spell_id, map_id, started_at }

-- castGUID safety: party-member and friendly events can carry secret
-- castGUIDs in 12.0.5 (taint propagates). Using a tainted value as a
-- table key throws "attempted to perform indexed assignment on a table
-- that cannot be indexed with secret keys". Always issecretvalue-check
-- before touching active_casts.
local function is_safe_castguid(cg)
    if not cg then return false end
    if issecretvalue and issecretvalue(cg) then return false end
    return true
end

-- Stale castGUIDs are dropped after 60s — protects against zone changes
-- and missed STOP events.
local function prune_active_casts()
    local now = GetTime()
    for cg, info in pairs(active_casts) do
        if (now - info.started_at) > 60 then
            active_casts[cg] = nil
        end
    end
end

-- Hook: UNIT_SPELLCAST_START on hostile nameplate units inside M+.
local function on_unit_cast_start(unit, castGUID)
    if not unit or not unit:find("nameplate") then return end
    if not UnitCanAttack("player", unit) then return end
    mod._stats.events_seen_start = mod._stats.events_seen_start + 1
    if not in_mplus_instance() then
        mod._stats.last_rejection_reason = "not in M+"
        return
    end

    local name, _, _, _, _, _, _, _, _, spell_id = UnitCastingInfo(unit)
    if not spell_id then
        mod._stats.last_rejection_reason = "spell_id nil from UnitCastingInfo"
        return
    end
    if issecretvalue and issecretvalue(spell_id) then
        mod._stats.last_rejection_reason = "spell_id is secret"
        return
    end
    local guid = UnitGUID(unit)
    local npc_id = npc_id_from_guid(guid)
    -- UnitName can return secret string in instances. Wrap defensively.
    local ok, npc_name = pcall(UnitName, unit)
    if not ok then npc_name = nil end
    local map_id = current_map()
    record_cast(map_id, spell_id, name, npc_id, npc_name)
    mod._stats.events_recorded = mod._stats.events_recorded + 1
    mod._stats.last_recorded_at = time()
    mod._stats.last_recorded_spell = (name or "?") .. " (" .. spell_id .. ")"

    if is_safe_castguid(castGUID) then
        active_casts[castGUID] = {
            spell_id = spell_id,
            map_id = map_id,
            started_at = GetTime(),
        }
    end
end

-- Hook: UNIT_SPELLCAST_INTERRUPTED on hostile nameplate units. Args' spellID
-- is taint-poisoned for enemies in instances — we MUST look up the clean
-- spell_id via our active_casts table keyed by castGUID.
local function on_unit_cast_interrupted(unit, castGUID)
    if not unit or not unit:find("nameplate") then return end
    if not UnitCanAttack("player", unit) then return end
    if not is_safe_castguid(castGUID) then return end
    local info = active_casts[castGUID]
    if not info then return end
    local db = ensure_db()
    local map = db[info.map_id]
    local entry = map and map[info.spell_id]
    if entry then
        entry.interrupts = (entry.interrupts or 0) + 1
        mod._stats.events_interrupted = mod._stats.events_interrupted + 1
    end
    active_casts[castGUID] = nil
end

local function on_unit_cast_finished(unit, castGUID)
    -- Only clean up castGUIDs we actually registered (hostile nameplates).
    -- Party/friendly STOP events fire constantly and their castGUIDs may
    -- be secret — never index our table with one.
    if not unit or not unit:find("nameplate") then return end
    if not is_safe_castguid(castGUID) then return end
    active_casts[castGUID] = nil
end

-- Public: snapshot of the discovery DB. UI can render this for the
-- player to review what got picked up.
function mod:GetSummary(map_id)
    local db = ensure_db()
    local map = db[map_id]
    if not map then return {} end
    local out = {}
    for sid, entry in pairs(map) do
        out[#out + 1] = {
            spell_id = sid,
            name = entry.name,
            count = entry.count,
            interrupts = entry.interrupts,
            npc_count = (function()
                local n = 0
                for _ in pairs(entry.npc_ids or {}) do n = n + 1 end
                return n
            end)(),
        }
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

-- Public: dump candidate trash mechanics for a map, sorted by cast
-- frequency, for human review before promoting into MechanicConfigs.
function mod:DumpCandidates(map_id, min_count)
    min_count = min_count or 3
    local rows = self:GetSummary(map_id)
    local lines = {}
    lines[#lines + 1] = string.format("Trash discovery for map %d (>= %d casts):", map_id, min_count)
    for _, r in ipairs(rows) do
        if r.count >= min_count then
            local rate = r.count > 0 and (r.interrupts / r.count * 100) or 0
            local tier
            if rate >= 80 then tier = "CRITICAL"
            elseif rate >= 50 then tier = "HIGH"
            elseif rate >= 25 then tier = "MED"
            else tier = "ignore" end
            lines[#lines + 1] = string.format(
                "  spell %d  '%s'  casts=%d kicks=%d rate=%.0f%%  %s  npcs=%d",
                r.spell_id, r.name, r.count, r.interrupts, rate, tier, r.npc_count
            )
        end
    end
    return table.concat(lines, "\n")
end

-- Diagnostic counters. Tally even when in_mplus_instance() rejects, so
-- we can tell "events not firing" from "events firing but gated out".
mod._stats = {
    events_seen_start  = 0,  -- UNIT_SPELLCAST_START on hostile nameplate (after unit/attack filter)
    events_recorded    = 0,  -- after in_mplus_instance() passed → record_cast called
    events_interrupted = 0,
    last_recorded_at   = 0,
    last_recorded_spell = nil,
    last_rejection_reason = nil,
}

function mod:Status()
    local _, itype, diffID = IsInInstance and IsInInstance() or "", "?", "?"
    local mp_ok = in_mplus_instance()
    local map_id = current_map()
    local db = ensure_db()
    local total_spells, total_casts = 0, 0
    for _, m in pairs(db) do
        for _, e in pairs(m) do
            total_spells = total_spells + 1
            total_casts = total_casts + (e.count or 0)
        end
    end
    print("|cff00c7ffVoidScout TrashDiscovery|r")
    print(("  Initialized:        %s"):format(tostring(mod._initialized or false)))
    print(("  Instance type:      %s (difficulty %s)"):format(tostring(itype), tostring(diffID)))
    print(("  In M+:              %s"):format(tostring(mp_ok)))
    print(("  Current mapID:      %s"):format(tostring(map_id)))
    print(("  Hostile casts seen: %d (passed unit/attack filter)"):format(mod._stats.events_seen_start))
    print(("  Casts recorded:     %d (passed M+ gate)"):format(mod._stats.events_recorded))
    print(("  Interrupts tracked: %d"):format(mod._stats.events_interrupted))
    if mod._stats.last_recorded_spell then
        print(("  Last recorded:      %s (%ds ago)"):format(
            mod._stats.last_recorded_spell,
            time() - (mod._stats.last_recorded_at or 0)))
    end
    if mod._stats.last_rejection_reason then
        print(("  Last rejection:     %s"):format(mod._stats.last_rejection_reason))
    end
    print(("  DB: %d spells across %d maps (%d total casts)"):format(
        total_spells, (function() local n = 0; for _ in pairs(db) do n = n + 1 end; return n end)(), total_casts))
end

function mod:Init()
    if mod._initialized then return end
    mod._initialized = true
    local f = CreateFrame("Frame", "VoidScoutTrashDiscoveryFrame")
    f:RegisterEvent("UNIT_SPELLCAST_START")
    f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    f:RegisterEvent("UNIT_SPELLCAST_STOP")
    f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    f:RegisterEvent("UNIT_SPELLCAST_FAILED")
    f:SetScript("OnEvent", function(_, event, unit, castGUID)
        if event == "UNIT_SPELLCAST_START" then
            on_unit_cast_start(unit, castGUID)
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            on_unit_cast_interrupted(unit, castGUID)
        else
            on_unit_cast_finished(unit, castGUID)
        end
    end)
    -- Prune stale castGUIDs every 30s.
    f.prune_at = GetTime() + 30
    f:SetScript("OnUpdate", function(self, elapsed)
        if GetTime() >= self.prune_at then
            prune_active_casts()
            self.prune_at = GetTime() + 30
        end
    end)
end

----------------------------------------------------------------------
-- Priority-candidate popup
--
-- Reads VoidScoutDB.trash_discovery across all discovered maps, computes
-- interrupt rate per spell, emits paste-ready Lua entries for spells
-- meeting the inclusion thresholds:
--   CRITICAL: rate >= 80% AND casts >= 5
--   HIGH:     rate >= 50% AND casts >= 5
-- Below those = not enough data or not a priority kick. Skipped.
--
-- Output is rendered into an EditBox the user can Ctrl+A / Ctrl+C and
-- paste into VoidRaidTools/Modules/KickRotation.lua PRIORITY_INTERRUPTS.
----------------------------------------------------------------------

local MAP_NAMES = {
    [658]  = "Pit of Saron",
    [1209] = "Skyreach",
    [1753] = "Algeth'ar Academy",
    [2526] = "Magisters' Terrace",
    [2805] = "Maisara Caverns",
    [2811] = "Windrunner Spire",
    [2874] = "Nexus-Point Xenas",
    [2915] = "Seat of the Triumvirate",
}

local function build_priority_text(min_casts)
    min_casts = min_casts or 5
    local db = ensure_db()
    local lines = {
        "-- Generated by VoidScout TrashDiscovery on " .. date("%Y-%m-%d %H:%M"),
        "-- Paste into VoidRaidTools/Modules/KickRotation.lua PRIORITY_INTERRUPTS.",
        "-- Inclusion: rate>=50% AND casts>=" .. min_casts,
        "",
    }
    local maps_sorted = {}
    for mid in pairs(db) do table.insert(maps_sorted, mid) end
    table.sort(maps_sorted, function(a, b)
        return (MAP_NAMES[a] or tostring(a)) < (MAP_NAMES[b] or tostring(b))
    end)
    local total_emitted = 0
    for _, mid in ipairs(maps_sorted) do
        local rows = mod:GetSummary(mid)
        local section_emitted = 0
        local buf = { "    -- M+: " .. (MAP_NAMES[mid] or ("Map " .. mid)) }
        for _, r in ipairs(rows) do
            if r.count >= min_casts then
                local rate = r.count > 0 and (r.interrupts / r.count * 100) or 0
                local tier = nil
                if rate >= 80 then tier = "CRITICAL"
                elseif rate >= 50 then tier = "HIGH" end
                if tier then
                    local nm = (r.name or "?"):gsub("\"", "'")
                    if #nm > 28 then nm = nm:sub(1, 28) end
                    buf[#buf + 1] = string.format(
                        "    [%d] = { name = \"%s\", priority = \"%s\" },  -- rate=%d%% n=%d",
                        r.spell_id, nm, tier, rate, r.count
                    )
                    section_emitted = section_emitted + 1
                end
            end
        end
        if section_emitted > 0 then
            for _, l in ipairs(buf) do lines[#lines + 1] = l end
            lines[#lines + 1] = ""
            total_emitted = total_emitted + section_emitted
        end
    end
    if total_emitted == 0 then
        lines[#lines + 1] = "-- No spells meet thresholds yet."
        lines[#lines + 1] = "-- Run more keys then reopen this popup."
    end
    return table.concat(lines, "\n"), total_emitted
end

local popup
local function build_popup()
    if popup then return popup end
    popup = CreateFrame("Frame", "VoidScoutPriorityPopup", UIParent, "BasicFrameTemplate")
    popup:SetSize(640, 460)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("DIALOG")
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    popup.TitleText:SetText("VoidScout — Priority Interrupt Candidates")

    local hint = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -28)
    hint:SetText("Click in the box, Ctrl+A, Ctrl+C, then paste into KickRotation.lua")
    hint:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, popup, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -52)
    scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -32, 38)
    scroll.CharCount:Hide()
    scroll.EditBox:SetFontObject("GameFontHighlight")
    scroll.EditBox:SetMaxLetters(50000)
    scroll.EditBox:SetAutoFocus(false)
    popup._edit = scroll.EditBox

    local refresh = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    refresh:SetSize(120, 22)
    refresh:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 12, 10)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function() mod:ShowPriorityPopup() end)

    local close = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    close:SetSize(100, 22)
    close:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -12, 10)
    close:SetText("Close")
    close:SetScript("OnClick", function() popup:Hide() end)

    local status = popup:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    status:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
    popup._status = status

    return popup
end

function mod:ShowPriorityPopup()
    build_popup()
    local txt, n = build_priority_text(5)
    popup._edit:SetText(txt)
    popup._edit:HighlightText(0, 0)
    popup._status:SetText(string.format("%d spell(s) meeting threshold (rate>=50%% AND casts>=5)", n))
    popup:Show()
end

-- Slash dump (silent fallback per UX rule)
SLASH_VOIDSCOUTTRASH1 = "/vstrash"
SlashCmdList["VOIDSCOUTTRASH"] = function(arg)
    arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "status" then
        mod:Status()
        return
    end
    local map_id = tonumber(arg)
    if map_id then
        print(mod:DumpCandidates(map_id, 3))
    else
        mod:ShowPriorityPopup()
    end
end
