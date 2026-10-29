-- Zonas y puertas de energía (estilo Pet Simulator; se abren pagando 💰):
-- - Construye las puertas de energía de ZoneConfig en la entrada de cada puente.
-- - Desbloqueo (UnlockZone): validado aquí, cobra una sola vez (ZoneLogic), se registra
--   en los datos del jugador (SaveService, mismo DataStore) y se guarda al momento.
-- - Guardia: si alguien está dentro de una zona que no ha desbloqueado, se le devuelve al bosque.
--   También mantiene el atributo CurrentZone según la posición real del personaje.
-- - Portales entre mundos (ZoneConfig.WorldPortals): el arco gigante de la Fortaleza Goblin al
--   Mundo 2 y el de vuelta. Los construye aquí (PortalBuilder); el cliente pide el viaje al
--   cruzar su energía (PortalController). El mundo en que estás se guarda (PetData.World): si
--   mueres o vuelves a entrar estando en el Mundo 2, apareces allí.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local RebirthLogic = require(Shared.RebirthLogic)
local CaveLogic = require(Shared.CaveLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local StudFloor = require(Shared.Util.StudFloor)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local ZoneLogic = require(script.Parent.Parent.Util.ZoneLogic)
local PortalBuilder = require(script.Parent.Parent.Util.PortalBuilder)
local DevConfig = require(script.Parent.Parent.DevConfig)

-- Solo en Studio (DevConfig.StudioAllZones): viajar a todas las zonas del Mundo 1 para probar
local function devAllZones(): boolean
	return DevConfig.StudioAllZones == true and RunService:IsStudio()
end

local Codes = Constants.PurchaseCodes
local FOLDER_NAME = "ZonePortals"
local MAX_ID_LENGTH = 64
local STREAM_TIMEOUT = 6
local GUARD_INTERVAL = 1
local GROUND = GeneratorConfig.Position.Y

local ZoneService = {}

local unlockLimiter = RateLimiter.new(ZoneConfig.UnlockCooldown, 5, 6)
local travelLimiter = RateLimiter.new(ZoneConfig.TravelCooldown, 6, 6)
local fastLimiter = RateLimiter.new(ZoneConfig.FastTravelCooldown or 5, 20, 4)
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
	local portal = ZoneConfig.Portals[portalId] or ZoneConfig.WorldPortals[portalId]
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
-- Las mazmorras (lejos del mapa) cuentan como la zona de su cueva (CaveConfig).
function ZoneService.zoneAt(position: Vector3): string?
	local _, cave = CaveLogic.caveAt(position.X, position.Z, 8)
	if cave then
		return cave.Zone
	end
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

-- ¿Está el jugador junto a una puerta que lleva a `targetZone`? Devuelve también el portal
-- entre mundos (WorldPortals) junto al que está, si es uno de esos.
local function isNearPortalTo(player: Player, targetZone: string): (boolean, any?)
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
	for portalId, portal in ZoneConfig.WorldPortals do
		if portal.Target == targetZone then
			local position = ZoneService.getPortalPosition(portalId)
			if position and flatDistance(root.Position, position) <= (portal.Radius or 8) + 14 then
				return true, portal
			end
		end
	end
	return false
end

-- Mundo de una zona (ZoneConfig.Zones.*.World; 1 si no lo dice)
local function worldOf(zoneId: string?): number
	local zone = zoneId and ZoneConfig.Zones[zoneId]
	return if zone and zone.World then zone.World else 1
end

local function isValidId(value: any): boolean
	return typeof(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH
end

-- Puertas de energía: barrera de cristal en el paso del muro ---------------------

-- Tono del cristal y del nombre de la zona según el estilo de la puerta
local GATE_STYLES = {
	Ancient = { Glass = Color3.fromRGB(150, 226, 255), Title = Color3.fromRGB(120, 236, 255) },
	Ember = { Glass = Color3.fromRGB(255, 176, 128), Title = Color3.fromRGB(255, 196, 120) },
	Frost = { Glass = Color3.fromRGB(200, 236, 255), Title = Color3.fromRGB(170, 230, 255) },
	Goblin = { Glass = Color3.fromRGB(170, 230, 120), Title = Color3.fromRGB(190, 255, 120) },
	-- Tierras Divididas: cristal entre el fuego y el hielo
	Divided = { Glass = Color3.fromRGB(226, 196, 255), Title = Color3.fromRGB(255, 214, 150) },
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

	-- Nombre de la zona y precio escritos en la cara por la que se llega: Front (hacia -Z) en
	-- las puertas del sur; Back en las del norte (Mundo 2: se llega andando hacia -Z)
	local sign = Instance.new("SurfaceGui")
	sign.Name = "GateSign"
	sign.Face = if portal.Offset.Y < 0 then Enum.NormalId.Back else Enum.NormalId.Front
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

-- Portales entre mundos: el arco gigante (PortalBuilder) con su nombre encima ----------------

local function buildWorldPortal(parent: Instance, portalId: string)
	local portal = ZoneConfig.WorldPortals[portalId]
	local position = ZoneService.getPortalPosition(portalId) :: Vector3
	local target = ZoneConfig.Zones[portal.Target]
	local facing = portal.Facing or Vector3.new(0, 0, -1)
	local ground = Vector3.new(position.X, GROUND + StudFloor.BaseTop + StudFloor.raiseAt(position.X, position.Z), position.Z)
	local model = Instance.new("Model")
	model.Name = "WorldPortal_" .. portalId
	model:SetAttribute("WorldPortalId", portalId)
	model:SetAttribute("TargetZone", portal.Target)
	model:SetAttribute("PortalRadius", portal.Radius or 8)
	local anchor, veil = PortalBuilder.build(model, CFrame.lookAt(ground, ground + facing), portal.Scale or 3.2, portal.Style)
	veil.Name = "Energy"
	model.PrimaryPart = anchor

	-- Nombre del destino y, si pide un jefe, quién lo abre (lo esconde el cliente al abrirse)
	local sign = Instance.new("Part")
	sign.Name = "SignAnchor"
	sign.Anchored = true
	sign.CanCollide = false
	sign.CanQuery = false
	sign.CanTouch = false
	sign.Transparency = 1
	sign.Size = Vector3.one * 0.2
	sign.CFrame = CFrame.new(ground + Vector3.new(0, 7.6 * (portal.Scale or 3.2) + 4, 0))
	sign.Parent = model
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PortalSign"
	billboard.Size = UDim2.fromScale(26, 7)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 260
	billboard.Parent = sign
	local function line(name: string, text: string, color: Color3, y: number, h: number)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0, y)
		label.Size = UDim2.fromScale(1, h)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = text
		label.Parent = billboard
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = Color3.fromRGB(20, 24, 30)
		stroke.Parent = label
	end
	line("Title", portal.Title or target.DisplayName, Color3.fromRGB(255, 236, 140), 0, 0.55)
	local boss = target.RequiredBoss and EnemyConfig.Types[target.RequiredBoss]
	if boss then
		line("Lock", "🔒 Derrota al 👑 " .. boss.DisplayName, Color3.fromRGB(255, 150, 130), 0.58, 0.4)
	end
	model.Parent = parent
end

-- Coloca al jugador en el punto de llegada de una zona (o el que diga el portal)
local function arrivalOf(zoneId: string, portal: any?): CFrame?
	if portal and portal.Arrival then
		local center = ZoneService.getZoneCenter(zoneId)
		if not center then
			return nil
		end
		local position = center + portal.Arrival
		return CFrame.lookAt(position, position + (portal.ArrivalFacing or Vector3.new(0, 0, -1)))
	end
	return ZoneService.getArrivalCFrame(zoneId)
end

local function placeCharacter(player: Player, destination: CFrame): boolean
	local root = rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and character and humanoid and humanoid.Health > 0) then
		return false
	end
	if humanoid.Sit then
		humanoid.Sit = false
	end
	local lift = humanoid.HipHeight + root.Size.Y / 2 + 0.5
	character:PivotTo(destination + Vector3.new(0, lift, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

-- Al aparecer (al entrar o tras morir): si estaba en el Mundo 2 (y lo tiene abierto), allí.
local function spawnInWorld(player: Player)
	local profile = PlayerDataService.get(player)
	if not (profile and PlayerDataService.isPetDataReady(profile)) then
		return
	end
	if profile.PetData.World ~= 2 or not ZoneLogic.isUnlocked(profile, ZoneConfig, "World2") then
		return
	end
	local destination = ZoneService.getArrivalCFrame("World2")
	if not destination then
		return
	end
	traveling[player] = true
	pcall(function()
		player:RequestStreamAroundAsync(destination.Position, STREAM_TIMEOUT)
	end)
	if placeCharacter(player, destination) then
		player:SetAttribute(Constants.Attributes.CurrentZone, "World2")
	end
	traveling[player] = nil
end

local function watchSpawns(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.2)
		if player.Character == character then
			spawnInWorld(player)
		end
	end)
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
	local near, worldPortal = isNearPortalTo(player, zoneId)
	if not near then
		return Codes.TooFar
	end
	if not ZoneLogic.isUnlocked(profile, ZoneConfig, zoneId) then
		return Codes.ZoneLocked
	end
	local destination = arrivalOf(zoneId, worldPortal) :: CFrame

	traveling[player] = true
	pcall(function()
		player:RequestStreamAroundAsync(destination.Position, STREAM_TIMEOUT)
	end)
	if not placeCharacter(player, destination) then
		traveling[player] = nil
		return Codes.NotReady
	end
	player:SetAttribute(Constants.Attributes.CurrentZone, zoneId)
	-- Cambio de mundo: se guarda para aparecer allí la próxima vez
	if worldPortal and profile.PetData.World ~= worldOf(zoneId) then
		profile.PetData.World = worldOf(zoneId)
		PlayerDataService.markDirty(player)
	end
	traveling[player] = nil
	return Codes.Success
end

-- Viaje rápido (🗺️ Viajar): a la llegada de cualquier zona abierta del Mundo 1 (ZoneConfig.TravelOrder), sin estar junto a un
-- portal. No durante una partida de oleadas (atributo WaveRun). Al pueblo se llega junto al
-- spawn (TravelArrival). Si cambia de mundo, se guarda para aparecer allí la próxima vez.
function ZoneService.fastTravel(player: Player, zoneId: any): string
	-- Solo las zonas de la lista (las del Mundo 1)
	if not isValidId(zoneId) or not ZoneConfig.Zones[zoneId] or not table.find(ZoneConfig.TravelOrder, zoneId) then
		return Codes.InvalidRequest
	end
	if traveling[player] then
		return Codes.Busy
	end
	local profile = PlayerDataService.get(player)
	if not (profile and PlayerDataService.isPetDataReady(profile)) then
		return Codes.NotReady
	end
	local run = player:GetAttribute(Constants.Attributes.WaveRun)
	if run ~= nil and run ~= 0 and run ~= "" then
		return Codes.InWave
	end
	if not ZoneLogic.isUnlocked(profile, ZoneConfig, zoneId) and not devAllZones() then
		return Codes.ZoneLocked
	end
	local zone = ZoneConfig.Zones[zoneId]
	local destination = ZoneService.getArrivalCFrame(zoneId) :: CFrame
	if zone.TravelArrival then
		local center = ZoneService.getZoneCenter(zoneId) :: Vector3
		local position = center + zone.TravelArrival
		destination = CFrame.lookAt(position, position + (zone.ArrivalFacing or Vector3.new(0, 0, -1)))
	end
	traveling[player] = true
	pcall(function()
		player:RequestStreamAroundAsync(destination.Position, STREAM_TIMEOUT)
	end)
	if not placeCharacter(player, destination) then
		traveling[player] = nil
		return Codes.NotReady
	end
	player:SetAttribute(Constants.Attributes.CurrentZone, zoneId)
	if profile.PetData.World ~= worldOf(zoneId) then
		profile.PetData.World = worldOf(zoneId)
		PlayerDataService.markDirty(player)
	end
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
			or (devAllZones() and table.find(ZoneConfig.TravelOrder, zoneId) ~= nil)
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
	for portalId in ZoneConfig.WorldPortals do
		local ok, err = pcall(buildWorldPortal, folder, portalId)
		if not ok then
			warn("[ZoneService] Portal " .. portalId .. ": " .. tostring(err))
		end
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

	RemoteService.get(Constants.Remotes.FastTravel).OnServerEvent:Connect(function(player: Player, zoneId: any)
		local rate = fastLimiter:check(player)
		if rate == "flood" then
			return
		end
		local safeZoneId = if isValidId(zoneId) then zoneId else nil
		if rate == "cooldown" then
			travelResult:FireClient(player, false, Codes.TooFast, safeZoneId, true)
			return
		end
		local code = ZoneService.fastTravel(player, zoneId)
		travelResult:FireClient(player, code == Codes.Success, code, safeZoneId, true)
	end)

	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute(Constants.Attributes.CurrentZone, ZoneConfig.DefaultZone)
		player:SetAttribute(Constants.Attributes.DevAllZones, if devAllZones() then true else nil)
		watchSpawns(player)
	end)
	for _, player in Players:GetPlayers() do
		player:SetAttribute(Constants.Attributes.CurrentZone, ZoneConfig.DefaultZone)
		player:SetAttribute(Constants.Attributes.DevAllZones, if devAllZones() then true else nil)
		watchSpawns(player)
	end
	-- Al cargar sus datos: si se fue estando en el Mundo 2, vuelve a aparecer allí
	PlayerDataService.onPetDataReady(function(player)
		if player.Character then
			spawnInWorld(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		unlockLimiter:remove(player)
		travelLimiter:remove(player)
		fastLimiter:remove(player)
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
