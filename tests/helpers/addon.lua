-- Loads the addon as the client does: the mocked WoW API first, then every
-- file the TOC lists, in the TOC's order, each called with the addon's name
-- and one shared namespace. The file list is read from the TOC, never retyped.
local M = {}

local ADDON = "SmartGroupFilter"
M.NAME = ADDON

function M.read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

-- The Lua files of the TOC, in load order. release: as the packager leaves the TOC, without
-- the lines between #@do-not-package@ and #@end-do-not-package@.
function M.tocFiles(release)
    local files, skip = {}, false
    for line in M.read(ADDON .. "/" .. ADDON .. ".toc"):gmatch("[^\r\n]+") do
        if line:match("^#@do%-not%-package@") then
            skip = release
        elseif line:match("^#@end%-do%-not%-package@") then
            skip = false
        elseif not skip and not line:match("^%s*#") and line:match("%S") then
            files[#files + 1] = line:match("^%s*(.-)%s*$")
        end
    end
    return files
end

-- A fresh mocked client with the addon loaded; `locale` is what GetLocale
-- answers. `world` may set the saved variables `db` and `globalDB` as the
-- client hands them over. They are set here, not in a spec: busted gives each
-- spec file its own globals, which the addon never sees. world.release loads only what a
-- release package holds.
-- Returns the addon's namespace.
function M.load(locale, world)
    world = world or {}
    assert(loadfile("tests/helpers/mock.lua"))()
    STATE.locale = locale or "deDE"
    SmartGroupFilterDB, SmartGroupFilterGlobalDB = world.db, world.globalDB
    -- world.recordGlobals: the files run in an environment of their own that records every
    -- global they write, `_G["..."]` too, in M.written - the specs share one global table, so
    -- comparing it before and after a load would miss a name an earlier load left
    local env
    if world.recordGlobals then
        local written, store = {}, {}
        env = setmetatable({}, {
            __index = function(_, k)
                if store[k] ~= nil then return store[k] end
                return _G[k]
            end,
            __newindex = function(_, k, v)
                written[k] = true
                store[k] = v
            end,
        })
        rawset(env, "_G", env)
        M.written = written
        M.store = store
    end
    local ns = {}
    for _, file in ipairs(M.tocFiles(world.release)) do
        local chunk = assert(loadstring(M.read(ADDON .. "/" .. file), "@" .. ADDON .. "/" .. file))
        if env then setfenv(chunk, env) end
        chunk(ADDON, ns)
    end
    return ns
end

return M
