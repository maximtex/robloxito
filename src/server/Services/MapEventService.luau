-- Eventos del mapa (MapEventConfig; lógica en MapEventLogic): cada pocos minutos pasa algo en una
-- zona del Mundo 1 con bichos y se avisa a todo el servidor (remoto MapEvent):
-- - Invasión: una horda de bichos de la zona alrededor de un punto. Si cae entera a tiempo,
--   premio para quien esté cerca o haya matado alguno.
-- - Goblin del tesoro: no ataca y corretea por la zona; si cae antes de escaparse, su botín
--   (grande) y un premio para quien esté cerca.
-- - Lluvia de diamantes: gemas por el suelo; cada una que tocas da 💎 y 💰 (con tope).
-- Todo lo decide el servidor; el cliente (MapEventController) solo avisa y marca el sitio.
-- Los bichos de los eventos son públicos (sin partida): los ven y los pegan todos los que no
-- estén jugando una partida de oleadas. Hacer un evento cuenta para el reto semanal
-- "Aventurero" (GameEvents "MapEventDone").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local MapEventConfig = require(Shared.Config.MapEventConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local MapEventLogic = require(Shared.MapEventLogic)
local WaveLogic = require(Shared.WaveLogic)
local StudFloor = require(Shared.Util.StudFloor)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local DiamondService = require(script.Parent.DiamondService)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local ZoneLogic = require(script.Parent.Parent.Util.ZoneLogic)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)

local MapEventService = {}

local FOLDER_NAME = "MapEvents"
local GEM_COLOR = Color3.fromRGB(110, 236, 255)

type Event = {
	Id: number,
	Kind: string,
	Zone: string,
	Center: Vector3,
	EndsAt: number, -- os.clock()
	Enemies: { [any]: boolean },
	Alive: number,
	Helpers: { [Player]: boolean }, -- mataron algún bicho del evento
	Collected: { [Player]: number }, -- gemas de la lluvia
	Done: { [Player]: boolean }, -- ya contado para el reto semanal
	Goblin: any?,
	Folder: Folder?,
	Finished: boolean,
}

local remote: RemoteEvent
local current: Event? = nil
local nextId = 0

-- Utilidades ---------------------------------------------------------------------------

local function serverTime(fromClock: number): number
	return Workspace:GetServerTimeNow() + (fromClock - os.clock())
end

local function zoneOrigin(zoneId: string): Vector3
	local zone = ZoneConfig.Zones[zoneId]
	local base = GeneratorConfig.Position
	return Vector3.new(base.X + zone.Center.X, 0, base.Z + zone.Center.Y)
end

local function groundAt(x: number, z: number): number
	return GeneratorConfig.Position.Y + StudFloor.BaseTop + StudFloor.raiseAt(x, z)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isNear(player: Player, center: Vector3): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	local offset = root.Position - center
	return Vector2.new(offset.X, offset.Z).Magnitude <= MapEventConfig.NearRadius
end

local function payload(event: Event, state: string, extra: { [string]: any }?)
	local kind = MapEventConfig.Kinds[event.Kind]
	local zone = ZoneConfig.Zones[event.Zone]
	local data = {
		Id = event.Id,
		State = state,
		Kind = event.Kind,
		Icon = kind.Icon,
		Name = kind.Name,
		Text = kind.Text:format(zone.DisplayName),
		Zone = event.Zone,
		ZoneName = zone.DisplayName,
		Position = event.Center,
		EndsAt = serverTime(event.EndsAt),
	}
	for key, value in extra or {} do
		data[key] = value
	end
	return data
end

-- Premio de un evento para un jugador (💰 y 💎 de la zona, por `scale`).
local function pay(player: Player, event: Event, scale: number): (number, number)
	local profile = PlayerDataService.get(player)
	if not (profile and PlayerDataService.isPetDataReady(profile)) then
		return 0, 0
	end
	local money, diamonds = MapEventLogic.reward(event.Kind, event.Zone)
	local coins = math.max(0, math.floor(money * scale))
	if coins > 0 then
		profile.Money += coins
	end
	local raw = diamonds * scale * PlayerDataService.diamondMultiplier(profile)
	local gems = DiamondService.grant(player, WaveLogic.roundDiamonds(raw, math.random()))
	PlayerDataService.replicate(player)
	return coins, gems
end

local function markDone(player: Player, event: Event)
	if not event.Done[player] then
		event.Done[player] = true
		GameEvents.fire("MapEventDone", player, event.Kind)
	end
end

-- Fin -----------------------------------------------------------------------------------

local scheduleNext: (delay: number?) -> ()

local function finish(event: Event, success: boolean)
	if event.Finished then
		return
	end
	event.Finished = true
	-- Premios: quien esté cerca o haya ayudado (la lluvia ya pagó gema a gema)
	if success and event.Kind ~= "DiamondRain" then
		for _, player in Players:GetPlayers() do
			if event.Helpers[player] or isNear(player, event.Center) then
				local coins, gems = pay(player, event, 1)
				markDone(player, event)
				remote:FireClient(player, payload(event, "Reward", { Money = coins, Diamonds = gems }))
			end
		end
	end
	for enemy in event.Enemies do
		if EnemyService.isAlive(enemy) then
			EnemyService.despawn(enemy)
		end
	end
	table.clear(event.Enemies)
	if event.Goblin and EnemyService.isAlive(event.Goblin) then
		EnemyService.despawn(event.Goblin)
	end
	if event.Folder then
		event.Folder:Destroy()
	end
	remote:FireAllClients(payload(event, "End", { Success = success }))
	if current == event then
		current = nil
	end
	scheduleNext()
end

-- Tipos de evento -----------------------------------------------------------------------

local function startInvasion(event: Event): boolean
	local settings = MapEventConfig.Kinds.Invasion
	local list = MapEventLogic.invasionList(event.Zone, math.random)
	for _, typeId in list do
		local angle = math.random() * math.pi * 2
		local distance = settings.Ring.Min + math.random() * (settings.Ring.Max - settings.Ring.Min)
		local x = event.Center.X + math.cos(angle) * distance
		local z = event.Center.Z + math.sin(angle) * distance
		local enemy = EnemyService.spawnPooled(event.Zone, typeId, Vector3.new(x, groundAt(x, z), z), {
			LeashCenter = event.Center,
			LeashRadius = 46,
			DetectRange = 40,
			HealthMultiplier = settings.Health,
			PoolLimit = 30,
			OnDeath = function(dead, killer: Player?)
				if event.Finished or not event.Enemies[dead] then
					return
				end
				event.Enemies[dead] = nil
				event.Alive = math.max(0, event.Alive - 1)
				if killer then
					event.Helpers[killer] = true
				end
				if event.Alive <= 0 then
					finish(event, true)
				elseif event.Alive % 4 == 0 then
					remote:FireAllClients(payload(event, "Progress", { Left = event.Alive }))
				end
			end,
		})
		if enemy then
			event.Enemies[enemy] = true
			event.Alive += 1
		end
	end
	return event.Alive > 0
end

local function startGoblin(event: Event): boolean
	local settings = MapEventConfig.Kinds.TreasureGoblin
	local health, reward = MapEventLogic.goblinScale(event.Zone)
	local position = Vector3.new(event.Center.X, groundAt(event.Center.X, event.Center.Z), event.Center.Z)
	local goblin = EnemyService.spawnPooled(event.Zone, settings.TypeId, position, {
		LeashCenter = event.Center,
		LeashRadius = settings.RoamRadius + 10,
		HealthMultiplier = health,
		RewardMultiplier = reward,
		PoolLimit = 2,
		OnDeath = function(_, killer: Player?)
			if killer then
				event.Helpers[killer] = true
			end
			finish(event, true)
		end,
	})
	if not goblin then
		return false
	end
	event.Goblin = goblin
	-- Corretea: cada poco, un sitio nuevo alrededor del punto (su "casa" se mueve)
	task.spawn(function()
		while not event.Finished and EnemyService.isAlive(goblin) do
			local angle = math.random() * math.pi * 2
			local distance = math.random() * settings.RoamRadius
			goblin.Home = event.Center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			goblin.NextWander = 0
			task.wait(settings.RoamEvery)
		end
	end)
	return true
end

local function startRain(event: Event): boolean
	local settings = MapEventConfig.Kinds.DiamondRain
	local folder = Instance.new("Folder")
	folder.Name = "Event" .. event.Id
	for index = 1, settings.Count do
		local angle = math.random() * math.pi * 2
		local distance = math.sqrt(math.random()) * settings.Radius
		local x = event.Center.X + math.cos(angle) * distance
		local z = event.Center.Z + math.sin(angle) * distance
		local gem = PartFactory.part(folder, "Gema" .. index, {
			Size = Vector3.new(1.4, 1.4, 1.4),
			CFrame = CFrame.new(x, groundAt(x, z) + 1.6, z) * CFrame.Angles(0, math.rad(45), math.rad(45)),
			Color = GEM_COLOR,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		gem.CanTouch = true
		local taken = false
		gem.Touched:Connect(function(hit)
			if taken or event.Finished then
				return
			end
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if not player then
				return
			end
			local count = event.Collected[player] or 0
			if count >= settings.MaxPerPlayer then
				return
			end
			taken = true
			event.Collected[player] = count + 1
			gem:Destroy()
			local coins, gems = pay(player, event, 1)
			remote:FireClient(player, payload(event, "Gem", { Money = coins, Diamonds = gems, Count = count + 1, Max = settings.MaxPerPlayer }))
			if count + 1 >= settings.MinForDone then
				markDone(player, event)
			end
			if #folder:GetChildren() == 0 then
				finish(event, true)
			end
		end)
	end
	folder.Parent = Workspace:FindFirstChild(FOLDER_NAME) or Workspace
	event.Folder = folder
	return true
end

-- Arranque de un evento ---------------------------------------------------------------------

local function tryRun(): boolean
	if current then
		return false
	end
	local present, unlocked = {}, {}
	for _, player in Players:GetPlayers() do
		local zoneId = player:GetAttribute(Constants.Attributes.CurrentZone)
		if type(zoneId) == "string" then
			present[zoneId] = true
		end
		local profile = PlayerDataService.get(player)
		if profile and PlayerDataService.isPetDataReady(profile) then
			for _, candidate in MapEventConfig.Zones do
				if ZoneLogic.isUnlocked(profile, ZoneConfig, candidate) then
					unlocked[candidate] = true
				end
			end
		end
	end
	local zoneId = MapEventLogic.pickZone(present, unlocked, math.random)
	local spot = zoneId and MapEventLogic.pickSpot(zoneId, math.random)
	if not (zoneId and spot) then
		return false
	end
	local origin = zoneOrigin(zoneId)
	local x, z = origin.X + spot.X, origin.Z + spot.Y
	local kindId = MapEventLogic.rollKind(math.random)
	local kind = MapEventConfig.Kinds[kindId]
	nextId += 1
	local event: Event = {
		Id = nextId,
		Kind = kindId,
		Zone = zoneId,
		Center = Vector3.new(x, groundAt(x, z), z),
		EndsAt = os.clock() + kind.Duration,
		Enemies = {},
		Alive = 0,
		Helpers = {},
		Collected = {},
		Done = {},
		Goblin = nil,
		Folder = nil,
		Finished = false,
	}
	local ok, started = pcall(function()
		if kindId == "Invasion" then
			return startInvasion(event)
		elseif kindId == "TreasureGoblin" then
			return startGoblin(event)
		end
		return startRain(event)
	end)
	if not (ok and started) then
		if not ok then
			warn("[MapEventService] " .. tostring(started))
		end
		event.Finished = true
		for enemy in event.Enemies do
			EnemyService.despawn(enemy)
		end
		if event.Folder then
			event.Folder:Destroy()
		end
		return false
	end
	current = event
	remote:FireAllClients(payload(event, "Start"))
	-- Se acaba solo al llegar la hora (la invasión que no cae se retira; el goblin se escapa)
	task.delay(kind.Duration, function()
		if not event.Finished then
			finish(event, event.Kind == "DiamondRain")
		end
	end)
	return true
end

-- Programa el siguiente (solo vale el último programado: si se lanza uno a mano en Studio, el
-- que estaba esperando se descarta y no se acumulan).
local scheduleToken = 0
function scheduleNext(delay: number?)
	scheduleToken += 1
	local token = scheduleToken
	task.delay(delay or MapEventLogic.nextDelay(math.random), function()
		while token == scheduleToken and not tryRun() do
			task.wait(MapEventConfig.RetryDelay)
		end
	end)
end

function MapEventService.start()
	remote = RemoteService.get(Constants.Remotes.MapEvent)
	PartFactory.removeExisting(Workspace, FOLDER_NAME)
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace
	-- Quien entra a mitad de un evento también se entera
	Players.PlayerAdded:Connect(function(player)
		task.wait(5)
		local event = current
		if event and not event.Finished and player.Parent then
			remote:FireClient(player, payload(event, "Start"))
		end
	end)
	scheduleNext(MapEventConfig.FirstDelay)
	-- Solo en Studio, para probar sin esperar: en la barra de comandos (vista Servidor),
	-- workspace.MapEvents:SetAttribute("RunNow", "Invasion") (o "TreasureGoblin",
	-- "DiamondRain", "Any" para uno al azar, "Stop" para acabar el que haya).
	if RunService:IsStudio() then
		folder:GetAttributeChangedSignal("RunNow"):Connect(function()
			local value = folder:GetAttribute("RunNow")
			if type(value) ~= "string" or value == "" then
				return
			end
			folder:SetAttribute("RunNow", nil)
			if value == "Stop" then
				if current and not current.Finished then
					finish(current, false)
				end
				return
			end
			local started = MapEventService.runNow(if value == "Any" then nil else value)
			print(("[MapEventService] RunNow %s: %s"):format(value, if started then "en marcha" else "no se pudo (ya hay uno o nadie puede ir)"))
		end)
	end
end

-- Para probar en Studio: lanza ya un evento (kindId opcional) si no hay otro en marcha.
function MapEventService.runNow(kindId: string?): boolean
	if current then
		return false
	end
	if kindId and MapEventConfig.Kinds[kindId] then
		local original = MapEventLogic.rollKind
		MapEventLogic.rollKind = function()
			return kindId
		end
		local ok = tryRun()
		MapEventLogic.rollKind = original
		return ok
	end
	return tryRun()
end

return MapEventService
