-- Animaciones de cada estilo de pelea (StyleConfig.Styles.<estilo>.Animations, publicadas en
-- Roblox), solo en TU personaje: Roblox enseña a los demás las animaciones que tu cliente pone
-- en tu personaje.
-- - Guardia (se repite) mientras llevas ese estilo: el arma medio levantada, la espada, los
--   puños en guardia o el bastón.
-- - Armas: Apuntar (las dos manos en el arma) con el clic derecho y un rato después de cada
--   disparo, Disparo (retroceso) y Recarga (al ritmo de la recarga del arma).
-- - Guerrero: Tajo, Revés y Giro (el paso del combo que manda el servidor) y Bloqueo (atributo
--   Blocking).
-- - Puños: Jab y Directo alternos, y el Gancho en el combo.
-- - Magia: Cargar (bastón arriba mientras cargas el orbe) y Lanzar.
-- Prioridades: guardia (Action) < apuntar, bloquear y cargar (Action2) < golpes (Action3). Lo que
-- no anima un golpe (las piernas al andar) sigue con la animación de Roblox. Sin animaciones de
-- un estilo, enabled(estilo) es false y CharacterPose hace sus movimientos a mano.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)
local AimCamera = require(script.Parent.AimCamera)

local StyleAnimations = {}

local player = Players.LocalPlayer
local FADE = 0.1
local AIM_HOLD = 0.9 -- el arma sigue al frente este rato después de disparar

local LOOPED = { Guard = Enum.AnimationPriority.Action, Aim = Enum.AnimationPriority.Action2, Block = Enum.AnimationPriority.Action2, Charge = Enum.AnimationPriority.Action2 }
local ONCE = { Shot = true, Reload = true, Hook = true, Cast = true }

type StyleTracks = { [string]: any }
local tracks: { [string]: StyleTracks } = {}
local aimUntil = 0
local charging = false
local punchSide = 0
local aimToken = 0

local function specOf(style: string?): { [string]: any }?
	local def = style and StyleConfig.Styles[style]
	return def and def.Animations
end

-- ¿Tiene ese estilo sus animaciones? (si no, se usan los movimientos de CharacterPose)
function StyleAnimations.enabled(style: string?): boolean
	local spec = specOf(style)
	return spec ~= nil and type(spec.Guard) == "string" and spec.Guard ~= ""
end

local function currentStyle(): string?
	local value = player:GetAttribute(Constants.Attributes.CombatStyle)
	return if type(value) == "string" then value else nil
end

local function load(character: Model): { [string]: StyleTracks }
	local loaded = {}
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator") or (humanoid and humanoid:WaitForChild("Animator", 10))
	if not (animator and animator:IsA("Animator")) then
		return loaded
	end
	local function track(id: any, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
		if type(id) ~= "string" or id == "" then
			return nil
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, result = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if not ok then
			warn("[StyleAnimations] no se pudo cargar", id, result)
			return nil
		end
		result.Priority = priority
		result.Looped = looped
		return result
	end
	for style in StyleConfig.Styles do
		local spec = specOf(style)
		if spec and StyleAnimations.enabled(style) then
			local set: StyleTracks = {}
			for key, value in spec do
				if LOOPED[key] then
					set[key] = track(value, LOOPED[key], true)
				elseif ONCE[key] then
					set[key] = track(value, Enum.AnimationPriority.Action3, false)
				elseif type(value) == "table" then
					-- Listas: los tajos del Guerrero, los puñetazos
					local list = {}
					for index, id in value do
						list[index] = track(id, Enum.AnimationPriority.Action3, false)
					end
					set[key] = list
				end
			end
			loaded[style] = set
		end
	end
	return loaded
end

local function setPlaying(track: AnimationTrack?, wanted: boolean, fade: number?)
	if not track then
		return
	end
	if wanted and not track.IsPlaying then
		track:Play(fade or FADE)
	elseif not wanted and track.IsPlaying then
		track:Stop(fade or FADE)
	end
end

local function stopAll(set: StyleTracks)
	for _, value in set do
		if typeof(value) == "Instance" then
			setPlaying(value :: AnimationTrack, false)
		elseif type(value) == "table" then
			for _, track in value do
				setPlaying(track, false)
			end
		end
	end
end

-- Lo que se repite según el estilo y lo que estás haciendo
local function refresh()
	local style = currentStyle()
	for name, set in tracks do
		if name ~= style then
			stopAll(set)
		end
	end
	local set = style and tracks[style]
	if not set then
		return
	end
	setPlaying(set.Guard, true, 0.2)
	if style == "Weapons" then
		setPlaying(set.Aim, AimCamera.isAds() or os.clock() < aimUntil)
	elseif style == "Warrior" then
		setPlaying(set.Block, player:GetAttribute(Constants.Attributes.Blocking) == true)
	elseif style == "Magic" then
		setPlaying(set.Charge, charging)
	end
end

local function playOnce(track: AnimationTrack?, speed: number?)
	if not track then
		return
	end
	track:Play(0.05)
	if speed and speed > 0 then
		track:AdjustSpeed(speed)
	end
end

local function setFor(style: string): StyleTracks?
	return if currentStyle() == style then tracks[style] else nil
end

-- Armas: un disparo (el arma sube a apuntar un rato y salta con el retroceso)
function StyleAnimations.shot()
	local set = setFor("Weapons")
	if not set then
		return
	end
	aimUntil = os.clock() + AIM_HOLD
	refresh()
	playOnce(set.Shot)
	aimToken += 1
	local token = aimToken
	task.delay(AIM_HOLD + 0.05, function()
		if token == aimToken then
			refresh()
		end
	end)
end

-- Armas: recargar en `seconds` (la animación se acelera o frena para durar eso)
function StyleAnimations.reload(seconds: number?)
	local set = setFor("Weapons")
	local track = set and set.Reload
	if not track then
		return
	end
	aimUntil = 0
	refresh()
	local speed = if seconds and seconds > 0.05 and track.Length > 0 then track.Length / seconds else 1
	playOnce(track, speed)
end

-- Guerrero: un golpe del combo (1 tajo, 2 revés, 3 giro)
function StyleAnimations.slash(step: number)
	local set = setFor("Warrior")
	local list = set and set.Slashes
	if not list or #list == 0 then
		return
	end
	local index = math.clamp(math.floor(step), 1, #list)
	for other, track in list do
		if other ~= index and track.IsPlaying then
			track:Stop(0.05)
		end
	end
	playOnce(list[index])
end

-- Puños: jab y directo alternos; `combo` = el gancho
function StyleAnimations.punch(combo: boolean?)
	local set = setFor("Fists")
	if not set then
		return
	end
	if combo and set.Hook then
		playOnce(set.Hook)
		return
	end
	local list = set.Punches
	if not list or #list == 0 then
		return
	end
	punchSide = punchSide % #list + 1
	playOnce(list[punchSide])
end

-- Magia: empieza o deja de cargar un orbe
function StyleAnimations.charging(on: boolean)
	charging = on
	refresh()
end

-- Magia: lanzar un hechizo
function StyleAnimations.cast()
	local set = setFor("Magic")
	if not set then
		return
	end
	charging = false
	refresh()
	playOnce(set.Cast)
end

local function onCharacter(character: Model)
	tracks = {}
	charging = false
	aimUntil = 0
	task.spawn(function()
		local loaded = load(character)
		if player.Character == character then
			tracks = loaded
			refresh()
		end
	end)
end

function StyleAnimations.start()
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(function()
		charging = false
		aimUntil = 0
		refresh()
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.Blocking):Connect(refresh)
	AimCamera.Changed:Connect(refresh)
end

return StyleAnimations
