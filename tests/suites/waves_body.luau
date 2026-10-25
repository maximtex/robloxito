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
	-- El de la práctica del tutorial juega su modo; los demás, el de su zona (uno por zona)
	local modeOK = zone and mode and mode.Zone == spot.Zone and mode.Place == placeId
	if spot.Practice then
		modeOK = modeOK and mode.Tutorial == true
	else
		modeOK = modeOK and not mode.Tutorial
		placeCount += 1
		if placeOfZone[spot.Zone] then
			placesOK = false
			print("  dos círculos en la zona " .. spot.Zone)
		end
		placeOfZone[spot.Zone] = placeId
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
check("un círculo de oleadas en cada zona con enemigos (Bosque, Valle y Caldera)", placeCount == 3 and placeOfZone.Forest ~= nil and placeOfZone.CrystalValley ~= nil and placeOfZone.EmberCaldera ~= nil)
check("cada círculo juega el modo de su zona", placesOK)
check("los círculos caben en su zona", insideOK)
check("la llegada a cada zona queda fuera del círculo", arrivalClear)
check("lejos de los portales de su zona", portalsClear)
check("no pisan la arena del jefe de la zona", bossClear)
check("ningún enemigo del mundo sale dentro ni cerca de un círculo", spawnsClear)
check("cada círculo es zona segura para los enemigos del mundo", guardedAll)
local tutorialMode = WaveLogic.tutorialArena()
local practice = tutorialMode and WaveConfig.Places[WaveConfig.Arenas[tutorialMode].Place]
check("la práctica del tutorial se juega en su altar de la pradera del Bosque", practice ~= nil and practice.Practice == true and practice.Zone == "Forest" and not practice.Cave)
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
check("Valle y Caldera: 10 oleadas con su jefe", WaveLogic.waveCount("CrystalValley") == 10 and WaveLogic.isBossWave("CrystalValley", 10) and WaveLogic.waveCount("EmberCaldera") == 10 and WaveLogic.isBossWave("EmberCaldera", 10))
local fE, fM = WaveLogic.clearReward(3, 2, "Forest")
local vE, vM = WaveLogic.clearReward(3, 2, "CrystalValley")
local cE, cM = WaveLogic.clearReward(3, 2, "EmberCaldera")
local wE, wM = WaveLogic.victoryReward(2, "Forest")
local xE, xM = WaveLogic.victoryReward(2, "EmberCaldera")
check("las zonas altas dan más premio (limpiar y ganar)", fE < vE and vE < cE and fM < vM and vM < cM and wE < xE and wM < xM)
check("el premio sin modo es el de siempre", WaveLogic.clearReward(3, 2) == fE)

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
local practiceE, practiceM = WaveLogic.victoryReward(2, "Tutorial")
check("la práctica da un premio de victoria más pequeño", practiceE == math.floor(WaveConfig.VictoryEnergy * 2 * practice.VictoryScale) and practiceM == math.floor(WaveConfig.VictoryMoney * practice.VictoryScale) and practiceE < WaveLogic.victoryReward(2, "Forest"))
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
local e11 = WaveLogic.clearReward(11, 2, "Forest")
local e20 = WaveLogic.clearReward(20, 2, "Forest")
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
local clearE, clearM = WaveLogic.clearReward(3, 1)
local clearE2 = WaveLogic.clearReward(3, 10)
check("premio por oleada: crece con la oleada y con el poder de energía", clearE > 0 and clearM > 0 and clearE2 == clearE * 10 and WaveLogic.clearReward(6, 1) > clearE)
local winE, winM = WaveLogic.victoryReward(2)
check("premio de victoria con el poder de energía", winE == WaveConfig.VictoryEnergy * 2 and winM == WaveConfig.VictoryMoney)
check("mejoras tras la 3, la 6 y la 9 (no tras la 10)", WaveLogic.isCardWave("Forest", 3) and WaveLogic.isCardWave("Forest", 6) and WaveLogic.isCardWave("Forest", 9) and not WaveLogic.isCardWave("Forest", 10) and not WaveLogic.isCardWave("Forest", 1))

print("-- Mejoras")
local ordersOK, effectsOK = true, true
local seen = {}
local effectKeys = { "Damage", "Cooldown", "Chain", "Splash", "Twin", "Explode", "Loot", "Heal", "StreakSeconds" }
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
check("energía de un Espinillo al empezar: 35 · 0.15", near(WaveLogic.killEnergy(35, 0.15, 1), 5.25))
check("crece con el poder de energía", near(WaveLogic.killEnergy(35, 0.15, 4), 21))
check("poder por debajo de 1 cuenta como 1 y valores raros dan 0", near(WaveLogic.killEnergy(35, 0.15, 0), 5.25) and WaveLogic.killEnergy(0 / 0, 0.15, 1) == 0 and WaveLogic.killEnergy(35, -1, 1) == 0)

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

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
