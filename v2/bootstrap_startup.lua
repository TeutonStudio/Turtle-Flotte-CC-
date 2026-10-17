local function readFile(p)
  local h=fs.open(p,'r') or fs.open(p..'.bak','r')
  assert(h,'Flotte-Datei fehlt: '..p)
  local v=h.readAll(); h.close(); return v
end
local root=readFile('.flotte/active')
local role=readFile('.flotte/role')
assert(root:match('^%.flotte/releases/[%w%-_%.]+/$'),'Ungueltiger Releasepfad')
shell.setAlias('flotte',root..'v2/main.lua')
shell.setAlias('flotte-update','.flotte/installer.lua')
if role~='taschencomputer' then return shell.run(root..'v2/main.lua','--role',role) end
print('Flotte v2 bereit. Hilfe: flotte')
