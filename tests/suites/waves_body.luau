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

print("-- El círculo de las oleadas")
local place = WaveConfig.Place
local zone = ZoneConfig.Zones[place.Zone]
check("su zona existe", zone ~= nil)
check("los enemigos salen dentro del círculo", place.SpawnRadius.Min > 0 and place.SpawnRadius.Max > place.SpawnRadius.Min and place.SpawnRadius.Max < place.AreaRadius)
check("el altar se usa desde dentro del círculo", place.PromptDistance > 0 and place.PromptDistance < place.AreaRadius)
check("el círculo cabe en su zona", math.abs(place.Offset.X) + place.AreaRadius < zone.Radius and math.abs(place.Offset.Y) + place.AreaRadius < zone.Radius)
local function distance(a, b)
	return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2)
end
local portalsClear = true
for _, portal in ZoneConfig.Portals do
	if portal.Zone == place.Zone and distance(portal.Offset, place.Offset) < place.AreaRadius + 20 then
		portalsClear = false
	end
end
check("lejos de los portales de su zona", portalsClear)
local bossArena = EnemyConfig.Zones[place.Zone] and EnemyConfig.Zones[place.Zone].Boss and EnemyConfig.Zones[place.Zone].Boss.Arena
check("no pisa la arena del jefe de la zona", bossArena == nil or distance(bossArena.Center, place.Offset) > bossArena.Radius + place.AreaRadius)
local zoneEnemies = EnemyConfig.Zones[place.Zone]
local spawnsClear = true
for _, spawn in (zoneEnemies and zoneEnemies.Spawns) or {} do
	if distance(spawn.Offset, place.Offset) <= place.AreaRadius + 10 then
		spawnsClear = false
		print("  enemigo del mundo junto al círculo: " .. spawn.Type .. " en " .. tostring(spawn.Offset))
	end
end
check("ningún enemigo del mundo sale dentro ni cerca del círculo", spawnsClear)
local guarded = false
for _, safe in (zoneEnemies and zoneEnemies.SafeZones) or {} do
	if distance(safe.Center, place.Offset) + place.AreaRadius <= safe.Radius then
		guarded = true
	end
end
check("el círculo es zona segura para los enemigos del mundo", guarded)
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
check("oleadas que no existen: vacías", #WaveLogic.spawnList("Forest", 0, math.random) == 0 and #WaveLogic.spawnList("Forest", 99, math.random) == 0)

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

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
