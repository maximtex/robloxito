-- 💎 de los jugadores (profile.Diamonds, atributo Diamonds).
-- - grant(player, amount): 💎 ganados peleando (enemigos y oleadas). Se suman al momento
--   (el contador sube con cada orbe) y cuentan como "conseguidos" en el siguiente aviso.
-- - Cada TickInterval segundos avisa a los oyentes (misiones, tutorial, clasificaciones)
--   con los 💎 conseguidos desde el aviso anterior (0 si no hubo): los oyentes no se
--   llaman en cada golpe, solo una vez por ciclo. No hay producción pasiva.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.EconomyConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)

local DiamondService = {}

-- Avisos de 💎 conseguidos (los usa QuestService). Se llaman una vez por ciclo, con la
-- cantidad conseguida desde el anterior.
local producedListeners: { (Player, number) -> () } = {}
-- 💎 ganados peleando desde el último aviso (por jugador).
local pending: { [Player]: number } = {}

function DiamondService.onProduced(listener: (Player, number) -> ())
	table.insert(producedListeners, listener)
end

-- 💎 ganados al derrotar enemigos (EnemyService) o en las oleadas. Devuelve lo sumado.
function DiamondService.grant(player: Player, amount: number): number
	local profile = PlayerDataService.get(player)
	if not profile or type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return 0
	end
	local value = math.floor(amount)
	if value <= 0 then
		return 0
	end
	profile.Diamonds += value
	pending[player] = (pending[player] or 0) + value
	PlayerDataService.replicate(player)
	return value
end

local function notifyEarned()
	for player in PlayerDataService.getAll() do
		local total = pending[player] or 0
		pending[player] = nil
		for _, listener in producedListeners do
			task.spawn(listener, player, total)
		end
	end
	-- Quien ya salió no deja 💎 pendientes colgados.
	for player in pending do
		if not PlayerDataService.get(player) then
			pending[player] = nil
		end
	end
end

function DiamondService.start()
	task.spawn(function()
		while true do
			task.wait(EconomyConfig.TickInterval)
			notifyEarned()
		end
	end)
end

return DiamondService
