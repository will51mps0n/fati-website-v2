-- Server entry point: builds the world, starts every service, and turns
-- joining players into participants.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")) -- creates the remotes

local WorldSetup = require(script.Parent.WorldSetup)
WorldSetup.run()

local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)

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
local Traps = require(script.Parent.Traps)

local firstMap = MapLayout.use(Config.MAP_ROTATION[1])
MapBuilder.build(firstMap)
FurnitureService.build(firstMap)
CharacterService.buildTemplate()
CharacterService.init()

FurnitureService.start(function()
	local movers = {}
	for _, p in Participants.all() do
		local root, humanoid = Participants.body(p)
		if root and humanoid then
			local item = Items.get(p.heldItem)
			local melee = p.team == "Human" and item and item.kind == "Melee"
			table.insert(movers, {
				root = root,
				humanoid = humanoid,
				id = p.id,
				scale = p.scale,
				aim = p.aim,
				reach = if melee and item then (item.reach or 5) * math.max(1, p.scale * 0.9) else nil,
			})
		end
	end
	return movers
end)

Combat.init()
Projectiles.init()
Traps.init()
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
