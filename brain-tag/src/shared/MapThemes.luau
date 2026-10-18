--!strict
-- Color schemes and lighting for maps. A layout names its theme (Classic if
-- none); MapBuilder paints the ground, floors, walls and bushes with the
-- theme's colors and sets the lighting. On a dark theme your own client
-- hangs a lantern on you (DarknessController): you only see what's near you,
-- other people's name tags show only up close, and bots can't see far either.
-- Maps built in Studio pick one with the folder attribute Theme.

local MapLayout = require(script.Parent.MapLayout)

local MapThemes = {}

export type Lighting = {
	ambient: string,
	outdoor: string,
	brightness: number,
	clock: number,
	tint: string?, -- ColorCorrection tint
	saturation: number?,
	contrast: number?,
}

export type Lantern = { range: number, brightness: number, color: string }

export type Theme = {
	name: string,
	about: string,
	colors: { [string]: string }, -- overrides of MapLayout.COLORS
	lighting: Lighting,
	dark: boolean?,
	sight: number?, -- dark themes: how far you (and bots) can see others, studs
	lantern: Lantern?,
}

local THEMES: { [string]: Theme } = {
	Classic = {
		name = "Classic",
		about = "Sunny grass, gray walls with blue or orange trim.",
		colors = {},
		lighting = { ambient = "BEBEBE", outdoor = "BEBEBE", brightness = 1, clock = 12 },
	},
	Haunted = {
		name = "Haunted",
		about = "Night. Dead grass, purple-black walls, murky water. You only see near yourself.",
		colors = {
			Grass = "3D4A3A",
			Outside = "161B15",
			BoundaryBrick = "3E383E",
			BoundaryCap = "211D24",
			GrassTuft = "2B3628",
			Flower = "5E4A70",
			FlowerCenter = "9BD86A",
			Pebble = "50545A",
			Twig = "35281F",
			Dirt = "46372B",
			DirtSpeck = "352920",
			Sidewalk = "4E5258",
			SidewalkSpeck = "3F4247",
			Asphalt = "232327",
			CenterLine = "6E6236",
			EdgeLine = "7C7C7C",
			Wall = "211A26",
			OutlineBlue = "6A4C93",
			OutlineOrange = "8E3B46",
			Window = "51626E",
			Brick = "553C45",
			BrickMortar = "382930",
			Tile = "4A4C54",
			TileAlt = "3D3F46",
			Wood = "47322A",
			WoodLine = "30221B",
			Concrete = "474A50",
			ConcreteSpeck = "3B3D42",
			PoolWater = "2B5546",
			PoolRim = "575B60",
			BushGreen = "2C4430",
			BushOrange = "5E3427",
			ZombiePit = "3A0F14",
			Roof = "060509", -- pitch black: you can't see into rooms you're not in
			Door = "3A2A20",
		},
		lighting = {
			ambient = "2C2540",
			outdoor = "2C2540",
			brightness = 0,
			clock = 0,
			tint = "C9C0E8",
			saturation = -0.25,
			contrast = 0.1,
		},
		dark = true,
		sight = 34,
		lantern = { range = 30, brightness = 2.6, color = "FFD9A0" },
	},
	Winter = {
		name = "Winter",
		about = "Snow on the ground, icy blue trim, bright and cold. Christmas Town uses it.",
		colors = {
			Grass = "EAF2F6",
			Outside = "B9CAD4",
			BoundaryBrick = "9C5A45",
			BoundaryCap = "F4F8FA",
			GrassTuft = "CFDDE5",
			Flower = "D8423F",
			FlowerCenter = "F5F5F5",
			Pebble = "AEBBC3",
			Twig = "7A5B3E",
			Dirt = "C9D6DD",
			DirtSpeck = "B3C2CA",
			Sidewalk = "C3D0D7",
			SidewalkSpeck = "AEBDC5",
			Asphalt = "4F5560",
			Wall = "4B4F58",
			OutlineBlue = "8FC1DE",
			OutlineOrange = "C8463F",
			Window = "D7F0FA",
			PoolWater = "A9D8EE",
			PoolRim = "F2F7FA",
			BushGreen = "3E7A55",
			BushOrange = "B5473F",
		},
		lighting = { ambient = "C9D3E0", outdoor = "C9D3E0", brightness = 1.2, clock = 13, tint = "EEF5FF" },
	},
	Lab = {
		name = "Lab",
		about = "Clean white and steel with teal trim, like a laboratory.",
		colors = {
			Grass = "8DAF8F",
			Outside = "4B5D4C",
			BoundaryBrick = "7D8590",
			BoundaryCap = "4A5059",
			Wall = "3E4650",
			OutlineBlue = "2EC4B6",
			OutlineOrange = "F2A541",
			Window = "C8F3F0",
			Brick = "C9CFD6",
			BrickMortar = "AEB6BF",
			Tile = "E3E8ED",
			TileAlt = "D2D9E0",
			Wood = "9AA4AE",
			WoodLine = "86909A",
			Concrete = "B4BCC4",
			ConcreteSpeck = "A0A9B2",
			PoolWater = "7CF2C9",
			PoolRim = "DDE3E8",
		},
		lighting = { ambient = "D0D8DC", outdoor = "C2CCD0", brightness = 1, clock = 12, tint = "F0FFFD" },
	},
	Desert = {
		name = "Desert",
		about = "Sand and sandstone under a hot sun.",
		colors = {
			Grass = "E2C48E",
			Outside = "B39461",
			BoundaryBrick = "C08A55",
			BoundaryCap = "8A5E36",
			GrassTuft = "C9A86A",
			Flower = "D9774A",
			FlowerCenter = "F6D776",
			Pebble = "B89B70",
			Twig = "8A6A45",
			Dirt = "C9A46B",
			DirtSpeck = "B48F58",
			Wall = "7A4E33",
			OutlineBlue = "E0B07A",
			OutlineOrange = "C2603A",
			Brick = "D79D63",
			BushGreen = "8C9E52",
			BushOrange = "C98A3E",
		},
		lighting = { ambient = "E2D2BC", outdoor = "E2D2BC", brightness = 1.2, clock = 14, tint = "FFF4E2" },
	},
}

-- Two more nights, built on Haunted: a red moon over a village, and a
-- green, foggy swamp forest.
local function night(name: string, about: string, colors: { [string]: string }, lighting: Lighting): Theme
	local merged = table.clone(THEMES.Haunted.colors)
	for key, value in colors do
		merged[key] = value
	end
	return {
		name = name,
		about = about,
		colors = merged,
		lighting = lighting,
		dark = true,
		sight = 34,
		lantern = { range = 30, brightness = 2.6, color = "FFD9A0" },
	}
end

THEMES.BloodMoon = night(
	"BloodMoon",
	"Night under a red moon: dark stone, red trim. You only see near yourself.",
	{
		Grass = "3B3533",
		Outside = "1A1212",
		GrassTuft = "2E2726",
		Flower = "7A2230",
		FlowerCenter = "E0A040",
		Dirt = "4A3530",
		DirtSpeck = "3A2824",
		Sidewalk = "57504E",
		SidewalkSpeck = "48423F",
		Wall = "24181A",
		OutlineBlue = "8E2B32",
		OutlineOrange = "B5562A",
		Brick = "5C3434",
		BrickMortar = "3B2424",
		BushGreen = "3A2E22",
		BushOrange = "6E2A22",
	},
	{
		ambient = "40222A",
		outdoor = "40222A",
		brightness = 0,
		clock = 0,
		tint = "FFC9C4",
		saturation = -0.1,
		contrast = 0.12,
	}
)

THEMES.Swamp = night("Swamp", "A foggy green night in the woods. You only see near yourself.", {
	Grass = "2F3F2A",
	Outside = "121A10",
	GrassTuft = "24321F",
	Flower = "4F6A3A",
	FlowerCenter = "C8E070",
	Dirt = "3D3626",
	DirtSpeck = "2F2A1D",
	Wall = "1F2419",
	OutlineBlue = "4E7A3A",
	OutlineOrange = "7A5A2A",
	Wood = "3E3324",
	WoodLine = "2C2418",
	PoolWater = "33502C",
	PoolRim = "4A5040",
	BushGreen = "1F3A22",
	BushOrange = "4A4A1E",
}, {
	ambient = "22362A",
	outdoor = "22362A",
	brightness = 0,
	clock = 0,
	tint = "C8F0C8",
	saturation = -0.2,
	contrast = 0.1,
})

MapThemes.NAMES = { "Classic", "Haunted", "Winter", "Lab", "Desert", "BloodMoon", "Swamp" }

function MapThemes.get(name: string?): Theme
	return THEMES[name or "Classic"] or THEMES.Classic
end

function MapThemes.exists(name: string): boolean
	return THEMES[name] ~= nil
end

-- MapLayout.COLORS with the theme's colors laid over it.
function MapThemes.palette(name: string?): typeof(MapLayout.COLORS)
	local out = table.clone(MapLayout.COLORS) :: any
	for key, value in MapThemes.get(name).colors do
		out[key] = value
	end
	return out
end

return MapThemes
