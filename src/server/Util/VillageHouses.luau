-- Casas del Pueblo del Renacimiento: los tres estilos del diseño de Santiago ("Casas del
-- Pueblo", Claude Design), pasados a piezas de Roblox con las mismas medidas (1 = 1 stud).
-- - "Timber" (A · Entramado): planta baja de piedra con sillares, piso alto volado con
--   entramado y riostras, tejado empinado con buhardilla, puerta en arco, farolillos e hiedra.
-- - "Tower" (B · Torre): cabaña de tejado alto con torre y chapitel con remate dorado,
--   chimenea exterior de ladrillo y camino de losas.
-- - "Shop" (C · Tienda): hastial hacia la calle, escaparate, toldo con faldón, balcón con
--   flores y cartel colgante. El texto del cartel va en el friso oscuro.
--
-- Cada función recibe el marco de la casa con la FACHADA mirando a +Z local (como en el
-- diseño) y devuelve lo que VillageService necesita después (chimeneas, friso...).
-- Solo las piezas grandes chocan (paredes, tejado, escalones, cajas...); los detalles son
-- decorativos (sin colisión ni sombra).

local VillageHouses = {}

local function material(name: string, fallback: Enum.Material): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and value then value else fallback
end
local PLASTER = material("Plaster", Enum.Material.SmoothPlastic)
local CLAY_ROOF = material("ClayRoofTiles", Enum.Material.Slate)
local SHINGLES = material("RoofShingles", Enum.Material.Slate)

local RGB = Color3.fromRGB
-- Paleta del diseño (material de Roblox y color).
local MATS: { [string]: { Color: Color3, Material: Enum.Material, Transparency: number? } } = {
	plaster = { Color = RGB(242, 232, 212), Material = PLASTER },
	beam = { Color = RGB(96, 66, 44), Material = Enum.Material.Wood },
	stone = { Color = RGB(168, 162, 148), Material = Enum.Material.Slate },
	stone_light = { Color = RGB(205, 197, 178), Material = Enum.Material.Limestone },
	darkstone = { Color = RGB(120, 116, 108), Material = Enum.Material.Slate },
	door = { Color = RGB(122, 80, 48), Material = Enum.Material.WoodPlanks },
	wood = { Color = RGB(150, 108, 70), Material = Enum.Material.WoodPlanks },
	brick = { Color = RGB(168, 96, 74), Material = Enum.Material.Brick },
	brick_dark = { Color = RGB(126, 70, 58), Material = Enum.Material.Brick },
	glass = { Color = RGB(255, 224, 160), Material = Enum.Material.Neon, Transparency = 0.15 },
	lamp = { Color = RGB(255, 214, 150), Material = Enum.Material.Neon },
	iron = { Color = RGB(58, 58, 64), Material = Enum.Material.Metal },
	gold = { Color = RGB(240, 200, 100), Material = Enum.Material.Metal },
	leaf = { Color = RGB(90, 150, 70), Material = Enum.Material.Grass },
	leaf_dark = { Color = RGB(68, 122, 56), Material = Enum.Material.Grass },
	cream = { Color = RGB(250, 242, 222), Material = Enum.Material.Fabric },
	sign = { Color = RGB(70, 48, 32), Material = Enum.Material.Wood },
	crystal = { Color = RGB(110, 236, 220), Material = Enum.Material.Neon },
	fl_pink = { Color = RGB(255, 120, 160), Material = Enum.Material.SmoothPlastic },
	fl_yellow = { Color = RGB(255, 214, 90), Material = Enum.Material.SmoothPlastic },
	fl_violet = { Color = RGB(190, 140, 255), Material = Enum.Material.SmoothPlastic },
	fl_white = { Color = RGB(255, 255, 255), Material = Enum.Material.SmoothPlastic },
}
local FLOWERS = { "fl_pink", "fl_yellow", "fl_violet", "fl_white" }

-- Piezas que chocan (las demás son decorativas).
local SOLID = {
	Plinth = true, GroundWalls = true, UpperWalls = true, Walls = true, RoofFront = true, RoofBack = true,
	Gable = true, Dormer = true, DormerGable = true, Chimney = true, ChimneyBase = true, TowerBase = true,
	TowerWalls = true, TowerSpire = true, TowerTop = true, Step = true, DoorLeaf = true, Surround = true,
	ShopDoor = true, DisplayPanel = true, DisplayGlass = true, BalconyFloor = true, Crate = true,
	Barrel = true, Fascia = true, FloorBand = true,
}

export type Context = {
	Model: Model,
	Roof: Color3,
	RoofDark: Color3,
	RoofMaterial: Enum.Material,
	Seed: number,
}

local function look(ctx: Context, key: string): (Color3, Enum.Material, number)
	if key == "roof" then
		return ctx.Roof, ctx.RoofMaterial, 0
	elseif key == "roof_dark" then
		return ctx.RoofDark, Enum.Material.Wood, 0
	elseif key == "roof_fabric" then
		return ctx.Roof, Enum.Material.Fabric, 0
	end
	local spec = MATS[key] or MATS.plaster
	return spec.Color, spec.Material, spec.Transparency or 0
end

local function finish(piece: BasePart, ctx: Context, name: string, key: string)
	local color, mat, transparency = look(ctx, key)
	piece.Name = name
	piece.Anchored = true
	piece.CanTouch = false
	piece.Color = color
	piece.Material = mat
	piece.Transparency = transparency
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	if not SOLID[name] then
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CastShadow = false
	end
	piece.Parent = ctx.Model
end

local function at(base: CFrame, pos: { number }, rot: { number }?): CFrame
	local frame = base * CFrame.new(pos[1], pos[2], pos[3])
	if rot then
		frame *= CFrame.Angles(rot[1], rot[2], rot[3])
	end
	return frame
end

local function box(ctx: Context, base: CFrame, name: string, key: string, size: { number }, pos: { number }, rot: { number }?): Part
	local piece = Instance.new("Part")
	piece.Size = Vector3.new(math.max(size[1], 0.05), math.max(size[2], 0.05), math.max(size[3], 0.05))
	piece.CFrame = at(base, pos, rot)
	finish(piece, ctx, name, key)
	return piece
end

local function ball(ctx: Context, base: CFrame, name: string, key: string, radius: number, pos: { number }): Part
	local piece = Instance.new("Part")
	piece.Shape = Enum.PartType.Ball
	piece.Size = Vector3.one * radius * 2
	piece.CFrame = at(base, pos)
	finish(piece, ctx, name, key)
	return piece
end

-- Cilindro a lo largo de un eje ("y" de pie, "z" hacia la fachada, "x" de lado).
local AXIS = { y = CFrame.Angles(0, 0, math.pi / 2), z = CFrame.Angles(0, math.pi / 2, 0), x = CFrame.identity }
local function cyl(ctx: Context, base: CFrame, name: string, key: string, radius: number, height: number, pos: { number }, axis: string?): Part
	local piece = Instance.new("Part")
	piece.Shape = Enum.PartType.Cylinder
	piece.Size = Vector3.new(height, radius * 2, radius * 2)
	piece.CFrame = at(base, pos) * AXIS[axis or "y"]
	finish(piece, ctx, name, key)
	return piece
end

local function group(base: CFrame, pos: { number }, yaw: number?): CFrame
	return base * CFrame.new(pos[1], pos[2], pos[3]) * CFrame.Angles(0, yaw or 0, 0)
end

local function wedgePart(ctx: Context, name: string, key: string, size: Vector3, frame: CFrame): WedgePart
	local piece = Instance.new("WedgePart")
	piece.Size = size
	piece.CFrame = frame
	finish(piece, ctx, name, key)
	return piece
end

-- Hastial triangular (base `span`, alto `rise`, grosor `t`) con la base en `pos`.
-- ridgeAlongZ = false: el triángulo abarca Z (paredes laterales, a ±X).
local function gable(ctx: Context, base: CFrame, name: string, key: string, span: number, rise: number, t: number, pos: { number }, ridgeAlongZ: boolean?)
	local frame = at(base, pos) * CFrame.Angles(0, if ridgeAlongZ then 0 else math.pi / 2, 0)
	local size = Vector3.new(t, rise, span / 2)
	wedgePart(ctx, name, key, size, frame * CFrame.new(span / 4, rise / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0))
	wedgePart(ctx, name, key, size, frame * CFrame.new(-span / 4, rise / 2, 0) * CFrame.Angles(0, math.pi / 2, 0))
end

-- Cuña del diseño: lado alto hacia -Z (high = -1) o hacia +Z (high = 1).
local function wedge(ctx: Context, base: CFrame, name: string, key: string, size: { number }, pos: { number }, high: number)
	local frame = at(base, pos)
	if high < 0 then
		frame *= CFrame.Angles(0, math.pi, 0)
	end
	wedgePart(ctx, name, key, Vector3.new(size[1], size[2], size[3]), frame)
end

-- Pirámide de base cuadrada (lado `side`, alto `height`) con la base en `pos`: cuatro
-- CornerWedge con la punta en el centro.
local function pyramid(ctx: Context, base: CFrame, name: string, key: string, side: number, height: number, pos: { number })
	local frame = at(base, pos)
	local s = side / 2
	for _, quadrant in { { -1, 1, 0 }, { 1, 1, 90 }, { 1, -1, 180 }, { -1, -1, 270 } } do
		local piece = Instance.new("CornerWedgePart")
		piece.Size = Vector3.new(s, height, s)
		piece.CFrame = frame * CFrame.new(quadrant[1] * s / 2, height / 2, quadrant[2] * s / 2) * CFrame.Angles(0, math.rad(quadrant[3]), 0)
		finish(piece, ctx, name, key)
	end
end

-- Cristal octaédrico (cubo girado).
local function gem(ctx: Context, base: CFrame, name: string, key: string, size: number, pos: { number }, scale: { number }?)
	local sc = scale or { 1, 1, 1 }
	local piece = Instance.new("Part")
	piece.Size = Vector3.new(size * sc[1], size * sc[2], size * sc[3])
	piece.CFrame = at(base, pos) * CFrame.Angles(math.rad(45), 0, math.rad(45))
	finish(piece, ctx, name, key)
end

local function rnd(ctx: Context): number
	ctx.Seed = (ctx.Seed * 16807) % 2147483647
	return ctx.Seed / 2147483647
end

-- Tejado a dos aguas de losas con vuelo, cumbrera y tablas de borde.
local function gableRoof(ctx: Context, base: CFrame, opts: any)
	local thick = opts.thick or 0.45
	local r = group(base, { opts.x or 0, opts.y, opts.z or 0 }, if opts.alongZ then math.pi / 2 else 0)
	local hs = opts.span / 2
	local hyp = math.sqrt(hs * hs + opts.rise * opts.rise)
	local a = math.atan2(opts.rise, hs)
	local ca, sa = hs / hyp, opts.rise / hyp
	local L = hyp + opts.ov
	for _, s in { 1, -1 } do
		local cz = s * (hs / 2 + ca * opts.ov / 2 + sa * thick / 2)
		local cy = opts.rise / 2 - sa * opts.ov / 2 + ca * thick / 2
		box(ctx, r, if s > 0 then "RoofFront" else "RoofBack", "roof", { opts.len, thick, L }, { 0, cy, cz }, { s * a, 0, 0 })
		if opts.trim then
			for _, sx in { 1, -1 } do
				box(ctx, r, "Bargeboard", opts.trim, { 0.3, thick + 0.3, L + 0.05 }, { sx * (opts.len / 2 + 0.15), cy - 0.05, cz }, { s * a, 0, 0 })
			end
		end
	end
	box(ctx, r, "Ridge", "roof_dark", { opts.len + (if opts.trim then 0.7 else 0.3), 0.5, 0.75 }, { 0, opts.rise + thick * 0.85, 0 })
end

local function lantern(ctx: Context, base: CFrame, pos: { number }, s: number)
	local l = group(base, pos)
	box(ctx, l, "LanternCap", "beam", { s * 1.3, s * 0.25, s * 1.3 }, { 0, s * 0.62, 0 })
	local glass = box(ctx, l, "LanternGlass", "lamp", { s, s, s }, { 0, 0, 0 })
	box(ctx, l, "LanternBase", "beam", { s * 1.1, s * 0.18, s * 1.1 }, { 0, -s * 0.58, 0 })
	local light = Instance.new("PointLight")
	light.Color = MATS.lamp.Color
	light.Range = 10
	light.Brightness = 0.8
	light.Shadows = false
	light.Parent = glass
end

local function flowerBox(ctx: Context, base: CFrame, w: number, pos: { number })
	local b = group(base, pos)
	box(ctx, b, "Planter", "wood", { w, 0.45, 0.55 }, { 0, 0, 0 })
	local n = math.max(3, math.floor(w / 0.45 + 0.5))
	for i = 0, n - 1 do
		local x = -w / 2 + 0.25 + i * (w - 0.5) / (n - 1)
		if i % 2 == 0 then
			ball(ctx, b, "Leaves", "leaf", 0.22, { x, 0.28, -0.05 })
		end
		ball(ctx, b, "Flower", FLOWERS[(i % 4) + 1], 0.16, { x + 0.05, 0.42, 0.08 })
	end
end

-- Ventana (mira a +Z): marco, cruz, alféizar, dintel, contraventanas y jardinera.
local function windowUnit(ctx: Context, base: CFrame, pos: { number }, yaw: number, opts: any)
	local w, h = opts.w or 1.8, opts.h or 1.8
	local u = group(base, pos, yaw)
	box(ctx, u, "Glass", "glass", { w, h, 0.2 }, { 0, 0, 0 })
	if opts.arch then
		cyl(ctx, u, "GlassArch", "glass", w / 2, 0.2, { 0, h / 2, 0 }, "z")
	end
	local f = 0.2
	for _, sx in { -1, 1 } do
		box(ctx, u, "Frame", "beam", { f, h + f, 0.3 }, { sx * (w / 2 + f / 2 - 0.02), 0, 0.05 })
	end
	if not opts.arch then
		box(ctx, u, "Frame", "beam", { w + f * 2, f, 0.3 }, { 0, h / 2 + f / 2 - 0.02, 0.05 })
	end
	box(ctx, u, "Mullion", "beam", { 0.12, h, 0.26 }, { 0, 0, 0.03 })
	box(ctx, u, "Transom", "beam", { w, 0.12, 0.26 }, { 0, if opts.arch then 0 else h * 0.12, 0.03 })
	box(ctx, u, "Sill", opts.lintel or "beam", { w + 0.55, 0.22, 0.5 }, { 0, -h / 2 - 0.1, 0.15 })
	if opts.lintel and not opts.arch then
		box(ctx, u, "Lintel", opts.lintel, { w + 0.7, 0.45, 0.36 }, { 0, h / 2 + 0.2, 0.08 })
	end
	if opts.shutters then
		for _, sx in { -1, 1 } do
			local sw = w * 0.46
			box(ctx, u, "Shutter", opts.shutters, { sw, h + 0.1, 0.14 }, { sx * (w / 2 + sw / 2 + 0.22), 0, 0.08 })
			box(ctx, u, "ShutterSlat", "cream", { sw * 0.7, 0.1, 0.16 }, { sx * (w / 2 + sw / 2 + 0.22), h * 0.25, 0.09 })
			box(ctx, u, "ShutterSlat", "cream", { sw * 0.7, 0.1, 0.16 }, { sx * (w / 2 + sw / 2 + 0.22), -h * 0.25, 0.09 })
		end
	end
	if opts.planter ~= false then
		flowerBox(ctx, u, w + 0.3, { 0, -h / 2 - 0.45, 0.4 })
	end
end

-- Puerta en arco (mira a +Z) con la base en `pos`.
local function archDoor(ctx: Context, base: CFrame, pos: { number }, opts: any)
	local w, h = opts.w or 2.4, opts.h or 3
	local surround, leaf = opts.surround or "stone_light", opts.m or "door"
	local d = group(base, pos)
	box(ctx, d, "Surround", surround, { w + 0.8, h, 0.16 }, { 0, h / 2, -0.02 })
	cyl(ctx, d, "SurroundArch", surround, w / 2 + 0.4, 0.16, { 0, h, -0.02 }, "z")
	box(ctx, d, "DoorLeaf", leaf, { w, h, 0.26 }, { 0, h / 2, 0.06 })
	cyl(ctx, d, "DoorArch", leaf, w / 2, 0.26, { 0, h, 0.06 }, "z")
	for _, x in { -w / 6, w / 6 } do
		box(ctx, d, "PlankGap", "beam", { 0.06, h + w * 0.4, 0.3 }, { x, (h + w * 0.4) / 2, 0.06 })
	end
	for _, y in { h * 0.22, h * 0.78 } do
		box(ctx, d, "Hinge", "iron", { w * 0.55, 0.14, 0.32 }, { -w * 0.18, y, 0.07 })
	end
	ball(ctx, d, "Knob", "gold", 0.15, { w * 0.32, h * 0.5, 0.26 })
end

local function ivy(ctx: Context, base: CFrame, cx: number, cz: number, axis: string, y0: number, y1: number, n: number)
	for _ = 1, n do
		local t = rnd(ctx)
		local y = y0 + t * (y1 - y0)
		local spread = (1 - t * 0.6) * 1.6
		local o = (rnd(ctx) - 0.3) * spread
		local pos = if axis == "x" then { cx + o, y, cz + 0.15 } else { cx + 0.15 * math.sign(cx), y, cz + o }
		ball(ctx, base, "Ivy", if rnd(ctx) > 0.4 then "leaf" else "leaf_dark", 0.3 + rnd(ctx) * 0.3, pos)
	end
end

local function bush(ctx: Context, base: CFrame, pos: { number }, r: number)
	local b = group(base, pos)
	ball(ctx, b, "BushLeaves", "leaf", r, { 0, 0, 0 })
	ball(ctx, b, "BushLeaves", "leaf_dark", r * 0.75, { r * 0.6, -r * 0.15, -r * 0.2 })
	for i = 0, 4 do
		local a = i * 1.3
		ball(ctx, b, "Bloom", FLOWERS[(i % 4) + 1], 0.16, { math.cos(a) * r * 0.75, r * 0.35 + (i % 2) * 0.2, math.sin(a) * r * 0.5 + r * 0.45 })
	end
end

local CORNERS = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

-- A · Casa de entramado (dos plantas) ---------------------------------------------------------
function VillageHouses.timber(ctx: Context, g: CFrame): any
	local W, D = 11, 9
	box(ctx, g, "Plinth", "darkstone", { W + 0.8, 1, D + 0.8 }, { 0, 0.5, 0 })
	box(ctx, g, "GroundWalls", "stone", { W, 4.5, D }, { 0, 3.25, 0 })
	for _, c in CORNERS do
		for i = 0, 5 do
			local long = i % 2 == 0
			box(ctx, g, "Quoin", "stone_light", { if long then 1.4 else 0.9, 0.62, if long then 0.9 else 1.4 }, { c[1] * (W / 2 - (if long then 0.6 else 0.35) + 0.06), 1.36 + i * 0.74, c[2] * (D / 2 - (if long then 0.35 else 0.6) + 0.06) })
		end
	end
	box(ctx, g, "FloorBand", "beam", { W + 1.5, 0.45, D + 1.5 }, { 0, 5.72, 0 })
	local W2, D2, y2, h2 = W + 1.2, D + 1.2, 5.95, 4
	local yT = y2 + h2
	box(ctx, g, "UpperWalls", "plaster", { W2, h2, D2 }, { 0, y2 + h2 / 2, 0 })
	for _, c in CORNERS do
		box(ctx, g, "Post", "beam", { 0.5, h2, 0.5 }, { c[1] * W2 / 2, y2 + h2 / 2, c[2] * D2 / 2 })
	end
	box(ctx, g, "TopPlate", "beam", { W2 + 0.2, 0.4, D2 + 0.2 }, { 0, yT - 0.1, 0 })
	local function brace(x0: number, x1: number, z: number, side: boolean?)
		local dx = x1 - x0
		local len = math.sqrt(dx * dx + (h2 - 0.4) ^ 2)
		local a = math.atan2(dx, h2 - 0.4)
		if side then
			box(ctx, g, "Brace", "beam", { 0.35, len, 0.26 }, { z, y2 + h2 / 2, (x0 + x1) / 2 }, { -a, 0, 0 })
		else
			box(ctx, g, "Brace", "beam", { 0.35, len, 0.26 }, { (x0 + x1) / 2, y2 + h2 / 2, z }, { 0, 0, -a })
		end
	end
	for _, zs in { 1, -1 } do
		local z = zs * (D2 / 2 + 0.06)
		for _, s in { -1, 1 } do
			box(ctx, g, "Stud", "beam", { 0.35, h2, 0.26 }, { s * 4.7, y2 + h2 / 2, z })
			box(ctx, g, "Stud", "beam", { 0.35, h2, 0.26 }, { s * 1.5, y2 + h2 / 2, z })
			brace(s * 6.0, s * 4.8, z)
		end
		brace(-1.4, 1.4, z)
		brace(1.4, -1.4, z)
	end
	for _, xs in { 1, -1 } do
		local x = xs * (W2 / 2 + 0.06)
		for _, s in { -1, 1 } do
			brace(s * 5, s * 3.6, x, true)
		end
	end
	-- Tejado empinado y hastiales
	local rise = 5.6
	gableRoof(ctx, g, { len = W2 + 1.8, span = D2, rise = rise, ov = 1.1, y = yT, trim = "beam" })
	for _, s in { -1, 1 } do
		gable(ctx, g, "Gable", "plaster", D2, rise, 0.3, { s * (W2 / 2 - 0.1), yT, 0 })
		box(ctx, g, "KingPost", "beam", { 0.3, rise * 0.75, 0.35 }, { s * (W2 / 2 + 0.06), yT + rise * 0.375, 0 })
		cyl(ctx, g, "GableWindowRim", "beam", 0.85, 0.3, { s * (W2 / 2 + 0.08), yT + 2, 0 }, "x")
		cyl(ctx, g, "GableWindow", "glass", 0.65, 0.34, { s * (W2 / 2 + 0.1), yT + 2, 0 }, "x")
	end
	-- Buhardilla frontal
	local dz = D2 / 2
	box(ctx, g, "Dormer", "plaster", { 3.8, 3.2, 4 }, { 0, yT + 1.6, dz - 2 })
	for _, s in { -1, 1 } do
		box(ctx, g, "DormerPost", "beam", { 0.3, 3.2, 0.3 }, { s * 1.9, yT + 1.6, dz + 0.02 })
	end
	windowUnit(ctx, g, { 0, yT + 1.6, dz + 0.02 }, 0, { w = 1.5, h = 1.6, planter = false })
	gable(ctx, g, "DormerGable", "plaster", 3.8, 1.7, 0.3, { 0, yT + 3.2, dz - 0.15 }, true)
	gableRoof(ctx, g, { len = 4.6, span = 3.8, rise = 1.7, ov = 0.5, thick = 0.35, y = yT + 3.2, z = dz - 1.9, alongZ = true, trim = "beam" })
	-- Chimenea de ladrillo
	local chimney = box(ctx, g, "Chimney", "brick", { 1.8, 9.4, 1.8 }, { 3.6, 12.7, -2.2 })
	box(ctx, g, "ChimneyBand", "darkstone", { 2.1, 0.3, 2.1 }, { 3.6, 16.2, -2.2 })
	box(ctx, g, "ChimneyCap", "darkstone", { 2.3, 0.4, 2.3 }, { 3.6, 17.5, -2.2 })
	for _, x in { 3.2, 4.0 } do
		cyl(ctx, g, "ChimneyPot", "brick_dark", 0.3, 0.8, { x, 18.1, -2.2 }, "y")
	end
	-- Fachada baja
	archDoor(ctx, g, { 0, 1, D / 2 }, { w = 2.4, h = 2.9 })
	for _, s in { -1, 1 } do
		windowUnit(ctx, g, { s * 3.6, 3.5, D / 2 + 0.02 }, 0, { w = 1.6, h = 1.8, lintel = "stone_light" })
		windowUnit(ctx, g, { s * 3.3, 8, D2 / 2 + 0.02 }, 0, { w = 1.8, h = 1.9, shutters = "roof" })
		windowUnit(ctx, g, { s * (W2 / 2 + 0.02), 8, 0 }, s * math.pi / 2, { w = 1.8, h = 1.9, shutters = "roof" })
		windowUnit(ctx, g, { s * (W / 2 + 0.02), 3.5, 0 }, s * math.pi / 2, { w = 1.6, h = 1.8, lintel = "stone_light" })
		box(ctx, g, "LanternArm", "iron", { 0.14, 0.14, 0.6 }, { s * 2.05, 4.75, D / 2 + 0.3 })
		lantern(ctx, g, { s * 2.05, 4.3, D / 2 + 0.6 }, 0.6)
	end
	windowUnit(ctx, g, { 0, 8, -D2 / 2 - 0.02 }, math.pi, { w = 1.8, h = 1.9, shutters = "roof" })
	box(ctx, g, "Step", "stone_light", { 3.6, 0.5, 1.3 }, { 0, 0.25, D / 2 + 1.05 })
	box(ctx, g, "Step", "stone_light", { 3.2, 0.5, 0.5 }, { 0, 0.75, D / 2 + 0.65 })
	ivy(ctx, g, -W / 2, D / 2, "x", 1.2, 6.2, 18)
	ivy(ctx, g, -W / 2, D / 2 - 0.8, "z", 1.2, 4.5, 10)
	bush(ctx, g, { 2.9, 1, D / 2 + 1.6 }, 0.9)
	bush(ctx, g, { -3, 1, D / 2 + 1.6 }, 0.8)
	return { Chimneys = { chimney }, Door = at(g, { 0, 1, D / 2 + 2.2 }) }
end

-- B · Cabaña con torre --------------------------------------------------------------------------
function VillageHouses.tower(ctx: Context, g: CFrame): any
	local W, D, wb, h = 10, 8, 0.8, 4.6
	local top = wb + h
	box(ctx, g, "Plinth", "stone", { W + 0.6, wb, D + 0.6 }, { 0, wb / 2, 0 })
	box(ctx, g, "Walls", "plaster", { W, h, D }, { 0, wb + h / 2, 0 })
	for _, c in CORNERS do
		box(ctx, g, "Post", "beam", { 0.5, h, 0.5 }, { c[1] * W / 2, wb + h / 2, c[2] * D / 2 })
	end
	box(ctx, g, "SillBeam", "beam", { W + 0.2, 0.35, D + 0.2 }, { 0, wb + 0.17, 0 })
	box(ctx, g, "TopPlate", "beam", { W + 0.2, 0.4, D + 0.2 }, { 0, top - 0.15, 0 })
	local rise = 6.2
	gableRoof(ctx, g, { len = W + 1.4, span = D, rise = rise, ov = 1.0, y = top, trim = "beam" })
	for _, s in { -1, 1 } do
		gable(ctx, g, "Gable", "plaster", D, rise, 0.3, { s * (W / 2 - 0.1), top, 0 })
		for _, zz in { -1, 1 } do
			local len = math.sqrt(4 + (rise * 0.6) ^ 2)
			box(ctx, g, "GableBrace", "beam", { 0.3, len, 0.3 }, { s * (W / 2 + 0.06), top + rise * 0.3, zz * 1.2 }, { zz * math.atan2(2, rise * 0.6) * 0.9, 0, 0 })
		end
		cyl(ctx, g, "GableWindowRim", "beam", 0.75, 0.3, { s * (W / 2 + 0.08), top + 2.6, 0 }, "x")
		cyl(ctx, g, "GableWindow", "glass", 0.55, 0.34, { s * (W / 2 + 0.1), top + 2.6, 0 }, "x")
	end
	-- Torre con chapitel
	local tx, tz, T = -3.4, D / 2 - 0.6, 4.2
	box(ctx, g, "TowerBase", "stone", { T + 0.4, 3, T + 0.4 }, { tx, 1.5, tz })
	box(ctx, g, "TowerWalls", "plaster", { T, 8.2, T }, { tx, 7.1, tz })
	box(ctx, g, "TowerBand", "beam", { T + 0.5, 0.4, T + 0.5 }, { tx, 3.1, tz })
	box(ctx, g, "TowerTop", "beam", { T + 0.5, 0.5, T + 0.5 }, { tx, 11.1, tz })
	for _, c in CORNERS do
		box(ctx, g, "TowerPost", "beam", { 0.4, 8, 0.4 }, { tx + c[1] * T / 2, 7.1, tz + c[2] * T / 2 })
	end
	pyramid(ctx, g, "TowerSpire", "roof", T + 1.6, 5.8, { tx, 11.35, tz })
	cyl(ctx, g, "FinialRod", "iron", 0.08, 1.2, { tx, 17.6, tz }, "y")
	ball(ctx, g, "Finial", "gold", 0.35, { tx, 17.5, tz })
	windowUnit(ctx, g, { tx, 5.8, tz + T / 2 + 0.02 }, 0, { w = 1.1, h = 1.8, arch = true, lintel = "beam" })
	cyl(ctx, g, "TowerRoundRim", "beam", 0.8, 0.3, { tx, 9.2, tz + T / 2 + 0.06 }, "z")
	cyl(ctx, g, "TowerRound", "glass", 0.6, 0.34, { tx, 9.2, tz + T / 2 + 0.08 }, "z")
	windowUnit(ctx, g, { tx - T / 2 - 0.02, 7.6, tz }, -math.pi / 2, { w = 1.1, h = 1.8, arch = true, planter = false })
	ivy(ctx, g, tx - T / 2 - 0.1, tz + T / 2, "x", 0.4, 4.2, 12)
	-- Buhardilla
	local dx = 2.6
	box(ctx, g, "Dormer", "plaster", { 2.6, 2.4, 2.4 }, { dx, 8.2, 1.5 })
	for _, s in { -1, 1 } do
		box(ctx, g, "DormerPost", "beam", { 0.25, 2.4, 0.25 }, { dx + s * 1.3, 8.2, 2.72 })
	end
	windowUnit(ctx, g, { dx, 8.2, 2.72 }, 0, { w = 1.2, h = 1.3, planter = false })
	gable(ctx, g, "DormerGable", "plaster", 2.6, 1.3, 0.3, { dx, 9.4, 2.55 }, true)
	gableRoof(ctx, g, { len = 3.4, span = 2.6, rise = 1.3, ov = 0.4, thick = 0.3, y = 9.4, x = dx, z = 1.4, alongZ = true, trim = "beam" })
	-- Chimenea exterior
	box(ctx, g, "ChimneyBase", "stone", { 2, 3, 1.8 }, { W / 2 + 0.8, 1.5, -2 })
	local chimney = box(ctx, g, "Chimney", "brick", { 1.5, 10.4, 1.4 }, { W / 2 + 0.75, 8.2, -2 })
	box(ctx, g, "ChimneyCap", "darkstone", { 2, 0.4, 1.9 }, { W / 2 + 0.75, 13.6, -2 })
	cyl(ctx, g, "ChimneyPot", "brick_dark", 0.3, 0.8, { W / 2 + 0.75, 14.2, -2 }, "y")
	-- Fachada
	archDoor(ctx, g, { 1, wb, D / 2 }, { w = 2.1, h = 2.7, surround = "wood" })
	lantern(ctx, g, { -0.55, wb + 3.1, D / 2 + 0.45 }, 0.55)
	box(ctx, g, "LanternArm", "iron", { 0.14, 0.14, 0.5 }, { -0.55, wb + 3.55, D / 2 + 0.22 })
	windowUnit(ctx, g, { 3.6, 3.1, D / 2 + 0.02 }, 0, { w = 1.6, h = 1.7, shutters = "roof" })
	windowUnit(ctx, g, { W / 2 + 0.02, 3.1, 1.8 }, math.pi / 2, { w = 1.6, h = 1.7, shutters = "roof" })
	windowUnit(ctx, g, { -W / 2 - 0.02, 3.1, -1.6 }, -math.pi / 2, { w = 1.6, h = 1.7, shutters = "roof" })
	windowUnit(ctx, g, { 0, 3.1, -D / 2 - 0.02 }, math.pi, { w = 1.6, h = 1.7, shutters = "roof" })
	box(ctx, g, "Step", "stone_light", { 2.8, 0.4, 1.1 }, { 1, 0.2, D / 2 + 0.85 })
	for i = 0, 3 do
		cyl(ctx, g, "SteppingStone", if i % 2 == 1 then "stone" else "stone_light", 0.6 + (i % 2) * 0.1, 0.18, { 1 + (if i % 2 == 1 then 0.3 else -0.25), 0.09, D / 2 + 2.2 + i * 1.4 }, "y")
	end
	bush(ctx, g, { 4.6, 0.9, D / 2 + 1.2 }, 0.8)
	return { Chimneys = { chimney }, Door = at(g, { 1, 1, D / 2 + 2 }) }
end

-- C · Tienda con escaparate -----------------------------------------------------------------------
-- opts.Display = "Crystals" (Tienda) | "Gifts" (Premios). Devuelve el friso para el texto.
function VillageHouses.shop(ctx: Context, g: CFrame, opts: any): any
	local W, D = 10, 11
	local fz = D / 2
	box(ctx, g, "Plinth", "stone", { W + 0.6, 1, D + 0.6 }, { 0, 0.5, 0 })
	box(ctx, g, "GroundWalls", "plaster", { W, 4.6, D }, { 0, 3.3, 0 })
	box(ctx, g, "FloorBand", "beam", { W + 0.4, 0.45, D + 0.4 }, { 0, 5.82, 0 })
	local y2, h2 = 6.05, 4.2
	local yT = y2 + h2
	box(ctx, g, "UpperWalls", "plaster", { W, h2, D }, { 0, y2 + h2 / 2, 0 })
	for _, c in CORNERS do
		box(ctx, g, "Post", "beam", { 0.5, 9.3, 0.5 }, { c[1] * W / 2, 5.6, c[2] * D / 2 })
	end
	box(ctx, g, "TopPlate", "beam", { W + 0.2, 0.4, D + 0.2 }, { 0, yT - 0.1, 0 })
	local rise = 5
	gableRoof(ctx, g, { len = D + 1.8, span = W, rise = rise, ov = 1.0, y = yT, alongZ = true, trim = "beam" })
	for _, s in { -1, 1 } do
		gable(ctx, g, "Gable", "plaster", W, rise, 0.3, { 0, yT, s * (D / 2 - 0.1) }, true)
		box(ctx, g, "KingPost", "beam", { 0.3, rise * 0.75, 0.3 }, { 0, yT + rise * 0.375, s * (D / 2 + 0.06) })
		for _, sx in { -1, 1 } do
			box(ctx, g, "GableBrace", "beam", { 0.3, 3.1, 0.3 }, { sx * 1.5, yT + 1.1, s * (D / 2 + 0.06) }, { 0, 0, sx * -0.95 })
		end
	end
	cyl(ctx, g, "GableWindowRim", "beam", 0.85, 0.34, { 0, yT + 2.3, fz + 0.1 }, "z")
	cyl(ctx, g, "GableWindow", "glass", 0.65, 0.38, { 0, yT + 2.3, fz + 0.12 }, "z")
	-- Escaparate
	local sx0, sw = -1.7, 5.2
	local fascia = box(ctx, g, "Fascia", "sign", { W - 0.5, 1, 0.3 }, { 0, 5.05, fz + 0.15 })
	for _, x in { -4.6, 0.95, 4.6 } do
		box(ctx, g, "Pilaster", "roof", { 0.5, 3.9, 0.4 }, { x, 2.95, fz + 0.12 })
	end
	box(ctx, g, "DisplayPanel", "roof", { sw, 1, 0.3 }, { sx0, 1.5, fz + 0.1 })
	box(ctx, g, "DisplayGlass", "glass", { sw, 2.5, 0.2 }, { sx0, 3.25, fz + 0.05 })
	for i = 1, 3 do
		box(ctx, g, "DisplayMullion", "beam", { 0.14, 2.5, 0.28 }, { sx0 - sw / 2 + i * sw / 4, 3.25, fz + 0.08 })
	end
	box(ctx, g, "DisplayTransom", "beam", { sw, 0.14, 0.28 }, { sx0, 4.0, fz + 0.08 })
	box(ctx, g, "DisplaySill", "beam", { sw + 0.3, 0.2, 0.55 }, { sx0, 2.0, fz + 0.25 })
	for i = 0, 3 do
		local x = sx0 - 1.95 + i * 1.3
		if opts.Display == "Gifts" then
			box(ctx, g, "DisplayGift", FLOWERS[(i % 4) + 1], { 0.6, 0.6, 0.6 }, { x, 2.4, fz + 0.45 })
			box(ctx, g, "DisplayRibbon", "gold", { 0.64, 0.12, 0.64 }, { x, 2.45, fz + 0.45 })
			box(ctx, g, "DisplayRibbon", "gold", { 0.12, 0.64, 0.64 }, { x, 2.4, fz + 0.45 })
		else
			gem(ctx, g, "DisplayCrystal", "crystal", 0.42, { x, 2.5, fz + 0.45 })
		end
	end
	-- Puerta de tienda
	box(ctx, g, "ShopDoor", "door", { 2, 3.3, 0.26 }, { 2.8, 2.65, fz + 0.06 })
	box(ctx, g, "ShopDoorGlass", "glass", { 1.3, 1.2, 0.3 }, { 2.8, 3.4, fz + 0.07 })
	box(ctx, g, "ShopDoorFrame", "beam", { 2.4, 0.25, 0.34 }, { 2.8, 4.4, fz + 0.1 })
	ball(ctx, g, "Knob", "gold", 0.14, { 3.5, 2.6, fz + 0.26 })
	box(ctx, g, "Step", "stone_light", { 2.6, 0.5, 1.2 }, { 2.8, 0.25, fz + 0.9 })
	-- Toldo de rayas con faldón
	local n, aw, tilt, adepth = 10, W - 0.6, 0.42, 2.4
	local stw = aw / n
	for i = 0, n - 1 do
		local x = -aw / 2 + stw * (i + 0.5)
		local key = if i % 2 == 1 then "cream" else "roof_fabric"
		box(ctx, g, "Awning", key, { stw + 0.01, 0.14, adepth }, { x, 4.85 - math.sin(tilt) * adepth / 2, fz + 0.3 + math.cos(tilt) * adepth / 2 }, { tilt, 0, 0 })
		box(ctx, g, "Valance", key, { stw + 0.01, 0.5, 0.08 }, { x, 4.85 - math.sin(tilt) * adepth - 0.2, fz + 0.3 + math.cos(tilt) * adepth })
	end
	for _, x in { -aw / 2, aw / 2 } do
		box(ctx, g, "AwningArm", "iron", { 0.1, 0.1, 2.4 }, { x, 4.4, fz + 1.3 }, { tilt, 0, 0 })
	end
	-- Balcón con flores
	local by, bz, bw = y2, fz + 0.8, 5.4
	box(ctx, g, "BalconyFloor", "wood", { bw, 0.3, 1.6 }, { 0, by, bz })
	for _, x in { -2.2, 2.2 } do
		wedge(ctx, g, "BalconyBracket", "beam", { 0.3, 1, 1.4 }, { x, by - 0.65, fz + 0.7 }, -1)
	end
	for i = 0, 9 do
		box(ctx, g, "Baluster", "wood", { 0.14, 0.9, 0.14 }, { -bw / 2 + 0.15 + i * (bw - 0.3) / 9, by + 0.6, bz + 0.7 })
	end
	for _, s in { -1, 1 } do
		for i = 0, 1 do
			box(ctx, g, "Baluster", "wood", { 0.14, 0.9, 0.14 }, { s * (bw / 2 - 0.15), by + 0.6, fz + 0.3 + i * 0.6 })
		end
	end
	box(ctx, g, "Rail", "beam", { bw, 0.2, 0.26 }, { 0, by + 1.1, bz + 0.7 })
	for _, s in { -1, 1 } do
		box(ctx, g, "Rail", "beam", { 0.26, 0.2, 1.6 }, { s * (bw / 2 - 0.15), by + 1.1, bz })
		flowerBox(ctx, g, 1.6, { s * 1.6, by + 1.4, bz + 0.72 })
	end
	box(ctx, g, "BalconyDoor", "glass", { 1.6, 2.6, 0.2 }, { 0, by + 1.5, fz + 0.02 })
	box(ctx, g, "BalconyDoorFrame", "beam", { 1.9, 0.22, 0.3 }, { 0, by + 2.85, fz + 0.06 })
	for _, s in { -1, 1 } do
		box(ctx, g, "BalconyDoorFrame", "beam", { 0.2, 2.7, 0.3 }, { s * 0.9, by + 1.5, fz + 0.06 })
	end
	box(ctx, g, "BalconyDoorMullion", "beam", { 0.12, 2.6, 0.26 }, { 0, by + 1.5, fz + 0.05 })
	for _, s in { -1, 1 } do
		windowUnit(ctx, g, { s * 3.5, 8.3, fz + 0.02 }, 0, { w = 1.3, h = 1.8, shutters = "roof", planter = false })
	end
	for _, s in { -1, 1 } do
		for _, z in { -2.6, 2.6 } do
			windowUnit(ctx, g, { s * (W / 2 + 0.02), 8.2, z }, s * math.pi / 2, { w = 1.6, h = 1.8, shutters = "roof" })
			windowUnit(ctx, g, { s * (W / 2 + 0.02), 3.4, z }, s * math.pi / 2, { w = 1.6, h = 1.8, lintel = "beam", planter = false })
		end
	end
	-- Cartel colgante
	box(ctx, g, "SignArm", "iron", { 0.16, 0.16, 2.4 }, { 4.75, 7.7, fz + 1.2 })
	box(ctx, g, "SignBrace", "iron", { 0.12, 1.5, 0.12 }, { 4.75, 7.1, fz + 0.5 }, { -0.8, 0, 0 })
	for _, z in { fz + 0.9, fz + 2.1 } do
		cyl(ctx, g, "SignChain", "iron", 0.04, 0.5, { 4.75, 7.4, z }, "y")
	end
	local hanging = box(ctx, g, "SignBoard", "sign", { 0.22, 1.5, 1.8 }, { 4.75, 6.4, fz + 1.5 })
	box(ctx, g, "SignTrim", "gold", { 0.26, 0.12, 1.9 }, { 4.75, 7.15, fz + 1.5 })
	-- Chimenea, cajas y barriles
	local chimney = box(ctx, g, "Chimney", "brick", { 1.6, 5.4, 1.6 }, { -2.6, 13.9, -3 })
	box(ctx, g, "ChimneyCap", "darkstone", { 2, 0.4, 2 }, { -2.6, 16.7, -3 })
	box(ctx, g, "Crate", "wood", { 1.4, 1.4, 1.4 }, { -4.1, 0.7, fz + 1.7 }, { 0, 0.3, 0 })
	box(ctx, g, "Crate", "wood", { 1, 1, 1 }, { -4.2, 1.9, fz + 1.7 }, { 0, -0.2, 0 })
	for _, spot in { { 4.4, fz + 1.4 }, { 5.3, fz + 0.4 } } do
		cyl(ctx, g, "Barrel", "door", 0.7, 1.8, { spot[1], 0.9, spot[2] }, "y")
		for _, y in { 0.4, 1.4 } do
			cyl(ctx, g, "BarrelHoop", "iron", 0.73, 0.12, { spot[1], y, spot[2] }, "y")
		end
	end
	lantern(ctx, g, { -4.75, 7.9, fz + 0.45 }, 0.6)
	return { Chimneys = { chimney }, Fascia = fascia, Hanging = hanging, Door = at(g, { 1.2, 1, fz + 2.6 }) }
end

-- Contexto de una casa: modelo, color del tejado y semilla de la hiedra.
function VillageHouses.context(model: Model, roof: Color3, roofName: string, seed: number): Context
	return {
		Model = model,
		Roof = roof,
		RoofDark = roof:Lerp(Color3.new(0, 0, 0), 0.25),
		RoofMaterial = if roofName == "Red" or roofName == "Orange" then CLAY_ROOF else SHINGLES,
		Seed = seed,
	}
end

return VillageHouses
