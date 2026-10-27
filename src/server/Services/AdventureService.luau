-- Aventuras opcionales (lógica en AdventureLogic, datos en AdventureConfig): personajes con
-- historias de tres misiones, objetos perdidos, amuletos y bendiciones. Todo lo decide el
-- servidor; el cliente solo pide.
-- - Hablar: el aviso de proximidad de cada personaje (NpcService) llama a interact().
--   Si el jugador llevaba un encargo para ese personaje, se entrega en ese momento.
-- - Acciones (remote AdventureAction): Accept / TurnIn junto al personaje (distancia
--   comprobada aquí), Equip / Unequip de amuletos y UseBlessing. Límite de frecuencia.
-- - Progreso SOLO de eventos del servidor: derrotas con recompensa (EnemyService),
--   conversaciones (interact) y objetos recogidos al pasar cerca (bucle de este servicio,
--   con las posiciones que da NpcService).
-- - Recompensas al entregar: 💰 (min(Min · factor de la zona del personaje, Max):
--   AdventureConfig.ZoneMoneyFactor), bendición y, al final de cada historia, el
--   amuleto. La marca de "entregada" va antes que la recompensa, sin pausas.
-- - Pasivas: los atributos se recalculan al cambiar amuletos o bendiciones (y cuando una
--   bendición caduca); los 💎 los multiplica PlayerDataService.diamondMultiplier; el daño y el botín los leen CombatService, AbilityService,
--   PetCombatService y EnemyService con AdventureLogic; la velocidad se aplica al
--   Humanoid (atributo BaseWalkSpeed, que respeta también el Vendaval).
-- - Los datos viven en el perfil guardado (PetData.Adventure). Sin datos cargados no se
--   registra ni se concede nada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local AdventureConfig = require(Shared.Config.AdventureConfig)
local AdventureLogic = require(Shared.AdventureLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Codes = Constants.PurchaseCodes
local ACTIONS = { Accept = true, TurnIn = true, Equip = true, Unequip = true, UseBlessing = true }
local COLLECT_INTERVAL = 0.25
local PRUNE_INTERVAL = 1
local PENDANT_NAME = "AdventureAmulet"

type Session = { Dirty: boolean, NextPushAt: number, Notices: { any } }

local AdventureService = {}

local sessions: { [Player]: Session } = {}
local stateRemote: any
local dialogRemote: any
local actionLimiter = RateLimiter.new(AdventureConfig.ActionRateLimit.Cooldown, AdventureConfig.ActionRateLimit.WindowSeconds, AdventureConfig.ActionRateLimit.MaxPerWindow)
local requestLimiter = RateLimiter.new(AdventureConfig.RequestRateLimit.Cooldown, AdventureConfig.RequestRateLimit.WindowSeconds, AdventureConfig.RequestRateLimit.MaxPerWindow)

-- Posiciones del mundo (las da NpcService; las pruebas ponen las suyas).
local world = {
	npcPosition = function(_npcId: string): any
		return nil
	end,
	itemPosition = function(_itemId: string): any
		return nil
	end,
	playerPosition = function(player: Player): any
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root.Position else nil
	end,
}

function AdventureService.setWorld(overrides: { [string]: any })
	for key, value in overrides do
		(world :: any)[key] = value
	end
end

-- Utilidades ----------------------------------------------------------------------------------

local function readyProfile(player: Player): PlayerDataService.Profile?
	local profile = PlayerDataService.get(player)
	if profile and PlayerDataService.isPetDataReady(profile) then
		return profile
	end
	return nil
end

local function dataOf(profile: PlayerDataService.Profile): AdventureLogic.AdventureData
	return profile.PetData.Adventure
end

local function sessionOf(player: Player): Session
	local session = sessions[player]
	if not session then
		session = { Dirty = true, NextPushAt = 0, Notices = {} }
		sessions[player] = session
	end
	return session
end

-- Distancias por componentes (valen con Vector3 y con las tablas de las pruebas).
local function distance(a: any, b: any): number
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function flatDistance(a: any, b: any): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function isNear(player: Player, npcId: string): boolean
	local position = world.playerPosition(player)
	local npc = world.npcPosition(npcId)
	return position ~= nil and npc ~= nil and distance(position, npc) <= AdventureConfig.InteractDistance
end

-- Factor del 💰 de las misiones de un personaje: el de su zona (AdventureConfig.ZoneMoneyFactor).
local function moneyFactor(npcId: string): number
	local npc = AdventureConfig.Npcs[npcId]
	return (npc and AdventureConfig.ZoneMoneyFactor[npc.Zone]) or 1
end

-- 💰 del paso actual de cada personaje (para mostrarlo antes de aceptar).
local function rewardsOf(profile: PlayerDataService.Profile): { [string]: number }
	local data = dataOf(profile)
	local rewards = {}
	for _, npcId in AdventureLogic.npcOrder() do
		local state = AdventureLogic.state(data, npcId)
		local step = AdventureLogic.stepOf(npcId, state.Step)
		rewards[npcId] = if step then AdventureLogic.rewardMoney(step, moneyFactor(npcId)) else 0
	end
	return rewards
end

local function push(player: Player, profile: PlayerDataService.Profile, session: Session)
	local state = AdventureLogic.snapshot(dataOf(profile), os.time(), rewardsOf(profile))
	state.Notices = session.Notices
	session.Notices = {}
	session.Dirty = false
	session.NextPushAt = os.clock() + AdventureConfig.PushInterval
	stateRemote:FireClient(player, state)
end

-- Envía el estado si cambió (como mucho cada PushInterval, salvo `force`).
local function update(player: Player, force: boolean)
	local profile = readyProfile(player)
	if not profile then
		return
	end
	local session = sessionOf(player)
	if session.Dirty and (force or os.clock() >= session.NextPushAt) then
		push(player, profile, session)
	end
end

local function noteChanges(player: Player, session: Session, changes: { any })
	for _, change in changes do
		table.insert(session.Notices, { Type = "Progress", Npc = change.Npc, Progress = change.Progress, Target = change.Target, Ready = change.Ready })
	end
	if #changes > 0 then
		session.Dirty = true
		PlayerDataService.markDirty(player)
	end
end

-- Pasivas en el personaje ----------------------------------------------------------------------

-- Colgante del primer amuleto puesto (lo ven todos). Decorativo, sin colisión ni masa.
local function setPendant(character: Model, amuletId: string?)
	local existing = character:FindFirstChild(PENDANT_NAME)
	if existing then
		existing:Destroy()
	end
	local amulet = amuletId and AdventureConfig.Amulets[amuletId]
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not amulet or not torso or not torso:IsA("BasePart") then
		return
	end
	local model = Instance.new("Model")
	model.Name = PENDANT_NAME
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = material
		if shape then
			part.Shape = shape
		end
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.CFrame = torso.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
		return part
	end
	local front = -torso.Size.Z / 2 - 0.06
	piece("Cord", Vector3.new(0.06, 0.06, 0.06), CFrame.new(0, 0.2, front), Color3.fromRGB(110, 80, 50), Enum.Material.Fabric)
	piece("Setting", Vector3.new(0.12, 0.46, 0.46), CFrame.new(0, -0.05, front) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(236, 200, 120), Enum.Material.Metal, Enum.PartType.Cylinder)
	local gem = piece("Gem", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, -0.05, front - 0.06) * CFrame.Angles(0, 0, math.rad(45)), amulet.Color, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = amulet.Color
	light.Range = 5
	light.Brightness = 0.6
	light.Shadows = false
	light.Parent = gem
	model.Parent = character
end

local function applyCharacter(player: Player, profile: PlayerDataService.Profile)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end
	local data = dataOf(profile)
	local speedLvl = (profile.UpgradeLevels and profile.UpgradeLevels.WalkSpeed) or 0
	local base = (28 + speedLvl * 2.5) * AdventureLogic.walkSpeedMultiplier(data)
	local previous = humanoid:GetAttribute("BaseWalkSpeed")
	humanoid:SetAttribute("BaseWalkSpeed", base)
	-- Si hay otro efecto de velocidad en curso (Vendaval), él la devuelve a la base al acabar.
	if typeof(previous) ~= "number" or math.abs(humanoid.WalkSpeed - previous) < 0.01 or math.abs(humanoid.WalkSpeed - StarterPlayer.CharacterWalkSpeed) < 0.01 then
		humanoid.WalkSpeed = base
	end
	local first = nil
	for slot = 1, AdventureLogic.slots(data) do
		local amuletId = data.Equipped[slot]
		if amuletId and amuletId ~= "" and AdventureConfig.Amulets[amuletId] then
			first = amuletId
			break
		end
	end
	setPendant(character, first)
end

-- Atributos (amuletos y bendiciones) y personaje al día.
local function refreshPassives(player: Player, profile: PlayerDataService.Profile)
	PlayerDataService.refreshStats(player)
	PlayerDataService.replicate(player)
	-- Lo visual nunca debe impedir que la acción termine.
	local ok, problem = pcall(applyCharacter, player, profile)
	if not ok then
		warn("[AdventureService] No se pudo aplicar la pasiva al personaje: " .. tostring(problem))
	end
end

-- Acciones ------------------------------------------------------------------------------------

-- Hablar con un personaje (aviso de proximidad). Entrega los encargos para él y abre la
-- conversación en el cliente con el estado al día.
function AdventureService.interact(player: Player, npcId: any): string
	if type(npcId) ~= "string" or not AdventureConfig.Npcs[npcId] then
		return Codes.InvalidRequest
	end
	local profile = readyProfile(player)
	if not profile then
		return Codes.NotReady
	end
	if not isNear(player, npcId) then
		return Codes.TooFar
	end
	local session = sessionOf(player)
	local changes = AdventureLogic.record(dataOf(profile), { Type = "Talk", NpcId = npcId })
	noteChanges(player, session, changes)
	session.Dirty = true
	push(player, profile, session)
	dialogRemote:FireClient(player, npcId, if changes[1] then changes[1].Npc else nil)
	return Codes.Success
end

local function codeOf(logicCode: string): string
	return Codes[logicCode] or Codes.InvalidRequest
end

function AdventureService.act(player: Player, action: any, arg1: any, arg2: any): (string, any)
	if type(action) ~= "string" or not ACTIONS[action] then
		return Codes.InvalidRequest, nil
	end
	local profile = readyProfile(player)
	if not profile then
		return Codes.NotReady, nil
	end
	local data = dataOf(profile)
	local session = sessionOf(player)

	if action == "Accept" or action == "TurnIn" then
		if type(arg1) ~= "string" or not AdventureConfig.Npcs[arg1] then
			return Codes.InvalidRequest, nil
		end
		if not isNear(player, arg1) then
			return Codes.TooFar, { Npc = arg1 }
		end
		if action == "Accept" then
			local code = AdventureLogic.accept(data, arg1)
			if code == "Success" then
				session.Dirty = true
				PlayerDataService.markDirty(player)
			end
			return codeOf(code), { Npc = arg1 }
		end
		local slotsBefore = AdventureLogic.slots(data)
		local code, step, stepIndex = AdventureLogic.turnIn(data, arg1)
		if code ~= "Success" then
			return codeOf(code), { Npc = arg1 }
		end
		local money = AdventureLogic.rewardMoney(step, moneyFactor(arg1))
		if money > 0 then
			profile.Money += money
		end
		local detail = {
			Npc = arg1,
			Step = stepIndex,
			Money = money,
			Blessing = step.Reward.Blessing,
			Amulet = step.Reward.Amulet,
			Finished = AdventureLogic.isComplete(data, arg1),
			AllDone = AdventureLogic.allComplete(data),
			SlotOpened = AdventureLogic.slots(data) > slotsBefore, -- se abrió la 2.ª ranura
		}
		table.insert(session.Notices, { Type = "Reward", Npc = arg1, Step = stepIndex, Money = money, Blessing = detail.Blessing, Amulet = detail.Amulet, Finished = detail.Finished, AllDone = detail.AllDone, SlotOpened = detail.SlotOpened })
		session.Dirty = true
		PlayerDataService.markDirty(player)
		refreshPassives(player, profile) -- energía y, si llegó un amuleto (se pone solo), su pasiva
		PlayerDataService.saveNow(player)
		return Codes.Success, detail
	end

	local code, detail
	if action == "Equip" then
		code = AdventureLogic.equip(data, arg1, arg2)
		detail = { Amulet = arg1 }
	elseif action == "Unequip" then
		code = AdventureLogic.unequip(data, arg1)
		detail = { Slot = arg1 }
	else -- UseBlessing
		local expires
		code, expires = AdventureLogic.useBlessing(data, arg1, os.time())
		detail = { Blessing = arg1, ExpiresAt = expires }
	end
	if code == "Success" then
		session.Dirty = true
		PlayerDataService.markDirty(player)
		refreshPassives(player, profile)
	end
	return codeOf(code), detail
end

-- Objetos perdidos al alcance del jugador -> recogidos. Devuelve cuántos.
function AdventureService.collectNearby(player: Player): number
	local profile = readyProfile(player)
	if not profile then
		return 0
	end
	local data = dataOf(profile)
	local pending = AdventureLogic.pendingItems(data)
	if #pending == 0 then
		return 0
	end
	local position = world.playerPosition(player)
	if not position then
		return 0
	end
	local session = sessionOf(player)
	local collected = 0
	for _, itemId in pending do
		local itemPosition = world.itemPosition(itemId)
		if itemPosition and flatDistance(position, itemPosition) <= AdventureConfig.CollectRadius and math.abs(position.Y - itemPosition.Y) <= AdventureConfig.CollectHeight then
			local changes = AdventureLogic.record(data, { Type = "Collect", ItemId = itemId })
			if #changes > 0 then
				collected += 1
				table.insert(session.Notices, { Type = "Found", Item = itemId })
				noteChanges(player, session, changes)
			end
		end
	end
	if collected > 0 then
		update(player, true)
	end
	return collected
end

-- Bendiciones regaladas (premio diario, códigos): se guardan sin activar y el panel de
-- amuletos se actualiza en seguida. Devuelve las que se sumaron.
function AdventureService.grantBlessings(player: Player, blessings: any): { [string]: number }
	local profile = readyProfile(player)
	if not profile then
		return {}
	end
	local added = AdventureLogic.addBlessings(dataOf(profile), blessings)
	if next(added) ~= nil then
		local session = sessionOf(player)
		session.Dirty = true
		PlayerDataService.markDirty(player)
		update(player, true)
	end
	return added
end

-- Bendiciones caducadas: atributos al día. Devuelve true si alguna terminó.
function AdventureService.prune(player: Player): boolean
	local profile = readyProfile(player)
	if not profile then
		return false
	end
	if AdventureLogic.prune(dataOf(profile), os.time()) then
		local session = sessionOf(player)
		table.insert(session.Notices, { Type = "BlessingEnded" })
		session.Dirty = true
		PlayerDataService.markDirty(player)
		refreshPassives(player, profile)
		return true
	end
	return false
end

-- Arranque ------------------------------------------------------------------------------------

function AdventureService.start()
	local ok, problems = AdventureLogic.validateConfig()
	if not ok then
		warn("[AdventureService] AdventureConfig con problemas: " .. table.concat(problems, "; "))
	end

	stateRemote = RemoteService.get(Constants.Remotes.AdventureState)
	dialogRemote = RemoteService.get(Constants.Remotes.AdventureDialog)
	local requestRemote = RemoteService.get(Constants.Remotes.RequestAdventure)
	local actionRemote = RemoteService.get(Constants.Remotes.AdventureAction)
	local resultRemote = RemoteService.get(Constants.Remotes.AdventureResult)

	EnemyService.onDefeated(function(player, info)
		local profile = readyProfile(player)
		if not profile then
			return
		end
		local changes = AdventureLogic.record(dataOf(profile), { Type = "Kill", TypeId = info.TypeId, ZoneId = info.ZoneId })
		if #changes > 0 then
			noteChanges(player, sessionOf(player), changes)
			update(player, true)
		end
	end)

	PlayerDataService.onPetDataReady(function(player)
		local profile = readyProfile(player)
		if profile then
			AdventureLogic.prune(dataOf(profile), os.time())
			refreshPassives(player, profile)
			sessionOf(player).Dirty = true
			update(player, true)
		end
	end)

	requestRemote.OnServerEvent:Connect(function(player: Player)
		if requestLimiter:check(player) ~= "ok" then
			return
		end
		local profile = readyProfile(player)
		if profile then
			sessionOf(player).Dirty = true
			update(player, true)
		else
			stateRemote:FireClient(player, { Ready = false })
		end
	end)

	actionRemote.OnServerEvent:Connect(function(player: Player, action: any, arg1: any, arg2: any)
		local rate = actionLimiter:check(player)
		if rate == "flood" then
			return
		end
		local safeAction = if type(action) == "string" and ACTIONS[action] then action else nil
		if rate == "cooldown" then
			resultRemote:FireClient(player, false, Codes.TooFast, safeAction, nil)
			return
		end
		local code, detail = AdventureService.act(player, action, arg1, arg2)
		-- Primero el estado y luego el resultado: el cliente ya tiene los datos nuevos al
		-- recibir la confirmación.
		update(player, true)
		resultRemote:FireClient(player, code == Codes.Success, code, safeAction, detail)
	end)

	local function watchCharacter(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			local profile = readyProfile(player)
			if profile then
				applyCharacter(player, profile)
			end
		end)
	end
	Players.PlayerAdded:Connect(watchCharacter)
	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		actionLimiter:remove(player)
		requestLimiter:remove(player)
	end)

	-- Objetos perdidos (cada cuarto de segundo) y bendiciones caducadas (cada segundo).
	task.spawn(function()
		local sincePrune = 0
		while true do
			task.wait(COLLECT_INTERVAL)
			sincePrune += COLLECT_INTERVAL
			local prune = sincePrune >= PRUNE_INTERVAL
			if prune then
				sincePrune = 0
			end
			for _, player in Players:GetPlayers() do
				AdventureService.collectNearby(player)
				if prune then
					AdventureService.prune(player)
					update(player, false)
				end
			end
		end
	end)
end

return AdventureService
