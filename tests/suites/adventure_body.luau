-- Esta batería prueba la producción pasiva y offline (cristal y núcleos), que sigue en el
-- código detrás de EconomyConfig.PassiveEnergy: se enciende para comprobarla.
EconomyConfig.PassiveEnergy = true
-- Aventuras: AdventureLogic (pura) y el AdventureService REAL con PlayerDataService y
-- SaveService reales sobre un DataStore en memoria. Configuración, saneado, aceptar /
-- progreso / entregar (derrotas, objetos perdidos y entregas entre personajes), amuletos y
-- ranuras, bendiciones (activar, alargar, tope y caducidad), pasivas (producción, offline,
-- daño, botín, velocidad), distancias, límites de frecuencia y guardado v5.
QuestLogic.init(QuestConfig, EnemyConfig, Economy)
local defeat = nil
EnemyService.onDefeated = function(listener)
	defeat = listener
end
PlayerDataService.start()
AdventureService.start()

local Codes = Constants.PurchaseCodes
local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function near(a, b)
	return math.abs(a - b) < 1e-9
end
local function record(userId)
	return storeData["player_" .. userId]
end
local function count(map)
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

-- Cumple el paso actual de un personaje (datos puros).
local function fulfil(data, npcId)
	local st = AdventureLogic.state(data, npcId)
	local step = AdventureLogic.stepOf(npcId, st.Step)
	local goal = step.Goal
	if goal.Type == "Collect" then
		for _, itemId in goal.Items do
			AdventureLogic.record(data, { Type = "Collect", ItemId = itemId })
		end
	elseif goal.Type == "Kill" then
		for _ = 1, goal.Target do
			AdventureLogic.record(data, { Type = "Kill", TypeId = goal.Enemies[1], ZoneId = "Forest" })
		end
	else
		AdventureLogic.record(data, { Type = "Talk", NpcId = goal.Npc })
	end
end
local function finishStory(data, npcId)
	while AdventureLogic.state(data, npcId).Status ~= "Done" do
		AdventureLogic.accept(data, npcId)
		fulfil(data, npcId)
		AdventureLogic.turnIn(data, npcId)
	end
end

print("-- 1. Configuración")
local okConfig, problems = AdventureLogic.validateConfig()
check("AdventureConfig válida" .. (if okConfig then "" else ": " .. table.concat(problems, "; ")), okConfig)
local order = AdventureLogic.npcOrder()
check("cinco personajes en orden: Hiedra, Tavo, Pip, Lumi y Brasa", #order == 5 and order[1] == "Herbalist" and order[2] == "Hunter" and order[3] == "Explorer" and order[4] == "Oracle" and order[5] == "Smith")
local goalTypes, amuletGivers, threeSteps = {}, {}, true
for _, npcId in order do
	local npc = AdventureConfig.Npcs[npcId]
	threeSteps = threeSteps and #npc.Steps == 3 and npc.Steps[3].Reward.Amulet == npc.Amulet
	for _, step in npc.Steps do
		goalTypes[step.Goal.Type] = true
		if step.Reward.Amulet then
			amuletGivers[step.Reward.Amulet] = (amuletGivers[step.Reward.Amulet] or 0) + 1
		end
	end
end
check("cada historia tiene 3 misiones y la última da su amuleto", threeSteps)
check("los tres tipos de misión: derrotas, objetos perdidos y entregas", goalTypes.Kill and goalTypes.Collect and goalTypes.Talk)
local oneEach = count(amuletGivers) == count(AdventureConfig.Amulets)
for _, n in amuletGivers do
	oneEach = oneEach and n == 1
end
check("cada amuleto lo da exactamente una historia", oneEach)
check("bendiciones de 10 min y una ranura (dos al terminar las historias de SlotStories)", AdventureConfig.Blessings.Abundance.Duration == 600 and AdventureConfig.BaseSlots == 1 and AdventureConfig.MaxSlots == 2)
local enemiesOk = true
for _, npcId in order do
	for _, step in AdventureConfig.Npcs[npcId].Steps do
		if step.Goal.Type == "Kill" then
			for _, typeId in step.Goal.Enemies do
				enemiesOk = enemiesOk and EnemyConfig.Types[typeId] ~= nil
			end
		end
	end
end
check("los enemigos de las misiones existen", enemiesOk)

print("-- 2. Datos guardados: saneado")
local empty = AdventureLogic.sanitize(nil)
check("sin datos: vacío y ranuras vacías", next(empty.Npcs) == nil and next(empty.Amulets) == nil and empty.Equipped[1] == "" and empty.Equipped[2] == "")
local dirty = AdventureLogic.sanitize({
	Npcs = {
		Herbalist = { Step = 99, Accepted = true, Progress = -4 },
		Hunter = { Step = 2, Accepted = true, Progress = 0 / 0, Found = { "Arrow1", "Arrow2" } },
		Explorer = { Step = 1, Accepted = false, Progress = 7, Found = { Map1 = true } },
		Future = { Step = 7, Accepted = true, Progress = 3 },
		[5] = { Step = 1 },
	},
	Amulets = { "Sap", Fang = true, Bad = 3 },
	Equipped = { "Fang", "Sap" },
	Blessings = { Fury = 2.7, Fortune = -1, Abundance = 0 / 0, Ghost = 4 },
	Active = { Fury = 12345.6, Fortune = "ya" },
})
check("paso acotado: la historia terminada no puede tener misión aceptada", dirty.Npcs.Herbalist.Step == 4 and dirty.Npcs.Herbalist.Accepted == false)
check("progreso no válido -> 0 y objetos en lista conservados", dirty.Npcs.Hunter.Progress == 0 and dirty.Npcs.Hunter.Found.Arrow1 and dirty.Npcs.Hunter.Found.Arrow2)
check("misión sin aceptar: sin progreso ni objetos", dirty.Npcs.Explorer.Progress == 0 and next(dirty.Npcs.Explorer.Found) == nil)
check("personajes futuros se conservan; claves no válidas fuera", dirty.Npcs.Future and dirty.Npcs.Future.Step == 7 and dirty.Npcs[5] == nil)
check("amuletos en lista o mapa; valores raros fuera", dirty.Amulets.Sap and dirty.Amulets.Fang and dirty.Amulets.Bad == nil)
check("sin todas las historias la 2.ª ranura se vacía", dirty.Equipped[1] == "Fang" and dirty.Equipped[2] == "")
check("bendiciones: enteras y positivas (las futuras se conservan)", dirty.Blessings.Fury == 2 and dirty.Blessings.Fortune == nil and dirty.Blessings.Abundance == nil and dirty.Blessings.Ghost == 4)
check("activas: solo horas válidas", dirty.Active.Fury == 12345 and dirty.Active.Fortune == nil)
check("no se equipa lo que no se tiene", AdventureLogic.sanitize({ Equipped = { "Sap" } }).Equipped[1] == "")
local copy = AdventureLogic.serialize(dirty)
copy.Npcs.Hunter.Found.Arrow3 = true
copy.Amulets.Geode = true
check("serialize hace copias (lo guardado no cambia con el perfil)", dirty.Npcs.Hunter.Found.Arrow3 == nil and dirty.Amulets.Geode == nil)

print("-- 3. Misiones: aceptar, progreso y entregar")
local d = AdventureLogic.empty()
check("al principio: ofrece la misión 1 de 3", AdventureLogic.state(d, "Herbalist").Status == "Offer" and AdventureLogic.state(d, "Herbalist").Step == 1 and AdventureLogic.state(d, "Herbalist").Steps == 3)
check("sin aceptar nada cuenta", #AdventureLogic.record(d, { Type = "Collect", ItemId = "Dew1" }) == 0 and #AdventureLogic.record(d, { Type = "Kill", TypeId = "Thornling", ZoneId = "Forest" }) == 0)
check("entregar sin aceptar: NotComplete", AdventureLogic.turnIn(d, "Herbalist") == "NotComplete")
check("aceptar", AdventureLogic.accept(d, "Herbalist") == "Success" and AdventureLogic.state(d, "Herbalist").Status == "Active")
check("aceptar otra vez: AlreadyAccepted", AdventureLogic.accept(d, "Herbalist") == "AlreadyAccepted")
check("personaje inventado o id raro: InvalidRequest", AdventureLogic.accept(d, "Nobody") == "InvalidRequest" and AdventureLogic.accept(d, 5) == "InvalidRequest" and AdventureLogic.turnIn(d, {}) == "InvalidRequest")
local changes = AdventureLogic.record(d, { Type = "Collect", ItemId = "Dew1" })
check("objeto de la misión: 1/5", #changes == 1 and changes[1].Npc == "Herbalist" and changes[1].Progress == 1 and changes[1].Target == 5 and not changes[1].Ready)
check("el mismo objeto no cuenta dos veces", #AdventureLogic.record(d, { Type = "Collect", ItemId = "Dew1" }) == 0)
check("objeto de otra misión (no aceptada) no cuenta", #AdventureLogic.record(d, { Type = "Collect", ItemId = "Arrow1" }) == 0)
check("objeto inventado no cuenta", #AdventureLogic.record(d, { Type = "Collect", ItemId = "Gold" }) == 0)
check("derrotas no cuentan para una misión de objetos", #AdventureLogic.record(d, { Type = "Kill", TypeId = "Thornling", ZoneId = "Forest" }) == 0)
check("pendientes: los 4 que faltan", #AdventureLogic.pendingItems(d) == 4)
for index = 2, 5 do
	changes = AdventureLogic.record(d, { Type = "Collect", ItemId = "Dew" .. index })
end
check("5/5: lista para entregar", changes[1].Ready and AdventureLogic.state(d, "Herbalist").Status == "Ready" and #AdventureLogic.pendingItems(d) == 0)
local code, step, stepIndex = AdventureLogic.turnIn(d, "Herbalist")
check("entregar: paso 1, bendición de Abundancia y siguiente misión ofrecida",
	code == "Success" and stepIndex == 1 and step.Title == "Flores de rocío" and d.Blessings.Abundance == 1 and AdventureLogic.state(d, "Herbalist").Status == "Offer" and AdventureLogic.state(d, "Herbalist").Step == 2)
check("entregar otra vez no cobra dos veces", AdventureLogic.turnIn(d, "Herbalist") == "NotComplete" and d.Blessings.Abundance == 1)
AdventureLogic.accept(d, "Herbalist")
AdventureLogic.record(d, { Type = "Kill", TypeId = "Barkbrute", ZoneId = "Forest" })
check("otro enemigo no cuenta", AdventureLogic.state(d, "Herbalist").Progress == 0)
for _ = 1, 10 do
	AdventureLogic.record(d, { Type = "Kill", TypeId = "Thornling", ZoneId = "Forest" })
end
check("8 Espinillos (y no pasa de 8)", AdventureLogic.state(d, "Herbalist").Progress == 8 and d.Npcs.Herbalist.Progress == 8 and AdventureLogic.state(d, "Herbalist").Status == "Ready")
AdventureLogic.turnIn(d, "Herbalist")
AdventureLogic.accept(d, "Herbalist")
check("entrega: hablar con otro personaje no cuenta", #AdventureLogic.record(d, { Type = "Talk", NpcId = "Oracle" }) == 0)
changes = AdventureLogic.record(d, { Type = "Talk", NpcId = "Hunter" })
check("hablar con Tavo entrega el ungüento", #changes == 1 and changes[1].Npc == "Herbalist" and changes[1].Ready)
code, step = AdventureLogic.turnIn(d, "Herbalist")
check("última misión: Amuleto de Savia, puesto solo en la ranura vacía", code == "Success" and step.Reward.Amulet == "Sap" and d.Amulets.Sap and d.Equipped[1] == "Sap")
check("historia completada: ya no ofrece nada", AdventureLogic.state(d, "Herbalist").Status == "Done" and AdventureLogic.accept(d, "Herbalist") == "AlreadyClaimed" and AdventureLogic.turnIn(d, "Herbalist") == "AlreadyClaimed")
local first = AdventureConfig.Npcs.Herbalist.Steps[1]
check("energía: clamp(Share · coste, Min, Max)",
	AdventureLogic.rewardEnergy(first, 50) == 100 and AdventureLogic.rewardEnergy(first, 500) == 500 and AdventureLogic.rewardEnergy(first, 1e9) == 2000
		and AdventureLogic.rewardEnergy(first, nil) == 100 and AdventureLogic.rewardEnergy(first, 0 / 0) == 100)
-- Dos misiones a la vez: un mismo enemigo cuenta para todas las que lo piden.
local both = AdventureLogic.empty()
both.Npcs.Hunter = { Step = 3, Accepted = true, Progress = 0, Found = {} }
both.Npcs.Oracle = { Step = 3, Accepted = true, Progress = 0, Found = {} }
changes = AdventureLogic.record(both, { Type = "Kill", TypeId = "ForestWarden", ZoneId = "Forest" })
check("jefe del bosque: cuenta para Tavo, no para Lumi", #changes == 1 and changes[1].Npc == "Hunter" and AdventureLogic.state(both, "Oracle").Progress == 0)

print("-- 4. Amuletos y ranuras")
check("una ranura mientras queden historias", AdventureLogic.slots(d) == 1)
check("amuleto que no se tiene: NotOwned", AdventureLogic.equip(d, "Fang") == "NotOwned")
check("amuleto inventado: InvalidRequest", AdventureLogic.equip(d, "Crown") == "InvalidRequest" and AdventureLogic.equip(d, nil) == "InvalidRequest")
check("ranura 2 cerrada: Locked", AdventureLogic.equip(d, "Sap", 2) == "Locked")
check("ya puesto: AlreadySelected", AdventureLogic.equip(d, "Sap", 1) == "AlreadySelected")
check("quitar: ranura vacía; quitar otra vez: InvalidRequest", AdventureLogic.unequip(d, 1) == "Success" and d.Equipped[1] == "" and AdventureLogic.unequip(d, 1) == "InvalidRequest" and AdventureLogic.unequip(d, 9) == "InvalidRequest")
check("ponerlo de nuevo", AdventureLogic.equip(d, "Sap") == "Success" and d.Equipped[1] == "Sap")
for _, npcId in AdventureConfig.SlotStories do
	finishStory(d, npcId)
end
check("las cuatro historias del Bosque y el Valle abren la 2.ª ranura (sin la Caldera)", not AdventureLogic.allComplete(d) and AdventureLogic.slotStoriesComplete(d) and AdventureLogic.slots(d) == 2 and count(d.Amulets) == 4)
local kept = AdventureLogic.sanitize(AdventureLogic.serialize(d))
check("guardada y cargada sin la historia de Brasa, la 2.ª ranura sigue abierta", AdventureLogic.slots(kept) == 2)
for _, npcId in order do
	finishStory(d, npcId)
end
check("todas las historias: 5 amuletos y 2 ranuras", AdventureLogic.allComplete(d) and count(d.Amulets) == 5 and AdventureLogic.slots(d) == 2)
check("la 2.ª ranura se llena sola con el siguiente libre (sin ranura)", AdventureLogic.equip(d, "Fang") == "Success" and d.Equipped[2] == "Fang")
check("poner Savia en la 2.ª la mueve (no se duplica)", AdventureLogic.equip(d, "Sap", 2) == "Success" and d.Equipped[1] == "" and d.Equipped[2] == "Sap")
check("sin ranura libre reemplaza la primera", AdventureLogic.equip(d, "Geode") == "Success" and d.Equipped[1] == "Geode" and AdventureLogic.equip(d, "Feather") == "Success" and d.Equipped[1] == "Feather" and d.Equipped[2] == "Sap")
check("bendiciones ganadas en las historias (2 por historia)", (d.Blessings.Abundance or 0) + (d.Blessings.Fury or 0) + (d.Blessings.Fortune or 0) == 10)

print("-- 5. Bendiciones")
local b = AdventureLogic.empty()
check("sin bendiciones: NotOwned", AdventureLogic.useBlessing(b, "Fury", 1000) == "NotOwned")
check("bendición inventada: InvalidRequest", AdventureLogic.useBlessing(b, "Luck", 1000) == "InvalidRequest")
b.Blessings.Fury = 2
local okUse, expires = AdventureLogic.useBlessing(b, "Fury", 1000)
check("activar: 10 min y se gasta una", okUse == "Success" and expires == 1600 and b.Blessings.Fury == 1 and b.Active.Fury == 1600)
okUse, expires = AdventureLogic.useBlessing(b, "Fury", 1100)
check("otra igual alarga (no se pisa) y la última se borra del inventario", okUse == "Success" and expires == 2200 and b.Blessings.Fury == nil)
b.Blessings.Fortune = 10
local now = 5000
local uses = 0
while AdventureLogic.useBlessing(b, "Fortune", now) == "Success" do
	uses += 1
end
check("tope de 1 h: al llegar no se gasta más (MaxLevel)", uses == 6 and b.Active.Fortune == now + 3600 and b.Blessings.Fortune == 4 and AdventureLogic.useBlessing(b, "Fortune", now) == "MaxLevel" and b.Blessings.Fortune == 4)
check("caducan: prune quita la de Furia", AdventureLogic.prune(b, 2200) and b.Active.Fury == nil and b.Active.Fortune ~= nil and not AdventureLogic.prune(b, 2200))
local p = AdventureLogic.empty()
p.Amulets = { Sap = true, Fang = true, Geode = true, Feather = true }
p.Equipped[1] = "Sap"
p.Active = { Abundance = 100, Fury = 100, Fortune = 100 }
check("producción: Savia ×1.25 · Abundancia ×2 = ×2.5 (antes de caducar)", near(AdventureLogic.productionMultiplier(p, 50), 2.5) and near(AdventureLogic.productionMultiplier(p, 100), 1.25))
check("offline: solo amuletos (×1.25)", near(AdventureLogic.offlineMultiplier(p), 1.25))
p.Equipped[1] = "Fang"
check("daño: Colmillo ×1.2 · Furia ×1.3", near(AdventureLogic.damageMultiplier(p, 50), 1.2 * 1.3) and near(AdventureLogic.productionMultiplier(p, 50), 2))
p.Equipped[1] = "Geode"
check("botín: Corazón de Geoda ×1.4 · Fortuna ×2", near(AdventureLogic.lootMultiplier(p, 50), 2.8))
p.Equipped[1] = "Feather"
check("velocidad: Pluma ×1.2", near(AdventureLogic.walkSpeedMultiplier(p), 1.2) and near(AdventureLogic.damageMultiplier(p, 200), 1))
p.Equipped = { "Feather", "Sap" }
check("la 2.ª ranura no cuenta sin todas las historias", near(AdventureLogic.productionMultiplier(p, 200), 1))
check("sin datos o hora no válida: ×1", AdventureLogic.productionMultiplier(nil, 5) == 1 and AdventureLogic.damageMultiplier({}, 5) == 1 and AdventureLogic.lootMultiplier(p, 0 / 0) == 1)

print("-- 6. Estado para el cliente")
local s = AdventureLogic.empty()
AdventureLogic.accept(s, "Explorer")
AdventureLogic.record(s, { Type = "Collect", ItemId = "Map3" })
s.Blessings.Fury = 3
s.Active = { Fortune = 900, Fury = 10 }
local snap = AdventureLogic.snapshot(s, 100, { Explorer = 321 })
check("estado: progreso, objetos encontrados y recompensa",
	snap.Ready and snap.Npcs.Explorer.Status == "Active" and snap.Npcs.Explorer.Progress == 1 and snap.Npcs.Explorer.Found[1] == "Map3" and snap.Npcs.Explorer.Reward == 321)
check("estado: pendientes, bendiciones y solo activas vigentes", #snap.Pending == 4 and snap.Blessings.Fury == 3 and snap.Active.Fortune == 900 and snap.Active.Fury == nil and snap.Slots == 1)

print("-- 7. AdventureService real")
local npcPos = {
	Herbalist = Vector3.new(100, 0, 100),
	Hunter = Vector3.new(-100, 0, 100),
	Explorer = Vector3.new(100, 0, -100),
	Oracle = Vector3.new(1500, 0, 0),
}
local itemPos = {}
for itemId, item in AdventureConfig.Items do
	itemPos[itemId] = Vector3.new(item.Position.X * 3, 0, item.Position.Y * 3 + 1000)
end
local playerPos = {}
AdventureService.setWorld({
	npcPosition = function(npcId) return npcPos[npcId] end,
	itemPosition = function(itemId) return itemPos[itemId] end,
	playerPosition = function(player) return playerPos[player] end,
})
local function makePlayer(name, userId)
	local player = newPlayer(name, userId)
	player.CharacterAdded = signal()
	return player
end
local function at(player, position, dx)
	playerPos[player] = Vector3.new(position.X + (dx or 0), position.Y + 3, position.Z)
end
local function act(player, ...)
	advance(AdventureConfig.ActionRateLimit.Cooldown + 0.05)
	fireServer("AdventureAction", player, ...)
	advance(0)
	return lastResult("AdventureResult", player)
end
local function lastState(player)
	local args = lastResult("AdventureState", player)
	return args and args[1]
end

local p1 = makePlayer("Ana", 1)
join(p1)
advance(0)
local profile = PlayerDataService.get(p1)
check("datos cargados: estado inicial enviado (4 personajes con misión)", profile.DataState == "Loaded" and lastState(p1) and lastState(p1).Ready and lastState(p1).Npcs.Herbalist.Status == "Offer")
profile.UpgradeLevels.GeneratorPower = 5
PlayerDataService.recalculateProduction(p1)
local baseProduction = profile.ProductionPerSecond

playerPos[p1] = Vector3.new(0, 3, 0)
local args = act(p1, "Accept", "Herbalist")
check("aceptar lejos del personaje: TooFar", args[1] == false and args[2] == Codes.TooFar and args[3] == "Accept")
at(p1, npcPos.Herbalist, 10)
args = act(p1, "Accept", "Herbalist")
check("junto a ella: aceptada", args[1] == true and args[2] == Codes.Success and lastState(p1).Npcs.Herbalist.Status == "Active" and #lastState(p1).Pending == 5)
check("el estado llega ANTES que la confirmación", (function()
	local stateIndex, resultIndex = 0, 0
	for index, entry in fired do
		if entry.Player == p1 and entry.Name == "AdventureState" then stateIndex = index end
		if entry.Player == p1 and entry.Name == "AdventureResult" then resultIndex = index end
	end
	return stateIndex > 0 and stateIndex < resultIndex
end)())
at(p1, itemPos.Dew1, AdventureConfig.CollectRadius + 1)
advance(0.3)
check("cerca pero fuera del radio: no se recoge", lastState(p1).Npcs.Herbalist.Progress == 0)
at(p1, itemPos.Dew1, AdventureConfig.CollectRadius - 1)
advance(0.3)
local st = lastState(p1)
local foundNotice = false
for _, notice in st.Notices do
	foundNotice = foundNotice or (notice.Type == "Found" and notice.Item == "Dew1")
end
check("al pasar cerca se recoge (1/5) con aviso", st.Npcs.Herbalist.Progress == 1 and foundNotice and #st.Pending == 4)
playerPos[p1] = Vector3.new(itemPos.Dew2.X, itemPos.Dew2.Y + AdventureConfig.CollectHeight + 5, itemPos.Dew2.Z)
advance(0.3)
check("muy por encima (en una colina) no se recoge", PlayerDataService.get(p1).PetData.Adventure.Npcs.Herbalist.Found.Dew2 == nil)
for index = 2, 5 do
	at(p1, itemPos["Dew" .. index])
	advance(0.3)
end
check("5/5: lista", lastState(p1).Npcs.Herbalist.Status == "Ready")
args = act(p1, "TurnIn", "Herbalist")
check("entregar lejos: TooFar", args[1] == false and args[2] == Codes.TooFar)
at(p1, npcPos.Herbalist, 5)
local energyBefore = profile.Energy
local expectedEnergy = AdventureLogic.rewardEnergy(AdventureConfig.Npcs.Herbalist.Steps[1], Economy.getUpgradeCost("GeneratorPower", 5))
args = act(p1, "TurnIn", "Herbalist")
check(("entregar: +%d de energía y una Bendición de Abundancia"):format(expectedEnergy),
	args[1] == true and args[4].Energy == expectedEnergy and args[4].Blessing == "Abundance" and near(profile.Energy - energyBefore, expectedEnergy) and profile.PetData.Adventure.Blessings.Abundance == 1)
st = lastState(p1)
local rewardNotice = nil
for _, notice in st.Notices do
	if notice.Type == "Reward" then rewardNotice = notice end
end
check("aviso de recompensa y siguiente misión ofrecida con su energía", rewardNotice and rewardNotice.Energy == expectedEnergy and st.Npcs.Herbalist.Status == "Offer" and st.Npcs.Herbalist.Step == 2 and st.Npcs.Herbalist.Reward > 0)
args = act(p1, "TurnIn", "Herbalist")
check("entregar otra vez: NotComplete y sin cobrar", args[1] == false and args[2] == Codes.NotComplete and near(profile.Energy - energyBefore, expectedEnergy))

-- Bendición: producción ×2 y caduca sola
args = act(p1, "UseBlessing", "Abundance")
check("usar la bendición: producción ×2", args[1] == true and near(profile.ProductionPerSecond, baseProduction * 2) and near(p1:GetAttribute("ProductionPerSecond"), baseProduction * 2) and profile.PetData.Adventure.Blessings.Abundance == nil)
args = act(p1, "UseBlessing", "Abundance")
check("sin más bendiciones: NotOwned", args[1] == false and args[2] == Codes.NotOwned)
advance(AdventureConfig.Blessings.Abundance.Duration + 2)
check("a los 10 min caduca y la producción vuelve", near(profile.ProductionPerSecond, baseProduction) and profile.PetData.Adventure.Active.Abundance == nil)

-- Derrotas (solo las que pide la misión)
args = act(p1, "Accept", "Herbalist")
defeat(p1, { TypeId = "Barkbrute", Kind = "Strong", ZoneId = "Forest", Reward = 10 })
for _ = 1, 8 do
	defeat(p1, { TypeId = "Thornling", Kind = "Normal", ZoneId = "Forest", Reward = 5 })
end
advance(0)
check("8 Espinillos derrotados (el Bruto no cuenta): lista", lastState(p1).Npcs.Herbalist.Status == "Ready" and lastState(p1).Npcs.Herbalist.Progress == 8)
act(p1, "TurnIn", "Herbalist")
act(p1, "Accept", "Herbalist")
-- Entrega a otro personaje
check("hablar lejos de Tavo: TooFar", AdventureService.interact(p1, "Hunter") == Codes.TooFar)
check("personaje inventado: InvalidRequest", AdventureService.interact(p1, "Ghost") == Codes.InvalidRequest)
at(p1, npcPos.Hunter, 3)
check("hablar con Tavo entrega el ungüento", AdventureService.interact(p1, "Hunter") == Codes.Success)
local dialog = lastResult("AdventureDialog", p1)
check("y abre su conversación avisando de la entrega", dialog[1] == "Hunter" and dialog[2] == "Herbalist" and lastState(p1).Npcs.Herbalist.Status == "Ready")
at(p1, npcPos.Herbalist, 3)
args = act(p1, "TurnIn", "Herbalist")
check("amuleto: llega puesto y la producción sube ×1.25",
	args[1] == true and args[4].Amulet == "Sap" and args[4].Finished == true and profile.PetData.Adventure.Equipped[1] == "Sap" and near(profile.ProductionPerSecond, baseProduction * 1.25))
advance(0)
check("guardado en seguida: Version 12 y Adventure en el registro", record(1) and record(1).Version == 12 and record(1).Adventure.Amulets.Sap == true and record(1).Adventure.Npcs.Herbalist.Step == 4)
args = act(p1, "Unequip", 1)
check("quitarlo: producción normal", args[1] == true and near(profile.ProductionPerSecond, baseProduction))
args = act(p1, "Equip", "Sap", 2)
check("la 2.ª ranura sigue cerrada: Locked", args[1] == false and args[2] == Codes.Locked)
args = act(p1, "Equip", "Sap")
check("ponérselo otra vez", args[1] == true and near(profile.ProductionPerSecond, baseProduction * 1.25))
fireServer("AdventureAction", p1, "Equip", "Sap")
fireServer("AdventureAction", p1, "Equip", "Sap")
advance(0)
args = lastResult("AdventureResult", p1)
check("dos acciones seguidas: TooFast", args[1] == false and args[2] == Codes.TooFast)
for _ = 1, 10 do
	fireServer("AdventureAction", p1, "Equip", "Sap")
end
local floodCount = #fired
fireServer("AdventureAction", p1, "Equip", "Sap")
check("avalancha de peticiones: se ignoran en silencio", #fired == floodCount)
advance(AdventureConfig.ActionRateLimit.WindowSeconds + 0.1)
args = act(p1, "Hack", "Sap")
check("acción inventada: InvalidRequest", args[1] == false and args[2] == Codes.InvalidRequest and args[3] == nil)
args = act(p1, "Accept", { "Herbalist" })
check("argumento raro: InvalidRequest", args[1] == false and args[2] == Codes.InvalidRequest)

-- Guardar y volver
local function exit(player)
	leave(player)
	advance(0)
end
exit(p1)
local saved = record(1)
check("al salir: historia, amuleto puesto y sin bendiciones activas", saved.Adventure.Npcs.Herbalist.Step == 4 and saved.Adventure.Equipped[1] == "Sap" and next(saved.Adventure.Active) == nil)
local p1b = makePlayer("Ana", 1)
join(p1b)
advance(0)
local again = PlayerDataService.get(p1b)
check("al volver: todo igual y la pasiva aplicada", again.PetData.Adventure.Amulets.Sap and again.PetData.Adventure.Equipped[1] == "Sap" and lastState(p1b).Npcs.Herbalist.Status == "Done")

-- Partidas antiguas y producción offline
storeData.player_2 = { Version = 4, Energy = 50, UpgradeLevels = { GeneratorPower = 3 } }
local p2 = makePlayer("Bea", 2)
join(p2)
advance(0)
check("registro v4 sin Adventure: empieza vacío", next(PlayerDataService.get(p2).PetData.Adventure.Npcs) == nil and PlayerDataService.get(p2).PetData.Adventure.Equipped[1] == "")
storeData.player_3 = { Version = 5, Energy = 0, UpgradeLevels = { GeneratorPower = 4 }, LastSeen = os.time() - 2 * 3600 }
storeData.player_4 = { Version = 5, Energy = 0, UpgradeLevels = { GeneratorPower = 4 }, LastSeen = os.time() - 2 * 3600,
	Adventure = { Amulets = { Sap = true }, Equipped = { "Sap" }, Active = { Abundance = os.time() + 300 } } }
local p3 = makePlayer("Caro", 3)
local p4 = makePlayer("Dani", 4)
join(p3)
join(p4)
advance(0)
local function offline(player)
	local value = player:GetAttribute("OfflineReward")
	return tonumber(string.match(value or "", "^(%d+)")) or 0
end
check(("offline con Savia ×1.25 (la bendición no cuenta sin jugar): %d -> %d"):format(offline(p3), offline(p4)),
	offline(p3) > 0 and math.abs(offline(p4) - offline(p3) * 1.25) <= 1)
check("al entrar con la bendición aún activa: producción ×2.5", near(PlayerDataService.get(p4).ProductionPerSecond, PlayerDataService.get(p3).ProductionPerSecond * 2.5))

-- Sin datos cargados no se hace nada
storeLatency = 5
local p5 = makePlayer("Eli", 5)
join(p5)
at(p5, npcPos.Herbalist, 2)
fireServer("AdventureAction", p5, "Accept", "Herbalist")
args = lastResult("AdventureResult", p5)
check("con los datos cargando: NotReady", args and args[1] == false and args[2] == Codes.NotReady)
check("y hablar tampoco hace nada", AdventureService.interact(p5, "Herbalist") == Codes.NotReady)
advance(6)
storeLatency = 0

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
