-- Tamaño de la interfaz elegido en ⚙️ Ajustes. Lo aplica al momento (HudLayout.UserScale,
-- que usan HudDock, UiKit y los controladores al calcular su escala) y avisa con Changed
-- para que cada pieza se vuelva a colocar; el servidor lo guarda (SetSetting) y lo devuelve
-- en el atributo HudScale al entrar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local SettingsLogic = require(Shared.SettingsLogic)
local HudLayout = require(script.Parent.HudLayout)

local UserScale = {}

local changed = Instance.new("BindableEvent")
UserScale.Changed = changed.Event

local player = Players.LocalPlayer
-- Tras cambiarlo aquí, el atributo aún trae el valor anterior un momento: se ignora.
local ignoreAttributeUntil = 0

local function apply(value: number)
	local scale = SettingsLogic.sanitizeHudScale(value)
	if scale == HudLayout.UserScale then
		return
	end
	HudLayout.setUserScale(scale)
	changed:Fire(scale)
end

function UserScale.get(): number
	return HudLayout.UserScale
end

-- Lo elige el jugador: se aplica ya y se manda a guardar.
function UserScale.set(value: number)
	local scale = SettingsLogic.sanitizeHudScale(value)
	ignoreAttributeUntil = os.clock() + 2
	apply(scale)
	local remotes = ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName)
	local remote = remotes and remotes:FindFirstChild(Constants.Remotes.SetSetting)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer("HudScale", scale)
	end
end

-- `callback` cada vez que cambia el tamaño (para volver a colocar y escalar).
function UserScale.watch(callback: () -> ()): RBXScriptConnection
	return changed.Event:Connect(function()
		callback()
	end)
end

local function fromAttribute()
	if os.clock() < ignoreAttributeUntil then
		return
	end
	local value = player:GetAttribute(Constants.Attributes.HudScale)
	if type(value) == "number" then
		apply(value)
	end
end
player:GetAttributeChangedSignal(Constants.Attributes.HudScale):Connect(function()
	if os.clock() < ignoreAttributeUntil then
		-- Comprobar al acabar la espera (por si el servidor corrigió el valor)
		task.delay(ignoreAttributeUntil - os.clock() + 0.05, fromAttribute)
		return
	end
	fromAttribute()
end)
fromAttribute()

return UserScale
