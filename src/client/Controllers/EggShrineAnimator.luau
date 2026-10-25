-- Santuarios de huevos en el cliente: el huevo (modelo EggBody que construye
-- EggStandService) flota y gira despacio sobre su nido y el anillo de luz del pedestal
-- palpita. Solo visual; una conexión (Heartbeat) y un BulkMoveTo por fotograma, en pausa
-- cuando la cámara está lejos.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EggShrineAnimator = {}

local FOLDER_NAME = "EggShrines"
local SEARCH_INTERVAL = 2
local MAX_DISTANCE = 110
local BOB_HEIGHT = 0.22
local BOB_SPEED = 1.6
local SPIN_SPEED = 0.45 -- radianes por segundo
local RING_TRANSPARENCY = 0.35
local RING_PULSE = 0.2

type Rig = {
	Rest: CFrame,
	Parts: { BasePart },
	Offsets: { CFrame },
	Ring: BasePart?,
	Phase: number,
}

local rigs: { Rig } = {}
local folder: Instance? = nil
local searchTimer = 0
local elapsed = 0
-- Los santuarios llegan por streaming poco a poco: al cambiar algo dentro de la carpeta se
-- vuelven a recoger (con una pequeña espera para agrupar los cambios).
local dirtyTimer: number? = nil
local RECOLLECT_DELAY = 0.5

local function collect(shrines: Instance)
	table.clear(rigs)
	for index, shrine in shrines:GetChildren() do
		local body = shrine:FindFirstChild("EggBody")
		if body and body:IsA("Model") then
			local rest = body:GetPivot()
			local rig: Rig = { Rest = rest, Parts = {}, Offsets = {}, Ring = nil, Phase = index * 1.7 }
			for _, part in body:GetDescendants() do
				if part:IsA("BasePart") then
					table.insert(rig.Parts, part)
					table.insert(rig.Offsets, rest:ToObjectSpace(part.CFrame))
				end
			end
			local ring = shrine:FindFirstChild("GlowRing")
			if ring and ring:IsA("BasePart") then
				rig.Ring = ring
			end
			if #rig.Parts > 0 then
				table.insert(rigs, rig)
			end
		end
	end
end

local function update(deltaTime: number)
	elapsed += deltaTime
	if not folder or folder.Parent ~= Workspace then
		searchTimer -= deltaTime
		if searchTimer <= 0 then
			searchTimer = SEARCH_INTERVAL
			local found = Workspace:FindFirstChild(FOLDER_NAME)
			if found then
				folder = found
				collect(found)
				found.DescendantAdded:Connect(function()
					dirtyTimer = RECOLLECT_DELAY
				end)
				found.DescendantRemoving:Connect(function()
					dirtyTimer = RECOLLECT_DELAY
				end)
			end
		end
		return
	end
	if dirtyTimer then
		dirtyTimer -= deltaTime
		if dirtyTimer <= 0 then
			dirtyTimer = nil
			-- Antes de recoger, devolver los huevos a su sitio (las posiciones de reposo
			-- se leen de las piezas).
			for _, rig in rigs do
				for index, part in rig.Parts do
					if part.Parent then
						part.CFrame = rig.Rest * rig.Offsets[index]
					end
				end
			end
			collect(folder)
		end
	end

	local camera = Workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	for _, rig in rigs do
		if (rig.Rest.Position - cameraPosition).Magnitude > MAX_DISTANCE then
			continue
		end
		local t = elapsed + rig.Phase
		local pose = rig.Rest * CFrame.new(0, math.sin(t * BOB_SPEED) * BOB_HEIGHT, 0) * CFrame.Angles(0, t * SPIN_SPEED, 0)
		for index, part in rig.Parts do
			table.insert(parts, part)
			table.insert(cframes, pose * rig.Offsets[index])
		end
		if rig.Ring then
			rig.Ring.Transparency = RING_TRANSPARENCY + math.sin(t * 2.2) * RING_PULSE
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function EggShrineAnimator.start()
	RunService.Heartbeat:Connect(update)
end

return EggShrineAnimator
