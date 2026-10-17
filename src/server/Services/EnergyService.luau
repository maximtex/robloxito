-- Suma energía a todos los jugadores cada TickInterval segundos.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.EconomyConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)

local EnergyService = {}

-- Avisos de energía producida (los usa QuestService). Se llaman después de sumar la
-- energía, con la cantidad producida; no cambian la producción.
local producedListeners: { (Player, number) -> () } = {}

function EnergyService.onProduced(listener: (Player, number) -> ())
	table.insert(producedListeners, listener)
end

local function produceEnergy()
	for player, profile in PlayerDataService.getAll() do
		local produced = profile.ProductionPerSecond * EconomyConfig.TickInterval
		profile.Energy += produced
		PlayerDataService.replicate(player)
		for _, listener in producedListeners do
			task.spawn(listener, player, produced)
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
