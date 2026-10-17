-- Entorno con matemáticas REALES de Vector3/CFrame (como Roblox) e instancias mínimas,
-- para construir el santuario con el GeneratorService real y medir su geometría.
local V = {}
V.__index = function(self, key)
	if key == "Magnitude" then return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z) end
	if key == "Unit" then local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z) return Vector3.new(self.X / m, self.Y / m, self.Z / m) end
	return V[key]
end
V.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then return Vector3.new(b.X * a, b.Y * a, b.Z * a) end
	if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b) return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
function V.Cross(a, b) return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
function V.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end }
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
Vector2 = { new = function(x, y) return { X = x, Y = y } end }

-- CFrame: posición + matriz 3x3 (columnas: derecha, arriba, atrás)
local CF = {}
local function cf(p, m) return setmetatable({ P = p, M = m }, CF) end
local function matmul(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			local s = 0
			for k = 0, 2 do s += a[i * 3 + k + 1] * b[k * 3 + j + 1] end
			r[i * 3 + j + 1] = s
		end
	end
	return r
end
local function rotate(m, v)
	return Vector3.new(m[1] * v.X + m[2] * v.Y + m[3] * v.Z, m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z)
end
CF.__index = function(self, key)
	if key == "Position" then return self.P end
	if key == "LookVector" then local m = self.M return Vector3.new(-m[3], -m[6], -m[9]) end
	if key == "UpVector" then local m = self.M return Vector3.new(m[2], m[5], m[8]) end
	return CF[key]
end
CF.__mul = function(a, b)
	if getmetatable(b) == V then return a.P + rotate(a.M, b) end
	return cf(a.P + rotate(a.M, b.P), matmul(a.M, b.M))
end
function CF.Inverse(self)
	local m = self.M
	local t = { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
	return cf(-rotate(t, self.P), t)
end
function CF.ToObjectSpace(self, other) return self:Inverse() * other end
local I = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function rx(a) local c, s = math.cos(a), math.sin(a) return { 1, 0, 0, 0, c, -s, 0, s, c } end
local function ry(a) local c, s = math.cos(a), math.sin(a) return { c, 0, s, 0, 1, 0, -s, 0, c } end
local function rz(a) local c, s = math.cos(a), math.sin(a) return { c, -s, 0, s, c, 0, 0, 0, 1 } end
CFrame = {
	new = function(x, y, z)
		if type(x) == "table" then return cf(x, I) end
		return cf(Vector3.new(x or 0, y or 0, z or 0), I)
	end,
	Angles = function(a, b, c) return cf(Vector3.zero, matmul(matmul(rx(a), ry(b)), rz(c))) end,
	lookAt = function(at, target)
		local look = (target - at).Unit
		local right = look:Cross(Vector3.new(0, 1, 0)).Unit
		local up = right:Cross(look)
		return cf(at, { right.X, up.X, -look.X, right.Y, up.Y, -look.Y, right.Z, up.Z, -look.Z })
	end,
}
CFrame.identity = CFrame.new(0, 0, 0)

Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end, new = function(r, g, b) return { R = r, G = g, B = b } end }
NumberRange = { new = function(...) return { ... } end }
NumberSequence = { new = function(...) return { ... } end }
NumberSequenceKeypoint = { new = function(...) return { ... } end }
ColorSequence = { new = function(...) return { ... } end }
UDim2 = { new = function(...) return { ... } end, fromScale = function(...) return { ... } end, fromOffset = function(...) return { ... } end }
UDim = { new = function(...) return { ... } end }
Enum = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })

-- Instancias mínimas con jerarquía, atributos y búsqueda
local BASE_PARTS = { Part = true }
local function isA(self, className)
	if self.ClassName == className then return true end
	if className == "BasePart" then return BASE_PARTS[self.ClassName] == true end
	if className == "Light" then return self.ClassName == "PointLight" end
	return className == "Instance"
end
local Inst = {}
Inst.__index = function(self, key)
	local props = rawget(self, "_props")
	if props[key] ~= nil then return props[key] end
	if Inst[key] then return Inst[key] end
	if key == "Position" and props.CFrame then return props.CFrame.Position end
	-- hijos por nombre (model.Core)
	for _, child in rawget(self, "_children") do
		if child.Name == key then return child end
	end
	return nil
end
Inst.__newindex = function(self, key, value)
	local props = rawget(self, "_props")
	if key == "Parent" then
		local old = props.Parent
		if old then
			local list = rawget(old, "_children")
			local i = table.find(list, self)
			if i then table.remove(list, i) end
		end
		if value then table.insert(rawget(value, "_children"), self) end
	end
	props[key] = value
end
function Inst.IsA(self, className) return isA(self, className) end
function Inst.GetChildren(self) return table.clone(rawget(self, "_children")) end
function Inst.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, child in rawget(node, "_children") do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end
function Inst.FindFirstChild(self, name)
	for _, child in rawget(self, "_children") do
		if child.Name == name then return child end
	end
	return nil
end
function Inst.FindFirstChildOfClass(self, className)
	for _, child in rawget(self, "_children") do
		if child.ClassName == className then return child end
	end
	return nil
end
function Inst.IsDescendantOf(self, ancestor)
	local node = self.Parent
	while node do
		if node == ancestor then return true end
		node = node.Parent
	end
	return false
end
function Inst.SetAttribute(self, k, v) rawget(self, "_attrs")[k] = v end
function Inst.GetAttribute(self, k) return rawget(self, "_attrs")[k] end
function Inst.Destroy(self) self.Parent = nil end
function Inst.Emit() end
local function newInstance(className)
	local defaults = { ClassName = className, Name = className }
	if className == "Part" then
		defaults.CanCollide = true
		defaults.CanQuery = true
		defaults.CanTouch = true
		defaults.Transparency = 0
		defaults.Shape = "PartType.Block"
	end
	if className == "ParticleEmitter" then defaults.Enabled = true end
	return setmetatable({ _props = defaults, _children = {}, _attrs = {} }, Inst)
end
Instance = { new = newInstance }

workspace = newInstance("Workspace")
local bulkMoves = 0
function workspace.BulkMoveTo(_, parts, cframes)
	bulkMoves += 1
	for i, part in parts do part.CFrame = cframes[i] end
end
local heartbeat
local services = {
	ReplicatedStorage = { WaitForChild = function() return {} end },
	Workspace = workspace,
	RunService = { Heartbeat = { Connect = function(_, fn) heartbeat = fn end } },
}
game = { GetService = function(_, name) return services[name] end }
