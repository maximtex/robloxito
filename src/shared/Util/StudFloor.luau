--!strict
-- Configuración de los mapas de bloques (Bosque, Valle Morado y Caldera de Brasas) y paleta
-- sRGB exacta de los bloques del diseño:
-- suelo_greenLight.glb, suelo_greenDark.glb, suelo_grayLight.glb, suelo_grayDark.glb, suelo_border.glb
-- Lo construye Server.Util.StudWorld.
local StudFloor = {}

local RGB = Color3.fromRGB

StudFloor.BlockSize = 8
-- Borde de los caminos (y de las orillas del río y la lava): una fila entera de studs del
-- camino (4 por bloque de 8, de 2 studs cada uno), como la referencia. Con 1 se veían medios
-- studs, como una raya gris.
StudFloor.BorderWidth = 2
StudFloor.BaseTop = 0.28
StudFloor.BaseThickness = 1.0
-- Los caminos y sus bordes sobresalen esto del damero, como en la referencia; lo que se apoya
-- en un camino sube lo mismo (StudFloor.raiseAt).
StudFloor.PathRaise = 0.5
StudFloor.FolderName = "StudFloor"

-- Texturas de la cara superior (studs en relieve suave de suelo_*.glb), todas reflejadas en
-- horizontal porque Roblox gira 180° la textura de la cara Top:
-- - Zones.*.GrassTexture: damero de losetas de 4x4 studs, un stud por stud; cubre GrassTile.
-- - Zones.*.PathTexture: camino en damero de bloques de 8x8 en dos tonos casi iguales, con
--   4x4 studs por bloque (como la referencia); cubre PathTile (2x2 bloques).
-- - StudTexture: solo los studs (luz y sombra sobre transparente) para el color del borde,
--   al mismo tamaño que los del camino (cubre 8 studs de la imagen, estirada a PathTile).
StudFloor.StudTexture = "rbxassetid://109441301720998"
StudFloor.GrassTile = 8
StudFloor.PathTile = 16

-- Muros de damero como la referencia: losetas cuadradas de 8x8 (alineadas con los bloques del
-- suelo) de tierra abajo y una capa gruesa de hierba arriba que cuelga en escalones. El grosor
-- (8) hace que el muro sur de una zona acabe justo donde empieza el suelo de la siguiente.
-- BaseRows + TopRows: filas del muro (y alto del cristal de los portales, ZoneService).
-- StudSize: tamaño de los studs de StudTexture en sus caras (4x4 por loseta, como el camino).
-- GrassRows: filas de hierba de cada columna (cambia como mucho una fila de una a la
-- siguiente); BumpChance: tramos de 2 o 3 columnas una fila más altos (nunca junto al portal).
-- Relieve: la hierba sobresale GrassOverhang studs hacia dentro (un alero por encima de la
-- tierra, con el borde en escalones) y, en los muros que no tienen otra zona detrás, algunos
-- tramos (TierChance) suben 1 a TierRows filas más de hierba un grosor más atrás.
StudFloor.Wall = {
	Thickness = 8,
	BlockWidth = 8,
	BlockHeight = 8,
	BaseRows = 6,
	TopRows = 3,
	StudSize = 2,
	GrassRows = { 2, 4 },
	BumpChance = 0.12,
	GrassOverhang = 4,
	TierChance = 0.5,
	TierRows = 2,
}

-- Paleta sRGB exacta extraída de los archivos .glb
StudFloor.Palette = {
	GreenLight = RGB(168, 200, 62),
	GreenDark = RGB(102, 175, 6),
	GrayLight = RGB(208, 156, 187),
	GrayDark = RGB(146, 93, 137),
}

-- Mapas en coordenadas del mundo. Los límites y los caminos son bordes de bloque: los bloques
-- de 8 están centrados en múltiplos de 8, así que todos los bordes caen en 8k ± 4.
-- Paths: { MinX, MaxX, MinZ, MaxZ } de caminos y plazas, con borde donde tocan el suelo; lo
-- demás es damero. Pueden salirse de los límites por el paso de un muro.
-- GrassTexture / PathTexture: el damero del suelo (GroundA / GroundB) y el de los caminos (en
-- tonos de Path); GroundA y Path son también el color de los lados.
-- Walls: North / South dicen si la zona pone ese muro (el muro sur de una zona hace de muro
-- norte de la siguiente) y GateHalf es el medio ancho del paso del muro sur para el portal.
StudFloor.Zones = {
	-- Bosque Inicial: el pueblo, el Jardín de los Huevos en su patio al sureste de la plaza,
	-- las praderas de enemigos (el Guardián, sobre la hierba) y los ocho cofres escondidos.
	-- El portal al Valle (Z = 135) queda en el paso del muro sur.
	Forest = {
		MinX = -132,
		MaxX = 132,
		MinZ = -172,
		MaxZ = 132,
		Colors = {
			GroundA = StudFloor.Palette.GreenLight,
			GroundB = StudFloor.Palette.GreenDark,
			Path = StudFloor.Palette.GrayLight,
			Border = StudFloor.Palette.GrayDark,
		},
		-- Píxeles literales de suelo_greenLight.glb y suelo_greenDark.glb; el camino, de suelo_grayLight.glb
		GrassTexture = "rbxassetid://102683223562470",
		PathTexture = "rbxassetid://126337185333576",
		Walls = {
			North = true,
			South = true,
			GateHalf = 28,
			Base = { RGB(216, 132, 88), RGB(190, 104, 64) }, -- terracota, como la referencia
			Top = { StudFloor.Palette.GreenLight, StudFloor.Palette.GreenDark },
		},
		-- Borde a medida (maqueta «Zona 1 — Bosque», simétrica): filas de norte a sur con
		-- { Z desde, Z hasta, medio ancho del suelo }. Lo de fuera hasta el rectángulo es una
		-- colina de bloques (StudWorld.buildWalls). La fila del medio mide lo de siempre y la del
		-- sur llega al paso del portal.
		Outline = {
			{ -164, -156, 92 },
			{ -156, -60, 100 },
			{ -60, -52, 108 },
			{ -52, -20, 124 },
			{ -20, 4, 132 },
			{ 4, 36, 124 },
			{ 36, 60, 116 },
			{ 60, 92, 108 },
			{ 92, 100, 100 },
			{ 100, 108, 92 },
			{ 108, 116, 76 },
			{ 116, 124, 60 },
			{ 124, 132, 44 },
		},
		Paths = {
			{ -44, 44, -28, 28 }, -- plaza del pueblo: spawn y puestos (X = ±36)
			{ 28, 60, 36, 84 }, -- patio del Jardín de los Huevos (6 bloques de ancho)
			{ 12, 28, 52, 68 }, -- pasillo de 2 bloques del patio a la avenida sur, con hierba a los lados
			{ -12, 12, 28, 108 }, -- avenida sur hacia el portal del Valle
			{ -28, 28, 108, 140 }, -- plazoleta del portal (entra en el paso del muro)
			{ -140, -44, 12, 28 }, -- camino de la cueva: de la plaza a la boca (Cave.Road)
		},
		DecorSeed = 2024,
		-- Cueva de los Espinillos, al oeste: un camino sale de la plaza del pueblo, cruza la
		-- pradera oeste y entra por una boca en la colina (la construye Server.Util.ForestCave).
		-- Al cruzar la bruma del fondo te lleva dentro de la cueva, a otro sitio (CaveConfig).
		-- Todo en coordenadas del mundo y en bordes de bloque.
		-- Road: el camino (también está en Paths, para que se dibuje con sus bordes).
		-- Opening: casillas de la colina que se vacían para la boca; Ceiling: filas de 8 de alto
		-- del hueco (encima vuelve a haber colina).
		Cave = {
			Name = "Cueva de los Espinillos",
			Road = { -140, -44, 12, 28 },
			Opening = { MinX = -140, MaxX = -124, MinZ = 12, MaxZ = 28, Ceiling = 3 },
		},
	},

	-- Valle Morado: llegada desde el Bosque, río con puente en la avenida, plaza del santuario
	-- (18, 303), Trono de Amatista (95, 330) y portal a la Caldera (Z = 455) en el muro sur.
	CrystalValley = {
		MinX = -132,
		MaxX = 132,
		MinZ = 140,
		MaxZ = 452,
		River = { MinZ = 252, MaxZ = 284, BridgeHalf = 12 },
		Colors = {
			GroundA = RGB(152, 140, 218),
			GroundB = RGB(132, 120, 198),
			Path = RGB(216, 214, 232),
			Border = RGB(78, 70, 138),
		},
		GrassTexture = "rbxassetid://137577632284745",
		PathTexture = "rbxassetid://110463584344376",
		Walls = {
			North = false,
			South = true,
			GateHalf = 28,
			Base = { RGB(78, 70, 138), RGB(58, 52, 108) },
			Top = { RGB(152, 140, 218), RGB(132, 120, 198) },
		},
		-- Borde a medida (maqueta «Zona 2 — Valle Morado», simétrica), como Forest.Outline. La
		-- fila del río ocupa lo de siempre y la del sur llega al paso del portal de la Caldera.
		Outline = {
			{ 140, 148, 44 },
			{ 148, 156, 60 },
			{ 156, 164, 76 },
			{ 164, 172, 92 },
			{ 172, 180, 100 },
			{ 180, 196, 108 },
			{ 196, 212, 116 },
			{ 212, 252, 124 },
			{ 252, 284, 132 },
			{ 284, 300, 124 },
			{ 300, 388, 132 },
			{ 388, 404, 124 },
			{ 404, 412, 116 },
			{ 412, 420, 108 },
			{ 420, 428, 100 },
			{ 428, 436, 84 },
			{ 436, 452, 60 },
		},
		-- Lo de fuera del borde son terrazas (StudWorld.buildWalls): cada escalón de 8 de fondo
		-- y más alto que el anterior; llegan Extend studs más allá del muro de siempre. El río
		-- sigue entre ellas hasta Reach: cascada al oeste y cueva al este.
		Hill = {
			Extend = 32,
			Terraces = {
				{ Height = 12, Colors = { RGB(178, 158, 232), RGB(164, 144, 222) } },
				{ Height = 28, Colors = { RGB(140, 112, 214), RGB(126, 98, 202) } },
				{ Height = 48, Colors = { RGB(108, 82, 190), RGB(96, 72, 176) } },
				{ Height = 80, Colors = { RGB(74, 56, 146), RGB(64, 48, 130) } },
			},
			Channel = { MinZ = 252, MaxZ = 284, Reach = 164 },
		},
		Paths = {
			{ -28, 28, 140, 180 }, -- llegada desde el Bosque
			{ -100, 100, 180, 204 }, -- camino de la llegada (8 studs antes del borde)
			{ -12, 12, 172, 428 }, -- avenida central (cruza el río por el puente)
			{ -36, 36, 292, 324 }, -- plaza del santuario del Huevo de Cristal
			-- Rondas oeste y este: siguen los escalones del borde, 8 studs por dentro
			{ -108, -92, 196, 220 },
			{ 92, 108, 196, 220 },
			{ -116, -100, 212, 252 },
			{ 100, 116, 212, 252 },
			{ -116, -100, 284, 308 },
			{ 100, 116, 284, 308 },
			{ -124, -108, 300, 396 },
			{ 108, 124, 300, 396 },
			{ -116, -92, 388, 412 },
			{ 92, 116, 388, 412 },
			{ -100, 100, 404, 420 }, -- camino del fondo
			{ 76, 116, 308, 348 }, -- Trono de Amatista (jefe del Valle)
			{ -28, 28, 420, 460 }, -- plazoleta del portal (entra en el paso del muro)
		},
		DecorSeed = 3031,
	},

	-- Caldera de Brasas: llegada desde el Valle, plaza de la Forja de Huevos (24, 625), lago de
	-- lava (-46, 623), Corazón de la Caldera (0, 710) y, en el muro sur, el portal a la Tundra
	-- Helada (Z = 775).
	EmberCaldera = {
		MinX = -132,
		MaxX = 132,
		MinZ = 460,
		MaxZ = 772,
		Colors = {
			GroundA = RGB(214, 114, 68),
			GroundB = RGB(188, 94, 52),
			Path = RGB(186, 160, 142),
			Border = RGB(106, 66, 50),
		},
		GrassTexture = "rbxassetid://102514480123144",
		PathTexture = "rbxassetid://75893954638467",
		Walls = {
			North = false,
			South = true,
			GateHalf = 28,
			Base = { RGB(132, 84, 64), RGB(106, 66, 50) },
			Top = { RGB(214, 114, 68), RGB(188, 94, 52) },
		},
		-- Borde a medida (maqueta «Zona 3 — Caldera de Brasas», cráter simétrico), como
		-- Forest.Outline. Arriba cierra como el final del Valle; la última fila llega al fondo.
		Outline = {
			{ 460, 476, 60 },
			{ 476, 484, 68 },
			{ 484, 492, 76 },
			{ 492, 500, 84 },
			{ 500, 508, 92 },
			{ 508, 516, 100 },
			{ 516, 532, 108 },
			{ 532, 548, 116 },
			{ 548, 572, 124 },
			{ 572, 660, 132 },
			{ 660, 684, 124 },
			{ 684, 700, 116 },
			{ 700, 708, 108 },
			{ 708, 716, 100 },
			{ 716, 724, 92 },
			{ 724, 732, 84 },
			{ 732, 740, 76 },
			{ 740, 748, 68 },
			{ 748, 756, 60 },
			{ 756, 772, 44 },
		},
		-- Paredes de roca volcánica en 5 escalones (StudWorld.buildWalls); el fondo lo cierra el
		-- muro sur con el paso del portal a la Tundra. El canal de lava a la altura del lago
		-- las cruza: cascada al oeste (sigue por el suelo hasta el lago) y a un pozo al este.
		Hill = {
			Extend = 32,
			Terraces = {
				{ Height = 12, Colors = { RGB(168, 104, 78), RGB(154, 92, 68) } },
				{ Height = 28, Colors = { RGB(132, 78, 58), RGB(118, 68, 50) } },
				{ Height = 48, Colors = { RGB(98, 58, 46), RGB(86, 50, 40) } },
				{ Height = 72, Colors = { RGB(70, 42, 36), RGB(60, 36, 30) } },
				{ Height = 104, Colors = { RGB(44, 28, 26), RGB(36, 22, 20) } },
			},
			-- OverSteps: las terrazas no se cortan; la lava baja por encima de los escalones
			-- (CalderaService.buildLavaFlows) en vez de abrir una ranura hasta Reach.
			Channel = { MinZ = 612, MaxZ = 628, Reach = 164, OverSteps = true },
		},
		Paths = {
			{ -28, 28, 460, 492 }, -- llegada desde el Valle
			{ -12, 12, 492, 684 }, -- avenida hacia el Corazón de la Caldera
			{ -100, 100, 516, 532 }, -- camino de la llegada (8 studs antes del borde)
			{ -12, 44, 604, 644 }, -- plaza de la Forja de Huevos
			-- Rondas oeste y este: siguen los escalones del borde, 8 studs por dentro
			{ -108, -92, 524, 548 },
			{ 92, 108, 524, 548 },
			{ -116, -100, 540, 580 },
			{ 100, 116, 540, 580 },
			{ -124, -108, 572, 660 },
			{ 108, 124, 572, 660 },
			{ -116, -100, 652, 684 },
			{ 100, 116, 652, 684 },
			{ -108, -92, 676, 700 },
			{ 92, 108, 676, 700 },
			{ -100, -84, 692, 708 },
			{ 84, 100, 692, 708 },
			{ -92, -76, 700, 716 },
			{ 76, 92, 700, 716 },
			{ -84, -68, 708, 724 },
			{ 68, 84, 708, 724 },
			{ -28, 28, 684, 732 }, -- Corazón de la Caldera (jefe)
			{ -76, 76, 716, 732 }, -- camino del fondo
			{ -28, 28, 732, 780 }, -- plazoleta del portal a la Tundra (entra en el paso del muro)
		},
		DecorSeed = 4047,
	},

	-- Tundra Helada (zona 4): la misma forma de cráter que la Caldera (sus filas, 320 más al
	-- sur), cubierta de nieve. Llegada desde la Caldera, plaza de los Huevos de Hielo (30, 944),
	-- lago helado (-46, 943), el Mirador del Gólem (0, 1030: una estatua de hielo; el jefe
	-- sale en las oleadas de su mazmorra) y el portal a la Fortaleza Goblin (Z = 1095) en el
	-- muro sur. Suelo: la textura del camino del Valle (casi blanca) aclarada, a 16 studs
	-- por imagen (GrassTile), y caminos de hielo con studs (StudTexture).
	FrozenTundra = {
		MinX = -132,
		MaxX = 132,
		MinZ = 780,
		MaxZ = 1092,
		Colors = {
			GroundA = RGB(236, 242, 250),
			GroundB = RGB(222, 232, 246),
			Path = RGB(150, 204, 240),
			Border = RGB(82, 128, 190),
		},
		GrassTexture = "rbxassetid://110463584344376",
		GrassTile = 16,
		GrassTint = RGB(245, 250, 255),
		PathTexture = StudFloor.StudTexture,
		Walls = {
			North = false,
			South = true,
			GateHalf = 28,
			Base = { RGB(120, 150, 200), RGB(100, 128, 180) },
			Top = { RGB(240, 246, 252), RGB(222, 234, 246) },
		},
		Outline = {
			{ 780, 796, 60 },
			{ 796, 804, 68 },
			{ 804, 812, 76 },
			{ 812, 820, 84 },
			{ 820, 828, 92 },
			{ 828, 836, 100 },
			{ 836, 852, 108 },
			{ 852, 868, 116 },
			{ 868, 892, 124 },
			{ 892, 980, 132 },
			{ 980, 1004, 124 },
			{ 1004, 1020, 116 },
			{ 1020, 1028, 108 },
			{ 1028, 1036, 100 },
			{ 1036, 1044, 92 },
			{ 1044, 1052, 84 },
			{ 1052, 1060, 76 },
			{ 1060, 1068, 68 },
			{ 1068, 1076, 60 },
			{ 1076, 1092, 44 },
		},
		-- Montañas nevadas en 5 escalones, de la nieve al hielo azul oscuro
		Hill = {
			Extend = 32,
			Terraces = {
				{ Height = 12, Colors = { RGB(238, 244, 250), RGB(226, 236, 246) } },
				{ Height = 28, Colors = { RGB(206, 224, 242), RGB(190, 212, 236) } },
				{ Height = 48, Colors = { RGB(160, 190, 226), RGB(146, 178, 218) } },
				{ Height = 72, Colors = { RGB(120, 150, 200), RGB(108, 138, 190) } },
				{ Height = 104, Colors = { RGB(86, 108, 160), RGB(76, 96, 146) } },
			},
		},
		Paths = {
			{ -28, 28, 780, 812 }, -- llegada desde la Caldera
			{ -12, 12, 812, 1052 }, -- avenida hacia el Mirador del Gólem
			{ -100, 100, 836, 852 }, -- camino de la llegada (8 studs antes del borde)
			{ -12, 52, 924, 964 }, -- plaza de los Huevos de Hielo
			-- Rondas oeste y este: siguen los escalones del borde, 8 studs por dentro
			{ -108, -92, 844, 868 },
			{ 92, 108, 844, 868 },
			{ -116, -100, 860, 900 },
			{ 100, 116, 860, 900 },
			{ -124, -108, 892, 980 },
			{ 108, 124, 892, 980 },
			{ -116, -100, 972, 1004 },
			{ 100, 116, 972, 1004 },
			{ -108, -92, 996, 1020 },
			{ 92, 108, 996, 1020 },
			{ -100, -84, 1012, 1028 },
			{ 84, 100, 1012, 1028 },
			{ -92, -76, 1020, 1036 },
			{ 76, 92, 1020, 1036 },
			{ -84, -68, 1028, 1044 },
			{ 68, 84, 1028, 1044 },
			{ -28, 28, 1004, 1052 }, -- Mirador del Gólem (estatua de hielo)
			{ -76, 76, 1036, 1052 }, -- camino del fondo
			{ -28, 28, 1052, 1100 }, -- plazoleta del portal a la Fortaleza (entra en el paso del muro)
		},
		DecorSeed = 5059,
	},

	-- Fortaleza Goblin (zona 5, final del Mundo 1): un prado de musgo con campamentos goblin,
	-- la muralla con su puerta (Z = 1196 a 1204, la construye FortressService), el patio con la
	-- Sala del Trono (arena del Rey Goblin, (0, 1299)) y al fondo, sobre su tarima, el PORTAL
	-- GIGANTE al Mundo 2 (0, 1379). Sin paso en el muro sur: las rocas cierran el fondo. Suelo:
	-- el damero del Bosque oscurecido (GrassTint) y caminos de tierra (el de la Caldera, PathTint).
	GoblinFortress = {
		MinX = -132,
		MaxX = 132,
		MinZ = 1100,
		MaxZ = 1412,
		Colors = {
			GroundA = RGB(110, 150, 52),
			GroundB = RGB(86, 126, 40),
			Path = RGB(150, 124, 98),
			Border = RGB(88, 68, 50),
		},
		GrassTexture = "rbxassetid://102683223562470",
		GrassTint = RGB(190, 200, 160),
		PathTexture = "rbxassetid://75893954638467",
		PathTint = RGB(215, 198, 172),
		Walls = {
			North = false,
			South = true,
			Base = { RGB(84, 80, 74), RGB(70, 66, 62) },
			Top = { RGB(110, 150, 52), RGB(86, 126, 40) },
		},
		Outline = {
			{ 1100, 1116, 60 },
			{ 1116, 1124, 76 },
			{ 1124, 1132, 92 },
			{ 1132, 1140, 108 },
			{ 1140, 1156, 124 },
			{ 1156, 1372, 132 },
			{ 1372, 1388, 124 },
			{ 1388, 1396, 108 },
			{ 1396, 1404, 84 },
			{ 1404, 1412, 60 },
		},
		-- Rocas y riscos oscuros con musgo, que también cierran el fondo (CloseSouth)
		Hill = {
			Extend = 32,
			CloseSouth = true,
			Terraces = {
				{ Height = 12, Colors = { RGB(98, 122, 70), RGB(86, 110, 60) } },
				{ Height = 28, Colors = { RGB(112, 106, 98), RGB(100, 94, 88) } },
				{ Height = 48, Colors = { RGB(86, 82, 76), RGB(76, 72, 68) } },
				{ Height = 72, Colors = { RGB(66, 62, 58), RGB(58, 54, 50) } },
				{ Height = 104, Colors = { RGB(46, 44, 42), RGB(40, 38, 36) } },
			},
		},
		Paths = {
			{ -28, 28, 1100, 1132 }, -- llegada desde la Tundra
			{ -12, 12, 1132, 1212 }, -- camino a la puerta de la muralla
			{ -100, 100, 1148, 1164 }, -- camino de los campamentos (8 studs antes del borde)
			{ -76, 76, 1212, 1356 }, -- patio de la fortaleza (Sala del Trono en medio)
			{ -36, 36, 1356, 1404 }, -- tarima del portal gigante
		},
		DecorSeed = 6067,
		-- Muralla de la fortaleza (FortressService): de borde a borde a esta Z, con la puerta
		-- abierta (medio ancho GateHalf) frente al camino.
		Rampart = { Z0 = 1196, Z1 = 1204, GateHalf = 16 },
	},

	-- Mundo 2: el pueblo nuevo, lejos de todo (centro (2000, 0); World2Service). Plaza con los
	-- cuatro puestos, el Jardín Celestial con 3 huevos al norte y la avenida al portal de vuelta
	-- al Mundo 1 al sur (donde se llega). Cerrado por todos los lados con terrazas (CloseNorth y
	-- CloseSouth). CenterX: el borde a medida (Outline) es simétrico respecto a esta X.
	World2 = {
		CenterX = 2000,
		MinX = 1876,
		MaxX = 2124,
		MinZ = -124,
		MaxZ = 124,
		Colors = {
			GroundA = StudFloor.Palette.GreenLight,
			GroundB = StudFloor.Palette.GreenDark,
			Path = RGB(232, 222, 200),
			Border = RGB(214, 168, 64),
		},
		GrassTexture = "rbxassetid://102683223562470",
		PathTexture = "rbxassetid://110463584344376",
		PathTint = RGB(255, 246, 222),
		Walls = {
			North = false,
			South = true,
			Base = { RGB(96, 196, 200), RGB(70, 170, 180) },
			Top = { StudFloor.Palette.GreenLight, StudFloor.Palette.GreenDark },
		},
		Outline = {
			{ -124, -116, 60 },
			{ -116, -108, 84 },
			{ -108, -100, 100 },
			{ -100, -84, 108 },
			{ -84, 84, 116 },
			{ 84, 100, 108 },
			{ 100, 108, 100 },
			{ 108, 116, 84 },
			{ 116, 124, 60 },
		},
		Hill = {
			Extend = 32,
			CloseNorth = true,
			CloseSouth = true,
			Terraces = {
				{ Height = 12, Colors = { RGB(150, 226, 120), RGB(132, 212, 104) } },
				{ Height = 28, Colors = { RGB(110, 214, 200), RGB(92, 198, 186) } },
				{ Height = 48, Colors = { RGB(84, 176, 214), RGB(72, 160, 202) } },
				{ Height = 72, Colors = { RGB(110, 120, 220), RGB(96, 104, 206) } },
				{ Height = 104, Colors = { RGB(150, 110, 220), RGB(134, 96, 204) } },
			},
		},
		Paths = {
			{ 1956, 2044, -28, 28 }, -- plaza del pueblo: puestos (X = 2000 ± 36)
			{ 1964, 2036, -92, -28 }, -- Jardín Celestial (3 huevos)
			{ 1988, 2012, 28, 76 }, -- avenida al portal de vuelta (aquí se llega)
			{ 1972, 2028, 76, 116 }, -- plazoleta del portal de vuelta al Mundo 1
		},
		DecorSeed = 7079,
	},
}

-- ¿Es suelo jugable el punto (x, z) del mundo? Con borde a medida (Outline), solo lo de dentro
-- de sus filas; si no, el rectángulo de la zona. margin: studs libres alrededor (cuadrado).
function StudFloor.onFloor(layout, x: number, z: number, margin: number?): boolean
	local m = margin or 0
	for _, dx in { -m, m } do
		for _, dz in { -m, m } do
			local px, pz = x + dx, z + dz
			local inside = false
			if layout.Outline then
				for _, row in layout.Outline do
					if pz >= row[1] and pz < row[2] and math.abs(px - (layout.CenterX or 0)) < row[3] then
						inside = true
						break
					end
				end
			else
				inside = px > layout.MinX and px < layout.MaxX and pz > layout.MinZ and pz < layout.MaxZ
			end
			if not inside then
				return false
			end
		end
	end
	return true
end

-- ¿Está el punto (x, z) del mundo en la boca de la cueva de alguna zona? margin: studs de
-- más alrededor. (La cueva de dentro está lejos del mapa: Shared.CaveLogic.)
function StudFloor.inCave(x: number, z: number, margin: number?): boolean
	local m = margin or 0
	for _, zone in StudFloor.Zones do
		local cave = (zone :: any).Cave
		local r = cave and cave.Opening
		if r and x > r.MinX - m and x < r.MaxX + m and z > r.MinZ - m and z < r.MaxZ + m then
			return true
		end
	end
	return false
end

-- Altura extra del suelo en (x, z) del mundo: PathRaise sobre un camino o plaza de cualquier
-- zona y 0 sobre el damero. Se suma a la altura de lo que se coloca encima.
function StudFloor.raiseAt(x: number, z: number): number
	for _, zone in StudFloor.Zones do
		for _, r in zone.Paths do
			if x >= r[1] and x <= r[2] and z >= r[3] and z <= r[4] then
				return StudFloor.PathRaise
			end
		end
	end
	return 0
end

return StudFloor
