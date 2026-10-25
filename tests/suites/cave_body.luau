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

local rooms, corridors = CaveConfig.Rooms, CaveConfig.Corridors
local base = GeneratorConfig.Position
local forestZone = ZoneConfig.Zones[CaveConfig.Zone]
local originX, originZ = base.X + forestZone.Center.X, base.Z + forestZone.Center.Y

print("-- Salas y pasillos")
local shapeOK, heightOK, namesOK = true, true, true
for index, room in rooms do
	shapeOK = shapeOK and rectOK(room.Rect)
	heightOK = heightOK and room.Height % B == 0 and room.Height >= 32
	namesOK = namesOK and type(room.Name) == "string" and type(room.Label) == "string" and type(room.Text) == "string" and #room.Crystal >= 1 and #room.Mushroom >= 1
	for _, sky in room.Skylights or {} do
		if not (rectOK(sky) and inside(room.Rect, (sky.MinX + sky.MaxX) / 2, (sky.MinZ + sky.MaxZ) / 2, WALL)) then
			shapeOK = false
			print("  claraboya fuera de la sala " .. index)
		end
	end
end
check("tres salas: los pequeños, los medianos y el altar", #rooms == 3 and rooms[3].Altar == true and not rooms[1].Altar and not rooms[2].Altar)
check("salas en bordes de bloque (8k ± 4) con sus claraboyas dentro", shapeOK)
check("techos de bloques enteros y altos", heightOK)
check("cada sala tiene nombre, cartel, texto y colores", namesOK)
local apartOK = true
for i = 1, #rooms do
	for j = i + 1, #rooms do
		apartOK = apartOK and not overlap(rooms[i].Rect, rooms[j].Rect)
	end
	for _, corridor in corridors do
		apartOK = apartOK and not overlap(rooms[i].Rect, corridor.Rect)
	end
end
check("las salas y los pasillos no se pisan", apartOK)
local doorsOK, linkedOK = true, true
local reached = { [1] = true }
for _, corridor in corridors do
	local c = corridor.Rect
	doorsOK = doorsOK and rectOK(c) and corridor.Height % B == 0
	for _, roomIndex in { corridor.From, corridor.To } do
		local room = rooms[roomIndex]
		local r = room and room.Rect
		local touches = false
		if r then
			if c.MaxX == r.MinX or c.MinX == r.MaxX then
				touches = c.MinZ >= r.MinZ + B and c.MaxZ <= r.MaxZ - B
			elseif c.MaxZ == r.MinZ or c.MinZ == r.MaxZ then
				touches = c.MinX >= r.MinX + B and c.MaxX <= r.MaxX - B
			end
			-- Encima del hueco sigue la pared (dintel)
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
for index in rooms do
	linkedOK = linkedOK and reached[index] == true
end
check("cada pasillo entra por un lado de sus dos salas, lejos de las esquinas y con dintel", doorsOK)
check("se llega andando de la sala 1 a todas (1 -> 2 -> 3)", linkedOK)

print("-- Lejos del mapa, pero sigue siendo el Bosque")
local minX, maxX, minZ, maxZ = CaveLogic.bounds()
local farOK = true
for zoneId, zone in ZoneConfig.Zones do
	local cx, cz = base.X + zone.Center.X, base.Z + zone.Center.Y
	local half = (zone.Radius or 160) + 12
	-- ZoneService.zoneAt: dentro del cuadrado de una zona (con su margen) cuenta como esa zona
	if minX <= cx + half and maxX >= cx - half and minZ <= cz + half and maxZ >= cz - half then
		farOK = false
		print("  la cueva pisa el cuadrado de " .. zoneId)
	end
	-- Ni las montañas del horizonte (a ~350 del centro de cada zona) ni el terreno la tocan
	local nearestX = math.clamp(cx, minX, maxX)
	local nearestZ = math.clamp(cz, minZ, maxZ)
	if dist(nearestX, nearestZ, cx, cz) < 500 then
		farOK = false
		print("  la cueva está demasiado cerca de " .. zoneId)
	end
end
check("fuera de los cuadrados de las zonas (ZoneService la cuenta como Bosque) y lejos de todo", farOK and ZoneConfig.DefaultZone == CaveConfig.Zone)

print("-- Entrar y salir")
local cave = StudFloor.Zones.Forest.Cave
local opening, road = cave.Opening, cave.Road
local trigger = CaveConfig.Entrance.Trigger
check("la boca te lleva dentro desde el fondo del túnel", trigger.MinX >= opening.MinX and trigger.MaxX < opening.MaxX and trigger.MinZ >= opening.MinZ and trigger.MaxZ <= opening.MaxZ and trigger.Height <= (opening.Ceiling or 3) * B)
local out = CaveConfig.Entrance.Exit
check("al salir apareces en el camino, fuera de la boca y mirando a la pradera",
	out.Position.X > opening.MaxX + 4 and out.Position.X >= road[1] and out.Position.X <= road[2] and out.Position.Z >= road[3] and out.Position.Z <= road[4] and out.Facing.X > 0)
local arrival = CaveConfig.Arrival.Position
local arrivalRoom = CaveLogic.roomAt(arrival.X, arrival.Z)
check("llegas a la sala 1, lejos de sus paredes", arrivalRoom == 1 and inside(rooms[1].Rect, arrival.X, arrival.Z, WALL + 4))
local exitsOK, bounceOK, roomsWithExit = true, true, {}
for index, exit in CaveConfig.Exits do
	local room = rooms[exit.Room]
	local r = room and room.Rect
	local roomIndex = CaveLogic.roomAt(exit.Position.X, exit.Position.Z)
	local nearWall = r and math.min(exit.Position.X - (r.MinX + WALL), (r.MaxX - WALL) - exit.Position.X, exit.Position.Z - (r.MinZ + WALL), (r.MaxZ - WALL) - exit.Position.Z) <= 2
	-- Mira hacia dentro de la sala
	local ahead = r and inside(r, exit.Position.X + exit.Facing.X * 10, exit.Position.Z + exit.Facing.Z * 10, WALL)
	if not (room and roomIndex == exit.Room and nearWall and ahead) then
		exitsOK = false
		print("  portal de salida mal puesto: " .. index)
	end
	if dist(arrival.X, arrival.Z, exit.Position.X, exit.Position.Z) < CaveConfig.ExitRadius + 6 then
		bounceOK = false
	end
	roomsWithExit[exit.Room] = true
end
check("portales de salida pegados a una pared y mirando a la sala", exitsOK)
check("hay salida en la sala 1 y en la del altar", roomsWithExit[1] == true and roomsWithExit[3] == true)
check("al llegar no pisas un portal de salida (no rebotas fuera)", bounceOK and CaveLogic.exitAt(Vector3.new(arrival.X, 0, arrival.Z)) == nil)
check("el viaje tiene fundido y espera entre dos viajes", CaveConfig.Travel.FadeSeconds > 0 and CaveConfig.Travel.FadeSeconds < 1 and CaveConfig.Travel.Cooldown >= 1 and CaveConfig.Travel.CheckInterval > 0)

print("-- Los bichos de cada sala")
local enemies = EnemyConfig.Zones[CaveConfig.Zone]
local counts = { {}, {}, {} }
local spawnsOK, corridorClear, arrivalClear, altarClear = true, true, true, true
local altar = CaveLogic.altarCenter()
for _, spawn in enemies.Spawns do
	local x, z = originX + spawn.Offset.X, originZ + spawn.Offset.Y
	if CaveLogic.inside(x, z, 0) then
		local roomIndex = CaveLogic.roomAt(x, z)
		local def = EnemyConfig.Types[spawn.Type]
		if not roomIndex then
			corridorClear = false
		else
			counts[roomIndex][def.Kind] = (counts[roomIndex][def.Kind] or 0) + 1
			if not inside(rooms[roomIndex].Rect, x, z, WALL + 4) then
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
check(("sala 2: los medianos (%d brutos)"):format(counts[2].Strong or 0), (counts[2].Strong or 0) >= 4 and counts[2].Normal == nil and counts[2].Boss == nil)
check("sala 3: sin bichos del mundo (solo las oleadas)", next(counts[3]) == nil and altarClear)
check("los bichos salen dentro de su sala, lejos de las paredes y nunca en un pasillo", spawnsOK and corridorClear)
check("ninguno sale junto a donde llegas", arrivalClear)
local guarded = false
for _, safe in enemies.SafeZones do
	if dist(originX + safe.Center.X, originZ + safe.Center.Y, arrival.X, arrival.Z) + 4 <= safe.Radius then
		guarded = true
	end
end
check("donde llegas es zona segura (no te atacan nada más entrar)", guarded)

print("-- Puertas entre salas")
local gates = CaveConfig.Gates
local gatesOK = #gates == #corridors
for index, gate in gates do
	local corridor = corridors[gate.Corridor]
	local c = corridor and corridor.Rect
	local fromRoom = rooms[gate.Room]
	local width, height = CaveLogic.gateSize(index)
	-- En su pasillo, junto a la sala de la que se viene (mirando hacia ella), y Back dentro de esa sala
	local ok = corridor ~= nil and corridor.From == gate.Room and fromRoom ~= nil
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
check("15 pequeños abren la Galería y 6 brutos el Altar", gates[1].Kills == 15 and gates[1].Room == 1 and gates[2].Kills == 6 and gates[2].Room == 2)
local strength = CaveConfig.Strength
check("los bichos de la cueva son más duros que los de fuera", strength.Health > 1 and strength.Damage > 1 and strength.Reward >= 1)
local roomKills = { 0, 0, 0 }
for _, spawn in enemies.Spawns do
	local x, z = originX + spawn.Offset.X, originZ + spawn.Offset.Y
	local roomIndex = CaveLogic.roomAt(x, z)
	if roomIndex then
		roomKills[roomIndex] += 1
	end
end
check("hay bichos de sobra en cada sala con puerta (vuelven a salir)", roomKills[1] >= 6 and roomKills[2] >= 4)

local progress = CaveLogic.sanitizeProgress(nil)
check("sin datos: todas cerradas y con un número por puerta", #progress == #gates and progress[1] == 0 and not CaveLogic.isOpen(progress, 1) and not CaveLogic.isOpen(progress, 2))
check("datos raros: se limpian y no pasan del tope", CaveLogic.sanitizeProgress({ 999, -3 })[1] == 15 and CaveLogic.sanitizeProgress({ 999, -3 })[2] == 0
	and CaveLogic.sanitizeProgress("x")[1] == 0 and CaveLogic.sanitizeProgress({ 0 / 0, 2.7 })[2] == 2 and CaveLogic.sanitizeProgress({ ["1"] = 4 })[1] == 4)
check("atributo: \"15,3\" de ida y vuelta", CaveLogic.formatProgress({ 15, 3 }) == "15,3" and CaveLogic.parseProgress("15,3")[2] == 3 and CaveLogic.parseProgress(nil)[1] == 0 and CaveLogic.parseProgress("a,b")[1] == 0)
local nest = rooms[1].Rect
local nestX, nestZ = (nest.MinX + nest.MaxX) / 2, (nest.MinZ + nest.MaxZ) / 2
local gallery = rooms[2].Rect
local galleryX, galleryZ = (gallery.MinX + gallery.MaxX) / 2, (gallery.MinZ + gallery.MaxZ) / 2
local altarRoom = rooms[3].Rect
local altarX, altarZ = (altarRoom.MinX + altarRoom.MaxX) / 2, (altarRoom.MinZ + altarRoom.MaxZ) / 2
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

local closed = CaveLogic.sanitizeProgress(nil)
local gate1, gate2 = gates[1], gates[2]
check("detrás de una cerrada: la sala 2 y la 3 quedan detrás de la puerta 1", CaveLogic.blockedAt(galleryX, galleryZ, closed) == 1 and CaveLogic.blockedAt(altarX, altarZ, closed) == 1)
check("delante de la puerta (sala 1 y su lado del pasillo) no", CaveLogic.blockedAt(nestX, nestZ, closed) == nil and CaveLogic.blockedAt(gate1.Position.X + 2, gate1.Position.Z, closed) == nil)
check("pasada la puerta en el pasillo, sí", CaveLogic.blockedAt(gate1.Position.X - 4, gate1.Position.Z, closed) == 1)
local half = { 15, 0 }
check("con la 1 abierta: la sala 2 libre y la 3 detrás de la puerta 2", CaveLogic.blockedAt(galleryX, galleryZ, half) == nil and CaveLogic.blockedAt(altarX, altarZ, half) == 2
	and CaveLogic.blockedAt(gate2.Position.X - 4, gate2.Position.Z, half) == 2)
check("con las dos abiertas, todo libre", CaveLogic.blockedAt(altarX, altarZ, { 15, 6 }) == nil and CaveLogic.blockedAt(0, 0, closed) == nil)

print("-- Lógica (CaveLogic)")
local r1 = rooms[1].Rect
check("roomAt: en la sala 1", CaveLogic.roomAt((r1.MinX + r1.MaxX) / 2, (r1.MinZ + r1.MaxZ) / 2) == 1)
check("roomAt: en el pueblo, ninguna", CaveLogic.roomAt(0, 0) == nil and not CaveLogic.inside(0, 0))
local c1 = corridors[1].Rect
check("inside: un pasillo cuenta como cueva, pero no es una sala", CaveLogic.inside((c1.MinX + c1.MaxX) / 2, (c1.MinZ + c1.MaxZ) / 2) and CaveLogic.roomAt((c1.MinX + c1.MaxX) / 2, (c1.MinZ + c1.MaxZ) / 2) == nil)
local floorY = 0.78
local midTrigger = Vector3.new((trigger.MinX + trigger.MaxX) / 2, floorY + 3, (trigger.MinZ + trigger.MaxZ) / 2)
check("inEntrance: en el fondo de la boca sí", CaveLogic.inEntrance(midTrigger, floorY))
check("inEntrance: encima de la colina, no", not CaveLogic.inEntrance(Vector3.new(midTrigger.X, floorY + 70, midTrigger.Z), floorY))
check("inEntrance: en el camino de fuera, no", not CaveLogic.inEntrance(Vector3.new(out.Position.X, floorY + 3, out.Position.Z), floorY))
local e1 = CaveConfig.Exits[1].Position
check("exitAt: sobre el portal sí y lejos no", CaveLogic.exitAt(Vector3.new(e1.X, 3, e1.Z)) == 1 and CaveLogic.exitAt(Vector3.new(e1.X - 12, 3, e1.Z)) == nil)

if failures == 0 then
	print("TODO OK")
else
	print(failures .. " FALLOS")
end
