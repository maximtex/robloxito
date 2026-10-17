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
-- Guide: a dónde apunta la guía del cliente ("Crystal", "Egg:<EggId>", "Portal:<PortalId>")
-- o qué parte de la interfaz se señala ("UpgradeButton", "PetsButton").

local TutorialConfig = {
	Steps = {
		{
			Id = "Energy",
			Title = "Genera energía",
			Text = "El cristal produce energía sin parar. Reúne tus primeros 10 ⚡.",
			Goal = { Source = "Stat", Key = "EnergyEarned" },
			Target = 10,
			Guide = "Crystal",
		},
		{
			Id = "Upgrade",
			Title = "Compra una mejora",
			Text = "Pulsa MEJORAR (abajo, en el centro) para producir más energía.",
			Goal = { Source = "State", Key = "UpgradeLevel" },
			Target = 1,
			Guide = "UpgradeButton",
		},
		{
			Id = "Pet",
			Title = "Consigue una mascota",
			Text = "Ve al santuario del Huevo del Bosque y ábrelo (100 ⚡).",
			Goal = { Source = "State", Key = "PetsOwned" },
			Target = 1,
			Guide = "Egg:ForestEgg",
		},
		{
			Id = "Equip",
			Title = "Equipa tu mascota",
			Text = "Abre 🐾 Mascotas (tecla P) y pulsa Equipar: multiplica tu energía.",
			Goal = { Source = "State", Key = "PetsEquipped" },
			Target = 1,
			Guide = "PetsButton",
		},
		{
			Id = "Valley",
			Title = "Desbloquea el Valle Cristalino",
			Text = "Reúne energía y usa el portal al final del camino.",
			Goal = { Source = "Zone", Zone = "CrystalValley" },
			Target = 1,
			Guide = "Portal:ForestPortal",
		},
	},
	SkipRateLimit = { Cooldown = 1, WindowSeconds = 5, MaxPerWindow = 4 },
	GuideHideDistance = 14, -- la guía en el mundo desaparece al llegar cerca
}

return TutorialConfig
