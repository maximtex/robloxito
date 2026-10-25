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
-- Puertas (CaveConfig.Gates): cada bicho de una sala que derrotas (o en el que has hecho
-- daño) cuenta para la puerta de esa sala (CaveLogic.countKill); el progreso se guarda en
-- PetData.Cave y se replica en el atributo CaveGates ("15,3"). Las puertas las dibuja cada
-- cliente (solo cierran a quien no las tiene abiertas); por si alguien se cuela, quien esté
-- detrás de una puerta cerrada vuelve delante de ella (Gates.*.Back) con un aviso
-- ("Blocked", { Index }).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CaveConfig = require(Shared.Config.CaveConfig)
local CaveLogic = require(Shared.CaveLogic)
local StudFloor = require(Shared.Util.StudFloor)
local RemoteService = require(script.Parent.RemoteService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EnemyService = require(script.Parent.EnemyService)
local StudWorld = require(script.Parent.Parent.Util.StudWorld)

local STREAM_TIMEOUT = 6
local SYNC_SECONDS = 1 -- cada cuánto se repasa el atributo de las puertas (al cargar los datos)
local CLOSED = CaveLogic.sanitizeProgress(nil) -- sin datos aún: todas cerradas

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

-- Progreso de las puertas del jugador (el mismo de sus datos) o nil si aún no han cargado.
local function progressOf(player: Player): { number }?
	local profile = PlayerDataService.get(player)
	if not (profile and PlayerDataService.isPetDataReady(profile)) then
		return nil
	end
	local progress = profile.PetData.Cave
	if type(progress) ~= "table" or #progress ~= #CaveConfig.Gates then
		progress = CaveLogic.sanitizeProgress(progress)
		profile.PetData.Cave = progress
	end
	return progress
end

local function syncAttribute(player: Player)
	local progress = progressOf(player)
	local text = if progress then CaveLogic.formatProgress(progress) else nil
	if player:GetAttribute(Constants.Attributes.CaveGates) ~= text then
		player:SetAttribute(Constants.Attributes.CaveGates, text)
	end
end

-- Un bicho derrotado: si vivía en una sala con puerta cerrada, cuenta para ella.
local function onDefeated(player: Player, info)
	if info.Wave or typeof(info.Home) ~= "Vector3" then
		return
	end
	local progress = progressOf(player)
	if not progress then
		return
	end
	local gate, opened = CaveLogic.countKill(progress, info.Home.X, info.Home.Z)
	if gate then
		PlayerDataService.markDirty(player)
		syncAttribute(player)
		if opened then
			PlayerDataService.saveNow(player) -- una puerta abierta no se pierde
		end
	end
end

-- Detrás de una puerta cerrada (alguien se ha colado): vuelve delante de ella.
local function sendBack(player: Player, index: number)
	local gate = CaveConfig.Gates[index]
	local character, root, humanoid = characterOf(player)
	if not (gate and character and root and humanoid) then
		return
	end
	local spot = spotCFrame(gate.Back, gate.Facing)
	local lift = humanoid.HipHeight + root.Size.Y / 2 + 0.5
	character:PivotTo(spot + Vector3.new(0, lift, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	humanoid:MoveTo(spot.Position + Vector3.new(0, lift, 0))
	eventRemote:FireClient(player, "Blocked", { Index = index })
end

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
		local position = root.Position
		if CaveLogic.inEntrance(position, StudWorld.FloorTop) then
			task.spawn(travel, player, ARRIVAL, true)
		elseif CaveLogic.exitAt(position) then
			task.spawn(travel, player, OUTSIDE, false)
		elseif CaveLogic.inside(position.X, position.Z) then
			local blocked = CaveLogic.blockedAt(position.X, position.Z, progressOf(player) or CLOSED)
			if blocked then
				sendBack(player, blocked)
			end
		end
	end
end

-- ¿Está viajando ahora (entre el fundido y la llegada)? Para otros servicios y pruebas.
function CaveService.isTraveling(player: Player): boolean
	return traveling[player] == true
end

-- Progreso de las puertas de un jugador (copia) o nil si sus datos no han cargado.
function CaveService.progressOf(player: Player): { number }?
	local progress = progressOf(player)
	return if progress then table.clone(progress) else nil
end

function CaveService.start()
	eventRemote = RemoteService.get(Constants.Remotes.CaveEvent)
	EnemyService.onDefeated(onDefeated)
	Players.PlayerRemoving:Connect(function(player)
		traveling[player] = nil
		readyAt[player] = nil
	end)
	task.spawn(function()
		local lastSync = 0
		while true do
			task.wait(CaveConfig.Travel.CheckInterval)
			local ok, err = pcall(check)
			if not ok then
				warn("[CaveService] " .. tostring(err))
			end
			if os.clock() - lastSync >= SYNC_SECONDS then
				lastSync = os.clock()
				for _, player in Players:GetPlayers() do
					pcall(syncAttribute, player)
				end
			end
		end
	end)
end

return CaveService
