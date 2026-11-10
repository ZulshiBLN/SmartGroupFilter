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

    it("is kept for the next login", function()
        ns = addon.load("enUS", { globalDB = { language = "deDE" } })
        FIRE("PLAYER_LOGIN")
        assert.are.equal("Selbst eintragen", ns.panel.buildButton.text) -- not listed: List Self
    end)
end)
