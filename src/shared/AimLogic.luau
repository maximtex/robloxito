-- Puntería: a quién da un golpe lanzado hacia donde apunta el jugador (el ratón, el toque o
-- hacia donde mira). Todo en plano (X y Z); la altura la comprueba quien llama.
-- - Armas: un disparo recto que da al primer enemigo que cruza la línea (su cuerpo más un
--   margen pequeño), hasta el alcance del arma (lineHits: también los que atraviesa el
--   francotirador). Si no hay nadie en la línea, falla.
-- - Magia: persigue al enemigo más cercano al punto apuntado (nearPoint con LockRadius); si
--   no hay, explota donde apuntabas (o al final de su alcance).
-- - Puños: el más cercano delante de ti (en un arco hacia donde apuntas) y a tu alcance.
-- - Guerrero: todos los del arco del tajo (arcAll; el giro, alrededor).
-- Sin datos del motor: lo usan el servidor (PetCombatService) y las pruebas.

local AimLogic = {}

AimLogic.Tolerance = { Weapons = 1.5, Magic = 2.5, Fists = 0, Warrior = 0 }
AimLogic.FistArcDegrees = 50
-- El enemigo sobre el que hiciste clic se mueve mientras el disparo viaja por la red: si el
-- punto apuntado cae a esto (o menos) de su cuerpo, también le das.
AimLogic.PointSlack = 3

export type Candidate = { Id: any, X: number, Z: number, Radius: number }

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
AimLogic.finite = finite

-- Dirección plana y unitaria de (ox, oz) hacia (ax, az); nil si el punto está encima.
function AimLogic.direction(ox: number, oz: number, ax: number, az: number): (number?, number?)
	if not (finite(ox) and finite(oz) and finite(ax) and finite(az)) then
		return nil, nil
	end
	local dx, dz = ax - ox, az - oz
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 0.5 then
		return nil, nil
	end
	return dx / length, dz / length
end

-- Primer enemigo en la línea que sale de (ox, oz) hacia (dx, dz): su cuerpo (Radius) más
-- `tolerance` toca la línea, está delante y su borde queda a `range` o menos. Si estás
-- pegado a uno (dentro de su cuerpo más el margen), le das aunque apuntes de lado.
-- Devuelve su Id y la distancia a lo largo de la línea.
function AimLogic.alongLine(ox: number, oz: number, dx: number, dz: number, candidates: { Candidate }, range: number, tolerance: number): (any?, number?)
	local bestId, bestKey, bestAlong = nil, math.huge, nil
	for _, candidate in candidates do
		local rx, rz = candidate.X - ox, candidate.Z - oz
		local distance = math.sqrt(rx * rx + rz * rz)
		local radius = math.max(0, candidate.Radius or 0)
		if distance - radius <= range then
			local along = rx * dx + rz * dz
			local px, pz = rx - dx * along, rz - dz * along
			local side = math.sqrt(px * px + pz * pz)
			local reach = radius + tolerance
			local touching = distance <= reach
			if touching or (along > 0 and side <= reach) then
				-- El primero que se cruza: donde la línea entra en su cuerpo
				local key = if touching then 0 else along - math.sqrt(math.max(0, reach * reach - side * side))
				if key < bestKey then
					bestId, bestKey, bestAlong = candidate.Id, key, math.max(0, along)
				end
			end
		end
	end
	return bestId, bestAlong
end

-- Todos los enemigos que toca la línea (como alongLine), del primero al último, como mucho
-- `maxHits`: { { Id, Along } }.
function AimLogic.lineHits(ox: number, oz: number, dx: number, dz: number, candidates: { Candidate }, range: number, tolerance: number, maxHits: number): { { Id: any, Along: number } }
	local hits = {}
	for _, candidate in candidates do
		local rx, rz = candidate.X - ox, candidate.Z - oz
		local distance = math.sqrt(rx * rx + rz * rz)
		local radius = math.max(0, candidate.Radius or 0)
		if distance - radius <= range then
			local along = rx * dx + rz * dz
			local px, pz = rx - dx * along, rz - dz * along
			local side = math.sqrt(px * px + pz * pz)
			local reach = radius + tolerance
			local touching = distance <= reach
			if touching or (along > 0 and side <= reach) then
				local key = if touching then 0 else along - math.sqrt(math.max(0, reach * reach - side * side))
				table.insert(hits, { Id = candidate.Id, Along = math.max(0, along), Key = key })
			end
		end
	end
	table.sort(hits, function(a, b)
		return a.Key < b.Key
	end)
	local result = {}
	for index = 1, math.min(#hits, math.max(1, math.floor(maxHits))) do
		table.insert(result, { Id = hits[index].Id, Along = hits[index].Along })
	end
	return result
end

-- ¿Está el enemigo dentro del arco (±arcDegrees hacia (dx, dz), contando lo ancho que es)?
local function insideArc(rx: number, rz: number, distance: number, radius: number, dx: number, dz: number, arc: number): boolean
	if distance <= radius + 0.5 or arc >= math.pi - 1e-6 then
		return true
	end
	local cosine = math.clamp((rx * dx + rz * dz) / distance, -1, 1)
	local width = math.asin(math.clamp(radius / distance, 0, 1))
	return math.acos(cosine) <= arc + width
end

-- Guerrero: todos los enemigos a tu alcance dentro del arco (±arcDegrees; 180 = alrededor),
-- del más cercano al más lejano, como mucho `maxTargets`.
function AimLogic.arcAll(ox: number, oz: number, dx: number, dz: number, candidates: { Candidate }, range: number, arcDegrees: number, maxTargets: number): { any }
	local arc = math.rad(arcDegrees)
	local found = {}
	for _, candidate in candidates do
		local rx, rz = candidate.X - ox, candidate.Z - oz
		local distance = math.sqrt(rx * rx + rz * rz)
		local radius = math.max(0, candidate.Radius or 0)
		if distance - radius <= range and insideArc(rx, rz, distance, radius, dx, dz, arc) then
			table.insert(found, { Id = candidate.Id, Distance = distance })
		end
	end
	table.sort(found, function(a, b)
		return a.Distance < b.Distance
	end)
	local result = {}
	for index = 1, math.min(#found, math.max(1, math.floor(maxTargets))) do
		table.insert(result, found[index].Id)
	end
	return result
end

-- Puños: el más cercano a tu alcance dentro del arco (±arcDegrees, contando lo ancho que es).
function AimLogic.inArc(ox: number, oz: number, dx: number, dz: number, candidates: { Candidate }, range: number, arcDegrees: number): any?
	local bestId, bestDistance = nil, math.huge
	local arc = math.rad(arcDegrees)
	for _, candidate in candidates do
		local rx, rz = candidate.X - ox, candidate.Z - oz
		local distance = math.sqrt(rx * rx + rz * rz)
		local radius = math.max(0, candidate.Radius or 0)
		if distance - radius <= range and distance < bestDistance then
			local inside = distance <= radius + 0.5
			local ok = inside
			if not ok then
				local cosine = math.clamp((rx * dx + rz * dz) / distance, -1, 1)
				local width = math.asin(math.clamp(radius / distance, 0, 1))
				ok = math.acos(cosine) <= arc + width
			end
			if ok then
				bestId, bestDistance = candidate.Id, distance
			end
		end
	end
	return bestId
end

-- El enemigo (a tu alcance) cuyo cuerpo queda a `slack` o menos del punto (ax, az).
function AimLogic.nearPoint(ox: number, oz: number, ax: number, az: number, candidates: { Candidate }, range: number, slack: number): any?
	local bestId, bestGap = nil, math.huge
	for _, candidate in candidates do
		local radius = math.max(0, candidate.Radius or 0)
		local fx, fz = candidate.X - ox, candidate.Z - oz
		if math.sqrt(fx * fx + fz * fz) - radius <= range then
			local px, pz = candidate.X - ax, candidate.Z - az
			local gap = math.sqrt(px * px + pz * pz) - radius
			if gap <= slack and gap < bestGap then
				bestId, bestGap = candidate.Id, gap
			end
		end
	end
	return bestId
end

-- A quién da un golpe del estilo `style` desde (ox, oz) hacia (dx, dz), apuntado al punto
-- (ax, az), con alcance `range` (nil: falla).
function AimLogic.pick(style: string, ox: number, oz: number, dx: number, dz: number, ax: number?, az: number?, candidates: { Candidate }, range: number): any?
	if style == "Fists" then
		return AimLogic.inArc(ox, oz, dx, dz, candidates, range, AimLogic.FistArcDegrees)
	end
	local tolerance = AimLogic.Tolerance[style] or AimLogic.Tolerance.Weapons
	local id = AimLogic.alongLine(ox, oz, dx, dz, candidates, range, tolerance)
	if id == nil and finite(ax) and finite(az) then
		id = AimLogic.nearPoint(ox, oz, ax :: number, az :: number, candidates, range, AimLogic.PointSlack)
	end
	return id
end

-- Dónde acaba un golpe que no da a nadie: Armas al final de su alcance; Magia donde
-- apuntabas (sin pasar del alcance); Puños y Guerrero, un poco delante. Distancia desde el
-- origen.
function AimLogic.missDistance(style: string, aimDistance: number, range: number): number
	if style == "Fists" or style == "Warrior" then
		return math.min(range, 3)
	elseif style == "Magic" then
		return math.clamp(if finite(aimDistance) then aimDistance else range, 2, range)
	end
	return range
end

return AimLogic
