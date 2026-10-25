-- Diseño del HUD (HudLayout, cálculo puro): en pantallas de escritorio y táctiles de
-- muchos tamaños, ninguna pieza fija se encima con otra ni se sale de la pantalla.

local failures = 0
local function check(name, ok)
	if not ok then failures += 1 end
	print((ok and "OK   " or "FALLO") .. "  " .. name)
end
local function info(text)
	print("INFO   " .. text)
end

local S = HudLayout.Sizes
local overlaps = HudLayout.overlaps

local function columnRect(column)
	return { X = column.X, Y = column.Y, W = column.W, H = column.Bottom - column.Y }
end
local function toastRect(t)
	return { X = t.X - t.W / 2, Y = t.Y, W = t.W, H = t.H }
end
local function fmt(r)
	return ("(%d,%d %dx%d)"):format(math.floor(r.X), math.floor(r.Y), math.floor(r.W), math.floor(r.H))
end

-- Tamaños del ScreenGui (sin la barra superior de 58 px en escritorio / ~36-56 en móvil).
local DESKTOP = {
	{ 1920, 1022 }, { 1600, 842 }, { 1536, 806 }, { 1366, 710 }, { 1280, 662 },
	{ 1631, 507 }, -- visor de Studio de la sesión
	{ 1024, 710 }, { 1024, 560 }, { 900, 600 }, { 800, 540 },
}
local TOUCH = {
	{ 667, 319 }, -- iPhone SE horizontal
	{ 844, 354 }, -- iPhone 14 horizontal
	{ 932, 394 }, -- iPhone Pro Max horizontal
	{ 800, 324 }, -- Android horizontal
	{ 1024, 712 }, -- iPad horizontal
	{ 1180, 764 }, -- iPad Air horizontal
	{ 1366, 968 }, -- iPad Pro horizontal
}

local function eachLayout(list, touch, fn)
	for _, size in list do
		local screen = Vector2.new(size[1], size[2])
		for _, boss in { false, true } do
			for _, chips in { false, true } do
				for _, entries in { 7, 8 } do
					local options = { MenuEntries = entries, StatusLines = 2, BossBar = boss, Chips = chips }
					fn(HudLayout.compute(screen, touch, options), ("%dx%d%s%s e%d"):format(size[1], size[2], boss and " jefe" or "", chips and " chips" or "", entries))
				end
			end
		end
	end
end

-- Piezas fijas que nunca deben tocarse.
local function pieces(layout)
	local list = {
		Energy = layout.Energy,
		Upgrade = layout.Upgrade,
		Menu = layout.Menu,
		Status = layout.Status,
		Toasts = toastRect(layout.Toasts),
		Attack = layout.Attack,
		Primary = layout.Abilities[1],
		Right = columnRect(layout.Right),
		SideMenu = layout.SideMenu, -- columna de botones del menú a la derecha (si cabe)
	}
	if not layout.Touch then
		list.Secondary = layout.Abilities[2]
	end
	if layout.ChipsVisible then
		list.Chips = layout.Chips
	end
	return list
end

-- Pares que pueden coincidir por diseño (la columna derecha termina justo encima del combate).
local ALLOWED = {
	["Attack|Chips"] = true, -- los indicadores de mascota van encima del botón de ataque
	["Chips|Primary"] = true,
	["Chips|Secondary"] = true,
}

local function checkSet(label, touch)
	local overlapsFound = {}
	local outside = {}
	eachLayout(label == "táctil" and TOUCH or DESKTOP, touch, function(layout, name)
		local list = pieces(layout)
		local keys = {}
		for key in list do table.insert(keys, key) end
		table.sort(keys)
		for i = 1, #keys do
			local a = list[keys[i]]
			if not HudLayout.inside(a, layout.Screen) then
				table.insert(outside, name .. " " .. keys[i] .. " " .. fmt(a))
			end
			for j = i + 1, #keys do
				local pair = keys[i] .. "|" .. keys[j]
				if not ALLOWED[pair] and overlaps(a, list[keys[j]]) then
					table.insert(overlapsFound, name .. " " .. pair .. " " .. fmt(a) .. " " .. fmt(list[keys[j]]))
				end
			end
		end
	end)
	for _, text in overlapsFound do info("se encima: " .. text) end
	for _, text in outside do info("fuera de pantalla: " .. text) end
	check(label .. ": ninguna pieza fija se encima con otra", #overlapsFound == 0)
	check(label .. ": todo cabe dentro de la pantalla", #outside == 0)
end

checkSet("escritorio", false)
checkSet("táctil", true)

-- Escritorio: el menú queda por debajo del chat de Roblox y la columna derecha cabe entera
-- (aviso de datos + tutorial + al menos una fila de misiones).
do
	local chatBad, rightBad, rowsBad, toastBad = {}, {}, {}, {}
	eachLayout(DESKTOP, false, function(layout, name)
		if overlaps(layout.Menu, layout.Chat) then
			table.insert(chatBad, name .. " " .. fmt(layout.Menu) .. " chat " .. fmt(layout.Chat))
		end
		local s = layout.Scale
		local stack = layout.Right.Y + (76 + 8 + 128 + S.Gap) * s
		if stack + S.TrackerRow * s > layout.Right.Bottom then
			table.insert(rightBad, name)
		end
		if HudLayout.trackerRows(stack, layout.Right.Bottom, s, 4) < 1 then
			table.insert(rowsBad, name)
		end
		if layout.Toasts.MaxItems < 2 or layout.Toasts.W < 230 then
			table.insert(toastBad, name)
		end
	end)
	for _, text in chatBad do info("menú bajo el chat: " .. text) end
	check("escritorio: el menú nunca queda bajo la ventana del chat", #chatBad == 0)
	check("escritorio: aviso de datos + tutorial + 1 fila de misiones caben a la derecha", #rightBad == 0 and #rowsBad == 0)
	check("escritorio: caben al menos 2 avisos a la vez y se leen (ancho >= 230 px)", #toastBad == 0)
end

-- Táctil: el menú y su columna no invaden la franja del joystick ni la tarjeta de mejora;
-- debajo del estado cabe al menos una fila de misiones.
do
	local rowsBad, leftBad = {}, {}
	eachLayout(TOUCH, true, function(layout, name)
		local s = layout.Scale
		local trackerTop = layout.Status.Y + layout.Status.H + S.Gap * s
		local rows = HudLayout.trackerRows(trackerTop, layout.Left.Bottom, s, 4)
		if rows < 1 then
			table.insert(rowsBad, name)
		end
		local tracker = { X = layout.Left.X, Y = trackerTop, W = S.TrackerWidth * s, H = rows * (S.TrackerRow + S.TrackerGap) * s }
		if overlaps(tracker, layout.Upgrade) or overlaps(tracker, layout.Energy) or overlaps(tracker, toastRect(layout.Toasts)) then
			table.insert(leftBad, name .. " " .. fmt(tracker))
		end
	end)
	for _, text in leftBad do info("seguimiento táctil se encima: " .. text) end
	check("táctil: cabe al menos una fila de misiones bajo el menú", #rowsBad == 0)
	check("táctil: el seguimiento no se encima con la mejora, la energía ni los avisos", #leftBad == 0)
end

-- A 1280x720 (sin indicadores de mascota) caben 3 misiones de seguimiento bajo el tutorial: con
-- la columna de botones a la derecha (diseño "HUD Botones") el seguimiento va a su izquierda y
-- termina encima de la fila de abajo.
do
	local layout = HudLayout.compute(Vector2.new(1280, 662), false, { MenuEntries = 7, StatusLines = 2 })
	local stack = layout.Right.Y + (76 + 8 + 128 + S.Gap) * layout.Scale
	check("1280x720: hay columna de botones a la derecha", layout.SideMenu ~= nil)
	check("1280x720: caben 3 filas de seguimiento bajo el aviso de datos y el tutorial", HudLayout.trackerRows(stack, layout.Right.Bottom, layout.Scale, 4) >= 3)
end

-- Avisos con un panel abierto (toastSpot): nunca encima del panel ni de las piezas fijas.
do
	local spotBad, modes = {}, { Top = 0, Bottom = 0, Side = 0, Hidden = 0 }
	for _, list in { { DESKTOP, false }, { TOUCH, true } } do
		eachLayout(list[1], list[2], function(layout, name)
			local s = layout.Scale
			local W, H = layout.Screen.X, layout.Screen.Y
			local t = layout.Toasts
			-- Sin panel, y con un panel pequeño lejos: su sitio de siempre.
			local free = HudLayout.toastSpot(layout, nil)
			local far = HudLayout.toastSpot(layout, { X = 0, Y = H - 10, W = 10, H = 10 })
			if free.Mode ~= "Top" or far.Mode ~= "Top" or free.X ~= t.X or free.Y ~= t.Y then
				table.insert(spotBad, name .. " sin panel no va arriba")
			end
			-- Un panel bajo que tapa la pila (como el de misiones arriba): avisos abajo.
			local short = { X = W / 2 - 200 * s, Y = t.Y, W = 400 * s, H = t.H }
			local low = HudLayout.toastSpot(layout, short)
			if low.Mode ~= "Bottom" and low.Mode ~= "Side" and low.Mode ~= "Hidden" then
				table.insert(spotBad, name .. " panel arriba: " .. low.Mode)
			end
			-- Un panel alto centrado (apertura de huevos): al lado o escondidos, nunca encima.
			local tall = { X = W / 2 - 170 * s, Y = layout.Energy.Y + layout.Energy.H + 8 * s, W = 340 * s, H = H * 0.7 }
			for _, panel in { short, tall } do
				local spot = HudLayout.toastSpot(layout, panel)
				modes[spot.Mode] += 1
				local area
				if spot.Mode == "Bottom" then
					area = { X = spot.X - spot.W / 2, Y = spot.Y - t.H, W = spot.W, H = t.H }
				elseif spot.Mode ~= "Hidden" then
					area = { X = spot.X - spot.W / 2, Y = spot.Y, W = spot.W, H = t.H }
				end
				if area then
					local clash = overlaps(area, panel) and "panel" or nil
					for pieceName, piece in pieces(layout) do
						-- La pila se mueve justo porque su sitio está tapado; abajo puede tocar la
						-- tarjeta de mejora solo si el panel ya la cubre (queda debajo del panel).
						if pieceName ~= "Toasts" and not (pieceName == "Upgrade" and spot.Mode == "Bottom") and overlaps(area, piece) then
							clash = pieceName
						end
					end
					if spot.Mode == "Side" and layout.Chat and overlaps(area, layout.Chat) then
						clash = "chat"
					end
					if not HudLayout.inside(area, layout.Screen) then
						clash = "fuera de pantalla"
					end
					if spot.Mode == "Side" and spot.W < S.ToastMinSide * s - 0.01 then
						clash = "demasiado estrecha"
					end
					if clash then
						table.insert(spotBad, name .. " " .. spot.Mode .. " pisa " .. clash .. " " .. fmt(area))
					end
				end
			end
		end)
	end
	for i = 1, math.min(#spotBad, 8) do info("avisos con panel: " .. spotBad[i]) end
	check("avisos con un panel abierto: nunca encima del panel, de las piezas fijas ni del chat", #spotBad == 0)
	info(("posiciones de avisos con panel: arriba %d, abajo %d, al lado %d, ocultos %d"):format(modes.Top, modes.Bottom, modes.Side, modes.Hidden))
	-- El caso de la captura: visor 1631x565 con el panel del huevo abierto -> al lado.
	local studio = HudLayout.compute(Vector2.new(1631, 565), false, { MenuEntries = 7, StatusLines = 2 })
	local egg = { X = 647, Y = 178, W = 338, H = 360 }
	check("1631x565 con la apertura de huevos: los avisos van al lado del panel", HudLayout.toastSpot(studio, egg).Mode == "Side")
end

-- Cálculos auxiliares.
check("menuSize: 5 entradas = 3 filas de 2 (con sitio para los nombres)", HudLayout.menuSize(5).Y == S.MenuPad + S.MenuPadBottom + 3 * S.Tile + 2 * S.TileGapY and HudLayout.menuSize(5).X == S.MenuPad * 2 + 2 * S.Tile + S.TileGap)
check("menuSize: 6 entradas siguen siendo 3 filas", HudLayout.menuSize(6).Y == HudLayout.menuSize(5).Y)
check("táctil: el menú usa hasta 4 columnas (7 entradas en 2 filas)", HudLayout.menuColumns(7, true) == 4 and HudLayout.menuColumns(3, true) == 3 and HudLayout.menuColumns(7, false) == 2
	and HudLayout.menuSize(7, true).Y == S.MenuPad + S.MenuPadBottom + 2 * S.Tile + S.TileGapY)
check("scale: 1280x660 escritorio = 1", HudLayout.scale(Vector2.new(1280, 660), false) == 1)
check("scale: mínimo táctil 0.6 y escritorio 0.75", HudLayout.scale(Vector2.new(400, 200), true) == 0.6 and HudLayout.scale(Vector2.new(400, 200), false) == 0.75)
check("trackerRows: nunca negativo y con tope", HudLayout.trackerRows(100, 50, 1, 4) == 0 and HudLayout.trackerRows(0, 10000, 1, 4) == 4)

local sample = HudLayout.compute(Vector2.new(1631, 507), false, { MenuEntries = 7, StatusLines = 2 })
info(("1631x507: escala %.2f, menú %s, chat hasta y=%d, columna derecha y=%d..%d, avisos máx %d"):format(sample.Scale, fmt(sample.Menu), math.floor(HudLayout.chatBottom(sample.Screen)), math.floor(sample.Right.Y), math.floor(sample.Right.Bottom), sample.Toasts.MaxItems))

print(failures == 0 and "TODO OK" or (failures .. " FALLOS"))
