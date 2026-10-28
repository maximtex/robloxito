-- Dónde va cada pieza del HUD (cálculo puro, sin servicios; lo prueba la suite "hudlayout"
-- en muchos tamaños de pantalla, de escritorio y táctiles, para que nada se encime).
-- Todo en píxeles del ScreenGui (ya sin la barra superior de Roblox) y con una sola escala
-- para todo el HUD.
--
-- Escritorio                                   Solo táctil (móvil, tableta)
--   chat de Roblox   energía      avisos        menú      energía      tutorial
--   menú (2 col.)    avisos       tutorial      estado    avisos
--   estado                        misiones      misiones               habilidades
--                    mejora       habilidades   joystick  mejora       ataque/salto
--
-- - Menú: barra compacta de iconos (2 columnas). En escritorio, a media altura por DEBAJO
--   de la ventana del chat; en táctil arriba a la izquierda (allí el chat empieza cerrado).
-- - Columna derecha: aviso de datos, tutorial y (escritorio) seguimiento de misiones, hasta
--   justo encima de los botones de combate.
-- - Botones del menú a la derecha (escritorio, MenuBar): Misiones, Premios y Tienda en
--   columna pegada al borde, entre el cartel de la zona y el combate (SideMenu). El
--   seguimiento de misiones queda a su izquierda. En táctil, y en ventanas tan estrechas
--   que el seguimiento pisaría la energía, van en la fila de abajo (sin SideMenu).
-- - Avisos: una sola pila bajo la tarjeta de energía (y bajo la barra del jefe si se ve),
--   con tantas filas como quepan antes de la tarjeta de mejora.

local HudLayout = {}

export type Rect = { X: number, Y: number, W: number, H: number }

local SIZES = {
	Margin = 12, -- separación con el borde superior
	Edge = 16, -- separación con los bordes laterales
	Gap = 12, -- separación entre piezas
	Diamonds = Vector2.new(330, 112), -- barras de energía y producción (estilo simulador)
	Upgrade = Vector2.new(420, 212),
	UpgradeBottom = 24,
	-- Menú: azulejos cuadrados con icono dibujado en una cuadrícula de 2 columnas; el
	-- nombre asoma por debajo de cada azulejo (por eso hay más hueco entre filas).
	Tile = 64,
	TileGap = 10,
	TileGapY = 16,
	MenuPad = 4,
	MenuPadBottom = 12, -- el nombre de la última fila
	MenuColumns = 2,
	MenuColumnsTouch = 4, -- en táctil el menú va arriba a la izquierda: más ancho y bajo
	MenuCenter = 0.55, -- escritorio: centro del menú (fracción de la altura)
	StatusWidth = 230,
	StatusLine = 20,
	StatusGap = 4,
	-- Columna derecha y seguimiento
	RightWidth = 330,
	TrackerWidth = 300,
	TrackerRow = 50,
	TrackerGap = 6,
	-- Avisos (más pequeños y como mucho 3 a la vez: antes, 4 tarjetas de 420 px tapaban el
	-- centro de la pantalla al completar misiones o logros; pruebas con amigos)
	ToastWidth = 360,
	Toast = 40,
	ToastTitled = 70,
	ToastLine = 26,
	ToastGap = 6,
	MaxToasts = 3,
	ToastMinSide = 200, -- ancho mínimo para poner los avisos al lado de un panel
	BossReserve = 62, -- barra del jefe (54) y su separación
	-- Combate (CombatController / AbilityController: deben coincidir con estos números)
	Attack = 96,
	AttackEdge = 20,
	AttackBottom = 24,
	Ability = 84,
	AbilityGap = 14,
	AbilityTouchLift = 76,
	AbilityTouchGap = 26,
	Chips = Vector2.new(140, 60), -- indicadores de mascotas (dragón, tortuga) con su rótulo debajo
	ChipLabel = 18,
	ChipsGap = 12, -- separación sobre el botón de ataque
	-- Botones del menú (MenuBar): un 30 % más grandes que el resto del HUD, como en el
	-- diseño (con la escala del HUD en 0,77 quedan a 76 px, igual que en el diseño).
	MenuBoost = 1.3,
	-- Columna de botones del menú a la derecha (MenuBar; solo escritorio)
	SideTile = 76,
	SideGap = 18,
	SideCount = 3, -- Misiones, Premios, Tienda
	SideEdge = 24, -- separación con el borde derecho
	SideTop = 108, -- borde superior (a escala 1), como en el diseño
	SideTopMin = 60, -- nunca encima del cartel de la zona (arriba a la derecha)
	SideLabel = 7, -- el nombre asoma por debajo del último azulejo
	-- Elementos de Roblox (no escalan con el HUD)
	ChatTop = 4,
	ChatShare = 0.25, -- la ventana del chat mide ~1/4 de la altura
	ChatExtra = 70, -- barra de escribir y bordes
	ChatWidth = 480,
	ThumbstickShare = 0.3, -- táctil: franja inferior izquierda donde descansa el pulgar
}
HudLayout.Sizes = SIZES

HudLayout.Reference = Vector2.new(1280, 660) -- 1280x720 reales (sin la barra superior)
HudLayout.MinScaleDesktop = 0.75
HudLayout.MinScaleTouch = 0.6
HudLayout.MaxScale = 1.5
-- Tamaño de la interfaz que elige el jugador en ⚙️ Ajustes (SettingsLogic.HudScales):
-- multiplica la escala de la pantalla y puede bajar de MinScale (para eso se elige).
HudLayout.UserScale = 1
HudLayout.MinUserScale = 0.5
HudLayout.MaxUserScale = 1
HudLayout.Floor = 0.4 -- nunca más pequeño que esto (texto ilegible)

local function rect(x: number, y: number, w: number, h: number): Rect
	return { X = x, Y = y, W = w, H = h }
end

-- Escala del HUD para una pantalla. `user`: el tamaño elegido (por defecto, UserScale).
function HudLayout.scale(screen: Vector2, touch: boolean, user: number?): number
	local minScale = if touch then HudLayout.MinScaleTouch else HudLayout.MinScaleDesktop
	local ref = HudLayout.Reference
	local base = math.clamp(math.min(screen.X / ref.X, screen.Y / ref.Y), minScale, HudLayout.MaxScale)
	local factor = math.clamp(user or HudLayout.UserScale, HudLayout.MinUserScale, HudLayout.MaxUserScale)
	return math.clamp(base * factor, HudLayout.Floor, HudLayout.MaxScale)
end

-- Cambia el tamaño elegido (lo hace UserScale en el cliente; las pruebas lo ponen a mano).
function HudLayout.setUserScale(value: number)
	if type(value) == "number" and value == value then
		HudLayout.UserScale = math.clamp(value, HudLayout.MinUserScale, HudLayout.MaxUserScale)
	else
		HudLayout.UserScale = 1
	end
end

-- Tamaño del menú (sin escalar) para un número de entradas.
function HudLayout.menuColumns(entries: number, touch: boolean?): number
	if touch then
		return math.clamp(entries, 1, SIZES.MenuColumnsTouch)
	end
	return SIZES.MenuColumns
end

function HudLayout.menuSize(entries: number, touch: boolean?): Vector2
	local columns = HudLayout.menuColumns(entries, touch)
	local rows = math.max(1, math.ceil(entries / columns))
	local width = SIZES.MenuPad * 2 + columns * SIZES.Tile + (columns - 1) * SIZES.TileGap
	local height = SIZES.MenuPad + SIZES.MenuPadBottom + rows * SIZES.Tile + (rows - 1) * SIZES.TileGapY
	return Vector2.new(width, height)
end

function HudLayout.statusHeight(lines: number): number
	if lines <= 0 then
		return 0
	end
	return SIZES.StatusGap + lines * SIZES.StatusLine + (lines - 1) * SIZES.StatusGap
end

-- Borde inferior de la ventana del chat de Roblox (escritorio, arriba a la izquierda).
function HudLayout.chatBottom(screen: Vector2): number
	return SIZES.ChatTop + screen.Y * SIZES.ChatShare + SIZES.ChatExtra
end

function HudLayout.overlaps(a: Rect, b: Rect): boolean
	return a.X < b.X + b.W and b.X < a.X + a.W and a.Y < b.Y + b.H and b.Y < a.Y + a.H
end

function HudLayout.inside(a: Rect, screen: Vector2): boolean
	return a.X >= 0 and a.Y >= 0 and a.X + a.W <= screen.X + 0.01 and a.Y + a.H <= screen.Y + 0.01
end

export type Options = {
	MenuEntries: number?,
	StatusLines: number?,
	BossBar: boolean?,
	Chips: boolean?, -- indicadores de mascotas visibles sobre el botón de ataque
	UserScale: number?, -- tamaño elegido (por defecto, HudLayout.UserScale)
}

-- Regiones del HUD para una pantalla. `touch` = solo táctil (sin teclado).
function HudLayout.compute(screen: Vector2, touch: boolean, options: Options?): any
	local opts: Options = options or {}
	local s = HudLayout.scale(screen, touch, opts.UserScale)
	local W, H = screen.X, screen.Y
	local layout: any = { Scale = s, Touch = touch, Screen = screen }

	-- Centro: energía arriba y mejora abajo.
	local diamonds = rect(W / 2 - SIZES.Diamonds.X * s / 2, SIZES.Margin, SIZES.Diamonds.X * s, SIZES.Diamonds.Y * s)
	layout.Diamonds = diamonds
	local upgradeH = SIZES.Upgrade.Y * s
	layout.Upgrade = rect(W / 2 - SIZES.Upgrade.X * s / 2, H - SIZES.UpgradeBottom - upgradeH, SIZES.Upgrade.X * s, upgradeH)

	-- Combate (abajo a la derecha; en táctil las habilidades suben a media altura).
	local attackSize = SIZES.Attack * s
	local attack = rect(W - SIZES.AttackEdge - attackSize, H - SIZES.AttackBottom - attackSize, attackSize, attackSize)
	layout.Attack = attack
	-- Indicadores de mascotas: encima del ataque en escritorio; a media altura en táctil.
	local chipsH = (SIZES.Chips.Y + SIZES.ChipLabel) * s
	local chipsBottom = if touch then H / 2 else attack.Y - SIZES.ChipsGap
	layout.Chips = rect(W - SIZES.AttackEdge - SIZES.Chips.X * s, chipsBottom - SIZES.Chips.Y * s, SIZES.Chips.X * s, chipsH)
	layout.ChipsVisible = opts.Chips == true
	local ability = SIZES.Ability * s
	if touch then
		local primaryBottom = H / 2 - SIZES.AbilityTouchLift * s
		local secondaryBottom = H / 2 - (SIZES.AbilityTouchLift + SIZES.Ability + SIZES.AbilityTouchGap) * s
		layout.Abilities = {
			rect(W - SIZES.AttackEdge - ability, primaryBottom - ability, ability, ability),
			rect(W - SIZES.AttackEdge - ability, secondaryBottom - ability, ability, ability),
		}
	else
		local primaryRight = W - (SIZES.AttackEdge + (SIZES.Attack + SIZES.AbilityGap) * s)
		local secondaryRight = W - (SIZES.AttackEdge + (SIZES.Attack + SIZES.AbilityGap + SIZES.Ability + SIZES.AbilityGap) * s)
		layout.Abilities = {
			rect(primaryRight - ability, H - SIZES.AttackBottom - ability, ability, ability),
			rect(secondaryRight - ability, H - SIZES.AttackBottom - ability, ability, ability),
		}
	end

	-- Menú y su columna (izquierda).
	local menu = HudLayout.menuSize(opts.MenuEntries or 5, touch)
	local menuW, menuH = menu.X * s, menu.Y * s
	local statusH = HudLayout.statusHeight(opts.StatusLines or 2) * s
	local menuTop: number
	local leftBottom: number
	if touch then
		menuTop = SIZES.Margin
		leftBottom = H * (1 - SIZES.ThumbstickShare)
	else
		menuTop = H * SIZES.MenuCenter - menuH / 2
		menuTop = math.max(menuTop, HudLayout.chatBottom(screen) + SIZES.Gap)
		-- Si no cabe bajo el chat, se prefiere quedar entero en pantalla.
		menuTop = math.min(menuTop, H - SIZES.Margin - menuH - statusH)
		menuTop = math.max(menuTop, SIZES.Margin)
		leftBottom = H - SIZES.Margin
	end
	layout.Menu = rect(SIZES.Edge, menuTop, menuW, menuH)
	layout.Status = rect(SIZES.Edge, menuTop + menuH, SIZES.StatusWidth * s, statusH)
	layout.Left = { X = SIZES.Edge, Y = menuTop, Bottom = leftBottom, W = math.max(menuW, SIZES.StatusWidth * s, SIZES.TrackerWidth * s) }
	layout.Chat = if touch then nil else rect(0, 0, SIZES.ChatWidth, HudLayout.chatBottom(screen))

	-- Columna derecha (de arriba hacia abajo).
	local rightW = SIZES.RightWidth * s
	local rightBottom: number
	if touch then
		rightBottom = layout.Abilities[1].Y - SIZES.Gap
	else
		-- Los indicadores de mascotas solo cuentan cuando se ven (CombatController lo avisa).
		rightBottom = math.min(attack.Y, layout.Abilities[1].Y, if opts.Chips then layout.Chips.Y else math.huge) - SIZES.Gap
	end
	local rightX = W - SIZES.Edge - rightW
	-- Escritorio: botones del menú en columna pegada al borde derecho, entre el cartel de la
	-- zona y el combate. El seguimiento de misiones (columna derecha) va a su izquierda.
	local menuScale = math.min(s * SIZES.MenuBoost, HudLayout.MaxScale)
	layout.MenuScale = menuScale
	if not touch then
		local sideScale = menuScale
		local sideW = SIZES.SideTile * sideScale
		local sideH = (SIZES.SideCount * SIZES.SideTile + (SIZES.SideCount - 1) * SIZES.SideGap + SIZES.SideLabel) * sideScale
		local top = SIZES.SideTop * sideScale
		if top + sideH > rightBottom then
			top = math.max(SIZES.SideTopMin * s, rightBottom - sideH)
			if top + sideH > rightBottom then
				-- No cabe ni subiéndola: se encoge hasta caber.
				sideScale = sideScale * math.max(rightBottom - top, 1) / sideH
				sideH = rightBottom - top
				sideW = SIZES.SideTile * sideScale
			end
		end
		local sideX = W - SIZES.SideEdge * s - sideW
		local shiftedX = math.min(rightX, sideX - SIZES.Gap * s - rightW)
		-- Solo si la columna derecha corrida aún no pisa la tarjeta de energía; si no (ventanas
		-- estrechas), sin columna de botones: MenuBar los pone todos en la fila de abajo.
		if shiftedX >= diamonds.X + diamonds.W then
			layout.SideMenu = { X = sideX, Y = top, W = sideW, H = sideH, Scale = sideScale }
			rightX = shiftedX
		end
	end
	-- En ventanas estrechas la columna llega a la altura de la tarjeta de mejora: para encima.
	if rightX < layout.Upgrade.X + layout.Upgrade.W then
		rightBottom = math.min(rightBottom, layout.Upgrade.Y - SIZES.Gap)
	end
	-- Inset: distancia de su borde derecho al de la pantalla (HudDock la ancla ahí).
	layout.Right = { X = rightX, Y = SIZES.Margin, W = rightW, Bottom = rightBottom, Inset = W - rightX - rightW }
	layout.TrackerColumn = if touch then "Left" else "Right"

	-- Pila de avisos (centrada bajo la energía y la barra del jefe).
	-- Ancho: el de la tarjeta, sin pisar las columnas laterales en ventanas estrechas.
	local toastTop = diamonds.Y + diamonds.H + SIZES.Gap + (if opts.BossBar then SIZES.BossReserve * s else 0)
	local toastLimit = layout.Upgrade.Y - SIZES.Gap
	local sideLimit = math.min(layout.Right.X - SIZES.Gap - W / 2, W / 2 - (layout.Status.X + layout.Status.W) - SIZES.Gap)
	local toastW = math.min(SIZES.ToastWidth * s, 2 * sideLimit)
	local slot = (SIZES.Toast + SIZES.ToastGap) * s
	local gap = SIZES.ToastGap * s
	local titledExtra = (SIZES.ToastTitled - SIZES.Toast) * s
	local fitTitled = math.floor((toastLimit - toastTop - titledExtra + gap) / slot)
	local fitPlain = math.floor((toastLimit - toastTop + gap) / slot)
	local allowTitled = fitTitled >= 1
	local maxToasts = math.clamp(if allowTitled then fitTitled else fitPlain, 1, SIZES.MaxToasts)
	layout.Toasts = {
		X = W / 2,
		Y = toastTop,
		W = toastW,
		MaxItems = maxToasts,
		-- Si no cabe una tarjeta con título (móvil con la barra del jefe), el título va en línea.
		AllowTitled = allowTitled,
		H = (if allowTitled then titledExtra else 0) + maxToasts * slot - gap,
	}
	return layout
end

-- Dónde va la pila de avisos con un panel abierto (`panel`: su rectángulo en pantalla):
-- 1. "Top": su sitio de siempre, si el panel no lo tapa;
-- 2. "Bottom": abajo del todo, si ahí no estorba (Y = borde INFERIOR de la pila);
-- 3. "Side": al lado del panel, en el hueco más ancho entre el panel y las columnas
--    (y el chat), a la altura de su borde superior;
-- 4. "Hidden": no hay hueco; los avisos esperan a que se cierre el panel.
-- Así un panel alto (la apertura de huevos) nunca queda con avisos encima de sus botones.
function HudLayout.toastSpot(layout: any, panel: Rect?): any
	local t = layout.Toasts
	local s = layout.Scale
	local screen = layout.Screen
	local top = rect(t.X - t.W / 2, t.Y, t.W, t.H)
	if not panel or not HudLayout.overlaps(top, panel) then
		return { Mode = "Top", X = t.X, Y = t.Y, W = t.W }
	end
	local bottomY = screen.Y - SIZES.Margin
	if not HudLayout.overlaps(rect(t.X - t.W / 2, bottomY - t.H, t.W, t.H), panel) then
		return { Mode = "Bottom", X = t.X, Y = bottomY, W = t.W }
	end
	local gap = SIZES.Gap * s
	local y = math.clamp(panel.Y, SIZES.Margin, math.max(SIZES.Margin, screen.Y - SIZES.Margin - t.H))
	local leftEdge = layout.Left.X + layout.Left.W + gap
	if layout.Chat and y < layout.Chat.Y + layout.Chat.H then
		leftEdge = math.max(leftEdge, layout.Chat.X + layout.Chat.W + gap)
	end
	local rightEdge = layout.Right.X - gap
	local leftGap = panel.X - gap - leftEdge
	local rightGap = rightEdge - (panel.X + panel.W + gap)
	local useRight = rightGap >= leftGap
	local room = if useRight then rightGap else leftGap
	if room < SIZES.ToastMinSide * s then
		return { Mode = "Hidden", X = t.X, Y = t.Y, W = t.W }
	end
	local w = math.min(t.W, room)
	local start = if useRight then panel.X + panel.W + gap else leftEdge
	return { Mode = "Side", X = start + room / 2, Y = y, W = w }
end

-- Filas de seguimiento que caben entre `top` (borde superior de la lista) y `bottom`.
function HudLayout.trackerRows(top: number, bottom: number, scale: number, maxRows: number): number
	local slot = (SIZES.TrackerRow + SIZES.TrackerGap) * scale
	local rows = math.floor((bottom - top + SIZES.TrackerGap * scale) / slot)
	return math.clamp(rows, 0, maxRows)
end

return HudLayout
