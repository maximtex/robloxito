GeneratorService.start()

local failures = 0
local function check(name, ok)
	if not ok then failures += 1 end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local origin = GeneratorConfig.Position
local model = workspace:FindFirstChild(GeneratorConfig.ModelName)
local function parts(container)
	local out = {}
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then table.insert(out, d) end
	end
	return out
end
-- Esquinas reales de una pieza (bloques) o su esfera envolvente (bolas y cilindros).
local function corners(part)
	local s = part.Size
	local out = {}
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(out, part.CFrame * Vector3.new(x * s.X / 2, y * s.Y / 2, z * s.Z / 2))
			end
		end
	end
	return out
end
-- Puntos de muestra de una pieza (esquinas, centros de caras y aristas) para distancias.
local function samples(part)
	local s = part.Size
	local out = {}
	for _, x in { -1, 0, 1 } do
		for _, y in { -1, 0, 1 } do
			for _, z in { -1, 0, 1 } do
				table.insert(out, part.CFrame * Vector3.new(x * s.X / 2, y * s.Y / 2, z * s.Z / 2))
			end
		end
	end
	return out
end
local function flatRadius(part) -- radio horizontal máximo de la pieza respecto a su centro
	local r = 0
	for _, c in corners(part) do
		local d = c - part.CFrame.Position
		r = math.max(r, math.sqrt(d.X * d.X + d.Z * d.Z))
	end
	return r
end

print("-- 1. Contrato con los demás sistemas")
check("modelo EnergyGenerator en Workspace con PrimaryPart = Dais", model ~= nil and model.PrimaryPart == model.Dais)
local core = model.Core
check("Core con PointLight (Tint Light) y ParticleEmitter (Tint Particles, StageRate)", core:FindFirstChildOfClass("PointLight") ~= nil and core:FindFirstChildOfClass("PointLight"):GetAttribute("Tint") == "Light" and core:FindFirstChildOfClass("ParticleEmitter"):GetAttribute("StageRate") == true)
check("Shell existe (Tint Shell)", model.Shell ~= nil and model.Shell:GetAttribute("Tint") == "Shell")
check(("Orbiters con %d fragmentos"):format(GeneratorConfig.OrbiterCount), #model.Orbiters:GetChildren() == GeneratorConfig.OrbiterCount)
local stageGroups = {}
for _, stage in GeneratorConfig.Evolution.Stages do
	for _, name in stage.Details do stageGroups[name] = true end
end
local missing = {}
for name in stageGroups do
	if not model.StageDetails:FindFirstChild(name) then table.insert(missing, name) end
end
check(("StageDetails contiene los %d grupos que usan las etapas"):format((function() local n = 0 for _ in stageGroups do n += 1 end return n end)()), #missing == 0)
check(("Fragments de la etapa Dorada: %d"):format(GeneratorConfig.Evolution.FragmentCount), #model.StageDetails.Fragments:GetChildren() == GeneratorConfig.Evolution.FragmentCount)
local validTints = { Core = true, Shell = true, Runes = true, Shards = true, Light = true, Particles = true }
local badTint = 0
for _, d in model:GetDescendants() do
	local tint = d:GetAttribute("Tint")
	if tint ~= nil and not validTints[tint] then badTint += 1 end
	if tint ~= nil and tint ~= "Particles" and GeneratorConfig.Evolution.Stages[1][tint] == nil then badTint += 1 end
end
check("todos los atributos Tint existen en las etapas", badTint == 0)
local stageOK = true
for _, stage in GeneratorConfig.Evolution.Stages do
	for _, key in { "Core", "Shell", "Light", "Runes", "Shards" } do
		if stage[key] == nil then stageOK = false end
	end
end
check("las cuatro etapas de evolución siguen definidas", #GeneratorConfig.Evolution.Stages == 4 and stageOK)
check("la etapa 1 usa la paleta turquesa #20E5D1", GeneratorConfig.Evolution.Stages[1].Core.R == 32 and GeneratorConfig.Evolution.Stages[1].Core.G == 229 and GeneratorConfig.Evolution.Stages[1].Core.B == 209)

print("-- 2. Detalles de etapa ocultos y sin colisión")
local hiddenOK = true
for _, d in model.StageDetails:GetDescendants() do
	if d:IsA("BasePart") and (d.Transparency ~= 1 or d.CanCollide ~= false or d:GetAttribute("VisibleTransparency") == nil) then hiddenOK = false end
	if d.ClassName == "ParticleEmitter" and d.Enabled ~= false then hiddenOK = false end
end
check("todo StageDetails empieza oculto, sin colisión y con emisores apagados", hiddenOK)

print("-- 3. Colisiones: solo la plataforma y los pilares son sólidos")
local SOLID = { Dais = true, DaisLip = true, Tier = true }
local wrong = {}
local solids = {}
for _, p in parts(model) do
	local structural = SOLID[p.Name] or p.Name:match("^Plinth%d$") or p.Name:match("^Pillar%d$") or p.Name:match("^Cap%d$")
	if structural then
		table.insert(solids, p)
		if p.CanCollide == false then table.insert(wrong, p.Name .. " debería ser sólido") end
	elseif p.CanCollide ~= false or p.CanQuery ~= false or p.CanTouch ~= false then
		table.insert(wrong, p.Name)
	end
	if p.Anchored ~= true then table.insert(wrong, p.Name .. " sin anclar") end
end
check(("decorativo sin colisión/consultas/toques y todo anclado (%d piezas sólidas)"):format(#solids), #wrong == 0)
if #wrong > 0 then print("   ", table.concat(wrong, ", ", 1, math.min(#wrong, 8))) end

print("-- 4. Escala y respeto del mapa")
local dais, lip = model.Dais, model.DaisLip
check("plataforma de 30 studs de diámetro", dais.Size.Y == 30 and dais.Size.Z == 30)
local daisTop = dais.CFrame.Position.Y + dais.Size.X / 2 - origin.Y
local lipTop = lip.CFrame.Position.Y + lip.Size.X / 2 - origin.Y
check(("se sube andando: escalones de %.2f y %.2f studs (<= 1)"):format(lipTop, daisTop - lipTop), lipTop <= 1 and daisTop - lipTop <= 1)
-- Zonas que deben quedar libres (WorldConfig.KeepClear: spawn, jardín de huevos, portal, arco)
local invaded = {}
local lipRadius = lip.Size.Y / 2
for _, zone in WorldConfig.KeepClear do
	local center = Vector3.new(origin.X + zone.X, 0, origin.Z + zone.Y)
	local isArch = zone.X == 0 and zone.Y == WorldConfig.RuinArch.Z
	local d = (Vector3.new(origin.X, 0, origin.Z) - center).Magnitude
	-- El suelo de la plataforma puede pisar la zona del arco (es el camino); nada más.
	if not isArch and d < zone.Z + lipRadius then table.insert(invaded, ("plataforma en (%d,%d)"):format(zone.X, zone.Y)) end
	for _, p in parts(model) do
		if not SOLID[p.Name] and p.Transparency < 1 then
			local pos = p.CFrame.Position
			local pd = (Vector3.new(pos.X, 0, pos.Z) - center).Magnitude
			-- Incrustaciones planas del suelo (runas, glifos, musgo): son parte del suelo
			-- de la plataforma, que sí puede pisar la zona del arco (el camino).
			local top = -math.huge
			for _, c in corners(p) do top = math.max(top, c.Y) end
			local floorInlay = top <= origin.Y + daisTop + 0.3
			if not (isArch and floorInlay) and pd < zone.Z + flatRadius(p) * 0.5 then table.insert(invaded, ("%s en (%d,%d)"):format(p.Name, zone.X, zone.Y)) end
		end
	end
end
check("no invade el spawn, el jardín de huevos, el portal ni el arco", #invaded == 0)
if #invaded > 0 then print("   ", table.concat(invaded, ", ", 1, math.min(#invaded, 8))) end
-- Accesos: desde el centro hacia el spawn (de ahí sale el sendero al Jardín de los Huevos,
-- EggConfig.Gardens) y hacia el árbol, sin pilares.
local blocked = {}
local garden = EggConfig.Gardens.Forest
check("el Jardín de los Huevos queda fuera de la plataforma", math.sqrt(garden.Center.X ^ 2 + garden.Center.Y ^ 2) - garden.Radius > dais.Size.Y / 2 + 5)
local targets = { { "spawn", 0, 25 }, { "árbol ancestral", 0, -52 } }
for _, target in targets do
	local dir = Vector3.new(target[2], 0, target[3]).Unit
	for _, p in solids do
		if p.Name:match("^Pillar") or p.Name:match("^Plinth") or p.Name:match("^Cap") then
			local rel = p.CFrame.Position - origin
			local along = rel.X * dir.X + rel.Z * dir.Z
			local lateral = math.abs(rel.X * dir.Z - rel.Z * dir.X)
			if along > 0 and lateral < flatRadius(p) + 1.5 then table.insert(blocked, target[1] .. " por " .. p.Name) end
		end
	end
end
check("accesos abiertos hacia el spawn (y su sendero al jardín de huevos) y el árbol ancestral", #blocked == 0)
if #blocked > 0 then print("   ", table.concat(blocked, ", ")) end

print("-- 5. Cristal flotante")
local body = parts(model.CrystalBody)
local minY, maxY = math.huge, -math.huge
for _, p in body do
	for _, c in corners(p) do
		minY = math.min(minY, c.Y)
		maxY = math.max(maxY, c.Y)
	end
end
local floatGap = minY - (origin.Y + daisTop + 0.35)
check(("altura del cristal %.1f studs (8–10)"):format(maxY - minY), maxY - minY >= 8 and maxY - minY <= 10.5)
check(("flota %.1f studs sobre el estrado (5–7)"):format(floatGap), floatGap >= 5 and floatGap <= 7)
local crystalCenter = core.CFrame.Position
check("el núcleo está en el centro del cristal (y la flecha del tutorial apunta ahí)", math.abs(crystalCenter.Y - (origin.Y + GeneratorConfig.CoreHeight)) < 1e-6)
local silhouette = 0
for _, p in body do silhouette += 1 end
check(("silueta facetada: %d piezas de cristal (no un bloque)"):format(silhouette), silhouette >= 6)

print("-- 6. Órbitas: sin cruces y movimiento suave")
local crystalPoints = {}
for _, p in body do
	for _, s in samples(p) do table.insert(crystalPoints, s - crystalCenter) end
end
local shellRadius = GeneratorConfig.ShellDiameter / 2
local halves = {}
for i, orbit in GeneratorConfig.Orbits do halves[i] = orbit.Size.Y / 2 end
local function orbitPos(i, t)
	local x, y, z = GeneratorConfig.orbitOffset(GeneratorConfig.Orbits[i], t)
	return Vector3.new(x, y, z)
end
local minCrystal, minPair, minShell, maxStep, minRing = math.huge, math.huge, math.huge, 0, math.huge
local previous = {}
local evo = GeneratorConfig.Evolution
for frame = 0, 60 * 600 do -- 10 minutos a 60 fps
	local t = frame / 60
	local positions = {}
	for i = 1, #GeneratorConfig.Orbits do
		local pos = orbitPos(i, t)
		positions[i] = pos
		for _, point in crystalPoints do
			minCrystal = math.min(minCrystal, (pos - point).Magnitude - halves[i])
		end
		minShell = math.min(minShell, pos.Magnitude - halves[i] - shellRadius)
		if previous[i] then maxStep = math.max(maxStep, (pos - previous[i]).Magnitude) end
		previous[i] = pos
	end
	for i = 1, #positions do
		for j = i + 1, #positions do
			minPair = math.min(minPair, (positions[i] - positions[j]).Magnitude - halves[i] - halves[j])
		end
		-- y lejos de la corona de chispas de la etapa Dorada
		for k = 1, evo.FragmentCount do
			local a = t * evo.FragmentOrbitSpeed + (k - 1) / evo.FragmentCount * math.pi * 2
			local ring = Vector3.new(math.cos(a) * evo.FragmentOrbitRadius, evo.FragmentHeight, math.sin(a) * evo.FragmentOrbitRadius)
			minRing = math.min(minRing, (positions[i] - ring).Magnitude - halves[i] - 0.6)
		end
	end
end
check(("fragmentos nunca atraviesan el cristal (holgura mínima %.2f studs)"):format(minCrystal), minCrystal > 0.3)
check(("ni el halo de energía (holgura %.2f)"):format(minShell), minShell > 0.3)
check(("ni se cruzan entre sí (holgura mínima %.2f studs)"):format(minPair), minPair > 0.2)
check(("ni con la corona de chispas dorada (holgura %.2f)"):format(minRing), minRing > 0.2)
check(("movimiento continuo: como mucho %.3f studs por fotograma a 60 fps"):format(maxStep), maxStep < 0.1)
local differentSpeeds = GeneratorConfig.Orbits[1].Speed ~= GeneratorConfig.Orbits[2].Speed and GeneratorConfig.Orbits[2].Speed ~= GeneratorConfig.Orbits[3].Speed
local differentTilts = GeneratorConfig.Orbits[1].Tilt ~= GeneratorConfig.Orbits[2].Tilt and GeneratorConfig.Orbits[2].Tilt ~= GeneratorConfig.Orbits[3].Tilt
check("órbitas con inclinaciones, velocidades y tamaños distintos", differentSpeeds and differentTilts and halves[1] ~= halves[2] and halves[2] ~= halves[3])
-- Las órbitas no bajan hasta los pilares ni las rocas flotantes
local lowest = math.huge
for i = 1, #GeneratorConfig.Orbits do
	for frame = 0, 600 do
		local p = orbitPos(i, frame / 10)
		local horizontal = math.sqrt(p.X * p.X + p.Z * p.Z)
		if horizontal > 10 then lowest = math.min(lowest, crystalCenter.Y + p.Y - halves[i]) end
	end
end
local highestRock = 0
for _, rock in model.FloatingRocks:GetChildren() do
	highestRock = math.max(highestRock, rock.CFrame.Position.Y + rock.Size.Y)
end
check(("sobre los pilares y las rocas los fragmentos pasan por encima (%.1f > %.1f)"):format(lowest, highestRock + GeneratorConfig.Animation.RockBobHeight), lowest > highestRock + GeneratorConfig.Animation.RockBobHeight)

print("-- 7. Animación real (GeneratorAnimator)")
GeneratorAnimator.start()
heartbeat(1.1) -- busca el modelo
local before = {}
for _, p in parts(model) do before[p] = p.CFrame.Position end
for _ = 1, 120 do heartbeat(1 / 60) end
check("un único BulkMoveTo por fotograma", bulkMoves == 120)
local moved = 0
for _, p in parts(model.Orbiters) do if (p.CFrame.Position - before[p]).Magnitude > 0.01 then moved += 1 end end
check("los tres fragmentos se mueven", moved == 3)
-- El cristal se mueve como un bloque rígido: distancias internas constantes
local rigid = true
local corePos = model.Core.CFrame.Position
for _, p in body do
	local d0 = (before[p] - before[model.Core]).Magnitude
	local d1 = (p.CFrame.Position - corePos).Magnitude
	if math.abs(d0 - d1) > 1e-6 then rigid = false end
end
check("el cristal flota y gira como una sola pieza (no se deforma)", rigid)
local platformStill = model.Dais.CFrame.Position == before[model.Dais] and model.Pillars.Pillar1.CFrame.Position == before[model.Pillars.Pillar1]
check("la plataforma y los pilares no se mueven", platformStill)
local rockMoved = 0
for _, rock in model.FloatingRocks:GetChildren() do if (rock.CFrame.Position - before[rock]).Magnitude > 0.001 then rockMoved += 1 end end
check("las rocas flotantes se balancean", rockMoved == #model.FloatingRocks:GetChildren())

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
