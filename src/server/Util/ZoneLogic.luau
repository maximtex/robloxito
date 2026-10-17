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

-- Desbloquea una zona cobrando su precio UNA vez. Si ya estaba desbloqueada no cobra
-- (AlreadyUnlocked), de modo que repetir la solicitud nunca cobra dos veces.
-- Devuelve el código y, si falta energía, cuánta falta.
function ZoneLogic.unlock(profile: ProfileLike, zoneConfig, zoneId: string, codes: Codes): (string, number?)
	local zone = zoneConfig.Zones[zoneId]
	if not zone then
		return codes.InvalidRequest, nil
	end
	if ZoneLogic.isUnlocked(profile, zoneConfig, zoneId) then
		return codes.AlreadyUnlocked, nil
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
