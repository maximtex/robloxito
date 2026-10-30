-- WaveService · Altar: el altar y el círculo de cada sitio (construcción).
-- Parte de WaveService (ver WaveService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WaveConfig = require(Shared.Config.WaveConfig)
local StudFloor = require(Shared.Util.StudFloor)
local PartFactory = require(script.Parent.Parent.Parent.Util.PartFactory)
local StudProps = require(script.Parent.Parent.Parent.Util.StudProps)
local Types = require(script.Parent.Types)
type Place = Types.Place

local ctx: any -- tabla de estado compartida (la crea WaveService/init.luau)
local GROUND: any

-- Funciones de las otras partes
local function tryStart(...) return ctx.tryStart(...) end

-- Altar y círculo -----------------------------------------------------------------------

local function label(parent: Instance, position: UDim2, size: UDim2, color: Color3, text: string, stroke: number): TextLabel
	local textLabel = Instance.new("TextLabel")
	textLabel.Position = position
	textLabel.Size = size
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextScaled = true
	textLabel.TextColor3 = color
	textLabel.Text = text
	textLabel.Parent = parent
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.fromRGB(43, 29, 63)
	outline.Thickness = stroke
	outline.Parent = textLabel
	return textLabel
end

-- Cara de arriba del suelo en (x, z) del mundo (los caminos sobresalen: StudFloor.raiseAt).
local function floorAt(x: number, z: number): number
	return GROUND + StudFloor.BaseTop + StudFloor.raiseAt(x, z)
end

local function buildPlace(info: Place, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "WavePedestal_" .. info.Id
	model:SetAttribute("Place", info.Id)
	local center = info.Center
	local ground = center.Y
	local stone = StudProps.Colors.Stone
	local rune = Color3.fromRGB(255, 140, 70)
	local area = WaveConfig.Place.AreaRadius

	-- Altar en el centro, en bloques con studs como el spawn (base baja: los enemigos y los
	-- jugadores pasan por encima sin tropezar) con un marco de neón encima de la base
	local at = CFrame.new(center.X, ground, center.Z)
	StudProps.block(model, "Base", Vector3.new(10, 0.4, 10), at * CFrame.new(0, 0.2, 0), stone, true)
	for index = 0, 3 do
		local ring = StudProps.glow(model, if index == 0 then "Ring" else "Ring" .. index + 1, Vector3.new(8.4, 0.1, 0.5),
			at * CFrame.Angles(0, math.rad(index * 90), 0) * CFrame.new(0, 0.45, -4.2), rune)
		ring.Transparency = 0.2
	end
	local column = StudProps.block(model, "Column", Vector3.new(2.6, 5, 2.6), at * CFrame.new(0, 2.9, 0), stone, true)
	StudProps.block(model, "Cap", Vector3.new(3.4, 0.6, 3.4), at * CFrame.new(0, 5.7, 0), StudProps.Colors.StoneDark, true)
	local crystal = PartFactory.part(model, "Crystal", {
		Size = Vector3.new(2.4, 3.6, 2.4),
		CFrame = CFrame.new(center.X, ground + 7.4, center.Z) * CFrame.Angles(0, math.rad(45), math.rad(12)),
		Color = rune,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	local light = Instance.new("PointLight")
	light.Color = rune
	light.Range = 24
	light.Brightness = 2
	light.Shadows = false
	light.Parent = crystal
	-- Columna de luz: se ve desde todo el pueblo (y desde el punto de aparición)
	local beam = PartFactory.verticalCylinder(model, "LightBeam", Vector3.new(center.X, ground + 39, center.Z), 62, 2.6, rune, Enum.Material.Neon, false)
	beam.Transparency = 0.45
	beam.CastShadow = false

	-- Borde del círculo en el suelo: aquí dentro se juega (cada losa, a la altura del suelo
	-- que pisa: puede cruzar un camino)
	local tiles = 32
	for index = 1, tiles do
		local angle = (index / tiles) * math.pi * 2
		local tx, tz = center.X + math.cos(angle) * area, center.Z + math.sin(angle) * area
		local position = Vector3.new(tx, floorAt(tx, tz), tz)
		local tile = PartFactory.part(model, "EdgeRune" .. index, {
			Size = Vector3.new(1.4, 0.2, 3),
			CFrame = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)) * CFrame.new(0, 0.12, 0),
			Color = rune,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		tile.Transparency = 0.15
		tile.CastShadow = false
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WavePrompt"
	prompt.ActionText = "Jugar oleadas"
	prompt.ObjectText = "⚔ " .. tostring((WaveConfig.Arenas[info.ArenaId] or {}).DisplayName or "Oleadas")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = WaveConfig.Place.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = column
	prompt.Triggered:Connect(function(player: Player)
		tryStart(player, info.Id)
	end)

	-- Cartel flotante: qué es, cómo empezar y lo que pasa
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WaveSign"
	billboard.Size = UDim2.fromOffset(360, 112)
	billboard.StudsOffset = Vector3.new(0, 5.5, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 260
	billboard.Adornee = crystal
	label(billboard, UDim2.fromScale(0, 0), UDim2.new(1, 0, 0.46, 0), Color3.fromRGB(255, 214, 120), if info.Practice then "⚔ PRÁCTICA" else "⚔ OLEADAS", 3)
	info.StatusLabel = label(billboard, UDim2.fromScale(0, 0.48), UDim2.new(1, 0, 0.3, 0), Color3.new(1, 1, 1), "Pulsa E para jugar", 2)
	info.InfoLabel = label(billboard, UDim2.fromScale(0.05, 0.8), UDim2.new(0.9, 0, 0.2, 0), Color3.fromRGB(255, 236, 200), "", 1.5)
	billboard.Parent = crystal

	model.Parent = parent
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.buildPlace = buildPlace
	context.floorAt = floorAt
end

function Part.link(context: any)
	GROUND = context.GROUND
end

return Part
