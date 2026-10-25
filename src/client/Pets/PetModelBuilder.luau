-- Construye el modelo visual de una mascota con piezas nativas (sin recursos externos).
-- El modelo tiene una pieza raíz anclada e invisible ("Root"); el resto va unido a ella
-- con Welds, de modo que basta con mover Root para mover la mascota. Todo es local al cliente y sin
-- colisión. El frente de la mascota es -Z (hacia donde mira); +Y es arriba.
--
-- Estilo: mascotas «chibi» de simulador (cabeza grande, ojos brillantes con destellos,
-- mejillas, patitas) con la paleta de cada mascota (PetConfig.Look).
--
-- Animación (la aplica PetAnimator cada frame, en local):
-- - Las piezas con Anim (alas, colas, hojas) se unen con un Weld llamado "PetAnim" con
--   atributos Hinge (punto de giro), Axis (eje), Offset, Amp, Speed y Phase.
-- - Los ojos llevan el atributo PetBlink = "Open" / "Closed" para parpadear.
-- Efectos por rareza (Rara, Épica, Legendaria): destellos, luz y aura en la raíz.
--
-- ARTE EXTERNO: si existe ReplicatedStorage.PetModels.<PetId> (un Model con PrimaryPart),
-- se usa ese modelo en lugar del construido aquí, con los efectos de su rareza. Una ★ Evo sin
-- modelo propio usa el de su mascota base, más grande (EVO_ART_SCALE) y con las piezas que
-- llevan el atributo PetTint = "Primary" / "Secondary" de los colores de su Look ("PrimaryDark":
-- el principal oscurecido, para las manchas y patas del pelaje). Las piezas
-- con AnimHinge y AnimAxis (Vector3, respecto a la raíz) y AnimAmp, AnimSpeed, AnimPhase y
-- AnimOffset se animan como las de aquí (PetAnimator): orejas, colas y alas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.PetConfig)

local BLACK = Color3.fromRGB(30, 24, 34)
local WHITE = Color3.fromRGB(255, 255, 255)
local CREAM = Color3.fromRGB(250, 238, 220)
local BLUSH = Color3.fromRGB(255, 150, 170)
local TONGUE = Color3.fromRGB(240, 110, 130)
local GOLD = Color3.fromRGB(255, 200, 90)

local PetModelBuilder = {}

type Builder = {
	Model: Model,
	Root: BasePart,
}

-- Animación de una pieza: gira alrededor de Hinge (espacio de la raíz) sobre Axis con
-- ángulo = Offset + Amp · sin(t · Speed + Phase).
type Anim = {
	Hinge: Vector3,
	Axis: Vector3,
	Offset: number?,
	Amp: number,
	Speed: number,
	Phase: number?,
}

type Opts = {
	Material: Enum.Material?,
	Transparency: number?,
	Reflectance: number?,
	Anim: Anim?,
	Blink: string?,
}

type Look = {
	Primary: Color3,
	Secondary: Color3,
}

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

-- Piezas básicas -----------------------------------------------------------------

local function newPart(builder: Builder, name: string, kind: string, size: Vector3, offset: CFrame, color: Color3, opts: Opts?): BasePart
	local options: Opts = opts or {}
	local part: BasePart
	if kind == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local basic = Instance.new("Part")
		basic.Shape = if kind == "Ball"
			then Enum.PartType.Ball
			elseif kind == "Cylinder" then Enum.PartType.Cylinder
			else Enum.PartType.Block
		part = basic
	end
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = options.Material or Enum.Material.SmoothPlastic
	part.Transparency = options.Transparency or 0
	part.Reflectance = options.Reflectance or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Anchored = false
	if kind == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	part.CFrame = builder.Root.CFrame * offset

	local anim = options.Anim
	if anim then
		local weld = Instance.new("Weld")
		weld.Name = "PetAnim"
		weld.Part0 = builder.Root
		weld.Part1 = part
		weld.C0 = offset
		weld:SetAttribute("Hinge", anim.Hinge)
		weld:SetAttribute("Axis", anim.Axis.Unit)
		weld:SetAttribute("Offset", anim.Offset or 0)
		weld:SetAttribute("Amp", anim.Amp)
		weld:SetAttribute("Speed", anim.Speed)
		weld:SetAttribute("Phase", anim.Phase or 0)
		weld.Parent = part
	else
		-- Weld con C0 explícito (no WeldConstraint): la posición relativa no depende de
		-- dónde esté la raíz cuando el modelo entra en Workspace.
		local weld = Instance.new("Weld")
		weld.Part0 = builder.Root
		weld.Part1 = part
		weld.C0 = offset
		weld.Parent = part
	end
	if options.Blink then
		part:SetAttribute("PetBlink", options.Blink)
	end

	part.Parent = builder.Model
	return part
end

local function ball(builder: Builder, name: string, diameter: number, position: Vector3, color: Color3, opts: Opts?): BasePart
	return newPart(builder, name, "Ball", Vector3.one * diameter, CFrame.new(position), color, opts)
end

local function ellipsoid(builder: Builder, name: string, size: Vector3, offset: CFrame, color: Color3, opts: Opts?): BasePart
	return newPart(builder, name, "Ellipsoid", size, offset, color, opts)
end

local function block(builder: Builder, name: string, size: Vector3, offset: CFrame, color: Color3, opts: Opts?): BasePart
	return newPart(builder, name, "Block", size, offset, color, opts)
end

-- Triángulo isósceles (dos cuñas espalda con espalda) en el plano XY de `offset`:
-- base abajo, punta arriba, grosor en Z. Sirve para orejas, picos y aletas.
local function triangle(builder: Builder, name: string, width: number, height: number, thickness: number, offset: CFrame, color: Color3, opts: Opts?)
	local size = Vector3.new(thickness, height, width / 2)
	newPart(builder, name .. "R", "Wedge", size, offset * CFrame.new(width / 4, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), color, opts)
	newPart(builder, name .. "L", "Wedge", size, offset * CFrame.new(-width / 4, 0, 0) * CFrame.Angles(0, math.rad(90), 0), color, opts)
end

-- Cubo apoyado en un vértice (punta hacia +Y de `offset`): puntas de cristal y gemas.
local VERTEX_UP = (function()
	local diagonal = Vector3.new(1, 1, 1).Unit
	local axis = diagonal:Cross(Vector3.yAxis).Unit
	return CFrame.fromAxisAngle(axis, math.acos(diagonal:Dot(Vector3.yAxis)))
end)()

local function gem(builder: Builder, name: string, size: number, offset: CFrame, color: Color3, opts: Opts?): BasePart
	return block(builder, name, Vector3.one * size, offset * VERTEX_UP, color, opts)
end

-- Cristal: prisma de sección rombo con punta. `offset` en la base; crece hacia +Y.
local function crystal(builder: Builder, name: string, width: number, height: number, offset: CFrame, color: Color3, opts: Opts?)
	local bodyHeight = height - width * 0.45
	block(builder, name, Vector3.new(width, bodyHeight, width), offset * CFrame.new(0, bodyHeight / 2, 0) * CFrame.Angles(0, math.rad(45), 0), color, opts)
	gem(builder, name .. "Tip", width * 0.72, offset * CFrame.new(0, bodyHeight - width * 0.05, 0), lighten(color, 0.25), opts)
end

-- Punto sobre la superficie de un elipsoide (centro y semiejes), mirando hacia fuera.
-- yaw: grados hacia +X (derecha); pitch: grados hacia arriba. (0, 0) = el frente (-Z).
local function surface(center: Vector3, semi: Vector3, yaw: number, pitch: number): CFrame
	local y, p = math.rad(yaw), math.rad(pitch)
	local dx, dy, dz = math.sin(y) * math.cos(p), math.sin(p), -math.cos(y) * math.cos(p)
	local point = center + Vector3.new(dx * semi.X, dy * semi.Y, dz * semi.Z)
	local normal = Vector3.new(dx / semi.X, dy / semi.Y, dz / semi.Z).Unit
	return CFrame.lookAt(point, point + normal)
end

-- Rasgos de la cara -----------------------------------------------------------------

type EyeOptions = {
	Iris: Color3?,
	Slit: boolean?,
}

-- Ojo brillante: óvalo oscuro (con iris opcional), dos destellos y párpado cerrado
-- (oculto) para el parpadeo. `cf` sale de surface(): -Z apunta hacia fuera.
local function eye(builder: Builder, name: string, cf: CFrame, width: number, height: number, options: EyeOptions?)
	local depth = 0.08
	ellipsoid(builder, name, Vector3.new(width, height, depth), cf, BLACK, { Blink = "Open" })
	local iris = options and options.Iris
	if iris then
		ellipsoid(builder, name .. "Iris", Vector3.new(width * 0.8, height * 0.8, depth), cf * CFrame.new(0, -height * 0.05, -0.012), iris, { Blink = "Open" })
		local pupilWidth = if options and options.Slit then width * 0.2 else width * 0.44
		ellipsoid(builder, name .. "Pupil", Vector3.new(pupilWidth, height * 0.6, depth), cf * CFrame.new(0, -height * 0.05, -0.024), BLACK, { Blink = "Open" })
	end
	ellipsoid(builder, name .. "Shine", Vector3.new(width * 0.4, width * 0.4, 0.05), cf * CFrame.new(width * 0.16, height * 0.2, -0.04), WHITE, { Blink = "Open" })
	ellipsoid(builder, name .. "Shine2", Vector3.new(width * 0.18, width * 0.18, 0.05), cf * CFrame.new(-width * 0.14, -height * 0.22, -0.04), WHITE, { Blink = "Open" })
	ellipsoid(builder, name .. "Closed", Vector3.new(width * 1.05, height * 0.16, depth), cf * CFrame.new(0, -height * 0.1, -0.03), BLACK, { Blink = "Closed", Transparency = 1 })
end

local function eyes(builder: Builder, center: Vector3, semi: Vector3, yaw: number, pitch: number, width: number, height: number, options: EyeOptions?)
	for index, side in { -1, 1 } do
		eye(builder, "Eye" .. index, surface(center, semi, side * yaw, pitch), width, height, options)
	end
end

local function cheeks(builder: Builder, center: Vector3, semi: Vector3, yaw: number, pitch: number, size: number)
	for index, side in { -1, 1 } do
		ellipsoid(builder, "Cheek" .. index, Vector3.new(size, size * 0.55, 0.05), surface(center, semi, side * yaw, pitch) * CFrame.new(0, 0, -0.01), BLUSH, { Transparency = 0.1 })
	end
end

-- Boca pequeña; con `open`, abierta y con lengua.
local function mouth(builder: Builder, cf: CFrame, width: number, open: boolean?)
	if open then
		ellipsoid(builder, "Mouth", Vector3.new(width, width * 0.7, 0.06), cf, BLACK)
		ellipsoid(builder, "Tongue", Vector3.new(width * 0.6, width * 0.35, 0.06), cf * CFrame.new(0, -width * 0.15, -0.01), TONGUE)
	else
		ellipsoid(builder, "Mouth", Vector3.new(width, width * 0.32, 0.05), cf, BLACK)
	end
end

local function nose(builder: Builder, position: Vector3, diameter: number)
	ball(builder, "Nose", diameter, position, BLACK)
	ball(builder, "NoseShine", diameter * 0.35, position + Vector3.new(diameter * 0.15, diameter * 0.2, -diameter * 0.35), WHITE)
end

-- Hojita con nervio central. `offset` en su base; la hoja se extiende hacia +X local.
local function leaf(builder: Builder, name: string, length: number, offset: CFrame, color: Color3, opts: Opts?)
	ellipsoid(builder, name, Vector3.new(length, 0.07, length * 0.5), offset * CFrame.new(length / 2, 0, 0), color, opts)
	block(builder, name .. "Vein", Vector3.new(length * 0.7, 0.08, 0.035), offset * CFrame.new(length * 0.45, 0.005, 0), darken(color, 0.25), opts)
end

-- Efectos por rareza -----------------------------------------------------------------
-- Las partículas salen de la superficie de una esfera invisible que envuelve el cuerpo
-- (si salieran de la raíz, quedarían ocultas dentro de la mascota).

local function effectShell(builder: Builder): BasePart
	local boxCf, boxSize = builder.Model:GetBoundingBox()
	local diameter = math.max(boxSize.X, boxSize.Y, boxSize.Z) * 0.6
	return newPart(builder, "EffectShell", "Ball", Vector3.one * diameter, builder.Root.CFrame:ToObjectSpace(boxCf), WHITE, { Transparency = 1 })
end

local function sparkles(parent: BasePart, color: Color3, rate: number, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "RaritySparkles"
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.9, 1.5)
	emitter.Speed = NumberRange.new(0.4, 0.9)
	emitter.Drag = 1.5
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new(lighten(color, 0.5), color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = parent
end

local function aura(parent: BasePart, color: Color3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "RarityAura"
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.Rate = 5
	emitter.Lifetime = NumberRange.new(0.8, 1.2)
	emitter.Speed = NumberRange.new(0.1, 0.3)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1.3),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Parent = parent
end

local function light(parent: BasePart, color: Color3, brightness: number, range: number)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Brightness = brightness
	pointLight.Range = range
	pointLight.Shadows = false
	pointLight.Parent = parent
end

local function addRarityEffects(builder: Builder, rarity: string?, glow: Color3)
	if rarity ~= "Rare" and rarity ~= "Epic" and rarity ~= "Legendary" then
		return
	end
	local shell = effectShell(builder)
	if rarity == "Rare" then
		sparkles(shell, glow, 2, 0.22)
	elseif rarity == "Epic" then
		sparkles(shell, glow, 3, 0.26)
		light(builder.Root, glow, 0.6, 6)
	else
		sparkles(shell, glow, 5, 0.3)
		aura(shell, glow)
		light(builder.Root, glow, 1, 8)
	end
end

-- Estilos ---------------------------------------------------------------------------

-- Brotecillo: semilla regordeta con brote de dos hojas que se mecen.
local function buildSprout(builder: Builder, look: Look)
	local bodyCenter = Vector3.new(0, 0, 0)
	local bodySemi = Vector3.new(0.85, 0.75, 0.8)
	ellipsoid(builder, "Body", bodySemi * 2, CFrame.new(bodyCenter), look.Primary)
	local bellyCenter, bellySemi = Vector3.new(0, -0.18, -0.6), Vector3.new(0.55, 0.475, 0.25)
	ellipsoid(builder, "Belly", bellySemi * 2, CFrame.new(bellyCenter), lighten(look.Primary, 0.45))

	eyes(builder, bodyCenter, bodySemi, 24, 14, 0.3, 0.4)
	cheeks(builder, bodyCenter, bodySemi, 42, -4, 0.28)
	mouth(builder, surface(bellyCenter, bellySemi, 0, 28), 0.18, true)

	for index, side in { -1, 1 } do
		ellipsoid(builder, "Foot" .. index, Vector3.new(0.5, 0.3, 0.6), CFrame.new(side * 0.42, -0.7, -0.2), darken(look.Primary, 0.18))
		ellipsoid(builder, "Arm" .. index, Vector3.new(0.3, 0.44, 0.3), CFrame.new(side * 0.8, -0.12, -0.08) * CFrame.Angles(0, 0, side * 0.55), darken(look.Primary, 0.08))
	end

	-- Brote: tallo, dos hojas (se mecen) y un capullo.
	local stemTop = Vector3.new(0, 1.15, 0.05)
	newPart(builder, "Stem", "Cylinder", Vector3.new(0.5, 0.14, 0.14), CFrame.new(0, 0.92, 0.05) * CFrame.Angles(0, 0, math.rad(90)), look.Secondary)
	for index, side in { -1, 1 } do
		local sway: Anim = { Hinge = stemTop, Axis = Vector3.new(0, 0, side), Amp = 0.18, Speed = 3, Phase = index }
		leaf(builder, "Leaf" .. index, 0.85, CFrame.new(stemTop) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0.4), lighten(look.Secondary, 0.15), { Anim = sway })
	end
	ball(builder, "Bud", 0.22, stemTop + Vector3.new(0, 0.08, 0), Color3.fromRGB(255, 214, 96))
end

-- Seta Saltarina: tallo con carita y sombrero moteado con láminas por debajo.
local function buildMushroom(builder: Builder, look: Look)
	-- El tallo usa el color secundario (crema); el sombrero, el principal.
	local stemCenter = Vector3.new(0, 0, 0)
	local stemSemi = Vector3.new(0.525, 0.575, 0.5)
	ellipsoid(builder, "StemBody", stemSemi * 2, CFrame.new(stemCenter), look.Secondary)

	local capCenter = Vector3.new(0, 0.8, 0)
	local capSemi = Vector3.new(1.15, 0.62, 1.15)
	ellipsoid(builder, "Cap", capSemi * 2, CFrame.new(capCenter), look.Primary)
	newPart(builder, "Gills", "Cylinder", Vector3.new(0.12, 2.05, 2.05), CFrame.new(0, 0.44, 0) * CFrame.Angles(0, 0, math.rad(90)), darken(look.Secondary, 0.1))
	for index, spot in { { 0, 38, 0.52 }, { 62, 28, 0.42 }, { -58, 32, 0.46 }, { 150, 30, 0.44 }, { -140, 22, 0.4 }, { 100, 58, 0.3 }, { -95, 60, 0.3 }, { 25, 72, 0.32 } } do
		ellipsoid(builder, "Spot" .. index, Vector3.new(spot[3], spot[3], 0.08), surface(capCenter, capSemi, spot[1], spot[2]), WHITE)
	end

	eyes(builder, stemCenter, stemSemi, 26, 4, 0.22, 0.3)
	cheeks(builder, stemCenter, stemSemi, 46, -12, 0.2)
	mouth(builder, surface(stemCenter, stemSemi, 0, -16), 0.14, true)
	for index, side in { -1, 1 } do
		ellipsoid(builder, "Foot" .. index, Vector3.new(0.36, 0.22, 0.46), CFrame.new(side * 0.25, -0.52, -0.1), darken(look.Secondary, 0.14))
		ellipsoid(builder, "Arm" .. index, Vector3.new(0.22, 0.32, 0.22), CFrame.new(side * 0.52, -0.1, -0.02) * CFrame.Angles(0, 0, side * 0.6), darken(look.Secondary, 0.06))
	end
end

-- Base común de los zorros (Musgo, Brasa y Cuarzo).
type FoxSpec = {
	BodyMaterial: Enum.Material?,
	Fur: Color3, -- pecho, hocico y mejillas
	Paws: Color3,
	EarInner: Color3,
	EarTip: Color3?,
	EarHeight: number,
	EarMaterial: Enum.Material?,
	EarColor: Color3?,
	Tail: boolean?, -- false: el estilo dibuja su propia cola
	TailTip: Color3?,
	TailTipMaterial: Enum.Material?,
}

local FOX_HEAD_CENTER = Vector3.new(0, 0.45, -0.55)
local FOX_HEAD_SEMI = Vector3.new(0.625, 0.55, 0.55)
-- Base de la cola y dirección (arriba y atrás).
local FOX_TAIL_BASE = Vector3.new(0, 0, 0.72)
local FOX_TAIL_DIR = Vector3.new(0, math.sin(math.rad(40)), math.cos(math.rad(40)))

local function foxWag(): Anim
	return { Hinge = FOX_TAIL_BASE, Axis = Vector3.yAxis, Amp = 0.35, Speed = 4 }
end

local function buildFoxBase(builder: Builder, look: Look, spec: FoxSpec)
	local material = spec.BodyMaterial
	ellipsoid(builder, "Torso", Vector3.new(1.1, 0.95, 1.45), CFrame.new(0, -0.15, 0.15), look.Primary, { Material = material })
	ellipsoid(builder, "Chest", Vector3.new(0.62, 0.58, 0.4), CFrame.new(0, -0.05, -0.42), spec.Fur)
	ellipsoid(builder, "Head", FOX_HEAD_SEMI * 2, CFrame.new(FOX_HEAD_CENTER), look.Primary, { Material = material })

	-- Hocico, nariz, mejillas esponjosas y cara
	ellipsoid(builder, "Muzzle", Vector3.new(0.54, 0.4, 0.54), CFrame.new(0, 0.28, -1.0), spec.Fur)
	nose(builder, Vector3.new(0, 0.4, -1.24), 0.16)
	mouth(builder, CFrame.lookAt(Vector3.new(0, 0.2, -1.23), Vector3.new(0, 0.2, -2)), 0.14)
	for index, side in { -1, 1 } do
		ellipsoid(builder, "Fluff" .. index, Vector3.new(0.42, 0.34, 0.36), CFrame.new(side * 0.5, 0.22, -0.74) * CFrame.Angles(0, 0, side * -0.5), spec.Fur)
	end
	eyes(builder, FOX_HEAD_CENTER, FOX_HEAD_SEMI, 30, 14, 0.24, 0.32)
	cheeks(builder, FOX_HEAD_CENTER, FOX_HEAD_SEMI, 50, -4, 0.2)

	-- Orejas triangulares con interior y, si se indica, punta de otro color.
	local earHeight = spec.EarHeight
	for index, side in { -1, 1 } do
		local earBase = CFrame.new(side * 0.32, 0.86 + earHeight * 0.3, -0.48) * CFrame.Angles(0, 0, -side * 0.32)
		triangle(builder, "Ear" .. index, 0.46, earHeight, 0.14, earBase, spec.EarColor or look.Primary, { Material = spec.EarMaterial or material })
		triangle(builder, "EarInner" .. index, 0.26, earHeight * 0.62, 0.15, earBase * CFrame.new(0, -earHeight * 0.1, -0.02), spec.EarInner)
		if spec.EarTip then
			triangle(builder, "EarTip" .. index, 0.17, earHeight * 0.34, 0.16, earBase * CFrame.new(0, earHeight * 0.33, 0), spec.EarTip)
		end
	end

	-- Patas con almohadillas
	for index, leg in { Vector3.new(-0.3, 0, -0.25), Vector3.new(0.3, 0, -0.25), Vector3.new(-0.3, 0, 0.55), Vector3.new(0.3, 0, 0.55) } do
		ellipsoid(builder, "Leg" .. index, Vector3.new(0.3, 0.42, 0.3), CFrame.new(leg.X, -0.52, leg.Z), darken(look.Primary, 0.12), { Material = material })
		ellipsoid(builder, "Paw" .. index, Vector3.new(0.32, 0.16, 0.36), CFrame.new(leg.X, -0.7, leg.Z - 0.03), spec.Paws)
	end

	if spec.Tail ~= false then
		local center = FOX_TAIL_BASE + FOX_TAIL_DIR * 0.55
		ellipsoid(builder, "Tail", Vector3.new(0.62, 0.62, 1.15), CFrame.lookAt(center, center + FOX_TAIL_DIR), look.Primary, { Material = material, Anim = foxWag() })
		local tip = FOX_TAIL_BASE + FOX_TAIL_DIR * 1.15
		ellipsoid(builder, "TailTip", Vector3.new(0.52, 0.52, 0.58), CFrame.lookAt(tip, tip + FOX_TAIL_DIR), spec.TailTip or spec.Fur, { Material = spec.TailTipMaterial, Anim = foxWag() })
	end
end

-- Zorro de Musgo: pelaje cálido, musgo en el lomo, punta de cola de musgo y un brote.
local function buildFox(builder: Builder, look: Look)
	buildFoxBase(builder, look, {
		Fur = CREAM,
		Paws = darken(look.Primary, 0.45),
		EarInner = Color3.fromRGB(255, 200, 190),
		EarHeight = 0.55,
		TailTip = look.Secondary,
	})
	-- Musgo en el lomo y en la cola
	ellipsoid(builder, "MossBack", Vector3.new(0.72, 0.22, 0.85), CFrame.new(0, 0.3, 0.22) * CFrame.Angles(math.rad(-8), 0, 0), look.Secondary)
	for index, offset in { Vector3.new(-0.22, 0.38, 0.05), Vector3.new(0.2, 0.36, 0.42), Vector3.new(0.05, 0.4, 0.2) } do
		ball(builder, "MossTuft" .. index, 0.22, offset, lighten(look.Secondary, 0.12))
	end
	-- Brote en la cabeza
	local sproutBase = Vector3.new(0.12, 0.98, -0.62)
	block(builder, "Sprout", Vector3.new(0.06, 0.22, 0.06), CFrame.new(sproutBase + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, -0.2), darken(look.Secondary, 0.1))
	for index, side in { -1, 1 } do
		local top = sproutBase + Vector3.new(0.03, 0.18, 0)
		local sway: Anim = { Hinge = top, Axis = Vector3.new(0, 0, side), Amp = 0.2, Speed = 3.5, Phase = index }
		leaf(builder, "SproutLeaf" .. index, 0.34, CFrame.new(top) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0.45), lighten(look.Secondary, 0.1), { Anim = sway })
	end
end

-- Zorrito de Brasa: orejas largas con punta negra, cola de llama luminosa y brasas.
local function buildEmber(builder: Builder, look: Look)
	buildFoxBase(builder, look, {
		Fur = Color3.fromRGB(255, 236, 214),
		Paws = Color3.fromRGB(70, 40, 36),
		EarInner = Color3.fromRGB(255, 186, 140),
		EarTip = Color3.fromRGB(56, 34, 32),
		EarHeight = 0.7,
		Tail = false,
	})
	-- Cola: pelaje que termina en una llama (lágrimas luminosas y fuego de partículas).
	local flicker: Anim = { Hinge = FOX_TAIL_BASE, Axis = Vector3.yAxis, Amp = 0.28, Speed = 5 }
	local furCenter = FOX_TAIL_BASE + FOX_TAIL_DIR * 0.45
	ellipsoid(builder, "Tail", Vector3.new(0.56, 0.56, 0.95), CFrame.lookAt(furCenter, furCenter + FOX_TAIL_DIR), look.Primary, { Anim = flicker })
	local flameBase = FOX_TAIL_BASE + FOX_TAIL_DIR * 0.95
	-- El neón aclara mucho los colores: la llama exterior es rojo anaranjado para que se
	-- vea naranja, y solo el núcleo es amarillo.
	local flameOuter = Color3.fromRGB(196, 52, 12)
	local outer = ellipsoid(builder, "Flame", Vector3.new(0.46, 0.66, 0.46), CFrame.new(flameBase + Vector3.new(0, 0.26, 0)), flameOuter, { Material = Enum.Material.Neon, Anim = flicker })
	ellipsoid(builder, "FlameMid", Vector3.new(0.34, 0.5, 0.34), CFrame.new(flameBase + Vector3.new(0, 0.26, -0.08)), Color3.fromRGB(224, 104, 20), { Material = Enum.Material.Neon, Anim = flicker })
	ellipsoid(builder, "FlameCore", Vector3.new(0.2, 0.3, 0.2), CFrame.new(flameBase + Vector3.new(0, 0.22, -0.16)), Color3.fromRGB(240, 176, 60), { Material = Enum.Material.Neon, Anim = flicker })
	triangle(builder, "FlameTip", 0.3, 0.4, 0.3, CFrame.new(flameBase + Vector3.new(0, 0.66, 0)), flameOuter, { Material = Enum.Material.Neon, Anim = flicker })
	triangle(builder, "FlameTipSide", 0.3, 0.4, 0.3, CFrame.new(flameBase + Vector3.new(0, 0.66, 0)) * CFrame.Angles(0, math.rad(90), 0), flameOuter, { Material = Enum.Material.Neon, Anim = flicker })

	-- Llamita en la frente
	triangle(builder, "BrowFlame", 0.16, 0.24, 0.06, surface(FOX_HEAD_CENTER, FOX_HEAD_SEMI, 0, 40) * CFrame.new(0, 0.04, -0.01), Color3.fromRGB(255, 210, 110), { Material = Enum.Material.Neon })

	local fire = Instance.new("ParticleEmitter")
	fire.Name = "TailFire"
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Rate = 14
	fire.Lifetime = NumberRange.new(0.35, 0.6)
	fire.Speed = NumberRange.new(1, 1.6)
	fire.EmissionDirection = Enum.NormalId.Top
	fire.SpreadAngle = Vector2.new(12, 12)
	fire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	fire.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(230, 60, 20))
	fire.LightEmission = 0.6
	fire.LightInfluence = 0
	fire.Parent = outer
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Rate = 4
	embers.Lifetime = NumberRange.new(0.6, 1)
	embers.Speed = NumberRange.new(0.5, 1.2)
	embers.Acceleration = Vector3.new(0, 2, 0)
	embers.Size = NumberSequence.new(0.12, 0)
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 110, 40))
	embers.LightEmission = 1
	embers.Parent = outer
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 150, 70)
	glow.Brightness = 0.7
	glow.Range = 6
	glow.Shadows = false
	glow.Parent = outer
end

-- Zorrito de Cuarzo: cuerpo de cristal, orejas de prisma, gema en la frente y cola de
-- fragmentos en abanico.
local function buildQuartz(builder: Builder, look: Look)
	buildFoxBase(builder, look, {
		Fur = Color3.fromRGB(255, 246, 250),
		Paws = look.Secondary,
		EarInner = lighten(look.Secondary, 0.35),
		EarHeight = 0.62,
		EarColor = look.Secondary,
		EarMaterial = Enum.Material.Neon,
		Tail = false,
	})
	gem(builder, "BrowGem", 0.18, CFrame.new(surface(FOX_HEAD_CENTER, FOX_HEAD_SEMI, 0, 38).Position), look.Secondary, { Material = Enum.Material.Neon })
	for index, spec in { { Vector3.new(0, 0.26, -0.02), 0.18, 0.48, 10 }, { Vector3.new(0.12, 0.24, 0.3), 0.15, 0.38, 25 }, { Vector3.new(-0.12, 0.2, 0.5), 0.13, 0.32, 35 } } do
		crystal(builder, "BackCrystal" .. index, spec[2], spec[3], CFrame.new(spec[1]) * CFrame.Angles(math.rad(spec[4]), 0, -spec[1].X), look.Secondary, { Material = Enum.Material.Neon })
	end
	for index, side in { -1, 1 } do
		gem(builder, "CheekGem" .. index, 0.1, CFrame.new(surface(FOX_HEAD_CENTER, FOX_HEAD_SEMI, side * 62, 6).Position), look.Secondary, { Material = Enum.Material.Neon })
	end
	-- Cola: cinco fragmentos en abanico
	for index, angle in { -0.7, -0.35, 0, 0.35, 0.7 } do
		local shardLength = if index == 3 then 1.05 else 0.85 - math.abs(angle) * 0.3
		local offset = CFrame.new(FOX_TAIL_BASE) * CFrame.Angles(0, 0, angle) * CFrame.Angles(math.rad(55), 0, 0)
		local material = if index % 2 == 1 then Enum.Material.Glass else Enum.Material.Neon
		local color = if index % 2 == 1 then look.Primary else look.Secondary
		crystal(builder, "TailShard" .. index, 0.24, shardLength, offset, color, { Material = material, Anim = foxWag() })
	end
end

-- Búho Lunar: plumaje suave, disco facial, ojos dorados, alas que aletean y luna creciente.
local function buildOwl(builder: Builder, look: Look)
	local bodyCenter = Vector3.zero
	local bodySemi = Vector3.new(0.75, 0.82, 0.7)
	ellipsoid(builder, "Body", bodySemi * 2, CFrame.new(bodyCenter), look.Primary)
	ellipsoid(builder, "Belly", Vector3.new(1.0, 1.0, 0.5), CFrame.new(0, -0.28, -0.5), Color3.fromRGB(228, 230, 246))
	for index, spot in { { -18, -30 }, { 18, -30 }, { 0, -44 } } do
		triangle(builder, "Feather" .. index, 0.14, 0.1, 0.04, surface(Vector3.new(0, -0.28, -0.5), Vector3.new(0.5, 0.5, 0.25), spot[1], spot[2]) * CFrame.Angles(0, 0, math.pi), lighten(look.Secondary, 0.25))
	end

	-- Disco facial y ojos dorados
	for index, side in { -1, 1 } do
		local discCf = surface(bodyCenter, bodySemi, side * 22, 20) * CFrame.new(0, 0, -0.02)
		ellipsoid(builder, "FaceDisc" .. index, Vector3.new(0.64, 0.64, 0.12), discCf, Color3.fromRGB(238, 240, 252))
		eye(builder, "Eye" .. index, discCf * CFrame.new(0, 0, -0.05), 0.44, 0.44, { Iris = GOLD })
	end
	triangle(builder, "Beak", 0.2, 0.22, 0.12, surface(bodyCenter, bodySemi, 0, 4) * CFrame.new(0, 0, -0.06) * CFrame.Angles(0, 0, math.pi), GOLD)

	-- Penachos
	for index, side in { -1, 1 } do
		triangle(builder, "Tuft" .. index, 0.26, 0.48, 0.12, CFrame.new(side * 0.45, 0.86, -0.12) * CFrame.Angles(0, 0, -side * 0.45), look.Secondary)
	end

	-- Luna creciente luminosa en la frente
	local markCf = surface(bodyCenter, bodySemi, 0, 46)
	ellipsoid(builder, "MoonMark", Vector3.new(0.3, 0.3, 0.06), markCf, Color3.fromRGB(235, 244, 255), { Material = Enum.Material.Neon })
	ellipsoid(builder, "MoonShade", Vector3.new(0.26, 0.26, 0.07), markCf * CFrame.new(0.08, 0.05, -0.01), look.Primary)

	-- Alas (aletean hacia fuera)
	for index, side in { -1, 1 } do
		local flap: Anim = { Hinge = Vector3.new(side * 0.6, 0.35, 0.1), Axis = Vector3.new(0, 0, side), Offset = 0.3, Amp = 0.35, Speed = 7, Phase = 0 }
		ellipsoid(builder, "Wing" .. index, Vector3.new(0.26, 1.0, 0.78), CFrame.new(side * 0.76, -0.05, 0.1) * CFrame.Angles(0, 0, side * 0.22), look.Secondary, { Anim = flap })
		ellipsoid(builder, "WingTip" .. index, Vector3.new(0.22, 0.5, 0.5), CFrame.new(side * 0.86, -0.42, 0.18) * CFrame.Angles(0, 0, side * 0.3), darken(look.Secondary, 0.15), { Anim = flap })
		ellipsoid(builder, "Foot" .. index, Vector3.new(0.2, 0.12, 0.28), CFrame.new(side * 0.22, -0.82, -0.22), GOLD)
	end
end

-- Cervatillo Esmeralda: cabeza grande, orejas grandes, astas de cristal y manchas claras.
local function buildFawn(builder: Builder, look: Look)
	local fur = Color3.fromRGB(255, 240, 222)
	ellipsoid(builder, "Torso", Vector3.new(0.95, 0.85, 1.5), CFrame.new(0, 0, 0.25), look.Primary)
	ellipsoid(builder, "Chest", Vector3.new(0.56, 0.6, 0.4), CFrame.new(0, 0, -0.42), fur)
	local neckFrom, neckTo = Vector3.new(0, 0.15, -0.3), Vector3.new(0, 0.95, -0.62)
	ellipsoid(builder, "Neck", Vector3.new(0.42, 0.42, 0.95), CFrame.lookAt((neckFrom + neckTo) / 2, neckTo), look.Primary)

	local headCenter = Vector3.new(0, 1.15, -0.72)
	local headSemi = Vector3.new(0.48, 0.43, 0.45)
	ellipsoid(builder, "Head", headSemi * 2, CFrame.new(headCenter), look.Primary)
	ellipsoid(builder, "Muzzle", Vector3.new(0.46, 0.34, 0.42), CFrame.new(0, 1.0, -1.08), fur)
	nose(builder, Vector3.new(0, 1.06, -1.29), 0.13)
	eyes(builder, headCenter, headSemi, 34, 10, 0.24, 0.3)
	cheeks(builder, headCenter, headSemi, 56, -10, 0.16)

	for index, side in { -1, 1 } do
		local earCf = CFrame.new(side * 0.52, 1.3, -0.64) * CFrame.Angles(0, 0, side * 0.4)
		ellipsoid(builder, "Ear" .. index, Vector3.new(0.56, 0.22, 0.13), earCf, look.Primary)
		ellipsoid(builder, "EarInner" .. index, Vector3.new(0.38, 0.13, 0.14), earCf * CFrame.new(side * 0.02, 0, -0.02), Color3.fromRGB(255, 196, 196))

		-- Astas de cristal: tronco, rama y puntas
		local antlerBase = CFrame.new(side * 0.2, 1.5, -0.68) * CFrame.Angles(math.rad(10), 0, -side * 0.35)
		block(builder, "Antler" .. index, Vector3.new(0.1, 0.5, 0.1), antlerBase * CFrame.new(0, 0.22, 0), look.Secondary, { Material = Enum.Material.Neon })
		gem(builder, "AntlerTip" .. index, 0.13, antlerBase * CFrame.new(0, 0.48, 0), lighten(look.Secondary, 0.3), { Material = Enum.Material.Neon })
		local branch = antlerBase * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, -side * 0.85)
		block(builder, "AntlerBranch" .. index, Vector3.new(0.08, 0.32, 0.08), branch * CFrame.new(0, 0.15, 0), look.Secondary, { Material = Enum.Material.Neon })
		gem(builder, "AntlerBranchTip" .. index, 0.11, branch * CFrame.new(0, 0.32, 0), lighten(look.Secondary, 0.3), { Material = Enum.Material.Neon })
	end

	-- Manchas claras sobre el lomo
	local torsoCenter, torsoSemi = Vector3.new(0, 0, 0.25), Vector3.new(0.475, 0.425, 0.75)
	for index, spot in { { 150, 40, 0.2 }, { -160, 50, 0.16 }, { 170, 25, 0.14 }, { -140, 30, 0.18 }, { 120, 55, 0.13 } } do
		ellipsoid(builder, "Spot" .. index, Vector3.new(spot[3], spot[3], 0.05), surface(torsoCenter, torsoSemi, spot[1], spot[2]), fur)
	end

	-- Patas finas con pezuñas
	for index, leg in { Vector3.new(-0.25, 0, -0.22), Vector3.new(0.25, 0, -0.22), Vector3.new(-0.25, 0, 0.68), Vector3.new(0.25, 0, 0.68) } do
		ellipsoid(builder, "Leg" .. index, Vector3.new(0.25, 0.92, 0.27), CFrame.new(leg.X, -0.76, leg.Z), darken(look.Primary, 0.12))
		ellipsoid(builder, "Hoof" .. index, Vector3.new(0.27, 0.16, 0.3), CFrame.new(leg.X, -1.28, leg.Z - 0.02), Color3.fromRGB(70, 52, 44))
	end

	local wag: Anim = { Hinge = Vector3.new(0, 0.25, 0.95), Axis = Vector3.yAxis, Amp = 0.4, Speed = 7 }
	ellipsoid(builder, "Tail", Vector3.new(0.3, 0.4, 0.28), CFrame.new(0, 0.3, 1.02) * CFrame.Angles(math.rad(-30), 0, 0), fur, { Anim = wag })
end

-- Tortuga de Musgo Cristalino: caparazón de musgo con placas, cristales y matas.
local TURTLE_SKIN = Color3.fromRGB(172, 196, 132)
local function buildTurtle(builder: Builder, look: Look)
	ellipsoid(builder, "Body", Vector3.new(1.5, 0.6, 1.7), CFrame.new(0, -0.15, 0.05), TURTLE_SKIN)
	local shellCenter, shellSemi = Vector3.new(0, 0.2, 0.05), Vector3.new(0.98, 0.62, 1.08)
	ellipsoid(builder, "Shell", shellSemi * 2, CFrame.new(shellCenter), look.Primary)
	newPart(builder, "ShellRim", "Cylinder", Vector3.new(0.16, 2.06, 2.06), CFrame.new(0, -0.05, 0.05) * CFrame.Angles(0, 0, math.rad(90)), darken(look.Primary, 0.25))
	for index, plate in { { 180, 55 }, { 120, 35 }, { -120, 35 }, { 60, 32 }, { -60, 32 }, { 0, 30 } } do
		ellipsoid(builder, "Plate" .. index, Vector3.new(0.5, 0.42, 0.06), surface(shellCenter, shellSemi, plate[1], plate[2]), lighten(look.Primary, 0.12))
	end
	for index, tuft in { { 150, 20 }, { -100, 18 }, { 30, 15 } } do
		local cf = surface(shellCenter, shellSemi, tuft[1], tuft[2])
		ball(builder, "Moss" .. index, 0.26, cf.Position, darken(look.Primary, 0.1), { Material = Enum.Material.LeafyGrass })
	end

	-- Cristales del caparazón
	local up = CFrame.Angles(0, 0, 0)
	for index, spec in {
		{ Vector3.new(0, 0.72, 0.15), 0.32, 0.9, up, Enum.Material.Neon },
		{ Vector3.new(-0.24, 0.66, -0.02), 0.22, 0.62, CFrame.Angles(math.rad(-12), 0, math.rad(22)), Enum.Material.Glass },
		{ Vector3.new(0.26, 0.64, 0.32), 0.24, 0.66, CFrame.Angles(math.rad(14), 0, math.rad(-24)), Enum.Material.Glass },
		{ Vector3.new(0.5, 0.42, -0.32), 0.16, 0.4, CFrame.Angles(math.rad(-20), 0, math.rad(-40)), Enum.Material.Neon },
		{ Vector3.new(-0.5, 0.44, 0.5), 0.16, 0.42, CFrame.Angles(math.rad(25), 0, math.rad(38)), Enum.Material.Neon },
	} do
		local color = if spec[5] == Enum.Material.Glass then lighten(look.Secondary, 0.3) else look.Secondary
		crystal(builder, "ShellCrystal" .. index, spec[2], spec[3], CFrame.new(spec[1]) * spec[4], color, { Material = spec[5] })
	end

	-- Cabeza
	local headCenter, headSemi = Vector3.new(0, 0.05, -1.1), Vector3.new(0.36, 0.31, 0.36)
	ellipsoid(builder, "Head", headSemi * 2, CFrame.new(headCenter), TURTLE_SKIN)
	eyes(builder, headCenter, headSemi, 34, 12, 0.18, 0.24)
	cheeks(builder, headCenter, headSemi, 56, -10, 0.13)
	mouth(builder, surface(headCenter, headSemi, 0, -14), 0.12)

	for index, leg in { Vector3.new(-0.68, -0.38, -0.55), Vector3.new(0.68, -0.38, -0.55), Vector3.new(-0.68, -0.38, 0.65), Vector3.new(0.68, -0.38, 0.65) } do
		ellipsoid(builder, "Leg" .. index, Vector3.new(0.5, 0.45, 0.55), CFrame.new(leg), darken(TURTLE_SKIN, 0.06))
	end
	local wag: Anim = { Hinge = Vector3.new(0, -0.15, 0.95), Axis = Vector3.yAxis, Amp = 0.3, Speed = 3 }
	ellipsoid(builder, "Tail", Vector3.new(0.22, 0.18, 0.36), CFrame.new(0, -0.15, 1.12), TURTLE_SKIN, { Anim = wag })
end

-- Dragón Bebé de Amatista: cabeza grande, ojos dorados de pupila rasgada, cuernos y púas
-- de cristal, alas que baten y cola con punta de gema.
local function buildDragon(builder: Builder, look: Look)
	local belly = Color3.fromRGB(232, 214, 250)
	local glowing = look.Secondary:Lerp(look.Primary, 0.45) -- el neón aclara mucho: más saturado
	ellipsoid(builder, "Body", Vector3.new(1.05, 1.15, 1.15), CFrame.new(0, -0.1, 0.05), look.Primary)
	ellipsoid(builder, "Belly", Vector3.new(0.7, 0.85, 0.4), CFrame.new(0, -0.2, -0.38), belly)
	for index = 1, 3 do
		block(builder, "BellyBand" .. index, Vector3.new(0.5 - index * 0.06, 0.035, 0.05), CFrame.new(0, -0.02 - index * 0.17, -0.57 + index * 0.01), darken(belly, 0.12))
	end

	local headCenter, headSemi = Vector3.new(0, 0.68, -0.55), Vector3.new(0.58, 0.5, 0.52)
	ellipsoid(builder, "Head", headSemi * 2, CFrame.new(headCenter), look.Primary)
	ellipsoid(builder, "Snout", Vector3.new(0.7, 0.48, 0.6), CFrame.new(0, 0.5, -1.02), lighten(look.Primary, 0.15))
	for index, side in { -1, 1 } do
		ball(builder, "Nostril" .. index, 0.07, Vector3.new(side * 0.12, 0.6, -1.31), darken(look.Primary, 0.5))
	end
	mouth(builder, CFrame.lookAt(Vector3.new(0, 0.38, -1.28), Vector3.new(0, 0.38, -2)), 0.2)
	eyes(builder, headCenter, headSemi, 30, 18, 0.28, 0.36, { Iris = GOLD, Slit = true })
	cheeks(builder, headCenter, headSemi, 52, -6, 0.2)
	gem(builder, "BrowGem", 0.16, CFrame.new(surface(headCenter, headSemi, 0, 46).Position), GOLD, { Material = Enum.Material.Neon })

	for index, side in { -1, 1 } do
		-- Cuernos y aletas de las orejas
		crystal(builder, "Horn" .. index, 0.14, 0.52, CFrame.new(side * 0.25, 1.06, -0.42) * CFrame.Angles(math.rad(30), 0, -side * 0.25), glowing, { Material = Enum.Material.Neon })
		triangle(builder, "EarFin" .. index, 0.26, 0.34, 0.06, CFrame.new(side * 0.58, 0.82, -0.42) * CFrame.Angles(0, side * 0.6, -side * 0.9), look.Secondary)

		-- Alas abiertas hacia los lados y atrás: hueso arriba, membrana y festón abajo.
		-- Baten juntas alrededor del hombro (eje vertical).
		local flap: Anim = { Hinge = Vector3.new(side * 0.3, 0.4, 0.3), Axis = Vector3.new(0, side, 0), Offset = -0.1, Amp = 0.4, Speed = 7 }
		local wingCf = CFrame.new(side * 0.95, 0.62, 0.42) * CFrame.Angles(0, side * 0.35, side * 0.45)
		ellipsoid(builder, "WingBone" .. index, Vector3.new(1.4, 0.13, 0.13), wingCf * CFrame.new(0, 0.4, 0), darken(look.Primary, 0.1), { Anim = flap })
		ellipsoid(builder, "Wing" .. index, Vector3.new(1.3, 0.85, 0.06), wingCf, look.Secondary, { Anim = flap })
		for claw = 1, 3 do
			ellipsoid(builder, "WingScallop" .. index .. claw, Vector3.new(0.34, 0.3, 0.06), wingCf * CFrame.new(side * (claw - 2) * 0.36, -0.36, 0), look.Secondary, { Anim = flap })
		end

		-- Bracitos y patas
		ellipsoid(builder, "Arm" .. index, Vector3.new(0.22, 0.36, 0.22), CFrame.new(side * 0.45, -0.3, -0.3) * CFrame.Angles(math.rad(-30), 0, side * 0.3), look.Primary)
		ellipsoid(builder, "Leg" .. index, Vector3.new(0.34, 0.4, 0.38), CFrame.new(side * 0.32, -0.62, 0.05), darken(look.Primary, 0.08))
		ellipsoid(builder, "Foot" .. index, Vector3.new(0.3, 0.14, 0.36), CFrame.new(side * 0.32, -0.8, -0.03), belly)
	end

	-- Púas del lomo
	for index, spec in { { Vector3.new(0, 0.42, 0.18), 0.2 }, { Vector3.new(0, 0.32, 0.46), 0.17 }, { Vector3.new(0, 0.12, 0.66), 0.14 } } do
		gem(builder, "Spike" .. index, spec[2], CFrame.new(spec[1]) * CFrame.Angles(math.rad(35), 0, 0), glowing, { Material = Enum.Material.Neon })
	end

	-- Cola en tramos (se balancea entera) con punta de gema
	local wag: Anim = { Hinge = Vector3.new(0, -0.3, 0.5), Axis = Vector3.yAxis, Amp = 0.25, Speed = 3 }
	for index, spec in { { Vector3.new(0, -0.35, 0.65), 0.5 }, { Vector3.new(0, -0.3, 1.0), 0.38 }, { Vector3.new(0, -0.15, 1.3), 0.28 }, { Vector3.new(0, 0.05, 1.5), 0.2 } } do
		ball(builder, "Tail" .. index, spec[2], spec[1], look.Primary, { Anim = wag })
	end
	gem(builder, "TailGem", 0.22, CFrame.new(0, 0.22, 1.64) * CFrame.Angles(math.rad(40), 0, 0), glowing, { Material = Enum.Material.Neon, Anim = wag })
end

local function buildGeneric(builder: Builder, look: Look)
	local center, semi = Vector3.zero, Vector3.new(0.75, 0.75, 0.75)
	ellipsoid(builder, "Body", semi * 2, CFrame.new(center), look.Primary)
	eyes(builder, center, semi, 24, 12, 0.28, 0.36)
	cheeks(builder, center, semi, 42, -6, 0.24)
	ball(builder, "Crest", 0.5, Vector3.new(0, 0.85, 0), look.Secondary)
end

local STYLES: { [string]: (Builder, Look) -> () } = {
	Sprout = buildSprout,
	Fox = buildFox,
	Owl = buildOwl,
	Mushroom = buildMushroom,
	Ember = buildEmber,
	Fawn = buildFawn,
	Quartz = buildQuartz,
	Turtle = buildTurtle,
	Dragon = buildDragon,
}

-- Color del brillo de rareza: el acento de la mascota.
local function glowColor(look: Look): Color3
	return look.Secondary
end

-- Arte externo: ReplicatedStorage.PetModels.<PetId>, si existe (o el de su mascota base si es
-- una ★ Evo sin modelo propio).
local EVO_ART_SCALE = 1.15

local function fromArt(petId: string): (Model?, BasePart?)
	local folder = ReplicatedStorage:FindFirstChild("PetModels")
	local art = folder and folder:FindFirstChild(petId)
	local evolved = false
	if not art and folder and string.sub(petId, -4) == "_Evo" then
		art = folder:FindFirstChild(string.sub(petId, 1, -5))
		evolved = art ~= nil
	end
	if not (art and art:IsA("Model") and art.PrimaryPart) then
		return nil, nil
	end
	local model = art:Clone()
	local root = model.PrimaryPart :: BasePart
	model:PivotTo(CFrame.new())
	if evolved then
		model:ScaleTo(model:GetScale() * EVO_ART_SCALE)
	end
	local growth = if evolved then EVO_ART_SCALE else 1
	local pet = PetConfig.Pets[petId]
	local look = if pet then pet.Look else nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = true
			descendant.Anchored = descendant == root
			if descendant ~= root then
				local tint = descendant:GetAttribute("PetTint")
				if evolved and look and tint == "Primary" and look.Primary then
					descendant.Color = look.Primary
				elseif evolved and look and tint == "PrimaryDark" and look.Primary then
					descendant.Color = darken(look.Primary, 0.38)
				elseif evolved and look and tint == "Secondary" and look.Secondary then
					descendant.Color = look.Secondary
				end
				local hinge = descendant:GetAttribute("AnimHinge")
				local axis = descendant:GetAttribute("AnimAxis")
				if typeof(hinge) == "Vector3" and typeof(axis) == "Vector3" and axis.Magnitude > 0 then
					-- Pieza animada: Weld "PetAnim" (PetAnimator mueve su C0)
					local weld = Instance.new("Weld")
					weld.Name = "PetAnim"
					weld.Part0 = root
					weld.Part1 = descendant
					weld.C0 = root.CFrame:ToObjectSpace(descendant.CFrame)
					weld:SetAttribute("Hinge", hinge * growth)
					weld:SetAttribute("Axis", axis.Unit)
					for _, name in { "Offset", "Amp", "Speed", "Phase" } do
						local value = descendant:GetAttribute("Anim" .. name)
						weld:SetAttribute(name, if typeof(value) == "number" then value else (if name == "Speed" then 1 else 0))
					end
					weld.Parent = descendant
				else
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = root
					weld.Part1 = descendant
					weld.Parent = descendant
				end
			end
		end
	end
	model.Name = "Pet_" .. petId
	return model, root
end

-- Devuelve el modelo y su pieza raíz, o nil si la mascota no existe en la configuración.
function PetModelBuilder.build(petId: string): (Model?, BasePart?)
	local pet = PetConfig.Pets[petId]
	if not pet then
		return nil, nil
	end
	local artModel, artRoot = fromArt(petId)
	if artModel and artRoot then
		local artLook = pet.Look or {}
		addRarityEffects({ Model = artModel, Root = artRoot }, pet.Rarity, artLook.Secondary or artLook.Primary or WHITE)
		return artModel, artRoot
	end

	local look = pet.Look or {}
	local primary = look.Primary or Color3.fromRGB(200, 200, 200)
	local resolvedLook: Look = {
		Primary = primary,
		Secondary = look.Secondary or primary,
	}

	local model = Instance.new("Model")
	model.Name = "Pet_" .. petId

	-- Raíz invisible en el centro del cuerpo: todo cuelga de ella.
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.one * 0.5
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	local builder: Builder = { Model = model, Root = root }
	local buildStyle = STYLES[look.Style] or buildGeneric
	buildStyle(builder, resolvedLook)
	addRarityEffects(builder, pet.Rarity, glowColor(resolvedLook))

	return model, root
end

return PetModelBuilder
