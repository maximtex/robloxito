Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }
local PetConfig = (function()
-- Mascotas y rarezas. Para añadir una mascota: añadir una entrada en Pets (con un ID
-- estable que no se renombre nunca: es lo que se guarda) y referenciarla desde un huevo
-- en EggConfig. El servidor valida esta tabla al arrancar.
--
-- Multiplicador: cada mascota equipada aporta (Multiplier - 1) de bonificación y las
-- bonificaciones se suman. Ej.: 1.10 + 1.25 equipadas = x1.35 de producción.
--
-- MODELOS: Look.Style elige un prototipo hecho con piezas nativas (PetModelBuilder).
-- Los marcados con Prototype = true deben sustituirse por arte definitivo: basta con
-- colocar un Model llamado igual que el ID en ReplicatedStorage.PetModels (con
-- PrimaryPart); PetModelBuilder lo usará automáticamente en lugar del prototipo.

local PetConfig = {
	MaxEquipped = 3,
	MaxInventory = 60,

	-- Multiplier: valor por defecto de las mascotas de esa rareza si no indican uno propio.
	Rarities = {
		Common = { DisplayName = "Común", Order = 1, Color = Color3.fromRGB(196, 204, 186), Multiplier = 1.1 },
		Uncommon = { DisplayName = "Poco común", Order = 2, Color = Color3.fromRGB(120, 214, 120), Multiplier = 1.25 },
		Rare = { DisplayName = "Rara", Order = 3, Color = Color3.fromRGB(96, 180, 255), Multiplier = 1.5 },
		Epic = { DisplayName = "Épica", Order = 4, Color = Color3.fromRGB(196, 120, 255), Multiplier = 2 },
		Legendary = { DisplayName = "Legendaria", Order = 5, Color = Color3.fromRGB(255, 200, 80), Multiplier = 3 },
	},

	Pets = {
		-- Huevo del Bosque ----------------------------------------------------------
		Sproutling = {
			DisplayName = "Brotecillo",
			Rarity = "Common",
			Multiplier = 1.1,
			Look = { Style = "Sprout", Prototype = true, Primary = Color3.fromRGB(156, 222, 112), Secondary = Color3.fromRGB(64, 150, 70) },
		},
		MushroomHopper = {
			DisplayName = "Seta Saltarina",
			Rarity = "Common",
			Multiplier = 1.1,
			Look = { Style = "Mushroom", Prototype = true, Primary = Color3.fromRGB(214, 70, 58), Secondary = Color3.fromRGB(244, 234, 214) },
		},
		EmberFox = {
			DisplayName = "Zorrito de Brasa",
			Rarity = "Uncommon",
			Multiplier = 1.25,
			Look = { Style = "Ember", Prototype = true, Primary = Color3.fromRGB(226, 96, 44), Secondary = Color3.fromRGB(255, 196, 70) },
		},

		-- Huevo de Musgo -----------------------------------------------------------
		MossFox = {
			DisplayName = "Zorro de Musgo",
			Rarity = "Uncommon",
			Multiplier = 1.25,
			Look = { Style = "Fox", Prototype = true, Primary = Color3.fromRGB(206, 124, 62), Secondary = Color3.fromRGB(112, 170, 82) },
		},

		-- Huevos de Musgo y Ancestral -------------------------------------------------
		MoonOwl = {
			DisplayName = "Búho Lunar",
			Rarity = "Rare",
			Multiplier = 1.5,
			Look = { Style = "Owl", Prototype = true, Primary = Color3.fromRGB(150, 160, 214), Secondary = Color3.fromRGB(110, 118, 176) },
		},

		-- Huevo Ancestral ------------------------------------------------------------
		EmeraldFawn = {
			DisplayName = "Cervatillo Esmeralda",
			Rarity = "Epic",
			Multiplier = 2,
			Look = { Style = "Fawn", Prototype = true, Primary = Color3.fromRGB(150, 112, 74), Secondary = Color3.fromRGB(70, 220, 130) },
		},
	},
}

return PetConfig
end)()
local PetLayout = (function()
-- Posiciones de las mascotas detrás del jugador (lógica pura, sin APIs de Roblox).
-- Garantiza que:
-- - dos mascotas nunca se solapan (separación >= suma de radios + GAP);
-- - ninguna queda dentro del jugador (distancia >= radio del jugador + su radio + GAP).
-- Cada hueco se expresa como { X = desplazamiento lateral, Z = distancia hacia atrás }.

local PetLayout = {}

PetLayout.GAP = 0.6
PetLayout.PLAYER_RADIUS = 1.6
PetLayout.ARC = 0.15 -- las de los lados se retrasan un poco: forma de abanico

export type Slot = { X: number, Z: number }

function PetLayout.slots(radii: { number }): { Slot }
	local count = #radii
	local slots: { Slot } = {}
	if count == 0 then
		return slots
	end

	-- Distancia hacia atrás común: la mascota más grande cabe sin tocar al jugador.
	local largest = 0
	for _, radius in radii do
		largest = math.max(largest, radius)
	end
	local back = PetLayout.PLAYER_RADIUS + largest + PetLayout.GAP + 0.6

	-- Laterales encadenados según el tamaño de cada vecina, y luego centrados.
	local laterals = { 0 }
	for index = 2, count do
		laterals[index] = laterals[index - 1] + radii[index - 1] + radii[index] + PetLayout.GAP
	end
	local center = (laterals[1] + laterals[count]) / 2

	for index = 1, count do
		local lateral = laterals[index] - center
		slots[index] = { X = lateral, Z = back + math.abs(lateral) * PetLayout.ARC }
	end
	return slots
end

-- Distancia mínima (en horizontal) entre el centro del jugador y una mascota.
function PetLayout.minDistanceFromPlayer(radius: number): number
	return PetLayout.PLAYER_RADIUS + radius + PetLayout.GAP
end

return PetLayout
end)()
local STYLES = { "Sprout","Fox","Owl","Mushroom","Ember","Fawn" }
local MOTIONS = { "Sprout","Mushroom","Fox","Ember","Fawn","Owl" }
local MAX_STORED_PETS = 1000
local SaveService = {}
function SaveService.emptyData(): PetData
	return { Pets = {}, Archived = {}, Equipped = {}, NextPetUid = 1 }
end
local function sanitize(raw: any): PetData
	local result = SaveService.emptyData()
	if type(raw) ~= "table" then
		return result
	end

	local seen: { [string]: boolean } = {}
	if type(raw.Pets) == "table" then
		for _, entry in raw.Pets do
			if #result.Pets + #result.Archived >= MAX_STORED_PETS then
				break
			end
			if type(entry) == "table" and type(entry.Uid) == "string" and type(entry.PetId) == "string" and not seen[entry.Uid] then
				seen[entry.Uid] = true
				local clean = { Uid = entry.Uid, PetId = entry.PetId }
				if PetConfig.Pets[entry.PetId] then
					table.insert(result.Pets, clean)
				else
					table.insert(result.Archived, clean)
				end
			end
		end
	end

	local valid: { [string]: boolean } = {}
	for _, entry in result.Pets do
		valid[entry.Uid] = true
	end
	if type(raw.Equipped) == "table" then
		for _, uid in raw.Equipped do
			if type(uid) == "string" and valid[uid] and not table.find(result.Equipped, uid) and #result.Equipped < PetConfig.MaxEquipped then
				table.insert(result.Equipped, uid)
			end
		end
	end

	local nextUid = if type(raw.NextPetUid) == "number" and raw.NextPetUid >= 1 then math.floor(raw.NextPetUid) else 1
	-- Garantiza que nunca se reutiliza un Uid existente.
	for uid in seen do
		local number = tonumber(uid)
		if number and number >= nextUid then
			nextUid = math.floor(number) + 1
		end
	end
	result.NextPetUid = nextUid

	return result
end
local failures = 0
local function check(name, ok) if not ok then failures += 1 end print((ok and "OK   " or "FALLO") .. "  " .. name) end

-- Cada mascota tiene modelo propio y movimiento propio (no recoloreados ni genéricos)
local hasStyle, hasMotion, styleOwner = {}, {}, {}
for _, s in STYLES do hasStyle[s] = true end
for _, s in MOTIONS do hasMotion[s] = true end
for petId, pet in PetConfig.Pets do
	local style = pet.Look.Style
	check(("%s: estilo '%s' con constructor propio"):format(petId, style), hasStyle[style] == true)
	check(("%s: estilo '%s' con movimiento propio"):format(petId, style), hasMotion[style] == true)
	check(("%s: estilo no compartido con otra mascota"):format(petId), styleOwner[style] == nil)
	styleOwner[style] = petId
end

-- Disposición: sin solapes y nunca dentro del jugador
math.randomseed(7)
local worstPair, worstPlayer, cases = math.huge, math.huge, 0
for _ = 1, 2000 do
	local radii = {}
	for i = 1, math.random(1, 3) do radii[i] = 0.6 + math.random() * 1.9 end
	local slots = PetLayout.slots(radii)
	cases += 1
	for i = 1, #slots do
		local d = math.sqrt(slots[i].X ^ 2 + slots[i].Z ^ 2)
		worstPlayer = math.min(worstPlayer, d - (PetLayout.PLAYER_RADIUS + radii[i]))
		for j = i + 1, #slots do
			local dij = math.sqrt((slots[i].X - slots[j].X) ^ 2 + (slots[i].Z - slots[j].Z) ^ 2)
			worstPair = math.min(worstPair, dij - (radii[i] + radii[j]))
		end
	end
end
check(("%d disposiciones: hueco mínimo entre mascotas %.2f studs (>= %.1f)"):format(cases, worstPair, PetLayout.GAP), worstPair >= PetLayout.GAP - 1e-9)
check(("%d disposiciones: hueco mínimo con el jugador %.2f studs (>= %.1f)"):format(cases, worstPlayer, PetLayout.GAP), worstPlayer >= PetLayout.GAP - 1e-9)
check("sin mascotas -> sin huecos", #PetLayout.slots({}) == 0)

-- Guardado: partidas antiguas siguen siendo válidas con el catálogo nuevo
local old = sanitize({
	Pets = { { Uid = "1", PetId = "Sproutling" }, { Uid = "2", PetId = "MossFox" }, { Uid = "3", PetId = "MoonOwl" }, { Uid = "4", PetId = "Borrada" } },
	Equipped = { "2", "3" },
	NextPetUid = 5,
})
check("partida antigua: Brotecillo, Zorro de Musgo y Búho Lunar se conservan", #old.Pets == 3)
check("partida antigua: equipamiento conservado (2,3)", #old.Equipped == 2 and old.Equipped[1] == "2" and old.Equipped[2] == "3")
check("partida antigua: especie inexistente archivada, no borrada", #old.Archived == 1)
local newer = sanitize({ Pets = { { Uid = "1", PetId = "EmberFox" }, { Uid = "2", PetId = "MushroomHopper" }, { Uid = "3", PetId = "EmeraldFawn" } }, Equipped = { "1", "2", "3" }, NextPetUid = 4 })
check("mascotas nuevas se cargan y equipan", #newer.Pets == 3 and #newer.Equipped == 3 and #newer.Archived == 0)
print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
