-- Server entry point: builds the world, starts every service, and turns
-- joining players into participants.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")) -- creates the remotes

local WorldSetup = require(script.Parent.WorldSetup)
WorldSetup.run()

local BotService = require(script.Parent.BotService)
local CharacterService = require(script.Parent.CharacterService)
local Combat = require(script.Parent.Combat)
local DataService = require(script.Parent.DataService)
local FurnitureService = require(script.Parent.FurnitureService)
local ItemService = require(script.Parent.ItemService)
local MapBuilder = require(script.Parent.MapBuilder)
local MonetizationService = require(script.Parent.MonetizationService)
local Participants = require(script.Parent.Participants)
local Projectiles = require(script.Parent.Projectiles)
local RoundManager = require(script.Parent.RoundManager)
local ShopService = require(script.Parent.ShopService)
local TopScores = require(script.Parent.TopScores)

MapBuilder.build()
FurnitureService.build()
CharacterService.buildTemplate()
CharacterService.init()

FurnitureService.start(function()
	local movers = {}
	for _, p in Participants.all() do
		local root, humanoid = Participants.body(p)
		if root and humanoid then
			table.insert(movers, { root = root, humanoid = humanoid })
		end
	end
	return movers
end)

Combat.init()
Projectiles.init()
ItemService.init()
ShopService.init()
DataService.init()
MonetizationService.init()
TopScores.start()
RoundManager.start()

local function onPlayerAdded(player: Player)
	player.CanLoadCharacterAppearance = false
	local profile = DataService.load(player) -- yields
	local passes = MonetizationService.ownedPasses(player) -- yields
	if player.Parent ~= Players then
		return
	end
	local p = Participants.add({
		id = Participants.playerId(player),
		name = player.DisplayName,
		player = player,
		isBot = false,
		profile = profile,
		passes = passes,
	})
	MonetizationService.applyPasses(p)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	local p = Participants.fromPlayer(player)
	if p then
		Participants.remove(p)
	end
end)

BotService.start()
print("[Brain Tag] server ready")
