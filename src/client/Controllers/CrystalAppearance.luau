-- Evolución visual del Cristal del Renacimiento según el nivel de mejora del jugador.
--
-- Es solo visual y local: cada cliente pinta el cristal compartido según SU nivel, que
-- lee del atributo que escribe el servidor. No toca la economía.
--
-- No mueve piezas (eso es exclusivo de GeneratorAnimator): solo cambia colores,
-- transparencias y emisores, con transiciones suaves. Los detalles de etapa ya existen
-- en el modelo (ocultos), así que no se crea ni se duplica nada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local Constants = require(Shared.Constants)
local GeneratorAnimator = require(script.Parent.GeneratorAnimator)

local Evolution = GeneratorConfig.Evolution
local LEVEL_ATTRIBUTE = Constants.Attributes.UpgradeLevelPrefix .. Evolution.UpgradeId

type Visuals = {
	Model: Model,
	Tinted: { Instance },
	Groups: { [string]: Instance },
}

local CrystalAppearance = {}

local player = Players.LocalPlayer
local visuals: Visuals? = nil
local appliedStage = 1
local levelKnown = false
local activeTweens: { [Instance]: Tween } = {}
local recollectQueued = false

local function readLevel(): number?
	local value = player:GetAttribute(LEVEL_ATTRIBUTE)
	return if typeof(value) == "number" then value else nil
end

local function collect(model: Model): Visuals
	local tinted = {}
	for _, descendant in model:GetDescendants() do
		if descendant:GetAttribute("Tint") ~= nil then
			table.insert(tinted, descendant)
		end
	end
	local groups = {}
	local details = model:FindFirstChild("StageDetails")
	if details then
		for _, group in details:GetChildren() do
			groups[group.Name] = group
		end
	end
	return { Model = model, Tinted = tinted, Groups = groups }
end

local function play(instance: Instance, properties: { [string]: any }, instant: boolean)
	local previous = activeTweens[instance]
	if previous then
		previous:Cancel()
		activeTweens[instance] = nil
	end
	if instant then
		for key, value in properties do
			(instance :: any)[key] = value
		end
		return
	end
	local tween = TweenService:Create(instance, TweenInfo.new(Evolution.TransitionSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), properties)
	activeTweens[instance] = tween
	tween.Completed:Once(function()
		if activeTweens[instance] == tween then
			activeTweens[instance] = nil
		end
	end)
	tween:Play()
end

local function apply(stageIndex: number, instant: boolean)
	local current = visuals
	if not current then
		return
	end
	local stage = Evolution.Stages[stageIndex]

	-- Una sola animación por instancia con todas sus propiedades destino.
	local targets: { [Instance]: { [string]: any } } = {}
	local function target(instance: Instance)
		local properties = targets[instance]
		if not properties then
			properties = {}
			targets[instance] = properties
		end
		return properties
	end

	for _, instance in current.Tinted do
		if not instance.Parent then
			continue
		end
		local tint = instance:GetAttribute("Tint")
		local color = if typeof(tint) == "string" then (stage :: any)[tint] else nil
		if typeof(color) == "Color3" and (instance:IsA("BasePart") or instance:IsA("Light")) then
			target(instance).Color = color
		elseif instance:IsA("ParticleEmitter") and tint == "Particles" then
			-- Las secuencias de color no se pueden interpolar con Tween; se cambian directamente.
			instance.Color = ColorSequence.new(stage.Particles[1], stage.Particles[2])
			if instance:GetAttribute("StageRate") then
				instance.Rate = stage.ParticleRate
			end
		end
	end

	local visibleGroups: { [string]: boolean } = {}
	for _, name in stage.Details do
		visibleGroups[name] = true
	end
	for name, group in current.Groups do
		local visible = visibleGroups[name] == true
		for _, descendant in group:GetDescendants() do
			if descendant:IsA("BasePart") then
				local shown = descendant:GetAttribute("VisibleTransparency")
				target(descendant).Transparency = if visible then (if typeof(shown) == "number" then shown else 0) else 1
			elseif descendant:IsA("ParticleEmitter") then
				descendant.Enabled = visible
			end
		end
	end

	for instance, properties in targets do
		play(instance, properties, instant)
	end
	GeneratorAnimator.setIntensity(stage.Intensity, instant)
end

local function notifyEvolution(stageIndex: number)
	local stage = Evolution.Stages[stageIndex]
	-- SetCore puede fallar si la interfaz de Roblox aún no está lista; no es crítico.
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = GeneratorConfig.DisplayName,
			Text = "Ha evolucionado: " .. stage.Name,
			Duration = 5,
		})
	end)
end

local function bind(model: Model)
	for _, tween in activeTweens do
		tween:Cancel()
	end
	table.clear(activeTweens)
	visuals = collect(model)
	apply(appliedStage, true)

	-- Si llegan piezas marcadas después (replicación tardía), se vuelve a recopilar.
	model.DescendantAdded:Connect(function(descendant)
		if recollectQueued or visuals == nil or visuals.Model ~= model then
			return
		end
		if descendant:GetAttribute("Tint") ~= nil or descendant:IsA("ParticleEmitter") or descendant:IsA("BasePart") then
			recollectQueued = true
			task.delay(0.5, function()
				recollectQueued = false
				if visuals and visuals.Model == model then
					visuals = collect(model)
					apply(appliedStage, true)
				end
			end)
		end
	end)
end

local function tryBind()
	local model = Workspace:FindFirstChild(GeneratorConfig.ModelName)
	if model and model:IsA("Model") and (visuals == nil or visuals.Model ~= model) then
		bind(model)
	end
end

local function onLevelChanged()
	local level = readLevel()
	if level == nil then
		return
	end
	local stageIndex = GeneratorConfig.getStageIndex(level)

	if not levelKnown then
		-- Primer valor conocido: aplicar sin animación ni aviso (inicialización).
		levelKnown = true
		appliedStage = stageIndex
		apply(stageIndex, true)
		return
	end
	if stageIndex == appliedStage then
		return
	end

	local evolved = stageIndex > appliedStage
	appliedStage = stageIndex
	apply(stageIndex, false)
	if evolved then
		GeneratorAnimator.playPurchaseBurst()
		notifyEvolution(stageIndex)
	end
end

function CrystalAppearance.start()
	local level = readLevel()
	if level ~= nil then
		levelKnown = true
		appliedStage = GeneratorConfig.getStageIndex(level)
	end

	Workspace.ChildAdded:Connect(function(child)
		if child.Name == GeneratorConfig.ModelName then
			task.defer(tryBind)
		end
	end)
	tryBind()

	player:GetAttributeChangedSignal(LEVEL_ATTRIBUTE):Connect(onLevelChanged)
end

return CrystalAppearance
