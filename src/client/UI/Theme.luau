-- Paleta, tipografías y medidas de la interfaz. Estilo simulador (la referencia que eligió
-- Santiago): iconos dibujados, contorno oscuro grueso, texto blanco con borde y colores
-- vivos sobre el verde esmeralda del bosque. La comparten todos los paneles.

local Theme = {
	Colors = {
		Panel = Color3.fromRGB(34, 74, 58), -- esmeralda
		PanelTransparency = 0.06,
		Stroke = Color3.fromRGB(43, 29, 63), -- contorno oscuro (el de los iconos)
		StrokeTransparency = 0,
		Inset = Color3.fromRGB(24, 54, 42),
		Text = Color3.fromRGB(246, 242, 228),
		Muted = Color3.fromRGB(198, 202, 186), -- piedra clara
		Accent = Color3.fromRGB(104, 214, 150), -- esmeralda
		Buy = Color3.fromRGB(64, 182, 88),
		BuyHighlight = Color3.fromRGB(156, 236, 140),
		Disabled = Color3.fromRGB(76, 94, 86),
		Secondary = Color3.fromRGB(84, 104, 94), -- botones secundarios (Quitar, Volver)
		Max = Color3.fromRGB(140, 104, 30),
		Gold = Color3.fromRGB(236, 200, 120),
		Error = Color3.fromRGB(255, 136, 120),
		Overlay = Color3.fromRGB(8, 16, 12),
		Outline = Color3.fromRGB(43, 29, 63), -- contorno oscuro de botones y texto
	},

	-- Piezas del estilo simulador: azulejos del menú, barras de moneda e insignias.
	Cartoon = {
		Ink = Color3.fromRGB(43, 29, 63), -- contorno de iconos, azulejos y barras
		Stroke = 3, -- grosor del contorno de azulejos, barras y botones grandes
		TextStroke = 2.5, -- borde de los textos grandes (UIStroke alrededor de las letras)
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
