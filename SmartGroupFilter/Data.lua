-- SmartGroupFilter - data
-- Constants and defaults. Every fact lives here once; other files point at it.

local _, ns = ...

local D = {}
ns.D = D

-- The shape of the saved settings. A change to it needs a plan and a migration in ns.InitDB()
-- (ruleset project.md). Version 1 got its first fields with the panel; 0.1.0 saved none.
D.DB_VERSION = 1

-- What the chat command is called; the help and the error message name it from here
D.SLASH = "/sgf"

---------------------------------------------------------------------------
-- Roles and classes (ruleset archive/decisions.md, 2026-11-09)
---------------------------------------------------------------------------
-- The order Build Group fills places in, and the order an own listing with several roles is
-- read in: the rarest role first
D.ROLES = { "TANK", "HEALER", "DAMAGER" }

-- The field of a Group Finder `lfgRoles` table that stands for each role
D.ROLE_FIELD = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

-- A dungeon group: 1 tank, 1 healer, 3 damage dealers. Raids come later.
D.GROUP_SIZE = 5
D.PLACES = { TANK = 1, HEALER = 1, DAMAGER = 3 }

-- The default priority of each row, which is also the set of classes able to fill the role.
-- SHAMAN is no tank in WoW Forever yet; once the game offers it, it joins the tank row here.
D.DEFAULT_ORDER = {
    TANK    = { "PALADIN", "WARRIOR", "DRUID" },
    HEALER  = { "PRIEST", "DRUID", "SHAMAN", "PALADIN" },
    DAMAGER = { "MAGE", "WARLOCK", "ROGUE", "WARRIOR", "SHAMAN", "PALADIN", "DRUID", "PRIEST", "HUNTER" },
}

-- role -> { classFilename = true }: which classes a role's row may hold
D.ROLE_CLASSES = {}
for role, order in pairs(D.DEFAULT_ORDER) do
    D.ROLE_CLASSES[role] = {}
    for _, class in ipairs(order) do D.ROLE_CLASSES[role][class] = true end
end

-- Class icons as Blizzard's Group Finder builds them; its own table is local to its file
D.CLASS_ATLAS = {}
for _, class in ipairs(D.DEFAULT_ORDER.DAMAGER) do
    D.CLASS_ATLAS[class] = "groupfinder-icon-class-" .. class:lower()
end

-- Armor by class: one kind, or { below, from } around D.ARMOR_LEVEL
D.ARMOR_LEVEL = 40
D.ARMOR = {
    MAGE = "CLOTH", PRIEST = "CLOTH", WARLOCK = "CLOTH",
    ROGUE = "LEATHER", DRUID = "LEATHER",
    HUNTER = { "LEATHER", "MAIL" }, SHAMAN = { "LEATHER", "MAIL" },
    WARRIOR = { "MAIL", "PLATE" }, PALADIN = { "MAIL", "PLATE" },
}

-- How many players of one class a group may hold, by "Allow double classes"
D.MAX_SAME_CLASS = { [false] = 1, [true] = 2 }

-- How long an invited player keeps his place before he joins, in seconds
D.HOLD_SECONDS = 120

-- The panel's options and their defaults. filterOn: off after Reset Filter until the next
-- change; panelShown: the side tab's switch - a hidden panel leaves Blizzard's list as it is.
D.OPTION_DEFAULTS = { filterOn = true, allowDouble = false, allowSameArmor = true, panelShown = true }

-- The project's logo, shipped as Media/Logo.tga: the panel's portrait (cut to the medallion)
D.LOGO = "Interface\\AddOns\\SmartGroupFilter\\Media\\Logo"
-- The portrait's shift from the template's place, x and y in px: left and up (Michel, in game)
D.PORTRAIT_NUDGE = { -2, 2 }
-- The side tab's icon: the full logo with its own gold ring (Media/Tab.tga)
D.TAB_ICON = "Interface\\AddOns\\SmartGroupFilter\\Media\\Tab"
