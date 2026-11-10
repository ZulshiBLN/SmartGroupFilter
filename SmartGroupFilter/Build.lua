-- SmartGroupFilter - Build Group
-- One click chooses by the rules in Logic.lua and invites (ruleset plan
-- 2026-11-10-panel-filter-build, phase 4). An invite needs a player's click (ruleset K5):
-- C_PartyInfo.InviteUnit runs only from the button, never from a timer or an event.
--
-- Placed players - the ones SGF invited - keep their role's place: while the invite is open
-- (D.HOLD_SECONDS), then as long as they are in the group. An invite declined or left to run
-- out opens the place again, and that player is not invited again this session (Michel).

local _, ns = ...
local D, L = ns.D, ns.L

local db
ns.OnDBReady(function(d) db = d end)

-- How many players one click invites. Whether the client lets one click send several invites
-- is checked in game first (plan, phase 4); 1 = one per click, the button naming whom next.
D.INVITES_PER_CLICK = D.INVITES_PER_CLICK or 5

local placed = {}   -- name -> { role, class, level, until, joined }
-- The dungeon (activityID) the group is built for, chosen by a click only (ruleset plan
-- 2026-11-11-build-dungeon). It holds while SGF's invites are pending or the group has
-- members and while it is in the own listing; then a click chooses anew.
local target
local declined = {} -- name -> true: an invite of this session ran out

local ROLE_KEY = { TANK = "ROLE_TANK", HEALER = "ROLE_HEALER", DAMAGER = "ROLE_DAMAGE" }
local ROLE_CLIENT = { TANK = "TANK", HEALER = "HEALER", DAMAGER = "DAMAGER" }

function ns.RoleName(role)
    return ns.LocalName(_G[ROLE_CLIENT[role]], ROLE_KEY[role])
end

local function Clean(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- A unit's name as the Group Finder writes it. WoW Forever gave characters surnames:
-- UnitName says "Zulsha", the Group Finder and whispers need "Zulsha Vashtar", which
-- GetUnitName(unit, true) gives (Michel's dump, 2026-11-11). Without it: name and realm.
function ns.FullUnitName(unit)
    if GetUnitName then
        local full = Clean(GetUnitName(unit, true))
        if full and full ~= "" then return full end
    end
    local name, realm = UnitName(unit)
    name, realm = Clean(name), Clean(realm)
    if name and realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

-- The group without the player: { { name, class, level } }, named as the Group Finder does
local function Members()
    local list = {}
    for i = 1, math.max(0, GetNumGroupMembers() - 1) do
        local unit = "party" .. i
        local name = ns.FullUnitName(unit)
        if name then
            local _, class = UnitClass(unit)
            list[#list + 1] = { name = name, class = Clean(class), level = Clean(UnitLevel(unit)) }
        end
    end
    return list
end

-- Ran-out invites leave; players seen in the group are joined; joined ones who left go
local function Prune(members)
    local inGroup = {}
    for _, m in ipairs(members) do inGroup[m.name] = true end
    local now = GetTime()
    for name, p in pairs(placed) do
        if inGroup[name] then
            p.joined = true
        elseif p.joined then
            placed[name] = nil -- left the group
        elseif now > p["until"] then
            placed[name] = nil
            declined[name] = true
        end
    end
end

-- The dungeons of the own listing; Build Group invites only players listed for one of them
local function OwnDungeons()
    local entry = C_LFGList.GetActiveEntryInfo()
    return ns.ReadActivities(entry and entry.activityIDs) or {}
end

-- The stored target if it still holds, else nil
local function KeptTarget(own, members)
    if not target then return nil end
    local listed = false
    for _, id in ipairs(own) do
        if id == target then listed = true end
    end
    if not listed then return nil end
    if #members > 0 then return target end
    for _, p in pairs(placed) do
        if not p.joined then return target end
    end
    return nil
end

function ns.DungeonName(id)
    local info = id and C_LFGList.GetActivityInfoTable(id)
    local name = info and Clean(info.fullName)
    return type(name) == "string" and name or ("#" .. tostring(id))
end

local function Candidates()
    local list = {}
    local _, ids = C_LFGList.GetFilteredSearchResults()
    for _, id in ipairs(ids or {}) do
        local entry = ns.ReadEntry(id)
        if entry and not (entry.name and declined[entry.name]) then list[#list + 1] = entry end
    end
    return list
end

-- What the next click would do: a list of { name, role, class, level }, or nil and the key of
-- the reason it can do nothing; then the state the choice was made from and its start (Logic)
local function Plan()
    -- A full group is delisted by the game: say it is full, not that the listing is missing
    if GetNumGroupMembers() >= D.GROUP_SIZE then return nil, "GROUP_FULL" end
    if not C_LFGList.HasActiveEntryInfo() then
        -- Only the leader lists a group; alone, anyone lists himself
        if IsInGroup() and not UnitIsGroupLeader("player") then return nil, "NOT_LEADER_LIST" end
        return nil, "NEED_LISTING"
    end
    if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return nil, "NOT_LEADER"
    end
    local members = Members()
    Prune(members)
    local _, class = UnitClass("player")
    local state = {
        own = { class = class, level = UnitLevel("player"), roles = C_LFGListRoles.GetRoles() },
        members = members, placed = placed, numGroupMembers = GetNumGroupMembers(),
        candidates = Candidates(), db = db, range = ns.LevelRange(),
    }
    -- The target a click keeps, or the one it would choose - read here, stored by the click only
    local own = OwnDungeons()
    state.target = KeptTarget(own, members)
    state.kept = state.target ~= nil
    state.target = state.target or ns.ChooseTarget(state, own)
    state.dungeons, state.ownDungeons = { state.target }, own
    local list, why, info = ns.ChooseInvites(state)
    if not list then return nil, why, state end
    if #list == 0 then
        -- Nobody chosen: no place left to fill, or no player for the places left
        local open = 0
        for _, n in pairs(info.open) do open = open + n end
        return nil, (info.free <= 0 or open <= 0) and "GROUP_FULL" or "NO_CANDIDATE", state, info
    end
    return list, nil, state, info
end

local button

-- Two steps on one button (Michel, 2026-11-11): results older than D.LIST_FRESH_SECONDS are
-- searched anew first - the search needs a click of its own, and the invites must come from
-- a click too (ruleset K5), so one click cannot search and then invite.
local lastResults -- GetTime() when the last search results arrived

local function ListAge()
    return lastResults and (GetTime() - lastResults) or nil
end

local function ListFresh()
    local age = ListAge()
    return age ~= nil and age <= D.LIST_FRESH_SECONDS
end

-- The button is a secure action button: in refresh mode it clicks Blizzard's own refresh arrow
-- (type "click"), so the protected search runs in Blizzard's secure code. Calling Blizzard's
-- search from addon code tainted LFGBrowseFrame.searching and later blocked Blizzard's own
-- Search() (Michel's BugSack, 2026-11-11; ruleset K5). A secure button cannot change in
-- combat: there the button keeps what it had.
local function SetMode(mode)
    if InCombatLockdown() then return false end
    if button.mode ~= mode then
        button.mode = mode
        -- refresh: Blizzard's refresh arrow. List Self has no secure action: SGF cannot switch
        -- the Group Finder's page safely, it points at Blizzard's eye tab instead
        local arrow = mode == "refresh" and LFGBrowseFrame and LFGBrowseFrame.RefreshButton or nil
        if arrow then
            button:SetAttribute("type", "click")
            button:SetAttribute("clickbutton", arrow)
        else
            button:SetAttribute("type", nil)
            button:SetAttribute("clickbutton", nil)
        end
    end
    return true
end

function ns.UpdateBuildButton()
    if not button or InCombatLockdown() then return end
    local list, why = Plan()
    -- Not listed: List Self points at Blizzard's eye tab; listing stays Blizzard's (Michel)
    if why == "NEED_LISTING" then
        SetMode("list")
        button.reason, button.reasonKey = L.LIST_SELF_TIP, "LIST_SELF_TIP"
        button:SetEnabled(true)
        button:SetText(L.LIST_SELF)
        return
    end
    -- Fresh results may bring a candidate the old ones lack; nothing else a search changes
    if not ListFresh() and (list or why == "NO_CANDIDATE") then
        SetMode("refresh")
        button.reason, button.reasonKey = L.LIST_OLD:format(D.LIST_FRESH_SECONDS), "LIST_OLD"
        button:SetEnabled(not (LFGBrowseFrame and LFGBrowseFrame.searching))
        button:SetText(L.REFRESH_LIST)
        return
    end
    SetMode("build")
    button.reason, button.reasonKey = why and L[why] or nil, why
    button:SetEnabled(list ~= nil)
    if list and D.INVITES_PER_CLICK == 1 then
        button:SetText(L.INVITE_NEXT:format(list[1].name, ns.RoleName(list[1].role)))
    else
        button:SetText(L.BUILD_GROUP)
    end
end


-- What to whisper with the invite, or nil: listed for several roles or none - which role;
-- for one role but several dungeons - which dungeon (Michel, 2026-11-11)
local function WhisperText(c, entry, dungeon)
    local roles = 0
    for _, field in pairs(D.ROLE_FIELD) do
        if entry and entry.roles and entry.roles[field] then roles = roles + 1 end
    end
    if roles ~= 1 then return D.WHISPER_ROLE:format(D.WHISPER_ROLE_NAMES[c.role], dungeon), "role" end
    if entry and entry.activities and #entry.activities > 1 then
        return D.WHISPER_DUNGEON:format(dungeon), "dungeon"
    end
end

local function EntryOf(name, state)
    for _, e in ipairs(state.candidates) do
        if e.name == name then return e end
    end
end

local function Whisper(c, state)
    local text, kind = WhisperText(c, EntryOf(c.name, state), ns.DungeonName(state.target))
    if not text then return end
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    -- A failed whisper must never stop the invite: skip it and say so in the log only
    local ok = pcall(send, text, "WHISPER", nil, c.name)
    ns.Log(("whisper %s %s %s%s"):format(kind, c.role, tostring(state.target), ok and "" or " failed"))
end

-- The click: invite and hold the places. Called only from the button's OnClick.
local function BuildGroup()
    local list, _, state = Plan()
    if not list then return ns.UpdateBuildButton() end
    target = state.target
    ns.Print(L.BUILDING_FOR:format(ns.DungeonName(target)))
    ns.Log("target " .. tostring(target))
    local now = GetTime()
    for i = 1, math.min(#list, D.INVITES_PER_CLICK) do
        local c = list[i]
        C_PartyInfo.InviteUnit(c.name)
        Whisper(c, state)
        placed[c.name] = { role = c.role, class = c.class, level = c.level, ["until"] = now + D.HOLD_SECONDS }
        ns.Print(L.INVITED:format(c.name, ns.RoleName(c.role), c.level))
        ns.Log(("invite %s %s %s"):format(c.role, ns.SafeValue(c.class), tostring(c.level)))
    end
    -- Look again once the invites have run out: their places may open
    C_Timer.After(D.HOLD_SECONDS + 1, ns.UpdateBuildButton)
    ns.UpdateBuildButton()
end

-- A protected frame may be anchored to its parent, not to the panel's other controls ("Cannot
-- anchor protected frames to regions", Michel's test 2026-11-11): bottom left of the panel,
-- beside the count in the bottom right corner
function ns.CreateBuildButton(parent)
    button = CreateFrame("Button", "SmartGroupFilterBuildButton", parent,
        "SecureActionButtonTemplate, UIPanelButtonTemplate")
    button:SetSize(160, 24)
    button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 14, 30)
    button:SetText(L.BUILD_GROUP)
    -- The secure action on the mouse button's release, whatever the key-down setting
    button:RegisterForClicks("LeftButtonUp")
    button:SetAttribute("useOnKeyDown", false)
    -- After the secure handler: in build mode invite; in refresh mode Blizzard's arrow has
    -- been clicked and the button only shows the search
    button:HookScript("OnClick", function()
        ns.Log("click build button mode=" .. ns.SafeValue(button.mode))
        if button.mode == "build" then
            BuildGroup()
        else
            if button.mode == "list" and ns.PointToListing then ns.PointToListing() end
            ns.UpdateBuildButton()
        end
    end)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self:GetText())
        -- Why it is greyed out in red; what it will do in white
        if self.reason then
            if self:IsEnabled() then GameTooltip:AddLine(self.reason, 1, 1, 1, true)
            else GameTooltip:AddLine(self.reason, 1, 0.2, 0.2, true) end
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.OnListFiltered(ns.UpdateBuildButton)
    -- Invites run out and lists grow old without an event: look again every second while the
    -- button is shown (Michel saw it stay greyed after a player was already in a group)
    local since = 0
    button:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since >= 1 then
            since = 0
            ns.UpdateBuildButton()
        end
    end)
    ns.OnLanguageChanged(ns.UpdateBuildButton)
    ns.UpdateBuildButton()
    return button
end

---------------------------------------------------------------------------
-- The bug report's view of Build Group (Report.lua): the button's mode and the key of its
-- reason - never its text, which can hold a player's name - and the invited players as role,
-- class and level. The names, kept apart, only feed the report's filter (Privacy.lua).
---------------------------------------------------------------------------
function ns.ReportBuildState()
    local state = { invited = {}, declined = 0 }
    state.target = KeptTarget(OwnDungeons(), Members())
    if button then
        state.mode, state.reasonKey, state.enabled = button.mode, button.reasonKey, button:IsEnabled()
    end
    for _, p in pairs(placed) do
        state.invited[#state.invited + 1] = { role = p.role, class = p.class, level = p.level, joined = p.joined and true or false }
    end
    local order = {}
    for i, role in ipairs(D.ROLES) do order[role] = i end
    table.sort(state.invited, function(a, b)
        if a.role ~= b.role then return (order[a.role] or 0) < (order[b.role] or 0) end
        if a.class ~= b.class then return tostring(a.class) < tostring(b.class) end
        return (tonumber(a.level) or 0) < (tonumber(b.level) or 0)
    end)
    for _ in pairs(declined) do state.declined = state.declined + 1 end
    return state
end

-- The names of the players SGF invited this session and of those who declined
function ns.InvitedNames()
    local names = {}
    for name in pairs(placed) do names[#names + 1] = name end
    for name in pairs(declined) do names[#names + 1] = name end
    return names
end

-- An active decline: the client's system message ERR_DECLINE_GROUP_S ("%s declines your group
-- invitation.", in the client's language). The place opens at once, and the player is not
-- invited again this session (Michel, 2026-11-10).
-- ERR_ALREADY_IN_GROUP_S ("%s is already in a group.") counts the same: he cannot come.
local declinePatterns
local function Pattern(format)
    if type(format) ~= "string" then return nil end
    local escaped = format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    return "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

local function DeclinedName(msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return nil end
    declinePatterns = declinePatterns or { Pattern(ERR_DECLINE_GROUP_S), Pattern(ERR_ALREADY_IN_GROUP_S) }
    for _, pattern in pairs(declinePatterns) do
        local name = msg:match(pattern)
        if name then return name end
    end
end

-- The system message names the player with or without his realm
local function PlacedName(name)
    if placed[name] then return name end
    for full in pairs(placed) do
        if full:match("^([^%-]+)") == name then return full end
    end
end

local function OnDeclined(name)
    local full = PlacedName(name)
    if not full or placed[full].joined then return end
    placed[full] = nil
    declined[full] = true
    ns.UpdateBuildButton()
end

local events = CreateFrame("Frame")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
events:RegisterEvent("LFG_LIST_SEARCH_FAILED") -- the button is clickable again
events:SetScript("OnEvent", function(_, event, msg)
    if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        lastResults = GetTime()
        -- The button turns back into Refresh List once these results grow old
        C_Timer.After(D.LIST_FRESH_SECONDS + 0.1, ns.UpdateBuildButton)
    end
    if not button then return end
    if event == "CHAT_MSG_SYSTEM" then
        local name = DeclinedName(msg)
        if name then OnDeclined(name) end
        return
    end
    Prune(Members())
    ns.UpdateBuildButton()
end)

-- What the development test (DevTest.lua, never packaged) reads; it calls nothing that sends
ns.BuildDev = {
    Plan = Plan, ListAge = ListAge, ListFresh = ListFresh, placed = placed, declined = declined,
    WhisperFor = function(c, state)
        return WhisperText(c, EntryOf(c.name, state), ns.DungeonName(state.target))
    end,
}
