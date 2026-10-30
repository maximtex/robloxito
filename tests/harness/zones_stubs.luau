-- Entorno mínimo para las configuraciones de zonas: Vector2 con resta y Magnitude,
-- Vector3 y Color3 (solo datos).
local Vector2Meta = {}
Vector2Meta.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X ^ 2 + self.Y ^ 2)
	end
	return nil
end
Vector2Meta.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
Vector2Meta.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
Vector2 = {
	new = function(x, y)
		return setmetatable({ X = x or 0, Y = y or 0 }, Vector2Meta)
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
-- Enum.X.Y devuelve "Y" (los módulos que solo los nombran al cargarse, como PadPortal)
Enum = setmetatable({}, {
	__index = function()
		return setmetatable({}, {
			__index = function(_, key)
				return key
			end,
		})
	end,
})
