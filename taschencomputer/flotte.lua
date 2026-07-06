-- Zweck: Normaler Taschencomputer-Entry-Point fuer einen einzelnen Flotte-CLI-Aufruf.
-- Erwartet: Flotte/cli.lua und Flotte/common/* unter /Flotte/.

local cli = dofile("Flotte/cli.lua")

local args = { ... }
cli.run(args)

return cli
