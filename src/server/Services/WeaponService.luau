-- Armería: comprar, equipar y mejorar armas con el dinero que sueltan los enemigos.
-- WeaponLogic valida cada acción con los datos del servidor (precio, requisito de zona,
-- nivel máximo); aquí solo se comprueba que el perfil esté listo, se cobra y se replica.
-- Un arma comprada se equipa al momento. Los jefes regalan la suya con WeaponService.grant
-- (BossRewardService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local WeaponLogic = require(Shared.WeaponLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local Codes = Constants.PurchaseCodes
local RateLimit = EconomyConfig.PurchaseRateLimit
local MAX_ID_LENGTH = 64

local WeaponService = {}

local limiter = RateLimiter.new(RateLimit.Cooldown, RateLimit.WindowSeconds, RateLimit.MaxRequestsPerWindow)
local resultRemote: RemoteEvent

-- Una acción de la Armería: "Buy", "Equip" o "Upgrade". Devuelve el código y lo cobrado.
function WeaponService.act(player: Player, action: any, weaponId: any): (string, number)
	if type(action) ~= "string" or type(weaponId) ~= "string" or #weaponId > MAX_ID_LENGTH then
		return Codes.InvalidRequest, 0
	end
	local profile = PlayerDataService.get(player)
	-- Mientras se cargan los datos guardados no se compra: los cargados sustituirán a estos.
	if not profile or profile.DataState == "Loading" then
		return Codes.NotReady, 0
	end
	local weapons = profile.PetData.Weapons
	local code, cost = "InvalidRequest", 0
	if action == "Buy" then
		code, cost = WeaponLogic.buy(weapons, weaponId, profile.PetData.UnlockedZones, profile.Money)
		if code == "Success" then
			profile.Money -= cost
			WeaponLogic.equip(weapons, weaponId)
		end
	elseif action == "Upgrade" then
		code, cost = WeaponLogic.upgrade(weapons, weaponId, profile.Money)
		if code == "Success" then
			profile.Money -= cost
		end
	elseif action == "Equip" then
		code = WeaponLogic.equip(weapons, weaponId)
	end
	if code == "Success" then
		PlayerDataService.markDirty(player)
		PlayerDataService.replicate(player)
		if action == "Buy" then
			PlayerDataService.saveNow(player) -- una compra grande no se pierde con una caída
		end
	end
	return Codes[code] or code, cost
end

-- Regala un arma (jefes). true si es nueva: el jugador recibe el aviso.
function WeaponService.grant(player: Player, weaponId: string): boolean
	local profile = PlayerDataService.get(player)
	if not profile or not WeaponLogic.grant(profile.PetData.Weapons, weaponId) then
		return false
	end
	PlayerDataService.markDirty(player)
	PlayerDataService.replicate(player)
	PlayerDataService.saveNow(player)
	resultRemote:FireClient(player, true, "BossDrop", "Grant", weaponId, 0)
	return true
end

function WeaponService.start()
	resultRemote = RemoteService.get(Constants.Remotes.WeaponResult)
	RemoteService.get(Constants.Remotes.WeaponAction).OnServerEvent:Connect(function(player: Player, action: any, weaponId: any)
		local rate = limiter:check(player)
		if rate == "flood" then
			return
		elseif rate == "cooldown" then
			resultRemote:FireClient(player, false, Codes.TooFast, action, weaponId, 0)
			return
		end
		local code, cost = WeaponService.act(player, action, weaponId)
		resultRemote:FireClient(player, code == Codes.Success, code, action, weaponId, cost)
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:remove(player)
	end)
end

return WeaponService
