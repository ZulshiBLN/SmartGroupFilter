-- The WoW API the addon touches, mocked for busted. Only what the addon uses: a new API call
-- in the addon is added here with the behaviour the client shows, never guessed wider.
--
-- STATE holds the mocked world; tests/helpers/addon.lua sets it before the addon loads, and a
-- spec may change its fields afterwards. FIRE sends an event to every frame registered for it,
-- CHAT holds every line the addon printed, RUNSCRIPT runs a frame's script.

STATE = {
    locale = "enUS",
    version = "0.1.0",
}

CHAT = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    CHAT[#CHAT + 1] = table.concat(parts, " ")
end

function GetLocale() return STATE.locale end

C_AddOns = {
    GetAddOnMetadata = function(_, field)
        if field == "Version" then return STATE.version end
    end,
}

SlashCmdList = {}

local frames = {}

local function NewFrame()
    local f = { events = {}, scripts = {} }
    function f:RegisterEvent(event) self.events[event] = true end
    function f:UnregisterEvent(event) self.events[event] = nil end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:GetScript(name) return self.scripts[name] end
    return f
end

function CreateFrame()
    local f = NewFrame()
    frames[#frames + 1] = f
    return f
end

function FIRE(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

function RUNSCRIPT(frame, name, ...)
    return frame.scripts[name](frame, ...)
end
