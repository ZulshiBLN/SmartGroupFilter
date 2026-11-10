-- The WoW API the addon touches, mocked for busted. Only what the addon uses: a new API call
-- in the addon is added here with the behaviour the client shows, never guessed wider.
--
-- STATE holds the mocked world; tests/helpers/addon.lua sets it before the addon loads, and a
-- spec may change its fields afterwards. FIRE sends an event to every frame registered for it,
-- CHAT holds every line the addon printed, RUNSCRIPT runs a frame's script.

STATE = {
    locale = "enUS",
    version = "0.1.0",
}

CHAT = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    CHAT[#CHAT + 1] = table.concat(parts, " ")
end

function GetLocale() return STATE.locale end

C_AddOns = {
    GetAddOnMetadata = function(_, field)
        if field == "Version" then return STATE.version end
    end,
}

SlashCmdList = {}

local frames = {}

-- A widget: frame, button, texture, font string, edit box - one shape for all. It keeps what
-- the addon sets (text, shown, checked, points, size, atlas, desaturation) so a spec can read
-- it back; geometry (left, top, ...) comes from fields a spec may set. Methods the addon calls
-- that matter to no spec do nothing.
local Widget = {}
Widget.__index = Widget
local function noop() end
for _, m in ipairs({ "SetAutoFocus", "SetNumeric", "SetMaxLetters", "ClearFocus", "SetAllPoints",
    "RegisterForClicks", "RegisterForDrag", "SetFrameStrata", "SetPortraitShown", "SetTextColor",
    "SetMotionScriptsWhileDisabled" }) do
    Widget[m] = noop
end
function Widget:GetFrameStrata() return "MEDIUM" end

local function NewWidget(kind, name, parent, template)
    local w = setmetatable({
        kind = kind, name = name, parent = parent, template = template,
        events = {}, scripts = {}, points = {}, shown = true, children = {},
        width = 0, height = 0, left = 0, top = 0, right = 0, bottom = 0, scale = 1,
    }, Widget)
    if parent and parent.children then parent.children[#parent.children + 1] = w end
    if name then _G[name] = w end
    return w
end

function Widget:RegisterEvent(event) self.events[event] = true end
function Widget:UnregisterEvent(event) self.events[event] = nil end
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:GetScript(name) return self.scripts[name] end
function Widget:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...)
        if old then old(...) end
        fn(...)
    end
end
function Widget:SetText(s) self.text = s end
function Widget:GetText() return self.text end
function Widget:SetFormattedText(fmt, ...) self.text = fmt:format(...) end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:SetShown(v) self.shown = v and true or false end
function Widget:IsShown() return self.shown end
function Widget:SetChecked(v) self.checked = v and true or false end
function Widget:GetChecked() return self.checked end
function Widget:SetEnabled(v) self.enabled = v and true or false end
function Widget:Enable() self.enabled = true end
function Widget:Disable() self.enabled = false end
function Widget:IsEnabled() return self.enabled ~= false end
function Widget:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Widget:ClearAllPoints() self.points = {} end
function Widget:GetNumPoints() return #self.points end
function Widget:GetPoint(i) return unpack(self.points[i or 1]) end
function Widget:SetSize(w, h) self.width, self.height = w, h end
function Widget:SetWidth(w) self.width = w end
function Widget:SetHeight(h) self.height = h end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:GetLeft() return self.left end
function Widget:GetRight() return self.right end
function Widget:GetTop() return self.top end
function Widget:GetBottom() return self.bottom end
function Widget:GetEffectiveScale() return self.scale end
function Widget:SetAtlas(a) self.atlas = a return true end
function Widget:SetTexture(t) self.textureFile = t end
function Widget:SetAlpha(a) self.alpha = a end
function Widget:SetColorTexture(...) self.color = { ... } end
function Widget:SetDesaturated(v) self.desaturated = v and true or false end
function Widget:SetNumber(n) self.text = tostring(n) end
function Widget:GetNumber() return tonumber(self.text) or 0 end
function Widget:CreateTexture(name) return NewWidget("Texture", name, self) end
function Widget:CreateFontString(name) return NewWidget("FontString", name, self) end
function Widget:GetTitleText()
    self.titleText = self.titleText or NewWidget("FontString", nil, self)
    return self.titleText
end

function CreateFrame(kind, name, parent, template)
    local f = NewWidget(kind or "Frame", name, parent, template)
    if template and template:find("PortraitFrameTemplate") then
        f.CloseButton = NewWidget("Button", nil, f)
        function f:SetPortraitToAsset(path) self.portrait = path end
        f.Portrait = NewWidget("Texture", nil, f)
        f.Portrait:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 7)
        function f:GetPortrait() return self.Portrait end
    end
    if template == "LargeSideTabButtonTemplate" or template == "LFGVanillaRightTabTemplate" then
        f.Icon = NewWidget("Texture", nil, f)
        function f:SetCustomOnMouseUpHandler(fn) self.mouseUp = fn end
        function f:SetFillToInterior(v) self.fillToInterior = v end
    end
    frames[#frames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
STATE.cursor = { x = 0, y = 0 }
function GetCursorPosition() return STATE.cursor.x, STATE.cursor.y end

GameTooltip = NewWidget("GameTooltip", "GameTooltip")
GameTooltip.lines = {}
function GameTooltip:SetOwner(owner) self.owner, self.lines = owner, {} end
function GameTooltip:IsOwned(f) return self.owner == f end
function GameTooltip:AddLine(s) self.lines[#self.lines + 1] = s end
function GameTooltip:SetText(s) self.lines = { s } end

-- The client's own names, enUS
LOCALIZED_CLASS_NAMES_MALE = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
TANK, HEALER, DAMAGER = "Tank", "Healer", "Damage"

function FIRE(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

function RUNSCRIPT(frame, name, ...)
    return frame.scripts[name](frame, ...)
end

---------------------------------------------------------------------------
-- Group Finder, as the Forever client (1.60.1) shows it: Michel's dumps of 2026-11-10 and
-- Blizzard_LFGVanilla_Browse.lua. STATE.results: id -> { info = GetSearchResultInfo's table,
-- player = GetSearchResultPlayerInfo(id, 1)'s table }; STATE.order: the ids in list order.
---------------------------------------------------------------------------
STATE.results = {}
STATE.order = {}
STATE.activities = {}   -- activityID -> GetActivityInfoTable's table
STATE.activeEntry = nil -- GetActiveEntryInfo's table while the player is listed
STATE.maxLevel = 60
STATE.secret = {}       -- values issecretvalue reports as secret

function issecretvalue(v) return STATE.secret[v] == true end
function GetMaxPlayerLevel() return STATE.maxLevel end

C_LFGList = {
    GetSearchResultInfo = function(id)
        local r = STATE.results[id]
        return r and r.info
    end,
    GetSearchResultPlayerInfo = function(id, i)
        local r = STATE.results[id]
        return r and i == 1 and r.player or nil
    end,
    GetActiveEntryInfo = function() return STATE.activeEntry end,
    HasActiveEntryInfo = function() return STATE.activeEntry ~= nil end,
    -- Blizzard's own filtered results, before SmartGroupFilter's filter: every id
    GetFilteredSearchResults = function()
        local ids = {}
        for i, id in ipairs(STATE.order) do ids[i] = id end
        return #ids, ids
    end,
    GetActivityInfoTable = function(id) return STATE.activities[id] end,
}

-- hooksecurefunc for a global function: the original runs first, then the hook
function hooksecurefunc(name, hook)
    local original = _G[name]
    _G[name] = function(...)
        local r = { original(...) }
        hook(...)
        return unpack(r)
    end
end

-- Blizzard's sort: the mock keeps STATE.order as it is
function LFGBrowseUtil_SortSearchResults(results) end

-- Blizzard's Group Finder window with its side tabs (modern style), and the player list in it
LFGParentFrame = NewWidget("Frame", "LFGParentFrame", UIParent)
LFGParentFrame.right, LFGParentFrame.height = 400, 600
LFGParentFrame.BrowsingTab = NewWidget("CheckButton", nil, LFGParentFrame)
LFGParentFrame.BrowsingTab.right = 440
LFGParentFrame.WhoListingTab = NewWidget("CheckButton", nil, LFGParentFrame)

LFGBrowseFrame = NewWidget("Frame", "LFGBrowseFrame", LFGParentFrame)
LFGBrowseFrame.results = {}
LFGBrowseFrame.ActivityDropdown = { selectedValues = {} }
-- As Blizzard's: fresh results from the client, sorted, then drawn
function LFGBrowseFrame:UpdateResultList()
    local results = {}
    for i, id in ipairs(STATE.order) do results[i] = id end
    self.totalResults, self.results = #results, results
    LFGBrowseUtil_SortSearchResults(self.results)
end

-- The player: STATE.player = { class, level }
STATE.player = { class = "MAGE", level = 25 }
-- The group: STATE.party = { { name, class, level }, ... } without the player; STATE.leader
STATE.party = {}
STATE.leader = true
local function Unit(unit)
    if unit == "player" then return STATE.player end
    local i = tonumber(unit:match("^party(%d)$"))
    return i and STATE.party[i]
end
function UnitClass(unit)
    local u = Unit(unit or "player")
    if u then return u.class, u.class end
end
function UnitLevel(unit)
    local u = Unit(unit or "player")
    return u and u.level
end
function UnitName(unit)
    local u = Unit(unit)
    if u then return u.name or "Me", u.realm end
end
function GetNumGroupMembers() return #STATE.party > 0 and #STATE.party + 1 or 0 end
function IsInGroup() return #STATE.party > 0 end
function UnitIsGroupLeader() return STATE.leader end
function UnitIsGroupAssistant() return false end

STATE.time = 1000
function GetTime() return STATE.time end

-- The own roles (C_LFGListRoles) and the invites sent (C_PartyInfo)
STATE.ownRoles = { tank = false, healer = false, dps = true }
C_LFGListRoles = { GetRoles = function() return STATE.ownRoles end }
STATE.invites = {}
C_PartyInfo = { InviteUnit = function(name) STATE.invites[#STATE.invites + 1] = name end }

-- C_Timer.After queues; RUNTIMERS runs what is due, as the client's next frames would
STATE.timers = {}
C_Timer = {
    After = function(_, fn) STATE.timers[#STATE.timers + 1] = fn end,
}
function RUNTIMERS()
    local due = STATE.timers
    STATE.timers = {}
    for _, fn in ipairs(due) do fn() end
end

-- Templates the client knows: STATE.templates
STATE.templates = { LFGVanillaRightTabTemplate = true, LargeSideTabButtonTemplate = true }
C_XMLUtil = {
    GetTemplateInfo = function(name) return STATE.templates[name] and {} or nil end,
}

-- Blizzard's switch to the Group Browser page (Blizzard_LFGVanilla_ParentFrame.lua)
STATE.tab2Clicks = 0
function LFGParentFrameTab2_OnClick()
    STATE.tab2Clicks = STATE.tab2Clicks + 1
    LFGBrowseFrame.shown = true
end
ERR_DECLINE_GROUP_S = "%s declines your group invitation."
