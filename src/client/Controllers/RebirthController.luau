-- Interfaz del renacimiento (solo presentación; el servidor decide todo):
-- - Azulejo "Renacer" en la barra del menú (o tecla T) con una barra del progreso hacia el
--   siguiente renacimiento; su borde late en dorado cuando ya se puede renacer. Aviso
--   "Renacer" en el Cristal del Renacimiento que abre el mismo panel.
-- - Panel (PanelManager): bonificación actual, requisito con barra, lo que se gana y lo que
--   se reinicia, botón de renacer con confirmación (dos pulsaciones) y tienda de fichas.
-- - Al renacer: destello, sacudida, título "RENACIMIENTO II", estallido de luz en el
--   cristal y sonido. Corona de gemas sobre el cristal (una por renacimiento, solo la ve
--   cada jugador para sí) y aviso breve cuando renace otro jugador.
-- El estado sale de atributos del Player (Rebirths, RebirthTokens, RebirthShop,
-- UpgradeLevel_GeneratorPower) y los números de RebirthLogic, igual que en el servidor.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local RebirthLogic = require(Shared.RebirthLogic)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.UI.MenuBar)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local AbilityController = require(script.Parent.AbilityController)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local Codes = Constants.PurchaseCodes
local Attributes = Constants.Attributes

local PANEL_NAME = "Rebirth"
local PANEL_SIZE = Vector2.new(620, 560)
local ROW_HEIGHT = 64
local CONFIRM_SECONDS = 4
local LEVEL_ATTRIBUTE = Attributes.UpgradeLevelPrefix .. RebirthConfig.UpgradeId
local UPGRADE_NAME = EconomyConfig.Upgrades[RebirthConfig.UpgradeId].DisplayName
local GOLD = RebirthConfig.Colors.Glow
local CRYSTAL_CENTER = GeneratorConfig.Position + Vector3.new(0, GeneratorConfig.CoreHeight, 0)

local MESSAGES = {
	[Codes.LevelTooLow] = "Aún te falta Resonancia para renacer.",
	[Codes.InsufficientTokens] = "Te faltan fichas.",
	[Codes.MaxLevel] = "Esa ventaja ya está al máximo.",
	[Codes.NotReady] = "Tus datos aún se están cargando.",
	[Codes.TooFast] = "Espera un momento.",
	[Codes.InvalidRequest] = "Esa acción no está disponible.",
}

local RebirthController = {}

local player = Players.LocalPlayer

-- Estado (de los atributos) ----------------------------------------------------------------

local function attributeNumber(name: string): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- Datos con la misma forma que los del servidor, para usar RebirthLogic.
local function currentData(): any
	return {
		Count = attributeNumber(Attributes.Rebirths),
		Tokens = attributeNumber(Attributes.RebirthTokens),
		Shop = RebirthLogic.parseShop(player:GetAttribute(Attributes.RebirthShop)),
		BestLevel = attributeNumber(Attributes.RebirthBestLevel),
		LastAt = 0,
	}
end

local function dataReady(): boolean
	local status = player:GetAttribute(Attributes.DataStatus)
	return status == "Loaded" or status == "Unavailable"
end

local function multiplierText(value: number): string
	local rounded = math.floor(value * 100 + 0.5) / 100
	if rounded == math.floor(rounded) then
		return "×" .. tostring(math.floor(rounded))
	end
	return (("×%.2f"):format(rounded):gsub("0$", ""))
end

local function tokensText(count: number): string
	return if count == 1 then "1 ficha" else ("%d fichas"):format(count)
end

-- Sonido y efectos -------------------------------------------------------------------------

local function playSound(id: string, volume: number, pitch: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Estallido de luz en el cristal (local): anillo que se expande y chispas.
local function crystalBurst(color: Color3)
	local folder = Workspace:FindFirstChild("RebirthEffects") or Instance.new("Folder")
	folder.Name = "RebirthEffects"
	folder.Parent = Workspace
	local ring = Instance.new("Part")
	ring.Name = "Shockwave"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 4, 4)
	ring.CFrame = CFrame.new(GeneratorConfig.Position + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	ring.Parent = folder
	TweenService:Create(ring, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, 70, 70), Transparency = 1 }):Play()

	local core = Instance.new("Part")
	core.Name = "Sparks"
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Transparency = 1
	core.Size = Vector3.one
	core.CFrame = CFrame.new(CRYSTAL_CENTER)
	core.Parent = folder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	emitter.Speed = NumberRange.new(14, 30)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(1, 1.8)
	emitter.Drag = 2
	emitter.Rate = 0
	emitter.Parent = core
	emitter:Emit(120)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 40
	light.Brightness = 6
	light.Parent = core
	TweenService:Create(light, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	task.delay(3, function()
		ring:Destroy()
		core:Destroy()
	end)
end

-- Corona de gemas sobre el cristal (local: cada jugador ve la suya) ---------------------------

local halo = {
	Folder = nil :: Folder?,
	Gems = {} :: { BasePart },
	Count = -1,
}

local function haloColor(count: number): Color3
	local tier = RebirthLogic.haloTier(count)
	return RebirthConfig.Colors.Halo[math.max(1, tier)]
end

local function rebuildHalo(count: number)
	if halo.Count == count then
		return
	end
	halo.Count = count
	if not halo.Folder then
		local folder = Instance.new("Folder")
		folder.Name = "RebirthHalo"
		folder.Parent = Workspace
		halo.Folder = folder
	end
	for _, gem in halo.Gems do
		gem:Destroy()
	end
	table.clear(halo.Gems)
	local gems = math.min(count, RebirthConfig.MaxHaloGems)
	local color = haloColor(count)
	for index = 1, gems do
		local gem = Instance.new("Part")
		gem.Name = "Gem" .. index
		gem.Anchored = true
		gem.CanCollide = false
		gem.CanQuery = false
		gem.CanTouch = false
		gem.CastShadow = false
		gem.Size = Vector3.new(0.55, 0.95, 0.55)
		gem.Material = if index % 2 == 0 then Enum.Material.Glass else Enum.Material.Neon
		gem.Transparency = if index % 2 == 0 then 0.15 else 0
		gem.Color = if index % 2 == 0 then color:Lerp(Color3.new(1, 1, 1), 0.35) else color
		gem.Parent = halo.Folder
		table.insert(halo.Gems, gem)
	end
end

local haloElapsed = 0
local function updateHalo(deltaTime: number)
	local count = #halo.Gems
	if count == 0 then
		return
	end
	haloElapsed += deltaTime
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - CRYSTAL_CENTER).Magnitude > GeneratorConfig.Animation.MaxDistance then
		return
	end
	local parts, cframes = {}, {}
	local radius = 2.6 + count * 0.12
	local center = CRYSTAL_CENTER + Vector3.new(0, 6.6 + math.sin(haloElapsed * 0.8) * 0.25, 0)
	for index, gem in halo.Gems do
		local angle = haloElapsed * 0.5 + (index / count) * math.pi * 2
		local position = center + Vector3.new(math.cos(angle) * radius, math.sin(haloElapsed * 1.6 + index) * 0.18, math.sin(angle) * radius)
		table.insert(parts, gem)
		table.insert(cframes, CFrame.new(position) * CFrame.Angles(0, -angle + haloElapsed, 0) * CFrame.Angles(0, 0, math.rad(45)) * CFrame.Angles(math.rad(45), 0, 0))
	end
	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Construcción de la interfaz ------------------------------------------------------------------

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("RebirthHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "RebirthHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	-- Panel ----------------------------------------------------------------------------------
	local panel, panelScale = UiKit.panel(screenGui, "RebirthPanel", PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	UiKit.text(panel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		TextColor3 = GOLD,
		Text = "🔄 Renacimiento",
	})
	local subtitle = UiKit.text(panel, "Subtitle", {
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(1, -90, 0, 20),
		Font = FONTS.Light,
		TextSize = 15,
		TextColor3 = THEME.Muted,
	})
	local close = UiKit.button(panel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})

	-- Tarjeta de estado
	local card = UiKit.create("Frame", {
		Name = "Status",
		Position = UDim2.fromOffset(22, 78),
		Size = UDim2.new(1, -44, 0, 156),
		BackgroundColor3 = THEME.Inset,
		BackgroundTransparency = 0.25,
	}, panel)
	UiKit.corner(card, 12)
	UiKit.stroke(card, GOLD, 1.5, 0.4)
	local bonus = UiKit.text(card, "Bonus", {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -28, 0, 22),
		Font = FONTS.Display,
		TextSize = 18,
		TextColor3 = GOLD,
	})
	local requirement = UiKit.text(card, "Requirement", {
		Position = UDim2.fromOffset(14, 34),
		Size = UDim2.new(1, -28, 0, 20),
		Font = FONTS.Body,
		TextSize = 15,
	})
	local track = UiKit.create("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(14, 58),
		Size = UDim2.new(1, -28, 0, 20),
		BackgroundColor3 = THEME.Panel,
		BorderSizePixel = 0,
	}, card)
	UiKit.corner(track, 8)
	local fill = UiKit.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = GOLD,
		BorderSizePixel = 0,
	}, track)
	UiKit.corner(fill, 8)
	UiKit.create("UIGradient", {
		Color = ColorSequence.new(GOLD, Color3.fromRGB(255, 244, 200)),
	}, fill)
	local trackText = UiKit.text(track, "Label", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		ZIndex = 3,
	})
	local gain = UiKit.text(card, "Gain", {
		Position = UDim2.fromOffset(14, 84),
		Size = UDim2.new(1, -28, 0, 20),
		Font = FONTS.Body,
		TextSize = 15,
		TextColor3 = THEME.BuyHighlight,
	})
	local resets = UiKit.text(card, "Resets", {
		Position = UDim2.fromOffset(14, 108),
		Size = UDim2.new(1, -28, 0, 40),
		Font = FONTS.Light,
		TextSize = 13,
		TextColor3 = THEME.Muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local rebirthButton = UiKit.button(panel, "RebirthNow", {
		Position = UDim2.fromOffset(22, 244),
		Size = UDim2.new(1, -44, 0, 46),
		TextSize = 22,
		Text = "🔄 Renacer",
	})
	local rebirthShimmer = UiKit.shimmer(rebirthButton, 10)

	local shopTitle = UiKit.text(panel, "ShopTitle", {
		Position = UDim2.fromOffset(22, 302),
		Size = UDim2.new(1, -44, 0, 24),
		Font = FONTS.Display,
		TextSize = 19,
		TextColor3 = GOLD,
	})
	local list = UiKit.create("ScrollingFrame", {
		Name = "Shop",
		Position = UDim2.fromOffset(22, 332),
		Size = UDim2.new(1, -44, 1, -372),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = THEME.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, panel)
	UiKit.create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	UiKit.create("UIPadding", { PaddingRight = UDim.new(0, 10) }, list)
	local feedback = UiKit.text(panel, "Feedback", {
		Position = UDim2.new(0, 22, 1, -34),
		Size = UDim2.new(1, -44, 0, 24),
		Font = FONTS.Body,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- Cinemática (pantalla completa, por encima de todo) ---------------------------------------
	local overlay = UiKit.create("ScreenGui", {
		Name = "RebirthCinematic",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Enabled = false,
	}, playerGui)
	local flash = UiKit.create("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, overlay)
	local titleHolder = UiKit.create("Frame", {
		Name = "TitleHolder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(760, 150),
		BackgroundTransparency = 1,
	}, overlay)
	local titleScale = UiKit.create("UIScale", { Scale = 1 }, titleHolder)
	local bigTitle = UiKit.text(titleHolder, "Title", {
		Size = UDim2.new(1, 0, 0, 82),
		Font = FONTS.Display,
		TextScaled = true,
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
	})
	local titleStroke = UiKit.stroke(bigTitle, Color3.fromRGB(70, 44, 8), 3, 1)
	titleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	local bigSubtitle = UiKit.text(titleHolder, "Subtitle", {
		Position = UDim2.fromOffset(0, 90),
		Size = UDim2.new(1, 0, 0, 40),
		Font = FONTS.Display,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 248, 228),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	screenGui.Parent = playerGui
	return {
		ScreenGui = screenGui,
		Panel = panel,
		PanelScale = panelScale,
		Subtitle = subtitle,
		Close = close,
		Bonus = bonus,
		Requirement = requirement,
		Fill = fill,
		TrackText = trackText,
		Gain = gain,
		Resets = resets,
		RebirthButton = rebirthButton,
		RebirthShimmer = rebirthShimmer,
		ShopTitle = shopTitle,
		List = list,
		Feedback = feedback,
		Overlay = overlay,
		Flash = flash,
		TitleScale = titleScale,
		BigTitle = bigTitle,
		TitleStroke = titleStroke,
		BigSubtitle = bigSubtitle,
	}
end

-- Controlador ----------------------------------------------------------------------------------

function RebirthController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local rebirthRemote = remotes:WaitForChild(Constants.Remotes.Rebirth) :: RemoteEvent
	local shopRemote = remotes:WaitForChild(Constants.Remotes.RebirthShop) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.RebirthResult) :: RemoteEvent
	local eventRemote = remotes:WaitForChild(Constants.Remotes.RebirthEvent) :: RemoteEvent

	local ui = buildGui()
	local confirmUntil = 0
	local pending = false
	local feedbackToken = 0
	local shopRows: { [string]: any } = {}

	local menuEntry = MenuBar.add({
		Id = "Rebirth",
		Order = 5,
		Icon = "🔄",
		Label = "Renacer",
		Key = "T",
		Color = GOLD,
		Panels = { PANEL_NAME },
		OnActivate = function()
			PanelManager.toggle(PANEL_NAME)
		end,
	})
	local function placeTitle()
		local size = ui.ScreenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		ui.TitleScale.Scale = math.clamp(size.X / 1280, 0.55, 1.3)
	end
	ui.ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTitle)
	placeTitle()

	local function setFeedback(text: string, color: Color3)
		feedbackToken += 1
		local token = feedbackToken
		ui.Feedback.Text = text
		ui.Feedback.TextColor3 = color
		task.delay(4, function()
			if feedbackToken == token then
				ui.Feedback.Text = ""
			end
		end)
	end

	-- Tienda: una fila por ventaja (se crean una vez; render solo cambia textos).
	local function buildShop()
		for order, entry in RebirthLogic.shopOrder() do
			local item = entry.Item
			local row = UiKit.create("Frame", {
				Name = entry.Id,
				Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
				BackgroundColor3 = THEME.Inset,
				BackgroundTransparency = 0.3,
				LayoutOrder = order,
			}, ui.List)
			UiKit.corner(row, 10)
			local stroke = UiKit.stroke(row, THEME.Stroke, 1, 0.7)
			UiKit.text(row, "Icon", {
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.fromOffset(40, ROW_HEIGHT),
				Font = FONTS.Display,
				TextSize = 26,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = item.Icon,
			})
			local name = UiKit.text(row, "Name", {
				Position = UDim2.fromOffset(56, 8),
				Size = UDim2.new(1, -190, 0, 22),
				Font = FONTS.Display,
				TextSize = 17,
				Text = item.DisplayName,
			})
			local detail = UiKit.text(row, "Detail", {
				Position = UDim2.fromOffset(56, 32),
				Size = UDim2.new(1, -190, 0, 24),
				Font = FONTS.Light,
				TextSize = 13,
				TextColor3 = THEME.Muted,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
			})
			local button = UiKit.button(row, "Buy", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(118, 38),
				TextSize = 16,
			})
			local shimmer = UiKit.shimmer(button, 10)
			button.Activated:Connect(function()
				if button:GetAttribute("Disabled") == true then
					local data = currentData()
					local cost = RebirthLogic.shopCost(entry.Id, RebirthLogic.shopLevel(data, entry.Id))
					if cost and data.Tokens < cost then
						setFeedback(("Te faltan fichas: necesitas 🪙 %d (renace para conseguir más)."):format(cost), THEME.Error)
					end
					return
				end
				shopRemote:FireServer(entry.Id)
			end)
			shopRows[entry.Id] = { Name = name, Detail = detail, Button = button, Shimmer = shimmer, Stroke = stroke, Item = item }
		end
	end
	buildShop()

	local function effectText(itemId: string, level: number): string
		local item = RebirthConfig.Shop[itemId]
		local value = item.PerLevel * level
		if itemId == "PetSlot" then
			return ("+%d"):format(value)
		elseif itemId == "Loot" or itemId == "Strike" then
			return ("+%d %%"):format(math.floor(value * 100 + 0.5))
		elseif itemId == "HeadStart" then
			return ("nivel %d"):format(value)
		elseif itemId == "Dreams" then
			return ("+%d h"):format(math.floor(value / 3600 + 0.5))
		end
		return tostring(value)
	end

	local function renderShop(data: any)
		ui.ShopTitle.Text = ("🪙 Tienda de fichas  ·  tienes %d"):format(data.Tokens)
		for itemId, row in shopRows do
			local level = RebirthLogic.shopLevel(data, itemId)
			local maxLevel = #row.Item.Costs
			local cost = RebirthLogic.shopCost(itemId, level)
			local current = if level > 0 then effectText(itemId, level) else "—"
			local nextText = if cost then " → " .. effectText(itemId, level + 1) else " (máximo)"
			row.Name.Text = ("%s  ·  %d/%d"):format(row.Item.DisplayName, level, maxLevel)
			row.Detail.Text = ("%s  ·  ahora %s%s"):format(row.Item.Description, current, nextText)
			local affordable = cost ~= nil and data.Tokens >= cost and dataReady()
			if cost then
				row.Button.Text = ("🪙 %d"):format(cost)
				row.Button.BackgroundColor3 = if affordable then THEME.Buy else THEME.Disabled
			else
				row.Button.Text = "MÁX"
				row.Button.BackgroundColor3 = THEME.Max
			end
			row.Button.TextColor3 = if affordable or not cost then THEME.Text else THEME.Muted
			UiKit.setDisabled(row.Button, not affordable)
			row.Shimmer(affordable)
			row.Stroke.Color = if level >= maxLevel then THEME.Gold else THEME.Stroke
		end
	end

	-- Panel y botón según el estado actual.
	local function render()
		local data = currentData()
		local count = data.Count
		local level = attributeNumber(LEVEL_ATTRIBUTE)
		local required = RebirthLogic.requiredLevel(count)
		local ready = RebirthLogic.canRebirth(data, level) and dataReady()
		local progress = math.clamp(level / math.max(1, required), 0, 1)

		-- Azulejo del menú
		menuEntry.setProgress(progress)
		menuEntry.setLabel(if ready then "¡Renacer!" else "Renacer", if ready then GOLD else nil)

		if not PanelManager.isOpen(PANEL_NAME) then
			return
		end
		local strike = RebirthLogic.shopLevel(data, "Strike")
		ui.Subtitle.Text = if count > 0
			then ("Renacimientos: %d (%s)  ·  🪙 %s"):format(count, RebirthLogic.numeral(count), tokensText(data.Tokens))
			else ("Aún no has renacido  ·  🪙 %s"):format(tokensText(data.Tokens))
		ui.Bonus.Text = ("Tu bonificación:  ✦ %s poder   ⚔ %s daño"):format(
			multiplierText(RebirthLogic.energyMultiplierAt(count)),
			multiplierText(RebirthLogic.damageMultiplierAt(count, strike))
		)
		ui.Requirement.Text = ("Para renacer: %s nivel %d"):format(UPGRADE_NAME, required)
		ui.Fill.Size = UDim2.fromScale(progress, 1)
		ui.TrackText.Text = if ready then "¡Listo para renacer!" else ("Nivel %d / %d"):format(level, required)
		ui.Gain.Text = ("Al renacer:  ✦ %s poder  ·  ⚔ %s daño  ·  🪙 +%s"):format(
			multiplierText(RebirthLogic.energyMultiplierAt(count + 1)),
			multiplierText(RebirthLogic.damageMultiplierAt(count + 1, strike)),
			tokensText(RebirthLogic.tokensFor(count))
		)
		local startLevel = RebirthLogic.headStartLevel(data, RebirthLogic.requiredLevel(count + 1))
		ui.Resets.Text = ("Se reinician tu 💰, el nivel de tus armas y la %s (vuelve al nivel %d). Te quedas tus 💎, habilidades, armas, mascotas, zonas, jefes derrotados, mejoras de la Armería, núcleos, misiones y los huevos ya desbloqueados."):format(UPGRADE_NAME, startLevel)

		local confirming = ready and os.clock() < confirmUntil
		if pending then
			ui.RebirthButton.Text = "Renaciendo..."
		elseif confirming then
			ui.RebirthButton.Text = "⚠ Pulsa otra vez para renacer"
		elseif ready then
			ui.RebirthButton.Text = "🔄 Renacer ahora"
		else
			ui.RebirthButton.Text = ("🔒 Te faltan %d niveles de Resonancia"):format(math.max(0, required - level))
		end
		ui.RebirthButton.BackgroundColor3 = if confirming then Color3.fromRGB(176, 110, 30) elseif ready then Color3.fromRGB(150, 112, 34) else THEME.Disabled
		ui.RebirthButton.TextColor3 = if ready then THEME.Text else THEME.Muted
		UiKit.setDisabled(ui.RebirthButton, not ready or pending)
		ui.RebirthShimmer(ready and not pending)
		renderShop(data)
	end

	-- El azulejo del menú late en dorado cuando se puede renacer.
	local function updateButtonGlow()
		local data = currentData()
		local ready = RebirthLogic.canRebirth(data, attributeNumber(LEVEL_ATTRIBUTE)) and dataReady()
		menuEntry.setAttention(ready, GOLD)
	end

	-- Navegación ---------------------------------------------------------------------------------
	PanelManager.register(PANEL_NAME, ui.Panel, {
		OnOpen = function()
			confirmUntil = 0
			render()
			updateButtonGlow()
		end,
		OnClose = function()
			confirmUntil = 0
			updateButtonGlow()
		end,
	})
	UiKit.bindModalLayout(ui.ScreenGui, ui.PanelScale, PANEL_SIZE, function(position)
		PanelManager.setBasePosition(PANEL_NAME, position)
	end)
	ui.Close.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.T then
			PanelManager.toggle(PANEL_NAME)
		end
	end)
	RebirthController.open = function()
		PanelManager.open(PANEL_NAME)
	end

	ui.RebirthButton.Activated:Connect(function()
		if pending then
			return
		end
		if ui.RebirthButton:GetAttribute("Disabled") == true then
			if not dataReady() then
				setFeedback(MESSAGES[Codes.NotReady], THEME.Error)
			else
				local data = currentData()
				local missing = RebirthLogic.requiredLevel(data.Count) - attributeNumber(LEVEL_ATTRIBUTE)
				setFeedback(("Sube la %s %d niveles más (mejórala en la tarjeta de abajo)."):format(UPGRADE_NAME, math.max(1, missing)), THEME.Error)
			end
			return
		end
		if os.clock() >= confirmUntil then
			-- Primera pulsación: pedir confirmación.
			confirmUntil = os.clock() + CONFIRM_SECONDS
			render()
			task.delay(CONFIRM_SECONDS + 0.05, function()
				if PanelManager.isOpen(PANEL_NAME) then
					render()
				end
			end)
			return
		end
		confirmUntil = 0
		pending = true
		render()
		rebirthRemote:FireServer()
		task.delay(5, function()
			if pending then
				pending = false
				render()
			end
		end)
	end)

	-- Cinemática del renacimiento propio.
	local function playCinematic(count: number, tokens: number)
		local color = haloColor(count)
		ui.Overlay.Enabled = true
		ui.Flash.BackgroundColor3 = Color3.new(1, 1, 1)
		ui.Flash.BackgroundTransparency = 0.05
		TweenService:Create(ui.Flash, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1, BackgroundColor3 = color }):Play()
		ui.BigTitle.Text = "✨ RENACIMIENTO " .. RebirthLogic.numeral(count) .. " ✨"
		ui.BigTitle.TextColor3 = color
		ui.BigSubtitle.Text = ("✦ %s poder para siempre  ·  🪙 +%s"):format(multiplierText(RebirthLogic.energyMultiplierAt(count)), tokensText(tokens))
		ui.BigTitle.TextTransparency = 0
		ui.TitleStroke.Transparency = 0
		ui.BigSubtitle.TextTransparency = 0
		ui.BigSubtitle.TextStrokeTransparency = 0.3
		local baseScale = ui.TitleScale.Scale
		ui.TitleScale.Scale = baseScale * 0.4
		TweenService:Create(ui.TitleScale, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = baseScale }):Play()
		crystalBurst(color)
		playSound(RebirthConfig.Sounds.Rebirth, 0.9)
		playSound(RebirthConfig.Sounds.Burst, 0.45, 0.8)
		if AbilityController.shake then
			AbilityController.shake(0.8)
		end
		if AbilityController.kickFov then
			AbilityController.kickFov(9)
		end
		task.delay(3.2, function()
			local fade = TweenInfo.new(0.6)
			TweenService:Create(ui.BigTitle, fade, { TextTransparency = 1 }):Play()
			TweenService:Create(ui.TitleStroke, fade, { Transparency = 1 }):Play()
			TweenService:Create(ui.BigSubtitle, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(0.7)
			ui.Overlay.Enabled = false
		end)
	end

	resultRemote.OnClientEvent:Connect(function(success: boolean, code: string, action: string, detail: any)
		if action == "Rebirth" then
			pending = false
			if success and typeof(detail) == "table" then
				PanelManager.close(PANEL_NAME)
				playCinematic(tonumber(detail.Count) or attributeNumber(Attributes.Rebirths), tonumber(detail.Tokens) or 0)
			else
				local message = MESSAGES[code] or tostring(code)
				if code == Codes.LevelTooLow and typeof(detail) == "table" and detail.Required then
					message = ("Necesitas %s nivel %d para renacer."):format(UPGRADE_NAME, detail.Required)
				end
				setFeedback(message, THEME.Error)
			end
			render()
		elseif action == "Shop" then
			if success and typeof(detail) == "table" then
				local item = RebirthConfig.Shop[detail.ItemId]
				setFeedback(("%s %s mejorado al nivel %d."):format(item and item.Icon or "", item and item.DisplayName or "", tonumber(detail.Level) or 0), THEME.BuyHighlight)
				playSound(RebirthConfig.Sounds.Shop, 0.5, 1.2)
			else
				local message = MESSAGES[code] or tostring(code)
				if code == Codes.InsufficientTokens and typeof(detail) == "table" and detail.Cost then
					message = ("Te faltan fichas: necesitas 🪙 %d."):format(detail.Cost)
				end
				setFeedback(message, THEME.Error)
			end
			render()
		end
	end)

	-- Aviso cuando renace otro jugador.
	eventRemote.OnClientEvent:Connect(function(userId: number, displayName: string, count: number)
		if userId == player.UserId or typeof(displayName) ~= "string" or typeof(count) ~= "number" then
			return
		end
		Toasts.show(("✨ %s ha renacido  ·  🔄 %s"):format(displayName, RebirthLogic.numeral(count)), { Color = GOLD, Duration = 4 })
	end)

	-- Cambios de estado -----------------------------------------------------------------------
	local function onStateChanged()
		render()
		updateButtonGlow()
		rebuildHalo(attributeNumber(Attributes.Rebirths))
	end
	for _, name in { Attributes.Rebirths, Attributes.RebirthTokens, Attributes.RebirthShop, LEVEL_ATTRIBUTE, Attributes.DataStatus } do
		player:GetAttributeChangedSignal(name):Connect(onStateChanged)
	end
	onStateChanged()
	RunService.Heartbeat:Connect(updateHalo)

	-- Aviso "Renacer" en el cristal (sobre la plataforma del santuario) ---------------------------
	task.spawn(function()
		while true do
			local model = Workspace:FindFirstChild(GeneratorConfig.ModelName)
			local dais = model and model:FindFirstChild("Dais")
			if dais and dais:IsA("BasePart") and not dais:FindFirstChild("RebirthPrompt") then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "RebirthPrompt"
				prompt.ActionText = "Renacer"
				prompt.ObjectText = GeneratorConfig.DisplayName
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 12
				prompt.RequiresLineOfSight = false
				prompt.Parent = dais
			end
			task.wait(if dais then 10 else 1)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "RebirthPrompt" then
			PanelManager.open(PANEL_NAME)
		end
	end)
end

return RebirthController
