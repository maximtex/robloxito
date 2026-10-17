-- Zonas y portales:
-- - Construye los portales de ZoneConfig (arco de piedra con musgo, raíces, cristales,
--   runas y energía en el interior). El ProximityPrompt solo abre el panel del cliente.
-- - Desbloqueo (UnlockZone): validado aquí, cobra una sola vez (ZoneLogic), se registra
--   en los datos del jugador (SaveService, mismo DataStore) y se guarda al momento.
-- - Viaje (TravelToZone): cerca de un portal que lleve a esa zona, con la zona
--   desbloqueada. Precarga la zona de destino (streaming) y mueve el personaje con
--   PivotTo: no usa LoadCharacter, así que avatar, mascotas y datos no cambian.
-- - Guardia: si alguien está dentro de una zona que no ha desbloqueado (p. ej. moviendo
--   su personaje con trampas), se le devuelve al bosque. También mantiene el atributo
--   CurrentZone según la posición real del personaje.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
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

-- Zona que contiene una posición (la más cercana cuyo radio la incluye).
function ZoneService.zoneAt(position: Vector3): string?
	local best, bestDistance = nil, math.huge
	for zoneId, zone in ZoneConfig.Zones do
		local center = ZoneService.getZoneCenter(zoneId) :: Vector3
		local distance = flatDistance(position, center)
		if distance <= zone.Radius and distance < bestDistance then
			best, bestDistance = zoneId, distance
		end
	end
	return best
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- ¿Está el jugador junto a un portal que lleva a `targetZone`?
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

-- Portales (visual) ---------------------------------------------------------------

local PORTAL_STYLES = {
	Ancient = {
		Stone = Color3.fromRGB(150, 148, 136),
		DarkStone = Color3.fromRGB(104, 106, 98),
		Energy = Color3.fromRGB(110, 214, 236),
	},
	Return = {
		Stone = Color3.fromRGB(190, 186, 204),
		DarkStone = Color3.fromRGB(128, 126, 150),
		Energy = Color3.fromRGB(150, 220, 140),
	},
}
local CRYSTAL_COLORS = {
	Color3.fromRGB(110, 170, 255), -- azul
	Color3.fromRGB(176, 120, 236), -- violeta
	Color3.fromRGB(96, 220, 210), -- turquesa
}
local MOSS = Color3.fromRGB(92, 140, 64)
local ROOT = Color3.fromRGB(96, 72, 50)

local INNER_WIDTH = 10
local PILLAR_HEIGHT = 9
local ARCH_RADIUS = 6.2

local function buildPortal(parent: Instance, portalId: string)
	local portal = ZoneConfig.Portals[portalId]
	local position = ZoneService.getPortalPosition(portalId) :: Vector3
	local target = ZoneConfig.Zones[portal.Target]
	local style = PORTAL_STYLES[portal.Style] or PORTAL_STYLES.Ancient

	-- Marco local: X a la derecha, Y arriba, el frente mira a -Z (hacia el interior de la zona).
	local frame = CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end

	local model = Instance.new("Model")
	model.Name = "Portal_" .. portalId
	model:SetAttribute("PortalId", portalId)

	-- Escalinata de piedra
	local base = PartFactory.part(model, "Steps", {
		Size = Vector3.new(16, 0.6, 7),
		CFrame = at(0, 0.3, 0),
		Color = style.DarkStone,
		Material = Enum.Material.Slate,
	})
	PartFactory.part(model, "StepFront", {
		Size = Vector3.new(12, 0.3, 2),
		CFrame = at(0, 0.15, -4.4),
		Color = style.Stone,
		Material = Enum.Material.Slate,
	})

	-- Pilares de bloques irregulares con runas y cristales incrustados
	local halfWidth = INNER_WIDTH / 2 + 1.1
	for side = -1, 1, 2 do
		local x = side * halfWidth
		for block = 1, 3 do
			local wobble = (block % 2 == 0) and 0.08 or -0.06
			PartFactory.part(model, ("Pillar%d_%d"):format(side, block), {
				Size = Vector3.new(2.4 - block * 0.1, PILLAR_HEIGHT / 3, 2.4),
				CFrame = at(x, 0.6 + (block - 0.5) * PILLAR_HEIGHT / 3, 0) * CFrame.Angles(0, wobble * side, wobble),
				Color = if block == 2 then style.DarkStone else style.Stone,
				Material = Enum.Material.Cobblestone,
			})
		end
		local rune = PartFactory.part(model, "Rune" .. side, {
			Size = Vector3.new(0.35, PILLAR_HEIGHT * 0.55, 0.08),
			CFrame = at(x, 0.6 + PILLAR_HEIGHT * 0.5, -1.25),
			Color = style.Energy,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		rune:SetAttribute("Glow", true)
		-- Cristales que brotan del pilar
		for index, offset in { Vector3.new(side * 1.1, 2.2, -0.6), Vector3.new(side * 1.2, 6.4, 0.5) } do
			PartFactory.part(model, ("Crystal%d_%d"):format(side, index), {
				Size = Vector3.new(0.7, 2.2, 0.7),
				CFrame = at(x + offset.X, offset.Y, offset.Z) * CFrame.Angles(0, math.rad(45), math.rad(-side * 35)),
				Color = CRYSTAL_COLORS[(index + (side > 0 and 1 or 0)) % 3 + 1],
				Material = Enum.Material.Neon,
				Solid = false,
			})
		end
		-- Raíz que trepa por el pilar
		local rootBase = frame * Vector3.new(x + side * 1.6, -0.4, 1.4)
		local rootMid = frame * Vector3.new(x + side * 1.3, 3.5, 1.3)
		local rootTop = frame * Vector3.new(x + side * 0.6, 7.5, 1.3)
		PartFactory.segment(model, "Root" .. side .. "_1", rootBase, rootMid, 0.9, ROOT, Enum.Material.Wood, false)
		PartFactory.segment(model, "Root" .. side .. "_2", rootMid, rootTop, 0.6, ROOT, Enum.Material.Wood, false)
		-- Musgo sobre el pilar
		PartFactory.ellipsoid(model, "Moss" .. side, at(x, 0.6 + PILLAR_HEIGHT + 0.1, 0), Vector3.new(2.8, 0.7, 2.8), MOSS, Enum.Material.LeafyGrass)
	end

	-- Arco: bloques de piedra a lo largo de una semicircunferencia
	local archCenterY = 0.6 + PILLAR_HEIGHT
	local segments = 7
	for index = 0, segments - 1 do
		local angle = math.pi * (index + 0.5) / segments
		local x = math.cos(angle) * ARCH_RADIUS
		local y = archCenterY + math.sin(angle) * ARCH_RADIUS * 0.75
		PartFactory.part(model, "Arch" .. index, {
			Size = Vector3.new(3, 2, 2.4),
			CFrame = at(x, y, 0) * CFrame.Angles(0, 0, angle + math.pi / 2),
			Color = if index % 2 == 0 then style.Stone else style.DarkStone,
			Material = Enum.Material.Cobblestone,
		})
	end
	-- Cristal clave en lo alto (silueta reconocible a distancia)
	PartFactory.part(model, "Keystone", {
		Size = Vector3.new(1.4, 3.6, 1.4),
		CFrame = at(0, archCenterY + ARCH_RADIUS * 0.75 + 1.6, 0) * CFrame.Angles(0, math.rad(45), 0),
		Color = CRYSTAL_COLORS[2],
		Material = Enum.Material.Neon,
		Solid = false,
	})
	PartFactory.ellipsoid(model, "ArchMoss", at(-2.5, archCenterY + ARCH_RADIUS * 0.75 + 0.9, 0), Vector3.new(3.4, 0.8, 2.6), MOSS, Enum.Material.LeafyGrass)

	-- Energía en el interior: óvalo de campo de fuerza con chispas sutiles
	local energy = PartFactory.ellipsoid(model, "Energy", at(0, 0.6 + (PILLAR_HEIGHT + ARCH_RADIUS * 0.6) / 2, 0), Vector3.new(INNER_WIDTH, PILLAR_HEIGHT + ARCH_RADIUS * 0.6, 0.4), style.Energy, Enum.Material.ForceField)
	energy.Transparency = 0.15
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Rate = 6
	sparkles.Lifetime = NumberRange.new(1.2, 2)
	sparkles.Speed = NumberRange.new(0.3, 0.8)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(0.25, 0)
	sparkles.Transparency = NumberSequence.new(0.2, 1)
	sparkles.LightEmission = 1
	sparkles.Color = ColorSequence.new(style.Energy, CRYSTAL_COLORS[2])
	sparkles.Parent = energy
	local light = Instance.new("PointLight")
	light.Color = style.Energy
	light.Range = 16
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = energy

	-- Vegetación y rocas que integran el portal con el entorno (a los lados, sin tapar el frente)
	for index, spot in { Vector3.new(-9.5, 0, 1.5), Vector3.new(9.8, 0, 0.8), Vector3.new(-8, 0, -2.5), Vector3.new(8.5, 0, -2.8) } do
		if index <= 2 then
			PartFactory.ellipsoid(model, "Rock" .. index, at(spot.X, 0.6, spot.Z), Vector3.new(3.6, 2.2, 3), style.DarkStone, Enum.Material.Slate)
		else
			PartFactory.ball(model, "Bush" .. index, frame * Vector3.new(spot.X, 0.8, spot.Z), 2.4, MOSS, Enum.Material.LeafyGrass, false)
		end
	end

	-- Interacción: solo abre el panel del portal en el cliente.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PortalPrompt"
	prompt.ActionText = "Usar portal"
	prompt.ObjectText = "Portal · " .. target.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("PortalId", portalId)
	prompt.Parent = base

	model.PrimaryPart = base
	model.Parent = parent
end

-- Acciones ----------------------------------------------------------------------

local function unlockZone(player: Player, zoneId: any): (string, number?)
	if not isValidId(zoneId) or not ZoneConfig.Zones[zoneId] then
		return Codes.InvalidRequest, nil
	end
	local profile = PlayerDataService.get(player)
	-- Sin datos cargados no se puede registrar el desbloqueo con seguridad.
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady, nil
	end
	if not isNearPortalTo(player, zoneId) then
		return Codes.TooFar, nil
	end
	local code, missing = ZoneLogic.unlock(profile, ZoneConfig, zoneId, Codes)
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
	-- Precargar la zona de destino para no caer a través de un terreno sin cargar.
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
	-- Altura del centro del personaje sobre el suelo (R6 y R15) más un pequeño margen.
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
