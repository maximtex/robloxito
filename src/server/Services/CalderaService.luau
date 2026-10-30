-- Construye la Caldera de Brasas (Zona 3) pegada directamente tras el Valle Morado
-- (sin puente intermedio), con el mismo estilo de bloques que el Bosque (StudWorld):
-- - Suelo en damero volcánico naranja / terracota con los cuadritos del diseño, caminos de
--   ceniza con borde (StudFloor.Zones.EmberCaldera). Empieza donde acaba el muro sur del Valle.
-- - Muros perimetrales de damero volcánico con remate naranja (fin del corredor: sin paso).
-- - Lago de lava (CalderaConfig.LavaLake), árboles de brasas junto a los muros, formaciones de
--   obsidiana con vetas de lava, pozas de lava y piedras de brasa por el damero.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CalderaConfig = require(Shared.Config.CalderaConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local StudFloor = require(Shared.Util.StudFloor)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local StudWorld = require(script.Parent.Parent.Util.StudWorld)
local StudProps = require(script.Parent.Parent.Util.StudProps)

local CalderaService = {}

local CENTER_2D = ZoneConfig.Zones.EmberCaldera.Center
local ORIGIN = Vector3.new(GeneratorConfig.Position.X + CENTER_2D.X, 0, GeneratorConfig.Position.Z + CENTER_2D.Y)
local CALDERA = StudFloor.Zones.EmberCaldera
local COLORS = CalderaConfig.Colors

-- Árboles de brasas: tronco carbonizado y copa naranja
local EMBER_TREE_COLORS = {
	Trunk = Color3.fromRGB(74, 52, 46),
	LeafLight = Color3.fromRGB(240, 128, 40),
	LeafDark = Color3.fromRGB(214, 84, 32),
}

local function world(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- Basalto por debajo del suelo, desde el muro sur del Valle hasta el fondo de la Caldera
local function buildFlatTerrain()
	local half = CalderaConfig.Terrain.Size / 2
	StudWorld.fillTerrainBelow(-half, half, CALDERA.MinZ, ORIGIN.Z + half, Enum.Material.Basalt)
end

-- Charco de lava cuadrado sobre el suelo con su borde de basalto (como el de los caminos)
local function buildLavaPool(parent: Instance, name: string, center: Vector3, size: number)
	local border = StudFloor.BorderWidth
	local top = StudWorld.FloorTop
	local m = Instance.new("Model")
	m.Name = name
	PartFactory.part(m, "Lava", {
		Size = Vector3.new(size - 2 * border, 0.2, size - 2 * border),
		CFrame = CFrame.new(center.X, top - 0.04, center.Z),
		Color = COLORS.Lava,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	for _, side in { -1, 1 } do
		PartFactory.part(m, "Borde", {
			Size = Vector3.new(size, 0.2, border),
			CFrame = CFrame.new(center.X, top - 0.04, center.Z + side * (size - border) / 2),
			Color = CALDERA.Colors.Border,
			Material = Enum.Material.Plastic,
			Solid = false,
		})
		PartFactory.part(m, "Borde", {
			Size = Vector3.new(border, 0.2, size - 2 * border),
			CFrame = CFrame.new(center.X + side * (size - border) / 2, top - 0.04, center.Z),
			Color = CALDERA.Colors.Border,
			Material = Enum.Material.Plastic,
			Solid = false,
		})
	end
	m.Parent = parent
	return m
end

-- Lago de lava grande con rocas de basalto con studs alrededor
local function buildLavaLake(parent: Instance)
	local lake = CalderaConfig.LavaLake
	local center = world(lake.Center.X, 0, lake.Center.Y)
	local size = lake.Radius * 2 + 4
	local m = buildLavaPool(parent, "LavaLake", center, size)
	for index, spec in {
		{ X = -1, Z = -1, H = 4.5 },
		{ X = 1, Z = -1, H = 3 },
		{ X = -1, Z = 1, H = 2.5 },
		{ X = 1, Z = 1, H = 5 },
	} do
		local pos = center + Vector3.new(spec.X * (size / 2 + 1), 0, spec.Z * (size / 2 + 1))
		StudWorld.allStuds(PartFactory.part(m, "Roca" .. index, {
			Size = Vector3.new(5, spec.H, 5),
			CFrame = CFrame.new(pos.X, StudWorld.FloorTop + spec.H / 2, pos.Z) * CFrame.Angles(0, math.rad(index * 23), 0),
			Color = COLORS.Rock,
			Material = Enum.Material.Plastic,
			Solid = true,
		}))
	end
end

-- Formación de obsidiana: tres bloques oscuros inclinados con una veta de lava
local function buildObsidian(parent: Instance, pos: Vector3, yawDeg: number, scale: number)
	local m = Instance.new("Model")
	m.Name = "ObsidianCluster"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	for index, spec in {
		{ Offset = Vector3.new(0, 3.2, 0), Size = Vector3.new(2.6, 6.4, 2.6), Tilt = CFrame.Angles(math.rad(6), 0, math.rad(-7)) },
		{ Offset = Vector3.new(-1.9, 2.0, 1.0), Size = Vector3.new(1.9, 4.0, 1.9), Tilt = CFrame.Angles(math.rad(-12), 0, math.rad(20)) },
		{ Offset = Vector3.new(1.8, 2.2, -0.9), Size = Vector3.new(2.0, 4.4, 2.0), Tilt = CFrame.Angles(math.rad(14), 0, math.rad(-18)) },
	} do
		PartFactory.part(m, "Obsidiana" .. index, {
			Size = spec.Size * scale,
			CFrame = cf * CFrame.new(spec.Offset * scale) * spec.Tilt * CFrame.Angles(0, math.rad(45), 0),
			Color = COLORS.Obsidian[index],
			Material = Enum.Material.SmoothPlastic,
			Solid = index == 1,
		})
	end
	PartFactory.part(m, "Veta", {
		Size = Vector3.new(0.5, 5.2, 0.5) * scale,
		CFrame = cf * CFrame.new(Vector3.new(0.9, 3.0, -0.9) * scale) * CFrame.Angles(math.rad(6), 0, math.rad(-7)),
		Color = COLORS.LavaBright,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	m.Parent = parent
end

-- Piedra de brasa: bloque de basalto con studs y un brillo de lava encima
local function buildEmberRock(parent: Instance, pos: Vector3, yawDeg: number)
	local m = Instance.new("Model")
	m.Name = "EmberRock"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	StudWorld.allStuds(PartFactory.part(m, "Roca", {
		Size = Vector3.new(2.6, 1.4, 2.2),
		CFrame = cf * CFrame.new(0, 0.7, 0),
		Color = COLORS.Rock,
		Material = Enum.Material.Plastic,
		Solid = false,
	}))
	PartFactory.part(m, "Brasa", {
		Size = Vector3.new(1.2, 0.5, 1.0),
		CFrame = cf * CFrame.new(0.3, 1.5, 0.1),
		Color = COLORS.LavaBright,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	m.Parent = parent
end

-- Lava del canal (Hill.Channel, OverSteps): las terrazas quedan completas y la lava baja
-- escalón por escalón por encima de ellas, del más alto hacia el cráter. Al oeste llega al
-- suelo y sigue por un canal hasta el lago (con un puentecito donde la cruza la ronda); al
-- este cae a un pozo sobre el primer escalón. Al lado del Corazón de la Caldera, dos medias
-- lunas de lava.
local function lavaStrip(parent: Instance, name: string, x0: number, x1: number, z0: number, z1: number)
	local border = StudFloor.BorderWidth
	local top = StudWorld.FloorTop
	local m = Instance.new("Model")
	m.Name = name
	PartFactory.part(m, "Lava", {
		Size = Vector3.new(x1 - x0, 0.2, z1 - z0 - 2 * border),
		CFrame = CFrame.new((x0 + x1) / 2, top - 0.04, (z0 + z1) / 2),
		Color = COLORS.Lava,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	for _, z in { z0 + border / 2, z1 - border / 2 } do
		PartFactory.part(m, "Borde", {
			Size = Vector3.new(x1 - x0, 0.2, border),
			CFrame = CFrame.new((x0 + x1) / 2, top - 0.04, z),
			Color = CALDERA.Colors.Border,
			Material = Enum.Material.Plastic,
			Solid = false,
		})
	end
	m.Parent = parent
	return m
end

-- Medio ancho del suelo jugable a la altura z (fila de CALDERA.Outline)
local function floorHalfWidthAt(z: number): number
	for _, row in CALDERA.Outline do
		if z >= row[1] and z < row[2] then
			return row[3]
		end
	end
	return CALDERA.MaxX
end

-- Columnas de terraza que caen dentro del canal en un lado (side: -1 oeste, 1 este), de la
-- más cercana al suelo a la más lejana: { X, Top } con la altura de la cara de arriba.
local function channelColumns(tops: { { Position: Vector3, Ring: number } }, side: number)
	local channel = CALDERA.Hill.Channel
	local byX = {}
	for _, cell in tops do
		local p = cell.Position
		if p.Z > channel.MinZ and p.Z < channel.MaxZ and math.sign(p.X) == side then
			byX[p.X] = math.max(byX[p.X] or -math.huge, p.Y)
		end
	end
	local cols = {}
	for x, top in byX do
		table.insert(cols, { X = x, Top = top })
	end
	table.sort(cols, function(a, b)
		return math.abs(a.X) < math.abs(b.X)
	end)
	return cols
end

-- Brillo y chispas suaves donde cae la lava
local function addSplash(part: BasePart)
	local glow = Instance.new("PointLight")
	glow.Color = COLORS.LavaBright
	glow.Range = 16
	glow.Brightness = 1
	glow.Parent = part
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Chispas"
	sparks.Texture = "rbxasset://textures/particles/fire_main.dds"
	sparks.Color = ColorSequence.new(COLORS.LavaBright, COLORS.Lava)
	sparks.Size = NumberSequence.new(1.5, 0)
	sparks.Lifetime = NumberRange.new(0.5, 1)
	sparks.Rate = 6
	sparks.Speed = NumberRange.new(2, 5)
	sparks.SpreadAngle = Vector2.new(35, 35)
	sparks.Parent = part
end

-- Cascada escalonada: en cada columna una lámina de lava encima del escalón y otra pegada al
-- frente que mira al cráter (lo que cae al escalón de abajo), en tramos cortos para que el neón
-- no se vea como un rayo. skipFirst: el primer escalón no lleva lava (el pozo del este).
-- Devuelve la lámina que cae más abajo.
local FALL_COLOR = Color3.fromRGB(232, 92, 28)
local function buildSteppedFall(folder: Instance, name: string, cols, side: number, midZ: number, width: number, skipFirst: boolean): BasePart?
	local B = StudFloor.Wall.BlockWidth
	local m = Instance.new("Model")
	m.Name = name
	local prevTop = StudWorld.FloorTop
	local lowest = nil
	for index, col in cols do
		if not (skipFirst and index == 1) then
			PartFactory.part(m, "Lava" .. index, {
				Size = Vector3.new(B, 0.2, width),
				CFrame = CFrame.new(col.X, col.Top + 0.06, midZ),
				Color = COLORS.Lava,
				Material = Enum.Material.Neon,
				Solid = false,
			})
		end
		local drop = col.Top - prevTop
		if drop > 0.5 and not (skipFirst and index == 1) then
			local fall = PartFactory.part(m, "Cae" .. index, {
				Size = Vector3.new(0.3, drop + 0.2, width),
				CFrame = CFrame.new(col.X - side * (B / 2 + 0.15), (col.Top + prevTop) / 2 + 0.1, midZ),
				Color = FALL_COLOR,
				Material = Enum.Material.Neon,
				Solid = false,
			})
			lowest = lowest or fall
		end
		prevTop = col.Top
	end
	-- Boca de roca arriba del todo, de donde sale la lava
	local last = cols[#cols]
	if last then
		StudWorld.allStuds(PartFactory.part(m, "Boca", {
			Size = Vector3.new(3, 5, width + 4),
			CFrame = CFrame.new(last.X + side * (B / 2 - 1.5), last.Top + 2.5, midZ),
			Color = COLORS.Rock,
			Material = Enum.Material.Plastic,
			Solid = true,
		}))
	end
	m.Parent = folder
	return lowest
end

local function buildLavaFlows(parent: Instance, tops: { { Position: Vector3, Ring: number } })
	local folder = PartFactory.folder(parent, "LavaFlows")
	local hill = CALDERA.Hill
	local channel = hill.Channel
	local top = StudWorld.FloorTop
	local midZ = (channel.MinZ + channel.MaxZ) / 2
	local width = channel.MaxZ - channel.MinZ - 2 * StudFloor.BorderWidth
	local lake = CalderaConfig.LavaLake
	local lakeCenter = world(lake.Center.X, 0, lake.Center.Y)
	local lakeEdge = lakeCenter.X - (lake.Radius + 2)

	-- Oeste: la lava baja por los escalones hasta el suelo y sigue por el canal hasta el lago
	local edge = floorHalfWidthAt(midZ)
	lavaStrip(folder, "CanalOeste", -edge, lakeEdge, channel.MinZ, channel.MaxZ)
	local westFall = buildSteppedFall(folder, "CascadaOeste", channelColumns(tops, -1), -1, midZ, width, false)
	if westFall then
		addSplash(westFall)
	end

	-- Este: baja por los escalones y cae a un pozo encima del primero (no llega al suelo)
	local eastCols = channelColumns(tops, 1)
	buildSteppedFall(folder, "CascadaEste", eastCols, 1, midZ, width, true)
	local first = eastCols[1]
	if first then
		local B = StudFloor.Wall.BlockWidth
		local border = StudFloor.BorderWidth
		local front = first.X - B / 2 -- borde del escalón que mira al cráter
		local length = channel.MaxZ - channel.MinZ + 12
		local y = first.Top + 0.06
		local pool = Instance.new("Model")
		pool.Name = "PozoEste"
		local lava = PartFactory.part(pool, "Lava", {
			Size = Vector3.new(B - border, 0.2, length - 2 * border),
			CFrame = CFrame.new(front + border + (B - border) / 2, y, midZ),
			Color = COLORS.Lava,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		PartFactory.part(pool, "Borde", {
			Size = Vector3.new(border, 0.6, length),
			CFrame = CFrame.new(front + border / 2, first.Top + 0.3, midZ),
			Color = CALDERA.Colors.Border,
			Material = Enum.Material.Plastic,
			Solid = false,
		})
		for _, s in { -1, 1 } do
			PartFactory.part(pool, "Borde", {
				Size = Vector3.new(B - border, 0.6, border),
				CFrame = CFrame.new(front + border + (B - border) / 2, first.Top + 0.3, midZ + s * (length - border) / 2),
				Color = CALDERA.Colors.Border,
				Material = Enum.Material.Plastic,
				Solid = false,
			})
		end
		addSplash(lava)
		pool.Parent = folder
	end

	-- Puentecito de piedra donde la ronda oeste cruza el canal
	for _, path in CALDERA.Paths do
		local px0, px1, pz0, pz1 = path[1], path[2], path[3], path[4]
		if px1 <= lakeEdge and px0 >= CALDERA.MinX and pz0 < channel.MinZ and pz1 > channel.MaxZ then
			StudWorld.allStuds(PartFactory.part(folder, "Puentecito", {
				Size = Vector3.new(px1 - px0, 1.2, channel.MaxZ - channel.MinZ + 4),
				CFrame = CFrame.new((px0 + px1) / 2, top + 0.6, midZ),
				Color = CALDERA.Colors.Path,
				Material = Enum.Material.Plastic,
				Solid = true,
			}))
		end
	end

	-- Medias lunas de lava a los lados del Corazón de la Caldera (arena del jefe)
	local arena = EnemyConfig.Zones.EmberCaldera.Boss.Arena
	local center = world(arena.Center.X, 0, arena.Center.Y)
	local radius = arena.Radius + 9
	local from, to, steps = math.rad(-55), math.rad(10), 9
	for _, side in { -1, 1 } do
		for step = 0, steps - 1 do
			local a0 = from + (to - from) * step / steps
			local a1 = from + (to - from) * (step + 1) / steps
			local mid = (a0 + a1) / 2
			local pos = Vector3.new(center.X + side * radius * math.cos(mid), top + 0.05, center.Z + radius * math.sin(mid))
			local length = 2 * radius * math.sin((a1 - a0) / 2) + 0.6
			PartFactory.part(folder, "MediaLuna", {
				Size = Vector3.new(4, 0.25, length),
				CFrame = CFrame.lookAt(pos, pos + Vector3.new(-side * math.sin(mid), 0, math.cos(mid))),
				Color = COLORS.Lava,
				Material = Enum.Material.Neon,
				Solid = false,
			})
		end
	end
end

-- Sobre los escalones: picos de obsidiana arriba (4 y 5) y árboles de brasas abajo (1 y 2),
-- repartidos siempre igual (una de cada pocas casillas), nada encima ni al lado de la lava que
-- baja. Grietas de lava: una línea fina al pie de cada escalón (1 a 3), justo donde empieza el
-- siguiente, siguiendo el borde de las terrazas.
local function buildTerraceDecor(parent: Instance, tops: { { Position: Vector3, Ring: number } })
	local folder = PartFactory.folder(parent, "TerraceDecor")
	local rng = Random.new(CALDERA.DecorSeed + 7)
	local B = StudFloor.Wall.BlockWidth
	local channel = CALDERA.Hill.Channel
	local midZ = (channel.MinZ + channel.MaxZ) / 2
	local half = (channel.MaxZ - channel.MinZ) / 2
	local heightAt = {}
	for _, cell in tops do
		heightAt[math.round(cell.Position.X / B) .. "," .. math.round(cell.Position.Z / B)] = cell.Position.Y
	end
	local SIDES = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	for index, cell in tops do
		local p = cell.Position
		local dz = math.abs(p.Z - midZ)
		if dz >= half + B then
			if cell.Ring >= 4 and index % 5 == 0 then
				buildObsidian(folder, p, rng:NextNumber(0, 360), rng:NextNumber(1.0, 1.6))
			elseif cell.Ring <= 2 and index % 11 == 0 then
				StudWorld.buildBlockyTree(folder, p, rng:NextNumber(0, 360), rng:NextNumber(0.75, 0.95), EMBER_TREE_COLORS)
			end
		end
		if cell.Ring <= 3 and dz >= half then
			local i, j = math.round(p.X / B), math.round(p.Z / B)
			for _, d in SIDES do
				local nh = heightAt[(i + d[1]) .. "," .. (j + d[2])]
				if nh and nh > p.Y + 0.5 then
					PartFactory.part(folder, "Grieta", {
						Size = if d[1] ~= 0 then Vector3.new(0.5, 0.15, B) else Vector3.new(B, 0.15, 0.5),
						CFrame = CFrame.new(p + Vector3.new(d[1] * (B / 2 - 0.4), 0.08, d[2] * (B / 2 - 0.4))),
						Color = COLORS.Lava,
						Material = Enum.Material.Neon,
						Solid = false,
					})
				end
			end
		end
	end
end

-- Árboles de brasas junto a los muros, el lago de lava, obsidiana, pozas y brasas
local function buildDecor(parent: Instance)
	local folder = PartFactory.folder(parent, "MapDetails")
	local lake = CalderaConfig.LavaLake
	local lakeCenter = world(lake.Center.X, 0, lake.Center.Y)
	local keepOut = { { lakeCenter.X, lakeCenter.Z, lake.Radius + 8 } }
	-- Nada encima del canal de lava ni junto a las medias lunas del jefe
	local channel = CALDERA.Hill.Channel
	for x = CALDERA.MinX, lakeCenter.X, 10 do
		table.insert(keepOut, { x, (channel.MinZ + channel.MaxZ) / 2, 12 })
	end
	local arena = EnemyConfig.Zones.EmberCaldera.Boss.Arena
	local arenaCenter = world(arena.Center.X, 0, arena.Center.Y)
	table.insert(keepOut, { arenaCenter.X, arenaCenter.Z, arena.Radius + 14 })
	local decor = StudWorld.newDecor(CALDERA, "EmberCaldera", keepOut)
	local rng = decor.Rng

	buildLavaLake(folder)
	decor.wallRow(22, 9, 12, function(pos, yaw)
		StudWorld.buildBlockyTree(folder, pos, yaw, rng:NextNumber(0.95, 1.2), EMBER_TREE_COLORS)
	end)
	decor.scatter(14, 4, math.huge, 10, function(pos, yaw)
		buildObsidian(folder, pos, yaw, rng:NextNumber(0.8, 1.3))
	end)
	decor.scatter(6, 6, math.huge, 10, function(pos)
		buildLavaPool(folder, "LavaPool", pos, 10)
	end)
	decor.scatter(28, 2, math.huge, 4, function(pos, yaw)
		buildEmberRock(folder, pos, yaw)
	end)
	-- Braseros volcánicos en la avenida y transición helada junto al portal sur hacia la Tundra
	local top = StudWorld.FloorTop
	for _, zOff in { -108, -44, 38 } do
		for _, side in { -1, 1 } do
			local p = world(side * 16, top, zOff)
			StudWorld.allStuds(PartFactory.part(folder, "BrazierBase", {
				Size = Vector3.new(2.4, 3.2, 2.4),
				CFrame = CFrame.new(p + Vector3.new(0, 1.6, 0)),
				Color = COLORS.Rock,
				Material = Enum.Material.Plastic,
				Solid = true,
			}))
			PartFactory.part(folder, "BrazierFlame", {
				Size = Vector3.new(1.6, 1.4, 1.6),
				CFrame = CFrame.new(p + Vector3.new(0, 3.8, 0)) * CFrame.Angles(0, math.rad(45), 0),
				Color = COLORS.LavaBright,
				Material = Enum.Material.Neon,
				Solid = false,
			})
		end
	end
	for _, side in { -1, 1 } do
		local gatePos = world(side * 15, top, 145)
		PartFactory.part(folder, "TundraTransitionIce", {
			Size = Vector3.new(2.2, 5.2, 2.2),
			CFrame = CFrame.new(gatePos + Vector3.new(0, 2.6, 0)) * CFrame.Angles(math.rad(10), math.rad(45), math.rad(-side * 12)),
			Color = Color3.fromRGB(165, 222, 255),
			Material = Enum.Material.Glass,
			Solid = true,
		})
	end
end

function CalderaService.start()
	PartFactory.removeExisting(workspace, CalderaConfig.ModelName)
	buildFlatTerrain()

	local model = Instance.new("Model")
	model.Name = CalderaConfig.ModelName
	StudWorld.buildFloor(model, CALDERA)
	local tops = StudWorld.buildWalls(model, CALDERA)
	buildLavaFlows(model, tops or {})
	buildDecor(model)
	if tops then
		buildTerraceDecor(model, tops)
	end
	-- Todo en estilo studs, como el spawn (menos lo que brilla)
	StudProps.studifyMap(model)
	model.Parent = workspace
end

return CalderaService
