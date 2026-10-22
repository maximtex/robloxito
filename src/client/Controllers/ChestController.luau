-- Cofres escondidos (ChestService): cada jugador ve SUS cofres abiertos o cerrados.
-- - Cerrado (disponible): brillo dorado, chispas y aviso "Abrir" (tecla E).
-- - Abierto (en espera): tapa levantada, sin brillo ni aviso y un letrero con lo que falta.
-- - Al abrir uno: la tapa salta, chispas, sonido y un aviso con el premio.
-- Abrir lo decide el servidor; aquí solo se pinta el estado que manda.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ChestConfig = require(Shared.Config.ChestConfig)
local AdventureConfig = require(Shared.Config.AdventureConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local Theme = require(script.Parent.Parent.UI.Theme)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local Juice = require(script.Parent.Parent.UI.Juice)

local Codes = Constants.PurchaseCodes
local THEME = Theme.Colors
local OPEN_ANGLE = math.rad(-105)

local ChestController = {}

local player = Players.LocalPlayer

type ChestView = {
	Model: Model,
	Body: BasePart,
	Prompt: ProximityPrompt?,
	LidParts: { { Part: BasePart, Closed: CFrame, Hinge: CFrame } },
	Label: TextLabel,
	Billboard: BillboardGui,
	Open: boolean,
	Angle: NumberValue,
}

local views: { [string]: ChestView } = {}
local deadlines: { [string]: number } = {} -- os.clock() en que vuelve a estar disponible

local function remaining(chestId: string): number
	local deadline = deadlines[chestId]
	return if deadline then math.max(0, deadline - os.clock()) else 0
end

local function formatWait(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	if hours > 0 then
		return ("%dh %02dm"):format(hours, minutes)
	end
	return ("%dm %02ds"):format(minutes, seconds % 60)
end

local function applyAngle(view: ChestView)
	local angle = view.Angle.Value
	for _, item in view.LidParts do
		item.Part.CFrame = item.Hinge * CFrame.Angles(angle, 0, 0) * item.Hinge:Inverse() * item.Closed
	end
end

local function setOpen(view: ChestView, open: boolean, animate: boolean)
	if view.Open == open and not animate then
		return
	end
	view.Open = open
	local glow = view.Body:FindFirstChild("Glow")
	if glow and glow:IsA("PointLight") then
		glow.Enabled = not open
	end
	local sparkles = view.Body:FindFirstChild("Sparkles")
	if sparkles and sparkles:IsA("ParticleEmitter") then
		sparkles.Enabled = not open
	end
	if view.Prompt then
		view.Prompt.Enabled = not open
	end
	view.Billboard.Enabled = open
	local target = if open then OPEN_ANGLE else 0
	if animate then
		local tween = TweenService:Create(view.Angle, TweenInfo.new(if open then 0.55 else 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = target })
		tween:Play()
	else
		view.Angle.Value = target
	end
end

local function attach(model: Model)
	local chestId = model:GetAttribute("ChestId")
	if typeof(chestId) ~= "string" or views[chestId] then
		return
	end
	local body = model:WaitForChild("Body", 10)
	if not (body and body:IsA("BasePart")) then
		return
	end
	local lidParts = {}
	for _, item in model:GetChildren() do
		local hinge = item:GetAttribute("Hinge")
		if item:IsA("BasePart") and typeof(hinge) == "CFrame" then
			table.insert(lidParts, { Part = item, Closed = item.CFrame, Hinge = hinge })
		end
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ChestWait"
	billboard.Size = UDim2.fromOffset(150, 34)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.MaxDistance = 30
	billboard.AlwaysOnTop = false
	billboard.Enabled = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(30, 36, 46)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 240, 210)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = label
	label.Parent = billboard
	billboard.Adornee = body
	billboard.Parent = body
	local angle = Instance.new("NumberValue")
	angle.Value = 0
	local prompt = body:FindFirstChild("ChestPrompt")
	local view: ChestView = {
		Model = model,
		Body = body,
		Prompt = if prompt and prompt:IsA("ProximityPrompt") then prompt else nil,
		LidParts = lidParts,
		Label = label,
		Billboard = billboard,
		Open = false,
		Angle = angle,
	}
	angle.Changed:Connect(function()
		applyAngle(view)
	end)
	-- Con StreamingEnabled el cofre puede salir y volver a entrar (otra copia): se suelta.
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil and views[chestId] == view then
			views[chestId] = nil
		end
	end)
	views[chestId] = view
	setOpen(view, remaining(chestId) > 0, false)
end

local function blessingText(blessings: any): string
	local parts = {}
	if typeof(blessings) == "table" then
		for blessingId, count in blessings do
			local def = AdventureConfig.Blessings[blessingId]
			if def then
				table.insert(parts, (if typeof(count) == "number" and count > 1 then count .. "× " else "") .. def.Icon .. " " .. def.DisplayName)
			end
		end
	end
	table.sort(parts)
	return table.concat(parts, " + ")
end

local function refreshAll()
	for chestId, view in views do
		local left = remaining(chestId)
		local open = left > 0
		if open ~= view.Open then
			setOpen(view, open, true)
		end
		if open then
			view.Label.Text = "⏳ " .. formatWait(left)
		end
	end
end

function ChestController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local stateRemote = remotes:WaitForChild(Constants.Remotes.ChestState) :: RemoteEvent
	local resultRemote = remotes:WaitForChild(Constants.Remotes.ChestResult) :: RemoteEvent
	local requestRemote = remotes:WaitForChild(Constants.Remotes.RequestChests) :: RemoteEvent

	stateRemote.OnClientEvent:Connect(function(state: any, serverNow: any)
		if typeof(state) ~= "table" or typeof(serverNow) ~= "number" then
			return
		end
		table.clear(deadlines)
		for chestId, readyAt in state do
			if typeof(chestId) == "string" and typeof(readyAt) == "number" and readyAt > serverNow then
				deadlines[chestId] = os.clock() + (readyAt - serverNow)
			end
		end
		refreshAll()
	end)

	resultRemote.OnClientEvent:Connect(function(success: any, code: any, chestId: any, detail: any)
		local chest = ChestConfig.get(chestId)
		if not chest then
			return
		end
		if success then
			local view = views[chestId]
			if view then
				local sparkles = view.Body:FindFirstChild("Sparkles")
				if sparkles and sparkles:IsA("ParticleEmitter") then
					sparkles:Emit(30)
				end
			end
			Juice.sound(Juice.Sounds.HatchRare)
			local parts = { "📦 " .. chest.Name }
			if typeof(detail) == "table" then
				if typeof(detail.Energy) == "number" then
					table.insert(parts, "+" .. formatNumber(detail.Energy) .. " ⚡")
				end
				local blessings = blessingText(detail.Blessings)
				if blessings ~= "" then
					table.insert(parts, blessings .. " (actívala en 🧿 Amuletos)")
				end
				if typeof(detail.Opened) == "number" and typeof(detail.Total) == "number" then
					table.insert(parts, ("%d/%d cofres"):format(detail.Opened, detail.Total))
				end
			end
			Toasts.show(table.concat(parts, "  ·  "), { Color = THEME.Gold, Duration = 5 })
		elseif code == Codes.ChestCooldown then
			local wait = if typeof(detail) == "table" and typeof(detail.ReadyAt) == "number" then remaining(chestId) else 0
			Toasts.show(("Este cofre ya está abierto. Vuelve en %s"):format(formatWait(wait)), { Color = THEME.Text, Key = "ChestWait" })
		elseif code == Codes.NotReady then
			Toasts.show("Cargando tus datos… prueba en un momento", { Color = THEME.Text, Key = "ChestWait" })
		end
	end)

	-- Los cofres aparecen cuando el servidor termina de construir la naturaleza.
	task.spawn(function()
		local folder = Workspace:WaitForChild("Chests")
		for _, model in folder:GetChildren() do
			if model:IsA("Model") then
				task.spawn(attach, model)
			end
		end
		folder.ChildAdded:Connect(function(model)
			if model:IsA("Model") then
				task.spawn(attach, model)
			end
		end)
		requestRemote:FireServer()
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			refreshAll()
		end
	end)
end

return ChestController
