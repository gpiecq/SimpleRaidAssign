----------------------------------------------------------------------
-- WowShiftAssign  -  Assignments.lua
-- CRUD layer over NS.db.encounters. Generates ids, manages role slots,
-- emits DATA_UPDATED so UI and Comms can react.
----------------------------------------------------------------------
local _, NS = ...

local Assignments = {}
NS.Assignments = Assignments

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function NowTs() return time() end

local function NewId(prefix)
    return string.format("%s_%d_%04d", prefix or "id", NowTs(), math.random(0, 9999))
end

local function CurrentPlayer()
    return UnitName("player") or "Unknown"
end

local function GetEncounter(key)
    if not NS.db or not NS.db.encounters then return nil end
    return NS.db.encounters[key]
end

----------------------------------------------------------------------
-- Encounter CRUD
----------------------------------------------------------------------
function Assignments:CreateEncounter(name, instance, templateKey)
    if not NS.db then return nil end
    local key = NewId("enc")

    local enc = {
        name      = name or "New Encounter",
        instance  = instance or "",
        roles     = {},
        order     = {},
        updated   = NowTs(),
        updatedBy = CurrentPlayer(),
    }

    -- Seed from template if provided
    if templateKey and NS.Data then
        local tpl = NS.Data:GetTemplate(templateKey)
        if tpl then
            enc.name     = enc.name == "New Encounter" and tpl.name or enc.name
            enc.instance = enc.instance == "" and (tpl.instance or "") or enc.instance
            for _, r in ipairs(tpl.roles) do
                local roleKey = NewId("role")
                enc.roles[roleKey] = {
                    label    = r.label or "",
                    roleType = r.roleType or "custom",
                    slots    = {},
                    notes    = "",
                }
                enc.order[#enc.order + 1] = roleKey
            end
        end
    end

    NS.db.encounters[key] = enc
    NS.db.settings.lastEncounter = key

    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("ENCOUNTER_CREATED", key)
    return key
end

function Assignments:DeleteEncounter(key)
    if not NS.db or not NS.db.encounters[key] then return end
    NS.db.encounters[key] = nil
    if NS.db.settings.lastEncounter == key then
        NS.db.settings.lastEncounter = nil
    end
    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("ENCOUNTER_DELETED", key)
end

function Assignments:RenameEncounter(key, newName)
    local enc = GetEncounter(key)
    if not enc then return end
    enc.name = newName or enc.name
    enc.updated = NowTs()
    enc.updatedBy = CurrentPlayer()
    NS:FireCallback("DATA_UPDATED")
end

function Assignments:GetEncounter(key)
    return GetEncounter(key)
end

function Assignments:IterateEncounters()
    local list = {}
    if NS.db and NS.db.encounters then
        for key, enc in pairs(NS.db.encounters) do
            list[#list + 1] = { key = key, enc = enc }
        end
    end
    table.sort(list, function(a, b)
        if a.enc.instance == b.enc.instance then
            return (a.enc.name or "") < (b.enc.name or "")
        end
        return (a.enc.instance or "") < (b.enc.instance or "")
    end)
    local i = 0
    return function()
        i = i + 1
        local item = list[i]
        if not item then return nil end
        return item.key, item.enc
    end
end

----------------------------------------------------------------------
-- Role CRUD
----------------------------------------------------------------------
function Assignments:AddRole(encounterKey, roleType, label)
    local enc = GetEncounter(encounterKey)
    if not enc then return nil end

    local typeEntry = NS.Data and NS.Data:GetRoleType(roleType) or nil
    local roleKey = NewId("role")
    enc.roles[roleKey] = {
        label    = label or (typeEntry and typeEntry.label) or "Role",
        roleType = roleType or "custom",
        slots    = {},
        notes    = "",
    }
    enc.order[#enc.order + 1] = roleKey
    enc.updated = NowTs()
    enc.updatedBy = CurrentPlayer()

    NS:FireCallback("DATA_UPDATED")
    return roleKey
end

function Assignments:RemoveRole(encounterKey, roleKey)
    local enc = GetEncounter(encounterKey)
    if not enc or not enc.roles[roleKey] then return end
    enc.roles[roleKey] = nil
    for i, k in ipairs(enc.order) do
        if k == roleKey then table.remove(enc.order, i); break end
    end
    enc.updated = NowTs()
    enc.updatedBy = CurrentPlayer()
    NS:FireCallback("DATA_UPDATED")
end

function Assignments:RenameRole(encounterKey, roleKey, newLabel)
    local enc = GetEncounter(encounterKey)
    if not enc or not enc.roles[roleKey] then return end
    enc.roles[roleKey].label = newLabel or enc.roles[roleKey].label
    enc.updated = NowTs()
    enc.updatedBy = CurrentPlayer()
    NS:FireCallback("DATA_UPDATED")
end

function Assignments:SetRoleNotes(encounterKey, roleKey, notes)
    local enc = GetEncounter(encounterKey)
    if not enc or not enc.roles[roleKey] then return end
    enc.roles[roleKey].notes = notes or ""
    enc.updated = NowTs()
    enc.updatedBy = CurrentPlayer()
    NS:FireCallback("DATA_UPDATED")
end

function Assignments:MoveRole(encounterKey, roleKey, delta)
    local enc = GetEncounter(encounterKey)
    if not enc then return end
    for i, k in ipairs(enc.order) do
        if k == roleKey then
            local target = i + delta
            if target < 1 or target > #enc.order then return end
            table.remove(enc.order, i)
            table.insert(enc.order, target, roleKey)
            enc.updated = NowTs()
            enc.updatedBy = CurrentPlayer()
            NS:FireCallback("DATA_UPDATED")
            return
        end
    end
end

----------------------------------------------------------------------
-- Slot management
----------------------------------------------------------------------
local function FindSlot(role, name)
    for i, n in ipairs(role.slots) do
        if n == name then return i end
    end
    return nil
end

function Assignments:AssignPlayer(encounterKey, roleKey, playerName)
    local enc = GetEncounter(encounterKey)
    if not enc or not enc.roles[roleKey] or not playerName then return end
    local role = enc.roles[roleKey]
    if FindSlot(role, playerName) then return end -- already assigned
    role.slots[#role.slots + 1] = playerName
    enc.updated = NowTs()
    enc.updatedBy = CurrentPlayer()
    NS:FireCallback("DATA_UPDATED")
end

function Assignments:UnassignPlayer(encounterKey, roleKey, playerName)
    local enc = GetEncounter(encounterKey)
    if not enc or not enc.roles[roleKey] then return end
    local role = enc.roles[roleKey]
    local idx = FindSlot(role, playerName)
    if not idx then return end
    table.remove(role.slots, idx)
    enc.updated = NowTs()
    enc.updatedBy = CurrentPlayer()
    NS:FireCallback("DATA_UPDATED")
end

function Assignments:ClearRole(encounterKey, roleKey)
    local enc = GetEncounter(encounterKey)
    if not enc or not enc.roles[roleKey] then return end
    enc.roles[roleKey].slots = {}
    enc.updated = NowTs()
    enc.updatedBy = CurrentPlayer()
    NS:FireCallback("DATA_UPDATED")
end

----------------------------------------------------------------------
-- Bulk operations (used by Comms.lua when receiving payloads)
----------------------------------------------------------------------
function Assignments:ReplaceEncounter(key, payload)
    if not NS.db or not key or type(payload) ~= "table" then return end
    NS.db.encounters[key] = {
        name      = payload.name or "Imported",
        instance  = payload.instance or "",
        roles     = payload.roles or {},
        order     = payload.order or {},
        updated   = payload.updated or NowTs(),
        updatedBy = payload.updatedBy or "Unknown",
    }
    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("ENCOUNTER_REPLACED", key)
end

function Assignments:ExportEncounter(key)
    local enc = GetEncounter(key)
    if not enc then return nil end
    -- Return a deep copy so callers can serialize without mutation risk
    return NS.DeepCopy(enc)
end
