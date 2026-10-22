-- Círculo Elemental: los altares de los siete núcleos (Agua … Celestial) alrededor del
-- Cristal del Renacimiento, que ES el núcleo de Naturaleza. Solo visual: no toca la
-- economía (CoreConfig/CoreLogic siguen sin conectar a ningún servicio).
--
-- Posiciones RELATIVAS al cristal (GeneratorConfig.Position), en X/Z, como el resto del mapa.
-- Los altares forman un arco por DETRÁS del cristal (Z negativo), entre la plataforma
-- (radio 15) y el árbol ancestral; el frente queda libre para el spawn, el camino y los
-- santuarios de huevos. El orden de desbloqueo zigzaguea de delante hacia atrás y
-- termina en Celestial, en el centro, frente al árbol ancestral.
--
-- ESTADO DE CADA ALTAR (lo pinta CoreShrineController en cada cliente, según SUS datos):
-- - Dormido: piedra gris, sin brillo ni partículas, el cristal reposa sobre la columna.
-- - Despierto: colores del elemento, partículas y el cristal flota y gira.
-- - Activo (elemento seleccionado): además, un haz de energía hasta el cristal central.
-- Contrato para la fase 2 (el servidor aún NO escribe estos atributos del Player):
--   UnlockedCores = "Nature,Water,Fire"   (Constants.Attributes.UnlockedCores)
--   SelectedCore  = "Water"               (Constants.Attributes.SelectedCore)
-- Mientras no existan, todos los altares se ven dormidos con el rótulo «Próximamente».
-- Vista previa en Studio: Workspace:SetAttribute("CorePreview", true) despierta todos;
-- con un elemento (p. ej. "Fire") además lo marca como activo.

local CoreShrineConfig = {
	ModelName = "ElementalCores",

	Radius = 21, -- distancia de cada altar al centro del cristal
	FootprintRadius = 2.7, -- radio de la base de piedra
	KeepClearRadius = 3.6, -- zona sin flores alrededor de cada altar (WorldService)

	-- Ángulo de cada altar en grados: 0 = +X (derecha vista desde el spawn), 90 = +Z
	-- (hacia el spawn), 270 = detrás del cristal (hacia el árbol ancestral).
	Angles = {
		Water = 201,
		Fire = 339,
		Wind = 224,
		Lightning = 316,
		Ice = 247,
		Shadow = 293,
		Celestial = 270,
	},

	-- Medidas comunes (studs). El cristal de Celestial es algo mayor.
	Altar = {
		BaseHeight = 0.6,
		StepHeight = 0.5,
		StepRadius = 2.1,
		ColumnHeight = 1.9,
		ColumnDiameter = 1.3,
		CrystalWidth = 0.95,
		CrystalHeight = 2.6,
		CelestialScale = 1.25,
		OrbiterCount = 3,
		OrbitRadius = 1.7,
		LightRange = 12,
		LabelMaxDistance = 22, -- de cerca: con más distancia los rótulos se amontonan
	},

	Stone = {
		Base = Color3.fromRGB(150, 140, 110),
		Dark = Color3.fromRGB(96, 92, 78),
		Moss = Color3.fromRGB(70, 112, 62),
		Dormant = Color3.fromRGB(104, 104, 108), -- cristal dormido (piedra gris, sin brillo)
		DormantRune = Color3.fromRGB(70, 74, 72),
	},

	-- Paleta y motivo de cada elemento. Color: cristal y runas; Glow: luz y partículas;
	-- Stone: piedra propia del altar (si no, la común); Motif: decoración de la base;
	-- Title: rótulo (por defecto "Núcleo de <nombre>").
	Elements = {
		Water = {
			Color = Color3.fromRGB(60, 150, 255),
			Glow = Color3.fromRGB(150, 210, 255),
			Motif = "Pool",
		},
		Fire = {
			Color = Color3.fromRGB(255, 92, 36),
			Glow = Color3.fromRGB(255, 186, 90),
			Stone = Color3.fromRGB(120, 92, 80),
			Motif = "Braziers",
		},
		Wind = {
			Color = Color3.fromRGB(110, 228, 186),
			Glow = Color3.fromRGB(210, 255, 238),
			Motif = "Gusts",
		},
		Lightning = {
			Color = Color3.fromRGB(255, 212, 50),
			Glow = Color3.fromRGB(255, 246, 170),
			Stone = Color3.fromRGB(110, 112, 128),
			Motif = "Spires",
		},
		Ice = {
			Color = Color3.fromRGB(140, 214, 255),
			Glow = Color3.fromRGB(225, 245, 255),
			Stone = Color3.fromRGB(170, 182, 196),
			Motif = "Frost",
		},
		Shadow = {
			Color = Color3.fromRGB(140, 72, 220),
			Glow = Color3.fromRGB(196, 150, 255),
			Stone = Color3.fromRGB(52, 48, 62),
			Motif = "Obsidian",
		},
		Celestial = {
			Color = Color3.fromRGB(255, 210, 110),
			Glow = Color3.fromRGB(255, 248, 220),
			Stone = Color3.fromRGB(226, 220, 200),
			Motif = "Halo",
			Title = "Núcleo Celestial",
		},
	},

	Animation = {
		SpinSpeed = 0.5, -- giro del cristal despierto (rad/s)
		BobHeight = 0.25,
		BobSpeed = 1.1,
		OrbitSpeed = 0.9,
		WakeSeconds = 1.2, -- subida del cristal al despertar
		MaxDistance = 180, -- más lejos que esto no se anima
	},
}

-- Posición (X, Z) del altar de un elemento, relativa al cristal.
function CoreShrineConfig.offset(elementId: string): Vector2
	local angle = math.rad(CoreShrineConfig.Angles[elementId])
	return Vector2.new(math.cos(angle) * CoreShrineConfig.Radius, math.sin(angle) * CoreShrineConfig.Radius)
end

return CoreShrineConfig
