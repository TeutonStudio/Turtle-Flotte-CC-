-- Zweck: Interaktive Startdatei fuer den Taschencomputer.
-- Erwartet: common/* und taschencomputer/cli.lua im selben Dateibaum.

local cli = dofile("taschencomputer/cli.lua")

local startup = {}

function startup.main()
  print("Flotte Taschencomputer bereit. 'flotte list' oder 'exit'.")
  while true do
    write("> ")
    local line = read()
    if not line or line == "exit" then return true end
    local args = {}
    for token in string.gmatch(line, "%S+") do args[#args + 1] = token end
    local ok, err = pcall(cli.run, args)
    if not ok then print("Fehler: " .. tostring(err)) end
  end
end

startup.main()
return startup
