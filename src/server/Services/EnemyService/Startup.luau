-- EnemyService · Startup: arranque (start): carpetas, grupos de colisión, enemigos de cada zona y bucle de la IA.
-- Parte de EnemyService (ver EnemyService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local CaveConfig = require(Shared.Config.CaveConfig)
local CaveLogic = require(Shared.CaveLogic)
local WaveConfig = require(Shared.Config.WaveConfig)
local RemoteService = require(script.Parent.Parent.RemoteService)
local PartFactory = require(script.Parent.Parent.Parent.Util.PartFactory)

local ctx: any -- tabla de estado compartida (la crea EnemyService/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a EnemyService)
local ARENAS_NAME: any
local CHARACTER_GROUP: any
local FOLDER_NAME: any
local WAVE_GROUP: any
local WAVE_SLOT_PREFIX: any
local bossByZone: any
local eliteCount: any
local enemies: any
local streaks: any

-- Funciones de las otras partes
local function createEnemy(...) return ctx.createEnemy(...) end
local function dressVariant(...) return ctx.dressVariant(...) end
local function inSafeArea(...) return ctx.inSafeArea(...) end
local function makeElite(...) return ctx.makeElite(...) end
local function place(...) return ctx.place(...) end
local function safeAreasOf(...) return ctx.safeAreasOf(...) end
local function scaleEnemy(...) return ctx.scaleEnemy(...) end
local function setCollisionGroup(...) return ctx.setCollisionGroup(...) end
local function strengthen(...) return ctx.strengthen(...) end
local function updateBoss(...) return ctx.updateBoss(...) end
local function updateEnemy(...) return ctx.updateEnemy(...) end
local function zoneCenter(...) return ctx.zoneCenter(...) end

function Api.start()
	PartFactory.removeExisting(workspace, FOLDER_NAME)
	PartFactory.removeExisting(workspace, ARENAS_NAME)
	ctx.folder = Instance.new("Folder")
	ctx.folder.Name = FOLDER_NAME
	ctx.folder.Parent = workspace
	ctx.fxFolder = PartFactory.folder(ctx.folder, "Effects")
	local arenas = Instance.new("Folder")
	arenas.Name = ARENAS_NAME
	arenas.Parent = workspace
	ctx.rewardRemote = RemoteService.get(Constants.Remotes.CombatReward)

	-- Oleadas privadas: los enemigos de las partidas no chocan con los personajes ni con los
	-- de otras partidas (así nadie tropieza con enemigos que no ve); los de una misma partida
	-- sí chocan entre ellos.
	local function register(group: string): boolean
		local ok, err = pcall(function()
			if not PhysicsService:IsCollisionGroupRegistered(group) then
				PhysicsService:RegisterCollisionGroup(group)
			end
		end)
		if not ok then
			warn("[EnemyService] Grupo de colisión " .. group .. ": " .. tostring(err))
		end
		return ok
	end
	register(WAVE_GROUP)
	register(CHARACTER_GROUP)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(WAVE_GROUP, WAVE_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(WAVE_GROUP, CHARACTER_GROUP, false)
	end)
	for slot = 1, math.max(1, WaveConfig.MaxRuns) do
		if not register(WAVE_SLOT_PREFIX .. slot) then
			break
		end
		ctx.waveSlots = slot
	end
	pcall(function()
		for slot = 1, ctx.waveSlots do
			local group = WAVE_SLOT_PREFIX .. slot
			PhysicsService:CollisionGroupSetCollidable(group, CHARACTER_GROUP, false)
			PhysicsService:CollisionGroupSetCollidable(group, WAVE_GROUP, false)
			for other = slot + 1, ctx.waveSlots do
				PhysicsService:CollisionGroupSetCollidable(group, WAVE_SLOT_PREFIX .. other, false)
			end
		end
	end)
	local function watchCharacter(character: Model)
		setCollisionGroup(character, CHARACTER_GROUP)
		character.DescendantAdded:Connect(function(part)
			if part:IsA("BasePart") then
				part.CollisionGroup = CHARACTER_GROUP
			end
		end)
	end
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(watchCharacter)
		if player.Character then
			watchCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	-- Enemigos repartidos por las zonas.
	for zoneId, zoneSettings in EnemyConfig.Zones do
		if not ZoneConfig.Zones[zoneId] then
			continue
		end
		PartFactory.folder(ctx.folder, zoneId)
		local center = zoneCenter(zoneId)
		local safeAreas = safeAreasOf(zoneId, zoneSettings)
		for _, spawn in zoneSettings.Spawns do
			local home = center + Vector3.new(spawn.Offset.X, 0, spawn.Offset.Y)
			-- En una zona sin monstruos no aparece ninguno, aunque la configuración lo pida
			if inSafeArea(safeAreas, home) then
				warn(("[EnemyService] %s en %s cae en una zona sin monstruos (SafeAreas): no se crea."):format(spawn.Type, tostring(home)))
				continue
			end
			local enemy = createEnemy(zoneId, spawn.Type, home, zoneSettings, nil, nil)
			-- Los de las mazmorras (lejos del mapa): más vida, más daño y más botín, y en las del
			-- Valle y la Caldera algunos de los pequeños son élite (los medianos no: el más duro
			-- de su sala es el mini-jefe)
			local caveId, cave = CaveLogic.caveAt(home.X, home.Z)
			if enemy and cave then
				local strength = cave.Strength or {}
				strengthen(enemy, strength.Health, strength.Damage, strength.Reward)
				enemy.Model:SetAttribute("Cave", caveId)
				local every = if cave.EliteChance and cave.EliteChance > 0 then math.max(1, math.round(1 / cave.EliteChance)) else 0
				if every > 0 and enemy.Kind == "Normal" then
					eliteCount[caveId] = (eliteCount[caveId] or 0) + 1
				end
				if every > 0 and enemy.Kind == "Normal" and eliteCount[caveId] % every == 0 then
					local elite = EnemyConfig.Elite
					strengthen(enemy, elite.Health, elite.Damage, elite.Reward)
					makeElite(enemy)
					place(enemy) -- de nuevo, ya con su tamaño
				end
			end
		end
		local boss = zoneSettings.Boss
		if boss then
			local arenaCenter = center + Vector3.new(boss.Arena.Center.X, 0, boss.Arena.Center.Y)
			local enemy = createEnemy(zoneId, boss.Type, arenaCenter, zoneSettings, arenaCenter, boss.Arena.Radius)
			if enemy then
				-- Jefes más grandes que su modelo (Scale: el Rey Goblin es enorme)
				local scale = enemy.Def.Scale
				if type(scale) == "number" and scale > 0 and scale ~= 1 then
					scaleEnemy(enemy, scale)
					place(enemy)
				end
				enemy.Model:SetAttribute("ArenaCenter", arenaCenter)
				enemy.Model:SetAttribute("ArenaRadius", boss.Arena.Radius)
				enemy.Model:SetAttribute("ArenaName", boss.Arena.Name)
				bossByZone[zoneId] = enemy
			end
		end
	end

	-- Mini-jefes de las mazmorras (CaveConfig.Caves.*.MiniBoss): uno en la sala 2 de cada una
	-- que lo tenga; abre la puerta del altar (CaveService). Reaparece como los demás.
	for caveId, cave in CaveConfig.Caves do
		local spec = cave.MiniBoss
		local zoneSettings = EnemyConfig.Zones[cave.Zone]
		if not (spec and zoneSettings and ZoneConfig.Zones[cave.Zone]) then
			continue
		end
		local center = zoneCenter(cave.Zone)
		local home = Vector3.new(spec.Position.X, center.Y, spec.Position.Z)
		local enemy = createEnemy(cave.Zone, spec.Type, home, zoneSettings, nil, nil)
		if enemy then
			local strength = cave.Strength or {}
			strengthen(enemy, (strength.Health or 1) * (spec.Health or 1), (strength.Damage or 1) * (spec.Damage or 1), (strength.Reward or 1) * (spec.Reward or 1))
			enemy.Model:SetAttribute("Cave", caveId)
			dressVariant(enemy, "MiniBoss", spec.Scale, cave.Theme and cave.Theme.Portal or Color3.fromRGB(255, 200, 80), spec.Name)
			place(enemy) -- de nuevo, ya con su tamaño
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		streaks[player] = nil
	end)

	-- Un único bucle de IA para todos los enemigos.
	task.spawn(function()
		while true do
			task.wait(EnemyConfig.AiTickSeconds)
			local now = os.clock()
			for _, enemy in enemies do
				local ok, err = pcall(if enemy.Brain then updateBoss else updateEnemy, enemy, now)
				if not ok then
					warn("[EnemyService] Error en la IA de " .. enemy.TypeId .. ": " .. tostring(err))
				end
			end
		end
	end)
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	ARENAS_NAME = context.ARENAS_NAME
	CHARACTER_GROUP = context.CHARACTER_GROUP
	FOLDER_NAME = context.FOLDER_NAME
	WAVE_GROUP = context.WAVE_GROUP
	WAVE_SLOT_PREFIX = context.WAVE_SLOT_PREFIX
	bossByZone = context.bossByZone
	eliteCount = context.eliteCount
	enemies = context.enemies
	streaks = context.streaks
end

return Part
