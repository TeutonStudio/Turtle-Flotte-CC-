-- Zweck: Planung und Basisalgorithmen fuer Abbau-Jobs und Layer-Subtasks.
-- Erwartet: common/vec3.lua; zur Laufzeit optional turtle/gps fuer Pionierfunktionen.

local vec3 = dofile("common/vec3.lua")

local abbau = {}
abbau.WORLD_MIN_Y = -64
abbau.WORLD_MAX_Y = 320
abbau.SURFACE_SCAN_LIMIT = 40

function abbau.normalize(von, bis)
  if not vec3.isVec(von) or not vec3.isVec(bis) then return nil, "von/bis muessen vec3 sein" end
  local box = {
    xMin = math.min(von.x, bis.x), xMax = math.max(von.x, bis.x),
    yTop = math.max(von.y, bis.y), yBottom = math.min(von.y, bis.y),
    zMin = math.min(von.z, bis.z), zMax = math.max(von.z, bis.z),
  }
  if box.yBottom < abbau.WORLD_MIN_Y or box.yTop > abbau.WORLD_MAX_Y then
    return nil, "Y ausserhalb der Weltgrenzen"
  end
  return box
end

function abbau.planeSubtasks(job)
  local box, err = abbau.normalize(job.params.von, job.params.bis)
  if not box then return nil, err end
  local tasks = {}
  for y = box.yTop, box.yBottom, -1 do
    tasks[#tasks + 1] = {
      id = job.id .. "#layer" .. tostring(y),
      jobId = job.id,
      typ = "mine_layer",
      params = { y = y, xMin = box.xMin, xMax = box.xMax, zMin = box.zMin, zMax = box.zMax },
      status = "pending",
      workerId = nil,
      zugewiesenAm = nil,
      abgeschlossenAm = nil,
      fehler = nil,
    }
  end
  return tasks
end

function abbau.findSurfaceY(maxScan)
  maxScan = maxScan or abbau.SURFACE_SCAN_LIMIT
  if not turtle or not gps then return nil, "Turtle/GPS API fehlt" end
  local steps = 0
  while turtle.detectUp() and steps < maxScan do
    turtle.digUp()
    if not turtle.up() then break end
    steps = steps + 1
  end
  local ok, x, y = pcall(gps.locate, 2)
  if not ok or not x then return nil, "GPS-Position nicht verfuegbar" end
  return math.floor(y + 0.5)
end

function abbau.bestimmeEinstiegsY(box)
  local surfaceY, err = abbau.findSurfaceY()
  if not surfaceY then return nil, err end
  if box.yTop > surfaceY then return box.yTop end
  return surfaceY
end

function abbau.grabeTreppeAb(zielY)
  local guard = 0
  while guard < (abbau.WORLD_MAX_Y - abbau.WORLD_MIN_Y + 1) do
    local ok, x, y = pcall(gps.locate, 2)
    if not ok or not x then return false, "GPS-Position nicht verfuegbar" end
    if y <= zielY then return true end
    turtle.dig()
    turtle.forward()
    turtle.digDown()
    if not turtle.down() then return false, "Kann nicht absteigen" end
    guard = guard + 1
  end
  return false, "Treppenabbruch durch Y-Sicherheitsgrenze"
end

function abbau.grabeTreppeAuf(zielY)
  local guard = 0
  while guard < (abbau.WORLD_MAX_Y - abbau.WORLD_MIN_Y + 1) do
    local ok, x, y = pcall(gps.locate, 2)
    if not ok or not x then return false, "GPS-Position nicht verfuegbar" end
    if y >= zielY then return true end
    turtle.digUp()
    if not turtle.up() then return false, "Kann nicht aufsteigen" end
    turtle.back()
    guard = guard + 1
  end
  return false, "Treppenabbruch durch Y-Sicherheitsgrenze"
end

return abbau
