-- Zweck: Vektor-Hilfsfunktionen fuer GPS-Positionen und Bounding-Boxes.
-- Erwartet: Keine Projektmodule; optional CC:Tweaked vector API.

local vec3 = {}
vec3.INFINITE_DISTANCE = 2147483647

function vec3.new(x, y, z)
  return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

function vec3.isVec(v)
  return type(v) == "table" and type(v.x) == "number" and type(v.y) == "number" and type(v.z) == "number"
end

function vec3.clone(v)
  if not vec3.isVec(v) then return nil end
  return { x = v.x, y = v.y, z = v.z }
end

function vec3.add(a, b)
  if not vec3.isVec(a) or not vec3.isVec(b) then return nil end
  return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

function vec3.sub(a, b)
  if not vec3.isVec(a) or not vec3.isVec(b) then return nil end
  return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

function vec3.manhattan(a, b)
  if not vec3.isVec(a) or not vec3.isVec(b) then return vec3.INFINITE_DISTANCE end
  return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z)
end

function vec3.min(a, b)
  if not vec3.isVec(a) or not vec3.isVec(b) then return nil end
  return { x = math.min(a.x, b.x), y = math.min(a.y, b.y), z = math.min(a.z, b.z) }
end

function vec3.max(a, b)
  if not vec3.isVec(a) or not vec3.isVec(b) then return nil end
  return { x = math.max(a.x, b.x), y = math.max(a.y, b.y), z = math.max(a.z, b.z) }
end

function vec3.equals(a, b)
  return vec3.isVec(a) and vec3.isVec(b) and a.x == b.x and a.y == b.y and a.z == b.z
end

function vec3.fromGps(timeout)
  if not gps or not gps.locate then return nil, "GPS API fehlt" end
  local ok, x, y, z = pcall(gps.locate, timeout or 2)
  if not ok or not x then return nil, "GPS-Position nicht verfuegbar" end
  return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
end

function vec3.toString(v)
  if not vec3.isVec(v) then return "nil" end
  return tostring(v.x) .. "," .. tostring(v.y) .. "," .. tostring(v.z)
end

function vec3.parse(value)
  if type(value) ~= "string" then return nil, "Vektor erwartet" end
  local x, y, z = string.match(value, "^(-?%d+),(-?%d+),(-?%d+)$")
  if not x then return nil, "Vektorformat ist x,y,z" end
  return vec3.new(tonumber(x), tonumber(y), tonumber(z))
end

return vec3
