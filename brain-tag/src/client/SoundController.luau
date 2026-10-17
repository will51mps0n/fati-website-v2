-- Sounds that follow what's going on rather than one-off events: countdown
-- ticks in the last 10 seconds of prep and of the round, your footsteps,
-- water guns and leaf blowers spraying, furniture scraping, and zombies
-- groaning near you.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.ClientState)
local Sounds = require(script.Parent.Sounds)

local SoundController = {}

local player = Players.LocalPlayer
local HEARING = 90
local INTERVAL = 0.1
local rng = Random.new()

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

local function rootOf(model: Instance): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setPlaying(sound: Sound?, on: boolean)
	if not sound then
		return
	end
	if on and not sound.IsPlaying then
		sound:Play()
	elseif not on and sound.IsPlaying then
		sound:Stop()
	end
end

function SoundController.start()
	local footsteps = Sounds.loop("Footsteps")
	local footstepsPitch = if footsteps then footsteps.PlaybackSpeed else 1
	local scrape = Sounds.loop("Scrape")
	local sprays: { [Instance]: { sound: Sound, volume: number } } = {}
	local lastTick = -1
	local nextGroan = os.clock() + 5
	local furniture = workspace:WaitForChild("Furniture")

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < INTERVAL then
			return
		end
		elapsed = 0
		local on = Sounds.enabled()
		local character = player.Character
		local me = character and rootOf(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		-- Countdown ticks.
		local phase = ClientState.phase()
		local left = ClientState.secondsLeft()
		if (phase == "Prep" or phase == "Infection") and left > 0 and left <= 10 then
			local second = math.ceil(left)
			if second ~= lastTick then
				lastTick = second
				Sounds.play(if second <= 3 then "TickFinal" else "Tick")
			end
		else
			lastTick = -1
		end

		-- Your footsteps, faster when you're faster.
		local walking = on
			and humanoid ~= nil
			and humanoid.Health > 0
			and humanoid.WalkSpeed > 0
			and humanoid.MoveDirection.Magnitude > 0.1
		if footsteps and humanoid then
			footsteps.PlaybackSpeed = footstepsPitch * math.clamp(humanoid.WalkSpeed / 16, 0.8, 1.5)
		end
		setPlaying(footsteps, walking)

		-- Furniture scraping along the floor near you.
		local scraping = false
		if on and me then
			for _, model in furniture:GetChildren() do
				local body = model:FindFirstChild("Body") :: BasePart?
				if body and not body.Anchored and body.AssemblyLinearVelocity.Magnitude > 2 then
					if (body.Position - me.Position).Magnitude < 40 then
						scraping = true
						break
					end
				end
			end
		end
		setPlaying(scrape, scraping)

		-- Water guns and leaf blowers, louder the closer they are.
		local seen: { [Instance]: boolean } = {}
		for _, model in characters() do
			local kind = model:GetAttribute("Spraying")
			local root = rootOf(model)
			if on and typeof(kind) == "string" and root then
				seen[model] = true
				local entry = sprays[model]
				if not entry then
					local sound = Sounds.loop(if kind == "LeafBlower" then "Blower" else "Spray")
					if sound then
						entry = { sound = sound, volume = sound.Volume }
						sprays[model] = entry
						sound:Play()
					end
				end
				if entry then
					local distance = if me then (root.Position - me.Position).Magnitude else 0
					entry.sound.Volume = entry.volume * math.clamp(1 - distance / HEARING, 0, 1)
				end
			end
		end
		for model, entry in sprays do
			if not seen[model] then
				entry.sound:Destroy()
				sprays[model] = nil
			end
		end

		-- Now and then a zombie near you groans.
		local now = os.clock()
		if on and me and now >= nextGroan then
			nextGroan = now + rng:NextNumber(4, 8)
			local nearby = {}
			for _, model in characters() do
				local root = rootOf(model)
				if model ~= character and root and model:GetAttribute("Team") == "Zombie" then
					if (root.Position - me.Position).Magnitude < 70 then
						table.insert(nearby, root)
					end
				end
			end
			if #nearby > 0 then
				local root = nearby[rng:NextInteger(1, #nearby)]
				Sounds.play("Groan", root.Position, 0.6, rng:NextNumber(0.9, 1.15))
			end
		end
	end)
end

return SoundController
