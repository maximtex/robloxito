-- Tablas de clasificación de madera (tabla-madera-leaderboard.glb, LeaderboardService). Cada
-- tabla pasa sola por varias páginas (cada PageSeconds):
--   Server  -> los mejores jugadores DE ESTE SERVIDOR, en tiempo real (atributos).
--   Global  -> los mejores de TODOS los servidores (OrderedDataStore), al día cada minuto.
--   Weekly  -> 💎 conseguidos esta semana en todos los servidores; se reinicia los lunes
--              a las 00:00 UTC (domingo 7 de la noche en Colombia).
-- Posiciones RELATIVAS al centro del bosque, en X/Z: las tres en arco al fondo de la plaza
-- (vistas desde el spawn), giradas hacia el centro de la plaza (FaceToward). La fila de
-- abajo de cada tabla es la del jugador que la mira (LeaderboardController).
-- Las clasificaciones globales solo funcionan en el juego publicado (o en Studio con
-- "Enable Studio Access to API Services"); si no, la página lo dice.

local LeaderboardConfig = {
	ModelName = "Leaderboards",
	Rows = 10, -- puestos que muestra cada tabla (las filas del diseño)
	RefreshSeconds = 3, -- página del servidor
	PageSeconds = 8, -- cada cuánto cambia de página
	FaceToward = Vector2.new(0, 25), -- miran al centro de la plaza
	Footprint = 9, -- radio que ocupa con su base (17.5 de ancho)

	-- Clasificaciones globales (OrderedDataStore). Cambiar el sufijo _v1 las empieza de cero.
	Global = {
		Stores = {
			Diamonds = "RC_Global_Diamonds_v1", -- 💎 conseguidos en total (no baja al renacer; antes, energía)
			Rebirths = "RC_Global_Rebirths_v1",
			Waves = "RC_Global_Waves_v1", -- oleadas superadas en total (WaveLogic.Records)
			Weekly = "RC_Weekly_Diamonds_v1_", -- + número de semana
		},
		PublishSeconds = 120, -- cada cuánto se publica lo de cada jugador (solo si cambió)
		FetchSeconds = 60, -- cada cuánto se leen los mejores
	},

	Boards = {
		{
			Id = "Diamonds",
			Title = "💎 Diamantes conseguidos",
			Attribute = "TotalDiamonds", -- 💎 conseguidos en total (no baja al gastar ni al renacer)
			Pages = { "Server", "Global", "Weekly" },
			Global = "Diamonds",
			Position = Vector2.new(-23, -3),
			Accent = Color3.fromRGB(110, 236, 220),
		},
		{
			Id = "Rebirths",
			Title = "🔄 Más renacimientos",
			Attribute = "Rebirths",
			Tiebreak = "TotalDiamonds", -- a igualdad de renacimientos, más 💎 conseguidos
			Pages = { "Server", "Global" },
			Global = "Rebirths",
			Position = Vector2.new(23, -3),
			Accent = Color3.fromRGB(255, 214, 110),
		},
		{
			Id = "Waves",
			Title = "🌊 Oleadas superadas",
			Attribute = "WavesCleared", -- en total, en todos los modos (sin la práctica)
			Tiebreak = "TotalDiamonds",
			Pages = { "Server", "Global" },
			Global = "Waves",
			Position = Vector2.new(0, -8),
			Accent = Color3.fromRGB(255, 150, 90),
		},
	},

	PageTitles = {
		Server = "Mejores del servidor",
		Global = "🌍 Mejores de todo el juego",
		Weekly = "🏆 Top de la semana",
	},
}

return LeaderboardConfig
