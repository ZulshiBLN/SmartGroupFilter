-- The panel beside the player list (ruleset plan 2026-11-10-panel-filter-build, phase 3).

local addon = require("addon")

local ns, db, panel

local function result(id, class, level, roles)
    STATE.results[id] = {
        info = { numMembers = 1, isDelisted = false, hasSelf = false, age = 0 },
        player = { name = "P" .. id, classFilename = class, level = level, lfgRoles = roles },
    }
    STATE.order[#STATE.order + 1] = id
end

local function shown()
    return table.concat(LFGBrowseFrame.results, " ")
end

local function classesOf(role)
    local out = {}
    for i, icon in ipairs(panel.rows[role].icons) do out[i] = icon.class end
    return table.concat(out, " ")
end

before_each(function()
    ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN")
    db = SmartGroupFilterDB
    panel = ns.panel
    STATE.activities[800] = { minLevelSuggestion = 20, maxLevelSuggestion = 30 }
    STATE.activeEntry = { activityIDs = { 800 } }
    result(1, "WARRIOR", 25, { tank = true })
    result(2, "MAGE", 25, { dps = true })
    result(3, "MAGE", 35, { dps = true })
    LFGBrowseFrame:UpdateResultList()
end)

describe("the panel", function()
    it("is a child of the player list, docked right of the side tabs, as tall as the window", function()
        assert.are.equal(LFGBrowseFrame, panel.parent)
        RUNSCRIPT(panel, "OnShow")
        local p = panel.points[#panel.points]
        assert.are.same({ "TOPLEFT", LFGParentFrame, "TOPRIGHT", 44, 0 }, p)
        assert.are.equal(600, panel.height)
        assert.is_false(panel.CloseButton.shown)
    end)

    it("docks to the window's edge when there are no side tabs", function()
        LFGParentFrame.BrowsingTab = nil
        RUNSCRIPT(panel, "OnShow")
        assert.are.same({ "TOPLEFT", LFGParentFrame, "TOPRIGHT", 4, 0 }, panel.points[#panel.points])
    end)

    it("counts the single players shown", function()
        assert.are.equal("2 of 3 single players", panel.count.text)
    end)

    it("switches the filter off and on", function()
        assert.is_true(panel.filterCheck.checked)
        panel.filterCheck:SetChecked(false)
        RUNSCRIPT(panel.filterCheck, "OnClick")
        assert.is_false(db.filterOn)
        assert.are.equal("1 2 3", shown())
        panel.filterCheck:SetChecked(true)
        RUNSCRIPT(panel.filterCheck, "OnClick")
        assert.are.equal("1 2", shown())
    end)

    it("shows each row's classes in their order, with Blizzard's class icons", function()
        assert.are.equal("PALADIN WARRIOR DRUID", classesOf("TANK"))
        assert.are.equal(9, #panel.rows.DAMAGER.icons)
        assert.are.equal("groupfinder-icon-class-paladin", panel.rows.TANK.icons[1].texture.atlas)
    end)

    it("excludes a class on a right-click and takes it back on the next", function()
        local warrior = panel.rows.TANK.icons[2]
        RUNSCRIPT(warrior, "OnClick", "RightButton")
        assert.is_true(db.excluded.TANK.WARRIOR)
        assert.is_true(warrior.texture.desaturated)
        assert.is_true(warrior.cross.shown)
        assert.are.equal("2", shown())
        RUNSCRIPT(warrior, "OnClick", "RightButton")
        assert.is_nil(db.excluded.TANK.WARRIOR)
        assert.is_false(warrior.texture.desaturated)
        assert.are.equal("1 2", shown())
    end)

    it("ignores a left-click on a class", function()
        RUNSCRIPT(panel.rows.TANK.icons[2], "OnClick", "LeftButton")
        assert.is_nil(db.excluded.TANK.WARRIOR)
    end)

    it("moves a dragged class to the slot under the cursor", function()
        local row = panel.rows.TANK
        row.left, row.top = 100, 500
        RUNSCRIPT(row.icons[1], "OnDragStart")
        STATE.cursor = { x = 100 + 2 * 32 + 5, y = 490 } -- third slot
        RUNSCRIPT(row.icons[1], "OnDragStop")
        assert.are.equal("WARRIOR DRUID PALADIN", table.concat(db.order.TANK, " "))
        assert.are.equal("WARRIOR DRUID PALADIN", classesOf("TANK"))
    end)

    it("reads the damage row's second line", function()
        local row = panel.rows.DAMAGER
        row.left, row.top = 100, 400
        RUNSCRIPT(row.icons[1], "OnDragStart")
        STATE.cursor = { x = 100 + 1 * 32 + 5, y = 400 - 32 - 5 } -- second line, second slot
        RUNSCRIPT(row.icons[1], "OnDragStop")
        assert.are.equal("MAGE", db.order.DAMAGER[7])
    end)

    it("keeps the order when a class is dropped outside its row", function()
        local row = panel.rows.TANK
        row.left, row.top = 100, 500
        RUNSCRIPT(row.icons[1], "OnDragStart")
        STATE.cursor = { x = 100 + 5, y = 300 }
        RUNSCRIPT(row.icons[1], "OnDragStop")
        assert.are.equal("PALADIN WARRIOR DRUID", table.concat(db.order.TANK, " "))
    end)

    it("names the class and the clicks in the tooltip, and an exclusion", function()
        local warrior = panel.rows.TANK.icons[2]
        RUNSCRIPT(warrior, "OnEnter")
        assert.are.equal("Warrior", GameTooltip.lines[1])
        assert.are.equal("Drag to reorder, right-click to exclude", GameTooltip.lines[2])
        RUNSCRIPT(warrior, "OnClick", "RightButton")
        RUNSCRIPT(warrior, "OnEnter")
        assert.are.equal("Excluded", GameTooltip.lines[3])
    end)

    it("shows the dungeon's level range and takes a typed one", function()
        RUNSCRIPT(panel, "OnShow")
        assert.are.equal("20", panel.fromBox.text)
        assert.are.equal("30", panel.toBox.text)
        panel.toBox:SetText("34")
        RUNSCRIPT(panel.toBox, "OnEnterPressed")
        assert.are.equal(34, ns.LevelRange().max)
        assert.are.equal("1 2", shown())
        panel.toBox:SetText("36")
        RUNSCRIPT(panel.toBox, "OnEnterPressed")
        assert.are.equal("1 2 3", shown())
    end)

    it("restores the fields when the typed text is no level", function()
        RUNSCRIPT(panel, "OnShow")
        panel.fromBox:SetText("abc")
        RUNSCRIPT(panel.fromBox, "OnEnterPressed")
        assert.are.equal("20", panel.fromBox.text)
        assert.are.equal(20, ns.LevelRange().min)
    end)

    it("sets the range with the slider's handles, the low one never past the high one", function()
        RUNSCRIPT(panel, "OnShow")
        local track, low, high = panel.slider, panel.slider.handles[1], panel.slider.handles[2]
        track.left, track.width = 100, 236 -- 59 steps of 4 px from level 1 to 60
        RUNSCRIPT(high, "OnMouseDown")
        STATE.cursor = { x = 100 + 35 * 4, y = 0 } -- level 36
        RUNSCRIPT(high, "OnUpdate")
        assert.are.equal("36", panel.toBox.text)
        RUNSCRIPT(high, "OnMouseUp")
        assert.are.equal(36, ns.LevelRange().max)
        assert.are.equal("1 2 3", shown())
        RUNSCRIPT(low, "OnMouseDown")
        STATE.cursor = { x = 100 + 50 * 4, y = 0 } -- level 51, past the high handle
        RUNSCRIPT(low, "OnUpdate")
        RUNSCRIPT(low, "OnMouseUp")
        assert.are.equal(36, ns.LevelRange().min)
        assert.are.equal(36, ns.LevelRange().max) -- stopped at the high handle, not swapped
    end)

    it("sets the two options", function()
        panel.doubleCheck:SetChecked(true)
        RUNSCRIPT(panel.doubleCheck, "OnClick")
        assert.is_true(db.allowDouble)
        panel.armorCheck:SetChecked(false)
        RUNSCRIPT(panel.armorCheck, "OnClick")
        assert.is_false(db.allowSameArmor)
    end)

    it("follows a language switch", function()
        assert.are.equal("Allow double classes", panel.doubleCheck.label.text)
        ns.ApplyLanguage("deDE")
        assert.are.equal("Doppelte Klassen erlauben", panel.doubleCheck.label.text)
        assert.are.equal("Heiler", panel.rows.HEALER.label.text)
    end)
end)
