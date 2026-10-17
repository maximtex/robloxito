-- Construye un santuario por cada huevo ACTIVO de EggConfig, cerca del área inicial.
-- Cada huevo tiene su estilo visual (Look.Style): Speckled (Bosque), Mossy (Musgo),
-- Runic (Ancestral) y Crystalline (Cristal, en el Valle Cristalino). Solo piezas nativas.
-- El ProximityPrompt solo abre el panel del huevo en el cliente; la compra pasa por
-- el RemoteEvent PurchaseEgg y la valida PetService (incluidos distancia y nivel).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared.Config.EggConfig)
local PetConfig = require(Shared.Config.PetConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local PetService = require(script.Parent.PetService)

local FOLDER_NAME = "EggShrines"
local STONE = Color3.fromRGB(150, 150, 136)
local DARK_STONE = Color3.fromRGB(96, 98, 92)
local WOOD = Color3.fromRGB(110, 80, 54)
local MOSS = Color3.fromRGB(92, 140, 64)
local GOLD = GeneratorConfig.Colors.Gold

local EggStandService = {}

local function toHex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
end

local function buildBillboard(adornee: BasePart, egg)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EggInfo"
	billboard.Size = UDim2.new(8, 0, 5.4, 0) -- en studs
	billboard.StudsOffset = Vector3.new(0, 4.4, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 45
	billboard.Adornee = adornee

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(24, 40, 34)
	frame.BackgroundTransparency = 0.15
	frame.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = egg.Look.Accent
	stroke.Thickness = 2
	stroke.Parent = frame

	local lines = {
		{ Text = egg.DisplayName, Height = 0.2, Font = Enum.Font.FredokaOne, Color = Color3.fromRGB(255, 244, 214) },
		{ Text = "⚡ " .. egg.Cost .. " de energía", Height = 0.14, Font = Enum.Font.GothamBold, Color = GOLD },
	}
	if (egg.RequiredLevel or 0) > 0 then
		local upgradeName = EconomyConfig.Upgrades[EggConfig.UnlockUpgradeId].DisplayName
		table.insert(lines, {
			Text = ("🔒 %s nivel %d"):format(upgradeName, egg.RequiredLevel),
			Height = 0.12,
			Font = Enum.Font.GothamBold,
			Color = Color3.fromRGB(214, 210, 196),
		})
	end
	-- Solo las mascotas que este huevo puede dar de verdad.
	for _, entry in egg.Chances do
		local pet = PetConfig.Pets[entry.PetId]
		local rarity = PetConfig.Rarities[pet.Rarity]
		table.insert(lines, {
			Text = ('<font color="%s">%s</font>  %s%%'):format(toHex(rarity.Color), pet.DisplayName, tostring(entry.Chance)),
			Height = 0.13,
			Font = Enum.Font.GothamBold,
			Color = Color3.fromRGB(240, 240, 228),
		})
	end

	local y = 0.05
	for index, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. index
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.06, y)
		label.Size = UDim2.fromScale(0.88, line.Height)
		label.Font = line.Font
		label.RichText = true
		label.TextScaled = true
		label.TextColor3 = line.Color
		label.Text = line.Text
		label.Parent = frame
		y += line.Height + 0.02
	end

	billboard.Parent = adornee
end

-- Huevo: esfera estirada con SpecialMesh nativo (sin recursos externos).
local function buildEgg(model: Model, center: Vector3, look): BasePart
	local material = if look.Style == "Runic"
		then Enum.Material.Slate
		elseif look.Style == "Crystalline" then Enum.Material.Glass
		else Enum.Material.SmoothPlastic
	local eggPart = PartFactory.part(model, "Egg", {
		Size = Vector3.one * 2.4,
		CFrame = CFrame.new(center),
		Color = look.Shell,
		Material = material,
		Solid = false,
	})
	if look.Style == "Crystalline" then
		eggPart.Transparency = 0.2
		eggPart.Reflectance = 0.15
	end
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = eggPart

	if look.Style == "Crystalline" then
		-- Núcleo de energía visible a través de la cáscara de cristal
		PartFactory.part(model, "Core", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.1,
			CFrame = CFrame.new(center),
			Color = look.Accent,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		-- Minerales que brotan de la cáscara
		for index, spec in { { Vector3.new(0.9, 0.6, 0.3), -40 }, { Vector3.new(-0.8, 0.2, 0.6), 35 }, { Vector3.new(0.1, 1.3, -0.5), 10 }, { Vector3.new(-0.4, -0.6, -0.9), -25 } } do
			PartFactory.part(model, "Mineral" .. index, {
				Size = Vector3.new(0.35, 0.9, 0.35),
				CFrame = CFrame.new(center + spec[1]) * CFrame.Angles(math.rad(spec[2]), math.rad(45), math.rad(spec[2] * 0.6)),
				Color = if index % 2 == 0 then look.Spots else look.Accent,
				Material = Enum.Material.Neon,
				Solid = false,
			})
		end
		-- Banda de musgo en la base del huevo
		PartFactory.verticalCylinder(model, "MossBand", center + Vector3.new(0, -1.0, 0), 0.35, 2.3, MOSS, Enum.Material.LeafyGrass, false)
	elseif look.Style == "Runic" then
		-- Bandas de runas doradas alrededor de la cáscara
		for index, height in { -0.6, 0.5 } do
			local radius = if height < 0 then 1.12 else 1.08
			PartFactory.verticalCylinder(model, "RuneBand" .. index, center + Vector3.new(0, height, 0), 0.12, radius * 2.02, look.Spots, Enum.Material.Neon, false)
		end
	elseif look.Style == "Mossy" then
		-- Parches de musgo y una hoja en la punta
		for index, offset in { Vector3.new(0.95, 0.2, 0.55), Vector3.new(-0.8, 0.7, -0.6), Vector3.new(-0.3, -0.7, 1.0), Vector3.new(0.5, 0.9, -0.7) } do
			PartFactory.part(model, "MossPatch" .. index, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.75,
				CFrame = CFrame.new(center + offset),
				Color = look.Spots,
				Material = Enum.Material.LeafyGrass,
				Solid = false,
			})
		end
		PartFactory.part(model, "Leaf", {
			Size = Vector3.new(0.9, 0.08, 0.45),
			CFrame = CFrame.new(center + Vector3.new(0.2, 1.6, 0)) * CFrame.Angles(0, 0, math.rad(25)),
			Color = MOSS,
			Material = Enum.Material.LeafyGrass,
			Solid = false,
		})
	else
		for index, offset in { Vector3.new(1.05, 0.3, 0.35), Vector3.new(-0.6, 0.9, 0.85), Vector3.new(0.2, -0.5, -1.08) } do
			PartFactory.part(model, "Spot" .. index, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.55,
				CFrame = CFrame.new(center + offset),
				Color = look.Spots,
				Material = Enum.Material.SmoothPlastic,
				Solid = false,
			})
		end
	end

	return eggPart
end

-- Decoración propia de cada santuario alrededor del pedestal.
local function buildSurroundings(model: Model, position: Vector3, look)
	if look.Style == "Crystalline" then
		-- Pilares de cristal natural alrededor del pedestal, en los colores del Valle
		for index, spec in { { -2.9, 0.6, 3.8, -12 }, { 3.0, 0.2, 3.2, 14 }, { -2.2, -2.4, 2.4, -20 }, { 2.4, -2.3, 2.8, 18 } } do
			local part = PartFactory.part(model, "Pillar" .. index, {
				Size = Vector3.new(0.9, spec[3], 0.9),
				CFrame = CFrame.new(position + Vector3.new(spec[1], spec[3] / 2 + 0.4, spec[2])) * CFrame.Angles(0, math.rad(45), math.rad(spec[4])),
				Color = if index % 2 == 0 then look.Spots else look.Accent,
				Material = if index <= 2 then Enum.Material.Neon else Enum.Material.Glass,
				Solid = false,
			})
			if index > 2 then
				part.Transparency = 0.15
			end
		end
	elseif look.Style == "Runic" then
		-- Dos menhires con runas doradas
		for index, side in { -1, 1 } do
			local base = CFrame.new(position + Vector3.new(side * 3.1, 0, -0.6)) * CFrame.Angles(0, 0, math.rad(side * -6))
			PartFactory.part(model, "Menhir" .. index, {
				Size = Vector3.new(1.2, 4.6, 0.8),
				CFrame = base * CFrame.new(0, 2.1, 0),
				Color = DARK_STONE,
				Material = Enum.Material.Slate,
			})
			PartFactory.part(model, "MenhirRune" .. index, {
				Size = Vector3.new(0.22, 2, 0.06),
				CFrame = base * CFrame.new(0, 2.6, 0.43),
				Color = look.Spots,
				Material = Enum.Material.Neon,
				Solid = false,
			})
		end
	elseif look.Style == "Mossy" then
		-- Setas y helechos alrededor
		for index, offset in { Vector3.new(2.6, 0, 1.6), Vector3.new(-2.8, 0, 1.2), Vector3.new(-2.2, 0, -2.2) } do
			local base = position + offset
			PartFactory.verticalCylinder(model, "MushroomStem" .. index, base + Vector3.new(0, 0.9, 0), 1, 0.4, Color3.fromRGB(236, 226, 200), Enum.Material.SmoothPlastic, false)
			local cap = PartFactory.part(model, "MushroomCap" .. index, {
				Size = Vector3.new(1.3, 0.6, 1.3),
				CFrame = CFrame.new(base + Vector3.new(0, 1.45, 0)),
				Color = Color3.fromRGB(96, 224, 200),
				Material = Enum.Material.Neon,
				Solid = false,
			})
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = cap
		end
	else
		-- Cristales a los lados del pedestal
		for index, side in { -1, 1 } do
			local shard = PartFactory.part(model, "Crystal" .. index, {
				Size = Vector3.new(0.6, 2.2, 0.6),
				CFrame = CFrame.new(position + Vector3.new(side * 2.4, 1.6, 1.2)) * CFrame.Angles(0, math.rad(45), math.rad(side * 14)),
				Color = GeneratorConfig.Colors.Crystal,
				Material = Enum.Material.Neon,
				Solid = false,
			})
			shard.Transparency = 0.1
		end
	end
end

local function buildShrine(parent: Instance, eggId: string, egg)
	local position = PetService.getStandPosition(eggId)
	if not position then
		return
	end
	local look = egg.Look

	local model = Instance.new("Model")
	model.Name = "EggShrine_" .. eggId
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("EggId", eggId)

	local baseColor = if look.Style == "Runic" then DARK_STONE elseif look.Style == "Crystalline" then Color3.fromRGB(176, 172, 192) else STONE
	local base = PartFactory.verticalCylinder(model, "Base", position + Vector3.new(0, 0.3, 0), 0.8, 7, baseColor, Enum.Material.Slate, true)
	PartFactory.verticalCylinder(model, "MossRing", position + Vector3.new(0, 0.72, 0), 0.06, 6.4, MOSS, Enum.Material.LeafyGrass, false)

	local pedestalHeight = 2.2
	local pedestal = PartFactory.verticalCylinder(model, "Pedestal", position + Vector3.new(0, 0.7 + pedestalHeight / 2, 0), pedestalHeight, 2.6, DARK_STONE, Enum.Material.Cobblestone, true)
	local nestY = 0.7 + pedestalHeight + 0.25
	PartFactory.verticalCylinder(model, "Nest", position + Vector3.new(0, nestY, 0), 0.5, 3.6, WOOD, Enum.Material.Wood, true)
	PartFactory.verticalCylinder(model, "NestMoss", position + Vector3.new(0, nestY + 0.03, 0), 0.5, 3, MOSS, Enum.Material.LeafyGrass, false)

	local eggPart = buildEgg(model, position + Vector3.new(0, nestY + 1.6, 0), look)
	buildSurroundings(model, position, look)
	buildBillboard(eggPart, egg)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EggPrompt"
	prompt.ActionText = "Ver huevo"
	prompt.ObjectText = egg.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("EggId", eggId)
	prompt.Parent = pedestal

	model.PrimaryPart = base
	model.Parent = parent
end

function EggStandService.start()
	PartFactory.removeExisting(workspace, FOLDER_NAME)
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	for eggId, egg in EggConfig.Eggs do
		-- Un huevo sin recompensas implementadas (Enabled = false) no se construye.
		if egg.Enabled ~= false then
			buildShrine(folder, eggId, egg)
		end
	end

	folder.Parent = workspace
end

return EggStandService
