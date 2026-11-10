-- SmartGroupFilter - development test
-- /sgf test: what the next click of Build Group would do and why - the target dungeon, the
-- invites and their whispers - sending nothing (Michel, 2026-11-10). Development only: the TOC
-- loads this file between #@do-not-package@ markers and .pkgmeta leaves it out, so a release
-- has no /sgf test (Michel, 2026-11-11). Technical output, English on purpose (ruleset
-- localization.md).

local _, ns = ...
local D, L = ns.D, ns.L

local db
ns.OnDBReady(function(d) db = d end)

local B = ns.BuildDev
local placed, declined = B.placed, B.declined

local function RolesText(roles)
    local out = {}
    for _, role in ipairs(D.ROLES) do
        if roles and roles[D.ROLE_FIELD[role]] then out[#out + 1] = role:lower() end
    end
    return #out > 0 and table.concat(out, "+") or "no role"
end

-- The roles, and the dungeons when more than one: a single role then gets the dungeon whisper
local function SignUp(e)
    local text = RolesText(e and e.roles)
    local n = e and e.activities and #e.activities or 0
    return n > 1 and ("%s, %d dungeons"):format(text, n) or text
end

local function RowPlace(role, class)
    for i, c in ipairs(db.order[role]) do
        if c == class then return i end
    end
end

-- Why a single player of the list is not chosen, checked in the order Logic.lua checks
local function WhyNot(e, state, chosenNames, ownArmor, after)
    if e.isDelisted then return "delisted" end
    if not e.name then return "name not readable" end
    if not (e.class and e.level and e.level >= 1) then return "class or level not loaded yet" end
    if declined[e.name] then return "declined or let an invite run out" end
    if placed[e.name] then return "already invited" end
    for _, m in ipairs(state.members) do
        if m.name == e.name then return "in your group" end
    end
    if not e.activities then return "dungeon not loaded yet" end
    if not ns.ListedFor(e, state.dungeons) then
        return ns.ListedFor(e, state.ownDungeons) and "listed for your other dungeon, not the target"
            or "not listed for your dungeon"
    end
    local r = state.range
    if e.level < r.min or e.level > r.max then
        return ("level %d outside %d-%d"):format(e.level, r.min, r.max)
    end
    local fits = {}
    local signed = RolesText(e.roles) ~= "no role"
    for _, role in ipairs(D.ROLES) do
        if D.ROLE_CLASSES[role][e.class] and not db.excluded[role][e.class]
            and (not signed or e.roles[D.ROLE_FIELD[role]]) then
            fits[#fits + 1] = role
        end
    end
    if #fits == 0 then return "no row takes this class for its role" end
    if not db.allowSameArmor and ns.ArmorOf(e.class, e.level) == ownArmor then
        return "same armor class as you"
    end
    if chosenNames[e.name] then return nil end
    if not after then return "nothing is chosen" end
    local count = after.classCount[e.class] or 0
    if count >= D.MAX_SAME_CLASS[db.allowDouble and true or false] then
        return ("class limit: %d %s already counted (you, your group and those chosen)"):format(count, e.class)
    end
    local open = false
    for _, role in ipairs(fits) do
        if after.open[role] > 0 then open = true end
    end
    if not open then
        local names = {}
        for i, role in ipairs(fits) do names[i] = role:lower() end
        return table.concat(names, "/") .. " places already filled"
    end
    if after.free <= 0 then return "no free place left in the group" end
    return "not chosen - please report this line"
end

-- The state after the choice: places still open, free places, players per class
local function After(state, info, list)
    local after = { open = {}, free = info.free - #list, classCount = {} }
    for role, n in pairs(info.open) do after.open[role] = n end
    local count = after.classCount
    local function Add(class) if class then count[class] = (count[class] or 0) + 1 end end
    Add(state.own.class)
    local inGroup = {}
    for _, m in ipairs(state.members) do
        inGroup[m.name] = true
        Add(m.class)
    end
    for name, p in pairs(placed) do
        if not p.joined and not inGroup[name] then Add(p.class) end
    end
    for _, c in ipairs(list) do
        after.open[c.role] = after.open[c.role] - 1
        Add(c.class)
    end
    return after
end

function ns.DryRun()
    local list, why, state, info = B.Plan()
    ns.Print("Build Group test - nothing is sent.")
    local asked, roles = B.Roles()
    local function MemberRoles()
        for _, m in ipairs(state.members) do
            if asked and asked[m.name] then
                print(("  %s: %s"):format(m.name, roles[m.name] and roles[m.name]:lower() or "no answer"))
            end
        end
    end
    if why == "ROLES_WAITING" then
        print("  Would do nothing: " .. ns.BuildReason(why, state))
        MemberRoles()
        return
    end
    if not state then
        print("  Would do nothing: " .. L[why])
        return
    end
    local age = B.ListAge()
    print(age and ("  List from %ds ago%s."):format(math.floor(age), B.ListFresh() and "" or " - older than "
        .. D.LIST_FRESH_SECONDS .. "s, the button refreshes it first") or "  No search results yet.")
    if state.target then
        print(("  Target dungeon: %s - %s."):format(ns.DungeonName(state.target),
            state.kept and "kept for your group" or "a click would choose it"))
    end
    MemberRoles()
    local own, r = state.own, state.range
    print(("  You: %s %s, listed as %s."):format(tostring(own.class), tostring(own.level), RolesText(own.roles)))
    print(("  Level range %d-%d; double classes %s; same armor class %s."):format(r.min, r.max,
        db.allowDouble and "allowed" or "not allowed", db.allowSameArmor and "allowed" or "not allowed"))
    local now = GetTime()
    for name, p in pairs(placed) do
        print(("  Invited by SGF: %s, %s - %s."):format(name, p.role:lower(), p.joined and "in the group"
            or ("waiting, %ds left"):format(math.max(0, math.floor(p["until"] - now)))))
    end
    if info then
        print(("  Your place: %s. Group %d of %d, free %d, invited and pending %d."):format(
            info.ownRole:lower(), math.max(1, state.numGroupMembers), D.GROUP_SIZE, info.free, info.waiting))
        print(("  Places to fill: tank %d, healer %d, damage %d."):format(info.open.TANK, info.open.HEALER,
            info.open.DAMAGER))
    end
    local chosenNames = {}
    if list then
        print(("  A click would print: %s"):format(L.BUILDING_FOR:format(ns.DungeonName(state.target))))
        print(("  Would invite (%s):"):format(D.INVITES_PER_CLICK == 1 and "first one per click" or "all in one click"))
        for i, c in ipairs(list) do
            chosenNames[c.name] = true
            local e
            for _, cand in ipairs(state.candidates) do
                if cand.name == c.name then e = cand end
            end
            print(("   %d. %s: %s - %s %d, %s, waits %ds, row place %d"):format(i, c.role:lower(), c.name,
                c.class, c.level, SignUp(e), e and e.age or 0, RowPlace(c.role, c.class) or 0))
            local whisper = B.WhisperFor(c, state)
            print("      " .. (whisper and ('whisper: "' .. whisper .. '"') or "no whisper"))
        end
    else
        print("  Would invite nobody: " .. L[why])
    end
    local after = info and After(state, info, list or {})
    if after then
        local left = {}
        for _, role in ipairs(D.ROLES) do
            if after.open[role] > 0 then left[#left + 1] = ("%s %d"):format(role:lower(), after.open[role]) end
        end
        if #left > 0 then
            print(("  Left open: %s - %s."):format(table.concat(left, ", "),
                after.free > 0 and "nobody fits" or "no free place left in the group"))
        end
    end
    local ownArmor = ns.ArmorOf(own.class, own.level)
    print("  Not chosen:")
    local left = 0
    local _, ids = C_LFGList.GetFilteredSearchResults()
    for _, id in ipairs(ids or {}) do
        local e = ns.ReadEntry(id) or {}
        if e.numMembers == 1 and not e.hasSelf then
            local reason = WhyNot(e, state, chosenNames, ownArmor, after)
            if reason then
                left = left + 1
                print(("   - %s %s %s (%s, waits %ds): %s"):format(tostring(e.name), tostring(e.class),
                    tostring(e.level), SignUp(e), e.age or 0, reason))
            end
        end
    end
    if left == 0 then print("   nobody") end
end
