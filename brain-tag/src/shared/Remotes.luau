-- Every RemoteEvent and RemoteFunction the game uses. The server creates them
-- at startup; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- client -> server
	"UseItem", -- (action: "start" | "stop", aim: Vector3)
	"PickUp",
	"DropItem",
	"SelectSlot", -- (slot: number) which inventory slot is in your hand
	"ZombieReturn",
	"TutorialDone",
	-- server -> client
	"Knockback", -- (velocity: Vector3, seconds: number)
	"Announce", -- (text, hexColor?)
	"Fx", -- (kind, data)
	"Toast", -- (text, hexColor?)
}

-- Unreliable: frequent, small, fine to lose one now and then.
local UNRELIABLE = {
	"PushClaim", -- client -> server: { Model } of furniture it is pushing
	"Aim", -- client -> server: flat aim direction, about 10 times a second
}

local FUNCTIONS = {
	"BuyItem", -- (itemId, fromWizard) -> (ok, message)
	"BuySkin", -- (skinId) -> (status, message)
	"Admin", -- (action, data) -> (ok, message); admins only, see AdminService
}

local Remotes = {}

local folder: Instance
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	folder = existing or Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in UNRELIABLE do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("UnreliableRemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

function Remotes.event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.unreliable(name: string): UnreliableRemoteEvent
	return folder:WaitForChild(name) :: UnreliableRemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
