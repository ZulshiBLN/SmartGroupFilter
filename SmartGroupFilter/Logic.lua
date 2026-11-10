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

-- The dungeon Build Group builds for, of the own dungeons (activityIDs, the listing's order):
-- the one for which ChooseInvites would fill the most tank and healer places - they are rare,
-- damage dealers are not (Michel, 2026-11-11) - then the most players; a tie goes to the
-- earlier. state as for ChooseInvites, without dungeons.
function ns.ChooseTarget(state, dungeons)
    if #dungeons <= 1 then return dungeons[1] end
    local best, bestRare, bestAll
    for _, id in ipairs(dungeons) do
        local each = {}
        for k, v in pairs(state) do each[k] = v end
        each.dungeons = { id }
        local chosen = ns.ChooseInvites(each) or {}
        local rare = 0
        for _, c in ipairs(chosen) do
            if c.role ~= "DAMAGER" then rare = rare + 1 end
        end
        if not best or rare > bestRare or (rare == bestRare and #chosen > bestAll) then
            best, bestRare, bestAll = id, rare, #chosen
        end
    end
    return best
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
    info.tried = 0 -- complete fills the search weighed, for the specs

    -- A role's candidates in priority order: the row's classes in order, the better player of
    -- a class first, and per class only as many as the class limit lets into a group - no best
    -- fill needs a worse player of a class (ruleset plan 2026-11-11-roles-and-places)
    local function Ranked(role, pool)
        local list = {}
        for _, class in ipairs(db.order[role]) do
            if not db.excluded[role][class] then
                local of = {}
                for _, e in ipairs(pool) do
                    if not used[e.name] and e.class == class and Fits(e, role, db)
                        and (db.allowSameArmor or ns.ArmorOf(e.class, e.level) ~= ownArmor) then
                        of[#of + 1] = e
                    end
                end
                table.sort(of, Better)
                for i = 1, math.min(#of, limit) do list[#list + 1] = of[i] end
            end
        end
        return list
    end

    -- The best fill of the open places from one pool: the most tank and healer places, then the
    -- most players. The search tries each place's candidates in priority order, the place left
    -- empty last, and only a strictly better fill replaces the one found - so among equals the
    -- fill priority would choose stays, a filled place before an empty one (Michel, 2026-11-11:
    -- one place after another left a healer place empty that a tank-only player could free).
    local function BestFill(pool)
        local slots, ranked = {}, {}
        for _, role in ipairs(D.ROLES) do
            ranked[role] = Ranked(role, pool)
            for _ = 1, open[role] do slots[#slots + 1] = role end
        end
        local room = free - #chosen
        local pick, taken = {}, {}
        local best, bestRare, bestAll = {}, -1, -1
        local function Search(i, rare, all, from)
            if i > #slots then
                info.tried = info.tried + 1
                if rare > bestRare or (rare == bestRare and all > bestAll) then
                    best, bestRare, bestAll = {}, rare, all
                    for k, e in pairs(pick) do best[k] = e end
                end
                return
            end
            -- Stop where even filling every place left cannot beat the best fill found
            local left = math.min(#slots - i + 1, room - all)
            local rareLeft = 0
            for k = i, #slots do
                if slots[k] ~= "DAMAGER" then rareLeft = rareLeft + 1 end
            end
            rareLeft = math.min(rareLeft, left)
            if rare + rareLeft < bestRare or (rare + rareLeft == bestRare and all + left <= bestAll) then return end
            local role = slots[i]
            -- Places of one role take candidates in rising order: no fill is weighed twice
            local nextSame = slots[i + 1] == role
            if all < room then
                local list = ranked[role]
                for k = from, #list do
                    local e = list[k]
                    if not taken[e.name] and (classCount[e.class] or 0) < limit then
                        taken[e.name] = true
                        classCount[e.class] = (classCount[e.class] or 0) + 1
                        pick[i] = e
                        Search(i + 1, rare + (role ~= "DAMAGER" and 1 or 0), all + 1, nextSame and k + 1 or 1)
                        pick[i] = nil
                        classCount[e.class] = classCount[e.class] - 1
                        taken[e.name] = nil
                    end
                end
            end
            -- This place empty, and so the role's later places
            local j = i
            while j <= #slots and slots[j] == role do j = j + 1 end
            Search(j, rare, all, 1)
        end
        Search(1, 0, 0, 1)
        for i = 1, #slots do
            local e = best[i]
            if e then
                local role = slots[i]
                used[e.name] = true
                open[role] = open[role] - 1
                classCount[e.class] = (classCount[e.class] or 0) + 1
                chosen[#chosen + 1] = { name = e.name, role = role, class = e.class, level = e.level }
            end
        end
    end

    -- Everyone who signed up for a role first; players with no role only for what is left,
    -- strictly (Michel, 2026-11-11)
    BestFill(signed)
    BestFill(unsigned)
    return chosen, nil, info
end
