-- Owns every furniture piece: builds them, simulates them on the server (so
-- humans and zombies push by the same rules), and resets them each round.
--
-- Pushing: each frame, anyone walking into a piece adds a push in their move
-- direction, scaled by the piece's weight class. Opposite pushes cancel, so a
-- human holding a couch from inside stops a zombie on the outside. Pieces
-- pressed into walls simply can't move: that is what makes a barricade hold.
-- When nobody pushes, strong drag stops a piece almost at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local FurnitureBuilder = require(script.Parent.FurnitureBuilder)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)

local FurnitureService = {}

type Piece = FurnitureBuilder.Built & {
	push: Vector3,
	spin: number,
	pushedThisFrame: boolean,
}

export type Mover = { root: BasePart, humanoid: Humanoid }

local pieces: { Piece } = {}
local byBody: { [BasePart]: Piece } = {}
local folder: Folder
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include

local getMovers: () -> { Mover } = function()
	return {}
end

function FurnitureService.build()
	folder = workspace:WaitForChild("Furniture") :: Folder
	folder:ClearAllChildren()
	table.clear(pieces)
	table.clear(byBody)
	for _, spot in MapLayout.furniture do
		local built = FurnitureBuilder.build(spot, folder)
		if not built.decor then
			local piece = built :: Piece
			piece.push = Vector3.zero
			piece.spin = 0
			piece.pushedThisFrame = false
			table.insert(pieces, piece)
			byBody[built.body] = piece
			-- Server-owned physics: one source of truth for every pusher.
			local ok, err = pcall(function()
				built.body:SetNetworkOwner(nil)
			end)
			if not ok then
				warn("[Furniture] could not set network owner:", err)
			end
		end
	end
	overlap.FilterDescendantsInstances = { folder }
end

-- Adds a push to a piece for this frame. `velocity` is the speed the pusher
-- would like the piece to move at; `at` is where the push lands (for spin).
function FurnitureService.addPush(body: BasePart, velocity: Vector3, at: Vector3?)
	local piece = byBody[body]
	if not piece then
		return
	end
	piece.push += Vector3.new(velocity.X, 0, velocity.Z)
	piece.pushedThisFrame = true
	if at then
		local r = at - body.Position
		-- Vertical component of (r x v): off-center pushes turn the piece.
		piece.spin += (r.Z * velocity.X - r.X * velocity.Z)
	end
end

function FurnitureService.pieceOf(part: BasePart): FurnitureBuilder.Built?
	return byBody[part]
end

function FurnitureService.weightOf(body: BasePart): string?
	local piece = byBody[body]
	return piece and piece.weight
end

-- Light/medium pieces in a box in front of a point, for the swordfish drag.
function FurnitureService.findInBox(cframe: CFrame, size: Vector3): { BasePart }
	local found = {}
	for _, part in workspace:GetPartBoundsInBox(cframe, size, overlap) do
		if byBody[part] then
			table.insert(found, part)
		end
	end
	return found
end

function FurnitureService.resetAll()
	for _, piece in pieces do
		piece.model:PivotTo(piece.home)
		piece.body.AssemblyLinearVelocity = Vector3.zero
		piece.body.AssemblyAngularVelocity = Vector3.zero
		piece.push = Vector3.zero
		piece.spin = 0
	end
end

local function collectPushes()
	for _, mover in getMovers() do
		local humanoid, root = mover.humanoid, mover.root
		local move = humanoid.MoveDirection
		local flat = Vector3.new(move.X, 0, move.Z)
		if flat.Magnitude > 0.1 and humanoid.WalkSpeed > 0 then
			local dir = flat.Unit
			local radius = root.Size.X / 2
			local depth = Config.PUSH_PROBE_DEPTH
			local center = root.Position + dir * (radius + depth / 2 - 0.3)
			local probe = CFrame.lookAt(center, center + dir)
			local size = Vector3.new(root.Size.X * 0.9, 2, depth)
			local seen: { [BasePart]: boolean } = {}
			for _, part in workspace:GetPartBoundsInBox(probe, size, overlap) do
				local piece = byBody[part]
				if piece and not seen[part] then
					seen[part] = true
					local speed = humanoid.WalkSpeed * Config.FURNITURE_PUSH_FACTOR[piece.weight]
					FurnitureService.addPush(part, dir * speed, center)
				end
			end
		end
	end
end

local function step(dt: number)
	collectPushes()
	local drag = Config.FURNITURE_DRAG ^ (dt * 60)
	local angularDrag = Config.FURNITURE_ANGULAR_DRAG ^ (dt * 60)
	local maxSpeed = Config.FURNITURE_MAX_SPEED
	for _, piece in pieces do
		local body = piece.body
		if body.Parent == nil then
			continue
		end
		local v = body.AssemblyLinearVelocity
		local w = body.AssemblyAngularVelocity
		local horizontal = Vector3.new(v.X, 0, v.Z)
		local spinY = w.Y
		if piece.pushedThisFrame then
			local target = piece.push
			if target.Magnitude > maxSpeed then
				target = target.Unit * maxSpeed
			end
			horizontal = horizontal:Lerp(target, math.min(1, dt * 20))
			local factor = Config.FURNITURE_PUSH_FACTOR[piece.weight]
			local wantSpin = math.clamp(
				piece.spin * Config.FURNITURE_SPIN * factor / math.max(1, body.Size.Magnitude / 4),
				-2,
				2
			)
			spinY = spinY + (wantSpin - spinY) * math.min(1, dt * 10)
		else
			horizontal *= drag
			spinY *= angularDrag
		end
		if horizontal.Magnitude > maxSpeed then
			horizontal = horizontal.Unit * maxSpeed
		end
		-- Skip writes on resting pieces so they can sleep.
		if
			piece.pushedThisFrame
			or horizontal.Magnitude > 0.05
			or math.abs(spinY) > 0.05
			or math.abs(v.Y) > 0.5
		then
			if horizontal.Magnitude <= 0.05 and not piece.pushedThisFrame then
				horizontal = Vector3.zero
			end
			body.AssemblyLinearVelocity = Vector3.new(horizontal.X, math.min(v.Y, 5), horizontal.Z)
			body.AssemblyAngularVelocity = Vector3.new(w.X * angularDrag, spinY, w.Z * angularDrag)
		end
		piece.push = Vector3.zero
		piece.spin = 0
		piece.pushedThisFrame = false
	end
end

function FurnitureService.start(movers: () -> { Mover })
	getMovers = movers
	RunService.Heartbeat:Connect(step)
end

return FurnitureService
