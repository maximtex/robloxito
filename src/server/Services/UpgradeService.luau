-- Procesa compras de mejoras. Toda la validación ocurre aquí:
-- tipo de argumento, mejora existente, nivel máximo, saldo y límite de frecuencia.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Constants = require(Shared.Constants)
local Economy = require(Shared.Economy)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)

local Codes = Constants.PurchaseCodes
local RateLimit = EconomyConfig.PurchaseRateLimit
local MAX_UPGRADE_ID_LENGTH = 64

local UpgradeService = {}

type RateState = {
	LastAccepted: number,
	WindowStart: number,
	Count: number,
}

local rateStates: { [Player]: RateState } = {}

-- Devuelve: "ok", "cooldown" (responder TooFast) o "flood" (ignorar en silencio).
local function checkRateLimit(player: Player): string
	local now = os.clock()
	local state = rateStates[player]
	if not state then
		state = { LastAccepted = -math.huge, WindowStart = now, Count = 0 }
		rateStates[player] = state
	end

	if now - state.WindowStart > RateLimit.WindowSeconds then
		state.WindowStart = now
		state.Count = 0
	end

	state.Count += 1
	if state.Count > RateLimit.MaxRequestsPerWindow then
		return "flood"
	end
	if now - state.LastAccepted < RateLimit.Cooldown then
		return "cooldown"
	end

	state.LastAccepted = now
	return "ok"
end

local function tryPurchase(player: Player, upgradeId: any): string
	if typeof(upgradeId) ~= "string" or #upgradeId == 0 or #upgradeId > MAX_UPGRADE_ID_LENGTH then
		return Codes.InvalidRequest
	end

	local definition = Economy.getUpgradeDefinition(upgradeId)
	if not definition then
		return Codes.InvalidRequest
	end

	local profile = PlayerDataService.get(player)
	-- Mientras se cargan los datos guardados no se compra: los niveles cargados sustituirán
	-- a los de la sesión. (Si la carga falló se juega en modo sesión, sin guardar.)
	if not profile or profile.DataState == "Loading" then
		return Codes.NotReady
	end

	local level = profile.UpgradeLevels[upgradeId] or 0
	if level >= definition.MaxLevel then
		return Codes.MaxLevel
	end

	local cost = Economy.getUpgradeCost(upgradeId, level)
	if not cost or profile.Energy < cost then
		return Codes.InsufficientEnergy
	end

	profile.Energy -= cost
	profile.UpgradeLevels[upgradeId] = level + 1
	PlayerDataService.recalculateProduction(player)
	PlayerDataService.replicate(player)

	return Codes.Success
end

function UpgradeService.start()
	local purchaseRemote = RemoteService.get(Constants.Remotes.PurchaseUpgrade)
	local resultRemote = RemoteService.get(Constants.Remotes.PurchaseResult)

	purchaseRemote.OnServerEvent:Connect(function(player: Player, upgradeId: any)
		local rate = checkRateLimit(player)
		if rate == "flood" then
			return
		end

		local safeId = if typeof(upgradeId) == "string" then upgradeId else nil
		if rate == "cooldown" then
			resultRemote:FireClient(player, false, Codes.TooFast, safeId)
			return
		end

		local code = tryPurchase(player, upgradeId)
		resultRemote:FireClient(player, code == Codes.Success, code, safeId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		rateStates[player] = nil
	end)
end

return UpgradeService
