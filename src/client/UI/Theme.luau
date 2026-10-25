-- Paleta, tipografías y medidas de la interfaz. Estilo simulador (la referencia que eligió
-- Santiago): paneles gris carbón con textura de studs, barra de título color arena,
-- botones rojos gruesos, contorno negro y texto blanco con borde. La comparten todos los
-- paneles.

local Theme = {
	Colors = {
		Panel = Color3.fromRGB(46, 46, 52), -- gris carbón
		PanelTransparency = 0.02,
		Stroke = Color3.fromRGB(16, 14, 18), -- contorno negro (el de los iconos)
		StrokeTransparency = 0,
		Inset = Color3.fromRGB(30, 30, 35), -- tarjetas y huecos, más oscuros que el panel
		Text = Color3.fromRGB(255, 255, 255),
		Muted = Color3.fromRGB(196, 196, 206), -- gris claro
		Accent = Color3.fromRGB(118, 224, 104), -- verde (reclamado, activo)
		Buy = Color3.fromRGB(228, 58, 50), -- botón principal: rojo
		BuyHighlight = Color3.fromRGB(150, 236, 120), -- textos de éxito (verde)
		Disabled = Color3.fromRGB(76, 76, 84),
		Secondary = Color3.fromRGB(96, 96, 106), -- botones secundarios (Quitar, Volver)
		Max = Color3.fromRGB(140, 104, 30),
		Gold = Color3.fromRGB(255, 206, 84),
		Error = Color3.fromRGB(255, 120, 104),
		Overlay = Color3.fromRGB(12, 12, 14),
		Outline = Color3.fromRGB(16, 14, 18), -- contorno negro de botones y texto
	},

	-- Piezas del estilo simulador: azulejos del menú, barras de moneda e insignias.
	Cartoon = {
		Ink = Color3.fromRGB(16, 14, 18), -- contorno de iconos, azulejos y barras
		Stroke = 3, -- grosor del contorno de azulejos, barras y botones grandes
		TextStroke = 3, -- borde de los textos grandes (UIStroke alrededor de las letras)
		Pill = Color3.fromRGB(255, 255, 255), -- barras de moneda: blanco translúcido
		PillTransparency = 0.3,
		Plus = Color3.fromRGB(96, 214, 96), -- botón verde "+" junto a la energía
		Badge = Color3.fromRGB(236, 56, 64), -- globito rojo de "hay algo nuevo"
		TileTop = 0.62, -- cuánto blanco lleva el color del azulejo arriba
		TileBottom = 0.12, -- ídem abajo
	},

	-- Acabado de paneles y botones: degradado vertical (luz arriba) y brillo superior.
	Finish = {
		PanelShade = 0.8, -- multiplicador del color en el borde inferior del panel
		ButtonShade = 0.74, -- ídem en botones (más marcado: efecto de volumen)
		ShineTransparency = 0.9, -- brillo blanco en la parte alta del panel
		ShineHeight = 46,
		PanelCorner = 12, -- esquinas de los paneles
	},

	-- Barra de título color arena de los paneles (con título arriba: "Title" o "Heading").
	-- Lleva el título, el subtítulo y el botón de cerrar (rojo).
	Header = {
		Top = Color3.fromRGB(246, 222, 170), -- arena clara arriba
		Bottom = Color3.fromRGB(204, 162, 104), -- arena tostada abajo
		Line = 3, -- línea negra que la separa del cuerpo
		GlossTransparency = 0.45, -- brillo blanco fino arriba
		MinHeight = 56,
		Close = Color3.fromRGB(228, 58, 50),
	},

	-- Textura del cuerpo de los paneles grandes: studs de Roblox sobre el gris carbón.
	Grid = {
		Image = "rbxassetid://109441301720998", -- la misma textura de studs del suelo
		Tile = 150, -- píxeles por repetición (unos 18 px por stud)
		Transparency = 0,
		MinSize = 200, -- solo en paneles de al menos 200 × 200 (no en botones ni barras)
	},

	Fonts = {
		Display = Enum.Font.FredokaOne, -- títulos y cifras
		Body = Enum.Font.GothamBold,
		Light = Enum.Font.GothamMedium,
	},

	-- Medidas compartidas (píxeles a escala 1). Los paneles modales se abren DEBAJO de
	-- la tarjeta de energía para no tapar la energía ni la producción.
	Layout = {
		Margin = 12, -- separación con los bordes de pantalla
		Gap = 12, -- separación entre elementos del HUD
		EnergyCardSize = Vector2.new(330, 112), -- igual que HudLayout.Sizes.Energy
		SideButtonWidth = 148, -- ancho de la barra del menú (HudLayout.menuSize)
		TransitionSeconds = 0.16,
	},
}

return Theme
