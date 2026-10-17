-- Bottom-left: your points, the speed boost and size they give you, and
-- anything changing your speed right now (energy drink, freeze, stun).
-- Plus a 2x score timer when one is running.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local UIKit = require(script.Parent.UIKit)
local Util = require(ReplicatedStorage.Shared.Util)

local BottomLeft = {}

local ICE = Color3.fromHex("8FD3FF")

function BottomLeft.build(parent: Instance): () -> ()
	local box = UIKit.panel({
		Name = "ScoreBox",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, { UIKit.padding(12, 8), UIKit.list(Enum.FillDirection.Vertical, 2) })
	local function line(name: string, order: number, height: number, props: { [string]: any }?): TextLabel
		local label = UIKit.label({
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, height),
			TextSize = height - 2,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = box,
		})
		local extra: { [string]: any } = props or {}
		for key, value in extra do
			(label :: any)[key] = value
		end
		return label
	end
	local points = line("Points", 1, 24, { Font = UIKit.HEAVY })
	local speed = line("Speed", 2, 18)
	local size = line("Size", 3, 18)
	local effect = line("Effect", 4, 16, { Visible = false })
	local boost = line("Boost", 5, 16, { TextColor3 = UIKit.GOLD, Visible = false })

	return function()
		local value = ClientState.my("Score") or 0
		points.Text = "Points: " .. Util.commas(value)
		local multiplier = Config.SPEED_MULTIPLIER(value)
		speed.Text = string.format("Speed boost: +%d%%", math.floor((multiplier - 1) * 100 + 0.5))
		size.Text = string.format("Size: %.2fx", ClientState.my("Scale") or 1)

		-- Compare your real walk speed with what your points alone give you.
		local _, _, humanoid = ClientState.myCharacter()
		local expected = RoundRules.walkSpeed(value, ClientState.isZombie())
		local ratio = if humanoid and expected > 0 then humanoid.WalkSpeed / expected else 1
		effect.Visible = math.abs(ratio - 1) > 0.03
		if ratio < 0.01 then
			effect.Text = "Stunned!"
			effect.TextColor3 = ICE
		elseif ratio > 1 then
			effect.Text = string.format("Speed right now: x%.2f", ratio)
			effect.TextColor3 = UIKit.GOLD
		else
			effect.Text = string.format("Slowed: x%.2f", ratio)
			effect.TextColor3 = ICE
		end

		local endsAt = ClientState.my("BoostEndsAt")
		local left = if typeof(endsAt) == "number" then endsAt - workspace:GetServerTimeNow() else 0
		boost.Visible = left > 0
		if left > 0 then
			boost.Text = "2x score  " .. Util.clock(left)
		end
	end
end

return BottomLeft
