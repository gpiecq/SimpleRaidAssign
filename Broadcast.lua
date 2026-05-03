----------------------------------------------------------------------
-- SimpleRaidAssign  -  Broadcast.lua
-- Builds localized chat announce strings for a boss encounter and
-- sends them via SendChatMessage. Handles the 255-char limit by
-- splitting on the `|` separator into multiple messages.
----------------------------------------------------------------------
local _, NS = ...

local Broadcast = {}
NS.Broadcast = Broadcast

local MAX_MSG = 255

-- Separator between attribution segments in the concatenated announce
-- message. Must NOT use the pipe character `|` because WoW's chat
-- protocol treats `|` as the start of an escape code (`|cXXX|r`,
-- `|Hlink|h`, ...) and SendChatMessage rejects messages with an
-- unrecognized escape sequence.
local SEP = " / "

----------------------------------------------------------------------
-- English-only labels for the chat announce strings.
----------------------------------------------------------------------
local L = {
    titleFmt    = "[%s]",
    noAttribs   = "no attributions",
    noEncounter = "no boss selected",
    noChannel   = "unknown channel",
    noGroup     = "not in a group",
}

----------------------------------------------------------------------
-- Channel validation
-- Valid Blizzard chat channels for SendChatMessage
----------------------------------------------------------------------
local VALID_CHANNELS = {
    RAID          = true,
    RAID_WARNING  = true,
    PARTY         = true,
    SAY           = true,
    YELL          = true,
    GUILD         = true,
    OFFICER       = true,
}

function Broadcast:IsValidChannel(channel)
    return VALID_CHANNELS[channel or ""] == true
end

----------------------------------------------------------------------
-- Is the player currently able to send to this channel?
-- We are conservative: if the group prerequisite is not met, fall back
-- to SAY so the user at least sees what would have been sent.
----------------------------------------------------------------------
local function ResolveChannel(channel)
    if channel == "RAID" or channel == "RAID_WARNING" then
        if not ((IsInRaid and IsInRaid()) or (GetNumRaidMembers and GetNumRaidMembers() > 0)) then
            return "SAY"
        end
    elseif channel == "PARTY" then
        if not ((IsInGroup and IsInGroup()) or (GetNumPartyMembers and GetNumPartyMembers() > 0)) then
            return "SAY"
        end
    elseif channel == "GUILD" or channel == "OFFICER" then
        if not IsInGuild() then
            return "SAY"
        end
    end
    return channel
end

----------------------------------------------------------------------
-- Sanitize a user-provided free-text field for safe inclusion in chat.
-- Strips newlines (chat messages are single-line), collapses whitespace,
-- and removes `|` because WoW's chat parser treats it as the start of
-- an escape code (`|cff...|r`, `|Hlink|h`, ...) and rejects the whole
-- message if it doesn't match a known code.
----------------------------------------------------------------------
local function SanitizeChatText(text)
    if not text or text == "" then return "" end
    text = text:gsub("[\r\n]+", " ")
    text = text:gsub("||", "")      -- already-escaped pipes
    text = text:gsub("|", "")       -- bare pipes
    text = text:gsub("%s+", " ")    -- collapse runs of whitespace
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

----------------------------------------------------------------------
-- Format a single attribution segment:
--   "{rt8} Context: A, B (note text)"
-- The marker token is only prepended when a marker is set; the note
-- suffix is only appended when the attribution has a non-empty note.
----------------------------------------------------------------------
local function FormatSegment(attrib)
    local parts = {}
    if attrib.marker and NS.Data then
        local m = NS.Data:GetMarker(attrib.marker)
        if m then parts[#parts + 1] = m.token end
    end

    if attrib.context and attrib.context ~= "" then
        parts[#parts + 1] = attrib.context .. ":"
    else
        parts[#parts + 1] = "(no context):"
    end

    if attrib.players and #attrib.players > 0 then
        parts[#parts + 1] = table.concat(attrib.players, ", ")
    else
        parts[#parts + 1] = "-"
    end

    local note = SanitizeChatText(attrib.note)
    if note ~= "" then
        parts[#parts + 1] = "(" .. note .. ")"
    end

    return table.concat(parts, " ")
end

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

----------------------------------------------------------------------
-- Assemble segments into chat-ready messages respecting the 255-char
-- limit. Splits cleanly on segment boundaries, prepending the boss
-- title only to the first message.
----------------------------------------------------------------------
local function ChunkMessages(title, segments)
    local messages = {}

    local function pushNew(firstSegment)
        if title and #messages == 0 then
            return title .. " " .. firstSegment
        end
        return firstSegment
    end

    if #segments == 0 then
        if title then messages[1] = title end
        return messages
    end

    local current = pushNew(segments[1])

    for i = 2, #segments do
        local seg = segments[i]
        local candidate = current .. SEP .. seg
        if #candidate <= MAX_MSG then
            current = candidate
        else
            messages[#messages + 1] = current
            current = seg
            -- If the isolated segment itself exceeds the limit, truncate
            -- gracefully (very rare: would need ~250 chars in one entry)
            if #current > MAX_MSG then
                current = current:sub(1, MAX_MSG - 3) .. "..."
            end
        end
    end

    if current ~= "" then
        messages[#messages + 1] = current
    end
    return messages
end

Broadcast.ChunkMessages = ChunkMessages   -- exposed for tests/debug

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

----------------------------------------------------------------------
-- Send an announce to the given chat channel.
-- Returns the number of messages sent, or 0 on failure.
----------------------------------------------------------------------
function Broadcast:Announce(raidKey, encounterKey, _language, channel, filter)
    channel = channel or (NS.db and NS.db.settings.announceChannel) or "RAID"

    if not self:IsValidChannel(channel) then
        NS:Print(L.noChannel .. ": " .. tostring(channel))
        return 0
    end

    local effectiveChannel = ResolveChannel(channel)
    local messages = self:BuildMessages(raidKey, encounterKey, filter)
    if #messages == 0 then return 0 end

    for _, msg in ipairs(messages) do
        SendChatMessage(msg, effectiveChannel)
    end

    if effectiveChannel ~= channel then
        NS:Print(string.format("Fell back to %s (%s not available)", effectiveChannel, channel))
    end

    return #messages
end

----------------------------------------------------------------------
-- Substitute {rt1}..{rt8} chat tokens with the equivalent texture
-- inline escape so the icons render in a preview printed via print().
-- The native chat parser only processes these tokens when a message
-- arrives through SendChatMessage; locally-printed lines display the
-- raw `{rt8}` text instead, which is unhelpful for a preview.
----------------------------------------------------------------------
local function RenderMarkerTokens(text)
    if not text then return "" end
    return (text:gsub("{rt(%d+)}", function(n)
        local idx = tonumber(n)
        if idx and idx >= 1 and idx <= 8 then
            return string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:0|t", idx)
        end
        return "{rt" .. n .. "}"
    end))
end

Broadcast.RenderMarkerTokens = RenderMarkerTokens   -- exposed for tests/debug

----------------------------------------------------------------------
-- Preview (does not actually send, prints to the local chat frame).
-- `filter` is an optional set of allowed attribution ids.
----------------------------------------------------------------------
function Broadcast:Preview(raidKey, encounterKey, filter)
    local messages = self:BuildMessages(raidKey, encounterKey, filter)
    NS:Print(string.format("Preview (%d messages):", #messages))
    for i, msg in ipairs(messages) do
        print(string.format("  [%d] %s", i, RenderMarkerTokens(msg)))
    end
end
