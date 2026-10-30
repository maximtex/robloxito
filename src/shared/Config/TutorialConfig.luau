-- Tutorial inicial: corto (unos 5 minutos) y fácil (pruebas con amigos: "es ambiguo, no se
-- entiende y se lo saltan"). Cuatro pasos en orden; cada uno se cumple con datos del servidor
-- (los mismos que usan las misiones, QuestLogic.Context y las estadísticas guardadas); el
-- cliente nunca declara un paso como hecho.
--
-- Goal:
--   { Source = "Stat", Key = ... }    estadística guardada (QuestData.Stats)
--   { Source = "State", Key = ... }   estado del perfil (QuestLogic.Context)
--   { Source = "Zone", Zone = ... }   zona desbloqueada
-- Si un paso posterior ya está cumplido, los anteriores cuentan como hechos.
--
-- Reward: lo justo para el paso siguiente, al cumplir cada paso (TutorialService): 💰 y
-- pociones (ItemConfig.Potions). Así nadie se queda trabado: la práctica da el 💰 de la
-- primera mejora del arma, el arma el del primer huevo, el huevo el de la primera mejora de ⚡
-- Mejoras, y al terminar 💰 y dos ❤️ pociones. Omitir no da premios.
--
-- Guide: a dónde apunta la guía del cliente ("Waves" (el altar de la práctica de
-- las oleadas, WaveConfig.Places), "Cave" (la boca de la Cueva de los Espinillos y, dentro,
-- el altar de las Oleadas del Guardián, CaveConfig), "Egg:<EggId>", "Arena:<zona del jefe>",
-- "Portal:<PortalId>") o qué parte de la interfaz se señala ("ArmoryButton", "PetsButton",
-- "SkillsButton": el ⚡ de los botones de habilidad, que abre ⚡ Mejoras).

local TutorialConfig = {
	Steps = {
		{
			-- La mecánica principal. El altar (en el Bosque de Espinas, junto a la llegada desde
			-- el pueblo: WaveConfig.Places.Practice) da una partida corta de práctica
			-- (WaveConfig.Arenas.Tutorial) con consejos en pantalla.
			Id = "Waves",
			Title = "Tu primera oleada",
			Text = "Sigue la flecha al Bosque de Espinas y pulsa E en el altar. Clic para atacar, Shift para esquivar.",
			Goal = { Source = "Stat", Key = "WaveWins" },
			Target = 1,
			Guide = "Waves",
			Reward = { Money = 50 }, -- la primera mejora del arma cuesta 25
		},
		{
			Id = "Weapon",
			Title = "Mejora tu arma",
			Text = "Pulsa L (Armas) y dale a MEJORAR. Más nivel = más daño.",
			Goal = { Source = "State", Key = "WeaponLevel" },
			Target = 1,
			Guide = "ArmoryButton",
			Reward = { Money = 250 }, -- el Huevo del Bosque (EggConfig.Eggs.ForestEgg.Cost)
		},
		{
			Id = "Pet",
			Title = "Consigue una mascota",
			Text = "Sigue la flecha y abre el Huevo del Bosque (el 💰 te lo regalamos). Te ayuda a pelear.",
			Goal = { Source = "State", Key = "PetsOwned" },
			Target = 2, -- la inicial y una más
			Guide = "Egg:ForestEgg",
			Reward = { Money = 300 }, -- la primera Vitalidad (EconomyConfig.Upgrades.Vitality)
		},
		{
			Id = "Upgrade",
			Title = "Hazte más fuerte",
			Text = "Pulsa B (⚡ Mejoras) y compra ❤️ Vitalidad o 🛡️ Armadura.",
			Goal = { Source = "State", Key = "BodyUpgrades" },
			Target = 1,
			Guide = "SkillsButton",
			Reward = { Money = 500, Potions = { Health = 2 } },
		},
	},
	-- Quien ya pasó de esto (jefe de la cueva derrotado, el Valle abierto o un renacimiento)
	-- no hace el tutorial: se completa solo, sin premios.
	Veteran = {
		{ Goal = { Source = "Stat", Key = "BossKills" }, Target = 1 },
		{ Goal = { Source = "Zone", Zone = "CrystalValley" }, Target = 1 },
		{ Goal = { Source = "State", Key = "Rebirths" }, Target = 1 },
	},
	-- Después del tutorial (completado u omitido): el siguiente objetivo, con su flecha, hasta
	-- cumplirlo (TutorialLogic.nextGoal; el cliente lo enseña y se puede ocultar).
	NextGoals = {
		{
			Id = "Boss",
			Title = "Vence al Guardián",
			Text = "Cruza al Bosque de Espinas: la 🦇 Cueva de los Espinillos está al fondo. Gana las oleadas de su altar.",
			Goal = { Source = "Stat", Key = "BossKills" },
			Target = 1,
			Guide = "Cave",
		},
		{
			Id = "Valley",
			Title = "Abre el Valle Morado",
			Text = "Junta el 💰 que pide el portal y ábrelo: allí siguen las aventuras.",
			Goal = { Source = "Zone", Zone = "CrystalValley" },
			Target = 1,
			Guide = "Portal:ValleyPortal",
		},
	},
	SkipRateLimit = { Cooldown = 1, WindowSeconds = 5, MaxPerWindow = 4 },
	-- Pasos que hay que hacer antes de poder omitirlo: la oleada de práctica es obligatoria.
	MinSkipStep = 1,
	GuideHideDistance = 14, -- la guía en el mundo desaparece al llegar cerca
}

return TutorialConfig
