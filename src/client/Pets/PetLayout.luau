-- Posiciones de las mascotas detrás del jugador (lógica pura, sin APIs de Roblox).
-- Garantiza que:
-- - dos mascotas nunca se solapan (separación >= suma de radios + GAP);
-- - ninguna queda dentro del jugador (distancia >= radio del jugador + su radio + GAP).
-- Cada hueco se expresa como { X = desplazamiento lateral, Z = distancia hacia atrás }.

local PetLayout = {}

PetLayout.GAP = 0.6
PetLayout.PLAYER_RADIUS = 1.6
PetLayout.ARC = 0.15 -- las de los lados se retrasan un poco: forma de abanico

export type Slot = { X: number, Z: number }

function PetLayout.slots(radii: { number }): { Slot }
	local count = #radii
	local slots: { Slot } = {}
	if count == 0 then
		return slots
	end

	-- Distancia hacia atrás común: la mascota más grande cabe sin tocar al jugador.
	local largest = 0
	for _, radius in radii do
		largest = math.max(largest, radius)
	end
	local back = PetLayout.PLAYER_RADIUS + largest + PetLayout.GAP + 0.6

	-- Laterales encadenados según el tamaño de cada vecina, y luego centrados.
	local laterals = { 0 }
	for index = 2, count do
		laterals[index] = laterals[index - 1] + radii[index - 1] + radii[index] + PetLayout.GAP
	end
	local center = (laterals[1] + laterals[count]) / 2

	for index = 1, count do
		local lateral = laterals[index] - center
		slots[index] = { X = lateral, Z = back + math.abs(lateral) * PetLayout.ARC }
	end
	return slots
end

-- Distancia mínima (en horizontal) entre el centro del jugador y una mascota.
function PetLayout.minDistanceFromPlayer(radius: number): number
	return PetLayout.PLAYER_RADIUS + radius + PetLayout.GAP
end

return PetLayout
