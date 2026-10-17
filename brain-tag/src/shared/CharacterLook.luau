-- The top-down person from the original: a rounded body in the shirt color
-- with a dark outline, a round head (hair on top) with a skin-colored face
-- crescent at the front, and a soft shadow. Zombies add two arms reaching
-- forward. Used on live characters (server) and skin previews (client).
-- Front is -Z of the root, like every Roblox character.

local Config = require(script.Parent.Config)
local Parts = require(script.Parent.Parts)
local Skins = require(script.Parent.Skins)

local C = Config.CHARACTER

local CharacterLook = {}

local UP = Parts.UPRIGHT

local function darker(hex: string, amount: number?): Color3
	local c = Color3.fromHex(hex)
	local k = amount or 0.62
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

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

local function disc(name: string, diameter: number, height: number, color: string | Color3): Part
	return Parts.make({
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, diameter, diameter),
		cframe = CFrame.identity,
		color = color,
		anchored = false,
	})
end

local function block(name: string, size: Vector3, color: string | Color3): Part
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

-- A flat rounded rectangle (w along X, d along Z) whose top is at `top`.
local function roundedRect(
	model: Model,
	root: BasePart,
	name: string,
	cx: number,
	cz: number,
	w: number,
	d: number,
	r: number,
	top: number,
	thickness: number,
	color: string | Color3
)
	local y = top - thickness / 2
	attach(root, block(name, Vector3.new(w, thickness, d - 2 * r), color), CFrame.new(cx, y, cz), model)
	attach(root, block(name, Vector3.new(w - 2 * r, thickness, d), color), CFrame.new(cx, y, cz), model)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local corner = disc(name, r * 2, thickness, color)
			attach(root, corner, CFrame.new(cx + sx * (w / 2 - r), y, cz + sz * (d / 2 - r)) * UP, model)
		end
	end
end

-- Hats sit on the head. `s` is the character scale; the hair's top surface
-- is at y = 0.96 * s above the root center and the head is 1.9 * s wide (the
-- caller passes s already scaled for the real head size).
type HatBuilder = (model: Model, root: BasePart, s: number) -> ()

local HATS: { [string]: HatBuilder } = {
	ChefHat = function(model, root, s)
		attach(root, disc("Hat", 1.75 * s, 0.25 * s, "D8DCE2"), CFrame.new(0, 0.95 * s, 0.05 * s) * UP, model)
		attach(root, disc("Hat", 1.45 * s, 0.5 * s, "FFFFFF"), CFrame.new(0, 1.15 * s, 0.12 * s) * UP, model)
	end,
	Headband = function(model, root, s)
		attach(root, disc("Hat", 2.08 * s, 0.25 * s, "D7263D"), CFrame.new(0, 0.72 * s, 0) * UP, model)
		for side = -1, 1, 2 do
			local tail = block("Hat", Vector3.new(0.22, 0.15, 0.9) * s, "D7263D")
			attach(
				root,
				tail,
				CFrame.new(side * 0.18 * s, 0.75 * s, 1.3 * s) * CFrame.Angles(0, side * 0.35, 0),
				model
			)
		end
	end,
	Stem = function(model, root, s)
		for _, x in { -0.35, 0.35 } do
			attach(
				root,
				block("Hat", Vector3.new(0.12, 0.04, 1.2) * s, "C86412"),
				CFrame.new(x * s, 0.98 * s, 0.08 * s),
				model
			)
		end
		attach(root, disc("Hat", 0.35 * s, 0.4 * s, "3E8E3A"), CFrame.new(0, 1.12 * s, 0.08 * s) * UP, model)
		attach(
			root,
			block("Hat", Vector3.new(0.5, 0.06, 0.28) * s, "4CAF50"),
			CFrame.new(0.3 * s, 1.14 * s, 0.15 * s),
			model
		)
	end,
	Visor = function(model, root, s)
		attach(root, disc("Hat", 1.2 * s, 0.12 * s, "7FC8F8"), CFrame.new(0, 0.98 * s, -0.3 * s) * UP, model)
		attach(root, ball("Hat", 0.32 * s, "9AA3AE"), CFrame.new(0.5 * s, 1.0 * s, 0.45 * s), model)
	end,
	Crown = function(model, root, s)
		attach(root, disc("Hat", 1.3 * s, 0.35 * s, "F5C542"), CFrame.new(0, 1.08 * s, 0.08 * s) * UP, model)
		attach(root, disc("Hat", 1.0 * s, 0.37 * s, "B3242F"), CFrame.new(0, 1.09 * s, 0.08 * s) * UP, model)
		for i = 0, 4 do
			local angle = i / 5 * math.pi * 2
			local point = ball("Hat", 0.3 * s, "F5C542")
			attach(
				root,
				point,
				CFrame.new(math.sin(angle) * 0.62 * s, 1.3 * s, 0.08 * s + math.cos(angle) * 0.62 * s),
				model
			)
		end
	end,
}

-- Costume pieces for the animal and character skins, drawn in real studs at
-- scale `s`. Reference points: head center (0, 0), head radius 1.15 * s,
-- head top at y = 0.97 * s, face front at z = -1.05 * s; body 3.6 x 2.1 * s
-- centered at z = +0.1 * s with its top at y = 0.5 * s.
type Kit = {
	dot: (x: number, z: number, d: number, top: number, color: string | Color3) -> Part,
	bar: (
		x: number,
		z: number,
		w: number,
		d: number,
		top: number,
		color: string | Color3,
		yaw: number?
	) -> Part,
	pill: (x: number, z: number, w: number, d: number, top: number, color: string | Color3) -> (),
	box: (x: number, z: number, w: number, d: number, r: number, top: number, color: string | Color3) -> (),
	ball: (x: number, y: number, z: number, d: number, color: string | Color3) -> Part,
}

local function kit(model: Model, root: BasePart, s: number): Kit
	local k = {} :: Kit
	function k.dot(x, z, d, top, color)
		local part = disc("Costume", d * s, 0.05 * s, color)
		attach(root, part, CFrame.new(x * s, (top - 0.025) * s, z * s) * UP, model)
		return part
	end
	function k.bar(x, z, w, d, top, color, yaw)
		local part = block("Costume", Vector3.new(w, 0.05, d) * s, color)
		attach(root, part, CFrame.new(x * s, (top - 0.025) * s, z * s) * CFrame.Angles(0, yaw or 0, 0), model)
		return part
	end
	function k.pill(x, z, w, d, top, color)
		local r = math.min(w, d) / 2
		roundedRect(
			model,
			root,
			"Costume",
			x * s,
			z * s,
			w * s,
			d * s,
			r * s * 0.999,
			top * s,
			0.05 * s,
			color
		)
	end
	function k.box(x, z, w, d, r, top, color)
		roundedRect(model, root, "Costume", x * s, z * s, w * s, d * s, r * s, top * s, 0.05 * s, color)
	end
	function k.ball(x, y, z, d, color)
		local part = ball("Costume", d * s, if typeof(color) == "string" then color else "FFFFFF")
		if typeof(color) == "Color3" then
			part.Color = color
		end
		attach(root, part, CFrame.new(x * s, y * s, z * s), model)
		return part
	end
	return k
end

type Style = (k: Kit, skin: Skins.Skin) -> ()

local STYLES: { [string]: Style } = {
	-- The first zombie: red blotches on the body and arms (red hands come
	-- from the skin's arm color).
	Alpha = function(k, skin)
		local red = skin.accent or "B8323A"
		local spots: { { number } } =
			{ { -1.0, 0.55, 0.9 }, { 1.05, 0.05, 0.7 }, { 0.3, 0.8, 0.55 }, { -0.35, -0.45, 0.4 } }
		for _, spot in spots do
			k.dot(spot[1], spot[2], spot[3], 0.52, red)
		end
		for side = -1, 1, 2 do
			k.dot(side * 1.35, -0.75, 0.45, 0.7, red)
		end
	end,
	Robot = function(k, skin)
		k.bar(0, -0.6, 1.5, 0.35, 1.02, skin.accent or "00E5FF") -- visor
		for side = -1, 1, 2 do
			k.dot(side * 1.1, 0, 0.35, 0.95, "7F8C8D") -- bolts
		end
		k.bar(0, 0.2, 0.08, 0.8, 1.05, "7F8C8D") -- antenna stalk (seen from above)
		k.ball(0, 1.2, 0.55, 0.38, "E5484D")
	end,
	Pirate = function(k, skin)
		k.dot(0, 0.1, 2.0, 1.15, "1C1C1C") -- tricorn hat
		k.bar(0, -0.75, 1.5, 0.3, 1.16, "1C1C1C")
		k.dot(0, 0.1, 0.35, 1.18, "F4F4F4") -- skull badge
		k.dot(0.35, -0.85, 0.32, 1.05, "1C1C1C") -- eye patch
		k.bar(-0.1, -0.7, 1.4, 0.06, 1.04, "1C1C1C", -0.5)
	end,
	Cowboy = function(k, skin)
		k.dot(0, 0.05, 2.9, 1.1, skin.accent or "8B5A2B") -- wide brim
		k.pill(0, 0.05, 1.4, 1.05, 1.3, "6B4226") -- crown
		k.bar(0, 0.05, 1.42, 0.18, 1.31, "1C1C1C")
	end,
	Alien = function(k, skin)
		for side = -1, 1, 2 do
			k.pill(side * 0.45, -0.55, 0.5, 0.75, 1.02, skin.accent or "1C1C1C") -- big eyes
			k.bar(side * 0.4, 0.35, 0.08, 0.9, 1.05, skin.hair, side * 0.4) -- antennae
			k.ball(side * 0.6, 1.2, 0.75, 0.32, "C6FF00")
		end
	end,
	Knight = function(k, skin)
		k.dot(0, 0, 2.45, 1.05, "BDC3C7") -- helmet
		k.bar(0, -0.75, 1.4, 0.14, 1.07, "2B2B30") -- visor slit
		k.pill(0, 0.5, 0.45, 1.4, 1.12, skin.accent or "C0392B") -- plume
	end,
	Hotdog = function(k, skin)
		for i = -2, 2 do
			k.bar(
				i * 0.32,
				-0.1 + (i % 2) * 0.25,
				0.32,
				0.12,
				1.03,
				skin.accent or "F7DC6F",
				(i % 2) * 0.8 - 0.4
			) -- mustard
		end
	end,
}

-- Where the right hand holds an item, relative to the root (front is -Z).
function CharacterLook.grip(scale: number): CFrame
	return CFrame.new(1.2 * scale, 0.6 * scale, -0.95 * scale)
end

-- Builds (or rebuilds) the look on `model`. Keeps an existing part named
-- "Head" so anything attached to it (name tag, chat bubbles) survives.
-- The part named "Head" (name tags hang off it), reused across rebuilds.
local function placeHead(
	model: Model,
	root: BasePart,
	diameter: number,
	thickness: number,
	color: string,
	at: CFrame
)
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
	head.Size = Vector3.new(thickness, diameter, diameter)
	head.Color = Color3.fromHex(color)
	head.Material = Enum.Material.SmoothPlastic
	head.CastShadow = false
	head.TopSurface = Enum.SurfaceType.Smooth
	head.BottomSurface = Enum.SurfaceType.Smooth
	attach(root, head, at * UP, model)
end

local function lighter(hex: string, amount: number): Color3
	local c = Color3.fromHex(hex)
	return Color3.new(c.R + (1 - c.R) * amount, c.G + (1 - c.G) * amount, c.B + (1 - c.B) * amount)
end

-- Animals ----------------------------------------------------------------------------
-- Animal skins get their own body instead of the person shape: long and thin
-- from above with the head in front (-Z), paws, ears and a tail. Sizes are
-- studs at scale 1. Colors: shirt = body, hair = head, skin = muzzle / light
-- parts, accent = ears, paws and other dark parts.

type Animal = {
	body: "Quadruped" | "Bird" | "Fish" | "Frog",
	width: number, -- torso, side to side
	length: number, -- torso, front to back
	head: number, -- head diameter
	snout: { number }?, -- muzzle { width, length } in front of the head
	ears: string?, -- Floppy | Pointy | Tall | Round | Long
	tail: string?, -- Wag | Long | Stub | Cotton | Tuft | Duck
	stripe: boolean?, -- dark line down the back
	whiskers: boolean?,
	patches: boolean?, -- panda markings
}

local ANIMALS: { [string]: Animal } = {
	Dog = {
		body = "Quadruped",
		width = 2.0,
		length = 3.6,
		head = 1.7,
		snout = { 0.8, 0.9 },
		ears = "Floppy",
		tail = "Wag",
	},
	Cat = {
		body = "Quadruped",
		width = 1.75,
		length = 3.3,
		head = 1.55,
		snout = { 0.6, 0.45 },
		ears = "Pointy",
		tail = "Long",
		whiskers = true,
	},
	Bunny = {
		body = "Quadruped",
		width = 1.95,
		length = 2.9,
		head = 1.55,
		snout = { 0.5, 0.35 },
		ears = "Tall",
		tail = "Cotton",
	},
	Bear = {
		body = "Quadruped",
		width = 2.5,
		length = 3.6,
		head = 1.9,
		snout = { 0.95, 0.8 },
		ears = "Round",
		tail = "Stub",
	},
	Panda = {
		body = "Quadruped",
		width = 2.5,
		length = 3.5,
		head = 1.9,
		snout = { 0.85, 0.7 },
		ears = "Round",
		tail = "Stub",
		patches = true,
	},
	Donkey = {
		body = "Quadruped",
		width = 1.8,
		length = 3.9,
		head = 1.45,
		snout = { 0.95, 1.25 },
		ears = "Long",
		tail = "Tuft",
		stripe = true,
	},
	Frog = { body = "Frog", width = 2.3, length = 2.5, head = 2.0 },
	Penguin = { body = "Bird", width = 2.2, length = 2.8, head = 1.65 },
	Bill = { body = "Bird", width = 2.2, length = 2.8, head = 1.55, tail = "Duck" }, -- the Duck skin
	Shark = { body = "Fish", width = 1.9, length = 4.6, head = 1.9 },
}

-- Animals are drawn smaller than people (and a bit slimmer still).
local ANIMAL_SCALE = 0.8
local ANIMAL_SLIM = 0.9

local function buildAnimal(model: Model, root: BasePart, scale: number, skin: Skins.Skin, a: Animal)
	local s = scale * ANIMAL_SCALE
	local k = kit(model, root, s)
	local main, head, light = skin.shirt, skin.hair, skin.skin
	local dark = skin.accent or darker(main)
	local edge = darker(main, 0.7)
	local W, L = a.width * ANIMAL_SLIM, a.length
	local headZ = if a.body == "Frog" then -0.85 elseif a.body == "Fish" then -1.35 else -1.5
	local bodyZ = if a.body == "Frog" then 0.4 elseif a.body == "Fish" then 0.6 else 0.45
	local back = bodyZ + L / 2 -- rear end of the torso
	local function torso()
		local r = W * (if a.body == "Quadruped" then 0.28 else 0.42)
		k.box(0, bodyZ, W + 0.24, L + 0.24, r + 0.12, 0.47, edge)
		k.box(0, bodyZ, W, L, r, 0.5, main)
		if a.body == "Quadruped" then
			-- Shoulders and hips a touch wider than the waist.
			k.box(0, bodyZ - L * 0.3, W * 1.07, L * 0.3, r, 0.502, main)
			k.box(0, bodyZ + L * 0.3, W * 1.09, L * 0.32, r, 0.502, main)
		end
		k.box(-W * 0.14, bodyZ - L * 0.08, W * 0.36, L * 0.5, W * 0.15, 0.51, lighter(main, 0.14)) -- sheen
	end
	local function eyes(spread: number, z: number, size: number)
		for side = -1, 1, 2 do
			k.dot(side * spread, z, size, 0.95, "1C1C1C")
			k.dot(side * spread - 0.04, z - 0.04, size * 0.35, 0.97, "FFFFFF")
		end
	end

	if a.body == "Quadruped" then
		-- Legs splay out from shoulders and hips (front ones forward, back
		-- ones back), with a paw or hoof at the end.
		local spread, legLength = 0.45, 1.0
		local sx, cz = math.sin(spread), math.cos(spread)
		for side = -1, 1, 2 do
			for _, leg in
				{
					{ z = bodyZ - L * 0.3, dz = -1, yaw = -side * spread },
					{ z = bodyZ + L * 0.3, dz = 1, yaw = side * spread },
				}
			do
				local dx, dz = side * sx, leg.dz * cz
				local cx, lz = side * W / 2 + dx * 0.3, leg.z + dz * 0.3
				k.bar(cx, lz, 0.42, legLength, 0.36, if a.patches then dark else main, leg.yaw) -- pandas: black legs
				k.box(cx + dx * legLength * 0.5, lz + dz * legLength * 0.5, 0.52, 0.44, 0.14, 0.37, dark)
			end
		end
		local tail = a.tail
		if tail == "Wag" then
			k.pill(0.2, back + 0.55, 0.42, 1.3, 0.4, main)
		elseif tail == "Long" then
			k.pill(0, back + 0.8, 0.3, 1.7, 0.4, main)
			k.pill(0.35, back + 1.55, 0.3, 0.7, 0.41, dark)
		elseif tail == "Stub" then
			k.dot(0, back + 0.05, 0.6, 0.4, dark)
		elseif tail == "Tuft" then
			k.pill(0, back + 0.65, 0.22, 1.4, 0.4, main)
			k.pill(0, back + 1.35, 0.42, 0.6, 0.41, dark)
		end
		torso()
		if a.stripe then
			k.pill(0, bodyZ - 0.1, 0.3, L * 0.85, 0.53, dark) -- mane / spine stripe
		end
		if a.patches then
			k.bar(0, bodyZ - L * 0.22, W, 0.95, 0.52, dark) -- panda shoulder band
		end
		if tail == "Cotton" then
			k.dot(0, back - 0.05, 0.85, 0.54, "FFFFFF")
		end
	elseif a.body == "Bird" then
		local beak = skin.accent or "F28C1C"
		for side = -1, 1, 2 do
			k.pill(side * 0.45, back + 0.2, 0.42, 0.65, 0.36, beak) -- feet
		end
		if a.tail == "Duck" then
			k.bar(0, back + 0.1, 0.75, 0.75, 0.42, main, math.rad(45))
		end
		torso()
		for side = -1, 1, 2 do
			k.pill(side * (W / 2 - 0.05), bodyZ + 0.15, 0.6, L * 0.72, 0.53, darker(main, 0.8)) -- wings
		end
	elseif a.body == "Fish" then
		local fin = skin.accent or darker(main)
		for side = -1, 1, 2 do
			k.bar(side * 0.5, back + 0.45, 0.45, 1.35, 0.42, fin, side * 0.6) -- tail fin
			k.bar(side * (W / 2 + 0.35), headZ + 1.0, 0.5, 1.5, 0.42, fin, side * 0.8) -- side fins
		end
		torso()
		k.pill(0, headZ - W / 2 + 0.1, W * 0.62, 1.0, 0.5, main) -- pointed nose
		k.pill(0, bodyZ + 0.2, 0.28, 1.3, 0.56, fin) -- dorsal fin
		for side = -1, 1, 2 do
			for i = 0, 2 do
				k.bar(side * W * 0.38, headZ + 0.75 + i * 0.2, 0.05, 0.42, 0.53, edge) -- gills
			end
		end
	else -- Frog
		for side = -1, 1, 2 do
			k.pill(side * 1.2, bodyZ + 0.55, 0.75, 1.7, 0.38, main) -- folded back legs
			k.dot(side * 1.45, bodyZ + 1.45, 0.85, 0.39, dark) -- webbed feet
			k.pill(side * 1.1, -0.55, 0.45, 0.9, 0.38, main) -- front legs
			k.dot(side * 1.25, -1.0, 0.5, 0.39, dark)
		end
		torso()
		for _, spot in { { -0.5, 0.6 }, { 0.55, 0.9 }, { 0.1, 1.25 } } do
			k.dot(spot[1], bodyZ + spot[2] - 0.6, 0.4, 0.52, dark)
		end
	end

	-- Head, with an outline. Four-legged animals get a squarer skull (with a
	-- neck); the "Head" part (name tags hang off it) sits hidden under it.
	local fish = a.body == "Fish"
	local headSize = if fish then W else a.head
	if a.body == "Quadruped" then
		local neckFrom, neckTo = bodyZ - L / 2 + 0.3, headZ
		k.box(0, (neckFrom + neckTo) / 2, W * 0.55, neckFrom - neckTo, W * 0.2, 0.6, main) -- neck
		local hw, hd = a.head * 0.9, a.head * 0.95
		k.box(0, headZ, hw + 0.2, hd + 0.2, hw * 0.32 + 0.1, 0.86, darker(head, 0.7))
		k.box(0, headZ, hw, hd, hw * 0.32, 0.88, head)
		placeHead(model, root, a.head * 0.75 * s, 0.3 * s, head, CFrame.new(0, 0.7 * s, headZ * s))
	else
		k.dot(
			0,
			headZ,
			headSize + 0.22,
			if fish then 0.49 else 0.86,
			if fish then edge else darker(head, 0.7)
		)
		placeHead(
			model,
			root,
			headSize * s,
			0.3 * s,
			if fish then main else head,
			CFrame.new(0, (if fish then 0.36 else 0.72) * s, headZ * s)
		)
	end

	if a.body == "Quadruped" then
		local ears = a.ears
		local hr = a.head / 2
		for side = -1, 1, 2 do
			if ears == "Floppy" then
				k.box(side * (hr - 0.02), headZ + 0.2, 0.55, 1.2, 0.2, 0.84, dark)
			elseif ears == "Pointy" then
				k.bar(side * hr * 0.78, headZ + hr * 0.5, 0.72, 0.72, 0.84, dark, math.rad(45))
			elseif ears == "Round" then
				k.dot(side * hr * 0.8, headZ + hr * 0.45, 0.72, 0.84, dark)
			elseif ears == "Tall" then
				k.box(side * 0.32, headZ + hr + 0.7, 0.5, 1.9, 0.22, 0.9, head)
				k.box(side * 0.32, headZ + hr + 0.75, 0.24, 1.4, 0.1, 0.91, skin.accent or "FFB3C7")
			elseif ears == "Long" then
				-- Donkey ears stick out to the sides, swept a little back.
				k.bar(side * (hr + 0.45), headZ + 0.35, 0.42, 1.35, 0.84, dark, side * math.rad(68))
				k.bar(
					side * (hr + 0.5),
					headZ + 0.37,
					0.18,
					0.95,
					0.85,
					lighter(main, 0.35),
					side * math.rad(68)
				)
			end
		end
		if a.patches then
			for side = -1, 1, 2 do
				k.pill(side * hr * 0.42, headZ - hr * 0.15, 0.45, 0.6, 0.93, dark) -- eye patches
			end
		end
		local snout = a.snout
		local front = headZ - a.head * 0.95 / 2
		if snout then
			-- A squarish muzzle sticking out past the skull, nose at its tip.
			local sw, sl = snout[1], snout[2]
			local muzzleZ = front - sl / 2 + 0.3
			k.box(0, muzzleZ, sw + 0.14, sl + 0.14, sw * 0.3 + 0.07, 0.9, darker(light, 0.75))
			k.box(0, muzzleZ, sw, sl, sw * 0.3, 0.92, light)
			k.box(0, muzzleZ - sl / 2 + 0.16, math.min(0.42, sw * 0.55), 0.24, 0.1, 0.95, "2B2B2B") -- nose
		end
		if a.whiskers then
			for side = -1, 1, 2 do
				for _, tilt in { -0.15, 0.15 } do
					k.bar(side * 0.5, front + tilt, 0.85, 0.05, 0.96, "1C1C1C", side * tilt)
				end
			end
		end
		eyes(hr * 0.42, headZ - hr * 0.2, 0.2)
	elseif a.body == "Bird" then
		local hr = a.head / 2
		local beak = skin.accent or "F28C1C"
		if a.tail == "Duck" then
			k.pill(0, headZ - hr - 0.1, 0.95, 0.75, 0.92, beak) -- flat bill
		else
			k.pill(0, headZ - hr * 0.35, a.head * 0.7, a.head * 0.45, 0.9, light) -- white face
			k.bar(0, headZ - hr - 0.05, 0.42, 0.42, 0.92, beak, math.rad(45)) -- pointy beak
		end
		eyes(hr * 0.4, headZ - hr * 0.3, 0.2)
	elseif fish then
		eyes(W * 0.32, headZ - 0.25, 0.18)
	else -- Frog
		for side = -1, 1, 2 do
			k.dot(side * 0.62, headZ - 0.45, 0.8, 0.93, light) -- bulging eyes
			k.dot(side * 0.62, headZ - 0.55, 0.36, 0.96, "1C1C1C")
		end
		k.bar(0, headZ - 0.85, 1.1, 0.07, 0.92, dark) -- wide mouth
	end
end

function CharacterLook.apply(model: Model, root: BasePart, skinId: string?, team: Skins.Team, scale: number)
	local skin = Skins.resolve(skinId, team)
	local s = scale

	for _, child in model:GetChildren() do
		if child:GetAttribute("LookPart") and child.Name ~= "Head" then
			child:Destroy()
		end
	end

	-- Soft shadow on the floor under the character.
	local shadow = disc("Shadow", 3.1 * s, 0.05, Color3.new(0, 0, 0))
	shadow.Transparency = 0.72
	-- Floor level is HipHeight below the root's bottom (hip height doesn't scale).
	attach(root, shadow, CFrame.new(0, -(C.RootHeight / 2 * s + C.HipHeight) + 0.14, 0) * UP, model)

	local animal = skin.hat and ANIMALS[skin.hat]
	if animal then
		buildAnimal(model, root, s, skin, animal)
		return
	end

	-- Body: outline first (bigger, lower), then the shirt on top.
	local w, d, r, o = C.BodyWidth * s, C.BodyDepth * s, 0.7 * s, 0.14 * s
	roundedRect(
		model,
		root,
		"BodyOutline",
		0,
		0.1 * s,
		w + 2 * o,
		d + 2 * o,
		r + o,
		0.42 * s,
		0.6 * s,
		darker(skin.shirt)
	)
	roundedRect(model, root, "Body", 0, 0.1 * s, w, d, r, 0.5 * s, 0.6 * s, skin.shirt)

	if team == "Zombie" then
		-- Arms reaching straight forward from the shoulders, like the original:
		-- one thick arm in the shirt color with the hand at the end in the
		-- skin color (red claws on the alpha).
		local hands = skin.arms or skin.skin
		local armW, armL, armZ = 0.88 * s, 2.45 * s, -1.35 * s
		local handL = 0.85 * s
		for side = -1, 1, 2 do
			local x = side * 1.36 * s
			roundedRect(
				model,
				root,
				"ArmOutline",
				x,
				armZ,
				armW + 2 * o,
				armL + 2 * o,
				armW / 2 + o,
				0.62 * s,
				0.25 * s,
				darker(skin.shirt)
			)
			roundedRect(
				model,
				root,
				"Arm",
				x,
				armZ,
				armW,
				armL,
				armW / 2 * 0.999,
				0.66 * s,
				0.25 * s,
				skin.shirt
			)
			local handZ = armZ - armL / 2 + handL / 2
			roundedRect(
				model,
				root,
				"Hand",
				x,
				handZ,
				armW,
				handL,
				armW / 2 * 0.999,
				0.67 * s,
				0.05 * s,
				hands
			)
			attach(
				root,
				block("Cuff", Vector3.new(armW, 0.05 * s, 0.08 * s), darker(skin.shirt)),
				CFrame.new(x, 0.655 * s, handZ + handL / 2),
				model
			)
		end
	end

	-- Head: hair-colored disc (kept as "Head"), with the face crescent at the
	-- front made by a skin disc partly covered by a hair disc set back.
	local hd = C.HeadDiameter * s
	placeHead(model, root, hd, 0.3 * s, skin.hair, CFrame.new(0, 0.75 * s, 0))
	attach(
		root,
		disc("HeadOutline", hd + 0.1 * s, 0.3 * s, darker(skin.hair, 0.8)),
		CFrame.new(0, 0.72 * s, 0) * UP,
		model
	)
	-- A little nose poking out past the front of the head, like the original.
	local nose = 0.3 * hd
	attach(
		root,
		disc("NoseOutline", nose + 0.1 * s, 0.05 * s, darker(skin.skin, 0.75)),
		CFrame.new(0, 0.89 * s, -0.47 * hd) * UP,
		model
	)
	attach(root, disc("Nose", nose, 0.05 * s, skin.skin), CFrame.new(0, 0.9 * s, -0.47 * hd) * UP, model)
	attach(root, disc("Face", 0.82 * hd, 0.04 * s, skin.skin), CFrame.new(0, 0.92 * s, -0.1 * s) * UP, model)
	attach(root, disc("Hair", 0.74 * hd, 0.04 * s, skin.hair), CFrame.new(0, 0.95 * s, 0.08 * s) * UP, model)

	local style = skin.hat and STYLES[skin.hat]
	if style then
		style(kit(model, root, s), skin)
	end
	local hat = skin.hat and HATS[skin.hat]
	if hat then
		hat(model, root, s * C.HeadDiameter / 1.9) -- hats were sized for a 1.9-stud head
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
			if d.Name == "Shadow" then
				d:Destroy()
			end
		end
	end
	return model
end

return CharacterLook
