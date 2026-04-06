----------------------------------------------------------------------
-- WowShiftAssign  -  Roster.lua
-- Discovers raid/party composition (name, class, role hint, online state)
-- Fires ROSTER_UPDATED whenever the group changes.
----------------------------------------------------------------------
local _, NS = ...

local Roster = {}
NS.Roster = Roster

----------------------------------------------------------------------
-- API compatibility (TBC + later)
----------------------------------------------------------------------
local IsInRaidFn  = IsInRaid       or function() return GetNumRaidMembers and GetNumRaidMembers() > 0 end
local IsInGroupFn = IsInGroup      or function() return (GetNumPartyMembers and GetNumPartyMembers() > 0) or IsInRaidFn() end
local GetNumGroup = GetNumGroupMembers or function()
    local n = (GetNumRaidMembers and GetNumRaidMembers() or 0)
    if n > 0 then return n end
    return (GetNumPartyMembers and GetNumPartyMembers() or 0) + 1 -- + player
end

----------------------------------------------------------------------
-- Internal state
----------------------------------------------------------------------
-- members[name] = {
--     name        = "Playername",
--     classFile   = "WARRIOR",
--     className   = "Warrior",     -- localized
--     subgroup    = 1,
--     online      = true,
--     level       = 70,
--     isMaster    = false,         -- raid leader / assistant
--     roleHint    = "tank"|"heal"|"melee"|"ranged"|nil,
-- }
Roster.members = {}
Roster.count   = 0
Roster.inRaid  = false

----------------------------------------------------------------------
-- Crude role hint from class (TBC has no real role data)
----------------------------------------------------------------------
local CLASS_ROLE_HINT = {
    WARRIOR = "melee",
    PALADIN = "melee",
    DEATHKNIGHT = "melee",
    ROGUE   = "melee",
    HUNTER  = "ranged",
    MAGE    = "ranged",
    WARLOCK = "ranged",
    PRIEST  = "heal",
    DRUID   = "heal",
    SHAMAN  = "heal",
}

local function HintForClass(classFile)
    return CLASS_ROLE_HINT[classFile or ""] or "ranged"
end

----------------------------------------------------------------------
-- Snapshot the current group into Roster.members
----------------------------------------------------------------------
function Roster:Scan()
    local fresh = {}
    local count = 0

    if IsInRaidFn() then
        self.inRaid = true
        local n = GetNumGroup()
        for i = 1, n do
            local name, rank, subgroup, level, className, classFile, _, online = GetRaidRosterInfo(i)
            if name then
                fresh[name] = {
                    name      = name,
                    classFile = classFile,
                    className = className,
                    subgroup  = subgroup,
                    online    = online and true or false,
                    level     = level,
                    isMaster  = (rank or 0) >= 1,
                    roleHint  = HintForClass(classFile),
                }
                count = count + 1
            end
        end
    elseif IsInGroupFn() then
        self.inRaid = false
        -- Player
        do
            local name = UnitName("player")
            local _, classFile = UnitClass("player")
            if name then
                fresh[name] = {
                    name      = name,
                    classFile = classFile,
                    className = UnitClass("player"),
                    subgroup  = 1,
                    online    = true,
                    level     = UnitLevel("player"),
                    isMaster  = false,
                    roleHint  = HintForClass(classFile),
                }
                count = count + 1
            end
        end
        -- Party members
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name = UnitName(unit)
                local _, classFile = UnitClass(unit)
                if name then
                    fresh[name] = {
                        name      = name,
                        classFile = classFile,
                        className = UnitClass(unit),
                        subgroup  = 1,
                        online    = UnitIsConnected(unit) and true or false,
                        level     = UnitLevel(unit),
                        isMaster  = false,
                        roleHint  = HintForClass(classFile),
                    }
                    count = count + 1
                end
            end
        end
    else
        -- Solo
        self.inRaid = false
        local name = UnitName("player")
        local _, classFile = UnitClass("player")
        if name then
            fresh[name] = {
                name      = name,
                classFile = classFile,
                className = UnitClass("player"),
                subgroup  = 1,
                online    = true,
                level     = UnitLevel("player"),
                isMaster  = false,
                roleHint  = HintForClass(classFile),
            }
            count = 1
        end
    end

    self.members = fresh
    self.count   = count
    NS:FireCallback("ROSTER_UPDATED")
end

----------------------------------------------------------------------
-- Public helpers
----------------------------------------------------------------------
function Roster:GetMember(name)
    return self.members[name]
end

function Roster:Iterate()
    -- Returns a deterministic iterator (sorted by name)
    local list = {}
    for name in pairs(self.members) do list[#list + 1] = name end
    table.sort(list)
    local i = 0
    return function()
        i = i + 1
        local name = list[i]
        if not name then return nil end
        return name, self.members[name]
    end
end

function Roster:GetByClass(classFile)
    local out = {}
    for name, m in pairs(self.members) do
        if m.classFile == classFile then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

function Roster:GetByRoleHint(hint)
    local out = {}
    for name, m in pairs(self.members) do
        if m.roleHint == hint then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

----------------------------------------------------------------------
-- Event frame
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
-- GROUP_ROSTER_UPDATE replaces RAID_ROSTER_UPDATE/PARTY_MEMBERS_CHANGED
-- on newer clients but TBC also fires the legacy events; register both.
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

local pending = false
local function ScheduleScan()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        Roster:Scan()
    end)
end

frame:SetScript("OnEvent", function(_, event)
    ScheduleScan()
end)

NS:RegisterCallback("ADDON_LOADED", function()
    C_Timer.After(1, function() Roster:Scan() end)
end)
