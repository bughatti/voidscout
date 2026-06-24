----------------------------------------------------------------------
-- VoidScout TimerScore — TimedPossibility scoring engine.
--
-- Computes 0-99 score for "can this player/group time this key".
-- Designed as a COMPOSITE of:
--   1. Per-spec Murlok base tier (50-95)
--   2. Per-key-level difficulty modifier (×0.78-1.00)
--   3. Per-ilvl gear modifier (-15 to +10 absolute)
--   4. Per-dungeon profile fit (×0.85-1.15)
--   5. Group utility fill (lust/battle-rez/skip — when scoring as a group)
--
-- Reference: design discussion 2026-05-31, [[wow-tier-list-sources]].
--
-- Phase 1 (PoC): single dungeon (MT), single-player + group scoring.
-- Phase 2: per-dungeon empirical multipliers from Blizzard leaderboard.
-- Phase 3: personal history modifier from our own captured data.
----------------------------------------------------------------------

VoidScout = VoidScout or {}
VoidScout.TimerScore = {}
local TS = VoidScout.TimerScore
local TD  -- lazy-load TimerData

local function getTD()
    if not TD then TD = VoidScout.TimerData end
    return TD
end

----------------------------------------------------------------------
-- Expected M+ rating per key level. Roughly +200 per level. Used to
-- gauge if an applicant's actual rating is above/below the expected
-- floor for the key they're applying to.
----------------------------------------------------------------------
local EXPECTED_MPRATING = {
    [10] = 2200, [11] = 2400, [12] = 2600,
    [13] = 2800, [14] = 3000, [15] = 3200,
    [16] = 3400, [17] = 3600, [18] = 3800,
    [19] = 4000, [20] = 4200, [21] = 4400,
}

----------------------------------------------------------------------
-- Compute score for a SINGLE player (you, alone, no group context).
-- Returns score, breakdown table.
-- Inputs:
--   classFile     - "DEATHKNIGHT", "MAGE", etc.
--   specName      - "Unholy", "Frost", etc.
--   ilvl          - average item level (integer)
--   keyLevel      - the key level being attempted (10-21+)
--   dungeonID     - map ID of the dungeon (e.g. 2811 for MT)
--   opts          - optional table of additional inputs:
--                     mp_rating: applicant's overall M+ rating
--                                (Blizzard's dungeonScore)
--                     is_leaver: boolean from Blizzard's leaver flag
----------------------------------------------------------------------
function TS:ScorePlayer(classFile, specName, ilvl, keyLevel, dungeonID, opts)
    local td = getTD()
    if not td then return nil, { error = "TimerData not loaded" } end
    opts = opts or {}

    local breakdown = {
        spec_base       = 0,
        gear_modifier   = 0,
        dungeon_fit     = 1.0,
        keylevel_factor = 1.0,
        mprating_mod    = 0,
        leaver_penalty  = 0,
        final           = 0,
        confidence      = "Low",
        notes           = {},
    }

    -- 1. Spec base from Murlok
    local base = td:GetSpecBase(classFile, specName)
    if not base then
        breakdown.notes[#breakdown.notes + 1] = "Unknown spec — using class average"
        base = 70  -- fallback for unknown specs
    end
    breakdown.spec_base = base

    -- 2. Gear modifier vs expected ilvl for this key bracket
    local expected = td:GetExpectedIlvl(keyLevel)
    local ilvl_delta = (ilvl or expected) - expected
    -- Asymmetric: surplus helps less than deficit hurts
    local gear_mod
    if ilvl_delta >= 0 then
        gear_mod = math.min(10, ilvl_delta * 0.5)
    else
        gear_mod = math.max(-15, ilvl_delta * 1.0)
    end
    breakdown.gear_modifier = gear_mod
    if ilvl_delta < -5 then
        breakdown.notes[#breakdown.notes + 1] = ("ilvl %d below tier expected (%d)"):format(ilvl or 0, expected)
    elseif ilvl_delta > 8 then
        breakdown.notes[#breakdown.notes + 1] = ("ilvl %d well above tier (%d expected)"):format(ilvl or 0, expected)
    end

    -- 3. Dungeon profile fit (PoC: MT-only; future per-spec per-dungeon)
    local prof = td:GetDungeonProfile(dungeonID)
    if prof then
        -- Simple PoC: AoE specs get a small boost in trash-heavy dungeons
        local is_aoe_spec = {
            ["MAGE/Frost"] = true, ["MAGE/Arcane"] = true, ["MAGE/Fire"] = true,
            ["WARLOCK/Demonology"] = true, ["WARLOCK/Destruction"] = true,
            ["DRUID/Balance"] = true, ["DEATHKNIGHT/Unholy"] = true,
            ["PALADIN/Retribution"] = true, ["DEMONHUNTER/Havoc"] = true,
            ["DEMONHUNTER/Devourer"] = true, ["SHAMAN/Elemental"] = true,
        }
        -- specName is optional — LFG search results don't expose member
        -- spec, so when called from the watch popup we get nil. Skip the
        -- per-spec fit calc in that case (no boost, no penalty, neutral).
        if specName then
            local key = classFile .. "/" .. specName
            if prof.aoe_weight > 0.5 and is_aoe_spec[key] then
                breakdown.dungeon_fit = 1.05
                breakdown.notes[#breakdown.notes + 1] = "AoE-strong spec in trash-heavy dungeon"
            elseif prof.st_weight > 0.6 and not is_aoe_spec[key] then
                breakdown.dungeon_fit = 1.03
            end
        end
    end

    -- 4. Key-level difficulty multiplier
    breakdown.keylevel_factor = td:GetKeyDifficulty(keyLevel)

    -- 5. M+ rating modifier (when known — applies to all applicants).
    -- Compare applicant's overall rating to expected floor for THIS key.
    -- Above expected = skill bonus, below = penalty. ~1 point per 100 rating delta.
    if opts.mp_rating and opts.mp_rating > 0 then
        local expected_mp = EXPECTED_MPRATING[math.min(math.max(keyLevel, 10), 21)] or 2200
        local mp_delta = opts.mp_rating - expected_mp
        local mp_mod = mp_delta / 100  -- 100 rating = 1 point
        -- Cap to keep balanced: max +15 / min -20
        mp_mod = math.max(-20, math.min(15, mp_mod))
        breakdown.mprating_mod = mp_mod
        if mp_delta > 300 then
            breakdown.notes[#breakdown.notes + 1] = ("MP rating %d well above tier"):format(opts.mp_rating)
        elseif mp_delta < -300 then
            breakdown.notes[#breakdown.notes + 1] = ("MP rating %d below tier expected"):format(opts.mp_rating)
        end
    end

    -- 6. Known-leaver penalty. Blizzard's flag — significant signal.
    if opts.is_leaver then
        breakdown.leaver_penalty = -25
        breakdown.notes[#breakdown.notes + 1] = "Flagged as known leaver"
    end

    -- 6b. Axes modifier (BEHAVIORAL): apply the player's actual axis
    -- performance as a +/- adjustment so the score reflects real play,
    -- not just class+gear. Average of axes vs neutral=70 → ±15 swing.
    -- Only applies when we have axis data (typically own player, addon users).
    breakdown.axes_mod = 0
    if opts.axes_avg and opts.axes_avg > 0 then
        local axes_delta = opts.axes_avg - 70
        breakdown.axes_mod = math.max(-15, math.min(15, axes_delta / 2))
    end

    -- 7. Final composite
    local raw = ((base + gear_mod) * breakdown.dungeon_fit * breakdown.keylevel_factor)
                + breakdown.mprating_mod + breakdown.leaver_penalty
                + breakdown.axes_mod
    local final = math.max(5, math.min(99, math.floor(raw + 0.5)))
    breakdown.final = final

    -- Confidence — PoC: high if we have all inputs, low if guessing
    if td:GetSpecBase(classFile, specName) and ilvl and keyLevel then
        breakdown.confidence = prof and "Medium" or "Low"
    else
        breakdown.confidence = "Low"
    end

    return final, breakdown
end

----------------------------------------------------------------------
-- Compute score for a GROUP (typically 5 players).
-- Input: array of {classFile, specName, ilvl} per player
-- Returns: aggregate score, per-player breakdown, group utility summary
----------------------------------------------------------------------
function TS:ScoreGroup(players, keyLevel, dungeonID)
    local td = getTD()
    if not td or not players or #players == 0 then return nil end

    local per_player = {}
    local sum = 0
    local has_lust, has_battle_rez = false, false
    local stealth_skippers = 0
    local interrupters = 0

    for i, p in ipairs(players) do
        local score, breakdown = self:ScorePlayer(p.classFile, p.specName, p.ilvl, keyLevel, dungeonID)
        per_player[i] = { player = p, score = score, breakdown = breakdown }
        sum = sum + (score or 50)

        local util = td:GetClassUtility(p.classFile)
        if util.lust then has_lust = true end
        if util.battle_rez then has_battle_rez = true end
        if util.stealth_skip then stealth_skippers = stealth_skippers + 1 end

        -- Count interrupters separately for kicker coverage bonus.
        -- Every class except classic-Druid-non-Feral/Guardian and non-Shadow
        -- Priest has a baseline kick. Use the same class capability table
        -- MechanicConfigs uses.
        if VoidScout.MechanicConfigs and VoidScout.MechanicConfigs.ClassCan then
            if VoidScout.MechanicConfigs.ClassCan(p.classFile, "interrupt", p.specName) then
                interrupters = (interrupters or 0) + 1
            end
        end

    end

    -- Aggregate: average individual score + utility modifiers
    local avg = sum / #players
    local utility_mod = 0
    local util_notes = {}

    if has_lust then
        utility_mod = utility_mod + 3
        util_notes[#util_notes + 1] = "|cff20ff20[+]|r Lust covered"
    else
        utility_mod = utility_mod - 4
        util_notes[#util_notes + 1] = "|cffff4040[-]|r NO lust in group"
    end

    if has_battle_rez then
        utility_mod = utility_mod + 1
        util_notes[#util_notes + 1] = "|cff20ff20[+]|r Battle-rez available"
    end

    -- Kicker coverage bonus. 5/5 kickers = +4. 4/5 = +2. <=3 = 0.
    -- Recognizes that comp CAPABILITY to kick is pre-knowable even if
    -- behavioral execution isn't. A 5/5-kicker group is structurally
    -- safer than a 2/5 even if neither has ever played together.
    if interrupters >= 5 then
        utility_mod = utility_mod + 4
        util_notes[#util_notes + 1] = ("|cff20ff20[+]|r Full kicker coverage (%d/5)"):format(interrupters)
    elseif interrupters >= 4 then
        utility_mod = utility_mod + 2
        util_notes[#util_notes + 1] = ("|cff20ff20[+]|r Strong kicker coverage (%d/5)"):format(interrupters)
    elseif interrupters <= 2 then
        utility_mod = utility_mod - 2
        util_notes[#util_notes + 1] = ("|cffff4040[-]|r Thin kicker coverage (%d/5)"):format(interrupters)
    end

    -- NOTE: brez is a shared group resource, not per-class. Having
    -- multiple brez sources only buys *redundancy* (if your one brezzer
    -- dies, someone else can still cast). The shared pool gives the same
    -- number of charges either way (~1 per 90s of fight). So we DON'T
    -- add a bonus for additional brezzers — the base +1 above already
    -- covers "you can use the pool at all."

    if stealth_skippers > 0 then
        utility_mod = utility_mod + 2
        util_notes[#util_notes + 1] = "|cff20ff20[+]|r Stealth-skip available"
    end

    local group_score = math.max(5, math.min(99, math.floor(avg + utility_mod + 0.5)))

    return {
        group_score   = group_score,
        avg_player    = math.floor(avg + 0.5),
        utility_mod   = utility_mod,
        utility_notes = util_notes,
        has_lust      = has_lust,
        has_battle_rez = has_battle_rez,
        per_player    = per_player,
    }
end

----------------------------------------------------------------------
-- Score YOUR own current character for a hypothetical run.
-- Convenience wrapper for slash command testing.
----------------------------------------------------------------------
function TS:ScoreSelf(keyLevel, dungeonID)
    local _, classFile = UnitClass("player")
    local specID = GetSpecialization()
    local specName = nil
    if specID then
        local _, name = GetSpecializationInfo(specID)
        specName = name
    end
    local ilvl = math.floor(select(2, GetAverageItemLevel()) or 0)
    return self:ScorePlayer(classFile, specName, ilvl, keyLevel, dungeonID)
end

----------------------------------------------------------------------
-- Pretty-print a breakdown for chat / tooltip use
----------------------------------------------------------------------
function TS:FormatBreakdown(breakdown)
    if not breakdown then return "(no breakdown)" end
    local lines = {
        ("Final: %d (%s confidence)"):format(breakdown.final or 0, breakdown.confidence or "?"),
        ("  Spec base: %d"):format(breakdown.spec_base or 0),
        ("  Gear: %+d"):format(breakdown.gear_modifier or 0),
        ("  Dungeon fit: x%.2f"):format(breakdown.dungeon_fit or 1.0),
        ("  Key level factor: x%.2f"):format(breakdown.keylevel_factor or 1.0),
    }
    for _, n in ipairs(breakdown.notes or {}) do
        lines[#lines + 1] = "  • " .. n
    end
    return table.concat(lines, "\n")
end
