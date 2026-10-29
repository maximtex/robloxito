-- PetController · HatchSequence: incubación, revelación 3D de la mascota, compra con reintento y proximidad al santuario.
-- Parte de PetController (ver PetController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local HttpService = game:GetService("HttpService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local PetConfig = require(Shared.Config.PetConfig)
local EggConfig = require(Shared.Config.EggConfig)
local PetMath = require(Shared.PetMath)
local PetClassLogic = require(Shared.PetClassLogic)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local RevealGate = require(script.Parent.Parent.Parent.Pets.RevealGate)
local PetModelBuilder = require(script.Parent.Parent.Parent.Pets.PetModelBuilder)
local PanelManager = require(script.Parent.Parent.Parent.UI.PanelManager)
local Juice = require(script.Parent.Parent.Parent.UI.Juice)

local ctx: any -- tabla de estado compartida (la crea PetController/init.luau)
local Codes: any
local EGG_PANEL_CLOSE_DISTANCE: any
local EGG_SIZE: any
local GIVE_UP_AFTER: any
local RESEND_AFTER: any
local SEQUENCE_SECONDS: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function bonusText(...) return ctx.bonusText(...) end
local function clearViewport(...) return ctx.clearViewport(...) end
local function closeEggPanel(...) return ctx.closeEggPanel(...) end
local function eggState(...) return ctx.eggState(...) end
local function failIncubation(...) return ctx.failIncubation(...) end
local function hasTriple(...) return ctx.hasTriple(...) end
local function messageFor(...) return ctx.messageFor(...) end
local function openEggPanel(...) return ctx.openEggPanel(...) end
local function rarityOf(...) return ctx.rarityOf(...) end
local function refreshEggButton(...) return ctx.refreshEggButton(...) end
local function renderInventory(...) return ctx.renderInventory(...) end
local function resetHatch(...) return ctx.resetHatch(...) end
local function setCracks(...) return ctx.setCracks(...) end
local function showFeedback(...) return ctx.showFeedback(...) end
local function stopAnimation(...) return ctx.stopAnimation(...) end

local Part = { Api = {} }

function Part.start()
	local eggResultRemote = ctx.eggResultRemote
	local purchaseEggRemote = ctx.purchaseEggRemote
	local requestInventoryRemote = ctx.requestInventoryRemote
	local ui = ctx.ui

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
		ctx.animationConnection = RunService.RenderStepped:Connect(function()
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
		ctx.phase = "revealed"
		ctx.incubating = false
		local petId = result[4] :: string
		local autoEquipped = result[6] == true
		local extras = if typeof(result[8]) == "table" then result[8] else {}
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
		-- Estallido de estrellas del color de la rareza y sonido según lo rara que es.
		local order = rarity.Order or 1
		Juice.burst(ui.Viewport, rarity.Color, 8 + order * 5, 130 + order * 20)
		Juice.sound(Juice.Sounds.Hatch)
		if order >= 4 then
			Juice.sound(Juice.Sounds.HatchEpic)
		elseif order >= 3 then
			Juice.sound(Juice.Sounds.HatchRare)
		end
		ui.HatchStatus.Text = "¡Ha nacido!"
		ui.HatchStatus.TextColor3 = THEME.Gold
		ui.RevealName.Text = if pet then pet.DisplayName else petId
		ui.RevealName.TextColor3 = rarity.Color
		ui.RevealDetails.Text = rarity.DisplayName .. "  ·  " .. bonusText(PetMath.getPetMultiplier(petId)) .. " de poder  ·  " .. PetClassLogic.describe(petId)
		ui.RevealEquip.Text = if autoEquipped then "✓ Equipada automáticamente" else "Guardada en tu inventario (ya tienes el máximo equipado)"
		-- Apertura ×3: las otras dos mascotas, con el color de su rareza, debajo.
		if #extras > 0 then
			local names = {}
			for _, extra in extras do
				if typeof(extra) == "table" and typeof(extra.PetId) == "string" then
					local other = PetConfig.Pets[extra.PetId]
					local color = rarityOf(extra.PetId).Color
					table.insert(names, ('<font color="#%s">%s</font>'):format(color:ToHex(), if other then other.DisplayName else extra.PetId))
				end
			end
			ui.RevealEquip.RichText = true
			ui.RevealEquip.Text = "También: " .. table.concat(names, "  ·  ")
		else
			ui.RevealEquip.RichText = false
		end
		ui.AgainButton.Visible = true
		ui.BackButton.Visible = true
		ui.EggClose.Visible = true
		refreshEggButton()

		-- A partir de aquí la mascota ya se puede ver en el mundo, el inventario y el HUD.
		RevealGate.release()
	end

	-- Fase de incubación: temblor creciente, brillo y grietas. Si al terminar aún no ha
	-- llegado el resultado, el huevo sigue temblando (sin revelar nada) hasta que llegue.
	local function runIncubation(token: number, eggId: string, requestId: string, count: number)
		local startedAt = os.clock()
		local resent = false
		ui.HatchStatus.Text = if count > 1 then ("Incubando %d huevos…"):format(count) else "Incubando…"
		ui.HatchStatus.TextColor3 = THEME.Text
		ctx.animationConnection = RunService.RenderStepped:Connect(function()
			if ctx.sequenceToken ~= token then
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
			if ctx.pendingResult then
				local result = ctx.pendingResult
				ctx.pendingResult = nil
				reveal(result)
			elseif elapsedTime > GIVE_UP_AFTER then
				failIncubation("Sin respuesta del servidor. Si la compra se completó, la mascota está en tu inventario.")
			elseif elapsedTime > RESEND_AFTER and not resent then
				resent = true
				ui.HatchStatus.Text = "Esperando al bosque…"
				-- Mismo requestId: el servidor no vuelve a cobrar ni a sortear.
				purchaseEggRemote:FireServer(eggId, requestId, count)
			end
		end)
	end

	local function startPurchase(count: number?)
		if ctx.incubating or not ctx.currentEggId then
			return
		end
		local amount = if count and count > 1 and hasTriple() then MonetizationConfig.TripleCount else 1
		local eggId = ctx.currentEggId :: string
		local egg = EggConfig.Eggs[eggId]
		local locked, affordable = eggState(egg)
		if amount > 1 then
			local money = player:GetAttribute(Constants.Attributes.Money)
			affordable = typeof(money) == "number" and money >= egg.Cost * amount
		end
		if locked then
			showFeedback(ui.EggFeedback, messageFor(Codes.ZoneLocked), THEME.Error)
			return
		end
		if not affordable then
			showFeedback(ui.EggFeedback, messageFor(Codes.InsufficientMoney), THEME.Error)
			return
		end
		ctx.lastCount = amount

		resetHatch() -- limpia una revelación anterior ("Abrir otro")
		local token = ctx.sequenceToken
		ctx.phase = "incubating"
		ctx.incubating = true
		local requestId = HttpService:GenerateGUID(false)
		ctx.currentRequestId = requestId
		RevealGate.hold()
		ui.Hatch.Visible = true
		ui.EggClose.Visible = false -- no se cierra a mitad de la apertura
		runIncubation(token, eggId, requestId, amount)
		purchaseEggRemote:FireServer(eggId, requestId, amount)
	end

	ui.IncubateButton.Activated:Connect(function()
		startPurchase(1)
	end)
	ui.TripleButton.Activated:Connect(function()
		startPurchase(MonetizationConfig.TripleCount)
	end)
	ui.AgainButton.Activated:Connect(function()
		startPurchase(ctx.lastCount)
	end)
	ui.BackButton.Activated:Connect(closeEggPanel)
	ui.EggClose.Activated:Connect(closeEggPanel)

	eggResultRemote.OnClientEvent:Connect(function(...)
		local result = table.pack(...)
		local success, code, requestId = result[1], result[2], result[7]
		-- Ignorar respuestas de otras solicitudes (p. ej. la del reenvío si ya llegó la original).
		if ctx.phase ~= "incubating" or requestId ~= ctx.currentRequestId or ctx.pendingResult then
			return
		end
		if success ~= true or typeof(result[4]) ~= "string" then
			failIncubation(messageFor(code))
			return
		end
		ctx.pendingResult = result -- se revela al terminar la incubación
	end)

	player:GetAttributeChangedSignal(Constants.Attributes.Money):Connect(refreshEggButton)
	player:GetAttributeChangedSignal(Constants.Attributes.UnlockedZones):Connect(refreshEggButton)
	player:GetAttributeChangedSignal(Constants.Attributes.Passes):Connect(refreshEggButton)

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
			if PanelManager.isOpen("Egg") and ctx.currentPromptPart and not ctx.incubating then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and (root.Position - ctx.currentPromptPart.Position).Magnitude > EGG_PANEL_CLOSE_DISTANCE then
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

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	Codes = context.Codes
	EGG_PANEL_CLOSE_DISTANCE = context.EGG_PANEL_CLOSE_DISTANCE
	EGG_SIZE = context.EGG_SIZE
	GIVE_UP_AFTER = context.GIVE_UP_AFTER
	RESEND_AFTER = context.RESEND_AFTER
	SEQUENCE_SECONDS = context.SEQUENCE_SECONDS
	THEME = context.THEME
	player = context.player
end

return Part
