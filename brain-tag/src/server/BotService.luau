-- Bots that fill every round (Config.BOTS_MIN to BOTS_MAX of them, fewer
-- when real players join). They count as participants for every rule and
-- wear random skins. Each has a level from 3 to 6; Mario Robles is a 6 and
-- most of the roster is 5 or 6:
--   * zombies spread out over different humans, lead their target,
--     remember where a human hid, and circle round a weapon held out at
--     them instead of walking into it. A human they can't reach (barricaded in)
--     draws a crowd: the pack picks one door, lines up outside it and
--     shoves through together (pushers in a line add their strength)
--   * zombies with nobody in sight hunt: they split up to check bushes (and
--     rooms on roofed maps), and a second zombie on the same human cuts it
--     off from the side instead of trailing behind
--   * every round each human bot takes a role. Builders team up in one room
--     (a fort), split its doors between them, shove furniture into the
--     doorways (two get behind a piece too heavy for one) and lean on the
--     barricade when a zombie knocks. Hiders each pick their own bush before
--     the outbreak and keep still in it. Runners keep away from the zombies.
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
local RunService = game:GetService("RunService")

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
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
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

-- Teams of human bots, reset every round. A fort is a room builders share:
-- who is in it, which doors are done, and the pieces being pushed into
-- doorways (with whoever is pushing each one).
type Job = {
	body: BasePart,
	target: Vector3,
	key: string,
	startedAt: number,
	pushers: { [string]: number }, -- bot id -> last push
	done: boolean,
}
type Fort = { members: { [string]: number }, barricaded: { [string]: boolean }, jobs: { Job } }
local forts: { [MapLayout.Room]: Fort } = {}
local bushTaken: { [BasePart]: string } = {} -- leaves -> the hider bot that picked it
local bushChecked: { [BasePart]: number } = {} -- leaves -> when a zombie last went to look
local teamsRound = -1

local function teamsFor(round: number)
	if teamsRound ~= round then
		teamsRound = round
		table.clear(forts)
		table.clear(bushTaken)
		table.clear(bushChecked)
	end
end

local function fortOf(room: MapLayout.Room): Fort
	local fort = forts[room]
	if not fort then
		fort = { members = {}, barricaded = {}, jobs = {} }
		forts[room] = fort
	end
	return fort
end

local function count(list: { [string]: number }, now: number, within: number): number
	local n = 0
	for _, seen in list do
		if now - seen < within then
			n += 1
		end
	end
	return n
end

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

-- The nearest bush no other hider has picked, away from the zombies.
local function freeBush(p: Participant, from: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = 160
	for _, leaves in Bushes.leaves() do
		local owner = bushTaken[leaves]
		if owner and owner ~= p.id then
			continue
		end
		local d = Util.flatDistance(leaves.Position, from)
		if d >= bestDistance then
			continue
		end
		local safe = true
		for _, zombie in seenZombies do
			if Util.flatDistance(zombie.position, leaves.Position) < 25 then
				safe = false
				break
			end
		end
		if safe then
			best, bestDistance = leaves, d
		end
	end
	if best then
		bushTaken[best] = p.id
	end
	return best
end

-- The nearest bush no zombie has looked in lately (zombies hunting).
local function bushToCheck(from: Vector3, now: number): BasePart?
	local best: BasePart? = nil
	local bestDistance = 110
	for _, leaves in Bushes.leaves() do
		local d = Util.flatDistance(leaves.Position, from)
		if d < bestDistance and now - (bushChecked[leaves] or -math.huge) > 25 then
			best, bestDistance = leaves, d
		end
	end
	return best
end

-- Item spot ("x,z") -> { bot id, when }: each bot heads for a different item.
local itemClaims: { [string]: { id: string, at: number } } = {}

local function nearestItem(from: Vector3, range: number, botId: string): Vector3?
	local folder = workspace:FindFirstChild("GroundItems")
	if not folder then
		return nil
	end
	local now = os.clock()
	local best: Vector3? = nil
	local bestKey = ""
	local bestDistance = range
	for _, model in folder:GetChildren() do
		local x, z = model:GetAttribute("SpotX"), model:GetAttribute("SpotZ")
		local item = Items.get(model:GetAttribute("ItemId") :: string?)
		-- Bots leave the good stuff for players: only cheap, common items.
		local common = item ~= nil
			and not item.isRare
			and (item.price or math.huge) <= Config.BOT_MAX_ITEM_PRICE
		if common and typeof(x) == "number" and typeof(z) == "number" then
			local key = string.format("%d,%d", math.floor(x + 0.5), math.floor(z + 0.5))
			local claim = itemClaims[key]
			if claim and claim.id ~= botId and now - claim.at < 4 then
				continue -- another bot is already on its way
			end
			local spot = Vector3.new(x, from.Y, z)
			local d = Util.flatDistance(spot, from)
			if d < bestDistance then
				best, bestKey, bestDistance = spot, key, d
			end
		end
	end
	if best then
		itemClaims[bestKey] = { id = botId, at = now }
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
	local reach = (item.reach or 5) * Items.reachScale(target.p.scale)
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

-- Where each bot was last told to walk, and when. The drive loop below moves
-- bots toward it at full speed, so it doesn't depend on what the Humanoid
-- reports while walking.
local walkGoal: { [Humanoid]: Vector3 } = setmetatable({}, { __mode = "k" }) :: any
local walkAt: { [Humanoid]: number } = setmetatable({}, { __mode = "k" }) :: any
local stopped: { [Humanoid]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- arrived and standing

local function moveTo(humanoid: Humanoid, point: Vector3)
	walkAt[humanoid] = os.clock()
	local old = walkGoal[humanoid]
	if old and stopped[humanoid] and Util.flatDistance(old, point) < 0.8 then
		return -- already standing there: stay put instead of twitching
	end
	humanoid:MoveTo(point)
	walkGoal[humanoid] = point
	stopped[humanoid] = nil
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
	-- A role for each round (human): Builders team up in a fort, Hiders take a
	-- bush of their own, Runners keep away from the zombies.
	local role: "Builder" | "Hider" | "Runner" = "Runner"
	local roleRound = -1
	local myBush: BasePart? = nil
	local home: MapLayout.Room? = nil
	local homeRound = -1
	local barricade: Job? = nil
	local waryOf: Participant? = nil
	local waryUntil = 0
	-- Zombies chasing alongside another zombie cut in from this side.
	local cutSide = if random:NextNumber() < 0.5 then 1 else -1

	local function radius(): number
		return math.min(0.9 * p.scale, Config.CHARACTER.MaxRootWidth / 2)
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
				AgentRadius = math.min(1.4 * p.scale, Config.CHARACTER.MaxRootWidth / 2 + 0.3),
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
			-- Next waypoint well before reaching this one, so a bot never
			-- arrives (and stops) between two decisions.
			and Util.flatDistance(waypoint.Position, root.Position) < math.max(
				2,
				humanoid.WalkSpeed * level.think * 1.6
			)
			and waypointIndex < #waypoints
		then
			waypointIndex += 1
			waypoint = waypoints[waypointIndex]
		end
		if waypoint then
			moveTo(humanoid, waypoint.Position)
		elseif pushThrough and Combat.clearWide(root.Position, goal, radius(), true) then
			moveTo(humanoid, goal) -- only furniture in the way: shove through it
		else
			local step = sidestep(root, goal)
			if step then
				moveTo(humanoid, step)
			end
		end
	end

	-- Straight there when the way is open for our whole body, else a path.
	local function goTo(goal: Vector3, root: BasePart, humanoid: Humanoid, pushThrough: boolean)
		local now = os.clock()
		if detour and now < detourUntil then
			moveTo(humanoid, detour)
			return
		end
		detour = nil
		local distance = Util.flatDistance(goal, root.Position)
		if distance < 45 and Combat.clearWide(root.Position, goal, radius()) then
			moveTo(humanoid, goal)
			pathGoal = nil
		elseif pushThrough and distance < 18 and Combat.clearWide(root.Position, goal, radius(), true) then
			moveTo(humanoid, goal) -- a barricade, not a wall: lean on it
		else
			followPath(goal, root, humanoid, pushThrough)
		end
	end

	-- What we're leaning on, if anything can give: furniture right where
	-- we're walking (in reach of body or arms), or the back of another
	-- zombie that is leaning on something (a queue: our strength adds to
	-- theirs). Returns the piece (nil for a queue) and whether other zombies
	-- are shoving with us.
	local function leaningOn(root: BasePart, humanoid: Humanoid): (boolean, BasePart?, boolean)
		local dir = Util.flatUnit(humanoid.MoveDirection)
		if not dir then
			return false, nil, false
		end
		local now = os.clock()
		local helped = false
		for _, entry in seenZombies do
			if
				entry.p ~= p
				and now - (leaning[entry.p] or 0) < 1
				and Util.flatDistance(entry.position, root.Position) < 9 * p.scale
			then
				helped = true
			end
		end
		local probe, size = FurniturePush.moverProbe(root, dir, p.scale)
		local found = FurnitureService.findInBox(probe, size + Vector3.new(0, 0, 1.5 * p.scale))
		if #found > 0 then
			return true, found[1], helped
		end
		for _, entry in seenZombies do
			if entry.p ~= p and now - (leaning[entry.p] or 0) < 1 then
				local rel = Util.flat(entry.position - root.Position)
				local along = rel:Dot(dir)
				if along > 0.5 and along < 4 * p.scale and (rel - dir * along).Magnitude < 2.5 * p.scale then
					return true, nil, true
				end
			end
		end
		return false, nil, false
	end

	-- A spot just past the side of a piece that won't give, on the side
	-- nearer the goal: walk round it instead of into it.
	local function roundPiece(body: BasePart, root: BasePart, goal: Vector3): Vector3?
		local here = root.Position
		local dir = Util.flatUnit(goal - here)
		if not dir then
			return nil
		end
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local reach = FurniturePush.extent(body, side) + FurniturePush.bumperRadius(p.scale) + 1
		local center = Vector3.new(body.Position.X, here.Y, body.Position.Z)
		local best: Vector3? = nil
		local bestDistance = math.huge
		for _, sign in { 1, -1 } do
			local spot = center + side * sign * reach + dir * 1.5
			if inBounds(spot, 3) and Combat.clearWide(here, spot, radius()) then
				local d = Util.flatDistance(spot, goal)
				if d < bestDistance then
					best, bestDistance = spot, d
				end
			end
		end
		return best
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
			local leant, piece, helped = false, nil, false
			if p.team == "Zombie" then
				leant, piece, helped = leaningOn(root, humanoid)
			end
			if leant then
				if leanFrom == 0 then
					leanFrom = now
				end
				-- Keep shoving while the pack is on it with us (or on its way);
				-- alone against a piece that won't budge, go round it soon.
				if now - leanFrom < (if helped then 6 else 2) then
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
			detour = (if piece then roundPiece(piece, root, goal) else nil) or sidestep(root, goal)
			detourUntil = now + (if piece then 1 else 0.7)
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
		moveTo(humanoid, s.center + s.across * (5 + r))
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
		teamsFor(RoundManager.roundNumber())

		-- Distance from a spot to the nearest zombie we can see.
		local function zombieGap(spot: Vector3): number
			local gap = math.huge
			for _, zombie in seenZombies do
				gap = math.min(gap, Util.flatDistance(zombie.position, spot))
			end
			return gap
		end

		local function wander()
			local due = not wanderGoal or now > wanderUntil or Util.flatDistance(wanderGoal, here) < 4
			-- A human heading somewhere a zombie now stands picks again.
			if
				not due
				and p.team == "Human"
				and phase == "Infection"
				and zombieGap(wanderGoal :: Vector3) < 20
			then
				due = true
			end
			if due then
				wanderGoal = randomSpot()
				wanderUntil = now + random:NextNumber(6, 12)
				if p.team == "Zombie" then
					-- Hunting: zombies split up to check the bushes, and on roofed
					-- maps (nobody can see into rooms) they go and look in rooms.
					local roofed = MapLayout.current().roofs
					local bush = if random:NextNumber() < (if roofed then 0.4 else 0.65)
						then bushToCheck(here, now)
						else nil
					if bush then
						bushChecked[bush] = now
						wanderGoal = Vector3.new(bush.Position.X, 2, bush.Position.Z)
						wanderUntil = now + random:NextNumber(6, 10)
					elseif roofed then
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
				elseif phase == "Prep" then
					-- Before the outbreak people scatter: of a few spots, the one
					-- with the fewest others around it.
					local function crowd(spot: Vector3): number
						local n = 0
						for _, entry in seenHumans do
							if entry.p ~= p and Util.flatDistance(entry.position, spot) < 25 then
								n += 1
							end
						end
						return n
					end
					local best, bestCrowd = wanderGoal, crowd(wanderGoal :: Vector3)
					for _ = 1, 4 do
						local spot = randomSpot()
						local n = crowd(spot)
						if n < bestCrowd then
							best, bestCrowd = spot, n
						end
					end
					wanderGoal = best
				elseif phase == "Infection" then
					-- Runners: of a few spots, the one farthest from the zombies.
					local best, bestGap = wanderGoal, zombieGap(wanderGoal :: Vector3)
					for _ = 1, 4 do
						local spot = randomSpot()
						local gap = zombieGap(spot)
						if gap > bestGap then
							best, bestGap = spot, gap
						end
					end
					wanderGoal = best
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
				-- Another zombie is already on them: cut in from the side ahead
				-- of them instead of trailing behind it.
				if chasers(best.p, p.id) > 0 and d > 10 and d < 70 and best.velocity.Magnitude > 4 then
					local ahead = best.velocity.Unit
					local side = Vector3.new(-ahead.Z, 0, ahead.X) * cutSide
					local cut = best.position
						+ best.velocity * (level.lead * 1.6)
						+ side * math.min(12, d * 0.4)
					if inBounds(cut, 3) and Combat.clearWide(here, cut, radius()) then
						goal = cut
					end
				end
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
		if roleRound ~= round then
			roleRound = round
			local roll = random:NextNumber()
			local builders = if level.flank then 0.5 else 0.25
			role = if roll < builders
				then "Builder"
				elseif roll < builders + level.hide * 0.7 then "Hider"
				else "Runner"
			myBush = nil
		end
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
				else (item.reach or 5) * Items.reachScale(p.scale) + 3
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
			moveTo(humanoid, dodgeSpot)
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
					moveTo(humanoid, dodgeSpot)
					pathGoal = nil
					continue
				end
			end
		end

		-- Builders team up in a fort: they hole up in one room, split its
		-- doorways, shove furniture into them (two get behind a piece too
		-- heavy for one), and lean on the barricade when a zombie knocks.
		if role == "Builder" and (phase == "Prep" or phase == "Infection") then
			if homeRound ~= round then
				homeRound, home, barricade = round, nil, nil
			end
			local threatInside = closest ~= nil
				and closestDistance < 16
				and home ~= nil
				and roomAt(closest.position.X, closest.position.Z) == home
			if not home and phase == "Prep" then
				-- The nearest good room, but join teammates already holing up
				-- somewhere close (up to three to a fort). Claimed at once, so
				-- the builders picking right after us see it.
				local best: MapLayout.Room? = nil
				local bestScore = math.huge
				for _, room in MapLayout.current().rooms do
					local r = room.rect
					local d =
						Util.flatDistance(Vector3.new((r.x1 + r.x2) / 2, here.Y, (r.z1 + r.z2) / 2), here)
					if room.house ~= "" and d < 160 and goodHideout(room) then
						local mates = count(fortOf(room).members, now, 3)
						local score = d
							- (if mates > 0 and mates < 3 then 40 else 0)
							+ (if mates >= 3 then 400 else 0)
						if score < bestScore then
							best, bestScore = room, score
						end
					end
				end
				home = best
				if best then
					fortOf(best).members[p.id] = now
				end
			end
			local myHome = home
			if myHome and not threatInside then
				local fort = fortOf(myHome)
				fort.members[p.id] = now
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
					-- A zombie at one of our doors: everyone leans on that barricade.
					for _, entry in roomDoors do
						if closest and Util.flatDistance(closest.position, entry.center) < 12 then
							moveTo(humanoid, entry.center)
							handled = true
							break
						end
					end
					-- Otherwise finish the barricades.
					if not handled and (not closest or closestDistance > 18) then
						local job = barricade
						if job and job.done then
							job = nil
						end
						if not job then
							-- Help a teammate behind a piece too heavy to push alone.
							local alone = RoundRules.pushStrength(p.scale)
							for _, other in fort.jobs do
								if
									not other.done
									and other.body.Parent
									and count(other.pushers, now, 1) == 1
									and RoundRules.pushFraction(FurniturePush.mass(other.body), alone)
										< 0.45
								then
									job = other
									break
								end
							end
						end
						if not job then
							-- Our own doorway: one no teammate is already blocking.
							local busy: { [string]: boolean } = {}
							local used: { [BasePart]: boolean } = {}
							for _, other in fort.jobs do
								if not other.done then
									busy[other.key] = true
									used[other.body] = true
								end
							end
							for _, entry in roomDoors do
								local key = doorKey(entry.door)
								if fort.barricaded[key] or busy[key] then
									continue
								end
								local block = CFrame.new(entry.center + entry.inward * 3)
								if
									#FurnitureService.findInBox(
										block,
										Vector3.new(entry.door.width + 1, 4, 4)
									) > 0
								then
									fort.barricaded[key] = true -- already blocked
									continue
								end
								-- Close pieces that cover the doorway well (not the
								-- immovable ones, and not one a teammate is using).
								local along = if entry.door.horizontal then Vector3.xAxis else Vector3.zAxis
								local piece: BasePart? = nil
								local pieceScore = math.huge
								for _, body in FurnitureService.piecesNear(entry.center, 30) do
									local d = Util.flatDistance(body.Position, entry.center)
									if
										used[body]
										or FurnitureService.weightOf(body) == "Massive"
										or d <= 4
										or not MapLayout.inRect(r, body.Position.X, body.Position.Z)
									then
										continue
									end
									local cover = FurniturePush.extent(body, along) * 2 / entry.door.width
									local score = d - 8 * math.min(cover, 1.2)
									if score < pieceScore then
										piece, pieceScore = body, score
									end
								end
								if piece then
									local depth = FurniturePush.extent(piece, entry.inward)
									local made: Job = {
										body = piece,
										target = Util.flat(entry.center + entry.inward * (depth + 1.6)),
										key = key,
										startedAt = now,
										pushers = {},
										done = false,
									}
									table.insert(fort.jobs, made)
									job = made
									break
								end
								fort.barricaded[key] = true -- nothing to block it with
							end
						end
						barricade = job
						if job then
							job.pushers[p.id] = now
							local body = job.body
							local at = Util.flat(body.Position)
							local toTarget = job.target - at
							if body.Parent == nil or toTarget.Magnitude < 2.2 or now - job.startedAt > 18 then
								job.done = true
								fort.barricaded[job.key] = true
								barricade = nil
							else
								-- Get behind the piece (side by side with a helper), then
								-- walk it to the doorway.
								local push = toTarget.Unit
								local side = Vector3.new(-push.Z, 0, push.X)
								local offset = 0
								if count(job.pushers, now, 1) >= 2 then
									local first = true
									for id, seen in job.pushers do
										if now - seen < 1 and id < p.id then
											first = false
										end
									end
									offset = (if first then -1 else 1) * 1.4 * p.scale
								end
								local behind = at
									- push * (FurniturePush.extent(body, push) + FurniturePush.bumperRadius(
										p.scale
									) + 0.6)
									+ side * offset
								if Util.flatDistance(behind, here) > 2.5 then
									goTo(Vector3.new(behind.X, here.Y, behind.Z), root, humanoid, false)
								else
									moveTo(
										humanoid,
										Vector3.new(job.target.X, here.Y, job.target.Z)
											+ push * 2
											+ side * offset
									)
								end
								handled = true
							end
						end
					end
					if not handled then
						-- Wait well back from the doors, each in our own spot.
						local away = Vector3.zero
						for _, entry in roomDoors do
							away += entry.inward
						end
						local ids = {}
						for id, seen in fort.members do
							if now - seen < 3 then
								table.insert(ids, id)
							end
						end
						table.sort(ids)
						local index = table.find(ids, p.id) or 1
						local angle = index / math.max(1, #ids) * math.pi * 2
						local ring = if #ids > 1 then 3 * p.scale else 0
						local spot = middle
							+ (if away.Magnitude > 0.1 then away.Unit else Vector3.zero) * 4
							+ Vector3.new(math.cos(angle), 0, math.sin(angle)) * ring
						if not MapLayout.inRect(r, spot.X, spot.Z, -2) then
							spot = middle
						end
						moveTo(humanoid, spot)
						handled = true
					end
				end
				if handled then
					continue
				end
			end
		end

		local hidden = BushService.hidden(p)
		-- Hiders take a bush of their own just before the outbreak and keep
		-- still in it; one a zombie flushed them out of is given up.
		if role == "Hider" then
			if #threats > 0 and not hidden then
				myBush = nil
			elseif
				not hidden
				and (phase == "Infection" or (phase == "Prep" and RoundManager.secondsLeft() < 15))
			then
				local bush = myBush
				if not bush or bush.Parent == nil then
					bush = freeBush(p, here)
					myBush = bush
				end
				if bush then
					local spot = Vector3.new(bush.Position.X, here.Y, bush.Position.Z)
					goTo(spot, root, humanoid, false)
					checkProgress(root, spot, humanoid)
					continue
				end
			end
		end
		if hidden and (not closest or closestDistance > Config.BUSH_REVEAL_DISTANCE + 4) then
			moveTo(humanoid, here) -- stay still and hope
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
					moveTo(humanoid, best)
					pathGoal = nil
				elseif closest then
					local step = sidestep(root, here + (here - closest.position))
					if step then
						moveTo(humanoid, step)
					end
				end
			end
		elseif phase == "Prep" and not p.heldItem then
			local spot = nearestItem(here, 90, p.id)
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
	-- A bot whose brain hits an error says so and starts thinking again,
	-- instead of standing still for the rest of the game.
	local seed = nextId * 97 + os.time()
	task.spawn(function()
		while Participants.get(p.id) == p do
			local ok, err = pcall(function()
				brain(p, level, seed)
			end)
			if ok then
				break
			end
			warn(string.format("[Bots] %s: %s", p.name, tostring(err)))
			seed += 1
			task.wait(1)
		end
	end)
end

-- Sharp movement, like players get from their own client: full speed the
-- instant a bot walks, a dead stop the instant it arrives, and it turns on
-- the spot (a Humanoid alone eases in and out and slides on the floors).
-- A shove (KnockbackForce) plays out untouched.
local function drive()
	for _, p in active do
		local root, humanoid = Participants.body(p)
		if not root or not humanoid or root:FindFirstChild("KnockbackForce") then
			continue
		end
		-- Never left inside a piece of furniture: out the shortest way.
		local radius = Config.rootWidth(p.scale) / 2 * 0.9
		local here = Util.flat(root.Position)
		local around = Vector3.new(radius * 2 + 2, root.Size.Y + 2, radius * 2 + 2)
		for _, body in FurnitureService.findInBox(CFrame.new(root.Position), around) do
			local depth, out = FurniturePush.overlapOut(here, here, radius, body)
			if out then
				root.CFrame += out * math.min(depth, 1)
			end
		end
		local v = root.AssemblyLinearVelocity
		-- Toward the spot the bot was last sent to (bots re-aim several times
		-- a second, so a goal older than that means: stand still).
		local goal: Vector3? = walkGoal[humanoid]
		local toGoal = Vector3.zero
		if goal and os.clock() - (walkAt[humanoid] or 0) < 1.5 then
			toGoal = Util.flat(goal - root.Position)
		end
		local move = if toGoal.Magnitude > 0.6 then toGoal.Unit else nil
		local speed = humanoid.WalkSpeed
		if move and speed > 0 then
			stopped[humanoid] = nil
			root.AssemblyLinearVelocity = Vector3.new(move.X * speed, v.Y, move.Z * speed)
			-- Not aiming a weapon: turn quickly toward where we walk. A spin,
			-- not a teleport of the rotation, so it replicates smoothly.
			local look = Util.flatUnit(root.CFrame.LookVector)
			if humanoid.AutoRotate and look then
				local angle = math.atan2(look.Z * move.X - look.X * move.Z, look:Dot(move))
				root.AssemblyAngularVelocity = Vector3.new(0, math.clamp(angle * 14, -24, 24), 0)
			end
		elseif not stopped[humanoid] then
			-- Arrived (or nothing new for a while): stop dead, and tell the
			-- Humanoid too so it doesn't keep nudging toward the old spot.
			stopped[humanoid] = true
			humanoid:MoveTo(root.Position)
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end
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
	RunService.Heartbeat:Connect(drive)
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
