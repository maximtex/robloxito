-- Códigos canjeables (solo servidor: el cliente no puede leer esta lista, así que los
-- códigos que aún no anuncies no se filtran).
--
-- Cada código se canjea UNA vez por jugador. Se escriben en MAYÚSCULAS, solo letras y
-- números (el jugador puede escribirlos en minúsculas o con espacios: se normalizan).
--   Reward       = premio, con el mismo formato que la racha (RewardConfig):
--                  Energy = { Minutes, Min }, Blessings = { Id = n }, Pet = true
--   Until        = { Year, Month, Day } último día válido (hora UTC, hasta las 23:59:59).
--                  Sin Until, el código no caduca.
--   MinRebirths  = renacimientos mínimos para canjearlo (opcional).
--
-- Para añadir uno: copia una línea, cámbiale el nombre y publícalo en tus redes.

return {
	BIENVENIDO = {
		Reward = { Energy = { Minutes = 15, Min = 1000 }, Blessings = { Abundance = 1 } },
	},
	REBIRTH = {
		Reward = { Blessings = { Fortune = 1, Fury = 1 } },
	},
	CALDERA = {
		Reward = { Energy = { Minutes = 30, Min = 5000 } },
		MinRebirths = 1,
		Until = { Year = 2027, Month = 1, Day = 31 },
	},
}
