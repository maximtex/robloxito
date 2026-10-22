-- Construye el Círculo Elemental: un altar por cada núcleo distinto de Naturaleza
-- (CoreConfig.Order), en las posiciones de CoreShrineConfig. Solo decorativo.
--
-- Todo se construye DORMIDO (piedra gris, sin brillo): cada cliente lo pinta según SUS
-- núcleos (CoreShrineController). Contrato con el cliente, por altar (Model = id del
-- elemento, con PrimaryPart = Base):
-- - Atributos del modelo: Element, Order (posición en CoreConfig.Order), RestY y FloatY
--   (altura en el mundo del centro del cristal dormido y despierto).
-- - Carpeta "Crystal": piezas del cristal; se mueven como un bloque.
-- - Carpeta "Orbiters": fragmentos que reposan en el escalón y orbitan al despertar.
-- - Piezas con atributo ShrineTint ("Crystal", "Rune" o "Accent") y sus estados:
--   AwakeColor/AwakeMaterial y SleepColor/SleepMaterial (nombre del Enum.Material).
-- - Emisores y luces con atributo AwakeOnly = true: solo encendidos si está despierto.
-- - Emisor "WakeBurst" (apagado) en el cristal para el destello al despertar.
-- - BillboardGui "Label" en ColumnCap con TextLabels "Title" y "State".
-- Sólidos: Base, Step, Column y ColumnCap. El resto no colisiona.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CoreConfig = require(Shared.Config.CoreConfig)
local CoreShrineConfig = require(Shared.Config.CoreShrineConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)

local CoreShrineService = {}

local ALTAR = CoreShrineConfig.Altar
local STONE = CoreShrineConfig.Stone
local ORIGIN = Vector3.new(GeneratorConfig.Position.X, 0, GeneratorConfig.Position.Z)
local GROUND = GeneratorConfig.Position.Y
local UPRIGHT = PartFactory.UPRIGHT
local DIAMOND = CFrame.Angles(0, math.rad(45), 0)
-- Cubo apoyado en un vértice (la diagonal (1, 1, 1) queda vertical): puntas de cristal.
local VERTEX_UP = CFrame.Angles(0, 0, math.rad(54.7356)) * DIAMOND

-- Medidas derivadas del altar (alturas relativas al suelo).
local BASE_TOP = ALTAR.BaseHeight - 0.1 -- la base está algo hundida en la hierba
local STEP_TOP = BASE_TOP + ALTAR.StepHeight
local CAP_HEIGHT = 0.3
local CAP_TOP = STEP_TOP + ALTAR.ColumnHeight + CAP_HEIGHT

type ElementLook = {
	Color: Color3,
	Glow: Color3,
	Stone: Color3?,
	Motif: string,
	Title: string?,
}

local function materialName(material: Enum.Material): string
	return (tostring(material):match("[^%.]+$")) :: string
end

-- Estado de una pieza teñible: dormida (como se construye) y despierta.
local function tint(part: BasePart, kind: string, awakeColor: Color3, awakeMaterial: Enum.Material, sleepColor: Color3, sleepMaterial: Enum.Material)
	part:SetAttribute("ShrineTint", kind)
	part:SetAttribute("AwakeColor", awakeColor)
	part:SetAttribute("AwakeMaterial", materialName(awakeMaterial))
	part:SetAttribute("SleepColor", sleepColor)
	part:SetAttribute("SleepMaterial", materialName(sleepMaterial))
	part.Color = sleepColor
	part.Material = sleepMaterial
end

local function awakeOnly(instance: Instance)
	instance:SetAttribute("AwakeOnly", true)
	;(instance :: any).Enabled = false
end

local function emitter(parent: Instance, name: string, properties: { [string]: any }): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	particles.Name = name
	particles.LightEmission = 1
	particles.LightInfluence = 0
	for key, value in properties do
		(particles :: any)[key] = value
	end
	particles.Parent = parent
	awakeOnly(particles)
	return particles
end

local function decor(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	return PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material,
		Shape = shape,
		Solid = false,
	})
end

-- Prisma de cristal (sección rombo) con punta, desde `base` hacia arriba.
local function prism(parent: Instance, name: string, base: CFrame, width: number, height: number, color: Color3, material: Enum.Material): (Part, Part)
	local bodyHeight = height - width * 0.5
	local body = decor(parent, name, Vector3.new(width, bodyHeight, width), base * CFrame.new(0, bodyHeight / 2, 0) * DIAMOND, color, material)
	local tip = decor(parent, name .. "Tip", Vector3.new(width * 0.72, width * 0.72, width * 0.72), base * CFrame.new(0, bodyHeight, 0) * VERTEX_UP, color, material)
	return body, tip
end

-- Motivos de la base -------------------------------------------------------------------
-- Cuatro adornos en las diagonales del altar, orientados hacia fuera. `at` es el
-- CFrame del adorno sobre la base (Y = parte alta de la base, -Z hacia fuera).

local MOTIFS: { [string]: (Instance, CFrame, number, ElementLook, Color3) -> () } = {}

-- Agua: cuencos de piedra con agua luminosa y gotas que suben.
MOTIFS.Pool = function(folder, at, index, look, stone)
	decor(folder, "Bowl" .. index, Vector3.new(0.4, 0.95, 0.95), at * CFrame.new(0, 0.2, 0) * UPRIGHT, stone, Enum.Material.Slate, Enum.PartType.Cylinder)
	local water = decor(folder, "Water" .. index, Vector3.new(0.06, 0.78, 0.78), at * CFrame.new(0, 0.41, 0) * UPRIGHT, STONE.DormantRune, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	tint(water, "Accent", look.Color, Enum.Material.Neon, STONE.DormantRune, Enum.Material.SmoothPlastic)
	emitter(water, "Droplets", {
		Rate = 3,
		Lifetime = NumberRange.new(0.8, 1.2),
		Speed = NumberRange.new(1.2, 2),
		Acceleration = Vector3.new(0, -4, 0),
		EmissionDirection = Enum.NormalId.Right, -- el eje X del cilindro apunta arriba
		SpreadAngle = Vector2.new(15, 15),
		Size = NumberSequence.new(0.14, 0.04),
		Color = ColorSequence.new(look.Glow),
	})
end

-- Fuego: braseros con brasas y llamas.
MOTIFS.Braziers = function(folder, at, index, look, stone)
	decor(folder, "BrazierLeg" .. index, Vector3.new(0.7, 0.3, 0.3), at * CFrame.new(0, 0.35, 0) * UPRIGHT, STONE.Dark, Enum.Material.Metal, Enum.PartType.Cylinder)
	decor(folder, "BrazierBowl" .. index, Vector3.new(0.3, 0.9, 0.9), at * CFrame.new(0, 0.8, 0) * UPRIGHT, STONE.Dark, Enum.Material.Metal, Enum.PartType.Cylinder)
	local coals = decor(folder, "Coals" .. index, Vector3.new(0.55, 0.55, 0.55), at * CFrame.new(0, 0.95, 0), STONE.DormantRune, Enum.Material.Slate, Enum.PartType.Ball)
	tint(coals, "Accent", look.Color, Enum.Material.Neon, STONE.DormantRune, Enum.Material.Slate)
	emitter(coals, "Flames", {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Rate = 10,
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(1.2, 2),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(10, 10),
		Size = NumberSequence.new(0.6, 0.1),
		Transparency = NumberSequence.new(0.2, 1),
		Color = ColorSequence.new(look.Glow, look.Color),
		LightEmission = 0.7,
	})
end

-- Viento: menhires con una espiral de runas y hojas que giran alrededor.
MOTIFS.Gusts = function(folder, at, index, look, stone)
	decor(folder, "Menhir" .. index, Vector3.new(0.5, 1.3, 0.32), at * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(if index % 2 == 0 then 6 else -6)), stone, Enum.Material.Slate)
	local swirl = decor(folder, "Swirl" .. index, Vector3.new(0.05, 0.34, 0.34), at * CFrame.new(0, 0.75, -0.17) * CFrame.Angles(0, math.rad(90), 0), STONE.DormantRune, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	tint(swirl, "Accent", look.Color, Enum.Material.Neon, STONE.DormantRune, Enum.Material.SmoothPlastic)
	emitter(swirl, "Leaves", {
		Rate = 2,
		Lifetime = NumberRange.new(1.5, 2.2),
		Speed = NumberRange.new(0.6, 1),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 0.6, 0),
		RotSpeed = NumberRange.new(-180, 180),
		Rotation = NumberRange.new(0, 360),
		Size = NumberSequence.new(0.18, 0.05),
		Color = ColorSequence.new(look.Glow, look.Color),
	})
end

-- Rayo: agujas de metal con punta luminosa y chispas.
MOTIFS.Spires = function(folder, at, index, look, stone)
	decor(folder, "SpireBase" .. index, Vector3.new(0.3, 0.6, 0.6), at * CFrame.new(0, 0.12, 0) * UPRIGHT, stone, Enum.Material.Slate, Enum.PartType.Cylinder)
	decor(folder, "Spire" .. index, Vector3.new(0.18, 1.6, 0.18), at * CFrame.new(0, 1.05, 0) * DIAMOND, STONE.Dark, Enum.Material.Metal)
	local tip = decor(folder, "SpireTip" .. index, Vector3.new(0.24, 0.24, 0.24), at * CFrame.new(0, 1.9, 0) * VERTEX_UP, STONE.DormantRune, Enum.Material.Metal)
	tint(tip, "Accent", look.Color, Enum.Material.Neon, STONE.DormantRune, Enum.Material.Metal)
	emitter(tip, "Sparks", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = 4,
		Lifetime = NumberRange.new(0.15, 0.3),
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.3, 0),
		Color = ColorSequence.new(look.Glow),
	})
end

-- Hielo: grupos de carámbanos y copos que caen.
MOTIFS.Frost = function(folder, at, index, look, stone)
	local lean = math.rad(if index % 2 == 0 then 12 else -12)
	local body, tip = prism(folder, "Icicle" .. index, at * CFrame.Angles(0, 0, lean), 0.36, 1.25, STONE.Dormant, Enum.Material.Glass)
	local small, smallTip = prism(folder, "IcicleSmall" .. index, at * CFrame.new(0.32, 0, 0.1) * CFrame.Angles(0, 0, lean - 0.4), 0.24, 0.7, STONE.Dormant, Enum.Material.Glass)
	for _, part in { body, tip, small, smallTip } do
		tint(part, "Accent", look.Color, Enum.Material.Glass, STONE.Dormant, Enum.Material.Slate)
	end
	emitter(body, "Snow", {
		Rate = 2,
		Lifetime = NumberRange.new(1.4, 2),
		Speed = NumberRange.new(0.3, 0.6),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -0.6, 0),
		Size = NumberSequence.new(0.14, 0.06),
		Color = ColorSequence.new(look.Glow),
	})
end

-- Sombra: esquirlas de obsidiana inclinadas hacia fuera, con grietas violeta y humo.
MOTIFS.Obsidian = function(folder, at, index, look, stone)
	local base = at * CFrame.new(0, 0, 0.3) * CFrame.Angles(math.rad(-14), 0, 0) -- algo hacia dentro: no sale de la base
	decor(folder, "Shard" .. index, Vector3.new(0.4, 1.3, 0.4), base * CFrame.new(0, 0.55, 0) * DIAMOND, Color3.fromRGB(26, 22, 34), Enum.Material.Glass)
	local tip = decor(folder, "ShardTip" .. index, Vector3.new(0.3, 0.3, 0.3), base * CFrame.new(0, 1.22, 0) * VERTEX_UP, STONE.DormantRune, Enum.Material.Glass)
	tint(tip, "Accent", look.Color, Enum.Material.Neon, STONE.DormantRune, Enum.Material.Glass)
	emitter(tip, "Smoke", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 2,
		Lifetime = NumberRange.new(1.2, 1.8),
		Speed = NumberRange.new(0.3, 0.6),
		SpreadAngle = Vector2.new(30, 30),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new(0.5, 1.2),
		Transparency = NumberSequence.new(0.5, 1),
		Color = ColorSequence.new(look.Color),
		LightEmission = 0.2,
	})
end

-- Celestial: postes dorados con orbes de luz y estrellas.
MOTIFS.Halo = function(folder, at, index, look, stone)
	decor(folder, "Post" .. index, Vector3.new(0.9, 0.22, 0.22), at * CFrame.new(0, 0.45, 0) * UPRIGHT, Color3.fromRGB(214, 176, 92), Enum.Material.Metal, Enum.PartType.Cylinder)
	local orb = decor(folder, "Orb" .. index, Vector3.new(0.42, 0.42, 0.42), at * CFrame.new(0, 1.05, 0), STONE.DormantRune, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	tint(orb, "Accent", look.Color, Enum.Material.Neon, STONE.DormantRune, Enum.Material.SmoothPlastic)
	emitter(orb, "Stars", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = 2,
		Lifetime = NumberRange.new(1, 1.6),
		Speed = NumberRange.new(0.3, 0.7),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.35, 0),
		Color = ColorSequence.new(look.Glow),
		Rotation = NumberRange.new(0, 360),
	})
end

-- Altar ------------------------------------------------------------------------------

local function buildAltar(parent: Instance, elementId: string, order: number)
	local look: ElementLook = CoreShrineConfig.Elements[elementId]
	local offset = CoreShrineConfig.offset(elementId)
	local center = ORIGIN + Vector3.new(offset.X, GROUND, offset.Y)
	-- Mirando al cristal central: -Z del altar apunta al centro.
	local facing = CFrame.lookAt(center, Vector3.new(ORIGIN.X, GROUND, ORIGIN.Z))
	local stone = look.Stone or STONE.Base
	local scale = if elementId == "Celestial" then ALTAR.CelestialScale else 1

	local model = Instance.new("Model")
	model.Name = elementId
	model:SetAttribute("Element", elementId)
	model:SetAttribute("Order", order)

	-- Estructura de piedra (sólida)
	local footprint = CoreShrineConfig.FootprintRadius
	local base = PartFactory.verticalCylinder(model, "Base", center + Vector3.new(0, BASE_TOP - ALTAR.BaseHeight / 2, 0), ALTAR.BaseHeight, footprint * 2, stone, Enum.Material.Slate, true)
	PartFactory.verticalCylinder(model, "Step", center + Vector3.new(0, STEP_TOP - ALTAR.StepHeight / 2, 0), ALTAR.StepHeight, ALTAR.StepRadius * 2, stone, Enum.Material.Slate, true)
	PartFactory.verticalCylinder(model, "Column", center + Vector3.new(0, STEP_TOP + ALTAR.ColumnHeight / 2, 0), ALTAR.ColumnHeight, ALTAR.ColumnDiameter, stone, Enum.Material.Slate, true)
	local cap = PartFactory.verticalCylinder(model, "ColumnCap", center + Vector3.new(0, CAP_TOP - CAP_HEIGHT / 2, 0), CAP_HEIGHT, ALTAR.ColumnDiameter + 0.5, stone, Enum.Material.Slate, true)
	model.PrimaryPart = base

	-- Anillo de runas sobre el escalón (disco luminoso con un disco de piedra encima)
	local rune = decor(model, "Rune", Vector3.new(0.06, ALTAR.StepRadius * 2 - 0.4, ALTAR.StepRadius * 2 - 0.4), CFrame.new(center + Vector3.new(0, STEP_TOP + 0.02, 0)) * UPRIGHT, STONE.DormantRune, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	tint(rune, "Rune", look.Color, Enum.Material.Neon, STONE.DormantRune, Enum.Material.SmoothPlastic)
	decor(model, "RuneInner", Vector3.new(0.08, ALTAR.StepRadius * 2 - 1.0, ALTAR.StepRadius * 2 - 1.0), CFrame.new(center + Vector3.new(0, STEP_TOP + 0.03, 0)) * UPRIGHT, stone, Enum.Material.Slate, Enum.PartType.Cylinder)
	-- Musgo en el borde de la base
	for index = 1, 3 do
		local angle = math.rad(40 + index * 110)
		local position = center + Vector3.new(math.cos(angle) * (footprint - 0.45), BASE_TOP - 0.05, math.sin(angle) * (footprint - 0.45))
		-- Alargado a lo largo del borde (tangente al círculo de la base)
		PartFactory.ellipsoid(model, "Moss" .. index, CFrame.new(position) * CFrame.Angles(0, -(angle + math.pi / 2), 0), Vector3.new(1.1, 0.3, 0.7), STONE.Moss, Enum.Material.LeafyGrass)
	end

	-- Cristal (dormido: apoyado sobre la columna)
	local crystalHeight = ALTAR.CrystalHeight * scale
	local crystalWidth = ALTAR.CrystalWidth * scale
	local bodyHeight = crystalHeight * 0.55
	local tipSize = crystalWidth * 0.78
	local tipReach = tipSize * 0.866 -- semidiagonal del cubo apoyado en un vértice
	local half = bodyHeight / 2 + tipReach
	local restY = GROUND + CAP_TOP + half - tipReach * 0.6 -- la punta inferior encaja en el capitel
	local floatY = GROUND + CAP_TOP + half + 1.3
	model:SetAttribute("RestY", restY)
	model:SetAttribute("FloatY", floatY)

	local crystalFolder = PartFactory.folder(model, "Crystal")
	local crystalCenter = CFrame.new(center.X, restY, center.Z)
	local body = decor(crystalFolder, "CrystalBody", Vector3.new(crystalWidth, bodyHeight, crystalWidth), crystalCenter * DIAMOND, STONE.Dormant, Enum.Material.Slate)
	local top = decor(crystalFolder, "CrystalTop", Vector3.one * tipSize, crystalCenter * CFrame.new(0, bodyHeight / 2, 0) * VERTEX_UP, STONE.Dormant, Enum.Material.Slate)
	local bottom = decor(crystalFolder, "CrystalBottom", Vector3.one * tipSize, crystalCenter * CFrame.new(0, -bodyHeight / 2, 0) * VERTEX_UP, STONE.Dormant, Enum.Material.Slate)
	for _, part in { body, top, bottom } do
		tint(part, "Crystal", look.Color, Enum.Material.Neon, STONE.Dormant, Enum.Material.Slate)
	end

	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = look.Glow
	glow.Range = ALTAR.LightRange
	glow.Brightness = 1.2
	glow.Shadows = false
	glow.Parent = body
	awakeOnly(glow)
	emitter(body, "Aura", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = 5,
		Lifetime = NumberRange.new(1, 1.6),
		Speed = NumberRange.new(0.4, 0.9),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.35, 0),
		Color = ColorSequence.new(look.Glow, look.Color),
	})
	local burst = Instance.new("ParticleEmitter")
	burst.Name = "WakeBurst"
	burst.Enabled = false
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Lifetime = NumberRange.new(0.6, 1)
	burst.Speed = NumberRange.new(6, 10)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Drag = 4
	burst.Size = NumberSequence.new(0.5, 0)
	burst.Color = ColorSequence.new(look.Glow, look.Color)
	burst.LightEmission = 1
	burst.LightInfluence = 0
	burst.Parent = body

	-- Fragmentos: reposan en el escalón (dormido) y orbitan el cristal (despierto).
	local orbiters = PartFactory.folder(model, "Orbiters")
	local orbiterCount = if elementId == "Celestial" then 6 else ALTAR.OrbiterCount
	for index = 1, orbiterCount do
		local angle = math.rad(index * 360 / orbiterCount + 20)
		local restPosition = center + Vector3.new(math.cos(angle) * (ALTAR.ColumnDiameter / 2 + 0.45), STEP_TOP + 0.18, math.sin(angle) * (ALTAR.ColumnDiameter / 2 + 0.45))
		local shard: Part
		if elementId == "Celestial" then
			shard = decor(orbiters, "Orbiter" .. index, Vector3.new(0.34, 0.34, 0.34), CFrame.new(restPosition), STONE.Dormant, Enum.Material.Slate, Enum.PartType.Ball)
		else
			shard = decor(orbiters, "Orbiter" .. index, Vector3.new(0.24, 0.62, 0.24), CFrame.new(restPosition) * CFrame.Angles(0, angle, math.rad(80)) * DIAMOND, STONE.Dormant, Enum.Material.Slate)
		end
		tint(shard, "Crystal", look.Color, Enum.Material.Neon, STONE.Dormant, Enum.Material.Slate)
	end

	-- Adornos del elemento en las cuatro diagonales de la base
	local motifs = PartFactory.folder(model, "Motif")
	local buildMotif = MOTIFS[look.Motif]
	for index = 1, 4 do
		local angle = math.rad(45 + (index - 1) * 90)
		local radius = footprint - 0.55
		local at = facing * CFrame.new(math.sin(angle) * radius, BASE_TOP, -math.cos(angle) * radius) * CFrame.Angles(0, -angle, 0)
		buildMotif(motifs, at, index, look, stone)
	end

	-- Rótulo (lo actualiza cada cliente)
	local label = Instance.new("BillboardGui")
	label.Name = "Label"
	label.Size = UDim2.fromOffset(180, 46)
	-- Encima del cristal despierto (el rótulo cuelga del capitel).
	local capCenterY = GROUND + CAP_TOP - CAP_HEIGHT / 2
	label.StudsOffsetWorldSpace = Vector3.new(0, floatY + half + 1.1 - capCenterY, 0)
	label.MaxDistance = ALTAR.LabelMaxDistance
	label.LightInfluence = 0
	label.Parent = cap
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 19
	title.TextColor3 = Color3.fromRGB(246, 242, 228)
	title.TextStrokeTransparency = 0.4
	title.Text = look.Title or ("Núcleo de " .. CoreConfig.Elements[elementId].DisplayName)
	title.Parent = label
	local state = Instance.new("TextLabel")
	state.Name = "State"
	state.BackgroundTransparency = 1
	state.Position = UDim2.fromOffset(0, 24)
	state.Size = UDim2.new(1, 0, 0, 20)
	state.Font = Enum.Font.GothamBold
	state.TextSize = 14
	state.TextColor3 = Color3.fromRGB(198, 202, 186)
	state.TextStrokeTransparency = 0.5
	state.Text = "Próximamente"
	state.Parent = label

	model.Parent = parent
end

function CoreShrineService.start()
	PartFactory.removeExisting(workspace, CoreShrineConfig.ModelName)
	local root = Instance.new("Model")
	root.Name = CoreShrineConfig.ModelName
	for order, elementId in CoreConfig.Order do
		if elementId ~= CoreConfig.DefaultElement then
			buildAltar(root, elementId, order)
		end
	end
	root.Parent = workspace
end

return CoreShrineService
