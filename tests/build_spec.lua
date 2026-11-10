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

-- Fresh search results, as a search's answer brings them
local function fresh()
    LFGBrowseFrame.searching = false
    FIRE("LFG_LIST_SEARCH_RESULTS_RECEIVED")
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
    fresh()
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
        fresh()
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
        fresh()
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
        fresh()
        STATE.invites = {}
        click()
        assert.are.equal("Pal", STATE.invites[1])
    end)

    describe("in two steps", function()
        it("refreshes a list older than 30 seconds first, and invites from the fresh one", function()
            STATE.time = STATE.time + 31
            ns.UpdateBuildButton()
            assert.are.equal("Refresh List", button.text)
            assert.are.equal("The list is older than 30 seconds: refresh it first.", button.reason)
            click()
            assert.are.equal(1, STATE.searches)
            assert.are.equal(0, #STATE.invites)
            assert.is_false(button:IsEnabled()) -- searching
            fresh()
            assert.are.equal("Build Group", button.text)
            assert.is_true(button:IsEnabled())
            click()
            assert.are.equal(4, #STATE.invites)
        end)

        it("searches only through a secure click on Blizzard's own refresh arrow", function()
            assert.truthy(button.template:find("SecureActionButtonTemplate", 1, true))
            -- anchored to its parent only: the client refuses other anchors for it
            assert.are.equal(1, #button.points)
            assert.are.equal(ns.panel, button.points[1][2])
            assert.is_nil(button:GetAttribute("type"))
            STATE.time = STATE.time + 31
            ns.UpdateBuildButton()
            assert.are.equal("click", button:GetAttribute("type"))
            assert.are.equal(LFGBrowseFrame.RefreshButton, button:GetAttribute("clickbutton"))
            fresh()
            assert.is_nil(button:GetAttribute("type")) -- build mode: no secure action
            -- SGF never runs Blizzard's search or page switch itself: that tainted Blizzard's own
            -- Search() (incident 2026-11-11)
            for _, file in ipairs(addon.tocFiles()) do
                local code = addon.read("SmartGroupFilter/" .. file)
                for _, name in ipairs({ "LFGBrowse_DoSearch", "LFGParentFrameTab1_OnClick", "LFGParentFrameTab2_OnClick" }) do
                    assert.is_nil(code:find(name, 1, true), file .. ": " .. name)
                end
            end
        end)

        it("leaves the secure button alone in combat", function()
            STATE.combat = true
            STATE.time = STATE.time + 31
            assert.has_no.errors(function() ns.UpdateBuildButton() end)
            assert.are.equal("Build Group", button.text)
            STATE.combat = false
            ns.UpdateBuildButton()
            assert.are.equal("Refresh List", button.text)
        end)

        it("turns back into Refresh List when the results grow old", function()
            assert.are.equal("Build Group", button.text)
            STATE.time = STATE.time + 31
            RUNTIMERS()
            assert.are.equal("Refresh List", button.text)
        end)

        it("offers a refresh when no player fits an old list, not when the group is full", function()
            STATE.order = {}
            LFGBrowseFrame:UpdateResultList()
            STATE.time = STATE.time + 31
            ns.UpdateBuildButton()
            assert.are.equal("Refresh List", button.text)
            STATE.party = { { name = "A", class = "HUNTER", level = 25 }, { name = "B", class = "ROGUE", level = 25 },
                { name = "C", class = "PRIEST", level = 25 }, { name = "D", class = "PALADIN", level = 25 } }
            ns.UpdateBuildButton()
            assert.are.equal("Build Group", button.text)
            assert.are.equal("Your group is full.", button.reason)
        end)

        it("shows the list's age in /sgf test", function()
            STATE.time = STATE.time + 12
            for i = #CHAT, 1, -1 do CHAT[i] = nil end
            SlashCmdList.SMARTGROUPFILTER("test")
            assert.is_true(said("List from 12s ago."))
            STATE.time = STATE.time + 30
            SlashCmdList.SMARTGROUPFILTER("test")
            assert.is_true(said("List from 42s ago - older than 30s, the button refreshes it first."))
        end)
    end)

    it("looks again every second, so a run-out invite frees its place without an event", function()
        click()
        STATE.party = { { name = "Pal", class = "PALADIN", level = 25 }, { name = "Pri", class = "PRIEST", level = 24 },
            { name = "Wlk", class = "WARLOCK", level = 25 } }
        FIRE("GROUP_ROSTER_UPDATE")
        assert.is_false(button:IsEnabled()) -- three in the group, Rog still awaited: full
        ns.D.LIST_FRESH_SECONDS = 1000 -- the list stays fresh: only the clock moves
        STATE.time = STATE.time + 121 -- Rog never came; no event follows
        RUNSCRIPT(button, "OnUpdate", 0.5)
        assert.is_false(button:IsEnabled()) -- not yet a second
        RUNSCRIPT(button, "OnUpdate", 0.6)
        assert.is_true(button:IsEnabled())
        assert.are.equal("Build Group", button.text)
    end)

    it("says the group is full when the game delisted the full group", function()
        STATE.party = { { name = "A", class = "HUNTER", level = 25 }, { name = "B", class = "ROGUE", level = 25 },
            { name = "C", class = "PRIEST", level = 25 }, { name = "D", class = "PALADIN", level = 25 } }
        STATE.activeEntry = nil
        ns.UpdateBuildButton()
        assert.are.equal("Your group is full.", button.reason)
    end)

    it("lists SGF's invites with their state in /sgf test", function()
        click()
        STATE.party = { { name = "Pal", class = "PALADIN", level = 25 } }
        FIRE("GROUP_ROSTER_UPDATE")
        STATE.time = STATE.time + 20
        for i = #CHAT, 1, -1 do CHAT[i] = nil end
        SlashCmdList.SMARTGROUPFILTER("test")
        assert.is_true(said("Invited by SGF: Pal, tank - in the group."))
        assert.is_true(said("Invited by SGF: Pri, healer - waiting, 100s left."))
    end)

    it("treats a player already in another group like a decline", function()
        click()
        FIRE("CHAT_MSG_SYSTEM", "Rog is already in a group.")
        STATE.invites = {}
        click()
        assert.are.equal("Hun", table.concat(STATE.invites, " "))
    end)

    describe("List Self", function()
        it("opens Blizzard's listing page through a secure click when you are not listed", function()
            STATE.activeEntry = nil
            ns.UpdateBuildButton()
            assert.are.equal("List Self", button.text)
            assert.is_true(button:IsEnabled())
            assert.are.equal("click", button:GetAttribute("type"))
            assert.are.equal(LFGParentFrameTab1, button:GetAttribute("clickbutton"))
            click()
            assert.are.equal(1, STATE.tab1Clicks)
            assert.are.equal(0, #STATE.invites)
            assert.are.equal(0, STATE.searches)
        end)

        it("reads Build Group once Blizzard has listed you and searched", function()
            STATE.activeEntry = nil
            ns.UpdateBuildButton()
            STATE.activeEntry = { activityIDs = { 800 } }
            FIRE("LFG_LIST_ACTIVE_ENTRY_UPDATE", true)
            fresh()
            assert.are.equal("Build Group", button.text)
            assert.is_nil(button:GetAttribute("type"))
        end)

        it("comes before Refresh List, after a full group", function()
            STATE.activeEntry = nil
            STATE.time = STATE.time + 31 -- an old list too
            ns.UpdateBuildButton()
            assert.are.equal("List Self", button.text)
            STATE.party = { { name = "A", class = "HUNTER", level = 25 }, { name = "B", class = "ROGUE", level = 25 },
                { name = "C", class = "PRIEST", level = 25 }, { name = "D", class = "PALADIN", level = 25 } }
            ns.UpdateBuildButton()
            assert.is_false(button:IsEnabled())
            assert.are.equal("Your group is full.", button.reason)
        end)

        it("is not offered to an assistant: only the leader lists", function()
            STATE.activeEntry = nil
            STATE.party = { { name = "X", class = "HUNTER", level = 25 } }
            STATE.leader, STATE.assistant = false, true
            ns.UpdateBuildButton()
            assert.is_false(button:IsEnabled())
            assert.are.equal("Only the group leader can list the group.", button.reason)
        end)

        it("is offered to the leader of a group", function()
            STATE.activeEntry = nil
            STATE.party = { { name = "X", class = "HUNTER", level = 25 } }
            ns.UpdateBuildButton()
            assert.are.equal("List Self", button.text)
        end)
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

    it("names the reason in its tooltip, and what List Self does", function()
        STATE.party = { { name = "X", class = "HUNTER", level = 25 } }
        STATE.leader = false
        ns.UpdateBuildButton()
        RUNSCRIPT(button, "OnEnter")
        assert.are.equal("Only the group leader or an assistant can invite.", GameTooltip.lines[2])
        STATE.party, STATE.leader, STATE.activeEntry = {}, true, nil
        ns.UpdateBuildButton()
        RUNSCRIPT(button, "OnEnter")
        assert.are.equal("Opens Blizzard's listing page: choose the dungeon, play style and role there.",
            GameTooltip.lines[2])
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
            assert.truthy(out:find("War WARRIOR 26 (tank, waits 0s): tank places already filled", 1, true))
            assert.truthy(out:find("Old MAGE 35 (damager, waits 0s): level 35 outside 20-30", 1, true))
            assert.truthy(out:find("NoRole DRUID 25 (no role, waits 0s): tank/healer/damager places already filled", 1, true))
            assert.falsy(out:find("Left open", 1, true))
        end)

        it("names the class limit and the places nobody fits", function()
            result(7, "Ini", "MAGE", 25, { dps = true })
            STATE.results[1] = nil
            STATE.results[2] = nil
            LFGBrowseFrame:UpdateResultList()
            SlashCmdList.SMARTGROUPFILTER("test")
            local out = lines()
            assert.truthy(out:find("Ini MAGE 25 (damager, waits 0s): class limit: 1 MAGE already counted (you, your group and those chosen)", 1, true))
            assert.truthy(out:find("Left open: tank 1 - nobody fits.", 1, true))
        end)

        it("names exclusions, the armor rule, invited and declined players", function()
            db.excluded.DAMAGER.HUNTER = true
            click()
            FIRE("CHAT_MSG_SYSTEM", "Rog declines your group invitation.")
            for i = #CHAT, 1, -1 do CHAT[i] = nil end
            SlashCmdList.SMARTGROUPFILTER("test")
            local out = lines()
            assert.truthy(out:find("Hun HUNTER 25 (damager, waits 0s): no row takes this class", 1, true))
            assert.truthy(out:find("Pal PALADIN 25 (tank, waits 0s): already invited", 1, true))
            assert.truthy(out:find("Rog ROGUE 25 (damager, waits 0s): declined", 1, true))
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
