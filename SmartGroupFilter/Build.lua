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

-- The group without the player: { { name, class, level } }; names as the Group Finder writes
-- them, "Name" or "Name-Realm"
local function Members()
    local list = {}
    for i = 1, math.max(0, GetNumGroupMembers() - 1) do
        local unit = "party" .. i
        local name, realm = UnitName(unit)
        name, realm = Clean(name), Clean(realm)
        if name then
            if realm and realm ~= "" then name = name .. "-" .. realm end
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
-- the reason it can do nothing
local function Plan()
    if not C_LFGList.HasActiveEntryInfo() then return nil, "NEED_LISTING" end
    if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return nil, "NOT_LEADER"
    end
    local members = Members()
    Prune(members)
    local _, class = UnitClass("player")
    local list, why = ns.ChooseInvites({
        own = { class = class, level = UnitLevel("player"), roles = C_LFGListRoles.GetRoles() },
        members = members, placed = placed, numGroupMembers = GetNumGroupMembers(),
        candidates = Candidates(), db = db, range = ns.LevelRange(),
    })
    if not list then return nil, why end
    if #list == 0 then
        -- Nobody chosen: no place left to fill, or no player for the places left
        local waiting, held = 0, 0
        for _, p in pairs(placed) do
            held = held + 1
            if not p.joined then waiting = waiting + 1 end
        end
        local free = D.GROUP_SIZE - math.max(1, GetNumGroupMembers()) - waiting
        local open = D.GROUP_SIZE - 1 - held -- role places: all but the player's own and SGF's
        return nil, (free <= 0 or open <= 0) and "GROUP_FULL" or "NO_CANDIDATE"
    end
    return list
end

local button

function ns.UpdateBuildButton()
    if not button then return end
    local list, why = Plan()
    button.reason = why and L[why] or nil
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
    end
    -- Look again once the invites have run out: their places may open
    C_Timer.After(D.HOLD_SECONDS + 1, ns.UpdateBuildButton)
    ns.UpdateBuildButton()
end

-- The button, below the options in the panel (Panel.lua calls this)
function ns.CreateBuildButton(parent, anchor)
    button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(160, 24)
    button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 4, -12)
    button:SetText(L.BUILD_GROUP)
    button:SetScript("OnClick", BuildGroup)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L.BUILD_GROUP)
        if self.reason then GameTooltip:AddLine(self.reason, 1, 0.2, 0.2) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.OnListFiltered(ns.UpdateBuildButton)
    ns.OnLanguageChanged(ns.UpdateBuildButton)
    ns.UpdateBuildButton()
    return button
end

-- An active decline: the client's system message ERR_DECLINE_GROUP_S ("%s declines your group
-- invitation.", in the client's language). The place opens at once, and the player is not
-- invited again this session (Michel, 2026-11-10).
local declinePattern
local function DeclinedName(msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return nil end
    if not declinePattern then
        if type(ERR_DECLINE_GROUP_S) ~= "string" then return nil end
        local escaped = ERR_DECLINE_GROUP_S:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
        declinePattern = "^" .. escaped:gsub("%%s", "(.+)") .. "$"
    end
    return msg:match(declinePattern)
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
events:SetScript("OnEvent", function(_, event, msg)
    if not button then return end
    if event == "CHAT_MSG_SYSTEM" then
        local name = DeclinedName(msg)
        if name then OnDeclined(name) end
        return
    end
    Prune(Members())
    ns.UpdateBuildButton()
end)
