-- Personajes (perfiles) de una cuenta (pruebas con amigos: "cambiar de clase a mitad de
-- partida no tiene gracia; mejor crear personajes, cada uno con su clase y su progreso").
-- Lógica pura: la usan SaveService (guardar la cuenta), PlayerDataService (qué personaje se
-- carga), ProfileService (crear y elegir) y el cliente (la lista en ⚙️ Ajustes).
--
-- Cuenta (DataStore de cuentas, una entrada por jugador):
--   Slots: { [hueco]: { Style, Created, Rebirths, Zone, Fresh } }  hasta MaxProfiles
--     Style     clase del personaje (fija; nil en el personaje de antes de los personajes,
--               que puede cambiar de estilo como siempre)
--     Rebirths, Zone  para la lista (renacimientos y mejor zona abierta)
--     Fresh     recién creado: al cargarlo por primera vez se le pone su clase
--   Last: hueco con el que se entra
--   TutorialDone: algún personaje ya completó u omitió el tutorial (los nuevos empiezan sin él)
-- Cada personaje guarda su progreso en su propia entrada (SaveService: hueco 1 = la de
-- siempre). Lo comprado con Robux en pases es de la cuenta (Roblox lo dice en cada servidor).

local ProfileLogic = {}

ProfileLogic.MaxProfiles = 3

export type Slot = { Style: string?, Created: number, Rebirths: number, Zone: string?, Fresh: boolean? }
export type Account = { Slots: { [number]: Slot }, Last: number, TutorialDone: boolean? }

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function ProfileLogic.empty(): Account
	return { Slots = {}, Last = 1 }
end

-- Guardado (o nada) -> cuenta válida. `styles`: los estilos que existen (StyleConfig.Styles).
function ProfileLogic.sanitize(raw: any, styles: { [string]: any }): Account
	local account = ProfileLogic.empty()
	if type(raw) ~= "table" then
		return account
	end
	if type(raw.Slots) == "table" then
		for key, entry in raw.Slots do
			local slot = tonumber(key)
			if slot and slot == math.floor(slot) and slot >= 1 and slot <= ProfileLogic.MaxProfiles and type(entry) == "table" then
				account.Slots[slot] = {
					Style = if type(entry.Style) == "string" and styles[entry.Style] then entry.Style else nil,
					Created = if isFiniteNumber(entry.Created) then entry.Created else 0,
					Rebirths = if isFiniteNumber(entry.Rebirths) then math.max(0, math.floor(entry.Rebirths)) else 0,
					Zone = if type(entry.Zone) == "string" and #entry.Zone <= 40 then entry.Zone else nil,
					Fresh = if entry.Fresh == true then true else nil,
				}
			end
		end
	end
	local last = tonumber(raw.Last)
	if last and account.Slots[last] then
		account.Last = last
	end
	account.TutorialDone = if raw.TutorialDone == true then true else nil
	return account
end

-- Para guardar (claves de texto: los DataStores no guardan tablas con huecos)
function ProfileLogic.serialize(account: Account): any
	local slots = {}
	for slot, entry in account.Slots do
		slots[tostring(slot)] = { Style = entry.Style, Created = entry.Created, Rebirths = entry.Rebirths, Zone = entry.Zone, Fresh = entry.Fresh }
	end
	return { Slots = slots, Last = account.Last, TutorialDone = if account.TutorialDone then true else nil }
end

function ProfileLogic.count(account: Account): number
	local count = 0
	for _ in account.Slots do
		count += 1
	end
	return count
end

-- Primer hueco libre (nil si ya tiene el máximo)
function ProfileLogic.freeSlot(account: Account): number?
	for slot = 1, ProfileLogic.MaxProfiles do
		if not account.Slots[slot] then
			return slot
		end
	end
	return nil
end

-- El personaje con el que juega aparece siempre en la lista (el de antes de los personajes
-- no estaba: es el hueco 1, sin clase fija).
function ProfileLogic.ensureSlot(account: Account, slot: number, now: number)
	if not account.Slots[slot] then
		account.Slots[slot] = { Style = nil, Created = now, Rebirths = 0, Zone = nil }
	end
end

-- Crea un personaje con su clase y lo deja como el siguiente con el que entrar. Devuelve el
-- código ("Success", "Full" o "InvalidRequest") y el hueco.
function ProfileLogic.create(account: Account, styleId: any, now: number, styles: { [string]: any }): (string, number?)
	if type(styleId) ~= "string" or not styles[styleId] then
		return "InvalidRequest", nil
	end
	local slot = ProfileLogic.freeSlot(account)
	if not slot then
		return "Full", nil
	end
	account.Slots[slot] = { Style = styleId, Created = now, Rebirths = 0, Zone = nil, Fresh = true }
	account.Last = slot
	return "Success", slot
end

-- Elige con qué personaje entrar la próxima vez. Devuelve "Success" o "InvalidRequest".
function ProfileLogic.select(account: Account, slot: any): string
	local number = tonumber(slot)
	if not (number and account.Slots[number]) then
		return "InvalidRequest"
	end
	account.Last = number
	return "Success"
end

-- Junta con lo guardado: los personajes que haya guardados y esta cuenta no tenga se quedan
-- (un guardado viejo de otro servidor nunca borra un personaje creado después).
function ProfileLogic.merge(account: Account, stored: Account)
	for slot, entry in stored.Slots do
		if not account.Slots[slot] then
			account.Slots[slot] = table.clone(entry)
		end
	end
	if stored.TutorialDone then
		account.TutorialDone = true
	end
end

-- Actualiza lo que se ve en la lista (renacimientos y mejor zona) y quita Fresh.
function ProfileLogic.updateSummary(account: Account, slot: number, rebirths: number?, zone: string?)
	local entry = account.Slots[slot]
	if not entry then
		return
	end
	entry.Rebirths = if isFiniteNumber(rebirths) then math.max(0, math.floor(rebirths :: number)) else entry.Rebirths
	entry.Zone = zone or entry.Zone
	entry.Fresh = nil
end

-- Para el cliente (atributo Profiles): "hueco:clase:renacimientos:zona" separados por "|"
-- (clase vacía = sin clase fija)
function ProfileLogic.encode(account: Account): string
	local parts = {}
	for slot = 1, ProfileLogic.MaxProfiles do
		local entry = account.Slots[slot]
		if entry then
			table.insert(parts, ("%d:%s:%d:%s"):format(slot, entry.Style or "", entry.Rebirths or 0, entry.Zone or ""))
		end
	end
	return table.concat(parts, "|")
end

export type Listed = { Slot: number, Style: string?, Rebirths: number, Zone: string? }

function ProfileLogic.decode(text: any): { Listed }
	local list = {}
	if type(text) ~= "string" then
		return list
	end
	for chunk in string.gmatch(text, "[^|]+") do
		local slot, style, rebirths, zone = string.match(chunk, "^(%d+):([^:]*):(%d+):([^:]*)$")
		if slot then
			table.insert(list, {
				Slot = tonumber(slot) :: number,
				Style = if style ~= "" then style else nil,
				Rebirths = tonumber(rebirths) or 0,
				Zone = if zone ~= "" then zone else nil,
			})
		end
	end
	return list
end

return ProfileLogic
