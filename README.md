# VoidScout - Mythic+ Player Score & Group Finder

**Works on:** WoW Midnight · WoW Forever (records your fights)

**Behavior-aware player and group scoring for the Premade Groups finder.**

Rating and item level tell you what a player *can* do on paper. VoidScout tells you what they actually *do*: kicks, dispels, dodging mechanics, staying for the whole key, pulling their weight. It docks a scouting panel beside the Premade Groups finder so you can build better groups before you invite — and coaches your own play along the way.

---

## Features

### The 8-axis Utility Score
Every player seen in logged content is graded on eight plain-English axes, which roll up into one **Utility Score**:

| Axis | What it measures |
|---|---|
| **Damage** | Output relative to group and role |
| **Interrupts** | How much of the important, interruptible stuff they actually kicked |
| **Dispels** | Dispels and purges on what mattered |
| **Avoidance** | Avoidable damage taken vs the fight median |
| **Activity** | Time spent doing something useful, not standing around |
| **Survival** | Staying alive through the dangerous moments |
| **Teamwork** | Covering for the group — soaks, raid cooldowns, rescues |
| **Commitment** | How often they finish keys instead of leaving |

### Probability Score — with coaching
- A **0–99 estimate** of how a player will likely perform in *your* group for the *listed* content
- Tells you **why** in plain language — e.g. *"Avoidance 52 — eating mechanics"*, *"Interrupts 70 — missing priority kicks"*
- Useful for vetting applicants **and** for improving your own play

### TimedPossibility
- A **0–99 group score** for whether a specific roster can realistically time a given keystone level, based on the group's combined behavior — not just rating

### Fair scoring — graded on your job
- **Role Picker** — your role is set from your spec automatically
- **Duties** — declare Boss DPS, Add Duty, Kicks, Soaks, Rescues, Dispels, or Utility, plus **boss-specific duties** that appear in known fights
- You're only graded on mechanics you *could and should* have handled, so a DPS isn't dinged for someone else's dispel

### Where you see it
- **Premade Groups panel** — Utility Score, the eight axes, raid progress, timed keys, and the Probability Score for the listed content
- **Applicant badges** — as a leader, every applicant gets a Probability badge so you can scan the whole queue at once
- **Player tooltips** — achievement tier (CE/AOTC/KSM), gear, raid progress, M+ rating, top timed keys, Utility Score, and a Behavior line (interrupt percentile and kick count)
- **Minimap button** — quick access; folds into the shared Void addon icon cluster

---

## Slash Commands

| Command | What it does |
|---|---|
| `/vs` | Show your recent logged fights |
| `/vs consent` | Show your current upload setting |
| `/vs optout` / `/vs optin` | Switch uploads off or on (opting out also requests server-side deletion) |
| `/vs sim` | Turn damage-sim sharing on or off (also: right-click the minimap button) |
| `/vs autosetup` | Re-run the one-time damage meter setup |

---

## Getting Started

1. Install with the CurseForge app, or copy the `VoidScout` folder into `World of Warcraft/_retail_/Interface/AddOns/` (WoW Forever: `_forever_/Interface/AddOns/`).
2. Restart WoW or `/reload`.
3. On first login, choose your upload option in the consent dialog.
4. Open **Group Finder → Premade Groups** — the VoidScout panel docks beside it.

---

## How It Works

- **Clean capture.** Scoring data comes from Blizzard's official damage meter, not the combat log — so VoidScout can't cause taint errors in your other addons.
- **Server-side scoring.** With your consent, per-fight summaries are scored at [voidscout.io](https://voidscout.io).
- **Built-in score bundle.** Scores for a large pool of players ship inside the addon and are refreshed every week, so lookups are instant and work offline.
- **Blizzard's M+ rating built in.** Tooltips and the group finder panel show each player's M+ rating and best timed keys next to the behavior scores, straight from Blizzard. When another rating addon adds the same lines, VoidScout hides the duplicates.

---

## Privacy & Data

A first-run dialog explains exactly what's collected before anything leaves your computer.

- **Local-only mode** — captures stay on your machine; nothing is uploaded
- **Uploads on** — per-fight combat-performance summaries are sent to be scored. Never chat, mail, bags, or anything from players who weren't in your fight
- **Damage sim (optional, off by default)** — tick the box to also share each boss and Mythic+ pull in detail (casts, hits, buffs, resources, stats, talents, gear) for the [voidscout.io](https://voidscout.io) damage sim. Stored under anonymous IDs: no names, no link to a character
- **Delete anytime** — `/vs optout` plus a deletion request removes your data from the server, damage-sim data included; the addon keeps working in local-only mode

### The companion uploader (optional)
WoW addons can't make web requests, so contributing your data uses a small separate app, **voidscout-uploader** — open source (MIT), a single ~7 MB file, nothing else to install. It watches your saved data and uploads new fights in the background.

- **Optional** — VoidScout works fully without it; the uploader just adds *your* fights to the shared pool everyone's scores are compared against
- **One app** covers both VoidScout and VoidRaidToolsReader
- **Get it:** [voidscout.io/install](https://voidscout.io/install) or the [GitHub releases page](https://github.com/bughatti/voidscout-uploader/releases/latest)

---

## Good to Know

- **Settings are per character.** Each character keeps its own VoidScout settings, and a new character starts with the settings of the one you played last, so nothing resets when you update. Right-click the Void hub icon by your minimap and pick **Copy settings from...** to take another character's settings for one Void addon or all of them. Scores and scans stay shared.
- Behavior scores exist only for players who've been logged through VoidScout, so coverage grows as more people contribute. For everyone else, rating and progress carry the vetting.
- VoidScout turns on Blizzard's damage meter setting for you on first run — it needs it to capture fights.

---

## Compatibility

- **WoW Midnight** 12.1.5 (Season 2)
- **WoW Forever**: records your Forever dungeon and raid fights. They're kept apart from retail and never count toward retail scores.
- Standalone — nothing else required

---

*Part of the Void addon family by Vede · MIT licensed · [Source & bug reports](https://github.com/bughatti/voidscout) · [All Void addons](https://www.curseforge.com/members/bughatti/projects) · free M+ & raid player lookups at [voidscout.io](https://voidscout.io) · more at [tinkerline.io](https://tinkerline.io/addons/voidscout/) · [Discord](https://discord.gg/7ZHmx7zMDh)*
