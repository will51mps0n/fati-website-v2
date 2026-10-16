-- Plays what the server announces: your own knockback, item swings, potato
-- splats, shotgun blasts, wall debris, infection bursts and sounds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Knockback = require(ReplicatedStorage.Shared.Knockback)
local Parts = require(ReplicatedStorage.Shared.Parts)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sounds = require(script.Parent.Sounds)

local Effects = {}

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
	Sounds.play(if thrust then "Lunge" else "Whoosh", root and root.Position)
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
		Sounds.play("Potato", root and root.Position)
	end,
	Splat = function(data)
		burst(data.position, "C9A66B", 4)
	end,
	Blast = function(data)
		blast(data.origin, data.direction, data.reach)
	end,
	WallBreak = function(data)
		debris(data.cframe, data.size)
	end,
	Infect = function(data)
		burst(data.position, "7BC043", 10)
		Sounds.play("Groan", data.position, 0.8)
	end,
	Eat = function(data)
		burst(data.position, "F4F4F4", 4)
		Sounds.play("Pickup", data.position, 0.5, 1.4)
	end,
	Pickup = function(data)
		Sounds.play("Pickup", data.position, 0.5)
	end,
	Outbreak = function()
		Sounds.play("Groan", nil, 0.7, 0.8)
	end,
	RoundEnd = function()
		Sounds.play("RoundEnd", nil, 0.7)
	end,
}

-- Furniture scrape loop (only if Config.SOUNDS.Scrape is set).
local function startScrape()
	local loop = Sounds.loop("Scrape")
	if not loop then
		return
	end
	local furniture = workspace:WaitForChild("Furniture")
	local playing = false
	task.spawn(function()
		while true do
			task.wait(0.15)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local moving = false
			if root and Sounds.enabled() then
				for _, model in furniture:GetChildren() do
					local body = model:FindFirstChild("Body") :: BasePart?
					if body and not body.Anchored and body.AssemblyLinearVelocity.Magnitude > 2 then
						if (body.Position - root.Position).Magnitude < 40 then
							moving = true
							break
						end
					end
				end
			end
			if moving and not playing then
				loop.Volume = 0.35
				loop:Play()
				playing = true
			elseif not moving and playing then
				loop:Stop()
				playing = false
			end
		end
	end)
end

function Effects.start()
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
	startScrape()
end

return Effects
