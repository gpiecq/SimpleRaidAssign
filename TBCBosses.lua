----------------------------------------------------------------------
-- SimpleRaidAssign  -  TBCBosses.lua
-- Reference data: TBC raid instances and their bosses, used by the
-- "Add Boss" dropdown in the Raid Editor.
----------------------------------------------------------------------
local _, NS = ...

local TBCBosses = {}
NS.TBCBosses = TBCBosses

----------------------------------------------------------------------
-- Ordered list of instances, each with an ordered list of bosses.
-- Order matches typical raid progression.
----------------------------------------------------------------------
TBCBosses.Instances = {
    {
        key   = "kara",
        name  = "Karazhan",
        bosses = {
            "Attumen the Huntsman",
            "Moroes",
            "Maiden of Virtue",
            "Opera Event",
            "The Curator",
            "Terestian Illhoof",
            "Shade of Aran",
            "Netherspite",
            "Chess Event",
            "Prince Malchezaar",
            "Nightbane",
        },
    },
    {
        key   = "gruul",
        name  = "Gruul's Lair",
        bosses = {
            "High King Maulgar",
            "Gruul the Dragonkiller",
        },
    },
    {
        key   = "mag",
        name  = "Magtheridon's Lair",
        bosses = {
            "Magtheridon",
        },
    },
    {
        key   = "ssc",
        name  = "Serpentshrine Cavern",
        bosses = {
            "Hydross the Unstable",
            "The Lurker Below",
            "Leotheras the Blind",
            "Fathom-Lord Karathress",
            "Morogrim Tidewalker",
            "Lady Vashj",
        },
    },
    {
        key   = "tk",
        name  = "The Eye (Tempest Keep)",
        bosses = {
            "Al'ar",
            "Void Reaver",
            "High Astromancer Solarian",
            "Kael'thas Sunstrider",
        },
    },
    {
        key   = "hyjal",
        name  = "Battle for Mount Hyjal",
        bosses = {
            "Rage Winterchill",
            "Anetheron",
            "Kaz'rogal",
            "Azgalor",
            "Archimonde",
        },
    },
    {
        key   = "bt",
        name  = "Black Temple",
        bosses = {
            "High Warlord Naj'entus",
            "Supremus",
            "Shade of Akama",
            "Teron Gorefiend",
            "Gurtogg Bloodboil",
            "Reliquary of Souls",
            "Mother Shahraz",
            "The Illidari Council",
            "Illidan Stormrage",
        },
    },
    {
        key   = "za",
        name  = "Zul'Aman",
        bosses = {
            "Nalorakk",
            "Akil'zon",
            "Jan'alai",
            "Halazzi",
            "Hex Lord Malacrass",
            "Zul'jin",
        },
    },
    {
        key   = "sunwell",
        name  = "Sunwell Plateau",
        bosses = {
            "Kalecgos",
            "Brutallus",
            "Felmyst",
            "The Eredar Twins",
            "M'uru",
            "Kil'jaeden",
        },
    },
}

----------------------------------------------------------------------
-- Build a flat lookup: bossName -> instanceName
----------------------------------------------------------------------
TBCBosses.BossToInstance = {}
for _, inst in ipairs(TBCBosses.Instances) do
    for _, bossName in ipairs(inst.bosses) do
        TBCBosses.BossToInstance[bossName] = inst.name
    end
end

function TBCBosses:GetInstanceOf(bossName)
    return self.BossToInstance[bossName]
end
