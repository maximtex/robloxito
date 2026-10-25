-- Paisaje (LandscapeLayout): distribución determinista que respeta las zonas de juego.

local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end

-- El mapa estilo simulador solo construye el límite invisible (LandscapeService): árboles,
-- caminos, montañas, jardines, pueblo y naturaleza de LandscapeLayout NO se construyen
-- (LandscapeConfig.BuildsDecor = false). Sus comprobaciones se omiten (no cuentan) hasta que
-- se vuelvan a construir; las del límite, los cofres y los personajes sí cuentan.
local decorBuilt = LandscapeConfig.BuildsDecor ~= false
local omitted = 0
local function decorCheck(name, ok)
	if decorBuilt then
		check(name, ok)
	else
		omitted += 1
		print("OMIT   " .. name .. (if ok then "" else "  (fallaría)"))
	end
end

LandscapeLayout.init({
	LandscapeConfig = LandscapeConfig,
	WorldConfig = WorldConfig,
	ValleyConfig = ValleyConfig,
	CalderaConfig = CalderaConfig,
	CoreShrineConfig = CoreShrineConfig,
	EggConfig = EggConfig,
	ZoneConfig = ZoneConfig,
	EnemyConfig = EnemyConfig,
	AdventureConfig = AdventureConfig,
	VillageConfig = VillageConfig,
	WildsConfig = WildsConfig,
	ChestConfig = ChestConfig,
})

-- 1. Azar determinista -----------------------------------------------------------------
local a, b = LandscapeLayout.rng(123), LandscapeLayout.rng(123)
local same, inRange = true, true
for _ = 1, 200 do
	local x, y = a:next(), b:next()
	same = same and x == y
	inRange = inRange and x >= 0 and x < 1
end
check("azar: misma semilla, misma secuencia", same)
check("azar: valores en [0, 1)", inRange)
local c = LandscapeLayout.rng(7)
local intsOk = true
for _ = 1, 300 do
	local n = c:int(2, 5)
	intsOk = intsOk and n >= 2 and n <= 5 and n == math.floor(n)
end
check("azar: enteros dentro del rango", intsOk)
check("azar: semilla 0 válida", LandscapeLayout.rng(0):next() > 0)

-- 2. Geometría ---------------------------------------------------------------------------
check("distancia a segmento", math.abs(LandscapeLayout.distanceToSegment(0, 5, -10, 0, 10, 0) - 5) < 1e-9 and math.abs(LandscapeLayout.distanceToSegment(13, 4, -10, 0, 10, 0) - 5) < 1e-9)
local along = LandscapeLayout.alongPath({ Vector2.new(0, 0), Vector2.new(0, 40) }, 10, 3)
local alongOk = #along == 4
for index, item in along do
	alongOk = alongOk and math.abs(math.abs(item.X) - 3) < 1e-9 and (index == 1 or item.X * along[index - 1].X < 0)
end
check("faroles: cada 10 studs, a 3 del centro y alternando lados", alongOk)

-- 3. Cada zona -----------------------------------------------------------------------------
local function insideAny(x, z, r, list)
	for _, item in list do
		if (x - item.X) ^ 2 + (z - item.Z) ^ 2 < (item.R + r) ^ 2 - 1e-6 then
			return item.Name
		end
	end
	return nil
end

for _, key in { "Forest", "Valley", "Caldera" } do
	local settings = LandscapeConfig[key]
	local layout = LandscapeLayout.compute(key)
	local again = LandscapeLayout.compute(key)
	local deterministic = #layout.Scatter == #again.Scatter
	for index, item in layout.Scatter do
		local other = again.Scatter[index]
		deterministic = deterministic and other and other.X == item.X and other.Z == item.Z and other.Kind == item.Kind
	end
	check(key .. ": siempre el mismo paisaje", deterministic)

	local obstacles = layout.Obstacles
	local okHard, okSolid, okPaths, okBoundary, okOverlap = true, true, true, true, true
	for index, item in layout.Scatter do
		local hit = insideAny(item.X, item.Z, item.R, obstacles.Hard)
		if hit then
			okHard = false
			print("  " .. item.Kind .. " sobre " .. hit)
		end
		if item.Solid and insideAny(item.X, item.Z, item.R, obstacles.SolidOnly) then
			okSolid = false
		end
		if LandscapeLayout.distanceToPaths(item.X, item.Z, obstacles.Paths) < item.R then
			okPaths = false
		end
		if math.sqrt(item.X ^ 2 + item.Z ^ 2) + item.R > settings.BoundaryRadius - 6 then
			okBoundary = false
		end
		for other = index + 1, #layout.Scatter do
			local o = layout.Scatter[other]
			if (item.X - o.X) ^ 2 + (item.Z - o.Z) ^ 2 < (item.R + o.R) ^ 2 then
				okOverlap = false
			end
		end
	end
	decorCheck(key .. ": nada al azar encima de lo que ya hay (spawn, altares, huevos, arenas...)", okHard)
	decorCheck(key .. ": nada sólido en la zona de los enemigos", okSolid)
	decorCheck(key .. ": nada al azar encima de los caminos", okPaths)
	decorCheck(key .. ": todo dentro del límite", okBoundary)
	decorCheck(key .. ": nada se solapa", okOverlap)
	local counts = {}
	for _, item in layout.Scatter do
		counts[item.Kind] = (counts[item.Kind] or 0) + 1
	end
	local enough, summary = true, {}
	for _, spec in settings.Scatter do
		local n = counts[spec.Kind] or 0
		table.insert(summary, spec.Kind .. "=" .. n .. "/" .. spec.Count)
		enough = enough and n >= math.floor(spec.Count * 0.75)
	end
	decorCheck(key .. ": cabe casi todo lo pedido (" .. table.concat(summary, " ") .. ")", enough)

	-- Faroles
	local lampsOk = #layout.Lamps > 0
	for _, lamp in layout.Lamps do
		if insideAny(lamp.X, lamp.Z, 0.8, obstacles.Hard) or LandscapeLayout.distanceToPaths(lamp.X, lamp.Z, obstacles.Paths) < 0.5 then
			lampsOk = false
		end
	end
	decorCheck(key .. ": " .. #layout.Lamps .. " faroles junto a los caminos, sin estorbar", lampsOk)

	-- Caminos: no pasan por encima de huevos, altares, portales ni del centro de las arenas.
	local base = LandscapeLayout.obstacles(key)
	local pathsOk = true
	for _, path in settings.Paths do
		for index = 1, #path.Points - 1 do
			local p, q = path.Points[index], path.Points[index + 1]
			for _, item in base.Hard do
				local strict = item.Name == "Egg" or item.Name:sub(1, 6) == "Altar_" or item.Name:find("Portal") ~= nil
				local arena = item.Name == "Arena"
				local limit = if strict then item.R - 3 elseif arena then item.R - 6 else -math.huge
				local d = LandscapeLayout.distanceToSegment(item.X, item.Z, p.X, p.Y, q.X, q.Y) - path.Width / 2
				if d < limit then
					pathsOk = false
					print(("  camino %s cerca de %s (%.1f)"):format(path.Name, item.Name, d))
				end
			end
		end
	end
	decorCheck(key .. ": los caminos respetan huevos, altares, portales y arenas", pathsOk)

	-- Lo colocado a mano no pisa lo que ya hay.
	local plain = { Hard = {}, SolidOnly = {}, Paths = {} }
	do
		local raw = if key == "Forest" then LandscapeLayout.obstacles(key) else LandscapeLayout.obstacles(key)
		for _, item in raw.Hard do
			local own = ({ Bench = true, Planter = true, Sign = true, Pond = true, Grove = true, Watchtower = true, CrystalSpire = true, CrystalArch = true, CrystalPool = true, Floating = true })[item.Name]
				or item.Name:sub(1, 5) == "Spire"
			if not own then
				table.insert(plain.Hard, item)
			end
		end
	end
	local handOk = true
	local function hand(name, x, z, r)
		local hit = insideAny(x, z, r, plain.Hard)
		if hit then
			handOk = false
			print(("  %s choca con %s"):format(name, hit))
		end
	end
	for _, bench in settings.Benches or {} do
		hand("banco", bench.X, bench.Y, 1.5)
	end
	for _, planter in settings.Planters or {} do
		hand("jardinera", planter.X, planter.Y, planter.Z / 2)
	end
	for _, sign in settings.Signs or {} do
		hand("cartel", sign.Position.X, sign.Position.Y, 1)
	end
	if settings.Pond then
		hand("estanque", settings.Pond.Center.X, settings.Pond.Center.Y, settings.Pond.Radius + 1)
	end
	if settings.MushroomGrove then
		hand("setas gigantes", settings.MushroomGrove.Center.X, settings.MushroomGrove.Center.Y, settings.MushroomGrove.Radius)
	end
	if settings.Watchtower then
		hand("torre", settings.Watchtower.Position.X, settings.Watchtower.Position.Y, settings.Watchtower.Diameter / 2 + 1)
	end
	if settings.CrystalSpire then
		hand("pico de cristal", settings.CrystalSpire.Position.X, settings.CrystalSpire.Position.Y, 6)
	end
	for _, spire in settings.Spires or {} do
		hand("aguja", spire.X, spire.Y, 4 * spire.Z)
	end
	if settings.CrystalArch then
		hand("arco de cristal", settings.CrystalArch.Position.X, settings.CrystalArch.Position.Y, settings.CrystalArch.Width / 2)
	end
	if settings.CrystalPool then
		hand("lago de cristal", settings.CrystalPool.Center.X, settings.CrystalPool.Center.Y, settings.CrystalPool.Radius + 1)
	end
	decorCheck(key .. ": lo construido a mano (bancos, carteles, estanque, torre...) no pisa nada", handOk)

	-- Límite y montañas
	local wallsOk = #layout.Boundary == LandscapeConfig.Boundary.Segments
	for _, wall in layout.Boundary do
		wallsOk = wallsOk and math.max(wall.Width, wall.Height, wall.Thickness) <= 120
	end
	check(key .. ": límite invisible en segmentos de menos de 120 studs (el aviso de piezas gigantes)", wallsOk)
	local insideOk = true
	for _, item in base.Hard do
		-- Los portales van en la frontera entre mapas (pegados) y el límite deja un hueco ahí
		-- (LandscapeService, GATE_CLEARANCE): no cuentan.
		if ZoneConfig.Portals[item.Name] then
			continue
		end
		-- Los bichos de la Cueva de los Espinillos están fuera del círculo a propósito: el límite
		-- deja un hueco ahí y las paredes de la cueva cierran (LandscapeService, ForestCave).
		local zoneCenter = ZoneConfig.Zones[settings.Zone].Center
		local worldX = GeneratorConfig.Position.X + zoneCenter.X + item.X
		local worldZ = GeneratorConfig.Position.Z + zoneCenter.Y + item.Z
		if item.Name:sub(1, 5) == "Spawn" and StudFloor.inCave(worldX, worldZ) then
			continue
		end
		if math.sqrt(item.X ^ 2 + item.Z ^ 2) + item.R > settings.BoundaryRadius then
			insideOk = false
			print("  fuera del límite: " .. item.Name)
		end
	end
	check(key .. ": todas las zonas de juego quedan dentro del límite", insideOk)
	local mountainsOk = true
	for _, mountain in layout.Mountains do
		local visible = mountain.Radius * math.sqrt(1 - (1 - settings.Mountains.Rise) ^ 2)
		if math.sqrt(mountain.X ^ 2 + mountain.Z ^ 2) - visible < settings.BoundaryRadius - 15 then
			mountainsOk = false
		end
	end
	decorCheck(key .. ": las montañas empiezan junto al límite, lejos del juego (" .. #layout.Mountains .. ")", mountainsOk)
end

-- 4. Jardines de huevos ---------------------------------------------------------------------
local STAND = LandscapeLayout.STAND_RADIUS
local function dist(ax, az, bx, bz)
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end
local keyOfZone = {}
for key, settings in { Forest = LandscapeConfig.Forest, Valley = LandscapeConfig.Valley, Caldera = LandscapeConfig.Caldera } do
	keyOfZone[settings.Zone] = key
end
local expected = {
	Forest = { Lamps = 4, Benches = 2, Planters = 2, Fountain = true },
	CrystalValley = { Lamps = 2, Benches = 0, Planters = 0, Fountain = false },
	EmberCaldera = { Lamps = 2, Benches = 0, Planters = 0, Fountain = false },
}
for gardenId, garden in EggConfig.Gardens do
	local key = keyOfZone[garden.Zone]
	local style = LandscapeConfig.Gardens[garden.Style]
	decorCheck(gardenId .. ": zona y estilo existen", key ~= nil and style ~= nil and ZoneConfig.Zones[garden.Zone] ~= nil)
	local layout = LandscapeLayout.compute(key).Garden
	local cx, cz, radius = garden.Center.X, garden.Center.Y, garden.Radius
	decorCheck(gardenId .. ": el paisaje construye el jardín de su zona", layout ~= nil and layout.Garden == garden)

	-- Santuarios: todos dentro del terreno libre del jardín, separados (los carteles no se
	-- tapan) y mirando al centro. El seto de LandscapeLayout.garden ya no se construye; lo que
	-- el mapa deja libre es el círculo de WorldService (Radius + 4: ni árboles ni adornos).
	local inner = radius + 4
	local stands = layout.Stands
	local zoneEggs = 0
	for _, egg in EggConfig.Eggs do
		if egg.Enabled ~= false and (egg.Zone or ZoneConfig.DefaultZone) == garden.Zone then
			zoneEggs += 1
		end
	end
	decorCheck(("%s: reúne los %d huevos de la zona"):format(gardenId, zoneEggs), #stands == zoneEggs and zoneEggs > 0)
	local insideOk, apartOk, facingOk = true, true, true
	for index, stand in stands do
		if dist(stand.X, stand.Z, cx, cz) + STAND > inner then
			insideOk = false
			print("  fuera del jardín: " .. stand.Id)
		end
		for other = index + 1, #stands do
			if dist(stand.X, stand.Z, stands[other].X, stands[other].Z) < 2 * STAND + 2.5 then
				apartOk = false
				print("  demasiado juntos: " .. stand.Id .. " y " .. stands[other].Id)
			end
		end
		local d = dist(stand.X, stand.Z, cx, cz)
		if d > 1 then
			facingOk = facingOk and math.abs((stand.FacingX * (cx - stand.X) + stand.FacingZ * (cz - stand.Z)) / d - 1) < 1e-6
		else
			local angle = math.rad(garden.Entrance)
			facingOk = facingOk and math.abs(stand.FacingX - math.cos(angle)) < 1e-6 and math.abs(stand.FacingZ - math.sin(angle)) < 1e-6
		end
	end
	decorCheck(gardenId .. ": cada santuario cabe en el terreno libre del jardín", insideOk)
	decorCheck(gardenId .. ": santuarios separados (sus carteles no se tapan)", apartOk)
	decorCheck(gardenId .. ": cada santuario mira al centro (o a la entrada)", facingOk)

	-- Mobiliario: lo esperado, sin tocar santuarios, sin solaparse y sin tapar la entrada.
	local want = expected[gardenId]
	if want then
		decorCheck(("%s: %d faroles, %d bancos, %d jardineras%s"):format(gardenId, want.Lamps, want.Benches, want.Planters, if want.Fountain then " y fuente" else ""),
			#layout.Lamps == want.Lamps and #layout.Benches == want.Benches and #layout.Planters == want.Planters and (layout.Fountain ~= nil) == want.Fountain)
	end
	local furniture = {}
	for _, list in { layout.Lamps, layout.Benches, layout.Planters } do
		for _, item in list do
			table.insert(furniture, item)
		end
	end
	if layout.Fountain then
		table.insert(furniture, layout.Fountain)
	end
	local clearOk, overlapOk, gateOk = true, true, true
	for index, item in furniture do
		for _, stand in stands do
			if dist(item.X, item.Z, stand.X, stand.Z) < STAND + item.R + 0.5 then
				clearOk = false
			end
		end
		for other = index + 1, #furniture do
			local o = furniture[other]
			if dist(item.X, item.Z, o.X, o.Z) < item.R + o.R then
				overlapOk = false
			end
		end
		if dist(item.X, item.Z, layout.Gate.X, layout.Gate.Z) < layout.Gate.Width / 2 + item.R then
			gateOk = false
		end
	end
	decorCheck(gardenId .. ": faroles, bancos, jardineras y fuente no tocan los santuarios", clearOk)
	decorCheck(gardenId .. ": el mobiliario no se solapa", overlapOk)
	decorCheck(gardenId .. ": la entrada queda despejada", gateOk)
	if layout.Fountain then
		local gap = math.huge
		for _, stand in stands do
			gap = math.min(gap, dist(stand.X, stand.Z, layout.Fountain.X, layout.Fountain.Z) - STAND - layout.Fountain.R)
		end
		decorCheck(("%s: se pasa entre la fuente y los santuarios (%.1f studs)"):format(gardenId, gap), gap >= 2)
	end
	decorCheck(("%s: entrada de %.1f studs entre pilares (cabe el sendero)"):format(gardenId, layout.Gate.Width), layout.Gate.Width - 1.6 >= 5)
	local ringOk = #layout.Ring > 0
	for _, item in layout.Ring do
		local delta = math.abs(((item.Angle - garden.Entrance) + 180) % 360 - 180)
		ringOk = ringOk and delta >= style.GateHalfAngle and math.abs(dist(item.X, item.Z, cx, cz) - radius) < 1e-6
	end
	decorCheck(("%s: %d tramos de seto/cristales, sin cerrar la entrada"):format(gardenId, #layout.Ring), ringOk)

	-- Respeto del mapa: no pisa nada de juego ni de lo que ya hay.
	local base = LandscapeLayout.obstacles(key)
	local mapOk = true
	for _, item in base.Hard do
		local own = item.Name == "EggGarden" or item.Name == "Egg" or (item.Name == "KeepClear" and dist(item.X, item.Z, cx, cz) < 1)
		if not own and dist(item.X, item.Z, cx, cz) < radius + 1 + item.R then
			mapOk = false
			print(("  el jardín %s pisa %s (%.0f, %.0f)"):format(gardenId, item.Name, item.X, item.Z))
		end
	end
	decorCheck(gardenId .. ": no pisa spawn, portales, altares, arenas, enemigos ni decorado", mapOk)
	local keep = if key == "Forest" then WorldConfig.KeepClear elseif key == "Caldera" then CalderaConfig.KeepClear else ValleyConfig.KeepClear
	local keepOk = false
	for _, zone in keep do
		keepOk = keepOk or (dist(zone.X, zone.Y, cx, cz) < 1 and zone.Z >= radius + 1)
	end
	decorCheck(gardenId .. ": sin flores sueltas dentro (KeepClear lo cubre)", keepOk)
	local safeOk = false
	for _, safe in EnemyConfig.Zones[garden.Zone].SafeZones do
		safeOk = safeOk or (dist(safe.Center.X, safe.Center.Y, cx, cz) < 1 and safe.Radius >= radius + 3)
	end
	decorCheck(gardenId .. ": zona protegida de los enemigos (SafeZone cubre el jardín)", safeOk)
	-- Caminos: llegan a la entrada y no atraviesan el seto por otro sitio.
	-- (y ese camino sale de otro: está conectado con el resto del mapa)
	local reached = false
	for _, path in base.Paths do
		if LandscapeLayout.distanceToPaths(layout.Gate.X, layout.Gate.Z, { path }) < 1.5 then
			local first = path.Points[1]
			local others = {}
			for _, other in base.Paths do
				if other ~= path then
					table.insert(others, other)
				end
			end
			reached = reached or LandscapeLayout.distanceToPaths(first.X, first.Y, others) < 1.5
		end
	end
	decorCheck(gardenId .. ": un camino conectado llega a la entrada", reached)
	local throughOk = true
	for _, path in LandscapeConfig[key].Paths do
		for index = 1, #path.Points - 1 do
			local p, q = path.Points[index], path.Points[index + 1]
			local d = LandscapeLayout.distanceToSegment(cx, cz, p.X, p.Y, q.X, q.Y) - path.Width / 2
			if d < radius + 0.5 then
				-- Solo puede entrar por la entrada: el punto más cercano al centro, junto a ella.
				local nearest = if dist(p.X, p.Y, cx, cz) < dist(q.X, q.Y, cx, cz) then p else q
				if dist(nearest.X, nearest.Y, layout.Gate.X, layout.Gate.Z) > layout.Gate.Width / 2 + 1 then
					throughOk = false
					print(("  el camino %s cruza el jardín %s"):format(path.Name, gardenId))
				end
			end
		end
	end
	decorCheck(gardenId .. ": ningún camino atraviesa el seto", throughOk)
end

-- Aventuras: los personajes y los objetos perdidos están en sitios despejados ------------
for key, zoneId in { Forest = "Forest", Valley = "CrystalValley", Caldera = "EmberCaldera" } do
	local obstacles = LandscapeLayout.obstacles(key)
	local spots = {}
	for npcId, npc in AdventureConfig.Npcs do
		if npc.Zone == zoneId then
			table.insert(spots, { Name = "Npc_" .. npcId, X = npc.Position.X, Z = npc.Position.Y, R = 2.5, PathGap = 1.5 })
		end
	end
	for itemId, item in AdventureConfig.Items do
		if item.Zone == zoneId then
			table.insert(spots, { Name = "Item_" .. itemId, X = item.Position.X, Z = item.Position.Y, R = 1.5, PathGap = -10 })
		end
	end
	local clear = true
	for _, spot in spots do
		for _, item in obstacles.Hard do
			local own = string.sub(item.Name, 1, 4) == "Npc_" or string.sub(item.Name, 1, 5) == "Item_"
			if not own and (spot.X - item.X) ^ 2 + (spot.Z - item.Z) ^ 2 < (item.R + spot.R) ^ 2 then
				clear = false
				print(("  %s choca con %s"):format(spot.Name, item.Name))
			end
		end
		if LandscapeLayout.distanceToPaths(spot.X, spot.Z, obstacles.Paths) < spot.R + spot.PathGap then
			clear = false
			print(("  %s está encima de un camino"):format(spot.Name))
		end
		if math.sqrt(spot.X ^ 2 + spot.Z ^ 2) > LandscapeConfig[key].BoundaryRadius - 15 then
			clear = false
			print(("  %s está fuera del límite"):format(spot.Name))
		end
	end
	check(key .. ": personajes y objetos perdidos en sitios despejados (" .. #spots .. ")", #spots > 0 and clear)
	local layout = LandscapeLayout.compute(key)
	local freeOfScatter = true
	for _, spot in spots do
		for _, item in layout.Scatter do
			if item.Solid ~= false and (spot.X - item.X) ^ 2 + (spot.Z - item.Z) ^ 2 < (spot.R + 1.5) ^ 2 then
				freeOfScatter = false
				print(("  %s tapado por %s"):format(spot.Name, tostring(item.Kind)))
			end
		end
	end
	decorCheck(key .. ": nada del paisaje al azar encima de ellos", freeOfScatter)
end

-- Pueblo del Renacimiento -----------------------------------------------------------------
do
	local obstacles = LandscapeLayout.obstacles("Forest")
	local others = {}
	for _, item in obstacles.Hard do
		local mine = string.sub(item.Name, 1, 7) == "Village"
		if not mine then
			table.insert(others, item)
		end
	end
	local clashOk = true
	local footprints = VillageConfig.footprints()
	local buildingRects = {}
	for _, building in VillageConfig.Buildings do
		buildingRects["Village_" .. building.Id] = VillageConfig.buildingRect(building)
	end
	for _, item in footprints do
		local hit = nil
		local rect = buildingRects[item.Name]
		if rect then
			for _, other in others do
				if VillageConfig.distanceToRect(other.X, other.Z, rect) < other.R then
					hit = other.Name
				end
			end
		else
			hit = insideAny(item.X, item.Z, item.R, others)
		end
		if hit then
			clashOk = false
			print(("  %s choca con %s"):format(item.Name, hit))
		end
	end
	decorCheck("pueblo: casitas, plaza, puestos y farolas no pisan nada del bosque", clashOk)
	-- Las casas se miden con su rectángulo real (VillageConfig.buildingRect); lo demás, círculos.
	local rects = {}
	for _, building in VillageConfig.Buildings do
		rects["Village_" .. building.Id] = VillageConfig.buildingRect(building)
	end
	local overlapOk = true
	for i = 1, #footprints do
		for j = i + 1, #footprints do
			local a, b = footprints[i], footprints[j]
			local square = a.Name == "VillageSquare" or b.Name == "VillageSquare"
			local ra, rb = rects[a.Name], rects[b.Name]
			local clash
			if ra and rb then
				clash = false -- entre casas, abajo con rectángulos
			elseif ra or rb then
				local rect, other = ra or rb, if ra then b else a
				clash = VillageConfig.distanceToRect(other.X, other.Z, rect) < other.R + 0.3
			else
				clash = (a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2 < (a.R + b.R) ^ 2
			end
			if not square and clash then
				overlapOk = false
				print(("  %s y %s se solapan"):format(a.Name, b.Name))
			end
		end
	end
	-- La plaza (círculo) no toca ninguna casa.
	local square = VillageConfig.Square
	for name, rect in rects do
		if VillageConfig.distanceToRect(square.Center.X, square.Center.Y, rect) < square.Radius + 1 then
			overlapOk = false
			print(("  %s pisa la plaza"):format(name))
		end
	end
	-- Casas separadas al menos 1 stud (rectángulos con tejados y adornos).
	local list = VillageConfig.Buildings
	for i = 1, #list do
		for j = i + 1, #list do
			local a, b = VillageConfig.buildingRect(list[i]), VillageConfig.buildingRect(list[j])
			local apartX = a.MaxX + 1 <= b.MinX or b.MaxX + 1 <= a.MinX
			local apartZ = a.MaxZ + 1 <= b.MinZ or b.MaxZ + 1 <= a.MinZ
			if not apartX and not apartZ then
				overlapOk = false
				print(("  casas %s y %s demasiado juntas"):format(list[i].Id, list[j].Id))
			end
		end
	end
	local stylesOk = true
	for _, building in list do
		stylesOk = stylesOk and VillageConfig.Styles[building.Style] ~= nil and (building.Facing == "East" or building.Facing == "West")
	end
	decorCheck("pueblo: cada casa tiene un estilo del diseño (entramado, torre o tienda)", stylesOk)
	decorCheck("pueblo: nada se solapa (casas separadas; los puestos van dentro de la plaza)", overlapOk)
	-- Calle y caminos: ningún camino atraviesa una casa, un puesto o el tablón.
	local pathOk = true
	local street = VillageConfig.Street
	local allPaths = { { Name = "VillageStreet", Width = street.Width, Points = { street.From, street.To } } }
	for _, path in LandscapeConfig.Forest.Paths do
		table.insert(allPaths, path)
	end
	for _, item in footprints do
		local solid = string.sub(item.Name, 1, 12) == "VillageStall" or item.Name == "VillageBoard"
		if solid then
			for _, path in allPaths do
				for index = 1, #path.Points - 1 do
					local p, q = path.Points[index], path.Points[index + 1]
					if LandscapeLayout.distanceToSegment(item.X, item.Z, p.X, p.Y, q.X, q.Y) < item.R + path.Width / 2 then
						pathOk = false
						print(("  el camino %s atraviesa %s"):format(path.Name, item.Name))
					end
				end
			end
		end
	end
	for name, rect in rects do
		for _, path in allPaths do
			for index = 1, #path.Points - 1 do
				local p, q = path.Points[index], path.Points[index + 1]
				local length = math.sqrt((q.X - p.X) ^ 2 + (q.Y - p.Y) ^ 2)
				local steps = math.max(1, math.ceil(length / 0.5))
				for step = 0, steps do
					local t = step / steps
					if VillageConfig.distanceToRect(p.X + (q.X - p.X) * t, p.Y + (q.Y - p.Y) * t, rect) < path.Width / 2 + 0.3 then
						pathOk = false
						print(("  el camino %s atraviesa %s"):format(path.Name, name))
						break
					end
				end
			end
		end
	end
	decorCheck("pueblo: la calle y los caminos no atraviesan casas ni puestos", pathOk)
	-- La calle llega del spawn hasta el escalón del portal del Valle, y el pueblo es zona protegida.
	local portal = ZoneConfig.Portals.ForestPortal.Offset
	local gap = portal.Y - street.To.Y
	decorCheck("pueblo: la calle llega hasta el escalón del portal del Valle", math.abs(portal.X - street.To.X) < 1 and gap > ZoneConfig.PortalRadius - 3 and gap < ZoneConfig.PortalRadius)
	-- Las lomas (bolas de terreno hundidas 0,6 de su radio) asoman hasta 0,8 del radio.
	local buriedOk = true
	for _, hill in WorldConfig.Terrain.Hills do
		if math.sqrt((hill.X - portal.X) ^ 2 + (hill.Y - portal.Y) ^ 2) < hill.Z * 0.8 + ZoneConfig.PortalRadius then
			buriedOk = false
			print(("  la loma (%d, %d) tapa la tarima del portal"):format(hill.X, hill.Y))
		end
	end
	decorCheck("pueblo: ninguna loma entierra la tarima del portal", buriedOk)
	local safeOk = false
	for _, safe in EnemyConfig.Zones.Forest.SafeZones do
		safeOk = safeOk or ((safe.Center.X - VillageConfig.Safe.Center.X) ^ 2 + (safe.Center.Y - VillageConfig.Safe.Center.Y) ^ 2 < 1 and safe.Radius >= VillageConfig.Safe.Radius)
	end
	local coveredOk = true
	local safeCenter = VillageConfig.Safe.Center
	for _, item in footprints do
		local rect = rects[item.Name]
		local far
		if rect then
			far = 0
			for _, cx in { rect.MinX, rect.MaxX } do
				for _, cz in { rect.MinZ, rect.MaxZ } do
					far = math.max(far, math.sqrt((cx - safeCenter.X) ^ 2 + (cz - safeCenter.Y) ^ 2))
				end
			end
		else
			far = math.sqrt((item.X - safeCenter.X) ^ 2 + (item.Z - safeCenter.Y) ^ 2) + item.R
		end
		if far > VillageConfig.Safe.Radius + 1 then
			coveredOk = false
			print(("  %s queda fuera de la zona protegida"):format(item.Name))
		end
	end
	decorCheck("pueblo: zona protegida de los enemigos que lo cubre entero", safeOk and coveredOk)
	local panels = { Shop = true, Rewards = true, Quests = true }
	local panelsOk = panels[VillageConfig.Board.Panel] == true
	for _, building in VillageConfig.Buildings do
		if building.Panel and not panels[building.Panel] then
			panelsOk = false
		end
	end
	check("pueblo: los avisos abren paneles que existen (Tienda, Premios, Misiones)", panelsOk)
end

-- Naturaleza del norte (WildsConfig) y cofres escondidos (ChestConfig) ------------------
do
	local obstacles = LandscapeLayout.obstacles("Forest")
	local own = { WaterfallPool = true, WaterfallCliff = true, Lake = true, Ruins = true, Camp = true }
	local function isOwn(name)
		return own[name] or string.sub(name, 1, 6) == "Bridge" or string.sub(name, 1, 6) == "Chest_"
	end
	local others = {}
	for _, item in obstacles.Hard do
		if not isOwn(item.Name) then
			table.insert(others, item)
		end
	end
	local clashOk = true
	for _, item in WildsConfig.footprints() do
		local hit = insideAny(item.X, item.Z, item.R, others)
		if hit then
			clashOk = false
			print(("  %s choca con %s"):format(item.Name, hit))
		end
	end
	decorCheck("naturaleza: cascada, lago, ruinas, campamento y puente no pisan nada", clashOk)

	-- El agua no entra en la zona de ningún enemigo ni pisa lo que ya hay.
	local river = WildsConfig.River
	local maxHalf = (river.Width + 1.7) / 2
	local waterOk = true
	for index, spawn in EnemyConfig.Zones.Forest.Spawns do
		local leash = EnemyConfig.Types[spawn.Type].LeashRange
		local d = WildsConfig.distanceToRiver(spawn.Offset.X, spawn.Offset.Y) - maxHalf
		if d < leash then
			waterOk = false
			print(("  el río entra en la zona del enemigo %d (%s, %.1f)"):format(index, spawn.Type, d))
		end
	end
	local samples = WildsConfig.riverSamples(river.Step)
	for _, sample in samples do
		local hit = insideAny(sample.X, sample.Z, maxHalf, others)
		if hit and not string.find(hit, "Meadow") then
			waterOk = false
			print(("  el río pasa por %s en (%.0f, %.0f)"):format(hit, sample.X, sample.Z))
		end
	end
	decorCheck("naturaleza: el río no pasa por zonas de enemigos ni encima de nada", waterOk)

	-- Los caminos solo cruzan el agua por un puente.
	local crossOk = true
	local function onBridge(x, z)
		for _, bridge in WildsConfig.Bridges do
			if LandscapeLayout.distanceToSegment(x, z, bridge.From.X, bridge.From.Y, bridge.To.X, bridge.To.Y) < bridge.Width / 2 + 0.5 then
				return true
			end
		end
		return false
	end
	local function inWater(x, z)
		local fall, lake = WildsConfig.Waterfall.Pool, WildsConfig.Lake
		return WildsConfig.distanceToRiver(x, z) < maxHalf + 0.5
			or (x - fall.Center.X) ^ 2 + (z - fall.Center.Y) ^ 2 < fall.Radius ^ 2
			or (x - lake.Center.X) ^ 2 + (z - lake.Center.Y) ^ 2 < lake.Radius ^ 2
	end
	for _, path in LandscapeConfig.Forest.Paths do
		for index = 1, #path.Points - 1 do
			local p, q = path.Points[index], path.Points[index + 1]
			local length = math.sqrt((q.X - p.X) ^ 2 + (q.Y - p.Y) ^ 2)
			for step = 0, math.ceil(length) do
				local t = step / math.max(1, math.ceil(length))
				local x, z = p.X + (q.X - p.X) * t, p.Y + (q.Y - p.Y) * t
				if inWater(x, z) and not onBridge(x, z) then
					crossOk = false
					print(("  el camino %s se mete en el agua en (%.0f, %.0f)"):format(path.Name, x, z))
					break
				end
			end
		end
	end
	decorCheck("naturaleza: los caminos cruzan el río solo por el puente", crossOk)

	-- El puente: sobre el río, más largo que el agua y sus orillas, y en un camino.
	local bridgeOk = #WildsConfig.Bridges > 0
	for _, bridge in WildsConfig.Bridges do
		local mx, mz = (bridge.From.X + bridge.To.X) / 2, (bridge.From.Y + bridge.To.Y) / 2
		local length = math.sqrt((bridge.From.X - bridge.To.X) ^ 2 + (bridge.From.Y - bridge.To.Y) ^ 2)
		local onTrail = function(point)
			return LandscapeLayout.distanceToPaths(point.X, point.Y, LandscapeConfig.Forest.Paths) < 0
		end
		if WildsConfig.distanceToRiver(mx, mz) > 1.5 or length < 2 * maxHalf + 2 * river.Bank or not onTrail(bridge.From) or not onTrail(bridge.To) then
			bridgeOk = false
			print("  puente mal colocado: " .. bridge.Name)
		end
	end
	decorCheck("naturaleza: el puente cruza el río de orilla a orilla en un camino", bridgeOk)

	-- Piedras de la poza: se saltan de una a otra y llevan a la repisa de detrás del agua.
	local fall = WildsConfig.Waterfall
	local stones = fall.Stones
	local jumpsOk = true
	for index = 2, #stones do
		local gap = math.sqrt((stones[index].X - stones[index - 1].X) ^ 2 + (stones[index].Y - stones[index - 1].Y) ^ 2)
		if gap > 6.5 then
			jumpsOk = false
		end
	end
	local falls = nil
	for _, path in LandscapeConfig.Forest.Paths do
		if path.Name == "FallsTrail" then
			falls = path.Points[#path.Points]
		end
	end
	local firstGap = if falls then math.sqrt((stones[1].X - falls.X) ^ 2 + (stones[1].Y - falls.Y) ^ 2) else math.huge
	local ledgeZ = fall.FaceZ + fall.LedgeDepth / 2
	local lastGap = math.sqrt((stones[#stones].X - fall.X) ^ 2 + (stones[#stones].Y - ledgeZ) ^ 2)
	decorCheck(("naturaleza: piedras a saltos cortos del sendero (%.1f) a la repisa (%.1f)"):format(firstGap, lastGap), jumpsOk and firstGap < 7 and lastGap < 4.5)

	-- Praderas fuera de las zonas de juego.
	local gameplay = {}
	for _, item in obstacles.Hard do
		local n = item.Name
		if n == "Arena" or n == "EggGarden" or n == "Egg" or string.sub(n, 1, 5) == "Spawn" or string.sub(n, 1, 4) == "Npc_" or string.sub(n, 1, 5) == "Item_" or string.sub(n, 1, 7) == "Village" or string.find(n, "Portal") then
			table.insert(gameplay, item)
		end
	end
	local meadowsOk = true
	for _, meadow in WildsConfig.Meadows do
		local hit = insideAny(meadow.Center.X, meadow.Center.Y, meadow.Radius, gameplay)
		if hit or math.sqrt(meadow.Center.X ^ 2 + meadow.Center.Y ^ 2) + meadow.Radius > LandscapeConfig.Forest.BoundaryRadius - 20 then
			meadowsOk = false
			print(("  la pradera %s pisa %s"):format(meadow.Name, tostring(hit)))
		end
	end
	decorCheck("naturaleza: las praderas no pisan zonas de juego", meadowsOk)

	-- Lomas nuevas (colinas pequeñas del interior): lejos de lo que tiene altura fija.
	local hillsOk = true
	for _, hill in WorldConfig.Terrain.Hills do
		if hill.Z <= 30 then
			local hit = insideAny(hill.X, hill.Y, hill.Z * 0.8, gameplay)
			if hit then
				hillsOk = false
				print(("  la loma (%d, %d) pisa %s"):format(hill.X, hill.Y, hit))
			end
		end
	end
	decorCheck("naturaleza: las lomas no levantan zonas de juego", hillsOk)

	-- Cofres: dentro del mapa, fuera del agua, de los caminos y de las zonas de juego.
	local chestsOk = true
	local pond = LandscapeConfig.Forest.Pond
	for _, chest in ChestConfig.Chests do
		local x, z = chest.Position.X, chest.Position.Y
		local reason = nil
		if math.sqrt(x * x + z * z) > LandscapeConfig.Forest.BoundaryRadius - 12 then
			reason = "fuera del mapa"
		elseif chest.Ledge then
			local onLedge = math.abs(x - fall.X) < fall.Width / 2 + 1 and z > fall.FaceZ + 0.6 and z < fall.FaceZ + fall.LedgeDepth - 0.6
			reason = if onLedge then nil else "fuera de la repisa de la cascada"
		elseif inWater(x, z) or (x - pond.Center.X) ^ 2 + (z - pond.Center.Y) ^ 2 < (pond.Radius + 2) ^ 2 then
			reason = "en el agua"
		elseif LandscapeLayout.distanceToPaths(x, z, LandscapeConfig.Forest.Paths) < 1.5 then
			reason = "encima de un camino"
		else
			reason = insideAny(x, z, 1.5, gameplay)
		end
		if reason then
			chestsOk = false
			print(("  cofre %s: %s"):format(chest.Id, reason))
		end
	end
	check(("naturaleza: %d cofres en sitios despejados"):format(#ChestConfig.Chests), chestsOk)
	-- Nada del paisaje al azar encima de un cofre.
	local layout = LandscapeLayout.compute("Forest")
	local coveredOk = true
	for _, chest in ChestConfig.Chests do
		for _, item in layout.Scatter do
			if item.Solid and (item.X - chest.Position.X) ^ 2 + (item.Z - chest.Position.Y) ^ 2 < (item.R + 2) ^ 2 then
				coveredOk = false
				print(("  cofre %s tapado por %s"):format(chest.Id, item.Kind))
			end
		end
	end
	decorCheck("naturaleza: ningún árbol ni roca tapa un cofre", coveredOk)
end

if omitted > 0 then
	print(("(%d comprobaciones del paisaje decorativo omitidas: LandscapeConfig.BuildsDecor = false)"):format(omitted))
end
print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
