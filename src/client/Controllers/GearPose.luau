-- Postura de reposo de cada jugador según lo que lleva en la mano (CharacterPose.setRest):
-- el arma medio levantada (al frente si TÚ apuntas con el clic derecho), la espada en guardia
-- (cruzada si bloquea: atributo Blocking) o el bastón. Si el estilo tiene sus animaciones,
-- nada: lo hacen ellas (StyleAnimations). Con Puños, los brazos normales. Solo se
-- ve; lo hace cada cliente con todos los personajes (atributos CombatStyle y Blocking).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local CharacterPose = require(script.Parent.CharacterPose)
local AimCamera = require(script.Parent.AimCamera)
local StyleAnimations = require(script.Parent.StyleAnimations)

local GearPose = {}

local localPlayer = Players.LocalPlayer

local function poseFor(player: Player): string?
	local style = player:GetAttribute(Constants.Attributes.CombatStyle)
	-- Con las animaciones del estilo, la postura la ponen ellas (StyleAnimations; Roblox las
	-- enseña a todos): nada a mano
	if type(style) == "string" and StyleAnimations.enabled(style) then
		return nil
	end
	if style == "Weapons" then
		return if player == localPlayer and AimCamera.isAds() then "Aim" else "Gun"
	elseif style == "Warrior" then
		return if player:GetAttribute(Constants.Attributes.Blocking) == true then "Block" else "Sword"
	elseif style == "Magic" then
		return "Staff"
	end
	return nil
end

function GearPose.refresh(player: Player)
	local character = player.Character
	if character then
		CharacterPose.setRest(character, poseFor(player))
	end
end

-- Las articulaciones del avatar pueden cambiar después de aparecer (al cargarse su aspecto
-- Roblox las vuelve a montar, p. ej. como AnimationConstraint): se vuelve a poner el reposo
local SHOULDERS = { RightShoulder = true, LeftShoulder = true, ["Right Shoulder"] = true, ["Left Shoulder"] = true }
local function watchCharacter(player: Player, character: Model)
	character.DescendantAdded:Connect(function(descendant)
		if SHOULDERS[descendant.Name] and (descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint")) then
			task.defer(GearPose.refresh, player)
		end
	end)
	task.delay(0.5, GearPose.refresh, player)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(function()
		GearPose.refresh(player)
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.Blocking):Connect(function()
		GearPose.refresh(player)
	end)
	if player.Character then
		watchCharacter(player, player.Character)
	end
end

function GearPose.start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	AimCamera.Changed:Connect(function()
		GearPose.refresh(localPlayer)
	end)
end

return GearPose
