--!strict
-- Footprints (studs) and weight classes for every furniture kind. At rotation
-- 0 a piece is `w` wide along X and `d` deep along Z, with its back toward -Z
-- (top of the screen) and its front facing +Z.

export type Weight = "Light" | "Medium" | "Heavy"

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
}

local FurnitureSpecs = { specs = Specs }

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
