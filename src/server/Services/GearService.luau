-- Lo que se ve en la mano de cada jugador según su estilo de pelea (lo ven todos): el arma de
-- fuego de su tipo con el estilo Armas, la espada con el Guerrero, el bastón con la Magia y
-- los guantes en las dos manos con Puños (GearModels). Se cambia al cambiar de estilo o de
-- objeto equipado (atributos CombatStyle y EquippedWeapon) y al reaparecer. Solo se ve: el
-- daño y de dónde sale cada golpe lo deciden PetCombatService y el cliente
-- (CharacterPose.gearPoint).
-- Equipo visible (OutfitLogic): además, cada clase lleva su pieza (carcaj, escudo, cinta y
-- fajín o capa) y la mejora de Armadura se ve en el cuerpo (hombreras de cuero, de hierro, peto
-- de acero y, al máximo, todo dorado). Se rehace al cambiar de estilo o de grado de armadura
-- (atributo UpgradeLevel_Armor) y al reaparecer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local StyleConfig = require(Shared.Config.StyleConfig)
local GunLogic = require(Shared.GunLogic)
local MagicLogic = require(Shared.MagicLogic)
local OutfitLogic = require(Shared.OutfitLogic)
local GearModels = require(script.Parent.Parent.Util.GearModels)

local GearService = {}

local shown: { [Player]: string } = {} -- lo que lleva ahora ("Weapons:Laser")
local dressed: { [Player]: string } = {} -- la ropa que lleva ahora (OutfitLogic.key)

local ARMOR_ATTRIBUTE = Constants.Attributes.UpgradeLevelPrefix .. "Armor"

-- La pieza de la clase y la armadura (solo si cambian, o `force` al reaparecer)
local function dress(player: Player, force: boolean?)
	local character = player.Character
	if not character then
		return
	end
	local style = player:GetAttribute(Constants.Attributes.CombatStyle)
	local level = player:GetAttribute(ARMOR_ATTRIBUTE)
	local key = OutfitLogic.key(style, level)
	local existing = character:FindFirstChild("ClassOutfit")
	if not force and dressed[player] == key and (existing ~= nil or key == "-:0") then
		return
	end
	dressed[player] = key
	if existing then
		existing:Destroy()
	end
	local def = if type(style) == "string" then StyleConfig.Styles[style] else nil
	local color = if def then def.Color else Color3.new(1, 1, 1)
	GearModels.outfit(character, OutfitLogic.piece(style), OutfitLogic.armor(OutfitLogic.armorTier(level)), color)
end

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
		dress(player, true)
	end)
	-- Al cambiar de estilo cambian los dos atributos seguidos: se mira cuando ya están los dos
	player:GetAttributeChangedSignal(Constants.Attributes.CombatStyle):Connect(function()
		task.defer(refresh, player)
		task.defer(dress, player)
	end)
	player:GetAttributeChangedSignal(ARMOR_ATTRIBUTE):Connect(function()
		task.defer(dress, player)
	end)
	player:GetAttributeChangedSignal(Constants.Attributes.EquippedWeapon):Connect(function()
		task.defer(refresh, player)
	end)
	if player.Character then
		task.spawn(refresh, player, true)
		task.spawn(dress, player, true)
	end
end

function GearService.start()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		shown[player] = nil
		dressed[player] = nil
	end)
end

return GearService
