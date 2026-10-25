-- Mazmorras por dentro (CaveConfig: una cueva por zona, con la misma forma y sus colores,
-- Theme), lejos del mapa: tres salas de piedra unidas por pasillos, como la boca de la colina
-- (ForestCave) pero en grande. Las bocas del Valle y la Caldera (montículos de roca) también:
-- - Suelo de piedra en damero con studs, paredes de bloques con el hueco de cada pasillo y
--   techo de bloques con claraboyas por las que entra un haz de luz (en la sala del altar, un
--   hueco grande por el que sale la columna de luz del altar de las oleadas).
-- - Estalactitas, estalagmitas, rocas, cristales y setas que brillan (con luces), antorchas en
--   cada paso y carteles con el nombre de cada sala.
-- - Sala 1: nidos de ramas con huevos (Bosque), geodas (Valle) o charcos de lava (Caldera).
--   Sala 2: columnas de roca del suelo al techo y charcas que brillan (de lava en la Caldera).
--   Sala 3: braseros alrededor del círculo de las oleadas (WaveService pone el altar) y
--   cristales gigantes en las esquinas.
-- - Portales de salida (CaveConfig.Exits) y el círculo de llegada. El viaje lo hace CaveService.
-- Con semilla fija: siempre igual. Nada sólido se pone encima de los bichos (EnemyConfig), de
-- los caminos entre puertas, del círculo de las oleadas ni delante de los portales.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaveConfig = require(Shared.Config.CaveConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local WaveConfig = require(Shared.Config.WaveConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local PartFactory = require(script.Parent.PartFactory)
local StudWorld = require(script.Parent.StudWorld)
local ForestCave = require(script.Parent.ForestCave)

local CaveDungeon = {}

local RGB = Color3.fromRGB
local B = 8 -- bloques de 8, como el resto del mundo
local WALL = 4 -- grosor de las paredes de las salas (por dentro) y de los pasillos (por fuera)
local GROUND = GeneratorConfig.Position.Y
local SEED = 9137

-- Colores de la cueva que se está construyendo (useTheme)
local STONE = { RGB(92, 98, 128), RGB(78, 84, 112) } -- suelo
local ROCK = { RGB(104, 108, 140), RGB(86, 90, 120) } -- paredes y techo
local DARK = { RGB(70, 74, 100), RGB(58, 62, 86) } -- estalactitas, rocas y columnas
local SHAFT = RGB(255, 244, 205)
local PORTAL = RGB(150, 90, 255)
local WOOD = RGB(120, 76, 40)
local LAVA = RGB(255, 110, 30)

local function useTheme(theme)
	if not theme then
		return
	end
	STONE = theme.Stone or STONE
	ROCK = theme.Rock or ROCK
	DARK = theme.Dark or DARK
	SHAFT = theme.Shaft or SHAFT
	PORTAL = theme.Portal or PORTAL
end

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

local function glow(part: BasePart, transparency: number?)
	part.Material = Enum.Material.Neon
	part.Transparency = transparency or 0
	part.CastShadow = false
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local point = Instance.new("PointLight")
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Shadows = false
	point.Parent = parent
end

local function cells(r): (number, number)
	return math.round((r.MaxX - r.MinX) / B), math.round((r.MaxZ - r.MinZ) / B)
end

local function center(r): (number, number)
	return (r.MinX + r.MaxX) / 2, (r.MinZ + r.MaxZ) / 2
end

local function distToSegment(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1) else 0
	local cx, cz = ax + dx * t, az + dz * t
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

-- Suelo -------------------------------------------------------------------------------------

-- Damero de losas de 8 con studs (el color sale de la casilla del mundo: los pasillos siguen
-- el damero de las salas).
local function buildFloor(folder: Instance, r)
	local floorTop = StudWorld.FloorTop
	local cols, rows = cells(r)
	for i = 1, cols do
		for j = 1, rows do
			local x, z = r.MinX + (i - 0.5) * B, r.MinZ + (j - 0.5) * B
			local parity = (math.round(x / B) + math.round(z / B)) % 2 + 1
			local part = block(folder, ("suelo_%d_%d"):format(x, z), Vector3.new(B, 1, B), CFrame.new(x, floorTop - 0.5, z), STONE[parity], true)
			part.CastShadow = false
			studs(part, Enum.NormalId.Top)
		end
	end
end

-- Paredes y techo de una sala --------------------------------------------------------------

-- Lados de una sala: { nombre, ¿a lo largo de Z?, x o z fijo, cara de dentro, cara de fuera }
local function sidesOf(r)
	return {
		{ Name = "West", AlongZ = true, Fixed = r.MinX + WALL / 2, Inner = Enum.NormalId.Right, Outer = Enum.NormalId.Left, Edge = r.MinX },
		{ Name = "East", AlongZ = true, Fixed = r.MaxX - WALL / 2, Inner = Enum.NormalId.Left, Outer = Enum.NormalId.Right, Edge = r.MaxX },
		{ Name = "North", AlongZ = false, Fixed = r.MinZ + WALL / 2, Inner = Enum.NormalId.Back, Outer = Enum.NormalId.Front, Edge = r.MinZ },
		{ Name = "South", AlongZ = false, Fixed = r.MaxZ - WALL / 2, Inner = Enum.NormalId.Front, Outer = Enum.NormalId.Back, Edge = r.MaxZ },
	}
end

-- Lado de la sala `room` por el que entra el pasillo `corridor` (o nil) y el tramo del hueco.
local function doorOf(room, corridor): (string?, number?, number?)
	local r, c = room.Rect, corridor.Rect
	if c.MaxX == r.MinX then
		return "West", c.MinZ, c.MaxZ
	elseif c.MinX == r.MaxX then
		return "East", c.MinZ, c.MaxZ
	elseif c.MaxZ == r.MinZ then
		return "North", c.MinX, c.MaxX
	elseif c.MinZ == r.MaxZ then
		return "South", c.MinX, c.MaxX
	end
	return nil, nil, nil
end

local function buildRoomShell(folder: Instance, room, doors)
	local r = room.Rect
	local cols, rows = cells(r)
	local wallRows = math.round(room.Height / B)
	local wallFolder = PartFactory.folder(folder, "Walls")
	for _, side in sidesOf(r) do
		local count = if side.AlongZ then rows else cols
		local start = if side.AlongZ then r.MinZ else r.MinX
		for k = 1, count do
			local along = start + (k - 0.5) * B
			for row = 1, wallRows do
				local hole, lintel = false, false
				for _, door in doors do
					if door.Side == side.Name and along > door.From and along < door.To then
						hole = hole or row <= door.Rows
						lintel = lintel or row == door.Rows + 1
					end
				end
				if not hole then
					local x, z
					if side.AlongZ then
						x, z = side.Fixed, along
					else
						x, z = along, side.Fixed
					end
					local size = if side.AlongZ then Vector3.new(WALL, B, B) else Vector3.new(B, B, WALL)
					local part = block(wallFolder, ("pared%s_%d_%d"):format(side.Name, k, row), size, CFrame.new(x, GROUND + (row - 0.5) * B, z), ROCK[(k + row) % 2 + 1], true)
					studs(part, side.Inner)
					if lintel then
						studs(part, Enum.NormalId.Bottom)
						studs(part, side.Outer)
					end
				end
			end
		end
	end

	-- Techo en franjas por filas, sin las casillas de las claraboyas
	local roofFolder = PartFactory.folder(folder, "Roof")
	local roofY = GROUND + wallRows * B
	local function open(x: number, z: number): boolean
		for _, sky in room.Skylights or {} do
			if x > sky.MinX and x < sky.MaxX and z > sky.MinZ and z < sky.MaxZ then
				return true
			end
		end
		return false
	end
	for j = 1, rows do
		local z = r.MinZ + (j - 0.5) * B
		local i = 1
		while i <= cols do
			if open(r.MinX + (i - 0.5) * B, z) then
				i += 1
			else
				local w = 1
				while i + w <= cols and not open(r.MinX + (i + w - 0.5) * B, z) do
					w += 1
				end
				local x0 = r.MinX + (i - 1) * B
				local part = block(roofFolder, ("techo_%d_%d"):format(i, j), Vector3.new(w * B, B, B), CFrame.new(x0 + w * B / 2, roofY + B / 2, z), ROCK[j % 2 + 1], true)
				studs(part, Enum.NormalId.Bottom)
				i += w
			end
		end
	end

	-- Haz de luz en cada claraboya: un Beam que mira a la cámara y se desvanece hacia el suelo
	for index, sky in room.Skylights or {} do
		local x, z = center(sky)
		local width = sky.MaxX - sky.MinX
		local shaftHeight = roofY - StudWorld.FloorTop
		local shaft = block(roofFolder, "HazDeLuz" .. index, Vector3.new(1, 1, 1), CFrame.new(x, roofY - 0.5, z), SHAFT, false)
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
		beam.Width0 = width - 1
		beam.Width1 = width + 1
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(SHAFT)
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, if width > B then 0.75 else 0.55), NumberSequenceKeypoint.new(0.7, 0.88), NumberSequenceKeypoint.new(1, 1) })
		beam.Parent = shaft
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Bottom
		spot.Angle = if width > B then 70 else 50
		spot.Range = shaftHeight + 6
		spot.Brightness = 2
		spot.Color = SHAFT
		spot.Shadows = false
		spot.Parent = shaft
		if width <= B then
			-- Un poco de hierba donde da la luz
			local patch = block(roofFolder, "HierbaDeLuz" .. index, Vector3.new(width - 2, 0.3, width - 2), CFrame.new(x, StudWorld.FloorTop + 0.15, z), RGB(120, 200, 70), false)
			patch.CastShadow = false
		end
	end
	return roofY
end

-- Pasillo: suelo, paredes a los lados (por fuera de su rectángulo) y techo.
local function buildCorridor(folder: Instance, corridor, index: number)
	local r = corridor.Rect
	local model = Instance.new("Model")
	model.Name = "Pasillo" .. index
	buildFloor(PartFactory.folder(model, "Floor"), r)
	local alongX = (r.MaxX - r.MinX) >= (r.MaxZ - r.MinZ)
	local rows = math.round(corridor.Height / B)
	local length = if alongX then r.MaxX - r.MinX else r.MaxZ - r.MinZ
	local count = math.round(length / B)
	local walls = PartFactory.folder(model, "Walls")
	for sideIndex, sign in { -1, 1 } do
		for k = 1, count do
			for row = 1, rows do
				local cframe, size, face
				if alongX then
					local z = if sign < 0 then r.MinZ - WALL / 2 else r.MaxZ + WALL / 2
					cframe = CFrame.new(r.MinX + (k - 0.5) * B, GROUND + (row - 0.5) * B, z)
					size = Vector3.new(B, B, WALL)
					face = if sign < 0 then Enum.NormalId.Back else Enum.NormalId.Front
				else
					local x = if sign < 0 then r.MinX - WALL / 2 else r.MaxX + WALL / 2
					cframe = CFrame.new(x, GROUND + (row - 0.5) * B, r.MinZ + (k - 0.5) * B)
					size = Vector3.new(WALL, B, B)
					face = if sign < 0 then Enum.NormalId.Right else Enum.NormalId.Left
				end
				local part = block(walls, ("pared%d_%d_%d"):format(sideIndex, k, row), size, cframe, ROCK[(k + row + sideIndex) % 2 + 1], true)
				studs(part, face)
			end
		end
	end
	local roofY = GROUND + rows * B
	local roofSize = if alongX then Vector3.new(r.MaxX - r.MinX, B, r.MaxZ - r.MinZ + 2 * WALL) else Vector3.new(r.MaxX - r.MinX + 2 * WALL, B, r.MaxZ - r.MinZ)
	local cx, cz = center(r)
	local roof = block(model, "Techo", roofSize, CFrame.new(cx, roofY + B / 2, cz), ROCK[2], true)
	studs(roof, Enum.NormalId.Bottom)
	-- Una antorcha a cada lado, al tresbolillo
	local torches = PartFactory.folder(model, "Torches")
	local y = StudWorld.FloorTop + 1.7
	if alongX then
		ForestCave.torch(torches, Vector3.new(r.MinX + length * 0.3, y, r.MinZ + 1.4))
		ForestCave.torch(torches, Vector3.new(r.MinX + length * 0.7, y, r.MaxZ - 1.4))
	else
		ForestCave.torch(torches, Vector3.new(r.MinX + 1.4, y, r.MinZ + length * 0.3))
		ForestCave.torch(torches, Vector3.new(r.MaxX - 1.4, y, r.MinZ + length * 0.7))
	end
	model.Parent = folder
end

-- Portal de salida ---------------------------------------------------------------------------

local function buildExit(folder: Instance, exit, index: number)
	local floorTop = StudWorld.FloorTop
	local facing = exit.Facing.Unit
	local base = Vector3.new(exit.Position.X, floorTop, exit.Position.Z)
	local frame = CFrame.lookAt(base, base + facing) -- -Z del marco mira a la sala
	local model = Instance.new("Model")
	model.Name = "PortalSalida" .. index
	local stone = DARK[1]
	local width, height = 9, 12
	for _, side in { -1, 1 } do
		local pillar = block(model, "Columna", Vector3.new(2, height, 2), frame * CFrame.new(side * (width / 2 + 1), height / 2, 0), stone, true)
		studs(pillar, Enum.NormalId.Front)
	end
	local lintel = block(model, "Dintel", Vector3.new(width + 4, 2, 2), frame * CFrame.new(0, height + 1, 0), stone, true)
	studs(lintel, Enum.NormalId.Front)
	-- Fondo negro y, delante, el remolino morado (sin colisión: se cruza andando)
	local core = block(model, "Fondo", Vector3.new(width, height, 0.3), frame * CFrame.new(0, height / 2, 0.6), RGB(8, 6, 18), false)
	core.CastShadow = false
	local swirl = block(model, "Remolino", Vector3.new(width, height, 0.2), frame * CFrame.new(0, height / 2, 0.2), PORTAL, false)
	glow(swirl, 0.35)
	ForestCave.motes(swirl, RGB(210, 170, 255), Enum.NormalId.Front, 18)
	light(swirl, PORTAL, 18, 1.4)
	-- Losa brillante delante
	local step = block(model, "Losa", Vector3.new(width + 2, 0.2, 4), frame * CFrame.new(0, 0.1, -2.4), PORTAL, false)
	glow(step, 0.45)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Cartel"
	billboard.Size = UDim2.fromOffset(240, 64)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 120
	billboard.Adornee = lintel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = RGB(230, 210, 255)
	label.TextStrokeColor3 = RGB(43, 29, 63)
	label.TextStrokeTransparency = 0
	label.Text = "🚪 SALIR DE LA CUEVA"
	label.Parent = billboard
	billboard.Parent = lintel
	model.Parent = folder
end

-- Decoración de cada sala --------------------------------------------------------------------

local function decorate(folder: Instance, room, roomIndex: number, doors, roofY: number, rng: Random, cave)
	local r = room.Rect
	local floorTop = StudWorld.FloorTop
	local cx, cz = center(r)
	local area = (r.MaxX - r.MinX) * (r.MaxZ - r.MinZ) / (96 * 96)

	-- Sitios ocupados (círculos en planta) y caminos que deben quedar libres
	local blocked: { { number } } = {}
	local lanes: { { number } } = {}
	local zone = ZoneConfig.Zones[cave.Zone]
	local originX = GeneratorConfig.Position.X + zone.Center.X
	local originZ = GeneratorConfig.Position.Z + zone.Center.Y
	if cave.MiniBoss then
		local p = cave.MiniBoss.Position
		if p.X > r.MinX and p.X < r.MaxX and p.Z > r.MinZ and p.Z < r.MaxZ then
			table.insert(blocked, { p.X, p.Z, 12 })
		end
	end
	for _, spawnInfo in EnemyConfig.Zones[cave.Zone].Spawns do
		local x, z = originX + spawnInfo.Offset.X, originZ + spawnInfo.Offset.Y
		if x > r.MinX and x < r.MaxX and z > r.MinZ and z < r.MaxZ then
			table.insert(blocked, { x, z, 7 })
		end
	end
	for _, sky in room.Skylights or {} do
		local sx, sz = center(sky)
		table.insert(blocked, { sx, sz, (sky.MaxX - sky.MinX) / 2 + 2 })
	end
	for _, door in doors do
		local mid = (door.From + door.To) / 2
		local dx, dz
		if door.Side == "West" then
			dx, dz = r.MinX, mid
		elseif door.Side == "East" then
			dx, dz = r.MaxX, mid
		elseif door.Side == "North" then
			dx, dz = mid, r.MinZ
		else
			dx, dz = mid, r.MaxZ
		end
		table.insert(lanes, { dx, dz, cx, cz })
		table.insert(blocked, { dx, dz, 9 })
	end
	for _, exit in CaveConfig.Exits do
		if exit.Room == roomIndex then
			table.insert(blocked, { exit.Position.X, exit.Position.Z, 10 })
			table.insert(lanes, { exit.Position.X, exit.Position.Z, cx, cz })
		end
	end
	local arrival = cave.Arrival.Position
	if arrival.X > r.MinX and arrival.X < r.MaxX and arrival.Z > r.MinZ and arrival.Z < r.MaxZ then
		table.insert(blocked, { arrival.X, arrival.Z, 8 })
	end
	if room.Altar then
		table.insert(blocked, { cx, cz, WaveConfig.Place.AreaRadius + 7 })
	end

	local function isFree(x: number, z: number, radius: number, solid: boolean): boolean
		if x < r.MinX + WALL + radius or x > r.MaxX - WALL - radius or z < r.MinZ + WALL + radius or z > r.MaxZ - WALL - radius then
			return false
		end
		if solid then
			for _, lane in lanes do
				if distToSegment(x, z, lane[1], lane[2], lane[3], lane[4]) < 6 + radius then
					return false
				end
			end
		end
		for _, k in blocked do
			if (x - k[1]) ^ 2 + (z - k[2]) ^ 2 < (k[3] + radius) ^ 2 then
				return false
			end
		end
		return true
	end
	local function spot(radius: number, nearWall: boolean, solid: boolean): (number?, number?)
		for _ = 1, 80 do
			local x = rng:NextNumber(r.MinX, r.MaxX)
			local z = rng:NextNumber(r.MinZ, r.MaxZ)
			if nearWall then
				local side = rng:NextInteger(1, 4)
				local inset = WALL + radius + rng:NextNumber(0, 3)
				if side == 1 then
					x = r.MinX + inset
				elseif side == 2 then
					x = r.MaxX - inset
				elseif side == 3 then
					z = r.MinZ + inset
				else
					z = r.MaxZ - inset
				end
			end
			if isFree(x, z, radius, solid) then
				table.insert(blocked, { x, z, radius })
				return x, z
			end
		end
		return nil, nil
	end

	-- Estalactitas (del techo) y estalagmitas (del suelo): bloques que se estrechan
	local rockFolder = PartFactory.folder(folder, "Rocks")
	local function stack(x: number, z: number, down: boolean, scale: number)
		local sizes = { 5, 3.6, 2.2, 1.2 }
		local y = if down then roofY else floorTop
		for index, size in sizes do
			local s = size * scale
			local h = s * 1.1
			local mid = if down then y - h / 2 else y + h / 2
			local part = block(rockFolder, if down then "Estalactita" else "Estalagmita", Vector3.new(s, h, s), CFrame.new(x, mid, z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0), DARK[index % 2 + 1], index <= 2 and not down)
			studs(part, if down then Enum.NormalId.Bottom else Enum.NormalId.Top)
			y = if down then y - h else y + h
		end
	end
	for _ = 1, math.round(14 * area) do
		local x = rng:NextNumber(r.MinX + 10, r.MaxX - 10)
		local z = rng:NextNumber(r.MinZ + 10, r.MaxZ - 10)
		local underSky = false
		for _, sky in room.Skylights or {} do
			if x > sky.MinX - 4 and x < sky.MaxX + 4 and z > sky.MinZ - 4 and z < sky.MaxZ + 4 then
				underSky = true
			end
		end
		if not underSky then
			stack(x, z, true, rng:NextNumber(0.9, 1.5))
		end
	end
	for _ = 1, math.round(7 * area) do
		local x, z = spot(3.5, true, true)
		if x and z then
			stack(x, z, false, rng:NextNumber(0.8, 1.3))
		end
	end
	for _ = 1, math.round(5 * area) do
		local x, z = spot(4, rng:NextNumber() < 0.6, true)
		if x and z then
			local w = rng:NextNumber(4, 7)
			local part = block(rockFolder, "Roca", Vector3.new(w, rng:NextNumber(2.5, 4.5), w * rng:NextNumber(0.7, 1.1)), CFrame.new(x, floorTop + 1.5, z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0), DARK[rng:NextInteger(1, 2)], true)
			studs(part, Enum.NormalId.Top)
		end
	end

	-- Cristales que brillan (con su luz) y setas luminosas
	local glowFolder = PartFactory.folder(folder, "Glow")
	local function crystals(x: number, z: number, color: Color3, scale: number, range: number)
		local cluster = Instance.new("Model")
		cluster.Name = "Cristales"
		for shard = 1, 3 do
			local h = rng:NextNumber(3, 6.5) * scale
			local w = rng:NextNumber(0.9, 1.6) * scale
			local tilt = CFrame.Angles(math.rad(rng:NextNumber(-22, 22)), math.rad(rng:NextNumber(0, 180)), math.rad(rng:NextNumber(-22, 22)))
			local offset = Vector3.new(rng:NextNumber(-1.4, 1.4), 0, rng:NextNumber(-1.4, 1.4)) * scale
			local part = block(cluster, "Cristal" .. shard, Vector3.new(w, h, w), CFrame.new(Vector3.new(x, floorTop + h / 2 - 0.4, z) + offset) * tilt, color, false)
			glow(part, 0.15)
			if shard == 1 then
				light(part, color, range, 1.6)
			end
		end
		cluster.Parent = glowFolder
	end
	for index = 1, math.round(7 * area) do
		local x, z = spot(3, true, false)
		if x and z then
			crystals(x, z, room.Crystal[index % #room.Crystal + 1], 1, 22)
		end
	end
	for index = 1, math.round(10 * area) do
		local x, z = spot(1.8, rng:NextNumber() < 0.5, false)
		if x and z then
			local mushroom = Instance.new("Model")
			mushroom.Name = "SetaBrillante"
			local scale = rng:NextNumber(0.8, 1.4)
			local stem = block(mushroom, "Tallo", Vector3.new(0.7, 1.8, 0.7) * scale, CFrame.new(x, floorTop + 0.9 * scale, z), RGB(236, 232, 214), false)
			stem.CastShadow = false
			local capColor = room.Mushroom[index % #room.Mushroom + 1]
			local cap = block(mushroom, "Sombrero", Vector3.new(2.6, 0.9, 2.6) * scale, CFrame.new(x, floorTop + (1.8 + 0.45) * scale, z), capColor, false)
			glow(cap)
			if index % 3 == 1 then
				light(cap, capColor, 14, 1)
			end
			mushroom.Parent = glowFolder
		end
	end

	-- Antorchas a los lados de cada paso (por dentro de la sala)
	local torchFolder = PartFactory.folder(folder, "Torches")
	local y = floorTop + 1.7
	for _, door in doors do
		local inset = WALL + 1.5
		for _, edge in { door.From - 2.5, door.To + 2.5 } do
			local position
			if door.Side == "West" then
				position = Vector3.new(r.MinX + inset, y, edge)
			elseif door.Side == "East" then
				position = Vector3.new(r.MaxX - inset, y, edge)
			elseif door.Side == "North" then
				position = Vector3.new(edge, y, r.MinZ + inset)
			else
				position = Vector3.new(edge, y, r.MaxZ - inset)
			end
			ForestCave.torch(torchFolder, position)
		end
	end

	-- Lo propio de cada sala
	local special = PartFactory.folder(folder, "Special")
	if room.Id == "Nest" and cave.Id == "CrystalValley" then
		-- Geodas: rocas abiertas con cristales dentro
		for index = 1, 4 do
			local x, z = spot(4, false, true)
			if x and z then
				for side = 1, 5 do
					local a = side / 5 * math.pi * 2
					local part = block(special, "Geoda", Vector3.new(2.6, rng:NextNumber(1.8, 3), 2.6), CFrame.new(x + math.cos(a) * 2.6, floorTop + 1, z + math.sin(a) * 2.6) * CFrame.Angles(0, -a, math.rad(rng:NextNumber(-12, 12))), DARK[side % 2 + 1], true)
					studs(part, Enum.NormalId.Top)
				end
				crystals(x, z, room.Crystal[index % #room.Crystal + 1], 0.9, 18)
			end
		end
	elseif room.Id == "Nest" and cave.Id == "EmberCaldera" then
		-- Charcos de lava con su borde de roca
		for _ = 1, 4 do
			local x, z = spot(4.5, false, false)
			if x and z then
				local size = rng:NextNumber(6, 8)
				local pool = PartFactory.verticalCylinder(special, "Lava", Vector3.new(x, floorTop + 0.08, z), 0.16, size, LAVA, Enum.Material.Neon, false)
				pool.CastShadow = false
				light(pool, LAVA, 16, 1.4)
				local rim = PartFactory.verticalCylinder(special, "Borde", Vector3.new(x, floorTop + 0.04, z), 0.08, size + 1.6, DARK[1], Enum.Material.Slate, false)
				rim.CastShadow = false
				local smoke = Instance.new("Smoke")
				smoke.Color = RGB(80, 60, 56)
				smoke.Opacity = 0.08
				smoke.RiseVelocity = 3
				smoke.Size = 3
				smoke.Parent = pool
			end
		end
	elseif room.Id == "Nest" and cave.Id == "FrozenTundra" then
		-- Montones de nieve con pinchos de hielo y carámbanos colgando del techo
		for index = 1, 5 do
			local x, z = spot(4, false, true)
			if x and z then
				local drift = PartFactory.ellipsoid(special, "Nieve", CFrame.new(x, floorTop + 0.5, z), Vector3.new(rng:NextNumber(6, 8), 2.2, rng:NextNumber(5, 7)), RGB(240, 246, 255), Enum.Material.Snow)
				drift.CastShadow = false
				crystals(x, z, room.Crystal[index % #room.Crystal + 1], 0.8, 16)
			end
		end
		for _ = 1, 10 do
			local x, z = spot(2, false, false)
			if x and z then
				local length = rng:NextNumber(2.5, 5)
				local icicle = block(special, "Carambano", Vector3.new(0.9, length, 0.9), CFrame.new(x, roofY - length / 2, z) * CFrame.Angles(0, math.rad(45), 0), room.Crystal[2], false)
				icicle.Material = Enum.Material.Glass
				icicle.Transparency = 0.25
			end
		end
	elseif room.Id == "Nest" then
		-- Nidos de ramas con huevos
		for _ = 1, 4 do
			local x, z = spot(3.5, false, false)
			if x and z then
				local nest = Instance.new("Model")
				nest.Name = "Nido"
				for stick = 1, 8 do
					local a0 = stick / 8 * math.pi * 2
					local a1 = a0 + math.pi * 2 / 8 * 1.3
					local from = Vector3.new(x + math.cos(a0) * 2.6, floorTop + 0.35, z + math.sin(a0) * 2.6)
					local to = Vector3.new(x + math.cos(a1) * 2.6, floorTop + 0.55, z + math.sin(a1) * 2.6)
					PartFactory.segment(nest, "Rama", from, to, 0.5, WOOD, Enum.Material.Wood, false)
				end
				for egg = 1, 3 do
					local a = egg / 3 * math.pi * 2 + rng:NextNumber(0, 1)
					local ball = PartFactory.ellipsoid(nest, "Huevo", CFrame.new(x + math.cos(a) * 0.9, floorTop + 0.7, z + math.sin(a) * 0.9), Vector3.new(1.1, 1.4, 1.1), RGB(236, 226, 190), Enum.Material.SmoothPlastic)
					ball.CastShadow = false
				end
				nest.Parent = special
			end
		end
	elseif room.Id == "Gallery" then
		-- Columnas de roca del suelo al techo (estalactita y estalagmita que se juntan)
		for _ = 1, 3 do
			local x, z = spot(4.5, false, true)
			if x and z then
				local height = roofY - floorTop
				local widths = { 7, 5.5, 4, 3.2, 4, 5.5, 7 }
				local slice = height / #widths
				for index, w in widths do
					local part = block(special, "Columna", Vector3.new(w, slice, w), CFrame.new(x, floorTop + (index - 0.5) * slice, z) * CFrame.Angles(0, math.rad(index * 17), 0), DARK[index % 2 + 1], true)
					studs(part, Enum.NormalId.Front)
				end
			end
		end
		-- Charcas que brillan
		for index = 1, 2 do
			local x, z = spot(4.5, false, false)
			if x and z then
				local color = if cave.Id == "EmberCaldera" then LAVA else room.Crystal[index]
				local pool = PartFactory.verticalCylinder(special, "Charca", Vector3.new(x, floorTop + 0.08, z), 0.16, rng:NextNumber(7, 9), color, Enum.Material.Neon, false)
				pool.Transparency = 0.35
				pool.CastShadow = false
				light(pool, color, 16, 1.2)
			end
		end
	elseif room.Altar then
		-- Braseros en anillo alrededor del círculo de las oleadas (sin pisar los caminos)
		for index = 1, 8 do
			local angle = math.rad(22.5 + (index - 1) * 45)
			local x, z = cx + math.cos(angle) * 31, cz + math.sin(angle) * 31
			local stand = PartFactory.verticalCylinder(special, "Brasero", Vector3.new(x, floorTop + 1.6, z), 3.2, 2.6, DARK[1], Enum.Material.Slate, true)
			stand.CastShadow = false
			local bowl = PartFactory.verticalCylinder(special, "Cuenco", Vector3.new(x, floorTop + 3.5, z), 0.8, 4, RGB(54, 46, 44), Enum.Material.Metal, false)
			-- En la Gruta Glacial, fuego azul
			local icy = cave.Id == "FrozenTundra"
			local flame = block(special, "Llama", Vector3.new(1.6, 1.6, 1.6), CFrame.new(x, floorTop + 4.4, z), if icy then RGB(110, 200, 255) else RGB(255, 160, 60), false)
			glow(flame)
			light(flame, if icy then RGB(140, 210, 255) else RGB(255, 170, 90), 24, 1.8)
			local fire = Instance.new("Fire")
			fire.Size = 4
			fire.Heat = 6
			fire.Color = if icy then RGB(90, 180, 255) else RGB(255, 150, 60)
			fire.SecondaryColor = if icy then RGB(220, 245, 255) else RGB(255, 230, 120)
			fire.Parent = bowl
		end
		-- Cristales gigantes en las esquinas
		for _, corner in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			local x = cx + corner[1] * ((r.MaxX - r.MinX) / 2 - 12)
			local z = cz + corner[2] * ((r.MaxZ - r.MinZ) / 2 - 12)
			crystals(x, z, room.Crystal[1], 2.4, 34)
		end
	end
end

-- Carteles de los pasos: por fuera, el nombre de la sala; por dentro, a dónde lleva.
local function doorSigns(folder: Instance, room, door, otherRoom, roomIndex: number, otherIndex: number)
	local r = room.Rect
	local mid = (door.From + door.To) / 2
	local y = GROUND + door.Rows * B + 3.2
	local width = door.To - door.From - 2
	for _, outside in { true, false } do
		local text = if outside then "⚠ " .. room.Label else (if otherIndex > roomIndex then "➜ " else "⬅ ") .. otherRoom.Label
		local depth = if outside then 0.35 else WALL + 0.35
		local cframe, size, face
		if door.Side == "West" or door.Side == "East" then
			local edge = if door.Side == "West" then r.MinX else r.MaxX
			local inward = if door.Side == "West" then 1 else -1
			local x = edge + inward * (if outside then -depth else depth)
			cframe = CFrame.new(x, y, mid)
			size = Vector3.new(0.6, 4.4, width)
			face = if (inward > 0) == outside then Enum.NormalId.Left else Enum.NormalId.Right
		else
			local edge = if door.Side == "North" then r.MinZ else r.MaxZ
			local inward = if door.Side == "North" then 1 else -1
			local z = edge + inward * (if outside then -depth else depth)
			cframe = CFrame.new(mid, y, z)
			size = Vector3.new(width, 4.4, 0.6)
			face = if (inward > 0) == outside then Enum.NormalId.Front else Enum.NormalId.Back
		end
		ForestCave.sign(folder, "Cartel", size, cframe, face, text)
	end
end

-- Círculo de llegada (runas moradas en el suelo)
local function buildArrival(folder: Instance, cave)
	local position = cave.Arrival.Position
	local floorTop = StudWorld.FloorTop
	local model = Instance.new("Model")
	model.Name = "Llegada"
	local tiles = 16
	for index = 1, tiles do
		local angle = index / tiles * math.pi * 2
		local p = Vector3.new(position.X + math.cos(angle) * 4, floorTop + 0.1, position.Z + math.sin(angle) * 4)
		local tile = block(model, "Runa" .. index, Vector3.new(0.8, 0.2, 1.6), CFrame.lookAt(p, Vector3.new(position.X, p.Y, position.Z)), PORTAL, false)
		glow(tile, 0.25)
	end
	model.Parent = folder
end

function CaveDungeon.build(parent: Instance): Model
	local root = Instance.new("Model")
	root.Name = "CuevaDentro"

	-- Pasos de cada sala (por qué lado entra cada pasillo), de todas las cuevas
	local doorsOf: { [number]: { any } } = {}
	for index in CaveConfig.Rooms do
		doorsOf[index] = {}
	end
	for _, corridor in CaveConfig.Corridors do
		for _, roomIndex in { corridor.From, corridor.To } do
			local room = CaveConfig.Rooms[roomIndex]
			local side, from, to = doorOf(room, corridor)
			if side then
				table.insert(doorsOf[roomIndex], {
					Side = side,
					From = from,
					To = to,
					Rows = math.round(corridor.Height / B),
					Other = if roomIndex == corridor.From then corridor.To else corridor.From,
				})
			else
				warn(("[CaveDungeon] El pasillo %d-%d no toca la sala %d"):format(corridor.From, corridor.To, roomIndex))
			end
		end
	end

	for order, caveId in CaveConfig.Order do
		local cave = CaveConfig.Caves[caveId]
		useTheme(cave.Theme)
		local rng = Random.new(SEED + order - 1)
		local model = Instance.new("Model")
		model.Name = "Cueva_" .. caveId
		for index, room in CaveConfig.Rooms do
			if room.Cave ~= caveId then
				continue
			end
			local roomModel = Instance.new("Model")
			roomModel.Name = ("Sala%d_%s"):format(room.Local, room.Id)
			buildFloor(PartFactory.folder(roomModel, "Floor"), room.Rect)
			local roofY = buildRoomShell(roomModel, room, doorsOf[index])
			decorate(roomModel, room, index, doorsOf[index], roofY, rng, cave)
			for _, door in doorsOf[index] do
				local other = CaveConfig.Rooms[door.Other]
				doorSigns(roomModel, room, door, other, room.Local, other.Local)
			end
			roomModel.Parent = model
		end
		for index, corridor in CaveConfig.Corridors do
			if corridor.Cave == caveId then
				buildCorridor(model, corridor, index)
			end
		end
		local exits = PartFactory.folder(model, "Salidas")
		for index, exit in CaveConfig.Exits do
			if exit.Cave == caveId then
				buildExit(exits, exit, index)
			end
		end
		buildArrival(model, cave)
		-- La boca (montículo) de las cuevas del Valle y la Caldera, en su zona
		if cave.Entrance.Mound then
			ForestCave.buildMound(model, cave)
		end
		model.Parent = root
		task.wait() -- una cueva por vez (no bloquear el servidor)
	end
	useTheme(CaveConfig.Caves[CaveConfig.Order[1]].Theme)

	root.Parent = parent
	return root
end

return CaveDungeon
