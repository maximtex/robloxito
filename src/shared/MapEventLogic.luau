-- Lógica pura de los eventos del mapa (MapEventConfig): qué evento sale, en qué zona y dónde,
-- qué bichos trae la invasión, cómo de fuerte es el goblin del tesoro y cuánto se gana. Sin
-- APIs de Roblox (batería "mapevents"); el azar llega como rng() en [0, 1).

local MapEventConfig = require(script.Parent.Config.MapEventConfig)
local EnemyConfig = require(script.Parent.Config.EnemyConfig)
local ZoneConfig = require(script.Parent.Config.ZoneConfig)
local EconomyConfig = require(script.Parent.Config.EconomyConfig)

local MapEventLogic = {}

local function positive(value: any): number
	return if type(value) == "number" and value == value and value > 0 and value < math.huge then value else 0
end

local function pick(list: { any }, rng: () -> number): any
	if #list == 0 then
		return nil
	end
	return list[math.clamp(math.floor(rng() * #list) + 1, 1, #list)]
end

-- Tipos de evento en su orden.
function MapEventLogic.kindOrder(): { string }
	local ids = {}
	for kindId in MapEventConfig.Kinds do
		table.insert(ids, kindId)
	end
	table.sort(ids, function(a, b)
		return MapEventConfig.Kinds[a].Order < MapEventConfig.Kinds[b].Order
	end)
	return ids
end

-- Un tipo de evento al azar según su Weight.
function MapEventLogic.rollKind(rng: () -> number): string
	local order = MapEventLogic.kindOrder()
	local total = 0
	for _, kindId in order do
		total += positive(MapEventConfig.Kinds[kindId].Weight)
	end
	local target = math.clamp(rng(), 0, 0.999999) * total
	for _, kindId in order do
		local weight = positive(MapEventConfig.Kinds[kindId].Weight)
		if target < weight then
			return kindId
		end
		target -= weight
	end
	return order[#order]
end

-- Zona del evento: una de MapEventConfig.Zones con alguien dentro (`present`: zona -> true);
-- si no hay, una que alguien tenga abierta (`unlocked`). nil si ninguna.
function MapEventLogic.pickZone(present: { [string]: boolean }, unlocked: { [string]: boolean }, rng: () -> number): string?
	local withPlayers, open = {}, {}
	for _, zoneId in MapEventConfig.Zones do
		if EnemyConfig.Zones[zoneId] and ZoneConfig.Zones[zoneId] then
			if present[zoneId] then
				table.insert(withPlayers, zoneId)
			end
			if unlocked[zoneId] then
				table.insert(open, zoneId)
			end
		end
	end
	return pick(if #withPlayers > 0 then withPlayers else open, rng)
end

-- Sitios de los bichos de la zona en el mapa (sin los de su cueva, que está lejos):
-- desplazamientos relativos al centro de la zona, en el suelo y lejos de sus zonas seguras.
function MapEventLogic.spots(zoneId: string): { Vector2 }
	local zone = EnemyConfig.Zones[zoneId]
	local list = {}
	for _, spawn in (zone and zone.Spawns) or {} do
		if math.abs(spawn.Offset.X) < 400 then
			table.insert(list, spawn.Offset)
		end
	end
	return list
end

-- Punto del evento (relativo al centro de la zona), o nil si la zona no tiene sitios.
function MapEventLogic.pickSpot(zoneId: string, rng: () -> number): Vector2?
	return pick(MapEventLogic.spots(zoneId), rng)
end

-- Tipos de bicho de la zona en el mapa, por clase (Normal / Strong).
local function typesOf(zoneId: string): ({ string }, { string })
	local normal, strong, seen = {}, {}, {}
	local zone = EnemyConfig.Zones[zoneId]
	for _, spawn in (zone and zone.Spawns) or {} do
		local def = EnemyConfig.Types[spawn.Type]
		if def and math.abs(spawn.Offset.X) < 400 and not seen[spawn.Type] then
			seen[spawn.Type] = true
			if def.Kind == "Strong" then
				table.insert(strong, spawn.Type)
			elseif def.Kind == "Normal" then
				table.insert(normal, spawn.Type)
			end
		end
	end
	table.sort(normal)
	table.sort(strong)
	return normal, strong
end

-- Bichos de una invasión: Count de los normales de la zona, uno fuerte cada StrongEvery (si
-- la zona tiene). Vacía si la zona no tiene bichos normales.
function MapEventLogic.invasionList(zoneId: string, rng: () -> number): { string }
	local settings = MapEventConfig.Kinds.Invasion
	local normal, strong = typesOf(zoneId)
	local list = {}
	if #normal == 0 then
		return list
	end
	for index = 1, math.floor(positive(settings.Count)) do
		if #strong > 0 and settings.StrongEvery and index % settings.StrongEvery == 0 then
			table.insert(list, pick(strong, rng))
		else
			table.insert(list, pick(normal, rng))
		end
	end
	return list
end

-- Vida y botín del goblin del tesoro en una zona: multiplicadores sobre los suyos para que
-- tenga HealthFactor veces la vida media de los normales de la zona y RewardFactor veces su
-- botín medio.
function MapEventLogic.goblinScale(zoneId: string): (number, number)
	local settings = MapEventConfig.Kinds.TreasureGoblin
	local def = EnemyConfig.Types[settings.TypeId]
	local normal = typesOf(zoneId)
	if not def or #normal == 0 then
		return 1, 1
	end
	local health, reward = 0, 0
	for _, typeId in normal do
		health += positive(EnemyConfig.Types[typeId].MaxHealth)
		reward += positive(EnemyConfig.Types[typeId].Reward)
	end
	health /= #normal
	reward /= #normal
	return math.max(0.1, health * positive(settings.HealthFactor) / math.max(1, def.MaxHealth)),
		math.max(0.1, reward * positive(settings.RewardFactor) / math.max(1, def.Reward))
end

-- Premio de un evento (o de una gema, con la lluvia) en una zona: (💰, 💎 con decimales).
function MapEventLogic.reward(kindId: string, zoneId: string): (number, number)
	local kind = MapEventConfig.Kinds[kindId]
	local zone = ZoneConfig.Zones[zoneId]
	if not (kind and zone and kind.Reward) then
		return 0, 0
	end
	local perMinute = positive(zone.MoneyPerMinute)
	local tier = positive(EconomyConfig.DiamondTier[zoneId] or 1)
	if tier == 0 then
		tier = 1
	end
	return math.floor(perMinute * positive(kind.Reward.Money)), positive(kind.Reward.Diamonds) * tier
end

-- Segundos hasta el siguiente evento (entre Interval.Min y Interval.Max).
function MapEventLogic.nextDelay(rng: () -> number): number
	local interval = MapEventConfig.Interval
	return interval.Min + math.clamp(rng(), 0, 1) * (interval.Max - interval.Min)
end

return MapEventLogic
