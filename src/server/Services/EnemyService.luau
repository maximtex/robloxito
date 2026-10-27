-- Enemigos PvE de todas las zonas (EnemyConfig):
-- - Modelos nativos provisionales por estilo, con Humanoid para moverse por el terreno
--   (MoveTo en línea recta; si se atascan al volver, reaparecen en su origen).
-- - UNA sola IA para todos (un bucle cada AiTickSeconds): Idle, Chase, Attack, Return, Dead.
--   Persiguen solo dentro de su radio, nunca entran en zonas protegidas (spawn, cristal,
--   portales, santuarios) y vuelven a casa si se alejan demasiado (curándose al llegar).
-- - Jefes: golpe normal + golpe en área anunciado en el suelo (un disco que se llena
--   marca el momento exacto y una onda expansiva el impacto) + furia bajo la mitad de vida
--   (aura y ojos encendidos). Los efectos son solo visuales y se limpian con Debris.
-- - Daño y muerte con EnemyLogic: la muerte se decide una sola vez por vida y la
--   recompensa en dinero se reparte por daño, sumándola a profile.Money (paga la Tienda de
--   Láser) y replicándola con PlayerDataService. Cada golpe suelta además un poco de dinero.
--   El cliente recibe dónde estaba el enemigo para dibujar las monedas que salen de él.
-- - Atacan a los jugadores que se acercan (DetectRange) o que les disparan dentro de su
--   radio; el daño respeta el escudo de aparición y la defensa de las tortugas. Cada golpe se
--   prepara quieto y avisado (AttackWindup; atributos AttackTarget, AttackDir, AttackReach y
--   AttackAt) y solo alcanza por delante: se puede esquivar, bloquear o parar (Guerrero).
-- - Al morir el modelo se retira (tras dejar que el cliente lo disuelva) y reaparece tras
--   RespawnSeconds, reutilizando el mismo modelo (sin crear ni filtrar instancias ni conexiones).
-- - Presentación: las piezas van unidas con Motor6D por grupos (cuerpo, brazos, piernas)
--   y el modelo publica atributos (SpawnedAt, AttackAt, SlamAt, DiedAt) que el cliente
--   usa para animarlo (EnemyAnimator). No cambian estadísticas, IA ni recompensas.
-- - Estados de las habilidades elementales (AbilityService): ralentizar, inmovilizar,
--   aturdir y marcar (más daño recibido), con EnemyLogic. Se borran al morir, reaparecer
--   o volver a casa. Publica <Estado>Until (hora del servidor) para los efectos del cliente.
-- - Marca elemental de los combos (Aura / AuraUntil) y retroceso breve al recibir una
--   habilidad fuerte (nunca los jefes).
-- - Rediseño "solo disparar": cada enemigo derrotado da también ⚡ (EnergyService.grant:
--   su recompensa · EconomyConfig.KillEnergyShare · poder de energía del jugador), sube la
--   RACHA del jugador (WaveLogic: multiplica el botín mientras mate sin parar; atributos
--   Streak y StreakUntil) y a veces suelta un ORBE DORADO (botín ×10, nunca un jefe).
--   setKillModifier deja que WaveService añada lo de las mejoras de la partida.
-- - Oleadas (WaveService): enemigos de una reserva (spawnPooled) que se crean una vez,
--   no reaparecen solos al morir y vuelven a la reserva; y jefes que solo salen en la
--   última oleada (setBossWaveControlled / wakeBoss). Al morir avisan a OnWaveDeath.
-- - Oleadas PRIVADAS: los enemigos de una partida llevan su número (Run, atributo WaveRun en
--   el modelo y en sus efectos) y los jugadores que la juegan, el atributo WaveRun. Solo se
--   persiguen, se golpean y se hacen daño los del mismo "mundo" (nil = el mundo normal);
--   el cliente oculta lo de los demás (WaveVisibility). Los de las partidas no chocan con
--   los jugadores ni entre ellos (grupo de colisión WaveEnemies) y no tienen zonas seguras.

local Debris = game:GetService("Debris")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local StudFloor = require(Shared.Util.StudFloor)
local CaveConfig = require(Shared.Config.CaveConfig)
local CaveLogic = require(Shared.CaveLogic)
local RebirthLogic = require(Shared.RebirthLogic)
local AdventureConfig = require(Shared.Config.AdventureConfig)
local AdventureLogic = require(Shared.AdventureLogic)
local CombatConfig = require(Shared.Config.CombatConfig)
local ItemLogic = require(Shared.ItemLogic)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local WaveLogic = require(Shared.WaveLogic)
local WaveConfig = require(Shared.Config.WaveConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EnergyService = require(script.Parent.EnergyService)
local RemoteService = require(script.Parent.RemoteService)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local EnemyLogic = require(script.Parent.Parent.Util.EnemyLogic)
local TerrainPaint = require(script.Parent.Parent.Util.TerrainPaint)
-- Modelos 3D de Santiago para los enemigos del Bosque (estilos Arbolito, ArbolitoBebe,
-- ArbolGuardian y GiganteDelBosque): se registran en BUILDERS / SHAPES más abajo.
local ModelosZona1 = require(script.Parent.Parent.Util.ModelosZona1)

local FOLDER_NAME = "Enemies"
local ARENAS_NAME = "BossArenas"
local GROUND = GeneratorConfig.Position.Y
local WINDUP_EYES = Color3.fromRGB(255, 70, 60)
local ENRAGED_EYES = Color3.fromRGB(255, 120, 40)
-- Tiempo que el cuerpo sigue en el mundo tras morir, para que el cliente lo disuelva
-- (ya está muerto: no recibe golpes ni ataca). Solo presentación.
local DISSOLVE_SECONDS = { Normal = 0.8, Strong = 0.9, Boss = 1.6 }
-- Tope de seguridad de cualquier estado (AbilityConfig.MaxControlSeconds).
local MAX_CONTROL_SECONDS = 10
local KNOCKBACK_SECONDS = 0.18 -- duración del empujón (distancia ≈ fuerza · duración)
-- Atributo de presentación de cada estado (hora del servidor a la que termina).
local STATUS_ATTRIBUTES = { Slow = "SlowUntil", Root = "RootUntil", Stun = "StunUntil", Vulnerable = "CurseUntil", Burn = "BurnUntil" }
-- Barra de vida como la de Roblox (la de los jugadores): nombre blanco con sombra y barra
-- verde que pasa a amarilla y a roja al bajar. El nombre de los fuertes y los jefes lleva un
-- toque de color para distinguirlos.
local BAR_HEALTHY = Color3.fromRGB(27, 252, 107)
local BAR_WARNING = Color3.fromRGB(250, 235, 0)
local BAR_CRITICAL = Color3.fromRGB(255, 28, 0)
local BAR_TRACK = Color3.fromRGB(28, 28, 28)
local KIND_NAME_COLORS = {
	Normal = Color3.fromRGB(255, 255, 255),
	Strong = Color3.fromRGB(255, 214, 140),
	Boss = Color3.fromRGB(255, 150, 150),
}
-- Contorno oscuro alrededor de cada enemigo (estilo caricatura).
local INK = Color3.fromRGB(43, 29, 63)
local BAR_SIZES = { Normal = UDim2.fromOffset(130, 32), Strong = UDim2.fromOffset(150, 34), Boss = UDim2.fromOffset(190, 38) }
local BAR_DISTANCE = { Normal = 120, Strong = 140, Boss = 180 }

-- Color de la barra según la vida que queda (0..1), como la de Roblox.
local function healthColor(fraction: number): Color3
	if fraction >= 0.5 then
		return BAR_HEALTHY
	elseif fraction >= 0.25 then
		return BAR_WARNING:Lerp(BAR_HEALTHY, (fraction - 0.25) / 0.25)
	end
	return BAR_CRITICAL:Lerp(BAR_WARNING, math.max(0, fraction) / 0.25)
end

type SafeZone = { Center: Vector3, Radius: number }
type SafeArea = { Min: Vector2, Max: Vector2 } -- rectángulo en X/Z del mundo

type Enemy = {
	Id: number,
	TypeId: string,
	Def: any,
	Kind: string,
	ZoneId: string,
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Eyes: { BasePart },
	EyeColor: Color3,
	Aura: ParticleEmitter?, -- aura de furia (solo jefes), apagada salvo en furia
	Glow: PointLight?, -- luz de furia (solo jefes), apagada salvo en furia
	Bar: Frame,
	Billboard: BillboardGui,
	RootHeight: number, -- altura del centro de la raíz sobre el suelo
	Radius: number, -- radio horizontal para recibir golpes
	DeathSeconds: number?, -- cuánto queda el cuerpo tras morir (modelos con animación Death)
	Home: Vector3,
	LeashCenter: Vector3,
	LeashRadius: number,
	DetectRange: number,
	SafeZones: { SafeZone },
	SafeAreas: { SafeArea },
	RewardMultiplier: number,
	Status: EnemyLogic.EnemyState,
	Control: EnemyLogic.Control, -- estados de las habilidades (os.clock)
	Target: Player?,
	NextAttack: number,
	WindupUntil: number?, -- preparando un golpe hasta entonces (os.clock): quieto, comprometido
	NextSlam: number,
	NextWander: number,
	Enraged: boolean,
	Generation: number, -- cambia en cada muerte/reaparición: invalida tareas pendientes
	StuckSince: number?,
	LastHomeDistance: number,
	Brain: any?, -- solo jefes con Def.Brain: su máquina de estados (updateBoss)
	-- Oleadas (WaveService)
	Pooled: boolean, -- de la reserva: no reaparece solo, vuelve a la reserva al morir
	InPool: boolean, -- en la reserva, esperando a que una oleada lo saque
	WaveControlled: boolean, -- jefe que solo sale en la última oleada (no reaparece solo)
	OnWaveDeath: ((any, Player?, Vector3) -> ())?, -- aviso al morir (enemigo, quién lo mató, dónde)
	LastHitBy: Player?, -- quién dio el último golpe (solo para OnWaveDeath)
	Run: number?, -- partida de oleadas a la que pertenece (nil = el mundo normal)
	MoneyMultiplier: number, -- dinero que suelta (golpes y derrota); la ⚡ no cambia
	DamageMultiplier: number?, -- daño que hace (oleadas; nil = 1)
	Territory: number?, -- territorio del jefe (si no, Def.Brain.Territory)
	Variant: string?, -- "Elite" o "MiniBoss" (mazmorras: más grande, brilla, más vida y botín)
	-- Jefe que se parte (oleadas: el Coloso del Equilibrio): al bajar a SplitAt de su vida
	-- máxima no baja más y se avisa a OnSplit (WaveService lo cambia por sus dos mitades)
	SplitAt: number?,
	OnSplit: ((any) -> ())?,
}

local EnemyService = {}

local enemies: { Enemy } = {}
-- Reserva de enemigos de las oleadas: "<zona>/<tipo>" -> libres y cuántos se han creado.
local pools: { [string]: { Enemy } } = {}
-- Élites de las salas de las mazmorras: cuántos pequeños lleva cada cueva (uno de cada
-- round(1 / EliteChance) es élite: siempre los mismos)
local eliteCount: { [string]: number } = {}
local poolCreated: { [string]: number } = {}
-- Jefe de cada zona (para las oleadas).
local bossByZone: { [string]: Enemy } = {}
-- Racha de cada jugador (WaveLogic) y extra de las mejoras de la partida (WaveService).
local streaks: { [Player]: WaveLogic.Streak } = {}
local killModifier: ((Player, Enemy) -> (number?, number?))? = nil
-- Modificador del daño que los enemigos hacen a los jugadores (lo registra
-- PetCombatService para la Tortuga). Un único punto: nunca se aplica dos veces.
local incomingModifier: ((Player, number, any?) -> number)? = nil
-- Daño que hace el jugador según su clase (StyleService: más a los jefes)
local outgoingModifier: ((Player, any, number) -> number)? = nil
local folder: Folder
local rewardRemote: RemoteEvent
-- Avisos de "este jugador ha derrotado a este enemigo" (los usa QuestService). Solo
-- informan: no cambian la muerte ni la recompensa.
local defeatListeners: { (Player, { TypeId: string, Kind: string, ZoneId: string, Reward: number }) -> () } = {}
local clickListeners: { (Player, Enemy) -> () } = {}

-- Oleadas privadas (WaveService) ------------------------------------------------------------
local RUN_ATTRIBUTE = Constants.Attributes.WaveRun
local WAVE_GROUP = "WaveEnemies" -- grupo de colisión de los de la reserva (sin partida)
local CHARACTER_GROUP = "Characters" -- personajes de los jugadores
-- Un grupo por partida a la vez ("WaveRun1".."WaveRunN", N = WaveConfig.MaxRuns): los de la
-- misma partida chocan entre ellos (rodean al jugador en vez de amontonarse en un punto),
-- pero no con los de otras partidas ni con los personajes.
local WAVE_SLOT_PREFIX = "WaveRun"
local waveSlots = 0 -- grupos de partida registrados

-- Partida que juega un jugador (nil = el mundo normal).
local function runOfPlayer(player: Player): number?
	local value = player:GetAttribute(RUN_ATTRIBUTE)
	return if type(value) == "number" then value else nil
end

-- ¿El enemigo y el jugador están en el mismo "mundo"?
local function sameWorld(enemy: Enemy, player: Player): boolean
	return enemy.Run == runOfPlayer(player)
end

-- ¿Este jugador puede ver, apuntar y golpear a este enemigo?
function EnemyService.canInteract(player: Player, enemy: any): boolean
	return enemy ~= nil and sameWorld(enemy, player)
end

-- Marca una pieza de efecto con la partida de su enemigo (el cliente oculta las ajenas).
local function tagRun(instance: Instance, run: number?)
	if run ~= nil then
		instance:SetAttribute(RUN_ATTRIBUTE, run)
	end
end

local fxFolder: Folder
-- Pieza de efecto creada sin padre: se marca con su partida y LUEGO se pone en el mundo
-- (así llega ya marcada y los demás jugadores no la ven ni un instante).
local function placeFx(part: Instance, run: number?)
	tagRun(part, run)
	part.Parent = fxFolder
end

local function setCollisionGroup(model: Instance, group: string)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

function EnemyService.onDefeated(listener: (Player, { TypeId: string, Kind: string, ZoneId: string, Reward: number }) -> ())
	table.insert(defeatListeners, listener)
end

function EnemyService.onClicked(listener: (Player, Enemy) -> ())
	table.insert(clickListeners, listener)
end

function EnemyService.findNearest(center: Vector3, maxRange: number): Enemy?
	local best: Enemy? = nil
	local bestDist = maxRange
	for _, enemy in enemies do
		if EnemyService.isAlive(enemy) then
			local d = Vector2.new(enemy.Root.Position.X - center.X, enemy.Root.Position.Z - center.Z).Magnitude
			if d <= bestDist then
				bestDist = d
				best = enemy
			end
		end
	end
	return best
end

-- El enemigo de un modelo (el cliente lo propone al apuntar; quien llama comprueba que
-- esté vivo y a su alcance).
function EnemyService.fromModel(model: Instance): Enemy?
	for _, enemy in enemies do
		if enemy.Model == model then
			return enemy
		end
	end
	return nil
end

local function zoneCenter(zoneId: string): Vector3
	local zone = ZoneConfig.Zones[zoneId]
	local base = GeneratorConfig.Position
	return Vector3.new(base.X + zone.Center.X, GROUND, base.Z + zone.Center.Y)
end

local function flat(vector: Vector3): number
	return Vector2.new(vector.X, vector.Z).Magnitude
end

-- Modelos -----------------------------------------------------------------------
-- Diseñados con el suelo en Y = 0 y el frente hacia -Z; luego se colocan con PivotTo.

type Rig = { Model: Model, Root: BasePart, Humanoid: Humanoid, Eyes: { BasePart }, RootHeight: number }

local function newRig(name: string, rootSize: Vector3, hipHeight: number, walkSpeed: number): Rig
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local rootHeight = hipHeight + rootSize.Y / 2
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = rootSize
	root.CFrame = CFrame.new(0, rootHeight, 0)
	root.Transparency = 1
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = hipHeight
	humanoid.WalkSpeed = walkSpeed
	humanoid.MaxHealth = 1e6 -- la vida real la lleva EnemyLogic
	humanoid.Health = 1e6
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	for _, state in { Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Climbing } do
		humanoid:SetStateEnabled(state, false)
	end
	humanoid.Parent = model

	return { Model = model, Root = root, Humanoid = humanoid, Eyes = {}, RootHeight = rootHeight }
end

-- Pieza decorativa sin colisión ni masa. Se une a la raíz después (addJoints).
local function piece(rig: Rig, name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Massless = true
	part.Parent = rig.Model
	return part
end

local function box(rig: Rig, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	return piece(rig, name, Enum.PartType.Block, size, cframe, color, material)
end

local function orb(rig: Rig, name: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material): Part
	return piece(rig, name, Enum.PartType.Ball, Vector3.one * diameter, CFrame.new(position), color, material)
end

local function limb(rig: Rig, name: string, from: Vector3, to: Vector3, diameter: number, color: Color3, material: Enum.Material): Part
	local direction = to - from
	return piece(rig, name, Enum.PartType.Cylinder, Vector3.new(direction.Magnitude, diameter, diameter), CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0), color, material)
end

local function eye(rig: Rig, name: string, diameter: number, position: Vector3, color: Color3)
	table.insert(rig.Eyes, orb(rig, name, diameter, position, color, Enum.Material.Neon))
end

local function crystalSpike(rig: Rig, name: string, size: Vector3, position: Vector3, tilt: Vector3, color: Color3)
	box(rig, name, size, CFrame.new(position) * CFrame.Angles(tilt.X, tilt.Y, tilt.Z) * CFrame.Angles(0, math.rad(45), 0), color, Enum.Material.Neon)
end

local BUILDERS = {}

-- Ojos de caricatura: globo blanco con pupila (la pupila es el "ojo" que cambia de color
-- al avisar un golpe) y ceja de enfado, para que se lea de lejos que es un enemigo.
local function cartoonEyes(rig: Rig, center: Vector3, spread: number, size: number, look)
	for side = -1, 1, 2 do
		local white = Vector3.new(side * spread, center.Y, center.Z)
		orb(rig, "Sclera" .. side, size, white, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		eye(rig, "Eye" .. side, size * 0.5, white + Vector3.new(-side * size * 0.06, -size * 0.04, -size * 0.36), look.Eyes)
		box(rig, "Brow" .. side, Vector3.new(size * 0.85, size * 0.2, size * 0.25), CFrame.new(white + Vector3.new(0, size * 0.58, -size * 0.28)) * CFrame.Angles(0, 0, math.rad(side * 22)), look.Eyes, Enum.Material.SmoothPlastic)
	end
end

-- Espinillo (caricatura): zarzamora redonda de color vivo con espinas amarillas, brote de
-- hojas, ojos grandes con ceja de enfado y patitas. Grande y de colores que resaltan
-- sobre el pasto (antes era una bola verde pequeña que se perdía).
function BUILDERS.Bramble(rig: Rig, look)
	local center = Vector3.new(0, 2.2, 0)
	orb(rig, "Body", 3.4, center, look.Primary, Enum.Material.SmoothPlastic)
	orb(rig, "Shine", 0.7, center + Vector3.new(-0.85, 1.05, -1.05), look.Primary:Lerp(Color3.new(1, 1, 1), 0.65), Enum.Material.SmoothPlastic)
	for index = 1, 8 do
		if index == 6 then
			continue -- sin espina delante de la cara (270° = -Z)
		end
		local angle = (index / 8) * math.pi * 2
		local direction = Vector3.new(math.cos(angle), if index % 2 == 0 then 0.55 else 0.1, math.sin(angle)).Unit
		local base = center + direction * 1.65
		box(rig, "Thorn" .. index, Vector3.new(0.42, 1.1, 0.42), CFrame.lookAt(base, base + direction) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.Angles(0, math.rad(45), 0), look.Secondary, Enum.Material.SmoothPlastic)
	end
	for index, tilt in { 28, -28 } do
		box(rig, "Leaf" .. index, Vector3.new(1.1, 0.16, 0.6), CFrame.new(center + Vector3.new(index == 1 and 0.42 or -0.42, 1.85, 0.1)) * CFrame.Angles(0, 0, math.rad(tilt)), Color3.fromRGB(110, 214, 86), Enum.Material.SmoothPlastic)
	end
	cartoonEyes(rig, center + Vector3.new(0, 0.35, -1.25), 0.62, 1.05, look)
	for side = -1, 1, 2 do
		orb(rig, "Foot" .. side, 1, Vector3.new(side * 0.75, 0.5, -0.1), look.Primary:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.SmoothPlastic)
	end
end

-- Bruto de Corteza: tronco andante con brazos largos y musgo.
function BUILDERS.Brute(rig: Rig, look)
	box(rig, "Torso", Vector3.new(3.2, 3.6, 2.4), CFrame.new(0, 3.7, 0), look.Primary, Enum.Material.Wood)
	local moss = box(rig, "Moss", Vector3.new(3.5, 0.9, 2.7), CFrame.new(0, 5.6, 0), look.Secondary, Enum.Material.LeafyGrass)
	local mossMesh = Instance.new("SpecialMesh")
	mossMesh.MeshType = Enum.MeshType.Sphere
	mossMesh.Parent = moss
	for side = -1, 1, 2 do
		eye(rig, "Eye" .. side, 0.36, Vector3.new(side * 0.6, 4.7, -1.22), look.Eyes)
		limb(rig, "Arm" .. side, Vector3.new(side * 1.9, 4.9, 0), Vector3.new(side * 2.3, 2.1, -0.7), 1, look.Primary, Enum.Material.Wood)
		orb(rig, "Fist" .. side, 1.3, Vector3.new(side * 2.3, 1.9, -0.7), look.Primary, Enum.Material.Wood)
		box(rig, "Leg" .. side, Vector3.new(1, 1.9, 1), CFrame.new(side * 0.8, 0.95, 0), look.Primary:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Wood)
	end
end

-- Guardián del Bosque (jefe): árbol antiguo con copa, brazos de rama y runa en el pecho.
function BUILDERS.Treant(rig: Rig, look)
	piece(rig, "Trunk", Enum.PartType.Cylinder, Vector3.new(9, 5, 5), CFrame.new(0, 7.5, 0) * CFrame.Angles(0, 0, math.rad(90)), look.Primary, Enum.Material.Wood)
	for index, blob in { { Vector3.new(0, 13.5, 0), 8 }, { Vector3.new(3, 12.5, 1), 6 }, { Vector3.new(-3, 12.5, 1), 6 }, { Vector3.new(0, 14.5, -2), 5 } } do
		orb(rig, "Canopy" .. index, blob[2], blob[1], look.Secondary, Enum.Material.LeafyGrass)
	end
	box(rig, "Rune", Vector3.new(1.6, 0.3, 0.1), CFrame.new(0, 7.5, -2.52), look.Eyes, Enum.Material.Neon)
	for side = -1, 1, 2 do
		eye(rig, "Eye" .. side, 0.8, Vector3.new(side * 1, 9.6, -2.35), look.Eyes)
		limb(rig, "UpperArm" .. side, Vector3.new(side * 2.3, 9, 0), Vector3.new(side * 5, 6, -1.5), 1.2, look.Primary, Enum.Material.Wood)
		limb(rig, "LowerArm" .. side, Vector3.new(side * 5, 6, -1.5), Vector3.new(side * 5.4, 3, -2.6), 1, look.Primary, Enum.Material.Wood)
		orb(rig, "Hand" .. side, 1.8, Vector3.new(side * 5.4, 2.8, -2.6), look.Primary, Enum.Material.Wood)
		for _, forward in { -1, 1 } do
			limb(rig, "Root" .. side .. forward, Vector3.new(side * 1.4, 3, 0), Vector3.new(side * 2.6, 0.3, forward * 1.6), 1.3, look.Primary, Enum.Material.Wood)
		end
	end
end

-- Fragmento Errante / Chispa Ígnea (caricatura): gema grande de color vivo con esquirlas
-- luminosas, ojos grandes con ceja de enfado y patitas.
function BUILDERS.Shard(rig: Rig, look)
	local center = Vector3.new(0, 2.6, 0)
	box(rig, "Core", Vector3.one * 2.4, CFrame.new(center) * CFrame.Angles(math.rad(45), 0, math.rad(35)), look.Primary, Enum.Material.SmoothPlastic)
	orb(rig, "Shine", 0.6, center + Vector3.new(-0.7, 1.1, -0.9), look.Primary:Lerp(Color3.new(1, 1, 1), 0.7), Enum.Material.SmoothPlastic)
	for index, spec in { { Vector3.new(1, 3.4, 0.3), Vector3.new(0, 0, -0.5) }, { Vector3.new(-1, 3.3, 0.4), Vector3.new(0, 0, 0.5) }, { Vector3.new(0, 4.1, 0.5), Vector3.new(0.3, 0, 0) }, { Vector3.new(0.5, 2.2, 1.2), Vector3.new(0.8, 0, 0) } } do
		crystalSpike(rig, "Shard" .. index, Vector3.new(0.5, 1.5, 0.5), spec[1], spec[2], look.Secondary)
	end
	cartoonEyes(rig, center + Vector3.new(0, 0.2, -1.25), 0.5, 0.85, look)
	for side = -1, 1, 2 do
		box(rig, "Leg" .. side, Vector3.new(0.55, 1.2, 0.55), CFrame.new(side * 0.55, 0.6, 0) * CFrame.Angles(0, math.rad(45), 0), look.Primary:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.SmoothPlastic)
	end
end

-- Material de la piedra de un estilo: look.Material (nombre de Enum.Material) o `default`
local function stoneOf(material: any, default: Enum.Material): Enum.Material
	if type(material) == "string" then
		local ok, value = pcall(function()
			return (Enum.Material :: any)[material]
		end)
		if ok and value then
			return value
		end
	end
	return default
end

-- Gólem de Geoda: bloques de pizarra con crecimientos de cristal (look.Material cambia la
-- piedra: los brutos de las Tierras Divididas son de basalto o de hielo glaciar).
function BUILDERS.Golem(rig: Rig, look)
	local stone = stoneOf(look.Material, Enum.Material.Slate)
	box(rig, "Torso", Vector3.new(3.6, 3.8, 2.8), CFrame.new(0, 3.9, 0), look.Primary, stone)
	box(rig, "Head", Vector3.new(1.8, 1.4, 1.6), CFrame.new(0, 6.5, -0.2), look.Primary, stone)
	for index, spec in { { Vector3.new(1.4, 6.2, 0.6), Vector3.new(0, 0, -0.4) }, { Vector3.new(-1.5, 6.0, 0.5), Vector3.new(0, 0, 0.4) }, { Vector3.new(0.6, 5.2, 1.5), Vector3.new(0.6, 0, 0) }, { Vector3.new(-0.7, 4.4, 1.5), Vector3.new(0.7, 0, 0) } } do
		crystalSpike(rig, "Crystal" .. index, Vector3.new(0.5, 1.6, 0.5), spec[1], spec[2], look.Secondary)
	end
	for side = -1, 1, 2 do
		eye(rig, "Eye" .. side, 0.32, Vector3.new(side * 0.45, 6.6, -1.02), look.Eyes)
		orb(rig, "Shoulder" .. side, 1.6, Vector3.new(side * 2.4, 5, 0), look.Primary, stone)
		limb(rig, "Arm" .. side, Vector3.new(side * 2.4, 5, 0), Vector3.new(side * 2.6, 2.4, -0.6), 1.1, look.Primary, stone)
		orb(rig, "Fist" .. side, 1.9, Vector3.new(side * 2.6, 2.3, -0.6), look.Primary, stone)
		box(rig, "Leg" .. side, Vector3.new(1.2, 1.9, 1.2), CFrame.new(side * 0.9, 0.95, 0), look.Primary, stone)
	end
end

-- Coloso de Amatista (jefe): gigante de pizarra con corona de amatista y núcleo brillante.
-- look.Material (nombre de Enum.Material) cambia la piedra: el Gólem de Hielo es de hielo glaciar.
-- look.Split: gigante de dos mitades (el Coloso del Equilibrio): su lado derecho (+X) lleva
-- los colores y la piedra de Split (Primary, Secondary, Eyes, Material).
function BUILDERS.Colossus(rig: Rig, look)
	local stone = stoneOf(look.Material, Enum.Material.Slate)
	local split = look.Split
	-- Colores de cada lado (side = -1 izquierda, 1 derecha)
	local function sideLook(side: number): (Color3, Color3, Color3, Enum.Material)
		if split and side > 0 then
			return split.Primary or look.Primary, split.Secondary or look.Secondary, split.Eyes or look.Eyes, stoneOf(split.Material, stone)
		end
		return look.Primary, look.Secondary, look.Eyes, stone
	end
	if split then
		-- Torso, cabeza y núcleo en dos mitades, con una veta brillante en medio
		for side = -1, 1, 2 do
			local primary, secondary, _, material = sideLook(side)
			box(rig, "TorsoHalf" .. side, Vector3.new(3.5, 8, 5), CFrame.new(side * 1.75, 8, 0), primary, material)
			box(rig, "HeadHalf" .. side, Vector3.new(1.5, 2.4, 2.6), CFrame.new(side * 0.75, 13.2, -0.4), primary, material)
			orb(rig, "CoreGemHalf" .. side, 1.5, Vector3.new(side * 0.55, 8.5, -2.55), secondary, Enum.Material.Neon)
		end
		box(rig, "Seam", Vector3.new(0.35, 8.2, 5.1), CFrame.new(0, 8, 0), Color3.fromRGB(255, 240, 255), Enum.Material.Neon)
	else
		box(rig, "Torso", Vector3.new(7, 8, 5), CFrame.new(0, 8, 0), look.Primary, stone)
		box(rig, "Head", Vector3.new(3, 2.4, 2.6), CFrame.new(0, 13.2, -0.4), look.Primary, stone)
		orb(rig, "CoreGem", 1.8, Vector3.new(0, 8.5, -2.55), look.Secondary, Enum.Material.Neon)
	end
	for index, spec in { { Vector3.new(0, 15.4, -0.4), Vector3.zero, 3.2 }, { Vector3.new(-1.1, 14.9, -0.3), Vector3.new(0, 0, 0.4), 2.4 }, { Vector3.new(1.1, 14.9, -0.3), Vector3.new(0, 0, -0.4), 2.4 }, { Vector3.new(-3.6, 12.6, 0.5), Vector3.new(0, 0, 0.5), 2.8 }, { Vector3.new(3.6, 12.6, 0.5), Vector3.new(0, 0, -0.5), 2.8 } } do
		local _, secondary = sideLook(if spec[1].X > 0 then 1 elseif spec[1].X < 0 then -1 else (if index % 2 == 0 then 1 else -1))
		crystalSpike(rig, "Crown" .. index, Vector3.new(0.9, spec[3], 0.9), spec[1], spec[2], secondary)
	end
	for side = -1, 1, 2 do
		local primary, _, eyes, material = sideLook(side)
		eye(rig, "Eye" .. side, 0.6, Vector3.new(side * 0.8, 13.4, -1.72), eyes)
		orb(rig, "Shoulder" .. side, 3, Vector3.new(side * 4.6, 10.5, 0), primary, material)
		limb(rig, "Arm" .. side, Vector3.new(side * 4.6, 10.5, 0), Vector3.new(side * 5.2, 4.2, -1.5), 2, primary, material)
		orb(rig, "Fist" .. side, 3.4, Vector3.new(side * 5.2, 4, -1.5), primary, material)
		box(rig, "Leg" .. side, Vector3.new(2.2, 3.8, 2.2), CFrame.new(side * 1.6, 1.9, 0), primary, material)
	end
end

local function darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end
local function lighter(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end
local GOLD = Color3.fromRGB(255, 200, 70)
local IVORY = Color3.fromRGB(246, 236, 210)
local STEEL = Color3.fromRGB(176, 182, 196)
local WOOD_DARK = Color3.fromRGB(104, 70, 44)

-- Lobo de Escarcha: lobo de pelo blanco azulado a cuatro patas con cristales de hielo en el
-- lomo, hocico, orejas de punta, cola y ojos que brillan. Las patas de delante son el grupo
-- Leg y las de atrás "Hind" (también Leg, con su pivote): trota en diagonal.
function BUILDERS.Wolf(rig: Rig, look)
	local fur, frost = look.Primary, look.Secondary
	box(rig, "Torso", Vector3.new(2.2, 1.9, 3.6), CFrame.new(0, 2.7, 0.2), fur, Enum.Material.SmoothPlastic)
	orb(rig, "Chest", 2.3, Vector3.new(0, 2.65, -1.35), lighter(fur, 0.4), Enum.Material.SmoothPlastic)
	box(rig, "Head", Vector3.new(1.7, 1.5, 1.6), CFrame.new(0, 3.65, -2.15), fur, Enum.Material.SmoothPlastic)
	box(rig, "Snout", Vector3.new(0.95, 0.75, 1.05), CFrame.new(0, 3.3, -3.25), lighter(fur, 0.5), Enum.Material.SmoothPlastic)
	orb(rig, "Nose", 0.42, Vector3.new(0, 3.55, -3.8), Color3.fromRGB(40, 44, 60), Enum.Material.SmoothPlastic)
	box(rig, "Fangs", Vector3.new(0.7, 0.18, 0.12), CFrame.new(0, 2.95, -3.72), IVORY, Enum.Material.SmoothPlastic)
	for side = -1, 1, 2 do
		box(rig, "Ear" .. side, Vector3.new(0.45, 0.85, 0.3), CFrame.new(side * 0.5, 4.65, -2.0) * CFrame.Angles(0, 0, math.rad(-side * 14)), fur, Enum.Material.SmoothPlastic)
		box(rig, "EarIn" .. side, Vector3.new(0.25, 0.5, 0.06), CFrame.new(side * 0.5, 4.6, -2.17) * CFrame.Angles(0, 0, math.rad(-side * 14)), frost, Enum.Material.SmoothPlastic)
		eye(rig, "Eye" .. side, 0.34, Vector3.new(side * 0.45, 3.9, -2.95), look.Eyes)
		box(rig, "Brow" .. side, Vector3.new(0.55, 0.14, 0.2), CFrame.new(side * 0.45, 4.18, -2.96) * CFrame.Angles(0, 0, math.rad(side * 20)), darker(frost, 0.4), Enum.Material.SmoothPlastic)
		-- Delanteras (Leg) y traseras (Hind): la delantera derecha y la trasera izquierda a la vez
		box(rig, "Leg" .. side, Vector3.new(0.6, 2.1, 0.6), CFrame.new(side * 0.72, 1.05, -1.25), fur, Enum.Material.SmoothPlastic)
		box(rig, "Hind" .. side, Vector3.new(0.65, 2.1, 0.65), CFrame.new(-side * 0.72, 1.05, 1.45), darker(fur, 0.08), Enum.Material.SmoothPlastic)
	end
	box(rig, "Tail", Vector3.new(0.55, 0.55, 1.9), CFrame.new(0, 3.15, 2.75) * CFrame.Angles(math.rad(28), 0, 0), fur, Enum.Material.SmoothPlastic)
	box(rig, "TailTip", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 3.6, 3.6), frost, Enum.Material.SmoothPlastic)
	for index, spec in { { Vector3.new(0, 3.95, -0.7), Vector3.new(-0.2, 0, 0) }, { Vector3.new(0.35, 3.85, 0.4), Vector3.new(0.2, 0, -0.4) }, { Vector3.new(-0.35, 3.8, 1.3), Vector3.new(0.3, 0, 0.4) } } do
		crystalSpike(rig, "Ice" .. index, Vector3.new(0.45, 1.2, 0.45), spec[1], spec[2], frost)
	end
end

-- Yeti: mole de pelo blanco con la cara y las manos azuladas, cuernos de marfil y cejas de
-- enfado; brazos largos que aplastan.
function BUILDERS.Yeti(rig: Rig, look)
	local fur, skin = look.Primary, look.Secondary
	box(rig, "Torso", Vector3.new(4, 4.2, 3), CFrame.new(0, 4.5, 0), fur, Enum.Material.SmoothPlastic)
	orb(rig, "Belly", 3, Vector3.new(0, 4.2, -0.75), lighter(skin, 0.55), Enum.Material.SmoothPlastic)
	orb(rig, "Fluff", 3.6, Vector3.new(0, 6.3, 0.2), fur, Enum.Material.SmoothPlastic)
	box(rig, "Head", Vector3.new(2.3, 2.1, 2.1), CFrame.new(0, 7.6, -0.45), fur, Enum.Material.SmoothPlastic)
	box(rig, "Face", Vector3.new(1.8, 1.4, 0.2), CFrame.new(0, 7.45, -1.52), skin, Enum.Material.SmoothPlastic)
	box(rig, "Mouth", Vector3.new(1, 0.22, 0.1), CFrame.new(0, 6.98, -1.64), darker(skin, 0.6), Enum.Material.SmoothPlastic)
	for side = -1, 1, 2 do
		box(rig, "Fang" .. side, Vector3.new(0.18, 0.32, 0.1), CFrame.new(side * 0.3, 7.08, -1.66), IVORY, Enum.Material.SmoothPlastic)
		eye(rig, "Eye" .. side, 0.38, Vector3.new(side * 0.42, 7.62, -1.66), look.Eyes)
		box(rig, "Brow" .. side, Vector3.new(0.7, 0.2, 0.22), CFrame.new(side * 0.42, 7.98, -1.66) * CFrame.Angles(0, 0, math.rad(side * 22)), darker(skin, 0.45), Enum.Material.SmoothPlastic)
		limb(rig, "Horn" .. side, Vector3.new(side * 0.95, 8.4, -0.4), Vector3.new(side * 1.75, 9.4, 0.1), 0.45, IVORY, Enum.Material.SmoothPlastic)
		orb(rig, "Shoulder" .. side, 2, Vector3.new(side * 2.55, 5.9, 0), fur, Enum.Material.SmoothPlastic)
		limb(rig, "Arm" .. side, Vector3.new(side * 2.6, 5.9, 0), Vector3.new(side * 2.9, 2.5, -0.6), 1.5, fur, Enum.Material.SmoothPlastic)
		orb(rig, "Fist" .. side, 1.9, Vector3.new(side * 2.9, 2.3, -0.6), skin, Enum.Material.SmoothPlastic)
		box(rig, "Leg" .. side, Vector3.new(1.4, 2.3, 1.4), CFrame.new(side * 1.05, 1.15, 0), fur, Enum.Material.SmoothPlastic)
		box(rig, "Foot" .. side, Vector3.new(1.5, 0.5, 1.9), CFrame.new(side * 1.05, 0.25, -0.25), skin, Enum.Material.SmoothPlastic)
	end
end

-- Goblin: bajito y verde, orejas largas, nariz de punta, chaleco de cuero y una daga.
function BUILDERS.Goblin(rig: Rig, look)
	local skin, leather = look.Primary, look.Secondary
	box(rig, "Torso", Vector3.new(1.8, 1.8, 1.2), CFrame.new(0, 2.6, 0), leather, Enum.Material.SmoothPlastic)
	box(rig, "Belt", Vector3.new(1.9, 0.3, 1.3), CFrame.new(0, 1.85, 0), darker(leather, 0.4), Enum.Material.SmoothPlastic)
	box(rig, "Head", Vector3.new(1.7, 1.5, 1.5), CFrame.new(0, 4.2, -0.1), skin, Enum.Material.SmoothPlastic)
	box(rig, "Nose", Vector3.new(0.35, 0.35, 0.65), CFrame.new(0, 4.05, -1.1) * CFrame.Angles(math.rad(-12), 0, 0), darker(skin, 0.15), Enum.Material.SmoothPlastic)
	box(rig, "Teeth", Vector3.new(0.7, 0.16, 0.1), CFrame.new(0, 3.72, -0.88), IVORY, Enum.Material.SmoothPlastic)
	cartoonEyes(rig, Vector3.new(0, 4.4, -0.7), 0.4, 0.62, look)
	for side = -1, 1, 2 do
		box(rig, "Ear" .. side, Vector3.new(1.3, 0.35, 0.5), CFrame.new(side * 1.25, 4.5, 0) * CFrame.Angles(0, math.rad(side * 15), math.rad(side * 22)), skin, Enum.Material.SmoothPlastic)
		limb(rig, "Arm" .. side, Vector3.new(side * 1.1, 3.2, 0), Vector3.new(side * 1.3, 1.95, -0.45), 0.45, skin, Enum.Material.SmoothPlastic)
		orb(rig, "Fist" .. side, 0.6, Vector3.new(side * 1.3, 1.9, -0.45), skin, Enum.Material.SmoothPlastic)
		box(rig, "Leg" .. side, Vector3.new(0.55, 1.3, 0.55), CFrame.new(side * 0.45, 0.65, 0), darker(leather, 0.25), Enum.Material.SmoothPlastic)
		box(rig, "Foot" .. side, Vector3.new(0.65, 0.3, 0.95), CFrame.new(side * 0.45, 0.15, -0.18), darker(skin, 0.3), Enum.Material.SmoothPlastic)
	end
	-- Daga en la mano derecha (va con el brazo: grupo Arm)
	box(rig, "Hand1", Vector3.new(0.18, 0.3, 0.5), CFrame.new(1.3, 1.9, -0.75), WOOD_DARK, Enum.Material.Wood)
	box(rig, "Hand1", Vector3.new(0.12, 0.3, 1.2), CFrame.new(1.3, 1.95, -1.6), STEEL, Enum.Material.Metal)
end

-- Goblin Bruto: un goblin enorme con casco con cuernos, peto de hierro, colmillos y un garrote.
function BUILDERS.GoblinBrute(rig: Rig, look)
	local skin, iron = look.Primary, look.Secondary
	box(rig, "Torso", Vector3.new(3.2, 3.2, 2.4), CFrame.new(0, 4.4, 0), skin, Enum.Material.SmoothPlastic)
	box(rig, "Armor", Vector3.new(3.35, 1.9, 2.55), CFrame.new(0, 5, 0), iron, Enum.Material.Metal)
	box(rig, "Belt", Vector3.new(3.4, 0.5, 2.6), CFrame.new(0, 3.1, 0), WOOD_DARK, Enum.Material.SmoothPlastic)
	box(rig, "Head", Vector3.new(2.2, 1.9, 2), CFrame.new(0, 7, -0.2), skin, Enum.Material.SmoothPlastic)
	box(rig, "Helmet", Vector3.new(2.4, 0.7, 2.2), CFrame.new(0, 8.15, -0.2), iron, Enum.Material.Metal)
	box(rig, "Nose", Vector3.new(0.5, 0.5, 0.7), CFrame.new(0, 6.95, -1.45), darker(skin, 0.15), Enum.Material.SmoothPlastic)
	cartoonEyes(rig, Vector3.new(0, 7.35, -1.05), 0.52, 0.75, look)
	for side = -1, 1, 2 do
		limb(rig, "HelmHorn" .. side, Vector3.new(side * 1.1, 8.3, -0.2), Vector3.new(side * 1.9, 9.4, -0.4), 0.4, IVORY, Enum.Material.SmoothPlastic)
		box(rig, "Ear" .. side, Vector3.new(1.4, 0.4, 0.6), CFrame.new(side * 1.5, 7.3, -0.1) * CFrame.Angles(0, math.rad(side * 12), math.rad(side * 20)), skin, Enum.Material.SmoothPlastic)
		box(rig, "Tusk" .. side, Vector3.new(0.22, 0.55, 0.22), CFrame.new(side * 0.55, 6.35, -1.18), IVORY, Enum.Material.SmoothPlastic)
		orb(rig, "Shoulder" .. side, 1.7, Vector3.new(side * 2.05, 5.6, 0), iron, Enum.Material.Metal)
		limb(rig, "Arm" .. side, Vector3.new(side * 2.05, 5.6, 0), Vector3.new(side * 2.35, 2.8, -0.6), 1, skin, Enum.Material.SmoothPlastic)
		orb(rig, "Fist" .. side, 1.35, Vector3.new(side * 2.35, 2.7, -0.6), skin, Enum.Material.SmoothPlastic)
		box(rig, "Leg" .. side, Vector3.new(1.1, 2, 1.1), CFrame.new(side * 0.8, 1, 0), darker(skin, 0.2), Enum.Material.SmoothPlastic)
	end
	-- Garrote con pinchos (va con el brazo derecho)
	limb(rig, "Hand1", Vector3.new(2.35, 2.5, -0.6), Vector3.new(2.5, 5.4, -2.6), 0.6, WOOD_DARK, Enum.Material.Wood)
	orb(rig, "Hand1", 1.5, Vector3.new(2.5, 5.6, -2.75), Color3.fromRGB(130, 90, 56), Enum.Material.Wood)
	for index = 1, 4 do
		local a = index / 4 * math.pi * 2
		box(rig, "Hand1", Vector3.new(0.25, 0.7, 0.25), CFrame.new(Vector3.new(2.5, 5.6, -2.75) + Vector3.new(math.cos(a) * 0.75, 0.2, math.sin(a) * 0.75)) * CFrame.Angles(math.sin(a) * 0.9, 0, -math.cos(a) * 0.9), STEEL, Enum.Material.Metal)
	end
end

-- Rey Goblin (jefe final del Mundo 1): un goblin gigante con corona de oro y joyas, armadura
-- real, capa roja y un hacha enorme. Ojos rojos que brillan.
function BUILDERS.GoblinKing(rig: Rig, look)
	local skin, royal = look.Primary, look.Secondary
	box(rig, "Torso", Vector3.new(7, 7, 4.6), CFrame.new(0, 9.6, 0), skin, Enum.Material.SmoothPlastic)
	box(rig, "Robe", Vector3.new(7.3, 4.2, 4.9), CFrame.new(0, 8.4, 0), royal, Enum.Material.Fabric)
	box(rig, "Chest", Vector3.new(5.2, 2.6, 0.4), CFrame.new(0, 11.2, -2.45), GOLD, Enum.Material.Metal)
	orb(rig, "Gem", 1.3, Vector3.new(0, 11.2, -2.7), look.Eyes, Enum.Material.Neon)
	box(rig, "Belt", Vector3.new(7.5, 0.9, 5), CFrame.new(0, 6.6, 0), GOLD, Enum.Material.Metal)
	box(rig, "Cape", Vector3.new(7.2, 9.5, 0.4), CFrame.new(0, 8.4, 2.75) * CFrame.Angles(math.rad(-6), 0, 0), royal, Enum.Material.Fabric)
	box(rig, "Head", Vector3.new(4.6, 4, 4.2), CFrame.new(0, 15.2, -0.3), skin, Enum.Material.SmoothPlastic)
	box(rig, "Nose", Vector3.new(0.9, 0.9, 1.5), CFrame.new(0, 14.8, -2.7) * CFrame.Angles(math.rad(-12), 0, 0), darker(skin, 0.15), Enum.Material.SmoothPlastic)
	box(rig, "Mouth", Vector3.new(2.4, 0.4, 0.2), CFrame.new(0, 13.75, -2.42), darker(skin, 0.6), Enum.Material.SmoothPlastic)
	cartoonEyes(rig, Vector3.new(0, 15.7, -2.0), 1.05, 1.5, look)
	-- Corona: aro de oro con picos y joyas
	box(rig, "Crown", Vector3.new(4.9, 1.1, 4.5), CFrame.new(0, 17.7, -0.3), GOLD, Enum.Material.Metal)
	for index = 1, 5 do
		local x = (index - 3) * 1.1
		box(rig, "CrownSpike" .. index, Vector3.new(0.7, if index == 3 then 2 else 1.4, 0.7), CFrame.new(x, 18.6 + (if index == 3 then 0.3 else 0), -2.1) * CFrame.Angles(0, math.rad(45), 0), GOLD, Enum.Material.Metal)
		orb(rig, "CrownGem" .. index, 0.5, Vector3.new(x, 17.7, -2.6), if index % 2 == 1 then look.Eyes else Color3.fromRGB(80, 200, 255), Enum.Material.Neon)
	end
	for side = -1, 1, 2 do
		box(rig, "Ear" .. side, Vector3.new(3.2, 0.7, 1.1), CFrame.new(side * 3.5, 15.8, 0) * CFrame.Angles(0, math.rad(side * 14), math.rad(side * 20)), skin, Enum.Material.SmoothPlastic)
		box(rig, "Tusk" .. side, Vector3.new(0.45, 1.1, 0.45), CFrame.new(side * 0.9, 13.4, -2.45), IVORY, Enum.Material.SmoothPlastic)
		orb(rig, "Shoulder" .. side, 3.3, Vector3.new(side * 4.6, 12.2, 0), GOLD, Enum.Material.Metal)
		limb(rig, "Arm" .. side, Vector3.new(side * 4.6, 12.2, 0), Vector3.new(side * 5.4, 6, -1.6), 2, skin, Enum.Material.SmoothPlastic)
		orb(rig, "Fist" .. side, 2.6, Vector3.new(side * 5.4, 5.8, -1.6), skin, Enum.Material.SmoothPlastic)
		box(rig, "Leg" .. side, Vector3.new(2.4, 4.2, 2.4), CFrame.new(side * 1.75, 2.1, 0), darker(skin, 0.2), Enum.Material.SmoothPlastic)
		box(rig, "Foot" .. side, Vector3.new(2.6, 1, 3.2), CFrame.new(side * 1.75, 0.5, -0.4), WOOD_DARK, Enum.Material.SmoothPlastic)
	end
	-- Hacha enorme en la mano derecha (va con el brazo)
	limb(rig, "Hand1", Vector3.new(5.4, 3.6, -1.6), Vector3.new(5.6, 15.5, -3.4), 0.85, WOOD_DARK, Enum.Material.Wood)
	box(rig, "Hand1", Vector3.new(0.5, 4.2, 3.4), CFrame.new(5.62, 14.2, -4.9) * CFrame.Angles(math.rad(-9), 0, 0), STEEL, Enum.Material.Metal)
	box(rig, "Hand1", Vector3.new(0.6, 4.4, 0.4), CFrame.new(5.62, 14.2, -6.55) * CFrame.Angles(math.rad(-9), 0, 0), lighter(STEEL, 0.4), Enum.Material.Metal)
end

-- Tamaño de la raíz (hitbox de movimiento), altura de cadera y radio de golpe por estilo.
-- Pivots: puntos de giro para la animación del cliente (cuerpo, hombro y cadera del lado
-- derecho; el izquierdo es su reflejo). Solo afectan a la presentación.
local SHAPES = {
	Bramble = { Root = Vector3.new(2.8, 2.8, 2.8), Hip = 0.8, Radius = 1.7, BarHeight = 5.4, Pivots = { Body = Vector3.new(0, 2.2, 0), Leg = Vector3.new(0.75, 0.8, 0) } },
	Brute = { Root = Vector3.new(3, 3.4, 2.2), Hip = 1.6, Radius = 2, BarHeight = 7, Pivots = { Body = Vector3.new(0, 1.9, 0), Arm = Vector3.new(1.9, 4.9, 0), Leg = Vector3.new(0.8, 1.9, 0) } },
	Treant = { Root = Vector3.new(5, 7, 4), Hip = 3, Radius = 4, BarHeight = 19, Pivots = { Body = Vector3.new(0, 3, 0), Arm = Vector3.new(2.3, 9, 0) } },
	Shard = { Root = Vector3.new(2.6, 2.8, 2.6), Hip = 1.2, Radius = 1.7, BarHeight = 5.8, Pivots = { Body = Vector3.new(0, 2.6, 0), Leg = Vector3.new(0.55, 1.2, 0) } },
	Golem = { Root = Vector3.new(3.4, 3.6, 2.6), Hip = 1.8, Radius = 2.2, BarHeight = 8.2, Pivots = { Body = Vector3.new(0, 1.9, 0), Arm = Vector3.new(2.4, 5, 0), Leg = Vector3.new(0.9, 1.9, 0) } },
	Colossus = { Root = Vector3.new(6, 8, 4.5), Hip = 3.5, Radius = 4.5, BarHeight = 18, Pivots = { Body = Vector3.new(0, 3.8, 0), Arm = Vector3.new(4.6, 10.5, 0), Leg = Vector3.new(1.6, 3.8, 0) } },
	-- Hind: pivote de las patas de atrás (cuadrúpedos; si no, el de Leg)
	Wolf = { Root = Vector3.new(2.6, 2.4, 4), Hip = 1.4, Radius = 2, BarHeight = 5.8, Pivots = { Body = Vector3.new(0, 2.4, 0), Leg = Vector3.new(0.72, 2.1, -1.25), Hind = Vector3.new(0.72, 2.1, 1.45) } },
	Yeti = { Root = Vector3.new(3.6, 4, 3), Hip = 2.2, Radius = 2.5, BarHeight = 10.6, Pivots = { Body = Vector3.new(0, 2.3, 0), Arm = Vector3.new(2.6, 5.9, 0), Leg = Vector3.new(1.05, 2.3, 0) } },
	Goblin = { Root = Vector3.new(2.2, 2.6, 2), Hip = 1.3, Radius = 1.6, BarHeight = 6.2, Pivots = { Body = Vector3.new(0, 1.3, 0), Arm = Vector3.new(1.1, 3.2, 0), Leg = Vector3.new(0.45, 1.3, 0) } },
	GoblinBrute = { Root = Vector3.new(3.4, 4, 3), Hip = 2, Radius = 2.4, BarHeight = 10.8, Pivots = { Body = Vector3.new(0, 2, 0), Arm = Vector3.new(2.05, 5.6, 0), Leg = Vector3.new(0.8, 2, 0) } },
	GoblinKing = { Root = Vector3.new(7, 9, 5), Hip = 4.2, Radius = 4.8, BarHeight = 22, Pivots = { Body = Vector3.new(0, 4.2, 0), Arm = Vector3.new(4.6, 12.2, 0), Leg = Vector3.new(1.75, 4.2, 0) } },
}

-- Enemigos del Bosque con los modelos 3D (.glb) de Santiago: Util.ModelosZona1
ModelosZona1.register(BUILDERS, SHAPES)

-- Articulaciones: cada pieza se une a la raíz con un Motor6D cuyo pivote es el de su grupo
-- (cuerpo, brazo o pierna). En reposo equivale a una soldadura; el cliente anima los
-- grupos escribiendo Motor6D.Transform (solo en su pantalla, sin tocar la IA ni la física).
-- Las raíces del Guardián quedan soldadas: están clavadas en el suelo.
local ARM_PARTS = { Arm = true, Fist = true, Hand = true, UpperArm = true, LowerArm = true, Shoulder = true }
local LEG_PARTS = { Leg = true, Foot = true, Hind = true }

local function poseGroup(partName: string): (string, number, string?)
	if partName:sub(1, 4) == "Root" then
		return "Static", 0
	end
	local base, side = partName:match("^(%a+)(%-?1)$")
	if base and ARM_PARTS[base] then
		return "Arm", tonumber(side) or 1, base
	elseif base and LEG_PARTS[base] then
		return "Leg", tonumber(side) or 1, base
	end
	return "Body", 0
end

local function addJoints(rig: Rig, pivots: { [string]: Vector3 })
	for _, part in rig.Model:GetChildren() do
		if not part:IsA("BasePart") or part == rig.Root then
			continue
		end
		local group, side, base = poseGroup(part.Name)
		if group ~= "Static" and not pivots[group] then
			group, side = "Body", 0 -- el estilo no anima ese grupo: va con el cuerpo
		end
		if group == "Static" then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rig.Root
			weld.Part1 = part
			weld.Parent = part
			continue
		end
		-- Patas de atrás de los cuadrúpedos: grupo Leg con su propio pivote (Pivots.Hind)
		local pivot = if group == "Leg" and base == "Hind" and pivots.Hind then pivots.Hind else pivots[group]
		if side ~= 0 then
			pivot = Vector3.new(pivot.X * side, pivot.Y, pivot.Z)
		end
		local motor = Instance.new("Motor6D")
		motor.Name = "Pose"
		motor.Part0 = rig.Root
		motor.Part1 = part
		motor.C0 = rig.Root.CFrame:ToObjectSpace(CFrame.new(pivot))
		motor.C1 = part.CFrame:ToObjectSpace(CFrame.new(pivot))
		motor:SetAttribute("Group", group)
		motor:SetAttribute("Side", side)
		motor:SetAttribute("Pivot", pivot)
		motor.Parent = part
	end
end

local function buildHealthBar(enemy: Enemy, barHeight: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = BAR_SIZES[enemy.Kind] or BAR_SIZES.Normal
	billboard.StudsOffset = Vector3.new(0, barHeight - enemy.RootHeight, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = BAR_DISTANCE[enemy.Kind] or BAR_DISTANCE.Normal
	billboard.Adornee = enemy.Root

	local name = Instance.new("TextLabel")
	name.Name = "EnemyName"
	name.Size = UDim2.new(1, 0, 0.58, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextColor3 = KIND_NAME_COLORS[enemy.Kind] or KIND_NAME_COLORS.Normal
	name.TextStrokeColor3 = Color3.new(0, 0, 0)
	name.TextStrokeTransparency = 0.35
	name.Text = enemy.Def.DisplayName
	name.Parent = billboard

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0.66, 0)
	track.Size = UDim2.new(0.86, 0, 0.26, 0)
	track.BackgroundColor3 = BAR_TRACK
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = track
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = Color3.new(0, 0, 0)
	trackStroke.Transparency = 0.4
	trackStroke.Thickness = 1
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = BAR_HEALTHY
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	billboard.Enabled = false
	billboard.Parent = enemy.Root
	enemy.Bar = fill
	enemy.Billboard = billboard
end

-- Estado visible ------------------------------------------------------------------

local function syncHealth(enemy: Enemy)
	local status = enemy.Status
	enemy.Model:SetAttribute("Health", math.ceil(status.Health))
	enemy.Model:SetAttribute("MaxHealth", status.MaxHealth)
	local fraction = math.clamp(status.Health / status.MaxHealth, 0, 1)
	enemy.Bar.Size = UDim2.fromScale(fraction, 1)
	enemy.Bar.BackgroundColor3 = healthColor(fraction)
end

local function setEyes(enemy: Enemy, color: Color3)
	for _, part in enemy.Eyes do
		part.Color = color
	end
end

-- Color de los ojos cuando no está preparando un golpe.
local function restingEyes(enemy: Enemy): Color3
	return if enemy.Enraged then ENRAGED_EYES else enemy.EyeColor
end

-- Velocidad al andar: la base (con furia) y los estados de control. Solo escribe si cambia.
local function refreshSpeed(enemy: Enemy, now: number)
	local base = enemy.Def.WalkSpeed
	if enemy.Enraged and enemy.Def.Enrage then
		base *= enemy.Def.Enrage.SpeedMultiplier
	end
	local speed = EnemyLogic.speed(base, enemy.Control, now)
	if enemy.Humanoid.WalkSpeed ~= speed then
		enemy.Humanoid.WalkSpeed = speed
	end
end

-- Quita todos los estados (al reaparecer, morir o volver a casa).
local function clearControl(enemy: Enemy)
	EnemyLogic.clearControl(enemy.Control)
	for _, attribute in STATUS_ATTRIBUTES do
		enemy.Model:SetAttribute(attribute, nil)
	end
	enemy.Model:SetAttribute("Aura", nil)
	enemy.Model:SetAttribute("AuraUntil", nil)
end

local function setEnraged(enemy: Enemy, enraged: boolean)
	enemy.Enraged = enraged
	enemy.Model:SetAttribute("Enraged", enraged)
	if enemy.Aura then
		enemy.Aura.Enabled = enraged
	end
	if enemy.Glow then
		enemy.Glow.Enabled = enraged
	end
	setEyes(enemy, restingEyes(enemy))
	refreshSpeed(enemy, os.clock())
end

local function burst(position: Vector3, color: Color3, amount: number, rising: boolean?, run: number?)
	local part = Instance.new("Part")
	tagRun(part, run)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = CFrame.new(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(color)
	emitter.Parent = part
	if rising then
		-- Motas de luz que ascienden: la criatura se disuelve en energía.
		local wisps = Instance.new("ParticleEmitter")
		wisps.Rate = 0
		wisps.Lifetime = NumberRange.new(1, 1.6)
		wisps.Speed = NumberRange.new(2, 4)
		wisps.Acceleration = Vector3.new(0, 8, 0)
		wisps.SpreadAngle = Vector2.new(60, 60)
		wisps.Size = NumberSequence.new(0.6, 0)
		wisps.Transparency = NumberSequence.new(0.1, 1)
		wisps.LightEmission = 1
		wisps.Color = ColorSequence.new(Color3.fromRGB(255, 246, 220), color)
		wisps.Parent = part
		part.Parent = fxFolder
		wisps:Emit(math.floor(amount / 2))
	end
	part.Parent = fxFolder
	emitter:Emit(amount)
	Debris:AddItem(part, 2.5)
end

-- Colocación y ciclo de vida ---------------------------------------------------------

local function place(enemy: Enemy)
	local home = enemy.Home
	local position = home + Vector3.new(0, enemy.RootHeight + 0.5 + StudFloor.raiseAt(home.X, home.Z), 0)
	enemy.Model:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, -1)))
	enemy.Root.AssemblyLinearVelocity = Vector3.zero
end

-- La IA de jefe (más abajo, updateBoss) reinicia su estado al reaparecer
local resetBrain: (Enemy, number) -> ()

local function respawn(enemy: Enemy)
	EnemyLogic.reset(enemy.Status)
	enemy.Target = nil
	clearControl(enemy)
	setEnraged(enemy, false) -- también restablece la velocidad
	enemy.StuckSince = nil
	enemy.LastHomeDistance = math.huge
	local now = os.clock()
	enemy.NextAttack = now + 1
	enemy.WindupUntil = nil
	enemy.NextSlam = now + (if enemy.Def.Slam then enemy.Def.Slam.Interval else math.huge)
	if enemy.Brain then
		resetBrain(enemy, now)
	end
	syncHealth(enemy)
	place(enemy)
	-- La barra de vida permanece oculta hasta que el jugador/mascotas ataquen a este enemigo.
	enemy.Billboard.Enabled = false
	enemy.Model:SetAttribute("AttackAt", nil)
	enemy.Model:SetAttribute("AttackTarget", nil)
	enemy.Model:SetAttribute("SlamAt", nil)
	enemy.Model:SetAttribute("DiedAt", nil)
	enemy.Model:SetAttribute("SpawnedAt", Workspace:GetServerTimeNow())
	enemy.Model.Parent = folder:FindFirstChild(enemy.ZoneId)
	pcall(function()
		enemy.Root:SetNetworkOwner(nil) -- el servidor controla el movimiento, no los clientes
	end)
end

-- Multiplicador del dinero que cobra un jugador: renacimiento y "Botín abundante", amuletos
-- y bendiciones de las aventuras, sus mascotas (CombatConfig.PetMoneyShare de su
-- bonificación) y la Poción de Riqueza (inventario) mientras dura.
local function lootMultiplier(profile): number
	local pets = 1 + math.max(0, (profile.PetMultiplier or 1) - 1) * CombatConfig.PetMoneyShare
	return RebirthLogic.lootMultiplier(RebirthLogic.ofProfile(profile))
		* AdventureLogic.lootMultiplier(AdventureLogic.ofProfile(profile), os.time())
		* pets
		* ItemLogic.multiplier(ItemLogic.ofProfile(profile), "Money", os.time())
end

-- Racha del jugador: sube con este enemigo y se publica para el cliente (Streak y la hora
-- del servidor a la que caduca, StreakUntil).
local function streakOf(player: Player): WaveLogic.Streak
	local streak = streaks[player]
	if not streak then
		streak = WaveLogic.newStreak()
		streaks[player] = streak
	end
	return streak
end

local function publishStreak(player: Player, streak: WaveLogic.Streak, nowClock: number)
	local attributes = Constants.Attributes
	player:SetAttribute(attributes.Streak, streak.Count)
	player:SetAttribute(attributes.StreakUntil, Workspace:GetServerTimeNow() + math.max(0, streak.Until - nowClock))
	player:SetAttribute(attributes.StreakBest, streak.Best)
end

-- Extra de las mejoras de la partida (WaveService): multiplicador del botín y segundos
-- de más en la ventana de la racha. Valores raros se ignoran.
local function killExtras(player: Player, enemy: Enemy): (number, number)
	if not killModifier then
		return 1, 0
	end
	local ok, loot, seconds = pcall(killModifier, player, enemy)
	if not ok then
		return 1, 0
	end
	local cleanLoot = if type(loot) == "number" and loot == loot and loot > 0 and loot < 100 then loot else 1
	local cleanSeconds = if type(seconds) == "number" and seconds == seconds and seconds > 0 and seconds < 30 then seconds else 0
	return cleanLoot, cleanSeconds
end

-- Vuelve a la reserva de las oleadas (una sola vez).
local function release(enemy: Enemy)
	if not enemy.Pooled or enemy.InPool then
		return
	end
	enemy.InPool = true
	local key = enemy.ZoneId .. "/" .. enemy.TypeId .. (if enemy.Variant == "Elite" then "/Elite" else "")
	pools[key] = pools[key] or {}
	table.insert(pools[key], enemy)
end

local function onDeath(enemy: Enemy)
	enemy.Generation += 1
	local generation = enemy.Generation
	enemy.Target = nil
	clearControl(enemy)
	enemy.Humanoid:MoveTo(enemy.Root.Position)
	syncHealth(enemy)
	enemy.Billboard.Enabled = false
	enemy.Model:SetAttribute("DiedAt", Workspace:GetServerTimeNow())

	-- Recompensa: una sola vez por vida (solo llega aquí el golpe que lo mató).
	-- 💰 y 💎 para cada uno según su daño, por la racha, el botín dorado y las mejoras.
	local reward = math.floor(enemy.Def.Reward * enemy.RewardMultiplier)
	local isBoss = enemy.Kind == "Boss"
	local position = enemy.Root.Position
	local nowClock = os.clock()
	for userId, amount in EnemyLogic.splitReward(enemy.Status.Contributions, reward) do
		local player = Players:GetPlayerByUserId(userId)
		local profile = player and PlayerDataService.get(player)
		if player and profile and amount > 0 then
			local lootBonus, streakSeconds = killExtras(player, enemy)
			local streak = streakOf(player)
			local count = WaveLogic.streakKill(streak, nowClock, streakSeconds)
			local golden = WaveLogic.rollGolden(math.random, isBoss)
			local bonus = WaveLogic.streakMultiplier(count) * WaveLogic.goldenMultiplier(golden) * lootBonus
			local earned = math.floor(amount * lootMultiplier(profile) * bonus * enemy.MoneyMultiplier)
			profile.Money += earned
			-- 💎 (en el código, Energy): pocos, por el pase Diamantes ×2, la Poción de Diamantes y
			-- las aventuras (PlayerDataService.diamondMultiplier); lo que no llega a uno entero es
			-- su probabilidad
			local diamonds = WaveLogic.killEnergy(amount, EconomyConfig.KillEnergyShare) * bonus * PlayerDataService.diamondMultiplier(profile)
			local energy = EnergyService.grant(player, WaveLogic.roundDiamonds(diamonds, math.random()))
			if energy <= 0 then
				PlayerDataService.replicate(player) -- grant ya replica si ha sumado energía
			end
			publishStreak(player, streak, nowClock)
			rewardRemote:FireClient(player, earned, enemy.Def.DisplayName, isBoss, position, true, { Energy = energy, Golden = golden, Streak = count })
			-- Cuenta como derrota para quien recibe parte de la recompensa (daño real). Home: dónde
			-- vive (la cueva cuenta los de cada sala); Wave: era de una oleada.
			local info = {
				TypeId = enemy.TypeId,
				Kind = enemy.Kind,
				ZoneId = enemy.ZoneId,
				Reward = earned,
				Energy = energy,
				Golden = golden,
				Streak = count,
				Home = enemy.Home,
				Wave = enemy.Pooled or enemy.WaveControlled,
				Elite = enemy.Variant == "Elite",
				MiniBoss = enemy.Variant == "MiniBoss", -- abre la puerta de su sala (CaveService)
			}
			for _, listener in defeatListeners do
				task.spawn(listener, player, info)
			end
		end
	end

	burst(position, enemy.Def.Look.Secondary, if isBoss then 60 else 20, true, enemy.Run)
	local killer = enemy.LastHitBy
	enemy.LastHitBy = nil
	local dissolve = enemy.DeathSeconds or DISSOLVE_SECONDS[enemy.Kind] or 0.8
	-- Oleadas: ni reaparece solo ni se queda; los de la reserva vuelven a ella.
	if enemy.Pooled or enemy.WaveControlled then
		task.delay(dissolve, function()
			if enemy.Generation == generation then
				enemy.Model.Parent = nil
				release(enemy)
			end
		end)
		local callback = enemy.OnWaveDeath
		enemy.OnWaveDeath = nil
		if callback then
			task.spawn(callback, enemy, killer, position)
		end
		return
	end
	-- Los modelos con animación de muerte (ModelosZona1) se quedan lo que dura esa animación.
	task.delay(dissolve, function()
		if enemy.Generation == generation then
			enemy.Model.Parent = nil -- fuera del mundo hasta reaparecer
		end
	end)
	task.delay(enemy.Def.RespawnSeconds, function()
		if enemy.Generation == generation then
			enemy.Generation += 1
			respawn(enemy)
		end
	end)
end

-- Daño recibido de un jugador (lo llama CombatService tras validar el golpe).
-- Devuelve el daño aplicado, si este golpe lo ha matado y las monedas ganadas en el impacto.
function EnemyService.damage(enemy: Enemy, player: Player, amount: number): (number, boolean, number)
	if enemy.Model.Parent == nil or not sameWorld(enemy, player) then
		return 0, false, 0 -- los de otra partida (o del mundo, si juegas una) no se golpean
	end
	-- Marcado por una maldición: recibe más daño (de todos los jugadores y mascotas).
	local profile = PlayerDataService.get(player)
	if type(amount) == "number" then
		amount = EnemyLogic.damageTaken(amount, enemy.Control, os.clock())
		-- Poción de Fuerza: todo el daño del jugador (disparos, habilidades y mascotas) x2.
		if profile then
			amount *= ItemLogic.multiplier(ItemLogic.ofProfile(profile), "Damage", os.time())
		end
		-- Clase (StyleService): p. ej. más daño a los jefes
		if outgoingModifier then
			local ok, result = pcall(outgoingModifier, player, enemy, amount)
			if ok and type(result) == "number" and result == result then
				amount = math.clamp(result, 0, amount * 3)
			end
		end
	end
	-- Jefe que se parte: ningún golpe lo baja de la vida del corte (ni lo mata de golpe)
	local splitFloor = if enemy.OnSplit and enemy.SplitAt then math.max(1, math.floor(enemy.Status.MaxHealth * enemy.SplitAt)) else nil
	if splitFloor and type(amount) == "number" then
		amount = math.clamp(amount, 0, math.max(0, enemy.Status.Health - splitFloor))
	end
	local dealt, killed = EnemyLogic.applyDamage(enemy.Status, player.UserId, amount)
	if dealt <= 0 then
		return 0, false, 0
	end
	-- Cada golpe al enemigo suelta un poco de dinero al instante
	local earnedHit = 0
	if profile then
		local baseHit = math.max(1, math.floor(enemy.Def.Reward * (dealt / math.max(1, enemy.Status.MaxHealth)) * 0.75))
		earnedHit = math.max(1, math.floor(baseHit * lootMultiplier(profile) * enemy.MoneyMultiplier))
		profile.Money += earnedHit
		PlayerDataService.replicate(player)
		rewardRemote:FireClient(player, earnedHit, enemy.Def.DisplayName, false, enemy.Root.Position, false)
	end
	burst(enemy.Root.Position, enemy.Def.Look.Secondary, 5, false, enemy.Run)
	if killed then
		enemy.LastHitBy = player
		onDeath(enemy)
		return dealt, true, earnedHit
	end
	enemy.Billboard.Enabled = true
	syncHealth(enemy)
	-- Llega al corte: se parte (WaveService lo retira y saca sus dos mitades)
	if splitFloor and enemy.Status.Health <= splitFloor then
		local onSplit = enemy.OnSplit
		enemy.OnSplit = nil
		enemy.SplitAt = nil
		if onSplit then
			task.spawn(onSplit, enemy)
		end
		return dealt, false, earnedHit
	end
	-- Furia del jefe
	local enrage = enemy.Def.Enrage
	if enrage and not enemy.Enraged and enemy.Status.Health <= enemy.Status.MaxHealth * enrage.HealthFraction then
		setEnraged(enemy, true) -- más rápido (refreshSpeed)
		burst(enemy.Root.Position, ENRAGED_EYES, 40, false, enemy.Run)
	end
	-- Quien le golpea se convierte en su objetivo si no tenía uno
	if enemy.Target == nil then
		enemy.Target = player
	end
	return dealt, false, earnedHit
end

function EnemyService.isAlive(enemy: Enemy?): boolean
	return enemy ~= nil and enemy.Model.Parent ~= nil and enemy.Status.State ~= "Dead"
end

-- Estado de una habilidad: "Slow" (factor = velocidad), "Root", "Stun" o "Vulnerable"
-- (factor = daño extra). No afecta a enemigos muertos o volviendo a casa. Devuelve true
-- si se ha aplicado. Lo llama AbilityService (que ya ha ajustado los valores de los jefes).
function EnemyService.applyControl(enemy: Enemy, kind: string, seconds: number, factor: number?): boolean
	if not EnemyService.isAlive(enemy) or enemy.Status.State == "Return" then
		return false
	end
	local now = os.clock()
	if not EnemyLogic.applyControl(enemy.Control, kind, now, seconds, factor, MAX_CONTROL_SECONDS) then
		return false
	end
	local control = enemy.Control
	local untilClock = if kind == "Slow" then control.SlowUntil elseif kind == "Root" then control.RootUntil elseif kind == "Stun" then control.StunUntil else control.VulnerableUntil
	enemy.Model:SetAttribute(STATUS_ATTRIBUTES[kind], Workspace:GetServerTimeNow() + (untilClock - now))
	refreshSpeed(enemy, now)
	if kind == "Root" or kind == "Stun" then
		enemy.Humanoid:MoveTo(enemy.Root.Position) -- se para en seco
	end
	return true
end

-- ¿Está aturdido o congelado ahora? (combos de las habilidades de los estilos)
function EnemyService.isStunned(enemy: Enemy): boolean
	return EnemyService.isAlive(enemy) and EnemyLogic.isStunned(enemy.Control, os.clock())
end

-- Marca elemental para los combos (AbilityService). Devuelve la activa o nil.
function EnemyService.auraOf(enemy: Enemy): string?
	return EnemyLogic.auraOf(enemy.Control, os.clock())
end

-- Pone la marca (o la quita con element = nil). No afecta a muertos o volviendo a casa.
function EnemyService.setAura(enemy: Enemy, element: string?, seconds: number?)
	if not EnemyService.isAlive(enemy) or enemy.Status.State == "Return" then
		return
	end
	local now = os.clock()
	EnemyLogic.setAura(enemy.Control, element, now, seconds, MAX_CONTROL_SECONDS)
	local active = EnemyLogic.auraOf(enemy.Control, now)
	enemy.Model:SetAttribute("Aura", active)
	enemy.Model:SetAttribute("AuraUntil", if active then Workspace:GetServerTimeNow() + (enemy.Control.AuraUntil - now) else nil)
end

-- Retroceso breve lejos de `from` (solo enemigos normales y fuertes; los jefes no se
-- mueven). Un LinearVelocity de KNOCKBACK_SECONDS empuja (el Humanoid anularía una simple
-- velocidad) y el enemigo queda quieto un instante para que su IA no luche contra él.
-- `lift`: parte de la fuerza que va hacia arriba (0.2 si no se dice; el gancho de Puños lo
-- levanta más).
function EnemyService.knockback(enemy: Enemy, from: Vector3, force: number, lift: number?)
	if enemy.Kind == "Boss" or not EnemyService.isAlive(enemy) or enemy.Status.State == "Return" then
		return
	end
	local offset = enemy.Root.Position - from
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	local direction = if flatOffset.Magnitude > 0.05 then flatOffset.Unit else Vector3.new(0, 0, -1)
	local strength = math.clamp(force, 0, 60) * (if enemy.Kind == "Strong" then 0.6 else 1)
	if strength <= 0 then
		return
	end
	-- Quieto un instante (sin atributo: no es un estado que haya que dibujar).
	local now = os.clock()
	EnemyLogic.applyControl(enemy.Control, "Root", now, KNOCKBACK_SECONDS + 0.15, nil, MAX_CONTROL_SECONDS)
	refreshSpeed(enemy, now)
	local attachment = enemy.Root:FindFirstChild("KnockbackAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "KnockbackAttachment"
		attachment.Parent = enemy.Root
	end
	local previous = enemy.Root:FindFirstChild("Knockback")
	if previous then
		previous:Destroy()
	end
	local mover = Instance.new("LinearVelocity")
	mover.Name = "Knockback"
	mover.Attachment0 = attachment :: Attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.MaxForce = 1e7
	mover.VectorVelocity = direction * strength + Vector3.new(0, strength * math.clamp(lift or 0.2, 0, 1), 0)
	mover.Parent = enemy.Root
	Debris:AddItem(mover, KNOCKBACK_SECONDS)
end

-- Marca de presentación (p. ej. "Burn" mientras se quema): solo el atributo para el cliente.
function EnemyService.markStatus(enemy: Enemy, name: string, seconds: number)
	local attribute = STATUS_ATTRIBUTES[name]
	if attribute and EnemyService.isAlive(enemy) and type(seconds) == "number" and seconds > 0 then
		enemy.Model:SetAttribute(attribute, Workspace:GetServerTimeNow() + math.min(seconds, MAX_CONTROL_SECONDS))
	end
end

-- Daño que recibe un jugador (estilo, clase, bloqueo del Guerrero): (jugador, daño, el
-- enemigo que le pega) -> daño final.
function EnemyService.setIncomingDamageModifier(modifier: (Player, number, any?) -> number)
	incomingModifier = modifier
end

function EnemyService.setOutgoingDamageModifier(modifier: (Player, any, number) -> number)
	outgoingModifier = modifier
end

local function damagePlayer(enemy: Enemy, player: Player, humanoid: Humanoid, amount: number)
	if not sameWorld(enemy, player) then
		return -- de otra partida (o del mundo normal mientras juegas una): no te alcanza
	end
	local final = amount * (enemy.DamageMultiplier or 1) -- oleadas: suave al principio, fuerte al final
	if incomingModifier then
		local ok, result = pcall(incomingModifier, player, final, enemy)
		if ok and type(result) == "number" and result == result then
			final = math.clamp(result, 0, final * 2) -- nunca curación ni más del doble (estilo Armas: algo más)
		end
	end
	humanoid:TakeDamage(final) -- respeta el escudo de aparición
end

-- Enemigos vivos dentro de un radio (borde incluido), sin repetidos y como mucho `maxTargets`.
-- Con `viewer`, solo los de su mismo "mundo" (oleadas privadas).
function EnemyService.findInRadius(center: Vector3, radius: number, maxTargets: number, viewer: Player?): { Enemy }
	local candidates = {}
	local byId: { [number]: Enemy } = {}
	local viewerRun = if viewer then runOfPlayer(viewer) else nil
	for _, enemy in enemies do
		if EnemyService.isAlive(enemy) and (viewer == nil or enemy.Run == viewerRun) and math.abs(enemy.Root.Position.Y - center.Y) <= 10 + enemy.RootHeight then
			byId[enemy.Id] = enemy
			table.insert(candidates, { Id = enemy.Id, X = enemy.Root.Position.X, Z = enemy.Root.Position.Z, Radius = enemy.Radius, Alive = true })
		end
	end
	local result = {}
	for _, id in EnemyLogic.selectInRadius(center.X, center.Z, candidates, radius, maxTargets) do
		table.insert(result, byId[id])
	end
	return result
end

-- Objetivos de un golpe (la lógica de alcance y ángulo está en EnemyLogic).
function EnemyService.findTargets(origin: Vector3, look: Vector3, range: number, arcDot: number, maxTargets: number, viewer: Player?): { Enemy }
	local candidates = {}
	local byId: { [number]: Enemy } = {}
	local viewerRun = if viewer then runOfPlayer(viewer) else nil
	for _, enemy in enemies do
		local alive = enemy.Model.Parent ~= nil and enemy.Status.State ~= "Dead" and (viewer == nil or enemy.Run == viewerRun)
		-- Sin golpes a través de suelos o desde muy arriba/abajo
		if alive and math.abs(enemy.Root.Position.Y - origin.Y) <= 10 + enemy.RootHeight then
			byId[enemy.Id] = enemy
			table.insert(candidates, { Id = enemy.Id, X = enemy.Root.Position.X, Z = enemy.Root.Position.Z, Radius = enemy.Radius, Alive = true })
		end
	end
	local result = {}
	for _, id in EnemyLogic.selectTargets(origin.X, origin.Z, look.X, look.Z, candidates, range, arcDot, maxTargets) do
		table.insert(result, byId[id])
	end
	return result
end

-- IA ------------------------------------------------------------------------------

local function characterOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

-- Zonas sin monstruos de una zona (EnemyConfig.Zones.*.SafeAreas), en el mundo
local function safeAreasOf(zoneId: string, zoneSettings): { SafeArea }
	local center = zoneCenter(zoneId)
	local areas = {}
	for _, area in zoneSettings.SafeAreas or {} do
		table.insert(areas, {
			Min = Vector2.new(center.X + area.Min.X, center.Z + area.Min.Y),
			Max = Vector2.new(center.X + area.Max.X, center.Z + area.Max.Y),
		})
	end
	return areas
end

local function inSafeArea(areas: { SafeArea }, position: Vector3): boolean
	for _, area in areas do
		if position.X >= area.Min.X and position.X <= area.Max.X and position.Z >= area.Min.Y and position.Z <= area.Max.Y then
			return true
		end
	end
	return false
end

local function inSafeZone(enemy: Enemy, position: Vector3): boolean
	for _, zone in enemy.SafeZones do
		if flat(position - zone.Center) <= zone.Radius then
			return true
		end
	end
	return inSafeArea(enemy.SafeAreas, position)
end

local function canTarget(enemy: Enemy, position: Vector3): boolean
	return flat(position - enemy.LeashCenter) <= enemy.LeashRadius and not inSafeZone(enemy, position)
end

local function acquireTarget(enemy: Enemy): Player?
	local best, bestDistance = nil, math.huge
	for _, player in Players:GetPlayers() do
		local root = characterOf(player)
		if root then
			local distance = flat(root.Position - enemy.Root.Position)
			local inRange = if enemy.Kind == "Boss" then flat(root.Position - enemy.LeashCenter) <= enemy.LeashRadius - 2 else distance <= enemy.DetectRange
			if inRange and distance < bestDistance and sameWorld(enemy, player) and canTarget(enemy, root.Position) then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

-- Golpe cuerpo a cuerpo avisado: el bicho se compromete (se queda quieto mirando a su
-- objetivo durante AttackWindup, con los ojos encendidos) y al final pega solo por delante y
-- a su alcance: apartarse o rodearlo lo esquiva; el Guerrero puede bloquearlo o pararlo.
-- Atributos para el cliente (AttackWarning y EnemyAnimator): AttackTarget (UserId de a quién
-- va), AttackDir (hacia dónde), AttackReach (alcance) y AttackAt (hora del golpe).
local HIT_SLACK = 1.5 -- studs de margen al validar el golpe
local FRONT_DOT = -0.1 -- un poco más de medio círculo por delante
local function attack(enemy: Enemy, target: Player)
	local generation = enemy.Generation
	local windup = enemy.Def.AttackWindup
	local origin = enemy.Root.Position
	local targetRoot = characterOf(target)
	local forward = if targetRoot then Vector3.new(targetRoot.Position.X - origin.X, 0, targetRoot.Position.Z - origin.Z) else Vector3.zero
	if forward.Magnitude > 0.05 then
		forward = forward.Unit
		enemy.Root.CFrame = CFrame.lookAt(origin, origin + forward)
	else
		local look = enemy.Root.CFrame.LookVector
		forward = Vector3.new(look.X, 0, look.Z)
		forward = if forward.Magnitude > 0.05 then forward.Unit else Vector3.new(0, 0, -1)
	end
	local reach = enemy.Def.AttackRange + enemy.Radius + HIT_SLACK
	enemy.WindupUntil = os.clock() + windup
	enemy.Humanoid:MoveTo(origin)
	setEyes(enemy, WINDUP_EYES) -- aviso del golpe
	enemy.Model:SetAttribute("AttackTarget", target.UserId)
	enemy.Model:SetAttribute("AttackDir", forward)
	enemy.Model:SetAttribute("AttackReach", reach)
	-- Momento del golpe para la animación y el aviso del cliente (preparación y golpe).
	enemy.Model:SetAttribute("AttackAt", Workspace:GetServerTimeNow() + windup)
	task.delay(windup, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" then
			return
		end
		enemy.WindupUntil = nil
		setEyes(enemy, restingEyes(enemy))
		if EnemyLogic.isStunned(enemy.Control, os.clock()) then
			return -- aturdido durante la preparación: el golpe se pierde
		end
		local root, humanoid = characterOf(target)
		if not (root and humanoid) then
			return
		end
		local offset = Vector3.new(root.Position.X - enemy.Root.Position.X, 0, root.Position.Z - enemy.Root.Position.Z)
		local distance = offset.Magnitude
		local inFront = distance < enemy.Radius + 1 or offset.Unit:Dot(forward) >= FRONT_DOT
		if distance <= reach and inFront then
			damagePlayer(enemy, target, humanoid, enemy.Def.Damage)
		end
	end)
end

-- Golpe en área del jefe: círculo de aviso en el suelo y daño al terminar.
local function slam(enemy: Enemy)
	local settings = enemy.Def.Slam
	local generation = enemy.Generation
	local center = Vector3.new(enemy.Root.Position.X, GROUND, enemy.Root.Position.Z)
	local diameter = settings.Radius * 2
	local warningColor = if enemy.Enraged then ENRAGED_EYES else enemy.Def.Look.Eyes
	enemy.Model:SetAttribute("SlamAt", Workspace:GetServerTimeNow() + settings.Telegraph)
	-- Borde del área (fijo) y disco interior que crece: cuando llena el borde, golpea.
	local ring = PartFactory.verticalCylinder(nil :: any, "SlamWarning", center + Vector3.new(0, 0.32, 0), 0.12, diameter, warningColor, Enum.Material.Neon, false)
	ring.Transparency = 0.55 -- borde bien visible: aquí acaba el área
	placeFx(ring, enemy.Run)
	local fill = PartFactory.verticalCylinder(nil :: any, "SlamFill", center + Vector3.new(0, 0.36, 0), 0.14, 1, warningColor, Enum.Material.Neon, false)
	fill.Transparency = 0.55
	placeFx(fill, enemy.Run)
	TweenService:Create(fill, TweenInfo.new(settings.Telegraph, Enum.EasingStyle.Linear), { Size = Vector3.new(0.14, diameter, diameter) }):Play()
	Debris:AddItem(ring, settings.Telegraph + 0.1)
	Debris:AddItem(fill, settings.Telegraph + 0.1)
	task.delay(settings.Telegraph, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" then
			return
		end
		if EnemyLogic.isStunned(enemy.Control, os.clock()) then
			return -- aturdido justo al golpear: el golpe en área se interrumpe
		end
		burst(center + Vector3.new(0, 1, 0), enemy.Def.Look.Secondary, 30, false, enemy.Run)
		-- Onda expansiva breve
		local wave = PartFactory.verticalCylinder(nil :: any, "SlamWave", center + Vector3.new(0, 0.4, 0), 0.3, diameter * 0.6, warningColor, Enum.Material.Neon, false)
		wave.Transparency = 0.3
		placeFx(wave, enemy.Run)
		TweenService:Create(wave, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, diameter * 1.15, diameter * 1.15), Transparency = 1 }):Play()
		Debris:AddItem(wave, 0.45)
		for _, player in Players:GetPlayers() do
			local root, humanoid = characterOf(player)
			if root and humanoid and flat(root.Position - center) <= settings.Radius and math.abs(root.Position.Y - center.Y) < 12 then
				damagePlayer(enemy, player, humanoid, settings.Damage)
			end
		end
	end)
end

-- IA de jefe ------------------------------------------------------------------------
-- Máquina de estados de cada jefe (enemy.Brain.State, Def.Brain):
-- - "Patrol": vigila su arena andando de un sitio a otro.
-- - "Chase": persigue a su objetivo (lo ve a DetectRange o le ha disparado). Si algo se
--   interpone usa una ruta de PathfindingService, que solo se recalcula cuando el objetivo
--   se ha movido bastante, cuando se atasca o cada PATH_REFRESH. Nunca sale de su
--   territorio (Territory studs desde el centro de la arena): si el objetivo se aleja más
--   de Territory + LOSE_MARGIN, muere o entra en una zona segura, lo deja.
-- - "Busy": prepara o hace un ataque. Cada ataque se anuncia (ojos rojos y una marca en
--   el suelo durante su Telegraph) y su daño se valida al final con la posición real.
-- - "Recover": descansa RecoverSeconds tras atacar (ventana para contraatacar).
-- - "Return": vuelve al centro de su arena (invulnerable, como todos) y se cura al llegar.
-- Un objetivo se mantiene LockSeconds aunque otro jugador esté más cerca.
-- Ataques: golpe cuerpo a cuerpo (Damage) y los especiales de su tipo: Slam (área a su
-- alrededor), Roots (atrapa y ralentiza donde estás), Charge (embestida en línea), Leap
-- (salta y cae donde estabas) y Volley (bolas de fuego que se pueden esquivar).

local PATH_REFRESH = 1.5 -- segundos mínimos entre rutas para el mismo objetivo quieto
local PATH_GOAL_MOVED = 6 -- studs que debe moverse el objetivo para recalcular la ruta
local WAYPOINT_REACHED = 3
local LOSE_MARGIN = 12
local STUCK_SECONDS = 1.2
local TELEGRAPH_RED = Color3.fromRGB(255, 70, 60)

type Brain = {
	State: string,
	Until: number,
	LockedUntil: number,
	Path: { Vector3 }?,
	PathIndex: number,
	PathGoal: Vector3?,
	PathAt: number,
	Computing: boolean,
	NextSpecial: { [string]: number },
	LastPosition: Vector3,
	StillSince: number,
	Dash: { Hit: { [Player]: boolean }, Until: number, Damage: number, Width: number }?,
}

local SPECIALS = { "Slam", "Roots", "Charge", "Leap", "Volley" }

local function newBrain(): Brain
	return {
		State = "Patrol",
		Until = 0,
		LockedUntil = 0,
		Path = nil,
		PathIndex = 1,
		PathGoal = nil,
		PathAt = -math.huge,
		Computing = false,
		NextSpecial = {},
		LastPosition = Vector3.zero,
		StillSince = 0,
		Dash = nil,
	}
end

-- Al reaparecer: patrulla y los especiales escalonados (no todos a la vez al empezar)
function resetBrain(enemy: Enemy, now: number)
	local brain = enemy.Brain :: Brain
	brain.State = "Patrol"
	brain.Until = 0
	brain.LockedUntil = 0
	brain.Path = nil
	brain.PathGoal = nil
	brain.Dash = nil
	for index, name in SPECIALS do
		local settings = enemy.Def[name]
		if settings then
			brain.NextSpecial[name] = now + settings.Interval * 0.5 + index
		end
	end
	enemy.Model:SetAttribute("TargetUserId", nil)
	enemy.Model:SetAttribute("BossState", "Patrol")
end

local function setBossState(enemy: Enemy, state: string)
	local brain = enemy.Brain :: Brain
	if brain.State ~= state then
		brain.State = state
		enemy.Model:SetAttribute("BossState", state)
	end
end

local function territoryOf(enemy: Enemy): number
	return enemy.Territory or enemy.Def.Brain.Territory
end

-- Punto dentro del territorio (el jefe nunca sale de él)
local function clampToTerritory(enemy: Enemy, point: Vector3): Vector3
	local offset = point - enemy.LeashCenter
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	local limit = territoryOf(enemy) - 2
	if flatOffset.Magnitude > limit then
		flatOffset = flatOffset.Unit * limit
	end
	return Vector3.new(enemy.LeashCenter.X + flatOffset.X, point.Y, enemy.LeashCenter.Z + flatOffset.Z)
end

local function bossCanTarget(enemy: Enemy, position: Vector3): boolean
	return flat(position - enemy.LeashCenter) <= territoryOf(enemy) + LOSE_MARGIN and not inSafeZone(enemy, position)
end

local function bossAcquire(enemy: Enemy): Player?
	local best, bestDistance = nil, enemy.Def.Brain.DetectRange
	for _, player in Players:GetPlayers() do
		local root = characterOf(player)
		if root then
			local distance = flat(root.Position - enemy.Root.Position)
			if distance <= bestDistance and sameWorld(enemy, player) and flat(root.Position - enemy.LeashCenter) <= territoryOf(enemy) and bossCanTarget(enemy, root.Position) then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

-- ¿Hay algo entre el jefe y el punto? (sin contar enemigos ni personajes)
local function lineBlocked(enemy: Enemy, goal: Vector3): boolean
	local origin = enemy.Root.Position
	local direction = Vector3.new(goal.X - origin.X, 0, goal.Z - origin.Z)
	if direction.Magnitude < 1 then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	-- A media altura del cuerpo: el suelo y las alfombras no cuentan como obstáculo
	local hit = Workspace:Raycast(origin + Vector3.new(0, 1, 0), direction, params)
	return hit ~= nil and hit.Instance.CanCollide
end

local function requestPath(enemy: Enemy, goal: Vector3)
	local brain = enemy.Brain :: Brain
	if brain.Computing then
		return
	end
	brain.Computing = true
	brain.PathAt = os.clock()
	brain.PathGoal = goal
	local generation = enemy.Generation
	local from = enemy.Root.Position
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = math.max(2, enemy.Radius), AgentHeight = 6, AgentCanJump = false, WaypointSpacing = 5 })
		local ok = pcall(function()
			path:ComputeAsync(from, goal)
		end)
		brain.Computing = false
		if enemy.Generation ~= generation then
			return
		end
		if ok and path.Status == Enum.PathStatus.Success then
			local points = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
			end
			brain.Path = points
			brain.PathIndex = math.min(2, #points)
		else
			brain.Path = nil -- sin ruta: va en línea recta (y si se atasca, lo deja)
		end
	end)
end

-- Andar hacia `goal` (dentro del territorio): recto si nada lo impide; si no, por la ruta.
local function bossMoveTo(enemy: Enemy, goal: Vector3, now: number)
	local brain = enemy.Brain :: Brain
	goal = clampToTerritory(enemy, goal)
	if not lineBlocked(enemy, goal) then
		brain.Path = nil
		enemy.Humanoid:MoveTo(goal)
		return
	end
	local stale = brain.PathGoal == nil or flat(goal - brain.PathGoal) > PATH_GOAL_MOVED or (now - brain.PathAt > PATH_REFRESH and now - brain.StillSince > STUCK_SECONDS)
	if (brain.Path == nil or stale) and now - brain.PathAt > 0.4 then
		requestPath(enemy, goal)
	end
	local path = brain.Path
	if path and path[brain.PathIndex] then
		local waypoint = path[brain.PathIndex]
		if flat(waypoint - enemy.Root.Position) < WAYPOINT_REACHED and brain.PathIndex < #path then
			brain.PathIndex += 1
			waypoint = path[brain.PathIndex]
		end
		enemy.Humanoid:MoveTo(waypoint)
	else
		enemy.Humanoid:MoveTo(goal)
	end
end

-- Marca de aviso en el suelo: borde fijo y un disco que crece hasta llenarlo cuando golpea
local function telegraphDisc(center: Vector3, radius: number, color: Color3, seconds: number, run: number?)
	local ground = Vector3.new(center.X, GROUND + StudFloor.raiseAt(center.X, center.Z), center.Z)
	local diameter = radius * 2
	local ring = PartFactory.verticalCylinder(nil :: any, "BossWarning", ground + Vector3.new(0, 0.32, 0), 0.12, diameter, color, Enum.Material.Neon, false)
	ring.Transparency = 0.55
	placeFx(ring, run)
	local fill = PartFactory.verticalCylinder(nil :: any, "BossWarningFill", ground + Vector3.new(0, 0.36, 0), 0.14, 1, color, Enum.Material.Neon, false)
	fill.Transparency = 0.55
	placeFx(fill, run)
	TweenService:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = Vector3.new(0.14, diameter, diameter) }):Play()
	Debris:AddItem(ring, seconds + 0.1)
	Debris:AddItem(fill, seconds + 0.1)
end

-- Franja de aviso de la embestida, de `from` a `to`
local function telegraphStrip(from: Vector3, to: Vector3, width: number, color: Color3, seconds: number, run: number?)
	local a = Vector3.new(from.X, GROUND + 0.34 + StudFloor.raiseAt(from.X, from.Z), from.Z)
	local b = Vector3.new(to.X, a.Y, to.Z)
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	local strip = PartFactory.part(nil :: any, "BossChargeWarning", {
		Size = Vector3.new(width, 0.12, length),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = color,
		Material = Enum.Material.Neon,
		Solid = false,
	})
	strip.Transparency = 0.5
	placeFx(strip, run)
	Debris:AddItem(strip, seconds + 0.1)
end

-- Ralentiza a un jugador un rato (deja su velocidad como estaba si nadie la ha cambiado)
local function slowPlayer(humanoid: Humanoid, factor: number, seconds: number)
	local before = humanoid.WalkSpeed
	local slowed = before * factor
	humanoid.WalkSpeed = slowed
	humanoid:SetAttribute("SlowedUntil", Workspace:GetServerTimeNow() + seconds)
	task.delay(seconds, function()
		if humanoid.Parent and math.abs(humanoid.WalkSpeed - slowed) < 0.01 then
			humanoid.WalkSpeed = before
		end
	end)
end

local function damageInRadius(enemy: Enemy, center: Vector3, radius: number, damage: number, onHit: ((Player, Humanoid) -> ())?)
	for _, player in Players:GetPlayers() do
		local root, humanoid = characterOf(player)
		if root and humanoid and sameWorld(enemy, player) and flat(root.Position - center) <= radius and math.abs(root.Position.Y - center.Y) < 12 then
			damagePlayer(enemy, player, humanoid, damage)
			if onHit then
				onHit(player, humanoid)
			end
		end
	end
end

-- Ocupado `seconds` (sin moverse ni elegir otro ataque) y después a descansar
local function busyThenRecover(enemy: Enemy, seconds: number)
	local brain = enemy.Brain :: Brain
	setBossState(enemy, "Busy")
	brain.Until = os.clock() + seconds
	enemy.Humanoid:MoveTo(enemy.Root.Position)
end

local function intervalOf(enemy: Enemy, settings): number
	if enemy.Enraged and enemy.Def.Enrage then
		return settings.Interval * enemy.Def.Enrage.SlamIntervalMultiplier
	end
	return settings.Interval
end

local function faceTowards(enemy: Enemy, point: Vector3): Vector3
	local origin = enemy.Root.Position
	local forward = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	forward = if forward.Magnitude > 0.05 then forward.Unit else Vector3.new(0, 0, -1)
	enemy.Root.CFrame = CFrame.lookAt(origin, origin + forward)
	return forward
end

-- Golpe cuerpo a cuerpo con aviso: un disco rojo delante y los ojos encendidos
local function bossStrike(enemy: Enemy, target: Player, targetRoot: BasePart)
	local reach = enemy.Def.AttackRange + enemy.Radius
	local forward = faceTowards(enemy, targetRoot.Position)
	telegraphDisc(enemy.Root.Position + forward * reach * 0.5, reach * 0.55, TELEGRAPH_RED, enemy.Def.AttackWindup, enemy.Run)
	attack(enemy, target) -- ojos, animación y daño validado al terminar la preparación
	busyThenRecover(enemy, enemy.Def.AttackWindup + 0.15)
end

local function bossSlam(enemy: Enemy)
	slam(enemy) -- círculo que se llena, onda y daño
	busyThenRecover(enemy, enemy.Def.Slam.Telegraph + 0.1)
end

local function bossRoots(enemy: Enemy, targetPosition: Vector3)
	local settings = enemy.Def.Roots
	local generation = enemy.Generation
	local center = Vector3.new(targetPosition.X, GROUND, targetPosition.Z)
	faceTowards(enemy, targetPosition)
	telegraphDisc(center, settings.Radius, enemy.Def.Look.Secondary, settings.Telegraph, enemy.Run)
	setEyes(enemy, WINDUP_EYES)
	task.delay(settings.Telegraph, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" then
			return
		end
		setEyes(enemy, restingEyes(enemy))
		burst(center + Vector3.new(0, 1, 0), enemy.Def.Look.Secondary, 25, false, enemy.Run)
		for index = 1, 6 do
			local angle = index / 6 * math.pi * 2
			local spike = PartFactory.part(nil :: any, "RootSpike", {
				Size = Vector3.new(0.8, 4, 0.8),
				CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * settings.Radius * 0.6, 1.5, math.sin(angle) * settings.Radius * 0.6)) * CFrame.Angles(math.rad(15), angle, 0),
				Color = enemy.Def.Look.Primary,
				Material = Enum.Material.Wood,
				Solid = false,
			})
			placeFx(spike, enemy.Run)
			Debris:AddItem(spike, 1.2)
		end
		damageInRadius(enemy, center, settings.Radius, settings.Damage, function(_player, humanoid)
			slowPlayer(humanoid, settings.SlowFactor, settings.SlowSeconds)
		end)
	end)
	busyThenRecover(enemy, 0.5) -- lanza las raíces y sigue
end

local function bossCharge(enemy: Enemy, targetPosition: Vector3)
	local settings = enemy.Def.Charge
	local brain = enemy.Brain :: Brain
	local generation = enemy.Generation
	local origin = enemy.Root.Position
	local direction = faceTowards(enemy, targetPosition)
	local finish = clampToTerritory(enemy, origin + direction * settings.Distance)
	telegraphStrip(origin, finish, settings.Width, TELEGRAPH_RED, settings.Telegraph, enemy.Run)
	setEyes(enemy, WINDUP_EYES)
	local dashSeconds = flat(finish - origin) / settings.Speed + 0.2
	busyThenRecover(enemy, settings.Telegraph + dashSeconds)
	task.delay(settings.Telegraph, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" or EnemyLogic.isStunned(enemy.Control, os.clock()) then
			return
		end
		setEyes(enemy, restingEyes(enemy))
		brain.Dash = { Hit = {}, Until = os.clock() + dashSeconds, Damage = settings.Damage, Width = settings.Width }
		enemy.Humanoid.WalkSpeed = settings.Speed
		enemy.Humanoid:MoveTo(finish)
	end)
end

-- Durante la embestida: cada jugador que toque la franja recibe el golpe una sola vez
local function updateDash(enemy: Enemy, now: number)
	local brain = enemy.Brain :: Brain
	local dash = brain.Dash
	if not dash then
		return
	end
	if now >= dash.Until then
		brain.Dash = nil
		refreshSpeed(enemy, now)
		return
	end
	for _, player in Players:GetPlayers() do
		local root, humanoid = characterOf(player)
		if root and humanoid and not dash.Hit[player] and flat(root.Position - enemy.Root.Position) <= dash.Width / 2 + enemy.Radius then
			dash.Hit[player] = true
			damagePlayer(enemy, player, humanoid, dash.Damage)
		end
	end
end

local function bossLeap(enemy: Enemy, targetPosition: Vector3)
	local settings = enemy.Def.Leap
	local generation = enemy.Generation
	local landing = clampToTerritory(enemy, Vector3.new(targetPosition.X, GROUND, targetPosition.Z))
	faceTowards(enemy, landing)
	telegraphDisc(landing, settings.Radius, TELEGRAPH_RED, settings.Telegraph + 0.5, enemy.Run)
	setEyes(enemy, WINDUP_EYES)
	busyThenRecover(enemy, settings.Telegraph + 0.7)
	task.delay(settings.Telegraph, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" or EnemyLogic.isStunned(enemy.Control, os.clock()) then
			return
		end
		-- Vuelo en arco (el cuerpo va anclado mientras salta)
		local start = enemy.Root.Position
		local finish = landing + Vector3.new(0, enemy.RootHeight + 0.5 + StudFloor.raiseAt(landing.X, landing.Z), 0)
		local heading = Vector3.new(finish.X - start.X, 0, finish.Z - start.Z)
		heading = if heading.Magnitude > 0.05 then heading.Unit else Vector3.new(0, 0, -1)
		local flight = 0.5
		local began = os.clock()
		enemy.Root.Anchored = true
		while os.clock() - began < flight do
			if enemy.Generation ~= generation then
				enemy.Root.Anchored = false
				return
			end
			local t = (os.clock() - began) / flight
			local point = start:Lerp(finish, t) + Vector3.new(0, math.sin(t * math.pi) * 12, 0)
			enemy.Model:PivotTo(CFrame.lookAt(point, point + heading))
			RunService.Heartbeat:Wait()
		end
		enemy.Model:PivotTo(CFrame.lookAt(finish, finish + heading))
		enemy.Root.Anchored = false
		pcall(function()
			enemy.Root:SetNetworkOwner(nil)
		end)
		setEyes(enemy, restingEyes(enemy))
		burst(landing + Vector3.new(0, 1, 0), enemy.Def.Look.Secondary, 35, false, enemy.Run)
		damageInRadius(enemy, landing + Vector3.new(0, enemy.RootHeight, 0), settings.Radius, settings.Damage)
	end)
end

local function bossVolley(enemy: Enemy, target: Player)
	local settings = enemy.Def.Volley
	local generation = enemy.Generation
	setEyes(enemy, WINDUP_EYES)
	busyThenRecover(enemy, settings.Telegraph + settings.Count * 0.3)
	task.delay(settings.Telegraph, function()
		for _ = 1, settings.Count do
			if enemy.Generation ~= generation or enemy.Status.State == "Dead" then
				return
			end
			local root = characterOf(target)
			if root then
				-- Va hacia donde estaba el jugador al lanzarla: moverse la esquiva
				local from = enemy.Root.Position + Vector3.new(0, 3, 0)
				local aim = root.Position
				faceTowards(enemy, aim)
				local travel = math.max(0.2, (aim - from).Magnitude / settings.Speed)
				local ball = PartFactory.ball(nil :: any, "BossFireball", from, 1.6, enemy.Def.Look.Secondary, Enum.Material.Neon, false)
				placeFx(ball, enemy.Run)
				task.spawn(function()
					local began = os.clock()
					local hit: { [Player]: boolean } = {}
					while os.clock() - began < travel and ball.Parent do
						local position = from:Lerp(aim, (os.clock() - began) / travel)
						ball.Position = position
						for _, player in Players:GetPlayers() do
							local playerRoot, humanoid = characterOf(player)
							if playerRoot and humanoid and not hit[player] and (playerRoot.Position - position).Magnitude <= settings.Radius then
								hit[player] = true
								damagePlayer(enemy, player, humanoid, settings.Damage)
							end
						end
						RunService.Heartbeat:Wait()
					end
					burst(aim, enemy.Def.Look.Secondary, 10, false, enemy.Run)
					ball:Destroy()
				end)
			end
			task.wait(0.3)
		end
		if enemy.Generation == generation then
			setEyes(enemy, restingEyes(enemy))
		end
	end)
end

-- Elige y lanza un ataque si hay alguno listo (true si ha atacado)
local function bossTryAttack(enemy: Enemy, target: Player, targetRoot: BasePart, now: number): boolean
	local brain = enemy.Brain :: Brain
	local def = enemy.Def
	local distance = flat(targetRoot.Position - enemy.Root.Position)
	local function ready(name: string): boolean
		return def[name] ~= nil and now >= (brain.NextSpecial[name] or 0)
	end
	local function used(name: string)
		brain.NextSpecial[name] = now + intervalOf(enemy, def[name])
	end
	if ready("Slam") and distance <= def.Slam.Radius + 2 then
		used("Slam")
		bossSlam(enemy)
		return true
	end
	if ready("Charge") and distance >= def.Charge.MinRange and distance <= def.Charge.MaxRange then
		used("Charge")
		bossCharge(enemy, targetRoot.Position)
		return true
	end
	if ready("Leap") and distance >= def.Leap.MinRange and distance <= def.Leap.MaxRange then
		used("Leap")
		bossLeap(enemy, targetRoot.Position)
		return true
	end
	if ready("Volley") and distance <= def.Volley.Range then
		used("Volley")
		bossVolley(enemy, target)
		return true
	end
	if ready("Roots") and distance <= def.Roots.Range then
		used("Roots")
		bossRoots(enemy, targetRoot.Position)
		return true
	end
	if now >= enemy.NextAttack and distance <= def.AttackRange + enemy.Radius then
		enemy.NextAttack = now + EnemyLogic.attackCooldown(def.AttackCooldown, enemy.Control, now)
		bossStrike(enemy, target, targetRoot)
		return true
	end
	return false
end

local function updateBoss(enemy: Enemy, now: number)
	local status = enemy.Status
	if status.State == "Dead" or enemy.Model.Parent == nil then
		return
	end
	local brain = enemy.Brain :: Brain
	local def = enemy.Def
	local position = enemy.Root.Position
	if (position - brain.LastPosition).Magnitude > 0.5 then
		brain.LastPosition = position
		brain.StillSince = now
	end
	updateDash(enemy, now)
	if not brain.Dash then
		refreshSpeed(enemy, now)
	end

	-- Vuelta a la arena (invulnerable) y curación al llegar
	if status.State == "Return" then
		setBossState(enemy, "Return")
		enemy.Model:SetAttribute("TargetUserId", nil)
		if flat(position - enemy.Home) < 4 then
			EnemyLogic.reset(status)
			syncHealth(enemy)
			setEnraged(enemy, false)
			status.State = "Idle"
			setBossState(enemy, "Patrol")
			return
		end
		bossMoveTo(enemy, enemy.Home, now)
		if now - brain.StillSince > EnemyConfig.StuckSeconds then
			place(enemy) -- atascado volviendo: reaparece en el centro
			brain.StillSince = now
		end
		return
	end

	-- Preparando o haciendo un ataque / descansando
	if brain.State == "Busy" then
		if now < brain.Until then
			return
		end
		setBossState(enemy, "Recover")
		brain.Until = now + def.Brain.RecoverSeconds
		enemy.Humanoid:MoveTo(position)
		return
	end
	if brain.State == "Recover" and now < brain.Until then
		return
	end

	-- Objetivo: se mantiene LockSeconds; si deja de valer, el más cercano que vea
	local previous = enemy.Target
	local target = previous
	local targetRoot = if target and target.Parent then characterOf(target) else nil
	if not (targetRoot and sameWorld(enemy, target) and bossCanTarget(enemy, targetRoot.Position)) then
		target, targetRoot = nil, nil
	elseif now >= brain.LockedUntil then
		local closer = bossAcquire(enemy)
		if closer and closer ~= target then
			target = closer
			targetRoot = characterOf(closer)
		end
	end
	if not target then
		target = bossAcquire(enemy)
		targetRoot = if target then characterOf(target) else nil
	end
	if target ~= previous then
		brain.LockedUntil = now + def.Brain.LockSeconds
		brain.Path = nil
	end
	enemy.Target = target
	enemy.Model:SetAttribute("TargetUserId", if target then target.UserId else nil)

	if not (target and targetRoot) then
		-- Sin nadie: si se alejó de la arena vuelve; si no, patrulla
		if flat(position - enemy.LeashCenter) > enemy.LeashRadius + 2 then
			status.State = "Return"
			clearControl(enemy)
			setEyes(enemy, restingEyes(enemy))
			return
		end
		status.State = "Idle"
		setBossState(enemy, "Patrol")
		if now >= enemy.NextWander then
			enemy.NextWander = now + math.random(40, 70) / 10
			local angle = math.random() * math.pi * 2
			enemy.Humanoid:MoveTo(enemy.Home + Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.random(3, math.max(4, math.floor(enemy.LeashRadius * 0.6))))
		end
		return
	end

	-- Aturdido por una habilidad: ni se mueve ni ataca
	if EnemyLogic.isStunned(enemy.Control, now) then
		return
	end
	if bossTryAttack(enemy, target, targetRoot, now) then
		status.State = "Attack"
		return
	end
	status.State = "Chase"
	setBossState(enemy, "Chase")
	bossMoveTo(enemy, targetRoot.Position, now)
end

local function updateEnemy(enemy: Enemy, now: number)
	local status = enemy.Status
	if status.State == "Dead" or enemy.Model.Parent == nil then
		return
	end
	local position = enemy.Root.Position
	local fromHome = flat(position - enemy.LeashCenter)
	refreshSpeed(enemy, now) -- los estados caducan solos: aquí se recupera la velocidad

	-- Volver a casa (invulnerable) y curarse al llegar; si se atasca, reaparece en su origen.
	if status.State == "Return" then
		if flat(position - enemy.Home) < 3 then
			EnemyLogic.reset(status)
			syncHealth(enemy)
			setEnraged(enemy, false) -- también restablece la velocidad
			return
		end
		enemy.Humanoid:MoveTo(enemy.Home)
		if fromHome >= enemy.LastHomeDistance - 0.3 then
			enemy.StuckSince = enemy.StuckSince or now
			if now - enemy.StuckSince > EnemyConfig.StuckSeconds then
				place(enemy)
				enemy.StuckSince = nil
			end
		else
			enemy.StuckSince = nil
		end
		enemy.LastHomeDistance = fromHome
		return
	end

	-- Demasiado lejos de su zona: volver.
	if fromHome > enemy.LeashRadius + 4 then
		status.State = "Return"
		enemy.Target = nil
		clearControl(enemy) -- vuelve sin estados (es invulnerable mientras vuelve)
		refreshSpeed(enemy, now)
		enemy.LastHomeDistance = math.huge
		setEyes(enemy, restingEyes(enemy))
		return
	end

	-- Validar u obtener objetivo
	local target = enemy.Target
	local targetRoot = if target and target.Parent then characterOf(target) else nil
	if not (targetRoot and sameWorld(enemy, target) and canTarget(enemy, targetRoot.Position) and flat(targetRoot.Position - enemy.LeashCenter) <= enemy.LeashRadius + 6) then
		enemy.Target = nil
		target = acquireTarget(enemy)
		enemy.Target = target
		targetRoot = if target then characterOf(target) else nil
	end

	if not (target and targetRoot) then
		status.State = "Idle"
		if now >= enemy.NextWander then
			enemy.NextWander = now + math.random(40, 80) / 10
			local angle = math.random() * math.pi * 2
			enemy.Humanoid:MoveTo(enemy.Home + Vector3.new(math.cos(angle), 0, math.sin(angle)) * math.random(2, 6))
		end
		return
	end

	-- Aturdido: ni golpea ni prepara golpes en área (se retrasan hasta que se recupere).
	local stunned = EnemyLogic.isStunned(enemy.Control, now)

	-- Jefe: golpe en área periódico (más seguido con furia)
	local slamSettings = enemy.Def.Slam
	if slamSettings and now >= enemy.NextSlam then
		if stunned then
			enemy.NextSlam = enemy.Control.StunUntil + 0.5
		else
			local interval = slamSettings.Interval * (if enemy.Enraged then enemy.Def.Enrage.SlamIntervalMultiplier else 1)
			enemy.NextSlam = now + interval
			slam(enemy)
		end
	end

	-- Preparando un golpe: se queda quieto hasta soltarlo (así se puede esquivar)
	if enemy.WindupUntil and now < enemy.WindupUntil then
		status.State = "Attack"
		enemy.Humanoid:MoveTo(position)
		return
	end

	local offset = targetRoot.Position - position
	local distance = flat(offset)
	if distance <= enemy.Def.AttackRange + enemy.Radius then
		status.State = "Attack"
		-- Detenerse mirando al objetivo (si están superpuestos no hay dirección: solo parar)
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		enemy.Humanoid:MoveTo(if distance > 0.05 then position + flatOffset.Unit * 0.1 else position)
		if now >= enemy.NextAttack and not stunned then
			-- Ralentizado: también ataca más despacio.
			enemy.NextAttack = now + EnemyLogic.attackCooldown(enemy.Def.AttackCooldown, enemy.Control, now)
			attack(enemy, target)
		end
	else
		status.State = "Chase"
		enemy.Humanoid:MoveTo(targetRoot.Position)
	end
end

-- Arenas de jefe ---------------------------------------------------------------------

local function buildArena(parent: Instance, zoneId: string, arena)
	local center = zoneCenter(zoneId) + Vector3.new(arena.Center.X, 0, arena.Center.Y)
	local isValley = zoneId == "CrystalValley"
	local floor = if isValley then Enum.Material.Pavement else Enum.Material.Cobblestone
	-- Suelo pintado a ras, sin montículo (TerrainPaint; un FillCylinder lo levantaría).
	TerrainPaint.circle(center.X, center.Z, arena.Radius, GROUND, { Enum.Material.Grass, Enum.Material.LeafyGrass, Enum.Material.Ground }, floor)

	local model = Instance.new("Model")
	model.Name = "Arena_" .. zoneId
	local stone = if isValley then Color3.fromRGB(120, 118, 144) else Color3.fromRGB(110, 112, 100)
	local rune = if isValley then Color3.fromRGB(176, 120, 236) else Color3.fromRGB(96, 224, 200)
	-- Entrada orientada hacia el centro de la zona
	local toZone = zoneCenter(zoneId) - center
	local entranceAngle = math.atan2(toZone.Z, toZone.X)
	local count = 10
	for index = 1, count do
		local angle = entranceAngle + (index - 0.5) / count * math.pi * 2
		-- Se salta el menhir que taparía la entrada
		if index ~= 1 and index ~= count then
			local position = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (arena.Radius + 1.5)
			local height = 5 + (index % 3) * 1.2
			local facing = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
			PartFactory.part(model, "Stone" .. index, {
				Size = Vector3.new(2, height, 1.2),
				CFrame = facing * CFrame.new(0, height / 2 - 0.3, 0),
				Color = stone,
				Material = Enum.Material.Slate,
			})
			PartFactory.part(model, "Rune" .. index, {
				Size = Vector3.new(0.3, height * 0.4, 0.06),
				CFrame = facing * CFrame.new(0, height * 0.55, -0.63),
				Color = rune,
				Material = Enum.Material.Neon,
				Solid = false,
			})
		end
	end
	-- Cartel con el nombre del lugar, sobre la entrada
	local signPosition = center + Vector3.new(math.cos(entranceAngle), 0, math.sin(entranceAngle)) * (arena.Radius + 2)
	local anchor = PartFactory.part(model, "SignAnchor", {
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(signPosition + Vector3.new(0, 8, 0)),
		Color = stone,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	anchor.Transparency = 1
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(14, 0, 2, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 150
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 236, 200)
	label.TextStrokeTransparency = 0.3
	label.Text = "⚔ " .. arena.Name
	label.Parent = billboard
	billboard.Parent = anchor

	-- Círculo de runas en el suelo (marca el límite de la pelea) y sello central. Piezas
	-- planas sin colisión; ni luces ni partículas.
	local runeCount = 12
	for index = 1, runeCount do
		local angle = (index / runeCount) * math.pi * 2
		local position = center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (arena.Radius - 1.5)
		local tile = PartFactory.part(model, "FloorRune" .. index, {
			Size = Vector3.new(0.9, 0.1, 2.2),
			CFrame = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)) * CFrame.new(0, 0.2, 0),
			Color = rune,
			Material = Enum.Material.Neon,
			Solid = false,
		})
		tile.Transparency = 0.35
	end
	for index, diameter in { 7, 4.2 } do
		local seal = PartFactory.verticalCylinder(model, "Seal" .. index, center + Vector3.new(0, 0.18 + index * 0.03, 0), 0.1, diameter, if index == 1 then stone else rune, if index == 1 then Enum.Material.Slate else Enum.Material.Neon, false)
		seal.Transparency = if index == 1 then 0 else 0.5
	end

	model.Parent = parent
end

-- Arranque --------------------------------------------------------------------------

-- Vida de un tipo con la escala global (EnemyConfig.HealthScale: todos aguantan más)
local function baseHealth(def): number
	local scale = EnemyConfig.HealthScale
	return math.max(1, math.floor(def.MaxHealth * (if type(scale) == "number" and scale > 0 then scale else 1)))
end

local function createEnemy(zoneId: string, typeId: string, home: Vector3, zoneSettings, leashCenter: Vector3?, leashRadius: number?, pooled: boolean?): Enemy?
	local def = EnemyConfig.Types[typeId]
	if not def then
		warn("[EnemyService] Tipo de enemigo desconocido: " .. tostring(typeId))
		return nil
	end
	local shape = SHAPES[def.Look.Style]
	local rig = newRig(typeId, shape.Root, shape.Hip, def.WalkSpeed)
	BUILDERS[def.Look.Style](rig, def.Look)
	addJoints(rig, shape.Pivots)
	-- Contorno de caricatura (el cliente lo reutiliza para el destello al recibir daño).
	local outline = Instance.new("Highlight")
	outline.Name = "Outline"
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.FillTransparency = 1
	outline.OutlineColor = INK
	outline.OutlineTransparency = 0
	outline.Parent = rig.Model
	rig.Model:SetAttribute("EnemyType", typeId)
	rig.Model:SetAttribute("Kind", def.Kind)
	rig.Model:SetAttribute("DisplayName", def.DisplayName)
	-- Datos de presentación para el cliente (copias de la configuración, no se leen de vuelta).
	rig.Model:SetAttribute("FxColor", def.Look.Secondary)
	rig.Model:SetAttribute("AttackWindup", def.AttackWindup)
	if def.Slam then
		rig.Model:SetAttribute("SlamTelegraph", def.Slam.Telegraph)
	end

	local safeZones = {}
	local center = zoneCenter(zoneId)
	for _, safe in zoneSettings.SafeZones or {} do
		table.insert(safeZones, { Center = center + Vector3.new(safe.Center.X, 0, safe.Center.Y), Radius = safe.Radius })
	end

	local enemy: Enemy = {
		Id = #enemies + 1,
		TypeId = typeId,
		Def = def,
		Kind = def.Kind,
		ZoneId = zoneId,
		Model = rig.Model,
		Root = rig.Root,
		Humanoid = rig.Humanoid,
		Eyes = rig.Eyes,
		EyeColor = def.Look.Eyes,
		Aura = nil,
		Glow = nil,
		Bar = nil :: any,
		Billboard = nil :: any,
		RootHeight = rig.RootHeight,
		Radius = shape.Radius,
		DeathSeconds = shape.DeathSeconds,
		Home = home,
		LeashCenter = leashCenter or home,
		LeashRadius = leashRadius or def.LeashRange,
		DetectRange = def.DetectRange,
		SafeZones = safeZones,
		SafeAreas = safeAreasOf(zoneId, zoneSettings),
		RewardMultiplier = zoneSettings.RewardMultiplier or 1,
		Status = { State = "Idle", Health = baseHealth(def), MaxHealth = baseHealth(def), Contributions = {} },
		Control = EnemyLogic.newControl(),
		Target = nil,
		NextAttack = 0,
		NextSlam = 0,
		NextWander = 0,
		Enraged = false,
		Generation = 0,
		StuckSince = nil,
		LastHomeDistance = math.huge,
		Brain = nil,
		Pooled = pooled == true,
		InPool = false,
		WaveControlled = false,
		OnWaveDeath = nil,
		LastHitBy = nil,
		Run = nil,
		MoneyMultiplier = 1,
		Territory = nil,
	}
	if pooled then
		-- De las oleadas: sin zonas seguras (el círculo está en la plaza) y sin chocar con
		-- los jugadores ni con los de otras partidas.
		enemy.SafeZones = {}
		enemy.SafeAreas = {}
		setCollisionGroup(rig.Model, WAVE_GROUP)
	end
	if def.Brain then
		enemy.Brain = newBrain()
	end
	buildHealthBar(enemy, shape.BarHeight)
	if def.Enrage then
		-- Aura de furia: se crea una vez y solo se enciende durante la furia.
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "EnrageAura"
		aura.Enabled = false
		aura.Rate = 12
		aura.Lifetime = NumberRange.new(0.8, 1.2)
		aura.Speed = NumberRange.new(1, 2)
		aura.Acceleration = Vector3.new(0, 4, 0)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.Size = NumberSequence.new(0.9, 0)
		aura.Transparency = NumberSequence.new(0.3, 1)
		aura.LightEmission = 1
		aura.Color = ColorSequence.new(ENRAGED_EYES, def.Look.Secondary)
		aura.Parent = enemy.Root
		enemy.Aura = aura
		local glow = Instance.new("PointLight")
		glow.Name = "EnrageGlow"
		glow.Enabled = false
		glow.Color = ENRAGED_EYES
		glow.Range = 16
		glow.Brightness = 1.6
		glow.Shadows = false
		glow.Parent = enemy.Root
		enemy.Glow = glow
	end
	table.insert(enemies, enemy)
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 75
	clickDetector.Parent = rig.Model
	clickDetector.MouseClick:Connect(function(player: Player)
		if EnemyService.isAlive(enemy) and sameWorld(enemy, player) then
			enemy.Billboard.Enabled = true
			for _, listener in clickListeners do
				task.spawn(listener, player, enemy)
			end
		end
	end)
	if enemy.Pooled then
		-- De la reserva: fuera del mundo hasta que una oleada lo saque (spawnPooled).
		enemy.Status.State = "Dead"
		syncHealth(enemy)
	else
		respawn(enemy)
	end
	return enemy
end

-- Mazmorras: élites y mini-jefes ------------------------------------------------------------

-- Lo visible de un élite o un mini-jefe (una sola vez, al crearlo): más grande (Scale), una
-- luz y chispas de su color alrededor y su nombre en la barra. Lo de más vida, daño y botín lo
-- pone quien lo crea.
-- Más grande (s veces): el modelo, su cadera, su radio de golpe y la barra encima
local function scaleEnemy(enemy: Enemy, s: number)
	if s == 1 then
		return
	end
	local model = enemy.Model
	local hip = enemy.Humanoid.HipHeight
	local offset = enemy.Billboard.StudsOffset
	local ok = pcall(function()
		model:ScaleTo(model:GetScale() * s)
	end)
	if ok then
		enemy.Humanoid.HipHeight = hip * s
		enemy.RootHeight *= s
		enemy.Radius *= s
		enemy.Billboard.StudsOffset = offset * s
	end
end

local function dressVariant(enemy: Enemy, variant: string, scale: number?, color: Color3, name: string)
	enemy.Variant = variant
	local model = enemy.Model
	local s = if type(scale) == "number" and scale > 0 then scale else 1
	scaleEnemy(enemy, s)
	local glow = Instance.new("PointLight")
	glow.Name = "VariantGlow"
	glow.Color = color
	glow.Range = 12 * s
	glow.Brightness = 1.6
	glow.Shadows = false
	glow.Parent = enemy.Root
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "VariantSparkles"
	sparkles.Color = ColorSequence.new(color)
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.45 * s), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new(0.15)
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Rate = if variant == "MiniBoss" then 22 else 12
	sparkles.Speed = NumberRange.new(1.5, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Acceleration = Vector3.new(0, 3, 0)
	sparkles.Parent = enemy.Root
	local label = enemy.Billboard:FindFirstChild("EnemyName")
	if label and label:IsA("TextLabel") then
		label.Text = name
		label.TextColor3 = color
	end
	enemy.Billboard.Size = if variant == "MiniBoss" then BAR_SIZES.Boss else BAR_SIZES.Strong
	model:SetAttribute("DisplayName", name)
	model:SetAttribute("Variant", variant)
end

-- Más vida, daño y botín (×) de golpe, para los del mundo (los de las oleadas lo llevan en
-- spawnPooled).
local function strengthen(enemy: Enemy, health: number?, damage: number?, reward: number?)
	enemy.Status.MaxHealth = math.max(1, math.floor(enemy.Status.MaxHealth * (health or 1)))
	enemy.Status.Health = enemy.Status.MaxHealth
	enemy.DamageMultiplier = (enemy.DamageMultiplier or 1) * (damage or 1)
	enemy.RewardMultiplier *= reward or 1
	syncHealth(enemy)
end

local function makeElite(enemy: Enemy)
	local elite = EnemyConfig.Elite
	dressVariant(enemy, "Elite", elite.Scale, elite.Color, (elite.Prefix or "") .. enemy.Def.DisplayName)
end

-- Oleadas ------------------------------------------------------------------------------

export type WaveSpawnOptions = {
	LeashCenter: Vector3?, -- persigue a quien esté dentro de este círculo
	LeashRadius: number?,
	DetectRange: number?, -- distancia a la que ve a los jugadores
	HealthMultiplier: number?,
	RewardMultiplier: number?,
	PoolLimit: number?, -- como mucho estos de su tipo en la reserva
	OnDeath: ((any, Player?, Vector3) -> ())?,
	Run: number?, -- partida (oleadas privadas): solo la ven y lo golpean sus jugadores
	MoneyMultiplier: number?, -- dinero que suelta (la ⚡ no cambia)
	DamageMultiplier: number?, -- daño que hace a los jugadores
	CollisionSlot: number?, -- hueco de la partida (1..MaxRuns): chocan los del mismo hueco
	Elite: boolean?, -- élite (EnemyConfig.Elite): de su propia reserva, más grande y más fuerte
	-- Jefes: su arena (para la barra del jefe del cliente) y su territorio
	Arena: { Center: Vector3, Radius: number, Name: string }?,
	Territory: number?,
	-- Jefe que se parte: al bajar a SplitAt (parte de la vida máxima) se llama a OnSplit una vez
	SplitAt: number?,
	OnSplit: ((any) -> ())?,
}

local function finiteOr(value: any, default: number): number
	return if type(value) == "number" and value == value and value > 0 and value < 1e9 then value else default
end

-- Saca un enemigo de la reserva (o lo crea si aún caben) en `position`. nil si no hay sitio.
function EnemyService.spawnPooled(zoneId: string, typeId: string, position: Vector3, options: WaveSpawnOptions?): Enemy?
	local opts: WaveSpawnOptions = options or {}
	local zoneSettings = EnemyConfig.Zones[zoneId]
	if not (zoneSettings and EnemyConfig.Types[typeId] and ZoneConfig.Zones[zoneId]) then
		return nil
	end
	local elite = opts.Elite == true
	local key = zoneId .. "/" .. typeId .. (if elite then "/Elite" else "")
	local free = pools[key]
	local enemy = if free then table.remove(free) else nil
	if not enemy then
		if (poolCreated[key] or 0) >= finiteOr(opts.PoolLimit, 20) then
			return nil
		end
		enemy = createEnemy(zoneId, typeId, position, zoneSettings, nil, nil, true)
		if not enemy then
			return nil
		end
		-- Tamaño propio (los jefes gigantes de las oleadas), una vez por instancia
		local scale = enemy.Def.Scale
		if type(scale) == "number" and scale > 0 and scale ~= 1 then
			scaleEnemy(enemy, scale)
		end
		if elite then
			makeElite(enemy)
		end
		poolCreated[key] = (poolCreated[key] or 0) + 1
	end
	local eliteSpec = if enemy.Variant == "Elite" then EnemyConfig.Elite else nil
	local def = enemy.Def
	enemy.InPool = false
	enemy.Home = position
	enemy.LeashCenter = opts.LeashCenter or position
	enemy.LeashRadius = finiteOr(opts.LeashRadius, def.LeashRange)
	enemy.DetectRange = finiteOr(opts.DetectRange, def.DetectRange)
	enemy.RewardMultiplier = finiteOr(opts.RewardMultiplier, 1) * (if eliteSpec then eliteSpec.Reward else 1)
	enemy.Status.MaxHealth = math.max(1, math.floor(baseHealth(def) * finiteOr(opts.HealthMultiplier, 1) * (if eliteSpec then eliteSpec.Health else 1)))
	enemy.OnWaveDeath = opts.OnDeath
	enemy.OnSplit = opts.OnSplit
	enemy.SplitAt = if opts.OnSplit then math.clamp(finiteOr(opts.SplitAt, 0.5), 0.05, 0.95) else nil
	enemy.LastHitBy = nil
	enemy.Run = opts.Run
	enemy.Model:SetAttribute(RUN_ATTRIBUTE, opts.Run)
	enemy.MoneyMultiplier = if opts.MoneyMultiplier ~= nil then math.clamp(finiteOr(opts.MoneyMultiplier, 1), 0, 10) else 1
	enemy.DamageMultiplier = if opts.DamageMultiplier ~= nil then math.clamp(finiteOr(opts.DamageMultiplier, 1), 0.1, 10) else nil
	if eliteSpec then
		enemy.DamageMultiplier = (enemy.DamageMultiplier or 1) * eliteSpec.Damage
	end
	local slot = opts.CollisionSlot
	setCollisionGroup(enemy.Model, if type(slot) == "number" and slot >= 1 and slot <= waveSlots then WAVE_SLOT_PREFIX .. math.floor(slot) else WAVE_GROUP)
	enemy.Territory = if opts.Territory ~= nil then finiteOr(opts.Territory, def.Brain and def.Brain.Territory or 20) else nil
	local arena = opts.Arena
	enemy.Model:SetAttribute("ArenaCenter", if arena then arena.Center else nil)
	enemy.Model:SetAttribute("ArenaRadius", if arena then arena.Radius else nil)
	enemy.Model:SetAttribute("ArenaName", if arena then arena.Name else nil)
	enemy.Generation += 1
	respawn(enemy)
	return enemy
end

-- Retira un enemigo de una oleada SIN recompensa (partida perdida o terminada). Los de la
-- reserva vuelven a ella; los jefes de las oleadas se quedan dormidos.
function EnemyService.despawn(enemy: Enemy?)
	if not enemy then
		return
	end
	enemy.Generation += 1 -- anula reapariciones y disoluciones pendientes
	enemy.OnWaveDeath = nil
	enemy.OnSplit = nil
	enemy.SplitAt = nil
	enemy.LastHitBy = nil
	enemy.Target = nil
	clearControl(enemy)
	setEnraged(enemy, false)
	if enemy.Model.Parent ~= nil and enemy.Status.State ~= "Dead" then
		burst(enemy.Root.Position, enemy.Def.Look.Secondary, 12, true, enemy.Run)
	end
	enemy.Status.State = "Dead"
	enemy.Billboard.Enabled = false
	enemy.Model:SetAttribute("TargetUserId", nil)
	enemy.Model.Parent = nil
	release(enemy)
end

-- El jefe de una zona pasa a salir solo en las oleadas (controlled = true: se duerme ya)
-- o vuelve a estar siempre en su arena (false: reaparece ahora con su vida normal).
function EnemyService.setBossWaveControlled(zoneId: string, controlled: boolean): Enemy?
	local boss = bossByZone[zoneId]
	if not boss then
		return nil
	end
	boss.WaveControlled = controlled
	if controlled then
		EnemyService.despawn(boss)
	else
		boss.Status.MaxHealth = baseHealth(boss.Def)
		boss.OnWaveDeath = nil
		boss.Generation += 1
		respawn(boss)
	end
	return boss
end

-- Despierta al jefe de una zona para la última oleada (con más vida si hay más jugadores).
function EnemyService.wakeBoss(zoneId: string, healthMultiplier: number?, onDeath: ((any, Player?, Vector3) -> ())?): Enemy?
	local boss = bossByZone[zoneId]
	if not boss then
		return nil
	end
	boss.Status.MaxHealth = math.max(1, math.floor(baseHealth(boss.Def) * finiteOr(healthMultiplier, 1)))
	boss.OnWaveDeath = onDeath
	boss.LastHitBy = nil
	boss.Generation += 1
	respawn(boss)
	return boss
end

function EnemyService.bossOf(zoneId: string): Enemy?
	return bossByZone[zoneId]
end

-- WaveService añade lo de las mejoras de la partida: (multiplicador del botín, segundos
-- extra de racha) para ese jugador y ese enemigo.
function EnemyService.setKillModifier(modifier: (Player, Enemy) -> (number?, number?))
	killModifier = modifier
end

-- Racha vigente de un jugador (0 si caducó) y la mejor de la sesión.
function EnemyService.streakOf(player: Player): (number, number)
	local streak = streaks[player]
	if not streak then
		return 0, 0
	end
	return WaveLogic.streakCount(streak, os.clock()), streak.Best
end

function EnemyService.start()
	PartFactory.removeExisting(workspace, FOLDER_NAME)
	PartFactory.removeExisting(workspace, ARENAS_NAME)
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	fxFolder = PartFactory.folder(folder, "Effects")
	local arenas = Instance.new("Folder")
	arenas.Name = ARENAS_NAME
	arenas.Parent = workspace
	rewardRemote = RemoteService.get(Constants.Remotes.CombatReward)

	-- Oleadas privadas: los enemigos de las partidas no chocan con los personajes ni con los
	-- de otras partidas (así nadie tropieza con enemigos que no ve); los de una misma partida
	-- sí chocan entre ellos.
	local function register(group: string): boolean
		local ok, err = pcall(function()
			if not PhysicsService:IsCollisionGroupRegistered(group) then
				PhysicsService:RegisterCollisionGroup(group)
			end
		end)
		if not ok then
			warn("[EnemyService] Grupo de colisión " .. group .. ": " .. tostring(err))
		end
		return ok
	end
	register(WAVE_GROUP)
	register(CHARACTER_GROUP)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(WAVE_GROUP, WAVE_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(WAVE_GROUP, CHARACTER_GROUP, false)
	end)
	for slot = 1, math.max(1, WaveConfig.MaxRuns) do
		if not register(WAVE_SLOT_PREFIX .. slot) then
			break
		end
		waveSlots = slot
	end
	pcall(function()
		for slot = 1, waveSlots do
			local group = WAVE_SLOT_PREFIX .. slot
			PhysicsService:CollisionGroupSetCollidable(group, CHARACTER_GROUP, false)
			PhysicsService:CollisionGroupSetCollidable(group, WAVE_GROUP, false)
			for other = slot + 1, waveSlots do
				PhysicsService:CollisionGroupSetCollidable(group, WAVE_SLOT_PREFIX .. other, false)
			end
		end
	end)
	local function watchCharacter(character: Model)
		setCollisionGroup(character, CHARACTER_GROUP)
		character.DescendantAdded:Connect(function(part)
			if part:IsA("BasePart") then
				part.CollisionGroup = CHARACTER_GROUP
			end
		end)
	end
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(watchCharacter)
		if player.Character then
			watchCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	-- Enemigos repartidos por las zonas.
	for zoneId, zoneSettings in EnemyConfig.Zones do
		if not ZoneConfig.Zones[zoneId] then
			continue
		end
		PartFactory.folder(folder, zoneId)
		local center = zoneCenter(zoneId)
		local safeAreas = safeAreasOf(zoneId, zoneSettings)
		for _, spawn in zoneSettings.Spawns do
			local home = center + Vector3.new(spawn.Offset.X, 0, spawn.Offset.Y)
			-- En una zona sin monstruos no aparece ninguno, aunque la configuración lo pida
			if inSafeArea(safeAreas, home) then
				warn(("[EnemyService] %s en %s cae en una zona sin monstruos (SafeAreas): no se crea."):format(spawn.Type, tostring(home)))
				continue
			end
			local enemy = createEnemy(zoneId, spawn.Type, home, zoneSettings, nil, nil)
			-- Los de las mazmorras (lejos del mapa): más vida, más daño y más botín, y en las del
			-- Valle y la Caldera algunos de los pequeños son élite (los medianos no: el más duro
			-- de su sala es el mini-jefe)
			local caveId, cave = CaveLogic.caveAt(home.X, home.Z)
			if enemy and cave then
				local strength = cave.Strength or {}
				strengthen(enemy, strength.Health, strength.Damage, strength.Reward)
				enemy.Model:SetAttribute("Cave", caveId)
				local every = if cave.EliteChance and cave.EliteChance > 0 then math.max(1, math.round(1 / cave.EliteChance)) else 0
				if every > 0 and enemy.Kind == "Normal" then
					eliteCount[caveId] = (eliteCount[caveId] or 0) + 1
				end
				if every > 0 and enemy.Kind == "Normal" and eliteCount[caveId] % every == 0 then
					local elite = EnemyConfig.Elite
					strengthen(enemy, elite.Health, elite.Damage, elite.Reward)
					makeElite(enemy)
					place(enemy) -- de nuevo, ya con su tamaño
				end
			end
		end
		local boss = zoneSettings.Boss
		if boss then
			local arenaCenter = center + Vector3.new(boss.Arena.Center.X, 0, boss.Arena.Center.Y)
			local enemy = createEnemy(zoneId, boss.Type, arenaCenter, zoneSettings, arenaCenter, boss.Arena.Radius)
			if enemy then
				-- Jefes más grandes que su modelo (Scale: el Rey Goblin es enorme)
				local scale = enemy.Def.Scale
				if type(scale) == "number" and scale > 0 and scale ~= 1 then
					scaleEnemy(enemy, scale)
					place(enemy)
				end
				enemy.Model:SetAttribute("ArenaCenter", arenaCenter)
				enemy.Model:SetAttribute("ArenaRadius", boss.Arena.Radius)
				enemy.Model:SetAttribute("ArenaName", boss.Arena.Name)
				bossByZone[zoneId] = enemy
			end
		end
	end

	-- Mini-jefes de las mazmorras (CaveConfig.Caves.*.MiniBoss): uno en la sala 2 de cada una
	-- que lo tenga; abre la puerta del altar (CaveService). Reaparece como los demás.
	for caveId, cave in CaveConfig.Caves do
		local spec = cave.MiniBoss
		local zoneSettings = EnemyConfig.Zones[cave.Zone]
		if not (spec and zoneSettings and ZoneConfig.Zones[cave.Zone]) then
			continue
		end
		local center = zoneCenter(cave.Zone)
		local home = Vector3.new(spec.Position.X, center.Y, spec.Position.Z)
		local enemy = createEnemy(cave.Zone, spec.Type, home, zoneSettings, nil, nil)
		if enemy then
			local strength = cave.Strength or {}
			strengthen(enemy, (strength.Health or 1) * (spec.Health or 1), (strength.Damage or 1) * (spec.Damage or 1), (strength.Reward or 1) * (spec.Reward or 1))
			enemy.Model:SetAttribute("Cave", caveId)
			dressVariant(enemy, "MiniBoss", spec.Scale, cave.Theme and cave.Theme.Portal or Color3.fromRGB(255, 200, 80), spec.Name)
			place(enemy) -- de nuevo, ya con su tamaño
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		streaks[player] = nil
	end)

	-- Un único bucle de IA para todos los enemigos.
	task.spawn(function()
		while true do
			task.wait(EnemyConfig.AiTickSeconds)
			local now = os.clock()
			for _, enemy in enemies do
				local ok, err = pcall(if enemy.Brain then updateBoss else updateEnemy, enemy, now)
				if not ok then
					warn("[EnemyService] Error en la IA de " .. enemy.TypeId .. ": " .. tostring(err))
				end
			end
		end
	end)
end

return EnemyService
