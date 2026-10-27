-- Los ocho núcleos elementales. Solo datos: la lógica está en CoreLogic (servidor).
-- CoreService (servidor) desbloquea, mejora y elige núcleos con 💎; el elemento
-- seleccionado (Q) y el secundario (R) dan sus habilidades de combate (AbilityConfig /
-- AbilityService) y su nivel sube la maestría de esas habilidades. Los núcleos ya NO
-- producen nada (la energía y el Cristal del Renacimiento se quitaron).
--
-- - Ocho elementos, en este orden: Naturaleza, Agua, Fuego, Viento, Rayo, Hielo, Sombra
--   y Celestial.
-- - Naturaleza está desbloqueada desde el principio y no tiene nivel; los otros siete se
--   desbloquean pagando 💎 diamantes (en el código, Energy), con costes crecientes. Sus
--   mejoras también se pagan con 💎; cambiar de elemento es gratis (solo tiene
--   enfriamiento).
-- - Los parámetros marcados [PROVISIONAL] son puntos de partida, no un balance definitivo.

local CoreConfig = {
	-- Orden de los elementos (el índice define su escalón de coste).
	Order = { "Nature", "Water", "Fire", "Wind", "Lightning", "Ice", "Shadow", "Celestial" },
	DefaultElement = "Nature",

	Elements = {
		Nature = { DisplayName = "Naturaleza" },
		Water = { DisplayName = "Agua" },
		Fire = { DisplayName = "Fuego" },
		Wind = { DisplayName = "Viento" },
		Lightning = { DisplayName = "Rayo" },
		Ice = { DisplayName = "Hielo" },
		Shadow = { DisplayName = "Sombra" },
		Celestial = { DisplayName = "Celestial" },
	},

	-- Desbloqueo del núcleo en la posición k del orden (k = 2..8):
	--   coste = BaseCost · Growth^(k - 2)   [💎]
	-- [PROVISIONAL] ×2 por núcleo: 300, 600, 1 200, 2 400, 4 800, 9 600 y 19 200 💎.
	Unlock = {
		BaseCost = 300,
		Growth = 2,
		-- [PROVISIONAL, comportamiento explícito] Desbloqueo secuencial: para desbloquear
		-- un núcleo hacen falta todos los anteriores del orden (no se puede saltar ninguno).
		Sequential = true,
	},

	-- Núcleos distintos de Naturaleza (que no tiene nivel). Núcleo en la posición k, nivel n:
	--   coste de subir al nivel n + 1 = floor(BaseUpgradeCost · TierMultiplier^(k - 1) · CostGrowth^n)
	-- [PROVISIONAL] Coste en 💎: 6 · 2^(k-1) · 1,15^n (Agua: 12 el nivel 1, ~50 el 10, ~200
	-- el 20); cada núcleo cuesta el doble que el anterior.
	Upgrade = {
		BaseUpgradeCost = 6,
		CostGrowth = 1.15,
		TierMultiplier = 2,
		MaxLevel = 50,
	},

	-- Cambio de elemento seleccionado: cuesta MinCost 💎 (gratis: los 💎 son para
	-- habilidades), con un enfriamiento de 10 s para evitar cambios en ráfaga.
	Switch = {
		MinCost = 0,
		CooldownSeconds = 10,
	},

	-- Topes de seguridad para datos guardados y entradas.
	MaxMastery = 1e12,
}

return CoreConfig
