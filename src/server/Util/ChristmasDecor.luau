--!strict
-- Decoración de Navidad (SeasonConfig.Christmas):
-- - leaderboard: en las tablas de clasificación, con piezas sencillas como el resto del mapa
--   (nieve en lo alto, guirnalda de pino con luces, coronas, bastones de caramelo y regalos).
-- - forest: los adornos del diseño (ChristmasData: arco de luces, faroles, pilas de regalos y
--   muñecos de nieve) por el Bosque, en los sitios de SeasonConfig.ForestDecor.
-- - tree: el árbol de Navidad de bloques del diseño, que sustituye a los árboles del Bosque.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SeasonConfig = require(Shared.Config.SeasonConfig)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.PartFactory)
local GlbParts = require(script.Parent.GlbParts)
local StudWorld = require(script.Parent.StudWorld)
local ChristmasData = require(script.Parent.ChristmasData)

local ChristmasDecor = {}

local SNOW = Color3.fromRGB(246, 250, 255)
local PINE = { Color3.fromRGB(34, 118, 58), Color3.fromRGB(50, 150, 74) }
local RED = Color3.fromRGB(222, 38, 48)
local WHITE = Color3.fromRGB(250, 250, 250)
local GOLD = Color3.fromRGB(255, 200, 64)
local LIGHTS = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 205, 70),
	Color3.fromRGB(90, 255, 130),
	Color3.fromRGB(90, 180, 255),
}
local PLASTIC = Enum.Material.SmoothPlastic

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, solid: boolean?): BasePart
	return PartFactory.part(parent, name, { Size = size, CFrame = cf, Color = color, Material = PLASTIC, Solid = solid == true })
end

-- Capa de nieve sobre la cara de arriba de una pieza, un poco más ancha que ella
local function snowOn(parent: Instance, part: BasePart, thickness: number, overhang: number)
	block(parent, "Snow", Vector3.new(part.Size.X + overhang, thickness, part.Size.Z + overhang), part.CFrame * CFrame.new(0, part.Size.Y / 2 + thickness / 2, 0), SNOW)
end

-- Lazo rojo mirando hacia -Z de `cf`
local function bow(parent: Instance, cf: CFrame, scale: number)
	for _, side in { -1, 1 } do
		block(parent, "Bow", Vector3.new(0.55, 0.32, 0.14) * scale, cf * CFrame.new(side * 0.26 * scale, 0, 0) * CFrame.Angles(0, 0, math.rad(side * 28)), RED)
		block(parent, "BowTail", Vector3.new(0.14, 0.5, 0.1) * scale, cf * CFrame.new(side * 0.14 * scale, -0.36 * scale, 0) * CFrame.Angles(0, 0, math.rad(side * 18)), RED)
	end
	block(parent, "BowKnot", Vector3.new(0.22, 0.22, 0.18) * scale, cf, RED)
end

-- Guirnalda de pino con luces que cuelga en `swags` curvas bajo el borde de delante de `ledge`
-- (de punta a punta en su eje X), con un lazo en cada punto del que cuelga.
local function garland(parent: Instance, ledge: BasePart, swags: number, sag: number)
	local half = ledge.Size.X / 2 - 0.4
	local hang = ledge.CFrame * CFrame.new(0, -ledge.Size.Y / 2, -ledge.Size.Z / 2 - 0.3)
	local width = 2 * half / swags
	local light = 0
	for swag = 0, swags - 1 do
		local x0 = -half + swag * width
		local leaves = math.ceil(width / 0.4)
		for step = 0, leaves do
			local t = step / leaves
			local x = x0 + t * width
			local y = -sag * math.sin(math.pi * t)
			PartFactory.ball(parent, "Garland", (hang * CFrame.new(x, y, 0)).Position, 0.62, PINE[step % 2 + 1], PLASTIC, false)
			if step % 3 == 1 then
				light += 1
				PartFactory.ball(parent, "Light", (hang * CFrame.new(x, y - 0.38, -0.05)).Position, 0.34, LIGHTS[(light - 1) % #LIGHTS + 1], Enum.Material.Neon, false)
			end
		end
	end
	for point = 0, swags do
		bow(parent, hang * CFrame.new(-half + point * width, 0, -0.32), 1)
	end
end

-- Corona de pino con bayas y lazo en la cara de delante (-Z) de `cf`
local function wreath(parent: Instance, cf: CFrame, radius: number)
	local count = 12
	for index = 1, count do
		local angle = (index - 1) / count * 2 * math.pi
		PartFactory.ball(parent, "Wreath", (cf * CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)).Position, 0.55, PINE[index % 2 + 1], PLASTIC, false)
	end
	for _, angle in { 40, 75, 140 } do
		local a = math.rad(angle)
		PartFactory.ball(parent, "Berry", (cf * CFrame.new(math.cos(a) * radius, math.sin(a) * radius, -0.28)).Position, 0.2, RED, PLASTIC, false)
	end
	bow(parent, cf * CFrame.new(0, -radius, -0.3), 0.9)
end

-- Bastón de caramelo de pie en `base` (frente -Z), con el gancho hacia `side` (-1 o 1 en X)
local function candyCane(parent: Instance, base: CFrame, height: number, side: number)
	local diameter = 0.55
	local band = 0.5
	local bands = math.floor(height / band)
	for index = 1, bands do
		PartFactory.verticalCylinder(parent, "CandyCane", (base * CFrame.new(0, (index - 0.5) * band, 0)).Position, band, diameter, if index % 2 == 0 then RED else WHITE, PLASTIC, false)
	end
	-- Gancho: media vuelta de radio 0.8 hacia fuera
	local top = bands * band
	local radius = 0.8
	local previous = base * CFrame.new(0, top, 0)
	local pieces = 6
	for index = 1, pieces do
		local angle = index / pieces * math.pi
		local point = base * CFrame.new(side * radius * (1 - math.cos(angle)), top + radius * math.sin(angle), 0)
		PartFactory.segment(parent, "CandyCane", previous.Position, point.Position, diameter, if index % 2 == 0 then WHITE else RED, PLASTIC, false)
		previous = point
	end
end

-- Regalo: caja con dos cintas en cruz y lazo encima, apoyado en `base`
local function gift(parent: Instance, base: CFrame, size: number, boxColor: Color3, ribbon: Color3)
	local center = base * CFrame.new(0, size / 2, 0)
	block(parent, "Gift", Vector3.one * size, center, boxColor, true)
	block(parent, "Ribbon", Vector3.new(size * 0.22, size + 0.04, size + 0.04), center, ribbon)
	block(parent, "Ribbon", Vector3.new(size + 0.04, size + 0.04, size * 0.22), center, ribbon)
	for _, side in { -1, 1 } do
		block(parent, "GiftBow", Vector3.new(size * 0.38, size * 0.2, size * 0.16), center * CFrame.new(side * size * 0.17, size / 2 + size * 0.1, 0) * CFrame.Angles(0, 0, math.rad(side * 30)), ribbon)
	end
end

-- Tabla de clasificación de madera (LeaderboardService): `parts` son sus piezas por nombre
-- (GlbParts.build) y `frame` su marco (suelo en Y = 0, frente hacia -Z).
function ChristmasDecor.leaderboard(model: Model, parts: { [string]: BasePart }, frame: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "Christmas"
	folder.Parent = model

	-- Nieve en la viga y en los tacos de arriba
	if parts.top_beam then
		snowOn(folder, parts.top_beam, 0.3, 0.3)
	end
	for index = 0, 8 do
		local topBlock = parts["top_block_" .. index]
		if topBlock then
			snowOn(folder, topBlock, 0.35, 0.2)
		end
	end
	-- Guirnalda con luces bajo el borde de la viga (por encima del título)
	if parts.top_beam_lip then
		garland(folder, parts.top_beam_lip, 3, 0.85)
	end
	-- Una corona en cada poste, por fuera de las filas
	for _, postName in { "post_L", "post_R" } do
		local post = parts[postName]
		if post then
			wreath(folder, post.CFrame * CFrame.new(0, post.Size.Y / 2 - 4, -post.Size.Z / 2 - 0.35), 0.8)
		end
	end
	-- Bastones de caramelo a los lados y regalos delante, en el suelo
	local plinth = parts.base_plinth
	local halfWidth = if plinth then plinth.Size.X / 2 else 8.75
	local front = if plinth then plinth.Size.Z / 2 else 2.5
	for _, side in { -1, 1 } do
		candyCane(folder, frame * CFrame.new(side * (halfWidth + 1.1), 0, -1.2), 6, side)
		gift(folder, frame * CFrame.new(side * (halfWidth - 1.2), 0, -front - 1.1) * CFrame.Angles(0, math.rad(side * 14), 0), 1.5, if side < 0 then RED else PINE[2], GOLD)
		gift(folder, frame * CFrame.new(side * (halfWidth - 3.0), 0, -front - 0.9) * CFrame.Angles(0, math.rad(-side * 10), 0), 1.0, if side < 0 then Color3.fromRGB(70, 150, 255) else RED, if side < 0 then WHITE else GOLD)
	end
end

-- Luz cálida en lo que brilla de cada adorno (el cristal del farol y la estrella del arco),
-- para que se vean de noche
local GLOWS = {
	vidrio = { Color = Color3.fromRGB(255, 196, 110), Range = 14, Brightness = 1.6 },
	estrella = { Color = Color3.fromRGB(255, 214, 90), Range = 18, Brightness = 2 },
}

-- Un adorno de ChristmasData (`key`) colocado en `frame`, con su luz
local function buildDecor(parent: Instance, key: string, frame: CFrame, name: string): Model?
	local data = (ChristmasData :: any)[key]
	if not data then
		warn("[ChristmasDecor] Adorno desconocido: " .. tostring(key))
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	local parts = GlbParts.build(model, data, frame)
	for partName, glow in GLOWS do
		local glowing = parts[partName]
		if glowing then
			local light = Instance.new("PointLight")
			light.Color = glow.Color
			light.Range = glow.Range
			light.Brightness = glow.Brightness
			light.Parent = glowing
		end
	end
	model.Parent = parent
	return model
end

-- Adornos del diseño por el Bosque (SeasonConfig.ForestDecor), sobre el suelo de bloques y de
-- cara a su FaceToward.
function ChristmasDecor.forest(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Christmas"
	for index, item in SeasonConfig.ForestDecor do
		local x, z = item.Position.X, item.Position.Y
		local y = StudWorld.FloorTop + StudFloor.raiseAt(x, z)
		local frame = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(item.FaceToward.X, y, item.FaceToward.Y))
		buildDecor(folder, item.Model, frame, item.Model .. index)
	end
	folder.Parent = parent
end

-- Árbol de Navidad de bloques del diseño (ChristmasData.Tree) con la base en `position`, girado
-- `yawDeg` y `scale` veces su tamaño: los árboles del Bosque en Navidad (WorldService).
function ChristmasDecor.tree(parent: Instance, position: Vector3, yawDeg: number, scale: number)
	local model = buildDecor(parent, "Tree", CFrame.new(position) * CFrame.Angles(0, math.rad(yawDeg), 0), "ChristmasTree")
	if model and scale ~= 1 then
		model.WorldPivot = CFrame.new(position) -- crece desde el suelo
		model:ScaleTo(scale)
	end
end

return ChristmasDecor
