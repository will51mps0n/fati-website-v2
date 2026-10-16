-- The top-down "blob" look: a flat round head with two round fists in front,
-- plus an optional skin hat. Used on live characters (server) and for skin
-- previews in the shop (client). Front is -Z of the root, like every Roblox
-- character.

local Config = require(script.Parent.Config)
local Parts = require(script.Parent.Parts)
local Skins = require(script.Parent.Skins)

local C = Config.CHARACTER

local CharacterLook = {}

local function attach(root: BasePart, part: BasePart, offset: CFrame, model: Instance)
	Parts.makeVisual(part)
	part.CFrame = root.CFrame * offset -- also correct inside ViewportFrames, which never solve joints
	part:SetAttribute("LookPart", true)
	part.Parent = model
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
end

local function disc(name: string, diameter: number, height: number, color: string): Part
	return Parts.make({
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, diameter, diameter),
		cframe = CFrame.identity,
		color = color,
		anchored = false,
	})
end

local function block(name: string, size: Vector3, color: string): Part
	return Parts.make({ name = name, size = size, cframe = CFrame.identity, color = color, anchored = false })
end

local function ball(name: string, diameter: number, color: string): Part
	return Parts.make({
		name = name,
		shape = Enum.PartType.Ball,
		size = Vector3.one * diameter,
		cframe = CFrame.identity,
		color = color,
		anchored = false,
	})
end

local UP = Parts.UPRIGHT

-- Hats are drawn on top of the head. `s` is the character scale; the head's
-- top surface is at y = s above the root center.
type HatBuilder = (model: Model, root: BasePart, s: number) -> ()

local HATS: { [string]: HatBuilder } = {
	ChefHat = function(model, root, s)
		attach(root, disc("Hat", 2.6 * s, 0.3 * s, "D8DCE2"), CFrame.new(0, 1.1 * s, 0) * UP, model)
		attach(root, disc("Hat", 2.2 * s, 0.6 * s, "FFFFFF"), CFrame.new(0, 1.45 * s, 0.1 * s) * UP, model)
	end,
	Headband = function(model, root, s)
		attach(root, disc("Hat", 3.3 * s, 0.35 * s, "D7263D"), CFrame.new(0, 0.7 * s, 0) * UP, model)
		for side = -1, 1, 2 do
			local tail = block("Hat", Vector3.new(0.3, 0.2, 1.3) * s, "D7263D")
			attach(
				root,
				tail,
				CFrame.new(side * 0.25 * s, 0.75 * s, 1.95 * s) * CFrame.Angles(0, side * 0.35, 0),
				model
			)
		end
	end,
	Stem = function(model, root, s)
		for _, x in { -0.6, 0.6 } do
			attach(
				root,
				block("Hat", Vector3.new(0.16, 0.05, 2.4) * s, "C86412"),
				CFrame.new(x * s, 1.02 * s, 0),
				model
			)
		end
		attach(root, disc("Hat", 0.55 * s, 0.6 * s, "3E8E3A"), CFrame.new(0, 1.25 * s, 0) * UP, model)
		attach(
			root,
			block("Hat", Vector3.new(0.7, 0.08, 0.4) * s, "4CAF50"),
			CFrame.new(0.45 * s, 1.3 * s, 0.1 * s),
			model
		)
	end,
	Bill = function(model, root, s)
		attach(
			root,
			block("Hat", Vector3.new(1.3, 0.25, 1.2) * s, "F28C1C"),
			CFrame.new(0, 0.6 * s, -1.75 * s),
			model
		)
	end,
	Visor = function(model, root, s)
		attach(root, disc("Hat", 1.7 * s, 0.2 * s, "7FC8F8"), CFrame.new(0, 1.05 * s, -0.45 * s) * UP, model)
		attach(root, ball("Hat", 0.45 * s, "9AA3AE"), CFrame.new(0.75 * s, 1.1 * s, 0.6 * s), model)
	end,
	Crown = function(model, root, s)
		attach(root, disc("Hat", 2.0 * s, 0.4 * s, "F5C542"), CFrame.new(0, 1.15 * s, 0) * UP, model)
		attach(root, disc("Hat", 1.5 * s, 0.42 * s, "B3242F"), CFrame.new(0, 1.16 * s, 0) * UP, model)
		for i = 0, 4 do
			local angle = i / 5 * math.pi * 2
			local point = ball("Hat", 0.42 * s, "F5C542")
			attach(
				root,
				point,
				CFrame.new(math.sin(angle) * 0.95 * s, 1.4 * s, math.cos(angle) * 0.95 * s),
				model
			)
		end
	end,
	Spots = function(model, root, s)
		for _, spot in { { -0.5, -0.3, 0.6 }, { 0.6, 0.2, 0.45 }, { -0.1, 0.7, 0.35 } } do
			attach(
				root,
				disc("Hat", spot[3] * s, 0.05 * s, "5E9E22"),
				CFrame.new(spot[1] * s, 1.02 * s, spot[2] * s) * UP,
				model
			)
		end
	end,
	Frost = function(model, root, s)
		for _, spot in { { -0.6, -0.2, 0.55 }, { 0.5, 0.5, 0.4 }, { 0.3, -0.7, 0.35 }, { -0.2, 0.6, 0.3 } } do
			attach(
				root,
				disc("Hat", spot[3] * s, 0.05 * s, "F2FBFF"),
				CFrame.new(spot[1] * s, 1.02 * s, spot[2] * s) * UP,
				model
			)
		end
	end,
	Bandage = function(model, root, s)
		for i, angle in { -0.5, 0.15, 0.8 } do
			local strip = block("Hat", Vector3.new(2.5, 0.05, 0.38) * s, "F4EFE1")
			attach(
				root,
				strip,
				CFrame.new(0, (1.01 + i * 0.01) * s, (i - 2) * 0.5 * s) * CFrame.Angles(0, angle, 0),
				model
			)
		end
	end,
}

-- Builds (or rebuilds) the head, fists and hat on `model`. Keeps an existing
-- part named "Head" so anything attached to it (name tag, chat bubbles) survives.
function CharacterLook.apply(model: Model, root: BasePart, skinId: string?, team: Skins.Team, scale: number)
	local skin = Skins.resolve(skinId, team)

	for _, child in model:GetChildren() do
		if child:GetAttribute("LookPart") and child.Name ~= "Head" then
			child:Destroy()
		end
	end

	local head = model:FindFirstChild("Head") :: Part?
	if head then
		local oldWeld = head:FindFirstChild("Weld")
		if oldWeld then
			oldWeld:Destroy()
		end
	else
		head = Instance.new("Part")
	end
	assert(head, "head")
	head.Name = "Head"
	head.Shape = Enum.PartType.Cylinder
	head.Size = Vector3.new(C.HeadThickness, C.HeadDiameter, C.HeadDiameter) * scale
	head.Color = Color3.fromHex(skin.head)
	head.Material = Enum.Material.SmoothPlastic
	head.CastShadow = false
	head.TopSurface = Enum.SurfaceType.Smooth
	head.BottomSurface = Enum.SurfaceType.Smooth
	attach(root, head, CFrame.new(0, 0.5 * scale, 0) * UP, model)

	local zombie = team == "Zombie"
	local fx = if zombie then 0.75 else 0.95
	local fz = if zombie then -2.05 else -1.45
	for side = -1, 1, 2 do
		local fist = ball("Fist", C.FistDiameter * scale, skin.fist)
		fist.Name = if side < 0 then "LeftFist" else "RightFist"
		attach(root, fist, CFrame.new(side * fx * scale, 0.1 * scale, fz * scale), model)
	end

	local hat = skin.hat and HATS[skin.hat]
	if hat then
		hat(model, root, scale)
	end
end

-- A standalone, anchored preview model for ViewportFrames.
function CharacterLook.preview(skinId: string, team: Skins.Team): Model
	local model = Instance.new("Model")
	model.Name = "Preview"
	local root = Parts.make({
		name = "HumanoidRootPart",
		size = Vector3.new(C.RootWidth, C.RootHeight, C.RootWidth),
		cframe = CFrame.identity,
		color = "FFFFFF",
		transparency = 1,
		parent = model,
	})
	model.PrimaryPart = root
	CharacterLook.apply(model, root, skinId, team, 1)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	return model
end

return CharacterLook
