-- Sustitutos mínimos de tipos de Roblox para ejecutar los módulos puros.
Color3 = { fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end }
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
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
local EggConfig = (function()
-- Huevos. Para añadir uno: nueva entrada en Eggs con su coste, probabilidades y
-- posición del santuario. El servidor valida al arrancar que las probabilidades
-- sumen 100 y que todas las mascotas existan en PetConfig.

local EggConfig = {
	-- Distancia máxima (studs) entre el jugador y el santuario para poder comprar.
	MaxPurchaseDistance = 18,
	-- Segundos mínimos entre aperturas (cubre la animación de incubación).
	PurchaseCooldown = 1.5,

	Eggs = {
		ForestEgg = {
			DisplayName = "Huevo del Bosque",
			Cost = 100, -- en energía
			-- Probabilidades explícitas en porcentaje (deben sumar 100).
			Chances = {
				{ PetId = "Sproutling", Chance = 70 },
				{ PetId = "MossFox", Chance = 25 },
				{ PetId = "MoonOwl", Chance = 5 },
			},
			-- Posición del santuario relativa al cristal (X, Z). El spawn está en Z ≈ +25.
			StandOffset = Vector2.new(-20, 12),
			Look = {
				Shell = Color3.fromRGB(240, 232, 200),
				Spots = Color3.fromRGB(110, 180, 96),
			},
		},
	},
}

return EggConfig
end)()
local PetMath = (function()
-- Cálculos de mascotas compartidos. El servidor los usa para la producción real;
-- el cliente solo para mostrar información.


local PetMath = {}

function PetMath.getPetMultiplier(petId: string): number
	local pet = PetConfig.Pets[petId]
	if not pet then
		return 1
	end
	if type(pet.Multiplier) == "number" then
		return pet.Multiplier
	end
	local rarity = PetConfig.Rarities[pet.Rarity]
	return if rarity then rarity.Multiplier else 1
end

-- Las bonificaciones se suman: 1 + Σ(multiplicador - 1). Redondeado a 3 decimales.
function PetMath.getTotalMultiplier(petIds: { string }): number
	local total = 1
	for _, petId in petIds do
		total += PetMath.getPetMultiplier(petId) - 1
	end
	return math.floor(total * 1000 + 0.5) / 1000
end

function PetMath.getRarity(petId: string)
	local pet = PetConfig.Pets[petId]
	return if pet then PetConfig.Rarities[pet.Rarity] else nil
end

return PetMath
end)()
local formatNumber = (function()
-- Formatea números grandes: 1234 -> "1.23K", 5600000 -> "5.6M".
-- Con `decimals`, los valores menores de 1000 conservan hasta esos decimales
-- (1.1 -> "1.1"); sin él se redondean hacia abajo como antes.

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

local function trimZeros(text: string): string
	return (text:gsub("%.?0+$", ""))
end

local function formatNumber(value: number, decimals: number?): string
	if math.abs(value) < 1000 then
		if decimals and decimals > 0 then
			return trimZeros(string.format("%." .. decimals .. "f", value))
		end
		return tostring(math.floor(value))
	end

	value = math.floor(value)
	local index = 1
	local scaled = value
	while math.abs(scaled) >= 1000 and index < #SUFFIXES do
		scaled /= 1000
		index += 1
	end

	return trimZeros(string.format("%.2f", scaled)) .. SUFFIXES[index]
end

return formatNumber
end)()
local random = { NextNumber = function(_, a, b) return a + math.random() * (b - a) end }
local function rollPet(egg): string
	local roll = random:NextNumber(0, 100)
	local cumulative = 0
	for _, entry in egg.Chances do
		cumulative += entry.Chance
		if roll < cumulative then
			return entry.PetId
		end
	end
	return egg.Chances[#egg.Chances].PetId
end
local failures = 0
local function check(name, ok) if not ok then failures += 1 end print((ok and "OK   " or "FALLO") .. "  " .. name) end

for eggId, egg in EggConfig.Eggs do
	local total = 0
	for _, e in egg.Chances do total += e.Chance; check(eggId .. ": existe " .. e.PetId, PetConfig.Pets[e.PetId] ~= nil) end
	check(eggId .. ": probabilidades suman 100 (" .. total .. ")", math.abs(total - 100) < 1e-6)
	math.randomseed(12345)
	local counts, n = {}, 200000
	for _ = 1, n do local id = rollPet(egg); counts[id] = (counts[id] or 0) + 1 end
	for _, e in egg.Chances do
		local observed = (counts[e.PetId] or 0) / n * 100
		check(("%s: %s observado %.2f%% vs %d%%"):format(eggId, e.PetId, observed, e.Chance), math.abs(observed - e.Chance) < 0.5)
	end
end
check("multiplicador sin mascotas = 1", PetMath.getTotalMultiplier({}) == 1)
check("Brotecillo+Zorro = 1.35", PetMath.getTotalMultiplier({ "Sproutling", "MossFox" }) == 1.35)
check("3 equipadas = 1.85", PetMath.getTotalMultiplier({ "Sproutling", "MossFox", "MoonOwl" }) == 1.85)
check("mascota desconocida no suma", PetMath.getTotalMultiplier({ "Hack" }) == 1)
check("format 1.1 con 2 decimales", formatNumber(1.1, 2) == "1.1")
check("format 2.75", formatNumber(2.75, 2) == "2.75")
check("format 3 entero", formatNumber(3, 2) == "3")
check("format 999.9 sin decimales", formatNumber(999.9) == "999")
check("format 1234", formatNumber(1234) == "1.23K")
check("format 1500000", formatNumber(1500000) == "1.5M")
print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
