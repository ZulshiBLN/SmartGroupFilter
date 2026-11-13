-- The filter (ruleset plan 2026-11-13-list-untouched): SGF leaves Blizzard's Group Finder list as
-- Blizzard built it and counts for itself - the panel's numbers and Build Group's candidates.

local addon = require("addon")

local ns, db

-- A result as the client gives it; roles nil = signed up with none
local function result(id, class, level, roles, over)
    local info = { searchResultID = id, numMembers = 1, isDelisted = false, hasSelf = false, age = 0,
        activityIDs = { 800 } }
    for k, v in pairs(over or {}) do info[k] = v end
    STATE.results[id] = {
        info = info,
        player = { name = "P" .. id, classFilename = class, level = level,
            lfgRoles = roles or { tank = false, healer = false, dps = false } },
    }
    STATE.order[#STATE.order + 1] = id
end

-- Single players that fit the filter, of all single players
local function fit()
    local s, t = ns.Counts()
    return s .. "/" .. t
end

local function received()
    FIRE("LFG_LIST_SEARCH_RESULTS_RECEIVED")
end

before_each(function()
    ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN")
    db = SmartGroupFilterDB
    STATE.activities[800] = { minLevelSuggestion = 20, maxLevelSuggestion = 30, minLevel = 0 }
    STATE.activeEntry = { activityIDs = { 800 } }
end)

describe("Blizzard's list", function()
    it("stays as Blizzard built it: every result, in Blizzard's order", function()
        result(1, "MAGE", 25, { dps = true })
        result(2, "MAGE", 35, { dps = true })
        result(3, nil, nil, nil, { numMembers = 3 })
        result(4, "MAGE", 25, { dps = true }, { isDelisted = true })
        received()
        assert.are.equal("1 2 3 4", LISTED())
        assert.are.equal(0, STATE.listBuilds)
    end)

    it("is never rebuilt by SGF: not on a setting change, Reset Filter, the side tab or late data", function()
        result(1, "MAGE", 0, { dps = true }) -- level 0: not loaded yet
        received()
        db.excluded.DAMAGER.MAGE = true
        ns.FilterChanged()
        ns.ResetFilter()
        ns.tab.Toggle()
        ns.tab.Toggle()
        STATE.results[1].player.level = 35
        FIRE("LFG_LIST_SEARCH_RESULT_UPDATED", 1)
        RUNTIMERS()
        assert.are.equal(0, STATE.listBuilds)
        assert.are.equal("1", LISTED())
    end)
end)

describe("the count", function()
    it("leaves out single players outside the dungeon's level range, counts no group, no own listing", function()
        result(1, "MAGE", 25, { dps = true })
        result(2, "MAGE", 35, { dps = true })
        result(3, nil, nil, nil, { numMembers = 3 })
        result(4, "MAGE", 60, { dps = true }, { hasSelf = true })
        received()
        assert.are.equal("1/2", fit())
    end)

    it("leaves out delisted players", function()
        result(1, "MAGE", 25, { dps = true }, { isDelisted = true })
        result(2, "MAGE", 25, { dps = true })
        received()
        assert.are.equal("1/2", fit())
    end)

    it("follows the rows: an excluded class leaves its role", function()
        db.excluded.TANK.WARRIOR = true
        result(1, "WARRIOR", 25, { tank = true })
        result(2, "WARRIOR", 25, { dps = true })
        received()
        assert.are.equal("1/2", fit())
        assert.are.equal(0, ns.RoleCounts().TANK)
        assert.are.equal(1, ns.RoleCounts().DAMAGER)
    end)

    it("treats a secret class or level as unknown, and lets the player fit", function()
        result(1, "MAGE", 35, { dps = true })
        STATE.secret[35] = true
        received()
        assert.are.equal("1/1", fit())
    end)

    it("leaves out the own armor class while same armor is not allowed", function()
        STATE.player = { class = "MAGE", level = 25 }
        db.allowSameArmor = false
        result(1, "PRIEST", 25, { healer = true })
        result(2, "DRUID", 25, { healer = true })
        received()
        assert.are.equal("1/2", fit())
    end)

    it("hands the single players that fit and all of them to its listeners", function()
        result(1, "MAGE", 25, { dps = true })
        result(2, "MAGE", 35, { dps = true })
        result(3, "MAGE", 36, { dps = true })
        result(4, nil, nil, nil, { numMembers = 3 })
        local counted
        ns.OnListFiltered(function(s, t) counted = s .. "/" .. t end)
        received()
        assert.are.equal("1/3", counted)
    end)

    -- Each trigger: the world changes without an event, then the trigger alone must count again
    local function changedQuietly()
        result(1, "MAGE", 25, { dps = true })
        received()
        assert.are.equal("1/1", fit())
        result(2, "MAGE", 26, { dps = true })
    end

    it("counts again after a failed search", function()
        changedQuietly()
        FIRE("LFG_LIST_SEARCH_FAILED")
        assert.are.equal("2/2", fit())
    end)

    it("counts again after a change of the own listing", function()
        changedQuietly()
        FIRE("LFG_LIST_ACTIVE_ENTRY_UPDATE")
        assert.are.equal("2/2", fit())
    end)

    it("counts again when the panel shows", function()
        changedQuietly()
        RUNSCRIPT(ns.panel, "OnShow")
        assert.are.equal("2/2", fit())
    end)

    it("counts again on a setting change", function()
        changedQuietly()
        db.excluded.DAMAGER.MAGE = true
        ns.FilterChanged()
        assert.are.equal("0/2", fit())
    end)

    it("counts again from the side tab", function()
        changedQuietly()
        ns.tab.Toggle()
        assert.are.equal("2/2", fit())
    end)

    it("counts late data once, shortly after, however many updates arrive", function()
        result(1, "MAGE", 0, { dps = true }) -- level 0: not loaded yet
        result(2, "MAGE", 25, { dps = true })
        received()
        assert.are.equal("2/2", fit())
        local before = #STATE.timers -- Build Group's own, queued by the results
        STATE.results[1].player.level = 35
        FIRE("LFG_LIST_SEARCH_RESULT_UPDATED", 1)
        FIRE("LFG_LIST_SEARCH_RESULT_UPDATED", 2)
        assert.are.equal(before + 1, #STATE.timers)
        assert.are.equal(0.3, STATE.delays[#STATE.delays])
        assert.are.equal("2/2", fit())
        RUNTIMERS()
        assert.are.equal("1/2", fit())
        FIRE("LFG_LIST_SEARCH_RESULT_UPDATED", 1) -- the next update waits again
        assert.are.equal(1, #STATE.timers)
    end)

    -- In an instance the client gives every field of a result as a secret (Michel's BugSack,
    -- 2026-11-11): the counts stay as they were, nothing errors
    it("keeps its counts while the results are secret", function()
        result(1, "MAGE", 25, { dps = true })
        result(2, "MAGE", 35, { dps = true })
        received()
        assert.are.equal("1/2", fit())
        for _, r in pairs(STATE.results) do
            for k in pairs(r.info) do r.info[k] = SECRET() end
        end
        assert.has_no.errors(received)
        assert.are.equal("1/2", fit())
        assert.is_nil(ns.ReadEntry(1))
        assert.has_no.errors(function()
            FIRE("LFG_LIST_SEARCH_RESULT_UPDATED", 1)
            RUNTIMERS()
        end)
        assert.are.equal("1/2", fit())
        assert.has_no.errors(ns.UpdateBuildButton)
    end)

    it("reads the dungeons a player listed for; a secret one makes them unknown", function()
        result(1, "MAGE", 25, { dps = true }, { activityIDs = { 800, 801 } })
        assert.are.same({ 800, 801 }, ns.ReadEntry(1).activities)
        STATE.secret[801] = true
        assert.is_nil(ns.ReadEntry(1).activities)
        result(2, "MAGE", 25, { dps = true }, { activityIDs = false })
        assert.is_nil(ns.ReadEntry(2).activities)
    end)

    it("reads a secret list of dungeons as unknown, the own listing's too", function()
        result(1, "MAGE", 25, { dps = true }, { activityIDs = SECRET() })
        assert.is_nil(ns.ReadEntry(1).activities)
        assert.is_nil(ns.ReadActivities(SECRET()))
        STATE.activeEntry = { activityIDs = SECRET() }
        assert.has_no.errors(ns.LevelRange)
        assert.has_no.errors(received)
    end)
end)

describe("Reset Filter", function()
    it("clears exclusions, allows same armor, takes the dungeon's range, keeps the rows' order", function()
        db.excluded.DAMAGER.MAGE = true
        db.allowSameArmor = false
        db.order.TANK = { "DRUID", "PALADIN", "WARRIOR" }
        result(1, "MAGE", 25, { dps = true })
        result(2, "MAGE", 45, { dps = true })
        ns.SetLevelRange(40, 50) -- set by hand
        received()
        assert.are.equal("0/2", fit())
        ns.ResetFilter()
        assert.are.same({}, db.excluded.DAMAGER)
        assert.is_true(db.allowSameArmor)
        assert.are.equal("DRUID PALADIN WARRIOR", table.concat(db.order.TANK, " "))
        assert.are.equal(20, ns.LevelRange().min) -- the dungeon's range again (Michel, 2026-11-13)
        assert.are.equal(30, ns.LevelRange().max)
        assert.are.equal("1/2", fit()) -- counted again by the reset filter
    end)
end)

describe("the level range", function()
    it("is the listed dungeon's suggestion", function()
        local r = ns.LevelRange()
        assert.are.equal(20, r.min)
        assert.are.equal(30, r.max)
    end)

    it("spans every activity of the listing", function()
        STATE.activities[801] = { minLevelSuggestion = 15, maxLevelSuggestion = 25 }
        STATE.activeEntry = { activityIDs = { 800, 801 } }
        local r = ns.LevelRange()
        assert.are.equal(15, r.min)
        assert.are.equal(30, r.max)
    end)

    it("takes the dropdown's activities when not listed, else the whole range", function()
        STATE.activeEntry = nil
        STATE.activities[801] = { minLevelSuggestion = 15, maxLevelSuggestion = 0 }
        LFGBrowseFrame.ActivityDropdown.selectedValues = { 801 }
        local r = ns.LevelRange()
        assert.are.equal(15, r.min)
        assert.are.equal(60, r.max) -- a missing or zero suggestion: the maximum level
        LFGBrowseFrame.ActivityDropdown.selectedValues = {}
        r = ns.LevelRange()
        assert.are.equal(1, r.min)
        assert.are.equal(60, r.max)
    end)

    it("keeps a range set by hand until the activities change, from > to swapped", function()
        ns.SetLevelRange(28, 22)
        local r = ns.LevelRange()
        assert.are.equal(22, r.min)
        assert.are.equal(28, r.max)
        STATE.activeEntry = { activityIDs = { 801 } }
        STATE.activities[801] = { minLevelSuggestion = 15, maxLevelSuggestion = 25 }
        r = ns.LevelRange()
        assert.are.equal(15, r.min)
        assert.are.equal(25, r.max)
    end)
end)
