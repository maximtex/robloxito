-- StyleService · Core: constantes, combos, estado de cada jugador, estilo, habilidades y clases del perfil.
-- Parte de StyleService (ver StyleService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)
local StyleLogic = require(Shared.StyleLogic)
local SkillLogic = require(Shared.SkillLogic)
local ClassLogic = require(Shared.ClassLogic)
local PlayerDataService = require(script.Parent.Parent.PlayerDataService)
local RateLimiter = require(script.Parent.Parent.Parent.Util.RateLimiter)

local ctx: any -- tabla de estado compartida (la crea StyleService/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a StyleService)

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
			ctx.eventRemote:FireClient(player, event)
		end
	end
end

local function result(player: Player, data: { [string]: any })
	data.Kind = "Result"
	data.Owner = player
	ctx.eventRemote:FireClient(player, data)
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
Api.classModsOf = classModsOf

-- DPS del estilo (con el arma, la cadencia, mascotas y bonificaciones)
local function styleDps(profile, style: string): number
	local stats = PlayerDataService.combatStats(profile)
	return StyleLogic.dps(stats.Dps, style)
end

-- Para pruebas y otros servicios: el default por si un perfil no tiene estilo.
Api.DefaultStyle = StyleConfig.Default
Api.Combo = COMBO

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
	context.CHAIN_AIM = CHAIN_AIM
	context.COMBO = COMBO
	context.Codes = Codes
	context.DASH_STEP = DASH_STEP
	context.DASH_WALL_GAP = DASH_WALL_GAP
	context.SLOT_ATTRIBUTES = SLOT_ATTRIBUTES
	context.broadcast = broadcast
	context.buffUntil = buffUntil
	context.classModsOf = classModsOf
	context.classesOf = classesOf
	context.dashReadyAt = dashReadyAt
	context.generation = generation
	context.lastSwitch = lastSwitch
	context.limiter = limiter
	context.rageTaken = rageTaken
	context.rageUntil = rageUntil
	context.readyAt = readyAt
	context.result = result
	context.rootOf = rootOf
	context.serverNow = serverNow
	context.shopLimiter = shopLimiter
	context.skillsOf = skillsOf
	context.styleDps = styleDps
	context.styleOf = styleOf
	context.validAim = validAim
end

function Part.link(context: any)
	-- (nada que enlazar)
end

return Part
