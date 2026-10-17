-- Construye el Cristal del Renacimiento con el diseño del Santuario del Núcleo Cósmico:
-- plataforma circular de piedra antigua con musgo y runas, cuatro pilares bajos con
-- raíces, un cristal oscuro facetado que flota con energía turquesa en su interior, tres
-- fragmentos en órbita, rocas flotantes y motas de luz que ascienden.
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

local PLATFORM_HEIGHT = GeneratorConfig.PlatformHeight
local PLATFORM_RADIUS = GeneratorConfig.PlatformDiameter / 2
local TIER_HEIGHT = 0.35
local TIER_TOP = PLATFORM_HEIGHT + TIER_HEIGHT

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

-- Plataforma -------------------------------------------------------------------------

local function buildPlatform(model: Model, origin: Vector3): BasePart
	-- Borde inferior algo más ancho y bajo: un escalón suave en todo el contorno.
	PartFactory.verticalCylinder(model, "DaisLip", origin + Vector3.new(0, 0.2, 0), 0.4, GeneratorConfig.PlatformDiameter + 1, Colors.DarkStone, Enum.Material.Slate, true)
	local dais = PartFactory.verticalCylinder(model, "Dais", origin + Vector3.new(0, PLATFORM_HEIGHT / 2, 0), PLATFORM_HEIGHT, GeneratorConfig.PlatformDiameter, Colors.WarmStone, Enum.Material.Slate, true)
	-- Estrado central bajo el cristal
	PartFactory.verticalCylinder(model, "Tier", origin + Vector3.new(0, PLATFORM_HEIGHT + TIER_HEIGHT / 2, 0), TIER_HEIGHT, 9, Colors.Stone, Enum.Material.Cobblestone, true)

	-- Runas discretas: un anillo de trazos y ocho glifos hacia el borde.
	for index = 1, 24 do
		local angle = (index - 0.5) / 24 * 360
		local position = polar(origin, angle, 10.5, PLATFORM_HEIGHT + 0.03)
		local rune = PartFactory.part(model, "Rune" .. index, {
			Size = Vector3.new(0.18, 0.05, 1.6),
			CFrame = CFrame.lookAt(position, Vector3.new(origin.X, position.Y, origin.Z)) * CFrame.Angles(0, math.rad(90), 0),
			Color = Colors.Turquoise,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		rune.Transparency = 0.3
		rune:SetAttribute("Tint", "Runes")
	end
	for index = 1, 8 do
		local angle = (index - 1) / 8 * 360 + 22.5
		local position = polar(origin, angle, 13.4, PLATFORM_HEIGHT + 0.03)
		local glyph = PartFactory.part(model, "Glyph" .. index, {
			Size = Vector3.new(0.7, 0.05, 0.7),
			CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(angle + 45), 0),
			Color = Colors.Turquoise,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		glyph.Transparency = 0.35
		glyph:SetAttribute("Tint", "Runes")
	end

	-- Musgo sobre la piedra (manchas planas, sin colisión)
	for index, spec in { { 15, 12.6, 3.4 }, { 80, 13.6, 2.6 }, { 165, 12.9, 3 }, { 200, 13.8, 2.4 }, { 250, 12.4, 3.6 }, { 290, 13.5, 2.8 }, { 340, 12.2, 3.2 }, { 110, 7.2, 2 }, { 300, 6.8, 2.2 } } do
		local position = polar(origin, spec[1], spec[2], PLATFORM_HEIGHT + 0.05)
		PartFactory.ellipsoid(model, "Moss" .. index, CFrame.new(position) * CFrame.Angles(0, math.rad(spec[1] * 1.7), 0), Vector3.new(spec[3], 0.25, spec[3] * 0.6), Colors.DeepGreen, Enum.Material.LeafyGrass)
	end
	return dais
end

-- Raíces ------------------------------------------------------------------------------

type RootPoint = { Radius: number, Height: number, Diameter: number }

-- Raíces que salen de debajo del borde de la plataforma y se hunden en la tierra.
local BASE_ROOT_PROFILE: { RootPoint } = {
	{ Radius = 12.6, Height = PLATFORM_HEIGHT + 0.25, Diameter = 1.3 },
	{ Radius = 14.6, Height = 0.7, Diameter = 1.1 },
	{ Radius = 16.4, Height = 0.1, Diameter = 0.85 },
	{ Radius = 17.8, Height = -0.6, Diameter = 0.6 },
}

-- Raíces de crecimiento (etapa Esmeralda en adelante): más gruesas.
local GROWTH_ROOT_PROFILE: { RootPoint } = {
	{ Radius = 11.8, Height = PLATFORM_HEIGHT + 0.45, Diameter = 1.7 },
	{ Radius = 14.2, Height = 1, Diameter = 1.4 },
	{ Radius = 16.6, Height = 0.2, Diameter = 1 },
	{ Radius = 18, Height = -0.6, Diameter = 0.7 },
}

-- Una raíz: tramos de cilindro con nudos en los codos. Devuelve sus piezas.
local function buildRoot(parent: Instance, prefix: string, origin: Vector3, angle: number, bendSign: number, profile: { RootPoint }): { Part }
	local radians = math.rad(angle)
	local direction = Vector3.new(math.cos(radians), 0, math.sin(radians))
	local side = Vector3.new(-direction.Z, 0, direction.X) * 0.8 * bendSign

	local points = {}
	for step, point in profile do
		-- Pequeña curva lateral en el tramo central para que no parezcan rectas.
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

-- Ángulos elegidos para no invadir los santuarios de huevos, el spawn ni el camino (+Z).
local function buildRoots(model: Model, origin: Vector3)
	local roots = Instance.new("Model")
	roots.Name = "Roots"
	roots.Parent = model
	for rootIndex, angle in { -35, -145, 15, 195 } do
		buildRoot(roots, "Root" .. rootIndex, origin, angle, if rootIndex % 2 == 0 then 1 else -1, BASE_ROOT_PROFILE)
	end
end

-- Pilares -------------------------------------------------------------------------------

-- Cuatro pilares bajos en diagonal, envueltos por raíces, con una runa hacia el cristal.
local function buildPillars(model: Model, origin: Vector3)
	local pillars = Instance.new("Model")
	pillars.Name = "Pillars"
	pillars.Parent = model
	for index, angle in GeneratorConfig.PillarAngles do
		local base = polar(origin, angle, GeneratorConfig.PillarRadius, PLATFORM_HEIGHT)
		local facing = CFrame.lookAt(base, Vector3.new(origin.X, base.Y, origin.Z))
		local height = if index % 2 == 0 then 4.2 else 3.6
		local lean = CFrame.Angles(math.rad(if index % 2 == 0 then 3 else -2), 0, math.rad(if index <= 2 then 2 else -3))

		PartFactory.part(pillars, "Plinth" .. index, {
			Size = Vector3.new(2.9, 0.6, 2.9),
			CFrame = facing * CFrame.new(0, 0.3, 0),
			Color = Colors.DarkStone,
			Material = Enum.Material.Slate,
		})
		local shaft = facing * lean * CFrame.new(0, 0.6 + height / 2, 0)
		PartFactory.part(pillars, "Pillar" .. index, {
			Size = Vector3.new(2.1, height, 2.1),
			CFrame = shaft,
			Color = Colors.WarmStone,
			Material = Enum.Material.Slate,
		})
		local capTop = shaft * CFrame.new(0, height / 2 + 0.25, 0)
		PartFactory.part(pillars, "Cap" .. index, {
			Size = Vector3.new(2.6, 0.5, 2.6),
			CFrame = capTop,
			Color = Colors.DarkStone,
			Material = Enum.Material.Slate,
		})
		PartFactory.ellipsoid(pillars, "CapMoss" .. index, capTop * CFrame.new(0.2, 0.3, 0.1), Vector3.new(2.3, 0.45, 1.8), Colors.DeepGreen, Enum.Material.LeafyGrass)
		-- Runa vertical en la cara que mira al cristal
		local rune = PartFactory.part(pillars, "PillarRune" .. index, {
			Size = Vector3.new(0.22, height * 0.55, 0.05),
			CFrame = shaft * CFrame.new(0, 0.1, -1.08),
			Color = Colors.Turquoise,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		rune:SetAttribute("Tint", "Runes")
		-- Raíces que trepan por el pilar desde la plataforma
		for rootIndex, side in { -1, 1 } do
			local low = (facing * CFrame.new(side * 1.25, 0.3, 0.6)).Position
			local mid = (shaft * CFrame.new(side * 1.05, 0.2, 0.9)).Position
			local high = (shaft * CFrame.new(side * 0.5, height / 2 - 0.2, 1.05)).Position
			segment(pillars, ("PillarRoot%d_%d_1"):format(index, rootIndex), low, mid, 0.45, Colors.Root, Enum.Material.Wood)
			segment(pillars, ("PillarRoot%d_%d_2"):format(index, rootIndex), mid, high, 0.35, Colors.Root, Enum.Material.Wood)
		end
	end
end

-- Pequeño racimo de cristales sobre el estrado central, bajo el cristal flotante.
local function buildCrystalCluster(model: Model, origin: Vector3)
	for index, shard in { { 0, 18, 1.8 }, { 72, 24, 1.3 }, { 144, 20, 1.6 }, { 216, 26, 1.2 }, { 288, 16, 1.5 } } do
		local radians = math.rad(shard[1])
		local base = origin + Vector3.new(math.cos(radians) * 1.6, TIER_TOP, math.sin(radians) * 1.6)
		local height = shard[3]
		local crystal = PartFactory.part(model, "Shard" .. index, {
			Size = Vector3.new(0.6, height, 0.6),
			CFrame = CFrame.new(base)
				* CFrame.Angles(0, -radians, 0)
				* CFrame.Angles(0, 0, math.rad(-shard[2]))
				* CFrame.new(0, height / 2 - 0.2, 0)
				* CFrame.Angles(0, math.rad(45), 0),
			Color = Colors.Crystal,
			Material = Enum.Material.Glass,
			Solid = false,
		})
		crystal.Transparency = 0.15
		crystal:SetAttribute("Tint", "Shards")
	end
end

-- Cristal flotante -----------------------------------------------------------------------

-- Exterior oscuro y facetado (varias piezas cruzadas de cristal translúcido) con el
-- núcleo luminoso dentro, grietas de energía y un halo. Todo flota y gira junto.
local function buildCrystal(model: Model, origin: Vector3): Vector3
	local center = origin + Vector3.new(0, GeneratorConfig.CoreHeight, 0)
	local C = CFrame.new(center)
	local vertex = CFrame.Angles(math.rad(45), 0, math.rad(35.26)) -- cubo apoyado en un vértice

	local body = PartFactory.folder(model, "CrystalBody")
	local function facet(name: string, size: Vector3, cframe: CFrame)
		local part = PartFactory.part(body, name, {
			Size = size,
			CFrame = cframe,
			Color = Colors.CrystalDark,
			Material = Enum.Material.Glass,
			Solid = false,
		})
		part.Transparency = 0.22
		part.Reflectance = 0.12
		return part
	end
	-- Silueta irregular: dos columnas cruzadas, punta superior larga, punta inferior más
	-- corta y dos espolones laterales.
	facet("ShaftMain", Vector3.new(2.8, 5.6, 2.8), C * CFrame.Angles(0, math.rad(45), math.rad(4)))
	facet("ShaftSide", Vector3.new(2, 4.4, 2), C * CFrame.new(0.7, -0.4, 0.3) * CFrame.Angles(math.rad(8), math.rad(20), math.rad(-10)))
	facet("TipTop", Vector3.one * 2.6, C * CFrame.new(0, 2.9, 0) * CFrame.Angles(0, math.rad(10), 0) * vertex)
	facet("TipBottom", Vector3.one * 2.2, C * CFrame.new(0.1, -2.75, 0) * CFrame.Angles(0, math.rad(-15), 0) * vertex)
	facet("SpurA", Vector3.new(1, 3, 1), C * CFrame.new(1.6, 1, -0.8) * CFrame.Angles(math.rad(10), math.rad(30), math.rad(-25)))
	facet("SpurB", Vector3.new(0.8, 2.4, 0.8), C * CFrame.new(-1.5, -1.2, 0.9) * CFrame.Angles(math.rad(15), 0, math.rad(30)))

	-- Grietas de energía: finas líneas de neón sobre las caras.
	for index, spec in { { 45, 1.42, 0.6, 2.2, 8 }, { 135, 1.42, -0.8, 1.8, -12 }, { 225, 1.42, 1.4, 1.5, 18 }, { 315, 1.42, -1.6, 2, -6 }, { 80, 1.3, 2.6, 1.2, 25 } } do
		local radians = math.rad(spec[1])
		local position = center + Vector3.new(math.cos(radians) * spec[2], spec[3], math.sin(radians) * spec[2])
		local crack = PartFactory.part(body, "Crack" .. index, {
			Size = Vector3.new(0.07, spec[4], 0.07),
			CFrame = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)) * CFrame.Angles(0, 0, math.rad(spec[5])),
			Color = Colors.Turquoise,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		crack.Transparency = 0.15
		crack:SetAttribute("Tint", "Runes")
	end

	-- Núcleo luminoso interior (se ve a través del cristal oscuro).
	local core = PartFactory.part(model, "Core", {
		Size = Vector3.one * GeneratorConfig.CoreSize,
		CFrame = C * vertex,
		Color = Colors.Turquoise,
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
	particles:SetAttribute("StageRate", true) -- su ritmo depende de la etapa
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
			Color = Colors.Crystal,
			Material = Enum.Material.Glass,
			Solid = false,
		})
		fragment.Transparency = 0.1
		fragment.Reflectance = 0.1
		fragment:SetAttribute("Tint", "Shards")
	end
end

-- Rocas pequeñas que flotan junto a los pilares, por encima de la cabeza y fuera de los
-- accesos y del arco (las balancea GeneratorAnimator). { ángulo, radio, altura, tamaño }
local function buildFloatingRocks(model: Model, origin: Vector3)
	local rocks = PartFactory.folder(model, "FloatingRocks")
	for index, spec in { { 40, 13.4, 6.2, 1 }, { 140, 13.6, 6, 0.9 }, { 222, 13.4, 6.4, 1.1 }, { 248, 13.2, 5.9, 0.8 }, { 292, 13.5, 6.3, 1 }, { 318, 13.3, 6, 0.9 } } do
		local size = spec[4]
		PartFactory.part(rocks, "Rock" .. index, {
			Size = Vector3.new(size, size * 0.75, size * 0.9),
			CFrame = CFrame.new(polar(origin, spec[1], spec[2], spec[3])) * CFrame.Angles(math.rad(spec[1]), math.rad(spec[1] * 2), 0),
			Color = if index % 2 == 0 then Colors.DarkStone else Colors.WarmStone,
			Material = Enum.Material.Slate,
			Solid = false,
		})
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
	emitter:SetAttribute("Tint", "Particles") -- color de la etapa (ritmo fijo)
	emitter.Parent = source
end

-- Detalles de etapa -----------------------------------------------------------------
-- Todo se crea oculto. CrystalAppearance (cliente) los muestra con un fundido hasta
-- "VisibleTransparency" y enciende sus emisores cuando la etapa los incluye.

local function hideDetail(part: BasePart, visibleTransparency: number?, tint: string?)
	part:SetAttribute("VisibleTransparency", visibleTransparency or 0)
	part.Transparency = 1
	-- Ocultas no deben estorbar: los detalles nunca colisionan.
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

-- Pieza invisible que solo sirve de origen para un emisor de partículas.
local function emitterSource(parent: Instance, name: string, cframe: CFrame, size: Vector3): Part
	local source = PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = Colors.Stone,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	hideDetail(source, 1) -- sigue invisible aunque el grupo se muestre
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

-- Segmentos de neón formando un anillo horizontal (no hay toros nativos).
local function segmentRing(parent: Instance, prefix: string, center: Vector3, radius: number, count: number, thickness: Vector2)
	local length = 2 * math.pi * radius / count * 0.92
	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local position = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local part = PartFactory.part(parent, prefix .. index, {
			Size = Vector3.new(length, thickness.Y, thickness.X),
			-- Tangente al círculo: el eje X apunta en la dirección del recorrido.
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

	-- Esmeralda: raíces de crecimiento detrás y a un lado (sin tocar accesos ni santuarios).
	local growth = detailGroup(details, "GrowthRoots")
	for index, angle in { -70, -110, 180 } do
		for _, part in buildRoot(growth, "GrowthRoot" .. index, origin, angle, if index % 2 == 0 then 1 else -1, GROWTH_ROOT_PROFILE) do
			hideDetail(part)
		end
	end

	-- Esmeralda: glifos luminosos grabados en el canto de la plataforma.
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

	-- Esmeralda: chispas que suben desde la plataforma.
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

	-- Dorado: corona de chispas que gira bajo la punta inferior del cristal (la mueve
	-- GeneratorAnimator; queda lejos de las órbitas de los fragmentos).
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

	-- Legendario: agujas de cristal sobre la plataforma, entre el centro y los pilares.
	local spires = detailGroup(details, "LegendarySpires")
	for index, spire in { { 20, 5.4 }, { 160, 6 }, { 200, 5.6 }, { 340, 6.2 } } do
		local radians = math.rad(spire[1])
		local height = spire[2]
		local base = origin + Vector3.new(math.cos(radians) * 8.2, PLATFORM_HEIGHT, math.sin(radians) * 8.2)
		local part = PartFactory.part(spires, "Spire" .. index, {
			Size = Vector3.new(1, height, 1),
			CFrame = CFrame.new(base)
				* CFrame.Angles(0, -radians, 0)
				* CFrame.Angles(0, 0, math.rad(-14)) -- inclinada hacia fuera
				* CFrame.new(0, height / 2 - 0.3, 0)
				* CFrame.Angles(0, math.rad(45), 0),
			Color = Colors.Crystal,
			Material = Enum.Material.Glass,
			Solid = false,
		})
		hideDetail(part, 0.1, "Shards")
	end

	-- Legendario: halo sobre la punta del cristal y círculo de runas en la plataforma.
	segmentRing(detailGroup(details, "LegendaryHalo"), "Halo", coreCenter + Vector3.new(0, GeneratorConfig.CrystalHeight / 2 + 0.9, 0), 3, 12, Vector2.new(0.15, 0.15))
	segmentRing(detailGroup(details, "LegendaryFloorRing"), "FloorRune", origin + Vector3.new(0, PLATFORM_HEIGHT + 0.06, 0), 14, 32, Vector2.new(0.3, 0.06))

	-- Legendario: aura de destellos alrededor del cristal.
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
	-- Ancla invisible: el cristal se mueve, el cartel no debe hacerlo.
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
	billboard.Size = UDim2.new(12, 0, 1.8, 0) -- en studs: escala con la distancia
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
	label.Text = "✦ " .. GeneratorConfig.DisplayName .. " ✦"
	label.Parent = frame

	billboard.Parent = anchor
end

function GeneratorService.start()
	PartFactory.removeExisting(workspace, GeneratorConfig.ModelName)

	local origin = GeneratorConfig.Position
	local model = Instance.new("Model")
	model.Name = GeneratorConfig.ModelName
	-- Con StreamingEnabled, Persistent envía el modelo completo al entrar y nunca lo
	-- descarga del cliente. (Atomic permitía que el motor lo quitara entero del
	-- Workspace del cliente durante la partida.)
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
