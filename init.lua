-- init.lua
-- Bootstrap fuer Teuton-Fleet v5.

local DEFAULT_BASE_URL = "https://raw.githubusercontent.com/TeutonStudio/Turtle-Flotte-CC-/master"
local VERSION = "5.0.0"

local function lib(name) return { src = "Bibliothek/" .. name, dst = name } end
local function script(name) return { src = "Skripte/" .. name, dst = name } end

local COMMON_V5 = {
    lib("fleet_common.lua"),
    lib("vec3.lua"),
    lib("direction.lua"),
    lib("equipment.lua"),
    lib("inventory.lua"),
    lib("task_queue.lua"),
    lib("protocol.lua"),
    lib("nav2.lua"),
    lib("safety.lua"),
}

local WORKER_FILES = {
    { src = "update.lua", dst = "update" },
    COMMON_V5[1], COMMON_V5[2], COMMON_V5[3], COMMON_V5[4], COMMON_V5[5],
    COMMON_V5[6], COMMON_V5[7], COMMON_V5[8], COMMON_V5[9],
    lib("worker_runtime.lua"),
    script("worker.lua"),
}

local ROLE_FILES = {
    koordinator = {
        { src = "update.lua", dst = "update" },
        COMMON_V5[1], COMMON_V5[2], COMMON_V5[3], COMMON_V5[4], COMMON_V5[5],
        COMMON_V5[6], COMMON_V5[7], COMMON_V5[8], COMMON_V5[9],
        lib("terrain.lua"),
        lib("report.lua"),
        lib("coordinator_brain.lua"),
        script("koordinator.lua"),
    },
    worker = WORKER_FILES,
    bergbau = WORKER_FILES,
    graben = WORKER_FILES,
    handwerk = WORKER_FILES,
    holzfaeller = WORKER_FILES,
    pocket = {
        { src = "update.lua", dst = "update" },
        script("flotte.lua"),
    },
}

local function usage()
    print("init koordinator <gruppe> [id] [base_url]")
    print("init worker <gruppe> [id] [koordinator] [base_url]")
    print("init <bergbau|graben|handwerk|holzfaeller> <gruppe> [id] [koordinator] [base_url]")
    print("init pocket <gruppe> <koordinator> [base_url]")
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
    else
        local example = path:gsub("%.lua$", ".example.lua")
        write(example, content)
        print("Bestehende Config behalten: " .. path)
        print("Neue Beispiel-Config geschrieben: " .. example)
    end
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
    local function literal(value)
        if value == nil then return "nil" end
        return string.format("%q", value)
    end

    if role == "koordinator" then
        return string.format([[return {
    group = %s,
    id = %s,
    role = "coordinator",
    protocolPrefix = "teuton_fleet_v2",
    statusInterval = 5,
    reportDir = "berichte",
    initChest = nil,
    start = nil,
    facing = nil,
}]], literal(group), literal(id or "basis_" .. tostring(os.getComputerID())))
    end

    if role == "pocket" then
        return string.format([[return {
    group = %s,
    coordinator = %s,
    protocolPrefix = "teuton_fleet_v2",
    timeout = 60,
}]], literal(group), literal(coordinator))
    end

    return string.format([[return {
    group = %s,
    id = %s,
    role = "worker",
    coordinator = %s,
    protocolPrefix = "teuton_fleet_v2",
    statusInterval = 5,
    start = nil,
    facing = nil,
}]], literal(group), literal(id or tostring(os.getComputerID())), literal(coordinator))
end

local args = { ... }
local role = args[1]
local group = args[2]
if not role or not ROLE_FILES[role] or not group then usage(); return end

local id = args[3]
local coordinator = args[4]
local baseUrl = args[5] or DEFAULT_BASE_URL

if role == "koordinator" then
    baseUrl = args[4] or DEFAULT_BASE_URL
elseif role == "pocket" then
    coordinator = args[3]
    baseUrl = args[4] or DEFAULT_BASE_URL
    if not coordinator then usage(); return end
elseif role == "worker" or role == "bergbau" or role == "graben" or role == "handwerk" or role == "holzfaeller" then
    baseUrl = args[5] or DEFAULT_BASE_URL
end

print("Teuton-Fleet Init " .. VERSION .. " fuer " .. role)
for _, file in ipairs(ROLE_FILES[role]) do download(baseUrl, file) end

if role == "pocket" then
    writeConfig("fleet_pocket_config.lua", configFor(role, group, id, coordinator))
else
    writeConfig("fleet_config.lua", configFor(role == "koordinator" and role or "worker", group, id, coordinator))
end

if role == "koordinator" then
    write("startup.lua", 'shell.run("koordinator")\n')
elseif role ~= "pocket" then
    write("startup.lua", 'shell.run("worker")\n')
end

print("Init fertig. v5 minimiert Config: group ist Pflicht, id/initChest/start/facing sind optional soweit automatisch ermittelbar.")
