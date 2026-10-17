-- Straight-down camera that follows your character. A narrow field of view
-- from high up gives the flat, near-orthographic 2D look. Screen up is world
-- -Z. No zoom or rotation (the Settings panel offers three fixed heights).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)

local CameraController = {}

local player = Players.LocalPlayer
local height = Config.CAMERA_HEIGHT
local focus: Vector3? = nil
local SCREEN_UP = Vector3.new(0, 0, -1)

function CameraController.setHeight(newHeight: number)
	height = newHeight
end

function CameraController.height(): number
	return height
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Config.CAMERA_FOV

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local target = Vector3.new(root.Position.X, 0, root.Position.Z)
		if not focus or (focus - target).Magnitude > 60 then
			focus = target -- snap after spawns and teleports
		else
			focus = focus:Lerp(target, 1 - math.exp(-Config.CAMERA_SMOOTHING * dt))
		end
	end
	if focus then
		-- Bigger players see a little more around them.
		local scale = ClientState.my("Scale") or 1
		local eye = height * (1 + (scale - 1) * Config.CAMERA_GROWTH)
		camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, eye, 0), focus, SCREEN_UP)
	end
end

function CameraController.start()
	RunService:BindToRenderStep("BrainTagCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
