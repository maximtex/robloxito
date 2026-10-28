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
			Title = "Tu primera oleada",
			Text = "1) Sigue la flecha hasta el círculo brillante.  2) Pulsa E en el altar.  3) Apunta con el ratón y haz clic para atacar. Shift = dash para esquivar.",
			Goal = { Source = "Stat", Key = "WaveWins" },
			Target = 1,
			Guide = "Waves",
		},
		{
			Id = "Weapon",
			Title = "Mejora tu arma",
			Text = "Pulsa L (o el botón Armas, abajo) y dale a MEJORAR con el 💰 que soltaron los enemigos. Más nivel = más daño.",
			Goal = { Source = "State", Key = "WeaponLevel" },
			Target = 1,
			Guide = "ArmoryButton",
		},
		{
			Id = "Pet",
			Title = "Consigue una mascota",
			Text = "Sigue la flecha al 🥚 Jardín de los Huevos y abre el Huevo del Bosque (250 💰). Cada mascota ayuda a su manera: ⚔️ daño, 🛡️ defensa, 💚 cura o 💰 dinero.",
			Goal = { Source = "State", Key = "PetsOwned" },
			Target = 2, -- la inicial y una más
			Guide = "Egg:ForestEgg",
		},
		{
			Id = "Boss",
			Title = "Vence al Guardián",
			Text = "Sigue la flecha a la 🦇 Cueva de los Espinillos y gana las 10 oleadas de su altar: en la última sale el Guardián. Sal de los círculos rojos y, con poca vida, toma una ❤️ poción (Y).",
			Goal = { Source = "Stat", Key = "BossKills" },
			Target = 1,
			Guide = "Cave",
		},
		{
			Id = "Valley",
			Title = "Abre el Valle Morado",
			Text = "Junta el 💰 que pide el portal (sigue la flecha) y ábrelo: allí siguen las aventuras.",
			Goal = { Source = "Zone", Zone = "CrystalValley" },
			Target = 1,
			Guide = "Portal:ForestPortal",
		},
	},
	SkipRateLimit = { Cooldown = 1, WindowSeconds = 5, MaxPerWindow = 4 },
	-- Pasos que hay que hacer antes de poder omitirlo (pruebas con amigos: "se lo saltan sin
	-- saber jugar"): la primera oleada y mejorar el arma son obligatorios.
	MinSkipStep = 2,
	GuideHideDistance = 14, -- la guía en el mundo desaparece al llegar cerca
}

return TutorialConfig
