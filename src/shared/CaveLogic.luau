-- Lógica pura de la Cueva de los Espinillos por dentro (CaveConfig): en qué sala estás, si
-- pisas la boca de la cueva o un portal de salida. Sin servicios: la usan CaveService (el
-- viaje), el cliente (carteles, ambiente y guía del tutorial) y las pruebas.

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
