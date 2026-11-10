-- The rules of the filter and of Build Group (ruleset plan 2026-11-10-panel-filter-build,
-- -IMPLEMENTATION "Definitions"). Logic.lua calls no client function, so these specs feed it
-- plain tables.

local addon = require("addon")

local ns, db
local RANGE = { min = 20, max = 30 }

-- The settings as a login leaves them: the defaults. A spec changes db's fields, never the
-- global itself (busted gives each spec its own globals, which the addon never sees).
before_each(function()
    ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN")
    db = SmartGroupFilterDB
end)

-- A single player as Filter.lua hands him over
local function solo(name, class, level, roles, age)
    return {
        numMembers = 1, name = name, class = class, level = level, age = age or 0,
        roles = roles or {},
    }
end

local T, H, D = { tank = true }, { healer = true }, { dps = true }

describe("the filter test", function()
    it("drops delisted entries, groups too", function()
        local e = solo("A", "MAGE", 25, D)
        e.isDelisted = true
        assert.is_false(ns.Passes(e, db, RANGE))
        assert.is_false(ns.Passes({ numMembers = 3, isDelisted = true }, db, RANGE))
    end)

    it("keeps groups and the own listing", function()
        assert.is_true(ns.Passes({ numMembers = 3 }, db, RANGE))
        assert.is_true(ns.Passes({ numMembers = 1, hasSelf = true, level = 5 }, db, RANGE))
    end)

    it("keeps a single player within the level range only", function()
        assert.is_true(ns.Passes(solo("A", "MAGE", 20, D), db, RANGE))
        assert.is_true(ns.Passes(solo("A", "MAGE", 30, D), db, RANGE))
        assert.is_false(ns.Passes(solo("A", "MAGE", 19, D), db, RANGE))
        assert.is_false(ns.Passes(solo("A", "MAGE", 31, D), db, RANGE))
    end)

    it("needs a signed-up role whose row holds the class unexcluded", function()
        db.excluded.TANK.WARRIOR = true
        assert.is_false(ns.Passes(solo("A", "WARRIOR", 25, T), db, RANGE))
        assert.is_true(ns.Passes(solo("A", "WARRIOR", 25, { tank = true, dps = true }), db, RANGE))
        assert.is_false(ns.Passes(solo("A", "MAGE", 25, T), db, RANGE)) -- a mage is no tank
    end)

    it("takes a player with no role when any row holds his class", function()
        db.excluded.TANK.WARRIOR = true
        assert.is_true(ns.Passes(solo("A", "WARRIOR", 25), db, RANGE))
        db.excluded.DAMAGER.WARRIOR = true
        assert.is_false(ns.Passes(solo("A", "WARRIOR", 25), db, RANGE))
    end)

    it("keeps a single player whose class or level is unknown, as Blizzard shows him", function()
        assert.is_true(ns.Passes(solo("A", nil, 25, D), db, RANGE))
        assert.is_true(ns.Passes(solo("A", "MAGE", nil, D), db, RANGE))
        -- the client reports level 0 until the player's data has loaded
        assert.is_true(ns.Passes(solo("A", "MAGE", 0, D), db, RANGE))
    end)

    it("leaves out the own armor class while same armor is not allowed, by the player's level", function()
        assert.is_true(ns.Passes(solo("A", "PRIEST", 25, H), db, RANGE, "CLOTH"))
        db.allowSameArmor = false
        assert.is_false(ns.Passes(solo("A", "PRIEST", 25, H), db, RANGE, "CLOTH"))
        assert.is_true(ns.Passes(solo("A", "DRUID", 25, H), db, RANGE, "CLOTH"))
        local wide = { min = 1, max = 60 }
        assert.is_true(ns.Passes(solo("A", "HUNTER", 39, D), db, wide, "MAIL"))
        assert.is_false(ns.Passes(solo("A", "HUNTER", 40, D), db, wide, "MAIL"))
    end)
end)

describe("the armor class", function()
    it("follows class and level", function()
        assert.are.equal("CLOTH", ns.ArmorOf("MAGE", 10))
        assert.are.equal("LEATHER", ns.ArmorOf("ROGUE", 50))
        assert.are.equal("LEATHER", ns.ArmorOf("HUNTER", 39))
        assert.are.equal("MAIL", ns.ArmorOf("HUNTER", 40))
        assert.are.equal("MAIL", ns.ArmorOf("WARRIOR", 39))
        assert.are.equal("PLATE", ns.ArmorOf("PALADIN", 40))
    end)
end)

describe("the choice of invites", function()
    local ME = { class = "MAGE", level = 25, roles = D }

    local function choose(candidates, over)
        local state = {
            own = ME, members = {}, placed = {}, numGroupMembers = 0,
            candidates = candidates, db = db, range = RANGE,
        }
        for k, v in pairs(over or {}) do state[k] = v end
        return ns.ChooseInvites(state)
    end

    local function names(list)
        local out = {}
        for i, c in ipairs(list or {}) do out[i] = c.name .. ":" .. c.role end
        return table.concat(out, " ")
    end

    it("fills tank, healer and two damage around a damage dealer, by priority", function()
        local list = choose({
            solo("War", "WARRIOR", 25, T), solo("Pal", "PALADIN", 25, T),
            solo("Dru", "DRUID", 25, H), solo("Pri", "PRIEST", 25, H),
            solo("Hun", "HUNTER", 25, D), solo("Wlk", "WARLOCK", 25, D), solo("Rog", "ROGUE", 25, D),
        })
        assert.are.equal("Pal:TANK Pri:HEALER Wlk:DAMAGER Rog:DAMAGER", names(list))
    end)

    it("takes the highest level of a class, then the longest wait", function()
        local list = choose({
            solo("Low", "PALADIN", 21, T), solo("High", "PALADIN", 28, T),
            solo("Old", "PRIEST", 25, H, 50), solo("New", "PRIEST", 25, H, 10),
        })
        assert.are.equal("High:TANK Old:HEALER", names(list))
    end)

    it("takes players with no role only for places still open after everyone signed up", function()
        local list = choose({
            solo("NoRole", "PALADIN", 30), solo("War", "WARRIOR", 21, T),
            solo("Pri", "PRIEST", 25, H), solo("NoRole2", "WARLOCK", 25),
        })
        -- the warrior tank is signed up: he goes before the higher-priority paladin without
        -- role, who only fills a damage place left open - after the warlock, by the damage row
        assert.are.equal("War:TANK Pri:HEALER NoRole2:DAMAGER NoRole:DAMAGER", names(list))
    end)

    it("allows no class twice, self included, unless double classes are on - then two", function()
        local c = { solo("M1", "MAGE", 25, D), solo("M2", "MAGE", 24, D), solo("Wlk", "WARLOCK", 25, D) }
        assert.are.equal("Wlk:DAMAGER", names(choose(c)))
        db.allowDouble = true
        assert.are.equal("M1:DAMAGER Wlk:DAMAGER", names(choose(c)))
    end)

    it("skips the own armor class when same armor is not allowed, by the candidate's level", function()
        db.allowSameArmor = false
        local list = choose({
            solo("Pri", "PRIEST", 25, H), solo("Dru", "DRUID", 25, H),
            solo("Hun39", "HUNTER", 39, D), solo("Wlk", "WARLOCK", 25, D),
        }, { own = { class = "SHAMAN", level = 45, roles = D }, range = { min = 1, max = 60 } })
        -- own armor mail: cloth priest and warlock fine, the leather hunter below 40 too
        assert.are.equal("Pri:HEALER Wlk:DAMAGER Hun39:DAMAGER", names(list))
        list = choose({ solo("Pri", "PRIEST", 25, H), solo("Dru", "DRUID", 25, H) })
        assert.are.equal("Dru:HEALER", names(list)) -- own mage wears cloth: the priest is skipped
    end)

    it("skips excluded classes", function()
        db.excluded.TANK.PALADIN = true
        assert.are.equal("War:TANK", names(choose({ solo("Pal", "PALADIN", 25, T), solo("War", "WARRIOR", 25, T) })))
    end)

    it("takes the rarest own role when listed with several", function()
        local list = choose({ solo("Pal", "PALADIN", 25, T), solo("Pri", "PRIEST", 25, H) },
            { own = { class = "DRUID", level = 25, roles = { tank = true, healer = true } } })
        assert.are.equal("Pri:HEALER", names(list))
    end)

    it("chooses nothing without an own role", function()
        local list, why = choose({ solo("Pal", "PALADIN", 25, T) }, { own = { class = "MAGE", level = 25, roles = {} } })
        assert.is_nil(list)
        assert.are.equal("NO_OWN_ROLE", why)
    end)

    it("fills only free places; members get no role's place", function()
        local list = choose({
            solo("Pal", "PALADIN", 25, T), solo("Pri", "PRIEST", 25, H),
            solo("Wlk", "WARLOCK", 25, D), solo("Rog", "ROGUE", 25, D),
        }, { numGroupMembers = 3, members = { { name = "X", class = "HUNTER", level = 25 }, { name = "Y", class = "SHAMAN", level = 25 } } })
        assert.are.equal("Pal:TANK Pri:HEALER", names(list))
    end)

    it("keeps an invited player's place, so the next choice takes the next role", function()
        local placed = { Pal = { role = "TANK", class = "PALADIN", level = 25 } }
        local list = choose({ solo("War", "WARRIOR", 25, T), solo("Pri", "PRIEST", 25, H) }, { placed = placed })
        assert.are.equal("Pri:HEALER", names(list))
    end)

    it("counts a placed player who joined as a member, not twice", function()
        local placed = { Pal = { role = "TANK", class = "PALADIN", level = 25, joined = true } }
        local list = choose({
            solo("Pri", "PRIEST", 25, H), solo("Wlk", "WARLOCK", 25, D), solo("Rog", "ROGUE", 25, D),
            solo("Hun", "HUNTER", 25, D),
        }, { placed = placed, numGroupMembers = 2, members = { { name = "Pal", class = "PALADIN", level = 25 } } })
        assert.are.equal("Pri:HEALER Wlk:DAMAGER Rog:DAMAGER", names(list))
    end)

    it("takes candidates by the filter's rules even when the Filter is off", function()
        ns.ResetFilter()
        local list = choose({ solo("Pal19", "PALADIN", 19, T), solo("War", "WARRIOR", 25, T) })
        assert.are.equal("War:TANK", names(list))
    end)

    it("never takes a candidate without name, class or level, or one already placed", function()
        local list = choose({
            solo(nil, "PALADIN", 25, T), solo("NoClass", nil, 25, T), solo("Pal", "PALADIN", 25, T),
            solo("War", "WARRIOR", 25, T),
        }, { placed = { Pal = { role = "HEALER", class = "PALADIN", level = 25 } } })
        assert.are.equal("War:TANK", names(list))
    end)
end)
