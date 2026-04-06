----------------------------------------------------------------------
-- WowShiftAssign  -  UI.lua
-- Main window with encounter list + role editor.
-- Minimal but ElvUI-compatible dark theme.
----------------------------------------------------------------------
local _, NS = ...

local UI = {}
NS.UI = UI

----------------------------------------------------------------------
-- Style
----------------------------------------------------------------------
local COLOURS = {
    bg       = { 0.08, 0.08, 0.10, 0.94 },
    panel    = { 0.12, 0.12, 0.14, 0.95 },
    border   = { 0.30, 0.30, 0.34, 1    },
    accent   = { 0.00, 0.80, 1.00, 1    },
    accent2  = { 1.00, 0.65, 0.20, 1    },
    text     = { 1, 1, 1, 1 },
    dim      = { 0.65, 0.65, 0.70, 1 },
    rowAlt   = { 1, 1, 1, 0.04 },
    rowHover = { 1, 1, 1, 0.10 },
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

----------------------------------------------------------------------
-- Forward declarations
----------------------------------------------------------------------
local mainFrame
local encounterList, roleEditor
local currentEncounterKey

local Refresh -- forward declared so children can call it

----------------------------------------------------------------------
-- Build a generic backdropped panel
----------------------------------------------------------------------
local function MakePanel(parent)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    SkinFrame(f)
    return f
end

----------------------------------------------------------------------
-- Encounter list (left column)
----------------------------------------------------------------------
local function BuildEncounterList(parent)
    local panel = MakePanel(parent)
    panel:SetPoint("TOPLEFT", 8, -36)
    panel:SetPoint("BOTTOMLEFT", 8, 40)
    panel:SetWidth(200)

    local title = FS(panel, 13)
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Encounters")
    title:SetTextColor(unpack(COLOURS.accent))

    -- New encounter button
    local newBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    newBtn:SetSize(86, 22)
    newBtn:SetPoint("TOPRIGHT", -8, -6)
    newBtn:SetText("+ New")
    newBtn:SetScript("OnClick", function()
        if not NS.Assignments then return end
        local key = NS.Assignments:CreateEncounter("New Encounter", "", "blank")
        currentEncounterKey = key
        Refresh()
    end)

    -- Scrollframe with rows
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -32)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    panel.scroll  = scroll
    panel.content = content
    panel.rows    = {}
    return panel
end

local function RefreshEncounterList()
    local panel = encounterList
    if not panel then return end

    -- Hide existing rows
    for _, row in ipairs(panel.rows) do row:Hide() end

    if not NS.Assignments then return end

    local y = 0
    local i = 0
    for key, enc in NS.Assignments:IterateEncounters() do
        i = i + 1
        local row = panel.rows[i]
        if not row then
            row = CreateFrame("Button", nil, panel.content)
            row:SetHeight(28)
            row:SetPoint("LEFT", 0, 0)
            row:SetPoint("RIGHT", 0, 0)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.bg:SetColorTexture(1, 1, 1, 0)
            row.title = FS(row, 12)
            row.title:SetPoint("TOPLEFT", 6, -4)
            row.sub   = FS(row, 10)
            row.sub:SetPoint("BOTTOMLEFT", 6, 4)
            row.sub:SetTextColor(unpack(COLOURS.dim))
            row:SetScript("OnEnter", function(self) self.bg:SetColorTexture(unpack(COLOURS.rowHover)) end)
            row:SetScript("OnLeave", function(self)
                if currentEncounterKey == self.key then
                    self.bg:SetColorTexture(unpack(COLOURS.rowAlt))
                else
                    self.bg:SetColorTexture(1, 1, 1, 0)
                end
            end)
            panel.rows[i] = row
        end

        row.key = key
        row.title:SetText(enc.name or "?")
        row.sub:SetText(enc.instance or "")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", panel.content, "TOPRIGHT", 0, -y)
        row:SetScript("OnClick", function(self)
            currentEncounterKey = self.key
            Refresh()
        end)
        if currentEncounterKey == key then
            row.bg:SetColorTexture(unpack(COLOURS.rowAlt))
        else
            row.bg:SetColorTexture(1, 1, 1, 0)
        end
        row:Show()
        y = y + 30
    end

    panel.content:SetHeight(math.max(1, y))
end

----------------------------------------------------------------------
-- Role editor (right column)
----------------------------------------------------------------------
local function BuildRoleEditor(parent)
    local panel = MakePanel(parent)
    panel:SetPoint("TOPLEFT", encounterList, "TOPRIGHT", 8, 0)
    panel:SetPoint("BOTTOMRIGHT", -8, 40)

    local header = FS(panel, 14)
    header:SetPoint("TOPLEFT", 10, -10)
    header:SetText("No encounter selected")
    header:SetTextColor(unpack(COLOURS.accent))
    panel.header = header

    local sub = FS(panel, 11)
    sub:SetPoint("TOPLEFT", 10, -28)
    sub:SetTextColor(unpack(COLOURS.dim))
    panel.sub = sub

    -- Add-role dropdown (simple cycle-button to keep code small)
    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetSize(120, 22)
    addBtn:SetPoint("TOPRIGHT", -10, -8)
    addBtn:SetText("+ Add Role")
    addBtn:SetScript("OnClick", function()
        if not currentEncounterKey or not NS.Assignments then return end
        -- Open a tiny menu of role types
        local menu = {}
        for _, t in ipairs(NS.Data.RoleTypes) do
            menu[#menu + 1] = {
                text = t.label,
                func = function()
                    NS.Assignments:AddRole(currentEncounterKey, t.key, t.label)
                    Refresh()
                end,
                notCheckable = true,
            }
        end
        EasyMenu(menu, CreateFrame("Frame", "WSAAddRoleMenu", UIParent, "UIDropDownMenuTemplate"),
                 "cursor", 0, 0, "MENU")
    end)

    -- Scroll list of roles
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -52)
    scroll:SetPoint("BOTTOMRIGHT", -26, 8)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    panel.scroll  = scroll
    panel.content = content
    panel.roleRows = {}
    return panel
end

local function BuildRoleRow(parent)
    local row = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    SkinFrame(row)
    row:SetHeight(56)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(36, 36)
    row.icon:SetPoint("LEFT", 8, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.label = FS(row, 13)
    row.label:SetPoint("TOPLEFT", 52, -8)

    row.slots = FS(row, 11)
    row.slots:SetPoint("BOTTOMLEFT", 52, 8)
    row.slots:SetTextColor(unpack(COLOURS.dim))

    -- Action buttons (right side): assign me, clear, delete
    row.assignMe = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.assignMe:SetSize(70, 20)
    row.assignMe:SetPoint("RIGHT", -8, 10)
    row.assignMe:SetText("Assign Me")

    row.clear = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.clear:SetSize(56, 20)
    row.clear:SetPoint("RIGHT", row.assignMe, "LEFT", -4, 0)
    row.clear:SetText("Clear")

    row.del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.del:SetSize(20, 20)
    row.del:SetPoint("RIGHT", -8, -10)
    row.del:SetText("X")
    return row
end

local function RefreshRoleEditor()
    local panel = roleEditor
    if not panel then return end

    for _, row in ipairs(panel.roleRows) do row:Hide() end

    if not NS.Assignments or not currentEncounterKey then
        panel.header:SetText("No encounter selected")
        panel.sub:SetText("Click + New on the left, or pick an existing one.")
        return
    end

    local enc = NS.Assignments:GetEncounter(currentEncounterKey)
    if not enc then
        panel.header:SetText("No encounter selected")
        panel.sub:SetText("")
        return
    end

    panel.header:SetText(enc.name or "?")
    panel.sub:SetText((enc.instance or "") .. "  -  last edit: " .. (enc.updatedBy or "?"))

    local y = 0
    for i, roleKey in ipairs(enc.order) do
        local role = enc.roles[roleKey]
        if role then
            local row = panel.roleRows[i]
            if not row then
                row = BuildRoleRow(panel.content)
                panel.roleRows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", panel.content, "TOPRIGHT", 0, -y)

            local typeEntry = NS.Data:GetRoleType(role.roleType)
            row.icon:SetTexture(typeEntry.icon)
            row.label:SetText(role.label or typeEntry.label)
            row.label:SetTextColor(typeEntry.color[1], typeEntry.color[2], typeEntry.color[3])

            local slotsText
            if #role.slots == 0 then
                slotsText = "|cff888888(unassigned)|r"
            else
                local parts = {}
                for _, name in ipairs(role.slots) do
                    local m = NS.Roster and NS.Roster:GetMember(name)
                    if m then
                        local r, g, b = NS.Data:GetClassColor(m.classFile)
                        parts[#parts + 1] = string.format("|cff%02x%02x%02x%s|r",
                            r * 255, g * 255, b * 255, name)
                    else
                        parts[#parts + 1] = name
                    end
                end
                slotsText = table.concat(parts, ", ")
            end
            row.slots:SetText(slotsText)

            -- Capture role key for handlers
            row.assignMe:SetScript("OnClick", function()
                NS.Assignments:AssignPlayer(currentEncounterKey, roleKey, UnitName("player"))
                Refresh()
            end)
            row.clear:SetScript("OnClick", function()
                NS.Assignments:ClearRole(currentEncounterKey, roleKey)
                Refresh()
            end)
            row.del:SetScript("OnClick", function()
                NS.Assignments:RemoveRole(currentEncounterKey, roleKey)
                Refresh()
            end)
            row:Show()
            y = y + 60
        end
    end
    panel.content:SetHeight(math.max(1, y))
end

----------------------------------------------------------------------
-- Bottom action bar
----------------------------------------------------------------------
local function BuildActionBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("BOTTOMLEFT", 8, 8)
    bar:SetPoint("BOTTOMRIGHT", -8, 8)
    bar:SetHeight(28)

    local push = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    push:SetSize(110, 22)
    push:SetPoint("LEFT", 0, 0)
    push:SetText("Push to Raid")
    push:SetScript("OnClick", function() NS:FireCallback("SYNC_PUSH_REQUEST") end)

    local pull = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    pull:SetSize(110, 22)
    pull:SetPoint("LEFT", push, "RIGHT", 6, 0)
    pull:SetText("Request Sync")
    pull:SetScript("OnClick", function() NS:FireCallback("SYNC_PULL_REQUEST") end)

    local del = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    del:SetSize(120, 22)
    del:SetPoint("RIGHT", 0, 0)
    del:SetText("Delete Encounter")
    del:SetScript("OnClick", function()
        if currentEncounterKey and NS.Assignments then
            NS.Assignments:DeleteEncounter(currentEncounterKey)
            currentEncounterKey = nil
            Refresh()
        end
    end)
    return bar
end

----------------------------------------------------------------------
-- Main window
----------------------------------------------------------------------
local function BuildMainFrame()
    local f = CreateFrame("Frame", "WowShiftAssignFrame", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(720, 460)
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

    -- Title bar
    local title = FS(f, 15)
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("WowShiftAssign")
    title:SetTextColor(unpack(COLOURS.accent))

    local version = FS(f, 10)
    version:SetPoint("LEFT", title, "RIGHT", 6, 0)
    version:SetText("v" .. (NS.version or "?"))
    version:SetTextColor(unpack(COLOURS.dim))

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Restore position
    if NS.db and NS.db.settings.windowPos then
        local p = NS.db.settings.windowPos
        f:ClearAllPoints()
        f:SetPoint(p.point or "CENTER", UIParent, p.point or "CENTER", p.x or 0, p.y or 0)
    else
        f:SetPoint("CENTER")
    end

    encounterList = BuildEncounterList(f)
    roleEditor    = BuildRoleEditor(f)
    BuildActionBar(f)

    return f
end

----------------------------------------------------------------------
-- Refresh dispatcher
----------------------------------------------------------------------
Refresh = function()
    if not mainFrame then return end
    -- Pick the most recent encounter if none is selected
    if not currentEncounterKey and NS.db and NS.db.encounters then
        currentEncounterKey = NS.db.settings.lastEncounter
        if not currentEncounterKey then
            for k in pairs(NS.db.encounters) do currentEncounterKey = k; break end
        end
    end
    if currentEncounterKey and NS.db then
        NS.db.settings.lastEncounter = currentEncounterKey
    end
    RefreshEncounterList()
    RefreshRoleEditor()
end

function UI:Toggle()
    if not mainFrame then mainFrame = BuildMainFrame() end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        Refresh()
    end
end

function UI:Hide()
    if mainFrame then mainFrame:Hide() end
end

----------------------------------------------------------------------
-- Wire up to event bus
----------------------------------------------------------------------
NS:RegisterCallback("ADDON_LOADED", function()
    -- Lazy: build on first toggle
end)

NS:RegisterCallback("TOGGLE_WINDOW", function() UI:Toggle() end)
NS:RegisterCallback("HIDE_WINDOW",   function() UI:Hide() end)
NS:RegisterCallback("DATA_UPDATED",  function()
    if mainFrame and mainFrame:IsShown() then Refresh() end
end)
NS:RegisterCallback("ROSTER_UPDATED", function()
    if mainFrame and mainFrame:IsShown() then Refresh() end
end)
