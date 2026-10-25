-- Energía de los jugadores.
-- - Cada TickInterval segundos avisa a los oyentes (misiones, tutorial, clasificaciones)
--   con la energía generada desde el aviso anterior. Con EconomyConfig.PassiveEnergy en
--   true además suma la producción pasiva (cristal y núcleos); en false (el rediseño "solo
--   disparar") esa parte es 0 y la energía solo llega por grant (enemigos derrotados).
-- - grant(player, amount): energía ganada peleando. Se suma al momento (el contador sube
--   con cada orbe) y cuenta como "generada" en el siguiente aviso: los oyentes no se
--   llaman en cada golpe, solo una vez por ciclo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.EconomyConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)

local EnergyService = {}

-- Avisos de energía producida (los usa QuestService). Se llaman después de sumar la
-- energía, con la cantidad producida; no cambian la producción.
local producedListeners: { (Player, number) -> () } = {}
-- Energía ganada peleando desde el último aviso (por jugador).
local pending: { [Player]: number } = {}

function EnergyService.onProduced(listener: (Player, number) -> ())
	table.insert(producedListeners, listener)
end

-- Energía ganada al derrotar enemigos (EnemyService). Devuelve lo sumado.
function EnergyService.grant(player: Player, amount: number): number
	local profile = PlayerDataService.get(player)
	if not profile or type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return 0
	end
	local value = math.floor(amount)
	if value <= 0 then
		return 0
	end
	profile.Energy += value
	pending[player] = (pending[player] or 0) + value
	PlayerDataService.replicate(player)
	return value
end

local function produceEnergy()
	for player, profile in PlayerDataService.getAll() do
		local produced = 0
		if EconomyConfig.PassiveEnergy ~= false then
			produced = profile.ProductionPerSecond * EconomyConfig.TickInterval
			profile.Energy += produced
			PlayerDataService.replicate(player)
		end
		local total = produced + (pending[player] or 0)
		pending[player] = nil
		for _, listener in producedListeners do
			task.spawn(listener, player, total)
		end
	end
	-- Quien ya salió no deja energía pendiente colgada.
	for player in pending do
		if not PlayerDataService.get(player) then
			pending[player] = nil
		end
	end
end

function EnergyService.start()
	task.spawn(function()
		while true do
			task.wait(EconomyConfig.TickInterval)
			produceEnergy()
		end
	end)
end

return EnergyService
