--!strict
-- Footprints (studs) and weight classes for every furniture kind. At rotation
-- 0 a piece is `w` wide along X and `d` deep along Z, with its back toward -Z
-- (top of the screen) and its front facing +Z.

export type Weight = "Light" | "Medium" | "Heavy" | "Massive"

export type Spec = {
	w: number,
	d: number,
	h: number,
	weight: Weight,
	decor: boolean?, -- anchored, walk-over decoration (rugs)
}

local Specs: { [string]: Spec } = {
	Couch = { w = 10, d = 3.6, h = 3, weight = "Heavy" },
	Armchair = { w = 3.8, d = 3.8, h = 3, weight = "Medium" },
	Fridge = { w = 4, d = 4, h = 7, weight = "Heavy" },
	Stove = { w = 4, d = 3.6, h = 3.5, weight = "Medium" },
	Sink = { w = 4, d = 3, h = 3.5, weight = "Medium" },
	Toilet = { w = 2.6, d = 3.4, h = 2.6, weight = "Medium" },
	Bathtub = { w = 9, d = 4.6, h = 2.6, weight = "Heavy" },
	Bed = { w = 7, d = 10, h = 2.6, weight = "Heavy" },
	Table = { w = 8, d = 5, h = 3, weight = "Medium" },
	CoffeeTable = { w = 4, d = 3, h = 2.4, weight = "Medium" },
	Chair = { w = 2.4, d = 2.4, h = 2.6, weight = "Light" },
	Bookshelf = { w = 9, d = 2, h = 7, weight = "Heavy" },
	Box = { w = 2.6, d = 2.6, h = 2.6, weight = "Light" },
	Plant = { w = 2.2, d = 2.2, h = 3, weight = "Light" },
	Picture = { w = 4, d = 3, h = 2.2, weight = "Light" },
	Rug = { w = 12, d = 8, h = 0.06, weight = "Light", decor = true },
	-- Added after looking at the original: more, and heavier, things to move.
	Wardrobe = { w = 6, d = 2.6, h = 8, weight = "Massive" },
	Piano = { w = 8, d = 4.5, h = 4, weight = "Massive" },
	PoolTable = { w = 10, d = 6, h = 3, weight = "Massive" },
	Car = { w = 9, d = 16, h = 4, weight = "Massive" }, -- the garage supercar
	Dresser = { w = 5, d = 2.4, h = 4, weight = "Heavy" },
	Washer = { w = 3, d = 3, h = 3.5, weight = "Heavy" },
	Desk = { w = 6, d = 3, h = 3, weight = "Medium" },
	TVStand = { w = 6, d = 2, h = 2.4, weight = "Medium" },
	Crate = { w = 3.4, d = 3.4, h = 3.4, weight = "Medium" },
	Barrel = { w = 2.4, d = 2.4, h = 3, weight = "Medium" },
	Bench = { w = 6, d = 2, h = 2.4, weight = "Medium" },
	Lamp = { w = 1.8, d = 1.8, h = 5, weight = "Light" },
	Beanbag = { w = 3.4, d = 3.4, h = 2.4, weight = "Light" },
	TrashCan = { w = 2.2, d = 2.2, h = 3, weight = "Light" },
	Aquarium = { w = 6, d = 2.6, h = 4, weight = "Heavy" },
	Arcade = { w = 3.2, d = 3, h = 6.5, weight = "Heavy" },
	VendingMachine = { w = 4.5, d = 3, h = 7.5, weight = "Massive" },
	Treadmill = { w = 3, d = 7, h = 2.4, weight = "Heavy" },
	-- Haunted house.
	Tombstone = { w = 3.2, d = 1.4, h = 4, weight = "Heavy" },
	Coffin = { w = 3, d = 7, h = 2.2, weight = "Heavy" },
	Candelabra = { w = 1.6, d = 1.6, h = 5, weight = "Light" }, -- gives off light
	Cauldron = { w = 3.6, d = 3.6, h = 2.6, weight = "Medium" },
	Pumpkin = { w = 2.4, d = 2.4, h = 2, weight = "Light" },
	JackOLantern = { w = 2.6, d = 2.6, h = 2.2, weight = "Light" }, -- glows
	HayBale = { w = 5, d = 2.6, h = 2.6, weight = "Medium" },
	Scarecrow = { w = 3.4, d = 1.6, h = 6, weight = "Medium" },
	-- Christmas Town.
	ChristmasTree = { w = 5, d = 5, h = 9, weight = "Medium" },
	Present = { w = 2, d = 2, h = 2, weight = "Light" },
	Snowman = { w = 3.4, d = 3.4, h = 6, weight = "Heavy" },
}

local FurnitureSpecs = { specs = Specs }

-- Everything is drawn this much bigger than the numbers above (footprint
-- only), so pieces read clearly at the game's camera distance.
FurnitureSpecs.SIZE_SCALE = 1.15
-- Pieces that sit tight against walls (and the already-huge car and rugs)
-- keep their size.
local KEEP_SIZE: { [string]: boolean } = {
	Beanbag = true,
	Bed = true,
	Bookshelf = true,
	Car = true,
	Dresser = true,
	Lamp = true,
	Rug = true,
	Sink = true,
	Stove = true,
	TVStand = true,
}
for kind, spec in Specs do
	if not KEEP_SIZE[kind] then
		spec.w *= FurnitureSpecs.SIZE_SCALE
		spec.d *= FurnitureSpecs.SIZE_SCALE
	end
end

function FurnitureSpecs.get(kind: string): Spec
	local spec = Specs[kind]
	assert(spec, "Unknown furniture kind: " .. kind)
	return spec
end

-- Axis-aligned footprint size for a rotation in degrees (multiples of 90).
function FurnitureSpecs.footprint(kind: string, rot: number): (number, number)
	local spec = FurnitureSpecs.get(kind)
	local quarter = math.floor((rot % 360) / 90 + 0.5) % 2
	if quarter == 1 then
		return spec.d, spec.w
	end
	return spec.w, spec.d
end

return FurnitureSpecs
