-- Left side bar: five big square icon buttons stacked down the left edge
-- (menu, shop, settings, trophy, chat).

local UIKit = require(script.Parent.UIKit)

local TopLeft = {}

TopLeft.BUTTON = 66 -- button size (pixels before UI scaling)
TopLeft.GAP = 8

export type Actions = {
	menu: () -> (),
	shop: () -> (),
	settings: () -> (),
	trophy: () -> (),
	chat: () -> (),
}

function TopLeft.build(parent: Instance, actions: Actions)
	local bar = UIKit.new("Frame", {
		Name = "SideBar",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.fromOffset(TopLeft.BUTTON, 5 * (TopLeft.BUTTON + TopLeft.GAP)),
		Parent = parent,
	}, { UIKit.list(Enum.FillDirection.Vertical, TopLeft.GAP) })

	local buttons: { { icon: string, action: () -> (), accent: boolean?, name: string } } = {
		{ icon = "☰", action = actions.menu, accent = true, name = "Menu" },
		{ icon = "🛒", action = actions.shop, name = "Shop" },
		{ icon = "⚙", action = actions.settings, name = "Settings" },
		{ icon = "🏆", action = actions.trophy, name = "Trophy" },
		{ icon = "💬", action = actions.chat, name = "Chat" },
	}
	for i, b in buttons do
		UIKit.button({
			Name = b.name,
			Text = b.icon,
			TextSize = 34,
			Font = UIKit.BOLD,
			LayoutOrder = i,
			Size = UDim2.fromOffset(TopLeft.BUTTON, TopLeft.BUTTON),
			BackgroundColor3 = if b.accent then UIKit.ACCENT else UIKit.PANEL,
			BackgroundTransparency = if b.accent then 0 else UIKit.PANEL_TRANSPARENCY,
			Parent = bar,
		}, b.action)
	end
end

return TopLeft
