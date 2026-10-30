local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end

-- Azar fijo: devuelve los valores de la lista en bucle.
local function sequence(values)
	local index = 0
	return function()
		index = index % #values + 1
		return values[index]
	end
end

local function near(a, b)
	return math.abs(a - b) < 1e-9
end

print("-- Los círculos de las oleadas")
local place = WaveConfig.Place
check("los enemigos salen dentro del círculo", place.SpawnRadius.Min > 0 and place.SpawnRadius.Max > place.SpawnRadius.Min and place.SpawnRadius.Max < place.AreaRadius)
check("el altar se usa desde dentro del círculo", place.PromptDistance > 0 and place.PromptDistance < place.AreaRadius)
local function distance(a, b)
	return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2)
end
local placeCount = 0
local placesOK, insideOK, portalsClear, bossClear, spawnsClear, guardedAll, arrivalClear = true, true, true, true, true, true, true
local placeOfZone = {}
-- Centro de un círculo en el mundo (como WaveService)
local function worldOf(spot)
	local zone = ZoneConfig.Zones[spot.Zone]
	local base = GeneratorConfig.Position
	return base.X + zone.Center.X + spot.Offset.X, base.Z + zone.Center.Y + spot.Offset.Y
end
for placeId, spot in WaveConfig.Places do
	local zone = ZoneConfig.Zones[spot.Zone]
	local mode = WaveConfig.Arenas[spot.Arena]
	-- El de la práctica del tutorial juega su modo; los demás, el de su zona (como mucho uno en
	-- su mazmorra y otro al aire libre: las Tierras Divididas tienen los dos)
	local modeOK = zone and mode and mode.Zone == spot.Zone and mode.Place == placeId
	if spot.Practice then
		modeOK = modeOK and mode.Tutorial == true
	else
		modeOK = modeOK and not mode.Tutorial
		placeCount += 1
		local key = spot.Zone .. (if spot.Cave then "/Cueva" else "")
		if placeOfZone[key] then
			placesOK = false
			print("  dos círculos en la zona " .. key)
		end
		placeOfZone[key] = placeId
	end
	if not modeOK then
		placesOK = false
		print("  círculo mal configurado: " .. placeId)
	end
	if spot.Cave and zone then
		-- En la sala del altar de la cueva, entero y lejos de sus paredes
		local x, z = worldOf(spot)
		local _, room = CaveLogic.roomAt(x, z)
		local r = room and room.Rect
		local margin = place.AreaRadius + 8
		if not (room and room.Altar and x - margin > r.MinX and x + margin < r.MaxX and z - margin > r.MinZ and z + margin < r.MaxZ) then
			insideOK = false
			print("  el círculo de " .. placeId .. " no cabe en la sala del altar de la cueva")
		end
	elseif zone and not (math.abs(spot.Offset.X) + place.AreaRadius < zone.Radius and math.abs(spot.Offset.Y) + place.AreaRadius < zone.Radius) then
		insideOK = false
	end
	if zone and distance(Vector2.new(zone.Arrival.X, zone.Arrival.Z), spot.Offset) <= place.AreaRadius + 4 then
		arrivalClear = false
		print("  la llegada a " .. spot.Zone .. " cae dentro del círculo")
	end
	for _, portal in ZoneConfig.Portals do
		if portal.Zone == spot.Zone and distance(portal.Offset, spot.Offset) < place.AreaRadius + 20 then
			portalsClear = false
		end
	end
	local zoneEnemies = EnemyConfig.Zones[spot.Zone]
	local bossArena = zoneEnemies and zoneEnemies.Boss and zoneEnemies.Boss.Arena
	if bossArena and distance(bossArena.Center, spot.Offset) <= bossArena.Radius + place.AreaRadius then
		bossClear = false
	end
	for _, spawn in (zoneEnemies and zoneEnemies.Spawns) or {} do
		if distance(spawn.Offset, spot.Offset) <= place.AreaRadius + 10 then
			spawnsClear = false
			print("  enemigo del mundo junto al círculo de " .. placeId .. ": " .. spawn.Type .. " en " .. tostring(spawn.Offset))
		end
	end
	local guarded = false
	for _, safe in (zoneEnemies and zoneEnemies.SafeZones) or {} do
		if distance(safe.Center, spot.Offset) + place.AreaRadius <= safe.Radius then
			guarded = true
		end
	end
	if not guarded then
		guardedAll = false
		print("  el círculo de " .. placeId .. " no es zona segura")
	end
end
-- (La Fortaleza Goblin no tiene: su jefe, el Rey Goblin, está en su Sala del Trono)
check("un círculo de oleadas en cada mazmorra (Bosque, Valle, Caldera, Tundra y Grieta) y el Altar del Equilibrio", placeCount == 6 and placeOfZone["Forest/Cueva"] ~= nil and placeOfZone["CrystalValley/Cueva"] ~= nil and placeOfZone["EmberCaldera/Cueva"] ~= nil and placeOfZone["FrozenTundra/Cueva"] ~= nil
	and placeOfZone["DividedLands/Cueva"] ~= nil and placeOfZone.DividedLands ~= nil and placeOfZone.GoblinFortress == nil)
check("cada círculo juega el modo de su zona", placesOK)
check("los círculos caben en su zona", insideOK)
check("la llegada a cada zona queda fuera del círculo", arrivalClear)
check("lejos de los portales de su zona", portalsClear)
check("no pisan la arena del jefe de la zona", bossClear)
check("ningún enemigo del mundo sale dentro ni cerca de un círculo", spawnsClear)
check("cada círculo es zona segura para los enemigos del mundo", guardedAll)
local tutorialMode = WaveLogic.tutorialArena()
local practice = tutorialMode and WaveConfig.Places[WaveConfig.Arenas[tutorialMode].Place]
local arrival = ZoneConfig.Zones.ThornWoods.Arrival
check("la práctica del tutorial se juega en su altar del Bosque de Espinas, cerca de la llegada (no en el spawn)", practice ~= nil and practice.Practice == true and practice.Zone == "ThornWoods" and not practice.Cave
	and distance(Vector2.new(arrival.X, arrival.Z), practice.Offset) <= 90)
local forestPlace = WaveConfig.Places[WaveConfig.Arenas.Forest.Place]
local altarCenter = CaveLogic.altarCenter()
local fx, fz = worldOf(forestPlace)
check("las Oleadas del Guardián se juegan en el centro de la sala del altar de la cueva", forestPlace.Cave == true and altarCenter ~= nil and math.abs(fx - altarCenter.X) < 1e-6 and math.abs(fz - altarCenter.Y) < 1e-6)
local aliveOK = WaveLogic.maxAlive(1) == WaveConfig.AliveStart and WaveLogic.maxAlive(1) < WaveConfig.MaxAlive
for wave = 2, 12 do
	if WaveLogic.maxAlive(wave) < WaveLogic.maxAlive(wave - 1) or WaveLogic.maxAlive(wave) > WaveConfig.MaxAlive then
		aliveOK = false
	end
end
check("las primeras oleadas no te rodean de golpe (vivos a la vez crecen hasta el tope)", aliveOK and WaveLogic.maxAlive(99) == WaveConfig.MaxAlive)
local damageOK = WaveLogic.damageMultiplier(1) < 1 and WaveLogic.damageMultiplier(WaveLogic.waveCount("Forest")) > 1
for wave = 2, 12 do
	if WaveLogic.damageMultiplier(wave) < WaveLogic.damageMultiplier(wave - 1) or WaveLogic.damageMultiplier(wave) > WaveConfig.DamageMax then
		damageOK = false
	end
end
check("los enemigos pegan flojo al principio y más fuerte al final", damageOK)
check("al limpiar una oleada se recupera parte de la vida", WaveConfig.ClearHeal > 0 and WaveConfig.ClearHeal < 1)
check("partidas a la vez y jugadores por partida", WaveConfig.MaxRuns >= 1 and WaveConfig.MaxPlayersPerRun >= 1)
check("el dinero de las oleadas se queda normal (multiplicador entre 0 y 1)", WaveConfig.MoneyMultiplier > 0 and WaveConfig.MoneyMultiplier <= 1)

print("-- Modos")
local arena = WaveConfig.Arenas.Forest
check("existe el modo del Bosque", arena ~= nil)
check("su zona existe", ZoneConfig.Zones[arena.Zone] ~= nil)
check("el jefe de las oleadas es un jefe que existe, con sitio en la reserva", EnemyConfig.Types[arena.Boss] ~= nil and EnemyConfig.Types[arena.Boss].Kind == "Boss" and (arena.Pool[arena.Boss] or 0) >= 1)
local typesOK, poolOK = true, true
local function checkTypes(mode, counts)
	for typeId, count in counts do
		local def = EnemyConfig.Types[typeId]
		if not (def and def.Kind ~= "Boss" and count > 0) then
			typesOK = false
		end
		if not (mode.Pool[typeId] and mode.Pool[typeId] >= 1) then
			poolOK = false
		end
	end
end
for _, mode in WaveConfig.Arenas do
	for _, counts in mode.Waves do
		checkTypes(mode, counts)
	end
	checkTypes(mode, mode.BossEscort or {})
end
check("las oleadas solo piden enemigos normales o fuertes que existen", typesOK)
check("cada tipo de las oleadas tiene sitio en la reserva", poolOK)
check("10 oleadas: 9 de hordas y la del jefe", WaveLogic.waveCount("Forest") == 10 and WaveLogic.isBossWave("Forest", 10) and not WaveLogic.isBossWave("Forest", 9))
local zonesOK = true
for arenaId, mode in WaveConfig.Arenas do
	local zoneEnemies = EnemyConfig.Zones[mode.Zone]
	local function fromZone(counts)
		for typeId in counts do
			local found = false
			for _, spawn in (zoneEnemies and zoneEnemies.Spawns) or {} do
				if spawn.Type == typeId then
					found = true
				end
			end
			if not found then
				zonesOK = false
				print("  " .. arenaId .. ": " .. typeId .. " no es de su zona")
			end
		end
	end
	for _, counts in mode.Waves do
		fromZone(counts)
	end
	fromZone(mode.BossEscort or {})
	if mode.Boss and not (zoneEnemies and zoneEnemies.Boss and zoneEnemies.Boss.Type == mode.Boss and (mode.Pool[mode.Boss] or 0) >= 1) then
		zonesOK = false
		print("  " .. arenaId .. ": su jefe no es el de su zona")
	end
end
check("cada modo usa los enemigos y el jefe de su zona", zonesOK)
-- Junto al punto de aparición no sale ningún bicho del mundo (EnemyConfig.Zones.*.SpawnClear)
local clearOK, worldCount = true, 0
for zoneId, zone in EnemyConfig.Zones do
	local clear = zone.SpawnClear
	for _, spawn in zone.Spawns or {} do
		if zoneId == "ThornWoods" and math.abs(spawn.Offset.X) < 500 then
			worldCount += 1
		end
		if clear and math.sqrt((spawn.Offset.X - clear.Center.X) ^ 2 + (spawn.Offset.Y - clear.Center.Y) ^ 2) < clear.Radius then
			clearOK = false
			print(("  %s: %s en (%d, %d) está junto al punto de aparición"):format(zoneId, spawn.Type, spawn.Offset.X, spawn.Offset.Y))
		end
	end
end
check("ningún bicho junto al punto de aparición, y el Bosque de Espinas lleno (30 o más)", clearOK and EnemyConfig.Zones.Forest.SpawnClear ~= nil and worldCount >= 30)
local townEnemies = 0
for _, spawn in EnemyConfig.Zones.Forest.Spawns do
	if math.abs(spawn.Offset.X) < 500 then
		townEnemies += 1
	end
end
check("el pueblo no tiene bichos (solo los de su cueva, lejos del mapa)", townEnemies == 0)
check("más oleadas en las mazmorras de arriba: Bosque 10, Valle 12 y Caldera 15, la última con su jefe", WaveLogic.waveCount("Forest") == 10 and WaveLogic.waveCount("CrystalValley") == 12 and WaveLogic.isBossWave("CrystalValley", 12) and not WaveLogic.isBossWave("CrystalValley", 10)
	and WaveLogic.waveCount("EmberCaldera") == 15 and WaveLogic.isBossWave("EmberCaldera", 15))

print("-- Mazmorras: élites y cofre")
check("élites solo en el Valle y la Caldera", not WaveLogic.isElite("Forest", 0) and WaveLogic.isElite("CrystalValley", 0.01) and not WaveLogic.isElite("CrystalValley", 0.5) and WaveLogic.isElite("EmberCaldera", 0.1) and not WaveLogic.isElite("Tutorial", 0))
local potions = { "Diamonds", "Damage", "Money", "Luck" }
local fm, fp = WaveLogic.chestReward("Forest", 0.99, 0, potions)
local vm, vp = WaveLogic.chestReward("CrystalValley", 0, 0.99, potions)
local cm = WaveLogic.chestReward("EmberCaldera", 0.99, 0, potions)
check("cofre: más 💰 en cada zona y a veces una poción", fm > 0 and vm > fm and cm > vm and fp == nil and vp == "Luck")
check("sin cofre en la práctica del tutorial ni sin pociones", WaveLogic.chestReward("Tutorial", 0, 0, potions) == 0 and select(2, WaveLogic.chestReward("Forest", 0, 0, {})) == nil)
local fE, fM = WaveLogic.clearReward(3, "Forest")
local vE, vM = WaveLogic.clearReward(3, "CrystalValley")
local cE, cM = WaveLogic.clearReward(3, "EmberCaldera")
local wE, wM = WaveLogic.victoryReward("Forest")
local xE, xM = WaveLogic.victoryReward("EmberCaldera")
check("las zonas altas dan más premio (limpiar y ganar)", fE < vE and vE < cE and fM < vM and vM < cM and wE < xE and wM < xM)
check("el premio sin modo es el de siempre", WaveLogic.clearReward(3) == fE)

local practice = WaveConfig.Arenas.Tutorial
check("existe la práctica del tutorial", practice ~= nil and practice.Tutorial == true)
check("la práctica: 3 oleadas y sin jefe", WaveLogic.waveCount("Tutorial") == 3 and not WaveLogic.isBossWave("Tutorial", 3))
check("la práctica: mejora tras la 2 (no tras la última)", WaveLogic.isCardWave("Tutorial", 2) and not WaveLogic.isCardWave("Tutorial", 3) and not WaveLogic.isCardWave("Tutorial", 1))
local easier = true
local firstForest = 0
for typeId, count in arena.Waves[1] do
	firstForest += EnemyConfig.Types[typeId].MaxHealth * count
end
local practiceFirst = 0
for typeId, count in practice.Waves[1] do
	practiceFirst += EnemyConfig.Types[typeId].MaxHealth * count
end
check("la práctica empieza más fácil que el modo normal", practiceFirst < firstForest)
local hintsOK = WaveLogic.hint("Tutorial", "Countdown") ~= nil and WaveLogic.hint("Tutorial", "Victory") ~= nil
for wave = 1, #practice.Waves do
	if not WaveLogic.hint("Tutorial", wave) then
		hintsOK = false
	end
end
check("la práctica explica cada momento (consejos)", hintsOK and easier)
check("el modo normal no tiene consejos y lo raro no falla", WaveLogic.hint("Forest", 1) == nil and WaveLogic.hint("Nada", "Countdown") == nil)
local practiceE, practiceM = WaveLogic.victoryReward("Tutorial")
check("la práctica da un premio de victoria más pequeño", near(practiceE, WaveConfig.VictoryDiamonds * practice.VictoryScale) and practiceM == math.floor(WaveConfig.VictoryMoney * practice.VictoryScale) and practiceE < WaveLogic.victoryReward("Forest"))
check("una arena que no existe no tiene oleadas", WaveLogic.waveCount("Nada") == 0)
local growing = true
local previous = 0
for wave = 1, #arena.Waves do
	local total = 0
	for typeId, count in arena.Waves[wave] do
		total += EnemyConfig.Types[typeId].MaxHealth * count
	end
	total *= WaveLogic.healthMultiplier(wave, 1)
	if total <= previous then
		growing = false
	end
	previous = total
end
check("cada oleada es más dura que la anterior (vida total)", growing)

print("-- Orden de aparición")
local list = WaveLogic.spawnList("Forest", 9, sequence({ 0.1, 0.9, 0.5, 0.3 }))
local counted = {}
for _, typeId in list do
	counted[typeId] = (counted[typeId] or 0) + 1
end
local exact = true
for typeId, count in arena.Waves[9] do
	if counted[typeId] ~= count then
		exact = false
	end
end
local expected = 0
for _, count in arena.Waves[9] do
	expected += count
end
check("salen exactamente los de la oleada", exact and #list == expected)
local firstBrute = table.find(list, "Barkbrute")
local lastBrute = 0
for index, typeId in list do
	if typeId == "Barkbrute" then
		lastBrute = index
	end
end
check("los fuertes no salen todos al principio (repartidos por la oleada)", firstBrute ~= nil and firstBrute > 1 and lastBrute > #list / 2)
local again = WaveLogic.spawnList("Forest", 9, sequence({ 0.1, 0.9, 0.5, 0.3 }))
local same = #again == #list
for index = 1, #list do
	if list[index] ~= again[index] then
		same = false
	end
end
check("con el mismo azar, el mismo orden", same)
check("la oleada del jefe no tiene hordas", #WaveLogic.spawnList("Forest", 10, math.random) == 0)
check("oleadas que no existen: vacías", #WaveLogic.spawnList("Forest", 0, math.random) == 0 and #WaveLogic.spawnList("Tutorial", 99, math.random) == 0 and #WaveLogic.spawnList("Nada", 11, math.random) == 0)

print("-- Modo infinito")
check("los modos con jefe tienen modo infinito; la práctica no", WaveLogic.hasEndless("Forest") and WaveLogic.hasEndless("CrystalValley") and WaveLogic.hasEndless("EmberCaldera") and not WaveLogic.hasEndless("Tutorial") and not WaveLogic.hasEndless("Nada"))
check("antes del jefe no hay oleadas infinitas", WaveLogic.endlessCounts("Forest", 9) == nil and WaveLogic.endlessCounts("Forest", 10) == nil)
local endlessOK, endlessTypesOK = true, true
for _, arenaId in { "Forest", "CrystalValley", "EmberCaldera" } do
	local count = WaveLogic.waveCount(arenaId)
	local previous = 0
	for wave = count + 1, count + 30 do
		local list = WaveLogic.spawnList(arenaId, wave, math.random)
		if #list == 0 or #list < previous then
			endlessOK = false
		end
		local k = wave - count
		if k % WaveConfig.Endless.StrongEvery ~= 0 then
			previous = #list
		end
		local zoneSpawns = EnemyConfig.Zones[WaveConfig.Arenas[arenaId].Zone].Spawns
		for _, typeId in list do
			local fromZone = false
			for _, spawn in zoneSpawns do
				fromZone = fromZone or spawn.Type == typeId
			end
			if not fromZone or EnemyConfig.Types[typeId].Kind == "Boss" then
				endlessTypesOK = false
			end
		end
	end
end
check("tras el jefe, oleadas sin fin y cada vez con más enemigos", endlessOK)
check("solo enemigos normales o fuertes de su zona", endlessTypesOK)
-- El jefe vuelve en el modo infinito cada Endless.BossEvery oleadas (pruebas con amigos)
do
	local every = WaveConfig.Endless.BossEvery
	local count = WaveLogic.waveCount("Forest")
	check("en el infinito vuelve el jefe cada BossEvery oleadas", every >= 2 and WaveLogic.isEndlessBossWave("Forest", count + every) and WaveLogic.isEndlessBossWave("Forest", count + 2 * every)
		and not WaveLogic.isEndlessBossWave("Forest", count + 1) and not WaveLogic.isEndlessBossWave("Forest", count) and not WaveLogic.isEndlessBossWave("Forest", 3))
	check("y cada vez con más vida", WaveLogic.endlessBossHealth("Forest", count + every) > 1 and WaveLogic.endlessBossHealth("Forest", count + 2 * every) > WaveLogic.endlessBossHealth("Forest", count + every)
		and WaveLogic.endlessBossHealth("Forest", count + 1) == 1)
	check("sin infinito (tutorial) nunca vuelve", not WaveLogic.isEndlessBossWave("Tutorial", 10))
end
-- Bichos a distancia (Def.Ranged) y peligros de las arenas de los jefes (Def.Hazard)
do
	local rangedOK, rangedInWaves, hazardsOK = true, {}, true
	for typeId, def in EnemyConfig.Types do
		local r = def.Ranged
		if r then
			if not (def.Kind ~= "Boss" and r.Range > def.AttackRange + 4 and (r.Keep or 0) < r.Range and r.Damage > 0 and r.Cooldown > 0 and r.Speed > 0) then
				rangedOK = false
				print("  " .. typeId .. ": Ranged raro")
			end
		end
	end
	for arenaId, mode in WaveConfig.Arenas do
		for _, counts in mode.Waves do
			for typeId in counts do
				if EnemyConfig.Types[typeId].Ranged then
					rangedInWaves[arenaId] = true
				end
			end
		end
		local boss = mode.Boss and EnemyConfig.Types[mode.Boss]
		local h = boss and boss.Hazard
		if boss and not (h and h.Interval > h.Telegraph and h.Radius > 0 and h.Damage > 0 and (h.Count or 1) >= 1) then
			hazardsOK = false
			print("  " .. arenaId .. ": su jefe no tiene peligro de arena")
		end
	end
	check("los bichos a distancia tienen alcance, daño y recarga razonables", rangedOK)
	check("hay bichos a distancia en las oleadas de cada zona", rangedInWaves.Forest and rangedInWaves.CrystalValley and rangedInWaves.EmberCaldera and rangedInWaves.FrozenTundra and rangedInWaves.DividedLands and rangedInWaves.DividedLandsCave)
	check("cada jefe de oleadas tiene su peligro de arena (avisado antes de dañar)", hazardsOK)
	-- Los lanzadores dan lo mismo que el bicho al que sustituyen: el ritmo de 💰 y 💎 no cambia
	check("los lanzadores dan el mismo botín que los bichos que sustituyen", EnemyConfig.Types.ThornCaster.Reward == EnemyConfig.Types.Thornling.Reward
		and EnemyConfig.Types.CrystalCaster.Reward == EnemyConfig.Types.Shardling.Reward and EnemyConfig.Types.EmberCaster.Reward == EnemyConfig.Types.Cinderling.Reward
		and EnemyConfig.Types.FrostCaster.Reward == EnemyConfig.Types.FrostWolf.Reward)
end
local function strongCount(arenaId, wave)
	local n = 0
	for typeId, count in WaveLogic.endlessCounts(arenaId, wave) do
		if EnemyConfig.Types[typeId].Kind == "Strong" then
			n += count
		end
	end
	return n
end
local every = WaveConfig.Endless.StrongEvery
check("cada StrongEvery oleadas, el doble de fuertes", strongCount("Forest", 10 + every) > strongCount("Forest", 10 + every - 1) * 1.5)
check("en el modo infinito siguen las mejoras cada CardEvery", WaveLogic.isCardWave("Forest", 12) and WaveLogic.isCardWave("Forest", 15) and not WaveLogic.isCardWave("Forest", 13) and not WaveLogic.isCardWave("Tutorial", 12))
check("los enemigos del modo infinito tienen cada vez más vida", WaveLogic.healthMultiplier(20, 1) > WaveLogic.healthMultiplier(11, 1))
local e11 = WaveLogic.clearReward(11, "Forest")
local e20 = WaveLogic.clearReward(20, "Forest")
check("y dan cada vez más premio", e20 > e11)

print("-- Récords")
local records = WaveLogic.emptyRecords()
check("récords vacíos", records.Cleared == 0 and next(records.Best) == nil and WaveLogic.bestWave(records, "Forest") == 0)
check("superar la 1 del Bosque: récord nuevo", WaveLogic.recordWave(records, "Forest", 1) == true and records.Cleared == 1 and WaveLogic.bestWave(records, "Forest") == 1)
check("superar la 2: récord nuevo", WaveLogic.recordWave(records, "Forest", 2) == true and WaveLogic.bestWave(records, "Forest") == 2)
check("otra partida que se queda en la 1: suma, pero no es récord", WaveLogic.recordWave(records, "Forest", 1) == false and records.Cleared == 3 and WaveLogic.bestWave(records, "Forest") == 2)
check("cada modo tiene su récord", WaveLogic.recordWave(records, "CrystalValley", 1) == true and WaveLogic.bestWave(records, "Forest") == 2 and WaveLogic.bestWave(records, "CrystalValley") == 1)
check("el modo infinito cuenta (oleada 14)", WaveLogic.recordWave(records, "Forest", 14) == true and WaveLogic.bestWave(records, "Forest") == 14)
check("la práctica del tutorial y lo raro no cuentan", WaveLogic.recordWave(records, "Tutorial", 3) == false and WaveLogic.recordWave(records, "Nada", 3) == false and WaveLogic.recordWave(records, "Forest", 0 / 0) == false and records.Cleared == 5)
local clean = WaveLogic.sanitizeRecords({ Cleared = 0 / 0, Best = { Forest = 12.7, Bad = -3, [5] = 2, Valley = "x" } })
check("guardado roto: se sanea (sin NaN, negativos ni claves raras)", clean.Cleared == 0 and clean.Best.Forest == 12 and clean.Best.Bad == nil and clean.Best[5] == nil and clean.Best.Valley == nil)
check("sin datos: vacíos; y siempre una tabla nueva", WaveLogic.sanitizeRecords(nil).Cleared == 0 and WaveLogic.sanitizeRecords("x").Cleared == 0 and WaveLogic.serializeRecords(records) ~= records and WaveLogic.serializeRecords(records).Best.Forest == 14)

print("-- Dificultad y premios")
check("oleada 1 en solitario: vida normal", near(WaveLogic.healthMultiplier(1, 1), 1))
check("más vida en oleadas más altas", WaveLogic.healthMultiplier(5, 1) > WaveLogic.healthMultiplier(4, 1))
check("más vida con más jugadores", WaveLogic.healthMultiplier(3, 3) > WaveLogic.healthMultiplier(3, 1))
check("valores raros cuentan como 1", near(WaveLogic.healthMultiplier(0 / 0, -5), 1))
check("el jefe tiene más vida con más jugadores", WaveLogic.bossHealthMultiplier(1) == 1 and WaveLogic.bossHealthMultiplier(2) > 1)
check("botín normal en la oleada 1 y más después", near(WaveLogic.rewardMultiplier(1), 1) and WaveLogic.rewardMultiplier(9) > 1)
local clearE, clearM = WaveLogic.clearReward(3)
check("premio por oleada: crece con la oleada (los 💎 los multiplica después el servicio)", clearE == WaveConfig.ClearDiamonds * 3 and clearM > 0 and WaveLogic.clearReward(6) > clearE)
local winE, winM = WaveLogic.victoryReward()
check("premio de victoria fijo", winE == WaveConfig.VictoryDiamonds and winM == WaveConfig.VictoryMoney)
check("mejoras tras la 3, la 6 y la 9 (no tras la 10)", WaveLogic.isCardWave("Forest", 3) and WaveLogic.isCardWave("Forest", 6) and WaveLogic.isCardWave("Forest", 9) and not WaveLogic.isCardWave("Forest", 10) and not WaveLogic.isCardWave("Forest", 1))

print("-- Mejoras")
local ordersOK, effectsOK = true, true
local seen = {}
local effectKeys = { "Damage", "Cooldown", "Chain", "Splash", "Twin", "Explode", "Loot", "Heal", "StreakSeconds", "Armor", "BossDamage" }
for cardId, card in WaveConfig.Cards do
	if seen[card.Order] or type(card.Name) ~= "string" or type(card.Text) ~= "string" or type(card.Icon) ~= "string" or not (card.MaxLevel >= 1) then
		ordersOK = false
	end
	seen[card.Order] = true
	local hasEffect = false
	for _, key in effectKeys do
		if card[key] ~= nil then
			hasEffect = true
		end
	end
	if not hasEffect then
		effectsOK = false
	end
end
check("cada mejora tiene nombre, icono, texto, nivel máximo y su sitio", ordersOK)
check("cada mejora hace algo", effectsOK)
local cards = WaveLogic.rollCards({}, sequence({ 0.2, 0.7, 0.4 }), 3)
check("se ofrecen 3 mejoras distintas", #cards == 3 and cards[1] ~= cards[2] and cards[2] ~= cards[3] and cards[1] ~= cards[3])
local maxed = {}
local keep = { "Fury", "Greed" }
for cardId, card in WaveConfig.Cards do
	if not table.find(keep, cardId) then
		maxed[cardId] = card.MaxLevel
	end
end
local few = WaveLogic.rollCards(maxed, math.random, 3)
check("las mejoras al máximo no se ofrecen", #few == 2 and table.find(few, "Fury") ~= nil and table.find(few, "Greed") ~= nil)
for cardId in WaveConfig.Cards do
	maxed[cardId] = 99
end
check("con todo al máximo no se ofrece nada", #WaveLogic.rollCards(maxed, math.random, 3) == 0)
local levels = {}
check("elegir una mejora la sube", WaveLogic.pick(levels, "Fury") and levels.Fury == 1)
WaveLogic.pick(levels, "Fury")
WaveLogic.pick(levels, "Fury")
check("no pasa de su nivel máximo", not WaveLogic.pick(levels, "Fury") and levels.Fury == 3)
check("mejoras que no existen o datos raros: nada", not WaveLogic.pick(levels, "Trampa") and not WaveLogic.pick(levels, 5) and not WaveLogic.pick(levels, nil))

local plain = WaveLogic.modifiers({})
check("sin mejoras, todo igual", plain.Damage == 1 and plain.Cooldown == 1 and plain.Chain == 0 and plain.Splash == nil and plain.Twin == 0 and plain.Explode == nil and plain.Loot == 1 and plain.Heal == 0 and plain.StreakSeconds == 0)
local mods = WaveLogic.modifiers({ Fury = 2, Trigger = 2, Bounce = 3, Blast = 2, Twin = 3, Detonate = 1, Greed = 1, Vampire = 2, LongStreak = 1 })
check("Furia x2: +50 % de daño", near(mods.Damage, 1.5))
check("Gatillo fácil x2: 0.85² del tiempo entre disparos", near(mods.Cooldown, 0.85 * 0.85))
check("Rebote x3: 3 saltos más", mods.Chain == 3)
check("Estallido x2: radio 7 al 40 %", mods.Splash ~= nil and mods.Splash.Radius == 7 and near(mods.Splash.Fraction, 0.4))
check("Doble disparo x3: 75 %", near(mods.Twin, 0.75))
check("Reacción en cadena: explosión al matar", mods.Explode ~= nil and mods.Explode.Radius > 0 and mods.Explode.ShotMultiplier > 0)
check("Codicia, Vampiro y Racha larga", near(mods.Loot, 1.3) and mods.Heal == 6 and mods.StreakSeconds == 1)
local clamped = WaveLogic.modifiers({ Fury = 50, Twin = 0 / 0, Greed = -3 })
check("niveles de más se quedan en el máximo y los raros no cuentan", near(clamped.Damage, 1 + 0.25 * 3) and clamped.Twin == 0 and clamped.Loot == 1)

print("-- Cartas raras, épicas y de clase")
local rarityOK, styleOK = true, true
local styles = { Weapons = 0, Warrior = 0, Fists = 0, Magic = 0 }
for cardId, card in WaveConfig.Cards do
	if card.Rarity ~= nil and not WaveConfig.CardRarity[card.Rarity] then
		rarityOK = false
	end
	if card.Style ~= nil then
		if styles[card.Style] == nil then
			styleOK = false
		else
			styles[card.Style] += 1
		end
	end
end
for _, count in styles do
	styleOK = styleOK and count >= 1
end
check("cada carta tiene una rareza que existe", rarityOK and WaveConfig.CardRarity.Common.Weight > WaveConfig.CardRarity.Rare.Weight and WaveConfig.CardRarity.Rare.Weight > WaveConfig.CardRarity.Epic.Weight)
check("cada estilo tiene al menos una carta de clase", styleOK)
local function lcg(seed)
	local state = seed
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end
local function countRolls(options, filter)
	local rng = lcg(12345)
	local hits, total = 0, 0
	for _ = 1, 400 do
		for _, cardId in WaveLogic.rollCards({}, rng, 3, options) do
			total += 1
			if filter(WaveConfig.Cards[cardId], cardId) then
				hits += 1
			end
		end
	end
	return hits, total
end
local classForOther = countRolls({ Style = "Magic" }, function(card) return card.Style ~= nil and card.Style ~= "Magic" end)
local ownClass = countRolls({ Style = "Magic" }, function(card) return card.Style == "Magic" end)
local noStyle = countRolls(nil, function(card) return card.Style ~= nil end)
check("las de clase solo salen a su estilo (y sin estilo, ninguna)", classForOther == 0 and ownClass > 0 and noStyle == 0)
local rareNormal = countRolls({ Style = "Magic" }, function(card) return (card.Rarity or "Common") ~= "Common" end)
local rareLucky = countRolls({ Style = "Magic", RareBoost = 3 }, function(card) return (card.Rarity or "Common") ~= "Common" end)
check("las raras y épicas salen menos que las comunes, y con Suerte bastante más", rareNormal > 0 and rareLucky > rareNormal * 1.4)
local epic = countRolls(nil, function(card) return card.Rarity == "Epic" end)
local common = countRolls(nil, function(card) return (card.Rarity or "Common") == "Common" end)
check("las épicas son las que menos salen", epic > 0 and epic * 4 < common)
local extra = WaveLogic.modifiers({ Tough = 2, Glass = 1, Hunter = 2, Crusher = 1, Blast = 1, Whirl = 2 })
check("Piel dura ×2 y Cañón de cristal: 0,9² · 1,3 del daño recibido", near(extra.Armor, 0.9 * 0.9 * 1.3) and near(extra.Damage, 1 + 0.6 + 0.1))
check("Cazajefes ×2 y Puño demoledor: +85 % a los jefes", near(extra.BossDamage, 1 + 0.3 * 2 + 0.25))
check("Estallido y Torbellino juntos: el radio y la fracción más grandes", extra.Splash ~= nil and extra.Splash.Radius == 9 and near(extra.Splash.Fraction, 0.5))
check("sin cartas nuevas, ni armadura ni daño a jefes", plain.Armor == 1 and plain.BossDamage == 1)

print("-- Modificadores de la partida")
local mutatorsOK = true
local weightSum = WaveConfig.MutatorNoneWeight
local rewardSum = WaveConfig.MutatorNoneWeight
local allowedKeys = { Order = true, Weight = true, Icon = true, Name = true, Text = true, Health = true, Damage = true, BossHealth = true, CountScale = true, EliteBonus = true, ClearHeal = true, CardEvery = true, RareBoost = true, Reward = true, VictoryBonus = true }
for mutatorId, mutator in WaveConfig.Mutators do
	for key in mutator do
		if not allowedKeys[key] then
			mutatorsOK = false
			print("  clave rara en el modificador " .. mutatorId .. ": " .. key)
		end
	end
	if type(mutator.Icon) ~= "string" or type(mutator.Name) ~= "string" or type(mutator.Text) ~= "string" or not (mutator.Weight > 0) then
		mutatorsOK = false
	end
	weightSum += mutator.Weight
	rewardSum += mutator.Weight * (mutator.Reward or 1)
end
check("cada modificador tiene nombre, icono, texto, peso y solo efectos que existen", mutatorsOK and #WaveLogic.mutatorOrder() >= 6)
check("de media los modificadores no inflan los premios (≤ +30 %)", rewardSum / weightSum <= 1.3)
check("la práctica del tutorial nunca lleva modificador", WaveLogic.rollMutator("Tutorial", sequence({ 0.5 })) == nil)
local seenMutators, noneSeen = {}, false
local mrng = lcg(777)
for _ = 1, 600 do
	local id = WaveLogic.rollMutator("Forest", mrng)
	if id then
		seenMutators[id] = true
	else
		noneSeen = true
	end
end
local allSeen = noneSeen
for mutatorId in WaveConfig.Mutators do
	allSeen = allSeen and seenMutators[mutatorId] == true
end
check("salen todos los modificadores (y a veces ninguno)", allSeen)
local fx = WaveLogic.runEffects("Hard", "Horde")
check("Difícil + Marea: se multiplican", near(fx.Health, 1.8 * 0.7) and near(fx.CountScale, 1.5) and near(fx.Reward, 1.75 * 1.3) and near(fx.Damage, 1.4) and fx.ClearHeal == nil)
local calm = WaveLogic.runEffects("Normal", nil)
check("Normal sin modificador: nada cambia", calm.Health == 1 and calm.Damage == 1 and calm.Reward == 1 and calm.EliteBonus == 0 and calm.CardEvery == nil and calm.ClearHeal == nil and calm.VictoryBonus == 1)
local restless = WaveLogic.runEffects("Nightmare", "Restless")
check("Pesadilla + Sin respiro: sin cura y más élites", restless.ClearHeal == 0 and near(restless.EliteBonus, 0.1) and near(restless.Reward, 2.75 * 1.45))
check("Suerte: mejoras cada 2 oleadas", WaveLogic.isCardWave("Forest", 2, WaveLogic.runEffects("Normal", "Lucky").CardEvery) and WaveLogic.isCardWave("Forest", 4, 2) and not WaveLogic.isCardWave("Forest", 3, 2) and not WaveLogic.isCardWave("Tutorial", 1, 1))
check("Élites: también en el Bosque (que no tiene)", WaveLogic.isElite("Forest", 0.1, 0.15) and not WaveLogic.isElite("Forest", 0.2, 0.15) and not WaveLogic.isElite("Tutorial", 0, 0.5))
local baseList = WaveLogic.spawnList("Forest", 9, sequence({ 0.5 }))
local hordeList = WaveLogic.spawnList("Forest", 9, sequence({ 0.5 }), 1.5)
check("Marea: un 50 % más de bichos", #hordeList >= math.floor(#baseList * 1.4) and #hordeList <= math.ceil(#baseList * 1.6) + 2)
check("las etiquetas de la partida", WaveLogic.runTags("Hard", "Horde") == "🌊 Marea · 🔥 Difícil" and WaveLogic.runTags("Normal", nil) == "")

print("-- Dificultades")
local diffs = WaveConfig.Difficulties
check("Normal, Difícil y Pesadilla, cada una pide la anterior", #diffs.Order == 3 and diffs.Order[1] == "Normal" and diffs.Hard.Requires == "Normal" and diffs.Nightmare.Requires == "Hard")
check("más difícil = más vida, más daño y más premio", diffs.Nightmare.Health > diffs.Hard.Health and diffs.Hard.Health > 1 and diffs.Nightmare.Reward > diffs.Hard.Reward and diffs.Hard.Reward > 1 and diffs.Nightmare.Damage > diffs.Hard.Damage)
check("los premios suben menos que la vida (no se hace más rentable sin más)", diffs.Hard.Reward < diffs.Hard.Health * diffs.Hard.Damage and diffs.Nightmare.Reward < diffs.Nightmare.Health)
check("dificultades solo en los modos con jefe (no la práctica)", WaveLogic.hasDifficulties("Forest") and not WaveLogic.hasDifficulties("Tutorial") and WaveLogic.difficultyOf("Tutorial", "Hard") == "Normal" and WaveLogic.difficultyOf("Forest", "Trampa") == "Normal" and WaveLogic.difficultyOf("Forest", "Nightmare") == "Nightmare")
check("cada dificultad guarda su récord aparte", WaveLogic.recordKey("Forest", "Normal") == "Forest" and WaveLogic.recordKey("Forest", "Hard") == "Forest@Hard" and WaveLogic.recordKey("Forest", nil) == "Forest")
local dr = WaveLogic.emptyRecords()
local forestWaves = WaveLogic.waveCount("Forest")
check("al principio solo Normal", WaveLogic.isDifficultyUnlocked(dr, "Forest", "Normal") and not WaveLogic.isDifficultyUnlocked(dr, "Forest", "Hard") and not WaveLogic.isDifficultyUnlocked(dr, "Forest", "Nightmare"))
WaveLogic.recordWave(dr, "Forest", forestWaves - 1)
check("sin ganar (sin el jefe) aún no se abre Difícil", not WaveLogic.isDifficultyUnlocked(dr, "Forest", "Hard"))
WaveLogic.recordWave(dr, "Forest", forestWaves)
check("ganar la Normal abre la Difícil (solo de ese modo)", WaveLogic.isDifficultyUnlocked(dr, "Forest", "Hard") and not WaveLogic.isDifficultyUnlocked(dr, "Forest", "Nightmare") and not WaveLogic.isDifficultyUnlocked(dr, "CrystalValley", "Hard"))
check("el récord en Difícil va aparte y suma a las superadas", WaveLogic.recordWave(dr, "Forest", 3, "Hard") == true and WaveLogic.bestWave(dr, "Forest@Hard") == 3 and WaveLogic.bestWave(dr, "Forest") == forestWaves and dr.Cleared == 3)
WaveLogic.recordWave(dr, "Forest", forestWaves, "Hard")
check("ganar la Difícil abre la Pesadilla", WaveLogic.isDifficultyUnlocked(dr, "Forest", "Nightmare"))
local saved = WaveLogic.sanitizeRecords(dr)
check("los récords por dificultad se guardan", WaveLogic.bestWave(saved, "Forest@Hard") == forestWaves and WaveLogic.isDifficultyUnlocked(saved, "Forest", "Nightmare"))

print("-- Racha")
local streak = WaveLogic.newStreak()
local window = WaveConfig.Streak.Window
check("el primer enemigo empieza la racha", WaveLogic.streakKill(streak, 10, 0) == 1)
WaveLogic.streakKill(streak, 10 + window * 0.5, 0)
check("matar dentro de la ventana la sube", WaveLogic.streakKill(streak, 10 + window, 0) == 3 and WaveLogic.streakCount(streak, 10 + window) == 3)
check("se acaba si pasa la ventana sin matar", WaveLogic.streakCount(streak, 10 + window * 2 + 0.1) == 0)
check("y vuelve a empezar desde 1", WaveLogic.streakKill(streak, 100, 0) == 1 and streak.Best == 3)
WaveLogic.streakKill(streak, 200, 2)
check("la Racha larga alarga la ventana", WaveLogic.streakCount(streak, 200 + window + 1.5) == 1 and WaveLogic.streakCount(streak, 200 + window + 2.5) == 0)
check("multiplicador: ×1 hasta 9, ×1.1 con 10, ×2 con 100 y no más", near(WaveLogic.streakMultiplier(9), 1) and near(WaveLogic.streakMultiplier(10), 1.1) and near(WaveLogic.streakMultiplier(100), 2) and near(WaveLogic.streakMultiplier(5000), 2))
check("racha rara: ×1", near(WaveLogic.streakMultiplier(0 / 0), 1) and near(WaveLogic.streakMultiplier(-4), 1))

print("-- Botín de cada enemigo")
check("orbe dorado cuando toca", WaveLogic.rollGolden(sequence({ 0 }), false) and not WaveLogic.rollGolden(sequence({ 0.99 }), false))
check("los jefes nunca sueltan orbe dorado", not WaveLogic.rollGolden(sequence({ 0 }), true))
check("el orbe dorado multiplica el botín", WaveLogic.goldenMultiplier(true) == WaveConfig.GoldenOrb.Multiplier and WaveLogic.goldenMultiplier(false) == 1)
-- 💎 de cada enemigo: por su tipo y su zona (EconomyConfig), NO por el 💰 que da
local smallForest = WaveLogic.killDiamonds("Normal", "Forest")
check(("💎 de un pequeño del Bosque: %.3f (1 de cada %d)"):format(smallForest, math.floor(1 / smallForest + 0.5)), near(smallForest, EconomyConfig.KillDiamonds.Normal) and smallForest < 0.1)
check("un mediano da más que un pequeño y un élite ×EliteDiamonds", WaveLogic.killDiamonds("Strong", "Forest") > smallForest
	and near(WaveLogic.killDiamonds("Normal", "Forest", true), smallForest * EconomyConfig.EliteDiamonds))
check("zonas más altas dan algo más, pero poco (no ×5 como el 💰)", WaveLogic.killDiamonds("Normal", "DividedLands") > WaveLogic.killDiamonds("Normal", "CrystalValley")
	and WaveLogic.killDiamonds("Normal", "DividedLands") <= smallForest * 6)
check("con varios jugadores, cada uno su parte", near(WaveLogic.killDiamonds("Strong", "Forest", false, 0.5), WaveLogic.killDiamonds("Strong", "Forest") / 2))
check("los jefes no dan 💎 por golpe (dan su DiamondReward aparte)", WaveLogic.killDiamonds("Boss", "Forest") == 0)
check("valores raros dan 0", WaveLogic.killDiamonds(nil, "Forest") == 0 and WaveLogic.killDiamonds("Nope", "Forest") == 0 and WaveLogic.killDiamonds("Normal", "Forest", false, 0 / 0) == 0)

print("-- Sonidos de la partida")
local soundsOK, soundCount = true, 0
for name, spec in WaveConfig.Sounds do
	soundCount += 1
	local id = type(spec) == "table" and spec.Id
	local okId = type(id) == "string" and (string.match(id, "^rbxassetid://%d+$") ~= nil or string.match(id, "^rbxasset://sounds/") ~= nil)
	local okVolume = type(spec.Volume) == "number" and spec.Volume > 0 and spec.Volume <= 1
	local okPitch = spec.Pitch == nil or (type(spec.Pitch) == "number" and spec.Pitch > 0.2 and spec.Pitch < 3)
	if not (okId and okVolume and okPitch) then
		soundsOK = false
		print("   sonido mal configurado: " .. tostring(name))
	end
end
check("cada sonido tiene Id de Roblox, volumen 0..1 y tono razonable", soundsOK)
local usedSounds = { "Tick", "Whoosh", "WaveHit", "Cleared", "CardsOpen", "Chime", "Pick", "BossGong", "BossRoar", "Victory", "Record", "Endless", "EndlessEnd", "Defeat" }
local missing = {}
for _, name in usedSounds do
	if WaveConfig.Sounds[name] == nil then
		table.insert(missing, name)
	end
end
check("están todos los que usa el cliente (" .. soundCount .. ")" .. (if #missing > 0 then ": faltan " .. table.concat(missing, ", ") else ""), #missing == 0)

print("-- Ritmo de los 💎 (pruebas con amigos: sobraban y se mejoraba todo en una tarde)")
-- 💎 de una partida ganada de cada modo (valor esperado, sin pases ni pociones): los bichos,
-- el premio de cada oleada, el de victoria y el jefe (o sus dos mitades).
local function runDiamonds(arenaId: string): (number, number)
	local arena = WaveConfig.Arenas[arenaId]
	local diamonds, money = 0, 0
	for w = 1, WaveLogic.waveCount(arenaId) do
		if not WaveLogic.isBossWave(arenaId, w) then
			for _, typeId in WaveLogic.spawnList(arenaId, w, function() return 0.5 end) do
				local def = EnemyConfig.Types[typeId]
				diamonds += WaveLogic.killDiamonds(def.Kind, arena.Zone)
				money += def.Reward * WaveLogic.rewardMultiplier(w) * WaveConfig.MoneyMultiplier
			end
			local d, m = WaveLogic.clearReward(w, arenaId)
			diamonds += d
			money += m
		end
	end
	local vd, vm = WaveLogic.victoryReward(arenaId)
	diamonds += vd
	money += vm + (if arena.Chest then arena.Chest.Money else 0)
	local boss = EnemyConfig.Types[arena.Boss]
	if boss and boss.Split then
		for _, half in boss.Split.Into do
			diamonds += EnemyConfig.Types[half].DiamondReward or 0
		end
	elseif boss then
		diamonds += boss.DiamondReward or 0
	end
	return diamonds, money
end
local ranges = {
	{ "Forest", 8, 25 },
	{ "CrystalValley", 15, 40 },
	{ "EmberCaldera", 30, 80 },
	{ "FrozenTundra", 55, 140 },
	{ "DividedLands", 70, 180 },
	{ "DividedLandsCave", 90, 220 },
}
local paceOK, report = true, {}
for _, entry in ranges do
	local d = runDiamonds(entry[1])
	table.insert(report, ("%s %d"):format(entry[1], d))
	paceOK = paceOK and d >= entry[2] and d <= entry[3]
end
print("  💎 por partida ganada: " .. table.concat(report, " · "))
check("cada partida ganada da pocos 💎 (de ~15 en el Bosque a ~150 en el Mundo 2)", paceOK)
local forestD = runDiamonds("Forest")
check("la 2.ª clase (200 💎) pide varias partidas del Bosque, no una", forestD * 6 < 200)
local caveD, caveM = runDiamonds("DividedLandsCave")
local _, forestM = runDiamonds("Forest")
check("de la primera a la última zona el 💰 crece mucho más que los 💎", caveM / forestM > 10 * (caveD / forestD))

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
