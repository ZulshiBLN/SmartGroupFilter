-- SmartGroupFilter - panel
-- The panel beside Blizzard's player list (ruleset plan 2026-11-10-panel-filter-build, phase 3):
-- Reset Filter and the count, level range, the three priority rows, the two options. A child of
-- LFGBrowseFrame, so it shows and hides with the list; docked right of the window's side tabs.
-- A fourth side tab with the project's logo shows and hides it (Michel, 2026-11-10).

local _, ns = ...
local D, L = ns.D, ns.L

local db
ns.OnDBReady(function(d) db = d end)

local WIDTH = 300
local PAD = 14
local SLOT = 32        -- an icon's slot in a row, px
local ICON = 28
local PER_LINE = 5     -- icons per line; the damage row takes two lines
local TRACK = 236      -- the level slider's track, px
local SAME_ARMOR_ALPHA = 0.45 -- the cross over a class of the player's armor

local panel
local LayoutRows -- defined with the rows below

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- A setting changed: the filter is on again and filters anew; the rows show the new state
local function Changed()
    ns.FilterChanged()
    LayoutRows()
end

local function Label(parent, key, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    ns.SetL(fs, key)
    return fs
end

local function Check(parent, key, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = Label(cb, key, "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
        Changed()
    end)
    return cb
end

-- A section header as in SimpleConjureBar's settings (UI.AddHeader): a Blizzard font object a
-- bit larger than body text, in Blizzard gold
local HEADER_FONT
function ns.HeaderFont()
    HEADER_FONT = HEADER_FONT or (_G.GameFontNormalMed3 and "GameFontNormalMed3")
        or (_G.GameFontNormalMed2 and "GameFontNormalMed2") or "GameFontNormal"
    return HEADER_FONT
end

local function Header(parent, key)
    local h = parent:CreateFontString(nil, "OVERLAY", ns.HeaderFont())
    h:SetTextColor(1, 0.82, 0)
    ns.SetL(h, key)
    return h
end

-- A gold line as in SimpleConjureBar's settings (UI.AddSeparator): 2 px, strong in the middle,
-- fading to both ends. Placed `gap` px below `anchor`, centred in the panel.
local SEP_HEIGHT = 2
local SEP_R, SEP_G, SEP_B = 1, 0.82, 0
---------------------------------------------------------------------------
-- Window background, invisible to solid (ruleset plan 2026-11-11-window-opacity, as the
-- sisters do it). The dialog texture lets the game show through and never turns solid on its
-- own: below D.WINDOW_OPACITY_TODAY it fades out, above it the black layer beneath fades in.
-- window: the panel or the report, each with opacityTexture and opacityLayer.
---------------------------------------------------------------------------
function ns.ApplyWindowOpacity(window, value)
    if not (window and window.opacityLayer) then return end
    local today = D.WINDOW_OPACITY_TODAY
    window.opacityTexture:SetAlpha(math.min(1, value / today))
    window.opacityLayer:SetAlpha(math.max(0, (value - today) / (100 - today)))
end

local function Separator(parent, anchor, gap)
    local line = CreateFrame("Frame", nil, parent)
    line:SetSize(WIDTH - 2 * PAD, SEP_HEIGHT)
    line:SetPoint("LEFT", parent, "LEFT", PAD, 0)
    line:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
    local half = math.floor((WIDTH - 2 * PAD) * 0.45)
    local left, right = line:CreateTexture(nil, "ARTWORK"), line:CreateTexture(nil, "ARTWORK")
    for _, tex in ipairs({ left, right }) do
        tex:SetColorTexture(1, 1, 1, 1)
        if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(true) end
        if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
        if PixelUtil then PixelUtil.SetSize(tex, half, SEP_HEIGHT) else tex:SetSize(half, SEP_HEIGHT) end
    end
    left:SetPoint("RIGHT", line, "CENTER", 0, 0)
    right:SetPoint("LEFT", line, "CENTER", 0, 0)
    local gradientOk = false
    if CreateColor then
        local edge, mid = CreateColor(SEP_R, SEP_G, SEP_B, 0), CreateColor(SEP_R, SEP_G, SEP_B, 0.9)
        gradientOk = pcall(left.SetGradient, left, "HORIZONTAL", edge, mid)
            and pcall(right.SetGradient, right, "HORIZONTAL", mid, edge)
    end
    if not gradientOk then -- older clients: a plain line
        left:SetColorTexture(SEP_R, SEP_G, SEP_B, 0.75)
        right:SetColorTexture(SEP_R, SEP_G, SEP_B, 0.75)
    end
    return line
end

-- An atlas from Blizzard's art; a plain colour when this client lacks it (SetAtlas answers false)
local function Art(tex, atlas, r, g, b, a)
    if not tex:SetAtlas(atlas) then tex:SetColorTexture(r, g, b, a) end
end

local function ClassName(class)
    local client = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
    return ns.LocalName(client, "CLASS_" .. class)
end

---------------------------------------------------------------------------
-- Level range: two fields and a slider with two handles
---------------------------------------------------------------------------
local function MaxLevel()
    return GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
end

local function ShowRange(from, to)
    panel.fromBox:SetText(tostring(from))
    panel.toBox:SetText(tostring(to))
    local span = math.max(1, MaxLevel() - 1)
    for i, v in ipairs({ from, to }) do
        local h = panel.slider.handles[i]
        h:ClearAllPoints()
        h:SetPoint("CENTER", panel.slider, "LEFT", (v - 1) / span * TRACK, 0)
    end
end

local function RefreshRange()
    local r = ns.LevelRange()
    ShowRange(r.min, r.max)
end

local function ApplyRange(from, to)
    ns.SetLevelRange(from, to)
    RefreshRange()
    Changed()
end

local function TypedLevel(box)
    local n = tonumber(box:GetText())
    if not n then return nil end
    return math.max(1, math.min(MaxLevel(), math.floor(n)))
end

local function LevelBox(parent, isFrom)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(36, 20)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(2)
    -- A typed level past the other one moves the other one along: from 52 with to 12 is 52-52
    local function Apply(self)
        local r = ns.LevelRange()
        local v = TypedLevel(self)
        if v then
            if isFrom then ApplyRange(v, math.max(v, r.max)) else ApplyRange(math.min(r.min, v), v) end
        else
            RefreshRange()
        end
        self:ClearFocus()
    end
    box:SetScript("OnEnterPressed", Apply)
    box:SetScript("OnEscapePressed", function(self) RefreshRange() self:ClearFocus() end)
    return box
end

-- The level under the cursor on the slider's track
local function LevelAtCursor()
    local x = GetCursorPosition() / UIParent:GetEffectiveScale()
    local width = panel.slider:GetWidth()
    if width <= 0 then width = TRACK end
    local f = (x - panel.slider:GetLeft()) / width
    f = math.max(0, math.min(1, f))
    return 1 + math.floor(f * (MaxLevel() - 1) + 0.5)
end

local function Handle(slider, index)
    local h = CreateFrame("Button", nil, slider)
    h:SetSize(10, 16) -- as SimpleConjureBar's slider thumb (UI.MakeSlider)
    local tex = h:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetColorTexture(1, 0.82, 0, 1) -- WoW gold
    h:SetScript("OnMouseDown", function(self) self.dragging = true end)
    h:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local r = ns.LevelRange()
        local v = LevelAtCursor()
        local from, to = r.min, r.max
        if index == 1 then from = math.min(v, to) else to = math.max(v, from) end
        self.pending = { from, to }
        ShowRange(from, to)
    end)
    h:SetScript("OnMouseUp", function(self)
        self.dragging = false
        if self.pending then
            ApplyRange(self.pending[1], self.pending[2])
            self.pending = nil
        end
    end)
    return h
end

---------------------------------------------------------------------------
-- Priority rows
---------------------------------------------------------------------------
local ROLE_TEXT = {
    TANK = function() return ns.LocalName(TANK, "ROLE_TANK") end,
    HEALER = function() return ns.LocalName(HEALER, "ROLE_HEALER") end,
    DAMAGER = function() return ns.LocalName(DAMAGER, "ROLE_DAMAGE") end,
}

-- The slot index (1..n) under screen point x, y in a row, or nil outside it
function ns.SlotAt(row, x, y)
    local n = #db.order[row.role]
    local lines = math.ceil(n / PER_LINE)
    local col = math.floor((x - row:GetLeft()) / SLOT)
    local line = math.floor((row:GetTop() - y) / SLOT)
    if col < 0 or col >= PER_LINE or line < 0 or line >= lines then return nil end
    local index = line * PER_LINE + col + 1
    return math.min(index, n)
end

-- With "Allow same armor class" off: does this class wear the player's armor over the whole
-- level range? Hunters, shamans, warriors and paladins change armor at 40.
local function SameArmor(class)
    if db.allowSameArmor then return false end
    local own, r = ns.OwnArmor(), ns.LevelRange()
    return ns.ArmorOf(class, r.min) == own and ns.ArmorOf(class, r.max) == own
end

local function LayoutRow(row)
    local order = db.order[row.role]
    for i, class in ipairs(order) do
        local icon = row.icons[i]
        icon.class = class
        icon.index = i
        icon.texture:SetAtlas(D.CLASS_ATLAS[class])
        local excluded = db.excluded[row.role][class] and true or false
        icon.sameArmor = SameArmor(class)
        -- Excluded: the full red cross; the player's armor: the same cross, fainter (Michel)
        icon.texture:SetDesaturated(excluded or icon.sameArmor)
        icon.cross:SetShown(excluded or icon.sameArmor)
        icon.cross:SetAlpha(excluded and 1 or SAME_ARMOR_ALPHA)
        icon:ClearAllPoints()
        local col, line = (i - 1) % PER_LINE, math.floor((i - 1) / PER_LINE)
        icon:SetPoint("TOPLEFT", row, "TOPLEFT", col * SLOT, -line * SLOT)
    end
end

local function ShowTooltip(icon)
    GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ClassName(icon.class))
    GameTooltip:AddLine(L.TIP_DRAG, 1, 1, 1)
    if db.excluded[icon.row.role][icon.class] then GameTooltip:AddLine(L.EXCLUDED, 1, 0.2, 0.2) end
    if icon.sameArmor then GameTooltip:AddLine(L.SAME_ARMOR, 1, 0.2, 0.2) end
    GameTooltip:Show()
end

local function Icon(row)
    local icon = CreateFrame("Button", nil, row)
    icon.row = row
    icon:SetSize(ICON, ICON)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.cross = icon:CreateTexture(nil, "OVERLAY")
    icon.cross:SetAllPoints()
    Art(icon.cross, "common-icon-redx", 1, 0, 0, 0.4)
    icon:RegisterForClicks("RightButtonUp")
    icon:RegisterForDrag("LeftButton")
    icon:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" then return end
        local ex = db.excluded[row.role]
        ex[self.class] = (not ex[self.class]) or nil
        Changed()
        if GameTooltip:IsOwned(self) then ShowTooltip(self) end
    end)
    icon:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:SetFrameStrata("TOOLTIP")
        self:SetScript("OnUpdate", function(s)
            local scale = UIParent:GetEffectiveScale()
            local x, y = GetCursorPosition()
            s:ClearAllPoints()
            s:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        end)
    end)
    icon:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        self:SetFrameStrata(panel:GetFrameStrata())
        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        local to = ns.SlotAt(row, x / scale, y / scale)
        local order = db.order[row.role]
        if to and to ~= self.index then
            local class = table.remove(order, self.index)
            table.insert(order, to, class)
            Changed()
        end
        LayoutRow(row)
    end)
    icon:SetScript("OnEnter", ShowTooltip)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return icon
end

local function Row(parent, role, anchor, gap)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.SetL(label, ROLE_TEXT[role])
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap)
    local row = CreateFrame("Frame", nil, parent)
    row.role = role
    row.label = label
    -- The players shown for this role, small and white beside the header
    row.count = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("LEFT", label, "RIGHT", 4, 0)
    local n = #db.order[role]
    row:SetSize(PER_LINE * SLOT, math.ceil(n / PER_LINE) * SLOT)
    row:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    row.icons = {}
    for i = 1, n do row.icons[i] = Icon(row) end
    LayoutRow(row)
    return row
end

LayoutRows = function()
    for _, row in pairs(panel.rows) do LayoutRow(row) end
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
-- Right of the side tabs (Blizzard's modern style), else right of the window
-- The panel holds a secure button (Build.lua), so in combat it may not be moved, shown or
-- hidden by addon code: these keep what they had until combat ends.
local function Dock()
    if InCombatLockdown() then return end
    local tabs = LFGParentFrame.BrowsingTab
    local x = 4
    if tabs and tabs:GetRight() and LFGParentFrame:GetRight() then
        x = tabs:GetRight() - LFGParentFrame:GetRight() + 4
    end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", LFGParentFrame, "TOPRIGHT", x, 0)
    panel:SetHeight(LFGParentFrame:GetHeight())
end

local function UpdateCount(shown, total)
    panel.count:SetText(L.SHOWN_COUNT:format(shown, total))
    local counts = ns.RoleCounts()
    for role, row in pairs(panel.rows) do
        row.count:SetText(L.ROLE_COUNT:format(counts[role] or 0))
    end
end

local function RefreshAll()
    RefreshRange()
    LayoutRows()
    UpdateCount(ns.Counts())
end

-- The fourth side tab, below Blizzard's three, from Blizzard's side tab template. The full logo
-- fills the tab as Blizzard's icons do (SetFillToInterior: 50 px, masked to the tab's shape);
-- the rim is the template's own. Highlighted (Blizzard's "checked" glow) while the panel is
-- visible. A child of LFGBrowseFrame: it shows on the Group Browser only and shows or hides the
-- panel there. SGF cannot switch the Group Finder's pages safely: Blizzard's hidden tab buttons
-- fail in the modern style, and its page switch run from addon code taints what its search and
-- its listing read (Michel's choice, 2026-11-11; archive/incidents.md).
local function ToggleTab()
    local tab = CreateFrame("Frame", "SmartGroupFilterTab", LFGBrowseFrame, "LargeSideTabButtonTemplate")
    ns.tab = tab
    local who = LFGParentFrame.WhoListingTab
    if who then
        tab:SetPoint("TOPLEFT", who, "BOTTOMLEFT", 0, -2)
    else
        tab:SetPoint("TOPLEFT", LFGParentFrame, "TOPRIGHT", 0, -200)
    end
    if tab.Icon then tab.Icon:SetTexture(D.TAB_ICON) end
    if tab.SetFillToInterior then tab:SetFillToInterior(true) end
    tab.tooltipText = ns.ADDON_NAME
    local function Sync()
        if not InCombatLockdown() then panel:SetShown(db.panelShown) end
        if tab.SetChecked then tab:SetChecked(db.panelShown) end
    end
    local function Toggle()
        if InCombatLockdown() then return end
        db.panelShown = not db.panelShown
        Sync()
        ns.RefreshList()
    end
    tab.Toggle = Toggle
    if tab.SetCustomOnMouseUpHandler then
        tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
            if button == "LeftButton" and upInside then Toggle() end
        end)
    else
        tab:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then Toggle() end end)
    end
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.ADDON_NAME)
        GameTooltip:AddLine(L.TIP_TOGGLE, 1, 1, 1)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    LFGBrowseFrame:HookScript("OnShow", Sync)
    Sync()
end

-- List Self's pointer: Blizzard's eye tab (the listing page) glows for a few seconds. SGF does
-- not switch the page itself (see the side tab above).
local GLOW_SECONDS = 5
function ns.PointToListing()
    local target = LFGParentFrame.ListingTab
    if not target then return end
    local glow = ns.listingGlow
    if not glow then
        -- The modern client's proc loop, as SmartBlessingBar's button glow (ns.AttachAnts):
        -- Blizzard's flipbook atlas of 6 x 5 cells, 30 frames, 1.4 times the tab, on a frame of
        -- SGF's own above Blizzard's tab - the tab itself is not touched (Michel, 2026-11-11)
        glow = CreateFrame("Frame", nil, LFGParentFrame)
        ns.listingGlow = glow
        glow:SetAllPoints(target)
        glow:SetFrameStrata("HIGH")
        local size = math.max(target:GetWidth(), target:GetHeight())
        if size <= 0 then size = 55 end
        local tex = glow:CreateTexture(nil, "OVERLAY")
        tex:SetAtlas(D.GLOW_ATLAS)
        tex:SetPoint("CENTER")
        tex:SetSize(size * D.GLOW_SCALE, size * D.GLOW_SCALE)
        glow.texture = tex
        local anim = tex:CreateAnimationGroup()
        anim:SetLooping("REPEAT")
        local flip = anim:CreateAnimation("FlipBook")
        flip:SetFlipBookRows(D.GLOW_ROWS)
        flip:SetFlipBookColumns(D.GLOW_COLUMNS)
        flip:SetFlipBookFrames(D.GLOW_FRAMES)
        flip:SetDuration(D.GLOW_SECONDS_PER_LOOP)
        glow.anim = anim
        glow:SetScript("OnHide", function(self) self.anim:Stop() end)
    end
    glow:Show()
    glow.anim:Play()
    glow.token = (glow.token or 0) + 1
    local token = glow.token
    C_Timer.After(GLOW_SECONDS, function()
        if glow.token == token then glow:Hide() end
    end)
end

local function Create()
    panel = CreateFrame("Frame", "SmartGroupFilterPanel", LFGBrowseFrame, "PortraitFrameTemplate")
    ns.panel = panel
    panel:SetWidth(WIDTH)
    -- The sisters' window background: Blizzard's dark, textured dialog background, tiled
    -- (SimpleConjureBar's settings backdrop), in place of the template's own
    if panel.Bg then panel.Bg:Hide() end
    local bg = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background", "REPEAT", "REPEAT")
    if bg.SetHorizTile then bg:SetHorizTile(true) end
    if bg.SetVertTile then bg:SetVertTile(true) end
    bg:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -21)
    bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)
    panel.background = bg
    -- Beneath it a black layer, so the slider in the settings can make the panel solid
    local layer = panel:CreateTexture(nil, "BACKGROUND", nil, 0)
    layer:SetColorTexture(0, 0, 0, 1)
    layer:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -21)
    layer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)
    panel.opacityTexture, panel.opacityLayer = bg, layer
    ns.ApplyWindowOpacity(panel, db.windowOpacity)
    if panel.SetPortraitToAsset then panel:SetPortraitToAsset(D.LOGO) end
    -- The template places the portrait a little right of and below the ring's centre for this
    -- logo (Michel, in game): moved by D.PORTRAIT_NUDGE from wherever the template put it
    local portrait = panel.GetPortrait and panel:GetPortrait()
    if portrait and portrait:GetNumPoints() > 0 then
        local point, rel, relPoint, x, y = portrait:GetPoint(1)
        portrait:SetPoint(point, rel, relPoint, x + D.PORTRAIT_NUDGE[1], y + D.PORTRAIT_NUDGE[2])
    end
    if panel.CloseButton then panel.CloseButton:Hide() end
    panel:GetTitleText():SetText(ns.ADDON_NAME)

    -- The count in the bottom right corner (Michel), Reset Filter at the top right
    panel.count = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- level with the middle of the build button (Build.lua: 10 above the edge, 24 high)
    panel.count:SetPoint("RIGHT", panel, "BOTTOMRIGHT", -14, 22)
    -- The filter view: every filter control is its child, so the settings view (Settings.lua)
    -- hides them in one; the protected build button sits on the panel itself
    local view = CreateFrame("Frame", nil, panel)
    view:SetAllPoints()
    panel.filterView = view
    panel.resetButton = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    panel.resetButton:SetSize(120, 22)
    panel.resetButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -30)
    ns.SetL(panel.resetButton, "RESET_FILTER")
    panel.resetButton:SetScript("OnClick", function()
        ns.ResetFilter()
        panel.armorCheck:SetChecked(db.allowSameArmor)
        RefreshAll()
    end)

    local rangeLabel = Header(view, "LEVEL_RANGE")
    panel.rangeHeader = rangeLabel
    rangeLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -70)
    panel.fromBox = LevelBox(view, true)
    panel.fromBox:SetPoint("TOPLEFT", rangeLabel, "BOTTOMLEFT", 6, -6)
    panel.toBox = LevelBox(view, false)
    panel.toBox:SetPoint("TOPLEFT", rangeLabel, "BOTTOMLEFT", TRACK - 30, -6)
    local fromLabel = Label(view, "LEVEL_FROM", "GameFontHighlightSmall")
    fromLabel:SetPoint("LEFT", panel.fromBox, "RIGHT", 4, 0)
    local toLabel = Label(view, "LEVEL_TO", "GameFontHighlightSmall")
    toLabel:SetPoint("RIGHT", panel.toBox, "LEFT", -8, 0)

    local slider = CreateFrame("Frame", nil, view)
    panel.slider = slider
    slider:SetSize(TRACK, 20)
    slider:SetPoint("TOPLEFT", panel.fromBox, "BOTTOMLEFT", -2, -8)
    local bar = slider:CreateTexture(nil, "BACKGROUND")
    bar:SetPoint("LEFT")
    bar:SetPoint("RIGHT")
    bar:SetHeight(6)
    bar:SetColorTexture(0.25, 0.25, 0.25, 1) -- as SimpleConjureBar's slider track
    slider.handles = { Handle(slider, 1), Handle(slider, 2) }

    -- Gold line, then the priority section under its header (Michel, after SCB and SBB)
    panel.separators = { Separator(view, slider, 12) }
    panel.prioHeader = Header(view, "PRIORITIES")
    panel.prioHeader:SetPoint("TOPLEFT", panel.separators[1], "BOTTOMLEFT", 0, -12)

    panel.rows = {}
    local anchor = panel.prioHeader
    for i, role in ipairs(D.ROLES) do
        local row = Row(view, role, anchor, i == 1 and -8 or -14)
        panel.rows[role] = row
        anchor = row
    end

    -- Gold line, then the two options - no header
    panel.separators[2] = Separator(view, anchor, 12)
    panel.doubleCheck = Check(view, "ALLOW_DOUBLE",
        function() return db.allowDouble end, function(v) db.allowDouble = v end)
    panel.doubleCheck:SetPoint("TOPLEFT", panel.separators[2], "BOTTOMLEFT", -4, -10)
    panel.armorCheck = Check(view, "ALLOW_ARMOR",
        function() return db.allowSameArmor end, function(v) db.allowSameArmor = v end)
    panel.armorCheck:SetPoint("TOPLEFT", panel.doubleCheck, "BOTTOMLEFT", 0, -2)
    panel.buildButton = ns.CreateBuildButton(panel)

    panel:SetScript("OnShow", function()
        Dock()
        RefreshAll()
    end)
    ns.OnListFiltered(function() RefreshAll() end)
    ns.OnLanguageChanged(function() UpdateCount(ns.Counts()) end)
    Dock()
    RefreshAll()
    ToggleTab()
    ns.CreateSettingsView(panel)
end

-- Blizzard's Group Finder may load after this addon: build the panel once both are ready
local function TryCreate()
    if panel or not db or not LFGBrowseFrame then return end
    Create()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Main.lua reads the settings on PLAYER_LOGIN too; wait until it has
        ns.OnDBReady(TryCreate)
    else
        TryCreate()
    end
end)
