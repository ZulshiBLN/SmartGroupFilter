-- SmartGroupFilter - startup and chat commands

local _, ns = ...
local D, L = ns.D, ns.L

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    ns.InitDB()
    -- Saved language choice (account-wide), otherwise the client language. Applied before any
    -- chat output, so every message already uses the chosen language.
    local lang = SmartGroupFilterGlobalDB.language
    if lang then ns.ApplyLanguage(lang) end
    ns.Print(L.LOADED:format(ns.VERSION))
end)

---------------------------------------------------------------------------
-- Chat commands
---------------------------------------------------------------------------
SLASH_SMARTGROUPFILTER1 = D.SLASH

-- In the order the help lists them
local COMMANDS = {
    { cmd = "help", desc = "CMD_HELP" },
    { cmd = "minimap", desc = "CMD_MINIMAP" },
    { cmd = "test", desc = "CMD_TEST" },
    { cmd = "bug", desc = "CMD_BUG" },
}

local function PrintHelp()
    ns.Print(L.HELP_HEADER)
    for _, c in ipairs(COMMANDS) do
        print("   |cffffd100" .. D.SLASH .. " " .. c.cmd .. "|r - " .. L[c.desc])
    end
end

SlashCmdList.SMARTGROUPFILTER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    -- the bug report's log names a known command only: the rest could be anything
    local known = msg == "" and "help" or "other"
    for _, c in ipairs(COMMANDS) do
        if c.cmd == msg then known = msg end
    end
    ns.Log("command " .. known)
    if msg == "" or msg == "help" then
        PrintHelp()
    elseif msg == "minimap" then
        ns.ToggleMinimapButton()
    elseif msg == "test" then
        ns.DryRun()
    elseif msg == "bug" then
        -- the report says in the chat what a button click shows elsewhere (Report.lua)
        ns.fromCommand = true
        ns.OpenBugReport()
        ns.fromCommand = false
    else
        ns.Print(L.CMD_UNKNOWN:format("|cffffd100" .. D.SLASH .. " help|r"))
    end
    ns.LogSettings()
end
