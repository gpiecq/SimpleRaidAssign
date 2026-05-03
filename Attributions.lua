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

local function GetEncounter(raidKey, encounterKey)
    local raid = GetRaid(raidKey)
    if not raid or not raid.encounters then return nil end
    return NormalizeEncounter(raid.encounters[encounterKey])
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
        name           = bossName,
        instance       = instance or "",
        attributions   = {},
        order          = {},
        categories     = {},
        categoryOrder  = {},
        updated        = NowTs(),
        updatedBy      = CurrentPlayer(),
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
        marker     = marker,              -- nil or 1..8
        context    = context or "",
        players    = players or {},
        note       = "",                  -- free-text multi-line note
        categoryId = categoryId,          -- nil = Uncategorized
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

    -- Find the source position and the source attribution's category.
    local fromIdx
    for i, k in ipairs(enc.order) do
        if k == attribId then fromIdx = i; break end
    end
    if not fromIdx then return end

    local sourceCat = enc.attributions[attribId] and enc.attributions[attribId].categoryId or nil

    -- Walk in the requested direction until we find the next attribId
    -- whose categoryId matches the source. delta is +1 (down) or -1 (up).
    local step = (delta and delta > 0) and 1 or -1
    local toIdx = fromIdx + step
    while toIdx >= 1 and toIdx <= #enc.order do
        local otherId  = enc.order[toIdx]
        local otherAtt = enc.attributions[otherId]
        local otherCat = otherAtt and otherAtt.categoryId or nil
        if otherCat == sourceCat then
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
    if catId ~= nil and not enc.categories[catId] then return end
    enc.attributions[attribId].categoryId = catId
    TouchParents(raidKey, encounterKey)
    NS:FireCallback("DATA_UPDATED")
end
