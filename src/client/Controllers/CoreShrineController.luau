-- Círculo Elemental en el cliente: pinta y anima los altares de los núcleos según los
-- datos del jugador local (cada cliente ve SUS núcleos). Solo visual.
--
-- - Lee Constants.Attributes.UnlockedCores ("Nature,Water,...") y SelectedCore, que
--   escribe el servidor (PlayerDataService). Sin ellos (datos sin cargar), todo se ve
--   dormido y «Próximamente». El panel para despertarlos es CoreController.
-- - Dormido: piedra gris; el cristal reposa en la columna y los fragmentos en el escalón.
--   Despierto: colores, luz y partículas; el cristal sube, flota y gira, y los fragmentos
--   orbitan. Activo (seleccionado): además, un haz de energía hasta el cristal central.
-- - Vista previa en Studio: Workspace:SetAttribute("CorePreview", true) o un id de
--   elemento ("Fire") para verlo activo.
-- Una conexión (Heartbeat) y un BulkMoveTo por fotograma; se pausa lejos de la cámara.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CoreConfig = require(Shared.Config.CoreConfig)
local CoreShrineConfig = require(Shared.Config.CoreShrineConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local formatNumber = require(Shared.Util.FormatNumber)

local Animation = CoreShrineConfig.Animation
local ALTAR = CoreShrineConfig.Altar
local SEARCH_INTERVAL = 1
local PREVIEW_ATTRIBUTE = "CorePreview"

local MUTED = Color3.fromRGB(198, 202, 186)
local GOLD = Color3.fromRGB(236, 200, 120)

type Rig = {
	Model: Model,
	Element: string,
	Order: number,
	X: number,
	Z: number,
	RestY: number,
	FloatY: number,
	Crystal: { BasePart },
	CrystalOffsets: { CFrame },
	Body: BasePart?,
	Orbiters: { BasePart },
	OrbiterRest: { CFrame },
	Tinted: { BasePart },
	AwakeOnly: { Instance },
	Burst: ParticleEmitter?,
	Title: TextLabel?,
	State: TextLabel?,
	Beam: Beam?,
	Wake: number,
	Spin: number,
	Awake: boolean?,
	Settled: boolean,
}

local CoreShrineController = {}

local player = Players.LocalPlayer
local rigs: { Rig } = {}
local rootModel: Model? = nil
local searchTimer = 0
local elapsed = 0

local function unlockCost(order: number): number
	local unlock = CoreConfig.Unlock
	return math.floor(unlock.BaseCost * unlock.Growth ^ (order - 2))
end

local function collect(model: Model): Rig?
	local elementId = model:GetAttribute("Element")
	local order = model:GetAttribute("Order")
	local restY = model:GetAttribute("RestY")
	local floatY = model:GetAttribute("FloatY")
	local base = model.PrimaryPart
	if typeof(elementId) ~= "string" or typeof(order) ~= "number" or typeof(restY) ~= "number" or typeof(floatY) ~= "number" or not base then
		return nil
	end
	local rig: Rig = {
		Model = model,
		Element = elementId,
		Order = order,
		X = base.Position.X,
		Z = base.Position.Z,
		RestY = restY,
		FloatY = floatY,
		Crystal = {},
		CrystalOffsets = {},
		Body = nil,
		Orbiters = {},
		OrbiterRest = {},
		Tinted = {},
		AwakeOnly = {},
		Burst = nil,
		Title = nil,
		State = nil,
		Beam = nil,
		Wake = 0,
		Spin = 0,
		Awake = nil,
		Settled = true,
	}
	local restCenter = CFrame.new(rig.X, restY, rig.Z)
	local crystal = model:FindFirstChild("Crystal")
	if crystal then
		for _, part in crystal:GetChildren() do
			if part:IsA("BasePart") then
				table.insert(rig.Crystal, part)
				table.insert(rig.CrystalOffsets, restCenter:ToObjectSpace(part.CFrame))
				if part.Name == "CrystalBody" then
					rig.Body = part
				end
			end
		end
	end
	local orbiters = model:FindFirstChild("Orbiters")
	if orbiters then
		local list = orbiters:GetChildren()
		table.sort(list, function(a, b)
			return a.Name < b.Name
		end)
		for _, part in list do
			if part:IsA("BasePart") then
				table.insert(rig.Orbiters, part)
				table.insert(rig.OrbiterRest, part.CFrame)
			end
		end
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("ShrineTint") ~= nil then
			table.insert(rig.Tinted, descendant)
		end
		if descendant:GetAttribute("AwakeOnly") == true then
			table.insert(rig.AwakeOnly, descendant)
		end
		if descendant:IsA("ParticleEmitter") and descendant.Name == "WakeBurst" then
			rig.Burst = descendant
		end
	end
	local label = model:FindFirstChild("Label", true)
	if label then
		rig.Title = label:FindFirstChild("Title") :: TextLabel?
		rig.State = label:FindFirstChild("State") :: TextLabel?
	end
	-- Aún llegando por la red: se vuelve a intentar en la siguiente búsqueda.
	if #rig.Crystal < 3 or not rig.Body or #rig.Orbiters == 0 or not rig.State or #rig.AwakeOnly == 0 then
		return nil
	end
	return rig
end

local EXPECTED_ALTARS = #CoreConfig.Order - 1 -- todos menos Naturaleza (el cristal central)

-- Estado del jugador: núcleos desbloqueados, principal, si la fase 2 está activa y secundario.
local function readState(): ({ [string]: boolean }, string?, boolean, string?)
	local preview = if RunService:IsStudio() then Workspace:GetAttribute(PREVIEW_ATTRIBUTE) else nil
	if preview == true or typeof(preview) == "string" then
		local all = {}
		for _, elementId in CoreConfig.Order do
			all[elementId] = true
		end
		return all, if typeof(preview) == "string" then preview else nil, true, nil
	end
	local value = player:GetAttribute(Constants.Attributes.UnlockedCores)
	if typeof(value) ~= "string" then
		return {}, nil, false, nil
	end
	local unlocked = {}
	for elementId in value:gmatch("[^,]+") do
		unlocked[elementId] = true
	end
	local selected = player:GetAttribute(Constants.Attributes.SelectedCore)
	local secondary = player:GetAttribute(Constants.Attributes.SecondaryCore)
	return unlocked, if typeof(selected) == "string" then selected else nil, true, if typeof(secondary) == "string" and secondary ~= "" then secondary else nil
end

local function mainCrystalAttachment(): Attachment?
	local generator = Workspace:FindFirstChild(GeneratorConfig.ModelName)
	local core = generator and generator:FindFirstChild("Core")
	if not (core and core:IsA("BasePart")) then
		return nil
	end
	local attachment = core:FindFirstChild("ShrineBeamTarget")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "ShrineBeamTarget"
		attachment.Parent = core
	end
	return attachment :: Attachment
end

local function setBeam(rig: Rig, active: boolean, widthScale: number)
	if not active then
		if rig.Beam then
			rig.Beam.Enabled = false
		end
		return
	end
	if not rig.Beam then
		local target = mainCrystalAttachment()
		if not (target and rig.Body) then
			return
		end
		local source = Instance.new("Attachment")
		source.Name = "ShrineBeamSource"
		source.Parent = rig.Body
		local look = CoreShrineConfig.Elements[rig.Element]
		local beam = Instance.new("Beam")
		beam.Name = "ShrineBeam"
		beam.Attachment0 = source
		beam.Attachment1 = target
		beam.Color = ColorSequence.new(look.Glow, look.Color)
		beam.LightEmission = 0.6 -- con más brillo el haz se ve blanco
		beam.LightInfluence = 0
		beam.Width0 = 0.4
		beam.Width1 = 0.18
		beam.FaceCamera = true
		beam.Segments = 12
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(1, 0.3),
		})
		beam.Parent = rig.Body
		rig.Beam = beam
	end
	local beam = rig.Beam :: Beam
	beam.Width0 = 0.4 * widthScale
	beam.Width1 = 0.18 * widthScale
	beam.Enabled = true
end

local function apply(rig: Rig, unlocked: { [string]: boolean }, selected: string?, phaseActive: boolean, instant: boolean, secondary: string?)
	local awake = unlocked[rig.Element] == true
	local isSelected = awake and selected == rig.Element
	local isSecondary = awake and not isSelected and secondary == rig.Element
	local look = CoreShrineConfig.Elements[rig.Element]

	if awake ~= rig.Awake then
		for _, part in rig.Tinted do
			local color = part:GetAttribute(if awake then "AwakeColor" else "SleepColor")
			local material = part:GetAttribute(if awake then "AwakeMaterial" else "SleepMaterial")
			if typeof(color) == "Color3" then
				part.Color = color
			end
			if typeof(material) == "string" then
				local ok, enumItem = pcall(function()
					return (Enum.Material :: any)[material]
				end)
				if ok and enumItem then
					part.Material = enumItem
				end
			end
		end
		for _, instance in rig.AwakeOnly do
			(instance :: any).Enabled = awake
		end
		if awake and rig.Awake == false and not instant and rig.Burst then
			rig.Burst:Emit(40)
		end
		rig.Awake = awake
		rig.Settled = false
	end

	-- Haz hasta el cristal: grueso el principal (Q), fino el secundario (R).
	setBeam(rig, isSelected or isSecondary, if isSecondary then 0.55 else 1)

	if rig.Title then
		rig.Title.TextColor3 = if awake then look.Glow else Color3.fromRGB(246, 242, 228)
	end
	if rig.State then
		if not phaseActive then
			rig.State.Text = "Próximamente"
			rig.State.TextColor3 = MUTED
		elseif isSelected then
			local bonus = CoreConfig.Affinity and CoreConfig.Affinity.Bonus or 0
			rig.State.Text = if bonus > 0 then ("★ Activo · +%d %%"):format(math.floor(bonus * 100 + 0.5)) else "★ Activo"
			rig.State.TextColor3 = GOLD
		elseif isSecondary then
			rig.State.Text = "◆ Secundario (R)"
			rig.State.TextColor3 = look.Glow
		elseif awake then
			rig.State.Text = "Despierto"
			rig.State.TextColor3 = look.Glow
		else
			rig.State.Text = "🔒 " .. formatNumber(unlockCost(rig.Order)) .. " 💎"
			rig.State.TextColor3 = MUTED
		end
	end
end

local function refresh(instant: boolean)
	local unlocked, selected, phaseActive, secondary = readState()
	for _, rig in rigs do
		apply(rig, unlocked, selected, phaseActive, instant, secondary)
	end
end

local function search()
	local model = Workspace:FindFirstChild(CoreShrineConfig.ModelName)
	if not (model and model:IsA("Model")) then
		return
	end
	local found = {}
	for _, child in model:GetChildren() do
		if child:IsA("Model") then
			local rig = collect(child)
			if rig then
				table.insert(found, rig)
			end
		end
	end
	-- El modelo puede aparecer antes que todo su contenido: hasta tener los siete
	-- altares completos no se da por encontrado (se reintenta cada segundo).
	if #found < EXPECTED_ALTARS then
		return
	end
	rootModel = model
	rigs = found
	refresh(true)
	-- Los que ya estaban despiertos al entrar aparecen ya flotando (sin animación).
	for _, rig in rigs do
		if rig.Awake then
			rig.Wake = 1
		end
	end
end

local function smoothstep(x: number): number
	return x * x * (3 - 2 * x)
end

local function update(deltaTime: number)
	elapsed += deltaTime
	if not (rootModel and rootModel.Parent) then
		searchTimer -= deltaTime
		if searchTimer <= 0 then
			searchTimer = SEARCH_INTERVAL
			rootModel = nil
			search()
		end
		return
	end

	local camera = Workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}

	for _, rig in rigs do
		local target = if rig.Awake then 1 else 0
		if rig.Wake ~= target then
			local step = deltaTime / Animation.WakeSeconds
			rig.Wake = if target > rig.Wake then math.min(target, rig.Wake + step) else math.max(target, rig.Wake - step)
			rig.Settled = false
		end
		if rig.Wake == 0 and rig.Settled then
			continue -- dormido y en reposo: nada que mover
		end
		local distance = (Vector3.new(rig.X, rig.FloatY, rig.Z) - cameraPosition).Magnitude
		if distance > Animation.MaxDistance and rig.Wake == target then
			continue
		end

		local eased = smoothstep(rig.Wake)
		local bob = math.sin(elapsed * Animation.BobSpeed + rig.Order) * Animation.BobHeight * eased
		local y = rig.RestY + (rig.FloatY - rig.RestY) * eased + bob
		rig.Spin += deltaTime * Animation.SpinSpeed * eased
		local center = CFrame.new(rig.X, y, rig.Z)
		local spun = center * CFrame.Angles(0, rig.Spin, 0)
		for index, part in rig.Crystal do
			table.insert(parts, part)
			table.insert(cframes, spun * rig.CrystalOffsets[index])
		end
		local count = #rig.Orbiters
		for index, part in rig.Orbiters do
			local angle = elapsed * Animation.OrbitSpeed + index * math.pi * 2 / count
			local orbit = center
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(ALTAR.OrbitRadius, math.sin(elapsed * 1.3 + index) * 0.35, 0)
				* CFrame.Angles(0, rig.Spin * 2, math.rad(12))
			table.insert(parts, part)
			table.insert(cframes, if eased >= 1 then orbit else rig.OrbiterRest[index]:Lerp(orbit, eased))
		end
		if rig.Wake == 0 then
			rig.Settled = true -- acaba de volver al reposo: esta es la última colocación
		end
	end

	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function CoreShrineController.start()
	player:GetAttributeChangedSignal(Constants.Attributes.UnlockedCores):Connect(function()
		refresh(false)
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.SelectedCore):Connect(function()
		refresh(false)
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.SecondaryCore):Connect(function()
		refresh(false)
	end)
	if RunService:IsStudio() then
		Workspace:GetAttributeChangedSignal(PREVIEW_ATTRIBUTE):Connect(function()
			refresh(false)
		end)
	end
	RunService.Heartbeat:Connect(update)
end

return CoreShrineController
