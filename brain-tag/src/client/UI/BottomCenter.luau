-- Bottom-center: a context hint ("Press E to pick up Bat"), the single item
-- slot with a 3D preview of what you hold, and the "Immunity 0/100" bar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local ItemModels = require(ReplicatedStorage.Shared.ItemModels)
local Items = require(ReplicatedStorage.Shared.Items)
local UIKit = require(script.Parent.UIKit)
local Util = require(ReplicatedStorage.Shared.Util)

local BottomCenter = {}

local function nearestGroundItem(position: Vector3): string?
	local folder = workspace:FindFirstChild("GroundItems")
	if not folder then
		return nil
	end
	local best: string? = nil
	local bestDistance = Config.PICKUP_RADIUS
	for _, model in folder:GetChildren() do
		local x, z = model:GetAttribute("SpotX"), model:GetAttribute("SpotZ")
		if typeof(x) == "number" and typeof(z) == "number" then
			local d = Util.flatDistance(Vector3.new(x, 0, z), position)
			if d <= bestDistance then
				best, bestDistance = model:GetAttribute("ItemId") :: string?, d
			end
		end
	end
	return best
end

function BottomCenter.wizardNear(position: Vector3): boolean
	local wizard = workspace:FindFirstChild("Wizard")
	local robe = wizard and wizard:FindFirstChild("Robe") :: BasePart?
	return robe ~= nil and Util.flatDistance(robe.Position, position) <= Config.WIZARD_SHOP_RADIUS
end

function BottomCenter.build(parent: Instance, touchMode: boolean): () -> ()
	local column = UIKit.new("Frame", {
		Name = "BottomCenter",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(300, 150),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		UIKit.list(
			Enum.FillDirection.Vertical,
			6,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Bottom
		),
	})

	local hint = UIKit.label({
		Name = "Hint",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(300, 22),
		TextSize = 17,
		Parent = column,
	})
	UIKit.textStroke(1.5).Parent = hint

	local slot = UIKit.new("Frame", {
		Name = "Slot",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = UIKit.PANEL,
		BackgroundTransparency = UIKit.PANEL_TRANSPARENCY,
		BorderSizePixel = 0,
		Parent = column,
	}, { UIKit.corner(10), UIKit.stroke(UIKit.WHITE, 2) })
	local itemName = UIKit.label({
		Name = "ItemName",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, -4, 0, 14),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
		Parent = slot,
	})
	UIKit.textStroke(1).Parent = itemName

	local bar = UIKit.new("Frame", {
		Name = "Immunity",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(200, 18),
		BackgroundColor3 = Color3.fromRGB(40, 40, 44),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = column,
	}, { UIKit.corner(9) })
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(94, 196, 255),
		BorderSizePixel = 0,
		Parent = bar,
	}, { UIKit.corner(9) })
	local barText = UIKit.label({
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		TextSize = 13,
		ZIndex = 2,
		Parent = bar,
	})
	UIKit.textStroke(1).Parent = barText

	local shownItem: string? = nil
	local preview: ViewportFrame? = nil

	return function()
		local held = ClientState.my("HeldItem")
		local itemId = if typeof(held) == "string" and held ~= "" then held else nil
		if itemId ~= shownItem then
			shownItem = itemId
			if preview then
				preview:Destroy()
				preview = nil
			end
			if itemId then
				preview = UIKit.viewport(slot, ItemModels.build(itemId), { ZIndex = 2 })
			end
			local item = Items.get(itemId)
			itemName.Text = if item then item.name else ""
		end

		local immunity = ClientState.my("Immunity") or 0
		fill.Size = UDim2.fromScale(math.clamp(immunity / Config.IMMUNITY_MAX, 0, 1), 1)
		barText.Text = string.format("Immunity  %d/%d", immunity, Config.IMMUNITY_MAX)

		local _, root = ClientState.myCharacter()
		local text = ""
		local keys = not touchMode
		if root then
			if ClientState.isZombie() then
				if ClientState.phase() == "Infection" then
					text = if keys then "[Z] back to spawn" else ""
				end
			else
				local ground = nearestGroundItem(root.Position)
				local groundItem = Items.get(ground)
				if BottomCenter.wizardNear(root.Position) then
					text = if keys
						then "Press [B] to trade with the wizard"
						else "Tap SHOP to trade with the wizard"
				elseif groundItem then
					text = (if keys then "Press [E] to pick up " else "Tap PICK UP: ") .. groundItem.name
				elseif itemId and keys then
					text = "[Click] use   [G] drop"
				end
			end
		end
		hint.Text = text
	end
end

return BottomCenter
