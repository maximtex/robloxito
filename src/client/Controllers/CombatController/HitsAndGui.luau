-- CombatController · HitsAndGui: destello de enemigos, números de daño y monedas, limpieza y construcción del HUD.
-- Parte de CombatController (ver CombatController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local formatNumber = require(Shared.Util.FormatNumber)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local EnemyAnimator = require(script.Parent.Parent.EnemyAnimator)

local ctx: any -- tabla de estado compartida (la crea CombatController/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a CombatController)
local AUTO_OFF: any
local BOSS_ENRAGED_COLOR: any
local FONTS: any
local LAYOUT: any
local MAX_DAMAGE_NUMBERS: any
local POOL_PREFIX: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function arrowFx(...) return ctx.arrowFx(...) end
local function beamEffect(...) return ctx.beamEffect(...) end
local function emitAt(...) return ctx.emitAt(...) end
local function fxPart(...) return ctx.fxPart(...) end
local function impactRing(...) return ctx.impactRing(...) end

-- Reacción del enemigo al recibir daño: destello blanco breve con un Highlight local
-- reutilizado por modelo. No mueve sus piezas, así que no interfiere con su IA.
local flashes: { [Model]: Highlight } = setmetatable({}, { __mode = "k" }) :: any
local function flashEnemy(model: Model, color: Color3)
	if not model.Parent then
		return
	end
	local highlight = flashes[model]
	if not (highlight and highlight.Parent == model) then
		-- Si el enemigo ya tiene su contorno de caricatura, el destello usa ese mismo
		-- Highlight (dos por modelo gastarían el límite de Highlights visibles).
		local outline = model:FindFirstChild("Outline")
		if outline and outline:IsA("Highlight") then
			highlight = outline
		else
			highlight = Instance.new("Highlight")
			highlight.Name = "HitFlash"
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.OutlineTransparency = 1
			highlight.Enabled = false
			highlight.Parent = model
		end
		flashes[model] = highlight
	end
	local current = highlight :: Highlight
	local persistent = current.Name == "Outline"
	current.FillColor = color
	current.FillTransparency = 0.2
	current.Enabled = true
	local tween = TweenService:Create(current, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1 })
	tween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and not persistent then
			current.Enabled = false -- apagado: no ocupa el límite de Highlights visibles
		end
	end)
	tween:Play()
end

-- Número de daño: aparece con un pequeño "pop", sube y se desvanece en 0.7 s.
-- Como mucho MAX_DAMAGE_NUMBERS a la vez: el más antiguo se retira antes de tiempo.
local liveNumbers: { BasePart } = {}
local function damageNumber(position: Vector3, amount: number, color: Color3, killed: boolean, big: boolean?, boost: number?)
	for index = #liveNumbers, 1, -1 do
		if liveNumbers[index].Parent == nil then
			table.remove(liveNumbers, index)
		end
	end
	while #liveNumbers >= MAX_DAMAGE_NUMBERS do
		table.remove(liveNumbers, 1):Destroy()
	end
	local anchor = fxPart(Vector3.one * 0.1, CFrame.new(position + Vector3.new(math.random(-8, 8) / 10, 2.4, math.random(-8, 8) / 10)), color)
	anchor.Transparency = 1
	table.insert(liveNumbers, anchor)
	local size = (if killed then Vector2.new(150, 48) elseif big then Vector2.new(118, 40) else Vector2.new(96, 34)) * math.clamp(boost or 1, 0.5, 2)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(size.X * 1.3, size.Y * 1.3)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONTS.Display
	label.TextScaled = true
	label.TextColor3 = if killed then THEME.Gold else color
	label.TextStrokeColor3 = Color3.fromRGB(20, 26, 22)
	label.TextStrokeTransparency = 0.15
	label.Text = (if killed then "★ " else "") .. formatNumber(amount, 1)
	label.Parent = billboard
	billboard.Parent = anchor
	TweenService:Create(billboard, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(size.X, size.Y) }):Play()
	TweenService:Create(billboard, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 2.2, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.8)
end

-- Monedas ganadas en cada golpe: flotan en dorado sobre el enemigo
local liveCoinNumbers: { BasePart } = {}
local function coinNumber(position: Vector3, amount: number)
	for index = #liveCoinNumbers, 1, -1 do
		if liveCoinNumbers[index].Parent == nil then
			table.remove(liveCoinNumbers, index)
		end
	end
	while #liveCoinNumbers >= 10 do
		table.remove(liveCoinNumbers, 1):Destroy()
	end
	local anchor = fxPart(Vector3.one * 0.1, CFrame.new(position + Vector3.new(math.random(-6, 6) / 10, 2.6, math.random(-6, 6) / 10)), Color3.fromRGB(255, 220, 50))
	anchor.Transparency = 1
	table.insert(liveCoinNumbers, anchor)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(130, 42)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 80

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONTS.Display
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 235, 60)
	label.TextStrokeColor3 = Color3.fromRGB(45, 30, 10)
	label.TextStrokeTransparency = 0.12
	label.Text = "+$" .. formatNumber(amount, 0)
	label.Parent = billboard
	billboard.Parent = anchor

	TweenService:Create(billboard, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(115, 36) }):Play()
	TweenService:Create(billboard, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0.6, 2.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.75)
end

-- Impactos ya confirmados por el servidor de otros sistemas (mascotas y habilidades
-- elementales): número de daño (solo para el dueño), chispas, destello y sacudida.
-- boost agranda los números (habilidades); los impactos que dispararon un combo (campo
-- Reaction) salen aún más grandes.
local function showHits(hits: any, color: Color3, isOwner: boolean, react: number?, boost: number?)
	if typeof(hits) ~= "table" or not ctx.fxFolder then
		return
	end
	for _, hit in hits do
		if typeof(hit) == "table" and typeof(hit.Position) == "Vector3" and typeof(hit.Damage) == "number" then
			local killed = hit.Killed == true
			if isOwner then
				local size = (boost or 1) * (if hit.Reaction or hit.Combo then 1.35 else 1)
				damageNumber(hit.Position, hit.Damage, color, killed, hit.Kind == "Boss", size)
			end
			emitAt("Spark", hit.Position, color, if killed then 16 else 6)
			if killed then
				emitAt("Wisp", hit.Position, color, 12)
			end
			if typeof(hit.Model) == "Instance" and hit.Model:IsA("Model") then
				flashEnemy(hit.Model, color)
				if not killed then
					EnemyAnimator.react(hit.Model, react or 0.6)
				end
			end
		end
	end
end
Api.showHits = showHits
Api.emitAt = function(kind: string, position: Vector3, color: Color3, amount: number)
	if ctx.fxFolder then
		emitAt(kind, position, color, amount)
	end
end
Api.impactRing = function(center: Vector3, radius: number, color: Color3)
	if ctx.fxFolder then
		impactRing(center, radius, color)
	end
end
Api.beam = function(from: Vector3, to: Vector3, color: Color3, thickness: number)
	if ctx.fxFolder then
		beamEffect(from, to, color, thickness)
	end
end
-- Flecha del Arquero (la balista de la habilidad también las dispara)
Api.arrow = function(from: Vector3, to: Vector3, color: Color3, scale: number?)
	if ctx.fxFolder then
		arrowFx(from, to, color, scale)
	end
end

-- Número flotante (p. ej. la curación de la Marea Sanadora) con el mismo estilo.
function Api.floatingNumber(position: Vector3, amount: number, color: Color3, boost: number?)
	if ctx.fxFolder then
		damageNumber(position, amount, color, false, false, boost)
	end
end

-- Limpia los efectos temporales (al morir o cambiar de zona); conserva los emisores.
local function clearTransientEffects()
	for _, child in ctx.fxFolder:GetChildren() do
		if child.Name:sub(1, #POOL_PREFIX) ~= POOL_PREFIX then
			child:Destroy()
		end
	end
	table.clear(liveNumbers)
	EnemyAnimator.clearEffects()
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("CombatHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "CombatHud",
		ResetOnSpawn = false,
		DisplayOrder = 3, -- por debajo de inventario (5) y portal (6)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)

	-- Botón de ataque estilo `HUD Rediseño (standalone).html` (circular coral con borde #2B1D3F)
	local INK = Color3.fromRGB(43, 29, 63)
	local CREAM = Color3.fromRGB(255, 246, 224)
	local buttonFrame, buttonScale = UiKit.panel(screenGui, "AttackButton", Vector2.new(82, 82), Vector2.new(1, 1), UDim2.new(1, -20, 1, -22))
	buttonFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	buttonFrame.BackgroundTransparency = 0
	buttonFrame:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
	local oldShine = buttonFrame:FindFirstChild("Shine")
	if oldShine then
		oldShine:Destroy()
	end
	local oldGrad = buttonFrame:FindFirstChildOfClass("UIGradient")
	if oldGrad then
		oldGrad:Destroy()
	end
	UiKit.create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 217, 196)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(240, 112, 92)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 64, 58)),
		}),
	}, buttonFrame)
	local atkStroke = buttonFrame:FindFirstChildOfClass("UIStroke")
	if atkStroke then
		atkStroke.Color = INK
		atkStroke.Thickness = 4
		atkStroke.Transparency = 0
	end
	local cooldown = UiKit.create("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.4,
		ZIndex = 2,
	}, buttonFrame)
	UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, cooldown)
	local button = UiKit.create("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONTS.Display,
		TextSize = 38,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "⚔️",
		ZIndex = 3,
	}, buttonFrame)
	UiKit.addStates(button)
	local keyBadge = UiKit.create("Frame", {
		Name = "KeyBadge",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 2, 1, 2),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = INK,
		ZIndex = 4,
	}, buttonFrame)
	UiKit.corner(keyBadge, 8)
	UiKit.create("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Thickness = 1.5,
		Transparency = 0.72,
	}, keyBadge)
	UiKit.text(keyBadge, "Hint", {
		Size = UDim2.fromScale(1, 1),
		Font = FONTS.Display,
		TextSize = 14,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "F",
		ZIndex = 5,
	})
	local atkLabel = UiKit.text(buttonFrame, "AttackLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 5),
		Size = UDim2.fromOffset(90, 18),
		Font = FONTS.Display,
		TextSize = 13,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Disparar",
		ZIndex = 4,
	})
	UiKit.create("UIStroke", {
		Color = INK,
		Thickness = 2.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	}, atkLabel)
	-- Disparo automático (pase): encendido (AUTO), apagado (OFF) o sin el pase (🔒 AUTO)
	local autoBadge = UiKit.create("TextButton", {
		Name = "AutoBadge",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(-10, -8),
		Size = UDim2.fromOffset(58, 20),
		AutoButtonColor = true,
		BackgroundColor3 = AUTO_OFF,
		Font = FONTS.Display,
		TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "🔒 AUTO",
		ZIndex = 6,
	}, buttonFrame)
	UiKit.corner(autoBadge, 6)
	UiKit.create("UIStroke", { Color = INK, Thickness = 1.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, autoBadge)
	-- Arma equipada y su daño por segundo, sobre el botón
	local weaponPill = UiKit.text(buttonFrame, "WeaponPill", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 4, 0, -8),
		Size = UDim2.fromOffset(240, 22),
		Font = FONTS.Display,
		TextSize = 15,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})
	UiKit.create("UIStroke", { Color = INK, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, weaponPill)

	-- Barra del jefe: justo debajo de la tarjeta de energía (la energía de cada enemigo va a
	-- la pila común de avisos, que baja cuando la barra se ve).
	local top = UiKit.create("Frame", {
		Name = "TopArea",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 148),
		Size = UDim2.fromOffset(440, 160),
		BackgroundTransparency = 1,
	}, screenGui)
	local topScale = UiKit.create("UIScale", {}, top)
	-- Barras de jefe: una a lo ancho o, con dos jefes a la vez (Ignis y Glacius), una al lado
	-- de la otra en el mismo sitio. La primera se llama "BossBar" (WaveController la busca).
	local function makeBossBar(name: string)
		local bossBar, _ = UiKit.panel(top, name, Vector2.new(440, 54), Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0))
		bossBar.Visible = false
		local bossName = UiKit.text(bossBar, "Name", {
			Position = UDim2.fromOffset(16, 6),
			Size = UDim2.new(1, -32, 0, 20),
			Font = FONTS.Display,
			TextSize = 18,
			TextScaled = true,
		})
		local bossTrack = UiKit.create("Frame", {
			Name = "Track",
			Position = UDim2.fromOffset(16, 30),
			Size = UDim2.new(1, -32, 0, 14),
			BackgroundColor3 = THEME.Inset,
		}, bossBar)
		UiKit.corner(bossTrack, 7)
		-- Tramo claro que se vacía con retraso: deja ver cuánto daño acaba de recibir.
		local bossTrail = UiKit.create("Frame", {
			Name = "Trail",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(255, 236, 200),
			BackgroundTransparency = 0.25,
		}, bossTrack)
		UiKit.corner(bossTrail, 7)
		local bossFill = UiKit.create("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(230, 90, 100),
			ZIndex = 2,
		}, bossTrack)
		UiKit.corner(bossFill, 7)
		-- Marca de la furia (a la mitad de vida, como en EnemyConfig).
		local enrageMark = UiKit.create("Frame", {
			Name = "EnrageMark",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 2, 1, 6),
			BackgroundColor3 = BOSS_ENRAGED_COLOR,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, bossTrack)
		-- Marca de dónde se parte (el Coloso del Equilibrio: EnemyConfig.Types.*.Split)
		local splitMark = UiKit.create("Frame", {
			Name = "SplitMark",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 3, 1, 8),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 3,
		}, bossTrack)
		return { Bar = bossBar, Name = bossName, Fill = bossFill, Trail = bossTrail, EnrageMark = enrageMark, SplitMark = splitMark, TrailTarget = 1 }
	end
	local bossBars = { makeBossBar("BossBar"), makeBossBar("BossBar2") }
	local bossBar = bossBars[1].Bar

	-- Anuncio de jefe derrotado
	local banner = UiKit.text(screenGui, "BossBanner", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(700, 60),
		Font = FONTS.Display,
		TextSize = 40,
		TextColor3 = THEME.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.2,
		TextTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0),
	})

	-- Destello suave de pantalla al derrotar a un jefe
	local screenFlash = UiKit.create("Frame", {
		Name = "ScreenFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 246, 220),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Active = false,
	}, screenGui)

	screenGui.Parent = playerGui
	UiKit.bindScale(screenGui, { buttonScale, topScale })
	-- La zona superior sigue el borde inferior de la tarjeta de energía.
	local function placeTop()
		local scale = UiKit.computeScale(screenGui.AbsoluteSize)
		top.Position = UDim2.new(0.5, 0, 0, LAYOUT.Margin + LAYOUT.DiamondCardSize.Y * scale + 8)
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeTop)
	UiKit.onScaleChanged(placeTop) -- ⚙️ tamaño de la interfaz
	placeTop()

	return {
		ButtonFrame = buttonFrame,
		Button = button,
		Cooldown = cooldown,
		AutoBadge = autoBadge,
		WeaponPill = weaponPill,
		AttackLabel = atkLabel,
		BossBar = bossBar,
		BossBars = bossBars,
		Banner = banner,
		ScreenFlash = screenFlash,
	}
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
	context.buildGui = buildGui
	context.clearTransientEffects = clearTransientEffects
	context.damageNumber = damageNumber
	context.showHits = showHits
end

function Part.link(context: any)
	AUTO_OFF = context.AUTO_OFF
	BOSS_ENRAGED_COLOR = context.BOSS_ENRAGED_COLOR
	FONTS = context.FONTS
	LAYOUT = context.LAYOUT
	MAX_DAMAGE_NUMBERS = context.MAX_DAMAGE_NUMBERS
	POOL_PREFIX = context.POOL_PREFIX
	THEME = context.THEME
	player = context.player
end

return Part
