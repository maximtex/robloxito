-- Aviso del estado de los datos guardados (solo presentación; lo decide el servidor con los
-- atributos DataStatus y SaveError). Una tarjeta pequeña arriba a la derecha que solo
-- aparece cuando hay algo que contar:
-- - Carga lenta (más de 6 s): "Cargando tus datos…".
-- - Sin DataStore (p. ej. Studio sin acceso a la API): esta sesión no se guardará.
-- - Carga fallida: los datos guardados están a salvo, pero esta sesión no se guardará.
-- - Guardado fallido: se reintenta solo; al conseguirlo, "Progreso guardado" un momento.
-- - Modo prueba del tutorial (atributo TestMode, solo Studio): siempre visible.
-- Se puede cerrar (✕) salvo mientras carga y en el modo prueba.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared").Constants)
local Theme = require(script.Parent.Parent.UI.Theme)
local UiKit = require(script.Parent.Parent.UI.UiKit)

local THEME = Theme.Colors
local FONTS = Theme.Fonts
local CARD_SIZE = Vector2.new(330, 76)
local SLOW_LOAD_SECONDS = 6

local MESSAGES = {
	-- Tall: título en dos líneas (el texto completo debe verse siempre).
	TestMode = { Title = "🧪 Modo prueba del tutorial: el progreso no se guarda", Body = "Perfil temporal de Studio. Tu partida real no se lee ni se modifica.", Color = THEME.Gold, Tall = true },
	Loading = { Title = "Cargando tus datos…", Body = "Tu progreso aparecerá en unos segundos.", Color = THEME.Muted },
	Unavailable = { Title = "Modo sin guardado", Body = "El guardado no está disponible: el progreso de esta sesión no se guardará.", Color = THEME.Gold },
	Failed = { Title = "No se pudieron cargar tus datos", Body = "Tu progreso guardado está a salvo, pero esta sesión no se guardará. Vuelve a entrar más tarde.", Color = THEME.Error },
	SaveError = { Title = "No se pudo guardar", Body = "Se reintentará automáticamente. No salgas todavía si puedes.", Color = THEME.Error },
	Saved = { Title = "Progreso guardado ✓", Body = "", Color = THEME.BuyHighlight },
}

local DataStatusController = {}

function DataStatusController.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("DataStatusHud")
	if existing then
		existing:Destroy()
	end
	local screenGui = UiKit.create("ScreenGui", {
		Name = "DataStatusHud",
		ResetOnSpawn = false,
		DisplayOrder = 4, -- por encima del HUD de combate, por debajo de los paneles
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, nil)
	local card, cardScale = UiKit.panel(screenGui, "Card", CARD_SIZE, Vector2.new(1, 0), UDim2.new(1, -16, 0, 12))
	card.Visible = false
	local stroke = card:FindFirstChildOfClass("UIStroke")
	local title = UiKit.text(card, "Title", {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -60, 0, 22),
		Font = FONTS.Display,
		TextSize = 18,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local body = UiKit.text(card, "Body", {
		Position = UDim2.fromOffset(16, 34),
		Size = UDim2.new(1, -32, 0, 34),
		Font = FONTS.Light,
		TextSize = 14,
		TextColor3 = THEME.Muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local close = UiKit.button(card, "Close", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = THEME.Inset,
		TextSize = 15,
		Text = "✕",
	})
	screenGui.Parent = playerGui
	UiKit.bindScale(screenGui, { cardScale })

	local dismissed: { [string]: boolean } = {}
	local shownKey: string? = nil
	local loadingSince = os.clock()
	local hadSaveError = false
	local savedToken = 0

	local function show(key: string?)
		shownKey = key
		local message = key and MESSAGES[key]
		if not message or dismissed[key :: string] then
			card.Visible = false
			return
		end
		title.Text = message.Title
		title.TextColor3 = message.Color
		body.Text = message.Body
		body.Visible = message.Body ~= ""
		-- Mensajes altos: título en dos líneas a todo el ancho y el texto debajo.
		local extra = if message.Tall then 24 else 0
		title.Size = if message.Tall then UDim2.new(1, -32, 0, 46) else UDim2.new(1, -60, 0, 22)
		body.Position = UDim2.fromOffset(16, 34 + extra)
		card.Size = UDim2.fromOffset(CARD_SIZE.X, (if message.Body ~= "" then CARD_SIZE.Y else 42) + extra)
		if stroke then
			stroke.Color = message.Color
		end
		close.Visible = key ~= "Loading" and key ~= "TestMode"
		card.Visible = true
	end

	local function refresh()
		-- El modo prueba se muestra siempre (y no se puede cerrar): nunca debe confundirse
		-- con la partida real.
		if player:GetAttribute(Constants.Attributes.TestMode) == true then
			dismissed.TestMode = nil
			show("TestMode")
			return
		end
		local status = player:GetAttribute(Constants.Attributes.DataStatus)
		local saveError = player:GetAttribute(Constants.Attributes.SaveError) == true
		if saveError then
			hadSaveError = true
			dismissed.SaveError = nil -- un fallo nuevo se vuelve a mostrar
			show("SaveError")
		elseif hadSaveError and status == "Loaded" then
			-- Recuperado: confirmarlo un momento.
			hadSaveError = false
			savedToken += 1
			local token = savedToken
			show("Saved")
			task.delay(3, function()
				if savedToken == token and shownKey == "Saved" then
					show(nil)
				end
			end)
		elseif status == "Failed" or status == "Unavailable" then
			show(status)
		elseif (status == nil or status == "Loading") and os.clock() - loadingSince >= SLOW_LOAD_SECONDS then
			show("Loading")
		elseif shownKey ~= "Saved" then
			show(nil)
		end
	end

	close.Activated:Connect(function()
		if shownKey then
			dismissed[shownKey] = true
		end
		show(nil)
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.DataStatus):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.SaveError):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.TestMode):Connect(refresh)
	-- Si la carga tarda, se avisa a los SLOW_LOAD_SECONDS (una sola comprobación diferida).
	task.delay(SLOW_LOAD_SECONDS, refresh)
	refresh()
end

return DataStatusController
