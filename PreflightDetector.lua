----------------------------------------------------------------------
-- VoidScout PreflightDetector
--
-- Detects when the player is inside an M+ dungeon instance BEFORE the
-- keystone has been inserted. In this state, the profile panel switches
-- from "generic capability" to "specific run probability" showing:
--   * YOUR Probability for THIS dungeon at THIS key level
--   * GROUP Probability computed from comp + utility coverage
--   * Per-dungeon-weighted coaching items
--
-- Lets a player decide to bounce BEFORE the key starts if the group
-- composition doesn't look like it'll time.
--
-- Triggers:
--   - PLAYER_ENTERING_WORLD (zone in)
--   - ZONE_CHANGED_NEW_AREA (cross-zone)
--   - CHALLENGE_MODE_START (clear preflight state)
--   - GROUP_ROSTER_UPDATE (members change in preflight)
----------------------------------------------------------------------

VoidScout = VoidScout or {}
local mod = {}
VoidScout.PreflightDetector = mod

mod._inPreflight = false
mod._currentContext = nil  -- { dungeon_id, dungeon_name, keylevel }


----------------------------------------------------------------------
-- Read the leader's hosted listing's dungeon + key level. Works
-- after we've joined the group via LFG. Returns nil if we joined
-- through guild/friend/whisper invite (no listing context).
----------------------------------------------------------------------
local function listing_context()
    if not C_LFGList or not C_LFGList.GetActiveEntryInfo then return nil end
    local entry = C_LFGList.GetActiveEntryInfo()
    if not entry then return nil end
    local actID = (entry.activityIDs and entry.activityIDs[1]) or entry.activityID
    if not actID then return nil end
    local act = C_LFGList.GetActivityInfoTable(actID)
    if not act then return nil end
    local lvl = 0
    if act.fullName then
        lvl = tonumber(act.fullName:match("%+(%d+)")) or 0
    end
    return {
        dungeon_id   = act.mapID or 0,
        dungeon_name = act.shortName or act.fullName or "M+",
        keylevel     = lvl,
    }
end


----------------------------------------------------------------------
-- Detect preflight state.
-- Conditions: in a "party" instance + no active keystone OR keystone
-- has level=0 (not yet inserted by leader). The party-instance check
-- also catches normal dungeons; we filter to known M+ dungeons later.
----------------------------------------------------------------------
local function detect_preflight()
    if not C_ChallengeMode then return nil end
    local _, instType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instType ~= "party" then return nil end
    -- If a keystone is active (level > 0), we're MID-RUN, not preflight
    local activeKL = (C_ChallengeMode.GetActiveKeystoneInfo
                      and C_ChallengeMode.GetActiveKeystoneInfo()) or 0
    if activeKL > 0 then return nil end

    -- Try to read leader's listing for the dungeon+key context
    local ctx = listing_context()
    if not ctx then
        return {
            dungeon_id   = instanceID or 0,
            dungeon_name = GetInstanceInfo() or "M+ Dungeon",
            keylevel     = 0,  -- unknown; default rendering
        }
    end
    return ctx
end


----------------------------------------------------------------------
-- Compute Group Probability from composition alone (works regardless
-- of whether other members have addon data). Uses:
--   * Each member's class+spec → Murlok baseline
--   * Lust coverage (Mage/Shaman/Hunter/Evoker)
--   * Brez coverage (Druid/DK/Warlock)
--   * Stealth/skip (Rogue/Druid)
-- Returns a 0-99 score + utility flags table.
----------------------------------------------------------------------
local function group_probability(dungeon_id, keylevel)
    if not VoidScout.TimerData then return nil end

    local members = {}
    if UnitExists("player") then
        local _, cls = UnitClass("player")
        local specID = GetSpecialization()
        local specName = nil
        if specID and specID > 0 then
            local _, n = GetSpecializationInfo(specID)
            specName = n
        end
        table.insert(members, { class = cls, spec = specName })
    end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            local _, cls = UnitClass(u)
            local sid = GetInspectSpecialization and GetInspectSpecialization(u) or 0
            local specName = nil
            if sid and sid > 0 and GetSpecializationInfoByID then
                local _, n = GetSpecializationInfoByID(sid)
                specName = n
            end
            table.insert(members, { class = cls, spec = specName })
        end
    end

    if #members == 0 then return nil end

    -- Average class baseline (using Murlok scores from TimerData)
    local base_sum, base_count = 0, 0
    local has_lust, has_brez, has_stealth = false, false, false
    local LUST_CLASSES = { MAGE=true, SHAMAN=true, HUNTER=true, EVOKER=true }
    local BREZ_CLASSES = { DRUID=true, DEATHKNIGHT=true, WARLOCK=true, HUNTER=true }
    local STEALTH_CLASSES = { ROGUE=true, DRUID=true }

    for _, m in ipairs(members) do
        if m.spec and m.class then
            local s = VoidScout.TimerData:GetSpecBase(m.class, m.spec) or 60
            base_sum = base_sum + s
            base_count = base_count + 1
        end
        if m.class and LUST_CLASSES[m.class] then has_lust = true end
        if m.class and BREZ_CLASSES[m.class] then has_brez = true end
        if m.class and STEALTH_CLASSES[m.class] then has_stealth = true end
    end

    if base_count == 0 then return nil end
    local avg_base = base_sum / base_count

    -- Utility modifiers
    local util_mod = 0
    if has_lust then util_mod = util_mod + 3 else util_mod = util_mod - 5 end
    if has_brez then util_mod = util_mod + 1 end
    if has_stealth then util_mod = util_mod + 1 end

    -- Key level scaling
    local kdiff = (VoidScout.TimerData:GetKeyDifficulty(keylevel)) or 1.0
    local score = math.floor((avg_base * kdiff) + util_mod + 0.5)
    score = math.max(5, math.min(99, score))

    return score, {
        lust = has_lust,
        brez = has_brez,
        stealth = has_stealth,
        members = #members,
        avg_base = math.floor(avg_base + 0.5),
    }
end


----------------------------------------------------------------------
-- Push current preflight context to LFGPanel for it to render with
-- the dungeon/key-specific header instead of the generic capability view.
----------------------------------------------------------------------
local function notify_panel()
    if not VoidScout.LFGPanel then return end
    -- The LFG panel reads the preflight state from this module when
    -- SetData fires. Trigger a refresh so it picks up the new context.
    if mod._inPreflight and VoidScout.LFGPanel.Refresh then
        VoidScout.LFGPanel:Refresh()
    end
end


----------------------------------------------------------------------
-- Exported getter: panel asks "are we in preflight, if so for what?"
-- Returns: { dungeon_id, dungeon_name, keylevel, group_score, util_flags }
-- or nil if not preflight.
----------------------------------------------------------------------
function mod:GetPreflight()
    if not mod._inPreflight then return nil end
    local ctx = mod._currentContext
    if not ctx then return nil end
    local gscore, util = group_probability(ctx.dungeon_id, ctx.keylevel)
    return {
        dungeon_id   = ctx.dungeon_id,
        dungeon_name = ctx.dungeon_name,
        keylevel     = ctx.keylevel,
        group_score  = gscore,
        util_flags   = util,
    }
end


----------------------------------------------------------------------
-- Event handling
----------------------------------------------------------------------
local function on_event(self, event, ...)
    local ctx = detect_preflight()
    if ctx then
        mod._inPreflight = true
        mod._currentContext = ctx
    else
        if mod._inPreflight then
            mod._inPreflight = false
            mod._currentContext = nil
        end
    end
    notify_panel()
end


function mod:Init()
    if mod._frame then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("CHALLENGE_MODE_START")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("CHALLENGE_MODE_RESET")
    f:SetScript("OnEvent", on_event)
    mod._frame = f
end
