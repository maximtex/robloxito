-- Entradas de las mazmorras (las construye Server.Util.ForestCave.gate): la gema de encima del
-- arco flota y gira y su aro de luz da vueltas. Lo hace cada cliente (en el servidor las
-- piezas están quietas) y solo con las que tienes cerca (etiquetas DungeonGem y DungeonHalo;
-- con StreamingEnabled entran y salen solas).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DungeonGates = {}

local GEM_TAG = "DungeonGem"
local HALO_TAG = "DungeonHalo"
local NEAR = 400 -- más lejos no se nota el giro

local gems: { [BasePart]: { Position: Vector3, Tilt: CFrame } } = {}
local halos: { [Model]: CFrame } = {}

local function addGem(instance: Instance)
	if instance:IsA("BasePart") and not gems[instance] then
		gems[instance] = { Position = instance.Position, Tilt = instance.CFrame.Rotation }
	end
end

local function addHalo(instance: Instance)
	if instance:IsA("Model") and not halos[instance] then
		halos[instance] = instance:GetPivot()
	end
end

local function step()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local now = os.clock()
	for gem, base in gems do
		if not gem.Parent then
			gems[gem] = nil
		elseif (base.Position - eye).Magnitude < NEAR then
			local bob = Vector3.new(0, math.sin(now * 1.8) * 0.7, 0)
			gem.CFrame = CFrame.new(base.Position + bob) * CFrame.Angles(0, now * 1.4, 0) * base.Tilt
		end
	end
	for halo, base in halos do
		if not halo.Parent then
			halos[halo] = nil
		elseif (base.Position - eye).Magnitude < NEAR then
			halo:PivotTo(base * CFrame.Angles(0, 0, now * 0.9))
		end
	end
end

function DungeonGates.start()
	for _, gem in CollectionService:GetTagged(GEM_TAG) do
		addGem(gem)
	end
	for _, halo in CollectionService:GetTagged(HALO_TAG) do
		addHalo(halo)
	end
	CollectionService:GetInstanceAddedSignal(GEM_TAG):Connect(addGem)
	CollectionService:GetInstanceAddedSignal(HALO_TAG):Connect(addHalo)
	CollectionService:GetInstanceRemovedSignal(GEM_TAG):Connect(function(instance)
		gems[instance :: BasePart] = nil
	end)
	CollectionService:GetInstanceRemovedSignal(HALO_TAG):Connect(function(instance)
		halos[instance :: Model] = nil
	end)
	RunService.RenderStepped:Connect(step)
end

return DungeonGates
