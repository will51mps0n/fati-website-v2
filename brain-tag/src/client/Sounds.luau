-- Plays the game's sounds (recipes in SoundBank), quieter the farther they
-- happen from you (the camera is far overhead, so normal 3D falloff would
-- make everything silent). A sound named in Config.SOUND_OVERRIDES plays that
-- uploaded sound instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundBank = require(script.Parent.SoundBank)

local Sounds = {}

local enabled = true
local player = Players.LocalPlayer
local HEARING = 90
local rng = Random.new()

function Sounds.setEnabled(on: boolean)
	enabled = on
end

function Sounds.enabled(): boolean
	return enabled
end

function Sounds.has(name: string?): boolean
	return name ~= nil
		and (SoundBank.RECIPES[name] ~= nil or (Config.SOUND_OVERRIDES :: { [string]: string })[name] ~= nil)
end

local function listener(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

local EFFECTS: { [string]: () -> SoundEffect } = {
	Echo = function()
		local e = Instance.new("EchoSoundEffect")
		e.Delay = 0.07
		e.Feedback = 0.35
		e.WetLevel = -4
		return e
	end,
	Distort = function()
		local e = Instance.new("DistortionSoundEffect")
		e.Level = 0.55
		return e
	end,
	Tremolo = function()
		local e = Instance.new("TremoloSoundEffect")
		e.Frequency = 14
		e.Depth = 0.8
		return e
	end,
	Flange = function()
		local e = Instance.new("FlangeSoundEffect")
		e.Mix = 0.8
		e.Rate = 5
		e.Depth = 0.6
		return e
	end,
	Reverb = function()
		local e = Instance.new("ReverbSoundEffect")
		e.DecayTime = 0.9
		e.WetLevel = -6
		return e
	end,
	Muffle = function()
		local e = Instance.new("EqualizerSoundEffect")
		e.HighGain = -25
		e.MidGain = -6
		e.LowGain = 4
		return e
	end,
	Thin = function()
		local e = Instance.new("EqualizerSoundEffect")
		e.LowGain = -20
		e.MidGain = 2
		e.HighGain = 4
		return e
	end,
}

-- Builds (but doesn't play) one note.
local function make(note: SoundBank.Note, volume: number, pitch: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = SoundBank.FILES[note.file] or ""
	sound.Volume = (note.volume or 0.6) * volume
	sound.PlaybackSpeed = (note.pitch or 1) * pitch
	if note.from or note.to then
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(note.from or 0, note.to or 60)
	end
	local effects: { string } = note.effects or {}
	for _, name in effects do
		local build = EFFECTS[name]
		if build then
			build().Parent = sound
		end
	end
	sound.Parent = SoundService
	return sound
end

local function playOnce(sound: Sound)
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(8, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- `volume` and `pitch` scale the recipe's own values.
function Sounds.play(name: string, position: Vector3?, volume: number?, pitch: number?)
	if not enabled then
		return
	end
	local v = volume or 1
	if position then
		local here = listener()
		if here then
			local dx, dz = position.X - here.X, position.Z - here.Z
			v *= math.clamp(1 - math.sqrt(dx * dx + dz * dz) / HEARING, 0, 1)
		end
		if v < 0.03 then
			return
		end
	end
	local p = (pitch or 1) * rng:NextNumber(0.96, 1.04) -- a little variety
	local override = (Config.SOUND_OVERRIDES :: { [string]: string })[name]
	if override and override ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = override
		sound.Volume = 0.6 * v
		sound.PlaybackSpeed = p
		sound.Parent = SoundService
		playOnce(sound)
		return
	end
	local recipe = SoundBank.RECIPES[name]
	if not recipe then
		return
	end
	for _, n in recipe do
		if n.delay and n.delay > 0 then
			task.delay(n.delay, function()
				if enabled then
					playOnce(make(n, v, p))
				end
			end)
		else
			playOnce(make(n, v, p))
		end
	end
end

-- A looping sound you switch on and off (sprays, scraping, footsteps). Uses
-- the first note of the recipe.
function Sounds.loop(name: string): Sound?
	local override = (Config.SOUND_OVERRIDES :: { [string]: string })[name]
	local recipe = SoundBank.RECIPES[name]
	local sound: Sound
	if override and override ~= "" then
		sound = Instance.new("Sound")
		sound.SoundId = override
		sound.Parent = SoundService
	elseif recipe and recipe[1] then
		sound = make(recipe[1], 1, 1)
	else
		return nil
	end
	sound.Looped = true
	return sound
end

return Sounds
