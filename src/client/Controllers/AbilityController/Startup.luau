-- AbilityController · Startup: arranque (start): remotes, teclas Q/R, recargas, recepción de AbilityEvent y bucle de estados.
-- Parte de AbilityController (ver AbilityController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local AbilityLogic = require(Shared.AbilityLogic)
local CoreController = require(script.Parent.Parent.CoreController)
local Types = require(script.Parent.Types)
type SlotUi = Types.SlotUi

local ctx: any -- tabla de estado compartida (la crea AbilityController/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a AbilityController)
local ABILITY_KINDS: any
local BUTTON_SIZE: any
local Codes: any
local EFFECTS: any
local INK: any
local SLOT_ORDER: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function addShake(...) return ctx.addShake(...) end
local function buildGui(...) return ctx.buildGui(...) end
local function cameraStep(...) return ctx.cameraStep(...) end
local function castableCount(...) return ctx.castableCount(...) end
local function kickFov(...) return ctx.kickFov(...) end
local function playGesture(...) return ctx.playGesture(...) end
local function refreshStatuses(...) return ctx.refreshStatuses(...) end
local function screenFlash(...) return ctx.screenFlash(...) end
local function showReaction(...) return ctx.showReaction(...) end
local function slotElement(...) return ctx.slotElement(...) end
local function soundAt(...) return ctx.soundAt(...) end

function Api.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local useRemote = remotes:WaitForChild(Constants.Remotes.UseAbility) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.AbilityResult) :: RemoteEvent
	local eventRemote = remotes:WaitForChild(Constants.Remotes.AbilityEvent) :: RemoteEvent

	local existingFx = Workspace:FindFirstChild("ClientAbilityFX")
	if existingFx then
		existingFx:Destroy()
	end
	ctx.fxFolder = Instance.new("Folder")
	ctx.fxFolder.Name = "ClientAbilityFX"
	ctx.fxFolder.Parent = Workspace

	local ui = buildGui()
	local slots: { [string]: SlotUi } = { Primary = ui.Primary, Secondary = ui.Secondary }
	local readyAtByElement: { [string]: number } = {}
	local wasCooling: { [string]: boolean } = {}
	local pendingAt: { [string]: number } = { Primary = -math.huge, Secondary = -math.huge }

	local function applyElements()
		for _, slot in SLOT_ORDER do
			local slotUi = slots[slot]
			local elementId = slotElement(slot)
			local ability = elementId and AbilityLogic.castable(elementId)
			if ability then
				slotUi.Frame.Visible = true
				slotUi.Button.Text = ability.Icon
				slotUi.Button.TextTransparency = 0
				slotUi.Name.Text = if #ability.Name > 9 then (ability.Name:match("^%S+") or ability.Name) else ability.Name
				slotUi.Frame.BackgroundColor3 = Color3.new(1, 1, 1)
				local c = ability.Color
				slotUi.Gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, c:Lerp(Color3.new(1, 1, 1), 0.55)),
					ColorSequenceKeypoint.new(0.55, c),
					ColorSequenceKeypoint.new(1, c:Lerp(Color3.new(0, 0, 0), 0.28)),
				})
				slotUi.Stroke.Color = INK
				slotUi.Stroke.Transparency = 0
			elseif slot == "Secondary" and castableCount() >= 2 then
				slotUi.Frame.Visible = true
				slotUi.Button.Text = "+"
				slotUi.Button.TextTransparency = 0.3
				slotUi.Name.Text = "Elige tu R (N)"
				slotUi.Frame.BackgroundColor3 = THEME.Panel
				slotUi.Stroke.Color = INK
				slotUi.Stroke.Transparency = 0.2
			else
				slotUi.Frame.Visible = false
			end
		end
	end
	for _, attribute in { Constants.Attributes.SelectedCore, Constants.Attributes.SecondaryCore, Constants.Attributes.UnlockedCores } do
		player:GetAttributeChangedSignal(attribute):Connect(applyElements)
	end
	applyElements()

	local noticeToken = 0
	local function notice(text: string)
		noticeToken += 1
		local token = noticeToken
		ui.Notice.Text = text
		ui.Notice.TextTransparency = 0
		ui.Notice.TextStrokeTransparency = 0.3
		task.delay(1.6, function()
			if noticeToken == token then
				TweenService:Create(ui.Notice, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end

	local function readyPulse(slotUi: SlotUi)
		slotUi.ReadyStroke.Transparency = 0
		slotUi.ReadyStroke.Thickness = 3
		local ring = slotUi.ReadyStroke.Parent :: Frame
		ring.Size = UDim2.fromScale(1, 1)
		TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1.35, 1.35) }):Play()
		TweenService:Create(slotUi.ReadyStroke, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Thickness = 1 }):Play()
	end

	-- Recargas: un bucle ligero para los dos botones.
	task.spawn(function()
		while true do
			local now = Workspace:GetServerTimeNow()
			for _, slot in SLOT_ORDER do
				local slotUi = slots[slot]
				local elementId = slotElement(slot)
				local ability = elementId and AbilityConfig.Abilities[elementId]
				local remaining = if elementId then (readyAtByElement[elementId] or 0) - now else 0
				if ability and remaining > 0 then
					slotUi.Cooldown.Size = UDim2.fromScale(1, math.clamp(remaining / ability.Cooldown, 0, 1))
					slotUi.Count.Visible = true
					slotUi.Count.Text = tostring(math.ceil(remaining))
					wasCooling[slot] = true
				else
					slotUi.Cooldown.Size = UDim2.fromScale(1, 0)
					slotUi.Count.Visible = false
					if wasCooling[slot] then
						wasCooling[slot] = false
						readyPulse(slotUi)
					end
				end
			end
			task.wait(0.1)
		end
	end)

	local function shake(slotUi: SlotUi)
		local tween = TweenService:Create(slotUi.Frame, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), { Rotation = 6 })
		tween.Completed:Once(function()
			slotUi.Frame.Rotation = 0
		end)
		tween:Play()
	end

	local function tryUse(slot: string)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (humanoid and humanoid.Health > 0) then
			return
		end
		local elementId = slotElement(slot)
		if not elementId then
			if slot == "Secondary" and castableCount() >= 2 and CoreController.open then
				CoreController.open(nil) -- elegir el secundario en el panel
			end
			return
		end
		if (readyAtByElement[elementId] or 0) - Workspace:GetServerTimeNow() > 0.05 then
			shake(slots[slot]) -- aún recargando
			return
		end
		if os.clock() - pendingAt[slot] < 0.8 then
			return -- esperando la respuesta del servidor
		end
		pendingAt[slot] = os.clock()
		useRemote:FireServer(slot) -- sin objetivo: lo decide el servidor
	end

	ContextActionService:BindAction("RebirthAbility", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			tryUse("Primary")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("RebirthAbilitySecondary", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			tryUse("Secondary")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonB)
	ui.Primary.Button.Activated:Connect(function()
		tryUse("Primary")
	end)
	ui.Secondary.Button.Activated:Connect(function()
		tryUse("Secondary")
	end)

	resultRemote.OnClientEvent:Connect(function(success: any, code: any, elementId: any, serverReadyAt: any, slot: any)
		local slotName = if slot == "Secondary" then "Secondary" else "Primary"
		pendingAt[slotName] = -math.huge
		local ability = typeof(elementId) == "string" and AbilityConfig.Abilities[elementId] or nil
		if typeof(serverReadyAt) == "number" and ability and (success == true or code == Codes.Cooldown) then
			readyAtByElement[elementId] = serverReadyAt
		end
		local slotUi = slots[slotName]
		if success == true and ability then
			-- Sensación al lanzarla: gesto, sacudida, zoom y destello del color del elemento.
			playGesture(ability.Gesture)
			addShake(ability.Shake or 0.3)
			kickFov(2.5)
			screenFlash(ability.Color, 0.6)
			slotUi.Frame.Size = UDim2.fromOffset(BUTTON_SIZE * 1.12, BUTTON_SIZE * 1.12)
			TweenService:Create(slotUi.Frame, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE) }):Play()
		elseif code == Codes.NoTarget then
			notice("No hay ningún enemigo delante")
			shake(slotUi)
		elseif code == Codes.Cooldown then
			shake(slotUi)
		end
	end)

	eventRemote.OnClientEvent:Connect(function(event: any)
		if typeof(event) ~= "table" or typeof(event.Kind) ~= "string" then
			return
		end
		local isOwner = event.Owner == player
		local ok, err = pcall(function()
			if event.Kind == "Reaction" then
				showReaction(event, isOwner)
				return
			end
			local effect = EFFECTS[event.Kind]
			if not effect then
				return
			end
			-- Sonido de lanzamiento en el punto de la habilidad (lo oyen los cercanos).
			if ABILITY_KINDS[event.Kind] then
				local origin = if typeof(event.Origin) == "Vector3" then event.Origin elseif typeof(event.Center) == "Vector3" then event.Center else nil
				if origin then
					soundAt(origin, AbilityConfig.Sounds.Cast[event.Element])
				end
			end
			effect(event, isOwner)
		end)
		if not ok then
			warn("[AbilityController] " .. tostring(event.Kind) .. ": " .. tostring(err))
		end
	end)

	-- Limpiar efectos temporales al morir o cambiar de zona.
	local function clear()
		ctx.fxFolder:ClearAllChildren()
	end
	player.CharacterRemoving:Connect(clear)
	player:GetAttributeChangedSignal(Constants.Attributes.CurrentZone):Connect(clear)

	RunService:BindToRenderStep("RebirthAbilityCamera", Enum.RenderPriority.Camera.Value + 1, cameraStep)

	-- Estados y marcas de los enemigos (atributos del servidor): un único bucle ligero.
	task.spawn(function()
		while true do
			task.wait(0.15)
			local ok, err = pcall(refreshStatuses)
			if not ok then
				warn("[AbilityController] estados: " .. tostring(err))
			end
		end
	end)
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	ABILITY_KINDS = context.ABILITY_KINDS
	BUTTON_SIZE = context.BUTTON_SIZE
	Codes = context.Codes
	EFFECTS = context.EFFECTS
	INK = context.INK
	SLOT_ORDER = context.SLOT_ORDER
	THEME = context.THEME
	player = context.player
end

return Part
