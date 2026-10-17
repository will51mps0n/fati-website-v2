-- Drives the furniture YOU are pushing, on your own machine, so it responds
-- instantly and stops the moment you stop. The server hands you a piece when
-- you claim it and takes it back if someone else pushes it too.
--
-- You move furniture by walking into it, by walking with a weapon whose
-- shaft touches it, or by holding click with a weapon to hook the nearest
-- piece and drag it toward you.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterLook = require(ReplicatedStorage.Shared.CharacterLook)
local ClientState = require(script.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local FurniturePush = require(ReplicatedStorage.Shared.FurniturePush)
local InputController = require(script.Parent.InputController)
local Items = require(ReplicatedStorage.Shared.Items)
local MovementController = require(script.Parent.MovementController)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local Util = require(ReplicatedStorage.Shared.Util)

local FurnitureController = {}

local player = Players.LocalPlayer
local OWNER = FurniturePush.OWNER_ATTRIBUTE
local CLAIM_INTERVAL = 0.1

local folder: Instance
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
local claimRemote: UnreliableRemoteEvent
local owned: { [BasePart]: boolean } = {}
local pendingClaims: { [Instance]: boolean } = {}
local lastClaim = 0

local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local body = model:WaitForChild("Body", 10) :: BasePart?
	if not body then
		return
	end
	local function refresh()
		if model:GetAttribute(OWNER) == player.UserId and model.Parent == folder then
			owned[body] = true
		else
			owned[body] = nil
		end
	end
	model:GetAttributeChangedSignal(OWNER):Connect(refresh)
	model.AncestryChanged:Connect(refresh)
	refresh()
end

local function query(cframe: CFrame, size: Vector3): { BasePart }
	local found = {}
	for _, part in workspace:GetPartBoundsInBox(cframe, size, overlap) do
		if part.Name == "Body" and not part.Anchored then
			table.insert(found, part)
		end
	end
	return found
end

local function collect(): FurniturePush.Pushes
	local pushes: FurniturePush.Pushes = {}
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return pushes
	end
	local scale = ClientState.my("Scale") or 1
	local strength = RoundRules.pushStrength(scale)
	local walk = humanoid.WalkSpeed
	local move = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
	local moving = move.Magnitude > 0.1 and walk > 0
	local dir = if moving then move.Unit else Vector3.zero

	-- Walking into furniture.
	if moving then
		local probe, size = FurniturePush.moverProbe(root, dir, scale)
		for _, body in query(probe, size) do
			FurniturePush.add(pushes, body, dir * walk, strength, probe.Position)
		end
	end

	-- Weapons: the shaft pushes what it touches; holding click hooks and drags.
	local item = Items.get(ClientState.my("HeldItem"))
	if item and item.kind == "Melee" and not ClientState.isZombie() then
		local aim = MovementController.aim()
		local reach = (item.reach or 5) * math.max(1, scale * 0.9)
		local grip = CharacterLook.grip(scale)
		local hand = (root.CFrame * grip).Position
		local probe, size = FurniturePush.itemProbe(root, grip, aim, reach, item.guard)
		local touched = query(probe, size)
		local firm = strength * (item.firmness or 1) -- a stiff bat shoves harder than a noodle
		local using = InputController.isUsing()
		if using and walk > 0 then
			local nearest: BasePart? = nil
			local best = math.huge
			for _, body in touched do
				local d = Util.flatDistance(body.Position, root.Position)
				if d < best then
					nearest, best = body, d
				end
			end
			if nearest then
				local toward = Util.flatUnit(root.Position - nearest.Position)
				local gap = FurniturePush.extent(nearest, toward or aim) + root.Size.X / 2 + 0.6
				if toward and best > gap then
					local hook = if item.dragsFurniture then 1.5 else 1
					FurniturePush.add(
						pushes,
						nearest,
						toward * walk * Config.ITEM_DRAG_FACTOR,
						strength * hook,
						nil
					)
				end
			end
		end
		-- The shaft is solid: what it overlaps moves out of the way (not while
		-- hooking with held click, where the drag does the work, like the server).
		if walk > 0 and not using then
			for _, body in touched do
				if not pushes[body] then
					if moving then
						FurniturePush.add(pushes, body, dir * walk, firm, body.Position + aim * 0.5)
					else
						local exit = FurniturePush.shaftExit(hand, aim, body)
						FurniturePush.add(
							pushes,
							body,
							exit * walk * Config.SHAFT_FURNITURE_FACTOR,
							firm,
							nil
						)
					end
				end
			end
		end
	end

	-- A piece you drive pushes whatever it runs into, so you can shove a line.
	for body, push in table.clone(pushes) do
		if owned[body] then
			local velocity = FurniturePush.resolve(body, push)
			local ahead = Util.flatUnit(velocity)
			if ahead and velocity.Magnitude > 0.5 then
				local reachAhead = FurniturePush.extent(body, ahead)
				local center = body.Position + ahead * (reachAhead + 0.6)
				local side = Vector3.new(-ahead.Z, 0, ahead.X)
				local width = FurniturePush.extent(body, side) * 2 * 0.9
				local probe = CFrame.lookAt(center, center + ahead)
				for _, other in query(probe, Vector3.new(width, 2, 1.2)) do
					if other ~= body and not pushes[other] then
						FurniturePush.add(pushes, other, velocity, push.strength, center)
					end
				end
			end
		end
	end
	return pushes
end

local function step()
	local pushes = collect()

	-- Ask the server for anything we're pushing.
	for body in pushes do
		local model = body.Parent
		if model then
			pendingClaims[model] = true
		end
	end
	local now = os.clock()
	if next(pendingClaims) and now - lastClaim >= CLAIM_INTERVAL then
		local list = {}
		for model in pendingClaims do
			table.insert(list, model)
			if #list >= 16 then
				break
			end
		end
		table.clear(pendingClaims)
		lastClaim = now
		claimRemote:FireServer(list)
	end

	-- Drive the pieces the server gave us. Unpushed ones stand still.
	for body in owned do
		if body.Parent == nil then
			owned[body] = nil
			continue
		end
		local v = body.AssemblyLinearVelocity
		local push = pushes[body]
		if push then
			local velocity, spin = FurniturePush.resolve(body, push)
			body.AssemblyLinearVelocity = Vector3.new(velocity.X, math.min(v.Y, 0), velocity.Z)
			body.AssemblyAngularVelocity = Vector3.new(0, spin, 0)
		elseif math.abs(v.X) + math.abs(v.Z) > 0.02 or body.AssemblyAngularVelocity.Magnitude > 0.02 then
			body.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), 0)
			body.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

function FurnitureController.start()
	folder = workspace:WaitForChild("Furniture")
	overlap.FilterDescendantsInstances = { folder }
	claimRemote = Remotes.unreliable("PushClaim")
	folder.ChildAdded:Connect(function(child)
		task.spawn(track, child)
	end)
	for _, child in folder:GetChildren() do
		task.spawn(track, child)
	end
	-- Before physics, so the velocities we set are used this very frame.
	RunService.PreSimulation:Connect(step)
end

return FurnitureController
