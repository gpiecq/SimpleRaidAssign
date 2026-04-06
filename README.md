# WowShiftAssign

A lightweight raid role assignment addon for **World of Warcraft: Burning Crusade Classic** (TBC 2.5.x, Interface `20504`).

Plan, share and live-sync per-encounter role assignments — tanks, healers, interrupts, decurses, kites, mind controls, raid cooldowns... — without the weight of MRT/ERT.

> **Status:** alpha (`v0.1.0`). The core architecture is in place; UI polish and richer encounter templates are on the roadmap.

---

## Features

- **Per-encounter role boards.** Create one assignment sheet per boss, populated either from scratch or from a built-in template (Lady Vashj, Kael'thas, Illidan, Blank).
- **13 built-in role types** out of the box: Tank, Main Heal, Tank Healer, Raid Healer, Interrupt, Decurse, Magic Dispel, Tranq Shot, Mind Control, Kite, Carry / Pick-up, Raid Cooldown, Custom.
- **Class-colored player slots** sourced from the live raid roster (TBC + modern API compatible).
- **Live raid sync.** Assignments are broadcast over the addon channel (`WSA1` prefix) using a versioned protocol with last-write-wins reconciliation. No Ace3 dependency — the serializer is self-contained.
- **ElvUI compatible.** Falls back to a clean dark backdrop when ElvUI is absent.
- **SavedVariables migration safe.** Non-destructive defaults merge keeps your data intact across updates.

---

## Installation

### From a release zip

1. Download `WowShiftAssign.zip` from the [Releases](../../releases) page.
2. Extract the `WowShiftAssign/` folder into:
   - **Windows:** `World of Warcraft\_classic_\Interface\AddOns\`
   - **macOS:** `World of Warcraft/_classic_/Interface/AddOns/`
3. Restart the game (or `/reload` if it was already running).

### From source

```bash
git clone https://github.com/your-org/WowShiftAssign.git
cd WowShiftAssign
bash package.sh
# WowShiftAssign.zip is ready to install
```

---

## Usage

### Slash commands

| Command | Effect |
|---|---|
| `/wsa` | Toggle the main window |
| `/wsa settings` | Open the settings panel *(planned)* |
| `/wsa sync` | Push every local encounter to the raid |
| `/wsa request` | Ask the raid to push their assignments to you |
| `/wsa reset` | Wipe ALL data (with confirmation popup) |

`/shiftassign` is also available as a long-form alias.

### Workflow

1. Open the window with `/wsa`.
2. Click **+ New** in the left pane to create an encounter (or seed it from a template — coming via the encounter context menu).
3. Click **+ Add Role** in the right pane and pick a role type from the dropdown.
4. Click **Assign Me** on a row to put yourself in that slot. (Drag-and-drop assignment from the roster panel is on the roadmap.)
5. Click **Push to Raid** at the bottom to broadcast the encounter to everyone running WowShiftAssign in your group.

---

## Architecture

The addon is split into independent modules loaded sequentially via the `.toc`, communicating exclusively through an internal event bus (`NS:RegisterCallback` / `NS:FireCallback`). Each module owns its own `CreateFrame` for Blizzard events.

| File | Responsibility |
|---|---|
| `Core.lua` | Addon bootstrap, `DEFAULTS` template, non-destructive merge, event bus, slash commands, reset popup |
| `AssignData.lua` | Static data: role types, class colors, encounter templates |
| `Roster.lua` | Raid / party / solo group scanning, class detection, role hints |
| `Assignments.lua` | CRUD over encounters, roles and slots; emits `DATA_UPDATED` |
| `Comms.lua` | `WSA1` addon-message protocol, self-contained serializer, last-write-wins merge |
| `UI.lua` | Main window, encounter list, role editor, ElvUI skinning |

The shared namespace is exposed as `local ADDON_NAME, NS = ...` in every file. SavedVariables live in `WowShiftAssignDB` (account-wide) and `WowShiftAssignCharDB` (per character, UI state only).

---

## Building

### Local build

```bash
bash package.sh
```

Produces `WowShiftAssign.zip` in the repo root containing the installable `WowShiftAssign/` folder. Uses the system `zip` tool when available and transparently falls back to PowerShell `Compress-Archive` on Windows hosts that lack it.

### CI builds

Two GitHub Actions workflows ship with the repo:

- **`.github/workflows/build-addon.yml`** — runs on every PR targeting `main`, uploads a versioned artifact (`WowShiftAssign-v<ver>-pr<num>`).
- **`.github/workflows/release.yml`** — runs when a PR is merged into `main`. Bails out if the tag already exists, otherwise builds the zip, extracts the matching `CHANGELOG.md` section as release notes, and creates a GitHub Release tagged `vX.Y.Z`.

### Release workflow

1. Develop on a feature branch and open a PR — the artifact is built automatically and downloadable from the Actions tab.
2. Before merging, bump `## Version:` in `WowShiftAssign.toc` and add a `## [x.y.z]` section to `CHANGELOG.md`.
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
