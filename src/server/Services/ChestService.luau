-- Cofres escondidos del Bosque (ChestConfig). Cada cofre se abre con su aviso de
-- proximidad: lo valida el servidor (perfil cargado, distancia y espera de ESE jugador) y
-- concede 💰 (minutos del 💰/min de su mejor zona, con mínimo) y a veces una bendición.
-- - La espera se marca antes del premio y se guarda en seguida (Rewards.Chests): no se
--   cobra dos veces aunque lleguen dos avisos seguidos o se cierre el servidor.
-- - El cliente (ChestController) recibe las esperas (ChestState) y pinta cada cofre
--   abierto o cerrado solo para ese jugador; el aviso es el mismo para todos.
-- - Los cofres se apoyan en el suelo cuando WildsService ha terminado (cascada, ruinas...).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ChestConfig = require(Shared.Config.ChestConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local AdventureService = require(script.Parent.AdventureService)
local WildsService = require(script.Parent.WildsService)
local RewardLogic = require(script.Parent.Parent.Util.RewardLogic)
local ZoneLogic = require(script.Parent.Parent.Util.ZoneLogic)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local StudProps = require(script.Parent.Parent.Util.StudProps)

local Codes = Constants.PurchaseCodes
local Colors = ChestConfig.Colors
local GROUND = GeneratorConfig.Position.Y
local ORIGIN = Vector3.new(GeneratorConfig.Position.X, 0, GeneratorConfig.Position.Z)
local MODEL_NAME = "Chests"

local ChestService = {}

local openLimiter = RateLimiter.new(0.5, 5, 10)
local requestLimiter = RateLimiter.new(0.5, 5, 10)
local stateRemote: any
local resultRemote: any
local chestParts: { [string]: BasePart } = {}

local CHEST_IDS = {}
for _, chest in ChestConfig.Chests do
	table.insert(CHEST_IDS, chest.Id)
end

-- Hora del servidor (las pruebas la cambian).
local clock = {
	now = function(): number
		return os.time()
	end,
}

function ChestService.setClock(now: () -> number)
	clock.now = now
end

local function readyProfile(player: Player): PlayerDataService.Profile?
	local profile = PlayerDataService.get(player)
	if profile and PlayerDataService.isPetDataReady(profile) then
		return profile
	end
	return nil
end

local function push(player: Player)
	local profile = readyProfile(player)
	if not profile or not stateRemote then
		return
	end
	stateRemote:FireClient(player, RewardLogic.chestState(profile.PetData.Rewards, CHEST_IDS, clock.now(), ChestConfig.Cooldown), clock.now())
end
ChestService.push = push

-- Cofres que el jugador tiene abiertos (en espera) ahora mismo.
local function openedCount(profile: PlayerDataService.Profile): number
	local count = 0
	for _ in RewardLogic.chestState(profile.PetData.Rewards, CHEST_IDS, clock.now(), ChestConfig.Cooldown) do
		count += 1
	end
	return count
end

-- Abre un cofre para un jugador. `position` = dónde está el cofre en el mundo (nil en las
-- pruebas sin mundo: no se comprueba la distancia).
function ChestService.open(player: Player, chestId: any, position: Vector3?): (string, any)
	local chest = ChestConfig.get(chestId)
	if not chest then
		return Codes.InvalidRequest, nil
	end
	local profile = readyProfile(player)
	if not profile then
		return Codes.NotReady, nil
	end
	if position then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) or (root.Position - position).Magnitude > ChestConfig.OpenDistance then
			return Codes.TooFar, nil
		end
	end
	local code, readyAt = RewardLogic.openChest(profile.PetData.Rewards, chest.Id, clock.now(), ChestConfig.Cooldown)
	if code ~= "Success" then
		return Codes[code] or Codes.InvalidRequest, { ReadyAt = readyAt }
	end
	local detail: any = { ReadyAt = readyAt }
	local reward = chest.Reward
	if reward.Money then
		local money = RewardLogic.moneyAmount(reward.Money, ZoneLogic.bestMoneyPerMinute(profile, ZoneConfig))
		if money > 0 then
			profile.Money += money
			detail.Money = money
		end
	end
	if reward.Blessings then
		local added = AdventureService.grantBlessings(player, reward.Blessings)
		if next(added) ~= nil then
			detail.Blessings = added
		end
	end
	detail.Opened = openedCount(profile)
	detail.Total = #CHEST_IDS
	PlayerDataService.replicate(player)
	PlayerDataService.markDirty(player)
	PlayerDataService.saveNow(player)
	return Codes.Success, detail
end

-- Cofres en el mundo ------------------------------------------------------------------------

local function rayDown(from: Vector3, length: number, filter: { Instance }): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.IgnoreWater = true
	params.FilterDescendantsInstances = filter
	return Workspace:Raycast(from, Vector3.new(0, -length, 0), params)
end

-- Suelo del cofre: el terreno y, justo encima, una repisa o losa de la naturaleza si la
-- hay (no el tejadillo de roca de la cascada ni los dinteles de las ruinas).
local function groundAt(x: number, z: number): number
	local terrainHit = rayDown(ORIGIN + Vector3.new(x, GROUND + 80, z), 160, { Workspace.Terrain })
	local y = if terrainHit then terrainHit.Position.Y else GROUND
	local wilds = Workspace:FindFirstChild("Wilds")
	if wilds then
		local floorHit = rayDown(ORIGIN + Vector3.new(x, y + 4, z), 6, { wilds })
		if floorHit then
			y = math.max(y, floorHit.Position.Y)
		end
	end
	return y
end

local function piece(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, solid: boolean?): Part
	return PartFactory.part(parent, name, { Size = size, CFrame = cframe, Color = color, Material = material, Solid = solid == true })
end

local function buildChest(parent: Instance, chest: any)
	local model = Instance.new("Model")
	model.Name = "Chest_" .. chest.Id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- llega entero al cliente
	model:SetAttribute("ChestId", chest.Id)
	local x, z = chest.Position.X, chest.Position.Y
	local base = CFrame.new(ORIGIN + Vector3.new(x, groundAt(x, z), z)) * CFrame.Angles(0, math.rad(chest.Yaw or 0), 0)

	-- Paleta estilo tesoro simulador vibrante
	local C_WOOD = Color3.fromRGB(152, 88, 42)
	local C_DARKWOOD = Color3.fromRGB(118, 64, 28)
	local C_GOLD = Color3.fromRGB(255, 206, 38)
	local C_GOLDBRIGHT = Color3.fromRGB(255, 228, 90)
	local C_GEM = Color3.fromRGB(36, 210, 255)

	-- 1. Base del cofre (cuerpo principal)
	local body = piece(model, "Body", Vector3.new(3.2, 1.8, 2.2), base * CFrame.new(0, 0.9, 0), C_WOOD, Enum.Material.WoodPlanks, true)

	-- Zócalo dorado inferior
	piece(model, "BaseRim", Vector3.new(3.35, 0.25, 2.35), base * CFrame.new(0, 0.125, 0), C_GOLD, Enum.Material.SmoothPlastic)

	-- Esquineras doradas verticales
	for _, sx in { -1.5, 1.5 } do
		for _, sz in { -1.0, 1.0 } do
			piece(model, "Corner", Vector3.new(0.3, 1.82, 0.3), base * CFrame.new(sx, 0.9, sz), C_GOLD, Enum.Material.SmoothPlastic)
		end
	end

	-- Flejes metálicos dorados en el cuerpo
	for _, sx in { -0.75, 0.75 } do
		piece(model, "Band", Vector3.new(0.24, 1.84, 2.26), base * CFrame.new(sx, 0.9, 0), C_GOLD, Enum.Material.SmoothPlastic)
	end

	-- Cerradura dorada central con gema brillante en el frontal (+Z local)
	piece(model, "LockPlate", Vector3.new(0.7, 0.7, 0.12), base * CFrame.new(0, 1.3, 1.15), C_GOLDBRIGHT, Enum.Material.SmoothPlastic)
	local gem = piece(model, "LockGem", Vector3.new(0.32, 0.32, 0.16), base * CFrame.new(0, 1.3, 1.18), C_GEM, Enum.Material.Neon)

	-- 2. Tapa abovedada con bisagra atrás (-Z local)
	local hinge = base * CFrame.new(0, 1.8, -1.1)

	-- Capas escalonadas para dar la curvatura del cofre clásico
	local lidBase = piece(model, "LidBase", Vector3.new(3.35, 0.45, 2.35), hinge * CFrame.new(0, 0.225, 1.175), C_DARKWOOD, Enum.Material.WoodPlanks, true)
	lidBase:SetAttribute("Hinge", hinge)

	local lidMid = piece(model, "LidMid", Vector3.new(3.1, 0.38, 1.95), hinge * CFrame.new(0, 0.55, 1.175), C_DARKWOOD, Enum.Material.WoodPlanks, true)
	lidMid:SetAttribute("Hinge", hinge)

	local lidTop = piece(model, "LidTop", Vector3.new(2.7, 0.32, 1.45), hinge * CFrame.new(0, 0.82, 1.175), C_DARKWOOD, Enum.Material.WoodPlanks, true)
	lidTop:SetAttribute("Hinge", hinge)

	-- Flejes dorados de la tapa
	for _, sx in { -0.75, 0.75 } do
		local lBand1 = piece(model, "LidBand1", Vector3.new(0.26, 0.48, 2.38), hinge * CFrame.new(sx, 0.225, 1.175), C_GOLD, Enum.Material.SmoothPlastic)
		lBand1:SetAttribute("Hinge", hinge)
		local lBand2 = piece(model, "LidBand2", Vector3.new(0.26, 0.42, 1.98), hinge * CFrame.new(sx, 0.55, 1.175), C_GOLD, Enum.Material.SmoothPlastic)
		lBand2:SetAttribute("Hinge", hinge)
		local lBand3 = piece(model, "LidBand3", Vector3.new(0.26, 0.36, 1.48), hinge * CFrame.new(sx, 0.82, 1.175), C_GOLD, Enum.Material.SmoothPlastic)
		lBand3:SetAttribute("Hinge", hinge)
	end

	-- Pestillo que cae sobre la cerradura
	local latch = piece(model, "LidLatch", Vector3.new(0.48, 0.55, 0.16), hinge * CFrame.new(0, 0.05, 2.38), C_GOLDBRIGHT, Enum.Material.SmoothPlastic)
	latch:SetAttribute("Hinge", hinge)

	-- Asa dorada superior
	local handle = piece(model, "LidHandle", Vector3.new(0.9, 0.18, 0.25), hinge * CFrame.new(0, 1.05, 1.175), C_GOLDBRIGHT, Enum.Material.SmoothPlastic)
	handle:SetAttribute("Hinge", hinge)

	-- Brillo dorado y partículas radiantes
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = Color3.fromRGB(255, 225, 120)
	glow.Range = 12
	glow.Brightness = 1.2
	glow.Shadows = false
	glow.Parent = body

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 5
	sparkles.Lifetime = NumberRange.new(1.2, 2.2)
	sparkles.Speed = NumberRange.new(0.6, 1.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.4), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 235, 140))
	sparkles.LightEmission = 1
	sparkles.Parent = body
	-- Brillo dorado (el cliente lo apaga si el cofre está abierto para ese jugador).
	local glow = Instance.new("PointLight")
	glow.Name = "Glow"
	glow.Color = Colors.Glow
	glow.Range = 9
	glow.Brightness = 0.8
	glow.Shadows = false
	glow.Parent = body
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 3
	sparkles.Lifetime = NumberRange.new(1.2, 2)
	sparkles.Speed = NumberRange.new(0.4, 1)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Color = ColorSequence.new(Colors.Glow)
	sparkles.LightEmission = 1
	sparkles.Parent = body

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ChestPrompt"
	prompt.ActionText = "Abrir"
	prompt.ObjectText = chest.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = ChestConfig.HoldDuration
	prompt.MaxActivationDistance = ChestConfig.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("ChestId", chest.Id)
	prompt.Parent = body
	prompt.Triggered:Connect(function(player: Player)
		if openLimiter:check(player) ~= "ok" then
			return
		end
		local code, detail = ChestService.open(player, chest.Id, body.Position)
		if resultRemote then
			resultRemote:FireClient(player, code == Codes.Success, code, chest.Id, detail)
		end
		if code == Codes.Success then
			push(player)
		end
	end)
	-- Estilo studs, como el spawn (el brillo de la gema y la cerradura se queda de neón)
	StudProps.studify(model)
	model.PrimaryPart = body
	model.Parent = parent
	chestParts[chest.Id] = body
end

local function buildAll()
	-- Espera a la cascada, las ruinas y el campamento (sus repisas y losas), con un límite.
	local waited = 0
	while not WildsService.isBuilt() and waited < 60 do
		waited += task.wait(0.5)
	end
	PartFactory.removeExisting(Workspace, MODEL_NAME)
	local folder = Instance.new("Folder")
	folder.Name = MODEL_NAME
	for _, chest in ChestConfig.Chests do
		buildChest(folder, chest)
	end
	folder.Parent = Workspace
end

-- Remotos y avisos a los jugadores (sin construir los cofres: lo usan las pruebas).
function ChestService.startRemotes()
	stateRemote = RemoteService.get(Constants.Remotes.ChestState)
	resultRemote = RemoteService.get(Constants.Remotes.ChestResult)
	local requestRemote = RemoteService.get(Constants.Remotes.RequestChests)
	requestRemote.OnServerEvent:Connect(function(player: Player)
		if requestLimiter:check(player) == "ok" then
			push(player)
		end
	end)
	PlayerDataService.onPetDataReady(push)
	Players.PlayerRemoving:Connect(function(player)
		openLimiter:remove(player)
		requestLimiter:remove(player)
	end)
end

function ChestService.start()
	ChestService.startRemotes()
	task.spawn(function()
		local ok, err = pcall(buildAll)
		if not ok then
			warn("[ChestService] " .. tostring(err))
		end
	end)
end

return ChestService
