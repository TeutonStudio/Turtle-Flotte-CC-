-- Zweck: Stationaeres Deploy fuer Koordinator-Turtles auf einer InitTruhe.
-- Erwartet: turtle, common/protocol.lua; InitTruhe direkt unter dem Koordinator.

local protocol = dofile("common/protocol.lua")

local deploy = {}
deploy.START_FUEL_DROP_COUNT = 64
deploy.COORDINATOR_MIN_FUEL = 50

local function itemName(slot)
  local detail = turtle.getItemDetail(slot)
  return detail and string.lower(tostring(detail.name or "")) or ""
end

local function isWorkerItemName(name)
  return string.find(name, "turtle", 1, true) ~= nil
end

local function inventoryFull()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return false end
  end
  return true
end

local function hasWorkerItem()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 and isWorkerItemName(itemName(slot)) then return true end
  end
  return false
end

local function hasFuelItem()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      local ok, canFuel = pcall(turtle.refuel, 0)
      if ok and canFuel then return true end
    end
  end
  return false
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

function deploy.suckFromChestBelow()
  if not turtle then return 0, "Turtle API fehlt" end
  local successes = 0
  local misses = 0
  while successes + misses < 16 and not inventoryFull() do
    local ok = turtle.suckDown()
    if ok then
      successes = successes + 1
      misses = 0
    else
      misses = misses + 1
      if misses >= 2 then break end
    end
  end
  local worker = hasWorkerItem()
  local fuel = hasFuelItem()
  print("InitTruhe unten: " .. tostring(successes) .. " Suck-Vorgaenge; worker=" .. tostring(worker) .. "; fuel=" .. tostring(fuel))
  return successes
end

-- Rueckwaertskompatibler Name fuer aeltere Aufrufer.
function deploy.suckFromChest()
  return deploy.suckFromChestBelow()
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
  if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() <= 0 then
    print("Koordinator hat keinen Fuel. Fuel in InitTruhe unter Koordinator legen.")
  end
  return changed
end

local function frontBlocked()
  local ok, blocked = pcall(turtle.detect)
  if ok then return blocked end
  return false
end

local function placeWorkerForward()
  local okWorker, workerErr = selectWorkerItem()
  if not okWorker then return false, nil, workerErr end

  local placed, placeErr = turtle.place()
  if not placed then
    return false, nil, "Worker vorne platzieren fehlgeschlagen; frontBlocked=" .. tostring(frontBlocked()) .. "; reason=" .. tostring(placeErr or "unbekannt")
  end

  local okFuel, fuelErr = selectFuelItem()
  if not okFuel then return false, nil, fuelErr end
  local dropped, dropErr = turtle.drop(deploy.START_FUEL_DROP_COUNT)
  if not dropped then return false, nil, "Fuel-Drop in Worker vorne fehlgeschlagen; reason=" .. tostring(dropErr or "unbekannt") end

  print("Worker vorne platziert; Startfuel=" .. tostring(deploy.START_FUEL_DROP_COUNT))
  return true, nil
end

function deploy.auspacken(benoetigt)
  if not turtle then return {}, "Turtle API fehlt" end
  if (benoetigt or 1) > 1 then
    print("Mehrere Worker nach vorne platzieren ist im stationaeren Front-Deploy noch nicht implementiert.")
  end

  deploy.suckFromChestBelow()
  deploy.refuelFromInventory()

  if not hasWorkerItem() and not hasFuelItem() then
    local err = "Aus InitTruhe wurden keine Worker/Fuel-Items aufgenommen. InitTruhe muss direkt unter dem Koordinator stehen."
    print(err)
    return {}, err
  end

  local ok, _, err = placeWorkerForward()
  if not ok then print(err); return {}, err end
  return {}
end

function deploy.naechsteDockPos()
  return nil
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
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.getItemCount(slot) > 0 then turtle.dropDown() end
  end
  return true
end

function deploy.einpacken(workerList)
  deploy.returnToDock(workerList)
  return true
end

return deploy
