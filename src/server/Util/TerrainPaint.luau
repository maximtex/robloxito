-- Pinta la capa superficial del terreno con otro material SIN cambiar su altura.
--
-- Por qué no FillCylinder: el terreno de Roblox es "blando" (vóxeles de 4 studs con
-- ocupación parcial) y un cilindro de relleno deja un montículo redondeado varios studs
-- por encima de su borde (medido: centro +3.8 studs). Aquí se usa ReplaceMaterial vóxel a
-- vóxel, en columnas de 4×4 studs alineadas a la rejilla, así que el suelo queda plano.

local TerrainPaint = {}

local VOXEL = 4

local function snapDown(value: number): number
	return math.floor(value / VOXEL) * VOXEL
end

local function snapUp(value: number): number
	return math.ceil(value / VOXEL) * VOXEL
end

-- Círculo de radio `radius` centrado en (centerX, centerZ) (coordenadas del mundo), en
-- la franja de alturas alrededor de `surfaceY`. Cambia `from` (uno o varios materiales)
-- por `to` en cada columna cuyo centro cae dentro del círculo.
function TerrainPaint.circle(centerX: number, centerZ: number, radius: number, surfaceY: number, from: { Enum.Material }, to: Enum.Material)
	local terrain = workspace.Terrain
	local bottom = snapDown(surfaceY - 8)
	local top = snapUp(surfaceY + 4)
	for x = snapDown(centerX - radius), snapUp(centerX + radius) - VOXEL, VOXEL do
		for z = snapDown(centerZ - radius), snapUp(centerZ + radius) - VOXEL, VOXEL do
			local dx, dz = x + VOXEL / 2 - centerX, z + VOXEL / 2 - centerZ
			if dx * dx + dz * dz <= radius * radius then
				local region = Region3.new(Vector3.new(x, bottom, z), Vector3.new(x + VOXEL, top, z + VOXEL))
				for _, material in from do
					terrain:ReplaceMaterial(region, VOXEL, material, to)
				end
			end
		end
	end
end

-- Camino: pinta círculos de radio width/2 a lo largo de una polilínea (puntos del mundo,
-- se usan X y Z), cada 2 studs. Mismo criterio que circle (solo la capa superficial).
function TerrainPaint.path(points: { Vector3 }, width: number, surfaceY: number, from: { Enum.Material }, to: Enum.Material)
	local radius = width / 2
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local delta = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local steps = math.max(1, math.ceil(delta.Magnitude / 2))
		for step = 0, steps do
			local t = step / steps
			TerrainPaint.circle(a.X + delta.X * t, a.Z + delta.Z * t, radius, surfaceY, from, to)
		end
	end
end

return TerrainPaint
