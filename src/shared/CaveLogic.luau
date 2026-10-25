-- Lógica pura de la Cueva de los Espinillos por dentro (CaveConfig): en qué sala estás, si
-- pisas la boca de la cueva o un portal de salida, y las puertas entre salas (cuántos bichos
-- llevas, cuáles están abiertas y si un sitio queda detrás de una cerrada). Sin servicios: la
-- usan CaveService (viaje y puertas), SaveService (guardar el progreso), StyleService (la
-- embestida no cruza puertas cerradas), el cliente y las pruebas.

local CaveConfig = require(script.Parent.Config.CaveConfig)

local CaveLogic = {}

local function inRect(r, x: number, z: number, margin: number?): boolean
	local m = margin or 0
	return x > r.MinX - m and x < r.MaxX + m and z > r.MinZ - m and z < r.MaxZ + m
end
CaveLogic.inRect = inRect

-- Sala que contiene el punto (x, z) del mundo: (índice, sala) o nil.
function CaveLogic.roomAt(x: number, z: number): (number?, any)
	for index, room in CaveConfig.Rooms do
		if inRect(room.Rect, x, z) then
			return index, room
		end
	end
	return nil, nil
end

-- ¿Está (x, z) dentro de la cueva (una sala o un pasillo)? margin: studs de más alrededor.
function CaveLogic.inside(x: number, z: number, margin: number?): boolean
	for _, room in CaveConfig.Rooms do
		if inRect(room.Rect, x, z, margin) then
			return true
		end
	end
	for _, corridor in CaveConfig.Corridors do
		if inRect(corridor.Rect, x, z, margin) then
			return true
		end
	end
	return false
end

-- ¿Pisa `position` la boca de la cueva (el fondo del túnel)? floorY: cara de arriba del suelo.
function CaveLogic.inEntrance(position: Vector3, floorY: number): boolean
	local trigger = CaveConfig.Entrance.Trigger
	return inRect(trigger, position.X, position.Z) and position.Y < floorY + trigger.Height
end

-- Portal de salida junto a `position` (índice en CaveConfig.Exits) o nil.
function CaveLogic.exitAt(position: Vector3): number?
	for index, exit in CaveConfig.Exits do
		local dx, dz = position.X - exit.Position.X, position.Z - exit.Position.Z
		if dx * dx + dz * dz <= CaveConfig.ExitRadius * CaveConfig.ExitRadius then
			return index
		end
	end
	return nil
end

-- Centro (x, z) del mundo de la sala del altar de las oleadas.
function CaveLogic.altarCenter(): Vector2?
	for _, room in CaveConfig.Rooms do
		if room.Altar then
			return Vector2.new((room.Rect.MinX + room.Rect.MaxX) / 2, (room.Rect.MinZ + room.Rect.MaxZ) / 2)
		end
	end
	return nil
end

-- Puertas ---------------------------------------------------------------------------------
-- Progreso: bichos derrotados por puerta, { [índice de CaveConfig.Gates] = número }, con el
-- tope de lo que pide cada una (una abierta se queda abierta).

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Progreso guardado (o raro) -> uno válido.
function CaveLogic.sanitizeProgress(raw: any): { number }
	local result = {}
	for index, gate in CaveConfig.Gates do
		local value = if type(raw) == "table" then (raw[index] or raw[tostring(index)]) else nil
		result[index] = if finite(value) and value > 0 then math.min(math.floor(value), gate.Kills) else 0
	end
	return result
end

-- Para guardar: una lista seguida (sin huecos) con un número por puerta.
function CaveLogic.serializeProgress(progress: any): { number }
	return CaveLogic.sanitizeProgress(progress)
end

-- Para el atributo del jugador: "15,3".
function CaveLogic.formatProgress(progress: any): string
	local parts = {}
	for index, value in CaveLogic.sanitizeProgress(progress) do
		parts[index] = tostring(value)
	end
	return table.concat(parts, ",")
end

function CaveLogic.parseProgress(text: any): { number }
	local raw = {}
	if type(text) == "string" then
		local index = 0
		for piece in string.gmatch(text, "[^,]+") do
			index += 1
			raw[index] = tonumber(piece)
		end
	end
	return CaveLogic.sanitizeProgress(raw)
end

function CaveLogic.isOpen(progress: { number }, index: number): boolean
	local gate = CaveConfig.Gates[index]
	return gate ~= nil and (progress[index] or 0) >= gate.Kills
end

-- Puerta que se abre con los bichos de la sala `roomIndex` (índice y puerta) o nil.
function CaveLogic.gateOfRoom(roomIndex: number?): (number?, any)
	for index, gate in CaveConfig.Gates do
		if gate.Room == roomIndex then
			return index, gate
		end
	end
	return nil, nil
end

-- Cuenta un bicho derrotado que vivía en (homeX, homeZ). Devuelve la puerta que avanza
-- (o nil si no cuenta para ninguna) y si se acaba de abrir. Cambia `progress`.
function CaveLogic.countKill(progress: { number }, homeX: number, homeZ: number): (number?, boolean)
	local index, gate = CaveLogic.gateOfRoom((CaveLogic.roomAt(homeX, homeZ)))
	if not (index and gate) or CaveLogic.isOpen(progress, index) then
		return nil, false
	end
	progress[index] = math.min((progress[index] or 0) + 1, gate.Kills)
	return index, CaveLogic.isOpen(progress, index)
end

-- ¿Queda (x, z) detrás de una puerta cerrada? Devuelve esa puerta o nil. Detrás = en una sala
-- posterior a la suya o en su pasillo pasada la puerta.
function CaveLogic.blockedAt(x: number, z: number, progress: { number }): number?
	local roomIndex = CaveLogic.roomAt(x, z)
	for index, gate in CaveConfig.Gates do
		if not CaveLogic.isOpen(progress, index) then
			if roomIndex and roomIndex > gate.Room then
				return index
			end
			local corridor = CaveConfig.Corridors[gate.Corridor]
			local ahead = (x - gate.Position.X) * gate.Facing.X + (z - gate.Position.Z) * gate.Facing.Z
			if corridor and inRect(corridor.Rect, x, z) and ahead < -1 then
				return index
			end
		end
	end
	return nil
end

-- Medidas de la puerta `index`: ancho (lo que cierra del pasillo) y alto.
function CaveLogic.gateSize(index: number): (number, number)
	local gate = CaveConfig.Gates[index]
	local corridor = gate and CaveConfig.Corridors[gate.Corridor]
	if not corridor then
		return 0, 0
	end
	local r = corridor.Rect
	local alongX = (r.MaxX - r.MinX) >= (r.MaxZ - r.MinZ)
	return if alongX then r.MaxZ - r.MinZ else r.MaxX - r.MinX, corridor.Height
end

-- Lo que ocupa toda la cueva: MinX, MaxX, MinZ, MaxZ.
function CaveLogic.bounds(): (number, number, number, number)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local function grow(r)
		minX, maxX = math.min(minX, r.MinX), math.max(maxX, r.MaxX)
		minZ, maxZ = math.min(minZ, r.MinZ), math.max(maxZ, r.MaxZ)
	end
	for _, room in CaveConfig.Rooms do
		grow(room.Rect)
	end
	for _, corridor in CaveConfig.Corridors do
		grow(corridor.Rect)
	end
	return minX, maxX, minZ, maxZ
end

return CaveLogic
