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
