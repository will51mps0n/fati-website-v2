-- The "Quick start" card shown on your first visit (and from the menu button).

local UIKit = require(script.Parent.UIKit)

local QuickStart = {}

function QuickStart.build(parent: Instance, touchMode: boolean, onDone: () -> ()): (() -> (), () -> boolean)
	local card = UIKit.panel({
		Name = "QuickStart",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 30,
		Parent = parent,
	}, { UIKit.padding(22, 18), UIKit.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center) })
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(440, 600), Parent = card })

	local function line(order: number, text: string, size: number, font: Enum.Font, color: Color3?)
		UIKit.label({
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = text,
			TextSize = size,
			Font = font,
			TextColor3 = color or UIKit.WHITE,
			TextWrapped = true,
			RichText = true,
			ZIndex = 31,
			Parent = card,
		})
	end

	line(1, "Quick start", 30, UIKit.HEAVY)
	line(
		2,
		"Everyone starts human. When the outbreak hits, some players turn into zombies. Survive until the timer runs out, or infect every human.",
		17,
		UIKit.FONT,
		UIKit.MUTED
	)
	local controls: { string } = if touchMode
		then {
			"<b>Thumbstick</b>  move",
			"<b>USE</b>  swing or fire your item",
			"<b>GRAB</b> (hold)  drag the furniture next to you",
			"<b>PICK UP / DROP</b>  grab or let go of an item",
			"<b>SHOP</b>  buy items (and trade with the wizard)",
			"<b>RETURN</b>  zombies: back to spawn",
		}
		else {
			"<b>WASD / Arrows</b>  move",
			"<b>Mouse</b>  aim     <b>Click</b>  use item",
			"<b>B</b>  shop (or the wizard, when you stand next to him)",
			"<b>E</b>  pick up     <b>G</b>  drop",
			"<b>F</b> (hold)  grab the furniture next to you and drag it",
			"<b>Z</b>  zombies: back to spawn",
		}
	for i, text in controls do
		line(2 + i, text, 18, UIKit.BOLD)
	end
	line(
		10,
		"Tip: walk into furniture to push it (bigger players push harder). A held weapon pushes too. Jam a couch into a doorway to build a barricade!",
		17,
		UIKit.BOLD,
		UIKit.LIME
	)
	UIKit.button({
		LayoutOrder = 11,
		Text = "Got it",
		Size = UDim2.fromOffset(160, 42),
		BackgroundColor3 = UIKit.GOOD,
		TextSize = 22,
		ZIndex = 31,
		Parent = card,
	}, function()
		card.Visible = false
		onDone()
	end)

	local function open()
		card.Visible = true
	end
	local function isOpen(): boolean
		return card.Visible
	end
	return open, isOpen
end

return QuickStart
