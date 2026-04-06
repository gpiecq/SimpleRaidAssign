----------------------------------------------------------------------
-- WowShiftAssign  -  AssignData.lua
-- Static data: role types, class colors, TBC encounter templates
----------------------------------------------------------------------
local _, NS = ...

local Data = {}
NS.Data = Data

----------------------------------------------------------------------
-- Built-in role types
-- Each role type has:
--   key       internal id (stable, used in DB)
--   label     display name
--   icon      texture path
--   color     {r, g, b}  (used by UI accents)
--   maxSlots  default slot count when creating a role from this type
----------------------------------------------------------------------
Data.RoleTypes = {
    { key = "tank",       label = "Tank",            icon = "Interface\\Icons\\Ability_Defend",                color = { 0.30, 0.55, 0.90 }, maxSlots = 2 },
    { key = "mainheal",   label = "Main Heal",       icon = "Interface\\Icons\\Spell_Holy_Heal",               color = { 0.27, 1.00, 0.27 }, maxSlots = 2 },
    { key = "tankheal",   label = "Tank Healer",     icon = "Interface\\Icons\\Spell_Holy_GreaterHeal",        color = { 0.45, 1.00, 0.55 }, maxSlots = 2 },
    { key = "raidheal",   label = "Raid Healer",     icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",  color = { 0.45, 0.95, 0.85 }, maxSlots = 3 },
    { key = "interrupt",  label = "Interrupt",       icon = "Interface\\Icons\\Spell_Frost_IceShock",          color = { 1.00, 0.50, 0.20 }, maxSlots = 3 },
    { key = "decurse",    label = "Decurse",         icon = "Interface\\Icons\\Spell_Nature_RemoveCurse",      color = { 0.65, 0.30, 0.85 }, maxSlots = 3 },
    { key = "dispel",     label = "Magic Dispel",    icon = "Interface\\Icons\\Spell_Holy_DispelMagic",        color = { 0.85, 0.65, 1.00 }, maxSlots = 3 },
    { key = "tranq",      label = "Tranq Shot",      icon = "Interface\\Icons\\Spell_Nature_Drowsy",           color = { 0.55, 0.85, 0.40 }, maxSlots = 2 },
    { key = "mc",         label = "Mind Control",    icon = "Interface\\Icons\\Spell_Shadow_ShadowWordDominate", color = { 0.85, 0.40, 0.85 }, maxSlots = 2 },
    { key = "kite",       label = "Kite",            icon = "Interface\\Icons\\Ability_Hunter_RunningShot",    color = { 1.00, 0.85, 0.30 }, maxSlots = 2 },
    { key = "carry",      label = "Carry / Pick-up", icon = "Interface\\Icons\\INV_Crate_02",                  color = { 0.95, 0.75, 0.40 }, maxSlots = 4 },
    { key = "cooldown",   label = "Raid Cooldown",   icon = "Interface\\Icons\\Spell_Holy_DivineProtection",   color = { 1.00, 0.84, 0.00 }, maxSlots = 4 },
    { key = "custom",     label = "Custom",          icon = "Interface\\Icons\\INV_Misc_QuestionMark",         color = { 0.70, 0.70, 0.70 }, maxSlots = 5 },
}

-- Build a key->entry index for fast lookups
Data.RoleTypeIndex = {}
for _, t in ipairs(Data.RoleTypes) do
    Data.RoleTypeIndex[t.key] = t
end

function Data:GetRoleType(key)
    return self.RoleTypeIndex[key] or self.RoleTypeIndex.custom
end

----------------------------------------------------------------------
-- Class colors (TBC client constants, with fallback)
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
    -- Prefer the live RAID_CLASS_COLORS table if available
    local rcc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if rcc then return rcc.r, rcc.g, rcc.b end
    local c = self.ClassColors[classFile]
    if c then return c[1], c[2], c[3] end
    return 0.7, 0.7, 0.7
end

----------------------------------------------------------------------
-- Encounter templates
-- Used when the user clicks "New from template" so they don't have to
-- recreate common roles for each boss. Templates are merely seeds; the
-- user is free to add/remove roles after creation.
----------------------------------------------------------------------
Data.EncounterTemplates = {
    {
        key      = "ssc_vashj",
        name     = "Lady Vashj",
        instance = "Serpentshrine Cavern",
        roles    = {
            { roleType = "tank",      label = "Main Tank" },
            { roleType = "tank",      label = "Strider Tank" },
            { roleType = "tankheal",  label = "MT Healers" },
            { roleType = "raidheal",  label = "Raid Healers" },
            { roleType = "carry",     label = "Tainted Core Runners" },
            { roleType = "kite",      label = "Tainted Elemental Kite" },
            { roleType = "interrupt", label = "Strider Interrupts" },
        },
    },
    {
        key      = "tk_kael",
        name     = "Kael'thas Sunstrider",
        instance = "The Eye",
        roles    = {
            { roleType = "tank",     label = "Main Tank" },
            { roleType = "tank",     label = "Weapon Tanks" },
            { roleType = "tankheal", label = "MT Healers" },
            { roleType = "raidheal", label = "Raid Healers" },
            { roleType = "decurse",  label = "Decursers (P3)" },
            { roleType = "dispel",   label = "Mind Control Dispels" },
            { roleType = "interrupt",label = "Pyroblast Interrupts" },
        },
    },
    {
        key      = "bt_illidan",
        name     = "Illidan Stormrage",
        instance = "Black Temple",
        roles    = {
            { roleType = "tank",     label = "Main Tank" },
            { roleType = "tank",     label = "Flame Tanks" },
            { roleType = "tankheal", label = "MT Healers" },
            { roleType = "raidheal", label = "Raid Healers" },
            { roleType = "kite",     label = "Parasite Kite" },
            { roleType = "cooldown", label = "Demon Form CDs" },
        },
    },
    {
        key      = "blank",
        name     = "Blank Encounter",
        instance = "Custom",
        roles    = {},
    },
}

function Data:GetTemplate(key)
    for _, t in ipairs(self.EncounterTemplates) do
        if t.key == key then return t end
    end
    return nil
end
