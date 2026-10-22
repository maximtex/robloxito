--!strict
-- Configuración de los mapas de bloques (Bosque, Valle Morado y Caldera de Brasas) y paleta
-- sRGB exacta de los bloques del diseño:
-- suelo_greenLight.glb, suelo_greenDark.glb, suelo_grayLight.glb, suelo_grayDark.glb, suelo_border.glb
-- Lo construye Server.Util.StudWorld.
local StudFloor = {}

local RGB = Color3.fromRGB

StudFloor.BlockSize = 8
StudFloor.BorderWidth = 1 -- como suelo_border.glb
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

-- Muros de damero: filas de base y dos filas de remate arriba. El grosor (8) hace que el muro
-- sur de una zona acabe justo donde empieza el suelo de la siguiente.
StudFloor.Wall = {
	Thickness = 8,
	BlockWidth = 11.2,
	BlockHeight = 5.2267,
	BaseRows = 6,
	TopRows = 2,
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
			Base = { RGB(194, 140, 86), RGB(168, 118, 68) },
			Top = { StudFloor.Palette.GreenLight, StudFloor.Palette.GreenDark },
		},
		Paths = {
			{ -44, 44, -28, 28 }, -- plaza del pueblo: spawn y puestos (X = ±36)
			{ 28, 60, 36, 84 }, -- patio del Jardín de los Huevos (6 bloques de ancho)
			{ 12, 28, 52, 68 }, -- pasillo de 2 bloques del patio a la avenida sur, con hierba a los lados
			{ -12, 12, 28, 108 }, -- avenida sur hacia el portal del Valle
			{ -28, 28, 108, 140 }, -- plazoleta del portal (entra en el paso del muro)
		},
		DecorSeed = 2024,
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
		Paths = {
			{ -28, 28, 140, 172 }, -- llegada desde el Bosque
			{ -124, 124, 172, 188 }, -- camino de la llegada
			{ -12, 12, 172, 428 }, -- avenida central (cruza el río por el puente)
			{ -36, 36, 292, 324 }, -- plaza del santuario del Huevo de Cristal
			{ -124, -108, 172, 252 }, -- ronda oeste hasta el río
			{ 108, 124, 172, 252 }, -- ronda este hasta el río
			{ -124, -108, 284, 428 }, -- ronda oeste pasado el río
			{ 108, 124, 284, 428 }, -- ronda este pasado el río
			{ -124, 124, 412, 428 }, -- camino del fondo
			{ 76, 116, 308, 348 }, -- Trono de Amatista (jefe del Valle)
			{ -28, 28, 428, 460 }, -- plazoleta del portal (entra en el paso del muro)
		},
		DecorSeed = 3031,
	},

	-- Caldera de Brasas: final del corredor (sin paso en el muro sur). Llegada desde el Valle,
	-- plaza de la Forja de Huevos (24, 625), lago de lava (-46, 623) y Corazón de la Caldera
	-- (0, 710), la arena del jefe.
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
			Base = { RGB(132, 84, 64), RGB(106, 66, 50) },
			Top = { RGB(214, 114, 68), RGB(188, 94, 52) },
		},
		Paths = {
			{ -28, 28, 460, 492 }, -- llegada desde el Valle
			{ -12, 12, 492, 684 }, -- avenida hacia el Corazón de la Caldera
			{ -124, 124, 516, 532 }, -- camino de la llegada
			{ -12, 44, 604, 644 }, -- plaza de la Forja de Huevos
			{ -124, -108, 516, 748 }, -- ronda oeste
			{ 108, 124, 516, 748 }, -- ronda este
			{ -28, 28, 684, 732 }, -- Corazón de la Caldera (jefe)
			{ -124, 124, 732, 748 }, -- camino del fondo
		},
		DecorSeed = 4047,
	},
}

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
