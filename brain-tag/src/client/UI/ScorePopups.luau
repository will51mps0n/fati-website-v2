-- Little "+10" numbers that float up from your character whenever your
-- points change (survival points every few seconds, eating someone,
-- rewards), only on your screen. Losses float up in red.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local UIKit = require(script.Parent.UIKit)
local Util = require(ReplicatedStorage.Shared.Util)

local ScorePopups = {}

local player = Players.LocalPlayer
local RISE = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.8)
local LOSS = Color3.fromHex(Config.COLORS.ZombieText)

local random = Random.new()

local function pop(amount: number)
	local _, root = ClientState.myCharacter()
	if not root then
		return
	end
	local board = UIKit.new("BillboardGui", {
		Name = "ScorePopup",
		Adornee = root,
		Size = UDim2.fromOffset(160, 120),
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local x = random:NextInteger(-18, 18)
	local label = UIKit.label({
		Text = (if amount > 0 then "+" else "-") .. Util.commas(math.abs(amount)),
		Font = UIKit.HEAVY,
		TextSize = if math.abs(amount) >= 100 then 30 else 24,
		TextColor3 = if amount > 0 then UIKit.LIME else LOSS,
		TextStrokeTransparency = 0.25,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, x, 0.5, -14),
		Size = UDim2.new(1, 0, 0, 32),
		Parent = board,
	})
	TweenService:Create(label, RISE, { Position = UDim2.new(0.5, x, 0, 32) }):Play()
	TweenService:Create(label, FADE, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.5, function()
		board:Destroy()
	end)
end

function ScorePopups.start()
	task.spawn(function()
		local me = ClientState.participants:WaitForChild(ClientState.myId(), 120)
		if not me then
			return
		end
		local last = (me:GetAttribute("Score") :: number?) or 0
		local pending = 0
		me:GetAttributeChangedSignal("Score"):Connect(function()
			local value = (me:GetAttribute("Score") :: number?) or 0
			local change = value - last
			last = value
			if change == 0 then
				return
			end
			-- Changes in the same moment (a reward and its bonus) show as one.
			if pending == 0 then
				task.delay(0.05, function()
					local total = pending
					pending = 0
					if total ~= 0 then
						pop(total)
					end
				end)
			end
			pending += change
		end)
	end)
end

return ScorePopups
