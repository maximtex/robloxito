-- Dibuja y mueve las mascotas equipadas de TODOS los jugadores, en local.
-- Lee el atributo EquippedPets que escribe el servidor; el cliente no decide qué
-- mascotas tiene nadie, solo las representa. Sin físicas ni colisiones: cada mascota
-- tiene una raíz anclada que se mueve con suavizado detrás de su dueño.
-- - Posiciones según el tamaño real de cada modelo (PetLayout): no se solapan entre sí
--   ni se meten dentro del jugador.
-- - Cada especie tiene un movimiento sencillo (saltos, trote, vuelo) según Look.Style.
-- - Al desequipar se destruyen sus modelos; al morir se ocultan y reaparecen junto al
--   nuevo personaje; al salir el jugador se destruye todo y se desconectan sus señales.
-- - Mientras se incuba un huevo (RevealGate), las mascotas del jugador local no cambian,
--   para no revelar la nueva antes de la presentación.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PetConfig = require(Shared.Config.PetConfig)
local PetModelBuilder = require(script.Parent.Parent.Pets.PetModelBuilder)
local PetLayout = require(script.Parent.Parent.Pets.PetLayout)
local RevealGate = require(script.Parent.Parent.Pets.RevealGate)

local FOLDER_NAME = "ClientPets"
local SMOOTHING = 8 -- mayor = sigue más rápido
local SNAP_DISTANCE = 40 -- si se aleja más (teletransporte, respawn), aparece directamente
local MAX_RENDER_DISTANCE = 250
local MOVING_SPEED = 1.5 -- velocidad horizontal del dueño a partir de la cual "camina"
local MIN_RADIUS = 0.6
local MAX_RADIUS = 2.5

-- Movimiento por estilo. Hover: altura del centro del cuerpo sobre el suelo.
-- Bob: balanceo en reposo. Hop: altura de los saltos al caminar. Sway: balanceo
-- lateral. Pitch: cabeceo.
type Motion = {
	Hover: number,
	Bob: number,
	BobSpeed: number,
	Hop: number?,
	HopSpeed: number?,
	Sway: number?,
	Pitch: number?,
}

local MOTIONS: { [string]: Motion } = {
	Sprout = { Hover = 0.85, Bob = 0.1, BobSpeed = 2.2, Hop = 0.6, HopSpeed = 7 }, -- saltitos
	Mushroom = { Hover = 0.55, Bob = 0.06, BobSpeed = 2, Hop = 0.9, HopSpeed = 6 }, -- grandes saltos
	Fox = { Hover = 0.75, Bob = 0.08, BobSpeed = 2.5, Hop = 0.18, HopSpeed = 10, Sway = 0.1 }, -- trote
	Ember = { Hover = 0.7, Bob = 0.08, BobSpeed = 3, Hop = 0.2, HopSpeed = 11, Sway = 0.12 }, -- trote vivo
	Fawn = { Hover = 1.36, Bob = 0.04, BobSpeed = 2, Hop = 0.35, HopSpeed = 8, Pitch = 0.05 }, -- brincos
	Owl = { Hover = 2.4, Bob = 0.35, BobSpeed = 1.6, Pitch = 0.12 }, -- vuelo
	Quartz = { Hover = 0.7, Bob = 0.08, BobSpeed = 2.5, Hop = 0.22, HopSpeed = 10, Sway = 0.1 }, -- trote ligero
	Turtle = { Hover = 0.62, Bob = 0.03, BobSpeed = 1.2, Hop = 0.08, HopSpeed = 5, Sway = 0.12 }, -- paso lento
	Dragon = { Hover = 2.7, Bob = 0.3, BobSpeed = 2.2, Pitch = 0.1 }, -- vuelo
}
local DEFAULT_MOTION: Motion = { Hover = 1.1, Bob = 0.15, BobSpeed = 3 }

type PetVisual = {
	Model: Model,
	Root: BasePart,
	Radius: number,
	Phase: number,
	Motion: Motion,
	Current: CFrame?, -- posición base suavizada (sin saltos ni inclinación)
}

type Tracker = {
	Key: string,
	Pets: { PetVisual },
	Slots: { PetLayout.Slot },
	Connections: { RBXScriptConnection },
}

local PetFollower = {}

local folder: Folder
local trackers: { [Player]: Tracker } = {}
local elapsed = 0

local function parseEquipped(value: any): { string }
	local petIds = {}
	if typeof(value) ~= "string" then
		return petIds
	end
	for petId in value:gmatch("[^,]+") do
		-- Solo mascotas conocidas y como mucho el límite configurado.
		if PetConfig.Pets[petId] and #petIds < PetConfig.MaxEquipped then
			table.insert(petIds, petId)
		end
	end
	return petIds
end

local function clearPets(tracker: Tracker)
	for _, visual in tracker.Pets do
		visual.Model:Destroy()
	end
	table.clear(tracker.Pets)
	table.clear(tracker.Slots)
end

local function hasCharacter(player: Player): boolean
	local character = player.Character
	return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
end

local function rebuild(player: Player)
	local tracker = trackers[player]
	if not tracker then
		return
	end
	if player == Players.LocalPlayer and RevealGate.isHeld() then
		-- Se reconstruye al soltar la compuerta (Key no cambia, así que se detecta).
		return
	end
	local value = player:GetAttribute(Constants.Attributes.EquippedPets)
	local key = if typeof(value) == "string" then value else ""
	if key == tracker.Key then
		return
	end
	tracker.Key = key

	clearPets(tracker)
	local radii = {}
	for index, petId in parseEquipped(value) do
		local model, root = PetModelBuilder.build(petId)
		if model and root then
			model.Name = player.Name .. "_" .. index .. "_" .. petId
			local size = model:GetExtentsSize()
			local radius = math.clamp(math.max(size.X, size.Z) / 2, MIN_RADIUS, MAX_RADIUS)
			local look = PetConfig.Pets[petId].Look
			local motion = (look and MOTIONS[look.Style]) or DEFAULT_MOTION
			model.Parent = if hasCharacter(player) then folder else nil
			table.insert(tracker.Pets, { Model = model, Root = root, Radius = radius, Phase = index * 1.7, Motion = motion, Current = nil })
			table.insert(radii, radius)
		end
	end
	tracker.Slots = PetLayout.slots(radii)
end

local function track(player: Player)
	if trackers[player] then
		return
	end
	local tracker: Tracker = {
		Key = "\0", -- fuerza la primera construcción
		Pets = {},
		Slots = {},
		Connections = {},
	}
	trackers[player] = tracker

	table.insert(tracker.Connections, player:GetAttributeChangedSignal(Constants.Attributes.EquippedPets):Connect(function()
		rebuild(player)
	end))
	-- Al morir, las mascotas se ocultan; al reaparecer vuelven junto al nuevo personaje.
	table.insert(tracker.Connections, player.CharacterRemoving:Connect(function()
		for _, visual in tracker.Pets do
			visual.Model.Parent = nil
			visual.Current = nil
		end
	end))
	table.insert(tracker.Connections, player.CharacterAdded:Connect(function()
		for _, visual in tracker.Pets do
			visual.Current = nil -- aparecer directamente junto al personaje
			visual.Model.Parent = folder
		end
	end))

	rebuild(player)
end

local function untrack(player: Player)
	local tracker = trackers[player]
	if tracker then
		for _, connection in tracker.Connections do
			connection:Disconnect()
		end
		clearPets(tracker)
		trackers[player] = nil
	end
end

local function update(deltaTime: number)
	elapsed += deltaTime
	local camera = Workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else nil
	local alpha = 1 - math.exp(-SMOOTHING * deltaTime)

	for player, tracker in trackers do
		if #tracker.Pets == 0 then
			continue
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and root:IsA("BasePart") and humanoid) then
			continue
		end
		if cameraPosition and (root.Position - cameraPosition).Magnitude > MAX_RENDER_DISTANCE then
			continue
		end

		-- Altura del suelo bajo el personaje (válido para R6 y R15)
		local groundY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 0.01 then
			flatLook = Vector3.new(0, 0, -1)
		end
		flatLook = flatLook.Unit
		local right = Vector3.new(-flatLook.Z, 0, flatLook.X)
		local velocity = root.AssemblyLinearVelocity
		local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude > MOVING_SPEED
		local rootFlat = Vector3.new(root.Position.X, 0, root.Position.Z)

		for index, visual in tracker.Pets do
			local slot = tracker.Slots[index]
			if not slot then
				continue
			end
			local motion = visual.Motion
			local position = root.Position - flatLook * slot.Z + right * slot.X
			position = Vector3.new(position.X, groundY + motion.Hover, position.Z)
			local target = CFrame.lookAt(position, position + flatLook)

			local current = visual.Current
			if not current or (current.Position - target.Position).Magnitude > SNAP_DISTANCE then
				current = target
			else
				current = current:Lerp(target, alpha)
			end

			-- Si el jugador retrocede sobre la mascota, empujarla fuera de su cuerpo.
			local minDistance = PetLayout.minDistanceFromPlayer(visual.Radius)
			local flatOffset = Vector3.new(current.Position.X, 0, current.Position.Z) - rootFlat
			if flatOffset.Magnitude < minDistance then
				local direction = if flatOffset.Magnitude > 0.01 then flatOffset.Unit else -flatLook
				local pushed = rootFlat + direction * minDistance
				current = CFrame.lookAt(Vector3.new(pushed.X, current.Position.Y, pushed.Z), Vector3.new(pushed.X, current.Position.Y, pushed.Z) + flatLook)
			end
			visual.Current = current

			-- Animación sobre la posición base (no se suaviza para que se note).
			local t = elapsed + visual.Phase
			local lift, roll, pitch = 0, 0, 0
			if moving and motion.Hop and motion.HopSpeed then
				lift = math.abs(math.sin(t * motion.HopSpeed)) * motion.Hop
				if motion.Sway then
					roll = math.sin(t * motion.HopSpeed) * motion.Sway
				end
			else
				lift = math.sin(t * motion.BobSpeed) * motion.Bob
			end
			if motion.Pitch then
				pitch = math.sin(t * motion.BobSpeed) * motion.Pitch
			end
			visual.Root.CFrame = current * CFrame.new(0, lift, 0) * CFrame.Angles(pitch, 0, roll)
		end
	end
end

function PetFollower.start()
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace

	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	for _, player in Players:GetPlayers() do
		track(player)
	end

	RunService.Heartbeat:Connect(update)
	RevealGate.Released:Connect(function()
		rebuild(Players.LocalPlayer)
	end)
end

return PetFollower
