-- Zweck: Aktiviert den Koordinator-Wartungsmodus fuer den naechsten Start.
-- Erwartet: fs API.

local h = fs.open("koordinator/maintenance", "w")
if h then
  h.write("maintenance")
  h.close()
  print("Koordinator-Wartungsmodus aktiviert.")
else
  print("Konnte koordinator/maintenance nicht schreiben.")
end

return true
