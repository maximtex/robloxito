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

-- Studs nítidos en una cara: la textura de los bordes del suelo (StudFloor.StudTexture, 8
-- studs por imagen) con una rejilla entera de studs de unos StudFloor.Wall.StudSize, que
-- empieza en la esquina de la cara. faceU / faceV: lo que mide la cara a lo ancho y a lo alto.
local function studFace(part: BasePart, face: Enum.NormalId, faceU: number, faceV: number)
	local size = StudFloor.Wall.StudSize
	local texture = Instance.new("Texture")
	texture.Name = "Studs"
	texture.Texture = StudFloor.StudTexture
	texture.Face = face
	texture.StudsPerTileU = faceU / math.max(1, math.round(faceU / size)) * 8
	texture.StudsPerTileV = faceV / math.max(1, math.round(faceV / size)) * 8
	texture.Parent = part
end

-- Muros de damero justo fuera de los límites del suelo, como la referencia: losetas cuadradas
-- de tierra abajo y hierba arriba, con relieve: la hierba sobresale hacia dentro como un alero
-- con el borde en escalones (cada columna con sus filas de hierba), algún tramo es una fila más
-- alto y, en los muros que no tienen otra zona detrás, la hierba sube en escalones hacia atrás.
-- Siempre igual (semilla de la zona). Nada entra en el suelo: el alero va por encima de la
-- tierra (a varias losetas de altura) y los escalones, por fuera. Las caras que se ven llevan
-- studs nítidos con textura.
local INWARD = {
	[Enum.NormalId.Right] = Vector3.xAxis,
	[Enum.NormalId.Left] = -Vector3.xAxis,
	[Enum.NormalId.Back] = Vector3.zAxis,
	[Enum.NormalId.Front] = -Vector3.zAxis,
}

-- Borde a medida (layout.Outline): lo que hay entre el suelo y el rectángulo del mapa es una
-- colina de bloques en una rejilla de 8x8 alineada con el suelo. Las casillas que tocan el suelo
-- son columnas de muro como las de siempre (tierra abajo, hierba arriba con alero y alguna una
-- fila más alta); las de detrás, una meseta de hierba a la misma altura. Studs nítidos en todo
-- lo que se ve. El muro sur (compartido con la zona siguiente) se hace aparte, como siempre.
local function buildHill(folder: Instance, layout)
	local W = StudFloor.Wall
	local B, H, O, t = W.BlockWidth, W.BlockHeight, W.GrassOverhang, W.Thickness
	local rows = W.BaseRows + W.TopRows
	local walls = layout.Walls
	local seed = layout.DecorSeed or 1
	local hill = PartFactory.folder(folder, "Hill")
	local x0, x1 = layout.MinX - t, layout.MaxX + t
	local z0, z1 = if walls.North then layout.MinZ - t else layout.MinZ, layout.MaxZ

	-- Casillas por su índice (centro = índice · 8): "floor", "wall", "top" o nil (fuera)
	local kinds: { [string]: string } = {}
	local function key(i: number, j: number): string
		return i .. "," .. j
	end
	local i0, i1 = math.round((x0 + B / 2) / B), math.round((x1 - B / 2) / B)
	local j0, j1 = math.round((z0 + B / 2) / B), math.round((z1 - B / 2) / B)
	for i = i0, i1 do
		for j = j0, j1 do
			kinds[key(i, j)] = if StudFloor.onFloor(layout, i * B, j * B) then "floor" else "fill"
		end
	end
	local SIDES = {
		{ 1, 0, Enum.NormalId.Right },
		{ -1, 0, Enum.NormalId.Left },
		{ 0, 1, Enum.NormalId.Back },
		{ 0, -1, Enum.NormalId.Front },
	}
	local function kind(i: number, j: number): string?
		return kinds[key(i, j)]
	end
	for i = i0, i1 do
		for j = j0, j1 do
			if kind(i, j) == "fill" then
				local touches = false
				for _, side in SIDES do
					if kind(i + side[1], j + side[2]) == "floor" then
						touches = true
					end
				end
				kinds[key(i, j)] = if touches then "wall" else "top"
			end
		end
	end

	-- Alto (a veces una fila más) y filas de hierba de cada columna, siempre iguales
	local heights: { [string]: number } = {}
	local function heightOf(i: number, j: number): number
		local k = kind(i, j)
		if k == "floor" then
			return 0
		elseif k == "wall" then
			local h = heights[key(i, j)]
			if not h then
				h = rows + (if Random.new(seed * 7919 + i * 131 + j * 17):NextNumber() < W.BumpChance then 1 else 0)
				heights[key(i, j)] = h
			end
			return h
		end
		return rows
	end
	local function grassRows(i: number, j: number): number
		local n = math.sin((i + j) * 0.72) + 0.6 * math.sin(i * 1.7 - j * 1.35)
		return math.clamp(3 + math.round(n), W.GrassRows[1], W.GrassRows[2]) + heightOf(i, j) - rows
	end

	local function block(name: string, center: Vector3, size: Vector3, color: Color3): BasePart
		return PartFactory.part(hill, name, {
			Size = size,
			CFrame = CFrame.new(center),
			Color = color,
			Material = Enum.Material.Plastic,
			Solid = true,
		})
	end

	for i = i0, i1 do
		for j = j0, j1 do
			local k = kind(i, j)
			if k == "top" then
				-- Meseta: un bloque de hierba arriba
				local part = block("meseta_" .. key(i, j), Vector3.new(i * B, GROUND + (rows - 0.5) * H, j * B), Vector3.new(B, H, B), walls.Top[(rows + i + j) % 2 + 1])
				studFace(part, Enum.NormalId.Top, B, B)
			elseif k == "wall" then
				local h = heightOf(i, j)
				local g = grassRows(i, j)
				local floorSides = {}
				for _, side in SIDES do
					if kind(i + side[1], j + side[2]) == "floor" then
						table.insert(floorSides, side)
					end
				end
				for r = 1, h do
					local grassy = r > h - g
					local color = (if grassy then walls.Top else walls.Base)[(r + i + j) % 2 + 1]
					local part = block(("muro_%s_%d"):format(key(i, j), r), Vector3.new(i * B, GROUND + (r - 0.5) * H, j * B), Vector3.new(B, H, B), color)
					for _, side in SIDES do
						if r > heightOf(i + side[1], j + side[2]) then
							studFace(part, side[3], B, H)
						end
					end
					if r == h then
						studFace(part, Enum.NormalId.Top, B, B)
					end
				end
				-- Alero de hierba hacia el suelo, solo en los tramos rectos (en una esquina se
				-- cruzaría con el de la columna de al lado)
				local side = floorSides[1]
				if #floorSides == 1 then
					local fi, fj = i + side[1], j + side[2]
					local corner = (side[1] ~= 0 and (kind(fi, fj + 1) ~= "floor" or kind(fi, fj - 1) ~= "floor"))
						or (side[2] ~= 0 and (kind(fi + 1, fj) ~= "floor" or kind(fi - 1, fj) ~= "floor"))
					if not corner then
						local out = Vector3.new(side[1], 0, side[2])
						local size = if side[1] ~= 0 then Vector3.new(O, H, B) else Vector3.new(B, H, O)
						local ends = if side[1] ~= 0 then { Enum.NormalId.Front, Enum.NormalId.Back } else { Enum.NormalId.Left, Enum.NormalId.Right }
						for r = h - g + 1, h do
							local color = walls.Top[(r + i + j) % 2 + 1]
							local center = Vector3.new(i * B, GROUND + (r - 0.5) * H, j * B) + out * (B / 2 + O / 2)
							local lip = block(("alero_%s_%d"):format(key(i, j), r), center, size, color)
							studFace(lip, side[3], B, H)
							for _, face in ends do
								studFace(lip, face, O, H)
							end
							if r == h then
								studFace(lip, Enum.NormalId.Top, size.X, size.Z)
							end
							if r == h - g + 1 then
								studFace(lip, Enum.NormalId.Bottom, size.X, size.Z)
							end
						end
					end
				end
			end
		end
	end
end

-- Borde a medida con terrazas (layout.Hill.Terraces): lo de fuera del borde, hasta Extend studs
-- más allá del muro de siempre, sube en escalones de 8 de fondo según la distancia al suelo
-- (también en diagonal): el primero mide Terraces[1].Height, el segundo Terraces[2].Height... y
-- todo lo demás, lo del último. Hill.Channel deja abierto el río (o la lava) de lado a lado
-- hasta Reach, donde lo cierra el escalón más alto (cascadas: ValleyService, CalderaService).
-- Hill.CloseSouth: también suben por el sur y hacen de muro del fondo. Una pieza por casilla
-- con studs nítidos en lo que se ve. Devuelve las casillas de arriba ({ Position, Ring }) para
-- poner cristales y árboles encima.
local function buildTerraces(folder: Instance, layout): { { Position: Vector3, Ring: number } }
	local W = StudFloor.Wall
	local B, t = W.BlockWidth, W.Thickness
	local hillSpec = layout.Hill
	local terraces = hillSpec.Terraces
	local channel = hillSpec.Channel
	if channel and channel.OverSteps then
		-- La lava baja por encima de los escalones (CalderaService): terrazas completas, sin ranura
		channel = nil
	end
	local walls = layout.Walls
	local hill = PartFactory.folder(folder, "Hill")
	local x0, x1 = layout.MinX - t - hillSpec.Extend, layout.MaxX + t + hillSpec.Extend
	local z0 = if walls.North then layout.MinZ - t else layout.MinZ
	-- CloseSouth: las terrazas también cierran el fondo (no hay muro sur ni zona detrás)
	local z1 = if hillSpec.CloseSouth then layout.MaxZ + t + hillSpec.Extend else layout.MaxZ
	local i0, i1 = math.round((x0 + B / 2) / B), math.round((x1 - B / 2) / B)
	local j0, j1 = math.round((z0 + B / 2) / B), math.round((z1 - B / 2) / B)
	local function key(i: number, j: number): string
		return i .. "," .. j
	end
	local function inChannel(j: number): boolean
		return channel ~= nil and j * B > channel.MinZ and j * B < channel.MaxZ
	end

	-- 0 = abierto (suelo o río); si no, distancia en casillas al abierto más cercano
	local ring: { [string]: number } = {}
	local queue = {}
	for i = i0, i1 do
		for j = j0, j1 do
			local open = StudFloor.onFloor(layout, i * B, j * B) or (inChannel(j) and math.abs(i * B) < channel.Reach)
			if open then
				ring[key(i, j)] = 0
				table.insert(queue, { i, j })
			end
		end
	end
	local head = 1
	while head <= #queue do
		local cell = queue[head]
		head += 1
		local d = ring[key(cell[1], cell[2])]
		for di = -1, 1 do
			for dj = -1, 1 do
				local ni, nj = cell[1] + di, cell[2] + dj
				if ni >= i0 and ni <= i1 and nj >= j0 and nj <= j1 and ring[key(ni, nj)] == nil then
					ring[key(ni, nj)] = d + 1
					table.insert(queue, { ni, nj })
				end
			end
		end
	end
	local function heightOf(i: number, j: number): number?
		local r = ring[key(i, j)]
		if r == nil then
			return nil -- fuera de la rejilla
		elseif r == 0 then
			return 0
		end
		if inChannel(j) then
			r = #terraces -- el río lo cierra el escalón más alto
		end
		return terraces[math.min(r, #terraces)].Height
	end

	local SIDES = {
		{ 1, 0, Enum.NormalId.Right },
		{ -1, 0, Enum.NormalId.Left },
		{ 0, 1, Enum.NormalId.Back },
		{ 0, -1, Enum.NormalId.Front },
	}
	local tops = {}
	for i = i0, i1 do
		for j = j0, j1 do
			local h = heightOf(i, j)
			if h and h > 0 then
				local r = math.min(if inChannel(j) then #terraces else ring[key(i, j)], #terraces)
				local spec = terraces[r]
				local part = PartFactory.part(hill, "terraza_" .. key(i, j), {
					Size = Vector3.new(B, h, B),
					CFrame = CFrame.new(i * B, GROUND + h / 2, j * B),
					Color = spec.Colors[(i + j) % 2 + 1],
					Material = Enum.Material.Plastic,
					Solid = true,
				})
				studFace(part, Enum.NormalId.Top, B, B)
				for _, side in SIDES do
					local nh = heightOf(i + side[1], j + side[2])
					if nh and nh < h then
						studFace(part, side[3], B, h)
					end
				end
				table.insert(tops, { Position = Vector3.new(i * B, GROUND + h, j * B), Ring = r })
			end
		end
	end
	return tops
end

function StudWorld.buildWalls(parent: Instance, layout): { { Position: Vector3, Ring: number } }?
	local folder = PartFactory.folder(parent, "PerimeterWalls")
	local walls = layout.Walls
	local W = StudFloor.Wall
	local t, H, O = W.Thickness, W.BlockHeight, W.GrassOverhang
	local minX, maxX, minZ, maxZ = layout.MinX, layout.MaxX, layout.MinZ, layout.MaxZ
	local rows = W.BaseRows + W.TopRows
	local seed = layout.DecorSeed or 1

	-- start: punto de arranque a ras del suelo; dir: hacia dónde avanza; inward: la cara que
	-- mira al mapa; tiers: si puede subir en escalones hacia atrás (no hay otra zona detrás);
	-- noBump(along): tramos que no pueden subir (junto al paso del portal); canHang(along):
	-- dónde puede haber alero (no en las esquinas, donde se cruzaría con el del otro muro)
	local function run(name: string, start: Vector3, dir: Vector3, length: number, inward: Enum.NormalId, runSeed: number, tiers: boolean, noBump: ((number) -> boolean)?, canHang: ((number) -> boolean)?)
		if length <= 0 then
			return
		end
		local wallModel = PartFactory.folder(folder, name)
		local cols = math.max(1, math.round(length / W.BlockWidth))
		local colW = length / cols
		local alongX = dir.X ~= 0
		local inwardDir = INWARD[inward]
		local startEnd = if alongX then Enum.NormalId.Left else Enum.NormalId.Front
		local finishEnd = if alongX then Enum.NormalId.Right else Enum.NormalId.Back
		local rng = Random.new(runSeed)

		-- Por columna: alto (tramos de 2 o 3, a veces una fila más), filas de hierba y escalón de atrás
		local heights, grass, tier, hangs = {}, {}, {}, {}
		local c = 1
		while c <= cols do
			local span = rng:NextInteger(2, 3)
			local offset = (c - 0.5) * colW
			local along = if alongX then start.X + offset * dir.X else start.Z + offset * dir.Z
			local bump = rng:NextNumber() < W.BumpChance and not (noBump and noBump(along))
			local rise = if tiers and rng:NextNumber() < W.TierChance then rng:NextInteger(1, W.TierRows) else 0
			for k = c, math.min(cols, c + span - 1) do
				heights[k] = rows + (if bump then 1 else 0)
				tier[k] = rise
			end
			c += span
		end
		local grassNow = rng:NextInteger(W.GrassRows[1], W.GrassRows[2])
		for k = 1, cols do
			grassNow = math.clamp(grassNow + rng:NextInteger(-1, 1), W.GrassRows[1], W.GrassRows[2])
			grass[k] = grassNow + heights[k] - rows
			local offset = (k - 0.5) * colW
			local along = if alongX then start.X + offset * dir.X else start.Z + offset * dir.Z
			hangs[k] = not canHang or canHang(along)
		end
		local function isGrass(k: number, r: number): boolean
			return k >= 1 and k <= cols and r <= heights[k] and r > heights[k] - grass[k]
		end
		local function overhangs(k: number, r: number): boolean
			return isGrass(k, r) and hangs[k]
		end

		local function block(k: number, r: number, colors: { Color3 }, depth: number, shift: number): BasePart
			local center = start + dir * ((k - 0.5) * colW) + Vector3.new(0, (r - 0.5) * H, 0) + inwardDir * shift
			return PartFactory.part(wallModel, ("bloque_%d_%d"):format(r, k), {
				Size = Vector3.new(if alongX then colW else depth, H, if alongX then depth else colW),
				CFrame = CFrame.new(center),
				Color = colors[(r + k) % 2 + 1],
				Material = Enum.Material.Plastic,
				Solid = true,
			})
		end

		for k = 1, cols do
			local h = heights[k]
			local before = if k > 1 then heights[k - 1] else 0
			local after = if k < cols then heights[k + 1] else 0
			for r = 1, h do
				-- La hierba sobresale O studs hacia dentro (el alero); la tierra, a ras del límite
				local grassy = isGrass(k, r)
				local hanging = overhangs(k, r)
				local depth = if hanging then t + O else t
				local part = block(k, r, if grassy then walls.Top else walls.Base, depth, if hanging then O / 2 else 0)
				studFace(part, inward, colW, H)
				if r == h then
					studFace(part, Enum.NormalId.Top, part.Size.X, part.Size.Z)
				end
				-- Puntas: más alta que la vecina, o alero donde la vecina no lo tiene
				if r > before or (hanging and not overhangs(k - 1, r)) then
					studFace(part, startEnd, depth, H)
				end
				if r > after or (hanging and not overhangs(k + 1, r)) then
					studFace(part, finishEnd, depth, H)
				end
				if hanging and r == h - grass[k] + 1 then
					studFace(part, Enum.NormalId.Bottom, part.Size.X, part.Size.Z) -- bajo del alero
				end
			end
			-- Escalón de hierba detrás, un grosor hacia fuera
			local top = h + tier[k]
			local beforeTop = if k > 1 then heights[k - 1] + tier[k - 1] else 0
			local afterTop = if k < cols then heights[k + 1] + tier[k + 1] else 0
			for r = h + 1, top do
				local part = block(k, r, walls.Top, t, -t)
				studFace(part, inward, colW, H)
				if r == top then
					studFace(part, Enum.NormalId.Top, part.Size.X, part.Size.Z)
				end
				if r > beforeTop then
					studFace(part, startEnd, t, H)
				end
				if r > afterTop then
					studFace(part, finishEnd, t, H)
				end
			end
		end
	end

	-- Oeste y este llegan hasta las esquinas exteriores de los muros norte y sur que haya. El
	-- muro sur que comparten dos zonas no sube hacia atrás (detrás está la zona siguiente).
	local southOuter = walls.South and not walls.GateHalf
	local z0 = if walls.North then minZ - t else minZ
	local z1 = if walls.South then maxZ + t else maxZ
	local function awayFromCorners(z: number): boolean
		return z > minZ + W.BlockWidth and z < maxZ - W.BlockWidth
	end
	local hillTops = nil
	if layout.Outline and layout.Hill and layout.Hill.Terraces then
		-- Borde a medida con terrazas (Valle, Caldera)
		hillTops = buildTerraces(folder, layout)
	elseif layout.Outline then
		-- Borde a medida: la colina hace de muros oeste, este y norte
		buildHill(folder, layout)
	else
		run("WestWall", Vector3.new(minX - t / 2, GROUND, z0), Vector3.zAxis, z1 - z0, Enum.NormalId.Right, seed + 101, true, nil, awayFromCorners)
		run("EastWall", Vector3.new(maxX + t / 2, GROUND, z0), Vector3.zAxis, z1 - z0, Enum.NormalId.Left, seed + 202, true, nil, awayFromCorners)
		if walls.North then
			run("NorthWall", Vector3.new(minX, GROUND, minZ - t / 2), Vector3.xAxis, maxX - minX, Enum.NormalId.Back, seed + 303, true)
		end
	end
	if walls.South and not (layout.Hill and layout.Hill.CloseSouth) then
		local gate = walls.GateHalf
		if gate then
			-- Junto al paso, a la altura del cristal del portal
			local function nearGate(x: number): boolean
				return math.abs(x) < gate + 3 * W.BlockWidth
			end
			local function awayFromGate(x: number): boolean
				return not nearGate(x) and StudFloor.onFloor(layout, x, maxZ - W.BlockWidth / 2)
			end
			run("SouthWallLeft", Vector3.new(minX, GROUND, maxZ + t / 2), Vector3.xAxis, -gate - minX, Enum.NormalId.Front, seed + 404, false, nearGate, awayFromGate)
			run("SouthWallRight", Vector3.new(gate, GROUND, maxZ + t / 2), Vector3.xAxis, maxX - gate, Enum.NormalId.Front, seed + 505, false, nearGate, awayFromGate)
		else
			run("SouthWall", Vector3.new(minX, GROUND, maxZ + t / 2), Vector3.xAxis, maxX - minX, Enum.NormalId.Front, seed + 404, southOuter)
		end
	end
	return hillTops
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
		if not StudFloor.onFloor(layout, x, z, 6) then
			return false -- encima o pegado a la colina del borde
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
