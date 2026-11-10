-- The core of the first version: the saved tables are read whatever they hold, the saved
-- language wins over the client's, and /sgf answers with its commands.

local addon = require("addon")

local function login(locale, world)
    local ns = addon.load(locale, world)
    FIRE("PLAYER_LOGIN")
    return ns
end

-- CHAT belongs to the mock's globals: a spec empties it, never replaces it
local function clearChat()
    for i = #CHAT, 1, -1 do CHAT[i] = nil end
end

local function said(text)
    for _, line in ipairs(CHAT) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

describe("the saved variables", function()
    it("start from nothing", function()
        login("enUS")
        assert.is_table(SmartGroupFilterDB)
        assert.is_table(SmartGroupFilterGlobalDB)
        assert.are.equal(1, SmartGroupFilterDB.dbVersion)
    end)

    it("survive a damaged file: a wrong type is replaced, an unknown language dropped", function()
        login("enUS", { db = "broken", globalDB = { language = "xxXX" } })
        assert.is_table(SmartGroupFilterDB)
        assert.is_nil(SmartGroupFilterGlobalDB.language)
    end)
end)

describe("the window background", function()
    local function opacity(saved)
        login("enUS", { db = { dbVersion = 1, windowOpacity = saved } })
        return SmartGroupFilterDB.windowOpacity
    end

    it("starts at today's look in a version-1 table without it", function()
        login("enUS", { db = { dbVersion = 1, allowDouble = true } })
        assert.are.equal(60, SmartGroupFilterDB.windowOpacity)
        assert.are.equal(1, SmartGroupFilterDB.dbVersion)
        assert.is_true(SmartGroupFilterDB.allowDouble)
    end)

    it("keeps a saved value over a login", function()
        assert.are.equal(80, opacity(80))
        assert.are.equal(0, opacity(0))
        assert.are.equal(100, opacity(100))
    end)

    it("rounds a fraction and drops what is out of range or no number", function()
        assert.are.equal(72, opacity(72.4))
        assert.are.equal(73, opacity(72.6))
        assert.are.equal(60, opacity(-1))
        assert.are.equal(60, opacity(101))
        assert.are.equal(60, opacity("80"))
        assert.are.equal(60, opacity(0 / 0))
    end)
end)

describe("the language", function()
    it("follows the client", function()
        local ns = login("deDE")
        assert.are.equal("deDE", ns.GetLocaleCode())
        assert.is_true(said("Version 0.1.0 geladen."))
    end)

    it("takes the saved choice over the client's, before the first chat line", function()
        local ns = login("deDE", { globalDB = { language = "frFR" } })
        assert.are.equal("frFR", ns.GetLocaleCode())
        assert.are.equal(1, #CHAT)
        assert.is_true(said("Version 0.1.0 chargée."))
    end)

    it("re-renders a registered text on a switch", function()
        local ns = login("enUS")
        local text = { SetText = function(self, s) self.value = s end }
        ns.SetL(text, "CMD_HELP")
        assert.are.equal("Show this list", text.value)
        ns.ApplyLanguage("deDE")
        assert.are.equal("Diese Liste anzeigen", text.value)
    end)
end)

describe("/sgf", function()
    it("is the command", function()
        login("enUS")
        assert.are.equal("/sgf", SLASH_SMARTGROUPFILTER1)
    end)

    it("lists its commands, alone and with help", function()
        login("enUS")
        for _, msg in ipairs({ "", "help", "  HELP " }) do
            clearChat()
            SlashCmdList.SMARTGROUPFILTER(msg)
            assert.is_true(said("Chat commands:"), msg)
            assert.is_true(said("/sgf help"), msg)
        end
    end)

    it("names the help for an unknown command", function()
        login("enUS")
        clearChat()
        SlashCmdList.SMARTGROUPFILTER("nonsense")
        assert.is_true(said("Unknown command."))
        assert.is_false(said("Chat commands:"))
    end)
end)
