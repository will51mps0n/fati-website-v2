-- Maps you build in Roblox Studio (README "Making your own maps").
--
-- Workspace.BrainTagMaps holds one folder per map, made of parts named for
-- what they are: Bounds, Wall, Door, Window, Floor, House, HumanSpawn,
-- ZombieSpawn, Start, ItemSpot, WizardSpot, Bush, Road... and any furniture
-- name (Couch, PoolTable...). Anything else you add (a statue, a tree, a
-- sign) is kept as scenery: solid scenery counts as wall for the bots and
-- never breaks. When the game starts it reads every map folder (see
-- MapMarks), adds it to the rotation and tucks the folder away. A map named
-- like a built-in one (Neighborhood, Mansion) replaces it.
--
-- Command Bar helpers (in Studio, while not playing):
--   local Maps = require(game.ServerScriptService.Server.MapStudio)
--   Maps.copy("Neighborhood")         -- edit a built-in map
--   Maps.copy("Mansion", "Castle")    -- start a new map from a built-in one
--   Maps.new("MyMap")                 -- a small starter map
--   Maps.new("Spooky", "Haunted")     -- ...in a theme (MapThemes: Classic,
--                                        Haunted, Winter, Lab, Desert)
--   Maps.resize("MyMap", 400, 300)    -- make the play area bigger (studs)
--   Maps.palette()                    -- one of every part, to copy from
--   Maps.check()                      -- what each map has, and any mistakes
--   Maps.unlock()                     -- unlock parts made by older versions
--
-- Map folder attributes: Title, Enabled, Theme (see MapThemes) and Roofs
-- (every room gets a pitch black roof hiding it, except on the screen of
-- whoever is inside, plus a shut-looking door in each doorway).

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local FurnitureBuilder = require(script.Parent.FurnitureBuilder)
local FurnitureSpecs = require(game:GetService("ReplicatedStorage").Shared.FurnitureSpecs)
local MapLayout = require(game:GetService("ReplicatedStorage").Shared.MapLayout)
local MapMarks = require(game:GetService("ReplicatedStorage").Shared.MapMarks)
local MapThemes = require(game:GetService("ReplicatedStorage").Shared.MapThemes)

type Mark = MapMarks.Mark
type Rect = MapLayout.Rect

local MapStudio = {}

local FOLDER = "BrainTagMaps"
local H = MapLayout.HEIGHTS
local WALL_H = MapLayout.WALL_HEIGHT

-- How each kind looks while you edit (top = height of its top above the
-- ground, which is the top of the Bounds part). `color` is a theme palette
-- name (MapLayout.COLORS) or a hex color.
type Look = {
	color: string,
	top: number,
	height: number,
	transparency: number?,
	disc: boolean?,
	label: boolean?,
	group: string,
}

local LOOKS: { [string]: Look } = {
	Bounds = { color = "Grass", top = 0, height = 1, group = "Ground" },
	Road = { color = "Asphalt", top = H.Asphalt, height = 0.1, group = "Ground" },
	Sidewalk = { color = "Sidewalk", top = H.Sidewalk, height = 0.1, group = "Ground" },
	CenterLine = { color = "CenterLine", top = H.RoadLine, height = 0.05, group = "Ground" },
	EdgeLine = { color = "EdgeLine", top = H.RoadLine, height = 0.05, group = "Ground" },
	Path = { color = "Dirt", top = H.Dirt, height = 0.05, group = "Ground" },
	Patio = { color = "Concrete", top = H.Patio, height = 0.05, group = "Ground" },
	Pool = { color = "PoolWater", top = H.PoolRim, height = 0.3, group = "Ground" },
	IslandWalk = { color = "Sidewalk", top = H.IslandWalk, height = 0.1, group = "Ground" },
	IslandGrass = { color = "Grass", top = H.IslandGrass, height = 0.05, group = "Ground" },
	House = {
		color = "OutlineBlue",
		top = 0.06,
		height = 0.05,
		transparency = 0.3,
		group = "Buildings",
	},
	Floor = { color = "Wood", top = H.Floor, height = 0.2, group = "Buildings" },
	Wall = { color = "Wall", top = WALL_H, height = WALL_H, group = "Buildings" },
	Door = {
		color = "39D353",
		top = WALL_H + 1,
		height = WALL_H + 1,
		transparency = 0.3,
		group = "Buildings",
	},
	Window = { color = "Window", top = WALL_H + 0.5, height = WALL_H + 0.5, group = "Buildings" },
	SecretWall = {
		color = "B05CFF",
		top = WALL_H + 1.2,
		height = WALL_H + 1.2,
		transparency = 0.35,
		group = "Buildings",
	},
	HumanSpawn = { color = "3B82F6", top = 0.9, height = 0.5, disc = true, label = true, group = "Spawns" },
	ZombieSpawn = { color = "E0303A", top = 0.9, height = 0.5, disc = true, label = true, group = "Spawns" },
	Start = { color = "FFFFFF", top = 0.9, height = 0.5, disc = true, label = true, group = "Spawns" },
	ItemSpot = { color = "F5C542", top = 0.9, height = 0.5, disc = true, label = true, group = "Spawns" },
	WizardSpot = { color = "9B59B6", top = 0.9, height = 0.5, disc = true, label = true, group = "Spawns" },
	Bush = { color = "BushGreen", top = 6, height = 6, disc = true, group = "Bushes" },
}

local FLOOR_LOOKS: { [string]: { color: string, material: Enum.Material } } = {
	Dirt = { color = "Dirt", material = Enum.Material.Ground },
	Brick = { color = "Brick", material = Enum.Material.Brick },
	Tile = { color = "Tile", material = Enum.Material.Slate },
	Wood = { color = "Wood", material = Enum.Material.WoodPlanks },
	Concrete = { color = "Concrete", material = Enum.Material.Concrete },
}

-- Reading parts ---------------------------------------------------------------------------

local function attr(instance: Instance, name: string): string?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "string" and value ~= "" then value else nil
end

-- Size of a box seen from above, along world X and Z (any rotation).
local function extents(cf: CFrame, size: Vector3): (number, number, number)
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local w = math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z
	local h = math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z
	local d = math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z
	return w, d, h
end

-- Degrees turned about the vertical (CFrame.Angles(0, a, 0) gives a).
local function yawOf(cf: CFrame): number
	local look = cf.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

local function floorOf(part: BasePart): string
	local m = part.Material
	if m == Enum.Material.Brick then
		return "Brick"
	elseif
		m == Enum.Material.Concrete
		or m == Enum.Material.Asphalt
		or m == Enum.Material.Cobblestone
		or m == Enum.Material.Pavement
	then
		return "Concrete"
	elseif m == Enum.Material.Ground or m == Enum.Material.Mud or m == Enum.Material.Sand then
		return "Dirt"
	elseif
		m == Enum.Material.Slate
		or m == Enum.Material.Marble
		or m == Enum.Material.Granite
		or m == Enum.Material.Basalt
	then
		return "Tile"
	end
	return "Wood"
end

local function orange(instance: Instance): boolean
	if instance:IsA("BasePart") then
		local c = instance.Color
		return c.R > c.G + 0.1
	end
	return false
end

-- Map coordinates start at the middle of the Bounds part's top.
local function originOf(bounds: BasePart): Vector3
	local _, _, h = extents(bounds.CFrame, bounds.Size)
	return Vector3.new(bounds.Position.X, bounds.Position.Y + h / 2, bounds.Position.Z)
end

local function markOf(child: Instance, kind: string, origin: Vector3): Mark
	local cf: CFrame, w: number, d: number
	if child:IsA("Model") then
		if MapMarks.isFurniture(kind) then
			cf, w, d = child:GetPivot(), 0, 0
		else
			local box, size = child:GetBoundingBox()
			cf = box
			w, d = extents(box, size)
		end
	else
		local part = child :: BasePart
		cf = part.CFrame
		w, d = extents(part.CFrame, part.Size)
	end
	local m: Mark = { kind = kind, x = cf.X - origin.X, z = cf.Z - origin.Z, w = w, d = d, rot = yawOf(cf) }
	m.id = attr(child, "Id")
	if kind == "Floor" then
		m.floor = attr(child, "Floor") or (if child:IsA("BasePart") then floorOf(child) else nil)
	elseif kind == "House" then
		m.outline = attr(child, "Outline") or (if orange(child) then "Orange" else "Blue")
	elseif kind == "Bush" then
		m.color = attr(child, "Color") or (if orange(child) then "Orange" else "Green")
	end
	return m
end

local function holdsKinds(instance: Instance): boolean
	for _, d in instance:GetDescendants() do
		if MapMarks.isKind(attr(d, "Kind") or d.Name) and (d:IsA("BasePart") or d:IsA("Model")) then
			return true
		end
	end
	return false
end

-- A map folder -> its layout (nil if it can't be played), the problems, and
-- its scenery (moved so the map's origin is at 0, 0, 0).
function MapStudio.read(folder: Instance): (MapLayout.Layout?, { string }, { string }, Model)
	local decor = Instance.new("Model")
	decor.Name = folder.Name .. " scenery"
	local bounds = folder:FindFirstChild("Bounds", true)
	if not (bounds and bounds:IsA("BasePart")) then
		return nil, { "No Bounds part: add a part named Bounds under the whole play area" }, {}, decor
	end
	local origin = originOf(bounds)
	local marks: { Mark } = {}
	local function visit(parent: Instance)
		for _, child in parent:GetChildren() do
			local kind = attr(child, "Kind") or child.Name
			local shape = child:IsA("BasePart") or child:IsA("Model")
			if shape and MapMarks.isKind(kind) then
				table.insert(marks, markOf(child, kind, origin))
			elseif child:IsA("Folder") or (child:IsA("Model") and holdsKinds(child)) then
				visit(child)
			elseif shape then
				local copy = child:Clone()
				if copy then
					for _, part in copy:GetDescendants() do
						if part:IsA("BasePart") then
							part.Anchored = true
						end
					end
					if copy:IsA("BasePart") then
						copy.Anchored = true
						copy.CFrame -= origin
					elseif copy:IsA("Model") then
						copy:PivotTo(copy:GetPivot() - origin)
					end
					(copy :: Instance).Parent = decor
				end
			end
		end
	end
	visit(folder)
	local layout, errors, warnings =
		MapMarks.toLayout(folder.Name, attr(folder, "Title") or folder.Name, marks)
	local theme = attr(folder, "Theme")
	if theme and MapThemes.exists(theme) then
		layout.theme = theme
	elseif theme then
		table.insert(
			warnings,
			"Unknown Theme " .. theme .. " (themes: " .. table.concat(MapThemes.NAMES, ", ") .. ")"
		)
	end
	layout.roofs = folder:GetAttribute("Roofs") == true
	return if #errors == 0 then layout else nil, errors, warnings, decor
end

-- Loading at game start -----------------------------------------------------------------------

local decorByMap: { [string]: Model } = {}

local function rootFolder(): Instance?
	return workspace:FindFirstChild(FOLDER) or ServerStorage:FindFirstChild(FOLDER)
end

local function isMap(folder: Instance): boolean
	return (folder:IsA("Folder") or folder:IsA("Model")) and string.sub(folder.Name, 1, 1) ~= "_"
end

-- Reads every map folder and adds the good ones to MapLayout. Call once,
-- before the first map is built. Returns the names loaded.
function MapStudio.loadAll(): { string }
	local root = rootFolder()
	if not root then
		return {}
	end
	root.Parent = ServerStorage -- the editable copies stay out of the game world
	local loaded = {}
	for _, folder in root:GetChildren() do
		if not isMap(folder) or folder:GetAttribute("Enabled") == false then
			continue
		end
		local ok, layout, errors, warnings, decor = pcall(MapStudio.read, folder)
		if not ok then
			warn(string.format("[Maps] %s couldn't be read: %s", folder.Name, tostring(layout)))
			continue
		end
		for _, text in warnings do
			warn(string.format("[Maps] %s: %s", folder.Name, text))
		end
		if layout then
			MapLayout.register(layout)
			if #decor:GetChildren() > 0 then
				decorByMap[layout.name] = decor
			end
			table.insert(loaded, layout.name)
			print(string.format("[Maps] loaded your map %s", folder.Name))
		else
			for _, text in errors do
				warn(string.format("[Maps] %s can't be played: %s", folder.Name, text))
			end
		end
	end
	return loaded
end

-- The scenery of a map built in Studio (for MapBuilder).
function MapStudio.decor(name: string): Instance?
	return decorByMap[name]
end

-- Making parts (Command Bar helpers) ---------------------------------------------------------

local function editing(): boolean
	if RunService:IsRunning() then
		warn("[Maps] Stop the game first: map helpers work while editing.")
		return false
	end
	return true
end

local function label(part: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromScale(12, 3) -- studs
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	gui.LightInfluence = 0
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = text
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextStrokeTransparency = 0
	textLabel.Parent = gui
	gui.Parent = part
end

local function groupFolder(map: Instance, name: string): Instance
	local found = map:FindFirstChild(name)
	if found then
		return found
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = map
	return folder
end

local function makeMark(m: Mark, origin: Vector3, parent: Instance, palette: { [string]: string }): Instance
	if MapMarks.isFurniture(m.kind) then
		local model = FurnitureBuilder.preview(
			{ kind = m.kind, x = origin.X + m.x, z = origin.Z + m.z, rot = m.rot, house = "" },
			parent
		)
		model:PivotTo(model:GetPivot() + Vector3.new(0, origin.Y, 0))
		return model
	end
	local look = LOOKS[m.kind]
	local part = Instance.new("Part")
	part.Name = m.kind
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	local color = palette[look.color] or look.color
	if m.kind == "Floor" then
		local floor = FLOOR_LOOKS[m.floor or "Wood"] or FLOOR_LOOKS.Wood
		color = palette[floor.color] or floor.color
		part.Material = floor.material
		part:SetAttribute("Floor", m.floor or "Wood")
	elseif m.kind == "House" then
		color = if m.outline == "Orange" then palette.OutlineOrange else palette.OutlineBlue
		part:SetAttribute("Outline", m.outline or "Blue")
	elseif m.kind == "Bush" then
		color = if m.color == "Cobweb"
			then "C3C9CF"
			elseif m.color == "Orange" then palette.BushOrange
			else palette.BushGreen
		part:SetAttribute("Color", m.color or "Green")
	end
	if m.id then
		part:SetAttribute("Id", m.id)
	end
	part.Color = Color3.fromHex(color)
	part.Transparency = look.transparency or 0
	local center = Vector3.new(origin.X + m.x, origin.Y + look.top - look.height / 2, origin.Z + m.z)
	if look.disc then
		local diameter = math.max(m.w, m.d, 1)
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(look.height, diameter, diameter)
		part.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	else
		part.Size = Vector3.new(math.max(m.w, 0.2), look.height, math.max(m.d, 0.2))
		part.CFrame = CFrame.new(center)
	end
	if look.label then
		label(part, m.kind)
	end
	part.Parent = parent
	return part
end

local function ensureRoot(): Instance
	local root = rootFolder()
	if root then
		if root.Parent ~= workspace then
			root.Parent = workspace
		end
		return root
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	folder.Parent = workspace
	return folder
end

-- Where a new map (or the palette) goes: just right of everything there.
local function freeOrigin(root: Instance, bounds: Rect): Vector3
	local right = -math.huge
	for _, child in root:GetChildren() do
		local b = child:FindFirstChild("Bounds", true)
		if b and b:IsA("BasePart") then
			local w = extents(b.CFrame, b.Size)
			right = math.max(right, b.Position.X + w / 2)
		elseif child.Name == "_Palette" and child:IsA("Folder") then
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					right = math.max(right, d.Position.X + d.Size.Magnitude / 2)
				end
			end
		end
	end
	-- Lifted a stud so it never flickers against a Baseplate.
	if right == -math.huge then
		return Vector3.new(0, 1, 0)
	end
	return Vector3.new(right + 60 - bounds.x1, 1, 0)
end

local function show(folder: Instance, origin: Vector3, bounds: Rect)
	pcall(function()
		game:GetService("Selection"):Set({ folder })
	end)
	local camera = workspace.CurrentCamera
	if camera then
		local center = origin + Vector3.new((bounds.x1 + bounds.x2) / 2, 0, (bounds.z1 + bounds.z2) / 2)
		local size = math.max(bounds.x2 - bounds.x1, bounds.z2 - bounds.z1)
		camera.CFrame = CFrame.lookAt(center + Vector3.new(0, size * 0.9, size * 0.45), center)
		camera.Focus = CFrame.new(center)
	end
	pcall(function()
		game:GetService("ChangeHistoryService"):SetWaypoint("Brain Tag map")
	end)
end

local function place(name: string, title: string, marks: { Mark }, theme: string, roofs: boolean): Instance?
	if not editing() then
		return nil
	end
	local root = ensureRoot()
	if root:FindFirstChild(name) then
		warn(
			string.format(
				"[Maps] BrainTagMaps already has %s. Pick another name, or delete that folder first.",
				name
			)
		)
		return nil
	end
	local bounds: Rect = { x1 = -100, z1 = -100, x2 = 100, z2 = 100 }
	for _, m in marks do
		if m.kind == "Bounds" then
			bounds = { x1 = m.x - m.w / 2, z1 = m.z - m.d / 2, x2 = m.x + m.w / 2, z2 = m.z + m.d / 2 }
		end
	end
	local origin = freeOrigin(root, bounds)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder:SetAttribute("Title", title)
	folder:SetAttribute("Enabled", true)
	folder:SetAttribute("Theme", theme)
	folder:SetAttribute("Roofs", roofs)
	local palette = MapThemes.palette(theme) :: any
	for _, m in marks do
		local group = if MapMarks.isFurniture(m.kind) then "Furniture" else LOOKS[m.kind].group
		makeMark(m, origin, groupFolder(folder, group), palette)
	end
	folder.Parent = root
	show(folder, origin, bounds)
	print(
		string.format(
			"[Maps] Made %s in Workspace.BrainTagMaps. Edit it, then press Play: it plays first.",
			name
		)
	)
	return folder
end

-- A built-in map as parts. Keep its name to change that map, or give a
-- new name to start a new map from it.
function MapStudio.copy(name: string, newName: string?): Instance?
	local layout = MapLayout.get(name)
	if not layout then
		warn(
			"[Maps] No map called "
				.. tostring(name)
				.. ". Built-in maps: "
				.. table.concat(MapLayout.names, ", ")
		)
		return nil
	end
	local title = if newName then newName else layout.title
	return place(newName or name, title, MapMarks.fromLayout(layout), layout.theme, layout.roofs)
end

-- A small map to build on, in a theme (Classic if none).
function MapStudio.new(name: string?, theme: string?): Instance?
	local mapName = name or "MyMap"
	local themeName = theme or "Classic"
	if not MapThemes.exists(themeName) then
		warn("[Maps] No theme called " .. themeName .. ". Themes: " .. table.concat(MapThemes.NAMES, ", "))
		return nil
	end
	-- Dark maps get roofs (rooms stay pitch black until you walk in).
	local dark = MapThemes.get(themeName).dark == true
	return place(mapName, mapName, MapMarks.starter(), themeName, dark)
end

local function mapFolder(name: string): Instance?
	local root = rootFolder()
	local folder = root and root:FindFirstChild(name)
	if not folder then
		warn("[Maps] No map called " .. name .. " in Workspace.BrainTagMaps")
	end
	return folder
end

-- Makes a map's play area (its Bounds part) this many studs wide (X) and
-- deep (Z), keeping its middle where it is.
function MapStudio.resize(name: string, width: number, depth: number)
	if not editing() then
		return
	end
	local folder = mapFolder(name)
	local bounds = folder and folder:FindFirstChild("Bounds", true)
	if not (bounds and bounds:IsA("BasePart")) then
		warn("[Maps] " .. name .. " has no Bounds part")
		return
	end
	bounds.Locked = false
	bounds.Size = Vector3.new(math.max(40, width), bounds.Size.Y, math.max(40, depth))
	pcall(function()
		game:GetService("ChangeHistoryService"):SetWaypoint("Resize map")
	end)
	print(
		string.format(
			"[Maps] %s is now %d x %d studs.",
			name,
			math.round(bounds.Size.X),
			math.round(bounds.Size.Z)
		)
	)
end

-- Unlocks every part in your maps (older versions locked the ground and
-- house plates, so Studio's tools couldn't move or scale them).
function MapStudio.unlock()
	local root = rootFolder()
	if not root then
		return
	end
	local count = 0
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") and part.Locked then
			part.Locked = false
			count += 1
		end
	end
	print(string.format("[Maps] Unlocked %d parts.", count))
end

-- One of every part (and every furniture piece) beside your maps, to copy
-- (Ctrl+D) into a map folder.
function MapStudio.palette(): Instance?
	if not editing() then
		return nil
	end
	local root = ensureRoot()
	local old = root:FindFirstChild("_Palette")
	if old then
		old:Destroy()
	end
	local samples: { Mark } = {}
	local function sample(kind: string, w: number, d: number, extra: { [string]: string }?): Mark
		local m: Mark = { kind = kind, x = 0, z = 0, w = w, d = d, rot = 0 }
		if extra then
			m.floor, m.color, m.outline = extra.floor, extra.color, extra.outline
		end
		table.insert(samples, m)
		return m
	end
	sample("Wall", 20, 3)
	sample("Door", 8, 3)
	sample("Window", 10, 3)
	sample("SecretWall", 8, 3)
	for _, floor in MapMarks.FLOORS do
		sample("Floor", 16, 16, { floor = floor })
	end
	sample("House", 16, 16, { outline = "Blue" })
	sample("House", 16, 16, { outline = "Orange" })
	for _, kind in { "HumanSpawn", "ZombieSpawn", "Start", "ItemSpot", "WizardSpot" } do
		sample(kind, 4, 4)
	end
	sample("Bush", 9, 9, { color = "Green" })
	sample("Bush", 9, 9, { color = "Orange" })
	sample("Bush", 6, 6, { color = "Cobweb" })
	sample("Road", 16, 16)
	sample("Sidewalk", 16, 8)
	sample("CenterLine", 16, 1)
	sample("EdgeLine", 16, 1)
	sample("Path", 16, 6)
	sample("Patio", 14, 14)
	sample("Pool", 16, 10)
	sample("IslandWalk", 16, 12)
	sample("IslandGrass", 12, 8)
	local kinds = {}
	for kind in FurnitureSpecs.specs do
		table.insert(kinds, kind)
	end
	table.sort(kinds)
	for _, kind in kinds do
		local spec = FurnitureSpecs.get(kind)
		sample(kind, spec.w, spec.d)
	end

	-- A grid of 26-stud cells, 8 across.
	local cell, across = 26, 8
	local rows = math.ceil(#samples / across)
	local bounds: Rect = { x1 = 0, z1 = 0, x2 = cell * across, z2 = cell * rows }
	local origin = freeOrigin(root, bounds)
	local folder = Instance.new("Folder")
	folder.Name = "_Palette"
	for i, m in samples do
		local col, row = (i - 1) % across, (i - 1) // across
		m.x, m.z = (col + 0.5) * cell, (row + 0.5) * cell
		local made = makeMark(m, origin, folder, MapThemes.palette("Classic") :: any)
		local part = if made:IsA("Model") then made.PrimaryPart else made :: BasePart
		if part and not part:FindFirstChild("Label") then
			label(part, m.kind)
		end
	end
	folder.Parent = root
	show(folder, origin, bounds)
	print("[Maps] Palette ready: select a piece, Ctrl+D to copy it, then drag it into your map's folder.")
	return folder
end

-- What each map folder (or just `name`) has, and anything wrong with it.
function MapStudio.check(name: string?)
	local root = rootFolder()
	if not root then
		print('[Maps] No maps yet. Try: require(game.ServerScriptService.Server.MapStudio).new("MyMap")')
		return
	end
	for _, folder in root:GetChildren() do
		if not isMap(folder) or (name and folder.Name ~= name) then
			continue
		end
		local layout, errors, warnings = MapStudio.read(folder)
		if layout then
			local doors, windows = 0, 0
			for _, w in layout.walls do
				doors += #w.gaps
				windows += #w.windows
			end
			print(
				string.format(
					"[Maps] %s%s (theme %s): %d walls, %d doors, %d windows, %d rooms, %d furniture, %d human spawns, %d zombie spawns, %d item spots, %d bushes",
					folder.Name,
					if folder:GetAttribute("Enabled") == false then " (turned off)" else "",
					layout.theme,
					#layout.walls,
					doors,
					windows,
					#layout.rooms,
					#layout.furniture,
					#layout.humanSpawns,
					#layout.zombieSpawns,
					#layout.itemSpots,
					#layout.bushes
				)
			)
		end
		for _, text in errors do
			warn(string.format("[Maps] %s can't be played: %s", folder.Name, text))
		end
		for _, text in warnings do
			warn(string.format("[Maps] %s: %s", folder.Name, text))
		end
		if layout and #warnings == 0 then
			print(string.format("[Maps] %s is ready to play.", folder.Name))
		end
	end
end

return MapStudio
