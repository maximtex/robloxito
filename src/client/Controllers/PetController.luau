-- Interfaz de mascotas:
-- - Botón "Mascotas" (o tecla P) que abre el inventario para equipar y desequipar.
-- - Panel del huevo al usar un santuario: precio, requisito, probabilidades reales y
--   apertura en tres tiempos (incubación con temblor, brillo y grietas; destello;
--   revelación con el modelo de la mascota, su rareza y su bonificación).
-- Solo envía solicitudes; el servidor decide el resultado y manda el inventario real.
-- Inventario y huevo son paneles modales del PanelManager: uno a la vez, se cierran con
-- su botón o con Escape, y el huevo no se puede cerrar a mitad de una apertura.
-- Cada compra lleva un requestId: si no llega respuesta se reenvía UNA vez con el mismo
-- id, y el servidor devuelve el mismo resultado sin cobrar ni sortear de nuevo.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PetConfig = require(Shared.Config.PetConfig)
local EggConfig = require(Shared.Config.EggConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local PetMath = require(Shared.PetMath)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local RevealGate = require(script.Parent.Parent.Pets.RevealGate)
local PetModelBuilder = require(script.Parent.Parent.Pets.PetModelBuilder)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)

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
	[Codes.InsufficientEnergy] = "Energía insuficiente",
	[Codes.InventoryFull] = "Inventario lleno",
	[Codes.TooFar] = "Acércate al santuario del huevo",
	[Codes.TooFast] = "Espera un momento",
	[Codes.NotReady] = "Cargando tus mascotas, inténtalo de nuevo",
	[Codes.NotOwned] = "No tienes esa mascota",
	[Codes.EquipLimit] = "Ya tienes el máximo de mascotas equipadas",
	[Codes.Unavailable] = "Los huevos no están disponibles ahora",
	[Codes.InvalidRequest] = "Solicitud no válida",
	[Codes.Locked] = "Necesitas más nivel de " .. EconomyConfig.Upgrades[EggConfig.UnlockUpgradeId].DisplayName,
	[Codes.ZoneLocked] = "Desbloquea primero su zona en el portal",
}

type Snapshot = {
	Ready: boolean,
	Saving: boolean?,
	Pets: { { Uid: string, PetId: string } },
	Equipped: { string },
	MaxEquipped: number,
	MaxInventory: number,
}

local PetController = {}

local player = Players.LocalPlayer
local snapshot: Snapshot = { Ready = false, Pets = {}, Equipped = {}, MaxEquipped = PetConfig.MaxEquipped, MaxInventory = PetConfig.MaxInventory }

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

	-- Botón lateral
	local openButtonFrame, openScale = UiKit.panel(screenGui, "PetsButton", Vector2.new(Theme.Layout.SideButtonWidth, 58), Vector2.new(0, 0.5), UDim2.new(0, 16, 0.5, 0))
	local openButton = UiKit.create("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONTS.Display,
		TextSize = 21,
		TextColor3 = THEME.Text,
		Text = "🐾 Mascotas",
	}, openButtonFrame)
	UiKit.addStates(openButton)

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
		Text = "✕",
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
		Text = "✕",
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

	screenGui.Parent = playerGui
	UiKit.bindScale(screenGui, { openScale })

	return {
		ScreenGui = screenGui,
		OpenButton = openButton,
		OpenButtonStroke = openButtonFrame:FindFirstChildOfClass("UIStroke"),
		InventoryScale = inventoryScale,
		EggScale = eggScale,
		SlotsRow = slotsRow,
		Inventory = inventory,
		InventorySubtitle = inventorySubtitle,
		InventoryClose = inventoryClose,
		List = list,
		EmptyLabel = emptyLabel,
		InventoryFeedback = inventoryFeedback,
		EggPanel = eggPanel,
		EggTitle = eggTitle,
		EggCost = eggCost,
		EggClose = eggClose,
		Odds = odds,
		IncubateButton = incubateButton,
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

function PetController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local purchaseEggRemote = remotes:WaitForChild(Constants.Remotes.PurchaseEgg) :: RemoteEvent
	local eggResultRemote = remotes:WaitForChild(Constants.Remotes.EggResult) :: RemoteEvent
	local equipRemote = remotes:WaitForChild(Constants.Remotes.EquipPet) :: RemoteEvent
	local actionResultRemote = remotes:WaitForChild(Constants.Remotes.PetActionResult) :: RemoteEvent
	local requestInventoryRemote = remotes:WaitForChild(Constants.Remotes.RequestPetInventory) :: RemoteEvent
	local inventoryRemote = remotes:WaitForChild(Constants.Remotes.PetInventory) :: RemoteEvent

	local ui = buildGui()
	local feedbackTokens: { [TextLabel]: number } = {}

	local function showFeedback(label: TextLabel, text: string, color: Color3)
		local token = (feedbackTokens[label] or 0) + 1
		feedbackTokens[label] = token
		label.Text = text
		label.TextColor3 = color
		task.delay(3, function()
			if feedbackTokens[label] == token then
				label.Text = ""
			end
		end)
	end

	-- Inventario -----------------------------------------------------------------
	local equipPending = false

	local function renderInventory()
		local equippedSet: { [string]: boolean } = {}
		local equippedIds = {}
		for _, uid in snapshot.Equipped do
			equippedSet[uid] = true
		end
		for _, entry in snapshot.Pets do
			if equippedSet[entry.Uid] then
				table.insert(equippedIds, entry.PetId)
			end
		end

		local multiplier = PetMath.getTotalMultiplier(equippedIds)
		-- Estado real de los datos (lo publica el servidor): nunca "cargando" para siempre.
		local dataStatus = player:GetAttribute(Constants.Attributes.DataStatus)
		local failed = dataStatus == "Failed"
		local status = if snapshot.Ready then "" elseif failed then "  ·  no se pudieron cargar" else "  ·  cargando…"
		local saving = if snapshot.Ready and snapshot.Saving == false then "  ·  sin guardado en esta sesión" else ""
		ui.InventorySubtitle.Text = ("Producción con mascotas: %s (×%s)  ·  %d/%d en total%s%s"):format(
			bonusText(multiplier),
			formatNumber(multiplier, 2),
			#snapshot.Pets,
			snapshot.MaxInventory,
			status,
			saving
		)

		-- Huecos de equipamiento
		local petIdByUid: { [string]: string } = {}
		for _, entry in snapshot.Pets do
			petIdByUid[entry.Uid] = entry.PetId
		end
		for _, child in ui.SlotsRow:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local slotWidth = (INVENTORY_SIZE.X - 44 - 8 * (snapshot.MaxEquipped - 1)) / snapshot.MaxEquipped
		for slotIndex = 1, snapshot.MaxEquipped do
			local uid = snapshot.Equipped[slotIndex]
			local petId = uid and petIdByUid[uid]
			local slot = UiKit.create("Frame", {
				Name = "Slot" .. slotIndex,
				Size = UDim2.fromOffset(slotWidth, 44),
				BackgroundColor3 = THEME.Inset,
				BackgroundTransparency = if petId then 0 else 0.5,
				LayoutOrder = slotIndex,
			}, ui.SlotsRow)
			UiKit.corner(slot, 10)
			if petId then
				local rarity = rarityOf(petId)
				UiKit.stroke(slot, rarity.Color, 1.5, 0.2)
				UiKit.text(slot, "Label", {
					Position = UDim2.fromOffset(10, 0),
					Size = UDim2.new(1, -20, 1, 0),
					Font = FONTS.Display,
					TextSize = 16,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextColor3 = rarity.Color,
					Text = PetConfig.Pets[petId].DisplayName .. "  " .. bonusText(PetMath.getPetMultiplier(petId)),
				})
			else
				UiKit.stroke(slot, THEME.Muted, 1, 0.7)
				UiKit.text(slot, "Label", {
					Size = UDim2.fromScale(1, 1),
					Font = FONTS.Light,
					TextSize = 14,
					TextColor3 = THEME.Muted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Text = "Hueco libre",
				})
			end
		end
		local slotsFull = #snapshot.Equipped >= snapshot.MaxEquipped
		ui.OpenButton.Text = if #snapshot.Pets > 0 then ("🐾 Mascotas (%d)"):format(#snapshot.Pets) else "🐾 Mascotas"

		for _, child in ui.List:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		ui.EmptyLabel.Visible = #snapshot.Pets == 0
		ui.EmptyLabel.Text = if failed
			then "No se pudieron cargar tus mascotas. Tus datos guardados están a salvo: vuelve a entrar más tarde."
			elseif not snapshot.Ready then "Cargando tus mascotas…"
			else "Aún no tienes mascotas. Visita el santuario del Huevo del Bosque junto al camino."

		-- Orden: equipadas primero, luego por rareza (de mayor a menor) y nombre.
		local sorted = table.clone(snapshot.Pets)
		table.sort(sorted, function(a, b)
			local aEquipped, bEquipped = equippedSet[a.Uid] == true, equippedSet[b.Uid] == true
			if aEquipped ~= bEquipped then
				return aEquipped
			end
			local aOrder, bOrder = rarityOf(a.PetId).Order, rarityOf(b.PetId).Order
			if aOrder ~= bOrder then
				return aOrder > bOrder
			end
			return a.Uid < b.Uid
		end)

		for order, entry in sorted do
			local pet = PetConfig.Pets[entry.PetId]
			if not pet then
				continue
			end
			local rarity = rarityOf(entry.PetId)
			local equipped = equippedSet[entry.Uid] == true

			local card = UiKit.create("Frame", {
				Name = "Pet_" .. entry.Uid,
				BackgroundColor3 = THEME.Inset,
				LayoutOrder = order,
			}, ui.List)
			UiKit.corner(card, 12)
			UiKit.stroke(card, if equipped then THEME.Gold else rarity.Color, if equipped then 2.5 else 1.2, if equipped then 0 else 0.35)
			local bar = UiKit.create("Frame", {
				Name = "RarityBar",
				Size = UDim2.new(1, 0, 0, 5),
				BackgroundColor3 = rarity.Color,
				BorderSizePixel = 0,
			}, card)
			UiKit.corner(bar, 3)

			UiKit.text(card, "Name", {
				Position = UDim2.fromOffset(10, 9),
				Size = UDim2.new(1, -20, 0, 36),
				Font = FONTS.Display,
				TextSize = 16,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				Text = pet.DisplayName,
			})
			UiKit.text(card, "Rarity", {
				Position = UDim2.fromOffset(10, 46),
				Size = UDim2.new(1, -20, 0, 16),
				TextSize = 13,
				TextColor3 = rarity.Color,
				Text = rarity.DisplayName,
			})
			UiKit.text(card, "Bonus", {
				Position = UDim2.fromOffset(10, 63),
				Size = UDim2.new(1, -20, 0, 16),
				Font = FONTS.Light,
				TextSize = 13,
				TextColor3 = THEME.Accent,
				Text = bonusText(PetMath.getPetMultiplier(entry.PetId)) .. " energía",
			})
			if equipped then
				UiKit.text(card, "Equipped", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -8, 0, 46),
					Size = UDim2.fromOffset(20, 16),
					TextSize = 14,
					TextColor3 = THEME.Gold,
					TextXAlignment = Enum.TextXAlignment.Right,
					Text = "✓",
				})
			end

			-- Equipar (verde) / Quitar (piedra). Equipar se ve deshabilitado si no hay hueco.
			local cannotEquip = not equipped and slotsFull
			local button = UiKit.button(card, "Toggle", {
				Position = UDim2.new(0, 8, 1, -38),
				Size = UDim2.new(1, -16, 0, 30),
				BackgroundColor3 = if equipped then THEME.Secondary elseif cannotEquip then THEME.Disabled else THEME.Buy,
				TextColor3 = if cannotEquip then THEME.Muted else THEME.Text,
				TextSize = 15,
				Text = if equipped then "Quitar" else "Equipar",
			})
			UiKit.setDisabled(button, cannotEquip)
			button.Activated:Connect(function()
				if equipPending or not snapshot.Ready then
					return
				end
				if cannotEquip then
					showFeedback(ui.InventoryFeedback, messageFor(Codes.EquipLimit), THEME.Error)
					return
				end
				equipPending = true
				equipRemote:FireServer(entry.Uid, not equipped)
				task.delay(2, function()
					equipPending = false
				end)
			end)
		end
	end

	PanelManager.register("Inventory", ui.Inventory, { OnOpen = renderInventory })
	UiKit.bindModalLayout(ui.ScreenGui, ui.InventoryScale, INVENTORY_SIZE, function(position)
		PanelManager.setBasePosition("Inventory", position)
	end)

	ui.OpenButton.Activated:Connect(function()
		PanelManager.toggle("Inventory")
	end)
	ui.InventoryClose.Activated:Connect(function()
		PanelManager.close("Inventory")
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.P then
			-- Si hay un huevo abriéndose, el PanelManager no deja cambiar de panel.
			PanelManager.toggle("Inventory")
		end
	end)
	-- Resaltar el botón lateral mientras el inventario está abierto.
	PanelManager.Changed:Connect(function(openPanel: string?)
		local stroke = ui.OpenButtonStroke
		if stroke then
			local active = openPanel == "Inventory"
			stroke.Color = if active then THEME.Gold else THEME.Stroke
			stroke.Thickness = if active then 2.5 else 1.5
			stroke.Transparency = if active then 0 else THEME.StrokeTransparency
		end
	end)

	-- Durante la incubación el inventario nuevo se guarda aparte y se muestra al revelar.
	local pendingSnapshot: Snapshot? = nil
	inventoryRemote.OnClientEvent:Connect(function(data)
		if typeof(data) ~= "table" then
			return
		end
		if RevealGate.isHeld() then
			pendingSnapshot = data
			return
		end
		snapshot = data
		renderInventory()
	end)
	RevealGate.Released:Connect(function()
		if pendingSnapshot then
			snapshot = pendingSnapshot
			pendingSnapshot = nil
			renderInventory()
		end
	end)

	actionResultRemote.OnClientEvent:Connect(function(success: boolean, code: string)
		equipPending = false
		if not success then
			showFeedback(ui.InventoryFeedback, messageFor(code), THEME.Error)
		end
	end)

	-- Huevo ----------------------------------------------------------------------
	local currentEggId: string? = nil
	local currentPromptPart: BasePart? = nil
	-- "idle" (viendo probabilidades), "incubating" (animación / esperando) o "revealed".
	local phase = "idle"
	local incubating = false -- true solo durante "incubating" (impide cerrar por distancia)
	local currentRequestId: string? = nil
	local pendingResult: { any }? = nil -- resultado ya recibido; se revela al acabar la secuencia
	local sequenceToken = 0
	local animationConnection: RBXScriptConnection? = nil
	local unlockUpgradeName = EconomyConfig.Upgrades[EggConfig.UnlockUpgradeId].DisplayName
	local levelAttribute = Constants.Attributes.UpgradeLevelPrefix .. EggConfig.UnlockUpgradeId

	local function zoneUnlocked(zoneId: string): boolean
		local value = player:GetAttribute(Constants.Attributes.UnlockedZones)
		return typeof(value) == "string" and table.find(string.split(value, ","), zoneId) ~= nil
	end

	-- Comprobación previa en el cliente (solo para la interfaz; el servidor la repite).
	-- Devuelve: bloqueado, asequible y si el bloqueo es por zona.
	local function eggState(egg): (boolean, boolean, boolean)
		local level = player:GetAttribute(levelAttribute)
		local energy = player:GetAttribute(Constants.Attributes.Energy)
		local zoneLocked = egg.RequiredZone ~= nil and not zoneUnlocked(egg.RequiredZone)
		local locked = zoneLocked or (if typeof(level) == "number" then level else 0) < (egg.RequiredLevel or 0)
		local affordable = typeof(energy) == "number" and energy >= egg.Cost
		return locked, affordable, zoneLocked
	end

	local function styleButton(button: TextButton, egg, label: string)
		local locked, affordable, zoneLocked = eggState(egg)
		if zoneLocked then
			local zone = ZoneConfig.Zones[egg.RequiredZone]
			button.Text = "🔒 Requiere " .. (if zone then zone.DisplayName else egg.RequiredZone)
		elseif locked then
			button.Text = ("🔒 %s nivel %d"):format(unlockUpgradeName, egg.RequiredLevel)
		else
			button.Text = label .. "  ·  ⚡ " .. formatNumber(egg.Cost)
		end
		local enabled = not locked and affordable
		button.BackgroundColor3 = if enabled then THEME.Buy else THEME.Disabled
		button.TextColor3 = if enabled then THEME.Text else THEME.Muted
		UiKit.setDisabled(button, not enabled)
	end

	local function refreshEggButton()
		local egg = currentEggId and EggConfig.Eggs[currentEggId]
		if not egg then
			return
		end
		styleButton(ui.IncubateButton, egg, "INCUBAR")
		if phase == "revealed" then
			styleButton(ui.AgainButton, egg, "Otro")
		end
	end

	local function renderOdds(egg)
		for _, child in ui.Odds:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		-- Solo lo que este huevo puede dar de verdad, con sus probabilidades reales.
		for order, entry in egg.Chances do
			local pet = PetConfig.Pets[entry.PetId]
			local rarity = rarityOf(entry.PetId)
			local row = UiKit.create("Frame", {
				Name = "Row" .. order,
				Size = UDim2.new(1, 0, 0, 48),
				BackgroundColor3 = THEME.Inset,
				LayoutOrder = order,
			}, ui.Odds)
			UiKit.corner(row, 10)
			UiKit.text(row, "Name", {
				Position = UDim2.fromOffset(12, 4),
				Size = UDim2.new(0.6, 0, 0, 22),
				Font = FONTS.Display,
				TextSize = 19,
				TextColor3 = rarity.Color,
				Text = if pet then pet.DisplayName else entry.PetId,
			})
			UiKit.text(row, "Detail", {
				Position = UDim2.fromOffset(12, 26),
				Size = UDim2.new(0.7, 0, 0, 18),
				Font = FONTS.Light,
				TextSize = 14,
				TextColor3 = THEME.Muted,
				Text = rarity.DisplayName .. "  ·  " .. bonusText(PetMath.getPetMultiplier(entry.PetId)) .. " de energía",
			})
			UiKit.text(row, "Chance", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(90, 28),
				Font = FONTS.Display,
				TextSize = 22,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = formatNumber(entry.Chance, 2) .. "%",
			})
		end
	end

	local function stopAnimation()
		if animationConnection then
			animationConnection:Disconnect()
			animationConnection = nil
		end
		ui.EggShape.Rotation = 0
		ui.EggShape.Size = UDim2.fromOffset(EGG_SIZE.X, EGG_SIZE.Y)
	end

	local function setCracks(count: number)
		for index, crack in ui.Cracks do
			crack.Visible = index <= count
		end
	end

	local function clearViewport()
		for _, child in ui.Viewport:GetChildren() do
			if child:IsA("Model") then
				child:Destroy()
			end
		end
	end

	local function resetHatch()
		sequenceToken += 1
		phase = "idle"
		incubating = false
		currentRequestId = nil
		pendingResult = nil
		stopAnimation()
		RevealGate.release()
		clearViewport()
		ui.Hatch.Visible = false
		ui.Viewport.Visible = false
		ui.AgainButton.Visible = false
		ui.BackButton.Visible = false
		ui.EggClose.Visible = true
		ui.HatchStatus.Text = ""
		ui.RevealName.Text = ""
		ui.RevealDetails.Text = ""
		ui.RevealEquip.Text = ""
		ui.EggShape.Visible = true
		ui.Flash.BackgroundTransparency = 1
		ui.Glow.BackgroundTransparency = 1
		ui.Glow.BackgroundColor3 = THEME.Gold
		ui.Glow.Size = UDim2.fromOffset(150, 150)
		setCracks(0)
	end

	-- Se ejecuta cuando el PanelManager cierra el panel del huevo.
	local function onEggPanelClosed()
		resetHatch()
		currentEggId = nil
		currentPromptPart = nil
	end

	local function closeEggPanel()
		PanelManager.close("Egg")
	end

	PanelManager.register("Egg", ui.EggPanel, {
		-- No se puede cerrar ni cambiar de panel a mitad de una apertura.
		CanClose = function()
			return not incubating
		end,
		OnClose = onEggPanelClosed,
	})
	UiKit.bindModalLayout(ui.ScreenGui, ui.EggScale, EGG_PANEL_SIZE, function(position)
		PanelManager.setBasePosition("Egg", position)
	end)

	local function openEggPanel(eggId: string, promptPart: BasePart?)
		local egg = EggConfig.Eggs[eggId]
		if not egg or egg.Enabled == false then
			return
		end
		if incubating then
			return -- no cambiar de huevo a mitad de una apertura
		end
		resetHatch()
		currentEggId = eggId
		currentPromptPart = promptPart
		ui.EggTitle.Text = egg.DisplayName
		ui.EggCost.Text = "⚡ "
			.. formatNumber(egg.Cost)
			.. " de energía por huevo"
			.. (if (egg.RequiredLevel or 0) > 0 then ("  ·  requiere %s nivel %d"):format(unlockUpgradeName, egg.RequiredLevel) else "")
		ui.EggShape.BackgroundColor3 = egg.Look.Shell
		for _, spot in ui.EggSpots do
			spot.BackgroundColor3 = egg.Look.Spots
		end
		renderOdds(egg)
		refreshEggButton()
		ui.EggFeedback.Text = ""
		PanelManager.open("Egg")
	end

	local function failIncubation(message: string)
		resetHatch()
		showFeedback(ui.EggFeedback, message, THEME.Error)
	end

	-- Modelo de la mascota girando suavemente en la revelación.
	local function showPetModel(petId: string)
		clearViewport()
		local model = PetModelBuilder.build(petId)
		if not model then
			return
		end
		model.Parent = ui.Viewport
		local size = model:GetExtentsSize()
		local distance = math.max(size.X, size.Y, size.Z) * 1.6 + 2.5
		local startedAt = os.clock()
		animationConnection = RunService.RenderStepped:Connect(function()
			local angle = math.sin((os.clock() - startedAt) * 0.8) * 0.7
			ui.ViewportCamera.CFrame = CFrame.lookAt(
				Vector3.new(math.sin(angle) * distance, size.Y * 0.25, -math.cos(angle) * distance),
				Vector3.new(0, size.Y * 0.1, 0)
			)
		end)
	end

	-- Fase final: destello y revelación. Solo se llama al acabar la incubación.
	local function reveal(result: { any })
		stopAnimation()
		phase = "revealed"
		incubating = false
		local petId = result[4] :: string
		local autoEquipped = result[6] == true
		local pet = PetConfig.Pets[petId]
		local rarity = rarityOf(petId)

		ui.Flash.BackgroundTransparency = 0
		TweenService:Create(ui.Flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		ui.EggShape.Visible = false
		setCracks(0)
		ui.Glow.BackgroundColor3 = rarity.Color
		ui.Glow.BackgroundTransparency = 0.2
		ui.Glow.Size = UDim2.fromOffset(160, 160)
		TweenService:Create(ui.Glow, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(300, 300),
			BackgroundTransparency = 0.75,
		}):Play()

		ui.Viewport.Visible = true
		showPetModel(petId)
		ui.HatchStatus.Text = "¡Ha nacido!"
		ui.HatchStatus.TextColor3 = THEME.Gold
		ui.RevealName.Text = if pet then pet.DisplayName else petId
		ui.RevealName.TextColor3 = rarity.Color
		ui.RevealDetails.Text = rarity.DisplayName .. "  ·  " .. bonusText(PetMath.getPetMultiplier(petId)) .. " de producción"
		ui.RevealEquip.Text = if autoEquipped then "✓ Equipada automáticamente" else "Guardada en tu inventario (ya tienes el máximo equipado)"
		ui.AgainButton.Visible = true
		ui.BackButton.Visible = true
		ui.EggClose.Visible = true
		refreshEggButton()

		-- A partir de aquí la mascota ya se puede ver en el mundo, el inventario y el HUD.
		RevealGate.release()
	end

	-- Fase de incubación: temblor creciente, brillo y grietas. Si al terminar aún no ha
	-- llegado el resultado, el huevo sigue temblando (sin revelar nada) hasta que llegue.
	local function runIncubation(token: number, eggId: string, requestId: string)
		local startedAt = os.clock()
		local resent = false
		ui.HatchStatus.Text = "Incubando…"
		ui.HatchStatus.TextColor3 = THEME.Text
		animationConnection = RunService.RenderStepped:Connect(function()
			if sequenceToken ~= token then
				return
			end
			local elapsedTime = os.clock() - startedAt
			local progress = math.clamp(elapsedTime / SEQUENCE_SECONDS, 0, 1)
			local amplitude = 3 + 11 * progress
			local speed = 18 + 22 * progress
			ui.EggShape.Rotation = math.sin(elapsedTime * speed) * amplitude
			local pulse = 1 + math.sin(elapsedTime * speed * 0.5) * 0.03 * progress
			ui.EggShape.Size = UDim2.fromOffset(EGG_SIZE.X * pulse, EGG_SIZE.Y * pulse)
			local glowSize = 150 + 110 * progress
			ui.Glow.Size = UDim2.fromOffset(glowSize, glowSize)
			ui.Glow.BackgroundTransparency = 1 - 0.7 * progress
			setCracks(if progress >= 0.9 then 4 elseif progress >= 0.7 then 3 elseif progress >= 0.5 then 2 elseif progress >= 0.3 then 1 else 0)

			if progress < 1 then
				return
			end
			if pendingResult then
				local result = pendingResult
				pendingResult = nil
				reveal(result)
			elseif elapsedTime > GIVE_UP_AFTER then
				failIncubation("Sin respuesta del servidor. Si la compra se completó, la mascota está en tu inventario.")
			elseif elapsedTime > RESEND_AFTER and not resent then
				resent = true
				ui.HatchStatus.Text = "Esperando al bosque…"
				-- Mismo requestId: el servidor no vuelve a cobrar ni a sortear.
				purchaseEggRemote:FireServer(eggId, requestId)
			end
		end)
	end

	local function startPurchase()
		if incubating or not currentEggId then
			return
		end
		local eggId = currentEggId :: string
		local egg = EggConfig.Eggs[eggId]
		local locked, affordable, zoneLocked = eggState(egg)
		if locked then
			showFeedback(ui.EggFeedback, messageFor(if zoneLocked then Codes.ZoneLocked else Codes.Locked), THEME.Error)
			return
		end
		if not affordable then
			showFeedback(ui.EggFeedback, messageFor(Codes.InsufficientEnergy), THEME.Error)
			return
		end

		resetHatch() -- limpia una revelación anterior ("Abrir otro")
		local token = sequenceToken
		phase = "incubating"
		incubating = true
		local requestId = HttpService:GenerateGUID(false)
		currentRequestId = requestId
		RevealGate.hold()
		ui.Hatch.Visible = true
		ui.EggClose.Visible = false -- no se cierra a mitad de la apertura
		runIncubation(token, eggId, requestId)
		purchaseEggRemote:FireServer(eggId, requestId)
	end

	ui.IncubateButton.Activated:Connect(startPurchase)
	ui.AgainButton.Activated:Connect(startPurchase)
	ui.BackButton.Activated:Connect(closeEggPanel)
	ui.EggClose.Activated:Connect(closeEggPanel)

	eggResultRemote.OnClientEvent:Connect(function(...)
		local result = table.pack(...)
		local success, code, requestId = result[1], result[2], result[7]
		-- Ignorar respuestas de otras solicitudes (p. ej. la del reenvío si ya llegó la original).
		if phase ~= "incubating" or requestId ~= currentRequestId or pendingResult then
			return
		end
		if success ~= true or typeof(result[4]) ~= "string" then
			failIncubation(messageFor(code))
			return
		end
		pendingResult = result -- se revela al terminar la incubación
	end)

	player:GetAttributeChangedSignal(Constants.Attributes.Energy):Connect(refreshEggButton)
	player:GetAttributeChangedSignal(levelAttribute):Connect(refreshEggButton)
	player:GetAttributeChangedSignal(Constants.Attributes.UnlockedZones):Connect(refreshEggButton)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local eggId = prompt:GetAttribute("EggId")
		if typeof(eggId) == "string" then
			local parent = prompt.Parent
			openEggPanel(eggId, if parent and parent:IsA("BasePart") then parent else nil)
		end
	end)

	-- Cerrar el panel del huevo al alejarse del santuario.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if PanelManager.isOpen("Egg") and currentPromptPart and not incubating then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and (root.Position - currentPromptPart.Position).Magnitude > EGG_PANEL_CLOSE_DISTANCE then
					closeEggPanel()
				end
			end
		end
	end)

	renderInventory()
	requestInventoryRemote:FireServer()
	-- Si la carga termina en error, el inventario lo explica en lugar de seguir "cargando".
	player:GetAttributeChangedSignal(Constants.Attributes.DataStatus):Connect(renderInventory)
end

return PetController
