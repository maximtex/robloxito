-- EnemyService · Rigs: modelos de los enemigos (piezas, estilos BUILDERS / SHAPES y articulaciones).
-- Parte de EnemyService (ver EnemyService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ModelosZona1 = require(script.Parent.Parent.Parent.Util.ModelosZona1)
local Types = require(script.Parent.Types)
type Rig = Types.Rig


-- Modelos -----------------------------------------------------------------------
-- Diseñados con el suelo en Y = 0 y el frente hacia -Z; luego se colocan con PivotTo.


local function newRig(name: string, rootSize: Vector3, hipHeight: number, walkSpeed: number): Rig
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local rootHeight = hipHeight + rootSize.Y / 2
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = rootSize
	root.CFrame = CFrame.new(0, rootHeight, 0)
	root.Transparency = 1
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = hipHeight
	humanoid.WalkSpeed = walkSpeed
	humanoid.MaxHealth = 1e6 -- la vida real la lleva EnemyLogic
	humanoid.Health = 1e6
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	for _, state in { Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Climbing } do
		humanoid:SetStateEnabled(state, false)
	end
	humanoid.Parent = model

	return { Model = model, Root = root, Humanoid = humanoid, Eyes = {}, RootHeight = rootHeight }
end

-- Pieza decorativa sin colisión ni masa. Se une a la raíz después (addJoints).
local function piece(rig: Rig, name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Massless = true
	part.Parent = rig.Model
	return part
end

local function box(rig: Rig, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	return piece(rig, name, Enum.PartType.Block, size, cframe, color, material)
end

local function orb(rig: Rig, name: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material): Part
	return piece(rig, name, Enum.PartType.Ball, Vector3.one * diameter, CFrame.new(position), color, material)
end

local function limb(rig: Rig, name: string, from: Vector3, to: Vector3, diameter: number, color: Color3, material: Enum.Material): Part
	local direction = to - from
	return piece(rig, name, Enum.PartType.Cylinder, Vector3.new(direction.Magnitude, diameter, diameter), CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0), color, material)
end

local function eye(rig: Rig, name: string, diameter: number, position: Vector3, color: Color3)
	table.insert(rig.Eyes, orb(rig, name, diameter, position, color, Enum.Material.Neon))
end

local function crystalSpike(rig: Rig, name: string, size: Vector3, position: Vector3, tilt: Vector3, color: Color3)
	box(rig, name, size, CFrame.new(position) * CFrame.Angles(tilt.X, tilt.Y, tilt.Z) * CFrame.Angles(0, math.rad(45), 0), color, Enum.Material.Neon)
end

local BUILDERS = {}

-- Ojos de caricatura: globo blanco con pupila (la pupila es el "ojo" que cambia de color
-- al avisar un golpe) y ceja de enfado, para que se lea de lejos que es un enemigo.
local function cartoonEyes(rig: Rig, center: Vector3, spread: number, size: number, look)
	for side = -1, 1, 2 do
		local white = Vector3.new(side * spread, center.Y, center.Z)
		orb(rig, "Sclera" .. side, size, white, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		eye(rig, "Eye" .. side, size * 0.5, white + Vector3.new(-side * size * 0.06, -size * 0.04, -size * 0.36), look.Eyes)
		box(rig, "Brow" .. side, Vector3.new(size * 0.85, size * 0.2, size * 0.25), CFrame.new(white + Vector3.new(0, size * 0.58, -size * 0.28)) * CFrame.Angles(0, 0, math.rad(side * 22)), look.Eyes, Enum.Material.SmoothPlastic)
	end
end

-- Espinillo (caricatura): zarzamora redonda de color vivo con espinas amarillas, brote de
-- hojas, ojos grandes con ceja de enfado y patitas. Grande y de colores que resaltan
-- sobre el pasto (antes era una bola verde pequeña que se perdía).
function BUILDERS.Bramble(rig: Rig, look)
	local center = Vector3.new(0, 2.2, 0)
	orb(rig, "Body", 3.4, center, look.Primary, Enum.Material.SmoothPlastic)
	orb(rig, "Shine", 0.7, center + Vector3.new(-0.85, 1.05, -1.05), look.Primary:Lerp(Color3.new(1, 1, 1), 0.65), Enum.Material.SmoothPlastic)
	for index = 1, 8 do
		if index == 6 then
			continue -- sin espina delante de la cara (270° = -Z)
		end
		local angle = (index / 8) * math.pi * 2
		local direction = Vector3.new(math.cos(angle), if index % 2 == 0 then 0.55 else 0.1, math.sin(angle)).Unit
		local base = center + direction * 1.65
		box(rig, "Thorn" .. index, Vector3.new(0.42, 1.1, 0.42), CFrame.lookAt(base, base + direction) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.Angles(0, math.rad(45), 0), look.Secondary, Enum.Material.SmoothPlastic)
	end
	for index, tilt in { 28, -28 } do
		box(rig, "Leaf" .. index, Vector3.new(1.1, 0.16, 0.6), CFrame.new(center + Vector3.new(index == 1 and 0.42 or -0.42, 1.85, 0.1)) * CFrame.Angles(0, 0, math.rad(tilt)), Color3.fromRGB(110, 214, 86), Enum.Material.SmoothPlastic)
	end
	cartoonEyes(rig, center + Vector3.new(0, 0.35, -1.25), 0.62, 1.05, look)
	for side = -1, 1, 2 do
		orb(rig, "Foot" .. side, 1, Vector3.new(side * 0.75, 0.5, -0.1), look.Primary:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.SmoothPlastic)
	end
end

-- Bruto de Corteza: tronco andante con brazos largos y musgo.
function BUILDERS.Brute(rig: Rig, look)
	box(rig, "Torso", Vector3.new(3.2, 3.6, 2.4), CFrame.new(0, 3.7, 0), look.Primary, Enum.Material.Wood)
	local moss = box(rig, "Moss", Vector3.new(3.5, 0.9, 2.7), CFrame.new(0, 5.6, 0), look.Secondary, Enum.Material.LeafyGrass)
	local mossMesh = Instance.new("SpecialMesh")
	mossMesh.MeshType = Enum.MeshType.Sphere
	mossMesh.Parent = moss
	for side = -1, 1, 2 do
		eye(rig, "Eye" .. side, 0.36, Vector3.new(side * 0.6, 4.7, -1.22), look.Eyes)
		limb(rig, "Arm" .. side, Vector3.new(side * 1.9, 4.9, 0), Vector3.new(side * 2.3, 2.1, -0.7), 1, look.Primary, Enum.Material.Wood)
		orb(rig, "Fist" .. side, 1.3, Vector3.new(side * 2.3, 1.9, -0.7), look.Primary, Enum.Material.Wood)
		box(rig, "Leg" .. side, Vector3.new(1, 1.9, 1), CFrame.new(side * 0.8, 0.95, 0), look.Primary:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Wood)
	end
end

-- Guardián del Bosque (jefe): árbol antiguo con copa, brazos de rama y runa en el pecho.
function BUILDERS.Treant(rig: Rig, look)
	piece(rig, "Trunk", Enum.PartType.Cylinder, Vector3.new(9, 5, 5), CFrame.new(0, 7.5, 0) * CFrame.Angles(0, 0, math.rad(90)), look.Primary, Enum.Material.Wood)
	for index, blob in { { Vector3.new(0, 13.5, 0), 8 }, { Vector3.new(3, 12.5, 1), 6 }, { Vector3.new(-3, 12.5, 1), 6 }, { Vector3.new(0, 14.5, -2), 5 } } do
		orb(rig, "Canopy" .. index, blob[2], blob[1], look.Secondary, Enum.Material.LeafyGrass)
	end
	box(rig, "Rune", Vector3.new(1.6, 0.3, 0.1), CFrame.new(0, 7.5, -2.52), look.Eyes, Enum.Material.Neon)
	for side = -1, 1, 2 do
		eye(rig, "Eye" .. side, 0.8, Vector3.new(side * 1, 9.6, -2.35), look.Eyes)
		limb(rig, "UpperArm" .. side, Vector3.new(side * 2.3, 9, 0), Vector3.new(side * 5, 6, -1.5), 1.2, look.Primary, Enum.Material.Wood)
		limb(rig, "LowerArm" .. side, Vector3.new(side * 5, 6, -1.5), Vector3.new(side * 5.4, 3, -2.6), 1, look.Primary, Enum.Material.Wood)
		orb(rig, "Hand" .. side, 1.8, Vector3.new(side * 5.4, 2.8, -2.6), look.Primary, Enum.Material.Wood)
		for _, forward in { -1, 1 } do
			limb(rig, "Root" .. side .. forward, Vector3.new(side * 1.4, 3, 0), Vector3.new(side * 2.6, 0.3, forward * 1.6), 1.3, look.Primary, Enum.Material.Wood)
		end
	end
end

-- Fragmento Errante / Chispa Ígnea (caricatura): gema grande de color vivo con esquirlas
-- luminosas, ojos grandes con ceja de enfado y patitas.
function BUILDERS.Shard(rig: Rig, look)
	local center = Vector3.new(0, 2.6, 0)
	box(rig, "Core", Vector3.one * 2.4, CFrame.new(center) * CFrame.Angles(math.rad(45), 0, math.rad(35)), look.Primary, Enum.Material.SmoothPlastic)
	orb(rig, "Shine", 0.6, center + Vector3.new(-0.7, 1.1, -0.9), look.Primary:Lerp(Color3.new(1, 1, 1), 0.7), Enum.Material.SmoothPlastic)
	for index, spec in { { Vector3.new(1, 3.4, 0.3), Vector3.new(0, 0, -0.5) }, { Vector3.new(-1, 3.3, 0.4), Vector3.new(0, 0, 0.5) }, { Vector3.new(0, 4.1, 0.5), Vector3.new(0.3, 0, 0) }, { Vector3.new(0.5, 2.2, 1.2), Vector3.new(0.8, 0, 0) } } do
		crystalSpike(rig, "Shard" .. index, Vector3.new(0.5, 1.5, 0.5), spec[1], spec[2], look.Secondary)
	end
	cartoonEyes(rig, center + Vector3.new(0, 0.2, -1.25), 0.5, 0.85, look)
	for side = -1, 1, 2 do
		box(rig, "Leg" .. side, Vector3.new(0.55, 1.2, 0.55), CFrame.new(side * 0.55, 0.6, 0) * CFrame.Angles(0, math.rad(45), 0), look.Primary:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.SmoothPlastic)
	end
end

-- Material de la piedra de un estilo: look.Material (nombre de Enum.Material) o `default`
local function stoneOf(material: any, default: Enum.Material): Enum.Material
	if type(material) == "string" then
		local ok, value = pcall(function()
			return (Enum.Material :: any)[material]
		end)
		if ok and value then
			return value
		end
	end
	return default
end

-- Gólem de Geoda: bloques de pizarra con crecimientos de cristal (look.Material cambia la
-- piedra: los brutos de las Tierras Divididas son de basalto o de hielo glaciar).
function BUILDERS.Golem(rig: Rig, look)
	local stone = stoneOf(look.Material, Enum.Material.Slate)
	box(rig, "Torso", Vector3.new(3.6, 3.8, 2.8), CFrame.new(0, 3.9, 0), look.Primary, stone)
	box(rig, "Head", Vector3.new(1.8, 1.4, 1.6), CFrame.new(0, 6.5, -0.2), look.Primary, stone)
	for index, spec in { { Vector3.new(1.4, 6.2, 0.6), Vector3.new(0, 0, -0.4) }, { Vector3.new(-1.5, 6.0, 0.5), Vector3.new(0, 0, 0.4) }, { Vector3.new(0.6, 5.2, 1.5), Vector3.new(0.6, 0, 0) }, { Vector3.new(-0.7, 4.4, 1.5), Vector3.new(0.7, 0, 0) } } do
		crystalSpike(rig, "Crystal" .. index, Vector3.new(0.5, 1.6, 0.5), spec[1], spec[2], look.Secondary)
	end
	for side = -1, 1, 2 do
		eye(rig, "Eye" .. side, 0.32, Vector3.new(side * 0.45, 6.6, -1.02), look.Eyes)
		orb(rig, "Shoulder" .. side, 1.6, Vector3.new(side * 2.4, 5, 0), look.Primary, stone)
		limb(rig, "Arm" .. side, Vector3.new(side * 2.4, 5, 0), Vector3.new(side * 2.6, 2.4, -0.6), 1.1, look.Primary, stone)
		orb(rig, "Fist" .. side, 1.9, Vector3.new(side * 2.6, 2.3, -0.6), look.Primary, stone)
		box(rig, "Leg" .. side, Vector3.new(1.2, 1.9, 1.2), CFrame.new(side * 0.9, 0.95, 0), look.Primary, stone)
	end
end

-- Coloso de Amatista (jefe): gigante de pizarra con corona de amatista y núcleo brillante.
-- look.Material (nombre de Enum.Material) cambia la piedra: el Gólem de Hielo es de hielo glaciar.
-- look.Split: gigante de dos mitades (el Coloso del Equilibrio): su lado derecho (+X) lleva
-- los colores y la piedra de Split (Primary, Secondary, Eyes, Material).
function BUILDERS.Colossus(rig: Rig, look)
	local stone = stoneOf(look.Material, Enum.Material.Slate)
	local split = look.Split
	-- Colores de cada lado (side = -1 izquierda, 1 derecha)
	local function sideLook(side: number): (Color3, Color3, Color3, Enum.Material)
		if split and side > 0 then
			return split.Primary or look.Primary, split.Secondary or look.Secondary, split.Eyes or look.Eyes, stoneOf(split.Material, stone)
		end
		return look.Primary, look.Secondary, look.Eyes, stone
	end
	if split then
		-- Torso, cabeza y núcleo en dos mitades, con una veta brillante en medio
		for side = -1, 1, 2 do
			local primary, secondary, _, material = sideLook(side)
			box(rig, "TorsoHalf" .. side, Vector3.new(3.5, 8, 5), CFrame.new(side * 1.75, 8, 0), primary, material)
			box(rig, "HeadHalf" .. side, Vector3.new(1.5, 2.4, 2.6), CFrame.new(side * 0.75, 13.2, -0.4), primary, material)
			orb(rig, "CoreGemHalf" .. side, 1.5, Vector3.new(side * 0.55, 8.5, -2.55), secondary, Enum.Material.Neon)
		end
		box(rig, "Seam", Vector3.new(0.35, 8.2, 5.1), CFrame.new(0, 8, 0), Color3.fromRGB(255, 240, 255), Enum.Material.Neon)
	else
		box(rig, "Torso", Vector3.new(7, 8, 5), CFrame.new(0, 8, 0), look.Primary, stone)
		box(rig, "Head", Vector3.new(3, 2.4, 2.6), CFrame.new(0, 13.2, -0.4), look.Primary, stone)
		orb(rig, "CoreGem", 1.8, Vector3.new(0, 8.5, -2.55), look.Secondary, Enum.Material.Neon)
	end
	for index, spec in { { Vector3.new(0, 15.4, -0.4), Vector3.zero, 3.2 }, { Vector3.new(-1.1, 14.9, -0.3), Vector3.new(0, 0, 0.4), 2.4 }, { Vector3.new(1.1, 14.9, -0.3), Vector3.new(0, 0, -0.4), 2.4 }, { Vector3.new(-3.6, 12.6, 0.5), Vector3.new(0, 0, 0.5), 2.8 }, { Vector3.new(3.6, 12.6, 0.5), Vector3.new(0, 0, -0.5), 2.8 } } do
		local _, secondary = sideLook(if spec[1].X > 0 then 1 elseif spec[1].X < 0 then -1 else (if index % 2 == 0 then 1 else -1))
		crystalSpike(rig, "Crown" .. index, Vector3.new(0.9, spec[3], 0.9), spec[1], spec[2], secondary)
	end
	for side = -1, 1, 2 do
		local primary, _, eyes, material = sideLook(side)
		eye(rig, "Eye" .. side, 0.6, Vector3.new(side * 0.8, 13.4, -1.72), eyes)
		orb(rig, "Shoulder" .. side, 3, Vector3.new(side * 4.6, 10.5, 0), primary, material)
		limb(rig, "Arm" .. side, Vector3.new(side * 4.6, 10.5, 0), Vector3.new(side * 5.2, 4.2, -1.5), 2, primary, material)
		orb(rig, "Fist" .. side, 3.4, Vector3.new(side * 5.2, 4, -1.5), primary, material)
		box(rig, "Leg" .. side, Vector3.new(2.2, 3.8, 2.2), CFrame.new(side * 1.6, 1.9, 0), primary, material)
	end
end

local function darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end
local function lighter(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end
local GOLD = Color3.fromRGB(255, 200, 70)
local IVORY = Color3.fromRGB(246, 236, 210)
local STEEL = Color3.fromRGB(176, 182, 196)
local WOOD_DARK = Color3.fromRGB(104, 70, 44)

-- Lobo de Escarcha: lobo de pelo blanco azulado a cuatro patas con cristales de hielo en el
-- lomo, hocico, orejas de punta, cola y ojos que brillan. Las patas de delante son el grupo
-- Leg y las de atrás "Hind" (también Leg, con su pivote): trota en diagonal.
function BUILDERS.Wolf(rig: Rig, look)
	local fur, frost = look.Primary, look.Secondary
	box(rig, "Torso", Vector3.new(2.2, 1.9, 3.6), CFrame.new(0, 2.7, 0.2), fur, Enum.Material.SmoothPlastic)
	orb(rig, "Chest", 2.3, Vector3.new(0, 2.65, -1.35), lighter(fur, 0.4), Enum.Material.SmoothPlastic)
	box(rig, "Head", Vector3.new(1.7, 1.5, 1.6), CFrame.new(0, 3.65, -2.15), fur, Enum.Material.SmoothPlastic)
	box(rig, "Snout", Vector3.new(0.95, 0.75, 1.05), CFrame.new(0, 3.3, -3.25), lighter(fur, 0.5), Enum.Material.SmoothPlastic)
	orb(rig, "Nose", 0.42, Vector3.new(0, 3.55, -3.8), Color3.fromRGB(40, 44, 60), Enum.Material.SmoothPlastic)
	box(rig, "Fangs", Vector3.new(0.7, 0.18, 0.12), CFrame.new(0, 2.95, -3.72), IVORY, Enum.Material.SmoothPlastic)
	for side = -1, 1, 2 do
		box(rig, "Ear" .. side, Vector3.new(0.45, 0.85, 0.3), CFrame.new(side * 0.5, 4.65, -2.0) * CFrame.Angles(0, 0, math.rad(-side * 14)), fur, Enum.Material.SmoothPlastic)
		box(rig, "EarIn" .. side, Vector3.new(0.25, 0.5, 0.06), CFrame.new(side * 0.5, 4.6, -2.17) * CFrame.Angles(0, 0, math.rad(-side * 14)), frost, Enum.Material.SmoothPlastic)
		eye(rig, "Eye" .. side, 0.34, Vector3.new(side * 0.45, 3.9, -2.95), look.Eyes)
		box(rig, "Brow" .. side, Vector3.new(0.55, 0.14, 0.2), CFrame.new(side * 0.45, 4.18, -2.96) * CFrame.Angles(0, 0, math.rad(side * 20)), darker(frost, 0.4), Enum.Material.SmoothPlastic)
		-- Delanteras (Leg) y traseras (Hind): la delantera derecha y la trasera izquierda a la vez
		box(rig, "Leg" .. side, Vector3.new(0.6, 2.1, 0.6), CFrame.new(side * 0.72, 1.05, -1.25), fur, Enum.Material.SmoothPlastic)
		box(rig, "Hind" .. side, Vector3.new(0.65, 2.1, 0.65), CFrame.new(-side * 0.72, 1.05, 1.45), darker(fur, 0.08), Enum.Material.SmoothPlastic)
	end
	box(rig, "Tail", Vector3.new(0.55, 0.55, 1.9), CFrame.new(0, 3.15, 2.75) * CFrame.Angles(math.rad(28), 0, 0), fur, Enum.Material.SmoothPlastic)
	box(rig, "TailTip", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 3.6, 3.6), frost, Enum.Material.SmoothPlastic)
	for index, spec in { { Vector3.new(0, 3.95, -0.7), Vector3.new(-0.2, 0, 0) }, { Vector3.new(0.35, 3.85, 0.4), Vector3.new(0.2, 0, -0.4) }, { Vector3.new(-0.35, 3.8, 1.3), Vector3.new(0.3, 0, 0.4) } } do
		crystalSpike(rig, "Ice" .. index, Vector3.new(0.45, 1.2, 0.45), spec[1], spec[2], frost)
	end
end

-- Yeti: mole de pelo blanco con la cara y las manos azuladas, cuernos de marfil y cejas de
-- enfado; brazos largos que aplastan.
function BUILDERS.Yeti(rig: Rig, look)
	local fur, skin = look.Primary, look.Secondary
	box(rig, "Torso", Vector3.new(4, 4.2, 3), CFrame.new(0, 4.5, 0), fur, Enum.Material.SmoothPlastic)
	orb(rig, "Belly", 3, Vector3.new(0, 4.2, -0.75), lighter(skin, 0.55), Enum.Material.SmoothPlastic)
	orb(rig, "Fluff", 3.6, Vector3.new(0, 6.3, 0.2), fur, Enum.Material.SmoothPlastic)
	box(rig, "Head", Vector3.new(2.3, 2.1, 2.1), CFrame.new(0, 7.6, -0.45), fur, Enum.Material.SmoothPlastic)
	box(rig, "Face", Vector3.new(1.8, 1.4, 0.2), CFrame.new(0, 7.45, -1.52), skin, Enum.Material.SmoothPlastic)
	box(rig, "Mouth", Vector3.new(1, 0.22, 0.1), CFrame.new(0, 6.98, -1.64), darker(skin, 0.6), Enum.Material.SmoothPlastic)
	for side = -1, 1, 2 do
		box(rig, "Fang" .. side, Vector3.new(0.18, 0.32, 0.1), CFrame.new(side * 0.3, 7.08, -1.66), IVORY, Enum.Material.SmoothPlastic)
		eye(rig, "Eye" .. side, 0.38, Vector3.new(side * 0.42, 7.62, -1.66), look.Eyes)
		box(rig, "Brow" .. side, Vector3.new(0.7, 0.2, 0.22), CFrame.new(side * 0.42, 7.98, -1.66) * CFrame.Angles(0, 0, math.rad(side * 22)), darker(skin, 0.45), Enum.Material.SmoothPlastic)
		limb(rig, "Horn" .. side, Vector3.new(side * 0.95, 8.4, -0.4), Vector3.new(side * 1.75, 9.4, 0.1), 0.45, IVORY, Enum.Material.SmoothPlastic)
		orb(rig, "Shoulder" .. side, 2, Vector3.new(side * 2.55, 5.9, 0), fur, Enum.Material.SmoothPlastic)
		limb(rig, "Arm" .. side, Vector3.new(side * 2.6, 5.9, 0), Vector3.new(side * 2.9, 2.5, -0.6), 1.5, fur, Enum.Material.SmoothPlastic)
		orb(rig, "Fist" .. side, 1.9, Vector3.new(side * 2.9, 2.3, -0.6), skin, Enum.Material.SmoothPlastic)
		box(rig, "Leg" .. side, Vector3.new(1.4, 2.3, 1.4), CFrame.new(side * 1.05, 1.15, 0), fur, Enum.Material.SmoothPlastic)
		box(rig, "Foot" .. side, Vector3.new(1.5, 0.5, 1.9), CFrame.new(side * 1.05, 0.25, -0.25), skin, Enum.Material.SmoothPlastic)
	end
end

-- Goblin: bajito y verde, orejas largas, nariz de punta, chaleco de cuero y una daga.
function BUILDERS.Goblin(rig: Rig, look)
	local skin, leather = look.Primary, look.Secondary
	box(rig, "Torso", Vector3.new(1.8, 1.8, 1.2), CFrame.new(0, 2.6, 0), leather, Enum.Material.SmoothPlastic)
	box(rig, "Belt", Vector3.new(1.9, 0.3, 1.3), CFrame.new(0, 1.85, 0), darker(leather, 0.4), Enum.Material.SmoothPlastic)
	box(rig, "Head", Vector3.new(1.7, 1.5, 1.5), CFrame.new(0, 4.2, -0.1), skin, Enum.Material.SmoothPlastic)
	box(rig, "Nose", Vector3.new(0.35, 0.35, 0.65), CFrame.new(0, 4.05, -1.1) * CFrame.Angles(math.rad(-12), 0, 0), darker(skin, 0.15), Enum.Material.SmoothPlastic)
	box(rig, "Teeth", Vector3.new(0.7, 0.16, 0.1), CFrame.new(0, 3.72, -0.88), IVORY, Enum.Material.SmoothPlastic)
	cartoonEyes(rig, Vector3.new(0, 4.4, -0.7), 0.4, 0.62, look)
	for side = -1, 1, 2 do
		box(rig, "Ear" .. side, Vector3.new(1.3, 0.35, 0.5), CFrame.new(side * 1.25, 4.5, 0) * CFrame.Angles(0, math.rad(side * 15), math.rad(side * 22)), skin, Enum.Material.SmoothPlastic)
		limb(rig, "Arm" .. side, Vector3.new(side * 1.1, 3.2, 0), Vector3.new(side * 1.3, 1.95, -0.45), 0.45, skin, Enum.Material.SmoothPlastic)
		orb(rig, "Fist" .. side, 0.6, Vector3.new(side * 1.3, 1.9, -0.45), skin, Enum.Material.SmoothPlastic)
		box(rig, "Leg" .. side, Vector3.new(0.55, 1.3, 0.55), CFrame.new(side * 0.45, 0.65, 0), darker(leather, 0.25), Enum.Material.SmoothPlastic)
		box(rig, "Foot" .. side, Vector3.new(0.65, 0.3, 0.95), CFrame.new(side * 0.45, 0.15, -0.18), darker(skin, 0.3), Enum.Material.SmoothPlastic)
	end
	-- Daga en la mano derecha (va con el brazo: grupo Arm)
	box(rig, "Hand1", Vector3.new(0.18, 0.3, 0.5), CFrame.new(1.3, 1.9, -0.75), WOOD_DARK, Enum.Material.Wood)
	box(rig, "Hand1", Vector3.new(0.12, 0.3, 1.2), CFrame.new(1.3, 1.95, -1.6), STEEL, Enum.Material.Metal)
end

-- Goblin Bruto: un goblin enorme con casco con cuernos, peto de hierro, colmillos y un garrote.
function BUILDERS.GoblinBrute(rig: Rig, look)
	local skin, iron = look.Primary, look.Secondary
	box(rig, "Torso", Vector3.new(3.2, 3.2, 2.4), CFrame.new(0, 4.4, 0), skin, Enum.Material.SmoothPlastic)
	box(rig, "Armor", Vector3.new(3.35, 1.9, 2.55), CFrame.new(0, 5, 0), iron, Enum.Material.Metal)
	box(rig, "Belt", Vector3.new(3.4, 0.5, 2.6), CFrame.new(0, 3.1, 0), WOOD_DARK, Enum.Material.SmoothPlastic)
	box(rig, "Head", Vector3.new(2.2, 1.9, 2), CFrame.new(0, 7, -0.2), skin, Enum.Material.SmoothPlastic)
	box(rig, "Helmet", Vector3.new(2.4, 0.7, 2.2), CFrame.new(0, 8.15, -0.2), iron, Enum.Material.Metal)
	box(rig, "Nose", Vector3.new(0.5, 0.5, 0.7), CFrame.new(0, 6.95, -1.45), darker(skin, 0.15), Enum.Material.SmoothPlastic)
	cartoonEyes(rig, Vector3.new(0, 7.35, -1.05), 0.52, 0.75, look)
	for side = -1, 1, 2 do
		limb(rig, "HelmHorn" .. side, Vector3.new(side * 1.1, 8.3, -0.2), Vector3.new(side * 1.9, 9.4, -0.4), 0.4, IVORY, Enum.Material.SmoothPlastic)
		box(rig, "Ear" .. side, Vector3.new(1.4, 0.4, 0.6), CFrame.new(side * 1.5, 7.3, -0.1) * CFrame.Angles(0, math.rad(side * 12), math.rad(side * 20)), skin, Enum.Material.SmoothPlastic)
		box(rig, "Tusk" .. side, Vector3.new(0.22, 0.55, 0.22), CFrame.new(side * 0.55, 6.35, -1.18), IVORY, Enum.Material.SmoothPlastic)
		orb(rig, "Shoulder" .. side, 1.7, Vector3.new(side * 2.05, 5.6, 0), iron, Enum.Material.Metal)
		limb(rig, "Arm" .. side, Vector3.new(side * 2.05, 5.6, 0), Vector3.new(side * 2.35, 2.8, -0.6), 1, skin, Enum.Material.SmoothPlastic)
		orb(rig, "Fist" .. side, 1.35, Vector3.new(side * 2.35, 2.7, -0.6), skin, Enum.Material.SmoothPlastic)
		box(rig, "Leg" .. side, Vector3.new(1.1, 2, 1.1), CFrame.new(side * 0.8, 1, 0), darker(skin, 0.2), Enum.Material.SmoothPlastic)
	end
	-- Garrote con pinchos (va con el brazo derecho)
	limb(rig, "Hand1", Vector3.new(2.35, 2.5, -0.6), Vector3.new(2.5, 5.4, -2.6), 0.6, WOOD_DARK, Enum.Material.Wood)
	orb(rig, "Hand1", 1.5, Vector3.new(2.5, 5.6, -2.75), Color3.fromRGB(130, 90, 56), Enum.Material.Wood)
	for index = 1, 4 do
		local a = index / 4 * math.pi * 2
		box(rig, "Hand1", Vector3.new(0.25, 0.7, 0.25), CFrame.new(Vector3.new(2.5, 5.6, -2.75) + Vector3.new(math.cos(a) * 0.75, 0.2, math.sin(a) * 0.75)) * CFrame.Angles(math.sin(a) * 0.9, 0, -math.cos(a) * 0.9), STEEL, Enum.Material.Metal)
	end
end

-- Rey Goblin (jefe final del Mundo 1): un goblin gigante con corona de oro y joyas, armadura
-- real, capa roja y un hacha enorme. Ojos rojos que brillan.
function BUILDERS.GoblinKing(rig: Rig, look)
	local skin, royal = look.Primary, look.Secondary
	box(rig, "Torso", Vector3.new(7, 7, 4.6), CFrame.new(0, 9.6, 0), skin, Enum.Material.SmoothPlastic)
	box(rig, "Robe", Vector3.new(7.3, 4.2, 4.9), CFrame.new(0, 8.4, 0), royal, Enum.Material.Fabric)
	box(rig, "Chest", Vector3.new(5.2, 2.6, 0.4), CFrame.new(0, 11.2, -2.45), GOLD, Enum.Material.Metal)
	orb(rig, "Gem", 1.3, Vector3.new(0, 11.2, -2.7), look.Eyes, Enum.Material.Neon)
	box(rig, "Belt", Vector3.new(7.5, 0.9, 5), CFrame.new(0, 6.6, 0), GOLD, Enum.Material.Metal)
	box(rig, "Cape", Vector3.new(7.2, 9.5, 0.4), CFrame.new(0, 8.4, 2.75) * CFrame.Angles(math.rad(-6), 0, 0), royal, Enum.Material.Fabric)
	box(rig, "Head", Vector3.new(4.6, 4, 4.2), CFrame.new(0, 15.2, -0.3), skin, Enum.Material.SmoothPlastic)
	box(rig, "Nose", Vector3.new(0.9, 0.9, 1.5), CFrame.new(0, 14.8, -2.7) * CFrame.Angles(math.rad(-12), 0, 0), darker(skin, 0.15), Enum.Material.SmoothPlastic)
	box(rig, "Mouth", Vector3.new(2.4, 0.4, 0.2), CFrame.new(0, 13.75, -2.42), darker(skin, 0.6), Enum.Material.SmoothPlastic)
	cartoonEyes(rig, Vector3.new(0, 15.7, -2.0), 1.05, 1.5, look)
	-- Corona: aro de oro con picos y joyas
	box(rig, "Crown", Vector3.new(4.9, 1.1, 4.5), CFrame.new(0, 17.7, -0.3), GOLD, Enum.Material.Metal)
	for index = 1, 5 do
		local x = (index - 3) * 1.1
		box(rig, "CrownSpike" .. index, Vector3.new(0.7, if index == 3 then 2 else 1.4, 0.7), CFrame.new(x, 18.6 + (if index == 3 then 0.3 else 0), -2.1) * CFrame.Angles(0, math.rad(45), 0), GOLD, Enum.Material.Metal)
		orb(rig, "CrownGem" .. index, 0.5, Vector3.new(x, 17.7, -2.6), if index % 2 == 1 then look.Eyes else Color3.fromRGB(80, 200, 255), Enum.Material.Neon)
	end
	for side = -1, 1, 2 do
		box(rig, "Ear" .. side, Vector3.new(3.2, 0.7, 1.1), CFrame.new(side * 3.5, 15.8, 0) * CFrame.Angles(0, math.rad(side * 14), math.rad(side * 20)), skin, Enum.Material.SmoothPlastic)
		box(rig, "Tusk" .. side, Vector3.new(0.45, 1.1, 0.45), CFrame.new(side * 0.9, 13.4, -2.45), IVORY, Enum.Material.SmoothPlastic)
		orb(rig, "Shoulder" .. side, 3.3, Vector3.new(side * 4.6, 12.2, 0), GOLD, Enum.Material.Metal)
		limb(rig, "Arm" .. side, Vector3.new(side * 4.6, 12.2, 0), Vector3.new(side * 5.4, 6, -1.6), 2, skin, Enum.Material.SmoothPlastic)
		orb(rig, "Fist" .. side, 2.6, Vector3.new(side * 5.4, 5.8, -1.6), skin, Enum.Material.SmoothPlastic)
		box(rig, "Leg" .. side, Vector3.new(2.4, 4.2, 2.4), CFrame.new(side * 1.75, 2.1, 0), darker(skin, 0.2), Enum.Material.SmoothPlastic)
		box(rig, "Foot" .. side, Vector3.new(2.6, 1, 3.2), CFrame.new(side * 1.75, 0.5, -0.4), WOOD_DARK, Enum.Material.SmoothPlastic)
	end
	-- Hacha enorme en la mano derecha (va con el brazo)
	limb(rig, "Hand1", Vector3.new(5.4, 3.6, -1.6), Vector3.new(5.6, 15.5, -3.4), 0.85, WOOD_DARK, Enum.Material.Wood)
	box(rig, "Hand1", Vector3.new(0.5, 4.2, 3.4), CFrame.new(5.62, 14.2, -4.9) * CFrame.Angles(math.rad(-9), 0, 0), STEEL, Enum.Material.Metal)
	box(rig, "Hand1", Vector3.new(0.6, 4.4, 0.4), CFrame.new(5.62, 14.2, -6.55) * CFrame.Angles(math.rad(-9), 0, 0), lighter(STEEL, 0.4), Enum.Material.Metal)
end

-- Tamaño de la raíz (hitbox de movimiento), altura de cadera y radio de golpe por estilo.
-- Pivots: puntos de giro para la animación del cliente (cuerpo, hombro y cadera del lado
-- derecho; el izquierdo es su reflejo). Solo afectan a la presentación.
local SHAPES = {
	Bramble = { Root = Vector3.new(2.8, 2.8, 2.8), Hip = 0.8, Radius = 1.7, BarHeight = 5.4, Pivots = { Body = Vector3.new(0, 2.2, 0), Leg = Vector3.new(0.75, 0.8, 0) } },
	Brute = { Root = Vector3.new(3, 3.4, 2.2), Hip = 1.6, Radius = 2, BarHeight = 7, Pivots = { Body = Vector3.new(0, 1.9, 0), Arm = Vector3.new(1.9, 4.9, 0), Leg = Vector3.new(0.8, 1.9, 0) } },
	Treant = { Root = Vector3.new(5, 7, 4), Hip = 3, Radius = 4, BarHeight = 19, Pivots = { Body = Vector3.new(0, 3, 0), Arm = Vector3.new(2.3, 9, 0) } },
	Shard = { Root = Vector3.new(2.6, 2.8, 2.6), Hip = 1.2, Radius = 1.7, BarHeight = 5.8, Pivots = { Body = Vector3.new(0, 2.6, 0), Leg = Vector3.new(0.55, 1.2, 0) } },
	Golem = { Root = Vector3.new(3.4, 3.6, 2.6), Hip = 1.8, Radius = 2.2, BarHeight = 8.2, Pivots = { Body = Vector3.new(0, 1.9, 0), Arm = Vector3.new(2.4, 5, 0), Leg = Vector3.new(0.9, 1.9, 0) } },
	Colossus = { Root = Vector3.new(6, 8, 4.5), Hip = 3.5, Radius = 4.5, BarHeight = 18, Pivots = { Body = Vector3.new(0, 3.8, 0), Arm = Vector3.new(4.6, 10.5, 0), Leg = Vector3.new(1.6, 3.8, 0) } },
	-- Hind: pivote de las patas de atrás (cuadrúpedos; si no, el de Leg)
	Wolf = { Root = Vector3.new(2.6, 2.4, 4), Hip = 1.4, Radius = 2, BarHeight = 5.8, Pivots = { Body = Vector3.new(0, 2.4, 0), Leg = Vector3.new(0.72, 2.1, -1.25), Hind = Vector3.new(0.72, 2.1, 1.45) } },
	Yeti = { Root = Vector3.new(3.6, 4, 3), Hip = 2.2, Radius = 2.5, BarHeight = 10.6, Pivots = { Body = Vector3.new(0, 2.3, 0), Arm = Vector3.new(2.6, 5.9, 0), Leg = Vector3.new(1.05, 2.3, 0) } },
	Goblin = { Root = Vector3.new(2.2, 2.6, 2), Hip = 1.3, Radius = 1.6, BarHeight = 6.2, Pivots = { Body = Vector3.new(0, 1.3, 0), Arm = Vector3.new(1.1, 3.2, 0), Leg = Vector3.new(0.45, 1.3, 0) } },
	GoblinBrute = { Root = Vector3.new(3.4, 4, 3), Hip = 2, Radius = 2.4, BarHeight = 10.8, Pivots = { Body = Vector3.new(0, 2, 0), Arm = Vector3.new(2.05, 5.6, 0), Leg = Vector3.new(0.8, 2, 0) } },
	GoblinKing = { Root = Vector3.new(7, 9, 5), Hip = 4.2, Radius = 4.8, BarHeight = 22, Pivots = { Body = Vector3.new(0, 4.2, 0), Arm = Vector3.new(4.6, 12.2, 0), Leg = Vector3.new(1.75, 4.2, 0) } },
}

-- Enemigos del Bosque con los modelos 3D (.glb) de Santiago: Util.ModelosZona1
ModelosZona1.register(BUILDERS, SHAPES)

-- Articulaciones: cada pieza se une a la raíz con un Motor6D cuyo pivote es el de su grupo
-- (cuerpo, brazo o pierna). En reposo equivale a una soldadura; el cliente anima los
-- grupos escribiendo Motor6D.Transform (solo en su pantalla, sin tocar la IA ni la física).
-- Las raíces del Guardián quedan soldadas: están clavadas en el suelo.
local ARM_PARTS = { Arm = true, Fist = true, Hand = true, UpperArm = true, LowerArm = true, Shoulder = true }
local LEG_PARTS = { Leg = true, Foot = true, Hind = true }

local function poseGroup(partName: string): (string, number, string?)
	if partName:sub(1, 4) == "Root" then
		return "Static", 0
	end
	local base, side = partName:match("^(%a+)(%-?1)$")
	if base and ARM_PARTS[base] then
		return "Arm", tonumber(side) or 1, base
	elseif base and LEG_PARTS[base] then
		return "Leg", tonumber(side) or 1, base
	end
	return "Body", 0
end

local function addJoints(rig: Rig, pivots: { [string]: Vector3 })
	for _, part in rig.Model:GetChildren() do
		if not part:IsA("BasePart") or part == rig.Root then
			continue
		end
		local group, side, base = poseGroup(part.Name)
		if group ~= "Static" and not pivots[group] then
			group, side = "Body", 0 -- el estilo no anima ese grupo: va con el cuerpo
		end
		if group == "Static" then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rig.Root
			weld.Part1 = part
			weld.Parent = part
			continue
		end
		-- Patas de atrás de los cuadrúpedos: grupo Leg con su propio pivote (Pivots.Hind)
		local pivot = if group == "Leg" and base == "Hind" and pivots.Hind then pivots.Hind else pivots[group]
		if side ~= 0 then
			pivot = Vector3.new(pivot.X * side, pivot.Y, pivot.Z)
		end
		local motor = Instance.new("Motor6D")
		motor.Name = "Pose"
		motor.Part0 = rig.Root
		motor.Part1 = part
		motor.C0 = rig.Root.CFrame:ToObjectSpace(CFrame.new(pivot))
		motor.C1 = part.CFrame:ToObjectSpace(CFrame.new(pivot))
		motor:SetAttribute("Group", group)
		motor:SetAttribute("Side", side)
		motor:SetAttribute("Pivot", pivot)
		motor.Parent = part
	end
end

local Part = { Api = {} }

function Part.install(context: any)
	-- (esta parte no usa el estado compartido)
	context.BUILDERS = BUILDERS
	context.SHAPES = SHAPES
	context.addJoints = addJoints
	context.newRig = newRig
end

function Part.link(context: any)
	-- (nada que enlazar)
end

return Part
