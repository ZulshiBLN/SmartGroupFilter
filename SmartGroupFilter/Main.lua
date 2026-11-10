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
    { cmd = "test", desc = "CMD_TEST" },
}

local function PrintHelp()
    ns.Print(L.HELP_HEADER)
    for _, c in ipairs(COMMANDS) do
        print("   |cffffd100" .. D.SLASH .. " " .. c.cmd .. "|r - " .. L[c.desc])
    end
end

SlashCmdList.SMARTGROUPFILTER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" or msg == "help" then
        PrintHelp()
    elseif msg == "test" then
        ns.DryRun()
    else
        ns.Print(L.CMD_UNKNOWN:format("|cffffd100" .. D.SLASH .. " help|r"))
    end
end
