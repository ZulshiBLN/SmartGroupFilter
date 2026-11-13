-- The panel beside the player list (ruleset plan 2026-11-10-panel-filter-build, phase 3).

local addon = require("addon")

local ns, db, panel

local function result(id, class, level, roles)
    STATE.results[id] = {
        info = { numMembers = 1, isDelisted = false, hasSelf = false, age = 0, activityIDs = { 800 } },
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
        assert.are.equal("Interface\\AddOns\\SmartGroupFilter\\Media\\Logo", panel.portrait)
        -- moved 2 px left and up from where the template put it (-5, 7 in the mock)
        assert.are.same({ "TOPLEFT", panel, "TOPLEFT", -7, 9 }, panel.Portrait.points[2])
    end)

    it("docks to the window's edge when there are no side tabs", function()
        LFGParentFrame.BrowsingTab = nil
        RUNSCRIPT(panel, "OnShow")
        assert.are.same({ "TOPLEFT", LFGParentFrame, "TOPRIGHT", 4, 0 }, panel.points[#panel.points])
    end)

    it("counts the players shown for each role beside its header", function()
        assert.are.equal("(1 listed)", panel.rows.TANK.count.text)
        assert.are.equal("(0 listed)", panel.rows.HEALER.count.text)
        assert.are.equal("(1 listed)", panel.rows.DAMAGER.count.text) -- the level 35 mage is hidden
        result(4, "DRUID", 25, { tank = true, dps = true })
        result(5, "ROGUE", 25, {})
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("(2 listed)", panel.rows.TANK.count.text) -- both roles count
        assert.are.equal("(2 listed)", panel.rows.DAMAGER.count.text) -- no role counts nowhere
    end)

    it("counts the single players shown", function()
        assert.are.equal("2 of 3 players", panel.count.text)
        -- level with the build button's middle (14 above the edge, 24 high)
        assert.are.same({ "RIGHT", panel, "BOTTOMRIGHT", -14, 26 }, panel.count.points[1])
    end)

    it("puts the build button in the bottom left corner, looking as far from the edges as Reset Filter", function()
        assert.are.same({ "TOPRIGHT", panel, "TOPRIGHT", -10, -30 }, panel.resetButton.points[1])
        -- 14 from the bottom: the frame's lower edge is drawn wider (Michel, in game)
        assert.are.same({ "BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 14 }, panel.buildButton.points[1])
    end)

    it("resets to Blizzard's list with Reset Filter, and filters again at the next change", function()
        RUNSCRIPT(panel.rows.TANK.icons[2], "OnClick", "RightButton") -- warrior out
        panel.armorCheck:SetChecked(false)
        RUNSCRIPT(panel.armorCheck, "OnClick") -- the mages out
        assert.are.equal("", shown())
        RUNSCRIPT(panel.resetButton, "OnClick")
        assert.are.equal("1 2 3", shown())
        assert.are.equal("3 of 3 players", panel.count.text)
        assert.is_true(panel.armorCheck.checked)
        assert.are.equal("1", panel.fromBox.text)
        assert.are.equal("60", panel.toBox.text)
        assert.is_false(panel.rows.TANK.icons[2].cross.shown)
        RUNSCRIPT(panel.rows.TANK.icons[2], "OnClick", "RightButton")
        assert.are.equal("2 3", shown())
    end)

    it("greys the classes of the player's armor while same armor is not allowed", function()
        STATE.player = { class = "MAGE", level = 25 }
        panel.armorCheck:SetChecked(false)
        RUNSCRIPT(panel.armorCheck, "OnClick")
        local healer = panel.rows.HEALER.icons[1]
        assert.are.equal("PRIEST", healer.class)
        assert.is_true(healer.texture.desaturated)
        assert.is_true(healer.cross.shown) -- the cross, fainter than an exclusion
        assert.are.equal(0.45, healer.cross.alpha)
        assert.is_nil(db.excluded.HEALER.PRIEST) -- not saved as an exclusion
        assert.is_false(panel.rows.HEALER.icons[2].texture.desaturated) -- druid: leather
        RUNSCRIPT(healer, "OnEnter")
        assert.are.equal("Same armor class as you", GameTooltip.lines[3])
        assert.are.equal("1", shown()) -- the mages leave the list too, the warrior stays
        panel.armorCheck:SetChecked(true)
        RUNSCRIPT(panel.armorCheck, "OnClick")
        assert.is_false(healer.texture.desaturated)
        assert.is_false(healer.cross.shown)
        RUNSCRIPT(healer, "OnClick", "RightButton")
        assert.are.equal(1, healer.cross.alpha) -- an exclusion: the full cross
    end)

    it("shows and hides the panel with a fourth side tab, remembered, Blizzard's list while hidden", function()
        local tab = ns.tab
        assert.are.equal(LFGBrowseFrame, tab.parent) -- on the Group Browser only (Michel)
        assert.are.equal("LargeSideTabButtonTemplate", tab.template)
        assert.are.same({ "TOPLEFT", LFGParentFrame.WhoListingTab, "BOTTOMLEFT", 0, -2 }, tab.points[1])
        assert.are.equal("Interface\\AddOns\\SmartGroupFilter\\Media\\Tab", tab.Icon.textureFile)
        assert.is_true(tab.fillToInterior) -- the logo fills the tab
        assert.is_true(tab.checked) -- highlighted while the panel is visible
        tab.mouseUp(tab, "LeftButton", true)
        assert.is_false(panel.shown)
        assert.is_false(db.panelShown)
        assert.is_false(tab.checked)
        assert.are.equal("1 2 3", shown())
        tab.mouseUp(tab, "LeftButton", true)
        assert.is_true(panel.shown)
        assert.is_true(tab.checked)
        assert.are.equal("1 2", shown())
        assert.are.equal(0, STATE.tab2ButtonClicks) -- SGF switches no page
    end)

    it("glows while the panel is shown", function()
        local tab = ns.tab
        assert.is_true(tab.checked)
        tab.mouseUp(tab, "LeftButton", true)
        assert.is_false(tab.checked)
    end)

    it("starts hidden when it was hidden before", function()
        ns = addon.load("enUS", { db = { panelShown = false } })
        FIRE("PLAYER_LOGIN")
        assert.is_false(ns.panel.shown)
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

    it("moves the other level along when a typed one passes it", function()
        RUNSCRIPT(panel, "OnShow")
        panel.fromBox:SetText("52")
        RUNSCRIPT(panel.fromBox, "OnEnterPressed")
        assert.are.equal("52", panel.fromBox.text)
        assert.are.equal("52", panel.toBox.text)
        panel.toBox:SetText("12")
        RUNSCRIPT(panel.toBox, "OnEnterPressed")
        assert.are.equal("12", panel.fromBox.text)
        assert.are.equal("12", panel.toBox.text)
        panel.toBox:SetText("0")
        RUNSCRIPT(panel.toBox, "OnEnterPressed")
        assert.are.equal("1", panel.toBox.text) -- below 1: level 1
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

    it("looks like the sisters: their dialog background, their gold slider thumbs", function()
        assert.are.equal("Interface\\DialogFrame\\UI-DialogBox-Background", panel.background.textureFile)
        local handle = panel.slider.handles[1]
        assert.are.equal(10, handle.width)
        assert.are.equal(16, handle.height)
        assert.are.same({ 1, 0.82, 0, 1 }, handle.children[1].color)
    end)

    it("parts its sections with headers and gold lines: range | priorities | options", function()
        assert.are.equal("Level range", panel.rangeHeader.text)
        assert.are.equal("Priorities", panel.prioHeader.text)
        local first, second = panel.separators[1], panel.separators[2]
        assert.are.same({ "TOP", panel.slider, "BOTTOM", 0, -12 }, first.points[2])
        assert.are.same({ "TOPLEFT", first, "BOTTOMLEFT", 0, -12 }, panel.prioHeader.points[1])
        assert.are.same({ "TOP", panel.rows.DAMAGER, "BOTTOM", 0, -12 }, second.points[2])
        assert.are.same({ "TOPLEFT", second, "BOTTOMLEFT", -4, -10 }, panel.doubleCheck.points[1])
        assert.are.equal(2, #first.children) -- the two halves of the line
    end)

    it("follows a language switch", function()
        assert.are.equal("Allow double classes", panel.doubleCheck.label.text)
        ns.ApplyLanguage("deDE")
        assert.are.equal("Doppelte Klassen erlauben", panel.doubleCheck.label.text)
        assert.are.equal("Heiler", panel.rows.HEALER.label.text)
    end)
end)

describe("the window background", function()
    local CASES = { { 0, 0, 0 }, { 30, 0.5, 0 }, { 60, 1, 0 }, { 80, 1, 0.5 }, { 100, 1, 1 } }

    it("lays a black layer beneath the dialog texture, inside the same edges", function()
        local tex, layer = panel.opacityTexture, panel.opacityLayer
        assert.are.equal(panel.background, tex)
        assert.are.same({ 0, 0, 0, 1 }, layer.color)
        assert.are.equal("BACKGROUND", layer.drawLayer)
        assert.is_true(layer.sublevel < tex.sublevel)
        assert.are.same(tex.points, layer.points)
    end)

    it("fades the texture out below 60 and the black layer in above", function()
        for _, c in ipairs(CASES) do
            ns.ApplyWindowOpacity(panel, c[1])
            assert.are.equal(c[2], panel.opacityTexture.alpha, "texture at " .. c[1])
            assert.are.equal(c[3], panel.opacityLayer.alpha, "layer at " .. c[1])
        end
    end)

    it("shows the saved value from the login on", function()
        ns = addon.load("enUS", { db = { dbVersion = 1, windowOpacity = 100 } })
        FIRE("PLAYER_LOGIN")
        assert.are.equal(1, ns.panel.opacityLayer.alpha)
        assert.are.equal(1, ns.panel.opacityTexture.alpha)
    end)
end)

-- The release reviews' panel findings (ruleset plan 2026-11-13-review-fixes, phase 3)
describe("the panel, after the release reviews", function()
    local function said(text)
        for _, line in ipairs(CHAT) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end

    it("says so when the filter leaves no player of the list", function()
        RUNSCRIPT(panel, "OnShow")
        panel.fromBox:SetText("50")
        RUNSCRIPT(panel.fromBox, "OnEnterPressed")
        assert.are.equal("", shown())
        assert.are.equal("0 of 3 players - none fit your filter", panel.count.text)
    end)

    it("leaves a level being typed alone while the list refreshes", function()
        RUNSCRIPT(panel, "OnShow")
        panel.fromBox:SetFocus()
        panel.fromBox:SetText("2")
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("2", panel.fromBox.text)
        assert.are.equal("30", panel.toBox.text)
    end)

    it("shows the clamped value after Enter and the old one after Escape on a focused box", function()
        RUNSCRIPT(panel, "OnShow")
        panel.fromBox:SetFocus()
        panel.fromBox:SetText("abc")
        RUNSCRIPT(panel.fromBox, "OnEscapePressed")
        assert.are.equal("20", panel.fromBox.text)
        assert.is_false(panel.fromBox:HasFocus())
        panel.toBox:SetFocus()
        panel.toBox:SetText("0")
        RUNSCRIPT(panel.toBox, "OnEnterPressed")
        assert.are.equal("1", panel.toBox.text)
        assert.is_false(panel.toBox:HasFocus())
    end)

    it("says Not in combat when its side tab is clicked in combat", function()
        for i = #CHAT, 1, -1 do CHAT[i] = nil end
        STATE.combat = true
        ns.tab.mouseUp(ns.tab, "LeftButton", true)
        assert.is_true(panel.shown)
        assert.is_true(said("Not in combat."))
    end)

    it("has no one-per-click text left in any locale", function()
        for code, t in pairs(ns.locales) do
            assert.is_nil(rawget(t, "INVITE_NEXT"), code)
        end
    end)
end)
