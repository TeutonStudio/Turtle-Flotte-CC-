-- Kopieren nach: fleet_config.lua auf dem Koordinator.
return {
    group = "bergwerk_789_-968",
    id = "basis_789_-968",
    role = "coordinator",
    protocolPrefix = "teuton_fleet_v2",
    statusInterval = 5,
    reportDir = "berichte",

    -- Optional. GPS/Facing werden automatisch versucht.
    start = nil, -- Beispiel: { x = 789, y = 64, z = -967 }
    facing = nil, -- "north", "east", "south" oder "west"
    initChest = nil, -- Beispiel: { x = 789, y = 64, z = -968 }
}
