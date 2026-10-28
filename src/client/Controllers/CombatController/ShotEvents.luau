-- CombatController · ShotEvents: recepción de PetAbility: disparos de cada estilo, paradas y habilidades de mascotas.
-- Parte de CombatController (ver CombatController/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared.Config.WeaponConfig)
local StyleConfig = require(Shared.Config.StyleConfig)
local CharacterPose = require(script.Parent.Parent.CharacterPose)
local AimPoint = require(script.Parent.Parent.AimPoint)
local AimCamera = require(script.Parent.Parent.AimCamera)
local CombatHud = require(script.Parent.Parent.CombatHud)
local StyleAnimations = require(script.Parent.Parent.StyleAnimations)
local GunLogic = require(Shared.GunLogic)

local ctx: any -- tabla de estado compartida (la crea CombatController/init.luau)
local GUN_FEEL: any
local PUNCH_REACH: any
local THEME: any
local player: any

-- Funciones de las otras partes
local function arrowFx(...) return ctx.arrowFx(...) end
local function beamEffect(...) return ctx.beamEffect(...) end
local function comboLabel(...) return ctx.comboLabel(...) end
local function damageNumber(...) return ctx.damageNumber(...) end
local function emitAt(...) return ctx.emitAt(...) end
local function flashBall(...) return ctx.flashBall(...) end
local function fxPart(...) return ctx.fxPart(...) end
local function impactRing(...) return ctx.impactRing(...) end
local function keepSteady(...) return ctx.keepSteady(...) end
local function lunge(...) return ctx.lunge(...) end
local function magicOrb(...) return ctx.magicOrb(...) end
local function petPosition(...) return ctx.petPosition(...) end
local function playStyleSound(...) return ctx.playStyleSound(...) end
local function playVaried(...) return ctx.playVaried(...) end
local function punchContact(...) return ctx.punchContact(...) end
local function punchFx(...) return ctx.punchFx(...) end
local function rocketFx(...) return ctx.rocketFx(...) end
local function shakeCamera(...) return ctx.shakeCamera(...) end
local function showHits(...) return ctx.showHits(...) end
local function showPetHits(...) return ctx.showPetHits(...) end
local function slashArc(...) return ctx.slashArc(...) end
local function startDragonCooldown(...) return ctx.startDragonCooldown(...) end

local Part = { Api = {} }

function Part.start()
	local DRAGON_COLOR = ctx.DRAGON_COLOR
	local FOX_COLOR = ctx.FOX_COLOR
	local GUARD_COLOR = ctx.GUARD_COLOR
	local hitSound = ctx.hitSound
	local killSound = ctx.killSound
	local novaSound = ctx.novaSound
	local othersCharging = ctx.othersCharging
	local petAbilityRemote = ctx.petAbilityRemote

	petAbilityRemote.OnClientEvent:Connect(function(event)
		if typeof(event) ~= "table" or typeof(event.Owner) ~= "Instance" then
			return
		end
		local owner = event.Owner :: Player
		local isOwner = owner == player

		if event.Kind == "PlayerShot" and typeof(event.Target) == "Vector3" then
			local def = WeaponConfig.Weapons[event.WeaponId] or WeaponConfig.Weapons[WeaponConfig.StarterWeapon]
			local style = if typeof(event.Style) == "string" and StyleConfig.Styles[event.Style] then event.Style else "Weapons"
			-- El color del arma, o el de los guantes / la espada (si no, el del estilo); la
			-- magia, el de su elemento
			local gearOfStyle = style == "Weapons" or def.Category == style
			local color = if gearOfStyle then def.Color else StyleConfig.Styles[style].Color
			local elementSpec = if style == "Magic" and typeof(event.Element) == "string" then StyleConfig.Styles.Magic.Elements[event.Element] else nil
			if elementSpec and elementSpec.Color then
				color = elementSpec.Color
			end
			-- Rayos que saltan de enemigo en enemigo (cristal, rayo)
			local function chainFx(from: Vector3)
				if typeof(event.Chain) ~= "table" then
					return
				end
				local previous = from
				for _, point in event.Chain do
					if typeof(point) == "Vector3" then
						beamEffect(previous, point, color, 0.25)
						emitAt("Glint", point, color, 3)
						previous = point
					end
				end
			end
			local crit = event.Crit == true
			local combo = if typeof(event.Combo) == "string" then event.Combo else nil
			local character = owner.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local target = event.Target :: Vector3
			-- Tu personaje mira hacia donde va el disparo (el automático, F con el mando) si
			-- está quieto y no estás manteniendo pulsado (entonces ya mira al cursor)
			if isOwner and ctx.hold == nil and not AimCamera.isAds() then
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.MoveDirection.Magnitude < 0.1 then
					AimPoint.faceToward(target)
				end
			end
			local from = if root and root:IsA("BasePart") then root.Position + Vector3.new(0, 1.2, 0) else target
			local hand = CharacterPose.handPosition(character) or from
			local soundAt = if isOwner then nil else from
			-- Números, chispas y sonido de acierto (y la ✕ de la mira si es tuyo).
			-- `styleSound`: el sonido del golpe de este estilo en vez del genérico
			local function impact(styleSound: string?)
				emitAt("Glint", target, color, if crit then 10 else 4)
				if typeof(event.Splash) == "number" then
					impactRing(target, event.Splash, color)
				end
				-- Crítico: número dorado y más grande
				showHits(event.Hits, if crit then THEME.Gold else color, isOwner, 0.8, if crit then 1.6 else nil)
				if typeof(event.Hits) == "table" and #event.Hits > 0 then
					local killed = false
					for _, hit in event.Hits do
						killed = killed or (typeof(hit) == "table" and hit.Killed == true)
					end
					if styleSound then
						playStyleSound(styleSound, soundAt)
					end
					if isOwner then
						CombatHud.hitMarker(killed)
						if killed then
							playVaried(killSound, 0.9, 0.05)
						elseif not styleSound then
							playVaried(hitSound, if style == "Fists" then 0.95 elseif crit then 1.6 else 1.35, 0.07)
						end
					end
				end
			end
			if style == "Fists" then
				-- Puñetazo: el personaje lanza el puño, se echa encima del enemigo (el tuyo; los
				-- demás lo ven por Roblox) y el golpe estalla justo donde el puño lo toca, con un
				-- frenazo de la animación y la cámara que tiembla. El gancho (el 3.º seguido) es
				-- más grande y lo levanta por los aires.
				local big = combo ~= nil
				if not StyleAnimations.enabled("Fists") then
					CharacterPose.punch(character)
				elseif isOwner then
					StyleAnimations.punch(big)
				end
				playStyleSound("PunchSwing", soundAt, if big then 0.8 else 1)
				local first = if typeof(event.Hits) == "table" then event.Hits[1] else nil
				local hitModel = if typeof(first) == "table" then first.Model else nil
				if event.Miss == true or hitModel == nil then
					-- Al aire: solo el soplo delante del puño
					local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
					local ahead = if flat.Magnitude > 0.05 then flat.Unit * math.min(flat.Magnitude, 2.5) else Vector3.zero
					emitAt("Miss", from + ahead, Color3.new(1, 1, 1), 4)
					impact()
				else
					local _, direction, reach = punchContact(from, target, hitModel)
					local lungeSeconds = 0
					if isOwner and root and root:IsA("BasePart") then
						keepSteady(root, 0.6)
						lungeSeconds = lunge(root, direction, reach - PUNCH_REACH, hitModel)
					end
					-- El golpe llega cuando el brazo está estirado (y la embestida ha terminado)
					task.delay(math.max(lungeSeconds, if big then 0.12 else 0.06), function()
						local now = if root and root:IsA("BasePart") and root.Parent then root.Position + Vector3.new(0, 1.2, 0) else from
						local contact, towards = punchContact(now, target, hitModel)
						punchFx(contact, towards, color, big)
						emitAt("Spark", contact, color, if big then 20 else 9)
						if big then
							impactRing(target, 5, color)
							comboLabel(target, combo :: string, color)
						end
						chainFx(contact)
						if isOwner then
							shakeCamera(if big then 0.62 else 0.34, if big then 5 else 1.5)
							StyleAnimations.hitstop(if big then 0.09 else 0.045)
						end
						impact(if big then "PunchHook" else "PunchHit")
					end)
				end
			elseif style == "Warrior" then
				-- Tajo de espada: el brazo barre y un arco de luz pasa delante (el 3.º, una
				-- rueda alrededor); el contraataque tras una parada sale dorado y más grande
				local step = math.clamp(math.floor(tonumber(event.Step) or 1), 1, 3)
				local counter = event.Counter == true
				local center = if root and root:IsA("BasePart") then root.Position else target
				local direction = if typeof(event.Direction) == "Vector3" then event.Direction else target - center
				local radius = tonumber(event.Radius) or 10
				local arcColor = if counter then THEME.Gold else color
				-- La animación de la espada la pone tu cliente en tu personaje (los demás la ven
				-- por Roblox); sin animaciones, el movimiento a mano en cada cliente
				if not StyleAnimations.enabled("Warrior") then
					CharacterPose.slash(character, step)
				elseif isOwner then
					StyleAnimations.slash(step)
				end
				slashArc(center, direction, radius, arcColor, step, counter or step == 3)
				if step == 3 then
					impactRing(center, radius * 0.9, arcColor)
				end
				playStyleSound(if step == 3 then "SwordSpin" else "SwordSwing", soundAt, if counter then 0.85 else 1)
				local slashes = StyleConfig.Styles.Warrior.Slashes
				local hitSomeone = typeof(event.Hits) == "table" and #event.Hits > 0
				if hitSomeone then
					emitAt("Spark", target, arcColor, if step == 3 or counter then 18 else 9)
					if counter then
						comboLabel(target, "¡Contraataque!", THEME.Gold)
						flashBall(target, Color3.new(1, 1, 1), 0.8, 6, 0.22)
					elseif step == 3 and slashes and slashes[3] and slashes[3].Name then
						comboLabel(target, slashes[3].Name, color)
					end
				end
				chainFx(target)
				impact("SwordHit")
			elseif style == "Magic" then
				-- Bola de energía desde la esfera del bastón, del color de su elemento: chispa
				-- pequeña sin maná, orbe enorme si la cargaste
				local charge = tonumber(event.Charge)
				local spark = event.Spark == true
				local scale = if charge then 1.3 + charge * 1.3 elseif spark then 0.5 else 1
				local others = othersCharging[owner]
				if others then
					others:Destroy()
					othersCharging[owner] = nil
				end
				if not StyleAnimations.enabled("Magic") then
					CharacterPose.cast(character, 0.12)
				elseif isOwner then
					StyleAnimations.cast()
				end
				local orbAt = CharacterPose.gearPoint(character, "Orb") or hand
				playStyleSound("MagicBolt", soundAt, if charge then 0.6 elseif spark then 1.35 else 1)
				magicOrb(orbAt, target, color, function()
					local big = charge ~= nil and charge >= 0.5
					flashBall(target, color, 1, if charge then 5 + charge * 9 elseif spark then 2.5 else 5, if big then 0.34 else 0.2)
					impactRing(target, if charge then 3 + charge * 5 elseif spark then 1.6 else 3, Color3.new(1, 1, 1))
					if big then
						playStyleSound("Explosion", soundAt, 1.25)
						emitAt("Glint", target, color, 14)
					end
					chainFx(target)
					if charge and charge >= 0.99 then
						comboLabel(target, "¡Orbe cargado!", color)
					end
					impact()
				end, scale)
			else
				-- Arquero: retroceso y una flecha por disparo (los virotes en abanico de la ballesta
				-- de abanico, el que atraviesa de la arbalesta) y el virote con bomba de la
				-- balista (su explosión llega luego en "ShotImpact"). Sin fogonazo: no hay pólvora.
				local gun = if typeof(event.Gun) == "string" then event.Gun else GunLogic.kind(event.WeaponId)
				local feel = GUN_FEEL[gun] or GUN_FEEL.Pistol
				local isBow = def.Model == "Bow"
				local muzzle = CharacterPose.gearPoint(character, "Muzzle") or hand
				if not StyleAnimations.enabled("Weapons") then
					CharacterPose.recoil(character, feel.Recoil)
				elseif isOwner then
					StyleAnimations.shot()
				end
				playStyleSound(if isBow then "GunBow" else "Gun" .. gun, soundAt)
				if isOwner then
					CombatHud.kick(feel.Kick)
				end
				if typeof(event.Delay) == "number" then
					rocketFx(muzzle, target, color, event.Delay)
				else
					local tracers = if typeof(event.Tracers) == "table" then event.Tracers else { { To = target, Hit = event.Miss ~= true } }
					local first = true
					for _, line in tracers do
						if typeof(line) == "table" and typeof(line.To) == "Vector3" then
							local to = line.To :: Vector3
							arrowFx(muzzle, to, color, if gun == "Sniper" then 1.3 elseif gun == "Shotgun" then 0.75 else 1)
							if isBow and first then
								emitAt("Glint", to, color, 4)
							end
							if line.Hit == true then
								emitAt("Spark", to, color, if gun == "Shotgun" then 2 else 5)
							else
								emitAt("Miss", to, Color3.fromRGB(200, 200, 200), 2)
							end
							first = false
						end
					end
					if combo then
						comboLabel(target, combo, color)
						flashBall(target, Color3.new(1, 1, 1), 0.6, 4, 0.18)
					end
					chainFx(target)
					impact()
				end
			end
		elseif event.Kind == "ShotImpact" and typeof(event.Position) == "Vector3" then
			-- Explosión del cohete de la bazuca
			local def = WeaponConfig.Weapons[event.WeaponId] or WeaponConfig.Weapons[WeaponConfig.StarterWeapon]
			local center = event.Position :: Vector3
			local radius = tonumber(event.Radius) or 8
			local crit = event.Crit == true
			flashBall(center, Color3.fromRGB(255, 220, 140), 1.5, radius * 1.5, 0.3)
			flashBall(center, def.Color, 1, radius * 1.9, 0.42)
			impactRing(center, radius, def.Color)
			emitAt("Spark", center, Color3.fromRGB(255, 190, 90), 24)
			emitAt("Miss", center, Color3.fromRGB(110, 110, 116), 8)
			playStyleSound("Explosion", if isOwner then nil else center)
			showHits(event.Hits, if crit then THEME.Gold else def.Color, isOwner, 1, if crit then 1.6 else nil)
			if isOwner and typeof(event.Hits) == "table" and #event.Hits > 0 then
				local killed = false
				for _, hit in event.Hits do
					killed = killed or (typeof(hit) == "table" and hit.Killed == true)
				end
				CombatHud.hitMarker(killed)
				if killed then
					playVaried(killSound, 0.9, 0.05)
				end
			end
		elseif event.Kind == "Blocked" and typeof(event.Position) == "Vector3" then
			-- Golpe bloqueado con la espada (sin parada): chispas y choque de metal
			local at = event.Position :: Vector3
			flashBall(at, Color3.new(1, 1, 1), 0.5, 2.6, 0.12)
			emitAt("Spark", at, Color3.fromRGB(210, 225, 255), 10)
			playStyleSound("SwordHit", if isOwner then nil else at, 0.7)
		elseif event.Kind == "Parry" and typeof(event.Position) == "Vector3" then
			-- Parada perfecta del Guerrero: destello blanco, chispas doradas
			local at = event.Position :: Vector3
			flashBall(at, Color3.new(1, 1, 1), 1, 7, 0.25)
			emitAt("Spark", at, THEME.Gold, 22)
			impactRing(at, 5, THEME.Gold)
			comboLabel(at, "¡Parada perfecta!", THEME.Gold)
			playStyleSound("Parry", if isOwner then nil else at)
		elseif event.Kind == "Charging" then
			-- Otro mago cargando un orbe: crece en su bastón (el tuyo lo dibuja tu cliente)
			if isOwner then
				return
			end
			local previous = othersCharging[owner]
			if previous then
				previous:Destroy()
			end
			local elementSpec = if typeof(event.Element) == "string" then StyleConfig.Styles.Magic.Elements[event.Element] else nil
			local color = if elementSpec and elementSpec.Color then elementSpec.Color else StyleConfig.Styles.Magic.Color
			local orb = fxPart(Vector3.one * 0.6, CFrame.new(), color)
			orb.Shape = Enum.PartType.Ball
			orb.Transparency = 0.2
			othersCharging[owner] = orb
			local began = os.clock()
			local full = StyleConfig.Styles.Magic.Charge.Full
			local connection
			connection = RunService.RenderStepped:Connect(function()
				local character = owner.Character
				local at = CharacterPose.gearPoint(character, "Orb") or CharacterPose.handPosition(character)
				local elapsed = os.clock() - began
				if not orb.Parent or othersCharging[owner] ~= orb or elapsed > full + 2.5 or not at then
					connection:Disconnect()
					if orb.Parent then
						orb:Destroy()
					end
					if othersCharging[owner] == orb then
						othersCharging[owner] = nil
					end
					return
				end
				local fraction = math.clamp(elapsed / full, 0, 1)
				orb.Size = Vector3.one * (0.6 + 2.8 * fraction)
				orb.CFrame = CFrame.new(at)
			end)
		elseif event.Kind == "FoxBolt" and typeof(event.Target) == "Vector3" then
			-- Rayo turquesa desde el zorrito hasta el objetivo (daño ya aplicado).
			-- Bola de luz con estela; tarda según la distancia para que se vea el recorrido.
			local from = petPosition(owner, tostring(event.PetId or "QuartzFox"), tonumber(event.Index) or 1) or event.Target
			local target = event.Target :: Vector3
			local travel = math.clamp((target - from).Magnitude / 70, 0.12, 0.3)
			local bolt = fxPart(Vector3.one * 0.6, CFrame.new(from), FOX_COLOR)
			bolt.Shape = Enum.PartType.Ball
			local tail = Instance.new("Attachment")
			tail.Position = Vector3.new(0, 0.22, 0)
			tail.Parent = bolt
			local head = Instance.new("Attachment")
			head.Position = Vector3.new(0, -0.22, 0)
			head.Parent = bolt
			local trail = Instance.new("Trail")
			trail.Attachment0 = tail
			trail.Attachment1 = head
			trail.Lifetime = 0.14
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(Color3.new(1, 1, 1), FOX_COLOR)
			trail.Transparency = NumberSequence.new(0.1, 1)
			trail.Parent = bolt
			emitAt("Glint", from, FOX_COLOR, 3)
			local tween = TweenService:Create(bolt, TweenInfo.new(travel, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { CFrame = CFrame.new(target) })
			tween.Completed:Once(function()
				bolt:Destroy()
				emitAt("Glint", target, FOX_COLOR, 4)
				showPetHits(event.Hits, FOX_COLOR, isOwner)
			end)
			tween:Play()
			Debris:AddItem(bolt, travel + 0.3)
		elseif event.Kind == "DragonCast" and typeof(event.Center) == "Vector3" and typeof(event.Radius) == "number" then
			-- Aviso previo: círculo violeta que se llena hasta el impacto.
			local telegraph = if typeof(event.Telegraph) == "number" then event.Telegraph else 0.8
			local center = Vector3.new(event.Center.X, event.Center.Y - 2.5, event.Center.Z)
			local diameter = event.Radius * 2
			local ring = fxPart(Vector3.new(0.1, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), DRAGON_COLOR)
			ring.Shape = Enum.PartType.Cylinder
			ring.Transparency = 0.7
			local fill = fxPart(Vector3.new(0.12, 0.5, 0.5), CFrame.new(center + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)), DRAGON_COLOR)
			fill.Shape = Enum.PartType.Cylinder
			fill.Transparency = 0.55
			TweenService:Create(fill, TweenInfo.new(telegraph, Enum.EasingStyle.Linear), { Size = Vector3.new(0.12, diameter, diameter) }):Play()
			Debris:AddItem(ring, telegraph + 0.1)
			Debris:AddItem(fill, telegraph + 0.1)
			local from = petPosition(owner, "AmethystDragon", tonumber(event.Index) or 1)
			if from then
				emitAt("Glint", from, DRAGON_COLOR, 8) -- el dragón carga la habilidad
			end
			if isOwner and typeof(event.ReadyAt) == "number" then
				startDragonCooldown(event.ReadyAt)
			end
		elseif event.Kind == "DragonImpact" and typeof(event.Center) == "Vector3" and typeof(event.Radius) == "number" then
			local center = Vector3.new(event.Center.X, event.Center.Y - 2.3, event.Center.Z)
			local diameter = event.Radius * 2
			local wave = fxPart(Vector3.new(0.2, diameter * 0.5, diameter * 0.5), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), DRAGON_COLOR)
			wave.Shape = Enum.PartType.Cylinder
			wave.Transparency = 0.3
			TweenService:Create(wave, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, diameter * 1.1, diameter * 1.1), Transparency = 1 }):Play()
			Debris:AddItem(wave, 0.45)
			emitAt("Glint", event.Center, DRAGON_COLOR, 14)
			showPetHits(event.Hits, DRAGON_COLOR, isOwner)
			if isOwner then
				playVaried(novaSound, 1.5, 0.05)
			end
		elseif event.Kind == "TurtleBlock" then
			-- Escudo de la tortuga: burbuja breve alrededor del jugador protegido.
			local character = owner.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local bubble = fxPart(Vector3.one * 6.5, root.CFrame, GUARD_COLOR)
				bubble.Shape = Enum.PartType.Ball
				bubble.Material = Enum.Material.ForceField
				bubble.Transparency = 0.2
				TweenService:Create(bubble, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.one * 7.5 }):Play()
				Debris:AddItem(bubble, 0.45)
				if isOwner and typeof(event.Blocked) == "number" and event.Blocked >= 0.5 then
					damageNumber(root.Position + Vector3.new(0, 1, 0), event.Blocked, GUARD_COLOR, false)
				end
			end
		end
	end)
end

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	GUN_FEEL = context.GUN_FEEL
	PUNCH_REACH = context.PUNCH_REACH
	THEME = context.THEME
	player = context.player
end

return Part
