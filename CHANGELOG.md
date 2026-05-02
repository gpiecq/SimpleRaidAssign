# Changelog

All notable changes to SimpleRaidAssign will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-05-02

### Added

#### Per-boss attribution categories
- Each boss can now hold an ordered list of **categories** (e.g. `P1`, `P2`, `Adds`, `Burn`) inside which attributions are grouped. Categories are optional: a boss with no category renders exactly like in v1.1, all its attributions in an implicit `- Uncategorized -` section at the top of the list.
- New `+ Add Category` button next to the master "Select all" checkbox. It opens a preset dropdown (`P1`, `P2`, `P3`, `P4`, `Pull`, `Adds`, `Burn`, `Transition`, `Heroism`) plus a `Custom...` entry that pops up a text input (max 32 chars).
- Each category renders as a foldable header. Per-header controls: chevron `v/>` for fold, `^` / `v` to reorder among siblings, `R` (or double-click on the label) to rename inline, `X` to delete (silent on empty, popup confirmation on non-empty), `+ Attrib` to add an attribution scoped to this category.
- New `Category:` dropdown in the right edit panel (between the marker dropdown and the context input) lets the selected attribution be reassigned to another category, to `(none)`, or to a brand new category created on the spot via `+ New Category...`.
- Fold state is persisted per character in `SimpleRaidAssignCharDB.ui.collapsed[<raidKey>:<encKey>:<catId>]` (existing CharDB slot reused). Stale entries are garbage-collected on `ADDON_LOADED`.

#### Per-category chat announce
- The `[Announce]` button now emits **one chat message per category**: `[Boss - <CategoryName>] segment / segment / ...`, in `categoryOrder`. The Uncategorized bucket emits a generic `[Boss] ...` message first (identical to the v1.1 format).
- Empty categories and categories whose every attribution is unchecked are silently skipped.
- The 255-char auto-split applies independently per block: each block is run through `ChunkMessages` with its own title.

#### Tri-state announce checkboxes
- Each category header now has its own announce checkbox. State is tri-state: `all` (every attrib in the category checked) / `some` (mixed - visualised by dimming the checked texture) / `none`. Clicking cascades: `all` -> `none`, otherwise -> `all`.
- The master `Select all / none` checkbox is now tri-state across the whole encounter using the same rules.

### Changed
- **`Attributions.lua`** API additions: `AddCategory`, `RenameCategory`, `DeleteCategory`, `MoveCategory`, `IterateCategories`, `GetCategory`, `SetAttributionCategory`. `AddAttribution` accepts an optional `categoryId` argument (defaults to `nil` -> Uncategorized - backwards compatible). `MoveAttribution` now scans for the closest neighbour with the same `categoryId` instead of the immediate one, so up/down arrows stay scoped to a category.
- **`Broadcast.lua`** API: `BuildSegments` accepts an optional `categoryFilter` argument (`nil` = legacy, `"uncategorized"`, or a `catId`). `BuildMessages` now produces multiple titled blocks. Public signature of `Announce` and `Preview` is unchanged.
- **Lazy migration**: legacy v1.1 encounters acquire empty `categories = {}` and `categoryOrder = {}` the first time they are read via `Attributions:GetEncounter`. No `ADDON_LOADED` migration step.

### Compatibility
- **`SRA1` protocol unchanged.** New encounter fields (`categories`, `categoryOrder`) and the `categoryId` field on attributions are sent as-is via the generic serialiser. v1.1 clients store the unknown fields in their SavedVariables and round-trip them intact when re-pushing; their own UI only renders the flat list, as before.
- **Export / Import (`SRA1:` prefix) format unchanged.**

## [1.1.0] - 2026-04-08

### Added

#### Per-attribution announce filter
- Each attribution row in the editor now has a **checkbox** on its left edge that controls whether the attribution is included in the next chat broadcast. The checkbox toggles independently of the row selection — clicking it does not change which attribution is loaded in the right edit panel.
- A **master "Select all / none" checkbox** sits above the attribution scroll list. It is automatically synced with the row state (checked when every attribution is selected, unchecked otherwise) and a click flips the entire list between "all checked" and "all unchecked".
- New attributions default to **selected**, so the announce flow stays one-click when you do not need filtering.
- Selection state is held in a module-local table (`deselectedAttribs`) and is **not persisted to SavedVariables** — it resets between sessions on purpose, so a new login starts with everything selected.

### Changed
- **`Broadcast.lua`** API now accepts an optional `filter` parameter (a `{ [attribId] = true }` set) on `BuildSegments`, `BuildMessages`, `Announce` and `Preview`. When provided, only the listed attributions are included in the segments. When `nil`, the legacy "include everything" behavior is preserved.
- **`Announce` / `Preview` button handlers** now build a filter from the current row checkboxes and pass it to `Broadcast`. If no attribution is currently selected, both buttons print `"No attributions selected to announce."` (resp. preview) and return early instead of sending an empty message.
- The attribution scroll frame moved down ~24 px to make room for the master checkbox row above it; the rest of the panel layout (announce bar, edit panel, etc.) is unchanged.

## [1.0.0] - 2026-04-06

First stable release. Brings the addon under its final name (`SimpleRaidAssign`), polishes the editor flow, ships import/export, adds the per-attribution note field, the player picker dropdown and the minimap button.

### Added

#### Import / Export
- `Raids:Export(raidKey)` serializes a single raid to a portable string with the format `SRA1:<encoded>`. The encoded body uses the existing self-contained serializer from `Comms.lua` (no Ace3 dependency, ASCII only, no raw newlines / pipes / tabs — safe to copy-paste into chat windows or forum posts).
- `Raids:Import(text, newName)` parses an exported string, validates the format and required fields, and creates a new raid with a fresh id and new metadata (`createdAt`/`createdBy`/`updatedAt`/`updatedBy` are reset to the current player and time). Errors are returned as `(nil, "human readable message")`.
- `Raids:PeekImportName(text)` decodes just the original raid name from an import string without actually importing, used to pre-fill the "New name" input.
- New buttons on the Raid Summary screen: `Import` next to `+ New Raid` in the header, and `Export` on every raid row (between `Rename` and `Duplicate`).
- Reusable Import/Export dialog (520×380, draggable) with a multi-line `EditBox` inside a `ScrollFrame`. Export mode highlights the string for instant `Ctrl+C`. Import mode shows an additional "New raid name" input that auto-fills with `<original name> (imported)` after a paste, and the user can override it freely.

#### Note field per attribution
- New `note` field on the attribution data model, edited via a multi-line `EditBox` (`textarea`-style) in the right edit panel under the players list.
- The note is **included in chat broadcasts**, appended in parentheses after the players list (e.g. `Tanks: TankA, TankB (alterner les CDs)`), with newlines collapsed and pipe characters stripped so the message stays valid.
- Notes are persisted in `db.raids[].encounters[].attributions[].note` and synced through the same comms protocol as the rest of the raid.

#### Player picker dropdown
- New `+ From Group` button in the right edit panel that opens a dropdown of the current raid / party members. Each entry is class-colored (warrior beige, mage cyan, etc.). Players already assigned to the current attribution are listed but disabled (no duplicates possible).
- The previous comma-separated `playersBox` was replaced by a vertical scrollable list of assigned players (each with a `[X]` remove button), plus a single-line text input + `[Add]` button below for manual entry. Manual typing keeps working in parallel for offline preparation when the named player is not in the current group.

#### Marker clearing
- New `Attributions:ClearMarker(raidKey, encounterKey, attribId)` helper that explicitly sets the marker to nil without the previous `{ marker = false }` patch hack.
- New `[X]` button next to the marker dropdown in the right edit panel — single click to clear the marker. The dropdown's `(none)` entry still works as a fallback.

#### Minimap button
- Draggable minimap button using the **Grey Skull** raid target icon as its texture (matches the addon's marker theme).
- Left-click toggles the main window, right-click pushes all raids to the group via the comms layer.
- Position persisted across sessions in `NS.db.settings.minimapPos` (angle in degrees on the minimap edge).
- Tooltip lists left/right click and drag actions.

### Changed

- **Renamed** the addon from `WowShiftAssign` to `SimpleRaidAssign`. The folder, `.toc` filename, SavedVariables (`SimpleRaidAssignDB` / `SimpleRaidAssignCharDB`), slash commands (`/sra`, `/simpleraidassign`), addon-message comms prefix (`SRA1`), and all frame / popup / dropdown names have been updated. Existing data from `WowShiftAssign` is **not** auto-migrated; back up the old `WTF/.../SavedVariables/WowShiftAssign.lua` file if you want to keep your raid plans, then re-create them under the new name.
- **Single `Announce` button** instead of separate `Announce EN` / `Announce FR` toggles. The output is now always English. The previous `announceLanguage` setting was removed from `DEFAULTS`. The localization scaffolding in `Broadcast.lua` was simplified to a flat English-only label table, but the dual-language groundwork could be re-introduced later if needed.
- **Default announce channel is now `RAID_WARNING`** instead of `RAID`. Existing installs with a saved `announceChannel` keep their previous value (the merge is non-destructive).
- **`Preview` renders raid target icons** by substituting `{rt1}..{rt8}` chat tokens with `|TInterface\TargetingFrame\UI-RaidTargetingIcon_N:0|t` texture inlines before printing locally. The actual `Announce` flow still sends the raw tokens because WoW's chat parser handles them on the receiver side.
- **Players counter on the Raid Summary** now counts **distinct** player names across all bosses and attributions, instead of the raw sum of slot occurrences. A player assigned to three bosses is counted once.
- **Broadcast message separator** changed from `|` to `/`. The pipe character is reserved by WoW's chat protocol for escape codes (`|cff...|r`, `|Hlink|h`); using it as a free-text separator caused `SendChatMessage` to reject messages with "Invalid escape code".
- **`SafeSetText` helper** in the right edit panel: refuses to overwrite an `EditBox` while it has keyboard focus, preventing background events (`ROSTER_UPDATED`, `DATA_UPDATED`) from wiping the user's in-progress typing.
- **`CommitPendingEdits` helper** force-commits any focused right-panel `EditBox` (context, note, players input) before changing the selected attribution / boss, so pending text is saved against the correct id instead of being lost.
- **Editor channel dropdown** entries are now `notCheckable = true` for uniform left padding (the previously-checked entry had an extra checkbox indent the others lacked, breaking alignment on TBC Anniversary clients). Same fix applied to the marker dropdown.
- **Window size** increased from 820×520 to 820×600 to fit the new note `textarea` and the two-row players input.
- Roster module: legacy `RAID_ROSTER_UPDATE` / `PARTY_MEMBERS_CHANGED` events are now registered through a `pcall`-wrapped helper, since TBC Anniversary rejects the older event names.

### Fixed

- **Static popup edit boxes** (`WSA_NEW_RAID`, `WSA_RENAME_RAID`, `WSA_DUPLICATE_RAID`): on TBC Anniversary the field is exposed as `self.EditBox` instead of `self.editBox`. The popup handlers now go through a `PopupEditBox(self)` helper that tries `self.editBox`, then `self.EditBox`, then `_G[self:GetName() .. "EditBox"]` as a last resort.
- **`EasyMenu` global removed** in modern clients (including TBC Anniversary). Replaced with a local `ShowEasyMenu` polyfill that reproduces the historical Blizzard implementation (`UIDropDownMenu_Initialize` + `ToggleDropDownMenu`). Used by the boss picker and player picker dropdowns.
- **Empty-state message** on the Raid Summary screen was clipped because it was anchored on the 1×1 scroll child. It is now anchored on the panel itself with a centered `JustifyH`.
- **`ScrollFrame` scroll children** (raid summary list, boss sidebar, attribution list, players list, note textarea) are now resized via an `AutoSizeScrollChild` helper that hooks `OnSizeChanged` and `OnShow`, plus a one-shot `OnUpdate` tick. Without this fix, rows anchored `TOPLEFT`+`TOPRIGHT` collapsed to 0 px wide on the very first refresh, making children (X buttons, names) pile up at the same position.
- **Multi-line note `EditBox`** required an explicit non-zero size (`SetSize(200, 100)`) to receive clicks; without it the hit rect was zero and the field was un-focusable on the first show. Clicking anywhere in the backdrop now focuses the editbox so the user does not have to hit an existing line precisely.
- **Pending edits lost on Announce**: clicking the `Announce` button while still typing in the players input or note field would read stale data from the DB before the focus-loss handler ran. The Announce / Preview button click handlers now call `CommitPendingEdits()` first.
- **Boss row in the sidebar** wrapped long names onto two lines and overlapped the attribute counter. The row is now single-line with `WordWrap(false)`, the title cap-anchored on the LEFT of the right-side counter so it truncates instead of wrapping.

### Removed

- **Shift-click absorber path**: all the `ChatEdit_GetActiveWindow` / `ChatEdit_InsertLink` / `SecureUnitButton_OnClick` hook code was removed (~190 lines from `Roster.lua`). The original goal was to let the user shift-click a raid frame to assign the player to the current attribution, but the integration was unreliable across raid frame addons (ElvUI / oUF / Vuhdo all bypass the standard click flow). The new in-addon player picker dropdown covers the same use case more reliably and with no addon-side hooks.
- **`UI:IsReadyForShiftClick`** and **`UI:TryAbsorbPlayerLink`** entry points (no longer called).
- **`Announce FR` button** and the **EN/FR language toggle** in the announce bar.
- **`announceLanguage` setting** key from `DEFAULTS`.
- The old single-line **`playersBox` / `ParsePlayerList`** workflow is gone — the players section is now a structured list, not a comma-separated text field. `Attributions.lua` still ships `ParsePlayerList` / `FormatPlayerList` because they may be useful elsewhere, but the editor no longer uses them.

## [0.2.0] - 2026-04-06

Complete pivot of the data model around **raid plans** and **attributions**. The earlier "role types" approach is removed — assignments are now structured as `marker + players + context` per boss, which matches how WoW raid coordination is actually expressed in game.

### Added

#### Raid Plans
- New top-level `raids` concept: a raid is a named plan that groups multiple boss encounters (e.g. "SSC Tuesday Farm")
- **Raid Summary** home screen listing all saved raids, most recent edit first, with per-card counters (bosses, attributions, assigned players) and metadata (author, last edit time)
- Raid CRUD on the summary screen: `+ New Raid`, `Rename`, `Duplicate`, `Delete` (with confirmation popup)
- `Raids.lua` module exposing `Create`, `Rename`, `Delete`, `Duplicate`, `Iterate`, `CountEncounters`, `CountAttributions`, `CountAssignedPlayers`

#### Boss Selection
- **Raid Editor** view with a vertical sidebar of bosses + `+ Add Boss` dropdown
- `TBCBosses.lua` reference data: full list of TBC raid bosses grouped by instance (Karazhan, Gruul, Magtheridon, SSC, Tempest Keep, Mount Hyjal, Black Temple, Zul'Aman, Sunwell Plateau)
- Adding a boss uses a two-level dropdown (instance → boss) populated from the reference data
- Instance name auto-filled from the boss name

#### Attributions (new data model)
- `attribution = { marker (optional, 1..8), players (1..N), context (free text) }`
- Markers may repeat within the same boss (e.g. two "Skull" attributions for different phases)
- `Attributions.lua` module with CRUD for both bosses (encounters) and attributions, plus `AddPlayer` / `RemovePlayer` / `ParsePlayerList` / `FormatPlayerList` helpers
- Middle-column attribution list: marker icon + context + class-colored player names
- Click an attribution row to **select** it (highlights)
- Right-column edit panel: marker dropdown (with "none" option), context text input, players text input, Delete Attribution button

#### Shift-Click Assignment
- Hook on `ChatEdit_InsertLink` absorbs player links when the WSA window is open with an attribution selected
- Shift-clicking a player in the default Blizzard raid/party/unit frames adds the player directly to the currently selected attribution — no text field focus required
- Roster link extraction supports `Hplayer:`, `Hunit:` and plain `[Name]` link formats

#### Chat Broadcast (Announce)
- `Broadcast.lua` module builds localized chat strings for a boss's attributions
- Two buttons per boss: `[Announce EN]` `[Announce FR]`, plus a channel dropdown (`RAID`, `RAID_WARNING`, `PARTY`, `SAY`, `GUILD`, `OFFICER`)
- Marker icons embedded via `{rt1}..{rt8}` chat tokens which the client converts to in-game raid target icons
- Message format: single concatenated line `[Boss] Context1: A, B | {rt8} Context2: C, D | ...`
- Auto-splits on `|` boundaries when a message exceeds the 255-character chat limit; sends multiple consecutive messages rather than truncating
- Graceful fallback to `SAY` if the selected channel requires a group the player isn't in
- `Preview` method prints the would-be messages to the local chat frame without sending

### Changed
- **Data schema**: `db.encounters` is gone. All boss data is now nested under `db.raids[raidKey].encounters[encounterKey]`.
- `Comms.lua` protocol version bumped to `2`: push/pull units are now whole raids, not individual encounters. Last-write-wins reconciliation uses the raid's `updatedAt`.
- `UI.lua` rewritten around a two-screen navigation (Raid Summary → Raid Editor), with three columns in the editor: boss sidebar, attribution list, edit panel
- `Core.lua` DEFAULTS schema updated; `settings.announceChannel` added
- `AssignData.lua` slimmed down: the role-types list is removed. The file now exposes `MarkerIcons` (the 8 raid target markers with textures and `{rtN}` tokens) and keeps `ClassColors` plus a new `ColorizeName` helper.
- `.toc` interface version bumped to `20504`; load order updated to pull in the new modules before UI
- Main window resized from 720x460 to 820x520 to fit the three-column editor

### Removed
- Old `Assignments.lua` module (fully replaced by `Attributions.lua`)
- `AssignData.RoleTypes` and `AssignData.EncounterTemplates` (the whole "role type" concept is gone — attributions use a free-text `context` field instead)
- `/wsa settings` slash command hint (no settings panel yet, to be re-added in a later version)

---

## [0.1.0] - 2026-04-06

Initial scaffold of the addon, modeled after the NodeCounter modular architecture.

### Added

#### Core Addon
- Addon initialization with account-wide (`WowShiftAssignDB`) and per-character (`WowShiftAssignCharDB`) SavedVariables
- Internal event bus (`NS:RegisterCallback` / `NS:FireCallback`) for module communication
- Deep copy and non-destructive merge defaults for safe SavedVariables migration
- Slash commands: `/wsa`, `/wsa settings`, `/wsa sync`, `/wsa request`, `/wsa reset`
- Static popup confirmation for destructive reset

#### Static Data (`AssignData.lua`)
- 13 built-in role types (Tank, Main Heal, Tank Healer, Raid Healer, Interrupt, Decurse, Magic Dispel, Tranq Shot, Mind Control, Kite, Carry, Raid Cooldown, Custom)
- Class color table with `RAID_CLASS_COLORS` fallback
- Encounter templates for Lady Vashj (SSC), Kael'thas (TK), Illidan (BT) and a Blank template

#### Roster (`Roster.lua`)
- Raid / party / solo group scanning with TBC + modern API compatibility
- Class detection and crude role hint per class (tank/melee/ranged/heal)
- Throttled rescans on `GROUP_ROSTER_UPDATE`, `RAID_ROSTER_UPDATE`, `PARTY_MEMBERS_CHANGED`, `PLAYER_ENTERING_WORLD`
- Public iterators (`Iterate`, `GetByClass`, `GetByRoleHint`)
- Fires `ROSTER_UPDATED` callback

#### Assignments (`Assignments.lua`)
- CRUD layer for encounters, roles and slots
- Encounter creation from a template (auto-seeds roles)
- Role reordering, renaming, notes, clear, delete
- Player slot assign / unassign with duplicate protection
- `updated` / `updatedBy` metadata for last-write-wins synchronization
- `ExportEncounter` / `ReplaceEncounter` for the comms layer
- Fires `DATA_UPDATED`, `ENCOUNTER_CREATED`, `ENCOUNTER_DELETED`, `ENCOUNTER_REPLACED`

#### Comms (`Comms.lua`)
- Versioned addon-message protocol (`WSA1`) over `RAID` / `PARTY`
- Commands: `PUSH <key> <encounter>`, `REQ`
- Self-contained recursive serializer (no Ace3 dependency) supporting strings, numbers, booleans and nested tables
- Last-write-wins merge based on `updated` timestamp
- Auto-broadcast on local edits (toggle in settings)
- Compat shim for `C_ChatInfo.SendAddonMessage` / `RegisterAddonMessagePrefix`
- Wired to `SYNC_PUSH_REQUEST` and `SYNC_PULL_REQUEST` callbacks

#### UI (`UI.lua`)
- Main window (720x460), draggable, position persisted
- Two-column layout: encounter list + role editor
- Per-row class-colored slot display
- Add Role dropdown menu listing every built-in role type
- Per-role actions: Assign Me, Clear, Delete
- Bottom action bar: Push to Raid, Request Sync, Delete Encounter
- ElvUI compatibility (`SetTemplate("Transparent")`) with fallback backdrop
- Lazy creation on first toggle, refreshes on `DATA_UPDATED` and `ROSTER_UPDATED`

#### Build & Release
- `package.sh` script for local addon packaging (Bash)
- GitHub Actions workflow `build-addon.yml` for automated builds on pull requests (uploads versioned artifact)
- GitHub Actions workflow `release.yml` for automated GitHub Releases on merge to main, with idempotent tag check and changelog extraction for release notes

[Unreleased]: https://github.com/gpiecq/SimpleRaidAssign/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/gpiecq/SimpleRaidAssign/releases/tag/v1.2.0
[1.1.0]: https://github.com/gpiecq/SimpleRaidAssign/releases/tag/v1.1.0
[1.0.0]: https://github.com/gpiecq/SimpleRaidAssign/releases/tag/v1.0.0
[0.2.0]: https://github.com/gpiecq/SimpleRaidAssign/releases/tag/v0.2.0
[0.1.0]: https://github.com/gpiecq/SimpleRaidAssign/releases/tag/v0.1.0
