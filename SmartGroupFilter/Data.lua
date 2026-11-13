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
-- How many players one click invites: one click may send several invites (checked in game)
D.INVITES_PER_CLICK = 5

-- Search results older than this, in seconds, are searched anew before Build Group invites
-- (Michel, 2026-11-11)
D.LIST_FRESH_SECONDS = 30

-- After a Check Roles click, how long answers are awaited before a member's assigned role
-- counts, in seconds: confirming the preselected role sends no event (Michel, 2026-11-11)
D.ROLE_WAIT = 15

-- The whisper to a player whose sign-up is ambiguous (ruleset plan 2026-11-11-build-dungeon).
-- English always - the receiver's language is unknown - so not in Locales.lua; the dungeon's
-- name comes from the client.
D.WHISPER_ROLE = "%s for %s?"
D.WHISPER_DUNGEON = "You want to join for %s?"
D.WHISPER_ROLE_NAMES = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }

-- The panel's options and their defaults. panelShown: the side tab's switch.
D.OPTION_DEFAULTS = { allowDouble = false, allowSameArmor = true, panelShown = true, hideMinimap = false }

-- The minimap button's place on its circle, degrees; 225 = bottom left, as SimpleConjureBar
D.MINIMAP_ANGLE = 225

-- The panel's and the report's background (%), 0 invisible to 100 solid: 60 shows the dialog
-- texture as it always was - the sisters matched it to a black square of 60 % in game (ruleset
-- plan 2026-11-11-window-opacity). Not in OPTION_DEFAULTS: InitDB forces those to booleans.
D.WINDOW_OPACITY_TODAY = 60

-- The project's logo, shipped as Media/Logo.tga: the panel's portrait (cut to the medallion)
D.LOGO = "Interface\\AddOns\\SmartGroupFilter\\Media\\Logo"
-- The portrait's shift from the template's place, x and y in px: left and up (Michel, in game)
D.PORTRAIT_NUDGE = { -2, 2 }
-- List Self's pointer on Blizzard's eye tab: the modern client's proc loop, as
-- SmartBlessingBar's button glow - Blizzard's flipbook atlas of 6 x 5 cells, 30 frames, 1.4
-- times the tab, one loop a second (Blizzard's own speed)
D.GLOW_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
D.GLOW_ROWS, D.GLOW_COLUMNS, D.GLOW_FRAMES = 6, 5, 30
D.GLOW_SCALE = 1.4
D.GLOW_SECONDS_PER_LOOP = 1
-- The side tab's icon: the full logo with its own gold ring (Media/Tab.tga)
D.TAB_ICON = "Interface\\AddOns\\SmartGroupFilter\\Media\\Tab"

---------------------------------------------------------------------------
-- Bug report (ruleset plan 2026-11-10-extras, phase 4; mechanics from SimpleConjureBar)
---------------------------------------------------------------------------
-- Where a bug happened, as the report form offers it; the report carries the key, the form
-- the text AREA_<key>
D.REPORT_AREAS = { "FILTER", "PRIORITIES", "BUILD", "PANEL", "MINIMAP", "SETTINGS", "LANGUAGE",
    "COMBAT", "OTHER" }

-- The settings a report names, sorted: the options, the minimap's place and the schema
-- version. The rows' order and exclusions are tables, reported apart.
D.REPORT_SETTINGS = { "dbVersion", "minimapAngle", "windowOpacity" }
for key in pairs(D.OPTION_DEFAULTS) do D.REPORT_SETTINGS[#D.REPORT_SETTINGS + 1] = key end
table.sort(D.REPORT_SETTINGS)

-- The fields a bug report holds, one pattern per kind of line, and nothing else: a spec checks
-- every line of a report against this list. A new field needs an entry here and a line in
-- README's privacy section first.
D.REPORT_FIELDS = {
    { pattern = "^$" },
    { pattern = "^## SmartGroupFilter bug report$" },
    { pattern = "^%*%*Description:%*%* " },                 -- player's text, filtered
    { pattern = "^%*%*Area:%*%* %u+$" },
    { pattern = "^%*%*Details:%*%* " },                     -- player's text, filtered
    { pattern = "^%- Addon version: [%w%.%-]+$" },
    { pattern = "^%- Client: [%w%.]+ %(build %w+, interface %d+%)$" },
    { pattern = "^%- Client locale: %a+, addon language: [%a<>:%d]+$" },
    { pattern = "^%- Character: %u+, level %d+%-%d+, %a+$" }, -- class token, level band, group kind
    { pattern = "^%- Settings: " },                         -- known keys, allowlisted values
    { pattern = "^%*%*Lua errors" },
    { pattern = "^Error %d+ %(x%d+, [%w ,]+, combat: %a+%):$" },
    { pattern = "^```$" },
    { pattern = "^msg " },                                  -- error message, filtered
    { pattern = "^at " },                                   -- stack line, filtered
    { pattern = "^local " },                                -- locals rebuilt by allowlist
    { pattern = "^%*%*Last actions %(seconds since load%):%*%*$" },
    { pattern = "^log " },                                  -- generated, allowlisted values
    { pattern = "^%*%*State:%*%*$" },
    { pattern = "^state " },                                -- generated, allowlisted values
    { pattern = "^%[%.%.%. cut: the report is too long%]$" },
}
-- Characters that show nothing - zero-width ones, direction and format marks, fillers,
-- variation selectors, tag characters - as code point ranges. Inside or beside a name they
-- hide it: the report drops them, the decoder (tools/decode-report.lua) shows them as <U+XXXX>.
D.HIDDEN = {
    { 0xAD, 0xAD }, { 0x34F, 0x34F }, { 0x600, 0x605 }, { 0x61C, 0x61C }, { 0x6DD, 0x6DD },
    { 0x70F, 0x70F }, { 0x890, 0x891 }, { 0x8E2, 0x8E2 }, { 0x115F, 0x1160 }, { 0x17B4, 0x17B5 },
    { 0x180B, 0x180F }, { 0x200B, 0x200F }, { 0x2028, 0x202E }, { 0x2060, 0x206F },
    { 0x3164, 0x3164 }, { 0xFE00, 0xFE0F }, { 0xFEFF, 0xFEFF }, { 0xFFA0, 0xFFA0 },
    { 0xFFF0, 0xFFFB }, { 0x110BD, 0x110BD }, { 0x110CD, 0x110CD }, { 0x13430, 0x13455 },
    { 0x1BCA0, 0x1BCA3 }, { 0x1D173, 0x1D17A }, { 0xE0000, 0xE007F }, { 0xE0100, 0xE01EF },
}

D.REPORT_CUT = "[... cut: the report is too long]"
D.REPORT_MAX_BYTES = 20000 -- fits a GitHub issue (65,536) also as a code, and stays readable
-- Strings a report may carry as they are; any other string becomes <text:N>, its length only.
-- Class and role tokens, the build button's modes and the keys of its reasons join below.
D.REPORT_SAFE = {
    "^player$", "^target$", "^focus$", "^mouseover$", "^pet$", "^party%d$", "^raid%d%d?$",
    "^%-?%d+%.?%d*$", "^true$", "^false$", "^nil$",
    "^build$", "^refresh$", "^list$", "^none$", "^filter$", "^settings$",
    "^NEED_LISTING$", "^NOT_LEADER$", "^NOT_LEADER_LIST$", "^NO_OWN_ROLE$", "^GROUP_FULL$",
    "^NO_CANDIDATE$", "^LIST_OLD$", "^LIST_SELF_TIP$", "^roles$", "^ROLES_WAITING$",
    "^%l%l%u%u$", "^auto$",                                 -- locale codes
}
for _, class in ipairs(D.DEFAULT_ORDER.DAMAGER) do D.REPORT_SAFE[#D.REPORT_SAFE + 1] = "^" .. class .. "$" end
for _, role in ipairs(D.ROLES) do D.REPORT_SAFE[#D.REPORT_SAFE + 1] = "^" .. role .. "$" end
-- Where bug reports go: the issue form with one field for the code
-- (.github/ISSUE_TEMPLATE/bug_report.yml). Empty = no link; the window asks the user to send the
-- report to the addon author instead.
D.BUG_REPORT_URL = "https://github.com/ZulshiBLN/SmartGroupFilter/issues/new?template=bug_report.yml"
