Color3 = { fromRGB = function(r, g, b) return { kind = "Color3", R = r, G = g, B = b } end }
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
local GeneratorConfig = (function()
-- Apariencia, posición y animación del Cristal del Renacimiento (el generador).
-- Solo afecta a lo visual; la producción la define EconomyConfig.
-- ModelName y la estructura (Core, Shell, Orbiters) los usa GeneratorAnimator.

local GeneratorConfig = {
	ModelName = "EnergyGenerator",
	DisplayName = "Cristal del Renacimiento",

	-- Centro de la base. Y = 0.5 es la superficie del terreno de la pradera (WorldConfig).
	Position = Vector3.new(0, 0.5, -25),

	Colors = {
		Stone = Color3.fromRGB(150, 150, 136),
		DarkStone = Color3.fromRGB(98, 102, 90),
		Root = Color3.fromRGB(104, 76, 52),
		Moss = Color3.fromRGB(92, 140, 64),
		Energy = Color3.fromRGB(80, 226, 196), -- turquesa natural del núcleo
		EnergySoft = Color3.fromRGB(186, 255, 236),
		Crystal = Color3.fromRGB(110, 214, 200),
		Gold = Color3.fromRGB(244, 204, 110),
	},

	CoreSize = 2.4, -- gema (cubo apoyado sobre un vértice)
	CoreHeight = 6.2, -- altura del centro del núcleo sobre el suelo
	ShellDiameter = 5,
	OrbiterCount = 3, -- piedras flotantes
	OrbiterSize = 1.1,

	LightRange = 22,

	-- Animación local en cada cliente (no se replica por red).
	Animation = {
		OrbitRadius = 3.6,
		OrbitSpeed = 0.7, -- radianes por segundo
		CoreSpinSpeed = 0.5,
		CoreBobHeight = 0.25,
		CoreBobSpeed = 1.2,
		LightBaseBrightness = 1.6,
		LightPulseAmount = 0.5,
		PulseSpeed = 1.8,
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

		-- Fragmentos flotantes (los mueve GeneratorAnimator en una órbita exterior).
		FragmentCount = 6,
		FragmentOrbitRadius = 5.4,
		FragmentOrbitSpeed = -0.45,
		FragmentHeight = 1.8,

		Stages = {
			{
				Name = "Turquesa",
				MinLevel = 0, -- niveles 0–5
				Core = Color3.fromRGB(80, 226, 196),
				Shell = Color3.fromRGB(186, 255, 236),
				Light = Color3.fromRGB(80, 226, 196),
				Runes = Color3.fromRGB(80, 226, 196),
				Shards = Color3.fromRGB(110, 214, 200),
				Particles = { Color3.fromRGB(244, 204, 110), Color3.fromRGB(186, 255, 236) },
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
end)()
local BUILT = { "GrowthRoots","RuneGlyphs","RuneSparkles","Fragments","LegendarySpires","LegendaryHalo","LegendaryFloorRing","LegendaryAura" }
local TINTS = { "Core","Light","Particles","Runes","Shards","Shell" }
local failures = 0
local function check(name, ok) if not ok then failures += 1 end print((ok and "OK   " or "FALLO") .. "  " .. name) end
local stages = GeneratorConfig.Evolution.Stages
local expected = { [0]=1, [1]=1, [5]=1, [6]=2, [15]=2, [16]=3, [30]=3, [31]=4, [50]=4 }
for level, stage in expected do
	check(("nivel %d -> etapa %d (%s)"):format(level, stage, stages[stage].Name), GeneratorConfig.getStageIndex(level) == stage)
end
local built = {}
for _, name in BUILT do built[name] = true end
local previous = {}
for index, stage in stages do
	for _, tint in TINTS do
		if tint ~= "Particles" then
			check(("etapa %d define color '%s'"):format(index, tint), type(stage[tint]) == "table" and stage[tint].kind == "Color3")
		end
	end
	check(("etapa %d define 2 colores de partículas"):format(index), #stage.Particles == 2)
	local current = {}
	for _, name in stage.Details do
		current[name] = true
		check(("etapa %d: grupo '%s' existe en GeneratorService"):format(index, name), built[name] == true)
	end
	for name in previous do
		check(("etapa %d conserva '%s' de la anterior"):format(index, name), current[name] == true)
	end
	previous = current
	if index > 1 then check(("etapa %d: MinLevel creciente"):format(index), stage.MinLevel > stages[index - 1].MinLevel) end
end
print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
