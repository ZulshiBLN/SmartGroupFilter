-- The filter in Blizzard's list (ruleset plan 2026-11-10-panel-filter-build, phase 2): it
-- removes single players from the results table Blizzard sorts, right before the list is drawn.

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

local function shown()
    local ids = {}
    for i, id in ipairs(LFGBrowseFrame.results) do ids[i] = id end
    return table.concat(ids, " ")
end

before_each(function()
    ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN")
    db = SmartGroupFilterDB
    STATE.activities[800] = { minLevelSuggestion = 20, maxLevelSuggestion = 30, minLevel = 0 }
    STATE.activeEntry = { activityIDs = { 800 } }
end)

describe("the filter", function()
    it("removes single players outside the dungeon's level range, keeps groups and the own listing", function()
        result(1, "MAGE", 25, { dps = true })
        result(2, "MAGE", 35, { dps = true })
        result(3, nil, nil, nil, { numMembers = 3 })
        result(4, "MAGE", 60, { dps = true }, { hasSelf = true })
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("1 3 4", shown())
    end)

    it("removes delisted entries, groups too", function()
        result(1, "MAGE", 25, { dps = true }, { isDelisted = true })
        result(2, nil, nil, nil, { numMembers = 2, isDelisted = true })
        result(3, "MAGE", 25, { dps = true })
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("3", shown())
    end)

    it("follows the rows: an excluded class leaves", function()
        db.excluded.TANK.WARRIOR = true
        result(1, "WARRIOR", 25, { tank = true })
        result(2, "WARRIOR", 25, { dps = true })
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("2", shown())
    end)

    it("leaves Blizzard's list untouched while the Filter is off", function()
        ns.ResetFilter()
        result(1, "MAGE", 35, { dps = true })
        result(2, "MAGE", 25, { dps = true }, { isDelisted = true })
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("1 2", shown())
    end)

    it("treats a secret class or level as unknown, and keeps the player", function()
        result(1, "MAGE", 35, { dps = true })
        STATE.secret[35] = true
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("1", shown())
    end)

    it("reads the dungeons a player listed for; a secret one makes them unknown", function()
        result(1, "MAGE", 25, { dps = true }, { activityIDs = { 800, 801 } })
        assert.are.same({ 800, 801 }, ns.ReadEntry(1).activities)
        STATE.secret[801] = true
        assert.is_nil(ns.ReadEntry(1).activities)
        result(2, "MAGE", 25, { dps = true }, { activityIDs = false })
        assert.is_nil(ns.ReadEntry(2).activities)
    end)

    -- In an instance the client gives every field of a result as a secret; the hook must
    -- neither error nor touch the table, or Blizzard's own drawing runs tainted and fails
    -- on the secrets (Michel's BugSack, 2026-11-11)
    it("leaves Blizzard's list untouched while the results are secret", function()
        result(1, "MAGE", 35, { dps = true })
        result(2, "MAGE", 25, { dps = true }, { isDelisted = true })
        for _, r in pairs(STATE.results) do
            for k in pairs(r.info) do r.info[k] = SECRET() end
        end
        assert.has_no.errors(function() LFGBrowseFrame:UpdateResultList() end)
        assert.are.equal("1 2", shown())
        assert.is_nil(ns.ReadEntry(1))
        assert.has_no.errors(function() FIRE("LFG_LIST_SEARCH_RESULT_UPDATED", 1) end)
        assert.has_no.errors(ns.UpdateBuildButton)
    end)

    it("reads a secret list of dungeons as unknown, the own listing's too", function()
        result(1, "MAGE", 25, { dps = true }, { activityIDs = SECRET() })
        assert.is_nil(ns.ReadEntry(1).activities)
        assert.is_nil(ns.ReadActivities(SECRET()))
        STATE.activeEntry = { activityIDs = SECRET() }
        assert.has_no.errors(ns.LevelRange)
        assert.has_no.errors(function() LFGBrowseFrame:UpdateResultList() end)
    end)

    it("counts the single players shown and all of them", function()
        result(1, "MAGE", 25, { dps = true })
        result(2, "MAGE", 35, { dps = true })
        result(3, "MAGE", 36, { dps = true })
        result(4, nil, nil, nil, { numMembers = 3 })
        local counted
        ns.OnListFiltered(function(s, t) counted = s .. "/" .. t end)
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("1/3", counted)
        local s, t = ns.Counts()
        assert.are.equal(1, s)
        assert.are.equal(3, t)
    end)

    it("keeps a player whose data has not loaded, and filters again once the client updates him", function()
        result(1, "MAGE", 0, { dps = true }) -- level 0: not loaded yet
        result(2, "MAGE", 25, { dps = true })
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("1 2", shown())
        STATE.results[1].player.level = 35
        FIRE("LFG_LIST_SEARCH_RESULT_UPDATED", 1)
        FIRE("LFG_LIST_SEARCH_RESULT_UPDATED", 1)
        assert.are.equal(1, #STATE.timers) -- one refresh, however many updates
        RUNTIMERS()
        assert.are.equal("2", shown())
    end)

    it("brings a hidden player back when an update lets him pass", function()
        result(1, "MAGE", 35, { dps = true })
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("", shown())
        STATE.results[1].player.level = 25
        FIRE("LFG_LIST_SEARCH_RESULT_UPDATED", 1)
        RUNTIMERS()
        assert.are.equal("1", shown())
    end)

    it("does not refresh for an update that changes nothing", function()
        result(1, "MAGE", 25, { dps = true })
        LFGBrowseFrame:UpdateResultList()
        FIRE("LFG_LIST_SEARCH_RESULT_UPDATED", 1)
        assert.are.equal(0, #STATE.timers)
    end)

    it("leaves Blizzard's list untouched while the panel is hidden", function()
        db.panelShown = false
        result(1, "MAGE", 35, { dps = true })
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("1", shown())
    end)

    it("leaves out the own armor class while same armor is not allowed", function()
        STATE.player = { class = "MAGE", level = 25 }
        db.allowSameArmor = false
        result(1, "PRIEST", 25, { healer = true })
        result(2, "DRUID", 25, { healer = true })
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("2", shown())
    end)

    it("resets to Blizzard's list, the rows' order kept, until the next change", function()
        db.excluded.DAMAGER.MAGE = true
        db.allowSameArmor = false
        db.order.TANK = { "DRUID", "PALADIN", "WARRIOR" }
        result(1, "MAGE", 25, { dps = true })
        result(2, "MAGE", 45, { dps = true }, { isDelisted = true })
        ns.SetLevelRange(40, 50) -- set by hand
        ns.ResetFilter()
        assert.are.equal("1 2", shown())
        assert.are.same({}, db.excluded.DAMAGER)
        assert.is_true(db.allowSameArmor)
        assert.are.equal("DRUID PALADIN WARRIOR", table.concat(db.order.TANK, " "))
        assert.are.equal(20, ns.LevelRange().min) -- the dungeon's range again (Michel, 2026-11-13)
        assert.are.equal(30, ns.LevelRange().max)
        ns.FilterChanged()
        assert.are.equal("1", shown()) -- filtering again: the delisted entry goes
    end)

    it("filters again after a login that followed Reset Filter", function()
        ns.ResetFilter()
        local saved = SmartGroupFilterDB
        ns = addon.load("enUS", { db = saved })
        FIRE("PLAYER_LOGIN")
        STATE.activities[800] = { minLevelSuggestion = 20, maxLevelSuggestion = 30 }
        STATE.activeEntry = { activityIDs = { 800 } }
        result(1, "MAGE", 19, { dps = true })
        result(2, "MAGE", 25, { dps = true })
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("2", shown()) -- the panel's 20-30 applies again
    end)

    it("refreshes Blizzard's list without a new search, only while it is shown", function()
        result(1, "MAGE", 25, { dps = true })
        LFGBrowseFrame:UpdateResultList()
        db.excluded.DAMAGER.MAGE = true
        ns.RefreshList()
        assert.are.equal("", shown())
        LFGBrowseFrame.shown = false
        db.excluded.DAMAGER.MAGE = nil
        ns.RefreshList()
        assert.are.equal("", shown())
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

-- Blizzard's sort errors while the client gives no roles - inside an instance, though listed
-- (Michel's BugSack, 2026-11-13): SGF
-- never rebuilds the list then - Blizzard's own redraws stay Blizzard's
describe("no roles from the client", function()
    it("means no list rebuild from SGF until they are back", function()
        LFGBrowseFrame:UpdateResultList()
        local before = table.concat(LFGBrowseFrame.results, " ")
        STATE.ownRoles = nil
        assert.has_no.errors(function() ns.RefreshList() end)
        assert.are.equal(before, table.concat(LFGBrowseFrame.results, " "))
        STATE.ownRoles = { tank = false, healer = false, dps = true }
        assert.has_no.errors(function() ns.RefreshList() end)
    end)
end)
