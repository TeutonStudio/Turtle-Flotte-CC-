-- Zweck: Rollen-Update fuer Taschencomputer.
-- Erwartet: update/core.lua oder Flotte/update/core.lua.

local corePath = fs.exists("Flotte/update/core.lua") and "Flotte/update/core.lua" or "update/core.lua"
local core = dofile(corePath)

return core.run("taschencomputer")
