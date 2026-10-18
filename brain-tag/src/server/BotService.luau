-- Bots that fill every round (Config.BOTS_MIN to BOTS_MAX of them, fewer
-- when real players join). They count as participants for every rule and
-- wear random skins. Each has a level from 3 to 6; Mario Robles is a 6 and
-- most of the roster is 5 or 6:
--   * zombies spread out over different humans, lead their target,
--     remember where a human hid, and circle round a weapon held out at
--     them instead of walking into it. A human they can't reach (barricaded in)
--     draws a crowd: the pack picks one door, lines up outside it and
--     shoves through together (pushers in a line add their strength)
--   * humans grab the odd item (some start with one), hold weapons out
--     toward close zombies (weapons are solid; a few can swing), flee
--     toward open ground or through doorways away from every zombie, juke
--     sideways when one is about to grab them, and hide in bushes
--   * on dark maps (MapThemes) nobody sees far and walls block the view; on
--     roofed maps nobody sees into a room they aren't in
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
local FurniturePush = require(ReplicatedStorage.Shared.FurniturePush)
local FurnitureService = require(script.Parent.FurnitureService)
local ItemService = require(script.Parent.ItemService)
local Items = require(ReplicatedStorage.Shared.Items)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local MapThemes = require(ReplicatedStorage.Shared.MapThemes)
local Participants = require(script.Parent.Participants)
local Roofs = require(ReplicatedStorage.Shared.Roofs)
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
	dodge: number, -- human: juke when a zombie closes in this near (0 = never)
	flank: boolean, -- zombie: circle round a held-out weapon
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
		dodge = 0,
		flank = false,
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
		dodge = 7,
		flank = true,
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
		dodge = 8,
		flank = true,
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
		dodge = 9.5,
		flank = true,
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

-- Barricades ---------------------------------------------------------------------------
-- A human the zombies can't reach is "fortified" for a few seconds: zombies
-- rally on them instead of spreading out, and break in through one door.
local fortified: { [Participant]: number } = setmetatable({}, { __mode = "k" }) :: any -- human -> until
local sieging: { [string]: { [string]: number } } = {} -- door -> bot id -> last push
local leaning: { [Participant]: number } = setmetatable({}, { __mode = "k" }) :: any -- bot -> last shove
local doorsOf = ""
local doorList: { MapLayout.Door } = {}

local function doors(): { MapLayout.Door }
	local layout = MapLayout.current()
	if doorsOf ~= layout.name then
		doorsOf = layout.name
		doorList = MapLayout.doors(layout)
		table.clear(sieging)
	end
	return doorList
end

local function doorKey(door: MapLayout.Door): string
	return string.format("%d,%d", math.floor(door.x + 0.5), math.floor(door.z + 0.5))
end

-- Unit vector across a door, toward the side `toward` is on.
local function across(door: MapLayout.Door, toward: Vector3): Vector3
	if door.horizontal then
		return Vector3.new(0, 0, if toward.Z >= door.z then 1 else -1)
	end
	return Vector3.new(if toward.X >= door.x then 1 else -1, 0, 0)
end

-- Zombies pushing on this door right now.
local function pushingDoor(key: string, now: number): number
	local count = 0
	local pushers: { [string]: number } = sieging[key] or {}
	for _, seen in pushers do
		if now - seen < 1 then
			count += 1
		end
	end
	return count
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

-- On a dark map nobody sees far and walls block the view; on a roofed map
-- nobody sees into a room they aren't in.
local function inSight(from: Vector3, to: Vector3, distance: number): boolean
	if not Roofs.canSee(from, to) then
		return false
	end
	local theme = MapThemes.get(MapLayout.current().theme)
	if not theme.dark then
		return true
	end
	return distance <= (theme.sight or 40) + 6 and Combat.canSee(from, to)
end

-- A human holding a weapon out at us: a spot round the side it isn't
-- pointing (the shaft only blocks straight ahead), or nil if we're already
-- beside or behind it. `wary` (just got hit or pushed off it): swing wider,
-- right round the back, out of reach.
local function flankAround(target: Seen, here: Vector3, wary: boolean?): Vector3?
	local item = Items.get(target.p.heldItem)
	if not item or item.kind ~= "Melee" then
		return nil
	end
	local aim = Util.flatUnit(target.p.aim)
	if not aim then
		return nil
	end
	local rel = Util.flat(here - target.position)
	local d = rel.Magnitude
	local reach = (item.reach or 5) * math.max(1, target.p.scale * 0.9)
	local front = if d > 0.5 then (rel / d):Dot(aim) else 0
	if d < 0.5 or d > reach + (if wary then 14 else 8) or front < (if wary then -0.2 else 0.35) then
		return nil
	end
	local side = Vector3.new(-aim.Z, 0, aim.X)
	local sign = if rel:Dot(side) >= 0 then 1 else -1
	if wary then
		-- Out of reach, round to the back.
		local around = (side * sign - aim * 0.9).Unit
		return target.position + around * (reach + 3)
	end
	local around = (side * sign - aim * 0.35).Unit
	return target.position + around * (reach * 0.75 + 2)
end

-- Rooms (inside houses, not yards) and their doorways ---------------------------------------

local function roomAt(x: number, z: number): MapLayout.Room?
	for _, room in MapLayout.current().rooms do
		if room.house ~= "" and MapLayout.inRect(room.rect, x, z) then
			return room
		end
	end
	return nil
end

type RoomDoor = { door: MapLayout.Door, center: Vector3, inward: Vector3 }

-- Each doorway of a room, with the unit vector pointing into the room.
local function doorsOfRoom(room: MapLayout.Room): { RoomDoor }
	local r = room.rect
	local out: { RoomDoor } = {}
	for _, door in doors() do
		local center = Vector3.new(door.x, 2, door.z)
		if door.horizontal and door.x > r.x1 and door.x < r.x2 then
			if math.abs(door.z - r.z1) < 0.6 then
				table.insert(out, { door = door, center = center, inward = Vector3.zAxis })
			elseif math.abs(door.z - r.z2) < 0.6 then
				table.insert(out, { door = door, center = center, inward = -Vector3.zAxis })
			end
		elseif not door.horizontal and door.z > r.z1 and door.z < r.z2 then
			if math.abs(door.x - r.x1) < 0.6 then
				table.insert(out, { door = door, center = center, inward = Vector3.xAxis })
			elseif math.abs(door.x - r.x2) < 0.6 then
				table.insert(out, { door = door, center = center, inward = -Vector3.xAxis })
			end
		end
	end
	return out
end

-- A room worth holing up in: walls round it, one or two doors, not a hallway.
local function goodHideout(room: MapLayout.Room): boolean
	local r = room.rect
	local doorsIn = #doorsOfRoom(room)
	return doorsIn >= 1
		and doorsIn <= 2
		and (r.x2 - r.x1) >= 14
		and (r.z2 - r.z1) >= 14
		and not string.find(string.lower(room.name), "hall")
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
	local pathFailed = false -- the last path asked for doesn't reach its goal
	local leanFrom = 0 -- when we started leaning on furniture that won't give
	type Siege = {
		door: MapLayout.Door,
		key: string,
		across: Vector3, -- unit, from outside the door toward the human
		center: Vector3,
		goal: Vector3,
		committed: boolean,
		startedAt: number,
		movedAt: number,
		from: Vector3,
	}
	local siege: Siege? = nil
	local badDoors: { [string]: number } = {} -- doors that wouldn't give -> until
	local dodgeSpot: Vector3? = nil
	local dodgeUntil, nextDodge = 0, 0
	-- Builders (more of the smarter bots) hole up in a room and barricade it.
	local builder = random:NextNumber() < (if level.flank then 0.55 else 0.2)
	local home: MapLayout.Room? = nil
	local homeRound = -1
	type Barricade = { body: BasePart, target: Vector3, key: string, startedAt: number }
	local barricade: Barricade? = nil
	local barricaded: { [string]: boolean } = {}
	local waryOf: Participant? = nil
	local waryUntil = 0

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
				pathFailed = false
			else
				waypoints = {}
				pathFailed = true
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

	-- Leaning on something that can give: furniture right where we're
	-- walking (in reach of body or arms), or the back of another zombie
	-- that is leaning on something (a queue: our strength adds to theirs).
	local function leaningOn(root: BasePart, humanoid: Humanoid): boolean
		local dir = Util.flatUnit(humanoid.MoveDirection)
		if not dir then
			return false
		end
		local probe, size = FurniturePush.moverProbe(root, dir, p.scale)
		if #FurnitureService.findInBox(probe, size + Vector3.new(0, 0, 1.5 * p.scale)) > 0 then
			return true
		end
		local now = os.clock()
		for _, entry in seenZombies do
			if entry.p ~= p and now - (leaning[entry.p] or 0) < 1 then
				local rel = Util.flat(entry.position - root.Position)
				local along = rel:Dot(dir)
				if along > 0.5 and along < 4 * p.scale and (rel - dir * along).Magnitude < 2.5 * p.scale then
					return true
				end
			end
		end
		return false
	end

	-- No progress for a moment while trying to move: step aside, then
	-- replan. A zombie leaning on furniture keeps shoving for a while
	-- instead (the others are on their way to help).
	local function checkProgress(root: BasePart, goal: Vector3?, humanoid: Humanoid)
		local now = os.clock()
		if (root.Position - progressFrom).Magnitude > 1.2 then
			progressFrom, progressAt = root.Position, now
			leanFrom = 0
			return
		end
		if goal and now - progressAt > 0.9 and not (detour and now < detourUntil) then
			if p.team == "Zombie" and leaningOn(root, humanoid) then
				if leanFrom == 0 then
					leanFrom = now
				end
				if now - leanFrom < 6 then
					progressAt = now
					leaning[p] = now
					local target = chasing[p.id]
					if target then
						fortified[target] = now + 8
					end
					return
				end
			end
			leanFrom = 0
			detour = sidestep(root, goal)
			detourUntil = now + 0.7
			pathGoal = nil
			progressAt = now
		end
	end

	-- Breaking in. When no path reaches `goal` and walls stand between us,
	-- furniture is blocking every way in: walk to just outside the door
	-- closest to it (the door the other zombies already use, if any), then
	-- shove straight through. Returns false when there's nothing to break.
	local function breach(goal: Vector3, root: BasePart, humanoid: Humanoid): boolean
		local now = os.clock()
		local here = root.Position
		local r = radius()
		local s = siege
		if s and Util.flatDistance(s.goal, goal) > 15 then
			s = nil
		end
		if not s then
			local failed = pathFailed
				and pathGoal ~= nil
				and Util.flatDistance(pathGoal :: Vector3, goal) < 10
			if not failed or Combat.clearWide(here, goal, r, true) then
				siege = nil
				return false
			end
			local best: MapLayout.Door? = nil
			local bestScore = math.huge
			for _, door in doors() do
				local key = doorKey(door)
				if (badDoors[key] or 0) > now or door.width < r * 2 + 0.6 then
					continue
				end
				local center = Vector3.new(door.x, here.Y, door.z)
				local d = Util.flatDistance(center, goal)
				if d > 70 then
					continue
				end
				local n = across(door, goal)
				if not Combat.clearWide(center + n * 2.5, goal, r * 0.8, true) then
					continue -- this door doesn't lead to them
				end
				local outside = center - n * (4 + r)
				local score = d + 0.5 * Util.flatDistance(outside, here) - 12 * pushingDoor(key, now)
				if score < bestScore then
					best, bestScore = door, score
				end
			end
			if not best then
				return false
			end
			s = {
				door = best,
				key = doorKey(best),
				across = across(best, goal),
				center = Vector3.new(best.x, here.Y, best.z),
				goal = goal,
				committed = false,
				startedAt = now,
				movedAt = now,
				from = here,
			}
		end
		assert(s, "siege")
		siege = s
		s.goal = goal
		local target = chasing[p.id]
		if target then
			fortified[target] = now + 8
		end

		local rel = Util.flat(here - s.center)
		local into = rel:Dot(s.across)
		local side = (rel - s.across * into).Magnitude
		if into > 1 + r and into < 10 and side < s.door.width / 2 + 2 then
			siege = nil -- through the door: go get them
			return false
		end
		if not s.committed then
			local outside = s.center - s.across * (4 + r)
			-- Close enough to join the line (zombies already queued there are
			-- in the way of the exact spot): lean in behind them.
			local near = Util.flatDistance(outside, here) < 8 + 2 * r
				or (into > -(5 + r) and into < 1 and side < s.door.width / 2)
			if near and Combat.clearWide(here, s.center, r * 0.8, true) then
				s.committed, s.movedAt, s.from = true, now, here
			else
				goTo(outside, root, humanoid, true)
				checkProgress(root, outside, humanoid)
				if now - s.startedAt > 20 then
					badDoors[s.key] = now + 10 -- can't get to that door
					siege = nil
				end
				return true
			end
		end
		-- Lined up: lean straight in through the doorway, no sidestepping.
		local pushers = sieging[s.key] or {}
		sieging[s.key] = pushers
		pushers[p.id] = now
		leaning[p] = now
		detour = nil
		humanoid:MoveTo(s.center + s.across * (5 + r))
		progressAt = now
		if (here - s.from).Magnitude > 1 then
			s.from, s.movedAt = here, now
		end
		if now - s.movedAt > 8 then
			badDoors[s.key] = now + 12 -- it won't give: try another way
			siege = nil
		end
		return true
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
				-- On roofed maps nobody can see into rooms: zombies go and look.
				if p.team == "Zombie" and MapLayout.current().roofs then
					local rooms = {}
					for _, room in MapLayout.current().rooms do
						if room.house ~= "" then
							table.insert(rooms, room)
						end
					end
					if #rooms > 0 then
						local r = rooms[random:NextInteger(1, #rooms)].rect
						wanderGoal = Vector3.new((r.x1 + r.x2) / 2, 2, (r.z1 + r.z2) / 2)
						wanderUntil = now + random:NextNumber(5, 9)
					end
				end
			end
			goTo(wanderGoal :: Vector3, root, humanoid, false)
			checkProgress(root, wanderGoal, humanoid)
		end

		if p.team == "Zombie" then
			face(root, humanoid, nil)
			-- Pick a human: close ones first, but spread out so the pack
			-- surrounds people instead of queueing behind each other.
			local best: Seen? = nil
			local bestScore = math.huge
			-- A barricaded human pulls the pack together instead (up to 6).
			for _, entry in seenHumans do
				local d = Util.flatDistance(entry.position, here)
				if d <= level.sight and visible(entry, here) and inSight(here, entry.position, d) then
					local others = chasers(entry.p, p.id)
					local rally = (fortified[entry.p] or 0) > now and others < 6
					local score = d
						+ (if rally then -15 - 10 * others else 14 * others)
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
				-- Just got hit, or held off a weapon? Be wary of that human for a
				-- while: no more running straight back into it.
				if now < p.knockedUntil + 0.3 or now < p.pressedUntil then
					waryOf, waryUntil = best.p, now + 5
				end
				local wary = waryOf == best.p and now < waryUntil
				-- Holding a weapon out at us? Go round it.
				local around = if level.flank or wary then flankAround(best, here, wary) else nil
				if around and inBounds(around, 3) then
					goal = around
				end
				if not breach(best.position, root, humanoid) then
					goTo(goal, root, humanoid, true)
					checkProgress(root, goal, humanoid)
				end
			elseif lastSeen and now - lastSeenAt < level.memory then
				chasing[p.id] = nil
				if not breach(lastSeen, root, humanoid) then
					goTo(lastSeen, root, humanoid, true)
					checkProgress(root, lastSeen, humanoid)
				end
			else
				chasing[p.id] = nil
				lastSeen = nil
				siege = nil
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
			local d = Util.flatDistance(entry.position, here)
			local seen = not entry.hidden or d <= Config.BUSH_REVEAL_DISTANCE
			if seen and inSight(here, entry.position, d) then
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

		-- A zombie about to grab us: juke sideways so it overshoots (then a
		-- moment before the next juke, or nobody could ever be caught).
		if dodgeSpot and now < dodgeUntil then
			humanoid:MoveTo(dodgeSpot)
			continue
		end
		dodgeSpot = nil
		if
			closest
			and level.dodge > 0
			and now >= nextDodge
			and closestDistance < level.dodge + p.scale * 1.5
		then
			local rel = Util.flat(here - closest.position)
			local away = if rel.Magnitude > 0.1 then rel.Unit else Vector3.xAxis
			if closest.velocity:Dot(away) > 6 then
				local side = Vector3.new(-away.Z, 0, away.X)
				local first = if random:NextNumber() < 0.5 then 1 else -1
				local order: { number } = { first, -first }
				for _, sign in order do
					local spot = here + side * sign * 8 + away * 2
					if inBounds(spot, 4) and Combat.clearWide(here, spot, radius()) then
						dodgeSpot, dodgeUntil, nextDodge = spot, now + 0.4, now + 1.6
						break
					end
				end
				if dodgeSpot then
					humanoid:MoveTo(dodgeSpot)
					pathGoal = nil
					continue
				end
			end
		end

		-- Builders: hole up in a room, shove furniture into its doorways, and
		-- lean on the barricade when a zombie comes knocking.
		if builder and (phase == "Prep" or phase == "Infection") then
			if homeRound ~= round then
				homeRound, home, barricade = round, nil, nil
				table.clear(barricaded)
			end
			local threatInside = closest ~= nil
				and closestDistance < 16
				and home ~= nil
				and roomAt(closest.position.X, closest.position.Z) == home
			if not home and phase == "Prep" then
				local best: MapLayout.Room? = nil
				local bestDistance = 140
				for _, room in MapLayout.current().rooms do
					local r = room.rect
					local d =
						Util.flatDistance(Vector3.new((r.x1 + r.x2) / 2, here.Y, (r.z1 + r.z2) / 2), here)
					if room.house ~= "" and d < bestDistance and goodHideout(room) then
						best, bestDistance = room, d
					end
				end
				home = best
			end
			local myHome = home
			if myHome and not threatInside then
				local r = myHome.rect
				local middle = Vector3.new((r.x1 + r.x2) / 2, here.Y, (r.z1 + r.z2) / 2)
				local inside = roomAt(here.X, here.Z) == myHome
				local roomDoors = doorsOfRoom(myHome)
				local handled = false
				if not inside then
					if not closest or closestDistance > 20 then
						goTo(middle, root, humanoid, false)
						checkProgress(root, middle, humanoid)
						handled = true
					end
				else
					-- A zombie at one of our doors: lean on the barricade.
					for _, entry in roomDoors do
						if closest and Util.flatDistance(closest.position, entry.center) < 12 then
							humanoid:MoveTo(entry.center)
							handled = true
							break
						end
					end
					-- Otherwise finish the barricades.
					if not handled and (not closest or closestDistance > 18) then
						if not barricade then
							for _, entry in roomDoors do
								local key = doorKey(entry.door)
								if barricaded[key] then
									continue
								end
								local block = CFrame.new(entry.center + entry.inward * 3)
								if
									#FurnitureService.findInBox(
										block,
										Vector3.new(entry.door.width + 1, 4, 4)
									) > 0
								then
									barricaded[key] = true -- already blocked
									continue
								end
								local piece: BasePart? = nil
								local pieceDistance = 30
								for _, body in FurnitureService.piecesNear(entry.center, 30) do
									local d = Util.flatDistance(body.Position, entry.center)
									if
										FurnitureService.weightOf(body) ~= "Massive"
										and d > 4
										and d < pieceDistance
										and MapLayout.inRect(r, body.Position.X, body.Position.Z)
									then
										piece, pieceDistance = body, d
									end
								end
								if piece then
									local depth = FurniturePush.extent(piece, entry.inward)
									barricade = {
										body = piece,
										target = Util.flat(entry.center + entry.inward * (depth + 1.6)),
										key = key,
										startedAt = now,
									}
									break
								end
								barricaded[key] = true -- nothing to block it with
							end
						end
						local job = barricade
						if job then
							local body = job.body
							local at = Util.flat(body.Position)
							local toTarget = job.target - at
							if body.Parent == nil or toTarget.Magnitude < 2.2 or now - job.startedAt > 14 then
								barricaded[job.key] = true
								barricade = nil
							else
								-- Get behind the piece, then walk it to the doorway.
								local push = toTarget.Unit
								local behind = at - push * (FurniturePush.extent(body, push) + radius() + 1.2)
								if Util.flatDistance(behind, here) > 2.5 then
									goTo(Vector3.new(behind.X, here.Y, behind.Z), root, humanoid, false)
								else
									humanoid:MoveTo(
										Vector3.new(job.target.X, here.Y, job.target.Z) + push * 2
									)
								end
								handled = true
							end
						end
					end
					if not handled then
						-- Wait well back from the doors.
						local away = Vector3.zero
						for _, entry in roomDoors do
							away += entry.inward
						end
						local spot = middle + (if away.Magnitude > 0.1 then away.Unit else Vector3.zero) * 4
						humanoid:MoveTo(spot)
						handled = true
					end
				end
				if handled then
					continue
				end
			end
		end

		local hidden = BushService.hidden(p)
		if hidden and (not closest or closestDistance > Config.BUSH_REVEAL_DISTANCE + 4) then
			humanoid:MoveTo(here) -- stay still and hope
		elseif #threats > 0 then
			local bush = if hider and not hidden then nearestBush(here, 30) else nil
			if bush and closest and Util.flatDistance(bush, here) < closestDistance * 0.8 then
				goTo(bush, root, humanoid, false)
				checkProgress(root, bush, humanoid)
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
				-- Doorways too: straight through one into the room (or out of it),
				-- which zombies have to funnel through after us.
				for _, door in doors() do
					local center = Vector3.new(door.x, here.Y, door.z)
					if Util.flatDistance(center, here) < 28 then
						local beyond = center + across(door, center * 2 - here) * 7
						if inBounds(beyond, 5) and Combat.clearWide(here, beyond, radius()) then
							local score = math.huge
							for _, zombie in threats do
								local future = zombie.position + zombie.velocity * 0.6
								score = math.min(score, Util.flatDistance(beyond, future))
							end
							table.insert(candidates, { spot = beyond, score = score + 4 })
						end
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
					checkProgress(root, spot, humanoid)
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
