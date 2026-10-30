-- Adornos en estilo studs, como el spawn (Santiago: "que todo el estilo visual sea del estilo
-- de studs"): bloques de plástico con studs en todas las caras, sin cilindros ni bolas, con
-- la paleta del suelo y de los árboles de bloques (StudWorld). Solo las llamas y las gemas van
-- de neón (sin studs) para que brillen.
-- Lo usan el pueblo (WorldService), el Bosque de Espinas (ThornWoodsService), el altar de las
-- oleadas, los cofres y la decoración del spawn. Los diseños importados (huevos,
-- Evolucionador, puestos, tablas de clasificación, portales) se quedan como están.
--
-- StudProps.studify(root, options): pasa a plástico con studs lo que ya tenía forma de bloques
-- (y, con Blockify, los cilindros y las bolas a bloques); lo de neón se queda brillando.
-- StudProps.studifyMap(model): lo mismo para el mapa de una zona entera (Valle, Caldera,
-- Tundra y Fortaleza), sin tocar el suelo ni los muros. Las cuevas: CaveDungeon.

local PartFactory = require(script.Parent.PartFactory)

local StudProps = {}

local RGB = Color3.fromRGB

StudProps.Colors = {
	Wood = RGB(206, 114, 42), -- el tronco de los árboles de bloques
	WoodDark = RGB(160, 84, 30),
	Stone = RGB(160, 162, 178),
	StoneDark = RGB(124, 126, 146),
	Iron = RGB(82, 84, 100),
	Gold = RGB(255, 206, 38),
	Cream = RGB(246, 234, 206),
	Red = RGB(226, 52, 52),
	RedDark = RGB(176, 34, 40),
	Blue = RGB(36, 152, 255),
	Leaf = RGB(124, 226, 26),
	LeafDark = RGB(84, 178, 20),
	Pink = RGB(255, 92, 168),
	Flame = RGB(255, 160, 60),
	FlameCore = RGB(255, 228, 110),
}
local C = StudProps.Colors

local function studs(part: BasePart): BasePart
	part.Material = Enum.Material.Plastic
	for _, face in { "TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface" } do
		(part :: any)[face] = Enum.SurfaceType.Studs
	end
	return part
end

-- Bloque de plástico con studs
function StudProps.block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, solid: boolean?): Part
	return studs(PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Plastic,
		Solid = solid == true,
	})) :: Part
end

-- Bloque de neón (llamas, gemas): brilla, sin studs ni colisión
function StudProps.glow(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	part.CastShadow = false
	return part
end

-- Lo que brilla se queda como está (llamas, lava, gemas, energía)
local KEEP = {
	[Enum.Material.Neon] = true,
	[Enum.Material.ForceField] = true,
}

export type StudifyOptions = {
	Blockify: boolean?, -- cilindros y bolas pasan a bloques del mismo tamaño
	Glass: boolean?, -- el cristal y el hielo también (sin perder su transparencia)
	Skip: { [string]: boolean }?, -- nombres (sin el número del final) que no se tocan
}

-- Pasa a plástico con studs las piezas de `root` (y `root` si es una pieza). No toca: lo de
-- neón y campo de fuerza, lo invisible, lo que ya lleva studs (de superficie o de textura, como
-- el suelo y los muros), las mallas importadas ni las uniones.
function StudProps.studify(root: Instance, options: StudifyOptions?)
	local opts: StudifyOptions = options or {}
	local skip = opts.Skip or {}
	local list = root:GetDescendants()
	if root:IsA("BasePart") then
		table.insert(list, root)
	end
	for _, item in list do
		if not (item:IsA("Part") or item:IsA("WedgePart") or item:IsA("CornerWedgePart")) then
			continue
		end
		local part = item :: BasePart
		if KEEP[part.Material] or part.Transparency >= 1 or part:FindFirstChildOfClass("Texture")
			or (part.Material == Enum.Material.Plastic and part.TopSurface == Enum.SurfaceType.Studs)
			or (part.Material == Enum.Material.Glass and not opts.Glass)
			or skip[(part.Name:gsub("%d+$", ""))] then
			continue
		end
		if opts.Blockify and part:IsA("Part") and (part.Shape == Enum.PartType.Cylinder or part.Shape == Enum.PartType.Ball) then
			part.Shape = Enum.PartType.Block
		end
		studs(part)
	end
end

-- Un mapa entero de una zona (su modelo): todo menos el suelo y los muros (ya van en studs con
-- textura), con cilindros y bolas a bloques y el hielo y el cristal también.
function StudProps.studifyMap(model: Instance, options: StudifyOptions?)
	local opts: StudifyOptions = options or { Blockify = true, Glass = true }
	for _, child in model:GetChildren() do
		if child.Name ~= "StudFloor" and child.Name ~= "PerimeterWalls" then
			StudProps.studify(child, opts)
		end
	end
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local point = Instance.new("PointLight")
	point.Color = color
	point.Range = range
	point.Brightness = brightness
	point.Shadows = false
	point.Parent = parent
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Antorcha de pie: base de piedra, palo de madera, cazoleta de hierro y llama de bloques
function StudProps.torch(parent: Instance, pos: Vector3, yawDeg: number, scale: number?): Model
	local s = scale or 1
	local m = model(parent, "Antorcha")
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	StudProps.block(m, "Base", Vector3.new(1.6, 0.6, 1.6) * s, cf * CFrame.new(0, 0.3 * s, 0), C.Stone, true)
	StudProps.block(m, "Palo", Vector3.new(0.8, 4.6, 0.8) * s, cf * CFrame.new(0, 2.9 * s, 0), C.Wood, true)
	StudProps.block(m, "Cazoleta", Vector3.new(1.4, 0.5, 1.4) * s, cf * CFrame.new(0, 5.45 * s, 0), C.Iron)
	local flame = StudProps.glow(m, "Llama", Vector3.new(0.95, 0.95, 0.95) * s, cf * CFrame.new(0, 6.15 * s, 0), C.Flame)
	StudProps.glow(m, "LlamaCentro", Vector3.new(0.5, 0.6, 0.5) * s, cf * CFrame.new(0, 6.85 * s, 0), C.FlameCore)
	light(flame, RGB(255, 192, 96), 14, 1.1)
	m.PrimaryPart = flame
	return m
end

-- Estandarte: base de piedra, mástil y travesaño de madera, bandera roja con escudo dorado y
-- la punta en escalones
function StudProps.banner(parent: Instance, pos: Vector3, yawDeg: number): Model
	local m = model(parent, "Estandarte")
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	StudProps.block(m, "Base", Vector3.new(2.2, 0.8, 2.2), cf * CFrame.new(0, 0.4, 0), C.Stone, true)
	StudProps.block(m, "Mastil", Vector3.new(0.8, 8, 0.8), cf * CFrame.new(0, 4.8, 0), C.Wood, true)
	StudProps.block(m, "Travesano", Vector3.new(3.6, 0.6, 0.6), cf * CFrame.new(0, 8.2, 0.5), C.Wood)
	StudProps.block(m, "Remate", Vector3.new(1, 1, 1), cf * CFrame.new(0, 9.3, 0), C.Gold)
	StudProps.block(m, "Bandera", Vector3.new(3, 3.8, 0.4), cf * CFrame.new(0, 5.9, 0.6), C.Red)
	StudProps.block(m, "Punta", Vector3.new(2, 0.8, 0.4), cf * CFrame.new(0, 3.6, 0.6), C.Red)
	StudProps.block(m, "PuntaFinal", Vector3.new(1, 0.8, 0.4), cf * CFrame.new(0, 2.8, 0.6), C.Red)
	StudProps.block(m, "Escudo", Vector3.new(1.4, 1.6, 0.3), cf * CFrame.new(0, 6.1, 0.9), C.Gold)
	return m
end

-- Provisiones: dos cajas, un barril cuadrado con aros y un saco
function StudProps.crates(parent: Instance, pos: Vector3, yawDeg: number): Model
	local m = model(parent, "Provisiones")
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	StudProps.block(m, "Caja", Vector3.new(2.6, 2.2, 2.6), cf * CFrame.new(-1.2, 1.1, -0.4), C.Wood, true)
	StudProps.block(m, "CajaChica", Vector3.new(1.8, 1.6, 1.8), cf * CFrame.new(-1.0, 3.0, -0.3) * CFrame.Angles(0, math.rad(20), 0), C.WoodDark, true)
	StudProps.block(m, "Barril", Vector3.new(1.8, 2.2, 1.8), cf * CFrame.new(1.3, 1.1, 0.4), C.WoodDark, true)
	for _, y in { 0.5, 1.7 } do
		StudProps.block(m, "Aro", Vector3.new(1.9, 0.3, 1.9), cf * CFrame.new(1.3, y, 0.4), C.Iron)
	end
	StudProps.block(m, "Saco", Vector3.new(1.4, 1, 1.2), cf * CFrame.new(0.2, 0.5, 1.5), C.Cream)
	return m
end

-- Seta de bloques: pie crema, sombrero en dos pisos y dos pintas
function StudProps.mushroom(parent: Instance, pos: Vector3, blue: boolean?, scale: number?): Model
	local s = scale or 1
	local m = model(parent, "Seta")
	local cap = if blue then C.Blue else C.Red
	StudProps.block(m, "Pie", Vector3.new(0.6, 0.8, 0.6) * s, CFrame.new(pos + Vector3.new(0, 0.4 * s, 0)), C.Cream)
	StudProps.block(m, "Sombrero", Vector3.new(1.6, 0.5, 1.6) * s, CFrame.new(pos + Vector3.new(0, 1.05 * s, 0)), cap)
	StudProps.block(m, "SombreroArriba", Vector3.new(1, 0.3, 1) * s, CFrame.new(pos + Vector3.new(0, 1.45 * s, 0)), cap)
	-- Pintas en el piso de abajo del sombrero, fuera del de arriba
	for _, offset in { Vector3.new(0.6, 1.33, 0.55), Vector3.new(-0.58, 1.33, -0.6) } do
		StudProps.block(m, "Pinta", Vector3.new(0.35, 0.06, 0.35) * s, CFrame.new(pos + offset * s), C.Cream)
	end
	return m
end

-- Matita: tres briznas de bloque y, a veces, una flor
function StudProps.grassTuft(parent: Instance, pos: Vector3, flowers: boolean?): Model
	local m = model(parent, "Matita")
	for index, h in { 0.8, 1.2, 0.6 } do
		StudProps.block(m, "Brizna", Vector3.new(0.4, h, 0.4), CFrame.new(pos + Vector3.new((index - 2) * 0.42, h / 2, (index % 2) * 0.2)), if index == 2 then C.LeafDark else C.Leaf)
	end
	if flowers then
		StudProps.block(m, "Flor", Vector3.new(0.5, 0.5, 0.5), CFrame.new(pos + Vector3.new(0, 1.45, 0.2)), C.Pink)
	end
	return m
end

-- Arbusto: un bloque grande de hojas con otro más pequeño encima
function StudProps.bush(parent: Instance, pos: Vector3, yawDeg: number, scale: number?): Model
	local s = scale or 1
	local m = model(parent, "Arbusto")
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	StudProps.block(m, "Hojas", Vector3.new(3.2, 2, 3.2) * s, cf * CFrame.new(0, 1 * s, 0), C.Leaf, true)
	StudProps.block(m, "HojasArriba", Vector3.new(2, 1.2, 2) * s, cf * CFrame.new(0.4 * s, 2.6 * s, -0.3 * s), C.LeafDark)
	return m
end

return StudProps
