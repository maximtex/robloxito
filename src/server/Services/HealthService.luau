-- Regeneración de vida del jugador. Reemplaza la de Roblox: el script "Health" que Roblox
-- pone en cada personaje cura un 1 % de la vida máxima por segundo SIEMPRE, también en plena
-- pelea, y con eso la vida, las pociones y la defensa casi no importaban (pruebas con amigos).
-- Aquí:
-- - Solo fuera de combate: tras CombatConfig.Regen.Delay segundos sin recibir daño.
-- - Más despacio: Rate de la vida máxima por segundo.
-- - Las curas de siempre siguen igual: al limpiar una oleada (WaveConfig.ClearHeal), el robo
--   de vida de la Magia y las clases, los elementos que curan y las habilidades.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.CombatConfig)

local HealthService = {}

local STEP = 0.5 -- cada cuánto se cura (s)

-- Cuándo recibió daño por última vez cada personaje vivo (os.clock)
local lastHurt: { [Humanoid]: number } = {}

local function settings(): (number, number)
	local regen = CombatConfig.Regen or {}
	local rate = if type(regen.Rate) == "number" and regen.Rate >= 0 then regen.Rate else 0.005
	local delay = if type(regen.Delay) == "number" and regen.Delay >= 0 then regen.Delay else 6
	return rate, delay
end

local function setup(character: Model)
	-- Sin la regeneración de Roblox (la copia al aparecer si no hay una "Health" propia)
	local default = character:WaitForChild("Health", 5)
	if default and default:IsA("Script") then
		default:Destroy()
	end
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	local last = humanoid.Health
	lastHurt[humanoid] = 0
	humanoid.HealthChanged:Connect(function(health: number)
		if health < last - 0.01 then
			lastHurt[humanoid] = os.clock()
		end
		last = health
	end)
	humanoid.Died:Connect(function()
		lastHurt[humanoid] = nil
	end)
	humanoid.AncestryChanged:Connect(function(_, parent)
		if not parent then
			lastHurt[humanoid] = nil
		end
	end)
end

local function heal(dt: number)
	local rate, delay = settings()
	if rate <= 0 then
		return
	end
	local now = os.clock()
	for humanoid, hurtAt in lastHurt do
		if humanoid.Parent == nil then
			lastHurt[humanoid] = nil
		elseif humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth and now - hurtAt >= delay then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * rate * dt)
		end
	end
end

function HealthService.start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(setup, character)
		end)
		if player.Character then
			task.spawn(setup, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= STEP then
			heal(acc)
			acc = 0
		end
	end)
end

return HealthService
