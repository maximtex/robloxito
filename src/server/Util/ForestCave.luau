-- Cueva de los Espinillos (Bosque, al oeste): la sala de dentro y la boca vista desde la
-- pradera. El camino de la plaza a la boca es un camino más del suelo (StudFloor Paths) y el
-- hueco en la colina lo hace StudWorld (layout.Cave.Opening); aquí va lo demás:
-- - Suelo de piedra en damero con studs, paredes de bloques (con el hueco de la entrada en el
--   lado de la boca) y techo de bloques con tres claraboyas por las que entra un haz de luz.
-- - Estalactitas, estalagmitas, rocas, cristales y setas que brillan (con luces) para que no
--   esté a oscuras, y antorchas y un cartel en la boca.
-- Con semilla fija: siempre igual. Nada se pone encima de los bichos (EnemyConfig), del pasillo
-- de la entrada ni bajo las claraboyas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local PartFactory = require(script.Parent.PartFactory)
local StudWorld = require(script.Parent.StudWorld)

local ForestCave = {}

local RGB = Color3.fromRGB
local B = 8 -- bloques de 8, alineados con el suelo del Bosque
local WALL = 4 -- grosor de las paredes (por dentro de la sala)
local GROUND = GeneratorConfig.Position.Y

local STONE = { RGB(92, 98, 128), RGB(78, 84, 112) } -- suelo
local ROCK = { RGB(104, 108, 140), RGB(86, 90, 120) } -- paredes y techo
local DARK = { RGB(70, 74, 100), RGB(58, 62, 86) } -- estalactitas y rocas
local CRYSTAL = { RGB(96, 224, 255), RGB(196, 128, 255), RGB(120, 255, 200) }
local SHAFT = RGB(255, 244, 205)
local SEED = 7311

-- Claraboyas del techo (índices de casilla dentro de la sala, desde 1)
local SKYLIGHTS = { { 4, 4 }, { 9, 9 }, { 3, 10 } }

local function studs(part: BasePart, face: Enum.NormalId)
	local size = part.Size
	local u, v
	if face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		u, v = size.X, size.Z
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		u, v = size.Z, size.Y
	else
		u, v = size.X, size.Y
	end
	StudWorld.studFace(part, face, u, v)
end

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, solid: boolean?): Part
	return PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Plastic,
		Solid = solid,
	})
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local point = Instance.new("PointLight")
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Shadows = false
	point.Parent = parent
end

-- Junta en franjas las casillas marcadas de cada fila (para el techo)
local function strips(cols: number, rows: number, solid: (number, number) -> boolean, emit: (number, number, number) -> ())
	for j = 1, rows do
		local i = 1
		while i <= cols do
			if solid(i, j) then
				local w = 1
				while i + w <= cols and solid(i + w, j) do
					w += 1
				end
				emit(i, j, w)
				i += w
			else
				i += 1
			end
		end
	end
end

function ForestCave.build(parent: Instance, layout)
	local cave = layout.Cave
	if not cave then
		return
	end
	local room, opening = cave.Room, cave.Opening
	local floorTop = StudWorld.FloorTop
	local height = cave.Height
	local cols = math.round((room.MaxX - room.MinX) / B)
	local rows = math.round((room.MaxZ - room.MinZ) / B)
	local model = Instance.new("Model")
	model.Name = "ForestCave"
	local rng = Random.new(SEED)

	local function cellCenter(i: number, j: number): (number, number)
		return room.MinX + (i - 0.5) * B, room.MinZ + (j - 0.5) * B
	end

	-- Sitios ocupados: bichos, pasillo de la entrada y claraboyas (en planta, círculos)
	local blocked: { { number } } = {}
	local zone = ZoneConfig.Zones.Forest
	local originX = GeneratorConfig.Position.X + zone.Center.X
	local originZ = GeneratorConfig.Position.Z + zone.Center.Y
	for _, spawnInfo in EnemyConfig.Zones.Forest.Spawns do
		local x, z = originX + spawnInfo.Offset.X, originZ + spawnInfo.Offset.Y
		if x > room.MinX and x < room.MaxX and z > room.MinZ and z < room.MaxZ then
			table.insert(blocked, { x, z, 7 })
		end
	end
	for _, cell in SKYLIGHTS do
		local x, z = cellCenter(cell[1], cell[2])
		table.insert(blocked, { x, z, 7 })
	end
	local laneZ = (opening.MinZ + opening.MaxZ) / 2
	local laneHalf = (opening.MaxZ - opening.MinZ) / 2 + 4
	local function isFree(x: number, z: number, radius: number): boolean
		if x < room.MinX + WALL + radius or x > room.MaxX - WALL - radius or z < room.MinZ + WALL + radius or z > room.MaxZ - WALL - radius then
			return false
		end
		-- El pasillo desde la puerta hasta el centro de la sala, libre
		if math.abs(z - laneZ) < laneHalf + radius and x > (room.MinX + room.MaxX) / 2 then
			return false
		end
		for _, k in blocked do
			if (x - k[1]) ^ 2 + (z - k[2]) ^ 2 < (k[3] + radius) ^ 2 then
				return false
			end
		end
		return true
	end
	local function claim(x: number, z: number, radius: number)
		table.insert(blocked, { x, z, radius })
	end
	-- Un sitio libre al azar (o nil); nearWall: pegado a una pared
	local function spot(radius: number, nearWall: boolean): (number?, number?)
		for _ = 1, 80 do
			local x = rng:NextNumber(room.MinX, room.MaxX)
			local z = rng:NextNumber(room.MinZ, room.MaxZ)
			if nearWall then
				local side = rng:NextInteger(1, 4)
				local inset = WALL + radius + rng:NextNumber(0, 3)
				if side == 1 then
					x = room.MinX + inset
				elseif side == 2 then
					x = room.MaxX - inset
				elseif side == 3 then
					z = room.MinZ + inset
				else
					z = room.MaxZ - inset
				end
			end
			if isFree(x, z, radius) then
				claim(x, z, radius)
				return x, z
			end
		end
		return nil, nil
	end

	-- 1. Suelo de piedra en damero (su cara de arriba, a la altura del suelo del Bosque)
	local floorFolder = PartFactory.folder(model, "Floor")
	for i = 1, cols do
		for j = 1, rows do
			local x, z = cellCenter(i, j)
			local part = block(floorFolder, ("suelo_%d_%d"):format(i, j), Vector3.new(B, 1, B), CFrame.new(x, floorTop - 0.5, z), STONE[(i + j) % 2 + 1])
			part.CastShadow = false
			studs(part, Enum.NormalId.Top)
		end
	end

	-- 2. Paredes: bloques de 8 de largo y WALL de grueso por dentro de la sala, filas de 8 de
	-- alto. En el lado de la boca, el hueco de la entrada (Opening.Ceiling filas).
	local wallFolder = PartFactory.folder(model, "Walls")
	local wallRows = math.round(height / B)
	local doorRows = opening.Ceiling or 3
	local function isDoor(z: number, r: number): boolean
		return z > opening.MinZ and z < opening.MaxZ and r <= doorRows
	end
	local sides = {
		-- { nombre, x fijo o nil, z fijo o nil, cara de dentro, ¿lado de la boca? }
		{ "Oeste", room.MinX + WALL / 2, nil, Enum.NormalId.Right, false },
		{ "Este", room.MaxX - WALL / 2, nil, Enum.NormalId.Left, true },
		{ "Norte", nil, room.MinZ + WALL / 2, Enum.NormalId.Back, false },
		{ "Sur", nil, room.MaxZ - WALL / 2, Enum.NormalId.Front, false },
	}
	for _, side in sides do
		local alongZ = side[2] ~= nil
		local count = if alongZ then rows else cols
		for k = 1, count do
			for r = 1, wallRows do
				local x, z
				if alongZ then
					x, z = side[2], room.MinZ + (k - 0.5) * B
				else
					x, z = room.MinX + (k - 0.5) * B, side[3]
				end
				if not (side[5] and isDoor(z, r)) then
					local size = if alongZ then Vector3.new(WALL, B, B) else Vector3.new(B, B, WALL)
					local part = block(wallFolder, ("pared%s_%d_%d"):format(side[1], k, r), size, CFrame.new(x, GROUND + (r - 0.5) * B, z), ROCK[(k + r) % 2 + 1])
					studs(part, side[4])
					if side[5] and r == doorRows + 1 and z > opening.MinZ and z < opening.MaxZ then
						studs(part, Enum.NormalId.Bottom) -- dintel de la entrada
					end
				end
			end
		end
	end

	-- 3. Techo con claraboyas: franjas de bloques y, en cada hueco, un haz de luz
	local roofFolder = PartFactory.folder(model, "Roof")
	local roofY = GROUND + wallRows * B
	local function isSkylight(i: number, j: number): boolean
		for _, cell in SKYLIGHTS do
			if cell[1] == i and cell[2] == j then
				return true
			end
		end
		return false
	end
	strips(cols, rows, function(i, j)
		return not isSkylight(i, j)
	end, function(i, j, w)
		local x0 = room.MinX + (i - 1) * B
		local part = block(roofFolder, ("techo_%d_%d"):format(i, j), Vector3.new(w * B, B, B), CFrame.new(x0 + w * B / 2, roofY + B / 2, room.MinZ + (j - 0.5) * B), ROCK[j % 2 + 1])
		studs(part, Enum.NormalId.Bottom)
	end)
	for _, cell in SKYLIGHTS do
		local x, z = cellCenter(cell[1], cell[2])
		-- Haz: un Beam que mira a la cámara y se desvanece hacia el suelo (no una pieza sólida)
		local shaftHeight = roofY - floorTop
		local shaft = block(roofFolder, "HazDeLuz", Vector3.new(1, 1, 1), CFrame.new(x, roofY - 0.5, z), SHAFT, false)
		shaft.Transparency = 1
		shaft.CastShadow = false
		local top = Instance.new("Attachment")
		top.Name = "Arriba"
		top.Parent = shaft
		local bottom = Instance.new("Attachment")
		bottom.Name = "Abajo"
		bottom.Position = Vector3.new(0, -(shaftHeight - 0.5), 0)
		bottom.Parent = shaft
		local beam = Instance.new("Beam")
		beam.Attachment0 = top
		beam.Attachment1 = bottom
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Width0 = B - 1
		beam.Width1 = B + 1
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(SHAFT)
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.7, 0.85), NumberSequenceKeypoint.new(1, 1) })
		beam.Parent = shaft
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = 50
		spot.Range = shaftHeight + 6
		spot.Brightness = 2
		spot.Color = SHAFT
		spot.Shadows = false
		spot.Parent = shaft
		-- Un poco de hierba donde da la luz
		local patch = block(roofFolder, "HierbaDeLuz", Vector3.new(B - 2, 0.3, B - 2), CFrame.new(x, floorTop + 0.15, z), RGB(120, 200, 70), false)
		patch.CastShadow = false
	end

	-- 4. Estalactitas (del techo) y estalagmitas (del suelo): bloques que se estrechan
	local rockFolder = PartFactory.folder(model, "Rocks")
	local function stack(x: number, z: number, down: boolean, scale: number)
		local sizes = { 5, 3.6, 2.2, 1.2 }
		local y = if down then roofY else floorTop
		for index, size in sizes do
			local s = size * scale
			local h = s * 1.1
			local center = if down then y - h / 2 else y + h / 2
			local part = block(rockFolder, if down then "Estalactita" else "Estalagmita", Vector3.new(s, h, s), CFrame.new(x, center, z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0), DARK[index % 2 + 1], index <= 2 and not down)
			studs(part, if down then Enum.NormalId.Bottom else Enum.NormalId.Top)
			y = if down then y - h else y + h
		end
	end
	for _ = 1, 16 do
		local x = rng:NextNumber(room.MinX + 10, room.MaxX - 10)
		local z = rng:NextNumber(room.MinZ + 10, room.MaxZ - 10)
		local skylight = false
		for _, cell in SKYLIGHTS do
			local cx, cz = cellCenter(cell[1], cell[2])
			if math.abs(x - cx) < 8 and math.abs(z - cz) < 8 then
				skylight = true
			end
		end
		if not skylight then
			stack(x, z, true, rng:NextNumber(0.8, 1.3))
		end
	end
	for _ = 1, 9 do
		local x, z = spot(3.5, true)
		if x and z then
			stack(x, z, false, rng:NextNumber(0.8, 1.2))
		end
	end
	for _ = 1, 7 do
		local x, z = spot(4, rng:NextNumber() < 0.6)
		if x and z then
			local w = rng:NextNumber(4, 7)
			local part = block(rockFolder, "Roca", Vector3.new(w, rng:NextNumber(2.5, 4.5), w * rng:NextNumber(0.7, 1.1)), CFrame.new(x, floorTop + 1.5, z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0), DARK[rng:NextInteger(1, 2)])
			studs(part, Enum.NormalId.Top)
		end
	end

	-- 5. Cristales que brillan (con su luz) y setas luminosas
	local glowFolder = PartFactory.folder(model, "Glow")
	for index = 1, 9 do
		local x, z = spot(3, true)
		if x and z then
			local color = CRYSTAL[index % #CRYSTAL + 1]
			local cluster = Instance.new("Model")
			cluster.Name = "Cristales"
			for shard = 1, 3 do
				local h = rng:NextNumber(3, 6.5)
				local w = rng:NextNumber(0.9, 1.6)
				local tilt = CFrame.Angles(math.rad(rng:NextNumber(-22, 22)), math.rad(rng:NextNumber(0, 180)), math.rad(rng:NextNumber(-22, 22)))
				local offset = Vector3.new(rng:NextNumber(-1.4, 1.4), 0, rng:NextNumber(-1.4, 1.4))
				local part = block(cluster, "Cristal" .. shard, Vector3.new(w, h, w), CFrame.new(Vector3.new(x, floorTop + h / 2 - 0.4, z) + offset) * tilt, color, false)
				part.Material = Enum.Material.Neon
				part.Transparency = 0.15
				if shard == 1 then
					light(part, color, 22, 1.6)
				end
			end
			cluster.Parent = glowFolder
		end
	end
	for index = 1, 12 do
		local x, z = spot(1.8, rng:NextNumber() < 0.5)
		if x and z then
			local mushroom = Instance.new("Model")
			mushroom.Name = "SetaBrillante"
			local scale = rng:NextNumber(0.8, 1.4)
			local stem = block(mushroom, "Tallo", Vector3.new(0.7, 1.8, 0.7) * scale, CFrame.new(x, floorTop + 0.9 * scale, z), RGB(236, 232, 214), false)
			stem.CastShadow = false
			local capColor = if index % 3 == 0 then RGB(255, 140, 220) else RGB(110, 236, 255)
			local cap = block(mushroom, "Sombrero", Vector3.new(2.6, 0.9, 2.6) * scale, CFrame.new(x, floorTop + (1.8 + 0.45) * scale, z), capColor, false)
			cap.Material = Enum.Material.Neon
			if index % 3 == 1 then
				light(cap, capColor, 14, 1)
			end
			mushroom.Parent = glowFolder
		end
	end

	-- 6. Antorchas: dos dentro, junto a la entrada, y dos fuera, a los lados de la boca
	local torchFolder = PartFactory.folder(model, "Torches")
	local function torch(position: Vector3)
		local stick = block(torchFolder, "Palo", Vector3.new(0.6, 3.4, 0.6), CFrame.new(position), RGB(120, 76, 40), false)
		local flame = block(torchFolder, "Llama", Vector3.new(1, 1.3, 1), CFrame.new(position + Vector3.new(0, 2.3, 0)), RGB(255, 160, 60), false)
		flame.Material = Enum.Material.Neon
		flame.CastShadow = false
		light(flame, RGB(255, 170, 90), 18, 1.6)
		local fire = Instance.new("Fire")
		fire.Size = 2.5
		fire.Heat = 4
		fire.Color = RGB(255, 150, 60)
		fire.SecondaryColor = RGB(255, 230, 120)
		fire.Parent = flame
		return stick
	end
	local doorZ0, doorZ1 = opening.MinZ, opening.MaxZ
	local inside = room.MaxX - WALL - 2
	torch(Vector3.new(inside, floorTop + 1.7, doorZ0 - 2))
	torch(Vector3.new(inside, floorTop + 1.7, doorZ1 + 2))
	local outside = opening.MaxX + 1.2
	torch(Vector3.new(outside, floorTop + 1.7, doorZ0 - 2.5))
	torch(Vector3.new(outside, floorTop + 1.7, doorZ1 + 2.5))

	-- 7. Cartel encima de la boca, en la cara de la colina que mira a la pradera
	local doorTop = GROUND + doorRows * B
	local board = block(model, "CartelCueva", Vector3.new(0.6, 5.2, 18), CFrame.new(opening.MaxX + 0.35, doorTop + 3.4, (doorZ0 + doorZ1) / 2), RGB(150, 98, 54))
	studs(board, Enum.NormalId.Right)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Texto"
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = RGB(255, 236, 170)
	label.TextStrokeColor3 = RGB(43, 29, 63)
	label.TextStrokeTransparency = 0
	label.Text = "⚠ " .. string.upper(cave.Name)
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.Parent = label

	model.Parent = parent
	return model
end

return ForestCave
