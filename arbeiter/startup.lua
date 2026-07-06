-- Zweck: Startdatei fuer Arbeiter-Turtles.
-- Erwartet: common/* und arbeiter/state.lua im selben Dateibaum.

local state = dofile("arbeiter/state.lua")
state.main()
return state
