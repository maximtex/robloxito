-- AdventureController · TrackerAndSync: lista de seguimiento, tiempos de bendiciones y sincronización con el servidor.
-- Parte de AdventureController (ver AdventureController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AdventureConfig = require(Shared.Config.AdventureConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local AdventureLogic = require(Shared.AdventureLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local PanelManager = require(script.Parent.Parent.Parent.UI.PanelManager)
local HudDock = require(script.Parent.Parent.Parent.UI.HudDock)
local HudLayout = require(script.Parent.Parent.Parent.UI.HudLayout)

local ctx: any -- tabla de estado compartida (la crea AdventureController/init.luau)
local AMULET_PANEL: any
local CLOSE_DISTANCE: any
local COLORS: any
local FONTS: any
local MESSAGES: any
local THEME: any
local TRACKER_ROW: any
local TRACKER_WIDTH: any
local npcViews: any
local player: any

-- Funciones de las otras partes
local function animate(...) return ctx.animate(...) end
local function blessingText(...) return ctx.blessingText(...) end
local function celebrate(...) return ctx.celebrate(...) end
local function clockText(...) return ctx.clockText(...) end
local function closeDialog(...) return ctx.closeDialog(...) end
local function feedbackAmulets(...) return ctx.feedbackAmulets(...) end
local function notify(...) return ctx.notify(...) end
local function npcState(...) return ctx.npcState(...) end
local function objectiveText(...) return ctx.objectiveText(...) end
local function playSound(...) return ctx.playSound(...) end
local function refreshIndicator(...) return ctx.refreshIndicator(...) end
local function renderAmulets(...) return ctx.renderAmulets(...) end
local function renderDialog(...) return ctx.renderDialog(...) end
local function serverNow(...) return ctx.serverNow(...) end
local function syncItems(...) return ctx.syncItems(...) end

local Part = { Api = {} }

function Part.start()
	local dialog = ctx.dialog
	local menuEntry = ctx.menuEntry
	local requestRemote = ctx.requestRemote
	local resultRemote = ctx.resultRemote
	local stateRemote = ctx.stateRemote
	local timerLabels = ctx.timerLabels
	local timersLine = ctx.timersLine
	local tracker = ctx.tracker

	-- Seguimiento -----------------------------------------------------------------------------------
	ctx.renderTracker = function()
		for _, row in tracker.Rows do
			row:Destroy()
		end
		tracker.Rows = {}
		if not ctx.state.Ready then
			return
		end
		-- Primero las que ya se pueden entregar; luego las demás en curso.
		local entries = {}
		for index, npcId in AdventureLogic.npcOrder() do
			local st = npcState(npcId)
			if st.Status == "Ready" or st.Status == "Active" then
				table.insert(entries, { Id = npcId, State = st, Rank = (if st.Status == "Ready" then 0 else 100) + index })
			end
		end
		table.sort(entries, function(a, b)
			return a.Rank < b.Rank
		end)
		-- Filas que caben hasta el borde de la columna (encima del combate o del joystick).
		local column = HudDock.trackerColumn()
		local fit = HudLayout.trackerRows(tracker.Frame.AbsolutePosition.Y, HudDock.bottom(column), tracker.Scale.Scale, #entries)
		local shown = if fit < #entries then math.max(0, fit - 1) else #entries
		for order = 1, shown do
			local npcId = entries[order].Id
			local st = entries[order].State
			local npc = AdventureConfig.Npcs[npcId]
			local step = AdventureLogic.stepOf(npcId, st.Step)
			local ready = st.Status == "Ready"
			local row = UiKit.create("Frame", {
				Name = npcId,
				Size = UDim2.fromOffset(TRACKER_WIDTH, TRACKER_ROW),
				BackgroundColor3 = THEME.Panel,
				BackgroundTransparency = 0.25,
				LayoutOrder = order,
			}, tracker.Frame)
			UiKit.corner(row, 10)
			UiKit.stroke(row, if ready then COLORS.Ready else THEME.Stroke, if ready then 2 else 1, if ready then 0 else 0.5)
			UiKit.text(row, "Who", {
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(1, -20, 0, 20),
				Font = FONTS.Display,
				TextSize = 15,
				TextColor3 = if ready then COLORS.Ready else THEME.Gold,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = ("%s · %s"):format(npc.DisplayName, if step then step.Title else ""),
			})
			UiKit.text(row, "Goal", {
				Position = UDim2.fromOffset(10, 25),
				Size = UDim2.new(1, -20, 0, 20),
				Font = FONTS.Body,
				TextSize = 13,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = if ready then ("✓ ¡Lista! Vuelve con %s"):format(npc.DisplayName) else objectiveText(npcId, st),
			})
			table.insert(tracker.Rows, row)
		end
		-- Las que no caben se resumen en una línea (el panel de amuletos las lista todas).
		local hidden = #entries - shown
		if hidden > 0 and fit > 0 then
			local more = UiKit.text(tracker.Frame, "More", {
				Size = UDim2.fromOffset(TRACKER_WIDTH, 22),
				Font = FONTS.Body,
				TextSize = 14,
				TextColor3 = THEME.Muted,
				TextStrokeTransparency = 0.5,
				TextXAlignment = if column == "Right" then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
				Text = ("+%d %s en curso"):format(hidden, if hidden == 1 then "misión" else "misiones"),
				LayoutOrder = shown + 1,
			})
			table.insert(tracker.Rows, more)
		end
	end

	local function refreshSide()
		local unused = 0
		for _, count in ctx.state.Blessings or {} do
			unused += count
		end
		menuEntry.setBadge(if unused > 0 then tostring(unused) else nil)
	end

	-- Tiempos de las bendiciones activas (cada medio segundo).
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = serverNow()
			local parts = {}
			for _, blessingId in AdventureLogic.blessingOrder() do
				local expires = ctx.state.Active and ctx.state.Active[blessingId]
				if expires and expires > now then
					table.insert(parts, ("%s %s"):format(AdventureConfig.Blessings[blessingId].Icon, clockText(expires - now)))
				end
			end
			local text = table.concat(parts, "   ")
			if timersLine.Text ~= text then
				timersLine.Text = text
			end
			if PanelManager.isOpen(AMULET_PANEL) then
				for blessingId, label in timerLabels do
					if label.Parent then
						local text, active = blessingText(blessingId, now)
						label.Text = text
						label.TextColor3 = if active then THEME.BuyHighlight else THEME.Muted
					end
				end
			end
		end
	end)

	-- Estado del servidor ------------------------------------------------------------------------
	local function handleNotices(notices: { any })
		for _, notice in notices do
			if notice.Type == "Found" then
				local item = AdventureConfig.Items[notice.Item]
				local kind = item and AdventureConfig.ItemKinds[item.Kind]
				if kind then
					playSound(AdventureConfig.Sounds.Collect)
				end
			elseif notice.Type == "Progress" then
				local npc = AdventureConfig.Npcs[notice.Npc]
				local st = npcState(notice.Npc)
				local step = AdventureLogic.stepOf(notice.Npc, st.Step)
				if npc and step then
					if notice.Ready then
						notify(("✓ ¡%s lista! Vuelve con %s"):format(step.Title, npc.DisplayName), COLORS.Ready)
						playSound(AdventureConfig.Sounds.Accept)
					elseif step.Goal.Type == "Collect" then
						local kind = AdventureConfig.ItemKinds[AdventureConfig.Items[step.Goal.Items[1]].Kind]
						notify(("%s %s %d/%d"):format(kind.Icon, kind.DisplayName, notice.Progress, notice.Target), kind.Glow, "Progress_" .. notice.Npc)
					elseif step.Goal.Type == "Kill" then
						local enemy = EnemyConfig.Types[step.Goal.Enemies[1]]
						notify(("⚔ %s %d/%d"):format(if enemy then enemy.DisplayName else step.Title, notice.Progress, notice.Target), THEME.Text, "Progress_" .. notice.Npc)
					end
				end
			elseif notice.Type == "Reward" then
				local parts = {}
				if (notice.Money or 0) > 0 then
					table.insert(parts, ("+%s 💰"):format(formatNumber(notice.Money)))
				end
				local blessing = notice.Blessing and AdventureConfig.Blessings[notice.Blessing]
				if blessing then
					table.insert(parts, ("+1 %s %s"):format(blessing.Icon, blessing.DisplayName))
				end
				notify("🎁 " .. table.concat(parts, "  ·  "), THEME.Gold)
				if blessing then
					menuEntry.shimmer(true)
				end
				if notice.Amulet then
					celebrate(notice.Amulet)
				end
				if notice.SlotOpened then
					task.delay(3, function()
						notify("🧿 ¡Historias del Bosque y del Valle completas! Se abrió la 2.ª ranura de amuleto", THEME.Gold)
					end)
				elseif notice.AllDone and notice.Finished then
					task.delay(3, function()
						notify("🏆 ¡Completaste todas las historias!", THEME.Gold)
					end)
				end
				playSound(AdventureConfig.Sounds.Reward)
			elseif notice.Type == "BlessingEnded" then
				notify("Una bendición terminó", THEME.Muted)
			end
		end
	end

	stateRemote.OnClientEvent:Connect(function(newState: any)
		if typeof(newState) ~= "table" then
			return
		end
		if not newState.Ready then
			ctx.state = { Ready = false }
			return
		end
		ctx.state = newState
		-- Un objeto que deja de estar pendiente por haberse encontrado estalla; si deja de
		-- estarlo por otro motivo, simplemente desaparece.
		local found = {}
		for _, st in ctx.state.Npcs or {} do
			for _, itemId in st.Found or {} do
				found[itemId] = true
			end
		end
		for _, notice in ctx.state.Notices or {} do
			if notice.Type == "Found" then
				found[notice.Item] = true
			end
		end
		syncItems(ctx.state.Pending or {}, found)
		for npcId in npcViews do
			refreshIndicator(npcId)
		end
		ctx.renderTracker()
		refreshSide()
		if ctx.dialogNpc then
			renderDialog(false)
		end
		if PanelManager.isOpen(AMULET_PANEL) then
			renderAmulets()
		end
		handleNotices(ctx.state.Notices or {})
	end)

	resultRemote.OnClientEvent:Connect(function(success: any, code: any, action: any, detail: any)
		ctx.pending = false
		if success then
			if action == "Accept" and typeof(detail) == "table" and ctx.dialogNpc == detail.Npc then
				local st = npcState(detail.Npc)
				local step = AdventureLogic.stepOf(detail.Npc, st.Step)
				playSound(AdventureConfig.Sounds.Accept)
				if step then
					notify(("📜 Misión aceptada: %s"):format(step.Title), THEME.Gold)
				end
				renderDialog(true)
			elseif action == "TurnIn" and typeof(detail) == "table" and ctx.dialogNpc == detail.Npc then
				renderDialog(true)
			elseif action == "Equip" then
				local amulet = typeof(detail) == "table" and AdventureConfig.Amulets[detail.Amulet]
				feedbackAmulets(if amulet then ("Llevas puesto: %s %s"):format(amulet.Icon, amulet.DisplayName) else "Amuleto puesto", THEME.BuyHighlight)
			elseif action == "UseBlessing" then
				local blessing = typeof(detail) == "table" and AdventureConfig.Blessings[detail.Blessing]
				if blessing then
					notify(("%s ¡%s activa!"):format(blessing.Icon, blessing.DisplayName), blessing.Color)
				end
				playSound(AdventureConfig.Sounds.Blessing)
			end
		else
			local message = MESSAGES[code] or "Esa acción no está disponible."
			if ctx.dialogNpc and (action == "Accept" or action == "TurnIn") then
				dialog.Feedback.Text = message
			elseif PanelManager.isOpen(AMULET_PANEL) then
				feedbackAmulets(message, THEME.Error)
			else
				notify(message, THEME.Error)
			end
		end
	end)

	-- Cerrar la conversación al alejarse; girar personajes y mover objetos.
	RunService.RenderStepped:Connect(function(dt)
		animate(dt)
		local npcId = ctx.dialogNpc
		if npcId then
			local view = npcViews[npcId]
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if view and view.Home and root and root:IsA("BasePart") and (root.Position - view.Home.Position).Magnitude > CLOSE_DISTANCE then
				closeDialog()
			end
		end
	end)

	-- Las posiciones de los objetos pueden llegar después que el estado.
	local info = ReplicatedStorage:WaitForChild("AdventureWorld", 30)
	if info then
		info.AttributeChanged:Connect(function()
			syncItems(ctx.state.Pending or {}, {})
		end)
	end
	requestRemote:FireServer()
	-- Por si el servidor aún cargaba los datos: un segundo intento.
	task.delay(6, function()
		if not ctx.state.Ready then
			requestRemote:FireServer()
		end
	end)
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	AMULET_PANEL = context.AMULET_PANEL
	CLOSE_DISTANCE = context.CLOSE_DISTANCE
	COLORS = context.COLORS
	FONTS = context.FONTS
	MESSAGES = context.MESSAGES
	THEME = context.THEME
	TRACKER_ROW = context.TRACKER_ROW
	TRACKER_WIDTH = context.TRACKER_WIDTH
	npcViews = context.npcViews
	player = context.player
end

return Part
