-- Misiones, misiones diarias y logros. Para añadir una basta con una entrada nueva aquí:
-- la lógica (QuestLogic) es la misma para todas.
--
-- Goal: de dónde sale el progreso (siempre de datos del servidor):
--   { Source = "Stat", Key = ... }   estadística permanente registrada por el servidor:
--       Kills, StrongKills, BossKills, DiamondsEarned (💎 de enemigos y oleadas; NUNCA
--       incluye recompensas de misiones), PetAbilities.
--   { Source = "ZoneKills", Zone = ... }   enemigos derrotados en una zona.
--   { Source = "BossTypes" }   jefes distintos derrotados al menos una vez.
--   { Source = "State", Key = ... }   estado actual del perfil: WeaponLevel (nivel del arma,
--       guante o bastón más mejorado), PetsOwned, PetsEquipped, CombatPetsOwned,
--       ZonesUnlocked (zonas compradas), Rebirths.
--   { Source = "Daily", Event = "Kill" | "Diamonds" | "PetAbility" | "Upgrade" | "Egg", Kind?, Zone? }
--       contador del día (solo para misiones diarias). Upgrade: mejoras de armas, guantes o
--       bastones compradas (GameEvents "WeaponUpgraded"); Egg: huevos abiertos.
-- RequiresZone: no se muestra como alcanzable (ni se ofrece como diaria) sin esa zona.
-- RequiresCombatPet: solo se ofrece como diaria si el jugador tiene una mascota de combate.
--
-- Recompensa (💎 diamantes, en el código Diamonds; la calcula el servidor al reclamar):
--   min(Min · ZoneFactor de tu mejor zona abierta, Max)
-- Así acompaña a la etapa actual sin dispararse (Max). Referencia: un enemigo pequeño da
-- ~1 💎, un Bruto ~4, una partida de oleadas ganada ~60 y los jefes 60 / 150 / 400; las
-- habilidades nuevas cuestan unos cientos (StyleConfig.Catalog).
-- Las tres diarias juntas dan como mucho ~1 200 al día (el peor caso, con los topes).
-- Los logros que coinciden con una misión (primer enemigo, primer jefe, primera mascota,
-- primera zona) no dan nada: la misma acción nunca se premia dos veces.

local QuestConfig = {
	DailyCount = 3,
	DailyAlways = { "DailyHunt" }, -- siempre entre las diarias del día
	DaySeconds = 86400, -- las diarias cambian a las 00:00 UTC (hora del servidor)
	-- Multiplicador de las recompensas según la mejor zona abierta (la más alta cuenta).
	ZoneFactor = {
		Forest = 1,
		CrystalValley = 1.5,
		EmberCaldera = 2,
		FrozenTundra = 3,
		GoblinFortress = 4,
		World2 = 5,
		DividedLands = 5,
	},
	MaxIdLength = 64,
	ClaimRateLimit = { Cooldown = 0.25, WindowSeconds = 2, MaxPerWindow = 8 },
	RequestRateLimit = { Cooldown = 1, WindowSeconds = 5, MaxPerWindow = 6 },
	PushInterval = 2, -- como mucho un envío de estado cada 2 s por jugador (salvo al reclamar)

	-- Misiones de una sola vez (en orden de progresión)
	Missions = {
		{
			Id = "BuyUpgrade",
			Title = "Mejora tu arma",
			Description = "Mejora tu arma, guante o bastón en la tienda de tu estilo (L).",
			Goal = { Source = "State", Key = "WeaponLevel" },
			Target = 1,
			Reward = { Min = 4, Max = 40 },
		},
		{
			Id = "DefeatFive",
			Title = "Primeros pasos de cazador",
			Description = "Derrota a 5 enemigos.",
			Goal = { Source = "Stat", Key = "Kills" },
			Target = 5,
			Reward = { Min = 8, Max = 80 },
		},
		{
			Id = "FirstPet",
			Title = "Un nuevo amigo",
			Description = "Consigue tu primera mascota en el Jardín de los Huevos.",
			Goal = { Source = "State", Key = "PetsOwned" },
			Target = 1,
			Reward = { Min = 12, Max = 100 },
		},
		{
			Id = "EquipPet",
			Title = "Compañero de viaje",
			Description = "Equipa una mascota.",
			Goal = { Source = "State", Key = "PetsEquipped" },
			Target = 1,
			Reward = { Min = 6, Max = 60 },
		},
		{
			Id = "DefeatStrong",
			Title = "Más duro que la corteza",
			Description = "Derrota a un enemigo fuerte.",
			Goal = { Source = "Stat", Key = "StrongKills" },
			Target = 1,
			Reward = { Min = 20, Max = 160 },
		},
		{
			Id = "EarnDiamonds",
			Title = "Buscador de diamantes",
			Description = "Consigue 40 💎 derrotando enemigos.",
			Goal = { Source = "Stat", Key = "DiamondsEarned" },
			Target = 40,
			Reward = { Min = 30, Max = 200 },
		},
		{
			Id = "UnlockValley",
			Title = "Más allá del portal",
			Description = "Desbloquea el Valle Cristalino.",
			Goal = { Source = "State", Key = "ZonesUnlocked" },
			Target = 1,
			Reward = { Min = 80, Max = 500 },
		},
		{
			Id = "FirstBoss",
			Title = "Caída de un gigante",
			Description = "Derrota a tu primer jefe.",
			Goal = { Source = "Stat", Key = "BossKills" },
			Target = 1,
			Reward = { Min = 60, Max = 600 },
		},
		{
			Id = "ValleyHunter",
			Title = "Eco del Valle",
			Description = "Derrota a 10 enemigos del Valle Cristalino.",
			Goal = { Source = "ZoneKills", Zone = "CrystalValley" },
			Target = 10,
			RequiresZone = "CrystalValley",
			Reward = { Min = 120, Max = 600 },
		},
		{
			Id = "UnlockCaldera",
			Title = "Corazón de fuego",
			Description = "Desbloquea la Caldera de Brasas (pide 3 renacimientos).",
			Goal = { Source = "State", Key = "ZonesUnlocked" },
			Target = 2,
			Reward = { Min = 600, Max = 5000 },
		},
		{
			Id = "CalderaHunter",
			Title = "Apagafuegos",
			Description = "Derrota a 15 enemigos de la Caldera de Brasas.",
			Goal = { Source = "ZoneKills", Zone = "EmberCaldera" },
			Target = 15,
			RequiresZone = "EmberCaldera",
			Reward = { Min = 1000, Max = 6000 },
		},
	},

	-- Diarias: cada día se eligen DailyCount entre las que el jugador puede hacer.
	Daily = {
		{
			Id = "DailyHunt",
			Title = "Patrulla del día",
			Description = "Derrota a 15 enemigos.",
			Goal = { Source = "Daily", Event = "Kill" },
			Target = 15,
			Reward = { Min = 20, Max = 300 },
		},
		{
			Id = "DailyStrong",
			Title = "Prueba de fuerza",
			Description = "Derrota a 2 enemigos fuertes.",
			Goal = { Source = "Daily", Event = "Kill", Kind = "Strong" },
			Target = 2,
			Reward = { Min = 30, Max = 300 },
		},
		{
			Id = "DailyDiamonds",
			Title = "Cosecha de diamantes",
			Description = "Consigue 60 💎 derrotando enemigos.",
			Goal = { Source = "Daily", Event = "Diamonds" },
			Target = 60,
			Reward = { Min = 24, Max = 240 },
		},
		{
			Id = "DailyUpgrade",
			Title = "Afila tu arma",
			Description = "Mejora tus armas, guantes o bastones 3 veces.",
			Goal = { Source = "Daily", Event = "Upgrade" },
			Target = 3,
			Reward = { Min = 24, Max = 300 },
		},
		{
			Id = "DailyEggs",
			Title = "Incubadora",
			Description = "Abre 3 huevos.",
			Goal = { Source = "Daily", Event = "Egg" },
			Target = 3,
			Reward = { Min = 30, Max = 300 },
		},
		{
			Id = "DailyPets",
			Title = "Trabajo en equipo",
			Description = "Tus mascotas de combate aciertan 30 habilidades.",
			Goal = { Source = "Daily", Event = "PetAbility" },
			Target = 30,
			RequiresCombatPet = true,
			Reward = { Min = 30, Max = 300 },
		},
		{
			Id = "DailyValley",
			Title = "Ronda por el Valle",
			Description = "Derrota a 12 enemigos del Valle Cristalino.",
			Goal = { Source = "Daily", Event = "Kill", Zone = "CrystalValley" },
			Target = 12,
			RequiresZone = "CrystalValley",
			Reward = { Min = 60, Max = 400 },
		},
		{
			Id = "DailyBoss",
			Title = "Cazador de leyendas",
			Description = "Derrota a un jefe.",
			Goal = { Source = "Daily", Event = "Kill", Kind = "Boss" },
			Target = 1,
			RequiresZone = "CrystalValley", -- a partir de la etapa media
			Reward = { Min = 80, Max = 500 },
		},
		{
			Id = "DailyCaldera",
			Title = "Ronda por la Caldera",
			Description = "Derrota a 12 enemigos de la Caldera de Brasas.",
			Goal = { Source = "Daily", Event = "Kill", Zone = "EmberCaldera" },
			Target = 12,
			RequiresZone = "EmberCaldera",
			Reward = { Min = 600, Max = 4000 },
		},
	},

	-- Logros permanentes: se desbloquean solos (una vez) al cumplirse.
	Achievements = {
		{ Id = "FirstBlood", Title = "Primer enemigo", Description = "Derrota a tu primer enemigo.", Goal = { Source = "Stat", Key = "Kills" }, Target = 1 },
		{ Id = "Hunter100", Title = "Cazador", Description = "Derrota a 100 enemigos.", Goal = { Source = "Stat", Key = "Kills" }, Target = 100, Reward = { Min = 60, Max = 600 } },
		{ Id = "Hunter500", Title = "Leyenda del bosque", Description = "Derrota a 500 enemigos.", Goal = { Source = "Stat", Key = "Kills" }, Target = 500, Reward = { Min = 200, Max = 1600 } },
		{ Id = "FirstBoss", Title = "Primer jefe", Description = "Derrota a un jefe.", Goal = { Source = "Stat", Key = "BossKills" }, Target = 1 },
		{ Id = "BossHunter", Title = "Cazajefes", Description = "Derrota a 5 jefes.", Goal = { Source = "Stat", Key = "BossKills" }, Target = 5, Reward = { Min = 200, Max = 1600 } },
		{ Id = "BothBosses", Title = "Domador de colosos", Description = "Derrota al Guardián del Bosque y al Coloso de Amatista.", Goal = { Source = "BossTypes" }, Target = 2, Reward = { Min = 300, Max = 1600 } },
		{ Id = "AllBosses", Title = "Señor de los titanes", Description = "Derrota a los tres jefes: Guardián, Coloso y Titán de la Caldera.", Goal = { Source = "BossTypes" }, Target = 3, Reward = { Min = 1000, Max = 6000 } },
		{ Id = "FirstPet", Title = "Primera mascota", Description = "Consigue una mascota.", Goal = { Source = "State", Key = "PetsOwned" }, Target = 1 },
		{ Id = "Collector", Title = "Coleccionista", Description = "Ten 10 mascotas.", Goal = { Source = "State", Key = "PetsOwned" }, Target = 10, Reward = { Min = 100, Max = 800 } },
		{ Id = "CombatPet", Title = "Guardián de cristal", Description = "Consigue una mascota de combate.", Goal = { Source = "State", Key = "CombatPetsOwned" }, Target = 1, Reward = { Min = 100, Max = 800 } },
		{ Id = "NewHorizon", Title = "Nuevo horizonte", Description = "Desbloquea una zona nueva.", Goal = { Source = "State", Key = "ZonesUnlocked" }, Target = 1 },
		-- (Id antiguo: era "Resonancia plena"; se conserva para no volver a darlo a quien ya lo tiene)
		{ Id = "Resonance10", Title = "Maestro armero", Description = "Lleva un arma, guante o bastón al nivel 10.", Goal = { Source = "State", Key = "WeaponLevel" }, Target = 10, Reward = { Min = 60, Max = 200 } },
		{ Id = "FirstRebirth", Title = "Renacido", Description = "Renace por primera vez.", Goal = { Source = "State", Key = "Rebirths" }, Target = 1, Reward = { Min = 100, Max = 800 } },
		{ Id = "Reborn5", Title = "Ciclo eterno", Description = "Renace 5 veces.", Goal = { Source = "State", Key = "Rebirths" }, Target = 5, Reward = { Min = 400, Max = 4000 } },
	},
}

return QuestConfig
