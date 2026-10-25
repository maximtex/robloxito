-- Avisos e interacción del pueblo que abren un panel de la interfaz:
-- Tienda, Premios, ⚡ Mejoras (habilidades y velocidad), Misiones, Máquina de Evolución y
-- Armería.
-- Los puestos y el cofre se abren al pararse en su círculo del suelo (piezas con OpenPanel;
-- su radio en el atributo PadRadius) y se cierran al salir; la Máquina de Evolución, que no
-- tiene círculo, con la tecla E.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PanelManager = require(script.Parent.Parent.UI.PanelManager)

local WorldPromptController = {}

local ALLOWED = {
	Shop = true,
	Rewards = true,
	Quests = true,
	Skills = true,
	Evolution = true,
	Armory = true,
}

local player = Players.LocalPlayer

function WorldPromptController.start()
	-- 1. Al presionar tecla E en el ProximityPrompt
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local panel = prompt:GetAttribute("OpenPanel")
		if typeof(panel) == "string" and ALLOWED[panel] then
			PanelManager.open(panel)
		end
	end)

	-- 2. Detección automática al caminar y pisar el círculo de la tienda
	local currentPadPanel: string? = nil
	local pads: { { Part: BasePart, Panel: string, Radius: number } } = {}

	local function registerPad(inst: Instance)
		if inst:IsA("BasePart") then
			local panel = inst:GetAttribute("OpenPanel")
			if typeof(panel) == "string" and ALLOWED[panel] then
				local radius = inst:GetAttribute("PadRadius")
				table.insert(pads, {
					Part = inst,
					Panel = panel,
					Radius = if typeof(radius) == "number" then radius else 4.2,
				})
			end
		end
	end

	for _, desc in Workspace:GetDescendants() do
		registerPad(desc)
	end
	Workspace.DescendantAdded:Connect(registerPad)

	-- Chequeo continuo ligero (cada 0.1s)
	local lastCheck = 0
	RunService.Heartbeat:Connect(function(dt: number)
		lastCheck += dt
		if lastCheck < 0.1 then
			return
		end
		lastCheck = 0

		local char = player.Character
		if not char then
			return
		end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end

		local rootPos = root.Position
		local activePanel: string? = nil

		for i = #pads, 1, -1 do
			local padData = pads[i]
			if not padData.Part or not padData.Part.Parent then
				table.remove(pads, i)
			else
				local diff = rootPos - padData.Part.Position
				local horizDist = math.sqrt(diff.X * diff.X + diff.Z * diff.Z)
				if horizDist <= padData.Radius and math.abs(diff.Y) <= 4.5 then
					activePanel = padData.Panel
					break
				end
			end
		end

		if activePanel then
			if currentPadPanel ~= activePanel then
				currentPadPanel = activePanel
				PanelManager.open(activePanel)
			end
		else
			if currentPadPanel then
				if PanelManager.isOpen(currentPadPanel) then
					PanelManager.close(currentPadPanel)
				end
				currentPadPanel = nil
			end
		end
	end)
end

return WorldPromptController
