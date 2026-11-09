-- The globals rule is only enforced if .luacheckrc is actually strict. This
-- runs the real luacheck with the real config against snippets that must be
-- refused, so a config loosened by accident turns this red.

local luacheck = require("luacheck")
local lfs = require("lfs")
local addon = require("addon")

-- The config is Lua that assigns globals; run it in an empty environment and
-- hand what it set to luacheck as options. The per-path `files` section is
-- returned apart: a snippet stands in for ordinary addon code.
local function loadConfig()
    local options = { files = {} }
    local chunk = assert(loadfile(".luacheckrc"))
    setfenv(chunk, options)
    chunk()
    local files = options.files
    options.files = nil
    return options, files
end

local function warningsFor(source)
    local report = luacheck.check_strings({ source }, loadConfig())
    return report.warnings + report.errors
end

-- Any warning is not enough: a loosened config can trade the refusal for a
-- different, weaker warning. Each case asks for the refusal's own code.
local function hasCode(source, code)
    local report = luacheck.check_strings({ source }, loadConfig())
    for _, w in ipairs(report[1]) do
        if w.code == code then return true end
    end
    return false
end

describe(".luacheckrc", function()
    it("refuses writing a global the rule does not allow", function()
        assert.is_true(hasCode("SmartGroupFilterScratch = 1\n", "111"))
    end)

    it("refuses io, os, require, dofile and loadfile", function()
        for _, name in ipairs({ "io", "os", "require", "dofile", "loadfile" }) do
            assert.is_true(hasCode("local x = " .. name .. "\nreturn x\n", "113"), name)
        end
    end)

    it("refuses defining a top-level function", function()
        assert.is_true(hasCode("function SmartGroupFilterHelper() end\n", "111"))
    end)

    it("refuses writing another addon's slash command entry", function()
        assert.is_true(hasCode("SlashCmdList.SOMEONE_ELSE = print\n", "142"))
    end)

    it("allows exactly the globals the rule names", function()
        local allowed = table.concat({
            "SmartGroupFilterDB = {}",
            "SmartGroupFilterGlobalDB = {}",
            'SLASH_SMARTGROUPFILTER1 = "/x"',
            "SlashCmdList.SMARTGROUPFILTER = print",
            "function SmartGroupFilter_OnCompartmentClick() end",
            "function SmartGroupFilter_OnCompartmentEnter() end",
            "function SmartGroupFilter_OnCompartmentLeave() end",
        }, "\n") .. "\n"
        assert.are.equal(0, warningsFor(allowed))
    end)

    it("finds the addon's own files clean", function()
        local sources, names = {}, {}
        for entry in lfs.dir(addon.NAME) do
            if entry:match("%.lua$") then
                local path = addon.NAME .. "/" .. entry
                sources[#sources + 1] = addon.read(path)
                names[#names + 1] = path
            end
        end
        assert.is_true(#sources > 0)
        local report = luacheck.check_strings(sources, loadConfig())
        assert.are.equal(0, report.warnings + report.errors, table.concat(names, ", "))
    end)
end)
