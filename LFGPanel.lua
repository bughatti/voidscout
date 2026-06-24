----------------------------------------------------------------------
-- VoidScout LFGPanel — RaiderIO-style transparent dual profile.
--
-- v0.8.0: Drop applicant list. Two profile panels:
--   * MY panel  : always-visible, shows current player's data
--   * THEIR panel: appears to LEFT of MY when hovering an applicant
-- Transparent tight rows, yellow section headers, like RaiderIO.
----------------------------------------------------------------------

local mod = {}
VoidScout.LFGPanel = mod

local PROFILE_WIDTH    = 230
local PANEL_GAP        = 4
local SECTION_PAD      = 8
local ROW_H            = 14
local HEADER_H         = 16
local DIV_GAP          = 4

-- Class colors fallback
local CLASS_COLORS_FALLBACK = {
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    DEMONHUNTER = { 0.64, 0.19, 0.79 },
    DRUID       = { 1.00, 0.49, 0.04 },
    EVOKER      = { 0.20, 0.58, 0.50 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    MAGE        = { 0.25, 0.78, 0.92 },
    MONK        = { 0.00, 1.00, 0.59 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    PRIEST      = { 1.00, 1.00, 1.00 },
    ROGUE       = { 1.00, 0.96, 0.41 },
    SHAMAN      = { 0.00, 0.44, 0.87 },
    WARLOCK     = { 0.53, 0.53, 0.93 },
    WARRIOR     = { 0.78, 0.61, 0.43 },
}
local function ClassRGB(classFile)
    if not classFile then return { 1, 1, 1 } end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return { c.r, c.g, c.b } end
    return CLASS_COLORS_FALLBACK[classFile] or { 1, 1, 1 }
end

local function ColorForScore(score)
    if not score then return { 0.5, 0.5, 0.5 } end
    if score >= 80 then return { 0.12, 1.00, 0.00 } end
    if score >= 50 then return { 1.00, 1.00, 1.00 } end
    return { 0.62, 0.62, 0.62 }
end

----------------------------------------------------------------------
-- Data sources
----------------------------------------------------------------------
local function ReadRaiderIO(name, realm)
    local rio = _G.RaiderIO
    if not rio or not rio.GetProfile then return nil end
    local ok, profile = pcall(rio.GetProfile, name, realm)
    if not ok or not profile then return nil end
    local mp = profile.mythicKeystoneProfile
    if not mp then return nil end
    return mp.currentScore or mp.previousScore, mp
end

----------------------------------------------------------------------
-- Read WCL parse from VoidScoutDB.wcl cache (populated by tooltip scraper).
-- See InstallArchonScraper() below — it watches GameTooltip after Archon
-- adds its lines and caches the parsed percentile forever per player.
----------------------------------------------------------------------
local function ReadArchonWCL(name, realm)
    if not VoidScoutDB or not VoidScoutDB.wcl then return nil end
    local candidates = { name }
    if realm and realm ~= "" then
        candidates[#candidates+1] = name .. "-" .. realm
        candidates[#candidates+1] = name .. "-" .. realm .. "-US"
    end
    for _, c in ipairs(candidates) do
        if VoidScoutDB.wcl[c] then return VoidScoutDB.wcl[c] end
    end
    return nil
end

----------------------------------------------------------------------
-- Archon tooltip scraper: when GameTooltip shows a unit and Archon has
-- added its parse lines, capture the percentile and cache it forever
-- in VoidScoutDB.wcl[playerName]. Zero API calls, piggybacks on Archon's
-- auto-updating data bundle.
----------------------------------------------------------------------
local function InstallArchonScraper()
    VoidScoutDB.wcl = VoidScoutDB.wcl or {}
    -- Modern API (DF/TWW): TooltipDataProcessor replaces OnTooltipSetUnit.
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall then
        return  -- API not available; silently skip
    end
    if _G._voidscoutArchonScraperInstalled then return end

    local function scrape(tooltip)
        if tooltip ~= GameTooltip then return end
        -- Wrap everything in pcall — UnitGUID can throw with secret-value
        -- errors in tooltip contexts (world cursor, items, etc.)
        pcall(function()
            local _, unit = tooltip:GetUnit()
            if not unit or unit == "" then return end
            -- pcall catches "Secret values..." errors that UnitGUID throws in
            -- tooltip contexts (world cursor, items, etc.) without a real unit.
            local guid_ok, guid = pcall(UnitGUID, unit)
            if not guid_ok or not guid or type(guid) ~= "string"
               or not guid:find("^Player%-") then return end
            local name_ok, n, realm = pcall(UnitName, unit)
            if not name_ok or not n then return end
            local key = (realm and realm ~= "") and (n .. "-" .. realm) or n
            -- Defer one frame so Archon finishes adding its lines
            C_Timer.After(0.1, function()
                pcall(function()
                    if not tooltip:IsShown() then return end
                    for i = 1, tooltip:NumLines() do
                        local lineL = _G["GameTooltipTextLeft"..i]
                        local lineR = _G["GameTooltipTextRight"..i]
                        local txtL = lineL and lineL:GetText() or ""
                        local txtR = lineR and lineR:GetText() or ""
                        local txt = txtL .. " " .. txtR
                        if txt:find("[Bb]est [Aa]verage") or txt:find("[Bb]est [Rr]un") then
                            local pct = tonumber(txt:match("(%d+)%s*[%%]?"))
                            if pct and pct >= 0 and pct <= 100 then
                                VoidScoutDB.wcl[key] = pct
                                break
                            end
                        end
                    end
                end)
            end)
        end)
    end

    local ok = pcall(function()
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, scrape)
    end)
    _G._voidscoutArchonScraperInstalled = ok
end

local function LookupVoidScout(name, realm)
    -- 1) Pull per-fight axis scores from VoidScoutDB.scores (populated by ScoreEngine)
    local scores = VoidScoutDB and VoidScoutDB.scores
    local fights_log = VoidScoutDB and VoidScoutDB.fightLog

    -- Match against BOTH possible name formats (cross-realm + same-realm)
    local candidates = { name }
    if realm and realm ~= "" then
        candidates[#candidates + 1] = name .. "-" .. realm
    end
    local function nameMatches(s)
        for _, c in ipairs(candidates) do
            if s == c then return true end
        end
        return false
    end

    -- 2) Merge live + historical fight records.
    -- Live scores in VoidScoutDB.scores (this session and persistent) +
    -- backfill from VoidScoutHistory.lua (Python-parsed disk logs).
    -- Same player may appear under different name formats:
    --   Vede           (bare, live)
    --   Vede-Elune     (with realm)
    --   Vede-Elune-US  (with realm+region, history format)
    local extra = {}
    if realm and realm ~= "" then
        extra[#extra + 1] = name .. "-" .. realm .. "-US"
    end
    local all_candidates = {}
    for _, c in ipairs(candidates) do all_candidates[#all_candidates+1] = c end
    for _, c in ipairs(extra) do all_candidates[#all_candidates+1] = c end

    -- Only merge live recordings — backfill (VoidScoutHistory) is no longer
    -- read because the historical backfill used the pre-v0.18 binary Survival
    -- scoring. Live recordings use the new time-based + mass-wipe logic and
    -- match what the server (api.voidscout.io) aggregates. Single source of
    -- truth: VoidScoutDB.scores written by ScoreEngine.
    local merged_fights = {}
    local seen_live, seen_hist = 0, 0
    if scores then
        for _, c in ipairs(all_candidates) do
            if scores[c] and scores[c].fights then
                for _, f in ipairs(scores[c].fights) do
                    table.insert(merged_fights, f); seen_live = seen_live + 1
                end
            end
        end
    end
    local rec = (#merged_fights > 0) and { fights = merged_fights } or nil

    -- 3) Compute Commitment from FightRecorder roster log
    local commitment = nil
    local pugs_seen = 0
    if fights_log and #fights_log > 0 then
        local pug_totals, pug_stayed = {}, {}
        for _, f in ipairs(fights_log) do
            local pug = f.pug_id or "_no_pug"
            pug_totals[pug] = (pug_totals[pug] or 0) + 1
            if f.roster then
                for _, n in ipairs(f.roster) do
                    if nameMatches(n) then
                        pug_stayed[pug] = (pug_stayed[pug] or 0) + 1
                        break
                    end
                end
            end
        end
        local sum, n = 0, 0
        for pug, stayed in pairs(pug_stayed) do
            sum = sum + (stayed / (pug_totals[pug] or 1)); n = n + 1
        end
        if n > 0 then
            commitment = math.floor(sum / n * 100)
            pugs_seen = n
        end
    end

    -- 4) Aggregate per-axis lifetime averages from rec.fights.
    -- Only count the 8 modern axes — legacy axes (Composure, Output, Tempo,
    -- Sync, Resilience from pre-v0.15 fights) would skew the average and
    -- diverge from server-side scoring. Server uses the same filter.
    local MODERN_AXES = {
        Damage=true, Interrupts=true, Dispels=true, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    }

    -- CURRENT-TIER FILTER (mirrors server util_aggregator.CURRENT_TIER_ENCOUNTERS).
    -- Without this, legacy raids (Fyrakk/Tindral/etc.) you did for achievements
    -- pad your local score. Server's util_score = 71; local panel would
    -- otherwise show 77. Keep in sync with util_aggregator.py.
    -- Verified DungeonEncounter IDs (Wago.tools DBC dump 12.0.5.67602).
    -- MUST stay in sync with util_aggregator.CURRENT_TIER_ENCOUNTERS.
    local CURRENT_TIER = {
        -- Midnight S1 raids
        [3176]=1, [3177]=1, [3178]=1, [3179]=1, [3180]=1, [3181]=1,  -- Voidspire
        [3306]=1,                                                      -- Dreamrift
        [3182]=1, [3183]=1,                                            -- MQD
        -- Midnight S1 M+ dungeons
        [2562]=1, [2563]=1, [2564]=1, [2565]=1,  -- Algeth'ar Academy (map 2526)
        [1894]=1, [1895]=1, [1897]=1, [1898]=1,  -- Magisters' Terrace (map 585)
        [3212]=1, [3213]=1, [3214]=1,            -- Maisara Caverns (map 2874)
        [3328]=1, [3332]=1, [3333]=1,            -- Nexus-Point Xenas (map 2915)
        [1999]=1, [2000]=1, [2001]=1,            -- Pit of Saron (map 658)
        [2065]=1, [2066]=1, [2067]=1, [2068]=1,  -- Seat of the Triumvirate (map 1753)
        [1698]=1, [1699]=1, [1700]=1, [1701]=1,  -- Skyreach (map 1209)
        [3056]=1, [3057]=1, [3058]=1, [3059]=1,  -- Windrunner Spire (map 2805)
        [3071]=1, [3072]=1, [3073]=1, [3074]=1,  -- Map 2811 (Arcanotron/Seranel/Gemellus/Degentrius)
    }

    local axes = { Damage=nil, Interrupts=nil, Dispels=nil, Avoidance=nil, Activity=nil, Survival=nil, Teamwork=nil }
    local axis_sum = {}
    local fights_seen, mplus_fights_seen, raid_fights_seen = 0, 0, 0
    if rec and rec.fights then
        for _, f in ipairs(rec.fights) do
            local in_tier_boss = CURRENT_TIER[f.encounter_id or 0]
            -- Two ways a fight counts toward M+ pulls:
            --   A) a CURRENT_TIER boss kill (encounter_id in tier table)
            --   B) a trash pull (encounter_id=0) with mode="mplus" — these
            --      are legitimate M+ activity (40-60% of run time).
            local is_mplus_trash = (f.mode == "mplus") and ((f.encounter_id or 0) == 0)
            local counts = in_tier_boss or is_mplus_trash
            -- Raid fights count toward raid_fights_seen but NOT M+.
            if f.mode == "raid" and in_tier_boss then
                raid_fights_seen = raid_fights_seen + 1
            end
            if counts then
                fights_seen = fights_seen + 1
                if f.mode == "mplus" or in_tier_boss then
                    mplus_fights_seen = mplus_fights_seen + 1
                end
                for k, v in pairs(f.axes or {}) do
                    if MODERN_AXES[k] and type(v) == "number" then
                        axis_sum[k] = (axis_sum[k] or { sum = 0, n = 0 })
                        axis_sum[k].sum = axis_sum[k].sum + v
                        axis_sum[k].n   = axis_sum[k].n + 1
                    end
                end
            end
        end
        for k, s in pairs(axis_sum) do
            if s.n > 0 then axes[k] = math.floor(s.sum / s.n + 0.5) end
        end
    end

    if fights_seen == 0 and not commitment then
        return nil  -- no data at all
    end

    -- 5) Overall = mean of non-nil SCORED axes. Commitment is shown as
    -- its own headline number but EXCLUDED from the overall average —
    -- matches server-side util_aggregator. Why: Commitment is a trust
    -- signal (do you stay through wipes?) separate from performance, so
    -- including it in the average diluted both signals.
    local overall_sum, overall_n = 0, 0
    for _, v in pairs(axes) do if v then overall_sum = overall_sum + v; overall_n = overall_n + 1 end end
    local vs_overall = (overall_n > 0) and math.floor(overall_sum / overall_n + 0.5) or nil

    return {
        commitment        = commitment,
        fights_seen       = fights_seen,
        mplus_fights_seen = mplus_fights_seen,
        raid_fights_seen  = raid_fights_seen,
        pugs_seen         = pugs_seen,
        axes              = axes,
        vs_overall        = vs_overall,
        seen_live         = seen_live,
        seen_hist         = seen_hist,
    }
end

----------------------------------------------------------------------
-- Build the current player's profile
----------------------------------------------------------------------
local function GetMyProfile()
    local name = UnitName("player")
    local realm = GetRealmName()
    local _, classFile = UnitClass("player")
    local specIdx = GetSpecialization()
    local specName = "—"
    if specIdx then
        local _, sn = GetSpecializationInfo(specIdx)
        if sn then specName = sn end
    end
    local ilvl = math.floor((select(1, GetAverageItemLevel())) or 0)

    -- Active declared label from LabelPicker
    local declared
    if VoidScoutCharDB.label then
        local roleCode = ({TANK="T", HEALER="H", DPS="D"})[VoidScoutCharDB.label.role] or "?"
        local subs = {}
        for _, k in ipairs({"boss_dps","add_duty","kicks","soaks","rescues","dispels","utility"}) do
            if VoidScoutCharDB.label.subcats and VoidScoutCharDB.label.subcats[k] then
                subs[#subs + 1] = ({boss_dps="B",add_duty="A",kicks="K",soaks="S",rescues="R",dispels="Dp",utility="U"})[k]
            end
        end
        declared = (#subs > 0) and (roleCode .. "+" .. table.concat(subs, "+")) or roleCode
    end

    local vs = LookupVoidScout(name, realm)
    local rio = ReadRaiderIO(name, realm)
    local wcl = ReadArchonWCL(name, realm)

    -- Override local-compute scores with bundle's canonical values when
    -- present. The bundle is the single source of truth (matches website,
    -- tooltip, leaderboard). Local compute drifted from server by a few
    -- points because of MIN_SAMPLE_AXIS handling — bundle eliminates that.
    -- Also pull per-mode scores (raid/M+) that local compute didn't have.
    local self_bundle
    if VoidScout.PlayerScan and VoidScout.PlayerScan.GetBundled then
        local norm = VoidScout.PlayerScan.Normalize and
            VoidScout.PlayerScan.Normalize(name, realm)
        if norm and norm.slug then
            self_bundle = VoidScout.PlayerScan:GetBundled(norm.slug)
        end
    end
    if self_bundle then
        vs = vs or {}
        if self_bundle.us  then vs.vs_overall  = self_bundle.us  end
        if self_bundle.ss  then vs.fights_seen = self_bundle.ss  end
        -- New: per-mode scores (raid + M+)
        vs.vs_raid_overall  = self_bundle.usr
        vs.vs_raid_sample   = self_bundle.usrs
        vs.vs_mplus_overall = self_bundle.usm
        vs.vs_mplus_sample  = self_bundle.usms
        -- Axes from bundle (overrides local-computed axes)
        if self_bundle.ua then
            vs.axes = vs.axes or {}
            for k, v in pairs(self_bundle.ua) do vs.axes[k] = v end
        end
    end

    -- PlayerScan cache (CE/AOTC/KSH badges + cross-source enrichment)
    local badges, scan, raid_progress
    if VoidScout.PlayerScan then
        scan          = VoidScout.PlayerScan:GetByName(name, realm)
        badges        = VoidScout.PlayerScan:GetBadges(name, realm)
        raid_progress = VoidScout.PlayerScan:GetRaidProgress(name, realm)
    end

    return {
        name = name, realm = realm, class = classFile, spec = specName, ilvl = ilvl,
        vs = vs, declared = declared, inferred = nil,
        rio = rio, wcl = wcl,
        scan = scan, badges = badges, raid_progress = raid_progress,
        is_preview = false,
    }
end

----------------------------------------------------------------------
-- Mock data for /vs preview
----------------------------------------------------------------------
local function MockApplicant(idx)
    local samples = {
        { name = "Telepoof",   realm = "Stormrage",    class = "MAGE",        spec = "Frost",    ilvl = 291,
          vs = { vs_overall = 88, commitment = 100, axes = {Damage=95, Interrupts=70, Dispels=nil, Avoidance=88, Activity=80, Survival=100, Teamwork=78}},
          declared = "D",     inferred = "PURE BOSS",
          rio = 3120, wcl = 95, archon = 3027, best_key = 14,
          raid_progress = {
              Voidspire = { N = 6, H = 6, M = ">=1" },
              Dreamrift = { N = 1, H = 1, M = 1 },
              MQD       = { N = 2, H = 2, M = ">=1" },
              parse_avg = 95,
          },
          badges = { {label="CE Voidspire",kind="ce"}, {label="CE Dreamrift",kind="ce"}, {label="CE MQD",kind="ce"}, {label="KS Legend",kind="key"} } },
        { name = "Aurvyn",     realm = "Trollbane",    class = "PALADIN",     spec = "Holy",     ilvl = 285,
          vs = { vs_overall = 72, commitment = 88, axes = {Damage=40, Interrupts=nil, Dispels=90, Avoidance=85, Activity=70, Survival=100, Teamwork=82}},
          declared = "H",     inferred = "HEAL",
          rio = 2680, wcl = 76,
          badges = { {label="AOTC Voidspire",kind="aotc"}, {label="KS Hero",kind="key"} } },
        { name = "Boomboompow",realm = "Stormreaver",  class = "WARRIOR",     spec = "Protection", ilvl = 290,
          vs = { vs_overall = 65, commitment = 45, axes = {Damage=50, Interrupts=60, Dispels=nil, Avoidance=70, Activity=55, Survival=80, Teamwork=68}},
          declared = "T",     inferred = "TANK",
          rio = nil,          wcl = nil,
          badges = { {label="AOTC Voidspire",kind="aotc"} } },
        { name = "Dudubull",   realm = "Aegwynn",      class = "DRUID",       spec = "Restoration", ilvl = 278,
          vs = nil,
          declared = "H",     inferred = nil,
          rio = 2200, wcl = 45,
          badges = nil },
    }
    return samples[((idx - 1) % #samples) + 1]
end

----------------------------------------------------------------------
-- Profile panel widget — transparent, dense, RaiderIO-style.
-- Returns a frame with :SetData(profile) method.
----------------------------------------------------------------------
local function CreateProfilePanel(name, parent)
    local p = CreateFrame("Frame", name, parent, "BackdropTemplate")
    p:SetWidth(PROFILE_WIDTH)
    p:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    p:SetBackdropColor(0, 0, 0, 0.75)        -- transparent dark
    p:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)  -- subtle grey border

    -- Header: name (class colored) right under the top edge
    p.name = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.name:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, -SECTION_PAD)

    p.realm = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.realm:SetPoint("LEFT", p.name, "RIGHT", 4, 0)

    p.meta = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.meta:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -2)

    p.divTop = p:CreateTexture(nil, "ARTWORK")
    p.divTop:SetColorTexture(0.7, 0.6, 0.0, 0.6)
    p.divTop:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, -42)
    p.divTop:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, -42)
    p.divTop:SetHeight(1)

    -- ── VoidScout section ──
    p.vsHdr = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.vsHdr:SetText("VoidScout Score")
    p.vsHdr:SetTextColor(1, 0.82, 0)
    p.vsHdr:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, -50)

    p.vsScore = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.vsScore:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, -50)
    p.vsScore:SetJustifyH("RIGHT")

    p.vsSub = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.vsSub:SetText("Commitment")
    p.vsSub:SetPoint("TOPLEFT", p.vsHdr, "BOTTOMLEFT", 0, -2)

    p.vsSubVal = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.vsSubVal:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, -68)
    p.vsSubVal:SetJustifyH("RIGHT")

    p.declHdr = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.declHdr:SetText("Declared / Inferred")
    p.declHdr:SetPoint("TOPLEFT", p.vsSub, "BOTTOMLEFT", 0, -2)

    p.declVal = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.declVal:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, -84)
    p.declVal:SetJustifyH("RIGHT")

    p.divAxes = p:CreateTexture(nil, "ARTWORK")
    p.divAxes:SetColorTexture(0.4, 0.4, 0.4, 0.5)
    p.divAxes:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, -100)
    p.divAxes:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, -100)
    p.divAxes:SetHeight(1)

    -- 7 axis rows
    local AXES = {"Damage", "Interrupts", "Dispels", "Avoidance", "Activity", "Survival", "Teamwork"}
    p.axes = {}
    local rowY = -106
    for _, axisName in ipairs(AXES) do
        local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetText(axisName)
        lbl:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD + 4, rowY)

        local val = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        val:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, rowY)
        val:SetJustifyH("RIGHT")

        p.axes[axisName] = { lbl = lbl, val = val }
        rowY = rowY - ROW_H
    end

    p.divExt = p:CreateTexture(nil, "ARTWORK")
    p.divExt:SetColorTexture(0.7, 0.6, 0.0, 0.6)
    p.divExt:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, rowY - 4)
    p.divExt:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, rowY - 4)
    p.divExt:SetHeight(1)

    -- WCL section (per-raid N/H/M progress + parse avg)
    p.wclHdr = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.wclHdr:SetText("Raid Progress")
    p.wclHdr:SetTextColor(1, 0.82, 0)
    p.wclHdr:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, rowY - 14)

    -- Raid-only VoidScout score (right side of header). Lets a player who
    -- specializes in raid be judged on raid-only performance, not diluted
    -- by sparse M+ data (or vice versa).
    p.vsRaidScore = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.vsRaidScore:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, rowY - 14)
    p.vsRaidScore:SetJustifyH("RIGHT")

    -- 3 raid rows + Midnight overall + parse avg. Each row: raid name on
    -- far left, N / H / M columns at FIXED x offsets so all align.
    -- "Midnight" is the zone-wide aggregate from Archon (real data).
    local WCL_RAIDS = { "Voidspire", "Dreamrift", "MQD", "Midnight" }
    local COL_N_X = SECTION_PAD + 78         -- "N 6/6" left edge
    local COL_H_X = SECTION_PAD + 118        -- "H 6/6"
    local COL_M_X = SECTION_PAD + 158        -- "M >=1/6"
    p.wclRows = {}
    local wclY = rowY - 32
    for _, raidName in ipairs(WCL_RAIDS) do
        local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetText(raidName)
        lbl:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD + 4, wclY)
        local valN = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valN:SetPoint("TOPLEFT", p, "TOPLEFT", COL_N_X, wclY)
        valN:SetJustifyH("LEFT")
        local valH = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valH:SetPoint("TOPLEFT", p, "TOPLEFT", COL_H_X, wclY)
        valH:SetJustifyH("LEFT")
        local valM = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valM:SetPoint("TOPLEFT", p, "TOPLEFT", COL_M_X, wclY)
        valM:SetJustifyH("LEFT")
        p.wclRows[raidName] = { lbl = lbl, valN = valN, valH = valH, valM = valM }
        wclY = wclY - 14
    end
    -- Parse Avg row removed (May 29 2026) — we don't pull WCL parse data.
    -- Keep wclParseVal as a hidden no-op fontstring so SetData calls don't error.
    p.wclParseVal = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.wclParseVal:Hide()
    local wclEndY = wclY

    -- Divider between WCL and Dungeons/M+
    p.divMp = p:CreateTexture(nil, "ARTWORK")
    p.divMp:SetColorTexture(0.7, 0.6, 0.0, 0.6)
    p.divMp:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, wclEndY - 4)
    p.divMp:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, wclEndY - 4)
    p.divMp:SetHeight(1)

    -- Dungeons/M+ section
    p.mpHdr = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.mpHdr:SetText("Dungeons/M+")
    p.mpHdr:SetTextColor(1, 0.82, 0)
    p.mpHdr:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, wclEndY - 14)

    -- M+-only VoidScout score (right side of header).
    p.vsMpScore = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.vsMpScore:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, wclEndY - 14)
    p.vsMpScore:SetJustifyH("RIGHT")

    p.rioLbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.rioLbl:SetText("M+ Score")
    p.rioLbl:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD + 4, wclEndY - 32)

    p.rioVal = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.rioVal:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, wclEndY - 32)
    p.rioVal:SetJustifyH("RIGHT")

    p.keyLbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.keyLbl:SetText("Top Keys")
    p.keyLbl:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD + 4, wclEndY - 46)

    p.keyVal = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.keyVal:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, wclEndY - 46)
    p.keyVal:SetJustifyH("RIGHT")
    p.keyVal:SetWordWrap(false)

    -- Divider between Dungeons/M+ and Probability Score
    p.divProb = p:CreateTexture(nil, "ARTWORK")
    p.divProb:SetColorTexture(0.7, 0.6, 0.0, 0.6)
    p.divProb:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, wclEndY - 64)
    p.divProb:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, wclEndY - 64)
    p.divProb:SetHeight(1)

    -- Probability Score section: headline + 4 coaching lines.
    -- Score = chance to time the current LFG-context key+dungeon.
    -- Coaching = top 4 behavioral axes to work on (NO gear coaching per design).
    p.probHdr = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.probHdr:SetText("Probability")
    p.probHdr:SetTextColor(1, 0.82, 0)
    p.probHdr:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, wclEndY - 74)

    p.probScore = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.probScore:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, wclEndY - 74)
    p.probScore:SetJustifyH("RIGHT")
    p.probScore:SetText("-")

    p.probContext = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.probContext:SetPoint("TOPLEFT", p.probHdr, "BOTTOMLEFT", 0, -1)
    p.probContext:SetText("")

    -- 4 coaching rows (axis-derived, behavioral)
    p.probCoach = {}
    local pcY = wclEndY - 108
    for i = 1, 4 do
        local row = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD + 4, pcY)
        row:SetPoint("RIGHT", p, "RIGHT", -SECTION_PAD, 0)
        row:SetJustifyH("LEFT")
        row:SetWordWrap(false)
        row:SetText("")
        p.probCoach[i] = row
        pcY = pcY - 13
    end

    -- Divider between Probability and Achievements
    p.divAch = p:CreateTexture(nil, "ARTWORK")
    p.divAch:SetColorTexture(0.7, 0.6, 0.0, 0.6)
    p.divAch:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, wclEndY - 168)
    p.divAch:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, wclEndY - 168)
    p.divAch:SetHeight(1)

    -- Achievements section (CE/AOTC/KSH from PlayerScan inspect cache)
    p.achHdr = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.achHdr:SetText("Achievements")
    p.achHdr:SetTextColor(1, 0.82, 0)
    p.achHdr:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, wclEndY - 178)

    p.badges = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.badges:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD + 4, wclEndY - 196)
    p.badges:SetPoint("RIGHT", p, "RIGHT", -SECTION_PAD, 0)
    p.badges:SetJustifyH("LEFT")
    p.badges:SetWordWrap(true)
    p.badges:SetText("|cff808080(none captured)|r")

    -- Footer divider — repositioned by SetData when badges expand
    p.divFoot = p:CreateTexture(nil, "ARTWORK")
    p.divFoot:SetColorTexture(0.4, 0.4, 0.4, 0.4)
    p.divFoot:SetPoint("TOPLEFT", p, "TOPLEFT", SECTION_PAD, wclEndY - 224)
    p.divFoot:SetPoint("TOPRIGHT", p, "TOPRIGHT", -SECTION_PAD, wclEndY - 224)
    p.divFoot:SetHeight(1)

    p._baseRowY    = rowY
    p._badgesY     = wclEndY - 196
    p._baselineFoot = wclEndY - 224
    local totalHeight = math.abs(wclEndY - 224) + 14
    p:SetHeight(totalHeight)

    function p:SetData(d)
        if not d then
            self.name:SetText("-")
            self.realm:SetText("")
            self.meta:SetText("")
            self.badges:SetText("")
            self.probScore:SetText("-"); self.probScore:SetTextColor(0.5,0.5,0.5)
            self.probContext:SetText("")
            for i = 1, 4 do self.probCoach[i]:SetText("") end
            self.vsScore:SetText("|cff808080-|r")
            self.vsSubVal:SetText("|cff808080-|r")
            self.declVal:SetText("|cff808080-|r")
            for _, r in pairs(self.axes) do r.val:SetText("-"); r.val:SetTextColor(0.5, 0.5, 0.5) end
            self.rioVal:SetText("-");      self.rioVal:SetTextColor(0.5, 0.5, 0.5)
            self.wclParseVal:SetText("-"); self.wclParseVal:SetTextColor(0.5, 0.5, 0.5)
            self.keyVal:SetText("-");      self.keyVal:SetTextColor(0.5, 0.5, 0.5)
            for _, row in pairs(self.wclRows) do
                row.valN:SetText("|cff707070-|r")
                row.valH:SetText("|cff707070-|r")
                row.valM:SetText("|cff707070-|r")
            end
            return
        end
        local rgb = ClassRGB(d.class)
        self.name:SetText(d.name or "?")
        self.name:SetTextColor(rgb[1], rgb[2], rgb[3])
        self.realm:SetText(d.realm and ("(" .. d.realm .. ")") or "")
        -- ASCII separator (default WoW font in 12.0.5 doesn't render U+2022)
        self.meta:SetText(string.format("%s  -  ilvl %d", d.spec or "?", d.ilvl or 0))


        -- VS headline + commitment (+ sample-data hint)
        local vs_v = d.vs and d.vs.vs_overall
        local com_v = d.vs and d.vs.commitment
        if vs_v then
            local sc = ColorForScore(vs_v)
            local suffix = d.is_preview and " |cff808080(sample)|r" or ""
            self.vsScore:SetText(tostring(math.floor(vs_v)) .. suffix)
            self.vsScore:SetTextColor(sc[1], sc[2], sc[3])
        else
            self.vsScore:SetText("-")
            self.vsScore:SetTextColor(0.5, 0.5, 0.5)
        end
        if com_v then
            local sc = ColorForScore(com_v)
            self.vsSubVal:SetText(tostring(math.floor(com_v)))
            self.vsSubVal:SetTextColor(sc[1], sc[2], sc[3])
        else
            self.vsSubVal:SetText("-")
            self.vsSubVal:SetTextColor(0.5, 0.5, 0.5)
        end

        -- Per-mode VoidScout scores next to section headers
        if self.vsRaidScore then
            local r_v = d.vs and d.vs.vs_raid_overall
            local r_n = d.vs and d.vs.vs_raid_sample
            -- Prefer live local raid count if it's higher than the bundled
            -- value (bundle can be days stale; local is the truth source).
            local r_local = d.vs and d.vs.raid_fights_seen
            if r_local and (not r_n or r_local > r_n) then r_n = r_local end
            if r_v and (not r_n or r_n >= 3) then
                local sc = ColorForScore(r_v)
                local n_str = r_n and (" |cff888888(" .. r_n .. " pulls)|r") or ""
                self.vsRaidScore:SetText(("VS %d%s"):format(r_v, n_str))
                self.vsRaidScore:SetTextColor(sc[1], sc[2], sc[3])
            else
                self.vsRaidScore:SetText("")
            end
        end
        if self.vsMpScore then
            local m_v = d.vs and d.vs.vs_mplus_overall
            local m_n = d.vs and d.vs.vs_mplus_sample
            -- Same live-local override for the M+ pull count
            local m_local = d.vs and d.vs.mplus_fights_seen
            if m_local and (not m_n or m_local > m_n) then m_n = m_local end
            if m_v and (not m_n or m_n >= 3) then
                local sc = ColorForScore(m_v)
                local n_str = m_n and (" |cff888888(" .. m_n .. " pulls)|r") or ""
                self.vsMpScore:SetText(("VS %d%s"):format(m_v, n_str))
                self.vsMpScore:SetTextColor(sc[1], sc[2], sc[3])
            else
                self.vsMpScore:SetText("")
            end
        end

        -- Probability Score (player's own panel):
        -- Default = GENERIC capability score (no dungeon/key shown). But
        -- when the PreflightDetector says we're inside an M+ instance
        -- pre-keystone, switch to specific-run context showing the
        -- dungeon, key level, and group probability alongside our own.
        local preflight = nil
        if VoidScout.PreflightDetector and VoidScout.PreflightDetector.GetPreflight then
            preflight = VoidScout.PreflightDetector:GetPreflight()
        end

        local prob_dungeon_id = preflight and preflight.dungeon_id or nil
        local prob_keylvl     = preflight and preflight.keylevel or 10
        local prob_dname      = preflight and preflight.dungeon_name or nil

        if preflight and prob_dungeon_id and prob_dungeon_id > 0 then
            local ctx_str = ("+%d %s"):format(prob_keylvl, prob_dname)
            if preflight.group_score then
                ctx_str = ctx_str .. ("  |cffa0a0a0Group %d|r"):format(preflight.group_score)
            end
            self.probContext:SetText(ctx_str)
        else
            self.probContext:SetText("")  -- generic capability view
        end

        if VoidScout.TimerScore and d.class and d.spec then
            -- Fold in player's actual axis data so the score moves with play.
            -- Average of axes (Damage..Teamwork) = behavior signal.
            local axes_for_calc = (d.vs and d.vs.axes) or {}
            local axes_sum, axes_n = 0, 0
            for _, ax in ipairs({"Damage","Interrupts","Dispels","Avoidance",
                                 "Activity","Survival","Teamwork"}) do
                local v = axes_for_calc[ax]
                if v then axes_sum = axes_sum + v; axes_n = axes_n + 1 end
            end
            local axes_avg = (axes_n > 0) and (axes_sum / axes_n) or 0
            local pscore, pbd = VoidScout.TimerScore:ScorePlayer(
                d.class, d.spec, d.ilvl or 0, prob_keylvl, prob_dungeon_id,
                { axes_avg = axes_avg }
            )
            if pscore then
                local sc = ColorForScore(pscore)
                self.probScore:SetText(tostring(pscore))
                self.probScore:SetTextColor(sc[1], sc[2], sc[3])
                -- Top 4 coaching lines: pull lowest axes for this role,
                -- exclude gear (user explicitly: everyone knows they need
                -- better gear, don't waste a coaching slot).
                local AXIS_NAMES = {"Damage","Interrupts","Dispels",
                                     "Avoidance","Activity","Survival","Teamwork"}
                local axes = (d.vs and d.vs.axes) or {}
                local pairs_list = {}
                for _, ax in ipairs(AXIS_NAMES) do
                    local v = axes[ax]
                    if v then table.insert(pairs_list, { ax = ax, v = v }) end
                end
                table.sort(pairs_list, function(a, b) return a.v < b.v end)
                -- Coaching templates by role (matches server probability_endpoint.py)
                local function role_of(cls, sp)
                    local tanks = { ["DRUID/Guardian"]=true, ["MONK/Brewmaster"]=true,
                        ["DEATHKNIGHT/Blood"]=true, ["PALADIN/Protection"]=true,
                        ["DEMONHUNTER/Vengeance"]=true, ["WARRIOR/Protection"]=true }
                    local healers = { ["MONK/Mistweaver"]=true, ["SHAMAN/Restoration"]=true,
                        ["PRIEST/Discipline"]=true, ["DRUID/Restoration"]=true,
                        ["PALADIN/Holy"]=true, ["EVOKER/Preservation"]=true,
                        ["PRIEST/Holy"]=true }
                    local k = (cls or "") .. "/" .. (sp or "")
                    if tanks[k] then return "TANK" end
                    if healers[k] then return "HEALER" end
                    return "DPS"
                end
                local role = role_of(d.class, d.spec)
                local TMPL = {
                    Damage = { DPS = "Damage %d - push CDs/trinkets",
                               TANK = "Damage %d - baseline DPS low" },
                    Interrupts = { DPS = "Interrupts %d - missing priority kicks",
                                   TANK = "Interrupts %d - tank kicks crucial",
                                   HEALER = "Interrupts %d - one kick helps" },
                    Dispels = { DPS = "Dispels %d - clear priority debuffs",
                                HEALER = "Dispels %d - magic effects lingering" },
                    Avoidance = { DPS = "Avoidance %d - eating mechanics",
                                  TANK = "Avoidance %d - unnecessary melee damage",
                                  HEALER = "Avoidance %d - hit when should move" },
                    Activity = { DPS = "Activity %d - rotation/global gaps",
                                 TANK = "Activity %d - threat rotation gaps",
                                 HEALER = "Activity %d - pre-HoT before pulls" },
                    Survival = { DPS = "Survival %d - defensives unused",
                                 TANK = "Survival %d - defensive CDs unused",
                                 HEALER = "Survival %d - self-heals unused" },
                    Teamwork = { DPS = "Teamwork %d - external defensives unused",
                                 TANK = "Teamwork %d - taunt/pull discipline",
                                 HEALER = "Teamwork %d - tank externals unused" },
                }
                local n = 0
                for _, p2 in ipairs(pairs_list) do
                    if n >= 4 then break end
                    local tmpl = TMPL[p2.ax] and TMPL[p2.ax][role]
                    if tmpl then
                        n = n + 1
                        local color = ColorForScore(p2.v)
                        local hex = ("|cff%02x%02x%02x"):format(
                            math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255))
                        self.probCoach[n]:SetText(hex .. tmpl:format(math.floor(p2.v)) .. "|r")
                    end
                end
                for i = n + 1, 4 do self.probCoach[i]:SetText("") end
            else
                self.probScore:SetText("-"); self.probScore:SetTextColor(0.5, 0.5, 0.5)
                for i = 1, 4 do self.probCoach[i]:SetText("") end
            end
        else
            self.probScore:SetText("-"); self.probScore:SetTextColor(0.5, 0.5, 0.5)
            for i = 1, 4 do self.probCoach[i]:SetText("") end
        end

        -- Declared / Inferred (ASCII only — default WoW font has poor unicode coverage)
        if d.declared and d.inferred then
            local matchSym = "|cff12ff00ok|r"
            if d.declared:find("%+A") and d.inferred:find("PURE") then
                matchSym = "|cffff4040!|r"
            end
            self.declVal:SetText(d.declared .. " >> " .. d.inferred .. " " .. matchSym)
        elseif d.declared then
            -- Inferred role detection isn't wired yet. Show declared alone
            -- (no "(no data)" suffix — clutter without value).
            self.declVal:SetText(d.declared)
        else
            self.declVal:SetText("|cff808080-|r")
        end

        -- 7 axes
        local AXES = {"Damage", "Interrupts", "Dispels", "Avoidance", "Activity", "Survival", "Teamwork"}
        for _, axisName in ipairs(AXES) do
            local r = self.axes[axisName]
            local v
            if axisName == "Commitment" then v = com_v
            else v = d.vs and d.vs.axes and d.vs.axes[axisName] end
            if v then
                local sc = ColorForScore(v)
                r.val:SetText(tostring(math.floor(v)))
                r.val:SetTextColor(sc[1], sc[2], sc[3])
            else
                r.val:SetText("-")
                r.val:SetTextColor(0.5, 0.5, 0.5)
            end
        end

        -- WCL section: per-raid progress (N/H/M) at fixed column positions
        local function fmtCount(killed, total)
            if not killed then return "|cff707070-|r" end
            if type(killed) == "string" then return killed end
            return tostring(killed) .. "/" .. tostring(total)
        end
        local rp = d.raid_progress or {}
        for raidName, row in pairs(self.wclRows) do
            if raidName == "Midnight" then
                -- Archon zone-wide aggregate: real data, includes parse %
                local arc = rp.archon or {}
                local function archCell(diff)
                    local s = arc[diff]
                    if not s or not s.progress then return "-" end
                    return s.progress .. "/" .. s.total
                end
                row.valN:SetText("N " .. archCell("N"))
                row.valH:SetText("|cffff8000H|r " .. archCell("H"))
                row.valM:SetText("|cffa335eeM|r " .. archCell("M"))
            else
                local r = rp[raidName] or {}
                local total = ({ Voidspire = 6, Dreamrift = 1, MQD = 2 })[raidName] or 0
                row.valN:SetText("N " .. fmtCount(r.N, total))
                row.valH:SetText("|cffff8000H|r " .. fmtCount(r.H, total))
                row.valM:SetText("|cffa335eeM|r " .. fmtCount(r.M, total))
            end
        end
        -- Parse avg priority: Archon real data > tooltip scrape fallback
        local wcl_val = rp.parse_avg or d.wcl or (d.scan and d.scan.scraped_wcl)
        if wcl_val then
            local sc = ColorForScore(wcl_val)
            self.wclParseVal:SetText(tostring(math.floor(wcl_val)) .. "%")
            self.wclParseVal:SetTextColor(sc[1], sc[2], sc[3])
        else
            self.wclParseVal:SetText("-")
            self.wclParseVal:SetTextColor(0.5, 0.5, 0.5)
        end

        -- Dungeons/M+ section
        -- Priority: d.rio (live RIO API call) > scan.rio_score (cached at enrich) > scraped_rio
        local rio_val = d.rio or (d.scan and (d.scan.rio_score or d.scan.scraped_rio))
        if rio_val then
            self.rioVal:SetText(tostring(rio_val))
            self.rioVal:SetTextColor(1, 1, 1)
        else
            self.rioVal:SetText("-")
            self.rioVal:SetTextColor(0.5, 0.5, 0.5)
        end

        -- Top 3 keys: prevent inflation from one lucky carry.
        local top = (d.scan and d.scan.top_keys) or nil
        if type(top) == "table" and top[1] then
            local parts = {}
            for i = 1, 3 do
                local k = top[i]
                if k then table.insert(parts, "+" .. k.level .. " " .. (k.dungeon or "?")) end
            end
            self.keyVal:SetText(table.concat(parts, "  "))
            self.keyVal:SetTextColor(0.4, 1, 0.4)
        else
            -- Fallback to single best key if top_keys hasn't been re-enriched yet
            local key_val = d.best_key or (d.scan and d.scan.best_key_level)
            local key_dungeon = d.best_key_dungeon or (d.scan and d.scan.best_key_dungeon)
            if key_val then
                self.keyVal:SetText("+" .. key_val .. (key_dungeon and (" " .. key_dungeon) or ""))
                self.keyVal:SetTextColor(0.4, 1, 0.4)
            else
                self.keyVal:SetText("-")
                self.keyVal:SetTextColor(0.5, 0.5, 0.5)
            end
        end

        -- Achievements section (CE/AOTC/KSH from PlayerScan inspect cache)
        if d.badges and #d.badges > 0 then
            local parts = {}
            for _, b in ipairs(d.badges) do
                local color = "|cffaaaaaa"
                if     b.kind == "ce"   then color = "|cffffa500"   -- orange (CE)
                elseif b.kind == "aotc" then color = "|cffcccccc"   -- silver (AOTC)
                elseif b.kind == "key"  then color = "|cff40ff80"   -- green (Keystone)
                end
                table.insert(parts, color .. b.label .. "|r")
            end
            self.badges:SetText(table.concat(parts, "   "))
            local badgesH = math.max(14, self.badges:GetStringHeight() + 4)
            self.divFoot:ClearAllPoints()
            self.divFoot:SetPoint("TOPLEFT", self.badges, "BOTTOMLEFT", -4, -8)
            self.divFoot:SetPoint("RIGHT", self, "RIGHT", -SECTION_PAD, 0)
            self:SetHeight(math.abs(self._badgesY) + badgesH + 24)
        else
            self.badges:SetText("|cff808080(none captured yet)|r")
            self.divFoot:ClearAllPoints()
            self.divFoot:SetPoint("TOPLEFT", self, "TOPLEFT", SECTION_PAD, self._baselineFoot)
            self.divFoot:SetPoint("RIGHT", self, "RIGHT", -SECTION_PAD, 0)
            self:SetHeight(math.abs(self._baselineFoot) + 14)
        end

        self._data = d
    end

    return p
end

----------------------------------------------------------------------
-- Module state
----------------------------------------------------------------------
local myPanel, theirPanel, headerCheck = nil, nil, nil

----------------------------------------------------------------------
-- External overlay management
-- Hide RaiderIO's standalone tooltip panels (RaiderIO addon stays
-- ENABLED so we can still read its data via GetProfile API).
----------------------------------------------------------------------
local OVERLAY_CANDIDATES = {
    -- RaiderIO standalone tooltips/profile frames
    "RaiderIO_ProfileTooltip", "RaiderIO_Profile", "RaiderIOProfileFrame",
    "RaiderIO_PvP", "RaiderIOMythicPlusTooltipFrame",
    "RaiderIO_SearchTooltip", "RaiderIOProfileTooltip",
    "RaiderIO_GroupFinderTooltip",
    -- ArchonTooltip (WCL parses)
    "ArchonTooltip", "ArchonTooltipFrame", "ArchonTooltipDB",
    "ArchonTooltipProfileFrame",
}
local function FindExternalOverlays()
    -- Look up frames by exact known names
    local found = {}
    for _, name in ipairs(OVERLAY_CANDIDATES) do
        local f = _G[name]
        if f and f.IsObjectType and f:IsObjectType("Frame") then
            found[#found + 1] = { name = name, frame = f }
        end
    end
    -- Scan global frame namespace for ANY frame named RaiderIO* or Archon*
    for k, v in pairs(_G) do
        if type(k) == "string" and (k:match("^RaiderIO") or k:match("^Archon"))
           and type(v) == "table" then
            local ok = pcall(function() return v:IsObjectType("Frame") end)
            if ok and v.IsObjectType and v:IsObjectType("Frame") then
                local already = false
                for _, item in ipairs(found) do
                    if item.frame == v then already = true; break end
                end
                if not already then
                    found[#found + 1] = { name = k, frame = v }
                end
            end
        end
    end
    return found
end
local function SuppressExternalOverlays()
    if not myPanel or not VoidScoutDB.enabled then return end
    for _, item in ipairs(FindExternalOverlays()) do
        pcall(function() item.frame:Hide() end)
        if not item.frame._voidscoutHidden then
            item.frame:HookScript("OnShow", function(self)
                if VoidScoutDB.enabled then pcall(function() self:Hide() end) end
            end)
            item.frame._voidscoutHidden = true
        end
    end
end

----------------------------------------------------------------------
-- Refresh my panel with current player data
----------------------------------------------------------------------
local DEBUG_REFRESH = false  -- toggle via /vs debug
local function RefreshMyPanel()
    if not myPanel then
        if DEBUG_REFRESH then print("|cffff8080VS RefreshMyPanel: myPanel is nil|r") end
        return
    end
    local p = GetMyProfile()
    if DEBUG_REFRESH then
        print(string.format("|cffffd100VS Refresh:|r name=%s class=%s ilvl=%s vs_overall=%s is_preview=%s",
            tostring(p.name), tostring(p.class), tostring(p.ilvl),
            tostring(p.vs and p.vs.vs_overall), tostring(p.is_preview)))
    end
    myPanel:SetData(p)
end

function mod:SetDebug(on)
    DEBUG_REFRESH = on and true or false
    print("|cffffd100VS:|r debug refresh =", tostring(DEBUG_REFRESH))
end

-- Public refresh handle so external modules (e.g., PreflightDetector)
-- can prompt a panel re-render when context changes (entering an M+
-- instance, group composition changes, etc.).
function mod:Refresh()
    RefreshMyPanel()
end

----------------------------------------------------------------------
-- Show another player's panel to the LEFT of mine
----------------------------------------------------------------------
function mod:ShowOther(data)
    if not theirPanel then return end
    theirPanel:SetData(data)
    theirPanel:Show()
end

function mod:HideOther()
    if theirPanel then theirPanel:Hide() end
end

function mod:Preview(count)
    -- My panel auto-shows on Premade Groups open. /vs preview only
    -- spawns the OTHER panel with mock data for design iteration.
    -- Pass 0 to hide the other panel.
    count = count or 1
    RefreshMyPanel()
    if count > 0 then
        self:ShowOther(MockApplicant(((count - 1) % 4) + 1))
        print("|cffffd100VoidScout:|r preview — mock applicant " .. count .. " (left of yours)")
    else
        self:HideOther()
        print("|cffffd100VoidScout:|r other panel hidden")
    end
end

----------------------------------------------------------------------
-- Diagnostic: show my computed profile + roster format in fightLog
----------------------------------------------------------------------
function mod:Status()
    print("|cffffd100VoidScout status:|r")
    print("  enabled (VoidScoutDB.enabled):", tostring(VoidScoutDB and VoidScoutDB.enabled))
    print("  myPanel created:", myPanel and "yes" or "no")
    if myPanel then
        print("    visible:", myPanel:IsShown() and "yes" or "NO")
        print("    width x height:", myPanel:GetWidth(), "x", myPanel:GetHeight())
        local p, _, _, x, y = myPanel:GetPoint(1)
        print("    anchor point:", p, "offset:", x, y)
    end
    print("  theirPanel created:", theirPanel and "yes" or "no")
    if theirPanel then print("    visible:", theirPanel:IsShown() and "yes" or "no") end
    print("  LFGListFrame exists:", LFGListFrame and "yes" or "no")
    if LFGListFrame then
        print("    LFGListFrame:IsShown:", LFGListFrame:IsShown() and "yes" or "NO")
        print("    LFGListFrame strata:", LFGListFrame:GetFrameStrata())
    end
    print("  PVEFrame exists:", PVEFrame and "yes" or "no")
    if PVEFrame then print("    PVEFrame:IsShown:", PVEFrame:IsShown() and "yes" or "no") end
end

function mod:DiagnoseMe()
    local name = UnitName("player")
    local realm = GetRealmName()
    print("|cffffd100VoidScout diag:|r player =", name, "realm =", realm)
    print("  candidates to match:", name, name .. "-" .. realm)

    local log = (VoidScoutDB and VoidScoutDB.fightLog) or {}
    print("  fightLog entries:", #log)
    if #log == 0 then
        print("  |cffff8080No fights recorded. FightRecorder captures on ENCOUNTER_START+END.|r")
        return
    end

    -- Show last fight with FULL roster dump
    local last = log[#log]
    print(string.format("  Last fight: %s %s (dur %ds)",
        last.encounter_name or "?", last.outcome or "?", math.floor(last.duration_sec or 0)))
    if not last.roster then
        print("    |cffff8080This fight has NO roster field (recorded before v0.4.0?)|r")
    else
        print(string.format("    Roster has %d entries:", #last.roster))
        for i, n in ipairs(last.roster) do
            local marker = ""
            if n == name then marker = "  |cff12ff00<-- MATCH (bare)|r"
            elseif n == name .. "-" .. realm then marker = "  |cff12ff00<-- MATCH (with realm)|r"
            elseif n:find(name, 1, true) then marker = "  |cffffd100<-- PARTIAL match|r" end
            print(string.format("      [%d] %s%s", i, n, marker))
            if i >= 25 then print("      (truncated...)"); break end
        end
    end

    local vs = LookupVoidScout(name, realm)
    if vs then
        print(string.format("  |cff12ff00LookupVoidScout: commitment=%d, fights=%d (live=%d, hist=%d), pugs=%d|r",
            vs.commitment or 0, vs.fights_seen or 0,
            vs.seen_live or 0, vs.seen_hist or 0, vs.pugs_seen or 0))
        if vs.axes then
            local axes_str = string.format("    axes: Damage=%s Interrupts=%s Dispels=%s Avoidance=%s Activity=%s Survival=%s Teamwork=%s",
                tostring(vs.axes.Damage), tostring(vs.axes.Interrupts), tostring(vs.axes.Dispels),
                tostring(vs.axes.Avoidance), tostring(vs.axes.Activity), tostring(vs.axes.Survival),
                tostring(vs.axes.Teamwork))
            print(axes_str)
        end
    else
        print("  |cffff8080LookupVoidScout returned nil.|r")
    end
end

----------------------------------------------------------------------
-- Build the panels (anchored to LFGListFrame)
----------------------------------------------------------------------
local function CreatePanels()
    if myPanel then return myPanel end
    if not LFGListFrame then return nil end

    -- MY panel: anchored to the right of LFGListFrame
    myPanel = CreateProfilePanel("VoidScoutMyPanel", LFGListFrame)
    myPanel:SetPoint("TOPLEFT", LFGListFrame, "TOPRIGHT", PANEL_GAP, 0)
    myPanel:SetFrameStrata(LFGListFrame:GetFrameStrata())
    myPanel:SetFrameLevel((LFGListFrame:GetFrameLevel() or 1) + 1)

    -- THEIR panel: anchored to the LEFT of my panel (appears between LFG and Mine)
    -- Wait — user said "their data and mine to the right of theirs" so theirs is LEFT, mine is RIGHT
    -- Both are to the right of LFGListFrame. Theirs sits BETWEEN LFG and Mine.
    theirPanel = CreateProfilePanel("VoidScoutTheirPanel", LFGListFrame)
    -- Re-anchor MY panel to be to the right of THEIR panel when THEIR is shown:
    -- We'll dynamically swap when ShowOther/HideOther is called.

    -- Initial state: MY is anchored to LFGListFrame right; THEIR is hidden
    theirPanel:Hide()

    -- When their panel shows, anchor it to LFG right and re-anchor my panel to their right
    theirPanel:SetScript("OnShow", function()
        theirPanel:ClearAllPoints()
        theirPanel:SetPoint("TOPLEFT", LFGListFrame, "TOPRIGHT", PANEL_GAP, 0)
        theirPanel:SetFrameStrata(LFGListFrame:GetFrameStrata())
        theirPanel:SetFrameLevel((LFGListFrame:GetFrameLevel() or 1) + 1)

        myPanel:ClearAllPoints()
        myPanel:SetPoint("TOPLEFT", theirPanel, "TOPRIGHT", PANEL_GAP, 0)
    end)
    theirPanel:SetScript("OnHide", function()
        myPanel:ClearAllPoints()
        myPanel:SetPoint("TOPLEFT", LFGListFrame, "TOPRIGHT", PANEL_GAP, 0)
    end)

    -- Initial data populate
    RefreshMyPanel()

    local function showLogic()
        if not VoidScoutDB.enabled then
            myPanel:Hide()
            if theirPanel then theirPanel:Hide() end
            return
        end
        RefreshMyPanel()
        myPanel:Show()
        if theirPanel then theirPanel:Hide() end
    end

    local function hideLogic()
        myPanel:Hide()
        if theirPanel then theirPanel:Hide() end
    end

    -- Hook LFGListFrame (the Premade Groups subwindow)
    if not LFGListFrame._voidscoutHook then
        LFGListFrame:HookScript("OnShow", showLogic)
        LFGListFrame:HookScript("OnHide", hideLogic)
        LFGListFrame._voidscoutHook = true
    end

    -- Also hook PVEFrame (Group Finder container) — Premade Groups is a
    -- tab inside it. If LFGListFrame's OnShow doesn't fire on tab switch,
    -- this catches the container open/close as a fallback.
    if PVEFrame and not PVEFrame._voidscoutHook then
        PVEFrame:HookScript("OnHide", hideLogic)
        PVEFrame._voidscoutHook = true
    end

    -- If LFG is already showing now (addon /reload while panel open), apply immediately
    if VoidScoutDB.enabled and LFGListFrame:IsShown() then
        showLogic()
    elseif not VoidScoutDB.enabled then
        myPanel:Hide()
    end

    return myPanel
end

----------------------------------------------------------------------
-- Header VS toggle (unchanged behavior)
----------------------------------------------------------------------
local function CreateHeaderToggle()
    if headerCheck then return headerCheck end
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    local refreshBtn = sp and sp.RefreshButton
    local parent = sp or LFGListFrame
    if not parent then return nil end

    headerCheck = CreateFrame("CheckButton", "VoidScoutHeaderToggle", parent, "UICheckButtonTemplate")
    headerCheck:SetSize(20, 20)
    if refreshBtn then
        headerCheck:SetPoint("RIGHT", refreshBtn, "LEFT", -22, 0)
    else
        headerCheck:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, -4)
    end

    local lbl = headerCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetText("VS")
    lbl:SetTextColor(1, 0.82, 0)
    lbl:SetPoint("LEFT", headerCheck, "RIGHT", 0, 1)

    headerCheck:SetChecked(VoidScoutDB.enabled and true or false)
    headerCheck:SetScript("OnClick", function(self)
        VoidScoutDB.enabled = self:GetChecked() and true or false
        if myPanel then
            if VoidScoutDB.enabled then myPanel:Show() else myPanel:Hide() end
        end
        if not VoidScoutDB.enabled and theirPanel then theirPanel:Hide() end
        if VoidScoutDB.enabled then SuppressExternalOverlays(); RefreshMyPanel() end
    end)
    headerCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("VoidScout", 1, 0.82, 0)
        GameTooltip:AddLine("Toggle your profile panel.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    headerCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return headerCheck
end

----------------------------------------------------------------------
-- LFG tooltip injectors — append PlayerScan VoidScout section to the
-- group-leader search-result tooltip and the applicant-member tooltip.
-- These paths bypass TooltipDataProcessor (Blizzard builds them directly)
-- so we hook the functions instead.
----------------------------------------------------------------------
-- Suppress RaiderIO + Archon lines from any GameTooltip. We render our
-- own consolidated VoidScout section; RIO/Archon tooltip output becomes
-- redundant noise. Both addons stay ENABLED (we still call RIO's
-- :GetProfile() API to read their data); only the visual tooltip is
-- blanked.
local function SuppressThirdPartyTooltipLines()
    if VoidScoutDB and VoidScoutDB.suppressRIOTooltip == false then return end
    if not GameTooltip or not GameTooltip.NumLines then return end
    for i = 1, GameTooltip:NumLines() do
        local lL = _G["GameTooltipTextLeft" .. i]
        local lR = _G["GameTooltipTextRight" .. i]
        local txtL = lL and lL:GetText() or ""
        local txtR = lR and lR:GetText() or ""
        if  txtL:find("[Rr]aider%.?[Ii][Oo]") or txtR:find("[Rr]aider%.?[Ii][Oo]")
         or txtL:find("[Bb]est [Rr]un")
         or txtL:find("[Tt]imed%s*%+?%d")     -- "Timed 15+ Runs" OR "Timed +12-14 Runs"
         or txtL:find("VS/DR/MQD")            or txtL:find("Mythic VS")
         or txtL:find("Heroic VS")            or txtL:find("Warcraft Logs")
         or txtL:find("[Aa]rchon")            or txtR:find("[Aa]rchon")
         or txtL:find("M%+ Score")            or txtR:find("M%+ Score") then
            if lL then lL:SetText("") end
            if lR then lR:SetText("") end
        end
    end
end

local _lfgTooltipHooksInstalled = false
local function InstallLFGTooltipHooks()
    if _lfgTooltipHooksInstalled then return end
    if not VoidScout.PlayerScan or not VoidScout.PlayerScan.AppendTooltipLines then return end

    -- Helper: color a 0-99 score for tooltip display
    local function score_color(s)
        if not s then return "|cffaaaaaa" end
        if s >= 85 then return "|cff20ff20"
        elseif s >= 70 then return "|cffffd820"
        elseif s >= 50 then return "|cffff8c20"
        else return "|cffff4040" end
    end

    -- Group leader tooltip (Premade Groups search results).
    -- When YOU hover a leader's listing, show YOUR Probability for
    -- that dungeon+key — answers "is this group a good fit for me?"
    if _G.LFGListSearchEntry_OnEnter then
        hooksecurefunc("LFGListSearchEntry_OnEnter", function(self)
            if not self or not self.resultID then return end
            local ok, info = pcall(C_LFGList.GetSearchResultInfo, self.resultID)
            if not ok or not info or not info.leaderName then return end
            local full = info.leaderName
            local n, r = full:match("^([^-]+)-(.+)$")
            if not n then n = full end
            local live_rio = info.leaderOverallDungeonScore
            pcall(function()
                VoidScout.PlayerScan:AppendTooltipLines(GameTooltip, n, r, live_rio)
            end)

            -- Combined Probability: leader + you (+ visible members).
            -- Pulls everything we can read: leader class/spec/PB/rating,
            -- visible group members, your stats, group utility (lust/brez).
            -- Assumed key level = leader's PB on the listed dungeon (best
            -- signal available — see [[wow-12-lfg-title-unreadable]]).
            local lp = VoidScout.LeaderProbabilityOverlay
            if lp and lp.ContextFromSearchResult and VoidScout.TimerScore then
                local ctx = lp:ContextFromSearchResult(self.resultID)
                if ctx and ctx.leader_pb and ctx.leader_pb > 0 then
                    local pb = ctx.leader_pb

                    -- Build the player list: leader + visible members + you.
                    local players = {}
                    local seenYou = false
                    local _, myClass = UnitClass("player")
                    local mySpecID = GetSpecialization and GetSpecialization()
                    local mySpecName
                    if mySpecID then
                        local _, sname = GetSpecializationInfo(mySpecID)
                        mySpecName = sname
                    end
                    local myIlvl = math.floor(select(2, GetAverageItemLevel()) or 0)

                    -- Read each visible member. GetSearchResultPlayerInfo
                    -- returns a TABLE struct in 12.0.5, not multi-return.
                    local numMembers = info.numMembers or 1
                    for i = 1, numMembers do
                        local ok, pinfo = pcall(C_LFGList.GetSearchResultPlayerInfo, self.resultID, i)
                        if ok and type(pinfo) == "table" and pinfo.classFilename then
                            -- Leader (i=1) gets a richer ilvl proxy from listing data
                            local ilvl_est = 270 + math.floor((info.leaderOverallDungeonScore or 2000) / 100)
                            if i == 1 and info.requiredItemLevel and info.requiredItemLevel > 0 then
                                ilvl_est = info.requiredItemLevel
                            end
                            players[#players+1] = {
                                classFile = pinfo.classFilename,
                                specName  = pinfo.specName or "?",
                                ilvl      = ilvl_est,
                                is_leader = pinfo.isLeader or (i == 1),
                            }
                        end
                    end
                    -- Include YOU as the prospective applicant
                    players[#players+1] = {
                        classFile = myClass,
                        specName  = mySpecName or "?",
                        ilvl      = myIlvl,
                        is_self   = true,
                    }

                    local group = VoidScout.TimerScore:ScoreGroup(players, pb, ctx.dungeon_id)
                    if group and group.group_score then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(("%sVoidScout Probability: %d|r  |cff999999(assuming +%d %s)|r"):format(
                            score_color(group.group_score), group.group_score, pb, ctx.dungeon_name))
                        if group.utility_notes and #group.utility_notes > 0 then
                            for _, note in ipairs(group.utility_notes) do
                                GameTooltip:AddLine("|cff999999  " .. note .. "|r")
                            end
                        end
                    end
                end
            end

            C_Timer.After(0, function()
                pcall(SuppressThirdPartyTooltipLines)
                pcall(function() GameTooltip:Show() end)
            end)
        end)
    end

    -- Applicant member tooltip (when YOU are the leader viewing applicants).
    -- Show THIS APPLICANT's Probability for YOUR hosted dungeon+key.
    if _G.LFGListApplicantMember_OnEnter then
        hooksecurefunc("LFGListApplicantMember_OnEnter", function(self)
            if not self then return end
            local appID = self:GetParent() and self:GetParent().applicantID
            local memberIdx = self.memberIdx
            if not appID or not memberIdx then return end
            local ok, name, class, _localizedClass, _level, itemLevel,
                  _honorLevel, _tank, _healer, _damage, _assignedRole,
                  _relationship, dungeonScore, _pvpItemLevel, _factionGroup,
                  _raceID, specID, isLeaver =
                pcall(C_LFGList.GetApplicantMemberInfo, appID, memberIdx)
            if not ok or not name or name == "" then return end
            local n, r = name:match("^([^-]+)-(.+)$")
            if not n then n = name end
            pcall(function()
                VoidScout.PlayerScan:AppendTooltipLines(GameTooltip, n, r)
            end)

            -- Probability of THIS APPLICANT timing the key YOU are hosting.
            local lp = VoidScout.LeaderProbabilityOverlay
            if lp and lp.ContextFromOwnListing and lp.Score then
                local ctx = lp:ContextFromOwnListing()
                if ctx then
                    local s = lp:Score(class, specID, itemLevel, dungeonScore, isLeaver, ctx)
                    if s then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(("%sVoidScout Probability: %d|r  |cff999999(applicant in %s +%d)|r"):format(
                            score_color(s), s, ctx.dungeon_name, ctx.keylevel))
                    end
                end
            end

            C_Timer.After(0, function()
                pcall(SuppressThirdPartyTooltipLines)
                pcall(function() GameTooltip:Show() end)
            end)
        end)
    end

    _lfgTooltipHooksInstalled = true
end

local function BuildAll()
    if not LFGListFrame then return false end
    CreatePanels()
    CreateHeaderToggle()
    SuppressExternalOverlays()
    InstallArchonScraper()  -- scrape WCL parses from Archon's tooltip lines
    InstallLFGTooltipHooks()
    if not LFGListFrame._voidscoutShowHook then
        LFGListFrame:HookScript("OnShow", function()
            if VoidScoutDB.enabled then SuppressExternalOverlays() end
        end)
        LFGListFrame._voidscoutShowHook = true
    end
    return true
end

function mod:Init()
    if BuildAll() then return end
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("ADDON_LOADED")
    waiter:RegisterEvent("PLAYER_ENTERING_WORLD")
    waiter:SetScript("OnEvent", function(self, event, addonName)
        -- Blizzard_GroupFinder (12.0.5) replaced Blizzard_LookingForGroupUI.
        -- Also accept VanillaStyle variant + any event where LFGListFrame
        -- is now available (covers /reload mid-session edge cases).
        if event == "PLAYER_ENTERING_WORLD"
           or addonName == "Blizzard_GroupFinder"
           or addonName == "Blizzard_GroupFinder_VanillaStyle"
           or addonName == "Blizzard_LookingForGroupUI" then
            if LFGListFrame and BuildAll() then
                self:UnregisterAllEvents()
            end
        end
    end)

    -- Auto-refresh the visible panel when a fight ends so the score updates
    -- live without needing to close+reopen Premade Groups between pulls.
    -- Defer by 200ms so FightRecorder's ENCOUNTER_END handler runs first.
    local liveRefresh = CreateFrame("Frame")
    liveRefresh:RegisterEvent("ENCOUNTER_END")
    liveRefresh:SetScript("OnEvent", function()
        if myPanel and myPanel:IsShown() then
            C_Timer.After(0.2, RefreshMyPanel)
        end
    end)
end
