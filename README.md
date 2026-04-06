# SimpleRaidAssign

A lightweight raid planning addon for **World of Warcraft: Burning Crusade Classic** (TBC 2.5.x, Interface `20504`).

Create named raid plans, add TBC bosses from a built-in dropdown, fill each boss with **attributions** (marker + players + context + free-text note), and broadcast them to the raid chat in one click — all without the weight of MRT/ERT.

> **Status:** stable (`v1.0.0`). Core workflow, broadcast, raid sync, and import/export are functional. A settings panel and richer presets are on the roadmap.

---

## Features

- **Raid plans as first-class objects.** Each raid has a name (e.g. "SSC Tuesday Farm"), a creation timestamp, an author, and an ordered list of bosses. You can create, rename, duplicate, **export**, **import** or delete raids from the home screen.
- **Raid Summary home screen.** All saved raid plans, sorted by last edit, with per-card counters: number of bosses, total attributions, and **distinct** assigned players (a player on multiple bosses is counted once).
- **TBC boss dropdown.** Adding a boss picks from a built-in list of every TBC raid boss grouped by instance (Karazhan, Gruul, Magtheridon, SSC, Tempest Keep, Mount Hyjal, Black Temple, Zul'Aman, Sunwell Plateau). The instance name is auto-filled from the boss.
- **Attribution-based model.** An attribution is a `{ marker, players, context, note }` quadruple:
  - **Marker** — optional raid target icon (skull, cross, square, diamond, triangle, moon, star, circle) embedded in chat via `{rtN}` tokens. Clear it with the `[X]` button next to the dropdown or the `(none)` entry.
  - **Players** — one or more player names. Pick from the current group via the `+ From Group` dropdown (class-colored, auto-disables already-assigned players) **or** type any name manually for offline preparation. Each row in the list has an `[X]` button to remove the player.
  - **Context** — free text like "Tanks", "Heals", "Kick phase 1", "Flame tank phase 2", "Parasite kite".
  - **Note** — multi-line free text for tactical detail (priorities, timings, callouts). Included in chat broadcasts in parentheses after the players list.
- **One-click chat announce.** A single `[Announce]` button per boss broadcasts every attribution to the selected channel (`RAID`, `RAID_WARNING`, `PARTY`, `SAY`, `GUILD`, `OFFICER`, default `RAID_WARNING`). Messages auto-split on segment boundaries when they exceed the 255-char chat limit. A `[Preview]` button renders the would-be message locally with the marker icons substituted in so you can read what you're about to send.
- **Import / Export.** Each raid can be serialized to a single ASCII string (`SRA1:<encoded>`) ready to copy-paste into Discord, a forum post, a chat window or a text file. Importing rebuilds the raid with a fresh id and lets you choose a new name.
- **Live raid sync.** Raids are broadcast over a versioned addon-message protocol (`SRA1`) with last-write-wins reconciliation based on `updatedAt`. No Ace3 dependency — the serializer is self-contained and is reused by the import/export feature.
- **Draggable minimap button** with the Grey Skull icon. Left-click toggles the window, right-click pushes all raids, drag relocates around the minimap edge.
- **ElvUI compatible.** Falls back to a clean dark backdrop when ElvUI is absent.
- **SavedVariables migration safe.** Non-destructive defaults merge keeps your data intact across updates.

---

## Installation

### From a release zip

1. Download `SimpleRaidAssign.zip` from the [Releases](../../releases) page.
2. Extract the `SimpleRaidAssign/` folder into:
   - **Windows:** `World of Warcraft\_classic_\Interface\AddOns\`
   - **macOS:** `World of Warcraft/_classic_/Interface/AddOns/`
3. Restart the game (or `/reload` if it was already running).

### From source

```bash
git clone https://github.com/gpiecq/SimpleRaidAssign.git
cd SimpleRaidAssign
bash package.sh
# SimpleRaidAssign.zip is ready to install
```

---

## Usage

### Slash commands

| Command | Effect |
|---|---|
| `/sra` | Toggle the main window |
| `/sra sync` | Push every local raid to the group (addon channel) |
| `/sra request` | Ask the group to push their raids to you |
| `/sra reset` | Wipe ALL data (with confirmation popup) |

`/simpleraidassign` is also available as a long-form alias.

### Workflow

1. Open the window with `/sra` (or click the **Grey Skull** minimap button). You land on the **Raid Summary** screen.
2. Click **`+ New Raid`**, give it a name → you enter the **Raid Editor**.
3. Click **`+ Add Boss`** in the left sidebar and pick a TBC boss from the two-level dropdown (instance → boss).
4. Click **`+ Add Attribution`** in the middle column → a blank attribution appears and is automatically selected.
5. In the right edit panel:
   - Pick a **marker** from the dropdown (or leave it as `(none)`, or hit `[X]` to clear)
   - Type the **context** (e.g. "Tanks", "Kick phase 1") and click outside the field to commit
   - Add **players**: either click `+ From Group` and pick from the current raid (class-colored), OR type a name in the input and click `[Add]` (works for absent players, useful when prepping a plan in advance). Each player in the list has an `[X]` to remove.
   - Optionally fill the **Note** textarea with tactical detail. It will be appended to the chat broadcast.
6. When the boss is ready, click **`[Announce]`** at the bottom of the middle column to broadcast to the chat channel selected in the `Announce to:` dropdown. Use **`[Preview]`** to see the rendered message locally first (with the marker icons substituted in) without actually sending anything.
7. Return to the summary with **`< Back`** to work on another raid.

### Sharing a raid plan

- **Export**: in the Raid Summary, click the `Export` button on a raid row. A dialog opens with the serialized string (`SRA1:...`) already selected. Press `Ctrl+C` and paste it anywhere (Discord, forum, text file).
- **Import**: in the Raid Summary header, click `Import`. Paste the string in the text area, optionally edit the auto-suggested name, then click `Import`. A new raid is created with a fresh id and opens immediately in the Raid Editor.

### Example announce

For an Illidan plan with 5 attributions, the addon sends:

```
[Illidan Stormrage] Tanks: TankA, TankB / Heals: HA, HB, HC / {rt8} Kick phase 1: IntA, IntB (focus interrupter demo) / {rt7} Flame tank phase 2: TankC / {rt6} Parasite kite: HealerX
```

- The `{rt8}` `{rt7}` `{rt6}` tokens are converted by WoW's chat parser into the actual in-game raid target icons on the receivers' chat windows.
- Notes are appended in parentheses after the players list.
- Segments are separated by ` / ` (the pipe character `|` is reserved by WoW's chat parser for escape codes and cannot be used).
- Messages exceeding 255 characters are auto-split on segment boundaries into consecutive chat lines.

---

## Architecture

The addon is split into independent modules loaded sequentially via the `.toc`, communicating exclusively through an internal event bus (`NS:RegisterCallback` / `NS:FireCallback`). Each module owns its own `CreateFrame` for Blizzard events.

| File | Responsibility |
|---|---|
| `Core.lua` | Addon bootstrap, `DEFAULTS` template, non-destructive merge, event bus, slash commands, reset popup |
| `AssignData.lua` | Static reference data: 8 raid target marker icons (with `{rtN}` chat tokens), class colors, `ColorizeName` helper |
| `TBCBosses.lua` | TBC raid bosses grouped by instance, used by the "Add Boss" dropdown |
| `Roster.lua` | Raid / party / solo group scanning, class detection, role hints |
| `Raids.lua` | Raid CRUD: create, rename, duplicate, delete, iterate (sorted by `updatedAt` desc), counters, **Export / Import** (`SRA1:` format) |
| `Attributions.lua` | Boss (encounter) CRUD + attribution CRUD scoped by `(raidKey, encounterKey, attribId)`, plus `AddPlayer` / `RemovePlayer` / `ClearMarker` |
| `Broadcast.lua` | English chat string builder, marker token rendering for local preview, 255-char auto-splitting on `/` boundaries, channel fallback, `SendChatMessage` wrapper |
| `Comms.lua` | Addon-message sync (`SRA1` protocol v2), push/pull of whole raids, last-write-wins merge, self-contained serializer (also reused by export/import) |
| `UI.lua` | Two-screen navigation: Raid Summary (home) + Raid Editor (3-column: boss sidebar / attribution list / edit panel), Import/Export dialog, minimap button, ElvUI skinning |

The shared namespace is exposed as `local ADDON_NAME, NS = ...` in every file. SavedVariables live in `SimpleRaidAssignDB` (account-wide) and `SimpleRaidAssignCharDB` (per character, UI state only).

### Data model

```lua
SimpleRaidAssignDB.raids[raidKey] = {
    name, createdAt, updatedAt, createdBy, updatedBy, notes,
    encounters = {
        [encKey] = {
            name, instance,
            attributions = {
                [attribId] = {
                    marker  = nil | 1..8,            -- raid target icon, optional
                    players = { "Name1", ... },      -- 1 or more
                    context = "free text",           -- e.g. "Tanks", "Kick phase 1"
                    note    = "multi-line detail",   -- appended to chat broadcast
                },
            },
            order = { attribId1, attribId2, ... },
            updated, updatedBy,
        },
    },
    encounterOrder = { encKey1, encKey2, ... },
}
```

### Export string format

```
SRA1:<encoded raid table>
```

The body is the same self-contained serialized format used by the addon-message sync layer (`Comms.Encode` / `Comms.Decode`). It is plain ASCII, contains no raw newlines / pipes / tabs, and is safe to copy-paste anywhere. The `SRA1:` prefix is a versioned magic header so a future incompatible format can ship as `SRA2:` without breaking older imports.

---

## Building

### Local build

```bash
bash package.sh
```

Produces `SimpleRaidAssign.zip` in the repo root containing the installable `SimpleRaidAssign/` folder. Uses the system `zip` tool when available and transparently falls back to PowerShell `Compress-Archive` on Windows hosts that lack it.

### CI builds

Two GitHub Actions workflows ship with the repo:

- **`.github/workflows/build-addon.yml`** — runs on every PR targeting `main`, uploads a versioned artifact (`SimpleRaidAssign-v<ver>-pr<num>`).
- **`.github/workflows/release.yml`** — runs when a PR is merged into `main`. Bails out if the tag already exists, otherwise builds the zip, extracts the matching `CHANGELOG.md` section as release notes, and creates a GitHub Release tagged `vX.Y.Z`.

### Release workflow

1. Develop on a feature branch and open a PR — the artifact is built automatically and downloadable from the Actions tab.
2. Before merging, bump `## Version:` in `SimpleRaidAssign.toc` and add a `## [x.y.z]` section to `CHANGELOG.md`.
3. Merge the PR — `release.yml` tags, builds and publishes the GitHub Release with notes extracted from the changelog.

---

## Compatibility

- **WoW client:** Burning Crusade Classic 2.5.x (Interface `20504`).
- **Other addons:** ElvUI is optional but supported via `SetTemplate("Transparent")`.

---

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md) for the full version history. Notable entries are also published as GitHub Release notes.

---

## License

TBD.
