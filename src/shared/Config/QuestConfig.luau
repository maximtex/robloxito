-- Misiones, misiones diarias y logros. Para añadir una basta con una entrada nueva aquí:
-- la lógica (QuestLogic) es la misma para todas.
--
-- Goal: de dónde sale el progreso (siempre de datos del servidor):
--   { Source = "Stat", Key = ... }   estadística permanente registrada por el servidor:
--       Kills, StrongKills, BossKills, EnergyEarned (producción + recompensas de enemigos;
--       NUNCA incluye recompensas de misiones), PetAbilities.
--   { Source = "ZoneKills", Zone = ... }   enemigos derrotados en una zona.
--   { Source = "BossTypes" }   jefes distintos derrotados al menos una vez.
--   { Source = "State", Key = ... }   estado actual del perfil: UpgradeLevel, PetsOwned,
--       PetsEquipped, CombatPetsOwned, ZonesUnlocked (zonas compradas).
--   { Source = "Daily", Event = "Kill" | "Energy" | "PetAbility", Kind?, Zone? }
--       contador del día (solo para misiones diarias).
-- RequiresZone: no se muestra como alcanzable (ni se ofrece como diaria) sin esa zona.
-- RequiresCombatPet: solo se ofrece como diaria si el jugador tiene una mascota de combate.
--
-- Recompensa (energía, la calcula el servidor al reclamar):
--   clamp(Share · coste de la siguiente mejora del jugador, Min, Max)
-- Así acompaña a la etapa actual sin dispararse (Max). Referencia de la economía actual:
--   mejora 5 = 75, 8 = 256, 10 = 576, 12 = 1 297, 15 = 4 378; Valle = 2 500;
--   Guardián del Bosque = 1 200 cada 3 min; Coloso = 4 000 cada 4 min.
-- Las tres diarias juntas dan como mucho 6 000 al día (el peor caso: Patrulla + Valle +
-- Jefe con los topes): ~1,5 Colosos, muy por debajo de una sesión normal de juego.
-- Los logros que coinciden con una misión (primer enemigo, primer jefe, primera mascota,
-- primera zona) no dan energía: la misma acción nunca se premia dos veces.

local QuestConfig = {
	DailyCount = 3,
	DailyAlways = { "DailyHunt" }, -- siempre entre las diarias del día
	DaySeconds = 86400, -- las diarias cambian a las 00:00 UTC (hora del servidor)
	RewardUpgradeId = "GeneratorPower",
	MaxIdLength = 64,
	ClaimRateLimit = { Cooldown = 0.25, WindowSeconds = 2, MaxPerWindow = 8 },
	RequestRateLimit = { Cooldown = 1, WindowSeconds = 5, MaxPerWindow = 6 },
	PushInterval = 2, -- como mucho un envío de estado cada 2 s por jugador (salvo al reclamar)

	-- Misiones de una sola vez (en orden de progresión)
	Missions = {
		{
			Id = "BuyUpgrade",
			Title = "Despierta el cristal",
			Description = "Compra una mejora de Resonancia del Cristal.",
			Goal = { Source = "State", Key = "UpgradeLevel" },
			Target = 1,
			Reward = { Min = 20, Share = 1, Max = 200 },
		},
		{
			Id = "DefeatFive",
			Title = "Primeros pasos de cazador",
			Description = "Derrota a 5 enemigos.",
			Goal = { Source = "Stat", Key = "Kills" },
			Target = 5,
			Reward = { Min = 40, Share = 1, Max = 400 },
		},
		{
			Id = "FirstPet",
			Title = "Un nuevo amigo",
			Description = "Consigue tu primera mascota en un santuario de huevos.",
			Goal = { Source = "State", Key = "PetsOwned" },
			Target = 1,
			Reward = { Min = 60, Share = 1, Max = 500 },
		},
		{
			Id = "EquipPet",
			Title = "Compañero de viaje",
			Description = "Equipa una mascota.",
			Goal = { Source = "State", Key = "PetsEquipped" },
			Target = 1,
			Reward = { Min = 30, Share = 0.5, Max = 300 },
		},
		{
			Id = "DefeatStrong",
			Title = "Más duro que la corteza",
			Description = "Derrota a un enemigo fuerte.",
			Goal = { Source = "Stat", Key = "StrongKills" },
			Target = 1,
			Reward = { Min = 100, Share = 1, Max = 800 },
		},
		{
			Id = "EarnEnergy",
			Title = "Corriente de energía",
			Description = "Genera 2.000 de energía (cristal y combates).",
			Goal = { Source = "Stat", Key = "EnergyEarned" },
			Target = 2000,
			Reward = { Min = 150, Share = 1, Max = 1000 },
		},
		{
			Id = "UnlockValley",
			Title = "Más allá del portal",
			Description = "Desbloquea el Valle Cristalino.",
			Goal = { Source = "State", Key = "ZonesUnlocked" },
			Target = 1,
			Reward = { Min = 400, Share = 1, Max = 2500 },
		},
		{
			Id = "FirstBoss",
			Title = "Caída de un gigante",
			Description = "Derrota a tu primer jefe.",
			Goal = { Source = "Stat", Key = "BossKills" },
			Target = 1,
			Reward = { Min = 300, Share = 1.5, Max = 3000 },
		},
		{
			Id = "ValleyHunter",
			Title = "Eco del Valle",
			Description = "Derrota a 10 enemigos del Valle Cristalino.",
			Goal = { Source = "ZoneKills", Zone = "CrystalValley" },
			Target = 10,
			RequiresZone = "CrystalValley",
			Reward = { Min = 600, Share = 1, Max = 3000 },
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
			Reward = { Min = 100, Share = 1, Max = 1500 },
		},
		{
			Id = "DailyStrong",
			Title = "Prueba de fuerza",
			Description = "Derrota a 2 enemigos fuertes.",
			Goal = { Source = "Daily", Event = "Kill", Kind = "Strong" },
			Target = 2,
			Reward = { Min = 150, Share = 1, Max = 1500 },
		},
		{
			Id = "DailyEnergy",
			Title = "Cosecha de energía",
			Description = "Genera 2.500 de energía (cristal y combates).",
			Goal = { Source = "Daily", Event = "Energy" },
			Target = 2500,
			Reward = { Min = 120, Share = 0.8, Max = 1200 },
		},
		{
			Id = "DailyPets",
			Title = "Trabajo en equipo",
			Description = "Tus mascotas de combate aciertan 30 habilidades.",
			Goal = { Source = "Daily", Event = "PetAbility" },
			Target = 30,
			RequiresCombatPet = true,
			Reward = { Min = 150, Share = 1, Max = 1500 },
		},
		{
			Id = "DailyValley",
			Title = "Ronda por el Valle",
			Description = "Derrota a 12 enemigos del Valle Cristalino.",
			Goal = { Source = "Daily", Event = "Kill", Zone = "CrystalValley" },
			Target = 12,
			RequiresZone = "CrystalValley",
			Reward = { Min = 300, Share = 1, Max = 2000 },
		},
		{
			Id = "DailyBoss",
			Title = "Cazador de leyendas",
			Description = "Derrota a un jefe.",
			Goal = { Source = "Daily", Event = "Kill", Kind = "Boss" },
			Target = 1,
			RequiresZone = "CrystalValley", -- a partir de la etapa media
			Reward = { Min = 400, Share = 1.5, Max = 2500 },
		},
	},

	-- Logros permanentes: se desbloquean solos (una vez) al cumplirse.
	Achievements = {
		{ Id = "FirstBlood", Title = "Primer enemigo", Description = "Derrota a tu primer enemigo.", Goal = { Source = "Stat", Key = "Kills" }, Target = 1 },
		{ Id = "Hunter100", Title = "Cazador", Description = "Derrota a 100 enemigos.", Goal = { Source = "Stat", Key = "Kills" }, Target = 100, Reward = { Min = 300, Share = 1, Max = 3000 } },
		{ Id = "Hunter500", Title = "Leyenda del bosque", Description = "Derrota a 500 enemigos.", Goal = { Source = "Stat", Key = "Kills" }, Target = 500, Reward = { Min = 1000, Share = 2, Max = 8000 } },
		{ Id = "FirstBoss", Title = "Primer jefe", Description = "Derrota a un jefe.", Goal = { Source = "Stat", Key = "BossKills" }, Target = 1 },
		{ Id = "BossHunter", Title = "Cazajefes", Description = "Derrota a 5 jefes.", Goal = { Source = "Stat", Key = "BossKills" }, Target = 5, Reward = { Min = 1000, Share = 2, Max = 8000 } },
		{ Id = "BothBosses", Title = "Domador de colosos", Description = "Derrota al Guardián del Bosque y al Coloso de Amatista.", Goal = { Source = "BossTypes" }, Target = 2, Reward = { Min = 1500, Share = 2, Max = 8000 } },
		{ Id = "FirstPet", Title = "Primera mascota", Description = "Consigue una mascota.", Goal = { Source = "State", Key = "PetsOwned" }, Target = 1 },
		{ Id = "Collector", Title = "Coleccionista", Description = "Ten 10 mascotas.", Goal = { Source = "State", Key = "PetsOwned" }, Target = 10, Reward = { Min = 500, Share = 1, Max = 4000 } },
		{ Id = "CombatPet", Title = "Guardián de cristal", Description = "Consigue una mascota de combate.", Goal = { Source = "State", Key = "CombatPetsOwned" }, Target = 1, Reward = { Min = 500, Share = 1, Max = 4000 } },
		{ Id = "NewHorizon", Title = "Nuevo horizonte", Description = "Desbloquea una zona nueva.", Goal = { Source = "State", Key = "ZonesUnlocked" }, Target = 1 },
		{ Id = "Resonance10", Title = "Resonancia plena", Description = "Lleva la Resonancia del Cristal al nivel 10.", Goal = { Source = "State", Key = "UpgradeLevel" }, Target = 10, Reward = { Min = 300, Share = 0.5, Max = 1000 } },
	},
}

return QuestConfig
