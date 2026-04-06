----------------------------------------------------------------------
-- SimpleRaidAssign  -  Comms.lua
-- Addon-message synchronization layer, operating on whole raids.
-- Protocol (versioned): SRA1\tCMD\t<args...>
--   PUSH <raidKey>\t<serializedRaidTable>
--   REQ                            (broadcast: anyone with newer data may PUSH)
----------------------------------------------------------------------
local _, NS = ...

local Comms = {}
NS.Comms = Comms

local PREFIX    = "SRA1"
local PROTO_VER = 2

----------------------------------------------------------------------
-- Compat: SendAddonMessage / RegisterAddonMessagePrefix can live in
-- C_ChatInfo on newer clients (TBC 2.5.5 supports both).
----------------------------------------------------------------------
local SendAddonMessageFn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
local RegisterPrefixFn   = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix

----------------------------------------------------------------------
-- Tiny self-contained serializer (no Ace3 dependency).
-- Encodes strings, numbers, booleans, and nested tables; escapes
-- characters that would collide with the chat protocol.
----------------------------------------------------------------------
local function Escape(s)
    return (s:gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\n", "\\n"):gsub("|", "\\p"))
end

local function Unescape(s)
    return (s:gsub("\\p", "|"):gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\\\", "\\"))
end

local function Encode(value)
    local t = type(value)
    if t == "nil" then
        return "N"
    elseif t == "boolean" then
        return value and "T" or "F"
    elseif t == "number" then
        return "n:" .. tostring(value)
    elseif t == "string" then
        return "s:" .. Escape(value)
    elseif t == "table" then
        local parts = { "{" }
        for k, v in pairs(value) do
            parts[#parts + 1] = Encode(k) .. "=" .. Encode(v) .. ";"
        end
        parts[#parts + 1] = "}"
        return table.concat(parts)
    end
    return "N"
end

local Decode
local function DecodeAt(s, i)
    local c = s:sub(i, i)
    if c == "N" then
        return nil, i + 1
    elseif c == "T" then
        return true, i + 1
    elseif c == "F" then
        return false, i + 1
    elseif c == "n" then
        local j = s:find("[;=}]", i + 2) or (#s + 1)
        return tonumber(s:sub(i + 2, j - 1)), j
    elseif c == "s" then
        local j = s:find("[;=}]", i + 2) or (#s + 1)
        return Unescape(s:sub(i + 2, j - 1)), j
    elseif c == "{" then
        local out = {}
        local j = i + 1
        while s:sub(j, j) ~= "}" and j <= #s do
            local k, nj = DecodeAt(s, j)
            if s:sub(nj, nj) ~= "=" then return out, nj end
            local v, nj2 = DecodeAt(s, nj + 1)
            out[k] = v
            j = nj2
            if s:sub(j, j) == ";" then j = j + 1 end
        end
        return out, j + 1
    end
    return nil, i + 1
end

Decode = function(s)
    local v = DecodeAt(s, 1)
    return v
end

Comms.Encode = Encode
Comms.Decode = Decode

----------------------------------------------------------------------
-- Channel selection
----------------------------------------------------------------------
local function PreferredChannel()
    if (IsInRaid and IsInRaid()) or (GetNumRaidMembers and GetNumRaidMembers() > 0) then
        return "RAID"
    elseif (IsInGroup and IsInGroup()) or (GetNumPartyMembers and GetNumPartyMembers() > 0) then
        return "PARTY"
    end
    return nil
end

----------------------------------------------------------------------
-- Send helpers
----------------------------------------------------------------------
local function Send(payload, channel, target)
    channel = channel or PreferredChannel()
    if not channel then return false end
    pcall(SendAddonMessageFn, PREFIX, payload, channel, target)
    return true
end

function Comms:PushRaid(raidKey, channel, target)
    if not NS.Raids then return end
    local raid = NS.Raids:Get(raidKey)
    if not raid then return end
    local body = string.format("PUSH\t%s\t%s", raidKey, Encode(raid))
    Send(body, channel, target)
end

function Comms:BroadcastAll()
    if not NS.db or not NS.db.raids then return end
    for key in pairs(NS.db.raids) do
        self:PushRaid(key)
    end
end

function Comms:RequestSync()
    Send("REQ", PreferredChannel())
end

----------------------------------------------------------------------
-- Apply an incoming raid payload (last-write-wins based on updatedAt)
----------------------------------------------------------------------
local function ApplyIncomingRaid(raidKey, payload, sender)
    if not NS.db or not NS.db.settings.acceptIncoming then return end
    if type(payload) ~= "table" then return end

    local existing = NS.db.raids[raidKey]
    if existing and (existing.updatedAt or 0) >= (payload.updatedAt or 0) then
        return -- our copy is newer or equal
    end

    NS.db.raids[raidKey] = payload
    NS:FireCallback("DATA_UPDATED")
    NS:FireCallback("RAID_REPLACED", raidKey)

    if NS.db.settings.notifyOnSync then
        NS:Print(string.format("Synced |cffffff00%s|r from %s", payload.name or raidKey, sender or "?"))
    end
end

----------------------------------------------------------------------
-- Inbound handler
----------------------------------------------------------------------
local function HandleMessage(text, sender)
    if not text or text == "" then return end
    local me = UnitName("player")
    if sender == me or sender == (me .. "-" .. (GetRealmName() or "")) then return end

    local cmd, rest = text:match("^([^\t]+)\t?(.*)$")
    if not cmd then return end

    if cmd == "PUSH" then
        local key, body = rest:match("^([^\t]+)\t(.*)$")
        if not key or not body then return end
        local payload = Decode(body)
        ApplyIncomingRaid(key, payload, sender)

    elseif cmd == "REQ" then
        if NS.db and NS.db.settings.autoBroadcast then
            Comms:BroadcastAll()
        end
    end
end

----------------------------------------------------------------------
-- Auto-broadcast on local edits
----------------------------------------------------------------------
local function MaybeAutoBroadcast(_, raidKey)
    if NS.db and NS.db.settings.autoBroadcast and raidKey then
        Comms:PushRaid(raidKey)
    end
end

----------------------------------------------------------------------
-- Event frame
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    if event == "CHAT_MSG_ADDON" and prefix == PREFIX then
        HandleMessage(message, sender)
    end
end)

NS:RegisterCallback("ADDON_LOADED", function()
    if RegisterPrefixFn then
        pcall(RegisterPrefixFn, PREFIX)
    end
end)

NS:RegisterCallback("SYNC_PUSH_REQUEST", function()
    Comms:BroadcastAll()
    NS:Print("Pushed all raids to the group.")
end)

NS:RegisterCallback("SYNC_PULL_REQUEST", function()
    Comms:RequestSync()
    NS:Print("Requested raid sync from the group.")
end)

NS:RegisterCallback("RAID_CREATED", MaybeAutoBroadcast)
NS:RegisterCallback("RAID_UPDATED", MaybeAutoBroadcast)
