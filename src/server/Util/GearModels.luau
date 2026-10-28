-- Modelos de lo que lleva el jugador en la mano (GearService): la ballesta del Arquero según su
-- tipo (de mano, de repetición, de abanico, arbalesta o balista; o el arco: GunLogic), la espada del Guerrero,
-- el bastón de la Magia y los guantes de Puños, hechos con piezas y con el color del objeto.
-- Todos se construyen en el espacio del agarre de la mano (como una herramienta de Roblox):
-- origen = la palma, -Z = a lo largo del brazo (hacia delante con el brazo levantado) y +Y =
-- arriba con el brazo levantado. Así:
-- - el cañón del arma va hacia -Z (sale por delante al apuntar),
-- - la hoja de la espada hacia +Y (con el brazo caído apunta hacia delante, en guardia),
-- - el bastón hacia +Z (con el brazo caído queda de pie).
-- La pieza "Handle" es la que se suelda a la mano. Puntos con nombre (Attachment): "Muzzle"
-- (boca del arma), "Tip" (punta de la espada) y "Orb" (la esfera del bastón): de ahí salen
-- los efectos (CharacterPose.gearPoint). Nada choca ni pesa.

local GearModels = {}

local DARK = Color3.fromRGB(38, 40, 48)
local METAL = Color3.fromRGB(150, 156, 168)
local WOOD = Color3.fromRGB(110, 74, 44)
local GOLD = Color3.fromRGB(230, 190, 80)

local function part(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Size = size
	piece.CFrame = cframe
	piece.Color = color
	piece.Material = material or Enum.Material.SmoothPlastic
	if shape then
		piece.Shape = shape
	end
	piece.Anchored = false
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.Massless = true
	piece.CastShadow = false
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.Parent = model
	return piece
end

-- Cilindro a lo largo del eje Z (los de Roblox van a lo largo de X)
local function cylinderZ(model: Model, name: string, diameter: number, length: number, center: Vector3, color: Color3, material: Enum.Material?): BasePart
	return part(model, name, Vector3.new(length, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, math.rad(90), 0), color, material, Enum.PartType.Cylinder)
end

-- Cilindro a lo largo del eje Y
local function cylinderY(model: Model, name: string, diameter: number, length: number, center: Vector3, color: Color3, material: Enum.Material?): BasePart
	return part(model, name, Vector3.new(length, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material, Enum.PartType.Cylinder)
end

local function point(handle: BasePart, name: string, position: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = position -- el Handle está en el origen sin girar
	attachment.Parent = handle
end

-- Suelda todas las piezas al Handle (todas construidas alrededor del origen)
local function weldAll(model: Model, handle: BasePart)
	for _, piece in model:GetChildren() do
		if piece:IsA("BasePart") and piece ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = piece
			weld.Parent = piece
		end
	end
	model.PrimaryPart = handle
end

local function newModel(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "HeldGear"
	-- La empuñadura: está en la palma (origen)
	local handle = part(model, "Handle", Vector3.new(0.3, 0.75, 0.4), CFrame.new(), DARK)
	return model, handle
end

-- Arquero: ballestas (antes armas de fuego; los tipos conservan su id: Pistol, Rifle...) ---

local GUNS = {}
local STRING = Color3.fromRGB(240, 236, 220)
local WOOD_LIGHT = Color3.fromRGB(176, 128, 82)

-- Ballesta: tablero de madera a lo largo de -Z, arco (dos brazos que se abren hacia atrás)
-- delante, cuerdas hasta la nuez y un virote cargado con la punta del color del arma.
type CrossbowSpec = {
	Length: number, -- largo del tablero
	Front: number, -- Z del arco (delante: negativo)
	Span: number, -- de punta a punta del arco
	Height: number?,
	Prods: number?, -- arcos (la de abanico lleva dos, uno encima del otro)
	ProdColor: Color3?,
	ProdMaterial: Enum.Material?,
	Thick: number?, -- grosor de los brazos
	BoltScale: number?,
}

local function crossbow(model: Model, handle: BasePart, color: Color3, spec: CrossbowSpec)
	local y = spec.Height or 0.48
	local length, front = spec.Length, spec.Front
	local thick = spec.Thick or 0.13
	part(model, "Stock", Vector3.new(0.3, 0.32, length), CFrame.new(0, y - 0.05, front + length / 2), WOOD, Enum.Material.Wood)
	part(model, "Rail", Vector3.new(0.12, 0.06, length * 0.9), CFrame.new(0, y + 0.13, front + length * 0.45), METAL, Enum.Material.Metal)
	part(model, "Trigger", Vector3.new(0.08, 0.26, 0.2), CFrame.new(0, y - 0.32, 0.05), METAL, Enum.Material.Metal)
	local nut = Vector3.new(0, y + 0.12, front + length * 0.45)
	for layer = 1, spec.Prods or 1 do
		local ly = y + (layer - 1) * 0.3
		for side = -1, 1, 2 do
			local root = Vector3.new(side * 0.14, ly, front)
			local tip = Vector3.new(side * spec.Span / 2, ly, front + 0.4)
			part(model, "Prod" .. layer .. side, Vector3.new(thick, thick * 1.2, (tip - root).Magnitude), CFrame.lookAt((root + tip) / 2, tip), spec.ProdColor or color, spec.ProdMaterial)
			local stringNut = Vector3.new(nut.X, ly + 0.12, nut.Z)
			part(model, "String" .. layer .. side, Vector3.new(0.03, 0.03, (stringNut - tip).Magnitude), CFrame.lookAt((tip + stringNut) / 2, stringNut), STRING)
		end
	end
	local boltScale = spec.BoltScale or 1
	local boltLength = length * 0.62
	local boltZ = front + length * 0.45 - boltLength / 2
	cylinderZ(model, "Bolt", 0.07 * boltScale, boltLength, Vector3.new(0, y + 0.2, boltZ), WOOD_LIGHT, Enum.Material.Wood)
	part(model, "BoltTip", Vector3.new(0.15, 0.15, 0.24) * boltScale, CFrame.new(0, y + 0.2, boltZ - boltLength / 2 - 0.1) * CFrame.Angles(0, 0, math.rad(45)), color, Enum.Material.Neon)
	point(handle, "Muzzle", Vector3.new(0, y + 0.2, boltZ - boltLength / 2 - 0.3))
end

-- Ballesta de mano (antes pistola)
function GUNS.Pistol(model: Model, handle: BasePart, color: Color3)
	crossbow(model, handle, color, { Length = 1.4, Front = -1.1, Span = 1.5 })
end

-- Ballesta de repetición (antes rifle): con su cajón de virotes encima
function GUNS.Rifle(model: Model, handle: BasePart, color: Color3)
	crossbow(model, handle, color, { Length = 2.2, Front = -1.6, Span = 1.9 })
	part(model, "Magazine", Vector3.new(0.26, 0.5, 0.8), CFrame.new(0, 0.95, -0.7), WOOD, Enum.Material.Wood)
	part(model, "Lever", Vector3.new(0.08, 0.08, 1.3), CFrame.new(0.2, 0.8, -0.2) * CFrame.Angles(math.rad(-18), 0, 0), METAL, Enum.Material.Metal)
end

-- Ballesta de abanico (antes escopeta): dos arcos, uno encima del otro
function GUNS.Shotgun(model: Model, handle: BasePart, color: Color3)
	crossbow(model, handle, color, { Length = 1.6, Front = -1.3, Span = 2, Prods = 2 })
end

-- Arbalesta (antes francotirador): larga, arco de acero y mira
function GUNS.Sniper(model: Model, handle: BasePart, color: Color3)
	crossbow(model, handle, color, { Length = 2.6, Front = -2.2, Span = 2.4, ProdColor = METAL, ProdMaterial = Enum.Material.Metal })
	part(model, "Sight", Vector3.new(0.1, 0.3, 0.1), CFrame.new(0, 0.9, -0.3), color, Enum.Material.Neon)
end

-- Balista de mano (antes bazuca): grande, brazos gruesos y un virote con bomba de brea
function GUNS.Launcher(model: Model, handle: BasePart, color: Color3)
	crossbow(model, handle, color, { Length = 2.8, Front = -2, Span = 2.8, Thick = 0.22, BoltScale = 1.6 })
	part(model, "Bomb", Vector3.new(0.45, 0.45, 0.45), CFrame.new(0, 0.68, -2.35), DARK, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	part(model, "FrontGrip", Vector3.new(0.24, 0.5, 0.3), CFrame.new(0, 0.1, -1.2), WOOD, Enum.Material.Wood)
end

function GUNS.Bow(model: Model, handle: BasePart, color: Color3)
	handle.Transparency = 1
	part(model, "Grip", Vector3.new(0.22, 0.6, 0.26), CFrame.new(0, 0, 0), WOOD, Enum.Material.Wood)
	part(model, "UpperLimb", Vector3.new(0.16, 1.5, 0.2), CFrame.new(0, 0.95, -0.2) * CFrame.Angles(math.rad(-20), 0, 0), color)
	part(model, "LowerLimb", Vector3.new(0.16, 1.5, 0.2), CFrame.new(0, -0.95, -0.2) * CFrame.Angles(math.rad(20), 0, 0), color)
	part(model, "String", Vector3.new(0.04, 3.2, 0.04), CFrame.new(0, 0, 0.12), Color3.fromRGB(240, 240, 220), Enum.Material.Neon)
	point(handle, "Muzzle", Vector3.new(0, 0, -0.5))
end

-- Arma del Arquero de tipo `kind` ("Pistol", "Rifle", "Shotgun", "Sniper", "Launcher": ballestas; o "Bow")
function GearModels.gun(kind: string, color: Color3): Model
	local model, handle = newModel()
	local build = GUNS[kind] or GUNS.Pistol
	build(model, handle, color)
	weldAll(model, handle)
	model:SetAttribute("GearKind", kind)
	return model
end

-- Espada del Guerrero: más larga cuanto mejor (`scale` 1 = la de madera)
function GearModels.sword(color: Color3, scale: number?, glowing: boolean?): Model
	local model, handle = newModel()
	local s = math.clamp(scale or 1, 0.8, 1.6)
	handle.Size = Vector3.new(0.26, 0.9, 0.26)
	handle.Color = DARK
	part(model, "Pommel", Vector3.new(0.34, 0.34, 0.34), CFrame.new(0, -0.55, 0), GOLD, Enum.Material.Metal, Enum.PartType.Ball)
	part(model, "Guard", Vector3.new(0.3, 0.2, 1.3), CFrame.new(0, 0.52, 0), GOLD, Enum.Material.Metal)
	local length = 3.4 * s
	part(model, "Blade", Vector3.new(0.12, length, 0.5), CFrame.new(0, 0.62 + length / 2, 0), color, if glowing then Enum.Material.Neon else Enum.Material.Metal)
	part(model, "Edge", Vector3.new(0.14, length * 0.95, 0.1), CFrame.new(0, 0.62 + length / 2, -0.24), Color3.new(1, 1, 1):Lerp(color, 0.4), Enum.Material.Neon)
	part(model, "Tip", Vector3.new(0.12, 0.45, 0.36), CFrame.new(0, 0.62 + length + 0.15, 0) * CFrame.Angles(math.rad(45), 0, 0), color, if glowing then Enum.Material.Neon else Enum.Material.Metal)
	point(handle, "Tip", Vector3.new(0, 0.62 + length, 0))
	weldAll(model, handle)
	model:SetAttribute("GearKind", "Sword")
	return model
end

-- Bastón de la Magia: palo con una esfera brillante del color de su elemento
function GearModels.staff(color: Color3, orbColor: Color3): Model
	local model, handle = newModel()
	handle.Size = Vector3.new(0.24, 0.24, 0.24)
	handle.Transparency = 1
	cylinderZ(model, "Shaft", 0.22, 4.6, Vector3.new(0, 0, 1.2), color:Lerp(WOOD, 0.55), Enum.Material.Wood)
	cylinderZ(model, "Band", 0.3, 0.25, Vector3.new(0, 0, 3.3), GOLD, Enum.Material.Metal)
	local orb = part(model, "OrbPart", Vector3.new(0.85, 0.85, 0.85), CFrame.new(0, 0, 3.95), orbColor, Enum.Material.Neon, Enum.PartType.Ball)
	orb.Transparency = 0.1
	local light = Instance.new("PointLight")
	light.Color = orbColor
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = orb
	part(model, "ClawA", Vector3.new(0.1, 0.1, 0.7), CFrame.new(0.3, 0, 3.75) * CFrame.Angles(0, math.rad(-25), 0), GOLD, Enum.Material.Metal)
	part(model, "ClawB", Vector3.new(0.1, 0.1, 0.7), CFrame.new(-0.3, 0, 3.75) * CFrame.Angles(0, math.rad(25), 0), GOLD, Enum.Material.Metal)
	point(handle, "Orb", Vector3.new(0, 0, 3.95))
	weldAll(model, handle)
	model:SetAttribute("GearKind", "Staff")
	return model
end

-- Guantes de Puños: uno en cada mano, del tamaño de la mano del avatar (un puño acolchado
-- redondo y el puño de la muñeca), del color de los guantes equipados; los mejores llevan una
-- franja brillante. A diferencia del resto, se construyen ya soldados al personaje: devuelve
-- el modelo (en el personaje) o nil si no tiene manos.
function GearModels.gloves(character: Model, color: Color3, glowing: boolean?): Model?
	local model = Instance.new("Model")
	model.Name = "HeldGear"
	local cuffColor = Color3.new(1, 1, 1):Lerp(color, 0.25)
	local made = 0
	for _, side in { "Right", "Left" } do
		local hand = character:FindFirstChild(side .. "Hand")
		if hand and hand:IsA("BasePart") then
			local size = hand.Size
			local width = math.max(size.X, size.Z)
			-- Las piezas se colocan en el espacio de la mano: +Y = hacia la muñeca
			local pieces = {
				{ "Fist", Vector3.one * width * 1.85, CFrame.new(0, -size.Y * 0.14, -size.Z * 0.08), color, Enum.PartType.Ball },
				{ "Knuckles", Vector3.one * width * 1.55, CFrame.new(0, size.Y * 0.14, -size.Z * 0.05), color, Enum.PartType.Ball },
				{ "Cuff", Vector3.new(size.Y * 0.34, width * 1.4, width * 1.4), CFrame.new(0, size.Y * 0.52, 0) * CFrame.Angles(0, 0, math.rad(90)), cuffColor, Enum.PartType.Cylinder },
			}
			if glowing then
				table.insert(pieces, { "Stripe", Vector3.new(size.Y * 0.1, width * 1.48, width * 1.48), CFrame.new(0, size.Y * 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder })
			end
			for _, spec in pieces do
				local piece = part(model, side .. spec[1], spec[2], hand.CFrame * spec[3], spec[4], if spec[1] == "Stripe" then Enum.Material.Neon else Enum.Material.SmoothPlastic, spec[5])
				local weld = Instance.new("Weld")
				weld.Name = "GearWeld"
				weld.Part0 = hand
				weld.Part1 = piece
				weld.C0 = spec[3]
				weld.Parent = piece
			end
			made += 1
		end
	end
	if made == 0 then
		model:Destroy()
		return nil
	end
	local primary = model:FindFirstChild("RightFist") or model:FindFirstChildWhichIsA("BasePart")
	if primary and primary:IsA("BasePart") then
		model.PrimaryPart = primary
	end
	model:SetAttribute("GearKind", "Gloves")
	model.Parent = character
	return model
end

-- Suelda el modelo a la mano derecha del personaje (por su RightGripAttachment, como una
-- herramienta). Devuelve false si el personaje no tiene mano.
function GearModels.attach(character: Model, model: Model): boolean
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local handle = model.PrimaryPart
	if not (hand and hand:IsA("BasePart") and handle) then
		return false
	end
	local grip = hand:FindFirstChild("RightGripAttachment")
	local gripFrame = if grip and grip:IsA("Attachment") then grip.CFrame else CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	model:PivotTo(hand.CFrame * gripFrame)
	local weld = Instance.new("Weld")
	weld.Name = "GearWeld"
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = gripFrame
	weld.C1 = CFrame.new()
	weld.Parent = handle
	model.Parent = character
	return true
end

-- Equipo visible (OutfitLogic) ----------------------------------------------------------------
-- La pieza de la clase y la armadura, soldadas al cuerpo (R15 y R6). Se construye en el espacio
-- de cada parte del cuerpo: -Z = delante, +Z = la espalda, +Y = arriba. Nada choca ni se puede
-- apuntar (CanQuery = false).

local LEATHER = Color3.fromRGB(122, 82, 52)
local ARMOR_LOOK = {
	Cuero = { Color = LEATHER, Material = Enum.Material.Fabric },
	Hierro = { Color = METAL, Material = Enum.Material.Metal },
	Acero = { Color = Color3.fromRGB(196, 204, 216), Material = Enum.Material.Metal },
	Oro = { Color = GOLD, Material = Enum.Material.Metal },
}

local function wear(model: Model, body: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local piece = part(model, name, size, body.CFrame * offset, color, material, shape)
	local weld = Instance.new("Weld")
	weld.Name = "GearWeld"
	weld.Part0 = body
	weld.Part1 = piece
	weld.C0 = offset
	weld.Parent = piece
	return piece
end

local function bodyPart(character: Model, ...: string): BasePart?
	for _, name in { ... } do
		local found = character:FindFirstChild(name)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	return nil
end

-- Arquero: carcaj inclinado a la espalda con tres flechas y la correa cruzando el pecho
local function quiver(model: Model, torso: BasePart, color: Color3)
	local t = torso.Size
	local length = t.Y * 1.1
	local center = Vector3.new(t.X * 0.16, t.Y * 0.04, t.Z / 2 + 0.32)
	local rotation = CFrame.Angles(0, 0, math.rad(90 - 18))
	local axis = rotation:VectorToWorldSpace(Vector3.new(1, 0, 0))
	wear(model, torso, "Quiver", Vector3.new(length, 0.62, 0.62), CFrame.new(center) * rotation, LEATHER, Enum.Material.Fabric, Enum.PartType.Cylinder)
	local top = center + axis * (length / 2)
	wear(model, torso, "QuiverRim", Vector3.new(0.14, 0.7, 0.7), CFrame.new(top - axis * 0.05) * rotation, color, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	for index, shift in { Vector3.new(-0.12, 0, 0.05), Vector3.new(0.1, 0, -0.08), Vector3.new(0.02, 0, 0.13) } do
		local shaftCenter = top + shift + axis * (0.3 + index * 0.05)
		wear(model, torso, "Arrow" .. index, Vector3.new(0.7, 0.07, 0.07), CFrame.new(shaftCenter) * rotation, WOOD, Enum.Material.Wood, Enum.PartType.Cylinder)
		wear(model, torso, "Fletching" .. index, Vector3.new(0.04, 0.3, 0.18), CFrame.new(shaftCenter + axis * 0.28) * rotation * CFrame.Angles(0, 0, math.rad(-90)), color, Enum.Material.Neon)
	end
	wear(model, torso, "Strap", Vector3.new(0.2, t.Y * 1.12, 0.06), CFrame.new(0, 0, -t.Z / 2 - 0.03) * CFrame.Angles(0, 0, math.rad(38)), LEATHER:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Fabric)
end

-- Guerrero: escudo redondo a la espalda (borde de metal, cara del color de la clase y umbo)
local function shield(model: Model, torso: BasePart, color: Color3)
	local t = torso.Size
	local diameter = math.min(t.X, t.Y) * 0.95
	local z = t.Z / 2 + 0.16
	local facing = CFrame.Angles(0, math.rad(90), 0) -- el eje del cilindro hacia la espalda
	wear(model, torso, "ShieldRim", Vector3.new(0.16, diameter, diameter), CFrame.new(0, t.Y * 0.02, z) * facing, METAL, Enum.Material.Metal, Enum.PartType.Cylinder)
	wear(model, torso, "ShieldFace", Vector3.new(0.2, diameter * 0.86, diameter * 0.86), CFrame.new(0, t.Y * 0.02, z) * facing, color, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	wear(model, torso, "ShieldBand", Vector3.new(diameter * 0.86, 0.16, 0.24), CFrame.new(0, t.Y * 0.02, z), METAL, Enum.Material.Metal)
	wear(model, torso, "ShieldBoss", Vector3.new(0.42, 0.42, 0.42), CFrame.new(0, t.Y * 0.02, z + 0.13), GOLD, Enum.Material.Metal, Enum.PartType.Ball)
end

-- Puños: cinta en la frente con dos colas atrás y fajín en la cintura
local function headband(model: Model, character: Model, torso: BasePart, color: Color3)
	local head = bodyPart(character, "Head")
	if head then
		local h = head.Size
		local width = math.min(h.X, h.Z * 1.25) -- la cabeza de R6 es 2x1x1 con una malla que la achica
		local y = h.Y * 0.2
		wear(model, head, "Headband", Vector3.new(0.22, width * 1.07, width * 1.07), CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Fabric, Enum.PartType.Cylinder)
		for index, side in { -1, 1 } do
			wear(model, head, "Tail" .. index, Vector3.new(0.08, 0.6, 0.18), CFrame.new(side * 0.14, y - 0.24, width * 0.55) * CFrame.Angles(math.rad(-25), 0, math.rad(side * 12)), color, Enum.Material.Fabric)
		end
	end
	local lower = bodyPart(character, "LowerTorso")
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.3)
	if lower then
		local l = lower.Size
		wear(model, lower, "Sash", Vector3.new(l.X * 1.05, math.min(l.Y * 0.75, 0.42), l.Z * 1.1), CFrame.new(0, l.Y * 0.1, 0), dark, Enum.Material.Fabric)
		wear(model, lower, "Knot", Vector3.new(0.18, 0.5, 0.08), CFrame.new(-l.X * 0.28, -l.Y * 0.35, -l.Z * 0.58) * CFrame.Angles(0, 0, math.rad(10)), dark, Enum.Material.Fabric)
	else
		local t = torso.Size
		wear(model, torso, "Sash", Vector3.new(t.X * 1.04, 0.36, t.Z * 1.08), CFrame.new(0, -t.Y * 0.38, 0), dark, Enum.Material.Fabric)
	end
end

-- Magia: capa desde los hombros (algo separada de la espalda para no meterse en las piernas)
local function cape(model: Model, torso: BasePart, color: Color3)
	local t = torso.Size
	local length = t.Y * 1.6
	local cloth = color:Lerp(Color3.new(0, 0, 0), 0.35)
	wear(model, torso, "Cape", Vector3.new(t.X * 0.92, length, 0.08), CFrame.new(0, t.Y * 0.47, t.Z / 2 + 0.07) * CFrame.Angles(math.rad(-12), 0, 0) * CFrame.new(0, -length / 2, 0), cloth, Enum.Material.Fabric)
	wear(model, torso, "Mantle", Vector3.new(t.X * 0.98, 0.18, t.Z * 1.15), CFrame.new(0, t.Y / 2 - 0.05, 0.03), color, Enum.Material.Fabric)
	for index, side in { -1, 1 } do
		wear(model, torso, "Clasp" .. index, Vector3.new(0.26, 0.26, 0.26), CFrame.new(side * t.X * 0.3, t.Y * 0.42, -t.Z / 2 - 0.04), GOLD, Enum.Material.Metal, Enum.PartType.Ball)
	end
end

local PIECES = { Quiver = quiver, Shield = shield, Cape = cape }

-- Hombreras (y, desde el grado 3, peto) del material de su grado
local function armor(model: Model, character: Model, torso: BasePart, spec: { Shoulders: string?, Chest: boolean, Trim: boolean }, color: Color3)
	local look = spec.Shoulders and ARMOR_LOOK[spec.Shoulders]
	if not look then
		return
	end
	local layered = spec.Shoulders ~= "Cuero"
	for _, side in { "Right", "Left" } do
		local arm = bodyPart(character, side .. "UpperArm", side .. " Arm")
		if arm then
			local a = arm.Size
			local tilt = CFrame.Angles(0, 0, math.rad(if side == "Right" then -12 else 12))
			wear(model, arm, side .. "Pauldron", Vector3.new(a.X * 1.32, 0.3, a.Z * 1.32), CFrame.new(0, a.Y / 2 - 0.04, 0) * tilt, look.Color, look.Material)
			if layered then
				wear(model, arm, side .. "Plate", Vector3.new(a.X * 1.2, 0.24, a.Z * 1.2), CFrame.new(0, a.Y / 2 - 0.3, 0) * tilt, look.Color:Lerp(Color3.new(0, 0, 0), 0.12), look.Material)
			end
			if spec.Trim then
				wear(model, arm, side .. "Trim", Vector3.new(a.X * 1.34, 0.06, a.Z * 1.34), CFrame.new(0, a.Y / 2 - 0.2, 0) * tilt, color, Enum.Material.Neon)
			end
		end
	end
	if spec.Chest then
		local t = torso.Size
		wear(model, torso, "Breastplate", Vector3.new(t.X * 0.78, t.Y * 0.62, 0.14), CFrame.new(0, t.Y * 0.1, -t.Z / 2 - 0.06), look.Color, look.Material)
		if spec.Trim then
			wear(model, torso, "ChestTrim", Vector3.new(t.X * 0.5, 0.08, 0.16), CFrame.new(0, t.Y * 0.26, -t.Z / 2 - 0.07), color, Enum.Material.Neon)
		end
	end
end

-- Viste al personaje: `piece` (OutfitLogic.Pieces) y la armadura `spec` (OutfitLogic.armor),
-- del color de la clase. Devuelve el modelo ("ClassOutfit", ya en el personaje) o nil si no
-- hay nada que poner o no tiene torso.
function GearModels.outfit(character: Model, piece: string?, spec: { Shoulders: string?, Chest: boolean, Trim: boolean }, color: Color3): Model?
	local torso = bodyPart(character, "UpperTorso", "Torso")
	if not torso or (piece == nil and spec.Shoulders == nil) then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "ClassOutfit"
	if piece == "Headband" then
		headband(model, character, torso, color)
	elseif piece and PIECES[piece] then
		PIECES[piece](model, torso, color)
	end
	armor(model, character, torso, spec, color)
	if #model:GetChildren() == 0 then
		model:Destroy()
		return nil
	end
	model:SetAttribute("Piece", piece or "")
	model:SetAttribute("Armor", spec.Shoulders or "")
	model.Parent = character
	return model
end

return GearModels
