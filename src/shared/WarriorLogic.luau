-- Lógica pura del estilo Guerrero (StyleConfig.Styles.Warrior): el combo de 3 tajos (cuál
-- toca y cuánto tarda el siguiente) y el bloqueo con su parada perfecta. Sin servicios: la
-- usan PetCombatService (tajos y bloqueo) y las pruebas.

local StyleConfig = require(script.Parent.Config.StyleConfig)

local WarriorLogic = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function def()
	return StyleConfig.Styles.Warrior
end
WarriorLogic.definition = def

export type ComboState = { Step: number, Last: number }
export type BlockState = { Blocking: boolean, Since: number, LastStart: number, ParryArmed: boolean }

function WarriorLogic.newCombo(): ComboState
	return { Step = 0, Last = -math.huge }
end

-- El tajo que toca ahora (1, 2 o 3) y su definición. Si pasó más de ComboWindow desde el
-- anterior, se vuelve al 1. Cambia `state`.
function WarriorLogic.nextSlash(state: ComboState, now: number): (number, { [string]: any })
	local slashes = def().Slashes
	if not finite(state.Last) or not finite(now) or now - state.Last > def().ComboWindow or state.Step >= #slashes then
		state.Step = 0
	end
	state.Step += 1
	state.Last = now
	return state.Step, slashes[state.Step]
end

-- Tiempo hasta el siguiente tajo tras el tajo `slash` con `cooldown` normal
function WarriorLogic.recovery(slash: { [string]: any }, cooldown: number): number
	return cooldown * (if finite(slash.Recovery) then slash.Recovery else 1)
end

-- Bloqueo ------------------------------------------------------------------------------

function WarriorLogic.newBlock(): BlockState
	return { Blocking = false, Since = -math.huge, LastStart = -math.huge, ParryArmed = false }
end

-- Empieza a bloquear. La parada perfecta solo vale si no empezaste otro bloqueo hace menos de
-- ParryRearm (machacar el clic derecho no sirve).
function WarriorLogic.startBlock(state: BlockState, now: number)
	if state.Blocking then
		return
	end
	local spec = def().Block
	state.ParryArmed = now - state.LastStart >= spec.ParryRearm
	state.LastStart = now
	state.Since = now
	state.Blocking = true
end

function WarriorLogic.stopBlock(state: BlockState)
	state.Blocking = false
	state.ParryArmed = false
end

-- Te pegan ahora: la parte del daño que recibes y si ha sido una parada perfecta (0 de daño;
-- la parada se gasta).
function WarriorLogic.incoming(state: BlockState?, now: number): (number, boolean)
	if not (state and state.Blocking) then
		return 1, false
	end
	local spec = def().Block
	if state.ParryArmed and now - state.Since <= spec.ParryWindow then
		state.ParryArmed = false
		return 0, true
	end
	return spec.DamageTaken, false
end

return WarriorLogic
