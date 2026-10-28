-- AbilityController · ReactionsAndStatus: efectos de combos elementales (REACTION_FX) y auras/marcas de estado sobre los enemigos.
-- Parte de AbilityController (ver AbilityController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityConfig = require(Shared.Config.AbilityConfig)
local CombatController = require(script.Parent.Parent.CombatController)

local ctx: any -- tabla de estado compartida (la crea AbilityController/init.luau)
local FONTS: any
local THEME: any

-- Funciones de las otras partes
local function abilityColor(...) return ctx.abilityColor(...) end
local function addShake(...) return ctx.addShake(...) end
local function bolt(...) return ctx.bolt(...) end
local function burst(...) return ctx.burst(...) end
local function flashLight(...) return ctx.flashLight(...) end
local function flatRing(...) return ctx.flatRing(...) end
local function floatingText(...) return ctx.floatingText(...) end
local function fxPart(...) return ctx.fxPart(...) end
local function healNumbers(...) return ctx.healNumbers(...) end
local function iceShards(...) return ctx.iceShards(...) end
local function kickFov(...) return ctx.kickFov(...) end
local function screenFlash(...) return ctx.screenFlash(...) end
local function soundAt(...) return ctx.soundAt(...) end
local function vines(...) return ctx.vines(...) end

-- Combos -----------------------------------------------------------------------------------

local REACTION_FX: { [string]: (any, Color3) -> () } = {}

function REACTION_FX.Electrocuted(event, color)
	if typeof(event.Hits) == "table" then
		for index, hit in event.Hits do
			if typeof(hit) == "table" and typeof(hit.Position) == "Vector3" then
				bolt(event.Center + Vector3.new(0, 3, 0), hit.Position, color, (index - 1) * 0.04)
			end
		end
	end
	burst(event.Center, "Spark", Color3.fromRGB(255, 250, 200), 30)
end

function REACTION_FX.Steam(event, color)
	burst(event.Center, "Steam", color, 40)
	flatRing(event.Center, (event.Radius or 8) * 2.2, Color3.new(1, 1, 1), 0.5, Enum.Material.Neon, 0.4)
end

function REACTION_FX.Frozen(event, color)
	-- Bloque de hielo alrededor del enemigo mientras dura la congelación.
	local seconds = AbilityConfig.Reactions.Frozen.StunSeconds
	local block = fxPart(Vector3.one, CFrame.new(event.Center) * CFrame.Angles(0, math.rad(math.random(0, 90)), 0), Color3.fromRGB(190, 236, 255), Enum.Material.Ice, 0.45)
	TweenService:Create(block, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(5, 6, 5) }):Play()
	TweenService:Create(block, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, seconds), { Transparency = 1 }):Play()
	Debris:AddItem(block, seconds + 0.4)
	iceShards(event.Center, 3, 8, 0.8)
	burst(event.Center, "Snow", color, 30)
end

function REACTION_FX.Wildfire(event, color)
	burst(event.Center, "Flame", color, 50, Vector3.new(0, 1, 0))
	flatRing(event.Center, (event.Radius or 10) * 2, color, 0.5, Enum.Material.Neon, 0.3)
end

function REACTION_FX.Melt(event, color)
	burst(event.Center, "Steam", Color3.fromRGB(255, 200, 160), 20)
	burst(event.Center, "Flame", color, 30, Vector3.new(0, 1, 0))
end

function REACTION_FX.Superconduct(event, color)
	flatRing(event.Center, (event.Radius or 8) * 2, color, 0.55, Enum.Material.Neon, 0.25)
	burst(event.Center, "Spark", color, 24)
end

function REACTION_FX.Bloom(event, color)
	burst(event.Center, "Leaf", color, 30)
	vines(event.Center, AbilityConfig.Reactions.Bloom.RootSeconds or 3, color)
end

function REACTION_FX.Eclipse(event, color)
	local sphere = fxPart(Vector3.one * 2, CFrame.new(event.Center + Vector3.new(0, 2, 0)), Color3.fromRGB(30, 16, 50), Enum.Material.Neon, 0.1, Enum.PartType.Ball)
	TweenService:Create(sphere, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * (event.Radius or 10) * 1.2, Color = color, Transparency = 1 }):Play()
	Debris:AddItem(sphere, 0.35)
	burst(event.Center, "Star", color, 40)
	flatRing(event.Center, (event.Radius or 10) * 2.2, color, 0.6, Enum.Material.Neon, 0.25)
end

function REACTION_FX.Swirl(event, color)
	local auraColor = abilityColor(event.Aura)
	local center = event.Center
	for index = 1, 3 do
		task.delay((index - 1) * 0.07, function()
			flatRing(center + Vector3.new(0, index * 0.6, 0), (event.Radius or 10) * (0.8 + index * 0.4), if index == 2 then auraColor else color, 0.45, Enum.Material.Neon, 0.35)
		end)
	end
	burst(center, "Wind", auraColor, 30, Vector3.new(0, 1, 0))
end

local function showReaction(event: any, isOwner: boolean)
	local reaction = typeof(event.Reaction) == "string" and AbilityConfig.Reactions[event.Reaction] or nil
	if not (reaction and typeof(event.Center) == "Vector3") then
		return
	end
	local color = reaction.Color
	floatingText(event.Center, reaction.Name, color)
	flashLight(event.Center + Vector3.new(0, 2, 0), color, 20, 0.45)
	local flavor = REACTION_FX[event.Reaction]
	if flavor then
		flavor(event, color)
	end
	soundAt(event.Center, AbilityConfig.Sounds.Reactions[event.Reaction] or AbilityConfig.Sounds.Reactions.Default)
	healNumbers(event.Healed, color)
	CombatController.showHits(event.Hits, color, isOwner, 1, 1.3)
	if isOwner then
		addShake(AbilityConfig.ReactionShake or 0.55)
		kickFov(4)
		screenFlash(color, 1)
	end
end

-- Estados y marcas sobre los enemigos --------------------------------------------------------

local STATUS_LOOKS: { [string]: { Color: Color3, Setup: (ParticleEmitter) -> () } } = {
	BurnUntil = {
		Color = Color3.fromRGB(255, 130, 50),
		Setup = function(e)
			e.Rate = 16
			e.Lifetime = NumberRange.new(0.4, 0.7)
			e.Speed = NumberRange.new(2, 4)
			e.Acceleration = Vector3.new(0, 6, 0)
			e.SpreadAngle = Vector2.new(40, 40)
			e.Size = NumberSequence.new(0.8, 0)
			e.Transparency = NumberSequence.new(0.2, 1)
			e.LightEmission = 1
		end,
	},
	SlowUntil = {
		Color = Color3.fromRGB(170, 230, 255),
		Setup = function(e)
			e.Rate = 10
			e.Lifetime = NumberRange.new(0.8, 1.2)
			e.Speed = NumberRange.new(0.5, 1.5)
			e.Acceleration = Vector3.new(0, -2, 0)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new(0.3, 0)
			e.Rotation = NumberRange.new(0, 360)
			e.LightEmission = 0.7
		end,
	},
	RootUntil = {
		Color = Color3.fromRGB(120, 214, 96),
		Setup = function(e)
			e.Rate = 8
			e.Lifetime = NumberRange.new(0.6, 1)
			e.Speed = NumberRange.new(1, 2)
			e.SpreadAngle = Vector2.new(180, 20)
			e.Size = NumberSequence.new(0.3, 0.05)
			e.Rotation = NumberRange.new(0, 360)
			e.RotSpeed = NumberRange.new(-120, 120)
			e.LightEmission = 0.2
		end,
	},
	StunUntil = {
		Color = Color3.fromRGB(255, 240, 120),
		Setup = function(e)
			e.Rate = 20
			e.Lifetime = NumberRange.new(0.15, 0.3)
			e.Speed = NumberRange.new(4, 8)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new(0.25, 0)
			e.LightEmission = 1
		end,
	},
	CurseUntil = {
		Color = Color3.fromRGB(150, 90, 230),
		Setup = function(e)
			e.Rate = 9
			e.Lifetime = NumberRange.new(0.8, 1.2)
			e.Speed = NumberRange.new(0.5, 1.5)
			e.Acceleration = Vector3.new(0, 3, 0)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new(0.7, 1.2)
			e.Transparency = NumberSequence.new(0.4, 1)
			e.LightEmission = 0.3
		end,
	},
}

-- Icono de la marca elemental sobre la barra de vida del enemigo.
local function refreshAura(model: Model, root: BasePart, now: number)
	local element = model:GetAttribute("Aura")
	local untilTime = model:GetAttribute("AuraUntil")
	local ability = typeof(element) == "string" and AbilityConfig.Abilities[element] or nil
	local active = ability ~= nil and typeof(untilTime) == "number" and untilTime > now
	local icon = root:FindFirstChild("AuraIcon") :: BillboardGui?
	if not active then
		if icon then
			icon:Destroy()
		end
		return
	end
	if not icon then
		local bar = root:FindFirstChild("HealthBar")
		local offset = if bar and bar:IsA("BillboardGui") then bar.StudsOffset else Vector3.new(0, 3, 0)
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "AuraIcon"
		billboard.Size = UDim2.fromOffset(30, 30)
		billboard.StudsOffset = offset + Vector3.new(0, 1.7, 0)
		billboard.LightInfluence = 0
		billboard.MaxDistance = 80
		local circle = Instance.new("Frame")
		circle.Name = "Circle"
		circle.Size = UDim2.fromScale(1, 1)
		circle.BackgroundColor3 = THEME.Panel
		circle.BackgroundTransparency = 0.15
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = circle
		local stroke = Instance.new("UIStroke")
		stroke.Name = "Ring"
		stroke.Thickness = 2
		stroke.Parent = circle
		local label = Instance.new("TextLabel")
		label.Name = "Icon"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = FONTS.Display
		label.TextScaled = true
		label.Parent = circle
		circle.Parent = billboard
		billboard.Parent = root
		icon = billboard
	end
	local circle = (icon :: BillboardGui):FindFirstChild("Circle") :: Frame
	local label = circle:FindFirstChild("Icon") :: TextLabel
	local ring = circle:FindFirstChild("Ring") :: UIStroke
	if label.Text ~= ability.Icon then
		label.Text = ability.Icon
		ring.Color = ability.Color
	end
	-- Parpadea cuando está a punto de acabarse.
	local remaining = untilTime - now
	circle.BackgroundTransparency = if remaining < 1.2 and math.floor(now * 6) % 2 == 0 then 0.6 else 0.15
end

local function refreshStatuses()
	local enemies = Workspace:FindFirstChild("Enemies")
	if not enemies then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for _, zoneFolder in enemies:GetChildren() do
		for _, model in zoneFolder:GetChildren() do
			local root = model:IsA("Model") and model:FindFirstChild("HumanoidRootPart")
			if not (root and root:IsA("BasePart")) then
				continue
			end
			for attribute, look in STATUS_LOOKS do
				local untilTime = model:GetAttribute(attribute)
				local active = typeof(untilTime) == "number" and untilTime > now
				local name = "Status_" .. attribute
				local existing = root:FindFirstChild(name)
				if active and not existing then
					local attachment = Instance.new("Attachment")
					attachment.Name = name
					local emitter = Instance.new("ParticleEmitter")
					look.Setup(emitter)
					emitter.Color = ColorSequence.new(look.Color:Lerp(Color3.new(1, 1, 1), 0.3), look.Color)
					emitter.Parent = attachment
					attachment.Parent = root
				elseif not active and existing then
					existing:Destroy()
				end
			end
			refreshAura(model :: Model, root, now)
		end
	end
end

local Part = { Api = {} }

function Part.install(context: any)
	ctx = context
	context.refreshStatuses = refreshStatuses
	context.showReaction = showReaction
end

function Part.link(context: any)
	FONTS = context.FONTS
	THEME = context.THEME
end

return Part
