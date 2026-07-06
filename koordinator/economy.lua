-- Zweck: Treibstoff- und Lagerlogistik fuer problematische Worker.
-- Erwartet: turtle, common/protocol.lua.

local protocol = dofile("common/protocol.lua")
local vec3 = dofile("common/vec3.lua")

local economy = {}
economy.FUEL_DROP_COUNT = 16

function economy.handleFuel(worker)
  if not worker then return false, "Worker fehlt" end
  if worker.dockPos and worker.position and vec3.equals(worker.dockPos, worker.position) then
    print("Fuel-Problem: Worker " .. tostring(worker.id) .. " ist am Dock, manueller Nachschub moeglich.")
    return protocol.send(worker.id, protocol.REFUEL, { count = 0, note = "refuel_from_local_inventory" })
  end
  if not worker.fuelProblemLogged then
    print("Fuel-Nachschub nicht moeglich: Worker " .. tostring(worker.id) .. " nicht am Dock")
    worker.fuelProblemLogged = true
  end
  worker.status = "problem"
  return false, "Fuel-Nachschub nur am Dock oder per vorab geladenem Inventar moeglich"
end

function economy.handleInventory(worker, lager)
  if not worker then return false, "Worker fehlt" end
  worker.status = "returning"
  return protocol.send(worker.id, protocol.RETURN_TO_STORAGE, { lager = lager })
end

function economy.handleProblem(worker, job)
  if not worker then return false, "Worker fehlt" end
  if worker.problemArt == "fuel" then return economy.handleFuel(worker) end
  if worker.problemArt == "inventory_full" then
    return economy.handleInventory(worker, job and job.params and job.params.lager)
  end
  return false, "Unbekanntes Worker-Problem"
end

return economy
