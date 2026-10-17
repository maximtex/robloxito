-- Misiones, misiones diarias y logros (lógica en QuestLogic, definiciones en QuestConfig).
-- - El progreso sale SOLO de avisos de servicios del servidor: derrotas con recompensa
--   (EnemyService), energía producida (EnergyService), habilidades de mascota con daño
--   real (PetCombatService) y el estado del perfil (mejora, mascotas, zonas).
-- - Sin bucle propio: se actualiza con el aviso de producción de cada segundo (cambio de
--   día, misiones de estado) y envía el estado solo si ha cambiado, como mucho cada
--   PushInterval segundos (o al momento al reclamar).
-- - Reclamar: validación, límite de frecuencia y marca de "reclamada" antes de sumar la
--   energía, sin pausas entre medias: cada recompensa se concede una sola vez.
-- - Los datos viven en el perfil guardado (PetData.Quests). Aquí solo se marca el perfil
--   como modificado; SaveService/PlayerDataService siguen siendo quienes guardan.
-- - Si los datos no se han cargado (o la carga falló), no se registra ni se concede nada:
--   una carga tardía no puede pisar ni duplicar recompensas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local QuestConfig = require(Shared.Config.QuestConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local PetCombatConfig = require(Shared.Config.PetCombatConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local EnergyService = require(script.Parent.EnergyService)
local PetCombatService = require(script.Parent.PetCombatService)
local QuestLogic = require(script.Parent.Parent.Util.QuestLogic)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Codes = Constants.PurchaseCodes

type Session = {
	Dirty: boolean,
	NextPushAt: number,
	Signature: string,
	Notices: { any },
}

local QuestService = {}

local sessions: { [Player]: Session } = {}
local stateRemote: RemoteEvent
local claimLimiter = RateLimiter.new(QuestConfig.ClaimRateLimit.Cooldown, QuestConfig.ClaimRateLimit.WindowSeconds, QuestConfig.ClaimRateLimit.MaxPerWindow)
local requestLimiter = RateLimiter.new(QuestConfig.RequestRateLimit.Cooldown, QuestConfig.RequestRateLimit.WindowSeconds, QuestConfig.RequestRateLimit.MaxPerWindow)

-- Estado del perfil que usan las misiones (todo del servidor).
local function contextOf(profile: PlayerDataService.Profile): QuestLogic.Context
	local unlocked: { [string]: boolean } = {}
	local purchased = 0
	for zoneId, zone in ZoneConfig.Zones do
		if (zone.UnlockCost or 0) <= 0 then
			unlocked[zoneId] = true -- zonas gratuitas (el Bosque)
		end
	end
	for _, zoneId in profile.PetData.UnlockedZones do
		local zone = ZoneConfig.Zones[zoneId]
		if zone and not unlocked[zoneId] then
			unlocked[zoneId] = true
			purchased += 1
		end
	end
	local combatPets = 0
	for _, entry in profile.PetData.Pets do
		if PetCombatConfig.Abilities[entry.PetId] then
			combatPets += 1
		end
	end
	return {
		UpgradeLevel = profile.UpgradeLevels[QuestConfig.RewardUpgradeId] or 0,
		PetsOwned = #profile.PetData.Pets + #profile.PetData.Archived,
		PetsEquipped = #profile.PetData.Equipped,
		CombatPetsOwned = combatPets,
		ZonesUnlocked = purchased,
		UnlockedZones = unlocked,
	}
end

-- Lo reutiliza TutorialService (mismos datos, una sola definición).
QuestService.contextOf = contextOf

local function signatureOf(ctx: QuestLogic.Context): string
	return ("%d|%d|%d|%d|%d"):format(ctx.UpgradeLevel, ctx.PetsOwned, ctx.PetsEquipped, ctx.CombatPetsOwned, ctx.ZonesUnlocked)
end

local function readyProfile(player: Player): PlayerDataService.Profile?
	local profile = PlayerDataService.get(player)
	if profile and PlayerDataService.isPetDataReady(profile) then
		return profile
	end
	return nil
end

local function sessionOf(player: Player): Session
	local session = sessions[player]
	if not session then
		session = { Dirty = true, NextPushAt = 0, Signature = "", Notices = {} }
		sessions[player] = session
	end
	return session
end

-- Energía de misiones y logros: se suma directamente y NO cuenta como progreso.
local function grant(player: Player, profile: PlayerDataService.Profile, amount: number)
	if amount > 0 then
		profile.Energy += amount
		PlayerDataService.replicate(player)
	end
end

local function today(): number
	return QuestLogic.dayOf(os.time())
end

local function push(player: Player, profile: PlayerDataService.Profile, session: Session, ctx: QuestLogic.Context)
	local state = QuestLogic.snapshot(profile.PetData.Quests, ctx, today())
	state.Notices = session.Notices
	session.Notices = {}
	session.Dirty = false
	session.NextPushAt = os.clock() + QuestConfig.PushInterval
	stateRemote:FireClient(player, state)
end

-- Día nuevo, misiones cumplidas, logros nuevos y envío (si toca).
local function update(player: Player, forcePush: boolean)
	local profile = readyProfile(player)
	if not profile then
		return
	end
	local session = sessionOf(player)
	local data = profile.PetData.Quests
	local ctx = contextOf(profile)
	if QuestLogic.ensureDay(data, today(), player.UserId, ctx) then
		session.Dirty = true
		PlayerDataService.markDirty(player)
	end
	local notices = QuestLogic.evaluate(data, ctx)
	if #notices > 0 then
		for _, notice in notices do
			if notice.Reward and notice.Reward > 0 then
				grant(player, profile, notice.Reward) -- logro con recompensa: solo ahora
			end
			table.insert(session.Notices, notice)
		end
		session.Dirty = true
		PlayerDataService.markDirty(player)
	end
	local signature = signatureOf(ctx)
	if signature ~= session.Signature then
		session.Signature = signature
		session.Dirty = true
	end
	if session.Dirty and (forcePush or os.clock() >= session.NextPushAt) then
		push(player, profile, session, ctx)
	end
end

-- Evento verificado por el servidor -> progreso.
local function record(player: Player, event: any)
	local profile = readyProfile(player)
	if not profile then
		return
	end
	local data = profile.PetData.Quests
	-- Primero el día: un evento justo tras medianoche cuenta para las diarias nuevas.
	QuestLogic.ensureDay(data, today(), player.UserId, contextOf(profile))
	if QuestLogic.record(data, event) then
		sessionOf(player).Dirty = true
		PlayerDataService.markDirty(player)
	end
end

local function claim(player: Player, questId: any): (string, number)
	local profile = readyProfile(player)
	if not profile then
		return Codes.NotReady, 0
	end
	update(player, false) -- día y progreso al día antes de decidir
	local ctx = contextOf(profile)
	local code, amount = QuestLogic.claim(profile.PetData.Quests, questId, ctx)
	if code == "Success" then
		grant(player, profile, amount)
		PlayerDataService.markDirty(player)
		sessionOf(player).Dirty = true
	end
	return code, amount
end

function QuestService.start()
	stateRemote = RemoteService.get(Constants.Remotes.QuestState)
	local requestRemote = RemoteService.get(Constants.Remotes.RequestQuests)
	local claimRemote = RemoteService.get(Constants.Remotes.ClaimQuest)
	local resultRemote = RemoteService.get(Constants.Remotes.QuestResult)

	EnemyService.onDefeated(function(player, info)
		record(player, { Type = "Kill", TypeId = info.TypeId, ZoneId = info.ZoneId })
		if info.Reward > 0 then
			record(player, { Type = "Energy", Amount = info.Reward })
		end
		update(player, false)
	end)
	PetCombatService.onAbilityHit(function(player)
		record(player, { Type = "PetAbility" })
	end)
	-- Cada segundo (con la producción): energía, cambio de día y misiones de estado.
	EnergyService.onProduced(function(player, amount)
		if amount > 0 then
			record(player, { Type = "Energy", Amount = amount })
		end
		update(player, false)
	end)
	PlayerDataService.onPetDataReady(function(player)
		update(player, true)
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

	claimRemote.OnServerEvent:Connect(function(player: Player, questId: any)
		local rate = claimLimiter:check(player)
		if rate == "flood" then
			return
		end
		local safeId = if typeof(questId) == "string" and #questId <= QuestConfig.MaxIdLength then questId else nil
		if rate == "cooldown" then
			resultRemote:FireClient(player, false, Codes.TooFast, safeId)
			return
		end
		local code, amount = claim(player, questId)
		local success = code == "Success"
		resultRemote:FireClient(player, success, code, safeId, if success then amount else nil)
		if success then
			update(player, true)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		claimLimiter:remove(player)
		requestLimiter:remove(player)
	end)
end

return QuestService
