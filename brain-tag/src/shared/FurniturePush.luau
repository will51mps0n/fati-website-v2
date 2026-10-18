-- Shared pushing rules, so your client (for the pieces it drives) and the
-- server (for bots and contested pieces) move furniture identically.
--
-- Each pusher adds a desired velocity weighted by their strength (size
-- squared). A piece moves at the strength-weighted average of those
-- velocities, slowed by its mass: equal pushes from opposite sides cancel,
-- and a big player shoves what a small one can't. With nobody pushing, a
-- piece stops dead: there is no sliding.

local Config = require(script.Parent.Config)
local RoundRules = require(script.Parent.RoundRules)

local FurniturePush = {}

FurniturePush.OWNER_ATTRIBUTE = "OwnerUserId" -- UserId of the client driving a piece (0 = server)

export type Push = { weighted: Vector3, strength: number, torque: number }
export type Pushes = { [BasePart]: Push }

function FurniturePush.weightOf(body: BasePart): string
	local model = body.Parent
	local weight = model and model:GetAttribute("Weight")
	return if typeof(weight) == "string" then weight else "Medium"
end

function FurniturePush.mass(body: BasePart): number
	return (Config.FURNITURE_MASS :: { [string]: number })[FurniturePush.weightOf(body)] or 0.45
end

-- How far furniture is kept from a mover's center (CharacterService's
-- bumper).
function FurniturePush.bumperRadius(scale: number): number
	return Config.bumperRadius(scale)
end

-- Box in front of a mover heading `dir`: from just inside the bumper to
-- PUSH_REACH beyond it, so a piece starts moving before you reach it.
function FurniturePush.moverProbe(root: BasePart, dir: Vector3, scale: number): (CFrame, Vector3)
	local bumper = FurniturePush.bumperRadius(scale)
	local grow = math.min(scale, 1.5) -- like the bumper: never reaching through walls
	local from = bumper - 0.6 * grow
	local to = bumper + Config.PUSH_REACH * grow
	local center = root.Position + dir * ((from + to) / 2)
	local size = Vector3.new(math.max(bumper * 1.6, root.Size.X), root.Size.Y + 1, to - from)
	return CFrame.lookAt(center, center + dir), size
end

-- Box along a held weapon, from the hand to the tip, `guard` studs either
-- side of the shaft (Items: thick bat, thin spear).
function FurniturePush.itemProbe(
	root: BasePart,
	grip: CFrame,
	aim: Vector3,
	reach: number,
	guard: number?
): (CFrame, Vector3)
	local hand = (root.CFrame * grip).Position
	local start = Vector3.new(hand.X, root.Position.Y, hand.Z)
	local center = start + aim * (reach / 2)
	return CFrame.lookAt(center, center + aim), Vector3.new((guard or 0.5) * 2, root.Size.Y + 1, reach)
end

-- Box over a zombie's outstretched arms, from the front of its body to its
-- hands (CharacterLook's arm box). The arms are solid to furniture too.
function FurniturePush.armsProbe(
	root: BasePart,
	scale: number,
	reach: number,
	span: number
): (CFrame, Vector3)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local from = root.Size.Z / 2 - 0.2
	-- A giant's arms push only just past its bumper, never through a wall.
	local to = math.min(reach * scale, FurniturePush.bumperRadius(scale) + 1.2)
	local center = root.Position + look * ((from + to) / 2)
	return CFrame.lookAt(center, center + look),
		Vector3.new(span * 2 * math.min(scale, 2.5), root.Size.Y + 1, math.max(0.5, to - from))
end

-- Held weapons are solid. While you stand still or turn, a piece the shaft
-- overlaps is pushed out of its way: toward whichever side of the shaft its
-- center is on (so a sweep shoves it along), and a little forward. Returns
-- a flat unit direction.
function FurniturePush.shaftExit(hand: Vector3, aim: Vector3, body: BasePart): Vector3
	local rel = Vector3.new(body.Position.X - hand.X, 0, body.Position.Z - hand.Z)
	local side = rel - aim * rel:Dot(aim)
	if side.Magnitude < 0.3 then
		return aim
	end
	return (side.Unit + aim * 0.5).Unit
end

function FurniturePush.add(pushes: Pushes, body: BasePart, desired: Vector3, strength: number, at: Vector3?)
	local flat = Vector3.new(desired.X, 0, desired.Z)
	local push = pushes[body]
	if not push then
		push = { weighted = Vector3.zero, strength = 0, torque = 0 }
		pushes[body] = push
	end
	assert(push, "push")
	push.weighted += flat * strength
	push.strength += strength
	if at then
		-- Vertical part of (r x v): off-center pushes turn the piece a little.
		local r = at - body.Position
		push.torque += (r.Z * flat.X - r.X * flat.Z) * strength
	end
end

-- The velocity and spin (radians/second about Y) a piece should have.
function FurniturePush.resolve(body: BasePart, push: Push): (Vector3, number)
	if push.strength <= 0 then
		return Vector3.zero, 0
	end
	local fraction = RoundRules.pushFraction(FurniturePush.mass(body), push.strength)
	local velocity = push.weighted / push.strength * fraction
	if velocity.Magnitude > Config.FURNITURE_MAX_SPEED then
		velocity = velocity.Unit * Config.FURNITURE_MAX_SPEED
	end
	local size = math.max(1, body.Size.Magnitude / 4)
	local spin = math.clamp(push.torque / push.strength * Config.FURNITURE_SPIN * fraction / size, -1.5, 1.5)
	return velocity, spin
end

-- How deep the segment a-b (flat; `pad` studs thick: a weapon's shaft, or a
-- body when a == b) sits inside a piece, and the flat unit direction that
-- gets it out the shortest way. Depth 0 and no direction when it's clear.
function FurniturePush.overlapOut(a: Vector3, b: Vector3, pad: number, body: BasePart): (number, Vector3?)
	local cf = body.CFrame
	local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if right.Magnitude < 0.5 or look.Magnitude < 0.5 then
		return 0, nil
	end
	right, look = right.Unit, look.Unit
	local hx, hz = body.Size.X / 2 + pad, body.Size.Z / 2 + pad
	local samples = if (b - a).Magnitude < 0.05 then 0 else 8
	local best, out = 0, nil
	for i = 0, samples do
		local p = if samples == 0 then a else a + (b - a) * (i / samples)
		local rel = Vector3.new(p.X - cf.Position.X, 0, p.Z - cf.Position.Z)
		local lx, lz = rel:Dot(right), rel:Dot(look)
		local dx, dz = hx - math.abs(lx), hz - math.abs(lz)
		if dx > 0 and dz > 0 then
			local depth = math.min(dx, dz)
			if depth > best then
				best = depth
				out = if dx < dz
					then right * (if lx >= 0 then 1 else -1)
					else look * (if lz >= 0 then 1 else -1)
			end
		end
	end
	return best, out
end

-- How far an oriented piece reaches from its center along a flat direction.
function FurniturePush.extent(body: BasePart, dir: Vector3): number
	local cf = body.CFrame
	return math.abs(dir:Dot(cf.RightVector)) * body.Size.X / 2
		+ math.abs(dir:Dot(cf.LookVector)) * body.Size.Z / 2
end

return FurniturePush
