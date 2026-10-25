-- Los ocho núcleos elementales. Solo datos: la lógica está en CoreLogic (servidor).
-- FASE 2: conectado. CoreService (servidor) desbloquea, mejora y elige núcleos; todos los
-- desbloqueados producen energía (PlayerDataService) y al entrar se concede la producción
-- offline. Mientras solo esté Naturaleza, la economía es exactamente la de siempre.
-- El elemento seleccionado da su habilidad de combate (AbilityConfig / AbilityService).
--
-- DECISIONES APROBADAS
-- - Ocho elementos, en este orden: Naturaleza, Agua, Fuego, Viento, Rayo, Hielo, Sombra
--   y Celestial.
-- - Naturaleza ES el cristal actual: su nivel es UpgradeLevels.GeneratorPower y su
--   producción y coste son los de Economy/EconomyConfig. Aquí NO se duplica.
-- - Naturaleza está desbloqueada desde el principio; los otros siete se desbloquean
--   pagando 💎 diamantes (en el código, Energy), con costes crecientes. Sus mejoras también
--   se pagan con 💎; cambiar de elemento es gratis (solo tiene enfriamiento).
-- - Todos los núcleos desbloqueados producirán energía pasiva (en una fase futura); solo
--   el elemento seleccionado habilitará sus habilidades.
-- - Las mascotas multiplican la producción de TODOS los núcleos desbloqueados, una sola
--   vez sobre la suma: total = (Σ producción base) · multiplicador de mascotas.
-- - Producción offline: (Σ producción base) · mascotas · 50 %, con un máximo de 4 horas
--   de ausencia (aún sin conectar).
-- - La energía offline NO cuenta para las misiones de "generar energía".
--
-- PARÁMETROS PROVISIONALES (marcados con [PROVISIONAL]): son puntos de partida
-- razonados a partir de la economía actual, NO un balance definitivo. Falta telemetría
-- real (duración de sesiones, nivel típico de los jugadores) para fijarlos.
-- Referencias de la economía actual (EconomyConfig):
--   mejora del cristal N cuesta 10 · 1,5^N (N = 10: 576; N = 15: 4 378; N = 20: 33 252)
--   y produce (1 + N) ⚡/s; Valle Cristalino 2 500; huevos 100, 750, 5 000 y 8 000.

local CoreConfig = {
	-- Orden de los elementos (el índice define su escalón de coste y producción).
	Order = { "Nature", "Water", "Fire", "Wind", "Lightning", "Ice", "Shadow", "Celestial" },
	DefaultElement = "Nature",

	Elements = {
		Nature = {
			DisplayName = "Naturaleza",
			-- Su nivel y su producción son los de esta mejora existente (no se duplican).
			UpgradeId = "GeneratorPower",
		},
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

	-- Núcleos distintos de Naturaleza (Naturaleza usa EconomyConfig.Upgrades.GeneratorPower).
	-- Núcleo en la posición k, nivel n:
	--   producción = BaseProduction · TierMultiplier^(k - 1) · (1 + n)    [⚡/s]
	--   coste de subir al nivel n + 1 = floor(BaseUpgradeCost · TierMultiplier^(k - 1) · CostGrowth^n)
	-- [PROVISIONAL] Coste en 💎: 6 · 2^(k-1) · 1,15^n (Agua: 12 el nivel 1, ~50 el 10, ~200
	-- el 20); cada núcleo produce y cuesta el doble que el anterior.
	Upgrade = {
		BaseProduction = 1,
		BaseUpgradeCost = 6,
		CostGrowth = 1.15,
		TierMultiplier = 2,
		MaxLevel = 50,
	},

	-- Cambio de elemento seleccionado:
	--   coste = max(MinCost, floor(ProductionSeconds · producción base total))
	-- Gratis (los 💎 son para habilidades), con un enfriamiento de 10 s para evitar cambios
	-- en ráfaga.
	Switch = {
		MinCost = 0,
		ProductionSeconds = 0,
		CooldownSeconds = 10,
	},

	-- Producción offline (aún NO se concede: solo se calcula en CoreLogic).
	--   recompensa = floor(min(ausencia, CapSeconds) · Σ producción base · mascotas · Efficiency)
	Offline = {
		CapSeconds = 4 * 60 * 60, -- APROBADO: 4 horas
		Efficiency = 0.5, -- APROBADO: 50 %
		IncludePetMultiplier = true, -- APROBADO: las mascotas cuentan (una sola vez)
	},

	-- Afinidad: además de su habilidad (AbilityConfig), el núcleo SELECCIONADO produce extra:
	--   producción del núcleo seleccionado · (1 + Bonus)
	-- [PROVISIONAL] +25 %. Naturaleza no recibe afinidad (es el cristal: la economía de
	-- siempre no cambia); empieza al elegir otro núcleo pagando el cambio (Switch). La
	-- producción offline usa la producción base, sin afinidad (como se aprobó).
	Affinity = {
		Bonus = 0.25,
	},

	-- Topes de seguridad para datos guardados y entradas.
	MaxMastery = 1e12,
	-- Multiplicador de mascotas máximo aceptado (el real del juego no pasa de ×7); por
	-- encima se considera no válido (×1) para que la producción no pueda desbordarse.
	MaxPetMultiplier = 1000,
}

return CoreConfig
