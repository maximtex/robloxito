-- Entorno mínimo para ejecutar el EnemyAnimator REAL fuera de Roblox (sin dibujar nada).
local V3 = {}
V3.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
	end
	return nil
end
V3.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	return Vector3.new(a.X * b, a.Y * b, a.Z * b)
end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) end }
Vector3.one = Vector3.new(1, 1, 1)
Vector2 = { new = function(x, y) return { X = x, Y = y, Magnitude = math.sqrt(x * x + y * y) } end }
local C3 = {}
Color3 = { fromRGB = function(r, g, b) return setmetatable({ R = r, G = g, B = b }, C3) end, new = function(r, g, b) return setmetatable({ R = r, G = g, B = b }, C3) end }
-- typeof de Roblox: distingue Vector3 y Color3 de las tablas.
local rawTypeof = typeof
typeof = function(value)
	local mt = getmetatable(value)
	if mt == V3 then return "Vector3" end
	if mt == C3 then return "Color3" end
	return rawTypeof(value)
end

-- CFrame: solo traslación + "giro" acumulado (suficiente para comprobar que se escribe).
local CF = {}
CF.__index = CF
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then
		return a.P + b
	end
	return setmetatable({ P = a.P + b.P, R = a.R + b.R }, CF)
end
CFrame = {
	new = function(x, y, z)
		if type(x) == "table" then return setmetatable({ P = x, R = 0 }, CF) end
		return setmetatable({ P = Vector3.new(x or 0, y or 0, z or 0), R = 0 }, CF)
	end,
	Angles = function(x, y, z) return setmetatable({ P = Vector3.new(0, 0, 0), R = math.abs(x) + math.abs(y) + math.abs(z) }, CF) end,
}
CFrame.identity = CFrame.new(0, 0, 0)

NumberRange = { new = function(...) return { ... } end }
NumberSequence = { new = function(...) return { ... } end }
ColorSequence = { new = function(...) return { ... } end }
TweenInfo = { new = function(...) return { ... } end }
Enum = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })

local created = {}
Instance = {
	new = function(className)
		local object = { ClassName = className, Name = className }
		function object.Emit() end
		function object.Play() end
		function object.Destroy(self) self.Parent = nil end
		function object.ClearAllChildren() end
		table.insert(created, object)
		return object
	end,
}

local clock = 0
local delayed = {}
task = {
	spawn = function(fn, ...) fn(...) end,
	delay = function(seconds, fn, ...) table.insert(delayed, { At = clock + seconds, Fn = fn, Args = { ... } }) end,
}
os = { clock = function() return clock end }

local frame
local enemiesFolder
local camera = { CFrame = { Position = Vector3.new(0, 5, 20) } }
local WorkspaceStub = {
	CurrentCamera = camera,
	GetServerTimeNow = function() return clock end,
	FindFirstChild = function(_, name)
		if name == "Enemies" then return enemiesFolder end
		return nil
	end,
}
local services = {
	Workspace = WorkspaceStub,
	Debris = { AddItem = function() end },
	SoundService = {},
	TweenService = { Create = function() return { Play = function() end } end },
	RunService = { PreSimulation = { Connect = function(_, fn) frame = fn end } },
}
game = { GetService = function(_, name) return services[name] end }
