-- A short horizontal shove. Runs on whichever machine simulates the character:
-- the owning client for players (the server asks it to via a remote) and the
-- server for test bots. A LinearVelocity is used because a Humanoid instantly
-- cancels velocity that is simply assigned to its root.

local RunService = game:GetService("RunService")

local Knockback = {}

function Knockback.apply(character: Model, velocity: Vector3, seconds: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude < 0.01 or seconds <= 0 then
		return
	end

	local old = root:FindFirstChild("KnockbackForce")
	if old then
		old:Destroy()
	end
	local attachment = root:FindFirstChild("KnockbackAttachment") :: Attachment?
	if not attachment then
		local created = Instance.new("Attachment")
		created.Name = "KnockbackAttachment"
		created.Parent = root
		attachment = created
	end

	local force = Instance.new("LinearVelocity")
	force.Name = "KnockbackForce"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	force.PrimaryTangentAxis = Vector3.xAxis
	force.SecondaryTangentAxis = Vector3.zAxis
	force.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	force.MaxForce = math.max(root.AssemblyMass, 1) * 4000
	force.PlaneVelocity = Vector2.new(flat.X, flat.Z)
	force.Parent = root

	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = (os.clock() - started) / seconds
		if t >= 1 or force.Parent == nil then
			connection:Disconnect()
			force:Destroy()
			return
		end
		local k = 1 - t
		force.PlaneVelocity = Vector2.new(flat.X * k, flat.Z * k)
	end)
end

return Knockback
