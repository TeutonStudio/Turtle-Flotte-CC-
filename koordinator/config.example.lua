-- Zweck: Beispielkonfiguration fuer stationaere Koordinator-Setups.
-- Erwartet: Wird optional nach koordinator/config.lua kopiert und dort angepasst.

return {
  -- Erlaubt: "north", "south", "east", "west".
  heading = "north",

  -- Erlaubt: "front", "back", "left", "right", "up", "down".
  chestSide = "back",

  -- V1-Standard: false. Nur fuer freie Testumgebungen aktivieren.
  autoCalibrateHeading = false,
}
