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
function Widget:SetAllPoints(rel) self.allPointsTo = rel end
for _, m in ipairs({ "SetAutoFocus", "SetNumeric", "SetMaxLetters", "ClearFocus",
    "RegisterForClicks", "RegisterForDrag", "SetFrameStrata", "SetPortraitShown", "SetTextColor",
    "SetMotionScriptsWhileDisabled", "SetBlendMode", "SetHighlightTexture" }) do
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
function Widget:SetDrawLayer(layer, sublevel) self.drawLayer, self.sublevel = layer, sublevel end
-- BackdropTemplate: the backdrop's middle is the texture Center, as the client names it
function Widget:SetBackdrop(b)
    self.backdrop = b
    -- a part of the frame, not one of its children
    if not self.Center then
        self.Center = NewWidget("Texture")
        self.Center.parent = self
    end
end
function Widget:SetDesaturated(v) self.desaturated = v and true or false end
function Widget:SetNumber(n) self.text = tostring(n) end
function Widget:GetNumber() return tonumber(self.text) or 0 end
function Widget:CreateTexture(name, layer, _, sublevel)
    local t = NewWidget("Texture", name, self)
    t.drawLayer, t.sublevel = layer, sublevel
    return t
end
-- Animation groups: a flipbook records its cells and whether it plays
function Widget:CreateAnimationGroup()
    local group = { playing = false, animations = {} }
    group.SetLooping = function(g, v) g.looping = v end
    group.Play = function(g) g.playing = true end
    group.Stop = function(g) g.playing = false end
    function group.CreateAnimation(g, kind)
        local a = { kind = kind }
        a.SetFlipBookRows = function(anim, n) anim.rows = n end
        a.SetFlipBookColumns = function(anim, n) anim.columns = n end
        a.SetFlipBookFrames = function(anim, n) anim.frames = n end
        a.SetDuration = function(anim, d) anim.duration = d end
        g.animations[#g.animations + 1] = a
        return a
    end
    self.animGroup = group
    return group
end
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
    -- A secure action button: its OnClick performs the "click" action on "clickbutton"
    if template and template:find("SecureActionButtonTemplate") then
        f.attributes = {}
        -- The client's rule: a protected frame is anchored to its parent or nothing
        function f:SetPoint(point, rel, ...)
            if type(rel) == "table" and rel ~= self.parent then
                error("Cannot anchor protected frames to regions")
            end
            self.points[#self.points + 1] = { point, rel, ... }
        end
        function f:SetAttribute(k, v)
            if STATE.combat then error("SetAttribute on a secure button in combat") end
            self.attributes[k] = v
        end
        function f:GetAttribute(k) return self.attributes[k] end
        -- As SecureButton_GetModifiedAttribute: "type1"/"clickbutton1" for the left button,
        -- "...2" for the right, else the plain attribute
        f.scripts.OnClick = function(self, mouse)
            local n = mouse == "RightButton" and "2" or "1"
            local a = self.attributes
            local action = a["type" .. n] or a.type
            local target = a["clickbutton" .. n] or a.clickbutton
            if action == "click" and target then target:Click() end
        end
    end
    -- The modern menu dropdown: keeps its menu generator for the specs
    if template == "WowStyle1DropdownTemplate" then
        function f:SetupMenu(gen) self.menuGenerator = gen end
        function f:GenerateMenu() self.generated = (self.generated or 0) + 1 end
        f.Text = NewWidget("FontString", nil, f)
    end
    if template == "LargeSideTabButtonTemplate" or template == "LFGVanillaRightTabTemplate" then
        f.Icon = NewWidget("Texture", nil, f)
        function f:SetCustomOnMouseUpHandler(fn) self.mouseUp = fn end
        f.HighlightTexture = NewWidget("Texture", nil, f)
        f.HighlightTexture.shown = false
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
LFGParentFrame.ListingTab = NewWidget("Frame", nil, LFGParentFrame)

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
-- WoW Forever: a first name and a surname. UnitName gives the first name, GetUnitName(unit,
-- true) both, UnitFullName the two apart (Michel's dump, 2026-11-11). A unit's name in STATE
-- is the full one, "First Last".
local function Split(full)
    local first, last = (full or ""):match("^(%S+)%s+(.+)$")
    return first or full, last
end
function UnitName(unit)
    local u = Unit(unit)
    if u then return (Split(u.name or "Me")), u.realm end
end
function UnitFullName(unit)
    local u = Unit(unit)
    if u then return Split(u.name or "Me") end
end
function GetUnitName(unit)
    local u = Unit(unit)
    return u and (u.name or "Me")
end
function GetNumGroupMembers() return #STATE.party > 0 and #STATE.party + 1 or 0 end
function IsInGroup() return #STATE.party > 0 end
function UnitIsGroupLeader() return STATE.leader end
STATE.assistant = false
function UnitIsGroupAssistant() return STATE.assistant end

STATE.time = 1000
function GetTime() return STATE.time end

-- The own roles (C_LFGListRoles) and the invites sent (C_PartyInfo)
STATE.ownRoles = { tank = false, healer = false, dps = true }
C_LFGListRoles = { GetRoles = function() return STATE.ownRoles end }
STATE.invites = {}
C_PartyInfo = { InviteUnit = function(name) STATE.invites[#STATE.invites + 1] = name end }

-- Whispers sent: { text, chatType, target }
STATE.whispers = {}
C_ChatInfo = { SendChatMessage = function(text, chatType, _, target)
    STATE.whispers[#STATE.whispers + 1] = { text = text, chatType = chatType, target = target }
end }

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
ERR_ALREADY_IN_GROUP_S = "%s is already in a group."

-- Blizzard's search from the Group Finder (Blizzard_LFGVanilla_Browse.lua): results arrive
-- later with LFG_LIST_SEARCH_RESULTS_RECEIVED, which a spec fires
STATE.searches = 0
function LFGBrowse_DoSearch()
    STATE.searches = STATE.searches + 1
    LFGBrowseFrame.searching = true
end

-- Combat: STATE.combat
STATE.combat = false
function InCombatLockdown() return STATE.combat end

-- Blizzard's refresh arrow in the Group Finder: a click searches
LFGBrowseFrame.RefreshButton = NewWidget("Button", nil, LFGBrowseFrame)
function LFGBrowseFrame.RefreshButton:Click() LFGBrowse_DoSearch() end

-- Blizzard's hidden page buttons of the Group Finder window (Mainline ParentFrame.xml):
-- Tab1 the listing page, Tab2 the Group Browser; a click switches the page
STATE.tab1Clicks, STATE.tab2ButtonClicks = 0, 0
LFGParentFrameTab1 = NewWidget("Button", "LFGParentFrameTab1", LFGParentFrame)
function LFGParentFrameTab1:Click()
    STATE.tab1Clicks = STATE.tab1Clicks + 1
    LFGBrowseFrame.shown = false
    if LFGBrowseFrame.scripts.OnHide then LFGBrowseFrame.scripts.OnHide(LFGBrowseFrame) end
end
LFGParentFrameTab2 = NewWidget("Button", "LFGParentFrameTab2", LFGParentFrame)
function LFGParentFrameTab2:Click()
    STATE.tab2ButtonClicks = STATE.tab2ButtonClicks + 1
    LFGBrowseFrame.shown = true
    if LFGBrowseFrame.scripts.OnShow then LFGBrowseFrame.scripts.OnShow(LFGBrowseFrame) end
end

-- A player's click on a button: PreClick, OnClick (the secure action), PostClick
function CLICK(frame, button)
    for _, name in ipairs({ "PreClick", "OnClick", "PostClick" }) do
        if frame.scripts[name] then frame.scripts[name](frame, button or "LeftButton", false) end
    end
end

-- The minimap and Blizzard's micro menu button for the Group Finder (MainMenuBarMicroButtons.lua)
Minimap = NewWidget("Frame", "Minimap", UIParent)
Minimap.cx, Minimap.cy, Minimap.width, Minimap.height = 1000, 600, 140, 140
Minimap.strata, Minimap.level = "LOW", 2
function Widget:GetCenter() return self.cx, self.cy end
function Widget:SetFrameStrata(s) self.strata = s end
function Widget:GetFrameStrata() return self.strata or "MEDIUM" end
function Widget:SetFrameLevel(l) self.level = l end
function Widget:GetFrameLevel() return self.level or 1 end
STATE.microClicks = 0
LFDMicroButton = NewWidget("Button", "LFDMicroButton", UIParent)
function LFDMicroButton:Click() STATE.microClicks = STATE.microClicks + 1 end

-- Button textures: what a button was given, read back as a texture region would answer
function Widget:SetNormalAtlas(a) self.normalAtlas = a end
function Widget:SetPushedAtlas(a) self.pushedAtlas = a end
function Widget:SetHighlightAtlas(a) self.highlightAtlas = a end
function Widget:SetNormalTexture(t) self.normalTexture = t end
function Widget:SetPushedTexture(t) self.pushedTexture = t end
function Widget:GetAtlas() return self.atlas end
function Widget:GetTexture() return self.textureFile end
for _, part in ipairs({ "Normal", "Pushed", "Highlight" }) do
    Widget["Get" .. part .. "Texture"] = function(self)
        local t = NewWidget("Texture")
        t.atlas = self[part:lower() .. "Atlas"]
        t.textureFile = self[part:lower() .. "Texture"]
        return t
    end
end
function Widget:IsVisible()
    local f = self
    while f do
        if f.shown == false then return false end
        f = f.parent
    end
    return true
end

-- Text width: 7 px a byte, enough to compare entries; font objects are kept
function Widget:GetStringWidth() return #(self.text or "") * 7 end
function Widget:SetFontObject(f) self.fontObject = f end
function Widget:GetFontObject() return self.fontObject end

---------------------------------------------------------------------------
-- The bug report (Report.lua, Privacy.lua, Log.lua): the clock, the client build, the names
-- the client knows, BugGrabber, and the edit boxes and scroll frame of the report window
---------------------------------------------------------------------------
STATE.now = 1700000000 -- time(): seconds, as BugGrabber stores an error's time
function time() return STATE.now end
function GetBuildInfo() return "1.60.1", "99999", "Nov 1 2026", 16001 end
STATE.realm, STATE.guild = "Mockrealm", nil
function GetRealmName() return STATE.realm end
function GetNormalizedRealmName() return STATE.realm end
function GetGuildInfo() return STATE.guild end
UISpecialFrames = {}

-- A global the addon reads but a spec cannot set: busted gives each spec file its own globals
function SETGLOBAL(name, value) _G[name] = value end

for _, m in ipairs({ "SetMovable", "EnableMouse", "StartMoving", "StopMovingOrSizing", "SetJustifyH",
    "SetMultiLine", "SetCursorPosition", "SetScrollChild" }) do
    Widget[m] = noop
end
-- An edit box's selection: "all" or "none", as HighlightText() and HighlightText(0, 0) leave it
function Widget:HighlightText(from, to)
    self.selection = (from == 0 and to == 0) and "none" or "all"
end
function Widget:SetFocus()
    self.focused = true
    if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end
end
