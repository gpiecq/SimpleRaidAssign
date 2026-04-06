----------------------------------------------------------------------
-- WowShiftAssign  -  Core.lua
-- Addon initialisation, SavedVariables defaults, event bus, slash cmds
----------------------------------------------------------------------
local ADDON_NAME, NS = ...
NS.version = "0.1.0"

----------------------------------------------------------------------
-- Default saved-variables template (account-wide)
----------------------------------------------------------------------
local DEFAULTS = {
    -- Per-encounter assignment trees
    -- encounters[encounterKey] = {
    --     name      = "Lady Vashj",
    --     instance  = "Serpentshrine Cavern",
    --     roles     = {
    --         [roleKey] = {
    --             label   = "Tainted Core Carriers",
    --             roleType = "carry",   -- key from AssignData
    --             slots   = { "Playername", ... },
    --             notes   = "...",
    --         },
    --         ...
    --     },
    --     order     = { roleKey1, roleKey2, ... },  -- display order
    --     updated   = <timestamp>,
    --     updatedBy = "Playername",
    -- }
    encounters = {},

    -- User-defined templates re-usable across encounters
    templates  = {},

    settings = {
        autoBroadcast   = true,    -- push changes to raid automatically
        acceptIncoming  = true,    -- accept incoming syncs
        notifyOnSync    = true,    -- chat message when receiving updates
        lastEncounter   = nil,     -- last encounter shown in the UI
        windowPos       = { point = "CENTER", x = 0, y = 0 },
        minimapPos      = 215,     -- angle on minimap edge
    },
}

local CHAR_DEFAULTS = {
    -- Per-character UI state (collapsed sections, last selected role, etc.)
    ui = {
        collapsed = {},
    },
}

----------------------------------------------------------------------
-- Deep-copy helper (for defaults)
----------------------------------------------------------------------
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do copy[k] = DeepCopy(v) end
    return copy
end
NS.DeepCopy = DeepCopy

----------------------------------------------------------------------
-- Merge defaults into saved table (non-destructive)
----------------------------------------------------------------------
local function MergeDefaults(sv, def)
    for k, v in pairs(def) do
        if type(v) == "table" then
            if type(sv[k]) ~= "table" then sv[k] = {} end
            MergeDefaults(sv[k], v)
        elseif sv[k] == nil then
            sv[k] = v
        end
    end
end

----------------------------------------------------------------------
-- Simple internal event bus
----------------------------------------------------------------------
NS.callbacks = {}

function NS:RegisterCallback(event, fn)
    if not self.callbacks[event] then self.callbacks[event] = {} end
    self.callbacks[event][#self.callbacks[event] + 1] = fn
end

function NS:FireCallback(event, ...)
    local cbs = self.callbacks[event]
    if not cbs then return end
    for i = 1, #cbs do cbs[i](...) end
end

----------------------------------------------------------------------
-- Pretty print helper
----------------------------------------------------------------------
function NS:Print(msg)
    print("|cff00ccffWowShiftAssign:|r " .. tostring(msg))
end

----------------------------------------------------------------------
-- Addon init frame
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Initialise / migrate account-wide saved variables
        if not WowShiftAssignDB then
            WowShiftAssignDB = DeepCopy(DEFAULTS)
        else
            MergeDefaults(WowShiftAssignDB, DEFAULTS)
        end

        -- Per-character saved variables
        if not WowShiftAssignCharDB then
            WowShiftAssignCharDB = DeepCopy(CHAR_DEFAULTS)
        else
            MergeDefaults(WowShiftAssignCharDB, CHAR_DEFAULTS)
        end

        NS.db     = WowShiftAssignDB
        NS.charDb = WowShiftAssignCharDB

        NS:FireCallback("ADDON_LOADED")
        frame:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        NS:FireCallback("PLAYER_LOGIN")

    elseif event == "PLAYER_LOGOUT" then
        NS:FireCallback("PLAYER_LOGOUT")
    end
end)

----------------------------------------------------------------------
-- Slash commands  /wsa  /shiftassign
----------------------------------------------------------------------
SLASH_WOWSHIFTASSIGN1 = "/wsa"
SLASH_WOWSHIFTASSIGN2 = "/shiftassign"

SlashCmdList["WOWSHIFTASSIGN"] = function(msg)
    msg = strtrim(msg or ""):lower()

    if msg == "" or msg == "show" or msg == "toggle" then
        NS:FireCallback("TOGGLE_WINDOW")

    elseif msg == "hide" then
        NS:FireCallback("HIDE_WINDOW")

    elseif msg == "settings" or msg == "config" then
        NS:FireCallback("SHOW_SETTINGS")

    elseif msg == "sync" or msg == "push" then
        NS:FireCallback("SYNC_PUSH_REQUEST")

    elseif msg == "request" or msg == "pull" then
        NS:FireCallback("SYNC_PULL_REQUEST")

    elseif msg == "reset" then
        StaticPopup_Show("WOWSHIFTASSIGN_RESET_ALL")

    else
        NS:Print("v" .. NS.version .. " commands:")
        print("  /wsa            - toggle main window")
        print("  /wsa settings   - open settings panel")
        print("  /wsa sync       - broadcast assignments to the raid")
        print("  /wsa request    - request assignments from the raid")
        print("  /wsa reset      - wipe ALL data (confirm)")
    end
end

----------------------------------------------------------------------
-- Static popup for "reset all" confirmation
----------------------------------------------------------------------
StaticPopupDialogs["WOWSHIFTASSIGN_RESET_ALL"] = {
    text = "Reset ALL WowShiftAssign data?\nThis cannot be undone.",
    button1 = "Yes, Reset",
    button2 = "Cancel",
    OnAccept = function()
        local pos = NS.db and NS.db.settings.minimapPos or 215
        WowShiftAssignDB = DeepCopy(DEFAULTS)
        WowShiftAssignDB.settings.minimapPos = pos
        NS.db = WowShiftAssignDB
        NS:FireCallback("DATA_UPDATED")
        NS:Print("All data has been reset.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
