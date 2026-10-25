-- Pedir un disparo con un clic o un toque: el cliente propone el modelo del enemigo al que
-- apunta y el servidor comprueba que exista, esté vivo y no demasiado lejos de la posición
-- real del personaje. Si vale, pasa a ser el objetivo del arma y de las mascotas y se pide
-- un disparo (PetCombatService decide cuándo y cuánto daña). Sin modelo (F o "Disparar"),
-- PetCombatService dispara al más cercano a tiro. Nunca acepta daño ni recompensas del cliente.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local MAX_SELECT_RANGE = 75 -- studs del personaje al enemigo para poder elegirlo

local CombatService = {}

-- Avisos de "el jugador ha elegido (o golpeado con una habilidad) a este enemigo": los usa
-- PetCombatService para fijar el objetivo. Se registran una vez al arrancar.
local hitListeners: { (Player, any) -> () } = {}
function CombatService.onPlayerHit(listener: (Player, any) -> ())
	table.insert(hitListeners, listener)
end

-- Otro servicio del servidor (AbilityService) avisa de que el jugador ha dañado a este
-- enemigo con una habilidad: su arma y sus mascotas lo toman como objetivo.
function CombatService.reportHit(player: Player, enemy: any)
	for _, listener in hitListeners do
		task.spawn(listener, player, enemy)
	end
end

-- Avisos de "el jugador pide un disparo" (enemigo validado, o nil para el más cercano).
local shotListeners: { (Player, any?) -> () } = {}
function CombatService.onShotRequest(listener: (Player, any?) -> ())
	table.insert(shotListeners, listener)
end

local function requestShot(player: Player, enemy: any?)
	for _, listener in shotListeners do
		task.spawn(listener, player, enemy)
	end
end

-- Mantener pulsado repite la petición cada ~0.15 s (CombatController)
local selectLimiter = RateLimiter.new(0.08, 2, 30)

local function handleSelect(player: Player, aimed: any)
	if selectLimiter:check(player) ~= "ok" or (aimed ~= nil and typeof(aimed) ~= "Instance") then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return
	end
	if aimed == nil then
		requestShot(player, nil)
		return
	end
	local enemy = EnemyService.fromModel(aimed)
	if not (enemy and EnemyService.isAlive(enemy)) then
		return
	end
	local offset = enemy.Root.Position - root.Position
	if Vector2.new(offset.X, offset.Z).Magnitude - enemy.Radius > MAX_SELECT_RANGE then
		return
	end
	CombatService.reportHit(player, enemy)
	requestShot(player, enemy)
end

function CombatService.start()
	RemoteService.get(Constants.Remotes.Attack).OnServerEvent:Connect(handleSelect)
	Players.PlayerRemoving:Connect(function(player)
		selectLimiter:remove(player)
	end)
end

return CombatService
