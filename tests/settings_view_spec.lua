-- The settings view behind the gear (ruleset plan 2026-11-10-extras, phase 3): language,
-- minimap button; the right-click and the compartment open it; nothing changes in combat.

local addon = require("addon")

local ns, db, panel

local function said(text)
    for _, line in ipairs(CHAT) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

local function clearChat()
    for i = #CHAT, 1, -1 do CHAT[i] = nil end
end

before_each(function()
    ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN")
    db = SmartGroupFilterDB
    panel = ns.panel
    STATE.activities[800] = { minLevelSuggestion = 20, maxLevelSuggestion = 30 }
    STATE.activeEntry = { activityIDs = { 800 } }
end)

-- The radios the language dropdown offers, as the modern menu builds them
local function radios()
    local list = {}
    local root = { CreateRadio = function(_, text, isSelected, select)
        list[#list + 1] = { text = text, isSelected = isSelected, select = select }
    end }
    panel.languageDropdown.menuGenerator(panel.languageDropdown, root)
    return list
end

describe("the settings view", function()
    it("is reached with the gear and left with it again; the build button goes and comes back", function()
        assert.is_true(panel.filterView.shown)
        assert.is_false(panel.settingsView.shown)
        RUNSCRIPT(panel.gearButton, "OnClick")
        assert.is_false(panel.filterView.shown)
        assert.is_true(panel.settingsView.shown)
        assert.is_false(panel.buildButton.shown)
        RUNSCRIPT(panel.gearButton, "OnClick")
        assert.is_true(panel.filterView.shown)
        assert.is_false(panel.settingsView.shown)
        assert.is_true(panel.buildButton.shown)
    end)

    it("looks like Blizzard's own gear in the Group Finder", function()
        ns = addon.load("enUS")
        LFGBrowseFrame.OptionsButton = CreateFrame("Button")
        LFGBrowseFrame.OptionsButton.normalAtlas = "gear-atlas"
        FIRE("PLAYER_LOGIN")
        assert.are.equal("gear-atlas", ns.panel.gearButton.normalAtlas)
    end)

    it("changes no frame in combat and says so", function()
        STATE.combat = true
        clearChat()
        RUNSCRIPT(panel.gearButton, "OnClick")
        assert.is_true(panel.filterView.shown)
        assert.is_true(said("Not in combat."))
        clearChat()
        ns.OpenSettings()
        assert.is_true(panel.filterView.shown)
        assert.is_true(said("Not in combat."))
        STATE.combat = false
    end)

    it("is opened by the right-click and the compartment while the panel shows", function()
        ns.OpenSettings()
        assert.is_true(panel.settingsView.shown)
        RUNSCRIPT(panel.gearButton, "OnClick")
        CLICK(ns.minimapButton, "RightButton")
        assert.is_true(panel.settingsView.shown)
        RUNSCRIPT(panel.gearButton, "OnClick")
        SmartGroupFilter_OnCompartmentClick()
        assert.is_true(panel.settingsView.shown)
    end)

    it("waits for the panel when it is hidden, says so, and opens there next time", function()
        panel.shown = false
        clearChat()
        SmartGroupFilter_OnCompartmentClick()
        assert.is_true(said("The settings open the next time the player list shows."))
        assert.is_false(panel.settingsView.shown)
        panel.shown = true
        RUNSCRIPT(panel, "OnShow")
        assert.is_true(panel.settingsView.shown)
    end)

    it("shows and hides the minimap button with its checkbox", function()
        assert.is_true(panel.minimapCheck.checked)
        panel.minimapCheck:SetChecked(false)
        RUNSCRIPT(panel.minimapCheck, "OnClick")
        assert.is_true(db.hideMinimap)
        assert.is_false(ns.minimapButton.shown)
    end)
end)

describe("the window background slider", function()
    it("sits below the minimap checkbox with its label and value, the bug report button below it", function()
        local slider = panel.opacitySlider
        assert.are.equal("Window background (%)", panel.opacityLabel.text)
        assert.are.equal("60", slider.value.text)
        assert.are.same({ "TOPLEFT", panel.minimapCheck, "BOTTOMLEFT", 4, -16 }, panel.opacityLabel.points[1])
        assert.are.equal(slider, panel.bugButton.points[1][2])
    end)

    it("looks like the level slider: the same track and thumb", function()
        local thumb, level = panel.opacitySlider.thumb, panel.slider.handles[1]
        assert.are.equal(level.width, thumb.width)
        assert.are.equal(level.height, thumb.height)
        assert.are.same(level.children[1].color, thumb.children[1].color)
        assert.are.same({ 0.25, 0.25, 0.25, 1 }, panel.opacitySlider.track.color)
        assert.are.same(panel.slider.track.color, panel.opacitySlider.track.color)
    end)

    it("saves and applies while dragged, to the panel and the docked report", function()
        ns.ShowView("settings")
        ns.OpenBugReport(true)
        local slider = panel.opacitySlider
        slider.left, slider.width = 100, 200
        RUNSCRIPT(slider.thumb, "OnMouseDown")
        STATE.cursor = { x = 100 + 160, y = 0 } -- 80 %
        RUNSCRIPT(slider.thumb, "OnUpdate")
        assert.are.equal(80, db.windowOpacity)
        assert.are.equal("80", slider.value.text)
        assert.are.equal(0.5, panel.opacityLayer.alpha)
        assert.are.equal(0.5, SmartGroupFilterReport.opacityLayer.alpha)
        RUNSCRIPT(slider.thumb, "OnMouseUp")
        STATE.cursor = { x = 100, y = 0 }
        RUNSCRIPT(slider.thumb, "OnUpdate") -- released: no longer follows the cursor
        assert.are.equal(80, db.windowOpacity)
    end)

    it("stops at 0 and 100", function()
        local slider = panel.opacitySlider
        slider.left, slider.width = 100, 200
        RUNSCRIPT(slider.thumb, "OnMouseDown")
        STATE.cursor = { x = 50, y = 0 }
        RUNSCRIPT(slider.thumb, "OnUpdate")
        assert.are.equal(0, db.windowOpacity)
        STATE.cursor = { x = 400, y = 0 }
        RUNSCRIPT(slider.thumb, "OnUpdate")
        assert.are.equal(100, db.windowOpacity)
    end)

    it("takes a typed value from 0 to 100 on Enter or when the field loses focus", function()
        local slider, box = panel.opacitySlider, panel.opacitySlider.value
        box:SetText("35")
        RUNSCRIPT(box, "OnEnterPressed")
        assert.are.equal(35, db.windowOpacity)
        assert.are.equal("35", box.text)
        assert.are.equal(35 / 60, panel.opacityTexture.alpha)
        assert.are.same({ "CENTER", slider, "LEFT", 70, 0 }, slider.thumb.points[1])
        box:SetText("100")
        RUNSCRIPT(box, "OnEditFocusLost")
        assert.are.equal(100, db.windowOpacity)
        box:SetText("0")
        RUNSCRIPT(box, "OnEnterPressed")
        assert.are.equal(0, db.windowOpacity)
    end)

    it("shows the previous value again after an invalid one, and on Escape", function()
        local box = panel.opacitySlider.value
        for _, typed in ipairs({ "101", "150", "", "abc" }) do
            box:SetText(typed)
            RUNSCRIPT(box, "OnEnterPressed")
            assert.are.equal(60, db.windowOpacity, typed)
            assert.are.equal("60", box.text, typed)
        end
        box:SetText("20")
        RUNSCRIPT(box, "OnEscapePressed")
        assert.are.equal(60, db.windowOpacity)
        assert.are.equal("60", box.text)
    end)

    it("shows the saved value whenever the panel shows", function()
        db.windowOpacity = 30
        RUNSCRIPT(panel, "OnShow")
        assert.are.equal("30", panel.opacitySlider.value.text)
    end)
end)

describe("the language choice", function()
    it("offers Automatic and the eleven languages, Automatic chosen", function()
        local list = radios()
        assert.are.equal(12, #list)
        assert.are.equal("Automatic (English)", list[1].text)
        assert.is_true(list[1].isSelected())
        assert.are.equal("Deutsch", list[3].text)
    end)

    it("switches every text at once, the build button's included, and saves it", function()
        local list = radios()
        list[3].select() -- Deutsch
        assert.are.equal("deDE", SmartGroupFilterGlobalDB.language)
        assert.are.equal("Filter zurücksetzen", panel.resetButton.text)
        assert.are.equal("Prioritäten", panel.prioHeader.text)
        assert.are.equal("Liste aktualisieren", panel.buildButton.text) -- no search yet: refresh
        assert.truthy(panel.count.text:find("Spielern", 1, true))
        assert.are.equal("Sprache", panel.languageLabel.text)
    end)

    it("follows the client again with Automatic", function()
        local list = radios()
        list[3].select()
        list[1].select()
        assert.is_nil(SmartGroupFilterGlobalDB.language)
        assert.are.equal("Reset Filter", panel.resetButton.text)
    end)

    it("is as wide as its longest entry", function()
        assert.is_true(panel.languageDropdown.width >= 180)
        -- the mock measures 7 px a character: "简体中文 (Chinese S.)" is the longest entry
        local longest = 0
        for _, code in ipairs(ns.LOCALE_ORDER) do longest = math.max(longest, #ns.LOCALE_NAMES[code]) end
        assert.are.equal(math.max(180, longest * 7 + 50), panel.languageDropdown.width)
    end)

    it("is kept for the next login", function()
        ns = addon.load("enUS", { globalDB = { language = "deDE" } })
        FIRE("PLAYER_LOGIN")
        assert.are.equal("Selbst eintragen", ns.panel.buildButton.text) -- not listed: List Self
    end)
end)
