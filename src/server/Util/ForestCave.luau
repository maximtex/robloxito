-- Boca de la Cueva de los Espinillos (Bosque, en la colina oeste). El camino de la plaza a la
-- boca es un camino más del suelo (StudFloor Paths) y el hueco en la colina lo hace StudWorld
-- (layout.Cave.Opening); aquí va lo demás:
-- - El fondo del túnel cerrado con roca y, delante, una bruma que se oscurece hasta el negro
--   (capas cada vez más opacas) con chispas moradas: al cruzarla, CaveService te lleva dentro
--   de la cueva (CaveConfig, lejos del mapa; la construye CaveDungeon).
-- - La entrada monumental (ForestCave.gate): arco con runas y el nombre, braseros, gema que
--   flota, haz de luz al cielo, cartel flotante, círculo de runas y lo de su zona.
-- buildMound: la boca de las otras mazmorras (Valle, Caldera y Tundra,
-- CaveConfig.Caves.*.Entrance.Mound): un montículo de roca de bloques con el túnel en medio, la
-- misma bruma y la misma entrada monumental.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local CaveConfig = require(Shared.Config.CaveConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.PartFactory)
local StudWorld = require(script.Parent.StudWorld)

local ForestCave = {}

local RGB = Color3.fromRGB
local B = 8 -- bloques de 8, alineados con el suelo del Bosque
local GROUND = GeneratorConfig.Position.Y

local ROCK = { RGB(104, 108, 140), RGB(86, 90, 120) }
local DARK = RGB(8, 6, 18)
local MIST = RGB(150, 90, 255)

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

-- Antorcha de pie (palo, llama de neón con fuego y luz). Sirve también para la cueva de dentro.
function ForestCave.torch(parent: Instance, position: Vector3): Part
	local stick = block(parent, "Palo", Vector3.new(0.6, 3.4, 0.6), CFrame.new(position), RGB(120, 76, 40), false)
	local flame = block(parent, "Llama", Vector3.new(1, 1.3, 1), CFrame.new(position + Vector3.new(0, 2.3, 0)), RGB(255, 160, 60), false)
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

-- Cartel de madera con letras (cara `face`), para la boca y las salas de dentro.
function ForestCave.sign(parent: Instance, name: string, size: Vector3, cframe: CFrame, face: Enum.NormalId, text: string): Part
	local board = block(parent, name, size, cframe, RGB(150, 98, 54))
	local u = if face == Enum.NormalId.Left or face == Enum.NormalId.Right then size.Z else size.X
	StudWorld.studFace(board, face, u, size.Y)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Texto"
	gui.Face = face
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
	label.Text = text
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.04, 0)
	padding.PaddingRight = UDim.new(0.04, 0)
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.Parent = label
	return board
end

-- Chispas que flotan despacio (bruma de la boca y portales de dentro).
function ForestCave.motes(part: BasePart, color: Color3, face: Enum.NormalId, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Chispas"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.2)
	emitter.Lifetime = NumberRange.new(1.6, 2.8)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(0.6, 1.6)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.EmissionDirection = face
	emitter.Parent = part
	return emitter
end

-- Entrada monumental de una mazmorra -----------------------------------------------------------
-- Para que se vea desde lejos y se note que es algo importante, delante de cada boca (la del
-- Bosque y los montículos de las demás):
-- - Un arco de piedra con runas que brillan del color de la cueva, su nombre grabado encima,
--   dos braseros con fuego mágico y, en lo alto, una gema que flota y gira dentro de un aro de
--   luz (gira en cada cliente: DungeonGates, etiquetas DungeonGem y DungeonHalo).
-- - Un haz de luz que sube al cielo desde la gema y el cartel flotante (⚔ MAZMORRA, el
--   nombre, la dificultad en estrellas y el jefe): se ven desde casi todo el mapa (el haz y el
--   cartel están siempre cargados aunque estés lejos: ModelStreamingMode Persistent).
-- - En la boca, un marco de luz y chispas que se cuelan hacia dentro (como si te tragara).
-- - En el suelo, un círculo de runas delante (donde apareces al salir) y pilares de cristal
--   que marcan el camino.
-- - A los lados, lo de su zona (CaveConfig.Caves.*.Decor): zarzas y setas, cristales, roca
--   volcánica con lava o pinchos de hielo.
-- Nada de esto choca, salvo los pilares del arco (fuera del camino).
ForestCave.GemTag = "DungeonGem"
ForestCave.HaloTag = "DungeonHalo"
local BEACON_HEIGHT = 170

local function neon(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): Part
	local part = PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Neon,
		Shape = shape,
		Solid = false,
		CastShadow = false,
	})
	return part
end

local function deco(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	return PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Shape = shape,
		Solid = false,
		CastShadow = false,
	})
end

-- Dificultad: tantas estrellas como el puesto de la cueva (Bosque 1 … Tundra 4)
local function difficulty(caveId: string): string
	local total = #CaveConfig.Order
	local index = table.find(CaveConfig.Order, caveId) or 1
	return "Dificultad " .. string.rep("⭐", index) .. string.rep("☆", math.max(0, total - index))
end

local function bossName(cave): string?
	local zone = EnemyConfig.Zones[cave.Zone]
	local boss = zone and zone.Boss and EnemyConfig.Types[zone.Boss.Type]
	return boss and boss.DisplayName
end

local function label(parent: Instance, text: string, height: number, color: Color3, order: number): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Size = UDim2.fromScale(1, height)
	item.Font = Enum.Font.FredokaOne
	item.TextScaled = true
	item.TextColor3 = color
	item.TextStrokeColor3 = RGB(30, 18, 48)
	item.TextStrokeTransparency = 0
	item.Text = text
	item.LayoutOrder = order
	item.Parent = parent
	return item
end

-- Aro de luz (en el plano XY del marco `center`) hecho de `count` trozos
local function ring(parent: Instance, name: string, center: CFrame, radius: number, thickness: number, count: number, color: Color3, flat: boolean?)
	local length = 2 * math.pi * radius / count + 0.15
	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2
		local cframe, size
		if flat then
			-- Tumbado en el suelo (plano XZ)
			cframe = center * CFrame.Angles(0, angle, 0) * CFrame.new(radius, 0, 0)
			size = Vector3.new(thickness, 0.1, length)
		else
			cframe = center * CFrame.Angles(0, 0, angle) * CFrame.new(radius, 0, 0)
			size = Vector3.new(thickness, length, thickness)
		end
		neon(parent, ("%s_%d"):format(name, index), size, cframe, color)
	end
end

-- Fuego y hielo de las entradas partidas (Decor = "Split": la Grieta Elemental)
local SPLIT_FIRE = RGB(255, 130, 40)
local SPLIT_ICE = RGB(110, 210, 255)

-- Lo de cada zona a un lado del arco (`side` = -1 / 1), alrededor de `origin` (en el suelo)
local function sideDecor(parent: Instance, cave, origin: CFrame, side: number)
	local kind = cave.Decor or "Crystal"
	local colors = (cave.Rooms[1] and cave.Rooms[1].Crystal) or { MIST, MIST }
	local glow = (cave.Theme and cave.Theme.Mist) or MIST
	if kind == "Split" then
		-- Un lado de roca volcánica con lava (los colores de la sala 1) y el otro de hielo (sala 2)
		kind = if side < 0 then "Magma" else "Ice"
		local room = cave.Rooms[if side < 0 then 1 else 2]
		colors = (room and room.Crystal) or colors
	end
	-- dx, dz, alto, inclinación
	local spots = { { 0, 0, 9, 6 }, { 2.8, -2.2, 6, 18 }, { -2.2, -3, 4.5, -14 }, { 4.2, 1.4, 3.5, 26 }, { -0.6, 3.2, 5, -8 } }
	for index, spot in spots do
		local height = spot[3]
		local base = origin * CFrame.new(side * spot[1], 0, spot[2]) * CFrame.Angles(0, math.rad(index * 41), 0) * CFrame.Angles(math.rad(spot[4] * 0.4), 0, math.rad(spot[4] * side))
		local center = base * CFrame.new(0, height / 2, 0)
		local color = colors[index % #colors + 1]
		local name = ("%s_%d"):format(kind, index)
		if kind == "Crystal" or kind == "Ice" then
			local shell = deco(parent, name, Vector3.new(1.9, height, 1.9), center * CFrame.Angles(0, math.rad(45), 0), color, if kind == "Ice" then Enum.Material.Ice else Enum.Material.Glass)
			shell.Transparency = if kind == "Ice" then 0.1 else 0.25
			neon(parent, name .. "_Nucleo", Vector3.new(0.7, height * 0.85, 0.7), center, if kind == "Ice" then RGB(225, 245, 255) else color)
			local tip = deco(parent, name .. "_Punta", Vector3.new(1.3, 1.3, 1.3), base * CFrame.new(0, height, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color, shell.Material)
			tip.Transparency = shell.Transparency
		elseif kind == "Magma" then
			deco(parent, name, Vector3.new(2.2, height, 2.2), center * CFrame.Angles(0, math.rad(45), 0), RGB(40, 30, 34), Enum.Material.Basalt)
			neon(parent, name .. "_Veta", Vector3.new(0.5, height * 0.8, 2.3), center * CFrame.Angles(0, math.rad(45), 0), color)
			neon(parent, name .. "_Punta", Vector3.new(1.2, 1.2, 1.2), base * CFrame.new(0, height + 0.2, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), RGB(255, 210, 90))
		else
			-- Zarza: tallo oscuro con espinas que brillan
			deco(parent, name, Vector3.new(1.4, height, 1.4), center, RGB(58, 92, 46), Enum.Material.Wood)
			for spike = 1, 3 do
				local at = base * CFrame.new(0, height * spike / 4, 0) * CFrame.Angles(0, math.rad(spike * 120), 0) * CFrame.Angles(0, 0, math.rad(70))
				deco(parent, name .. "_Espina" .. spike, Vector3.new(0.4, 2.2, 0.4), at * CFrame.new(0, 1.2, 0), RGB(150, 255, 110), Enum.Material.Neon)
			end
		end
	end
	if kind == "Thorns" then
		-- Setas que brillan junto a las zarzas
		for index, spot in { { 3.4, -4.4, 2.4 }, { -3, 2.2, 1.8 }, { 5.2, -1, 1.4 } } do
			local base = origin * CFrame.new(side * spot[1], 0, spot[2])
			local size = spot[3]
			local mushroom = (cave.Rooms[1] and cave.Rooms[1].Mushroom) or { glow, glow }
			deco(parent, "SetaPie" .. index, Vector3.new(size * 0.9, size * 0.4, size * 0.4), base * CFrame.new(0, size * 0.45, 0) * PartFactory.UPRIGHT, RGB(236, 226, 206), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			local cap = neon(parent, "SetaSombrero" .. index, Vector3.one * size * 1.3, base * CFrame.new(0, size * 1.05, 0), mushroom[index % 2 + 1], Enum.PartType.Ball)
			light(cap, cap.Color, 8, 0.8)
		end
	elseif kind == "Magma" then
		-- Charco de lava
		local pool = neon(parent, "Lava", Vector3.new(0.12, 7, 7), origin * CFrame.new(side * 1.5, 0.08, -1) * PartFactory.UPRIGHT, RGB(255, 110, 30), Enum.PartType.Cylinder)
		light(pool, RGB(255, 120, 40), 14, 1.2)
	end
end

-- La entrada delante de una boca. `frame`: en el suelo (Y = GROUND), en el centro del frente
-- del túnel, con -Z mirando hacia fuera; `width` × `height`: el hueco del túnel.
function ForestCave.gate(parent: Instance, cave, frame: CFrame, width: number, height: number): Model
	local theme = cave.Theme or {}
	local rock = theme.Rock or ROCK
	local dark = (theme.Dark and theme.Dark[2]) or RGB(58, 62, 86)
	local glow = theme.Mist or MIST
	local accent = theme.Portal or glow
	local lift = StudWorld.FloorTop - GROUND
	local model = Instance.new("Model")
	model.Name = "Entrada"
	-- Lo que brilla a cada lado: el color de la cueva o, en las partidas, fuego y hielo
	local function tone(side: number): Color3
		if cave.Decor == "Split" then
			return if side < 0 then SPLIT_FIRE else SPLIT_ICE
		end
		return glow
	end
	-- Altura del suelo en un punto del marco (los caminos sobresalen)
	local function floorAt(local_: CFrame): number
		local p = local_.Position
		return lift + StudFloor.raiseAt(p.X, p.Z)
	end

	-- 1. Arco: dos pilares de bloques con runas, el dintel con el nombre y la corona
	local arch = PartFactory.folder(model, "Arco")
	local pillarX = width / 2 + 3.5
	local pillarHeight = height + 8
	local depth = -2.5 -- delante de la roca
	for _, side in { -1, 1 } do
		local x = side * pillarX
		block(arch, "Basa", Vector3.new(7, 2.4, 7), frame * CFrame.new(x, 1.2, depth), dark, true)
		local rows = math.ceil(pillarHeight / 4)
		for row = 1, rows do
			local piece = block(arch, "Pilar" .. row, Vector3.new(5, 4, 5), frame * CFrame.new(x, (row - 0.5) * 4, depth), rock[row % 2 + 1], true)
			StudWorld.studFace(piece, Enum.NormalId.Front, 5, 4)
		end
		-- Runas: una raya de luz por delante con travesaños
		neon(arch, "Runa", Vector3.new(0.9, pillarHeight - 7, 0.25), frame * CFrame.new(x, 3 + (pillarHeight - 7) / 2 + 0.5, depth - 2.6), tone(side))
		for bar = 1, 3 do
			neon(arch, "RunaBarra" .. bar, Vector3.new(2.6, 0.5, 0.25), frame * CFrame.new(x, 3 + bar * (pillarHeight - 7) / 4, depth - 2.6), accent)
		end
	end
	local spanWidth = 2 * pillarX + 7
	local lintel = block(arch, "Dintel", Vector3.new(spanWidth, 5, 7), frame * CFrame.new(0, pillarHeight + 2.5, depth), dark, true)
	StudWorld.studFace(lintel, Enum.NormalId.Top, spanWidth, 7)
	neon(arch, "DintelLuz", Vector3.new(spanWidth - 1, 0.5, 0.25), frame * CFrame.new(0, pillarHeight + 0.4, depth - 3.6), glow)
	neon(arch, "DintelLuzArriba", Vector3.new(spanWidth - 1, 0.5, 0.25), frame * CFrame.new(0, pillarHeight + 4.6, depth - 3.6), glow)
	-- El nombre grabado en el dintel
	local plate = Instance.new("SurfaceGui")
	plate.Name = "Nombre"
	plate.Face = Enum.NormalId.Front
	plate.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	plate.PixelsPerStud = 30
	plate.LightInfluence = 0
	plate.Parent = lintel
	local name = label(plate, ("%s  %s  %s"):format(cave.Icon or "", string.upper(cave.Name), cave.Icon or ""), 1, RGB(255, 230, 150), 1)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.Parent = name
	local crownY = pillarHeight + 5
	local crown = block(arch, "Corona", Vector3.new(14, 3, 6), frame * CFrame.new(0, crownY + 1.5, depth), rock[1], true)
	StudWorld.studFace(crown, Enum.NormalId.Front, 14, 3)
	block(arch, "CoronaPico", Vector3.new(7, 2, 5), frame * CFrame.new(0, crownY + 4, depth), rock[2], true)

	-- 2. Braseros en las puntas del dintel, con fuego del color de la cueva
	for _, side in { -1, 1 } do
		local base = frame * CFrame.new(side * pillarX, pillarHeight + 5, depth)
		deco(arch, "Brasero", Vector3.new(1.8, 4.2, 4.2), base * CFrame.new(0, 0.9, 0) * PartFactory.UPRIGHT, RGB(46, 40, 52), Enum.Material.Metal, Enum.PartType.Cylinder)
		local flame = tone(side)
		local coal = neon(arch, "Brasas", Vector3.one * 2.4, base * CFrame.new(0, 2, 0), flame, Enum.PartType.Ball)
		local fire = Instance.new("Fire")
		fire.Size = 7
		fire.Heat = 12
		fire.Color = flame
		fire.SecondaryColor = Color3.new(1, 1, 1):Lerp(flame, 0.35)
		fire.Parent = coal
		light(coal, flame, 26, 2)
	end

	-- 3. Gema que flota sobre la corona, dentro de un aro de luz (los dos giran en el cliente)
	local gemCenter = frame * CFrame.new(0, crownY + 11, depth)
	local gem = neon(model, "Gema", Vector3.new(4, 4, 4), gemCenter * CFrame.Angles(math.rad(45), 0, math.rad(45)), glow)
	light(gem, glow, 30, 2)
	CollectionService:AddTag(gem, ForestCave.GemTag)
	local halo = Instance.new("Model")
	halo.Name = "Aro"
	local hub = deco(halo, "Centro", Vector3.one * 0.4, gemCenter, glow)
	hub.Transparency = 1
	halo.PrimaryPart = hub
	ring(halo, "Aro", gemCenter, 5.2, 0.5, 18, accent)
	ring(halo, "AroFino", gemCenter, 6.4, 0.22, 24, Color3.new(1, 1, 1):Lerp(glow, 0.5))
	halo.Parent = model
	CollectionService:AddTag(halo, ForestCave.HaloTag)

	-- 4. Haz de luz al cielo y cartel flotante (siempre cargados, para verlos de lejos)
	local beacon = Instance.new("Model")
	beacon.Name = "Faro"
	beacon.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local anchor = deco(beacon, "Faro", Vector3.one * 0.5, CFrame.new(gemCenter.Position), glow)
	anchor.Transparency = 1
	local bottom = Instance.new("Attachment")
	bottom.Name = "Abajo"
	bottom.Parent = anchor
	local top = Instance.new("Attachment")
	top.Name = "Arriba"
	top.Position = Vector3.new(0, BEACON_HEIGHT, 0)
	top.Parent = anchor
	for _, spec in { { "Haz", 9, 3, glow, 0.35 }, { "HazNucleo", 2.4, 0.8, Color3.new(1, 1, 1):Lerp(glow, 0.3), 0.15 } } do
		local beam = Instance.new("Beam")
		beam.Name = spec[1]
		beam.Attachment0 = bottom
		beam.Attachment1 = top
		beam.Width0 = spec[2]
		beam.Width1 = spec[3]
		beam.Color = ColorSequence.new(spec[4])
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, spec[5]),
			NumberSequenceKeypoint.new(0.6, math.min(1, spec[5] + 0.35)),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Parent = anchor
	end
	-- El cartel, un poco por delante (que no se meta en la colina) y con fondo oscuro para
	-- leerse encima del haz
	local title = Instance.new("BillboardGui")
	title.Name = "Cartel"
	title.Size = UDim2.new(22, 130, 9, 54)
	title.StudsOffsetWorldSpace = Vector3.new(0, 11, 0) + frame.LookVector * 12
	title.MaxDistance = 700
	title.LightInfluence = 0
	title.Parent = anchor
	local panel = Instance.new("Frame")
	panel.Name = "Fondo"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = RGB(24, 16, 40)
	panel.BackgroundTransparency = 0.2
	panel.Parent = title
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.18, 0)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = glow
	stroke.Thickness = 3
	stroke.Parent = panel
	local inset = Instance.new("UIPadding")
	inset.PaddingTop = UDim.new(0.06, 0)
	inset.PaddingBottom = UDim.new(0.06, 0)
	inset.PaddingLeft = UDim.new(0.05, 0)
	inset.PaddingRight = UDim.new(0.05, 0)
	inset.Parent = panel
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel
	label(panel, "⚔ MAZMORRA ⚔", 0.2, glow:Lerp(Color3.new(1, 1, 1), 0.45), 1)
	label(panel, ("%s %s"):format(cave.Icon or "", string.upper(cave.Name)), 0.36, RGB(255, 226, 120), 2)
	label(panel, difficulty(cave.Id or "Forest"), 0.2, RGB(255, 236, 170), 3)
	local boss = bossName(cave)
	if boss then
		label(panel, "👑 Jefe: " .. boss, 0.2, RGB(255, 255, 255), 4)
	end
	beacon.Parent = model

	-- 5. La boca: marco de luz y chispas que se cuelan hacia dentro
	local mouth = PartFactory.folder(model, "Boca")
	local inner = height - lift
	for _, side in { -1, 1 } do
		neon(mouth, "Marco", Vector3.new(0.6, inner, 0.4), frame * CFrame.new(side * (width / 2 - 0.3), lift + inner / 2, -0.3), glow)
	end
	neon(mouth, "MarcoArriba", Vector3.new(width, 0.6, 0.4), frame * CFrame.new(0, height - 0.3, -0.3), glow)
	local pull = deco(mouth, "Remolino", Vector3.new(width - 1.2, inner - 0.6, 0.2), frame * CFrame.new(0, lift + inner / 2, 1.5), glow)
	pull.Transparency = 1
	local swirl = Instance.new("ParticleEmitter")
	swirl.Name = "Remolino"
	swirl.Color = ColorSequence.new(Color3.new(1, 1, 1), glow)
	swirl.LightEmission = 1
	swirl.LightInfluence = 0
	swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	swirl.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	swirl.Lifetime = NumberRange.new(0.9, 1.5)
	swirl.Rate = 30
	swirl.Speed = NumberRange.new(4, 7)
	swirl.SpreadAngle = Vector2.new(25, 25)
	swirl.Rotation = NumberRange.new(0, 360)
	swirl.RotSpeed = NumberRange.new(-180, 180)
	swirl.EmissionDirection = Enum.NormalId.Back -- hacia dentro del túnel
	swirl.Parent = pull
	local shine = Instance.new("SurfaceLight")
	shine.Face = Enum.NormalId.Front
	shine.Color = glow
	shine.Range = 18
	shine.Brightness = 2.5
	shine.Angle = 100
	shine.Parent = pull

	-- 6. Círculo de runas en el suelo, delante (donde apareces al salir), y pilares de cristal
	-- que marcan el camino
	local floor = PartFactory.folder(model, "Suelo")
	local circle = frame * CFrame.new(0, 0, -12)
	circle = frame * CFrame.new(0, floorAt(circle) + 0.06, -12)
	ring(floor, "Runas", circle, 6.5, 0.45, 24, glow, true)
	ring(floor, "RunasDentro", circle, 4, 0.3, 16, accent, true)
	local disc = deco(floor, "Disco", Vector3.new(0.1, 8, 8), circle * CFrame.new(0, -0.02, 0) * PartFactory.UPRIGHT, glow, Enum.Material.Glass, Enum.PartType.Cylinder)
	disc.Transparency = 0.6
	for index, distance in { 24, 36 } do
		for _, side in { -1, 1 } do
			local spot = frame * CFrame.new(side * (width / 2 + 2), 0, -distance)
			local base = frame * CFrame.new(side * (width / 2 + 2), floorAt(spot), -distance)
			deco(floor, "Hito" .. index, Vector3.new(2.6, 2, 2.6), base * CFrame.new(0, 1, 0), dark, Enum.Material.Slate)
			local crystal = neon(floor, "HitoCristal" .. index, Vector3.new(1.3, 3.6, 1.3), base * CFrame.new(0, 3.8, 0) * CFrame.Angles(0, math.rad(45), 0), tone(side))
			light(crystal, crystal.Color, 12, 1)
		end
	end

	-- 7. Lo de su zona a los lados del arco
	local sides = PartFactory.folder(model, "Adornos")
	for _, side in { -1, 1 } do
		sideDecor(sides, cave, frame * CFrame.new(side * (pillarX + 6), lift, -3.5), side)
	end

	model.Parent = parent
	return model
end

function ForestCave.build(parent: Instance, layout)
	local cave = layout.Cave
	if not cave then
		return
	end
	local opening = cave.Opening
	local floorTop = StudWorld.FloorTop
	local doorRows = opening.Ceiling or 3
	local doorTop = GROUND + doorRows * B
	local doorZ0, doorZ1 = opening.MinZ, opening.MaxZ
	local midZ = (doorZ0 + doorZ1) / 2
	local width = doorZ1 - doorZ0
	local model = Instance.new("Model")
	model.Name = "ForestCave"

	-- 1. Fondo del túnel: roca (detrás ya no hay colina) un bloque más ancha y alta que el hueco
	local back = PartFactory.folder(model, "Fondo")
	for k = 0, math.round(width / B) + 1 do
		for r = 1, doorRows + 1 do
			local z = doorZ0 - B / 2 + k * B
			local part = block(back, ("fondo_%d_%d"):format(k, r), Vector3.new(B, B, B), CFrame.new(opening.MinX - B / 2, GROUND + (r - 0.5) * B, z), ROCK[(k + r) % 2 + 1], true)
			StudWorld.studFace(part, Enum.NormalId.Right, B, B)
		end
	end

	-- 2. Bruma: capas negras cada vez más opacas hacia el fondo (la boca "se traga" la luz) y
	-- chispas moradas. Sin colisión: al cruzarla te lleva dentro (CaveService).
	local mist = PartFactory.folder(model, "Bruma")
	local layers = { { 0.6, 0.86 }, { 2.8, 0.68 }, { 5, 0.42 }, { 7.4, 0.12 } }
	local deepest: Part? = nil
	for index, layer in layers do
		local x = opening.MinX + B - layer[1]
		local part = block(mist, "Bruma" .. index, Vector3.new(0.2, doorTop - floorTop, width), CFrame.new(x, (floorTop + doorTop) / 2, midZ), DARK, false)
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = layer[2]
		part.CastShadow = false
		deepest = part
	end
	if deepest then
		ForestCave.motes(deepest, MIST, Enum.NormalId.Right, 14)
		light(deepest, MIST, 14, 0.8)
	end

	-- 3. La entrada monumental delante de la boca (mira a la pradera, +X)
	local front = Vector3.new(opening.MaxX, GROUND, midZ)
	ForestCave.gate(model, CaveConfig.Caves.Forest, CFrame.lookAt(front, front + Vector3.xAxis), width, doorRows * B)

	model.Parent = parent
	return model
end

-- Boca de una mazmorra fuera del Bosque: montículo de Depth × Span (bloques de 8) y 3 filas de
-- alto (más una joroba encima), con un túnel de Width × Height desde el frente (Front, que
-- mira hacia Facing) hasta el bloque del fondo; dentro, la bruma que lleva a la cueva
-- (CaveService: Entrance.Trigger, en el fondo del túnel).
function ForestCave.buildMound(parent: Instance, cave)
	local spec = cave.Entrance.Mound
	local theme = cave.Theme or {}
	local rock = theme.Rock or ROCK
	local mistColor = theme.Mist or MIST
	local facing = Vector3.new(spec.Facing.X, 0, spec.Facing.Z).Unit
	local floorTop = StudWorld.FloorTop
	-- Marco: -Z local mira hacia fuera (Facing); X local a lo ancho; el montículo va hacia +Z
	local front = Vector3.new(spec.Front.X, GROUND, spec.Front.Z)
	local frame = CFrame.lookAt(front, front + facing)
	local model = Instance.new("Model")
	model.Name = "BocaCueva_" .. tostring(cave.Id)
	local cols = math.round(spec.Span / B)
	local deep = math.round(spec.Depth / B)
	local tunnelCols = math.round(spec.Width / B)
	local tunnelRows = math.round(spec.Height / B)
	local firstTunnel = math.floor((cols - tunnelCols) / 2) + 1
	local rocks = PartFactory.folder(model, "Roca")
	for d = 1, deep do
		for c = 1, cols do
			for row = 1, tunnelRows + 1 do
				local inTunnel = c >= firstTunnel and c < firstTunnel + tunnelCols and row <= tunnelRows and d < deep
				if not inTunnel then
					local offset = CFrame.new((c - (cols + 1) / 2) * B, (row - 0.5) * B, (d - 0.5) * B)
					local part = block(rocks, ("roca_%d_%d_%d"):format(d, c, row), Vector3.new(B, B, B), frame * offset, rock[(d + c + row) % 2 + 1], true)
					StudWorld.studFace(part, Enum.NormalId.Front, B, B)
					StudWorld.studFace(part, Enum.NormalId.Top, B, B)
				end
			end
		end
	end
	-- Joroba encima (más estrecha)
	for d = 1, deep - 1 do
		for c = 2, cols - 1 do
			local offset = CFrame.new((c - (cols + 1) / 2) * B, (tunnelRows + 1.5) * B, (d + 0.5) * B)
			local part = block(rocks, ("joroba_%d_%d"):format(d, c), Vector3.new(B, B, B), frame * offset, rock[(d + c) % 2 + 1], true)
			StudWorld.studFace(part, Enum.NormalId.Top, B, B)
		end
	end

	-- Bruma: capas oscuras cada vez más opacas hacia el fondo del túnel, con chispas
	local mist = PartFactory.folder(model, "Bruma")
	local back = (deep - 1) * B -- fondo del túnel (en Z local)
	local layers = { { 0.6, 0.86 }, { 2.8, 0.68 }, { 5, 0.42 }, { 7.4, 0.12 } }
	local deepest: Part? = nil
	local tunnelHeight = tunnelRows * B
	local lift = floorTop - GROUND
	for index, layer in layers do
		local z = back - B + layer[1]
		local part = block(mist, "Bruma" .. index, Vector3.new(spec.Width, tunnelHeight - lift, 0.2), frame * CFrame.new(0, (tunnelHeight + lift) / 2, z), DARK, false)
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = layer[2]
		part.CastShadow = false
		deepest = part
	end
	if deepest then
		ForestCave.motes(deepest, mistColor, Enum.NormalId.Front, 14)
		light(deepest, mistColor, 14, 0.8)
	end

	-- La entrada monumental delante de la boca
	ForestCave.gate(model, cave, frame, spec.Width, tunnelHeight)

	model.Parent = parent
	return model
end

return ForestCave
