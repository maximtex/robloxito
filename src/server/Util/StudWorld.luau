-- Mapas de bloques estilo simulador (suelo_muestra.glb), compartido por el Bosque, el Valle y
-- la Caldera: suelo en damero con los cuadritos del diseño, caminos y plazas con borde, muros
-- de damero y un reparto de decoración con semilla fija que no pisa caminos, enemigos ni la
-- arena del jefe. La distribución de cada zona está en Shared.Util.StudFloor.Zones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StudFloor = require(Shared.Util.StudFloor)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local PartFactory = require(script.Parent.PartFactory)

local StudWorld = {}

local GROUND = GeneratorConfig.Position.Y

-- Altura de la cara superior del suelo: base de todo lo que se pone encima
StudWorld.FloorTop = GROUND + StudFloor.BaseTop

function StudWorld.allStuds(part: BasePart): BasePart
	part.Material = Enum.Material.Plastic
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Studs
	part.FrontSurface = Enum.SurfaceType.Studs
	part.BackSurface = Enum.SurfaceType.Studs
	part.LeftSurface = Enum.SurfaceType.Studs
	part.RightSurface = Enum.SurfaceType.Studs
	return part
end

-- Terreno bajo el suelo de bloques de una zona (rectángulo en el mundo): vacía la franja de la
-- superficie y rellena por debajo, alineado a los vóxeles de 4 studs. Con el relleno a ras
-- (GeneratorConfig.TerrainFillOffset) la pizarra y el basalto asomaban entre los bloques.
function StudWorld.fillTerrainBelow(minX: number, maxX: number, minZ: number, maxZ: number, material: Enum.Material)
	local terrain = workspace.Terrain
	local center = Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2)
	terrain:FillBlock(CFrame.new(center + Vector3.new(0, 4, 0)), Vector3.new(maxX - minX, 16, maxZ - minZ), Enum.Material.Air)
	terrain:FillBlock(CFrame.new(center + Vector3.new(0, -8, 0)), Vector3.new(maxX - minX, 8, maxZ - minZ), material)
end

-- Un bloque es camino si su centro cae dentro de algún rectángulo de layout.Paths
function StudWorld.onPath(layout, x: number, z: number): boolean
	for _, r in layout.Paths do
		if x > r[1] and x < r[2] and z > r[3] and z < r[4] then
			return true
		end
	end
	return false
end

-- Distancia en planta al camino más cercano (0 si el punto está sobre un camino)
function StudWorld.distToPaths(layout, x: number, z: number): number
	local best = math.huge
	for _, r in layout.Paths do
		local dx = math.max(r[1] - x, 0, x - r[2])
		local dz = math.max(r[3] - z, 0, z - r[4])
		best = math.min(best, math.sqrt(dx * dx + dz * dz))
	end
	return best
end

-- Junta las casillas iguales (valor distinto de 0) de una rejilla en los rectángulos más
-- grandes posibles; emit(i, j, ancho, alto, valor) recibe cada uno (índices desde 1).
local function mergeRects(grid: { { number } }, cols: number, rows: number, emit: (number, number, number, number, number) -> ())
	for j = 1, rows do
		for i = 1, cols do
			local v = grid[i][j]
			if v ~= 0 then
				local w = 1
				while i + w <= cols and grid[i + w][j] == v do
					w += 1
				end
				local h = 1
				while j + h <= rows do
					local same = true
					for k = i, i + w - 1 do
						if grid[k][j + h] ~= v then
							same = false
							break
						end
					end
					if not same then
						break
					end
					h += 1
				end
				for k = i, i + w - 1 do
					for l = j, j + h - 1 do
						grid[k][l] = 0
					end
				end
				emit(i, j, w, h, v)
			end
		end
	end
end

-- Suelo: damero de losetas de 4x4 (layout.GrassTexture) en todo el mapa y, sobre los
-- caminos, su color con un borde de 1 stud donde tocan el damero, como la muestra. Los
-- caminos sobresalen StudFloor.PathRaise y el borde enseña su color en el escalón.
function StudWorld.buildFloor(parent: Instance, layout)
	local folder = PartFactory.folder(parent, StudFloor.FolderName)
	local colors = layout.Colors
	local B = StudFloor.BlockSize
	local S = StudFloor.BorderWidth
	local thickness = StudFloor.BaseThickness
	local y = StudWorld.FloorTop - thickness / 2

	-- La textura de la cara Top empieza en la esquina +X/+Z de la pieza (u = x1 - x,
	-- v = z1 - z, más OffsetStuds): con este desplazamiento queda fija al mundo, con las juntas
	-- de sus bloques en los bordes de bloque del mapa (8k ± 4), mida lo que mida cada pieza.
	-- raise: lo que sube la cara superior (crece hacia arriba, la de abajo no se mueve)
	local function makePart(name: string, x0: number, x1: number, z0: number, z1: number, color: Color3, texture: string, tile: number, raise: number): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = true
		p.CanTouch = false
		p.CastShadow = false
		p.Size = Vector3.new(x1 - x0, thickness + raise, z1 - z0)
		p.CFrame = CFrame.new((x0 + x1) / 2, y + raise / 2, (z0 + z1) / 2)
		p.Color = color
		p.Material = Enum.Material.Plastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth

		local studs = Instance.new("Texture")
		studs.Name = "Studs"
		studs.Texture = texture
		studs.Face = Enum.NormalId.Top
		studs.StudsPerTileU = tile
		studs.StudsPerTileV = tile
		studs.OffsetStudsU = (B / 2 - x1) % tile
		studs.OffsetStudsV = (B / 2 - z1) % tile
		studs.Parent = p

		p.Parent = folder
		return p
	end

	local function onPath(x: number, z: number): boolean
		return StudWorld.onPath(layout, x, z)
	end

	-- Extensión total: los límites más lo que sobresalgan los caminos (el paso de un muro)
	local minX, maxX, minZ, maxZ = layout.MinX, layout.MaxX, layout.MinZ, layout.MaxZ
	for _, r in layout.Paths do
		minX, maxX = math.min(minX, r[1]), math.max(maxX, r[2])
		minZ, maxZ = math.min(minZ, r[3]), math.max(maxZ, r[4])
	end

	-- 1. Damero: las celdas que no son camino, juntas en rectángulos con la textura del damero.
	-- Todos empiezan en un borde de bloque y miden múltiplos de 8, así que las losetas siguen
	-- de un rectángulo al siguiente.
	local cellCols = (maxX - minX) / B
	local cellRows = (maxZ - minZ) / B
	local cells: { { number } } = {}
	for i = 1, cellCols do
		cells[i] = table.create(cellRows, 0)
		local cx = minX + (i - 0.5) * B
		for j = 1, cellRows do
			local cz = minZ + (j - 0.5) * B
			local inside = cx > layout.MinX and cx < layout.MaxX and cz > layout.MinZ and cz < layout.MaxZ
			if inside and not onPath(cx, cz) then
				cells[i][j] = 1
			end
		end
	end
	local groundCount = 0
	mergeRects(cells, cellCols, cellRows, function(i, j, w, h)
		groundCount += 1
		local x0, z0 = minX + (i - 1) * B, minZ + (j - 1) * B
		makePart(("Suelo_%d"):format(groundCount), x0, x0 + w * B, z0, z0 + h * B, colors.GroundA, layout.GrassTexture, StudFloor.GrassTile, 0)
	end)

	-- 2. Caminos en una rejilla de S x S studs (1 = camino, 2 = borde). Una casilla del anillo
	-- exterior de un bloque es borde si el bloque vecino de ese lado (o de esa esquina) no es
	-- camino. Después se juntan en los rectángulos más grandes posibles.
	local cols = (maxX - minX) / S
	local rows = (maxZ - minZ) / S
	local per = B / S
	local grid: { { number } } = {}
	for i = 1, cols do
		grid[i] = table.create(rows, 0)
	end
	for cx = minX + B / 2, maxX - B / 2, B do
		for cz = minZ + B / 2, maxZ - B / 2, B do
			if onPath(cx, cz) then
				local i0 = (cx - B / 2 - minX) / S
				local j0 = (cz - B / 2 - minZ) / S
				for a = 0, per - 1 do
					local dx = if a == 0 then -1 elseif a == per - 1 then 1 else 0
					for b = 0, per - 1 do
						local dz = if b == 0 then -1 elseif b == per - 1 then 1 else 0
						local edge = (dx ~= 0 and not onPath(cx + dx * B, cz))
							or (dz ~= 0 and not onPath(cx, cz + dz * B))
							or (dx ~= 0 and dz ~= 0 and not onPath(cx + dx * B, cz + dz * B))
						grid[i0 + a + 1][j0 + b + 1] = if edge then 2 else 1
					end
				end
			end
		end
	end

	local count = 0
	mergeRects(grid, cols, rows, function(i, j, w, h, v)
		count += 1
		local x0, z0 = minX + (i - 1) * S, minZ + (j - 1) * S
		local isBorder = v == 2
		makePart(
			(if isBorder then "Borde_%d" else "Camino_%d"):format(count),
			x0,
			x0 + w * S,
			z0,
			z0 + h * S,
			if isBorder then colors.Border else colors.Path,
			if isBorder then StudFloor.StudTexture else layout.PathTexture,
			StudFloor.PathTile,
			StudFloor.PathRaise
		)
	end)
end

-- Muros de damero (filas de base y remate) justo fuera de los límites del suelo
function StudWorld.buildWalls(parent: Instance, layout)
	local folder = PartFactory.folder(parent, "PerimeterWalls")
	local walls = layout.Walls
	local W = StudFloor.Wall
	local t = W.Thickness
	local minX, maxX, minZ, maxZ = layout.MinX, layout.MaxX, layout.MinZ, layout.MaxZ

	local function run(name: string, start: Vector3, dir: Vector3, length: number)
		if length <= 0 then
			return
		end
		local wallModel = PartFactory.folder(folder, name)
		local cols = math.max(1, math.round(length / W.BlockWidth))
		local colW = length / cols
		local alongX = dir.X ~= 0
		for r = 1, W.BaseRows + W.TopRows do
			local rowColors = if r > W.BaseRows then walls.Top else walls.Base
			for c = 1, cols do
				local center = start + dir * ((c - 0.5) * colW) + Vector3.new(0, (r - 0.5) * W.BlockHeight, 0)
				local part = PartFactory.part(wallModel, ("bloque_%d_%d"):format(r, c), {
					Size = Vector3.new(if alongX then colW else t, W.BlockHeight, if alongX then t else colW),
					CFrame = CFrame.new(center),
					Color = rowColors[(r + c) % 2 + 1],
					Material = Enum.Material.Plastic,
					Solid = true,
				})
				StudWorld.allStuds(part)
			end
		end
	end

	-- Oeste y este llegan hasta las esquinas exteriores de los muros norte y sur que haya
	local z0 = if walls.North then minZ - t else minZ
	local z1 = if walls.South then maxZ + t else maxZ
	run("WestWall", Vector3.new(minX - t / 2, GROUND, z0), Vector3.zAxis, z1 - z0)
	run("EastWall", Vector3.new(maxX + t / 2, GROUND, z0), Vector3.zAxis, z1 - z0)
	if walls.North then
		run("NorthWall", Vector3.new(minX, GROUND, minZ - t / 2), Vector3.xAxis, maxX - minX)
	end
	if walls.South then
		local gate = walls.GateHalf
		if gate then
			run("SouthWallLeft", Vector3.new(minX, GROUND, maxZ + t / 2), Vector3.xAxis, -gate - minX)
			run("SouthWallRight", Vector3.new(gate, GROUND, maxZ + t / 2), Vector3.xAxis, maxX - gate)
		else
			run("SouthWall", Vector3.new(minX, GROUND, maxZ + t / 2), Vector3.xAxis, maxX - minX)
		end
	end
end

-- Árbol de bloques con studs de Roblox. colors: { Trunk, LeafLight, LeafDark } (opcional)
function StudWorld.buildBlockyTree(parent: Instance, pos: Vector3, yawDeg: number, scale: number, colors: { [string]: Color3 }?)
	local tree = Instance.new("Model")
	tree.Name = "BlockyTree"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local trunkColor = colors and colors.Trunk or Color3.fromRGB(206, 114, 42)
	local leafLight = colors and colors.LeafLight or Color3.fromRGB(124, 226, 26)
	local leafDark = colors and colors.LeafDark or Color3.fromRGB(106, 206, 18)

	local baseW = 3.2 * scale
	local baseH = 0.8 * scale
	local baseBlock = StudWorld.allStuds(PartFactory.part(tree, "TrunkBase", {
		Size = Vector3.new(baseW, baseH, baseW),
		CFrame = cf * CFrame.new(0, baseH / 2, 0),
		Color = trunkColor,
		Material = Enum.Material.Plastic,
		Solid = true,
	}))

	local trunkH = 10.5 * scale
	local trunkW = 1.8 * scale
	StudWorld.allStuds(PartFactory.part(tree, "Trunk", {
		Size = Vector3.new(trunkW, trunkH, trunkW),
		CFrame = cf * CFrame.new(0, baseH + trunkH / 2, 0),
		Color = trunkColor,
		Material = Enum.Material.Plastic,
		Solid = true,
	}))

	for _, side in { -1, 1 } do
		StudWorld.allStuds(PartFactory.part(tree, "Branch" .. side, {
			Size = Vector3.new(1.2 * scale, 5.2 * scale, 1.2 * scale),
			CFrame = cf * CFrame.new(side * 1.9 * scale, 6.8 * scale, 0) * CFrame.Angles(0, 0, math.rad(-side * 38)),
			Color = trunkColor,
			Material = Enum.Material.Plastic,
			Solid = false,
		}))
	end

	StudWorld.allStuds(PartFactory.part(tree, "CanopyMain", {
		Size = Vector3.new(7.4 * scale, 5.4 * scale, 7.4 * scale),
		CFrame = cf * CFrame.new(0, 11.6 * scale, 0),
		Color = leafLight,
		Material = Enum.Material.Plastic,
		Solid = false,
	}))
	StudWorld.allStuds(PartFactory.part(tree, "CanopyLeft", {
		Size = Vector3.new(5.8 * scale, 4.8 * scale, 5.8 * scale),
		CFrame = cf * CFrame.new(-3.2 * scale, 10.0 * scale, 0.8 * scale),
		Color = leafDark,
		Material = Enum.Material.Plastic,
		Solid = false,
	}))
	StudWorld.allStuds(PartFactory.part(tree, "CanopyRight", {
		Size = Vector3.new(5.6 * scale, 4.6 * scale, 5.6 * scale),
		CFrame = cf * CFrame.new(3.2 * scale, 10.4 * scale, -0.6 * scale),
		Color = leafLight,
		Material = Enum.Material.Plastic,
		Solid = false,
	}))

	tree.PrimaryPart = baseBlock
	tree.Parent = parent
	return tree
end

-- Reparto de decoración con semilla fija (layout.DecorSeed) sobre el damero de una zona.
-- Nunca pisa los caminos, los puntos de aparición de enemigos (EnemyConfig) ni la arena del
-- jefe; keepOut añade círculos propios { x, z, radio } en coordenadas del mundo.
function StudWorld.newDecor(layout, zoneName: string, keepOut: { { number } }?)
	local zone = ZoneConfig.Zones[zoneName]
	local originX = GeneratorConfig.Position.X + zone.Center.X
	local originZ = GeneratorConfig.Position.Z + zone.Center.Y
	local blocked: { { number } } = table.clone(keepOut or {})
	local enemies = EnemyConfig.Zones[zoneName]
	if enemies then
		for _, spawnInfo in enemies.Spawns do
			table.insert(blocked, { originX + spawnInfo.Offset.X, originZ + spawnInfo.Offset.Y, 9 })
		end
		if enemies.Boss then
			local arena = enemies.Boss.Arena
			table.insert(blocked, { originX + arena.Center.X, originZ + arena.Center.Y, arena.Radius + 6 })
		end
	end

	local placed: { { number } } = {} -- { x, z, radio que ocupa }
	local rng = Random.new(layout.DecorSeed)
	local decor = { Rng = rng }

	function decor.isFree(x: number, z: number, minPath: number, maxPath: number, radius: number): boolean
		if x < layout.MinX + 5 or x > layout.MaxX - 5 or z < layout.MinZ + 5 or z > layout.MaxZ - 5 then
			return false
		end
		local d = StudWorld.distToPaths(layout, x, z)
		if d < minPath or d > maxPath then
			return false
		end
		local river = layout.River
		if river and z > river.MinZ - radius and z < river.MaxZ + radius then
			return false
		end
		for _, k in blocked do
			if (x - k[1]) ^ 2 + (z - k[2]) ^ 2 < k[3] ^ 2 then
				return false
			end
		end
		for _, p in placed do
			if (x - p[1]) ^ 2 + (z - p[2]) ^ 2 < math.max(radius, p[3]) ^ 2 then
				return false
			end
		end
		return true
	end

	function decor.claim(x: number, z: number, radius: number)
		table.insert(placed, { x, z, radius })
	end

	-- Hasta `count` objetos al azar a entre minPath y maxPath studs de un camino
	function decor.scatter(count: number, minPath: number, maxPath: number, radius: number, build: (Vector3, number) -> ())
		local done, tries = 0, 0
		while done < count and tries < count * 60 do
			tries += 1
			local x = rng:NextNumber(layout.MinX, layout.MaxX)
			local z = rng:NextNumber(layout.MinZ, layout.MaxZ)
			if decor.isFree(x, z, minPath, maxPath, radius) then
				decor.claim(x, z, radius)
				build(Vector3.new(x, StudWorld.FloorTop, z), rng:NextNumber(0, 360))
				done += 1
			end
		end
	end

	-- Una fila a `inset` studs por dentro de cada muro, un objeto cada `spacing` studs
	function decor.wallRow(spacing: number, inset: number, radius: number, build: (Vector3, number) -> ())
		local x0, x1 = layout.MinX + inset, layout.MaxX - inset
		local z0, z1 = layout.MinZ + inset, layout.MaxZ - inset
		for _, line in { { x0, z0, x1, z0 }, { x0, z1, x1, z1 }, { x0, z0, x0, z1 }, { x1, z0, x1, z1 } } do
			local from = Vector2.new(line[1], line[2])
			local to = Vector2.new(line[3], line[4])
			local steps = math.floor((to - from).Magnitude / spacing)
			for s = 0, steps do
				local p = from:Lerp(to, s / math.max(steps, 1)) + Vector2.new(rng:NextNumber(-3, 3), rng:NextNumber(-3, 3))
				if decor.isFree(p.X, p.Y, 6, math.huge, radius) then
					decor.claim(p.X, p.Y, radius)
					build(Vector3.new(p.X, StudWorld.FloorTop, p.Y), rng:NextNumber(0, 360))
				end
			end
		end
	end

	return decor
end

return StudWorld
