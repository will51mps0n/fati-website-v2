-- Word themes. Each player picks one; when it's their turn, the words come from
-- it (see Words.luau) and everyone's background takes its colours.

export type Theme = {
	id: string,
	name: string,
	emoji: string,
	background: Color3, -- the screen's colour behind everything
	doodles: Color3, -- the colour of the doodle lines on it
	still: boolean?, -- true keeps the background from sliding
	overlay: Color3?, -- the screen over the canvas between turns (default: a darker background)
}

local Themes = {
	list = {
		{
			id = "halloween",
			name = "Halloween",
			emoji = "🎃",
			background = Color3.fromRGB(255, 128, 20),
			doodles = Color3.fromRGB(20, 12, 8),
			still = true, -- black lines on bright orange look jerky when they slide
		},
		{
			id = "general",
			name = "General",
			emoji = "🌍",
			-- Shows the original green tile (Config.BACKGROUND_TILE) as it always was.
			background = Color3.fromRGB(59, 106, 72),
			doodles = Color3.fromRGB(22, 61, 37),
			overlay = Color3.fromRGB(35, 82, 52),
		},
		{
			id = "fantasy",
			name = "Fantasy",
			emoji = "🐉",
			background = Color3.fromRGB(120, 80, 200),
			doodles = Color3.fromRGB(58, 30, 118),
		},
		{
			id = "nature",
			name = "Plants & Animals",
			emoji = "🌿",
			background = Color3.fromRGB(36, 158, 168),
			doodles = Color3.fromRGB(10, 78, 88),
		},
		{
			id = "everyday",
			name = "People, Places & Things",
			emoji = "🏙️",
			background = Color3.fromRGB(50, 100, 210),
			doodles = Color3.fromRGB(20, 48, 128),
		},
		{
			id = "food",
			name = "Food",
			emoji = "🍔",
			background = Color3.fromRGB(236, 70, 86),
			doodles = Color3.fromRGB(120, 18, 36),
		},
	} :: { Theme },
	byId = {} :: { [string]: Theme },
}

for _, theme in Themes.list do
	Themes.byId[theme.id] = theme
end

return Themes
