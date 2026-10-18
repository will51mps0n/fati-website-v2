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
				c:top(side * (c.w / 4 - 0.2), 0.45, c.w / 2 - 1.8, 0.12, 0.17, 0.2, "4A93C2") -- cushion seam
			end
			c:top(c.w / 2 - 1.6, -0.2, 1.2, 1.0, 0.35, 0.3, "F1C40F", 0.3) -- throw pillow
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
			c:disc(-0.9, 0.6, 0.4, 0.05, 0.06, "E5484D") -- fridge magnets
			c:disc(-0.3, 0.9, 0.35, 0.05, 0.06, "3498DB")
			c:top(0.6, 0.7, 0.6, 0.45, 0.05, 0.06, "FFE14D", 0.2) -- a note
		end,
	},
	Stove = {
		body = "E6E6E6",
		draw = function(c)
			c:top(0, -c.d / 2 + 0.3, c.w, 0.6, 0.35, 0.4, "BDBDBD") -- control strip
			for i = -1, 1 do
				c:disc(i * 1.1, -c.d / 2 + 0.3, 0.3, 0.42, 0.08, "333333") -- knobs
			end
			c:disc(0.9, 0.95, 0.95, 0.5, 0.5, "7F8C8D") -- a pot on the front burner
			c:disc(0.9, 0.95, 0.75, 0.52, 0.5, "C0392B")
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
			c:disc(c.w / 2 + 0.2, -c.d / 2 + 0.6, 0.7, -0.4, 0.5, "FFFFFF") -- paper roll
		end,
	},
	Bathtub = {
		body = "F4F7FA",
		draw = function(c)
			c:top(0, 0, c.w - 1.0, c.d - 1.0, 0.03, 0.06, "A9D6F0")
			c:top(c.w / 2 - 0.4, 0, 0.4, 0.5, 0.3, 0.3, "8A939C") -- tap
			c:ball(-1.5, c.h / 2 + 0.15, 0.3, 0.6, "FFD93B") -- rubber duck
			c:ball(-1.25, c.h / 2 + 0.35, 0.3, 0.35, "FFD93B")
			c:top(-1.0, 0.3, 0.2, 0.15, 0.4, 0.1, "F28C1C")
			for i = 1, 4 do
				c:disc(1.6 - i * 0.5, -0.6 + (i % 2) * 0.4, 0.35, 0.08, 0.06, "FFFFFF") -- bubbles
			end
		end,
	},
	Bed = {
		body = "8E5A32",
		draw = function(c)
			c:top(0, -c.d / 2 + 0.25, c.w, 0.5, 0.6, 0.7, "6B4226") -- headboard
			c:top(0, 0.1, c.w - 0.6, c.d - 0.8, 0.2, 0.3, "F5F5F5") -- mattress
			c:top(0, c.d * 0.18, c.w - 0.5, c.d * 0.6, 0.3, 0.35, "2FA84F") -- blanket (green, like the original)
			c:top(0, c.d * 0.18 - c.d * 0.3 + 0.2, c.w - 0.5, 0.4, 0.32, 0.36, "F2F2F2") -- folded sheet
			for side = -1, 1, 2 do
				c:top(side * 1.55, -c.d / 2 + 1.3, 2.6, 1.4, 0.45, 0.4, "FFFFFF") -- pillows
			end
			for row = 0, 2 do
				for col = -1, 1, 2 do
					c:top(col * 1.5, c.d * 0.02 + row * 1.6, 2.4, 0.06, 0.32, 0.36, "27924A") -- quilt lines
				end
			end
			c:ball(1.6, c.h / 2 + 0.55, -c.d / 2 + 2.6, 0.9, "A0582A") -- teddy bear
			c:ball(1.6, c.h / 2 + 0.75, -c.d / 2 + 2.05, 0.6, "A0582A")
		end,
	},
	Table = {
		body = "B07A45",
		draw = function(c)
			c:top(0, 0, c.w - 0.6, c.d - 0.6, 0.02, 0.04, "C08A55")
			for _, x in { -2.3, 0, 2.3 } do
				c:disc(x, 0, 1.3, 0.06, 0.06, "F4F4F4") -- plates
				c:disc(x, 0, 0.7, 0.08, 0.06, "E8E8E8")
			end
			c:disc(-1.2, 1.4, 0.45, 0.1, 0.1, "3498DB") -- cups
			c:disc(1.2, -1.4, 0.45, 0.1, 0.1, "E5484D")
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
			c:top(0, 0.2, c.w - 0.6, c.d - 0.9, 0.05, 0.06, "C0392B") -- seat cushion
		end,
	},
	Bookshelf = {
		body = "6B4226",
		draw = function(c)
			local count = 11
			local span = c.w - 0.6
			for i = 1, count do
				local x = -span / 2 + (i - 0.5) * span / count
				local depth = c.d - 0.7 - (i % 3) * 0.2 -- books of different sizes
				local raise = 0.04 + (i % 2) * 0.03
				c:top(
					x,
					0.15,
					span / count - 0.12,
					depth,
					raise,
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
			c:top(0.75, 0.75, 0.7, 0.45, 0.03, 0.04, "F4F4F4") -- shipping label
		end,
	},
	-- Wooden crate with a diagonal brace, like the original's.
	Crate = {
		body = "C8955A",
		draw = function(c)
			local t = 0.4
			c:top(0, -c.d / 2 + t / 2, c.w, t, 0.03, 0.06, "8E5F33")
			c:top(0, c.d / 2 - t / 2, c.w, t, 0.03, 0.06, "8E5F33")
			c:top(-c.w / 2 + t / 2, 0, t, c.d, 0.03, 0.06, "8E5F33")
			c:top(c.w / 2 - t / 2, 0, t, c.d, 0.03, 0.06, "8E5F33")
			c:top(0, 0, (c.w - t) * 1.3, t, 0.03, 0.06, "8E5F33", math.rad(45))
		end,
	},
	SmallBox = {
		body = "D4AE78",
		draw = function(c)
			c:top(0, 0, 0.4, c.d, 0.02, 0.04, "EAD7AE") -- tape
			c:top(0, 0, c.w, 0.06, 0.02, 0.04, "A88350") -- flap seam
		end,
	},
	-- Two cardboard boxes side by side, a third one on top.
	BoxStack = {
		body = "C9A06A",
		draw = function(c)
			c:top(0, 0, 0.1, c.d, 0.02, 0.04, "A88350") -- gap between the bottom two
			c:top(-c.w / 4, 0, 0.45, c.d, 0.02, 0.04, "E6CFA1") -- their tape
			c:top(c.w / 5, 0.1, c.w * 0.55, c.d - 0.3, 1.5, 1.5, "D9B57E") -- the box on top
			c:top(c.w / 5, 0.1, 0.45, c.d - 0.3, 1.52, 0.04, "EFE0BD") -- its tape
			c:top(c.w / 5 + 0.7, 0.55, 0.7, 0.45, 1.53, 0.04, "F4F4F4") -- shipping label
		end,
	},
	-- A long shipping crate: planks along its length, battens across.
	LongCrate = {
		body = "B98550",
		draw = function(c)
			local t = 0.4
			for _, z in { -c.d / 2 + t / 2, 0, c.d / 2 - t / 2 } do
				c:top(0, z, c.w, t, 0.03, 0.06, "8E5F33")
			end
			for _, x in { -c.w / 2 + t / 2, -c.w / 6, c.w / 6, c.w / 2 - t / 2 } do
				c:top(x, 0, t, c.d, 0.05, 0.06, "7A5029")
			end
		end,
	},
	-- A big, heavy crate: a frame, an X brace and a stenciled stripe.
	BigCrate = {
		body = "A8733F",
		draw = function(c)
			local t = 0.55
			c:top(0, -c.d / 2 + t / 2, c.w, t, 0.03, 0.06, "6E4824")
			c:top(0, c.d / 2 - t / 2, c.w, t, 0.03, 0.06, "6E4824")
			c:top(-c.w / 2 + t / 2, 0, t, c.d, 0.03, 0.06, "6E4824")
			c:top(c.w / 2 - t / 2, 0, t, c.d, 0.03, 0.06, "6E4824")
			c:top(0, 0, (c.w - t) * 1.35, t, 0.05, 0.06, "6E4824", math.rad(45))
			c:top(0, 0, (c.w - t) * 1.35, t, 0.05, 0.06, "6E4824", math.rad(-45))
			c:top(0, c.d / 2 - 1.1, 2.2, 0.35, 0.07, 0.04, "2E2E2E") -- stencil
		end,
	},
	Barrel = {
		body = "8B5A2B",
		transparentBody = true,
		draw = function(c)
			c:disc(0, 0, c.w, -0.05, c.h - 0.1, "8B5A2B")
			c:disc(0, 0, c.w * 0.82, 0.01, 0.06, "A0703F")
			c:disc(0, 0, c.w * 0.3, 0.03, 0.06, "6B4226")
		end,
	},
	Wardrobe = {
		body = "7A4A2A",
		draw = function(c)
			c:top(0, 0, c.w - 0.5, c.d - 0.5, 0.02, 0.04, "8E5A32")
			c:top(0, 0, 0.12, c.d - 0.5, 0.04, 0.06, "5A3520") -- door split
		end,
	},
	Piano = {
		body = "222222",
		draw = function(c)
			c:top(0, c.d / 2 - 0.55, c.w - 0.6, 0.9, 0.04, 0.06, "F4F4F4") -- keys
			for i = 1, 9 do
				local x = -c.w / 2 + 0.3 + (c.w - 0.6) * (i / 10)
				c:top(x, c.d / 2 - 0.75, 0.18, 0.5, 0.07, 0.06, "111111") -- black keys
			end
			c:top(0, -0.6, c.w - 1.2, 1.6, 0.03, 0.06, "333333") -- lid
		end,
	},
	PoolTable = {
		body = "6B4226",
		draw = function(c)
			c:top(0, 0, c.w - 1.2, c.d - 1.2, 0.03, 0.06, "2E8B57") -- felt
			for _, x in { -1, 0, 1 } do
				for _, z in { -1, 1 } do
					c:disc(x * (c.w / 2 - 0.6), z * (c.d / 2 - 0.6), 0.6, 0.06, 0.06, "111111") -- pockets
				end
			end
			c:disc(-2, 0, 0.45, 0.1, 0.1, "FFFFFF")
			c:disc(1.5, 0.4, 0.45, 0.1, 0.1, "E5484D")
			c:disc(2, -0.5, 0.45, 0.1, 0.1, "F2C230")
		end,
	},
	-- A big yellow supercar: tapered nose, black glass with shiny streaks,
	-- wing mirrors, a vented engine cover and a black tail (nose toward -Z).
	Car = {
		body = "F5C518",
		transparentBody = true,
		draw = function(c)
			local yellow, edge, black = "F5C518", "B8860B", "151515"
			c:top(0, 1.0, c.w, c.d - 2.2, -0.6, c.h - 0.8, edge) -- outline
			c:top(0, 1.0, c.w - 0.6, c.d - 3.0, -0.4, c.h - 0.6, yellow) -- hull
			c:top(0, -6.4, 6.8, 3.2, -0.65, c.h - 1.1, edge) -- nose outline
			c:top(0, -6.6, 6.2, 2.6, -0.6, c.h - 1.0, yellow) -- nose
			for side = -1, 1, 2 do
				c:top(side * 2.9, -6.0, 2.2, 2.6, -0.6, c.h - 1.0, yellow, side * 0.45) -- nose corners
				c:top(side * 2.6, -7.1, 1.4, 0.7, -0.55, 0.1, black, side * 0.4) -- front intakes
				c:top(side * 2.6, -2.6, 1.2, 2.6, 0, 0.4, black, side * 0.35) -- windshield corners
				c:top(side * 2.75, 0.4, 0.5, 4.4, 0, 0.3, black) -- side windows
				local shine = c:top(side * 2.75, -0.2, 0.12, 1.6, 0.02, 0.05, "FFFFFF")
				shine.Transparency = 0.4
				c:top(side * 4.7, -2.6, 1.4, 0.55, -0.5, 0.3, black, side * 0.45) -- wing mirrors
				c:top(side * 3.6, 2.6, 0.7, 2.4, -0.3, 0.1, black) -- side intakes
				c:top(side * 3.0, 4.6, 2.6, 4.2, -0.2, 0.3, yellow, side * 0.12) -- rear haunches
				c:top(side * 2.6, 7.55, 1.8, 0.3, -0.35, 0.1, "C0392B") -- tail lights
				for _, z in { -4.4, 4.6 } do
					c:top(side * 4.35, z, 0.6, 2.5, -1.6, 1.0, black) -- tyres peeking out
				end
			end
			c:top(0, -2.4, 5.6, 3.0, 0, 0.4, black) -- windshield
			-- Shiny streaks across the glass.
			for _, streak in { { -0.9, 0.35, 0.3 }, { 0.4, 0.22, 0.45 }, { 1.5, 0.15, 0.6 } } do
				local part = c:top(streak[1], -2.4, streak[2], 3.2, 0.03, 0.05, "FFFFFF", 0.7)
				part.Transparency = streak[3]
			end
			c:top(0, 0.2, 5.0, 2.6, 0.05, 0.4, yellow) -- roof
			c:top(0, 3.6, 4.6, 3.4, -0.1, 0.3, black) -- engine cover
			for i = 0, 3 do
				c:top(0, 2.4 + i * 0.75, 3.6, 0.3, 0, 0.1, "5E5E5E") -- vents
			end
			c:disc(0, 3.6, 1.4, 0.02, 0.1, "7A7A7A")
			c:top(0, 7.4, 7.6, 1.2, -0.4, 0.4, black) -- tail
			for side = -1, 1, 2 do
				c:disc(side * 0.8, 7.7, 0.6, -0.3, 0.2, "9A9A9A") -- exhausts
			end
		end,
	},
	Dresser = {
		body = "8E5A32",
		draw = function(c)
			c:top(0, 0, c.w - 0.4, c.d - 0.4, 0.02, 0.04, "A0703F")
			c:disc(-1, 0.3, 0.7, 0.04, 0.06, "D9E0E6") -- mirror stand
			c:disc(1.2, 0.2, 0.5, 0.06, 0.06, "E8C26A")
		end,
	},
	Washer = {
		body = "E8ECEF",
		draw = function(c)
			c:disc(0, 0.2, 2.0, 0.03, 0.06, "B9C3CC") -- door rim
			c:disc(0, 0.2, 1.5, 0.05, 0.06, "7FB8E0") -- window
			c:top(0, -c.d / 2 + 0.3, c.w, 0.5, 0.06, 0.08, "C9D1D9") -- control strip
		end,
	},
	Desk = {
		body = "A0703F",
		draw = function(c)
			c:top(0, 0, c.w - 0.4, c.d - 0.4, 0.02, 0.04, "B88A55")
			c:top(-1.2, -0.3, 1.8, 1.2, 0.06, 0.08, "2B2B30") -- laptop
			c:top(1.4, 0.2, 1.2, 0.9, 0.05, 0.06, "F4F4F4") -- papers
		end,
	},
	TVStand = {
		body = "5A3A22",
		draw = function(c)
			c:top(0, -0.2, c.w - 0.8, 0.6, 0.15, 0.2, "1C1C20") -- TV
		end,
	},
	Bench = {
		body = "A0703F",
		draw = function(c)
			for i = -1, 1 do
				c:top(0, i * 0.6, c.w, 0.45, 0.02, 0.04, "B88A55") -- slats
			end
		end,
	},
	Lamp = {
		body = "F2E2A0",
		transparentBody = true,
		draw = function(c)
			c:disc(0, 0, 0.9, -c.h + 0.6, 0.3, "6B6B6B") -- base
			c:disc(0, 0, c.w, -0.2, 0.6, "F2E2A0") -- shade
			c:disc(0, 0, 0.5, 0.0, 0.06, "FFF8D6")
		end,
	},
	Plant = {
		body = "B5653A",
		transparentBody = true,
		draw = function(c)
			c:disc(0, 0, 2.0, -0.6, c.h - 0.6, "B5653A") -- pot
			c:disc(0, 0, 1.6, -0.55, 0.1, "5A3A22") -- soil
			for i = 0, 5 do
				local a = i / 6 * math.pi * 2 + 0.4
				local leaf = if i % 2 == 0 then "3E9B3A" else "4FB848"
				c:ball(math.cos(a) * 0.6, c.h / 2 + 0.1, math.sin(a) * 0.6, 1.0, leaf)
			end
			c:ball(0, c.h / 2 + 0.45, 0, 0.5, "F48FB1") -- a flower
			c:ball(0, c.h / 2 + 0.6, 0, 0.22, "FFE066")
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
	Beanbag = {
		body = "E74C3C",
		transparentBody = true,
		draw = function(c)
			c:disc(0, 0, c.w + 0.3, -0.25, c.h - 0.3, "A93226") -- outline
			c:disc(0, 0, c.w, -0.2, c.h - 0.3, "E74C3C")
			c:disc(0.3, 0.3, c.w * 0.55, -0.15, 0.1, "C0392B") -- the dent you sit in
		end,
	},
	TrashCan = {
		body = "7F8C8D",
		transparentBody = true,
		draw = function(c)
			c:disc(0, 0, c.w + 0.25, -0.1, c.h - 0.2, "4D5656")
			c:disc(0, 0, c.w, -0.05, c.h - 0.2, "95A5A6")
			c:disc(0, 0, c.w * 0.8, 0, 0.06, "7F8C8D") -- lid
			c:top(0, 0, c.w * 0.5, 0.25, 0.08, 0.1, "4D5656") -- handle
			c:top(0.5, 0.45, 0.6, 0.18, 0.12, 0.08, "F7DC6F", 0.6) -- a banana peel on top
		end,
	},
	Aquarium = {
		body = "7FC8F8",
		draw = function(c)
			c:top(0, 0, c.w - 0.4, c.d - 0.4, 0.02, 0.04, "4FA3D9") -- water
			c:top(0, c.d / 2 - 0.45, c.w - 0.5, 0.4, 0.03, 0.04, "E8D3A2") -- sand
			local fishes: { { x: number, z: number, color: string } } = {
				{ x = -1.6, z = -0.2, color = "F39C12" },
				{ x = 0.4, z = 0.3, color = "E74C3C" },
				{ x = 1.7, z = -0.4, color = "F1C40F" },
			}
			for i, fish in fishes do
				local x, z, color = fish.x, fish.z, fish.color
				c:top(x, z, 0.7, 0.35, 0.05 + i * 0.01, 0.04, color) -- fish
				c:top(x + 0.45, z, 0.25, 0.3, 0.05 + i * 0.01, 0.04, color, math.rad(45)) -- tails
			end
			c:top(-2.3, 0.6, 0.15, 0.8, 0.04, 0.05, "27AE60") -- seaweed
			c:disc(2.4, 0.5, 0.25, 0.07, 0.04, "FFFFFF") -- bubbles
			c:disc(2.2, 0.1, 0.18, 0.07, 0.04, "FFFFFF")
		end,
	},
	Arcade = {
		body = "6C3483",
		draw = function(c)
			c:top(0, -0.35, c.w - 0.6, 1.4, 0.04, 0.06, "111111") -- screen
			for i, color in { "E74C3C", "F1C40F", "2ECC71", "3498DB" } do
				c:top(-0.9 + i * 0.36, -0.35 + (i % 2) * 0.3, 0.25, 0.25, 0.06, 0.04, color) -- pixels
			end
			c:disc(-0.6, 0.85, 0.45, 0.2, 0.25, "E74C3C") -- joystick
			c:disc(0.4, 0.85, 0.3, 0.08, 0.08, "F1C40F") -- buttons
			c:disc(0.9, 0.85, 0.3, 0.08, 0.08, "3498DB")
		end,
	},
	VendingMachine = {
		body = "C0392B",
		draw = function(c)
			c:top(-0.4, 0, c.w - 1.6, c.d - 0.6, 0.03, 0.05, "B3E5FC") -- glass
			local colors = { "E74C3C", "3498DB", "2ECC71", "F1C40F", "9B59B6", "E67E22" }
			for row = 0, 2 do
				for col = 0, 2 do
					c:disc(
						-1.5 + col * 0.8,
						-0.8 + row * 0.8,
						0.45,
						0.06,
						0.04,
						colors[(row * 3 + col) % #colors + 1]
					) -- cans
				end
			end
			c:top(c.w / 2 - 0.55, -0.4, 0.5, 0.9, 0.05, 0.06, "2B2B30") -- coin slot panel
			c:top(c.w / 2 - 0.55, 0.6, 0.5, 0.25, 0.06, 0.06, "F1C40F")
		end,
	},
	Treadmill = {
		body = "3A3A3A",
		draw = function(c)
			c:top(0, 0.4, c.w - 0.8, c.d - 1.6, 0.02, 0.04, "222222") -- belt
			for i = -2, 2 do
				c:top(0, 0.4 + i * 1.1, c.w - 0.9, 0.06, 0.04, 0.03, "4A4A4A") -- belt slats
			end
			c:top(0, -c.d / 2 + 0.4, c.w, 0.8, 0.5, 0.5, "5D6D7E") -- console
			c:top(0, -c.d / 2 + 0.4, 1.0, 0.4, 0.52, 0.5, "2ECC71") -- display
		end,
	},
	-- Haunted house ---------------------------------------------------------------
	Tombstone = {
		body = "7F858C",
		draw = function(c)
			c:top(0, 0, c.w - 0.35, c.d - 0.35, 0.02, 0.04, "989EA5")
			c:top(0, 0, 0.28, c.d - 0.7, 0.05, 0.04, "5C6167") -- engraved cross
			c:top(0, -0.05, 1.3, 0.24, 0.05, 0.04, "5C6167")
			c:disc(c.w / 2 - 0.6, 0.2, 0.55, 0.06, 0.04, "5E7A4A") -- moss
		end,
	},
	Coffin = {
		body = "3F271D",
		draw = function(c)
			c:top(0, 0, c.w - 0.45, c.d - 0.45, 0.03, 0.06, "57362A") -- lid
			c:top(0, -c.d / 2 + 2.2, 0.3, 2.4, 0.06, 0.05, "C9A35A") -- brass cross
			c:top(0, -c.d / 2 + 1.7, 1.4, 0.3, 0.06, 0.05, "C9A35A")
			for side = -1, 1, 2 do
				c:top(side * (c.w / 2 + 0.08), 0, 0.16, 1.4, -0.6, 0.25, "8C7A55") -- handles
			end
		end,
	},
	Candelabra = {
		body = "2E2626",
		transparentBody = true,
		draw = function(c)
			c:disc(0, 0, c.w, -c.h + 0.3, 0.3, "2E2626") -- base
			c:disc(0, 0, 0.3, -0.5, c.h - 0.8, "2E2626") -- stem
			c:top(0, 0, c.w + 0.4, 0.2, -0.45, 0.15, "2E2626") -- arms
			for _, x in { -0.9, 0, 0.9 } do
				c:disc(x, 0, 0.32, 0, 0.5, "F2E8D0") -- candles
				c:ball(x, c.h / 2 + 0.2, 0, 0.32, "FFB347").Material = Enum.Material.Neon -- flames
			end
			local light = Instance.new("PointLight")
			light.Range = 18
			light.Brightness = 1.6
			light.Color = Color3.fromHex("FFC27A")
			-- No shadows: Roblox draws only a few shadow-casting lights at a
			-- time, and dozens of candles would crowd out your own lantern.
			light.Shadows = false
			light.Parent = c.body
		end,
	},
	Cauldron = {
		body = "26262B",
		transparentBody = true,
		draw = function(c)
			c:disc(0, 0, c.w, -0.05, c.h - 0.1, "26262B")
			c:disc(0, 0, c.w * 0.8, 0.0, 0.06, "4FC24F").Material = Enum.Material.Neon -- brew
			c:disc(-0.5, 0.3, 0.6, 0.03, 0.06, "9BF59B")
			c:disc(0.6, -0.4, 0.45, 0.03, 0.06, "9BF59B")
		end,
	},
	Pumpkin = {
		body = "E8761E",
		transparentBody = true,
		draw = function(c)
			c:disc(0, 0, c.w, -0.05, c.h - 0.1, "E8761E")
			for k = 0, 3 do
				c:top(0, 0, c.w * 0.92, 0.12, 0.0, 0.04, "C45C12", k * math.pi / 4) -- ribs
			end
			c:disc(0, 0, 0.45, 0.25, 0.4, "5B7A2E") -- stem
		end,
	},
	JackOLantern = {
		body = "E8761E",
		transparentBody = true,
		draw = function(c)
			c:disc(0, 0, c.w, -0.05, c.h - 0.1, "E2701A")
			c:disc(0, -0.1, c.w * 0.86, 0.0, 0.04, "D86514")
			-- The carved face, glowing (forehead toward the back, mouth to the front).
			local glow = "FFD24A"
			for side = -1, 1, 2 do
				c:top(side * 0.5, -0.35, 0.42, 0.42, 0.03, 0.04, glow, math.rad(45)).Material =
					Enum.Material.Neon
			end
			c:top(0, 0.05, 0.22, 0.22, 0.03, 0.04, glow, math.rad(45)).Material = Enum.Material.Neon
			c:top(0, 0.5, 1.2, 0.22, 0.03, 0.04, glow).Material = Enum.Material.Neon
			for _, x in { -0.4, 0, 0.4 } do
				c:top(x, 0.42, 0.16, 0.14, 0.035, 0.04, "D86514") -- teeth
			end
			c:disc(0, -c.d / 2 + 0.55, 0.4, 0.25, 0.4, "5B7A2E") -- stem
			local light = Instance.new("PointLight")
			light.Range = 12
			light.Brightness = 1.4
			light.Color = Color3.fromHex("FF9A3C")
			light.Shadows = false
			light.Parent = c.body
		end,
	},
	HayBale = {
		body = "D8B24C",
		draw = function(c)
			c:top(0, 0, c.w - 0.3, c.d - 0.3, 0.02, 0.04, "E2C062")
			for i = -2, 2 do
				c:top(i * 0.9, 0, 0.08, c.d - 0.5, 0.04, 0.03, "C29A38") -- straw
			end
			for side = -1, 1, 2 do
				c:top(side * c.w / 4, 0, 0.18, c.d + 0.04, 0.05, 0.04, "7A5B34") -- twine
			end
		end,
	},
	Scarecrow = {
		body = "8B6A43",
		transparentBody = true,
		draw = function(c)
			c:disc(0, 0, 0.3, -c.h + 0.5, c.h - 0.6, "6B4E2E") -- post
			c:top(0, 0, c.w, 0.32, -1.2, 0.3, "6B4E2E") -- arms
			c:top(0, 0.05, 1.6, 1.0, -1.6, 1.4, "8E3B2E") -- shirt
			for side = -1, 1, 2 do
				c:top(side * (c.w / 2 - 0.15), 0, 0.5, 0.5, -1.15, 0.2, "D8B24C") -- straw hands
			end
			c:disc(0, 0, 1.0, -0.45, 0.9, "D8B24C") -- sack head
			c:disc(0, 0, 1.7, -0.05, 0.12, "6B5232") -- hat brim
			c:disc(0, 0, 0.9, 0.25, 0.4, "5A4329") -- hat crown
		end,
	},
	-- Christmas Town --------------------------------------------------------------
	ChristmasTree = {
		body = "2E7D46",
		transparentBody = true,
		draw = function(c)
			c:disc(0, 0, 0.8, -c.h + 1.2, 1.2, "6B4226") -- trunk
			local layers = { { c.w, -c.h + 3.2 }, { c.w * 0.74, -2.6 }, { c.w * 0.46, -0.6 } }
			for i, layer in layers do
				c:disc(0, 0, layer[1], layer[2], 0.9, if i == 2 then "3A9455" else "2E7D46")
			end
			local ornaments = { "D8423F", "F5C542", "3B82F6", "F4F4F4", "D8423F", "F5C542" }
			for i, color in ornaments do
				local angle = i / #ornaments * math.pi * 2
				local r = if i % 2 == 0 then c.w * 0.4 else c.w * 0.28
				c:disc(math.cos(angle) * r, math.sin(angle) * r, 0.42, -2.6 + 0.05, 0.1, color)
			end
			c:ball(0, c.h / 2 + 0.1, 0, 0.8, "FFD54A").Material = Enum.Material.Neon -- star
		end,
	},
	Present = {
		body = "D8423F",
		draw = function(c)
			c:top(0, 0, 0.36, c.d, 0.02, 0.04, "F5C542") -- ribbon
			c:top(0, 0, c.w, 0.36, 0.02, 0.04, "F5C542")
			c:disc(0, 0, 0.7, 0.08, 0.1, "F5C542") -- bow
		end,
	},
	Snowman = {
		body = "F4F8FA",
		transparentBody = true,
		draw = function(c)
			local white = "F4F8FA"
			c:ball(0, -c.h / 2 + 1.5, 0, c.w, white)
			c:ball(0, -c.h / 2 + 3.6, 0, c.w * 0.72, white)
			c:ball(0, c.h / 2 - 1.0, 0, c.w * 0.5, white)
			c:disc(0, 0, 1.1, 0.5, 0.9, "1C1C1C") -- top hat
			c:disc(0, 0, 1.6, -0.35, 0.12, "1C1C1C") -- brim
			c:top(0, 1.0, 0.24, 0.8, -0.85, 0.24, "F28C28") -- carrot nose (front)
			for side = -1, 1, 2 do
				c:top(side * 2.0, 0, 1.6, 0.14, -2.6, 0.14, "6B4226", side * 0.4) -- stick arms
			end
		end,
	},
	-- Green rug with a pale border and a fringe on the short ends, like the original.
	Rug = {
		body = "A9C7B8",
		draw = function(c)
			c:top(0, 0, c.w - 0.8, c.d - 0.8, 0.02, 0.02, "2DB35A")
			c:top(0, 0, c.w - 1.6, c.d - 1.6, 0.04, 0.02, "34BF62")
			for i = 0, 11 do
				local z = -c.d / 2 + 0.5 + (c.d - 1) * i / 11
				for _, side in { -1, 1 } do
					c:top(side * (c.w / 2 + 0.25), z, 0.5, 0.08, 0.0, 0.02, "C9D9CF")
				end
			end
			c:disc(-c.w / 4, c.d / 5, 0.5, 0.06, 0.02, "1F8F45")
			c:disc(c.w / 4, -c.d / 5, 0.4, 0.06, 0.02, "1F8F45")
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

-- The piece's parts, posed at its spot (body first, no physics yet).
local function draw(spot: MapLayout.FurnitureSpot): (Model, Part, CFrame)
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

	if not design.transparentBody and not decor then
		-- A darker, slightly bigger copy just under the top: from above it
		-- draws the thick outline the original's furniture has.
		local base = Color3.fromHex(design.body)
		Parts.make({
			name = "Outline",
			size = Vector3.new(spec.w + 0.4, spec.h - 0.04, spec.d + 0.4),
			cframe = home * CFrame.new(0, -0.02, 0),
			color = Color3.new(base.R * 0.55, base.G * 0.55, base.B * 0.55),
			parent = model,
		})
	end
	return model, body, home
end

-- A still, anchored copy for editing maps in Studio (MapStudio). Its pivot
-- is the spot: move or turn it and the map follows.
function FurnitureBuilder.preview(spot: MapLayout.FurnitureSpot, parent: Instance): Model
	local model = draw(spot)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	model.Parent = parent
	return model
end

function FurnitureBuilder.build(spot: MapLayout.FurnitureSpot, parent: Instance): Built
	local spec = FurnitureSpecs.get(spot.kind)
	local decor = spec.decor == true
	local model, body, home = draw(spot)

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
	-- Low friction with weight 1: floors (friction 0, weight 100) let pieces
	-- glide at exactly the speed FurnitureService sets, while walls (friction
	-- 1, weight 100) grip them, so a barricade pressed into a doorway holds.
	body.CustomPhysicalProperties =
		PhysicalProperties.new(Config.FURNITURE_DENSITY[spec.weight], 0.3, 0, 1, 1)

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
	model:SetAttribute("OwnerUserId", 0)
	model.Parent = parent
	return { model = model, body = body, kind = spot.kind, weight = spec.weight, decor = false, home = home }
end

return FurnitureBuilder
