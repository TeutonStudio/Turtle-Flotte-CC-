-- Zweck: Deaktiviert den Koordinator-Wartungsmodus.
-- Erwartet: fs API.

if fs.exists("koordinator/maintenance") then
  fs.delete("koordinator/maintenance")
  print("Koordinator-Wartungsmodus deaktiviert.")
else
  print("Koordinator-Wartungsmodus war nicht aktiv.")
end

return true
