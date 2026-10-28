-- AdventureController · Dialog: arranque de remotes y paneles, colocación en el HUD y conversación con los personajes.
-- Parte de AdventureController (ver AdventureController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local AdventureConfig = require(Shared.Config.AdventureConfig)
local AdventureLogic = require(Shared.AdventureLogic)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.Parent.UI.PanelManager)
local MenuBar = require(script.Parent.Parent.Parent.UI.MenuBar)
local Toasts = require(script.Parent.Parent.Parent.UI.Toasts)
local HudDock = require(script.Parent.Parent.Parent.UI.HudDock)

local ctx: any -- tabla de estado compartida (la crea AdventureController/init.luau)
local AMULET_PANEL: any
local COLORS: any
local DIALOG_PANEL: any
local DIALOG_SIZE: any
local THEME: any
local TYPE_SPEED: any
local player: any

-- Funciones de las otras partes
local function buildAmuletPanel(...) return ctx.buildAmuletPanel(...) end
local function buildCelebration(...) return ctx.buildCelebration(...) end
local function buildDialog(...) return ctx.buildDialog(...) end
local function buildTracker(...) return ctx.buildTracker(...) end
local function npcState(...) return ctx.npcState(...) end
local function objectiveText(...) return ctx.objectiveText(...) end
local function playSound(...) return ctx.playSound(...) end
local function rewardText(...) return ctx.rewardText(...) end
local function watchNpcs(...) return ctx.watchNpcs(...) end

local Part = { Api = {} }

function Part.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local requestRemote = remotes:WaitForChild(Constants.Remotes.RequestAdventure) :: RemoteEvent
	local stateRemote = remotes:WaitForChild(Constants.Remotes.AdventureState) :: RemoteEvent
	local dialogRemote = remotes:WaitForChild(Constants.Remotes.AdventureDialog) :: RemoteEvent
	local actionRemote = remotes:WaitForChild(Constants.Remotes.AdventureAction) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.AdventureResult) :: RemoteEvent

	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local existing = playerGui:FindFirstChild("AdventureHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "AdventureHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local dialog = buildDialog(screenGui)
	local amulets = buildAmuletPanel(screenGui)
	local tracker = buildTracker()
	screenGui.Parent = playerGui
	local celebration = buildCelebration(playerGui)

	local localFolder = Workspace:FindFirstChild("AdventureItemsLocal")
	if localFolder then
		localFolder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "AdventureItemsLocal"
	folder.Parent = Workspace
	ctx.itemsFolder = folder

	watchNpcs(playerGui)

	-- Azulejo del menú y línea de estado con las bendiciones activas.
	local menuEntry = MenuBar.add({
		Id = "Amulets",
		Order = 4,
		Icon = "🧿",
		Label = "Amuletos",
		Key = "G",
		Color = Color3.fromRGB(190, 130, 255),
		Panels = { AMULET_PANEL },
		OnActivate = function()
			PanelManager.toggle(AMULET_PANEL)
		end,
	})
	local timersLine = MenuBar.status("Blessings", 2)
	timersLine.TextColor3 = THEME.Gold

	-- Diseño: el diálogo abajo al centro; el seguimiento en su columna de HudDock.
	local function place()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local scale = UiKit.computeScale(size)
		dialog.Scale.Scale = math.min(scale, (size.X - 24) / DIALOG_SIZE.X)
		tracker.Scale.Scale = scale
		celebration.Scale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 720) * 1.1, 0.6, 1.3)
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()
	-- Si cambia el diseño (o sube/baja lo que hay encima), cambian las filas que caben.
	local relayoutQueued = false
	local function queueTrackerRender()
		if relayoutQueued then
			return
		end
		relayoutQueued = true
		task.defer(function()
			relayoutQueued = false
			if ctx.renderTracker then
				ctx.renderTracker()
			end
		end)
	end
	HudDock.Changed:Connect(function()
		place()
		local column = HudDock.trackerColumn()
		if tracker.Frame.Parent ~= HudDock.column(column) then
			HudDock.attach(column, tracker.Frame, 20)
		end
		queueTrackerRender()
	end)
	local lastTop = -1
	tracker.Frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		local top = math.floor(tracker.Frame.AbsolutePosition.Y)
		if math.abs(top - lastTop) >= 4 then
			lastTop = top
			queueTrackerRender()
		end
	end)

	-- Avisos breves (pila común) -------------------------------------------------------------
	-- `key`: los avisos del mismo progreso se sustituyen en lugar de apilarse.
	local function notify(text: string, color: Color3?, key: string?)
		Toasts.show(text, { Color = color or THEME.Text, Key = key })
	end

	-- Conversación ----------------------------------------------------------------------------
	local pages: { any } = {}
	local typingToken = 0

	local function typeText(text: string)
		typingToken += 1
		local token = typingToken
		dialog.Body.Text = text
		dialog.Body.MaxVisibleGraphemes = 0
		local total = utf8.len(text) or #text
		task.spawn(function()
			local shown = 0
			while shown < total and typingToken == token do
				shown = math.min(total, shown + math.max(1, math.floor(TYPE_SPEED * RunService.RenderStepped:Wait())))
				dialog.Body.MaxVisibleGraphemes = shown
			end
			if typingToken == token then
				dialog.Body.MaxVisibleGraphemes = -1
			end
		end)
	end

	local function setButton(button: TextButton, text: string?, color: Color3?)
		button.Visible = text ~= nil
		if text then
			button.Text = text
			if color then
				button.BackgroundColor3 = color
			end
		end
	end

	local function renderDialog(retype: boolean)
		local npcId = ctx.dialogNpc
		if not npcId then
			return
		end
		local npc = AdventureConfig.Npcs[npcId]
		dialog.Name.Text = npc.DisplayName
		dialog.PortraitText.Text = string.sub(npc.DisplayName, 1, 1)
		dialog.Portrait.BackgroundColor3 = npc.Look.Primary
		dialog.PortraitStroke.Color = npc.Look.Accent
		local page = pages[1]
		dialog.Feedback.Text = ""
		dialog.PrimaryShimmer(false)
		if page and page.Kind == "Delivery" then
			local giver = AdventureConfig.Npcs[page.Giver]
			local step = AdventureLogic.stepOf(page.Giver, npcState(page.Giver).Step)
			dialog.Title.Text = ("Encargo de %s"):format(giver.DisplayName)
			if retype then
				typeText(page.Text)
			end
			dialog.Objective.Visible = true
			dialog.ObjectiveStroke.Color = COLORS.Ready
			dialog.ObjectiveText.Text = ("✓ Entregado: %s"):format(if step then step.Title else "encargo")
			dialog.ObjectiveText.TextColor3 = COLORS.Ready
			dialog.Reward.Text = ("Vuelve con %s para la recompensa."):format(giver.DisplayName)
			setButton(dialog.Primary, "Seguir", THEME.Buy)
			setButton(dialog.Secondary, nil)
			return
		end
		local st = npcState(npcId)
		local step = AdventureLogic.stepOf(npcId, st.Step)
		dialog.ObjectiveText.TextColor3 = THEME.Text
		dialog.ObjectiveStroke.Color = THEME.Stroke
		if st.Status == "Done" or not step then
			dialog.Title.Text = npc.Title .. " · historia completada ✓"
			if retype then
				typeText(npc.Greeting)
			end
			dialog.Objective.Visible = false
			setButton(dialog.Primary, "Adiós", THEME.Secondary)
			setButton(dialog.Secondary, nil)
			return
		end
		dialog.Title.Text = ("%s · misión %d de %d: %s"):format(npc.Title, st.Step, st.Steps, step.Title)
		dialog.Objective.Visible = true
		dialog.Reward.Text = rewardText(npcId, st)
		if st.Status == "Offer" then
			if retype then
				typeText(step.Offer)
			end
			dialog.ObjectiveText.Text = "🎯 " .. step.Objective .. (if step.Goal.Type ~= "Talk" then (" (%d)"):format(st.Target) else "")
			setButton(dialog.Primary, "Aceptar", THEME.Buy)
			setButton(dialog.Secondary, "Ahora no", THEME.Secondary)
			dialog.PrimaryShimmer(true)
		elseif st.Status == "Ready" then
			if retype then
				typeText(step.Ready)
			end
			dialog.ObjectiveText.Text = "✓ " .. objectiveText(npcId, st)
			dialog.ObjectiveText.TextColor3 = COLORS.Ready
			dialog.ObjectiveStroke.Color = COLORS.Ready
			setButton(dialog.Primary, "Entregar ✓", THEME.Buy)
			setButton(dialog.Secondary, nil)
			dialog.PrimaryShimmer(true)
		else
			if retype then
				typeText(step.Active)
			end
			dialog.ObjectiveText.Text = "🎯 " .. objectiveText(npcId, st)
			setButton(dialog.Primary, "¡Voy!", THEME.Secondary)
			setButton(dialog.Secondary, nil)
		end
	end

	local function openDialog(npcId: string, deliveredFor: string?)
		ctx.dialogNpc = npcId
		pages = {}
		if deliveredFor and AdventureConfig.Npcs[deliveredFor] then
			local giverState = npcState(deliveredFor)
			local step = AdventureLogic.stepOf(deliveredFor, giverState.Step)
			if step and step.Delivery then
				table.insert(pages, { Kind = "Delivery", Giver = deliveredFor, Text = step.Delivery })
			end
		end
		PanelManager.open(DIALOG_PANEL)
		renderDialog(true)
		playSound(AdventureConfig.Sounds.Talk)
	end

	local function closeDialog()
		PanelManager.close(DIALOG_PANEL)
	end

	PanelManager.register(DIALOG_PANEL, dialog.Panel, {
		OnClose = function()
			ctx.dialogNpc = nil
			typingToken += 1
		end,
	})

	dialog.Skip.Activated:Connect(function()
		typingToken += 1
		dialog.Body.MaxVisibleGraphemes = -1
	end)
	dialog.Close.Activated:Connect(closeDialog)
	dialog.Secondary.Activated:Connect(closeDialog)
	dialog.Primary.Activated:Connect(function()
		local npcId = ctx.dialogNpc
		if not npcId or ctx.pending then
			return
		end
		if pages[1] then
			table.remove(pages, 1)
			renderDialog(true)
			return
		end
		local st = npcState(npcId)
		local action = if st.Status == "Offer" then "Accept" elseif st.Status == "Ready" then "TurnIn" else nil
		if not action then
			closeDialog()
			return
		end
		ctx.pending = true
		actionRemote:FireServer(action, npcId)
		task.delay(3, function()
			ctx.pending = false -- sin respuesta (límite de frecuencia): se puede reintentar
		end)
	end)

	dialogRemote.OnClientEvent:Connect(function(npcId: any, deliveredFor: any)
		if typeof(npcId) == "string" and AdventureConfig.Npcs[npcId] then
			openDialog(npcId, if typeof(deliveredFor) == "string" then deliveredFor else nil)
		end
	end)

	ctx.actionRemote = actionRemote
	ctx.amulets = amulets
	ctx.celebration = celebration
	ctx.closeDialog = closeDialog
	ctx.dialog = dialog
	ctx.menuEntry = menuEntry
	ctx.notify = notify
	ctx.renderDialog = renderDialog
	ctx.requestRemote = requestRemote
	ctx.resultRemote = resultRemote
	ctx.screenGui = screenGui
	ctx.stateRemote = stateRemote
	ctx.timersLine = timersLine
	ctx.tracker = tracker
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	AMULET_PANEL = context.AMULET_PANEL
	COLORS = context.COLORS
	DIALOG_PANEL = context.DIALOG_PANEL
	DIALOG_SIZE = context.DIALOG_SIZE
	THEME = context.THEME
	TYPE_SPEED = context.TYPE_SPEED
	player = context.player
end

return Part
