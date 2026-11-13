-- SmartGroupFilter - filter
-- Reads the Group Finder's results and counts the single players the filter lets through - for
-- the panel's numbers and Build Group. Blizzard's own list is never touched: calling its build
-- from addon code made its rows SGF's, and its later protected search and secret reads failed
-- (ruleset plan 2026-11-13-list-untouched).

local _, ns = ...

local db
ns.OnDBReady(function(d)
    db = d
    db.filterOn = nil -- saved by earlier builds; Reset Filter's "off" is no longer kept
end)

-- A secret value is unreadable: it counts as missing (ruleset code.md, "Secret values")
local function IsSecret(v)
    return v ~= nil and issecretvalue ~= nil and issecretvalue(v) == true
end

local function Clean(v)
    if IsSecret(v) then return nil end
    return v
end

-- Every readable name a search result showed this session: the bug report filters them out
-- (Privacy.lua), never prints them
local seenNames = {}

function ns.SeenNames()
    return seenNames
end

-- The dungeons a result is listed for, or nil while any of them is missing or secret
function ns.ReadActivities(ids)
    ids = Clean(ids) -- in an instance the whole list is secret: measuring it errors
    if type(ids) ~= "table" or #ids == 0 then return nil end
    local list = {}
    for i, v in ipairs(ids) do
        v = Clean(v)
        if type(v) ~= "number" then return nil end
        list[i] = v
    end
    return list
end

-- One search result as the plain entry Logic.lua reads, or nil when the client has none;
-- nil, "secret" while the client hides the result: in an instance every field is a secret
-- (Michel's BugSack, 2026-11-11)
function ns.ReadEntry(id)
    local info = C_LFGList.GetSearchResultInfo(id)
    if not info then return nil end
    if IsSecret(info) or IsSecret(info.numMembers) or IsSecret(info.hasSelf) or IsSecret(info.isDelisted) then
        return nil, "secret"
    end
    local entry = {
        id = id, numMembers = info.numMembers, hasSelf = info.hasSelf,
        isDelisted = info.isDelisted, age = Clean(info.age),
        activities = ns.ReadActivities(info.activityIDs),
    }
    if entry.numMembers == 1 then
        local p = C_LFGList.GetSearchResultPlayerInfo(id, 1)
        if p then
            entry.name = Clean(p.name)
            if type(entry.name) == "string" then seenNames[entry.name] = true end
            entry.class = Clean(p.classFilename)
            entry.level = Clean(p.level)
            local r = p.lfgRoles
            if type(r) == "table" then
                entry.roles = { tank = Clean(r.tank), healer = Clean(r.healer), dps = Clean(r.dps) }
            end
        end
    end
    return entry
end

---------------------------------------------------------------------------
-- Level range: the dungeon's suggestion, or what the player set by hand for it
---------------------------------------------------------------------------
local manual -- { key, min, max } while a hand-set range applies

local function MaxLevel()
    return GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
end

-- The activities the list is for: the own listing's, else those chosen in Blizzard's dropdown
local function Activities()
    local entry = C_LFGList.GetActiveEntryInfo()
    local own = entry and ns.ReadActivities(entry.activityIDs)
    if own then return own end
    local dropdown = LFGBrowseFrame and LFGBrowseFrame.ActivityDropdown
    local selected = dropdown and dropdown.selectedValues
    if type(selected) == "table" then return selected end
    return {}
end

local function ActivityKey(ids)
    local copy = {}
    for i, id in ipairs(ids) do copy[i] = tostring(id) end
    table.sort(copy)
    return table.concat(copy, ",")
end

function ns.LevelRange()
    local ids = Activities()
    local key = ActivityKey(ids)
    if manual and manual.key == key then return { min = manual.min, max = manual.max } end
    manual = nil
    local top = MaxLevel()
    if #ids == 0 then return { min = 1, max = top } end
    local low, high
    for _, id in ipairs(ids) do
        local a = C_LFGList.GetActivityInfoTable(id)
        local lo = a and a.minLevelSuggestion or 0
        local hi = a and a.maxLevelSuggestion or 0
        if lo <= 0 then lo = 1 end
        if hi <= 0 then hi = top end
        low = low and math.min(low, lo) or lo
        high = high and math.max(high, hi) or hi
    end
    return { min = low, max = high }
end

-- A range set by hand holds until the activities change
function ns.SetLevelRange(from, to)
    if from > to then from, to = to, from end
    manual = { key = ActivityKey(Activities()), min = from, max = to }
end

-- Forgets the range set by hand: the dungeon's range again
function ns.ClearLevelRange()
    manual = nil
end

---------------------------------------------------------------------------
-- The count
---------------------------------------------------------------------------
local shownCount, totalCount = 0, 0
local roleCounts = { TANK = 0, HEALER = 0, DAMAGER = 0 }
local listeners = {}

-- fn(fit, total) runs after every count: single players that fit and all single players
function ns.OnListFiltered(fn)
    listeners[#listeners + 1] = fn
end

-- Single players that fit, by the roles they signed up for (one with several counts for each;
-- one with none for none) - shown beside the rows' headers (Michel, 2026-11-11)
function ns.RoleCounts()
    return roleCounts
end

function ns.Counts()
    return shownCount, totalCount
end

local function IsSingle(entry)
    return entry and entry.numMembers == 1 and not entry.hasSelf
end

-- The player's own armor class, for "Allow same armor class"
function ns.OwnArmor()
    local _, class = UnitClass("player")
    return ns.ArmorOf(class, UnitLevel("player"))
end

local listSecret = false -- logged once per change, not at every update in an instance

-- The client's results read anew, or nil while they are secret (in an instance)
local function Count()
    local _, ids = C_LFGList.GetFilteredSearchResults()
    local secret = IsSecret(ids)
    if secret or type(ids) ~= "table" then ids = {} end
    local entries = {}
    for i, id in ipairs(ids) do
        local entry, why = ns.ReadEntry(id)
        if why == "secret" then secret = true break end
        entries[i] = entry
    end
    if secret then
        if not listSecret then ns.Log("list secret: counts kept") end
        listSecret = true
        return nil
    end
    listSecret = false
    local range, ownArmor = ns.LevelRange(), ns.OwnArmor()
    local shown, total = 0, 0
    local counts = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for i = 1, #ids do
        local entry = entries[i]
        if IsSingle(entry) then
            total = total + 1
            if ns.Passes(entry, db, range, ownArmor) then
                shown = shown + 1
                for role, field in pairs(ns.D.ROLE_FIELD) do
                    if entry.roles and entry.roles[field] then counts[role] = counts[role] + 1 end
                end
            end
        end
    end
    return shown, total, counts
end

-- Counts anew and tells the listeners; secret results keep the counts as they were
function ns.Recount()
    if not db then return end
    local shown, total, counts = Count()
    if shown then shownCount, totalCount, roleCounts = shown, total, counts end
    for _, fn in ipairs(listeners) do fn(shownCount, totalCount) end
end

-- A setting in the panel changed: count anew
function ns.FilterChanged()
    ns.LogSettings()
    ns.Recount()
end

-- Reset Filter: no exclusion, same armor allowed, the dungeon's level range (Michel,
-- 2026-11-13). The rows' order is kept (Michel, 2026-11-10).
function ns.ResetFilter()
    for _, role in ipairs(ns.D.ROLES) do db.excluded[role] = {} end
    db.allowSameArmor = true
    ns.Log("reset filter")
    ns.LogSettings()
    ns.ClearLevelRange()
    ns.Recount()
end

---------------------------------------------------------------------------
-- Late data: the client may hand a single player's class and level over only after the results
-- arrived, then sends LFG_LIST_SEARCH_RESULT_UPDATED - counted once, shortly after, however
-- many updates arrive.
---------------------------------------------------------------------------
local RECOUNT_DELAY = 0.3
local recountPending = false

local function OnResultUpdated()
    if recountPending then return end
    recountPending = true
    C_Timer.After(RECOUNT_DELAY, function()
        recountPending = false
        ns.Recount()
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
events:RegisterEvent("LFG_LIST_SEARCH_FAILED")
events:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
events:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
events:SetScript("OnEvent", function(_, event)
    if event == "LFG_LIST_SEARCH_RESULT_UPDATED" then OnResultUpdated() else ns.Recount() end
end)
