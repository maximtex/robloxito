-- El jugador ya está conectado ANTES de que arranquen los servicios (Play en Studio).
isStudio = true
local me = newPlayer("Yo", 1)
table.insert(playersList, me)
PlayerDataService.start()
EnergyService.start()
UpgradeService.start()
QuestService.start()
TutorialService.start()
local ok = true
local function check(name, cond) if not cond then ok = false end print((cond and "OK   " or "FALLO") .. "  " .. name) end
local profile = PlayerDataService.get(me)
check("perfil temporal creado al arrancar, sin DataStore", profile ~= nil and profile.Sandbox and storeCalls == 0)
check("atributos para el cliente: TestMode, DataStatus, energía", me:GetAttribute("TestMode") == true and me:GetAttribute("DataStatus") == "Unavailable" and me:GetAttribute("Energy") == 3000)
advance(1)
check("el tutorial aparece activo en el primer segundo", me:GetAttribute("TutorialStatus") == "Active" and me:GetAttribute("TutorialStep") == 0)
print(ok and "TODO OK" or "FALLOS")
