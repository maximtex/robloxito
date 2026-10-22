-- Integra visualmente los SpawnLocation existentes con el claro mágico (piedra,
-- runas doradas y farolillos) y los orienta hacia el cristal. No crea ni elimina
-- puntos de aparición, no cambia sus propiedades de spawn y no toca personajes ni avatares.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpawnConfig = require(Shared.Config.SpawnConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)

local SpawnService = {}

local function createDecorPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	-- Decorativo: no debe interferir con el spawn ni con el movimiento.
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Parent = parent
	return part
end

local function findSpawnLocations(): { SpawnLocation }
	local spawns = {}
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			table.insert(spawns, descendant)
		end
	end
	return spawns
end

-- Gira el spawn solo alrededor del eje Y para que mire al generador.
local function faceGenerator(spawnLocation: SpawnLocation)
	local position = spawnLocation.Position
	local target = Vector3.new(GeneratorConfig.Position.X, position.Y, GeneratorConfig.Position.Z)
	if (target - position).Magnitude < 1 then
		return
	end
	spawnLocation.CFrame = CFrame.lookAt(position, target)
end

local function restyle(spawnLocation: SpawnLocation)
	spawnLocation.Color = SpawnConfig.PadColor
	spawnLocation.Material = SpawnConfig.PadMaterial
	for _, child in spawnLocation:GetChildren() do
		if child:IsA("Decal") then
			child.Color3 = SpawnConfig.DecalTint
			if SpawnConfig.HideDecal then
				child.Transparency = 1
			end
		end
	end
end

local function decorate(spawnLocation: SpawnLocation, parent: Instance)
	local size = spawnLocation.Size
	local pad = spawnLocation.CFrame
	local inset = SpawnConfig.TrimInset

	-- Runas doradas en el borde de la cara superior del spawn
	local topY = size.Y / 2 + 0.03
	local halfX = size.X / 2 - inset
	local halfZ = size.Z / 2 - inset
	local edges = {
		{ Vector3.new(0, topY, halfZ), Vector3.new(halfX * 2, 0.06, 0.3) },
		{ Vector3.new(0, topY, -halfZ), Vector3.new(halfX * 2, 0.06, 0.3) },
		{ Vector3.new(halfX, topY, 0), Vector3.new(0.3, 0.06, halfZ * 2) },
		{ Vector3.new(-halfX, topY, 0), Vector3.new(0.3, 0.06, halfZ * 2) },
	}
	for index, edge in edges do
		createDecorPart(parent, "PadTrim" .. index, edge[2], pad * CFrame.new(edge[1]), SpawnConfig.TrimColor, Enum.Material.Neon)
	end

	-- Farolillos de madera a ambos lados, apoyados en el suelo junto al spawn. Si el spawn
	-- está medio hundido en el terreno, el suelo es la superficie del terreno.
	local floorY = math.max(pad.Position.Y - size.Y / 2, GeneratorConfig.Position.Y)
	local floorOffset = floorY - pad.Position.Y
	local postHeight = SpawnConfig.PostHeight
	for index, side in { -1, 1 } do
		local base = pad * CFrame.new(side * (size.X / 2 + SpawnConfig.PostGap), floorOffset, 0)

		createDecorPart(parent, "Post" .. index, Vector3.new(0.6, postHeight, 0.6), base * CFrame.new(0, postHeight / 2, 0), SpawnConfig.PostColor, Enum.Material.Wood)
		-- Brazo del que cuelga el farolillo, hacia el camino
		createDecorPart(parent, "Arm" .. index, Vector3.new(1.4, 0.25, 0.25), base * CFrame.new(-side * 0.55, postHeight - 0.2, 0), SpawnConfig.PostColor, Enum.Material.Wood)
		local lantern = createDecorPart(parent, "Lantern" .. index, Vector3.new(0.6, 0.75, 0.6), base * CFrame.new(-side * 1.05, postHeight - 0.75, 0), SpawnConfig.LanternColor, Enum.Material.Neon)
		createDecorPart(parent, "LanternCap" .. index, Vector3.new(0.8, 0.2, 0.8), base * CFrame.new(-side * 1.05, postHeight - 0.3, 0), SpawnConfig.PostColor, Enum.Material.Wood)

		local light = Instance.new("PointLight")
		light.Color = SpawnConfig.LightColor
		light.Range = SpawnConfig.LightRange
		light.Brightness = SpawnConfig.LightBrightness
		light.Shadows = false
		light.Parent = lantern
	end
end

function SpawnService.start()
	local existing = workspace:FindFirstChild(SpawnConfig.DecorFolderName)
	if existing then
		existing:Destroy()
	end

	local spawns = findSpawnLocations()
	if #spawns == 0 then
		warn("[SpawnService] No hay SpawnLocation en Workspace; no se aplica decoración.")
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = SpawnConfig.DecorFolderName

	for index, spawnLocation in spawns do
		if SpawnConfig.FaceGenerator then
			faceGenerator(spawnLocation)
		end
		restyle(spawnLocation)

		local decor = Instance.new("Model")
		decor.Name = "SpawnDecor" .. index
		decorate(spawnLocation, decor)
		decor.Parent = folder
	end

	folder.Parent = workspace
end

return SpawnService
