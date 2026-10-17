-- Construye el modelo visual de una mascota con piezas nativas (sin recursos externos).
-- El modelo tiene una pieza raíz anclada ("Root"); el resto va soldado a ella, de modo
-- que basta con mover Root para mover la mascota. Todo es local al cliente y sin colisión.
-- El frente de la mascota es -Z (hacia donde mira).
--
-- ARTE DEFINITIVO: todos los estilos de este archivo son PROTOTIPOS. Si existe
-- ReplicatedStorage.PetModels.<PetId> (un Model con PrimaryPart), se usa ese modelo en
-- su lugar, sin cambiar nada más. Así se sustituye el prototipo por el arte final.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.PetConfig)

local BLACK = Color3.fromRGB(28, 26, 30)
local WHITE = Color3.fromRGB(246, 244, 236)
local CREAM = Color3.fromRGB(240, 230, 214)
local BLUSH = Color3.fromRGB(255, 160, 170)
local GOLD = Color3.fromRGB(244, 196, 90)

local PetModelBuilder = {}

type Builder = {
	Model: Model,
	Root: BasePart,
}

local function newPart(builder: Builder, name: string, shape: Enum.PartType, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = builder.Root.CFrame * offset
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Anchored = false

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = builder.Root
	weld.Part1 = part
	weld.Parent = part

	part.Parent = builder.Model
	return part
end

local function ball(builder: Builder, name: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material?)
	return newPart(builder, name, Enum.PartType.Ball, Vector3.one * diameter, CFrame.new(position), color, material)
end

local function block(builder: Builder, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
	return newPart(builder, name, Enum.PartType.Block, size, offset, color, material)
end

local function eyes(builder: Builder, y: number, z: number, spacing: number, diameter: number)
	for index, side in { -1, 1 } do
		ball(builder, "Eye" .. index, diameter, Vector3.new(side * spacing, y, z), BLACK)
	end
end

-- Estilos ---------------------------------------------------------------------

local function buildSprout(builder: Builder, look)
	-- El cuerpo es la propia raíz.
	eyes(builder, 0.2, -0.7, 0.3, 0.28)
	for index, side in { -1, 1 } do
		ball(builder, "Cheek" .. index, 0.24, Vector3.new(side * 0.5, -0.05, -0.62), BLUSH)
	end
	block(builder, "Stem", Vector3.new(0.14, 0.5, 0.14), CFrame.new(0, 0.95, 0), look.Secondary)
	for index, side in { -1, 1 } do
		block(builder, "Leaf" .. index, Vector3.new(0.7, 0.08, 0.36), CFrame.new(side * 0.32, 1.2, 0) * CFrame.Angles(0, 0, side * 0.5), look.Secondary, Enum.Material.LeafyGrass)
	end
end

local function buildFox(builder: Builder, look)
	ball(builder, "Head", 1.15, Vector3.new(0, 0.55, -0.6), look.Primary)
	for index, side in { -1, 1 } do
		block(builder, "Ear" .. index, Vector3.new(0.3, 0.5, 0.14), CFrame.new(side * 0.32, 1.15, -0.6) * CFrame.Angles(0, 0, side * -0.35), look.Primary)
	end
	ball(builder, "Snout", 0.5, Vector3.new(0, 0.4, -1.08), CREAM)
	ball(builder, "Nose", 0.16, Vector3.new(0, 0.48, -1.33), BLACK)
	eyes(builder, 0.72, -1.08, 0.24, 0.18)
	-- Cola con punta de musgo
	ball(builder, "Tail", 0.85, Vector3.new(0, 0.3, 0.85), look.Primary)
	ball(builder, "TailTip", 0.55, Vector3.new(0, 0.45, 1.2), look.Secondary, Enum.Material.LeafyGrass)
end

local function buildOwl(builder: Builder, look)
	ball(builder, "Belly", 1.1, Vector3.new(0, -0.15, -0.4), Color3.fromRGB(226, 228, 242))
	for index, side in { -1, 1 } do
		ball(builder, "EyeWhite" .. index, 0.55, Vector3.new(side * 0.3, 0.3, -0.62), WHITE)
		ball(builder, "Pupil" .. index, 0.26, Vector3.new(side * 0.3, 0.3, -0.86), BLACK)
		block(builder, "Tuft" .. index, Vector3.new(0.12, 0.45, 0.25), CFrame.new(side * 0.45, 0.85, -0.1) * CFrame.Angles(0, 0, side * -0.4), look.Secondary)
		ball(builder, "Wing" .. index, 0.7, Vector3.new(side * 0.78, -0.05, 0), look.Secondary)
	end
	block(builder, "Beak", Vector3.new(0.18, 0.22, 0.2), CFrame.new(0, 0.08, -0.8), GOLD)
	-- Marca lunar luminosa en la frente
	ball(builder, "MoonMark", 0.3, Vector3.new(0, 0.66, -0.6), Color3.fromRGB(230, 240, 255), Enum.Material.Neon)
end

-- Seta Saltarina: el cuerpo (raíz) es el tallo; sombrero rojo con motas.
local function buildMushroom(builder: Builder, look)
	local cap = block(builder, "Cap", Vector3.new(2.2, 1.1, 2.2), CFrame.new(0, 0.75, 0), look.Primary)
	local capMesh = Instance.new("SpecialMesh")
	capMesh.MeshType = Enum.MeshType.Sphere
	capMesh.Parent = cap
	for index, offset in { Vector3.new(0.55, 1.12, -0.35), Vector3.new(-0.6, 1.05, 0.2), Vector3.new(0.1, 1.28, 0.45), Vector3.new(-0.2, 1.2, -0.6) } do
		ball(builder, "CapSpot" .. index, 0.3, offset, WHITE)
	end
	eyes(builder, 0.05, -0.5, 0.2, 0.18)
	for index, side in { -1, 1 } do
		ball(builder, "Cheek" .. index, 0.16, Vector3.new(side * 0.34, -0.1, -0.44), BLUSH)
		ball(builder, "Foot" .. index, 0.38, Vector3.new(side * 0.26, -0.5, -0.1), look.Secondary:Lerp(BLACK, 0.15))
	end
end

-- Zorrito de Brasa: zorro esbelto con cola de llama luminosa y brasas.
local function buildEmber(builder: Builder, look)
	ball(builder, "Head", 1.0, Vector3.new(0, 0.5, -0.65), look.Primary)
	ball(builder, "Snout", 0.42, Vector3.new(0, 0.38, -1.08), CREAM)
	ball(builder, "Nose", 0.14, Vector3.new(0, 0.44, -1.3), BLACK)
	eyes(builder, 0.66, -1.05, 0.22, 0.16)
	for index, side in { -1, 1 } do
		block(builder, "Ear" .. index, Vector3.new(0.24, 0.6, 0.12), CFrame.new(side * 0.28, 1.08, -0.62) * CFrame.Angles(0, 0, side * -0.25), look.Primary)
		block(builder, "EarTip" .. index, Vector3.new(0.2, 0.2, 0.13), CFrame.new(side * 0.36, 1.33, -0.62) * CFrame.Angles(0, 0, side * -0.25), BLACK)
	end
	-- Cola de llama: de pelaje a fuego, cada vez más pequeña y brillante.
	ball(builder, "Tail", 0.7, Vector3.new(0, 0.35, 0.75), look.Primary)
	ball(builder, "Flame", 0.55, Vector3.new(0, 0.72, 1.0), look.Secondary, Enum.Material.Neon)
	local tip = ball(builder, "FlameTip", 0.34, Vector3.new(0, 1.05, 1.12), Color3.fromRGB(255, 240, 170), Enum.Material.Neon)
	local embers = Instance.new("ParticleEmitter")
	embers.Rate = 3
	embers.Lifetime = NumberRange.new(0.6, 1)
	embers.Speed = NumberRange.new(0.5, 1.2)
	embers.Acceleration = Vector3.new(0, 2, 0)
	embers.Size = NumberSequence.new(0.12, 0)
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 110, 40))
	embers.LightEmission = 1
	embers.Parent = tip
end

-- Cervatillo Esmeralda: cuatro patas, cuello, astas de cristal y manchas claras.
local function buildFawn(builder: Builder, look)
	ball(builder, "Rear", 1.2, Vector3.new(0, 0.05, 0.55), look.Primary)
	block(builder, "Neck", Vector3.new(0.42, 0.85, 0.42), CFrame.new(0, 0.62, -0.55) * CFrame.Angles(math.rad(-20), 0, 0), look.Primary)
	ball(builder, "Head", 0.8, Vector3.new(0, 1.15, -0.85), look.Primary)
	ball(builder, "Snout", 0.4, Vector3.new(0, 1.04, -1.2), CREAM)
	ball(builder, "Nose", 0.12, Vector3.new(0, 1.08, -1.39), BLACK)
	eyes(builder, 1.25, -1.12, 0.2, 0.15)
	for index, side in { -1, 1 } do
		block(builder, "Ear" .. index, Vector3.new(0.45, 0.16, 0.12), CFrame.new(side * 0.4, 1.35, -0.8) * CFrame.Angles(0, 0, side * 0.35), look.Primary)
		-- Astas de cristal
		block(builder, "Antler" .. index, Vector3.new(0.1, 0.6, 0.1), CFrame.new(side * 0.2, 1.72, -0.8) * CFrame.Angles(0, 0, side * -0.35), look.Secondary, Enum.Material.Neon)
		block(builder, "AntlerBranch" .. index, Vector3.new(0.08, 0.35, 0.08), CFrame.new(side * 0.38, 1.86, -0.8) * CFrame.Angles(0, 0, side * -1.0), look.Secondary, Enum.Material.Neon)
	end
	-- Patas
	for index, leg in { Vector3.new(-0.3, 0, -0.4), Vector3.new(0.3, 0, -0.4), Vector3.new(-0.3, 0, 0.6), Vector3.new(0.3, 0, 0.6) } do
		block(builder, "Leg" .. index, Vector3.new(0.18, 1, 0.18), CFrame.new(leg.X, -0.85, leg.Z), look.Primary:Lerp(BLACK, 0.2))
		block(builder, "Hoof" .. index, Vector3.new(0.2, 0.14, 0.22), CFrame.new(leg.X, -1.32, leg.Z), BLACK)
	end
	for index, offset in { Vector3.new(0.2, 0.62, 0.3), Vector3.new(-0.25, 0.6, 0.6), Vector3.new(0.05, 0.55, 0.85) } do
		ball(builder, "Spot" .. index, 0.2, offset, WHITE)
	end
	ball(builder, "Tail", 0.3, Vector3.new(0, 0.3, 1.1), WHITE)
end

-- Zorrito de Cuarzo: cuerpo de cristal, orejas de prisma y cola de fragmentos en abanico.
local function buildQuartz(builder: Builder, look)
	ball(builder, "Head", 1.0, Vector3.new(0, 0.5, -0.62), look.Primary, Enum.Material.Glass)
	ball(builder, "Snout", 0.4, Vector3.new(0, 0.38, -1.05), CREAM)
	ball(builder, "Nose", 0.13, Vector3.new(0, 0.44, -1.26), BLACK)
	eyes(builder, 0.66, -1.04, 0.22, 0.16)
	for index, side in { -1, 1 } do
		-- Orejas: prismas de cuarzo luminoso
		block(builder, "Ear" .. index, Vector3.new(0.22, 0.62, 0.22), CFrame.new(side * 0.28, 1.08, -0.6) * CFrame.Angles(0, math.rad(45), side * -0.3), look.Secondary, Enum.Material.Neon)
	end
	-- Cola: tres fragmentos de cristal en abanico
	for index, angle in { -0.55, 0, 0.55 } do
		block(builder, "TailShard" .. index, Vector3.new(0.28, 0.95, 0.28), CFrame.new(angle * 0.5, 0.55, 0.85) * CFrame.Angles(math.rad(-50), 0, angle) * CFrame.Angles(0, math.rad(45), 0), look.Secondary, Enum.Material.Glass)
	end
	-- Pequeñas puntas de cristal en el lomo
	for index, z in { -0.1, 0.25 } do
		block(builder, "BackCrystal" .. index, Vector3.new(0.16, 0.38, 0.16), CFrame.new(0, 0.66, z) * CFrame.Angles(0, math.rad(45), 0), look.Secondary, Enum.Material.Neon)
	end
end

-- Tortuga de Musgo Cristalino: caparazón de musgo con cristales, cuatro patas y cabeza.
local TURTLE_SKIN = Color3.fromRGB(168, 186, 132)
local function buildTurtle(builder: Builder, look)
	local shell = block(builder, "Shell", Vector3.new(1.9, 1.05, 2.1), CFrame.new(0, 0.32, 0.05), look.Primary, Enum.Material.LeafyGrass)
	local shellMesh = Instance.new("SpecialMesh")
	shellMesh.MeshType = Enum.MeshType.Sphere
	shellMesh.Parent = shell
	for index, offset in { Vector3.new(0, 0.95, 0.1), Vector3.new(-0.42, 0.78, -0.3), Vector3.new(0.45, 0.76, 0.45) } do
		block(builder, "ShellCrystal" .. index, Vector3.new(0.26, 0.62, 0.26), CFrame.new(offset) * CFrame.Angles(0, math.rad(45), math.rad(offset.X * 30)), look.Secondary, Enum.Material.Neon)
	end
	ball(builder, "Head", 0.62, Vector3.new(0, 0.12, -1.05), TURTLE_SKIN)
	eyes(builder, 0.22, -1.32, 0.15, 0.12)
	for index, leg in { Vector3.new(-0.6, -0.3, -0.55), Vector3.new(0.6, -0.3, -0.55), Vector3.new(-0.6, -0.3, 0.6), Vector3.new(0.6, -0.3, 0.6) } do
		ball(builder, "Leg" .. index, 0.46, leg, TURTLE_SKIN)
	end
	ball(builder, "Tail", 0.22, Vector3.new(0, -0.05, 1.1), TURTLE_SKIN)
end

-- Dragón Bebé de Amatista: alas, cuernos de cristal, cola en tramos y vientre claro.
local function buildDragon(builder: Builder, look)
	ball(builder, "Belly", 0.85, Vector3.new(0, -0.15, -0.35), Color3.fromRGB(226, 206, 246))
	ball(builder, "Head", 0.9, Vector3.new(0, 0.62, -0.72), look.Primary)
	ball(builder, "Snout", 0.5, Vector3.new(0, 0.5, -1.12), look.Primary:Lerp(Color3.new(1, 1, 1), 0.15))
	eyes(builder, 0.76, -1.06, 0.2, 0.15)
	for index, side in { -1, 1 } do
		block(builder, "Horn" .. index, Vector3.new(0.12, 0.48, 0.12), CFrame.new(side * 0.22, 1.08, -0.58) * CFrame.Angles(math.rad(25), 0, side * -0.2), look.Secondary, Enum.Material.Neon)
		-- Alas: membranas finas inclinadas hacia arriba
		block(builder, "Wing" .. index, Vector3.new(1.3, 0.08, 0.85), CFrame.new(side * 0.95, 0.5, 0.15) * CFrame.Angles(0, side * -0.25, side * 0.5), look.Secondary)
		block(builder, "WingBone" .. index, Vector3.new(1.35, 0.12, 0.12), CFrame.new(side * 0.95, 0.56, -0.25) * CFrame.Angles(0, side * -0.25, side * 0.5), look.Primary)
	end
	-- Cola en tres tramos con punta de cristal
	for index, spec in { { Vector3.new(0, 0.05, 0.78), 0.55 }, { Vector3.new(0, 0.18, 1.12), 0.4 }, { Vector3.new(0, 0.32, 1.4), 0.28 } } do
		ball(builder, "Tail" .. index, spec[2], spec[1], look.Primary)
	end
	block(builder, "TailCrystal", Vector3.new(0.2, 0.42, 0.2), CFrame.new(0, 0.42, 1.6) * CFrame.Angles(math.rad(-60), math.rad(45), 0), look.Secondary, Enum.Material.Neon)
	for index, z in { -0.15, 0.2, 0.5 } do
		block(builder, "Spike" .. index, Vector3.new(0.14, 0.3, 0.14), CFrame.new(0, 0.66 - index * 0.06, z) * CFrame.Angles(0, math.rad(45), 0), look.Secondary, Enum.Material.Neon)
	end
end

local function buildGeneric(builder: Builder, look)
	eyes(builder, 0.2, -0.68, 0.28, 0.24)
	ball(builder, "Crest", 0.5, Vector3.new(0, 0.85, 0), look.Secondary)
end

local STYLES = {
	Sprout = buildSprout,
	Fox = buildFox,
	Owl = buildOwl,
	Mushroom = buildMushroom,
	Ember = buildEmber,
	Fawn = buildFawn,
	Quartz = buildQuartz,
	Turtle = buildTurtle,
	Dragon = buildDragon,
}

-- Diámetro del cuerpo (la pieza raíz) por estilo.
local BODY_SIZE = {
	Sprout = 1.6,
	Fox = 1.4,
	Owl = 1.6,
	Mushroom = 1.05,
	Ember = 1.25,
	Fawn = 1.3,
	Quartz = 1.25,
	Turtle = 1.0,
	Dragon = 1.2,
}

-- Material y color del cuerpo cuando no son los de por defecto.
local BODY_MATERIAL = {
	Quartz = Enum.Material.Glass,
}
local BODY_COLOR = {
	Turtle = TURTLE_SKIN, -- el cuerpo queda bajo el caparazón
}

-- Estilos cuyo cuerpo usa el color secundario (la Seta: tallo claro, sombrero de color).
local BODY_USES_SECONDARY = {
	Mushroom = true,
}

-- Arte definitivo: ReplicatedStorage.PetModels.<PetId>, si existe.
local function fromArt(petId: string): (Model?, BasePart?)
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local art = folder and folder:FindFirstChild(petId)
	if not (art and art:IsA("Model") and art.PrimaryPart) then
		return nil, nil
	end
	local model = art:Clone()
	local root = model.PrimaryPart :: BasePart
	model:PivotTo(CFrame.new())
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = true
			descendant.Anchored = descendant == root
			if descendant ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end
	model.Name = "Pet_" .. petId
	return model, root
end

-- Devuelve el modelo y su pieza raíz, o nil si la mascota no existe en la configuración.
function PetModelBuilder.build(petId: string): (Model?, BasePart?)
	local pet = PetConfig.Pets[petId]
	if not pet then
		return nil, nil
	end
	local artModel, artRoot = fromArt(petId)
	if artModel and artRoot then
		return artModel, artRoot
	end

	local look = pet.Look or {}
	local primary = look.Primary or Color3.fromRGB(200, 200, 200)
	local secondary = look.Secondary or primary
	local style = look.Style

	local model = Instance.new("Model")
	model.Name = "Pet_" .. petId

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.one * (BODY_SIZE[style] or 1.5)
	root.Color = BODY_COLOR[style] or (if BODY_USES_SECONDARY[style] then secondary else primary)
	root.Material = BODY_MATERIAL[style] or Enum.Material.SmoothPlastic
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	local builder: Builder = { Model = model, Root = root }
	local resolvedLook = {
		Primary = primary,
		Secondary = secondary,
	}
	local buildStyle = STYLES[style] or buildGeneric
	buildStyle(builder, resolvedLook)

	return model, root
end

return PetModelBuilder
