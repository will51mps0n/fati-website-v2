-- Colours and fonts, modelled on skribbl.io: flat white panels, Nunito text,
-- a monospace word, and green/blue/orange chat lines.

local function fontFace(enum: Enum.Font, weight: Enum.FontWeight?): Font
	return Font.new(Font.fromEnum(enum).Family, weight or Enum.FontWeight.Regular)
end

local Theme = {
	background = Color3.fromRGB(59, 106, 72),

	panel = Color3.fromRGB(255, 255, 255),
	rowAlt = Color3.fromRGB(236, 236, 236),
	border = Color3.fromRGB(204, 204, 204),
	text = Color3.fromRGB(20, 20, 20),
	muted = Color3.fromRGB(110, 110, 110),
	white = Color3.fromRGB(255, 255, 255),
	outline = Color3.fromRGB(15, 20, 30),

	you = Color3.fromRGB(74, 157, 230), -- your own name in the player list
	guessedRow = Color3.fromRGB(150, 226, 128),
	drawerRow = Color3.fromRGB(255, 236, 160),
	selected = Color3.fromRGB(170, 120, 230), -- the active tool / brush size

	-- The screen over the canvas between turns: a deep green to match the background.
	overlay = Color3.fromRGB(35, 82, 52),
	overlayTransparency = 0.04,
	overlayText = Color3.fromRGB(214, 240, 222),

	-- Chat colours
	green = Color3.fromRGB(86, 206, 39),
	greenBg = Color3.fromRGB(231, 255, 223),
	blue = Color3.fromRGB(57, 117, 206),
	orange = Color3.fromRGB(206, 79, 10),
	yellow = Color3.fromRGB(255, 211, 61),
	closeText = Color3.fromRGB(200, 160, 0),
	closeBg = Color3.fromRGB(255, 249, 214),
	red = Color3.fromRGB(230, 60, 60),

	gold = Color3.fromRGB(255, 205, 50),
	crownText = Color3.fromRGB(196, 140, 0), -- the win count beside the crown
	silver = Color3.fromRGB(200, 210, 222),
	bronze = Color3.fromRGB(222, 150, 92),

	regular = fontFace(Enum.Font.Nunito),
	bold = fontFace(Enum.Font.Nunito, Enum.FontWeight.Bold),
	heavy = fontFace(Enum.Font.Nunito, Enum.FontWeight.ExtraBold),
	mono = fontFace(Enum.Font.RobotoMono),
	monoBold = fontFace(Enum.Font.RobotoMono, Enum.FontWeight.Bold),
	logo = fontFace(Enum.Font.FredokaOne),
}

-- Logo letters cycle through these, like skribbl.io's.
Theme.rainbow = {
	Color3.fromRGB(239, 19, 11),
	Color3.fromRGB(255, 113, 0),
	Color3.fromRGB(255, 228, 0),
	Color3.fromRGB(0, 204, 0),
	Color3.fromRGB(0, 178, 255),
	Color3.fromRGB(35, 31, 211),
	Color3.fromRGB(163, 0, 186),
	Color3.fromRGB(223, 105, 167),
}

return Theme
