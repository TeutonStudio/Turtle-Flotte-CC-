local Sim=dofile('tests/sim.lua')
local passed=0
local function test(name,fn)
  if arg[1] and not name:find(arg[1],1,true) then return end
  io.write(name..' ... '); io.flush()
  local ok,e=pcall(fn)
  if not ok then print('FAIL\n'..tostring(e)); os.exit(1) end
  passed=passed+1; print('ok')
end
local function finish(sim,id,seconds)
  local ok=sim:run(seconds or 300,function() return sim.manager.store.data.manager.reports[id]~=nil end)
  if not ok then
    local s=sim.manager.app:status()
    error('Timeout: '..Sim.serialize(s))
  end
  return sim.manager.store.data.manager.reports[id]
end
test('one worker: deploy, mine, fuel delivery, collect, pack, store',function()
  local sim=Sim.fixture()
  sim:block({x=10,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  local ok,r,e=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'}); assert(ok,e)
  local report=finish(sim,r.jobId)
  assert(report.status=='done')
  assert(not sim.world['10,0,0'])
  assert(report.delivered['minecraft:stone']==1)
  assert(sim.startChest.inventory[1] and sim.startChest.inventory[1].computer==101)
end)
test('three professions cooperate on mixed quarry with packet loss/duplicates',function()
  local sim=Sim.fixture({'spitzhacke','schaufel','axt'})
  sim.lossEvery=9; sim.duplicateEvery=7
  sim:block({x=10,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  sim:block({x=11,y=0,z=0},'minecraft:dirt',{['minecraft:mineable/shovel']=true})
  sim:block({x=12,y=0,z=0},'minecraft:oak_log',{['minecraft:logs']=true})
  local ok,r=sim.manager.app:command('abbau',{von='10,0,0',bis='12,0,0'}); assert(ok)
  local report=finish(sim,r.jobId,600)
  assert(report.status=='done')
  for x=10,12 do assert(not sim.world[x..',0,0']) end
  assert(report.delivered['minecraft:dirt']==1 and report.delivered['minecraft:oak_log']==1)
  assert(sim.duplicated>0 and sim.dropped>0)
end)
test('wood job respects bounding box and leaves stone intact',function()
  local sim=Sim.fixture({'axt'})
  sim:block({x=10,y=0,z=0},'minecraft:oak_log',{['minecraft:logs']=true})
  sim:block({x=11,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  sim:block({x=10,y=0,z=-1},'minecraft:oak_log',{['minecraft:logs']=true})
  local ok,r=sim.manager.app:command('holz',{von='10,0,0',bis='11,0,0'}); assert(ok)
  finish(sim,r.jobId)
  assert(not sim.world['10,0,0'] and sim.world['11,0,0'] and sim.world['10,0,-1'])
end)
test('registered crafting recipe, multiple batches and material pickup',function()
  local sim=Sim.fixture({'werkbank'})
  sim.config.recipes.planks={output='minecraft:oak_planks',count=4,grid={[1]='minecraft:oak_log'},returns={}}
  sim.config.materials['minecraft:oak_log']={pos={x=0,y=0,z=4},heading=2,side='down'}
  sim:chest({x=0,y=-1,z=4},{{name='minecraft:oak_log',count=8}})
  local ok,r,e=sim.manager.app:command('craft',{rezept='planks',menge='8'}); assert(ok,e)
  local report=finish(sim,r.jobId,600)
  assert(report.crafted==2 and report.delivered['minecraft:oak_planks']==8)
end)
test('empty coal chest blocks, then resumes after restock',function()
  local sim=Sim.fixture(); sim.coalChest.inventory={}
  sim:block({x=10,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'})
  sim:run(30)
  assert(not sim.manager.store.data.manager.reports[r.jobId])
  assert(sim.manager.app:status().blocked:find('Kohletruhe leer',1,true))
  sim.coalChest.inventory[1]={name='minecraft:coal',count=64}
  finish(sim,r.jobId)
end)
test('full output chest prevents success and resumes after clearing',function()
  local sim=Sim.fixture()
  for i=1,27 do sim.outputChest.inventory[i]={name='test:full_'..i,count=64} end
  sim:block({x=10,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'})
  assert(sim:run(180,function() return (sim.manager.app:status().blocked or ''):find('Ergebnislager voll',1,true) end))
  assert(not sim.manager.store.data.manager.reports[r.jobId])
  sim.outputChest.inventory={}
  local report=finish(sim,r.jobId)
  assert(report.delivered['minecraft:stone']==1)
end)
test('missing profession blocks and cancellation still collects all workers',function()
  local sim=Sim.fixture({'axt'})
  sim:block({x=10,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'})
  assert(sim:run(120,function() return sim.manager.store.data.manager.phase=='working' end))
  sim:run(15)
  assert(not sim.manager.store.data.manager.reports[r.jobId] and sim.world['10,0,0'])
  assert(sim.manager.app:command('abbrechen',{}))
  assert(finish(sim,r.jobId).status=='cancelled')
end)
test('worker low fuel and full inventory trigger additional physical service',function()
  local sim=Sim.fixture()
  for x=10,13 do sim:block({x=x,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true}) end
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='13,0,0'})
  assert(sim:run(180,function() return sim.manager.store.data.manager.phase=='working' end))
  local w=sim.actors[101]; w.fuel=1
  for i=1,16 do w.inv[i]={name='test:cargo_'..i,count=64} end
  local report=finish(sim,r.jobId,600)
  for i=1,16 do assert(report.delivered['test:cargo_'..i]==64) end
  assert(report.delivered['minecraft:stone']==4)
end)
test('paused job performs no new mining and resumes',function()
  local sim=Sim.fixture()
  sim:block({x=10,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  assert(sim.manager.app:command('pause',{}))
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'})
  sim:run(10); assert(sim.world['10,0,0'] and not sim.manager.store.data.manager.active)
  assert(sim.manager.app:command('weiter',{})); finish(sim,r.jobId)
end)
test('restart during manager transfer reconciles durable quantities',function()
  local sim=Sim.fixture()
  sim:block({x=10,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'})
  sim.crash=function(a,kind,meta) return a.id==1 and kind=='drop' and meta.name=='minecraft:stone' end
  assert(sim:run(180,function() return sim.crashed~=nil end))
  assert(sim.manager.store.data.intent and sim.manager.store.data.intent.kind=='drop')
  sim:start(sim.manager)
  local report=finish(sim,r.jobId)
  assert(report.delivered['minecraft:stone']==1)
end)
test('restart during worker movement reconciles GPS before continuing',function()
  local sim=Sim.fixture()
  sim:block({x=10,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'})
  sim.crash=function(a,kind) return a.id==101 and kind=='move' end
  assert(sim:run(180,function() return sim.crashed~=nil end))
  sim:start(sim.crashed)
  finish(sim,r.jobId)
end)
test('store selects complete next generation and rejects total corruption',function()
  local sim=Sim.new(); local a=sim:computer(1,'koordinator',{x=0,y=0,z=0},2)
  local S=a.env.dofile('v2/store.lua')
  local s=S.open('state',{v=1}); s:save(); s.data.v=2; s:save()
  a.files['state.next']=a.files.state; a.files.state='broken'
  assert(S.open('state',{}).data.v==2)
  a.files['state.next']='broken'; a.files['state.bak']='broken'
  assert(not pcall(S.open,'state',{}))
end)
test('protocol rejects spoofed sender and foreign fleet',function()
  local sim=Sim.fixture(); local before=sim.manager.store.data.manager.counter
  local packet={version=2,fleet='test',from=2,session='1',id='fake',kind='COMMAND',payload={cmd='abbau',args={von='1,1,1',bis='1,1,1'}}}
  sim.manager.net:receive(3,packet)
  packet.from=3; packet.fleet='other'; sim.manager.net:receive(3,packet)
  assert(sim.manager.store.data.manager.counter==before and #sim.manager.store.data.manager.queue==0)
end)
test('recipe validation rejects impossible output counts before queuing',function()
  local sim=Sim.fixture({'werkbank'})
  sim.config.recipes.planks={output='minecraft:oak_planks',count=4,grid={[1]='minecraft:oak_log'}}
  local ok=sim.manager.app:command('craft',{rezept='planks',menge='3'})
  assert(not ok and #sim.manager.store.data.manager.queue==0)
end)
test('restart while deploying resumes the same worker identity',function()
  local sim=Sim.fixture()
  sim:block({x=10,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'})
  sim.crash=function(a,kind) return a.id==1 and kind=='place' end
  assert(sim:run(180,function() return sim.crashed~=nil end))
  sim:start(sim.manager)
  finish(sim,r.jobId)
  assert(Sim.unserialize(sim.manager.files['.flotte/state']).seq>0)
end)
test('restart while collecting a worker finishes deposit before success',function()
  local sim=Sim.fixture()
  sim:block({x=10,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'})
  sim.crash=function(a,kind) return a.id==1 and kind=='dig' end
  assert(sim:run(180,function() return sim.crashed~=nil end))
  sim:start(sim.manager)
  finish(sim,r.jobId)
  assert(sim.startChest.inventory[1].computer==101)
end)
test('restart after physical crafting never crafts the batch twice',function()
  local sim=Sim.fixture({'werkbank'})
  sim.config.recipes.planks={output='minecraft:oak_planks',count=4,grid={[1]='minecraft:oak_log'},returns={}}
  sim.config.materials['minecraft:oak_log']={pos={x=0,y=0,z=4},heading=2,side='down'}
  sim:chest({x=0,y=-1,z=4},{{name='minecraft:oak_log',count=8}})
  local _,r=sim.manager.app:command('craft',{rezept='planks',menge='4'})
  sim.crash=function(a,kind) return a.id==101 and kind=='craft' end
  assert(sim:run(180,function() return sim.crashed~=nil end))
  sim:start(sim.crashed)
  local report=finish(sim,r.jobId)
  local crafts=0; for _,op in ipairs(sim.operations) do if op.kind=='craft' then crafts=crafts+1 end end
  assert(crafts==1 and report.delivered['minecraft:oak_planks']==4)
end)
test('lost network preserves reservations and resumes after reconnect',function()
  local sim=Sim.fixture()
  for x=10,13 do sim:block({x=x,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true}) end
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='13,0,0'})
  assert(sim:run(180,function() return sim.manager.store.data.manager.phase=='working' end))
  sim.network=false; sim:run(30)
  assert(not sim.manager.store.data.manager.reports[r.jobId])
  assert(sim.manager.store.data.manager.frozen)
  sim.network=true; sim:run(6); sim.manager.app:command('weiter',{pruefen='ja'})
  finish(sim,r.jobId)
end)
test('missing GPS blocks navigation and continues after infrastructure returns',function()
  local sim=Sim.fixture()
  sim:block({x=10,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'})
  assert(sim:run(180,function() return sim.manager.store.data.manager.phase=='working' end))
  sim.gps=false; sim:run(8)
  assert(not sim.manager.store.data.manager.reports[r.jobId])
  sim.gps=true; sim.manager.app:command('weiter',{pruefen='ja'})
  finish(sim,r.jobId)
end)
test('crafting preserves registered container returns',function()
  local sim=Sim.fixture({'werkbank'})
  sim.config.recipes.cake={output='minecraft:cake',count=1,grid={[1]='minecraft:milk_bucket'},returns={['minecraft:bucket']=1}}
  sim.config.materials['minecraft:milk_bucket']={pos={x=0,y=0,z=4},heading=2,side='down'}
  sim:chest({x=0,y=-1,z=4},{{name='minecraft:milk_bucket',count=1}})
  local _,r=sim.manager.app:command('craft',{rezept='cake',menge='1'})
  local report=finish(sim,r.jobId)
  assert(report.delivered['minecraft:cake']==1 and report.delivered['minecraft:bucket']==1)
end)
test('installer stages pinned files and preserves active release on download failure',function()
  local sim=Sim.new(); local a=sim:computer(1,'taschencomputer',{x=0,y=0,z=0})
  local env=a.env; local manifest={format=2,version='2.0.0',files={}}; local content={}
  local U=env.dofile('v2/util.lua')
  local initFile=assert(io.open('init.lua','r')); local installer=initFile:read('*a'); initFile:close()
  manifest.installer={bytes=#installer,checksum=U.checksum(installer)}
  for path in io.popen("find v2 -name '*.lua' | sort"):lines() do
    local f=assert(io.open(path,'r')); local body=f:read('*a'); f:close(); content[path]=body
    manifest.files[#manifest.files+1]={path=path,bytes=#body,checksum=U.checksum(body)}
  end
  a.files['.flotte/active']='.flotte/releases/old/'
  a.files['.flotte/role']='taschencomputer'; a.files['.flotte/config']='keep-config'; a.files['startup.lua']='old-startup'
  a.files['.flotte/releases/old/.complete']='old'
  a.files['init.lua']='installer-source'
  env.shell={getRunningProgram=function() return 'init.lua' end}
  env.printError=env.print
  env.textutils.unserializeJSON=function(s) return s=='commit' and {sha=string.rep('a',40)} or Sim.copy(manifest) end
  local requests=0; local fail=true
  env.http={get=function(url)
    requests=requests+1
    if fail and requests==4 then return nil,'injected failure' end
    local body
    if url:find('api.github.com',1,true) then body='commit'
    elseif url:match('/manifest.json$') then body='manifest'
    elseif url:match('/init.lua$') then body=installer
    else
      assert(url:find('/'..string.rep('a',40)..'/',1,true),'Unpinned file URL')
      body=content[url:match('/(v2/.+)$')]
    end
    if not body then return nil,'not found' end
    return {readAll=function() return body end,close=function() end}
  end}
  assert(loadfile('init.lua','t',env)()==false)
  assert(a.files['.flotte/active']=='.flotte/releases/old/' and a.files['startup.lua']=='old-startup' and a.files['.flotte/config']=='keep-config')
  fail=false; requests=0
  assert(loadfile('init.lua','t',env)()==true)
  assert(a.files['.flotte/active']:find(string.rep('a',40),1,true))
  assert(a.files['.flotte/config']=='keep-config' and a.files['.flotte/active.bak']=='.flotte/releases/old/')
end)
test('restart during worker turn recalibrates without trusting the old heading',function()
  local sim=Sim.fixture()
  sim:block({x=10,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true})
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'})
  sim.crash=function(a,kind) return a.id==101 and kind=='turn' and a.store.data.worker.task and a.store.data.worker.task.kind=='dig' end
  assert(sim:run(180,function() return sim.crashed~=nil end))
  sim:start(sim.crashed)
  sim:run(8)
  sim.manager.app:command('weiter',{pruefen='ja'})
  finish(sim,r.jobId)
end)
test('queued jobs redeploy the same installed worker with its saved state',function()
  local sim=Sim.fixture()
  for x=10,11 do sim:block({x=x,y=0,z=0},'minecraft:stone',{['minecraft:mineable/pickaxe']=true}) end
  local _,a=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'})
  local _,b=sim.manager.app:command('abbau',{von='11,0,0',bis='11,0,0'})
  finish(sim,a.jobId); finish(sim,b.jobId)
  local stored=sim.startChest.inventory[1]; assert(stored and stored.computer==101)
end)
test('abort during missing crafting ingredients returns workers without crafting',function()
  local sim=Sim.fixture({'werkbank'})
  sim.config.recipes.planks={output='minecraft:oak_planks',count=4,grid={[1]='minecraft:oak_log'},returns={}}
  sim.config.materials['minecraft:oak_log']={pos={x=0,y=0,z=4},heading=2,side='down'}
  sim:chest({x=0,y=-1,z=4})
  local _,r=sim.manager.app:command('craft',{rezept='planks',menge='4'})
  assert(sim:run(180,function() return (sim.manager.app:status().blocked or ''):find('Zutaten fehlen',1,true) end))
  sim.manager.app:command('abbrechen',{})
  local report=finish(sim,r.jobId)
  assert(report.status=='cancelled' and report.crafted==0)
end)
test('manager material overrides propagate to workers while protected blocks stay protected',function()
  local sim=Sim.fixture()
  sim.config.blockRoles['test:ore']='spitzhacke'
  sim:block({x=10,y=0,z=0},'test:ore',{})
  local _,r=sim.manager.app:command('abbau',{von='10,0,0',bis='10,0,0'})
  assert(finish(sim,r.jobId).delivered['test:ore']==1)
  local J=sim.manager.env.dofile('v2/jobs.lua')
  assert(not J.classify({name='minecraft:chest'},{['minecraft:chest']='spitzhacke'}))
end)
print(passed..' tests passed')
