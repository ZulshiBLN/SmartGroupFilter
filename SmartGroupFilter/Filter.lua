-- SmartGroupFilter - filter
-- Shortens Blizzard's Group Finder list. Blizzard's LFGBrowseFrame:UpdateResultList() fetches
-- the results, sorts them with the global LFGBrowseUtil_SortSearchResults(self.results) and
-- then draws exactly that table (Blizzard_LFGVanilla_Browse.lua, Forever 1.60.1). The filter
-- posthooks the sort and removes, in place, the entries ns.Passes rejects - Blizzard's code is
-- hooked, never replaced (ruleset K6). Filter off: the table stays untouched.

local _, ns = ...

local db
ns.OnDBReady(function(d) db = d end)

-- A secret value is unreadable: it counts as missing (ruleset code.md, "Secret values")
local function Clean(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- One search result as the plain entry Logic.lua reads, or nil when the client has none
function ns.ReadEntry(id)
    local info = C_LFGList.GetSearchResultInfo(id)
    if not info then return nil end
    local entry = {
        id = id, numMembers = info.numMembers, hasSelf = info.hasSelf,
        isDelisted = info.isDelisted, age = Clean(info.age),
    }
    if entry.numMembers == 1 then
        local p = C_LFGList.GetSearchResultPlayerInfo(id, 1)
        if p then
            entry.name = Clean(p.name)
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
    if entry and type(entry.activityIDs) == "table" and #entry.activityIDs > 0 then
        return entry.activityIDs
    end
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

---------------------------------------------------------------------------
-- The hook
---------------------------------------------------------------------------
local shownCount, totalCount = 0, 0
local listeners = {}

-- fn(shown, total) runs after every filtering: single players kept and all single players
function ns.OnListFiltered(fn)
    listeners[#listeners + 1] = fn
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

-- The filter works while it is on and the panel is shown; else Blizzard's list stays as it is
function ns.FilterActive()
    return db and db.filterOn and db.panelShown or false
end

local function Filter(results)
    if type(results) ~= "table" or not db then return end
    local active = ns.FilterActive()
    local range, ownArmor = ns.LevelRange(), ns.OwnArmor()
    local shown, total = 0, 0
    for i = #results, 1, -1 do
        local entry = ns.ReadEntry(results[i])
        local single = IsSingle(entry)
        if single then total = total + 1 end
        if active and entry and not ns.Passes(entry, db, range, ownArmor) then
            table.remove(results, i)
        elseif single then
            shown = shown + 1
        end
    end
    shownCount, totalCount = shown, total
    for _, fn in ipairs(listeners) do fn(shown, total) end
end

-- Rebuilds Blizzard's list from the results the client already has - no new search
function ns.RefreshList()
    if LFGBrowseFrame and LFGBrowseFrame:IsShown() then LFGBrowseFrame:UpdateResultList() end
end

-- A setting in the panel changed: the filter is on again (after Reset Filter) and filters anew
function ns.FilterChanged()
    db.filterOn = true
    ns.RefreshList()
end

-- Reset Filter: Blizzard's own list again - no exclusion, every level, same armor allowed,
-- the filter off until the next change. The rows' order is kept (Michel, 2026-11-10).
function ns.ResetFilter()
    for _, role in ipairs(ns.D.ROLES) do db.excluded[role] = {} end
    db.allowSameArmor = true
    db.filterOn = false
    ns.SetLevelRange(1, GetMaxPlayerLevel and GetMaxPlayerLevel() or 60)
    ns.RefreshList()
end

---------------------------------------------------------------------------
-- Late data: the client may hand a single player's class and level over only after the list
-- was drawn, then sends LFG_LIST_SEARCH_RESULT_UPDATED. Is the entry now on the wrong side of
-- the filter, the list is filtered again - once, shortly after, however many updates arrive.
---------------------------------------------------------------------------
local REFILTER_DELAY = 0.3
local refilterPending = false

local function InList(id)
    for _, v in ipairs(LFGBrowseFrame.results or {}) do
        if v == id then return true end
    end
    return false
end

local function OnResultUpdated(id)
    if refilterPending or not ns.FilterActive() or not LFGBrowseFrame then return end
    local entry = ns.ReadEntry(id)
    if not IsSingle(entry) then return end
    local passes = ns.Passes(entry, db, ns.LevelRange(), ns.OwnArmor())
    if passes == InList(id) then return end
    refilterPending = true
    C_Timer.After(REFILTER_DELAY, function()
        refilterPending = false
        ns.RefreshList()
    end)
end

-- Blizzard's Group Finder loads on demand, after this addon; hook it once it is there
local hooked = false
local function Hook()
    if hooked or not LFGBrowseUtil_SortSearchResults then return end
    hooksecurefunc("LFGBrowseUtil_SortSearchResults", Filter)
    hooked = true
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
events:SetScript("OnEvent", function(_, event, id)
    if event == "LFG_LIST_SEARCH_RESULT_UPDATED" then OnResultUpdated(id) else Hook() end
end)
