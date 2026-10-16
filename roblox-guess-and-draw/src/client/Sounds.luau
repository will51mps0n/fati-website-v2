-- Plays the UI sound effects listed in Config.SOUNDS. Sounds without an ID are skipped.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("GuessAndDraw"):WaitForChild("Config"))

local Sounds = {}

Sounds.muted = false

local folder = Instance.new("Folder")
folder.Name = "GuessAndDrawSounds"
folder.Parent = SoundService

local templates: { [string]: Sound } = {}
for name, id in Config.SOUNDS do
	if typeof(id) == "string" and id ~= "" then
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = id
		sound.Parent = folder
		templates[name] = sound
	end
end

task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync(folder:GetChildren())
	end)
end)

-- `volume` scales Config.SOUND_VOLUME, so 0.5 plays at half the normal loudness.
function Sounds.play(name: string, volume: number?)
	local template = templates[name]
	if not template or Sounds.muted then
		return
	end
	-- A fresh copy per play lets the same sound overlap itself (fast ticks, many guesses).
	local sound = template:Clone()
	sound.Volume = Config.SOUND_VOLUME * (volume or 1)
	sound.Parent = folder
	sound:Play()
	Debris:AddItem(sound, 6)
end

return Sounds
