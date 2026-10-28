-- ⚙️ Ajustes: el tamaño de la interfaz (pruebas con amigos: el HUD tapaba demasiado y no se
-- podía achicar) y los 👤 Personajes. Botón pequeño de engranaje (abajo a la izquierda en
-- escritorio; arriba en la columna izquierda en táctil, donde abajo está el joystick) y un
-- panel con − / + que cambia el tamaño al momento. Se guarda con la partida (UserScale →
-- SetSetting → SettingsService).
--
-- Personajes (ProfileLogic; ProfileService): hasta 3, cada uno con su clase fija y su
-- progreso. La lista sale del atributo Profiles; "Jugar" o "＋ Crear" piden ProfileAction y el
-- servidor guarda y te hace volver a entrar con ese personaje.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local SettingsLogic = require(Shared.SettingsLogic)
local ProfileLogic = require(Shared.ProfileLogic)
local StyleConfig = require(Shared.Config.StyleConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local HudDock = require(script.Parent.Parent.UI.HudDock)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local UserScale = require(script.Parent.Parent.UI.UserScale)
local Toasts = require(script.Parent.Parent.UI.Toasts)

local THEME = Theme.Colors
local FONTS = Theme.Fonts

local SettingsController = {}

local PANEL_NAME = "Settings"
local PANEL_SIZE = Vector2.new(440, 520)
local GEAR = 44 -- lado del botón a escala 1
local GEAR_EDGE = 16
local ROW_HEIGHT = 58
local ROW_GAP = 8
local LIST_TOP = 252

local player = Players.LocalPlayer

type ProfileRow = { Frame: Frame, Icon: TextLabel, Name: TextLabel, Detail: TextLabel, Button: TextButton }

local function buildProfileRow(parent: Instance, index: number): ProfileRow
	local frame = UiKit.create("Frame", {
		Name = "Profile" .. index,
		Position = UDim2.fromOffset(22, LIST_TOP + (index - 1) * (ROW_HEIGHT + ROW_GAP)),
		Size = UDim2.new(1, -44, 0, ROW_HEIGHT),
		BackgroundColor3 = THEME.Inset,
	}, parent)
	UiKit.corner(frame, 10)
	local stroke = UiKit.stroke(frame, THEME.Gold, 2, 0)
	stroke.Name = "Current"
	local icon = UiKit.text(frame, "Icon", {
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.fromOffset(44, ROW_HEIGHT),
		Font = FONTS.Display,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local name = UiKit.text(frame, "Name", {
		Position = UDim2.fromOffset(58, 7),
		Size = UDim2.new(1, -186, 0, 22),
		Font = FONTS.Display,
		TextSize = 19,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local detail = UiKit.text(frame, "Detail", {
		Position = UDim2.fromOffset(58, 31),
		Size = UDim2.new(1, -186, 0, 18),
		Font = FONTS.Light,
		TextSize = 14,
		TextColor3 = THEME.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local button = UiKit.button(frame, "Play", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(112, 40),
		TextSize = 17,
		Text = "▶ Jugar",
	})
	return { Frame = frame, Icon = icon, Name = name, Detail = detail, Button = button }
end

-- Elegir la clase del personaje nuevo: tapa la lista (cuatro clases y "Crear y jugar")
local function buildChooser(panel: Instance)
	local chooser = UiKit.create("Frame", {
		Name = "NewProfile",
		Position = UDim2.fromOffset(12, 184),
		Size = UDim2.new(1, -24, 1, -196),
		BackgroundColor3 = THEME.Panel,
		Active = true, -- que los clics no lleguen a la lista de debajo
		Visible = false,
		ZIndex = 10,
	}, panel)
	UiKit.corner(chooser, 12)
	UiKit.text(chooser, "Title", {
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 28),
		Font = FONTS.Display,
		TextSize = 21,
		Text = "Clase del nuevo personaje",
		ZIndex = 11,
	})
	UiKit.text(chooser, "Hint", {
		Position = UDim2.fromOffset(10, 34),
		Size = UDim2.new(1, -20, 0, 36),
		Font = FONTS.Light,
		TextSize = 14,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = THEME.Muted,
		Text = "Empieza desde cero con esa clase (no se cambia). Tus pases de Robux valen para todos.",
		ZIndex = 11,
	})
	local cards: { [string]: TextButton } = {}
	for index, styleId in StyleConfig.Order do
		local def = StyleConfig.Styles[styleId]
		local column = (index - 1) % 2
		local line = math.floor((index - 1) / 2)
		local card = UiKit.button(chooser, styleId, {
			Position = UDim2.new(column * 0.5, if column == 0 then 10 else 5, 0, 76 + line * 62),
			Size = UDim2.new(0.5, -15, 0, 54),
			BackgroundColor3 = def.Color:Lerp(Color3.new(0, 0, 0), 0.25),
			TextSize = 19,
			Text = ("%s %s"):format(def.Icon, def.DisplayName),
			ZIndex = 11,
		})
		UiKit.stroke(card, THEME.Outline, 2, 0).Name = "Pick"
		cards[styleId] = card
	end
	local cancel = UiKit.button(chooser, "Cancel", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(0.5, -15, 0, 42),
		BackgroundColor3 = THEME.Secondary,
		TextSize = 17,
		Text = "Cancelar",
		ZIndex = 11,
	})
	local confirm = UiKit.button(chooser, "Confirm", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.new(0.5, -15, 0, 42),
		TextSize = 17,
		Text = "Crear y jugar",
		ZIndex = 11,
	})
	return { Frame = chooser, Cards = cards, Cancel = cancel, Confirm = confirm }
end

local function buildPanel(playerGui: Instance)
	local existing = playerGui:FindFirstChild("SettingsHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "SettingsHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local panel, panelScale = UiKit.panel(screenGui, "SettingsPanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		Text = "⚙️ Ajustes",
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})

	-- Tamaño de la interfaz: [−]  90 %  [+]
	local row = UiKit.create("Frame", {
		Name = "HudScaleRow",
		Position = UDim2.fromOffset(22, 64),
		Size = UDim2.new(1, -44, 0, 58),
		BackgroundColor3 = THEME.Inset,
	}, panel)
	UiKit.corner(row, 10)
	UiKit.text(row, "Label", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -190, 1, 0),
		Font = FONTS.Display,
		TextSize = 19,
		TextWrapped = true,
		Text = "Tamaño de la interfaz",
	})
	local minus = UiKit.button(row, "Smaller", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -124, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = THEME.Secondary,
		TextSize = 26,
		Text = "−",
	})
	local value = UiKit.text(row, "Value", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -60, 0.5, 0),
		Size = UDim2.fromOffset(62, 40),
		Font = FONTS.Display,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "100 %",
	})
	local plus = UiKit.button(row, "Bigger", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = THEME.Secondary,
		TextSize = 26,
		Text = "+",
	})
	UiKit.text(panel, "Hint", {
		Position = UDim2.fromOffset(22, 130),
		Size = UDim2.new(1, -200, 0, 36),
		Font = FONTS.Light,
		TextSize = 14,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = THEME.Muted,
		Text = "Más pequeño = ves más del juego. Se guarda con tu partida.",
	})
	local reset = UiKit.button(panel, "Reset", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -22, 0, 130),
		Size = UDim2.fromOffset(160, 34),
		BackgroundColor3 = THEME.Secondary,
		TextSize = 16,
		Text = "Normal (100 %)",
	})

	-- 👤 Personajes
	UiKit.create("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(22, 178),
		Size = UDim2.new(1, -44, 0, 2),
		BackgroundColor3 = THEME.Inset,
		BorderSizePixel = 0,
	}, panel)
	UiKit.text(panel, "ProfilesTitle", {
		Position = UDim2.fromOffset(22, 188),
		Size = UDim2.new(1, -44, 0, 28),
		Font = FONTS.Display,
		TextSize = 23,
		Text = "👤 Personajes",
	})
	local profilesHint = UiKit.text(panel, "ProfilesHint", {
		Position = UDim2.fromOffset(22, 216),
		Size = UDim2.new(1, -44, 0, 32),
		Font = FONTS.Light,
		TextSize = 14,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = THEME.Muted,
		Text = "Cada uno con su clase y su progreso. Los pases de Robux valen para todos.",
	})
	local rows = {}
	for index = 1, ProfileLogic.MaxProfiles do
		rows[index] = buildProfileRow(panel, index)
	end
	local status = UiKit.text(panel, "ProfilesStatus", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 22, 1, -12),
		Size = UDim2.new(1, -44, 0, 36),
		Font = FONTS.Light,
		TextSize = 14,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextColor3 = THEME.Muted,
		Text = "Al cambiar se guarda todo y vuelves a entrar con ese personaje.",
	})
	local chooser = buildChooser(panel)
	screenGui.Parent = playerGui
	return {
		ScreenGui = screenGui,
		Panel = panel,
		PanelScale = panelScale,
		Close = close,
		Minus = minus,
		Plus = plus,
		Value = value,
		Reset = reset,
		ProfilesHint = profilesHint,
		Rows = rows,
		Status = status,
		Chooser = chooser,
	}
end

-- Engranaje: azulejo gris oscuro con contorno negro, como los del menú pero pequeño.
local function buildGear(playerGui: Instance): (TextButton, ScreenGui)
	local existing = playerGui:FindFirstChild("SettingsButtonHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "SettingsButtonHud",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local gear = UiKit.create("TextButton", {
		Name = "SettingsButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, GEAR_EDGE, 1, -GEAR_EDGE),
		Size = UDim2.fromOffset(GEAR, GEAR),
		BackgroundColor3 = Color3.fromRGB(58, 61, 69),
		AutoButtonColor = true,
		Font = FONTS.Display,
		TextSize = 24,
		TextColor3 = THEME.Text,
		Text = "⚙️",
	}, screenGui)
	UiKit.corner(gear, 12)
	UiKit.shade(gear, Theme.Finish.ButtonShade)
	UiKit.stroke(gear, THEME.Outline, 3, 0)
	local scale = UiKit.create("UIScale", {}, gear)
	UiKit.bindScale(screenGui, { scale })
	screenGui.Parent = playerGui
	return gear, screenGui
end

local RESULT_TEXT = {
	Full = ("Ya tienes %d personajes."):format(ProfileLogic.MaxProfiles),
	TooFast = "Espera un momento…",
	NotReady = "Tus datos aún se están cargando.",
	AlreadySelected = "Ya estás jugando con ese personaje.",
	Unavailable = "Ahora no se puede (tus datos no se pudieron cargar o guardar). Prueba más tarde.",
}

-- Texto de la segunda línea: "🔁 2 renacimientos · Valle Morado"
local function detailOf(entry: ProfileLogic.Listed): string
	local parts = {}
	if entry.Rebirths > 0 then
		table.insert(parts, ("🔁 %d %s"):format(entry.Rebirths, if entry.Rebirths == 1 then "renacimiento" else "renacimientos"))
	end
	local zone = entry.Zone and ZoneConfig.Zones[entry.Zone]
	table.insert(parts, if zone and zone.DisplayName then zone.DisplayName else "Recién creado")
	return table.concat(parts, " · ")
end

local function bindProfiles(ui: any)
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local actionRemote = remotes:WaitForChild(Constants.Remotes.ProfileAction) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.ProfileResult) :: RemoteEvent
	local pending = false -- esperando a volver a entrar
	local picked: string? = nil
	local actions: { [number]: () -> () } = {}

	local function setStatus(text: string, color: Color3?)
		ui.Status.Text = text
		ui.Status.TextColor3 = color or THEME.Muted
	end

	local function setButton(button: TextButton, text: string, color: Color3, disabled: boolean)
		button.Text = text
		button.BackgroundColor3 = if disabled then THEME.Disabled else color
		UiKit.setDisabled(button, disabled)
	end

	local function renderChooser()
		for styleId, card in ui.Chooser.Cards do
			local stroke = card:FindFirstChild("Pick") :: UIStroke?
			if stroke then
				stroke.Color = if styleId == picked then THEME.Gold else THEME.Outline
				stroke.Thickness = if styleId == picked then 4 else 2
			end
		end
		setButton(ui.Chooser.Confirm, if pending then "Entrando…" else "Crear y jugar", THEME.Buy, picked == nil or pending)
	end

	local function render()
		local list = ProfileLogic.decode(player:GetAttribute(Constants.Attributes.Profiles))
		local current = player:GetAttribute(Constants.Attributes.ProfileSlot)
		local available = #list > 0
		ui.ProfilesHint.Text = if available
			then "Cada uno con su clase y su progreso. Los pases de Robux valen para todos."
			else "Los personajes no están disponibles ahora (tu partida no se guarda en esta sesión)."
		local bySlot = {}
		for _, entry in list do
			bySlot[entry.Slot] = entry
		end
		for index, row in ui.Rows do
			row.Frame.Visible = available
			local entry = bySlot[index]
			local playing = entry ~= nil and entry.Slot == current
			local stroke = row.Frame:FindFirstChild("Current") :: UIStroke?
			if stroke then
				stroke.Transparency = if playing then 0 else 1
			end
			if entry then
				local def = entry.Style and StyleConfig.Styles[entry.Style]
				row.Icon.Text = if def then def.Icon else "⇄"
				row.Name.Text = if def then def.DisplayName else "Personaje de siempre"
				row.Name.TextColor3 = if def then def.Color else THEME.Text
				row.Detail.Text = if def then detailOf(entry) else detailOf(entry) .. " · cambia de estilo"
				if playing then
					setButton(row.Button, "✓ Jugando", THEME.Inset, true)
				else
					setButton(row.Button, "▶ Jugar", THEME.Buy, pending)
				end
				actions[index] = function()
					if not playing then
						pending = true
						setStatus("✨ Guardando… vuelves a entrar con ese personaje.", THEME.Gold)
						actionRemote:FireServer("Select", index)
						render()
					end
				end
			else
				row.Icon.Text = "＋"
				row.Name.Text = "Hueco libre"
				row.Name.TextColor3 = THEME.Muted
				row.Detail.Text = "Crea un personaje con otra clase"
				setButton(row.Button, "＋ Crear", THEME.Accent, pending)
				actions[index] = function()
					picked = nil
					ui.Chooser.Frame.Visible = true
					renderChooser()
				end
			end
		end
		renderChooser()
	end

	for index, row in ui.Rows do
		row.Button.Activated:Connect(function()
			local action = actions[index]
			if action and not pending and row.Button:GetAttribute("Disabled") ~= true then
				action()
			end
		end)
	end
	for styleId, card in ui.Chooser.Cards do
		card.Activated:Connect(function()
			if not pending then
				picked = styleId
				renderChooser()
			end
		end)
	end
	ui.Chooser.Cancel.Activated:Connect(function()
		ui.Chooser.Frame.Visible = false
		picked = nil
	end)
	ui.Chooser.Confirm.Activated:Connect(function()
		if picked and not pending then
			pending = true
			setStatus("✨ Creando tu personaje… vuelves a entrar con él.", THEME.Gold)
			actionRemote:FireServer("Create", picked)
			render()
		end
	end)
	resultRemote.OnClientEvent:Connect(function(success: any, code: any)
		if success == true then
			setStatus("✨ Guardado. Volviendo a entrar con tu personaje…", THEME.Gold)
			Toasts.show("👤 Cambiando de personaje…", { Color = THEME.Gold, Key = "Profiles" })
			return
		end
		pending = false
		local text = RESULT_TEXT[code] or "No se pudo cambiar de personaje."
		setStatus(text, THEME.Error)
		Toasts.show("👤 " .. text, { Color = THEME.Error, Key = "Profiles" })
		render()
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.Profiles):Connect(render)
	player:GetAttributeChangedSignal(Constants.Attributes.ProfileSlot):Connect(render)
	render()
	return function()
		if not pending then
			ui.Chooser.Frame.Visible = false
			picked = nil
		end
		render()
	end
end

function SettingsController.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local ui = buildPanel(playerGui)
	local gear, gearGui = buildGear(playerGui)

	local function render()
		local current = UserScale.get()
		ui.Value.Text = SettingsLogic.hudScaleLabel(current)
		local list = SettingsLogic.HudScales
		UiKit.setDisabled(ui.Minus, current <= list[1])
		UiKit.setDisabled(ui.Plus, current >= list[#list])
		UiKit.setDisabled(ui.Reset, current == SettingsLogic.DefaultHudScale)
	end
	local function change(steps: number)
		local nextScale = SettingsLogic.stepHudScale(UserScale.get(), steps)
		if nextScale ~= UserScale.get() then
			UserScale.set(nextScale)
		end
	end
	ui.Minus.Activated:Connect(function()
		change(-1)
	end)
	ui.Plus.Activated:Connect(function()
		change(1)
	end)
	ui.Reset.Activated:Connect(function()
		UserScale.set(SettingsLogic.DefaultHudScale)
	end)
	UserScale.watch(render)
	render()
	local renderProfiles = bindProfiles(ui)

	PanelManager.register(PANEL_NAME, ui.Panel, {
		OnOpen = function()
			render()
			renderProfiles()
		end,
	})
	UiKit.bindModalLayout(ui.ScreenGui, ui.PanelScale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition(PANEL_NAME, position)
	end)
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	gear.Activated:Connect(function()
		PanelManager.toggle(PANEL_NAME)
	end)

	-- Escritorio: esquina de abajo a la izquierda (libre). Táctil: ahí descansa el pulgar,
	-- así que va arriba en la columna izquierda del HUD (encima del seguimiento de misiones).
	local function place()
		local touch = HudDock.layout().Touch == true
		if touch then
			if gear.Parent ~= HudDock.column("Left") then
				HudDock.attach("Left", gear, 1)
			end
		elseif gear.Parent ~= gearGui then
			gear.Parent = gearGui
			gear.AnchorPoint = Vector2.new(0, 1)
			gear.Position = UDim2.new(0, GEAR_EDGE, 1, -GEAR_EDGE)
		end
	end
	HudDock.Changed:Connect(place)
	place()
end

return SettingsController
