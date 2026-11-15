-- SmartGroupFilter - filter
-- Reads the Group Finder's results and counts the single players the filter lets through - for
-- the panel's numbers and Build Group. Blizzard's own list is never touched: calling its build
-- from addon code made its rows SGF's, and its later protected search and secret reads failed
-- (ruleset plan 2026-11-13-list-untouched).

local _, ns = ...

local db
ns.OnDBReady(function(d) db = d end)

local IsSecret, Clean = ns.IsSecret, ns.Clean

-- Every readable name a search result showed this session: the bug report filters them out
-- (Privacy.lua), never prints them
local seenNames = {}

local function See(name)
    name = Clean(name)
    if type(name) == "string" then seenNames[name] = true end
end

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
-- (a BugSack of 2026-11-11)
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
    See(info.leaderName) -- the name Blizzard's row shows, a group's too
    if entry.numMembers == 1 then
        local p = Clean(C_LFGList.GetSearchResultPlayerInfo(id, 1))
        if p then
            entry.name = Clean(p.name)
            See(entry.name)
            entry.class = Clean(p.classFilename)
            entry.level = Clean(p.level)
            local r = Clean(p.lfgRoles)
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
local last   -- { key, min, max }: the range last known, kept while the activities are unknown

function ns.MaxLevel()
    return GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
end

-- The activities the list is for: the own listing's, else those chosen in Blizzard's dropdown;
-- nil while the own listing's are secret (in an instance) - unknown, not "none"
local function Activities()
    local entry = C_LFGList.GetActiveEntryInfo()
    local own = entry and entry.activityIDs
    if IsSecret(own) then return nil end
    if type(own) == "table" and #own > 0 then return ns.ReadActivities(own) end
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

-- The range for these activities, from their suggestions
local function Suggested(ids)
    local top = ns.MaxLevel()
    if #ids == 0 then return 1, top end
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
    return low, high
end

function ns.LevelRange()
    local ids = Activities()
    if ids then
        local key = ActivityKey(ids)
        if manual and manual.key ~= key then manual = nil end
        if manual then
            last = manual
        else
            local low, high = Suggested(ids)
            last = { key = key, min = low, max = high }
        end
    end
    local r = manual or last
    if not r then return { min = 1, max = ns.MaxLevel() } end
    return { min = r.min, max = r.max }
end

-- A range set by hand holds until the activities change; set while they are unknown, it is for
-- the ones last known
function ns.SetLevelRange(from, to)
    if from > to then from, to = to, from end
    local ids = Activities()
    local key = ids and ActivityKey(ids) or (last and last.key)
    manual = { key = key, min = from, max = to }
    last = manual
end

-- Forgets the range set by hand: the dungeon's range again
function ns.ClearLevelRange()
    if last == manual then last = nil end
    manual = nil
end

---------------------------------------------------------------------------
-- The count
---------------------------------------------------------------------------
local shownCount, totalCount = 0, 0
local roleCounts = { TANK = 0, HEALER = 0, DAMAGER = 0 }
local rolePlayers = { TANK = {}, HEALER = {}, DAMAGER = {} }
local listeners = {}

-- fn(fit, total) runs after every count: single players that fit and all single players
function ns.OnCounted(fn)
    listeners[#listeners + 1] = fn
end

-- Single players that fit, by the roles they signed up for (one with several counts for each;
-- one with none for none) - shown beside the rows' headers (2026-11-11)
function ns.RoleCounts()
    return roleCounts
end

function ns.Counts()
    return shownCount, totalCount
end

-- The entries behind a role's count, for its tooltip
function ns.RolePlayers(role)
    return rolePlayers[role] or {}
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

-- A group's members, as Blizzard's tooltip names them: read on a count, not by Build Group's plan
-- each second
local function SeeMembers(entry)
    local n = entry and entry.numMembers
    if type(n) ~= "number" or n < 2 or n > ns.D.TIP_MEMBERS_MAX then return end
    for i = 1, n do
        local p = Clean(C_LFGList.GetSearchResultPlayerInfo(entry.id, i))
        if p then See(p.name) end
    end
end

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
        SeeMembers(entry)
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
    local players = { TANK = {}, HEALER = {}, DAMAGER = {} }
    for i = 1, #ids do
        local entry = entries[i]
        if IsSingle(entry) then
            total = total + 1
            if ns.Passes(entry, db, range, ownArmor) then
                shown = shown + 1
                for role, field in pairs(ns.D.ROLE_FIELD) do
                    if entry.roles and entry.roles[field] then
                        counts[role] = counts[role] + 1
                        players[role][#players[role] + 1] = entry
                    end
                end
            end
        end
    end
    return shown, total, counts, players
end

-- Counts anew and tells the listeners; secret results keep the counts as they were
function ns.Recount()
    if not db then return end
    local shown, total, counts, players = Count()
    if shown then shownCount, totalCount, roleCounts, rolePlayers = shown, total, counts, players end
    for _, fn in ipairs(listeners) do fn(shownCount, totalCount) end
end

-- A setting in the panel changed: count anew
function ns.FilterChanged()
    ns.LogSettings()
    ns.Recount()
end

-- Reset Filter: no exclusion, same armor allowed, the dungeon's level range
-- (2026-11-13). The rows' order is kept (2026-11-10).
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
local recountPending = false

local function OnResultUpdated()
    if recountPending then return end
    recountPending = true
    C_Timer.After(ns.D.RECOUNT_DELAY, function()
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
