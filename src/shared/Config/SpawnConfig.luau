-- Integración visual de los SpawnLocation existentes con el claro mágico.
-- No crea puntos de aparición ni toca el avatar del jugador.

local SpawnConfig = {
	DecorFolderName = "SpawnDecor",

	-- Gira el SpawnLocation (solo en Y) para que su cara frontal mire al cristal.
	-- Roblox hace aparecer al personaje con la orientación del spawn.
	FaceGenerator = true,

	PadColor = Color3.fromRGB(206, 196, 176),
	PadMaterial = Enum.Material.Slate,
	DecalTint = Color3.fromRGB(246, 216, 140), -- tiñe el logo del spawn de dorado
	HideDecal = true, -- el logo de Roblox se veía como una mancha negra en el suelo

	-- Runas doradas en el borde superior del spawn.
	TrimInset = 0.4,
	TrimColor = Color3.fromRGB(244, 204, 110),

	-- Farolillos de madera a ambos lados del spawn.
	PostGap = 2.5, -- distancia desde el borde lateral del spawn
	PostHeight = 3.2,
	PostColor = Color3.fromRGB(104, 76, 52),
	LanternColor = Color3.fromRGB(255, 214, 140),
	LightColor = Color3.fromRGB(255, 206, 140),
	LightRange = 12,
	LightBrightness = 1,
}

return SpawnConfig
