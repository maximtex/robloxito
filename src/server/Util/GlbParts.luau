--!strict
-- Construye las piezas de un diseño pasado de .glb a datos (EggGardenData,
-- LeaderboardBoardData, ChristmasData): { Nombre, Forma, Material, Color, Reflectance, Tamaño,
-- CFrame, Extra? } con el CFrame en el marco del modelo y Extra = { Inner?, Transparency? }.
-- Formas (las redondas tienen el eje en Y local):
-- - Block: un bloque.
-- - Cylinder: cilindro redondo (Roblox lo tiene en X).
-- - Octagon: prisma de 8 lados con caras en X/Z (Tamaño = ancho entre caras, alto, ancho):
--   dos bloques en cruz y una cuña en cada esquina.
-- - Ring: aro plano (Tamaño = diámetro exterior, alto; Inner = diámetro interior) hecho de
--   tramos rectos alrededor.
-- - Sphere: elipsoide del tamaño (bolas, nieve, focos, botones).
-- - Star: estrella de 5 puntas plana en Y (Tamaño = ancho, grosor, ancho), con una punta hacia -Z.
-- Las piezas finas (menos de MIN_SOLID de grosor), las transparentes, las esferas, las estrellas
-- y los aros son decorativas: sin colisión.

local PartFactory = require(script.Parent.PartFactory)

local GlbParts = {}

local MIN_SOLID = 0.3
local RING_SEGMENT = 0.6 -- largo aproximado de cada tramo de un aro (studs)
local TAN_22_5 = math.tan(math.rad(22.5))
-- Cuña de una esquina del octágono: su eje X (la extrusión) en vertical, Y hacia +X y Z hacia -Z
local WEDGE_FLAT = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.xAxis, -Vector3.zAxis)

type Look = { Color: Color3, Material: Enum.Material, Reflectance: number }

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, look: Look, solid: boolean, shape: Enum.PartType?): BasePart
	local built = PartFactory.part(parent, name, {
		Size = size,
		CFrame = cf,
		Color = look.Color,
		Material = look.Material,
		Shape = shape,
		Solid = solid,
	})
	built.Reflectance = look.Reflectance
	return built
end

local function octagon(parent: Instance, name: string, cf: CFrame, size: Vector3, look: Look, solid: boolean): BasePart
	local a = size.X / 2
	local h = size.Y
	local side = 2 * a * TAN_22_5
	local leg = a - side / 2
	local first = part(parent, name, Vector3.new(2 * a, h, side), cf, look, solid)
	part(parent, name, Vector3.new(side, h, 2 * a), cf, look, solid)
	for k = 0, 3 do
		local wedge = Instance.new("WedgePart")
		wedge.Name = name
		wedge.Anchored = true
		wedge.CanCollide = solid
		wedge.CanQuery = solid
		wedge.CanTouch = false
		wedge.CastShadow = solid
		wedge.TopSurface = Enum.SurfaceType.Smooth
		wedge.BottomSurface = Enum.SurfaceType.Smooth
		wedge.Color = look.Color
		wedge.Material = look.Material
		wedge.Reflectance = look.Reflectance
		wedge.Size = Vector3.new(h, leg, leg)
		wedge.CFrame = cf * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(side / 2 + leg / 2, 0, side / 2 + leg / 2) * WEDGE_FLAT
		wedge.Parent = parent
	end
	return first
end

local function ring(parent: Instance, name: string, cf: CFrame, size: Vector3, inner: number, look: Look): BasePart
	local outer = size.X / 2
	local radius = (outer + inner / 2) / 2
	local width = outer - inner / 2
	local count = math.max(12, math.ceil(2 * math.pi * radius / RING_SEGMENT))
	local length = 2 * outer * math.tan(math.pi / count) -- sin huecos en el borde de fuera
	local first: BasePart? = nil
	for index = 1, count do
		local angle = (index - 1) / count * 2 * math.pi
		local segment = part(parent, name, Vector3.new(length, size.Y, width), cf * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius), look, false)
		first = first or segment
	end
	return first :: BasePart
end

-- Estrella: un disco en el centro y cinco brazos hacia fuera
local function star(parent: Instance, name: string, cf: CFrame, size: Vector3, look: Look): BasePart
	local radius = size.X / 2
	local center = part(parent, name, Vector3.new(size.Y, radius, radius), cf * PartFactory.UPRIGHT, look, false, Enum.PartType.Cylinder)
	for k = 0, 4 do
		local angle = k * 2 * math.pi / 5
		local direction = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		part(parent, name, Vector3.new(radius * 0.42, size.Y, radius), cf * CFrame.lookAt(direction * radius / 2, direction * radius), look, false)
	end
	return center
end

-- Construye `data` en `parent` con el modelo colocado en `frame`. Devuelve una pieza de cada
-- nombre (la primera).
function GlbParts.build(parent: Instance, data: { { any } }, frame: CFrame): { [string]: BasePart }
	local byName: { [string]: BasePart } = {}
	for _, entry in data do
		local name: string, kind: string, size: Vector3 = entry[1], entry[2], entry[6]
		local extra = entry[8] or {}
		local look: Look = { Material = entry[3], Color = entry[4], Reflectance = entry[5] }
		local cf = frame * (entry[7] :: CFrame)
		local transparency = extra.Transparency or 0
		local solid = (kind == "Block" or kind == "Cylinder" or kind == "Octagon") and transparency == 0 and math.min(size.X, size.Y, size.Z) >= MIN_SOLID
		local built: BasePart
		if kind == "Octagon" then
			built = octagon(parent, name, cf, size, look, solid)
		elseif kind == "Ring" then
			built = ring(parent, name, cf, size, extra.Inner, look)
		elseif kind == "Cylinder" then
			built = part(parent, name, Vector3.new(size.Y, size.X, size.Z), cf * PartFactory.UPRIGHT, look, solid, Enum.PartType.Cylinder)
		elseif kind == "Sphere" then
			built = PartFactory.ellipsoid(parent, name, cf, size, look.Color, look.Material)
			built.Reflectance = look.Reflectance
		elseif kind == "Star" then
			built = star(parent, name, cf, size, look)
		else
			built = part(parent, name, size, cf, look, solid)
		end
		if transparency > 0 then
			built.Transparency = transparency
		end
		byName[name] = byName[name] or built
	end
	return byName
end

return GlbParts
