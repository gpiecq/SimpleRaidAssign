----------------------------------------------------------------------
-- SimpleRaidAssign  -  Attributions.lua
-- CRUD for encounters (bosses) within a raid AND attributions within
-- an encounter. All operations are scoped by (raidKey, encounterKey,
-- attribId) and fire DATA_UPDATED + parent Raid touch.
----------------------------------------------------------------------
local _, NS = ...

local Attributions = {}
NS.Attributions = Attributions

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

local function GetRaid(raidKey)
    return NS.Raids and NS.Raids:Get(raidKey) or nil
end

local function GetEncounter(raidKey, encounterKey)
    local raid = GetRaid(raidKey)
    if not raid or not raid.encounters then return nil end
    return raid.encounters[encounterKey]
end

local function TouchParents(raidKey, encounterKey)
    local enc = GetEncounter(raidKey, encounterKey)
    if enc then
        enc.updated   = NowTs()
        enc.updatedBy = CurrentPlayer()
    end
    if NS.Raids then NS.Raids:Touch(raidKey) end
end

-- ====================================================================
--  ENCOUNTERS (bosses)
-- ====================================================================

----------------------------------------------------------------------
-- Add a boss to a raid. `bossName` must be a known TBC boss name from
-- TBCBosses (or any string the caller wants).
----------------------------------------------------------------------
function Attributions:AddEncounter(raidKey, bossName)
    local raid = GetRaid(raidKey)
    if not raid or not bossName or bossName == "" then return nil end

    local encKey = NewId("enc")
    local instance = NS.TBCBosses and NS.TBCBosses:GetInstanceOf(bossName) or ""

    raid.encounters[encKey] = {
        name         = bossName,
        instance     = instance or "",
        attributions = {},
        order        = {},
        updated      = NowTs(),
        updatedBy    = CurrentPlayer(),
    }
    raid.encounterOrder[#raid.encounterOrder + 1] = encKey

    if NS.Raids then NS.Raids:Touch(raidKey) end
    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("ENCOUNTER_ADDED", raidKey, encKey)
    return encKey
end

----------------------------------------------------------------------
-- Delete a boss from a raid
----------------------------------------------------------------------
function Attributions:DeleteEncounter(raidKey, encounterKey)
    local raid = GetRaid(raidKey)
    if not raid or not raid.encounters[encounterKey] then return end
    raid.encounters[encounterKey] = nil
    for i, k in ipairs(raid.encounterOrder) do
        if k == encounterKey then table.remove(raid.encounterOrder, i); break end
    end
    if NS.db and NS.db.settings.lastEncounter == encounterKey then
        NS.db.settings.lastEncounter = nil
    end
    if NS.Raids then NS.Raids:Touch(raidKey) end
    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("ENCOUNTER_DELETED", raidKey, encounterKey)
end

----------------------------------------------------------------------
-- Rename a boss (free text override of the canonical name)
----------------------------------------------------------------------
function Attributions:RenameEncounter(raidKey, encounterKey, newName)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc or not newName or newName == "" then return end
    enc.name = newName
    TouchParents(raidKey, encounterKey)
    NS:FireCallback("DATA_UPDATED")
end

----------------------------------------------------------------------
-- Move a boss up or down in the encounterOrder
----------------------------------------------------------------------
function Attributions:MoveEncounter(raidKey, encounterKey, delta)
    local raid = GetRaid(raidKey)
    if not raid then return end
    for i, k in ipairs(raid.encounterOrder) do
        if k == encounterKey then
            local target = i + delta
            if target < 1 or target > #raid.encounterOrder then return end
            table.remove(raid.encounterOrder, i)
            table.insert(raid.encounterOrder, target, encounterKey)
            if NS.Raids then NS.Raids:Touch(raidKey) end
            NS:FireCallback("DATA_UPDATED")
            return
        end
    end
end

----------------------------------------------------------------------
-- Iterators
----------------------------------------------------------------------
function Attributions:IterateEncounters(raidKey)
    local raid = GetRaid(raidKey)
    if not raid then return function() return nil end end
    local order = raid.encounterOrder or {}
    local i = 0
    return function()
        i = i + 1
        local key = order[i]
        if not key then return nil end
        return key, raid.encounters[key]
    end
end

function Attributions:GetEncounter(raidKey, encounterKey)
    return GetEncounter(raidKey, encounterKey)
end

-- ====================================================================
--  ATTRIBUTIONS (marker + players + context)
-- ====================================================================

----------------------------------------------------------------------
-- Add a blank attribution to an encounter
----------------------------------------------------------------------
function Attributions:AddAttribution(raidKey, encounterKey, marker, context, players)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc then return nil end

    local attribId = NewId("attrib")
    enc.attributions[attribId] = {
        marker  = marker,              -- nil or 1..8
        context = context or "",
        players = players or {},
        note    = "",                  -- free-text multi-line note
    }
    enc.order[#enc.order + 1] = attribId
    TouchParents(raidKey, encounterKey)
    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("ATTRIBUTION_ADDED", raidKey, encounterKey, attribId)
    return attribId
end

----------------------------------------------------------------------
-- Update the marker / context / players / note of an attribution.
--
-- Marker semantics:
--   * omit the `marker` key entirely to keep the current value
--   * pass `marker = false` (or an explicit nil wrapper, see below)
--     to CLEAR the marker
--   * pass `marker = 1..8` to set a specific raid target icon
--
-- Because Lua tables collapse `{ marker = nil }` (the key simply does
-- not exist), callers who want to clear must use `marker = false`,
-- which we translate to nil on assignment.
----------------------------------------------------------------------
function Attributions:UpdateAttribution(raidKey, encounterKey, attribId, patch)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc or not enc.attributions[attribId] or type(patch) ~= "table" then return end
    local a = enc.attributions[attribId]

    if patch.marker ~= nil then
        if patch.marker == false then
            a.marker = nil
        else
            a.marker = patch.marker
        end
    end
    if patch.context ~= nil then a.context = patch.context end
    if patch.players ~= nil then a.players = patch.players end
    if patch.note    ~= nil then a.note    = patch.note end

    TouchParents(raidKey, encounterKey)
    NS:FireCallback("DATA_UPDATED")
end

----------------------------------------------------------------------
-- Dedicated helper to explicitly clear the marker of an attribution.
-- Avoids any ambiguity with the patch-based UpdateAttribution.
----------------------------------------------------------------------
function Attributions:ClearMarker(raidKey, encounterKey, attribId)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc or not enc.attributions[attribId] then return end
    enc.attributions[attribId].marker = nil
    TouchParents(raidKey, encounterKey)
    NS:FireCallback("DATA_UPDATED")
end

----------------------------------------------------------------------
-- Delete an attribution
----------------------------------------------------------------------
function Attributions:DeleteAttribution(raidKey, encounterKey, attribId)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc or not enc.attributions[attribId] then return end
    enc.attributions[attribId] = nil
    for i, k in ipairs(enc.order) do
        if k == attribId then table.remove(enc.order, i); break end
    end
    TouchParents(raidKey, encounterKey)
    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("ATTRIBUTION_DELETED", raidKey, encounterKey, attribId)
end

----------------------------------------------------------------------
-- Append a player to an attribution (dedup, respects order)
-- Used by the shift-click hook and by manual "add player" actions.
----------------------------------------------------------------------
function Attributions:AddPlayer(raidKey, encounterKey, attribId, playerName)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc or not enc.attributions[attribId] or not playerName or playerName == "" then return end
    local a = enc.attributions[attribId]
    a.players = a.players or {}
    for _, n in ipairs(a.players) do
        if n == playerName then return end -- already present
    end
    a.players[#a.players + 1] = playerName
    TouchParents(raidKey, encounterKey)
    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("ATTRIBUTION_PLAYER_ADDED", raidKey, encounterKey, attribId, playerName)
end

----------------------------------------------------------------------
-- Remove a player from an attribution
----------------------------------------------------------------------
function Attributions:RemovePlayer(raidKey, encounterKey, attribId, playerName)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc or not enc.attributions[attribId] then return end
    local a = enc.attributions[attribId]
    if not a.players then return end
    for i, n in ipairs(a.players) do
        if n == playerName then
            table.remove(a.players, i)
            TouchParents(raidKey, encounterKey)
            NS:FireCallback("DATA_UPDATED")
            return
        end
    end
end

----------------------------------------------------------------------
-- Iterators
----------------------------------------------------------------------
function Attributions:IterateAttributions(raidKey, encounterKey)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc then return function() return nil end end
    local order = enc.order or {}
    local i = 0
    return function()
        i = i + 1
        local key = order[i]
        if not key then return nil end
        return key, enc.attributions[key]
    end
end

function Attributions:GetAttribution(raidKey, encounterKey, attribId)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc then return nil end
    return enc.attributions[attribId]
end

----------------------------------------------------------------------
-- Move an attribution up or down in the display order
----------------------------------------------------------------------
function Attributions:MoveAttribution(raidKey, encounterKey, attribId, delta)
    local enc = GetEncounter(raidKey, encounterKey)
    if not enc then return end
    for i, k in ipairs(enc.order) do
        if k == attribId then
            local target = i + delta
            if target < 1 or target > #enc.order then return end
            table.remove(enc.order, i)
            table.insert(enc.order, target, attribId)
            TouchParents(raidKey, encounterKey)
            NS:FireCallback("DATA_UPDATED")
            return
        end
    end
end

----------------------------------------------------------------------
-- Parse a free-text players string like "PlayerA, PlayerB PlayerC"
-- into a clean list, splitting on commas and whitespace.
----------------------------------------------------------------------
function Attributions:ParsePlayerList(text)
    local out = {}
    if not text or text == "" then return out end
    for word in string.gmatch(text, "[^,%s]+") do
        if word and word ~= "" then out[#out + 1] = word end
    end
    return out
end

----------------------------------------------------------------------
-- Format a player list for display in an input field
----------------------------------------------------------------------
function Attributions:FormatPlayerList(players)
    if not players or #players == 0 then return "" end
    return table.concat(players, ", ")
end
