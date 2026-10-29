-- Decoración de temporada del mapa. Christmas = true pone la decoración navideña
-- (Server.Util.ChristmasDecor): en las tablas de clasificación nieve, guirnaldas con luces,
-- coronas, bastones de caramelo y regalos, y por el Bosque (solo el primer mapa) los adornos de
-- ForestDecor. Pasada la Navidad, ponlo en false y desaparece toda.

local V2 = Vector2.new

local SeasonConfig = {
	Christmas = false,

	-- Adornos navideños del Bosque (diseños de ChristmasData: Arch, Lantern, GiftPile y
	-- Snowman), en coordenadas del mundo y mirando hacia FaceToward. Todos en el prado, sin
	-- pisar caminos, puestos, cofres, personajes ni los puntos de aparición de los enemigos
	-- (el arco cruza la avenida por encima).
	ForestDecor = {
		{ Model = "Arch", Position = V2(0, 90), FaceToward = V2(0, 0) }, -- sobre la avenida, de cara a la plaza
		{ Model = "Lantern", Position = V2(-17, 47), FaceToward = V2(0, 47) }, -- a los lados de la avenida
		{ Model = "Lantern", Position = V2(17, 46.5), FaceToward = V2(0, 46.5) },
		{ Model = "Lantern", Position = V2(-17, 102), FaceToward = V2(0, 102) },
		{ Model = "Lantern", Position = V2(17, 102), FaceToward = V2(0, 102) },
		{ Model = "GiftPile", Position = V2(0, -46), FaceToward = V2(0, 0) }, -- entre las tablas de clasificación
		{ Model = "GiftPile", Position = V2(22, 78), FaceToward = V2(0, 78) },
		{ Model = "GiftPile", Position = V2(-34, 86), FaceToward = V2(0, 86) },
		{ Model = "Snowman", Position = V2(-34, 62), FaceToward = V2(0, 62) },
		{ Model = "Snowman", Position = V2(53, -14), FaceToward = V2(0, 0) }, -- al este de la plaza
	},
}

return SeasonConfig
