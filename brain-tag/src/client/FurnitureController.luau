-- Drives the furniture YOU are pushing, on your own machine, so it responds
-- instantly and stops the moment you stop. The server hands you a piece when
-- you claim it and takes it back if someone else pushes it too.
--
-- You move furniture by walking into it, with a zombie's arms, or with a
-- held weapon: its shaft is solid and pushes whatever it touches. Humans can
-- also grab the piece next to them (hold F): it comes with you, pulled or
-- pushed, and heavy pieces slow you down.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterLook = require(ReplicatedStorage.Shared.CharacterLook)
local ClientState = require(script.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local FurniturePush = require(ReplicatedStorage.Shared.FurniturePush)
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
local grabRemote: RemoteEvent
local held: BasePart? = nil -- the piece you're holding
local heldOffset = Vector3.zero -- where it stays, relative to you
local heldGlow: Highlight? = nil

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

-- Your walking speed while dragging (MovementController reads it).
local function setDrag(factor: number?)
	local character = player.Character
	if character and character:GetAttribute("DragFactor") ~= factor then
		character:SetAttribute("DragFactor", factor)
	end
end

function FurnitureController.release()
	local body = held
	if not body then
		return
	end
	held = nil
	if heldGlow then
		heldGlow:Destroy()
		heldGlow = nil
	end
	setDrag(nil)
	if body.Parent then
		grabRemote:FireServer(body.Parent, false)
	end
end

-- Grab the piece next to you (the one you face, if several).
function FurnitureController.grab()
	FurnitureController.release()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or ClientState.isZombie() then
		return
	end
	local scale = ClientState.my("Scale") or 1
	local around = (FurniturePush.bumperRadius(scale) + Config.GRAB_REACH) * 2 + 14
	local body = FurniturePush.pickGrab(
		root,
		scale,
		MovementController.aim(),
		query(CFrame.new(root.Position), Vector3.new(around, root.Size.Y + 4, around))
	)
	local model = body and body.Parent
	if not body or not model then
		return
	end
	held = body
	heldOffset = Vector3.new(body.Position.X - root.Position.X, 0, body.Position.Z - root.Position.Z)
	local glow = Instance.new("Highlight")
	glow.Name = "HeldGlow" -- ForceField skips the piece you hold
	glow.FillTransparency = 1
	glow.OutlineColor = Color3.fromHex(Config.COLORS.SelfName)
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Adornee = model
	glow.Parent = model
	heldGlow = glow
	grabRemote:FireServer(model, true)
end

local function collect(): FurniturePush.Pushes
	local pushes: FurniturePush.Pushes = {}
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		FurnitureController.release()
		return pushes
	end
	local scale = ClientState.my("Scale") or 1
	local strength = RoundRules.pushStrength(scale, ClientState.isZombie())
	local walk = humanoid.WalkSpeed
	local move = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
	local moving = move.Magnitude > 0.1 and walk > 0
	local dir = if moving then move.Unit else Vector3.zero

	-- The piece you're holding comes with you; you let go if it gets stuck.
	local body = held
	if body then
		if body.Parent == nil or ClientState.isZombie() then
			FurnitureController.release()
		else
			local desired, lag = FurniturePush.holdVelocity(root, heldOffset, body)
			if lag > Config.GRAB_BREAK then
				FurnitureController.release()
			else
				FurniturePush.add(pushes, body, desired, strength, nil)
				setDrag(FurniturePush.dragFactor(body, strength))
			end
		end
	end

	-- Walking into furniture.
	if moving then
		local probe, size = FurniturePush.moverProbe(root, dir, scale)
		for _, body in query(probe, size) do
			FurniturePush.add(pushes, body, dir * walk, strength, probe.Position)
		end
	end

	-- A zombie's arms are solid: walking, they push what they touch; standing
	-- or turning, they shove it out of the way.
	if ClientState.isZombie() and walk > 0 then
		local probe, size = FurniturePush.armsProbe(
			root,
			scale,
			CharacterLook.ZOMBIE_ARM_REACH,
			CharacterLook.ZOMBIE_ARM_SPAN
		)
		for _, body in query(probe, size) do
			if not pushes[body] then
				if moving then
					FurniturePush.add(pushes, body, dir * walk, strength, probe.Position)
				else
					local exit = FurniturePush.shaftExit(root.Position, probe.LookVector, body)
					FurniturePush.add(
						pushes,
						body,
						exit * walk * Config.SHAFT_FURNITURE_FACTOR,
						strength,
						nil
					)
				end
			end
		end
	end

	-- Weapons: the shaft pushes what it touches.
	local item = Items.get(ClientState.my("HeldItem"))
	if item and item.kind == "Melee" and not ClientState.isZombie() then
		local aim = MovementController.aim()
		local reach = (item.reach or 5) * Items.reachScale(scale)
		local grip = CharacterLook.grip(scale)
		local hand = (root.CFrame * grip).Position
		local probe, size = FurniturePush.itemProbe(root, grip, aim, reach, item.guard)
		local touched = query(probe, size)
		local firm = strength * (item.firmness or 1) -- a stiff bat shoves harder than a noodle
		-- The shaft is solid: what it overlaps moves out of the way.
		if walk > 0 then
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
	grabRemote = Remotes.event("Grab")
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
