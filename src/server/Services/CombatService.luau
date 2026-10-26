-- Pedir un ataque: el cliente manda el punto del mundo al que apunta (donde está el ratón,
-- el toque o delante del personaje) y qué hace: un golpe (clic), "Hold" (mantiene pulsado),
-- "Release" (lo suelta), "Aim" (solo apunta, para el disparo automático del pase),
-- "Charge" (empieza a cargar un orbe, Magia), "Reload" (recargar, Armas), "AdsOn"/"AdsOff"
-- (apuntar con el clic derecho, Armas) o "BlockOn"/"BlockOff" (bloquear, Guerrero). El
-- servidor solo comprueba que el punto sea un número de verdad y no esté absurdamente lejos;
-- PetCombatService decide a quién da (lo que haya en el camino), cuándo y cuánto daña.
-- Nunca acepta daño, enemigos ni recompensas del cliente. Por compatibilidad, un modelo de
-- enemigo vale como punto (su posición) y nada, como "hacia donde mira".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local MAX_AIM_DISTANCE = 400 -- un punto más lejos del personaje que esto no vale
local FACING_DISTANCE = 40
local MODES = { Shot = true, Hold = true, Aim = true, Release = true, Charge = true, Reload = true, AdsOn = true, AdsOff = true, BlockOn = true, BlockOff = true }
-- Cambios de estado (soltar, apuntar, bloquear, recargar): llegan justo tras un golpe, así
-- que no esperan la cadencia del límite de golpes (solo uno contra inundaciones).
local TOGGLES = { Release = true, Reload = true, AdsOn = true, AdsOff = true, BlockOn = true, BlockOff = true }

local CombatService = {}

-- Avisos de "el jugador ha golpeado con una habilidad a este enemigo": los usa
-- PetCombatService para fijar el objetivo de sus mascotas. Se registran una vez al arrancar.
local hitListeners: { (Player, any) -> () } = {}
function CombatService.onPlayerHit(listener: (Player, any) -> ())
	table.insert(hitListeners, listener)
end

-- Otro servicio del servidor (StyleService, AbilityService) avisa de que el jugador ha dañado
-- a este enemigo con una habilidad: sus mascotas lo toman como objetivo.
function CombatService.reportHit(player: Player, enemy: any)
	for _, listener in hitListeners do
		task.spawn(listener, player, enemy)
	end
end

-- Avisos de "el jugador apunta aquí (y pide un disparo, mantiene pulsado o solo apunta)".
local shotListeners: { (Player, Vector3, string) -> () } = {}
function CombatService.onShotRequest(listener: (Player, Vector3, string) -> ())
	table.insert(shotListeners, listener)
end

local function requestShot(player: Player, aim: Vector3, mode: string)
	for _, listener in shotListeners do
		task.spawn(listener, player, aim, mode)
	end
end

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

-- Mantener pulsado o apuntar con el automático repite el aviso cada ~0.12 s (CombatController)
local selectLimiter = RateLimiter.new(0.06, 2, 36)
local toggleLimiter = RateLimiter.new(0, 2, 30)

local function handleSelect(player: Player, aimed: any, mode: any)
	local limiter = if type(mode) == "string" and TOGGLES[mode] then toggleLimiter else selectLimiter
	if limiter:check(player) ~= "ok" then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return
	end
	local kind = if type(mode) == "string" and MODES[mode] then mode else "Shot"
	local aim: Vector3
	if typeof(aimed) == "Vector3" then
		aim = aimed
	elseif typeof(aimed) == "Instance" then
		-- Clientes antiguos: el modelo del enemigo apuntado
		local enemy = EnemyService.fromModel(aimed)
		if not (enemy and EnemyService.isAlive(enemy) and EnemyService.canInteract(player, enemy)) then
			return
		end
		aim = enemy.Root.Position
	elseif aimed == nil then
		local look = root.CFrame.LookVector
		aim = root.Position + Vector3.new(look.X, 0, look.Z) * FACING_DISTANCE
	else
		return
	end
	if not (finite(aim.X) and finite(aim.Y) and finite(aim.Z)) or (aim - root.Position).Magnitude > MAX_AIM_DISTANCE then
		return
	end
	requestShot(player, aim, kind)
end

function CombatService.start()
	RemoteService.get(Constants.Remotes.Attack).OnServerEvent:Connect(handleSelect)
	Players.PlayerRemoving:Connect(function(player)
		selectLimiter:remove(player)
		toggleLimiter:remove(player)
	end)
end

return CombatService
