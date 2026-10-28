-- Fórmulas de las habilidades elementales (puras, sin APIs de Roblox). El servidor
-- (AbilityService) calcula con ellas el efecto real; el resumen de texto lo enseña el
-- panel de núcleos. Ver AbilityConfig para los números y su porqué.

local AbilityConfig = require(script.Parent.Config.AbilityConfig)

local AbilityLogic = {}

local DEFAULT_ELEMENT = "Nature"

function AbilityLogic.get(elementId: any): any
	if type(elementId) ~= "string" then
		return nil
	end
	return AbilityConfig.Abilities[elementId]
end

-- La habilidad que da un elemento en la Q / R (nil si no da ninguna: Naturaleza, Skill =
-- false). get() sigue devolviendo sus datos para las marcas y los combos.
function AbilityLogic.castable(elementId: any): any
	local ability = AbilityLogic.get(elementId)
	if ability and ability.Skill == false then
		return nil
	end
	return ability
end

local function round2(value: number): number
	return math.floor(value * 100 + 0.5) / 100
end

-- Multiplicador por el nivel del núcleo (Naturaleza: siempre 1, ver AbilityConfig).
function AbilityLogic.mastery(elementId: string, level: any): number
	if elementId == DEFAULT_ELEMENT or type(level) ~= "number" or level ~= level then
		return 1
	end
	local settings = AbilityConfig.Mastery
	local capped = math.clamp(math.floor(level), 0, settings.MaxLevel)
	return 1 + settings.PerLevel * capped
end

-- Daño de un efecto: fracción del daño del jugador por la maestría del núcleo.
function AbilityLogic.damage(elementId: string, ratio: number, playerDamage: number, level: any): number
	if type(playerDamage) ~= "number" or playerDamage ~= playerDamage or playerDamage <= 0 then
		return 0
	end
	return round2(math.max(0, ratio) * playerDamage * AbilityLogic.mastery(elementId, level))
end

-- Daños de la cadena de rayos: el primero completo y cada salto un JumpFalloff del anterior.
function AbilityLogic.chainDamages(first: number, jumps: number, falloff: number): { number }
	local result = { first }
	local current = first
	for _ = 1, math.max(0, math.floor(jumps)) do
		current = round2(current * falloff)
		table.insert(result, current)
	end
	return result
end

export type Candidate = { Id: any, X: number, Z: number, Radius: number, Alive: boolean }

-- Orden de la cadena: desde `firstId`, cada salto va al enemigo vivo más cercano que aún
-- no ha recibido el rayo y está a `jumpRange` o menos (hasta su borde). Sin repetidos.
function AbilityLogic.chainOrder(candidates: { Candidate }, firstId: any, jumpRange: number, jumps: number): { any }
	local byId: { [any]: Candidate } = {}
	for _, candidate in candidates do
		if candidate.Alive then
			byId[candidate.Id] = candidate
		end
	end
	local current = byId[firstId]
	if not current then
		return {}
	end
	local order = { firstId }
	local visited = { [firstId] = true }
	for _ = 1, math.max(0, math.floor(jumps)) do
		local best, bestDistance = nil, math.huge
		for _, candidate in candidates do
			if candidate.Alive and not visited[candidate.Id] then
				local dx, dz = candidate.X - current.X, candidate.Z - current.Z
				local distance = math.sqrt(dx * dx + dz * dz)
				if distance - candidate.Radius <= jumpRange and distance < bestDistance then
					best, bestDistance = candidate, distance
				end
			end
		end
		if not best then
			break
		end
		visited[best.Id] = true
		table.insert(order, best.Id)
		current = best
	end
	return order
end

-- Duración y fuerza de un estado de control según si el objetivo es un jefe.
-- kind: "Root" | "Stun" (dura menos) o "Slow" (factor de velocidad: más débil).
function AbilityLogic.control(kind: string, seconds: number, factor: number?, isBoss: boolean): (number, number)
	local cap = AbilityConfig.MaxControlSeconds
	local duration = math.clamp(seconds, 0, cap)
	local strength = factor or 0
	if isBoss then
		if kind == "Slow" then
			-- Ralentizar a la mitad de fuerza: factor 0.5 -> 0.75
			strength = 1 - (1 - (factor or 1)) * 0.5
		else
			duration = duration * AbilityConfig.BossControl
		end
	end
	return duration, strength
end

-- Combos ------------------------------------------------------------------------------

-- Si una habilidad de este elemento deja su marca en los enemigos (el Viento no).
function AbilityLogic.leavesAura(elementId: any): boolean
	return AbilityLogic.get(elementId) ~= nil and not AbilityConfig.Aura.NoAura[elementId]
end

-- Combo que se dispara al alcanzar con `incoming` a un enemigo con la marca `aura` (o nil).
function AbilityLogic.reaction(aura: any, incoming: any): string?
	if type(aura) ~= "string" or type(incoming) ~= "string" or aura == incoming then
		return nil
	end
	for id, reaction in AbilityConfig.Reactions do
		if reaction.Trigger then
			if incoming == reaction.Trigger and reaction.Spreads[aura] then
				return id
			end
		elseif reaction.Pair then
			local a, b = reaction.Pair[1], reaction.Pair[2]
			if (a == aura and b == incoming) or (b == aura and a == incoming) then
				return id
			end
		end
	end
	return nil
end

-- Combos en los que participa un elemento: { { Reaction, With } } (With = el otro
-- elemento, o "*" para el Remolino del Viento). Ordenados por nombre de combo.
function AbilityLogic.partners(elementId: string): { { Reaction: string, With: string } }
	local list = {}
	for id, reaction in AbilityConfig.Reactions do
		if reaction.Trigger then
			if reaction.Trigger == elementId then
				table.insert(list, { Reaction = id, With = "*" })
			elseif reaction.Spreads[elementId] then
				table.insert(list, { Reaction = id, With = reaction.Trigger })
			end
		elseif reaction.Pair then
			if reaction.Pair[1] == elementId then
				table.insert(list, { Reaction = id, With = reaction.Pair[2] })
			elseif reaction.Pair[2] == elementId then
				table.insert(list, { Reaction = id, With = reaction.Pair[1] })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Reaction < b.Reaction
	end)
	return list
end

-- Texto de combos para la interfaz: "💧 ¡Electrocutado!  ·  ❄ ¡Superconductor!".
function AbilityLogic.partnersText(elementId: string): string
	local parts = {}
	for _, entry in AbilityLogic.partners(elementId) do
		local reaction = AbilityConfig.Reactions[entry.Reaction]
		local other = AbilityLogic.get(entry.With)
		local icon = if entry.With == "*" then "★" elseif other then other.Icon else "?"
		table.insert(parts, ("%s %s"):format(icon, reaction.Name))
	end
	return table.concat(parts, "  ·  ")
end

-- Número de tics de una quemadura.
function AbilityLogic.burnTicks(ability: any): number
	return math.max(1, math.floor(ability.BurnSeconds / ability.BurnTickSeconds + 1e-6))
end

local function short(value: number): string
	if value >= 100 then
		return tostring(math.floor(value + 0.5))
	end
	local rounded = math.floor(value * 10 + 0.5) / 10
	if rounded == math.floor(rounded) then
		return tostring(math.floor(rounded))
	end
	return string.format("%.1f", rounded)
end

local function percent(value: number): string
	return tostring(math.floor(value * 100 + 0.5))
end

-- Resumen para la interfaz con los números reales (daño del jugador y nivel del núcleo).
function AbilityLogic.summary(elementId: string, playerDamage: number, level: any): string
	local ability = AbilityLogic.get(elementId)
	if not ability then
		return ""
	end
	local function dmg(ratio: number): string
		return short(AbilityLogic.damage(elementId, ratio, playerDamage, level))
	end
	local kind = ability.Type
	if kind == "Roots" then
		return ("%s de daño a tu alrededor e inmoviliza %s s"):format(dmg(ability.DamageRatio), short(ability.RootSeconds))
	elseif kind == "Heal" then
		return ("Te cura un %s %% de vida (aliados %s %%) y hace %s de daño"):format(percent(ability.HealFraction), percent(ability.AllyHealFraction), dmg(ability.DamageRatio))
	elseif kind == "Burn" then
		local total = AbilityLogic.damage(elementId, ability.BurnRatioPerTick, playerDamage, level) * AbilityLogic.burnTicks(ability)
		return ("Llamarada de %s y quemadura de %s en %s s"):format(dmg(ability.DamageRatio), short(total), short(ability.BurnSeconds))
	elseif kind == "Gust" then
		return ("%s de daño delante y +%s %% de velocidad %s s"):format(dmg(ability.DamageRatio), percent(ability.HasteBonus), short(ability.HasteSeconds))
	elseif kind == "Chain" then
		return ("Rayo de %s que salta a %d enemigos más"):format(dmg(ability.DamageRatio), ability.Jumps)
	elseif kind == "Frost" then
		return ("%s de daño a tu alrededor y ralentiza un %s %% %s s"):format(dmg(ability.DamageRatio), percent(1 - ability.SlowFactor), short(ability.SlowSeconds))
	elseif kind == "Curse" then
		return ("%s de daño; los marcados reciben +%s %% de daño %s s"):format(dmg(ability.DamageRatio), percent(ability.VulnerableBonus), short(ability.CurseSeconds))
	elseif kind == "Starfall" then
		return ("%d oleadas de estrellas de %s delante de ti"):format(ability.Waves, dmg(ability.DamageRatio))
	end
	return ""
end

return AbilityLogic
