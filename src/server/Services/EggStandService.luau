-- Construye el Jardín de mascotas (el antiguo Jardín de los Huevos, mismo sitio y piezas)
-- con las piezas de pedestales-huevos.glb (EggGardenData):
-- - Pedestales octogonales con anillo dorado y luz de su color (EggConfig.Stands.*.Pedestal),
--   mirando al altar. Cada uno vende UNA mascota fija por dinero: la mascota gira encima (la
--   dibuja el cliente, PetStandDisplay, sobre la pieza PetDisplay), su nombre y su precio
--   flotan encima y con E se compra (PetShopPrompt -> PetService.buyPet).
-- - Altar central de dos pisos con runas, con la mascota exclusiva a la venta por Robux
--   (Gardens.Forest.FeaturedPet) o, si el place no tiene su modelo, una mascota guardiana
--   coronada, velas cian y anillos de aura.
-- - Pedestal rosa (arcoíris) con la mascota más cara del jardín (Gardens.Forest.RainbowPet).

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared.Config.EggConfig)
local PetConfig = require(Shared.Config.PetConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local GlbParts = require(script.Parent.Parent.Util.GlbParts)
local EggGardenData = require(script.Parent.Parent.Util.EggGardenData)
local PetService = require(script.Parent.PetService)

local FOLDER_NAME = "PetGarden"
local ORIGIN = Vector3.new(GeneratorConfig.Position.X, 0, GeneratorConfig.Position.Z)
local GROUND = GeneratorConfig.Position.Y
local BILLBOARD_ABOVE_PET = 3.8
local PET_ABOVE_TOP = 2.2 -- centro de la mascota sobre la cara de arriba de su pedestal
local BILLBOARD_DISTANCE = 95

local EggStandService = {}

local function world(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- Sube lo que va sobre el patio del jardín (un camino: StudFloor.PathRaise más alto)
local function onFloor(pos: Vector3): Vector3
	return pos + Vector3.new(0, StudFloor.raiseAt(pos.X, pos.Z), 0)
end

-- Texto flotante de 2 líneas estilo cartoon: nombre de la mascota + precio
local function buildStandTitle(adornee: BasePart, titleText: string, titleColor: Color3, costText: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StandInfo"
	billboard.Size = UDim2.new(9.5, 0, 3.6, 0)
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = BILLBOARD_DISTANCE
	billboard.Adornee = adornee

	local topLabel = Instance.new("TextLabel")
	topLabel.Name = "RarityTitle"
	topLabel.Position = UDim2.fromScale(0, 0)
	topLabel.Size = UDim2.fromScale(1, 0.56)
	topLabel.BackgroundTransparency = 1
	topLabel.Font = Enum.Font.FredokaOne
	topLabel.TextScaled = true
	topLabel.TextColor3 = titleColor
	topLabel.Text = titleText
	topLabel.Parent = billboard

	local topStroke = Instance.new("UIStroke")
	topStroke.Color = Color3.fromRGB(16, 18, 24)
	topStroke.Thickness = 3.5
	topStroke.Parent = topLabel

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostTitle"
	costLabel.Position = UDim2.fromScale(0, 0.54)
	costLabel.Size = UDim2.fromScale(1, 0.44)
	costLabel.BackgroundTransparency = 1
	costLabel.Font = Enum.Font.FredokaOne
	costLabel.TextScaled = true
	costLabel.TextColor3 = Color3.fromRGB(255, 224, 36)
	costLabel.Text = costText
	costLabel.Parent = billboard

	local costStroke = Instance.new("UIStroke")
	costStroke.Color = Color3.fromRGB(16, 18, 24)
	costStroke.Thickness = 3
	costStroke.Parent = costLabel

	billboard.Parent = adornee
end

-- Pedestal de pedestales-huevos.glb (EggGardenData[variant]) con la base en `base` (cara de
-- arriba del suelo), mirando al altar del jardín como en el diseño. Devuelve su placa de luz
-- (donde va la interacción) y el centro de su cara de arriba, donde va la mascota.
local function buildPedestal(parent: Instance, base: Vector3, variant: string): (BasePart, Vector3)
	local data = EggGardenData[variant] or EggGardenData.Comun
	local altarAt = EggConfig.Gardens.Forest.AltarOffset
	local altar = world(altarAt.X, base.Y, altarAt.Y)
	local parts = GlbParts.build(parent, data, CFrame.lookAt(base, altar))
	return parts.glow_pad, base + Vector3.new(0, EggGardenData.Top[variant] or EggGardenData.Top.Comun, 0)
end

-- Pedestal que vende la mascota de `offer` ({ PetId, Price }) con la base en `base`
local function buildStand(parent: Instance, standId: string, offer, base: Vector3, variant: string, accent: Color3)
	local pet = PetConfig.Pets[offer.PetId]
	if not pet then
		return
	end
	local rarity = PetConfig.Rarities[pet.Rarity]
	local model = Instance.new("Model")
	model.Name = "PetStand_" .. standId
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("ShopStand", standId)

	local pedestal, top = buildPedestal(model, base, variant)
	local center = top + Vector3.new(0, PET_ABOVE_TOP, 0)
	local display = PartFactory.part(model, "PetDisplay", {
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(center),
		Color = accent,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	display.Transparency = 1
	display:SetAttribute("ShopPet", offer.PetId)

	local anchor = PartFactory.part(model, "InfoAnchor", {
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(center + Vector3.new(0, BILLBOARD_ABOVE_PET, 0)),
		Color = accent,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	anchor.Transparency = 1
	local multiplier = pet.Multiplier or (rarity and rarity.Multiplier) or 1
	buildStandTitle(anchor, pet.DisplayName, if rarity then rarity.Color else Color3.new(1, 1, 1), ("💰 %s  ·  ×%s"):format(formatNumber(offer.Price), tostring(multiplier)))

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PetShopPrompt"
	prompt.ActionText = "Comprar · $" .. formatNumber(offer.Price)
	prompt.ObjectText = pet.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 13
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ShopStand", standId)
	prompt.Parent = pedestal

	model.PrimaryPart = pedestal
	model.Parent = parent
end

local function buildFeaturedPet(altar: Model, padTop: Vector3, base: BasePart): boolean
	local garden = EggConfig.Gardens.Forest
	local petId = garden.FeaturedPet
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local source = folder and petId and folder:FindFirstChild(petId)
	if not source then
		return false
	end
	local copy = source:Clone()
	local pet: Model
	if copy:IsA("Model") then
		pet = copy
	else
		pet = Instance.new("Model")
		copy.Parent = pet
		if copy:IsA("BasePart") then
			pet.PrimaryPart = copy
		end
	end
	pet.Name = "FeaturedPet_" .. source.Name
	pet:SetAttribute("MapAsset", source.Name) -- contenido del place: WorkspaceAudit no lo lista
	for _, item in pet:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end

	local scale = garden.FeaturedPetScale or 1
	pet:ScaleTo(scale)
	-- Más grande, más chispas: la misma cantidad de partículas por superficie
	for _, item in pet:GetDescendants() do
		if item:IsA("ParticleEmitter") then
			item.Enabled = true
			item.Rate *= scale * scale
		end
	end

	-- Flotando justo encima del altar
	local box, size = pet:GetBoundingBox()
	local center = padTop + Vector3.new(0, size.Y / 2 + 0.3, 0)
	local facing = CFrame.lookAt(center, center - Vector3.xAxis) * CFrame.Angles(0, math.rad(garden.FeaturedPetYaw or 0), 0)
	pet:PivotTo(facing * box:ToObjectSpace(pet:GetPivot()))
	pet.Parent = altar

	-- Nombre (color de su rareza) y precio flotando encima
	local def = PetConfig.Pets[petId]
	local rarity = def and PetConfig.Rarities[def.Rarity]
	local anchor = PartFactory.part(altar, "InfoAnchor", {
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(center + Vector3.new(0, size.Y / 2 + 2.6, 0)),
		Color = Color3.new(1, 1, 1),
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	anchor.Transparency = 1
	local product = MonetizationConfig.PetProducts[petId]
	local forSale = product ~= nil and typeof(product.Id) == "number" and product.Id > 0
	buildStandTitle(anchor, if def then def.DisplayName else petId, if rarity then rarity.Color else Color3.new(1, 1, 1), if forSale then "Robux" else "Robux · Próximamente")
	if forSale then
		-- El precio lo pone Roblox (el del Creator Dashboard)
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, product.Id, Enum.InfoType.Product)
			local label = anchor:FindFirstChild("CostTitle", true)
			if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" and label and label:IsA("TextLabel") then
				label.Text = "R$ " .. formatNumber(info.PriceInRobux)
			end
		end)
	end
	if product then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PetProductPrompt"
		prompt.ActionText = "Comprar con Robux"
		prompt.ObjectText = (if def then def.DisplayName else petId) .. (if rarity then " · " .. rarity.DisplayName else "")
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 13
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("PetProduct", petId)
		prompt.Parent = base
	end
	return true
end

-- Altar central dorado/morado con la mascota de exhibición (o un guardián coronado con velas
-- cian y aura)
local function buildFeaturedGuardianAltar(parent: Instance)
	local altar = Instance.new("Model")
	altar.Name = "FeaturedPetAltar"

	-- Al fondo del arco del Jardín de los Huevos, en el centro: el altar de
	-- pedestales-huevos.glb con su escalón hacia la entrada del jardín (-X)
	local altarAt = EggConfig.Gardens.Forest.AltarOffset
	local pos = onFloor(world(altarAt.X, GROUND + StudFloor.BaseTop, altarAt.Y))
	local goldColor = Color3.fromRGB(246, 184, 34)
	local cyanNeon = Color3.fromRGB(64, 245, 220)
	local parts = GlbParts.build(altar, EggGardenData.Altar, CFrame.lookAt(pos, pos - Vector3.xAxis))
	local padTop = pos + Vector3.new(0, EggGardenData.Top.Altar, 0)

	-- La mascota exclusiva sobre la superficie de runas; sin ella, la guardiana de bloques
	if buildFeaturedPet(altar, padTop, parts.rune_pad) then
		altar.Parent = parent
		return
	end

	-- Mascota guardiana central (estilo calavera tierna coronada con velas de llama cian, como en la captura 4)
	local bodyCenter = padTop + Vector3.new(0, 1.67, 0)
	local head = PartFactory.part(altar, "GuardianHead", {
		Size = Vector3.new(3.4, 3.0, 3.1),
		CFrame = CFrame.new(bodyCenter),
		Color = Color3.fromRGB(246, 236, 232),
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	local headCorner = Instance.new("SpecialMesh")
	headCorner.MeshType = Enum.MeshType.Brick
	headCorner.Parent = head

	-- Ojos grandes tiernos (negro + iris turquesa + brillo blanco)
	for _, side in { -0.82, 0.82 } do
		PartFactory.ball(altar, "EyeSocket", bodyCenter + Vector3.new(side * 0.2, 0.15, -1.45) + Vector3.new(0, 0, side), 0.95, Color3.fromRGB(22, 24, 32), Enum.Material.SmoothPlastic, false)
		PartFactory.ball(altar, "EyeIris", bodyCenter + Vector3.new(-1.52, 0.15, side), 0.65, cyanNeon, Enum.Material.Neon, false)
		PartFactory.ball(altar, "EyeSpark", bodyCenter + Vector3.new(-1.62, 0.3, side - 0.12), 0.24, Color3.new(1, 1, 1), Enum.Material.Neon, false)
	end

	-- Corona real dorada + velas mágicas con llama cian
	PartFactory.part(altar, "CrownBand", {
		Size = Vector3.new(3.5, 0.7, 3.3),
		CFrame = CFrame.new(bodyCenter + Vector3.new(0, 1.65, 0)),
		Color = goldColor,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	for i = -2, 2 do
		local candlePos = bodyCenter + Vector3.new(0, 2.45 + (2 - math.abs(i)) * 0.25, i * 0.68)
		PartFactory.verticalCylinder(altar, "Candle" .. i, candlePos, 1.1, 0.34, Color3.fromRGB(248, 248, 252), Enum.Material.SmoothPlastic, false)
		PartFactory.ball(altar, "CandleFlame" .. i, candlePos + Vector3.new(0, 0.75, 0), 0.46, cyanNeon, Enum.Material.Neon, false)
	end

	-- Anillos de aura mágica alrededor del altar
	local aura = PartFactory.ball(altar, "MagicAura", bodyCenter + Vector3.new(0, 0.4, 0), 6.8, cyanNeon, Enum.Material.ForceField, false)
	aura.Transparency = 0.55

	altar.Parent = parent
end

function EggStandService.start()
	PartFactory.removeExisting(workspace, FOLDER_NAME)
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	-- La plaza gris ahora forma parte del suelo de bloques (StudFloor).
	buildFeaturedGuardianAltar(folder)

	for standId, stand in EggConfig.Stands do
		local position = stand.Enabled ~= false and PetService.getStandPosition(standId)
		if position then
			buildStand(folder, standId, stand, onFloor(position) + Vector3.new(0, StudFloor.BaseTop, 0), stand.Pedestal or "Comun", stand.Look.Accent)
		end
	end
	-- Extremo derecho del arco del jardín (visto desde la avenida): el pedestal arcoíris
	local garden = EggConfig.Gardens.Forest
	local rainbowAt = garden.RainbowOffset
	buildStand(folder, "Rainbow", garden.RainbowPet, onFloor(world(rainbowAt.X, GROUND + StudFloor.BaseTop, rainbowAt.Y)), "Arcoiris", Color3.fromRGB(242, 48, 128))

	folder.Parent = workspace
end

return EggStandService
