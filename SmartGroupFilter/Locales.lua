-- SmartGroupFilter - localization
-- The language follows the client (GetLocale()); a saved choice overrides it (ns.SetLocale).
-- Missing texts fall back to English (enUS). enGB clients report enUS.
-- string.format in WoW Lua has no positional arguments (%1$s), so every translation keeps the
-- placeholder order of enUS.

local _, ns = ...

local locales = {}

locales.enUS = {
    LOADED = "Version %s loaded.",
    HELP_HEADER = "Chat commands:",
    CMD_HELP = "Show this list",
    CMD_UNKNOWN = "Unknown command. Type %s for a list.",
}

locales.deDE = {
    LOADED = "Version %s geladen.",
    HELP_HEADER = "Chat-Befehle:",
    CMD_HELP = "Diese Liste anzeigen",
    CMD_UNKNOWN = "Unbekannter Befehl. %s zeigt alle Befehle.",
}

locales.frFR = {
    LOADED = "Version %s chargée.",
    HELP_HEADER = "Commandes de discussion :",
    CMD_HELP = "Afficher cette liste",
    CMD_UNKNOWN = "Commande inconnue. Tapez %s pour la liste.",
}

locales.esES = {
    LOADED = "Versión %s cargada.",
    HELP_HEADER = "Comandos de chat:",
    CMD_HELP = "Mostrar esta lista",
    CMD_UNKNOWN = "Comando desconocido. Escribe %s para ver la lista.",
}

-- esMX holds only what differs from esES
locales.esMX = setmetatable({
}, { __index = locales.esES })

locales.itIT = {
    LOADED = "Versione %s caricata.",
    HELP_HEADER = "Comandi chat:",
    CMD_HELP = "Mostra questo elenco",
    CMD_UNKNOWN = "Comando sconosciuto. Digita %s per l'elenco.",
}

locales.ptBR = {
    LOADED = "Versão %s carregada.",
    HELP_HEADER = "Comandos de chat:",
    CMD_HELP = "Mostrar esta lista",
    CMD_UNKNOWN = "Comando desconhecido. Digite %s para ver a lista.",
}

locales.ruRU = {
    LOADED = "Версия %s загружена.",
    HELP_HEADER = "Команды чата:",
    CMD_HELP = "Показать этот список",
    CMD_UNKNOWN = "Неизвестная команда. Введите %s для списка.",
}

locales.koKR = {
    LOADED = "버전 %s 로드됨.",
    HELP_HEADER = "채팅 명령어:",
    CMD_HELP = "이 목록 표시",
    CMD_UNKNOWN = "알 수 없는 명령어입니다. 목록은 %s 를 입력하세요.",
}

locales.zhCN = {
    LOADED = "版本 %s 已加载。",
    HELP_HEADER = "聊天命令：",
    CMD_HELP = "显示此列表",
    CMD_UNKNOWN = "未知命令。输入 %s 查看列表。",
}

locales.zhTW = {
    LOADED = "版本 %s 已載入。",
    HELP_HEADER = "聊天指令：",
    CMD_HELP = "顯示此列表",
    CMD_UNKNOWN = "未知指令。輸入 %s 查看列表。",
}

local client = GetLocale()
if not locales[client] then client = "enUS" end -- e.g. enGB/enCN -> English
local active, activeCode = locales[client], client

ns.locales = locales
ns.clientLocale = client
ns.LOCALE_ORDER = { "enUS", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
-- Language names in their own language; non-Latin scripts carry an English suffix in case the
-- client font cannot display them
ns.LOCALE_NAMES = {
    enUS = "English", deDE = "Deutsch", frFR = "Français",
    esES = "Español (España)", esMX = "Español (México)", itIT = "Italiano",
    ptBR = "Português (Brasil)", ruRU = "Русский (Russian)", koKR = "한국어 (Korean)",
    zhCN = "简体中文 (Chinese S.)", zhTW = "繁體中文 (Chinese T.)",
}

function ns.SetLocale(code)
    if not locales[code] then code = client end
    active, activeCode = locales[code], code
end
function ns.GetLocaleCode() return activeCode end
ns.L = setmetatable({}, {
    __index = function(_, key)
        return active[key] or locales.enUS[key] or key
    end,
})
