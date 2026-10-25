-- Cofre de victoria de las mazmorras (WaveService "Chest": ya pagado). Aparece delante del
-- altar solo para ti: cae del techo, brilla y se abre al acercarte (o solo a los pocos
-- segundos) con una lluvia de monedas, lo que da (💰 y, si toca, una poción) y un aviso.
-- Luego se va. Solo decorativo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared.Config.ItemConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local WaveFx = require(script.Parent.WaveFx)

local WaveChest = {}

local player = Players.LocalPlayer
local RGB = Color3.fromRGB
local WOOD = { RGB(150, 92, 44), RGB(118, 70, 32) }
local GOLD = RGB(255, 206, 84)
local OPEN_DISTANCE = 10
local AUTO_OPEN = 6 -- segundos
local LIFETIME = 12

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Plastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- data: { Position (suelo), Facing, Money, Potion, Arena }
function WaveChest.show(data: any)
	if type(data) ~= "table" or typeof(data.Position) ~= "Vector3" then
		return
	end
	local money = tonumber(data.Money) or 0
	local potion = if type(data.Potion) == "string" then ItemConfig.Potions[data.Potion] else nil
	local facing = if typeof(data.Facing) == "Vector3" and data.Facing.Magnitude > 0.1 then data.Facing.Unit else Vector3.new(0, 0, -1)
	local ground = data.Position
	local base = CFrame.lookAt(ground, ground + facing) -- -Z local: el frente del cofre

	local model = Instance.new("Model")
	model.Name = "CofreMazmorra"
	-- Caja (las piezas se ponen respecto a `base` y luego todo cae desde arriba)
	local pieces: { { Part: BasePart, Offset: CFrame } } = {}
	local function add(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Part
		local p = part(model, name, size, base * offset, color, material)
		table.insert(pieces, { Part = p, Offset = offset })
		return p
	end
	add("Caja", Vector3.new(4.4, 2.4, 3), CFrame.new(0, 1.2, 0), WOOD[1], Enum.Material.Wood)
	add("BandaIzq", Vector3.new(0.4, 2.5, 3.1), CFrame.new(-1.4, 1.2, 0), GOLD, Enum.Material.Metal)
	add("BandaDer", Vector3.new(0.4, 2.5, 3.1), CFrame.new(1.4, 1.2, 0), GOLD, Enum.Material.Metal)
	local glow = add("Brillo", Vector3.new(3.9, 0.2, 2.5), CFrame.new(0, 2.35, 0), RGB(255, 236, 140), Enum.Material.Neon)
	glow.Transparency = 1
	-- Tapa: gira sobre la bisagra de atrás (+Z local)
	local hinge = CFrame.new(0, 2.4, 1.5)
	local lidOffset = hinge * CFrame.new(0, 0.55, -1.5)
	local lid = add("Tapa", Vector3.new(4.5, 1.1, 3.1), lidOffset, WOOD[2], Enum.Material.Wood)
	local lidBand = add("TapaBanda", Vector3.new(0.4, 1.15, 3.15), lidOffset, GOLD, Enum.Material.Metal)
	local lock = add("Cerradura", Vector3.new(0.9, 1, 0.3), CFrame.new(0, 2.3, -1.6), GOLD, Enum.Material.Metal)
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 14
	light.Brightness = 1.5
	light.Shadows = false
	light.Parent = lock
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(GOLD)
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Rate = 10
	sparkle.Speed = NumberRange.new(1, 2.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Parent = lock
	-- Cartel encima
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Cartel"
	billboard.Size = UDim2.fromOffset(260, 70)
	billboard.StudsOffset = Vector3.new(0, 4.5, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 120
	billboard.AlwaysOnTop = true
	billboard.Adornee = lock
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.TextStrokeColor3 = RGB(43, 29, 63)
	label.TextStrokeTransparency = 0
	label.RichText = true
	label.Text = "🎁 ¡COFRE!"
	label.Parent = billboard
	billboard.Parent = lock
	local folder = Workspace:FindFirstChild("WaveChestFx")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "WaveChestFx"
		folder.Parent = Workspace
	end
	model.Parent = folder

	local function placeAll(lift: number, lidAngle: number)
		local origin = base + Vector3.new(0, lift, 0)
		for _, piece in pieces do
			local offset = piece.Offset
			if piece.Part == lid or piece.Part == lidBand then
				offset = hinge * CFrame.Angles(math.rad(lidAngle), 0, 0) * CFrame.new(0, 0.55, -1.5)
			end
			piece.Part.CFrame = origin * offset
		end
	end

	-- Cae (con un pequeño rebote), espera y se abre
	local spawnedAt = os.clock()
	local opened: number? = nil
	local landed = false
	WaveFx.sound("Chime", 0.8)
	local function open()
		if opened then
			return
		end
		opened = os.clock()
		glow.Transparency = 0.1
		sparkle.Rate = 30
		local coins = Instance.new("ParticleEmitter")
		coins.Color = ColorSequence.new(GOLD, RGB(255, 240, 160))
		coins.LightEmission = 0.6
		coins.Size = NumberSequence.new(0.45)
		coins.Lifetime = NumberRange.new(1, 1.6)
		coins.Speed = NumberRange.new(12, 20)
		coins.SpreadAngle = Vector2.new(30, 30)
		coins.Acceleration = Vector3.new(0, -35, 0)
		coins.EmissionDirection = Enum.NormalId.Top
		coins.Rate = 0
		coins.Parent = glow
		coins:Emit(45)
		local lines = {}
		if money > 0 then
			table.insert(lines, ("+%s 💰"):format(formatNumber(money)))
		end
		if potion then
			table.insert(lines, ("%s %s"):format(potion.Icon, potion.DisplayName))
		end
		label.Text = table.concat(lines, "\n")
		billboard.Size = UDim2.fromOffset(260, if #lines > 1 then 96 else 60)
		WaveFx.sound("Victory", 1.15)
		WaveFx.confetti(30)
		Toasts.show(("🎁 Cofre de %s: %s"):format(tostring(data.Arena or "la mazmorra"), table.concat(lines, " · ")), { Color = GOLD, Key = "WaveChest" })
	end

	local connection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local t = now - spawnedAt
		-- Caída: 0.5 s desde 12 studs, rebote corto
		local lift = 0
		if t < 0.5 then
			local k = t / 0.5
			lift = 12 * (1 - k * k)
		elseif t < 0.75 then
			local k = (t - 0.5) / 0.25
			lift = math.sin(k * math.pi) * 0.8
		elseif not landed then
			landed = true
			WaveFx.shake(0.2)
		end
		local lidAngle = 0
		if opened then
			lidAngle = math.min(1, (now - opened) / 0.35) * 105
		elseif landed then
			local at = rootPosition()
			if t >= AUTO_OPEN or (at and (at - ground).Magnitude <= OPEN_DISTANCE) then
				open()
			end
		end
		placeAll(lift, lidAngle)
		if t >= LIFETIME then
			connection:Disconnect()
			model:Destroy()
		end
	end)
end

return WaveChest
