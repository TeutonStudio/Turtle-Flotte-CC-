-- init.lua
-- Bootstrap fuer Teuton-Fleet. Dieses Skript selbst per wget von GitHub laden,
-- danach laedt es die benoetigten Rollen-Dateien nach.

local DEFAULT_BASE_URL = "https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master"
local VERSION = "4.1.0"

local function lib(name) return { src = "Bibliothek/" .. name, dst = name } end
local function script(name) return { src = "Skripte/" .. name, dst = name } end

local ROLE_FILES = {
    koordinator = {
        { src = "update.lua", dst = "update" }, lib("fleet_common.lua"), lib("nav.lua"), script("koordinator.lua"),
    },
    bergbau = {
        { src = "update.lua", dst = "update" }, lib("fleet_common.lua"), lib("nav.lua"), lib("worker_core.lua"), script("worker_bergbau.lua"),
    },
    graben = {
        { src = "update.lua", dst = "update" }, lib("fleet_common.lua"), lib("nav.lua"), lib("worker_core.lua"), script("worker_graben.lua"),
    },
    handwerk = {
        { src = "update.lua", dst = "update" }, lib("fleet_common.lua"), lib("nav.lua"), lib("worker_core.lua"), script("worker_handwerk.lua"),
        lib("recipes.lua"), lib("crafting_lib.lua"),
    },
    holzfaeller = {
        { src = "update.lua", dst = "update" }, lib("fleet_common.lua"), lib("nav.lua"), lib("worker_core.lua"), script("worker_holzfaeller.lua"),
    },
    pocket = {
        { src = "update.lua", dst = "update" }, script("flotte.lua"),
    },
}

local WORKER_SCRIPT = {
    bergbau = "worker_bergbau",
    graben = "worker_graben",
    handwerk = "worker_handwerk",
    holzfaeller = "worker_holzfaeller",
}

local function usage()
    print("init koordinator <gruppe> <id> [base_url]")
    print("init <worker-rolle> <gruppe> <id> <koordinator> [base_url]")
    print("init pocket <gruppe> <koordinator> [base_url]")
    print("Rollen: koordinator, bergbau, graben, handwerk, holzfaeller, pocket")
    print("Beispiele:")
    print("  init koordinator bergwerk_01 basis_01")
    print("  init bergbau bergwerk_01 bergbau_01 basis_01")
    print("  init pocket bergwerk_01 pocket basis_01")
end

local function write(path, content)
    local h = fs.open(path, "w")
    h.write(content)
    h.close()
end

local function writeConfig(path, content)
    if not fs.exists(path) then
        write(path, content)
        print("Config geschrieben: " .. path)
        return path
    end

    local example = path:gsub("%.lua$", ".example.lua")
    if example == path then example = path .. ".example" end
    write(example, content)
    print("Bestehende Config behalten: " .. path)
    print("Neue Beispiel-Config geschrieben: " .. example)
    return example
end

local function download(baseUrl, file)
    local src = type(file) == "table" and file.src or file
    local dst = type(file) == "table" and file.dst or file
    local url = baseUrl:gsub("/$", "") .. "/" .. src
    if fs.exists(dst) then fs.delete(dst) end
    print("Lade " .. src .. " -> " .. dst)
    local ok = shell.run("wget", url, dst)
    if not ok or not fs.exists(dst) then error("Download fehlgeschlagen: " .. url) end
end

local function configFor(role, group, id, coordinator)
    if role == "koordinator" then
        return string.format([[return {
    group = %q,
    id = %q,
    role = "coordinator",
    protocolPrefix = "teuton_fleet_v2",
    chestSide = "back",
    deploySide = "left",
    deploySides = { "left", "right", "front" },
    deployCount = 3,
    deployPause = 1.5,
    deployWait = 8,
    autoDeploy = true,
    workerFuelItems = 64,
    coordinatorFuelReserveItems = 64,
    searchPullLimit = 32,
    statusInterval = 5,
    reportDir = "berichte",
    abbauRole = "bergbau",
    start = nil,
    facing = nil,
    initChest = nil,
    chat = { enabled = true },
    workers = {},
}]], group, id)
    end

    if role == "pocket" then
        return string.format([[return {
    group = %q,
    coordinator = %q,
    protocolPrefix = "teuton_fleet_v2",
    timeout = 60,
}]], group, coordinator)
    end

    return string.format([[return {
    group = %q,
    id = %q,
    role = "worker",
    workerRole = %q,
    coordinator = %q,
    protocolPrefix = "teuton_fleet_v2",
    statusInterval = 5,
    reportItems = false,
    minFuel = 500,
    serviceFuelThreshold = 100,
}]], group, id, role, coordinator)
end

local args = { ... }
local role = args[1]
local group = args[2]
local id = args[3]
local coordinator = args[4]
local baseUrl = args[5] or DEFAULT_BASE_URL

if not role or not ROLE_FILES[role] or not group or not id then usage(); return end
if role == "koordinator" then
    coordinator = nil
    baseUrl = args[4] or DEFAULT_BASE_URL
elseif role == "pocket" then
    coordinator = id
    baseUrl = args[4] or DEFAULT_BASE_URL
else
    if not coordinator then usage(); return end
    baseUrl = args[5] or DEFAULT_BASE_URL
end

print("Teuton-Fleet Init " .. VERSION .. " fuer " .. role)
for _, file in ipairs(ROLE_FILES[role]) do download(baseUrl, file) end

if role == "pocket" then
    writeConfig("fleet_pocket_config.lua", configFor(role, group, id, coordinator))
else
    writeConfig("fleet_config.lua", configFor(role, group, id, coordinator))
end

if role == "koordinator" then
    write("startup.lua", 'shell.run("koordinator")\n')
elseif role ~= "pocket" then
    write("startup.lua", 'shell.run("' .. WORKER_SCRIPT[role] .. '")\n')
end

print("Init fertig. Bitte fleet_config.lua pruefen, besonders start/facing/initChest beim Koordinator.")
