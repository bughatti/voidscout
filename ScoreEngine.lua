----------------------------------------------------------------------
-- VoidScout ScoreEngine v2 — C_DamageMeter-based scoring.
--
-- Replaces the failed CLEU integration. Uses Blizzard's official damage
-- meter API which is engine-tracked, taint-safe, and exposes every
-- metric we need as a clean enum-keyed query.
--
-- Flow:
--   1) FightRecorder calls SE.CaptureFromBlizzardMeter(encounterID, difficulty,
--      encounterName, durationSec) when ENCOUNTER_END fires.
--   2) If still in combat (some APIs are SecretWhenInCombat), defers via
--      PLAYER_REGEN_ENABLED listener and retries.
--   3) Pulls Current session data for: DamageDone, HealingDone, Interrupts,
--      AvoidableDamageTaken, Deaths.
--   4) Aggregates per-player scorecard, computes axes via within-raid
--      percentile + severity tiers.
--   5) Returns scorecard for FightRecorder to persist into VoidScoutDB.scores.
--
-- Pets are already attributed to owners by Blizzard's engine (via
-- DamageMeterOverrideType.RedirectSourceToOwner) — no manual pet tracking needed.
----------------------------------------------------------------------

VoidScout = VoidScout or {}
VoidScout.ScoreEngine = {}

local SE = VoidScout.ScoreEngine

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function percentile(value, pool)
    if not pool or #pool == 0 then return 50 end
    local cnt = 0
    for _, v in ipairs(pool) do
        if v <= value then cnt = cnt + 1 end
    end
    return math.floor((cnt / #pool) * 100 + 0.5)
end

-- Inverse percentile: lower value = higher score. Used for axes where
-- "less is better" (avoidable damage taken, deaths). 0 in the pool is
-- the best possible — everyone with 0 ties at 100. Anyone above 0
-- ranks against the others.
local function percentile_inverse(value, pool)
    if not pool or #pool == 0 then return 100 end
    -- If everyone (including you) took zero avoidable damage, perfect run
    local any_nonzero = false
    for _, v in ipairs(pool) do if (v or 0) > 0 then any_nonzero = true; break end end
    if not any_nonzero then return 100 end
    -- Count how many in the pool took MORE damage than you (you outrank them)
    local cnt = 0
    for _, v in ipairs(pool) do
        if (v or 0) > value then cnt = cnt + 1 end
    end
    return math.floor((cnt / #pool) * 100 + 0.5)
end

local function is_ally(source)
    if not source then return false end
    -- sourceDisplayType is secret-tainted on cross-realm members in 12.0.5.
    -- Comparing it directly propagates taint into VoidScout's call frame
    -- and triggers "blocked from action" popups later. Gate the read with
    -- issecretvalue() before touching it. classFilename is the safe
    -- fallback — it's never secret for valid party/raid members.
    local sdt = source.sourceDisplayType
    if sdt ~= nil and not (issecretvalue and issecretvalue(sdt)) then
        if sdt == Enum.DamageMeterSourceDisplayType.Ally then return true end
    end
    return source.classFilename and source.classFilename ~= "" and source.classFilename ~= "NONE"
end

----------------------------------------------------------------------
-- Pull a session safely. Returns combatSources array or nil.
----------------------------------------------------------------------
local function pull_session(metricType)
    if not C_DamageMeter or not C_DamageMeter.GetCombatSessionFromType then return nil end
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
        Enum.DamageMeterSessionType.Current, metricType)
    if not ok or not session or not session.combatSources then return nil end
    return session
end

-- Strip secret-tainted numbers. C_DamageMeter session fields (totalAmount,
-- amountPerSecond, durationSeconds, deathTimeSeconds) come back as secret
-- numbers when the group contains cross-realm players in instances. Any
-- comparison/arithmetic on a secret number throws "secret number value
-- while execution tainted". Pre-check + fall through to default.
local function safe_num(v, default)
    if v == nil then return default end
    if _issecret and _issecret(v) then return default end
    if type(v) ~= "number" then return default end
    return v
end

----------------------------------------------------------------------
-- Core capture: read all metrics, build per-player aggregate.
-- KEY DEFENSIVE PATTERN: never read source.name (ConditionalSecret).
-- Use source.sourceGUID and map to a clean name via our own roster.
----------------------------------------------------------------------
local _issecret = _G.issecretvalue or function() return false end

local function build_guid_to_name()
    -- Build a GUID -> "Name-Realm" map from raid/party members using
    -- safe UnitGUID/UnitName calls. These are clean for group members
    -- regardless of instance, unlike C_DamageMeter source names.
    local map = {}
    local function add(unit)
        if not UnitExists(unit) then return end
        local guid = UnitGUID(unit)
        if not guid or _issecret(guid) then return end
        local n, realm = UnitName(unit)
        if not n then return end
        -- UnitName returns realm="" for your OWN character on home realm,
        -- which would store bare "Vede" instead of "Vede-Elune". Fall back
        -- to GetRealmName() so own-character entries get full identity too.
        if not realm or realm == "" then
            realm = GetRealmName and GetRealmName() or ""
            -- Strip spaces from realm to match cross-realm format ("Mal'Ganis", not "Mal'Ganis")
            if realm then realm = realm:gsub("%s+", "") end
        end
        local full = (realm and realm ~= "") and (n .. "-" .. realm) or n
        map[guid] = full
    end
    add("player")
    if IsInRaid() then
        for i = 1, 40 do add("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, 4 do add("party" .. i) end
    end
    return map
end

local function build_scorecard(encounterID, difficulty, encounterName, durationSec)
    if not C_DamageMeter then
        return nil, "C_DamageMeter API unavailable"
    end
    local avail, reason = C_DamageMeter.IsDamageMeterAvailable()
    if not avail then
        return nil, "DamageMeter not available: " .. tostring(reason)
    end

    -- Build clean GUID → name lookup from group roster BEFORE touching meter data
    local guid_to_name = build_guid_to_name()

    -- Pull each metric we care about
    local damageSession   = pull_session(Enum.DamageMeterType.DamageDone)
    local healSession     = pull_session(Enum.DamageMeterType.HealingDone)
    local interruptSession= pull_session(Enum.DamageMeterType.Interrupts)
    local avoidSession    = pull_session(Enum.DamageMeterType.AvoidableDamageTaken)
    local deathsSession   = pull_session(Enum.DamageMeterType.Deaths)
    local dispelsSession  = pull_session(Enum.DamageMeterType.Dispels)

    if not damageSession then
        return nil, "no damage session returned"
    end

    -- Use session duration if Blizzard provides it; fall back to our timing.
    -- damageSession.durationSeconds is sometimes a secret number (cross-realm
    -- M+ groups). Comparison ops on secret numbers throw "attempt to compare
    -- a secret number value, while execution tainted by 'VoidScout'". Guard
    -- with issecretvalue BEFORE touching it; fall through to durationSec.
    local dur
    local sessionDur = damageSession.durationSeconds
    if sessionDur ~= nil and not _issecret(sessionDur) then
        dur = sessionDur
    else
        dur = durationSec
    end
    if not dur or dur < 1 then dur = 1 end

    -- Index per player keyed by GUID (never name; name is ConditionalSecret)
    local players = {}
    local function get_or_create(source)
        if not source then return nil end
        -- Filter on sourceGUID — never touch source.name (ConditionalSecret)
        local guid = source.sourceGUID
        if not guid then return nil end
        if _issecret(guid) then return nil end
        -- Only score players we recognize in our group (skips other-raid sources)
        local clean_name = guid_to_name[guid]
        if not clean_name then return nil end
        if not players[guid] then
            players[guid] = {
                guid = guid,
                name = clean_name,
                class = source.classFilename,  -- NeverSecret per API
                damage_done = 0,
                heal_done = 0,
                interrupts = 0,
                dispels = 0,
                casts = 0,        -- filled from FightRecorder's cast tracker
                teamwork = 0,     -- filled from FightRecorder's teamwork tracker
                avoidable_taken = 0,
                died = false,
                death_time = nil,  -- seconds into the fight when they died (nil = survived)
            }
        end
        return players[guid]
    end

    -- DamageDone
    for _, src in ipairs(damageSession.combatSources or {}) do
        if is_ally(src) then
            local p = get_or_create(src)
            if p then
                p.damage_done = safe_num(src.totalAmount, 0)
                local aps = safe_num(src.amountPerSecond, 0)
                p.dps = aps > 0 and aps or (p.damage_done / dur)
                local dt = safe_num(src.deathTimeSeconds, 0)
                if dt > 0 then
                    p.died = true
                    -- Take the earliest death time we see across sessions
                    if not p.death_time or dt < p.death_time then
                        p.death_time = dt
                    end
                end
            end
        end
    end

    -- HealingDone
    if healSession then
        for _, src in ipairs(healSession.combatSources or {}) do
            if is_ally(src) then
                local p = get_or_create(src)
                if p then
                    p.heal_done = safe_num(src.totalAmount, 0)
                    p.hps = safe_num(src.amountPerSecond, 0)
                end
            end
        end
    end

    -- Interrupts
    if interruptSession then
        for _, src in ipairs(interruptSession.combatSources or {}) do
            if is_ally(src) then
                local p = get_or_create(src)
                if p then p.interrupts = safe_num(src.totalAmount, 0) end
            end
        end
    end

    -- AvoidableDamageTaken
    if avoidSession then
        for _, src in ipairs(avoidSession.combatSources or {}) do
            if is_ally(src) then
                local p = get_or_create(src)
                if p then p.avoidable_taken = safe_num(src.totalAmount, 0) end
            end
        end
    end

    -- Dispels
    if dispelsSession then
        for _, src in ipairs(dispelsSession.combatSources or {}) do
            if is_ally(src) then
                local p = get_or_create(src)
                if p then p.dispels = safe_num(src.totalAmount, 0) end
            end
        end
    end

    -- Deaths
    if deathsSession then
        for _, src in ipairs(deathsSession.combatSources or {}) do
            if is_ally(src) then
                local p = get_or_create(src)
                if p and safe_num(src.totalAmount, 0) > 0 then
                    p.died = true
                    local dt = safe_num(src.deathTimeSeconds, 0)
                    if dt > 0 then
                        if not p.death_time or dt < p.death_time then
                            p.death_time = dt
                        end
                    end
                end
            end
        end
    end

    -- Pull cast tracker data from FightRecorder (Activity axis)
    local cast_counts = (VoidScout.FightRecorder and VoidScout.FightRecorder.GetCastCounts
                         and VoidScout.FightRecorder:GetCastCounts()) or {}
    for guid, count in pairs(cast_counts) do
        if players[guid] then players[guid].casts = count end
    end

    -- Pull teamwork tracker data from FightRecorder (Teamwork axis)
    local teamwork_counts = (VoidScout.FightRecorder and VoidScout.FightRecorder.GetTeamworkCounts
                             and VoidScout.FightRecorder:GetTeamworkCounts()) or {}
    for guid, count in pairs(teamwork_counts) do
        if players[guid] then players[guid].teamwork = count end
    end

    -- Build percentile pools
    local dps_pool, hps_pool, interrupt_pool, dispel_pool, cps_pool, teamwork_pool, avoid_pool = {}, {}, {}, {}, {}, {}, {}
    for _, p in pairs(players) do
        table.insert(dps_pool, p.dps or 0)
        if (p.heal_done or 0) > 0 then table.insert(hps_pool, p.hps or 0) end
        table.insert(interrupt_pool, p.interrupts or 0)
        table.insert(dispel_pool, p.dispels or 0)
        -- casts per second normalises across fight length
        table.insert(cps_pool, (p.casts or 0) / dur)
        -- teamwork actions per second
        table.insert(teamwork_pool, (p.teamwork or 0) / dur)
        -- avoidable damage taken — less is better, scored via percentile_inverse
        table.insert(avoid_pool, p.avoidable_taken or 0)
    end

    ----------------------------------------------------------------------
    -- Mass-wipe cluster detection (for fair Survival scoring)
    --
    -- If >=50% of the group dies within an 8-second window AND the fight
    -- is a wipe, that cluster represents the "effective end" of the fight.
    -- Stragglers who linger and die later shouldn't get bonus credit, and
    -- nobody in the cluster should be penalized for dying at the wipe.
    --
    -- Returns: scoring_end (number of seconds; nil = no cluster, use full dur)
    ----------------------------------------------------------------------
    local function detect_mass_wipe_time(group_size)
        if group_size < 4 then return nil end  -- too few players to cluster
        local death_times = {}
        for _, p in pairs(players) do
            if p.death_time then table.insert(death_times, p.death_time) end
        end
        if #death_times < math.ceil(group_size * 0.5) then
            return nil  -- not enough deaths total to ever cluster 50%+
        end
        table.sort(death_times)
        local threshold = math.ceil(group_size * 0.5)
        local WINDOW = 8  -- seconds
        for i = 1, #death_times do
            local count_in_window = 0
            for j = i, #death_times do
                if death_times[j] - death_times[i] <= WINDOW then
                    count_in_window = count_in_window + 1
                else
                    break
                end
            end
            if count_in_window >= threshold then
                -- Use midpoint of the cluster (start + WINDOW/2 = effective end)
                return death_times[i] + (WINDOW / 2)
            end
        end
        return nil
    end

    -- group_size: count of players we scored (proxy for raid size when API lacks it)
    local group_n = 0
    for _ in pairs(players) do group_n = group_n + 1 end
    local mass_wipe_time = detect_mass_wipe_time(group_n)

    -- Per-player Survival score:
    --   * survived to end → 100
    --   * died before mass-wipe → death_time / scoring_end * 100  (penalized)
    --   * died in/after mass-wipe → 100  (no bonus for lingering)
    local function survival_score_for(p)
        if not p.died then return 100 end
        if not p.death_time then
            -- We know they died but no timestamp — fall back to binary
            return 0
        end
        local scoring_end
        if mass_wipe_time then
            scoring_end = mass_wipe_time
        else
            scoring_end = dur
        end
        if scoring_end <= 0 then return 0 end
        local frac = p.death_time / scoring_end
        if frac > 1 then frac = 1 end  -- cap at 100
        return math.floor(frac * 100 + 0.5)
    end

    -- Per-boss axis applicability (from MechanicConfigs)
    -- v0.15.0 uses 8-axis names: Damage/Interrupts/Dispels/Avoidance/Activity/Survival/Teamwork
    local mech_cfg = (VoidScout.MechanicConfigs and VoidScout.MechanicConfigs.Get(encounterID))
                     or { applicable_axes = nil }
    local applicable = mech_cfg.applicable_axes or {
        Damage=true, Interrupts=true, Dispels=true,
        Avoidance=true, Activity=true, Survival=true, Teamwork=true,
    }

    -- Read local player's declared duties (used to filter eligibility for THEM only).
    -- Other players' declarations aren't available without a comm channel —
    -- they fall through to class-default behavior (raw scoring).
    local local_guid = UnitGUID("player")
    local local_decls = (VoidScoutCharDB and VoidScoutCharDB.label and VoidScoutCharDB.label.subcats) or {}

    -- Compute median casts/sec across the group. Used for data_quality:
    -- a player who casts <10% of the median AND was in the pull for >10s
    -- is almost certainly disconnected, late-arrival, AFK, or reset back
    -- to the start. Their scores would be misleading noise; tag as stale
    -- so server aggregator excludes from peer pools and util_score.
    local cps_sorted = {}
    for _, p in pairs(players) do
        table.insert(cps_sorted, (p.casts or 0) / math.max(dur, 1))
    end
    table.sort(cps_sorted)
    local median_cps = 0
    if #cps_sorted > 0 then
        local mid = math.floor(#cps_sorted / 2) + 1
        median_cps = cps_sorted[mid] or 0
    end
    local stale_threshold = median_cps * 0.10  -- 10% of median = stale

    -- Compute axes per player (iterate by GUID, output keyed by clean name)
    local scorecard = {}
    for _, p in pairs(players) do
        local is_local = (p.guid == local_guid)
        -- Output: if healer (heal_done > damage_done), use HPS percentile, else DPS
        local outputVal, outputPool
        if (p.heal_done or 0) > (p.damage_done or 0) then
            outputVal, outputPool = (p.hps or 0), hps_pool
        else
            outputVal, outputPool = (p.dps or 0), dps_pool
        end

        scorecard[p.name] = {
            -- Player identity (used by companion uploader to attribute fights)
            class      = p.class,
            spec       = nil,  -- TODO: derive from GetInspectSpecialization() when available
            guid       = p.guid,
            -- 8-axis output (v0.15.0); nil for axes not applicable to this boss.
            -- Live scoring uses C_DamageMeter's raw counts as approximations:
            --   * Interrupts here = raw interrupt count percentile (NOT mechanic-aware).
            --     Backfill will refine with responsibility-aware scoring after raid.
            --   * Dispels here = nil for now (would need Dispels session pull). TODO.
            --   * Teamwork here = nil for now (needs per-mechanic config + cast tracking). TODO.
            -- For local player: respect their declared duties to opt out of axes
            -- (e.g. didn't declare kicks → don't grade Interrupts). Other players
            -- get class-default scoring (we don't have their declarations).
            Damage     = applicable.Damage and percentile(outputVal, outputPool) or nil,
            Interrupts = (applicable.Interrupts and (not is_local or local_decls.kicks))
                         and percentile(p.interrupts or 0, interrupt_pool) or nil,
            -- Dispels: percentile vs whoever-dispelled. Skipped if the player
            -- did 0 dispels AND nobody else did either — that's not a "dispel
            -- fight" for this pull, so it shouldn't drag down the score.
            Dispels    = (applicable.Dispels and (p.dispels or 0) > 0)
                         and percentile(p.dispels or 0, dispel_pool) or nil,
            Avoidance  = applicable.Avoidance and percentile_inverse(p.avoidable_taken or 0, avoid_pool) or nil,
            -- Activity: casts per second percentile vs same pool. Catches
            -- rotation gaps. Skipped if no cast data captured (e.g. addon
            -- loaded mid-pull).
            Activity   = (applicable.Activity and (p.casts or 0) > 0)
                         and percentile((p.casts or 0) / dur, cps_pool) or nil,
            Survival   = applicable.Survival and survival_score_for(p) or nil,
            -- Teamwork: percentile of teamwork actions/sec vs same pool.
            -- Counts class-specific support spells (Pain Suppression, BoP,
            -- Battle Rez, raid CDs, etc.). Nil if no teamwork data captured.
            Teamwork   = (applicable.Teamwork and (p.teamwork or 0) > 0)
                         and percentile((p.teamwork or 0) / dur, teamwork_pool) or nil,
            raw = {
                damage_done = p.damage_done,
                dps = p.dps,
                heal_done = p.heal_done,
                interrupts = p.interrupts,
                dispels = p.dispels,
                casts = p.casts,
                cps = (p.casts or 0) / dur,
                teamwork_actions = p.teamwork,
                avoidable_taken = p.avoidable_taken,
                died = p.died,
                death_time = p.death_time,
                mass_wipe_time = mass_wipe_time,
                class = p.class,
            },
            -- Data quality flag: "ok" = trust this player's axes for
            -- aggregation. "stale" = DC/AFK/reset/late-arrival, exclude
            -- from peer pools and util_score. Heuristic: <10% of group
            -- median casts/sec AND fight long enough to matter (>10s).
            -- Skipped when nobody cast (degenerate pull, mark all "ok").
            data_quality = (median_cps > 0 and dur > 10
                            and ((p.casts or 0) / math.max(dur, 1)) < stale_threshold)
                           and "stale" or "ok",
        }
    end

    return {
        encounterID = encounterID,
        difficulty  = difficulty,
        encounterName = encounterName,
        duration    = dur,
        players     = scorecard,
    }
end

----------------------------------------------------------------------
-- Public: capture from Blizzard's meter. Defers if still in combat.
-- Calls callback(scorecard, err) when done.
----------------------------------------------------------------------
function SE.CaptureFromBlizzardMeter(encounterID, difficulty, encounterName, durationSec, callback)
    callback = callback or function() end

    local function attempt()
        local card, err = build_scorecard(encounterID, difficulty, encounterName, durationSec)
        if card then
            callback(card, nil)
        else
            callback(nil, err or "unknown error")
        end
    end

    if InCombatLockdown() then
        -- Defer until out of combat
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            -- Small delay to let Blizzard finalize the session
            C_Timer.After(0.5, attempt)
        end)
    else
        -- Out of combat but session may need a tick to finalize
        C_Timer.After(0.5, attempt)
    end
end
