----------------------------------------------------------------------
-- SimpleRaidAssign  -  AssignData.lua
-- Static reference data: class colors + 8 raid target marker icons.
----------------------------------------------------------------------
local _, NS = ...

local Data = {}
NS.Data = Data

----------------------------------------------------------------------
-- 8 raid target marker icons (Blizzard indices 1..8)
-- Order matches the in-game marker menu.
----------------------------------------------------------------------
Data.MarkerIcons = {
    { id = 1, key = "star",     label = "Yellow Star",    token = "{rt1}", texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", color = { 1.00, 0.92, 0.20 } },
    { id = 2, key = "circle",   label = "Orange Circle",  token = "{rt2}", texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2", color = { 1.00, 0.50, 0.15 } },
    { id = 3, key = "diamond",  label = "Purple Diamond", token = "{rt3}", texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3", color = { 0.80, 0.40, 1.00 } },
    { id = 4, key = "triangle", label = "Green Triangle", token = "{rt4}", texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4", color = { 0.30, 0.90, 0.30 } },
    { id = 5, key = "moon",     label = "White Moon",     token = "{rt5}", texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5", color = { 0.95, 0.95, 0.95 } },
    { id = 6, key = "square",   label = "Blue Square",    token = "{rt6}", texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", color = { 0.20, 0.55, 1.00 } },
    { id = 7, key = "cross",    label = "Red Cross",      token = "{rt7}", texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", color = { 0.95, 0.20, 0.20 } },
    { id = 8, key = "skull",    label = "Grey Skull",     token = "{rt8}", texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", color = { 0.85, 0.85, 0.85 } },
}

-- Index by id for fast lookup
Data.MarkerIndex = {}
for _, m in ipairs(Data.MarkerIcons) do
    Data.MarkerIndex[m.id] = m
end

function Data:GetMarker(id)
    if not id then return nil end
    return self.MarkerIndex[id]
end

function Data:IterateMarkers()
    local i = 0
    return function()
        i = i + 1
        return self.MarkerIcons[i]
    end
end

----------------------------------------------------------------------
-- Class colors (TBC client constants, with live fallback)
----------------------------------------------------------------------
Data.ClassColors = {
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    DRUID       = { 1.00, 0.49, 0.04 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    MAGE        = { 0.41, 0.80, 0.94 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    PRIEST      = { 1.00, 1.00, 1.00 },
    ROGUE       = { 1.00, 0.96, 0.41 },
    SHAMAN      = { 0.00, 0.44, 0.87 },
    WARLOCK     = { 0.58, 0.51, 0.79 },
    WARRIOR     = { 0.78, 0.61, 0.43 },
}

function Data:GetClassColor(classFile)
    if not classFile then return 0.7, 0.7, 0.7 end
    local rcc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if rcc then return rcc.r, rcc.g, rcc.b end
    local c = self.ClassColors[classFile]
    if c then return c[1], c[2], c[3] end
    return 0.7, 0.7, 0.7
end

function Data:ColorizeName(name)
    if not name or name == "" then return name or "" end
    local m = NS.Roster and NS.Roster:GetMember(name)
    if m and m.classFile then
        local r, g, b = self:GetClassColor(m.classFile)
        return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name)
    end
    return name
end
