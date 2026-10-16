-- Plays short 2D sounds, quieter the farther they happen from you (the
-- camera is far overhead, so normal 3D falloff would make everything silent).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local Sounds = {}

local enabled = true
local player = Players.LocalPlayer
local HEARING = 90

function Sounds.setEnabled(on: boolean)
	enabled = on
end

function Sounds.enabled(): boolean
	return enabled
end

local function listener(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position
end

function Sounds.play(name: string, position: Vector3?, volume: number?, pitch: number?)
	if not enabled then
		return
	end
	local id = (Config.SOUNDS :: { [string]: string })[name]
	if not id or id == "" then
		return
	end
	local v = volume or 0.6
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
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = v
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
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

-- A looping sound you can switch on and off (furniture scraping).
function Sounds.loop(name: string): Sound?
	local id = (Config.SOUNDS :: { [string]: string })[name]
	if not id or id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	return sound
end

return Sounds
