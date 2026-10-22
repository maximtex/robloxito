QuestLogic.init(QuestConfig, EnemyConfig, Economy)

local failures = 0
local function check(name, ok)
	if not ok then failures += 1 end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function ctxWith(overrides)
	local ctx = { UpgradeLevel = 0, PetsOwned = 0, PetsEquipped = 0, CombatPetsOwned = 0, ZonesUnlocked = 0, UnlockedZones = { Forest = true } }
	for k, v in overrides or {} do ctx[k] = v end
	return ctx
end
local DAY = 20000
local function kill(data, typeId, zoneId)
	return QuestLogic.record(data, { Type = "Kill", TypeId = typeId, ZoneId = zoneId or "Forest" })
end

print("-- 0. Configuración")
do
	local ids, ok = {}, true
	for _, list in { QuestConfig.Missions, QuestConfig.Daily, QuestConfig.Achievements } do
		for _, def in list do
			if ids[def.Id .. tostring(list)] or #def.Id > QuestConfig.MaxIdLength or type(def.Target) ~= "number" or def.Target <= 0 then ok = false end
			ids[def.Id .. tostring(list)] = true
			local goal = def.Goal
			if goal.Source == "ZoneKills" or goal.Zone then
				if not ZoneConfig.Zones[goal.Zone] then ok = false print("  zona inexistente", def.Id) end
			end
			if def.RequiresZone and not ZoneConfig.Zones[def.RequiresZone] then ok = false end
			if goal.Kind and goal.Kind ~= "Normal" and goal.Kind ~= "Strong" and goal.Kind ~= "Boss" then ok = false end
			if def.Reward and not (def.Reward.Min > 0 and def.Reward.Max >= def.Reward.Min and def.Reward.Share > 0) then ok = false end
		end
	end
	check("ids únicos, objetivos > 0, zonas y tipos de enemigo existentes, recompensas coherentes", ok)
	local unique = {}
	local dup = false
	for _, list in { QuestConfig.Missions, QuestConfig.Daily } do
		for _, def in list do
			if unique[def.Id] then dup = true end
			unique[def.Id] = true
		end
	end
	check("misiones y diarias no comparten Id (se reclaman por Id)", not dup)
	-- Equilibrio: peor caso real del día = diarias fijas + las de mayor tope del resto.
	-- Antes de la Caldera de Brasas (sin sus diarias) sigue siendo ~1,5 Colosos; con ella,
	-- como mucho ~1 Titán de la Caldera con la energía de 3 renacimientos.
	local function worstDay(includeCaldera)
		local worst, others = 0, {}
		for _, def in QuestConfig.Daily do
			if includeCaldera or def.RequiresZone ~= "EmberCaldera" then
				if table.find(QuestConfig.DailyAlways, def.Id) then worst += def.Reward.Max else table.insert(others, def.Reward.Max) end
			end
		end
		table.sort(others, function(a, b) return a > b end)
		for i = 1, QuestConfig.DailyCount - #QuestConfig.DailyAlways do worst += others[i] or 0 end
		return worst
	end
	check(("peor día sin la Caldera: %d de energía (<= 6000, ~1,5 Colosos)"):format(worstDay(false)), worstDay(false) <= 6000)
	check(("peor día con la Caldera: %d de energía (<= 30000, ~1 Titán con 3 renacimientos)"):format(worstDay(true)), worstDay(true) <= 30000)
end

print("-- 1. Progreso de objetivos")
local data = QuestLogic.empty()
local ctx = ctxWith()
QuestLogic.ensureDay(data, DAY, 1, ctx)
for _ = 1, 3 do kill(data, "Thornling") end
local defeatFive = QuestLogic.Missions.DefeatFive
check("3 derrotas -> DefeatFive 3/5", QuestLogic.progress(defeatFive, data, ctx) == 3)
kill(data, "Barkbrute")
check("un Bruto cuenta como enemigo fuerte (StrongKills 1)", data.Stats.StrongKills == 1 and data.Stats.Kills == 4)
kill(data, "Shardling", "CrystalValley")
check("derrotas por zona (Valle 1, Bosque 4)", data.Stats.ZoneKills.CrystalValley == 1 and data.Stats.ZoneKills.Forest == 4)
check("el progreso nunca pasa del objetivo", QuestLogic.progress(defeatFive, data, ctx) == 5)
check("diaria de derrotas cuenta (Patrulla 5/15)", data.Daily.Progress.DailyHunt == 5)

print("-- 2. Misión incompleta no se puede reclamar")
local fresh = QuestLogic.empty()
local code, amount = QuestLogic.claim(fresh, "DefeatFive", ctx)
check("DefeatFive sin derrotas -> NotComplete y 0 energía", code == "NotComplete" and amount == 0 and not fresh.Claimed.DefeatFive)
code = QuestLogic.claim(fresh, "ValleyHunter", ctx)
check("misión del Valle sin el Valle -> Locked", code == "Locked")

print("-- 3. Recompensa una sola vez")
code, amount = QuestLogic.claim(data, "DefeatFive", ctx)
check(("primera reclamación -> Success +%d"):format(amount), code == "Success" and amount == 40)
local code2, amount2 = QuestLogic.claim(data, "DefeatFive", ctx)
check("segunda reclamación -> AlreadyClaimed y 0", code2 == "AlreadyClaimed" and amount2 == 0)

print("-- Recompensa según la etapa")
local mission = QuestLogic.Missions.UnlockValley
check("nivel 0 -> mínimo (400)", QuestLogic.reward(mission, 0) == 400)
check("nivel 12 -> coste de la mejora 12 (1297)", QuestLogic.reward(mission, 12) == 1297)
check("nivel 50 -> tope (2500)", QuestLogic.reward(mission, 50) == 2500)

print("-- 5. Logros sin duplicados")
local adata = QuestLogic.empty()
QuestLogic.ensureDay(adata, DAY, 2, ctx)
kill(adata, "Thornling")
local first = QuestLogic.evaluate(adata, ctx)
local again = QuestLogic.evaluate(adata, ctx)
local firstBlood = 0
for _, n in first do if n.Id == "FirstBlood" then firstBlood += 1 end end
check("FirstBlood se desbloquea una vez", firstBlood == 1 and adata.Achievements.FirstBlood == true)
check("evaluar de nuevo no repite avisos ni recompensas", #again == 0)
for _ = 1, 99 do kill(adata, "Thornling") end
local hunter = QuestLogic.evaluate(adata, ctx)
local hunterReward, hunterCount = 0, 0
for _, n in hunter do if n.Id == "Hunter100" then hunterReward = n.Reward hunterCount += 1 end end
check(("Hunter100 una vez con su recompensa (+%d)"):format(hunterReward), hunterCount == 1 and hunterReward == 300)
check("ni con más derrotas vuelve a darse", #QuestLogic.evaluate(adata, ctx) == 0 and kill(adata, "Thornling") and #QuestLogic.evaluate(adata, ctx) == 0)
code = QuestLogic.claim(adata, "Hunter100", ctx)
check("los logros no se pueden 'reclamar' por remote (se conceden solos)", code == "InvalidRequest")

print("-- 6. Reinicio diario y persistencia")
local ddata = QuestLogic.empty()
QuestLogic.ensureDay(ddata, DAY, 7, ctx)
local todayIds = table.clone(ddata.Daily.Ids)
check(("3 diarias el día %d (%s)"):format(DAY, table.concat(todayIds, ", ")), #todayIds == 3 and table.find(todayIds, "DailyHunt") ~= nil)
check("sin el Valle ni mascota de combate no se ofrecen diarias imposibles", not table.find(todayIds, "DailyValley") and not table.find(todayIds, "DailyBoss") and not table.find(todayIds, "DailyPets"))
check("mismo día: no cambian", QuestLogic.ensureDay(ddata, DAY, 7, ctx) == false and table.concat(ddata.Daily.Ids) == table.concat(todayIds))
local other = QuestLogic.empty()
QuestLogic.ensureDay(other, DAY, 7, ctx)
check("deterministas: mismo jugador y día -> mismas diarias (cualquier servidor)", table.concat(other.Daily.Ids) == table.concat(todayIds))
for _ = 1, 15 do kill(ddata, "Thornling") end
code = QuestLogic.claim(ddata, "DailyHunt", ctx)
check("diaria completa se reclama", code == "Success")
check("y no dos veces el mismo día", QuestLogic.claim(ddata, "DailyHunt", ctx) == "AlreadyClaimed")
-- Persistencia (serialize -> guardar -> sanitize)
local restored = QuestLogic.sanitize(QuestLogic.serialize(ddata))
check("tras guardar y cargar: diarias, progreso y reclamadas intactos", restored.Daily.Day == DAY and table.concat(restored.Daily.Ids) == table.concat(todayIds) and restored.Daily.Claimed.DailyHunt == true and restored.Daily.Progress.DailyHunt == 15)
check("tras cargar no se puede volver a reclamar", QuestLogic.claim(restored, "DailyHunt", ctx) == "AlreadyClaimed")
-- Reloj de otro servidor ATRASADO: no reinicia
check("un día anterior (reloj atrasado) no reinicia las diarias", QuestLogic.ensureDay(restored, DAY - 1, 7, ctx) == false and restored.Daily.Claimed.DailyHunt == true)
-- Día nuevo
check("día siguiente: diarias nuevas, progreso a cero y reclamables otra vez", QuestLogic.ensureDay(restored, DAY + 1, 7, ctx) == true and next(restored.Daily.Progress) == nil and next(restored.Daily.Claimed) == nil)
check("una diaria del día anterior ya no se puede reclamar", (function()
	local r = QuestLogic.sanitize(QuestLogic.serialize(ddata))
	QuestLogic.ensureDay(r, DAY + 1, 7, ctx)
	local old = todayIds[2]
	return table.find(r.Daily.Ids, old) ~= nil or QuestLogic.claim(r, old, ctx) == "InvalidRequest"
end)())
local valleyCtx = ctxWith({ UnlockedZones = { Forest = true, CrystalValley = true }, ZonesUnlocked = 1, CombatPetsOwned = 1 })
local seenValley = false
for day = DAY, DAY + 30 do
	local d = QuestLogic.empty()
	QuestLogic.ensureDay(d, day, 7, valleyCtx)
	if table.find(d.Daily.Ids, "DailyValley") or table.find(d.Daily.Ids, "DailyPets") or table.find(d.Daily.Ids, "DailyBoss") then seenValley = true end
end
check("con el Valle y mascota de combate aparecen esas diarias algunos días", seenValley)

print("-- 7. Perfiles antiguos")
local old = SaveServiceSanitize({ Pets = { { Uid = "1", PetId = "Sproutling" } }, Equipped = { "1" }, NextPetUid = 2, UnlockedZones = { "CrystalValley" } })
check("partida sin Quests: mascotas y zonas intactas", #old.Pets == 1 and old.UnlockedZones[1] == "CrystalValley")
check("partida sin Quests: misiones vacías y válidas", old.Quests.Stats.Kills == 0 and next(old.Quests.Claimed) == nil and old.Quests.Daily.Day == 0)
local broken = QuestLogic.sanitize({ Stats = { Kills = -5, EnergyEarned = 0 / 0, BossKills = "x", TypeKills = { ForestWarden = 2, [5] = 9 } }, Claimed = { "DefeatFive", 42, ("x"):rep(100) }, Done = "nope", Daily = { Day = -3, Ids = { "DailyHunt", "DailyHunt", {} }, Progress = { DailyHunt = 1e30 } } })
check("datos corruptos se sanean (negativos, NaN, tipos raros, ids largos, duplicados)", broken.Stats.Kills == 0 and broken.Stats.EnergyEarned == 0 and broken.Stats.BossKills == 0 and broken.Stats.TypeKills.ForestWarden == 2 and broken.Claimed.DefeatFive and not broken.Claimed[("x"):rep(100)] and next(broken.Done) == nil and broken.Daily.Day == 0 and #broken.Daily.Ids == 1 and broken.Daily.Progress.DailyHunt <= 1e15)
local unknownKept = QuestLogic.sanitize({ Claimed = { RetiredMission = true } })
check("ids de misiones retiradas se conservan (no se pierde nada)", unknownKept.Claimed.RetiredMission == true)

print("-- 8. Eventos y solicitudes manipulados")
local vdata = QuestLogic.empty()
QuestLogic.ensureDay(vdata, DAY, 3, ctx)
check("enemigo inexistente rechazado", kill(vdata, "FakeDragon") == false and vdata.Stats.Kills == 0)
check("zona inexistente rechazada", kill(vdata, "Thornling", "Moon") == false)
check("energía negativa, NaN, enorme o texto rechazada", not QuestLogic.record(vdata, { Type = "Energy", Amount = -50 }) and not QuestLogic.record(vdata, { Type = "Energy", Amount = 0 / 0 }) and not QuestLogic.record(vdata, { Type = "Energy", Amount = 1e12 }) and not QuestLogic.record(vdata, { Type = "Energy", Amount = "999" }) and vdata.Stats.EnergyEarned == 0)
check("tipo de evento desconocido rechazado", QuestLogic.record(vdata, { Type = "Claim" }) == false and QuestLogic.record(vdata, nil) == false)
local bad = { {}, 42, "", ("A"):rep(200), "NoExiste", "FirstBlood" }
local allInvalid = true
for _, id in bad do
	local c, a = QuestLogic.claim(vdata, id, ctx)
	if c ~= "InvalidRequest" or a ~= 0 then allInvalid = false end
end
check("ids inválidos (tabla, número, vacío, largo, inventado, logro) -> InvalidRequest, 0 energía", allInvalid)
local notToday
for _, def in QuestConfig.Daily do
	if not table.find(vdata.Daily.Ids, def.Id) then notToday = def.Id break end
end
check(("diaria que no es de hoy (%s) -> InvalidRequest"):format(tostring(notToday)), QuestLogic.claim(vdata, notToday, ctx) == "InvalidRequest")

print("-- 9. Sin recompensas duplicadas ni ciclos")
local edata = QuestLogic.empty()
QuestLogic.ensureDay(edata, DAY, 4, ctx)
QuestLogic.record(edata, { Type = "Energy", Amount = 1999 })
code, amount = QuestLogic.claim(edata, "EarnEnergy", ctx)
check("EarnEnergy a 1999/2000 no se puede reclamar", code == "NotComplete")
-- Reclamar otra misión (energía de recompensa) NO suma a EnergyEarned
kill(edata, "Thornling")
QuestLogic.evaluate(edata, ctx)
local before = edata.Stats.EnergyEarned
QuestLogic.claim(edata, "BuyUpgrade", ctxWith({ UpgradeLevel = 1 }))
check("la energía de una recompensa no cuenta como progreso", edata.Stats.EnergyEarned == before)
-- Una derrota de jefe: misión FirstBoss (energía) + logro FirstBoss (insignia sin energía)
kill(edata, "ForestWarden")
local notices = QuestLogic.evaluate(edata, ctx)
local achievementEnergy = 0
for _, n in notices do if n.Type == "Achievement" and n.Id == "FirstBoss" then achievementEnergy = n.Reward end end
check("el primer jefe da la misión con energía y el logro como insignia (0 energía)", achievementEnergy == 0 and edata.Done.FirstBoss == true)
-- Misión de estado ya cumplida no se pierde al gastar
local sdata = QuestLogic.empty()
QuestLogic.evaluate(sdata, ctxWith({ PetsEquipped = 1 }))
check("misión cumplida queda marcada aunque luego se desequipe", QuestLogic.claim(sdata, "EquipPet", ctxWith({ PetsEquipped = 0 })) == "Success")

-- QuestService real ---------------------------------------------------------------------
print("-- 4. Servicio: solicitudes simultáneas, eventos y guardado")
local alice = { Name = "Alice", UserId = 11 }
local profile = { Energy = 0, UpgradeLevels = { GeneratorPower = 0 }, PetData = SaveServiceSanitize(nil), DataState = "Loaded", Dirty = false }
profiles[alice] = profile
QuestService.start()
readyListener(alice)
check("al estar listo envía el estado", lastState(alice) ~= nil and lastState(alice).Ready == true and #lastState(alice).Daily == 3)
for _ = 1, 5 do defeatListener(alice, { TypeId = "Thornling", Kind = "Normal", ZoneId = "Forest", Reward = 25 }) end
check("5 derrotas reales -> 5 en el perfil; su recompensa es dinero: no cuenta como energía", profile.PetData.Quests.Stats.Kills == 5 and profile.PetData.Quests.Stats.EnergyEarned == 0)
check("marca el perfil para guardar (no guarda él mismo)", profile.Dirty == true and saveCalls == 0)
-- Dos reclamaciones en el mismo instante (sin tiempo entre ellas)
local energyBefore = profile.Energy
clock += 1
fireServer("ClaimQuest", alice, "DefeatFive")
fireServer("ClaimQuest", alice, "DefeatFive")
local successes = 0
for _, r in results(alice) do if r[1] == true then successes += 1 end end
check(("dos solicitudes simultáneas: 1 éxito, energía +%d una sola vez"):format(profile.Energy - energyBefore), successes == 1 and profile.Energy - energyBefore == 40)
clock += 1
fireServer("ClaimQuest", alice, "DefeatFive")
local last = results(alice)[#results(alice)]
check("una tercera más tarde -> AlreadyClaimed", last[1] == false and last[2] == "AlreadyClaimed" and profile.Energy - energyBefore == 40)
clock += 1
fireServer("ClaimQuest", alice, { Id = "DefeatFive", Amount = 999999 })
last = results(alice)[#results(alice)]
check("el cliente no puede enviar cantidades (tabla -> InvalidRequest)", last[2] == "InvalidRequest" and profile.Energy - energyBefore == 40)
-- Ráfaga de solicitudes: límite de frecuencia
local countBefore = #results(alice)
for _ = 1, 20 do fireServer("ClaimQuest", alice, "DefeatFive") end
local tooFast, answered = 0, #results(alice) - countBefore
for i = countBefore + 1, #results(alice) do if results(alice)[i][2] == "TooFast" then tooFast += 1 end end
check(("ráfaga de 20: %d respuestas TooFast y el resto ignorado (inundación)"):format(tooFast), answered <= 8 and tooFast >= 1 and profile.Energy - energyBefore == 40)
-- Datos sin cargar: nada se registra ni se concede
local bob = { Name = "Bob", UserId = 12 }
profiles[bob] = { Energy = 0, UpgradeLevels = { GeneratorPower = 0 }, PetData = SaveServiceSanitize(nil), DataState = "Loading", Dirty = false }
defeatListener(bob, { TypeId = "Thornling", Kind = "Normal", ZoneId = "Forest", Reward = 25 })
clock += 1
fireServer("ClaimQuest", bob, "DefeatFive")
check("datos cargando: no registra progreso ni concede nada (NotReady)", profiles[bob].PetData.Quests.Stats.Kills == 0 and results(bob)[1][2] == "NotReady" and profiles[bob].Energy == 0)
-- Energía producida cuenta, y cambio de día durante la sesión
producedListener(alice, 10)
check("energía producida cuenta para EnergyEarned", profile.PetData.Quests.Stats.EnergyEarned == 10)
local dayBefore = profile.PetData.Quests.Daily.Day
serverTime += 86400
clock += 3
producedListener(alice, 1)
check("medianoche durante la sesión: diarias del día nuevo y estado enviado", profile.PetData.Quests.Daily.Day == dayBefore + 1 and lastState(alice).Day == dayBefore + 1)
-- Logro con recompensa: se concede una vez aunque haya muchos ciclos
local e0 = profile.Energy
for _ = 1, 95 do defeatListener(alice, { TypeId = "Thornling", Kind = "Normal", ZoneId = "Forest", Reward = 0 }) end
local e1 = profile.Energy
for _ = 1, 5 do clock += 1 producedListener(alice, 1) end
local e2 = profile.Energy
check(("Hunter100 concedido una vez (+%d) aunque se evalúe muchas veces"):format(e1 - e0), profile.PetData.Quests.Achievements.Hunter100 == true and e1 - e0 == 300 and e2 == e1)
-- Guardado real (SaveService) con los misiones, y carga posterior
local saved = SaveService.save(alice.UserId, profile.PetData, true)
local status, loaded = SaveService.load(alice.UserId)
check("SaveService guarda y carga las misiones (mismo DataStore, mismo registro)", saved and status == "Loaded" and loaded.Quests.Claimed.DefeatFive == true and loaded.Quests.Achievements.Hunter100 == true and loaded.Quests.Stats.Kills == 100)
storeData["player_11"].FutureField = "keep"
SaveService.save(alice.UserId, loaded, true)
check("campos desconocidos del registro no se borran al guardar", storeData["player_11"].FutureField == "keep")
-- Fallo de guardado y reintento: no duplica (la marca está en el perfil en memoria)
storeFailNext = 10
local okSave = SaveService.save(alice.UserId, profile.PetData, false)
clock += 1
fireServer("ClaimQuest", alice, "DefeatFive")
check("si el guardado falla, la reclamación sigue marcada en memoria (no se repite)", okSave == false and results(alice)[#results(alice)][2] == "AlreadyClaimed")
storeFailNext = 0
-- Diarias de mejoras y huevos: llegan del UpgradeService / PetService por GameEvents.
do
	local q = profile.PetData.Quests
	q.Daily.Ids = { "DailyUpgrade", "DailyEggs", "DailyHunt" }
	q.Daily.Progress = {}
	q.Daily.Claimed = {}
	q.Daily.Notified = {}
	local kills = q.Stats.Kills
	for _ = 1, 12 do
		GameEvents.fire("UpgradePurchased", alice, "GeneratorPower")
	end
	GameEvents.fire("UpgradePurchased", alice, "OtraMejora") -- solo cuenta la Resonancia del Cristal
	GameEvents.fire("EggOpened", alice, "ForestEgg")
	check("diaria de mejoras: 10/10 (con tope); huevos: 1/3", q.Daily.Progress.DailyUpgrade == 10 and q.Daily.Progress.DailyEggs == 1)
	check("esos eventos no tocan otras diarias ni las estadísticas", (q.Daily.Progress.DailyHunt or 0) == 0 and q.Stats.Kills == kills)
	GameEvents.fire("EggOpened", bob, "ForestEgg")
	check("con los datos cargando no cuenta", profiles[bob].PetData.Quests.Daily.Progress.DailyEggs == nil)
	local data = QuestLogic.empty()
	check("evento sin diarias activas: válido y sin progreso", QuestLogic.record(data, { Type = "Egg" }) and next(data.Daily.Progress) == nil)
end
-- Jugador antiguo cargado de un registro sin Quests
storeData["player_99"] = { Version = 1, Pets = { { Uid = "1", PetId = "MossFox" } }, Equipped = {}, NextPetUid = 2 }
local st, oldData = SaveService.load(99)
check("registro antiguo sin Quests carga bien (misiones vacías, mascota intacta)", st == "Loaded" and #oldData.Pets == 1 and oldData.Quests.Stats.Kills == 0)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
