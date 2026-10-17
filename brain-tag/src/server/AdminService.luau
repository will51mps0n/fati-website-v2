-- The admin panel's server side. Every request is checked here: only admins
-- (Studio testers, the experience owner, Config.ADMIN_USER_IDS) get through,
-- and every argument is validated before it touches the game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterService = require(script.Parent.CharacterService)
local Config = require(ReplicatedStorage.Shared.Config)
local FurnitureService = require(script.Parent.FurnitureService)
local ItemService = require(script.Parent.ItemService)
local Items = require(ReplicatedStorage.Shared.Items)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Participants = require(script.Parent.Participants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RoundManager = require(script.Parent.RoundManager)
local ShopService = require(script.Parent.ShopService)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Util = require(ReplicatedStorage.Shared.Util)

type Participant = Participants.Participant

local AdminService = {}

local MAX_SPEED_FACTOR = 5
local C = Config.CHARACTER

-- Where to stand someone of `scale` at a spot, feet on the floor (like spawns).
local function standAt(position: Vector3, scale: number): CFrame
	local y = MapLayout.HEIGHTS.Floor + C.HipHeight + C.RootHeight / 2 * scale + 0.3
	return CFrame.new(position.X, y, position.Z)
end
local MAX_POINTS = 10_000_000

function AdminService.isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(Config.ADMIN_USER_IDS, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank >= 254
end

-- "*" means everyone; otherwise one participant id.
local function targets(data: { [string]: any }): { Participant }
	local id = data.target
	if id == "*" then
		return Participants.all()
	end
	local p = if typeof(id) == "string" then Participants.get(id) else nil
	return if p then { p } else {}
end

local function number(value: any, low: number, high: number): number?
	if typeof(value) ~= "number" or value ~= value then
		return nil
	end
	return math.clamp(value, low, high)
end

local function names(list: { Participant }): string
	if #list == 1 then
		return list[1].name
	end
	return #list .. " players"
end

type Handler = (admin: Participant, data: { [string]: any }) -> (boolean, string)

local ACTIONS: { [string]: Handler } = {}

-- Items ---------------------------------------------------------------------------------

function ACTIONS.give(admin, data)
	local item = Items.get(if typeof(data.item) == "string" then data.item else nil)
	if not item then
		return false, "Unknown item"
	end
	if data.ground == true then
		local root = Participants.body(admin)
		if not root then
			return false, "You need a character to drop items"
		end
		ItemService.spawnGround(item.id, root.Position + root.CFrame.LookVector * 5)
		return true, item.name .. " dropped in front of you"
	end
	local list = targets(data)
	local given = 0
	for _, p in list do
		if p.team == "Human" then
			ItemService.give(p, item.id)
			given += 1
		end
	end
	if given == 0 then
		return false, "Only humans can hold items"
	end
	return true, string.format("Gave %s to %s", item.name, names(list))
end

-- Skins ---------------------------------------------------------------------------------

function ACTIONS.skin(_admin, data)
	local skin = Skins.get(if typeof(data.skin) == "string" then data.skin else nil)
	if not skin then
		return false, "Unknown skin"
	end
	local list = targets(data)
	for _, p in list do
		ShopService.grantSkin(p, skin.id) -- theirs to keep
		ShopService.equipSkin(p, skin)
	end
	return #list > 0, string.format("%s skin for %s", skin.name, names(list))
end

-- Players -------------------------------------------------------------------------------

function ACTIONS.speed(_admin, data)
	local factor = number(data.factor, 0, MAX_SPEED_FACTOR)
	if not factor then
		return false, "Bad speed"
	end
	local list = targets(data)
	for _, p in list do
		p.adminSpeed = factor
		CharacterService.refreshSpeed(p)
	end
	return #list > 0, string.format("Speed x%.2g for %s", factor, names(list))
end

function ACTIONS.points(_admin, data)
	local add = number(data.add, -MAX_POINTS, MAX_POINTS)
	local set = number(data.set, 0, MAX_POINTS)
	if not add and not set then
		return false, "Bad points"
	end
	local list = targets(data)
	for _, p in list do
		Participants.setScore(p, if set then set else p.score + (add or 0))
		CharacterService.refreshSize(p)
		CharacterService.refreshSpeed(p)
	end
	local what = if set then "set to " .. Util.commas(set) else string.format("%+d", add or 0)
	return #list > 0, string.format("Points %s for %s", what, names(list))
end

function ACTIONS.immunity(_admin, data)
	local value = number(data.value, 0, Config.IMMUNITY_MAX)
	if not value then
		return false, "Bad immunity"
	end
	local list = targets(data)
	for _, p in list do
		Participants.setImmunity(p, value)
	end
	return #list > 0, string.format("Immunity %d for %s", value, names(list))
end

function ACTIONS.team(_admin, data)
	local team = data.team
	if team ~= "Human" and team ~= "Zombie" then
		return false, "Bad team"
	end
	local list = targets(data)
	for _, p in list do
		RoundManager.setTeam(p, team)
	end
	return #list > 0, string.format("%s now %s", names(list), if team == "Zombie" then "zombie" else "human")
end

function ACTIONS.bring(admin, data)
	local root = Participants.body(admin)
	if not root then
		return false, "You need a character"
	end
	local list = targets(data)
	for i, p in list do
		if p ~= admin then
			local angle = i / math.max(1, #list) * math.pi * 2
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 6
			CharacterService.place(p, standAt(root.Position + offset * math.max(1, p.scale), p.scale))
		end
	end
	return #list > 0, "Brought " .. names(list)
end

function ACTIONS.goTo(admin, data)
	local list = targets(data)
	local target = list[1]
	local root = target and Participants.body(target)
	if not target or target == admin or not root then
		return false, "Pick one other player"
	end
	CharacterService.place(
		admin,
		standAt(root.Position + Vector3.new(6 * math.max(1, target.scale), 0, 0), admin.scale)
	)
	return true, "Went to " .. target.name
end

function ACTIONS.respawn(_admin, data)
	local list = targets(data)
	for _, p in list do
		RoundManager.respawn(p)
	end
	return #list > 0, "Respawned " .. names(list)
end

-- Round ---------------------------------------------------------------------------------

function ACTIONS.skip()
	if RoundManager.skipPhase() then
		return true, "Skipped to the next phase"
	end
	return false, "Nothing to skip right now"
end

function ACTIONS.time(_admin, data)
	local seconds = number(data.seconds, -600, 600)
	if not seconds then
		return false, "Bad time"
	end
	if RoundManager.addTime(seconds) then
		return true, string.format("%+d seconds", seconds)
	end
	return false, "No timer to change right now"
end

function ACTIONS.nextMap()
	if RoundManager.queueNextMap() then
		return true, "Next round loads the next map"
	end
	return false, "Only one map is in the rotation"
end

function ACTIONS.resetFurniture()
	FurnitureService.resetAll()
	return true, "Furniture put back"
end

function ACTIONS.clearItems()
	ItemService.clearGround()
	return true, "Ground items removed"
end

local function handle(player: Player, action: unknown, data: unknown): (boolean, string)
	if not AdminService.isAdmin(player) then
		return false, "Not an admin"
	end
	local admin = Participants.fromPlayer(player)
	local handler = if typeof(action) == "string" then ACTIONS[action] else nil
	if not admin or not handler then
		return false, "Unknown command"
	end
	local args: { [string]: any } = if typeof(data) == "table" then data :: any else {}
	local ok, success, message = pcall(handler, admin, args)
	if not ok then
		warn("[Admin] " .. tostring(action) .. " failed: " .. tostring(success))
		return false, "That failed (see server output)"
	end
	return success, message
end

function AdminService.init()
	Remotes.func("Admin").OnServerInvoke = handle
	Participants.onAdded(function(p)
		if p.player and AdminService.isAdmin(p.player) then
			p.state:SetAttribute("Admin", true)
		end
	end)
end

return AdminService
