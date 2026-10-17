-- Studio-only test bots so you can play a full round alone. They count as
-- participants for every rule. Bot humans run from the nearest zombie (and
-- wander during prep); bot zombies chase the nearest human they can see
-- with PathfindingService and press "Z" when stuck. Anyone hiding in a bush
-- is invisible to bots until they come close.

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bushes = require(ReplicatedStorage.Shared.Bushes)
local BushService = require(script.Parent.BushService)
local Combat = require(script.Parent.Combat)
local Config = require(ReplicatedStorage.Shared.Config)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Participants = require(script.Parent.Participants)
local RoundManager = require(script.Parent.RoundManager)
local Util = require(ReplicatedStorage.Shared.Util)

type Participant = Participants.Participant

local BotService = {}

local NAMES = { "Mia", "Leo", "Zoe", "Max", "Ivy", "Sam", "Ada", "Kai" }

local function nearest(me: Participant, from: Vector3, team: string): (Vector3?, number)
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, other in Participants.onTeam(team :: Participants.Team) do
		if other ~= me then
			local root = Participants.body(other)
			if root and BushService.visibleFrom(other, from) then
				local d = Util.flatDistance(root.Position, from)
				if d < bestDistance then
					best, bestDistance = root.Position, d
				end
			end
		end
	end
	return best, bestDistance
end

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

local function brain(p: Participant, rng: Random)
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
	local hider = rng:NextNumber() < 0.5 -- some bot humans run for the bushes

	local function followPath(goal: Vector3, root: BasePart, humanoid: Humanoid)
		local now = os.clock()
		if not pathGoal or now - computedAt > 1.2 or (goal - pathGoal).Magnitude > 8 then
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

	while Participants.get(p.id) == p do
		task.wait(0.2)
		local root, humanoid = Participants.body(p)
		if not root or not humanoid then
			continue
		end
		local now = os.clock()
		if (root.Position - lastPosition).Magnitude > 1.5 then
			lastPosition = root.Position
			stuckSince = now
		end

		local function wander()
			if not wanderGoal or now > wanderUntil or Util.flatDistance(wanderGoal, root.Position) < 3 then
				wanderGoal = randomInside(rng)
				wanderUntil = now + rng:NextNumber(6, 12)
			end
			followPath(wanderGoal :: Vector3, root, humanoid)
		end

		if p.team == "Zombie" then
			local target, distance = nearest(p, root.Position, "Human")
			if target then
				if distance < 30 and Combat.clearPath(root.Position, target) then
					humanoid:MoveTo(target)
					pathGoal = nil
				else
					followPath(target, root, humanoid)
				end
			else
				wander() -- everyone left is hiding (or there's nobody yet)
			end
			if now - stuckSince > 6 then
				RoundManager.zombieReturn(p)
				stuckSince = now
				lastPosition = root.Position
			end
		else
			local threat, distance = nearest(p, root.Position, "Zombie")
			local hidden = BushService.hidden(p)
			local bush = if hider and not hidden then nearestBush(root.Position, 30) else nil
			if hidden and (not threat or distance > Config.BUSH_REVEAL_DISTANCE) then
				humanoid:MoveTo(root.Position) -- stay still and hope
				stuckSince = now
			elseif threat and distance < 45 and bush then
				followPath(bush, root, humanoid)
			elseif threat and distance < 45 then
				-- Try 12 directions and run toward the one farthest from zombies.
				local best: Vector3? = nil
				local bestScore = -math.huge
				for i = 0, 11 do
					local angle = i / 12 * math.pi * 2
					local candidate = root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 14
					if inBounds(candidate) and Combat.clearPath(root.Position, candidate) then
						local _, away = nearest(p, candidate, "Zombie")
						if away > bestScore then
							best, bestScore = candidate, away
						end
					end
				end
				humanoid:MoveTo(best or (root.Position + (root.Position - threat).Unit * 10))
				pathGoal = nil
			else
				wander()
			end
		end
	end
end

function BotService.start()
	if not (RunService:IsStudio() and Config.DEBUG_BOTS) then
		return
	end
	warn(
		string.format(
			"[Bots] Spawning %d test bots (Studio only). Set Config.DEBUG_BOTS = false to turn them off.",
			Config.DEBUG_BOT_COUNT
		)
	)
	for i = 1, Config.DEBUG_BOT_COUNT do
		local p = Participants.add({
			id = "B" .. i,
			name = "Bot " .. NAMES[(i - 1) % #NAMES + 1],
			isBot = true,
		})
		task.spawn(brain, p, Random.new(i * 97))
	end
end

return BotService
