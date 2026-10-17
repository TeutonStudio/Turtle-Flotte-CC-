local U=dofile((FLOTTE_ROOT or '')..'v2/util.lua')
local V=U.load('nav')
local J={}
local ground={dirt=true,grass_block=true,sand=true,red_sand=true,gravel=true,clay=true,snow=true,snow_block=true,mud=true,rooted_dirt=true,coarse_dirt=true,podzol=true,mycelium=true,soul_sand=true,soul_soil=true}
local stone={stone=true,cobblestone=true,deepslate=true,netherrack=true,granite=true,diorite=true,andesite=true,end_stone=true,basalt=true,blackstone=true,tuff=true,calcite=true,obsidian=true}
function J.classify(block, overrides)
  if block=='air' then return 'air' end
  if type(block)~='table' or type(block.name)~='string' then return nil,'Unbekannter Block' end
  local name=block.name; local tags=block.tags or {}
  if name:find('turtle',1,true) or name:find('computer',1,true) or name:find('chest',1,true) or name:find('barrel',1,true) or name:find('furnace',1,true) or name:find('spawner',1,true) then return nil,'Geschuetzter Block: '..name end
  if name=='minecraft:water' or name=='minecraft:lava' or name=='minecraft:bedrock' then return nil,'Fluessigkeit oder unzerstoerbarer Block: '..name end
  if overrides and overrides[name] then return overrides[name] end
  local short=name:match('^minecraft:(.+)$')
  if tags['minecraft:logs'] or tags['minecraft:leaves'] or (short and (short:match('_log$') or short:match('_wood$') or short:match('_leaves$') or short:match('_stem$') or short:match('_hyphae$'))) then return 'axt' end
  if tags['minecraft:mineable/shovel'] or (short and ground[short]) then return 'schaufel' end
  if tags['minecraft:mineable/pickaxe'] or (short and (stone[short] or short:match('_ore$'))) then return 'spitzhacke' end
  if tags['minecraft:mineable/axe'] then return 'axt' end
  return nil,'Keine Materialzuordnung: '..name
end
function J.recipe(recipe)
  if type(recipe)~='table' or type(recipe.output)~='string' or not tonumber(recipe.count) or recipe.count%1~=0 or recipe.count<1 or recipe.count>64 then return false,'Rezept benoetigt output und count (1..64)' end
  if type(recipe.grid)~='table' then return false,'Rezept benoetigt grid mit neun Plaetzen' end
  local found=false
  for k,v in pairs(recipe.grid) do
    if type(k)~='number' or k<1 or k>9 or k%1~=0 or (v~=false and type(v)~='string') then return false,'Ungueltiges 3x3-Raster' end
    if type(v)=='string' then found=true end
  end
  if not found then return false,'Leeres Rezept' end
  for name,n in pairs(recipe.returns or {}) do
    if type(name)~='string' or type(n)~='number' or n<1 or n%1~=0 then return false,'Ungueltige Restgegenstaende' end
  end
  return true
end
function J.create(id,kind,p,recipes)
  local job={id=id,kind=kind,status='queued',created=U.now(),tasks={},done={},errors={},params=U.copy(p),history={}}
  if kind=='craft' then
    local recipe=recipes[p.rezept]; local ok,e=J.recipe(recipe); if not ok then return nil,e end
    local amount=tonumber(p.menge)
    if not amount or amount<1 or amount%1~=0 or amount>32768 or amount%recipe.count~=0 then return nil,'Menge muss 1..32768 und durch '..recipe.count..' teilbar sein' end
    job.recipe=U.copy(recipe); job.batches=amount/recipe.count; job.crafted=0
  else
    if kind~='abbau' and kind~='erdarbeiten' and kind~='holz' then return nil,'Unbekannter Auftrag' end
    local box,e=U.box(p.von,p.bis); if not box then return nil,e end
    job.box=box
    job.total=(box.max.x-box.min.x+1)*(box.max.y-box.min.y+1)*(box.max.z-box.min.z+1)
  end
  return job
end
function J.accepts(job,role)
  return job.kind=='abbau' or job.kind=='erdarbeiten' and role=='schaufel' or job.kind=='holz' and role=='axt'
end
-- Frontier tasks always work from known air, with a second reachable air cell for service.
function J.next(job,map,worker,manager,occupied,overrides)
  if job.kind=='craft' then return nil end
  local blockedReason
  local checked=0
  for y=job.box.max.y,job.box.min.y,-1 do
    for x=job.box.min.x,job.box.max.x do for z=job.box.min.z,job.box.max.z do
      local p={x=x,y=y,z=z}; local key=U.key(p); local value=map[key]
      checked=checked+1; if checked%64==0 and sleep then sleep(0) end
      if not job.done[key] and not job.tasks[key] then
        local role,reason=J.classify(value,overrides)
        if value=='air' or (role and not J.accepts(job,role)) then
          job.done[key]=value=='air' and 'air' or 'skipped'
        elseif reason and value then blockedReason=reason
        elseif not role or role==worker.role then
          for _,stand in ipairs(U.neighbors(p)) do
            if map[U.key(stand)]=='air' and not occupied(U.key(stand),worker.id) then
              local route=V.path(map,worker.position,stand,function(k) return occupied(k,worker.id) end)
              if route then
                for _,service in ipairs(U.neighbors(stand)) do
                  if not U.eq(service,p) and map[U.key(service)]=='air' and (not occupied(U.key(service),manager.id) or U.eq(service,worker.position)) then
                    local access=V.path(map,manager.position,service,function(k) return U.eq(U.pos(k),stand) or (occupied(k,manager.id) and not U.eq(U.pos(k),worker.position)) end)
                    if access then
                      return {id=job.id..'/'..key..'/'..(role and 'dig' or 'inspect')..'/'..((job.sequence or 0)+1),jobId=job.id,key=key,target=p,stand=stand,service=service,kind=role and 'dig' or 'inspect',role=role,route=route,expected=type(value)=='table' and value.name or nil,status='offered',worker=worker.id}
                    end
                  end
                end
              end
            end
          end
        end
      end
    end end
  end
  return nil,blockedReason
end
function J.complete(job)
  if job.kind=='craft' then return job.crafted==job.batches end
  return U.count(job.done)==job.total
end
return J
