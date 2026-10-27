-- Tutorial inicial: pasos en orden. Cada paso se cumple con datos del servidor (los mismos
-- que usan las misiones, QuestLogic.Context y las estadísticas guardadas); el cliente
-- nunca declara un paso como hecho.
--
-- Goal:
--   { Source = "Stat", Key = ... }    estadística guardada (QuestData.Stats)
--   { Source = "State", Key = ... }   estado del perfil (QuestLogic.Context)
--   { Source = "Zone", Zone = ... }   zona desbloqueada
-- Si un paso posterior ya está cumplido, los anteriores cuentan como hechos (un jugador
-- veterano con el Valle no repite nada: el tutorial se completa solo).
-- Sin recompensas: las mismas acciones ya las premian las misiones.
--
-- Guide: a dónde apunta la guía del cliente ("Waves" (el altar de la práctica de
-- las oleadas, WaveConfig.Places), "Cave" (la boca de la Cueva de los Espinillos y, dentro,
-- el altar de las Oleadas del Guardián, CaveConfig), "Egg:<EggId>", "Arena:<zona del jefe>",
-- "Portal:<PortalId>") o qué parte de la interfaz se señala ("ArmoryButton", "PetsButton").

local TutorialConfig = {
	Steps = {
		{
			-- Primer paso: la mecánica principal. El altar le da una partida corta de práctica
			-- (WaveConfig.Arenas.Tutorial) con consejos en pantalla.
			Id = "Waves",
			Title = "Juega tu primera oleada",
			Text = "Ve al círculo brillante delante de ti y pulsa E en el altar. Dentro apunta con el ratón y haz clic (o mantén) para atacar: aguanta 3 oleadas cortas.",
			Goal = { Source = "Stat", Key = "WaveWins" },
			Target = 1,
			Guide = "Waves",
		},
		{
			Id = "Weapon",
			Title = "Mejora tu equipo",
			Text = "Abre la tienda de tu estilo (tecla L o el puesto del pueblo) y mejora tu arma, tus guantes o tu bastón con 💰.",
			Goal = { Source = "State", Key = "WeaponLevel" },
			Target = 1,
			Guide = "ArmoryButton",
		},
		{
			Id = "Pet",
			Title = "Consigue una mascota",
			Text = "Ve al 🥚 Jardín de los Huevos (a la derecha del spawn) y abre el Huevo del Bosque (250 💰).",
			Goal = { Source = "State", Key = "PetsOwned" },
			Target = 2, -- la inicial y una más
			Guide = "Egg:ForestEgg",
		},
		{
			Id = "Boss",
			Title = "Vence al Guardián en la cueva",
			Text = "Entra en la 🦇 Cueva de los Espinillos (camino de piedra al oeste de la plaza), cruza la sala de los pequeños y la de los medianos y, en el altar, aguanta las 10 oleadas: en la última sale el Guardián. Apártate de los círculos rojos. Regala un arma.",
			Goal = { Source = "Stat", Key = "BossKills" },
			Target = 1,
			Guide = "Cave",
		},
		{
			Id = "Valley",
			Title = "Desbloquea el Valle Morado",
			Text = "Con el Guardián derrotado y 💰 suficiente, abre el portal al final del camino.",
			Goal = { Source = "Zone", Zone = "CrystalValley" },
			Target = 1,
			Guide = "Portal:ForestPortal",
		},
	},
	SkipRateLimit = { Cooldown = 1, WindowSeconds = 5, MaxPerWindow = 4 },
	GuideHideDistance = 14, -- la guía en el mundo desaparece al llegar cerca
}

return TutorialConfig
