-- Portal de tarima (el del spawn, con el diseño que eligió Santiago de su referencia): un
-- octógono plano en el suelo en vez de un arco:
-- - Marco de tablones de madera (dos tablas por lado, clara dentro y oscura fuera) con
--   herrajes de hierro y un remache dorado en cada esquina. Bajito y sin colisión: se entra
--   caminando.
-- - Dentro, la energía turquesa (Energy: la que mira el cliente para entrar), un campo de
--   fuerza que ondula encima y un remolino de tres brazos (Swirl, lo hace girar el cliente:
--   PortalController), con chispas que suben y luz.
-- - Detrás, un poste con una calavera de bloques y dos huesos cruzados, entre dos antorchas.
--
-- PadPortal.build(model, root, radius) -> (anchor, energy)
--   root: CFrame sobre el suelo, mirando hacia donde se llega (su LookVector).
--   radius: del centro al lado de dentro del marco (la energía).
-- PadPortal.footprint(radius): hasta dónde llega todo (marco, poste y antorchas).

local PadPortal = {}

local RGB = Color3.fromRGB
local M = Enum.Material

PadPortal.FrameWidth = 1.8
local FRAME_HEIGHT = 0.8
local TAN = math.tan(math.rad(22.5))
local COS = math.cos(math.rad(22.5))
local BACK_GAP = 1.6 -- del borde de fuera del marco al poste y las antorchas

local WOOD_LIGHT = RGB(186, 128, 74)
local WOOD_DARK = RGB(146, 94, 52)
local POST_WOOD = RGB(116, 78, 46)
local IRON = RGB(66, 68, 78)
local GOLD = RGB(230, 184, 82)
local BONE = RGB(240, 232, 208)
local HOLE = RGB(28, 26, 30)
local FLOOR = RGB(16, 52, 62)
local ENERGY = RGB(40, 214, 200)
local GLOW = RGB(120, 255, 236)
local SWIRL = RGB(214, 255, 250)
local FLAME = RGB(255, 170, 60)

local function piece(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, solid: boolean?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = solid == true
	part.CanQuery = solid == true
	part.CanTouch = false
	part.Parent = parent
	return part
end

-- Disco plano (cilindro tumbado con el eje en vertical) centrado en `at`
local function disc(parent: Instance, name: string, at: CFrame, radius: number, thick: number, color: Color3, material: Enum.Material): Part
	local part = piece(parent, name, Vector3.new(thick, radius * 2, radius * 2), at * CFrame.Angles(0, 0, math.pi / 2), color, material)
	part.Shape = Enum.PartType.Cylinder
	part.CastShadow = false
	return part
end

-- Marco octogonal: un lado plano mira hacia donde se llega
local function buildFrame(model: Instance, root: CFrame, radius: number)
	local width = PadPortal.FrameWidth
	for index = 0, 7 do
		local side = root * CFrame.Angles(0, math.rad(index * 45), 0)
		-- Dos tablas por lado: la de dentro más corta, como un trapecio
		for strip, color in { WOOD_LIGHT, WOOD_DARK } do
			local apothem = radius + width * (strip * 2 - 1) / 4
			local board = piece(model, "Tabla", Vector3.new(apothem * 2 * TAN + 0.05, FRAME_HEIGHT, width / 2), side * CFrame.new(0, FRAME_HEIGHT / 2, -apothem), color, M.WoodPlanks)
			board.CastShadow = false
		end
		-- Herraje de la esquina con su remache
		local corner = root * CFrame.Angles(0, math.rad(index * 45 + 22.5), 0) * CFrame.new(0, 0, -(radius + width / 2) / COS)
		local bracket = piece(model, "Herraje", Vector3.new(width * 0.95, FRAME_HEIGHT + 0.3, width * 0.95), corner * CFrame.new(0, (FRAME_HEIGHT + 0.3) / 2, 0), IRON, M.Metal)
		bracket.CastShadow = false
		local rivet = piece(model, "Remache", Vector3.new(0.3, 0.7, 0.7), corner * CFrame.new(0, FRAME_HEIGHT + 0.45, 0) * CFrame.Angles(0, 0, math.pi / 2), GOLD, M.Metal)
		rivet.Shape = Enum.PartType.Cylinder
	end
end

-- Remolino de tres brazos en espiral, más fino hacia fuera (el cliente lo gira)
local function buildSwirl(model: Instance, root: CFrame, radius: number)
	local swirl = Instance.new("Model")
	swirl.Name = "Swirl"
	swirl:SetAttribute("SpinRate", 1.3)
	local height = 0.82
	local center = piece(swirl, "SwirlCenter", Vector3.one * 0.2, root * CFrame.new(0, height, 0), SWIRL, M.Neon)
	center.Transparency = 1
	swirl.PrimaryPart = center
	local eye = disc(swirl, "Ojo", root * CFrame.new(0, height, 0), 1.3, 0.06, SWIRL, M.Neon)
	eye.Transparency = 0.1
	local SEGMENTS = 9
	local inner, outer = 1, radius - 0.5
	local function point(arm: number, t: number): Vector3
		local angle = arm * math.pi * 2 / 3 + t * math.pi * 1.6
		local r = inner + (outer - inner) * t
		return (root * CFrame.new(math.cos(angle) * r, height, math.sin(angle) * r)).Position
	end
	for arm = 0, 2 do
		for index = 0, SEGMENTS - 1 do
			local a, b = point(arm, index / SEGMENTS), point(arm, (index + 1) / SEGMENTS)
			local mid = (a + b) / 2
			local widthAt = 0.95 - 0.6 * (index / SEGMENTS)
			local stroke = piece(swirl, "Brazo", Vector3.new(widthAt, 0.05, (b - a).Magnitude + 0.2), CFrame.lookAt(mid, b, root.UpVector), SWIRL, M.Neon)
			stroke.Transparency = 0.15 + 0.4 * (index / SEGMENTS)
			stroke.CastShadow = false
		end
	end
	swirl.Parent = model
end

-- Poste con la calavera y los huesos cruzados, mirando al portal
local function buildSkullPost(model: Instance, at: CFrame)
	local folder = Instance.new("Model")
	folder.Name = "Calavera"
	piece(folder, "Poste", Vector3.new(1.1, 6.6, 1.1), at * CFrame.new(0, 3.3, 0), POST_WOOD, M.Wood, true)
	local head = at * CFrame.new(0, 7.8, 0)
	-- Huesos cruzados detrás de la calavera (en el plano que mira al portal)
	for _, tilt in { 40, -40 } do
		local bone = head * CFrame.new(0, -0.2, 0.7) * CFrame.Angles(0, 0, math.rad(tilt))
		local rod = piece(folder, "Hueso", Vector3.new(5.6, 0.6, 0.6), bone, BONE, M.SmoothPlastic)
		rod.Shape = Enum.PartType.Cylinder
		for _, x in { -2.8, 2.8 } do
			for _, y in { -0.3, 0.3 } do
				local knob = piece(folder, "Nudo", Vector3.one * 0.85, bone * CFrame.new(x, y, 0), BONE, M.SmoothPlastic)
				knob.Shape = Enum.PartType.Ball
			end
		end
	end
	piece(folder, "Craneo", Vector3.new(2.8, 2.5, 2.4), head, BONE, M.SmoothPlastic, true)
	piece(folder, "Mandibula", Vector3.new(2, 0.8, 2), head * CFrame.new(0, -1.55, -0.2), BONE, M.SmoothPlastic)
	local front = -1.2 -- cara de delante del cráneo (mira al portal, -Z)
	for _, x in { -0.62, 0.62 } do
		piece(folder, "Ojo", Vector3.new(0.78, 0.78, 0.2), head * CFrame.new(x, 0.15, front - 0.02), HOLE, M.SmoothPlastic)
		local spark = piece(folder, "Brillo", Vector3.new(0.3, 0.3, 0.1), head * CFrame.new(x, 0.15, front - 0.16), ENERGY, M.Neon)
		spark.CastShadow = false
	end
	piece(folder, "Nariz", Vector3.new(0.34, 0.46, 0.2), head * CFrame.new(0, -0.6, front - 0.02), HOLE, M.SmoothPlastic)
	for _, x in { -0.5, 0, 0.5 } do
		piece(folder, "Diente", Vector3.new(0.08, 0.6, 0.1), head * CFrame.new(x, -1.55, -1.21), HOLE, M.SmoothPlastic)
	end
	folder.Parent = model
end

local function buildTorch(model: Instance, at: CFrame)
	local torch = Instance.new("Model")
	torch.Name = "Antorcha"
	piece(torch, "Poste", Vector3.new(0.6, 4.4, 0.6), at * CFrame.new(0, 2.2, 0), POST_WOOD, M.Wood, true)
	piece(torch, "Cazoleta", Vector3.new(1.1, 0.45, 1.1), at * CFrame.new(0, 4.6, 0), IRON, M.Metal)
	local flame = piece(torch, "Llama", Vector3.new(0.75, 1.1, 0.75), at * CFrame.new(0, 5.35, 0) * CFrame.Angles(0, math.rad(45), 0), FLAME, M.Neon)
	flame.CastShadow = false
	local light = Instance.new("PointLight")
	light.Color = RGB(255, 190, 96)
	light.Range = 12
	light.Brightness = 1
	light.Shadows = false
	light.Parent = flame
	torch.Parent = model
end

function PadPortal.footprint(radius: number): number
	return radius + PadPortal.FrameWidth + BACK_GAP + 1.5
end

function PadPortal.build(model: Instance, root: CFrame, radius: number): (BasePart, BasePart)
	local floor = disc(model, "PadFloor", root * CFrame.new(0, 0.15, 0), radius + 0.6, 0.3, FLOOR, M.SmoothPlastic)
	floor.CanQuery = true
	local energy = disc(model, "Energy", root * CFrame.new(0, 0.36, 0), radius + 0.4, 0.12, ENERGY, M.Neon)
	energy.Transparency = 0.12
	local glow = disc(model, "EnergyGlow", root * CFrame.new(0, 0.55, 0), radius, 0.3, GLOW, M.ForceField)
	glow.Transparency = 0.05
	buildFrame(model, root, radius)
	buildSwirl(model, root, radius)

	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 16
	sparks.Lifetime = NumberRange.new(1.2, 2.2)
	sparks.Speed = NumberRange.new(2, 5)
	sparks.EmissionDirection = Enum.NormalId.Right -- el eje del disco (vertical)
	sparks.SpreadAngle = Vector2.new(10, 10)
	sparks.Size = NumberSequence.new(0.4, 0)
	sparks.Transparency = NumberSequence.new(0.1, 1)
	sparks.LightEmission = 1
	sparks.Color = ColorSequence.new(GLOW, SWIRL)
	sparks.Parent = energy
	local light = Instance.new("PointLight")
	light.Color = ENERGY
	light.Range = 22
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = energy

	-- Detrás (al otro lado de por donde se llega): la calavera y una antorcha a cada lado
	local back = radius + PadPortal.FrameWidth + BACK_GAP
	buildSkullPost(model, root * CFrame.new(0, 0, back))
	for _, side in { -1, 1 } do
		buildTorch(model, root * CFrame.Angles(0, math.rad(side * 135), 0) * CFrame.new(0, 0, -back))
	end
	return floor, energy
end

return PadPortal
