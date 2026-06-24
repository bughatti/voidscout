# VoidScout

**Utility-aware applicant and group scoring for Looking-For-Group premade content.**

VoidScout adds a panel to Blizzard's Premade Groups finder that scores players on what they
actually *do* in content — interrupts, dispels, mechanic avoidance, staying for the whole key,
pulling their weight — not just their item level or M+ rating. Where RaiderIO tells you a player's
*score*, VoidScout tells you their *behavior*: the signal that actually decides whether a pug times
the key or wipes on the first boss.

## Why it exists (intent)

M+ rating and ilvl tell you what a player *can* do on paper. They don't tell you whether a player
kicks, dispels, sidesteps avoidable damage, or bails the moment a key looks dicey. Group leaders
learn this the hard way. VoidScout's purpose is to surface that behavioral track record — and a
forward-looking estimate of how someone will perform in *your* group for *this* content — *before*
you invite, so you build better groups with less guesswork.

It's a thin client over a scoring backend: the addon captures clean combat data locally, an opt-in
uploader sends per-fight summaries to a server that does the heavy scoring, and a baked-in data
bundle brings the computed scores back into the game so lookups are instant and offline.

## What it scores

### The 8-axis Utility model
Every player seen in logged content is graded on eight plain-English axes:

| Axis | What it measures |
|---|---|
| **Damage** | Output relative to group/role (rDPS-aware) |
| **Interrupts** | How much of the interruptible, important stuff they actually kicked |
| **Dispels** | Dispel/purge uptime on what mattered |
| **Avoidance** | Avoidable damage taken vs the fight median |
| **Activity** | Time-on-target / not standing around |
| **Survival** | Staying alive through the dangerous moments |
| **Teamwork** | Cover, raid-CD usage, soaks — pulling for the group |
| **Commitment** | Per-pug stay rate — do they finish keys or bail |

These roll up into a **Utility Score** (a backward-looking behavioral grade).

### Probability Score — forward-looking, with coaching
A **Probability Score** (0–99) estimates how a given player is likely to perform in *your* group
for the *listed content* — and it tells you *why*, in plain language: e.g. *"Avoidance 52 — eating
mechanics,"* *"Interrupts 70 — missing priority kicks,"* *"Damage 69 — push CDs/trinkets."* It's
coaching, not just a number — useful for vetting an applicant **and** for improving your own play.

### TimedPossibility — can this group time the key
A **0–99 group score** for whether a specific roster can realistically time a given keystone level,
factoring the composition's collective behavioral execution — not just raw rating.

## Role & duty declaration (fair scoring)

Scores are only fair if you're judged on what you're actually responsible for. The **Role Picker**
lets each player declare:
- **Role** — Tank / Healer / DPS, auto-set from your spec and updated when you respec.
- **Duties** — Boss DPS, Add Duty, Kicks, Soaks, Rescues, Dispels, Utility, plus **boss-specific
  duties** (orbs, soaks, etc.) that appear automatically when you're in a known fight.

VoidScout then grades you only on the mechanics you *could and should* have handled (a per-boss
mechanic database drives this), so a DPS isn't dinged for a dispel that wasn't theirs, and a
designated kicker is held to the kicks. Declared duties and behavior inferred from the log both
feed the same scoring engine.

## Where you see it

- **Premade Groups panel** — VoidScout docks a RaiderIO-style profile panel beside the finder.
  Selecting an applicant shows their Utility Score, the eight axes, RaiderIO rating, raid progress
  matrix, timed keys, and the forward-looking Probability Score for the listed content.
- **Applicant-row badges** — as a leader, each applicant in your list gets a Probability badge so
  you can scan the whole queue at a glance without clicking each one.
- **Player tooltips** — mouse over anyone and the tooltip is enriched with their achievement tier
  (CE/AOTC/KSM), gear, raid progress, M+ score, top timed keys, Utility Score, and the Behavior
  line (interrupt percentile + kick count).
- **Minimap button** — quick access, and it folds into the shared VoidHub icon cluster.

## How it works

- **Clean capture.** Scoring data comes from Blizzard's official `C_DamageMeter` engine, not the
  combat log — deliberately, to stay clear of the 12.0 secret-value taint that breaks
  SecureActionButton addons. VoidScout's capture can't taint your other addons.
- **Opt-in upload.** With your consent, per-fight summaries are uploaded to `api.voidscout.io`,
  which parses them server-side and computes the axis scores.
- **Baked-in bundle.** Computed scores for a large pool of players ship inside the addon as
  `VoidScoutBundle.lua` (regenerated regularly), so in-game lookups are instant, offline, and free
  at runtime — the same model RaiderIO uses for its database.
- **RaiderIO blend.** If RaiderIO is installed, VoidScout reads its M+/raid data too, so the panel
  shows the rating *and* the behavior together.

## Data & privacy

A first-run dialog spells out exactly what's collected before anything leaves your client.

- **Local-only mode:** captures stay on your machine, nothing is uploaded.
- **Uploads enabled:** per-fight summaries go to `api.voidscout.io` to be scored.
- **Deletion on request:** `/vs optout` plus a deletion request removes your data from the server.
  The addon stays fully usable in local-only mode.

It scores behavior, not chat or personal data, and honors a server-side opt-out list.

## The companion uploader (optional)

WoW addons can't make web requests, so contributing your data to the community pool uses a small
**separate companion app**: **[voidscout-uploader](https://github.com/bughatti/voidscout-uploader)** —
open-source (MIT), a single ~7 MB binary, no install dependencies. It watches your SavedVariables and
uploads new scored fights to `api.voidscout.io`.

- **Optional.** VoidScout works fully without it (bundle-backed scores + tooltips); the uploader just
  lets *your* data feed the shared percentile pool everyone reads from.
- **Private + opt-in.** First-run consent dialog; it uploads only combat-performance data — never
  chat, mail, bags, or anything from players not on your screen. Request deletion anytime via `/vs optout`.
- **Get it:** **https://voidscout.io/install** (or the [GitHub Releases](https://github.com/bughatti/voidscout-uploader/releases/latest)). Run it once; it sits quietly in the background.

## Install

1. Copy the `VoidScout` folder into `World of Warcraft\_retail_\Interface\AddOns\`.
2. Restart WoW (or enable it at the character-select AddOns screen).
3. On first login, choose your consent option in the dialog that appears.
4. Open **Group Finder → Premade Groups** — VoidScout's panel docks to the side.

Self-contained (VoidLib embedded). **RaiderIO** is recommended — it adds M+/raid rating alongside
the behavioral scores.

## Slash commands

| Command | Action |
|---|---|
| `/vs` | Open settings / consent options |
| `/vs optout` / `/vs optin` | Switch upload mode (and request server-side deletion) |
| `/vs autosetup` | Re-run the one-time damage-meter cvar setup |
| `/vsscan` | Diagnostic: dump visible LFG search-result fields |
| `/vstrash` | Diagnostic: show auto-discovered trash casts |

## Notes

- Behavioral scores (Utility, interrupt %, etc.) only exist for players who've been *logged*
  through VoidScout, so coverage grows with the user base. For everyone else, the RaiderIO rating
  and raid/M+ data carry the vetting.
- Requires the Blizzard damage-meter cvar (VoidScout enables it for you on first run).

Author: Vede · Backend: api.voidscout.io · Discord: https://discord.gg/7ZHmx7zMDh
