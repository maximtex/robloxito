-- Premio diario (racha de 7 días) y códigos canjeables. Lo decide todo el servidor
-- (RewardService con RewardLogic); el cliente solo lo lee para mostrar los premios.
--
-- Racha:
-- - Un premio por día. El día cambia a las 00:00 UTC, igual que las misiones diarias
--   (QuestConfig.DaySeconds): en Colombia, a las 7 de la noche.
-- - Reclamar el día siguiente sube la racha; si pasa un día entero sin reclamar, vuelve al
--   día 1. Tras el día 7 empieza otra vuelta (lo ya conseguido no se pierde).
--
-- Cómo se escribe un premio (sirve igual para la racha y para los códigos):
--   Energy = { Minutes = 10, Min = 500 }  -> energía de N minutos de TU producción actual,
--                                            nunca menos de Min (así vale lo mismo al
--                                            empezar que con mucho avance).
--   Blessings = { Abundance = 1 }         -> bendiciones de las aventuras (se guardan y se
--                                            activan cuando se quiere desde 🧿 Amuletos).
--   Pet = true                            -> una mascota del mejor huevo que ya puedas abrir
--                                            (si el inventario está lleno, su precio en energía).

local RewardConfig = {
	DaySeconds = 86400,

	Streak = {
		{ Energy = { Minutes = 10, Min = 500 } },
		{ Energy = { Minutes = 20, Min = 1500 } },
		{ Blessings = { Abundance = 1 } },
		{ Energy = { Minutes = 40, Min = 4000 } },
		{ Blessings = { Fortune = 1, Fury = 1 } },
		{ Energy = { Minutes = 60, Min = 8000 } },
		{ Energy = { Minutes = 90, Min = 15000 }, Pet = true }, -- gran premio del día 7
	},

	-- Abrir el panel solo al entrar si hay premio sin reclamar (después del tutorial).
	AutoOpen = true,
	AutoOpenDelay = 4, -- segundos tras cargar los datos

	-- Códigos (la lista vive en el servidor: src/server/CodesConfig.luau, para que nadie
	-- pueda leer los que aún no se han anunciado).
	Codes = {
		MaxLength = 24,
		Cooldown = 2, -- segundos entre intentos
		MaxPerMinute = 8, -- intentos por minuto (contra probar códigos al azar)
		MaxStored = 200, -- códigos canjeados que se recuerdan por jugador
	},
}

return RewardConfig
