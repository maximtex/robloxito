-- Animaciones de la espada del Guerrero (StyleConfig.Styles.Warrior.Animations), solo en TU
-- personaje: Roblox enseña a los demás las animaciones que tu cliente pone en tu personaje.
-- - Guardia (se repite) mientras llevas el estilo Guerrero.
-- - Bloqueo (se repite) mientras bloqueas (atributo Blocking).
-- - Tajo, Revés y Giro: cada golpe del combo (CombatController, con el paso que manda el
--   servidor).
-- Mientras suena un tajo o el bloqueo, la guardia se para (así los demás también ven el
-- movimiento limpio). Sin animaciones configuradas, enabled() es false y CharacterPose hace los
-- movimientos a mano.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local StyleConfig = require(Shared.Config.StyleConfig)

local SwordAnimations = {}

local player = Players.LocalPlayer
local spec = StyleConfig.Styles.Warrior.Animations
local FADE = 0.1

type Tracks = { Guard: AnimationTrack?, Block: AnimationTrack?, Slashes: { AnimationTrack } }
local tracks: Tracks? = nil
local slashToken = 0

-- ¿Hay animaciones de espada? (si no, se usan los movimientos de CharacterPose)
function SwordAnimations.enabled(): boolean
	return spec ~= nil and type(spec.Guard) == "string" and spec.Guard ~= ""
end

local function load(character: Model): Tracks?
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 10)
	if not (animator and animator:IsA("Animator")) then
		return nil
	end
	local function track(id: string?, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
		if type(id) ~= "string" or id == "" then
			return nil
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, result = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if not ok then
			warn("[SwordAnimations] no se pudo cargar", id, result)
			return nil
		end
		result.Priority = priority
		result.Looped = looped
		return result
	end
	local loaded: Tracks = {
		Guard = track(spec.Guard, Enum.AnimationPriority.Action, true),
		Block = track(spec.Block, Enum.AnimationPriority.Action2, true),
		Slashes = {},
	}
	for index, id in spec.Slashes or {} do
		loaded.Slashes[index] = track(id, Enum.AnimationPriority.Action3, false) :: AnimationTrack
	end
	return loaded
end

local function isWarrior(): boolean
	return player:GetAttribute(Constants.Attributes.CombatStyle) == "Warrior"
end

local function slashing(): boolean
	if not tracks then
		return false
	end
	for _, slash in tracks.Slashes do
		if slash.IsPlaying then
			return true
		end
	end
	return false
end

-- Guardia o bloqueo según el estilo y si bloqueas
local function refresh()
	local current = tracks
	if not current then
		return
	end
	local warrior = isWarrior()
	local blocking = warrior and player:GetAttribute(Constants.Attributes.Blocking) == true
	if current.Block then
		if blocking and not current.Block.IsPlaying then
			current.Block:Play(FADE)
		elseif not blocking and current.Block.IsPlaying then
			current.Block:Stop(FADE)
		end
	end
	if current.Guard then
		local wanted = warrior and not blocking and not slashing()
		if wanted and not current.Guard.IsPlaying then
			current.Guard:Play(0.2)
		elseif not wanted and current.Guard.IsPlaying then
			current.Guard:Stop(FADE)
		end
	end
	if not warrior then
		for _, slash in current.Slashes do
			if slash.IsPlaying then
				slash:Stop(FADE)
			end
		end
	end
end

-- Un golpe del combo (1 tajo, 2 revés, 3 giro) en tu personaje
function SwordAnimations.slash(step: number)
	local current = tracks
	if not current then
		return
	end
	local slash = current.Slashes[math.clamp(math.floor(step), 1, #current.Slashes)]
	if not slash then
		return
	end
	for _, other in current.Slashes do
		if other ~= slash and other.IsPlaying then
			other:Stop(0.05)
		end
	end
	if current.Guard and current.Guard.IsPlaying then
		current.Guard:Stop(0.05)
	end
	slash:Play(0.05)
	slashToken += 1
	local token = slashToken
	task.delay(math.max(0.2, slash.Length), function()
		if token == slashToken then
			refresh()
		end
	end)
end

local function onCharacter(character: Model)
	tracks = nil
	task.spawn(function()
		local loaded = load(character)
		if player.Character == character then
			tracks = loaded
			refresh()
		end
	end)
end

function SwordAnimations.start()
	if not SwordAnimations.enabled() then
		return
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(refresh)
	player:GetAttributeChangedSignal(Constants.Attributes.Blocking):Connect(refresh)
end

return SwordAnimations
