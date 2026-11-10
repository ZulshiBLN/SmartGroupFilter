-- SmartGroupFilter - minimap button
-- SimpleConjureBar's minimap button (look and drag), made secure (ruleset plan
-- 2026-11-10-extras, phase 1): a left-click clicks Blizzard's Group Finder micro button
-- (LFDMicroButton) through a secure action, so the window opens in Blizzard's own code - as
-- that button and its key do, on the listing page. A right-click opens SGF's settings.
--
-- The button is parented and anchored to UIParent: a protected child would make the minimap
-- protected, and minimap addons could no longer change it in combat. It is placed from the
-- minimap's centre; in combat it is neither moved, shown, hidden nor dragged - a placement
-- combat skipped follows when combat ends.

local _, ns = ...
local D, L = ns.D, ns.L

local db
local button
local pending = false -- a placement or show/hide waits for the end of combat

local function Radius()
    return Minimap:GetWidth() / 2 + 10
end

-- The minimap's centre in UIParent's coordinates
local function MinimapCentre()
    local mx, my = Minimap:GetCenter()
    if not mx then return nil end
    local k = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return mx * k, my * k, k
end

local function Apply()
    if not button then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    local mx, my, k = MinimapCentre()
    if mx then
        local angle = math.rad(db.minimapAngle)
        local r = Radius() * k
        button:ClearAllPoints()
        button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx + math.cos(angle) * r, my + math.sin(angle) * r)
    end
    button:SetShown(not db.hideMinimap)
end

function ns.ToggleMinimapButton()
    db.hideMinimap = not db.hideMinimap
    Apply()
    if db.hideMinimap then
        ns.Print(L.MINIMAP_HIDDEN:format("|cffffd100" .. D.SLASH .. " minimap|r"))
    else
        ns.Print(L.MINIMAP_SHOWN)
    end
end

---------------------------------------------------------------------------
-- Drag around the minimap
---------------------------------------------------------------------------
local function OnDrag()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    db.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    Apply()
end

local function StopDrag()
    if button then button:SetScript("OnUpdate", nil) end
end

---------------------------------------------------------------------------
-- Tooltip: what the clicks do; Blizzard's reason when its Group Finder button is disabled
---------------------------------------------------------------------------
local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("SmartGroupFilter |cffffffffv" .. ns.VERSION .. "|r")
    local micro = LFDMicroButton
    if micro and micro.IsEnabled and not micro:IsEnabled() and micro.disabledTooltip then
        local reason = micro.disabledTooltip
        if type(reason) == "function" then reason = reason() end
        if type(reason) == "string" then GameTooltip:AddLine(reason, 1, 0.2, 0.2, true) end
    else
        GameTooltip:AddLine(L.MM_LEFT, 0, 1, 0)
    end
    GameTooltip:AddLine(L.MM_RIGHT, 0, 1, 0)
    GameTooltip:AddLine(L.MM_DRAG, 0, 1, 0)
    GameTooltip:Show()
end

local function Create()
    button = CreateFrame("Button", "SmartGroupFilterMinimapButton", UIParent, "SecureActionButtonTemplate")
    ns.minimapButton = button
    button:SetSize(31, 31)
    button:SetFrameStrata(Minimap:GetFrameStrata())
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetAttribute("useOnKeyDown", false)
    if LFDMicroButton then
        button:SetAttribute("type1", "click")
        button:SetAttribute("clickbutton1", LFDMicroButton)
    end
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- SimpleConjureBar's look: dark disc, the logo, Blizzard's tracking border
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(D.TAB_ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self:SetScript("OnUpdate", OnDrag)
    end)
    button:SetScript("OnDragStop", StopDrag)
    -- After the secure action: the right-click opens the settings
    button:SetScript("PostClick", function(_, mouse)
        if mouse == "RightButton" and ns.OpenSettings then ns.OpenSettings() end
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", Apply) end
    Apply()
end

---------------------------------------------------------------------------
-- Addon compartment (plan, phase 2). Blizzard's menu calls these as addon code - no secure
-- click is possible there, so the entry opens SGF's settings, as the right-click does.
-- The TOC names the three globals (ruleset code.md allows exactly these).
---------------------------------------------------------------------------
function SmartGroupFilter_OnCompartmentClick()
    if ns.OpenSettings then ns.OpenSettings() end
end

function SmartGroupFilter_OnCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_RIGHT")
    GameTooltip:AddLine("SmartGroupFilter |cffffffffv" .. ns.VERSION .. "|r")
    GameTooltip:AddLine(L.COMPARTMENT_CLICK, 0, 1, 0)
    GameTooltip:AddLine(L.COMPARTMENT_HINT, 1, 1, 1, true)
    GameTooltip:Show()
end

function SmartGroupFilter_OnCompartmentLeave()
    GameTooltip:Hide()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        StopDrag()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then Apply() end
    else
        Apply()
    end
end)

ns.OnDBReady(function(d)
    db = d
    if not button then Create() end
end)
