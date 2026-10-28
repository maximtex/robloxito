-- Lógica pura de enemigos (sin APIs de Roblox), para poder probarla fuera de Studio.
-- La usa EnemyService para el daño, la muerte, el reparto de recompensas y los estados
-- de control de las habilidades (ralentizar, inmovilizar, aturdir, marcar), y
-- CombatService para elegir los objetivos de un golpe.

local EnemyLogic = {}

export type EnemyState = {
	State: string, -- "Idle" | "Chase" | "Attack" | "Return" | "Dead"
	Health: number,
	MaxHealth: number,
	Contributions: { [number]: number }, -- userId -> daño hecho en esta vida
}

-- Aplica daño. No hace nada si está muerto o volviendo a casa (así no se puede sacar a
-- un enemigo de su zona para matarlo sin que se defienda). Devuelve el daño aplicado y
-- si ESTE golpe lo ha matado: solo un golpe puede devolver killed = true por vida.
function EnemyLogic.applyDamage(enemy: EnemyState, attackerId: number, amount: number): (number, boolean)
	if enemy.State == "Dead" or enemy.State == "Return" then
		return 0, false
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0, false
	end
	local dealt = math.min(amount, enemy.Health)
	enemy.Health -= dealt
	enemy.Contributions[attackerId] = (enemy.Contributions[attackerId] or 0) + dealt
	if enemy.Health <= 0 then
		enemy.Health = 0
		enemy.State = "Dead" -- a partir de aquí no acepta más daño ni recompensas
		return dealt, true
	end
	return dealt, false
end

-- Reparte la recompensa según el daño de cada participante. La suma de lo repartido
-- nunca supera `reward` (se redondea hacia abajo y el resto va al que más daño hizo).
function EnemyLogic.splitReward(contributions: { [number]: number }, reward: number): { [number]: number }
	local total = 0
	for _, damage in contributions do
		total += damage
	end
	local payouts: { [number]: number } = {}
	if total <= 0 or reward <= 0 then
		return payouts
	end
	local given, topId, topDamage = 0, nil, -1
	for userId, damage in contributions do
		local share = math.floor(reward * damage / total)
		payouts[userId] = share
		given += share
		if damage > topDamage then
			topId, topDamage = userId, damage
		end
	end
	if topId ~= nil then
		payouts[topId] += reward - given
	end
	return payouts
end

-- Restablece un enemigo para una vida nueva (al reaparecer o al volver a casa).
function EnemyLogic.reset(enemy: EnemyState)
	enemy.Health = enemy.MaxHealth
	enemy.State = "Idle"
	table.clear(enemy.Contributions)
end

export type Candidate = { Id: any, X: number, Z: number, Radius: number, Alive: boolean }

-- Objetivos de un golpe: vivos, dentro del alcance (hasta su borde) y por delante del
-- jugador (o pegados a él). Sin repetidos, ordenados por cercanía y como mucho `maxTargets`.
function EnemyLogic.selectTargets(originX: number, originZ: number, lookX: number, lookZ: number, candidates: { Candidate }, range: number, arcDot: number, maxTargets: number): { any }
	local lookLength = math.sqrt(lookX * lookX + lookZ * lookZ)
	if lookLength > 0 then
		lookX, lookZ = lookX / lookLength, lookZ / lookLength
	end
	local hits = {}
	local seen = {}
	for _, candidate in candidates do
		if candidate.Alive and not seen[candidate.Id] then
			local dx, dz = candidate.X - originX, candidate.Z - originZ
			local distance = math.sqrt(dx * dx + dz * dz)
			local edge = distance - candidate.Radius
			if edge <= range then
				local facing = if distance > 0 then (dx * lookX + dz * lookZ) / distance else 1
				if facing >= arcDot or distance < 4 + candidate.Radius then
					seen[candidate.Id] = true
					table.insert(hits, { Id = candidate.Id, Distance = distance })
				end
			end
		end
	end
	table.sort(hits, function(a, b)
		return a.Distance < b.Distance
	end)
	local result = {}
	for index = 1, math.min(maxTargets, #hits) do
		result[index] = hits[index].Id
	end
	return result
end

-- Estados de control (habilidades elementales) -------------------------------------
-- Tiempos en os.clock(). Cada estado dura hasta su "Until"; uno nuevo nunca acorta el
-- que ya hay y, si coinciden, se queda la ralentización más fuerte y el bonus mayor.

export type Control = {
	SlowUntil: number,
	SlowFactor: number, -- multiplicador de velocidad y ritmo de ataque (0.1..1)
	RootUntil: number, -- no anda (sí ataca si te tiene a su alcance)
	StunUntil: number, -- ni anda ni ataca
	VulnerableUntil: number,
	VulnerableBonus: number, -- daño recibido extra (0..1)
	AuraElement: string?, -- marca elemental para los combos (nil si no hay)
	AuraUntil: number,
}

function EnemyLogic.newControl(): Control
	return { SlowUntil = 0, SlowFactor = 1, RootUntil = 0, StunUntil = 0, VulnerableUntil = 0, VulnerableBonus = 0, AuraElement = nil, AuraUntil = 0 }
end

function EnemyLogic.clearControl(control: Control)
	control.SlowUntil, control.SlowFactor = 0, 1
	control.RootUntil, control.StunUntil = 0, 0
	control.VulnerableUntil, control.VulnerableBonus = 0, 0
	control.AuraElement, control.AuraUntil = nil, 0
end

local function validSeconds(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

-- Marca elemental (combos): la pone o la quita (element = nil). Nunca dura más de maxSeconds.
function EnemyLogic.setAura(control: Control, element: string?, now: number, seconds: number?, maxSeconds: number)
	if element == nil or not validSeconds(seconds) then
		control.AuraElement, control.AuraUntil = nil, 0
		return
	end
	control.AuraElement = element
	control.AuraUntil = now + math.min(seconds :: number, maxSeconds)
end

-- Marca activa o nil.
function EnemyLogic.auraOf(control: Control, now: number): string?
	if control.AuraElement ~= nil and now < control.AuraUntil then
		return control.AuraElement
	end
	return nil
end

-- Aplica un estado. kind: "Slow" (factor = velocidad), "Root", "Stun" o "Vulnerable"
-- (factor = daño extra). Devuelve true si se ha aplicado.
function EnemyLogic.applyControl(control: Control, kind: string, now: number, seconds: number, factor: number?, maxSeconds: number): boolean
	if not validSeconds(seconds) then
		return false
	end
	local untilTime = now + math.min(seconds, maxSeconds)
	if kind == "Slow" then
		if type(factor) ~= "number" or factor ~= factor then
			return false
		end
		local clean = math.clamp(factor, 0.1, 1)
		local active = now < control.SlowUntil
		control.SlowFactor = if active then math.min(control.SlowFactor, clean) else clean
		control.SlowUntil = math.max(control.SlowUntil, untilTime)
	elseif kind == "Root" then
		control.RootUntil = math.max(control.RootUntil, untilTime)
	elseif kind == "Stun" then
		control.StunUntil = math.max(control.StunUntil, untilTime)
	elseif kind == "Vulnerable" then
		if type(factor) ~= "number" or factor ~= factor then
			return false
		end
		local clean = math.clamp(factor, 0, 1)
		local active = now < control.VulnerableUntil
		control.VulnerableBonus = if active then math.max(control.VulnerableBonus, clean) else clean
		control.VulnerableUntil = math.max(control.VulnerableUntil, untilTime)
	else
		return false
	end
	return true
end

function EnemyLogic.isStunned(control: Control, now: number): boolean
	return now < control.StunUntil
end

-- Velocidad al andar con los estados actuales (base = ya con la furia aplicada).
function EnemyLogic.speed(base: number, control: Control, now: number): number
	if now < control.RootUntil or now < control.StunUntil then
		return 0
	end
	if now < control.SlowUntil then
		return base * control.SlowFactor
	end
	return base
end

-- Tiempo hasta el siguiente golpe: más largo mientras está ralentizado.
function EnemyLogic.attackCooldown(cooldown: number, control: Control, now: number): number
	if now < control.SlowUntil and control.SlowFactor > 0 then
		return cooldown / control.SlowFactor
	end
	return cooldown
end

-- Daño que recibe con los estados actuales (marcado: más daño).
function EnemyLogic.damageTaken(amount: number, control: Control, now: number): number
	if now < control.VulnerableUntil then
		return amount * (1 + control.VulnerableBonus)
	end
	return amount
end

-- Persecución de los jefes (anti "kiteo"; EnemyConfig.Pursuit): tras `farFor` segundos con su
-- objetivo fuera del alcance de sus golpes, a partir de Delay acelera Ramp por segundo hasta
-- Max × su velocidad, pero sin pasar de CatchUp × la velocidad de su objetivo (así se le acerca
-- al que corre en círculos sin ser imposible de esquivar). Devuelve el multiplicador (>= 1).
function EnemyLogic.pursuitBoost(farFor: number, settings: any, baseSpeed: number, targetSpeed: number?): number
	if type(settings) ~= "table" or type(farFor) ~= "number" or farFor ~= farFor then
		return 1
	end
	local delay = if type(settings.Delay) == "number" then settings.Delay else 1.5
	local ramp = if type(settings.Ramp) == "number" then math.max(0, settings.Ramp) else 0
	local max = if type(settings.Max) == "number" then math.max(1, settings.Max) else 1
	if farFor <= delay or ramp <= 0 then
		return 1
	end
	local cap = max
	local catchUp = if type(settings.CatchUp) == "number" then settings.CatchUp else 1
	if type(targetSpeed) == "number" and targetSpeed == targetSpeed and targetSpeed > 0 and baseSpeed > 0 then
		cap = math.clamp(targetSpeed * catchUp / baseSpeed, 1, max)
	end
	return math.clamp(1 + (farFor - delay) * ramp, 1, cap)
end

-- Objetivos de un área: vivos, con su borde dentro del radio alrededor del centro, sin
-- repetidos, ordenados por cercanía y como mucho `maxTargets`.
function EnemyLogic.selectInRadius(centerX: number, centerZ: number, candidates: { Candidate }, radius: number, maxTargets: number): { any }
	local hits = {}
	local seen = {}
	for _, candidate in candidates do
		if candidate.Alive and not seen[candidate.Id] then
			local dx, dz = candidate.X - centerX, candidate.Z - centerZ
			local distance = math.sqrt(dx * dx + dz * dz)
			if distance - candidate.Radius <= radius then
				seen[candidate.Id] = true
				table.insert(hits, { Id = candidate.Id, Distance = distance })
			end
		end
	end
	table.sort(hits, function(a, b)
		return a.Distance < b.Distance
	end)
	local result = {}
	for index = 1, math.min(maxTargets, #hits) do
		result[index] = hits[index].Id
	end
	return result
end

return EnemyLogic
