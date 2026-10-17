-- Owns every furniture piece: builds them, decides who simulates each one,
-- and resets them each round.
--
-- Responsiveness: when you push a piece, your client asks for it ("claim")
-- and the server hands you its physics, so it moves the instant you push
-- and stops the instant you stop, with no network lag. If anyone else pushes
-- the same piece (a zombie on the other side of a barricade, another player,
-- a bot), the server takes it back and resolves everyone's pushes itself, so
-- a barricade standoff is fair. Pieces nobody pushes stand perfectly still.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterLook = require(ReplicatedStorage.Shared.CharacterLook)
local Config = require(ReplicatedStorage.Shared.Config)
local FurnitureBuilder = require(script.Parent.FurnitureBuilder)
local FurniturePush = require(ReplicatedStorage.Shared.FurniturePush)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Participants = require(script.Parent.Participants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local Util = require(ReplicatedStorage.Shared.Util)

local FurnitureService = {}

type Piece = FurnitureBuilder.Built & {
	owner: Player?,
	lastClaim: number,
	pushers: { [string]: number }, -- participant id -> last time seen pushing
	contestedUntil: number,
	tugOfWar: boolean, -- contestedUntil came from two pushers, not a shove
	burst: Vector3,
	burstUntil: number,
	burstLength: number,
	lastGood: CFrame, -- last position that passed the anti-cheat checks
	lastGoodAt: number, -- when the piece last moved to lastGood
}

-- Someone who can push furniture. `reach` is set while they hold a melee
-- weapon, whose shaft (along `aim`) pushes too.
export type Mover = {
	root: BasePart,
	humanoid: Humanoid,
	id: string,
	scale: number,
	aim: Vector3,
	dragging: boolean?, -- hooking a piece with held click
	firmness: number?, -- held weapon's Items.firmness
	guard: number?, -- held weapon's Items.guard
	reach: number?,
}

local OWNER = FurniturePush.OWNER_ATTRIBUTE
local CONTEST_SECONDS = 0.8

local pieces: { Piece } = {}
local byBody: { [BasePart]: Piece } = {}
local byModel: { [Instance]: Piece } = {}
local folder: Folder
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
local external: FurniturePush.Pushes = {}

local getMovers: () -> { Mover } = function()
	return {}
end

local function serverOwns(piece: Piece)
	piece.owner = nil
	pcall(function()
		piece.body:SetNetworkOwner(nil)
	end)
	piece.model:SetAttribute(OWNER, 0)
end

local function stop(piece: Piece)
	local v = piece.body.AssemblyLinearVelocity
	piece.body.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), 0)
	piece.body.AssemblyAngularVelocity = Vector3.zero
end

-- Takes a piece back from a client (optionally blocking new claims for a
-- bit). In a tug of war the piece keeps moving: the server writes the
-- resolved velocity the same frame, so stopping it would only cause a snap.
local function revoke(piece: Piece, blockSeconds: number, halt: boolean?)
	if piece.owner then
		serverOwns(piece)
		if halt ~= false then
			stop(piece)
		end
	end
	piece.contestedUntil = math.max(piece.contestedUntil, os.clock() + blockSeconds)
end

-- True if anyone other than `id` pushed the piece in the last moment.
local function othersPushing(piece: Piece, id: string, now: number): boolean
	for other, seen in piece.pushers do
		if other ~= id and now - seen <= 0.3 then
			return true
		end
	end
	return false
end

local function grant(piece: Piece, player: Player)
	local ok = pcall(function()
		piece.body:SetNetworkOwner(player)
	end)
	if ok then
		piece.owner = player
		piece.model:SetAttribute(OWNER, player.UserId)
	end
end

function FurnitureService.build(layout: MapLayout.Layout)
	folder = workspace:WaitForChild("Furniture") :: Folder
	folder:ClearAllChildren()
	table.clear(pieces)
	table.clear(byBody)
	table.clear(byModel)
	for _, spot in layout.furniture do
		local built = FurnitureBuilder.build(spot, folder)
		if not built.decor then
			local piece = built :: Piece
			piece.owner = nil
			piece.lastClaim = 0
			piece.pushers = {}
			piece.contestedUntil = 0
			piece.tugOfWar = false
			piece.burst = Vector3.zero
			piece.burstUntil = 0
			piece.burstLength = 1
			piece.lastGood = built.home
			piece.lastGoodAt = 0
			table.insert(pieces, piece)
			byBody[built.body] = piece
			byModel[built.model] = piece
			serverOwns(piece)
		end
	end
	overlap.FilterDescendantsInstances = { folder }
end

-- Adds a push on a server-driven piece for the next frame (weapon drags).
function FurnitureService.addPush(body: BasePart, desired: Vector3, strength: number, at: Vector3?)
	if byBody[body] then
		FurniturePush.add(external, body, desired, strength, at)
	end
end

-- A sudden shove (shotgun blast, potato hit): the server takes the piece and
-- moves it at `velocity`, easing to a stop over `seconds`.
function FurnitureService.shove(body: BasePart, velocity: Vector3, seconds: number)
	local piece = byBody[body]
	if not piece then
		return
	end
	revoke(piece, seconds + 0.2)
	piece.burst = Vector3.new(velocity.X, 0, velocity.Z)
	piece.burstLength = seconds
	piece.burstUntil = os.clock() + seconds
end

function FurnitureService.pieceOf(part: BasePart): FurnitureBuilder.Built?
	return byBody[part]
end

function FurnitureService.weightOf(body: BasePart): string?
	local piece = byBody[body]
	return piece and piece.weight
end

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
		serverOwns(piece)
		piece.contestedUntil = 0
		piece.tugOfWar = false
		piece.burstUntil = 0
		table.clear(piece.pushers)
		piece.model:PivotTo(piece.home)
		piece.lastGood = piece.home
		piece.body.AssemblyLinearVelocity = Vector3.zero
		piece.body.AssemblyAngularVelocity = Vector3.zero
	end
end

-- A client asks to drive the pieces it is pushing.
local function onClaim(player: Player, list: unknown)
	if typeof(list) ~= "table" then
		return
	end
	local claims = list :: { unknown }
	if #claims > 16 then
		return
	end
	local p = Participants.fromPlayer(player)
	local root = p and Participants.body(p)
	if not p or not root then
		return
	end
	local now = os.clock()
	for _, model in claims do
		local piece = if typeof(model) == "Instance" then byModel[model] else nil
		if not piece or now < piece.contestedUntil or now < piece.burstUntil then
			continue
		end
		if piece.owner and piece.owner ~= player then
			revoke(piece, CONTEST_SECONDS, false) -- two players fighting over it: server decides
			continue
		end
		if othersPushing(piece, p.id, now) then
			continue -- someone else is on it too: the server settles that
		end
		-- Only pieces you could actually be touching (body or longest weapon).
		local range = piece.body.Size.Magnitude / 2 + root.Size.X / 2 + 12 * math.max(1, p.scale) + 3
		if Util.flatDistance(piece.body.Position, root.Position) > range then
			continue
		end
		piece.lastClaim = now
		if piece.owner ~= player then
			grant(piece, player)
		end
	end
end

local function collectPushes(now: number): FurniturePush.Pushes
	local pushes: FurniturePush.Pushes = external
	external = {}
	for _, mover in getMovers() do
		local humanoid, root = mover.humanoid, mover.root
		local walk = humanoid.WalkSpeed
		if walk <= 0 then
			continue
		end
		local move = humanoid.MoveDirection
		local flat = Vector3.new(move.X, 0, move.Z)
		local moving = flat.Magnitude > 0.1
		local dir = if moving then flat.Unit else Vector3.zero
		local strength = RoundRules.pushStrength(mover.scale)
		local touched: { [BasePart]: boolean } = {}
		if moving then
			local probe, size = FurniturePush.moverProbe(root, dir, mover.scale)
			for _, part in workspace:GetPartBoundsInBox(probe, size, overlap) do
				local piece = byBody[part]
				if piece then
					touched[part] = true
					piece.pushers[mover.id] = now
					FurniturePush.add(pushes, part, dir * walk, strength, probe.Position)
				end
			end
		end
		-- A held weapon's shaft is solid, same as on the client: it pushes
		-- what it touches along your path, or out of its way when you stand
		-- still or turn. While hooking a piece (held click) the drag does the work.
		if mover.reach and not mover.dragging then
			local shaft, shaftSize = FurniturePush.itemProbe(
				root,
				CharacterLook.grip(mover.scale),
				mover.aim,
				mover.reach,
				mover.guard
			)
			local firm = strength * (mover.firmness or 1)
			for _, part in workspace:GetPartBoundsInBox(shaft, shaftSize, overlap) do
				local piece = byBody[part]
				if piece and not touched[part] then
					piece.pushers[mover.id] = now
					if moving then
						FurniturePush.add(pushes, part, dir * walk, firm, part.Position + mover.aim * 0.5)
					else
						local exit = FurniturePush.shaftExit(root, mover.aim, part)
						FurniturePush.add(
							pushes,
							part,
							exit * walk * Config.SHAFT_FURNITURE_FACTOR,
							firm,
							nil
						)
					end
				end
			end
		end
	end
	return pushes
end

-- Is a client-driven piece somewhere a legitimate push could have put it?
local function plausible(piece: Piece, now: number): boolean
	local body = piece.body
	local owner = piece.owner
	local p = owner and Participants.fromPlayer(owner)
	local root = p and Participants.body(p)
	if not p or not root then
		return false
	end
	local v = body.AssemblyLinearVelocity
	if Vector3.new(v.X, 0, v.Z).Magnitude > Config.FURNITURE_MAX_SPEED * 1.5 or v.Y > 8 then
		return false
	end
	if body.AssemblyAngularVelocity.Magnitude > 3 then
		return false
	end
	-- Client positions arrive in bursts, so compare against the time since
	-- the piece last moved, not one server frame (capped so a piece that sat
	-- still for a while can't jump far).
	local moved = Util.flatDistance(body.Position, piece.lastGood.Position)
	local elapsed = math.clamp(now - piece.lastGoodAt, 1 / 60, 0.3)
	if moved > Config.FURNITURE_MAX_SPEED * 1.6 * elapsed + 1.5 then
		return false -- teleported
	end
	local range = body.Size.Magnitude / 2 + root.Size.X / 2 + 14 * math.max(1, p.scale) + 6
	return Util.flatDistance(body.Position, root.Position) <= range
end

local function step(dt: number)
	local now = os.clock()
	local pushes = collectPushes(now)
	for _, piece in pieces do
		local body = piece.body
		if body.Parent == nil then
			continue
		end

		-- Who is pushing this piece right now (seen by the server)?
		local owner = piece.owner
		local ownerId = if owner then "P" .. owner.UserId else ""
		local active, someoneElse = 0, false
		for id, seen in piece.pushers do
			if now - seen > 0.3 then
				piece.pushers[id] = nil
			else
				active += 1
				if owner and id ~= ownerId then
					someoneElse = true
				end
			end
		end
		if now >= piece.contestedUntil then
			piece.tugOfWar = false
		end
		if active >= 2 or someoneElse then
			-- A tug of war: the server simulates it so both sides count.
			piece.tugOfWar = true
			revoke(piece, CONTEST_SECONDS, false)
		elseif not owner and piece.tugOfWar and now < piece.contestedUntil and active >= 1 then
			-- Keep the server in charge until the tug of war is really over.
			piece.contestedUntil = now + CONTEST_SECONDS
		elseif owner then
			if owner.Parent ~= Players or now - piece.lastClaim > Config.FURNITURE_RELEASE_SECONDS then
				revoke(piece, 0)
			elseif not plausible(piece, now) then
				-- Moved in a way no push could: put it back and take it away.
				revoke(piece, 1.5)
				piece.model:PivotTo(piece.lastGood)
			end
		end
		if piece.owner then
			-- Only advance when a new position has arrived (see plausible).
			if (body.Position - piece.lastGood.Position).Magnitude > 0.01 then
				piece.lastGood, piece.lastGoodAt = body.CFrame, now
			end
		end

		if piece.owner == nil then
			piece.lastGood, piece.lastGoodAt = body.CFrame, now
			local v = body.AssemblyLinearVelocity
			if now < piece.burstUntil then
				local k = (piece.burstUntil - now) / piece.burstLength
				body.AssemblyLinearVelocity =
					Vector3.new(piece.burst.X * k, math.min(v.Y, 0), piece.burst.Z * k)
			else
				local push = pushes[body]
				if push then
					local velocity, spin = FurniturePush.resolve(body, push)
					body.AssemblyLinearVelocity = Vector3.new(velocity.X, math.min(v.Y, 0), velocity.Z)
					body.AssemblyAngularVelocity = Vector3.new(0, spin, 0)
				elseif
					math.abs(v.X) + math.abs(v.Z) > 0.02 or body.AssemblyAngularVelocity.Magnitude > 0.02
				then
					stop(piece) -- no sliding
				end
			end
		end
	end
end

function FurnitureService.start(movers: () -> { Mover })
	getMovers = movers
	Remotes.unreliable("PushClaim").OnServerEvent:Connect(onClaim)
	Players.PlayerRemoving:Connect(function(player)
		for _, piece in pieces do
			if piece.owner == player then
				revoke(piece, 0)
			end
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return FurnitureService
