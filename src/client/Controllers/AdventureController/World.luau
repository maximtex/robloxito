-- AdventureController · World: objetos perdidos en el mundo y carteles, avisos y giro de los personajes.
-- Parte de AdventureController (ver AdventureController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AdventureConfig = require(Shared.Config.AdventureConfig)
local AdventureLogic = require(Shared.AdventureLogic)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)

local ctx: any -- tabla de estado compartida (la crea AdventureController/init.luau)
local ANIMATE_DISTANCE: any
local COLORS: any
local FACE_DISTANCE: any
local FONTS: any
local ITEM_FLOAT: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function npcState(...) return ctx.npcState(...) end

-- Objetos perdidos (solo en este cliente) ---------------------------------------------------------

local itemVisuals: { [string]: { Model: Model, Base: Vector3, Phase: number } } = {}

local function itemWorldPosition(itemId: string): Vector3?
	local info = ReplicatedStorage:FindFirstChild("AdventureWorld")
	local value = info and info:GetAttribute("Item_" .. itemId)
	return if typeof(value) == "Vector3" then value else nil
end

local function localPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	if shape then
		part.Shape = shape
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- Forma de cada tipo de objeto, alrededor de `center` (todo anclado; se mueve con PivotTo).
local SHAPES = {}

function SHAPES.Dew(model: Model, center: CFrame, kind: any)
	-- Flor de cinco pétalos de cara al jugador, con tallo y hoja.
	local face = center * CFrame.Angles(math.rad(-70), 0, 0)
	for index = 1, 5 do
		local angle = math.rad(index * 72)
		localPart(model, "Petal" .. index, Vector3.new(0.62, 0.62, 0.62), face * CFrame.new(math.cos(angle) * 0.42, 0, math.sin(angle) * 0.42), kind.Color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	localPart(model, "Center", Vector3.new(0.46, 0.46, 0.46), face * CFrame.new(0, 0.12, 0), Color3.fromRGB(255, 226, 110), Enum.Material.Neon, Enum.PartType.Ball)
	localPart(model, "Stem", Vector3.new(1.2, 0.12, 0.12), center * CFrame.new(0, -0.75, 0.15) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 170, 80), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	localPart(model, "Leaf", Vector3.new(0.6, 0.08, 0.3), center * CFrame.new(0.25, -0.9, 0.15) * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(100, 190, 90), Enum.Material.SmoothPlastic)
end

function SHAPES.Arrow(model: Model, center: CFrame, kind: any)
	local tilt = center * CFrame.Angles(0, 0, math.rad(35))
	localPart(model, "Shaft", Vector3.new(2.4, 0.14, 0.14), tilt, Color3.fromRGB(150, 104, 62), Enum.Material.Wood, Enum.PartType.Cylinder)
	localPart(model, "Tip", Vector3.new(0.4, 0.3, 0.3), tilt * CFrame.new(1.3, 0, 0) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(200, 204, 214), Enum.Material.Metal)
	for side = -1, 1, 2 do
		localPart(model, "Fletch" .. side, Vector3.new(0.5, 0.06, 0.32), tilt * CFrame.new(-1.0, side * 0.1, 0) * CFrame.Angles(side * math.rad(30), 0, 0), kind.Color, Enum.Material.Neon)
	end
end

function SHAPES.Map(model: Model, center: CFrame, kind: any)
	localPart(model, "Paper", Vector3.new(1.3, 0.08, 1.0), center * CFrame.Angles(math.rad(-60), math.rad(15), 0), kind.Color, Enum.Material.SmoothPlastic)
	localPart(model, "Mark", Vector3.new(0.3, 0.1, 0.3), center * CFrame.Angles(math.rad(-60), math.rad(15), 0) * CFrame.new(0.2, 0.02, 0.1), Color3.fromRGB(214, 70, 60), Enum.Material.Neon)
end

function SHAPES.Ember(model: Model, center: CFrame, kind: any)
	-- Piedra oscura con grietas de lava y un corazón brillante.
	localPart(model, "Rock", Vector3.new(1.1, 0.9, 1.0), center * CFrame.Angles(0.4, 0.7, 0.2), Color3.fromRGB(64, 50, 50), Enum.Material.Basalt)
	localPart(model, "Core", Vector3.new(0.75, 0.75, 0.75), center * CFrame.new(0, 0.1, 0), kind.Color, Enum.Material.Neon, Enum.PartType.Ball)
	for index = 1, 3 do
		local angle = math.rad(index * 120)
		localPart(model, "Crack" .. index, Vector3.new(0.12, 0.7, 0.12), center * CFrame.Angles(0, angle, math.rad(35)) * CFrame.new(0, 0, -0.52), kind.Glow, Enum.Material.Neon)
	end
end

function SHAPES.Shard(model: Model, center: CFrame, kind: any)
	localPart(model, "Crystal", Vector3.new(0.6, 1.4, 0.6), center * CFrame.Angles(0, math.rad(45), math.rad(10)), kind.Color, Enum.Material.Neon)
	localPart(model, "Small", Vector3.new(0.35, 0.8, 0.35), center * CFrame.new(0.45, -0.3, 0.1) * CFrame.Angles(0, 0, math.rad(-30)), kind.Glow, Enum.Material.Neon)
end

local function makeItem(itemId: string, ground: Vector3): Model
	local item = AdventureConfig.Items[itemId]
	local kind = AdventureConfig.ItemKinds[item.Kind]
	local model = Instance.new("Model")
	model.Name = itemId
	local center = CFrame.new(ground + Vector3.new(0, ITEM_FLOAT, 0))
	local anchor = localPart(model, "Anchor", Vector3.new(0.2, 0.2, 0.2), center, kind.Glow, Enum.Material.SmoothPlastic)
	anchor.Transparency = 1
	model.PrimaryPart = anchor
	local shape = SHAPES[item.Kind] or SHAPES.Shard
	shape(model, center, kind)
	-- Haz de luz para verlo de lejos
	local beam = localPart(model, "Beam", Vector3.new(26, 0.35, 0.35), CFrame.new(ground + Vector3.new(0, 13, 0)) * CFrame.Angles(0, 0, math.rad(90)), kind.Glow, Enum.Material.Neon, Enum.PartType.Cylinder)
	beam.Transparency = 0.78
	local light = Instance.new("PointLight")
	light.Color = kind.Glow
	light.Range = 9
	light.Brightness = 1
	light.Shadows = false
	light.Parent = anchor
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 5
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(0.5, 1.2)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new(0.22, 0)
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(kind.Glow)
	sparkle.Parent = anchor
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(44, 44)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.MaxDistance = 160
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor
	UiKit.text(billboard, "Icon", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = kind.Icon,
	})
	return model
end

local function burstAt(position: Vector3, color: Color3)
	local folder = ctx.itemsFolder
	if not folder then
		return
	end
	local part = localPart(folder, "Burst", Vector3.new(0.2, 0.2, 0.2), CFrame.new(position), color, Enum.Material.SmoothPlastic)
	part.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(color)
	emitter.Parent = part
	emitter:Emit(30)
	local ring = localPart(folder, "Ring", Vector3.new(0.2, 1, 1), CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.Transparency = 0.2
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.1, 8, 8), Transparency = 1 }):Play()
	task.delay(1.2, function()
		part:Destroy()
		ring:Destroy()
	end)
end

-- Muestra los objetos pendientes y quita (con estallido) los recogidos.
local function syncItems(pending: { string }, found: { [string]: boolean })
	local folder = ctx.itemsFolder
	if not folder then
		return
	end
	local wanted = {}
	for _, itemId in pending do
		wanted[itemId] = true
		if not itemVisuals[itemId] then
			local ground = itemWorldPosition(itemId)
			if ground then
				local model = makeItem(itemId, ground)
				model.Parent = folder
				itemVisuals[itemId] = { Model = model, Base = ground + Vector3.new(0, ITEM_FLOAT, 0), Phase = math.random() * math.pi * 2 }
			end
		end
	end
	for itemId, visual in itemVisuals do
		if not wanted[itemId] then
			if found[itemId] then
				local kind = AdventureConfig.ItemKinds[AdventureConfig.Items[itemId].Kind]
				burstAt(visual.Base, kind.Glow)
			end
			visual.Model:Destroy()
			itemVisuals[itemId] = nil
		end
	end
end

-- Personajes: nombre, aviso y giro hacia el jugador ------------------------------------------------

type NpcView = { Model: Model?, Billboard: BillboardGui, Indicator: TextLabel, Home: CFrame?, Yaw: number?, IndicatorTween: Tween? }

local npcViews: { [string]: NpcView } = {}

local function buildNpcBillboard(npcId: string, playerGui: PlayerGui): NpcView
	local npc = AdventureConfig.Npcs[npcId]
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Npc_" .. npcId
	billboard.Size = UDim2.fromOffset(220, 110)
	billboard.StudsOffset = Vector3.new(0, 2.9, 0)
	billboard.MaxDistance = 80
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = false
	billboard.ResetOnSpawn = false
	billboard.Enabled = false
	billboard.Parent = playerGui
	local indicator = UiKit.text(billboard, "Indicator", {
		Size = UDim2.new(1, 0, 0, 56),
		Font = FONTS.Display,
		TextSize = 54,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.fromRGB(40, 28, 10),
	})
	UiKit.text(billboard, "Name", {
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 26),
		Font = FONTS.Display,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Text = npc.DisplayName,
	})
	UiKit.text(billboard, "Title", {
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 0, 18),
		Font = FONTS.Body,
		TextSize = 15,
		TextColor3 = THEME.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		Text = npc.Title,
	})
	return { Model = nil, Billboard = billboard, Indicator = indicator, Home = nil, Yaw = nil, IndicatorTween = nil }
end

local function refreshIndicator(npcId: string)
	local view = npcViews[npcId]
	if not view then
		return
	end
	local st = npcState(npcId)
	local text, color = "", COLORS.Active
	if st.Status == "Offer" then
		text, color = "!", COLORS.Offer
	elseif st.Status == "Ready" then
		text, color = "?", COLORS.Ready
	elseif st.Status == "Active" then
		text, color = "…", COLORS.Active
	end
	view.Indicator.Text = text
	view.Indicator.TextColor3 = color
	view.Indicator.TextSize = if st.Status == "Active" then 40 else 54
	if view.IndicatorTween then
		view.IndicatorTween:Cancel()
		view.IndicatorTween = nil
	end
	view.Indicator.Position = UDim2.new()
	if st.Status == "Offer" or st.Status == "Ready" then
		local tween = TweenService:Create(view.Indicator, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromOffset(0, -8) })
		tween:Play()
		view.IndicatorTween = tween
	end
end

local function attachModel(npcId: string, model: Model)
	local view = npcViews[npcId]
	if not view then
		return
	end
	view.Model = model
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		view.Home = root.CFrame
		local _, yaw = root.CFrame:ToOrientation()
		view.Yaw = yaw
	end
	view.Billboard.Adornee = model:FindFirstChild("Head") or root
	view.Billboard.Enabled = true
end

local function detachModel(npcId: string)
	local view = npcViews[npcId]
	if view then
		view.Model = nil
		view.Billboard.Adornee = nil
		view.Billboard.Enabled = false
	end
end

local function watchNpcs(playerGui: PlayerGui)
	for _, npcId in AdventureLogic.npcOrder() do
		npcViews[npcId] = buildNpcBillboard(npcId, playerGui)
		refreshIndicator(npcId)
	end
	task.spawn(function()
		local folder = Workspace:WaitForChild("Npcs", 60)
		if not folder then
			return
		end
		local function added(child: Instance)
			if child:IsA("Model") and npcViews[child.Name] then
				-- Con streaming el modelo llega entero (Atomic); su raíz puede tardar un instante.
				if not child.PrimaryPart then
					child:WaitForChild("Root", 5)
				end
				attachModel(child.Name, child)
			end
		end
		for _, child in folder:GetChildren() do
			task.spawn(added, child)
		end
		folder.ChildAdded:Connect(added)
		folder.ChildRemoved:Connect(function(child)
			if npcViews[child.Name] and npcViews[child.Name].Model == child then
				detachModel(child.Name)
			end
		end)
	end)
end

local function angleLerp(from: number, to: number, alpha: number): number
	local delta = (to - from + math.pi) % (2 * math.pi) - math.pi
	return from + delta * alpha
end

local function animate(dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local me = if root and root:IsA("BasePart") then root.Position else nil
	local camera = Workspace.CurrentCamera
	local clock = os.clock()
	for _, view in npcViews do
		local model = view.Model
		if model and model.Parent and view.Home and view.Yaw then
			local home = view.Home
			if camera and (camera.CFrame.Position - home.Position).Magnitude < ANIMATE_DISTANCE then
				local _, homeYaw = home:ToOrientation()
				local target = homeYaw
				if me then
					local offset = Vector3.new(me.X - home.Position.X, 0, me.Z - home.Position.Z)
					if offset.Magnitude < FACE_DISTANCE and offset.Magnitude > 0.5 then
						target = math.atan2(-offset.X, -offset.Z)
					end
				end
				view.Yaw = angleLerp(view.Yaw, target, math.clamp(dt * 5, 0, 1))
				local bob = math.sin(clock * 2.2) * 0.05
				model:PivotTo(CFrame.new(home.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, view.Yaw, 0))
			end
		end
	end
	for _, visual in itemVisuals do
		local spin = CFrame.Angles(0, clock * 1.6 + visual.Phase, 0)
		visual.Model:PivotTo(CFrame.new(visual.Base + Vector3.new(0, math.sin(clock * 2 + visual.Phase) * 0.35, 0)) * spin)
	end
end

-- Controlador ------------------------------------------------------------------------------------

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.animate = animate
	context.npcViews = npcViews
	context.refreshIndicator = refreshIndicator
	context.syncItems = syncItems
	context.watchNpcs = watchNpcs
end

function Part.link(context: any)
	ANIMATE_DISTANCE = context.ANIMATE_DISTANCE
	COLORS = context.COLORS
	FACE_DISTANCE = context.FACE_DISTANCE
	FONTS = context.FONTS
	ITEM_FLOAT = context.ITEM_FLOAT
	THEME = context.THEME
	player = context.player
end

return Part
