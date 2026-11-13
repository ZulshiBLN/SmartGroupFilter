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

-- A single player as Filter.lua hands him over, listed for dungeon 800 unless told otherwise
local function solo(name, class, level, roles, age, activities)
    return {
        numMembers = 1, name = name, class = class, level = level, age = age or 0,
        roles = roles or {}, activities = activities or { 800 },
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

describe("the target dungeon", function()
    local function state(candidates)
        return {
            own = { class = "MAGE", level = 25, roles = D }, members = {}, placed = {}, numGroupMembers = 0,
            candidates = candidates, db = db, range = RANGE,
        }
    end

    it("is the one own dungeon", function()
        assert.are.equal(801, ns.ChooseTarget(state({ solo("War", "WARRIOR", 25, T) }), { 801 }))
    end)

    it("is the own dungeon for which the most players would be chosen", function()
        local c = { solo("War", "WARRIOR", 25, T), solo("Pal", "PALADIN", 25, T, 0, { 801 }),
            solo("Pri", "PRIEST", 25, H, 0, { 801 }) }
        assert.are.equal(801, ns.ChooseTarget(state(c), { 800, 801 }))
    end)

    it("puts tank and healer places first: they are rare, damage dealers are not", function()
        -- 801 would get two damage dealers, 800 a tank and a healer; then 802 a tank, a healer
        -- and a damage dealer: as many rare places as 800 and more players
        local c = { solo("War", "WARRIOR", 25, T), solo("Pri", "PRIEST", 25, H),
            solo("Wlk", "WARLOCK", 25, D, 0, { 801 }), solo("Rog", "ROGUE", 25, D, 0, { 801 }) }
        assert.are.equal(800, ns.ChooseTarget(state(c), { 801, 800 }))
        c[#c + 1] = solo("Pal", "PALADIN", 25, T, 0, { 802 })
        c[#c + 1] = solo("Dru", "DRUID", 25, H, 0, { 802 })
        c[#c + 1] = solo("Hun", "HUNTER", 25, D, 0, { 802 })
        assert.are.equal(802, ns.ChooseTarget(state(c), { 801, 800, 802 }))
    end)

    it("goes to the listing's order on a tie", function()
        local c = { solo("War", "WARRIOR", 25, T), solo("Pal", "PALADIN", 25, T, 0, { 801 }) }
        assert.are.equal(800, ns.ChooseTarget(state(c), { 800, 801 }))
        assert.are.equal(801, ns.ChooseTarget(state(c), { 801, 800 }))
    end)
end)

describe("the choice of invites", function()
    local ME = { class = "MAGE", level = 25, roles = D }

    local function choose(candidates, over)
        local state = {
            own = ME, members = {}, placed = {}, numGroupMembers = 0,
            candidates = candidates, db = db, range = RANGE, dungeons = { 800 },
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

    it("takes candidates by the filter's rules after Reset Filter", function()
        ns.ResetFilter()
        local list = choose({ solo("Pal19", "PALADIN", 19, T), solo("War", "WARRIOR", 25, T) })
        assert.are.equal("War:TANK", names(list))
    end)

    it("takes only players listed for one of the given dungeons", function()
        local c = { solo("Pal", "PALADIN", 25, T, 0, { 801 }), solo("War", "WARRIOR", 25, T, 0, { 802, 800 }) }
        assert.are.equal("War:TANK", names(choose(c)))
        assert.are.equal("Pal:TANK", names(choose(c, { dungeons = { 800, 801 } })))
        assert.are.equal("", names(choose(c, { dungeons = {} })))
    end)

    it("takes no player whose dungeons are not loaded yet", function()
        local pal = solo("Pal", "PALADIN", 25, T)
        pal.activities = nil
        assert.are.equal("War:TANK", names(choose({ pal, solo("War", "WARRIOR", 25, T) })))
    end)

    it("never takes a candidate without name, class or level, or one already placed", function()
        local list = choose({
            solo(nil, "PALADIN", 25, T), solo("NoClass", nil, 25, T), solo("Pal", "PALADIN", 25, T),
            solo("War", "WARRIOR", 25, T),
        }, { placed = { Pal = { role = "HEALER", class = "PALADIN", level = 25 } } })
        assert.are.equal("War:TANK", names(list))
    end)
end)

-- The best fill (ruleset plan 2026-11-11-roles-and-places): every case of its -RESEARCH table,
-- run before the live test, with the fill the plan expects. Levels 30, range 1-60, dungeon 800.
describe("the best fill, case by case", function()
    local TH, TD, HD = { tank = true, healer = true }, { tank = true, dps = true }, { healer = true, dps = true }
    local ALL = { tank = true, healer = true, dps = true }
    local WIDE = { min = 1, max = 60 }

    local function p(name, class, roles, level, activities)
        return solo(name, class, level or 30, roles, 0, activities)
    end

    local function own(class, roles, level) return { class = class, level = level or 30, roles = roles } end

    local function fill(me, candidates, over)
        local state = { own = me, members = {}, placed = {}, numGroupMembers = 0, candidates = candidates,
            db = db, range = WIDE, dungeons = { 800 } }
        for k, v in pairs(over or {}) do state[k] = v end
        local list, why = ns.ChooseInvites(state)
        if not list then return "nil " .. why end
        local out = {}
        for i, c in ipairs(list) do out[i] = c.name .. ":" .. c.role end
        return table.concat(out, " ")
    end

    local function base()
        return { p("War", "WARRIOR", T), p("Pri", "PRIEST", H), p("Rog", "ROGUE", D), p("Hun", "HUNTER", D),
            p("Wlk", "WARLOCK", D), p("Mag", "MAGE", D) }
    end

    it("own role and class (O1-O8)", function()
        assert.are.equal("War:TANK Pri:HEALER Wlk:DAMAGER Rog:DAMAGER", fill(own("MAGE", D), base()))
        assert.are.equal("Pri:HEALER Mag:DAMAGER Wlk:DAMAGER Rog:DAMAGER", fill(own("WARRIOR", T), base()))
        assert.are.equal("War:TANK Mag:DAMAGER Wlk:DAMAGER Rog:DAMAGER", fill(own("PRIEST", H), base()))
        assert.are.equal("Pri:HEALER Mag:DAMAGER Wlk:DAMAGER Rog:DAMAGER", fill(own("PALADIN", TH), base()))
        assert.are.equal("Pri:HEALER Mag:DAMAGER Wlk:DAMAGER Rog:DAMAGER", fill(own("DRUID", ALL), base()))
        assert.are.equal("nil NO_OWN_ROLE", fill(own("HUNTER", {}), base()))
        assert.are.equal("War:TANK Mag:DAMAGER Wlk:DAMAGER Rog:DAMAGER", fill(own("SHAMAN", HD), base()))
        assert.are.equal("Pri:HEALER Mag:DAMAGER Wlk:DAMAGER", fill(own("WARRIOR", D), base())) -- class limit
    end)

    it("the roles candidates signed up for (R1-R10)", function()
        local me = own("MAGE", D)
        assert.are.equal("Pal:TANK Pri:HEALER Rog:DAMAGER",
            fill(me, { p("Pal", "PALADIN", TD), p("Pri", "PRIEST", H), p("Rog", "ROGUE", D) }))
        -- R2: the hybrid heals, so the tank-only warrior can tank
        assert.are.equal("War:TANK Pal:HEALER", fill(me, { p("Pal", "PALADIN", TH), p("War", "WARRIOR", T) }))
        assert.are.equal("Sha:HEALER Wlk:DAMAGER Rog:DAMAGER",
            fill(me, { p("Sha", "SHAMAN", HD), p("Rog", "ROGUE", D), p("Wlk", "WARLOCK", D), p("Hun", "HUNTER", D) }))
        assert.are.equal("Pri:HEALER Wlk:DAMAGER Rog:DAMAGER",
            fill(me, { p("Pri", "PRIEST", HD), p("Rog", "ROGUE", D), p("Wlk", "WARLOCK", D) }))
        assert.are.equal("War:TANK Rog:DAMAGER NoR:HEALER",
            fill(me, { p("NoR", "DRUID"), p("War", "WARRIOR", T), p("Rog", "ROGUE", D) }))
        assert.are.equal("Pri:HEALER NoR:TANK", fill(me, { p("NoR", "DRUID"), p("Pri", "PRIEST", H) }))
        assert.are.equal("Pal:TANK", fill(me, { p("War", "WARRIOR", T), p("Pal", "PALADIN", T) }))
        assert.are.equal("Pal:TANK NoR:HEALER", fill(me, { p("NoR", "DRUID"), p("Pal", "PALADIN", TH) }))
        -- R9: as R2 with a druid, third in the tank row
        assert.are.equal("Dru:TANK Pal:HEALER", fill(me, { p("Pal", "PALADIN", TH), p("Dru", "DRUID", T) }))
        -- R10: no-role players strictly last - the warrior only gets what the paladin left
        assert.are.equal("Pal:TANK NoR:DAMAGER", fill(me, { p("Pal", "PALADIN", TH), p("NoR", "WARRIOR") }))
    end)

    it("exclusions and row order (X1-X4)", function()
        local me = own("MAGE", D)
        db.excluded.TANK.PALADIN = true
        assert.are.equal("War:TANK Pal:HEALER", fill(me, { p("Pal", "PALADIN", TH), p("War", "WARRIOR", T) }))
        db.excluded.TANK.WARRIOR, db.excluded.TANK.DRUID = true, true
        assert.are.equal("Pri:HEALER", fill(me, { p("War", "WARRIOR", T), p("Pri", "PRIEST", H) }))
        db.excluded.TANK = {}
        db.excluded.DAMAGER.ROGUE = true
        assert.are.equal("Wlk:DAMAGER", fill(me, { p("Rog", "ROGUE"), p("Wlk", "WARLOCK", D) }))
        db.excluded.DAMAGER = {}
        db.order.TANK = { "DRUID", "WARRIOR", "PALADIN" }
        assert.are.equal("Dru:TANK",
            fill(me, { p("Pal", "PALADIN", T), p("War", "WARRIOR", T), p("Dru", "DRUID", T) }))
    end)

    it("double classes (D1-D2)", function()
        local c = { p("Mag", "MAGE", D), p("Wlk", "WARLOCK", D), p("Wl2", "WARLOCK", D, 29), p("PalT", "PALADIN", T),
            p("PalH", "PALADIN", H), p("Rog", "ROGUE", D) }
        assert.are.equal("PalT:TANK Wlk:DAMAGER Rog:DAMAGER", fill(own("MAGE", D), c))
        db.allowDouble = true
        assert.are.equal("PalT:TANK PalH:HEALER Mag:DAMAGER Wlk:DAMAGER", fill(own("MAGE", D), c))
    end)

    it("same armor class off (A1-A4)", function()
        db.allowSameArmor = false
        local c = { p("Pri", "PRIEST", H), p("Dru", "DRUID", H), p("Wlk", "WARLOCK", D), p("Rog", "ROGUE", D),
            p("War", "WARRIOR", T, 45), p("Pal", "PALADIN", T, 35), p("Hun", "HUNTER", D, 45) }
        assert.are.equal("Pal:TANK Dru:HEALER Rog:DAMAGER Hun:DAMAGER", fill(own("MAGE", D), c))
        assert.are.equal("Pal:TANK Pri:HEALER Wlk:DAMAGER Rog:DAMAGER", fill(own("WARRIOR", D, 45), c))
        assert.are.equal("Pri:HEALER Wlk:DAMAGER Rog:DAMAGER", fill(own("WARRIOR", D, 35), c))
        assert.are.equal("Pal:TANK Pri:HEALER Wlk:DAMAGER Hun:DAMAGER", fill(own("DRUID", D), c))
    end)

    it("level and dungeons (L1-L4)", function()
        local me = own("MAGE", D)
        assert.are.equal("Dru:TANK", fill(me, { p("War", "WARRIOR", T, 31), p("Pal", "PALADIN", T, 0),
            p("Dru", "DRUID", T, 26) }, { range = { min = 25, max = 30 } }))
        local unknown = p("Pal", "PALADIN", T)
        unknown.activities = nil
        assert.are.equal("War:TANK", fill(me, { unknown, p("War", "WARRIOR", T) }))
        assert.are.equal("War:TANK", fill(me, { p("Pal", "PALADIN", T, 30, { 801 }), p("War", "WARRIOR", T) }))
        assert.are.equal("Pal:TANK", fill(me, { p("Pal", "PALADIN", T, 30, { 800, 801 }) }))
    end)

    it("the group as it stands (G2-G4)", function()
        local me = own("MAGE", D)
        local c = { p("War", "WARRIOR", T), p("Pri", "PRIEST", H), p("Rog", "ROGUE", D), p("Wlk", "WARLOCK", D) }
        assert.are.equal("War:TANK", fill(me, c, { numGroupMembers = 4, members = {
            { name = "A", class = "HUNTER", level = 30 }, { name = "B", class = "SHAMAN", level = 30 },
            { name = "C", class = "DRUID", level = 30 } } }))
        assert.are.equal("Pri:HEALER Wlk:DAMAGER Rog:DAMAGER",
            fill(me, c, { placed = { X = { role = "TANK", class = "PALADIN", level = 30 } } }))
        assert.are.equal("War:TANK Pri:HEALER Rog:DAMAGER", fill(me, c, { numGroupMembers = 2,
            members = { { name = "Fr", class = "WARLOCK", level = 30 } } }))
    end)

    it("takes a filled place over an empty one before priority", function()
        -- tank and healer are both filled either way; the paladin tanks, the first place
        assert.are.equal("Pal:TANK NoR:HEALER", fill(own("MAGE", D), { p("NoR", "DRUID"), p("Pal", "PALADIN", TH) }))
        -- one rare place either way: the paladin as tank, not as healer, as tank comes first
        assert.are.equal("Pal:TANK", fill(own("MAGE", D), { p("Pal", "PALADIN", TH) }))
    end)

    it("keeps its search small with a hundred candidates", function()
        local classes = { "PALADIN", "WARRIOR", "DRUID", "PRIEST", "SHAMAN", "ROGUE", "WARLOCK", "HUNTER", "MAGE" }
        local roleSets = { T, H, D, TH, TD, HD, ALL }
        local c = {}
        for i = 1, 100 do
            c[i] = p("P" .. i, classes[i % #classes + 1], roleSets[i % #roleSets + 1], 20 + i % 11)
        end
        local state = { own = own("MAGE", D), members = {}, placed = {}, numGroupMembers = 0, candidates = c,
            db = db, range = WIDE, dungeons = { 800 } }
        local list, _, info = ns.ChooseInvites(state)
        assert.are.equal(4, #list)
        assert.is_true(info.tried <= 5000, "fills tried: " .. tostring(info.tried))
        db.allowDouble = true
        list, _, info = ns.ChooseInvites(state)
        assert.are.equal(4, #list)
        assert.is_true(info.tried <= 20000, "fills tried: " .. tostring(info.tried))
    end)
end)

-- Members' known roles (ruleset plan 2026-11-11-roles-and-places, phase 2)
describe("members' known roles", function()
    local WIDE = { min = 1, max = 60 }
    local function fill(over)
        local state = { own = { class = "MAGE", level = 30, roles = D }, members = {}, placed = {},
            numGroupMembers = 0, db = db, range = WIDE, dungeons = { 800 },
            candidates = { solo("War", "WARRIOR", 30, T), solo("Pri", "PRIEST", 30, H),
                solo("Rog", "ROGUE", 30, D), solo("Wlk", "WARLOCK", 30, D) } }
        for k, v in pairs(over) do state[k] = v end
        local list = ns.ChooseInvites(state)
        local out = {}
        for i, c in ipairs(list) do out[i] = c.name .. ":" .. c.role end
        return table.concat(out, " ")
    end
    local FRIEND = { { name = "Fr", class = "PALADIN", level = 30 } }

    it("take their role's place: a friend who tanks brings no second tank", function()
        assert.are.equal("Pri:HEALER Wlk:DAMAGER Rog:DAMAGER",
            fill({ numGroupMembers = 2, members = FRIEND, memberRoles = { Fr = "TANK" } }))
    end)

    it("count only for members still in the group", function()
        assert.are.equal("War:TANK Pri:HEALER Wlk:DAMAGER Rog:DAMAGER", fill({ memberRoles = { Fr = "TANK" } }))
    end)

    it("count a member SGF invited by his invite, never twice", function()
        local placed = { Fr = { role = "TANK", class = "PALADIN", level = 30, joined = true } }
        assert.are.equal("Pri:HEALER Wlk:DAMAGER Rog:DAMAGER",
            fill({ numGroupMembers = 2, members = FRIEND, placed = placed, memberRoles = { Fr = "HEALER" } }))
    end)

    it("fill a role twice when two members chose it, the rest as usual", function()
        local two = { { name = "A", class = "PALADIN", level = 30 }, { name = "B", class = "DRUID", level = 30 } }
        assert.are.equal("Pri:HEALER Wlk:DAMAGER",
            fill({ numGroupMembers = 3, members = two, memberRoles = { A = "TANK", B = "TANK" } }))
    end)
end)
