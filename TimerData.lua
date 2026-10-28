----------------------------------------------------------------------
-- VoidScout TimerData — static lookup tables for TimedPossibility
-- scoring. Per-spec base from Murlok.io rankings (2026-05-31 pull),
-- utility flags from class capability research, scaling tuned by hand.
--
-- Refresh per major patch by re-pulling Murlok rankings + manual
-- editorial source review (Wowhead/Icy Veins/MaxRoll/Method).
-- See [[wow-tier-list-sources]] for sourcing methodology.
----------------------------------------------------------------------

VoidScout = VoidScout or {}
VoidScout.TimerData = {}
local TD = VoidScout.TimerData

----------------------------------------------------------------------
-- Per-spec base score (Murlok M+ rankings, normalized to 50-95 range)
-- Murlok raw range: 3433 (worst) to 4165 (best)
-- Normalization: 50 + ((murlok - 3433) / 732) * 45
-- Keyed by "CLASS_FILE/SPEC_NAME"
----------------------------------------------------------------------
TD.spec_base = {
    -- TANKS
    ["DRUID/Guardian"]         = 95,  -- Murlok 4156 #1 tank
    ["MONK/Brewmaster"]        = 89,  -- 4055
    ["DEATHKNIGHT/Blood"]      = 76,  -- 3852
    ["PALADIN/Protection"]     = 75,  -- 3834
    ["DEMONHUNTER/Vengeance"]  = 73,  -- 3812
    ["WARRIOR/Protection"]     = 73,  -- 3811

    -- HEALERS
    ["MONK/Mistweaver"]        = 95,  -- 4157 #1 healer
    ["SHAMAN/Restoration"]     = 89,  -- 4073
    ["PRIEST/Discipline"]      = 82,  -- 3951
    ["DRUID/Restoration"]      = 81,  -- 3932
    ["PALADIN/Holy"]           = 78,  -- 3891
    ["EVOKER/Preservation"]    = 73,  -- 3803
    ["PRIEST/Holy"]            = 66,  -- 3697

    -- DPS
    ["EVOKER/Augmentation"]    = 95,  -- 4165 #1 DPS
    ["DEMONHUNTER/Devourer"]   = 95,  -- 4161
    ["DEATHKNIGHT/Unholy"]     = 95,  -- 4159
    ["WARRIOR/Arms"]           = 88,  -- 4059
    ["PALADIN/Retribution"]    = 88,  -- 4052
    ["DRUID/Feral"]            = 86,  -- 4023
    ["ROGUE/Outlaw"]           = 86,  -- 4021
    ["WARLOCK/Demonology"]     = 85,  -- 4010
    ["SHAMAN/Elemental"]       = 84,  -- 3989
    ["HUNTER/Survival"]        = 84,  -- 3981
    ["WARRIOR/Fury"]           = 82,  -- 3950
    ["PRIEST/Shadow"]          = 82,  -- 3949
    ["SHAMAN/Enhancement"]     = 81,  -- 3941
    ["MONK/Windwalker"]        = 79,  -- 3911
    ["MAGE/Frost"]             = 79,  -- 3908
    ["ROGUE/Assassination"]    = 79,  -- 3903
    ["ROGUE/Subtlety"]         = 79,  -- 3898
    ["DEMONHUNTER/Havoc"]      = 79,  -- 3898
    ["HUNTER/Beast Mastery"]   = 79,  -- 3897
    ["DRUID/Balance"]          = 76,  -- 3853
    ["HUNTER/Marksmanship"]    = 73,  -- 3810
    ["DEATHKNIGHT/Frost"]      = 72,  -- 3792
    ["WARLOCK/Affliction"]     = 70,  -- 3756
    ["MAGE/Fire"]              = 58,  -- 3558
    ["EVOKER/Devastation"]     = 56,  -- 3529
    ["MAGE/Arcane"]            = 55,  -- 3508
    ["WARLOCK/Destruction"]    = 50,  -- 3433 #27 DPS
}

----------------------------------------------------------------------
-- Class utility — what each class brings to the group
-- Lust: Shaman/Mage/Hunter/Evoker
-- Battle Rez: Druid/DK/Warlock/Hunter (Eagle Eye)
-- Group invis: Mage (Mass Invis) — saves wall pulls
-- Stealth skip: Rogue (Shroud) — saves whole packs
----------------------------------------------------------------------
TD.class_utility = {
    SHAMAN      = { lust = true, battle_rez = false },
    MAGE        = { lust = true, battle_rez = false, mass_invis = true },
    HUNTER      = { lust = true, battle_rez = false },
    EVOKER      = { lust = true, battle_rez = false },
    DRUID       = { lust = false, battle_rez = true },
    DEATHKNIGHT = { lust = false, battle_rez = true },
    WARLOCK     = { lust = false, battle_rez = true },
    ROGUE       = { lust = false, battle_rez = false, stealth_skip = true },
    PALADIN     = { lust = false, battle_rez = false },
    MONK        = { lust = false, battle_rez = false },
    PRIEST      = { lust = false, battle_rez = false },
    WARRIOR     = { lust = false, battle_rez = false },
    DEMONHUNTER = { lust = false, battle_rez = false },
}

----------------------------------------------------------------------
-- Per-dungeon profile — what THIS dungeon demands.
-- aoe_weight: high if trash-heavy with big AoE pulls
-- st_weight:  high if boss-DPS-check heavy
-- skip_value: high if stealth skips save real time
-- time_pressure: 0-1, how tight the timer is
----------------------------------------------------------------------
TD.dungeon_profile = {
    -- Magisters' Terrace (map 2811) — trash-heavy, lots of caster packs
    -- with polymorphs/silences. Skip routes available via stealth.
    [2811] = {
        name           = "Magisters' Terrace",
        aoe_weight     = 0.75,
        st_weight      = 0.25,
        skip_value     = 0.40,  -- Rogue Shroud saves a significant pack
        time_pressure  = 0.65,
        cc_demand      = 0.85,  -- High - many interruptible/CCable casters
    },
    -- Pit of Saron (map 658) — outdoor cleave dungeon, dense pulls + boss-heavy
    [658] = {
        name           = "Pit of Saron",
        aoe_weight     = 0.70,
        st_weight      = 0.30,
        skip_value     = 0.30,
        time_pressure  = 0.60,
        cc_demand      = 0.70,
    },
    -- Skyreach (map 1209) — caster-heavy, big AoE packs, high CC demand
    [1209] = {
        name           = "Skyreach",
        aoe_weight     = 0.80,
        st_weight      = 0.20,
        skip_value     = 0.50,  -- significant stealth-skip routes
        time_pressure  = 0.70,
        cc_demand      = 0.85,
    },
    -- Seat of the Triumvirate (map 1753) — mixed mechanic-heavy
    [1753] = {
        name           = "Seat of the Triumvirate",
        aoe_weight     = 0.60,
        st_weight      = 0.40,
        skip_value     = 0.40,
        time_pressure  = 0.65,
        cc_demand      = 0.70,
    },
    -- Algeth'ar Academy (map 2526) — caster trash, library theme
    [2526] = {
        name           = "Algeth'ar Academy",
        aoe_weight     = 0.75,
        st_weight      = 0.25,
        skip_value     = 0.45,
        time_pressure  = 0.65,
        cc_demand      = 0.85,
    },
    -- Windrunner Spire (map 2805) — mixed melee/caster, ranger theme
    [2805] = {
        name           = "Windrunner Spire",
        aoe_weight     = 0.65,
        st_weight      = 0.35,
        skip_value     = 0.40,
        time_pressure  = 0.65,
        cc_demand      = 0.70,
    },
    -- Maisara Caverns (map 2874) — cave dungeon, modest packs
    [2874] = {
        name           = "Maisara Caverns",
        aoe_weight     = 0.50,
        st_weight      = 0.50,
        skip_value     = 0.40,
        time_pressure  = 0.60,
        cc_demand      = 0.60,
    },
    -- Nexus-Point Xenas (map 2915) — tech-construct dungeon
    [2915] = {
        name           = "Nexus-Point Xenas",
        aoe_weight     = 0.60,
        st_weight      = 0.40,
        skip_value     = 0.40,
        time_pressure  = 0.65,
        cc_demand      = 0.70,
    },
}

----------------------------------------------------------------------
-- Tier ilvl expectations per key-level bracket
-- Used to compute gear modifier: (actual_ilvl - expected) * coefficient
----------------------------------------------------------------------
TD.keylevel_expected_ilvl = {
    [2]  = 245, [3]  = 250, [4]  = 255,
    [5]  = 258, [6]  = 261, [7]  = 264,
    [8]  = 266, [9]  = 268, [10] = 270,
    [11] = 275, [12] = 278, [13] = 281,
    [14] = 284, [15] = 287, [16] = 290,
    [17] = 292, [18] = 294, [19] = 296,
    [20] = 298, [21] = 300, [22] = 302,
    [23] = 304, [24] = 305, [25] = 306,
    [26] = 307, [27] = 308, [28] = 309,
    [29] = 310, [30] = 311,
}

----------------------------------------------------------------------
-- Key-level difficulty scaling
-- At higher keys, base spec tier matters MORE (utility > raw dps)
-- This curve gradually pulls scores toward 0 as keys climb
----------------------------------------------------------------------
TD.keylevel_difficulty = {
    -- Low keys: trivial, score floor is the spec base
    [2]  = 1.05, [3]  = 1.05, [4]  = 1.04,
    [5]  = 1.04, [6]  = 1.03, [7]  = 1.03,
    [8]  = 1.02, [9]  = 1.01, [10] = 1.00,
    -- Pushing brackets
    [11] = 1.00, [12] = 1.00, [13] = 0.98,
    [14] = 0.97, [15] = 0.95, [16] = 0.93,
    [17] = 0.91, [18] = 0.89, [19] = 0.86,
    [20] = 0.83, [21] = 0.80, [22] = 0.77,
    [23] = 0.74, [24] = 0.71, [25] = 0.68,
    [26] = 0.65, [27] = 0.62, [28] = 0.59,
    [29] = 0.56, [30] = 0.53,
}

----------------------------------------------------------------------
-- Lookup helpers
----------------------------------------------------------------------
function TD:GetSpecBase(classFile, specName)
    if not classFile or not specName then return nil end
    return self.spec_base[classFile .. "/" .. specName]
end

function TD:GetClassUtility(classFile)
    return classFile and self.class_utility[classFile] or {}
end

function TD:GetDungeonProfile(dungeonID)
    return self.dungeon_profile[dungeonID]
end

function TD:GetExpectedIlvl(keyLevel)
    keyLevel = keyLevel or 10
    if keyLevel < 2 then keyLevel = 2 end
    if keyLevel > 30 then keyLevel = 30 end
    return self.keylevel_expected_ilvl[keyLevel] or 270
end

function TD:GetKeyDifficulty(keyLevel)
    keyLevel = keyLevel or 10
    if keyLevel < 2 then return 1.05 end
    if keyLevel > 30 then return 0.50 end
    return self.keylevel_difficulty[keyLevel] or 1.00
end
