# Attribution Categories — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, collapsible category layer (e.g. `P1`, `P2`, `Adds`) under each boss in SimpleRaidAssign, so attributions can be grouped, displayed and announced phase by phase. Existing flat raids continue to work untouched.

**Architecture:** Flat data model — a `categoryId` field on each attribution + `enc.categories` and `enc.categoryOrder` on the encounter. `enc.order` stays the canonical global display order. Per-category chat messages produced by `Broadcast`. Hierarchical tri-state announce checkboxes. Fold state stored in `SimpleRaidAssignCharDB.ui.collapsed` (existing slot).

**Tech Stack:** Lua, WoW addon API (Burning Crusade Classic 2.5.x, Interface `20505`). No automated test framework — verification is in-game via `/reload`, `/run` console invocations, and direct UI interaction.

**Source spec:** `docs/superpowers/specs/2026-04-28-attribution-categories-design.md`.

## Verification model

There is no test runner. Each task ends with a manual verification block describing:

1. Files saved (the workspace is the live addon — no build step is required between edits, but `/reload` is needed for the new code to load and for SavedVariables changes to flush).
2. Inside-WoW commands to type in chat (`/reload`, `/run ...`, `/dump ...`, `/sra`).
3. Expected observable output (console line, UI state, raid chat content, SavedVariables shape).

The user is expected to run these checks. Do not commit a task without confirmation that the verification passed.

## File structure

Existing files (modified):

- `Attributions.lua` — adds 7 new methods + amends 2; ~150 LOC delta.
- `Broadcast.lua` — splits `BuildMessages` into per-category blocks; ~40 LOC delta.
- `UI.lua` — bulk of the work: new header row builder, refresh rewrite, two new dropdowns, two new popups, fold-state plumbing, tri-state checkbox plumbing; ~350 LOC delta. Already 1959 LOC; we keep the all-in-one structure (the file's pattern).
- `Core.lua` — no code change required (`CHAR_DEFAULTS.ui.collapsed` already exists). Only updated for version string.
- `SimpleRaidAssign.toc` — version bump.
- `CHANGELOG.md` — new `## [1.2.0]` section.
- `README.md` — new "Categories" feature section + updated example announce.

No new files.

---

## Task 1: Categories CRUD in `Attributions.lua`

Add the data layer for categories. No UI yet. Verify entirely from console.

**Files:**
- Modify: `Attributions.lua` — add new methods, update `AddAttribution` and `MoveAttribution`, add lazy normalisation inside `GetEncounter`.

- [ ] **Step 1.1: Add lazy normalisation helper inside `Attributions.lua`**

Insert this helper right before the `-- ENCOUNTERS (bosses)` banner around line 43:

```lua
----------------------------------------------------------------------
-- Normalise an encounter table in place so newer fields are present
-- (categories / categoryOrder). Called from every read/write entry
-- point so legacy v1.1 saves are migrated lazily without touching
-- ADDON_LOADED. Idempotent.
----------------------------------------------------------------------
local function NormalizeEncounter(enc)
    if not enc then return nil end
    if enc.categories     == nil then enc.categories     = {} end
    if enc.categoryOrder  == nil then enc.categoryOrder  = {} end
    return enc
end
```

Then update `GetEncounter` (the **module-private** one defined at line 29) to call it on the way out:

```lua
local function GetEncounter(raidKey, encounterKey)
    local raid = GetRaid(raidKey)
    if not raid or not raid.encounters then return nil end
    return NormalizeEncounter(raid.encounters[encounterKey])
end
```

The public `Attributions:GetEncounter` (line 139) already proxies through `GetEncounter`, so no extra change there.

- [ ] **Step 1.2: Update `Attributions:AddEncounter`**

Around line 52, add the two new fields to the encounter literal so newly-created encounters start normalised:

```lua
raid.encounters[encKey] = {
    name           = bossName,
    instance       = instance or "",
    attributions   = {},
    order          = {},
    categories     = {},          -- NEW
    categoryOrder  = {},          -- NEW
    updated        = NowTs(),
    updatedBy      = CurrentPlayer(),
}
```

- [ ] **Step 1.3: Add categories CRUD methods**

Append at the end of `Attributions.lua` (after the existing `FormatPlayerList` helper):

```lua
-- ====================================================================
--  CATEGORIES (P1 / P2 / ... grouping inside an encounter)
-- ====================================================================

----------------------------------------------------------------------
-- Add a category to a boss. Returns its catId.
-- The category is appended to the end of categoryOrder.
----------------------------------------------------------------------
function Attributions:AddCategory(raidKey, encounterKey, name)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc or not name or name == "" then return nil end

    local catId = NewId("cat")
    enc.categories[catId] = {
        name      = name,
        updated   = NowTs(),
        updatedBy = CurrentPlayer(),
    }
    enc.categoryOrder[#enc.categoryOrder + 1] = catId

    TouchParents(raidKey, encounterKey)
    NS:FireCallback("DATA_UPDATED")
    return catId
end

----------------------------------------------------------------------
-- Rename an existing category. No-op if name is empty or catId is
-- unknown.
----------------------------------------------------------------------
function Attributions:RenameCategory(raidKey, encounterKey, catId, newName)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc or not catId or not newName or newName == "" then return end
    local cat = enc.categories[catId]
    if not cat then return end
    cat.name      = newName
    cat.updated   = NowTs()
    cat.updatedBy = CurrentPlayer()
    TouchParents(raidKey, encounterKey)
    NS:FireCallback("DATA_UPDATED")
end

----------------------------------------------------------------------
-- Delete a category. Any attribution whose categoryId points at the
-- removed category has its categoryId reset to nil so it falls back
-- to the Uncategorized bucket. The attributions themselves and their
-- position in enc.order are untouched.
----------------------------------------------------------------------
function Attributions:DeleteCategory(raidKey, encounterKey, catId)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc or not catId or not enc.categories[catId] then return end

    -- Reassign attributions to "Uncategorized"
    for _, attrib in pairs(enc.attributions) do
        if attrib.categoryId == catId then
            attrib.categoryId = nil
        end
    end

    enc.categories[catId] = nil
    for i, k in ipairs(enc.categoryOrder) do
        if k == catId then table.remove(enc.categoryOrder, i); break end
    end

    TouchParents(raidKey, encounterKey)
    NS:FireCallback("DATA_UPDATED")
end

----------------------------------------------------------------------
-- Move a category up or down in categoryOrder.
----------------------------------------------------------------------
function Attributions:MoveCategory(raidKey, encounterKey, catId, delta)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc then return end
    for i, k in ipairs(enc.categoryOrder) do
        if k == catId then
            local target = i + delta
            if target < 1 or target > #enc.categoryOrder then return end
            table.remove(enc.categoryOrder, i)
            table.insert(enc.categoryOrder, target, catId)
            TouchParents(raidKey, encounterKey)
            NS:FireCallback("DATA_UPDATED")
            return
        end
    end
end

----------------------------------------------------------------------
-- Iterate categories in display order. Yields (catId, category).
----------------------------------------------------------------------
function Attributions:IterateCategories(raidKey, encounterKey)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc then return function() return nil end end
    local order = enc.categoryOrder or {}
    local i = 0
    return function()
        i = i + 1
        local key = order[i]
        if not key then return nil end
        return key, enc.categories[key]
    end
end

function Attributions:GetCategory(raidKey, encounterKey, catId)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc or not catId then return nil end
    return enc.categories[catId]
end

----------------------------------------------------------------------
-- Reassign an attribution to a category (or to "Uncategorized"
-- when catId is nil). Does NOT change the attribution's position in
-- enc.order: it stays where it is, just renders under a different
-- section header.
----------------------------------------------------------------------
function Attributions:SetAttributionCategory(raidKey, encounterKey, attribId, catId)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc or not enc.attributions[attribId] then return end
    -- Allow nil (Uncategorized). If a non-nil catId is unknown, refuse
    -- silently rather than orphan the attribution.
    if catId ~= nil and not enc.categories[catId] then return end
    enc.attributions[attribId].categoryId = catId
    TouchParents(raidKey, encounterKey)
    NS:FireCallback("DATA_UPDATED")
end
```

- [ ] **Step 1.4: Update `Attributions:AddAttribution` to accept an optional categoryId**

Replace the function signature and body around line 150:

```lua
function Attributions:AddAttribution(raidKey, encounterKey, marker, context, players, categoryId)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc then return nil end

    -- Defensive: if a non-nil catId is passed but doesn't exist, drop
    -- it so the attribution lands in Uncategorized instead of pointing
    -- at a ghost category.
    if categoryId ~= nil and not enc.categories[categoryId] then
        categoryId = nil
    end

    local attribId = NewId("attrib")
    enc.attributions[attribId] = {
        marker     = marker,
        context    = context or "",
        players    = players or {},
        note       = "",
        categoryId = categoryId,         -- NEW. nil = Uncategorized
    }
    enc.order[#enc.order + 1] = attribId
    TouchParents(raidKey, encounterKey)
    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("ATTRIBUTION_ADDED", raidKey, encounterKey, attribId)
    return attribId
end
```

The existing call site in `UI.lua:652` (the global `+ Add Attribution` button) does not pass `categoryId`, so the parameter defaults to `nil` ⇒ Uncategorized. Backwards compatible.

- [ ] **Step 1.5: Update `Attributions:MoveAttribution` to skip foreign categories**

Replace the existing function around line 289:

```lua
function Attributions:MoveAttribution(raidKey, encounterKey, attribId, delta)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc then return end

    -- Find the source position and the source attribution's category
    local fromIdx
    for i, k in ipairs(enc.order) do
        if k == attribId then fromIdx = i; break end
    end
    if not fromIdx then return end

    local sourceCat = enc.attributions[attribId] and enc.attributions[attribId].categoryId or nil

    -- Walk in the requested direction until we find the next attribId
    -- whose categoryId matches the source's. delta is +1 (down) or -1 (up).
    local step = (delta and delta > 0) and 1 or -1
    local toIdx = fromIdx + step
    while toIdx >= 1 and toIdx <= #enc.order do
        local otherId  = enc.order[toIdx]
        local otherAtt = enc.attributions[otherId]
        local otherCat = otherAtt and otherAtt.categoryId or nil
        if otherCat == sourceCat then
            -- Swap: take attribId out and insert at toIdx
            table.remove(enc.order, fromIdx)
            table.insert(enc.order, toIdx, attribId)
            TouchParents(raidKey, encounterKey)
            NS:FireCallback("DATA_UPDATED")
            return
        end
        toIdx = toIdx + step
    end
    -- No same-category neighbour in the requested direction → no-op.
end
```

- [ ] **Step 1.6: Verify in-game**

Save the file. In WoW:

```
/reload
/sra
```

Make sure the editor opens normally on an existing raid. Then create a test category and attribution from console (paste in chat as a single line):

```
/run local r=next(NS.db.raids); local e=next(NS.db.raids[r].encounters); local c=NS.Attributions:AddCategory(r,e,"P1"); print("cat="..c)
```

Expected: prints `cat=cat_<timestamp>_<NNNN>`. No Lua error. The UI **does not** show the category yet (Task 3 wires that up).

Inspect:

```
/dump (function() local r=next(NS.db.raids); local e=next(NS.db.raids[r].encounters); return NS.db.raids[r].encounters[e].categories end)()
```

Expected: a table with one entry whose `name = "P1"`. `categoryOrder` has the same catId.

Test reassigning an existing attribution:

```
/run local r=next(NS.db.raids); local e=next(NS.db.raids[r].encounters); local c=next(NS.db.raids[r].encounters[e].categories); local a=next(NS.db.raids[r].encounters[e].attributions); NS.Attributions:SetAttributionCategory(r,e,a,c); print("attrib "..a.." → cat "..c)
```

Confirm `categoryId` was set:

```
/dump (function() local r=next(NS.db.raids); local e=next(NS.db.raids[r].encounters); local a=next(NS.db.raids[r].encounters[e].attributions); return NS.db.raids[r].encounters[e].attributions[a].categoryId end)()
```

Expected: the catId string.

- [ ] **Step 1.7: Commit**

```bash
git add Attributions.lua
git commit -m "Add categories CRUD to Attributions.lua

AddCategory/RenameCategory/DeleteCategory/MoveCategory plus
IterateCategories, GetCategory, SetAttributionCategory. AddAttribution
gains an optional categoryId; MoveAttribution skips attributions of a
different categoryId so intra-category arrows stay scoped. Lazy
NormalizeEncounter helper handles legacy saves on first read."
```

---

## Task 2: Per-category broadcast messages in `Broadcast.lua`

Replace the single-block message build with one block per category (Uncategorized first, then categories in `categoryOrder`).

**Files:**
- Modify: `Broadcast.lua` — add `categoryFilter` arg to `BuildSegments`, rewrite `BuildMessages`.

- [ ] **Step 2.1: Update `BuildSegments` signature and body**

Replace the existing function around line 129:

```lua
----------------------------------------------------------------------
-- Build segments for a boss, optionally restricted to a single
-- category bucket.
--
--   filter         : optional set { [attribId] = true } as before.
--   categoryFilter : nil → include every attribution (legacy);
--                    "uncategorized" → include only attribs with
--                       attribution.categoryId == nil;
--                    "<catId>"      → include only attribs whose
--                       categoryId matches.
----------------------------------------------------------------------
function Broadcast:BuildSegments(raidKey, encounterKey, filter, categoryFilter)
    local segments = {}
    if not NS.Attributions then return segments end
    for attribId, attrib in NS.Attributions:IterateAttributions(raidKey, encounterKey) do
        local match
        if categoryFilter == nil then
            match = true
        elseif categoryFilter == "uncategorized" then
            match = (attrib.categoryId == nil)
        else
            match = (attrib.categoryId == categoryFilter)
        end
        if match and (not filter or filter[attribId]) then
            segments[#segments + 1] = FormatSegment(attrib)
        end
    end
    return segments
end
```

The existing call sites in `BuildMessages` and any tests pass `categoryFilter = nil` ⇒ legacy behaviour.

- [ ] **Step 2.2: Rewrite `BuildMessages` to emit one block per category**

Replace the existing function around line 193:

```lua
----------------------------------------------------------------------
-- Build all chat-ready messages for a boss. Emits:
--   1. one block (possibly chunked) for the Uncategorized bucket if
--      it has any selected segment;
--   2. one block per category in enc.categoryOrder, with title
--      "[Boss - CategoryName]".
-- Categories with no surviving segment are silently skipped. If every
-- block is empty, fall back to the legacy single-line "no attributions"
-- message so the announce flow stays observable.
----------------------------------------------------------------------
function Broadcast:BuildMessages(raidKey, encounterKey, filter)
    local enc = NS.Attributions and NS.Attributions:GetEncounter(raidKey, encounterKey)
    if not enc then return {} end

    local bossTitle = string.format(L.titleFmt, enc.name or "?")
    local out = {}

    -- 1. Uncategorized bucket
    local uncatSegs = self:BuildSegments(raidKey, encounterKey, filter, "uncategorized")
    if #uncatSegs > 0 then
        for _, m in ipairs(ChunkMessages(bossTitle, uncatSegs)) do
            out[#out + 1] = m
        end
    end

    -- 2. One block per category
    if NS.Attributions then
        for catId, cat in NS.Attributions:IterateCategories(raidKey, encounterKey) do
            local catName = SanitizeChatText(cat and cat.name or "")
            if catName == "" then catName = "?" end
            local catTitle = string.format("[%s - %s]", enc.name or "?", catName)
            local segs = self:BuildSegments(raidKey, encounterKey, filter, catId)
            if #segs > 0 then
                for _, m in ipairs(ChunkMessages(catTitle, segs)) do
                    out[#out + 1] = m
                end
            end
        end
    end

    if #out == 0 then
        return { bossTitle .. " " .. L.noAttribs }
    end
    return out
end
```

`SanitizeChatText` is module-private (defined around line 79) and visible from this scope.

- [ ] **Step 2.3: Verify in-game**

Save the file. In WoW:

```
/reload
```

Run `Preview` against the boss that already had a category and an attribution moved into it (from Task 1):

```
/run local r=next(NS.db.raids); local e=next(NS.db.raids[r].encounters); NS.Broadcast:Preview(r,e)
```

Expected output in the chat frame: at least two preview lines, one of the form `[BossName - P1] ...` containing the attribution that was reassigned. If there are still uncategorised attribs you should see a `[BossName] ...` line first.

Now move the attribution back to Uncategorized and re-run:

```
/run local r=next(NS.db.raids); local e=next(NS.db.raids[r].encounters); local a=next(NS.db.raids[r].encounters[e].attributions); NS.Attributions:SetAttributionCategory(r,e,a,nil)
/run local r=next(NS.db.raids); local e=next(NS.db.raids[r].encounters); NS.Broadcast:Preview(r,e)
```

Expected: only `[BossName] ...` preview lines, no `[BossName - P1]` block (P1 is empty so it's silently skipped).

- [ ] **Step 2.4: Commit**

```bash
git add Broadcast.lua
git commit -m "Broadcast: one chat message block per category

BuildMessages emits the Uncategorized bucket first (legacy [Boss]
title preserved) then one block per category in categoryOrder titled
[Boss - CategoryName]. BuildSegments gains an optional categoryFilter
argument (nil = legacy behaviour). Empty categories are silently
skipped; a wholly-empty boss still yields the no-attributions fallback."
```

---

## Task 3: UI display grouping (no controls yet)

Render category headers + indented attributions in the middle column, but leave the new buttons as visual placeholders. This task is the biggest refactor of `RefreshAttribList`. Splitting it from interaction lets you verify the layout independently before wiring behaviour.

**Files:**
- Modify: `UI.lua` — add `BuildCategoryHeaderRow`, change `RefreshAttribList` (line 1447), bump per-row layout y-offsets.

- [ ] **Step 3.1: Add `BuildCategoryHeaderRow` next to `BuildAttribRow`**

Insert just before `local function BuildAttribRow(parent)` around line 1419:

```lua
----------------------------------------------------------------------
-- Build a section header row for a category (or for the implicit
-- Uncategorized bucket when `isUncategorized` is true).
--
-- All interactive children are created here but their OnClick handlers
-- are wired in RefreshAttribList per-call (they need closures over the
-- current catId / raidKey / encKey).
----------------------------------------------------------------------
local function BuildCategoryHeaderRow(parent)
    local row = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    SkinFrame(row)
    row:SetHeight(24)
    row.kind = "header"   -- so RefreshAttribList knows row pool kind

    -- Chevron toggle (▼/▶)
    row.chevron = CreateFrame("Button", nil, row)
    row.chevron:SetSize(16, 16)
    row.chevron:SetPoint("LEFT", 4, 0)
    row.chevron.label = FS(row.chevron, 12)
    row.chevron.label:SetAllPoints()
    row.chevron.label:SetJustifyH("CENTER")
    row.chevron.label:SetText("▼")

    -- Tri-state announce checkbox
    row.selectCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.selectCheck:SetSize(18, 18)
    row.selectCheck:SetPoint("LEFT", row.chevron, "RIGHT", 4, 0)

    -- Name label
    row.label = FS(row, 12)
    row.label:SetPoint("LEFT", row.selectCheck, "RIGHT", 4, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetTextColor(unpack(COLOURS.accent))

    -- Inline rename EditBox (hidden by default, toggled on double-click)
    row.renameBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.renameBox:SetSize(120, 18)
    row.renameBox:SetPoint("LEFT", row.selectCheck, "RIGHT", 4, 0)
    row.renameBox:SetAutoFocus(false)
    row.renameBox:SetMaxLetters(32)
    row.renameBox:Hide()

    -- Right-aligned button cluster: ▲ ▼ ✎ 🗑 [+ Attrib]
    row.addAttribBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.addAttribBtn:SetSize(70, 18)
    row.addAttribBtn:SetPoint("RIGHT", -4, 0)
    row.addAttribBtn:SetText("+ Attrib")

    row.deleteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.deleteBtn:SetSize(22, 18)
    row.deleteBtn:SetPoint("RIGHT", row.addAttribBtn, "LEFT", -2, 0)
    row.deleteBtn:SetText("X")

    row.renameBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.renameBtn:SetSize(22, 18)
    row.renameBtn:SetPoint("RIGHT", row.deleteBtn, "LEFT", -2, 0)
    row.renameBtn:SetText("R")

    row.downBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.downBtn:SetSize(18, 18)
    row.downBtn:SetPoint("RIGHT", row.renameBtn, "LEFT", -2, 0)
    row.downBtn:SetText("v")

    row.upBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.upBtn:SetSize(18, 18)
    row.upBtn:SetPoint("RIGHT", row.downBtn, "LEFT", -2, 0)
    row.upBtn:SetText("^")

    return row
end
```

Note the textual `R`/`X`/`v`/`^`/`▼/▶` are intentional: WoW's default font does not render `✎`, `🗑`, `▲`, `▼` glyphs reliably. ASCII keeps the UI readable on any client.

- [ ] **Step 3.2: Add a helper to bucket attributions by category**

Insert just before `local function RefreshAttribList()` around line 1447:

```lua
----------------------------------------------------------------------
-- Walk enc.order once and bucket attribIds by their categoryId.
-- Returns:
--   uncatIds : array of attribIds with categoryId == nil
--   buckets  : table { [catId] = { attribId1, ... } }
-- Both arrays preserve enc.order's relative order.
-- Attributions whose categoryId points at an unknown category fall
-- back to the uncatIds bucket (defensive).
----------------------------------------------------------------------
local function BucketAttribsByCategory(raidKey, encKey)
    local uncatIds, buckets = {}, {}
    if not NS.Attributions then return uncatIds, buckets end
    local enc = NS.Attributions:GetEncounter(raidKey, encKey)
    if not enc then return uncatIds, buckets end

    for attribId, attrib in NS.Attributions:IterateAttributions(raidKey, encKey) do
        local cid = attrib.categoryId
        if cid == nil or not enc.categories[cid] then
            uncatIds[#uncatIds + 1] = attribId
        else
            buckets[cid] = buckets[cid] or {}
            buckets[cid][#buckets[cid] + 1] = attribId
        end
    end
    return uncatIds, buckets
end
```

- [ ] **Step 3.3: Split row pools**

Find the `attribPanel.rows = {}` initialisation around line 740 and replace it with two pools:

```lua
attribPanel.rows        = {}   -- attribution rows (existing pool)
attribPanel.headerRows  = {}   -- category header rows (new pool)
```

Update the `for _, row in ipairs(panel.rows) do row:Hide() end` line at the top of `RefreshAttribList` to hide both pools:

```lua
for _, row in ipairs(panel.rows)       do row:Hide() end
for _, row in ipairs(panel.headerRows) do row:Hide() end
```

- [ ] **Step 3.4: Rewrite the iteration body of `RefreshAttribList`**

Replace the loop in `RefreshAttribList` (currently `for attribId, attrib in NS.Attributions:IterateAttributions(...)` around line 1470) with the grouped layout. Keep everything else (header text, master checkbox sync) intact:

```lua
    panel.header:SetText("Attributions - " .. (enc.name or "?"))

    local uncatIds, buckets = BucketAttribsByCategory(currentRaidKey, currentEncounterKey)

    local y = 0
    local attribIdx, headerIdx = 0, 0

    -- Helper that renders a single attribution row at vertical offset y
    -- and bumps y. The closure captures the panel and indent.
    local function renderAttribRow(attribId, attrib, indent)
        attribIdx = attribIdx + 1
        local row = panel.rows[attribIdx]
        if not row then
            row = BuildAttribRow(panel.content)
            panel.rows[attribIdx] = row
        end

        if attrib.marker and NS.Data then
            local m = NS.Data:GetMarker(attrib.marker)
            if m then
                row.markerIcon:SetTexture(m.texture)
                row.markerIcon:Show()
            else
                row.markerIcon:Hide()
            end
        else
            row.markerIcon:Hide()
        end

        row.context:SetText(attrib.context ~= "" and attrib.context or "|cff888888(no context)|r")

        if attrib.players and #attrib.players > 0 then
            local parts = {}
            for _, name in ipairs(attrib.players) do
                parts[#parts + 1] = NS.Data and NS.Data:ColorizeName(name) or name
            end
            row.players:SetText(table.concat(parts, ", "))
        else
            row.players:SetText("|cff888888(no players)|r")
        end

        if currentAttribKey == attribId then
            if row.SetBackdropColor then row:SetBackdropColor(unpack(COLOURS.rowActive)) end
        else
            if row.SetBackdropColor then row:SetBackdropColor(unpack(COLOURS.bg)) end
        end

        row.selectCheck:SetChecked(IsAttribSelected(attribId))
        local capturedId = attribId
        row.selectCheck:SetScript("OnClick", function(self)
            SetAttribSelected(capturedId, self:GetChecked() and true or false)
            if panel.masterCheck then
                panel.masterCheck:SetChecked(AreAllAttribsSelected(currentRaidKey, currentEncounterKey))
            end
        end)

        row:SetScript("OnClick", function()
            CommitPendingEdits()
            currentAttribKey = attribId
            Refresh()
        end)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  panel.content, "TOPLEFT",  indent, -y)
        row:SetPoint("TOPRIGHT", panel.content, "TOPRIGHT", 0,      -y)
        row:Show()
        y = y + 52
    end

    -- Helper that renders a category header at vertical offset y. The
    -- isUncategorized flag hides the management buttons (rename/delete/
    -- reorder/+Attrib) — only the chevron + checkbox remain.
    local function renderHeaderRow(catId, name, isUncategorized)
        headerIdx = headerIdx + 1
        local row = panel.headerRows[headerIdx]
        if not row then
            row = BuildCategoryHeaderRow(panel.content)
            panel.headerRows[headerIdx] = row
        end
        row.label:SetText(name)
        row.label:Show()
        row.renameBox:Hide()

        -- Visibility of management buttons. Hidden in this task; wired
        -- in later tasks. They stay hidden for the Uncategorized header
        -- regardless.
        row.upBtn:Hide()
        row.downBtn:Hide()
        row.renameBtn:Hide()
        row.deleteBtn:Hide()
        row.addAttribBtn:Hide()

        -- Chevron and selectCheck do nothing useful yet, but keep them
        -- visible so the layout matches the final design.
        row.chevron:Show()
        row.chevron:SetScript("OnClick", nil)
        row.selectCheck:Show()
        row.selectCheck:SetScript("OnClick", nil)
        row.selectCheck:SetChecked(true)

        if isUncategorized then
            row.label:SetTextColor(unpack(COLOURS.dim))
        else
            row.label:SetTextColor(unpack(COLOURS.accent))
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  panel.content, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", panel.content, "TOPRIGHT", 0, -y)
        row:Show()
        y = y + 26
    end

    -- 1. Uncategorized first (only if non-empty)
    if #uncatIds > 0 then
        renderHeaderRow(nil, "— Uncategorized —", true)
        for _, attribId in ipairs(uncatIds) do
            local attrib = enc.attributions[attribId]
            if attrib then renderAttribRow(attribId, attrib, 0) end
        end
    end

    -- 2. Each category in categoryOrder
    for catId, cat in NS.Attributions:IterateCategories(currentRaidKey, currentEncounterKey) do
        renderHeaderRow(catId, cat.name or "?", false)
        local ids = buckets[catId] or {}
        for _, attribId in ipairs(ids) do
            local attrib = enc.attributions[attribId]
            if attrib then renderAttribRow(attribId, attrib, 20) end
        end
    end

    panel.content:SetHeight(math.max(1, y))

    if panel.masterCheck then
        panel.masterCheck:SetChecked(AreAllAttribsSelected(currentRaidKey, currentEncounterKey))
    end
```

The full new `RefreshAttribList` body is the existing pre-amble (`if not panel...`, `if not enc...`) followed by the block above.

- [ ] **Step 3.5: Verify in-game**

Save. In WoW:

```
/reload
/sra
```

Open a raid, select a boss. With existing attributions all `categoryId = nil`, you should see them under a `— Uncategorized —` header, no other change vs. v1.1.

From console (if you ran Task 1 verification, you may already have a P1):

```
/run local r=next(NS.db.raids); local e=next(NS.db.raids[r].encounters); NS.Attributions:AddCategory(r,e,"P1")
/run local r=next(NS.db.raids); local e=next(NS.db.raids[r].encounters); local c=next(NS.db.raids[r].encounters[e].categories); local a=next(NS.db.raids[r].encounters[e].attributions); NS.Attributions:SetAttributionCategory(r,e,a,c)
```

The editor should refresh on its own (DATA_UPDATED triggers). Expected:

- A new section `P1` (accent colour) appears under the Uncategorized list.
- The reassigned attribution moves from Uncategorized to under the P1 header (indented ~20 px).
- Click the attribution: it stays selectable, edit panel on the right still reflects it.
- Click `[X]` next to an attribution to remove a player: still works.
- Click `[Announce]` / `[Preview]`: the raid chat / preview output now shows two blocks (`[Boss] ...` + `[Boss - P1] ...`). This was already true after Task 2.

- [ ] **Step 3.6: Commit**

```bash
git add UI.lua
git commit -m "UI: render attributions grouped by category

RefreshAttribList walks attributions once via BucketAttribsByCategory,
emits an Uncategorized header (only when non-empty), then iterates
enc.categoryOrder and emits one header per category followed by its
indented attribution rows. New BuildCategoryHeaderRow builder. Header
management buttons (rename/delete/reorder/+Attrib) are present in the
DOM but hidden — wired in subsequent commits."
```

---

## Task 4: `+ Add Category` button + preset dropdown + Custom popup

Wire creation of new categories.

**Files:**
- Modify: `UI.lua` — add `addCategoryBtn` next to the master checkbox row, the preset dropdown, the new `SRA_NEW_CATEGORY` static popup, and a small helper `OpenCategoryPicker`.

- [ ] **Step 4.1: Add the `SRA_NEW_CATEGORY` popup**

Append to the popup block (after `SRA_DELETE_ENCOUNTER` around line 360):

```lua
StaticPopupDialogs["SRA_NEW_CATEGORY"] = {
    text = "New category name:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 32,
    OnShow = function(self)
        local eb = PopupEditBox(self)
        if eb then eb:SetText(""); eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = PopupEditBox(self)
        local name = eb and eb:GetText() or ""
        name = strtrim(name or "")
        if name == "" or not data then return end
        if NS.Attributions then
            NS.Attributions:AddCategory(data.raidKey, data.encKey, name)
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local data   = parent.data
        local name   = strtrim(self:GetText() or "")
        if name ~= "" and data and NS.Attributions then
            NS.Attributions:AddCategory(data.raidKey, data.encKey, name)
        end
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
```

- [ ] **Step 4.2: Add the `OpenCategoryPicker` helper**

Insert near `OpenBossPicker` around line 1047:

```lua
----------------------------------------------------------------------
-- Category presets dropdown. Selecting a preset creates the category
-- immediately. Selecting "Custom..." opens SRA_NEW_CATEGORY.
----------------------------------------------------------------------
local CATEGORY_PRESETS = {
    "P1", "P2", "P3", "P4",
    "Pull", "Adds", "Burn", "Transition", "Heroism",
}

local categoryPickerFrame

function UI:OpenCategoryPicker(onPick)
    if not currentRaidKey or not currentEncounterKey then return end

    local menu = {}
    for _, name in ipairs(CATEGORY_PRESETS) do
        local capturedName = name
        menu[#menu + 1] = {
            text         = capturedName,
            notCheckable = true,
            func         = function()
                if NS.Attributions then
                    local catId = NS.Attributions:AddCategory(
                        currentRaidKey, currentEncounterKey, capturedName)
                    if onPick then onPick(catId) end
                end
            end,
        }
    end
    menu[#menu + 1] = { text = "", notCheckable = true, disabled = true }
    menu[#menu + 1] = {
        text         = "Custom...",
        notCheckable = true,
        func         = function()
            local dialog = StaticPopup_Show("SRA_NEW_CATEGORY")
            if dialog then
                dialog.data = {
                    raidKey  = currentRaidKey,
                    encKey   = currentEncounterKey,
                    onPick   = onPick,    -- not used by the popup directly
                }
            end
        end,
    }

    if not categoryPickerFrame then
        categoryPickerFrame = CreateFrame("Frame", "SRACategoryPickerMenu", UIParent, "UIDropDownMenuTemplate")
    end
    ShowEasyMenu(menu, categoryPickerFrame, "cursor", 0, 0, "MENU")
end
```

- [ ] **Step 4.3: Add the `+ Add Category` button**

In the editor view setup, just under the master checkbox / label block around line 643, insert:

```lua
    local addCategoryBtn = CreateFrame("Button", nil, attribPanel, "UIPanelButtonTemplate")
    addCategoryBtn:SetSize(110, 20)
    addCategoryBtn:SetPoint("LEFT", masterLabel, "RIGHT", 12, 0)
    addCategoryBtn:SetText("+ Add Category")
    addCategoryBtn:SetScript("OnClick", function()
        if not currentRaidKey or not currentEncounterKey then return end
        UI:OpenCategoryPicker()
    end)
```

- [ ] **Step 4.4: Verify in-game**

Save. In WoW:

```
/reload
/sra
```

Open a raid, select a boss.

1. Click `+ Add Category`. Expected: dropdown appears at the cursor with `P1`, `P2`, ..., `Heroism`, separator, `Custom...`.
2. Click `P2`. Expected: a new `P2` section header appears immediately at the bottom of the list (empty section). No Lua error.
3. Click `+ Add Category` → `Custom...`. Expected: popup with edit field. Type `Burn phase` and Enter / Create. Expected: a new `Burn phase` section appears. Cancel closes without creating.
4. `/reload` and reopen — both `P2` and `Burn phase` should still be there (persisted in `SimpleRaidAssignDB`).

- [ ] **Step 4.5: Commit**

```bash
git add UI.lua
git commit -m "UI: + Add Category button with preset dropdown

A new button next to the master checkbox opens a UIDropDownMenu of
preset names (P1..P4, Pull, Adds, Burn, Transition, Heroism). Custom...
opens the new SRA_NEW_CATEGORY popup for free-text input (max 32 chars).
The popup uses the existing PopupEditBox helper for TBC Anniversary
compatibility."
```

---

## Task 5: Right-panel `Category` dropdown

Lets the user move the currently-selected attribution to another category (or to Uncategorized).

**Files:**
- Modify: `UI.lua` — add a new dropdown between the marker dropdown and the context input on the edit panel; refresh it from `Refresh()` so it follows the selected attribution.

- [ ] **Step 5.1: Add the dropdown frame**

In the editor view setup, after the marker `clearMarkerBtn` block (around line 818) and before the `Context` label (line 821), insert:

```lua
    -- Category dropdown
    local categoryLabel = FS(editPanel, 10)
    categoryLabel:SetPoint("TOPLEFT", 10, -62)
    categoryLabel:SetText("Category:")
    categoryLabel:SetTextColor(unpack(COLOURS.dim))

    local categoryDrop = CreateFrame("Frame", "SRACategoryAttribDropdown", editPanel, "UIDropDownMenuTemplate")
    categoryDrop:SetPoint("TOPLEFT", 4, -78)
    UIDropDownMenu_SetWidth(categoryDrop, 180)
    editPanel.categoryDrop = categoryDrop
```

The `Context` label and its EditBox are currently anchored at `TOPLEFT, 10, -88` / `TOPLEFT, 16, -104`. Update those anchors to push them down by 24 px (the height of the new dropdown row):

```lua
    contextLabel:SetPoint("TOPLEFT", 10, -112)   -- was -88
    contextBox:SetPoint("TOPLEFT", 16, -128)     -- was -104
```

Apply the same +24 px shift to every subsequent right-panel anchor:

| Element             | Old offset | New offset |
|---------------------|-----------:|-----------:|
| `playersLabel`      | `-136`     | `-160`     |
| `playersBg`         | `-152`     | `-176`     |
| `playersInput`      | `-256`     | `-280`     |
| `addPlayerBtn` (if y-anchored relative to playersInput) | n/a | follows |
| `fromGroupBtn`      | (relative) | unchanged  |
| `noteLabel`         | varies     | +24        |
| `noteScroll`        | varies     | +24        |
| `deleteAttribBtn`   | varies     | +24        |

Read `UI.lua` lines 845–1000 carefully and bump every `SetPoint("TOPLEFT", ..., y)` whose `y` is more negative than `-104` by 24 (i.e. subtract 24). Anchors expressed relative to siblings (`SetPoint("LEFT", playersInput, ...)`) need no change — they follow the parent.

- [ ] **Step 5.2: Initialise the dropdown contents in `Refresh()`**

Find the right-panel refresh block in the existing `Refresh()` function (search for `markerDrop` updates near line 1700). Add after the marker refresh logic and before the `contextBox` refresh:

```lua
    -- Refresh the category dropdown
    if editPanel.categoryDrop then
        UIDropDownMenu_Initialize(editPanel.categoryDrop, function(self, level)
            -- (none) entry
            local none = UIDropDownMenu_CreateInfo()
            none.text         = "|cff888888(none)|r"
            none.notCheckable = true
            none.func = function()
                if NS.Attributions and currentRaidKey and currentEncounterKey and currentAttribKey then
                    NS.Attributions:SetAttributionCategory(
                        currentRaidKey, currentEncounterKey, currentAttribKey, nil)
                    UIDropDownMenu_SetText(editPanel.categoryDrop, "|cff888888(none)|r")
                end
            end
            UIDropDownMenu_AddButton(none, level)

            if NS.Attributions and currentRaidKey and currentEncounterKey then
                for catId, cat in NS.Attributions:IterateCategories(currentRaidKey, currentEncounterKey) do
                    local capId, capName = catId, cat.name or "?"
                    local info = UIDropDownMenu_CreateInfo()
                    info.text         = capName
                    info.value        = capId
                    info.notCheckable = true
                    info.func = function()
                        if NS.Attributions and currentRaidKey and currentEncounterKey and currentAttribKey then
                            NS.Attributions:SetAttributionCategory(
                                currentRaidKey, currentEncounterKey, currentAttribKey, capId)
                            UIDropDownMenu_SetText(editPanel.categoryDrop, capName)
                        end
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end

            -- Separator + "+ New Category..." shortcut
            local sep = UIDropDownMenu_CreateInfo()
            sep.text = ""; sep.notCheckable = true; sep.disabled = true
            UIDropDownMenu_AddButton(sep, level)

            local newOne = UIDropDownMenu_CreateInfo()
            newOne.text         = "+ New Category..."
            newOne.notCheckable = true
            newOne.func = function()
                local capturedAttrib = currentAttribKey
                UI:OpenCategoryPicker(function(newCatId)
                    if newCatId and NS.Attributions and currentRaidKey and currentEncounterKey then
                        NS.Attributions:SetAttributionCategory(
                            currentRaidKey, currentEncounterKey, capturedAttrib, newCatId)
                    end
                end)
            end
            UIDropDownMenu_AddButton(newOne, level)
        end)

        -- Set the displayed text from the current attribution
        local currentLabel = "|cff888888(none)|r"
        if currentAttribKey then
            local attrib = NS.Attributions and NS.Attributions:GetAttribution(
                currentRaidKey, currentEncounterKey, currentAttribKey)
            if attrib and attrib.categoryId then
                local cat = NS.Attributions:GetCategory(
                    currentRaidKey, currentEncounterKey, attrib.categoryId)
                if cat then currentLabel = cat.name or "?" end
            end
        end
        UIDropDownMenu_SetText(editPanel.categoryDrop, currentLabel)
    end
```

- [ ] **Step 5.3: Verify in-game**

```
/reload
/sra
```

1. Open a boss with at least one Uncategorized attribution and at least one category.
2. Click an Uncategorized attribution → in the right edit panel, the new `Category:` dropdown shows `(none)`.
3. Open the dropdown → entries: `(none)`, every existing category, separator, `+ New Category...`.
4. Pick `P1` → the attribution row immediately moves under the `P1` header in the middle list. The dropdown text shows `P1`.
5. Pick `(none)` → the row moves back to `— Uncategorized —`.
6. Pick `+ New Category...` → preset dropdown opens. Pick `P2` → a new `P2` section is created **and** the current attribution lands in it.

Verify that the right-panel anchors didn't shift visually for the rest of the elements: marker dropdown still at the top, context input below the new category dropdown, players list further down, note textarea, delete button at the bottom.

- [ ] **Step 5.4: Commit**

```bash
git add UI.lua
git commit -m "UI: Category dropdown in the right edit panel

Adds a Category: dropdown between the marker dropdown and the context
input. Lists (none), every existing category in categoryOrder, then a
separator and a + New Category... shortcut that opens the preset picker
and assigns the new category to the currently-selected attribution.
Right-panel siblings shifted down by 24 px to make room."
```

---

## Task 6: Category header buttons (rename, delete, reorder)

Wire the management buttons that `BuildCategoryHeaderRow` already created.

**Files:**
- Modify: `UI.lua` — extend `renderHeaderRow` (inside `RefreshAttribList`), add the `SRA_DELETE_CATEGORY` popup.

- [ ] **Step 6.1: Add the `SRA_DELETE_CATEGORY` popup**

Append after `SRA_NEW_CATEGORY` (added in Task 4):

```lua
StaticPopupDialogs["SRA_DELETE_CATEGORY"] = {
    text = "Delete category '%s' and move %d attributions to Uncategorized?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and NS.Attributions then
            NS.Attributions:DeleteCategory(data.raidKey, data.encKey, data.catId)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
```

- [ ] **Step 6.2: Wire the buttons in `renderHeaderRow`**

Replace the `if isUncategorized then ... else ... end` block in `renderHeaderRow` (the part that currently hides every button — added in Task 3). New body:

```lua
        if isUncategorized then
            row.label:SetTextColor(unpack(COLOURS.dim))
            row.upBtn:Hide(); row.downBtn:Hide()
            row.renameBtn:Hide(); row.deleteBtn:Hide()
            row.addAttribBtn:Hide()
        else
            row.label:SetTextColor(unpack(COLOURS.accent))

            -- Reorder
            local capCatId = catId
            row.upBtn:Show()
            row.upBtn:SetScript("OnClick", function()
                if NS.Attributions then
                    NS.Attributions:MoveCategory(currentRaidKey, currentEncounterKey, capCatId, -1)
                end
            end)
            row.downBtn:Show()
            row.downBtn:SetScript("OnClick", function()
                if NS.Attributions then
                    NS.Attributions:MoveCategory(currentRaidKey, currentEncounterKey, capCatId, 1)
                end
            end)

            -- Rename: ✎ button → inline EditBox
            local function startRename()
                row.label:Hide()
                row.renameBox:SetText(name)
                row.renameBox:Show()
                row.renameBox:SetFocus()
                row.renameBox:HighlightText()
            end
            row.renameBtn:Show()
            row.renameBtn:SetScript("OnClick", startRename)
            row.renameBox:SetScript("OnEnterPressed", function(self)
                local newName = strtrim(self:GetText() or "")
                self:ClearFocus()
                if newName ~= "" and NS.Attributions then
                    NS.Attributions:RenameCategory(currentRaidKey, currentEncounterKey, capCatId, newName)
                end
                self:Hide()
                row.label:Show()
            end)
            row.renameBox:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
                self:Hide()
                row.label:Show()
            end)
            row.renameBox:SetScript("OnEditFocusLost", function(self)
                self:Hide()
                row.label:Show()
            end)
            -- Double-click on the label fires the same flow
            row.label:EnableMouse(true)
            row.label:SetScript("OnMouseDown", nil) -- FontString doesn't support; use overlay frame
            -- Workaround: an invisible Button on top of the label for double-click capture
            if not row.labelClick then
                row.labelClick = CreateFrame("Button", nil, row)
                row.labelClick:SetAllPoints(row.label)
                row.labelClick:RegisterForClicks("LeftButtonUp")
                row.labelClick:SetScript("OnDoubleClick", function() startRename() end)
            end
            row.labelClick:Show()

            -- Delete: empty category → silent; non-empty → popup
            row.deleteBtn:Show()
            row.deleteBtn:SetScript("OnClick", function()
                local count = #(buckets[capCatId] or {})
                if count == 0 then
                    if NS.Attributions then
                        NS.Attributions:DeleteCategory(currentRaidKey, currentEncounterKey, capCatId)
                    end
                else
                    local dlg = StaticPopup_Show("SRA_DELETE_CATEGORY", name, count)
                    if dlg then
                        dlg.data = {
                            raidKey = currentRaidKey,
                            encKey  = currentEncounterKey,
                            catId   = capCatId,
                        }
                    end
                end
            end)

            -- + Attrib button is wired in Task 7. Keep hidden for now.
            row.addAttribBtn:Hide()
        end
```

Note: `FontString` does not support `OnMouseDown`/`OnDoubleClick` on TBC clients, so the overlay Button trick (`row.labelClick`) is the standard workaround. Persist it on the row so we don't leak frames between refreshes.

- [ ] **Step 6.3: Verify in-game**

```
/reload
/sra
```

Open a boss with at least 2 categories and some attributions in them.

1. Click `^` on `P2` → `P2` swaps with the category above it. Re-click → swap back.
2. Double-click the `P1` label → an EditBox replaces it. Type `Phase 1`, press Enter → header updates to `Phase 1`. Refresh persists.
3. Click `R` on `Phase 1` → same inline edit flow opens. Press Escape → no change.
4. Click `X` on an empty category → it disappears immediately, no popup.
5. Click `X` on a non-empty category → popup `Delete category 'Phase 1' and move N attributions to Uncategorized?`. OK → all attributions move to `— Uncategorized —`, category is gone.
6. `/reload` and reopen: state persists.

- [ ] **Step 6.4: Commit**

```bash
git add UI.lua
git commit -m "UI: category header rename / delete / reorder

Wires the per-header buttons created in BuildCategoryHeaderRow:
  - ^ / v       → MoveCategory(catId, ±1)
  - R           → opens an inline rename EditBox over the label
  - double-click the label → same rename flow (via an overlay Button
                  because FontString has no OnMouseDown on TBC)
  - X           → silent delete on empty categories,
                  SRA_DELETE_CATEGORY popup otherwise
The Uncategorized header still exposes none of these, only the chevron
and the (still inert) checkbox."
```

---

## Task 7: `+ Attrib` button per category header

Adds an attribution scoped to a specific category, with that category's `categoryId` set at creation time.

**Files:**
- Modify: `UI.lua` — show and wire `row.addAttribBtn` for non-Uncategorized headers.

- [ ] **Step 7.1: Wire `addAttribBtn` in `renderHeaderRow`**

In the `else` branch of the `isUncategorized` check (the same block edited in Task 6), replace `row.addAttribBtn:Hide()` with:

```lua
            row.addAttribBtn:Show()
            row.addAttribBtn:SetScript("OnClick", function()
                if not (currentRaidKey and currentEncounterKey and NS.Attributions) then return end
                CommitPendingEdits()
                local newId = NS.Attributions:AddAttribution(
                    currentRaidKey, currentEncounterKey,
                    nil,            -- no marker
                    "",             -- empty context
                    {},             -- no players
                    capCatId        -- ← the category for this header
                )
                currentAttribKey = newId
                Refresh()
            end)
```

- [ ] **Step 7.2: Verify in-game**

```
/reload
/sra
```

1. Open a boss with at least one category.
2. Click `+ Attrib` on the `P1` header. Expected:
   - A new attribution row appears under `P1`, indented.
   - The right edit panel auto-selects it (highlighted in the list, fields cleared).
   - The right-panel `Category:` dropdown shows `P1`.
3. Click the global `+ Add Attribution` (still at the bottom of the middle column). Expected:
   - A new attribution appears in the `— Uncategorized —` section (categoryId = nil).
4. Verify announce: `Preview` should now have a `[Boss - P1] (no context): -` segment for the row created in step 2.

- [ ] **Step 7.3: Commit**

```bash
git add UI.lua
git commit -m "UI: + Attrib button on each category header

Clicking the per-section + Attrib button creates an attribution with
its categoryId pre-set to that header's catId. The new attribution is
auto-selected and the right edit panel reflects the category in its
dropdown. The global + Add Attribution at the bottom continues to
create Uncategorized attributions."
```

---

## Task 8: Fold state in CharDB

Makes the chevron toggle the section open/closed and persist the choice across `/reload`.

**Files:**
- Modify: `UI.lua` — read/write `NS.charDb.ui.collapsed`, conditionally hide attribution rows under collapsed headers, garbage-collect stale keys at `ADDON_LOADED`.

- [ ] **Step 8.1: Add fold-state helpers**

Insert near the top of `UI.lua`, after the `deselectedAttribs` helpers around line 183:

```lua
----------------------------------------------------------------------
-- Per-character fold state for category sections.
-- Stored in the existing CHAR_DEFAULTS.ui.collapsed slot, keyed by
-- "<raidKey>:<encKey>:<catId>" (or "...:__uncategorized__"). A key
-- mapping to a truthy value means the section is collapsed; absent or
-- false means expanded.
----------------------------------------------------------------------
local UNCAT_KEY = "__uncategorized__"

local function FoldKey(raidKey, encKey, catIdOrNil)
    return string.format("%s:%s:%s", raidKey or "?", encKey or "?", catIdOrNil or UNCAT_KEY)
end

local function GetCollapsedTable()
    if not NS.charDb then return nil end
    NS.charDb.ui = NS.charDb.ui or {}
    NS.charDb.ui.collapsed = NS.charDb.ui.collapsed or {}
    return NS.charDb.ui.collapsed
end

local function IsSectionFolded(raidKey, encKey, catIdOrNil)
    local t = GetCollapsedTable()
    if not t then return false end
    return t[FoldKey(raidKey, encKey, catIdOrNil)] == true
end

local function SetSectionFolded(raidKey, encKey, catIdOrNil, folded)
    local t = GetCollapsedTable()
    if not t then return end
    if folded then
        t[FoldKey(raidKey, encKey, catIdOrNil)] = true
    else
        t[FoldKey(raidKey, encKey, catIdOrNil)] = nil
    end
end

----------------------------------------------------------------------
-- Garbage-collect fold-state entries whose <raidKey>:<encKey> prefix
-- no longer corresponds to an existing encounter. Called on
-- ADDON_LOADED, idempotent.
----------------------------------------------------------------------
local function GCFoldState()
    local t = GetCollapsedTable()
    if not t or not NS.db or not NS.db.raids then return end
    for key in pairs(t) do
        local raidKey, encKey = key:match("^([^:]+):([^:]+):")
        local raid = raidKey and NS.db.raids[raidKey]
        local exists = raid and raid.encounters and encKey and raid.encounters[encKey]
        if not exists then t[key] = nil end
    end
end

NS:RegisterCallback("ADDON_LOADED", GCFoldState)
```

- [ ] **Step 8.2: Honour fold state in `renderHeaderRow` and `renderAttribRow`**

Update `renderHeaderRow` to set the chevron glyph and click handler from the fold state, and to short-circuit attribution rendering in the caller. Replace the chevron block from Task 3:

```lua
        local capFoldId = catId  -- nil for the Uncategorized header
        local folded = IsSectionFolded(currentRaidKey, currentEncounterKey, capFoldId)
        row.chevron.label:SetText(folded and "▶" or "▼")
        row.chevron:Show()
        row.chevron:SetScript("OnClick", function()
            SetSectionFolded(currentRaidKey, currentEncounterKey, capFoldId, not folded)
            Refresh()
        end)
```

Update the two callers in `RefreshAttribList`:

```lua
    -- 1. Uncategorized first (only if non-empty)
    if #uncatIds > 0 then
        renderHeaderRow(nil, "— Uncategorized —", true)
        if not IsSectionFolded(currentRaidKey, currentEncounterKey, nil) then
            for _, attribId in ipairs(uncatIds) do
                local attrib = enc.attributions[attribId]
                if attrib then renderAttribRow(attribId, attrib, 0) end
            end
        end
    end

    -- 2. Each category in categoryOrder
    for catId, cat in NS.Attributions:IterateCategories(currentRaidKey, currentEncounterKey) do
        renderHeaderRow(catId, cat.name or "?", false)
        if not IsSectionFolded(currentRaidKey, currentEncounterKey, catId) then
            local ids = buckets[catId] or {}
            for _, attribId in ipairs(ids) do
                local attrib = enc.attributions[attribId]
                if attrib then renderAttribRow(attribId, attrib, 20) end
            end
        end
    end
```

- [ ] **Step 8.3: Verify in-game**

```
/reload
/sra
```

1. Boss with at least 2 categories. Click the chevron `▼` of `P1` → it switches to `▶` and the P1 attributions disappear from the list. The P1 header itself stays visible.
2. Click again → expands.
3. `/reload` while P1 is folded. Reopen the editor, select the same boss → P1 is **still folded** (chevron still `▶`).
4. Open a different boss in the same raid → its sections render with default expanded state (no fold key for them).
5. Delete the boss whose P1 was folded → `/reload` → no Lua error. The fold key for that encounter has been GC'd.
6. Verify GC: `/dump SimpleRaidAssignCharDB.ui.collapsed` should not contain any key whose `<raidKey>:<encKey>` no longer exists.

- [ ] **Step 8.4: Commit**

```bash
git add UI.lua
git commit -m "UI: persist category fold state in CharDB

Per-character collapsed/expanded state stored under the existing
CHAR_DEFAULTS.ui.collapsed slot, keyed by <raidKey>:<encKey>:<catId>
(or :__uncategorized__ for the implicit bucket). Default is expanded
(absence ⇒ expanded). RefreshAttribList skips rendering attribution
rows under a folded section. Stale keys are garbage-collected on
ADDON_LOADED so deleting an encounter doesn't leak entries."
```

---

## Task 9: Tri-state announce checkboxes

Per-category checkbox cascades into its attributions; the master cascades into all categories. Partial state visualised by dimming the checked texture.

**Files:**
- Modify: `UI.lua` — extend the existing announce-selection helpers with a per-category variant, wire `row.selectCheck` in `renderHeaderRow`, refresh the master from per-category state.

- [ ] **Step 9.1: Add per-category selection helpers**

After the existing `AreAllAttribsSelected` helper around line 162, add:

```lua
----------------------------------------------------------------------
-- Compute the announce-selection state of a category as a tri-state:
--   "all"  → every attribution in the bucket is selected
--   "none" → none are selected (or the bucket is empty)
--   "some" → mixed
-- The bucket is the array of attribIds passed in (already grouped by
-- BucketAttribsByCategory), to avoid a second walk.
----------------------------------------------------------------------
local function CategorySelectionState(attribIds)
    if not attribIds or #attribIds == 0 then return "none" end
    local checked, unchecked = 0, 0
    for _, id in ipairs(attribIds) do
        if IsAttribSelected(id) then checked = checked + 1
        else                          unchecked = unchecked + 1 end
    end
    if unchecked == 0 then return "all"  end
    if checked   == 0 then return "none" end
    return "some"
end

local function ApplyCategorySelection(attribIds, state)
    if not attribIds then return end
    for _, id in ipairs(attribIds) do
        SetAttribSelected(id, state and true or false)
    end
end

----------------------------------------------------------------------
-- Visualise a tri-state checkbox. TBC's UICheckButtonTemplate has no
-- native mixed state, so we approximate "some" by leaving the box
-- checked but dimming its checked texture's vertex colour.
----------------------------------------------------------------------
local function ApplyTriState(check, state)
    if state == "all" then
        check:SetChecked(true)
        local tex = check:GetCheckedTexture()
        if tex then tex:SetVertexColor(1, 1, 1, 1) end
    elseif state == "some" then
        check:SetChecked(true)
        local tex = check:GetCheckedTexture()
        if tex then tex:SetVertexColor(0.6, 0.6, 0.6, 0.7) end
    else  -- "none"
        check:SetChecked(false)
        local tex = check:GetCheckedTexture()
        if tex then tex:SetVertexColor(1, 1, 1, 1) end
    end
end
```

- [ ] **Step 9.2: Wire `row.selectCheck` in `renderHeaderRow`**

Replace the existing checkbox block from Task 3 (`row.selectCheck:SetScript("OnClick", nil)`) with the per-category variant. Place it after the chevron logic from Task 8:

```lua
        local catBucket
        if isUncategorized then
            catBucket = uncatIds
        else
            catBucket = buckets[capFoldId] or {}
        end
        local state = CategorySelectionState(catBucket)
        ApplyTriState(row.selectCheck, state)

        local capBucketId = isUncategorized and nil or capFoldId
        row.selectCheck:Show()
        row.selectCheck:SetScript("OnClick", function(self)
            -- Click cascades: if "all" → flip to none; otherwise → all.
            local current = CategorySelectionState(catBucket)
            local newSelected = (current ~= "all")
            ApplyCategorySelection(catBucket, newSelected)
            Refresh()
        end)
```

- [ ] **Step 9.3: Update master checkbox sync**

The current code calls `panel.masterCheck:SetChecked(AreAllAttribsSelected(...))`. Replace those two call sites at the end of `RefreshAttribList` and inside `renderAttribRow`'s checkbox handler with a tri-state version that reuses the same helpers:

```lua
    -- Compute master state across all attributions
    local function ComputeMasterState()
        local checked, unchecked = 0, 0
        if not NS.Attributions then return "none" end
        for attribId in NS.Attributions:IterateAttributions(currentRaidKey, currentEncounterKey) do
            if IsAttribSelected(attribId) then checked = checked + 1
            else                                unchecked = unchecked + 1 end
        end
        if checked == 0 and unchecked == 0 then return "none" end
        if unchecked == 0 then return "all"  end
        if checked   == 0 then return "none" end
        return "some"
    end

    if panel.masterCheck then
        ApplyTriState(panel.masterCheck, ComputeMasterState())
    end
```

(Move `ComputeMasterState` and the `ApplyTriState` call to the bottom of `RefreshAttribList`, replacing the old `panel.masterCheck:SetChecked(...)` line.)

Inside `renderAttribRow`, the per-row checkbox `OnClick` currently calls `panel.masterCheck:SetChecked(AreAllAttribsSelected(...))`. Change it to call `Refresh()` instead — that's lighter than computing a partial state and Refresh re-runs the bucket walk. Replacement:

```lua
        row.selectCheck:SetScript("OnClick", function(self)
            SetAttribSelected(capturedId, self:GetChecked() and true or false)
            Refresh()
        end)
```

Update the master `OnClick` (around line 629) so it cycles `all`/`none` based on the tri-state:

```lua
    masterCheck:SetScript("OnClick", function(self)
        if not currentRaidKey or not currentEncounterKey then
            self:SetChecked(false); return
        end
        -- Compute the current state and toggle: all → none, otherwise → all.
        local checked, unchecked = 0, 0
        for attribId in NS.Attributions:IterateAttributions(currentRaidKey, currentEncounterKey) do
            if IsAttribSelected(attribId) then checked = checked + 1
            else                                unchecked = unchecked + 1 end
        end
        local state
        if checked == 0 and unchecked == 0 then state = "none"
        elseif unchecked == 0              then state = "all"
        elseif checked   == 0              then state = "none"
        else                                     state = "some" end

        local newSelected = (state ~= "all")
        SetAllAttribsSelected(currentRaidKey, currentEncounterKey, newSelected)
        Refresh()
    end)
```

- [ ] **Step 9.4: Verify in-game**

```
/reload
/sra
```

Boss with Uncategorized + 2 categories, each with a couple of attributions.

1. Master is fully checked. Per-category checks all show `all` (full checkmark).
2. Uncheck one attribution in P1. The per-row check goes off; P1's check shows the dimmed `some` style; master also goes to `some`.
3. Click P1's check (currently `some`). Expected: it flips to `all` (every P1 row check turns on). Master may stay `some` if P2 has dropouts, otherwise back to `all`.
4. Click P2's check. Cycles its rows off (`some` or `all` → `none`, all P2 row checks unchecked). Master shows `some`.
5. Click master. From `some` → `all` (every row checked). Click again → `none`.
6. Run `/reload` after a state change — selection state is intentionally **not** persisted (module-local `deselectedAttribs`), so everything resets to `all`. This is documented v1.1 behaviour.
7. Click `Announce` with one whole category unchecked. Expected raid chat: messages for the kept categories only, no message for the all-unchecked category.

- [ ] **Step 9.5: Commit**

```bash
git add UI.lua
git commit -m "UI: tri-state announce checkboxes

Per-category checkbox in each header reflects 'all/some/none' for its
attribution bucket. Click cascades: 'all' → 'none', otherwise → 'all'.
The master checkbox now also tri-states across the whole encounter
with the same flip rule. TBC's UICheckButtonTemplate has no native
mixed state so the partial state is approximated by dimming the
checked texture's vertex colour."
```

---

## Task 10: Versioning, CHANGELOG, README

Final shipping commit.

**Files:**
- Modify: `Core.lua` — bump `NS.version`.
- Modify: `SimpleRaidAssign.toc` — bump `## Version`.
- Modify: `CHANGELOG.md` — add `## [1.2.0] - 2026-04-28` section.
- Modify: `README.md` — add a "Categories (phases)" subsection under Features and refresh the example announce.

- [ ] **Step 10.1: Bump versions**

In `Core.lua` line 6:

```lua
NS.version = "1.2.0"
```

In `SimpleRaidAssign.toc` line 5:

```
## Version: 1.2.0
```

- [ ] **Step 10.2: Add the changelog section**

Insert below the `## [Unreleased]` line in `CHANGELOG.md`:

```markdown
## [1.2.0] - 2026-04-28

### Added

#### Per-boss attribution categories
- Each boss can now hold an ordered list of **categories** (e.g. `P1`, `P2`, `Adds`, `Burn`) inside which attributions are grouped. Categories are optional: a boss with no category renders exactly like in v1.1, all its attributions in an implicit `— Uncategorized —` section at the top of the list.
- New `+ Add Category` button next to the master "Select all" checkbox. It opens a preset dropdown (`P1`, `P2`, `P3`, `P4`, `Pull`, `Adds`, `Burn`, `Transition`, `Heroism`) plus a `Custom...` entry that pops up a text input (max 32 chars).
- Each category renders as a foldable header. Per-header controls: chevron `▼/▶` for fold, `^` / `v` to reorder among siblings, `R` (or double-click on the label) to rename inline, `X` to delete (silent on empty, popup confirmation on non-empty), `+ Attrib` to add an attribution scoped to this category.
- New `Category:` dropdown in the right edit panel (between the marker dropdown and the context input) lets the selected attribution be reassigned to another category, to `(none)`, or to a brand new category created on the spot via `+ New Category...`.
- Fold state is persisted per character in `SimpleRaidAssignCharDB.ui.collapsed[<raidKey>:<encKey>:<catId>]` (existing CharDB slot reused). Stale entries are garbage-collected on `ADDON_LOADED`.

#### Per-category chat announce
- The `[Announce]` button now emits **one chat message per category**: `[Boss - <CategoryName>] segment / segment / ...`, in `categoryOrder`. The Uncategorized bucket emits a generic `[Boss] ...` message first (identical to the v1.1 format).
- Empty categories and categories whose every attribution is unchecked are silently skipped.
- The 255-char auto-split applies independently per block: each block is run through `ChunkMessages` with its own title.

#### Tri-state announce checkboxes
- Each category header now has its own announce checkbox. State is tri-state: `all` (every attrib in the category checked) / `some` (mixed — visualised by dimming the checked texture) / `none`. Clicking cascades: `all` → `none`, otherwise → `all`.
- The master `Select all / none` checkbox is now tri-state across the whole encounter using the same rules.

### Changed
- **`Attributions.lua`** API additions: `AddCategory`, `RenameCategory`, `DeleteCategory`, `MoveCategory`, `IterateCategories`, `GetCategory`, `SetAttributionCategory`. `AddAttribution` accepts an optional `categoryId` argument (defaults to `nil` ⇒ Uncategorized — backwards compatible). `MoveAttribution` now scans for the closest neighbour with the same `categoryId` instead of the immediate one, so up/down arrows stay scoped to a category.
- **`Broadcast.lua`** API: `BuildSegments` accepts an optional `categoryFilter` argument (`nil` = legacy, `"uncategorized"`, or a `catId`). `BuildMessages` now produces multiple titled blocks. Public signature of `Announce` and `Preview` is unchanged.
- **Lazy migration**: legacy v1.1 encounters acquire empty `categories = {}` and `categoryOrder = {}` the first time they are read via `Attributions:GetEncounter`. No `ADDON_LOADED` migration step.

### Compatibility
- **`SRA1` protocol unchanged.** New encounter fields (`categories`, `categoryOrder`) and the `categoryId` field on attributions are sent as-is via the generic serialiser. v1.1 clients store the unknown fields in their SavedVariables and round-trip them intact when re-pushing; their own UI only renders the flat list, as before.
- **Export / Import (`SRA1:` prefix) format unchanged.**
```

- [ ] **Step 10.3: Update README**

Find the `### Workflow` section in `README.md`. Insert a new bullet after step 4 ("Click `+ Add Attribution`"):

```markdown
   - **Optional categories.** If you want to split the boss into phases (P1, P2, ...), click `+ Add Category` next to the `Select all` checkbox, pick a preset (or `Custom...`) and use the per-category `+ Attrib` button to add attributions inside it. Use the `Category:` dropdown in the right edit panel to move an existing attribution between categories.
```

Replace the example announce snippet under `### Example announce` with a categorised example:

```markdown
For an Illidan plan with phases P1, P2 and a couple of uncategorised tanks, the addon sends:

```
[Illidan Stormrage] Tanks: TankA, TankB / Heals: HA, HB, HC
[Illidan Stormrage - P1] {rt8} Kick: IntA, IntB (focus interrupter demo)
[Illidan Stormrage - P2] {rt7} Flame tank: TankC / {rt6} Parasite kite: HealerX
```
```

(Keep the explanatory bullets that follow it.)

- [ ] **Step 10.4: Verify in-game**

```
/reload
/sra
```

1. `/dump NS.version` → `"1.2.0"`.
2. The addon shows up in `/console addons` (or in the AddOns selector at the character screen) as version 1.2.0.
3. Existing raids load cleanly, no Lua error in `BugSack` / chat.
4. CHANGELOG and README render reasonably in a Markdown viewer (`gh markdown-preview` or VS Code preview).

- [ ] **Step 10.5: Commit**

```bash
git add Core.lua SimpleRaidAssign.toc CHANGELOG.md README.md
git commit -m "Release 1.2.0: attribution categories per boss"
```

---

## Self-review

Re-read the spec sections (`docs/superpowers/specs/2026-04-28-attribution-categories-design.md`) and confirm:

- [x] Data model: covered by Task 1 (categories CRUD + lazy normalization + AddAttribution/MoveAttribution updates) and Task 8 (CharDB fold state).
- [x] UI layout (Section 2 of spec): Task 3 (grouping + headers), Task 4 (`+ Add Category`), Task 5 (right-panel dropdown), Task 6 (rename/delete/reorder), Task 7 (`+ Attrib` per section), Task 8 (fold state), Task 9 (tri-state checkboxes).
- [x] CRUD ergonomics (Section 3 of spec): Tasks 4–7 cover every interaction listed.
- [x] Broadcast (Section 4 of spec): Task 2.
- [x] Persistence + sync (Section 5 of spec): Task 1 (no protocol bump), Task 8 (CharDB), Task 10 (versioning + CHANGELOG compatibility note).
- [x] No `TBD` / `TODO` / `add appropriate error handling` / placeholder steps.
- [x] Method names consistent across tasks: `AddCategory`/`RenameCategory`/`DeleteCategory`/`MoveCategory`/`IterateCategories`/`GetCategory`/`SetAttributionCategory` used identically in Tasks 1, 5, 6, 7.
- [x] Anchors (line numbers) named in the existing UI.lua are confirmed: `master checkbox` ~626, `addAttribBtn` ~645, `markerDrop` ~759, `clearMarkerBtn` ~800, `contextLabel/Box` ~821-839, `RefreshAttribList` ~1447, `BuildAttribRow` ~1419, `OpenBossPicker` ~1047, popups ~198-360.
- [x] Each task ends with an explicit `git commit` step using a heredoc-free message.
