-- Interfaz del ataque según el estilo (solo presentación):
-- - Armas: una MIRA en cruz donde está el ratón (en el centro al apuntar con el clic derecho)
--   que se abre con el desvío del arma y salta al disparar, una marca ✕ cuando le das a algo
--   (roja si lo matas) y las balas que quedan junto a la mira. Mientras se ve la mira, el
--   cursor normal se esconde (vuelve con un panel abierto o el selector de estilo). Con el
--   resto de estilos, el cursor normal.
-- - Sobre el botón de atacar: las balas del cargador (y la recarga) con Armas, o la barra de
--   maná con Magia.
-- Lee los atributos del jugador (CombatStyle, EquippedWeapon, Ammo, AmmoMax, ReloadEnd, Mana,
-- ManaMax); CombatController le avisa de cada disparo (kick) y de cada acierto (hitMarker).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local GunLogic = require(Shared.GunLogic)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local AimCamera = require(script.Parent.AimCamera)

local CombatHud = {}

local FONTS = Theme.Fonts
local INK = Color3.fromRGB(20, 18, 28)
local CROSS_COLOR = Color3.fromRGB(255, 255, 255)
local HIT_COLOR = Color3.fromRGB(255, 255, 255)
local KILL_COLOR = Color3.fromRGB(255, 70, 70)
local AMMO_COLOR = Color3.fromRGB(255, 214, 90)
local RELOAD_COLOR = Color3.fromRGB(255, 140, 80)
local MANA_COLOR = Color3.fromRGB(120, 150, 255)
local BAR_LENGTH = 9
local PIXELS_PER_DEGREE = 3
local RESOURCE_ON_BUTTON = UDim2.new(1, 4, 0, -34) -- encima del botón de atacar
local RESOURCE_TOUCH = UDim2.new(1, -24, 1, -232) -- táctil: encima de los botones de Roblox

local player = Players.LocalPlayer
local ui: { [string]: any } = {}
local kickAmount = 0
local hitUntil = 0
local attributes = Constants.Attributes

local function bar(parent: Instance, name: string, size: Vector2): Frame
	local frame = UiKit.create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = CROSS_COLOR,
		BorderSizePixel = 0,
	}, parent)
	UiKit.create("UIStroke", { Color = INK, Thickness = 1, Transparency = 0.2 }, frame)
	return frame
end

local function build()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("CombatAimHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "CombatAimHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true, -- en coordenadas del ratón (GetMouseLocation)
		DisplayOrder = 4,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local cross = UiKit.create("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(2, 2),
		BackgroundTransparency = 1,
		Visible = false,
	}, screenGui)
	ui.Cross = cross
	ui.Dot = bar(cross, "Dot", Vector2.new(3, 3))
	ui.Dot.Position = UDim2.fromScale(0.5, 0.5)
	ui.Top = bar(cross, "Top", Vector2.new(2, BAR_LENGTH))
	ui.Bottom = bar(cross, "Bottom", Vector2.new(2, BAR_LENGTH))
	ui.Left = bar(cross, "Left", Vector2.new(BAR_LENGTH, 2))
	ui.Right = bar(cross, "Right", Vector2.new(BAR_LENGTH, 2))
	-- Marca de acierto: una ✕ de cuatro rayitas
	local hit = UiKit.create("Frame", {
		Name = "Hit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(2, 2),
		BackgroundTransparency = 1,
		Visible = false,
	}, cross)
	ui.Hit = hit
	ui.HitBars = {}
	for index, rotation in { 45, 135, 225, 315 } do
		local piece = bar(hit, "Hit" .. index, Vector2.new(2, 7))
		local angle = math.rad(rotation)
		piece.Position = UDim2.new(0.5, math.sin(angle) * 11, 0.5, -math.cos(angle) * 11)
		piece.Rotation = rotation
		piece.BackgroundColor3 = HIT_COLOR
		table.insert(ui.HitBars, piece)
	end
	-- Balas junto a la mira
	local ammo = UiKit.text(cross, "Ammo", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0.5, 16, 0.5, 12),
		Size = UDim2.fromOffset(90, 16),
		Font = FONTS.Display,
		TextSize = 14,
		TextColor3 = AMMO_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	UiKit.create("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, ammo)
	ui.CrossAmmo = ammo
	screenGui.Parent = playerGui
	ui.ScreenGui = screenGui
end

-- Barra de balas o de maná sobre el botón de atacar
local function buildResource(anchor: GuiObject)
	local frame = UiKit.create("Frame", {
		Name = "Resource",
		AnchorPoint = Vector2.new(1, 1),
		Position = RESOURCE_ON_BUTTON,
		Size = UDim2.fromOffset(170, 16),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 4,
	}, anchor)
	UiKit.corner(frame, 8)
	UiKit.create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.2, Transparency = 0.6 }, frame)
	local fill = UiKit.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = MANA_COLOR,
		ZIndex = 5,
	}, frame)
	UiKit.corner(fill, 8)
	local label = UiKit.text(frame, "Label", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		ZIndex = 6,
	})
	UiKit.create("UIStroke", { Color = INK, Thickness = 1.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, label)
	-- Tocar la barra de balas recarga (pantallas táctiles)
	local button = UiKit.create("TextButton", {
		Name = "Tap",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 7,
	}, frame)
	ui.Resource = frame
	ui.Fill = fill
	ui.ResourceLabel = label
	ui.ResourceButton = button
end

local function style(): string?
	local value = player:GetAttribute(attributes.CombatStyle)
	return if type(value) == "string" then value else nil
end

-- Se dispara con la mira y el ratón (o apuntando): no en táctil sin ratón
local function crosshairWanted(): boolean
	if style() ~= "Weapons" then
		return false
	end
	if PanelManager.current() ~= nil then
		return false
	end
	local picker = player.PlayerGui:FindFirstChild("StylePickerHud")
	if picker and picker:IsA("ScreenGui") and picker.Enabled then
		return false
	end
	return UserInputService.MouseEnabled or AimCamera.isAds()
end

local function reloadFraction(): number?
	local finish = player:GetAttribute(attributes.ReloadEnd)
	if type(finish) ~= "number" or finish <= 0 then
		return nil
	end
	local spec = GunLogic.spec(player:GetAttribute(attributes.EquippedWeapon))
	local total = math.max(0.1, spec.Reload or 1)
	local left = finish - Workspace:GetServerTimeNow()
	if left <= 0 then
		return nil
	end
	return math.clamp(1 - left / total, 0, 1)
end

local cursorHidden = false
local function render(dt: number)
	local wanted = crosshairWanted()
	local cross = ui.Cross
	cross.Visible = wanted
	if wanted ~= cursorHidden then
		cursorHidden = wanted
		UserInputService.MouseIconEnabled = not wanted
	end
	local currentStyle = style()
	-- En pantallas solo táctiles el botón de atacar no se ve (se usa el de Roblox): la barra
	-- va sola encima de los botones de la derecha
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local holder = if touchOnly or not ui.Anchor then ui.ScreenGui else ui.Anchor
	if ui.Resource.Parent ~= holder then
		ui.Resource.Parent = holder
		ui.Resource.Position = if holder == ui.Anchor then RESOURCE_ON_BUTTON else RESOURCE_TOUCH
	end
	-- Balas o maná
	local ammo = player:GetAttribute(attributes.Ammo)
	local magazine = player:GetAttribute(attributes.AmmoMax)
	local reload = reloadFraction()
	if currentStyle == "Weapons" and type(ammo) == "number" and type(magazine) == "number" and magazine > 0 then
		ui.Resource.Visible = true
		if reload then
			ui.Fill.BackgroundColor3 = RELOAD_COLOR
			ui.Fill.Size = UDim2.fromScale(reload, 1)
			ui.ResourceLabel.Text = "🔄 Recargando…"
		else
			ui.Fill.BackgroundColor3 = AMMO_COLOR
			ui.Fill.Size = UDim2.fromScale(ammo / magazine, 1)
			ui.ResourceLabel.Text = ("🔫 %d / %d"):format(ammo, magazine) .. (if ammo < magazine then "  · R" else "")
		end
	elseif currentStyle == "Magic" then
		local mana = player:GetAttribute(attributes.Mana)
		local maxMana = player:GetAttribute(attributes.ManaMax)
		if type(mana) == "number" and type(maxMana) == "number" and maxMana > 0 then
			ui.Resource.Visible = true
			ui.Fill.BackgroundColor3 = MANA_COLOR
			ui.Fill.Size = UDim2.fromScale(math.clamp(mana / maxMana, 0, 1), 1)
			ui.ResourceLabel.Text = ("💧 %d / %d"):format(mana, maxMana)
		else
			ui.Resource.Visible = false
		end
	else
		ui.Resource.Visible = false
	end
	if not wanted then
		return
	end
	-- Dónde: el ratón, o el centro apuntando
	local camera = Workspace.CurrentCamera
	local position: Vector2
	if AimCamera.isAds() and camera then
		position = camera.ViewportSize / 2
	else
		position = UserInputService:GetMouseLocation()
	end
	cross.Position = UDim2.fromOffset(position.X, position.Y)
	-- Abierta según el desvío del arma (y el salto del último disparo)
	local spec = GunLogic.spec(player:GetAttribute(attributes.EquippedWeapon))
	local spread = GunLogic.spread(spec, AimCamera.isAds())
	kickAmount = math.max(0, kickAmount - dt * 40)
	local gap = 4 + spread * PIXELS_PER_DEGREE + kickAmount
	ui.Top.Position = UDim2.new(0.5, 0, 0.5, -gap - BAR_LENGTH / 2)
	ui.Bottom.Position = UDim2.new(0.5, 0, 0.5, gap + BAR_LENGTH / 2)
	ui.Left.Position = UDim2.new(0.5, -gap - BAR_LENGTH / 2, 0.5, 0)
	ui.Right.Position = UDim2.new(0.5, gap + BAR_LENGTH / 2, 0.5, 0)
	ui.Dot.Visible = spread <= 2 or AimCamera.isAds()
	ui.Hit.Visible = os.clock() < hitUntil
	-- Balas junto a la mira
	if reload then
		ui.CrossAmmo.Text = "🔄"
		ui.CrossAmmo.TextColor3 = RELOAD_COLOR
	elseif type(ammo) == "number" then
		ui.CrossAmmo.Text = tostring(ammo)
		ui.CrossAmmo.TextColor3 = if type(magazine) == "number" and ammo <= math.max(1, magazine * 0.25) then RELOAD_COLOR else AMMO_COLOR
	end
end

-- El disparo hace saltar la mira
function CombatHud.kick(strength: number?)
	kickAmount = math.min(24, kickAmount + 8 * (strength or 1))
end

-- Le has dado a algo (roja si lo has matado)
function CombatHud.hitMarker(killed: boolean)
	hitUntil = os.clock() + (if killed then 0.3 else 0.15)
	for _, piece in ui.HitBars or {} do
		piece.BackgroundColor3 = if killed then KILL_COLOR else HIT_COLOR
	end
end

-- Al tocar la barra de balas (pantalla táctil): `callback` recarga
function CombatHud.onResourceTapped(callback: () -> ())
	if ui.ResourceButton then
		ui.ResourceButton.Activated:Connect(callback)
	end
end

function CombatHud.start(anchor: GuiObject)
	build()
	ui.Anchor = anchor
	buildResource(anchor)
	RunService.RenderStepped:Connect(render)
end

return CombatHud
