-- SmartGroupFilter - core
-- Chat output, the runtime language switch and the saved variables. Every other module builds
-- on this file.

local ADDON_NAME, ns = ...
local D = ns.D

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"

---------------------------------------------------------------------------
-- Chat output
---------------------------------------------------------------------------
function ns.Print(msg)
    print("|cff33ff99SmartGroupFilter|r: " .. msg)
end

---------------------------------------------------------------------------
-- Runtime language switch, as in the sister addons
-- Every localized text is registered with its key (and format arguments), so a language
-- change re-renders exactly these texts. No text is ever matched by its content.
---------------------------------------------------------------------------
local registry = setmetatable({}, { __mode = "k" }) -- object -> key | function | { key, args... }
local languageCallbacks = {}

local function Resolve(entry)
    local kind = type(entry)
    if kind == "function" then return entry() end
    if kind == "table" then return ns.L[entry[1]]:format(unpack(entry, 2)) end
    return ns.L[entry]
end

-- Sets a localized text on a FontString or Button and keeps it current on language changes.
-- key: locale key, or a function returning the text. Extra arguments are format arguments.
function ns.SetL(obj, key, ...)
    local entry = key
    if select("#", ...) > 0 then entry = { key, ... } end
    registry[obj] = entry
    obj:SetText(Resolve(entry))
end

-- A name the client provides (a class, a zone): the client's own while the addon speaks the
-- client's language, else the addon's translation under `key` (localization.md)
function ns.LocalName(clientName, key)
    if clientName and ns.GetLocaleCode() == ns.clientLocale then return clientName end
    return ns.L[key]
end

-- fn runs after every language change (layout updates that depend on text widths)
function ns.OnLanguageChanged(fn)
    languageCallbacks[#languageCallbacks + 1] = fn
end

function ns.ApplyLanguage(code)
    if code == ns.GetLocaleCode() then return end
    ns.SetLocale(code)
    for obj, entry in pairs(registry) do obj:SetText(Resolve(entry)) end
    for _, fn in ipairs(languageCallbacks) do fn() end
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local db
local dbCallbacks = {}

-- Modules keep their own local reference to the settings table; it exists after PLAYER_LOGIN.
function ns.OnDBReady(fn)
    dbCallbacks[#dbCallbacks + 1] = fn
    if db then fn(db) end
end

-- Reads both saved tables as the client hands them over. Whatever they hold, the addon must
-- start: a damaged value is dropped, never trusted (ruleset project.md, "Data").
function ns.InitDB()
    if type(SmartGroupFilterGlobalDB) ~= "table" then SmartGroupFilterGlobalDB = {} end
    local lang = SmartGroupFilterGlobalDB.language
    if lang ~= nil and not ns.locales[lang] then
        SmartGroupFilterGlobalDB.language = nil -- unknown language code
    end

    if type(SmartGroupFilterDB) ~= "table" then SmartGroupFilterDB = {} end
    db = SmartGroupFilterDB
    db.dbVersion = D.DB_VERSION

    for _, fn in ipairs(dbCallbacks) do fn(db) end
end
