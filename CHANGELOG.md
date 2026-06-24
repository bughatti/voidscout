# Changelog

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
