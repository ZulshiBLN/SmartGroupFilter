-- SmartGroupFilter - data
-- Constants and defaults. Every fact lives here once; other files point at it.

local _, ns = ...

local D = {}
ns.D = D

-- The shape of the saved settings. A change to it needs a plan and a migration in ns.InitDB()
-- (ruleset project.md).
D.DB_VERSION = 1

-- What the chat command is called; the help and the error message name it from here
D.SLASH = "/sgf"
