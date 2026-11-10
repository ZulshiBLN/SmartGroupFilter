-- Build Group (ruleset plan 2026-11-10-panel-filter-build, phase 4): one click chooses by the
-- rules in Logic.lua and invites; invited players keep their places.

local addon = require("addon")

local ns, db, button

local function result(id, name, class, level, roles, age)
    STATE.results[id] = {
        info = { numMembers = 1, isDelisted = false, hasSelf = false, age = age or 0 },
        player = { name = name, classFilename = class, level = level, lfgRoles = roles or {} },
    }
    STATE.order[#STATE.order + 1] = id
end

local function said(text)
    for _, line in ipairs(CHAT) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

local function click()
    RUNSCRIPT(button, "OnClick", "LeftButton")
end

before_each(function()
    ns = addon.load("enUS")
    FIRE("PLAYER_LOGIN")
    db = SmartGroupFilterDB
    button = ns.panel.buildButton
    STATE.activities[800] = { minLevelSuggestion = 20, maxLevelSuggestion = 30 }
    STATE.activeEntry = { activityIDs = { 800 } }
    result(1, "Pal", "PALADIN", 25, { tank = true })
    result(2, "War", "WARRIOR", 26, { tank = true })
    result(3, "Pri", "PRIEST", 24, { healer = true })
    result(4, "Wlk", "WARLOCK", 25, { dps = true })
    result(5, "Rog", "ROGUE", 25, { dps = true })
    result(6, "Hun", "HUNTER", 25, { dps = true })
    LFGBrowseFrame:UpdateResultList()
end)

describe("Build Group", function()
    it("invites a tank, a healer and two damage dealers around a damage dealer in one click", function()
        assert.is_true(button:IsEnabled())
        click()
        assert.are.equal("Pal Pri Wlk Rog", table.concat(STATE.invites, " "))
        assert.is_true(said("Invited Pal (Tank, level 25)."))
        assert.is_true(said("Invited Rog (Damage, level 25)."))
    end)

    it("chooses from the whole list, even while the Filter is reset", function()
        db.excluded.TANK.PALADIN = true
        ns.ResetFilter() -- exclusions gone, so the paladin may be chosen again
        click()
        assert.are.equal("Pal", STATE.invites[1])
    end)

    it("invites nobody twice while the invites are pending, and then nobody at all", function()
        click()
        click()
        assert.are.equal(4, #STATE.invites)
        assert.is_false(button:IsEnabled()) -- every place is held
        assert.are.equal("Your group is full.", button.reason)
    end)

    it("opens a declined player's place after 120 seconds, for his role only", function()
        click()
        STATE.party = { { name = "Pal", class = "PALADIN", level = 25 }, { name = "Pri", class = "PRIEST", level = 24 },
            { name = "Wlk", class = "WARLOCK", level = 25 } }
        FIRE("GROUP_ROSTER_UPDATE")
        STATE.time = STATE.time + 121 -- Rog never came
        RUNTIMERS()
        STATE.invites = {}
        click()
        assert.are.equal("Hun", table.concat(STATE.invites, " ")) -- a damage dealer, not a tank
    end)

    it("opens a place at once when the player declines, and never asks him again", function()
        click()
        FIRE("CHAT_MSG_SYSTEM", "Rog declines your group invitation.")
        STATE.invites = {}
        click()
        assert.are.equal("Hun", table.concat(STATE.invites, " ")) -- Rog's place, not Rog
    end)

    it("knows a declining player by his name without the realm", function()
        STATE.results[5].player.name = "Rog-Realm"
        click()
        FIRE("CHAT_MSG_SYSTEM", "Rog declines your group invitation.")
        STATE.invites = {}
        click()
        assert.are.equal("Hun", table.concat(STATE.invites, " "))
    end)

    it("ignores other system messages", function()
        click()
        FIRE("CHAT_MSG_SYSTEM", "Rog has joined the party.")
        FIRE("CHAT_MSG_SYSTEM", "Somebody declines your group invitation.")
        STATE.invites = {}
        click()
        assert.are.equal(0, #STATE.invites) -- every place still held
    end)

    it("keeps a joined player's place while he is in the group", function()
        click()
        STATE.party = { { name = "Pal", class = "PALADIN", level = 25 } }
        FIRE("GROUP_ROSTER_UPDATE")
        STATE.time = STATE.time + 500
        RUNTIMERS()
        STATE.invites = {}
        click()
        -- Pal keeps the tank place: War is not invited. Pri, Wlk and Rog let their invites run
        -- out and are not asked again; the hunter is the one damage dealer left
        assert.are.equal("Hun", table.concat(STATE.invites, " "))
    end)

    it("frees a place when the player leaves the group", function()
        click()
        STATE.party = { { name = "Pal", class = "PALADIN", level = 25 } }
        FIRE("GROUP_ROSTER_UPDATE")
        STATE.party = {}
        FIRE("GROUP_ROSTER_UPDATE")
        STATE.time = STATE.time + 500
        RUNTIMERS()
        STATE.invites = {}
        click()
        assert.are.equal("Pal", STATE.invites[1])
    end)

    it("is disabled without an own listing, and says why", function()
        STATE.activeEntry = nil
        ns.UpdateBuildButton()
        assert.is_false(button:IsEnabled())
        assert.are.equal("List yourself in the Group Finder first.", button.reason)
        click()
        assert.are.equal(0, #STATE.invites)
    end)

    it("is disabled when listed without a role", function()
        STATE.ownRoles = { tank = false, healer = false, dps = false }
        ns.UpdateBuildButton()
        assert.are.equal("Your listing has no role.", button.reason)
    end)

    it("is disabled in a group the player does not lead", function()
        STATE.party = { { name = "X", class = "HUNTER", level = 25 } }
        STATE.leader = false
        ns.UpdateBuildButton()
        assert.are.equal("Only the group leader or an assistant can invite.", button.reason)
    end)

    it("is disabled when no player fits", function()
        STATE.order = {}
        LFGBrowseFrame:UpdateResultList()
        assert.are.equal("No fitting player in the list.", button.reason)
    end)

    it("names the reason in its tooltip", function()
        STATE.activeEntry = nil
        ns.UpdateBuildButton()
        RUNSCRIPT(button, "OnEnter")
        assert.are.equal("List yourself in the Group Finder first.", GameTooltip.lines[2])
    end)

    describe("/sgf test", function()
        local function lines()
            return table.concat(CHAT, "\n")
        end

        before_each(function()
            for i = #CHAT, 1, -1 do CHAT[i] = nil end
        end)

        it("shows whom a click would invite and why, and invites nobody", function()
            result(7, "Old", "MAGE", 35, { dps = true })
            result(8, "NoRole", "DRUID", 25)
            LFGBrowseFrame:UpdateResultList()
            SlashCmdList.SMARTGROUPFILTER("test")
            local out = lines()
            assert.are.equal(0, #STATE.invites)
            assert.truthy(out:find("nothing is sent", 1, true))
            assert.truthy(out:find("You: MAGE 25, listed as damager.", 1, true))
            assert.truthy(out:find("Places to fill: tank 1, healer 1, damage 2.", 1, true))
            assert.truthy(out:find("1. tank: Pal - PALADIN 25, tank, waits 0s, row place 1", 1, true))
            assert.truthy(out:find("4. damager: Rog - ROGUE 25, damager, waits 0s, row place 3", 1, true))
            assert.truthy(out:find("War WARRIOR 26 (tank): tank places already filled", 1, true))
            assert.truthy(out:find("Old MAGE 35 (damager): level 35 outside 20-30", 1, true))
            assert.truthy(out:find("NoRole DRUID 25 (no role): tank/healer/damager places already filled", 1, true))
            assert.falsy(out:find("Left open", 1, true))
        end)

        it("names the class limit and the places nobody fits", function()
            result(7, "Ini", "MAGE", 25, { dps = true })
            STATE.results[1] = nil
            STATE.results[2] = nil
            LFGBrowseFrame:UpdateResultList()
            SlashCmdList.SMARTGROUPFILTER("test")
            local out = lines()
            assert.truthy(out:find("Ini MAGE 25 (damager): class limit: 1 MAGE already (you included)", 1, true))
            assert.truthy(out:find("Left open: tank 1 - nobody fits.", 1, true))
        end)

        it("names exclusions, the armor rule, invited and declined players", function()
            db.excluded.DAMAGER.HUNTER = true
            click()
            FIRE("CHAT_MSG_SYSTEM", "Rog declines your group invitation.")
            for i = #CHAT, 1, -1 do CHAT[i] = nil end
            SlashCmdList.SMARTGROUPFILTER("test")
            local out = lines()
            assert.truthy(out:find("Hun HUNTER 25 (damager): no row takes this class", 1, true))
            assert.truthy(out:find("Pal PALADIN 25 (tank): already invited", 1, true))
            assert.truthy(out:find("Rog ROGUE 25 (damager): declined", 1, true))
        end)

        it("says why it would do nothing", function()
            STATE.activeEntry = nil
            SlashCmdList.SMARTGROUPFILTER("test")
            assert.truthy(lines():find("Would do nothing: List yourself in the Group Finder first.", 1, true))
        end)

        it("is listed in the help", function()
            SlashCmdList.SMARTGROUPFILTER("help")
            assert.truthy(lines():find("/sgf test", 1, true))
        end)
    end)

    it("invites one player per click in one-per-click mode, naming the next on the button", function()
        ns.D.INVITES_PER_CLICK = 1
        ns.UpdateBuildButton()
        assert.are.equal("Invite: Pal (Tank)", button.text)
        click()
        assert.are.equal("Pal", table.concat(STATE.invites, " "))
        assert.are.equal("Invite: Pri (Healer)", button.text)
        click()
        click()
        click()
        assert.are.equal("Pal Pri Wlk Rog", table.concat(STATE.invites, " "))
    end)
end)
