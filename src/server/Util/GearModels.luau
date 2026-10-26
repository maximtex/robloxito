-- Modelos de lo que lleva el jugador en la mano (GearService): el arma de fuego según su tipo
-- (pistola, rifle, escopeta, francotirador, bazuca o arco: GunLogic), la espada del Guerrero,
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

-- Armas de fuego ---------------------------------------------------------------------------

local GUNS = {}

function GUNS.Pistol(model: Model, handle: BasePart, color: Color3)
	part(model, "Slide", Vector3.new(0.34, 0.36, 1.35), CFrame.new(0, 0.48, -0.38), DARK)
	part(model, "Stripe", Vector3.new(0.36, 0.08, 1.2), CFrame.new(0, 0.6, -0.38), color, Enum.Material.Neon)
	cylinderZ(model, "Barrel", 0.2, 0.3, Vector3.new(0, 0.46, -1.15), METAL, Enum.Material.Metal)
	part(model, "Trigger", Vector3.new(0.08, 0.22, 0.22), CFrame.new(0, 0.18, -0.25), METAL)
	point(handle, "Muzzle", Vector3.new(0, 0.46, -1.35))
end

function GUNS.Rifle(model: Model, handle: BasePart, color: Color3)
	part(model, "Body", Vector3.new(0.36, 0.46, 2.3), CFrame.new(0, 0.48, -0.55), DARK)
	part(model, "Stripe", Vector3.new(0.38, 0.1, 1.9), CFrame.new(0, 0.66, -0.55), color, Enum.Material.Neon)
	part(model, "Stock", Vector3.new(0.3, 0.5, 0.9), CFrame.new(0, 0.38, 1.0), color)
	part(model, "Magazine", Vector3.new(0.26, 0.65, 0.34), CFrame.new(0, 0.0, -0.95) * CFrame.Angles(math.rad(-12), 0, 0), METAL)
	cylinderZ(model, "Barrel", 0.18, 1.1, Vector3.new(0, 0.52, -2.2), METAL, Enum.Material.Metal)
	part(model, "Sight", Vector3.new(0.12, 0.2, 0.3), CFrame.new(0, 0.8, -0.2), DARK)
	point(handle, "Muzzle", Vector3.new(0, 0.52, -2.8))
end

function GUNS.Shotgun(model: Model, handle: BasePart, color: Color3)
	part(model, "Body", Vector3.new(0.42, 0.44, 1.4), CFrame.new(0, 0.46, -0.35), DARK)
	cylinderZ(model, "BarrelL", 0.22, 1.7, Vector3.new(-0.11, 0.58, -1.75), METAL, Enum.Material.Metal)
	cylinderZ(model, "BarrelR", 0.22, 1.7, Vector3.new(0.11, 0.58, -1.75), METAL, Enum.Material.Metal)
	part(model, "Pump", Vector3.new(0.34, 0.3, 0.7), CFrame.new(0, 0.32, -1.45), color, Enum.Material.Neon)
	part(model, "Stock", Vector3.new(0.32, 0.48, 0.85), CFrame.new(0, 0.34, 0.75), WOOD, Enum.Material.Wood)
	point(handle, "Muzzle", Vector3.new(0, 0.58, -2.62))
end

function GUNS.Sniper(model: Model, handle: BasePart, color: Color3)
	part(model, "Body", Vector3.new(0.32, 0.42, 2.2), CFrame.new(0, 0.48, -0.45), DARK)
	cylinderZ(model, "Barrel", 0.16, 2.4, Vector3.new(0, 0.52, -2.75), METAL, Enum.Material.Metal)
	cylinderZ(model, "Scope", 0.3, 1.1, Vector3.new(0, 0.92, -0.45), DARK)
	cylinderZ(model, "Lens", 0.24, 0.06, Vector3.new(0, 0.92, -1.02), color, Enum.Material.Neon)
	part(model, "Stock", Vector3.new(0.28, 0.52, 1.0), CFrame.new(0, 0.36, 1.05), color)
	part(model, "Stripe", Vector3.new(0.34, 0.08, 1.8), CFrame.new(0, 0.32, -0.45), color, Enum.Material.Neon)
	point(handle, "Muzzle", Vector3.new(0, 0.52, -3.95))
end

function GUNS.Launcher(model: Model, handle: BasePart, color: Color3)
	cylinderZ(model, "Tube", 0.75, 3.4, Vector3.new(0, 0.62, -0.55), DARK)
	cylinderZ(model, "Ring", 0.82, 0.25, Vector3.new(0, 0.62, -2.2), color, Enum.Material.Neon)
	cylinderZ(model, "Back", 0.82, 0.25, Vector3.new(0, 0.62, 1.1), color)
	part(model, "Sight", Vector3.new(0.15, 0.35, 0.4), CFrame.new(-0.3, 1.05, -0.6), METAL)
	part(model, "FrontGrip", Vector3.new(0.24, 0.5, 0.3), CFrame.new(0, 0.1, -1.2), DARK)
	point(handle, "Muzzle", Vector3.new(0, 0.62, -2.35))
end

function GUNS.Bow(model: Model, handle: BasePart, color: Color3)
	handle.Transparency = 1
	part(model, "Grip", Vector3.new(0.22, 0.6, 0.26), CFrame.new(0, 0, 0), WOOD, Enum.Material.Wood)
	part(model, "UpperLimb", Vector3.new(0.16, 1.5, 0.2), CFrame.new(0, 0.95, -0.2) * CFrame.Angles(math.rad(-20), 0, 0), color)
	part(model, "LowerLimb", Vector3.new(0.16, 1.5, 0.2), CFrame.new(0, -0.95, -0.2) * CFrame.Angles(math.rad(20), 0, 0), color)
	part(model, "String", Vector3.new(0.04, 3.2, 0.04), CFrame.new(0, 0, 0.12), Color3.fromRGB(240, 240, 220), Enum.Material.Neon)
	point(handle, "Muzzle", Vector3.new(0, 0, -0.5))
end

-- Arma de fuego de tipo `kind` ("Pistol", "Rifle", "Shotgun", "Sniper", "Launcher" o "Bow")
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

return GearModels
