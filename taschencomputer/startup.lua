-- Compatibility entry point: all runtime behavior lives in v2.
local h=fs.open(".flotte/active","r")
local root=h and h.readAll() or ""
if h then h.close() end
return shell.run(root.."v2/main.lua","--role","taschencomputer",...)
