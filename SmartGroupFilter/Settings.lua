-- SmartGroupFilter - settings view
-- A gear in the panel switches between the filter view and this settings view (ruleset plan
-- 2026-11-10-extras, phases 3 and 4): language, minimap button, bug report.
-- The minimap's right-click and the AddOn menu open it. The panel holds the protected build
-- button, so the views switch out of combat only.

local _, ns = ...
local L = ns.L

local db
ns.OnDBReady(function(d) db = d end)

local PAD = 14
local DD_WIDTH = 180
local DD_TEXT_PAD = 50 -- room beside the text: its inset and the arrow

local HINT_WIDTH = 220
local HINT_SECONDS = 8

local panel
local settingsNext = false -- open on the settings view the next time the panel shows

local function NotInCombat()
    if InCombatLockdown() then
        ns.Print(L.NOT_IN_COMBAT)
        return false
    end
    return true
end

-- "filter" or "settings"; false when combat forbids it
function ns.ShowView(view)
    if not panel or not NotInCombat() then return false end
    local settings = view == "settings"
    panel.view = view
    panel.filterView:SetShown(not settings)
    panel.settingsView:SetShown(settings)
    if panel.buildButton then panel.buildButton:SetShown(not settings) end
    return true
end

-- The minimap's right-click and the AddOn menu
function ns.OpenSettings()
    if not NotInCombat() then return end
    if panel and panel:IsVisible() then
        ns.ShowView("settings")
    else
        settingsNext = true
        ns.Print(L.SETTINGS_NEXT)
    end
end

-- Why the bug report did not open (a player name is secret), under its button for a while;
-- false when the settings view is not shown, so the caller says it in the chat
local hintShown = 0
function ns.ShowReportSecretHint()
    local hint = panel and panel.reportHint
    if not (hint and panel.settingsView:IsVisible()) then return false end
    ns.SetL(hint, "REPORT_SECRET")
    hint:Show()
    hintShown = hintShown + 1
    local mine = hintShown
    C_Timer.After(HINT_SECONDS, function()
        if mine == hintShown then hint:Hide() end
    end)
    return true
end

---------------------------------------------------------------------------
-- The gear: Blizzard's own gear of the Group Finder window, copied
---------------------------------------------------------------------------
local function CopyLook(gear)
    local src = LFGBrowseFrame and LFGBrowseFrame.OptionsButton
    local copied = false
    if src and src.GetNormalTexture then
        for _, part in ipairs({ "Normal", "Pushed", "Highlight" }) do
            local tex = src["Get" .. part .. "Texture"] and src["Get" .. part .. "Texture"](src)
            local atlas = tex and tex.GetAtlas and tex:GetAtlas()
            local file = tex and tex.GetTexture and tex:GetTexture()
            if atlas then
                gear["Set" .. part .. "Atlas"](gear, atlas)
                copied = true
            elseif file then
                gear["Set" .. part .. "Texture"](gear, file)
                copied = true
            end
        end
    end
    if not copied then
        gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
        gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    end
end

local function Gear()
    local gear = CreateFrame("Button", nil, panel)
    panel.gearButton = gear
    gear:SetSize(22, 22)
    -- Left of Reset Filter, whose width follows its translation
    gear:SetPoint("RIGHT", panel.resetButton, "LEFT", -6, 0)
    CopyLook(gear)
    gear:SetScript("OnClick", function()
        ns.ShowView(panel.view == "settings" and "filter" or "settings")
    end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(panel.view == "settings" and L.GEAR_BACK or L.SETTINGS)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Language: "Automatic" follows the client; a fixed choice is saved account-wide (SimpleConjure-
-- Bar's language dropdown, UI.AddDropdown, modern menu)
---------------------------------------------------------------------------
local function LanguageOptions()
    local opts = { { value = "auto", text = function()
        return L.LANG_AUTO:format(ns.LOCALE_NAMES[ns.clientLocale] or ns.clientLocale)
    end } }
    for _, code in ipairs(ns.LOCALE_ORDER) do
        opts[#opts + 1] = { value = code, text = function() return ns.LOCALE_NAMES[code] end }
    end
    return opts
end

local function CurrentLanguage()
    return SmartGroupFilterGlobalDB.language or "auto"
end

local function SetLanguage(v)
    SmartGroupFilterGlobalDB.language = (v ~= "auto") and v or nil
    ns.ApplyLanguage(v == "auto" and ns.clientLocale or v)
end

local function LanguageDropdown(view, anchor)
    local label = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ns.SetL(label, "LANGUAGE")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    panel.languageLabel = label
    local options = LanguageOptions()
    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, view, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        -- As wide as the longest entry in the dropdown's own font ("简体中文 (Chinese S.)" was
        -- cut short at a fixed width), as SimpleConjureBar's dropdown does
        local probe = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        probe:Hide()
        local function Fit()
            local font = dd.Text and dd.Text.GetFontObject and dd.Text:GetFontObject()
            if font then probe:SetFontObject(font) end
            local widest = 0
            for _, opt in ipairs(options) do
                probe:SetText(opt.text())
                widest = math.max(widest, probe:GetStringWidth())
            end
            dd:SetWidth(math.max(DD_WIDTH, math.ceil(widest) + DD_TEXT_PAD))
        end
        Fit()
        ns.OnLanguageChanged(Fit)
        dd:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
        dd:SetupMenu(function(_, root)
            for _, opt in ipairs(options) do
                root:CreateRadio(opt.text(), function() return CurrentLanguage() == opt.value end,
                    function() SetLanguage(opt.value) end)
            end
        end)
        ns.OnLanguageChanged(function() if dd.GenerateMenu then dd:GenerateMenu() end end)
        panel.languageDropdown = dd
    end
    return dd or label
end

---------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------
function ns.CreateSettingsView(p)
    panel = p
    local view = CreateFrame("Frame", nil, panel)
    view:SetAllPoints()
    view:Hide()
    panel.settingsView = view
    panel.view = "filter"
    Gear()

    local header = view:CreateFontString(nil, "OVERLAY", ns.HeaderFont())
    header:SetTextColor(1, 0.82, 0)
    ns.SetL(header, "SETTINGS")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -70)
    panel.settingsHeader = header

    local language = LanguageDropdown(view, header)

    local check = CreateFrame("CheckButton", nil, view, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", language, "BOTTOMLEFT", -4, -16)
    check.label = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    ns.SetL(check.label, "SHOW_MINIMAP")
    check:SetChecked(not db.hideMinimap)
    check:SetScript("OnClick", function(self)
        if db.hideMinimap == (self:GetChecked() and true or false) then ns.ToggleMinimapButton() end
    end)
    panel.minimapCheck = check

    -- The bug report (Report.lua); under it, for a while, why it did not open
    local bug = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    bug:SetSize(160, 22)
    bug:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 4, -16)
    ns.SetL(bug, "BTN_REPORT_BUG")
    bug:SetScript("OnClick", function() ns.OpenBugReport(true) end) -- docked to the panel
    panel.bugButton = bug
    local hint = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", bug, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(HINT_WIDTH)
    hint:SetJustifyH("LEFT")
    hint:Hide()
    panel.reportHint = hint

    panel:HookScript("OnShow", function()
        check:SetChecked(not db.hideMinimap)
        if settingsNext and not InCombatLockdown() then
            settingsNext = false
            ns.ShowView("settings")
        end
    end)
end
