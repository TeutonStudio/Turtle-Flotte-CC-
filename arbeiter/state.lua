-- Zweck: Zustandsautomat fuer Arbeiter-Turtles mit Registrierung und Task-Ausfuehrung.
-- Erwartet: common/protocol.lua, common/vec3.lua, turtle, gps, os.

local protocol = dofile("common/protocol.lua")
local vec3 = dofile("common/vec3.lua")

local state = {}
state.FUEL_THRESHOLD = 250
state.GPS_TIMEOUT = 2
state.MOVE_GUARD = 4096

local koordinatorId = nil
local currentTask = nil
local status = "BOOT"
local berufName = "spitzhacke"
local beruf = nil
local lastTaskPos = nil
local heading = nil

local function equippedNames()
  local okL, left = pcall(turtle.getEquippedLeft)
  local okR, right = pcall(turtle.getEquippedRight)
  local names = {}
  if okL and type(left) == "table" and left.name then names[#names + 1] = left.name end
  if okR and type(right) == "table" and right.name then names[#names + 1] = right.name end
  return names
end

local function nameContains(name, needle)
  local lower = string.lower(tostring(name or ""))
  return string.find(lower, needle, 1, true) ~= nil
end

function state.detectBeruf()
  local names = equippedNames()
  for _, name in ipairs(names) do
    if nameContains(name, "pickaxe") then return "spitzhacke", names end
  end
  for _, name in ipairs(names) do
    if nameContains(name, "shovel") or nameContains(name, "spade") then return "schaufel", names end
  end
  for _, name in ipairs(names) do
    if nameContains(name, "crafting") or nameContains(name, "workbench") or nameContains(name, "crafting_table") then return "werkbank", names end
  end
  for _, name in ipairs(names) do
    if nameContains(name, "axe") then return "axt", names end
  end
  return "spitzhacke"
end

local function loadBeruf(name)
  local path = "arbeiter/beruf/" .. name .. ".lua"
  if fs.exists(path) then return dofile(path) end
  return dofile("arbeiter/beruf/spitzhacke.lua")
end

local function pos()
  local p = vec3.fromGps(state.GPS_TIMEOUT)
  return p
end

local function allSlotsFull()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return false end
  end
  return true
end

function state.sendStatus(extra)
  local payload = extra or {}
  payload.id = os.getComputerID()
  payload.beruf = berufName
  payload.status = status
  payload.position = pos()
  payload.fuel = turtle.getFuelLevel()
  payload.currentTask = currentTask and currentTask.id or nil
  if koordinatorId then protocol.send(koordinatorId, protocol.WORKER_STATUS, payload) end
end

local function waitFor(kind)
  while true do
    local _, msg = protocol.receive(nil, function(m) return m.type == kind end)
    if msg then return msg end
  end
end

local function waitForFuelInstruction(timeout)
  local _, msg = protocol.receive(timeout or 10, function(m)
    return m.type == protocol.REFUEL or m.type == protocol.RETURN_TO_DOCK or m.type == protocol.RETURN_TO_STORAGE
  end)
  return msg
end

function state.checkNeeds()
  state.refuelFromInventory()
  if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < state.FUEL_THRESHOLD then
    status = "problem"
    protocol.send(koordinatorId, protocol.WORKER_PROBLEM, { art = "fuel", position = pos() })
    local before = turtle.getFuelLevel()
    local msg = waitForFuelInstruction(10)
    if not msg then
      return false, "Fuel zu niedrig und kein Nachschub/Rueckkehrbefehl erhalten"
    end
    if msg.type == protocol.RETURN_TO_DOCK then
      local dockPos = msg.payload and msg.payload.dockPos
      if vec3.isVec(dockPos) then state.goTo(dockPos) end
      protocol.send(koordinatorId, protocol.READY_AT_DOCK, { position = pos() })
      return false, "Fuel-Problem: Rueckkehr zum Dock angefordert"
    end
    if msg.type == protocol.RETURN_TO_STORAGE then
      state.unloadAtStorage(msg.payload and msg.payload.lager)
    end
    state.refuelFromInventory()
    local after = turtle.getFuelLevel()
    if after ~= "unlimited" and before ~= "unlimited" and after <= before then
      protocol.send(koordinatorId, protocol.WORKER_PROBLEM, { art = "fuel", position = pos(), error = "REFUEL erhalten, aber kein lokaler Fuel verfuegbar" })
      status = "problem"
      return false, "Fuel weiterhin zu niedrig"
    end
    status = "ARBEITEN"
  end
  if allSlotsFull() then
    status = "problem"
    protocol.send(koordinatorId, protocol.WORKER_PROBLEM, { art = "inventory_full", position = pos() })
    local msg = waitFor(protocol.RETURN_TO_STORAGE)
    state.unloadAtStorage(msg.payload and msg.payload.lager)
    status = "ARBEITEN"
  end
  return true
end

local function forwardDig()
  if beruf and beruf.digForward then
    local digOk, digErr = beruf.digForward()
    if digOk == false and turtle.detect() then return false, digErr or "Graben nach vorne fehlgeschlagen" end
  else
    local digOk, digErr = turtle.dig()
    if digOk == false and turtle.detect() then return false, digErr or "Graben nach vorne fehlgeschlagen" end
  end
  local ok = turtle.forward()
  if not ok then return false, "Vorwaertsbewegung blockiert" end
  local needsOk, needsErr = state.checkNeeds()
  if not needsOk then return false, needsErr end
  return true
end

local function calibrateHeading()
  if heading then return heading end
  local before = pos()
  if not before then return nil, "GPS vor Kalibrierung fehlgeschlagen" end
  if not forwardDig() then return nil, "Kann fuer Richtungskalibrierung nicht vorfahren" end
  local after = pos()
  turtle.back()
  if not after then return nil, "GPS nach Kalibrierung fehlgeschlagen" end
  local dx, dz = after.x - before.x, after.z - before.z
  if dx == 1 then heading = "east"
  elseif dx == -1 then heading = "west"
  elseif dz == 1 then heading = "south"
  elseif dz == -1 then heading = "north"
  else return nil, "Richtung nicht bestimmbar" end
  return heading
end

local function turnLeftHeading()
  turtle.turnLeft()
  if heading == "north" then heading = "west"
  elseif heading == "west" then heading = "south"
  elseif heading == "south" then heading = "east"
  elseif heading == "east" then heading = "north" end
end

local function turnRightHeading()
  turtle.turnRight()
  if heading == "north" then heading = "east"
  elseif heading == "east" then heading = "south"
  elseif heading == "south" then heading = "west"
  elseif heading == "west" then heading = "north" end
end

local function turnTo(wanted)
  local ok, err = calibrateHeading()
  if not ok then return false, err end
  local guard = 0
  while heading ~= wanted and guard < 4 do
    turnRightHeading()
    guard = guard + 1
  end
  return heading == wanted
end

local function moveAxis(axis, targetValue)
  local guard = 0
  while guard < state.MOVE_GUARD do
    local p, err = pos()
    if not p then return false, err end
    if p[axis] == targetValue then return true end
    local wanted
    if axis == "x" then wanted = (targetValue > p.x) and "east" or "west" end
    if axis == "z" then wanted = (targetValue > p.z) and "south" or "north" end
    local turned, turnErr = turnTo(wanted)
    if not turned then return false, turnErr or "Drehung fehlgeschlagen" end
    if not forwardDig() then return false, "Vorwaertsbewegung blockiert" end
    guard = guard + 1
  end
  return false, "Achsenfahrt abgebrochen"
end

local function moveVertical(targetY)
  local guard = 0
  while guard < state.MOVE_GUARD do
    local p, err = pos()
    if not p then return false, err end
    if p.y == targetY then return true end
    if p.y < targetY then
      if beruf and beruf.digUp then
        local digOk, digErr = beruf.digUp()
        if digOk == false and turtle.detectUp() then return false, digErr or "Graben nach oben fehlgeschlagen" end
      else
        local digOk, digErr = turtle.digUp()
        if digOk == false and turtle.detectUp() then return false, digErr or "Graben nach oben fehlgeschlagen" end
      end
      if not turtle.up() then return false, "Aufstieg blockiert" end
    else
      if beruf and beruf.digDown then
        local digOk, digErr = beruf.digDown()
        if digOk == false and turtle.detectDown() then return false, digErr or "Graben nach unten fehlgeschlagen" end
      else
        local digOk, digErr = turtle.digDown()
        if digOk == false and turtle.detectDown() then return false, digErr or "Graben nach unten fehlgeschlagen" end
      end
      if not turtle.down() then return false, "Abstieg blockiert" end
    end
    local needsOk, needsErr = state.checkNeeds()
    if not needsOk then return false, needsErr end
    guard = guard + 1
  end
  return false, "Bewegungsabbruch durch Sicherheitszaehler"
end

function state.goTo(target)
  if not vec3.isVec(target) then return false, "Ziel ist kein vec3" end
  local ok, err = moveVertical(target.y)
  if not ok then return false, err end
  ok, err = moveAxis("x", target.x)
  if not ok then return false, err end
  ok, err = moveAxis("z", target.z)
  if not ok then return false, err end
  return true
end

function state.mineLayer(task)
  local p = task.params
  if not p then return false, "Task-Parameter fehlen" end
  local ok, err = state.goTo({ x = p.xMin, y = p.y, z = p.zMin })
  if not ok then return false, err end
  for x = p.xMin, p.xMax do
    local span = p.zMax - p.zMin
    for _ = 1, span do
      local ok, err = forwardDig()
      if not ok then return false, err end
    end
    if x < p.xMax then
      if (x % 2) == 0 then
        turtle.turnLeft()
        local okMove, moveErr = forwardDig()
        if not okMove then return false, moveErr end
        turtle.turnLeft()
      else
        turtle.turnRight()
        local okMove, moveErr = forwardDig()
        if not okMove then return false, moveErr end
        turtle.turnRight()
      end
    end
  end
  lastTaskPos = pos()
  return true
end

function state.unloadAtStorage(lager)
  if vec3.isVec(lager) then state.goTo(lager) end
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.getItemCount(slot) > 0 then turtle.drop() end
  end
  if lastTaskPos then state.goTo(lastTaskPos) end
end

function state.register()
  status = "REGISTER"
  local names
  berufName, names = state.detectBeruf()
  beruf = loadBeruf(berufName)
  print("Equipment: " .. table.concat(names or {}, ", "))
  print("Beruf erkannt: " .. tostring(berufName))
  state.refuelFromInventory()
  protocol.broadcast(protocol.WORKER_REGISTER, {
    id = os.getComputerID(),
    beruf = berufName,
    position = pos(),
    fuel = turtle.getFuelLevel(),
  })
  local sender, msg = protocol.receive(10, function(m) return m.type == protocol.TASK_ASSIGN or m.type == protocol.RETURN_TO_DOCK end)
  if sender then koordinatorId = sender end
  return msg
end

function state.handleTask(task)
  currentTask = task
  status = "ARBEITEN"
  protocol.send(koordinatorId, protocol.WORKER_STATUS, { status = "busy", currentTask = task.id, position = pos() })
  local ok, err = false, "Unbekannter Task"
  if task.typ == "mine_layer" then ok, err = state.mineLayer(task) end
  if ok then
    protocol.send(koordinatorId, protocol.TASK_DONE, { taskId = task.id, position = pos() })
  else
    protocol.send(koordinatorId, protocol.TASK_FAILED, { taskId = task.id, error = err, position = pos() })
  end
  currentTask = nil
  status = "IDLE"
end

function state.loop(initialMsg)
  local msg = initialMsg
  status = "IDLE"
  while true do
    if not msg then
      local sender, received = protocol.receive(nil)
      if sender and not koordinatorId then koordinatorId = sender end
      msg = received
    end
    if msg and msg.type == protocol.TASK_ASSIGN then
      koordinatorId = msg.from
      state.handleTask(msg.payload)
    elseif msg and msg.type == protocol.RETURN_TO_DOCK then
      koordinatorId = msg.from
      status = "RUECKKEHR"
      local dockPos = msg.payload and msg.payload.dockPos
      if vec3.isVec(dockPos) then state.goTo(dockPos) end
      protocol.send(koordinatorId, protocol.READY_AT_DOCK, { position = pos() })
      return
    elseif msg and msg.type == protocol.REFUEL then
      state.refuelFromInventory()
    end
    msg = nil
  end
end

function state.refuelFromInventory()
  if not turtle or not turtle.refuel then return false, "Turtle API fehlt" end
  if turtle.getFuelLevel() == "unlimited" then return true end
  local changed = false
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      local ok, canFuel = pcall(turtle.refuel, 0)
      if ok and canFuel then
        pcall(turtle.refuel)
        changed = true
      end
    end
  end
  return changed
end

function state.main()
  if not turtle then print("Arbeiter braucht Turtle API"); return false end
  local initial = state.register()
  state.loop(initial)
  return true
end

return state
