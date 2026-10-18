-- Dark maps (MapThemes with dark = true, like the haunted house): a lantern
-- follows your own character, lit only on your screen, so you see what's
-- near you and little beyond. Other people's name tags show only within the
-- theme's sight (BushController asks `sees`).
--
-- The lantern is a light on an attachment in Terrain, not on a part: there
-- is nothing around it that could block it, nothing a respawn, a new look
-- or a new map can destroy, and it casts no shadows. Every frame it reads
-- the map's theme again and moves to you, so it can't get stuck off.

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

local holder: Attachment? = nil
local light: PointLight? = nil

local function lantern(): (Attachment, PointLight)
	local at, lamp = holder, light
	if at and lamp and at.Parent == workspace.Terrain and lamp.Parent == at then
		return at, lamp
	end
	if at then
		at:Destroy()
	end
	local made = Instance.new("Attachment")
	made.Name = "MyLantern"
	local madeLight = Instance.new("PointLight")
	madeLight.Shadows = false
	madeLight.Parent = made
	made.Parent = workspace.Terrain
	holder, light = made, madeLight
	return made, madeLight
end

local function currentTheme(): MapThemes.Theme
	local map = workspace:FindFirstChild("Map")
	local name = map and map:GetAttribute("Theme")
	return MapThemes.get(if typeof(name) == "string" then name else nil)
end

local function updateLantern()
	theme = currentTheme()
	local at, lamp = lantern()
	local settings = theme.lantern
	local root = myRoot()
	local camera = workspace.CurrentCamera
	-- No character for a moment (respawning)? Light where the camera looks.
	local center = if root then root.Position elseif camera then camera.Focus.Position else nil
	if theme.dark and settings and center then
		local scale = if root then math.max(1, root.Size.Y / 2) else 1
		at.WorldPosition = center + Vector3.new(0, 2 + scale, 0)
		lamp.Range = settings.range
		lamp.Brightness = settings.brightness
		lamp.Color = Color3.fromHex(settings.color)
		lamp.Enabled = true
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
	updateLantern()
	RunService.RenderStepped:Connect(updateLantern)
end

return DarknessController
