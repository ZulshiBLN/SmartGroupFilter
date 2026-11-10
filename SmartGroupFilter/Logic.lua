-- SmartGroupFilter - logic
-- The rules of the filter and of Build Group (ruleset plan 2026-11-10-panel-filter-build,
-- -IMPLEMENTATION "Definitions"). No frame and no client call: Filter.lua and Build.lua read
-- the Group Finder and hand plain tables over.
--
-- An entry: { numMembers, hasSelf, isDelisted, name, class, level, age, roles, activities },
-- where class is the classFilename, roles the player's lfgRoles ({ tank, healer, dps }),
-- activities the activityIDs he listed for, and any field may be nil - a secret value arrives
-- as nil.

local _, ns = ...
local D = ns.D

local function HasRole(roles)
    if not roles then return false end
    for _, field in pairs(D.ROLE_FIELD) do
        if roles[field] then return true end
    end
    return false
end

local function IsSingle(entry)
    return entry.numMembers == 1 and not entry.hasSelf
end

-- May this class fill this role for this player? Signed up for roles: only those count;
-- signed up with none: any role the class can fill.
local function Fits(entry, role, db)
    local class = entry.class
    if not D.ROLE_CLASSES[role][class] or db.excluded[role][class] then return false end
    if HasRole(entry.roles) then return entry.roles[D.ROLE_FIELD[role]] and true or false end
    return true
end

-- Is the player listed for one of these dungeons (activityIDs)? Not while his are unknown.
function ns.ListedFor(entry, dungeons)
    for _, mine in ipairs(entry.activities or {}) do
        for _, id in ipairs(dungeons) do
            if mine == id then return true end
        end
    end
    return false
end

local function Known(entry)
    return entry.class ~= nil and type(entry.level) == "number" and entry.level >= 1
end

-- Does Blizzard's list keep this entry? range: { min, max }; ownArmor: the player's armor
-- class, which the list leaves out while "Allow same armor class" is off
function ns.Passes(entry, db, range, ownArmor)
    if entry.isDelisted then return false end
    if not IsSingle(entry) then return true end -- groups and the own listing stay
    -- Class or level not loaded yet (the client reports level 0 then): shown as Blizzard
    -- shows him; Filter.lua filters again once the client updates the result
    if not Known(entry) then return true end
    if entry.level < range.min or entry.level > range.max then return false end
    if not db.allowSameArmor and ownArmor and ns.ArmorOf(entry.class, entry.level) == ownArmor then
        return false
    end
    for _, role in ipairs(D.ROLES) do
        if Fits(entry, role, db) then return true end
    end
    return false
end

function ns.ArmorOf(class, level)
    local armor = D.ARMOR[class]
    if type(armor) == "table" then
        return (level or 0) < D.ARMOR_LEVEL and armor[1] or armor[2]
    end
    return armor
end

-- The better of two players of one class: the higher level, then the longer wait, then the
-- name, so the same list always gives the same choice
local function Better(a, b)
    if a.level ~= b.level then return a.level > b.level end
    if (a.age or 0) ~= (b.age or 0) then return (a.age or 0) > (b.age or 0) end
    return a.name < b.name
end

-- Chooses whom Build Group invites. state:
--   own             { class, level, roles }
--   members         { { name, class, level } } - the group without the player
--   placed          name -> { role, class, level, joined } - players SGF invited
--   numGroupMembers GetNumGroupMembers(): 0 alone, else the group's size with the player
--   candidates      entries from the Group Finder list
--   dungeons        activityIDs: only players listed for one of them are candidates
--   db, range
-- Returns a list of { name, role, class, level }, nil and a table of what the choice started
-- from ({ ownRole, free, waiting, open }); or nil and the reason.
function ns.ChooseInvites(state)
    local db, own = state.db, state.own
    local ownRole
    for _, role in ipairs(D.ROLES) do
        if own.roles and own.roles[D.ROLE_FIELD[role]] then ownRole = role break end
    end
    if not ownRole then return nil, "NO_OWN_ROLE" end

    local open = {}
    for role, n in pairs(D.PLACES) do open[role] = n end
    open[ownRole] = open[ownRole] - 1

    local classCount = { [own.class or ""] = 1 }
    local inGroup = {}
    for _, m in ipairs(state.members) do
        inGroup[m.name] = true
        if m.class then classCount[m.class] = (classCount[m.class] or 0) + 1 end
    end
    local waiting = 0
    for name, p in pairs(state.placed) do
        open[p.role] = math.max(0, open[p.role] - 1)
        if not p.joined and not inGroup[name] then
            waiting = waiting + 1
            classCount[p.class] = (classCount[p.class] or 0) + 1
        end
    end
    local free = D.GROUP_SIZE - math.max(1, state.numGroupMembers) - waiting
    -- What the choice starts from, for /sgf test
    local info = { ownRole = ownRole, free = free, waiting = waiting, open = {} }
    for role, n in pairs(open) do info.open[role] = n end

    local signed, unsigned = {}, {}
    for _, e in ipairs(state.candidates) do
        if IsSingle(e) and e.name and Known(e) and not state.placed[e.name]
            and not inGroup[e.name] and ns.ListedFor(e, state.dungeons)
            and ns.Passes(e, db, state.range) then
            if HasRole(e.roles) then signed[#signed + 1] = e else unsigned[#unsigned + 1] = e end
        end
    end

    local limit = D.MAX_SAME_CLASS[db.allowDouble and true or false]
    local ownArmor = ns.ArmorOf(own.class, own.level)
    local chosen, used = {}, {}

    local function Pick(role, pool)
        for _, class in ipairs(db.order[role]) do
            if not db.excluded[role][class] and (classCount[class] or 0) < limit then
                local best
                for _, e in ipairs(pool) do
                    if not used[e.name] and e.class == class and Fits(e, role, db)
                        and (db.allowSameArmor or ns.ArmorOf(e.class, e.level) ~= ownArmor)
                        and (not best or Better(e, best)) then
                        best = e
                    end
                end
                if best then return best end
            end
        end
    end

    -- Everyone who signed up for a role first; players with no role only for what is left
    for _, pool in ipairs({ signed, unsigned }) do
        for _, role in ipairs(D.ROLES) do
            while open[role] > 0 and #chosen < free do
                local e = Pick(role, pool)
                if not e then break end
                used[e.name] = true
                open[role] = open[role] - 1
                classCount[e.class] = (classCount[e.class] or 0) + 1
                chosen[#chosen + 1] = { name = e.name, role = role, class = e.class, level = e.level }
            end
        end
    end
    return chosen, nil, info
end
