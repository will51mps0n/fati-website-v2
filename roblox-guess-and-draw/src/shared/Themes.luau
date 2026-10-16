-- Word themes. Each player picks one; when it's their turn, the words come from
-- it (see Words.luau) and everyone's background takes its colours.

export type Theme = {
	id: string,
	name: string,
	emoji: string,
	background: Color3, -- the screen's colour behind everything
	doodles: Color3, -- the colour of the doodle lines: a darker shade of the same
	-- colour, so they're soft (strong contrast looks jerky when it slides)
	still: boolean?, -- true keeps the background from sliding
	overlay: Color3?, -- the screen over the canvas between turns (default: a darker background)
}

local Themes = {
	list = {
		{
			id = "halloween",
			name = "Halloween",
			emoji = "🎃",
			background = Color3.fromRGB(236, 145, 64),
			doodles = Color3.fromRGB(190, 92, 36),
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
			doodles = Color3.fromRGB(92, 56, 164),
		},
		{
			id = "nature",
			name = "Plants & Animals",
			emoji = "🌿",
			background = Color3.fromRGB(36, 158, 168),
			doodles = Color3.fromRGB(22, 118, 128),
		},
		{
			id = "everyday",
			name = "People, Places & Things",
			emoji = "🏙️",
			background = Color3.fromRGB(50, 100, 210),
			doodles = Color3.fromRGB(34, 72, 170),
		},
		{
			id = "food",
			name = "Food",
			emoji = "🍔",
			background = Color3.fromRGB(236, 70, 86),
			doodles = Color3.fromRGB(186, 42, 62),
		},
	} :: { Theme },
	byId = {} :: { [string]: Theme },
}

for _, theme in Themes.list do
	Themes.byId[theme.id] = theme
end

return Themes
