-- The globals rule from the ruleset's code.md, made checkable: the addon may
-- write only what the client or the TOC must find by name.
std = "lua51"
max_line_length = false

-- CI installs Lua and LuaRocks into the checkout (.lua/, .luarocks/); their
-- code is not ours to check
exclude_files = { ".lua/**", ".luarocks/**" }

-- WoW's Lua has no file, process or module loading. lua51 would allow them.
not_globals = { "io", "os", "require", "dofile", "loadfile", "module" }

-- Every name the rule allows, including those no code writes yet: the rule is
-- encoded here whole, not grown file by file.
globals = {
    "SmartGroupFilterDB",
    "SmartGroupFilterGlobalDB",
    "SLASH_SMARTGROUPFILTER1",
    "SmartGroupFilter_OnCompartmentClick",
    "SmartGroupFilter_OnCompartmentEnter",
    "SmartGroupFilter_OnCompartmentLeave",
}

-- The WoW API the addon reads, listed by hand so a typo or a removed API is
-- reported instead of trusted. SlashCmdList is shared by every addon; only our
-- own entry may be written. A new API joins this list with the code that uses it.
read_globals = {
    "C_AddOns", "CreateFrame", "GetLocale",
    -- Group Finder (Blizzard_LFGVanilla_Browse.lua, Forever 1.60.1)
    "C_LFGList", "LFGBrowseFrame", "LFGBrowseUtil_SortSearchResults", "hooksecurefunc",
    "GetMaxPlayerLevel", "issecretvalue", "UnitClass", "UnitLevel", "C_Timer", "C_XMLUtil",
    -- The panel
    "LFGParentFrame", "UIParent", "GameTooltip", "GetCursorPosition", "PixelUtil", "CreateColor",
    "LFGParentFrameTab2_OnClick",
    -- Build Group
    "C_LFGListRoles", "C_PartyInfo", "GetNumGroupMembers", "IsInGroup", "UnitIsGroupLeader",
    "UnitIsGroupAssistant", "UnitName", "GetTime",
    "LOCALIZED_CLASS_NAMES_MALE", "TANK", "HEALER", "DAMAGER",
    SlashCmdList = { fields = { SMARTGROUPFILTER = { read_only = false } } },
}

-- Specs run in plain Lua 5.1 under busted, where file access is how they read
-- the addon's sources.
-- Checked together with the mock (as `luacheck .` and CI do), the mock's top-level
-- definitions count as defined here too; these lists keep a spec clean when it is
-- checked alone.
files["tests/"] = {
    std = "lua51+busted",
    -- Specs build the mocked world by changing STATE's fields
    globals = { "STATE" },
    read_globals = {
        "io", "require", "loadfile", "dofile", "os",
        -- What tests/helpers/mock.lua provides to drive the mocked client
        "FIRE", "CHAT", "RUNSCRIPT", "RUNTIMERS",
    },
}

-- The decoder runs in plain Lua 5.1 on a developer's machine, not in the client: it reads a
-- file and exits with a status (SmartBlessingBar's ruleset plan 2026-10-24-bug-report).
files["tools/"] = {
    std = "lua51",
    read_globals = { "io", "os", "arg", "debug", "dofile", "loadfile" },
}

-- The mock *is* the WoW API: defining client globals is its whole job.
files["tests/helpers/mock.lua"] = {
    std = "lua51",
    allow_defined_top = true,
    read_globals = { "io" },
    ignore = { "111", "112", "121", "122", "131", "212" },
}
