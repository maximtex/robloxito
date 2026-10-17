-- Apariencia, posición y animación del Cristal del Renacimiento (el generador), con el
-- diseño del Santuario del Núcleo Cósmico: plataforma de piedra antigua con musgo y raíces,
-- cristal oscuro flotante con energía turquesa interna y tres fragmentos en órbita.
-- Solo afecta a lo visual; la producción la define EconomyConfig.
-- ModelName y la estructura (Core, Shell, CrystalBody, Orbiters, FloatingRocks y
-- StageDetails) los usan GeneratorAnimator y CrystalAppearance.

local GeneratorConfig = {
	ModelName = "EnergyGenerator",
	DisplayName = "Cristal del Renacimiento",

	-- Centro de la base y ORIGEN DE TODO EL MAPA (mundo, zonas, huevos y enemigos se
	-- colocan respecto a él): no se mueve. Y = 0.5 es la superficie del terreno.
	Position = Vector3.new(0, 0.5, -25),

	Colors = {
		-- Paleta del santuario
		Turquoise = Color3.fromRGB(32, 229, 209), -- #20E5D1 energía principal
		DeepGreen = Color3.fromRGB(22, 61, 53), -- #163D35 vegetación y contraste
		WarmStone = Color3.fromRGB(184, 167, 122), -- #B8A77A estructura antigua
		Violet = Color3.fromRGB(156, 140, 255), -- #9C8CFF acentos cósmicos
		CrystalDark = Color3.fromRGB(14, 38, 44), -- exterior oscuro del cristal
		-- Complementarios
		Stone = Color3.fromRGB(150, 140, 110),
		DarkStone = Color3.fromRGB(92, 88, 74),
		Root = Color3.fromRGB(96, 70, 48),
		Moss = Color3.fromRGB(22, 61, 53),
		Energy = Color3.fromRGB(32, 229, 209),
		EnergySoft = Color3.fromRGB(170, 255, 240),
		Crystal = Color3.fromRGB(110, 214, 200), -- también lo usa EggStandService: no cambiar
		Gold = Color3.fromRGB(244, 204, 110),
	},

	-- Santuario (medidas en studs). 30 de diámetro: lo máximo que cabe sin invadir el
	-- santuario del Huevo del Bosque (-20, 12) ni el arco en ruinas (Z = 17).
	PlatformDiameter = 30,
	PlatformHeight = 0.8, -- se sube andando (sin saltar)
	PillarRadius = 12.3, -- cuatro pilares bajos en diagonal: accesos libres
	PillarAngles = { 55, 125, 235, 305 }, -- desde +X hacia +Z (+Z = camino al spawn)

	-- Cristal flotante
	CoreHeight = 11.2, -- altura del CENTRO del cristal sobre el suelo (flota ~6 studs)
	CoreSize = 1.9, -- núcleo luminoso interior (cubo apoyado en un vértice)
	CrystalHeight = 9.6, -- altura total aproximada del cristal (de punta a punta)
	ShellDiameter = 6, -- halo de energía alrededor del cristal

	LightRange = 26,

	-- Fragmentos en órbita. Órbitas concéntricas (mismo centro) con radios separados más
	-- que la suma de sus medios tamaños: nunca se cruzan entre sí ni con el cristal.
	-- Tilt: inclinación del plano (grados); Node: dirección del eje de inclinación;
	-- Speed: radianes/s (signo = sentido); Phase: ángulo inicial; Spin: giro propio.
	OrbiterCount = 3,
	Orbits = {
		{ Radius = 6.6, Tilt = 22, Node = 0, Speed = 0.42, Phase = 0, Size = Vector3.new(0.9, 3.2, 0.9), Spin = 0.6 },
		{ Radius = 9.8, Tilt = -30, Node = 110, Speed = -0.31, Phase = 2.1, Size = Vector3.new(0.75, 2.6, 0.75), Spin = -0.8 },
		{ Radius = 12.4, Tilt = 10, Node = 230, Speed = 0.23, Phase = 4.2, Size = Vector3.new(0.6, 2, 0.6), Spin = 1 },
	},

	-- Animación local en cada cliente (no se replica por red).
	Animation = {
		CrystalSpinSpeed = 0.12, -- giro lento del cristal (rad/s)
		CoreBobHeight = 0.35, -- flotación del cristal
		CoreBobSpeed = 0.6,
		RockBobHeight = 0.3, -- rocas flotantes
		RockBobSpeed = 0.5,
		LightBaseBrightness = 1.4,
		LightPulseAmount = 0.45,
		PulseSpeed = 0.9, -- pulsación lenta
		MaxDistance = 220, -- más lejos que esto la animación se pausa
	},

	-- Respuesta visual al comprar una mejora.
	PurchaseBurst = {
		Particles = 24,
		FlashBrightness = 4,
		FlashDecayPerSecond = 2.5,
	},

	-- Evolución visual según el nivel de la mejora del jugador. Es SOLO visual: cada
	-- cliente pinta el cristal según su propio nivel (atributo que escribe el servidor).
	-- Details: grupos de StageDetails (construidos ocultos en el servidor) visibles en la etapa.
	Evolution = {
		UpgradeId = "GeneratorPower",
		TransitionSeconds = 1.2,

		-- Fragmentos de la etapa Dorada: corona de chispas bajo la punta inferior del
		-- cristal (los mueve GeneratorAnimator; altura relativa al centro del cristal).
		FragmentCount = 6,
		FragmentOrbitRadius = 3.2,
		FragmentOrbitSpeed = -0.45,
		FragmentHeight = -3.6,

		Stages = {
			{
				Name = "Turquesa",
				MinLevel = 0, -- niveles 0–5 (paleta del santuario: turquesa con acento violeta)
				Core = Color3.fromRGB(32, 229, 209),
				Shell = Color3.fromRGB(170, 255, 240),
				Light = Color3.fromRGB(32, 229, 209),
				Runes = Color3.fromRGB(32, 229, 209),
				Shards = Color3.fromRGB(60, 200, 190),
				Particles = { Color3.fromRGB(170, 255, 240), Color3.fromRGB(156, 140, 255) },
				ParticleRate = 4,
				Intensity = 1,
				Details = {},
			},
			{
				Name = "Esmeralda",
				MinLevel = 6, -- niveles 6–15
				Core = Color3.fromRGB(60, 214, 112),
				Shell = Color3.fromRGB(176, 255, 196),
				Light = Color3.fromRGB(80, 224, 128),
				Runes = Color3.fromRGB(100, 244, 150),
				Shards = Color3.fromRGB(84, 192, 124),
				Particles = { Color3.fromRGB(196, 255, 180), Color3.fromRGB(60, 214, 112) },
				ParticleRate = 7,
				Intensity = 1.2,
				Details = { "GrowthRoots", "RuneGlyphs", "RuneSparkles" },
			},
			{
				Name = "Dorado",
				MinLevel = 16, -- niveles 16–30
				Core = Color3.fromRGB(255, 196, 70),
				Shell = Color3.fromRGB(255, 236, 170),
				Light = Color3.fromRGB(255, 204, 100),
				Runes = Color3.fromRGB(255, 214, 110),
				Shards = Color3.fromRGB(240, 204, 116),
				Particles = { Color3.fromRGB(255, 244, 190), Color3.fromRGB(255, 180, 60) },
				ParticleRate = 10,
				Intensity = 1.5,
				Details = { "GrowthRoots", "RuneGlyphs", "RuneSparkles", "Fragments" },
			},
			{
				Name = "Violeta legendario",
				MinLevel = 31, -- nivel 31 en adelante
				Core = Color3.fromRGB(178, 98, 255),
				Shell = Color3.fromRGB(228, 194, 255),
				Light = Color3.fromRGB(176, 116, 255),
				Runes = Color3.fromRGB(206, 146, 255),
				Shards = Color3.fromRGB(172, 124, 232),
				Particles = { Color3.fromRGB(255, 224, 255), Color3.fromRGB(160, 92, 255) },
				ParticleRate = 12,
				Intensity = 1.9,
				Details = {
					"GrowthRoots",
					"RuneGlyphs",
					"RuneSparkles",
					"Fragments",
					"LegendarySpires",
					"LegendaryHalo",
					"LegendaryFloorRing",
					"LegendaryAura",
				},
			},
		},
	},
}

-- Posición de un fragmento en su órbita, relativa al centro del cristal (cálculo puro,
-- sin APIs de Roblox, para poder probarlo): círculo de radio Radius en el plano
-- horizontal, girado Tilt grados alrededor del eje horizontal de dirección Node.
function GeneratorConfig.orbitOffset(orbit: { [string]: number }, time: number): (number, number, number)
	local angle = orbit.Phase + orbit.Speed * time
	local vx, vz = math.cos(angle) * orbit.Radius, math.sin(angle) * orbit.Radius
	local node = math.rad(orbit.Node)
	local kx, kz = math.cos(node), math.sin(node)
	local tilt = math.rad(orbit.Tilt)
	local cosT, sinT = math.cos(tilt), math.sin(tilt)
	local dot = kx * vx + kz * vz
	-- Rodrigues con eje horizontal k = (kx, 0, kz) y vector v = (vx, 0, vz)
	return vx * cosT + kx * dot * (1 - cosT), (kz * vx - kx * vz) * sinT, vz * cosT + kz * dot * (1 - cosT)
end

-- Índice de la etapa que corresponde a un nivel (las etapas van ordenadas por MinLevel).
function GeneratorConfig.getStageIndex(level: number): number
	local stages = GeneratorConfig.Evolution.Stages
	local index = 1
	for stageIndex, stage in stages do
		if level >= stage.MinLevel then
			index = stageIndex
		end
	end
	return index
end

return GeneratorConfig
