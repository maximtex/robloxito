-- Crea los RemoteEvents en ReplicatedStorage.Remotes al arrancar el servidor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared").Constants)

local RemoteService = {}

local remotesFolder: Folder? = nil

function RemoteService.start()
	local folder = ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Constants.RemotesFolderName
		folder.Parent = ReplicatedStorage
	end

	for _, remoteName in Constants.Remotes do
		if not folder:FindFirstChild(remoteName) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = remoteName
			remote.Parent = folder
		end
	end

	remotesFolder = folder
end

function RemoteService.get(remoteName: string): RemoteEvent
	assert(remotesFolder, "RemoteService.start() debe llamarse antes de get()")
	local remote = remotesFolder:FindFirstChild(remoteName)
	assert(remote and remote:IsA("RemoteEvent"), "RemoteEvent no encontrado: " .. remoteName)
	return remote
end

return RemoteService
