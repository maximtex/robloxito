-- Premios especiales de los jefes, para cada jugador que recibe parte de su recompensa
-- (EnemyService.onDefeated: una vez por muerte y jugador):
-- - Cuenta la derrota en PetData.Bosses (abre la zona siguiente, ZoneLogic). Las zonas sin
--   precio que pide (el Mundo 2, del Rey Goblin) quedan abiertas al momento.
-- - Energía extra (DiamondReward del jefe), que se suma directa: no cuenta como generada.
-- - Su arma, sus guantes o su bastón (WeaponConfig.BossDrop): el de TU estilo de pelea
--   (StyleConfig) la primera vez que lo derrotas con él. Cada estilo tiene el suyo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared.Config.EnemyConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local WeaponLogic = require(Shared.WeaponLogic)
local StyleLogic = require(Shared.StyleLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EnemyService = require(script.Parent.EnemyService)
local WeaponService = require(script.Parent.WeaponService)
local ZoneLogic = require(script.Parent.Parent.Util.ZoneLogic)

local BossRewardService = {}

-- Lo que suelta cada jefe para cada estilo (tipo de EnemyConfig -> categoría -> id)
local dropOf: { [string]: { [string]: string } } = {}
for weaponId, def in WeaponConfig.Weapons do
	if def.BossDrop then
		dropOf[def.BossDrop] = dropOf[def.BossDrop] or {}
		dropOf[def.BossDrop][WeaponLogic.category(weaponId)] = weaponId
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
	-- Zonas que abre este jefe sin precio (el Rey Goblin abre el Mundo 2)
	local opened = ZoneLogic.unlockByBoss(profile, ZoneConfig, info.TypeId)
	if #opened > 0 then
		PlayerDataService.saveNow(player)
	end
	local def = EnemyConfig.Types[info.TypeId]
	local diamonds = def and def.DiamondReward or 0
	if diamonds > 0 then
		profile.Diamonds += diamonds
	end
	PlayerDataService.markDirty(player)
	PlayerDataService.replicate(player)
	local drops = dropOf[info.TypeId]
	local weaponId = drops and drops[StyleLogic.sanitize(profile.PetData.Style)]
	if weaponId then
		WeaponService.grant(player, weaponId) -- solo la primera vez (si ya la tiene, nada)
	end
end

function BossRewardService.start()
	EnemyService.onDefeated(onDefeated)
end

return BossRewardService
