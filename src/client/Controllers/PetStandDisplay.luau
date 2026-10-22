-- Jardín de mascotas en el cliente: sobre cada pedestal (pieza PetDisplay con el atributo
-- ShopPet, la construye EggStandService) se dibuja la mascota que vende, que flota y gira
-- despacio. Solo visual: una conexión (Heartbeat), en pausa cuando la cámara está lejos.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PetModelBuilder = require(script.Parent.Parent.Pets.PetModelBuilder)

local PetStandDisplay = {}

local FOLDER_NAME = "PetGarden"
local SEARCH_INTERVAL = 2
local MAX_DISTANCE = 110
local PET_SCALE = 1.7
local BOB_HEIGHT = 0.25
local BOB_SPEED = 1.6
local SPIN_SPEED = 0.6 -- radianes por segundo

type Display = { Anchor: BasePart, Model: Model, Root: BasePart, Phase: number }

local displays: { Display } = {}
local folder: Instance? = nil
local searchTimer = 0
local elapsed = 0

local function attach(anchor: Instance)
	if not anchor:IsA("BasePart") or anchor.Name ~= "PetDisplay" then
		return
	end
	local petId = anchor:GetAttribute("ShopPet")
	if typeof(petId) ~= "string" then
		return
	end
	for _, display in displays do
		if display.Anchor == anchor then
			return
		end
	end
	local model, root = PetModelBuilder.build(petId)
	if not (model and root) then
		return
	end
	model:ScaleTo(PET_SCALE)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	model:PivotTo(anchor.CFrame)
	model.Parent = anchor
	table.insert(displays, { Anchor = anchor, Model = model, Root = root, Phase = #displays * 1.7 })
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
				table.clear(displays)
				for _, descendant in found:GetDescendants() do
					attach(descendant)
				end
				found.DescendantAdded:Connect(attach) -- llegan por streaming poco a poco
			end
		end
		return
	end

	local camera = Workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	for index = #displays, 1, -1 do
		local display = displays[index]
		if not display.Anchor.Parent or not display.Model.Parent then
			table.remove(displays, index)
		elseif (display.Anchor.Position - cameraPosition).Magnitude <= MAX_DISTANCE then
			local t = elapsed + display.Phase
			display.Root.CFrame = display.Anchor.CFrame * CFrame.new(0, math.sin(t * BOB_SPEED) * BOB_HEIGHT, 0) * CFrame.Angles(0, t * SPIN_SPEED, 0)
		end
	end
end

function PetStandDisplay.start()
	RunService.Heartbeat:Connect(update)
end

return PetStandDisplay
