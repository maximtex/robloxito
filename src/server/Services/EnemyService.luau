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
--   recompensa se reparte por daño, sumándola a profile.Energy (la misma energía de
--   siempre) y replicándola con PlayerDataService.
-- - Al morir el modelo se retira (tras dejar que el cliente lo disuelva) y reaparece tras
--   RespawnSeconds, reutilizando el mismo modelo (sin crear ni filtrar instancias ni conexiones).
-- - Presentación: las piezas van unidas con Motor6D por grupos (cuerpo, brazos, piernas)
--   y el modelo publica atributos (SpawnedAt, AttackAt, SlamAt, DiedAt) que el cliente
--   usa para animarlo (EnemyAnimator). No cambian estadísticas, IA ni recompensas.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteService = require(script.Parent.RemoteService)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local EnemyLogic = require(script.Parent.Parent.Util.EnemyLogic)

local FOLDER_NAME = "Enemies"
local ARENAS_NAME = "BossArenas"
local GROUND = GeneratorConfig.Position.Y
local WINDUP_EYES = Color3.fromRGB(255, 70, 60)
local ENRAGED_EYES = Color3.fromRGB(255, 120, 40)
-- Tiempo que el cuerpo sigue en el mundo tras morir, para que el cliente lo disuelva
-- (ya está muerto: no recibe golpes ni ataca). Solo presentación.
local DISSOLVE_SECONDS = { Normal = 0.8, Strong = 0.9, Boss = 1.6 }
local KIND_BAR_COLORS = {
	Normal = Color3.fromRGB(120, 214, 120),
	Strong = Color3.fromRGB(240, 170, 70),
	Boss = Color3.fromRGB(230, 90, 100),
}

type SafeZone = { Center: Vector3, Radius: number }

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
	Home: Vector3,
	LeashCenter: Vector3,
	LeashRadius: number,
	DetectRange: number,
	SafeZones: { SafeZone },
	RewardMultiplier: number,
	Status: EnemyLogic.EnemyState,
	Target: Player?,
	NextAttack: number,
	NextSlam: number,
	NextWander: number,
	Enraged: boolean,
	Generation: number, -- cambia en cada muerte/reaparición: invalida tareas pendientes
	StuckSince: number?,
	LastHomeDistance: number,
}

local EnemyService = {}

local enemies: { Enemy } = {}
-- Modificador del daño que los enemigos hacen a los jugadores (lo registra
-- PetCombatService para la Tortuga). Un único punto: nunca se aplica dos veces.
local incomingModifier: ((Player, number) -> number)? = nil
local folder: Folder
local fxFolder: Folder
local rewardRemote: RemoteEvent
-- Avisos de "este jugador ha derrotado a este enemigo" (los usa QuestService). Solo
-- informan: no cambian la muerte ni la recompensa.
local defeatListeners: { (Player, { TypeId: string, Kind: string, ZoneId: string, Reward: number }) -> () } = {}

function EnemyService.onDefeated(listener: (Player, { TypeId: string, Kind: string, ZoneId: string, Reward: number }) -> ())
	table.insert(defeatListeners, listener)
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
	part.CanQuery = false
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

-- Espinillo: bola de zarzas con espinas y ojos ámbar.
function BUILDERS.Bramble(rig: Rig, look)
	orb(rig, "Body", 2.2, Vector3.new(0, 1.6, 0), look.Primary, Enum.Material.LeafyGrass)
	for index = 1, 6 do
		local angle = (index / 6) * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0.35, math.sin(angle)).Unit
		local base = Vector3.new(0, 1.6, 0) + direction * 1.05
		box(rig, "Thorn" .. index, Vector3.new(0.22, 0.8, 0.22), CFrame.lookAt(base, base + direction) * CFrame.Angles(math.rad(-90), 0, 0), look.Secondary, Enum.Material.Wood)
	end
	for side = -1, 1, 2 do
		eye(rig, "Eye" .. side, 0.3, Vector3.new(side * 0.35, 1.9, -0.98), look.Eyes)
		orb(rig, "Foot" .. side, 0.6, Vector3.new(side * 0.45, 0.35, 0), look.Secondary, Enum.Material.Wood)
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

-- Fragmento Errante: núcleo de cristal facetado con esquirlas luminosas.
function BUILDERS.Shard(rig: Rig, look)
	box(rig, "Core", Vector3.one * 1.8, CFrame.new(0, 2, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35)), look.Primary, Enum.Material.Glass)
	for index, spec in { { Vector3.new(0.7, 2.6, 0.2), Vector3.new(0, 0, -0.5) }, { Vector3.new(-0.7, 2.5, 0.3), Vector3.new(0, 0, 0.5) }, { Vector3.new(0, 3.0, 0.4), Vector3.new(0.3, 0, 0) }, { Vector3.new(0.3, 1.6, 0.8), Vector3.new(0.8, 0, 0) } } do
		crystalSpike(rig, "Shard" .. index, Vector3.new(0.35, 1.1, 0.35), spec[1], spec[2], look.Secondary)
	end
	for side = -1, 1, 2 do
		eye(rig, "Eye" .. side, 0.26, Vector3.new(side * 0.3, 2.2, -1.02), look.Eyes)
		box(rig, "Leg" .. side, Vector3.new(0.4, 1, 0.4), CFrame.new(side * 0.4, 0.5, 0) * CFrame.Angles(0, math.rad(45), 0), look.Primary, Enum.Material.Glass)
	end
end

-- Gólem de Geoda: bloques de pizarra con crecimientos de cristal.
function BUILDERS.Golem(rig: Rig, look)
	box(rig, "Torso", Vector3.new(3.6, 3.8, 2.8), CFrame.new(0, 3.9, 0), look.Primary, Enum.Material.Slate)
	box(rig, "Head", Vector3.new(1.8, 1.4, 1.6), CFrame.new(0, 6.5, -0.2), look.Primary, Enum.Material.Slate)
	for index, spec in { { Vector3.new(1.4, 6.2, 0.6), Vector3.new(0, 0, -0.4) }, { Vector3.new(-1.5, 6.0, 0.5), Vector3.new(0, 0, 0.4) }, { Vector3.new(0.6, 5.2, 1.5), Vector3.new(0.6, 0, 0) }, { Vector3.new(-0.7, 4.4, 1.5), Vector3.new(0.7, 0, 0) } } do
		crystalSpike(rig, "Crystal" .. index, Vector3.new(0.5, 1.6, 0.5), spec[1], spec[2], look.Secondary)
	end
	for side = -1, 1, 2 do
		eye(rig, "Eye" .. side, 0.32, Vector3.new(side * 0.45, 6.6, -1.02), look.Eyes)
		orb(rig, "Shoulder" .. side, 1.6, Vector3.new(side * 2.4, 5, 0), look.Primary, Enum.Material.Slate)
		limb(rig, "Arm" .. side, Vector3.new(side * 2.4, 5, 0), Vector3.new(side * 2.6, 2.4, -0.6), 1.1, look.Primary, Enum.Material.Slate)
		orb(rig, "Fist" .. side, 1.9, Vector3.new(side * 2.6, 2.3, -0.6), look.Primary, Enum.Material.Slate)
		box(rig, "Leg" .. side, Vector3.new(1.2, 1.9, 1.2), CFrame.new(side * 0.9, 0.95, 0), look.Primary, Enum.Material.Slate)
	end
end

-- Coloso de Amatista (jefe): gigante de pizarra con corona de amatista y núcleo brillante.
function BUILDERS.Colossus(rig: Rig, look)
	box(rig, "Torso", Vector3.new(7, 8, 5), CFrame.new(0, 8, 0), look.Primary, Enum.Material.Slate)
	box(rig, "Head", Vector3.new(3, 2.4, 2.6), CFrame.new(0, 13.2, -0.4), look.Primary, Enum.Material.Slate)
	orb(rig, "CoreGem", 1.8, Vector3.new(0, 8.5, -2.55), look.Secondary, Enum.Material.Neon)
	for index, spec in { { Vector3.new(0, 15.4, -0.4), Vector3.zero, 3.2 }, { Vector3.new(-1.1, 14.9, -0.3), Vector3.new(0, 0, 0.4), 2.4 }, { Vector3.new(1.1, 14.9, -0.3), Vector3.new(0, 0, -0.4), 2.4 }, { Vector3.new(-3.6, 12.6, 0.5), Vector3.new(0, 0, 0.5), 2.8 }, { Vector3.new(3.6, 12.6, 0.5), Vector3.new(0, 0, -0.5), 2.8 } } do
		crystalSpike(rig, "Crown" .. index, Vector3.new(0.9, spec[3], 0.9), spec[1], spec[2], look.Secondary)
	end
	for side = -1, 1, 2 do
		eye(rig, "Eye" .. side, 0.6, Vector3.new(side * 0.8, 13.4, -1.72), look.Eyes)
		orb(rig, "Shoulder" .. side, 3, Vector3.new(side * 4.6, 10.5, 0), look.Primary, Enum.Material.Slate)
		limb(rig, "Arm" .. side, Vector3.new(side * 4.6, 10.5, 0), Vector3.new(side * 5.2, 4.2, -1.5), 2, look.Primary, Enum.Material.Slate)
		orb(rig, "Fist" .. side, 3.4, Vector3.new(side * 5.2, 4, -1.5), look.Primary, Enum.Material.Slate)
		box(rig, "Leg" .. side, Vector3.new(2.2, 3.8, 2.2), CFrame.new(side * 1.6, 1.9, 0), look.Primary, Enum.Material.Slate)
	end
end

-- Tamaño de la raíz (hitbox de movimiento), altura de cadera y radio de golpe por estilo.
-- Pivots: puntos de giro para la animación del cliente (cuerpo, hombro y cadera del lado
-- derecho; el izquierdo es su reflejo). Solo afectan a la presentación.
local SHAPES = {
	Bramble = { Root = Vector3.new(2, 2, 2), Hip = 0.6, Radius = 1.2, BarHeight = 3.6, Pivots = { Body = Vector3.new(0, 1.6, 0), Leg = Vector3.new(0.45, 0.7, 0) } },
	Brute = { Root = Vector3.new(3, 3.4, 2.2), Hip = 1.6, Radius = 2, BarHeight = 7, Pivots = { Body = Vector3.new(0, 1.9, 0), Arm = Vector3.new(1.9, 4.9, 0), Leg = Vector3.new(0.8, 1.9, 0) } },
	Treant = { Root = Vector3.new(5, 7, 4), Hip = 3, Radius = 4, BarHeight = 19, Pivots = { Body = Vector3.new(0, 3, 0), Arm = Vector3.new(2.3, 9, 0) } },
	Shard = { Root = Vector3.new(2, 2.2, 2), Hip = 0.8, Radius = 1.3, BarHeight = 4.2, Pivots = { Body = Vector3.new(0, 2, 0), Leg = Vector3.new(0.4, 1, 0) } },
	Golem = { Root = Vector3.new(3.4, 3.6, 2.6), Hip = 1.8, Radius = 2.2, BarHeight = 8.2, Pivots = { Body = Vector3.new(0, 1.9, 0), Arm = Vector3.new(2.4, 5, 0), Leg = Vector3.new(0.9, 1.9, 0) } },
	Colossus = { Root = Vector3.new(6, 8, 4.5), Hip = 3.5, Radius = 4.5, BarHeight = 18, Pivots = { Body = Vector3.new(0, 3.8, 0), Arm = Vector3.new(4.6, 10.5, 0), Leg = Vector3.new(1.6, 3.8, 0) } },
}

-- Articulaciones: cada pieza se une a la raíz con un Motor6D cuyo pivote es el de su grupo
-- (cuerpo, brazo o pierna). En reposo equivale a una soldadura; el cliente anima los
-- grupos escribiendo Motor6D.Transform (solo en su pantalla, sin tocar la IA ni la física).
-- Las raíces del Guardián quedan soldadas: están clavadas en el suelo.
local ARM_PARTS = { Arm = true, Fist = true, Hand = true, UpperArm = true, LowerArm = true, Shoulder = true }
local LEG_PARTS = { Leg = true, Foot = true }

local function poseGroup(partName: string): (string, number)
	if partName:sub(1, 4) == "Root" then
		return "Static", 0
	end
	local base, side = partName:match("^(%a+)(%-?1)$")
	if base and ARM_PARTS[base] then
		return "Arm", tonumber(side) or 1
	elseif base and LEG_PARTS[base] then
		return "Leg", tonumber(side) or 1
	end
	return "Body", 0
end

local function addJoints(rig: Rig, pivots: { [string]: Vector3 })
	for _, part in rig.Model:GetChildren() do
		if not part:IsA("BasePart") or part == rig.Root then
			continue
		end
		local group, side = poseGroup(part.Name)
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
		local pivot = pivots[group]
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
	local isBoss = enemy.Kind == "Boss"
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = if isBoss then UDim2.fromOffset(200, 38) else UDim2.fromOffset(120, 30)
	billboard.StudsOffset = Vector3.new(0, barHeight - enemy.RootHeight, 0)
	billboard.LightInfluence = 0
	billboard.MaxDistance = if isBoss then 120 else 70
	billboard.Adornee = enemy.Root

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0.5, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.TextColor3 = Color3.fromRGB(248, 244, 228)
	name.TextStrokeTransparency = 0.4
	name.Text = enemy.Def.DisplayName
	name.Parent = billboard

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 0, 0.6, 0)
	track.Size = UDim2.new(1, 0, 0.32, 0)
	track.BackgroundColor3 = Color3.fromRGB(22, 38, 32)
	track.BackgroundTransparency = 0.15
	track.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = KIND_BAR_COLORS[enemy.Kind] or KIND_BAR_COLORS.Normal
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	billboard.Parent = enemy.Root
	enemy.Bar = fill
	enemy.Billboard = billboard
end

-- Estado visible ------------------------------------------------------------------

local function syncHealth(enemy: Enemy)
	local status = enemy.Status
	enemy.Model:SetAttribute("Health", math.ceil(status.Health))
	enemy.Model:SetAttribute("MaxHealth", status.MaxHealth)
	enemy.Bar.Size = UDim2.fromScale(math.clamp(status.Health / status.MaxHealth, 0, 1), 1)
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
end

local function burst(position: Vector3, color: Color3, amount: number, rising: boolean?)
	local part = Instance.new("Part")
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
	local position = enemy.Home + Vector3.new(0, enemy.RootHeight + 0.5, 0)
	enemy.Model:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, -1)))
	enemy.Root.AssemblyLinearVelocity = Vector3.zero
end

local function respawn(enemy: Enemy)
	EnemyLogic.reset(enemy.Status)
	enemy.Target = nil
	enemy.Humanoid.WalkSpeed = enemy.Def.WalkSpeed
	setEnraged(enemy, false)
	enemy.StuckSince = nil
	enemy.LastHomeDistance = math.huge
	local now = os.clock()
	enemy.NextAttack = now + 1
	enemy.NextSlam = now + (if enemy.Def.Slam then enemy.Def.Slam.Interval else math.huge)
	syncHealth(enemy)
	place(enemy)
	-- Avisos para la animación del cliente (aparición; sin golpes pendientes).
	enemy.Billboard.Enabled = true
	enemy.Model:SetAttribute("AttackAt", nil)
	enemy.Model:SetAttribute("SlamAt", nil)
	enemy.Model:SetAttribute("DiedAt", nil)
	enemy.Model:SetAttribute("SpawnedAt", Workspace:GetServerTimeNow())
	enemy.Model.Parent = folder:FindFirstChild(enemy.ZoneId)
	pcall(function()
		enemy.Root:SetNetworkOwner(nil) -- el servidor controla el movimiento, no los clientes
	end)
end

local function onDeath(enemy: Enemy)
	enemy.Generation += 1
	local generation = enemy.Generation
	enemy.Target = nil
	enemy.Humanoid:MoveTo(enemy.Root.Position)
	syncHealth(enemy)
	enemy.Billboard.Enabled = false
	enemy.Model:SetAttribute("DiedAt", Workspace:GetServerTimeNow())

	-- Recompensa: una sola vez por vida (solo llega aquí el golpe que lo mató).
	local reward = math.floor(enemy.Def.Reward * enemy.RewardMultiplier)
	local isBoss = enemy.Kind == "Boss"
	for userId, amount in EnemyLogic.splitReward(enemy.Status.Contributions, reward) do
		local player = Players:GetPlayerByUserId(userId)
		local profile = player and PlayerDataService.get(player)
		if player and profile and amount > 0 then
			profile.Energy += amount
			PlayerDataService.replicate(player)
			rewardRemote:FireClient(player, amount, enemy.Def.DisplayName, isBoss)
			-- Cuenta como derrota para quien recibe parte de la recompensa (daño real).
			local info = { TypeId = enemy.TypeId, Kind = enemy.Kind, ZoneId = enemy.ZoneId, Reward = amount }
			for _, listener in defeatListeners do
				task.spawn(listener, player, info)
			end
		end
	end

	burst(enemy.Root.Position, enemy.Def.Look.Secondary, if isBoss then 60 else 20, true)
	task.delay(DISSOLVE_SECONDS[enemy.Kind] or 0.8, function()
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
-- Devuelve el daño aplicado y si este golpe lo ha matado.
function EnemyService.damage(enemy: Enemy, player: Player, amount: number): (number, boolean)
	if enemy.Model.Parent == nil then
		return 0, false
	end
	local dealt, killed = EnemyLogic.applyDamage(enemy.Status, player.UserId, amount)
	if dealt <= 0 then
		return 0, false
	end
	if killed then
		onDeath(enemy)
		return dealt, true
	end
	syncHealth(enemy)
	-- Furia del jefe
	local enrage = enemy.Def.Enrage
	if enrage and not enemy.Enraged and enemy.Status.Health <= enemy.Status.MaxHealth * enrage.HealthFraction then
		enemy.Humanoid.WalkSpeed = enemy.Def.WalkSpeed * enrage.SpeedMultiplier
		setEnraged(enemy, true)
		burst(enemy.Root.Position, ENRAGED_EYES, 40)
	end
	-- Quien le golpea se convierte en su objetivo si no tenía uno
	if enemy.Target == nil then
		enemy.Target = player
	end
	return dealt, false
end

function EnemyService.isAlive(enemy: Enemy?): boolean
	return enemy ~= nil and enemy.Model.Parent ~= nil and enemy.Status.State ~= "Dead"
end

function EnemyService.setIncomingDamageModifier(modifier: (Player, number) -> number)
	incomingModifier = modifier
end

-- Daño que un enemigo hace a un jugador, tras el modificador (si lo hay).
local function damagePlayer(player: Player, humanoid: Humanoid, amount: number)
	local final = amount
	if incomingModifier then
		local ok, result = pcall(incomingModifier, player, amount)
		if ok and type(result) == "number" and result == result then
			final = math.clamp(result, 0, amount) -- nunca más daño ni curación
		end
	end
	humanoid:TakeDamage(final) -- respeta el escudo de aparición
end

-- Enemigos vivos dentro de un radio (borde incluido), sin repetidos y como mucho `maxTargets`.
function EnemyService.findInRadius(center: Vector3, radius: number, maxTargets: number): { Enemy }
	local candidates = {}
	local byId: { [number]: Enemy } = {}
	for _, enemy in enemies do
		if EnemyService.isAlive(enemy) and math.abs(enemy.Root.Position.Y - center.Y) <= 10 + enemy.RootHeight then
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
function EnemyService.findTargets(origin: Vector3, look: Vector3, range: number, arcDot: number, maxTargets: number): { Enemy }
	local candidates = {}
	local byId: { [number]: Enemy } = {}
	for _, enemy in enemies do
		local alive = enemy.Model.Parent ~= nil and enemy.Status.State ~= "Dead"
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

local function inSafeZone(enemy: Enemy, position: Vector3): boolean
	for _, zone in enemy.SafeZones do
		if flat(position - zone.Center) <= zone.Radius then
			return true
		end
	end
	return false
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
			if inRange and distance < bestDistance and canTarget(enemy, root.Position) then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

local function attack(enemy: Enemy, target: Player)
	local generation = enemy.Generation
	setEyes(enemy, WINDUP_EYES) -- aviso del golpe
	-- Momento del golpe para la animación del cliente (preparación y golpe).
	enemy.Model:SetAttribute("AttackAt", Workspace:GetServerTimeNow() + enemy.Def.AttackWindup)
	task.delay(enemy.Def.AttackWindup, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" then
			return
		end
		setEyes(enemy, restingEyes(enemy))
		local root, humanoid = characterOf(target)
		if root and humanoid and flat(root.Position - enemy.Root.Position) <= enemy.Def.AttackRange + enemy.Radius + 1.5 then
			damagePlayer(target, humanoid, enemy.Def.Damage)
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
	local ring = PartFactory.verticalCylinder(fxFolder, "SlamWarning", center + Vector3.new(0, 0.32, 0), 0.12, diameter, warningColor, Enum.Material.Neon, false)
	ring.Transparency = 0.55 -- borde bien visible: aquí acaba el área
	local fill = PartFactory.verticalCylinder(fxFolder, "SlamFill", center + Vector3.new(0, 0.36, 0), 0.14, 1, warningColor, Enum.Material.Neon, false)
	fill.Transparency = 0.55
	TweenService:Create(fill, TweenInfo.new(settings.Telegraph, Enum.EasingStyle.Linear), { Size = Vector3.new(0.14, diameter, diameter) }):Play()
	Debris:AddItem(ring, settings.Telegraph + 0.1)
	Debris:AddItem(fill, settings.Telegraph + 0.1)
	task.delay(settings.Telegraph, function()
		if enemy.Generation ~= generation or enemy.Status.State == "Dead" then
			return
		end
		burst(center + Vector3.new(0, 1, 0), enemy.Def.Look.Secondary, 30)
		-- Onda expansiva breve
		local wave = PartFactory.verticalCylinder(fxFolder, "SlamWave", center + Vector3.new(0, 0.4, 0), 0.3, diameter * 0.6, warningColor, Enum.Material.Neon, false)
		wave.Transparency = 0.3
		TweenService:Create(wave, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, diameter * 1.15, diameter * 1.15), Transparency = 1 }):Play()
		Debris:AddItem(wave, 0.45)
		for _, player in Players:GetPlayers() do
			local root, humanoid = characterOf(player)
			if root and humanoid and flat(root.Position - center) <= settings.Radius and math.abs(root.Position.Y - center.Y) < 12 then
				damagePlayer(player, humanoid, settings.Damage)
			end
		end
	end)
end

local function updateEnemy(enemy: Enemy, now: number)
	local status = enemy.Status
	if status.State == "Dead" or enemy.Model.Parent == nil then
		return
	end
	local position = enemy.Root.Position
	local fromHome = flat(position - enemy.LeashCenter)

	-- Volver a casa (invulnerable) y curarse al llegar; si se atasca, reaparece en su origen.
	if status.State == "Return" then
		if flat(position - enemy.Home) < 3 then
			EnemyLogic.reset(status)
			syncHealth(enemy)
			enemy.Humanoid.WalkSpeed = enemy.Def.WalkSpeed
			setEnraged(enemy, false)
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
		enemy.LastHomeDistance = math.huge
		setEyes(enemy, restingEyes(enemy))
		return
	end

	-- Validar u obtener objetivo
	local target = enemy.Target
	local targetRoot = if target and target.Parent then characterOf(target) else nil
	if not (targetRoot and canTarget(enemy, targetRoot.Position) and flat(targetRoot.Position - enemy.LeashCenter) <= enemy.LeashRadius + 6) then
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

	-- Jefe: golpe en área periódico (más seguido con furia)
	local slamSettings = enemy.Def.Slam
	if slamSettings and now >= enemy.NextSlam then
		local interval = slamSettings.Interval * (if enemy.Enraged then enemy.Def.Enrage.SlamIntervalMultiplier else 1)
		enemy.NextSlam = now + interval
		slam(enemy)
	end

	local offset = targetRoot.Position - position
	local distance = flat(offset)
	if distance <= enemy.Def.AttackRange + enemy.Radius then
		status.State = "Attack"
		-- Detenerse mirando al objetivo (si están superpuestos no hay dirección: solo parar)
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		enemy.Humanoid:MoveTo(if distance > 0.05 then position + flatOffset.Unit * 0.1 else position)
		if now >= enemy.NextAttack then
			enemy.NextAttack = now + enemy.Def.AttackCooldown
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
	workspace.Terrain:FillCylinder(CFrame.new(center + Vector3.new(0, -2, 0)), 4, arena.Radius, floor)

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

local function createEnemy(zoneId: string, typeId: string, home: Vector3, zoneSettings, leashCenter: Vector3?, leashRadius: number?): Enemy?
	local def = EnemyConfig.Types[typeId]
	if not def then
		warn("[EnemyService] Tipo de enemigo desconocido: " .. tostring(typeId))
		return nil
	end
	local shape = SHAPES[def.Look.Style]
	local rig = newRig(typeId, shape.Root, shape.Hip, def.WalkSpeed)
	BUILDERS[def.Look.Style](rig, def.Look)
	addJoints(rig, shape.Pivots)
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
		Home = home,
		LeashCenter = leashCenter or home,
		LeashRadius = leashRadius or def.LeashRange,
		DetectRange = def.DetectRange,
		SafeZones = safeZones,
		RewardMultiplier = zoneSettings.RewardMultiplier or 1,
		Status = { State = "Idle", Health = def.MaxHealth, MaxHealth = def.MaxHealth, Contributions = {} },
		Target = nil,
		NextAttack = 0,
		NextSlam = 0,
		NextWander = 0,
		Enraged = false,
		Generation = 0,
		StuckSince = nil,
		LastHomeDistance = math.huge,
	}
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
	respawn(enemy)
	return enemy
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

	for zoneId, zoneSettings in EnemyConfig.Zones do
		if not ZoneConfig.Zones[zoneId] then
			warn("[EnemyService] Zona desconocida en EnemyConfig: " .. zoneId)
			continue
		end
		PartFactory.folder(folder, zoneId)
		local center = zoneCenter(zoneId)
		for _, spawn in zoneSettings.Spawns do
			createEnemy(zoneId, spawn.Type, center + Vector3.new(spawn.Offset.X, 0, spawn.Offset.Y), zoneSettings, nil, nil)
		end
		local boss = zoneSettings.Boss
		if boss then
			local arenaCenter = center + Vector3.new(boss.Arena.Center.X, 0, boss.Arena.Center.Y)
			buildArena(arenas, zoneId, boss.Arena)
			local enemy = createEnemy(zoneId, boss.Type, arenaCenter, zoneSettings, arenaCenter, boss.Arena.Radius)
			if enemy then
				enemy.Model:SetAttribute("ArenaCenter", arenaCenter)
				enemy.Model:SetAttribute("ArenaRadius", boss.Arena.Radius)
				enemy.Model:SetAttribute("ArenaName", boss.Arena.Name)
			end
		end
	end

	-- Un único bucle de IA para todos los enemigos.
	task.spawn(function()
		while true do
			task.wait(EnemyConfig.AiTickSeconds)
			local now = os.clock()
			for _, enemy in enemies do
				local ok, err = pcall(updateEnemy, enemy, now)
				if not ok then
					warn("[EnemyService] Error en la IA de " .. enemy.TypeId .. ": " .. tostring(err))
				end
			end
		end
	end)
end

return EnemyService
