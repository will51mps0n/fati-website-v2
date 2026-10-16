-- Top-left: five square icon buttons (menu, shop, settings, trophy, chat).

local UIKit = require(script.Parent.UIKit)

local TopLeft = {}

export type Actions = {
	menu: () -> (),
	shop: () -> (),
	settings: () -> (),
	trophy: () -> (),
	chat: () -> (),
}

function TopLeft.build(parent: Instance, actions: Actions)
	local bar = UIKit.new("Frame", {
		Name = "TopLeft",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(5 * 50, 46),
		Parent = parent,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 6) })

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
			TextSize = 22,
			Font = UIKit.BOLD,
			LayoutOrder = i,
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = if b.accent then UIKit.ACCENT else UIKit.PANEL,
			BackgroundTransparency = if b.accent then 0 else UIKit.PANEL_TRANSPARENCY,
			Parent = bar,
		}, b.action)
	end
end

return TopLeft
