-- Zweck: Berufsadapter fuer Spitzhacken-Arbeiter.
-- Erwartet: turtle API; wird von arbeiter/state.lua geladen.

local spitzhacke = {}

local patterns = { stone = true, ore = true, deepslate = true, netherrack = true, basalt = true, cobble = true, granite = true, diorite = true, andesite = true }

local function nameMatches(data)
  if type(data) ~= "table" or type(data.name) ~= "string" then return true end
  for key in pairs(patterns) do
    if string.find(data.name, key) then return true end
  end
  return false
end

function spitzhacke.canHandle(blockData)
  return nameMatches(blockData)
end

function spitzhacke.digForward()
  local ok, data = turtle.inspect()
  if ok and not spitzhacke.canHandle(data) then return false, "Block passt nicht zur Spitzhacke" end
  return turtle.dig()
end

function spitzhacke.digDown()
  local ok, data = turtle.inspectDown()
  if ok and not spitzhacke.canHandle(data) then return false, "Block passt nicht zur Spitzhacke" end
  return turtle.digDown()
end

function spitzhacke.digUp()
  local ok, data = turtle.inspectUp()
  if ok and not spitzhacke.canHandle(data) then return false, "Block passt nicht zur Spitzhacke" end
  return turtle.digUp()
end

return spitzhacke
