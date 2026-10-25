-- Jardín de los Huevos rediseñado (diseño "Jardín de los Huevos" de Santiago, Claude
-- Design), pasado a piezas de Roblox con las mismas medidas (1 = 1 stud):
-- - Terraza de piedra de dos alturas con escalones, suelo de adoquín y una rosa de los
--   vientos: rayos de piedra clara y, hacia cada huevo, un camino de runas de su color.
-- - Muro bajo con seto encima, columnas rematadas con huevos de seto recortado y una
--   puerta lunar con hiedra, farolillos y el cartel con el nombre.
-- - Estanque central con el Nido Mayor: nido de ramas, gran huevo de mármol con bandas
--   doradas y cristales de los colores de los huevos girando encima.
-- - Santuarios (EggStandService): tarima octogonal, pedestal con nido, arco con hiedra y un
--   halo del color del huevo detrás; setas, piedras rúnicas o cristales según el huevo.
--
-- Marco del diseño: centro del jardín en el suelo, con la ENTRADA hacia +Z local (en el
-- diseño, el ángulo 90). Los ángulos de este módulo son los del diseño: x = r·cos, z = r·sin.

local EggGardenTerrace = {}

local RGB = Color3.fromRGB
EggGardenTerrace.FLOOR = 0.95 -- altura del suelo de la terraza sobre el terreno

local MATS: { [string]: { Color: Color3, Material: Enum.Material, Transparency: number? } } = {
	cobble = { Color = RGB(179, 171, 152), Material = Enum.Material.Cobblestone },
	stone = { Color = RGB(176, 172, 158), Material = Enum.Material.Slate },
	stone_light = { Color = RGB(214, 207, 189), Material = Enum.Material.Limestone },
	darkstone = { Color = RGB(96, 98, 92), Material = Enum.Material.Slate },
	marble = { Color = RGB(238, 234, 222), Material = Enum.Material.Marble },
	gold = { Color = RGB(244, 204, 110), Material = Enum.Material.Metal },
	gold_glow = { Color = RGB(244, 204, 110), Material = Enum.Material.Neon },
	hedge1 = { Color = RGB(58, 118, 54), Material = Enum.Material.Grass },
	hedge2 = { Color = RGB(66, 128, 58), Material = Enum.Material.Grass },
	hedge3 = { Color = RGB(52, 108, 50), Material = Enum.Material.Grass },
	moss = { Color = RGB(92, 140, 64), Material = Enum.Material.Grass },
	wood = { Color = RGB(110, 80, 54), Material = Enum.Material.Wood },
	wood_light = { Color = RGB(138, 102, 68), Material = Enum.Material.Wood },
	iron = { Color = RGB(58, 58, 64), Material = Enum.Material.Metal },
	water = { Color = RGB(104, 186, 220), Material = Enum.Material.Glass, Transparency = 0.3 },
	lamp = { Color = RGB(255, 226, 170), Material = Enum.Material.Neon },
	crystal = { Color = RGB(110, 236, 220), Material = Enum.Material.Neon },
	mushroom = { Color = RGB(96, 224, 200), Material = Enum.Material.Neon },
	stem = { Color = RGB(236, 226, 200), Material = Enum.Material.SmoothPlastic },
	fl_pink = { Color = RGB(255, 130, 180), Material = Enum.Material.SmoothPlastic },
	fl_yellow = { Color = RGB(255, 220, 100), Material = Enum.Material.SmoothPlastic },
	fl_violet = { Color = RGB(200, 150, 255), Material = Enum.Material.SmoothPlastic },
	fl_white = { Color = RGB(255, 255, 255), Material = Enum.Material.SmoothPlastic },
}
local FLOWERS = { "fl_pink", "fl_yellow", "fl_violet", "fl_white" }
local HEDGE = { "hedge1", "hedge2", "hedge3" }

-- Piezas que chocan (se puede subir a la terraza, no atravesar muros ni el estanque).
local SOLID = {
	TerraceBase = true, TerraceTop = true, Step = true, Wall = true, WallCap = true, Hedge = true,
	ColumnBase = true, Column = true, GateRing = true, GateFoot = true, Basin = true, Island = true,
	Dais = true, DaisTop = true, DaisStep = true, Pedestal = true, ArchPillar = true, ArchFoot = true,
	Seat = true, Pot = true, LampBase = true, LampPost = true, RuneStone = true,
}

-- Color propio (acento de un huevo) en vez de una clave de la paleta.
export type Look = { Color: Color3, Material: Enum.Material, Transparency: number? }

local function finish(piece: BasePart, parent: Instance, name: string, look: any)
	local spec = if type(look) == "string" then (MATS[look] or MATS.stone) else look
	piece.Name = name
	piece.Anchored = true
	piece.CanTouch = false
	piece.Color = spec.Color
	piece.Material = spec.Material
	piece.Transparency = spec.Transparency or 0
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	if not SOLID[name] then
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CastShadow = false
	end
	piece.Parent = parent
end

local function at(base: CFrame, pos: { number }, rot: { number }?): CFrame
	local frame = base * CFrame.new(pos[1], pos[2], pos[3])
	if rot then
		frame *= CFrame.Angles(rot[1], rot[2], rot[3])
	end
	return frame
end

local function box(parent: Instance, base: CFrame, name: string, look: any, size: { number }, pos: { number }, rot: { number }?): Part
	local piece = Instance.new("Part")
	piece.Size = Vector3.new(math.max(size[1], 0.05), math.max(size[2], 0.05), math.max(size[3], 0.05))
	piece.CFrame = at(base, pos, rot)
	finish(piece, parent, name, look)
	return piece
end

local function ball(parent: Instance, base: CFrame, name: string, look: any, radius: number, pos: { number }): Part
	local piece = Instance.new("Part")
	piece.Shape = Enum.PartType.Ball
	piece.Size = Vector3.one * radius * 2
	piece.CFrame = at(base, pos)
	finish(piece, parent, name, look)
	return piece
end

-- Elipsoide (esfera nativa estirada con SpecialMesh).
local function ellip(parent: Instance, base: CFrame, name: string, look: any, size: { number }, pos: { number }, rot: { number }?): Part
	local piece = Instance.new("Part")
	piece.Size = Vector3.new(size[1], size[2], size[3])
	piece.CFrame = at(base, pos, rot)
	finish(piece, parent, name, look)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = piece
	return piece
end

local AXIS = { y = CFrame.Angles(0, 0, math.pi / 2), z = CFrame.Angles(0, math.pi / 2, 0), x = CFrame.identity }
local function cyl(parent: Instance, base: CFrame, name: string, look: any, radius: number, height: number, pos: { number }, axis: string?): Part
	local piece = Instance.new("Part")
	piece.Shape = Enum.PartType.Cylinder
	piece.Size = Vector3.new(math.max(height, 0.05), radius * 2, radius * 2)
	piece.CFrame = at(base, pos) * AXIS[axis or "y"]
	finish(piece, parent, name, look)
	return piece
end

-- Prisma octogonal (tarimas y macetas): cuatro tablas cruzadas. `radius` = radio exterior.
local function octagon(parent: Instance, base: CFrame, name: string, look: any, radius: number, height: number, pos: { number })
	local apothem = radius * math.cos(math.pi / 8)
	local width = 2 * apothem * math.tan(math.pi / 8)
	for k = 0, 3 do
		box(parent, base, name, look, { 2 * apothem, height, width }, pos, { 0, k * math.pi / 4, 0 })
	end
end

-- Cristal octaédrico (cubo girado y estirado).
local function gem(parent: Instance, base: CFrame, name: string, look: any, size: number, pos: { number }, scale: { number }?, rot: { number }?)
	local sc = scale or { 1, 1.5, 1 }
	local piece = Instance.new("Part")
	piece.Size = Vector3.new(size * 1.2 * sc[1], size * 1.2 * sc[2], size * 1.2 * sc[3])
	piece.CFrame = at(base, pos, rot) * CFrame.Angles(0, math.rad(45), 0)
	finish(piece, parent, name, look)
end

-- Pirámide de base cuadrada (tejadillo de los farolillos): cuatro CornerWedge.
local function pyramid(parent: Instance, base: CFrame, name: string, look: any, side: number, height: number, pos: { number })
	local frame = at(base, pos)
	local s = side / 2
	for _, q in { { -1, 1, 0 }, { 1, 1, 90 }, { 1, -1, 180 }, { -1, -1, 270 } } do
		local piece = Instance.new("CornerWedgePart")
		piece.Size = Vector3.new(s, height, s)
		piece.CFrame = frame * CFrame.new(q[1] * s / 2, height / 2, q[2] * s / 2) * CFrame.Angles(0, math.rad(q[3]), 0)
		finish(piece, parent, name, look)
	end
end

local function group(base: CFrame, pos: { number }, yaw: number?): CFrame
	return base * CFrame.new(pos[1], pos[2], pos[3]) * CFrame.Angles(0, yaw or 0, 0)
end

local function polar(r: number, degrees: number): (number, number)
	local a = math.rad(degrees)
	return r * math.cos(a), r * math.sin(a)
end

-- Grupo en el ángulo `degrees` con su +Z local mirando al centro.
local function facingCenter(base: CFrame, r: number, degrees: number, y: number): CFrame
	local x, z = polar(r, degrees)
	return group(base, { x, y, z }, math.atan2(-x, -z))
end

-- Tramo tangente a un círculo (x local = radial).
local function ringBox(parent: Instance, base: CFrame, name: string, look: any, r: number, degrees: number, size: { number }, y: number): Part
	local x, z = polar(r, degrees)
	return box(parent, base, name, look, size, { x, y, z }, { 0, -math.rad(degrees), 0 })
end

-- Arco vertical en el plano XY local (bloques).
local function arcXY(parent: Instance, base: CFrame, name: string, look: any, cx: number, cy: number, z: number, r: number, thick: number, depth: number, a0: number, a1: number, count: number)
	local step = (a1 - a0) / count
	local len = 2 * r * math.sin(step / 2) + 0.06
	for i = 0, count - 1 do
		local t = a0 + step * (i + 0.5)
		box(parent, base, name, look, { thick, len, depth }, { cx + r * math.cos(t), cy + r * math.sin(t), z }, { 0, 0, t })
	end
end

local function lantern(parent: Instance, base: CFrame, pos: { number }, s: number)
	local l = group(base, pos)
	box(parent, l, "LanternCap", "iron", { s * 1.35, s * 0.22, s * 1.35 }, { 0, s * 0.62, 0 })
	pyramid(parent, l, "LanternRoof", "iron", s * 1.15, s * 0.5, { 0, s * 0.7, 0 })
	local glass = box(parent, l, "LanternGlass", "lamp", { s, s, s }, { 0, 0, 0 })
	box(parent, l, "LanternBase", "iron", { s * 1.15, s * 0.18, s * 1.15 }, { 0, -s * 0.58, 0 })
	local light = Instance.new("PointLight")
	light.Color = MATS.lamp.Color
	light.Range = 12
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = glass
end

local function flowerCluster(parent: Instance, base: CFrame, pos: { number }, n: number, spread: number, random: any)
	for i = 0, n - 1 do
		local a = random:range(0, math.pi * 2)
		local d = random:range(0, spread)
		local x, z = pos[1] + math.cos(a) * d, pos[3] + math.sin(a) * d
		ball(parent, base, "FlowerLeaves", "moss", 0.26, { x, pos[2] + 0.15, z })
		ball(parent, base, "Flower", FLOWERS[((i + random:int(0, 3)) % 4) + 1], 0.17, { x, pos[2] + 0.38, z })
	end
end

-- Cartel de madera con texto en la cara que mira a +Z local.
local function textBoard(parent: Instance, base: CFrame, size: { number }, pos: { number }, text: string): Part
	local board = box(parent, base, "Sign", { Color = RGB(90, 62, 38), Material = Enum.Material.Wood }, size, pos)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.3
	gui.MaxDistance = 140
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = RGB(255, 244, 220)
	label.TextStrokeColor3 = RGB(42, 26, 14)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.PaddingTop = UDim.new(0.14, 0)
	padding.PaddingBottom = UDim.new(0.14, 0)
	padding.Parent = label
	label.Parent = gui
	gui.Parent = board
	return board
end

local function accentLook(color: Color3): Look
	return { Color = color, Material = Enum.Material.Neon }
end

local function haloLook(color: Color3): Look
	return { Color = color, Material = Enum.Material.Neon, Transparency = 0.72 }
end

-- Jardín ---------------------------------------------------------------------------------------
-- opts: Name (cartel), Stands = { { Angle (grados del diseño), Accent: Color3 } },
-- Lamps / Benches / Planters = { { X, Z } } en el marco del diseño (los pone
-- LandscapeLayout), GateHalfAngle, Radius (del muro), FountainRadius, Random.
function EggGardenTerrace.garden(parent: Instance, root: CFrame, opts: any)
	local random = opts.Random
	local F = EggGardenTerrace.FLOOR
	local wallR = opts.Radius - 0.4
	local gap = opts.GateHalfAngle
	-- Terraza de dos piedras y suelo
	cyl(parent, root, "TerraceBase", "darkstone", wallR + 1, 0.5, { 0, 0.25, 0 })
	cyl(parent, root, "TerraceTop", "stone", wallR + 0.5, 0.45, { 0, 0.72, 0 })
	cyl(parent, root, "FloorBand", "stone_light", wallR - 0.4, 0.05, { 0, F + 0.02, 0 })
	cyl(parent, root, "FloorCobble", "cobble", wallR - 1.1, 0.05, { 0, F + 0.035, 0 })
	cyl(parent, root, "InnerBand", "stone_light", 5.6, 0.06, { 0, F + 0.05, 0 })
	-- Rosa de los vientos: rayos claros; hacia cada huevo, una runa de su color.
	local rays = { { Angle = 90, Gate = true }, { Angle = 150 }, { Angle = 30 }, { Angle = 0 }, { Angle = 180 } }
	for _, stand in opts.Stands do
		table.insert(rays, { Angle = stand.Angle, Accent = stand.Accent })
	end
	for _, ray in rays do
		local r0 = 5.6
		local r1 = if ray.Gate then wallR + 0.7 elseif ray.Accent then 6.7 else wallR - 1.1
		local mid = (r0 + r1) / 2
		ringBox(parent, root, "FloorRay", "stone_light", mid, ray.Angle, { r1 - r0, 0.06, if ray.Gate then 3.2 else 1.1 }, F + 0.06)
		if ray.Accent then
			ringBox(parent, root, "RunePath", accentLook(ray.Accent), mid, ray.Angle, { r1 - r0, 0.07, 0.22 }, F + 0.07)
		end
	end
	-- Escalones de la entrada
	box(parent, root, "Step", "stone_light", { 6.6, 0.32, 1.2 }, { 0, 0.16, wallR + 2 })
	box(parent, root, "Step", "stone_light", { 6.2, 0.64, 1.2 }, { 0, 0.32, wallR + 1.1 })
	task.wait()

	-- Muro bajo con seto encima (hueco para la puerta lunar)
	local span = 360 - gap * 2
	local n = math.max(12, math.floor(math.rad(span) * wallR / 1.95))
	local step = span / n
	local len = 2 * wallR * math.sin(math.rad(step) / 2) + 0.08
	for i = 0, n - 1 do
		local deg = 90 + gap + step * (i + 0.5)
		local hedge = HEDGE[(i % 3) + 1]
		ringBox(parent, root, "Wall", "stone", wallR, deg, { 1.3, 1.1, len }, F + 0.55)
		ringBox(parent, root, "WallCap", "stone_light", wallR, deg, { 1.6, 0.25, len + 0.02 }, F + 1.22)
		ringBox(parent, root, "Hedge", hedge, wallR, deg, { 1.1, 1.2, len }, F + 1.95)
		local x, z = polar(wallR, deg)
		ellip(parent, root, "HedgeTop", hedge, { 1.05, 0.55, len }, { x, F + 2.55, z }, { 0, -math.rad(deg), 0 })
		if i % 3 == 1 then
			local fx, fz = polar(wallR - 0.1, deg)
			ball(parent, root, "Flower", FLOWERS[(i % 4) + 1], 0.2, { fx, F + 2.85, fz })
		end
		if i % 14 == 13 then
			task.wait()
		end
	end
	-- Columnas con huevos de seto recortado
	for _, deg in { 125, 55, 180, 0, 240, 300 } do
		local x, z = polar(wallR, deg)
		local c = group(root, { x, F, z })
		box(parent, c, "ColumnBase", "stone", { 2, 0.5, 2 }, { 0, 0.25, 0 })
		box(parent, c, "Column", "stone_light", { 1.5, 4.4, 1.5 }, { 0, 2.7, 0 })
		box(parent, c, "ColumnCap", "stone", { 2, 0.4, 2 }, { 0, 5.1, 0 })
		box(parent, c, "ColumnBand", "gold", { 1.56, 0.18, 1.56 }, { 0, 4.3, 0 })
		ellip(parent, c, "Topiary", "hedge2", { 1.6, 2.1, 1.6 }, { 0, 6.3, 0 })
		ball(parent, c, "TopiaryTip", "gold_glow", 0.18, { 0, 7.4, 0 })
	end
	task.wait()

	-- Puerta lunar
	local gz, gcy = wallR, F + 2.6
	arcXY(parent, root, "GateRing", "stone_light", 0, gcy, gz, 4.15, 1.1, 1.8, -math.pi * 0.22, math.pi * 1.22, 26)
	for _, side in { 1, -1 } do
		arcXY(parent, root, "GateTrim", "gold", 0, gcy, gz + side * 0.91, 3.62, 0.12, 0.06, -math.pi * 0.15, math.pi * 1.15, 18)
	end
	for _, sx in { -1, 1 } do
		box(parent, root, "GateFoot", "stone", { 2, 1.6, 2.2 }, { sx * 4.2, F + 0.8, gz })
	end
	ellip(parent, root, "Keystone", "gold_glow", { 1.3, 1.7, 1.3 }, { 0, gcy + 4.4, gz })
	textBoard(parent, root, { 7.4, 1.4, 0.3 }, { 0, gcy + 5.9, gz + 0.2 }, opts.Name or "Jardín de los Huevos")
	box(parent, root, "SignTrim", "gold", { 7.7, 0.16, 0.4 }, { 0, gcy + 6.65, gz + 0.2 })
	for _, sx in { -1, 1 } do
		box(parent, root, "SignPost", "stone", { 0.4, 1.2, 0.4 }, { sx * 2.6, gcy + 5, gz + 0.2 })
	end
	for i = 0, 17 do
		local t = math.pi * (0.5 + random:next() * 0.55)
		local r = 4.15 + (random:next() - 0.5) * 1.1
		ball(parent, root, "Ivy", if random:next() > 0.4 then "hedge2" else "hedge1", 0.22 + random:next() * 0.2, { r * math.cos(t), gcy + r * math.sin(t), gz + 0.9 + random:next() * 0.2 })
		if i % 3 == 0 then
			ball(parent, root, "IvyFlower", FLOWERS[(i % 4) + 1], 0.18, { r * math.cos(t), gcy + r * math.sin(t) + 0.3, gz + 1.3 })
		end
	end
	for _, sx in { -1, 1 } do
		local t = if sx > 0 then math.pi * 0.25 else math.pi * 0.75
		local x, y = 3.62 * math.cos(t), gcy + 3.62 * math.sin(t)
		cyl(parent, root, "LanternChain", "iron", 0.05, 1, { x * 0.9, y - 0.5, gz })
		lantern(parent, root, { x * 0.9, y - 1.4, gz }, 0.6)
	end
	task.wait()

	-- Estanque central con el Nido Mayor
	local c = group(root, { 0, F, 0 })
	local basinR = opts.FountainRadius or 4.4
	cyl(parent, c, "Basin", "marble", basinR, 1, { 0, 0.5, 0 })
	cyl(parent, c, "BasinTrim", "gold", basinR + 0.06, 0.14, { 0, 0.8, 0 })
	cyl(parent, c, "Water", "water", basinR - 0.5, 0.08, { 0, 1.03, 0 })
	for index, spec in { { 0.6, 0.7 }, { 2.1, 0.74 }, { 3.9, 0.68 }, { 5.2, 0.76 } } do
		local a, r = spec[1], spec[2] * basinR
		cyl(parent, c, "LilyPad", "moss", 0.55, 0.05, { math.cos(a) * r, 1.09, math.sin(a) * r })
		if index > 1 then
			ball(parent, c, "LilyFlower", "fl_pink", 0.18, { math.cos(a) * r, 1.22, math.sin(a) * r })
		end
	end
	cyl(parent, c, "Island", "stone", 1.7, 1.2, { 0, 1.2, 0 })
	cyl(parent, c, "NestLow", "wood", 2.3, 0.45, { 0, 1.95, 0 })
	cyl(parent, c, "NestMid", "wood_light", 2.6, 0.45, { 0, 2.35, 0 })
	cyl(parent, c, "NestTop", "wood", 2.4, 0.4, { 0, 2.75, 0 })
	cyl(parent, c, "NestMoss", "moss", 2.05, 0.42, { 0, 2.8, 0 })
	for i = 0, 17 do
		local a = i / 18 * math.pi * 2
		box(parent, c, "Twig", if i % 2 == 1 then "wood_light" else "wood", { 0.18, 0.18, 1.6 }, { math.cos(a) * 2.45, 2.5 + (i % 3) * 0.15, math.sin(a) * 2.45 }, { 0.25 * (if i % 2 == 1 then 1 else -1), -a + math.pi / 2, 0.3 })
	end
	ellip(parent, c, "GreatEgg", "marble", { 3, 3.9, 3 }, { 0, 4.6, 0 })
	cyl(parent, c, "GreatEggBand", "gold_glow", 1.5, 0.26, { 0, 4.0, 0 })
	cyl(parent, c, "GreatEggBand", "gold_glow", 1.42, 0.14, { 0, 5.25, 0 })
	ball(parent, c, "GreatEggTip", "gold_glow", 0.22, { 0, 6.6, 0 })
	for index, stand in opts.Stands do
		local x, z = polar(2.4, stand.Angle)
		gem(parent, c, "OrbitCrystal", accentLook(stand.Accent), 0.32, { x, 7.0 + (index % 2) * 0.4, z })
	end
	local glow = Instance.new("PointLight")
	glow.Color = MATS.gold_glow.Color
	glow.Range = 14
	glow.Brightness = 0.7
	glow.Shadows = false
	glow.Parent = parent:FindFirstChild("GreatEggTip") or parent
	task.wait()

	-- Bancos, macetas con huevo de seto y farolas (donde las pone LandscapeLayout)
	for _, bench in opts.Benches do
		local r = math.sqrt(bench.X ^ 2 + bench.Z ^ 2)
		local b = facingCenter(root, r, math.deg(math.atan2(bench.Z, bench.X)), F)
		box(parent, b, "Seat", "wood_light", { 3.4, 0.25, 1.1 }, { 0, 1, 0 })
		box(parent, b, "Back", "wood_light", { 3.4, 0.8, 0.2 }, { 0, 1.65, -0.5 }, { -0.15, 0, 0 })
		for _, sx in { -1, 1 } do
			box(parent, b, "Leg", "iron", { 0.2, 1, 1 }, { sx * 1.4, 0.5, 0 })
			box(parent, b, "Arm", "iron", { 0.2, 0.15, 1 }, { sx * 1.6, 1.45, 0 })
			flowerCluster(parent, b, { sx * 2.6, 0, -0.3 }, 3, 0.4, random)
		end
	end
	for _, planter in opts.Planters do
		local p = group(root, { planter.X, F, planter.Z })
		octagon(parent, p, "Pot", "stone_light", 1.1, 1, { 0, 0.5, 0 })
		cyl(parent, p, "PotRim", "gold", 1.12, 0.12, { 0, 1, 0 })
		cyl(parent, p, "Soil", "moss", 0.98, 0.1, { 0, 1.02, 0 })
		ellip(parent, p, "TopiaryEgg", "hedge2", { 1.6, 2.1, 1.6 }, { 0, 2.1, 0 })
		for k = 0, 5 do
			local a = k * 1.05
			ball(parent, p, "TopiaryFlower", FLOWERS[(k % 4) + 1], 0.14, { math.cos(a) * 0.78, 1.9 + (k % 3) * 0.35, math.sin(a) * 0.78 })
		end
	end
	for _, lamp in opts.Lamps do
		local l = group(root, { lamp.X, F, lamp.Z }, math.atan2(-lamp.X, -lamp.Z))
		cyl(parent, l, "LampBase", "darkstone", 0.45, 0.5, { 0, 0.25, 0 })
		cyl(parent, l, "LampPost", "iron", 0.14, 4.6, { 0, 2.8, 0 })
		box(parent, l, "LampArm", "iron", { 0.1, 0.1, 1 }, { 0, 5, 0.4 })
		lantern(parent, l, { 0, 4.4, 0.85 }, 0.65)
		box(parent, l, "LampTop", "iron", { 0.2, 0.2, 0.2 }, { 0, 5.2, 0 })
	end
	-- Flores junto al muro (no delante de los santuarios ni en la entrada)
	local placed = 0
	for _ = 1, 40 do
		if placed >= 18 then
			break
		end
		local deg = 90 + gap + 4 + random:next() * (span - 8)
		local nearStand = false
		for _, stand in opts.Stands do
			if math.abs(((deg - stand.Angle) + 180) % 360 - 180) < 14 then
				nearStand = true
			end
		end
		if not nearStand then
			local x, z = polar(wallR - 1.4, deg)
			flowerCluster(parent, root, { x, F, z }, 3, 0.5, random)
			placed += 1
		end
	end
end

-- Santuario --------------------------------------------------------------------------------
-- `s`: centro de la tarima a ras de la terraza, con +Z local mirando al centro del jardín.
-- look: Style ("Speckled" | "Mossy" | "Runic"), Accent. Devuelve el pedestal (para el aviso)
-- y la altura del centro del huevo sobre `s`.
function EggGardenTerrace.shrine(parent: Instance, s: CFrame, look: any, random: any): (BasePart, number)
	local accent = accentLook(look.Accent)
	octagon(parent, s, "Dais", "stone_light", 3.55, 0.45, { 0, 0.225, 0 })
	octagon(parent, s, "DaisTop", "marble", 2.92, 0.45, { 0, 0.675, 0 })
	octagon(parent, s, "DaisTrim", "gold", 2.97, 0.08, { 0, 0.88, 0 })
	box(parent, s, "DaisStep", "stone_light", { 2.8, 0.3, 1 }, { 0, 0.15, 3.75 })
	cyl(parent, s, "GlowRing", accent, 2.2, 0.05, { 0, 0.92, 0 })
	cyl(parent, s, "GlowInner", "marble", 2.0, 0.06, { 0, 0.93, 0 })
	local pedestal = cyl(parent, s, "Pedestal", "darkstone", 0.8, 2.1, { 0, 1.95, 0 })
	cyl(parent, s, "PedestalBase", "stone_light", 1.15, 0.3, { 0, 1.05, 0 })
	cyl(parent, s, "Capital", "stone_light", 1.25, 0.35, { 0, 3.15, 0 })
	cyl(parent, s, "Nest", "wood", 1.75, 0.5, { 0, 3.55, 0 })
	cyl(parent, s, "NestMoss", "moss", 1.5, 0.5, { 0, 3.6, 0 })
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		box(parent, s, "Twig", "wood_light", { 0.12, 0.12, 1.1 }, { math.cos(a) * 1.7, 3.6, math.sin(a) * 1.7 }, { 0.3, -a + math.pi / 2, 0.3 })
	end
	-- Arco con hiedra y halo del color del huevo detrás
	local az, py, ph = -1.5, 0.9, 4.6
	local top = py + ph
	for _, sx in { -1, 1 } do
		box(parent, s, "ArchFoot", "stone", { 1.3, 0.4, 1.3 }, { sx * 3, py + 0.2, az })
		box(parent, s, "ArchPillar", "stone_light", { 0.9, ph, 0.9 }, { sx * 3, py + ph / 2, az })
		box(parent, s, "ArchRune", accent, { 0.14, 2.4, 0.06 }, { sx * 3, py + 2.6, az + 0.47 })
	end
	arcXY(parent, s, "ArchRing", "stone_light", 0, top, az, 3, 0.9, 0.9, 0, math.pi, 14)
	gem(parent, s, "Keystone", accent, 0.45, { 0, top + 3.1, az + 0.1 }, { 1, 1.4, 0.7 })
	cyl(parent, s, "Halo", haloLook(look.Accent), 2.55, 0.06, { 0, top, az - 0.25 }, "z")
	box(parent, s, "HaloLower", haloLook(look.Accent), { 5.1, ph - 0.4, 0.06 }, { 0, py + 0.2 + (ph - 0.4) / 2, az - 0.25 })
	for k = 0, 6 do
		local t = math.pi * (0.62 + k * 0.06)
		local r = 3 + (random:next() - 0.5) * 0.4
		ball(parent, s, "Vine", if k % 2 == 1 then "hedge2" else "hedge1", 0.32 + random:next() * 0.15, { r * math.cos(t), top + r * math.sin(t), az + 0.4 })
		if k % 2 == 0 then
			ball(parent, s, "VineFlower", FLOWERS[(k % 4) + 1], 0.15, { r * math.cos(t), top + r * math.sin(t) + 0.25, az + 0.7 })
		end
	end
	-- Detalle de cada huevo
	if look.Style == "Mossy" then
		for _, spec in { { 2.9, 1.6, 1.1 }, { -3.1, 1.2, 0.8 }, { 3.4, -0.2, 0.7 } } do
			local x, z, h = spec[1], spec[2], spec[3]
			cyl(parent, s, "MushroomStem", "stem", 0.16, h, { x, h / 2, z })
			ellip(parent, s, "MushroomCap", "mushroom", { h + 0.3, 0.45, h + 0.3 }, { x, h + 0.1, z })
		end
	elseif look.Style == "Runic" then
		for _, sx in { -1, 1 } do
			local frame = at(s, { sx * 3.3, 0, 1.5 }, { 0, sx * 0.4, sx * -0.08 })
			box(parent, frame, "RuneStone", "darkstone", { 0.7, 1.8, 0.5 }, { 0, 0.9, 0 })
			box(parent, frame, "RuneGlyph", accent, { 0.14, 0.9, 0.04 }, { 0, 1.05, 0.28 })
		end
	else
		for _, spec in { { 2.9, 1.5, 1.6, 0.25 }, { -3.0, 1.3, 1.2, -0.3 }, { 3.3, 0.3, 0.9, 0.4 } } do
			gem(parent, s, "Crystal", "crystal", 0.3, { spec[1], spec[3] / 2 + 0.1, spec[2] }, { 1, spec[3] * 1.4, 1 }, { 0, 0.6, spec[4] })
		end
	end
	return pedestal, 5.4
end

EggGardenTerrace.polar = polar

return EggGardenTerrace
