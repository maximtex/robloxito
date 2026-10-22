-- Premios especiales de los jefes, para cada jugador que recibe parte de su recompensa
-- (EnemyService.onDefeated: una vez por muerte y jugador):
-- - Cuenta la derrota en PetData.Bosses (abre la zona siguiente, ZoneLogic).
-- - Energía extra (EnergyReward del jefe), que se suma directa: no cuenta como generada.
-- - Su arma (WeaponConfig.BossDrop), la primera vez que lo derrota.
-- - Su mascota de combate (PetReward): la primera vez seguro y después con PetDropChance
--   (copias para evolucionarla). Si no cabe en el inventario, se pierde esa copia.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EnemyService = require(script.Parent.EnemyService)
local WeaponService = require(script.Parent.WeaponService)
local PetService = require(script.Parent.PetService)
local RemoteService = require(script.Parent.RemoteService)

local random = Random.new()

local BossRewardService = {}

-- Arma que suelta cada jefe (tipo de EnemyConfig -> id de WeaponConfig)
local dropOf: { [string]: string } = {}
for weaponId, def in WeaponConfig.Weapons do
	if def.BossDrop then
		dropOf[def.BossDrop] = weaponId
	end
end

local function onDefeated(player: Player, info: { TypeId: string, Kind: string })
	if info.Kind ~= "Boss" then
		return
	end
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	local bosses = profile.PetData.Bosses
	bosses[info.TypeId] = (bosses[info.TypeId] or 0) + 1
	local def = EnemyConfig.Types[info.TypeId]
	local energy = def and def.EnergyReward or 0
	if energy > 0 then
		profile.Energy += energy
	end
	PlayerDataService.markDirty(player)
	PlayerDataService.replicate(player)
	local weaponId = dropOf[info.TypeId]
	if weaponId then
		WeaponService.grant(player, weaponId) -- solo la primera vez (si ya la tiene, nada)
	end
	local petId = def and def.PetReward
	if petId and (bosses[info.TypeId] == 1 or random:NextNumber() < (def.PetDropChance or 0)) then
		local code, grant = PetService.grantFreePet(player, petId)
		if code == Constants.PurchaseCodes.Success and grant then
			RemoteService.get(Constants.Remotes.PetShopResult):FireClient(player, true, "BossDrop", nil, grant.PetId, grant.Uid, grant.AutoEquipped)
		end
	end
end

function BossRewardService.start()
	EnemyService.onDefeated(onDefeated)
end

return BossRewardService
