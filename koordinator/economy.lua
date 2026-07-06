-- Zweck: Treibstoff- und Lagerlogistik fuer problematische Worker.
-- Erwartet: turtle, common/protocol.lua.

local protocol = dofile("common/protocol.lua")

local economy = {}
economy.FUEL_DROP_COUNT = 16

local function selectFuelLikeItem()
  if not turtle then return false end
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      return true
    end
  end
  return false
end

function economy.handleFuel(worker)
  if not worker then return false, "Worker fehlt" end
  if turtle and selectFuelLikeItem() then turtle.drop(economy.FUEL_DROP_COUNT) end
  return protocol.send(worker.id, protocol.REFUEL, { count = economy.FUEL_DROP_COUNT })
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
