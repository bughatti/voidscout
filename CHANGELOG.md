# Changelog

## [0.37.16] — 2026-10-29

### Fixed
- **Last boss of a Mythic+ key scored from the whole run.** When a key completes, Blizzard's damage meter switches to the whole run, so the last boss read about ten times its own damage. VoidScout now reads that boss's own meter session.
- **Damage-sim sharing inside a key:** your fight details were lost on every pull when the game hid a value. Now only the hidden values are left out.

### Changed
- **Combat logging, when VoidScout manages it, now starts when you enter a Mythic dungeon** instead of when the key starts. That way the game's snapshot of the group at the key start (gear, talents, buffs) is in the log. It stops when you leave. Logging you turned on yourself is never touched.

## [0.37.15] — 2026-10-29

### Added
- **Damage-sim sharing (optional, off by default).** A new box in the upload dialog lets you also share each boss and Mythic+ pull in detail for the voidscout.io damage sim: casts, hits, buffs, resources, stats, talents and gear. It is stored under anonymous IDs, with no names. If you already allow uploads, VoidScout asks you once. Turn it on or off anytime: right-click the minimap button, or `/vs sim`.
- The minimap button tooltip shows whether damage-sim sharing is on.

## [0.37.14] — 2026-10-28

### Removed
- **An old data file with other players' fight history.** The addon stopped using it in June, but it was still in the download. Nothing changes in game.

## [0.37.13] — 2026-10-27

### Fixed
- **Timed keys were saved as depleted.** Key results now come from the game's completion info, so a timed run is recorded as timed.
- **Raid kills no longer count as Mythic+**, and the dungeon difficulty is read correctly.
- **Trash and boss pulls:** deaths on trash after the first boss are counted, a trash pull that turns into a boss is dropped instead of saved twice, and boss scoring uses the run state at the moment the boss dies.
- **Spec and item lookups** use the current game APIs (they broke when the old ones were switched off).
- **Group finder:** live rating shows, listing text the game hides no longer causes errors, and the leader view is Mythic+ only.
- **Interrupt and dispel credit** for Balance Druid, Restoration Druid and Preservation Evoker; Paladin battle rez counted.
- **Gear check gem count:** sockets are no longer counted twice, and gems in items without an enchant are seen, so fully gemmed gear scores full marks.
- Enemy forces % read from the scenario, minimap left-click works in combat, and inspect retries when the first try fails.

### Added
- VoidScout shows up in the VoidHub launcher.

## [0.37.12] — 2026-10-22

### Fixed
- **Uploads credited to the wrong character.** The uploader guessed who you are by picking whoever had the most saved fights, and that list includes everyone you've grouped with. VoidScout now saves which character you're playing, so uploads are credited to you. Use uploader v0.4.5 or newer.

## [0.37.11] — 2026-10-22

### Fixed
- **Follower dungeons counted twice.** The follower NPCs (Captain Garrick and the others) were recorded as group members, so each boss in a follower dungeon was saved twice, and each NPC showed up as a player. Only real players are recorded now.

## [0.37.10] — 2026-10-18

### Fixed
- **Season 2 in the LFG inspect panel.** The panel was still set up for Season 1:
  - **Raid Progress** now lists **The Venomous Abyss** (8 bosses) first. Your own kills are tracked as you make them and from this week's lockouts.
  - **Top Keys** now shows Season 2 keys. Before, every Season 2 key was filtered out, so it read "-".
  - The local score now counts Season 2 raid and dungeon fights.
- **M+ Score showed 0** for anyone who hasn't run a key this season. It now shows last season's score, marked "(last season)".
- **Coaching tips** no longer list an axis you're already strong in (75+).
- **Classes with no friendly dispel** (Death Knight, Warrior, Rogue, Hunter, Demon Hunter) no longer get a "Dispels 0" tip. Their Dispels axis now shows "n/a" instead of dragging the average down.

## [0.37.9] — 2026-10-14

### Changed
- Updated for WoW 12.1.5 — no longer shows as out of date.

### Fixed
- **Reading a player's item level** (`/vs group` and the scan) errored after 12.1.5 removed an old game function.

### Added
- `/vs metercheck` — shows, for your last scored fights, whether WoW hid any group member from the damage meter (12.1.5 can hide some players' identities).

## [0.37.8] — 2026-10-06

### Fixed
- `/vs group` no longer scores NPC followers as players, and names the dungeon you're in instead of "?".
- `/vs show` outside the Group Finder tells you where the panel lives; the help line lists the player commands.
- The Void addons info panel (`/vhub info`) now lists only the addons you can actually get, with up-to-date descriptions.

## [0.37.7] — 2026-08-11

### Changed
- Compatibility with patch 12.1 "Curse of Ula'tek" (TOC interface bump to 12.1).

## [0.37.6] — 2026-07-09

### Changed
- Removed all remaining third-party parse scraping and re-presentation. VoidScout no
  longer reads or caches Archon/WarcraftLogs parse percentiles from tooltips, and raid
  progress is now sourced purely from Blizzard's official API plus your own live kills —
  never another site's data. Any previously-cached scraped values are wiped on load.

## [0.37.5] — 2026-07-08

### Fixed
- Your own raid progress now updates the instant you kill a boss, instead of waiting on a
  periodic external scrape. Killing a boss for the first time (e.g. finally downing L'ura) could
  still show the old count — "6/9 Heroic" after a 9/9 night — because progress read only from the
  slower-refreshing snapshot. It now counts your live per-boss kill flags and takes the higher of
  the two, so your tier progress is always current for you.

## [0.37.4] — 2026-06-24

### Fixed
- Upload-consent dialog no longer re-prompts on every reload. v0.37.3 bumped the consent version,
  which accidentally invalidated existing "allowed"/"local" choices; now any prior choice is honored
  and only a genuinely new data category would ever re-prompt — so you're asked once and never nagged.
- Fixed a Lua error ("attempt to index global 'VoidScoutCharDB'") when logging into a character that
  had never run VoidScout (e.g. a fresh alt). Per-character data now initializes safely.

## [0.37.3] — 2026-06-24

### Changed
- The first-run upload-consent dialog now explains that uploads require a small separate companion
  app (`voidscout-uploader`) and points to **voidscout.io/install** — so enabling uploads no longer
  silently does nothing for people who don't realize a second piece is needed. Existing users will
  see the dialog once more (consent v3).

## [0.37.2] — 2026-06-23

### Changed
- Updated for patch 12.0.7 (interface bumped to 120007).
- Quieter, cleaner login — the background sync-cache merge no longer prints a status line to
  chat on every login. The merge still happens; it's just silent now.
