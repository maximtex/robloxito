-- Lógica pura de zonas (sin APIs de Roblox) para poder probarla fuera de Studio.
-- La usa ZoneService, que añade las comprobaciones del mundo (datos cargados,
-- distancia al portal) y el viaje.

local ZoneLogic = {}

export type ProfileLike = { Energy: number, PetData: { UnlockedZones: { string } } }
export type Codes = { [string]: string }

function ZoneLogic.isUnlocked(profile: ProfileLike, zoneConfig, zoneId: string): boolean
	local zone = zoneConfig.Zones[zoneId]
	if not zone then
		return false
	end
	if (zone.UnlockCost or 0) <= 0 then
		return true
	end
	return table.find(profile.PetData.UnlockedZones, zoneId) ~= nil
end

-- Renacimientos que pide una zona además de su precio (0 si ninguno).
function ZoneLogic.requiredRebirths(zoneConfig, zoneId: string): number
	local zone = zoneConfig.Zones[zoneId]
	local required = zone and zone.RequiredRebirths
	return if type(required) == "number" and required > 0 then math.floor(required) else 0
end

-- Desbloquea una zona cobrando su precio UNA vez. Si ya estaba desbloqueada no cobra
-- (AlreadyUnlocked), de modo que repetir la solicitud nunca cobra dos veces.
-- `rebirths`: renacimientos del jugador (algunas zonas los piden: RebirthLocked, sin cobrar).
-- Devuelve el código y, si falta energía, cuánta falta (o cuántos renacimientos faltan).
function ZoneLogic.unlock(profile: ProfileLike, zoneConfig, zoneId: string, codes: Codes, rebirths: number?): (string, number?)
	local zone = zoneConfig.Zones[zoneId]
	if not zone then
		return codes.InvalidRequest, nil
	end
	if ZoneLogic.isUnlocked(profile, zoneConfig, zoneId) then
		return codes.AlreadyUnlocked, nil
	end
	local required = ZoneLogic.requiredRebirths(zoneConfig, zoneId)
	local have = if type(rebirths) == "number" and rebirths == rebirths then math.max(0, math.floor(rebirths)) else 0
	if have < required then
		return codes.RebirthLocked, required - have
	end
	local cost = zone.UnlockCost
	if profile.Energy < cost then
		return codes.InsufficientEnergy, math.ceil(cost - profile.Energy)
	end
	profile.Energy -= cost
	table.insert(profile.PetData.UnlockedZones, zoneId)
	return codes.Success, nil
end

return ZoneLogic
