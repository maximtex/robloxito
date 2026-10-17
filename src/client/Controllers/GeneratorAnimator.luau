-- Animación local del Santuario del Núcleo Cósmico: el cristal flota y gira despacio
-- (exterior, núcleo, grietas y halo como un solo bloque), los tres fragmentos siguen sus
-- órbitas inclinadas (GeneratorConfig.orbitOffset), las rocas se balancean y la luz pulsa.
-- Es el ÚNICO script que mueve piezas del cristal y fija el brillo de su luz;
-- CrystalAppearance solo cambia colores, transparencias y emisores, y le pasa la
-- intensidad de la etapa con setIntensity().
-- UNA conexión (Heartbeat) y un único BulkMoveTo por fotograma para todas las piezas; se
-- pausa lejos de la cámara. Solo mueve piezas en este cliente (no afecta al servidor).
-- Si el modelo aún no existe (o se descarga por streaming), lo vuelve a buscar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GeneratorConfig = require(ReplicatedStorage:WaitForChild("Shared").Config.GeneratorConfig)

local Animation = GeneratorConfig.Animation
local Burst = GeneratorConfig.PurchaseBurst
local Evolution = GeneratorConfig.Evolution
local SEARCH_INTERVAL = 1

type Rig = {
	Model: Model,
	Center: Vector3, -- centro del cristal en reposo
	Floating: { BasePart }, -- cristal: se mueve como un bloque
	FloatingOffsets: { CFrame },
	Orbiters: { BasePart },
	Fragments: { BasePart },
	Rocks: { BasePart },
	RockHomes: { CFrame },
	Light: PointLight?,
	Particles: ParticleEmitter?,
	Parts: { BasePart },
	CFrames: { CFrame },
}

local GeneratorAnimator = {}

local rig: Rig? = nil
local elapsed = 0
local searchTimer = 0
local flash = 0
local intensity = 1 -- multiplicador de brillo actual (se acerca suavemente al objetivo)
local targetIntensity = 1

local function sortedParts(container: Instance?): { BasePart }
	local parts = {}
	if container then
		for _, child in container:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(parts, child)
			end
		end
		table.sort(parts, function(a, b)
			return a.Name < b.Name
		end)
	end
	return parts
end

local function findRig(): Rig?
	local model = Workspace:FindFirstChild(GeneratorConfig.ModelName)
	if not (model and model:IsA("Model")) then
		return nil
	end

	local core = model:FindFirstChild("Core")
	if not (core and core:IsA("BasePart")) then
		return nil
	end
	-- Espera a que lleguen todos los fragmentos para no fijar un reparto incompleto.
	local orbiters = sortedParts(model:FindFirstChild("Orbiters"))
	if #orbiters < GeneratorConfig.OrbiterCount then
		return nil
	end

	-- Fragmentos de la evolución (ocultos hasta su etapa, pero siempre animados aquí).
	local details = model:FindFirstChild("StageDetails")
	local fragmentGroup = details and details:FindFirstChild("Fragments")
	local fragments = sortedParts(fragmentGroup)
	if fragmentGroup and #fragments < Evolution.FragmentCount then
		return nil
	end

	-- El cristal (núcleo, halo y exterior) gira alrededor de su centro como un bloque.
	local center = core.Position
	local pivot = CFrame.new(center)
	local floating: { BasePart } = { core }
	local shell = model:FindFirstChild("Shell")
	if shell and shell:IsA("BasePart") then
		table.insert(floating, shell)
	end
	for _, part in sortedParts(model:FindFirstChild("CrystalBody")) do
		table.insert(floating, part)
	end
	local offsets = {}
	for index, part in floating do
		offsets[index] = pivot:ToObjectSpace(part.CFrame)
	end

	local rocks = sortedParts(model:FindFirstChild("FloatingRocks"))
	local rockHomes = {}
	for index, rock in rocks do
		rockHomes[index] = rock.CFrame
	end

	local parts: { BasePart } = {}
	for _, list in { floating, orbiters, fragments, rocks } do
		for _, part in list do
			table.insert(parts, part)
		end
	end

	return {
		Model = model,
		Center = center,
		Floating = floating,
		FloatingOffsets = offsets,
		Orbiters = orbiters,
		Fragments = fragments,
		Rocks = rocks,
		RockHomes = rockHomes,
		Light = core:FindFirstChildOfClass("PointLight"),
		Particles = core:FindFirstChildOfClass("ParticleEmitter"),
		Parts = parts,
		CFrames = table.create(#parts),
	}
end

local function isRigValid(current: Rig): boolean
	if not current.Model:IsDescendantOf(Workspace) then
		return false
	end
	for _, part in current.Parts do
		if not part:IsDescendantOf(current.Model) then
			return false
		end
	end
	return true
end

local function animate(current: Rig)
	local cframes = current.CFrames
	local index = 0

	-- Cristal: flotación suave y giro lento, todo junto.
	local bob = math.sin(elapsed * Animation.CoreBobSpeed) * Animation.CoreBobHeight
	local center = current.Center + Vector3.new(0, bob, 0)
	local pivot = CFrame.new(center) * CFrame.Angles(0, elapsed * Animation.CrystalSpinSpeed, 0)
	for partIndex = 1, #current.Floating do
		index += 1
		cframes[index] = pivot * current.FloatingOffsets[partIndex]
	end

	-- Fragmentos: cada uno en su órbita inclinada, con su velocidad y giro propio. Siguen
	-- la flotación del cristal, así que la separación entre ellos no cambia nunca.
	for orbiterIndex = 1, #current.Orbiters do
		local orbit = GeneratorConfig.Orbits[orbiterIndex] or GeneratorConfig.Orbits[1]
		local x, y, z = GeneratorConfig.orbitOffset(orbit, elapsed)
		local spin = elapsed * orbit.Spin
		index += 1
		cframes[index] = CFrame.new(center + Vector3.new(x, y, z)) * CFrame.Angles(spin * 0.6, spin, math.rad(20))
	end

	-- Corona de chispas de la etapa Dorada, bajo la punta inferior del cristal.
	local fragmentCount = #current.Fragments
	for fragmentIndex = 1, fragmentCount do
		local angle = elapsed * Evolution.FragmentOrbitSpeed + (fragmentIndex - 1) / fragmentCount * math.pi * 2
		local offset = Vector3.new(
			math.cos(angle) * Evolution.FragmentOrbitRadius,
			Evolution.FragmentHeight + math.sin(elapsed * 1.3 + fragmentIndex) * 0.15,
			math.sin(angle) * Evolution.FragmentOrbitRadius
		)
		index += 1
		cframes[index] = CFrame.new(center + offset) * CFrame.Angles(0, elapsed * 2 + fragmentIndex, math.rad(15))
	end

	-- Rocas flotantes: balanceo lento con fases distintas.
	for rockIndex = 1, #current.Rocks do
		local lift = math.sin(elapsed * Animation.RockBobSpeed + rockIndex * 1.7) * Animation.RockBobHeight
		local turn = elapsed * 0.2 * (if rockIndex % 2 == 0 then 1 else -1)
		index += 1
		cframes[index] = current.RockHomes[rockIndex] * CFrame.new(0, lift, 0) * CFrame.Angles(0, turn, 0)
	end

	Workspace:BulkMoveTo(current.Parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	if current.Light then
		current.Light.Brightness = (Animation.LightBaseBrightness + math.sin(elapsed * Animation.PulseSpeed) * Animation.LightPulseAmount)
				* intensity
			+ flash * Burst.FlashBrightness
	end
end

local function onHeartbeat(deltaTime: number)
	elapsed += deltaTime
	flash = math.max(0, flash - deltaTime * Burst.FlashDecayPerSecond)
	intensity += (targetIntensity - intensity) * math.min(1, deltaTime * 2)

	local current = rig
	if current and not isRigValid(current) then
		rig = nil
		current = nil
	end

	if not current then
		searchTimer -= deltaTime
		if searchTimer <= 0 then
			searchTimer = SEARCH_INTERVAL
			rig = findRig()
		end
		return
	end

	-- No gastar CPU animando algo que está fuera de la vista lejana.
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - current.Center).Magnitude > Animation.MaxDistance then
		return
	end

	animate(current)
end

function GeneratorAnimator.start()
	RunService.Heartbeat:Connect(onHeartbeat)
end

-- Intensidad de la etapa de evolución (la fija CrystalAppearance).
-- Con `instant` se aplica de golpe (al iniciar); si no, se acerca en ~1-2 s.
function GeneratorAnimator.setIntensity(value: number, instant: boolean?)
	targetIntensity = math.max(value, 0)
	if instant then
		intensity = targetIntensity
	end
end

-- Ráfaga breve al comprar una mejora: destello de luz y partículas.
function GeneratorAnimator.playPurchaseBurst()
	flash = 1
	local current = rig
	if current and current.Particles and current.Particles.Parent then
		current.Particles:Emit(Burst.Particles)
	end
end

return GeneratorAnimator
