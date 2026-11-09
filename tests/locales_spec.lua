-- rules/localization.md: every enUS key exists in every other locale, with
-- the placeholders in the same order. The keys, the locale list and the
-- esMX -> esES inheritance are read from Locales.lua, never retyped here.

local addon = require("addon")

local PATH = addon.NAME .. "/Locales.lua"

-- Runs Locales.lua as the client would, with GetLocale answering `client`,
-- and returns the namespace it fills. A changed source can be passed in.
local function load(client, source)
    local ns = {}
    local chunk = assert(loadstring(source or addon.read(PATH), "Locales.lua"))
    setfenv(chunk, setmetatable({ GetLocale = function() return client end }, { __index = _G }))
    chunk(addon.NAME, ns)
    return ns
end

-- The placeholder letters in order, e.g. "sd" for "Missing %s: %d".
local function placeholders(s)
    local seq = {}
    for p in s:gmatch("%%([sd])") do seq[#seq + 1] = p end
    return table.concat(seq)
end

-- The text a locale table gives for a key: its own, or what it inherits.
local function lookup(t, key)
    local v = rawget(t, key)
    if v ~= nil then return v end
    local mt = getmetatable(t)
    local parent = mt and type(mt.__index) == "table" and mt.__index
    return parent and lookup(parent, key)
end

-- Any one enUS key, for the checks that need a key to remove or look up.
local function someKey(ns)
    return (next(ns.locales.enUS))
end

describe("locales", function()
    local ns = load("enUS")

    it("lists every locale it defines, and enUS defines keys", function()
        assert.is_true(#ns.LOCALE_ORDER > 1)
        assert.is_not_nil(next(ns.locales.enUS))
        for _, code in ipairs(ns.LOCALE_ORDER) do
            assert.is_table(ns.locales[code], code)
            assert.is_string(ns.LOCALE_NAMES[code], code)
        end
    end)

    it("has every enUS key in every locale", function()
        for _, code in ipairs(ns.LOCALE_ORDER) do
            for key in pairs(ns.locales.enUS) do
                assert.is_string(lookup(ns.locales[code], key), code .. "." .. key)
            end
        end
    end)

    it("keeps each text's placeholders in the order of enUS", function()
        for _, code in ipairs(ns.LOCALE_ORDER) do
            for key, english in pairs(ns.locales.enUS) do
                local text = lookup(ns.locales[code], key)
                assert.are.equal(placeholders(english), placeholders(text), code .. "." .. key)
            end
        end
    end)

    it("defines no key that enUS lacks", function()
        for _, code in ipairs(ns.LOCALE_ORDER) do
            for key in pairs(ns.locales[code]) do
                assert.is_string(ns.locales.enUS[key], code .. "." .. key)
            end
        end
    end)

    it("lets esMX inherit what it does not override from esES", function()
        local esMX, esES = ns.locales.esMX, ns.locales.esES
        local inherited = 0
        for key in pairs(ns.locales.enUS) do
            if rawget(esMX, key) == nil then
                inherited = inherited + 1
                assert.are.equal(esES[key], lookup(esMX, key), key)
            end
        end
        assert.is_true(inherited > 0)
    end)

    -- The check above must be able to fail: drop one German entry from a copy
    -- of the source and it has to notice.
    it("would notice a key missing from a locale", function()
        local key = someKey(ns)
        -- [^}] keeps the match inside the deDE table: .- would reach the next locale's key
        local cut, n = addon.read(PATH):gsub("(locales%.deDE = {[^}]-)\n%s*" .. key .. " = [^\n]*", "%1", 1)
        assert.are.equal(1, n, "the test copy should lose deDE." .. key)
        local broken = load("deDE", cut)
        assert.is_nil(lookup(broken.locales.deDE, key))
        assert.are.equal(broken.locales.enUS[key], broken.L[key]) -- English at runtime
    end)

    it("falls back to English at runtime, and follows SetLocale", function()
        local key = someKey(ns)
        local de = load("deDE")
        assert.are.equal("deDE", de.GetLocaleCode())
        assert.are.equal(de.locales.deDE[key], de.L[key])
        assert.are.equal("NO_SUCH_KEY", de.L.NO_SUCH_KEY)
        de.SetLocale("frFR")
        assert.are.equal(de.locales.frFR[key], de.L[key])
        de.SetLocale("xxXX") -- unknown: back to the client language
        assert.are.equal("deDE", de.GetLocaleCode())
        local en = load("enGB")
        assert.are.equal("enUS", en.GetLocaleCode())
    end)
end)
