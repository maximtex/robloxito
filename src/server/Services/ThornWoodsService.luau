-- Construye el Bosque de Espinas (Zona 1, gratis), pegado tras el pueblo (pruebas con amigos:
-- "el spawn solo el pueblo y la primera zona de pelea la de al lado"), con el mismo estilo de
-- bloques que el pueblo (StudWorld; la distribución está en StudFloor.Zones.ThornWoods):
-- - Suelo verde en damero, la avenida central y dos caminos de lado a lado, y la plazoleta de
--   la puerta del Valle al fondo (la boca de la Cueva de los Espinillos, a su derecha, la
--   construye CaveDungeon con CaveConfig).
-- - Muros de damero con remate de hierba y el paso de la puerta del Valle.
-- - Árboles de bloques, zarzas con espinas, rocas y setas; un cartel a la llegada.
-- Los bichos (EnemyConfig.Zones.ThornWoods) los pone EnemyService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local StudWorld = require(script.Parent.Parent.Util.StudWorld)

local ThornWoodsService = {}

local ZONE_ID = "ThornWoods"
local MODEL_NAME = "ThornWoods"
local LAYOUT = StudFloor.Zones[ZONE_ID]
local CENTER_2D = ZoneConfig.Zones[ZONE_ID].Center
local ORIGIN = Vector3.new(GeneratorConfig.Position.X + CENTER_2D.X, 0, GeneratorConfig.Position.Z + CENTER_2D.Y)

-- Árboles algo más oscuros que los del pueblo (bosque más cerrado)
local TREE_COLORS = {
	{ Trunk = Color3.fromRGB(150, 92, 46), LeafLight = Color3.fromRGB(96, 186, 30), LeafDark = Color3.fromRGB(70, 150, 22) },
	{ Trunk = Color3.fromRGB(132, 82, 42), LeafLight = Color3.fromRGB(84, 168, 40), LeafDark = Color3.fromRGB(58, 132, 30) },
}
local THORN = Color3.fromRGB(60, 112, 36)
local THORN_TIP = Color3.fromRGB(196, 226, 110)
local ROCK = Color3.fromRGB(138, 140, 150)
local MUSHROOM_CAP = Color3.fromRGB(214, 70, 60)
local MUSHROOM_STEM = Color3.fromRGB(240, 228, 206)

local function world(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- Zarza: mata baja con pinchos de bloques (las de los Espinillos)
local function buildBramble(parent: Instance, pos: Vector3, yaw: number, scale: number)
	local model = Instance.new("Model")
	model.Name = "Zarza"
	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
	StudWorld.allStuds(PartFactory.part(model, "Mata", {
		Size = Vector3.new(4.4, 2.2, 4.4) * scale,
		CFrame = cf * CFrame.new(0, 1.1 * scale, 0),
		Color = THORN,
		Material = Enum.Material.Plastic,
		Solid = true,
	}))
	for index = 0, 5 do
		local angle = math.rad(index * 60 + 15)
		local spike = PartFactory.part(model, "Pincho", {
			Size = Vector3.new(0.5, 1.8, 0.5) * scale,
			CFrame = cf * CFrame.new(math.cos(angle) * 1.8 * scale, 2.4 * scale, math.sin(angle) * 1.8 * scale)
				* CFrame.Angles(math.cos(angle) * 0.5, 0, -math.sin(angle) * 0.5),
			Color = THORN_TIP,
			Material = Enum.Material.Plastic,
			Solid = false,
		})
		spike.CastShadow = false
	end
	model.Parent = parent
end

local function buildRock(parent: Instance, pos: Vector3, yaw: number, scale: number)
	StudWorld.allStuds(PartFactory.part(parent, "Roca", {
		Size = Vector3.new(3.2, 2, 2.6) * scale,
		CFrame = CFrame.new(pos + Vector3.new(0, 1 * scale, 0)) * CFrame.Angles(0, math.rad(yaw), 0),
		Color = ROCK,
		Material = Enum.Material.Slate,
		Solid = true,
	}))
end

local function buildMushroom(parent: Instance, pos: Vector3, scale: number)
	PartFactory.part(parent, "SetaPie", {
		Size = Vector3.new(0.8, 1.6, 0.8) * scale,
		CFrame = CFrame.new(pos + Vector3.new(0, 0.8 * scale, 0)),
		Color = MUSHROOM_STEM,
		Material = Enum.Material.Plastic,
		Solid = false,
	})
	StudWorld.allStuds(PartFactory.part(parent, "SetaSombrero", {
		Size = Vector3.new(2.4, 0.9, 2.4) * scale,
		CFrame = CFrame.new(pos + Vector3.new(0, 1.9 * scale, 0)),
		Color = MUSHROOM_CAP,
		Material = Enum.Material.Plastic,
		Solid = false,
	}))
end

-- Cartel de bienvenida a la derecha de la llegada
local function buildSign(parent: Instance)
	local folder = PartFactory.folder(parent, "Cartel")
	local top = StudWorld.FloorTop
	local base = world(22, top, -126)
	for _, side in { -1, 1 } do
		PartFactory.part(folder, "Poste", {
			Size = Vector3.new(0.8, 6, 0.8),
			CFrame = CFrame.new(base + Vector3.new(side * 3.4, 3, 0)),
			Color = Color3.fromRGB(116, 78, 46),
			Material = Enum.Material.Wood,
			Solid = true,
		})
	end
	local board = PartFactory.part(folder, "Tabla", {
		Size = Vector3.new(8.4, 3, 0.5),
		CFrame = CFrame.new(base + Vector3.new(0, 5, 0)),
		Color = Color3.fromRGB(162, 116, 68),
		Material = Enum.Material.WoodPlanks,
		Solid = true,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- mira a quien llega (hacia -Z, de donde viene)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 244, 214)
	label.TextStrokeTransparency = 0.2
	label.Text = "🌲 " .. ZoneConfig.Zones[ZONE_ID].DisplayName .. "\n🦇 Cueva al fondo, junto a la puerta"
	label.Parent = gui
end

local function buildDecor(parent: Instance)
	local folder = PartFactory.folder(parent, "Decor")
	local decor = StudWorld.newDecor(LAYOUT, ZONE_ID, { { ORIGIN.X + 22, ORIGIN.Z - 126, 8 } })
	local rng = decor.Rng
	-- Árboles junto a los muros (bosque cerrado) y sueltos por las praderas
	decor.wallRow(20, 9, 12, function(pos, yaw)
		StudWorld.buildBlockyTree(folder, pos, yaw, rng:NextNumber(0.95, 1.25), TREE_COLORS[rng:NextInteger(1, #TREE_COLORS)])
	end)
	decor.scatter(22, 10, math.huge, 20, function(pos, yaw)
		StudWorld.buildBlockyTree(folder, pos, yaw, rng:NextNumber(0.85, 1.15), TREE_COLORS[rng:NextInteger(1, #TREE_COLORS)])
	end)
	decor.scatter(26, 3, math.huge, 6, function(pos, yaw)
		buildBramble(folder, pos, yaw, rng:NextNumber(0.8, 1.2))
	end)
	decor.scatter(14, 3, math.huge, 5, function(pos, yaw)
		buildRock(folder, pos, yaw, rng:NextNumber(0.7, 1.3))
	end)
	decor.scatter(18, 2, math.huge, 3, function(pos)
		buildMushroom(folder, pos, rng:NextNumber(0.7, 1.2))
	end)
end

function ThornWoodsService.start()
	PartFactory.removeExisting(workspace, MODEL_NAME)
	StudWorld.fillTerrainBelow(-172, 172, LAYOUT.MinZ, LAYOUT.MaxZ + StudFloor.Wall.Thickness, Enum.Material.Grass)
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	StudWorld.buildFloor(model, LAYOUT)
	StudWorld.buildWalls(model, LAYOUT)
	buildSign(model)
	buildDecor(model)
	model.Parent = workspace
end

return ThornWoodsService
