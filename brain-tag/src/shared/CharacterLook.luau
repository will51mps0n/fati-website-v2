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
	Bill = function(model, root, s)
		attach(
			root,
			block("Hat", Vector3.new(0.9, 0.2, 0.8) * s, "F28C1C"),
			CFrame.new(0, 0.85 * s, -1.15 * s),
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
	Spots = function(model, root, s)
		for _, spot in { { -0.35, 0.1, 0.4 }, { 0.35, 0.35, 0.3 }, { 0, 0.55, 0.25 } } do
			local part = disc("Hat", spot[3] * s, 0.04 * s, "3E7F12")
			attach(root, part, CFrame.new(spot[1] * s, 0.97 * s, spot[2] * s) * UP, model)
		end
	end,
	Frost = function(model, root, s)
		for _, spot in { { -0.4, 0.05, 0.38 }, { 0.3, 0.4, 0.3 }, { 0.25, -0.25, 0.25 } } do
			local part = disc("Hat", spot[3] * s, 0.04 * s, "FFFFFF")
			attach(root, part, CFrame.new(spot[1] * s, 0.97 * s, spot[2] * s) * UP, model)
		end
	end,
	Bandage = function(model, root, s)
		for i, angle in { -0.5, 0.15, 0.8 } do
			local strip = block("Hat", Vector3.new(1.5, 0.04, 0.24) * s, "F7F2E4")
			attach(
				root,
				strip,
				CFrame.new(0, (0.97 + i * 0.01) * s, (i - 2) * 0.35 * s + 0.1 * s)
					* CFrame.Angles(0, angle, 0),
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

-- Ears stick out from under the head; snouts and noses sit on top of it.
type Style = (k: Kit, skin: Skins.Skin) -> ()

local function snout(k: Kit, color: string, nose: string)
	k.dot(0, -0.85, 0.95, 1.0, color)
	k.dot(0, -1.15, 0.42, 1.04, nose)
end

local STYLES: { [string]: Style } = {
	Dog = function(k, skin)
		local ear = skin.accent or "6B4226"
		for side = -1, 1, 2 do
			k.pill(side * 1.05, 0.15, 0.7, 1.3, 0.92, ear) -- floppy ears
		end
		snout(k, skin.skin, "1C1C1C")
		k.pill(0, 1.7, 0.5, 1.2, 0.55, skin.shirt) -- tail
		k.dot(0, 2.25, 0.5, 0.55, skin.shirt)
	end,
	Cat = function(k, skin)
		local ear = skin.accent or "6E6E73"
		for side = -1, 1, 2 do
			k.bar(side * 0.72, -0.45, 0.75, 0.75, 0.85, ear, math.rad(45)) -- pointy ears
			for _, angle in { -0.15, 0.15 } do
				k.bar(side * 0.55, -1.15 + angle, 0.9, 0.05, 1.06, "1C1C1C", side * angle) -- whiskers
			end
		end
		k.dot(0, -1.1, 0.3, 1.05, "FF8FAB")
		k.bar(0.4, 1.7, 0.3, 1.4, 0.55, skin.shirt, 0.5) -- tail
	end,
	Bunny = function(k, skin)
		for side = -1, 1, 2 do
			k.pill(side * 0.42, 1.05, 0.55, 1.9, 1.05, skin.hair) -- long ears
			k.pill(side * 0.42, 1.05, 0.28, 1.4, 1.07, skin.accent or "FFB3C7")
		end
		k.dot(0, -1.12, 0.32, 1.05, "FF8FAB")
		k.dot(0, 1.4, 0.75, 0.56, "FFFFFF") -- fluffy tail
	end,
	Bear = function(k, skin)
		for side = -1, 1, 2 do
			k.dot(side * 0.9, 0.2, 0.75, 0.86, skin.accent or "5A3518")
		end
		snout(k, skin.skin, "1C1C1C")
	end,
	Panda = function(k, skin)
		for side = -1, 1, 2 do
			k.dot(side * 0.9, 0.15, 0.75, 0.86, "1C1C1C") -- ears
			k.pill(side * 0.38, -0.55, 0.38, 0.55, 1.0, "1C1C1C") -- eye patches
		end
		k.dot(0, -1.12, 0.3, 1.04, "1C1C1C")
	end,
	Frog = function(k, skin)
		for side = -1, 1, 2 do
			k.dot(side * 0.5, -0.55, 0.8, 1.1, "FFFFFF") -- big eyes
			k.dot(side * 0.5, -0.65, 0.35, 1.14, "1C1C1C")
		end
		k.bar(0, -0.95, 0.9, 0.08, 1.03, skin.accent or "2E7D32") -- smile
	end,
	Penguin = function(k, skin)
		k.pill(0, -0.4, 2.0, 1.0, 0.53, "F4F4F4") -- white belly on the chest
		k.bar(0, -1.25, 0.5, 0.45, 1.03, skin.accent or "F39C12", math.rad(45)) -- beak
		for side = -1, 1, 2 do
			k.dot(side * 0.35, -0.6, 0.25, 1.02, "1C1C1C")
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
	Shark = function(k, skin)
		local fin = skin.accent or "4A6378"
		k.bar(0, 0.2, 0.55, 0.55, 1.12, fin, math.rad(45)) -- dorsal fin
		for side = -1, 1, 2 do
			k.bar(side * 2.0, 0.1, 0.8, 0.8, 0.45, fin, math.rad(45)) -- side fins
			k.bar(side * 0.45, 1.75, 0.7, 0.7, 0.45, fin, math.rad(45)) -- tail fin
		end
		k.bar(0, -0.95, 1.2, 0.1, 1.03, "F4F4F4") -- teeth
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
	Skeleton = function(k, skin)
		for i = -1, 2 do
			k.bar(0, i * 0.35 + 0.1, 2.4, 0.13, 0.53, "F4F4F4") -- ribs
		end
		k.bar(0, 0.1, 0.18, 1.6, 0.54, "F4F4F4") -- spine
		for side = -1, 1, 2 do
			k.dot(side * 0.4, -0.5, 0.45, 1.02, "1C1C1C") -- eye sockets
		end
	end,
	Ghost = function(k, skin)
		for side = -1, 1, 2 do
			k.pill(side * 0.38, -0.55, 0.35, 0.55, 1.02, "1C1C1C")
		end
		k.dot(0, -0.95, 0.4, 1.03, "1C1C1C") -- "oooo" mouth
		k.pill(0, 1.6, 1.6, 1.0, 0.45, skin.shirt) -- wispy tail
	end,
	Vampire = function(k, skin)
		k.pill(0, 0.55, 4.1, 1.8, 0.48, skin.accent or "8E1B1B") -- cape lining
		k.bar(0, -0.75, 0.9, 0.5, 1.0, skin.hair, 0) -- widow's peak
		for side = -1, 1, 2 do
			k.bar(side * 0.15, -1.12, 0.1, 0.18, 1.06, "FFFFFF") -- fangs
		end
	end,
	Clown = function(k, skin)
		for i, color in { "E5484D", "F1C40F", "3498DB" } do
			k.ball(-1.0, 0.95, (i - 2) * 0.45, 0.6, color)
			k.ball(1.0, 0.95, (i - 2) * 0.45, 0.6, color)
		end
		k.ball(0, 1.05, -1.1, 0.4, skin.accent or "E5484D") -- red nose
	end,
}

-- Where the right hand holds an item, relative to the root (front is -Z).
function CharacterLook.grip(scale: number): CFrame
	return CFrame.new(1.2 * scale, 0.6 * scale, -0.95 * scale)
end

-- Builds (or rebuilds) the look on `model`. Keeps an existing part named
-- "Head" so anything attached to it (name tag, chat bubbles) survives.
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
		-- Arms reaching forward, drawn over the body.
		for side = -1, 1, 2 do
			local x, z = side * 0.85 * s, -1.45 * s
			roundedRect(
				model,
				root,
				"ArmOutline",
				x,
				z,
				0.86 * s,
				2.0 * s,
				0.43 * s,
				0.62 * s,
				0.3 * s,
				darker(skin.skin)
			)
			roundedRect(model, root, "Arm", x, z, 0.62 * s, 1.76 * s, 0.31 * s, 0.68 * s, 0.3 * s, skin.skin)
		end
	end

	-- Head: hair-colored disc (kept as "Head"), with the face crescent at the
	-- front made by a skin disc partly covered by a hair disc set back.
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
	local hd = C.HeadDiameter * s
	head.Name = "Head"
	head.Shape = Enum.PartType.Cylinder
	head.Size = Vector3.new(0.3 * s, hd, hd)
	head.Color = Color3.fromHex(skin.hair)
	head.Material = Enum.Material.SmoothPlastic
	head.CastShadow = false
	head.TopSurface = Enum.SurfaceType.Smooth
	head.BottomSurface = Enum.SurfaceType.Smooth
	attach(root, head, CFrame.new(0, 0.75 * s, 0) * UP, model)
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
