-- Zweck: Arbeiter aus Personal Chest auspacken und nach Jobende wieder einpacken.
-- Erwartet: turtle, gps, common/vec3.lua, common/protocol.lua.

local vec3 = dofile("common/vec3.lua")
local protocol = dofile("common/protocol.lua")

local deploy = {}
deploy.START_FUEL_DROP_COUNT = 64
deploy.REGISTER_TIMEOUT = 8
deploy.DEFAULT_CHEST_SIDE = "back"
deploy.COORDINATOR_MIN_FUEL = 20

local placedQueue = {}
local heading = nil
local config = {}

local function loadConfig()
  local paths = { "koordinator/config.lua", "flotte_config.lua" }
  for _, path in ipairs(paths) do
    if fs.exists(path) then
      local ok, loaded = pcall(dofile, path)
      if ok and type(loaded) == "table" then return loaded end
      print("Konfiguration nicht lesbar: " .. path)
    end
  end
  return {}
end

config = loadConfig()

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

local function isValidHeading(value)
  return value == "north" or value == "south" or value == "east" or value == "west"
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

local function turnAroundRaw()
  turtle.turnLeft()
  turtle.turnLeft()
end

local function fuelLevelText()
  local ok, level = pcall(turtle.getFuelLevel)
  if ok then return tostring(level) end
  return "unbekannt"
end

function deploy.refuelFromInventory()
  if not turtle or not turtle.refuel then return false, "Turtle API fehlt" end
  if turtle.getFuelLevel() == "unlimited" then return true end
  local changed = false
  for slot = 1, 16 do
    if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() >= deploy.COORDINATOR_MIN_FUEL then break end
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      local ok, canFuel = pcall(turtle.refuel, 0)
      if ok and canFuel then
        pcall(turtle.refuel, 1)
        changed = true
      end
    end
  end
  return changed
end

local function hasFuelForMove()
  local level = turtle.getFuelLevel()
  return level == "unlimited" or level > 0
end

local function moveFailureMessage(context, moveErr)
  local detected = false
  local okDetect, detectResult = pcall(turtle.detect)
  if okDetect then detected = detectResult end
  return tostring(context) .. ": Bewegung vorwaerts nicht moeglich; fuel=" .. fuelLevelText() .. "; detect=" .. tostring(detected) .. "; reason=" .. tostring(moveErr or "unbekannt")
end

local function headingFromDelta(before, after)
  local dx, dz = after.x - before.x, after.z - before.z
  if dx == 1 then return "east" end
  if dx == -1 then return "west" end
  if dz == 1 then return "south" end
  if dz == -1 then return "north" end
  return nil
end

local function calibrateByForward(context)
  local before, beforeErr = gpsPos()
  if not before then return false, "GPS fuer Heading-Kalibrierung nicht verfuegbar: " .. tostring(beforeErr) end
  local moved, moveErr = turtle.forward()
  if not moved then return false, moveFailureMessage(context, moveErr) end
  local after, afterErr = gpsPos()
  local backOk, backErr = turtle.back()
  if not after then return false, "GPS fuer Heading-Kalibrierung nicht verfuegbar: " .. tostring(afterErr) end
  if not backOk then return false, "Heading-Kalibrierung: Rueckkehr zum Start fehlgeschlagen; reason=" .. tostring(backErr) end
  local newHeading = headingFromDelta(before, after)
  if not newHeading then return false, "Heading konnte aus GPS-Bewegung nicht bestimmt werden" end
  heading = newHeading
  return true
end

local function calibrateByBack()
  local before, beforeErr = gpsPos()
  if not before then return false, "GPS fuer Heading-Kalibrierung nicht verfuegbar: " .. tostring(beforeErr) end
  local moved, moveErr = turtle.back()
  if not moved then return false, "Rueckwaerts-Kalibrierung fehlgeschlagen; fuel=" .. fuelLevelText() .. "; reason=" .. tostring(moveErr or "unbekannt") end
  local after, afterErr = gpsPos()
  local forwardOk, forwardErr = turtle.forward()
  if not after then return false, "GPS fuer Heading-Kalibrierung nicht verfuegbar: " .. tostring(afterErr) end
  if not forwardOk then return false, "Heading-Kalibrierung: Rueckkehr zum Start fehlgeschlagen; reason=" .. tostring(forwardErr) end
  local reverseHeading = headingFromDelta(before, after)
  if reverseHeading == "north" then heading = "south"
  elseif reverseHeading == "south" then heading = "north"
  elseif reverseHeading == "east" then heading = "west"
  elseif reverseHeading == "west" then heading = "east"
  else return false, "Heading konnte aus Rueckwaerts-GPS-Bewegung nicht bestimmt werden" end
  return true
end

local function calibrateHeading()
  if heading then return true end
  if isValidHeading(config.heading) then
    heading = config.heading
    print("Heading aus Konfiguration: " .. heading)
    return true
  end
  if not config.autoCalibrateHeading then
    return false, "Koordinator heading fehlt. Bitte koordinator/config.lua mit heading=\"north|south|east|west\" anlegen."
  end
  if not hasFuelForMove() then
    return false, "Koordinator hat keinen Fuel fuer Heading-Kalibrierung; fuel=" .. fuelLevelText()
  end

  local errors = {}
  local ok, err = calibrateByForward("Heading-Kalibrierung fehlgeschlagen")
  if ok then return true end
  errors[#errors + 1] = err

  ok, err = calibrateByBack()
  if ok then return true end
  errors[#errors + 1] = err

  turnLeft()
  ok, err = calibrateByForward("Heading-Kalibrierung links fehlgeschlagen")
  turnRight()
  if ok then return true end
  errors[#errors + 1] = err

  turnRight()
  ok, err = calibrateByForward("Heading-Kalibrierung rechts fehlgeschlagen")
  turnLeft()
  if ok then return true end
  errors[#errors + 1] = err

  print(table.concat(errors, " | "))
  return false, "Heading-Kalibrierung nicht moeglich: keine freie Bewegungsrichtung oder kein Fuel"
end

local function suckFromSide(side)
  if side == "front" then return turtle.suck() end
  if side == "up" then return turtle.suckUp() end
  if side == "down" then return turtle.suckDown() end
  if side == "left" then turtle.turnLeft(); local ok = turtle.suck(); turtle.turnRight(); return ok end
  if side == "right" then turtle.turnRight(); local ok = turtle.suck(); turtle.turnLeft(); return ok end
  turnAroundRaw()
  local ok = turtle.suck()
  turnAroundRaw()
  return ok
end

local function inventoryFull()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return false end
  end
  return true
end

function deploy.suckFromChest()
  if not turtle then return false, "Turtle API fehlt" end
  local side = config.chestSide or deploy.DEFAULT_CHEST_SIDE
  print("InitTruhe-Seite: " .. tostring(side))
  local successes = 0
  local misses = 0
  while successes + misses < 16 and not inventoryFull() do
    local ok = suckFromSide(side)
    if ok then
      successes = successes + 1
      misses = 0
    else
      misses = misses + 1
      if misses >= 2 then break end
    end
  end
  return successes
end

local function moveForwardOrFail(context)
  local moved, moveErr = turtle.forward()
  if moved then return true end
  return false, moveFailureMessage(context or "Deploy-Bewegung fehlgeschlagen", moveErr)
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
  deploy.refuelFromInventory()
  local hasWorker = selectWorkerItem()
  local hasFuel = selectFuelItem()
  if not hasWorker and not hasFuel then
    local err = "Aus InitTruhe wurden keine Worker/Fuel-Items aufgenommen. Pruefe chestSide in koordinator/config.lua."
    print(err)
    return {}, err
  end
  local placed = {}
  while #placed < (benoetigt or 1) do
    local okL, posL, errL = placeWorkerLeft()
    if okL then placed[#placed + 1] = posL else print(errL) end
    if #placed >= benoetigt then break end
    local okR, posR, errR = placeWorkerRight()
    if okR then placed[#placed + 1] = posR else print(errR) end
    if not okL and not okR then break end
    local moved, moveErr = moveForwardOrFail("Deploy-Vorschub")
    if not moved then print(moveErr); break end
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
