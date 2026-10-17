-- Zonas del mundo y portales entre ellas. Configuración centralizada del precio de
-- desbloqueo, puntos de llegada y límites de cada zona.
--
-- Posiciones RELATIVAS al Cristal del Renacimiento (GeneratorConfig.Position), en X/Z.
-- Cada zona tiene un centro; sus puntos (llegada, portales) son relativos a ese centro.
--
-- Precio del Valle (2 500): con las fórmulas actuales (mejora N = 10·1.5^N, producción
-- 1 + N), un jugador llega al nivel 10 hacia el minuto 3 y reúne 2 500 en ~3 min más
-- (~13/s con dos mascotas comunes). Es un objetivo de progresión sin espera excesiva.

local ZoneConfig = {
	DefaultZone = "Forest",

	Zones = {
		Forest = {
			DisplayName = "Bosque Inicial",
			Center = Vector2.new(0, 0),
			UnlockCost = 0, -- siempre disponible
			-- Llegada al volver: junto al portal del bosque, mirando al cristal (-Z).
			Arrival = Vector3.new(0, 0, 44),
			ArrivalFacing = Vector3.new(0, 0, -1),
			Radius = 320, -- radio horizontal que ocupa la zona
		},
		CrystalValley = {
			DisplayName = "Valle Cristalino",
			-- Lejos del bosque (su terreno acaba en ±310) para que no se vean ni se solapen.
			Center = Vector2.new(1400, 0),
			UnlockCost = 2500,
			Arrival = Vector3.new(0, 0, 44),
			ArrivalFacing = Vector3.new(0, 0, -1),
			Radius = 260,
		},
	},

	-- Portales: dónde están (zona + desplazamiento) y a qué zona llevan.
	Portals = {
		ForestPortal = {
			Zone = "Forest",
			Offset = Vector2.new(0, 56), -- al final del camino, detrás del spawn
			Target = "CrystalValley",
			Style = "Ancient",
		},
		ValleyPortal = {
			Zone = "CrystalValley",
			Offset = Vector2.new(0, 58),
			Target = "Forest",
			Style = "Return",
		},
	},

	-- Distancia máxima (horizontal) a un portal para desbloquear o viajar.
	InteractDistance = 18,
	-- Segundos mínimos entre viajes y entre intentos de desbloqueo de un jugador.
	TravelCooldown = 2,
	UnlockCooldown = 1,
}

return ZoneConfig
