-- Build Group (ruleset plan 2026-11-10-panel-filter-build, phase 4): one click chooses by the
-- rules in Logic.lua and invites; invited players keep their places.

local addon = require("addon")

local ns, db, button

local function result(id, name, class, level, roles, age)
    STATE.results[id] = {
        info = { numMembers = 1, isDelisted = false, hasSelf = false, age = age or 0, activityIDs = { 800 } },
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
    STATE.activities[800] = { minLevelSuggestion = 20, maxLevelSuggestion = 30, fullName = "Shadowfang Keep" }
    STATE.activities[801] = { minLevelSuggestion = 20, maxLevelSuggestion = 30, fullName = "Blackfathom Deeps" }
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

    it("invites only players listed for your dungeon", function()
        STATE.results[1].info.activityIDs = { 801 }
        click()
        assert.are.equal("War Pri Wlk Rog", table.concat(STATE.invites, " "))
    end)

    it("invites nobody whose dungeons are not loaded yet", function()
        STATE.results[1].info.activityIDs = nil
        click()
        assert.are.equal("War", STATE.invites[1])
    end)

    describe("the target dungeon", function()
        local function listedFor(id, ...)
            result(id, ...)
            STATE.results[id].info.activityIDs = { 801 }
        end

        local function line(text)
            for i, l in ipairs(CHAT) do
                if l:find(text, 1, true) then return i end
            end
        end

        local function count(text)
            local n = 0
            for _, l in ipairs(CHAT) do
                if l:find(text, 1, true) then n = n + 1 end
            end
            return n
        end

        before_each(function()
            for i = #CHAT, 1, -1 do CHAT[i] = nil end
            STATE.activeEntry = { activityIDs = { 801, 800 } }
            listedFor(7, "Dru", "DRUID", 25, { dps = true })
            LFGBrowseFrame:UpdateResultList()
            fresh()
        end)

        it("is named before the invites, and only players listed for it are invited", function()
            click() -- 800 would get four players, 801 one
            assert.are.equal("Pal Pri Wlk Rog", table.concat(STATE.invites, " "))
            local building = line("Building a group for Shadowfang Keep.")
            assert.truthy(building)
            assert.is_true(building < line("Invited Pal"))
        end)

        it("is kept while SGF's invites are pending, and named on every click", function()
            click()
            FIRE("CHAT_MSG_SYSTEM", "Rog declines your group invitation.")
            STATE.invites = {}
            click() -- chosen anew, 800 and 801 would tie at one, and 801 comes first
            assert.are.equal("Hun", table.concat(STATE.invites, " "))
            assert.are.equal(2, count("Building a group for Shadowfang Keep."))
        end)

        it("is kept while the group has members", function()
            click()
            STATE.party = { { name = "Pal", class = "PALADIN", level = 25 } }
            FIRE("GROUP_ROSTER_UPDATE")
            STATE.time = STATE.time + 121 -- the others let their invites run out
            RUNTIMERS()
            fresh()
            STATE.invites = {}
            click()
            assert.are.equal("Hun", table.concat(STATE.invites, " "))
            assert.are.equal(0, count("Blackfathom Deeps"))
        end)

        it("is chosen anew once the group is empty and no invite pending", function()
            listedFor(8, "Pa2", "PALADIN", 25, { tank = true })
            listedFor(9, "Sha", "SHAMAN", 25, { healer = true })
            LFGBrowseFrame:UpdateResultList()
            click() -- 800 four, 801 three
            assert.truthy(line("Building a group for Shadowfang Keep."))
            STATE.time = STATE.time + 121 -- nobody came
            RUNTIMERS()
            fresh()
            STATE.invites = {}
            click() -- 800 has War and Hun left, 801 Pa2, Sha and Dru
            assert.are.equal("Pa2 Sha Dru", table.concat(STATE.invites, " "))
            assert.truthy(line("Building a group for Blackfathom Deeps."))
        end)

        it("is chosen anew when it is no longer in your listing", function()
            click()
            FIRE("CHAT_MSG_SYSTEM", "Rog declines your group invitation.")
            STATE.activeEntry = { activityIDs = { 801 } }
            STATE.invites = {}
            click()
            assert.are.equal("Dru", table.concat(STATE.invites, " "))
            assert.truthy(line("Building a group for Blackfathom Deeps."))
        end)

        it("is never stored by the button's look or by /sgf test", function()
            STATE.party = { { name = "Xan", class = "HUNTER", level = 25 } } -- a member SGF did not invite
            FIRE("GROUP_ROSTER_UPDATE")
            SlashCmdList.SMARTGROUPFILTER("test")
            assert.truthy(line("Target dungeon: Shadowfang Keep - a click would choose it."))
            for id = 1, 6 do STATE.results[id].info.activityIDs = { 802 } end
            LFGBrowseFrame:UpdateResultList()
            click()
            assert.are.equal("Dru", table.concat(STATE.invites, " "))
            assert.truthy(line("Building a group for Blackfathom Deeps."))
        end)

        it("is named by /sgf test once chosen", function()
            click()
            SlashCmdList.SMARTGROUPFILTER("test")
            assert.truthy(line("Target dungeon: Shadowfang Keep - kept for your group."))
            assert.truthy(line("Dru DRUID 25 (damager, waits 0s): listed for your other dungeon, not the target"))
        end)
    end)

    describe("the whisper", function()
        local function whispers()
            local out = {}
            for i, w in ipairs(STATE.whispers) do out[i] = w.target .. ": " .. w.text end
            return table.concat(out, " | ")
        end

        it("asks a player listed for several roles which one, by his full name", function()
            STATE.results[1].player.name = "Pal Light"
            STATE.results[1].player.lfgRoles = { tank = true, dps = true }
            click()
            assert.are.equal("Pal Light: Tank for Shadowfang Keep?", whispers())
            assert.are.equal("WHISPER", STATE.whispers[1].chatType)
        end)

        it("asks a player with no role too", function()
            STATE.results[3].player.lfgRoles = {}
            click()
            assert.are.equal("Pri: Healer for Shadowfang Keep?", whispers())
        end)

        it("asks a player with one role listed for several dungeons for the target", function()
            STATE.results[4].info.activityIDs = { 801, 800 }
            click()
            assert.are.equal("Wlk: You want to join for Shadowfang Keep?", whispers())
        end)

        it("sends the role line alone to a player with several roles and dungeons", function()
            STATE.results[5].player.lfgRoles = { dps = true, tank = true }
            STATE.results[5].info.activityIDs = { 800, 801 }
            click()
            assert.are.equal("Rog: Damage for Shadowfang Keep?", whispers())
        end)

        it("sends nothing to a player with one role for one dungeon", function()
            click()
            assert.are.equal(4, #STATE.invites)
            assert.are.equal(0, #STATE.whispers)
        end)

        it("invites even when the whisper fails", function()
            STATE.results[1].player.lfgRoles = { tank = true, dps = true }
            STATE.results[3].player.lfgRoles = {}
            C_ChatInfo.SendChatMessage = function() error("No player named 'Pal'") end
            click()
            assert.are.equal("Pal Wlk Rog Pri", table.concat(STATE.invites, " ")) -- no role: last
        end)

        it("is sent from the click only", function()
            STATE.results[1].player.lfgRoles = { tank = true, dps = true }
            LFGBrowseFrame:UpdateResultList()
            ns.UpdateBuildButton()
            SlashCmdList.SMARTGROUPFILTER("test")
            FIRE("GROUP_ROSTER_UPDATE")
            STATE.time = STATE.time + 5
            RUNSCRIPT(button, "OnUpdate", 1)
            assert.are.equal(0, #STATE.whispers)
        end)
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

    it("knows an invited player with a surname once he joins (WoW Forever names)", function()
        STATE.results[1].player.name = "Pal Lightbringer"
        click()
        assert.are.equal("Pal Lightbringer", STATE.invites[1])
        STATE.party = { { name = "Pal Lightbringer", class = "PALADIN", level = 25 } }
        FIRE("GROUP_ROSTER_UPDATE")
        STATE.time = STATE.time + 500 -- far past the hold: only a joined player keeps his place
        RUNTIMERS()
        fresh()
        local state = ns.ReportBuildState()
        local joined = false
        for _, p in ipairs(state.invited) do if p.role == "TANK" and p.joined then joined = true end end
        assert.is_true(joined)
        STATE.invites = {}
        click()
        for _, n in ipairs(STATE.invites) do assert.are_not.equal("War", n) end -- no second tank
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
        it("points at Blizzard's eye tab when you are not listed, switching no page", function()
            STATE.activeEntry = nil
            ns.UpdateBuildButton()
            assert.are.equal("List Self", button.text)
            assert.is_true(button:IsEnabled())
            assert.is_nil(button:GetAttribute("type")) -- no secure action: SGF switches no page
            click()
            local glow = ns.listingGlow
            assert.is_true(glow.shown)
            -- Blizzard's proc loop, as SmartBlessingBar's button glow
            assert.are.equal("UI-HUD-ActionBar-Proc-Loop-Flipbook", glow.texture.atlas)
            assert.is_true(glow.anim.playing)
            assert.are.equal(30, glow.anim.animations[1].frames)
            assert.are.same({ LFGParentFrame.ListingTab }, { glow.allPointsTo })
            assert.are.equal(0, STATE.tab1Clicks)
            assert.are.equal(0, #STATE.invites)
            STATE.time = STATE.time + 6
            RUNTIMERS()
            assert.is_false(glow.shown) -- a few seconds, then gone
            RUNSCRIPT(glow, "OnHide")
            assert.is_false(glow.anim.playing)
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
        assert.are.equal("List yourself on Blizzard's eye tab, top right: choose the dungeon, play style and role there.",
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

        it("names players listed for another dungeon and those not loaded yet", function()
            STATE.results[1].info.activityIDs = { 801 }
            STATE.results[2].info.activityIDs = nil
            LFGBrowseFrame:UpdateResultList()
            SlashCmdList.SMARTGROUPFILTER("test")
            local out = lines()
            assert.truthy(out:find("Pal PALADIN 25 (tank, waits 0s): not listed for your dungeon", 1, true))
            assert.truthy(out:find("War WARRIOR 26 (tank, waits 0s): dungeon not loaded yet", 1, true))
        end)

        it("shows the target line and each invite's whisper, and sends none", function()
            STATE.results[1].player.lfgRoles = { tank = true, dps = true }
            LFGBrowseFrame:UpdateResultList()
            SlashCmdList.SMARTGROUPFILTER("test")
            local out = lines()
            assert.truthy(out:find("A click would print: Building a group for Shadowfang Keep.", 1, true))
            assert.truthy(out:find('row place 1\n      whisper: "Tank for Shadowfang Keep?"', 1, true))
            assert.truthy(out:find("Pri - PRIEST 24, healer, waits 0s, row place 1\n      no whisper", 1, true))
            assert.are.equal(0, #STATE.whispers)
            assert.are.equal(0, #STATE.invites)
        end)

        it("names how many dungeons a player listed for, when more than one", function()
            STATE.results[4].info.activityIDs = { 800, 801 }
            STATE.results[2].info.activityIDs = { 801, 800, 802 }
            LFGBrowseFrame:UpdateResultList()
            SlashCmdList.SMARTGROUPFILTER("test")
            local out = lines()
            assert.truthy(out:find("3. damager: Wlk - WARLOCK 25, damager, 2 dungeons, waits 0s", 1, true))
            assert.truthy(out:find("War WARRIOR 26 (tank, 3 dungeons, waits 0s)", 1, true))
            assert.truthy(out:find("1. tank: Pal - PALADIN 25, tank, waits 0s", 1, true))
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

-- Whom Check Roles asks and what they answered (ruleset plan 2026-11-11-roles-and-places,
-- phase 2): the members present when SGF first acts in the group; answers by event
describe("members' roles", function()
    local function roles()
        local asked, known = ns.BuildDev.Roles()
        local a, k = {}, {}
        for name in pairs(asked or {}) do a[#a + 1] = name end
        for name, role in pairs(known) do k[#k + 1] = name .. "=" .. role end
        table.sort(a)
        table.sort(k)
        return asked and table.concat(a, " ") or "not fixed", table.concat(k, " ")
    end

    local function join(...)
        STATE.party = {}
        for i, name in ipairs({ ... }) do STATE.party[i] = { name = name, class = "HUNTER", level = 25 } end
        FIRE("GROUP_ROSTER_UPDATE")
    end

    it("asks the members present when SGF first looks at a group", function()
        join("Fr")
        assert.are.equal("Fr", (roles()))
        join("Fr", "Late") -- joins after: never asked
        assert.are.equal("Fr", (roles()))
    end)

    it("asks nobody when the first click came alone", function()
        click()
        assert.are.equal("", (roles()))
        join("Pal") -- SGF invited him
        join("Pal", "Late")
        assert.are.equal("", (roles()))
    end)

    it("fixes the set on promotion to leader: before, SGF does not look", function()
        STATE.leader = false
        join("Fr")
        assert.are.equal("not fixed", (roles()))
        join("Fr", "Two")
        STATE.leader = true
        FIRE("PARTY_LEADER_CHANGED")
        assert.are.equal("Fr Two", (roles()))
    end)

    it("records the answers of those asked only, the new role from the event's fourth argument", function()
        join("Fr", "Two")
        FIRE("ROLE_CHANGED_INFORM", "Fr", "Me", "NONE", "HEALER")
        join("Fr", "Two", "Late")
        FIRE("ROLE_CHANGED_INFORM", "Late", "Me", "NONE", "TANK")
        local _, known = roles()
        assert.are.equal("Fr=HEALER", known)
    end)

    it("forgets a role set back to none, skips a secret name and the player's own answer", function()
        join("Fr")
        FIRE("ROLE_CHANGED_INFORM", "Fr", "Me", "NONE", "TANK")
        FIRE("ROLE_CHANGED_INFORM", "Fr", "Me", "TANK", "NONE")
        assert.are.equal("", select(2, roles()))
        STATE.secret["Fr"] = true
        FIRE("ROLE_CHANGED_INFORM", "Fr", "Me", "NONE", "TANK")
        STATE.secret["Fr"] = nil
        FIRE("ROLE_CHANGED_INFORM", ns.FullUnitName("player"), "Me", "NONE", "TANK")
        assert.are.equal("", select(2, roles()))
    end)

    it("knows an answer by the name with or without the realm", function()
        join("Fr-Realm")
        FIRE("ROLE_CHANGED_INFORM", "Fr", "Me", "NONE", "HEALER")
        assert.are.equal("Fr-Realm=HEALER", select(2, roles()))
    end)

    it("invites around the known roles", function()
        join("Fr")
        FIRE("ROLE_CHANGED_INFORM", "Fr", "Me", "NONE", "TANK")
        fresh()
        click()
        assert.are.equal("Pri Wlk Rog", table.concat(STATE.invites, " ")) -- no tank; a hunter member: Hun not
    end)

    it("forgets everything once the player is alone with no invite pending", function()
        join("Fr")
        FIRE("ROLE_CHANGED_INFORM", "Fr", "Me", "NONE", "TANK")
        join()
        assert.are.equal("not fixed", (roles()))
        assert.are.equal("", select(2, roles()))
    end)
end)
