-- The bug report (ruleset plan 2026-11-10-extras, phase 4; SimpleConjureBar's specs, adapted):
-- everything needed to find and fix a bug without asking the player back, and no other
-- player's name.

local addon = require("addon")

local function login(world)
    local ns = addon.load("enUS", world)
    SETGLOBAL("BugGrabber", nil)
    FIRE("PLAYER_LOGIN"); RUNTIMERS()
    return ns, SmartGroupFilterDB
end

local function contains(lines, pattern)
    for _, l in ipairs(lines) do if l:find(pattern) then return l end end
end

local function said(text)
    for _, line in ipairs(CHAT) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

local function clearChat()
    for i = #CHAT, 1, -1 do CHAT[i] = nil end
end

local function result(id, name, class, level, roles)
    STATE.results[id] = {
        info = { numMembers = 1, isDelisted = false, hasSelf = false, age = 0, activityIDs = { 800 } },
        player = { name = name, classFilename = class, level = level, lfgRoles = roles or {} },
    }
    STATE.order[#STATE.order + 1] = id
end

-- Listed for activity 800 (levels 20-30), fresh results the filter has read: a tank, a healer,
-- two damage dealers and one more damage dealer from another realm
local function listed()
    STATE.activities[800] = { minLevelSuggestion = 20, maxLevelSuggestion = 30 }
    STATE.activeEntry = { activityIDs = { 800 } }
    result(1, "Tankguy", "PALADIN", 25, { tank = true })
    result(2, "Healgal", "PRIEST", 24, { healer = true })
    result(3, "Dpsone", "WARLOCK", 25, { dps = true })
    result(4, "Dpstwo", "ROGUE", 25, { dps = true })
    result(5, "Farguy-Farrealm", "HUNTER", 26, { dps = true })
    LFGBrowseFrame:UpdateResultList()
    LFGBrowseFrame.searching = false
    FIRE("LFG_LIST_SEARCH_RESULTS_RECEIVED")
end

local function clickBuild(ns)
    RUNSCRIPT(ns.panel.buildButton, "OnClick", "LeftButton")
end

-- A BugGrabber as SimpleConjureBar's research found it on Forever: GetDB and GetSessionId, no
-- callback; entries with a Unix time and a session
local function grabber(errors, session)
    SETGLOBAL("BugGrabber", {
        GetDB = function() return errors end,
        GetSessionId = function() return session end,
    })
end

local function ourError(at, session, extra)
    local e = { message = "Interface/AddOns/SmartGroupFilter/Build.lua:10: attempt to index nil",
        stack = "[Interface/AddOns/SmartGroupFilter/Build.lua]:10: in function 'x'", counter = 2,
        time = at, session = session, locals = "self=<table>" }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

-- The report text, the window opened with a description, an area and details
local function report(ns, area, description, details)
    ns.OpenBugReport()
    local f = SmartGroupFilterReport
    if description then f.desc:SetText(description) end
    if details then f.details:SetText(details) end
    if area then f.SetArea(area) end
    return f.BuildText()
end

-- Every line belongs to a field of D.REPORT_FIELDS
local function allListed(ns, text)
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local known = false
        for _, f in ipairs(ns.D.REPORT_FIELDS) do
            if line:find(f.pattern) then known = true break end
        end
        assert.is_true(known, "not a listed field: " .. line)
    end
end

describe("the state snapshot", function()
    it("holds the build button's mode and reason key, the invited players, the listing and the counts", function()
        local ns = login()
        listed()
        clickBuild(ns)
        local lines = ns.StateSnapshot()
        local build = contains(lines, "^build ")
        assert.is_truthy(build:find("mode=build", 1, true), build)
        assert.is_truthy(build:find("reason=GROUP_FULL", 1, true), build) -- every place is held
        assert.is_truthy(contains(lines, "^invited TANK PALADIN 25 joined=false$"))
        assert.is_truthy(contains(lines, "^invited HEALER PRIEST 24 joined=false$"))
        assert.is_truthy(contains(lines, "^listing activities=800$"))
        assert.is_truthy(contains(lines, "^range 20%-30$"))
        local shown, total = ns.Counts()
        local roles = ns.RoleCounts()
        assert.is_truthy(contains(lines, ("^list shown=%d total=%d tank=%d healer=%d damage=%d filter=true$"):format(
            shown, total, roles.TANK, roles.HEALER, roles.DAMAGER)))
        assert.is_truthy(contains(lines, "^panel visible=true view=filter$"))
        assert.is_truthy(contains(lines, "^combat no$"))
        local all = table.concat(lines, "\n")
        for _, name in ipairs({ "Tankguy", "Healgal", "Dpsone", "Dpstwo", "Farguy" }) do
            assert.is_nil(all:find(name, 1, true), name)
        end
    end)

    it("reports the target dungeon by its ID, never by its name", function()
        local ns = login()
        listed()
        STATE.activities[800].fullName = "Shadowfang Keep"
        local text = report(ns, "BUILD")
        assert.is_truthy(text:find("declined=0 target=none", 1, true), text)
        clickBuild(ns)
        text = report(ns, "BUILD")
        assert.is_truthy(text:find("declined=0 target=800", 1, true), text)
        assert.is_nil(text:find("Shadowfang", 1, true), text)
    end)

    it("reports the build button by mode and key, never by its text", function()
        local ns = login()
        listed()
        ns.D.INVITES_PER_CLICK = 1
        ns.UpdateBuildButton()
        local button = ns.panel.buildButton
        assert.is_truthy(button:GetText():find("Tankguy", 1, true)) -- the text names him
        local text = report(ns, "BUILD")
        assert.is_nil(text:find("Tankguy", 1, true), text)
        assert.is_truthy(text:find("state build mode=build reason=none enabled=true", 1, true), text)

        STATE.time = STATE.time + ns.D.LIST_FRESH_SECONDS + 1 -- the list grows old: refresh
        ns.UpdateBuildButton()
        text = report(ns, "BUILD")
        assert.is_truthy(text:find("state build mode=refresh reason=LIST_OLD", 1, true), text)
        assert.is_nil(text:find(button.reason, 1, true), text)

        STATE.activeEntry = nil -- not listed: List Self
        ns.UpdateBuildButton()
        text = report(ns, "BUILD")
        assert.is_truthy(text:find("state build mode=list reason=LIST_SELF_TIP", 1, true), text)
    end)

    it("takes the window background whenever it shows, and names its value", function()
        local ns, db = login()
        db.windowOpacity = 80
        local text = report(ns, "SETTINGS")
        local f = SmartGroupFilterReport
        assert.are.equal(f.Center, f.opacityTexture)
        assert.are.same({ 0, 0, 0, 1 }, f.opacityLayer.color)
        assert.are.equal(1, f.opacityTexture.alpha)
        assert.are.equal(0.5, f.opacityLayer.alpha)
        assert.is_truthy(text:match("%- Settings: ([^\n]*)"):find("windowOpacity=80", 1, true), text)
    end)

    it("names the settings, the rows' order and their exclusions", function()
        local ns, db = login()
        db.excluded.DAMAGER.HUNTER = true
        db.excluded.DAMAGER.MAGE = true
        local text = report(ns, "SETTINGS")
        local settings = text:match("%- Settings: ([^\n]*)")
        assert.is_truthy(settings:find("allowDouble=false", 1, true), settings)
        assert.is_truthy(settings:find("allowSameArmor=true", 1, true), settings)
        assert.is_truthy(settings:find("panelShown=true", 1, true), settings)
        assert.is_truthy(settings:find("hideMinimap=false", 1, true), settings)
        assert.is_truthy(settings:find("minimapAngle=" .. ns.D.MINIMAP_ANGLE, 1, true), settings)
        assert.is_truthy(settings:find("dbVersion=" .. ns.D.DB_VERSION, 1, true), settings)
        assert.is_truthy(settings:find("orderTANK=" .. table.concat(ns.D.DEFAULT_ORDER.TANK, ","), 1, true), settings)
        assert.is_truthy(settings:find("excludedDAMAGER=HUNTER,MAGE", 1, true), settings)
        assert.is_truthy(settings:find("excludedTANK=-", 1, true), settings)
        assert.is_truthy(text:find("- Client: 1.60.1 (build 99999, interface 16001)", 1, true), text)
        assert.is_truthy(text:find("- Client locale: enUS, addon language: auto", 1, true), text)
        assert.is_truthy(text:find("- Character: MAGE, level 20-29, solo", 1, true), text)
        allListed(ns, text)
    end)
end)

describe("the action log", function()
    it("holds clicks, invites as role, class and level, commands and changed settings", function()
        local ns, db = login()
        listed()
        clickBuild(ns)
        local log = table.concat(ns.LogLines(), "\n")
        assert.is_truthy(log:find("click build button mode=build", 1, true), log)
        assert.is_truthy(log:find("invite TANK PALADIN 25", 1, true), log)
        assert.is_nil(log:find("Tankguy", 1, true), log)
        SlashCmdList.SMARTGROUPFILTER("minimap")
        SlashCmdList.SMARTGROUPFILTER("Somebody")
        log = table.concat(ns.LogLines(), "\n")
        assert.is_truthy(log:find("command minimap", 1, true), log)
        assert.is_truthy(log:find("setting hideMinimap=true", 1, true), log)
        assert.is_truthy(log:find("command other", 1, true), log)
        assert.is_nil(log:find("Somebody", 1, true), log)
        db.allowDouble = true
        ns.FilterChanged()
        assert.is_truthy(contains(ns.LogLines(), " setting allowDouble=true$"))
    end)

    it("holds the last 50 in order, and never breaks on a failing write", function()
        local ns = login()
        for i = 1, 60 do ns.Log("entry " .. i) end
        local lines = ns.LogLines()
        assert.are.equal(50, #lines)
        assert.is_truthy(lines[1]:find("entry 11$"), lines[1])
        assert.is_truthy(lines[50]:find("entry 60$"), lines[50])
        local clock = time
        SETGLOBAL("time", function() error("broken clock") end)
        ns.Log("lost") -- no error
        SETGLOBAL("time", clock)
        ns.LogFormat = function() error("broken format") end
        assert.are.equal("?", ns.LogLines()[1])
    end)

    it("knows whether a moment was in combat", function()
        local ns = login()
        local t0 = time()
        assert.are.equal("no", ns.CombatAt(t0))
        assert.are.equal("unknown", ns.CombatAt(t0 - 3600))
        FIRE("PLAYER_REGEN_DISABLED"); STATE.combat = true
        assert.are.equal("yes", ns.CombatAt(time()))
        STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED")
        assert.is_truthy(contains(ns.LogLines(), "combat start"))
        assert.is_truthy(contains(ns.LogLines(), "combat end"))
    end)
end)

describe("the report window", function()
    it("is opened by /sgf bug and by the settings' button", function()
        local ns = login()
        SlashCmdList.SMARTGROUPFILTER("bug")
        local f = SmartGroupFilterReport
        assert.is_true(f:IsShown())
        assert.is_truthy(f.report:GetText():find("^SGF1:"))
        f:Hide()
        ns.ShowView("settings")
        local bug = ns.panel.bugButton
        assert.are.equal(ns.L.BTN_REPORT_BUG, bug:GetText())
        assert.are.equal(ns.panel.opacitySlider, select(2, bug:GetPoint())) -- below the background slider
        RUNSCRIPT(bug, "OnClick")
        assert.is_true(f:IsShown())
        assert.are.equal("", f.desc:GetText())
    end)

    it("lists /sgf bug in the help", function()
        local ns = login()
        clearChat()
        SlashCmdList.SMARTGROUPFILTER("help")
        assert.is_true(said("/sgf bug|r - " .. ns.L.CMD_BUG))
    end)

    it("carries the area key and both texts, and offers every area", function()
        local ns = login()
        grabber({}, 1)
        local text = report(ns, "BUILD", "Build Group does nothing", "after a refresh")
        assert.is_truthy(text:find("**Area:** BUILD", 1, true), text)
        assert.is_truthy(text:find("**Description:** Build Group does nothing", 1, true), text)
        assert.is_truthy(text:find("**Details:** after a refresh", 1, true), text)
        local offered = {}
        local menu = SmartGroupFilterReport.areaMenu
        menu.menuGenerator(menu, { CreateRadio = function(_, label) offered[#offered + 1] = label end })
        assert.are.equal(#ns.D.REPORT_AREAS, #offered)
        for i, key in ipairs(ns.D.REPORT_AREAS) do assert.are.equal(ns.L["AREA_" .. key], offered[i]) end
    end)

    it("names the chosen area anew after a language switch", function()
        local ns = login()
        ns.OpenBugReport()
        local menu = SmartGroupFilterReport.areaMenu
        local before = menu.generated
        ns.ApplyLanguage("deDE")
        assert.are.equal(before + 1, menu.generated)
        local titled = false
        for _, child in ipairs(SmartGroupFilterReport.children) do
            if child.text == ns.locales.deDE.REPORT_TITLE then titled = true end
        end
        assert.is_true(titled)
    end)

    it("offers the code selected for copying, and the content to read", function()
        local ns = login()
        ns.OpenBugReport()
        local box = SmartGroupFilterReport.report
        assert.are.equal("all", box.selection)
        RUNSCRIPT(SmartGroupFilterReport.toggle, "OnClick")
        assert.is_truthy(box:GetText():find("^## SmartGroupFilter bug report"))
        assert.are.equal("none", box.selection)
        assert.are.equal(ns.D.BUG_REPORT_URL, SmartGroupFilterReport.url:GetText())
        assert.are.equal("https://github.com/ZulshiBLN/SmartGroupFilter/issues/new?template=bug_report.yml",
            ns.D.BUG_REPORT_URL)
    end)

    it("does not open in combat - /sgf bug says why, the button says nothing - and closes and comes back with combat", function()
        local ns = login()
        clearChat()
        STATE.combat = true
        ns.OpenBugReport()
        assert.is_false(SmartGroupFilterReport:IsShown())
        assert.are.equal(0, #CHAT)
        SlashCmdList.SMARTGROUPFILTER("bug")
        assert.is_false(SmartGroupFilterReport:IsShown())
        assert.is_true(said(ns.L.REPORT_COMBAT))
        STATE.combat = false
        ns.OpenBugReport()
        SmartGroupFilterReport.desc:SetText("kept")
        assert.is_true(SmartGroupFilterReport:IsShown())
        FIRE("PLAYER_REGEN_DISABLED")
        assert.is_false(SmartGroupFilterReport:IsShown())
        FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        assert.is_true(SmartGroupFilterReport:IsShown())
        assert.are.equal("kept", SmartGroupFilterReport.desc:GetText())
        SmartGroupFilterReport:Hide() -- closed by hand: no return after the next combat
        FIRE("PLAYER_REGEN_DISABLED"); FIRE("PLAYER_REGEN_ENABLED"); RUNTIMERS()
        assert.is_false(SmartGroupFilterReport:IsShown())
    end)

    it("dates nothing: times are relative to now and to the load", function()
        local ns = login()
        grabber({ ourError(time() - 90, 1) }, 1)
        local text = report(ns, "OTHER")
        assert.is_nil(text:find("%d%d%d%d%-%d%d%-%d%d"), text)
        assert.is_nil(text:find("%d%d:%d%d:%d%d"), text)
        assert.is_truthy(text:find("2 min ago", 1, true), text)
    end)

    it("says whether an error came in combat, and keeps earlier sessions and other addons out", function()
        local ns = login()
        STATE.now = STATE.now + 100
        FIRE("PLAYER_REGEN_DISABLED"); STATE.combat = true
        local inCombat = time()
        STATE.now = STATE.now + 10
        STATE.combat = false; FIRE("PLAYER_REGEN_ENABLED")
        STATE.now = STATE.now + 100
        grabber({
            ourError(inCombat, 3, { message = "Interface/AddOns/SmartGroupFilter/Build.lua:1: in combat" }),
            ourError(time() - 5, 3, { message = "Interface/AddOns/SmartGroupFilter/Build.lua:2: out of combat" }),
            ourError(time() - 99999, 3, { message = "Interface/AddOns/SmartGroupFilter/Build.lua:3: before the log" }),
            ourError(time() - 50, 2, { message = "Interface/AddOns/SmartGroupFilter/Build.lua:4: earlier session" }),
            ourError(time() - 5, 3, { message = "Interface/AddOns/Other/x.lua:5: foreign", stack = "foreign stack" }),
        }, 3)
        local text = report(ns, "OTHER")
        local function flagOf(what)
            for block in text:gmatch("Error %d+ %b()") do
                local _, finish = text:find(block, 1, true)
                if text:sub(finish, finish + 200):find(what, 1, true) then return block:match("combat: (%a+)") end
            end
        end
        assert.are.equal("yes", flagOf("in combat"))
        assert.are.equal("no", flagOf("out of combat"))
        assert.are.equal("unknown", flagOf("before the log"))
        assert.is_nil(text:find("earlier session", 1, true))
        assert.is_nil(text:find("foreign", 1, true))
        allListed(ns, text)
    end)

    it("takes errors without a session number only from the addon's load on", function()
        local ns = login()
        local at = ns.logStartClock
        STATE.now = STATE.now + 100
        grabber({
            ourError(at - 99999, nil, { message = "Interface/AddOns/SmartGroupFilter/Build.lua:1: before" }),
            ourError(at, nil, { message = "Interface/AddOns/SmartGroupFilter/Build.lua:2: atload" }),
        }, nil)
        local text = report(ns, "OTHER")
        assert.is_truthy(text:find("atload", 1, true), text)
        assert.is_nil(text:find("before", 1, true), text)
    end)

    it("says when BugGrabber is missing or has nothing from this addon", function()
        local ns = login()
        assert.is_truthy(report(ns, "OTHER"):find("**Lua errors:** BugGrabber/BugSack not installed", 1, true))
        grabber({}, 1)
        assert.is_truthy(report(ns, "OTHER"):find("**Lua errors:** none from SmartGroupFilter in this session", 1, true))
    end)
end)

-- Every byte sequence a whole UTF-8 character
local function validUtf8(s)
    local i = 1
    while i <= #s do
        local c = s:byte(i)
        local len = c < 0x80 and 1 or c >= 0xF0 and 4 or c >= 0xE0 and 3 or c >= 0xC0 and 2 or 0
        if len == 0 or i + len - 1 > #s then return false end
        for k = i + 1, i + len - 1 do
            local b = s:byte(k)
            if b < 0x80 or b > 0xBF then return false end
        end
        i = i + len
    end
    return true
end

-- Made-up names from every source SGF knows: the player, the realm, the guild, the group, the
-- search results (one with a realm), the invited players and one who declined
local POISON = {
    "Testplayer", "Mockrealm", "Testguild", "Partyone", "Otherrealm", "Tankguy", "Healgal", "Dpsone",
    "Farguy", "Farrealm", "Player-1111-0AAAAAAA", "Somebody#1234", "C:\\Users\\someone",
}

local function poison(ns)
    STATE.player.name = "Testplayer"
    STATE.guild = "Testguild"
    listed()
    clickBuild(ns) -- invites Tankguy, Healgal, Dpsone, Dpstwo
    FIRE("CHAT_MSG_SYSTEM", "Dpstwo declines your group invitation.")
    STATE.party = { { name = "Partyone", realm = "Otherrealm", class = "DRUID", level = 25 } }
    FIRE("GROUP_ROSTER_UPDATE")
    grabber({ ourError(time(), 1, {
        message = "Interface/AddOns/SmartGroupFilter/Build.lua:10: Tankguy and Farguy-Farrealm, Partyone-Otherrealm, Dpstwo Player-1111-0AAAAAAA Somebody#1234",
        stack = "[C:\\Users\\someone\\Interface\\AddOns\\SmartGroupFilter\\Build.lua]:10: in function 'Healgal'",
        locals = table.concat({ 'name="Healgal"', "self=<table> {", "  Healgal = 1", "}", "count=3" }, "\n"),
    }) }, 1)
end

describe("the report's privacy", function()
    it("lets no name of any source through, and every line is a listed field", function()
        local ns = login()
        poison(ns)
        local text = report(ns, "BUILD", "Testplayer, Tankguy and Dpsone broke it in Testguild on Mockrealm",
            "with Farguy, Farrealm, Partyone and Dpstwo, see C:\\Users\\someone\\x")
        for _, bad in ipairs(POISON) do
            assert.is_nil(text:find(bad, 1, true), bad .. " leaked:\n" .. text)
        end
        assert.is_nil(text:find("Dpstwo", 1, true), text)
        -- what the developer needs is still there
        assert.is_truthy(text:find("<name>", 1, true))
        assert.is_truthy(text:find("<guid>", 1, true))
        assert.is_truthy(text:find("<tag>", 1, true))
        assert.is_truthy(text:find("at [Interface/AddOns/SmartGroupFilter/Build.lua]:10:", 1, true), text)
        assert.is_truthy(text:find("local count=3", 1, true), text)
        assert.is_truthy(text:find("state invited TANK PALADIN 25", 1, true), text)
        allListed(ns, text)
    end)

    it("removes a name typed only in the description - one the Group Finder showed, also without its realm", function()
        local ns = login()
        listed()
        -- nowhere else in the report: only the search results knew these names
        local text = report(ns, "FILTER", "Healgal and Farguy are hidden", "farrealm players too")
        assert.is_truthy(text:find("**Description:** <name> and <name> are hidden", 1, true), text)
        assert.is_truthy(text:find("**Details:** <name> players too", 1, true), text)
        -- a name the addon never saw stays: the field says so (REPORT_PUBLIC)
        text = report(ns, "FILTER", "Unseenguy is hidden")
        assert.is_truthy(text:find("Unseenguy is hidden", 1, true), text)
    end)

    it("knows the names of the search results, the group and the invites", function()
        local ns = login()
        poison(ns)
        local names = ns.ReportNames()
        local set = {}
        for _, n in ipairs(names) do set[n] = true end
        for _, n in ipairs({ "Testplayer", "Mockrealm", "Testguild", "Partyone", "Otherrealm", "Partyone-Otherrealm",
            "Tankguy", "Healgal", "Dpsone", "Dpstwo", "Farguy-Farrealm", "Farguy", "Farrealm" }) do
            assert.is_true(set[n], n)
        end
        for i = 2, #names do assert.is_true(#names[i - 1] >= #names[i], names[i]) end
    end)

    it("keeps the window shut while a name is secret, and says why", function()
        local ns = login()
        STATE.party = { { name = "Secretguy", class = "DRUID", level = 25 } }
        STATE.secret.Secretguy = true
        ns.ShowView("settings")
        clearChat()
        RUNSCRIPT(ns.panel.bugButton, "OnClick") -- the settings show: the hint under the button
        assert.is_false(SmartGroupFilterReport:IsShown())
        assert.is_true(ns.panel.reportHint:IsShown())
        assert.are.equal(ns.L.REPORT_SECRET, ns.panel.reportHint:GetText())
        assert.are.equal(0, #CHAT)
        RUNTIMERS()
        assert.is_false(ns.panel.reportHint:IsShown())
        ns.ShowView("filter")
        SlashCmdList.SMARTGROUPFILTER("bug") -- no settings shown: the chat
        assert.is_false(SmartGroupFilterReport:IsShown())
        assert.is_true(said(ns.L.REPORT_SECRET))
        STATE.secret.Secretguy = nil
        ns.OpenBugReport()
        assert.is_true(SmartGroupFilterReport:IsShown())
    end)

    it("builds nothing new while a name turns secret after the window opened, and says so above the code", function()
        local ns = login()
        poison(ns)
        ns.OpenBugReport()
        local f = SmartGroupFilterReport
        local before = f.report:GetText()
        STATE.secret.Partyone = true
        f.desc:SetText("Testplayer saw it"); RUNSCRIPT(f.desc, "OnTextChanged", true)
        assert.are.equal(before, f.report:GetText())
        assert.are.equal(ns.L.REPORT_SECRET, f.step2:GetText())
        STATE.secret.Partyone = nil
        f.desc:SetText("clean"); RUNSCRIPT(f.desc, "OnTextChanged", true)
        assert.are.equal(ns.L.REPORT_STEP2, f.step2:GetText())
        assert.is_nil(ns.ReportCode.Decode(f.report:GetText()):find("Testplayer", 1, true))
    end)

    it("stays under 20,000 bytes, cut at a whole character, and shows the data list", function()
        local ns = login()
        local errors = {}
        for i = 1, 5 do
            local lines = {}
            for j = 1, 200 do lines[j] = ("v%d=%d"):format(j, j) end
            errors[i] = ourError(time(), 1, { message = ("Interface/AddOns/SmartGroupFilter/Build.lua:%d: %s"):format(i, ("ü"):rep(2000)),
                locals = table.concat(lines, "\n") })
        end
        grabber(errors, 1)
        local text = report(ns, "OTHER", ("ä"):rep(500), ("ö"):rep(500))
        assert.is_true(#text <= 20000, #text)
        assert.is_truthy(text:find(ns.D.REPORT_CUT, 1, true))
        assert.is_true(validUtf8(text))
        local function shown(key)
            for _, r in ipairs(SmartGroupFilterReport.children) do if r.text == ns.L[key] then return true end end
        end
        assert.is_true(shown("REPORT_PRIVACY"))
        assert.is_true(shown("REPORT_PUBLIC"))
    end)

    it("reports the addon language through the allowlist", function()
        local ns = login()
        SmartGroupFilterGlobalDB.language = "Testplayer"
        assert.is_truthy(report(ns, "OTHER"):find("addon language: <text:10>", 1, true))
        SmartGroupFilterGlobalDB.language = "deDE"
        assert.is_truthy(report(ns, "OTHER"):find("addon language: deDE", 1, true))
    end)

    it("filters the realm in both spellings and a two-letter name, longest first", function()
        local ns = login()
        STATE.realm = "Twin Peaks"
        STATE.player.name = "Testplayer"
        STATE.party = { { name = "Al", class = "PRIEST", level = 25 } }
        local names = ns.KnownNames()
        for i = 2, #names do assert.is_true(#names[i - 1] >= #names[i], names[i]) end
        assert.are.equal("<name> and Al hit <name>", ns.Scrub("Twin Peaks and Al hit Testplayer", { "Twin Peaks", "Testplayer" }))
        assert.are.equal("<name> and <name> hit <name>", ns.Scrub("Twin Peaks and Al hit Testplayer", names))
        STATE.realm = "Mockrealm"
    end)
end)

-- SimpleConjureBar's filter, unchanged: the cases its audits found (SimpleConjureBar's
-- report_spec, where each is explained)
describe("the report's text filter", function()
    it("filters spaced paths, e-mail, the WTF folder, account folders and hidden name joins", function()
        local ns = login()
        local names = { "Testplayer" }
        local cases = {
            { "C:\\Users\\John Doe\\Games\\x.lua:12: boom", "Doe", "<path>:12: boom" },
            { "see /home/John Doe/wow", "Doe", "see <path>" },
            { "see /Users/Jane Roe/wow", "Roe", "see <path>" },
            { "\\\\server\\share\\John Doe\\x", "Doe", "<path>" },
            { "write john.doe+wow@example.com now", "john", "write <email> now" },
            { "WTF\\Account\\MYACCOUNT\\SavedVariables\\x.lua", "MYACCOUNT", "<wtf>" },
            { "folder 12345678#1 here", "12345678", "folder <tag> here" },
            { "Testplayer\226\128\139 did it", "Testplayer", "<name> did it" },
            { "with\194\160Testplayer\194\160too", "Testplayer", "<name>" },
            { "Tes\226\129\160tplayer", "Tes", "<name>" },
            { "Testplayer\243\160\128\129", "Testplayer", "<name>" },
        }
        for _, c in ipairs(cases) do
            local out = ns.Scrub(c[1], names)
            assert.is_nil(out:find(c[2], 1, true), c[1] .. " -> " .. out)
            assert.is_truthy(out:find(c[3], 1, true), c[1] .. " -> " .. out)
        end
        assert.are.equal("see https://github.com/x and a: b", ns.Scrub("see https://github.com/x and a: b", names))
        assert.are.equal("Interface/AddOns/SmartGroupFilter/Build.lua:10: x",
            ns.Scrub("C:\\Program Files\\World of Warcraft\\_forever_\\Interface\\AddOns\\SmartGroupFilter\\Build.lua:10: x", names))
    end)

    it("finds a name beside any non-letter, inside CJK text and in non-ASCII capitals", function()
        local ns = login()
        local names = { "Testplayer", "\208\152\208\178\208\176\208\189", "T\195\168stplayer" }
        for _, input in ipairs({ "\226\128\158Testplayer\226\128\156", "\194\171Testplayer\194\187",
            "Testplayer\239\188\140\229\165\189", "\228\189\160\229\165\189Testplayer\228\189\160\229\165\189",
            "Testplayer\234\176\128", "TESTPLAYER", "\208\152\208\146\208\144\208\157", "T\195\136STPLAYER" }) do
            local out = ns.Scrub(input, names)
            assert.is_truthy(out:find("<name>", 1, true), input .. " -> " .. out)
        end
        assert.are.equal("<name> Secondname", ns.Scrub("Testplayer Secondname", names))
        assert.are.equal("Testplayerish", ns.Scrub("Testplayerish", names))
    end)

    it("takes display codes out, and finds what they hid or split", function()
        local ns = login()
        for _, row in ipairs({
            { "|cffc41f3bTesta|r failed", "<name> failed" },
            { "Tes|rta", "<name>" },
            { "joe@exa|rmple.de", "<email>" },
            { "|Hplayer:Unknownguy-Realm:1|h[click]|h", "[click]" },
            { "a | b", "a | b" },
        }) do
            assert.are.equal(row[2], ns.Scrub(row[1], { "Testa" }), row[1])
        end
    end)

    it("scrubs a long run without a space quickly", function()
        local ns = login()
        for _, input in ipairs({ ("a"):rep(20000) .. "@", ("a"):rep(20000) .. "#1234", ("|T"):rep(10000) }) do
            local start = os.clock()
            ns.Scrub(input, { "Testplayer" })
            assert.is_true(os.clock() - start < 0.5, input:sub(-6))
        end
    end)

    it("lets no name through a local's kind, nor prints text as an error count", function()
        local ns = login()
        local out = table.concat(ns.SafeLocals(table.concat({
            "who=<Testplayer>", "Other=<Secretguy> {", "}", "self=<table> {", "}", "count=3",
        }, "\n"), {}), "\n")
        assert.is_nil(out:find("Testplayer", 1, true), out)
        assert.is_nil(out:find("Secretguy", 1, true), out)
        assert.is_truthy(out:find("count=3", 1, true), out)
        grabber({ ourError(time(), 1, { counter = "Leakcounter" }) }, 1)
        local text = report(ns, "OTHER")
        assert.is_nil(text:find("Leakcounter", 1, true), text)
        assert.is_truthy(text:find("Error 1 (x1,", 1, true), text)
    end)
end)

describe("where the report opens", function()
    it("docks right of the panel from the settings' button, and closes with the panel", function()
        local ns = addon.load("enUS")
        FIRE("PLAYER_LOGIN")
        ns.panel.height = 535
        RUNSCRIPT(ns.panel.bugButton, "OnClick")
        local w = SmartGroupFilterReport
        assert.is_true(w.shown)
        assert.are.same({ "TOPLEFT", ns.panel, "TOPRIGHT", 4, 0 }, w.points[#w.points])
        assert.are.equal(535, w.height)
        assert.is_true(w.docked)
        RUNSCRIPT(ns.panel, "OnHide")
        assert.is_false(w.shown)
    end)

    it("opens as its own window in the middle with /sgf bug", function()
        local ns = addon.load("enUS")
        FIRE("PLAYER_LOGIN")
        SlashCmdList.SMARTGROUPFILTER("bug")
        local w = SmartGroupFilterReport
        assert.is_true(w.shown)
        assert.are.same({ "CENTER", UIParent, "CENTER", 0, 0 }, w.points[#w.points])
        assert.is_false(w.docked)
        assert.is_true(ns ~= nil)
    end)
end)
