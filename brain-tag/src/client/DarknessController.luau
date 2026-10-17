-- Dark maps (MapThemes with dark = true, like the haunted house): a lantern
-- hangs on your own character, lit only on your screen, so you see what's
-- near you and little beyond. Walls and closed doors stop its light. Other
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

local function updateLantern()
	local root = myRoot()
	if not root then
		return
	end
	local lamp = root:FindFirstChild("Lantern") :: PointLight?
	local lantern = theme.lantern
	if theme.dark and lantern then
		if not lamp then
			local made = Instance.new("PointLight")
			made.Name = "Lantern"
			made.Shadows = true
			made.Parent = root
			lamp = made
		end
		assert(lamp, "lamp")
		lamp.Range = lantern.range
		lamp.Brightness = lantern.brightness
		lamp.Color = Color3.fromHex(lantern.color)
	elseif lamp then
		lamp:Destroy()
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
	-- Characters (and their root) are rebuilt on respawn and resize: check
	-- now and then that the lantern is still on the current one.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 0.5 then
			elapsed = 0
			updateLantern()
		end
	end)
end

return DarknessController
