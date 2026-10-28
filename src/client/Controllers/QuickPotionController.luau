-- ❤️ Poción de Vida rápida: botón pequeño (junto al ⚙️ de Ajustes: abajo a la izquierda en
-- escritorio, en la columna izquierda en táctil) y tecla Y (↑ de la cruceta del mando). Solo se
-- ve si tienes alguna; late en rojo cuando te queda poca vida. La cura y sus límites los decide
-- el servidor (ItemService: ItemAction "UsePotion"); los avisos de error los pone el inventario.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ItemConfig = require(Shared.Config.ItemConfig)
local ItemLogic = require(Shared.ItemLogic)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudDock = require(script.Parent.Parent.UI.HudDock)

local THEME = Theme.Colors
local FONTS = Theme.Fonts

local QuickPotionController = {}

local ACTION = "RebirthQuickPotion"
local SIZE = 44 -- lado del botón a escala 1 (como el ⚙️)
local EDGE = 16
local LEFT = EDGE + SIZE + 10 -- a la derecha del ⚙️
local LOW_HEALTH = 0.4 -- late por debajo de esta parte de la vida

local player = Players.LocalPlayer

function QuickPotionController.start()
	local healId = ItemLogic.healPotion()
	if not healId then
		return
	end
	local def = ItemConfig.Potions[healId]
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.ItemAction) :: RemoteEvent
	local stateRemote = remotes:WaitForChild(Constants.Remotes.ItemState) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.ItemResult) :: RemoteEvent
	local requestRemote = remotes:WaitForChild(Constants.Remotes.RequestItems) :: RemoteEvent

	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("QuickPotionHud")
	if existing then
		existing:Destroy()
	end
	local gui = UiKit.create("ScreenGui", {
		Name = "QuickPotionHud",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local button = UiKit.create("TextButton", {
		Name = "QuickPotion",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, LEFT, 1, -EDGE),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = def.Color:Lerp(Color3.new(0, 0, 0), 0.35),
		AutoButtonColor = true,
		Font = FONTS.Display,
		TextSize = 24,
		TextColor3 = THEME.Text,
		Text = def.Icon,
		Visible = false,
	}, gui)
	UiKit.corner(button, 12)
	UiKit.shade(button, Theme.Finish.ButtonShade)
	local stroke = UiKit.stroke(button, THEME.Outline, 3, 0)
	local cooldown = UiKit.create("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		ZIndex = 2,
	}, button)
	UiKit.corner(cooldown, 12)
	local countLabel = UiKit.text(button, "Count", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 2, 1, 2),
		Size = UDim2.fromOffset(30, 16),
		Font = FONTS.Display,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		ZIndex = 3,
	})
	UiKit.outline(countLabel, 1.5)
	local keyLabel = UiKit.text(button, "Key", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(-2, -4),
		Size = UDim2.fromOffset(16, 16),
		Font = FONTS.Display,
		TextSize = 13,
		Text = "Y",
		ZIndex = 3,
	})
	UiKit.outline(keyLabel, 1.5)
	local scale = UiKit.create("UIScale", {}, button)
	UiKit.bindScale(gui, { scale })
	gui.Parent = playerGui

	local count = 0
	local readyAt = 0
	local total = ItemConfig.HealCooldown or 6

	local function refresh()
		button.Visible = count > 0
		countLabel.Text = if count > 1 then "×" .. count else ""
		keyLabel.Visible = UserInputService.KeyboardEnabled
	end

	local function use()
		if count <= 0 or os.clock() < readyAt then
			return
		end
		actionRemote:FireServer("UsePotion", healId)
	end
	button.Activated:Connect(use)
	ContextActionService:BindAction(ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			use()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Y, Enum.KeyCode.DPadUp)

	stateRemote.OnClientEvent:Connect(function(state: any)
		if typeof(state) == "table" and typeof(state.Potions) == "table" then
			local value = state.Potions[healId]
			count = if typeof(value) == "number" then value else 0
			refresh()
		end
	end)
	resultRemote.OnClientEvent:Connect(function(success: any, _code: any, action: any, detail: any)
		if action == "UsePotion" and success == true and typeof(detail) == "table" and detail.PotionId == healId then
			total = if typeof(detail.Cooldown) == "number" then detail.Cooldown else total
			readyAt = os.clock() + total
		end
	end)

	-- Recarga y latido con poca vida
	RunService.Heartbeat:Connect(function()
		if not button.Visible then
			return
		end
		local left = readyAt - os.clock()
		cooldown.Size = UDim2.fromScale(1, if left > 0 then math.clamp(left / total, 0, 1) else 0)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local low = humanoid ~= nil and humanoid.Health > 0 and humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth < LOW_HEALTH and left <= 0
		if low then
			local beat = 0.5 + 0.5 * math.sin(os.clock() * 8)
			stroke.Color = THEME.Outline:Lerp(Color3.fromRGB(255, 70, 90), beat)
			stroke.Thickness = 3 + beat * 2
		elseif stroke.Thickness ~= 3 then
			stroke.Color = THEME.Outline
			stroke.Thickness = 3
		end
	end)

	-- Escritorio: junto al ⚙️ (abajo a la izquierda). Táctil: en la columna izquierda, bajo el ⚙️.
	local function place()
		if HudDock.layout().Touch == true then
			if button.Parent ~= HudDock.column("Left") then
				HudDock.attach("Left", button, 2)
			end
		elseif button.Parent ~= gui then
			button.Parent = gui
			button.AnchorPoint = Vector2.new(0, 1)
			button.Position = UDim2.new(0, LEFT, 1, -EDGE)
		end
	end
	HudDock.Changed:Connect(place)
	place()
	UserInputService.LastInputTypeChanged:Connect(refresh)
	refresh()
	-- Estado inicial (el inventario también lo pide al arrancar)
	task.delay(2, function()
		requestRemote:FireServer()
	end)
end

return QuickPotionController
