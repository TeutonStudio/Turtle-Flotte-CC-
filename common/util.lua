-- Zweck: Kleine Hilfsfunktionen fuer IDs, Dateien, Logging und Tabellen.
-- Erwartet: CC:Tweaked APIs fs, textutils, os; keine globalen Projektmodule.

local util = {}

local ID_RANDOM_MAX = 99999

function util.now()
  if os and os.epoch then
    local ok, value = pcall(os.epoch, "utc")
    if ok and value then return value end
  end
  return math.floor(os.clock() * 1000)
end

function util.computerId()
  if os and os.getComputerID then
    local ok, value = pcall(os.getComputerID)
    if ok and value then return value end
  end
  return 0
end

function util.newId(prefix)
  local base = tostring(prefix or util.computerId())
  return base .. "-" .. tostring(util.now()) .. "-" .. tostring(math.random(1, ID_RANDOM_MAX))
end

function util.jobId()
  return tostring(util.computerId()) .. "-" .. tostring(util.now())
end

function util.log(level, message)
  local line = "[" .. tostring(level or "INFO") .. "] " .. tostring(message or "")
  print(line)
  return line
end

function util.ensureDirFor(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

function util.readFile(path)
  if not fs.exists(path) then return nil, "Datei fehlt: " .. path end
  local h = fs.open(path, "r")
  if not h then return nil, "Datei nicht lesbar: " .. path end
  local data = h.readAll()
  h.close()
  return data
end

function util.writeFileAtomic(path, data)
  util.ensureDirFor(path)
  local tmp = path .. ".tmp"
  if fs.exists(tmp) then fs.delete(tmp) end
  local h = fs.open(tmp, "w")
  if not h then return false, "Tempdatei nicht schreibbar: " .. tmp end
  h.write(data or "")
  h.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
  return true
end

function util.serialize(value)
  local ok, encoded = pcall(textutils.serialize, value)
  if ok then return encoded end
  return nil, encoded
end

function util.unserialize(value)
  if type(value) ~= "string" then return nil, "Kein String" end
  local ok, decoded = pcall(textutils.unserialize, value)
  if ok then return decoded end
  return nil, decoded
end

function util.toJson(value)
  if textutils.serializeJSON then
    local ok, encoded = pcall(textutils.serializeJSON, value)
    if ok then return encoded end
  end
  return textutils.serialize(value)
end

function util.fromJson(value)
  if type(value) ~= "string" then return nil, "Kein String" end
  if textutils.unserializeJSON then
    local ok, decoded = pcall(textutils.unserializeJSON, value)
    if ok then return decoded end
  end
  return textutils.unserialize(value)
end

function util.shallowCopy(t)
  local out = {}
  if type(t) ~= "table" then return out end
  for k, v in pairs(t) do out[k] = v end
  return out
end

function util.count(t)
  local n = 0
  if type(t) == "table" then
    for _ in pairs(t) do n = n + 1 end
  end
  return n
end

return util
