-- Lógica pura del tutorial (sin APIs de Roblox), para probarla fuera de Studio.
-- Estado guardado: { Status = "Active" | "Completed" | "Skipped", Step = pasos hechos }.
-- - Los pasos avanzan solo con datos del servidor (ctx y estadísticas).
-- - Lo hecho queda hecho (Step nunca baja), aunque luego se gaste o se desequipe.
-- - Si se cumple un paso posterior, los anteriores cuentan como hechos.
-- - Completado u omitido es definitivo: no vuelve a mostrarse.

local TutorialLogic = {}

local TutorialConfig: any

function TutorialLogic.init(config: any)
	TutorialConfig = config
end

export type TutorialData = { Status: string, Step: number }

local STATUSES = { Active = true, Completed = true, Skipped = true }

function TutorialLogic.empty(): TutorialData
	return { Status = "Active", Step = 0 }
end

function TutorialLogic.stepCount(): number
	return #TutorialConfig.Steps
end

-- Guardado (o ausente en partidas antiguas) -> estado válido.
function TutorialLogic.sanitize(raw: any): TutorialData
	local data = TutorialLogic.empty()
	if type(raw) ~= "table" then
		return data
	end
	if type(raw.Status) == "string" and STATUSES[raw.Status] then
		data.Status = raw.Status
	end
	local step = raw.Step
	if type(step) == "number" and step == step then
		data.Step = math.clamp(math.floor(step), 0, #TutorialConfig.Steps)
	end
	if data.Status == "Active" and data.Step >= #TutorialConfig.Steps then
		data.Status = "Completed"
	end
	return data
end

function TutorialLogic.serialize(data: TutorialData): any
	return { Status = data.Status, Step = data.Step }
end

local function isMet(step: any, ctx: any, stats: any): boolean
	local goal = step.Goal
	if goal.Source == "Stat" then
		return (stats[goal.Key] or 0) >= step.Target
	elseif goal.Source == "State" then
		return (ctx[goal.Key] or 0) >= step.Target
	elseif goal.Source == "Zone" then
		return ctx.UnlockedZones[goal.Zone] == true
	end
	return false
end

-- Avanza con el estado actual del servidor. Devuelve true si algo cambió.
function TutorialLogic.update(data: TutorialData, ctx: any, stats: any): boolean
	if data.Status ~= "Active" then
		return false
	end
	local steps = TutorialConfig.Steps
	local reached = data.Step
	for index = #steps, reached + 1, -1 do
		if isMet(steps[index], ctx, stats) then
			reached = index -- este y todos los anteriores
			break
		end
	end
	local changed = reached ~= data.Step
	data.Step = reached
	if data.Step >= #steps then
		data.Status = "Completed"
		changed = true
	end
	return changed
end

-- Omitir: solo si sigue activo. Devuelve true si cambió.
function TutorialLogic.skip(data: TutorialData): boolean
	if data.Status ~= "Active" then
		return false
	end
	data.Status = "Skipped"
	return true
end

-- En Roblox se inicializa solo; las pruebas llaman a init con su propia configuración.
if typeof(script) == "Instance" then
	TutorialLogic.init(require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.TutorialConfig))
end

return TutorialLogic
