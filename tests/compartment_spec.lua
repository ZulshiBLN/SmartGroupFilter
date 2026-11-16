-- The addon compartment entry (ruleset plan 2026-11-10-extras, phase 2). Blizzard's menu calls
-- these functions as addon code, so the entry opens SGF's settings, not the Group Finder.

local addon = require("addon")

local ns

before_each(function()
    ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN")
end)

describe("the addon compartment entry", function()
    it("is named in the TOC with its three functions", function()
        local toc = addon.read("SmartGroupFilter/SmartGroupFilter.toc")
        assert.truthy(toc:find("## AddonCompartmentFunc: SmartGroupFilter_OnCompartmentClick", 1, true))
        assert.truthy(toc:find("## AddonCompartmentFuncOnEnter: SmartGroupFilter_OnCompartmentEnter", 1, true))
        assert.truthy(toc:find("## AddonCompartmentFuncOnLeave: SmartGroupFilter_OnCompartmentLeave", 1, true))
        assert.is_function(SmartGroupFilter_OnCompartmentClick)
        assert.is_function(SmartGroupFilter_OnCompartmentEnter)
        assert.is_function(SmartGroupFilter_OnCompartmentLeave)
    end)

    it("opens SGF's settings on a click, never the Group Finder", function()
        local opened = 0
        ns.OpenSettings = function() opened = opened + 1 end
        SmartGroupFilter_OnCompartmentClick(nil, "LeftButton")
        SmartGroupFilter_OnCompartmentClick(nil, "RightButton")
        assert.are.equal(2, opened)
        assert.are.equal(0, STATE.microClicks)
    end)

    it("names the click and where the Group Finder opens in its tooltip", function()
        local entry = CreateFrame("Button")
        SmartGroupFilter_OnCompartmentEnter(nil, entry)
        assert.are.equal(entry, GameTooltip.owner)
        assert.truthy(GameTooltip.lines[1]:find("SmartGroupFilter", 1, true))
        assert.are.equal("Click: SmartGroupFilter settings", GameTooltip.lines[2])
        assert.are.equal("The minimap button or Blizzard's own button opens the Group Finder.", GameTooltip.lines[3])
        SmartGroupFilter_OnCompartmentLeave()
        assert.is_false(GameTooltip.shown)
    end)
end)
