-- PetController · InventoryAndEvo: inventario de mascotas, equipamiento, máquina de evolución y recepción del inventario.
-- Parte de PetController (ver PetController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PetConfig = require(Shared.Config.PetConfig)
local PetMath = require(Shared.PetMath)
local PetClassLogic = require(Shared.PetClassLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local RevealGate = require(script.Parent.Parent.Parent.Pets.RevealGate)
local PanelManager = require(script.Parent.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.Parent.UI.MenuBar)
local Juice = require(script.Parent.Parent.Parent.UI.Juice)
local Types = require(script.Parent.Types)
type Snapshot = Types.Snapshot

local ctx: any -- tabla de estado compartida (la crea PetController/init.luau)
local Codes: any
local FONTS: any
local INVENTORY_SIZE: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function bonusText(...) return ctx.bonusText(...) end
local function buildGui(...) return ctx.buildGui(...) end
local function messageFor(...) return ctx.messageFor(...) end
local function rarityOf(...) return ctx.rarityOf(...) end

local Part = { Api = {} }

function Part.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local purchaseEggRemote = remotes:WaitForChild(Constants.Remotes.PurchaseEgg) :: RemoteEvent
	local eggResultRemote = remotes:WaitForChild(Constants.Remotes.EggResult) :: RemoteEvent
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
		for _, uid in ctx.snapshot.Equipped do
			equippedSet[uid] = true
		end
		for _, entry in ctx.snapshot.Pets do
			if equippedSet[entry.Uid] then
				table.insert(equippedIds, entry.PetId)
			end
		end

		local multiplier = PetMath.getTotalMultiplier(equippedIds)
		-- Estado real de los datos (lo publica el servidor): nunca "cargando" para siempre.
		local dataStatus = player:GetAttribute(Constants.Attributes.DataStatus)
		local failed = dataStatus == "Failed"
		local status = if ctx.snapshot.Ready then "" elseif failed then "  ·  no se pudieron cargar" else "  ·  cargando…"
		local saving = if ctx.snapshot.Ready and ctx.snapshot.Saving == false then "  ·  sin guardado en esta sesión" else ""
		-- Las equipadas suben el daño y el dinero (la mitad de su bonificación:
		-- CombatConfig.PetDamageShare y PetMoneyShare)
		local half = 1 + (multiplier - 1) * 0.5
		-- Y lo que dan sus clases (Atacante, Tanque, Sanadora, Recolectora)
		local classes = PetClassLogic.summary(PetClassLogic.bonuses(equippedIds))
		ui.InventorySubtitle.Text = ("💥 y 💰 ×%s%s  ·  %d/%d en total%s%s"):format(
			formatNumber(half, 2),
			if classes ~= "" then "  ·  " .. classes else "",
			#ctx.snapshot.Pets,
			ctx.snapshot.MaxInventory,
			status,
			saving
		)

		-- Huecos de equipamiento
		local petIdByUid: { [string]: string } = {}
		for _, entry in ctx.snapshot.Pets do
			petIdByUid[entry.Uid] = entry.PetId
		end
		for _, child in ui.SlotsRow:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local slotWidth = (INVENTORY_SIZE.X - 44 - 8 * (ctx.snapshot.MaxEquipped - 1)) / ctx.snapshot.MaxEquipped
		for slotIndex = 1, ctx.snapshot.MaxEquipped do
			local uid = ctx.snapshot.Equipped[slotIndex]
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
		local slotsFull = #ctx.snapshot.Equipped >= ctx.snapshot.MaxEquipped
		-- "!" en el menú: hay un hueco libre y alguna mascota sin equipar.
		menuEntry.setBadge(if ctx.snapshot.Ready and not slotsFull and #ctx.snapshot.Pets > #ctx.snapshot.Equipped then "!" else nil)

		for _, child in ui.List:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		ui.EmptyLabel.Visible = #ctx.snapshot.Pets == 0
		ui.EmptyLabel.Text = if failed
			then "No se pudieron cargar tus mascotas. Tus datos guardados están a salvo: vuelve a entrar más tarde."
			elseif not ctx.snapshot.Ready then "Cargando tus mascotas…"
			else "Aún no tienes mascotas. Visita el santuario del Huevo del Bosque junto al camino."

		-- Orden: equipadas primero, luego por rareza (de mayor a menor) y nombre.
		local sorted = table.clone(ctx.snapshot.Pets)
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
			-- Rareza y clase (Atacante, Tanque, Sanadora o Recolectora) con lo que da
			local classId, classValue = PetClassLogic.bonusOf(entry.PetId)
			local classDef = PetConfig.Classes[classId]
			UiKit.text(card, "Rarity", {
				Position = UDim2.fromOffset(10, 46),
				Size = UDim2.new(1, -30, 0, 16),
				TextSize = 13,
				TextColor3 = rarity.Color,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = rarity.DisplayName .. " · " .. classDef.Icon .. " " .. classDef.Name,
			})
			UiKit.text(card, "Bonus", {
				Position = UDim2.fromOffset(10, 63),
				Size = UDim2.new(1, -20, 0, 16),
				Font = FONTS.Light,
				TextSize = 12,
				TextColor3 = THEME.Accent,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = bonusText(PetMath.getPetMultiplier(entry.PetId)) .. " · " .. PetClassLogic.amountText(classId, classValue),
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
				if equipPending or not ctx.snapshot.Ready then
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
		for _, entry in ctx.snapshot.Pets do
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
				if equipPending or not ctx.snapshot.Ready then
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
			-- Si hay un huevo abriéndose, el PanelManager no deja cambiar de panel.
			PanelManager.toggle("Inventory")
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
		ctx.snapshot = data
		renderInventory()
		renderEvolution()
	end)
	RevealGate.Released:Connect(function()
		if pendingSnapshot then
			ctx.snapshot = pendingSnapshot
			pendingSnapshot = nil
			renderInventory()
			renderEvolution()
		end
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

	ctx.eggResultRemote = eggResultRemote
	ctx.purchaseEggRemote = purchaseEggRemote
	ctx.renderInventory = renderInventory
	ctx.requestInventoryRemote = requestInventoryRemote
	ctx.showFeedback = showFeedback
	ctx.ui = ui
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	Codes = context.Codes
	FONTS = context.FONTS
	INVENTORY_SIZE = context.INVENTORY_SIZE
	THEME = context.THEME
	player = context.player
end

return Part
