-- CombatController · RewardsAndBoss: monedas y diamantes voladores, avisos de botín y barras de vida de los jefes.
-- Parte de CombatController (ver CombatController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CombatConfig = require(Shared.Config.CombatConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local Toasts = require(script.Parent.Parent.Parent.UI.Toasts)
local HudDock = require(script.Parent.Parent.Parent.UI.HudDock)
local EnemyAnimator = require(script.Parent.Parent.EnemyAnimator)
local WaveVisibility = require(script.Parent.Parent.WaveVisibility)

local ctx: any -- tabla de estado compartida (la crea CombatController/init.luau)
local BOSS_BAR_COLOR: any
local BOSS_BAR_RANGE: any
local BOSS_CHASE_COLOR: any
local BOSS_ENRAGED_COLOR: any
local COINS_BOSS: any
local COINS_KILL: any
local COIN_COLOR: any
local COIN_SIZE: any
local GEM_TILT: any
local GOLDEN_COLOR: any
local MAX_FLYING: any
local ORBS_BOSS: any
local ORBS_KILL: any
local ORB_COLOR: any
local ORB_SIZE: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function clearTransientEffects(...) return ctx.clearTransientEffects(...) end
local function emitAt(...) return ctx.emitAt(...) end
local function playVaried(...) return ctx.playVaried(...) end

local Part = { Api = {} }

function Part.start()
	local bossDefeatSound = ctx.bossDefeatSound
	local killSound = ctx.killSound
	local rewardRemote = ctx.rewardRemote
	local ui = ctx.ui

	-- Limpiar efectos temporales al morir o al cambiar de zona.
	player.CharacterRemoving:Connect(function()
		if ctx.animationTrack then
			ctx.animationTrack:Stop(0)
			ctx.animationTrack = nil
		end
		clearTransientEffects()
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.CurrentZone):Connect(function()
		clearTransientEffects()
	end)

	-- Dinero ganado al derrotar a un enemigo (línea breve en la pila común de avisos)
	local function toast(text: string, color: Color3)
		Toasts.show(text, { Style = "Line", Color = color })
	end

	-- Monedas: saltan del enemigo en abanico y vuelan girando hasta el jugador
	local flying = 0
	local function dropCoins(from: Vector3, count: number)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		count = math.min(count, math.max(0, MAX_FLYING - flying))
		flying += count
		task.delay(0.7 + count * 0.025, function()
			flying = math.max(0, flying - count)
		end)
		for index = 1, count do
			local coin = Instance.new("Part")
			coin.Name = "Coin"
			coin.Shape = Enum.PartType.Cylinder
			coin.Size = COIN_SIZE
			coin.Color = COIN_COLOR
			coin.Material = Enum.Material.SmoothPlastic
			coin.Reflectance = 0.25
			coin.Anchored = true
			coin.CanCollide = false
			coin.CanQuery = false
			coin.CanTouch = false
			coin.CastShadow = false
			local angle = (index / count + math.random() * 0.15) * math.pi * 2
			local spread = if count > 1 then 2 + math.random() * 2.5 else 1
			local peak = from + Vector3.new(math.cos(angle) * spread, 2.5 + math.random() * 2, math.sin(angle) * spread)
			coin.CFrame = CFrame.new(from) * CFrame.Angles(0, angle, 0)
			coin.Parent = ctx.fxFolder
			local pop = TweenService:Create(coin, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(peak) * CFrame.Angles(0, angle + math.pi, 0) })
			pop:Play()
			task.delay(0.28 + index * 0.025, function()
				if not coin.Parent then
					return
				end
				local goal = if root.Parent then root.Position else peak
				TweenService:Create(coin, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = CFrame.new(goal) * CFrame.Angles(0, angle + math.pi * 3, 0),
					Size = COIN_SIZE * 0.4,
				}):Play()
				Debris:AddItem(coin, 0.32)
			end)
		end
	end

	-- Diamantes: brotan del enemigo, flotan un instante y vuelan hasta el jugador (uno por 💎,
	-- hasta ORBS_KILL).
	-- El orbe dorado es uno grande que brilla (y suena) antes de volar.
	local function dropOrbs(from: Vector3, count: number, golden: boolean)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		if golden then
			count += 1
		end
		count = math.min(count, math.max(0, MAX_FLYING - flying))
		flying += count
		task.delay(1 + count * 0.04, function()
			flying = math.max(0, flying - count)
		end)
		for index = 1, count do
			local isGolden = golden and index == count
			local size = if isGolden then ORB_SIZE * 2.4 else ORB_SIZE * (0.8 + math.random() * 0.4)
			local orb = Instance.new("Part")
			orb.Name = if isGolden then "GoldenOrb" else "DiamondDrop"
			orb.Shape = if isGolden then Enum.PartType.Ball else Enum.PartType.Block
			local tilt = if isGolden then CFrame.identity else GEM_TILT
			orb.Size = Vector3.one * size
			orb.Color = if isGolden then GOLDEN_COLOR else ORB_COLOR
			orb.Material = Enum.Material.Neon
			orb.Anchored = true
			orb.CanCollide = false
			orb.CanQuery = false
			orb.CanTouch = false
			orb.CastShadow = false
			local angle = math.random() * math.pi * 2
			local spread = 1.5 + math.random() * 2.5
			local peak = from + Vector3.new(math.cos(angle) * spread, 3 + math.random() * 2.5, math.sin(angle) * spread)
			orb.CFrame = CFrame.new(from) * tilt
			if isGolden then
				local light = Instance.new("PointLight")
				light.Color = GOLDEN_COLOR
				light.Range = 12
				light.Brightness = 3
				light.Shadows = false
				light.Parent = orb
			end
			orb.Parent = ctx.fxFolder
			TweenService:Create(orb, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = CFrame.new(peak) * tilt * CFrame.Angles(0, math.pi, 0) }):Play()
			local hold = if isGolden then 0.6 else 0.3 + index * 0.04
			task.delay(0.35 + hold, function()
				if not orb.Parent then
					return
				end
				local goal = if root.Parent then root.Position else peak
				TweenService:Create(orb, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = CFrame.new(goal) * tilt,
					Size = Vector3.one * size * 0.3,
				}):Play()
				Debris:AddItem(orb, 0.3)
				if isGolden then
					emitAt("Glint", goal, GOLDEN_COLOR, 24)
				end
			end)
		end
	end

	-- Anuncio grande y breve en el centro (jefe derrotado o en furia).
	local bannerToken = 0
	local function showBanner(text: string, color: Color3)
		bannerToken += 1
		local token = bannerToken
		ui.Banner.Text = text
		ui.Banner.TextColor3 = color
		ui.Banner.TextTransparency = 0
		ui.Banner.TextStrokeTransparency = 0.2
		task.delay(2.6, function()
			if bannerToken == token then
				TweenService:Create(ui.Banner, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end

	-- Cada golpe suelta una moneda; al derrotarlo, un puñado (más si es un jefe) y el aviso.
	rewardRemote.OnClientEvent:Connect(function(amount: number, enemyName: string, isBoss: boolean, at: Vector3?, isKill: boolean?, extra: any?)
		if typeof(amount) ~= "number" then
			return
		end
		local diamonds = if type(extra) == "table" and typeof(extra.Diamonds) == "number" then extra.Diamonds else 0
		local golden = type(extra) == "table" and extra.Golden == true
		if typeof(at) == "Vector3" then
			dropCoins(at, if isBoss then COINS_BOSS elseif isKill then COINS_KILL else 1)
			if isKill and (diamonds > 0 or golden) then
				dropOrbs(at, math.clamp(diamonds, 1, if isBoss then ORBS_BOSS else ORBS_KILL), golden)
			end
		end
		if not (isKill or isBoss) then
			return -- golpe suelto: solo la moneda y el salto del contador
		end
		local loot = ("+%s 💰"):format(formatNumber(amount)) .. (if diamonds > 0 then ("  +%s 💎"):format(formatNumber(diamonds)) else "")
		if golden then
			Toasts.show(("🌟 ¡BOTÍN DORADO!  ×10  ·  %s"):format(loot), { Color = GOLDEN_COLOR, Key = "GoldenOrb" })
			playVaried(killSound, 1.6, 0.05)
		elseif isBoss then
			toast(("%s  ·  %s"):format(loot, tostring(enemyName)), THEME.Gold)
		else
			-- Uno solo que se actualiza: con hordas no se apilan decenas de avisos.
			Toasts.show(("%s  ·  %s"):format(loot, tostring(enemyName)), { Style = "Line", Color = THEME.BuyHighlight, Key = "KillLoot" })
		end
		if isBoss then
			showBanner(("¡%s derrotado!  +%s 💰"):format(tostring(enemyName), formatNumber(amount)), THEME.Gold)
			ui.ScreenFlash.BackgroundTransparency = 0.55
			TweenService:Create(ui.ScreenFlash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
			if bossDefeatSound then
				bossDefeatSound:Play()
			end
		end
	end)

	-- Animación de enemigos y entrada de los jefes (aviso solo si estás cerca de su arena).
	EnemyAnimator.start({
		SpawnSound = CombatConfig.Sounds.BossSpawn,
		IsVisible = WaveVisibility.isVisible,
		OnBossSpawn = function(model: Model)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local center = model:GetAttribute("ArenaCenter")
			local radius = model:GetAttribute("ArenaRadius")
			if root and root:IsA("BasePart") and typeof(center) == "Vector3" and typeof(radius) == "number" then
				local offset = root.Position - center
				if Vector2.new(offset.X, offset.Z).Magnitude <= radius + BOSS_BAR_RANGE * 2 then
					showBanner(("¡%s ha despertado!"):format(tostring(model:GetAttribute("DisplayName"))), BOSS_BAR_COLOR)
				end
			end
		end,
	})

	-- Barras de jefe: se muestran al acercarse a una arena con su jefe vivo. Con dos jefes a
	-- la vez (las mitades del Coloso del Equilibrio), una al lado de la otra.
	local enragedAnnounced: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local barOwner: { [number]: Model? } = {}
	local bossBarShown = false
	local function fillBar(bar, model: Model, health: number, maxHealth: number, compact: boolean)
		local enraged = model:GetAttribute("Enraged") == true
		-- La IA del jefe publica a quién persigue (TargetUserId)
		local chasing = model:GetAttribute("TargetUserId") == player.UserId
		local name = tostring(model:GetAttribute("DisplayName"))
		local status = if compact then "" else (if chasing then "  ·  ¡Te persigue!" else "") .. (if enraged then "  ·  ¡Furioso!" else "")
		bar.Name.Text = name .. status .. ("   %s / %s"):format(formatNumber(health), formatNumber(maxHealth))
		bar.Name.TextColor3 = if enraged then BOSS_ENRAGED_COLOR elseif chasing then BOSS_CHASE_COLOR else THEME.Text
		local def = EnemyConfig.Types[model:GetAttribute("EnemyType")]
		local tint = def and def.Look and def.Look.Secondary
		bar.Fill.BackgroundColor3 = if enraged then BOSS_ENRAGED_COLOR elseif compact and typeof(tint) == "Color3" then tint else BOSS_BAR_COLOR
		local fraction = math.clamp(health / maxHealth, 0, 1)
		bar.Fill.Size = UDim2.fromScale(fraction, 1)
		-- El tramo claro alcanza a la vida real con un pequeño retraso.
		if fraction < bar.TrailTarget then
			TweenService:Create(bar.Trail, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.25), { Size = UDim2.fromScale(fraction, 1) }):Play()
		else
			bar.Trail.Size = UDim2.fromScale(fraction, 1)
		end
		bar.TrailTarget = fraction
		local enrageAt = def and def.Enrage and def.Enrage.HealthFraction
		bar.EnrageMark.Visible = enrageAt ~= nil and not enraged
		if enrageAt then
			bar.EnrageMark.Position = UDim2.fromScale(enrageAt, 0.5)
		end
		local splitAt = def and def.Split and def.Split.HealthFraction
		bar.SplitMark.Visible = splitAt ~= nil
		if splitAt then
			bar.SplitMark.Position = UDim2.fromScale(splitAt, 0.5)
		end
		-- Anunciar la entrada en furia una vez por vida del jefe
		if enraged and not enragedAnnounced[model] then
			enragedAnnounced[model] = true
			showBanner(("¡%s entra en furia!"):format(name), BOSS_ENRAGED_COLOR)
		elseif not enraged then
			enragedAnnounced[model] = nil
		end
	end
	task.spawn(function()
		while true do
			task.wait(0.25)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local enemiesFolder = Workspace:FindFirstChild("Enemies")
			local found = {}
			if root and root:IsA("BasePart") and enemiesFolder then
				for _, zoneFolder in enemiesFolder:GetChildren() do
					for _, model in zoneFolder:GetChildren() do
						if model:IsA("Model") and model:GetAttribute("Kind") == "Boss" and WaveVisibility.isVisible(model) then
							local center = model:GetAttribute("ArenaCenter")
							local radius = model:GetAttribute("ArenaRadius")
							local health = model:GetAttribute("Health")
							local maxHealth = model:GetAttribute("MaxHealth")
							if typeof(center) == "Vector3" and typeof(radius) == "number" and typeof(health) == "number" and typeof(maxHealth) == "number" and health > 0 and maxHealth > 0 then
								local offset = root.Position - center
								if Vector2.new(offset.X, offset.Z).Magnitude <= radius + BOSS_BAR_RANGE then
									table.insert(found, { Model = model, Health = health, MaxHealth = maxHealth })
								end
							end
						end
					end
				end
			end
			-- Siempre en el mismo orden (fuego a la izquierda: por tipo)
			table.sort(found, function(a, b)
				return tostring(a.Model:GetAttribute("EnemyType")) > tostring(b.Model:GetAttribute("EnemyType"))
			end)
			local count = math.min(#found, #ui.BossBars)
			local compact = count > 1
			for index, bar in ui.BossBars do
				local entry = found[index]
				local visible = entry ~= nil and index <= count
				if visible then
					if barOwner[index] ~= entry.Model then
						barOwner[index] = entry.Model
						bar.TrailTarget = 1
					end
					fillBar(bar, entry.Model, entry.Health, entry.MaxHealth, compact)
					-- Dos a la vez: mitad de ancho cada una, una a cada lado del centro
					bar.Bar.Size = UDim2.fromOffset(if compact then 216 else 440, 54)
					bar.Bar.AnchorPoint = Vector2.new(if compact then (if index == 1 then 1 else 0) else 0.5, 0)
					bar.Bar.Position = UDim2.new(0.5, if compact then (if index == 1 then -4 else 4) else 0, 0, 0)
				else
					barOwner[index] = nil
				end
				if bar.Bar.Visible ~= visible then
					bar.Bar.Visible = visible
				end
			end
			local shown = count > 0
			if bossBarShown ~= shown then
				bossBarShown = shown
				HudDock.setBossBar(shown)
			end
		end
	end)
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	BOSS_BAR_COLOR = context.BOSS_BAR_COLOR
	BOSS_BAR_RANGE = context.BOSS_BAR_RANGE
	BOSS_CHASE_COLOR = context.BOSS_CHASE_COLOR
	BOSS_ENRAGED_COLOR = context.BOSS_ENRAGED_COLOR
	COINS_BOSS = context.COINS_BOSS
	COINS_KILL = context.COINS_KILL
	COIN_COLOR = context.COIN_COLOR
	COIN_SIZE = context.COIN_SIZE
	GEM_TILT = context.GEM_TILT
	GOLDEN_COLOR = context.GOLDEN_COLOR
	MAX_FLYING = context.MAX_FLYING
	ORBS_BOSS = context.ORBS_BOSS
	ORBS_KILL = context.ORBS_KILL
	ORB_COLOR = context.ORB_COLOR
	ORB_SIZE = context.ORB_SIZE
	THEME = context.THEME
	player = context.player
end

return Part
