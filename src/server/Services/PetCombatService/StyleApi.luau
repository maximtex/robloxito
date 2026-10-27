-- PetCombatService · StyleApi: lo que usa StyleService: recargar, golpe elemental, maná y bloqueo.
-- Parte de PetCombatService (ver PetCombatService/init.luau): el estado compartido llega en install()
-- y lo de las demás partes, en link() o con un reenvío.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StyleConfig = require(Shared.Config.StyleConfig)
local MagicLogic = require(Shared.MagicLogic)
local WarriorLogic = require(Shared.WarriorLogic)
local EnemyService = require(script.Parent.Parent.EnemyService)

local ctx: any -- tabla de estado compartida (la crea PetCombatService/init.luau)
local Api = {} -- funciones públicas de esta parte (init.luau las copia a PetCombatService)
local states: any

-- Funciones de las otras partes
local function broadcast(...) return ctx.broadcast(...) end
local function control(...) return ctx.control(...) end
local function rootOf(...) return ctx.rootOf(...) end
local function spendMana(...) return ctx.spendMana(...) end
local function stateOf(...) return ctx.stateOf(...) end

-- Para StyleService ------------------------------------------------------------------------

-- Cargador y maná llenos y listo para atacar (pruebas y regalos)
function Api.refill(player: Player)
	local state = states[player]
	if state then
		state.AmmoWeapon = nil
		state.ReloadUntil = 0
		state.Mana = MagicLogic.maxMana()
		state.NextShotAt = 0
	end
end

-- Marca y combos elementales de un golpe (habilidades de Magia): el multiplicador del daño
function Api.elementHit(player: Player, enemy: any, element: string, amount: number): number
	if not ctx.elementHook then
		return 1
	end
	local ok, multiplier = pcall(ctx.elementHook, player, enemy, element, amount)
	return if ok and type(multiplier) == "number" and multiplier == multiplier then math.clamp(multiplier, 0, 4) else 1
end

-- Maná que tiene ahora el jugador
function Api.mana(player: Player): number
	local state = states[player]
	return if state then state.Mana else MagicLogic.maxMana()
end

-- Gasta maná (habilidades, teletransporte). false si no le llega.
function Api.spendMana(player: Player, cost: number): boolean
	return spendMana(player, stateOf(player), cost, os.clock())
end

-- Le pegan al jugador (EnemyService, por StyleService): la parte del daño que recibe al
-- bloquear con el Guerrero. Con una parada perfecta no recibe nada, aturde a `enemy` y su
-- siguiente tajo es un contraataque.
function Api.blockIncoming(player: Player, enemy: any?): number
	local state = states[player]
	if not (state and state.Style == "Warrior") then
		return 1
	end
	local now = os.clock()
	local factor, parried = WarriorLogic.incoming(state.Block, now)
	if factor < 1 and not parried then
		-- Bloqueado (sin parada): chispas en la espada
		local root = rootOf(player)
		if root then
			local at = root.Position
			if enemy and enemy.Root then
				-- Un poco hacia el bicho (donde choca la espada)
				local dx, dz = enemy.Root.Position.X - at.X, enemy.Root.Position.Z - at.Z
				local length = math.sqrt(dx * dx + dz * dz)
				if length > 0.1 then
					at = Vector3.new(at.X + dx / length * 1.5, at.Y, at.Z + dz / length * 1.5)
				end
			end
			broadcast(player, at, { Kind = "Blocked", Position = at })
		end
	end
	if parried then
		local spec = StyleConfig.Styles.Warrior.Block
		state.CounterUntil = now + spec.CounterSeconds
		local root = rootOf(player)
		if enemy and EnemyService.isAlive(enemy) then
			control(enemy, "Stun", spec.Stun)
		end
		local at = if enemy and enemy.Root then enemy.Root.Position elseif root then root.Position else nil
		if at then
			broadcast(player, at, { Kind = "Parry", Position = at })
		end
	end
	return factor
end

local Part = { Api = Api }

function Part.install(context: any)
	ctx = context
end

function Part.link(context: any)
	states = context.states
end

return Part
