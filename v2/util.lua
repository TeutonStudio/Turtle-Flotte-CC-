local U = {}
function U.copy(t)
  if type(t) ~= 'table' then return t end
  local r = {}; for k,v in pairs(t) do r[k] = U.copy(v) end; return r
end
function U.now() return os.epoch('utc') / 1000 end
function U.key(p) return p.x .. ',' .. p.y .. ',' .. p.z end
function U.pos(s)
  if type(s) == 'table' then
    for _, k in ipairs({'x','y','z'}) do
      if type(s[k]) ~= 'number' or s[k] ~= s[k] or math.abs(s[k]) > 30000000 or s[k] % 1 ~= 0 then return nil end
    end
    return {x=s.x,y=s.y,z=s.z}
  end
  if type(s) ~= 'string' then return nil end
  local x,y,z = s:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
  if x then return U.pos({x=tonumber(x),y=tonumber(y),z=tonumber(z)}) end
end
function U.eq(a,b) return a and b and a.x==b.x and a.y==b.y and a.z==b.z end
function U.add(a,b) return {x=a.x+b.x,y=a.y+b.y,z=a.z+b.z} end
function U.dist(a,b) return math.abs(a.x-b.x)+math.abs(a.y-b.y)+math.abs(a.z-b.z) end
U.dirs = {{x=0,y=0,z=-1},{x=1,y=0,z=0},{x=0,y=0,z=1},{x=-1,y=0,z=0},{x=0,y=1,z=0},{x=0,y=-1,z=0}}
U.headings = {north=1,east=2,south=3,west=4}
function U.heading(v) return U.headings[v] or (tonumber(v) and tonumber(v)>=1 and tonumber(v)<=4 and tonumber(v)%1==0 and tonumber(v)) end
function U.neighbors(p)
  local r={}; for _,d in ipairs(U.dirs) do r[#r+1]=U.add(p,d) end; return r
end
function U.inside(p, box)
  return p.x>=box.min.x and p.x<=box.max.x and p.y>=box.min.y and p.y<=box.max.y and p.z>=box.min.z and p.z<=box.max.z
end
function U.box(a,b)
  a,b=U.pos(a),U.pos(b); if not a or not b then return nil,'Ganzzahlige Koordinaten x,y,z erforderlich' end
  local r={min={},max={}}
  for _,k in ipairs({'x','y','z'}) do r.min[k]=math.min(a[k],b[k]); r.max[k]=math.max(a[k],b[k]) end
  local volume=(r.max.x-r.min.x+1)*(r.max.y-r.min.y+1)*(r.max.z-r.min.z+1)
  if volume>32768 then return nil,'Maximal 32768 Bloecke pro Auftrag' end
  return r
end
function U.count(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
function U.checksum(s)
  local h=1; for i=1,#s do h=(h*31+s:byte(i))%2147483647 end; return h
end
function U.load(name) return dofile((FLOTTE_ROOT or '')..'v2/'..name..'.lua') end
function U.peripheralSide(side) return side=='up' and 'top' or side=='down' and 'bottom' or side end
function U.read(path)
  if not fs.exists(path) then return nil end
  local h=assert(fs.open(path,'r')); local s=h.readAll(); h.close(); return s
end
function U.write(path,s)
  local dir=fs.getDir(path); if dir~='' then fs.makeDir(dir) end
  local h=assert(fs.open(path,'w'),'Datei nicht schreibbar: '..path); h.write(s); h.close()
end
return U
