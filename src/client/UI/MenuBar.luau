-- Barra inferior central del HUD (Dock de 7 botones estilo simulador) + Tarjeta de Misión Diaria:
-- Implementa fielmente el diseño de `HUD Rediseño (standalone).html`:
-- - Abajo en el centro: Dock horizontal con 7 botones squircle con iconos 3D, insignia de tecla
--   oscura abajo a la izquierda, globo rojo de notificación arriba a la derecha y etiqueta debajo.
--   El botón central "Renacer" (T) es más grande y destacado en dorado con barra de progreso.
-- - A la izquierda (bajo las monedas): Tarjeta estilo pergamino para la misión diaria activa
--   con icono de pergamino, título, contador verde (ej. 2/15) y barra de progreso.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local UiKit = require(script.Parent.UiKit)
local Icons = require(script.Parent.Icons)
local HudLayout = require(script.Parent.HudLayout)
local PanelManager = require(script.Parent.PanelManager)

local FONTS = Theme.Fonts
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(43, 29, 63) -- #2B1D3F
local CREAM = Color3.fromRGB(255, 246, 224) -- #FFF6E0
local BADGE_RED = Color3.fromRGB(236, 56, 64) -- #EC3840
local GREEN_TEXT = Color3.fromRGB(63, 174, 69) -- #3FAE45

local MenuBar = {}

export type Spec = {
	Id: string,
	Order: number,
	Icon: string,
	Image: string?,
	Label: string,
	Key: string?,
	Color: Color3?,
	Panels: { string }?,
	OnActivate: () -> (),
}

export type Entry = {
	Id: string,
	Tile: Frame,
	Button: TextButton,
	setBadge: (text: string?) -> (),
	setAttention: (active: boolean, color: Color3?) -> (),
	setProgress: (ratio: number?) -> (),
	setLabel: (text: string, color: Color3?) -> (),
	shimmer: (active: boolean) -> (),
}

type StyleSpec = {
	Order: number,
	Icon: string,
	Key: string,
	Top: Color3,
	Mid: Color3,
	Bot: Color3,
	LabelColor: Color3,
	Featured: boolean?,
}

local DOCK_STYLES: { [string]: StyleSpec } = {
	Armory = {
		Order = 0,
		Icon = "armory",
		Key = "L",
		Top = Color3.fromRGB(226, 236, 255),
		Mid = Color3.fromRGB(110, 150, 230),
		Bot = Color3.fromRGB(70, 104, 196),
		LabelColor = WHITE,
	},
	Pets = {
		Order = 1,
		Icon = "pets",
		Key = "P",
		Top = Color3.fromRGB(255, 224, 191),
		Mid = Color3.fromRGB(238, 152, 68),
		Bot = Color3.fromRGB(217, 122, 42),
		LabelColor = WHITE,
	},
	Quests = {
		Order = 2,
		Icon = "quests",
		Key = "M",
		Top = Color3.fromRGB(255, 241, 196),
		Mid = Color3.fromRGB(242, 193, 78),
		Bot = Color3.fromRGB(217, 157, 34),
		LabelColor = WHITE,
	},
	Cores = {
		Order = 3,
		Icon = "cores",
		Key = "N",
		Top = Color3.fromRGB(214, 250, 255),
		Mid = Color3.fromRGB(92, 214, 232),
		Bot = Color3.fromRGB(47, 175, 200),
		LabelColor = WHITE,
	},
	Rebirth = {
		Order = 4,
		Icon = "rebirth",
		Key = "T",
		Top = Color3.fromRGB(255, 244, 191),
		Mid = Color3.fromRGB(255, 201, 60),
		Bot = Color3.fromRGB(242, 154, 26),
		LabelColor = Color3.fromRGB(255, 244, 191),
		Featured = true,
	},
	Amulets = {
		Order = 5,
		Icon = "amulets",
		Key = "G",
		Top = Color3.fromRGB(237, 226, 255),
		Mid = Color3.fromRGB(164, 124, 240),
		Bot = Color3.fromRGB(126, 85, 214),
		LabelColor = WHITE,
	},
	Rewards = {
		Order = 6,
		Icon = "rewards",
		Key = "J",
		Top = Color3.fromRGB(255, 214, 216),
		Mid = Color3.fromRGB(240, 84, 92),
		Bot = Color3.fromRGB(208, 53, 64),
		LabelColor = WHITE,
	},
	Shop = {
		Order = 7,
		Icon = "shop",
		Key = "K",
		Top = Color3.fromRGB(216, 255, 200),
		Mid = Color3.fromRGB(88, 232, 44),
		Bot = Color3.fromRGB(54, 184, 26),
		LabelColor = Color3.fromRGB(216, 255, 200),
	},
}

local dockGui: ScreenGui? = nil
local dockRow: Frame? = nil
local dockScale: UIScale? = nil
local leftStack: Frame? = nil
local leftScale: UIScale? = nil
local dailyCard: Frame? = nil
local dailyTitle: TextLabel? = nil
local dailyProg: TextLabel? = nil
local dailyFill: Frame? = nil
local entries: { [string]: any } = {}
local statusLines: { [string]: TextLabel } = {}

local function addInkStroke(instance: Instance, thickness: number, mode: Enum.ApplyStrokeMode?): UIStroke
	return UiKit.create("UIStroke", {
		Color = INK,
		Thickness = thickness,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, instance)
end

local function build()
	if dockGui and dockGui.Parent then
		return
	end
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local oldTopHud = playerGui:FindFirstChild("SimpleTopHud")
	if oldTopHud then
		oldTopHud:Destroy()
	end
	local existing = playerGui:FindFirstChild("MenuDockHud")
	if existing then
		existing:Destroy()
	end

	local screenGui = UiKit.create("ScreenGui", {
		Name = "MenuDockHud",
		ResetOnSpawn = false,
		DisplayOrder = 4,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	dockGui = screenGui

	-- Contenedor del Dock inferior central (8 botones: 7 de 66 + Renacer de 84, con 8 de hueco)
	local dock = UiKit.create("Frame", {
		Name = "BottomDock",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(640, 114),
		BackgroundTransparency = 1,
	}, screenGui)
	dockScale = UiKit.create("UIScale", {}, dock)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, dock)
	dockRow = dock

	-- Contenedor izquierdo para la tarjeta de misión diaria (debajo de las monedas)
	local left = UiKit.create("Frame", {
		Name = "LeftStatusStack",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 20, 0.56, 0),
		Size = UDim2.fromOffset(244, 96),
		BackgroundTransparency = 1,
	}, screenGui)
	leftScale = UiKit.create("UIScale", {}, left)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, left)
	leftStack = left

	-- Tarjeta de Misión Diaria estilo pergamino (como en `HUD Rediseño (standalone).html`)
	local card = UiKit.create("Frame", {
		Name = "DailyMiniCard",
		Size = UDim2.fromOffset(238, 56),
		BackgroundColor3 = WHITE,
		LayoutOrder = 1,
		Visible = false,
	}, left)
	UiKit.corner(card, 16)
	UiKit.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 248, 230), Color3.fromRGB(244, 226, 184)),
	}, card)
	addInkStroke(card, 3.5, Enum.ApplyStrokeMode.Border)

	Icons.make(card, "quests", {
		Name = "QuestIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(38, 38),
		ZIndex = 2,
	})

	local dTitle = UiKit.text(card, "Title", {
		Position = UDim2.fromOffset(54, 8),
		Size = UDim2.new(1, -110, 0, 20),
		Font = FONTS.Display,
		TextSize = 15,
		TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "Patrulla del día",
		ZIndex = 2,
	})
	local dProg = UiKit.text(card, "Progress", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 9),
		Size = UDim2.fromOffset(54, 18),
		Font = FONTS.Display,
		TextSize = 14,
		TextColor3 = GREEN_TEXT,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "0/15",
		ZIndex = 2,
	})

	local dTrack = UiKit.create("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(54, 33),
		Size = UDim2.new(1, -66, 0, 11),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, card)
	UiKit.corner(dTrack, 6)

	local dFill = UiKit.create("Frame", {
		Name = "Fill",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(0.15, -4, 1, -4),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, dTrack)
	UiKit.corner(dFill, 4)
	UiKit.create("UIGradient", {
		Rotation = 0,
		Color = ColorSequence.new(Color3.fromRGB(182, 245, 166), Color3.fromRGB(96, 214, 96)),
	}, dFill)

	local cardBtn = UiKit.create("TextButton", {
		Name = "OpenQuests",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
	}, card)
	cardBtn.Activated:Connect(function()
		PanelManager.toggle("Quests")
	end)

	dailyCard = card
	dailyTitle = dTitle
	dailyProg = dProg
	dailyFill = dFill

	local function applyScale()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local baseScale = HudLayout.scale(size, isTouch)
		-- Ajustar escala del Dock para que nunca colisione con los botones de ataque a la derecha (~220px)
		-- ni con la tarjeta diaria a la izquierda (~240px)
		local maxDockWidth = size.X - 360
		local fitScale = math.clamp(maxDockWidth / 614, 0.6, 1)
		local s = math.min(baseScale, fitScale)
		if dockScale then
			dockScale.Scale = s
		end
		if leftScale then
			leftScale.Scale = baseScale
		end
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyScale)
	applyScale()

	PanelManager.Changed:Connect(function(openPanel: string?)
		for _, entry in entries do
			local active = false
			for _, panelName in entry.Panels do
				if panelName == openPanel then
					active = true
				end
			end
			entry.setOpen(active)
		end
	end)
end

function MenuBar.add(spec: Spec): Entry
	build()

	local existing = entries[spec.Id]
	if existing then
		return existing
	end

	local style: StyleSpec = DOCK_STYLES[spec.Id] or {
		Order = spec.Order,
		Icon = spec.Image or string.lower(spec.Id),
		Key = spec.Key or "",
		Top = WHITE,
		Mid = spec.Color or Color3.fromRGB(92, 214, 232),
		Bot = (spec.Color or Color3.fromRGB(92, 214, 232)):Lerp(Color3.new(0, 0, 0), 0.25),
		LabelColor = WHITE,
	}

	local isFeatured = style.Featured == true
	local tileSize = if isFeatured then 84 else 66
	local slotHeight = tileSize + 24
	local cornerRadius = if isFeatured then 22 else 17
	local iconSize = if isFeatured then 68 else 52

	local slot = UiKit.create("Frame", {
		Name = "Slot_" .. spec.Id,
		Size = UDim2.fromOffset(tileSize, slotHeight),
		BackgroundTransparency = 1,
		LayoutOrder = style.Order,
	}, dockRow)

	local tile = UiKit.create("Frame", {
		Name = "Tile_" .. spec.Id,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(tileSize, tileSize),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
	}, slot)
	UiKit.corner(tile, cornerRadius)
	UiKit.create("UIGradient", {
		Name = "Tint",
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, style.Top),
			ColorSequenceKeypoint.new(0.55, style.Mid),
			ColorSequenceKeypoint.new(1, style.Bot),
		}),
	}, tile)
	local stroke = addInkStroke(tile, if isFeatured then 4 else 3.5, Enum.ApplyStrokeMode.Border)

	-- Brillo superior redondeado estilo cartoon
	local gloss = UiKit.create("Frame", {
		Name = "Gloss",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 5),
		Size = UDim2.new(1, -18, 0, if isFeatured then 14 else 11),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, tile)
	UiKit.corner(gloss, 8)

	local icon = Icons.make(tile, style.Icon, {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.fromOffset(iconSize, iconSize),
		ZIndex = 4,
	})
	local emoji = icon:FindFirstChild("Emoji")
	if emoji and emoji:IsA("TextLabel") and not Icons.has(style.Icon) then
		emoji.Text = spec.Icon
	end

	-- Barra de progreso interna (usada por Renacer)
	local track = UiKit.create("Frame", {
		Name = "Progress",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -24, 0, 7),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		Visible = isFeatured,
		ZIndex = 5,
	}, tile)
	UiKit.corner(track, 4)
	local fill = UiKit.create("Frame", {
		Name = "Fill",
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(if isFeatured then 0.62 else 0, -2, 1, -2),
		BackgroundColor3 = Color3.fromRGB(156, 236, 140),
		BorderSizePixel = 0,
		ZIndex = 6,
	}, track)
	UiKit.corner(fill, 3)

	-- Insignia de tecla (abajo a la izquierda del azulejo)
	local keyStr = spec.Key or style.Key
	if keyStr and keyStr ~= "" then
		local keyBadge = UiKit.create("Frame", {
			Name = "KeyBadge",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, -5, 1, 5),
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = INK,
			ZIndex = 7,
		}, tile)
		UiKit.corner(keyBadge, 7)
		UiKit.create("UIStroke", {
			Color = WHITE,
			Thickness = 1.5,
			Transparency = 0.72,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, keyBadge)
		UiKit.text(keyBadge, "KeyText", {
			Size = UDim2.fromScale(1, 1),
			Font = FONTS.Display,
			TextSize = 13,
			TextColor3 = CREAM,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = keyStr,
			ZIndex = 8,
		})
	end

	-- Globo rojo de notificación (arriba a la derecha del azulejo)
	local badge = UiKit.create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 7, 0, -7),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = BADGE_RED,
		Visible = false,
		ZIndex = 8,
	}, tile)
	UiKit.corner(badge, 14)
	addInkStroke(badge, 3, Enum.ApplyStrokeMode.Border)
	local badgeText = UiKit.text(badge, "Count", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 15,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 9,
	})
	addInkStroke(badgeText, 1.8, Enum.ApplyStrokeMode.Contextual)

	-- Etiqueta debajo del botón
	local label = UiKit.text(slot, "Label", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, tileSize + 4),
		Size = UDim2.new(1, 16, 0, 20),
		Font = FONTS.Display,
		TextSize = if isFeatured then 16 else 14,
		TextColor3 = style.LabelColor,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = spec.Label,
		ZIndex = 6,
	})
	addInkStroke(label, 3, Enum.ApplyStrokeMode.Contextual)

	local button = UiKit.create("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 10,
	}, tile)

	-- Animación hover ligera estilo HTML (-5px hacia arriba)
	button.MouseEnter:Connect(function()
		TweenService:Create(tile, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0, -5),
		}):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(tile, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0, 0),
		}):Play()
	end)
	button.Activated:Connect(spec.OnActivate)

	local shimmer = UiKit.shimmer(tile, 4)

	local entry: any = {
		Id = spec.Id,
		Tile = tile,
		Button = button,
		Panels = spec.Panels or {},
	}
	function entry.setBadge(text: string?)
		local show = text ~= nil and text ~= ""
		badge.Visible = show
		badgeText.Text = text or ""
	end
	function entry.setAttention(active: boolean, color: Color3?)
		stroke.Color = if active then (color or Color3.fromRGB(255, 224, 102)) else INK
	end
	function entry.setOpen(active: boolean)
		stroke.Color = if active then Color3.fromRGB(255, 224, 102) else INK
	end
	function entry.setProgress(ratio: number?)
		track.Visible = ratio ~= nil
		local r = math.clamp(ratio or 0, 0, 1)
		fill.Size = UDim2.new(r, -2, 1, -2)
	end
	function entry.setLabel(text: string, color: Color3?)
		label.Text = text
		label.TextColor3 = color or style.LabelColor
	end
	entry.shimmer = shimmer
	entry.Icon = icon

	entries[spec.Id] = entry
	return entry
end

function MenuBar.tile(id: string): GuiObject?
	local entry = entries[id]
	return entry and entry.Tile
end

function MenuBar.status(id: string, order: number): TextLabel
	build()
	local existing = statusLines[id]
	if existing then
		return existing
	end

	if id == "Quests" then
		-- Proxy TextLabel que sincroniza automáticamente la tarjeta estilo pergamino `DailyMiniCard`
		local proxy = Instance.new("TextLabel")
		proxy.Name = "Status_Quests_Proxy"
		proxy.Visible = false
		proxy:GetPropertyChangedSignal("Text"):Connect(function()
			local raw = proxy.Text
			if not dailyCard or not dailyTitle or not dailyProg or not dailyFill then
				return
			end
			if raw == "" then
				dailyCard.Visible = false
				return
			end
			dailyCard.Visible = true
			-- Limpia el emoji inicial "📜 " si viene incluido
			local clean = string.gsub(raw, "^📜%s*", "")
			local titlePart, curStr, maxStr = string.match(clean, "^(.-)%s+([%d%.,kKmM]+)/([%d%.,kKmM]+)$")
			if titlePart and curStr and maxStr then
				dailyTitle.Text = titlePart
				dailyProg.Text = curStr .. "/" .. maxStr
				local curNum = tonumber((string.gsub(curStr, "[^%d%.]", ""))) or 0
				local maxNum = tonumber((string.gsub(maxStr, "[^%d%.]", ""))) or 1
				local ratio = math.clamp(curNum / math.max(maxNum, 1), 0.06, 1)
				dailyFill.Size = UDim2.new(ratio, -4, 1, -4)
			else
				dailyTitle.Text = clean
				dailyProg.Text = "¡Lista!"
				dailyFill.Size = UDim2.new(1, -4, 1, -4)
			end
		end)
		statusLines[id] = proxy
		return proxy
	end

	local line = UiKit.text(leftStack :: Frame, "Status_" .. id, {
		Size = UDim2.fromOffset(238, 22),
		Font = FONTS.Display,
		TextSize = 15,
		TextColor3 = WHITE,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = order + 2,
		Visible = false,
	})
	addInkStroke(line, 2.5, Enum.ApplyStrokeMode.Contextual)
	line:GetPropertyChangedSignal("Text"):Connect(function()
		line.Visible = line.Text ~= ""
	end)
	statusLines[id] = line
	return line
end

return MenuBar
