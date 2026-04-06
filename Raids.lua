----------------------------------------------------------------------
-- SimpleRaidAssign  -  Raids.lua
-- CRUD layer over NS.db.raids: create, rename, duplicate, delete,
-- iterate. Emits DATA_UPDATED so the UI and Comms layers can react.
----------------------------------------------------------------------
local _, NS = ...

local Raids = {}
NS.Raids = Raids

----------------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------------
local function NowTs() return time() end

local function NewId(prefix)
    return string.format("%s_%d_%04d", prefix or "id", NowTs(), math.random(0, 9999))
end

local function CurrentPlayer()
    return UnitName("player") or "Unknown"
end

local function GetRaid(key)
    if not NS.db or not NS.db.raids then return nil end
    return NS.db.raids[key]
end

----------------------------------------------------------------------
-- Create a new raid (optionally seeded from a source raid for duplication)
----------------------------------------------------------------------
function Raids:Create(name, sourceRaidKey)
    if not NS.db then return nil end
    local key = NewId("raid")

    local raid
    if sourceRaidKey and NS.db.raids[sourceRaidKey] then
        raid = NS.DeepCopy(NS.db.raids[sourceRaidKey])
        raid.name      = name or (raid.name .. " (copy)")
        raid.createdAt = NowTs()
        raid.updatedAt = NowTs()
        raid.createdBy = CurrentPlayer()
        raid.updatedBy = CurrentPlayer()
    else
        raid = {
            name           = name or "New Raid",
            createdAt      = NowTs(),
            updatedAt      = NowTs(),
            createdBy      = CurrentPlayer(),
            updatedBy      = CurrentPlayer(),
            notes          = "",
            encounters     = {},
            encounterOrder = {},
        }
    end

    NS.db.raids[key] = raid
    NS.db.settings.lastRaid = key

    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("RAID_CREATED", key)
    return key
end

----------------------------------------------------------------------
-- Duplicate an existing raid (shortcut for Create with a source)
----------------------------------------------------------------------
function Raids:Duplicate(sourceKey)
    local src = GetRaid(sourceKey)
    if not src then return nil end
    return self:Create((src.name or "Raid") .. " (copy)", sourceKey)
end

----------------------------------------------------------------------
-- Rename
----------------------------------------------------------------------
function Raids:Rename(key, newName)
    local raid = GetRaid(key)
    if not raid or not newName or newName == "" then return end
    raid.name = newName
    raid.updatedAt = NowTs()
    raid.updatedBy = CurrentPlayer()
    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("RAID_UPDATED", key)
end

----------------------------------------------------------------------
-- Delete
----------------------------------------------------------------------
function Raids:Delete(key)
    if not NS.db or not NS.db.raids[key] then return end
    NS.db.raids[key] = nil
    if NS.db.settings.lastRaid == key then
        NS.db.settings.lastRaid = nil
        NS.db.settings.lastEncounter = nil
    end
    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("RAID_DELETED", key)
end

----------------------------------------------------------------------
-- Touch: update the updatedAt timestamp (called by child modules when
-- an encounter or attribution is modified)
----------------------------------------------------------------------
function Raids:Touch(key)
    local raid = GetRaid(key)
    if not raid then return end
    raid.updatedAt = NowTs()
    raid.updatedBy = CurrentPlayer()
end

----------------------------------------------------------------------
-- Getters
----------------------------------------------------------------------
function Raids:Get(key)
    return GetRaid(key)
end

function Raids:Exists(key)
    return GetRaid(key) ~= nil
end

----------------------------------------------------------------------
-- Iterator: sorted by updatedAt descending (most recent first)
----------------------------------------------------------------------
function Raids:Iterate()
    local list = {}
    if NS.db and NS.db.raids then
        for key, raid in pairs(NS.db.raids) do
            list[#list + 1] = { key = key, raid = raid }
        end
    end
    table.sort(list, function(a, b)
        return (a.raid.updatedAt or 0) > (b.raid.updatedAt or 0)
    end)
    local i = 0
    return function()
        i = i + 1
        local item = list[i]
        if not item then return nil end
        return item.key, item.raid
    end
end

----------------------------------------------------------------------
-- Counters (for the raid summary cartouche)
----------------------------------------------------------------------
function Raids:CountEncounters(key)
    local raid = GetRaid(key)
    if not raid then return 0 end
    local n = 0
    for _ in pairs(raid.encounters) do n = n + 1 end
    return n
end

-- Returns the number of DISTINCT player names assigned anywhere in
-- the raid (across all bosses and attributions). A player assigned to
-- multiple roles / bosses is counted once.
function Raids:CountAssignedPlayers(key)
    local raid = GetRaid(key)
    if not raid then return 0 end
    local seen = {}
    local n = 0
    for _, enc in pairs(raid.encounters) do
        for _, attrib in pairs(enc.attributions or {}) do
            if attrib.players then
                for _, name in ipairs(attrib.players) do
                    if name and name ~= "" and not seen[name] then
                        seen[name] = true
                        n = n + 1
                    end
                end
            end
        end
    end
    return n
end

----------------------------------------------------------------------
-- Import / Export
--
-- An exported raid is a single text string of the form:
--
--     SRA1:<encoded raid table>
--
-- The encoded body uses NS.Comms.Encode (the same self-contained
-- serializer used for raid sync over addon channels), so the format
-- is plain ASCII, has no raw newlines / pipes / tabs, and is safe to
-- copy-paste into chat windows or forum posts.
----------------------------------------------------------------------
local FORMAT_PREFIX = "SRA1:"

function Raids:Export(key)
    local raid = GetRaid(key)
    if not raid or not NS.Comms then return nil end
    local payload = NS.Comms.Encode(raid)
    return FORMAT_PREFIX .. payload
end

function Raids:Import(text, newName)
    if type(text) ~= "string" or text == "" then
        return nil, "Empty import string"
    end
    -- Trim leading/trailing whitespace (newlines from copy-paste are common)
    text = text:match("^%s*(.-)%s*$") or ""
    if text:sub(1, #FORMAT_PREFIX) ~= FORMAT_PREFIX then
        return nil, "Invalid format - expected an SRA1: prefix"
    end
    if not NS.Comms then
        return nil, "Comms module not loaded"
    end

    local payload = text:sub(#FORMAT_PREFIX + 1)
    local ok, raid = pcall(NS.Comms.Decode, payload)
    if not ok or type(raid) ~= "table" then
        return nil, "Failed to parse raid data"
    end
    if type(raid.encounters) ~= "table" or type(raid.encounterOrder) ~= "table" then
        return nil, "Imported data is missing required fields"
    end

    -- Sanity-defaults for fields that might be absent on older exports
    raid.notes      = raid.notes or ""
    raid.name       = (newName and newName ~= "") and newName or (raid.name or "Imported raid")
    raid.createdAt  = NowTs()
    raid.updatedAt  = NowTs()
    raid.createdBy  = CurrentPlayer()
    raid.updatedBy  = CurrentPlayer()

    local key = NewId("raid")
    NS.db.raids[key] = raid
    NS.db.settings.lastRaid = key

    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("RAID_CREATED", key)
    return key, nil
end

----------------------------------------------------------------------
-- Quick helper for the import dialog: extract the original raid name
-- from an exported string WITHOUT actually importing it. Used to
-- pre-fill the "New name" input with a sensible default the user can
-- accept or override.
----------------------------------------------------------------------
function Raids:PeekImportName(text)
    if type(text) ~= "string" or text == "" then return nil end
    text = text:match("^%s*(.-)%s*$") or ""
    if text:sub(1, #FORMAT_PREFIX) ~= FORMAT_PREFIX then return nil end
    if not NS.Comms then return nil end
    local ok, raid = pcall(NS.Comms.Decode, text:sub(#FORMAT_PREFIX + 1))
    if ok and type(raid) == "table" then return raid.name end
    return nil
end

function Raids:CountAttributions(key)
    local raid = GetRaid(key)
    if not raid then return 0 end
    local n = 0
    for _, enc in pairs(raid.encounters) do
        for _ in pairs(enc.attributions or {}) do n = n + 1 end
    end
    return n
end
