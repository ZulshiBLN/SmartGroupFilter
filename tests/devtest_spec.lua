-- /sgf test is for development only (2026-11-11): DevTest.lua is loaded by the TOC
-- between #@do-not-package@ markers and left out by .pkgmeta, so a release lacks it.

local addon = require("addon")

local function chat()
    return table.concat(CHAT, "\n")
end

describe("the development test", function()
    it("is loaded between the packager's markers and left out of the package", function()
        local toc = addon.read("SmartGroupFilter/SmartGroupFilter.toc")
        assert.truthy(toc:find("#@do%-not%-package@\r?\nDevTest%.lua\r?\n#@end%-do%-not%-package@"))
        assert.truthy(addon.read(".pkgmeta"):find("%- SmartGroupFilter/DevTest%.lua"))
    end)

    it("answers /sgf test and is in the help of a development checkout", function()
        addon.load("enUS")
        FIRE("PLAYER_LOGIN")
        SlashCmdList.SMARTGROUPFILTER("help")
        assert.truthy(chat():find("/sgf test", 1, true))
    end)

    it("is missing from a release: no help line, and /sgf test is unknown", function()
        local ns = addon.load("enUS", { release = true })
        FIRE("PLAYER_LOGIN")
        assert.is_nil(ns.DryRun)
        SlashCmdList.SMARTGROUPFILTER("help")
        assert.falsy(chat():find("/sgf test", 1, true))
        SlashCmdList.SMARTGROUPFILTER("test")
        assert.truthy(chat():find("Unknown command", 1, true) or chat():find("unknown", 1, true))
    end)

    -- Inside an instance the results list is secret (ruleset plan 2026-11-15-pre-release-cleanup)
    it("runs with a secret results list and errors nowhere", function()
        addon.load("enUS")
        FIRE("PLAYER_LOGIN")
        STATE.activities[800] = { minLevelSuggestion = 20, maxLevelSuggestion = 30, fullName = "Shadowfang Keep" }
        STATE.activeEntry = { activityIDs = { 800 } }
        LFGBrowseFrame.searching = false
        FIRE("LFG_LIST_SEARCH_RESULTS_RECEIVED")
        C_LFGList.GetFilteredSearchResults = function() return 6, SECRET() end
        assert.has_no.errors(function() SlashCmdList.SMARTGROUPFILTER("test") end)
        assert.truthy(chat():find("Not chosen:", 1, true))
    end)
end)
