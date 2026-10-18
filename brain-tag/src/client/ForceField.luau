-- Soft force fields around people and held weapons, felt by YOUR character
-- (worked out on your machine, so it is smooth and instant):
--   * people on your team gently push apart before they overlap
--   * someone else's weapon pushes you off it (firm ones and bigger
--     holders harder)
--   * someone pressing on your own weapon pushes you back (by size)
--   * two weapons pressed together push their holders apart
-- So nobody stacks up and there is always a bit of friction, like the
-- original. Bots get the same push from the server (ItemService.shaftStep).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterLook = require(ReplicatedStorage.Shared.CharacterLook)
local Config = require(ReplicatedStorage.Shared.Config)
local Items = require(ReplicatedStorage.Shared.Items)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)

local ForceField = {}

local C = Config.CHARACTER
local player = Players.LocalPlayer

type Body = { root: BasePart, scale: number, team: any, item: Items.Item? }

local cached: { Model } = {}
local cachedAt = 0

local function others(): { Model }
	local now = os.clock()
	if now - cachedAt > 0.25 then
		cachedAt = now
		cached = {}
		for _, folder in { workspace, workspace:FindFirstChild("Bots") } do
			if folder then
				for _, child in folder:GetChildren() do
					if
						child:IsA("Model")
						and child:GetAttribute("ParticipantId")
						and child ~= player.Character
					then
						table.insert(cached, child)
					end
				end
			end
		end
	end
	return cached
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Closest point to `p` on the segment a-b (all flat).
local function closest(a: Vector3, b: Vector3, p: Vector3): Vector3
	local ab = b - a
	local length2 = ab:Dot(ab)
	if length2 < 1e-6 then
		return a
	end
	local t = math.clamp((p - a):Dot(ab) / length2, 0, 1)
	return a + ab * t
end

-- A held melee weapon's shaft: from the hand along where the holder faces.
local function shaft(root: BasePart, scale: number, item: Items.Item, facing: Vector3): (Vector3, Vector3)
	local hand = flat((root.CFrame * CharacterLook.grip(scale)).Position)
	local reach = (item.reach or 5) * math.max(1, scale * 0.9)
	return hand, hand + facing * reach
end

local function heldMelee(model: Model): Items.Item?
	local held = model:FindFirstChild("HeldItem")
	local id = held and held:GetAttribute("ItemId")
	local item = if typeof(id) == "string" then Items.get(id) else nil
	return if item and item.kind == "Melee" then item else nil
end

-- Extra velocity (studs/second, flat) for your character this frame.
function ForceField.velocity(root: BasePart, aim: Vector3, myItemId: string?, myTeam: any): Vector3
	local myScale = root.Size.X / C.RootWidth
	local myRadius = C.ShellDiameter / 2 * myScale
	local me = flat(root.Position)
	local myItem = Items.get(myItemId)
	local myA, myB: Vector3? = nil, nil
	if myItem and myItem.kind == "Melee" then
		myA, myB = shaft(root, myScale, myItem, aim)
	end
	local push = Vector3.zero

	for _, model in others() do
		local other = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not other then
			continue
		end
		local them = flat(other.Position)
		local offset = me - them
		if offset.Magnitude > 40 then
			continue
		end
		local scale = other.Size.X / C.RootWidth
		local radius = C.ShellDiameter / 2 * scale

		-- Body to body (same team only: a zombie touching you should infect).
		if model:GetAttribute("Team") == myTeam then
			local overlap = myRadius + radius + 0.3 - offset.Magnitude
			if overlap > 0 then
				local away = if offset.Magnitude > 0.01 then offset.Unit else Vector3.xAxis
				push += away * math.min(overlap * Config.FIELD_BODY, Config.FIELD_BODY_MAX)
			end
		end

		-- Their weapon against you.
		local item = heldMelee(model)
		local facing = flat(other.CFrame.LookVector)
		if item and facing.Magnitude > 0.1 then
			local a, b = shaft(other, scale, item, facing.Unit)
			local point = closest(a, b, me)
			local away = me - point
			local overlap = (item.guard or 0.5) + myRadius - away.Magnitude
			if overlap > 0 then
				-- Shared by strength (size squared, times how firm the weapon is):
				-- a much bigger holder holds you off completely.
				local hold = scale * scale * (item.firmness or 1)
				local share = hold / (hold + RoundRules.pushStrength(myScale, myTeam == "Zombie"))
				local dir = if away.Magnitude > 0.01 then away.Unit else facing.Unit
				push += dir * math.min(overlap * Config.FIELD_WEAPON * share * 2, Config.FIELD_WEAPON_MAX)
			end

			-- Weapon against weapon: both holders get pushed apart.
			if myA and myB and myItem then
				local mine = closest(myA, myB, closest(a, b, (myA + myB) / 2))
				local theirs = closest(a, b, mine)
				local gap = mine - theirs
				local touch = (myItem.guard or 0.5) + (item.guard or 0.5) - gap.Magnitude
				if touch > 0 then
					local dir = if gap.Magnitude > 0.01 then gap.Unit else (me - them).Unit
					push += dir * math.min(touch * Config.FIELD_WEAPON, Config.FIELD_WEAPON_MAX) * 0.6
				end
			end
		end

		-- Someone pressing on your weapon pushes you back, by their share of
		-- the strength: an equal zombie walks you backwards, a small one
		-- against a big you barely does.
		if myA and myB and myItem then
			local point = closest(myA, myB, them)
			local overlap = (myItem.guard or 0.5) + radius - (point - them).Magnitude
			if overlap > 0 then
				local back = if offset.Magnitude > 0.01 then offset.Unit else -aim
				local mine = myScale * myScale * (myItem.firmness or 1)
				local theirs = RoundRules.pushStrength(scale, model:GetAttribute("Team") == "Zombie")
				local share = theirs / (mine + theirs)
				push += back * math.min(overlap * Config.FIELD_RECOIL * share * 2, Config.FIELD_WEAPON_MAX)
			end
		end
	end
	return push
end

return ForceField
