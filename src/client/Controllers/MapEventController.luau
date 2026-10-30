-- Eventos del mapa en el cliente (solo avisos; MapEventService decide todo):
-- - Al empezar: aviso grande con el evento y la zona (tócalo para abrir 🗺️ Viajar) y una
--   columna de luz con su icono y la cuenta atrás en el sitio, que se ve desde lejos.
-- - Durante: cuántos bichos quedan (invasión) y las gemas que recoges (lluvia).
-- - Al acabar: el premio si estabas ahí, o que se retiraron / se escapó.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local formatNumber = require(Shared.Util.FormatNumber)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)

local MapEventController = {}

local GOLD = Color3.fromRGB(255, 206, 84)
local GREEN = Color3.fromRGB(150, 236, 120)
local MUTED = Color3.fromRGB(196, 196, 206)
local BEAM_COLORS = {
	Invasion = Color3.fromRGB(255, 96, 70),
	TreasureGoblin = Color3.fromRGB(255, 206, 60),
	DiamondRain = Color3.fromRGB(110, 236, 255),
}

local beacon: Model? = nil
local beaconId: number? = nil
local countdown: TextLabel? = nil
local endsAt = 0

local function clearBeacon()
	if beacon then
		beacon:Destroy()
	end
	beacon, beaconId, countdown = nil, nil, nil
end

-- Columna de luz con el icono y la cuenta atrás (solo en este cliente)
local function placeBeacon(data: any)
	clearBeacon()
	if typeof(data.Position) ~= "Vector3" then
		return
	end
	local color = BEAM_COLORS[data.Kind] or GOLD
	local model = Instance.new("Model")
	model.Name = "MapEventBeacon"
	local beam = Instance.new("Part")
	beam.Name = "Columna"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Transparency = 0.45
	beam.Size = Vector3.new(3, 90, 3)
	beam.CFrame = CFrame.new(data.Position + Vector3.new(0, 45, 0))
	beam.Parent = model
	local anchor = Instance.new("Part")
	anchor.Name = "Cartel"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(data.Position + Vector3.new(0, 14, 0))
	anchor.Parent = model
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 70)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 600
	billboard.Parent = anchor
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.6, 0)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = color
	title.Text = ("%s %s"):format(tostring(data.Icon or ""), tostring(data.Name or ""))
	title.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(16, 14, 18)
	stroke.Parent = title
	local timer = Instance.new("TextLabel")
	timer.BackgroundTransparency = 1
	timer.Position = UDim2.fromScale(0, 0.6)
	timer.Size = UDim2.new(1, 0, 0.4, 0)
	timer.Font = Enum.Font.FredokaOne
	timer.TextScaled = true
	timer.TextColor3 = Color3.new(1, 1, 1)
	timer.Parent = billboard
	local timerStroke = stroke:Clone()
	timerStroke.Thickness = 2
	timerStroke.Parent = timer
	model.Parent = Workspace
	beacon, beaconId, countdown = model, data.Id, timer
	endsAt = tonumber(data.EndsAt) or 0
end

local function onEvent(data: any)
	if type(data) ~= "table" or type(data.State) ~= "string" then
		return
	end
	local state = data.State
	if state == "Start" then
		placeBeacon(data)
		Toasts.show(tostring(data.Text or "") .. "  Toca para ir con 🗺️ Viajar.", {
			Title = ("%s %s"):format(tostring(data.Icon or ""), string.upper(tostring(data.Name or "Evento"))),
			Color = BEAM_COLORS[data.Kind] or GOLD,
			Key = "MapEvent",
			Duration = 9,
			OnClick = function()
				PanelManager.open("Travel")
			end,
		})
	elseif state == "Progress" then
		Toasts.show(("%s %s: quedan %d"):format(tostring(data.Icon or ""), tostring(data.Name or ""), tonumber(data.Left) or 0), { Color = MUTED, Key = "MapEventProgress", Style = "Line" })
	elseif state == "Gem" then
		Toasts.show(("💎 Gema %d/%d  +%s 💎  +%s 💰"):format(tonumber(data.Count) or 0, tonumber(data.Max) or 0, formatNumber(tonumber(data.Diamonds) or 0), formatNumber(tonumber(data.Money) or 0)), { Color = BEAM_COLORS.DiamondRain, Key = "MapEventGem", Style = "Line" })
	elseif state == "Reward" then
		Toasts.show(("+%s 💰  +%s 💎"):format(formatNumber(tonumber(data.Money) or 0), formatNumber(tonumber(data.Diamonds) or 0)), {
			Title = ("🏆 ¡%s superada!"):format(tostring(data.Name or "Evento")),
			Color = GREEN,
			Key = "MapEventReward",
		})
	elseif state == "End" then
		if beaconId == data.Id then
			clearBeacon()
		end
		if data.Success ~= true then
			local text = if data.Kind == "TreasureGoblin" then "💨 El goblin del tesoro se escapó." elseif data.Kind == "Invasion" then "La invasión se retiró." else "Se acabó el evento."
			Toasts.show(text, { Color = MUTED, Key = "MapEvent", Style = "Line" })
		end
	end
end

function MapEventController.start()
	local remotes = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName)
	local remote = remotes:WaitForChild(Constants.Remotes.MapEvent) :: RemoteEvent
	remote.OnClientEvent:Connect(onEvent)
	-- Cuenta atrás del cartel
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.5 or not countdown then
			return
		end
		accumulator = 0
		local left = math.max(0, math.floor(endsAt - Workspace:GetServerTimeNow()))
		countdown.Text = ("%d:%02d"):format(math.floor(left / 60), left % 60)
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		-- (la columna sigue: es del mundo, no del personaje)
	end)
end

return MapEventController
