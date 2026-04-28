----------------------------------------------------------------------
-- SimpleRaidAssign  -  UI.lua
-- Two-screen window: Raid Summary (home) and Raid Editor.
-- Raid Summary lists saved raids with CRUD actions.
-- Raid Editor has a boss sidebar, an attribution list, and an edit
-- panel for the selected attribution.
----------------------------------------------------------------------
local _, NS = ...

local UI = {}
NS.UI = UI

----------------------------------------------------------------------
-- Style
----------------------------------------------------------------------
local COLOURS = {
    bg        = { 0.08, 0.08, 0.10, 0.95 },
    panel     = { 0.12, 0.12, 0.14, 0.96 },
    border    = { 0.30, 0.30, 0.34, 1    },
    accent    = { 0.00, 0.80, 1.00, 1    },
    accent2   = { 1.00, 0.65, 0.20, 1    },
    text      = { 1, 1, 1, 1 },
    dim       = { 0.65, 0.65, 0.70, 1 },
    rowAlt    = { 1, 1, 1, 0.04 },
    rowHover  = { 1, 1, 1, 0.10 },
    rowActive = { 0.00, 0.50, 0.90, 0.25 },
    danger    = { 1.00, 0.35, 0.35, 1 },
}

local function IsElvUI()
    return ElvUI and ElvUI[1] and true or false
end

local function SkinFrame(f)
    if IsElvUI() and f.SetTemplate then
        f:SetTemplate("Transparent")
        return
    end
    if not f.SetBackdrop and BackdropTemplateMixin then
        Mixin(f, BackdropTemplateMixin)
    end
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        f:SetBackdropColor(unpack(COLOURS.bg))
        f:SetBackdropBorderColor(unpack(COLOURS.border))
    end
end

local function GetFont()
    if IsElvUI() then
        local E = ElvUI[1]
        local LSM = E.Libs and E.Libs.LSM
        if LSM then
            local font = LSM:Fetch("font", E.db and E.db.general and E.db.general.font)
            if font then return font end
        end
    end
    return "Fonts\\FRIZQT__.TTF"
end

local function FS(parent, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(GetFont(), size or 12, "OUTLINE")
    fs:SetTextColor(unpack(COLOURS.text))
    return fs
end

local function MakePanel(parent)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    SkinFrame(f)
    return f
end

----------------------------------------------------------------------
-- ScrollFrame scroll-child auto-sizing helper.
-- A scroll child defaults to 1x1 which makes any row anchored to its
-- TOPLEFT+TOPRIGHT collapse to 0 pixels wide. Hook the scroll frame's
-- size changes so the content width follows it, and also call it on
-- every show / first paint. We additionally seed a sensible default
-- width via OnUpdate (one-shot) for the very first refresh that may
-- run before WoW has actually computed the frame layout.
----------------------------------------------------------------------
local function AutoSizeScrollChild(scroll, content)
    local function update()
        local w = scroll:GetWidth()
        if w and w > 0 then content:SetWidth(w) end
    end
    scroll:HookScript("OnSizeChanged", update)
    scroll:HookScript("OnShow", update)

    -- Run once on the next OnUpdate tick to catch the case where
    -- the frame becomes laid out after this function returns.
    scroll:SetScript("OnUpdate", function(self)
        update()
        self:SetScript("OnUpdate", nil)
    end)

    update()
end

----------------------------------------------------------------------
-- Time formatting helper for the raid summary cartouche
----------------------------------------------------------------------
local function TimeAgo(ts)
    if not ts or ts == 0 then return "never" end
    local delta = time() - ts
    if delta < 60 then return "just now" end
    if delta < 3600 then return string.format("%dm ago", math.floor(delta / 60)) end
    if delta < 86400 then return string.format("%dh ago", math.floor(delta / 3600)) end
    if delta < 86400 * 7 then return string.format("%dd ago", math.floor(delta / 86400)) end
    return date("%Y-%m-%d", ts)
end

----------------------------------------------------------------------
-- Forward declarations
----------------------------------------------------------------------
local mainFrame
local summaryView, editorView
local currentScreen      -- "summary" or "editor"
local currentRaidKey
local currentEncounterKey
local currentAttribKey

local Refresh
local ShowSummary, ShowEditor
local SafeSetText, CommitPendingEdits

----------------------------------------------------------------------
-- Per-attribution announce-selection state.
--
-- Held in a module-local table (NOT persisted to the SavedVariables)
-- so it resets between game sessions but is shared across the
-- different bosses in the current session. Default state for any
-- attribution id absent from the table is "selected" — only entries
-- the user has explicitly UNCHECKED show up here.
----------------------------------------------------------------------
local deselectedAttribs = {}

local function IsAttribSelected(attribId)
    return not deselectedAttribs[attribId]
end

local function SetAttribSelected(attribId, selected)
    if selected then
        deselectedAttribs[attribId] = nil
    else
        deselectedAttribs[attribId] = true
    end
end

local function AreAllAttribsSelected(raidKey, encounterKey)
    if not NS.Attributions then return true end
    local count = 0
    for attribId in NS.Attributions:IterateAttributions(raidKey, encounterKey) do
        count = count + 1
        if not IsAttribSelected(attribId) then return false end
    end
    return count > 0
end

local function SetAllAttribsSelected(raidKey, encounterKey, state)
    if not NS.Attributions then return end
    for attribId in NS.Attributions:IterateAttributions(raidKey, encounterKey) do
        SetAttribSelected(attribId, state)
    end
end

local function BuildSelectedFilter(raidKey, encounterKey)
    local filter = {}
    local any = false
    if not NS.Attributions then return filter, any end
    for attribId in NS.Attributions:IterateAttributions(raidKey, encounterKey) do
        if IsAttribSelected(attribId) then
            filter[attribId] = true
            any = true
        end
    end
    return filter, any
end

-- ====================================================================
--  STATIC POPUPS
-- ====================================================================
-- Compat helper: on older clients StaticPopup's edit box lives at
-- self.editBox, on modern clients (TBC Anniversary, retail) it's at
-- self.EditBox. Fall back to the global name as a last resort.
local function PopupEditBox(self)
    return self.editBox
        or self.EditBox
        or (self.GetName and _G[self:GetName() .. "EditBox"])
        or nil
end

StaticPopupDialogs["SRA_NEW_RAID"] = {
    text = "New raid name:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = 1,
    maxLetters = 64,
    OnShow = function(self)
        local eb = PopupEditBox(self)
        if eb then
            eb:SetText("")
            eb:SetFocus()
        end
    end,
    OnAccept = function(self)
        local eb = PopupEditBox(self)
        local name = (eb and eb:GetText()) or ""
        if name ~= "" and NS.Raids then
            local key = NS.Raids:Create(name)
            currentRaidKey = key
            currentEncounterKey = nil
            currentAttribKey = nil
            ShowEditor()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if parent and parent.button1 then parent.button1:Click() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["SRA_RENAME_RAID"] = {
    text = "Rename raid:",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = 1,
    maxLetters = 64,
    OnShow = function(self)
        local raid = NS.Raids and NS.Raids:Get(self.data)
        local eb = PopupEditBox(self)
        if eb then
            eb:SetText(raid and raid.name or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    OnAccept = function(self)
        local eb = PopupEditBox(self)
        local name = (eb and eb:GetText()) or ""
        if name ~= "" and NS.Raids then
            NS.Raids:Rename(self.data, name)
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if parent and parent.button1 then parent.button1:Click() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["SRA_DELETE_RAID"] = {
    text = "Delete raid \"%s\"?\nThis cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self)
        if NS.Raids then
            NS.Raids:Delete(self.data)
            if currentRaidKey == self.data then
                currentRaidKey = nil
                currentEncounterKey = nil
                currentAttribKey = nil
                ShowSummary()
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["SRA_DUPLICATE_RAID"] = {
    text = "Duplicate as:",
    button1 = "Duplicate",
    button2 = "Cancel",
    hasEditBox = 1,
    maxLetters = 64,
    OnShow = function(self)
        local raid = NS.Raids and NS.Raids:Get(self.data)
        local eb = PopupEditBox(self)
        if eb then
            eb:SetText(raid and (raid.name .. " (copy)") or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    OnAccept = function(self)
        local eb = PopupEditBox(self)
        local name = (eb and eb:GetText()) or ""
        if name ~= "" and NS.Raids then
            local newKey = NS.Raids:Create(name, self.data)
            currentRaidKey = newKey
            currentEncounterKey = nil
            currentAttribKey = nil
            ShowEditor()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if parent and parent.button1 then parent.button1:Click() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["SRA_DELETE_ENCOUNTER"] = {
    text = "Delete boss \"%s\" from this raid?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self)
        if NS.Attributions and currentRaidKey and self.data then
            NS.Attributions:DeleteEncounter(currentRaidKey, self.data)
            if currentEncounterKey == self.data then
                currentEncounterKey = nil
                currentAttribKey = nil
            end
            Refresh()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ====================================================================
--  RAID SUMMARY VIEW
-- ====================================================================

local function BuildSummaryView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    local header = FS(view, 16)
    header:SetPoint("TOPLEFT", 12, -12)
    header:SetText("My Raids")
    header:SetTextColor(unpack(COLOURS.accent))

    local sub = FS(view, 11)
    sub:SetPoint("TOPLEFT", 12, -32)
    sub:SetText("All saved raid plans, most recent first.")
    sub:SetTextColor(unpack(COLOURS.dim))

    local newBtn = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    newBtn:SetSize(100, 24)
    newBtn:SetPoint("TOPRIGHT", -12, -12)
    newBtn:SetText("+ New Raid")
    newBtn:SetScript("OnClick", function() StaticPopup_Show("SRA_NEW_RAID") end)

    local importBtn = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 24)
    importBtn:SetPoint("RIGHT", newBtn, "LEFT", -6, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function() UI:ShowImportDialog() end)

    -- Scrolling list of raid cartouches
    local panel = MakePanel(view)
    panel:SetPoint("TOPLEFT", 12, -52)
    panel:SetPoint("BOTTOMRIGHT", -12, 12)

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    AutoSizeScrollChild(scroll, content)

    view.scroll  = scroll
    view.content = content
    view.panel   = panel
    view.rows    = {}
    return view
end

local function BuildSummaryRow(parent)
    local row = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    SkinFrame(row)
    row:SetHeight(72)

    -- Action buttons on the right (horizontal row, always visible).
    -- Built FIRST so the text fontstrings below can cap their RIGHT
    -- anchor to the leftmost button and avoid overlapping it.
    row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.delBtn:SetSize(64, 22)
    row.delBtn:SetPoint("TOPRIGHT", -10, -10)
    row.delBtn:SetText("Delete")

    row.dupBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.dupBtn:SetSize(80, 22)
    row.dupBtn:SetPoint("RIGHT", row.delBtn, "LEFT", -4, 0)
    row.dupBtn:SetText("Duplicate")

    row.exportBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.exportBtn:SetSize(64, 22)
    row.exportBtn:SetPoint("RIGHT", row.dupBtn, "LEFT", -4, 0)
    row.exportBtn:SetText("Export")

    row.renameBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.renameBtn:SetSize(70, 22)
    row.renameBtn:SetPoint("RIGHT", row.exportBtn, "LEFT", -4, 0)
    row.renameBtn:SetText("Rename")

    -- Name, meta and counters (left side), anchored TOPLEFT and capped
    -- at the leftmost button so a long raid name can't collide with
    -- the action buttons.
    row.name = FS(row, 14)
    row.name:SetPoint("TOPLEFT", 12, -10)
    row.name:SetPoint("TOPRIGHT", row.renameBtn, "TOPLEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetTextColor(unpack(COLOURS.accent))
    row.name:SetWordWrap(false)

    row.meta = FS(row, 10)
    row.meta:SetPoint("TOPLEFT", 12, -30)
    row.meta:SetPoint("TOPRIGHT", row.renameBtn, "BOTTOMLEFT", -8, 0)
    row.meta:SetJustifyH("LEFT")
    row.meta:SetTextColor(unpack(COLOURS.dim))
    row.meta:SetWordWrap(false)

    -- Hover highlight + click-row-to-open hint anchored bottom-right,
    -- counters anchored bottom-left with its RIGHT capped at the hint
    -- so the two never collide.
    local clickHint = FS(row, 9)
    clickHint:SetPoint("BOTTOMRIGHT", -12, 10)
    clickHint:SetText("click row to open")
    clickHint:SetTextColor(0.5, 0.5, 0.55, 1)
    row.clickHint = clickHint

    row.counters = FS(row, 11)
    row.counters:SetPoint("BOTTOMLEFT", 12, 10)
    row.counters:SetPoint("BOTTOMRIGHT", clickHint, "BOTTOMLEFT", -10, 0)
    row.counters:SetJustifyH("LEFT")
    row.counters:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(unpack(COLOURS.rowHover)) end
    end)
    row:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then self:SetBackdropColor(unpack(COLOURS.bg)) end
    end)

    return row
end

local function RefreshSummary()
    local view = summaryView
    if not view then return end

    for _, row in ipairs(view.rows) do row:Hide() end

    if not NS.Raids then return end

    local y = 0
    local i = 0
    for raidKey, raid in NS.Raids:Iterate() do
        i = i + 1
        local row = view.rows[i]
        if not row then
            row = BuildSummaryRow(view.content)
            view.rows[i] = row
        end

        row.name:SetText(raid.name or "?")
        row.meta:SetText(string.format("created by %s - last edit %s",
            raid.updatedBy or raid.createdBy or "?",
            TimeAgo(raid.updatedAt)))
        row.counters:SetText(string.format(
            "|cff88c0ff%d|r boss  |cff88c0ff%d|r attributions  |cff88c0ff%d|r players",
            NS.Raids:CountEncounters(raidKey),
            NS.Raids:CountAttributions(raidKey),
            NS.Raids:CountAssignedPlayers(raidKey)))

        -- Clicking anywhere on the row (background) opens the raid.
        -- Child buttons swallow their own clicks so they don't propagate.
        row:SetScript("OnClick", function()
            currentRaidKey = raidKey
            currentEncounterKey = nil
            currentAttribKey = nil
            ShowEditor()
        end)
        row.renameBtn:SetScript("OnClick", function()
            local dialog = StaticPopup_Show("SRA_RENAME_RAID")
            if dialog then dialog.data = raidKey end
        end)
        row.exportBtn:SetScript("OnClick", function()
            UI:ShowExportDialog(raidKey)
        end)
        row.dupBtn:SetScript("OnClick", function()
            local dialog = StaticPopup_Show("SRA_DUPLICATE_RAID")
            if dialog then dialog.data = raidKey end
        end)
        row.delBtn:SetScript("OnClick", function()
            local dialog = StaticPopup_Show("SRA_DELETE_RAID", raid.name or "?")
            if dialog then dialog.data = raidKey end
        end)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", view.content, "TOPRIGHT", 0, -y)
        row:Show()
        y = y + 78
    end

    if i == 0 then
        if not view.emptyText then
            -- Anchor on the panel (not the scroll child) so the text has
            -- the full panel width and centers correctly. The scroll
            -- child is only 1px wide and would clip half the string.
            view.emptyText = FS(view.panel, 12)
            view.emptyText:SetPoint("TOPLEFT", view.panel, "TOPLEFT", 12, -40)
            view.emptyText:SetPoint("TOPRIGHT", view.panel, "TOPRIGHT", -12, -40)
            view.emptyText:SetJustifyH("CENTER")
            view.emptyText:SetTextColor(unpack(COLOURS.dim))
            view.emptyText:SetText("No raid yet. Click |cff00ccff+ New Raid|r to create your first one.")
        end
        view.emptyText:Show()
    elseif view.emptyText then
        view.emptyText:Hide()
    end

    view.content:SetHeight(math.max(1, y))
end

-- ====================================================================
--  RAID EDITOR VIEW
-- ====================================================================

local function BuildEditorView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints(parent)

    -- Top header with back button and raid name
    local backBtn = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    backBtn:SetSize(70, 22)
    backBtn:SetPoint("TOPLEFT", 12, -12)
    backBtn:SetText("< Back")
    backBtn:SetScript("OnClick", function() ShowSummary() end)
    view.backBtn = backBtn

    local title = FS(view, 15)
    title:SetPoint("LEFT", backBtn, "RIGHT", 10, 0)
    title:SetTextColor(unpack(COLOURS.accent))
    view.title = title

    -- Three-column layout below the header
    local topPad = 44

    -- Left sidebar: bosses list
    local bossPanel = MakePanel(view)
    bossPanel:SetPoint("TOPLEFT", 12, -topPad)
    bossPanel:SetPoint("BOTTOMLEFT", 12, 12)
    bossPanel:SetWidth(170)

    local bossHeader = FS(bossPanel, 12)
    bossHeader:SetPoint("TOPLEFT", 8, -8)
    bossHeader:SetText("Bosses")
    bossHeader:SetTextColor(unpack(COLOURS.accent))

    local addBossBtn = CreateFrame("Button", nil, bossPanel, "UIPanelButtonTemplate")
    addBossBtn:SetSize(90, 20)
    addBossBtn:SetPoint("BOTTOMLEFT", 8, 8)
    addBossBtn:SetText("+ Add Boss")
    addBossBtn:SetScript("OnClick", function()
        UI:OpenBossPicker()
    end)

    local bossScroll = CreateFrame("ScrollFrame", nil, bossPanel, "UIPanelScrollFrameTemplate")
    bossScroll:SetPoint("TOPLEFT", 4, -28)
    bossScroll:SetPoint("BOTTOMRIGHT", -24, 36)
    local bossContent = CreateFrame("Frame", nil, bossScroll)
    bossContent:SetSize(1, 1)
    bossScroll:SetScrollChild(bossContent)
    AutoSizeScrollChild(bossScroll, bossContent)

    bossPanel.scroll  = bossScroll
    bossPanel.content = bossContent
    bossPanel.rows    = {}
    view.bossPanel    = bossPanel

    -- Middle: attribution list + announce controls
    local attribPanel = MakePanel(view)
    attribPanel:SetPoint("TOPLEFT", bossPanel, "TOPRIGHT", 6, 0)
    attribPanel:SetPoint("BOTTOMLEFT", bossPanel, "BOTTOMRIGHT", 6, 0)
    attribPanel:SetWidth(340)

    -- Header on one line, hint text on a second line underneath, so
    -- a long "Attributions - <boss name>" label can't collide with
    -- the help instructions.
    local attribHeader = FS(attribPanel, 12)
    attribHeader:SetPoint("TOPLEFT", 8, -8)
    attribHeader:SetPoint("TOPRIGHT", -8, -8)
    attribHeader:SetJustifyH("LEFT")
    attribHeader:SetWordWrap(false)
    attribHeader:SetText("Attributions")
    attribHeader:SetTextColor(unpack(COLOURS.accent))
    attribPanel.header = attribHeader

    local attribHint = FS(attribPanel, 9)
    attribHint:SetPoint("TOPLEFT", 8, -24)
    attribHint:SetPoint("TOPRIGHT", -8, -24)
    attribHint:SetJustifyH("LEFT")
    attribHint:SetWordWrap(false)
    attribHint:SetText("click an attribution to edit it on the right")
    attribHint:SetTextColor(unpack(COLOURS.dim))

    -- Master "select all / none" checkbox above the attribution scroll
    -- list. Stays visible regardless of scroll position because it
    -- lives outside the scroll frame.
    local masterCheck = CreateFrame("CheckButton", nil, attribPanel, "UICheckButtonTemplate")
    masterCheck:SetSize(20, 20)
    masterCheck:SetPoint("TOPLEFT", 6, -38)
    masterCheck:SetScript("OnClick", function(self)
        if not currentRaidKey or not currentEncounterKey then
            self:SetChecked(false)
            return
        end
        local newState = self:GetChecked() and true or false
        SetAllAttribsSelected(currentRaidKey, currentEncounterKey, newState)
        Refresh()
    end)
    attribPanel.masterCheck = masterCheck

    local masterLabel = FS(attribPanel, 10)
    masterLabel:SetPoint("LEFT", masterCheck, "RIGHT", 2, 0)
    masterLabel:SetText("Select all / none")
    masterLabel:SetTextColor(unpack(COLOURS.dim))

    local addAttribBtn = CreateFrame("Button", nil, attribPanel, "UIPanelButtonTemplate")
    addAttribBtn:SetSize(130, 20)
    addAttribBtn:SetPoint("BOTTOMLEFT", 8, 64)
    addAttribBtn:SetText("+ Add Attribution")
    addAttribBtn:SetScript("OnClick", function()
        if not currentRaidKey or not currentEncounterKey or not NS.Attributions then return end
        CommitPendingEdits()
        local attribId = NS.Attributions:AddAttribution(currentRaidKey, currentEncounterKey, nil, "", {})
        currentAttribKey = attribId
        Refresh()
    end)

    -- Announce bar (bottom of middle column)
    local announceBar = CreateFrame("Frame", nil, attribPanel)
    announceBar:SetPoint("BOTTOMLEFT", 8, 8)
    announceBar:SetPoint("BOTTOMRIGHT", -8, 8)
    announceBar:SetHeight(50)

    local announceLabel = FS(announceBar, 10)
    announceLabel:SetPoint("TOPLEFT", 0, 0)
    announceLabel:SetText("Announce to:")
    announceLabel:SetTextColor(unpack(COLOURS.dim))

    local channelDrop = CreateFrame("Frame", "SRAChannelDropdown", announceBar, "UIDropDownMenuTemplate")
    channelDrop:SetPoint("LEFT", announceLabel, "RIGHT", -6, -2)
    local CHANNELS = { "RAID", "RAID_WARNING", "PARTY", "SAY", "GUILD", "OFFICER" }
    UIDropDownMenu_SetWidth(channelDrop, 110)
    UIDropDownMenu_Initialize(channelDrop, function(self, level)
        for _, ch in ipairs(CHANNELS) do
            local info = UIDropDownMenu_CreateInfo()
            -- notCheckable on every entry so they all share the same
            -- left padding (otherwise the currently-selected entry has
            -- an extra checkbox indent that the others lack, breaking
            -- alignment on TBC Anniversary clients).
            info.text         = ch
            info.notCheckable = true
            info.func = function()
                if NS.db then NS.db.settings.announceChannel = ch end
                UIDropDownMenu_SetSelectedValue(channelDrop, ch)
                UIDropDownMenu_SetText(channelDrop, ch)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(channelDrop, (NS.db and NS.db.settings.announceChannel) or "RAID")
    UIDropDownMenu_SetText(channelDrop, (NS.db and NS.db.settings.announceChannel) or "RAID")
    attribPanel.channelDrop = channelDrop

    -- Single "Announce" button. Output is always in English.
    local announceBtn = CreateFrame("Button", nil, announceBar, "UIPanelButtonTemplate")
    announceBtn:SetSize(95, 22)
    announceBtn:SetPoint("BOTTOMLEFT", 0, 0)
    announceBtn:SetText("Announce")
    announceBtn:SetScript("OnClick", function()
        -- Commit any in-progress text edit (note/context/players) BEFORE
        -- reading the attribution out of the DB, otherwise pending
        -- changes are lost to the announce.
        CommitPendingEdits()
        if NS.Broadcast and currentRaidKey and currentEncounterKey then
            local filter, any = BuildSelectedFilter(currentRaidKey, currentEncounterKey)
            if not any then
                NS:Print("No attributions selected to announce.")
                return
            end
            NS.Broadcast:Announce(currentRaidKey, currentEncounterKey, "EN", nil, filter)
        end
    end)

    local previewBtn = CreateFrame("Button", nil, announceBar, "UIPanelButtonTemplate")
    previewBtn:SetSize(70, 22)
    previewBtn:SetPoint("LEFT", announceBtn, "RIGHT", 4, 0)
    previewBtn:SetText("Preview")
    previewBtn:SetScript("OnClick", function()
        CommitPendingEdits()
        if NS.Broadcast and currentRaidKey and currentEncounterKey then
            local filter, any = BuildSelectedFilter(currentRaidKey, currentEncounterKey)
            if not any then
                NS:Print("No attributions selected to preview.")
                return
            end
            NS.Broadcast:Preview(currentRaidKey, currentEncounterKey, filter)
        end
    end)

    -- Attribution scrolling list
    local attribScroll = CreateFrame("ScrollFrame", nil, attribPanel, "UIPanelScrollFrameTemplate")
    attribScroll:SetPoint("TOPLEFT", 4, -64)
    attribScroll:SetPoint("BOTTOMRIGHT", -24, 90)
    local attribContent = CreateFrame("Frame", nil, attribScroll)
    attribContent:SetSize(1, 1)
    attribScroll:SetScrollChild(attribContent)
    AutoSizeScrollChild(attribScroll, attribContent)

    attribPanel.scroll      = attribScroll
    attribPanel.content     = attribContent
    attribPanel.rows        = {}    -- attribution rows
    attribPanel.headerRows  = {}    -- category header rows
    view.attribPanel        = attribPanel

    -- Right: edit panel
    local editPanel = MakePanel(view)
    editPanel:SetPoint("TOPLEFT", attribPanel, "TOPRIGHT", 6, 0)
    editPanel:SetPoint("BOTTOMRIGHT", -12, 12)

    local editHeader = FS(editPanel, 12)
    editHeader:SetPoint("TOPLEFT", 10, -10)
    editHeader:SetText("Edit Attribution")
    editHeader:SetTextColor(unpack(COLOURS.accent))

    -- Marker dropdown
    local markerLabel = FS(editPanel, 10)
    markerLabel:SetPoint("TOPLEFT", 10, -36)
    markerLabel:SetText("Marker:")
    markerLabel:SetTextColor(unpack(COLOURS.dim))

    local markerDrop = CreateFrame("Frame", "SRAMarkerDropdown", editPanel, "UIDropDownMenuTemplate")
    markerDrop:SetPoint("TOPLEFT", 4, -52)
    UIDropDownMenu_SetWidth(markerDrop, 130)
    UIDropDownMenu_Initialize(markerDrop, function(self, level)
        -- None option: clear any marker on the current attribution.
        -- notCheckable = true so the entry renders without a checkbox
        -- and the text alignment matches the marker icons below.
        local info = UIDropDownMenu_CreateInfo()
        info.text = "(none)"
        info.notCheckable = true
        info.func = function()
            UIDropDownMenu_SetSelectedValue(markerDrop, 0)
            UIDropDownMenu_SetText(markerDrop, "|cff888888(none)|r")
            if NS.Attributions and currentRaidKey and currentEncounterKey and currentAttribKey then
                NS.Attributions:ClearMarker(currentRaidKey, currentEncounterKey, currentAttribKey)
            end
        end
        UIDropDownMenu_AddButton(info, level)

        if NS.Data then
            for m in NS.Data:IterateMarkers() do
                local info2 = UIDropDownMenu_CreateInfo()
                info2.text = "|T" .. m.texture .. ":16|t " .. m.label
                info2.value = m.id
                info2.notCheckable = true
                info2.func = function()
                    UIDropDownMenu_SetSelectedValue(markerDrop, m.id)
                    UIDropDownMenu_SetText(markerDrop, "|T" .. m.texture .. ":16|t " .. m.label)
                    if NS.Attributions and currentRaidKey and currentEncounterKey and currentAttribKey then
                        NS.Attributions:UpdateAttribution(currentRaidKey, currentEncounterKey, currentAttribKey, { marker = m.id })
                    end
                end
                UIDropDownMenu_AddButton(info2, level)
            end
        end
    end)
    editPanel.markerDrop = markerDrop

    -- Explicit "clear marker" X button next to the dropdown. A single
    -- click removes the marker without having to open the dropdown
    -- and pick the (none) entry.
    local clearMarkerBtn = CreateFrame("Button", nil, editPanel, "UIPanelButtonTemplate")
    clearMarkerBtn:SetSize(24, 22)
    clearMarkerBtn:SetPoint("LEFT", markerDrop, "RIGHT", -10, 2)
    clearMarkerBtn:SetText("X")
    clearMarkerBtn:SetScript("OnClick", function()
        if NS.Attributions and currentRaidKey and currentEncounterKey and currentAttribKey then
            NS.Attributions:ClearMarker(currentRaidKey, currentEncounterKey, currentAttribKey)
            UIDropDownMenu_SetSelectedValue(markerDrop, 0)
            UIDropDownMenu_SetText(markerDrop, "|cff888888(none)|r")
            Refresh()
        end
    end)
    clearMarkerBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Clear marker")
        GameTooltip:AddLine("Remove the raid target icon from this attribution.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    clearMarkerBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Context text
    local contextLabel = FS(editPanel, 10)
    contextLabel:SetPoint("TOPLEFT", 10, -88)
    contextLabel:SetText("Context:")
    contextLabel:SetTextColor(unpack(COLOURS.dim))

    local contextBox = CreateFrame("EditBox", nil, editPanel, "InputBoxTemplate")
    contextBox:SetSize(220, 22)
    contextBox:SetPoint("TOPLEFT", 16, -104)
    contextBox:SetAutoFocus(false)
    contextBox:SetMaxLetters(120)
    contextBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    contextBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    contextBox:SetScript("OnEditFocusLost", function(self)
        if NS.Attributions and currentRaidKey and currentEncounterKey and currentAttribKey then
            NS.Attributions:UpdateAttribution(currentRaidKey, currentEncounterKey, currentAttribKey,
                { context = self:GetText() or "" })
            Refresh()
        end
    end)
    editPanel.contextBox = contextBox

    -- ---------------- Players section ----------------
    -- Vertical list of currently-assigned players (each row has a
    -- remove X button), plus an input + Add button + From Group
    -- dropdown trigger underneath for adding new ones.
    local playersLabel = FS(editPanel, 10)
    playersLabel:SetPoint("TOPLEFT", 10, -136)
    playersLabel:SetText("Players:")
    playersLabel:SetTextColor(unpack(COLOURS.dim))

    -- List backdrop / container
    local playersBg = MakePanel(editPanel)
    playersBg:SetPoint("TOPLEFT", 16, -152)
    playersBg:SetPoint("TOPRIGHT", -16, -152)
    playersBg:SetHeight(96)

    local playersScroll = CreateFrame("ScrollFrame", nil, playersBg, "UIPanelScrollFrameTemplate")
    playersScroll:SetPoint("TOPLEFT", 4, -4)
    playersScroll:SetPoint("BOTTOMRIGHT", -24, 4)

    local playersContent = CreateFrame("Frame", nil, playersScroll)
    playersContent:SetSize(1, 1)
    playersScroll:SetScrollChild(playersContent)
    AutoSizeScrollChild(playersScroll, playersContent)

    editPanel.playersBg      = playersBg
    editPanel.playersScroll  = playersScroll
    editPanel.playersContent = playersContent
    editPanel.playerRows     = {}

    -- Input row underneath the list: text field + Add button.
    -- "From Group" is on its own line below to keep both rows
    -- comfortably inside the edit panel (which is only ~270 px wide).
    local playersInput = CreateFrame("EditBox", nil, editPanel, "InputBoxTemplate")
    playersInput:SetSize(170, 22)
    playersInput:SetPoint("TOPLEFT", 16, -256)
    playersInput:SetAutoFocus(false)
    playersInput:SetMaxLetters(32)

    local addPlayerBtn = CreateFrame("Button", nil, editPanel, "UIPanelButtonTemplate")
    addPlayerBtn:SetSize(60, 22)
    addPlayerBtn:SetPoint("LEFT", playersInput, "RIGHT", 6, 0)
    addPlayerBtn:SetText("Add")

    local fromGroupBtn = CreateFrame("Button", nil, editPanel, "UIPanelButtonTemplate")
    fromGroupBtn:SetSize(120, 22)
    fromGroupBtn:SetPoint("TOPLEFT", playersInput, "BOTTOMLEFT", 0, -4)
    fromGroupBtn:SetText("+ From Group")
    fromGroupBtn:SetScript("OnClick", function() UI:OpenPlayerPicker() end)

    -- Add the typed name and clear the input. Used by the Add button
    -- and by the EditBox's Enter key.
    local function CommitTypedPlayer()
        if not (NS.Attributions and currentRaidKey and currentEncounterKey and currentAttribKey) then
            return
        end
        local raw = playersInput:GetText() or ""
        local name = raw:match("^%s*(.-)%s*$") or ""  -- trim
        if name == "" then return end
        NS.Attributions:AddPlayer(currentRaidKey, currentEncounterKey, currentAttribKey, name)
        playersInput:SetText("")
        Refresh()
        playersInput:SetFocus()  -- ready for the next entry
    end

    addPlayerBtn:SetScript("OnClick", CommitTypedPlayer)
    playersInput:SetScript("OnEnterPressed", CommitTypedPlayer)
    playersInput:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    editPanel.playersInput = playersInput

    -- ---------------- Note section ----------------
    -- Multi-line free-text area for extra detail on the attribution
    -- (tactics, callouts, timings, etc). Built as a scrollable
    -- multi-line EditBox wrapped in a ScrollFrame with a backdrop
    -- frame behind it to give the illusion of a "textarea" control.
    local noteLabel = FS(editPanel, 10)
    noteLabel:SetPoint("TOPLEFT", 10, -316)
    noteLabel:SetText("Note:")
    noteLabel:SetTextColor(unpack(COLOURS.dim))

    local noteBg = MakePanel(editPanel)
    noteBg:SetPoint("TOPLEFT", 16, -332)
    noteBg:SetPoint("TOPRIGHT", -16, -332)
    noteBg:SetHeight(110)

    local noteScroll = CreateFrame("ScrollFrame", "SRANoteScroll", noteBg, "UIPanelScrollFrameTemplate")
    noteScroll:SetPoint("TOPLEFT", 4, -4)
    noteScroll:SetPoint("BOTTOMRIGHT", -24, 4)

    local noteBox = CreateFrame("EditBox", nil, noteScroll)
    noteBox:SetMultiLine(true)
    noteBox:SetAutoFocus(false)
    noteBox:SetFontObject("GameFontHighlightSmall")
    noteBox:SetMaxLetters(1000)
    noteBox:EnableMouse(true)
    -- IMPORTANT: a multi-line EditBox inside a ScrollFrame MUST have a
    -- non-zero explicit size at creation time, otherwise it has no hit
    -- rect and can never receive a click to focus. noteScroll:GetWidth()
    -- still returns 0 here because the frame hierarchy has not been
    -- laid out yet, so we seed sensible defaults and let the
    -- OnSizeChanged / OnShow hooks resize once the real width is known.
    noteBox:SetSize(200, 100)
    -- Enter inserts a newline by default in multi-line mode; only Escape
    -- clears focus. Focus loss commits the edit to the data store.
    noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    noteBox:SetScript("OnEditFocusLost", function(self)
        if NS.Attributions and currentRaidKey and currentEncounterKey and currentAttribKey then
            NS.Attributions:UpdateAttribution(currentRaidKey, currentEncounterKey, currentAttribKey,
                { note = self:GetText() or "" })
            Refresh()
        end
    end)
    -- Keep scroll view centered on the cursor line while typing
    noteBox:SetScript("OnCursorChanged", function(self, _, y, _, cursorHeight)
        local scroll = noteScroll:GetVerticalScroll()
        local height = noteScroll:GetHeight()
        local cursorBottom = -y + cursorHeight
        if -y < scroll then
            noteScroll:SetVerticalScroll(-y)
        elseif cursorBottom > scroll + height then
            noteScroll:SetVerticalScroll(cursorBottom - height)
        end
    end)
    noteScroll:SetScrollChild(noteBox)

    -- Clicking anywhere in the backdrop (not just on an existing line)
    -- focuses the edit box, so you can click in the empty area below
    -- the last typed line rather than having to hit the exact line.
    noteBg:EnableMouse(true)
    noteBg:SetScript("OnMouseDown", function() noteBox:SetFocus() end)

    -- Resize the EditBox width with the scroll frame so lines wrap at
    -- the right edge instead of scrolling horizontally forever.
    local function ResizeNoteBox()
        local w = noteScroll:GetWidth()
        if w and w > 0 then noteBox:SetWidth(w) end
    end
    noteScroll:HookScript("OnSizeChanged", ResizeNoteBox)
    noteScroll:HookScript("OnShow", ResizeNoteBox)

    editPanel.noteBox = noteBox

    -- Delete attribution button
    local delAttribBtn = CreateFrame("Button", nil, editPanel, "UIPanelButtonTemplate")
    delAttribBtn:SetSize(160, 22)
    delAttribBtn:SetPoint("BOTTOMLEFT", 10, 10)
    delAttribBtn:SetText("Delete Attribution")
    delAttribBtn:SetScript("OnClick", function()
        if NS.Attributions and currentRaidKey and currentEncounterKey and currentAttribKey then
            NS.Attributions:DeleteAttribution(currentRaidKey, currentEncounterKey, currentAttribKey)
            currentAttribKey = nil
            Refresh()
        end
    end)

    -- Delete boss button (right side of edit panel)
    local delBossBtn = CreateFrame("Button", nil, editPanel, "UIPanelButtonTemplate")
    delBossBtn:SetSize(100, 22)
    delBossBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    delBossBtn:SetText("Delete Boss")
    delBossBtn:SetScript("OnClick", function()
        if currentEncounterKey then
            local enc = NS.Attributions and NS.Attributions:GetEncounter(currentRaidKey, currentEncounterKey)
            local bossName = enc and enc.name or "?"
            local dialog = StaticPopup_Show("SRA_DELETE_ENCOUNTER", bossName)
            if dialog then dialog.data = currentEncounterKey end
        end
    end)

    view.editPanel = editPanel
    return view
end

----------------------------------------------------------------------
-- Boss picker: dropdown menu of all TBC bosses grouped by instance
----------------------------------------------------------------------

-- Local polyfill for Blizzard's old EasyMenu (removed in modern clients).
-- Replicates the Blizzard implementation: initialize the dropdown with a
-- generator that walks the current level's menuList and emits buttons,
-- then toggle the dropdown open at the requested anchor.
local function ShowEasyMenu(menuList, menuFrame, anchor, x, y, displayMode, autoHideDelay)
    if displayMode == "MENU" then
        menuFrame.displayMode = displayMode
    end
    UIDropDownMenu_Initialize(menuFrame, function(frame, level, currentList)
        if not currentList then return end
        for index = 1, #currentList do
            local value = currentList[index]
            if value.text then
                value.index = index
                UIDropDownMenu_AddButton(value, level)
            end
        end
    end, displayMode, nil, menuList)
    ToggleDropDownMenu(1, nil, menuFrame, anchor, x, y, menuList, nil, autoHideDelay)
end

-- Persistent frame (re-using the same anchor avoids leaking a Frame on
-- every click and also keeps the dropdown state consistent)
local bossPickerFrame

function UI:OpenBossPicker()
    if not NS.TBCBosses or not currentRaidKey then return end

    local menu = {}
    for _, inst in ipairs(NS.TBCBosses.Instances) do
        local submenu = {}
        for _, bossName in ipairs(inst.bosses) do
            submenu[#submenu + 1] = {
                text = bossName,
                notCheckable = true,
                func = function()
                    if NS.Attributions then
                        local encKey = NS.Attributions:AddEncounter(currentRaidKey, bossName)
                        currentEncounterKey = encKey
                        currentAttribKey = nil
                        Refresh()
                    end
                end,
            }
        end
        menu[#menu + 1] = {
            text = inst.name,
            notCheckable = true,
            hasArrow = true,
            menuList = submenu,
        }
    end

    if not bossPickerFrame then
        bossPickerFrame = CreateFrame("Frame", "SRABossPickerMenu", UIParent, "UIDropDownMenuTemplate")
    end
    ShowEasyMenu(menu, bossPickerFrame, "cursor", 0, 0, "MENU")
end

----------------------------------------------------------------------
-- Player picker: dropdown listing the current raid / party members.
-- Clicking a name appends it to the currently selected attribution.
-- The menu is rebuilt on every open so it always reflects the live
-- roster (joins, leaves, disconnects...).
----------------------------------------------------------------------
local playerPickerFrame

function UI:OpenPlayerPicker()
    if not currentRaidKey or not currentEncounterKey or not currentAttribKey then
        NS:Print("Select an attribution first.")
        return
    end
    if not NS.Roster or not NS.Attributions then return end

    -- Re-scan just in case the group changed recently
    NS.Roster:Scan()

    local menu = {}

    -- Header
    menu[#menu + 1] = {
        text = "Group members",
        isTitle = true,
        notCheckable = true,
    }

    -- Already-assigned set so we can strike out or hide duplicates
    local assigned = {}
    local attrib = NS.Attributions:GetAttribution(currentRaidKey, currentEncounterKey, currentAttribKey)
    if attrib and attrib.players then
        for _, n in ipairs(attrib.players) do assigned[n] = true end
    end

    local count = 0
    for name, member in NS.Roster:Iterate() do
        count = count + 1
        local display = name
        if NS.Data and member.classFile then
            local r, g, b = NS.Data:GetClassColor(member.classFile)
            display = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name)
        end
        if assigned[name] then
            display = display .. "  |cff888888(already assigned)|r"
        end
        menu[#menu + 1] = {
            text         = display,
            notCheckable = true,
            disabled     = assigned[name] or nil,
            func         = function()
                if NS.Attributions then
                    NS.Attributions:AddPlayer(currentRaidKey, currentEncounterKey, currentAttribKey, name)
                    Refresh()
                end
            end,
        }
    end

    if count == 0 then
        menu[#menu + 1] = {
            text = "|cff888888(no group members)|r",
            notCheckable = true,
            disabled = true,
        }
    end

    if not playerPickerFrame then
        playerPickerFrame = CreateFrame("Frame", "SRAPlayerPickerMenu", UIParent, "UIDropDownMenuTemplate")
    end
    ShowEasyMenu(menu, playerPickerFrame, "cursor", 0, 0, "MENU")
end

----------------------------------------------------------------------
-- Import / Export dialog
--
-- Single reusable dialog frame with a multi-line text area inside a
-- ScrollFrame, plus a single-line "New name" input that is only
-- displayed in import mode. Switching mode is done by ShowExportDialog
-- and ShowImportDialog which reconfigure labels, button text and the
-- visibility of the name input.
----------------------------------------------------------------------
local importExportDialog
local IE_MODE_EXPORT = "export"
local IE_MODE_IMPORT = "import"

local function BuildImportExportDialog()
    local f = CreateFrame("Frame", "SimpleRaidAssignImportExport", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(520, 380)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER")
    f:Hide()
    SkinFrame(f)

    local title = FS(f, 14)
    title:SetPoint("TOP", 0, -10)
    title:SetTextColor(unpack(COLOURS.accent))
    f.title = title

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local label = FS(f, 10)
    label:SetPoint("TOPLEFT", 14, -32)
    label:SetPoint("TOPRIGHT", -14, -32)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    label:SetTextColor(unpack(COLOURS.dim))
    f.label = label

    -- Multi-line text area (paste / read zone)
    local textBg = MakePanel(f)
    textBg:SetPoint("TOPLEFT", 14, -56)
    textBg:SetPoint("TOPRIGHT", -14, -56)
    textBg:SetHeight(220)

    local textScroll = CreateFrame("ScrollFrame", nil, textBg, "UIPanelScrollFrameTemplate")
    textScroll:SetPoint("TOPLEFT", 4, -4)
    textScroll:SetPoint("BOTTOMRIGHT", -24, 4)

    local textBox = CreateFrame("EditBox", nil, textScroll)
    textBox:SetMultiLine(true)
    textBox:SetAutoFocus(false)
    textBox:SetFontObject("ChatFontSmall")
    textBox:EnableMouse(true)
    textBox:SetMaxLetters(0)         -- 0 means no limit
    textBox:SetMaxBytes(0)
    textBox:SetSize(440, 200)        -- non-zero seed so the hit rect exists
    textBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    textScroll:SetScrollChild(textBox)
    AutoSizeScrollChild(textScroll, textBox)

    -- Click anywhere in the backdrop focuses the editbox
    textBg:EnableMouse(true)
    textBg:SetScript("OnMouseDown", function() textBox:SetFocus() end)

    f.textBox   = textBox
    f.textBg    = textBg

    -- "New name" input (only visible in import mode)
    local nameLabel = FS(f, 10)
    nameLabel:SetPoint("TOPLEFT", 14, -284)
    nameLabel:SetText("New raid name:")
    nameLabel:SetTextColor(unpack(COLOURS.dim))
    f.nameLabel = nameLabel

    local nameInput = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    nameInput:SetSize(360, 22)
    nameInput:SetPoint("TOPLEFT", 22, -300)
    nameInput:SetAutoFocus(false)
    nameInput:SetMaxLetters(64)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.nameInput = nameInput

    -- Action bar at the bottom
    local primaryBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    primaryBtn:SetSize(120, 24)
    primaryBtn:SetPoint("BOTTOMLEFT", 14, 14)
    f.primaryBtn = primaryBtn

    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 24)
    cancelBtn:SetPoint("BOTTOMRIGHT", -14, 14)
    cancelBtn:SetText("Close")
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    f:SetScript("OnHide", function()
        textBox:ClearFocus()
        nameInput:ClearFocus()
    end)

    return f
end

local function ConfigureImportExportDialog(mode)
    if not importExportDialog then importExportDialog = BuildImportExportDialog() end
    local d = importExportDialog
    if mode == IE_MODE_EXPORT then
        -- Hide the name input row in export mode
        d.nameLabel:Hide()
        d.nameInput:Hide()
    else
        d.nameLabel:Show()
        d.nameInput:Show()
    end
    return d
end

function UI:ShowExportDialog(raidKey)
    if not NS.Raids then return end
    local raid = NS.Raids:Get(raidKey)
    if not raid then return end

    local exported = NS.Raids:Export(raidKey)
    if not exported then
        NS:Print("Export failed.")
        return
    end

    local d = ConfigureImportExportDialog(IE_MODE_EXPORT)
    d.title:SetText("Export raid: " .. (raid.name or "?"))
    d.label:SetText("Copy this string and share it. Click in the box, press Ctrl+A then Ctrl+C.")
    d.textBox:SetText(exported)
    d.textBox:SetCursorPosition(0)
    d.textBox:HighlightText()
    d.textBox:SetFocus()

    d.primaryBtn:SetText("Select All")
    d.primaryBtn:SetScript("OnClick", function()
        d.textBox:SetFocus()
        d.textBox:HighlightText()
    end)

    d:Show()
end

function UI:ShowImportDialog()
    local d = ConfigureImportExportDialog(IE_MODE_IMPORT)
    d.title:SetText("Import raid")
    d.label:SetText("Paste an exported raid string here and choose a name for the new raid.")
    d.textBox:SetText("")
    d.nameInput:SetText("")
    d.textBox:SetFocus()

    -- When the user has finished pasting (defocus the text box), try
    -- to peek at the original raid name and pre-fill the name input
    -- as a sensible default they can override.
    d.textBox:SetScript("OnEditFocusLost", function(self)
        if not d.nameInput:GetText() or d.nameInput:GetText() == "" then
            local guess = NS.Raids and NS.Raids:PeekImportName(self:GetText() or "")
            if guess and guess ~= "" then
                d.nameInput:SetText(guess .. " (imported)")
            end
        end
    end)

    d.primaryBtn:SetText("Import")
    d.primaryBtn:SetScript("OnClick", function()
        if not NS.Raids then return end
        local text = d.textBox:GetText() or ""
        local newName = d.nameInput:GetText() or ""
        local key, err = NS.Raids:Import(text, newName)
        if key then
            NS:Print("Raid imported as |cffffff00" .. (newName ~= "" and newName or "(default)") .. "|r")
            d:Hide()
            currentRaidKey = key
            currentEncounterKey = nil
            currentAttribKey = nil
            ShowEditor()
        else
            NS:Print("|cffff5555Import failed:|r " .. (err or "unknown error"))
        end
    end)

    d:Show()
end

----------------------------------------------------------------------
-- Boss row (sidebar)
----------------------------------------------------------------------
local function BuildBossRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(26)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0)

    -- Attrib counter on the right (built first so the title can cap
    -- its RIGHT anchor to it and avoid overlap / wrapping).
    row.sub = FS(row, 9)
    row.sub:SetPoint("RIGHT", -6, 0)
    row.sub:SetJustifyH("RIGHT")
    row.sub:SetWordWrap(false)
    row.sub:SetTextColor(unpack(COLOURS.dim))

    row.title = FS(row, 12)
    row.title:SetPoint("LEFT", 8, 0)
    row.title:SetPoint("RIGHT", row.sub, "LEFT", -6, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    return row
end

local function RefreshBossList()
    local panel = editorView and editorView.bossPanel
    if not panel then return end

    for _, row in ipairs(panel.rows) do row:Hide() end

    if not currentRaidKey or not NS.Attributions then return end

    local y = 0
    local i = 0
    for encKey, enc in NS.Attributions:IterateEncounters(currentRaidKey) do
        i = i + 1
        local row = panel.rows[i]
        if not row then
            row = BuildBossRow(panel.content)
            panel.rows[i] = row
        end
        row.title:SetText(enc.name or "?")
        local nAttribs = 0
        for _ in pairs(enc.attributions or {}) do nAttribs = nAttribs + 1 end
        row.sub:SetText(string.format("%d attrib.", nAttribs))

        row:SetScript("OnClick", function()
            CommitPendingEdits()
            currentEncounterKey = encKey
            currentAttribKey = nil
            if NS.db then NS.db.settings.lastEncounter = encKey end
            Refresh()
        end)

        if currentEncounterKey == encKey then
            row.bg:SetColorTexture(unpack(COLOURS.rowActive))
        else
            row.bg:SetColorTexture(1, 1, 1, 0)
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", panel.content, "TOPRIGHT", 0, -y)
        row:Show()
        y = y + 30
    end
    panel.content:SetHeight(math.max(1, y))
end

----------------------------------------------------------------------
-- Attribution row (middle column)
----------------------------------------------------------------------
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
    row.kind = "header"

    -- Chevron toggle
    row.chevron = CreateFrame("Button", nil, row)
    row.chevron:SetSize(16, 16)
    row.chevron:SetPoint("LEFT", 4, 0)
    row.chevron.label = FS(row.chevron, 12)
    row.chevron.label:SetAllPoints()
    row.chevron.label:SetJustifyH("CENTER")
    row.chevron.label:SetText("v")

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

    -- Right-aligned button cluster
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

local function BuildAttribRow(parent)
    local row = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    SkinFrame(row)
    row:SetHeight(48)

    -- "Include in announce" checkbox on the far left.
    row.selectCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.selectCheck:SetSize(20, 20)
    row.selectCheck:SetPoint("LEFT", 4, 0)

    row.markerIcon = row:CreateTexture(nil, "ARTWORK")
    row.markerIcon:SetSize(22, 22)
    row.markerIcon:SetPoint("LEFT", 30, 0)

    row.context = FS(row, 12)
    row.context:SetPoint("TOPLEFT", 56, -6)
    row.context:SetPoint("TOPRIGHT", -6, -6)
    row.context:SetJustifyH("LEFT")
    row.context:SetWordWrap(false)

    row.players = FS(row, 10)
    row.players:SetPoint("BOTTOMLEFT", 56, 6)
    row.players:SetPoint("BOTTOMRIGHT", -6, 6)
    row.players:SetJustifyH("LEFT")
    row.players:SetWordWrap(false)
    return row
end

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

local function RefreshAttribList()
    local panel = editorView and editorView.attribPanel
    if not panel then return end

    for _, row in ipairs(panel.rows)       do row:Hide() end
    for _, row in ipairs(panel.headerRows) do row:Hide() end

    if not currentRaidKey or not currentEncounterKey then
        panel.header:SetText("Attributions")
        if panel.masterCheck then panel.masterCheck:SetChecked(false) end
        return
    end

    local enc = NS.Attributions and NS.Attributions:GetEncounter(currentRaidKey, currentEncounterKey)
    if not enc then
        panel.header:SetText("Attributions")
        if panel.masterCheck then panel.masterCheck:SetChecked(false) end
        return
    end

    panel.header:SetText("Attributions - " .. (enc.name or "?"))

    local uncatIds, buckets = BucketAttribsByCategory(currentRaidKey, currentEncounterKey)

    local y = 0
    local attribIdx, headerIdx = 0, 0

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

        row.upBtn:Hide()
        row.downBtn:Hide()
        row.renameBtn:Hide()
        row.deleteBtn:Hide()
        row.addAttribBtn:Hide()

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
        renderHeaderRow(nil, "- Uncategorized -", true)
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
end

----------------------------------------------------------------------
-- Edit panel (right column)
----------------------------------------------------------------------
-- Only write into an EditBox if the user isn't currently typing in it;
-- otherwise we'd wipe their in-progress input whenever a background
-- event (ROSTER_UPDATED, DATA_UPDATED...) triggers a Refresh.
-- (Forward-declared at the top of the file so earlier builders can
-- reference it through closures.)
SafeSetText = function(editBox, text)
    if not editBox then return end
    if editBox.HasFocus and editBox:HasFocus() then return end
    editBox:SetText(text or "")
end

-- Force-commit any in-progress edit in the right-panel EditBoxes.
-- Call this BEFORE changing currentAttribKey / currentEncounterKey so
-- the focus-loss handlers run against the old ids and save their
-- pending text to the correct attribution.
CommitPendingEdits = function()
    if not editorView or not editorView.editPanel then return end
    local panel = editorView.editPanel
    if panel.contextBox and panel.contextBox:HasFocus() then
        panel.contextBox:ClearFocus()
    end
    if panel.noteBox and panel.noteBox:HasFocus() then
        panel.noteBox:ClearFocus()
    end
    -- The players input is a "draft" field: anything still typed in
    -- it has not been added yet. We do NOT auto-commit it here so the
    -- user can decide whether to actually press Add. We just clear
    -- the focus to keep the cursor state clean.
    if panel.playersInput and panel.playersInput:HasFocus() then
        panel.playersInput:ClearFocus()
    end
end

----------------------------------------------------------------------
-- Build a single row in the players list (name + remove button).
-- Reused across refreshes via panel.playerRows.
----------------------------------------------------------------------
local function BuildPlayerRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)

    row.removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.removeBtn:SetSize(20, 18)
    row.removeBtn:SetPoint("RIGHT", -2, 0)
    row.removeBtn:SetText("X")

    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetFont(GetFont(), 12, "OUTLINE")
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetPoint("RIGHT", row.removeBtn, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    return row
end

local function RefreshPlayersList(panel, attrib)
    if not panel.playersContent then return end

    -- Make sure the scroll child has a real width before we anchor
    -- rows to its TOPLEFT/TOPRIGHT. The AutoSizeScrollChild hook
    -- normally handles this, but it may not have fired yet on the
    -- very first refresh after the window opens, leaving the content
    -- frame at its 1px default and collapsing every row.
    if panel.playersScroll then
        local sw = panel.playersScroll:GetWidth()
        if sw and sw > 0 then
            panel.playersContent:SetWidth(sw)
        end
    end

    -- Hide all reusable rows first
    for _, row in ipairs(panel.playerRows) do row:Hide() end

    if not attrib or not attrib.players or #attrib.players == 0 then
        panel.playersContent:SetHeight(1)
        return
    end

    local y = 0
    for i, name in ipairs(attrib.players) do
        local row = panel.playerRows[i]
        if not row then
            row = BuildPlayerRow(panel.playersContent)
            panel.playerRows[i] = row
        end

        local display = name
        if NS.Data then display = NS.Data:ColorizeName(name) end
        row.name:SetText(display)

        local capturedName = name
        row.removeBtn:SetScript("OnClick", function()
            if NS.Attributions and currentRaidKey and currentEncounterKey and currentAttribKey then
                NS.Attributions:RemovePlayer(currentRaidKey, currentEncounterKey, currentAttribKey, capturedName)
                Refresh()
            end
        end)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.playersContent, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", panel.playersContent, "TOPRIGHT", 0, -y)
        row:Show()
        y = y + 22
    end
    panel.playersContent:SetHeight(math.max(1, y))
end

local function RefreshEditPanel()
    local panel = editorView and editorView.editPanel
    if not panel then return end

    local attrib = nil
    if currentRaidKey and currentEncounterKey and currentAttribKey and NS.Attributions then
        attrib = NS.Attributions:GetAttribution(currentRaidKey, currentEncounterKey, currentAttribKey)
    end

    if not attrib then
        SafeSetText(panel.contextBox, "")
        SafeSetText(panel.noteBox, "")
        SafeSetText(panel.playersInput, "")
        UIDropDownMenu_SetSelectedValue(panel.markerDrop, 0)
        UIDropDownMenu_SetText(panel.markerDrop, "|cff888888(none)|r")
        panel.contextBox:Disable()
        if panel.playersInput then panel.playersInput:Disable() end
        if panel.noteBox then panel.noteBox:Disable() end
        RefreshPlayersList(panel, nil)
        return
    end

    panel.contextBox:Enable()
    if panel.playersInput then panel.playersInput:Enable() end
    if panel.noteBox then panel.noteBox:Enable() end

    SafeSetText(panel.contextBox, attrib.context or "")
    SafeSetText(panel.noteBox, attrib.note or "")
    RefreshPlayersList(panel, attrib)

    if attrib.marker and NS.Data then
        local m = NS.Data:GetMarker(attrib.marker)
        if m then
            UIDropDownMenu_SetSelectedValue(panel.markerDrop, m.id)
            UIDropDownMenu_SetText(panel.markerDrop, "|T" .. m.texture .. ":16|t " .. m.label)
        end
    else
        UIDropDownMenu_SetSelectedValue(panel.markerDrop, 0)
        UIDropDownMenu_SetText(panel.markerDrop, "|cff888888(none)|r")
    end
end

-- ====================================================================
--  MAIN FRAME
-- ====================================================================

local function BuildMainFrame()
    local f = CreateFrame("Frame", "SimpleRaidAssignFrame", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(820, 600)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        if NS.db then
            NS.db.settings.windowPos = { point = point, x = x, y = y }
        end
    end)
    f:SetClampedToScreen(true)
    f:Hide()
    SkinFrame(f)

    local title = FS(f, 15)
    title:SetPoint("TOP", 0, -8)
    title:SetText("SimpleRaidAssign  v" .. (NS.version or "?"))
    title:SetTextColor(unpack(COLOURS.accent))

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() f:Hide() end)

    if NS.db and NS.db.settings.windowPos then
        local p = NS.db.settings.windowPos
        f:ClearAllPoints()
        f:SetPoint(p.point or "CENTER", UIParent, p.point or "CENTER", p.x or 0, p.y or 0)
    else
        f:SetPoint("CENTER")
    end

    -- Content area container
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 0, -26)
    content:SetPoint("BOTTOMRIGHT", 0, 0)

    summaryView = BuildSummaryView(content)
    editorView  = BuildEditorView(content)

    summaryView:Hide()
    editorView:Hide()

    return f
end

-- ====================================================================
--  NAVIGATION & REFRESH
-- ====================================================================

ShowSummary = function()
    if not mainFrame then mainFrame = BuildMainFrame() end
    currentScreen = "summary"
    if editorView then editorView:Hide() end
    if summaryView then summaryView:Show() end
    Refresh()
end

ShowEditor = function()
    if not mainFrame then mainFrame = BuildMainFrame() end
    if not currentRaidKey then
        ShowSummary()
        return
    end
    currentScreen = "editor"
    if summaryView then summaryView:Hide() end
    if editorView then editorView:Show() end

    -- Auto-select the first boss if none is selected
    if not currentEncounterKey and NS.Attributions then
        for encKey in NS.Attributions:IterateEncounters(currentRaidKey) do
            currentEncounterKey = encKey
            break
        end
    end
    -- Auto-select the first attribution if none is selected
    if currentEncounterKey and not currentAttribKey and NS.Attributions then
        for attribId in NS.Attributions:IterateAttributions(currentRaidKey, currentEncounterKey) do
            currentAttribKey = attribId
            break
        end
    end

    if NS.db then
        NS.db.settings.lastRaid = currentRaidKey
        NS.db.settings.lastEncounter = currentEncounterKey
    end

    Refresh()
end

Refresh = function()
    if not mainFrame then return end
    if currentScreen == "summary" then
        RefreshSummary()
    elseif currentScreen == "editor" then
        if editorView and editorView.title then
            local raid = NS.Raids and NS.Raids:Get(currentRaidKey)
            editorView.title:SetText(raid and raid.name or "?")
        end
        RefreshBossList()
        RefreshAttribList()
        RefreshEditPanel()
    end
end

function UI:Toggle()
    if not mainFrame then mainFrame = BuildMainFrame() end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        -- Restore last state: if a raid was selected, open its editor;
        -- otherwise show the summary.
        if NS.db and NS.db.settings.lastRaid and NS.Raids and NS.Raids:Exists(NS.db.settings.lastRaid) then
            currentRaidKey = NS.db.settings.lastRaid
            currentEncounterKey = NS.db.settings.lastEncounter
            ShowEditor()
        else
            ShowSummary()
        end
    end
end

function UI:Hide()
    if mainFrame then mainFrame:Hide() end
end


-- ====================================================================
--  MINIMAP BUTTON
-- ====================================================================
-- A draggable button on the minimap edge with the Grey Skull raid
-- target icon. Left-click toggles the main window; left-drag moves
-- the button around the minimap's circumference. The angle is
-- persisted in NS.db.settings.minimapPos.
----------------------------------------------------------------------

local minimapButton

local function CreateMinimapButton()
    if minimapButton then return minimapButton end
    if not Minimap then return end

    local btn = CreateFrame("Button", "SimpleRaidAssignMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)

    -- Circular tracking border (matches other minimap buttons)
    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    -- Skull icon (raid target 8, matches the addon's marker theme)
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    btn.icon = icon

    -- Hover glow
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(24, 24)
    highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    -- Position on minimap edge based on the persisted angle
    local function UpdatePosition()
        local angle = math.rad(NS.db and NS.db.settings.minimapPos or 215)
        local x = math.cos(angle) * 80
        local y = math.sin(angle) * 80
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    UpdatePosition()

    -- Dragging: follow cursor around the minimap edge
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            if NS.db then NS.db.settings.minimapPos = angle end
            local rad = math.rad(angle)
            self:ClearAllPoints()
            self:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * 80, math.sin(rad) * 80)
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- Left-click toggles the main window
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            UI:Toggle()
        elseif button == "RightButton" then
            -- Quick access to the raid sync for raid leaders
            NS:FireCallback("SYNC_PUSH_REQUEST")
        end
    end)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("SimpleRaidAssign", 1, 1, 1)
        GameTooltip:AddLine("Raid role assignments by boss.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ccffLeft-click|r: toggle window", 1, 1, 1)
        GameTooltip:AddLine("|cff00ccffRight-click|r: push all raids to group", 1, 1, 1)
        GameTooltip:AddLine("|cff00ccffDrag|r: reposition around minimap", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    minimapButton = btn
    return btn
end

function UI:ShowMinimapButton()
    if not minimapButton then CreateMinimapButton() end
    if minimapButton then minimapButton:Show() end
end

function UI:HideMinimapButton()
    if minimapButton then minimapButton:Hide() end
end

-- ====================================================================
--  EVENT BUS WIRING
-- ====================================================================

NS:RegisterCallback("ADDON_LOADED", function()
    -- DB is ready at this point; create the minimap button so its
    -- position restore works on the very first login.
    CreateMinimapButton()
end)

NS:RegisterCallback("TOGGLE_WINDOW", function() UI:Toggle() end)
NS:RegisterCallback("HIDE_WINDOW",   function() UI:Hide() end)
NS:RegisterCallback("DATA_UPDATED",  function()
    if mainFrame and mainFrame:IsShown() then Refresh() end
end)
NS:RegisterCallback("ROSTER_UPDATED", function()
    if mainFrame and mainFrame:IsShown() then Refresh() end
end)
