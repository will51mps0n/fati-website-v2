-- Builds one furniture piece: an invisible-to-physics stack of colored details
-- welded onto a single "Body" part that carries all the mass and collision.
-- Details are designed to read clearly from straight above.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FurnitureSpecs = require(ReplicatedStorage.Shared.FurnitureSpecs)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Parts = require(ReplicatedStorage.Shared.Parts)

local FurnitureBuilder = {}

-- Context passed to each design: adds parts relative to the body center.
type Ctx = {
	w: number,
	d: number,
	h: number,
	body: Part,
	model: Model,
	-- Block whose top sits `raise` studs above the body's top.
	top: (
		self: Ctx,
		x: number,
		z: number,
		sx: number,
		sz: number,
		raise: number,
		thickness: number,
		color: string,
		yaw: number?
	) -> Part,
	disc: (
		self: Ctx,
		x: number,
		z: number,
		diameter: number,
		raise: number,
		thickness: number,
		color: string
	) -> Part,
	ball: (self: Ctx, x: number, y: number, z: number, diameter: number, color: string) -> Part,
}

local function newCtx(model: Model, body: Part, w: number, d: number, h: number): Ctx
	local ctx = { w = w, d = d, h = h, body = body, model = model } :: any

	function ctx.top(self: Ctx, x, z, sx, sz, raise, thickness, color, yaw)
		local y = self.h / 2 + raise - thickness / 2
		local part = Parts.make({
			name = "Detail",
			size = Vector3.new(sx, thickness, sz),
			cframe = self.body.CFrame * CFrame.new(x, y, z) * CFrame.Angles(0, yaw or 0, 0),
			color = color,
			parent = self.model,
		})
		return part
	end

	function ctx.disc(self: Ctx, x, z, diameter, raise, thickness, color)
		local y = self.h / 2 + raise - thickness / 2
		return Parts.make({
			name = "Detail",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(thickness, diameter, diameter),
			cframe = self.body.CFrame * CFrame.new(x, y, z) * Parts.UPRIGHT,
			color = color,
			parent = self.model,
		})
	end

	function ctx.ball(self: Ctx, x, y, z, diameter, color)
		return Parts.make({
			name = "Detail",
			shape = Enum.PartType.Ball,
			size = Vector3.one * diameter,
			cframe = self.body.CFrame * CFrame.new(x, y, z),
			color = color,
			parent = self.model,
		})
	end

	return ctx :: Ctx
end

type Design = { body: string, transparentBody: boolean?, draw: (ctx: Ctx) -> () }

local BOOK_COLORS = { "C0392B", "2E86C1", "27AE60", "F1C40F", "8E44AD", "E67E22", "16A085", "D35400" }

local DESIGNS: { [string]: Design } = {
	Couch = {
		body = "3C8DBC",
		draw = function(c)
			c:top(0, -c.d / 2 + 0.5, c.w, 1.0, 0.7, 0.8, "2F7099") -- backrest
			for side = -1, 1, 2 do
				c:top(side * (c.w / 2 - 0.45), 0.2, 0.9, c.d - 0.4, 0.5, 0.6, "2F7099") -- arms
				c:top(side * (c.w / 4 - 0.2), 0.45, c.w / 2 - 1.3, c.d - 1.3, 0.15, 0.2, "5BA7D6") -- cushions
			end
		end,
	},
	Armchair = {
		body = "4E9A3E",
		draw = function(c)
			c:top(0, -c.d / 2 + 0.45, c.w, 0.9, 0.7, 0.8, "3D7D30")
			for side = -1, 1, 2 do
				c:top(side * (c.w / 2 - 0.35), 0.2, 0.7, c.d - 0.4, 0.5, 0.6, "3D7D30")
			end
			c:top(0, 0.45, c.w - 1.6, c.d - 1.3, 0.15, 0.2, "6CBF5A")
		end,
	},
	Fridge = {
		body = "EEF1F4",
		draw = function(c)
			c:top(0, -0.3, c.w - 0.4, 0.12, 0.03, 0.06, "B9C0C8") -- door split
			c:top(c.w / 2 - 0.7, c.d / 2 - 0.25, 0.25, 0.5, 0.06, 0.1, "8A939C") -- handle
			c:top(0, 0, c.w - 0.3, c.d - 0.3, 0.01, 0.02, "F7F9FA")
		end,
	},
	Stove = {
		body = "E6E6E6",
		draw = function(c)
			c:top(0, -c.d / 2 + 0.3, c.w, 0.6, 0.35, 0.4, "BDBDBD") -- control strip
			for _, x in { -0.9, 0.9 } do
				for _, z in { -0.35, 0.95 } do
					c:disc(x, z, 1.1, 0.06, 0.08, "3A3A3A")
					c:disc(x, z, 0.5, 0.08, 0.08, "6B6B6B")
				end
			end
		end,
	},
	Sink = {
		body = "C9D1D9",
		draw = function(c)
			c:top(0, 0.25, c.w - 1.4, c.d - 1.2, 0.03, 0.06, "8FA6BC") -- basin
			c:top(0, -c.d / 2 + 0.35, 0.3, 0.7, 0.4, 0.4, "8A939C") -- faucet
		end,
	},
	Toilet = {
		body = "F2F4F6",
		draw = function(c)
			c:top(0, -c.d / 2 + 0.5, c.w, 1.0, 0.5, 0.6, "E1E6EB") -- tank
			c:disc(0, 0.45, 2.1, 0.04, 0.08, "DCE3E9") -- seat
			c:disc(0, 0.45, 1.3, 0.06, 0.08, "A8D4EE") -- water
		end,
	},
	Bathtub = {
		body = "F4F7FA",
		draw = function(c)
			c:top(0, 0, c.w - 1.0, c.d - 1.0, 0.03, 0.06, "A9D6F0")
			c:top(c.w / 2 - 0.4, 0, 0.4, 0.5, 0.3, 0.3, "8A939C") -- tap
		end,
	},
	Bed = {
		body = "8E5A32",
		draw = function(c)
			c:top(0, -c.d / 2 + 0.25, c.w, 0.5, 0.6, 0.7, "6B4226") -- headboard
			c:top(0, 0.1, c.w - 0.6, c.d - 0.8, 0.2, 0.3, "F5F5F5") -- mattress
			c:top(0, c.d * 0.18, c.w - 0.5, c.d * 0.6, 0.3, 0.35, "5B7FD6") -- blanket
			c:top(0, c.d * 0.18 - c.d * 0.3 + 0.2, c.w - 0.5, 0.4, 0.32, 0.36, "4A6BC0") -- fold
			for side = -1, 1, 2 do
				c:top(side * 1.55, -c.d / 2 + 1.3, 2.6, 1.4, 0.45, 0.4, "FFFFFF") -- pillows
			end
		end,
	},
	Table = {
		body = "B07A45",
		draw = function(c)
			c:top(0, 0, c.w - 0.6, c.d - 0.6, 0.02, 0.04, "C08A55")
		end,
	},
	CoffeeTable = {
		body = "9A6838",
		draw = function(c)
			c:top(0, 0, c.w - 0.5, c.d - 0.5, 0.02, 0.04, "B07A45")
		end,
	},
	Chair = {
		body = "C08A55",
		draw = function(c)
			c:top(0, -c.d / 2 + 0.2, c.w, 0.4, 0.8, 0.9, "8B5A2B")
		end,
	},
	Bookshelf = {
		body = "6B4226",
		draw = function(c)
			local count = 11
			local span = c.w - 0.6
			for i = 1, count do
				local x = -span / 2 + (i - 0.5) * span / count
				c:top(
					x,
					0.15,
					span / count - 0.12,
					c.d - 0.7,
					0.04,
					0.08,
					BOOK_COLORS[(i - 1) % #BOOK_COLORS + 1]
				)
			end
		end,
	},
	Box = {
		body = "C9A06A",
		draw = function(c)
			c:top(0, 0, 0.55, c.d, 0.02, 0.04, "E6CFA1") -- tape
			c:top(0, 0, c.w, 0.08, 0.02, 0.04, "A88350") -- flap seam
		end,
	},
	Plant = {
		body = "B5653A",
		transparentBody = true,
		draw = function(c)
			c:disc(0, 0, 2.0, -0.6, c.h - 0.6, "B5653A") -- pot
			c:disc(0, 0, 1.6, -0.55, 0.1, "5A3A22") -- soil
			for i = 0, 3 do
				local a = i / 4 * math.pi * 2 + 0.4
				c:ball(
					math.cos(a) * 0.55,
					c.h / 2 + 0.1,
					math.sin(a) * 0.55,
					1.2,
					if i % 2 == 0 then "3E9B3A" else "4FB848"
				)
			end
		end,
	},
	Picture = {
		body = "D4A93A",
		draw = function(c)
			c:top(0, 0, c.w - 0.7, c.d - 0.7, 0.03, 0.06, "7FB8E0") -- sky
			c:top(0, 0.55, c.w - 0.7, 0.6, 0.05, 0.06, "5BAA4A") -- hill
			c:disc(0.9, -0.35, 0.6, 0.07, 0.06, "FFD54A") -- sun
		end,
	},
	Rug = {
		body = "B5443B",
		draw = function(c)
			c:top(0, 0, c.w - 1.0, c.d - 1.0, 0.02, 0.02, "D46A5E")
			c:top(0, 0, c.w - 3.0, c.d - 3.0, 0.04, 0.02, "B5443B")
			c:top(0, 0, c.w - 5.0, c.d - 5.0, 0.06, 0.02, "E8C26A")
		end,
	},
}

local UPRIGHT_FRAME = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.zAxis) -- X axis points up

export type Built = {
	model: Model,
	body: Part,
	kind: string,
	weight: FurnitureSpecs.Weight,
	decor: boolean,
	home: CFrame,
}

function FurnitureBuilder.build(spot: MapLayout.FurnitureSpot, parent: Instance): Built
	local spec = FurnitureSpecs.get(spot.kind)
	local design = DESIGNS[spot.kind]
	local floorTop = MapLayout.HEIGHTS.Floor
	local decor = spec.decor == true
	local baseY = if decor then MapLayout.HEIGHTS.Rug - spec.h / 2 else floorTop + spec.h / 2 + 0.02
	local home = CFrame.new(spot.x, baseY, spot.z) * CFrame.Angles(0, math.rad(spot.rot), 0)

	local model = Instance.new("Model")
	model.Name = spot.kind
	local body = Parts.make({
		name = "Body",
		size = Vector3.new(spec.w, spec.h, spec.d),
		cframe = home,
		color = design.body,
		transparency = if design.transparentBody then 1 else 0,
		parent = model,
	})
	model.PrimaryPart = body

	design.draw(newCtx(model, body, spec.w, spec.d, spec.h))

	if decor then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
			end
		end
		model.Parent = parent
		return {
			model = model,
			body = body,
			kind = spot.kind,
			weight = spec.weight,
			decor = true,
			home = home,
		}
	end

	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part ~= body then
			Parts.makeVisual(part)
			Parts.weldInPlace(body, part)
		end
	end

	body.Anchored = false
	body.CollisionGroup = "Furniture"
	body.CustomPhysicalProperties =
		PhysicalProperties.new(Config.FURNITURE_DENSITY[spec.weight], 1, 0, 100, 1)

	-- Stay upright but spin freely around the vertical axis.
	local attachment = Instance.new("Attachment")
	attachment.Name = "Upright"
	attachment.CFrame = UPRIGHT_FRAME
	attachment.Parent = body
	local align = Instance.new("AlignOrientation")
	align.Name = "KeepUpright"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.AlignType = Enum.AlignType.PrimaryAxisParallel
	align.Attachment0 = attachment
	align.CFrame = UPRIGHT_FRAME
	align.MaxTorque = 1e7
	align.Responsiveness = 40
	align.Parent = body

	model:SetAttribute("Weight", spec.weight)
	model.Parent = parent
	return { model = model, body = body, kind = spot.kind, weight = spec.weight, decor = false, home = home }
end

return FurnitureBuilder
