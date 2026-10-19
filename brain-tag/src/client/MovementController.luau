-- Moves the character in SCREEN directions (W = up the screen = world -Z)
-- and turns it to face the mouse. On touch screens and gamepads, where there
-- is no mouse, the character faces the way it walks instead.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.ClientState)
local ForceField = require(script.Parent.ForceField)

local MovementController = {}

local player = Players.LocalPlayer
local aim = Vector3.new(0, 0, -1)
local usingMouse = not UserInputService.TouchEnabled or UserInputService.MouseEnabled
local controls: any = nil
local aimRemote: UnreliableRemoteEvent? = nil
local lastAimSent = 0
local lastAimSentValue = Vector3.zero

local KEYS: { [Enum.KeyCode]: Vector3 } = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.Up] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.Down] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.Left] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
	[Enum.KeyCode.Right] = Vector3.new(1, 0, 0),
}

local MOUSE_INPUTS = {
	[Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseWheel] = true,
	[Enum.UserInputType.Keyboard] = true,
}

function MovementController.aim(): Vector3
	return aim
end

function MovementController.usingMouse(): boolean
	return usingMouse
end

local function rawMove(): Vector3
	local v = Vector3.zero
	-- Thumbsticks and gamepads come from Roblox's PlayerModule. Its vector is
	-- already in screen terms: -Z means "up the screen".
	if controls then
		local ok, mv = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(mv) == "Vector3" then
			v += mv
		end
	end
	if not UserInputService:GetFocusedTextBox() then
		-- Read keys directly too, so arrows always work. Counting a key twice
		-- is harmless because the result is normalized below.
		for key, direction in KEYS do
			if UserInputService:IsKeyDown(key) then
				v += direction
			end
		end
	end
	v = Vector3.new(v.X, 0, v.Z)
	if v.Magnitude > 1 then
		v = v.Unit
	end
	return v
end

local function step()
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	humanoid.AutoRotate = false

	local move = rawMove()
	humanoid:Move(move, false) -- false = world space, not camera space

	-- Sharp, like the original: full speed the instant a key goes down, a dead
	-- stop the instant it comes up (a Humanoid alone eases in and out). Left
	-- alone while a knockback shove is playing.
	-- Soft force fields from people and weapons nearby are added on top, so
	-- nobody stacks and pushing always meets a little resistance.
	if not root:FindFirstChild("KnockbackForce") then
		local v = root.AssemblyLinearVelocity
		-- Dragging a heavy piece slows you down (FurnitureController).
		local drag = character:GetAttribute("DragFactor")
		local speed = humanoid.WalkSpeed * (if typeof(drag) == "number" then drag else 1)
		local field =
			ForceField.velocity(root, aim, ClientState.my("HeldItem"), character:GetAttribute("Team"))
		root.AssemblyLinearVelocity = Vector3.new(move.X * speed + field.X, v.Y, move.Z * speed + field.Z)
	end

	local camera = workspace.CurrentCamera
	if usingMouse and camera then
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		if math.abs(ray.Direction.Y) > 1e-3 then
			local t = (root.Position.Y - ray.Origin.Y) / ray.Direction.Y
			local point = ray.Origin + ray.Direction * t
			local flat = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
			if flat.Magnitude > 0.5 then
				aim = flat.Unit
			end
		end
	elseif move.Magnitude > 0.1 then
		aim = move.Unit
	end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + aim)

	-- Keep the server's idea of your aim fresh (weapon pushes use it).
	local now = os.clock()
	if aimRemote and now - lastAimSent > 0.1 and aim:Dot(lastAimSentValue) < 0.995 then
		lastAimSent, lastAimSentValue = now, aim
		aimRemote:FireServer(aim)
	end
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.AutoRotate = false
	for _, state in
		{
			Enum.HumanoidStateType.Jumping,
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Seated,
			Enum.HumanoidStateType.Swimming,
		}
	do
		humanoid:SetStateEnabled(state, false)
	end
end

function MovementController.start()
	task.spawn(function()
		local Remotes = require(game:GetService("ReplicatedStorage").Shared.Remotes)
		aimRemote = Remotes.unreliable("Aim")
	end)
	task.spawn(function()
		local ok, module = pcall(function()
			return require(
					player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript
				) :: any
		end)
		if ok and module then
			controls = module:GetControls()
		else
			warn("[Movement] PlayerModule unavailable; keyboard only")
		end
	end)

	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		if MOUSE_INPUTS[inputType] then
			usingMouse = true
		elseif inputType == Enum.UserInputType.Touch or string.find(inputType.Name, "Gamepad") then
			usingMouse = false
		end
	end)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	-- Runs right after Roblox's own control script (priority Input), so our
	-- world-space move wins.
	RunService:BindToRenderStep("BrainTagMove", Enum.RenderPriority.Input.Value + 1, step)
end

return MovementController
