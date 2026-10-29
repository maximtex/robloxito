local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end

local B, WALL = 8, 4
local function edge(v)
	return (v - 4) % 8 == 0
end
local function rectOK(r)
	return edge(r.MinX) and edge(r.MaxX) and edge(r.MinZ) and edge(r.MaxZ) and r.MaxX > r.MinX and r.MaxZ > r.MinZ
end
local function overlap(a, b)
	return a.MinX < b.MaxX and b.MinX < a.MaxX and a.MinZ < b.MaxZ and b.MinZ < a.MaxZ
end
local function inside(r, x, z, margin)
	return x > r.MinX + margin and x < r.MaxX - margin and z > r.MinZ + margin and z < r.MaxZ - margin
end
local function dist(ax, az, bx, bz)
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

local base = GeneratorConfig.Position
local rooms, corridors, gates = CaveConfig.Rooms, CaveConfig.Corridors, CaveConfig.Gates

print("-- Las cinco mazmorras")
local orderOK = #CaveConfig.Order == 5 and CaveConfig.Order[1] == "Forest" and CaveConfig.Order[4] == "FrozenTundra" and CaveConfig.Order[5] == "DividedLands"
local zonesSeen = {}
for _, caveId in CaveConfig.Order do
	local cave = CaveConfig.Caves[caveId]
	orderOK = orderOK and cave ~= nil and cave.Id == caveId and ZoneConfig.Zones[cave.Zone] ~= nil and not zonesSeen[cave.Zone]
		and type(cave.Name) == "string" and type(cave.Icon) == "string" and type(cave.Subtitle) == "string" and cave.Theme ~= nil and cave.Theme.Tint ~= nil
	zonesSeen[cave.Zone] = true
end
check("una mazmorra por zona (Bosque, Valle, Caldera, Tundra y Tierras Divididas), con nombre, icono y colores", orderOK)
check("listas planas: 3 salas, 2 pasillos, 2 puertas y 2 salidas por cueva; las del Bosque primero",
	#rooms == 15 and #corridors == 10 and #gates == 10 and #CaveConfig.Exits == 10 and rooms[1].Cave == "Forest" and rooms[4].Cave == "CrystalValley" and gates[3].Cave == "CrystalValley" and gates[5].Cave == "EmberCaldera" and gates[7].Cave == "FrozenTundra" and rooms[10].Cave == "FrozenTundra" and gates[9].Cave == "DividedLands" and rooms[13].Cave == "DividedLands")
local apartOK = true
for i = 1, #rooms do
	for j = i + 1, #rooms do
		apartOK = apartOK and not overlap(rooms[i].Rect, rooms[j].Rect)
	end
	for _, corridor in corridors do
		apartOK = apartOK and not overlap(rooms[i].Rect, corridor.Rect)
	end
end
check("ninguna sala ni pasillo de ninguna cueva se pisa", apartOK)
local harderOK = true
for index = 2, #CaveConfig.Order do
	local before = CaveConfig.Caves[CaveConfig.Order[index - 1]].Strength
	local now = CaveConfig.Caves[CaveConfig.Order[index]].Strength
	harderOK = harderOK and now.Health > before.Health and now.Damage > before.Damage and now.Reward > before.Reward
end
check("cada mazmorra es más dura que la anterior (vida, daño y botín)", harderOK)

for _, caveId in CaveConfig.Order do
	local cave = CaveConfig.Caves[caveId]
	local zone = ZoneConfig.Zones[cave.Zone]
	local originX, originZ = base.X + zone.Center.X, base.Z + zone.Center.Y
	local first = cave.FirstRoom
	local localRooms = cave.Rooms
	local function global(localIndex)
		return first + localIndex - 1
	end
	print(("-- %s %s (%s)"):format(cave.Icon, cave.Name, caveId))

	-- Salas y pasillos
	local shapeOK, heightOK, namesOK = true, true, true
	for index, room in localRooms do
		shapeOK = shapeOK and rectOK(room.Rect) and room.Cave == caveId and room.Local == index and rooms[global(index)] == room
		heightOK = heightOK and room.Height % B == 0 and room.Height >= 32
		namesOK = namesOK and type(room.Name) == "string" and type(room.Label) == "string" and type(room.Text) == "string" and #room.Crystal >= 1 and #room.Mushroom >= 1
		for _, sky in room.Skylights or {} do
			if not (rectOK(sky) and inside(room.Rect, (sky.MinX + sky.MaxX) / 2, (sky.MinZ + sky.MaxZ) / 2, WALL)) then
				shapeOK = false
				print("  claraboya fuera de la sala " .. index)
			end
		end
	end
	check("tres salas: los pequeños, los medianos y el altar", #localRooms == 3 and localRooms[3].Altar == true and not localRooms[1].Altar and not localRooms[2].Altar)
	check("salas en bordes de bloque (8k ± 4) con sus claraboyas dentro, techos enteros y altos, y sus nombres", shapeOK and heightOK and namesOK)
	local doorsOK, linkedOK = true, true
	local reached = { [1] = true }
	for _, corridor in cave.Corridors do
		local c = corridor.Rect
		doorsOK = doorsOK and rectOK(c) and corridor.Height % B == 0
		for _, roomIndex in { corridor.From, corridor.To } do
			local room = localRooms[roomIndex]
			local r = room and room.Rect
			local touches = false
			if r then
				if c.MaxX == r.MinX or c.MinX == r.MaxX then
					touches = c.MinZ >= r.MinZ + B and c.MaxZ <= r.MaxZ - B
				elseif c.MaxZ == r.MinZ or c.MinZ == r.MaxZ then
					touches = c.MinX >= r.MinX + B and c.MaxX <= r.MaxX - B
				end
				touches = touches and corridor.Height < room.Height
			end
			if not touches then
				doorsOK = false
				print(("  el pasillo %d-%d no entra bien en la sala %d"):format(corridor.From, corridor.To, roomIndex))
			end
		end
		if reached[corridor.From] then
			reached[corridor.To] = true
		end
	end
	for index in localRooms do
		linkedOK = linkedOK and reached[index] == true
	end
	check("cada pasillo entra por un lado de sus dos salas, con dintel, y se llega a todas (1 -> 2 -> 3)", doorsOK and linkedOK)

	-- Lejos del mapa y cuenta como su zona
	local minX, maxX, minZ, maxZ = CaveLogic.bounds(caveId)
	local farOK = true
	for otherId, other in ZoneConfig.Zones do
		local cx, cz = base.X + other.Center.X, base.Z + other.Center.Y
		local half = (other.Radius or 160) + 12
		if minX <= cx + half and maxX >= cx - half and minZ <= cz + half and maxZ >= cz - half then
			farOK = false
			print("  la cueva pisa el cuadrado de " .. otherId)
		end
		local nearestX = math.clamp(cx, minX, maxX)
		local nearestZ = math.clamp(cz, minZ, maxZ)
		if dist(nearestX, nearestZ, cx, cz) < 500 then
			farOK = false
			print("  la cueva está demasiado cerca de " .. otherId)
		end
	end
	local midRoom = localRooms[2].Rect
	local foundId, found = CaveLogic.caveAt((midRoom.MinX + midRoom.MaxX) / 2, (midRoom.MinZ + midRoom.MaxZ) / 2)
	check("fuera de los cuadrados de las zonas y lejos de todo; caveAt la reconoce", farOK and foundId == caveId and found == cave)
	-- Misma forma que la del Bosque, movida en Z lo que se separan los centros de las zonas
	-- (redondeado a bordes de bloque: el Mundo 2 no cae en múltiplos de 8)
	local forest = CaveConfig.Caves.Forest
	local forestZone = ZoneConfig.Zones[forest.Zone]
	local dz = B * math.floor((zone.Center.Y - forestZone.Center.Y) / B + 0.5)
	local sameOK = true
	for index, room in localRooms do
		local f = forest.Rooms[index].Rect
		sameOK = sameOK and room.Rect.MinX == f.MinX and room.Rect.MaxX == f.MaxX and room.Rect.MinZ == f.MinZ + dz and room.Rect.MaxZ == f.MaxZ + dz
	end
	check("la misma cueva que la del Bosque, en su sitio", sameOK)

	-- Entrar y salir
	local trigger = cave.Entrance.Trigger
	local out = cave.Entrance.Exit
	-- Todas las bocas son montículos; la del Bosque está en el Bosque de Espinas (EntranceZone)
	local mouthZoneId = cave.EntranceZone or cave.Zone
	local mouthZone = ZoneConfig.Zones[mouthZoneId]
	do
		local originX, originZ = base.X + mouthZone.Center.X, base.Z + mouthZone.Center.Y
		local mound = cave.Entrance.Mound
		local front = mound.Front
		local facing = mound.Facing
		-- El túnel va del frente hacia atrás (contra Facing); el disparador, al fondo del túnel
		local tunnelOK = facing.X < 0 and trigger.MinX >= front.X + B - 0.01 and trigger.MaxX <= front.X + mound.Depth - B + 0.01
			and trigger.MinZ >= front.Z - mound.Width / 2 - 0.01 and trigger.MaxZ <= front.Z + mound.Width / 2 + 0.01 and trigger.Height <= mound.Height
		local inZone = math.abs(front.X - originX) + mound.Depth < 160 and math.abs(front.Z - originZ) + mound.Span / 2 < 160
		check("la boca (montículo) está en su zona y te lleva dentro desde el fondo del túnel", tunnelOK and inZone)
		check("al salir apareces delante de la boca, mirando hacia fuera", out.Position.X < front.X - 6 and math.abs(out.Position.Z - front.Z) < 1 and out.Facing.X < 0)
		local guarded = false
		for _, safe in EnemyConfig.Zones[mouthZoneId].SafeZones do
			if dist(originX + safe.Center.X, originZ + safe.Center.Y, out.Position.X, out.Position.Z) + 2 <= safe.Radius then
				guarded = true
			end
		end
		check("delante de la boca es zona segura", guarded)
		-- Junto a la puerta de la zona siguiente (pruebas con amigos), si su zona tiene una
		for _, portal in ZoneConfig.Portals do
			if portal.Zone == mouthZoneId and portal.Offset.Y > 0 then
				local gateDist = dist(front.X, front.Z, originX + portal.Offset.X, originZ + portal.Offset.Y)
				check(("la boca está junto a la puerta de %s (%.0f studs)"):format(portal.Target, gateDist), gateDist <= 60)
			end
		end
	end
	local arrival = cave.Arrival.Position
	check("llegas a la sala 1, lejos de sus paredes", CaveLogic.roomAt(arrival.X, arrival.Z) == global(1) and inside(localRooms[1].Rect, arrival.X, arrival.Z, WALL + 4))
	local exitsOK, bounceOK, roomsWithExit = true, true, {}
	for index, exit in CaveConfig.Exits do
		if exit.Cave ~= caveId then
			continue
		end
		local room = rooms[exit.Room]
		local r = room and room.Rect
		local roomIndex = CaveLogic.roomAt(exit.Position.X, exit.Position.Z)
		local nearWall = r and math.min(exit.Position.X - (r.MinX + WALL), (r.MaxX - WALL) - exit.Position.X, exit.Position.Z - (r.MinZ + WALL), (r.MaxZ - WALL) - exit.Position.Z) <= 2
		local ahead = r and inside(r, exit.Position.X + exit.Facing.X * 10, exit.Position.Z + exit.Facing.Z * 10, WALL)
		if not (room and room.Cave == caveId and roomIndex == exit.Room and nearWall and ahead) then
			exitsOK = false
			print("  portal de salida mal puesto: " .. index)
		end
		if dist(arrival.X, arrival.Z, exit.Position.X, exit.Position.Z) < CaveConfig.ExitRadius + 6 then
			bounceOK = false
		end
		roomsWithExit[room and room.Local or 0] = true
	end
	check("portales de salida pegados a una pared, en la sala 1 y en la del altar, y al llegar no rebotas", exitsOK and roomsWithExit[1] == true and roomsWithExit[3] == true and bounceOK and CaveLogic.exitAt(Vector3.new(arrival.X, 0, arrival.Z)) == nil)

	-- Los bichos de cada sala (los del mundo de su zona)
	local enemies = EnemyConfig.Zones[cave.Zone]
	local counts = { {}, {}, {} }
	local spawnsOK, corridorClear, arrivalClear, altarClear = true, true, true, true
	local altar = CaveLogic.altarCenter(caveId)
	for _, spawn in enemies.Spawns do
		local x, z = originX + spawn.Offset.X, originZ + spawn.Offset.Y
		local inId = CaveLogic.caveAt(x, z)
		if inId ~= nil and inId ~= caveId then
			spawnsOK = false
			print(("  %s de %s cae en otra cueva (%s)"):format(spawn.Type, cave.Zone, inId))
		end
		if inId == caveId then
			local roomIndex, room = CaveLogic.roomAt(x, z)
			local def = EnemyConfig.Types[spawn.Type]
			if not roomIndex then
				corridorClear = false
			else
				counts[room.Local][def.Kind] = (counts[room.Local][def.Kind] or 0) + 1
				if not inside(room.Rect, x, z, WALL + 4) then
					spawnsOK = false
					print(("  %s en (%d, %d) pegado a la pared"):format(spawn.Type, x, z))
				end
			end
			if dist(x, z, arrival.X, arrival.Z) < 24 then
				arrivalClear = false
			end
			if altar and dist(x, z, altar.X, altar.Y) < WaveConfig.Place.AreaRadius + def.LeashRange + 20 then
				altarClear = false
			end
		end
	end
	check(("sala 1: solo pequeños (%d)"):format(counts[1].Normal or 0), (counts[1].Normal or 0) >= 6 and counts[1].Strong == nil and counts[1].Boss == nil)
	check(("sala 2: los medianos (%d)"):format(counts[2].Strong or 0), (counts[2].Strong or 0) >= 4 and counts[2].Normal == nil and counts[2].Boss == nil)
	check("sala 3: sin bichos del mundo (solo las oleadas); ninguno junto a donde llegas ni en un pasillo", next(counts[3]) == nil and altarClear and arrivalClear and spawnsOK and corridorClear)
	local guarded = false
	for _, safe in enemies.SafeZones do
		if dist(originX + safe.Center.X, originZ + safe.Center.Y, arrival.X, arrival.Z) + 4 <= safe.Radius then
			guarded = true
		end
	end
	check("donde llegas es zona segura (no te atacan nada más entrar)", guarded)

	-- Oleadas del altar de su zona, dentro de la sala 3
	local placeOK, place = false, nil
	for _, settings in WaveConfig.Places do
		if settings.Zone == cave.Zone and settings.Cave and not settings.Practice then
			place = settings
		end
	end
	if place and altar then
		local px, pz = originX + place.Offset.X, originZ + place.Offset.Y
		placeOK = place.Cave == true and dist(px, pz, altar.X, altar.Y) < 1 and (place.LeashRadius or 0) >= 56 and (place.InsideRadius or 0) >= 56
	end
	local points = (place and place.SpawnPoints) or {}
	local pointsOk = #points >= 4 and altar ~= nil
	local altarRect = localRooms[3].Rect
	for _, point in points do
		local x, z = altar.X + point.X, altar.Y + point.Y
		if CaveLogic.roomAt(x, z) ~= global(3) or not inside(altarRect, x, z, WALL + 3) or dist(x, z, altar.X, altar.Y) < WaveConfig.Place.AreaRadius + 10 then
			pointsOk = false
			print(("  salida de oleada mal en (%d, %d)"):format(x, z))
		end
	end
	check("el altar de las oleadas de su zona está en la sala 3, con sus salidas por la sala", placeOK and pointsOk)

	-- Puertas
	local gatesOK = #cave.Gates == #cave.Corridors
	for index, gate in CaveConfig.Gates do
		if gate.Cave ~= caveId then
			continue
		end
		local corridor = corridors[gate.Corridor]
		local c = corridor and corridor.Rect
		local fromRoom = rooms[gate.Room]
		local width, height = CaveLogic.gateSize(index)
		local ok = corridor ~= nil and corridor.Cave == caveId and corridor.From == gate.Room and fromRoom ~= nil and fromRoom.Cave == caveId
			and gate.Position.X >= c.MinX and gate.Position.X <= c.MaxX and gate.Position.Z >= c.MinZ and gate.Position.Z <= c.MaxZ
			and CaveLogic.roomAt(gate.Position.X + gate.Facing.X * 8, gate.Position.Z + gate.Facing.Z * 8) == gate.Room
			and CaveLogic.roomAt(gate.Back.X, gate.Back.Z) == gate.Room and inside(fromRoom.Rect, gate.Back.X, gate.Back.Z, WALL + 2)
			and width == 16 and height == corridor.Height and gate.Kills >= 1 and type(gate.Opens) == "string" and type(gate.Enemies) == "string"
		if not ok then
			gatesOK = false
			print("  puerta mal puesta: " .. index)
		end
	end
	check("una puerta al principio de cada pasillo, mirando a la sala de antes", gatesOK)

	-- Lo diferente del Valle y la Caldera
	if caveId ~= "Forest" then
		local gate2 = cave.Gates[2]
		local spec = cave.MiniBoss
		local def = spec and EnemyConfig.Types[spec.Type]
		local p = spec and spec.Position
		local miniOK = gate2.MiniBoss == true and gate2.Kills == 1 and type(gate2.Ask) == "string" and def ~= nil and def.Kind == "Strong"
			and p ~= nil and CaveLogic.roomAt(p.X, p.Z) == global(2) and inside(localRooms[2].Rect, p.X, p.Z, WALL + 8) and spec.Health > 1 and spec.Scale > 1
		local bossHealth = EnemyConfig.Types[(enemies.Boss or {}).Type or ""] and EnemyConfig.Types[enemies.Boss.Type].MaxHealth or math.huge
		local miniHealth = def and def.MaxHealth * cave.Strength.Health * spec.Health or math.huge
		check(("mini-jefe en la sala 2 (%d de vida, el jefe %d): abre la puerta del altar"):format(miniHealth, bossHealth), miniOK and miniHealth < bossHealth)
		local traps = cave.Traps
		check("trampas: avisan antes, quitan una parte de la vida y no muy seguidas", traps ~= nil and traps.Warning >= 0.8 and traps.Damage > 0 and traps.Damage < 0.4 and traps.Interval[1] >= 3 and traps.Interval[2] >= traps.Interval[1] and traps.Radius >= 4)
		check("bichos élite en las salas", (cave.EliteChance or 0) > 0 and (cave.EliteChance or 0) < 1)
		check("más puerta que en el Bosque: más pequeños para abrir la sala 2", cave.Gates[1].Kills > CaveConfig.Caves.Forest.Gates[1].Kills)
	end
end

print("-- Élites")
local elite = EnemyConfig.Elite
check("los élite son más grandes, tienen más vida y dan más botín", elite.Scale > 1 and elite.Health > 1 and elite.Reward > 1 and elite.Damage >= 1 and elite.Color ~= nil)

print("-- Puertas (lógica)")
check("15 pequeños abren la Galería y 6 brutos el Altar", gates[1].Kills == 15 and gates[1].Room == 1 and gates[2].Kills == 6 and gates[2].Room == 2)
local progress = CaveLogic.sanitizeProgress(nil)
check("sin datos: todas cerradas y con un número por puerta (las de las cinco cuevas)", #progress == #gates and #progress == 10 and progress[1] == 0 and not CaveLogic.isOpen(progress, 1) and not CaveLogic.isOpen(progress, 4))
check("datos raros: se limpian y no pasan del tope", CaveLogic.sanitizeProgress({ 999, -3 })[1] == 15 and CaveLogic.sanitizeProgress({ 999, -3 })[2] == 0
	and CaveLogic.sanitizeProgress("x")[1] == 0 and CaveLogic.sanitizeProgress({ 0 / 0, 2.7 })[2] == 2 and CaveLogic.sanitizeProgress({ ["1"] = 4 })[1] == 4)
local old = CaveLogic.sanitizeProgress({ 15, 6 })
check("una partida de antes (solo la cueva del Bosque) conserva sus puertas y las nuevas empiezan cerradas", old[1] == 15 and old[2] == 6 and old[3] == 0 and old[10] == 0 and #old == 10)
check("atributo de ida y vuelta", CaveLogic.formatProgress({ 15, 3 }) == "15,3,0,0,0,0,0,0,0,0" and CaveLogic.parseProgress("15,3")[2] == 3 and CaveLogic.parseProgress(nil)[1] == 0 and CaveLogic.parseProgress("a,b")[1] == 0)
local function center(r)
	return (r.MinX + r.MaxX) / 2, (r.MinZ + r.MaxZ) / 2
end
local nestX, nestZ = center(rooms[1].Rect)
local galleryX, galleryZ = center(rooms[2].Rect)
local altarX, altarZ = center(rooms[3].Rect)
local counted, opened = 0, false
for _ = 1, 14 do
	local gate, justOpened = CaveLogic.countKill(progress, nestX, nestZ)
	counted += if gate == 1 then 1 else 0
	opened = opened or justOpened
end
check("cada pequeño de la sala 1 suma para la puerta 1 (14 aún no abren)", counted == 14 and progress[1] == 14 and not opened and not CaveLogic.isOpen(progress, 1))
local galleryEarly = CaveLogic.countKill(progress, galleryX, galleryZ)
check("los de la sala 2 suman para su puerta aunque la 1 siga cerrada", galleryEarly == 2 and progress[2] == 1)
local gate15, open15 = CaveLogic.countKill(progress, nestX, nestZ)
check("el 15 abre la Galería", gate15 == 1 and open15 and CaveLogic.isOpen(progress, 1))
check("con la puerta abierta ya no suma, ni los de fuera o del altar", CaveLogic.countKill(progress, nestX, nestZ) == nil and progress[1] == 15
	and CaveLogic.countKill(progress, 0, 0) == nil and CaveLogic.countKill(progress, altarX, altarZ) == nil)
-- Valle: la puerta 2 es del mini-jefe (índice 4)
local valley = CaveConfig.Caves.CrystalValley
local vNestX, vNestZ = center(valley.Rooms[1].Rect)
local vGalleryX, vGalleryZ = center(valley.Rooms[2].Rect)
local vAltarX, vAltarZ = center(valley.Rooms[3].Rect)
check("en el Valle, los pequeños de su sala 1 cuentan para SU puerta (la 3)", CaveLogic.countKill(progress, vNestX, vNestZ) == 3 and progress[3] == 1 and progress[1] == 15)
local plain = CaveLogic.countKill(progress, vGalleryX, vGalleryZ, false)
local boss, bossOpened = CaveLogic.countKill(progress, vGalleryX, vGalleryZ, true)
check("la puerta del mini-jefe: los gólems normales no cuentan; el mini-jefe la abre", plain == nil and progress[4] == 1 and boss == 4 and bossOpened and CaveLogic.isOpen(progress, 4))
check("lo que pide cada puerta", CaveLogic.gateAsk(gates[1]) == "Derrota 15 Espinillos" and CaveLogic.gateAsk(gates[4]) == "Derrota al Gólem Guardián")

local closed = CaveLogic.sanitizeProgress(nil)
local gate1, gate2 = gates[1], gates[2]
check("detrás de una cerrada: la sala 2 y la 3 quedan detrás de la puerta 1", CaveLogic.blockedAt(galleryX, galleryZ, closed) == 1 and CaveLogic.blockedAt(altarX, altarZ, closed) == 1)
check("delante de la puerta (sala 1 y su lado del pasillo) no", CaveLogic.blockedAt(nestX, nestZ, closed) == nil and CaveLogic.blockedAt(gate1.Position.X + 2, gate1.Position.Z, closed) == nil)
check("pasada la puerta en el pasillo, sí", CaveLogic.blockedAt(gate1.Position.X - 4, gate1.Position.Z, closed) == 1)
local half = { 15, 0 }
check("con la 1 abierta: la sala 2 libre y la 3 detrás de la puerta 2", CaveLogic.blockedAt(galleryX, galleryZ, half) == nil and CaveLogic.blockedAt(altarX, altarZ, half) == 2
	and CaveLogic.blockedAt(gate2.Position.X - 4, gate2.Position.Z, half) == 2)
check("con las dos abiertas, todo libre", CaveLogic.blockedAt(altarX, altarZ, { 15, 6 }) == nil and CaveLogic.blockedAt(0, 0, closed) == nil)
check("las puertas de una cueva no cierran las de otra", CaveLogic.blockedAt(vGalleryX, vGalleryZ, { 0, 0 }) == 3 and CaveLogic.blockedAt(vNestX, vNestZ, closed) == nil
	and CaveLogic.blockedAt(vAltarX, vAltarZ, { 15, 6, 20, 0 }) == 4 and CaveLogic.blockedAt(vAltarX, vAltarZ, { 0, 0, 20, 1 }) == nil)

print("-- Lógica (CaveLogic)")
local r1 = rooms[1].Rect
check("roomAt: en la sala 1", CaveLogic.roomAt((r1.MinX + r1.MaxX) / 2, (r1.MinZ + r1.MaxZ) / 2) == 1)
check("roomAt: en el pueblo, ninguna", CaveLogic.roomAt(0, 0) == nil and not CaveLogic.inside(0, 0) and CaveLogic.caveAt(0, 0) == nil)
local c1 = corridors[1].Rect
check("inside: un pasillo cuenta como cueva, pero no es una sala", CaveLogic.inside((c1.MinX + c1.MaxX) / 2, (c1.MinZ + c1.MaxZ) / 2) and CaveLogic.roomAt((c1.MinX + c1.MaxX) / 2, (c1.MinZ + c1.MaxZ) / 2) == nil)
local floorY = 0.78
for _, caveId in CaveConfig.Order do
	local cave = CaveConfig.Caves[caveId]
	local trigger = cave.Entrance.Trigger
	local out = cave.Entrance.Exit
	local midTrigger = Vector3.new((trigger.MinX + trigger.MaxX) / 2, floorY + 3, (trigger.MinZ + trigger.MaxZ) / 2)
	check(("inEntrance: la boca de %s lleva a su cueva; encima o fuera, no"):format(cave.Name), CaveLogic.inEntrance(midTrigger, floorY) == caveId
		and CaveLogic.inEntrance(Vector3.new(midTrigger.X, floorY + 70, midTrigger.Z), floorY) == nil and CaveLogic.inEntrance(Vector3.new(out.Position.X, floorY + 3, out.Position.Z), floorY) == nil)
end
local e1 = CaveConfig.Exits[1].Position
check("exitAt: sobre el portal sí y lejos no; cada salida sabe de qué cueva es", CaveLogic.exitAt(Vector3.new(e1.X, 3, e1.Z)) == 1 and CaveLogic.exitAt(Vector3.new(e1.X - 12, 3, e1.Z)) == nil
	and CaveConfig.Exits[3].Cave == "CrystalValley" and CaveLogic.exitAt(CaveConfig.Exits[6].Position) == 6)
check("altarCenter: el de cada cueva", CaveLogic.altarCenter().X == altarX and CaveLogic.altarCenter("CrystalValley").Y == vAltarZ)

print("-- Trampas")
local room1 = valley.Rooms[1]
local spot = CaveLogic.trapSpot(room1, room1.Rect.MinX + 1, room1.Rect.MinZ + 1, 4, 0.5, 1)
check("una trampa sale junto a ti pero nunca fuera de la sala", spot.X >= room1.Rect.MinX + 6 and spot.Y >= room1.Rect.MinZ + 6)
local mid = CaveLogic.trapSpot(room1, vNestX, vNestZ, 4, 0, 1)
check("a como mucho Spread studs", math.abs(dist(mid.X, mid.Y, vNestX, vNestZ) - 4) < 1e-6)
check("cada cuánto sale una: entre el mínimo y el máximo", CaveLogic.trapDelay(valley.Traps, 0) == valley.Traps.Interval[1] and CaveLogic.trapDelay(valley.Traps, 1) == valley.Traps.Interval[2])
check("le da a quien está en el círculo (no a quien está fuera o muy arriba)", CaveLogic.trapHits(Vector2.new(0, 0), 6, Vector3.new(3, 1, 3), 0.78)
	and not CaveLogic.trapHits(Vector2.new(0, 0), 6, Vector3.new(6, 1, 6), 0.78) and not CaveLogic.trapHits(Vector2.new(0, 0), 6, Vector3.new(1, 30, 1), 0.78))

if failures == 0 then
	print("TODO OK")
else
	print(failures .. " FALLOS")
end
