-- PetController · Gui: constantes, textos de aviso y construcción de los paneles de inventario, evolución y huevo.
-- Parte de PetController (ver PetController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PetConfig = require(Shared.Config.PetConfig)
local PetMath = require(Shared.PetMath)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)


local THEME = Theme.Colors
local FONTS = Theme.Fonts
local Codes = Constants.PurchaseCodes

local SEQUENCE_SECONDS = 2.4 -- duración mínima de la incubación antes del destello
local RESEND_AFTER = 6 -- sin respuesta: reenviar UNA vez con el mismo requestId
local GIVE_UP_AFTER = 12 -- sin respuesta tras el reenvío: dejar de esperar
local EGG_SIZE = Vector2.new(130, 165)
local INVENTORY_SIZE = Vector2.new(600, 440)
local EGG_PANEL_SIZE = Vector2.new(440, 470)
local EGG_PANEL_CLOSE_DISTANCE = 20

local MESSAGES = {
	[Codes.InsufficientDiamonds] = "Diamantes insuficientes",
	[Codes.InsufficientMoney] = "Dinero insuficiente",
	[Codes.InventoryFull] = "Inventario lleno",
	[Codes.TooFar] = "Acércate al santuario del huevo",
	[Codes.TooFast] = "Espera un momento",
	[Codes.NotReady] = "Cargando tus mascotas, inténtalo de nuevo",
	[Codes.NotOwned] = "No tienes esa mascota",
	[Codes.EquipLimit] = "Ya tienes el máximo de mascotas equipadas",
	[Codes.Unavailable] = "Los huevos no están disponibles ahora",
	[Codes.InvalidRequest] = "Solicitud no válida",
	[Codes.ZoneLocked] = "Desbloquea primero su zona en el portal",
}



local player = Players.LocalPlayer

local function messageFor(code: string): string
	return MESSAGES[code] or tostring(code)
end

-- Bonificación legible: 1.25 -> "+25 %".
local function bonusText(multiplier: number): string
	return "+" .. formatNumber((multiplier - 1) * 100, 1) .. " %"
end

local function rarityOf(petId: string)
	return PetMath.getRarity(petId) or PetConfig.Rarities.Common
end

-- Construcción ----------------------------------------------------------------

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("PetsHud")
	if existing then
		existing:Destroy()
	end

	local screenGui = UiKit.create("ScreenGui", {
		Name = "PetsHud",
		ResetOnSpawn = false,
		DisplayOrder = 5, -- los paneles quedan por encima del HUD de energía
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	-- Inventario ---------------------------------------------------------------
	local inventory, inventoryScale = UiKit.panel(screenGui, "Inventory", INVENTORY_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	UiKit.text(inventory, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		Text = "Mascotas",
	})
	local inventorySubtitle = UiKit.text(inventory, "Subtitle", {
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(1, -90, 0, 20),
		Font = FONTS.Light,
		TextSize = 16,
		TextColor3 = THEME.Muted,
	})
	local inventoryClose = UiKit.button(inventory, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})
	-- Huecos de equipamiento: qué hay equipado y cuánta capacidad queda.
	local slotsRow = UiKit.create("Frame", {
		Name = "EquippedSlots",
		Position = UDim2.fromOffset(22, 78),
		Size = UDim2.new(1, -44, 0, 44),
		BackgroundTransparency = 1,
	}, inventory)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, slotsRow)
	local list = UiKit.create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(22, 134),
		Size = UDim2.new(1, -44, 1, -180),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = THEME.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, inventory)
	UiKit.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(128, 132),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)
	local emptyLabel = UiKit.text(inventory, "Empty", {
		Position = UDim2.fromOffset(22, 150),
		Size = UDim2.new(1, -44, 0, 60),
		Font = FONTS.Light,
		TextSize = 17,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Text = "Aún no tienes mascotas. Visita el santuario del Huevo del Bosque junto al camino.",
	})
	local inventoryFeedback = UiKit.text(inventory, "Feedback", {
		Position = UDim2.new(0, 22, 1, -36),
		Size = UDim2.new(1, -44, 0, 24),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- Panel del huevo ------------------------------------------------------------
	local eggPanel, eggScale = UiKit.panel(screenGui, "EggPanel", EGG_PANEL_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	local eggTitle = UiKit.text(eggPanel, "Title", {
		Position = UDim2.fromOffset(22, 16),
		Size = UDim2.new(1, -90, 0, 34),
		Font = FONTS.Display,
		TextSize = 28,
	})
	local eggCost = UiKit.text(eggPanel, "Cost", {
		Position = UDim2.fromOffset(22, 52),
		Size = UDim2.new(1, -44, 0, 22),
		TextSize = 18,
		TextColor3 = THEME.Gold,
	})
	local eggClose = UiKit.button(eggPanel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})
	UiKit.text(eggPanel, "OddsTitle", {
		Position = UDim2.fromOffset(22, 90),
		Size = UDim2.new(1, -44, 0, 20),
		Font = FONTS.Light,
		TextSize = 15,
		TextColor3 = THEME.Muted,
		Text = "PROBABILIDADES",
	})
	local odds = UiKit.create("Frame", {
		Name = "Odds",
		Position = UDim2.fromOffset(22, 116),
		Size = UDim2.new(1, -44, 0, 230),
		BackgroundTransparency = 1,
	}, eggPanel)
	UiKit.create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, odds)
	local incubateButton = UiKit.button(eggPanel, "Incubate", {
		Position = UDim2.new(0, 22, 1, -96),
		Size = UDim2.new(1, -44, 0, 56),
		TextSize = 23,
	})
	-- Pase «Abrir ×3»: segundo botón a la derecha (solo se ve con el pase).
	local tripleButton = UiKit.button(eggPanel, "Triple", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -22, 1, -96),
		Size = UDim2.new(0.5, -28, 0, 56),
		TextSize = 21,
		Visible = false,
	})
	local eggFeedback = UiKit.text(eggPanel, "Feedback", {
		Position = UDim2.new(0, 22, 1, -34),
		Size = UDim2.new(1, -44, 0, 22),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	-- Capa de apertura (cubre el panel del huevo) ----------------------------------
	local hatch = UiKit.create("Frame", {
		Name = "Hatch",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Panel,
		Visible = false,
		ZIndex = 5,
		ClipsDescendants = true,
	}, eggPanel)
	UiKit.corner(hatch, 16)
	-- Brillo creciente detrás del huevo; al revelar estalla con el color de la rareza.
	local glow = UiKit.create("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.33),
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = THEME.Gold,
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, hatch)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, glow)
	local eggShape = UiKit.create("Frame", {
		Name = "Egg",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.33),
		Size = UDim2.fromOffset(EGG_SIZE.X, EGG_SIZE.Y),
		BackgroundColor3 = Color3.fromRGB(240, 232, 200),
		ZIndex = 7,
	}, hatch)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, eggShape)
	local eggSpots = {}
	for index, spot in { Vector2.new(0.3, 0.35), Vector2.new(0.68, 0.55), Vector2.new(0.42, 0.75) } do
		local dot = UiKit.create("Frame", {
			Name = "Spot" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spot.X, spot.Y),
			Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = Color3.fromRGB(110, 180, 96),
			ZIndex = 8,
		}, eggShape)
		UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
		table.insert(eggSpots, dot)
	end
	-- Grietas que aparecen una a una durante la incubación
	local cracks = {}
	for index, crack in {
		{ X = 0.46, Y = 0.3, Rotation = 35, Length = 0.38 },
		{ X = 0.6, Y = 0.5, Rotation = -50, Length = 0.42 },
		{ X = 0.4, Y = 0.64, Rotation = 70, Length = 0.32 },
		{ X = 0.55, Y = 0.18, Rotation = -20, Length = 0.28 },
	} do
		table.insert(
			cracks,
			UiKit.create("Frame", {
				Name = "Crack" .. index,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(crack.X, crack.Y),
				Size = UDim2.new(crack.Length, 0, 0, 4),
				Rotation = crack.Rotation,
				BackgroundColor3 = Color3.fromRGB(70, 58, 46),
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 9,
			}, eggShape)
		)
	end
	-- Modelo 3D de la mascota en la revelación
	local viewport = UiKit.create("ViewportFrame", {
		Name = "PetView",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.33),
		Size = UDim2.fromOffset(220, 220),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(190, 196, 186),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1, -1),
		Visible = false,
		ZIndex = 8,
	}, hatch)
	local viewportCamera = Instance.new("Camera")
	viewportCamera.FieldOfView = 40
	viewportCamera.Parent = viewport
	viewport.CurrentCamera = viewportCamera
	local flash = UiKit.create("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 12,
	}, hatch)
	UiKit.corner(flash, 16)
	local hatchStatus = UiKit.text(hatch, "Status", {
		Position = UDim2.new(0, 20, 0.58, 0),
		Size = UDim2.new(1, -40, 0, 26),
		Font = FONTS.Display,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 10,
	})
	local revealName = UiKit.text(hatch, "PetName", {
		Position = UDim2.new(0, 20, 0.58, 28),
		Size = UDim2.new(1, -40, 0, 36),
		Font = FONTS.Display,
		TextSize = 32,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 10,
	})
	local revealDetails = UiKit.text(hatch, "Details", {
		Position = UDim2.new(0, 20, 0.58, 68),
		Size = UDim2.new(1, -40, 0, 22),
		Font = FONTS.Body,
		TextSize = 17,
		TextColor3 = THEME.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 10,
	})
	local revealEquip = UiKit.text(hatch, "EquipState", {
		Position = UDim2.new(0, 20, 0.58, 92),
		Size = UDim2.new(1, -40, 0, 20),
		Font = FONTS.Light,
		TextSize = 15,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 10,
	})
	local againButton = UiKit.button(hatch, "Again", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -6, 1, -18),
		Size = UDim2.fromOffset(180, 48),
		Text = "Abrir otro",
		Visible = false,
		ZIndex = 10,
	})
	local backButton = UiKit.button(hatch, "Back", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 6, 1, -18),
		Size = UDim2.fromOffset(180, 48),
		BackgroundColor3 = THEME.Inset,
		Text = "Volver al juego",
		Visible = false,
		ZIndex = 10,
	})

	-- Máquina de Evolución (3 iguales -> 1 ★ Evo) --------------------------------
	local evoPanel, evoScale = UiKit.panel(screenGui, "EvolutionPanel", INVENTORY_SIZE, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.2))
	UiKit.text(evoPanel, "Title", {
		Position = UDim2.fromOffset(22, 14),
		Size = UDim2.new(1, -90, 0, 32),
		Font = FONTS.Display,
		TextSize = 28,
		Text = "🌟 Máquina de Evolución",
	})
	UiKit.text(evoPanel, "Subtitle", {
		Position = UDim2.fromOffset(22, 48),
		Size = UDim2.new(1, -90, 0, 20),
		Font = FONTS.Light,
		TextSize = 16,
		TextColor3 = THEME.Muted,
		Text = "Combina 3 mascotas iguales para evolucionarlas a su versión ★ Evo (¡doble poder!).",
	})
	local evoClose = UiKit.button(evoPanel, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = THEME.Inset,
		Text = "×",
	})
	local evoList = UiKit.create("ScrollingFrame", {
		Name = "EvoList",
		Position = UDim2.fromOffset(22, 82),
		Size = UDim2.new(1, -44, 1, -128),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = THEME.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, evoPanel)
	UiKit.create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, evoList)
	local evoEmpty = UiKit.text(evoPanel, "Empty", {
		Position = UDim2.fromOffset(22, 150),
		Size = UDim2.new(1, -44, 0, 60),
		Font = FONTS.Light,
		TextSize = 17,
		TextColor3 = THEME.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Text = "Abre huevos para conseguir mascotas y fusionar 3 iguales aquí.",
	})
	local evoFeedback = UiKit.text(evoPanel, "Feedback", {
		Position = UDim2.new(0, 22, 1, -36),
		Size = UDim2.new(1, -44, 0, 24),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	screenGui.Parent = playerGui

	return {
		ScreenGui = screenGui,
		InventoryScale = inventoryScale,
		EggScale = eggScale,
		EvoScale = evoScale,
		SlotsRow = slotsRow,
		Inventory = inventory,
		InventorySubtitle = inventorySubtitle,
		InventoryClose = inventoryClose,
		List = list,
		EmptyLabel = emptyLabel,
		InventoryFeedback = inventoryFeedback,
		EvoPanel = evoPanel,
		EvoClose = evoClose,
		EvoList = evoList,
		EvoEmpty = evoEmpty,
		EvoFeedback = evoFeedback,
		EggPanel = eggPanel,
		EggTitle = eggTitle,
		EggCost = eggCost,
		EggClose = eggClose,
		Odds = odds,
		IncubateButton = incubateButton,
		TripleButton = tripleButton,
		EggFeedback = eggFeedback,
		Hatch = hatch,
		Glow = glow,
		EggShape = eggShape,
		EggSpots = eggSpots,
		Cracks = cracks,
		Viewport = viewport,
		ViewportCamera = viewportCamera,
		Flash = flash,
		HatchStatus = hatchStatus,
		RevealName = revealName,
		RevealDetails = revealDetails,
		RevealEquip = revealEquip,
		AgainButton = againButton,
		BackButton = backButton,
	}
end

-- Controlador -----------------------------------------------------------------

local Part = { Api = {} }

function Part.install(context: any)
	-- (esta parte no usa el estado compartido)
	context.Codes = Codes
	context.EGG_PANEL_CLOSE_DISTANCE = EGG_PANEL_CLOSE_DISTANCE
	context.EGG_PANEL_SIZE = EGG_PANEL_SIZE
	context.EGG_SIZE = EGG_SIZE
	context.FONTS = FONTS
	context.GIVE_UP_AFTER = GIVE_UP_AFTER
	context.INVENTORY_SIZE = INVENTORY_SIZE
	context.RESEND_AFTER = RESEND_AFTER
	context.SEQUENCE_SECONDS = SEQUENCE_SECONDS
	context.THEME = THEME
	context.bonusText = bonusText
	context.buildGui = buildGui
	context.messageFor = messageFor
	context.player = player
	context.rarityOf = rarityOf
end

function Part.link(context: any)
	-- (nada que enlazar)
end

return Part
