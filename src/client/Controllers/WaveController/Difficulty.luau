-- WaveController · Difficulty: ventana para elegir la dificultad de la mazmorra al pulsar E en su
-- altar (solo sale si ya tienes abierta más de una: WaveService "Difficulty"). Normal, 🔥 Difícil
-- y 💀 Pesadilla, cada una con lo que cambia; las cerradas salen con su candado y lo que piden.
-- Elegir manda WaveAction ("Start", { Place, Difficulty }); el servidor vuelve a comprobarlo.
-- Parte de WaveController (ver WaveController/init.luau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local WaveFx = require(script.Parent.Parent.WaveFx)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local INK = Theme.Cartoon.Ink

local ROW_HEIGHT = 74
local PANEL_WIDTH = 460
local COLORS = {
	Normal = Color3.fromRGB(96, 170, 255),
	Hard = Color3.fromRGB(255, 140, 60),
	Nightmare = Color3.fromRGB(196, 92, 255),
}

local ctx: any

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
end

function Part.link(_context: any) end

function Part.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("WaveDifficulty")
	if existing then
		existing:Destroy()
	end
	local gui = UiKit.create("ScreenGui", {
		Name = "WaveDifficulty",
		ResetOnSpawn = false,
		DisplayOrder = 8,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local panel, scale = UiKit.panel(gui, "Panel", Vector2.new(PANEL_WIDTH, 120 + 3 * (ROW_HEIGHT + 10)), Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5))
	panel.Visible = false
	local title = UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -80, 0, 32),
		Font = FONTS.Display,
		TextSize = 26,
		Text = "⚔ Elige la dificultad",
	})
	UiKit.outline(title, 2.5, INK)
	local subtitle = UiKit.text(panel, "Subtitle", {
		Position = UDim2.fromOffset(20, 46),
		Size = UDim2.new(1, -40, 0, 22),
		Font = FONTS.Body,
		TextSize = 17,
		TextColor3 = THEME.Muted,
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 12),
		Size = UDim2.fromOffset(40, 40),
		Text = "✕",
		TextSize = 20,
	})

	local placeId: string? = nil
	local rows = {}
	local function hide()
		panel.Visible = false
		placeId = nil
	end
	close.Activated:Connect(hide)

	for index = 1, 3 do
		local button = UiKit.create("TextButton", {
			Name = "Option" .. index,
			Position = UDim2.fromOffset(20, 80 + (index - 1) * (ROW_HEIGHT + 10)),
			Size = UDim2.new(1, -40, 0, ROW_HEIGHT),
			BackgroundColor3 = THEME.Inset,
			AutoButtonColor = true,
			Text = "",
		}, panel)
		UiKit.corner(button, 12)
		local stroke = UiKit.stroke(button, THEME.Gold, 3, 0)
		UiKit.addStates(button)
		local name = UiKit.text(button, "Name", {
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -28, 0, 28),
			Font = FONTS.Display,
			TextSize = 22,
		})
		UiKit.outline(name, 2, INK)
		local body = UiKit.text(button, "Body", {
			Position = UDim2.fromOffset(14, 38),
			Size = UDim2.new(1, -28, 0, 30),
			Font = FONTS.Body,
			TextSize = 15,
			TextWrapped = true,
			TextColor3 = THEME.Muted,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local row = { Button = button, Stroke = stroke, Name = name, Body = body, Id = nil :: string?, Unlocked = false }
		button.Activated:Connect(function()
			if not (placeId and row.Id) then
				return
			end
			if not row.Unlocked then
				WaveFx.sound("Tick")
				return
			end
			ctx.actionRemote:FireServer("Start", { Place = placeId, Difficulty = row.Id })
			WaveFx.sound("Pick")
			hide()
		end)
		rows[index] = row
	end

	gui.Parent = playerGui
	UiKit.bindScale(gui, { scale })

	-- Se cierra sola si empiezas a jugar o te alejas mucho
	player:GetAttributeChangedSignal(Constants.Attributes.WaveRun):Connect(function()
		if player:GetAttribute(Constants.Attributes.WaveRun) ~= nil then
			hide()
		end
	end)

	ctx.openDifficulty = function(data: any)
		if type(data) ~= "table" or type(data.Place) ~= "string" or type(data.Options) ~= "table" then
			return
		end
		placeId = data.Place
		subtitle.Text = tostring(data.Arena or "")
		for index, row in rows do
			local info = data.Options[index]
			row.Button.Visible = info ~= nil
			if info then
				row.Id = tostring(info.Id)
				row.Unlocked = info.Unlocked == true
				local color = COLORS[row.Id] or THEME.Gold
				row.Stroke.Color = if row.Unlocked then color else THEME.Disabled
				row.Name.TextColor3 = if row.Unlocked then color else THEME.Muted
				row.Name.Text = ("%s %s%s"):format(tostring(info.Icon or ""), tostring(info.Name or ""), if row.Unlocked then "" else "  🔒")
				row.Body.Text = if row.Unlocked then tostring(info.Text or "")
					else ("Gana la %s de este modo para abrirla."):format(tostring(info.Needs or "anterior"))
				UiKit.setDisabled(row.Button, not row.Unlocked)
			end
		end
		panel.Visible = true
		WaveFx.sound("CardsOpen")
	end
end

return Part
