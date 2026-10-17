-- Bots that fill every round (Config.BOTS_MIN to BOTS_MAX of them, fewer
-- when real players join). They count as participants for every rule and
-- wear random skins. Each has a level from 3 to 6; Mario Robles is a 6 and
-- most of the roster is 5 or 6:
--   * zombies spread out over different humans, lead their target, shove
--     through barricades, remember where a human hid, and press Z sooner
--     when stuck
--   * humans grab the odd item (some start with one), hold weapons out
--     toward close zombies (weapons are solid; a few can swing), flee
--     toward open ground away from every zombie, and hide in bushes
-- Movement never aims through walls: straight lines are checked with a
-- body-wide sweep, everything else uses pathfinding, and a bot that stops
-- making progress steps sideways and replans.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bushes = require(ReplicatedStorage.Shared.Bushes)
local BushService = require(script.Parent.BushService)
local CharacterService = require(script.Parent.CharacterService)
local Combat = require(script.Parent.Combat)
local Config = require(ReplicatedStorage.Shared.Config)
local ItemService = require(script.Parent.ItemService)
local Items = require(ReplicatedStorage.Shared.Items)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Participants = require(script.Parent.Participants)
local RoundManager = require(script.Parent.RoundManager)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Util = require(ReplicatedStorage.Shared.Util)

type Participant = Participants.Participant

local BotService = {}

type Level = {
	think: number, -- seconds between decisions
	speed: number, -- walk speed multiplier
	sight: number, -- zombie: how far away it notices humans
	lead: number, -- zombie: seconds of target movement it predicts
	memory: number, -- zombie: seconds it keeps hunting where a human vanished
	stuck: number, -- zombie: seconds without progress before pressing Z
	flee: number, -- human: zombie distance that starts a run
	directions: number, -- human: escape directions considered
	hide: number, -- human: chance to be a bush hider
}

local LEVELS: { [number]: Level } = {
	[3] = {
		think = 0.25,
		speed = 1,
		sight = 120,
		lead = 0.4,
		memory = 3,
		stuck = 5,
		flee = 45,
		directions = 8,
		hide = 0.35,
	},
	[4] = {
		think = 0.18,
		speed = 1.02,
		sight = 200,
		lead = 0.55,
		memory = 5,
		stuck = 4,
		flee = 55,
		directions = 10,
		hide = 0.45,
	},
	[5] = {
		think = 0.14,
		speed = 1.05,
		sight = 400,
		lead = 0.7,
		memory = 7,
		stuck = 3,
		flee = 65,
		directions = 12,
		hide = 0.5,
	},
	[6] = {
		think = 0.11,
		speed = 1.08,
		sight = 600,
		lead = 0.8,
		memory = 9,
		stuck = 2.5,
		flee = 75,
		directions = 12,
		hide = 0.55,
	},
}

-- Name and level. Bots join in this order.
local ROSTER: { { name: string, level: number } } = {
	{ name = "Mario Robles", level = 6 },
	{ name = "Fart Butt", level = 5 },
	{ name = "Poop Face", level = 5 },
	{ name = "Fat Guy", level = 4 },
	{ name = "Booger Bob", level = 6 },
	{ name = "Stinky Pete", level = 5 },
	{ name = "Captain Wedgie", level = 4 },
	{ name = "Toilet Ted", level = 3 },
	{ name = "Sir Toots-a-Lot", level = 6 },
	{ name = "Sweaty Steve", level = 5 },
	{ name = "Moldy Cheese", level = 4 },
	{ name = "Burp Master", level = 5 },
	{ name = "Snot Rocket", level = 6 },
	{ name = "Diaper Dan", level = 3 },
	{ name = "Barf Bag", level = 5 },
	{ name = "Lord Stinkbottom", level = 6 },
	{ name = "Cheesy Feet", level = 4 },
	{ name = "Greasy Gary", level = 5 },
	{ name = "Wet Sock", level = 3 },
	{ name = "Professor Poot", level = 6 },
	{ name = "Nacho Breath", level = 4 },
	{ name = "Big Nose Ned", level = 5 },
	{ name = "Soggy Waffle", level = 3 },
	{ name = "Chunky Monkey", level = 4 },
	{ name = "Gassy Gus", level = 5 },
	{ name = "Pickle Pants", level = 4 },
	{ name = "Smelly Kelly", level = 5 },
	{ name = "Belly Flop Bob", level = 3 },
	{ name = "Turbo Toot", level = 6 },
	{ name = "Stinkerbell", level = 5 },
}

-- Cheap, common weapons a bot may start a round with (never rare ones).
local STARTER_WEAPONS = { "Stick", "RubberChicken", "PoolNoodle", "Bat", "Baguette" }

local rng = Random.new()

-- Shared view of the world, refreshed at most 10 times a second -------------------------

type Seen = { p: Participant, position: Vector3, velocity: Vector3, hidden: boolean }

local seenAt = 0
local seenHumans: { Seen } = {}
local seenZombies: { Seen } = {}
local chasing: { [string]: Participant } = {} -- bot id -> the human it hunts

local function look()
	local now = os.clock()
	if now - seenAt < 0.1 then
		return
	end
	seenAt = now
	table.clear(seenHumans)
	table.clear(seenZombies)
	for _, p in Participants.all() do
		local root = Participants.body(p)
		if root then
			local entry = {
				p = p,
				position = root.Position,
				velocity = Util.flat(root.AssemblyLinearVelocity),
				hidden = BushService.hidden(p),
			}
			table.insert(if p.team == "Zombie" then seenZombies else seenHumans, entry)
		end
	end
end

local function chasers(target: Participant, except: string): number
	local count = 0
	for id, p in chasing do
		if p == target and id ~= except then
			count += 1
		end
	end
	return count
end

-- Pathfinding is the expensive part: share a budget across all bots.
local PATHS_PER_SECOND = 30
local tokens, tokensAt = PATHS_PER_SECOND, os.clock()

local function takePathToken(): boolean
	local now = os.clock()
	tokens = math.min(PATHS_PER_SECOND, tokens + (now - tokensAt) * PATHS_PER_SECOND)
	tokensAt = now
	if tokens >= 1 then
		tokens -= 1
		return true
	end
	return false
end

local function inBounds(v: Vector3, margin: number): boolean
	return MapLayout.inRect(MapLayout.current().bounds, v.X, v.Z, -margin)
end

local function randomSpot(): Vector3
	local layout = MapLayout.current()
	local list = if rng:NextNumber() < 0.6 then layout.itemSpots else layout.humanSpawns
	local spot = list[rng:NextInteger(1, #list)]
	return Vector3.new(spot.x, 2, spot.z)
end

local function nearestBush(from: Vector3, range: number): Vector3?
	local best: Vector3? = nil
	local bestDistance = range
	for _, leaves in Bushes.leaves() do
		local d = Util.flatDistance(leaves.Position, from)
		if d < bestDistance then
			best, bestDistance = Vector3.new(leaves.Position.X, from.Y, leaves.Position.Z), d
		end
	end
	return best
end

local function nearestItem(from: Vector3, range: number): Vector3?
	local folder = workspace:FindFirstChild("GroundItems")
	if not folder then
		return nil
	end
	local best: Vector3? = nil
	local bestDistance = range
	for _, model in folder:GetChildren() do
		local x, z = model:GetAttribute("SpotX"), model:GetAttribute("SpotZ")
		local item = Items.get(model:GetAttribute("ItemId") :: string?)
		-- Bots leave the good stuff for players: only cheap, common items.
		local common = item ~= nil
			and not item.isRare
			and (item.price or math.huge) <= Config.BOT_MAX_ITEM_PRICE
		if common and typeof(x) == "number" and typeof(z) == "number" then
			local spot = Vector3.new(x, from.Y, z)
			local d = Util.flatDistance(spot, from)
			if d < bestDistance then
				best, bestDistance = spot, d
			end
		end
	end
	return best
end

-- Can a zombie at `from` see this human?
local function visible(entry: Seen, from: Vector3): boolean
	return not entry.hidden or Util.flatDistance(entry.position, from) <= Config.BUSH_REVEAL_DISTANCE
end

-- One bot ---------------------------------------------------------------------------------

local function brain(p: Participant, level: Level, seed: number)
	local random = Random.new(seed)
	local pathScale = 0
	local path: Path? = nil
	local waypoints: { PathWaypoint } = {}
	local waypointIndex = 1
	local pathGoal: Vector3? = nil
	local computedAt = 0
	local wanderGoal: Vector3? = nil
	local wanderUntil = 0
	local progressAt = os.clock()
	local progressFrom = Vector3.zero
	local detour: Vector3? = nil
	local detourUntil = 0
	local lastSeen: Vector3? = nil
	local lastSeenAt = 0
	local armedRound = -1
	local hider = random:NextNumber() < level.hide

	local function radius(): number
		return 0.9 * p.scale
	end

	-- A short step in the open direction closest to `toward` (unsticking).
	local function sidestep(root: BasePart, toward: Vector3): Vector3?
		local want = Util.flatUnit(toward - root.Position) or Vector3.xAxis
		local best: Vector3? = nil
		local bestScore = -math.huge
		for i = 0, 7 do
			local angle = i / 8 * math.pi * 2 + random:NextNumber(-0.2, 0.2)
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local spot = root.Position + dir * 7
			if inBounds(spot, 3) and Combat.clearWide(root.Position, spot, radius()) then
				local score = dir:Dot(want) + random:NextNumber(0, 0.6)
				if score > bestScore then
					best, bestScore = spot, score
				end
			end
		end
		return best
	end

	local function followPath(goal: Vector3, root: BasePart, humanoid: Humanoid, pushThrough: boolean)
		local now = os.clock()
		if not path or math.abs(p.scale - pathScale) > 0.2 then
			pathScale = p.scale
			path = PathfindingService:CreatePath({
				AgentRadius = 1.4 * p.scale,
				AgentHeight = 4,
				AgentCanJump = false,
				WaypointSpacing = 4,
			})
			pathGoal = nil
		end
		local stale = not pathGoal or now - computedAt > 1.2 or (goal - (pathGoal :: Vector3)).Magnitude > 6
		if stale and takePathToken() then
			pathGoal, computedAt = goal, now
			local ok = pcall(function()
				(path :: Path):ComputeAsync(root.Position, goal)
			end)
			if ok and (path :: Path).Status == Enum.PathStatus.Success then
				waypoints = (path :: Path):GetWaypoints()
				waypointIndex = math.min(2, #waypoints)
			else
				waypoints = {}
			end
		end
		-- Skip ahead to the farthest waypoint we can walk straight to.
		local ahead = math.min(#waypoints, waypointIndex + 4)
		while ahead > waypointIndex do
			if Combat.clearWide(root.Position, waypoints[ahead].Position, radius()) then
				waypointIndex = ahead
				break
			end
			ahead -= 1
		end
		local waypoint = waypoints[waypointIndex]
		if
			waypoint
			and Util.flatDistance(waypoint.Position, root.Position) < 2
			and waypointIndex < #waypoints
		then
			waypointIndex += 1
			waypoint = waypoints[waypointIndex]
		end
		if waypoint then
			humanoid:MoveTo(waypoint.Position)
		elseif pushThrough and Combat.clearWide(root.Position, goal, radius(), true) then
			humanoid:MoveTo(goal) -- only furniture in the way: shove through it
		else
			local step = sidestep(root, goal)
			if step then
				humanoid:MoveTo(step)
			end
		end
	end

	-- Straight there when the way is open for our whole body, else a path.
	local function goTo(goal: Vector3, root: BasePart, humanoid: Humanoid, pushThrough: boolean)
		local now = os.clock()
		if detour and now < detourUntil then
			humanoid:MoveTo(detour)
			return
		end
		detour = nil
		local distance = Util.flatDistance(goal, root.Position)
		if distance < 45 and Combat.clearWide(root.Position, goal, radius()) then
			humanoid:MoveTo(goal)
			pathGoal = nil
		elseif pushThrough and distance < 18 and Combat.clearWide(root.Position, goal, radius(), true) then
			humanoid:MoveTo(goal) -- a barricade, not a wall: lean on it
		else
			followPath(goal, root, humanoid, pushThrough)
		end
	end

	-- No progress for a moment while trying to move: step aside, then replan.
	local function checkProgress(root: BasePart, goal: Vector3?)
		local now = os.clock()
		if (root.Position - progressFrom).Magnitude > 1.2 then
			progressFrom, progressAt = root.Position, now
			return
		end
		if goal and now - progressAt > 0.9 and not (detour and now < detourUntil) then
			detour = sidestep(root, goal)
			detourUntil = now + 0.7
			pathGoal = nil
			progressAt = now
		end
	end

	local function face(root: BasePart, humanoid: Humanoid, direction: Vector3?)
		if direction then
			humanoid.AutoRotate = false
			root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
			p.aim = direction
		else
			humanoid.AutoRotate = true
			local facing = Util.flatUnit(root.CFrame.LookVector)
			if facing then
				p.aim = facing
			end
		end
	end

	while Participants.get(p.id) == p do
		task.wait(level.think * random:NextNumber(0.85, 1.15))
		local root, humanoid = Participants.body(p)
		if not root or not humanoid then
			continue
		end
		look()
		local now = os.clock()
		local here = root.Position
		local phase = RoundManager.phase()

		local function wander()
			if not wanderGoal or now > wanderUntil or Util.flatDistance(wanderGoal, here) < 4 then
				wanderGoal = randomSpot()
				wanderUntil = now + random:NextNumber(6, 12)
			end
			goTo(wanderGoal :: Vector3, root, humanoid, false)
			checkProgress(root, wanderGoal)
		end

		if p.team == "Zombie" then
			face(root, humanoid, nil)
			-- Pick a human: close ones first, but spread out so the pack
			-- surrounds people instead of queueing behind each other.
			local best: Seen? = nil
			local bestScore = math.huge
			for _, entry in seenHumans do
				local d = Util.flatDistance(entry.position, here)
				if d <= level.sight and visible(entry, here) then
					local score = d
						+ 14 * chasers(entry.p, p.id)
						- (if chasing[p.id] == entry.p then 8 else 0)
					if score < bestScore then
						best, bestScore = entry, score
					end
				end
			end
			if best then
				chasing[p.id] = best.p
				local d = Util.flatDistance(best.position, here)
				local lead = best.velocity * level.lead * math.clamp(d / 25, 0, 1)
				local goal = best.position + lead
				lastSeen, lastSeenAt = goal, now
				goTo(goal, root, humanoid, true)
				checkProgress(root, goal)
			elseif lastSeen and now - lastSeenAt < level.memory then
				chasing[p.id] = nil
				goTo(lastSeen, root, humanoid, true)
				checkProgress(root, lastSeen)
			else
				chasing[p.id] = nil
				lastSeen = nil
				wander()
			end
			if now - progressAt > level.stuck then
				RoundManager.zombieReturn(p)
				progressAt = now
			end
			continue
		end
		chasing[p.id] = nil

		-- Human ----------------------------------------------------------------------
		local round = RoundManager.roundNumber()
		if phase == "Prep" and armedRound ~= round then
			armedRound = round -- one roll per round: only some bots start armed
			if not p.heldItem and random:NextNumber() < Config.BOT_WEAPON_CHANCE then
				ItemService.give(p, STARTER_WEAPONS[random:NextInteger(1, #STARTER_WEAPONS)])
			end
		end
		local item = Items.get(p.heldItem)

		-- The zombies this bot can see, and the closest one.
		local threats: { Seen } = {}
		local closest: Seen? = nil
		local closestDistance = math.huge
		for _, entry in seenZombies do
			if not entry.hidden or Util.flatDistance(entry.position, here) <= Config.BUSH_REVEAL_DISTANCE then
				local d = Util.flatDistance(entry.position, here)
				if d <= level.flee then
					table.insert(threats, entry)
				end
				if d < closestDistance then
					closest, closestDistance = entry, d
				end
			end
		end

		-- Armed: hold the weapon out toward a close zombie (it's solid) and swing.
		local guarding = false
		if closest and item then
			local reach = if item.kind == "Projectile"
				then 45
				else (item.reach or 5) * math.max(1, p.scale * 0.9) + 3
			if closestDistance <= reach then
				local aim = Util.flatUnit(closest.position + closest.velocity * 0.15 - here)
				if aim then
					guarding = item.kind == "Melee"
					face(root, humanoid, aim)
					ItemService.botUse(p, aim)
				end
			end
		end
		if not guarding then
			face(root, humanoid, nil)
		end

		local hidden = BushService.hidden(p)
		if hidden and (not closest or closestDistance > Config.BUSH_REVEAL_DISTANCE + 4) then
			humanoid:MoveTo(here) -- stay still and hope
		elseif #threats > 0 then
			local bush = if hider and not hidden then nearestBush(here, 30) else nil
			if bush and closest and Util.flatDistance(bush, here) < closestDistance * 0.8 then
				goTo(bush, root, humanoid, false)
				checkProgress(root, bush)
			else
				-- Escape: try directions, keep the ones our body fits through,
				-- and pick the spot farthest from where the zombies are going,
				-- preferring open ground over dead ends.
				local stride = 12 + p.scale * 2
				local candidates: { { spot: Vector3, score: number } } = {}
				for i = 0, level.directions - 1 do
					local angle = i / level.directions * math.pi * 2 + random:NextNumber(-0.15, 0.15)
					local spot = here + Vector3.new(math.cos(angle), 0, math.sin(angle)) * stride
					if inBounds(spot, 5) and Combat.clearWide(here, spot, radius()) then
						local score = math.huge
						for _, zombie in threats do
							local future = zombie.position + zombie.velocity * 0.6
							score = math.min(score, Util.flatDistance(spot, future))
						end
						table.insert(candidates, { spot = spot, score = score })
					end
				end
				table.sort(candidates, function(a, b)
					return a.score > b.score
				end)
				local best: Vector3? = nil
				local bestScore = -math.huge
				for i = 1, math.min(3, #candidates) do
					local c = candidates[i]
					local open = 0
					for j = 0, 3 do
						local angle = j / 4 * math.pi * 2
						if
							Combat.clearWide(
								c.spot,
								c.spot + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 10,
								radius()
							)
						then
							open += 1
						end
					end
					local score = c.score + open * 3
					if score > bestScore then
						best, bestScore = c.spot, score
					end
				end
				if best then
					humanoid:MoveTo(best)
					pathGoal = nil
				elseif closest then
					local step = sidestep(root, here + (here - closest.position))
					if step then
						humanoid:MoveTo(step)
					end
				end
			end
		elseif phase == "Prep" and not p.heldItem then
			local spot = nearestItem(here, 90)
			if spot then
				if Util.flatDistance(spot, here) < Config.PICKUP_RADIUS then
					ItemService.pickUp(p)
				else
					goTo(spot, root, humanoid, false)
					checkProgress(root, spot)
				end
			else
				wander()
			end
		else
			wander()
		end
	end
	chasing[p.id] = nil
end

-- Roster ----------------------------------------------------------------------------------

local active: { [number]: Participant } = {} -- roster index -> bot
local nextId = 0

local function randomSkin(team: Skins.Team): string
	local list = Skins.forTeam(team)
	return list[rng:NextInteger(1, #list)].id
end

-- Only a few bots dress up (Config.BOTS_WITH_SKINS); the rest look classic.
local function dressedUp(): number
	local count = 0
	for _, p in active do
		if p.humanSkin ~= Skins.DEFAULT_HUMAN then
			count += 1
		end
	end
	return count
end

local function addBot(index: number)
	local entry = ROSTER[index]
	local level = LEVELS[entry.level] or LEVELS[5]
	nextId += 1
	local p = Participants.add({
		id = "B" .. nextId,
		name = entry.name,
		isBot = true,
	})
	if dressedUp() < Config.BOTS_WITH_SKINS and rng:NextNumber() < 0.35 then
		repeat
			p.humanSkin = randomSkin("Human")
		until p.humanSkin ~= Skins.DEFAULT_HUMAN
	end
	p.adminSpeed = level.speed
	p.state:SetAttribute("BotLevel", entry.level)
	Participants.publish(p)
	if p.character then
		CharacterService.applyLook(p)
	end
	CharacterService.refreshSpeed(p)
	active[index] = p
	task.spawn(brain, p, level, nextId * 97 + os.time())
end

-- How many bots this round: a random count in range, leaving room for
-- real players.
local function wanted(): number
	local players = #Players:GetPlayers()
	local room = math.max(0, Config.MAX_PARTICIPANTS - players)
	return math.min(rng:NextInteger(Config.BOTS_MIN, Config.BOTS_MAX), room, #ROSTER)
end

local function rebalance()
	local target = wanted()
	local count = 0
	for _ in active do
		count += 1
	end
	-- Add in roster order (Mario Robles first), remove from the end.
	for index = 1, #ROSTER do
		if count >= target then
			break
		end
		if not active[index] then
			addBot(index)
			count += 1
		end
	end
	for index = #ROSTER, 2, -1 do
		if count <= target then
			break
		end
		local p = active[index]
		if p then
			active[index] = nil
			Participants.remove(p)
			count -= 1
		end
	end
end

function BotService.start()
	if not Config.BOTS then
		return
	end
	rebalance()
	print("[Bots] bots are playing. Set Config.BOTS = false to turn them off.")
	-- A fresh mix of bots for every round.
	local state = ReplicatedStorage:WaitForChild("BrainTagState")
	state:GetAttributeChangedSignal("Phase"):Connect(function()
		if state:GetAttribute("Phase") == "Prep" then
			rebalance()
		end
	end)
end

return BotService
