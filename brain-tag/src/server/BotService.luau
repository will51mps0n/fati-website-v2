-- Studio-only test bots so you can play a full round alone. They count as
-- participants for every rule. Bot humans run from the nearest zombie (and
-- wander during prep); bot zombies chase the nearest human with
-- PathfindingService and press "Z" when stuck.

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
			if root then
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
	local list = if rng:NextNumber() < 0.6 then MapLayout.itemSpots else MapLayout.humanSpawns
	local spot = list[rng:NextInteger(1, #list)]
	return Vector3.new(spot.x, 2, spot.z)
end

local function inBounds(v: Vector3): boolean
	return MapLayout.inRect(MapLayout.BOUNDS, v.X, v.Z, -4)
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

		if p.team == "Zombie" then
			local target, distance = nearest(p, root.Position, "Human")
			if target then
				if distance < 30 and Combat.clearPath(root.Position, target) then
					humanoid:MoveTo(target)
					pathGoal = nil
				else
					followPath(target, root, humanoid)
				end
			end
			if now - stuckSince > 6 then
				RoundManager.zombieReturn(p)
				stuckSince = now
			end
		else
			local threat, distance = nearest(p, root.Position, "Zombie")
			if threat and distance < 45 then
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
				if
					not wanderGoal
					or now > wanderUntil
					or Util.flatDistance(wanderGoal, root.Position) < 3
				then
					wanderGoal = randomInside(rng)
					wanderUntil = now + rng:NextNumber(6, 12)
				end
				followPath(wanderGoal :: Vector3, root, humanoid)
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
