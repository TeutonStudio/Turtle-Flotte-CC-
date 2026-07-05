-- update.lua
-- Teuton-Fleet v5 Updater: alte Programmdateien loeschen, aktuelle Dateien neu laden.
-- Config-Dateien bleiben erhalten.

local DEFAULT_BASE_URL = "https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master"
local VERSION = "5.0.0"

local function lib(name, dstDir)
    return { src = "Bibliothek/" .. name, dst = (dstDir and (dstDir .. "/") or "") .. name }
end

local function script(name, dstDir)
    return { src = "Skripte/" .. name, dst = (dstDir and (dstDir .. "/") or "") .. name }
end

local COMMON = {
    "fleet_common.lua", "vec3.lua", "direction.lua", "equipment.lua", "inventory.lua",
    "task_queue.lua", "protocol.lua", "nav2.lua", "safety.lua",
}

local function commonFiles(dstDir)
    local out = {}
    for _, name in ipairs(COMMON) do out[#out + 1] = lib(name, dstDir) end
    return out
end

local function appendAll(target, source)
    for _, item in ipairs(source) do target[#target + 1] = item end
end

local function workerFiles(dstDir)
    local files = { { src = "update.lua", dst = (dstDir and (dstDir .. "/") or "") .. "update" } }
    appendAll(files, commonFiles(dstDir))
    files[#files + 1] = lib("worker_runtime.lua", dstDir)
    files[#files + 1] = script("worker.lua", dstDir)
    files[#files + 1] = script("worker_bergbau.lua", dstDir)
    files[#files + 1] = script("worker_graben.lua", dstDir)
    files[#files + 1] = script("worker_holzfaeller.lua", dstDir)
    files[#files + 1] = script("worker_handwerk.lua", dstDir)
    return files
end

local function coordinatorFiles(dstDir)
    local files = { { src = "update.lua", dst = (dstDir and (dstDir .. "/") or "") .. "update" } }
    appendAll(files, commonFiles(dstDir))
    files[#files + 1] = lib("terrain.lua", dstDir)
    files[#files + 1] = lib("report.lua", dstDir)
    files[#files + 1] = lib("coordinator_brain.lua", dstDir)
    files[#files + 1] = script("koordinator.lua", dstDir)
    return files
end

local ROLE_FILES = {
    koordinator = coordinatorFiles(nil),
    worker = workerFiles(nil),
    bergbau = workerFiles(nil),
    graben = workerFiles(nil),
    handwerk = workerFiles(nil),
    holzfaeller = workerFiles(nil),
    pocket = {
        { src = "update.lua", dst = "Flotte/update.lua" },
        script("flotte.lua", "Flotte"),
    },
}

local OLD_FILES = {
    "nav.lua", "worker_core.lua", "recipes.lua", "crafting_lib.lua",
    "worker_bergbau.lua", "worker_graben.lua", "worker_holzfaeller.lua", "worker_handwerk.lua",
    "koordinator.lua", "worker.lua",
    "fleet_common.lua", "vec3.lua", "direction.lua", "equipment.lua", "inventory.lua",
    "task_queue.lua", "protocol.lua", "nav2.lua", "safety.lua", "terrain.lua", "report.lua",
    "worker_runtime.lua", "coordinator_brain.lua",
}

local function usage()
    print("update [rolle] [base_url]")
    print("Rollen: koordinator, worker, bergbau, graben, handwerk, holzfaeller, pocket")
    print("Pocket-Dateien liegen unter Flotte/. Configs werden nicht geloescht.")
end

local function ensureDirFor(path)
    local dir = fs.getDir(path)
    if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function deleteOld(role)
    if role == "pocket" then
        if fs.exists("flotte.lua") then fs.delete("flotte.lua") end
        if fs.exists("flotte") then fs.delete("flotte") end
        if not fs.exists("Flotte") then fs.makeDir("Flotte") end
        if fs.exists("Flotte/flotte.lua") then fs.delete("Flotte/flotte.lua") end
        if fs.exists("Flotte/update.lua") then fs.delete("Flotte/update.lua") end
        return
    end
    for _, path in ipairs(OLD_FILES) do
        if fs.exists(path) then fs.delete(path) end
    end
end

local function download(baseUrl, file)
    local url = baseUrl:gsub("/$", "") .. "/" .. file.src
    ensureDirFor(file.dst)
    local tmp = file.dst .. ".tmp"
    if fs.exists(tmp) then fs.delete(tmp) end
    print("Lade " .. file.src .. " -> " .. file.dst)
    local ok = shell.run("wget", url, tmp)
    if not ok or not fs.exists(tmp) then error("Download fehlgeschlagen: " .. url) end
    if fs.exists(file.dst) then fs.delete(file.dst) end
    fs.move(tmp, file.dst)
end

local function inferRole()
    if fs.exists("Flotte/fleet_pocket_config.lua") or fs.exists("fleet_pocket_config.lua") then return "pocket" end
    if fs.exists("fleet_config.lua") then
        local ok, cfg = pcall(require, "fleet_config")
        if ok and type(cfg) == "table" then
            if cfg.role == "coordinator" then return "koordinator" end
            if cfg.role == "worker" or not cfg.role then return "worker" end
        end
    end
    return nil
end

local args = { ... }
local role = args[1]
local baseUrl = args[2] or DEFAULT_BASE_URL

if role and not ROLE_FILES[role] then baseUrl = role; role = nil end
role = role or inferRole()
if not role or not ROLE_FILES[role] then usage(); return end

print("Teuton-Fleet Update " .. VERSION .. " fuer " .. role)
deleteOld(role)
for _, file in ipairs(ROLE_FILES[role]) do download(baseUrl, file) end
print("Update fertig. Config-Dateien wurden nicht geaendert.")
