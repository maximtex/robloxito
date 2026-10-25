-- Elegir estilo al empezar: a un jugador nuevo (atributo StylePicked = false con sus datos
-- ya cargados) se le enseña una pantalla con los tres estilos (Armas, Puños y Magia), cada
-- uno con lo que hace, su ventaja, su desventaja y sus dos primeras habilidades. Al elegir
-- se pide StyleAction("Pick", estilo) y StyleService lo pone y lo marca (no se vuelve a
-- preguntar; luego se cambia cuando se quiera con la tecla C).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local INK = Color3.fromRGB(43, 29, 63)
local BASE = Vector2.new(900, 520)

local StylePickerController = {}

local player = Players.LocalPlayer

local function build()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("StylePickerHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "StylePickerHud",
		ResetOnSpawn = false,
		DisplayOrder = 20, -- encima del HUD y del tutorial
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, nil)
	local shade = UiKit.create("Frame", {
		Name = "Shade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 8, 20),
		BackgroundTransparency = 0.25,
		Active = true,
	}, screenGui)
	local holder = UiKit.create("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(BASE.X, BASE.Y),
		BackgroundTransparency = 1,
	}, shade)
	local scale = UiKit.create("UIScale", {}, holder)
	local title = UiKit.text(holder, "Title", {
		Size = UDim2.new(1, 0, 0, 56),
		Font = FONTS.Display,
		TextSize = 48,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "¡Elige tu estilo de pelea!",
	})
	UiKit.outline(title, 3, INK)
	UiKit.text(holder, "Subtitle", {
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 0, 24),
		Font = FONTS.Light,
		TextSize = 18,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Cada uno tiene su tienda, sus habilidades y su progreso. Podrás cambiarlo cuando quieras (tecla C).",
	})
	local row = UiKit.create("Frame", {
		Name = "Cards",
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, 0, 0, BASE.Y - 96),
		BackgroundTransparency = 1,
	}, holder)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 18),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local buttons = {}
	for order, id in StyleConfig.Order do
		local def = StyleConfig.Styles[id]
		local card = UiKit.create("Frame", {
			Name = id,
			Size = UDim2.fromOffset(280, BASE.Y - 110),
			BackgroundColor3 = THEME.Inset,
			LayoutOrder = order,
		}, row)
		UiKit.corner(card, 18)
		UiKit.stroke(card, def.Color, 4, 0)
		UiKit.text(card, "Icon", {
			Position = UDim2.fromOffset(0, 12),
			Size = UDim2.new(1, 0, 0, 64),
			Font = FONTS.Display,
			TextSize = 58,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.Icon,
		})
		local name = UiKit.text(card, "Name", {
			Position = UDim2.fromOffset(0, 78),
			Size = UDim2.new(1, 0, 0, 36),
			Font = FONTS.Display,
			TextSize = 32,
			TextColor3 = def.Color,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = def.DisplayName,
		})
		UiKit.outline(name, 2.5, INK)
		local skills = {}
		for _, skillId in def.StartSkills do
			local skill = def.Skills[skillId]
			table.insert(skills, ("%s %s"):format(skill.Icon, skill.Name))
		end
		UiKit.text(card, "Body", {
			Position = UDim2.fromOffset(16, 120),
			Size = UDim2.new(1, -32, 0, 200),
			Font = FONTS.Body,
			TextSize = 15,
			RichText = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = ("%s\n\n<font color=\"#96F096\">✅ %s</font>\n<font color=\"#FF968C\">❌ %s</font>\n\n<b>Empiezas con:</b> %s"):format(def.Attack, def.Pros, def.Cons, table.concat(skills, ", ")),
		})
		local choose = UiKit.button(card, "Choose", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -30, 0, 50),
			BackgroundColor3 = def.Color,
			TextSize = 24,
			Text = "¡Este!",
		})
		buttons[id] = choose
	end
	screenGui.Parent = playerGui
	return { ScreenGui = screenGui, Shade = shade, Holder = holder, Scale = scale, Buttons = buttons }
end

function StylePickerController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.StyleAction) :: RemoteEvent
	local ui = build()
	local chosen = false

	local function fit()
		local size = ui.ScreenGui.AbsoluteSize
		if size.X > 0 and size.Y > 0 then
			ui.Scale.Scale = math.min(1, (size.X - 24) / BASE.X, (size.Y - 24) / BASE.Y)
		end
	end
	ui.ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local function refresh()
		local status = player:GetAttribute(Constants.Attributes.DataStatus)
		local ready = status == "Loaded" or status == "Unavailable"
		local show = ready and player:GetAttribute(Constants.Attributes.StylePicked) == false and not chosen
		if show and not ui.ScreenGui.Enabled then
			ui.ScreenGui.Enabled = true
			fit()
			ui.Scale.Scale *= 0.85
			TweenService:Create(ui.Scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = ui.Scale.Scale / 0.85 }):Play()
		elseif not show then
			ui.ScreenGui.Enabled = false
		end
	end

	for id, button in ui.Buttons do
		button.Activated:Connect(function()
			if chosen then
				return
			end
			chosen = true
			actionRemote:FireServer("Pick", id)
			ui.ScreenGui.Enabled = false
		end)
	end
	player:GetAttributeChangedSignal(Constants.Attributes.StylePicked):Connect(function()
		if player:GetAttribute(Constants.Attributes.StylePicked) == false then
			chosen = false -- (perfil de prueba nuevo en Studio)
		end
		refresh()
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.DataStatus):Connect(refresh)
	refresh()
end

return StylePickerController
