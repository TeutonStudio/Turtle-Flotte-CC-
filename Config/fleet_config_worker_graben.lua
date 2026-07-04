-- Kopieren nach: fleet_config.lua auf die Graben-/Schaufel-Turtle
return {
    group = "bergwerk_789_-968",
    id = "graben_789_-968",
    role = "worker",
    workerRole = "graben",
    coordinator = "basis_789_-968",
    protocolPrefix = "teuton_fleet_v2",
    statusInterval = 5,
    reportItems = false,
    minFuel = 500,
    serviceFuelThreshold = 100,
    preferredShovel = "minecraft:diamond_shovel",
}
