-- One-time world settings: flat lighting, collision groups, the folders other
-- services fill, and the replicated state folder the HUD reads.

local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local WorldSetup = {}

WorldSetup.GROUPS = {
	Characters = "Characters",
	Furniture = "Furniture",
	Shells = "CharacterShells", -- body-sized cylinders that only hit each other
}

local function folder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function WorldSetup.run()
	Players.CharacterAutoLoads = false

	Lighting.GlobalShadows = false
	Lighting.Brightness = 1
	Lighting.ClockTime = 12
	Lighting.Ambient = Color3.fromRGB(190, 190, 190)
	Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 190)
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.FogEnd = 100000
	for _, child in Lighting:GetChildren() do
		if child:IsA("Atmosphere") or child:IsA("BloomEffect") or child:IsA("SunRaysEffect") then
			child:Destroy()
		end
	end

	local groups = WorldSetup.GROUPS
	PhysicsService:RegisterCollisionGroup(groups.Characters)
	PhysicsService:RegisterCollisionGroup(groups.Furniture)
	PhysicsService:RegisterCollisionGroup(groups.Shells)
	-- Root boxes never hit each other; the shells do the bumping, and only
	-- with each other, so a big player's wide shell never snags a doorway.
	PhysicsService:CollisionGroupSetCollidable(groups.Characters, groups.Characters, false)
	for _, other in { "Default", groups.Characters, groups.Furniture } do
		PhysicsService:CollisionGroupSetCollidable(groups.Shells, other, false)
	end
	PhysicsService:CollisionGroupSetCollidable(groups.Shells, groups.Shells, Config.PLAYERS_COLLIDE)

	for _, name in { "Map", "Furniture", "GroundItems", "Projectiles", "Traps", "Effects", "Bots" } do
		folder(name, workspace)
	end

	local state = folder("BrainTagState", ReplicatedStorage)
	folder("Participants", state)
	state:SetAttribute("Phase", "Waiting")
	state:SetAttribute("PhaseEndsAt", 0)
	state:SetAttribute("Survivors", 0)
	state:SetAttribute("Zombies", 0)
	state:SetAttribute("Winner", "")
	state:SetAttribute("Round", 0)
	state:SetAttribute("Needed", Config.MIN_PLAYERS)
	state:SetAttribute("WizardHere", false)
	state:SetAttribute("TopScores", "[]")
end

function WorldSetup.state(): Folder
	return ReplicatedStorage:WaitForChild("BrainTagState") :: Folder
end

return WorldSetup
