-- Lógica pura de enemigos (sin APIs de Roblox), para poder probarla fuera de Studio.
-- La usa EnemyService para el daño, la muerte y el reparto de recompensas, y
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
