-- Construye los puestos del pueblo estilo simulador:
-- - 🛒 TIENDA, 🎁 PREMIOS, 📜 MISIONES
-- - ⚡ TIENDA LÁSER (para mejorar el láser que dispara tu personaje)
-- - 🌟 MÁQUINA DE EVOLUCIÓN (para fusionar 3 mascotas iguales en su versión ★ Evo)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VillageConfig = require(Shared.Config.VillageConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local EvolucionadorData = require(script.Parent.Parent.Util.EvolucionadorData)
local StallsData = require(script.Parent.Parent.Util.StallsData)

local EVO_MATERIALS = {
	PurpleDark = { Color = Color3.fromRGB(45, 15, 116), Material = Enum.Material.SmoothPlastic },
	Purple = { Color = Color3.fromRGB(96, 38, 202), Material = Enum.Material.SmoothPlastic },
	PurpleLight = { Color = Color3.fromRGB(144, 82, 233), Material = Enum.Material.SmoothPlastic },
	Slot = { Color = Color3.fromRGB(18, 14, 28), Material = Enum.Material.SmoothPlastic },
	LightTeal = { Color = Color3.fromRGB(7, 190, 141), Material = Enum.Material.Neon },
	LightMint = { Color = Color3.fromRGB(84, 233, 171), Material = Enum.Material.Neon },
	LightLime = { Color = Color3.fromRGB(122, 255, 12), Material = Enum.Material.Neon },
	LightYellow = { Color = Color3.fromRGB(255, 222, 17), Material = Enum.Material.Neon },
	ScreenWhite = { Color = Color3.fromRGB(231, 255, 240), Material = Enum.Material.Neon },
}

local VillageService = {}

local GROUND = GeneratorConfig.Position.Y
local ORIGIN = Vector3.new(0, 0, 0)

local WOOD = Color3.fromRGB(168, 108, 56)
local DARK_WOOD = Color3.fromRGB(122, 74, 36)
local WHITE = Color3.fromRGB(250, 250, 250)
local RED_STRIPE = Color3.fromRGB(232, 64, 58)
local YELLOW_STRIPE = Color3.fromRGB(246, 204, 48)
local BLUE_STRIPE = Color3.fromRGB(58, 172, 240)
local CYAN_STRIPE = Color3.fromRGB(48, 224, 210)
local PURPLE_NEON = Color3.fromRGB(190, 95, 255)
local GOLD_NEON = Color3.fromRGB(255, 215, 65)
local RING_YELLOW = Color3.fromRGB(255, 232, 64)
-- Círculo de los puestos: más ancho que el puesto (unos 12 con el toldo) y con el puesto
-- encima, centrado un poco por delante para que sobre sitio delante del mostrador.
local STALL_PAD_DIAMETER = 15
local STALL_PAD_FORWARD = 1.5
local CHEST_PAD_DIAMETER = 11 -- círculo del cofre «RECLAMAR»

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- Altura del suelo en pos: sobre un camino de la plaza, StudFloor.PathRaise más arriba
local function groundAt(pos: Vector2): number
	return GROUND + StudFloor.raiseAt(ORIGIN.X + pos.X, ORIGIN.Z + pos.Y)
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, mat: Enum.Material, solid: boolean?): Part
	return PartFactory.part(parent, name, { Size = size, CFrame = cframe, Color = color, Material = mat, Solid = solid == true })
end

-- Círculo de interacción (se pisa para abrir el panel, WorldPromptController): disco
-- translúcido que brilla en el color del sitio, con el borde más fuerte y un halo suave
-- alrededor. `center`: centro del disco, justo encima del suelo.
local PAD_RIM_SEGMENT = 1.2 -- largo de cada tramo del borde (studs)
local function glowPad(parent: Instance, center: Vector3, diameter: number, color: Color3)
	local halo = PartFactory.verticalCylinder(parent, "PadHalo", center - Vector3.new(0, 0.04, 0), 0.06, diameter + 1.6, color, Enum.Material.Neon, false)
	halo.Transparency = 0.85
	local fill = PartFactory.verticalCylinder(parent, "PadFill", center, 0.1, diameter, color:Lerp(Color3.new(1, 1, 1), 0.35), Enum.Material.Neon, false)
	fill.Transparency = 0.55
	local outer = diameter / 2
	local width = math.max(0.4, diameter * 0.04)
	local segments = math.max(28, math.ceil(math.pi * diameter / PAD_RIM_SEGMENT))
	local length = 2 * outer * math.tan(math.pi / segments)
	for index = 1, segments do
		local angle = (index - 1) / segments * 2 * math.pi
		local rim = PartFactory.part(parent, "PadRim", {
			Size = Vector3.new(length, 0.14, width),
			CFrame = CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.02, -(outer - width / 2)),
			Color = color,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		rim.Transparency = 0.15
	end
end

-- Zona invisible que abre `panel` al pisarla (WorldPromptController), del radio del círculo
local function touchPadAt(parent: Instance, center: Vector3, radius: number, panel: string)
	local touchPad = Instance.new("Part")
	touchPad.Name = "TouchPad"
	touchPad.Size = Vector3.new(radius * 2, 1.2, radius * 2)
	touchPad.CFrame = CFrame.new(center + Vector3.new(0, 0.6, 0))
	touchPad.Transparency = 1
	touchPad.CanCollide = false
	touchPad.CanTouch = true
	touchPad.CanQuery = false
	touchPad.Anchored = true
	touchPad:SetAttribute("OpenPanel", panel)
	touchPad:SetAttribute("PadRadius", radius)
	touchPad.Parent = parent
end

local function panelPrompt(parent: BasePart, panel: string, actionText: string, objectText: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PanelPrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpenPanel", panel)
	prompt.Parent = parent
end

-- Nombre que flota sobre un sitio del pueblo, como en los simuladores: letras grandes del
-- color del sitio con un borde oscuro grueso, siempre de cara a la cámara. `position` es el
-- centro de las letras; el borde crece con ellas (ScaledSize) para verse igual de lejos.
local NAME_HEIGHT = 2.8 -- alto del renglón (studs)
local NAME_WIDTH = 20 -- ancho máximo: los nombres caben a lo alto sin encogerse
local NAME_OUTLINE = Color3.fromRGB(16, 16, 22)
local NAME_OUTLINE_SCALE = 0.1 -- grosor del borde respecto al renglón
local function floatingName(parent: Instance, position: Vector3, text: string, color: Color3)
	local anchor = part(parent, "NameAnchor", Vector3.one * 0.2, CFrame.new(position), color, Enum.Material.SmoothPlastic, false)
	anchor.Transparency = 1

	local gui = Instance.new("BillboardGui")
	gui.Name = "FloatingName"
	gui.Size = UDim2.new(NAME_WIDTH, 0, NAME_HEIGHT, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 150

	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = NAME_OUTLINE
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	stroke.Thickness = NAME_OUTLINE_SCALE
	stroke.Parent = label

	gui.Parent = anchor
end

local function signText(board: BasePart, text: string)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Text" .. face.Name
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 45
		gui.LightInfluence = 0
		gui.MaxDistance = 130
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeColor3 = Color3.fromRGB(24, 24, 28)
		label.TextStrokeTransparency = 0
		label.Text = text
		label.Parent = gui
		gui.Parent = board
	end
end

-- Piezas de puestos_pueblo.glb que no se construyen: el cartel de madera sobre el tejado y
-- lo que lleva encima. El nombre del puesto flota en su lugar (floatingName).
local SIGN_PARTS = {
	SignPost = true,
	SignBoard = true,
	SignFrameTop = true,
	SignFrameBottom = true,
	SignFrameSide = true,
	Topper = true,
	TopperBase = true,
	TopperRing = true,
	TopperGift = true,
	TopperRibbon = true,
	TopperBow = true,
	QuestMark = true,
	QuestDot = true,
}
local STALL_NAME_Y = 11.8 -- centro del nombre, por encima de la cumbrera (9.66)

-- Puesto de aldea construido 1:1 a partir de puestos_pueblo.glb, con su nombre flotando encima
local function buildStall(parent: Instance, id: string, pos: Vector2, lookToward: Vector2, titleText: string, panelName: string, emblemEmoji: string?): Model
	local model = Instance.new("Model")
	model.Name = "Stall_" .. id

	local y = groundAt(pos)
	local base = at(pos.X, y, pos.Y)
	local target = at(lookToward.X, y, lookToward.Y)
	-- En puestos_pueblo.glb, el frontal del puesto (mostrador, paso, anillo de interacción) está en +Z local
	local frame = CFrame.lookAt(base, target) * CFrame.Angles(0, math.pi, 0)

	local stallParts = StallsData[id]
	local primaryPart: BasePart? = nil
	local emblemPart: BasePart? = nil
	local padColor = RING_YELLOW

	if stallParts then
		for _, pData in stallParts do
			local name = pData[1]
			local shape = pData[2]
			local mat = pData[3]
			local color = pData[4]
			local trans = pData[5]
			local rawSize = pData[6]
			local localCF = pData[7]
			local solid = pData[8]

			-- El círculo de interacción del diseño se dibuja aparte (glowPad), del color del puesto
			if name == "InteractRing" or name == "InteractInner" then
				if name == "InteractInner" then
					padColor = color
				end
				continue
			end
			if SIGN_PARTS[name] then
				continue
			end

			local p = Instance.new("Part")
			p.Name = name
			p.Material = mat
			p.Color = color
			p.Transparency = trans
			p.CanCollide = solid
			p.CanQuery = solid
			p.CanTouch = false
			p.Anchored = true
			p.CastShadow = solid

			if shape == "Ball" then
				p.Shape = Enum.PartType.Ball
				p.Size = rawSize
				p.CFrame = frame * localCF
			elseif shape == "VerticalCylinder" then
				p.Shape = Enum.PartType.Cylinder
				p.Size = Vector3.new(rawSize.Y, rawSize.X, rawSize.X)
				p.CFrame = frame * localCF * CFrame.Angles(0, 0, math.pi / 2)
			elseif shape == "ZCylinder" then
				p.Shape = Enum.PartType.Cylinder
				p.Size = Vector3.new(rawSize.Z, rawSize.X, rawSize.X)
				p.CFrame = frame * localCF * CFrame.Angles(0, math.pi / 2, 0)
			else
				p.Shape = Enum.PartType.Block
				p.Size = rawSize
				p.CFrame = frame * localCF
			end

			p.Parent = model

			if name == "Counter" and not primaryPart then
				primaryPart = p
			elseif name == "Emblem" then
				emblemPart = p
			end
		end
	end

	floatingName(model, (frame * CFrame.new(0, STALL_NAME_Y, 0)).Position, titleText, padColor)

	if emblemPart and emblemEmoji then
		signText(emblemPart, emblemEmoji)
	end

	-- Círculo con el puesto encima: al pararse en él se abre el panel (sin pulsar E)
	local padCenter = (frame * CFrame.new(0, 0.34, STALL_PAD_FORWARD)).Position
	glowPad(model, padCenter, STALL_PAD_DIAMETER, padColor)
	touchPadAt(model, padCenter, STALL_PAD_DIAMETER / 2 + 0.6, panelName)

	model.PrimaryPart = primaryPart or model:FindFirstChildWhichIsA("BasePart")
	model.Parent = parent
	return model
end

-- Máquina de Evolución de Mascotas (construcción 1:1 de evolucionador.obj + evolucionador.mtl),
-- `scale` veces su tamaño. Se usa con E delante de la pantalla (sin círculo en el suelo).
local function buildEvolutionMachine(parent: Instance, pos: Vector2, lookToward: Vector2, scale: number)
	local model = Instance.new("Model")
	model.Name = "EvolutionMachine"

	local y = groundAt(pos)
	local base = at(pos.X, y, pos.Y)
	local target = at(lookToward.X, y, lookToward.Y)
	-- En evolucionador.obj, el frontal (pantalla, luces, ranuras) está en +Z local
	local frame = CFrame.lookAt(base, target) * CFrame.Angles(0, math.pi, 0)

	-- 1. Si existe un modelo importado manualmente en ReplicatedStorage, lo usamos
	local customModel = ReplicatedStorage:FindFirstChild("Evolucionador")
		or (ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Evolucionador"))
	
	local primaryPart: BasePart? = nil

	if customModel and customModel:IsA("Model") then
		local clone = customModel:Clone()
		clone.Name = "CustomMachine"
		for _, desc in clone:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Anchored = true
			end
		end
		clone:ScaleTo(scale)
		clone:PivotTo(frame * CFrame.new(0, 3.6 * scale + 0.28, 0))
		clone.Parent = model
		primaryPart = clone.PrimaryPart
	else
		-- 2. Construcción procedural exacta 1:1 de evolucionador.obj + evolucionador.mtl
		for _, item in EvolucionadorData do
			local name = item[1]
			local mtlName = item[2]
			local size = item[3]
			local localOffset = item[4]

			local mtlDef = EVO_MATERIALS[mtlName] or EVO_MATERIALS.Purple
			local partCF = frame * CFrame.new(localOffset * scale + Vector3.new(0, 0.28, 0))

			local p = PartFactory.part(model, name, {
				Size = size * scale,
				CFrame = partCF,
				Color = mtlDef.Color,
				Material = mtlDef.Material,
				Solid = (name == "Body_2" or name == "Plinth_1" or name == "TopCap_3"),
			})
			if name == "Plinth_1" then
				primaryPart = p
			end
		end
	end

	-- ProximityPrompt (E) delante de la pantalla para abrir la ventana de Evolución. La pieza no
	-- lleva OpenPanel: si no, WorldPromptController la trataría como un círculo que se pisa.
	local promptSpot = part(model, "PromptSpot", Vector3.new(2, 2, 2), frame * CFrame.new(0, 2.5, 2.3 * scale + 1), RING_YELLOW, Enum.Material.SmoothPlastic, false)
	promptSpot.Transparency = 1
	panelPrompt(promptSpot, "Evolution", "Evolucionar Mascotas", "🌟 Máquina de Evolución")

	-- Nombre flotando sobre la máquina (mide unos 8.7 de alto sin escalar)
	floatingName(model, (frame * CFrame.new(0, 8.7 * scale + 2.2, 0)).Position, "Evolucionar", PURPLE_NEON)

	-- Luz ambiental mística
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(144, 82, 233)
	light.Range = 18
	light.Brightness = 1.8
	light.Parent = promptSpot

	model.PrimaryPart = primaryPart or model:FindFirstChildWhichIsA("BasePart")
	model.Parent = parent
	return model
end

-- Cofre colosal mítico "RECLAMAR" en el prado junto a la plaza (VillageConfig.ClaimChest)
local function buildFreeClaimChest(parent: Instance, pos: Vector2, lookToward: Vector2)
	local model = Instance.new("Model")
	model.Name = "FreeRewardChest"

	local y = groundAt(pos)
	local base = at(pos.X, y, pos.Y)
	local target = at(lookToward.X, y, lookToward.Y)
	local frame = CFrame.lookAt(base, target)

	-- Paleta mítica de simulador estilo Pet Sim
	local C_RED = Color3.fromRGB(195, 26, 36)
	local C_DARKRED = Color3.fromRGB(145, 18, 26)
	local C_GOLD = Color3.fromRGB(255, 208, 32)
	local C_GOLDBRIGHT = Color3.fromRGB(255, 235, 90)
	local C_CYAN_GEM = Color3.fromRGB(45, 220, 255)

	-- 1. Círculo dorado en el suelo: al pararse encima se abren los Premios (sin pulsar E)
	glowPad(model, base + Vector3.new(0, 0.36, 0), CHEST_PAD_DIAMETER, Color3.fromRGB(255, 205, 40))
	touchPadAt(model, base + Vector3.new(0, 0.36, 0), CHEST_PAD_DIAMETER / 2 + 0.6, "Rewards")

	-- 2. Dimensiones colosales (ancho 7.0 studs, alto 3.6 base, fondo 4.2)
	local chestCF = frame * CFrame.new(0, 2.1 + 0.28, 0)

	-- Zócalo dorado inferior
	part(model, "GoldPedestalRim", Vector3.new(7.6, 0.45, 4.8), chestCF * CFrame.new(0, -1.9, 0), C_GOLD, Enum.Material.SmoothPlastic, true)

	-- Cuerpo principal (rojo carmesí profundo)
	local body = part(model, "ChestBody", Vector3.new(7.0, 3.6, 4.2), chestCF, C_RED, Enum.Material.SmoothPlastic, true)

	-- Esquineras doradas macizas (4 esquinas verticales)
	for _, sx in { -3.35, 3.35 } do
		for _, sz in { -1.95, 1.95 } do
			part(model, "CornerGold", Vector3.new(0.65, 3.64, 0.65), chestCF * CFrame.new(sx, 0, sz), C_GOLD, Enum.Material.SmoothPlastic, true)
		end
	end

	-- Flejes / bandas doradas verticales en el cuerpo
	for _, sx in { -2.1, 0, 2.1 } do
		part(model, "BodyBand", Vector3.new(0.55, 3.66, 4.3), chestCF * CFrame.new(sx, 0, 0), C_GOLD, Enum.Material.SmoothPlastic, false)
	end
	part(model, "BodyMidBand", Vector3.new(7.15, 0.45, 4.35), chestCF * CFrame.new(0, -0.4, 0), C_GOLDBRIGHT, Enum.Material.SmoothPlastic, false)

	-- Remaches dorados brillantes
	for _, sx in { -2.1, 2.1 } do
		for _, sy in { -1.1, 0.6 } do
			part(model, "RivetF", Vector3.new(0.2, 0.2, 0.15), chestCF * CFrame.new(sx, sy, -2.18), C_GOLDBRIGHT, Enum.Material.Neon, false)
			part(model, "RivetB", Vector3.new(0.2, 0.2, 0.15), chestCF * CFrame.new(sx, sy, 2.18), C_GOLDBRIGHT, Enum.Material.Neon, false)
		end
	end

	-- 3. Tapa abovedada curvada en 3 capas
	local lidCF = chestCF * CFrame.new(0, 1.8, 0)
	local lid1 = part(model, "ChestLidBase", Vector3.new(7.4, 0.75, 4.6), lidCF * CFrame.new(0, 0.38, 0), C_DARKRED, Enum.Material.SmoothPlastic, true)
	local lid2 = part(model, "ChestLidMid", Vector3.new(7.0, 0.65, 3.8), lidCF * CFrame.new(0, 1.05, 0), C_DARKRED, Enum.Material.SmoothPlastic, true)
	local lid3 = part(model, "ChestLidTop", Vector3.new(6.4, 0.55, 2.8), lidCF * CFrame.new(0, 1.62, 0), C_DARKRED, Enum.Material.SmoothPlastic, true)

	-- Flejes dorados sobre la tapa abovedada
	for _, sx in { -2.1, 0, 2.1 } do
		part(model, "LidBand1", Vector3.new(0.58, 0.8, 4.7), lidCF * CFrame.new(sx, 0.38, 0), C_GOLD, Enum.Material.SmoothPlastic, false)
		part(model, "LidBand2", Vector3.new(0.58, 0.7, 3.9), lidCF * CFrame.new(sx, 1.05, 0), C_GOLD, Enum.Material.SmoothPlastic, false)
		part(model, "LidBand3", Vector3.new(0.58, 0.6, 2.9), lidCF * CFrame.new(sx, 1.62, 0), C_GOLD, Enum.Material.SmoothPlastic, false)
	end

	-- Borde dorado inferior de la tapa
	part(model, "LidBottomLip", Vector3.new(7.55, 0.25, 4.75), lidCF * CFrame.new(0, 0.05, 0), C_GOLDBRIGHT, Enum.Material.SmoothPlastic, false)

	-- Corona y gema en la cima
	part(model, "TopCrest", Vector3.new(2.4, 0.45, 0.6), lidCF * CFrame.new(0, 2.05, 0), C_GOLDBRIGHT, Enum.Material.SmoothPlastic, false)
	part(model, "TopGem", Vector3.new(0.7, 0.7, 0.7), lidCF * CFrame.new(0, 2.45, 0), C_CYAN_GEM, Enum.Material.Neon, false)

	-- 4. Cerradura central colosal con Gran Gema
	local lockCF = chestCF * CFrame.new(0, 0.2, -2.25)
	part(model, "LockPlate", Vector3.new(1.6, 2.0, 0.3), lockCF, C_GOLD, Enum.Material.SmoothPlastic, false)
	part(model, "LockPlateBorder", Vector3.new(1.8, 0.3, 0.35), lockCF * CFrame.new(0, 1.0, 0), C_GOLDBRIGHT, Enum.Material.SmoothPlastic, false)
	local bigGem = part(model, "LockGem", Vector3.new(0.8, 0.8, 0.4), lockCF * CFrame.new(0, 0.1, -0.05), C_CYAN_GEM, Enum.Material.Neon, false)
	part(model, "Keyhole", Vector3.new(0.3, 0.55, 0.42), lockCF * CFrame.new(0, -0.55, -0.05), Color3.fromRGB(25, 25, 30), Enum.Material.SmoothPlastic, false)

	-- Pestillo que baja de la tapa
	part(model, "LidLatch", Vector3.new(0.9, 1.1, 0.35), lidCF * CFrame.new(0, -0.25, -2.3), C_GOLDBRIGHT, Enum.Material.SmoothPlastic, false)

	-- 5. Luz y partículas de recompensa
	local light = Instance.new("PointLight")
	light.Name = "RewardGlow"
	light.Color = Color3.fromRGB(255, 230, 120)
	light.Range = 22
	light.Brightness = 2.0
	light.Parent = bigGem

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "RewardSparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 180)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 215, 45)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(45, 220, 255)),
	})
	sparkles.Rate = 16
	sparkles.Lifetime = NumberRange.new(1.4, 2.4)
	sparkles.Speed = NumberRange.new(1.5, 3.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.4, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.LightEmission = 1
	sparkles.Parent = body

	-- 6. Cartel flotante "RECLAMAR" en arcoíris
	local signAnchor = part(model, "SignAnchor", Vector3.one * 0.2, chestCF * CFrame.new(0, 6.4, 0), C_GOLD, Enum.Material.SmoothPlastic, false)
	signAnchor.Transparency = 1

	local bb = Instance.new("BillboardGui")
	bb.Name = "ClaimBanner"
	bb.Adornee = signAnchor
	bb.Size = UDim2.new(16, 0, 5.0, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 140
	bb.Parent = signAnchor

	local title = Instance.new("TextLabel")
	title.Name = "RainbowTitle"
	title.Size = UDim2.fromScale(1, 0.64)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "RECLAMAR"
	title.Parent = bb

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 50, 245)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(50, 155, 255)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(55, 255, 95)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 225, 45)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 45, 45)),
	})
	grad.Parent = title

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(16, 16, 22)
	titleStroke.Thickness = 4.5
	titleStroke.Parent = title

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.Position = UDim2.fromScale(0, 0.64)
	sub.Size = UDim2.fromScale(1, 0.34)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.FredokaOne
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(255, 224, 42)
	sub.Text = "¡Únete al grupo o dale un me gusta para reclamar!"
	sub.Parent = bb

	local subStroke = Instance.new("UIStroke")
	subStroke.Color = Color3.fromRGB(16, 16, 22)
	subStroke.Thickness = 3.0
	subStroke.Parent = sub

	model.PrimaryPart = body
	model.Parent = parent
end

function VillageService.start()
	PartFactory.removeExisting(Workspace, VillageConfig.ModelName)

	-- Limpiar cualquier modelo suelto que haya quedado en Workspace
	for _, name in { "AuxScene", "CofreReclamar", "BossBanana", "jefe_banana", "banana", "BananaMesh" } do
		local old = Workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local root = Instance.new("Model")
	root.Name = VillageConfig.ModelName
	root.Parent = Workspace

	-- Puestos del pueblo a los lados de la plaza (X = -36 y X = +36), mirando al centro. Juntos
	-- lo que se compra (Tienda y Mejorar Láser, al este) y lo que se reclama (Premios y
	-- Misiones, al oeste).
	buildStall(root, "Rewards", Vector2.new(-36, -12), Vector2.new(0, -12), "Premios", "Rewards", "🎁")
	buildStall(root, "Quests", Vector2.new(-36, 12), Vector2.new(0, 12), "Misiones", "Quests", "📜")
	buildStall(root, "Shop", Vector2.new(36, -12), Vector2.new(0, -12), "Tienda", "Shop", "🛒")
	buildStall(root, "LaserShop", Vector2.new(36, 12), Vector2.new(0, 12), "Mejorar Láser", "LaserShop", "⚡")

	local machine = VillageConfig.EvolutionMachine
	buildEvolutionMachine(root, machine.Position, machine.FaceToward, machine.Scale)
	buildFreeClaimChest(root, VillageConfig.ClaimChest.Position, VillageConfig.ClaimChest.FaceToward)
end

return VillageService
