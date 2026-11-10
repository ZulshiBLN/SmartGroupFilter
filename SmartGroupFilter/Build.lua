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
        local target = mode == "refresh" and LFGBrowseFrame and LFGBrowseFrame.RefreshButton or nil
        if target then
            button:SetAttribute("type", "click")
            button:SetAttribute("clickbutton", target)
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


-- The click: invite and hold the places. Called only from the button's OnClick.
local function BuildGroup()
    local list = Plan()
    if not list then return ns.UpdateBuildButton() end
    local now = GetTime()
    for i = 1, math.min(#list, D.INVITES_PER_CLICK) do
        local c = list[i]
        C_PartyInfo.InviteUnit(c.name)
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

---------------------------------------------------------------------------
-- /sgf test: what the next click would do and why, invites nothing (Michel, 2026-11-10).
-- Technical output, English on purpose (ruleset localization.md).
---------------------------------------------------------------------------
local function RolesText(roles)
    local out = {}
    for _, role in ipairs(D.ROLES) do
        if roles and roles[D.ROLE_FIELD[role]] then out[#out + 1] = role:lower() end
    end
    return #out > 0 and table.concat(out, "+") or "no role"
end

local function RowPlace(role, class)
    for i, c in ipairs(db.order[role]) do
        if c == class then return i end
    end
end

-- Why a single player of the list is not chosen, checked in the order Logic.lua checks
local function WhyNot(e, state, chosenNames, ownArmor, after)
    if e.isDelisted then return "delisted" end
    if not e.name then return "name not readable" end
    if not (e.class and e.level and e.level >= 1) then return "class or level not loaded yet" end
    if declined[e.name] then return "declined or let an invite run out" end
    if placed[e.name] then return "already invited" end
    for _, m in ipairs(state.members) do
        if m.name == e.name then return "in your group" end
    end
    local r = state.range
    if e.level < r.min or e.level > r.max then
        return ("level %d outside %d-%d"):format(e.level, r.min, r.max)
    end
    local fits = {}
    local signed = RolesText(e.roles) ~= "no role"
    for _, role in ipairs(D.ROLES) do
        if D.ROLE_CLASSES[role][e.class] and not db.excluded[role][e.class]
            and (not signed or e.roles[D.ROLE_FIELD[role]]) then
            fits[#fits + 1] = role
        end
    end
    if #fits == 0 then return "no row takes this class for its role" end
    if not db.allowSameArmor and ns.ArmorOf(e.class, e.level) == ownArmor then
        return "same armor class as you"
    end
    if chosenNames[e.name] then return nil end
    if not after then return "nothing is chosen" end
    local count = after.classCount[e.class] or 0
    if count >= D.MAX_SAME_CLASS[db.allowDouble and true or false] then
        return ("class limit: %d %s already counted (you, your group and those chosen)"):format(count, e.class)
    end
    local open = false
    for _, role in ipairs(fits) do
        if after.open[role] > 0 then open = true end
    end
    if not open then
        local names = {}
        for i, role in ipairs(fits) do names[i] = role:lower() end
        return table.concat(names, "/") .. " places already filled"
    end
    if after.free <= 0 then return "no free place left in the group" end
    return "not chosen - please report this line"
end

-- The state after the choice: places still open, free places, players per class
local function After(state, info, list)
    local after = { open = {}, free = info.free - #list, classCount = {} }
    for role, n in pairs(info.open) do after.open[role] = n end
    local count = after.classCount
    local function Add(class) if class then count[class] = (count[class] or 0) + 1 end end
    Add(state.own.class)
    local inGroup = {}
    for _, m in ipairs(state.members) do
        inGroup[m.name] = true
        Add(m.class)
    end
    for name, p in pairs(placed) do
        if not p.joined and not inGroup[name] then Add(p.class) end
    end
    for _, c in ipairs(list) do
        after.open[c.role] = after.open[c.role] - 1
        Add(c.class)
    end
    return after
end

function ns.DryRun()
    local list, why, state, info = Plan()
    ns.Print("Build Group test - nothing is sent.")
    if not state then
        print("  Would do nothing: " .. L[why])
        return
    end
    local age = ListAge()
    print(age and ("  List from %ds ago%s."):format(math.floor(age), ListFresh() and "" or " - older than "
        .. D.LIST_FRESH_SECONDS .. "s, the button refreshes it first") or "  No search results yet.")
    local own, r = state.own, state.range
    print(("  You: %s %s, listed as %s."):format(tostring(own.class), tostring(own.level), RolesText(own.roles)))
    print(("  Level range %d-%d; double classes %s; same armor class %s."):format(r.min, r.max,
        db.allowDouble and "allowed" or "not allowed", db.allowSameArmor and "allowed" or "not allowed"))
    local now = GetTime()
    for name, p in pairs(placed) do
        print(("  Invited by SGF: %s, %s - %s."):format(name, p.role:lower(), p.joined and "in the group"
            or ("waiting, %ds left"):format(math.max(0, math.floor(p["until"] - now)))))
    end
    if info then
        print(("  Your place: %s. Group %d of %d, free %d, invited and pending %d."):format(
            info.ownRole:lower(), math.max(1, state.numGroupMembers), D.GROUP_SIZE, info.free, info.waiting))
        print(("  Places to fill: tank %d, healer %d, damage %d."):format(info.open.TANK, info.open.HEALER,
            info.open.DAMAGER))
    end
    local chosenNames = {}
    if list then
        print(("  Would invite (%s):"):format(D.INVITES_PER_CLICK == 1 and "first one per click" or "all in one click"))
        for i, c in ipairs(list) do
            chosenNames[c.name] = true
            local e
            for _, cand in ipairs(state.candidates) do
                if cand.name == c.name then e = cand end
            end
            print(("   %d. %s: %s - %s %d, %s, waits %ds, row place %d"):format(i, c.role:lower(), c.name,
                c.class, c.level, RolesText(e and e.roles), e and e.age or 0, RowPlace(c.role, c.class) or 0))
        end
    else
        print("  Would invite nobody: " .. L[why])
    end
    local after = info and After(state, info, list or {})
    if after then
        local left = {}
        for _, role in ipairs(D.ROLES) do
            if after.open[role] > 0 then left[#left + 1] = ("%s %d"):format(role:lower(), after.open[role]) end
        end
        if #left > 0 then
            print(("  Left open: %s - %s."):format(table.concat(left, ", "),
                after.free > 0 and "nobody fits" or "no free place left in the group"))
        end
    end
    local ownArmor = ns.ArmorOf(own.class, own.level)
    print("  Not chosen:")
    local left = 0
    local _, ids = C_LFGList.GetFilteredSearchResults()
    for _, id in ipairs(ids or {}) do
        local e = ns.ReadEntry(id) or {}
        if e.numMembers == 1 and not e.hasSelf then
            local reason = WhyNot(e, state, chosenNames, ownArmor, after)
            if reason then
                left = left + 1
                print(("   - %s %s %s (%s, waits %ds): %s"):format(tostring(e.name), tostring(e.class),
                    tostring(e.level), RolesText(e.roles), e.age or 0, reason))
            end
        end
    end
    if left == 0 then print("   nobody") end
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
