-- update.lua
-- Aktualisiert Teuton-Fleet-Programme ohne bestehende Configs zu ueberschreiben.

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

local function usage()
    print("update [rolle] [base_url]")
    print("Rollen: koordinator, bergbau, graben, handwerk, holzfaeller, pocket")
    print("Ohne Rolle wird aus fleet_config.lua oder fleet_pocket_config.lua gelesen.")
end

local function download(baseUrl, file)
    local url = baseUrl:gsub("/$", "") .. "/" .. file.src
    local tmp = file.dst .. ".tmp"
    if fs.exists(tmp) then fs.delete(tmp) end
    print("Aktualisiere " .. file.dst)
    local ok = shell.run("wget", url, tmp)
    if not ok or not fs.exists(tmp) then error("Download fehlgeschlagen: " .. url) end
    if fs.exists(file.dst) then fs.delete(file.dst) end
    fs.move(tmp, file.dst)
end

local function inferRole()
    if fs.exists("fleet_pocket_config.lua") then return "pocket" end
    if fs.exists("fleet_config.lua") then
        local ok, cfg = pcall(require, "fleet_config")
        if ok and type(cfg) == "table" then
            if cfg.role == "coordinator" then return "koordinator" end
            if cfg.role == "worker" then return cfg.workerRole end
        end
    end
    return nil
end

local args = { ... }
local role = args[1]
local baseUrl = args[2] or DEFAULT_BASE_URL

if role and not ROLE_FILES[role] then
    baseUrl = role
    role = nil
end

role = role or inferRole()
if not role or not ROLE_FILES[role] then usage(); return end

print("Teuton-Fleet Update " .. VERSION .. " fuer " .. role)
for _, file in ipairs(ROLE_FILES[role]) do download(baseUrl, file) end
print("Update fertig. Config-Dateien wurden nicht geaendert.")
if role == "koordinator" then
    print("Hinweis: Fuer neues Depot-Layout deploySides = { \"left\", \"right\", \"front\" } setzen.")
end
