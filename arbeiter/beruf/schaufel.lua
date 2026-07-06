-- Zweck: Berufsadapter fuer Schaufel-Arbeiter.
-- Erwartet: turtle API; wird von arbeiter/state.lua geladen.

local schaufel = {}

local patterns = { dirt = true, grass = true, sand = true, gravel = true, clay = true, snow = true, mud = true }

local function nameMatches(data)
  if type(data) ~= "table" or type(data.name) ~= "string" then return true end
  for key in pairs(patterns) do
    if string.find(data.name, key) then return true end
  end
  return false
end

function schaufel.canHandle(blockData)
  return nameMatches(blockData)
end

function schaufel.digForward()
  local ok, data = turtle.inspect()
  if ok and not schaufel.canHandle(data) then return false, "Block passt nicht zur Schaufel" end
  return turtle.dig()
end

function schaufel.digDown()
  local ok, data = turtle.inspectDown()
  if ok and not schaufel.canHandle(data) then return false, "Block passt nicht zur Schaufel" end
  return turtle.digDown()
end

function schaufel.digUp()
  local ok, data = turtle.inspectUp()
  if ok and not schaufel.canHandle(data) then return false, "Block passt nicht zur Schaufel" end
  return turtle.digUp()
end

return schaufel
