-- Zonas y puertas de energía (estilo Pet Simulator; se abren pagando 💰):
-- - Construye las puertas de energía de ZoneConfig en la entrada de cada puente.
-- - Desbloqueo (UnlockZone): validado aquí, cobra una sola vez (ZoneLogic), se registra
--   en los datos del jugador (SaveService, mismo DataStore) y se guarda al momento.
-- - Guardia: si alguien está dentro de una zona que no ha desbloqueado, se le devuelve al bosque.
--   También mantiene el atributo CurrentZone según la posición real del personaje.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local RebirthLogic = require(Shared.RebirthLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local StudFloor = require(Shared.Util.StudFloor)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local ZoneLogic = require(script.Parent.Parent.Util.ZoneLogic)

local Codes = Constants.PurchaseCodes
local FOLDER_NAME = "ZonePortals"
local MAX_ID_LENGTH = 64
local STREAM_TIMEOUT = 6
local GUARD_INTERVAL = 1
local GROUND = GeneratorConfig.Position.Y

local ZoneService = {}

local unlockLimiter = RateLimiter.new(ZoneConfig.UnlockCooldown, 5, 6)
local travelLimiter = RateLimiter.new(ZoneConfig.TravelCooldown, 6, 6)
local traveling: { [Player]: boolean } = {}

-- Posiciones ------------------------------------------------------------------

function ZoneService.getZoneCenter(zoneId: string): Vector3?
	local zone = ZoneConfig.Zones[zoneId]
	if not zone then
		return nil
	end
	local base = GeneratorConfig.Position
	return Vector3.new(base.X + zone.Center.X, GROUND, base.Z + zone.Center.Y)
end

function ZoneService.getPortalPosition(portalId: string): Vector3?
	local portal = ZoneConfig.Portals[portalId]
	local center = portal and ZoneService.getZoneCenter(portal.Zone)
	if not center then
		return nil
	end
	return center + Vector3.new(portal.Offset.X, 0, portal.Offset.Y)
end

-- Punto de llegada seguro: sobre el suelo de la zona, mirando hacia su interior.
function ZoneService.getArrivalCFrame(zoneId: string): CFrame?
	local zone = ZoneConfig.Zones[zoneId]
	local center = ZoneService.getZoneCenter(zoneId)
	if not (zone and center) then
		return nil
	end
	local position = center + Vector3.new(zone.Arrival.X, zone.Arrival.Y, zone.Arrival.Z)
	return CFrame.lookAt(position, position + zone.ArrivalFacing)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- Zona que contiene una posición (comprobación cuadrada exacta para mapas contiguos 320×320).
function ZoneService.zoneAt(position: Vector3): string?
	local best, bestDz = nil, math.huge
	for zoneId, zone in ZoneConfig.Zones do
		local center = ZoneService.getZoneCenter(zoneId) :: Vector3
		local dx = math.abs(position.X - center.X)
		local dz = math.abs(position.Z - center.Z)
		local half = zone.Radius or 160
		if dx <= half + 12 and dz <= half and dz < bestDz then
			best, bestDz = zoneId, dz
		end
	end
	return best
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- ¿Está el jugador junto a una puerta que lleva a `targetZone`?
local function isNearPortalTo(player: Player, targetZone: string): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	for portalId, portal in ZoneConfig.Portals do
		if portal.Target == targetZone then
			local position = ZoneService.getPortalPosition(portalId)
			if position and flatDistance(root.Position, position) <= ZoneConfig.InteractDistance then
				return true
			end
		end
	end
	return false
end

local function isValidId(value: any): boolean
	return typeof(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH
end

-- Puertas de energía: barrera de cristal en el paso del muro ---------------------

-- Tono del cristal y del nombre de la zona según el estilo de la puerta
local GATE_STYLES = {
	Ancient = { Glass = Color3.fromRGB(150, 226, 255), Title = Color3.fromRGB(120, 236, 255) },
	Ember = { Glass = Color3.fromRGB(255, 176, 128), Title = Color3.fromRGB(255, 196, 120) },
}
local GATE_TRANSPARENCY = 0.6
local SIGN_PIXELS_PER_STUD = 20

-- Texto escrito en el cristal: centrado a `center` studs del suelo y `height` studs de alto
local function gateLabel(sign: SurfaceGui, name: string, text: string, color: Color3, center: number, height: number)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 1, -center * SIGN_PIXELS_PER_STUD)
	label.Size = UDim2.new(0.9, 0, 0, height * SIGN_PIXELS_PER_STUD)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Parent = sign
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Color = Color3.fromRGB(20, 40, 56)
	stroke.Parent = label
end

local function buildPortal(parent: Instance, portalId: string)
	local portal = ZoneConfig.Portals[portalId]
	local position = ZoneService.getPortalPosition(portalId) :: Vector3
	local target = ZoneConfig.Zones[portal.Target]
	local cost = target.UnlockCost or 0
	local style = GATE_STYLES[portal.Style] or GATE_STYLES.Ancient

	local model = Instance.new("Model")
	model.Name = "Portal_" .. portalId
	model:SetAttribute("PortalId", portalId)
	model:SetAttribute("TargetZone", portal.Target)

	-- Cristal translúcido que llena el paso del muro de damero de lado a lado y hasta arriba,
	-- como en la referencia: se ve la zona siguiente detrás. Al desbloquear la zona, el
	-- cliente lo vuelve invisible y sin colisión (PortalController).
	local layout = StudFloor.Zones[portal.Zone]
	local width = 2 * (if layout and layout.Walls.GateHalf then layout.Walls.GateHalf else 28)
	local height = (StudFloor.Wall.BaseRows + StudFloor.Wall.TopRows) * StudFloor.Wall.BlockHeight
	local barrier = PartFactory.part(model, "GateBarrier", {
		Size = Vector3.new(width, height, 1),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)),
		Color = style.Glass,
		Material = Enum.Material.SmoothPlastic,
		Solid = true,
		CastShadow = false,
	})
	barrier.Transparency = GATE_TRANSPARENCY
	barrier:SetAttribute("LockedTransparency", GATE_TRANSPARENCY)

	-- Nombre de la zona y precio escritos en la cara por la que se llega (Front, hacia -Z)
	local sign = Instance.new("SurfaceGui")
	sign.Name = "GateSign"
	sign.Face = Enum.NormalId.Front
	sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sign.PixelsPerStud = SIGN_PIXELS_PER_STUD
	sign.LightInfluence = 0
	sign.MaxDistance = 220
	sign.Parent = barrier
	gateLabel(sign, "ZoneTitle", target.DisplayName, style.Title, 17, 7)
	local boss = target.RequiredBoss and EnemyConfig.Types[target.RequiredBoss]
	gateLabel(sign, "ZoneCost", "🔒 💰 " .. formatNumber(cost), Color3.fromRGB(255, 230, 80), 11, 4.5)
	if boss then
		gateLabel(sign, "ZoneBoss", "🏆 Derrota al " .. boss.DisplayName, Color3.fromRGB(255, 160, 140), 6.5, 3.2)
	end

	-- Interacción para desbloquear, a la altura del jugador en medio del paso
	local promptAt = Instance.new("Attachment")
	promptAt.Name = "PromptAttachment"
	promptAt.Position = Vector3.new(0, 4 - height / 2, 0)
	promptAt.Parent = barrier
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PortalPrompt"
	prompt.ActionText = "Desbloquear (" .. formatNumber(cost) .. " 💰)"
	prompt.ObjectText = target.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 22
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("PortalId", portalId)
	prompt.Parent = promptAt

	model.PrimaryPart = barrier
	model.Parent = parent
end

-- Acciones ----------------------------------------------------------------------

local function unlockZone(player: Player, zoneId: any): (string, number?)
	if not isValidId(zoneId) or not ZoneConfig.Zones[zoneId] then
		return Codes.InvalidRequest, nil
	end
	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady, nil
	end
	if not isNearPortalTo(player, zoneId) then
		return Codes.TooFar, nil
	end
	local rebirths = RebirthLogic.count(RebirthLogic.ofProfile(profile))
	local code, missing = ZoneLogic.unlock(profile, ZoneConfig, zoneId, Codes, rebirths)
	if code == Codes.Success then
		PlayerDataService.replicate(player)
		PlayerDataService.markDirty(player)
		PlayerDataService.saveNow(player)
	end
	return code, missing
end

local function travel(player: Player, zoneId: any): string
	if not isValidId(zoneId) or not ZoneConfig.Zones[zoneId] then
		return Codes.InvalidRequest
	end
	if traveling[player] then
		return Codes.Busy
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return Codes.NotReady
	end
	local zone = ZoneConfig.Zones[zoneId]
	if (zone.UnlockCost or 0) > 0 and not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady
	end
	if not isNearPortalTo(player, zoneId) then
		return Codes.TooFar
	end
	if not ZoneLogic.isUnlocked(profile, ZoneConfig, zoneId) then
		return Codes.ZoneLocked
	end
	local destination = ZoneService.getArrivalCFrame(zoneId) :: CFrame

	traveling[player] = true
	pcall(function()
		player:RequestStreamAroundAsync(destination.Position, STREAM_TIMEOUT)
	end)
	local root = rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and character and humanoid and humanoid.Health > 0) then
		traveling[player] = nil
		return Codes.NotReady
	end
	if humanoid.Sit then
		humanoid.Sit = false
	end
	local lift = humanoid.HipHeight + root.Size.Y / 2 + 0.5
	character:PivotTo(destination + Vector3.new(0, lift, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	player:SetAttribute(Constants.Attributes.CurrentZone, zoneId)
	traveling[player] = nil
	return Codes.Success
end

-- Guardia de zonas: devuelve al bosque a quien esté en una zona no desbloqueada.
local function guardZones()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if not root or traveling[player] then
			continue
		end
		local zoneId = ZoneService.zoneAt(root.Position) or ZoneConfig.DefaultZone
		local profile = PlayerDataService.get(player)
		local allowed = zoneId == ZoneConfig.DefaultZone
			or (profile ~= nil and PlayerDataService.isPetDataReady(profile) and ZoneLogic.isUnlocked(profile, ZoneConfig, zoneId))
		if not allowed then
			local back = ZoneService.getArrivalCFrame(ZoneConfig.DefaultZone)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if back and character and humanoid then
				warn(("[ZoneService] %s estaba en %s sin desbloquearla; vuelve al bosque."):format(player.Name, zoneId))
				character:PivotTo(back + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 + 0.5, 0))
				root.AssemblyLinearVelocity = Vector3.zero
			end
			zoneId = ZoneConfig.DefaultZone
		end
		if player:GetAttribute(Constants.Attributes.CurrentZone) ~= zoneId then
			player:SetAttribute(Constants.Attributes.CurrentZone, zoneId)
		end
	end
end

function ZoneService.start()
	PartFactory.removeExisting(workspace, FOLDER_NAME)
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for portalId in ZoneConfig.Portals do
		buildPortal(folder, portalId)
	end
	folder.Parent = workspace

	local zoneResult = RemoteService.get(Constants.Remotes.ZoneResult)
	local travelResult = RemoteService.get(Constants.Remotes.TravelResult)

	RemoteService.get(Constants.Remotes.UnlockZone).OnServerEvent:Connect(function(player: Player, zoneId: any)
		local rate = unlockLimiter:check(player)
		if rate == "flood" then
			return
		end
		local safeZoneId = if isValidId(zoneId) then zoneId else nil
		if rate == "cooldown" then
			zoneResult:FireClient(player, false, Codes.TooFast, safeZoneId)
			return
		end
		local code, missing = unlockZone(player, zoneId)
		local success = code == Codes.Success or code == Codes.AlreadyUnlocked
		zoneResult:FireClient(player, success, code, safeZoneId, missing)
	end)

	RemoteService.get(Constants.Remotes.TravelToZone).OnServerEvent:Connect(function(player: Player, zoneId: any)
		local rate = travelLimiter:check(player)
		if rate == "flood" then
			return
		end
		local safeZoneId = if isValidId(zoneId) then zoneId else nil
		if rate == "cooldown" then
			travelResult:FireClient(player, false, Codes.TooFast, safeZoneId)
			return
		end
		local code = travel(player, zoneId)
		travelResult:FireClient(player, code == Codes.Success, code, safeZoneId)
	end)

	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute(Constants.Attributes.CurrentZone, ZoneConfig.DefaultZone)
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute(Constants.Attributes.CurrentZone, ZoneConfig.DefaultZone)
	end
	Players.PlayerRemoving:Connect(function(player)
		unlockLimiter:remove(player)
		travelLimiter:remove(player)
		traveling[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(GUARD_INTERVAL)
			guardZones()
		end
	end)
end

return ZoneService
