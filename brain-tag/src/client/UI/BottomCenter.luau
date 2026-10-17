-- Bottom-center: a context hint ("Press E to pick up Bat"), the inventory
-- (3 slots with 3D previews; the gold one is in your hand), and the
-- "Immunity 0/100" bar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local InputController = require(script.Parent.Parent.InputController)
local ItemModels = require(ReplicatedStorage.Shared.ItemModels)
local Items = require(ReplicatedStorage.Shared.Items)
local UIKit = require(script.Parent.UIKit)
local Util = require(ReplicatedStorage.Shared.Util)

local BottomCenter = {}

-- " x3" for peels, " 60%" for a water tank, "" for everything else.
local function chargeText(item: Items.Item, charges: any): string
	if typeof(charges) ~= "number" or charges <= 0 or not item.charges then
		return ""
	end
	if item.kind == "Stream" then
		return string.format(" %d%%", math.ceil(charges / item.charges * 100))
	end
	return " x" .. charges
end

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

	-- The inventory: one box per slot, the one in your hand outlined in gold.
	-- Click a box (or press 1-3) to switch.
	local row = UIKit.new("Frame", {
		Name = "Inventory",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(Config.INVENTORY_SLOTS * 80, 72),
		BackgroundTransparency = 1,
		Parent = column,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	type SlotView = { box: Frame, stroke: UIStroke, name: TextLabel, shown: string?, preview: ViewportFrame? }
	local views: { SlotView } = {}
	for i = 1, Config.INVENTORY_SLOTS do
		local stroke = UIKit.stroke(UIKit.WHITE, 2) :: UIStroke
		local box = UIKit.new("Frame", {
			Name = "Slot" .. i,
			LayoutOrder = i,
			Size = UDim2.fromOffset(72, 72),
			BackgroundColor3 = UIKit.PANEL,
			BackgroundTransparency = UIKit.PANEL_TRANSPARENCY,
			BorderSizePixel = 0,
			Parent = row,
		}, { UIKit.corner(10), stroke })
		local number = UIKit.label({
			Name = "Number",
			Text = tostring(i),
			Position = UDim2.fromOffset(5, 2),
			Size = UDim2.fromOffset(16, 16),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
			Parent = box,
		})
		UIKit.textStroke(1).Parent = number
		local name = UIKit.label({
			Name = "ItemName",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -2),
			Size = UDim2.new(1, -4, 0, 14),
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 3,
			Parent = box,
		})
		UIKit.textStroke(1).Parent = name
		UIKit.new("TextButton", {
			Name = "Pick",
			Text = "",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = box,
		}).Activated
			:Connect(function()
				InputController.selectSlot(i)
			end)
		table.insert(views, { box = box, stroke = stroke, name = name, shown = nil, preview = nil })
	end

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

	return function()
		local active = ClientState.my("ActiveSlot") or 1
		for i, view in views do
			local raw = ClientState.my("Slot" .. i)
			local id = if typeof(raw) == "string" and raw ~= "" then raw else nil
			if id ~= view.shown then
				view.shown = id
				if view.preview then
					view.preview:Destroy()
					view.preview = nil
				end
				if id then
					view.preview = UIKit.viewport(view.box, ItemModels.build(id), { ZIndex = 2 })
				end
			end
			local slotItem = Items.get(id)
			view.name.Text = if slotItem
				then slotItem.name .. chargeText(slotItem, ClientState.my("Slot" .. i .. "Charges"))
				else ""
			local isActive = i == active
			view.stroke.Color = if isActive then UIKit.GOLD else UIKit.WHITE
			view.stroke.Thickness = if isActive then 3 else 1.5
			view.stroke.Transparency = if isActive then 0 else 0.5
		end
		local held = ClientState.my("HeldItem")
		local item = Items.get(if typeof(held) == "string" and held ~= "" then held else nil)

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
				elseif item and keys then
					local verb = if item.kind == "Stream"
						then "[Hold click] spray"
						elseif item.kind == "Trap" then "[Click] drop one"
						elseif item.kind == "Melee" and item.hits then "[Click] swing  - hold it out to block"
						elseif item.kind == "Melee" then "Hold it toward zombies to keep them back"
						else "[Click] use"
					text = verb .. "   [G] drop   [1-3] switch"
				end
			end
		end
		hint.Text = text
	end
end

return BottomCenter
