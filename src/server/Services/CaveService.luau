-- Cueva de los Espinillos (CaveConfig): el viaje entre la boca de la cueva (en la colina oeste
-- del Bosque) y la cueva de dentro (lejos del mapa; la construye CaveDungeon):
-- - Quien cruza la bruma del fondo de la boca (CaveLogic.inEntrance) aparece en la sala 1,
--   junto al portal de salida (CaveConfig.Arrival).
-- - Quien pisa un portal de salida (CaveLogic.exitAt, en la sala 1 y en la 3) aparece fuera,
--   en el camino delante de la boca (CaveConfig.Entrance.Exit).
-- Lo comprueba el servidor cada poco con la posición real del personaje (el cliente no pide
-- nada). CaveEvent avisa a ese jugador para el fundido a negro: ("Fade", { Inside }) antes de
-- moverlo y ("Arrived", { Inside, Position, Facing }) al llegar (CaveController gira la cámara
-- hacia Facing, para que al seguir andando no vuelvas a cruzar). Al llegar se para el paso que
-- llevara (no sigue andando hacia un portal) y hay una espera entre dos viajes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CaveConfig = require(Shared.Config.CaveConfig)
local CaveLogic = require(Shared.CaveLogic)
local StudFloor = require(Shared.Util.StudFloor)
local RemoteService = require(script.Parent.RemoteService)
local StudWorld = require(script.Parent.Parent.Util.StudWorld)

local STREAM_TIMEOUT = 6

local CaveService = {}

local eventRemote: RemoteEvent
local traveling: { [Player]: boolean } = {}
local readyAt: { [Player]: number } = {}

local function characterOf(player: Player): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return character, root, humanoid
	end
	return nil, nil, nil
end

-- Punto de llegada sobre el suelo (los caminos sobresalen un poco), mirando hacia `facing`.
local function spotCFrame(position: Vector3, facing: Vector3): CFrame
	local ground = Vector3.new(position.X, StudWorld.FloorTop + StudFloor.raiseAt(position.X, position.Z), position.Z)
	return CFrame.lookAt(ground, ground + Vector3.new(facing.X, 0, facing.Z))
end

local ARRIVAL = spotCFrame(CaveConfig.Arrival.Position, CaveConfig.Arrival.Facing)
local OUTSIDE = spotCFrame(CaveConfig.Entrance.Exit.Position, CaveConfig.Entrance.Exit.Facing)

local function travel(player: Player, destination: CFrame, inside: boolean)
	traveling[player] = true
	eventRemote:FireClient(player, "Fade", { Inside = inside })
	task.wait(CaveConfig.Travel.FadeSeconds)
	pcall(function()
		player:RequestStreamAroundAsync(destination.Position, STREAM_TIMEOUT)
	end)
	local character, root, humanoid = characterOf(player)
	if character and root and humanoid and player.Parent then
		if humanoid.Sit then
			humanoid.Sit = false
		end
		local lift = humanoid.HipHeight + root.Size.Y / 2 + 0.5
		character:PivotTo(destination + Vector3.new(0, lift, 0))
		root.AssemblyLinearVelocity = Vector3.zero
		humanoid:MoveTo(destination.Position + Vector3.new(0, lift, 0)) -- se queda donde llega
	end
	if player.Parent then
		eventRemote:FireClient(player, "Arrived", { Inside = inside, Position = destination.Position, Facing = destination.LookVector })
	end
	readyAt[player] = os.clock() + CaveConfig.Travel.Cooldown
	traveling[player] = nil
end

local function check()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if traveling[player] or (readyAt[player] or 0) > now then
			continue
		end
		local _, root = characterOf(player)
		if not root then
			continue
		end
		if CaveLogic.inEntrance(root.Position, StudWorld.FloorTop) then
			task.spawn(travel, player, ARRIVAL, true)
		elseif CaveLogic.exitAt(root.Position) then
			task.spawn(travel, player, OUTSIDE, false)
		end
	end
end

-- ¿Está viajando ahora (entre el fundido y la llegada)? Para otros servicios y pruebas.
function CaveService.isTraveling(player: Player): boolean
	return traveling[player] == true
end

function CaveService.start()
	eventRemote = RemoteService.get(Constants.Remotes.CaveEvent)
	Players.PlayerRemoving:Connect(function(player)
		traveling[player] = nil
		readyAt[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CaveConfig.Travel.CheckInterval)
			local ok, err = pcall(check)
			if not ok then
				warn("[CaveService] " .. tostring(err))
			end
		end
	end)
end

return CaveService
