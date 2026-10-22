-- Zonas del mundo y puertas de energía entre ellas. Configuración centralizada del precio de
-- desbloqueo, puntos de llegada y límites de cada zona.
-- Para abrir una zona: derrotar al jefe de la anterior (RequiredBoss, tipo de EnemyConfig;
-- se cuenta en PetData.Bosses), los renacimientos que pida y pagar su energía.
--
-- Los 3 mapas son cuadrados de 320×320 (halfSpan = 160) pegados de forma continua en +Z
-- sin puentes intermedios:
--   1. Forest:        Z = -160 .. +160 (Center Z = 0)
--   2. CrystalValley: Z = +160 .. +480 (Center Z = 320)
--   3. EmberCaldera:  Z = +480 .. +800 (Center Z = 640)

local ZoneConfig = {
	DefaultZone = "Forest",

	Zones = {
		Forest = {
			DisplayName = "Bosque Inicial",
			Center = Vector2.new(0, 0),
			UnlockCost = 0, -- siempre disponible
			Arrival = Vector3.new(0, 0, 125),
			ArrivalFacing = Vector3.new(0, 0, -1),
			Radius = 160,
		},
		CrystalValley = {
			DisplayName = "Valle Morado",
			-- Pegado directamente tras el Bosque (Z = 160..480, centro en Z = 320).
			Center = Vector2.new(0, 320),
			UnlockCost = 2500,
			RequiredBoss = "ForestWarden",
			Arrival = Vector3.new(0, 0, -132),
			ArrivalFacing = Vector3.new(0, 0, 1),
			Radius = 160,
		},
		EmberCaldera = {
			DisplayName = "Caldera de Brasas",
			-- Pegada directamente tras el Valle Morado (Z = 480..800, centro en Z = 640).
			Center = Vector2.new(0, 640),
			UnlockCost = 25000,
			RequiredRebirths = 0,
			RequiredBoss = "AmethystColossus",
			Arrival = Vector3.new(0, 0, -132),
			ArrivalFacing = Vector3.new(0, 0, 1),
			Radius = 160,
		},
	},

	-- Puertas de energía: situadas exactamente en el paso abierto del muro divisorio entre mapas.
	Portals = {
		ForestPortal = {
			Zone = "Forest",
			Offset = Vector2.new(0, 160), -- justo en la frontera Z = 160 entre Bosque y Valle Morado
			Target = "CrystalValley",
			Style = "Ancient",
		},
		CalderaPortal = {
			Zone = "CrystalValley",
			Offset = Vector2.new(0, 160), -- justo en la frontera Z = 480 (320 + 160) entre Valle y Caldera
			Target = "EmberCaldera",
			Style = "Ember",
		},
	},

	PortalScale = 3.2,
	PortalRadius = 15.5,

	-- Distancia máxima (horizontal) a una puerta para desbloquear o viajar.
	InteractDistance = 28,
	-- Segundos mínimos entre viajes y entre intentos de desbloqueo de un jugador.
	TravelCooldown = 2,
	UnlockCooldown = 1,
}

return ZoneConfig
