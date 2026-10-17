-- Utilidades para construir geometría estática con piezas nativas.
-- Todas las piezas se crean ancladas y sin eventos de contacto.

local PartFactory = {}

export type PartOptions = {
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material,
	Shape: Enum.PartType?,
	Solid: boolean?, -- false: decorativa, sin colisión ni raycasts
	CastShadow: boolean?, -- por defecto: solo las sólidas proyectan sombra
}

-- Los cilindros de Roblox se alinean con el eje X; esta rotación los pone de pie.
PartFactory.UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
-- Y esta los tumba a lo largo del eje Z.
PartFactory.ALONG_Z = CFrame.Angles(0, math.rad(90), 0)

function PartFactory.part(parent: Instance, name: string, options: PartOptions): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if options.Shape then
		part.Shape = options.Shape
	end
	part.Size = options.Size
	part.CFrame = options.CFrame
	part.Color = options.Color
	part.Material = options.Material

	local solid = options.Solid ~= false
	if not solid then
		part.CanCollide = false
		part.CanQuery = false
	end
	if options.CastShadow ~= nil then
		part.CastShadow = options.CastShadow
	else
		part.CastShadow = solid
	end

	part.Parent = parent
	return part
end

-- Cilindro vertical (disco o columna) centrado en `center`.
function PartFactory.verticalCylinder(parent: Instance, name: string, center: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material, solid: boolean?): Part
	return PartFactory.part(parent, name, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(center) * PartFactory.UPRIGHT,
		Color = color,
		Material = material,
		Solid = solid,
	})
end

-- Cilindro de un punto a otro (raíces, troncos, ramas).
function PartFactory.segment(parent: Instance, name: string, from: Vector3, to: Vector3, diameter: number, color: Color3, material: Enum.Material, solid: boolean?): Part
	local direction = to - from
	return PartFactory.part(parent, name, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(direction.Magnitude, diameter, diameter),
		-- lookAt orienta -Z hacia el destino; girar 90° en Y alinea el eje X del cilindro.
		CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Material = material,
		Solid = solid,
	})
end

function PartFactory.ball(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material, solid: boolean?): Part
	return PartFactory.part(parent, name, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = CFrame.new(center),
		Color = color,
		Material = material,
		Solid = solid,
	})
end

-- Elipsoide nativo (SpecialMesh de tipo esfera, sin recursos externos). Decorativo.
function PartFactory.ellipsoid(parent: Instance, name: string, cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = PartFactory.part(parent, name, {
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material,
		Solid = false,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Elimina de `container` los hijos con ese nombre (evita duplicados al reiniciar).
function PartFactory.removeExisting(container: Instance, name: string)
	for _, child in container:GetChildren() do
		if child.Name == name then
			child:Destroy()
		end
	end
end

function PartFactory.folder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

return PartFactory
