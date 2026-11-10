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

local function NewFrame()
    local f = { events = {}, scripts = {} }
    function f:RegisterEvent(event) self.events[event] = true end
    function f:UnregisterEvent(event) self.events[event] = nil end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:GetScript(name) return self.scripts[name] end
    return f
end

function CreateFrame()
    local f = NewFrame()
    frames[#frames + 1] = f
    return f
end

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

LFGBrowseFrame = {
    results = {},
    shown = true,
    ActivityDropdown = { selectedValues = {} },
}
function LFGBrowseFrame:IsShown() return self.shown end
-- As Blizzard's: fresh results from the client, sorted, then drawn
function LFGBrowseFrame:UpdateResultList()
    local results = {}
    for i, id in ipairs(STATE.order) do results[i] = id end
    self.totalResults, self.results = #results, results
    LFGBrowseUtil_SortSearchResults(self.results)
end
