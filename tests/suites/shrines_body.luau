-- Círculo Elemental: construye los altares con el CoreShrineService real (entorno
-- simulado del santuario) y comprueba el contrato con el cliente y el respeto del mapa.
CoreShrineService.start()

local failures = 0
local function check(name, ok)
	if not ok then failures += 1 end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function parts(container)
	local out = {}
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") then table.insert(out, d) end
	end
	return out
end
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
local function flatDistance(ax, az, bx, bz)
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end
-- Puntos del contorno real de una pieza: círculo para bolas y cilindros verticales,
-- elipse para elipsoides (SpecialMesh) y esquinas para bloques.
local function outline(part)
	local s = part.Size
	local out = {}
	local round = part.Shape == "PartType.Ball" or part.Shape == "PartType.Cylinder"
	local ellipsoid = part:FindFirstChildOfClass("SpecialMesh") ~= nil
	if round or ellipsoid then
		local rx, rz
		if part.Shape == "PartType.Cylinder" then
			rx, rz = s.Y / 2, s.Z / 2 -- de pie: el eje del cilindro (X) es la altura
		else
			rx, rz = s.X / 2, s.Z / 2
		end
		for step = 0, 15 do
			local a = step * math.pi / 8
			table.insert(out, part.CFrame * Vector3.new(math.cos(a) * rx, 0, math.sin(a) * rz))
		end
		table.insert(out, part.CFrame.Position)
		return out
	end
	return corners(part)
end
-- Distancia horizontal mínima de una pieza a un punto.
local function partDistance(part, x, z)
	local best = math.huge
	for _, c in outline(part) do
		best = math.min(best, flatDistance(c.X, c.Z, x, z))
	end
	return best
end

local origin = GeneratorConfig.Position
local root = workspace:FindFirstChild(CoreShrineConfig.ModelName)
local altars = {}
local expected = {}
for order, elementId in CoreConfig.Order do
	if elementId ~= CoreConfig.DefaultElement then
		expected[elementId] = order
	end
end

print("-- 1. Contrato con el cliente (CoreShrineController)")
check("modelo ElementalCores en Workspace", root ~= nil)
local count, named = 0, true
for _, child in root:GetChildren() do
	count += 1
	altars[child.Name] = child
	if expected[child.Name] == nil or child:GetAttribute("Element") ~= child.Name or child:GetAttribute("Order") ~= expected[child.Name] then
		named = false
	end
end
check(("un altar por núcleo distinto de Naturaleza (%d)"):format(count), count == 7 and named)
local configOK = true
for elementId in expected do
	local look = CoreShrineConfig.Elements[elementId]
	if CoreShrineConfig.Angles[elementId] == nil or not look or not look.Color or not look.Glow or not look.Motif then
		configOK = false
	end
end
local angleCount = 0
for elementId in CoreShrineConfig.Angles do
	angleCount += 1
	if expected[elementId] == nil then configOK = false end
end
check("CoreShrineConfig define ángulo, colores y motivo de los siete (y nada más)", configOK and angleCount == 7)

local structureOK, missing = true, {}
for elementId, altar in altars do
	local crystal = altar:FindFirstChild("Crystal")
	local orbiters = altar:FindFirstChild("Orbiters")
	local motif = altar:FindFirstChild("Motif")
	local cap = altar:FindFirstChild("ColumnCap")
	local label = cap and cap:FindFirstChild("Label")
	local ok = altar.PrimaryPart == altar:FindFirstChild("Base")
		and crystal ~= nil and crystal:FindFirstChild("CrystalBody") ~= nil and #crystal:GetChildren() == 3
		and orbiters ~= nil and #orbiters:GetChildren() >= 3
		and motif ~= nil and #motif:GetChildren() >= 8
		and label ~= nil and label:FindFirstChild("Title") ~= nil and label:FindFirstChild("State") ~= nil
	if not ok then
		structureOK = false
		table.insert(missing, elementId)
	end
end
check("cada altar: Base (PrimaryPart), Crystal (3 piezas), Orbiters, Motif y rótulo", structureOK)
if #missing > 0 then print("   ", table.concat(missing, ", ")) end

local heightsOK = true
for _, altar in altars do
	local restY, floatY = altar:GetAttribute("RestY"), altar:GetAttribute("FloatY")
	if type(restY) ~= "number" or type(floatY) ~= "number" or floatY - restY < 1 then heightsOK = false end
end
check("RestY y FloatY: el cristal sube al menos 1 stud al despertar", heightsOK)

local VALID_TINT = { Crystal = true, Rune = true, Accent = true }
local tintOK, tinted = true, 0
for _, altar in altars do
	for _, p in parts(altar) do
		local kind = p:GetAttribute("ShrineTint")
		if kind ~= nil then
			tinted += 1
			local sleep = p:GetAttribute("SleepColor")
			if not VALID_TINT[kind] or p:GetAttribute("AwakeColor") == nil or sleep == nil
				or type(p:GetAttribute("AwakeMaterial")) ~= "string" or type(p:GetAttribute("SleepMaterial")) ~= "string"
				or p.Color ~= sleep or p.Material ~= "Material." .. p:GetAttribute("SleepMaterial") then
				tintOK = false
			end
		end
	end
end
check(("%d piezas teñibles con sus dos estados, construidas dormidas"):format(tinted), tintOK and tinted >= 7 * 6)

local offOK, awakeOnly = true, 0
for _, altar in altars do
	for _, d in altar:GetDescendants() do
		if d:GetAttribute("AwakeOnly") == true then
			awakeOnly += 1
			if d.Enabled ~= false then offOK = false end
		end
		if d.Name == "WakeBurst" and d.Enabled ~= false then offOK = false end
	end
end
check(("%d emisores y luces AwakeOnly empiezan apagados (y el destello de despertar)"):format(awakeOnly), offOK and awakeOnly >= 7 * 5)

print("-- 2. Colisiones")
local SOLID = { Base = true, Step = true, Column = true, ColumnCap = true }
local wrong = {}
for _, altar in altars do
	for _, p in parts(altar) do
		if SOLID[p.Name] then
			if p.CanCollide == false then table.insert(wrong, p.Name .. " debería ser sólido") end
		elseif p.CanCollide ~= false or p.CanQuery ~= false or p.CanTouch ~= false then
			table.insert(wrong, altar.Name .. "." .. p.Name)
		end
		if p.Anchored ~= true then table.insert(wrong, p.Name .. " sin anclar") end
	end
end
check("solo base, escalón y columna son sólidos; todo anclado", #wrong == 0)
if #wrong > 0 then print("   ", table.concat(wrong, ", ", 1, math.min(#wrong, 8))) end

print("-- 3. Respeto del mapa")
local footprint = CoreShrineConfig.FootprintRadius
local function intrusions(x, z, clearance)
	local out = {}
	for elementId, altar in altars do
		for _, p in parts(altar) do
			if partDistance(p, origin.X + x, origin.Z + z) < clearance then
				table.insert(out, elementId .. "." .. p.Name)
				break
			end
		end
	end
	return out
end

-- Dentro del radio de la base (no sobresale nada salvo el rótulo)
local spill = {}
for elementId, altar in altars do
	local base = altar.PrimaryPart.CFrame.Position
	for _, p in parts(altar) do
		for _, c in outline(p) do
			if flatDistance(c.X, c.Z, base.X, base.Z) > footprint + 0.05 then
				table.insert(spill, elementId .. "." .. p.Name)
				break
			end
		end
	end
end
check(("todo cabe en la base de radio %.1f"):format(footprint), #spill == 0)
if #spill > 0 then print("   ", table.concat(spill, ", ", 1, math.min(#spill, 8))) end

local platformRadius = GeneratorConfig.PlatformDiameter / 2
local nearest = math.huge
for elementId in altars do
	local offset = CoreShrineConfig.offset(elementId)
	nearest = math.min(nearest, math.sqrt(offset.X ^ 2 + offset.Y ^ 2) - footprint)
end
check(("pasillo de %.1f studs entre la plataforma del cristal y los altares (>= 2.5)"):format(nearest - platformRadius), nearest - platformRadius >= 2.5)

local closest = math.huge
local ids = {}
for elementId in altars do table.insert(ids, elementId) end
for i = 1, #ids do
	for j = i + 1, #ids do
		local a, b = CoreShrineConfig.offset(ids[i]), CoreShrineConfig.offset(ids[j])
		closest = math.min(closest, flatDistance(a.X, a.Y, b.X, b.Y) - 2 * footprint)
	end
end
check(("se puede pasar entre altares (hueco mínimo %.1f studs >= 2)"):format(closest), closest >= 2)

local blocked = {}
for _, zone in WorldConfig.KeepClear do
	for _, hit in intrusions(zone.X, zone.Y, zone.Z) do
		table.insert(blocked, ("%s en (%d,%d)"):format(hit, zone.X, zone.Y))
	end
end
check("no invade el spawn, el jardín de huevos, el portal ni el arco", #blocked == 0)
if #blocked > 0 then print("   ", table.concat(blocked, ", ")) end

for standId, stand in EggConfig.Stands do
	if (stand.Zone or ZoneConfig.DefaultZone) == ZoneConfig.DefaultZone then
		local hits = intrusions(stand.StandOffset.X, stand.StandOffset.Y, 7)
		check(("lejos del pedestal %s"):format(standId), #hits == 0)
	end
end

local scenery = {}
for index, tree in WorldConfig.Trees do
	for _, hit in intrusions(tree.X, tree.Y, 4.5 * tree.Z) do table.insert(scenery, "árbol " .. index .. ": " .. hit) end
end
for index, column in WorldConfig.RuinColumns do
	-- Las columnas caídas (altura 0) yacen hasta ~4 studs de su base.
	for _, hit in intrusions(column.X, column.Y, if column.Z == 0 then 4.5 else 2) do table.insert(scenery, "columna " .. index .. ": " .. hit) end
end
for index, cluster in WorldConfig.MushroomClusters do
	for _, hit in intrusions(cluster.X, cluster.Y, 2.2) do table.insert(scenery, "setas " .. index .. ": " .. hit) end
end
for index, cluster in WorldConfig.CrystalClusters do
	for _, hit in intrusions(cluster.X, cluster.Y, 1.6) do table.insert(scenery, "cristales " .. index .. ": " .. hit) end
end
for index, rock in WorldConfig.Terrain.Rocks do
	for _, hit in intrusions(rock.X, rock.Y, rock.Z) do table.insert(scenery, "roca " .. index .. ": " .. hit) end
end
local tree = WorldConfig.AncientTree
for _, hit in intrusions(tree.Position.X, tree.Position.Y, tree.RootReach + 1) do table.insert(scenery, "árbol ancestral: " .. hit) end
check("sin chocar con árboles, raíces, columnas, setas, cristales ni rocas", #scenery == 0)
if #scenery > 0 then print("   ", table.concat(scenery, ", ", 1, math.min(#scenery, 8))) end

local onPath = {}
local pathHalf = WorldConfig.Terrain.PathWidth / 2 + 1
for elementId, altar in altars do
	for _, p in parts(altar) do
		local rel = p.CFrame.Position - origin
		if math.abs(rel.X) < pathHalf + footprint and rel.Z > 0 and rel.Z < WorldConfig.Terrain.PathEndZ then
			table.insert(onPath, elementId)
			break
		end
	end
end
check("el camino del spawn al portal queda libre", #onPath == 0)

local forest = EnemyConfig.Zones.Forest
local nearEnemies = {}
for _, spawn in forest.Spawns do
	for _, hit in intrusions(spawn.Offset.X, spawn.Offset.Y, 25) do table.insert(nearEnemies, spawn.Type .. ": " .. hit) end
end
local arena = forest.Boss.Arena
for _, hit in intrusions(arena.Center.X, arena.Center.Y, arena.Radius + 10) do table.insert(nearEnemies, "arena: " .. hit) end
check("lejos de las apariciones de enemigos y de la arena del jefe", #nearEnemies == 0)
check("las flores respetan cada altar (KeepClearRadius >= radio de la base)", CoreShrineConfig.KeepClearRadius >= footprint)

print("-- 4. Cristal")
local restOK, floatOK, heightOK = true, true, true
for _, altar in altars do
	local cap = altar.ColumnCap
	local capTop = cap.CFrame.Position.Y + cap.Size.X / 2
	local minY, maxY = math.huge, -math.huge
	for _, p in parts(altar.Crystal) do
		for _, c in corners(p) do
			minY = math.min(minY, c.Y)
			maxY = math.max(maxY, c.Y)
		end
	end
	-- Dormido: la punta inferior encaja en el capitel, sin hundirse demasiado.
	if not (minY <= capTop + 0.02 and minY >= capTop - 0.6) then restOK = false end
	-- Despierto: flota con un hueco visible sobre el capitel.
	local lift = altar:GetAttribute("FloatY") - altar:GetAttribute("RestY")
	if minY + lift < capTop + 1 then floatOK = false end
	-- Más bajo que el Cristal del Renacimiento (protagonista del claro).
	if maxY + lift - origin.Y > GeneratorConfig.CoreHeight then heightOK = false end
end
check("dormido: el cristal reposa sobre el capitel", restOK)
check("despierto: flota al menos 1 stud sobre el capitel", floatOK)
check("los altares no superan la altura del Cristal del Renacimiento", heightOK)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
if failures > 0 then error("fallos") end
