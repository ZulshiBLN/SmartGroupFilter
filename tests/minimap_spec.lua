-- The minimap button (ruleset plan 2026-11-10-extras, phase 1): a secure button on UIParent,
-- placed around the minimap; left-click clicks Blizzard's Group Finder micro button.

local addon = require("addon")

local ns, db, btn

local function said(text)
    for _, line in ipairs(CHAT) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

before_each(function()
    ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN")
    db = SmartGroupFilterDB
    btn = ns.minimapButton
end)

describe("the minimap button", function()
    it("is a secure button parented and anchored to UIParent, never to the minimap", function()
        assert.truthy(btn.template:find("SecureActionButtonTemplate", 1, true))
        assert.are.equal(UIParent, btn.parent)
        for _, point in ipairs(btn.points) do assert.are.equal(UIParent, point[2]) end
        assert.are.equal("LOW", btn.strata)
        assert.is_true(btn.level > Minimap.level)
    end)

    it("clicks Blizzard's Group Finder button securely on a left-click", function()
        assert.are.equal("click", btn:GetAttribute("type1"))
        assert.are.equal(LFDMicroButton, btn:GetAttribute("clickbutton1"))
        CLICK(btn, "LeftButton")
        assert.are.equal(1, STATE.microClicks)
        CLICK(btn, "RightButton")
        assert.are.equal(1, STATE.microClicks) -- the right-click opens no Group Finder
    end)

    it("sits on a circle around the minimap at the saved angle, 225 by default", function()
        assert.are.equal(225, db.minimapAngle)
        local p = btn.points[#btn.points]
        local r = 140 / 2 + 10
        assert.are.equal("CENTER", p[1])
        assert.are.equal("BOTTOMLEFT", p[3])
        assert.is_true(math.abs(p[4] - (1000 + math.cos(math.rad(225)) * r)) < 0.01)
        assert.is_true(math.abs(p[5] - (600 + math.sin(math.rad(225)) * r)) < 0.01)
    end)

    it("is dragged around the minimap and keeps the angle", function()
        RUNSCRIPT(btn, "OnDragStart")
        STATE.cursor = { x = 1200, y = 600 } -- right of the centre: 0 degrees
        RUNSCRIPT(btn, "OnUpdate", 0.1)
        RUNSCRIPT(btn, "OnDragStop")
        assert.is_true(math.abs(db.minimapAngle) < 0.01)
    end)

    it("is not dragged in combat, and combat ends a drag", function()
        STATE.combat = true
        RUNSCRIPT(btn, "OnDragStart")
        assert.is_nil(btn.scripts.OnUpdate)
        STATE.combat = false
        RUNSCRIPT(btn, "OnDragStart")
        assert.is_function(btn.scripts.OnUpdate)
        STATE.combat = true
        FIRE("PLAYER_REGEN_DISABLED")
        assert.is_nil(btn.scripts.OnUpdate)
    end)

    it("is placed again after combat when combat skipped a placement", function()
        STATE.combat = true
        Minimap.cx = 500
        FIRE("PLAYER_ENTERING_WORLD")
        local x = btn.points[#btn.points][4]
        assert.is_true(math.abs(x - (1000 + math.cos(math.rad(225)) * 80)) < 0.01) -- not moved
        STATE.combat = false
        FIRE("PLAYER_REGEN_ENABLED")
        assert.is_true(math.abs(btn.points[#btn.points][4] - (500 + math.cos(math.rad(225)) * 80)) < 0.01)
        Minimap.cx = 1000
    end)

    it("is hidden and shown with /sgf minimap, saved", function()
        SlashCmdList.SMARTGROUPFILTER("minimap")
        assert.is_false(btn.shown)
        assert.is_true(db.hideMinimap)
        assert.is_true(said("Minimap button hidden."))
        SlashCmdList.SMARTGROUPFILTER("minimap")
        assert.is_true(btn.shown)
        assert.is_true(said("Minimap button shown."))
    end)

    it("waits for combat to end before it shows or hides", function()
        STATE.combat = true
        SlashCmdList.SMARTGROUPFILTER("minimap")
        assert.is_true(btn.shown)
        STATE.combat = false
        FIRE("PLAYER_REGEN_ENABLED")
        assert.is_false(btn.shown)
    end)

    it("starts hidden when it was hidden, and repairs a damaged angle", function()
        ns = addon.load("enUS", { db = { hideMinimap = true, minimapAngle = "north" } })
        FIRE("PLAYER_LOGIN")
        assert.is_false(ns.minimapButton.shown)
        assert.are.equal(225, SmartGroupFilterDB.minimapAngle)
        ns = addon.load("enUS", { db = { minimapAngle = 400 } })
        FIRE("PLAYER_LOGIN")
        assert.are.equal(225, SmartGroupFilterDB.minimapAngle)
    end)

    it("names its clicks in the tooltip, and Blizzard's reason when its button is disabled", function()
        RUNSCRIPT(btn, "OnEnter")
        assert.truthy(GameTooltip.lines[1]:find("SmartGroupFilter", 1, true))
        assert.are.equal("Left-click: open or close the Group Finder", GameTooltip.lines[2])
        assert.are.equal("Right-click: SmartGroupFilter settings", GameTooltip.lines[3])
        LFDMicroButton.enabled = false
        LFDMicroButton.disabledTooltip = function() return "Not available" end
        RUNSCRIPT(btn, "OnEnter")
        assert.are.equal("Not available", GameTooltip.lines[2])
        LFDMicroButton.enabled = true
    end)

    it("is listed in the help", function()
        SlashCmdList.SMARTGROUPFILTER("help")
        assert.is_true(said("/sgf minimap"))
    end)
end)
