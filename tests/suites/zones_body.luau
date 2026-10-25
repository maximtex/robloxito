-- Zonas: ZoneLogic (desbloqueo con precio y renacimientos, sin cobrar dos veces) y la
-- coherencia de todo lo que depende de cada zona (portales, enemigos, huevos y mascotas,
-- personajes de las aventuras, misiones y paisaje), con la Caldera de Brasas incluida.

local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end

local Codes = Constants.PurchaseCodes
-- Por defecto con los jefes ya derrotados (el requisito del jefe se prueba aparte)
local function profile(energy, zones, bosses)
	return { Money = energy, Energy = 0, PetData = { UnlockedZones = zones or {}, Bosses = bosses or { ForestWarden = 1, AmethystColossus = 1 } } }
end

print("-- 1. Desbloqueo")
local caldera = ZoneConfig.Zones.EmberCaldera
check("la Caldera existe y cuesta 💰", caldera ~= nil and caldera.UnlockCost > 0)
check("los renacimientos que pide cada zona salen de su configuración", ZoneLogic.requiredRebirths(ZoneConfig, "EmberCaldera") == (caldera.RequiredRebirths or 0))
check("el bosque y el valle no piden renacimientos", ZoneLogic.requiredRebirths(ZoneConfig, "Forest") == 0 and ZoneLogic.requiredRebirths(ZoneConfig, "CrystalValley") == 0)

-- Ahora la Caldera no pide renacimientos (RequiredRebirths = 0: la abre el jefe del Valle),
-- pero el requisito sigue funcionando: se prueba con una copia que pide 3.
local GatedConfig = table.clone(ZoneConfig)
GatedConfig.Zones = table.clone(ZoneConfig.Zones)
GatedConfig.Zones.EmberCaldera = table.clone(caldera)
GatedConfig.Zones.EmberCaldera.RequiredRebirths = 3
check("con RequiredRebirths = 3 la Caldera pide 3", ZoneLogic.requiredRebirths(GatedConfig, "EmberCaldera") == 3)

local p = profile(1e9)
local code, missing = ZoneLogic.unlock(p, GatedConfig, "EmberCaldera", Codes, 2)
check("con 2 renacimientos: RebirthLocked, falta 1 y no cobra", code == Codes.RebirthLocked and missing == 1 and p.Money == 1e9 and #p.PetData.UnlockedZones == 0)
code, missing = ZoneLogic.unlock(p, GatedConfig, "EmberCaldera", Codes, nil)
check("sin dato de renacimientos cuenta como 0", code == Codes.RebirthLocked and missing == 3)
code = ZoneLogic.unlock(p, GatedConfig, "EmberCaldera", Codes, 0 / 0)
check("renacimientos NaN: bloqueado", code == Codes.RebirthLocked and p.Money == 1e9)
local poor = profile(caldera.UnlockCost - 10)
code, missing = ZoneLogic.unlock(poor, GatedConfig, "EmberCaldera", Codes, 3)
check("con 3 renacimientos pero sin 💰: InsufficientMoney (faltan 10)", code == Codes.InsufficientMoney and missing == 10 and poor.Money == caldera.UnlockCost - 10)
code = ZoneLogic.unlock(p, GatedConfig, "EmberCaldera", Codes, 3)
check("con 3 renacimientos y 💰: Success y cobra una vez", code == Codes.Success and p.Money == 1e9 - caldera.UnlockCost and table.find(p.PetData.UnlockedZones, "EmberCaldera") ~= nil)
code = ZoneLogic.unlock(p, GatedConfig, "EmberCaldera", Codes, 0)
check("ya desbloqueada: AlreadyUnlocked sin cobrar (aunque luego tenga menos renacimientos)", code == Codes.AlreadyUnlocked and p.Money == 1e9 - caldera.UnlockCost)
check("desbloqueada se puede usar (isUnlocked)", ZoneLogic.isUnlocked(p, ZoneConfig, "EmberCaldera") and not ZoneLogic.isUnlocked(profile(0), ZoneConfig, "EmberCaldera"))
code = ZoneLogic.unlock(profile(1e9), ZoneConfig, "Lava", Codes, 99)
check("zona inventada: InvalidRequest", code == Codes.InvalidRequest)
local valley = profile(ZoneConfig.Zones.CrystalValley.UnlockCost + 5000)
code = ZoneLogic.unlock(valley, ZoneConfig, "CrystalValley", Codes)
check("el Valle sigue igual sin renacimientos", code == Codes.Success and valley.Money == 5000)
local noBoss = profile(1e9, nil, {})
code = ZoneLogic.unlock(noBoss, ZoneConfig, "CrystalValley", Codes)
check("sin derrotar al Guardián del Bosque: BossLocked y no cobra", ZoneConfig.Zones.CrystalValley.RequiredBoss == "ForestWarden" and code == Codes.BossLocked and noBoss.Money == 1e9 and #noBoss.PetData.UnlockedZones == 0)
noBoss.PetData.Bosses.ForestWarden = 1
check("tras derrotarlo ya se abre", ZoneLogic.unlock(noBoss, ZoneConfig, "CrystalValley", Codes) == Codes.Success)
check("la Caldera pide al Coloso de Amatista", ZoneConfig.Zones.EmberCaldera.RequiredBoss == "AmethystColossus" and ZoneLogic.bossDefeated(profile(0, nil, { ForestWarden = 3 }), ZoneConfig, "EmberCaldera") == false)
check("una partida antigua sin jefes guardados: bloqueada, nunca error", ZoneLogic.unlock({ Energy = 1e9, PetData = { UnlockedZones = {} } }, ZoneConfig, "CrystalValley", Codes) == Codes.BossLocked)

print("-- 2. Mapa y portales")
local zoneIds = {}
for zoneId in ZoneConfig.Zones do
	table.insert(zoneIds, zoneId)
end
local apartOk = true
for i = 1, #zoneIds do
	for j = i + 1, #zoneIds do
		local a, b = ZoneConfig.Zones[zoneIds[i]], ZoneConfig.Zones[zoneIds[j]]
		-- Los mapas van pegados en +Z (cuadrados de 2·Radius), sin solaparse.
		if (a.Center - b.Center).Magnitude < a.Radius + b.Radius - 0.01 then
			apartOk = false
			print("  se solapan: " .. zoneIds[i] .. " y " .. zoneIds[j])
		end
	end
end
check("las zonas no se solapan (cada mapa en su franja)", apartOk)
local portalsOk, reach = true, {}
for portalId, portal in ZoneConfig.Portals do
	if not ZoneConfig.Zones[portal.Zone] or not ZoneConfig.Zones[portal.Target] or portal.Zone == portal.Target then
		portalsOk = false
		print("  portal mal definido: " .. portalId)
	end
	reach[portal.Target] = true
end
check("cada portal está en una zona y lleva a otra", portalsOk)
local reachOk = true
for zoneId in ZoneConfig.Zones do
	reachOk = reachOk and (zoneId == ZoneConfig.DefaultZone or reach[zoneId] == true)
end
check("a todas las zonas se llega por algún portal", reachOk)
-- Sin portales de vuelta: los mapas están pegados y el portal es un paso en el muro, así que
-- se vuelve andando. Cada portal debe estar en la frontera con la zona a la que lleva.
local backOk = true
for portalId, portal in ZoneConfig.Portals do
	local from, to = ZoneConfig.Zones[portal.Zone], ZoneConfig.Zones[portal.Target]
	if from and to then
		local touching = math.abs((from.Center - to.Center).Magnitude - (from.Radius + to.Radius)) < 0.01
		local onEdge = math.abs(portal.Offset.Y) >= from.Radius - 0.01 or math.abs(portal.Offset.X) >= from.Radius - 0.01
		if not (touching and onEdge) then
			backOk = false
			print("  " .. portalId .. " no está en la frontera entre sus zonas")
		end
	end
end
check("cada portal está en la frontera con su destino (se vuelve andando)", backOk)
check("el portal de la Caldera está en el Valle (Bosque -> Valle -> Caldera)", ZoneConfig.Portals.CalderaPortal.Zone == "CrystalValley" and ZoneConfig.Portals.CalderaPortal.Target == "EmberCaldera")

print("-- 3. Enemigos")
local enemiesOk = true
for zoneId, zone in EnemyConfig.Zones do
	if not ZoneConfig.Zones[zoneId] then
		enemiesOk = false
		print("  zona de enemigos sin zona: " .. zoneId)
	end
	for _, spawn in zone.Spawns do
		local def = EnemyConfig.Types[spawn.Type]
		if not def then
			enemiesOk = false
			print("  tipo desconocido: " .. tostring(spawn.Type))
		end
		for _, safe in zone.SafeZones do
			if (spawn.Offset - safe.Center).Magnitude < safe.Radius then
				enemiesOk = false
				print("  aparece dentro de una zona protegida: " .. tostring(spawn.Type))
			end
		end
	end
	if zone.Boss and EnemyConfig.Types[zone.Boss.Type].Kind ~= "Boss" then
		enemiesOk = false
	end
end
check("cada zona de enemigos existe, sus tipos existen y nadie aparece en zona protegida", enemiesOk)
local safeOk = false
for _, safe in EnemyConfig.Zones.CrystalValley.SafeZones do
	safeOk = safeOk or (safe.Center - ZoneConfig.Portals.CalderaPortal.Offset).Magnitude < 1
end
check("el portal de la Caldera es zona protegida en el Valle", safeOk)
local t = EnemyConfig.Types
check("la Caldera es más dura y da más que el Valle", t.Cinderling.MaxHealth > t.Shardling.MaxHealth and t.MagmaGolem.MaxHealth > t.GeodeGolem.MaxHealth
	and t.CalderaTitan.MaxHealth > t.AmethystColossus.MaxHealth and t.CalderaTitan.Reward > t.AmethystColossus.Reward and t.Cinderling.Reward > t.Shardling.Reward)

print("-- 4. Huevos y mascotas")
local eggsOk = true
for eggId, egg in EggConfig.Eggs do
	if egg.Enabled ~= false then
		local total = 0
		for _, chance in egg.Chances do
			total += chance.Chance
			if not PetConfig.Pets[chance.PetId] then
				eggsOk = false
				print("  mascota desconocida en " .. eggId .. ": " .. chance.PetId)
			end
		end
		if total ~= 100 then
			eggsOk = false
			print("  probabilidades de " .. eggId .. " suman " .. total)
		end
		local zoneId = egg.Zone or ZoneConfig.DefaultZone
		if not ZoneConfig.Zones[zoneId] or (egg.RequiredZone and not ZoneConfig.Zones[egg.RequiredZone]) then
			eggsOk = false
		end
	end
end
check("cada huevo suma 100 %, sus mascotas existen y su zona también", eggsOk)
local function meanBonus(eggId)
	local total = 0
	for _, chance in EggConfig.Eggs[eggId].Chances do
		total += chance.Chance / 100 * (PetConfig.Pets[chance.PetId].Multiplier - 1)
	end
	return total
end
check(("Huevo de Magma: valor medio mayor que el de Cristal (%.0f %% > %.0f %%)"):format(meanBonus("MagmaEgg") * 100, meanBonus("CrystalEgg") * 100), meanBonus("MagmaEgg") > meanBonus("CrystalEgg"))
check("el Huevo de Magma solo se compra con la Caldera desbloqueada", EggConfig.Eggs.MagmaEgg.Zone == "EmberCaldera" and EggConfig.Eggs.MagmaEgg.RequiredZone == "EmberCaldera")
local garden = EggConfig.Gardens.EmberCaldera
check("la Forja de Huevos tiene su estilo en el paisaje", garden ~= nil and LandscapeConfig.Gardens[garden.Style] ~= nil)

print("-- 5. Aventuras y misiones")
local smith = AdventureConfig.Npcs.Smith
check("Brasa vive en la Caldera y da el Corazón de Magma", smith ~= nil and smith.Zone == "EmberCaldera" and AdventureConfig.Amulets[smith.Amulet] ~= nil)
local itemsOk = true
for itemId, item in AdventureConfig.Items do
	itemsOk = itemsOk and ZoneConfig.Zones[item.Zone] ~= nil and AdventureConfig.ItemKinds[item.Kind] ~= nil
end
check("cada objeto perdido está en una zona y tiene su aspecto", itemsOk)
local killOk = true
for npcId, npc in AdventureConfig.Npcs do
	for _, step in npc.Steps do
		if step.Goal.Type == "Kill" then
			for _, enemyId in step.Goal.Enemies do
				killOk = killOk and EnemyConfig.Types[enemyId] ~= nil
			end
		end
	end
end
check("las misiones de derrotar piden enemigos que existen", killOk)
local slotOk = AdventureConfig.SlotStories ~= nil and table.find(AdventureConfig.SlotStories, "Smith") == nil and #AdventureConfig.SlotStories == 4
check("la 2.ª ranura sigue abriéndose con las cuatro historias de antes (no con la Caldera)", slotOk)
local questsOk = true
for _, list in { QuestConfig.Missions, QuestConfig.Daily } do
	for _, def in list do
		if def.RequiresZone and not ZoneConfig.Zones[def.RequiresZone] then
			questsOk = false
		end
		if def.Goal.Zone and not ZoneConfig.Zones[def.Goal.Zone] then
			questsOk = false
		end
	end
end
check("las misiones solo nombran zonas que existen", questsOk)

print("-- 6. Paisaje de la Caldera")
check("la Caldera tiene paisaje propio con su zona", LandscapeConfig.Caldera ~= nil and LandscapeConfig.Caldera.Zone == "EmberCaldera")
local volcano = CalderaConfig.Volcano
check("el volcán queda al fondo, fuera del área de juego", volcano.Distance - volcano.BaseRadius * 0.3 > LandscapeConfig.Caldera.BoundaryRadius)
local lake = CalderaConfig.LavaLake
local lakeOk = (lake.Center - EggConfig.Gardens.EmberCaldera.Center).Magnitude > lake.Radius + EggConfig.Gardens.EmberCaldera.Radius + 6
for _, spawn in EnemyConfig.Zones.EmberCaldera.Spawns do
	lakeOk = lakeOk and (spawn.Offset - lake.Center).Magnitude > lake.Radius + 4
end
check("el lago de lava no pisa la Forja ni los puntos de aparición", lakeOk)

print("-- 7. Portales (diseño Portal del Renacimiento)")
local kinds = { Box = true, Ball = true, Glyph = true, Crystal = true, Disc = true, Rod = true, Frustum = true, Pyramid = true }
local designOk = #PortalDesign.Parts >= 200
for _, piece in PortalDesign.Parts do
	designOk = designOk and kinds[piece[1]] == true and type(piece[2]) == "string" and type(piece[3]) == "string"
end
check(("el diseño del portal tiene sus %d piezas y formas conocidas"):format(#PortalDesign.Parts), designOk)
local reach = PortalDesign.Footprint * ZoneConfig.PortalScale
check(("el portal cabe en su radio (%.1f de %.1f studs)"):format(reach, ZoneConfig.PortalRadius), reach <= ZoneConfig.PortalRadius)
local roomOk, guardOk = true, true
for portalId, portal in ZoneConfig.Portals do
	local zone = ZoneConfig.Zones[portal.Zone]
	local arrival = Vector2.new(zone.Arrival.X, zone.Arrival.Z)
	if (arrival - portal.Offset).Magnitude < ZoneConfig.PortalRadius + 1 then
		roomOk = false
		print("  la llegada de " .. portal.Zone .. " cae encima de " .. portalId)
	end
	for otherId, other in ZoneConfig.Portals do
		if otherId ~= portalId and other.Zone == portal.Zone and (other.Offset - portal.Offset).Magnitude < ZoneConfig.PortalRadius * 2 then
			roomOk = false
			print("  se pisan " .. portalId .. " y " .. otherId)
		end
	end
	local guarded = false
	for _, safe in EnemyConfig.Zones[portal.Zone].SafeZones do
		guarded = guarded or ((safe.Center - portal.Offset).Magnitude < 1 and safe.Radius >= ZoneConfig.PortalRadius)
	end
	if not guarded then
		guardOk = false
		print("  sin zona protegida: " .. portalId)
	end
end
check("las llegadas quedan fuera de los portales y los portales no se pisan", roomOk)
check("cada portal entero es zona protegida de los enemigos", guardOk)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
