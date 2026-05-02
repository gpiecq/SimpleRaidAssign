----------------------------------------------------------------------
-- SimpleRaidAssign  -  Core.lua
-- Addon initialisation, SavedVariables defaults, event bus, slash cmds
----------------------------------------------------------------------
local ADDON_NAME, NS = ...
NS.version = "1.2.0"

----------------------------------------------------------------------
-- Default saved-variables template (account-wide)
----------------------------------------------------------------------
local DEFAULTS = {
    -- Top-level container: a "raid" is a named plan that groups multiple
    -- boss encounters together (e.g. "SSC Tuesday Farm").
    --
    -- raids[raidKey] = {
    --     name           = "SSC Tuesday Farm",
    --     createdAt      = <timestamp>,
    --     updatedAt      = <timestamp>,
    --     createdBy      = "Playername",
    --     updatedBy      = "Playername",
    --     notes          = "",
    --     encounters     = {
    --         [encounterKey] = {
    --             name         = "Lady Vashj",
    --             instance     = "Serpentshrine Cavern",
    --             attributions = {
    --                 [attribId] = {
    --                     marker  = nil | 1..8,  -- raid target icon index (optional)
    --                     players = { "PlayerA", "PlayerB", ... },
    --                     context = "Tanks" | "Kick phase 1" | ... (free text),
    --                     note    = "multi-line free text for extra detail",
    --                 },
    --             },
    --             order    = { attribId1, ... },  -- attribution display order
    --             updated  = <timestamp>,
    --             updatedBy = "Playername",
    --         },
    --     },
    --     encounterOrder = { encKey1, encKey2, ... },  -- boss display order
    -- }
    raids = {},

    settings = {
        autoBroadcast    = true,      -- push changes to raid automatically
        acceptIncoming   = true,      -- accept incoming syncs
        notifyOnSync     = true,      -- chat message when receiving updates
        lastRaid         = nil,       -- last raid shown in the UI
        lastEncounter    = nil,       -- last boss selected within lastRaid
        windowPos        = { point = "CENTER", x = 0, y = 0 },
        minimapPos       = 215,       -- angle on minimap edge
        announceChannel  = "RAID_WARNING", -- RAID / RAID_WARNING / PARTY / SAY / GUILD
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
    print("|cff00ccffSimpleRaidAssign:|r " .. tostring(msg))
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
        if not SimpleRaidAssignDB then
            SimpleRaidAssignDB = DeepCopy(DEFAULTS)
        else
            MergeDefaults(SimpleRaidAssignDB, DEFAULTS)
        end

        -- Per-character saved variables
        if not SimpleRaidAssignCharDB then
            SimpleRaidAssignCharDB = DeepCopy(CHAR_DEFAULTS)
        else
            MergeDefaults(SimpleRaidAssignCharDB, CHAR_DEFAULTS)
        end

        NS.db     = SimpleRaidAssignDB
        NS.charDb = SimpleRaidAssignCharDB

        NS:FireCallback("ADDON_LOADED")
        frame:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        NS:FireCallback("PLAYER_LOGIN")

    elseif event == "PLAYER_LOGOUT" then
        NS:FireCallback("PLAYER_LOGOUT")
    end
end)

----------------------------------------------------------------------
-- Slash commands  /sra  /simpleraidassign
----------------------------------------------------------------------
SLASH_SIMPLERAIDASSIGN1 = "/sra"
SLASH_SIMPLERAIDASSIGN2 = "/simpleraidassign"

SlashCmdList["SIMPLERAIDASSIGN"] = function(msg)
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
        StaticPopup_Show("SIMPLERAIDASSIGN_RESET_ALL")

    else
        NS:Print("v" .. NS.version .. " commands:")
        print("  /sra            - toggle main window")
        print("  /sra settings   - open settings panel")
        print("  /sra sync       - broadcast assignments to the raid")
        print("  /sra request    - request assignments from the raid")
        print("  /sra reset      - wipe ALL data (confirm)")
    end
end

----------------------------------------------------------------------
-- Static popup for "reset all" confirmation
----------------------------------------------------------------------
StaticPopupDialogs["SIMPLERAIDASSIGN_RESET_ALL"] = {
    text = "Reset ALL SimpleRaidAssign data?\nThis cannot be undone.",
    button1 = "Yes, Reset",
    button2 = "Cancel",
    OnAccept = function()
        local pos = NS.db and NS.db.settings.minimapPos or 215
        SimpleRaidAssignDB = DeepCopy(DEFAULTS)
        SimpleRaidAssignDB.settings.minimapPos = pos
        NS.db = SimpleRaidAssignDB
        NS:FireCallback("DATA_UPDATED")
        NS:Print("All data has been reset.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
