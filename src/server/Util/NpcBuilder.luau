-- Personajes de las aventuras con piezas nativas, al estilo chibi de las mascotas: cabeza
-- grande, ojos con brillo, mofletes y un traje y accesorios propios de cada uno
-- (Look.Style en AdventureConfig).
--
-- El modelo se construye en espacio local (pies en Y = 0, mirando a -Z) y se coloca con
-- PivotTo. "Root" es la única pieza anclada (colisión del personaje y aviso de
-- proximidad); el resto va soldado a ella, sin colisión ni masa, para que el cliente
-- pueda girar el personaje entero hacia el jugador con PivotTo.

local NpcBuilder = {}

local DARK = Color3.fromRGB(34, 28, 30)
local WHITE = Color3.new(1, 1, 1)
local BLUSH = Color3.fromRGB(255, 150, 160)
local GOLD = Color3.fromRGB(240, 200, 110)
local WOOD = Color3.fromRGB(122, 84, 52)

type Builder = { Model: Model, Root: BasePart, Origin: CFrame }

local function shade(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function attach(builder: Builder, part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = builder.Root
	weld.Part1 = part
	weld.Parent = part
	part.Parent = builder.Model
end

-- Pieza en coordenadas locales del personaje.
local function piece(builder: Builder, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	if shape then
		part.Shape = shape
	end
	part.CFrame = builder.Origin * offset
	attach(builder, part)
	return part
end

local function ball(builder: Builder, name: string, diameter: number, position: Vector3, color: Color3, material: Enum.Material?): Part
	return piece(builder, name, Vector3.one * diameter, CFrame.new(position), color, material, Enum.PartType.Ball)
end

-- Elipsoide (SpecialMesh de esfera).
local function blob(builder: Builder, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Part
	local part = piece(builder, name, size, offset, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Cilindro de pie (disco o columna) centrado en `position`.
local function disc(builder: Builder, name: string, height: number, diameter: number, position: Vector3, color: Color3, material: Enum.Material?): Part
	return piece(builder, name, Vector3.new(height, diameter, diameter), CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), color, material, Enum.PartType.Cylinder)
end

-- Cilindro de un punto a otro.
local function stick(builder: Builder, name: string, from: Vector3, to: Vector3, diameter: number, color: Color3, material: Enum.Material?): Part
	local direction = to - from
	return piece(builder, name, Vector3.new(direction.Magnitude, diameter, diameter), CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0), color, material, Enum.PartType.Cylinder)
end

-- Cuerpo común ---------------------------------------------------------------------------------

local HEAD_Y = 4.1
local HEAD = 2.5

local function face(builder: Builder, look: any)
	ball(builder, "Head", HEAD, Vector3.new(0, HEAD_Y, 0), look.Skin)
	for _, side in { -1, 1 } do
		blob(builder, "Eye" .. side, Vector3.new(0.34, 0.52, 0.2), CFrame.new(side * 0.46, HEAD_Y + 0.02, -1.13), DARK)
		ball(builder, "Shine" .. side, 0.13, Vector3.new(side * 0.42, HEAD_Y + 0.14, -1.22), WHITE, Enum.Material.Neon)
		local cheek = blob(builder, "Blush" .. side, Vector3.new(0.42, 0.22, 0.1), CFrame.new(side * 0.78, HEAD_Y - 0.3, -1.0) * CFrame.Angles(0, side * math.rad(-28), 0), BLUSH)
		cheek.Transparency = 0.25
	end
	blob(builder, "Mouth", Vector3.new(0.26, 0.1, 0.08), CFrame.new(0, HEAD_Y - 0.4, -1.18), shade(look.Skin, 0.55))
end

local function limbs(builder: Builder, look: any, legColor: Color3, armColor: Color3)
	for _, side in { -1, 1 } do
		disc(builder, "Leg" .. side, 1.0, 0.62, Vector3.new(side * 0.45, 0.55, 0), legColor)
		blob(builder, "Foot" .. side, Vector3.new(0.72, 0.42, 0.95), CFrame.new(side * 0.45, 0.2, -0.12), shade(legColor, 0.35))
	end
	for _, side in { -1, 1 } do
		blob(builder, "Arm" .. side, Vector3.new(0.55, 1.3, 0.55), CFrame.new(side * 1.12, 2.15, 0) * CFrame.Angles(0, 0, side * math.rad(14)), armColor)
		ball(builder, "Hand" .. side, 0.5, Vector3.new(side * 1.28, 1.48, -0.05), look.Skin)
	end
end

-- Estilos ---------------------------------------------------------------------------------------

local STYLES = {}

-- Abuela Hiedra: sombrero de paja con flor, moño blanco, chal y cesta de flores.
function STYLES.Herbalist(builder: Builder, look: any)
	limbs(builder, look, shade(look.Primary, 0.35), look.Primary)
	blob(builder, "Body", Vector3.new(2.1, 2.3, 1.8), CFrame.new(0, 2.05, 0), look.Primary)
	blob(builder, "Apron", Vector3.new(1.4, 1.5, 0.4), CFrame.new(0, 1.85, -0.78), Color3.fromRGB(246, 238, 220))
	blob(builder, "Shawl", Vector3.new(2.4, 0.9, 2.0), CFrame.new(0, 3.0, 0), shade(look.Primary, 0.2))
	face(builder, look)
	blob(builder, "Hair", Vector3.new(2.6, 1.4, 2.5), CFrame.new(0, HEAD_Y + 0.45, 0.2), look.Hair)
	ball(builder, "Bun", 1.0, Vector3.new(0, HEAD_Y + 0.9, 0.95), look.Hair)
	-- Sombrero de paja
	disc(builder, "Brim", 0.14, 4.0, Vector3.new(0, HEAD_Y + 1.05, 0), look.Secondary, Enum.Material.Fabric)
	blob(builder, "Crown", Vector3.new(2.0, 1.2, 2.0), CFrame.new(0, HEAD_Y + 1.4, 0), look.Secondary, Enum.Material.Fabric)
	disc(builder, "Band", 0.26, 2.05, Vector3.new(0, HEAD_Y + 1.2, 0), shade(look.Primary, 0.1))
	local flower = Vector3.new(0.75, HEAD_Y + 1.32, -0.62)
	for index = 1, 5 do
		local angle = math.rad(index * 72)
		ball(builder, "Petal" .. index, 0.34, flower + Vector3.new(math.cos(angle) * 0.2, math.sin(angle) * 0.2, -0.05), look.Accent)
	end
	ball(builder, "FlowerCenter", 0.22, flower + Vector3.new(0, 0, -0.12), GOLD, Enum.Material.Neon)
	blob(builder, "Leaf", Vector3.new(0.7, 0.14, 0.34), CFrame.new(flower + Vector3.new(0.4, -0.12, 0.05)) * CFrame.Angles(0, 0, math.rad(-20)), Color3.fromRGB(96, 170, 80))
	-- Cesta con flores en la mano derecha
	local basket = Vector3.new(1.55, 1.25, -0.25)
	disc(builder, "Basket", 0.75, 1.05, basket, WOOD, Enum.Material.Wood)
	stick(builder, "Handle1", basket + Vector3.new(-0.45, 0.35, 0), basket + Vector3.new(0, 0.95, 0), 0.12, WOOD, Enum.Material.Wood)
	stick(builder, "Handle2", basket + Vector3.new(0, 0.95, 0), basket + Vector3.new(0.45, 0.35, 0), 0.12, WOOD, Enum.Material.Wood)
	for index, color in { look.Accent, GOLD, Color3.fromRGB(170, 210, 255) } do
		ball(builder, "BasketFlower" .. index, 0.34, basket + Vector3.new((index - 2) * 0.28, 0.42, (index % 2) * 0.2 - 0.1), color)
	end
end

-- Tavo el cazador: capucha con pluma roja, chaleco de cuero, carcaj y arco.
function STYLES.Hunter(builder: Builder, look: any)
	limbs(builder, look, shade(look.Secondary, 0.3), look.Secondary)
	blob(builder, "Body", Vector3.new(2.1, 2.3, 1.8), CFrame.new(0, 2.05, 0), look.Secondary)
	disc(builder, "Belt", 0.28, 2.0, Vector3.new(0, 1.55, 0), shade(look.Secondary, 0.5), Enum.Material.Fabric)
	piece(builder, "Buckle", Vector3.new(0.34, 0.26, 0.1), CFrame.new(0, 1.55, -0.98), GOLD, Enum.Material.Metal)
	blob(builder, "Cape", Vector3.new(2.5, 1.0, 2.1), CFrame.new(0, 3.0, 0.1), look.Primary, Enum.Material.Fabric)
	face(builder, look)
	blob(builder, "Fringe", Vector3.new(2.0, 0.6, 0.8), CFrame.new(0, HEAD_Y + 0.85, -0.7), look.Hair)
	blob(builder, "Hood", Vector3.new(2.8, 2.7, 2.7), CFrame.new(0, HEAD_Y + 0.3, 0.6), look.Primary, Enum.Material.Fabric)
	blob(builder, "HoodTip", Vector3.new(0.8, 1.2, 0.8), CFrame.new(0, HEAD_Y + 1.1, 1.75) * CFrame.Angles(math.rad(-50), 0, 0), look.Primary, Enum.Material.Fabric)
	blob(builder, "Feather", Vector3.new(0.16, 1.3, 0.42), CFrame.new(1.25, HEAD_Y + 1.0, 0.45) * CFrame.Angles(math.rad(-15), 0, math.rad(-25)), look.Accent)
	-- Carcaj con flechas a la espalda
	local quiver = CFrame.new(0.45, 2.7, 1.0) * CFrame.Angles(0, 0, math.rad(-18))
	piece(builder, "Quiver", Vector3.new(1.6, 0.7, 0.7), quiver * CFrame.Angles(0, 0, math.rad(90)), shade(look.Secondary, 0.25), Enum.Material.Fabric, Enum.PartType.Cylinder)
	for index = -1, 1 do
		local base = (quiver * CFrame.new(index * 0.18, 0.7, 0)).Position
		local tip = (quiver * CFrame.new(index * 0.22, 1.45, 0)).Position
		stick(builder, "Arrow" .. index, base, tip, 0.08, WOOD, Enum.Material.Wood)
		blob(builder, "Fletch" .. index, Vector3.new(0.12, 0.34, 0.24), CFrame.new(tip), look.Accent)
	end
	-- Arco en la mano izquierda: arco de cinco tramos y cuerda
	local grip = Vector3.new(-1.42, 1.6, -0.2)
	local points = {}
	for index = 0, 5 do
		local t = index / 5
		local angle = math.rad(-70 + 140 * t)
		table.insert(points, grip + Vector3.new(0, math.sin(angle) * 1.5, -math.cos(angle) * 0.55 + 0.2))
	end
	for index = 1, #points - 1 do
		stick(builder, "Bow" .. index, points[index], points[index + 1], 0.16, shade(WOOD, 0.15), Enum.Material.Wood)
	end
	stick(builder, "String", points[1], points[#points], 0.04, Color3.fromRGB(240, 236, 220))
end

-- Pip el explorador: casco de explorador con gafas, pañuelo, mochila con el mapa y lupa.
function STYLES.Explorer(builder: Builder, look: any)
	limbs(builder, look, Color3.fromRGB(130, 96, 60), look.Primary)
	blob(builder, "Body", Vector3.new(2.0, 2.2, 1.8), CFrame.new(0, 2.0, 0), look.Primary)
	for _, side in { -1, 1 } do
		blob(builder, "Pocket" .. side, Vector3.new(0.5, 0.45, 0.2), CFrame.new(side * 0.5, 1.75, -0.86), shade(look.Primary, 0.15))
	end
	disc(builder, "Scarf", 0.36, 1.7, Vector3.new(0, 3.05, 0), look.Accent, Enum.Material.Fabric)
	blob(builder, "ScarfTail", Vector3.new(0.4, 0.9, 0.2), CFrame.new(0.55, 2.65, -0.85) * CFrame.Angles(0, 0, math.rad(-15)), look.Accent, Enum.Material.Fabric)
	face(builder, look)
	for _, side in { -1, 1 } do
		blob(builder, "Tuft" .. side, Vector3.new(0.6, 0.7, 0.9), CFrame.new(side * 1.05, HEAD_Y + 0.25, -0.3), look.Hair)
	end
	-- Casco de explorador con gafas
	blob(builder, "Helmet", Vector3.new(2.4, 1.5, 2.4), CFrame.new(0, HEAD_Y + 0.85, 0), look.Secondary, Enum.Material.Fabric)
	disc(builder, "HelmetBrim", 0.12, 3.1, Vector3.new(0, HEAD_Y + 0.6, 0), look.Secondary, Enum.Material.Fabric)
	disc(builder, "HelmetBand", 0.22, 2.42, Vector3.new(0, HEAD_Y + 0.75, 0), shade(look.Secondary, 0.4), Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		local lens = CFrame.new(side * 0.42, HEAD_Y + 1.1, -1.2) * CFrame.Angles(math.rad(-20), 0, 0)
		piece(builder, "GoggleRim" .. side, Vector3.new(0.16, 0.56, 0.56), lens * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(214, 120, 50), Enum.Material.Metal, Enum.PartType.Cylinder)
		local glass = piece(builder, "Goggle" .. side, Vector3.new(0.18, 0.42, 0.42), lens * CFrame.new(0, 0, -0.02) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(140, 210, 240), Enum.Material.Glass, Enum.PartType.Cylinder)
		glass.Transparency = 0.25
	end
	-- Mochila con el mapa enrollado
	blob(builder, "Backpack", Vector3.new(1.7, 1.9, 1.05), CFrame.new(0, 2.2, 1.05), Color3.fromRGB(120, 140, 80), Enum.Material.Fabric)
	blob(builder, "BackpackPocket", Vector3.new(1.1, 0.8, 0.4), CFrame.new(0, 1.8, 1.55), Color3.fromRGB(100, 120, 66), Enum.Material.Fabric)
	piece(builder, "MapRoll", Vector3.new(1.9, 0.48, 0.48), CFrame.new(0, 3.25, 1.15), Color3.fromRGB(236, 214, 160), Enum.Material.Fabric, Enum.PartType.Cylinder)
	for _, side in { -1, 1 } do
		disc(builder, "Strap" .. side, 0.14, 0.3, Vector3.new(side * 0.55, 2.5, -0.85), Color3.fromRGB(90, 70, 50))
	end
	-- Lupa en la mano derecha
	local hand = Vector3.new(1.28, 1.48, -0.05)
	stick(builder, "LoupeHandle", hand, hand + Vector3.new(0.25, 0.75, -0.2), 0.14, WOOD, Enum.Material.Wood)
	local ring = CFrame.new(hand + Vector3.new(0.35, 1.15, -0.28)) * CFrame.Angles(0, math.rad(90), 0)
	piece(builder, "LoupeRing", Vector3.new(0.1, 0.62, 0.62), ring, GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
	local lens = piece(builder, "LoupeLens", Vector3.new(0.12, 0.5, 0.5), ring, Color3.fromRGB(200, 236, 255), Enum.Material.Glass, Enum.PartType.Cylinder)
	lens.Transparency = 0.4
end

-- Lumi la oráculo: túnica larga, capucha con diadema y gema, melena plateada y un cristal
-- que flota sobre su mano.
function STYLES.Oracle(builder: Builder, look: any)
	blob(builder, "Robe", Vector3.new(2.4, 3.3, 2.1), CFrame.new(0, 1.6, 0), look.Primary, Enum.Material.Fabric)
	blob(builder, "RobeHem", Vector3.new(2.6, 0.6, 2.3), CFrame.new(0, 0.3, 0), shade(look.Primary, 0.25), Enum.Material.Fabric)
	disc(builder, "Sash", 0.24, 2.1, Vector3.new(0, 2.1, 0), GOLD, Enum.Material.Metal)
	for index = -1, 1 do
		ball(builder, "Star" .. index, 0.2, Vector3.new(index * 0.45, 1.2 + math.abs(index) * 0.25, -1.02), look.Accent, Enum.Material.Neon)
	end
	for _, side in { -1, 1 } do
		blob(builder, "Sleeve" .. side, Vector3.new(0.7, 1.4, 0.7), CFrame.new(side * 1.15, 2.2, 0) * CFrame.Angles(0, 0, side * math.rad(18)), look.Primary, Enum.Material.Fabric)
		ball(builder, "Hand" .. side, 0.48, Vector3.new(side * 1.38, 1.5, -0.05), look.Skin)
	end
	face(builder, look)
	for _, side in { -1, 1 } do
		blob(builder, "Lock" .. side, Vector3.new(0.62, 1.7, 0.75), CFrame.new(side * 1.0, HEAD_Y - 0.5, 0.05), look.Hair)
	end
	blob(builder, "Bangs", Vector3.new(2.2, 0.6, 0.8), CFrame.new(0, HEAD_Y + 0.85, -0.68), look.Hair)
	blob(builder, "Hood", Vector3.new(2.85, 2.8, 2.8), CFrame.new(0, HEAD_Y + 0.3, 0.6), look.Secondary, Enum.Material.Fabric)
	disc(builder, "Circlet", 0.14, 2.45, Vector3.new(0, HEAD_Y + 0.72, -0.05), GOLD, Enum.Material.Metal)
	piece(builder, "CircletGem", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, HEAD_Y + 0.75, -1.18) * CFrame.Angles(0, 0, math.rad(45)), look.Accent, Enum.Material.Neon)
	-- Cristal flotante sobre la mano izquierda (el cliente lo hace girar)
	local crystal = piece(builder, "Floating", Vector3.new(0.6, 1.1, 0.6), CFrame.new(-1.5, 2.9, -0.4) * CFrame.Angles(0, math.rad(45), 0), look.Accent, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = look.Accent
	light.Range = 10
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = crystal
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 4
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Speed = NumberRange.new(0.4, 1)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new(0.18, 0)
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(look.Accent)
	sparkle.Parent = crystal
end

-- Brasa la herrera: delantal de cuero, mangas remangadas con guantes, melena pelirroja con
-- cinta y gafas de forja en la frente, martillo en una mano y un lingote al rojo en la otra.
function STYLES.Smith(builder: Builder, look: any)
	local leather = look.Secondary
	for _, side in { -1, 1 } do
		disc(builder, "Leg" .. side, 1.0, 0.66, Vector3.new(side * 0.46, 0.55, 0), Color3.fromRGB(70, 56, 50))
		blob(builder, "Boot" .. side, Vector3.new(0.78, 0.5, 1.0), CFrame.new(side * 0.46, 0.22, -0.12), Color3.fromRGB(46, 36, 32))
	end
	blob(builder, "Body", Vector3.new(2.3, 2.3, 1.9), CFrame.new(0, 2.05, 0), look.Primary)
	blob(builder, "Apron", Vector3.new(1.7, 2.0, 0.45), CFrame.new(0, 1.75, -0.82), leather, Enum.Material.Fabric)
	piece(builder, "ApronPocket", Vector3.new(0.7, 0.4, 0.12), CFrame.new(0, 1.55, -1.06), shade(leather, 0.2), Enum.Material.Fabric)
	disc(builder, "Belt", 0.26, 2.15, Vector3.new(0, 1.5, 0), shade(leather, 0.45), Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		-- Manga remangada, antebrazo al aire y guante grueso
		blob(builder, "Sleeve" .. side, Vector3.new(0.62, 0.7, 0.62), CFrame.new(side * 1.15, 2.55, 0) * CFrame.Angles(0, 0, side * math.rad(14)), look.Primary)
		blob(builder, "Forearm" .. side, Vector3.new(0.5, 0.75, 0.5), CFrame.new(side * 1.24, 1.95, 0) * CFrame.Angles(0, 0, side * math.rad(10)), look.Skin)
		ball(builder, "Glove" .. side, 0.62, Vector3.new(side * 1.3, 1.45, -0.05), shade(leather, 0.3))
	end
	face(builder, look)
	-- Melena con coleta, cinta y gafas de forja
	blob(builder, "Hair", Vector3.new(2.6, 1.5, 2.55), CFrame.new(0, HEAD_Y + 0.4, 0.15), look.Hair)
	blob(builder, "Ponytail", Vector3.new(0.7, 1.5, 0.7), CFrame.new(0, HEAD_Y - 0.2, 1.35) * CFrame.Angles(math.rad(25), 0, 0), look.Hair)
	disc(builder, "Headband", 0.3, 2.55, Vector3.new(0, HEAD_Y + 0.6, 0), shade(leather, 0.1), Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		local lens = CFrame.new(side * 0.42, HEAD_Y + 0.92, -1.12) * CFrame.Angles(math.rad(-25), 0, 0)
		piece(builder, "GoggleRim" .. side, Vector3.new(0.16, 0.54, 0.54), lens * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(70, 66, 64), Enum.Material.Metal, Enum.PartType.Cylinder)
		local glass = piece(builder, "Goggle" .. side, Vector3.new(0.18, 0.4, 0.4), lens * CFrame.new(0, 0, -0.02) * CFrame.Angles(0, math.rad(90), 0), look.Accent, Enum.Material.Glass, Enum.PartType.Cylinder)
		glass.Transparency = 0.3
	end
	-- Martillo en la mano derecha
	local hand = Vector3.new(1.3, 1.45, -0.05)
	stick(builder, "HammerHandle", hand - Vector3.new(0, 0.35, 0), hand + Vector3.new(0.1, 1.2, -0.15), 0.18, WOOD, Enum.Material.Wood)
	piece(builder, "HammerHead", Vector3.new(0.9, 0.5, 0.5), CFrame.new(hand + Vector3.new(0.12, 1.35, -0.17)), Color3.fromRGB(96, 92, 92), Enum.Material.Metal)
	-- Lingote al rojo en la mano izquierda
	local ingot = piece(builder, "Ingot", Vector3.new(0.75, 0.3, 0.42), CFrame.new(-1.3, 1.75, -0.3) * CFrame.Angles(0, math.rad(20), 0), look.Accent, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = look.Accent
	light.Range = 9
	light.Brightness = 1.1
	light.Shadows = false
	light.Parent = ingot
	local sparks = Instance.new("ParticleEmitter")
	sparks.Rate = 5
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.Speed = NumberRange.new(1.5, 3)
	sparks.SpreadAngle = Vector2.new(40, 40)
	sparks.Acceleration = Vector3.new(0, -6, 0)
	sparks.Size = NumberSequence.new(0.14, 0)
	sparks.LightEmission = 1
	sparks.Color = ColorSequence.new(look.Accent, Color3.fromRGB(255, 220, 140))
	sparks.Parent = ingot
end

-- Construye un personaje. `pivot`: punto del suelo (pies) ya orientado.
function NpcBuilder.build(npcId: string, npc: any, pivot: CFrame): Model
	local model = Instance.new("Model")
	model.Name = npcId
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2.6, 5.4, 2.6)
	root.CFrame = pivot * CFrame.new(0, 2.7, 0)
	root.Anchored = true
	root.CanCollide = true
	root.CanQuery = true
	root.CanTouch = false
	root.Transparency = 1
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root
	local builder: Builder = { Model = model, Root = root, Origin = pivot }
	local style = STYLES[npc.Look.Style] or STYLES.Explorer
	style(builder, npc.Look)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			part.CastShadow = part.Transparency < 0.5 and part.Material ~= Enum.Material.Neon
		end
	end
	model:SetAttribute("NpcId", npcId)
	return model
end

return NpcBuilder
