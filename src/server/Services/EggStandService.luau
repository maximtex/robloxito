-- Construye el Jardín de los Huevos con las piezas de pedestales-huevos.glb (EggGardenData):
-- - Pedestales octogonales con anillo dorado y luz de su color (Común azul, No común verde,
--   Raro turquesa y Arcoíris rosa; EggConfig.Eggs.*.Pedestal), mirando al altar.
-- - Texto flotante limpio de 2 líneas con borde negro grueso (sin caja de fondo):
--     COMÚN / NO COMÚN / RARO + costo en amarillo brillante.
-- - Altar central de dos pisos con runas, con la mascota exclusiva a la venta por Robux
--   (Gardens.Forest.FeaturedPet) o, si el place no tiene su modelo, una mascota guardiana
--   coronada, velas cian y anillos de aura.
-- - Pedestal rosa con el Huevo del Arcoíris: ahora es el Huevo Clásico (EggConfig.Eggs.ClassicEgg,
--   un huevo normal en RainbowOffset). Si ningún huevo ocupa ese sitio, vuelve el decorativo.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EggConfig = require(Shared.Config.EggConfig)
local PetConfig = require(Shared.Config.PetConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local GlbParts = require(script.Parent.Parent.Util.GlbParts)
local EggGardenData = require(script.Parent.Parent.Util.EggGardenData)
local PetService = require(script.Parent.PetService)

local FOLDER_NAME = "EggShrines"
local ORIGIN = Vector3.new(GeneratorConfig.Position.X, 0, GeneratorConfig.Position.Z)
local GROUND = GeneratorConfig.Position.Y
local BILLBOARD_ABOVE_EGG = 3.8
local EGG_ABOVE_TOP = 2.18 -- centro del huevo sobre la cara de arriba de su pedestal
local BILLBOARD_DISTANCE = 95

local EggStandService = {}

local function world(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- Sube lo que va sobre el patio del jardín (un camino: StudFloor.PathRaise más alto)
local function onFloor(pos: Vector3): Vector3
	return pos + Vector3.new(0, StudFloor.raiseAt(pos.X, pos.Z), 0)
end

-- Texto flotante de 2 líneas estilo cartoon (como en las capturas 4 y 5: "COMÚN" + "💰 250")
local function buildFloatingEggTitle(adornee: BasePart, titleText: string, titleColor: Color3, costText: string)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EggInfo"
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
-- (donde va la interacción) y el centro de su cara de arriba, donde se apoya el huevo.
-- faceToward: a dónde mira (en el mundo); sin él, al altar del Jardín de los Huevos.
local function buildPedestal(parent: Instance, base: Vector3, variant: string, faceToward: Vector3?): (BasePart, Vector3)
	local data = EggGardenData[variant] or EggGardenData.Comun
	local altarAt = EggConfig.Gardens.Forest.AltarOffset
	local altar = faceToward or world(altarAt.X, base.Y, altarAt.Y)
	local parts = GlbParts.build(parent, data, CFrame.lookAt(base, Vector3.new(altar.X, base.Y, altar.Z)))
	return parts.glow_pad, base + Vector3.new(0, EggGardenData.Top[variant] or EggGardenData.Top.Comun, 0)
end

local function buildEgg(shrine: Model, center: Vector3, look): BasePart
	local model = Instance.new("Model")
	model.Name = "EggBody"
	model.Parent = shrine

	local eggCF = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(-5))
	local meshScale = Vector3.new(3.6, 3.6, 3.6)

	local eggPart = PartFactory.part(model, "Egg", {
		Size = Vector3.new(3.5, 4.6, 3.5),
		CFrame = eggCF,
		Color = look.Shell,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	eggPart.Reflectance = 0.08
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = EggConfig.Art.Shell
	mesh.Scale = meshScale
	mesh.Parent = eggPart

	if look.Style == "Lightning" then
		-- Destellos eléctricos como el huevo RARO de la captura
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "LightningSparks"
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(Color3.fromRGB(190, 245, 255), Color3.fromRGB(60, 210, 255))
		sparkles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.5, 0.7),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkles.Lifetime = NumberRange.new(0.35, 0.7)
		sparkles.Rate = 8
		sparkles.Speed = NumberRange.new(1.5, 3.5)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.LightEmission = 1
		sparkles.Parent = eggPart
	elseif look.Style == "Rainbow" then
		-- Las 32 bandas arcoíris (textura) + las grietas 3D: el anillo y tres arriba y abajo
		mesh.TextureId = EggConfig.Art.RainbowTexture
		mesh.VertexColor = Vector3.new(1, 1, 1)

		for index, crack in EggConfig.Art.Cracks do
			local cracksPart = PartFactory.part(model, "Cracks" .. index, {
				Size = Vector3.new(1, 1, 1),
				CFrame = eggCF * CFrame.new(crack.Offset * meshScale),
				Color = Color3.fromRGB(162, 38, 232),
				Material = Enum.Material.Neon,
				Solid = false,
			})
			local crackMesh = Instance.new("SpecialMesh")
			crackMesh.MeshType = Enum.MeshType.FileMesh
			crackMesh.MeshId = crack.Mesh
			crackMesh.Scale = meshScale
			crackMesh.Parent = cracksPart
		end
	end

	model.WorldPivot = CFrame.new(center)
	return eggPart
end

local function buildShrine(parent: Instance, eggId: string, egg)
	local position = PetService.getStandPosition(eggId)
	if not position then
		return
	end
	local look = egg.Look
	local zoneId = egg.Zone or ZoneConfig.DefaultZone

	local model = Instance.new("Model")
	model.Name = "EggShrine_" .. eggId
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("EggId", eggId)
	model:SetAttribute("Zone", zoneId)

	local neonColor = look.Accent or Color3.fromRGB(45, 215, 255)
	local base = onFloor(position) + Vector3.new(0, StudFloor.BaseTop, 0)
	-- FaceToward (relativo al centro de su zona, como StandOffset): a dónde mira el pedestal
	local faceToward = nil
	if egg.FaceToward then
		local stand = egg.StandOffset
		faceToward = position + Vector3.new(egg.FaceToward.X - stand.X, 0, egg.FaceToward.Y - stand.Y)
	end
	local pedestal, top = buildPedestal(model, base, egg.Pedestal or "Comun", faceToward)

	local eggCenter = top + Vector3.new(0, EGG_ABOVE_TOP, 0)
	buildEgg(model, eggCenter, look)

	local anchor = PartFactory.part(model, "InfoAnchor", {
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(eggCenter + Vector3.new(0, BILLBOARD_ABOVE_EGG, 0)),
		Color = neonColor,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	anchor.Transparency = 1

	local titleText = egg.RarityTitle or egg.DisplayName
	local titleColor = egg.TitleColor or Color3.new(1, 1, 1)
	local costText = "💰 " .. formatNumber(egg.Cost)
	buildFloatingEggTitle(anchor, titleText, titleColor, costText)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EggPrompt"
	prompt.ActionText = "¡Eclosionar! (" .. formatNumber(egg.Cost) .. " 💰)"
	prompt.ObjectText = egg.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 13
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("EggId", eggId)
	prompt.Parent = pedestal

	model.PrimaryPart = pedestal
	model.Parent = parent
end

-- Plataforma gris clara con studs donde van los huevos y el altar central
local function buildEggPlaza(parent: Instance)
	local plaza = Instance.new("Model")
	plaza.Name = "EggStonePlaza"

	local center = world(0, GROUND + 0.22, 26)
	local border = PartFactory.part(plaza, "PlazaBorder", {
		Size = Vector3.new(28, 0.40, 28),
		CFrame = CFrame.new(center),
		Color = Color3.fromRGB(152, 156, 174),
		Material = Enum.Material.Plastic,
		Solid = true,
	})
	border.TopSurface = Enum.SurfaceType.Studs

	local inner = PartFactory.part(plaza, "PlazaSurface", {
		Size = Vector3.new(25.6, 0.44, 26.8),
		CFrame = CFrame.new(center + Vector3.new(0, 0.03, 0.6)),
		Color = Color3.fromRGB(204, 206, 226),
		Material = Enum.Material.Plastic,
		Solid = true,
	})
	inner.TopSurface = Enum.SurfaceType.Studs

	plaza.Parent = parent
end

-- Construye un Haxigator limpio con piezas nativas si el modelo del place falta o está corrupto
-- (p. ej. si trae agrupado un mini-mapa o mallas desfasadas que disparan su caja a >10 studs).
local function buildCleanCrocodile(parent: Instance): BasePart
	local green = Color3.fromRGB(76, 188, 72)
	local darkGreen = Color3.fromRGB(42, 128, 48)
	local bellyColor = Color3.fromRGB(238, 224, 132)
	local eyeWhite = Color3.fromRGB(250, 250, 252)
	local pupilColor = Color3.fromRGB(24, 28, 34)

	local body = PartFactory.part(parent, "Body", {
		Size = Vector3.new(3.2, 2.2, 2.5),
		CFrame = CFrame.new(0, 1.5, 0),
		Color = green,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	PartFactory.part(parent, "Belly", {
		Size = Vector3.new(2.9, 1.5, 2.56),
		CFrame = CFrame.new(0.1, 1.25, 0),
		Color = bellyColor,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	PartFactory.part(parent, "Head", {
		Size = Vector3.new(2.4, 2.1, 2.6),
		CFrame = CFrame.new(-1.2, 2.35, 0),
		Color = green,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	PartFactory.part(parent, "Snout", {
		Size = Vector3.new(2.2, 1.15, 2.2),
		CFrame = CFrame.new(-2.6, 2.0, 0),
		Color = green,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	PartFactory.part(parent, "Jaw", {
		Size = Vector3.new(2.0, 0.55, 2.0),
		CFrame = CFrame.new(-2.5, 1.35, 0),
		Color = bellyColor,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	for _, z in { -0.68, 0.68 } do
		PartFactory.ball(parent, "Nostril", Vector3.new(-3.45, 2.62, z), 0.28, darkGreen, Enum.Material.SmoothPlastic, false)
		PartFactory.ball(parent, "Eye", Vector3.new(-2.15, 2.85, z * 1.45), 0.58, eyeWhite, Enum.Material.SmoothPlastic, false)
		PartFactory.ball(parent, "Pupil", Vector3.new(-2.38, 2.85, z * 1.48), 0.32, pupilColor, Enum.Material.SmoothPlastic, false)
		PartFactory.part(parent, "Tooth", {
			Size = Vector3.new(0.28, 0.38, 0.28),
			CFrame = CFrame.new(-3.2, 1.62, z * 1.1),
			Color = eyeWhite,
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
	end
	for _, x in { -0.95, 0.95 } do
		for _, z in { -1.15, 1.15 } do
			PartFactory.part(parent, "Leg", {
				Size = Vector3.new(0.95, 0.9, 0.85),
				CFrame = CFrame.new(x, 0.45, z),
				Color = green,
				Material = Enum.Material.SmoothPlastic,
				Solid = false,
			})
		end
	end
	PartFactory.part(parent, "Tail", {
		Size = Vector3.new(2.4, 1.1, 1.35),
		CFrame = CFrame.new(2.35, 1.15, 0),
		Color = green,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	-- Crestas dorsales pegadas al lomo (sin mallas con offset que se separen al escalar)
	for i, crest in {
		{ X = -0.7, Y = 3.55, S = Vector3.new(0.65, 0.45, 0.9) },
		{ X = 0.25, Y = 2.82, S = Vector3.new(0.75, 0.5, 1.0) },
		{ X = 1.15, Y = 2.62, S = Vector3.new(0.7, 0.45, 0.9) },
		{ X = 2.15, Y = 1.85, S = Vector3.new(0.65, 0.4, 0.75) },
	} do
		PartFactory.part(parent, "Crest" .. i, {
			Size = crest.S,
			CFrame = CFrame.new(crest.X, crest.Y, 0),
			Color = darkGreen,
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
	end
	return body
end

-- Comprueba si el modelo de ReplicatedStorage.PetModels está corrupto (p. ej. contiene un mapa
-- entero, piezas a más de 6 studs de su raíz, demasiadas piezas o SpecialMesh con Offset).
local function isPetModelCorrupted(model: Model): boolean
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not root then
		return true
	end
	local _, rawSize = model:GetBoundingBox()
	if rawSize.X > 8 or rawSize.Y > 8 or rawSize.Z > 8 or rawSize.Y < 0.2 then
		return true
	end
	local partCount = 0
	for _, item in model:GetDescendants() do
		if item:IsA("Model") then
			return true
		elseif item:IsA("SpecialMesh") and item.Offset.Magnitude > 0.05 then
			return true
		elseif item:IsA("BasePart") then
			partCount += 1
			if (item.Position - root.Position).Magnitude > 6 then
				return true
			end
		end
	end
	return partCount == 0 or partCount > 35
end

-- Mascota exclusiva sobre el altar (Gardens.Forest.FeaturedPet): su modelo de
-- ReplicatedStorage.PetModels (guardado en el place, fuera de Rojo; el mismo que te sigue al
-- comprarla), agrandado, con sus partículas y mirando a la entrada del jardín (-X). Encima, su
-- nombre y su precio en Robux; con E se compra (MonetizationConfig.PetProducts, lo abre
-- ShopController). Si el modelo del place está corrupto o sobredimensionado, lo sanea.
local function buildFeaturedPet(altar: Model, padTop: Vector3, base: BasePart): boolean
	local garden = EggConfig.Gardens.Forest
	local petId = garden.FeaturedPet
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local source = folder and petId and folder:FindFirstChild(petId)
	if not source then
		return false
	end
	local pet: Model
	local scale = garden.FeaturedPetScale or 1
	local sourceModel = if source:IsA("Model") then source else nil
	if sourceModel and not isPetModelCorrupted(sourceModel) then
		pet = sourceModel:Clone()
		pet:ScaleTo(pet:GetScale() * scale)
		local _, scaledSize = pet:GetBoundingBox()
		if scaledSize.X > 12 or scaledSize.Y > 12 or scaledSize.Z > 12 then
			pet:Destroy()
			pet = Instance.new("Model")
			pet.PrimaryPart = buildCleanCrocodile(pet)
		end
	else
		-- Saneamos también la plantilla en ReplicatedStorage.PetModels para que el cliente
		-- (PetModelBuilder) no clone el mini-mapa roto si alguien equipa la mascota.
		pet = Instance.new("Model")
		pet.PrimaryPart = buildCleanCrocodile(pet)
		if folder and source then
			local cleanTemplate = pet:Clone()
			cleanTemplate.Name = source.Name
			source:Destroy()
			cleanTemplate.Parent = folder
		end
	end
	pet.Name = "FeaturedPet_" .. petId
	pet:SetAttribute("MapAsset", petId) -- contenido del place: WorkspaceAudit no lo lista
	for _, item in pet:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end

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
	buildFloatingEggTitle(anchor, if def then def.DisplayName else petId, if rarity then rarity.Color else Color3.new(1, 1, 1), if forSale then "Robux" else "Robux · Próximamente")
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

-- 4º Pedestal decorativo: Huevo del Arcoíris en base rosa
local function buildRainbowEggDisplay(parent: Instance)
	local model = Instance.new("Model")
	model.Name = "EggShrine_RainbowDisplay"
	-- Extremo derecho del arco del Jardín de los Huevos (visto desde la avenida)
	local rainbowAt = EggConfig.Gardens.Forest.RainbowOffset
	local base = onFloor(world(rainbowAt.X, GROUND + StudFloor.BaseTop, rainbowAt.Y))
	local pinkBase = Color3.fromRGB(242, 48, 128)

	local pedestal, top = buildPedestal(model, base, "Arcoiris")
	local eggCenter = top + Vector3.new(0, EGG_ABOVE_TOP, 0)
	buildEgg(model, eggCenter, {
		Style = "Rainbow",
		Shell = Color3.fromRGB(255, 230, 50),
	})

	local anchor = PartFactory.part(model, "InfoAnchor", {
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(eggCenter + Vector3.new(0, BILLBOARD_ABOVE_EGG, 0)),
		Color = pinkBase,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	anchor.Transparency = 1
	buildFloatingEggTitle(anchor, "Huevo del Arcoíris", Color3.fromRGB(255, 105, 235), "✨ Especial")

	-- Al interactuar, abre el huevo Raro o la tienda
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EggPrompt"
	prompt.ActionText = "¡Eclosionar!"
	prompt.ObjectText = "Huevo del Arcoíris"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("EggId", "AncientEgg")
	prompt.Parent = pedestal

	model.PrimaryPart = pedestal
	model.Parent = parent
end

function EggStandService.start()
	PartFactory.removeExisting(workspace, FOLDER_NAME)
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	-- La plaza gris ahora forma parte del suelo de bloques (StudFloor).
	buildFeaturedGuardianAltar(folder)

	for eggId, egg in EggConfig.Eggs do
		if egg.Enabled ~= false then
			buildShrine(folder, eggId, egg)
		end
	end

	-- El pedestal rosa decorativo solo si ningún huevo de verdad ocupa su sitio (el Clásico).
	local rainbowAt = EggConfig.Gardens.Forest.RainbowOffset
	local taken = false
	for _, egg in EggConfig.Eggs do
		if egg.Enabled ~= false and egg.StandOffset == rainbowAt and (egg.Zone or ZoneConfig.DefaultZone) == EggConfig.Gardens.Forest.Zone then
			taken = true
		end
	end
	if not taken then
		buildRainbowEggDisplay(folder)
	end

	folder.Parent = workspace
end

return EggStandService
