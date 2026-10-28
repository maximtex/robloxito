-- El servidor arranca con el interruptor en true pero FUERA de Studio (partida publicada).
PlayerDataService.start()
DiamondService.start()
UpgradeService.start()
QuestService.start()
TutorialService.start()

local failures = 0
local function check(name, ok)
	if not ok then failures += 1 end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in a do if not same(v, b[k]) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end
local function hasWarning(text)
	for _, w in warnings do
		if w:find(text, 1, true) then return true end
	end
	return false
end

-- Tu partida "real": veterano con el Valle, tutorial completado y 9 000 de energía.
local REAL = { Version = 2, Diamonds = 9000, UpgradeLevels = { GeneratorPower = 12 }, Pets = { { Uid = "1", PetId = "MossFox" } }, Equipped = { "1" }, NextPetUid = 2, UnlockedZones = { "CrystalValley" }, Quests = { Stats = { Kills = 300, DiamondsEarned = 50000 }, Claimed = { DefeatFive = true } }, Tutorial = { Status = "Completed", Step = 5 } }
storeData.player_1 = deep(REAL)

print("-- 1. Partida publicada con el interruptor olvidado en true")
check("el servidor avisa de que se ignora", hasWarning("se IGNORA"))
local me = newPlayer("Yo", 1)
join(me)
advance(0)
local profile = PlayerDataService.get(me)
check("carga normal de los datos guardados (no hay modo prueba)", storeCalls > 0 and profile.DataState == "Loaded" and profile.Money >= 45000 and not profile.Sandbox)
check("sin atributo TestMode ni tutorial (veterano: completado)", me:GetAttribute("TestMode") == nil and me:GetAttribute("TutorialStatus") == "Completed")
leave(me)
advance(0)
REAL = deep(storeData.player_1) -- lo guardado por esta sesión normal pasa a ser la referencia
REAL.Session = nil

print("-- 2. Studio con el modo prueba activo")
isStudio = true
local callsBefore, storesBefore = storeCalls, getStoreCalls
me = newPlayer("Yo", 1)
join(me)
advance(0)
profile = PlayerDataService.get(me)
check("NINGUNA llamada al DataStore al entrar (ni lectura ni bloqueo)", storeCalls == callsBefore and getStoreCalls == storesBefore)
check("perfil temporal: 💰 15000 y 0 💎, mejoras a 0, solo la mascota inicial y sin zonas", profile.Sandbox == true and profile.Money == DevConfig.SandboxStartingMoney and profile.Diamonds == 0 and profile.UpgradeLevels.LaserSpeed == 0 and profile.UpgradeLevels.GeneratorPower == nil and #profile.PetData.Pets == 1 and #profile.PetData.UnlockedZones == 0)
check("misiones nuevas (nada reclamado del perfil real)", profile.PetData.Quests.Stats.Kills == 0 and next(profile.PetData.Quests.Claimed) == nil)
check("núcleos iniciales (solo Naturaleza), sin archivo y sin llamadas al DataStore", same(profile.PetData.Cores, CoreLogic.empty()) and #profile.PetData.CoresArchive == 0 and storeCalls == callsBefore and getStoreCalls == storesBefore)
check("atributo TestMode para el aviso y tutorial activo en el paso 1", me:GetAttribute("TestMode") == true and me:GetAttribute("TutorialStatus") == "Active" and me:GetAttribute("TutorialStep") == 0)
advance(1)
check("el 💰 inicial NO cuenta como 💎 conseguidos (sin producción pasiva; paso 1 sin hacer)", profile.PetData.Quests.Stats.DiamondsEarned == 0 and me:GetAttribute("TutorialStep") == 0)
GameEvents.fire("WaveWon", me, "Tutorial") -- lo que hace WaveService al ganar la práctica
advance(1)
check("tras ganar la oleada de práctica: paso 1 hecho", me:GetAttribute("TutorialStep") == 1)
advance(0.5)
fireServer("PurchaseUpgrade", me, "LaserSpeed")
profile.PetData.Weapons.Levels.Laser = 1
advance(1)
check("compras reales funcionan en el modo prueba y mejorar el arma completa el paso 2", profile.UpgradeLevels.LaserSpeed == 1 and me:GetAttribute("TutorialStep") == 2)
table.insert(profile.PetData.Pets, { Uid = "9", PetId = "MushroomHopper" })
defeat(me, "ForestWarden", "Boss")
table.insert(profile.PetData.UnlockedZones, "CrystalValley")
advance(1)
check("los cinco pasos se pueden completar", me:GetAttribute("TutorialStatus") == "Completed")
profile.Dirty = true
PlayerDataService.markDirty(me)
PlayerDataService.saveNow(me)
advance(200) -- dos guardados automáticos
check("ni saveNow, ni marcar cambios, ni el guardado automático llaman al DataStore", storeCalls == callsBefore)
leave(me)
advance(0)
check("al salir tampoco: el perfil temporal se descarta", storeCalls == callsBefore and PlayerDataService.get(me) == nil)
check("el registro real queda EXACTAMENTE igual", same(storeData.player_1, REAL))

print("-- 3. Cada Play empieza de cero")
me = newPlayer("Yo", 1)
join(me)
advance(0)
profile = PlayerDataService.get(me)
check("al volver a entrar: perfil nuevo otra vez (💰 15000, tutorial en el paso 1)", profile.Money == DevConfig.SandboxStartingMoney and me:GetAttribute("TutorialStatus") == "Active" and me:GetAttribute("TutorialStep") == 0)
fireServer("SkipTutorial", me)
check("en el modo prueba tampoco se omite antes de los primeros pasos", me:GetAttribute("TutorialStatus") == "Active")
PlayerDataService.get(me).PetData.Tutorial.Step = TutorialConfig.MinSkipStep
advance(1.1)
fireServer("SkipTutorial", me)
check("omitir funciona en el modo prueba", me:GetAttribute("TutorialStatus") == "Skipped")

print("-- 4. Cierre del servidor con un perfil de prueba")
task.spawn(closeCallbacks[1])
advance(1)
check("BindToClose no guarda el perfil de prueba", storeCalls == callsBefore and same(storeData.player_1, REAL))
leave(me)
advance(0)

print("-- 5. Dinero inicial no válido")
DevConfig.SandboxStartingMoney = -5
local other = newPlayer("Otro", 2)
join(other)
advance(0)
check("dinero inicial negativo -> valor normal (0)", PlayerDataService.get(other).Money == 0)
leave(other)
advance(0)
DevConfig.SandboxStartingMoney = 15000

print("-- 6. Studio con el modo prueba desactivado")
DevConfig.TutorialSandbox = false
me = newPlayer("Yo", 1)
join(me)
advance(0)
profile = PlayerDataService.get(me)
check("carga normal del perfil real (DataStore usado)", storeCalls > callsBefore and profile.DataState == "Loaded" and not profile.Sandbox and profile.Money >= 45000)
check("sin aviso de modo prueba", me:GetAttribute("TestMode") == nil)
profile.Diamonds += 5
local expected = profile.Diamonds
leave(me)
advance(0)
check("y se guarda con normalidad", storeData.player_1.Diamonds == expected)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
