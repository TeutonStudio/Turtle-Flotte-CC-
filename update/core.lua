-- Zweck: Gemeinsames rollenbasiertes Update fuer Flotte-Installationen.
-- Erwartet: http, fs, textutils, shell, os; liest manifest.json aus dem Repository.

local core = {}

core.RAW_BASE_URL = "https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master/"
core.MANIFEST_URL = core.RAW_BASE_URL .. "manifest.json"

local function httpGet(url)
  local ok, handleOrErr = pcall(http.get, url)
  if not ok or not handleOrErr then return nil, "Download fehlgeschlagen: " .. tostring(url) end
  local data = handleOrErr.readAll()
  handleOrErr.close()
  return data
end

local function parseManifest(raw)
  if textutils.unserializeJSON then
    local ok, data = pcall(textutils.unserializeJSON, raw)
    if ok and type(data) == "table" then return data end
  end
  local ok, data = pcall(textutils.unserialize, raw)
  if ok and type(data) == "table" then return data end
  return nil, "Manifest ist nicht lesbar"
end

local function ensureDirFor(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function writeFile(path, data)
  ensureDirFor(path)
  local h = fs.open(path, "w")
  if not h then return false, "Kann Datei nicht schreiben: " .. tostring(path) end
  h.write(data or "")
  h.close()
  return true
end

function core.normalizeEntry(entry, role)
  if type(entry) == "string" then
    if role == "taschencomputer" and string.sub(entry, 1, 7) == "common/" then
      return entry, "Flotte/" .. entry
    end
    return entry, entry
  end
  if type(entry) == "table" and type(entry.src) == "string" then
    return entry.src, entry.dest or entry.src
  end
  return nil, nil, "Ungueltiger Manifest-Eintrag"
end

function core.collectFiles(manifest, role)
  local files = {}
  for _, entry in ipairs(manifest.common or {}) do files[#files + 1] = entry end
  for _, entry in ipairs((manifest.roles and manifest.roles[role]) or {}) do files[#files + 1] = entry end
  return files
end

local function safeDelete(path)
  if type(path) == "string" and path ~= "" and fs.exists(path) then
    fs.delete(path)
    return true
  end
  return false
end

local function removePocketStartupIfManaged()
  if not fs.exists("startup.lua") then return false end
  local h = fs.open("startup.lua", "r")
  local data = h and h.readAll() or ""
  if h then h.close() end
  local lower = string.lower(data or "")
  if string.find(lower, "flotte") or string.find(lower, "taschencomputer") then
    fs.delete("startup.lua")
    return true
  end
  return false
end

function core.downloadFile(entry, role)
  local src, dest, err = core.normalizeEntry(entry, role)
  if not src then return false, err end
  local data, getErr = httpGet(core.RAW_BASE_URL .. src)
  if not data then return false, getErr end
  local ok, writeErr = writeFile(dest, data)
  if not ok then return false, writeErr end
  return true, src, dest
end

function core.applyStartup(manifest, role)
  local startup = manifest.startup and manifest.startup[role]
  if startup then
    local _, dest = core.normalizeEntry(startup, role)
    dest = dest or startup
    if not fs.exists(dest) then return false, "Startup-Datei fehlt: " .. tostring(dest) end
    if fs.exists("startup.lua") then fs.delete("startup.lua") end
    fs.copy(dest, "startup.lua")
    return true, "startup.lua gesetzt"
  end
  if role == "taschencomputer" then
    removePocketStartupIfManaged()
  end
  return true, "keine startup.lua fuer diese Rolle"
end

function core.run(role)
  if not http or not http.get then print("HTTP API ist nicht aktiviert."); return false end
  if type(role) ~= "string" then print("Update-Rolle fehlt."); return false end

  local raw, err = httpGet(core.MANIFEST_URL)
  if not raw then print(err); return false end
  local manifest, parseErr = parseManifest(raw)
  if not manifest then print(parseErr); return false end

  local cfg = manifest.update and manifest.update[role] or {}
  print("Flotte-Update fuer Rolle: " .. role)

  local removed = 0
  for _, path in ipairs(cfg.managed or {}) do
    if safeDelete(path) then removed = removed + 1 end
  end
  if cfg.removeStartup then
    if removePocketStartupIfManaged() then removed = removed + 1 end
  end

  local downloaded = 0
  for _, entry in ipairs(core.collectFiles(manifest, role)) do
    local ok, src, dest = core.downloadFile(entry, role)
    if not ok then print(src or dest); return false end
    downloaded = downloaded + 1
    print("Geladen: " .. tostring(src) .. " -> " .. tostring(dest))
  end

  local startupOk, startupMsg = core.applyStartup(manifest, role)
  if not startupOk then print(startupMsg); return false end

  print("Update fertig. Geloescht: " .. tostring(removed) .. ", geladen: " .. tostring(downloaded) .. ".")
  print(startupMsg)

  if cfg.reboot then
    print("Neustart...")
    sleep(1)
    os.reboot()
  end
  return true
end

return core
