-- WaveService · Spawns: premios de cada jugador y enemigos de la partida (aparición y retirada).
-- Parte de WaveService (ver WaveService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WaveConfig = require(Shared.Config.WaveConfig)
local WaveLogic = require(Shared.WaveLogic)
local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local EnemyService = require(script.Parent.Parent.EnemyService)
local DiamondService = require(script.Parent.Parent.DiamondService)
local Types = require(script.Parent.Types)
type Participant = Types.Participant
type Run = Types.Run

local ctx: any -- tabla de estado compartida (la crea WaveService/init.luau)
local INSIDE_SLACK: any
local places: any

-- Funciones de las otras partes
local function isInside(...) return ctx.isInside(...) end
local function onEnemyDeath(...) return ctx.onEnemyDeath(...) end

-- Premios -------------------------------------------------------------------------------

local function pay(participant: Participant, diamonds: number, money: number): (number, number)
	local profile = PlayerDataService.get(participant.Player)
	if not profile then
		return 0, 0
	end
	-- Pase Diamantes ×2, Poción de Diamantes y aventuras: también multiplican los 💎 de los
	-- premios de las oleadas.
	local given = DiamondService.grant(participant.Player, diamonds * PlayerDataService.diamondMultiplier(profile))
	local coins = math.max(0, math.floor(money))
	if coins > 0 then
		profile.Money += coins
		PlayerDataService.replicate(participant.Player)
	end
	participant.Diamonds += given
	participant.Money += coins
	return given, coins
end

-- Enemigos de la partida -----------------------------------------------------------------


local function spawnPoint(run: Run): Vector3
	-- La cueva: por uno de sus sitios de la sala, al azar
	local place = places[run.PlaceId]
	local points = place and place.SpawnPoints
	if points and #points > 0 then
		local point = points[math.random(1, #points)]
		local jitter = place.SpawnJitter
		local x = run.Center.X + point.X + (math.random() * 2 - 1) * jitter
		local z = run.Center.Z + point.Y + (math.random() * 2 - 1) * jitter
		return Vector3.new(x, run.Center.Y, z)
	end
	local radius = WaveConfig.Place.SpawnRadius
	local angle = math.random() * math.pi * 2
	local distance = radius.Min + math.random() * (radius.Max - radius.Min)
	return run.Center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- `allowElite`: las hordas pueden sacar élites (la escolta del jefe no).
local function spawnOne(run: Run, typeId: string, wave: number, allowElite: boolean?): boolean
	local area = WaveConfig.Place.AreaRadius
	local place = places[run.PlaceId]
	local leash = (place and place.LeashRadius) or (area + INSIDE_SLACK + 2)
	local options = {
		LeashCenter = run.Center,
		LeashRadius = leash,
		DetectRange = math.max(area * 2.5, leash * 1.6),
		HealthMultiplier = WaveLogic.healthMultiplier(wave, run.Players),
		RewardMultiplier = WaveLogic.rewardMultiplier(wave),
		PoolLimit = (run.Arena.Pool and run.Arena.Pool[typeId]) or 12,
		OnDeath = onEnemyDeath(run, run.Id),
		Run = run.Id,
		MoneyMultiplier = WaveConfig.MoneyMultiplier,
		DamageMultiplier = WaveLogic.damageMultiplier(wave),
		CollisionSlot = run.Slot,
	}
	local position = spawnPoint(run)
	local enemy = nil
	if allowElite and WaveLogic.isElite(run.ArenaId, math.random()) then
		local eliteOptions = table.clone(options)
		eliteOptions.Elite = true
		eliteOptions.PoolLimit = run.Arena.EliteMax or 4
		enemy = EnemyService.spawnPooled(run.ZoneId, typeId, position, eliteOptions)
	end
	enemy = enemy or EnemyService.spawnPooled(run.ZoneId, typeId, position, options)
	if not enemy then
		return false
	end
	run.Alive[enemy] = true
	run.AliveCount += 1
	return true
end

local function despawnAll(run: Run)
	for enemy in run.Alive do
		EnemyService.despawn(enemy)
	end
	table.clear(run.Alive)
	run.AliveCount = 0
	table.clear(run.Queue)
	for _, boss in run.Bosses do
		if EnemyService.isAlive(boss) then
			EnemyService.despawn(boss)
		end
	end
	table.clear(run.Bosses)
end

local function insideCount(run: Run): number
	local count = 0
	for player in run.Participants do
		if isInside(run, player) then
			count += 1
		end
	end
	return math.max(1, count)
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.despawnAll = despawnAll
	context.insideCount = insideCount
	context.pay = pay
	context.spawnOne = spawnOne
end

function Part.link(context: any)
	INSIDE_SLACK = context.INSIDE_SLACK
	places = context.places
end

return Part
