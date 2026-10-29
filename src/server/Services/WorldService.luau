-- Construye el mapa estilo simulador clásico y simple:
-- - Suelo 100% plano con patrón cuadriculado (damero verde claro / verde oscuro con studs).
-- - Muros perimetrales rectos con patrón cuadriculado marrón y borde superior verde.
-- - Corrales / parcelas con cercas de madera marrón a los lados del pasillo central y
--   medallón circular flotante con el avatar y nombre de cada jugador.
-- - Letrero de "ZONA SEGURA" en el suelo e iluminación de día soleado y cielo azul limpio.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared.Config.WorldConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local ChestConfig = require(Shared.Config.ChestConfig)
local EggConfig = require(Shared.Config.EggConfig)
local AdventureConfig = require(Shared.Config.AdventureConfig)
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)
local VillageConfig = require(Shared.Config.VillageConfig)
local SeasonConfig = require(Shared.Config.SeasonConfig)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local StudWorld = require(script.Parent.Parent.Util.StudWorld)
local ChristmasDecor = require(script.Parent.Parent.Util.ChristmasDecor)
local ChristmasData = require(script.Parent.Parent.Util.ChristmasData)
local ForestCave = require(script.Parent.Parent.Util.ForestCave)
local CaveDungeon = require(script.Parent.Parent.Util.CaveDungeon)
local StudFloor = require(Shared.Util.StudFloor)

local WorldService = {}

local ORIGIN = Vector3.new(GeneratorConfig.Position.X, 0, GeneratorConfig.Position.Z)
local GROUND = GeneratorConfig.Position.Y
local FOREST = StudFloor.Zones.Forest
local FOREST_TREES = 18 -- árboles sueltos por el Bosque (al azar, sin hileras)

-- Colores estilo simulador limpio (inspirado en la referencia)
local GRASS_A = Color3.fromRGB(106, 218, 46)
local PATH_A = Color3.fromRGB(98, 210, 42)
local WALL_TOP = Color3.fromRGB(102, 214, 44)
local FENCE_WOOD = Color3.fromRGB(156, 92, 44)
local FENCE_DARK = Color3.fromRGB(124, 70, 30)

local function world(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- Terreno plano de base (para que cualquier raycast hacia Workspace.Terrain encuentre suelo en GROUND)
local function buildFlatTerrain()
	pcall(function()
		local FILL = GROUND - GeneratorConfig.TerrainFillOffset
		local terrain = workspace.Terrain
		pcall(function()
			terrain:Clear()
		end)
		pcall(function()
			terrain.Decoration = false
		end)
		if WorldConfig.Terrain and WorldConfig.Terrain.MaterialColors then
			for materialName, color in WorldConfig.Terrain.MaterialColors do
				pcall(function()
					terrain:SetMaterialColor((Enum.Material :: any)[materialName], color)
				end)
			end
		end
		pcall(function()
			terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(86, 175, 58))
		end)
		pcall(function()
			terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(86, 175, 58))
		end)

		local size = (WorldConfig.Terrain and WorldConfig.Terrain.Size) or 620
		local thickness = (WorldConfig.Terrain and WorldConfig.Terrain.Thickness) or 8
		-- Pradera fuera de los muros (se ve por encima de ellos), no tierra oscura
		local groundMaterial = (Enum.Material :: any)[(WorldConfig.Terrain and WorldConfig.Terrain.GroundMaterial) or "Grass"]
		pcall(function()
			terrain:FillBlock(
				CFrame.new(world(0, FILL - thickness / 2, 0)),
				Vector3.new(size, thickness, size),
				groundMaterial
			)
		end)
	end)
end

local function allStuds(part: BasePart): BasePart
	part.Material = Enum.Material.Plastic
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Studs
	part.FrontSurface = Enum.SurfaceType.Studs
	part.BackSurface = Enum.SurfaceType.Studs
	part.LeftSurface = Enum.SurfaceType.Studs
	part.RightSurface = Enum.SurfaceType.Studs
	return part
end

-- Suelo del Bosque (StudFloor.Zones.Forest): damero verde con los cuadritos del diseño,
-- caminos y plazas con borde (StudWorld.buildFloor) y el spawn sobre la plaza del pueblo.
local function buildStudFloor(parent: Instance)
	StudWorld.buildFloor(parent, FOREST)

	-- SpawnLocation centrado sobre el camino sur
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if not spawn then
		spawn = Instance.new("SpawnLocation")
		spawn.Name = "SpawnLocation"
		spawn.Size = Vector3.new(6, 0.4, 6)
		spawn.Anchored = true
		spawn.CanCollide = true
		spawn.Transparency = 1
		spawn.Parent = workspace
	end
	local spawnY = GROUND + 0.5 + StudFloor.raiseAt(0, 18) -- en la plaza, que sobresale del damero
	spawn.CFrame = CFrame.lookAt(Vector3.new(0, spawnY, 18), Vector3.new(0, spawnY, 0))
end

local function buildFenceSegment(parent: Instance, fromPos: Vector3, toPos: Vector3)
	local diff = toPos - fromPos
	local length = diff.Magnitude
	local bays = math.max(1, math.floor(length / 7))
	local bayLen = length / bays
	local dir = diff.Unit

	for i = 0, bays do
		local postPos = fromPos + dir * (i * bayLen)
		PartFactory.part(parent, "Post", {
			Size = Vector3.new(0.65, 3.6, 0.65),
			CFrame = CFrame.new(postPos + Vector3.new(0, 1.8, 0)),
			Color = FENCE_DARK,
			Material = Enum.Material.Wood,
			Solid = true,
		})
		if i < bays then
			local segStart = postPos
			local segEnd = fromPos + dir * ((i + 1) * bayLen)
			local segMid = (segStart + segEnd) / 2
			local segCF = CFrame.lookAt(segMid, segEnd)
			-- Dos travesaños horizontales
			for _, h in { 1.0, 2.7 } do
				PartFactory.part(parent, "Rail", {
					Size = Vector3.new(0.3, 0.32, bayLen),
					CFrame = segCF * CFrame.new(0, h, 0),
					Color = FENCE_WOOD,
					Material = Enum.Material.Wood,
					Solid = true,
				})
			end
			-- Diagonal de granja
			PartFactory.segment(
				parent,
				"Diag",
				segStart + Vector3.new(0, 1.05, 0),
				segEnd + Vector3.new(0, 2.65, 0),
				0.24,
				FENCE_WOOD,
				Enum.Material.Wood,
				false
			)
		end
	end
end

-- Medallón circular con la foto de avatar del jugador y su nombre debajo (estilo simulador)
local function createPlotBadge(parent: Instance, position: Vector3, slotIndex: number, defaultName: string)
	local anchor = PartFactory.part(parent, "BadgeAnchor" .. slotIndex, {
		Size = Vector3.one * 0.5,
		CFrame = CFrame.new(position),
		Color = GRASS_A,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	anchor.Transparency = 1

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PlotBadge"
	billboard.Size = UDim2.new(9, 0, 10.5, 0)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 180
	billboard.Adornee = anchor

	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.AnchorPoint = Vector2.new(0.5, 0)
	circle.Position = UDim2.fromScale(0.5, 0.04)
	circle.Size = UDim2.fromScale(0.68, 0.68)
	circle.BackgroundColor3 = Color3.fromRGB(58, 58, 64)
	circle.BackgroundTransparency = 0.1
	circle.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = circle

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 24)
	stroke.Thickness = 4
	stroke.Parent = circle

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.AnchorPoint = Vector2.new(0.5, 0.5)
	avatar.Position = UDim2.fromScale(0.5, 0.5)
	avatar.Size = UDim2.fromScale(0.92, 0.92)
	avatar.BackgroundTransparency = 1
	avatar.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
	avatar.Parent = circle

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(0.5, 0)
	avatarCorner.Parent = avatar

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "PlayerName"
	nameLabel.AnchorPoint = Vector2.new(0.5, 1)
	nameLabel.Position = UDim2.fromScale(0.5, 0.98)
	nameLabel.Size = UDim2.fromScale(1, 0.24)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 24)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.Text = defaultName
	nameLabel.Parent = billboard

	billboard.Parent = anchor

	local function refreshPlayers()
		local list = Players:GetPlayers()
		local p = list[slotIndex]
		if p then
			nameLabel.Text = p.DisplayName or p.Name
			task.spawn(function()
				local ok, content = pcall(function()
					return Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size180x180)
				end)
				if ok and content then
					avatar.Image = content
				end
			end)
		else
			nameLabel.Text = defaultName
		end
	end

	Players.PlayerAdded:Connect(refreshPlayers)
	Players.PlayerRemoving:Connect(refreshPlayers)
	refreshPlayers()
end

-- Corrales de madera (parcelas a ambos lados del camino de spawn)
local function buildPlayerCorrals(parent: Instance)
	local folder = PartFactory.folder(parent, "PlayerPlots")
	local plots = {
		{ X = -22, Z = 56, W = 26, D = 24, Side = "Left", Label = "Tu Parcela" },
		{ X = 22, Z = 56, W = 26, D = 24, Side = "Right", Label = "Parcela 2" },
		{ X = -22, Z = 84, W = 26, D = 24, Side = "Left", Label = "Parcela 3" },
		{ X = 22, Z = 84, W = 26, D = 24, Side = "Right", Label = "Parcela 4" },
	}

	for index, spec in plots do
		local plotModel = Instance.new("Model")
		plotModel.Name = "Plot" .. index
		local x0 = spec.X - spec.W / 2
		local x1 = spec.X + spec.W / 2
		local z0 = spec.Z - spec.D / 2
		local z1 = spec.Z + spec.D / 2

		local nw = world(x0, GROUND, z0)
		local ne = world(x1, GROUND, z0)
		local sw = world(x0, GROUND, z1)
		local se = world(x1, GROUND, z1)

		-- Norte y Sur completos
		buildFenceSegment(plotModel, nw, ne)
		buildFenceSegment(plotModel, sw, se)

		-- Lado exterior cerrado, lado interior hacia el pasillo con puerta abierta en el medio
		if spec.Side == "Left" then
			buildFenceSegment(plotModel, nw, sw)
			buildFenceSegment(plotModel, ne, world(x1, GROUND, spec.Z - 4.5))
			buildFenceSegment(plotModel, world(x1, GROUND, spec.Z + 4.5), se)
		else
			buildFenceSegment(plotModel, ne, se)
			buildFenceSegment(plotModel, nw, world(x0, GROUND, spec.Z - 4.5))
			buildFenceSegment(plotModel, world(x0, GROUND, spec.Z + 4.5), sw)
		end

		createPlotBadge(plotModel, world(spec.X, GROUND + 7, spec.Z), index, spec.Label)
		plotModel.Parent = folder
	end
end

-- Arroyo de agua azul con rocas grises y nenúfares junto a la puerta sur (Z = 148)
local function buildWaterBorder(parent: Instance)
	local folder = PartFactory.folder(parent, "RiverBorder")
	local rockColor = Color3.fromRGB(122, 128, 154)
	local rockDark = Color3.fromRGB(98, 104, 130)
	local waterColor = Color3.fromRGB(58, 178, 250)
	local lilyColor = Color3.fromRGB(78, 198, 44)

	local sideW = 66 -- de 14 a 80
	for _, side in { -1, 1 } do
		local centerX = side * (14 + sideW / 2)
		local water = PartFactory.part(folder, "StreamWater", {
			Size = Vector3.new(sideW, 0.28, 12),
			CFrame = CFrame.new(world(centerX, GROUND + 0.08, 148)),
			Color = waterColor,
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
		water.Reflectance = 0.15

		-- Rocas grises escalonadas a ambos lados del arroyo
		for i = 0, 10 do
			local rx = (side * 17) + side * (i * 5.8)
			for _, rz in { 141.5, 154.5 } do
				local h = 1.4 + ((i * 3) % 3) * 0.75
				local rock = PartFactory.part(folder, "RiverRock", {
					Size = Vector3.new(5.2, h, 4.4),
					CFrame = CFrame.new(world(rx, GROUND + h / 2, rz)),
					Color = if i % 2 == 0 then rockColor else rockDark,
					Material = Enum.Material.SmoothPlastic,
					Solid = true,
				})
				allStuds(rock)
			end
		end

		-- Nenúfares verdes
		for _, lx in { side * 28, side * 48, side * 68 } do
			PartFactory.verticalCylinder(folder, "LilyPad", world(lx, GROUND + 0.24, 148), 0.1, 2.8, lilyColor, Enum.Material.SmoothPlastic, false)
		end
	end
end

-- Detalles decorativos del mapa (capturas 1, 2, 3 y 4):
-- Espantapájaros con cabeza de calabaza brillante, calabazas talladas, setas, matitas de pasto y flores
local function buildForestDetails(parent: Instance)
	local folder = PartFactory.folder(parent, "MapDetails")

	-- Helper: Calabaza luminosa (Jack-o'-lantern)
	local function buildGlowingPumpkin(pos: Vector3, scale: number, yawDeg: number)
		local m = Instance.new("Model")
		m.Name = "GlowingPumpkin"
		local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
		local r = 2.4 * scale

		PartFactory.ball(m, "PumpkinBody", (cf * CFrame.new(0, r * 0.44, 0)).Position, r, Color3.fromRGB(252, 118, 18), Enum.Material.SmoothPlastic, false)
		PartFactory.ball(m, "InnerGlow", (cf * CFrame.new(0, r * 0.44, -r * 0.12)).Position, r * 0.86, Color3.fromRGB(255, 224, 48), Enum.Material.Neon, false)

		-- Ojos y sonrisa luminosos amarillos
		for _, sx in { -0.22, 0.22 } do
			PartFactory.part(m, "EyeGlow", {
				Size = Vector3.new(0.28 * r, 0.26 * r, 0.18 * r),
				CFrame = cf * CFrame.new(sx * r, r * 0.56, -r * 0.44) * CFrame.Angles(0, 0, math.rad(sx * 24)),
				Color = Color3.fromRGB(255, 238, 60),
				Material = Enum.Material.Neon,
				Solid = false,
			})
		end
		PartFactory.part(m, "MouthGlow", {
			Size = Vector3.new(0.58 * r, 0.18 * r, 0.18 * r),
			CFrame = cf * CFrame.new(0, r * 0.30, -r * 0.45),
			Color = Color3.fromRGB(255, 234, 52),
			Material = Enum.Material.Neon,
			Solid = false,
		})
		-- Tallo verde curvado
		PartFactory.part(m, "Stem", {
			Size = Vector3.new(0.22 * r, 0.42 * r, 0.22 * r),
			CFrame = cf * CFrame.new(0, r * 0.92, 0) * CFrame.Angles(math.rad(16), 0, math.rad(12)),
			Color = Color3.fromRGB(68, 124, 38),
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
		m.Parent = folder
	end

	-- Helper: Grupo de calabazas pequeñas + hojas de otoño (captura 1 y 2)
	local function buildPumpkinPatch(pos: Vector3, yawDeg: number)
		local m = Instance.new("Model")
		m.Name = "PumpkinPatch"
		local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
		buildGlowingPumpkin((cf * CFrame.new(0, 0, 0)).Position, 0.9, yawDeg)
		PartFactory.ball(m, "WhiteGourd", (cf * CFrame.new(-1.4, 0.9, 1.1)).Position, 1.6, Color3.fromRGB(244, 228, 214), Enum.Material.SmoothPlastic, false)
		PartFactory.ball(m, "MiniPumpkin", (cf * CFrame.new(1.5, 0.65, 0.8)).Position, 1.2, Color3.fromRGB(255, 140, 28), Enum.Material.SmoothPlastic, false)
		-- Hojas de otoño rojas y amarillas en el suelo
		for i, leafCol in {
			Color3.fromRGB(232, 54, 36),
			Color3.fromRGB(250, 178, 32),
			Color3.fromRGB(110, 198, 38),
			Color3.fromRGB(240, 96, 28),
		} do
			local angle = math.rad(i * 90 + 25)
			PartFactory.part(m, "Leaf" .. i, {
				Size = Vector3.new(0.9, 0.12, 0.6),
				CFrame = cf * CFrame.new(math.cos(angle) * 2.1, 0.08, math.sin(angle) * 2.1) * CFrame.Angles(0, angle, 0),
				Color = leafCol,
				Material = Enum.Material.SmoothPlastic,
				Solid = false,
			})
		end
		m.Parent = folder
	end

	-- Helper: Espantapájaros con cabeza de calabaza luminosa y sombrero (como en la captura 1)
	local function buildScarecrow(pos: Vector3, yawDeg: number)
		local m = Instance.new("Model")
		m.Name = "Scarecrow"
		local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)

		-- Base morada de roca + calabaza pequeña a los pies
		PartFactory.part(m, "BaseStone", {
			Size = Vector3.new(4.2, 0.45, 3.6),
			CFrame = cf * CFrame.new(0, 0.22, 0),
			Color = Color3.fromRGB(116, 68, 128),
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
		PartFactory.ball(m, "FootPumpkin", (cf * CFrame.new(1.3, 0.75, -0.8)).Position, 1.3, Color3.fromRGB(252, 124, 20), Enum.Material.SmoothPlastic, false)

		-- Poste de madera y brazos extendidos
		PartFactory.part(m, "WoodPole", {
			Size = Vector3.new(0.65, 6.6, 0.65),
			CFrame = cf * CFrame.new(0, 3.3, 0),
			Color = Color3.fromRGB(142, 88, 44),
			Material = Enum.Material.Wood,
			Solid = true,
		})
		PartFactory.part(m, "CrossArms", {
			Size = Vector3.new(6.2, 0.55, 0.55),
			CFrame = cf * CFrame.new(0, 4.9, 0) * CFrame.Angles(0, 0, math.rad(6)),
			Color = Color3.fromRGB(142, 88, 44),
			Material = Enum.Material.Wood,
			Solid = false,
		})

		-- Túnica naranja y mangas
		PartFactory.part(m, "Tunic", {
			Size = Vector3.new(2.5, 3.2, 1.6),
			CFrame = cf * CFrame.new(0, 3.9, 0),
			Color = Color3.fromRGB(238, 134, 48),
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
		PartFactory.part(m, "Sleeves", {
			Size = Vector3.new(4.8, 0.95, 1.1),
			CFrame = cf * CFrame.new(0, 4.85, 0) * CFrame.Angles(0, 0, math.rad(6)),
			Color = Color3.fromRGB(238, 134, 48),
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
		-- Cinturón de cuerda blanca
		PartFactory.part(m, "RopeBelt", {
			Size = Vector3.new(2.65, 0.32, 1.75),
			CFrame = cf * CFrame.new(0, 3.35, 0),
			Color = Color3.fromRGB(245, 232, 212),
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})

		-- Cabeza de calabaza luminosa + sombrero de paja
		buildGlowingPumpkin((cf * CFrame.new(0, 5.4, 0)).Position, 1.15, yawDeg)
		PartFactory.part(m, "HatBrim", {
			Size = Vector3.new(4.2, 0.35, 4.2),
			CFrame = cf * CFrame.new(0, 7.65, 0) * CFrame.Angles(math.rad(-8), 0, math.rad(5)),
			Color = Color3.fromRGB(244, 178, 52),
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
		PartFactory.part(m, "HatBand", {
			Size = Vector3.new(2.45, 0.38, 2.45),
			CFrame = cf * CFrame.new(0, 7.95, 0) * CFrame.Angles(math.rad(-8), 0, math.rad(5)),
			Color = Color3.fromRGB(142, 62, 168),
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
		PartFactory.part(m, "HatTop", {
			Size = Vector3.new(2.1, 1.35, 2.1),
			CFrame = cf * CFrame.new(0, 8.65, 0) * CFrame.Angles(math.rad(-8), 0, math.rad(5)),
			Color = Color3.fromRGB(244, 178, 52),
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})

		m.Parent = folder
	end

	-- Helper: Seta pequeña (roja o azul con pintas, como en las capturas 1 y 2)
	local function buildMushroom(pos: Vector3, isBlue: boolean)
		local m = Instance.new("Model")
		m.Name = "Mushroom"
		PartFactory.verticalCylinder(m, "Stem", pos + Vector3.new(0, 0.4, 0), 0.8, 0.55, Color3.fromRGB(238, 224, 198), Enum.Material.SmoothPlastic, false)
		local capColor = if isBlue then Color3.fromRGB(36, 152, 255) else Color3.fromRGB(248, 42, 42)
		local spotColor = if isBlue then Color3.fromRGB(132, 226, 255) else Color3.fromRGB(252, 248, 238)
		PartFactory.part(m, "Cap", {
			Size = Vector3.new(1.5, 0.65, 1.5),
			CFrame = CFrame.new(pos + Vector3.new(0, 0.92, 0)),
			Color = capColor,
			Material = Enum.Material.SmoothPlastic,
			Solid = false,
		})
		for _, offset in { Vector3.new(0.35, 1.26, 0.25), Vector3.new(-0.35, 1.26, -0.25) } do
			PartFactory.part(m, "Spot", {
				Size = Vector3.new(0.36, 0.08, 0.36),
				CFrame = CFrame.new(pos + offset),
				Color = spotColor,
				Material = Enum.Material.SmoothPlastic,
				Solid = false,
			})
		end
		m.Parent = folder
	end

	-- Helper: Matita de pasto verde oscuro y florecitas rosas/rojas (capturas 1, 3 y 4)
	local function buildGrassTuft(pos: Vector3, withFlowers: boolean)
		local m = Instance.new("Model")
		m.Name = "GrassTuft"
		local bladeColor = Color3.fromRGB(38, 148, 36)
		for i = -1, 1 do
			PartFactory.part(m, "Blade" .. i, {
				Size = Vector3.new(0.28, 1.25, 0.28),
				CFrame = CFrame.new(pos + Vector3.new(i * 0.28, 0.58, 0)) * CFrame.Angles(0, 0, math.rad(-i * 22)),
				Color = bladeColor,
				Material = Enum.Material.SmoothPlastic,
				Solid = false,
			})
		end
		if withFlowers then
			for _, fOff in { Vector3.new(-0.32, 1.22, 0.12), Vector3.new(0.28, 1.18, -0.14) } do
				PartFactory.ball(m, "Flower", pos + fOff, 0.42, Color3.fromRGB(255, 68, 148), Enum.Material.SmoothPlastic, false)
			end
		end
		m.Parent = folder
	end

	-- Reparto con semilla fija sobre el damero verde: nada encima de los caminos, los enemigos,
	-- el Círculo del Guardián, el Jardín de los Huevos, las tablas de clasificación, los cofres
	-- escondidos ni lo de las aventuras (posiciones relativas al cristal).
	local keepOut: { { number } } = {}
	for _, chest in ChestConfig.Chests do
		table.insert(keepOut, { ORIGIN.X + chest.Position.X, ORIGIN.Z + chest.Position.Y, 8 })
	end
	local garden = EggConfig.Gardens.Forest
	table.insert(keepOut, { ORIGIN.X + garden.Center.X, ORIGIN.Z + garden.Center.Y, garden.Radius + 4 })
	-- Tablas de clasificación (con sitio delante para leerlas)
	for _, board in LeaderboardConfig.Boards do
		table.insert(keepOut, { ORIGIN.X + board.Position.X, ORIGIN.Z + board.Position.Y, LeaderboardConfig.Footprint + 4 })
	end
	-- Cofre «RECLAMAR» con su círculo y la Máquina de Evolución (en coordenadas del mundo)
	local claimChest = VillageConfig.ClaimChest.Position
	table.insert(keepOut, { claimChest.X, claimChest.Y, 8 })
	local machine = VillageConfig.EvolutionMachine.Position
	table.insert(keepOut, { machine.X, machine.Y, 10 })
	-- Adornos de Navidad (en coordenadas del mundo)
	if SeasonConfig.Christmas then
		for _, item in SeasonConfig.ForestDecor do
			table.insert(keepOut, { item.Position.X, item.Position.Y, (ChristmasData.Radius :: any)[item.Model] or 6 })
		end
	end
	-- Personajes de las aventuras y sus objetos perdidos
	for _, group in { AdventureConfig.Npcs, AdventureConfig.Items } do
		for _, entry in group do
			if entry.Zone == "Forest" then
				table.insert(keepOut, { ORIGIN.X + entry.Position.X, ORIGIN.Z + entry.Position.Y, 6 })
			end
		end
	end
	-- La decoración se reparte como antes de existir el camino de la cueva (misma semilla, mismos
	-- sitios) y luego se quita lo que haya quedado encima de ese camino.
	local road = FOREST.Cave and FOREST.Cave.Road
	local decorLayout = FOREST
	if road then
		decorLayout = table.clone(FOREST)
		decorLayout.Paths = {}
		for _, path in FOREST.Paths do
			if path ~= road and not (path[1] == road[1] and path[2] == road[2] and path[3] == road[3] and path[4] == road[4]) then
				table.insert(decorLayout.Paths, path)
			end
		end
	end
	local decor = StudWorld.newDecor(decorLayout, "Forest", keepOut)
	local rng = decor.Rng

	-- Pocos árboles sueltos al azar por las praderas, sin hileras (en Navidad, el árbol navideño
	-- del diseño); calabazas y espantapájaros junto a los caminos, setas y matas
	decor.scatter(FOREST_TREES, 9, math.huge, 26, function(pos, yaw)
		if SeasonConfig.Christmas then
			ChristmasDecor.tree(folder, pos, yaw, rng:NextNumber(0.85, 1.1))
		else
			StudWorld.buildBlockyTree(folder, pos, yaw, rng:NextNumber(0.9, 1.2))
		end
	end)
	decor.scatter(4, 3, 9, 14, buildScarecrow)
	decor.scatter(6, 2, 10, 7, buildPumpkinPatch)
	decor.scatter(10, 2, 12, 6, function(pos, yaw)
		buildGlowingPumpkin(pos, rng:NextNumber(0.9, 1.2), yaw)
	end)
	decor.scatter(16, 2, math.huge, 4, function(pos)
		buildMushroom(pos, rng:NextNumber() < 0.5)
	end)
	decor.scatter(50, 1.5, math.huge, 3, function(pos)
		buildGrassTuft(pos, rng:NextNumber() < 0.45)
	end)

	-- Fuera lo que pise el camino de la cueva (con 3 studs de margen)
	if road then
		for _, child in folder:GetChildren() do
			local position = if child:IsA("Model") then child:GetPivot().Position elseif child:IsA("BasePart") then child.Position else nil
			if position and position.X > road[1] - 3 and position.X < road[2] + 3 and position.Z > road[3] - 3 and position.Z < road[4] + 3 then
				child:Destroy()
			end
		end
	end
end

-- Luz del juego desde WorldConfig.Lighting: la misma que DayNightController usa de día, así
-- el servidor y el ciclo de día y noche no se contradicen.
local function applyLighting()
	local settings = WorldConfig.Lighting
	if settings.Enabled == false then
		return
	end
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2
	Lighting.ClockTime = settings.ClockTime
	Lighting.Brightness = settings.Brightness
	Lighting.Ambient = settings.Ambient
	Lighting.OutdoorAmbient = settings.OutdoorAmbient
	Lighting.EnvironmentDiffuseScale = settings.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = settings.EnvironmentSpecularScale

	-- El efecto de esa clase que ya haya (o uno nuevo con su nombre), con los valores de la tabla
	local function effect(className: string, values: { [string]: any })
		local instance = Lighting:FindFirstChildOfClass(className)
		if not instance then
			instance = Instance.new(className)
			instance.Name = values.Name
			instance.Parent = Lighting
		end
		for key, value in values do
			if key ~= "Name" then
				(instance :: any)[key] = value
			end
		end
	end

	-- Atmósfera con un poco de bruma al horizonte
	effect("Atmosphere", settings.Atmosphere)

	-- Cielo despejado y luminoso
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Name = "RebirthSky"
		sky.CelestialBodiesShown = true
		sky.Parent = Lighting
	end

	-- Corrección de color (neutra: los colores tal cual), bloom suave para neones y gemas y
	-- rayos de sol
	effect("ColorCorrectionEffect", settings.Effects.ColorCorrection)
	effect("BloomEffect", settings.Effects.Bloom)
	effect("SunRaysEffect", settings.Effects.SunRays)
end

function WorldService.start()
	print("[WorldService] Iniciando construcción del mundo...")
	PartFactory.removeExisting(workspace, WorldConfig.ModelName)

	-- Limpiar cualquier modelo, carpeta o mesh huérfano que haya quedado guardado en el .rbxl
	-- de Studio (WorldService es el primer servicio de mundo en arrancar: aquí en Workspace
	-- solo deben quedar Terrain, Camera, Baseplate y personajes).
	pcall(function()
		local chars = {}
		for _, p in Players:GetPlayers() do
			if p.Character then
				chars[p.Character] = true
			end
		end
		for _, child in workspace:GetChildren() do
			if child:IsA("Terrain") or child:IsA("Camera") or chars[child] or child.Name == "Baseplate" then
				continue
			end
			if child:IsA("Model") or child:IsA("BasePart") or child:IsA("Folder") or child:IsA("BaseScript") then
				child:Destroy()
			end
		end
	end)

	buildFlatTerrain()

	local model = Instance.new("Model")
	model.Name = WorldConfig.ModelName

	-- Suelo con caminos, muros de damero y decoración, en ese orden (la decoración evita los caminos)
	for _, step in {
		{ "buildStudFloor", buildStudFloor },
		{
			"buildCheckerWalls",
			function(parent)
				StudWorld.buildWalls(parent, FOREST)
			end,
		},
		{ "buildForestDetails", buildForestDetails },
		{
			"buildForestCave",
			function(parent)
				ForestCave.build(parent, FOREST)
			end,
		},
		{
			-- La cueva por dentro (CaveConfig), lejos del mapa: se llega por la boca (CaveService)
			"buildCaveDungeon",
			function(parent)
				CaveDungeon.build(parent)
			end,
		},
		{
			"buildChristmasDecor",
			function(parent)
				if SeasonConfig.Christmas then
					ChristmasDecor.forest(parent)
				end
			end,
		},
	} do
		local ok, err = pcall(step[2], model)
		if not ok then
			warn("[WorldService ERROR en " .. step[1] .. "]:", err)
		end
	end

	model.Parent = workspace
	pcall(applyLighting)
	print("[WorldService] Construcción del mundo completada con éxito.")
end

return WorldService
