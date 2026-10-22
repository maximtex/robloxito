-- Tablas de clasificación de madera al norte de la plaza (LeaderboardConfig), construidas con
-- las piezas de tabla-madera-leaderboard.glb (LeaderboardBoardData): el título en la placa, la
-- página en la viga de arriba, 10 filas (oro, plata y bronce) y abajo la fila del jugador que
-- la mira (la rellena LeaderboardController en cada cliente). En Navidad (SeasonConfig) llevan
-- nieve, guirnalda con luces, coronas, bastones y regalos (ChristmasDecor). Pasan solas por
-- varias páginas:
-- - Servidor: los mejores jugadores de este servidor, al momento (atributos del Player).
-- - Global: los mejores de todos los servidores (OrderedDataStore), leídos cada minuto.
-- - Semana: energía generada esta semana (se reinicia los lunes a las 00:00 UTC).
-- Publicación: cada PublishSeconds (y al salir) se escribe lo de cada jugador con datos
-- cargados, solo si cambió. Los perfiles de prueba o sin cargar nunca se publican.
-- La energía de la semana se suma aquí (producción del cristal y botín de enemigos) y se
-- guarda en el campo Weekly del registro.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)
local GeneratorConfig = require(Shared.Config.GeneratorConfig)
local RebirthLogic = require(Shared.RebirthLogic)
local formatNumber = require(Shared.Util.FormatNumber)
local StudFloor = require(Shared.Util.StudFloor)
local SeasonConfig = require(Shared.Config.SeasonConfig)
local PartFactory = require(script.Parent.Parent.Util.PartFactory)
local GlbParts = require(script.Parent.Parent.Util.GlbParts)
local LeaderboardBoardData = require(script.Parent.Parent.Util.LeaderboardBoardData)
local ChristmasDecor = require(script.Parent.Parent.Util.ChristmasDecor)
local LeaderboardLogic = require(script.Parent.Parent.Util.LeaderboardLogic)
local PlayerDataService = require(script.Parent.PlayerDataService)
local EnergyService = require(script.Parent.EnergyService)

local LeaderboardService = {}

local GOLD = Color3.fromRGB(255, 214, 90)
local TEXT = Color3.fromRGB(252, 240, 214) -- crema sobre las incrustaciones de nogal
local MUTED = Color3.fromRGB(214, 196, 168)
local INK = Color3.fromRGB(70, 40, 22) -- sobre la placa de pino y las medallas
local OUTLINE = Color3.fromRGB(30, 18, 10)
local GLOBAL = LeaderboardConfig.Global

-- Los textos van en una pantalla invisible delante del tablón (de -SCREEN.X/2 a SCREEN.X/2 y
-- de 0 a SCREEN.Y en el marco de la tabla), justo por delante de sus piezas y por detrás de la
-- viga de arriba (la página se escribe en la propia viga).
local SCREEN = Vector2.new(17.5, 21.5)
local SCREEN_Z = -0.85
local PIXELS = 40 -- píxeles por stud
local ROW_TEXT = 0.7 -- alto de los textos de una fila (studs)

type Row = { Rank: TextLabel, Name: TextLabel, Value: TextLabel }
type Board = { Spec: any, Rows: { Row }, Subtitle: TextLabel, Note: TextLabel, Page: number }

local boards: { Board } = {}
-- Mejores globales leídos: { [stat] = { Entries = { {Name, Value} }, Status = "ok" | "offline" | "error" | "loading" } }
local globalTop: { [string]: any } = {}
local nameCache: { [number]: string } = {}
local published: { [Player]: { [string]: number } } = {}
local storeCache: { [string]: any } = {}

-- Sin acceso a las APIs (Studio sin "Enable Studio Access to API Services" o juego sin
-- publicar): la página global lo explica en vez de dar error.
local function isUnavailable(message: string): boolean
	return message:find("StudioAccessToApisNotAllowed", 1, true) ~= nil
		or message:find("Studio access to APIs is not allowed", 1, true) ~= nil
		or message:find("403", 1, true) ~= nil
		or message:find("publish", 1, true) ~= nil
end

local function currentWeek(): number
	return LeaderboardLogic.weekOf(os.time())
end

local function storeName(stat: string): string
	if stat == "Weekly" then
		return GLOBAL.Stores.Weekly .. tostring(currentWeek())
	end
	return GLOBAL.Stores[stat]
end

local function orderedStore(name: string): (any, string?)
	if storeCache[name] then
		return storeCache[name], nil
	end
	local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
	if ok then
		storeCache[name] = result
		return result, nil
	end
	return nil, tostring(result)
end

-- Construcción --------------------------------------------------------------------------------

local function label(parent: Instance, name: string, properties: { [string]: any }): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = TEXT
	text.TextStrokeColor3 = OUTLINE
	text.TextStrokeTransparency = 0.5
	text.Text = ""
	for key, value in properties do
		(text :: any)[key] = value
	end
	text.Parent = parent
	return text
end

-- Coloca un texto de la pantalla centrado en (x, y) del marco de la tabla (x crece hacia la
-- izquierda de quien la mira: el frente es -Z).
local function place(item: GuiObject, x: number, y: number, width: number, height: number)
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Position = UDim2.fromOffset((SCREEN.X / 2 - x) * PIXELS, (SCREEN.Y - y) * PIXELS)
	item.Size = UDim2.fromOffset(width * PIXELS, height * PIXELS)
end

-- Texto sobre una pieza del diseño (LeaderboardBoardData.Anchors). Las medallas y el avatar
-- son discos: su ancho es el diámetro.
local function onAnchor(screen: Instance, anchorName: string, name: string, height: number, properties: { [string]: any }): TextLabel
	local anchor = LeaderboardBoardData.Anchors[anchorName]
	local text = label(screen, name, properties)
	place(text, anchor.Center.X, anchor.Center.Y, anchor.Size.X, height)
	return text
end

local function buildScreen(model: Model, frame: CFrame, beam: BasePart, spec: any): Board
	local part = PartFactory.part(model, "Screen", {
		Size = Vector3.new(SCREEN.X, SCREEN.Y, 0.05),
		CFrame = frame * CFrame.new(0, SCREEN.Y / 2, SCREEN_Z),
		Color = TEXT,
		Material = Enum.Material.SmoothPlastic,
		Solid = false,
	})
	part.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Parent = part

	-- Título en la placa de pino, en tinta de nogal
	onAnchor(gui, "header_plaque", "Title", 1, { Text = spec.Title, TextColor3 = INK, TextStrokeTransparency = 1 })
	local rows = {}
	for index = 1, LeaderboardConfig.Rows do
		local prefix = "row_" .. index
		if not LeaderboardBoardData.Anchors[prefix .. "_name"] then
			break
		end
		local onMedal = index <= 3 -- oro, plata y bronce; las demás son de hierro
		table.insert(rows, {
			Rank = onAnchor(gui, prefix .. "_rank", "Rank" .. index, 0.55, {
				Text = tostring(index),
				TextColor3 = if onMedal then INK else TEXT,
				TextStrokeTransparency = if onMedal then 1 else 0.5,
			}),
			Name = onAnchor(gui, prefix .. "_name", "Name" .. index, ROW_TEXT, { TextXAlignment = Enum.TextXAlignment.Left }),
			Value = onAnchor(gui, prefix .. "_value", "Value" .. index, ROW_TEXT, { TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = GOLD }),
		})
	end
	-- Aviso breve (cuenta atrás de la semana, sin conexión) en el listón de abajo
	local note = onAnchor(gui, "frame_bottom", "Note", 0.6, { TextColor3 = MUTED, TextStrokeTransparency = 1 })

	-- Fila del jugador que mira la tabla: la rellena cada cliente (LeaderboardController)
	local you = Instance.new("Frame")
	you.Name = "You"
	you.Size = UDim2.fromScale(1, 1)
	you.BackgroundTransparency = 1
	you.Parent = gui
	local avatarAnchor = LeaderboardBoardData.Anchors.you_avatar
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundTransparency = 1
	avatar.Image = ""
	place(avatar, avatarAnchor.Center.X, avatarAnchor.Center.Y, avatarAnchor.Size.X, avatarAnchor.Size.X)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = avatar
	avatar.Parent = you
	onAnchor(you, "you_name", "Name", 0.8, { Text = "Tú", TextXAlignment = Enum.TextXAlignment.Left })
	onAnchor(you, "you_value", "Value", 0.8, { TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = GOLD })

	-- La página que se ve, en dorado sobre la viga de arriba
	local beamGui = Instance.new("SurfaceGui")
	beamGui.Name = "Page"
	beamGui.Face = Enum.NormalId.Front
	beamGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	beamGui.PixelsPerStud = PIXELS
	beamGui.LightInfluence = 0
	beamGui.MaxDistance = 160
	beamGui.Parent = beam
	local subtitle = label(beamGui, "Subtitle", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.8),
		Text = LeaderboardConfig.PageTitles.Server,
		TextColor3 = GOLD,
	})
	return { Spec = spec, Rows = rows, Subtitle = subtitle, Note = note, Page = 1 }
end

local function buildBoard(parent: Instance, spec: any)
	local base = GeneratorConfig.Position
	local x, z = base.X + spec.Position.X, base.Z + spec.Position.Y
	local y = base.Y + StudFloor.BaseTop + StudFloor.raiseAt(x, z)
	local toward = Vector3.new(base.X + LeaderboardConfig.FaceToward.X, y, base.Z + LeaderboardConfig.FaceToward.Y)
	local frame = CFrame.lookAt(Vector3.new(x, y, z), toward)
	local model = Instance.new("Model")
	model.Name = "Leaderboard_" .. spec.Id
	model:SetAttribute("Attribute", spec.Attribute) -- lo que muestra la fila del jugador
	local parts = GlbParts.build(model, LeaderboardBoardData.Parts, frame)
	model.PrimaryPart = parts.base_plinth
	if SeasonConfig.Christmas then
		ChristmasDecor.leaderboard(model, parts, frame)
	end
	table.insert(boards, buildScreen(model, frame, parts.top_beam, spec))
	model.Parent = parent
end

-- Páginas -----------------------------------------------------------------------------------

-- Solo el número: la tabla ya lleva su icono dorado delante de cada valor
local function valueText(stat: string, value: number): string
	if stat == "Rebirths" then
		return tostring(math.floor(value))
	end
	return formatNumber(value)
end

local function countdownText(): string
	local remaining = math.max(0, LeaderboardLogic.weekEndsAt(currentWeek()) - os.time())
	local days = math.floor(remaining / 86400)
	local hours = math.floor((remaining % 86400) / 3600)
	if days > 0 then
		return ("Se reinicia en %d d %d h"):format(days, hours)
	end
	return ("Se reinicia en %d h %02d min"):format(hours, math.floor((remaining % 3600) / 60))
end

-- Entradas, estadística y aviso de la página actual de una tabla.
local function pageData(board: Board): ({ any }, string, string)
	local spec = board.Spec
	local page = spec.Pages[board.Page] or "Server"
	if page == "Server" then
		local entries = {}
		for _, player in Players:GetPlayers() do
			table.insert(entries, {
				Name = player.DisplayName,
				Value = player:GetAttribute(spec.Attribute),
				Tie = if spec.Tiebreak then player:GetAttribute(spec.Tiebreak) else nil,
			})
		end
		return LeaderboardLogic.rank(entries, LeaderboardConfig.Rows), spec.Attribute, ""
	end
	local stat = if page == "Weekly" then "Weekly" else spec.Global
	local data = globalTop[stat]
	local note = if page == "Weekly" then countdownText() else ""
	if not data or data.Status == "loading" then
		return {}, stat, "Cargando…"
	elseif data.Status == "offline" then
		return {}, stat, "Se ve en el juego publicado"
	elseif data.Status == "error" and #data.Entries == 0 then
		return {}, stat, "Sin conexión por ahora"
	end
	return data.Entries, stat, note
end

local function render(board: Board)
	local spec = board.Spec
	local page = spec.Pages[board.Page] or "Server"
	local entries, stat, note = pageData(board)
	board.Subtitle.Text = LeaderboardConfig.PageTitles[page] or ""
	board.Note.Text = note
	for index, row in board.Rows do
		local entry = entries[index]
		row.Name.Text = if entry then entry.Name else "—"
		row.Name.TextColor3 = if entry then TEXT else MUTED
		row.Value.Text = if entry then valueText(if stat == "Rebirths" then "Rebirths" else "Energy", entry.Value) else ""
	end
end

local function refresh()
	for _, board in boards do
		render(board)
	end
end

-- Global: publicar y leer ------------------------------------------------------------------

local function publishedValues(profile: PlayerDataService.Profile): { [string]: number? }
	local data = profile.PetData
	local quests = data.Quests
	return {
		Energy = LeaderboardLogic.storeValue(type(quests) == "table" and type(quests.Stats) == "table" and quests.Stats.EnergyEarned or 0),
		Rebirths = LeaderboardLogic.storeValue(RebirthLogic.count(data.Rebirth)),
		Weekly = LeaderboardLogic.storeValue(LeaderboardLogic.weeklyValue(data.Weekly, currentWeek())),
	}
end

local function publish(player: Player, leavingProfile: PlayerDataService.Profile?)
	local profile = leavingProfile or PlayerDataService.get(player)
	-- Solo datos de verdad: nada de perfiles de prueba, sin cargar o con la carga fallida.
	if not profile or profile.DataState ~= "Loaded" or profile.Sandbox then
		return
	end
	local last = published[player]
	if not last then
		last = {}
		published[player] = last
	end
	local week = currentWeek()
	for stat, value in publishedValues(profile) do
		local lastKey = if stat == "Weekly" then "Weekly" .. week else stat
		if value and value > 0 and last[lastKey] ~= value then
			local store = orderedStore(storeName(stat))
			if store then
				local ok, err = pcall(store.SetAsync, store, tostring(player.UserId), value)
				if ok then
					last[lastKey] = value
				elseif not isUnavailable(tostring(err)) then
					warn("[LeaderboardService] No se pudo publicar " .. stat .. ": " .. tostring(err))
				end
			end
		end
	end
end

-- Nombres de usuario de una lista de UserIds (con caché).
local function resolveNames(userIds: { number })
	local missing = {}
	for _, userId in userIds do
		if not nameCache[userId] then
			local player = Players:GetPlayerByUserId(userId)
			if player then
				nameCache[userId] = player.DisplayName
			else
				table.insert(missing, userId)
			end
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, missing)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info) == "table" and type(info.Id) == "number" then
				nameCache[info.Id] = if type(info.DisplayName) == "string" and info.DisplayName ~= "" then info.DisplayName else info.Username
			end
		end
	end
	for _, userId in missing do
		if not nameCache[userId] then
			local nameOk, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
			nameCache[userId] = if nameOk and type(name) == "string" then name else ("Jugador " .. userId)
		end
	end
end

local function fetch(stat: string)
	local store, openError = orderedStore(storeName(stat))
	if not store then
		globalTop[stat] = { Entries = {}, Status = if openError and isUnavailable(openError) then "offline" else "error" }
		return
	end
	local ok, pages = pcall(store.GetSortedAsync, store, false, LeaderboardConfig.Rows)
	if not ok then
		local previous = globalTop[stat]
		globalTop[stat] = {
			Entries = if previous then previous.Entries else {},
			Status = if isUnavailable(tostring(pages)) then "offline" else "error",
		}
		return
	end
	local pageOk, page = pcall(pages.GetCurrentPage, pages)
	if not pageOk or type(page) ~= "table" then
		globalTop[stat] = { Entries = {}, Status = "error" }
		return
	end
	local ids = {}
	for _, item in page do
		local userId = tonumber(item.key)
		if userId then
			table.insert(ids, userId)
		end
	end
	resolveNames(ids)
	local entries = {}
	for _, item in page do
		local userId = tonumber(item.key)
		if userId and type(item.value) == "number" then
			table.insert(entries, { Name = nameCache[userId] or ("Jugador " .. userId), Value = item.value })
		end
	end
	globalTop[stat] = { Entries = LeaderboardLogic.rank(entries, LeaderboardConfig.Rows), Status = "ok" }
end

-- Arranque ------------------------------------------------------------------------------------

function LeaderboardService.start()
	PartFactory.removeExisting(Workspace, LeaderboardConfig.ModelName)
	local folder = Instance.new("Folder")
	folder.Name = LeaderboardConfig.ModelName
	for _, spec in LeaderboardConfig.Boards do
		buildBoard(folder, spec)
	end
	folder.Parent = Workspace
	for _, stat in { "Energy", "Rebirths", "Weekly" } do
		globalTop[stat] = { Entries = {}, Status = "loading" }
	end
	refresh()

	-- Energía de la semana: la producción (los enemigos sueltan dinero, no energía).
	EnergyService.onProduced(function(player, amount)
		local profile = PlayerDataService.get(player)
		if profile and PlayerDataService.isPetDataReady(profile) then
			LeaderboardLogic.addWeekly(profile.PetData.Weekly, currentWeek(), amount)
		end
	end)

	-- Página del servidor al momento; las páginas pasan solas.
	task.spawn(function()
		local elapsed = 0
		while true do
			task.wait(LeaderboardConfig.RefreshSeconds)
			elapsed += LeaderboardConfig.RefreshSeconds
			if elapsed >= LeaderboardConfig.PageSeconds then
				elapsed = 0
				for _, board in boards do
					board.Page = (board.Page % #board.Spec.Pages) + 1
				end
			end
			refresh()
		end
	end)

	-- Leer los mejores de todo el juego. Sin acceso a las APIs (Studio) se deja de intentar:
	-- no va a cambiar en esta sesión y así no se llena la consola de avisos.
	task.spawn(function()
		while true do
			local offline = false
			for _, stat in { "Energy", "Rebirths", "Weekly" } do
				fetch(stat)
				offline = offline or globalTop[stat].Status == "offline"
			end
			refresh()
			if offline then
				return
			end
			task.wait(GLOBAL.FetchSeconds)
		end
	end)

	-- Publicar lo de cada jugador (repartido en el tiempo).
	task.spawn(function()
		while true do
			task.wait(GLOBAL.PublishSeconds)
			for _, player in Players:GetPlayers() do
				task.spawn(publish, player)
				task.wait(0.5)
			end
		end
	end)
	PlayerDataService.onLeaving(function(player, profile)
		publish(player, profile)
		published[player] = nil
	end)
end

return LeaderboardService
