-- Builds the neighborhood from MapLayout: grass with little details, dirt
-- paths, the road, house floors with patterns, outlined walls split into
-- breakable segments, windows, bushes and an invisible boundary.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Parts = require(ReplicatedStorage.Shared.Parts)

local MapBuilder = {}

local COLORS = MapLayout.COLORS
local H = MapLayout.HEIGHTS
local WALL_HEIGHT = MapLayout.WALL_HEIGHT

type Rect = MapLayout.Rect

local mapFolder: Folder
local wallsFolder: Folder
local brokenSegments: { Model } = {}

local function sub(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Thin detail lying on a surface whose top is `surfaceY`.
local function detail(
	name: string,
	x: number,
	z: number,
	sx: number,
	sz: number,
	surfaceY: number,
	color: string,
	parent: Instance,
	yaw: number?
): Part
	local part = Parts.make({
		name = name,
		size = Vector3.new(sx, 0.04, sz),
		cframe = CFrame.new(x, surfaceY + 0.015, z) * CFrame.Angles(0, yaw or 0, 0),
		color = color,
		canCollide = false,
		canQuery = false,
		parent = parent,
	})
	return part
end

local function flatDisc(
	name: string,
	x: number,
	z: number,
	diameter: number,
	surfaceY: number,
	color: string,
	parent: Instance
)
	local part = Parts.disc(name, Vector3.new(x, surfaceY + 0.02, z), diameter, 0.05, color, parent)
	part.CanCollide = false
	part.CanQuery = false
	return part
end

local function slab(name: string, r: Rect, topY: number, color: string, parent: Instance): Part
	return Parts.slab(name, r.x1, r.z1, r.x2, r.z2, topY, 0.4, color, parent)
end

-- Ground, decorations, paths -----------------------------------------------------

local function buildGround(parent: Instance)
	-- Much bigger than the playable area so the camera never sees past it.
	local ground = Parts.slab("Grass", -360, -360, 360, 360, H.Grass, 4, COLORS.Grass, parent)
	ground.Name = "Ground"

	local decor = sub("GrassDetails", parent)
	local rng = Random.new(1337)
	local blocked = MapLayout.noDecorRects()
	local bounds = MapLayout.BOUNDS
	local function isFree(x: number, z: number): boolean
		for _, r in blocked do
			if MapLayout.inRect(r, x, z, 1) then
				return false
			end
		end
		return true
	end

	local placed = 0
	local tries = 0
	while placed < 460 and tries < 6000 do
		tries += 1
		local x = rng:NextNumber(bounds.x1 + 3, bounds.x2 - 3)
		local z = rng:NextNumber(bounds.z1 + 3, bounds.z2 - 3)
		if isFree(x, z) then
			placed += 1
			local roll = rng:NextNumber()
			if roll < 0.5 then
				-- Tuft: three dark blades fanned out.
				for _, angle in { -0.5, 0, 0.5 } do
					detail("Tuft", x + angle * 0.5, z, 0.25, 1.1, H.Grass, COLORS.GrassTuft, decor, angle)
				end
			elseif roll < 0.7 then
				flatDisc("Flower", x, z, 1.0, H.Grass, COLORS.Flower, decor)
				flatDisc("FlowerCenter", x, z, 0.35, H.Grass + 0.03, COLORS.FlowerCenter, decor)
			elseif roll < 0.88 then
				flatDisc("Pebble", x, z, rng:NextNumber(0.5, 0.9), H.Grass, COLORS.Pebble, decor)
				if rng:NextNumber() < 0.5 then
					flatDisc(
						"Pebble",
						x + 0.8,
						z + 0.3,
						rng:NextNumber(0.35, 0.6),
						H.Grass,
						COLORS.Pebble,
						decor
					)
				end
			else
				local yaw = rng:NextNumber(0, math.pi)
				detail("Twig", x, z, 0.16, 1.5, H.Grass, COLORS.Twig, decor, yaw)
				detail("Twig", x + 0.3, z + 0.2, 0.12, 0.6, H.Grass, COLORS.Twig, decor, yaw + 0.8)
			end
		end
	end

	local paths = sub("Paths", parent)
	for _, r in MapLayout.paths do
		slab("Dirt", r, H.Dirt, COLORS.Dirt, paths)
		local count = math.floor((r.x2 - r.x1) * (r.z2 - r.z1) / 14)
		for _ = 1, count do
			flatDisc(
				"Speck",
				rng:NextNumber(r.x1 + 0.4, r.x2 - 0.4),
				rng:NextNumber(r.z1 + 0.4, r.z2 - 0.4),
				rng:NextNumber(0.25, 0.5),
				H.Dirt,
				COLORS.DirtSpeck,
				paths
			)
		end
	end
end

local function buildRoad(parent: Instance)
	local road = MapLayout.road
	for _, r in road.sidewalks do
		slab("Sidewalk", r, H.Sidewalk, COLORS.Sidewalk, parent)
	end
	for _, r in road.asphalt do
		slab("Asphalt", r, H.Asphalt, COLORS.Asphalt, parent)
	end
	for _, r in road.centerLines do
		slab("CenterLine", r, H.RoadLine, COLORS.CenterLine, parent)
	end
	for _, r in road.edgeLines do
		slab("EdgeLine", r, H.RoadLine, COLORS.EdgeLine, parent)
	end
	slab("IslandWalk", road.islandWalk, H.IslandWalk, COLORS.Sidewalk, parent)
	slab("IslandGrass", road.islandGrass, H.IslandGrass, COLORS.Grass, parent)

	for _, spawn in MapLayout.zombieSpawns do
		flatDisc("ZombiePit", spawn.x, spawn.z, 11, H.RoadLine, COLORS.ZombiePit, parent)
		flatDisc("ZombiePitInner", spawn.x, spawn.z, 7, H.RoadLine + 0.03, "4A1C1C", parent)
	end
end

-- Floors ---------------------------------------------------------------------------

local function brickFloor(r: Rect, parent: Instance)
	slab("Brick", r, H.Floor, COLORS.Brick, parent)
	local row = 0
	local z = r.z1
	while z < r.z2 - 0.5 do
		local nextZ = math.min(z + 4, r.z2)
		if nextZ < r.z2 then
			detail("Mortar", (r.x1 + r.x2) / 2, nextZ, r.x2 - r.x1, 0.25, H.Floor, COLORS.BrickMortar, parent)
		end
		local x = r.x1 + (if row % 2 == 0 then 8 else 4)
		while x < r.x2 - 0.5 do
			detail("Joint", x, (z + nextZ) / 2, 0.25, nextZ - z, H.Floor, COLORS.BrickMortar, parent)
			x += 8
		end
		z = nextZ
		row += 1
	end
end

local function tileFloor(r: Rect, parent: Instance)
	slab("Tile", r, H.Floor, COLORS.Tile, parent)
	local size = 4
	local i = 0
	local x = r.x1
	while x < r.x2 - 0.01 do
		local x2 = math.min(x + size, r.x2)
		local j = 0
		local z = r.z1
		while z < r.z2 - 0.01 do
			local z2 = math.min(z + size, r.z2)
			if (i + j) % 2 == 1 then
				detail("TileAlt", (x + x2) / 2, (z + z2) / 2, x2 - x, z2 - z, H.Floor, COLORS.TileAlt, parent)
			end
			z = z2
			j += 1
		end
		x = x2
		i += 1
	end
end

local function woodFloor(r: Rect, parent: Instance, rng: Random)
	slab("Wood", r, H.Floor, COLORS.Wood, parent)
	local z = r.z1 + 2.5
	while z < r.z2 - 0.5 do
		detail("Plank", (r.x1 + r.x2) / 2, z, r.x2 - r.x1, 0.18, H.Floor, COLORS.WoodLine, parent)
		local x = r.x1 + rng:NextNumber(3, 12)
		while x < r.x2 - 2 do
			detail("PlankEnd", x, z - 1.25, 0.18, 2.5, H.Floor, COLORS.WoodLine, parent)
			x += rng:NextNumber(11, 17)
		end
		z += 2.5
	end
end

local function buildFloors(parent: Instance)
	local rng = Random.new(7)
	for _, room in MapLayout.rooms do
		local folder = sub(room.house .. " " .. room.name, parent)
		if room.floor == "Brick" then
			brickFloor(room.rect, folder)
		elseif room.floor == "Tile" then
			tileFloor(room.rect, folder)
		else
			woodFloor(room.rect, folder, rng)
		end
	end
end

-- Walls ----------------------------------------------------------------------------

local function outlineColor(houseId: string): string
	for _, house in MapLayout.houses do
		if house.id == houseId then
			return if house.outline == "Orange" then COLORS.OutlineOrange else COLORS.OutlineBlue
		end
	end
	return COLORS.OutlineBlue
end

local function buildWalls(parent: Instance)
	for i, piece in MapLayout.allWallPieces() do
		local r = piece.rect
		local sx, sz = r.x2 - r.x1, r.z2 - r.z1
		local cx, cz = (r.x1 + r.x2) / 2, (r.z1 + r.z2) / 2
		local segment = Instance.new("Model")
		segment.Name = "WallSegment" .. i

		local wall = Parts.make({
			name = "Wall",
			size = Vector3.new(sx, WALL_HEIGHT, sz),
			cframe = CFrame.new(cx, WALL_HEIGHT / 2, cz),
			color = COLORS.Wall,
			parent = segment,
		})
		-- A slightly bigger, slightly lower slab: from above only its edge shows,
		-- which draws a colored outline around the whole wall shape.
		Parts.make({
			name = "Outline",
			size = Vector3.new(sx + 1, WALL_HEIGHT - 0.1, sz + 1),
			cframe = CFrame.new(cx, (WALL_HEIGHT - 0.1) / 2, cz),
			color = outlineColor(piece.house),
			canCollide = false, -- keeps doorways at their designed width
			canQuery = false,
			parent = segment,
		})
		if piece.window then
			Parts.make({
				name = "Window",
				size = if piece.horizontal then Vector3.new(sx, 0.1, 1.2) else Vector3.new(1.2, 0.1, sz),
				cframe = CFrame.new(cx, WALL_HEIGHT + 0.05, cz),
				color = COLORS.Window,
				canCollide = false,
				canQuery = false,
				parent = segment,
			})
		end
		segment.PrimaryPart = wall
		segment:SetAttribute("House", piece.house)
		CollectionService:AddTag(segment, "Breakable")
		segment.Parent = parent
	end
end

-- Bushes and boundary -------------------------------------------------------------

local function buildBushes(parent: Instance)
	for _, bush in MapLayout.bushes do
		local base = if bush.color == "Orange" then COLORS.BushOrange else COLORS.BushGreen
		local light = if bush.color == "Orange" then "F2AC62" else "5CBF67"
		local model = Instance.new("Model")
		model.Name = "Bush"
		local blobs = {
			{ 0, 0, bush.r * 2 },
			{ math.cos(0.7) * bush.r * 0.6, math.sin(0.7) * bush.r * 0.6, bush.r * 1.4 },
			{ math.cos(3.5) * bush.r * 0.6, math.sin(3.5) * bush.r * 0.6, bush.r * 1.3 },
		}
		for _, blob in blobs do
			Parts.disc("Leaves", Vector3.new(bush.x + blob[1], 2, bush.z + blob[2]), blob[3], 4, base, model)
			local highlight = Parts.disc(
				"Highlight",
				Vector3.new(bush.x + blob[1] - 0.2, 4.03, bush.z + blob[2] - 0.2),
				blob[3] * 0.6,
				0.06,
				light,
				model
			)
			highlight.CanCollide = false
			highlight.CanQuery = false
		end
		model.Parent = parent
	end
end

local function buildBoundary(parent: Instance)
	local b = MapLayout.BOUNDS
	local height, t = 40, 4
	local function wall(cx: number, cz: number, sx: number, sz: number)
		Parts.make({
			name = "Boundary",
			size = Vector3.new(sx, height, sz),
			cframe = CFrame.new(cx, height / 2, cz),
			color = "000000",
			transparency = 1,
			canQuery = false,
			parent = parent,
		})
	end
	local w, d = b.x2 - b.x1, b.z2 - b.z1
	wall((b.x1 + b.x2) / 2, b.z1 - t / 2, w + t * 2, t)
	wall((b.x1 + b.x2) / 2, b.z2 + t / 2, w + t * 2, t)
	wall(b.x1 - t / 2, (b.z1 + b.z2) / 2, t, d)
	wall(b.x2 + t / 2, (b.z1 + b.z2) / 2, t, d)
end

-- Public ----------------------------------------------------------------------------

function MapBuilder.build()
	mapFolder = workspace:WaitForChild("Map") :: Folder
	mapFolder:ClearAllChildren()
	buildGround(sub("Ground", mapFolder))
	buildRoad(sub("Road", mapFolder))
	buildFloors(sub("Floors", mapFolder))
	wallsFolder = sub("Walls", mapFolder)
	buildWalls(wallsFolder)
	buildBushes(sub("Bushes", mapFolder))
	buildBoundary(sub("Boundary", mapFolder))
end

function MapBuilder.wallsFolder(): Folder
	return wallsFolder
end

-- Shotgun hit: hide a wall segment until the next round.
function MapBuilder.breakSegment(segment: Model): boolean
	if segment:GetAttribute("Broken") or not CollectionService:HasTag(segment, "Breakable") then
		return false
	end
	segment:SetAttribute("Broken", true)
	for _, part in segment:GetChildren() do
		if part:IsA("BasePart") then
			part:SetAttribute("WasCollide", part.CanCollide)
			part:SetAttribute("WasQuery", part.CanQuery)
			part.Transparency = 1
			part.CanCollide = false
			part.CanQuery = false
		end
	end
	table.insert(brokenSegments, segment)
	return true
end

function MapBuilder.restoreWalls()
	for _, segment in brokenSegments do
		segment:SetAttribute("Broken", nil)
		for _, part in segment:GetChildren() do
			if part:IsA("BasePart") then
				part.Transparency = 0
				part.CanCollide = part:GetAttribute("WasCollide") ~= false
				part.CanQuery = part:GetAttribute("WasQuery") ~= false
			end
		end
	end
	table.clear(brokenSegments)
end

-- Finds the breakable segment a part belongs to.
function MapBuilder.segmentOf(part: Instance): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	if model and CollectionService:HasTag(model, "Breakable") then
		return model
	end
	return nil
end

return MapBuilder
