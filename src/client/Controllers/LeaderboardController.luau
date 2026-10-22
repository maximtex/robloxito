-- Fila del jugador en las tablas de clasificación (LeaderboardService): cada cliente escribe
-- en su copia de la tabla su foto, su puesto en este servidor y su número de lo que muestra
-- esa tabla (el atributo del jugador que lleva el modelo en "Attribute"). Lo que se cambia
-- aquí solo lo ve este jugador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)
local formatNumber = require(Shared.Util.FormatNumber)

local LeaderboardController = {}

local REFRESH_SECONDS = 2

local player = Players.LocalPlayer

local function valueOf(target: Player, attribute: string): number
	local value = target:GetAttribute(attribute)
	return if typeof(value) == "number" and value == value then value else 0
end

-- Puesto en este servidor (como la página «Mejores del servidor»: más es mejor)
local function rankOf(attribute: string): number
	local mine = valueOf(player, attribute)
	local rank = 1
	for _, other in Players:GetPlayers() do
		if other ~= player and valueOf(other, attribute) > mine then
			rank += 1
		end
	end
	return rank
end

local function refresh()
	local folder = Workspace:FindFirstChild(LeaderboardConfig.ModelName)
	if not folder then
		return
	end
	for _, board in folder:GetChildren() do
		local attribute = board:GetAttribute("Attribute")
		local screen = board:FindFirstChild("Screen")
		local gui = screen and screen:FindFirstChild("Board")
		local you = gui and gui:FindFirstChild("You")
		if typeof(attribute) ~= "string" or not you then
			continue
		end
		local name = you:FindFirstChild("Name")
		local value = you:FindFirstChild("Value")
		local avatar = you:FindFirstChild("Avatar")
		if name and name:IsA("TextLabel") then
			name.Text = ("#%d  %s"):format(rankOf(attribute), player.DisplayName)
		end
		if value and value:IsA("TextLabel") then
			local amount = valueOf(player, attribute)
			value.Text = if attribute == "Rebirths" then tostring(math.floor(amount)) else formatNumber(amount)
		end
		if avatar and avatar:IsA("ImageLabel") and avatar.Image == "" then
			avatar.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(player.UserId)
		end
	end
end

function LeaderboardController.start()
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return LeaderboardController
