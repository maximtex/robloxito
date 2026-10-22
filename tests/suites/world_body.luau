-- Mundo vivo: ciclo de día y noche (DayNight), cofres escondidos (RewardLogic +
-- ChestConfig) y cauce del río (WildsConfig).

local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end

local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 1e-6)
end

-- 1. Día y noche ----------------------------------------------------------------------------
local settings = WorldConfig.DayNight
local cycle = settings.CycleMinutes * 60
check("día y noche: activado y con ciclo de varios minutos", DayNight.enabled() and cycle >= 600)
check("día y noche: la fracción del ciclo da la vuelta", near(DayNight.phase(0), 0) and near(DayNight.phase(cycle), 0) and near(DayNight.phase(cycle * 2.5), 0.5))
check("día y noche: horas de los tramos (7 h, 17 h, 19,4 h, 4,6 h)", near(DayNight.clockAtPhase(0), 7) and near(DayNight.clockAtPhase(0.6), 17) and near(DayNight.clockAtPhase(0.7), 19.4) and near(DayNight.clockAtPhase(0.88), 4.6, 1e-4) and near(DayNight.clockAtPhase(1), 7))
local smoothOk, previous = true, DayNight.clockAtPhase(0)
local dayTime, deepNight = 0, 0
local steps = 2000
for step = 1, steps do
	local clock = DayNight.clockAtPhase(step / steps)
	local delta = ((clock - previous + 12) % 24) - 12
	if delta < 0 or delta > 0.2 then
		smoothOk = false
	end
	previous = clock
	local night = DayNight.nightFactor(clock)
	if night == 0 then
		dayTime += 1
	elseif night == 1 then
		deepNight += 1
	end
end
check("día y noche: la hora siempre avanza, sin saltos", smoothOk)
check(("día y noche: el día ocupa más de la mitad del ciclo (%d%%) y la noche cerrada poco (%d%%)"):format(dayTime * 100 // steps, deepNight * 100 // steps), dayTime / steps > 0.55 and deepNight / steps < 0.25 and deepNight > 0)
check("día y noche: de noche 1, a mediodía 0, al atardecer en medio", DayNight.nightFactor(12) == 0 and DayNight.nightFactor(0) == 1 and DayNight.nightFactor(18) > 0 and DayNight.nightFactor(18) < 1 and DayNight.nightFactor(6) > 0 and DayNight.nightFactor(6) < 1)
local day = { OutdoorAmbient = WorldConfig.Lighting.OutdoorAmbient, Ambient = WorldConfig.Lighting.Ambient }
local noon = DayNight.lighting(cycle * 0.3, day)
local midnight = DayNight.lighting(cycle * 0.79, day)
check("día y noche: de día la luz del juego; de noche la luz de luna", noon.Night == 0 and near(noon.OutdoorAmbient.R, day.OutdoorAmbient.R) and midnight.Night == 1 and near(midnight.OutdoorAmbient.B, settings.NightOutdoorAmbient.B))
check("día y noche: la Caldera tiene su luz fija; el Bosque no", DayNight.isFixedZone("EmberCaldera") and not DayNight.isFixedZone("Forest") and not DayNight.isFixedZone(nil))
local nightOutdoor = settings.NightOutdoorAmbient
check("día y noche: la noche no es negra (se sigue viendo)", nightOutdoor.R + nightOutdoor.G + nightOutdoor.B > 1)

-- 2. Cofres: guardado ---------------------------------------------------------------------
local clean = RewardLogic.sanitize({ Chests = { Waterfall = 1000.7, Ruins = -5, [12] = 300, Bad = "x", Nan = 0 / 0, [string.rep("a", 40)] = 500 } })
check("cofres: se guardan esperas válidas y se descarta lo raro", clean.Chests.Waterfall == 1000 and clean.Chests.Ruins == nil and clean.Chests[12] == nil and clean.Chests.Bad == nil and clean.Chests.Nan == nil and clean.Chests[string.rep("a", 40)] == nil)
local many = {}
for index = 1, 100 do
	many["C" .. index] = 1000
end
local count = 0
for _ in RewardLogic.sanitize({ Chests = many }).Chests do
	count += 1
end
check("cofres: como mucho 64 guardados", count == 64)
check("cofres: registro viejo sin cofres -> vacío", next(RewardLogic.sanitize({ Streak = 2 }).Chests) == nil and next(RewardLogic.empty().Chests) == nil)
local saved = RewardLogic.serialize(clean)
saved.Chests.Waterfall = 1
check("cofres: serializar copia (no comparte la tabla)", clean.Chests.Waterfall == 1000)

-- 3. Cofres: abrir --------------------------------------------------------------------------
local cooldown = ChestConfig.Cooldown
local data = RewardLogic.empty()
local now = 1_800_000_000
local code, readyAt = RewardLogic.openChest(data, "Waterfall", now, cooldown)
check("cofres: el primero se abre y marca la espera", code == "Success" and readyAt == now + cooldown and data.Chests.Waterfall == now + cooldown)
code = RewardLogic.openChest(data, "Waterfall", now + 60, cooldown)
check("cofres: no se abre otra vez durante la espera", code == "ChestCooldown")
check("cofres: otro cofre sí se abre", (RewardLogic.openChest(data, "Ruins", now + 60, cooldown)) == "Success")
code = RewardLogic.openChest(data, "Waterfall", now + cooldown, cooldown)
check("cofres: pasada la espera se vuelve a abrir", code == "Success")
local skewed = RewardLogic.empty()
skewed.Chests.Pond = now + cooldown * 10
check("cofres: una marca imposible (reloj adelantado) no lo bloquea para siempre", RewardLogic.canOpenChest(skewed, "Pond", now, cooldown) and (RewardLogic.openChest(skewed, "Pond", now, cooldown)) == "Success")
local ids = {}
for _, chest in ChestConfig.Chests do
	table.insert(ids, chest.Id)
end
local state = RewardLogic.chestState(data, ids, now + cooldown + 100, cooldown)
check("cofres: el estado lista solo los que esperan", state.Waterfall ~= nil and state.Ruins == nil and state.Pond == nil)

-- 4. Cofres: configuración ------------------------------------------------------------------
local unique, rewardsOk, namesOk = true, true, true
local seen = {}
for _, chest in ChestConfig.Chests do
	if seen[chest.Id] or #chest.Id > 32 then
		unique = false
	end
	seen[chest.Id] = true
	local reward = chest.Reward
	if not (reward and reward.Energy and reward.Energy.Minutes > 0 and reward.Energy.Min > 0) then
		rewardsOk = false
	end
	for blessingId, amount in (reward and reward.Blessings) or {} do
		if not AdventureConfig.Blessings[blessingId] or amount < 1 then
			rewardsOk = false
		end
	end
	if type(chest.Name) ~= "string" or chest.Name == "" or ChestConfig.get(chest.Id) ~= chest then
		namesOk = false
	end
end
check(("cofres: %d cofres con nombre e id único"):format(#ChestConfig.Chests), unique and namesOk and #ChestConfig.Chests >= 6)
check("cofres: premios de energía y bendiciones que existen", rewardsOk)
check("cofres: espera de horas y distancia de apertura razonable", cooldown >= 3600 and ChestConfig.OpenDistance >= ChestConfig.PromptDistance and ChestConfig.get("Nada") == nil and ChestConfig.get(5) == nil)

-- 5. Río -------------------------------------------------------------------------------------
local river = WildsConfig.River
local samples = WildsConfig.riverSamples(river.Step)
local first, last = river.Points[1], river.Points[#river.Points]
local spacingOk = true
for index = 2, #samples do
	local a, b = samples[index - 1], samples[index]
	if math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) > river.Step + 1e-6 or b.Distance < a.Distance then
		spacingOk = false
	end
end
check(("río: %d cortes, del primer punto al último, sin huecos"):format(#samples), spacingOk and near(samples[1].X, first.X) and near(samples[1].Z, first.Y) and near(samples[#samples].X, last.X) and near(samples[#samples].Z, last.Y))
local widthOk = true
for _, sample in samples do
	local width = WildsConfig.riverWidthAt(sample.Distance)
	if width < river.Width - 1.8 or width > river.Width + 1.8 then
		widthOk = false
	end
	if WildsConfig.distanceToRiver(sample.X, sample.Z) > 1e-6 then
		widthOk = false
	end
end
check("río: ancho natural (varía poco) y los cortes van sobre el cauce", widthOk)
local fall = WildsConfig.Waterfall
local lake = WildsConfig.Lake
check("río: nace en la poza de la cascada y acaba en el lago", near(first.X, fall.Pool.Center.X) and near(first.Y, fall.Pool.Center.Y) and math.sqrt((last.X - lake.Center.X) ^ 2 + (last.Y - lake.Center.Y) ^ 2) < lake.Radius)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
