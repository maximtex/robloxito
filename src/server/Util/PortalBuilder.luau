-- Portales entre zonas con el diseño "Portal del Renacimiento" de Santiago (Claude Design).
-- Las piezas salen de PortalDesign (generado desde su OBJ): tarima redonda con tres anillos
-- de runas, arco de bloques antiguos con runas y cristales, cristal dorado en la clave,
-- raíces y musgo, cuatro obeliscos y unas piedras caídas. Aquí se escalan a studs, se
-- colorean según el estilo del portal y se les añade lo que el diseño no traía: la energía
-- del hueco del arco, sus chispas y la luz.
--
-- Estilos: Ancient (bosque -> Valle, el diseño tal cual), Return (vuelta al bosque: piedra
-- lavanda y energía verde), Ember (Valle -> Caldera: basalto, ceniza y energía de lava) y
-- Goblin (el portal gigante de la Fortaleza al Mundo 2: piedra oscura con musgo, oro y
-- energía verde).

local PortalDesign = require(script.Parent.PortalDesign)

local PortalBuilder = {}

type Look = { Color: Color3, Material: Enum.Material }

local RGB = Color3.fromRGB
local M = Enum.Material

-- Paleta del diseño (claves = materiales del OBJ).
local BASE: { [string]: Look } = {
	darkstone = { Color = RGB(98, 100, 94), Material = M.Slate },
	warmstone = { Color = RGB(198, 184, 156), Material = M.Sandstone },
	stone = { Color = RGB(150, 148, 138), Material = M.Slate },
	ancient = { Color = RGB(176, 170, 152), Material = M.Slate },
	ancient_dark = { Color = RGB(134, 130, 116), Material = M.Slate },
	gold = { Color = RGB(232, 186, 88), Material = M.Metal },
	moss = { Color = RGB(92, 146, 64), Material = M.Grass },
	moss_light = { Color = RGB(130, 180, 84), Material = M.Grass },
	root = { Color = RGB(104, 76, 52), Material = M.Wood },
	rune = { Color = RGB(110, 226, 255), Material = M.Neon },
	edge = { Color = RGB(170, 240, 255), Material = M.Neon },
	rune_ring1 = { Color = RGB(110, 226, 255), Material = M.Neon },
	rune_ring2 = { Color = RGB(188, 132, 255), Material = M.Neon },
	rune_ring3 = { Color = RGB(255, 210, 110), Material = M.Neon },
	crystal_blue = { Color = RGB(110, 176, 255), Material = M.Neon },
	crystal_violet = { Color = RGB(182, 124, 255), Material = M.Neon },
	crystal_gold = { Color = RGB(255, 206, 92), Material = M.Neon },
}

local STYLES = {
	Ancient = {
		Energy = RGB(110, 214, 236),
		Sparks = RGB(182, 124, 255),
		Looks = {},
	},
	Return = {
		Energy = RGB(150, 220, 140),
		Sparks = RGB(182, 124, 255),
		Looks = {
			darkstone = { Color = RGB(112, 110, 132), Material = M.Slate },
			warmstone = { Color = RGB(198, 192, 214), Material = M.Sandstone },
			stone = { Color = RGB(150, 146, 170), Material = M.Slate },
			ancient = { Color = RGB(188, 184, 206), Material = M.Slate },
			ancient_dark = { Color = RGB(140, 136, 162), Material = M.Slate },
			rune = { Color = RGB(150, 236, 150), Material = M.Neon },
			edge = { Color = RGB(200, 255, 196), Material = M.Neon },
			rune_ring1 = { Color = RGB(150, 236, 150), Material = M.Neon },
			crystal_blue = { Color = RGB(120, 232, 180), Material = M.Neon },
		},
	},
	Goblin = {
		Energy = RGB(120, 255, 110),
		Sparks = RGB(255, 220, 90),
		Looks = {
			darkstone = { Color = RGB(58, 62, 52), Material = M.Slate },
			warmstone = { Color = RGB(96, 100, 82), Material = M.Slate },
			stone = { Color = RGB(78, 82, 70), Material = M.Slate },
			ancient = { Color = RGB(92, 96, 80), Material = M.Slate },
			ancient_dark = { Color = RGB(64, 68, 56), Material = M.Slate },
			gold = { Color = RGB(240, 196, 70), Material = M.Metal },
			moss = { Color = RGB(80, 140, 50), Material = M.Grass },
			moss_light = { Color = RGB(110, 170, 64), Material = M.Grass },
			rune = { Color = RGB(120, 255, 110), Material = M.Neon },
			edge = { Color = RGB(200, 255, 170), Material = M.Neon },
			rune_ring1 = { Color = RGB(120, 255, 110), Material = M.Neon },
			rune_ring2 = { Color = RGB(255, 220, 90), Material = M.Neon },
			rune_ring3 = { Color = RGB(255, 120, 80), Material = M.Neon },
			crystal_blue = { Color = RGB(110, 255, 140), Material = M.Neon },
			crystal_violet = { Color = RGB(255, 210, 80), Material = M.Neon },
			crystal_gold = { Color = RGB(255, 236, 120), Material = M.Neon },
		},
	},
	Ember = {
		Energy = RGB(255, 132, 50),
		Sparks = RGB(255, 186, 70),
		Looks = {
			darkstone = { Color = RGB(52, 44, 44), Material = M.Basalt },
			warmstone = { Color = RGB(100, 82, 76), Material = M.Basalt },
			stone = { Color = RGB(76, 64, 62), Material = M.Basalt },
			ancient = { Color = RGB(94, 78, 74), Material = M.Basalt },
			ancient_dark = { Color = RGB(66, 54, 54), Material = M.Basalt },
			gold = { Color = RGB(230, 132, 60), Material = M.Metal },
			moss = { Color = RGB(70, 60, 58), Material = M.Basalt },
			moss_light = { Color = RGB(88, 74, 70), Material = M.Basalt },
			root = { Color = RGB(46, 38, 38), Material = M.Wood },
			rune = { Color = RGB(255, 132, 50), Material = M.Neon },
			edge = { Color = RGB(255, 196, 130), Material = M.Neon },
			rune_ring1 = { Color = RGB(255, 132, 50), Material = M.Neon },
			rune_ring2 = { Color = RGB(255, 86, 40), Material = M.Neon },
			rune_ring3 = { Color = RGB(255, 204, 96), Material = M.Neon },
			crystal_blue = { Color = RGB(255, 118, 36), Material = M.Neon },
			crystal_violet = { Color = RGB(224, 64, 30), Material = M.Neon },
			crystal_gold = { Color = RGB(255, 186, 70), Material = M.Neon },
		},
	},
}

-- Piezas que chocan: se sube a la tarima y no se atraviesan pilares ni obeliscos.
local SOLID = {
	DaisLip = true, Dais = true, Step = true, ArchDais = true, PillarPlinth = true, PillarPlinthCap = true,
	PillarBlock = true, PillarJoint = true, Capital = true, Voussoir = true, KeystoneSocket = true,
	ObeliskBase = true, ObeliskShaft = true, ObeliskTip = true, Rubble = true,
}

local QUARTERS = { { -1, 1, 0 }, { 1, 1, 90 }, { 1, -1, 180 }, { -1, -1, 270 } }
local SIDES = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }
local FAN = 8 -- tramos del medio círculo de energía

function PortalBuilder.styles(): { string }
	local names = {}
	for name in STYLES do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Construye el portal dentro de `model`. `origin`: centro de la tarima en el suelo, con
-- su LookVector hacia donde mira el frente (por donde se llega). Devuelve la losa bajo el
-- arco (para el aviso de proximidad) y la energía del hueco.
function PortalBuilder.build(model: Model, origin: CFrame, scale: number, styleName: string?): (BasePart, BasePart)
	local style = STYLES[styleName or "Ancient"] or STYLES.Ancient
	local s = scale
	-- En el diseño el frente mira a +Z: media vuelta para que mire al LookVector.
	local frame = origin * CFrame.Angles(0, math.pi, 0)

	local function look(key: string): Look
		return style.Looks[key] or BASE[key] or BASE.stone
	end

	local function finish(piece: BasePart, name: string, key: string)
		local spec = look(key)
		piece.Name = name
		piece.Anchored = true
		piece.CanTouch = false
		piece.Color = spec.Color
		piece.Material = spec.Material
		piece.TopSurface = Enum.SurfaceType.Smooth
		piece.BottomSurface = Enum.SurfaceType.Smooth
		if not SOLID[name] then
			piece.CanCollide = false
			piece.CanQuery = false
			piece.CastShadow = false
		elseif spec.Material == M.Neon then
			piece.CastShadow = false
		end
		piece.Parent = model
	end

	local function block(name: string, key: string, cframe: CFrame, size: Vector3): Part
		local piece = Instance.new("Part")
		piece.Size = size
		piece.CFrame = cframe
		finish(piece, name, key)
		return piece
	end

	-- Pirámide de base cuadrada (cuatro CornerWedge) con la base en `base` y la punta en su +Y.
	local function pyramid(name: string, key: string, base: CFrame, side: number, height: number)
		local q = side / 2
		for _, quarter in QUARTERS do
			local piece = Instance.new("CornerWedgePart")
			piece.Size = Vector3.new(q, height, q)
			piece.CFrame = base * CFrame.new(quarter[1] * q / 2, height / 2, quarter[2] * q / 2) * CFrame.Angles(0, math.rad(quarter[3]), 0)
			finish(piece, name, key)
		end
	end

	local function at(p: { any }, i: number): CFrame
		return frame * CFrame.new(p[i] * s, p[i + 1] * s, p[i + 2] * s)
	end
	local function turn(p: { any }, i: number): CFrame
		return CFrame.Angles(math.rad(p[i]), math.rad(p[i + 1]), math.rad(p[i + 2]))
	end

	local anchor: BasePart? = nil
	for _, p in PortalDesign.Parts do
		local kind, name, key = p[1], p[2], p[3]
		if kind == "Box" then
			local piece = block(name, key, at(p, 4) * turn(p, 10), Vector3.new(p[7], p[8], p[9]) * s)
			if name == "ArchDais" then
				anchor = piece
			end
		elseif kind == "Ball" then
			local piece = block(name, key, at(p, 4) * turn(p, 10), Vector3.new(p[7], p[8], p[9]) * s)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = piece
		elseif kind == "Glyph" then
			-- Rombo plano: un cuadrado fino girado 45° en su plano.
			local side = p[7] / math.sqrt(2) * s
			block(name, key, at(p, 4) * turn(p, 9) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(side, side, p[8] * s))
		elseif kind == "Crystal" then
			-- Octaedro: dos pirámides unidas por la base, con las esquinas sobre los ejes.
			local center = at(p, 4) * turn(p, 9)
			local side, half = p[8] / math.sqrt(2) * s, p[7] / 2 * s
			pyramid(name, key, center * CFrame.Angles(0, math.rad(45), 0), side, half)
			pyramid(name, key, center * CFrame.Angles(math.pi, 0, 0) * CFrame.Angles(0, math.rad(45), 0), side, half)
		elseif kind == "Disc" then
			local piece = block(name, key, at(p, 4) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(p[8], p[7], p[7]) * s)
			piece.Shape = Enum.PartType.Cylinder
		elseif kind == "Rod" then
			local a = frame * (Vector3.new(p[4], p[5], p[6]) * s)
			local b = frame * (Vector3.new(p[7], p[8], p[9]) * s)
			local piece = block(name, key, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new((b - a).Magnitude, p[10] * s, p[10] * s))
			piece.Shape = Enum.PartType.Cylinder
		elseif kind == "Frustum" then
			-- Tronco de pirámide: un bloque con el lado de arriba y cuatro cuñas que lo ensanchan abajo.
			local base = at(p, 4) * CFrame.Angles(0, math.rad(p[10]), 0)
			local height, bottom, top = p[7] * s, p[8] * s, p[9] * s
			block(name, key, base * CFrame.new(0, height / 2, 0), Vector3.new(top, height, top))
			local depth, width = (bottom - top) / 2, (bottom + top) / 2
			for _, side in SIDES do
				local center = base * (side * (top / 2 + depth / 2) + Vector3.new(0, height / 2, 0))
				local outward = base:VectorToWorldSpace(side)
				local piece = Instance.new("WedgePart")
				piece.Size = Vector3.new(width, height, depth)
				piece.CFrame = CFrame.lookAt(center, center + outward, base.UpVector)
				finish(piece, name, key)
			end
		elseif kind == "Pyramid" then
			pyramid(name, key, at(p, 4) * CFrame.Angles(0, math.rad(p[9]), 0), p[8] * s, p[7] * s)
		end
	end

	-- Energía del hueco: rectángulo hasta el arranque del arco y medio círculo encima
	-- (abanico de cuñas que no se solapan, para que el brillo se vea parejo). Dos capas: un
	-- brillo neón translúcido y, envolviéndolo, el campo de fuerza que ondula.
	local opening = PortalDesign.Opening
	local center = Vector3.new(0, opening.Spring, 0)
	local half = math.pi / (2 * FAN)
	local radius = opening.Radius / math.cos(half) -- las esquinas del abanico tocan el borde
	local apothem, chord = radius * math.cos(half), radius * math.sin(half)
	local function layer(name: string, material: Enum.Material, transparency: number, thick: number): BasePart
		local function energy(piece: BasePart, partName: string)
			piece.Name = partName
			piece.Anchored = true
			piece.CanCollide = false
			piece.CanQuery = false
			piece.CanTouch = false
			piece.CastShadow = false
			piece.Color = style.Energy
			piece.Material = material
			piece.Transparency = transparency
			piece.Parent = model
		end
		local rect = Instance.new("Part")
		rect.Size = Vector3.new(opening.HalfWidth * 2 * s, (opening.Spring - opening.Bottom) * s, thick)
		rect.CFrame = frame * CFrame.new(0, (opening.Bottom + opening.Spring) / 2 * s, 0)
		energy(rect, name)
		for index = 0, FAN - 1 do
			local mid = (index + 0.5) * math.pi / FAN
			local u = Vector3.new(math.cos(mid), math.sin(mid), 0)
			local m = center + u * apothem
			for _, angle in { index * math.pi / FAN, (index + 1) * math.pi / FAN } do
				local corner = center + Vector3.new(math.cos(angle), math.sin(angle), 0) * radius
				local v = (corner - m).Unit
				local position = (m + v * (chord / 2) - u * (apothem / 2)) * s
				local piece = Instance.new("WedgePart")
				piece.Size = Vector3.new(thick, chord * s, apothem * s)
				piece.CFrame = frame * CFrame.fromMatrix(position, v:Cross(u), v)
				energy(piece, name .. "Arc")
			end
		end
		return rect
	end
	layer("EnergyGlow", M.Neon, 0.62, 0.012 * s)
	local veil = layer("Energy", M.ForceField, 0.15, 0.03 * s)

	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 10
	sparks.Lifetime = NumberRange.new(1.4, 2.4)
	sparks.Speed = NumberRange.new(0.4, 1.2)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Transparency = NumberSequence.new(0.2, 1)
	sparks.LightEmission = 1
	sparks.Color = ColorSequence.new(style.Energy, style.Sparks)
	sparks.Parent = veil
	local light = Instance.new("PointLight")
	light.Color = style.Energy
	light.Range = 20
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = veil

	-- Brillo del cristal de la clave (se ve de lejos y de noche).
	local keystone = model:FindFirstChild("KeystoneSocket")
	if keystone then
		local glow = Instance.new("PointLight")
		glow.Color = look("crystal_gold").Color
		glow.Range = 12
		glow.Brightness = 1
		glow.Shadows = false
		glow.Parent = keystone
	end

	return anchor or veil, veil
end

return PortalBuilder
