Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }
local PetConfig = (function()
-- Mascotas y rarezas. Para añadir una mascota: añadir una entrada en Pets y
-- referenciarla desde un huevo en EggConfig. El servidor valida esta tabla al arrancar.
--
-- Multiplicador: cada mascota equipada aporta (Multiplier - 1) de bonificación y las
-- bonificaciones se suman. Ej.: 1.10 + 1.25 equipadas = x1.35 de producción.

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

	-- Look.Style elige el modelo en el cliente (Sprout, Fox, Owl; otro valor = criatura genérica).
	Pets = {
		Sproutling = {
			DisplayName = "Brotecillo",
			Rarity = "Common",
			Multiplier = 1.1,
			Look = { Style = "Sprout", Primary = Color3.fromRGB(156, 222, 112), Secondary = Color3.fromRGB(64, 150, 70) },
		},
		MossFox = {
			DisplayName = "Zorro de Musgo",
			Rarity = "Uncommon",
			Multiplier = 1.25,
			Look = { Style = "Fox", Primary = Color3.fromRGB(206, 124, 62), Secondary = Color3.fromRGB(112, 170, 82) },
		},
		MoonOwl = {
			DisplayName = "Búho Lunar",
			Rarity = "Rare",
			Multiplier = 1.5,
			Look = { Style = "Owl", Primary = Color3.fromRGB(150, 160, 214), Secondary = Color3.fromRGB(110, 118, 176) },
		},
	},
}

return PetConfig
end)()
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

local d = sanitize(nil)
check("nil -> vacío", #d.Pets == 0 and d.NextPetUid == 1)
d = sanitize("basura")
check("tipo erróneo -> vacío", #d.Pets == 0)

d = sanitize({
	Pets = {
		{ Uid = "1", PetId = "Sproutling" },
		{ Uid = "1", PetId = "MoonOwl" }, -- uid duplicado
		{ Uid = "2", PetId = "DragonBorrado" }, -- especie que ya no existe
		{ Uid = "7", PetId = "MossFox" },
		{ Uid = 3, PetId = "MossFox" }, -- uid no string
		"basura",
		{ Uid = "9", PetId = "MoonOwl" },
		{ Uid = "10", PetId = "Sproutling" },
	},
	Equipped = { "1", "1", "2", "99", "7", "9", "10" },
	NextPetUid = 2,
})
check("válidas: 4 (" .. #d.Pets .. ")", #d.Pets == 4)
check("duplicado descartado (uid 1 es Sproutling)", d.Pets[1].PetId == "Sproutling")
check("especie desconocida archivada, no borrada", #d.Archived == 1 and d.Archived[1].PetId == "DragonBorrado")
check("equipadas: sin duplicados, sin archivadas, sin inexistentes, máx " .. PetConfig.MaxEquipped .. " -> " .. table.concat(d.Equipped, ","),
	#d.Equipped == PetConfig.MaxEquipped and d.Equipped[1] == "1" and d.Equipped[2] == "7" and d.Equipped[3] == "9")
check("NextPetUid no reutiliza uids (" .. d.NextPetUid .. ")", d.NextPetUid == 11)
print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
