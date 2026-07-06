-- Zweck: Arbeiter aus Personal Chest auspacken und nach Jobende wieder einpacken.
-- Erwartet: turtle, gps, common/vec3.lua, common/protocol.lua.

local vec3 = dofile("common/vec3.lua")
local protocol = dofile("common/protocol.lua")

local deploy = {}
deploy.START_FUEL_DROP_COUNT = 64
deploy.REGISTER_TIMEOUT = 8

local placedQueue = {}
local heading = nil

local function itemName(slot)
  local detail = turtle.getItemDetail(slot)
  return detail and string.lower(tostring(detail.name or "")) or ""
end

local function isWorkerItemName(name)
  return string.find(name, "turtle", 1, true) ~= nil
end

local function selectWorkerItem()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 and isWorkerItemName(itemName(slot)) then
      turtle.select(slot)
      return true
    end
  end
  return false, "Kein Worker-Turtle-Item im Koordinator-Inventar gefunden"
end

local function selectFuelItem()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      local ok, canFuel = pcall(turtle.refuel, 0)
      if ok and canFuel then return true end
    end
  end
  return false, "Kein Fuel-Item im Koordinator-Inventar gefunden"
end

local function gpsPos()
  return vec3.fromGps(2)
end

local function headingVector(name)
  if name == "north" then return { x = 0, y = 0, z = -1 } end
  if name == "south" then return { x = 0, y = 0, z = 1 } end
  if name == "east" then return { x = 1, y = 0, z = 0 } end
  if name == "west" then return { x = -1, y = 0, z = 0 } end
  return nil
end

local function leftVector()
  local h = headingVector(heading)
  if not h then return nil end
  return { x = h.z, y = 0, z = -h.x }
end

local function rightVector()
  local h = headingVector(heading)
  if not h then return nil end
  return { x = -h.z, y = 0, z = h.x }
end

local function addOffset(pos, offset)
  if not pos or not offset then return nil end
  return { x = pos.x + offset.x, y = pos.y + offset.y, z = pos.z + offset.z }
end

local function turnLeft()
  turtle.turnLeft()
  if heading == "north" then heading = "west"
  elseif heading == "west" then heading = "south"
  elseif heading == "south" then heading = "east"
  elseif heading == "east" then heading = "north" end
end

local function turnRight()
  turtle.turnRight()
  if heading == "north" then heading = "east"
  elseif heading == "east" then heading = "south"
  elseif heading == "south" then heading = "west"
  elseif heading == "west" then heading = "north" end
end

local function calibrateHeading()
  if heading then return true end
  local before, beforeErr = gpsPos()
  if not before then return false, beforeErr or "GPS vor Heading-Kalibrierung fehlgeschlagen" end
  if not turtle.forward() then return false, "Heading-Kalibrierung fehlgeschlagen: Feld vor Koordinator blockiert" end
  local after, afterErr = gpsPos()
  turtle.back()
  if not after then return false, afterErr or "GPS nach Heading-Kalibrierung fehlgeschlagen" end
  local dx, dz = after.x - before.x, after.z - before.z
  if dx == 1 then heading = "east"
  elseif dx == -1 then heading = "west"
  elseif dz == 1 then heading = "south"
  elseif dz == -1 then heading = "north"
  else return false, "Heading konnte aus GPS-Bewegung nicht bestimmt werden" end
  return true
end

function deploy.suckFromChest()
  if not turtle then return false, "Turtle API fehlt" end
  turnLeft()
  turnLeft()
  for _ = 1, 16 do turtle.suck() end
  turnLeft()
  turnLeft()
  return true
end

local function placeWorkerLeft()
  local basePos, posErr = gpsPos()
  if not basePos then return false, nil, posErr end
  local offset = leftVector()
  if not offset then return false, nil, "Heading nicht kalibriert" end
  local okFuel, fuelErr = selectFuelItem()
  if not okFuel then return false, nil, fuelErr end
  local okWorker, workerErr = selectWorkerItem()
  if not okWorker then return false, nil, workerErr end
  turnLeft()
  local placed = turtle.place()
  if not placed then turnRight(); return false, nil, "Worker links platzieren fehlgeschlagen" end
  local okFuelDrop, dropErr = selectFuelItem()
  if not okFuelDrop then turnRight(); return false, nil, dropErr end
  if not turtle.drop(deploy.START_FUEL_DROP_COUNT) then turnRight(); return false, nil, "Fuel-Drop in linken Worker fehlgeschlagen" end
  turnRight()
  return true, addOffset(basePos, offset)
end

local function placeWorkerRight()
  local basePos, posErr = gpsPos()
  if not basePos then return false, nil, posErr end
  local offset = rightVector()
  if not offset then return false, nil, "Heading nicht kalibriert" end
  local okFuel, fuelErr = selectFuelItem()
  if not okFuel then return false, nil, fuelErr end
  local okWorker, workerErr = selectWorkerItem()
  if not okWorker then return false, nil, workerErr end
  turnRight()
  local placed = turtle.place()
  if not placed then turnLeft(); return false, nil, "Worker rechts platzieren fehlgeschlagen" end
  local okFuelDrop, dropErr = selectFuelItem()
  if not okFuelDrop then turnLeft(); return false, nil, dropErr end
  if not turtle.drop(deploy.START_FUEL_DROP_COUNT) then turnLeft(); return false, nil, "Fuel-Drop in rechten Worker fehlgeschlagen" end
  turnLeft()
  return true, addOffset(basePos, offset)
end

function deploy.auspacken(benoetigt)
  if not turtle then return {}, "Turtle API fehlt" end
  local headingOk, headingErr = calibrateHeading()
  if not headingOk then print(headingErr); return {}, headingErr end
  deploy.suckFromChest()
  local placed = {}
  while #placed < (benoetigt or 1) do
    local okL, posL, errL = placeWorkerLeft()
    if okL then placed[#placed + 1] = posL else print(errL) end
    if #placed >= benoetigt then break end
    local okR, posR, errR = placeWorkerRight()
    if okR then placed[#placed + 1] = posR else print(errR) end
    if not okL and not okR then break end
    turtle.forward()
  end
  placedQueue = placed
  return placed
end

function deploy.naechsteDockPos()
  if #placedQueue == 0 then return nil end
  return table.remove(placedQueue, 1)
end

function deploy.returnToDock(workerList)
  for _, worker in ipairs(workerList or {}) do
    if worker.dockPos then
      worker.status = "returning"
      protocol.send(worker.id, protocol.RETURN_TO_DOCK, { dockPos = worker.dockPos })
    end
  end
end

function deploy.einlagernInventar()
  if not turtle then return false, "Turtle API fehlt" end
  turnLeft()
  turnLeft()
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.getItemCount(slot) > 0 then turtle.drop() end
  end
  turnLeft()
  turnLeft()
  return true
end

function deploy.einpacken(workerList)
  -- Minimaler v1-Einpackpfad: Worker werden zum Dock gerufen; der Koordinator baut nahe Docks ab.
  deploy.returnToDock(workerList)
  return true
end

return deploy
