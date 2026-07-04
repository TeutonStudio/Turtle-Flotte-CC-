-- Kopieren nach: fleet_config.lua auf die Holzfaeller-/Axt-Turtle
return {
    group = "bergwerk_789_-968",
    id = "holz_789_-968",
    role = "worker",
    workerRole = "holzfaeller",
    coordinator = "basis_789_-968",
    protocolPrefix = "teuton_fleet_v1",
    statusInterval = 5,
    reportItems = false,
    minFuel = 500,
    serviceFuelThreshold = 100,
    preferredAxe = "minecraft:diamond_axe",
}
