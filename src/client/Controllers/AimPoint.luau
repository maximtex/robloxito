-- Punto del mundo al que apunta el jugador (lo usan los disparos, CombatController, y las
-- habilidades, StyleController). El servidor decide a quién da; esto solo dice "hacia aquí".
-- - Ratón o toque: lo que hay bajo el cursor (el cuerpo de un enemigo, si lo toca con un
--   margen de CombatConfig.AimRadius; si no, el suelo o la pared). Se saltan tu personaje,
--   los efectos, las mascotas y las piezas invisibles o que no chocan.
-- - Mando, botón táctil o botón de la pantalla: delante del personaje (hacia donde mira).
-- También gira al personaje hacia donde apunta mientras dispara (faceToward).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared.Config.CombatConfig)
local WaveVisibility = require(script.Parent.WaveVisibility)

local AimPoint = {}

local AIM_DISTANCE = 400 -- largo de la línea del cursor desde la cámara
local SELECT_RANGE = 90 -- el cursor solo se pega a enemigos a esta distancia del personaje
local FACING_DISTANCE = 40
local MAX_SKIPS = 8 -- piezas que se saltan (invisibles, sin choque) antes de rendirse
-- Carpetas de efectos y mascotas del cliente (no son el mundo)
local IGNORED_FOLDERS = { "ClientCombatFX", "ClientPets", "ClientAbilityFX", "ClientStyleFX", "ClientWaveFX", "ClientEnemyFX", "ClientAmbience", "ClientTutorialGuide", "ClientWaveFxWorld" }

local player = Players.LocalPlayer

local function rootOf(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Delante del personaje, a `distance` (FACING_DISTANCE si no se dice)
function AimPoint.facing(distance: number?): Vector3?
	local root = rootOf()
	if not root then
		return nil
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
	return root.Position + flat * (distance or FACING_DISTANCE)
end

-- Modelo del enemigo (Workspace.Enemies.<Zona>.<Modelo>) al que pertenece una pieza
local function enemyModelOf(instance: Instance, enemiesFolder: Instance): Model?
	local current: Instance? = instance
	while current and current.Parent and current.Parent.Parent ~= enemiesFolder do
		current = current.Parent
	end
	if current and current:IsA("Model") and current.Parent and current.Parent.Parent == enemiesFolder then
		return current
	end
	return nil
end

local enemyParams = RaycastParams.new()
enemyParams.FilterType = Enum.RaycastFilterType.Include

-- Enemigo vivo (y de tu "mundo") que toca la línea del cursor: su centro
local function enemyOnRay(root: BasePart, ray: Ray): Vector3?
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if not enemiesFolder then
		return nil
	end
	enemyParams.FilterDescendantsInstances = { enemiesFolder }
	local hit = Workspace:Spherecast(ray.Origin, CombatConfig.AimRadius, ray.Direction.Unit * AIM_DISTANCE, enemyParams)
	local model = hit and enemyModelOf(hit.Instance, enemiesFolder)
	if not model or model:GetAttribute("DiedAt") ~= nil or not WaveVisibility.isVisible(model) then
		return nil
	end
	local health = model:GetAttribute("Health")
	local enemyRoot = model:FindFirstChild("HumanoidRootPart")
	if (health ~= nil and health <= 0) or not (enemyRoot and enemyRoot:IsA("BasePart")) then
		return nil
	end
	local offset = enemyRoot.Position - root.Position
	if Vector2.new(offset.X, offset.Z).Magnitude > SELECT_RANGE then
		return nil
	end
	return enemyRoot.Position
end

local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude

-- Primer sólido visible bajo la línea (sin tu personaje, efectos, mascotas ni zonas invisibles)
local function worldOnRay(ray: Ray): Vector3?
	local ignore: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	for _, name in IGNORED_FOLDERS do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	local origin, direction = ray.Origin, ray.Direction.Unit * AIM_DISTANCE
	for _ = 1, MAX_SKIPS do
		worldParams.FilterDescendantsInstances = ignore
		local hit = Workspace:Raycast(origin, direction, worldParams)
		if not hit then
			return nil
		end
		local part = hit.Instance
		if part:IsA("BasePart") and (part.Transparency >= 0.95 or not part.CanCollide) then
			table.insert(ignore, part)
		else
			return hit.Position
		end
	end
	return nil
end

-- Punto bajo la posición de pantalla (x, y). `viewport`: coordenadas de GetMouseLocation
-- (con la barra de arriba); si no, las de un toque (ScreenPointToRay).
function AimPoint.fromScreen(x: number, y: number, viewport: boolean?): Vector3?
	local root = rootOf()
	local camera = Workspace.CurrentCamera
	if not (root and camera) then
		return nil
	end
	local ray = if viewport then camera:ViewportPointToRay(x, y) else camera:ScreenPointToRay(x, y)
	local onEnemy = enemyOnRay(root, ray)
	if onEnemy then
		return onEnemy
	end
	local unit = ray.Direction.Unit
	-- Lo que quede entre la cámara y el personaje no cuenta (daría la vuelta al disparo)
	local characterAlong = (root.Position - ray.Origin):Dot(unit)
	local hit = worldOnRay(ray)
	if hit and (hit - ray.Origin):Dot(unit) >= characterAlong - 2 then
		return hit
	end
	-- Al aire: donde la línea cruza la altura del personaje (o lejos, si mira hacia arriba)
	if unit.Y < -0.02 then
		local t = (root.Position.Y - 2.5 - ray.Origin.Y) / unit.Y
		if t > 0 then
			return ray.Origin + unit * math.min(t, AIM_DISTANCE)
		end
	end
	return ray.Origin + unit * AIM_DISTANCE
end

-- Apuntando con el clic derecho (Armas): se apunta al centro de la pantalla (la mira)
local centered = false
function AimPoint.setCentered(on: boolean)
	centered = on
end
function AimPoint.isCentered(): boolean
	return centered
end

-- Donde está el ratón ahora (o el centro de la pantalla si apuntas con el clic derecho)
function AimPoint.mouse(): Vector3?
	if centered then
		local camera = Workspace.CurrentCamera
		if camera then
			local size = camera.ViewportSize
			return AimPoint.fromScreen(size.X / 2, size.Y / 2, true)
		end
	end
	local mouse = game:GetService("UserInputService"):GetMouseLocation()
	return AimPoint.fromScreen(mouse.X, mouse.Y, true)
end

-- Cuerpo a cuerpo (Guerrero y Puños): el bicho más cercano a tu alcance, primero los de
-- delante (±70°); si no hay, el más cercano alrededor. Su posición (para girarte y pegarle) o
-- delante de ti si no hay ninguno.
function AimPoint.melee(range: number): Vector3?
	local root = rootOf()
	if not root then
		return nil
	end
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 0.05 then flatLook.Unit else Vector3.new(0, 0, -1)
	local bestFront, frontDistance = nil, math.huge
	local bestAny, anyDistance = nil, math.huge
	if enemiesFolder then
		for _, zone in enemiesFolder:GetChildren() do
			for _, model in zone:GetChildren() do
				local enemyRoot = model:FindFirstChild("HumanoidRootPart")
				local health = model:GetAttribute("Health")
				if enemyRoot and enemyRoot:IsA("BasePart") and (health == nil or health > 0) and model:GetAttribute("DiedAt") == nil and WaveVisibility.isVisible(model) then
					local offset = enemyRoot.Position - root.Position
					local flat = Vector3.new(offset.X, 0, offset.Z)
					local radius = math.max(enemyRoot.Size.X, enemyRoot.Size.Z) / 2
					local distance = flat.Magnitude
					if distance - radius <= range + 2 and math.abs(offset.Y) <= 12 then
						if distance < anyDistance then
							bestAny, anyDistance = enemyRoot.Position, distance
						end
						if distance > 0.1 and flat.Unit:Dot(flatLook) >= math.cos(math.rad(70)) and distance < frontDistance then
							bestFront, frontDistance = enemyRoot.Position, distance
						end
					end
				end
			end
		end
	end
	return bestFront or bestAny or (root.Position + flatLook * math.min(range, 6))
end

-- Gira al personaje (en plano) hacia `point`, sin moverlo
function AimPoint.faceToward(point: Vector3?)
	local root = rootOf()
	if not (root and point) then
		return
	end
	local flat = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
	if flat.Magnitude < 1 then
		return
	end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
end

return AimPoint
