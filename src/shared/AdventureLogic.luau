-- Lógica pura de las aventuras (personajes, misiones, amuletos y bendiciones), sin APIs
-- de Roblox, para poder probarla fuera de Studio. La usan AdventureService (servidor),
-- SaveService (sanear al cargar), los servicios que aplican las pasivas (producción,
-- daño, botín) y el cliente (textos y estado).
--
-- Garantías:
-- - El progreso solo sale de eventos que crea el servidor (record). Nada viene del cliente.
-- - Las misiones solo cuentan desde que se aceptan.
-- - Entregar marca el paso y concede bendición/amuleto en el mismo paso, sin pausas: dos
--   solicitudes seguidas no pueden cobrar dos veces.
-- - Las bendiciones activas caducan por hora (os.time), también sin jugar.

local AdventureConfig = require(script.Parent.Config.AdventureConfig)

local AdventureLogic = {}

export type NpcProgress = {
	Step: number, -- paso actual (1..#Steps); #Steps + 1 = historia terminada
	Accepted: boolean,
	Progress: number, -- Kill y Talk
	Found: { [string]: boolean }, -- Collect
}

export type AdventureData = {
	Npcs: { [string]: NpcProgress },
	Amulets: { [string]: boolean },
	Equipped: { string }, -- "" = ranura vacía
	Blessings: { [string]: number }, -- guardadas sin usar
	Active: { [string]: number }, -- bendición -> os.time() en que termina
}

local MAX_ID = 64
local MAX_ENTRIES = 32
local MAX_PROGRESS = 1e6

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function cleanId(value: any): string?
	if type(value) == "string" and #value > 0 and #value <= MAX_ID then
		return value
	end
	return nil
end

local function cleanInteger(value: any, minValue: number, maxValue: number): number
	if not isFiniteNumber(value) then
		return minValue
	end
	return math.clamp(math.floor(value), minValue, maxValue)
end

-- Configuración ------------------------------------------------------------------------------

local function ordered(map: { [string]: any }): { string }
	local ids = {}
	for id in map do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local oa, ob = map[a].Order or 0, map[b].Order or 0
		if oa ~= ob then
			return oa < ob
		end
		return a < b
	end)
	return ids
end

local NPC_ORDER = ordered(AdventureConfig.Npcs)
local AMULET_ORDER = ordered(AdventureConfig.Amulets)
local BLESSING_ORDER = ordered(AdventureConfig.Blessings)

-- Objeto perdido -> { Npc, Step } (cada objeto pertenece a un único paso).
local ITEM_OWNER: { [string]: { Npc: string, Step: number } } = {}
for _, npcId in NPC_ORDER do
	for stepIndex, step in AdventureConfig.Npcs[npcId].Steps do
		if step.Goal.Type == "Collect" then
			for _, itemId in step.Goal.Items do
				ITEM_OWNER[itemId] = { Npc = npcId, Step = stepIndex }
			end
		end
	end
end

function AdventureLogic.npcOrder(): { string }
	return table.clone(NPC_ORDER)
end

function AdventureLogic.amuletOrder(): { string }
	return table.clone(AMULET_ORDER)
end

function AdventureLogic.blessingOrder(): { string }
	return table.clone(BLESSING_ORDER)
end

function AdventureLogic.stepOf(npcId: string, stepIndex: number): any
	local npc = AdventureConfig.Npcs[npcId]
	return npc and npc.Steps[stepIndex]
end

-- Cuánto pide un paso (objetos, derrotas o 1 conversación).
function AdventureLogic.target(step: any): number
	local goal = step.Goal
	if goal.Type == "Collect" then
		return #goal.Items
	elseif goal.Type == "Kill" then
		return goal.Target
	end
	return 1
end

-- Comprobación de la configuración (avisos en el servidor y en las pruebas).
function AdventureLogic.validateConfig(): (boolean, { string })
	local problems = {}
	local seenItems = {}
	for _, npcId in NPC_ORDER do
		local npc = AdventureConfig.Npcs[npcId]
		if #npc.Steps == 0 then
			table.insert(problems, npcId .. " no tiene misiones")
		end
		if npc.Amulet and not AdventureConfig.Amulets[npc.Amulet] then
			table.insert(problems, npcId .. ": amuleto desconocido " .. tostring(npc.Amulet))
		end
		for index, step in npc.Steps do
			local name = ("%s paso %d"):format(npcId, index)
			local goal = step.Goal
			if goal.Type == "Collect" then
				for _, itemId in goal.Items do
					if not AdventureConfig.Items[itemId] then
						table.insert(problems, name .. ": objeto desconocido " .. itemId)
					elseif seenItems[itemId] then
						table.insert(problems, name .. ": objeto repetido " .. itemId)
					end
					seenItems[itemId] = true
				end
			elseif goal.Type == "Kill" then
				if type(goal.Target) ~= "number" or goal.Target < 1 or #goal.Enemies == 0 then
					table.insert(problems, name .. ": objetivo de derrotas no válido")
				end
			elseif goal.Type == "Talk" then
				if not AdventureConfig.Npcs[goal.Npc] or goal.Npc == npcId then
					table.insert(problems, name .. ": personaje de entrega no válido")
				end
				if type(step.Delivery) ~= "string" then
					table.insert(problems, name .. ": falta el texto de la entrega")
				end
			else
				table.insert(problems, name .. ": tipo de objetivo desconocido " .. tostring(goal.Type))
			end
			local reward = step.Reward
			if reward.Blessing and not AdventureConfig.Blessings[reward.Blessing] then
				table.insert(problems, name .. ": bendición desconocida " .. tostring(reward.Blessing))
			end
			if reward.Amulet and not AdventureConfig.Amulets[reward.Amulet] then
				table.insert(problems, name .. ": amuleto desconocido " .. tostring(reward.Amulet))
			end
			local money = reward.Money
			if not money or money.Min < 0 or money.Max < money.Min then
				table.insert(problems, name .. ": dinero no válido")
			end
			for _, field in { "Title", "Objective", "Offer", "Active", "Ready" } do
				if type(step[field]) ~= "string" or step[field] == "" then
					table.insert(problems, name .. ": falta " .. field)
				end
			end
		end
	end
	for itemId, item in AdventureConfig.Items do
		if not AdventureConfig.ItemKinds[item.Kind] then
			table.insert(problems, itemId .. ": tipo de objeto desconocido")
		end
		if not seenItems[itemId] then
			table.insert(problems, itemId .. ": ninguna misión lo usa")
		end
	end
	for blessingId, blessing in AdventureConfig.Blessings do
		if not isFiniteNumber(blessing.Duration) or blessing.Duration <= 0 then
			table.insert(problems, blessingId .. ": duración no válida")
		end
	end
	return #problems == 0, problems
end

-- Datos ---------------------------------------------------------------------------------------

local function emptyNpc(): NpcProgress
	return { Step = 1, Accepted = false, Progress = 0, Found = {} }
end

function AdventureLogic.empty(): AdventureData
	local equipped = {}
	for _ = 1, AdventureConfig.MaxSlots do
		table.insert(equipped, "")
	end
	return { Npcs = {}, Amulets = {}, Equipped = equipped, Blessings = {}, Active = {} }
end

-- Datos guardados (o ausentes en partidas antiguas) -> estructura válida. Los personajes,
-- amuletos y bendiciones desconocidos se conservan (no se pierde nada al retirar uno).
function AdventureLogic.sanitize(raw: any): AdventureData
	local data = AdventureLogic.empty()
	if type(raw) ~= "table" then
		return data
	end
	if type(raw.Npcs) == "table" then
		local count = 0
		for npcId, entry in raw.Npcs do
			local id = cleanId(npcId)
			if id and type(entry) == "table" and count < MAX_ENTRIES then
				count += 1
				local npc = AdventureConfig.Npcs[id]
				local maxStep = if npc then #npc.Steps + 1 else 100
				local clean = emptyNpc()
				clean.Step = cleanInteger(entry.Step, 1, maxStep)
				clean.Accepted = entry.Accepted == true and clean.Step < maxStep
				clean.Progress = cleanInteger(entry.Progress, 0, MAX_PROGRESS)
				if type(entry.Found) == "table" then
					local found = 0
					for key, value in entry.Found do
						local itemId = if type(key) == "string" and value == true then cleanId(key) elseif type(key) == "number" then cleanId(value) else nil
						if itemId and found < MAX_ENTRIES then
							clean.Found[itemId] = true
							found += 1
						end
					end
				end
				if not clean.Accepted then
					clean.Progress = 0
					clean.Found = {}
				end
				data.Npcs[id] = clean
			end
		end
	end
	if type(raw.Amulets) == "table" then
		local count = 0
		for key, value in raw.Amulets do
			local id = if type(key) == "string" and value == true then cleanId(key) elseif type(key) == "number" then cleanId(value) else nil
			if id and count < MAX_ENTRIES then
				data.Amulets[id] = true
				count += 1
			end
		end
	end
	if type(raw.Equipped) == "table" then
		for slot = 1, AdventureConfig.MaxSlots do
			local id = cleanId(raw.Equipped[slot])
			-- Solo amuletos que se tienen y sin repetir.
			if id and data.Amulets[id] and not table.find(data.Equipped, id) then
				data.Equipped[slot] = id
			end
		end
	end
	for _, field in { "Blessings", "Active" } do
		local source = raw[field]
		if type(source) == "table" then
			local count = 0
			for key, value in source do
				local id = cleanId(key)
				if id and isFiniteNumber(value) and value > 0 and count < MAX_ENTRIES then
					data[field][id] = if field == "Blessings" then cleanInteger(value, 0, AdventureConfig.MaxBlessings) else math.floor(value)
					count += 1
				end
			end
		end
	end
	-- La segunda ranura solo vale con todas las historias terminadas.
	for slot = AdventureLogic.slots(data) + 1, AdventureConfig.MaxSlots do
		data.Equipped[slot] = ""
	end
	return data
end

-- Copia para guardar (tablas nuevas: lo guardado no cambia si el perfil sigue cambiando).
function AdventureLogic.serialize(data: AdventureData): any
	local npcs = {}
	for npcId, entry in data.Npcs do
		npcs[npcId] = { Step = entry.Step, Accepted = entry.Accepted, Progress = entry.Progress, Found = table.clone(entry.Found) }
	end
	return {
		Npcs = npcs,
		Amulets = table.clone(data.Amulets),
		Equipped = table.clone(data.Equipped),
		Blessings = table.clone(data.Blessings),
		Active = table.clone(data.Active),
	}
end

-- Datos de aventura de un perfil del servidor (o nil si no tiene).
function AdventureLogic.ofProfile(profile: any): AdventureData?
	local petData = if type(profile) == "table" then profile.PetData else nil
	local data = if type(petData) == "table" then petData.Adventure else nil
	return if type(data) == "table" then data else nil
end

local function entryOf(data: AdventureData, npcId: string): NpcProgress
	local entry = data.Npcs[npcId]
	if not entry then
		entry = emptyNpc()
		data.Npcs[npcId] = entry
	end
	return entry
end

-- Estado de un personaje ----------------------------------------------------------------------

local function progressOf(entry: NpcProgress, step: any): number
	if step.Goal.Type == "Collect" then
		local count = 0
		for _, itemId in step.Goal.Items do
			if entry.Found[itemId] then
				count += 1
			end
		end
		return count
	end
	return math.min(entry.Progress, AdventureLogic.target(step))
end

-- { Status = "Offer" | "Active" | "Ready" | "Done", Step, Steps, Progress, Target }
function AdventureLogic.state(data: AdventureData?, npcId: string): any
	local npc = AdventureConfig.Npcs[npcId]
	if not npc then
		return nil
	end
	local entry = if data and data.Npcs[npcId] then data.Npcs[npcId] else emptyNpc()
	local steps = #npc.Steps
	if entry.Step > steps then
		return { Status = "Done", Step = steps + 1, Steps = steps, Progress = 0, Target = 0 }
	end
	local step = npc.Steps[entry.Step]
	local target = AdventureLogic.target(step)
	if not entry.Accepted then
		return { Status = "Offer", Step = entry.Step, Steps = steps, Progress = 0, Target = target }
	end
	local progress = progressOf(entry, step)
	return { Status = if progress >= target then "Ready" else "Active", Step = entry.Step, Steps = steps, Progress = progress, Target = target }
end

function AdventureLogic.isComplete(data: AdventureData?, npcId: string): boolean
	local state = AdventureLogic.state(data, npcId)
	return state ~= nil and state.Status == "Done"
end

function AdventureLogic.allComplete(data: AdventureData?): boolean
	for _, npcId in NPC_ORDER do
		if not AdventureLogic.isComplete(data, npcId) then
			return false
		end
	end
	return true
end

-- ¿Están terminadas las historias que abren la segunda ranura (SlotStories; sin lista,
-- todas)?
function AdventureLogic.slotStoriesComplete(data: AdventureData?): boolean
	local stories = AdventureConfig.SlotStories or NPC_ORDER
	for _, npcId in stories do
		if not AdventureLogic.isComplete(data, npcId) then
			return false
		end
	end
	return true
end

-- Ranuras de amuleto: la segunda con las historias de SlotStories terminadas.
function AdventureLogic.slots(data: AdventureData?): number
	if AdventureLogic.slotStoriesComplete(data) then
		return AdventureConfig.MaxSlots
	end
	return AdventureConfig.BaseSlots
end

-- Acciones ------------------------------------------------------------------------------------

-- Aceptar el paso actual de un personaje.
function AdventureLogic.accept(data: AdventureData, npcId: any): string
	if type(npcId) ~= "string" or not AdventureConfig.Npcs[npcId] then
		return "InvalidRequest"
	end
	local state = AdventureLogic.state(data, npcId)
	if state.Status == "Done" then
		return "AlreadyClaimed"
	elseif state.Status ~= "Offer" then
		return "AlreadyAccepted"
	end
	local entry = entryOf(data, npcId)
	entry.Accepted = true
	entry.Progress = 0
	entry.Found = {}
	return "Success"
end

-- Evento del servidor -> progreso. event: { Type = "Kill", TypeId, ZoneId } |
-- { Type = "Collect", ItemId } | { Type = "Talk", NpcId }.
-- Devuelve los cambios: { { Npc, Progress, Target, Ready } } (vacío si no cuenta para nada).
function AdventureLogic.record(data: AdventureData, event: any): { any }
	local changes = {}
	if type(event) ~= "table" then
		return changes
	end
	local function note(npcId: string)
		local state = AdventureLogic.state(data, npcId)
		table.insert(changes, { Npc = npcId, Progress = state.Progress, Target = state.Target, Ready = state.Status == "Ready" })
	end
	if event.Type == "Collect" then
		local owner = type(event.ItemId) == "string" and ITEM_OWNER[event.ItemId]
		if not owner then
			return changes
		end
		local entry = data.Npcs[owner.Npc]
		if entry and entry.Accepted and entry.Step == owner.Step and not entry.Found[event.ItemId] then
			entry.Found[event.ItemId] = true
			note(owner.Npc)
		end
		return changes
	end
	for _, npcId in NPC_ORDER do
		local entry = data.Npcs[npcId]
		if entry and entry.Accepted then
			local step = AdventureLogic.stepOf(npcId, entry.Step)
			local goal = step and step.Goal
			local target = if step then AdventureLogic.target(step) else 0
			if goal and entry.Progress < target then
				local counts = false
				if event.Type == "Kill" and goal.Type == "Kill" then
					counts = table.find(goal.Enemies, event.TypeId) ~= nil and (goal.Zone == nil or goal.Zone == event.ZoneId)
				elseif event.Type == "Talk" and goal.Type == "Talk" then
					counts = goal.Npc == event.NpcId
				end
				if counts then
					entry.Progress += 1
					note(npcId)
				end
			end
		end
	end
	return changes
end

-- Entregar el paso actual. Devuelve (código, paso entregado, índice). La bendición y el
-- amuleto se conceden aquí; la energía la calcula el servidor (depende de la economía).
function AdventureLogic.turnIn(data: AdventureData, npcId: any): (string, any, number?)
	if type(npcId) ~= "string" or not AdventureConfig.Npcs[npcId] then
		return "InvalidRequest", nil, nil
	end
	local state = AdventureLogic.state(data, npcId)
	if state.Status == "Done" then
		return "AlreadyClaimed", nil, nil
	elseif state.Status ~= "Ready" then
		return "NotComplete", nil, nil
	end
	local entry = entryOf(data, npcId)
	local stepIndex = entry.Step
	local step = AdventureLogic.stepOf(npcId, stepIndex)
	-- Marca primero (sin pausas entre la comprobación y la marca).
	entry.Step += 1
	entry.Accepted = false
	entry.Progress = 0
	entry.Found = {}
	local reward = step.Reward
	if reward.Blessing then
		data.Blessings[reward.Blessing] = math.min((data.Blessings[reward.Blessing] or 0) + 1, AdventureConfig.MaxBlessings)
	end
	if reward.Amulet then
		local first = next(data.Amulets) == nil
		data.Amulets[reward.Amulet] = true
		-- El primer amuleto se pone solo (la ranura estaba vacía).
		if first and data.Equipped[1] == "" then
			data.Equipped[1] = reward.Amulet
		end
	end
	return "Success", step, stepIndex
end

-- 💰 de un paso: min(Min · factor, Max) con el factor de la zona del personaje
-- (AdventureConfig.ZoneMoneyFactor; sin factor válido, el mínimo).
function AdventureLogic.rewardMoney(step: any, factor: number?): number
	local settings = step and step.Reward and step.Reward.Money
	if not settings then
		return 0
	end
	local f = if isFiniteNumber(factor) and (factor :: number) > 0 then factor :: number else 1
	return math.floor(math.clamp(settings.Min * f, settings.Min, settings.Max))
end

-- Poner un amuleto en una ranura (si ya estaba en otra, se mueve).
function AdventureLogic.equip(data: AdventureData, amuletId: any, slot: any): string
	if type(amuletId) ~= "string" or not AdventureConfig.Amulets[amuletId] then
		return "InvalidRequest"
	end
	if not data.Amulets[amuletId] then
		return "NotOwned"
	end
	local slots = AdventureLogic.slots(data)
	local target = if slot == nil then nil else cleanInteger(slot, 0, 99)
	if target == nil then
		-- Sin ranura: la primera vacía; si no hay, la primera.
		target = 1
		for index = 1, slots do
			if data.Equipped[index] == "" then
				target = index
				break
			end
		end
	end
	if target < 1 or target > slots then
		return "Locked"
	end
	if data.Equipped[target] == amuletId then
		return "AlreadySelected"
	end
	for index = 1, AdventureConfig.MaxSlots do
		if data.Equipped[index] == amuletId then
			data.Equipped[index] = ""
		end
	end
	data.Equipped[target] = amuletId
	return "Success"
end

function AdventureLogic.unequip(data: AdventureData, slot: any): string
	local index = if isFiniteNumber(slot) then math.floor(slot) else -1
	if index < 1 or index > AdventureConfig.MaxSlots then
		return "InvalidRequest"
	end
	if data.Equipped[index] == "" then
		return "InvalidRequest"
	end
	data.Equipped[index] = ""
	return "Success"
end

-- Suma bendiciones guardadas (premios diarios y códigos). Solo las que existen y con
-- cantidades enteras positivas; respeta el tope de cada tipo. Devuelve las que se sumaron.
function AdventureLogic.addBlessings(data: AdventureData, blessings: any): { [string]: number }
	local added = {}
	if type(blessings) ~= "table" then
		return added
	end
	for blessingId, count in blessings do
		if type(blessingId) == "string" and AdventureConfig.Blessings[blessingId] and type(count) == "number" and count >= 1 and count == count then
			local before = data.Blessings[blessingId] or 0
			local after = math.min(before + math.floor(count), AdventureConfig.MaxBlessings)
			if after > before then
				data.Blessings[blessingId] = after
				added[blessingId] = after - before
			end
		end
	end
	return added
end

-- Activar una bendición guardada. Devuelve (código, hora en que termina).
function AdventureLogic.useBlessing(data: AdventureData, blessingId: any, now: number): (string, number?)
	local blessing = type(blessingId) == "string" and AdventureConfig.Blessings[blessingId]
	if not blessing then
		return "InvalidRequest", nil
	end
	if (data.Blessings[blessingId] or 0) <= 0 then
		return "NotOwned", nil
	end
	local current = data.Active[blessingId]
	local start = if current and current > now then current else now
	if start - now >= AdventureConfig.MaxActiveSeconds then
		return "MaxLevel", current -- ya está al tope: no se gasta
	end
	data.Blessings[blessingId] -= 1
	if data.Blessings[blessingId] <= 0 then
		data.Blessings[blessingId] = nil
	end
	local expires = math.min(start + blessing.Duration, now + AdventureConfig.MaxActiveSeconds)
	data.Active[blessingId] = expires
	return "Success", expires
end

-- Quita las bendiciones caducadas. Devuelve true si quitó alguna.
function AdventureLogic.prune(data: AdventureData, now: number): boolean
	local changed = false
	for blessingId, expires in data.Active do
		if expires <= now then
			data.Active[blessingId] = nil
			changed = true
		end
	end
	return changed
end

-- Pasivas -------------------------------------------------------------------------------------

-- Suma de los amuletos puestos (solo las ranuras abiertas) para una estadística.
function AdventureLogic.amuletBonus(data: AdventureData?, stat: string): number
	if type(data) ~= "table" or type(data.Equipped) ~= "table" then
		return 0
	end
	local total = 0
	for slot = 1, AdventureLogic.slots(data) do
		local amulet = AdventureConfig.Amulets[data.Equipped[slot] or ""]
		if amulet and data.Amulets[data.Equipped[slot]] and amulet.Effect.Stat == stat then
			total += amulet.Effect.Value
		end
	end
	return total
end

-- Suma de las bendiciones activas en `now` para una estadística.
function AdventureLogic.blessingBonus(data: AdventureData?, stat: string, now: number?): number
	if type(data) ~= "table" or type(data.Active) ~= "table" or not isFiniteNumber(now) then
		return 0
	end
	local total = 0
	for blessingId, expires in data.Active do
		local blessing = AdventureConfig.Blessings[blessingId]
		if blessing and blessing.Effect.Stat == stat and expires > (now :: number) then
			total += blessing.Effect.Value
		end
	end
	return total
end

local function multiplier(data: AdventureData?, stat: string, now: number?): number
	return (1 + AdventureLogic.amuletBonus(data, stat)) * (1 + AdventureLogic.blessingBonus(data, stat, now))
end

-- Energía producida (con el jugador conectado).
function AdventureLogic.productionMultiplier(data: AdventureData?, now: number?): number
	return multiplier(data, "Production", now)
end

-- Producción sin jugar: solo los amuletos (las bendiciones son para jugar).
function AdventureLogic.offlineMultiplier(data: AdventureData?): number
	return 1 + AdventureLogic.amuletBonus(data, "Production")
end

function AdventureLogic.damageMultiplier(data: AdventureData?, now: number?): number
	return multiplier(data, "Damage", now)
end

function AdventureLogic.lootMultiplier(data: AdventureData?, now: number?): number
	return multiplier(data, "Loot", now)
end

function AdventureLogic.walkSpeedMultiplier(data: AdventureData?): number
	return 1 + AdventureLogic.amuletBonus(data, "WalkSpeed")
end

-- Objetos perdidos que el jugador debe ver (pasos Collect aceptados, sin encontrar).
function AdventureLogic.pendingItems(data: AdventureData?): { string }
	local items = {}
	if type(data) ~= "table" then
		return items
	end
	for _, npcId in NPC_ORDER do
		local entry = data.Npcs[npcId]
		if entry and entry.Accepted then
			local step = AdventureLogic.stepOf(npcId, entry.Step)
			if step and step.Goal.Type == "Collect" then
				for _, itemId in step.Goal.Items do
					if not entry.Found[itemId] then
						table.insert(items, itemId)
					end
				end
			end
		end
	end
	return items
end

-- Estado para la interfaz. `rewards` (opcional): npcId -> energía del paso actual.
function AdventureLogic.snapshot(data: AdventureData?, now: number, rewards: { [string]: number }?): any
	local npcs = {}
	for _, npcId in NPC_ORDER do
		local state = AdventureLogic.state(data, npcId)
		state.Reward = if rewards then rewards[npcId] or 0 else 0
		local found = {}
		local entry = data and data.Npcs[npcId]
		if entry and entry.Accepted then
			for itemId in entry.Found do
				table.insert(found, itemId)
			end
			table.sort(found)
		end
		state.Found = found
		npcs[npcId] = state
	end
	local owned = {}
	for _, amuletId in AMULET_ORDER do
		if data and data.Amulets[amuletId] then
			table.insert(owned, amuletId)
		end
	end
	local blessings, active = {}, {}
	for _, blessingId in BLESSING_ORDER do
		local count = if data then data.Blessings[blessingId] or 0 else 0
		if count > 0 then
			blessings[blessingId] = count
		end
		local expires = if data then data.Active[blessingId] else nil
		if expires and expires > now then
			active[blessingId] = expires
		end
	end
	return {
		Ready = true,
		Now = now,
		Npcs = npcs,
		Amulets = owned,
		Equipped = if data then table.clone(data.Equipped) else AdventureLogic.empty().Equipped,
		Slots = AdventureLogic.slots(data),
		Blessings = blessings,
		Active = active,
		Pending = AdventureLogic.pendingItems(data),
	}
end

return AdventureLogic
