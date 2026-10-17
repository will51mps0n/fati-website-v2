-- The wizard: shows up at a random moment during the prep phase in one of the
-- yards, sells rare items to humans standing within reach (press B near
-- him), and leaves when the outbreak starts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Announcer = require(script.Parent.Announcer)
local Config = require(ReplicatedStorage.Shared.Config)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Parts = require(ReplicatedStorage.Shared.Parts)
local Util = require(ReplicatedStorage.Shared.Util)

local Wizard = {}

local model: Model? = nil
local scheduleToken = 0
local rng = Random.new()

local function build(at: Vector3): Model
	local m = Instance.new("Model")
	m.Name = "Wizard"
	local function disc(name: string, offset: Vector3, diameter: number, height: number, color: string): Part
		return Parts.disc(name, at + offset, diameter, height, color, m)
	end
	-- Like the original: a blue robe, a big brown pointy hat, a grey beard.
	disc("RobeOutline", Vector3.new(0, 1.95, 0), 4.3, 3.9, "2C5866")
	local robe = disc("Robe", Vector3.new(0, 2, 0), 3.9, 4, "4F8FA3")
	disc("RobeTrim", Vector3.new(0, 4.03, 0), 3.1, 0.06, "6FB0C2")
	disc("HatBrimOutline", Vector3.new(0, 4.55, 0), 3.7, 0.3, "4A2C17")
	disc("HatBrim", Vector3.new(0, 4.6, 0), 3.4, 0.3, "6B4226")
	disc("HatMid", Vector3.new(0, 5.1, 0), 2.2, 0.7, "8B5A2B")
	disc("HatTip", Vector3.new(0, 5.6, 0), 0.9, 0.3, "A0703F")
	disc("Star", Vector3.new(0.5, 5.5, 0.3), 0.5, 0.25, "FFD54A")
	disc("Beard", Vector3.new(0, 4.3, -1.6), 1.4, 0.3, "B8BEC4")
	-- Staff with a glowing orb.
	Parts.make({
		name = "Staff",
		size = Vector3.new(0.35, 0.35, 4.5),
		cframe = CFrame.new(at + Vector3.new(1.9, 4.4, -0.6)),
		color = "8B5A2B",
		canCollide = false,
		parent = m,
	})
	local orb = Parts.make({
		name = "Orb",
		shape = Enum.PartType.Ball,
		size = Vector3.one * 1.1,
		cframe = CFrame.new(at + Vector3.new(1.9, 4.7, -3.0)),
		color = "7FE7FF",
		material = Enum.Material.Neon,
		canCollide = false,
		parent = m,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("7FE7FF")
	light.Range = 10
	light.Brightness = 2
	light.Parent = orb
	m.PrimaryPart = robe

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(240, 44)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.StudsOffsetWorldSpace = Vector3.new(0, 2, -4.2)
	tag.Adornee = robe
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.BuilderSansExtraBold
	label.TextSize = 18
	label.TextColor3 = Color3.fromHex("D7B8FF")
	label.TextStrokeTransparency = 0.3
	label.Text = "Wizard\n[B] special items"
	label.Parent = tag
	tag.Parent = robe
	return m
end

function Wizard.arrive()
	if model then
		return
	end
	local spots = MapLayout.current().wizardSpots
	local spot = spots[rng:NextInteger(1, #spots)]
	local m = build(Vector3.new(spot.x, 0, spot.z))
	m.Parent = workspace
	model = m
	local state = ReplicatedStorage:FindFirstChild("BrainTagState")
	if state then
		state:SetAttribute("WizardHere", true)
	end
	Announcer.chat("* The wizard has arrived! Press [B] at wizard to buy special items! *")
	Announcer.fx("Wizard", { position = Vector3.new(spot.x, 2, spot.z) })
end

function Wizard.leave()
	scheduleToken += 1
	if model then
		model:Destroy()
		model = nil
		Announcer.chat("* The wizard vanished in a puff of smoke. *")
	end
	local state = ReplicatedStorage:FindFirstChild("BrainTagState")
	if state then
		state:SetAttribute("WizardHere", false)
	end
end

-- Arrives after a random delay inside the configured window, unless leave()
-- is called first.
function Wizard.schedule()
	scheduleToken += 1
	local token = scheduleToken
	task.delay(rng:NextNumber(Config.WIZARD_ARRIVE_MIN, Config.WIZARD_ARRIVE_MAX), function()
		if token == scheduleToken then
			Wizard.arrive()
		end
	end)
end

function Wizard.isNear(position: Vector3): boolean
	local current = model
	if not current or not current.PrimaryPart then
		return false
	end
	return Util.flatDistance(current.PrimaryPart.Position, position) <= Config.WIZARD_SHOP_RADIUS
end

return Wizard
