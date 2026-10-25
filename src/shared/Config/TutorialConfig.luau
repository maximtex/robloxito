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
-- Guide: a dónde apunta la guía del cliente ("Crystal", "Egg:<EggId>", "Arena:<zona del
-- jefe>", "Portal:<PortalId>") o qué parte de la interfaz se señala ("ArmoryButton",
-- "PetsButton").

local TutorialConfig = {
	Steps = {
		{
			Id = "Hunt",
			Title = "Derrota enemigos",
			Text = "Sal del pueblo y haz clic en un enemigo para dispararle (o pulsa F / \"Disparar\" para el más cercano). Derrota 3 y recoge su 💰.",
			Goal = { Source = "Stat", Key = "Kills" },
			Target = 3,
		},
		{
			Id = "Weapon",
			Title = "Mejora tu arma",
			Text = "Abre la ⚔️ Armería (tecla L o el puesto del pueblo) y mejora tu láser con 💰.",
			Goal = { Source = "State", Key = "WeaponLevel" },
			Target = 1,
			Guide = "ArmoryButton",
		},
		{
			Id = "Pet",
			Title = "Consigue una mascota",
			Text = "Ve al 🥚 Jardín de los Huevos (a la derecha del spawn) y abre el Huevo del Bosque (50 ⚡).",
			Goal = { Source = "State", Key = "PetsOwned" },
			Target = 2, -- la inicial y una más
			Guide = "Egg:ForestEgg",
		},
		{
			Id = "Boss",
			Title = "Aguanta las oleadas del Guardián",
			Text = "En el Círculo del Guardián pulsa E en el pedestal: aguanta 10 oleadas y en la última sale el Guardián. Avisa sus golpes en el suelo: apártate del círculo rojo. Regala un arma.",
			Goal = { Source = "Stat", Key = "BossKills" },
			Target = 1,
			Guide = "Arena:Forest",
		},
		{
			Id = "Valley",
			Title = "Desbloquea el Valle Morado",
			Text = "Con el Guardián derrotado y energía suficiente, abre el portal al final del camino.",
			Goal = { Source = "Zone", Zone = "CrystalValley" },
			Target = 1,
			Guide = "Portal:ForestPortal",
		},
	},
	SkipRateLimit = { Cooldown = 1, WindowSeconds = 5, MaxPerWindow = 4 },
	GuideHideDistance = 14, -- la guía en el mundo desaparece al llegar cerca
}

return TutorialConfig
