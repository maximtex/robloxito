-- Zonas del mundo y puertas de energía entre ellas. Configuración centralizada del precio de
-- desbloqueo, puntos de llegada y límites de cada zona.
-- Para abrir una zona: derrotar al jefe de la anterior (RequiredBoss, tipo de EnemyConfig;
-- se cuenta en PetData.Bosses), los renacimientos que pida y pagar su precio en 💰 (UnlockCost).
--
-- Los 5 mapas del Mundo 1 son cuadrados de 320×320 (halfSpan = 160) pegados de forma
-- continua en +Z sin puentes intermedios:
--   1. Forest:         Z = -160 .. +160 (Center Z = 0)
--   2. CrystalValley:  Z = +160 .. +480 (Center Z = 320)
--   3. EmberCaldera:   Z = +480 .. +800 (Center Z = 640)
--   4. FrozenTundra:   Z = +800 .. +1120 (Center Z = 960)
--   5. GoblinFortress: Z = +1120 .. +1440 (Center Z = 1280): al fondo, el portal gigante al Mundo 2
-- El Mundo 2 (World2) es un pueblo aparte, lejos (X = 2000): se llega por el portal gigante de
-- la Fortaleza (WorldPortals), que solo se abre al derrotar al Rey Goblin (RequiredBoss sin
-- precio: se desbloquea solo al matarlo, BossRewardService).

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
			UnlockCost = 12500, -- 💰
			RequiredBoss = "ForestWarden",
			Arrival = Vector3.new(0, 0, -132),
			ArrivalFacing = Vector3.new(0, 0, 1),
			Radius = 160,
		},
		EmberCaldera = {
			DisplayName = "Caldera de Brasas",
			-- Pegada directamente tras el Valle Morado (Z = 480..800, centro en Z = 640).
			Center = Vector2.new(0, 640),
			UnlockCost = 125000, -- 💰
			RequiredRebirths = 0,
			RequiredBoss = "AmethystColossus",
			Arrival = Vector3.new(0, 0, -132),
			ArrivalFacing = Vector3.new(0, 0, 1),
			Radius = 160,
		},
		FrozenTundra = {
			DisplayName = "Tundra Helada",
			-- Pegada tras la Caldera (Z = 800..1120, centro en Z = 960).
			Center = Vector2.new(0, 960),
			UnlockCost = 600000, -- 💰
			RequiredBoss = "CalderaTitan",
			Arrival = Vector3.new(0, 0, -132),
			ArrivalFacing = Vector3.new(0, 0, 1),
			Radius = 160,
		},
		GoblinFortress = {
			DisplayName = "Fortaleza Goblin",
			-- Pegada tras la Tundra (Z = 1120..1440, centro en Z = 1280). Final del Mundo 1.
			Center = Vector2.new(0, 1280),
			UnlockCost = 3500000, -- 💰
			RequiredBoss = "IceGolem",
			Arrival = Vector3.new(0, 0, -132),
			ArrivalFacing = Vector3.new(0, 0, 1),
			Radius = 160,
		},
		World2 = {
			DisplayName = "Mundo 2",
			World = 2,
			-- Pueblo del Mundo 2, lejos de todo (X = 2000). Sin precio: se abre solo al derrotar al
			-- Rey Goblin (ZoneLogic.isUnlocked / BossRewardService).
			Center = Vector2.new(2000, 25),
			UnlockCost = 0,
			RequiredBoss = "GoblinKing",
			Arrival = Vector3.new(0, 0, 60),
			ArrivalFacing = Vector3.new(0, 0, -1),
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
		TundraPortal = {
			Zone = "EmberCaldera",
			Offset = Vector2.new(0, 160), -- frontera Z = 800 entre la Caldera y la Tundra
			Target = "FrozenTundra",
			Style = "Frost",
		},
		FortressPortal = {
			Zone = "FrozenTundra",
			Offset = Vector2.new(0, 160), -- frontera Z = 1120 entre la Tundra y la Fortaleza
			Target = "GoblinFortress",
			Style = "Goblin",
		},
	},

	-- Portales entre mundos (no son puertas de un muro): un arco enorme que te lleva lejos al
	-- cruzar su energía (cliente: PortalController; viaje: ZoneService). Se abren cuando su
	-- destino está desbloqueado. Offset: relativo al centro de su zona; Arrival / Facing: dónde
	-- apareces (relativo al centro de Target; sin ellos, su Arrival). Scale: tamaño del arco
	-- (Server.Util.PortalBuilder) y Style su aspecto. Radius: lo cerca que hay que pasar de
	-- su centro para cruzarlo.
	WorldPortals = {
		World2Portal = {
			Zone = "GoblinFortress",
			Offset = Vector2.new(0, 124),
			Facing = Vector3.new(0, 0, -1), -- mira a la arena del Rey Goblin (por donde se llega)
			Target = "World2",
			Title = "🌍 MUNDO 2",
			Style = "Goblin",
			Scale = 5.2,
			Radius = 9,
		},
		ReturnPortal = {
			Zone = "World2",
			Offset = Vector2.new(0, 96),
			Facing = Vector3.new(0, 0, -1), -- mira a la plaza del pueblo
			Target = "Forest",
			Arrival = Vector3.new(0, 0, 62), -- en la avenida, junto a la plaza del pueblo
			ArrivalFacing = Vector3.new(0, 0, -1),
			Title = "🌲 MUNDO 1",
			Style = "Return",
			Scale = 3.4,
			Radius = 6,
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
