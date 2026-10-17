-- Plays what the server announces: your own knockback, item swings, potato
-- splats, shotgun blasts, wall debris, infection bursts and sounds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.ClientState)
local Knockback = require(ReplicatedStorage.Shared.Knockback)
local Parts = require(ReplicatedStorage.Shared.Parts)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(script.Parent.Sounds)

local Effects = {}

local Items = require(ReplicatedStorage.Shared.Items)
local ItemModels = require(ReplicatedStorage.Shared.ItemModels)

-- Plays an item's sound style (a SoundBank name) if it has one.
local function playStyle(style: string?, position: Vector3?): boolean
	if style and Sounds.has(style) then
		Sounds.play(style, position)
		return true
	end
	return false
end

local player = Players.LocalPlayer
local effectsFolder = workspace:WaitForChild("Effects")

local baseGrip: { [Weld]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function fadeAndRemove(part: BasePart, seconds: number, grow: Vector3?)
	local goal: { [string]: any } = { Transparency = 1 }
	if grow then
		goal.Size = grow
	end
	local tween = TweenService:Create(
		part,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	tween.Completed:Once(function()
		part:Destroy()
	end)
end

local function flatPart(position: Vector3, diameter: number, color: string): Part
	local part = Parts.disc("Fx", position, diameter, 0.1, color, effectsFolder)
	part.CanCollide = false
	part.CanQuery = false
	return part
end

-- Swings the held item around its grip (or thrusts a spear).
local function swing(character: Model?, itemId: string)
	if not character then
		return
	end
	local held = character:FindFirstChild("HeldItem")
	local handle = held and held:FindFirstChild("Handle")
	local weld = handle and handle:FindFirstChild("GripWeld") :: Weld?
	if not weld then
		return
	end
	local base = baseGrip[weld] or weld.C0
	baseGrip[weld] = base
	local thrust = itemId == "Spear" or itemId == "AncientSpear"
	local started = os.clock()
	local duration = if thrust then 0.22 else 0.28
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) / duration
		if t >= 1 or weld.Parent == nil then
			connection:Disconnect()
			if weld.Parent then
				weld.C0 = base
			end
			return
		end
		if thrust then
			local push = math.sin(t * math.pi) * 2.2
			weld.C0 = base * CFrame.new(0, 0, -push)
		else
			-- Sweep from the right side across to the left, then settle.
			local angle = if t < 0.6
				then math.rad(70) - (t / 0.6) * math.rad(130)
				else math.rad(-60) * (1 - (t - 0.6) / 0.4)
			weld.C0 = base * CFrame.Angles(0, angle, 0)
		end
	end)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local item = Items.get(itemId)
	if not playStyle(item and item.sound, root and root.Position) then
		Sounds.play(if thrust then "Lunge" else "Whoosh", root and root.Position)
	end
end

-- Little bits flying out from a point and fading (stars, feathers, crumbs...).
local BITS: { [string]: { colors: { string }, size: number, count: number, shape: Enum.PartType } } = {
	Stars = { colors = { "FFE14D", "FFFFFF", "FFC21A" }, size = 0.5, count = 6, shape = Enum.PartType.Block },
	Puff = { colors = { "FFFFFF", "EDEDED" }, size = 0.45, count = 4, shape = Enum.PartType.Ball },
	Feathers = {
		colors = { "FFFFFF", "FFF3B0", "FFE14D" },
		size = 0.45,
		count = 8,
		shape = Enum.PartType.Block,
	},
	Crumbs = { colors = { "D9A15C", "B5783A", "E8C28A" }, size = 0.3, count = 10, shape = Enum.PartType.Ball },
	Sparkle = {
		colors = { "FF5FA2", "7FD3FF", "FFFFFF", "FFE14D" },
		size = 0.35,
		count = 8,
		shape = Enum.PartType.Ball,
	},
	Confetti = {
		colors = { "E5484D", "F1C40F", "2ECC71", "3498DB", "9B59B6", "FF5FA2" },
		size = 0.35,
		count = 30,
		shape = Enum.PartType.Block,
	},
	Snow = { colors = { "FFFFFF", "E8F6FF" }, size = 0.35, count = 10, shape = Enum.PartType.Ball },
	Peel = { colors = { "F7DC6F", "FFFFFF", "FFE14D" }, size = 0.4, count = 7, shape = Enum.PartType.Block },
}

local function bits(kind: string, position: Vector3, direction: Vector3?, spread: number?)
	local spec = BITS[kind]
	if not spec then
		return
	end
	local rng = Random.new()
	for i = 1, spec.count do
		local part = Parts.make({
			name = "Bit",
			shape = spec.shape,
			size = Vector3.new(spec.size, 0.08, spec.size)
				* (if spec.shape == Enum.PartType.Ball then 1 else 1),
			cframe = CFrame.new(position + Vector3.new(0, 2, 0))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			color = spec.colors[(i - 1) % #spec.colors + 1],
			canCollide = false,
			canQuery = false,
			parent = effectsFolder,
		})
		if spec.shape == Enum.PartType.Ball then
			part.Size = Vector3.one * spec.size
		end
		local dir: Vector3
		if direction then
			local cone = spread or 0.6
			dir = (CFrame.Angles(0, rng:NextNumber(-cone, cone), 0) * direction) * rng:NextNumber(14, 34)
		else
			local a = rng:NextNumber(0, math.pi * 2)
			dir = Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(6, 14)
		end
		local finish = position + Vector3.new(dir.X, 0, dir.Z) * 0.35
		local info = TweenInfo.new(rng:NextNumber(0.4, 0.8), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(part, info, {
			CFrame = CFrame.new(finish + Vector3.new(0, 1, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			Transparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			part:Destroy()
		end)
	end
end

-- A temporary visual stuck to a character (plunger, bubble, ice).
local function stickTo(character: Model?, seconds: number, build: (root: BasePart) -> { BasePart })
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local parts = build(root)
	for _, part in parts do
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Parent = character
	end
	task.delay(seconds, function()
		for _, part in parts do
			part:Destroy()
		end
	end)
end

local function bodyScale(root: BasePart): number
	return root.Size.X / 2.2
end

-- Spray particles on everyone currently holding a water gun / leaf blower.
local SPRAY_COLORS = {
	WaterGun = ColorSequence.new(Color3.fromHex("8FD3F5"), Color3.fromHex("E8F6FF")),
	LeafBlower = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("6BBF4E")),
		ColorSequenceKeypoint.new(0.5, Color3.fromHex("E8913A")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("C0392B")),
	}),
}

local function characters(): { Instance }
	local list = workspace:GetChildren()
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		for _, bot in bots:GetChildren() do
			table.insert(list, bot)
		end
	end
	return list
end

local function updateSprays()
	for _, character in characters() do
		if character:IsA("Model") and character:GetAttribute("ParticipantId") then
			local spraying = character:GetAttribute("Spraying")
			local held = character:FindFirstChild("HeldItem")
			local handle = held and held:FindFirstChild("Handle")
			if handle then
				local emitter = handle:FindFirstChild("Spray", true) :: ParticleEmitter?
				if spraying and not emitter then
					local attachment = Instance.new("Attachment")
					attachment.Name = "SprayAt"
					attachment.CFrame = CFrame.new(0, 0, -4.3)
					attachment.Parent = handle
					local created = Instance.new("ParticleEmitter")
					created.Name = "Spray"
					created.Color = SPRAY_COLORS[spraying] or SPRAY_COLORS.WaterGun
					created.EmissionDirection = Enum.NormalId.Front
					created.Speed = NumberRange.new(28, 40)
					created.SpreadAngle = Vector2.new(if spraying == "LeafBlower" then 18 else 6, 4)
					created.Lifetime = NumberRange.new(0.35, 0.5)
					created.Rate = 70
					created.Size = NumberSequence.new(if spraying == "LeafBlower" then 0.9 else 0.6, 0.2)
					created.LightEmission = 0.2
					created.Parent = attachment
					emitter = created
				end
				if emitter then
					emitter.Enabled = spraying ~= nil
				end
			end
		end
	end
end

local function blast(origin: Vector3, direction: Vector3, reach: number)
	for _, angle in { -0.3, -0.15, 0, 0.15, 0.3 } do
		local dir = CFrame.Angles(0, angle, 0) * direction
		local mid = origin + dir * (reach / 2)
		local tracer = Parts.make({
			name = "Pellet",
			size = Vector3.new(0.25, 0.25, reach),
			cframe = CFrame.lookAt(mid, mid + dir),
			color = "FFE36E",
			material = Enum.Material.Neon,
			canCollide = false,
			canQuery = false,
			parent = effectsFolder,
		})
		fadeAndRemove(tracer, 0.18)
	end
	local flash = flatPart(origin + direction * 2 + Vector3.new(0, 1, 0), 3, "FFF3B0")
	flash.Material = Enum.Material.Neon
	fadeAndRemove(flash, 0.15, flash.Size * 1.6)
	Sounds.play("Shotgun", origin, 0.8)
end

local function debris(cframe: CFrame, size: Vector3)
	local rng = Random.new()
	for _ = 1, 8 do
		local offset = Vector3.new(
			rng:NextNumber(-size.X / 2, size.X / 2),
			rng:NextNumber(-1, 3),
			rng:NextNumber(-size.Z / 2, size.Z / 2)
		)
		local chunk = Parts.make({
			name = "Debris",
			size = Vector3.one * rng:NextNumber(0.8, 1.8),
			cframe = cframe * CFrame.new(offset),
			color = "4A4A4A",
			anchored = false,
			canCollide = false,
			canQuery = false,
			parent = effectsFolder,
		})
		chunk.AssemblyLinearVelocity =
			Vector3.new(rng:NextNumber(-25, 25), rng:NextNumber(20, 40), rng:NextNumber(-25, 25))
		task.delay(1.2, function()
			chunk:Destroy()
		end)
	end
end

local function burst(position: Vector3, color: string, size: number)
	local ring = flatPart(Vector3.new(position.X, 0.6, position.Z), 2, color)
	ring.Transparency = 0.2
	fadeAndRemove(ring, 0.45, Vector3.new(0.1, size, size))
end

local HANDLERS: { [string]: (data: { [string]: any }) -> () } = {
	Swing = function(data)
		swing(data.character, data.item)
	end,
	Shoot = function(data)
		local character = data.character :: Model?
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		Sounds.play("Shoot", root and root.Position)
	end,
	Splat = function(data)
		local look = data.look
		if look == "Snowball" then
			bits("Snow", data.position)
		elseif look == "Bubble" then
			burst(data.position, "BFE9FF", 5)
			playStyle("Pop", data.position)
		elseif look == "Pebble" then
			burst(data.position, "8C8C8C", 2.5)
		else
			burst(data.position, "C9A66B", 4)
			Sounds.play("Splat", data.position)
		end
	end,
	Blast = function(data)
		if data.item == "ConfettiCannon" then
			bits("Confetti", data.origin, data.direction, 0.6)
			playStyle("Pop", data.origin)
			playStyle("Squeak", data.origin)
		else
			blast(data.origin, data.direction, data.reach)
		end
	end,
	Hit = function(data)
		bits(data.fx, data.position)
		Sounds.play("Hit", data.position)
	end,
	Plunged = function(data)
		local target = data.character :: Model?
		local hit = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
		Sounds.play("Plunge", hit and hit.Position)
		stickTo(data.character, data.seconds, function(root)
			local s = bodyScale(root)
			local plunger = ItemModels.build("Plunger")
			-- Cup on the face, stick pointing straight out the front.
			plunger:PivotTo(
				root.CFrame
					* CFrame.new(0, 1.2 * s, -1.0 * s)
					* CFrame.Angles(0, math.pi, 0)
					* CFrame.new(0, 0, 3.4)
			)
			local parts = {}
			for _, part in plunger:GetDescendants() do
				if part:IsA("BasePart") and part.Name ~= "Handle" then
					for _, weld in part:GetChildren() do
						if weld:IsA("Weld") then
							weld:Destroy()
						end
					end
					table.insert(parts, part)
				end
			end
			return parts
		end)
	end,
	Bubbled = function(data)
		local character = data.character :: Model?
		local inside = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		Sounds.play("Bubble", inside and inside.Position)
		stickTo(character, data.seconds, function(root)
			local s = bodyScale(root)
			local bubble = Parts.make({
				name = "Bubble",
				shape = Enum.PartType.Ball,
				size = Vector3.one * 5.2 * s,
				cframe = root.CFrame,
				color = "BFE9FF",
				transparency = 0.6,
			})
			local shine = Parts.make({
				name = "Shine",
				shape = Enum.PartType.Ball,
				size = Vector3.one * 1.1 * s,
				cframe = root.CFrame * CFrame.new(-1.2 * s, 1.9 * s, -1.0 * s),
				color = "FFFFFF",
				transparency = 0.3,
			})
			return { bubble, shine }
		end)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			task.delay(data.seconds, function()
				burst(root.Position, "BFE9FF", 7)
				playStyle("Pop", root.Position)
			end)
		end
	end,
	Frozen = function(data)
		local character = data.character :: Model?
		if not character then
			return
		end
		local ice = Instance.new("Highlight")
		ice.FillColor = Color3.fromHex("9FE3FF")
		ice.FillTransparency = 0.45
		ice.OutlineColor = Color3.new(1, 1, 1)
		ice.DepthMode = Enum.HighlightDepthMode.Occluded
		ice.Parent = character
		task.delay(data.seconds, function()
			ice:Destroy()
		end)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			bits("Snow", root.Position)
			Sounds.play("Freeze", root.Position)
		end
	end,
	Slip = function(data)
		bits("Peel", data.position)
		bits("Stars", data.position)
		playStyle("Slip", data.position)
	end,
	Drop = function(data)
		Sounds.play("Drop", data.position)
	end,
	Gulp = function(data)
		bits("Sparkle", data.position)
		playStyle("Gulp", data.position)
	end,
	Boom = function(data)
		bits("Feathers", data.position)
		burst(data.position, "FFD93B", 16)
		Sounds.play("Boom", data.position)
	end,
	WallBreak = function(data)
		debris(data.cframe, data.size)
		Sounds.play("WallBreak", data.cframe.Position)
	end,
	Infect = function(data)
		burst(data.position, "7BC043", 10)
		Sounds.play("Infect", data.position)
		task.delay(0.35, function()
			Sounds.play("Groan", data.position, 0.8)
		end)
	end,
	Eat = function(data)
		burst(data.position, "F4F4F4", 4)
		Sounds.play("Eat", data.position)
	end,
	Pickup = function(data)
		Sounds.play("Pickup", data.position)
	end,
	Outbreak = function()
		Sounds.play("Outbreak")
	end,
	RoundEnd = function(data)
		-- A happy chime if your side won, a sad one if it didn't.
		local zombie = ClientState.isZombie()
		local won = (data.winner == "Survivors" and not zombie) or (data.winner == "Zombies" and zombie)
		Sounds.play(if won then "RoundWin" else "RoundLose")
	end,
	Wizard = function(data)
		bits("Sparkle", data.position)
		Sounds.play("Wizard")
	end,
	Warp = function(data)
		Sounds.play("Warp", data.position)
	end,
}

-- Bumping into another character: a soft thud and a little puff where you
-- touched, so collisions read clearly. Your character's "Shell" is the
-- body-sized cylinder only other characters collide with.
local BUMP_COOLDOWN = 0.4
local lastBump = 0

local function watchShell(character: Model)
	local function hook(shell: Instance)
		if not shell:IsA("BasePart") or shell.Name ~= "Shell" then
			return
		end
		shell.Touched:Connect(function(other)
			if other.Name ~= "Shell" or other:IsDescendantOf(character) then
				return
			end
			local now = os.clock()
			if now - lastBump < BUMP_COOLDOWN then
				return
			end
			lastBump = now
			local between = (shell.Position + other.Position) / 2
			playStyle("Bump", between)
			bits("Puff", between)
		end)
	end
	character.ChildAdded:Connect(hook)
	for _, child in character:GetChildren() do
		hook(child)
	end
end

function Effects.start()
	player.CharacterAdded:Connect(watchShell)
	if player.Character then
		watchShell(player.Character)
	end
	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(function()
				updateSprays()
				return true
			end)
			if not ok then
				warn("[Fx] spray: " .. tostring(err))
			end
		end
	end)
	Remotes.event("Knockback").OnClientEvent:Connect(function(velocity: Vector3, seconds: number)
		local character = player.Character
		if character and typeof(velocity) == "Vector3" then
			Knockback.apply(character, velocity, seconds)
		end
	end)
	Remotes.event("Fx").OnClientEvent:Connect(function(kind: string, data: { [string]: any })
		local handler = HANDLERS[kind]
		if handler then
			local ok, err = pcall(function()
				handler(data or {})
				return true
			end)
			if not ok then
				warn("[Fx] " .. kind .. ": " .. tostring(err))
			end
		end
	end)
end

return Effects
