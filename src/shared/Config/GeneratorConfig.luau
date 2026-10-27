-- Origen del mapa. Antes también era el Cristal del Renacimiento (el generador de energía),
-- que ya no existe; se conserva el nombre para no tocar los muchos archivos que colocan
-- el mundo respecto a este punto.

local GeneratorConfig = {
	-- ORIGEN DE TODO EL MAPA (mundo, zonas, huevos y enemigos se colocan respecto a él):
	-- no se mueve. Y = 0.5 es la superficie del terreno.
	Position = Vector3.new(0, 0.5, -25),

	-- El terreno de Roblox (vóxeles de 4 studs) deja la superficie ~2 studs POR ENCIMA
	-- del borde superior de cada FillBlock/FillCylinder/FillBall (medido en Studio:
	-- tope 0.5 -> superficie 2.5; tope -1.5 -> superficie 0.5). WorldService,
	-- ValleyService y las arenas bajan sus rellenos esta cantidad para que la superficie
	-- quede en Position.Y y nada (plataforma, huevos, altares, flores) quede enterrado.
	TerrainFillOffset = 2,
}

return GeneratorConfig
