-- Distribución del paisaje (pura, sin APIs de Roblox salvo Vector2/Vector3 de la
-- configuración), para poder probarla fuera de Studio. LandscapeService construye las
-- piezas a partir de lo que calcula este módulo.
--
-- - Obstáculos de cada zona a partir de las demás configuraciones: lo que ya existe
--   (spawn, cristal, altares, jardines de huevos, portales, arenas, árboles, rocas,
--   ruinas...), las zonas de los enemigos (allí no se ponen cosas sólidas, para no
--   estorbar sus persecuciones) y los sitios de los personajes de las aventuras y de sus
--   objetos perdidos.
-- - Jardines de huevos: tramos del seto, entrada, faroles, bancos, jardineras y fuente, y
--   hacia dónde mira cada santuario.
-- - Faroles repartidos a lo largo de los caminos, alternando los lados.
-- - Colocación al azar con semilla fija (xorshift propio: mismo resultado en Roblox y en
--   las pruebas) que respeta obstáculos, caminos, límite del mapa y lo ya colocado.
-- - Montañas en anillo y segmentos del límite invisible.

local LandscapeLayout = {}

local Deps: any = nil

-- Dependencias (configuraciones). En Roblox se cargan solas; las pruebas pasan las suyas.
function LandscapeLayout.init(dependencies: any)
	Deps = dependencies
end

-- Números al azar deterministas -------------------------------------------------------------

export type Rng = { State: number }

function LandscapeLayout.rng(seed: number): any
	local rng = { State = bit32.band(math.floor(seed), 0xFFFFFFFF) }
	if rng.State == 0 then
		rng.State = 0x9E3779B9
	end
	function rng.next(self): number
		local x = self.State
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
		self.State = x
		return x / 4294967296
	end
	function rng.range(self, a: number, b: number): number
		return a + (b - a) * self:next()
	end
	function rng.int(self, a: number, b: number): number
		return math.min(b, a + math.floor((b - a + 1) * self:next()))
	end
	return rng
end

-- Geometría --------------------------------------------------------------------------------

export type Point = { X: number, Z: number }
export type Circle = { X: number, Z: number, R: number, Name: string }

-- Distancia de (x, z) al segmento a-b.
function LandscapeLayout.distanceToSegment(x: number, z: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local lengthSquared = dx * dx + dz * dz
	local t = if lengthSquared > 0 then math.clamp(((x - ax) * dx + (z - az) * dz) / lengthSquared, 0, 1) else 0
	local px, pz = ax + dx * t, az + dz * t
	return math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
end

-- Distancia al borde del camino más cercano (negativa si está encima).
function LandscapeLayout.distanceToPaths(x: number, z: number, paths: { any }): number
	local best = math.huge
	for _, path in paths do
		local points = path.Points
		for index = 1, #points - 1 do
			local a, b = points[index], points[index + 1]
			local distance = LandscapeLayout.distanceToSegment(x, z, a.X, a.Y, b.X, b.Y) - path.Width / 2
			best = math.min(best, distance)
		end
	end
	return best
end

local function circle(x: number, z: number, r: number, name: string): Circle
	return { X = x, Z = z, R = r, Name = name }
end

-- Obstáculos ---------------------------------------------------------------------------------

export type Obstacles = { Hard: { Circle }, SolidOnly: { Circle }, Paths: { any } }

-- Lo que ya hay en el Bosque (WorldConfig y compañía) y las zonas de juego.
local function forestObstacles(): Obstacles
	local World, Shrines = Deps.WorldConfig, Deps.CoreShrineConfig
	local hard, solidOnly = {}, {}
	table.insert(hard, circle(0, 0, World.Terrain.PlazaRadius + 3, "Plaza"))
	for _, zone in World.KeepClear do
		table.insert(hard, circle(zone.X, zone.Y, zone.Z, "KeepClear"))
	end
	for elementId in Shrines.Angles do
		local offset = Shrines.offset(elementId)
		table.insert(hard, circle(offset.X, offset.Y, Shrines.KeepClearRadius + 1.5, "Altar_" .. elementId))
	end
	local tree = World.AncientTree
	table.insert(hard, circle(tree.Position.X, tree.Position.Y, tree.RootReach + 2, "AncientTree"))
	for index, item in World.Trees do
		table.insert(hard, circle(item.X, item.Y, 4.5 * item.Z, "Tree" .. index))
	end
	for index, item in World.Terrain.Rocks do
		table.insert(hard, circle(item.X, item.Y, item.Z + 1.5, "Rock" .. index))
	end
	for index, item in World.RuinColumns do
		table.insert(hard, circle(item.X, item.Y, 4, "Column" .. index))
	end
	for index, item in World.MushroomClusters do
		table.insert(hard, circle(item.X, item.Y, 3, "Mushrooms" .. index))
	end
	for index, item in World.CrystalClusters do
		table.insert(hard, circle(item.X, item.Y, 2.5, "Crystals" .. index))
	end
	-- Pueblo del Renacimiento (VillageConfig): casitas, plaza, puestos, farolas...
	local paths = {}
	local village = Deps.VillageConfig
	if village then
		for _, item in village.footprints() do
			table.insert(hard, circle(item.X, item.Z, item.R, item.Name))
		end
		table.insert(paths, { Name = "VillageStreet", Width = village.Street.Width, Points = { village.Street.From, village.Street.To } })
	end
	-- Naturaleza del norte (WildsConfig): río (como un camino ancho), cascada, lago,
	-- ruinas, campamento y puente; en las praderas no van cosas sólidas (árboles, rocas).
	local wilds = Deps.WildsConfig
	if wilds then
		for _, item in wilds.footprints() do
			table.insert(hard, circle(item.X, item.Z, item.R, item.Name))
		end
		table.insert(paths, { Name = "River", Width = wilds.riverClearance(), Points = wilds.River.Points })
		for index, meadow in wilds.Meadows do
			table.insert(solidOnly, circle(meadow.Center.X, meadow.Center.Y, meadow.Radius + 2, "Meadow" .. index))
		end
	end
	-- Cofres escondidos (ChestConfig): sitio despejado alrededor.
	local chests = Deps.ChestConfig
	if chests then
		for _, chest in chests.Chests do
			table.insert(hard, circle(chest.Position.X, chest.Position.Y, LandscapeLayout.CHEST_RADIUS, "Chest_" .. chest.Id))
		end
	end
	-- Camino de tierra del spawn al pueblo
	local pathPoints = { Vector2.new(0, World.Terrain.PlazaRadius - 1), Vector2.new(0, World.Terrain.PathEndZ) }
	table.insert(paths, 1, { Name = "MainPath", Width = World.Terrain.PathWidth, Points = pathPoints })
	return { Hard = hard, SolidOnly = solidOnly, Paths = paths }
end

local function valleyObstacles(): Obstacles
	local Valley = Deps.ValleyConfig
	local hard, solidOnly = {}, {}
	for _, zone in Valley.KeepClear do
		table.insert(hard, circle(zone.X, zone.Y, zone.Z, "KeepClear"))
	end
	for index, item in Valley.Trees do
		table.insert(hard, circle(item.X, item.Y, 4.5 * item.Z, "Tree" .. index))
	end
	for index, item in Valley.CrystalClusters do
		table.insert(hard, circle(item.X, item.Y, 5 * item.Z, "Crystals" .. index))
	end
	for index, item in Valley.RuinColumns do
		table.insert(hard, circle(item.X, item.Y, 4, "Column" .. index))
	end
	table.insert(hard, circle(0, Valley.Arch.Z, 8, "Arch"))
	local paths = {}
	for index, path in Valley.Terrain.Paths do
		table.insert(paths, { Name = "ValleyPath" .. index, Width = path.Width, Points = { path.From, path.To } })
	end
	return { Hard = hard, SolidOnly = solidOnly, Paths = paths }
end

local function calderaObstacles(): Obstacles
	local Caldera = Deps.CalderaConfig
	local hard, solidOnly = {}, {}
	for _, zone in Caldera.KeepClear do
		table.insert(hard, circle(zone.X, zone.Y, zone.Z, "KeepClear"))
	end
	for index, item in Caldera.ObsidianClusters do
		table.insert(hard, circle(item.X, item.Y, 5 * item.Z, "Obsidian" .. index))
	end
	for index, vent in Caldera.Vents do
		table.insert(hard, circle(vent.X, vent.Y, 4, "Vent" .. index))
	end
	table.insert(hard, circle(0, Caldera.Arch.Z, 8, "Arch"))
	local paths = {}
	for index, path in Caldera.Terrain.Paths do
		table.insert(paths, { Name = "CalderaPath" .. index, Width = path.Width, Points = { path.From, path.To } })
	end
	return { Hard = hard, SolidOnly = solidOnly, Paths = paths }
end

-- Zonas de juego comunes: jardines y santuarios de huevos, portales, enemigos y arenas.
local function addGameplay(zoneId: string, obstacles: Obstacles)
	for _, garden in Deps.EggConfig.Gardens or {} do
		if garden.Zone == zoneId then
			table.insert(obstacles.Hard, circle(garden.Center.X, garden.Center.Y, garden.Radius + 3, "EggGarden"))
		end
	end
	for _, egg in Deps.EggConfig.Stands do
		if (egg.Zone or Deps.ZoneConfig.DefaultZone) == zoneId and egg.StandOffset then
			table.insert(obstacles.Hard, circle(egg.StandOffset.X, egg.StandOffset.Y, 8, "Egg"))
		end
	end
	for name, portal in Deps.ZoneConfig.Portals do
		if portal.Zone == zoneId then
			table.insert(obstacles.Hard, circle(portal.Offset.X, portal.Offset.Y, Deps.ZoneConfig.PortalRadius or 11, name))
		end
	end
	local zone = Deps.EnemyConfig.Zones[zoneId]
	if zone then
		for _, safe in zone.SafeZones or {} do
			table.insert(obstacles.SolidOnly, circle(safe.Center.X, safe.Center.Y, safe.Radius, "SafeZone"))
		end
		for index, spawn in zone.Spawns do
			local def = Deps.EnemyConfig.Types[spawn.Type]
			table.insert(obstacles.Hard, circle(spawn.Offset.X, spawn.Offset.Y, 4, "Spawn" .. index))
			table.insert(obstacles.SolidOnly, circle(spawn.Offset.X, spawn.Offset.Y, def.LeashRange, "Leash" .. index))
		end
		if zone.Boss then
			local arena = zone.Boss.Arena
			table.insert(obstacles.Hard, circle(arena.Center.X, arena.Center.Y, arena.Radius + 4, "Arena"))
		end
	end
	-- Personajes de las aventuras y sus objetos perdidos (sitios despejados).
	local adventure = Deps.AdventureConfig
	if adventure then
		for npcId, npc in adventure.Npcs do
			if npc.Zone == zoneId then
				table.insert(obstacles.Hard, circle(npc.Position.X, npc.Position.Y, LandscapeLayout.NPC_RADIUS, "Npc_" .. npcId))
			end
		end
		for itemId, item in adventure.Items do
			if item.Zone == zoneId then
				table.insert(obstacles.Hard, circle(item.Position.X, item.Position.Y, LandscapeLayout.ITEM_RADIUS, "Item_" .. itemId))
			end
		end
	end
end

-- Hueco que se deja alrededor de un personaje y de un objeto perdido.
LandscapeLayout.NPC_RADIUS = 5
LandscapeLayout.ITEM_RADIUS = 3
LandscapeLayout.CHEST_RADIUS = 2.5

-- Lo construido a mano por el paisaje (para que lo aleatorio no lo pise).
local function addLandmarks(settings: any, obstacles: Obstacles)
	for _, bench in settings.Benches or {} do
		table.insert(obstacles.Hard, circle(bench.X, bench.Y, 2.5, "Bench"))
	end
	for _, planter in settings.Planters or {} do
		table.insert(obstacles.Hard, circle(planter.X, planter.Y, planter.Z, "Planter"))
	end
	for _, sign in settings.Signs or {} do
		table.insert(obstacles.Hard, circle(sign.Position.X, sign.Position.Y, 2.5, "Sign"))
	end
	if settings.Pond then
		table.insert(obstacles.Hard, circle(settings.Pond.Center.X, settings.Pond.Center.Y, settings.Pond.Radius + 6, "Pond"))
	end
	if settings.MushroomGrove then
		table.insert(obstacles.Hard, circle(settings.MushroomGrove.Center.X, settings.MushroomGrove.Center.Y, settings.MushroomGrove.Radius + 5, "Grove"))
	end
	if settings.Watchtower then
		table.insert(obstacles.Hard, circle(settings.Watchtower.Position.X, settings.Watchtower.Position.Y, settings.Watchtower.Diameter / 2 + 5, "Watchtower"))
	end
	if settings.CrystalSpire then
		table.insert(obstacles.Hard, circle(settings.CrystalSpire.Position.X, settings.CrystalSpire.Position.Y, 12, "CrystalSpire"))
	end
	for index, spire in settings.Spires or {} do
		table.insert(obstacles.Hard, circle(spire.X, spire.Y, 7 * spire.Z, "Spire" .. index))
	end
	if settings.CrystalArch then
		table.insert(obstacles.Hard, circle(settings.CrystalArch.Position.X, settings.CrystalArch.Position.Y, settings.CrystalArch.Width / 2 + 3, "CrystalArch"))
	end
	if settings.CrystalPool then
		table.insert(obstacles.Hard, circle(settings.CrystalPool.Center.X, settings.CrystalPool.Center.Y, settings.CrystalPool.Radius + 5, "CrystalPool"))
	end
	if settings.FloatingCrystals then
		table.insert(obstacles.Hard, circle(settings.FloatingCrystals.Center.X, settings.FloatingCrystals.Center.Y, settings.FloatingCrystals.Radius + 3, "Floating"))
	end
end

-- Obstáculos de una zona del paisaje ("Forest", "Valley" o "Caldera").
function LandscapeLayout.obstacles(key: string): Obstacles
	local settings = Deps.LandscapeConfig[key]
	local obstacles = if key == "Forest" then forestObstacles() elseif key == "Caldera" then calderaObstacles() else valleyObstacles()
	addGameplay(settings.Zone, obstacles)
	addLandmarks(settings, obstacles)
	for _, path in settings.Paths do
		table.insert(obstacles.Paths, path)
	end
	return obstacles
end

-- ¿Está libre un punto para algo de radio `radius`? (sólido o no)
function LandscapeLayout.isFree(x: number, z: number, radius: number, solid: boolean, obstacles: Obstacles, boundaryRadius: number, placed: { any }?, pathClearance: number?): boolean
	if math.sqrt(x * x + z * z) + radius > boundaryRadius - 6 then
		return false
	end
	for _, item in obstacles.Hard do
		if (x - item.X) ^ 2 + (z - item.Z) ^ 2 < (item.R + radius) ^ 2 then
			return false
		end
	end
	if solid then
		for _, item in obstacles.SolidOnly do
			if (x - item.X) ^ 2 + (z - item.Z) ^ 2 < (item.R + radius) ^ 2 then
				return false
			end
		end
	end
	if LandscapeLayout.distanceToPaths(x, z, obstacles.Paths) < radius + (pathClearance or 1) then
		return false
	end
	if placed then
		for _, other in placed do
			if (x - other.X) ^ 2 + (z - other.Z) ^ 2 < (other.R + radius) ^ 2 then
				return false
			end
		end
	end
	return true
end

-- Jardines de huevos ---------------------------------------------------------------------------

-- Radio de la base de un santuario de huevo (EggStandService: base de 7 studs).
LandscapeLayout.STAND_RADIUS = 3.5

local function onCircle(cx: number, cz: number, radius: number, degrees: number): (number, number)
	local angle = math.rad(degrees)
	return cx + math.cos(angle) * radius, cz + math.sin(angle) * radius
end

-- Ángulo (grados, 0..360) de un punto visto desde el centro.
local function angleOf(cx: number, cz: number, x: number, z: number): number
	return math.deg(math.atan2(z - cz, x - cx)) % 360
end

-- Giro que hace mirar al centro (el -Z local de faroles y bancos) desde un ángulo dado.
local function yawToward(degrees: number): number
	local angle = math.rad(degrees)
	return math.atan2(math.cos(angle), math.sin(angle))
end

-- Santuarios activos de una zona: { Id, X, Z }, ordenados por Id.
function LandscapeLayout.standsOf(zoneId: string): { { Id: string, X: number, Z: number } }
	local result = {}
	for eggId, egg in Deps.EggConfig.Stands do
		if egg.Enabled ~= false and egg.StandOffset and (egg.Zone or Deps.ZoneConfig.DefaultZone) == zoneId then
			table.insert(result, { Id = eggId, X = egg.StandOffset.X, Z = egg.StandOffset.Y })
		end
	end
	table.sort(result, function(a, b)
		return a.Id < b.Id
	end)
	return result
end

-- Jardín (EggConfig.Gardens) de una zona, o nil.
function LandscapeLayout.gardenOf(zoneId: string): any
	for _, garden in Deps.EggConfig.Gardens or {} do
		if garden.Zone == zoneId then
			return garden
		end
	end
	return nil
end

-- Hacia dónde mira un santuario (X, Z unitario): al centro de su jardín; si está en el
-- centro, hacia la entrada; sin jardín, hacia +Z (como antes).
function LandscapeLayout.standFacing(zoneId: string, x: number, z: number): (number, number)
	local garden = LandscapeLayout.gardenOf(zoneId)
	if not garden then
		return 0, 1
	end
	local dx, dz = garden.Center.X - x, garden.Center.Y - z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance < 1 then
		local angle = math.rad(garden.Entrance)
		return math.cos(angle), math.sin(angle)
	end
	return dx / distance, dz / distance
end

-- ¿Cae un ángulo dentro del hueco de la entrada (más un margen)?
local function inGate(garden: any, style: any, degrees: number, margin: number): boolean
	local delta = math.abs(((degrees - garden.Entrance) + 180) % 360 - 180)
	return delta < style.GateHalfAngle + margin
end

local function clearOfStands(stands: { any }, x: number, z: number, radius: number): boolean
	for _, stand in stands do
		if (x - stand.X) ^ 2 + (z - stand.Z) ^ 2 < (LandscapeLayout.STAND_RADIUS + radius + 0.5) ^ 2 then
			return false
		end
	end
	return true
end

-- Distribución de un jardín: tramos del seto (o cristales), entrada, faroles, bancos,
-- jardineras y fuente, sin tocar los santuarios ni el paso de la entrada.
function LandscapeLayout.garden(zoneId: string): any
	local garden = LandscapeLayout.gardenOf(zoneId)
	if not garden then
		return nil
	end
	local style = Deps.LandscapeConfig.Gardens[garden.Style]
	local cx, cz, radius = garden.Center.X, garden.Center.Y, garden.Radius
	local stands = LandscapeLayout.standsOf(zoneId)
	local result = {
		Garden = garden,
		Style = style,
		Center = { X = cx, Z = cz },
		Radius = radius,
		Stands = {},
		Ring = {},
		Lamps = {},
		Benches = {},
		Planters = {},
		Fountain = nil,
	}
	for _, stand in stands do
		local fx, fz = LandscapeLayout.standFacing(zoneId, stand.X, stand.Z)
		table.insert(result.Stands, { Id = stand.Id, X = stand.X, Z = stand.Z, FacingX = fx, FacingZ = fz })
	end

	-- Seto o anillo de cristales: de un lado de la entrada al otro, en tramos iguales.
	local from = garden.Entrance + style.GateHalfAngle
	local span = 360 - 2 * style.GateHalfAngle
	local count = math.max(1, math.ceil(math.rad(span) * radius / style.RingSegment))
	local step = span / count
	for index = 0, count - 1 do
		local degrees = from + step * (index + 0.5)
		local x, z = onCircle(cx, cz, radius, degrees)
		table.insert(result.Ring, { X = x, Z = z, Angle = degrees % 360, Length = 2 * radius * math.sin(math.rad(step) / 2) })
	end

	-- Entrada: dos pilares a los lados del hueco; Out = dirección hacia fuera.
	local leftX, leftZ = onCircle(cx, cz, radius, garden.Entrance - style.GateHalfAngle)
	local rightX, rightZ = onCircle(cx, cz, radius, garden.Entrance + style.GateHalfAngle)
	local gateX, gateZ = onCircle(cx, cz, radius, garden.Entrance)
	local outAngle = math.rad(garden.Entrance)
	result.Gate = {
		X = gateX,
		Z = gateZ,
		Left = { X = leftX, Z = leftZ },
		Right = { X = rightX, Z = rightZ },
		OutX = math.cos(outAngle),
		OutZ = math.sin(outAngle),
		Width = math.sqrt((leftX - rightX) ^ 2 + (leftZ - rightZ) ^ 2),
	}

	-- Fuente central.
	if style.Fountain and clearOfStands(stands, cx, cz, style.Fountain.Radius + 1.5) then
		result.Fountain = { X = cx, Z = cz, R = style.Fountain.Radius }
	end

	-- Faroles y bancos a ambos lados de la entrada, mirando al centro.
	local function sides(angles: { number }, offset: number, itemRadius: number, into: { any }, degreesYaw: boolean)
		for _, delta in angles do
			for _, side in { -1, 1 } do
				local degrees = garden.Entrance + side * delta
				local x, z = onCircle(cx, cz, radius + offset, degrees)
				if not inGate(garden, style, degrees, 2) and clearOfStands(stands, x, z, itemRadius) then
					local yaw = yawToward(degrees)
					table.insert(into, { X = x, Z = z, Yaw = if degreesYaw then math.deg(yaw) else yaw, R = itemRadius })
				end
			end
		end
	end
	sides(style.LampAngles, style.LampRadius, 0.8, result.Lamps, false)
	sides(style.BenchAngles, style.BenchRadius, 2.1, result.Benches, true)

	-- Jardineras entre santuarios vecinos (no en el hueco que da a la entrada).
	if style.Planters and #stands >= 2 then
		local angles = {}
		for _, stand in stands do
			table.insert(angles, angleOf(cx, cz, stand.X, stand.Z))
		end
		table.sort(angles)
		for index = 1, #angles do
			local a = angles[index]
			local b = if index < #angles then angles[index + 1] else angles[1] + 360
			local middle = (a + b) / 2
			if b - a < 180 and not inGate(garden, style, middle, 0) then
				local x, z = onCircle(cx, cz, radius + style.PlanterRadius, middle)
				local half = style.PlanterSize * 0.75
				if clearOfStands(stands, x, z, half) then
					table.insert(result.Planters, { X = x, Z = z, Size = style.PlanterSize, R = half })
				end
			end
		end
	end
	return result
end

-- Faroles ------------------------------------------------------------------------------------

-- Puntos a lo largo de un camino cada `spacing`, desplazados `offset` a un lado (alterno).
function LandscapeLayout.alongPath(points: { any }, spacing: number, offset: number): { { X: number, Z: number, Yaw: number } }
	local result = {}
	local carried = spacing / 2
	local side = 1
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local dx, dz = b.X - a.X, b.Y - a.Y
		local length = math.sqrt(dx * dx + dz * dz)
		if length > 0 then
			local ux, uz = dx / length, dz / length
			local distance = carried
			while distance <= length do
				local px, pz = a.X + ux * distance, a.Y + uz * distance
				-- Normal a la izquierda (-uz, ux) o a la derecha.
				local nx, nz = -uz * side, ux * side
				-- Yaw: el brazo del farol (su -Z local) apunta hacia el camino.
				table.insert(result, { X = px + nx * offset, Z = pz + nz * offset, Yaw = math.atan2(nx, nz) })
				side = -side
				distance += spacing
			end
			carried = distance - length
		end
	end
	return result
end

-- Faroles válidos de una zona (sin pisar obstáculos ni otros caminos).
function LandscapeLayout.lamps(key: string, obstacles: Obstacles): { { X: number, Z: number, Yaw: number } }
	local settings = Deps.LandscapeConfig[key]
	local result = {}
	for _, path in settings.Paths do
		if path.Lamps then
			for _, lamp in LandscapeLayout.alongPath(path.Points, settings.LampSpacing, path.Width / 2 + settings.LampGap) do
				if LandscapeLayout.isFree(lamp.X, lamp.Z, 0.8, true, { Hard = obstacles.Hard, SolidOnly = {}, Paths = obstacles.Paths }, settings.BoundaryRadius, result, 0.6) then
					table.insert(result, { X = lamp.X, Z = lamp.Z, Yaw = lamp.Yaw, R = 0.8 })
				end
			end
		end
	end
	return result
end

-- Colocación al azar ---------------------------------------------------------------------------

local RADIUS_BY_KIND = { Tree = 2.2, Boulder = 1.8, Log = 2.5, Stump = 1, Bush = 1.4, MushroomPatch = 1.4, FlowerPatch = 1.2, CrystalTree = 2.2, EmberTree = 2.2, Shards = 1.2 }

-- Lista de objetos { Kind, X, Z, R, Scale, Yaw, Variant } que respeta todo lo anterior.
function LandscapeLayout.scatter(key: string, obstacles: Obstacles, avoid: { any }?): { any }
	local settings = Deps.LandscapeConfig[key]
	local rng = LandscapeLayout.rng(settings.Seed)
	local placed = {}
	for _, extra in avoid or {} do
		table.insert(placed, extra)
	end
	local result = {}
	for _, spec in settings.Scatter do
		-- Con Clusters: primero los centros de las arboledas y luego los objetos alrededor
		-- (más natural que un reparto uniforme).
		local centers = {}
		if spec.Clusters then
			local tries = 0
			while #centers < spec.Clusters and tries < spec.Clusters * 60 do
				tries += 1
				local angle = rng:range(0, math.pi * 2)
				local distance = math.sqrt(rng:range(spec.MinRadius ^ 2, spec.MaxRadius ^ 2))
				local x, z = math.cos(angle) * distance, math.sin(angle) * distance
				if LandscapeLayout.isFree(x, z, 4, spec.Solid, obstacles, settings.BoundaryRadius, nil, 2) then
					table.insert(centers, { X = x, Z = z })
				end
			end
		end
		local count, attempts = 0, 0
		while count < spec.Count and attempts < spec.Count * 40 do
			attempts += 1
			local x, z
			if #centers > 0 then
				local center = centers[rng:int(1, #centers)]
				local angle = rng:range(0, math.pi * 2)
				local distance = spec.ClusterRadius * math.sqrt(rng:next())
				x, z = center.X + math.cos(angle) * distance, center.Z + math.sin(angle) * distance
			else
				local angle = rng:range(0, math.pi * 2)
				-- Raíz cuadrada: reparto uniforme por superficie (no amontonado en el centro).
				local distance = math.sqrt(rng:range(spec.MinRadius ^ 2, spec.MaxRadius ^ 2))
				x, z = math.cos(angle) * distance, math.sin(angle) * distance
			end
			local scale = rng:range(0.8, 1.35)
			local footprint = RADIUS_BY_KIND[spec.Kind] * scale
			local variant = rng:next()
			local yaw = rng:range(0, math.pi * 2)
			if LandscapeLayout.isFree(x, z, footprint + spec.Clearance, spec.Solid, obstacles, settings.BoundaryRadius, placed, 1) then
				local item = { Kind = spec.Kind, X = x, Z = z, R = footprint, Scale = scale, Yaw = yaw, Variant = variant, Solid = spec.Solid, Mix = spec.Mix }
				table.insert(placed, item)
				table.insert(result, item)
				count += 1
			end
		end
	end
	return result
end

-- Tipo de árbol según TreeMix y el valor Variant (0..1) del objeto.
function LandscapeLayout.treeKind(mix: { [string]: number }, variant: number): string
	local order = { "Oak", "Pine", "Birch" }
	local total = 0
	for _, name in order do
		total += mix[name] or 0
	end
	local accumulated = 0
	for _, name in order do
		accumulated += (mix[name] or 0) / total
		if variant < accumulated then
			return name
		end
	end
	return order[#order]
end

-- Montañas y límite -----------------------------------------------------------------------------

function LandscapeLayout.mountains(key: string): { { X: number, Z: number, Radius: number } }
	local settings = Deps.LandscapeConfig[key]
	local spec = settings.Mountains
	local result = {}
	if not spec then
		return result
	end
	local rng = LandscapeLayout.rng(settings.Seed + 17)
	for index = 1, spec.Count do
		local angle = (index - 1) / spec.Count * math.pi * 2 + rng:range(-0.08, 0.08)
		local distance = spec.Distance + rng:range(-10, 10)
		table.insert(result, {
			X = math.cos(angle) * distance,
			Z = math.sin(angle) * distance,
			Radius = rng:range(spec.MinRadius, spec.MaxRadius),
		})
	end
	return result
end

-- Segmentos de pared del límite (anillo de radio `radius`), mirando al centro.
function LandscapeLayout.boundary(radius: number): { { X: number, Z: number, Yaw: number, Width: number, Height: number, Thickness: number } }
	local spec = Deps.LandscapeConfig.Boundary
	local result = {}
	local width = 2 * radius * math.sin(math.pi / spec.Segments) + 2 -- un poco de solape
	for index = 1, spec.Segments do
		local angle = (index - 0.5) / spec.Segments * math.pi * 2
		table.insert(result, {
			X = math.cos(angle) * radius,
			Z = math.sin(angle) * radius,
			Yaw = math.atan2(-math.cos(angle), -math.sin(angle)),
			Width = width,
			Height = spec.Height,
			Thickness = spec.Thickness,
		})
	end
	return result
end

-- Todo lo de una zona de una vez (lo usa LandscapeService).
function LandscapeLayout.compute(key: string): any
	local obstacles = LandscapeLayout.obstacles(key)
	local lamps = LandscapeLayout.lamps(key, obstacles)
	return {
		Obstacles = obstacles,
		Lamps = lamps,
		Scatter = LandscapeLayout.scatter(key, obstacles, lamps),
		Mountains = LandscapeLayout.mountains(key),
		Boundary = LandscapeLayout.boundary(Deps.LandscapeConfig[key].BoundaryRadius),
		Garden = LandscapeLayout.garden(Deps.LandscapeConfig[key].Zone),
	}
end

-- En Roblox se inicializa solo; las pruebas llaman a init con sus propias tablas.
if typeof(script) == "Instance" then
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	LandscapeLayout.init({
		LandscapeConfig = require(Shared.Config.LandscapeConfig),
		WorldConfig = require(Shared.Config.WorldConfig),
		ValleyConfig = require(Shared.Config.ValleyConfig),
		CalderaConfig = require(Shared.Config.CalderaConfig),
		CoreShrineConfig = require(Shared.Config.CoreShrineConfig),
		EggConfig = require(Shared.Config.EggConfig),
		ZoneConfig = require(Shared.Config.ZoneConfig),
		EnemyConfig = require(Shared.Config.EnemyConfig),
		AdventureConfig = require(Shared.Config.AdventureConfig),
		VillageConfig = require(Shared.Config.VillageConfig),
		WildsConfig = require(Shared.Config.WildsConfig),
		ChestConfig = require(Shared.Config.ChestConfig),
	})
end

return LandscapeLayout
