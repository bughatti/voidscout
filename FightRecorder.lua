----------------------------------------------------------------------
-- VoidScout FightRecorder — captures per-fight contract data.
--
-- v0.4.0 scope:
--   * Listen for ENCOUNTER_START / ENCOUNTER_END
--   * Capture group LEADER (name+GUID) and full roster on each pull
--   * Group consecutive fights under same leader into a "pug session"
--   * Record {timestamp, encounter_id, difficulty, label, outcome, dur,
--             leader, roster, pug_id}
--   * Persist to VoidScoutDB.fightLog (capped at 200 most recent entries)
--   * Print debug summary to chat on each fight completion
--
-- This is the THIN-CLIENT contract — the addon just captures what the
-- player did (their declared label) and when. The actual scoring happens
-- on the backend by pulling WCL log data + applying the algorithms.
--
-- Commitment axis: per-pug stay rate = (attempts you stayed) / (total in
-- that leader's pug). Backend aggregates across many leaders for a player's
-- lifetime commitment percentile.
--
-- Future: HTTP POST queue to backend when one exists (NAS + Cloudflare).
-- For now, entries just accumulate locally for the player's own review.
----------------------------------------------------------------------

local mod = {}
VoidScout.FightRecorder = mod

local MAX_FIGHT_LOG = 200    -- FIFO cap, never overflow SavedVariables

local C = {
    accent  = "ff00c7ff",
    success = "ff66ff66",
    fail    = "ffff6666",
    dim     = "ff8c8c9e",
}

-- DIFFICULTY ID → name (Blizzard's raid difficulty enum)
local DIFF_NAMES = {
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
    [17] = "LFR",
}

-- In-flight state — set on START, finalized on END
local current_fight = nil

-- Separate from current_fight: tracks whether a BOSS encounter is
-- currently active. current_fight is ALSO set by CHALLENGE_MODE_START
-- for the M+ wrapper, so it can't be used to detect "is a boss pull
-- happening right now" — that needs its own flag, set on ENCOUNTER_START
-- and cleared on ENCOUNTER_END. Used by trash-pull capture to know
-- when to ignore a combat enter/exit (it's a boss, not trash).
local boss_encounter_active = false

-- Per-M+ run identifier — generated on CHALLENGE_MODE_START, attached to
-- EVERY fight (trash + boss) captured during the run, cleared on
-- COMPLETED/RESET. Server aggregator groups by run_id so one M+ counts
-- as ONE event in averages, not 30+ trash pulls + 4 bosses inflating the
-- denominator. Format: {instanceID}_{server_time_at_start}.
local current_run_id = nil

-- Death tracking. C_DamageMeter's death fields are secret-tainted in
-- cross-realm M+ groups; CLEU UNIT_DIED is banned (taint). Use PLAYER_DEAD
-- for self + UNIT_HEALTH transitions for party members.
local self_deaths_this_pull = 0   -- reset per combat (PLAYER_REGEN_DISABLED)
local self_deaths_this_run  = 0   -- reset per M+ run (CHALLENGE_MODE_START)
local member_deaths_this_pull = {}   -- {[player_name] = count}
local member_was_alive = {}          -- {[unitID] = bool}

-- Combat log auto-toggle state. The combat log file (Logs/WoWCombatLog-*.txt)
-- is the same data WCL parses — captures every event we lose to taint via
-- C_DamageMeter. We auto-enable /combatlog at encounter/run start and
-- auto-disable at end. We only disable if WE enabled it; if the user had
-- it on manually before us we leave it alone.
--
-- PERSISTED to VoidScoutCharDB so a /reload mid-key doesn't orphan the log
-- file. On Init we reconcile: if we previously enabled it but there's no
-- longer an active context (no key, no encounter), turn it off.
local cl_we_enabled = false      -- did VoidScout flip it on?
local cl_active_contexts = 0     -- nesting count (encounter inside M+ run)

-- Gated debug print. Enable via VoidScoutDB.debug = true (no public
-- toggle yet; flip manually in SavedVariables to re-enable trace).
local function vs_dbg(fmt, ...)
    if not (VoidScoutDB and VoidScoutDB.debug) then return end
    print(("|cffff00ff[VS DEBUG]|r " .. fmt):format(...))
end

local function _persist_cl()
    VoidScoutCharDB = VoidScoutCharDB or {}
    VoidScoutCharDB.cl = VoidScoutCharDB.cl or {}
    VoidScoutCharDB.cl.weEnabledIt = cl_we_enabled
    VoidScoutCharDB.cl.contexts    = cl_active_contexts
end

local function cl_start()
    if not LoggingCombat then return end
    -- Clamp drift: Blizzard sometimes drops ENCOUNTER_END on raid wipes,
    -- leaving our context count >0 with no real fight in progress. If
    -- IsEncounterInProgress() returns false but our count says we should
    -- be deep in a fight, force-reset to 0 so this fresh start fires the
    -- file-open path cleanly (new file per pull instead of appending).
    if cl_active_contexts > 0 and IsEncounterInProgress
       and not IsEncounterInProgress() then
        -- Only reset if we're not inside an M+ key (key keeps the count
        -- legitimately ≥1 between bosses).
        local in_key = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
                       and (C_ChallengeMode.GetActiveChallengeMapID() or 0) > 0
        if not in_key then
            cl_active_contexts = 0
            if cl_we_enabled and LoggingCombat() then
                LoggingCombat(false)
                cl_we_enabled = false
            end
        end
    end
    cl_active_contexts = cl_active_contexts + 1
    if cl_active_contexts > 1 then _persist_cl(); return end
    local was_on = LoggingCombat()
    if not was_on then
        -- /combatlog is OFF. We're going to turn it on for the fight,
        -- so we own it and we'll turn it off when the encounter ends.
        LoggingCombat(true)
        cl_we_enabled = true
    else
        -- /combatlog is already ON — user enabled it manually, or
        -- another addon (WCL Client, Archon, Raider.IO, BigWigs,
        -- DBM logger plugin) requested it for their own logging
        -- pipeline. NEVER claim ownership in this case. cl_stop()
        -- only acts when cl_we_enabled is true, so leaving it false
        -- guarantees we won't touch their log when the encounter
        -- ends. They get to manage their own logging.
        --
        -- cl_we_enabled may already be true from a prior context this
        -- session (e.g. M+ key already running with us as the owner) —
        -- leave it untouched in that case too.
    end
    _persist_cl()
end

local function cl_stop()
    if not LoggingCombat then return end
    if cl_active_contexts > 0 then
        cl_active_contexts = cl_active_contexts - 1
    end
    if cl_active_contexts > 0 then _persist_cl(); return end
    if cl_we_enabled then
        -- DEFER LoggingCombat(false) by ~0.5s so WoW's combat log writer
        -- has time to flush the ENCOUNTER_END (or CHALLENGE_MODE_END) line
        -- to disk before we close the file. Without this, the closing event
        -- is lost — backend parser then sees N starts / N-1 ends and has
        -- to infer the last fight's outcome from absence of events.
        cl_we_enabled = false
        _persist_cl()
        C_Timer.After(0.5, function()
            -- Re-check: only actually disable if no new context grabbed it
            -- during the deferral window (e.g., next boss pulled instantly).
            if cl_active_contexts == 0 and LoggingCombat() then
                LoggingCombat(false)
            end
        end)
        return
    end
    _persist_cl()
end

-- Reconcile state at addon load. Handles the "reload mid-key after a taint
-- error" case: in-memory state was wiped, but the combatlog file is still
-- open on disk. If we previously enabled it and there's no longer an active
-- M+ key or boss encounter, turn it off so the file can stabilize and be
-- picked up by the uploader.
local function reconcile_cl_state_on_load()
    if not LoggingCombat then return end
    VoidScoutCharDB = VoidScoutCharDB or {}
    local saved = VoidScoutCharDB.cl or {}
    cl_we_enabled      = saved.weEnabledIt or false
    cl_active_contexts = saved.contexts    or 0

    -- NEVER touch a log we don't own. The persisted `cl_we_enabled`
    -- flag is the authoritative signal of ownership: it's only set
    -- true when cl_start() actually called LoggingCombat(true). If
    -- the user manually `/combatlog`'d, or WCL Client / Archon /
    -- Raider.IO / BigWigs flipped it on, cl_we_enabled stays false
    -- and we leave their log alone — even on /reload, even outside
    -- combat. Their logging pipeline is their business.
    --
    -- An older "AGGRESSIVE" version of this function force-stopped
    -- any out-of-combat log regardless of ownership. It silently
    -- killed guildies' manual /combatlog sessions when they /reloaded
    -- mid-farm. Fixed 2026-06-10.
    local on_now = LoggingCombat()
    if not on_now then
        cl_we_enabled = false
        cl_active_contexts = 0
        _persist_cl()
        return
    end

    -- Logging is on, but we don't own it. Hands off.
    if not cl_we_enabled then return end

    -- We own it. Are we still in a context that should keep it on?
    local in_key = false
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        in_key = (C_ChallengeMode.GetActiveChallengeMapID() or 0) > 0
    end
    local in_enc = IsEncounterInProgress and IsEncounterInProgress() or false

    if in_key or in_enc then
        cl_active_contexts = math.max(cl_active_contexts, 1)
        _persist_cl()
        return
    end

    -- We own it and there's no active context — our own orphan. Stop it.
    LoggingCombat(false)
    cl_we_enabled      = false
    cl_active_contexts = 0
    _persist_cl()
    print("|cff00c7ffVoidScout:|r stopped our /combatlog from a prior session.")
end

-- Pull-start snapshots: buffs active + forces% at PLAYER_REGEN_DISABLED.
-- Lets us answer "did Lust go up at the start of pulls" + "what % did we
-- clear this pull".
local pull_start_buffs = {}     -- {[player_name] = {lust=true, pi=true, ...}}
local pull_start_forces = 0     -- scenario forces% at pull start
local run_start_forces = 0      -- forces% at run start

-- Dead-time tracking — for active DPS calculation. Tracks per-player
-- intervals spent dead during the current pull.
local dead_time_per_player = {}    -- {[player_name] = total_seconds_dead}
local died_at_per_unit = {}        -- {[unitID] = GetTime() when died}

-- Important buff/utility spell IDs we track at pull start
local PULL_BUFFS = {
    -- Lust/Heroism family — any of these = "lust covered"
    [2825]   = "Bloodlust",
    [32182]  = "Heroism",
    [80353]  = "TimeWarp",
    [264667] = "PrimalRage",
    [390386] = "FuryOfTheAspects",
    [354017] = "Ancient_Hysteria_evoker",  -- placeholder alt
    -- High-value group buffs
    [10060]  = "PowerInfusion",
    [395152] = "EbonMight",
    [413984] = "ShiftingSands",
    [1459]   = "ArcaneIntellect",
    [21562]  = "PowerWordFortitude",
    [6673]   = "BattleShout",
    [381762] = "BlessingOfTheBronze",
}

-- Read forces% from the M+ scenario step. Returns 0 outside M+.
-- Declared early so save closures (defined further down) can capture it
-- as an upvalue — Lua locals don't lift, must exist before reference.
local function read_forces_pct()
    if not C_Scenario or not C_Scenario.GetStepInfo then return 0 end
    local ok, _, _, _, _, _, _, _, _, weight, count, _, _, _, _, dungeonScore =
        pcall(C_Scenario.GetCriteriaInfo, 1)
    if ok and weight and weight > 0 then
        return math.floor((count or 0) / weight * 100)
    end
    return 0
end

-- Snapshot active group buffs at pull start. Same early-declaration reason.
local function snapshot_pull_buffs()
    pull_start_buffs = {}
    for _, unit in ipairs({"player","party1","party2","party3","party4"}) do
        if UnitExists(unit) then
            local n, r = UnitName(unit)
            if n then
                if not r or r == "" then
                    r = (GetRealmName and GetRealmName() or ""):gsub("%s+", "")
                end
                local full = (r and r ~= "") and (n .. "-" .. r) or n
                pull_start_buffs[full] = pull_start_buffs[full] or {}
                local i = 1
                while true do
                    local ok, aura = pcall(function()
                        if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
                            return C_UnitAuras.GetBuffDataByIndex(unit, i)
                        end
                    end)
                    if not ok or not aura then break end
                    local sid = aura.spellId
                    local sid_safe = sid ~= nil
                                     and type(sid) == "number"
                                     and not (_G.issecretvalue and issecretvalue(sid))
                    if sid_safe and PULL_BUFFS[sid] then
                        pull_start_buffs[full][PULL_BUFFS[sid]] = true
                    end
                    i = i + 1
                    if i > 40 then break end
                end
            end
        end
    end
end

-- Pug session state — persists across fights with same leader
-- Reset when leader changes (player joins a different group)
local current_pug = nil  -- { leader_name, leader_guid, first_pull_ts, pug_id }

----------------------------------------------------------------------
-- Group leader detection
-- Works for raid (raid1..raid40), party (player/party1..party4), solo (nil)
----------------------------------------------------------------------
local function GetGroupLeader()
    local n = GetNumGroupMembers() or 0
    if n == 0 then
        return nil, nil  -- solo, no leader
    end
    local prefix, max
    if IsInRaid() then
        prefix, max = "raid", 40
    else
        -- party: check player first, then party1..party4
        if UnitIsGroupLeader("player") then
            local name, realm = UnitName("player")
            local guid = UnitGUID("player")
            local fullname = realm and realm ~= "" and (name .. "-" .. realm) or name
            return fullname, guid
        end
        prefix, max = "party", 4
    end
    for i = 1, max do
        local unit = prefix .. i
        if UnitExists(unit) and UnitIsGroupLeader(unit) then
            local name, realm = UnitName(unit)
            local guid = UnitGUID(unit)
            if name then
                local fullname = realm and realm ~= "" and (name .. "-" .. realm) or name
                return fullname, guid
            end
        end
    end
    return nil, nil
end

----------------------------------------------------------------------
-- Capture full group roster (player names) at this moment
-- Returns sorted array of "Name-Realm" strings.
----------------------------------------------------------------------
local function CaptureRoster()
    local roster = {}
    local n = GetNumGroupMembers() or 0
    if n == 0 then
        -- solo
        local name, realm = UnitName("player")
        roster[1] = realm and realm ~= "" and (name .. "-" .. realm) or name
        return roster
    end
    if IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) then
                local name, realm = UnitName(unit)
                if name then
                    roster[#roster + 1] = realm and realm ~= "" and (name .. "-" .. realm) or name
                end
            end
        end
    else
        local pname, prealm = UnitName("player")
        if pname then
            roster[#roster + 1] = prealm and prealm ~= "" and (pname .. "-" .. prealm) or pname
        end
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name, realm = UnitName(unit)
                if name then
                    roster[#roster + 1] = realm and realm ~= "" and (name .. "-" .. realm) or name
                end
            end
        end
    end
    table.sort(roster)
    return roster
end

----------------------------------------------------------------------
-- Pug session tracking — persists across /reload via SavedVariables.
-- Same leader_guid + still in their group = same pug, even across reloads.
----------------------------------------------------------------------
local function GetPersistedPug()
    VoidScoutDB = VoidScoutDB or {}
    return VoidScoutDB.currentPug
end

local function SetPersistedPug(pug)
    VoidScoutDB = VoidScoutDB or {}
    VoidScoutDB.currentPug = pug
    current_pug = pug   -- mirror to module-local for fast access this session
end

local function EnsurePugSession(leader_name, leader_guid)
    -- No leader (solo, or scenario) — clear active pug
    if not leader_guid then
        SetPersistedPug(nil)
        return nil
    end
    -- Sync from SavedVariables if module-local is stale (post-reload case)
    if not current_pug then current_pug = GetPersistedPug() end
    -- Same leader as before (this session or persisted from before reload) — continue
    if current_pug and current_pug.leader_guid == leader_guid then
        return current_pug
    end
    -- Different leader — start new pug session
    local first_ts = GetServerTime()
    local new_pug = {
        leader_name   = leader_name,
        leader_guid   = leader_guid,
        first_pull_ts = first_ts,
        pug_id        = leader_guid .. "_" .. tostring(first_ts),
    }
    SetPersistedPug(new_pug)
    return new_pug
end

----------------------------------------------------------------------
-- Snapshot the active label from LabelPicker
----------------------------------------------------------------------
local function SnapshotLabel()
    local label = VoidScoutCharDB and VoidScoutCharDB.label
    if not label then
        return { role = "DPS", subcats = {}, code = "?" }
    end
    -- Build code like "D+U" or "T+R"
    local roleCode = ({ TANK="T", HEALER="H", DPS="D" })[label.role] or "?"
    local subList = {}
    if label.subcats then
        for _, k in ipairs({ "utility", "soaks", "rescues" }) do
            if label.subcats[k] then
                subList[#subList + 1] = ({ utility="U", soaks="S", rescues="R" })[k]
            end
        end
    end
    local code = (#subList > 0) and (roleCode .. "+" .. table.concat(subList)) or roleCode
    return {
        role = label.role,
        subcats = label.subcats or {},
        code = code,
    }
end

----------------------------------------------------------------------
-- Persist a completed fight entry
----------------------------------------------------------------------
local function AppendFightLog(entry)
    VoidScoutDB.fightLog = VoidScoutDB.fightLog or {}
    table.insert(VoidScoutDB.fightLog, entry)
    while #VoidScoutDB.fightLog > MAX_FIGHT_LOG do
        table.remove(VoidScoutDB.fightLog, 1)
    end
end

----------------------------------------------------------------------
-- Activity + Teamwork tracker: counts successful casts per player during
-- the encounter, and separately counts teamwork-flagged spell casts.
-- UNIT_SPELLCAST_SUCCEEDED is untainted, fires for raid/party + player.
-- Filters to player units only (no NPC casts).
-- ScoreEngine reads `cast_counts` and `teamwork_counts` at ENCOUNTER_END.
----------------------------------------------------------------------
local cast_counts     = {}    -- {playerGUID -> total cast count}
local teamwork_counts = {}    -- {playerGUID -> count of teamwork spell casts}
local cast_frame      = nil

local function StartActivityTracking()
    cast_counts = {}
    teamwork_counts = {}
    if not cast_frame then
        cast_frame = CreateFrame("Frame")
        cast_frame:SetScript("OnEvent", function(_, _, unit, _, spellID)
            if not unit then return end
            -- Only count player units (raid1..40, party1..4, player). Skips NPCs.
            if unit ~= "player"
               and not unit:match("^raid%d+$")
               and not unit:match("^party%d+$") then
                return
            end
            local guid = UnitGUID(unit)
            if not guid then return end
            cast_counts[guid] = (cast_counts[guid] or 0) + 1

            -- Teamwork credit: support spell OR CC spell on enemy.
            -- spellID can be a SECRET VALUE (12.0.5 taint system) — wrap
            -- the MechanicConfigs lookups in pcall so taint propagation
            -- doesn't break the addon. issecretvalue check is the cheaper
            -- guard; pcall is the safety net.
            if spellID and not (issecretvalue and issecretvalue(spellID))
               and VoidScout.MechanicConfigs then
                local _, classFile = UnitClass(unit)
                if classFile then
                    local ok, matched = pcall(function()
                        return VoidScout.MechanicConfigs.IsUniversalTeamworkSpell(spellID, classFile)
                            or VoidScout.MechanicConfigs.IsCCSpell(spellID, classFile)
                    end)
                    if ok and matched then
                        teamwork_counts[guid] = (teamwork_counts[guid] or 0) + 1
                    end
                end
            end
        end)
    end
    cast_frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

local function StopActivityTracking()
    if cast_frame then cast_frame:UnregisterAllEvents() end
end

-- Exposed for ScoreEngine to read at ENCOUNTER_END
function mod:GetCastCounts()
    return cast_counts
end
function mod:GetTeamworkCounts()
    return teamwork_counts
end

----------------------------------------------------------------------
-- Event handlers
----------------------------------------------------------------------
local function OnEncounterStart(encounterID, encounterName, difficultyID, groupSize, instanceID)
    -- Auto-enable /combatlog so the encounter's events are written to disk
    -- for backend re-scoring. Safe to call inside M+ (nested context).
    cl_start()
    -- DEBUG: loud trace so user can verify event firing during M+
    local _, inst_type_dbg = GetInstanceInfo()
    local kl = (C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo and C_ChallengeMode.GetActiveKeystoneInfo()) or 0
    vs_dbg("ENCOUNTER_START id=%s name=%s diff=%s instType=%s keystoneLvl=%s",
        tostring(encounterID), tostring(encounterName), tostring(difficultyID),
        tostring(inst_type_dbg), tostring(kl))
    -- Capture leader and roster as the pull begins
    local leader_name, leader_guid = GetGroupLeader()
    local pug = EnsurePugSession(leader_name, leader_guid)
    local roster = CaptureRoster()

    current_fight = {
        encounter_id = encounterID,
        encounter_name = encounterName or "",
        difficulty_id = difficultyID,
        difficulty_name = DIFF_NAMES[difficultyID] or tostring(difficultyID),
        group_size = groupSize,
        instance_id = instanceID,
        start_ts = GetServerTime(),
        start_game_time = GetTime(),
        label_snapshot = SnapshotLabel(),
        leader_name = leader_name,
        leader_guid = leader_guid,
        pug_id      = pug and pug.pug_id or nil,
        roster      = roster,
    }
    boss_encounter_active = true  -- trash capture skips while a boss is in progress
    StartActivityTracking()

    -- ScoreEngine.StartFight intentionally NOT called. Scoring happens
    -- via external disk-log parser (Python on user's machine or NAS).
    -- Print start hint with leader (if any)
    local leader_str = leader_name and (" • led by |c%s%s|r"):format(C.dim, leader_name) or ""
    print(("|c%sVoidScout:|r tracking %s (%s, %dp) as |c%s%s|r%s"):format(
        C.accent,
        encounterName or "encounter " .. tostring(encounterID),
        current_fight.difficulty_name,
        groupSize or 0,
        C.accent,
        current_fight.label_snapshot.code,
        leader_str))
end

local function OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    -- Pop the encounter logging context. If we're not also inside an M+
    -- run, this disables /combatlog. Inside a run, the run-level toggle
    -- keeps it on until CHALLENGE_MODE_COMPLETED/RESET.
    cl_stop()
    vs_dbg("ENCOUNTER_END id=%s name=%s diff=%s success=%s current_fight=%s",
        tostring(encounterID), tostring(encounterName), tostring(difficultyID),
        tostring(success), current_fight and tostring(current_fight.encounter_id) or "nil")
    if not current_fight or current_fight.encounter_id ~= encounterID then
        vs_dbg("ENCOUNTER_END skipped — no matching current_fight")
        -- mismatched end (started before reload, or wrong fight) — skip
        current_fight = nil
        boss_encounter_active = false
        return
    end
    boss_encounter_active = false  -- boss done → next combat is trash again

    StopActivityTracking()

    local end_ts = GetServerTime()
    local end_game_time = GetTime()
    local dur_sec = end_game_time - current_fight.start_game_time
    local killed = (success == 1) or (success == true)

    -- INSTANCE / MODE CLASSIFICATION
    --   raid          → mode "raid"
    --   M+ keystone   → mode "mplus" (per-boss; CHALLENGE_MODE_COMPLETED also
    --                   fires later with the run summary — both upload)
    --   non-key party → mode "dungeon"
    -- Mode classification. Priority:
    --   1) difficulty_id 8 = Mythic Keystone → always "mplus"  (most reliable signal)
    --   2) C_ChallengeMode.GetActiveKeystoneInfo() truthy → "mplus"
    --   3) GetInstanceInfo type "party" → "dungeon" (non-keystone party)
    --   4) GetInstanceInfo type "raid" → "raid"
    --   5) default → "raid"
    local fight_mode = "raid"
    local _, inst_type = GetInstanceInfo()
    local active_kl = 0
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        active_kl = C_ChallengeMode.GetActiveKeystoneInfo() or 0
    end
    if difficultyID == 8 or active_kl > 0 then
        fight_mode = "mplus"
    elseif inst_type == "party" then
        fight_mode = "dungeon"
    elseif inst_type == "raid" then
        fight_mode = "raid"
    end
    vs_dbg("ENCOUNTER_END will save as mode=%s killed=%s duration=%ds (instType=%s diff=%s kl=%s)",
        fight_mode, tostring(killed), math.floor(dur_sec),
        tostring(inst_type), tostring(difficultyID), tostring(active_kl))

    -- For M+ boss kills, override Blizzard's difficulty_id (always 8 =
    -- Mythic Keystone enum) with the ACTUAL keystone level so the server
    -- can filter "Arcanotron at +14" vs "Arcanotron at +20" properly.
    -- active_kl computed above from C_ChallengeMode.GetActiveKeystoneInfo().
    local saved_difficulty = current_fight.difficulty_id
    if fight_mode == "mplus" and active_kl and active_kl > 0 then
        saved_difficulty = active_kl
    end

    local entry = {
        encounter_id   = current_fight.encounter_id,
        encounter_name = current_fight.encounter_name,
        difficulty_id  = saved_difficulty,
        difficulty_name = current_fight.difficulty_name,
        group_size     = current_fight.group_size,
        instance_id    = current_fight.instance_id,
        start_ts       = current_fight.start_ts,
        end_ts         = end_ts,
        duration_sec   = dur_sec,
        outcome        = killed and "kill" or "wipe",
        label          = current_fight.label_snapshot,
        leader_name    = current_fight.leader_name,
        leader_guid    = current_fight.leader_guid,
        pug_id         = current_fight.pug_id,
        roster         = current_fight.roster,
        recorded_at    = GetServerTime(),
        addon_version  = VoidScout.VERSION,
        _backend_sent  = false,
        mode           = fight_mode,
    }

    AppendFightLog(entry)

    -- Capture per-axis scores from Blizzard's native damage meter API.
    -- Engine-tracked, taint-safe, deferred to out-of-combat automatically.
    if VoidScout.ScoreEngine and VoidScout.ScoreEngine.CaptureFromBlizzardMeter then
        VoidScout.ScoreEngine.CaptureFromBlizzardMeter(
            entry.encounter_id,
            entry.difficulty_id,
            entry.encounter_name,
            entry.duration_sec,
            function(card, err)
                if not card then
                    print(("|cffff8080VS scorer:|r %s"):format(err or "no card"))
                    return
                end
                -- Consent gate. In local-only or no-choice mode we don't
                -- persist roster-bearing fight summaries. The user still
                -- gets the in-chat "scored N players" feedback below; the
                -- bundle-backed panel/tooltip continue to work because
                -- they read VoidScoutBundle.lua, not VoidScoutDB.scores.
                if VoidScout_IsUploadAllowed and not VoidScout_IsUploadAllowed() then
                    return
                end
                VoidScoutDB.scores = VoidScoutDB.scores or {}
                local count = 0
                -- Identity for own-death override
                local self_player_name
                do
                    local pn, pr = UnitName("player")
                    if pn then
                        if not pr or pr == "" then
                            pr = (GetRealmName and GetRealmName() or ""):gsub("%s+", "")
                        end
                        self_player_name = (pr and pr ~= "") and (pn .. "-" .. pr) or pn
                    end
                end
                -- Compute aggregate group DPS for this fight
                local group_dmg_total, group_dps_total = 0, 0
                for _, axes in pairs(card.players) do
                    if axes.raw and axes.raw.damage_done then
                        group_dmg_total = group_dmg_total + axes.raw.damage_done
                    end
                end
                local cur_dur = (card and card.duration) or entry.duration_sec or 1
                if cur_dur < 1 then cur_dur = 1 end
                group_dps_total = group_dmg_total / cur_dur

                -- Forces % delta this pull
                local forces_end = read_forces_pct()
                local forces_gained = math.max(0, forces_end - pull_start_forces)

                for name, axes in pairs(card.players) do
                    -- Self deaths from PLAYER_DEAD tracker
                    if name == self_player_name and (self_deaths_this_pull or 0) > 0 then
                        axes.raw = axes.raw or {}
                        axes.raw.died = true
                        axes.raw.deaths = self_deaths_this_pull
                    end
                    -- Party member deaths from UNIT_HEALTH transitions
                    if member_deaths_this_pull[name] and member_deaths_this_pull[name] > 0 then
                        axes.raw = axes.raw or {}
                        axes.raw.died = true
                        axes.raw.deaths = math.max(axes.raw.deaths or 0, member_deaths_this_pull[name])
                    end
                    -- Stamp pull-level group metrics + buff snapshot on every player's record
                    axes.raw = axes.raw or {}
                    axes.raw.group_dps_total = group_dps_total
                    axes.raw.group_dmg_total = group_dmg_total
                    axes.raw.forces_pull_start = pull_start_forces
                    axes.raw.forces_pull_end = forces_end
                    axes.raw.forces_gained = forces_gained
                    axes.raw.buffs_at_pull_start = pull_start_buffs[name] or {}
                    -- Active DPS: damage_done / (duration - time spent dead)
                    local dt = dead_time_per_player[name] or 0
                    -- If they died but never rezzed before fight end, count
                    -- the open interval up to "now" as dead time
                    if dt == 0 and axes.raw.died and self_deaths_this_pull > 0 and name == self_player_name then
                        dt = 10 * (axes.raw.deaths or 1) -- conservative 10s/death floor
                    end
                    axes.raw.dead_seconds = dt
                    local active = (cur_dur or 1) - dt
                    if active < 1 then active = 1 end
                    axes.raw.active_time_sec = active
                    if axes.raw.damage_done then
                        axes.raw.active_dps = axes.raw.damage_done / active
                    end
                    local rec = VoidScoutDB.scores[name] or { fights = {} }
                    table.insert(rec.fights, {
                        encounter_id   = card.encounterID,
                        encounter_name = card.encounterName,
                        difficulty_id  = card.difficulty,
                        outcome        = entry.outcome,
                        duration_sec   = entry.duration_sec,
                        timestamp      = entry.end_ts,
                        pug_id         = entry.pug_id,
                        -- Class + spec from C_DamageMeter source (NeverSecret)
                        class          = axes.class,
                        spec           = axes.spec,
                        -- Roster present in the pull — used by server to
                        -- compute Commitment with the same logic as in-game
                        -- (was this player in the roster, regardless of
                        -- whether the addon scored their axes).
                        roster         = entry.roster,
                        -- Upload state — companion app flips to true after POST
                        uploaded       = false,
                        -- Fight mode: "raid" for ENCOUNTER_END, "mplus" for
                        -- CHALLENGE_MODE_COMPLETED. Uploader passes this to
                        -- the server which stores fights.mode for proper
                        -- raid/M+ separation on the website.
                        mode           = entry.mode or "raid",
                        axes = {
                            Damage     = axes.Damage,
                            Interrupts = axes.Interrupts,
                            Dispels    = axes.Dispels,
                            Avoidance  = axes.Avoidance,
                            Activity   = axes.Activity,
                            Survival   = axes.Survival,
                            Teamwork   = axes.Teamwork,
                        },
                        -- Raw values behind the percentile axes so we can
                        -- show "Damage 100 (47.2k DPS)" instead of just a
                        -- bucket. Built by ScoreEngine and copied here.
                        raw = axes.raw,
                        -- Run ID: links every fight in an M+ run together
                        -- so the aggregator counts 1 run = 1 event, not
                        -- 30+ pulls inflating averages. Nil for raid (one
                        -- ENCOUNTER = one event already).
                        run_id = current_run_id,
                        -- Data quality: "ok" = trust scores, "stale" =
                        -- DC/AFK/reset, exclude from peer pool aggregation
                        data_quality = axes.data_quality or "ok",
                    })
                    -- FIFO cap per player
                    do local _n=#rec.fights if _n>100 then local _d=math.max(1,math.floor(100*0.1)) local _m=_n-_d for _i=1,_m do rec.fights[_i]=rec.fights[_i+_d] end for _i=_m+1,_n do rec.fights[_i]=nil end end end
                    VoidScoutDB.scores[name] = rec
                    count = count + 1
                end
                print(("|cffffd100VoidScout:|r scored %d players for %s"):format(
                    count, card.encounterName or "fight"))
            end
        )
    end

    -- User-facing summary
    local color = killed and C.success or C.fail
    print(("|c%sVoidScout:|r %s — %s in %ds as |c%s%s|r (logged)"):format(
        C.accent,
        entry.encounter_name,
        ("|c%s%s|r"):format(color, killed and "KILL" or "wipe"),
        math.floor(dur_sec),
        C.accent,
        entry.label.code))

    current_fight = nil
end

----------------------------------------------------------------------
-- Reset pug session when player leaves group or leader transfers
----------------------------------------------------------------------
local function OnGroupChange()
    local leader_name, leader_guid = GetGroupLeader()
    if not leader_guid then
        -- Player left group / disbanded — end persisted pug
        SetPersistedPug(nil)
        return
    end
    -- Sync from SavedVariables if needed
    if not current_pug then current_pug = GetPersistedPug() end
    -- Leader changed mid-pug → new pug session
    if current_pug and current_pug.leader_guid ~= leader_guid then
        EnsurePugSession(leader_name, leader_guid)
    end
end

----------------------------------------------------------------------
-- Slash diagnostic — print recent fight log to chat
----------------------------------------------------------------------
function mod:DumpLog(n)
    n = n or 10
    local log = (VoidScoutDB and VoidScoutDB.fightLog) or {}
    if #log == 0 then
        print(("|c%sVoidScout:|r no fights logged yet."):format(C.accent))
        return
    end
    local startIdx = math.max(1, #log - n + 1)
    print(("|c%sVoidScout fight log — last %d of %d:|r"):format(C.accent, math.min(n, #log), #log))
    for i = startIdx, #log do
        local e = log[i]
        local outColor = (e.outcome == "kill") and C.success or C.fail
        local leader_str = e.leader_name and (" • |c%s%s|r"):format(C.dim, e.leader_name) or ""
        print(("  [%s] %s — |c%s%s|r %ds as |c%s%s|r%s"):format(
            date("%H:%M", e.end_ts),
            e.encounter_name,
            outColor,
            e.outcome:upper(),
            math.floor(e.duration_sec or 0),
            C.accent,
            e.label and e.label.code or "?",
            leader_str))
    end
end

----------------------------------------------------------------------
-- Pug summary — group fight log by pug_id and show commitment per pug
----------------------------------------------------------------------
function mod:DumpPugs()
    local log = (VoidScoutDB and VoidScoutDB.fightLog) or {}
    if #log == 0 then
        print(("|c%sVoidScout:|r no fights logged yet."):format(C.accent))
        return
    end
    -- Group by pug_id, preserving chronological order of first occurrence
    local pug_order, pugs = {}, {}
    for _, e in ipairs(log) do
        local key = e.pug_id or "(no leader)"
        if not pugs[key] then
            pugs[key] = { fights = {}, leader = e.leader_name or "(unknown)" }
            pug_order[#pug_order + 1] = key
        end
        table.insert(pugs[key].fights, e)
    end
    print(("|c%sVoidScout — %d pug sessions:|r"):format(C.accent, #pug_order))
    for _, key in ipairs(pug_order) do
        local p = pugs[key]
        local kills = 0
        for _, f in ipairs(p.fights) do if f.outcome == "kill" then kills = kills + 1 end end
        print(("  led by |c%s%s|r — %d attempts, %d kill%s"):format(
            C.accent, p.leader, #p.fights, kills, kills == 1 and "" or "s"))
    end
end

----------------------------------------------------------------------
-- Per-run M+ analysis: dump trash + boss pulls from the most recent
-- M+ run with per-pull axes for YOU. Compares against group context.
-- Used for "me vs group" diagnosis after a run.
----------------------------------------------------------------------
function mod:DumpLastRun()
    local me_full = nil
    do
        local n, realm = UnitName("player")
        local r = realm and realm ~= "" and realm
                  or (GetRealmName and GetRealmName():gsub("%s+", "") or "")
        me_full = r ~= "" and (n .. "-" .. r) or n
    end

    local scores = VoidScoutDB and VoidScoutDB.scores and VoidScoutDB.scores[me_full]
    if not scores or not scores.fights or #scores.fights == 0 then
        print(("|c%sVoidScout:|r no fight data for %s"):format(C.accent, me_full or "?"))
        return
    end

    -- Find the most recent M+ run by collecting consecutive mplus-mode
    -- fights ending at the latest timestamp. A "run" is any sequence
    -- of mode=mplus fights within 90 min of the previous one.
    local fights = scores.fights
    local last = fights[#fights]
    if not last or last.mode ~= "mplus" then
        print(("|c%sVoidScout:|r last fight (%s) was not M+; nothing to dump."):format(
            C.accent, last and last.encounter_name or "?"))
        return
    end

    -- Walk backwards collecting mplus fights within 90 min of each other
    local run_fights = { last }
    for i = #fights - 1, 1, -1 do
        local f = fights[i]
        if f.mode ~= "mplus" then break end
        local gap = (run_fights[#run_fights].timestamp or 0) - (f.timestamp or 0)
        if gap > 90 * 60 then break end
        table.insert(run_fights, f)
    end
    -- Reverse to chronological order
    local chrono = {}
    for i = #run_fights, 1, -1 do chrono[#chrono + 1] = run_fights[i] end

    print(("|c%sVoidScout — last M+ run, %d pull%s:|r"):format(
        C.accent, #chrono, #chrono == 1 and "" or "s"))

    local trash_n, boss_n = 0, 0
    for i, f in ipairs(chrono) do
        local kind = (f.encounter_id == 0) and "trash" or "boss"
        if kind == "trash" then trash_n = trash_n + 1 else boss_n = boss_n + 1 end
        local ax = f.axes or {}
        local out_color = (f.outcome == "kill") and C.success or (f.outcome == "trash") and C.dim or C.fail
        print(("  %d. [%s] |c%s%s|r %ds — %s"):format(
            i,
            date("%H:%M", f.timestamp or 0),
            out_color,
            f.encounter_name or "?",
            math.floor(f.duration_sec or 0),
            (kind == "boss") and f.outcome:upper() or "trash"))
        print(("       D:%s I:%s Disp:%s Av:%s Act:%s Surv:%s Tw:%s"):format(
            tostring(ax.Damage     or "-"),
            tostring(ax.Interrupts or "-"),
            tostring(ax.Dispels    or "-"),
            tostring(ax.Avoidance  or "-"),
            tostring(ax.Activity   or "-"),
            tostring(ax.Survival   or "-"),
            tostring(ax.Teamwork   or "-")))
    end

    print(("  |c%sTotals:|r %d trash pulls, %d boss pulls"):format(C.accent, trash_n, boss_n))

    -- Quick diagnostic: are most pulls scored 100? That means we have no
    -- peer pool (you = only sample). Normal during dogfooding.
    local all_100 = true
    for _, f in ipairs(chrono) do
        if (f.axes and f.axes.Damage and f.axes.Damage ~= 100) then all_100 = false; break end
    end
    if all_100 then
        print(("  |c%sNote:|r all axes = 100 (no peer pool yet — solo-bootstrap mode)"):format(C.dim))
    end
end

function mod:GetCurrentPug()
    return current_pug
end

----------------------------------------------------------------------
-- One-shot migration: merge fightLog entries from the same leader_guid
-- that were split into multiple pug_ids by /reload cycles. Walks the log
-- chronologically; consecutive entries with same leader_guid collapse
-- into the earliest pug_id of that leader's contiguous run.
-- Triggered manually via /vs mergepugs.
----------------------------------------------------------------------
function mod:MergeSplitPugs()
    local log = VoidScoutDB and VoidScoutDB.fightLog
    if not log or #log == 0 then
        print(("|c%sVoidScout:|r no fight log to merge."):format(C.accent))
        return
    end

    -- Sort by end_ts ascending (should already be, but ensure)
    table.sort(log, function(a, b) return (a.end_ts or 0) < (b.end_ts or 0) end)

    local last_guid, current_id = nil, nil
    local merged_count, total_pugs_before, total_pugs_after = 0, {}, {}
    for _, e in ipairs(log) do
        if e.pug_id then total_pugs_before[e.pug_id] = true end
        if e.leader_guid then
            if e.leader_guid == last_guid then
                -- Same leader as last fight, reuse the previous pug_id
                if e.pug_id ~= current_id then
                    e.pug_id = current_id
                    merged_count = merged_count + 1
                end
            else
                -- New leader — adopt this entry's pug_id as the anchor
                last_guid = e.leader_guid
                current_id = e.pug_id
            end
        else
            -- No leader (older entries) — leave as-is, treat as boundary
            last_guid, current_id = nil, nil
        end
        if e.pug_id then total_pugs_after[e.pug_id] = true end
    end

    local before, after = 0, 0
    for _ in pairs(total_pugs_before) do before = before + 1 end
    for _ in pairs(total_pugs_after)  do after  = after  + 1 end

    print(("|c%sVoidScout:|r merged %d fight entries — %d pugs -> %d pugs"):format(
        C.accent, merged_count, before, after))
end

function mod:ClearLog()
    if VoidScoutDB then
        VoidScoutDB.fightLog = {}
        print(("|c%sVoidScout:|r fight log cleared."):format(C.accent))
    end
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
----------------------------------------------------------------------
-- Safe CLEU handler v2 — issecretvalue-first pattern.
--
-- The 12.0.5 secret-value system makes enemy GUIDs/spellIDs secret values
-- inside instances. The cardinal rule (from [wow-12-issecretvalue-pattern])
-- is: NEVER call any operation on a value before checking issecretvalue().
-- Even :sub() on a secret string taints the result.
--
-- Strategy:
--   1) issecretvalue(srcGUID) GATE — bail BEFORE any string op if src is secret
--   2) Special-case UNIT_DIED so player deaths still register for Resilience
--      even when the killer is a secret enemy
--   3) After src clears the gate, check :sub() to confirm "Player-" prefix
--   4) Scrub amount/spellID/extra with issecretvalue before forwarding
--   5) Skip non-player sources (NPCs, vehicles) entirely — we only score
--      player performance
----------------------------------------------------------------------
local _issecret = _G.issecretvalue or function() return false end

local function safe_dispatch_cleu()
    if not current_fight then return end
    if not VoidScout.ScoreEngine then return end

    local ts, sub, hideC,
          srcGUID, srcName, srcF, srcRF,
          dstGUID, dstName, dstF, dstRF,
          spellID, spellName, spellSchool,
          amount, extra = CombatLogGetCurrentEventInfo()

    -- ── GATE 1: Source secret? ──
    -- If yes, the only useful case is UNIT_DIED on a player target (Resilience).
    if _issecret(srcGUID) then
        if sub == "UNIT_DIED" and not _issecret(dstGUID)
           and type(dstGUID) == "string" and dstGUID:sub(1, 7) == "Player-" then
            VoidScout.ScoreEngine.HandleEvent({
                ts, sub, hideC,
                nil, nil, nil, nil,            -- src scrubbed (was secret)
                dstGUID, dstName, dstF, dstRF,
                nil, nil, nil, nil, nil,
            })
        end
        return
    end

    -- ── GATE 2: srcGUID is safe. Is it a Player- prefix? ──
    if type(srcGUID) ~= "string" or srcGUID:sub(1, 7) ~= "Player-" then
        return
    end

    -- ── GATE 3: Scrub remaining potentially-secret fields ──
    local safe_amount  = amount
    if _issecret(amount)  then safe_amount  = nil end

    local safe_spellID = spellID
    if _issecret(spellID) then safe_spellID = nil end

    local safe_extra   = extra
    if _issecret(extra)   then safe_extra   = nil end

    -- dstGUID may also be a secret enemy (most player-source events target enemies)
    local safe_dstGUID  = dstGUID
    local safe_dstName  = dstName
    if _issecret(dstGUID) then
        safe_dstGUID = nil
        safe_dstName = nil
    end

    VoidScout.ScoreEngine.HandleEvent({
        ts, sub, hideC,
        srcGUID, srcName, srcF, srcRF,
        safe_dstGUID, safe_dstName, dstF, dstRF,
        safe_spellID, spellName, spellSchool,
        safe_amount, safe_extra,
    })
end

----------------------------------------------------------------------
-- M+ (Challenge Mode) tracking
--
-- An M+ run = one "fight" for scoring purposes. We treat the whole
-- dungeon as a single unit because the keystone level + completion
-- time are the meaningful comparison axes, not individual boss kills
-- (which all happen at the same key level).
--
-- CHALLENGE_MODE_START fires when the keystone is inserted + countdown
-- finishes (run actually starts). CHALLENGE_MODE_COMPLETED fires on
-- final boss kill (timed or over).
-- CHALLENGE_MODE_RESET fires if the run is abandoned/reset.
--
-- We use GetInstanceInfo() to get dungeon name + difficulty (challenge
-- mode), and C_ChallengeMode.GetActiveKeystoneInfo() for keystone level
-- + affixes.
----------------------------------------------------------------------
local function OnChallengeStart()
    -- Auto-enable /combatlog for the whole run (covers trash + bosses).
    -- Nested context: encounter starts inside keep the count > 0 so
    -- ENCOUNTER_END won't disable it mid-run.
    cl_start()
    -- New M+ run — reset run-scope counters
    self_deaths_this_run = 0
    self_deaths_this_pull = 0
    run_start_forces = 0  -- baseline; will start counting up
    dead_time_per_player = {}
    died_at_per_unit = {}
    local instanceName, _, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
    -- Keystone info: level, affix list, etc.
    local keystoneLevel = 0
    local affixes = nil
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local l, a = C_ChallengeMode.GetActiveKeystoneInfo()
        keystoneLevel = l or 0
        affixes = a
    end

    local leader_name, leader_guid = GetGroupLeader()
    local pug = EnsurePugSession(leader_name, leader_guid)
    local roster = CaptureRoster()
    local group_size = GetNumGroupMembers() or 5

    current_fight = {
        -- For M+ we use instanceID as encounter_id (e.g. 2287 = Halls of Atonement).
        -- This stays consistent across runs of the same dungeon.
        encounter_id    = instanceID or 0,
        encounter_name  = instanceName or ("Mythic+ " .. tostring(instanceID)),
        -- Use keystone level as the "difficulty" — directly comparable
        difficulty_id   = keystoneLevel,
        difficulty_name = keystoneLevel > 0 and ("+" .. keystoneLevel) or "M+",
        group_size      = group_size,
        instance_id     = instanceID,
        start_ts        = GetServerTime(),
        start_game_time = GetTime(),
        label_snapshot  = SnapshotLabel(),
        leader_name     = leader_name,
        leader_guid     = leader_guid,
        pug_id          = pug and pug.pug_id or nil,
        roster          = roster,
        mode            = "mplus",
        affixes         = affixes,
    }
    -- Generate run_id for this M+; every fight captured during this run
    -- (trash + boss) carries it so server can group by run.
    current_run_id = tostring(instanceID or 0) .. "_" .. tostring(GetServerTime())
    StartActivityTracking()

    local leader_str = leader_name and (" • led by |c%s%s|r"):format(C.dim, leader_name) or ""
    print(("|c%sVoidScout:|r tracking %s |c%s%s|r (M+, %dp)%s"):format(
        C.accent,
        instanceName or "dungeon",
        C.accent,
        current_fight.difficulty_name,
        group_size,
        leader_str))

    -- AUTO-FIRE: Probability Score prediction for this key.
    -- Persist BOTH the prediction and the eventual outcome so we can
    -- calibrate the model over time (/vs predictions).
    if VoidScout.TimerScore then
        -- Match expected ilvl baseline for THIS key bracket so non-self
        -- players (no inspect data) default to a realistic value, not a
        -- conservative 280.
        local expected_ilvl_for_key = 270
        if VoidScout.TimerData and VoidScout.TimerData.GetExpectedIlvl then
            expected_ilvl_for_key = VoidScout.TimerData:GetExpectedIlvl(keystoneLevel)
        end

        -- Build the group from current party. For each member, try PlayerScan
        -- cache first (deep_inspected records have spec + ilvl + rio). Fall
        -- back to expected-ilvl-for-key only if we have no inspect data.
        local players = {}
        local comp_str = {}
        for _, unit in ipairs({"player","party1","party2","party3","party4"}) do
            if UnitExists(unit) then
                local _, cls = UnitClass(unit)
                local spec, ilvl = nil, 0
                if unit == "player" then
                    local sid = GetSpecialization and GetSpecialization()
                    if sid then
                        local _, sn = GetSpecializationInfo(sid)
                        spec = sn
                    end
                    ilvl = math.floor(select(2, GetAverageItemLevel()) or 0)
                else
                    -- Other party members: pull from PlayerScan cache via GUID
                    if VoidScout.PlayerScan and VoidScout.PlayerScan.GetByGUID then
                        local guid = UnitGUID(unit)
                        if guid then
                            local rec = VoidScout.PlayerScan:GetByGUID(guid)
                            if rec then
                                if rec.spec then spec = rec.spec end
                                if rec.ilvl and rec.ilvl > 0 then ilvl = rec.ilvl end
                            end
                        end
                    end
                end
                if cls then
                    players[#players+1] = {
                        classFile = cls,
                        specName  = spec or "?",
                        ilvl      = (ilvl > 0) and ilvl or expected_ilvl_for_key,
                    }
                    comp_str[#comp_str+1] = cls
                end
            end
        end

        local grp = VoidScout.TimerScore:ScoreGroup(players, keystoneLevel, instanceID)
        local predicted = grp and grp.group_score or nil

        if predicted then
            print(("|c%sVoidScout Probability:|r |cffffcc00%d|r for +%d %s (group of %d)"):format(
                C.accent, predicted, keystoneLevel, instanceName or "dungeon", #players))
            print(("  Group: %s"):format(table.concat(comp_str, " . ")))
        end

        -- Persist prediction keyed by run_id for later calibration
        if current_run_id then
            VoidScoutDB.runs = VoidScoutDB.runs or {}
            VoidScoutDB.runs[current_run_id] = {
                run_id          = current_run_id,
                started_at      = GetServerTime(),
                dungeon_id      = instanceID,
                dungeon_name    = instanceName,
                keystone_level  = keystoneLevel,
                predicted_score = predicted,
                roster          = roster,
                group_comp      = comp_str,
                outcome         = "in_progress",
                addon_version   = VoidScout.VERSION,
            }
        end
    end
end

local function OnChallengeCompleted()
    -- Pop the run-level logging context. Last cl_stop disables /combatlog.
    cl_stop()
    vs_dbg("CHALLENGE_MODE_COMPLETED fired — current_fight mode=%s",
          tostring(current_fight and current_fight.mode or "nil"))

    -- Stamp prediction record BEFORE the current_fight guard. The last
    -- boss kill's ENCOUNTER_END handler clears current_fight earlier,
    -- so by the time CHALLENGE_MODE_COMPLETED fires, current_fight is
    -- nil and the rest of this function bails. The prediction record
    -- stamping doesn't need current_fight — just current_run_id.
    if current_run_id and VoidScoutDB.runs and VoidScoutDB.runs[current_run_id] then
        local rec = VoidScoutDB.runs[current_run_id]
        local cl_timed, cl_runTime = false, nil
        if C_ChallengeMode and C_ChallengeMode.GetCompletionInfo then
            local _, _, time, _onTime = C_ChallengeMode.GetCompletionInfo()
            cl_runTime = time
            cl_timed = (_onTime == true) or (_onTime == 1)
        end
        rec.completed_at   = GetServerTime()
        rec.actual_time_ms = cl_runTime
        rec.timed          = cl_timed
        rec.self_deaths    = self_deaths_this_run or 0
        local md_total = 0
        for _, n in pairs(member_deaths_this_pull or {}) do md_total = md_total + n end
        rec.member_deaths_last_pull = md_total
        rec.outcome = cl_timed and "timed" or "depleted"
        vs_dbg("prediction record stamped: %s, timed=%s", current_run_id, tostring(cl_timed))
    end

    if not current_fight or current_fight.mode ~= "mplus" then
        -- Clear run_id now that the prediction record is stamped
        current_run_id = nil
        return
    end
    StopActivityTracking()

    local end_ts = GetServerTime()
    local end_game_time = GetTime()
    local dur_sec = end_game_time - current_fight.start_game_time

    -- C_ChallengeMode.GetCompletionInfo returns (mapID, level, time_ms, onTime, ...)
    local timed, runTime, onTime = false, nil, nil
    if C_ChallengeMode and C_ChallengeMode.GetCompletionInfo then
        local _, _, time, _onTime = C_ChallengeMode.GetCompletionInfo()
        runTime = time
        onTime = _onTime
        timed = (_onTime == true) or (_onTime == 1)
    end

    -- (Prediction record stamping moved to top of function — see comment
    -- above; the current_fight guard would have caused us to skip it.)
    -- Refresh duration on the already-stamped record so we have the
    -- accurate fight-side duration too.
    if current_run_id and VoidScoutDB.runs and VoidScoutDB.runs[current_run_id] then
        VoidScoutDB.runs[current_run_id].duration_sec = dur_sec
    end

    local entry = {
        encounter_id    = current_fight.encounter_id,
        encounter_name  = current_fight.encounter_name,
        difficulty_id   = current_fight.difficulty_id,
        difficulty_name = current_fight.difficulty_name,
        group_size      = current_fight.group_size,
        instance_id     = current_fight.instance_id,
        start_ts        = current_fight.start_ts,
        end_ts          = end_ts,
        duration_sec    = dur_sec,
        -- For M+: "kill" = timed, "wipe" = depleted (over time)
        outcome         = timed and "kill" or "wipe",
        label           = current_fight.label_snapshot,
        leader_name     = current_fight.leader_name,
        leader_guid     = current_fight.leader_guid,
        pug_id          = current_fight.pug_id,
        roster          = current_fight.roster,
        recorded_at     = GetServerTime(),
        addon_version   = VoidScout.VERSION,
        _backend_sent   = false,
        mode            = "mplus",
    }
    AppendFightLog(entry)

    -- Same scoring path as raid — C_DamageMeter is encounter-agnostic
    if VoidScout.ScoreEngine and VoidScout.ScoreEngine.CaptureFromBlizzardMeter then
        VoidScout.ScoreEngine.CaptureFromBlizzardMeter(
            entry.encounter_id, entry.difficulty_id,
            entry.encounter_name, entry.duration_sec,
            function(card, err)
                if not card then
                    print(("|cffff8080VS scorer:|r %s"):format(err or "no card"))
                    return
                end
                -- Consent gate (M+ per-boss capture site).
                if VoidScout_IsUploadAllowed and not VoidScout_IsUploadAllowed() then
                    return
                end
                VoidScoutDB.scores = VoidScoutDB.scores or {}
                local count = 0
                -- Identity for own-death override
                local self_player_name
                do
                    local pn, pr = UnitName("player")
                    if pn then
                        if not pr or pr == "" then
                            pr = (GetRealmName and GetRealmName() or ""):gsub("%s+", "")
                        end
                        self_player_name = (pr and pr ~= "") and (pn .. "-" .. pr) or pn
                    end
                end
                -- Compute aggregate group DPS for this fight
                local group_dmg_total, group_dps_total = 0, 0
                for _, axes in pairs(card.players) do
                    if axes.raw and axes.raw.damage_done then
                        group_dmg_total = group_dmg_total + axes.raw.damage_done
                    end
                end
                local cur_dur = (card and card.duration) or entry.duration_sec or 1
                if cur_dur < 1 then cur_dur = 1 end
                group_dps_total = group_dmg_total / cur_dur

                -- Forces % delta this pull
                local forces_end = read_forces_pct()
                local forces_gained = math.max(0, forces_end - pull_start_forces)

                for name, axes in pairs(card.players) do
                    -- Self deaths from PLAYER_DEAD tracker
                    if name == self_player_name and (self_deaths_this_pull or 0) > 0 then
                        axes.raw = axes.raw or {}
                        axes.raw.died = true
                        axes.raw.deaths = self_deaths_this_pull
                    end
                    -- Party member deaths from UNIT_HEALTH transitions
                    if member_deaths_this_pull[name] and member_deaths_this_pull[name] > 0 then
                        axes.raw = axes.raw or {}
                        axes.raw.died = true
                        axes.raw.deaths = math.max(axes.raw.deaths or 0, member_deaths_this_pull[name])
                    end
                    -- Stamp pull-level group metrics + buff snapshot on every player's record
                    axes.raw = axes.raw or {}
                    axes.raw.group_dps_total = group_dps_total
                    axes.raw.group_dmg_total = group_dmg_total
                    axes.raw.forces_pull_start = pull_start_forces
                    axes.raw.forces_pull_end = forces_end
                    axes.raw.forces_gained = forces_gained
                    axes.raw.buffs_at_pull_start = pull_start_buffs[name] or {}
                    -- Active DPS: damage_done / (duration - time spent dead)
                    local dt = dead_time_per_player[name] or 0
                    -- If they died but never rezzed before fight end, count
                    -- the open interval up to "now" as dead time
                    if dt == 0 and axes.raw.died and self_deaths_this_pull > 0 and name == self_player_name then
                        dt = 10 * (axes.raw.deaths or 1) -- conservative 10s/death floor
                    end
                    axes.raw.dead_seconds = dt
                    local active = (cur_dur or 1) - dt
                    if active < 1 then active = 1 end
                    axes.raw.active_time_sec = active
                    if axes.raw.damage_done then
                        axes.raw.active_dps = axes.raw.damage_done / active
                    end
                    local rec = VoidScoutDB.scores[name] or { fights = {} }
                    table.insert(rec.fights, {
                        encounter_id   = card.encounterID,
                        encounter_name = card.encounterName,
                        difficulty_id  = card.difficulty,
                        outcome        = entry.outcome,
                        duration_sec   = entry.duration_sec,
                        timestamp      = entry.end_ts,
                        pug_id         = entry.pug_id,
                        class          = axes.class,
                        spec           = axes.spec,
                        roster         = entry.roster,
                        uploaded       = false,
                        mode           = "mplus",
                        axes = {
                            Damage     = axes.Damage,
                            Interrupts = axes.Interrupts,
                            Dispels    = axes.Dispels,
                            Avoidance  = axes.Avoidance,
                            Activity   = axes.Activity,
                            Survival   = axes.Survival,
                            Teamwork   = axes.Teamwork,
                        },
                        -- Raw values behind the percentile axes so we can
                        -- show "Damage 100 (47.2k DPS)" instead of just a
                        -- bucket. Built by ScoreEngine and copied here.
                        raw = axes.raw,
                        -- Run ID: links every fight in an M+ run together
                        -- so the aggregator counts 1 run = 1 event, not
                        -- 30+ pulls inflating averages. Nil for raid (one
                        -- ENCOUNTER = one event already).
                        run_id = current_run_id,
                        -- Data quality: "ok" = trust scores, "stale" =
                        -- DC/AFK/reset, exclude from peer pool aggregation
                        data_quality = axes.data_quality or "ok",
                    })
                    do local _n=#rec.fights if _n>100 then local _d=math.max(1,math.floor(100*0.1)) local _m=_n-_d for _i=1,_m do rec.fights[_i]=rec.fights[_i+_d] end for _i=_m+1,_n do rec.fights[_i]=nil end end end
                    VoidScoutDB.scores[name] = rec
                    count = count + 1
                end
                print(("|cffffd100VoidScout:|r scored %d players for %s %s"):format(
                    count, card.encounterName or "dungeon",
                    timed and "(timed)" or "(over)"))
            end
        )
    end

    local color = timed and C.success or C.fail
    print(("|c%sVoidScout:|r %s %s — %s in %ds (logged)"):format(
        C.accent, entry.encounter_name, entry.difficulty_name,
        ("|c%s%s|r"):format(color, timed and "TIMED" or "OVER"),
        math.floor(dur_sec)))
    current_fight = nil

    -- AUTO-FIRE: per-pull breakdown for the run we just finished.
    -- Defer 2.5s so the last trash/boss capture has time to land in
    -- SavedVariables (CaptureFromBlizzardMeter has its own 0.5s defer
    -- on top of out-of-combat detection).
    C_Timer.After(2.5, function()
        print(("|c%s───── M+ run summary (%s) ─────|r"):format(
            C.accent, timed and "TIMED" or "OVER"))
        if mod.DumpLastRun then mod:DumpLastRun() end
    end)
    current_run_id = nil  -- run done, no more captures tagged to it
end

local function OnChallengeReset()
    -- Abandoned run — pop the logging context so /combatlog stops too
    cl_stop()
    vs_dbg("CHALLENGE_MODE_RESET fired (key abandoned/reset)")
    -- Stamp the in-progress prediction record as abandoned
    if current_run_id and VoidScoutDB.runs and VoidScoutDB.runs[current_run_id] then
        local rec = VoidScoutDB.runs[current_run_id]
        rec.completed_at = GetServerTime()
        rec.outcome = "abandoned"
        rec.timed = false
    end
    -- Run abandoned without completion. Don't drop the data — auto-dump
    -- what we captured so the user can review who showed up and who didn't.
    if current_fight and current_fight.mode == "mplus" then
        StopActivityTracking()
        current_fight = nil
    end
    boss_encounter_active = false  -- next run starts clean
    C_Timer.After(2.5, function()
        print(("|c%s───── M+ run summary (ABANDONED) ─────|r"):format(C.fail))
        if mod.DumpLastRun then mod:DumpLastRun() end
    end)
    current_run_id = nil
end

----------------------------------------------------------------------
-- M+ trash-pull capture
--
-- ENCOUNTER_START/END only fires for boss pulls. Without trash capture
-- we miss 40-60% of meaningful M+ time — the wall pulls where:
--   * polymorph on a DPS = 8s of lost throughput
--   * healer runs OOM and lets the tank eat it
--   * the warrior never interrupts Lightning Bolt
--
-- Design: a trash pull = combat state with NO active boss encounter.
--   PLAYER_REGEN_DISABLED (combat begins) AND in M+ AND no current_fight
--     → start tracking a trash pull
--   PLAYER_REGEN_ENABLED (combat ends) AND we were tracking
--     → capture C_DamageMeter session (deferred), persist as mode="mplus_trash"
----------------------------------------------------------------------
local current_trash_pull = nil  -- { start_ts, start_game_time, leader_name, leader_guid, pug_id, roster }

local function InActiveChallenge()
    if not (C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo) then
        return false
    end
    local kl = C_ChallengeMode.GetActiveKeystoneInfo() or 0
    return kl > 0
end

local function OnPlayerRegenDisabled()
    -- Reset per-combat self-death counter (carried into the fight save)
    self_deaths_this_pull = 0
    member_deaths_this_pull = {}
    dead_time_per_player = {}
    died_at_per_unit = {}
    -- Snapshot current alive/dead state so we only count NEW deaths.
    -- Include player + party + raid units so raid encounters with 5-40
    -- group members all get baseline state.
    member_was_alive = { ["player"] = not UnitIsDeadOrGhost("player") }
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            member_was_alive[u] = not UnitIsDeadOrGhost(u)
        end
    end
    for i = 1, 40 do
        local u = "raid" .. i
        if UnitExists(u) then
            member_was_alive[u] = not UnitIsDeadOrGhost(u)
        end
    end
    -- Snapshot scenario forces + group buffs (only meaningful in M+)
    pull_start_forces = read_forces_pct()
    snapshot_pull_buffs()
    vs_dbg("PLAYER_REGEN_DISABLED (combat start) — boss=%s, inM+=%s",
        tostring(boss_encounter_active), tostring(InActiveChallenge()))
    -- Boss pull already captured by ENCOUNTER_START path; skip
    if boss_encounter_active then return end
    if not InActiveChallenge() then return end
    vs_dbg("starting trash-pull capture")

    local leader_name, leader_guid = GetGroupLeader()
    local pug = EnsurePugSession(leader_name, leader_guid)
    local roster = CaptureRoster()
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()

    current_trash_pull = {
        start_ts        = GetServerTime(),
        start_game_time = GetTime(),
        leader_name     = leader_name,
        leader_guid     = leader_guid,
        pug_id          = pug and pug.pug_id or nil,
        roster          = roster,
        instance_id     = instanceID,
        label_snapshot  = SnapshotLabel(),
    }
    StartActivityTracking()
end

local function OnPlayerRegenEnabled()
    if not current_trash_pull then return end
    local pull = current_trash_pull
    current_trash_pull = nil
    StopActivityTracking()

    local end_ts = GetServerTime()
    local dur_sec = GetTime() - pull.start_game_time

    -- Ignore micro-pulls (< 3s) — usually a single mob misclick, adds no signal
    if dur_sec < 3 then return end

    -- Read the just-ended Current session out-of-combat. Same defer pattern
    -- as boss capture: 0.5s lets Blizzard finalize the session totals.
    if not (VoidScout.ScoreEngine and VoidScout.ScoreEngine.CaptureFromBlizzardMeter) then
        return
    end

    -- We use encounter_id=0 for trash pulls (no boss); encounter_name uses
    -- the dungeon name + pull duration as a human-readable identifier.
    local inst_name = GetInstanceInfo() or "Dungeon"
    local pull_name = ("%s trash (%ds)"):format(inst_name, math.floor(dur_sec))

    VoidScout.ScoreEngine.CaptureFromBlizzardMeter(
        0,  -- encounter_id 0 = trash pull
        0,  -- difficulty unused for trash
        pull_name,
        dur_sec,
        function(card, err)
            if not card then return end  -- silent; trash pulls are noisy
            -- Consent gate (M+ trash pull site).
            if VoidScout_IsUploadAllowed and not VoidScout_IsUploadAllowed() then
                return
            end
            VoidScoutDB.scores = VoidScoutDB.scores or {}
            for name, axes in pairs(card.players) do
                local rec = VoidScoutDB.scores[name] or { fights = {} }
                table.insert(rec.fights, {
                    encounter_id   = 0,
                    encounter_name = pull_name,
                    difficulty_id  = 0,
                    outcome        = "trash",
                    duration_sec   = dur_sec,
                    timestamp      = end_ts,
                    pug_id         = pull.pug_id,
                    class          = axes.class,
                    spec           = axes.spec,
                    roster         = pull.roster,
                    uploaded       = false,
                    -- mode="mplus" + encounter_id=0 is the trash-pull marker
                    -- (no need for a new server enum; server already filters
                    -- non-current-tier encounter_ids out of util_score).
                    mode           = "mplus",
                    axes = {
                        Damage     = axes.Damage,
                        Interrupts = axes.Interrupts,
                        Dispels    = axes.Dispels,
                        Avoidance  = axes.Avoidance,
                        Activity   = axes.Activity,
                        Survival   = axes.Survival,
                        Teamwork   = axes.Teamwork,
                    },
                    raw = axes.raw,
                    run_id = current_run_id,
                    data_quality = axes.data_quality or "ok",
                })
                do local _n=#rec.fights if _n>100 then local _d=math.max(1,math.floor(100*0.1)) local _m=_n-_d for _i=1,_m do rec.fights[_i]=rec.fights[_i+_d] end for _i=_m+1,_n do rec.fights[_i]=nil end end end
                VoidScoutDB.scores[name] = rec
            end
            print(("|c%sVoidScout:|r trash pull captured — %ds, %d players"):format(
                C.accent, math.floor(dur_sec),
                (function() local n=0 for _ in pairs(card.players) do n=n+1 end return n end)()))
        end
    )
end

function mod:Init()
    -- Reconcile orphaned combatlog state from a prior reload mid-key.
    reconcile_cl_state_on_load()

    local f = CreateFrame("Frame")
    f:RegisterEvent("ENCOUNTER_START")
    f:RegisterEvent("ENCOUNTER_END")
    f:RegisterEvent("CHALLENGE_MODE_START")
    f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    f:RegisterEvent("CHALLENGE_MODE_RESET")
    -- PEW backfill for the case where CHALLENGE_MODE_START did NOT fire
    -- on this client — typically: joining a M+ in progress (replacing a
    -- dropped player), /reload mid-run, or addon loaded after countdown.
    -- See OnPlayerEnteringWorldChallengeCheck() below.
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PARTY_LEADER_CHANGED")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- Death tracking. C_DamageMeter.deathTimeSeconds is secret-tainted in
    -- cross-realm M+ groups (returns nil from safe_num). PLAYER_DEAD for
    -- self, UNIT_HEALTH for party members.
    f:RegisterEvent("PLAYER_DEAD")
    f:RegisterEvent("PLAYER_ALIVE")
    f:RegisterEvent("PLAYER_UNGHOST")
    -- UNIT_HEALTH for self + all party/raid members. RegisterUnitEvent
    -- has a small arg cap; register the full set across multiple calls.
    -- Order: player + party (M+) + raid1..raid40 (mythic raid).
    f:RegisterUnitEvent("UNIT_HEALTH", "player", "party1", "party2", "party3", "party4")
    for i = 1, 40 do
        f:RegisterUnitEvent("UNIT_HEALTH", "raid" .. i)
    end
    -- CLEU PERMANENTLY DISABLED — pivoted to disk-log + external scorer pipeline.
    -- WoW's secret-value system makes in-game scoring brittle without a full-time
    -- taint maintenance team. See [voidscout-data-sources] memory for new design.
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "ENCOUNTER_START" then
            OnEncounterStart(...)
        elseif event == "ENCOUNTER_END" then
            OnEncounterEnd(...)
        elseif event == "CHALLENGE_MODE_START" then
            OnChallengeStart()
        elseif event == "CHALLENGE_MODE_COMPLETED" then
            OnChallengeCompleted()
        elseif event == "CHALLENGE_MODE_RESET" then
            OnChallengeReset()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Defer 1.5s so GetInstanceInfo + C_ChallengeMode APIs are
            -- populated (these can return placeholder data the first
            -- instant after zone-in).
            C_Timer.After(1.5, function()
                if current_run_id then return end  -- normal flow already fired
                if not (C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID) then return end
                local mapID = C_ChallengeMode.GetActiveChallengeMapID()
                if not mapID or mapID == 0 then return end
                -- We're in an active M+ but no run_id was generated —
                -- CHALLENGE_MODE_START missed this client. Backfill.
                print(("|c%sVoidScout:|r CHALLENGE_MODE_START missed (joined in progress / reloaded) — backfilling run record."):format(C.accent))
                OnChallengeStart()
            end)
        elseif event == "PARTY_LEADER_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
            OnGroupChange()
        elseif event == "PLAYER_REGEN_DISABLED" then
            OnPlayerRegenDisabled()
        elseif event == "PLAYER_REGEN_ENABLED" then
            OnPlayerRegenEnabled()
        elseif event == "PLAYER_DEAD" then
            -- Only count if we're in a tracked fight
            if current_fight or boss_encounter_active then
                self_deaths_this_pull = (self_deaths_this_pull or 0) + 1
                self_deaths_this_run = (self_deaths_this_run or 0) + 1
                died_at_per_unit["player"] = GetTime()
            end
        elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
            -- Player came back to life — close out the dead interval
            if died_at_per_unit["player"] then
                local pn, pr = UnitName("player")
                if pn then
                    if not pr or pr == "" then
                        pr = (GetRealmName and GetRealmName() or ""):gsub("%s+", "")
                    end
                    local full = (pr and pr ~= "") and (pn .. "-" .. pr) or pn
                    local delta = GetTime() - died_at_per_unit["player"]
                    dead_time_per_player[full] = (dead_time_per_player[full] or 0) + delta
                    died_at_per_unit["player"] = nil
                end
            end
        elseif event == "UNIT_HEALTH" then
            -- Detect alive->dead and dead->alive transitions on party members
            local unit = ...
            if unit and (current_fight or boss_encounter_active) then
                local is_dead = UnitIsDeadOrGhost(unit) and true or false
                local was_alive = member_was_alive[unit]
                local n, r = UnitName(unit)
                local full
                if n and n ~= "Unknown" then
                    if not r or r == "" then
                        r = (GetRealmName and GetRealmName() or ""):gsub("%s+", "")
                    end
                    full = (r and r ~= "") and (n .. "-" .. r) or n
                end
                if was_alive == true and is_dead then
                    -- Just died: count the death + stamp the dead-from time
                    if full then
                        member_deaths_this_pull[full] = (member_deaths_this_pull[full] or 0) + 1
                    end
                    died_at_per_unit[unit] = GetTime()
                elseif was_alive == false and not is_dead and died_at_per_unit[unit] then
                    -- Came back to life: accumulate dead-time interval
                    if full then
                        local delta = GetTime() - died_at_per_unit[unit]
                        dead_time_per_player[full] = (dead_time_per_player[full] or 0) + delta
                    end
                    died_at_per_unit[unit] = nil
                end
                member_was_alive[unit] = not is_dead
            end
        end
    end)
    mod._frame = f
end

-- Stub left in so /vs cleu on still works as a no-op (silent ignore)
-- in case any old slash commands or saved variables reference it.
function mod:SetCLEU(on)
    VoidScoutDB.cleuEnabled = false
    if on then
        print("|cffff8080VoidScout:|r CLEU scoring is permanently disabled (taint risk). " ..
              "Use external disk-log parser instead.")
    end
end
