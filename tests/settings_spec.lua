-- The panel's settings, read at login whatever the saved file holds (ruleset plan
-- 2026-11-10-panel-filter-build, -IMPLEMENTATION "Settings").

local addon = require("addon")

local function login(db)
    local ns = addon.load("enUS", { db = db })
    FIRE("PLAYER_LOGIN")
    return ns, SmartGroupFilterDB
end

local function joined(list) return table.concat(list, " ") end

describe("the settings", function()
    it("start with the decided defaults", function()
        local _, db = login()
        assert.is_false(db.allowDouble)
        assert.is_true(db.allowSameArmor)
        assert.are.equal("PALADIN WARRIOR DRUID", joined(db.order.TANK))
        assert.are.equal("PRIEST DRUID SHAMAN PALADIN", joined(db.order.HEALER))
        assert.are.equal("MAGE WARLOCK ROGUE WARRIOR SHAMAN PALADIN DRUID PRIEST HUNTER", joined(db.order.DAMAGER))
        assert.are.same({ TANK = {}, HEALER = {}, DAMAGER = {} }, db.excluded)
    end)

    it("keep a valid saved order and exclusions", function()
        local _, db = login({
            order = { TANK = { "DRUID", "PALADIN", "WARRIOR" } },
            excluded = { HEALER = { SHAMAN = true } },
            allowDouble = true, filterOn = false, -- saved by earlier builds
        })
        assert.are.equal("DRUID PALADIN WARRIOR", joined(db.order.TANK))
        assert.is_true(db.excluded.HEALER.SHAMAN)
        assert.is_true(db.allowDouble)
        assert.is_nil(db.filterOn) -- Reset Filter's "off" is not kept across logins
    end)

    it("reset an order that misses, repeats or adds a class", function()
        local _, db = login({ order = {
            TANK = { "PALADIN", "WARRIOR" },
            HEALER = { "PRIEST", "PRIEST", "SHAMAN", "PALADIN" },
            DAMAGER = "broken",
        } })
        assert.are.equal("PALADIN WARRIOR DRUID", joined(db.order.TANK))
        assert.are.equal("PRIEST DRUID SHAMAN PALADIN", joined(db.order.HEALER))
        assert.are.equal(9, #db.order.DAMAGER)
        local _, db2 = login({ order = { TANK = { "PALADIN", "WARRIOR", "DRUID", "MAGE" } } })
        assert.are.equal("PALADIN WARRIOR DRUID", joined(db2.order.TANK))
    end)

    it("drop exclusions of unknown roles, of classes the role cannot take, and non-true values", function()
        local _, db = login({ excluded = {
            TANK = { MAGE = true, WARRIOR = "yes", PALADIN = true },
            ROGUE = { MAGE = true },
            HEALER = "broken",
        } })
        assert.are.same({ PALADIN = true }, db.excluded.TANK)
        assert.are.same({}, db.excluded.HEALER)
        assert.is_nil(db.excluded.ROGUE)
    end)

    it("reset options of the wrong type", function()
        local _, db = login({ allowDouble = 1, allowSameArmor = {} })
        assert.is_false(db.allowDouble)
        assert.is_true(db.allowSameArmor)
    end)
end)
