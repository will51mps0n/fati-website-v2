-- Bots that play every round with everyone (Config.BOTS). They count as
-- participants for every rule. Each has a difficulty level from 1 (dopey)
-- to 5 (Mario Robles):
--   * thinks faster, walks faster and sees farther
--   * as a zombie: leads its target, remembers where a human hid, and
--     presses "Z" sooner when stuck
--   * as a human: grabs items during prep (top levels "buy" one), swings at
--     zombies that get close, flees smarter and hides in bushes more

local PathfindingService = game:GetService("PathfindingService")
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
local Util = require(ReplicatedStorage.Shared.Util)

type Participant = Participants.Participant

local BotService = {}

type Level = {
	think: number, -- seconds between decisions
	speed: number, -- walk speed multiplier
	sight: number, -- zombie: how far away it notices humans
	lead: number, -- zombie: seconds of target movement it predicts
	memory: number, -- zombie: seconds it keeps chasing where a human vanished
	stuck: number, -- zombie: seconds stuck before pressing Z
	flee: number, -- human: zombie distance that starts a run
	directions: number, -- human: escape directions considered
	hide: number, -- human: chance to be a bush hider
	swing: number, -- human: chance per decision to swing at a close zombie
	grab: boolean, -- human: walks to items during prep
	buys: boolean, -- human: starts each round with a weapon
}

local LEVELS: { Level } = {
	{
		think = 0.45,
		speed = 0.82,
		sight = 35,
		lead = 0,
		memory = 0,
		stuck = 8,
		flee = 25,
		directions = 6,
		hide = 0.15,
		swing = 0,
		grab = false,
		buys = false,
	},
	{
		think = 0.3,
		speed = 0.9,
		sight = 55,
		lead = 0.15,
		memory = 1,
		stuck = 7,
		flee = 35,
		directions = 8,
		hide = 0.3,
		swing = 0.25,
		grab = false,
		buys = false,
	},
	{
		think = 0.2,
		speed = 0.97,
		sight = 85,
		lead = 0.35,
		memory = 2.5,
		stuck = 6,
		flee = 45,
		directions = 12,
		hide = 0.45,
		swing = 0.55,
		grab = true,
		buys = false,
	},
	{
		think = 0.12,
		speed = 1.04,
		sight = 140,
		lead = 0.5,
		memory = 4,
		stuck = 4.5,
		flee = 55,
		directions = 16,
		hide = 0.55,
		swing = 0.85,
		grab = true,
		buys = true,
	},
	{
		think = 0.07,
		speed = 1.12,
		sight = 500,
		lead = 0.7,
		memory = 7,
		stuck = 3,
		flee = 70,
		directions = 20,
		hide = 0.65,
		swing = 1,
		grab = true,
		buys = true,
	},
}

-- Name and difficulty. The first Config.BOT_COUNT of these join.
local ROSTER: { { name: string, level: number } } = {
	{ name = "Mario Robles", level = 5 },
	{ name = "Fart Butt", level = 2 },
	{ name = "Poop Face", level = 3 },
	{ name = "Fat Guy", level = 1 },
	{ name = "Booger Bob", level = 4 },
	{ name = "Stinky Pete", level = 3 },
	{ name = "Captain Wedgie", level = 2 },
	{ name = "Toilet Ted", level = 1 },
	{ name = "Sir Toots-a-Lot", level = 4 },
	{ name = "Sweaty Steve", level = 3 },
	{ name = "Moldy Cheese", level = 2 },
	{ name = "Burp Master", level = 4 },
}

-- Weapons the top bots "buy" at the start of a round.
local STARTER_WEAPONS = { "Bat", "Spear", "Swordfish", "FryingPan", "Katana", "Lollipop" }

local function randomInside(rng: Random): Vector3
	local layout = MapLayout.current()
	local list = if rng:NextNumber() < 0.6 then layout.itemSpots else layout.humanSpawns
	local spot = list[rng:NextInteger(1, #list)]
	return Vector3.new(spot.x, 2, spot.z)
end

local function inBounds(v: Vector3): boolean
	return MapLayout.inRect(MapLayout.current().bounds, v.X, v.Z, -4)
end

-- Center of the nearest bush within `range`, to hide in.
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

-- Nearest ground item within `range`.
local function nearestItem(from: Vector3, range: number): Vector3?
	local folder = workspace:FindFirstChild("GroundItems")
	if not folder then
		return nil
	end
	local best: Vector3? = nil
	local bestDistance = range
	for _, model in folder:GetChildren() do
		local x, z = model:GetAttribute("SpotX"), model:GetAttribute("SpotZ")
		if typeof(x) == "number" and typeof(z) == "number" then
			local spot = Vector3.new(x, from.Y, z)
			local d = Util.flatDistance(spot, from)
			if d < bestDistance then
				best, bestDistance = spot, d
			end
		end
	end
	return best
end

-- The nearest member of `team` this bot can notice: within `sight`, and
-- not hidden in a bush (unless close). Returns their root too.
local function nearest(me: Participant, from: Vector3, team: string, sight: number): (BasePart?, number)
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, other in Participants.onTeam(team :: Participants.Team) do
		if other ~= me then
			local root = Participants.body(other)
			if root and BushService.visibleFrom(other, from) then
				local d = Util.flatDistance(root.Position, from)
				if d < bestDistance and d <= sight then
					best, bestDistance = root, d
				end
			end
		end
	end
	return best, bestDistance
end

local function brain(p: Participant, level: Level, rng: Random)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 4,
		AgentCanJump = false,
		WaypointSpacing = 5,
	})
	local waypoints: { PathWaypoint } = {}
	local waypointIndex = 1
	local pathGoal: Vector3? = nil
	local computedAt = 0
	local wanderGoal: Vector3? = nil
	local wanderUntil = 0
	local lastPosition = Vector3.zero
	local stuckSince = os.clock()
	local hider = rng:NextNumber() < level.hide
	local lastSeen: Vector3? = nil -- zombie memory of a target that vanished
	local lastSeenAt = 0
	local armedRound = -1

	local function followPath(goal: Vector3, root: BasePart, humanoid: Humanoid)
		local now = os.clock()
		local refresh = math.max(0.4, level.think * 5)
		if not pathGoal or now - computedAt > refresh or (goal - pathGoal).Magnitude > 8 then
			pathGoal, computedAt = goal, now
			local ok = pcall(function()
				path:ComputeAsync(root.Position, goal)
			end)
			if ok and path.Status == Enum.PathStatus.Success then
				waypoints = path:GetWaypoints()
				waypointIndex = math.min(2, #waypoints)
			else
				waypoints = {}
			end
		end
		local waypoint = waypoints[waypointIndex]
		if waypoint then
			if Util.flatDistance(waypoint.Position, root.Position) < 2.5 and waypointIndex < #waypoints then
				waypointIndex += 1
				waypoint = waypoints[waypointIndex]
			end
			humanoid:MoveTo(waypoint.Position)
		else
			humanoid:MoveTo(goal)
		end
	end

	-- Walk straight when nothing is in the way (sharper), else pathfind.
	local function goTo(goal: Vector3, root: BasePart, humanoid: Humanoid)
		if Util.flatDistance(goal, root.Position) < 30 and Combat.clearPath(root.Position, goal) then
			humanoid:MoveTo(goal)
			pathGoal = nil
		else
			followPath(goal, root, humanoid)
		end
	end

	while Participants.get(p.id) == p do
		task.wait(level.think * rng:NextNumber(0.8, 1.2))
		local root, humanoid = Participants.body(p)
		if not root or not humanoid then
			continue
		end
		local now = os.clock()
		if (root.Position - lastPosition).Magnitude > 1.5 then
			lastPosition = root.Position
			stuckSince = now
		end
		local phase = RoundManager.phase()

		local function wander()
			if not wanderGoal or now > wanderUntil or Util.flatDistance(wanderGoal, root.Position) < 3 then
				wanderGoal = randomInside(rng)
				wanderUntil = now + rng:NextNumber(6, 12)
			end
			followPath(wanderGoal :: Vector3, root, humanoid)
		end

		if p.team == "Zombie" then
			local target, distance = nearest(p, root.Position, "Human", level.sight)
			if target then
				-- Aim where the human is going, not where they are.
				local lead = Util.flat(target.AssemblyLinearVelocity)
					* level.lead
					* math.min(1, distance / 20)
				local goal = target.Position + lead
				lastSeen, lastSeenAt = goal, now
				goTo(goal, root, humanoid)
			elseif lastSeen and now - lastSeenAt < level.memory then
				goTo(lastSeen, root, humanoid) -- check where they vanished
			else
				lastSeen = nil
				wander()
			end
			if now - stuckSince > level.stuck then
				RoundManager.zombieReturn(p)
				stuckSince = now
				lastPosition = root.Position
			end
			continue
		end

		-- Human ----------------------------------------------------------------------
		local round = RoundManager.roundNumber()
		if level.buys and phase == "Prep" and armedRound ~= round and not p.heldItem then
			armedRound = round
			ItemService.give(p, STARTER_WEAPONS[rng:NextInteger(1, #STARTER_WEAPONS)])
		end
		local item = Items.get(p.heldItem)
		local threat, distance = nearest(p, root.Position, "Zombie", math.huge)

		-- Swing at a zombie in reach.
		if
			threat
			and item
			and (item.kind == "Melee" or item.kind == "Blast" or item.kind == "Projectile")
		then
			local reach = if item.kind == "Projectile"
				then 40
				else (item.reach or 5) * math.max(1, p.scale * 0.9) + 2
			if distance <= reach and rng:NextNumber() < level.swing then
				local aim = Util.flatUnit(threat.Position - root.Position)
				if aim then
					ItemService.botUse(p, aim)
				end
			end
		end

		local hidden = BushService.hidden(p)
		local bush = if hider and not hidden then nearestBush(root.Position, 35) else nil
		if hidden and (not threat or distance > Config.BUSH_REVEAL_DISTANCE) then
			humanoid:MoveTo(root.Position) -- stay still and hope
		elseif threat and distance < level.flee and bush then
			followPath(bush, root, humanoid)
		elseif threat and distance < level.flee then
			-- Try several directions and run toward the one that keeps the
			-- most distance from every zombie (better bots look further).
			local stride = 10 + level.directions * 0.5
			local best: Vector3? = nil
			local bestScore = -math.huge
			for i = 0, level.directions - 1 do
				local angle = i / level.directions * math.pi * 2
				local candidate = root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * stride
				if inBounds(candidate) and Combat.clearPath(root.Position, candidate) then
					local _, away = nearest(p, candidate, "Zombie", math.huge)
					if away > bestScore then
						best, bestScore = candidate, away
					end
				end
			end
			humanoid:MoveTo(best or (root.Position + (root.Position - threat.Position).Unit * 10))
			pathGoal = nil
		elseif level.grab and phase == "Prep" and not p.heldItem then
			local spot = nearestItem(root.Position, 80)
			if spot then
				if Util.flatDistance(spot, root.Position) < Config.PICKUP_RADIUS then
					ItemService.pickUp(p)
				else
					goTo(spot, root, humanoid)
				end
			else
				wander()
			end
		else
			wander()
		end
		-- Hold the weapon out the way you're going (it's solid).
		local facing = Util.flatUnit(root.CFrame.LookVector)
		if facing then
			p.aim = facing
		end
	end
end

function BotService.start()
	if not Config.BOTS then
		return
	end
	local count = math.min(Config.BOT_COUNT, #ROSTER)
	print(string.format("[Bots] %d bots are playing. Set Config.BOTS = false to turn them off.", count))
	for i = 1, count do
		local entry = ROSTER[i]
		local level = LEVELS[math.clamp(entry.level, 1, #LEVELS)]
		local p = Participants.add({
			id = "B" .. i,
			name = entry.name,
			isBot = true,
		})
		p.adminSpeed = level.speed
		p.state:SetAttribute("BotLevel", entry.level)
		CharacterService.refreshSpeed(p)
		task.spawn(brain, p, level, Random.new(i * 97 + os.time()))
	end
end

return BotService
