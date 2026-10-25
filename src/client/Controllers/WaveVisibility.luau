-- Oleadas privadas en el cliente (solo presentación; el servidor ya decide quién golpea a
-- quién, EnemyService.canInteract):
-- - Cada enemigo de una partida lleva el atributo WaveRun (número de la partida) en su
--   modelo y en sus efectos (Workspace.Enemies.Effects); el jugador que juega una partida
--   lo lleva también. Aquí se ocultan, solo para este jugador, los que no son de su "mundo":
--   mientras juegas, los enemigos normales y los de otras partidas; si no juegas, los de
--   todas las partidas.
-- - Ocultar = piezas transparentes (LocalTransparencyModifier), sin barra de vida, contorno,
--   partículas, luces ni clic. Todo es local: no cambia nada en el servidor ni para otros.
-- - isVisible lo usan CombatController (apuntar, barra del jefe), EnemyAnimator y
--   AbilityController para no tener en cuenta lo que no se ve.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local WaveVisibility = {}

local player = Players.LocalPlayer
local RUN_ATTRIBUTE = Constants.Attributes.WaveRun
local HIDDEN_DISTANCE = 0.01 -- BillboardGui.MaxDistance que no se ve (0 sería "sin límite")

local function runOf(instance: Instance): number?
	local value = instance:GetAttribute(RUN_ATTRIBUTE)
	return if type(value) == "number" then value else nil
end

-- ¿Este enemigo (o efecto) es del mismo "mundo" que el jugador?
function WaveVisibility.isVisible(instance: Instance): boolean
	return runOf(instance) == runOf(player)
end

-- Valores originales de lo que se oculta (para devolverlos al volver a verse).
local saved: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
local hiddenUnits: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local INVISIBLE = NumberSequence.new(1)

local function apply(instance: Instance, hide: boolean)
	if instance:IsA("BasePart") then
		instance.LocalTransparencyModifier = if hide then 1 else 0
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		instance.LocalTransparencyModifier = if hide then 1 else 0
	elseif instance:IsA("BillboardGui") then
		if hide then
			if saved[instance] == nil then
				saved[instance] = instance.MaxDistance
			end
			instance.MaxDistance = HIDDEN_DISTANCE
		elseif saved[instance] ~= nil then
			instance.MaxDistance = saved[instance]
			saved[instance] = nil
		end
	elseif instance:IsA("Highlight") then
		if hide then
			if saved[instance] == nil then
				saved[instance] = instance.Enabled
			end
			instance.Enabled = false
		elseif saved[instance] ~= nil then
			instance.Enabled = saved[instance]
			saved[instance] = nil
		end
	elseif instance:IsA("ParticleEmitter") then
		if hide then
			if saved[instance] == nil then
				saved[instance] = instance.Transparency
			end
			instance.Transparency = INVISIBLE
		elseif saved[instance] ~= nil then
			instance.Transparency = saved[instance]
			saved[instance] = nil
		end
	elseif instance:IsA("Light") then
		if hide then
			if saved[instance] == nil then
				saved[instance] = instance.Brightness
			end
			instance.Brightness = 0
		elseif saved[instance] ~= nil then
			instance.Brightness = saved[instance]
			saved[instance] = nil
		end
	elseif instance:IsA("ClickDetector") then
		if hide then
			if saved[instance] == nil then
				saved[instance] = instance.MaxActivationDistance
			end
			instance.MaxActivationDistance = 0
		elseif saved[instance] ~= nil then
			instance.MaxActivationDistance = saved[instance]
			saved[instance] = nil
		end
	end
end

-- Un enemigo (Workspace.Enemies.<Zona>.<Modelo>) o un efecto (Workspace.Enemies.Effects.<Pieza>)
local function refreshUnit(unit: Instance)
	local hide = not WaveVisibility.isVisible(unit)
	if (hiddenUnits[unit] == true) == hide then
		return
	end
	hiddenUnits[unit] = if hide then true else nil
	apply(unit, hide)
	for _, descendant in unit:GetDescendants() do
		apply(descendant, hide)
	end
end

local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function watchUnit(unit: Instance)
	if watched[unit] then
		refreshUnit(unit)
		return
	end
	watched[unit] = true
	-- Al reutilizarse en otra partida cambia su WaveRun
	unit:GetAttributeChangedSignal(RUN_ATTRIBUTE):Connect(function()
		refreshUnit(unit)
	end)
	-- Piezas que se añaden después (efectos, empujones…) con el mismo estado que el resto
	unit.DescendantAdded:Connect(function(descendant)
		if hiddenUnits[unit] then
			apply(descendant, true)
		end
	end)
	refreshUnit(unit)
end

local function watchGroup(group: Instance)
	group.ChildAdded:Connect(watchUnit)
	for _, unit in group:GetChildren() do
		watchUnit(unit)
	end
end

local function refreshAll(enemies: Instance)
	for _, group in enemies:GetChildren() do
		for _, unit in group:GetChildren() do
			refreshUnit(unit)
		end
	end
end

function WaveVisibility.start()
	task.spawn(function()
		local enemies = Workspace:WaitForChild("Enemies")
		enemies.ChildAdded:Connect(watchGroup)
		for _, group in enemies:GetChildren() do
			watchGroup(group)
		end
		player:GetAttributeChangedSignal(RUN_ATTRIBUTE):Connect(function()
			refreshAll(enemies)
		end)
		refreshAll(enemies)
	end)
end

return WaveVisibility
