-- Enemigos de la Zona 1 (Bosque) con los modelos 3D animados de Santiago (los .glb hechos de
-- bloques, con sus animaciones Idle, Walk, Attack, Hit y Death):
--   Arbolito          -> Espinillo y Espinillo Bebé (este, más pequeño)
--   ArbolGuardian     -> Bruto de Corteza
--   GiganteDelBosque  -> Guardián del Bosque (jefe)
-- Los bloques y los huesos salen de ModelosZona1Data (generado a partir de los .glb). Aquí se
-- escalan a studs y se arman como los demás enemigos de EnemyService: el estilo (EnemyConfig
-- Look.Style) elige el modelo, SHAPES da la raíz / cadera / radio / barra y BUILDERS lo
-- construye.
--
-- Animación: cada hueso del .glb (rig, caderas, tronco, hombros, codos y copa) es una pieza
-- invisible dentro de la carpeta "Huesos", unida a su hueso padre con un Motor6D "Joint" (el
-- primero, a la raíz del enemigo). Los bloques van soldados a su hueso. El cliente
-- (EnemyAnimator) reproduce las animaciones de Shared.ClipsZona1 escribiendo el Transform de
-- esos Motor6D. Los huesos van en una carpeta para que addJoints (EnemyService) no les ponga
-- además las articulaciones "Pose" de los enemigos de siempre.
--
-- ModelosZona1.buildStatic(nombre) devuelve el modelo suelto y anclado (para verlo o
-- reutilizarlo fuera de los enemigos: ServerStorage.ModelosEnemigos).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Data = require(script.Parent.ModelosZona1Data)
local Clips = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClipsZona1"))

local ModelosZona1 = {}

-- Estilos (EnemyConfig Look.Style). Scale: studs por unidad del .glb.
-- Root / Hip / Radius / BarHeight: como SHAPES de EnemyService, para este tamaño.
ModelosZona1.Styles = {
	Arbolito = { Model = "Arbolito", Scale = 3.2, Root = Vector3.new(2.4, 2.4, 2.4), Hip = 0.8, Radius = 1.9, BarHeight = 6.6 },
	ArbolitoBebe = { Model = "Arbolito", Scale = 2.6, Root = Vector3.new(2, 2, 2), Hip = 0.6, Radius = 1.6, BarHeight = 5.5 },
	ArbolGuardian = { Model = "ArbolGuardian", Scale = 3.2, Root = Vector3.new(3, 3.6, 2.4), Hip = 1.6, Radius = 2.6, BarHeight = 10.4 },
	GiganteDelBosque = { Model = "GiganteDelBosque", Scale = 4, Root = Vector3.new(5, 7, 4), Hip = 3, Radius = 4.5, BarHeight = 18.6 },
}

-- Cuánto deja el servidor el cuerpo tras morir: lo que dura la animación Death y un poco más
-- (el cliente lo disuelve al final de la animación).
local DEATH_EXTRA = 0.25

-- Boxes viene comprimido (ver ModelosZona1Data): se descomprime una vez por modelo.
type Box = { Joint: number, Color: number, Position: Vector3, Size: Vector3, Rotation: { number }? }

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, #ALPHABET do
	VALUE[string.byte(ALPHABET, i)] = i - 1
end

local decoded: { [string]: { Box } } = {}

local function boxesOf(modelName: string): { Box }
	local cached = decoded[modelName]
	if cached then
		return cached
	end
	local s = Data[modelName].Boxes
	local i = 1
	local function read(): number
		local v = VALUE[string.byte(s, i)] * 64 + VALUE[string.byte(s, i + 1)]
		i += 2
		return v
	end
	local function length(): number
		return (read() - 1024) * 0.002
	end
	local boxes = {}
	while i <= #s do
		local joint = VALUE[string.byte(s, i)] + 1
		local color = VALUE[string.byte(s, i + 1)] + 1
		i += 2
		local position = Vector3.new(length(), length(), length())
		local size = Vector3.new(length(), length(), length())
		local flag = string.sub(s, i, i)
		i += 1
		local rotation = nil
		if flag == "q" then
			rotation = { read() / 2047 - 1, read() / 2047 - 1, read() / 2047 - 1, read() / 2047 - 1 }
		end
		table.insert(boxes, { Joint = joint, Color = color, Position = position, Size = size, Rotation = rotation })
	end
	assert(#boxes == Data[modelName].Count, "ModelosZona1Data: bloques incompletos en " .. modelName)
	decoded[modelName] = boxes
	return boxes
end

local function boxCFrame(box: Box, scale: number): CFrame
	local p = box.Position * scale
	local q = box.Rotation
	if q then
		return CFrame.new(p.X, p.Y, p.Z, q[1], q[2], q[3], q[4])
	end
	return CFrame.new(p)
end

local function block(parent: Instance, box: Box, scale: number, palette, anchored: boolean): Part
	local entry = palette[box.Color]
	local glow = entry[3]
	local part = Instance.new("Part")
	part.Name = entry[1]
	part.Size = box.Size * scale
	part.CFrame = boxCFrame(box, scale)
	part.Color = entry[2]
	part.Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = anchored
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true -- se puede seleccionar el enemigo haciendo clic en cualquier bloque
	part.Massless = true
	part.CastShadow = not glow
	part.Parent = parent
	return part
end

-- Pose de reposo de un hueso, en studs.
local function jointCFrame(joint, scale: number): CFrame
	local p = joint[3]
	return CFrame.new(p[1] * scale, p[2] * scale, p[3] * scale, p[4], p[5], p[6], p[7])
end

function ModelosZona1.deathSeconds(modelName: string): number
	local set = Clips[modelName]
	local death = set and set.Clips.Death
	return (if death then death.Length else 1) + DEATH_EXTRA
end

function ModelosZona1.shapeOf(styleName: string)
	local style = ModelosZona1.Styles[styleName]
	return {
		Root = style.Root,
		Hip = style.Hip,
		Radius = style.Radius,
		BarHeight = style.BarHeight,
		-- addJoints no encuentra piezas sueltas (van en carpetas): basta con el cuerpo.
		Pivots = { Body = Vector3.zero },
		DeathSeconds = ModelosZona1.deathSeconds(style.Model),
	}
end

-- Construye el estilo dentro de un rig de EnemyService ({ Model, Root, Eyes, ... }).
function ModelosZona1.buildInto(rig, styleName: string)
	local style = ModelosZona1.Styles[styleName]
	local model = Data[style.Model]
	local scale = style.Scale

	local bones = Instance.new("Folder")
	bones.Name = "Huesos"
	bones.Parent = rig.Model
	local cores: { BasePart } = {}
	for index, joint in model.Joints do
		local part = Instance.new("Part")
		part.Name = joint[1]
		part.Size = Vector3.one * 0.2
		part.CFrame = jointCFrame(joint, scale)
		part.Transparency = 1
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.Parent = bones
		cores[index] = part
	end
	-- Cada hueso cuelga de su padre (el primero, de la raíz) con un Motor6D en reposo.
	for index, joint in model.Joints do
		local parentPart = if joint[2] == 0 then rig.Root else cores[joint[2]]
		local motor = Instance.new("Motor6D")
		motor.Name = "Joint"
		motor.Part0 = parentPart
		motor.Part1 = cores[index]
		motor.C0 = parentPart.CFrame:ToObjectSpace(cores[index].CFrame)
		motor.C1 = CFrame.identity
		motor:SetAttribute("JointIndex", index)
		motor.Parent = cores[index]
	end

	local pieces = Instance.new("Folder")
	pieces.Name = "Piezas"
	pieces.Parent = rig.Model
	local eyes = {}
	for _, index in model.Eyes do
		eyes[index] = true
	end
	for index, box in boxesOf(style.Model) do
		local part = block(pieces, box, scale, model.Palette, false)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = cores[box.Joint]
		weld.Part1 = part
		weld.Parent = part
		if eyes[index] then
			table.insert(rig.Eyes, part) -- se ponen rojos al preparar un golpe
		end
	end

	-- Para el cliente: qué animaciones usar y a qué escala.
	rig.Model:SetAttribute("Clips", style.Model)
	rig.Model:SetAttribute("ClipScale", scale)
	rig.Model:SetAttribute("DeathSeconds", ModelosZona1.deathSeconds(style.Model))
end

-- Registra los estilos en las tablas de EnemyService (las llama una vez al cargar).
function ModelosZona1.register(builders, shapes)
	for styleName in ModelosZona1.Styles do
		shapes[styleName] = ModelosZona1.shapeOf(styleName)
		builders[styleName] = function(rig, _look)
			ModelosZona1.buildInto(rig, styleName)
		end
	end
end

-- Modelo suelto y anclado, con el suelo en Y = 0 y el frente hacia -Z (en su pose de reposo).
function ModelosZona1.buildStatic(modelName: string, scale: number?): Model
	local model = Data[modelName]
	local s = scale or ModelosZona1.Styles[modelName].Scale
	local result = Instance.new("Model")
	result.Name = modelName
	for _, box in boxesOf(modelName) do
		block(result, box, s, model.Palette, true)
	end
	result:SetAttribute("Fuente", model.Source)
	return result
end

return ModelosZona1
