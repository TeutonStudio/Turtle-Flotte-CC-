-- Zweck: Berufsadapter fuer Axt-Arbeiter.
-- Erwartet: turtle API; wird von arbeiter/state.lua geladen.

local axt = {}

local patterns = { log = true, wood = true, stem = true, hyphae = true, leaves = true }

local function nameMatches(data)
  if type(data) ~= "table" or type(data.name) ~= "string" then return true end
  for key in pairs(patterns) do
    if string.find(data.name, key) then return true end
  end
  return false
end

function axt.canHandle(blockData)
  return nameMatches(blockData)
end

function axt.digForward()
  local ok, data = turtle.inspect()
  if ok and not axt.canHandle(data) then return false, "Block passt nicht zur Axt" end
  return turtle.dig()
end

function axt.digDown()
  local ok, data = turtle.inspectDown()
  if ok and not axt.canHandle(data) then return false, "Block passt nicht zur Axt" end
  return turtle.digDown()
end

function axt.digUp()
  local ok, data = turtle.inspectUp()
  if ok and not axt.canHandle(data) then return false, "Block passt nicht zur Axt" end
  return turtle.digUp()
end

return axt
