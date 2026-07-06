-- Zweck: Grundgeruest fuer Crafting-Arbeiter; v1 nutzt noch keine Crafting-Jobs.
-- Erwartet: turtle API; wird von arbeiter/state.lua geladen.

local werkbank = {}

function werkbank.canHandle()
  return false
end

function werkbank.digForward()
  return false, "Werkbank-Arbeiter graebt nicht"
end

function werkbank.digDown()
  return false, "Werkbank-Arbeiter graebt nicht"
end

function werkbank.digUp()
  return false, "Werkbank-Arbeiter graebt nicht"
end

function werkbank.craft(count)
  if not turtle or not turtle.craft then return false, "Crafting API fehlt" end
  return turtle.craft(count)
end

return werkbank
