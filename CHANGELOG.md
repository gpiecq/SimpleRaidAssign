# Changelog

All notable changes to WowShiftAssign will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/your-org/WowShiftAssign/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/your-org/WowShiftAssign/releases/tag/v0.1.0
