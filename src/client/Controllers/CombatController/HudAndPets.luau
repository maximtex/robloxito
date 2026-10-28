-- CombatController · HudAndPets: recarga, disparo automático, pastilla del arma e indicadores de mascotas.
-- Parte de CombatController (ver CombatController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local StyleConfig = require(Shared.Config.StyleConfig)
local formatNumber = require(Shared.Util.FormatNumber)
local CombatMath = require(Shared.CombatMath)
local MonetizationLogic = require(Shared.MonetizationLogic)
local UiKit = require(script.Parent.Parent.Parent.UI.UiKit)
local Toasts = require(script.Parent.Parent.Parent.UI.Toasts)
local PanelManager = require(script.Parent.Parent.Parent.UI.PanelManager)
local HudDock = require(script.Parent.Parent.Parent.UI.HudDock)
local AimPoint = require(script.Parent.Parent.AimPoint)
local CombatHud = require(script.Parent.Parent.CombatHud)
local StyleAnimations = require(script.Parent.Parent.StyleAnimations)

local ctx: any -- tabla de estado compartida (la crea CombatController/init.luau)
local AUTO_ACTION: any
local AUTO_OFF: any
local AUTO_ON: any
local FONTS: any
local REPEAT_SECONDS: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function enemiesInRange(...) return ctx.enemiesInRange(...) end
local function isMelee(...) return ctx.isMelee(...) end
local function meleeAim(...) return ctx.meleeAim(...) end
local function playStyleSound(...) return ctx.playStyleSound(...) end
local function send(...) return ctx.send(...) end
local function showHits(...) return ctx.showHits(...) end
local function signal(...) return ctx.signal(...) end
local function styleNow(...) return ctx.styleNow(...) end

local Part = { Api = {} }

function Part.start()
	local autoRemote = ctx.autoRemote
	local remotes = ctx.remotes
	local swingSound = ctx.swingSound
	local ui = ctx.ui

	-- R: recargar (Armas) si al cargador le faltan balas; si está lleno, la R sigue siendo la
	-- habilidad secundaria del núcleo
	local function canReload(): boolean
		local ammo = player:GetAttribute(Constants.Attributes.Ammo)
		local magazine = player:GetAttribute(Constants.Attributes.AmmoMax)
		local reloadEnd = player:GetAttribute(Constants.Attributes.ReloadEnd)
		return styleNow() == "Weapons" and type(ammo) == "number" and type(magazine) == "number" and ammo < magazine and not (type(reloadEnd) == "number" and reloadEnd > Workspace:GetServerTimeNow())
	end
	ContextActionService:BindActionAtPriority("RebirthReload", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if canReload() then
			signal("Reload")
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.R)
	CombatHud.start(ui.ButtonFrame)
	CombatHud.onResourceTapped(function()
		if canReload() then
			signal("Reload")
		end
	end)
	-- Sonido de recarga (también la automática al vaciar el cargador)
	player:GetAttributeChangedSignal(Constants.Attributes.ReloadEnd):Connect(function()
		local reloadEnd = player:GetAttribute(Constants.Attributes.ReloadEnd)
		if type(reloadEnd) == "number" and reloadEnd > 0 then
			playStyleSound("Reload", nil)
			StyleAnimations.reload(reloadEnd - Workspace:GetServerTimeNow())
		end
	end)

	-- Insignia AUTO o V: enciende o apaga el disparo automático; sin el pase, a la tienda
	local function hasAutoPass(): boolean
		return MonetizationLogic.autoFire(MonetizationLogic.parsePasses(player:GetAttribute(Constants.Attributes.Passes)))
	end
	local function refreshAutoFire()
		local owned = hasAutoPass()
		local on = owned and player:GetAttribute(Constants.Attributes.AutoFire) == true
		ui.AutoBadge.Text = if not owned then "🔒 AUTO" elseif on then "AUTO" else "OFF"
		ui.AutoBadge.BackgroundColor3 = if on then AUTO_ON else AUTO_OFF
	end
	local function toggleAutoFire()
		if not hasAutoPass() then
			Toasts.show("🎯 Disparo automático: consíguelo en la 🛒 Tienda", { Color = THEME.Gold, Key = "AutoFirePass" })
			PanelManager.open("Shop")
			return
		end
		autoRemote:FireServer(player:GetAttribute(Constants.Attributes.AutoFire) ~= true)
		if swingSound then
			swingSound:Play()
		end
	end
	ContextActionService:BindAction(AUTO_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggleAutoFire()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.V)
	ui.AutoBadge.Activated:Connect(toggleAutoFire)
	player:GetAttributeChangedSignal(Constants.Attributes.AutoFire):Connect(refreshAutoFire)
	player:GetAttributeChangedSignal(Constants.Attributes.Passes):Connect(refreshAutoFire)
	refreshAutoFire()

	-- Automático (con el pase y encendido): mientras haya enemigos cerca manda hacia dónde
	-- apuntas (el ratón; con mando o táctil, delante del personaje) y el servidor dispara solo
	-- cuando el disparo va a dar a alguien. Mientras mantienes pulsado no hace falta.
	task.spawn(function()
		local lastSent: Vector3? = nil
		local lastAt = 0
		while true do
			task.wait(REPEAT_SECONDS)
			if ctx.hold ~= nil or ctx.magicPress ~= nil or ctx.altHeld == "Block" or player:GetAttribute(Constants.Attributes.AutoFire) ~= true or not hasAutoPass() then
				continue
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (root and root:IsA("BasePart")) or #enemiesInRange(root.Position) == 0 then
				continue
			end
			local last = UserInputService:GetLastInputType()
			local pointer = UserInputService.MouseEnabled and last ~= Enum.UserInputType.Touch and not string.find(last.Name, "Gamepad", 1, true)
			local aim = if isMelee(styleNow()) then meleeAim() elseif pointer then AimPoint.mouse() else AimPoint.facing()
			local now = os.clock()
			if aim and (lastSent == nil or (aim - lastSent).Magnitude > 0.5 or now - lastAt > 0.3) then
				send(aim, "Aim")
				lastSent = aim
				lastAt = now
			end
		end
	end)

	-- Arma equipada (o el estilo, si no es Armas) y su daño por segundo sobre el botón
	local ATTACK_WORDS = { Weapons = "Disparar", Warrior = "Atacar", Fists = "Golpear", Magic = "Lanzar" }
	local function refreshWeaponPill()
		local def = WeaponConfig.Weapons[player:GetAttribute(Constants.Attributes.EquippedWeapon)] or WeaponConfig.Weapons[WeaponConfig.StarterWeapon]
		local dps = player:GetAttribute(Constants.Attributes.DamagePerSecond)
		local styleId = player:GetAttribute(Constants.Attributes.CombatStyle)
		local style = if typeof(styleId) == "string" and styleId ~= "Weapons" then StyleConfig.Styles[styleId] else nil
		local dpsText = formatNumber(if typeof(dps) == "number" then dps else 0)
		if style and def.Category == styleId then
			-- Puños / Magia: sus guantes o su bastón
			ui.WeaponPill.Text = ("%s %s · %s/s"):format(def.Icon, def.DisplayName, dpsText)
			ui.WeaponPill.TextColor3 = def.Color
		elseif style then
			ui.WeaponPill.Text = ("%s %s · %s/s"):format(style.Icon, style.DisplayName, dpsText)
			ui.WeaponPill.TextColor3 = style.Color
		else
			ui.WeaponPill.Text = ("%s %s · %s/s"):format(def.Icon, def.DisplayName, dpsText)
			ui.WeaponPill.TextColor3 = def.Color
		end
		ui.AttackLabel.Text = ATTACK_WORDS[if typeof(styleId) == "string" then styleId else "Weapons"] or "Disparar"
	end
	player:GetAttributeChangedSignal(Constants.Attributes.EquippedWeapon):Connect(refreshWeaponPill)
	player:GetAttributeChangedSignal(Constants.Attributes.DamagePerSecond):Connect(refreshWeaponPill)
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(refreshWeaponPill)
	refreshWeaponPill()

	-- En pantallas solo táctiles se usa el botón táctil de Roblox (junto al de saltar).
	local function refreshButtonVisibility()
		ui.ButtonFrame.Visible = not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	end
	UserInputService.LastInputTypeChanged:Connect(refreshButtonVisibility)
	refreshButtonVisibility()

	-- Mascotas de combate -------------------------------------------------------------
	-- Solo se dibujan acciones que el servidor ya ha resuelto (PetAbility).
	local petAbilityRemote = remotes:WaitForChild(Constants.Remotes.PetAbility) :: RemoteEvent
	local FOX_COLOR = Color3.fromRGB(110, 236, 220)
	local DRAGON_COLOR = Color3.fromRGB(190, 120, 255)
	local GUARD_COLOR = Color3.fromRGB(150, 232, 214)

	-- Posición de la mascota dibujada por PetFollower ("<jugador>_<hueco>_<PetId>").
	local function petPosition(owner: Player, petId: string, index: number): Vector3?
		local pets = Workspace:FindFirstChild("ClientPets")
		if pets then
			local prefix = owner.Name .. "_"
			local matches = {}
			for _, model in pets:GetChildren() do
				if model:IsA("Model") and model.PrimaryPart and model.Name:sub(1, #prefix) == prefix and model.Name:sub(-#petId) == petId then
					table.insert(matches, model)
				end
			end
			table.sort(matches, function(a, b)
				return a.Name < b.Name
			end)
			local model = matches[index] or matches[1]
			if model and model.PrimaryPart then
				return model.PrimaryPart.Position
			end
		end
		local character = owner.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root.Position + Vector3.new(0, 2, 0) else nil
	end

	local function showPetHits(hits: any, color: Color3, isOwner: boolean)
		showHits(hits, color, isOwner, 0.6)
	end

	-- Indicadores sobre el botón de ataque: recarga del dragón y defensa de la tortuga.
	local chips = UiKit.create("Frame", {
		Name = "PetAbilities",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -130),
		Size = UDim2.fromOffset(140, 60),
		BackgroundTransparency = 1,
	}, ui.ButtonFrame.Parent)
	local chipsScale = UiKit.create("UIScale", {}, chips)
	UiKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8),
	}, chips)
	local function makeChip(name: string, icon: string)
		local chip, _ = UiKit.panel(chips, name, Vector2.new(56, 56), Vector2.zero, UDim2.new())
		chip:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
		local scale = chip:FindFirstChildOfClass("UIScale")
		if scale then
			scale:Destroy() -- la escala la lleva el contenedor
		end
		local overlay = UiKit.create("Frame", {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = THEME.Overlay,
			BackgroundTransparency = 0.35,
			ZIndex = 2,
		}, chip)
		UiKit.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, overlay)
		UiKit.text(chip, "Icon", {
			Size = UDim2.fromScale(1, 1),
			Font = FONTS.Display,
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = icon,
			ZIndex = 3,
		})
		local label = UiKit.text(chip, "Label", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 2),
			Size = UDim2.fromOffset(70, 16),
			Font = FONTS.Light,
			TextSize = 13,
			TextColor3 = THEME.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.5,
			ZIndex = 3,
		})
		chip.Visible = false
		return chip, overlay, label
	end
	local dragonChip, dragonCooldown, dragonLabel = makeChip("DragonChip", "🐉")
	local turtleChip, _, turtleLabel = makeChip("TurtleChip", "🛡")
	dragonLabel.Text = "Nova lista"
	UiKit.bindScale(ui.ButtonFrame.Parent :: ScreenGui, { chipsScale })

	local function equippedCount(petId: string): number
		local value = player:GetAttribute(Constants.Attributes.EquippedPets)
		local count = 0
		if typeof(value) == "string" then
			for _, id in string.split(value, ",") do
				if id == petId then
					count += 1
				end
			end
		end
		return count
	end

	-- Aura discreta de la tortuga: partículas locales en el propio personaje (no cambia
	-- el avatar y desaparece con él).
	local function refreshGuardAura()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local existing = root:FindFirstChild("GuardAura")
		local turtles = equippedCount("CrystalTurtle")
		if turtles <= 0 then
			if existing then
				existing:Destroy()
			end
			return
		end
		if existing then
			return
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = "GuardAura"
		local motes = Instance.new("ParticleEmitter")
		motes.Rate = 3
		motes.Lifetime = NumberRange.new(1, 1.6)
		motes.Speed = NumberRange.new(0.3, 0.8)
		motes.SpreadAngle = Vector2.new(180, 180)
		motes.Size = NumberSequence.new(0.22, 0)
		motes.Transparency = NumberSequence.new(0.3, 1)
		motes.LightEmission = 1
		motes.Color = ColorSequence.new(GUARD_COLOR)
		motes.Parent = attachment
		attachment.Parent = root
	end

	local function refreshPetChips()
		local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		-- En móvil, a media altura a la derecha para no chocar con los botones táctiles; en
		-- escritorio, justo encima del botón de ataque (que crece con la escala del HUD).
		local hudScale = UiKit.computeScale((ui.ButtonFrame.Parent :: ScreenGui).AbsoluteSize)
		-- (por encima del arma equipada, que va justo sobre el botón)
		chips.Position = if touchOnly then UDim2.new(1, -20, 0.5, 0) else UDim2.new(1, -20, 1, -(24 + 96 * hudScale + 12 + 30 * hudScale))
		dragonChip.Visible = equippedCount("AmethystDragon") > 0
		local turtles = equippedCount("CrystalTurtle")
		turtleChip.Visible = turtles > 0
		turtleLabel.Text = "-" .. formatNumber(CombatMath.guardReduction(turtles) * 100, 0) .. " % daño"
		-- La columna derecha del HUD termina encima de los indicadores cuando se ven.
		-- (el arma equipada ocupa ese sitio aunque no haya indicadores)
		HudDock.setChips(true)
		refreshGuardAura()
	end
	player:GetAttributeChangedSignal(Constants.Attributes.EquippedPets):Connect(refreshPetChips)
	local hudGui = ui.ButtonFrame.Parent :: ScreenGui
	hudGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refreshPetChips)
	UiKit.onScaleChanged(refreshPetChips) -- ⚙️ tamaño de la interfaz
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 5)
		refreshPetChips()
	end)
	refreshPetChips()

	local function startDragonCooldown(readyAt: number)
		local remaining = readyAt - Workspace:GetServerTimeNow()
		if remaining <= 0 then
			return
		end
		dragonLabel.Text = "¡Nova!"
		dragonLabel.TextColor3 = DRAGON_COLOR
		dragonCooldown.Size = UDim2.fromScale(1, 1)
		local tween = TweenService:Create(dragonCooldown, TweenInfo.new(remaining, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 0) })
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				dragonLabel.Text = "Nova lista"
				dragonLabel.TextColor3 = THEME.Muted
			end
		end)
		tween:Play()
	end

	-- Orbes que están cargando otros magos (aviso "Charging"); se quitan al lanzarlo
	local othersCharging: { [Player]: Part } = {}
	Players.PlayerRemoving:Connect(function(leaving)
		local orb = othersCharging[leaving]
		if orb then
			orb:Destroy()
			othersCharging[leaving] = nil
		end
	end)

	ctx.DRAGON_COLOR = DRAGON_COLOR
	ctx.FOX_COLOR = FOX_COLOR
	ctx.GUARD_COLOR = GUARD_COLOR
	ctx.othersCharging = othersCharging
	ctx.petAbilityRemote = petAbilityRemote
	ctx.petPosition = petPosition
	ctx.showPetHits = showPetHits
	ctx.startDragonCooldown = startDragonCooldown
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	AUTO_ACTION = context.AUTO_ACTION
	AUTO_OFF = context.AUTO_OFF
	AUTO_ON = context.AUTO_ON
	FONTS = context.FONTS
	REPEAT_SECONDS = context.REPEAT_SECONDS
	THEME = context.THEME
	player = context.player
end

return Part
