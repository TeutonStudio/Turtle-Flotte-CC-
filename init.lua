-- Zweck: Einmaliger Bootstrap-Installer fuer eine Flotte-Rolle.
-- Erwartet: http, fs, textutils, shell, os; RAW_BASE_URL/MANIFEST_URL muessen angepasst werden.

local init = {}

init.RAW_BASE_URL = "https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master/"
init.MANIFEST_URL = init.RAW_BASE_URL .. "manifest.json"

local function get(url)
  local ok, handleOrErr = pcall(http.get, url)
  if not ok or not handleOrErr then return nil, "Download fehlgeschlagen: " .. tostring(url) end
  local data = handleOrErr.readAll()
  handleOrErr.close()
  return data
end

local function writeFile(path, data)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local h = fs.open(path, "w")
  if not h then return false, "Kann Datei nicht schreiben: " .. path end
  h.write(data or "")
  h.close()
  return true
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

local function chooseRole()
  print("[1] Taschencomputer")
  print("[2] Koordinator")
  print("[3] Arbeiter")
  if _G.write then _G.write("Rolle: ") else term.write("Rolle: ") end
  local choice = read()
  if choice == "1" then return "taschencomputer" end
  if choice == "2" then return "koordinator" end
  if choice == "3" then return "arbeiter" end
  return nil, "Ungueltige Auswahl"
end

local function normalizeEntry(entry, role)
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

local function installFile(entry, role)
  local src, dest, entryErr = normalizeEntry(entry, role)
  if not src then return false, entryErr end
  local data, err = get(init.RAW_BASE_URL .. src)
  if not data then return false, err end
  return writeFile(dest, data)
end

function init.install()
  if not http or not http.get then print("HTTP API ist nicht aktiviert."); return false end
  local raw, err = get(init.MANIFEST_URL)
  if not raw then print(err); return false end
  local manifest, parseErr = parseManifest(raw)
  if not manifest then print(parseErr); return false end
  local role, roleErr = chooseRole()
  if not role then print(roleErr); return false end
  local files = {}
  for _, path in ipairs(manifest.common or {}) do files[#files + 1] = path end
  for _, path in ipairs((manifest.roles and manifest.roles[role]) or {}) do files[#files + 1] = path end
  for _, entry in ipairs(files) do
    local src, dest = normalizeEntry(entry, role)
    print("Lade " .. tostring(src) .. " -> " .. tostring(dest))
    local ok, fileErr = installFile(entry, role)
    if not ok then print(fileErr); return false end
  end
  local startupPath = manifest.startup and manifest.startup[role]
  if startupPath then
    local _, startupDest = normalizeEntry(startupPath, role)
    startupDest = startupDest or startupPath
    if not fs.exists(startupDest) then print("Startup-Datei fehlt im Manifest: " .. tostring(startupDest)); return false end
    if fs.exists("startup.lua") then fs.delete("startup.lua") end
    fs.copy(startupDest, "startup.lua")
  elseif role == "taschencomputer" and fs.exists("startup.lua") then
    fs.delete("startup.lua")
  end
  print("Flotte installiert als Rolle: " .. role)
  local running = shell and shell.getRunningProgram and shell.getRunningProgram()
  if running and fs.exists(running) then fs.delete(running) end
  os.reboot()
  return true
end

init.install()
return init
