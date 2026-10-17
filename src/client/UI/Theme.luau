-- Paleta, tipografías y medidas de la interfaz (fantasía natural): verde bosque,
-- verde esmeralda, piedra clara y dorado suave. La comparten todos los paneles.

local Theme = {
	Colors = {
		Panel = Color3.fromRGB(22, 38, 32), -- verde bosque profundo
		PanelTransparency = 0.12,
		Stroke = Color3.fromRGB(196, 176, 126), -- dorado suave
		StrokeTransparency = 0.45, -- bordes discretos
		Inset = Color3.fromRGB(36, 56, 48),
		Text = Color3.fromRGB(246, 242, 228),
		Muted = Color3.fromRGB(198, 202, 186), -- piedra clara
		Accent = Color3.fromRGB(104, 214, 150), -- esmeralda
		Buy = Color3.fromRGB(46, 128, 74),
		BuyHighlight = Color3.fromRGB(156, 236, 140),
		Disabled = Color3.fromRGB(60, 74, 68),
		Secondary = Color3.fromRGB(70, 84, 76), -- botones secundarios (Quitar, Volver)
		Max = Color3.fromRGB(140, 104, 30),
		Gold = Color3.fromRGB(236, 200, 120),
		Error = Color3.fromRGB(255, 136, 120),
		Overlay = Color3.fromRGB(8, 16, 12),
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
		EnergyCardSize = Vector2.new(320, 124),
		SideButtonWidth = 150, -- botón lateral de Mascotas
		TransitionSeconds = 0.16,
	},
}

return Theme
