-- Entorno mínimo para la distribución del paisaje (LandscapeLayout es pura): solo los
-- tipos que usan las configuraciones.
Vector2 = {
	new = function(x, y)
		return { X = x or 0, Y = y or 0, Magnitude = math.sqrt((x or 0) ^ 2 + (y or 0) ^ 2) }
	end,
}
Vector3 = {
	new = function(x, y, z)
		return { X = x or 0, Y = y or 0, Z = z or 0 }
	end,
}
Color3 = {
	fromRGB = function(r, g, b)
		return { R = r / 255, G = g / 255, B = b / 255 }
	end,
	new = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
}
