-- Construye el Cristal del Renacimiento a partir del diseño 3D (cristal-renacimiento.obj):
-- plataforma escalonada de piedra antigua con 24 runas radiales y anillo rúnico grabado,
-- plinto hexagonal con emisor dorado, 6 garras rúnicas, 5 gemas de cristal y musgo en la
-- base, haz de energía ascendente con anillos, y el gran cristal hexagonal facetado con
-- bandas doradas, 2 brotes laterales de cristal, 2 anillos astronómicos dorados con nodos
-- rúnicos, núcleo luminoso interior y 3 fragmentos en órbita.
-- Es decorativo: la producción la calcula EnergyService.
--
-- Contrato con el cliente (estos nombres no deben cambiar):
-- - GeneratorAnimator mueve "Core", "Shell", "CrystalBody", "Orbiters", "FloatingRocks"
--   y "StageDetails/Fragments", y usa la PointLight y el ParticleEmitter de "Core".
-- - CrystalAppearance colorea las piezas con atributo "Tint" (Core, Shell, Runes, Shards,
--   Light, Particles) según la etapa y muestra u oculta los grupos de "StageDetails".
--   Esos detalles se construyen aquí UNA vez, ocultos (Transparency 1, emisores apagados).
--
-- Colisiones: solo la plataforma ("Dais", "DaisLip", "Tier") y los pilares son sólidos
-- (se puede caminar por todo el santuario). Todo lo demás es decorativo: sin colisión,
-- sin consultas y sin toques, así que no bloquea a jugadores ni a la IA.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GeneratorConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GeneratorConfig)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)

local Colors = GeneratorConfig.Colors

-- Colores exactos del archivo cristal-renacimiento.mtl
local MtlColors = {
	DarkStone = Color3.fromRGB(27, 25, 17),
	WarmStone = Color3.fromRGB(122, 99, 50),
	Runes = Colors.Turquoise,
	Gold = Color3.fromRGB(231, 154, 40),
	Core = Colors.Turquoise,
	Shards = Color3.fromRGB(12, 147, 131),
	Moss = Color3.fromRGB(3, 22, 16),
	EnergyBeam = Color3.fromRGB(103, 255, 222),
	CrystalGlass = Color3.fromRGB(103, 255, 222),
	CrystalFacet = Color3.fromRGB(1, 5, 6),
}

local PLATFORM_HEIGHT = GeneratorConfig.PlatformHeight
local PLATFORM_RADIUS = GeneratorConfig.PlatformDiameter / 2
local TIER_HEIGHT = 0.35
local TIER_TOP = PLATFORM_HEIGHT + TIER_HEIGHT
local SQRT3 = math.sqrt(3)

local GeneratorService = {}

-- Utilidades ----------------------------------------------------------------------

-- Cilindro entre dos puntos (raíces). Decorativo: nunca bloquea.
local function segment(parent: Instance, name: string, from: Vector3, to: Vector3, diameter: number, color: Color3, material: Enum.Material): Part
	local direction = to - from
	return PartFactory.part(parent, name, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(direction.Magnitude, diameter, diameter),
		-- lookAt orienta -Z hacia el destino; girar 90° en Y alinea el eje X del cilindro.
		CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Material = material,
		Solid = false,
	})
end

local function polar(origin: Vector3, angleDegrees: number, radius: number, height: number): Vector3
	local radians = math.rad(angleDegrees)
	return origin + Vector3.new(math.cos(radians) * radius, height, math.sin(radians) * radius)
end

-- Prisma hexagonal regular (3 bloques cruzados a 0°, 60° y 120°) fiel al OBJ.
local function hexPrism(
	parent: Instance,
	prefix: string,
	cframe: CFrame,
	radius: number,
	height: number,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	tint: string?
)
	local sideWidth = radius
	local flatToFlat = radius * SQRT3
	for index = 1, 3 do
		local part = PartFactory.part(parent, prefix .. "_" .. index, {
			Size = Vector3.new(sideWidth, height, flatToFlat),
			CFrame = cframe * CFrame.Angles(0, math.rad((index - 1) * 60), 0),
			Color = color,
			Material = material,
			Solid = false,
		})
		if transparency and transparency > 0 then
			part.Transparency = transparency
		end
		if tint then
			part:SetAttribute("Tint", tint)
		end
	end
end

-- Pirámide hexagonal vertical (6 cuñas dispuestas en hexágono) para las puntas del cristal.
-- Al mantener las cuñas verticales (solo rotación en Y, o 180° en X si está invertida),
-- su caja envolvente tiene exactamente la altura `height` sin sobresalir.
local function hexPyramid(
	parent: Instance,
	prefix: string,
	center: Vector3,
	radius: number,
	height: number,
	inverted: boolean,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	tint: string?
)
	local apothem = radius * SQRT3 / 2
	local sideLength = radius
	for index = 1, 6 do
		local yaw = math.rad((index - 1) * 60 + 30)
		local dir = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
		local pos = center + dir * (apothem / 2)
		local cf = if inverted
			then CFrame.new(pos) * CFrame.Angles(0, yaw + math.pi, 0) * CFrame.Angles(math.pi, 0, 0)
			else CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		local wedge = PartFactory.part(parent, prefix .. "_" .. index, {
			Shape = Enum.PartType.Wedge,
			Size = Vector3.new(sideLength, height, apothem),
			CFrame = cf,
			Color = color,
			Material = material,
			Solid = false,
		})
		if transparency and transparency > 0 then
			wedge.Transparency = transparency
		end
		if tint then
			wedge:SetAttribute("Tint", tint)
		end
	end
end

-- Anillo circular de segmentos (horizontal o inclinado según `ringCFrame`).
local function buildRing(
	parent: Instance,
	prefix: string,
	ringCFrame: CFrame,
	radius: number,
	count: number,
	thickness: Vector2,
	color: Color3,
	material: Enum.Material,
	tint: string?
)
	local length = 2 * math.pi * radius / count * 1.04
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local part = PartFactory.part(parent, prefix .. "_" .. index, {
			Size = Vector3.new(thickness.X, thickness.Y, length),
			CFrame = ringCFrame * CFrame.Angles(0, -angle, 0) * CFrame.new(radius, 0, 0),
			Color = color,
			Material = material,
			Solid = false,
		})
		if tint then
			part:SetAttribute("Tint", tint)
		end
	end
end

-- Plataforma y Plinto Emisor (cristal-renacimiento.obj) ------------------------------

local function buildPlatform(model: Model, origin: Vector3): BasePart
	-- DaisLip (diámetro 31, altura 0.4) y Dais (diámetro 30, altura 0.8)
	PartFactory.verticalCylinder(model, "DaisLip", origin + Vector3.new(0, 0.2, 0), 0.4, GeneratorConfig.PlatformDiameter + 1, MtlColors.DarkStone, Enum.Material.Slate, true)
	local dais = PartFactory.verticalCylinder(model, "Dais", origin + Vector3.new(0, PLATFORM_HEIGHT / 2, 0), PLATFORM_HEIGHT, GeneratorConfig.PlatformDiameter, MtlColors.WarmStone, Enum.Material.Slate, true)
	-- Tier central (diámetro 9, altura 0.35)
	PartFactory.verticalCylinder(model, "Tier", origin + Vector3.new(0, PLATFORM_HEIGHT + TIER_HEIGHT / 2, 0), TIER_HEIGHT, 9, MtlColors.WarmStone, Enum.Material.Slate, true)

	-- 24 runas radiales sobre la plataforma (Rune1..Rune24 en el OBJ)
	for index = 1, 24 do
		local angle = (index - 0.5) / 24 * 360
		local position = polar(origin, angle, 10.5, PLATFORM_HEIGHT + 0.03)
		local rune = PartFactory.part(model, "Rune" .. index, {
			Size = Vector3.new(0.18, 0.05, 1.6),
			CFrame = CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z)) * CFrame.Angles(0, math.rad(90), 0),
			Color = MtlColors.Runes,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		rune:SetAttribute("Tint", "Runes")
	end

	-- RuneInlay: anillo rúnico en el estrado (r = 3.70, y = 1.17)
	buildRing(
		model,
		"RuneInlay",
		CFrame.new(origin + Vector3.new(0, TIER_TOP + 0.02, 0)),
		3.70,
		24,
		Vector2.new(0.24, 0.14),
		MtlColors.Runes,
		Enum.Material.Neon,
		"Runes"
	)

	-- Plinth, PlinthCap, Emitter y EmitterGlow (hexágonos concéntricos sobre el Tier)
	hexPrism(model, "CenterPlinth", CFrame.new(origin + Vector3.new(0, 1.50, 0)), 2.80, 0.70, MtlColors.DarkStone, Enum.Material.Slate)
	hexPrism(model, "CenterPlinthCap", CFrame.new(origin + Vector3.new(0, 1.975, 0)), 2.30, 0.25, MtlColors.WarmStone, Enum.Material.Slate)
	hexPrism(model, "Emitter", CFrame.new(origin + Vector3.new(0, 2.25, 0)), 1.10, 0.30, MtlColors.Gold, Enum.Material.Metal)
	hexPrism(model, "EmitterGlow", CFrame.new(origin + Vector3.new(0, 2.43, 0)), 0.55, 0.06, MtlColors.Core, Enum.Material.Neon, 0, "Core")

	-- 6 garras doradas con puntas rúnicas alrededor del emisor (ProngLow1..6 y ProngTip1..6)
	for index = 1, 6 do
		local angle = (index - 1) * 60 + 30
		local radians = math.rad(angle)
		local dir = Vector3.new(math.cos(radians), 0, math.sin(radians))
		local lowPos = origin + dir * 2.15 + Vector3.new(0, 2.60, 0)
		local tipPos = origin + dir * 2.35 + Vector3.new(0, 3.30, 0)
		PartFactory.part(model, "ProngLow" .. index, {
			Size = Vector3.new(0.30, 1.15, 0.30),
			CFrame = CFrame.lookAt(lowPos, tipPos) * CFrame.Angles(math.rad(-90), 0, 0),
			Color = MtlColors.Gold,
			Material = Enum.Material.Metal,
			Solid = false,
		})
		local tip = PartFactory.part(model, "ProngTip" .. index, {
			Size = Vector3.new(0.32, 0.32, 0.32),
			CFrame = CFrame.new(tipPos) * CFrame.Angles(math.rad(45), math.rad(angle), math.rad(35.264)),
			Color = MtlColors.Runes,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		tip:SetAttribute("Tint", "Runes")
	end

	-- 3 manchas de musgo junto al plinto (PlinthMoss1..3 en el OBJ)
	for index, spec in {
		{ 20, 2.60, Vector3.new(2.27, 0.44, 1.56) },
		{ 150, 2.70, Vector3.new(1.83, 0.44, 1.44) },
		{ 260, 2.60, Vector3.new(1.71, 0.44, 2.76) },
	} do
		local pos = polar(origin, spec[1], spec[2], 1.20)
		PartFactory.ellipsoid(model, "PlinthMoss" .. index, CFrame.new(pos) * CFrame.Angles(0, math.rad(spec[1]), 0), spec[3], MtlColors.Moss, Enum.Material.LeafyGrass)
	end

	-- Haz de energía central (Beam) y sus 2 anillos (BeamRing1, BeamRing2)
	local beam = PartFactory.verticalCylinder(model, "Beam", origin + Vector3.new(0, 4.725, 0), 4.55, 0.90, MtlColors.EnergyBeam, Enum.Material.Neon, false)
	beam.Transparency = 0.72
	beam:SetAttribute("Tint", "Core")

	buildRing(model, "BeamRing1", CFrame.new(origin + Vector3.new(0, 3.60, 0)), 1.10, 12, Vector2.new(0.18, 0.10), MtlColors.Runes, Enum.Material.Neon, "Runes")
	buildRing(model, "BeamRing2", CFrame.new(origin + Vector3.new(0, 5.40, 0)), 0.80, 12, Vector2.new(0.16, 0.10), MtlColors.Runes, Enum.Material.Neon, "Runes")

	return dais
end

-- Raíces ------------------------------------------------------------------------------

type RootPoint = { Radius: number, Height: number, Diameter: number }

local BASE_ROOT_PROFILE: { RootPoint } = {
	{ Radius = 12.6, Height = PLATFORM_HEIGHT + 0.25, Diameter = 1.3 },
	{ Radius = 14.6, Height = 0.7, Diameter = 1.1 },
	{ Radius = 16.4, Height = 0.1, Diameter = 0.85 },
	{ Radius = 17.8, Height = -0.6, Diameter = 0.6 },
}

local GROWTH_ROOT_PROFILE: { RootPoint } = {
	{ Radius = 11.8, Height = PLATFORM_HEIGHT + 0.45, Diameter = 1.7 },
	{ Radius = 14.2, Height = 1, Diameter = 1.4 },
	{ Radius = 16.6, Height = 0.2, Diameter = 1 },
	{ Radius = 18, Height = -0.6, Diameter = 0.7 },
}

local function buildRoot(parent: Instance, prefix: string, origin: Vector3, angle: number, bendSign: number, profile: { RootPoint }): { Part }
	local radians = math.rad(angle)
	local direction = Vector3.new(math.cos(radians), 0, math.sin(radians))
	local side = Vector3.new(-direction.Z, 0, direction.X) * 0.8 * bendSign

	local points = {}
	for step, point in profile do
		local bend = if step == 2 or step == 3 then side else Vector3.zero
		points[step] = origin + direction * point.Radius + bend + Vector3.new(0, point.Height, 0)
	end

	local parts = {}
	for step = 1, #points - 1 do
		local diameter = profile[step].Diameter
		table.insert(parts, segment(parent, prefix .. "_" .. step, points[step], points[step + 1], diameter, Colors.Root, Enum.Material.Wood))
		table.insert(parts, PartFactory.part(parent, prefix .. "Knot_" .. step, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * diameter,
			CFrame = CFrame.new(points[step]),
			Color = Colors.Root,
			Material = Enum.Material.Wood,
			Solid = false,
		}))
	end
	return parts
end

local function buildRoots(model: Model, _origin: Vector3)
	local roots = Instance.new("Model")
	roots.Name = "Roots"
	roots.Parent = model
end

-- Pilares -------------------------------------------------------------------------------

local function buildPillars(model: Model, origin: Vector3)
	local pillars = Instance.new("Model")
	pillars.Name = "Pillars"
	pillars.Parent = model
	local p1 = PartFactory.part(pillars, "Pillar1", {
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.2, 0)),
		Color = MtlColors.WarmStone,
		Material = Enum.Material.Slate,
	})
	p1.Transparency = 1
end

-- 5 gemas de cristal alrededor del plinto (ShardGem1..5 del OBJ)
local function buildCrystalCluster(model: Model, origin: Vector3)
	local specs = {
		{ 0, 14.2, 1.95 },
		{ 72, 19.6, 1.45 },
		{ 144, 15.9, 1.75 },
		{ 216, 21.5, 1.35 },
		{ 288, 12.6, 1.70 },
	}
	for index, spec in specs do
		local radians = math.rad(spec[1])
		local base = origin + Vector3.new(math.cos(radians) * 3.30, TIER_TOP, math.sin(radians) * 3.30)
		local height = spec[3]
		local gemCF = CFrame.new(base)
			* CFrame.Angles(0, -radians, 0)
			* CFrame.Angles(0, 0, math.rad(-spec[2]))
			* CFrame.new(0, height / 2, 0)
		hexPrism(model, "ShardGem" .. index, gemCF, 0.36, height * 0.72, MtlColors.Shards, Enum.Material.Glass, 0.15, "Shards")
		local tip = PartFactory.part(model, "ShardGemTip" .. index, {
			Size = Vector3.one * 0.48,
			CFrame = gemCF * CFrame.new(0, height * 0.36, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35.264)),
			Color = MtlColors.Shards,
			Material = Enum.Material.Glass,
			Solid = false,
		})
		tip.Transparency = 0.15
		tip:SetAttribute("Tint", "Shards")
	end
end

-- Cristal flotante (CrystalBody + anillos astronómicos del OBJ) -------------------------

local function buildCrystal(model: Model, origin: Vector3): Vector3
	local center = origin + Vector3.new(0, GeneratorConfig.CoreHeight, 0)
	local C = CFrame.new(center)
	local vertex = CFrame.Angles(math.rad(45), 0, math.rad(35.264))

	local body = PartFactory.folder(model, "CrystalBody")

	-- Cuerpo central hexagonal (CrystalBodyPrism: altura 2.60, radio 1.50)
	hexPrism(body, "CrystalBodyPrism", C, 1.50, 2.60, MtlColors.CrystalGlass, Enum.Material.Glass, 0.32)

	-- Punta superior piramidal (CrystalBodyTop: 2.60 a 6.40 sobre el centro -> 3.80 de alto)
	hexPyramid(body, "CrystalBodyTop", center + Vector3.new(0, 1.30 + 3.80 / 2, 0), 1.50, 3.80, false, MtlColors.CrystalGlass, Enum.Material.Glass, 0.32)

	-- Punta inferior piramidal (CrystalBodyBottom: -1.30 a -4.20 bajo el centro -> 2.90 de alto)
	hexPyramid(body, "CrystalBodyBottom", center + Vector3.new(0, -1.30 - 2.90 / 2, 0), 1.50, 2.90, true, MtlColors.CrystalGlass, Enum.Material.Glass, 0.32)

	-- Bandas doradas (GirdleTop y GirdleBottom) y remate superior (Capstone)
	hexPrism(body, "GirdleTop", C * CFrame.new(0, 1.30, 0), 1.62, 0.19, MtlColors.Gold, Enum.Material.Metal)
	hexPrism(body, "GirdleBottom", C * CFrame.new(0, -1.30, 0), 1.62, 0.19, MtlColors.Gold, Enum.Material.Metal)

	PartFactory.part(body, "Capstone", {
		Size = Vector3.new(0.50, 0.80, 0.50),
		CFrame = C * CFrame.new(0, 5.55, 0) * CFrame.Angles(0, math.rad(45), 0),
		Color = MtlColors.Gold,
		Material = Enum.Material.Metal,
		Solid = false,
	})

	-- 3 facetas oscuras (Facet1..3) y 3 venas luminosas (Vein1..3)
	for index, angle in { -90, 150, 30 } do
		local radians = math.rad(angle)
		local dir = Vector3.new(math.cos(radians), 0, math.sin(radians))
		local facetPos = center + dir * 1.31
		local facetCF = CFrame.lookAt(facetPos, center)
		local facet = PartFactory.part(body, "Facet" .. index, {
			Size = Vector3.new(1.48, 2.56, 0.04),
			CFrame = facetCF,
			Color = MtlColors.CrystalFacet,
			Material = Enum.Material.Glass,
			Solid = false,
		})
		facet.Transparency = 0.35

		local veinPos = center + dir * 1.34 + Vector3.new(0, 0.10, 0)
		local vein = PartFactory.part(body, "Vein" .. index, {
			Size = Vector3.new(0.07, 1.98, 0.03),
			CFrame = CFrame.lookAt(veinPos, Vector3.new(center.X, veinPos.Y, center.Z)) * CFrame.Angles(0, 0, math.rad(if index == 2 then -6 else 5)),
			Color = MtlColors.Runes,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		vein:SetAttribute("Tint", "Runes")
	end

	-- 2 brotes de cristal laterales (BudGem1, BudGem2 y sus núcleos BudCore1, BudCore2)
	for index, bud in {
		{ Offset = Vector3.new(-1.05, 0.80, 0.49), Tilt = CFrame.Angles(math.rad(-12), math.rad(25), math.rad(22)), Height = 2.10 },
		{ Offset = Vector3.new(0.87, 1.48, -0.41), Tilt = CFrame.Angles(math.rad(10), math.rad(-25), math.rad(-20)), Height = 2.15 },
	} do
		local budCF = C * CFrame.new(bud.Offset) * bud.Tilt
		hexPrism(body, "BudGem" .. index, budCF, 0.48, bud.Height, MtlColors.CrystalGlass, Enum.Material.Glass, 0.32, "Shards")
		local budCore = PartFactory.part(body, "BudCore" .. index, {
			Size = Vector3.new(0.45, 0.85, 0.45),
			CFrame = budCF,
			Color = MtlColors.Core,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		budCore:SetAttribute("Tint", "Core")
	end

	-- 2 anillos astronómicos dorados (RingBand1 y RingBand2) con 4 nodos rúnicos cada uno
	local ringSpecs = {
		{
			Name = "RingBand1",
			NodePrefix = "RingNode1_",
			Radius = 3.30,
			Tilt = C * CFrame.Angles(math.rad(-16.3), math.rad(7.5), math.rad(2.4)),
		},
		{
			Name = "RingBand2",
			NodePrefix = "RingNode2_",
			Radius = 3.90,
			Tilt = C * CFrame.Angles(math.rad(12.6), math.rad(-14.2), math.rad(-61.8)),
		},
	}
	for _, spec in ringSpecs do
		buildRing(body, spec.Name, spec.Tilt, spec.Radius, 16, Vector2.new(0.14, 0.14), MtlColors.Gold, Enum.Material.Metal)
		for nodeIndex = 1, 4 do
			local angle = (nodeIndex - 1) * math.pi / 2
			local nodePos = spec.Tilt * Vector3.new(math.cos(angle) * spec.Radius, 0, math.sin(angle) * spec.Radius)
			local node = PartFactory.part(body, spec.NodePrefix .. nodeIndex, {
				Size = Vector3.one * 0.28,
				CFrame = CFrame.new(nodePos) * vertex,
				Color = MtlColors.Runes,
				Material = Enum.Material.Neon,
				Solid = false,
			})
			node:SetAttribute("Tint", "Runes")
		end
	end

	-- Núcleo luminoso interior (Core) y halo de energía (Shell)
	local core = PartFactory.part(model, "Core", {
		Size = Vector3.one * GeneratorConfig.CoreSize,
		CFrame = C * vertex,
		Color = MtlColors.Core,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	core:SetAttribute("Tint", "Core")

	local shell = PartFactory.part(model, "Shell", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * GeneratorConfig.ShellDiameter,
		CFrame = C,
		Color = Colors.EnergySoft,
		Material = Enum.Material.ForceField,
		Solid = false,
	})
	shell:SetAttribute("Tint", "Shell")

	-- Única luz dinámica del santuario (la pulsa GeneratorAnimator).
	local light = Instance.new("PointLight")
	light.Color = Colors.Turquoise
	light.Range = GeneratorConfig.LightRange
	light.Brightness = GeneratorConfig.Animation.LightBaseBrightness
	light.Shadows = false
	light:SetAttribute("Tint", "Light")
	light.Parent = core

	-- Motas de luz del núcleo; el cliente también las usa para la ráfaga de compra.
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(Colors.EnergySoft, Colors.Violet)
	particles.LightEmission = 1
	particles.LightInfluence = 0
	particles.Rate = 4
	particles.Lifetime = NumberRange.new(1.2, 2)
	particles.Speed = NumberRange.new(1, 2.2)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Size = NumberSequence.new(0.3, 0)
	particles.Transparency = NumberSequence.new(0.1, 1)
	particles:SetAttribute("Tint", "Particles")
	particles:SetAttribute("StageRate", true)
	particles.Parent = core

	return center
end

-- Fragmentos en órbita (los mueve GeneratorAnimator con GeneratorConfig.orbitOffset).
local function buildOrbiters(model: Model, center: Vector3)
	local orbiters = PartFactory.folder(model, "Orbiters")
	for index = 1, GeneratorConfig.OrbiterCount do
		local orbit = GeneratorConfig.Orbits[index]
		local x, y, z = GeneratorConfig.orbitOffset(orbit, 0)
		local fragment = PartFactory.part(orbiters, "Orbiter" .. index, {
			Size = orbit.Size,
			CFrame = CFrame.new(center + Vector3.new(x, y, z)) * CFrame.Angles(math.rad(20), 0, math.rad(15)),
			Color = MtlColors.Shards,
			Material = Enum.Material.Glass,
			Solid = false,
		})
		fragment.Transparency = 0.15
		fragment.Reflectance = 0.1
		fragment:SetAttribute("Tint", "Shards")
	end
end

-- Rocas pequeñas que flotan junto a los pilares (las balancea GeneratorAnimator).
local function buildFloatingRocks(model: Model, origin: Vector3)
	local rocks = PartFactory.folder(model, "FloatingRocks")
	for index, spec in { { 40, 13.4, 6.2, 1 }, { 140, 13.6, 6, 0.9 }, { 222, 13.4, 6.4, 1.1 }, { 248, 13.2, 5.9, 0.8 }, { 292, 13.5, 6.3, 1 }, { 318, 13.3, 6, 0.9 } } do
		local size = spec[4]
		local rock = PartFactory.part(rocks, "Rock" .. index, {
			Size = Vector3.new(size, size * 0.75, size * 0.9),
			CFrame = CFrame.new(polar(origin, spec[1], spec[2], spec[3])) * CFrame.Angles(math.rad(spec[1]), math.rad(spec[1] * 2), 0),
			Color = if index % 2 == 0 then MtlColors.DarkStone else MtlColors.WarmStone,
			Material = Enum.Material.Slate,
			Solid = false,
		})
		rock.Transparency = 1
	end
end

-- Motas que ascienden desde la plataforma (un único emisor, ritmo bajo).
local function buildAmbientMotes(model: Model, origin: Vector3)
	local source = PartFactory.part(model, "AmbientMotes", {
		Size = Vector3.new(22, 0.2, 22),
		CFrame = CFrame.new(origin + Vector3.new(0, PLATFORM_HEIGHT + 0.2, 0)),
		Color = Colors.Stone,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	source.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 3
	emitter.Lifetime = NumberRange.new(2.5, 4)
	emitter.Speed = NumberRange.new(0.6, 1.3)
	emitter.Acceleration = Vector3.new(0, 1, 0)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Size = NumberSequence.new(0.2, 0)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Color = ColorSequence.new(Colors.EnergySoft, Colors.Violet)
	emitter:SetAttribute("Tint", "Particles")
	emitter.Parent = source
end

-- Detalles de etapa -----------------------------------------------------------------

local function hideDetail(part: BasePart, visibleTransparency: number?, tint: string?)
	part:SetAttribute("VisibleTransparency", visibleTransparency or 0)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	if tint then
		part:SetAttribute("Tint", tint)
	end
end

local function detailGroup(parent: Instance, name: string): Model
	local group = Instance.new("Model")
	group.Name = name
	group.Parent = parent
	return group
end

local function emitterSource(parent: Instance, name: string, cframe: CFrame, size: Vector3): Part
	local source = PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = Colors.Stone,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	hideDetail(source, 1)
	return source
end

local function stageEmitter(parent: Instance, settings: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	for key, value in settings do
		(emitter :: any)[key] = value
	end
	emitter:SetAttribute("Tint", "Particles")
	emitter.Parent = parent
	return emitter
end

local function segmentRing(parent: Instance, prefix: string, center: Vector3, radius: number, count: number, thickness: Vector2)
	local length = 2 * math.pi * radius / count * 0.92
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local position = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local part = PartFactory.part(parent, prefix .. index, {
			Size = Vector3.new(length, thickness.Y, thickness.X),
			CFrame = CFrame.lookAt(position, center),
			Color = Colors.Energy,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		hideDetail(part, 0, "Runes")
	end
end

local function buildStageDetails(model: Model, origin: Vector3, coreCenter: Vector3)
	local details = PartFactory.folder(model, "StageDetails")
	local evolution = GeneratorConfig.Evolution

	local growth = detailGroup(details, "GrowthRoots")
	for index, angle in { -70, -110, 180 } do
		for _, part in buildRoot(growth, "GrowthRoot" .. index, origin, angle, if index % 2 == 0 then 1 else -1, GROWTH_ROOT_PROFILE) do
			hideDetail(part)
		end
	end

	local glyphs = detailGroup(details, "RuneGlyphs")
	for index = 1, 12 do
		local angle = math.rad((index - 0.5) * 30)
		local position = origin + Vector3.new(math.cos(angle) * (PLATFORM_RADIUS + 0.03), PLATFORM_HEIGHT / 2, math.sin(angle) * (PLATFORM_RADIUS + 0.03))
		local glyph = PartFactory.part(glyphs, "Glyph" .. index, {
			Size = Vector3.new(1, 0.45, 0.06),
			CFrame = CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z)),
			Color = Colors.Energy,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		hideDetail(glyph, 0, "Runes")
	end

	local sparkles = detailGroup(details, "RuneSparkles")
	local sparkleSource = emitterSource(sparkles, "Source", CFrame.new(origin + Vector3.new(0, PLATFORM_HEIGHT + 0.2, 0)), Vector3.new(18, 0.2, 18))
	stageEmitter(sparkleSource, {
		Rate = 6,
		Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(0.8, 1.6),
		Acceleration = Vector3.new(0, 1.2, 0),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new(0.18, 0),
		Transparency = NumberSequence.new(0.2, 1),
	})

	local fragments = detailGroup(details, "Fragments")
	for index = 1, evolution.FragmentCount do
		local angle = (index - 1) / evolution.FragmentCount * math.pi * 2
		local fragment = PartFactory.part(fragments, "Fragment" .. index, {
			Size = Vector3.new(0.4, 1.1, 0.4),
			CFrame = CFrame.new(coreCenter + Vector3.new(math.cos(angle) * evolution.FragmentOrbitRadius, evolution.FragmentHeight, math.sin(angle) * evolution.FragmentOrbitRadius)),
			Color = Colors.Energy,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		hideDetail(fragment, 0, "Runes")
	end

	local spires = detailGroup(details, "LegendarySpires")
	for index, spire in { { 20, 5.4 }, { 160, 6 }, { 200, 5.6 }, { 340, 6.2 } } do
		local radians = math.rad(spire[1])
		local height = spire[2]
		local base = origin + Vector3.new(math.cos(radians) * 8.2, PLATFORM_HEIGHT, math.sin(radians) * 8.2)
		local part = PartFactory.part(spires, "Spire" .. index, {
			Size = Vector3.new(1, height, 1),
			CFrame = CFrame.new(base)
				* CFrame.Angles(0, -radians, 0)
				* CFrame.Angles(0, 0, math.rad(-14))
				* CFrame.new(0, height / 2 - 0.3, 0)
				* CFrame.Angles(0, math.rad(45), 0),
			Color = Colors.Crystal,
			Material = Enum.Material.Glass,
			Solid = false,
		})
		hideDetail(part, 0.1, "Shards")
	end

	segmentRing(detailGroup(details, "LegendaryHalo"), "Halo", coreCenter + Vector3.new(0, GeneratorConfig.CrystalHeight / 2 + 0.9, 0), 3, 12, Vector2.new(0.15, 0.15))
	segmentRing(detailGroup(details, "LegendaryFloorRing"), "FloorRune", origin + Vector3.new(0, PLATFORM_HEIGHT + 0.06, 0), 14, 32, Vector2.new(0.3, 0.06))

	local aura = detailGroup(details, "LegendaryAura")
	local auraSource = emitterSource(aura, "Source", CFrame.new(coreCenter), Vector3.one * 5)
	stageEmitter(auraSource, {
		Rate = 6,
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(0.4, 1),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.45),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new(0.1, 1),
		RotSpeed = NumberRange.new(-90, 90),
	})
end

local function buildNameplate(model: Model, labelPosition: Vector3)
	local anchor = PartFactory.part(model, "LabelAnchor", {
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(labelPosition),
		Color = Colors.Stone,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	anchor.Transparency = 1

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.new(12, 0, 1.8, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 100
	billboard.Adornee = anchor

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(16, 40, 36)
	frame.BackgroundTransparency = 0.2
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Colors.Turquoise
	stroke.Thickness = 2
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.9, 0.7)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 244, 214)
	label.Text = "★ " .. GeneratorConfig.DisplayName .. " ★"
	label.Parent = frame

	billboard.Parent = anchor
end

function GeneratorService.start()
	PartFactory.removeExisting(workspace, GeneratorConfig.ModelName)

	local origin = GeneratorConfig.Position
	local model = Instance.new("Model")
	model.Name = GeneratorConfig.ModelName
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local dais = buildPlatform(model, origin)
	buildRoots(model, origin)
	buildPillars(model, origin)
	buildCrystalCluster(model, origin)
	local coreCenter = buildCrystal(model, origin)
	buildOrbiters(model, coreCenter)
	buildFloatingRocks(model, origin)
	buildAmbientMotes(model, origin)
	buildStageDetails(model, origin, coreCenter)
	buildNameplate(model, coreCenter + Vector3.new(0, GeneratorConfig.CrystalHeight / 2 + 2.6, 0))

	model.PrimaryPart = dais
	model.Parent = workspace
end

return GeneratorService
