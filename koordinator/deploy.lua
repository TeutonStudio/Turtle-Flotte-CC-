-- Zweck: Arbeiter aus Personal Chest auspacken und nach Jobende wieder einpacken.
-- Erwartet: turtle, gps, common/vec3.lua, common/protocol.lua.

local vec3 = dofile("common/vec3.lua")
local protocol = dofile("common/protocol.lua")

local deploy = {}
deploy.DEFAULT_FUEL_DROP = 8
deploy.REGISTER_TIMEOUT = 8

local placedQueue = {}

local function selectAnyItem()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      return true
    end
  end
  return false
end

local function gpsPos()
  return vec3.fromGps(2)
end

function deploy.suckFromChest()
  if not turtle then return false, "Turtle API fehlt" end
  turtle.turnLeft()
  turtle.turnLeft()
  for _ = 1, 16 do turtle.suck() end
  turtle.turnLeft()
  turtle.turnLeft()
  return true
end

local function placeWorkerLeft()
  turtle.turnLeft()
  local ok = selectAnyItem() and turtle.place()
  local pos = nil
  if ok then
    local p = gpsPos()
    if p then pos = { x = p.x - 1, y = p.y, z = p.z } end
    if selectAnyItem() then turtle.drop(deploy.DEFAULT_FUEL_DROP) end
  end
  turtle.turnRight()
  return ok, pos
end

local function placeWorkerRight()
  turtle.turnRight()
  local ok = selectAnyItem() and turtle.place()
  local pos = nil
  if ok then
    local p = gpsPos()
    if p then pos = { x = p.x + 1, y = p.y, z = p.z } end
    if selectAnyItem() then turtle.drop(deploy.DEFAULT_FUEL_DROP) end
  end
  turtle.turnLeft()
  return ok, pos
end

function deploy.auspacken(benoetigt)
  if not turtle then return {}, "Turtle API fehlt" end
  deploy.suckFromChest()
  local placed = {}
  while #placed < (benoetigt or 1) do
    local okL, posL = placeWorkerLeft()
    if okL then placed[#placed + 1] = posL end
    if #placed >= benoetigt then break end
    local okR, posR = placeWorkerRight()
    if okR then placed[#placed + 1] = posR end
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
  turtle.turnLeft()
  turtle.turnLeft()
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.getItemCount(slot) > 0 then turtle.drop() end
  end
  turtle.turnLeft()
  turtle.turnLeft()
  return true
end

function deploy.einpacken(workerList)
  -- Minimaler v1-Einpackpfad: Worker werden zum Dock gerufen; der Koordinator baut nahe Docks ab.
  deploy.returnToDock(workerList)
  return true
end

return deploy
