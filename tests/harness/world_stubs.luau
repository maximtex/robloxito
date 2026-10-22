-- Entorno mínimo para el mundo vivo (DayNight, RewardLogic, configuraciones): tipos de
-- Roblox simulados que usan (Color3 con Lerp para la luz de la noche).
local Color3Meta = {}
Color3Meta.__index = Color3Meta
function Color3Meta.Lerp(self, other, t)
	return setmetatable({ R = self.R + (other.R - self.R) * t, G = self.G + (other.G - self.G) * t, B = self.B + (other.B - self.B) * t }, Color3Meta)
end
Color3 = {
	fromRGB = function(r, g, b)
		return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, Color3Meta)
	end,
	new = function(r, g, b)
		return setmetatable({ R = r, G = g, B = b }, Color3Meta)
	end,
}
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
game = {
	GetService = function()
		return {}
	end,
}
