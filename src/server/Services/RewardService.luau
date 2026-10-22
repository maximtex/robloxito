-- Premio diario (racha de 7 días) y códigos canjeables. Todo lo decide el servidor; el
-- cliente solo pide (RewardAction "Claim" o "Redeem" con el texto del código).
-- - Racha y códigos: lógica pura en RewardLogic; premios en RewardConfig y CodesConfig
--   (esta última solo en el servidor).
-- - Premios: energía (N minutos de la producción actual, con mínimo; no cuenta como energía
--   generada), bendiciones (AdventureService, se guardan sin activar) y mascota del mejor
--   huevo que ya pueda abrir (PetService; con el inventario lleno, su precio en energía).
-- - La marca de "reclamado"/"canjeado" va antes que el premio, sin pausas, y se guarda en
--   seguida: no se cobra dos veces aunque lleguen dos solicitudes o se cierre el servidor.
-- - Atributo DailyReady (insignia del menú), al día también al cambiar el día.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local RewardConfig = require(Shared.Config.RewardConfig)
local EggConfig = require(Shared.Config.EggConfig)
local RebirthLogic = require(Shared.RebirthLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local AdventureService = require(script.Parent.AdventureService)
local PetService = require(script.Parent.PetService)
local RewardLogic = require(script.Parent.Parent.Util.RewardLogic)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local CodesConfig = require(script.Parent.Parent.CodesConfig)

local Codes = Constants.PurchaseCodes
local DAY_CHECK_INTERVAL = 30

local RewardService = {}

local claimLimiter = RateLimiter.new(1, 5, 6)
local codeLimiter = RateLimiter.new(RewardConfig.Codes.Cooldown, 60, RewardConfig.Codes.MaxPerMinute)
local requestLimiter = RateLimiter.new(0.5, 5, 10)
local stateRemote: any
local resultRemote: any

-- Hora del servidor (las pruebas la cambian).
local clock = {
	now = function(): number
		return os.time()
	end,
}

function RewardService.setClock(now: () -> number)
	clock.now = now
end

local function readyProfile(player: Player): PlayerDataService.Profile?
	local profile = PlayerDataService.get(player)
	if profile and PlayerDataService.isPetDataReady(profile) then
		return profile
	end
	return nil
end

local function snapshotOf(profile: PlayerDataService.Profile?): any
	if not profile then
		return { Ready = false }
	end
	return RewardLogic.snapshot(profile.PetData.Rewards, clock.now(), profile.ProductionPerSecond)
end

local function refreshAttribute(player: Player, profile: PlayerDataService.Profile?)
	local ready = false
	if profile then
		ready = RewardLogic.status(profile.PetData.Rewards, RewardLogic.dayOf(clock.now())).CanClaim
	end
	if player:GetAttribute(Constants.Attributes.DailyReady) ~= ready then
		player:SetAttribute(Constants.Attributes.DailyReady, ready)
	end
end

local function push(player: Player)
	local profile = readyProfile(player)
	refreshAttribute(player, profile)
	if stateRemote then
		stateRemote:FireClient(player, snapshotOf(profile))
	end
end
RewardService.push = push

-- Concede un premio (formato de RewardConfig). Devuelve lo concedido, para el cliente.
local function grant(player: Player, profile: PlayerDataService.Profile, reward: any): any
	local detail: any = {}
	if type(reward) ~= "table" then
		return detail
	end
	local energy = 0
	if reward.Energy then
		energy += RewardLogic.energyAmount(reward.Energy, profile.ProductionPerSecond)
	end
	if reward.Blessings then
		local added = AdventureService.grantBlessings(player, reward.Blessings)
		if next(added) ~= nil then
			detail.Blessings = added
		end
	end
	if reward.Pet then
		local code, pet, eggId = PetService.grantFreePet(player)
		if code == Codes.Success and pet then
			detail.PetId = pet.PetId
			detail.EggId = eggId
		elseif code == Codes.InventoryFull and eggId and EggConfig.Eggs[eggId] then
			-- Inventario lleno: su precio en energía, para no perder el premio.
			energy += EggConfig.Eggs[eggId].Cost
			detail.InventoryFull = true
			detail.EggId = eggId
		end
	end
	if energy > 0 then
		profile.Energy += energy
		detail.Energy = energy
	end
	PlayerDataService.replicate(player)
	PlayerDataService.markDirty(player)
	PlayerDataService.saveNow(player)
	return detail
end

-- Acciones ------------------------------------------------------------------------------------

function RewardService.claim(player: Player): (string, any)
	local profile = readyProfile(player)
	if not profile then
		return Codes.NotReady, nil
	end
	local code, day = RewardLogic.claim(profile.PetData.Rewards, RewardLogic.dayOf(clock.now()))
	if code ~= "Success" or not day then
		return Codes[code] or Codes.InvalidRequest, nil
	end
	local detail = grant(player, profile, RewardLogic.streakReward(day))
	detail.Day = day
	detail.Streak = profile.PetData.Rewards.Streak
	return Codes.Success, detail
end

function RewardService.redeem(player: Player, text: any): (string, any)
	local profile = readyProfile(player)
	if not profile then
		return Codes.NotReady, nil
	end
	local rebirths = RebirthLogic.count(RebirthLogic.ofProfile(profile))
	local code, result, codeKey = RewardLogic.redeem(profile.PetData.Rewards, CodesConfig, text, clock.now(), rebirths)
	if code ~= "Success" then
		return Codes[code] or Codes.InvalidRequest, if code == "RebirthLocked" then { Required = result } else nil
	end
	local detail = grant(player, profile, result.Reward)
	detail.Code = codeKey
	return Codes.Success, detail
end

-- Arranque ------------------------------------------------------------------------------------

function RewardService.start()
	stateRemote = RemoteService.get(Constants.Remotes.RewardState)
	resultRemote = RemoteService.get(Constants.Remotes.RewardResult)
	local requestRemote = RemoteService.get(Constants.Remotes.RequestRewards)
	local actionRemote = RemoteService.get(Constants.Remotes.RewardAction)

	requestRemote.OnServerEvent:Connect(function(player: Player)
		if requestLimiter:check(player) == "ok" then
			push(player)
		end
	end)

	actionRemote.OnServerEvent:Connect(function(player: Player, action: any, arg: any)
		if action == "Claim" then
			local rate = claimLimiter:check(player)
			if rate == "flood" then
				return
			elseif rate == "cooldown" then
				resultRemote:FireClient(player, false, Codes.TooFast, "Claim", nil)
				return
			end
			local code, detail = RewardService.claim(player)
			resultRemote:FireClient(player, code == Codes.Success, code, "Claim", detail)
			push(player)
		elseif action == "Redeem" then
			local rate = codeLimiter:check(player)
			if rate == "flood" then
				resultRemote:FireClient(player, false, Codes.TooFast, "Redeem", nil)
				return
			elseif rate == "cooldown" then
				resultRemote:FireClient(player, false, Codes.TooFast, "Redeem", nil)
				return
			end
			local code, detail = RewardService.redeem(player, arg)
			resultRemote:FireClient(player, code == Codes.Success, code, "Redeem", detail)
			if code == Codes.Success then
				push(player)
			end
		end
	end)

	PlayerDataService.onPetDataReady(push)

	-- Cambio de día: la insignia se enciende sola (sin esperar a que el jugador pida nada).
	task.spawn(function()
		local lastDay = RewardLogic.dayOf(clock.now())
		while true do
			task.wait(DAY_CHECK_INTERVAL)
			local today = RewardLogic.dayOf(clock.now())
			for _, player in Players:GetPlayers() do
				refreshAttribute(player, readyProfile(player))
			end
			if today ~= lastDay then
				lastDay = today
				for _, player in Players:GetPlayers() do
					push(player)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		claimLimiter:remove(player)
		codeLimiter:remove(player)
		requestLimiter:remove(player)
	end)
end

return RewardService
