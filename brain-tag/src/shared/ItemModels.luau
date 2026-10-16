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
	Swordfish = {
		blockAt(Vector3.new(1.2, 0.6, 3.2), 0, 0, -1.6, "4E7FA6"),
		blockAt(Vector3.new(0.6, 0.62, 3.0), 0, 0, -1.6, "A9C8E0"),
		rod(3.6, 0.2, -5.0, "3B6585"),
		blockAt(Vector3.new(1.3, 0.2, 0.5), 0.35, 0, 0.35, "4E7FA6", CFrame.Angles(0, 0.6, 0)),
		blockAt(Vector3.new(1.3, 0.2, 0.5), -0.35, 0, 0.35, "4E7FA6", CFrame.Angles(0, -0.6, 0)),
		ballAt(0.25, 0.4, 0.3, -2.8, "111111"),
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
