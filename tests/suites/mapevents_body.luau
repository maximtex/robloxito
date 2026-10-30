local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function sequence(values)
	local index = 0
	return function()
		index = index % #values + 1
		return values[index]
	end
end
local function lcg(seed)
	local state = seed
	return function()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end

print("-- Configuración")
local kindsOK = true
for kindId, kind in MapEventConfig.Kinds do
	if type(kind.Icon) ~= "string" or type(kind.Name) ~= "string" or type(kind.Text) ~= "string" or not (kind.Weight > 0) or not (kind.Duration > 0) or type(kind.Reward) ~= "table" then
		kindsOK = false
		print("  evento raro: " .. kindId)
	end
	if not kind.Text:find("%%s") then
		kindsOK = false
		print("  el texto de " .. kindId .. " no dice la zona")
	end
end
check("cada evento tiene icono, nombre, texto con la zona, peso, duración y premio", kindsOK and #MapEventLogic.kindOrder() == 3)
local zonesOK = true
for _, zoneId in MapEventConfig.Zones do
	zonesOK = zonesOK and ZoneConfig.Zones[zoneId] ~= nil and (ZoneConfig.Zones[zoneId].World or 1) == 1 and EnemyConfig.Zones[zoneId] ~= nil and #MapEventLogic.spots(zoneId) >= 5
end
check("solo zonas del Mundo 1 con bichos (y sitios para el evento)", zonesOK and table.find(MapEventConfig.Zones, "Forest") == nil)
local goblin = EnemyConfig.Types[MapEventConfig.Kinds.TreasureGoblin.TypeId]
check("el goblin del tesoro existe, no persigue a nadie y no es un jefe", goblin ~= nil and goblin.DetectRange == 0 and goblin.Kind ~= "Boss")
check("el reto semanal \"Aventurero\" cuenta los eventos", (function()
	for _, def in QuestConfig.Weekly do
		if def.Goal.Event == "MapEvent" then
			return true
		end
	end
	return false
end)())

print("-- Qué evento sale y dónde")
local seen = {}
local rng = lcg(99)
for _ = 1, 300 do
	seen[MapEventLogic.rollKind(rng)] = true
end
check("salen los tres eventos", seen.Invasion and seen.TreasureGoblin and seen.DiamondRain)
check("se prefiere una zona con alguien dentro", MapEventLogic.pickZone({ CrystalValley = true }, { ThornWoods = true, CrystalValley = true, EmberCaldera = true }, sequence({ 0.9 })) == "CrystalValley")
check("si no hay nadie en una zona, una que alguien tenga abierta", MapEventLogic.pickZone({ Forest = true }, { ThornWoods = true }, sequence({ 0.5 })) == "ThornWoods")
check("en el pueblo nunca hay evento y sin zonas abiertas no hay", MapEventLogic.pickZone({ Forest = true }, { Forest = true }, sequence({ 0.5 })) == nil)
local floorOK = true
local base = GeneratorConfig.Position
for _, zoneId in MapEventConfig.Zones do
	local zone = ZoneConfig.Zones[zoneId]
	local layout = StudFloor.Zones[zoneId]
	for _, spot in MapEventLogic.spots(zoneId) do
		local x, z = base.X + zone.Center.X + spot.X, base.Z + zone.Center.Y + spot.Y
		if not (layout and StudFloor.onFloor(layout, x, z, 2)) then
			floorOK = false
			print(("  sitio fuera del suelo en %s (%.0f, %.0f)"):format(zoneId, x, z))
		end
	end
end
check("los sitios de los eventos están en el suelo de su zona", floorOK)

print("-- Invasión y goblin")
local list = MapEventLogic.invasionList("ThornWoods", lcg(5))
local strong, normal = 0, 0
for _, typeId in list do
	local def = EnemyConfig.Types[typeId]
	if def.Kind == "Strong" then
		strong += 1
	elseif def.Kind == "Normal" then
		normal += 1
	end
end
check("la invasión trae los bichos de la zona, con algún fuerte", #list == MapEventConfig.Kinds.Invasion.Count and strong == math.floor(#list / MapEventConfig.Kinds.Invasion.StrongEvery) and normal + strong == #list)
local hT, rT = MapEventLogic.goblinScale("ThornWoods")
local hF, rF = MapEventLogic.goblinScale("GoblinFortress")
check("el goblin es más duro y da más en las zonas altas", hF > hT and rF > rT and hT > 0 and rT > 0)
local thornHealth = goblin.MaxHealth * hT
check("en el Bosque de Espinas tiene unas 10 veces la vida de un bicho normal", thornHealth > EnemyConfig.Types.StarterThornling.MaxHealth * 3 and thornHealth < EnemyConfig.Types.Barkbrute.MaxHealth * 10)

print("-- Premios")
local mT, dT = MapEventLogic.reward("Invasion", "ThornWoods")
local mC, dC = MapEventLogic.reward("Invasion", "EmberCaldera")
check("premio de la invasión: minutos de 💰 de la zona y unos pocos 💎", mT == ZoneConfig.Zones.ThornWoods.MoneyPerMinute * 2 and dT == 3 and mC > mT and dC > dT)
local gemMoney, gemDiamonds = MapEventLogic.reward("DiamondRain", "ThornWoods")
local rain = MapEventConfig.Kinds.DiamondRain
check("la lluvia da poco por gema y con tope no supera a la invasión en 💎 por mucho", gemDiamonds > 0 and gemDiamonds * rain.MaxPerPlayer <= dT * 2 and gemMoney >= 0)
check("evento o zona que no existen: nada", MapEventLogic.reward("Nada", "ThornWoods") == 0 and MapEventLogic.reward("Invasion", "Nada") == 0)
local delays = { MapEventLogic.nextDelay(sequence({ 0 })), MapEventLogic.nextDelay(sequence({ 1 })) }
check("entre evento y evento, entre Interval.Min y Interval.Max", delays[1] == MapEventConfig.Interval.Min and delays[2] == MapEventConfig.Interval.Max)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
