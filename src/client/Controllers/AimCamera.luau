-- Cámara y movimiento al apuntar (Armas, clic derecho o L2) y al bloquear (Guerrero):
-- - Apuntar: la cámara se acerca (FieldOfView) y se pone por encima del hombro derecho
--   (Humanoid.CameraOffset), el personaje mira hacia donde mira la cámara (sin girar solo
--   hacia donde anda) y se apunta al centro de la pantalla (AimPoint.setCentered). Roblox ya
--   gira la cámara con el ratón mientras mantienes el clic derecho.
-- - Apuntar y bloquear te hacen caminar más lento (WeaponConfig.Ads.WalkSpeed y
--   StyleConfig.Styles.Warrior.Block.WalkSpeed): se aplica sobre la velocidad que pone el
--   servidor y se devuelve al soltar.
-- Solo para tu personaje y solo se ve en tu cliente; el servidor sabe que apuntas o bloqueas
-- por los avisos del ataque (CombatController: "AdsOn", "BlockOn"…).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local AimPoint = require(script.Parent.AimPoint)

local AimCamera = {}

local player = Players.LocalPlayer
local ads = false
local slow = 1
local defaultFov: number? = nil
local normalSpeed: number? = nil
local lastSet: number? = nil
local changed = Instance.new("BindableEvent")
AimCamera.Changed = changed.Event

function AimCamera.isAds(): boolean
	return ads
end

function AimCamera.setAds(on: boolean)
	if ads == on then
		return
	end
	ads = on
	AimPoint.setCentered(on)
	changed:Fire()
end

-- Más lento mientras dure (1 = normal): bloquear con el Guerrero
function AimCamera.setSlow(factor: number)
	slow = math.clamp(factor, 0.1, 1)
end

local function humanoidOf(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local humanoid = humanoidOf()
	local root = humanoid and humanoid.RootPart
	local spec = WeaponConfig.Ads
	local alpha = math.clamp(dt * 12, 0, 1)
	if camera then
		if ads and not defaultFov then
			defaultFov = camera.FieldOfView
		end
		local target = if ads then spec.FieldOfView else defaultFov
		if target and math.abs(camera.FieldOfView - target) > 0.05 then
			camera.FieldOfView += (target - camera.FieldOfView) * alpha
		elseif not ads and defaultFov then
			camera.FieldOfView = defaultFov
			defaultFov = nil
		end
	end
	if humanoid then
		local offset = if ads then spec.CameraOffset else Vector3.zero
		if (humanoid.CameraOffset - offset).Magnitude > 0.01 then
			humanoid.CameraOffset = humanoid.CameraOffset:Lerp(offset, alpha)
		elseif humanoid.CameraOffset ~= offset then
			humanoid.CameraOffset = offset
		end
		-- Mirar hacia donde mira la cámara
		if ads and camera and root then
			humanoid.AutoRotate = false
			local look = camera.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 0.05 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
			end
		end
		-- Más lento apuntando o bloqueando, sobre la velocidad que ponga el servidor. WalkSpeed
		-- se guarda con menos decimales: se compara con margen (si no, se reduciría una y otra vez)
		local factor = (if ads then spec.WalkSpeed else 1) * slow
		local ours = lastSet ~= nil and math.abs(humanoid.WalkSpeed - lastSet) < 0.01
		if factor < 0.999 then
			if not ours then
				normalSpeed = humanoid.WalkSpeed -- la puso el servidor (o es la primera vez)
			end
			local wanted = (normalSpeed or humanoid.WalkSpeed) * factor
			if lastSet == nil or math.abs(wanted - lastSet) > 0.001 or not ours then
				humanoid.WalkSpeed = wanted
			end
			lastSet = wanted
		elseif normalSpeed then
			if ours then
				humanoid.WalkSpeed = normalSpeed
			end
			normalSpeed = nil
			lastSet = nil
		end
	end
end

local wasAds = false
function AimCamera.start()
	RunService.RenderStepped:Connect(function(dt)
		step(dt)
		-- Al dejar de apuntar, el personaje vuelve a girar solo
		if wasAds and not ads then
			local humanoid = humanoidOf()
			if humanoid then
				humanoid.AutoRotate = true
			end
		end
		wasAds = ads
	end)
	player.CharacterAdded:Connect(function()
		AimCamera.setAds(false)
		slow = 1
		normalSpeed = nil
		lastSet = nil
	end)
end

return AimCamera
