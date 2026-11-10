-- SmartGroupFilter - action log for the bug report (mechanics from SimpleConjureBar)
-- The last actions and events, in memory only, so a report shows what happened before a bug
-- without asking the player. Entries hold modes, keys, tokens and counts, never names. A write
-- never raises an error: logging must not break a click.

local _, ns = ...

local D = ns.D
local MAX_ENTRIES = 50
local entries, first = {}, 1 -- a ring: entries[first] is the oldest
-- The clock starts when the addon loads - after a /reload too, not only at login
local loadAt, loadClock = GetTime(), time()
ns.logStartClock = loadClock -- the report's fallback to tell this session's errors apart
local combats = {} -- { start = clock, stop = clock or nil }, kept apart from the ring

-- How an entry reads in the report: seconds since load, then the text. A field of ns, so a
-- spec can make it fail.
function ns.LogFormat(e)
    return ("+%.1fs %s"):format(e.since, e.text)
end

function ns.Log(text)
    pcall(function()
        local e = { since = GetTime() - loadAt, clock = time(), text = text }
        if #entries < MAX_ENTRIES then
            entries[#entries + 1] = e
        else
            entries[first] = e
            first = first % MAX_ENTRIES + 1
        end
    end)
end

-- The entries, oldest first, as the report prints them
function ns.LogLines()
    local lines = {}
    for i = 0, #entries - 1 do
        local e = entries[(first - 1 + i) % #entries + 1]
        local ok, line = pcall(ns.LogFormat, e)
        lines[#lines + 1] = ok and line or "?"
    end
    return lines
end

-- Whether a moment (time() scale, as BugGrabber stores an error's time) fell in combat:
-- "unknown" before the log began - BugGrabber offers no callback to ask at the moment itself
function ns.CombatAt(clock)
    if clock < loadClock then return "unknown" end
    for _, c in ipairs(combats) do
        if clock >= c.start and (not c.stop or clock <= c.stop) then return "yes" end
    end
    return "no"
end

---------------------------------------------------------------------------
-- Settings: the plain values that changed since the last look - after a change in the panel,
-- after a chat command and when a report is built
---------------------------------------------------------------------------
local db, seen = nil, {}
local function Plain(v) local t = type(v) return t == "number" or t == "boolean" or t == "string" end
ns.OnDBReady(function(d)
    db = d
    for k, v in pairs(d) do if Plain(v) then seen[k] = v end end
end)

-- The keys a report names (D.REPORT_SETTINGS); a key the addon does not know is not named: it
-- could be anything
local known = {}
for _, k in ipairs(D.REPORT_SETTINGS) do known[k] = true end

function ns.LogSettings()
    if not db then return end
    local changed = {}
    for k, v in pairs(db) do
        if Plain(v) and seen[k] ~= v then changed[#changed + 1] = k end
    end
    table.sort(changed)
    for _, k in ipairs(changed) do
        seen[k] = db[k]
        if known[k] then ns.Log("setting " .. k .. "=" .. ns.SafeValue(db[k])) end
    end
end

---------------------------------------------------------------------------
-- Events: combat, group size
---------------------------------------------------------------------------
local lastGroup
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        combats[#combats + 1] = { start = time() }
        if #combats > MAX_ENTRIES then table.remove(combats, 1) end
        ns.Log("combat start")
    elseif event == "PLAYER_REGEN_ENABLED" then
        local c = combats[#combats]
        if c and not c.stop then c.stop = time() end
        ns.Log("combat end")
    else
        local group = (IsInGroup() and "party" or "solo") .. " size=" .. math.max(1, GetNumGroupMembers())
        if group ~= lastGroup then
            lastGroup = group
            ns.Log("group " .. group)
        end
    end
end)
