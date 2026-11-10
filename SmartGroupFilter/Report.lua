-- SmartGroupFilter - bug report window (ruleset plan 2026-11-10-extras, phase 4; the window,
-- the form and the code are SimpleConjureBar's)
-- Addons cannot send data, open a browser or write to the clipboard. The window therefore builds
-- the report from a short form and the game, shows it as one code (ReportCode.lua), selected for
-- Ctrl+C, and links the GitHub form the code is pasted into. What it may hold: Privacy.lua.

local _, ns = ...

local D, L = ns.D, ns.L
local SetL = ns.SetL

local db
ns.OnDBReady(function(d) db = d end)

local MAX_ERRORS = 5       -- newest errors of this addon included in the report
local MAX_STACK_LINES = 12 -- stack lines per error

---------------------------------------------------------------------------
-- State snapshot: what decides a misbehaviour without a Lua error - the build button, the
-- invited players, the own listing, the list's counts - as modes, keys, tokens, IDs and
-- counts. No name: the button's text is left out, it can name the player to invite next.
---------------------------------------------------------------------------
local SV = function(v) return ns.SafeValue(v) end

local function Join(list, sep)
    local out = {}
    for i, v in ipairs(list) do out[i] = SV(v) end
    return table.concat(out, sep or ",")
end

function ns.StateSnapshot()
    local lines = {}
    local build = ns.ReportBuildState()
    lines[#lines + 1] = ("build mode=%s reason=%s enabled=%s declined=%d"):format(SV(build.mode or "none"),
        SV(build.reasonKey or "none"), SV(build.enabled), build.declined)
    for _, p in ipairs(build.invited) do
        lines[#lines + 1] = ("invited %s %s %s joined=%s"):format(SV(p.role), SV(p.class), SV(p.level), SV(p.joined))
    end
    local entry = C_LFGList.GetActiveEntryInfo()
    local ids = entry and type(entry.activityIDs) == "table" and entry.activityIDs or {}
    lines[#lines + 1] = "listing " .. (#ids > 0 and ("activities=" .. Join(ids)) or "none")
    local range = ns.LevelRange()
    lines[#lines + 1] = ("range %s-%s"):format(SV(range.min), SV(range.max))
    local shown, total = ns.Counts()
    local roles = ns.RoleCounts()
    lines[#lines + 1] = ("list shown=%d total=%d tank=%d healer=%d damage=%d filter=%s"):format(shown, total,
        roles.TANK or 0, roles.HEALER or 0, roles.DAMAGER or 0, SV(ns.FilterActive()))
    local panel = ns.panel
    lines[#lines + 1] = panel and ("panel visible=%s view=%s"):format(SV(panel:IsVisible()), SV(panel.view or "none"))
        or "panel none"
    lines[#lines + 1] = ("group %s size=%d"):format(IsInGroup() and "party" or "solo", math.max(1, GetNumGroupMembers()))
    lines[#lines + 1] = "combat " .. (InCombatLockdown() and "yes" or "no")
    return lines
end

---------------------------------------------------------------------------
-- Report content
---------------------------------------------------------------------------
-- This addon's errors of the current session from BugGrabber (the error collector BugSack
-- builds on), newest first. Errors of earlier sessions come from BugGrabber's saved data and
-- stay out; without a session number, an error from before this addon loaded counts as one.
local function CollectErrors()
    local list = {}
    local grabber = BugGrabber
    if not (grabber and grabber.GetDB) then return list, false end
    local ok, errors = pcall(grabber.GetDB, grabber)
    if not ok or type(errors) ~= "table" then return list, true end
    local okSession, session = pcall(function() return grabber.GetSessionId and grabber:GetSessionId() end)
    if not okSession then session = nil end
    for i = #errors, 1, -1 do
        local e = errors[i]
        if type(e) == "table" then
            local current
            if type(session) == "number" and type(e.session) == "number" then
                current = e.session == session
            else
                current = type(e.time) == "number" and e.time >= ns.logStartClock
            end
            local text = tostring(e.message or "") .. "\n" .. tostring(e.stack or "")
            if current and text:find(ns.ADDON_NAME, 1, true) then
                list[#list + 1] = e
                if #list >= MAX_ERRORS then break end
            end
        end
    end
    return list, true
end

-- The first lines of a text, each with the tag of its report field and filtered
local function FirstLines(text, max, tag, names)
    local out, n = {}, 0
    for line in tostring(text or ""):gmatch("[^\n]+") do
        n = n + 1
        if n > max then out[#out + 1] = tag .. " ..." break end
        out[#out + 1] = tag .. " " .. ns.Scrub(line, names)
    end
    return out
end

-- When an error came, relative only - no date or clock in a report - and whether in combat
local function ErrorWhen(e)
    if type(e.time) ~= "number" then return "time unknown", "unknown" end
    local when = ("%d min ago"):format(math.floor((time() - e.time) / 60 + 0.5))
    local since = e.time - ns.logStartClock
    if since >= 0 then when = when .. (", %d s after load"):format(since) end
    return when, ns.CombatAt(e.time)
end

local function OrDash(s) return (s and s ~= "") and s or "-" end

-- The settings the addon knows (D.REPORT_SETTINGS), values by allowlist; a key it does not know
-- is left out (it could hold anything). The rows: their order and exclusions, as class tokens.
local function SettingsText()
    if not db then return "(not loaded)" end
    local parts = {}
    for _, k in ipairs(D.REPORT_SETTINGS) do
        local v = db[k]
        local t = type(v)
        if t == "number" or t == "boolean" or t == "string" then parts[#parts + 1] = k .. "=" .. SV(v) end
    end
    for _, role in ipairs(D.ROLES) do
        local order = type(db.order) == "table" and type(db.order[role]) == "table" and db.order[role] or {}
        parts[#parts + 1] = "order" .. role .. "=" .. Join(order)
        local out = {}
        local excluded = type(db.excluded) == "table" and type(db.excluded[role]) == "table" and db.excluded[role] or {}
        for class in pairs(excluded) do out[#out + 1] = SV(class) end
        table.sort(out)
        parts[#parts + 1] = "excluded" .. role .. "=" .. (#out > 0 and table.concat(out, ",") or "-")
    end
    return table.concat(parts, ", ")
end

-- The level in a band of ten: enough for ranks, too coarse to tell a character apart
local function LevelBand()
    local low = math.floor((tonumber(UnitLevel("player")) or 0) / 10) * 10
    return ("%d-%d"):format(low, low + 9)
end

-- A one-line field: what a pasted line break would split into a second report line
local function OneLine(s)
    return (tostring(s or ""):gsub("[\r\n]+", " "))
end

-- Every line belongs to a field of D.REPORT_FIELDS. form: { description, area (a key of
-- D.REPORT_AREAS), details }. The fields are filtered as SimpleConjureBar's; the whole text
-- then passes the filter once more with every name SGF knows (Privacy.lua, ns.ReportNames).
local function BuildReport(form)
    ns.LogSettings()
    -- A secret name could not be filtered: no report at all, not one without the filter
    local names, all = ns.KnownNames(), ns.ReportNames()
    if not (names and all) then return nil end
    local version, build, _, interface = GetBuildInfo()
    local _, classFile = UnitClass("player")
    local lines = {
        "## SmartGroupFilter bug report",
        "",
        "**Description:** " .. OrDash(ns.Scrub(OneLine(form.description), names)),
        "**Area:** " .. form.area,
        "**Details:** " .. OrDash(ns.Scrub(OneLine(form.details), names)),
        "",
        "- Addon version: " .. ns.VERSION,
        "- Client: " .. tostring(version) .. " (build " .. tostring(build) .. ", interface " .. tostring(interface) .. ")",
        "- Client locale: " .. tostring(GetLocale()) .. ", addon language: "
            .. SV((SmartGroupFilterGlobalDB and SmartGroupFilterGlobalDB.language) or "auto"),
        "- Character: " .. tostring(classFile) .. ", level " .. LevelBand() .. (IsInGroup() and ", party" or ", solo"),
        "- Settings: " .. SettingsText(),
        "",
    }
    local errors, hasGrabber = CollectErrors()
    if not hasGrabber then
        lines[#lines + 1] = "**Lua errors:** BugGrabber/BugSack not installed"
    elseif #errors == 0 then
        lines[#lines + 1] = "**Lua errors:** none from SmartGroupFilter in this session"
    else
        lines[#lines + 1] = "**Lua errors (newest first):**"
        for i, e in ipairs(errors) do
            local when, combat = ErrorWhen(e)
            lines[#lines + 1] = ""
            lines[#lines + 1] = ("Error %d (x%s, %s, combat: %s):"):format(i, type(e.counter) == "number" and e.counter or 1, when, combat)
            lines[#lines + 1] = "```"
            for _, l in ipairs(FirstLines(e.message, 6, "msg", names)) do lines[#lines + 1] = l end
            for _, l in ipairs(FirstLines(e.stack, MAX_STACK_LINES, "at", names)) do lines[#lines + 1] = l end
            for _, l in ipairs(ns.SafeLocals(e.locals, names)) do lines[#lines + 1] = "local " .. l end
            lines[#lines + 1] = "```"
        end
    end
    local function Block(title, tag, list)
        lines[#lines + 1] = ""
        lines[#lines + 1] = title
        lines[#lines + 1] = "```"
        for _, l in ipairs(list) do lines[#lines + 1] = tag .. " " .. l end
        lines[#lines + 1] = "```"
    end
    Block("**Last actions (seconds since load):**", "log", ns.LogLines())
    Block("**State:**", "state", ns.StateSnapshot())
    return ns.CapReport(ns.Scrub(table.concat(lines, "\n"), all))
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame
local MAX_TEXT = 500 -- letters of the description and of the details
local reopen = false -- combat closed the window: it comes back after

-- The box shows the code, selected for Ctrl+C, or - "Show content" - the readable report,
-- never selected, so what gets copied is the code
local function Shown() return frame.showContent and frame.reportText or frame.codeText end

local function MarkSelection()
    if frame.showContent then frame.report:HighlightText(0, 0) else frame.report:HighlightText() end
end

local function SelectReport()
    frame.report:SetFocus()
    MarkSelection()
end

local function FormValues()
    return { description = frame.desc:GetText(), area = frame.area, details = frame.details:GetText() }
end

local function ShowBox()
    frame.report:SetText(Shown())
    frame.report:SetCursorPosition(0)
    MarkSelection()
    SetL(frame.toggle, frame.showContent and "REPORT_SHOW_CODE" or "REPORT_SHOW_CONTENT")
end

-- Each keystroke rebuilds the report; while a name is secret the last clean one stays, and the
-- line above the code box says why until the next clean report (no chat)
local function Refresh()
    local text = BuildReport(FormValues())
    if not text then
        SetL(frame.step2, "REPORT_SECRET")
        return
    end
    SetL(frame.step2, "REPORT_STEP2")
    frame.reportText = text
    frame.codeText = ns.ReportCode.Encode(text)
    ShowBox()
end

-- A one-line text field: typing rebuilds the report, Enter selects it for copying
local function AddInput(anchor, width)
    local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 6, -4)
    box:SetSize(width, 22)
    box:SetAutoFocus(false)
    box:SetMaxLetters(MAX_TEXT)
    box:SetScript("OnTextChanged", function(_, userInput) if userInput then Refresh() end end)
    box:SetScript("OnEnterPressed", SelectReport)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- Shows the window with a fresh report. Built out of combat only, where names are readable;
-- a secret name keeps it shut and the settings say why under the button (the chat when they
-- are not shown).
local function Open()
    if InCombatLockdown() then return end
    if not ns.ReportNames() then
        frame:Hide()
        if not ns.ShowReportSecretHint() then ns.Print(L.REPORT_SECRET) end
        return
    end
    frame:Show()
    Refresh()
    SelectReport()
end

local function CreateWindow()
    local W, H, PAD = 520, 580, 22
    frame = CreateFrame("Frame", "SmartGroupFilterReport", UIParent, "BackdropTemplate")
    frame:SetSize(W, H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not self.docked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    table.insert(UISpecialFrames, "SmartGroupFilterReport") -- closes with Escape

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    SetL(title, "REPORT_TITLE")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- What the report holds and never holds, and that an issue is public
    local privacy = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    privacy:SetPoint("TOPLEFT", PAD, -44)
    privacy:SetWidth(W - 2 * PAD)
    privacy:SetJustifyH("LEFT")
    SetL(privacy, "REPORT_PRIVACY")
    local public = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    public:SetPoint("TOPLEFT", privacy, "BOTTOMLEFT", 0, -4)
    public:SetWidth(W - 2 * PAD)
    public:SetJustifyH("LEFT")
    SetL(public, "REPORT_PUBLIC")

    -- Step 1: what happened, where (a list, so the developer knows where to look), details
    local step1 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    step1:SetPoint("TOPLEFT", public, "BOTTOMLEFT", 0, -10)
    SetL(step1, "REPORT_STEP1")
    frame.desc = AddInput(step1, W - 2 * PAD - 6)

    local where = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    where:SetPoint("TOPLEFT", frame.desc, "BOTTOMLEFT", -6, -14)
    SetL(where, "REPORT_WHERE")
    frame.area = "OTHER"
    local menu = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    menu:SetPoint("LEFT", where, "RIGHT", 12, 0)
    menu:SetWidth(240)
    menu:SetupMenu(function(_, root)
        for _, key in ipairs(D.REPORT_AREAS) do
            root:CreateRadio(L["AREA_" .. key], function() return frame.area == key end,
                function() frame.SetArea(key) end)
        end
    end)
    frame.areaMenu = menu
    function frame.SetArea(key)
        frame.area = key
        menu:GenerateMenu()
        Refresh()
    end
    -- The dropdown shows its selection's text as of its last generation: a language switch
    -- would keep the old language's word
    ns.OnLanguageChanged(function() menu:GenerateMenu() end)

    local detailsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detailsLabel:SetPoint("TOPLEFT", where, "BOTTOMLEFT", 0, -16)
    SetL(detailsLabel, "REPORT_DETAILS")
    frame.details = AddInput(detailsLabel, W - 2 * PAD - 6)

    -- Step 2: the report, selected for Ctrl+C (read-only)
    local step2 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    step2:SetPoint("TOPLEFT", frame.details, "BOTTOMLEFT", -6, -12)
    SetL(step2, "REPORT_STEP2")
    frame.step2 = step2

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", step2, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, 92)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", scroll, -4, 4)
    bg:SetPoint("BOTTOMRIGHT", scroll, 24, -4)
    bg:SetColorTexture(0, 0, 0, 0.5)

    local report = CreateFrame("EditBox", nil, scroll)
    report:SetMultiLine(true)
    report:SetAutoFocus(false)
    report:SetFontObject("ChatFontNormal")
    report:SetWidth(W - 2 * PAD - 30)
    report:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    report:SetScript("OnEditFocusGained", MarkSelection)
    -- Read-only: user edits are undone right away, back to what the box shows
    report:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(Shown() or "")
            MarkSelection()
        end
    end)
    scroll:SetScrollChild(report)
    frame.report = report

    -- Step 3: where to paste it
    local step3 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    step3:SetPoint("BOTTOMLEFT", PAD, 66)
    step3:SetPoint("RIGHT", -PAD, 0)
    step3:SetJustifyH("LEFT")
    local url = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    url:SetPoint("BOTTOMLEFT", PAD + 6, 40)
    url:SetSize(W - 2 * PAD - 6, 22)
    url:SetAutoFocus(false)
    url:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    url:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(D.BUG_REPORT_URL) self:HighlightText() end
    end)
    url:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if D.BUG_REPORT_URL ~= "" then
        SetL(step3, "REPORT_STEP3")
        url:SetText(D.BUG_REPORT_URL)
    else
        SetL(step3, "REPORT_NO_URL")
        url:Hide()
    end
    frame.url = url

    local done = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    done:SetSize(120, 22)
    done:SetPoint("BOTTOMRIGHT", -PAD, 16)
    SetL(done, "CLOSE")
    done:SetScript("OnClick", function() frame:Hide() end)

    local toggle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    toggle:SetSize(160, 22)
    toggle:SetPoint("BOTTOMLEFT", PAD, 16)
    toggle:SetScript("OnClick", function()
        frame.showContent = not frame.showContent
        ShowBox()
    end)
    frame.toggle = toggle

    -- Combat closes the window and it comes back after, the text kept
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if frame:IsShown() then reopen = true; frame:Hide() end
        elseif reopen then
            reopen = false
            C_Timer.After(0, Open)
        end
    end)
    function frame.BuildText() return BuildReport(FormValues()) end
    frame:Hide()
end

-- Docked right of the panel, as tall as it and not movable (the settings' button), or its own
-- window in the middle of the screen (/sgf bug) - Michel, 2026-11-11
local FREE_HEIGHT = 580
local function Place(docked)
    local panel = ns.panel
    frame:ClearAllPoints()
    if docked and panel and panel:IsVisible() then
        frame.docked = true
        frame:SetPoint("TOPLEFT", panel, "TOPRIGHT", 4, 0)
        frame:SetHeight(panel:GetHeight())
        if not frame.followsPanel then
            frame.followsPanel = true
            panel:HookScript("OnHide", function() if frame.docked then frame:Hide() end end)
        end
    else
        frame.docked = false
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame:SetHeight(FREE_HEIGHT)
    end
end

-- /sgf bug and the settings' button (docked). In combat nothing opens, and only /sgf bug says
-- why.
function ns.OpenBugReport(docked)
    if not frame then CreateWindow() end
    if InCombatLockdown() then
        if ns.fromCommand then ns.Print(L.REPORT_COMBAT) end
        return
    end
    Place(docked)
    reopen = false
    frame.desc:SetText("")
    frame.details:SetText("")
    frame.area = "OTHER"
    frame.areaMenu:GenerateMenu()
    frame.showContent = false
    Open()
end
