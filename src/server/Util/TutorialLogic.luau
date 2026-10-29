-- Lógica pura del tutorial (sin APIs de Roblox), para probarla fuera de Studio.
-- Estado guardado: { Status = "Active" | "Completed" | "Skipped", Step = pasos hechos }.
-- - Los pasos avanzan solo con datos del servidor (ctx y estadísticas).
-- - Lo hecho queda hecho (Step nunca baja), aunque luego se gaste o se desequipe.
-- - Si se cumple un paso posterior, los anteriores cuentan como hechos.
-- - Completado u omitido es definitivo: no vuelve a mostrarse.
-- - Veteranos (TutorialConfig.Veteran): se completa solo, sin premios.
-- - Premios: update devuelve los pasos recién cumplidos (TutorialService da su Reward).
-- - Después: nextGoal dice el siguiente objetivo (TutorialConfig.NextGoals).

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
		return ctx.UnlockedZones ~= nil and ctx.UnlockedZones[goal.Zone] == true
	end
	return false
end
TutorialLogic.isMet = isMet

-- ¿Ya pasó de lo que enseña el tutorial? (TutorialConfig.Veteran)
function TutorialLogic.isVeteran(ctx: any, stats: any): boolean
	for _, rule in TutorialConfig.Veteran or {} do
		if isMet(rule, ctx, stats) then
			return true
		end
	end
	return false
end

-- Avanza con el estado actual del servidor. Devuelve true si algo cambió y los pasos que se
-- acaban de cumplir, en orden (sus premios; ninguno si se completa por ser veterano).
function TutorialLogic.update(data: TutorialData, ctx: any, stats: any): (boolean, { number })
	if data.Status ~= "Active" then
		return false, {}
	end
	local steps = TutorialConfig.Steps
	if TutorialLogic.isVeteran(ctx, stats) then
		data.Status = "Completed"
		data.Step = #steps
		return true, {}
	end
	local reached = data.Step
	for index = #steps, reached + 1, -1 do
		if isMet(steps[index], ctx, stats) then
			reached = index -- este y todos los anteriores
			break
		end
	end
	local done = {}
	for index = data.Step + 1, reached do
		table.insert(done, index)
	end
	local changed = reached ~= data.Step
	data.Step = reached
	if data.Step >= #steps then
		data.Status = "Completed"
		changed = true
	end
	return changed, done
end

-- Premio de un paso (o nil): { Money = número, Potions = { [id] = cantidad } }
function TutorialLogic.reward(index: number): any
	local step = TutorialConfig.Steps[index]
	return step and step.Reward
end

-- Siguiente objetivo tras el tutorial (completado u omitido): el Id del que sigue al último
-- cumplido de TutorialConfig.NextGoals (con el Valle abierto, el Guardián cuenta como hecho),
-- o nil (tutorial activo o todos cumplidos).
function TutorialLogic.nextGoal(data: TutorialData, ctx: any, stats: any): string?
	if data.Status == "Active" then
		return nil
	end
	local goals = TutorialConfig.NextGoals or {}
	local reached = 0
	for index = #goals, 1, -1 do
		if isMet(goals[index], ctx, stats) then
			reached = index
			break
		end
	end
	local goal = goals[reached + 1]
	return if goal then goal.Id else nil
end

-- ¿Se puede omitir ya? (activo y con los MinSkipStep primeros pasos hechos)
function TutorialLogic.canSkip(data: TutorialData): boolean
	return data.Status == "Active" and data.Step >= (TutorialConfig.MinSkipStep or 0)
end

-- Omitir: solo si sigue activo y ya se hicieron los primeros pasos. Devuelve true si cambió.
function TutorialLogic.skip(data: TutorialData): boolean
	if not TutorialLogic.canSkip(data) then
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
