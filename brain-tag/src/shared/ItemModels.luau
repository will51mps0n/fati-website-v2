-- Builds the 3D look of every item from simple parts. The grip (where the
-- fist holds it) is the origin and items point forward along -Z.

local Parts = require(script.Parent.Parts)

local ItemModels = {}

type PieceSpec = {
	size: Vector3,
	at: CFrame,
	color: string,
	shape: Enum.PartType?,
	material: Enum.Material?,
	transparency: number?,
}

local Z = Parts.ALONG_Z

local function blockAt(size: Vector3, x: number, y: number, z: number, color: string, rot: CFrame?): PieceSpec
	return { size = size, at = CFrame.new(x, y, z) * (rot or CFrame.identity), color = color }
end

-- Cylinder lying along Z.
local function rod(
	length: number,
	diameter: number,
	z: number,
	color: string,
	x: number?,
	y: number?
): PieceSpec
	return {
		size = Vector3.new(length, diameter, diameter),
		at = CFrame.new(x or 0, y or 0, z) * Z,
		color = color,
		shape = Enum.PartType.Cylinder,
	}
end

local function ballAt(
	diameter: number,
	x: number,
	y: number,
	z: number,
	color: string,
	material: Enum.Material?
): PieceSpec
	return {
		size = Vector3.one * diameter,
		at = CFrame.new(x, y, z),
		color = color,
		shape = Enum.PartType.Ball,
		material = material,
	}
end

local DIAMOND = CFrame.Angles(0, math.rad(45), 0)

-- Flat disc lying face-up (reads as a circle from the top-down camera).
local function discAt(
	diameter: number,
	height: number,
	x: number,
	y: number,
	z: number,
	color: string
): PieceSpec
	return {
		size = Vector3.new(height, diameter, diameter),
		at = CFrame.new(x, y, z) * Parts.UPRIGHT,
		color = color,
		shape = Enum.PartType.Cylinder,
	}
end

-- Cylinder lying along X (sideways across the item).
local function crossRod(length: number, diameter: number, x: number, z: number, color: string): PieceSpec
	return {
		size = Vector3.new(length, diameter, diameter),
		at = CFrame.new(x, 0, z),
		color = color,
		shape = Enum.PartType.Cylinder,
	}
end

local function see(spec: PieceSpec, transparency: number): PieceSpec
	spec.transparency = transparency
	return spec
end

local function yaw(radians: number): CFrame
	return CFrame.Angles(0, radians, 0)
end

local DESIGNS: { [string]: { PieceSpec } } = {
	Stick = {
		rod(4, 0.35, -2, "8B5A2B"),
		blockAt(Vector3.new(0.5, 0.15, 0.2), 0.25, 0, -2.6, "8B5A2B", CFrame.Angles(0, 0.6, 0)),
	},
	Bat = {
		rod(1.6, 0.35, -0.8, "C8924F"),
		rod(0.5, 0.42, -0.2, "2E2E2E"),
		rod(2.6, 0.75, -2.9, "E0AE6A"),
		ballAt(0.75, 0, 0, -4.2, "E0AE6A"),
	},
	-- Held by the tail: a round, torpedo-shaped fish with a sail fin, side
	-- fins, big eyes and a long, sharp sword for a nose.
	Swordfish = {
		blockAt(Vector3.new(0.38, 0.14, 1.3), 0.4, 0, 0.45, "2B4F73", yaw(0.7)),
		blockAt(Vector3.new(0.38, 0.14, 1.3), -0.4, 0, 0.45, "2B4F73", yaw(-0.7)),
		rod(1.1, 0.36, -0.4, "3F73A3"),
		ballAt(0.62, 0, 0, -1.05, "3F73A3"),
		ballAt(0.88, 0, 0, -1.45, "3F73A3"),
		ballAt(1.1, 0, 0, -1.8, "4F86B5"),
		rod(2.6, 1.1, -3.1, "4F86B5"),
		ballAt(1.1, 0, 0, -4.4, "4F86B5"),
		rod(2.8, 0.8, -3.1, "C9DDEC", 0, -0.22),
		rod(3.0, 0.42, -3.05, "2A527A", 0, 0.38),
		ballAt(0.82, 0, 0, -4.95, "4F86B5"),
		ballAt(0.52, 0, 0, -5.35, "4F86B5"),
		blockAt(Vector3.new(0.12, 0.95, 1.1), 0, 0.75, -3.2, "2B4F73"),
		blockAt(Vector3.new(0.9, 0.1, 0.4), 0.72, -0.1, -4.0, "2B4F73", yaw(-0.5)),
		blockAt(Vector3.new(0.9, 0.1, 0.4), -0.72, -0.1, -4.0, "2B4F73", yaw(0.5)),
		ballAt(0.36, 0.34, 0.16, -4.95, "FFFFFF"),
		ballAt(0.36, -0.34, 0.16, -4.95, "FFFFFF"),
		ballAt(0.2, 0.45, 0.2, -5.0, "111111"),
		ballAt(0.2, -0.45, 0.2, -5.0, "111111"),
		rod(2.3, 0.26, -6.7, "3A4F63"),
		rod(0.7, 0.16, -8.1, "3A4F63"),
		blockAt(Vector3.new(0.13, 0.1, 0.13), 0, 0, -8.5, "3A4F63", DIAMOND),
	},
	Spear = {
		rod(7, 0.3, -3.5, "8B5A2B"),
		blockAt(Vector3.new(0.75, 0.3, 0.75), 0, 0, -7.25, "B8BEC6", DIAMOND),
		blockAt(Vector3.new(0.5, 0.32, 0.5), 0, 0, -7.9, "B8BEC6", DIAMOND),
	},
	AncientSpear = {
		rod(7.6, 0.34, -3.8, "C9A227"),
		rod(0.5, 0.45, -0.6, "7A1F1F"),
		blockAt(Vector3.new(0.85, 0.32, 0.85), 0, 0, -7.85, "F5D76E", DIAMOND),
		blockAt(Vector3.new(0.55, 0.34, 0.55), 0, 0, -8.55, "F5D76E", DIAMOND),
	},
	PotatoGun = {
		blockAt(Vector3.new(0.9, 0.9, 2.4), 0, 0, -1.2, "6B7F5A"),
		rod(1.6, 0.55, -3.1, "4E5B43"),
		ballAt(0.9, 0, 0.55, -0.9, "C9A66B"),
	},
	RarePotatoGun = {
		blockAt(Vector3.new(1.0, 1.0, 2.6), 0, 0, -1.3, "6A3FA0"),
		rod(1.8, 0.7, -3.4, "C9A227"),
		ballAt(1.1, 0, 0.6, -1.0, "C9A66B"),
	},
	Shotgun = {
		blockAt(Vector3.new(0.55, 0.5, 1.4), 0, 0, 0.3, "7A4A24"),
		blockAt(Vector3.new(0.75, 0.6, 1.4), 0, 0, -1.0, "33363B"),
		rod(3.0, 0.32, -3.2, "4A4E55", -0.17),
		rod(3.0, 0.32, -3.2, "4A4E55", 0.17),
	},
	Pill = {
		{
			size = Vector3.new(0.5, 0.5, 0.5),
			at = CFrame.new(0, 0, -0.55) * Z,
			color = "E5484D",
			shape = Enum.PartType.Cylinder,
		},
		{
			size = Vector3.new(0.5, 0.5, 0.5),
			at = CFrame.new(0, 0, -1.05) * Z,
			color = "F4F4F4",
			shape = Enum.PartType.Cylinder,
		},
		ballAt(0.5, 0, 0, -0.3, "E5484D"),
		ballAt(0.5, 0, 0, -1.3, "F4F4F4"),
	},
	Drumstick = {
		rod(1.0, 0.3, -0.3, "F4EFE1"),
		ballAt(0.45, 0.12, 0, 0.25, "F4EFE1"),
		ballAt(0.45, -0.12, 0, 0.25, "F4EFE1"),
		ballAt(1.35, 0, 0, -1.35, "A0582A"),
	},
	GoldenDrumstick = {
		rod(1.0, 0.3, -0.3, "F4EFE1"),
		ballAt(0.45, 0.12, 0, 0.25, "F4EFE1"),
		ballAt(0.45, -0.12, 0, 0.25, "F4EFE1"),
		ballAt(1.35, 0, 0, -1.35, "F5C542", Enum.Material.Neon),
	},
	RubberChicken = {
		rod(0.8, 0.25, -0.2, "F28C1C"), -- feet (the handle)
		ballAt(1.25, 0, 0, -2.5, "FFE14D"), -- body
		blockAt(Vector3.new(0.22, 0.16, 0.7), 0.6, 0.05, -2.5, "F7D23A", yaw(0.4)), -- wings
		blockAt(Vector3.new(0.22, 0.16, 0.7), -0.6, 0.05, -2.5, "F7D23A", yaw(-0.4)),
		rod(1.4, 0.35, -1.25, "FFE14D"), -- neck
		ballAt(0.65, 0, 0.05, -3.35, "FFE14D"), -- head
		blockAt(Vector3.new(0.26, 0.2, 0.45), 0, 0.05, -3.75, "F28C1C"), -- beak
		ballAt(0.32, 0, 0.35, -3.3, "E5484D"), -- comb
		ballAt(0.13, 0.22, 0.2, -3.45, "111111"), -- eyes
		ballAt(0.13, -0.22, 0.2, -3.45, "111111"),
	},
	PoolNoodle = {
		rod(6, 0.65, -3, "FF4FA3"),
		rod(0.06, 0.32, -6.02, "B8326F"), -- the hole in the end
	},
	Baguette = {
		rod(4.4, 0.75, -2.3, "D9A15C"),
		ballAt(0.75, 0, 0, -0.1, "D9A15C"),
		ballAt(0.75, 0, 0, -4.5, "D9A15C"),
		blockAt(Vector3.new(0.6, 0.08, 0.12), 0, 0.36, -1.1, "B5783A", yaw(0.6)),
		blockAt(Vector3.new(0.6, 0.08, 0.12), 0, 0.36, -2.0, "B5783A", yaw(0.6)),
		blockAt(Vector3.new(0.6, 0.08, 0.12), 0, 0.36, -2.9, "B5783A", yaw(0.6)),
		blockAt(Vector3.new(0.6, 0.08, 0.12), 0, 0.36, -3.8, "B5783A", yaw(0.6)),
	},
	FryingPan = {
		rod(1.6, 0.25, -0.8, "2B2B2B"),
		discAt(2.2, 0.2, 0, 0, -2.6, "333333"),
		discAt(1.9, 0.22, 0, 0.01, -2.6, "4A4A4A"),
		discAt(1.1, 0.24, 0.15, 0.02, -2.5, "FFFFFF"), -- a fried egg
		ballAt(0.45, 0.15, 0.12, -2.5, "FFC21A"),
	},
	GoldenPan = {
		rod(1.6, 0.25, -0.8, "B8860B"),
		discAt(2.3, 0.2, 0, 0, -2.65, "E0B235"),
		discAt(2.0, 0.22, 0, 0.01, -2.65, "F5C542"),
		discAt(1.1, 0.24, 0.15, 0.02, -2.55, "FFFFFF"),
		ballAt(0.45, 0.15, 0.12, -2.55, "F5C542", Enum.Material.Neon),
	},
	Crowbar = {
		rod(4, 0.3, -2, "C0392B"),
		blockAt(Vector3.new(0.3, 0.3, 0.9), 0.3, 0, -4.2, "C0392B", yaw(0.9)),
		blockAt(Vector3.new(0.32, 0.22, 0.3), 0.62, 0, -4.4, "3A3A3A"),
		rod(0.5, 0.32, -0.25, "3A3A3A"),
	},
	Plunger = {
		rod(3, 0.3, -1.5, "B88A55"),
		ballAt(1.4, 0, 0, -3.4, "C0392B"),
		{
			size = Vector3.new(0.12, 1.5, 1.5),
			at = CFrame.new(0, 0, -3.95) * Z,
			color = "8E2A20",
			shape = Enum.PartType.Cylinder,
		},
	},
	Lollipop = {
		rod(3, 0.22, -1.5, "F4F4F4"),
		discAt(2.4, 0.25, 0, 0, -3.9, "FF5FA2"),
		discAt(1.8, 0.27, 0, 0.01, -3.9, "FFFFFF"),
		discAt(1.2, 0.29, 0, 0.02, -3.9, "7FD3FF"),
		discAt(0.6, 0.31, 0, 0.03, -3.9, "FFE14D"),
	},
	Katana = {
		rod(1.3, 0.3, -0.3, "1C1C20"),
		discAt(0.7, 0.15, 0, 0, -1.0, "C9A227"),
		blockAt(Vector3.new(0.18, 0.12, 4.2), 0, 0, -3.15, "D9DEE4"),
		blockAt(Vector3.new(0.06, 0.13, 4.0), 0.07, 0, -3.15, "FFFFFF"),
	},
	InflatableHammer = {
		rod(3, 0.35, -1.5, "FFD93B"),
		crossRod(3, 1.8, 0, -3.6, "E5484D"),
		crossRod(0.4, 1.85, 1.3, -3.6, "FFD93B"),
		crossRod(0.4, 1.85, -1.3, -3.6, "FFD93B"),
	},
	Slingshot = {
		rod(1.2, 0.3, -0.6, "8B5A2B"),
		blockAt(Vector3.new(0.25, 0.25, 1.2), 0.35, 0, -1.6, "8B5A2B", yaw(0.4)),
		blockAt(Vector3.new(0.25, 0.25, 1.2), -0.35, 0, -1.6, "8B5A2B", yaw(-0.4)),
		blockAt(Vector3.new(1.0, 0.08, 0.08), 0, 0, -2.15, "E5484D"),
		ballAt(0.32, 0, 0.05, -2.0, "8C8C8C"),
	},
	WaterGun = {
		blockAt(Vector3.new(0.8, 0.7, 1.8), 0, 0, -0.9, "2ECC71"),
		see(ballAt(0.95, 0, 0.55, -0.6, "5DADE2"), 0.25),
		rod(1.2, 0.3, -2.4, "F39C12"),
		blockAt(Vector3.new(0.25, 0.4, 0.3), 0, -0.4, -0.2, "F39C12"),
	},
	SnowballLauncher = {
		rod(2.6, 0.8, -1.6, "AED6F1"),
		ballAt(0.8, 0, 0.5, -0.5, "FFFFFF"),
		{
			size = Vector3.new(0.1, 0.9, 0.9),
			at = CFrame.new(0, 0, -2.92) * Z,
			color = "FFFFFF",
			shape = Enum.PartType.Cylinder,
		},
	},
	BubbleGun = {
		blockAt(Vector3.new(0.7, 0.6, 1.4), 0, 0, -0.7, "9B59B6"),
		discAt(1.3, 0.15, 0, 0, -2.0, "E056FD"),
		see(discAt(0.95, 0.17, 0, 0.01, -2.0, "D6EAF8"), 0.4),
		see(ballAt(0.55, 0.45, 0.35, -2.8, "D6EAF8"), 0.5),
		see(ballAt(0.35, -0.3, 0.25, -3.3, "D6EAF8"), 0.5),
	},
	ConfettiCannon = {
		rod(2.6, 0.9, -1.6, "8E44AD"),
		rod(0.3, 0.95, -0.8, "F1C40F"),
		rod(0.3, 0.95, -1.6, "1ABC9C"),
		rod(0.3, 0.95, -2.4, "FF5FA2"),
		blockAt(Vector3.new(0.15, 0.05, 0.15), 0.3, 0.3, -3.1, "F1C40F", yaw(0.5)),
		blockAt(Vector3.new(0.15, 0.05, 0.15), -0.2, 0.35, -3.2, "1ABC9C", yaw(1.1)),
		blockAt(Vector3.new(0.15, 0.05, 0.15), 0.05, 0.4, -3.35, "FF5FA2", yaw(0.2)),
	},
	LeafBlower = {
		blockAt(Vector3.new(1.2, 1.0, 1.2), 0, 0, -0.2, "E67E22"),
		rod(3.2, 0.55, -2.4, "2B2B2B"),
		rod(0.5, 0.75, -4.1, "2B2B2B"),
		blockAt(Vector3.new(0.45, 0.05, 0.28), 0.25, 0.4, -4.6, "27AE60", yaw(0.7)),
	},
	DuckLauncher = {
		rod(3, 0.9, -1.8, "27AE60"),
		rod(0.3, 0.95, -0.6, "1E8449"),
		ballAt(0.7, 0, 0.3, -3.4, "FFD93B"),
		blockAt(Vector3.new(0.3, 0.15, 0.3), 0, 0.3, -3.85, "F28C1C"),
	},
	BananaPeel = {
		ballAt(0.45, 0, 0, -1.0, "8B5A2B"),
		blockAt(Vector3.new(0.45, 0.12, 1.0), 0, 0, -1.4, "F7DC6F"),
		blockAt(Vector3.new(0.45, 0.12, 1.0), 0.35, 0, -0.8, "F7DC6F", yaw(math.rad(120))),
		blockAt(Vector3.new(0.45, 0.12, 1.0), -0.35, 0, -0.8, "F7DC6F", yaw(math.rad(-120))),
	},
	EnergyDrink = {
		rod(1.2, 0.7, -0.8, "2ECC71"),
		rod(0.4, 0.72, -0.8, "1C1C20"),
		{
			size = Vector3.new(0.06, 0.66, 0.66),
			at = CFrame.new(0, 0, -1.43) * Z,
			color = "C0C6CC",
			shape = Enum.PartType.Cylinder,
		},
	},
}

-- Returns a Model whose PrimaryPart "Handle" (an invisible grip at the
-- origin) has every visible part welded to it. Parts are anchored; callers
-- unanchor them when the item goes into a hand.
function ItemModels.build(itemId: string): Model
	local model = Instance.new("Model")
	model.Name = itemId
	local handle = Parts.make({
		name = "Handle",
		size = Vector3.new(0.2, 0.2, 0.2),
		cframe = CFrame.identity,
		color = "FFFFFF",
		transparency = 1,
		canCollide = false,
		canQuery = false,
		parent = model,
	})
	model.PrimaryPart = handle
	for i, spec in DESIGNS[itemId] or DESIGNS.Stick do
		local part = Parts.make({
			name = "Piece" .. i,
			size = spec.size,
			cframe = spec.at,
			color = spec.color,
			shape = spec.shape,
			material = spec.material,
			transparency = spec.transparency,
			canCollide = false,
			canQuery = false,
			parent = model,
		})
		Parts.weldInPlace(handle, part)
	end
	return model
end

-- Bounding size of an item, for framing previews.
function ItemModels.extents(model: Model): Vector3
	local _, size = model:GetBoundingBox()
	return size
end

return ItemModels
