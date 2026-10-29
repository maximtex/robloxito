-- Zonas del mundo y puertas de energía entre ellas. Configuración centralizada del precio de
-- desbloqueo, puntos de llegada y límites de cada zona.
-- Para abrir una zona: derrotar al jefe de la anterior (RequiredBoss, tipo de EnemyConfig;
-- se cuenta en PetData.Bosses), los renacimientos que pida y pagar su precio en 💰 (UnlockCost).
--
-- MoneyPerMinute: 💰 por minuto que se gana más o menos peleando en esa zona (estimado con la
-- recompensa de su enemigo pequeño a partir de los ~700/min medidos en el Bosque). Los premios
-- "de N minutos" (premio diario, cofres, códigos: RewardLogic.moneyAmount) usan el de la mejor
-- zona abierta del jugador (ZoneLogic.bestMoneyPerMinute). Ajustable después de jugar.
--
-- Los 6 mapas del Mundo 1 son cuadrados de 320×320 (halfSpan = 160) pegados de forma
-- continua en +Z sin puentes intermedios (el pueblo, sin bichos, y detrás la Zona 1 gratis;
-- pruebas con amigos: "que el spawn sea solo el pueblo y la primera zona de pelea la de al lado"):
--   0. Forest:         Z = -160 .. +160 (Center Z = 0): el pueblo (spawn, tiendas, huevos, práctica)
--   1. ThornWoods:     Z = +160 .. +480 (Center Z = 320): Bosque de Espinas, gratis, con los
--                      bichos del Bosque y la Cueva de los Espinillos junto a la puerta del Valle
--   2. CrystalValley:  Z = +480 .. +800 (Center Z = 640)
--   3. EmberCaldera:   Z = +800 .. +1120 (Center Z = 960)
--   4. FrozenTundra:   Z = +1120 .. +1440 (Center Z = 1280)
--   5. GoblinFortress: Z = +1440 .. +1760 (Center Z = 1600): al fondo, el portal gigante al Mundo 2
-- Cada mazmorra (CaveConfig) tiene la boca junto a la puerta de la zona siguiente.
-- El Mundo 2 (World2) es un pueblo aparte, lejos (X = 2000): se llega por el portal gigante de
-- la Fortaleza (WorldPortals), que solo se abre al derrotar al Rey Goblin (RequiredBoss sin
-- precio: se desbloquea solo al matarlo, BossRewardService).
-- Sus zonas van al NORTE del pueblo (en -Z), pegadas como las del Mundo 1:
--   1. DividedLands (Tierras Divididas): Z = -480 .. -160 (centro Z = -320), mitad volcán y
--      mitad glaciar; su puerta está en el paso del norte del Jardín Celestial.

local ZoneConfig = {
	DefaultZone = "Forest",

	Zones = {
		Forest = {
			DisplayName = "Pueblo del Bosque",
			MoneyPerMinute = 700, -- 💰/min de referencia (premios por minutos)
			Center = Vector2.new(0, 0),
			UnlockCost = 0, -- siempre disponible
			Arrival = Vector3.new(0, 0, 125),
			ArrivalFacing = Vector3.new(0, 0, -1),
			Radius = 160,
		},
		-- Zona 1: la primera de pelea, gratis, pegada tras el pueblo (Z = 160..480, centro en
		-- Z = 320; ThornWoodsService). Sus bichos son los del Bosque (EnemyConfig.Zones.ThornWoods)
		-- y su mazmorra, la Cueva de los Espinillos (con las oleadas del Guardián del Bosque).
		ThornWoods = {
			DisplayName = "Bosque de Espinas",
			MoneyPerMinute = 700, -- 💰/min de referencia (premios por minutos)
			Center = Vector2.new(0, 320),
			UnlockCost = 0, -- gratis, sin jefe
			Arrival = Vector3.new(0, 0, -132),
			ArrivalFacing = Vector3.new(0, 0, 1),
			Radius = 160,
		},
		CrystalValley = {
			DisplayName = "Valle Morado",
			MoneyPerMinute = 2200, -- 💰/min de referencia (premios por minutos)
			-- Tras el Bosque de Espinas (Z = 480..800, centro en Z = 640).
			Center = Vector2.new(0, 640),
			UnlockCost = 25000, -- 💰 (antes 12 500: ~4 partidas del Bosque)
			RequiredBoss = "ForestWarden",
			Arrival = Vector3.new(0, 0, -132),
			ArrivalFacing = Vector3.new(0, 0, 1),
			Radius = 160,
		},
		EmberCaldera = {
			DisplayName = "Caldera de Brasas",
			MoneyPerMinute = 6400, -- 💰/min de referencia (premios por minutos)
			-- Pegada directamente tras el Valle Morado (Z = 800..1120, centro en Z = 960).
			Center = Vector2.new(0, 960),
			UnlockCost = 250000, -- 💰 (antes 125 000: ~10 partidas del Valle)
			RequiredRebirths = 0,
			RequiredBoss = "AmethystColossus",
			Arrival = Vector3.new(0, 0, -132),
			ArrivalFacing = Vector3.new(0, 0, 1),
			Radius = 160,
		},
		FrozenTundra = {
			DisplayName = "Tundra Helada",
			MoneyPerMinute = 20000, -- 💰/min de referencia (premios por minutos)
			-- Pegada tras la Caldera (Z = 1120..1440, centro en Z = 1280).
			Center = Vector2.new(0, 1280),
			UnlockCost = 1500000, -- 💰 (antes 600 000: ~13 partidas de la Caldera)
			RequiredBoss = "CalderaTitan",
			Arrival = Vector3.new(0, 0, -132),
			ArrivalFacing = Vector3.new(0, 0, 1),
			Radius = 160,
		},
		GoblinFortress = {
			DisplayName = "Fortaleza Goblin",
			MoneyPerMinute = 64000, -- 💰/min de referencia (premios por minutos)
			-- Pegada tras la Tundra (Z = 1440..1760, centro en Z = 1600). Final del Mundo 1.
			Center = Vector2.new(0, 1600),
			UnlockCost = 6000000, -- 💰 (antes 3 500 000: ~13 partidas de la Tundra)
			RequiredBoss = "IceGolem",
			Arrival = Vector3.new(0, 0, -132),
			ArrivalFacing = Vector3.new(0, 0, 1),
			Radius = 160,
		},
		World2 = {
			DisplayName = "Mundo 2",
			MoneyPerMinute = 64000, -- 💰/min de referencia (premios por minutos)
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
		DividedLands = {
			DisplayName = "Tierras Divididas",
			MoneyPerMinute = 160000, -- 💰/min de referencia (premios por minutos)
			World = 2,
			-- Al norte del pueblo del Mundo 2 (Z = -480..-160, centro (2000, -320) del mundo):
			-- volcán al oeste, glaciar al este, el Altar del Equilibrio en medio (el Coloso que se
			-- parte en dos) y la Grieta Elemental (mazmorra) al norte.
			Center = Vector2.new(2000, -295),
			UnlockCost = 15000000, -- 💰 (antes 20 000 000)
			RequiredBoss = "GoblinKing",
			Arrival = Vector3.new(0, 0, 100),
			ArrivalFacing = Vector3.new(0, 0, -1),
			Radius = 160,
		},
	},

	-- Puertas de energía: situadas exactamente en el paso abierto del muro divisorio entre mapas.
	Portals = {
		-- Del pueblo al Bosque de Espinas: gratis (siempre abierto)
		ForestPortal = {
			Zone = "Forest",
			Offset = Vector2.new(0, 160), -- justo en la frontera Z = 160 entre el pueblo y el Bosque de Espinas
			Target = "ThornWoods",
			Style = "Ancient",
		},
		ValleyPortal = {
			Zone = "ThornWoods",
			Offset = Vector2.new(0, 160), -- frontera Z = 480 entre el Bosque de Espinas y el Valle Morado
			Target = "CrystalValley",
			Style = "Ancient",
		},
		CalderaPortal = {
			Zone = "CrystalValley",
			Offset = Vector2.new(0, 160), -- justo en la frontera Z = 800 (640 + 160) entre Valle y Caldera
			Target = "EmberCaldera",
			Style = "Ember",
		},
		TundraPortal = {
			Zone = "EmberCaldera",
			Offset = Vector2.new(0, 160), -- frontera Z = 1120 entre la Caldera y la Tundra
			Target = "FrozenTundra",
			Style = "Frost",
		},
		FortressPortal = {
			Zone = "FrozenTundra",
			Offset = Vector2.new(0, 160), -- frontera Z = 1440 entre la Tundra y la Fortaleza
			Target = "GoblinFortress",
			Style = "Goblin",
		},
		-- Mundo 2: al NORTE del pueblo (la frontera Z = -160), al final del paso del Jardín
		-- Celestial. Se llega andando hacia -Z: su cartel mira al pueblo (ZoneService).
		DividedPortal = {
			Zone = "World2",
			Offset = Vector2.new(0, -160),
			Target = "DividedLands",
			Style = "Divided",
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
