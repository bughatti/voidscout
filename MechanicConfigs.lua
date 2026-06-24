----------------------------------------------------------------------
-- VoidScout MechanicConfigs — per-boss mechanic definitions for
-- responsibility-aware scoring.
--
-- 8-AXIS MODEL (renamed for clarity, all axes ARE mechanics):
--   Damage      — your raw contribution (DPS/HPS/threat)
--   Interrupts  — kicks on mechanic-required casts
--   Dispels     — defensive/offensive dispels of required debuffs
--   Avoidance   — not getting hit by dodgeable damage
--   Activity    — keep pressure on / not idle
--   Survival    — stay alive
--   Teamwork    — boss-specific group actions (soaks, rescues, orbs)
--   Commitment  — per-pug stay rate
--
-- ELIGIBILITY MODEL — only count mechanic-required actions:
--   Interrupts axis tallies ONLY kicks of spell IDs in `mechanics`
--   Dispels axis tallies ONLY dispels of debuff IDs in `mechanics`
--   Random kicks/dispels of non-mechanic spells = ignored
----------------------------------------------------------------------

VoidScout = VoidScout or {}
VoidScout.MechanicConfigs = {}
local M = VoidScout.MechanicConfigs

local function default_axes()
    return {
        Damage=true, Interrupts=true, Dispels=true,
        Avoidance=true, Activity=true, Survival=true, Teamwork=true,
    }
end
M._default = { boss_name="Unknown", applicable_axes=default_axes(), mechanics={} }

----------------------------------------------------------------------
-- 3176 — Imperator Averzian (Mythic)
----------------------------------------------------------------------
M[3176] = {
    boss_name = "Imperator Averzian", raid = "voidspire",
    applicable_axes = default_axes(),
    mechanics = {
        { id="abyssal_malus_kick", type="interrupt", trigger_spell_id=1255702,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },
        { id="void_marked_dispel", type="dispel", trigger_spell_id=1280015,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },
        { id="cosmic_shell_strip", type="dispel", trigger_spell_id=1280035,
          success_window=10,
          capability="dispel_magic_off", declared_duty="dispels", critical=true },
    },
}

----------------------------------------------------------------------
-- 3177 — Vorasius (Mythic)
-- No required interrupts. No required dispels (per research so far).
----------------------------------------------------------------------
M[3177] = {
    boss_name = "Vorasius", raid = "voidspire",
    applicable_axes = {
        Damage=true, Interrupts=false, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {},
}

----------------------------------------------------------------------
-- 3178 — Vaelgor & Ezzorak (Mythic)
----------------------------------------------------------------------
M[3178] = {
    boss_name = "Vaelgor & Ezzorak", raid = "voidspire",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="voidbolt", type="interrupt", trigger_spell_id=1245175,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },
    },
}

----------------------------------------------------------------------
-- 3179 — Fallen-King Salhadaar (Mythic)
----------------------------------------------------------------------
M[3179] = {
    boss_name = "Fallen-King Salhadaar", raid = "voidspire",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="shadow_fracture", type="interrupt", trigger_spell_id=1254088,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },
    },
}

----------------------------------------------------------------------
-- 3180 — Lightblinded Vanguard (Mythic)
----------------------------------------------------------------------
M[3180] = {
    boss_name = "Lightblinded Vanguard", raid = "voidspire",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="blinding_light", type="interrupt", trigger_spell_id=1258514,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },
    },
}

----------------------------------------------------------------------
-- 3181 — Crown of the Cosmos (Mythic)
----------------------------------------------------------------------
M[3181] = {
    boss_name = "Crown of the Cosmos", raid = "voidspire",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="void_barrage", type="interrupt", trigger_spell_id=1260000,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },
        { id="devour", type="interrupt", trigger_spell_id=1217610,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },
    },
}

----------------------------------------------------------------------
-- 3306 — Chimaerus, the Undreamt God (Mythic)
----------------------------------------------------------------------
M[3306] = {
    boss_name = "Chimaerus, the Undreamt God", raid = "the_dreamrift",
    applicable_axes = default_axes(),
    mechanics = {
        { id="fearsome_cry", type="interrupt", trigger_spell_id=1245406,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },
        { id="essence_bolt_v1", type="interrupt", trigger_spell_id=1262020,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },
        { id="essence_bolt_v2", type="interrupt", trigger_spell_id=1262053,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },
        { id="essence_bolt_v3", type="interrupt", trigger_spell_id=1262059,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },
        { id="consuming_miasma_v1", type="dispel", trigger_spell_id=1257087,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },
        { id="consuming_miasma_v2", type="dispel", trigger_spell_id=1257085,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },
    },
}

----------------------------------------------------------------------
-- 3182 — Belo'ren, Child of Al'ar (Mythic, March on Quel'Danas)
----------------------------------------------------------------------
M[3182] = {
    boss_name = "Belo'ren, Child of Al'ar", raid = "march_on_queldanas",
    applicable_axes = default_axes(),
    mechanics = {
        -- Light Eruption — only Light feather players can interrupt.
        -- ID 1243852 unverified in latest WCL pull (was always interrupted
        -- before reaching cast table); keeping as the working hypothesis.
        { id="light_eruption", type="interrupt", trigger_spell_id=1243852,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },
        -- Immortal Flame (1243320) — boss buff acting as absorb, healers
        -- need to magic-dispel. Verified via WCL boss-buffs table 2026-05-30.
        -- (Was previously named "Eternal Burns" with wrong ID 1244344.)
        { id="immortal_flame", type="dispel", trigger_spell_id=1243320,
          success_window=8,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },
        -- Incubation of Flames (1242792) — soft-enrage stacking buff on
        -- boss, also dispellable. Bonus credit for staying on top of it.
        { id="incubation_of_flames", type="dispel", trigger_spell_id=1242792,
          success_window=10,
          capability="dispel_magic_def", declared_duty="dispels", critical=false },
    },
    teamwork_soak_spells = { 1241292, 1241339 },     -- Light Dive, Void Dive
    teamwork_carrier_auras = { 1241162, 1241163 },   -- Light/Void Feather
    teamwork_intercept_spells = { 1242260 },         -- Infused Quills
}

----------------------------------------------------------------------
-- 3183 — Midnight Falls (Mythic, March on Quel'Danas)
----------------------------------------------------------------------
M[3183] = {
    boss_name = "Midnight Falls", raid = "march_on_queldanas",
    applicable_axes = default_axes(),
    mechanics = {
        -- Core Harvest (1282412) — L'ura's channeled life-drain; interruptible.
        -- Only 3 casts per fight (5+ min channel windows).
        { id="core_harvest", type="interrupt", trigger_spell_id=1282412,
          success_window=4,
          capability="interrupt", declared_duty="kicks", critical=true },
        -- Death's Dirge (1249620) — positional; not interruptible, just survival
        -- Heaven's Lance (1267049), Heaven's Glaives (1253915), Galvanize
        -- (1284525) handled via teamwork/avoidance below
    },
    teamwork_soak_spells = { 1266897, 1284525 },  -- Light Siphon, Galvanize
    -- Dawnlight Barrier (1253770) — verified via WCL: players gain this as a
    -- debuff/carrier from Environment casts (27/fight = the "Dawn Crystal"
    -- mechanic). Carrier players have positional/soak duties.
    teamwork_carrier_auras = { 1253770 },          -- Dawnlight Barrier
}

----------------------------------------------------------------------
-- M+ DUNGEON BOSSES — auto-generated from Wago.tools DBC
-- (JournalEncounter + JournalEncounterSection + SpellName, build 12.0.5.67602).
-- Generator: C:\tmp\generate_mechanic_configs.py
-- Coverage: 29 bosses across 8 Midnight S1 dungeons.
--
-- Classification combines:
--   1. JES BodyText_lang (authoritative — says "channels" or "Magic Effect")
--   2. Spell name heuristics (verbs vs nouns) as fallback
--
-- Bosses where automated extraction yielded no machine-classifiable
-- interrupts/dispels emit empty mechanics + axes_disabled. Those bosses
-- are typically positional/avoidance fights (Forgemaster Garfrost, Crawth,
-- etc.) where Interrupts/Dispels shouldn't grade players anyway.
--
-- TRASH MOBS are NOT covered by JES (JES is boss-only). Per-dungeon trash
-- spell IDs are populated via observed-cast discovery (see Task #88 / the
-- TrashDiscovery module) — not from DBC.
----------------------------------------------------------------------

-- Pit of Saron (mapID 658) — 3 bosses
M[1999] = {
    boss_name = "Forgemaster Garfrost", dungeon = "pit_of_saron",
    applicable_axes = {
        Damage=true, Interrupts=false, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {}, -- positional/soak fight, no required interrupts
}
M[2001] = {
    boss_name = "Ick and Krick", dungeon = "pit_of_saron",
    applicable_axes = default_axes(),
    mechanics = {
        { id="death_bolt", type="interrupt", trigger_spell_id=1278893,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Death Bolt
        { id="blight_smash", type="interrupt", trigger_spell_id=1264287,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Blight Smash
        { id="plague_expulsion", type="dispel", trigger_spell_id=1264336,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Plague Expulsion
        { id="plague_globs_a", type="dispel", trigger_spell_id=1264349,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Plague Globs
        { id="blight", type="dispel", trigger_spell_id=1264299,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Blight
        { id="plague_globs_b", type="dispel", trigger_spell_id=1264461,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Plague Globs (v2)
    },
}
M[2000] = {
    boss_name = "Scourgelord Tyrannus", dungeon = "pit_of_saron",
    applicable_axes = default_axes(),
    mechanics = {
        { id="bone_infusion", type="interrupt", trigger_spell_id=1276648,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Bone Infusion
        { id="infused_bone_piles", type="interrupt", trigger_spell_id=1276391,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Infused Bone Piles
        { id="plague_bolt", type="interrupt", trigger_spell_id=1262941,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Plague Bolt
        { id="rime_blast", type="interrupt", trigger_spell_id=1262745,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Rime Blast
        { id="ice_barrage", type="interrupt", trigger_spell_id=1276948,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Ice Barrage
        { id="death_s_grasp", type="dispel", trigger_spell_id=1263756,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Death's Grasp
        { id="scourgelord_brand", type="dispel", trigger_spell_id=1262582,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Scourgelord's Brand
    },
}

-- Skyreach (mapID 1209) — 4 bosses
M[1698] = {
    boss_name = "Ranjit", dungeon = "skyreach",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="chakram_vortex", type="interrupt", trigger_spell_id=156793,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Chakram Vortex
        { id="gale_surge", type="interrupt", trigger_spell_id=1252691,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Gale Surge
    },
}
M[1699] = {
    boss_name = "Araknath", dungeon = "skyreach",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="solar_infusion", type="interrupt", trigger_spell_id=1252877,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Solar Infusion
        { id="fiery_smash", type="interrupt", trigger_spell_id=154132,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Fiery Smash
        { id="light_ray", type="interrupt", trigger_spell_id=154150,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Light Ray
        { id="blast_wave", type="interrupt", trigger_spell_id=1279002,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Blast Wave
    },
}
M[1700] = {
    boss_name = "Rukhran", dungeon = "skyreach",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="blaze_of_glory", type="interrupt", trigger_spell_id=1253416,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Blaze of Glory
    },
}
M[1701] = {
    boss_name = "High Sage Viryx", dungeon = "skyreach",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="cast_down", type="interrupt", trigger_spell_id=153954,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Cast Down
        { id="lens_flare", type="interrupt", trigger_spell_id=154044,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Lens Flare
        { id="solar_blast", type="interrupt", trigger_spell_id=154396,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Solar Blast
        { id="scorching_ray", type="interrupt", trigger_spell_id=1253543,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Scorching Ray
    },
}

-- Seat of the Triumvirate (mapID 1753) — 4 bosses
M[2065] = {
    boss_name = "Zuraal the Ascended", dungeon = "seat_of_the_triumvirate",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="oozing_slam", type="interrupt", trigger_spell_id=1263399,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Oozing Slam
    },
}
M[2066] = {
    boss_name = "Saprish", dungeon = "seat_of_the_triumvirate",
    applicable_axes = default_axes(),
    mechanics = {
        { id="umbral_nova", type="interrupt", trigger_spell_id=1263508,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Umbral Nova
        { id="dread_screech", type="dispel", trigger_spell_id=248831,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Dread Screech
    },
}
M[2067] = {
    boss_name = "Viceroy Nezhar", dungeon = "seat_of_the_triumvirate",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="mass_void_infusion", type="interrupt", trigger_spell_id=1263542,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Mass Void Infusion
        { id="void_storm", type="interrupt", trigger_spell_id=1265030,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Void Storm
        { id="mind_blast", type="interrupt", trigger_spell_id=244750,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Mind Blast
    },
}
M[2068] = {
    boss_name = "L'ura", dungeon = "seat_of_the_triumvirate",
    applicable_axes = default_axes(),
    mechanics = {
        { id="discordant_beam", type="interrupt", trigger_spell_id=1265464,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Discordant Beam
        { id="siphon_void", type="dispel", trigger_spell_id=1265999,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Siphon Void
    },
}

-- Algeth'ar Academy (mapID 2526) — 4 bosses
M[2562] = {
    boss_name = "Vexamus", dungeon = "algethar_academy",
    applicable_axes = {
        Damage=true, Interrupts=false, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {}, -- adds/avoidance fight, no required interrupts
}
M[2563] = {
    boss_name = "Overgrown Ancient", dungeon = "algethar_academy",
    applicable_axes = {
        Damage=true, Interrupts=false, Dispels=true, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="lasher_toxin", type="dispel", trigger_spell_id=389033,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Lasher Toxin
    },
}
M[2564] = {
    boss_name = "Crawth", dungeon = "algethar_academy",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="gale_force", type="interrupt", trigger_spell_id=376467,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Gale Force
        { id="searing_blaze", type="interrupt", trigger_spell_id=389481,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Goal of the Searing Blaze
    },
}
M[2565] = {
    boss_name = "Echo of Doragosa", dungeon = "algethar_academy",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="astral_blast", type="interrupt", trigger_spell_id=1282251,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Astral Blast
    },
}

-- Windrunner Spire (mapID 2805) — 4 bosses
M[3056] = {
    boss_name = "Emberdawn", dungeon = "windrunner_spire",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="burning_gale", type="interrupt", trigger_spell_id=465904,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Burning Gale
    },
}
M[3057] = {
    boss_name = "Derelict Duo", dungeon = "windrunner_spire",
    applicable_axes = default_axes(),
    mechanics = {
        { id="shadow_bolt", type="interrupt", trigger_spell_id=472724,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Shadow Bolt
        { id="curse_of_darkness", type="dispel", trigger_spell_id=474105,
          success_window=5,
          capability="dispel_curse", declared_duty="dispels", critical=true },  -- Curse of Darkness
    },
}
M[3058] = {
    boss_name = "Commander Kroluk", dungeon = "windrunner_spire",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="flame_nova", type="interrupt", trigger_spell_id=1270620,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Flame Nova
    },
}
M[3059] = {
    boss_name = "Restless Heart", dungeon = "windrunner_spire",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="tempest_slash", type="interrupt", trigger_spell_id=472662,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Tempest Slash
        { id="gust_shot", type="interrupt", trigger_spell_id=1253986,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Gust Shot
        { id="arrow_rain", type="interrupt", trigger_spell_id=472556,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Arrow Rain
        { id="bolt_gale", type="interrupt", trigger_spell_id=474528,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Bolt Gale
    },
}

-- Magisters' Terrace (mapID 2811) — 4 bosses
M[3071] = {
    boss_name = "Arcanotron Custos", dungeon = "magisters_terrace",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="arcane_empowerment", type="interrupt", trigger_spell_id=474407,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Arcane Empowerment
        { id="repulsing_slam", type="interrupt", trigger_spell_id=474496,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Repulsing Slam
    },
}
M[3072] = {
    boss_name = "Seranel Sunlash", dungeon = "magisters_terrace",
    applicable_axes = {
        Damage=true, Interrupts=false, Dispels=true, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="runic_mark", type="dispel", trigger_spell_id=1225792,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Runic Mark
    },
}
M[3073] = {
    boss_name = "Gemellus", dungeon = "magisters_terrace",
    applicable_axes = {
        Damage=true, Interrupts=false, Dispels=true, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="astral_grasp", type="dispel", trigger_spell_id=1224299,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Astral Grasp
    },
}
M[3074] = {
    boss_name = "Degentrius", dungeon = "magisters_terrace",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="devouring_entropy", type="interrupt", trigger_spell_id=1215897,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Devouring Entropy
        { id="entropy_blast", type="interrupt", trigger_spell_id=1271066,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Entropy Blast
    },
}

-- Maisara Caverns (mapID 2874) — 3 bosses
M[3212] = {
    boss_name = "Muro'jin and Nekraxx", dungeon = "maisara_caverns",
    applicable_axes = default_axes(),
    mechanics = {
        { id="barrage", type="interrupt", trigger_spell_id=1260643,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Barrage
        { id="infected_pinions", type="dispel", trigger_spell_id=1246666,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Infected Pinions
    },
}
M[3213] = {
    boss_name = "Vordaza", dungeon = "maisara_caverns",
    applicable_axes = default_axes(),
    mechanics = {
        { id="drain_soul", type="interrupt", trigger_spell_id=1251554,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Drain Soul
        { id="lingering_dread", type="dispel", trigger_spell_id=1251813,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Lingering Dread
        { id="withering_miasma", type="dispel", trigger_spell_id=1264987,
          success_window=5,
          capability="dispel_magic_def", declared_duty="dispels", critical=true },  -- Withering Miasma
    },
}
M[3214] = {
    boss_name = "Rak'tul, Vessel of Souls", dungeon = "maisara_caverns",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="crush_souls", type="interrupt", trigger_spell_id=1252676,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Crush Souls
    },
}

-- Nexus-Point Xenas (mapID 2915) — 3 bosses
M[3328] = {
    boss_name = "Chief Corewright Kasreth", dungeon = "nexus_point_xenas",
    applicable_axes = {
        Damage=true, Interrupts=false, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {}, -- mechanic fight, no required interrupts
}
M[3332] = {
    boss_name = "Corewarden Nysarra", dungeon = "nexus_point_xenas",
    applicable_axes = {
        Damage=true, Interrupts=true, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {
        { id="devour_the_unworthy", type="interrupt", trigger_spell_id=1252883,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=true },  -- Devour the Unworthy
        { id="lightscar_flare", type="interrupt", trigger_spell_id=1247976,
          success_window=3, engagement_window=5,
          capability="interrupt", declared_duty="kicks", critical=false },  -- Lightscar Flare
    },
}
M[3333] = {
    boss_name = "Lothraxion", dungeon = "nexus_point_xenas",
    applicable_axes = {
        Damage=true, Interrupts=false, Dispels=false, Avoidance=true,
        Activity=true, Survival=true, Teamwork=true,
    },
    mechanics = {}, -- mechanic fight, no required interrupts
}

----------------------------------------------------------------------
-- TRASH MOB MECHANICS (per dungeon)
--
-- Seeded with known high-priority casters from veteran knowledge of
-- legacy dungeons recycled into Midnight S1. Auto-discovery from
-- observed enemy casts populates the rest (see TrashDiscovery module
-- and Task #88). Boss-fight ENCOUNTER scoring uses the M[encounterID]
-- entries above; trash pulls fall through to M.TRASH_MECHANICS[mapID].
----------------------------------------------------------------------
M.TRASH_MECHANICS = {
    [658] = {  -- Pit of Saron
        boss_name = "Pit of Saron trash",
        applicable_axes = default_axes(),
        mechanics = {
            -- TODO: seed from observed casts (TrashDiscovery)
        },
    },
    [1209] = {  -- Skyreach
        boss_name = "Skyreach trash",
        applicable_axes = default_axes(),
        mechanics = {},
    },
    [1753] = {  -- Seat of the Triumvirate
        boss_name = "Seat of the Triumvirate trash",
        applicable_axes = default_axes(),
        mechanics = {},
    },
    [2526] = {  -- Algeth'ar Academy
        boss_name = "Algeth'ar Academy trash",
        applicable_axes = default_axes(),
        mechanics = {},
    },
    [2805] = {  -- Windrunner Spire
        boss_name = "Windrunner Spire trash",
        applicable_axes = default_axes(),
        mechanics = {},
    },
    [2811] = {  -- Magisters' Terrace
        boss_name = "Magisters' Terrace trash",
        applicable_axes = default_axes(),
        mechanics = {},
    },
    [2874] = {  -- Maisara Caverns
        boss_name = "Maisara Caverns trash",
        applicable_axes = default_axes(),
        mechanics = {},
    },
    [2915] = {  -- Nexus-Point Xenas
        boss_name = "Nexus-Point Xenas trash",
        applicable_axes = default_axes(),
        mechanics = {},
    },
}

----------------------------------------------------------------------
-- Universal Teamwork spell IDs — class-specific support spells
-- that always count as teamwork when cast on others.
-- Mirrors UNIVERSAL_TEAMWORK_SPELLS in mechanics_lib.py
----------------------------------------------------------------------
M.UNIVERSAL_TEAMWORK_SPELLS = {
    DEATHKNIGHT = {
        [61999]  = "Raise Ally",
        [51052]  = "Anti-Magic Zone",
        [49576]  = "Death Grip",
    },
    DEMONHUNTER = {
        [196718] = "Darkness",
        [202137] = "Sigil of Silence",
        [207684] = "Sigil of Misery",
    },
    DRUID = {
        [20484]  = "Rebirth",
        [77764]  = "Stampeding Roar",
        [740]    = "Tranquility",
        [102342] = "Ironbark",
    },
    EVOKER = {
        [370960] = "Emerald Communion",
        [363534] = "Rewind",
        [361509] = "Rescue",
        [357170] = "Time Dilation",
    },
    HUNTER = {
        [34477]  = "Misdirection",
        [20736]  = "Distracting Shot",
    },
    MAGE = {
        [80353]  = "Time Warp",
        [342245] = "Alter Time",
    },
    MONK = {
        [115310] = "Revival",
        [116849] = "Life Cocoon",
        [116841] = "Tiger's Lust",
        [115176] = "Zen Meditation",
        [116844] = "Ring of Peace",
    },
    PALADIN = {
        [633]    = "Lay on Hands",
        [1022]   = "Blessing of Protection",
        [6940]   = "Blessing of Sacrifice",
        [1044]   = "Blessing of Freedom",
        [31821]  = "Aura Mastery",
        [328620] = "Intercession",
    },
    PRIEST = {
        [33076]  = "Prayer of Mending",
        [47788]  = "Guardian Spirit",
        [33206]  = "Pain Suppression",
        [62618]  = "Power Word: Barrier",
        [64901]  = "Symbol of Hope",
        [265202] = "Holy Word: Salvation",
        [32375]  = "Mass Dispel",
    },
    ROGUE = {
        [57934]  = "Tricks of the Trade",
        [76577]  = "Smoke Bomb",
    },
    SHAMAN = {
        [108280] = "Healing Tide Totem",
        [98008]  = "Spirit Link Totem",
        [2825]   = "Bloodlust",
        [32182]  = "Heroism",
        [207399] = "Ancestral Protection Totem",
    },
    WARLOCK = {
        [20707]  = "Soulstone",
        [29893]  = "Create Soulwell",
    },
    WARRIOR = {
        [97462]  = "Rallying Cry",
        [114030] = "Vigilance",
        [46968]  = "Shockwave",
    },
}

function M.IsUniversalTeamworkSpell(spell_id, class_file)
    if not class_file then return false end
    local class_spells = M.UNIVERSAL_TEAMWORK_SPELLS[class_file]
    if not class_spells then return false end
    return class_spells[spell_id] ~= nil
end

----------------------------------------------------------------------
-- CC spells per class — applied to enemies count as teamwork
-- (protecting the group from an add's damage)
----------------------------------------------------------------------
M.CC_SPELLS = {
    DEATHKNIGHT = { [108194]="Asphyxiate", [47476]="Strangulate" },
    DEMONHUNTER = { [217832]="Imprison", [207684]="Sigil of Misery" },
    DRUID       = { [33786]="Cyclone", [5211]="Mighty Bash", [78675]="Solar Beam", [99]="Incapacitating Roar" },
    EVOKER      = { [360806]="Sleep Walk" },
    HUNTER      = { [187650]="Freezing Trap", [19577]="Intimidation", [109248]="Binding Shot", [19386]="Wyvern Sting" },
    MAGE        = { [118]="Polymorph", [122]="Frost Nova", [31661]="Dragon's Breath", [113724]="Ring of Frost" },
    MONK        = { [119381]="Leg Sweep", [115078]="Paralysis", [116844]="Ring of Peace" },
    PALADIN     = { [853]="Hammer of Justice", [20066]="Repentance", [105421]="Blinding Light" },
    PRIEST      = { [605]="Mind Control", [8122]="Psychic Scream", [88625]="Holy Word: Chastise" },
    ROGUE       = { [6770]="Sap", [2094]="Blind", [408]="Kidney Shot", [1833]="Cheap Shot" },
    SHAMAN      = { [51514]="Hex", [192058]="Capacitor Totem", [2484]="Earthbind Totem" },
    WARLOCK     = { [5782]="Fear", [5484]="Howl of Terror", [6789]="Mortal Coil" },
    WARRIOR     = { [46968]="Shockwave", [107570]="Storm Bolt", [5246]="Intimidating Shout" },
}

function M.IsCCSpell(spell_id, class_file)
    if not class_file then return false end
    local s = M.CC_SPELLS[class_file]
    if not s then return false end
    return s[spell_id] ~= nil
end

----------------------------------------------------------------------
-- Class capability tables — mirror mechanics_lib.py
----------------------------------------------------------------------
M.CLASS_CAPABILITIES = {
    interrupt = {
        DEATHKNIGHT=true, DEMONHUNTER=true, EVOKER=true, HUNTER=true,
        MAGE=true, MONK=true, PALADIN=true, ROGUE=true, SHAMAN=true,
        WARLOCK=true, WARRIOR=true,
        DRUID  = { Feral=true, Guardian=true },
        PRIEST = { Shadow=true },
    },
    dispel_magic_def = {
        EVOKER=true,
        MONK    = { Mistweaver=true },
        PALADIN = { Holy=true },
        PRIEST  = { Holy=true, Discipline=true },
        SHAMAN  = { Restoration=true },
    },
    dispel_magic_off = {
        HUNTER=true, SHAMAN=true, WARLOCK=true,
        PRIEST = { Shadow=true, Discipline=true, Holy=true },
    },
    dispel_poison = {
        DRUID=true, MONK=true, PALADIN=true,
        SHAMAN = { Restoration=true },
    },
    dispel_curse = {
        DRUID=true, MAGE=true, SHAMAN=true,
    },
    grip = {
        DEATHKNIGHT=true, WARRIOR=true, DEMONHUNTER=true,
    },
}

function M.ClassCan(class_file, capability, spec)
    local table = M.CLASS_CAPABILITIES[capability]
    if not table or not class_file then return false end
    local entry = table[class_file]
    if entry == nil then return false end
    if entry == true then return true end
    if type(entry) == "table" then
        if spec and entry[spec] then return true end
        if spec == nil then return true end  -- lenient when spec unknown
    end
    return false
end

----------------------------------------------------------------------
-- Lookup helpers
----------------------------------------------------------------------
function M.Get(encounterID)
    return M[encounterID] or M._default
end

-- Trash-pull config (no boss encounter). Falls back to default if the
-- map isn't in TRASH_MECHANICS (e.g. raid trash).
function M.GetTrash(mapID)
    return (M.TRASH_MECHANICS and M.TRASH_MECHANICS[mapID]) or M._default
end
