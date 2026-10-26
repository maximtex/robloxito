-- Lo que se ve en la mano de cada jugador según su estilo de pelea (lo ven todos): el arma de
-- fuego de su tipo con el estilo Armas, la espada con el Guerrero, el bastón con la Magia y
-- los guantes en las dos manos con Puños (GearModels). Se cambia al cambiar de estilo o de
-- objeto equipado (atributos CombatStyle y EquippedWeapon) y al reaparecer. Solo se ve: el
-- daño y de dónde sale cada golpe lo deciden PetCombatService y el cliente
-- (CharacterPose.gearPoint).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local StyleConfig = require(Shared.Config.StyleConfig)
local GunLogic = require(Shared.GunLogic)
local MagicLogic = require(Shared.MagicLogic)
local GearModels = require(script.Parent.Parent.Util.GearModels)

local GearService = {}

local shown: { [Player]: string } = {} -- lo que lleva ahora ("Weapons:Laser")

local function build(style: string, weaponId: string): Model?
	local def = WeaponConfig.Weapons[weaponId]
	if not def then
		return nil
	end
	local color = def.Color or Color3.new(1, 1, 1)
	if style == "Weapons" then
		return GearModels.gun(def.Model or GunLogic.kind(weaponId), color)
	elseif style == "Warrior" then
		-- Las mejores, más largas y brillantes
		local order = (def.Order or 301) - 300
		return GearModels.sword(color, 0.9 + order * 0.04, order >= 6)
	elseif style == "Magic" then
		local element = MagicLogic.elementDef(MagicLogic.element(weaponId))
		return GearModels.staff(color, element.Color or color)
	end
	return nil
end

local function refresh(player: Player, force: boolean?)
	local character = player.Character
	if not character then
		return
	end
	local style = player:GetAttribute(Constants.Attributes.CombatStyle)
	local weaponId = player:GetAttribute(Constants.Attributes.EquippedWeapon)
	if type(style) ~= "string" or type(weaponId) ~= "string" then
		return
	end
	local key = style .. ":" .. weaponId
	local existing = character:FindFirstChild("HeldGear")
	if not force and shown[player] == key and existing ~= nil then
		return
	end
	shown[player] = key
	if existing then
		existing:Destroy()
	end
	if style == "Fists" then
		-- Los guantes equipados (su color; los mejores brillan) o, sin guantes, del color del estilo
		local def = WeaponConfig.Weapons[weaponId]
		local gloves = def ~= nil and def.Category == "Fists"
		local color = if gloves and def.Color then def.Color else StyleConfig.Styles.Fists.Color
		GearModels.gloves(character, color, gloves and (def.Order or 101) >= 106)
		return
	end
	local model = build(style, weaponId)
	if model and not GearModels.attach(character, model) then
		model:Destroy()
	end
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("RightHand", 5)
		task.wait(0.2) -- que termine de montarse el avatar
		refresh(player, true)
	end)
	-- Al cambiar de estilo cambian los dos atributos seguidos: se mira cuando ya están los dos
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(function()
		task.defer(refresh, player)
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.EquippedWeapon):Connect(function()
		task.defer(refresh, player)
	end)
	if player.Character then
		task.spawn(refresh, player, true)
	end
end

function GearService.start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		shown[player] = nil
	end)
end

return GearService
