-- Interfaz de mascotas:
-- - Azulejo "Mascotas" en la barra del menú (o tecla P) que abre el inventario para equipar
--   y desequipar. Lleva un "!" si hay un hueco libre y mascotas sin equipar.
-- - Máquina de Evolución (3 iguales -> 1 ★ Evo).
-- - Jardín de mascotas: con E en un pedestal se compra su mascota (BuyPet); el resultado
--   llega como aviso. Los jefes también regalan mascotas (aviso "¡Nueva mascota!").
-- Solo envía solicitudes; el servidor decide el resultado y manda el inventario real.
-- Inventario y evolución son paneles modales del PanelManager: uno a la vez, se cierran
-- con su botón o con Escape.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PetConfig = require(Shared.Config.PetConfig)
local PetMath = require(Shared.PetMath)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.UI.MenuBar)
local Juice = require(script.Parent.Parent.UI.Juice)
local Toasts = require(script.Parent.Parent.UI.Toasts)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local Codes = Constants.PurchaseCodes

local INVENTORY_SIZE = Vector2.new(600, 440)

local MESSAGES = {
	[Codes.InsufficientMoney] = "Te falta 💰 dinero: derrota enemigos",
	[Codes.InventoryFull] = "Inventario lleno",
	[Codes.TooFar] = "Acércate al pedestal",
	[Codes.TooFast] = "Espera un momento",
	[Codes.NotReady] = "Cargando tus mascotas, inténtalo de nuevo",
	[Codes.NotOwned] = "No tienes esa mascota",
	[Codes.EquipLimit] = "Ya tienes el máximo de mascotas equipadas",
	[Codes.Unavailable] = "La tienda del jardín no está disponible ahora",
	[Codes.InvalidRequest] = "Solicitud no válida",
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
		Text = "Aún no tienes mascotas. Cómpralas en el Jardín de mascotas o derrota a un jefe.",
	})
	local inventoryFeedback = UiKit.text(inventory, "Feedback", {
		Position = UDim2.new(0, 22, 1, -36),
		Size = UDim2.new(1, -44, 0, 24),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
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
		Text = "Consigue 3 mascotas iguales (en el jardín o de los jefes) y fusiónalas aquí.",
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
	}
end

-- Controlador -----------------------------------------------------------------

function PetController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local buyPetRemote = remotes:WaitForChild(Constants.Remotes.BuyPet) :: RemoteEvent
	local shopResultRemote = remotes:WaitForChild(Constants.Remotes.PetShopResult) :: RemoteEvent
	local equipRemote = remotes:WaitForChild(Constants.Remotes.EquipPet) :: RemoteEvent
	local evolveRemote = remotes:WaitForChild(Constants.Remotes.EvolvePet) :: RemoteEvent
	local actionResultRemote = remotes:WaitForChild(Constants.Remotes.PetActionResult) :: RemoteEvent
	local requestInventoryRemote = remotes:WaitForChild(Constants.Remotes.RequestPetInventory) :: RemoteEvent
	local inventoryRemote = remotes:WaitForChild(Constants.Remotes.PetInventory) :: RemoteEvent

	local ui = buildGui()
	local menuEntry = MenuBar.add({
		Id = "Pets",
		Order = 1,
		Icon = "🐾",
		Label = "Mascotas",
		Key = "P",
		Color = Color3.fromRGB(120, 214, 130),
		Panels = { "Inventory" },
		OnActivate = function()
			PanelManager.toggle("Inventory")
		end,
	})
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
		-- Las equipadas suben la energía (entera), el daño y el dinero (la mitad de su bonificación)
		local half = 1 + (multiplier - 1) * 0.5
		ui.InventorySubtitle.Text = ("⚡ ×%s  ·  💥 y 💰 ×%s  ·  %d/%d en total%s%s"):format(
			formatNumber(multiplier, 2),
			formatNumber(half, 2),
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
		-- "!" en el menú: hay un hueco libre y alguna mascota sin equipar.
		menuEntry.setBadge(if snapshot.Ready and not slotsFull and #snapshot.Pets > #snapshot.Equipped then "!" else nil)

		for _, child in ui.List:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		ui.EmptyLabel.Visible = #snapshot.Pets == 0
		ui.EmptyLabel.Text = if failed
			then "No se pudieron cargar tus mascotas. Tus datos guardados están a salvo: vuelve a entrar más tarde."
			elseif not snapshot.Ready then "Cargando tus mascotas…"
			else "Aún no tienes mascotas. Cómpralas en el Jardín de mascotas o derrota a un jefe."

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

	ui.InventoryClose.Activated:Connect(function()
		PanelManager.close("Inventory")
	end)

	-- Máquina de Evolución -------------------------------------------------------
	local neededForEvo = PetConfig.EvolutionCopiesRequired or 3
	local function renderEvolution()
		for _, child in ui.EvoList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local counts: { [string]: number } = {}
		local speciesList = {}
		for _, entry in snapshot.Pets do
			local def = PetConfig.Pets[entry.PetId]
			if def and def.EvolvesInto and PetConfig.Pets[def.EvolvesInto] then
				if not counts[entry.PetId] then
					counts[entry.PetId] = 0
					table.insert(speciesList, entry.PetId)
				end
				counts[entry.PetId] += 1
			end
		end
		table.sort(speciesList, function(a, b)
			local aReady = (counts[a] or 0) >= neededForEvo
			local bReady = (counts[b] or 0) >= neededForEvo
			if aReady ~= bReady then
				return aReady
			end
			return PetMath.getPetMultiplier(a) > PetMath.getPetMultiplier(b)
		end)

		ui.EvoEmpty.Visible = #speciesList == 0

		for order, petId in speciesList do
			local baseDef = PetConfig.Pets[petId]
			local evoDef = PetConfig.Pets[baseDef.EvolvesInto]
			local count = counts[petId] or 0
			local canEvolve = count >= neededForEvo
			local rarity = rarityOf(petId)

			local row = UiKit.create("Frame", {
				Name = "Evo_" .. petId,
				Size = UDim2.new(1, -8, 0, 72),
				BackgroundColor3 = THEME.Inset,
				LayoutOrder = order,
			}, ui.EvoList)
			UiKit.corner(row, 12)
			UiKit.stroke(row, if canEvolve then THEME.Gold else rarity.Color, if canEvolve then 2 else 1.2, 0.2)

			UiKit.text(row, "Title", {
				Position = UDim2.fromOffset(14, 10),
				Size = UDim2.new(1, -210, 0, 26),
				Font = FONTS.Display,
				TextSize = 19,
				TextColor3 = rarity.Color,
				Text = ("%s  →  %s"):format(baseDef.DisplayName, evoDef.DisplayName),
			})
			UiKit.text(row, "Detail", {
				Position = UDim2.fromOffset(14, 38),
				Size = UDim2.new(1, -210, 0, 22),
				Font = FONTS.Light,
				TextSize = 15,
				TextColor3 = if canEvolve then THEME.BuyHighlight else THEME.Muted,
				Text = ("Tienes: %d/%d   ·   Poder: %s → %s"):format(
					count,
					neededForEvo,
					bonusText(PetMath.getPetMultiplier(petId)),
					bonusText(PetMath.getPetMultiplier(baseDef.EvolvesInto))
				),
			})

			local evoBtn = UiKit.button(row, "EvolveButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(176, 46),
				BackgroundColor3 = if canEvolve then THEME.Buy else THEME.Disabled,
				TextColor3 = if canEvolve then THEME.Text else THEME.Muted,
				TextSize = 16,
				Text = if canEvolve then "🌟 Evolucionar (3→1)" else ("Faltan %d"):format(neededForEvo - count),
			})
			UiKit.setDisabled(evoBtn, not canEvolve)
			evoBtn.Activated:Connect(function()
				if equipPending or not snapshot.Ready then
					return
				end
				if not canEvolve then
					showFeedback(ui.EvoFeedback, ("Necesitas %d %s para evolucionar"):format(neededForEvo, baseDef.DisplayName), THEME.Error)
					return
				end
				equipPending = true
				evolveRemote:FireServer(petId)
				task.delay(2, function()
					equipPending = false
				end)
			end)
		end
	end

	PanelManager.register("Evolution", ui.EvoPanel, { OnOpen = renderEvolution })
	UiKit.bindModalLayout(ui.ScreenGui, ui.EvoScale, INVENTORY_SIZE, function(position)
		PanelManager.setBasePosition("Evolution", position)
	end)
	ui.EvoClose.Activated:Connect(function()
		PanelManager.close("Evolution")
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.P then
			PanelManager.toggle("Inventory")
		end
	end)

	inventoryRemote.OnClientEvent:Connect(function(data)
		if typeof(data) ~= "table" then
			return
		end
		snapshot = data
		renderInventory()
		renderEvolution()
	end)

	actionResultRemote.OnClientEvent:Connect(function(success: boolean, code: string, targetId: any, extra: any)
		equipPending = false
		if not success then
			showFeedback(ui.InventoryFeedback, messageFor(code), THEME.Error)
			showFeedback(ui.EvoFeedback, messageFor(code), THEME.Error)
		elseif extra == "Evolve" then
			local evoPet = typeof(targetId) == "string" and PetConfig.Pets[targetId]
			local msg = if evoPet then "¡Obtuviste " .. evoPet.DisplayName .. "!" else "¡Mascota evolucionada!"
			showFeedback(ui.EvoFeedback, msg, THEME.BuyHighlight)
			Juice.sound(Juice.Sounds.Upgrade, 1.15)
		end
	end)

	-- Jardín de mascotas: E en un pedestal compra su mascota -----------------------
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local standId = prompt:GetAttribute("ShopStand")
		if typeof(standId) == "string" and prompt.Name == "PetShopPrompt" then
			buyPetRemote:FireServer(standId)
		end
	end)
	shopResultRemote.OnClientEvent:Connect(function(success: boolean, code: string, _standId: any, petId: any, _uid: any, autoEquipped: any)
		local pet = typeof(petId) == "string" and PetConfig.Pets[petId]
		if success and pet then
			local rarity = rarityOf(petId)
			local equipped = if autoEquipped then "Ya la tienes equipada." else "Equípala en 🐾 Mascotas (P)."
			Toasts.show(("%s  %s · %s"):format(pet.DisplayName, bonusText(PetMath.getPetMultiplier(petId)), equipped), {
				Title = if code == "BossDrop" then "🏆 ¡Nueva mascota!" else "🐾 ¡Mascota comprada!",
				Color = if rarity then rarity.Color else THEME.Gold,
			})
			Juice.sound(if code == "BossDrop" then Juice.Sounds.HatchEpic else Juice.Sounds.Hatch)
		elseif not success then
			Toasts.show(messageFor(code), { Style = "Line", Color = THEME.Error })
		end
	end)

	renderInventory()
	requestInventoryRemote:FireServer()
	-- Si la carga termina en error, el inventario lo explica en lugar de seguir "cargando".
	player:GetAttributeChangedSignal(Constants.Attributes.DataStatus):Connect(renderInventory)
end

return PetController
