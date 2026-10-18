-- Dark maps (MapThemes with dark = true, like the haunted house): a lantern
-- follows your own character, lit only on your screen, so you see what's
-- near you and little beyond. Walls stop its light. Other
-- people's name tags show only within the theme's sight (BushController
-- asks `sees`).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapThemes = require(ReplicatedStorage.Shared.MapThemes)

local DarknessController = {}

local player = Players.LocalPlayer
local theme = MapThemes.get("Classic")

local function myRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The lantern is its own invisible part on your machine, following you
-- every frame, so nothing that happens to your character (respawns, size
-- changes, a new round on another dark map) can ever switch it off.
local lanternPart: Part? = nil
local light: PointLight? = nil

local function lantern(): (Part, PointLight)
	local part, lamp = lanternPart, light
	if part and lamp and part.Parent then
		return part, lamp
	end
	local made = Instance.new("Part")
	made.Name = "MyLantern"
	made.Anchored = true
	made.CanCollide = false
	made.CanQuery = false
	made.CanTouch = false
	made.Transparency = 1
	made.Size = Vector3.new(0.2, 0.2, 0.2)
	local madeLight = Instance.new("PointLight")
	madeLight.Shadows = true
	madeLight.Parent = made
	made.Parent = workspace
	lanternPart, light = made, madeLight
	return made, madeLight
end

local function updateLantern()
	local part, lamp = lantern()
	local root = myRoot()
	local settings = theme.lantern
	if theme.dark and settings and root then
		part.CFrame = CFrame.new(root.Position + Vector3.new(0, 2, 0))
		lamp.Enabled = true
		lamp.Range = settings.range
		lamp.Brightness = settings.brightness
		lamp.Color = Color3.fromHex(settings.color)
	else
		lamp.Enabled = false
	end
end

function DarknessController.isDark(): boolean
	return theme.dark == true
end

-- Can you see someone standing at `position`?
function DarknessController.sees(position: Vector3): boolean
	if not theme.dark then
		return true
	end
	local root = myRoot()
	if not root then
		return true
	end
	local offset = position - root.Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= (theme.sight or 40)
end

function DarknessController.start()
	local map = workspace:WaitForChild("Map")
	local function refresh()
		local name = map:GetAttribute("Theme")
		theme = MapThemes.get(if typeof(name) == "string" then name else nil)
		updateLantern()
	end
	map:GetAttributeChangedSignal("Theme"):Connect(refresh)
	refresh()
	RunService.RenderStepped:Connect(updateLantern)
end

return DarknessController
