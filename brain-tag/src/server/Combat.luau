-- Shoves and stuns. Weapons never kill: they push zombies away and freeze
-- them for a moment. Players' characters are simulated by their own clients,
-- so their shove is sent to them; bots are shoved right here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterService = require(script.Parent.CharacterService)
local Config = require(ReplicatedStorage.Shared.Config)
local Knockback = require(ReplicatedStorage.Shared.Knockback)
local MapBuilder = require(script.Parent.MapBuilder)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Participants = require(script.Parent.Participants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)

type Participant = Participants.Participant

local Combat = {}

local knockbackRemote = Remotes.event("Knockback")
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Include
local solidParams = RaycastParams.new()
solidParams.FilterType = Enum.RaycastFilterType.Include
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Include

function Combat.init()
	wallParams.FilterDescendantsInstances = { MapBuilder.wallsFolder() }
	solidParams.FilterDescendantsInstances = { MapBuilder.wallsFolder(), workspace:WaitForChild("Furniture") }
	sightParams.FilterDescendantsInstances = { MapBuilder.wallsFolder(), MapBuilder.doorsFolder() }
end

-- Can someone at `from` see `to`? Walls and closed swinging doors block the
-- view (bots on dark maps use this; doors swing open only on players' screens).
function Combat.canSee(from: Vector3, to: Vector3): boolean
	local y = MapLayout.HEIGHTS.Floor + 3
	local a = Vector3.new(from.X, y, from.Z)
	local b = Vector3.new(to.X, y, to.Z)
	return workspace:Raycast(a, b - a, sightParams) == nil
end

-- Like lineOfSight, but furniture blocks too (used for infection, so a
-- barricade always protects the people behind it).
function Combat.clearPath(from: Vector3, to: Vector3): boolean
	-- Low enough to hit every piece of furniture, whatever the players' size.
	local y = MapLayout.HEIGHTS.Floor + 1.4
	local a = Vector3.new(from.X, y, from.Z)
	local b = Vector3.new(to.X, y, to.Z)
	return workspace:Raycast(a, b - a, solidParams) == nil
end

-- Like clearPath, but for a body `radius` wide, so bots never try to squeeze
-- past a wall corner. With `wallsOnly`, furniture doesn't count (a zombie
-- may shove through a barricade).
function Combat.clearWide(from: Vector3, to: Vector3, radius: number, wallsOnly: boolean?): boolean
	local y = MapLayout.HEIGHTS.Floor + 1.4
	local a = Vector3.new(from.X, y, from.Z)
	local direction = Vector3.new(to.X, y, to.Z) - a
	if direction.Magnitude < 0.05 then
		return true
	end
	return workspace:Spherecast(a, radius, direction, if wallsOnly then wallParams else solidParams) == nil
end

-- True when no (unbroken) wall stands between the two points.
function Combat.lineOfSight(from: Vector3, to: Vector3): boolean
	local y = math.max(from.Y, to.Y)
	local a = Vector3.new(from.X, y, from.Z)
	local b = Vector3.new(to.X, y, to.Z)
	return workspace:Raycast(a, b - a, wallParams) == nil
end

function Combat.wallParams(): RaycastParams
	return wallParams
end

-- `gentle` shoves (a zombie leaning on a held weapon) never cut short a
-- real hit that is still sending the zombie flying.
function Combat.knockback(
	target: Participant,
	velocity: Vector3,
	stun: number,
	seconds: number?,
	gentle: boolean?
)
	local root = Participants.body(target)
	local character = target.character
	if not root or not character then
		return
	end
	local now = os.clock()
	if gentle and now < target.knockedUntil then
		return
	end
	if stun > 0 then
		target.stunUntil = math.max(target.stunUntil, os.clock() + stun)
		CharacterService.refreshSpeed(target)
		task.delay(stun + 0.05, function()
			CharacterService.refreshSpeed(target)
		end)
	end
	local duration = seconds or Config.KNOCKBACK_SECONDS
	if not gentle then
		target.knockedUntil = now + duration
	end
	if target.player then
		knockbackRemote:FireClient(target.player, velocity, duration)
	else
		Knockback.apply(character, velocity, duration)
	end
end

-- Area blast (duck launcher): shoves everyone within `radius` away from the
-- center, with a classic (harmless) Roblox explosion for show.
function Combat.explode(at: Vector3, radius: number, knockback: number, stun: number)
	local boom = Instance.new("Explosion")
	boom.Position = at
	boom.BlastRadius = radius
	boom.BlastPressure = 0
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Parent = workspace
	for _, person in Participants.all() do
		local root = Participants.body(person)
		if root then
			local offset = Util.flat(root.Position - at)
			if offset.Magnitude <= radius and Combat.lineOfSight(at, root.Position) then
				local away = if offset.Magnitude > 0.1 then offset.Unit else Vector3.xAxis
				local falloff = 1 - offset.Magnitude / radius * 0.5
				Combat.knockback(person, away * knockback * falloff, stun)
			end
		end
	end
end

export type Hit = { target: Participant, direction: Vector3, distance: number }

-- Everyone else (zombies and humans) inside a cone in front of `attacker`,
-- not behind walls: weapons push people on both teams.
function Combat.peopleInCone(attacker: Participant, aim: Vector3, reach: number, arcDegrees: number): { Hit }
	local root = Participants.body(attacker)
	local hits = {}
	if not root then
		return hits
	end
	local cosHalf = math.cos(math.rad(arcDegrees / 2))
	local myRadius = root.Size.X / 2
	for _, other in Participants.all() do
		local zRoot = if other ~= attacker then Participants.body(other) else nil
		if zRoot then
			local offset = Util.flat(zRoot.Position - root.Position)
			local distance = offset.Magnitude
			local zRadius = zRoot.Size.X / 2
			if distance > 0.01 and distance <= reach + zRadius then
				local direction = offset.Unit
				local touching = distance <= myRadius + zRadius + 0.6
				if
					(touching or direction:Dot(aim) >= cosHalf)
					and Combat.lineOfSight(root.Position, zRoot.Position)
				then
					table.insert(hits, { target = other, direction = direction, distance = distance })
				end
			end
		end
	end
	return hits
end

return Combat
