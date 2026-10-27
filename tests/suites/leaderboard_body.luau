-- Monolitos de clasificación: LeaderboardLogic (orden puro) y su sitio en el bosque, que no
-- pisa la plaza, los altares, el spawn, los caminos ni nada del paisaje.

local failures = 0
local function check(name, ok)
	if not ok then
		failures += 1
	end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end

LandscapeLayout.init({
	LandscapeConfig = LandscapeConfig,
	WorldConfig = WorldConfig,
	ValleyConfig = ValleyConfig,
	CalderaConfig = CalderaConfig,
	EggConfig = EggConfig,
	ZoneConfig = ZoneConfig,
	EnemyConfig = EnemyConfig,
	AdventureConfig = AdventureConfig,
	VillageConfig = VillageConfig,
	WildsConfig = WildsConfig,
	ChestConfig = ChestConfig,
})

print("-- 1. Orden")
local top = LeaderboardLogic.rank({
	{ Name = "Ana", Value = 50 },
	{ Name = "Beto", Value = 900 },
	{ Name = "Caro", Value = 50, Tie = 10 },
	{ Name = "Dani", Value = 0 / 0 },
	{ Name = "Eva", Value = "mucho" },
	{ Name = "Fede", Value = 300 },
	{ Name = "Gabi", Value = 50 },
	{ Name = "Hugo", Value = math.huge },
}, 5)
check("de mayor a menor, con desempate y luego por nombre", #top == 5 and top[1].Name == "Beto" and top[2].Name == "Fede" and top[3].Name == "Caro" and top[4].Name == "Ana" and top[5].Name == "Gabi")
check("ignora valores no válidos (NaN, texto, infinito)", (function()
	for _, entry in top do
		if entry.Name == "Dani" or entry.Name == "Eva" or entry.Name == "Hugo" then
			return false
		end
	end
	return true
end)())
check("con menos jugadores que puestos devuelve los que hay", #LeaderboardLogic.rank({ { Name = "Solo", Value = 1 } }, 5) == 1 and #LeaderboardLogic.rank({}, 5) == 0)
check("entradas raras no rompen nada", #LeaderboardLogic.rank({ 1, "x", { Value = 3 }, { Name = "Ok", Value = 2 } }, 3) == 1)

local pagesOk = true
for _, board in LeaderboardConfig.Boards do
	for _, page in board.Pages do
		pagesOk = pagesOk and LeaderboardConfig.PageTitles[page] ~= nil
		if page == "Global" then
			pagesOk = pagesOk and LeaderboardConfig.Global.Stores[board.Global] ~= nil
		end
	end
	pagesOk = pagesOk and board.Pages[1] == "Server"
end
check("páginas de cada monolito: existen, la primera es la del servidor y las globales tienen su tabla", pagesOk and LeaderboardConfig.Global.Stores.Weekly ~= nil)

print("-- 2. Sitio en el bosque")
local obstacles = LandscapeLayout.obstacles("Forest")
-- Lo que LandscapeLayout aún cuenta pero el mapa de bloques (StudFloor) ya no construye: el
-- sitio que reservaban los antiguos altares de los núcleos (WorldConfig.AltarReserve) y la
-- decoración del terreno antiguo de WorldConfig (plaza de adoquines,
-- árboles, rocas, columnas, setas y cristales). Comprobado en Studio: los monolitos solo
-- rozan un montón de regalos de Navidad.
local GONE = { "^Plaza$", "^Altar_", "^AncientTree$", "^Tree%d", "^Rock%d", "^Column%d", "^Mushrooms%d", "^Crystals%d" }
local function gone(name: string): boolean
	for _, pattern in GONE do
		if string.match(name, pattern) then
			return true
		end
	end
	return false
end
local layout = LandscapeLayout.compute("Forest")
local clearOk, pathOk, keepOk, scatterOk = true, true, true, true
for _, board in LeaderboardConfig.Boards do
	local x, z, r = board.Position.X, board.Position.Y, LeaderboardConfig.Footprint
	local covered = false
	for _, item in obstacles.Hard do
		local d = math.sqrt((x - item.X) ^ 2 + (z - item.Z) ^ 2)
		if item.Name == "KeepClear" and d < 0.5 then
			covered = covered or item.R >= r
		elseif d < item.R + r and not gone(item.Name) then
			clearOk = false
			print(("  %s pisa %s"):format(board.Id, item.Name))
		end
	end
	keepOk = keepOk and covered
	if LandscapeLayout.distanceToPaths(x, z, obstacles.Paths) < r + 0.5 then
		pathOk = false
		print("  " .. board.Id .. " está encima de un camino")
	end
	for _, item in layout.Scatter do
		if (x - item.X) ^ 2 + (z - item.Z) ^ 2 < (item.R + r) ^ 2 then
			scatterOk = false
		end
	end
	for _, lamp in layout.Lamps do
		if (x - lamp.X) ^ 2 + (z - lamp.Z) ^ 2 < (lamp.R + r) ^ 2 then
			scatterOk = false
		end
	end
end
check("los monolitos no pisan nada de lo que se construye (spawn, jardín, portales, enemigos...)", clearOk)
-- Los caminos de LandscapeLayout solo existen con la decoración (LandscapeConfig.BuildsDecor).
if LandscapeConfig.BuildsDecor ~= false then
	check("no están sobre ningún camino", pathOk)
else
	print("OMIT   no están sobre ningún camino (los caminos de LandscapeLayout no se construyen)")
end
check("WorldConfig.KeepClear cubre cada monolito (sin flores encima)", keepOk)
check("el paisaje al azar y los faroles no los tapan", scatterOk)
local faceOk = true
for _, board in LeaderboardConfig.Boards do
	local spawn = LeaderboardConfig.FaceToward
	local d = math.sqrt((spawn.X - board.Position.X) ^ 2 + (spawn.Y - board.Position.Y) ^ 2)
	faceOk = faceOk and d > 8 and d < 40
end
check("se ven desde el spawn (a menos de 40 studs y mirándolo)", faceOk)

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
