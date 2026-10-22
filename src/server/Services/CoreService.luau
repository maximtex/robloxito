-- Núcleos elementales (FASE 2): desbloquear, mejorar y elegir el elemento activo.
-- Toda la decisión es del servidor (CoreLogic): el cliente solo pide una acción y
-- muestra el estado que se le envía.
--
-- - Acción (CoreAction): "Unlock" | "Upgrade" | "Select" | "Secondary" + elementId
--   ("Secondary" elige el elemento de la R, con el mismo coste y enfriamiento que
--   cambiar el principal). Se valida el tipo, el límite de frecuencia y que los datos estén listos (como con huevos y zonas: con
--   los datos aún cargando no se gasta). CoreLogic modifica los datos y devuelve el coste,
--   que se resta en el MISMO paso, sin pausas entre medias.
-- - Naturaleza se mejora con la Resonancia del Cristal (UpgradeService), no aquí.
-- - Tras un cambio: producción recalculada, atributos replicados, perfil marcado para
--   guardar (desbloquear y elegir se guardan al momento) y estado nuevo al cliente.
-- - Estado (CoreState) bajo petición (RequestCores) y después de cada acción. Incluye la
--   habilidad de cada elemento con sus números reales (AbilityLogic.summary).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CoreConfig = require(Shared.Config.CoreConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local CombatConfig = require(Shared.Config.CombatConfig)
local CombatMath = require(Shared.CombatMath)
local AbilityLogic = require(Shared.AbilityLogic)
local RebirthLogic = require(Shared.RebirthLogic)
local AdventureLogic = require(Shared.AdventureLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local CoreLogic = require(script.Parent.Parent.Util.CoreLogic)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Codes = Constants.PurchaseCodes
local ACTIONS = { Unlock = true, Upgrade = true, Select = true, Secondary = true }
local MAX_ID_LENGTH = 32

-- CoreLogic devuelve estos códigos; todos existen en Constants.PurchaseCodes.
local CODE_MAP = {
	Success = Codes.Success,
	InvalidRequest = Codes.InvalidRequest,
	AlreadyUnlocked = Codes.AlreadyUnlocked,
	Locked = Codes.Locked,
	InsufficientEnergy = Codes.InsufficientEnergy,
	AlreadySelected = Codes.AlreadySelected,
	TooFast = Codes.TooFast,
	MaxLevel = Codes.MaxLevel,
}

local CoreService = {}

local stateRemote: RemoteEvent
local resultRemote: RemoteEvent
local actionLimiter = RateLimiter.new(EconomyConfig.PurchaseRateLimit.Cooldown, EconomyConfig.PurchaseRateLimit.WindowSeconds, EconomyConfig.PurchaseRateLimit.MaxRequestsPerWindow)
local requestLimiter = RateLimiter.new(0.5, 3, 8)

-- Estado para mostrar (todo calculado aquí; el cliente no repite fórmulas).
function CoreService.snapshot(profile: PlayerDataService.Profile): { [string]: any }
	local data = profile.PetData.Cores
	local levels = profile.UpgradeLevels
	local elements = {}
	local previousUnlocked = true
	local playerDamage = CombatMath.withBonus(CombatMath.playerDamage(levels[CombatConfig.DamageUpgradeId] or 0, profile.PetMultiplier), RebirthLogic.damageMultiplier(RebirthLogic.ofProfile(profile)) * AdventureLogic.damageMultiplier(AdventureLogic.ofProfile(profile), os.time()))
	for index, elementId in CoreConfig.Order do
		local unlocked = CoreLogic.isUnlocked(data, elementId)
		local level = CoreLogic.level(data, levels, elementId)
		local isDefault = index == 1
		local maxLevel = if isDefault then EconomyConfig.Upgrades[CoreConfig.Elements[elementId].UpgradeId].MaxLevel else CoreConfig.Upgrade.MaxLevel
		local upgradeCost = if unlocked then CoreLogic.upgradeCost(elementId, level) else nil
		local ability = AbilityLogic.get(elementId)
		table.insert(elements, {
			Id = elementId,
			Unlocked = unlocked,
			Level = level,
			MaxLevel = maxLevel,
			-- Producción base actual (o la que tendría al despertarlo, si está bloqueado).
			Production = CoreLogic.productionAt(elementId, level),
			-- Lo que añade el siguiente nivel (0 si está al máximo).
			NextGain = if upgradeCost then CoreLogic.productionAt(elementId, level + 1) - CoreLogic.productionAt(elementId, level) else 0,
			UpgradeCost = upgradeCost,
			UnlockCost = if unlocked then nil else CoreLogic.unlockCost(elementId),
			-- Se puede despertar ya (los anteriores están despiertos si es secuencial).
			Available = not unlocked and (previousUnlocked or not CoreConfig.Unlock.Sequential),
			-- Habilidad del elemento (solo la del seleccionado se usa), con números reales.
			Ability = if ability
				then {
					Name = ability.Name,
					Icon = ability.Icon,
					Cooldown = ability.Cooldown,
					Summary = AbilityLogic.summary(elementId, playerDamage, level),
				}
				else nil,
		})
		previousUnlocked = previousUnlocked and unlocked
	end
	return {
		Ready = PlayerDataService.isPetDataReady(profile),
		Selected = data.Selected,
		Secondary = CoreLogic.secondaryOf(data),
		SwitchCost = CoreLogic.switchCost(data, levels),
		-- Hora del servidor (os.time) a partir de la cual se puede volver a cambiar.
		SwitchReadyAt = if data.LastSwitchAt > 0 then data.LastSwitchAt + CoreConfig.Switch.CooldownSeconds else 0,
		AffinityRate = CoreLogic.affinityRate(),
		AffinityProduction = CoreLogic.affinityBonus(data, levels),
		BaseProduction = CoreLogic.baseProduction(data, levels),
		PetMultiplier = profile.PetMultiplier,
		Total = profile.ProductionPerSecond,
		Elements = elements,
	}
end

local function push(player: Player)
	local profile = PlayerDataService.get(player)
	if profile and player.Parent then
		stateRemote:FireClient(player, CoreService.snapshot(profile))
	end
end
CoreService.push = push

-- Devuelve (código, coste).
function CoreService.perform(player: Player, action: any, elementId: any): (string, number)
	if typeof(action) ~= "string" or not ACTIONS[action] then
		return Codes.InvalidRequest, 0
	end
	if typeof(elementId) ~= "string" or #elementId == 0 or #elementId > MAX_ID_LENGTH then
		return Codes.InvalidRequest, 0
	end
	local profile = PlayerDataService.get(player)
	if not profile or not PlayerDataService.isPetDataReady(profile) then
		return Codes.NotReady, 0
	end

	local data = profile.PetData.Cores
	local code, cost
	if action == "Unlock" then
		code, cost = CoreLogic.unlock(data, elementId, profile.Energy, os.time())
	elseif action == "Upgrade" then
		code, cost = CoreLogic.upgrade(data, elementId, profile.Energy)
	elseif action == "Secondary" then
		code, cost = CoreLogic.selectSecondary(data, profile.UpgradeLevels, elementId, profile.Energy, os.time())
	else
		code, cost = CoreLogic.selectElement(data, profile.UpgradeLevels, elementId, profile.Energy, os.time())
	end

	if code == "Success" then
		-- Mismo paso que la modificación de los datos: sin pausas entre medias.
		profile.Energy -= cost
		PlayerDataService.recalculateProduction(player)
		PlayerDataService.replicate(player)
		PlayerDataService.markDirty(player)
		if action ~= "Upgrade" then
			PlayerDataService.saveNow(player) -- desbloquear o elegir (Q o R): se guarda al momento
		end
	end
	return CODE_MAP[code] or Codes.InvalidRequest, cost
end

function CoreService.start()
	stateRemote = RemoteService.get(Constants.Remotes.CoreState)
	resultRemote = RemoteService.get(Constants.Remotes.CoreResult)
	local actionRemote = RemoteService.get(Constants.Remotes.CoreAction)
	local requestRemote = RemoteService.get(Constants.Remotes.RequestCores)

	actionRemote.OnServerEvent:Connect(function(player: Player, action: any, elementId: any)
		local rate = actionLimiter:check(player)
		if rate == "flood" then
			return
		end
		local safeAction = if typeof(action) == "string" and ACTIONS[action] then action else nil
		local safeId = if typeof(elementId) == "string" and #elementId <= MAX_ID_LENGTH then elementId else nil
		if rate == "cooldown" then
			resultRemote:FireClient(player, false, Codes.TooFast, safeAction, safeId, 0)
			return
		end
		local code, cost = CoreService.perform(player, action, elementId)
		resultRemote:FireClient(player, code == Codes.Success, code, safeAction, safeId, cost)
		push(player)
	end)

	requestRemote.OnServerEvent:Connect(function(player: Player)
		if requestLimiter:check(player) == "ok" then
			push(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		actionLimiter:remove(player)
		requestLimiter:remove(player)
	end)
end

return CoreService
