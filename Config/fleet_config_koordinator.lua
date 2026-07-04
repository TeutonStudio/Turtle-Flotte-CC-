-- Kopieren nach: fleet_config.lua auf dem Koordinator
return {
    group = "bergwerk_789_-968",      -- Arbeitsgruppen-ID. Muss pro Koordinator-Flotte eindeutig sein.
    id = "basis_789_-968",
    role = "coordinator",
    protocolPrefix = "teuton_fleet_v2",

    -- Der Koordinator steht direkt vor der persoenlichen Truhe und schaut sie an.
    chestSide = "front",
    -- GPS-Startdaten fuer Servicefahrten nach dem Initialisieren.
    -- initChest ist die Koordinate der persoenlichen/Init-Truhe.
    start = nil, -- Beispiel: { x = 789, y = 64, z = -967 }
    facing = nil, -- "north", "east", "south" oder "west"
    initChest = nil, -- Beispiel: { x = 789, y = 64, z = -968 }

    -- Wohin Worker platziert werden. front geht NICHT, wenn dort die Truhe steht.
    -- Bei Auto-Deploy wird die Liste der Reihe nach probiert.
    deploySide = "right", -- alter Einzelwert, bleibt als Fallback nutzbar
    deploySides = { "right", "left", "back", "top" },

    -- In der Truhe liegen vier vorbereitete, beschriftete Turtles.
    -- Auto-Deploy zieht so lange Turtles aus der Truhe und platziert sie auf freien deploySides,
    -- bis die benoetigte Rolle online ist. Deshalb ist die Reihenfolge nicht kritisch.
    deployCount = 4,
    deployPause = 1.5,
    deployWait = 8,
    autoDeploy = true,

    -- Nach dem Platzieren versucht der Koordinator, dem Worker so viele Fuel-Items zu geben.
    -- Wichtig: Kohle/Brennstoff muss in derselben Truhe liegen.
    workerFuelItems = 64,
    coordinatorFuelReserveItems = 64,
    searchPullLimit = 32,
    statusInterval = 5,
    reportDir = "berichte",

    -- Standardrolle fuer 'flotte abbau'. Fuer kombinierte Soft/Hard-Abbauplaene spaeter erweitern.
    abbauRole = "bergbau",

    chat = {
        enabled = true, -- nutzt ein Chatty/ChatBox-Peripheral, falls eines gefunden wird
    },

    workers = {
        { id = "handwerk_789_-968",   role = "handwerk" },
        { id = "graben_789_-968",     role = "graben" },
        { id = "bergbau_789_-968",    role = "bergbau" },
        { id = "holz_789_-968",       role = "holzfaeller" },
    }
}
