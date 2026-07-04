-- Kopieren nach: fleet_config.lua auf die Mining-/Spitzhacken-Turtle
return {
    group = "bergwerk_789_-968",
    id = "bergbau_789_-968",
    role = "worker",
    workerRole = "bergbau",
    coordinator = "basis_789_-968",
    protocolPrefix = "teuton_fleet_v1",
    statusInterval = 5,
    reportItems = false,
    minFuel = 500,
    serviceFuelThreshold = 100,
    preferredPickaxe = "minecraft:diamond_pickaxe",
}
