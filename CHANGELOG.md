# Changelog

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
