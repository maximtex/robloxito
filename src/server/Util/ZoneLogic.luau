-- Lógica pura de zonas (sin APIs de Roblox) para poder probarla fuera de Studio.
-- La usa ZoneService, que añade las comprobaciones del mundo (datos cargados,
-- distancia al portal) y el viaje.

local ZoneLogic = {}

export type ProfileLike = { Money: number, PetData: { UnlockedZones: { string }, Bosses: { [string]: number }? } }
export type Codes = { [string]: string }

-- Las zonas sin precio están abiertas, salvo las que piden un jefe (RequiredBoss, como el
-- Mundo 2): esas se abren solas al derrotarlo (BossRewardService la apunta en UnlockedZones).
function ZoneLogic.isUnlocked(profile: ProfileLike, zoneConfig, zoneId: string): boolean
	local zone = zoneConfig.Zones[zoneId]
	if not zone then
		return false
	end
	if table.find(profile.PetData.UnlockedZones, zoneId) ~= nil then
		return true
	end
	if (zone.UnlockCost or 0) <= 0 then
		return zone.RequiredBoss == nil or ZoneLogic.bossDefeated(profile, zoneConfig, zoneId)
	end
	return false
end

-- El valor más alto de `values` ({ [zoneId] = número }) entre las zonas abiertas del jugador
-- (`fallback` si no hay ninguno). Lo usan los premios que crecen con el avance: factores de
-- misiones (QuestConfig.ZoneFactor) y 💰 por minuto (bestMoneyPerMinute).
function ZoneLogic.bestValue(profile: ProfileLike, zoneConfig, values: { [string]: number }, fallback: number): number
	local best = nil
	for zoneId, value in values do
		if type(value) == "number" and value == value and value < math.huge and ZoneLogic.isUnlocked(profile, zoneConfig, zoneId) then
			best = if best then math.max(best, value) else value
		end
	end
	return best or fallback
end

-- 💰 por minuto de la mejor zona abierta (ZoneConfig.Zones.*.MoneyPerMinute).
function ZoneLogic.bestMoneyPerMinute(profile: ProfileLike, zoneConfig): number
	local values = {}
	for zoneId, zone in zoneConfig.Zones do
		values[zoneId] = zone.MoneyPerMinute
	end
	return ZoneLogic.bestValue(profile, zoneConfig, values, 0)
end

-- Zonas sin precio que abre este jefe al derrotarlo (las que aún no estaban en la lista se
-- añaden a UnlockedZones). Devuelve las que se acaban de abrir.
function ZoneLogic.unlockByBoss(profile: ProfileLike, zoneConfig, bossType: string): { string }
	local opened = {}
	for zoneId, zone in zoneConfig.Zones do
		if zone.RequiredBoss == bossType and (zone.UnlockCost or 0) <= 0 and not table.find(profile.PetData.UnlockedZones, zoneId) then
			table.insert(profile.PetData.UnlockedZones, zoneId)
			table.insert(opened, zoneId)
		end
	end
	table.sort(opened)
	return opened
end

-- Renacimientos que pide una zona además de su precio (0 si ninguno).
function ZoneLogic.requiredRebirths(zoneConfig, zoneId: string): number
	local zone = zoneConfig.Zones[zoneId]
	local required = zone and zone.RequiredRebirths
	return if type(required) == "number" and required > 0 then math.floor(required) else 0
end

-- ¿Ha derrotado ya al jefe que pide la zona (RequiredBoss)? true si no pide ninguno.
function ZoneLogic.bossDefeated(profile: ProfileLike, zoneConfig, zoneId: string): boolean
	local zone = zoneConfig.Zones[zoneId]
	local boss = zone and zone.RequiredBoss
	if not boss then
		return true
	end
	local bosses = profile.PetData.Bosses
	return type(bosses) == "table" and (bosses[boss] or 0) > 0
end

-- Desbloquea una zona cobrando su precio UNA vez. Si ya estaba desbloqueada no cobra
-- (AlreadyUnlocked), de modo que repetir la solicitud nunca cobra dos veces.
-- Sin derrotar al jefe de la anterior: BossLocked, sin cobrar.
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
	if not ZoneLogic.bossDefeated(profile, zoneConfig, zoneId) then
		return codes.BossLocked, nil
	end
	local cost = zone.UnlockCost
	-- Los portales se pagan con 💰 (economía 2: EconomyConfig)
	if (profile.Money or 0) < cost then
		return codes.InsufficientMoney, math.ceil(cost - (profile.Money or 0))
	end
	profile.Money -= cost
	table.insert(profile.PetData.UnlockedZones, zoneId)
	return codes.Success, nil
end

return ZoneLogic
