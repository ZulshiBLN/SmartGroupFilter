-- rules/code.md names the only globals the addon may write. luacheck checks the source, but it
-- cannot see a write through _G["..."]: this loads the addon in an environment that records
-- every global it writes, and holds them against .luacheckrc's list.

local addon = require("addon")

-- The globals .luacheckrc allows, read from it rather than retyped here
local function allowed()
    local options = { files = {} }
    local chunk = assert(loadfile(".luacheckrc"))
    setfenv(chunk, options)
    chunk()
    local names = {}
    for _, name in ipairs(options.globals) do names[name] = true end
    return names
end

-- The written names .luacheckrc does not allow, sorted
local function strays(written)
    local ok, out = allowed(), {}
    for name in pairs(written) do
        if not ok[name] then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

describe("the globals the addon writes", function()
    it("are all named in .luacheckrc, at load and after login", function()
        addon.load("enUS", { recordGlobals = true })
        -- The login runs in the recording environment too: its frame was created there
        FIRE("PLAYER_LOGIN")
        assert.is_true(addon.written.SLASH_SMARTGROUPFILTER1) -- the recording sees the writes
        assert.are.same({}, strays(addon.written))
    end)

    it("would notice a stray one", function()
        addon.load("enUS", { recordGlobals = true })
        addon.written.SmartGroupFilterStray = true
        assert.are.same({ "SmartGroupFilterStray" }, strays(addon.written))
    end)
end)
