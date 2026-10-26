-- Estilos de pelea (StyleConfig): elegir estilo, sus pasivas fuera del disparo, sus
-- habilidades (4 por estilo, 2 puestas: SkillLogic), los combos, el dash de Puños y el
-- teletransporte de Magia. El
-- disparo de cada estilo (alcance, ritmo, daño, crítico, robo de vida y los combos de golpes)
-- lo hace PetCombatService; aquí:
-- - StyleAction("Set", styleId): cambia el estilo (con una espera corta entre cambios), se
--   guarda en PetData.Style y se replica (atributo CombatStyle; la velocidad al caminar y la
--   vida las pone PlayerDataService con StyleLogic).
-- - StyleAction("Pick", styleId): la elección del estilo al empezar (StylePicker): lo pone y
--   marca PetData.Skills.Picked (ya no se vuelve a preguntar).
-- - StyleAction("Ability", slot, aimPoint): usa la habilidad puesta en la Z (1) o la X (2)
--   si está lista, hacia el punto al que apuntas (el ratón; con el botón, delante). Todo lo
--   decide el servidor:
--     Armas:  Ráfaga, Granada (cae donde apuntas), Rayo perforante (franja recta hacia donde
--             apuntas) y Torreta (dispara sola al más cercano un rato).
--     Guerrero: Giro de acero (tajos alrededor), Salto aplastante (HANDLERS.Leap: saltas
--             hacia donde apuntas y al caer golpeas, aturdes y empujas alrededor), Grito de
--             guerra (como la Furia, y pegas más fuerte) y Onda cortante (franja recta).
--     Puños:  Terremoto, Embestida, Furia (pegas más rápido y recibes la mitad) y Torbellino
--             (4 golpes alrededor que atraen).
--     Magia:  Meteoros (donde apuntas), Nova de hielo, Cadena de rayos (empieza en el enemigo
--             junto a donde apuntas, salta de enemigo en enemigo y aturde) y Agujero negro
--             (donde apuntas: atrae y daña, y al final explota).
--   Las de Magia gastan maná (ManaCost; sin maná: Result "NoMana"). Una habilidad con Base
--   usa el efecto de otra (también en cadena: la del Mundo 2 sobre la del Mundo 1).
--   El daño son múltiplos del DPS del estilo × el nivel de la habilidad (SkillLogic.power)
--   y pasa por EnemyService.damage (mismas recompensas y muertes). La recarga es por
--   habilidad (cambiar de estilo o de hueco no la reinicia; la acorta su nivel) y se replica
--   en StyleReadyAt (Z) y StyleReadyAt2 (X).
-- - StyleAction("BuySkill" | "UpgradeSkill", skillId) y ("EquipSkill", skillId, slot):
--   comprar y subir con 💎 (profile.Energy) y ponerla en la Z o la X (SkillLogic valida).
-- - StyleAction("Dash"): el dash de Puños (StyleConfig.Styles.Fists.Dash): un salto corto
--   hacia donde te mueves, sin cruzar paredes ni puertas cerradas; DashReadyAt.
-- - StyleAction("Blink", aimPoint): el teletransporte de Magia (StyleConfig.Styles.Magic.Blink)
--   hacia el punto (o hacia donde te mueves), gasta maná y comparte DashReadyAt.
-- - Combos de habilidades (COMBO): una habilidad que da a un enemigo aturdido o congelado
--   (Terremoto, Embestida, Nova, Cadena de rayos) hace ×1.5 («¡Remate!», «¡Hielo roto!»…);
--   con tu Ráfaga o tu Furia activas, las demás habilidades hacen ×1.4; y a un enemigo con
--   la marca de un elemento (las habilidades elementales Q/R, AbilityService) le hace ×1.5 y
--   gasta la marca («¡Combo elemental!»). Se multiplican, hasta ×COMBO.Max.
-- - Daño que recibe el jugador según el estilo (Puños y Guerrero menos, Armas más; la Furia,
--   la mitad; bloqueando con el Guerrero, PetCombatService.blockIncoming).
-- - Clases (ClassConfig, ClassLogic): StyleAction("BuyClass" | "UpgradeClass", classId) y
--   ("SelectClass", classId): comprar y subir con 💎 y elegir la activa de su estilo. Sus
--   pasivas, aquí: daño y recarga de las habilidades, recarga del dash, daño que recibes y
--   daño a los jefes (gancho de EnemyService); las demás en PetCombatService y PlayerDataService.
-- - StyleEvent: efectos ya resueltos a quien la usa y a los cercanos; "Result" solo a él.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)
local StyleLogic = require(Shared.StyleLogic)
local SkillLogic = require(Shared.SkillLogic)
local ClassLogic = require(Shared.ClassLogic)
local MagicLogic = require(Shared.MagicLogic)
local AbilityLogic = require(Shared.AbilityLogic)
local CaveLogic = require(Shared.CaveLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local EnemyService = require(script.Parent.EnemyService)
local CombatService = require(script.Parent.CombatService)
local PetCombatService = require(script.Parent.PetCombatService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local BROADCAST_RANGE = 150
local DASH_STEP = 2 -- la embestida se comprueba cada tantos studs (suelo y puertas)
local DASH_WALL_GAP = 2.5 -- se para a esta distancia de una pared
local CHAIN_AIM = 12 -- la Cadena de rayos empieza en un enemigo a esto (o menos) de donde apuntas
local MAX_AIM_DISTANCE = 400
local SLOT_ATTRIBUTES = { Constants.Attributes.StyleReadyAt, Constants.Attributes.StyleReadyAt2 }
local Codes = Constants.PurchaseCodes

-- Combos de las habilidades (ver la cabecera)
local COMBO = {
	Stunned = 1.5, -- a un enemigo aturdido o congelado
	Buffed = 1.4, -- con tu Ráfaga o tu Furia activas
	Element = 1.5, -- a un enemigo con marca elemental (la gasta)
	Max = 2.5,
	Names = {
		Stunned = { Weapons = "¡Tiro certero!", Warrior = "¡Golpe de gracia!", Fists = "¡Remate!", Magic = "¡Hielo roto!" },
		Buffed = { Weapons = "¡Ráfaga cargada!", Warrior = "¡Furia guerrera!", Fists = "¡Furia desatada!", Magic = "¡Poder arcano!" },
		Element = "¡Combo elemental!",
	},
}

local StyleService = {}

local eventRemote: RemoteEvent
local limiter = RateLimiter.new(0.15, 3, 8)
local shopLimiter = RateLimiter.new(0.25, 3, 10)
local lastSwitch: { [Player]: number } = {}
local readyAt: { [Player]: { [string]: number } } = {}
local buffUntil: { [Player]: number } = {} -- Ráfaga o Furia activa (os.clock)
local rageUntil: { [Player]: number } = {} -- Furia: recibes menos daño
local rageTaken: { [Player]: number } = {}
local dashReadyAt: { [Player]: number } = {}
local generation: { [Player]: number } = {} -- cambia al salir o morir: anula lo pendiente

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

-- Punto apuntado que manda el cliente con la habilidad (nil si no vale)
local function validAim(player: Player, aim: any): Vector3?
	local root = rootOf(player)
	if typeof(aim) ~= "Vector3" or not root then
		return nil
	end
	for _, value in { aim.X, aim.Y, aim.Z } do
		if value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
	end
	return if (aim - root.Position).Magnitude <= MAX_AIM_DISTANCE then aim else nil
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function broadcast(owner: Player, origin: Vector3, event: { [string]: any })
	event.Owner = owner
	for _, player in Players:GetPlayers() do
		local root = if player == owner then nil else rootOf(player)
		if player == owner or (root and (root.Position - origin).Magnitude <= BROADCAST_RANGE) then
			eventRemote:FireClient(player, event)
		end
	end
end

local function result(player: Player, data: { [string]: any })
	data.Kind = "Result"
	data.Owner = player
	eventRemote:FireClient(player, data)
end

local function styleOf(player: Player): (string?, any)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil, nil
	end
	return StyleLogic.sanitize(profile.PetData.Style), profile
end

local function skillsOf(profile): SkillLogic.SkillData
	local skills = profile.PetData.Skills
	if not skills then
		skills = SkillLogic.empty()
		profile.PetData.Skills = skills
	end
	return skills
end

local function classesOf(profile): ClassLogic.ClassData
	local classes = profile.PetData.Classes
	if not classes then
		classes = ClassLogic.empty()
		profile.PetData.Classes = classes
	end
	return classes
end

-- Pasivas de la clase activa del estilo actual del jugador (neutras sin datos)
local function classModsOf(player: Player): ClassLogic.Mods
	local profile = PlayerDataService.get(player)
	if not profile then
		return ClassLogic.neutral()
	end
	return ClassLogic.mods(profile.PetData.Classes, StyleLogic.sanitize(profile.PetData.Style))
end
StyleService.classModsOf = classModsOf

-- DPS del estilo (con el arma, la cadencia, mascotas y bonificaciones)
local function styleDps(profile, style: string): number
	local stats = PlayerDataService.combatStats(profile)
	return StyleLogic.dps(stats.Dps, style)
end

-- Lo que comparten los golpes de una habilidad: quién, su estilo y su nivel, y el primer
-- combo que salta (para avisarlo una vez).
type Cast = {
	Player: Player,
	Style: string,
	SkillId: string,
	Damage: number, -- daño base de cada golpe (DPS × DamageRatio × nivel)
	Buffed: boolean,
	Color: Color3?, -- el de sus efectos (las del Mundo 2 traen el suyo)
	Aim: Vector3?, -- punto al que apuntaba el jugador al usarla (ratón, toque o delante)
	Element: string?, -- Magia: deja su marca elemental y dispara combos (AbilityService)
	Combo: string?,
	ComboAt: Vector3?,
}

-- Multiplicador de los combos para un golpe de la habilidad a `enemy` (y su nombre).
local function comboFor(cast: Cast, enemy: any, ignoreStun: boolean?): (number, string?)
	local multiplier, name = 1, nil
	if not ignoreStun and EnemyService.isStunned(enemy) then
		multiplier *= COMBO.Stunned
		name = COMBO.Names.Stunned[cast.Style]
	end
	if cast.Buffed then
		multiplier *= COMBO.Buffed
		name = name or COMBO.Names.Buffed[cast.Style]
	end
	if cast.Element then
		-- Habilidades de Magia: su elemento deja marca o dispara el combo de la pareja
		multiplier *= PetCombatService.elementHit(cast.Player, enemy, cast.Element, cast.Damage)
	else
		local aura = EnemyService.auraOf(enemy)
		if aura then
			multiplier *= COMBO.Element
			name = COMBO.Names.Element
			EnemyService.setAura(enemy, nil) -- se gasta
		end
	end
	return math.min(multiplier, COMBO.Max), name
end

-- Un golpe de la habilidad a un enemigo (cuenta como golpe del jugador para su objetivo).
-- `scale`: parte del daño base (los golpes de cada momento del agujero negro).
local function hit(cast: Cast, enemy: any, hits: { any }, scale: number?, ignoreStun: boolean?): boolean
	local multiplier, name = comboFor(cast, enemy, ignoreStun)
	local dealt, killed = EnemyService.damage(enemy, cast.Player, cast.Damage * (scale or 1) * multiplier)
	if dealt > 0 then
		table.insert(hits, { Position = enemy.Root.Position, Damage = dealt, Killed = killed, Kind = enemy.Kind, Combo = name })
		if name and not cast.Combo then
			cast.Combo = name
			cast.ComboAt = enemy.Root.Position
		end
		if not killed then
			CombatService.reportHit(cast.Player, enemy)
		end
	end
	return killed
end

-- Aviso del combo (una vez por habilidad)
local function announceCombo(cast: Cast)
	if cast.Combo and cast.ComboAt then
		broadcast(cast.Player, cast.ComboAt, { Kind = "Combo", Name = cast.Combo, Position = cast.ComboAt, Style = cast.Style })
		cast.ComboAt = nil
	end
end

-- El color de los efectos de la habilidad va en cada aviso al cliente (si tiene uno propio)
local function fx(cast: Cast, event: { [string]: any }): { [string]: any }
	if cast.Color then
		event.Color = cast.Color
	end
	return event
end

-- Enemigos válidos alrededor de `center` para el jugador
local function targetsAround(player: Player, center: Vector3, radius: number, maxTargets: number): { any }
	local list = {}
	for _, enemy in EnemyService.findInRadius(center, radius, maxTargets, player) do
		if EnemyService.canInteract(player, enemy) then
			table.insert(list, enemy)
		end
	end
	return list
end

local function nearestTarget(player: Player, center: Vector3, range: number): any?
	return targetsAround(player, center, range, 1)[1]
end

-- Punto apuntado para la habilidad, sin pasar de `range` desde el personaje (nil si no apuntó).
-- A la altura del suelo apuntado si está cerca de la tuya; si no, a la tuya.
local function aimedPoint(cast: Cast, root: BasePart, range: number): Vector3?
	local aim = cast.Aim
	if not aim then
		return nil
	end
	local origin = root.Position
	local flat = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
	if flat.Magnitude > range then
		flat = flat.Unit * range
	end
	local y = if math.abs(aim.Y - origin.Y) <= 12 then aim.Y + 1 else origin.Y
	return Vector3.new(origin.X + flat.X, y, origin.Z + flat.Z)
end

-- Dirección (en plano) hacia el punto apuntado; nil si no apuntó o está encima
local function aimedDirection(cast: Cast, root: BasePart): Vector3?
	local aim = cast.Aim
	if not aim then
		return nil
	end
	local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
	return if flat.Magnitude > 0.5 then flat.Unit else nil
end

-- Atrae a `enemy` hacia `center` (el retroceso de EnemyService, hacia dentro)
local function pull(enemy: any, center: Vector3, force: number)
	local position = enemy.Root.Position
	local away = Vector3.new(position.X - center.X, 0, position.Z - center.Z)
	if away.Magnitude < 1.5 then
		return
	end
	EnemyService.knockback(enemy, position + away.Unit * 2, force)
end

-- Hasta dónde se puede ir desde `origin` hacia `direction`: sin atravesar paredes, sin
-- salirse del suelo y sin cruzar una puerta cerrada de la cueva.
local function dashReach(player: Player, origin: Vector3, direction: Vector3, distance: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local enemies = Workspace:FindFirstChild("Enemies")
	if enemies then
		table.insert(ignore, enemies)
	end
	params.FilterDescendantsInstances = ignore
	local limit = distance
	-- A la altura del cuerpo y a la de las rodillas (rocas bajas)
	for _, height in { 0, -1.6 } do
		local start = origin + Vector3.new(0, height, 0)
		local wall = Workspace:Raycast(start, direction * distance, params)
		if wall then
			limit = math.min(limit, math.max(0, (wall.Position - start).Magnitude - DASH_WALL_GAP))
		end
	end
	local progress = CaveLogic.parseProgress(player:GetAttribute(Constants.Attributes.CaveGates))
	local reach = 0
	local step = DASH_STEP
	while step <= limit + 1e-6 do
		local point = origin + direction * step
		local ahead = origin + direction * (step + 2) -- el cuerpo no se mete en la puerta
		local blocked = CaveLogic.inside(ahead.X, ahead.Z) and CaveLogic.blockedAt(ahead.X, ahead.Z, progress) ~= nil
		local ground = Workspace:Raycast(point, Vector3.new(0, -10, 0), params)
		if blocked or not ground then
			break
		end
		reach = step
		step += DASH_STEP
	end
	return reach
end

-- Hacia donde se mueve el personaje (o hacia donde mira si está quieto), en plano
local function moveDirection(player: Player, root: BasePart): Vector3
	local character = player.Character :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local move = humanoid.MoveDirection
	local look = root.CFrame.LookVector
	local direction = if move.Magnitude > 0.1 then Vector3.new(move.X, 0, move.Z) else Vector3.new(look.X, 0, look.Z)
	return if direction.Magnitude > 0.05 then direction.Unit else Vector3.new(0, 0, -1)
end

local function stun(enemy: any, seconds: number)
	if EnemyService.isAlive(enemy) then
		EnemyService.applyControl(enemy, "Stun", (AbilityLogic.control("Stun", seconds, nil, enemy.Kind == "Boss")))
	end
end

-- Habilidades ----------------------------------------------------------------------------
-- Cada una: (cast, ability, root, level) -> true si se ha usado (false: sin objetivo).

local HANDLERS = {}

-- Armas: Ráfaga
function HANDLERS.Burst(cast: Cast, ability: any, root: BasePart, level: number): boolean
	local player = cast.Player
	local duration = SkillLogic.duration(ability, level)
	PetCombatService.setBurst(player, os.clock() + duration, ability.CooldownScale)
	buffUntil[player] = os.clock() + duration
	player:SetAttribute(Constants.Attributes.StyleBurstUntil, serverNow() + duration)
	broadcast(player, root.Position, fx(cast, { Kind = "Burst", Duration = duration }))
	return true
end

-- Armas: Granada (vuela hasta donde apuntas y explota al llegar). Count (Bombardeo): la
-- primera donde apuntas y las demás en corro alrededor, una detrás de otra. Sin punto
-- (clientes antiguos), a los enemigos más cercanos.
function HANDLERS.Grenade(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local count = math.max(1, math.floor(ability.Count or 1))
	local landings = {}
	local aimed = aimedPoint(cast, root, ability.Range)
	if aimed then
		table.insert(landings, aimed)
		local ring = ability.Radius * 1.2
		for index = 2, count do
			local angle = (index - 2) / math.max(1, count - 1) * math.pi * 2
			table.insert(landings, aimed + Vector3.new(math.cos(angle) * ring, 0, math.sin(angle) * ring))
		end
	else
		for _, target in targetsAround(player, root.Position, ability.Range, count) do
			table.insert(landings, target.Root.Position)
		end
	end
	if #landings == 0 then
		return false
	end
	local token = generation[player] or 0
	for index, landing in landings do
		local delay = ability.Delay + (index - 1) * 0.1
		broadcast(player, root.Position, fx(cast, {
			Kind = "Grenade",
			From = root.Position + Vector3.new(0, 1.5, 0),
			To = landing,
			Delay = delay,
			Radius = ability.Radius,
		}))
		task.delay(delay, function()
			if not player.Parent or (generation[player] or 0) ~= token then
				return
			end
			local hits = {}
			for _, enemy in targetsAround(player, landing, ability.Radius, ability.MaxTargets) do
				local killed = hit(cast, enemy, hits)
				if not killed and EnemyService.isAlive(enemy) then
					EnemyService.knockback(enemy, landing, ability.Knockback)
				end
			end
			broadcast(player, landing, fx(cast, { Kind = "GrenadeHit", Position = landing, Radius = ability.Radius, Hits = hits }))
			announceCombo(cast)
		end)
	end
	return true
end

-- Armas: Rayo perforante (franja recta hacia donde apuntas; sin punto, hacia el más cercano)
function HANDLERS.Pierce(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local origin = root.Position
	local aim = aimedDirection(cast, root)
	if not aim then
		local target = nearestTarget(player, origin, ability.Length)
		if not target then
			return false
		end
		local toward = target.Root.Position - origin
		local flat = Vector3.new(toward.X, 0, toward.Z)
		aim = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
	end
	assert(aim, "dirección del rayo")
	-- Beams (Rayo triple): varios rayos en abanico, Spread grados entre uno y otro; cada
	-- enemigo recibe como mucho un rayo
	local beams = math.max(1, math.floor(ability.Beams or 1))
	local struck = {}
	for beam = 1, beams do
		local angle = math.rad((beam - (beams + 1) / 2) * (ability.Spread or 0))
		local direction = (CFrame.Angles(0, angle, 0) * aim).Unit
		local finish = origin + direction * ability.Length
		local hits = {}
		local middle = (origin + finish) / 2
		for _, enemy in targetsAround(player, middle, ability.Length / 2 + ability.Width, ability.MaxTargets * 2) do
			if #hits >= ability.MaxTargets then
				break
			end
			local p = enemy.Root.Position
			if not struck[enemy] and StyleLogic.inStrip(origin.X, origin.Z, finish.X, finish.Z, ability.Width / 2, p.X, p.Z, enemy.Radius) then
				struck[enemy] = true
				hit(cast, enemy, hits)
			end
		end
		broadcast(player, origin, fx(cast, { Kind = ability.Visual or "Pierce", From = origin + Vector3.new(0, 1.2, 0), To = finish + Vector3.new(0, 1.2, 0), Width = ability.Width, Hits = hits }))
	end
	announceCombo(cast)
	return true
end

-- Armas: Torreta (dispara sola al más cercano mientras dura)
function HANDLERS.Turret(cast: Cast, ability: any, root: BasePart, level: number): boolean
	local player = cast.Player
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local base = root.Position + (if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)) * 3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local floor = Workspace:Raycast(base + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
	local spot = if floor then floor.Position else base - Vector3.new(0, 2.5, 0)
	local duration = SkillLogic.duration(ability, level)
	local token = generation[player] or 0
	local gun = spot + Vector3.new(0, 2.6, 0)
	broadcast(player, spot, fx(cast, { Kind = "Turret", Position = spot, Duration = duration }))
	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			task.wait(ability.Interval)
			elapsed += ability.Interval
			if not player.Parent or (generation[player] or 0) ~= token then
				break
			end
			local target = nearestTarget(player, gun, ability.Range)
			if target then
				local hits = {}
				hit(cast, target, hits)
				broadcast(player, gun, fx(cast, { Kind = "TurretShot", From = gun, To = target.Root.Position, Hits = hits }))
				announceCombo(cast)
			end
		end
		broadcast(player, spot, fx(cast, { Kind = "TurretEnd", Position = spot }))
	end)
	return true
end

-- Puños: Terremoto. Waves (Terremoto titán): varios golpes seguidos donde lo usaste, cada uno
-- un 35 % más grande.
local function quakeWave(cast: Cast, ability: any, center: Vector3, radius: number)
	local hits = {}
	for _, enemy in targetsAround(cast.Player, center, radius, ability.MaxTargets) do
		local killed = hit(cast, enemy, hits)
		if not killed and EnemyService.isAlive(enemy) then
			stun(enemy, ability.Stun)
			EnemyService.knockback(enemy, center, ability.Knockback)
		end
	end
	broadcast(cast.Player, center, fx(cast, { Kind = "Quake", Position = center, Radius = radius, Hits = hits }))
	announceCombo(cast)
end

function HANDLERS.Quake(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local center = root.Position
	quakeWave(cast, ability, center, ability.Radius)
	local waves = math.max(1, math.floor(ability.Waves or 1))
	if waves > 1 then
		local token = generation[player] or 0
		task.spawn(function()
			local radius = ability.Radius
			for _ = 2, waves do
				task.wait(ability.WaveInterval or 0.35)
				if not player.Parent or (generation[player] or 0) ~= token then
					return
				end
				radius *= 1.35
				quakeWave(cast, ability, center, radius)
			end
		end)
	end
	return true
end

-- Puños: Embestida
function HANDLERS.Dash(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local character = player.Character :: Model
	local direction = moveDirection(player, root)
	local origin = root.Position
	local reach = dashReach(player, origin, direction, ability.Distance)
	local finish = origin + direction * reach
	local hits = {}
	local middle = (origin + finish) / 2
	for _, enemy in targetsAround(player, middle, reach / 2 + ability.Width, ability.MaxTargets * 2) do
		if #hits >= ability.MaxTargets then
			break
		end
		local p = enemy.Root.Position
		if StyleLogic.inStrip(origin.X, origin.Z, finish.X, finish.Z, ability.Width / 2, p.X, p.Z, enemy.Radius) then
			local killed = hit(cast, enemy, hits)
			if not killed and EnemyService.isAlive(enemy) then
				stun(enemy, ability.Stun)
				-- Se apartan a los lados de tu camino
				local along = math.clamp((p - origin):Dot(direction), 0, reach)
				EnemyService.knockback(enemy, origin + direction * along, ability.Knockback)
			end
		end
	end
	if reach > 0 then
		character:PivotTo(CFrame.lookAt(finish, finish + direction))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	broadcast(player, origin, fx(cast, { Kind = "Dash", From = origin, To = finish, Hits = hits }))
	-- EndRadius (Cometa): al llegar, explota alrededor (EndRatio × DPS)
	if ability.EndRadius then
		local blast = {}
		local scale = (ability.EndRatio or ability.DamageRatio) / math.max(0.01, ability.DamageRatio)
		for _, enemy in targetsAround(player, finish, ability.EndRadius, ability.MaxTargets) do
			local killed = hit(cast, enemy, blast, scale)
			if not killed and EnemyService.isAlive(enemy) then
				EnemyService.knockback(enemy, finish, ability.Knockback)
			end
		end
		broadcast(player, finish, fx(cast, { Kind = "Quake", Position = finish, Radius = ability.EndRadius, Hits = blast }))
	end
	announceCombo(cast)
	return true
end

-- Guerrero: Salto aplastante (saltas hacia donde apuntas y caes con un golpe en área). El
-- cliente del jugador hace el salto (StyleController); al caer, si no llegó, se le pone allí.
function HANDLERS.Leap(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local origin = root.Position
	local direction = aimedDirection(cast, root) or moveDirection(player, root)
	local wanted = ability.Distance
	if cast.Aim then
		local flat = Vector3.new(cast.Aim.X - origin.X, 0, cast.Aim.Z - origin.Z)
		wanted = math.clamp(flat.Magnitude, 4, ability.Distance)
	end
	local reach = dashReach(player, origin, direction, wanted)
	local landing = origin + direction * reach
	local delay = ability.Delay or 0.55
	local token = generation[player] or 0
	broadcast(player, origin, fx(cast, { Kind = "Leap", From = origin, To = landing, Delay = delay, Radius = ability.Radius }))
	task.delay(delay, function()
		if not player.Parent or (generation[player] or 0) ~= token then
			return
		end
		local here = rootOf(player)
		if not here then
			return
		end
		if (here.Position - landing).Magnitude > 8 then
			(player.Character :: Model):PivotTo(CFrame.lookAt(landing, landing + direction))
		end
		local hits = {}
		for _, enemy in targetsAround(player, landing, ability.Radius, ability.MaxTargets) do
			local killed = hit(cast, enemy, hits)
			if not killed and EnemyService.isAlive(enemy) then
				stun(enemy, ability.Stun)
				EnemyService.knockback(enemy, landing, ability.Knockback)
			end
		end
		broadcast(player, landing, fx(cast, { Kind = "Quake", Position = landing, Radius = ability.Radius, Hits = hits }))
		announceCombo(cast)
	end)
	return true
end

-- Puños: Furia (pegas más rápido y recibes la mitad de daño)
function HANDLERS.Rage(cast: Cast, ability: any, root: BasePart, level: number): boolean
	local player = cast.Player
	local duration = SkillLogic.duration(ability, level)
	local untilClock = os.clock() + duration
	PetCombatService.setBurst(player, untilClock, ability.CooldownScale, ability.DamageBoost)
	buffUntil[player] = untilClock
	rageUntil[player] = untilClock
	rageTaken[player] = ability.DamageTaken or 0.5
	player:SetAttribute(Constants.Attributes.StyleRageUntil, serverNow() + duration)
	broadcast(player, root.Position, fx(cast, { Kind = "Rage", Duration = duration }))
	return true
end

-- Puños: Torbellino (varios golpes alrededor que atraen hacia ti)
function HANDLERS.Whirlwind(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local token = generation[player] or 0
	broadcast(player, root.Position, fx(cast, { Kind = "Whirl", Radius = ability.Radius, Pulses = ability.Pulses, Interval = ability.Interval }))
	task.spawn(function()
		for pulse = 1, ability.Pulses do
			if pulse > 1 then
				task.wait(ability.Interval)
			end
			local here = rootOf(player)
			if not here or (generation[player] or 0) ~= token then
				return
			end
			local hits = {}
			for _, enemy in targetsAround(player, here.Position, ability.Radius, ability.MaxTargets) do
				local killed = hit(cast, enemy, hits)
				if not killed and EnemyService.isAlive(enemy) and pulse < ability.Pulses then
					pull(enemy, here.Position, ability.Pull)
				end
			end
			broadcast(player, here.Position, fx(cast, { Kind = "WhirlHit", Position = here.Position, Radius = ability.Radius, Hits = hits }))
			announceCombo(cast)
		end
	end)
	return true
end

-- Magia: Meteoros (caen donde apuntas; sin punto, sobre el más cercano)
function HANDLERS.Meteors(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local center = aimedPoint(cast, root, ability.Range)
	if not center then
		local target = nearestTarget(player, root.Position, ability.Range)
		if not target then
			return false -- sin nadie a tiro no se gasta
		end
		center = target.Root.Position
	end
	assert(center, "centro de los meteoros")
	local points = {}
	for _, offset in StyleLogic.meteorOffsets(ability.Count, ability.Spread) do
		table.insert(points, center + Vector3.new(offset.X, 0, offset.Y))
	end
	local token = generation[player] or 0
	broadcast(player, root.Position, fx(cast, {
		Kind = "Meteor",
		Points = points,
		Delay = ability.Delay,
		Interval = ability.Interval,
		Radius = ability.Radius,
		StartAt = serverNow(),
	}))
	for index, point in points do
		task.delay(ability.Delay + (index - 1) * ability.Interval, function()
			if not player.Parent or (generation[player] or 0) ~= token then
				return
			end
			local hits = {}
			for _, enemy in targetsAround(player, point, ability.Radius, ability.MaxTargets) do
				hit(cast, enemy, hits)
			end
			broadcast(player, point, fx(cast, { Kind = "MeteorHit", Position = point, Radius = ability.Radius, Hits = hits }))
			announceCombo(cast)
		end)
	end
	return true
end

-- Magia: Nova de hielo (daña y congela alrededor)
function HANDLERS.Nova(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local hits, frozen = {}, {}
	for _, enemy in targetsAround(player, root.Position, ability.Radius, ability.MaxTargets) do
		local killed = hit(cast, enemy, hits)
		if not killed and EnemyService.isAlive(enemy) then
			local seconds = AbilityLogic.control("Stun", ability.Freeze, nil, enemy.Kind == "Boss")
			if EnemyService.applyControl(enemy, "Stun", seconds) then
				table.insert(frozen, { Model = enemy.Model, Seconds = seconds })
			end
		end
	end
	broadcast(player, root.Position, fx(cast, { Kind = "Nova", Position = root.Position, Radius = ability.Radius, Hits = hits, Frozen = frozen }))
	announceCombo(cast)
	return true
end

-- Magia: Cadena de rayos: empieza en el enemigo más cercano a donde apuntas (a CHAIN_AIM
-- studs o menos de ese punto, y a tu alcance) y salta al siguiente más cercano que aún no ha
-- tocado. Sin punto, empieza en el más cercano a ti.
function HANDLERS.ChainLightning(cast: Cast, ability: any, root: BasePart): boolean
	local player = cast.Player
	local current = nil
	local aimed = aimedPoint(cast, root, ability.Range)
	if aimed then
		for _, candidate in targetsAround(player, aimed, CHAIN_AIM, 6) do
			if (candidate.Root.Position - root.Position).Magnitude - (candidate.Radius or 0) <= ability.Range then
				current = candidate
				break
			end
		end
	else
		current = nearestTarget(player, root.Position, ability.Range)
	end
	if not current then
		return false
	end
	local points = { root.Position + Vector3.new(0, 1.5, 0) }
	local touched = {}
	local hits = {}
	for _ = 1, ability.Jumps do
		touched[current] = true
		table.insert(points, current.Root.Position)
		-- Primero el daño (el combo mira si ya estaba aturdido) y luego aturde
		local killed = hit(cast, current, hits)
		if not killed then
			stun(current, ability.Stun)
		end
		local nextEnemy = nil
		local best = math.huge
		for _, candidate in targetsAround(player, current.Root.Position, ability.JumpRange, 12) do
			if not touched[candidate] then
				local distance = (candidate.Root.Position - current.Root.Position).Magnitude
				if distance < best then
					best = distance
					nextEnemy = candidate
				end
			end
		end
		if not nextEnemy then
			break
		end
		current = nextEnemy
	end
	broadcast(player, root.Position, fx(cast, { Kind = "Lightning", Points = points, Hits = hits }))
	announceCombo(cast)
	return true
end

-- Magia: Agujero negro (atrae y daña un rato y luego explota)
function HANDLERS.BlackHole(cast: Cast, ability: any, root: BasePart, level: number): boolean
	local player = cast.Player
	local center = aimedPoint(cast, root, ability.Range)
	if not center then
		local target = nearestTarget(player, root.Position, ability.Range)
		if not target then
			return false
		end
		center = target.Root.Position
	end
	assert(center, "centro del agujero negro")
	local duration = SkillLogic.duration(ability, level)
	local token = generation[player] or 0
	local tickScale = (ability.TickRatio or 0.5) / math.max(0.01, ability.DamageRatio)
	broadcast(player, center, fx(cast, { Kind = "BlackHole", Position = center, Radius = ability.Radius, Duration = duration }))
	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			task.wait(ability.Interval)
			elapsed += ability.Interval
			if not player.Parent or (generation[player] or 0) ~= token then
				return
			end
			local hits = {}
			for _, enemy in targetsAround(player, center, ability.Radius, ability.MaxTargets) do
				local killed = hit(cast, enemy, hits, tickScale, true)
				if not killed and EnemyService.isAlive(enemy) then
					pull(enemy, center, ability.Pull)
				end
			end
			if #hits > 0 then
				broadcast(player, center, fx(cast, { Kind = "BlackHoleTick", Position = center, Hits = hits }))
			end
		end
		local hits = {}
		for _, enemy in targetsAround(player, center, ability.Radius, ability.MaxTargets) do
			hit(cast, enemy, hits)
		end
		broadcast(player, center, fx(cast, { Kind = "BlackHoleBlast", Position = center, Radius = ability.Radius, Hits = hits }))
		announceCombo(cast)
	end)
	return true
end

StyleService.Handlers = HANDLERS

local function useAbility(player: Player, slot: number, aim: Vector3?)
	local style, profile = styleOf(player)
	local root = rootOf(player)
	if not (style and profile and root) then
		return
	end
	local skills = skillsOf(profile)
	local ability, skillId = StyleLogic.ability(style, slot, skills)
	-- Las del Mundo 2 usan el efecto de una del Mundo 1 (Base), que a su vez puede usar el de
	-- otra (las del Guerrero: Giro de acero → Torbellino, Grito de guerra → Furia…)
	local baseId = if ability and ability.Base then ability.Base else skillId
	local baseDef = baseId and SkillLogic.definition(baseId)
	if baseId and not HANDLERS[baseId] and baseDef and baseDef.Base then
		baseId = baseDef.Base
	end
	local handler = baseId and HANDLERS[baseId]
	if not (ability and skillId and handler) then
		return
	end
	local level = math.max(1, SkillLogic.level(skills, skillId))
	local class = ClassLogic.mods(profile.PetData.Classes, style)
	local now = os.clock()
	local own = readyAt[player] or {}
	readyAt[player] = own
	if (own[skillId] or 0) > now then
		result(player, { Success = false, Code = "NotReady", Style = style, Slot = slot, ReadyAt = serverNow() + (own[skillId] - now) })
		return
	end
	-- Magia: las habilidades gastan maná
	local manaCost = MagicLogic.skillCost(ability)
	if manaCost > 0 and PetCombatService.mana(player) < manaCost then
		result(player, { Success = false, Code = "NoMana", Style = style, Slot = slot, Cost = manaCost })
		return
	end
	local cast: Cast = {
		Player = player,
		Style = style,
		SkillId = skillId,
		Damage = styleDps(profile, style) * (ability.DamageRatio or 0) * SkillLogic.power(level) * class.SkillDamage,
		-- La Ráfaga y la Furia (y las que las usan) no se potencian a sí mismas
		Buffed = (buffUntil[player] or 0) > now and baseId ~= "Burst" and baseId ~= "Rage",
		Color = ability.Color,
		Aim = aim,
		Element = ability.Element,
	}
	if not handler(cast, ability, root, level) then
		result(player, { Success = false, Code = "NoTarget", Style = style, Slot = slot })
		return
	end
	if manaCost > 0 then
		PetCombatService.spendMana(player, manaCost)
	end
	local cooldown = SkillLogic.cooldown(ability, level) * class.SkillCooldown
	own[skillId] = now + cooldown
	local ready = serverNow() + cooldown
	player:SetAttribute(SLOT_ATTRIBUTES[slot], ready)
	result(player, { Success = true, Code = "Success", Style = style, Slot = slot, ReadyAt = ready, Cooldown = cooldown })
end

-- Recargas de las dos habilidades puestas del estilo `style` en los atributos del jugador.
local function publishCooldowns(player: Player, style: string)
	local profile = PlayerDataService.get(player)
	local own = readyAt[player]
	local now = os.clock()
	for slot, attribute in SLOT_ATTRIBUTES do
		local skillId = profile and SkillLogic.equipped(skillsOf(profile), style, slot)
		local at = own and skillId and own[skillId]
		player:SetAttribute(attribute, serverNow() + (if at then math.max(0, at - now) else 0))
	end
end

local function setStyle(player: Player, styleId: any, pick: boolean?)
	local profile = PlayerDataService.get(player)
	if not (profile and type(styleId) == "string" and StyleLogic.definition(styleId)) then
		return
	end
	local skills = skillsOf(profile)
	if pick then
		if skills.Picked then
			return -- ya eligió: se cambia con "Set"
		end
		skills.Picked = true
		PlayerDataService.markDirty(player)
	end
	local now = os.clock()
	if profile.PetData.Style == styleId then
		if pick then
			PlayerDataService.replicate(player)
			result(player, { Success = true, Code = "Success", Action = "Pick", Style = styleId })
		end
		return
	end
	if not pick and not StyleLogic.canSwitch(lastSwitch[player], now) then
		result(player, { Success = false, Code = "TooFast", Style = profile.PetData.Style })
		return
	end
	lastSwitch[player] = now
	profile.PetData.Style = styleId
	PlayerDataService.markDirty(player)
	PlayerDataService.replicate(player) -- también la velocidad al caminar y la vida del estilo
	publishCooldowns(player, styleId)
	result(player, { Success = true, Code = "Success", Action = if pick then "Pick" else "Set", Style = styleId })
end

-- Comprar, subir y poner habilidades (con 💎) -------------------------------------------------

-- Devuelve el código y los 💎 cobrados.
function StyleService.skillAction(player: Player, action: string, skillId: any, slot: any): (string, number)
	local profile = PlayerDataService.get(player)
	if not profile or profile.DataState == "Loading" then
		return Codes.NotReady, 0
	end
	if type(skillId) ~= "string" or #skillId > 40 then
		return Codes.InvalidRequest, 0
	end
	local skills = skillsOf(profile)
	local code, cost = "InvalidRequest", 0
	if action == "BuySkill" then
		code, cost = SkillLogic.buy(skills, skillId, profile.Energy, profile.PetData.UnlockedZones)
	elseif action == "UpgradeSkill" then
		code, cost = SkillLogic.upgrade(skills, skillId, profile.Energy)
	elseif action == "EquipSkill" then
		code = SkillLogic.equip(skills, skillId, slot)
	end
	if code == "Success" then
		profile.Energy -= cost
		PlayerDataService.markDirty(player)
		PlayerDataService.replicate(player)
		local style = StyleLogic.sanitize(profile.PetData.Style)
		publishCooldowns(player, style)
		if action ~= "EquipSkill" then
			PlayerDataService.saveNow(player) -- lo comprado con 💎 no se pierde con una caída
		end
	end
	return Codes[code] or code, cost
end

-- Comprar, subir y elegir clases (con 💎) ---------------------------------------------------

local CLASS_ACTIONS = { BuyClass = true, UpgradeClass = true, SelectClass = true }

-- Devuelve el código y los 💎 cobrados.
function StyleService.classAction(player: Player, action: string, classId: any): (string, number)
	local profile = PlayerDataService.get(player)
	if not profile or profile.DataState == "Loading" then
		return Codes.NotReady, 0
	end
	if type(classId) ~= "string" or #classId > 40 then
		return Codes.InvalidRequest, 0
	end
	local classes = classesOf(profile)
	local code, cost = "InvalidRequest", 0
	if action == "BuyClass" then
		code, cost = ClassLogic.buy(classes, classId, profile.Energy)
	elseif action == "UpgradeClass" then
		code, cost = ClassLogic.upgrade(classes, classId, profile.Energy)
	elseif action == "SelectClass" then
		code = ClassLogic.select(classes, classId)
	end
	if code == "Success" then
		profile.Energy -= cost
		PlayerDataService.markDirty(player)
		PlayerDataService.replicate(player) -- también la vida y la velocidad de la clase
		if action ~= "SelectClass" then
			PlayerDataService.saveNow(player) -- lo comprado con 💎 no se pierde con una caída
		end
	end
	return Codes[code] or code, cost
end

-- Dash de Puños ---------------------------------------------------------------------------

local function dash(player: Player)
	local style = styleOf(player)
	local root = rootOf(player)
	local def = StyleLogic.definition(style)
	local spec = def and def.Dash
	if not (root and spec) then
		return
	end
	local now = os.clock()
	if (dashReadyAt[player] or 0) > now then
		return
	end
	local direction = moveDirection(player, root)
	local origin = root.Position
	local reach = dashReach(player, origin, direction, spec.Distance)
	local cooldown = spec.Cooldown * classModsOf(player).DashCooldown -- clase (Monje)
	dashReadyAt[player] = now + cooldown
	player:SetAttribute(Constants.Attributes.DashReadyAt, serverNow() + cooldown)
	local finish = origin + direction * reach
	if reach > 0 then
		local character = player.Character :: Model
		character:PivotTo(CFrame.lookAt(finish, finish + direction))
		root.AssemblyLinearVelocity = Vector3.new(direction.X * 20, 0, direction.Z * 20)
	end
	broadcast(player, origin, { Kind = "QuickDash", From = origin, To = finish })
end

-- Teletransporte de Magia (clic derecho corto, Shift o su botón) ---------------------------

local function blink(player: Player, aim: Vector3?)
	local style = styleOf(player)
	local root = rootOf(player)
	local def = StyleLogic.definition(style)
	local spec = def and def.Blink
	if not (root and spec) then
		return
	end
	local now = os.clock()
	if (dashReadyAt[player] or 0) > now then
		return
	end
	if not PetCombatService.spendMana(player, spec.Cost or 0) then
		result(player, { Success = false, Code = "NoMana", Action = "Blink", Cost = spec.Cost })
		return
	end
	local origin = root.Position
	local direction = moveDirection(player, root)
	if aim then
		local flat = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
		if flat.Magnitude > 1 then
			direction = flat.Unit
		end
	end
	local reach = dashReach(player, origin, direction, spec.Distance)
	dashReadyAt[player] = now + spec.Cooldown
	player:SetAttribute(Constants.Attributes.DashReadyAt, serverNow() + spec.Cooldown)
	local finish = origin + direction * reach
	if reach > 0 then
		local character = player.Character :: Model
		character:PivotTo(CFrame.lookAt(finish, finish + direction))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	broadcast(player, origin, { Kind = "Blink", From = origin, To = finish })
end

function StyleService.start()
	eventRemote = RemoteService.get(Constants.Remotes.StyleEvent)

	RemoteService.get(Constants.Remotes.StyleAction).OnServerEvent:Connect(function(player: Player, action: any, value: any, extra: any)
		if type(action) ~= "string" then
			return
		end
		if action == "BuySkill" or action == "UpgradeSkill" or action == "EquipSkill" then
			local rate = shopLimiter:check(player)
			if rate == "flood" then
				return
			elseif rate == "cooldown" then
				result(player, { Success = false, Code = Codes.TooFast, Action = action, Skill = value })
				return
			end
			local code, cost = StyleService.skillAction(player, action, value, extra)
			result(player, { Success = code == Codes.Success, Code = code, Action = action, Skill = value, Slot = extra, Cost = cost })
			return
		end
		if CLASS_ACTIONS[action] then
			local rate = shopLimiter:check(player)
			if rate == "flood" then
				return
			elseif rate == "cooldown" then
				result(player, { Success = false, Code = Codes.TooFast, Action = action, Class = value })
				return
			end
			local code, cost = StyleService.classAction(player, action, value)
			result(player, { Success = code == Codes.Success, Code = code, Action = action, Class = value, Cost = cost })
			return
		end
		if limiter:check(player) ~= "ok" then
			return
		end
		if action == "Set" then
			setStyle(player, value)
		elseif action == "Pick" then
			setStyle(player, value, true)
		elseif action == "Ability" then
			useAbility(player, if value == 2 then 2 else 1, validAim(player, extra))
		elseif action == "Dash" then
			dash(player)
		elseif action == "Blink" then
			blink(player, validAim(player, value))
		end
	end)

	-- Daño que recibe el jugador según su estilo (Puños menos, Armas más; con Furia, menos) y
	-- su clase (Tanque, Criomante)
	EnemyService.setIncomingDamageModifier(function(player: Player, amount: number, enemy: any?): number
		local style = styleOf(player)
		local taken = if style then StyleLogic.damageTaken(style, amount) else amount
		if (rageUntil[player] or 0) > os.clock() and (style == "Fists" or style == "Warrior") then
			taken *= math.clamp(rageTaken[player] or 0.5, 0, 1)
		end
		-- Guerrero: bloqueo (y parada perfecta: nada de daño)
		if style == "Warrior" then
			taken *= PetCombatService.blockIncoming(player, enemy)
		end
		return taken * classModsOf(player).DamageTaken
	end)
	-- Daño a los jefes según la clase (Comando Élite)
	EnemyService.setOutgoingDamageModifier(function(player: Player, enemy: any, amount: number): number
		if enemy and enemy.Kind == "Boss" then
			return amount * classModsOf(player).BossDamage
		end
		return amount
	end)

	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			generation[player] = (generation[player] or 0) + 1
			PetCombatService.setBurst(player, 0)
			buffUntil[player] = nil
			rageUntil[player] = nil
			player:SetAttribute(Constants.Attributes.StyleBurstUntil, nil)
			player:SetAttribute(Constants.Attributes.StyleRageUntil, nil)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwitch[player] = nil
		readyAt[player] = nil
		generation[player] = nil
		buffUntil[player] = nil
		rageUntil[player] = nil
		rageTaken[player] = nil
		dashReadyAt[player] = nil
		limiter:remove(player)
		shopLimiter:remove(player)
	end)
end

-- Para pruebas y otros servicios: el default por si un perfil no tiene estilo.
StyleService.DefaultStyle = StyleConfig.Default
StyleService.Combo = COMBO

return StyleService
