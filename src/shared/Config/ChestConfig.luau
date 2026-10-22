-- Cofres escondidos del Bosque (ChestService): rincones que premian explorar el mapa.
-- Cada cofre se abre con su aviso de proximidad (tecla E) y da energía (minutos de TU
-- producción actual, con un mínimo; como el premio diario) y a veces una bendición. Luego
-- se cierra para ese jugador durante Cooldown segundos (se guarda en su registro, campo
-- Rewards.Chests); cada jugador ve sus cofres abiertos o cerrados.
--
-- Posiciones RELATIVAS al Cristal del Renacimiento (como WorldConfig y WildsConfig). Yaw:
-- hacia dónde mira la tapa, en grados (0 = hacia +Z, el spawn; 90 = hacia +X).

local V2 = Vector2.new

local ChestConfig = {
	Cooldown = 6 * 3600,
	OpenDistance = 12, -- distancia máxima (servidor) entre el jugador y el cofre
	PromptDistance = 8,
	HoldDuration = 0.4,

	Chests = {
		{
			Id = "Waterfall",
			Name = "Cofre de la Cascada",
			Hint = "Detrás del agua que cae…",
			Position = V2(-63.4, -120.3),
			Yaw = 0,
			Ledge = true, -- sobre la repisa de piedra de detrás del agua (encima de la poza)
			Reward = { Energy = { Minutes = 12, Min = 800 }, Blessings = { Abundance = 1 } },
		},
		{
			Id = "Ruins",
			Name = "Cofre de las Ruinas",
			Hint = "Al otro lado del río, entre columnas antiguas.",
			Position = V2(3.3, -137.9),
			Yaw = 0,
			Reward = { Energy = { Minutes = 12, Min = 800 }, Blessings = { Fortune = 1 } },
		},
		{
			Id = "Spire",
			Name = "Cofre del Pico de Cristal",
			Hint = "En lo alto de la colina del cristal gigante.",
			Position = V2(104, 105),
			Yaw = -60,
			Reward = { Energy = { Minutes = 10, Min = 700 }, Blessings = { Fury = 1 } },
		},
		{
			Id = "Camp",
			Name = "Cofre del Campamento",
			Hint = "Junto a la tienda del explorador, cerca del lago.",
			Position = V2(97, -71),
			Yaw = -90,
			Reward = { Energy = { Minutes = 8, Min = 500 } },
		},
		{
			Id = "Grove",
			Name = "Cofre de las Setas",
			Hint = "A la sombra de las setas gigantes.",
			Position = V2(-83.4, -100.3),
			Yaw = 180,
			Reward = { Energy = { Minutes = 8, Min = 500 } },
		},
		{
			Id = "Watchtower",
			Name = "Cofre del Vigía",
			Hint = "Al pie de la torre del vigía.",
			Position = V2(-48.6, 87.3),
			Yaw = 30,
			Reward = { Energy = { Minutes = 6, Min = 400 } },
		},
		{
			Id = "Meadow",
			Name = "Cofre de la Pradera",
			Hint = "Escondido en la hierba alta del oeste.",
			Position = V2(-122.4, 16.9),
			Yaw = 45,
			Reward = { Energy = { Minutes = 6, Min = 400 } },
		},
		{
			Id = "Pond",
			Name = "Cofre del Estanque",
			Hint = "En la orilla del estanque, junto al pueblo.",
			Position = V2(64, 70), -- en la hierba, al lado del patio del Jardín de los Huevos
			Yaw = -120,
			Reward = { Energy = { Minutes = 5, Min = 300 } },
		},
	},

	Colors = {
		Wood = Color3.fromRGB(150, 98, 56),
		DarkWood = Color3.fromRGB(104, 66, 38),
		Band = Color3.fromRGB(240, 196, 90),
		Glow = Color3.fromRGB(255, 220, 130),
	},
}

local byId = {}
for _, chest in ChestConfig.Chests do
	byId[chest.Id] = chest
end

function ChestConfig.get(id: any): any
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

return ChestConfig
