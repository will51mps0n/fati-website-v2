-- Builds the game screen, lets the drawer draw (streaming strokes to the server),
-- shows everyone else the drawing live, and handles guessing/chat. The look follows
-- skribbl.io; colours and fonts are in Theme, building blocks in Ui, sounds in
-- Sounds, and confetti/floating text in Effects.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("GuessAndDraw"):WaitForChild("Config"))
local Themes = require(ReplicatedStorage:WaitForChild("GuessAndDraw"):WaitForChild("Themes"))
local CanvasRenderer = require(script.Parent:WaitForChild("CanvasRenderer"))
local ColorPicker = require(script.Parent:WaitForChild("ColorPicker"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Ui = require(script.Parent:WaitForChild("Ui"))

local make, label, title = Ui.make, Ui.label, Ui.title

local Remotes = ReplicatedStorage:WaitForChild("GuessAndDrawRemotes")
local StateEvent = Remotes:WaitForChild("State") :: RemoteEvent
local DrawEvent = Remotes:WaitForChild("Draw") :: RemoteEvent
local CanvasEvent = Remotes:WaitForChild("Canvas") :: RemoteEvent
local ChatEvent = Remotes:WaitForChild("Chat") :: RemoteEvent
local GuessEvent = Remotes:WaitForChild("Guess") :: RemoteEvent
local WordChoiceEvent = Remotes:WaitForChild("WordChoice") :: RemoteEvent
local VoteEvent = Remotes:WaitForChild("Vote") :: RemoteEvent
local ShopEvent = Remotes:WaitForChild("Shop") :: RemoteEvent
local ThemeEvent = Remotes:WaitForChild("Theme") :: RemoteEvent

-- The Robux symbol, which Roblox's fonts draw at this code point.
local ROBUX = utf8.char(0xE002)

-- Live prices from Roblox (they can change with Managed pricing); Config's price
-- is shown until the real one arrives, or if it can't be looked up.
local MarketplaceService = game:GetService("MarketplaceService")
local livePrices: { [string]: number } = {}
local function priceOf(item: string): number
	return livePrices[item] or Config.PRODUCTS[item].price
end
local priceListeners: { () -> () } = {}
for item, product in Config.PRODUCTS do
	if product.id ~= 0 then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(product.id, Enum.InfoType.Product)
			end)
			if ok and info and typeof(info.PriceInRobux) == "number" then
				livePrices[item] = info.PriceInRobux
				for _, listener in priceListeners do
					listener()
				end
			end
		end)
	end
end

local player = Players.LocalPlayer

-- Guesses go through this game's own chat box, so hide Roblox's chat to keep
-- answers out of it.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			break
		end
		task.wait(1)
	end
end)

local function clearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function escapeRichText(text: string): string
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

local function colorTag(color: Color3, text: string): string
	return `<font color="#{color:ToHex()}">{text}</font>`
end

-- Each letter in a different colour, like the skribbl.io logo.
local function rainbowText(text: string): string
	local parts = {}
	local index = 0
	for _, code in utf8.codes(text) do
		local char = utf8.char(code)
		if char == " " then
			table.insert(parts, " ")
		else
			index += 1
			table.insert(parts, colorTag(Theme.rainbow[(index - 1) % #Theme.rainbow + 1], escapeRichText(char)))
		end
	end
	return table.concat(parts)
end

-- Screen & background ---------------------------------------------------------------

local screen = make("ScreenGui", {
	Name = "GuessAndDraw",
	ResetOnSpawn = false,
	-- Cover the whole window, behind Roblox's topbar too, so the background fills it.
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

local background = make("Frame", {
	Name = "Background",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Theme.background,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 0,
	Parent = screen,
})

-- The background takes the colours of the current word theme. With the doodle
-- lines uploaded (white on see-through), they're tinted per theme over a plain
-- colour; without them, the green tile shows for the General theme only.
local doodles = Config.BACKGROUND_DOODLES ~= ""
local tile = Config.BACKGROUND_TILE_SIZE
local backgroundImage: ImageLabel? = nil
if doodles or Config.BACKGROUND_TILE ~= "" then
	local image = make("ImageLabel", {
		-- One tile larger than the screen so it can scroll seamlessly.
		Size = UDim2.new(1, tile, 1, tile),
		BackgroundTransparency = 1,
		Image = if doodles then Config.BACKGROUND_DOODLES else Config.BACKGROUND_TILE,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(tile, tile),
		Parent = background,
	})
	backgroundImage = image
	if Config.BACKGROUND_SCROLL_SPEED > 0 then
		-- Roblox draws GUI at whole pixels, so the drift is a series of 1-pixel hops.
		-- Timing each hop by the clock lets frame-time wobble space them unevenly
		-- (4 frames, then 6, then 5...), which reads as a judder on bold lines. So hop
		-- every N frames instead, with N worked out from the smoothed frame rate: the
		-- hops come at an even beat and the speed still matches the setting.
		local framesPerSecond = 60
		local framesSinceHop = 0
		local offset = 0
		RunService.RenderStepped:Connect(function(dt)
			framesPerSecond += (1 / math.max(dt, 1 / 360) - framesPerSecond) * 0.02
			framesSinceHop += 1
			if framesSinceHop >= math.max(1, math.round(framesPerSecond / Config.BACKGROUND_SCROLL_SPEED)) then
				framesSinceHop = 0
				offset = (offset + 1) % tile
				image.Position = UDim2.fromOffset(-offset, -offset)
			end
		end)
	end
end

local shownTheme: string? = nil
local applyThemeToOverlay: (Themes.Theme) -> () = function() end

local function applyTheme(themeId: string)
	if themeId == shownTheme then
		return
	end
	shownTheme = themeId
	local theme = Themes.byId[themeId] or Themes.byId.general
	Ui.tween(background, 0.8, { BackgroundColor3 = theme.background })
	local image = backgroundImage
	if image then
		if doodles then
			Ui.tween(image, 0.8, { ImageColor3 = theme.doodles, ImageTransparency = 0 })
		else
			-- Only the green tile is available: show it for General, plain colour otherwise.
			Ui.tween(image, 0.8, { ImageTransparency = if theme.id == "general" then 0 else 1 })
		end
	end
	applyThemeToOverlay(theme)
end

local root = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 1,
	Parent = screen,
})

local effectsLayer = make("Frame", {
	Name = "Effects",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 10,
	Parent = screen,
})
Effects.init(effectsLayer)

-- The whole game sits in one box laid out with skribbl.io's own measurements (in
-- pixels at 1870 wide), then zoomed as a whole to fill the window's width, or its
-- height if that runs out first, so everything keeps the same proportions and
-- spacing on any screen. `box` turns design-pixel rectangles into positions and
-- sizes inside it.
local DESIGN = Vector2.new(1870, 1086)
local MARGIN = 10
-- At most this share of the window's width, so background shows at the sides.
local MAX_WIDTH_SHARE = 0.82

local game_ = make("Frame", {
	Name = "Game",
	AnchorPoint = Vector2.new(0.5, 0),
	Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y),
	BackgroundTransparency = 1,
	Parent = root,
})
local gameScale = make("UIScale", { Parent = game_ })

-- Height of Roblox's topbar (menu buttons). It can be 0 for a moment while the
-- game loads, so this is re-checked whenever it changes.
local function topInset(): number
	local inset = GuiService:GetGuiInset().Y
	pcall(function()
		inset = math.max(inset, GuiService.TopbarInset.Height)
	end)
	return inset
end

local function fitToScreen()
	local inset = topInset()
	local available = screen.AbsoluteSize - Vector2.new(MARGIN * 2, inset + MARGIN * 2)
	local width = math.min(available.X, screen.AbsoluteSize.X * MAX_WIDTH_SHARE)
	gameScale.Scale = math.clamp(math.min(width / DESIGN.X, available.Y / DESIGN.Y), 0.1, 2)
	-- Centred left to right, pinned to the top just below Roblox's topbar.
	game_.Position = UDim2.new(0.5, 0, 0, inset + MARGIN)
end

screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToScreen)
pcall(function()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fitToScreen)
end)
fitToScreen()

-- Roblox's automatic sizing (AutomaticCanvasSize / AutomaticSize) miscounts inside
-- the zoomed game area, which left the newest chat messages below the bottom of
-- the scroll area, out of sight. So scrolling lists are sized by hand: measure the
-- content, undo the zoom, and set the size. `onSized` runs after each resize.
local function sizeToContent(layout: UIListLayout, target: GuiObject, extra: number, onSized: ((number) -> ())?)
	local function update()
		local height = layout.AbsoluteContentSize.Y / gameScale.Scale + extra
		if target:IsA("ScrollingFrame") then
			target.CanvasSize = UDim2.fromOffset(0, height)
		else
			target.Size = UDim2.new(1, 0, 0, height)
		end
		if onSized then
			onSized(height)
		end
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update)
	gameScale:GetPropertyChangedSignal("Scale"):Connect(update)
	task.defer(update)
end

local function box(x: number, y: number, width: number, height: number): (UDim2, UDim2)
	return UDim2.fromScale(x / DESIGN.X, y / DESIGN.Y), UDim2.fromScale(width / DESIGN.X, height / DESIGN.Y)
end

-- Logo -----------------------------------------------------------------------------------

local LOGO_TEXT = "Guess & Draw"
local logoPosition, logoSize = box(0, 0, 430, 64)
local logo = make("Frame", {
	Position = logoPosition,
	Size = logoSize,
	BackgroundTransparency = 1,
	Parent = game_,
})
-- A dark copy behind the letters gives the chunky drop shadow.
local logoShadowOutline = Ui.textOutline(3, Theme.outline)
local logoOutline = Ui.textOutline(3, Theme.outline)
local logoShadow = label({
	Position = UDim2.fromOffset(3, 4),
	Size = UDim2.fromScale(0.86, 1),
	Text = LOGO_TEXT,
	FontFace = Theme.logo,
	TextColor3 = Theme.outline,
	TextTransparency = 0.35,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = logo,
}, { logoShadowOutline })
local logoLetters = label({
	Size = UDim2.fromScale(0.86, 1),
	RichText = true,
	Text = rainbowText(LOGO_TEXT),
	FontFace = Theme.logo,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = logo,
}, { logoOutline })
local logoPencil = Ui.pencil({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.92, 0.5),
	Size = UDim2.fromScale(0.12, 1.1),
	Rotation = 23,
	OutlineThickness = 3,
	Parent = logo,
})

-- Like skribbl.io's logo, it doesn't glide: it flicks between two slightly
-- different drawings (thicker outline, nudged a pixel) a few times a second, so it
-- looks hand-drawn and alive.
task.spawn(function()
	local alternate = false
	while true do
		task.wait(0.32)
		alternate = not alternate
		logoOutline.Thickness = if alternate then 4.5 else 3
		logoShadowOutline.Thickness = logoOutline.Thickness
		logoLetters.Position = if alternate then UDim2.fromOffset(1, -1) else UDim2.new()
		logoShadow.Position = if alternate then UDim2.fromOffset(4, 4) else UDim2.fromOffset(3, 4)
		logoPencil.Rotation = if alternate then 27 else 23
	end
end)

-- Top bar: alarm clock, round, word, sound toggle ----------------------------------------

local topPosition, topSize = box(0, 70, 1870, 68)
local topBar = Ui.panel({ Position = topPosition, Size = topSize, Parent = game_ })

-- skribbl.io's alarm clock: grey bells, a thick black ring and little legs, and a
-- bit bigger than the bar so it pokes out above and below.
local clock = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 2, 0.5, 0),
	Size = UDim2.fromScale(1, 1.12),
	BackgroundTransparency = 1,
	Parent = topBar,
}, { Ui.square() })

make("Frame", { -- the knob between the bells
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.09),
	Size = UDim2.fromScale(0.08, 0.07),
	BackgroundColor3 = Theme.outline,
	ZIndex = 1,
	Parent = clock,
}, { Ui.corner(2) })
for _, side in { -1, 1 } do
	make("Frame", { -- bell
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + side * 0.25, 0.15),
		Size = UDim2.fromScale(0.32, 0.2),
		Rotation = side * 35,
		BackgroundColor3 = Color3.fromRGB(150, 150, 150),
		ZIndex = 1,
		Parent = clock,
	}, { Ui.round(), Ui.border(3, Theme.outline) })
	make("Frame", { -- leg
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + side * 0.24, 0.92),
		Size = UDim2.fromScale(0.06, 0.13),
		Rotation = side * -40,
		BackgroundColor3 = Theme.outline,
		ZIndex = 1,
		Parent = clock,
	}, { Ui.round() })
end

local clockFace = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.fromScale(0.76, 0.76),
	BackgroundColor3 = Theme.white,
	ZIndex = 2,
	Parent = clock,
}, { Ui.round(), Ui.border(4, Theme.outline) })

local timerLabel = label({
	Size = UDim2.fromScale(1, 1),
	FontFace = Theme.heavy,
	Text = "",
	Parent = clockFace,
}, { Ui.pad(8) })

local roundLabel = label({
	Position = UDim2.fromScale(0.045, 0.06),
	Size = UDim2.fromScale(0.25, 0.54),
	FontFace = Theme.bold,
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = topBar,
}, { Ui.maxText(30) })

-- Which word theme this turn uses, under the round.
local themeLabel = label({
	Position = UDim2.fromScale(0.045, 0.58),
	Size = UDim2.fromScale(0.25, 0.36),
	FontFace = Theme.bold,
	Text = "",
	TextColor3 = Theme.muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = topBar,
}, { Ui.maxText(20) })

local wordArea = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromScale(0.44, 1),
	BackgroundTransparency = 1,
	Parent = topBar,
})

local wordCaption = label({
	Position = UDim2.fromScale(0, 0.08),
	Size = UDim2.fromScale(1, 0.3),
	FontFace = Theme.mono,
	Text = "",
	Parent = wordArea,
}, { Ui.maxText(20) })

-- The word, one letter per box like skribbl.io: hidden letters are just an
-- underline, and each word's letter count sits raised at the end.
local wordRow = make("Frame", {
	Position = UDim2.fromScale(0, 0.4),
	Size = UDim2.fromScale(1, 0.52),
	BackgroundTransparency = 1,
	Parent = wordArea,
}, {
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local shownWord: string? = nil
local function setWord(word: string?, hidden: boolean, color: Color3)
	local key = if word then `{word}|{hidden}|{color:ToHex()}` else nil
	if key == shownWord then
		return
	end
	shownWord = key
	for _, child in wordRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not word then
		return
	end
	local counts, current = {}, 0
	for i = 1, #word do
		local char = string.sub(word, i, i)
		if char == " " then
			make("Frame", { Size = UDim2.fromOffset(16, 1), BackgroundTransparency = 1, LayoutOrder = i, Parent = wordRow })
			table.insert(counts, current)
			current = 0
		else
			current += 1
			local cell = label({
				Size = UDim2.new(0, 20, 1, 0),
				Text = if char == "_" then "" else char,
				FontFace = Theme.monoBold,
				TextScaled = false,
				TextSize = 30,
				TextColor3 = color,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				LayoutOrder = i,
				Parent = wordRow,
			})
			if hidden then
				make("Frame", {
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.new(0, 0, 1, 2),
					Size = UDim2.new(1, 0, 0, 3),
					BackgroundColor3 = Theme.text,
					BorderSizePixel = 0,
					Parent = cell,
				})
			end
		end
	end
	table.insert(counts, current)
	label({
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = table.concat(counts, " "),
		FontFace = Theme.mono,
		TextScaled = false,
		TextSize = 18,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = #word + 1,
		Parent = wordRow,
	}, { make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, -6) }) })
end

-- Where skribbl.io has its settings gear: a sound on/off switch.
local soundButton = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -6, 0.5, 0),
	Size = UDim2.fromScale(1, 0.85),
	BackgroundTransparency = 1,
	Text = "🔊",
	TextScaled = true,
	Parent = topBar,
}, { Ui.square() })
Ui.hoverable(soundButton)
soundButton.Activated:Connect(function()
	Sounds.muted = not Sounds.muted
	soundButton.Text = if Sounds.muted then "🔇" else "🔊"
	Sounds.play("click")
end)

-- Orange pill buttons in the top bar.
local function pill(text: string, width: number, rightOffset: number): TextButton
	local button = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -rightOffset, 0.5, 0),
		Size = UDim2.fromOffset(width, 48),
		BackgroundColor3 = Color3.fromRGB(255, 150, 30),
		AutoButtonColor = false,
		Text = text,
		TextScaled = true,
		FontFace = Theme.heavy,
		TextColor3 = Theme.white,
		Parent = topBar,
	}, { Ui.corner(10), Ui.pad(14, 9) })
	Ui.hoverable(button)
	return button
end

-- Votes to kick whoever is drawing right now (e.g. for drawing something rude).
local voteKickButton = pill("Vote Kick: 0/2", 230, 230)
local reportButton = pill("Report", 140, 78)

-- Left: players ----------------------------------------------------------------------------

local MAIN_TOP = 147
local CANVAS_HEIGHT = 856 -- 4:3 of the 1141-wide canvas

local THEME_MENU_HEIGHT = 64
local playersPosition, playersSize = box(0, MAIN_TOP, 284, CANVAS_HEIGHT - THEME_MENU_HEIGHT - 10)
local playersScroller = make("ScrollingFrame", {
	Position = playersPosition,
	Size = playersSize,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	Parent = game_,
})
-- Like skribbl.io's, the list is one white card with rounded corners, only as tall
-- as its rows (the small padding keeps the rows inside the rounded corners).
local playersLayout = make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder })
local playersList = Ui.panel({
	Size = UDim2.fromScale(1, 0),
	Parent = playersScroller,
}, {
	playersLayout,
	make("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }),
})
-- The card is as tall as its rows (plus its padding), and the scroller fits the card.
sizeToContent(playersLayout, playersList, 10, function(height)
	playersScroller.CanvasSize = UDim2.fromOffset(0, height)
end)
playersList:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 7)

-- "Your theme" menu under the player list: the words you get, and everyone's
-- background colour, when it's your turn to draw.
local themeMenuPosition, themeMenuSize = box(0, MAIN_TOP + CANVAS_HEIGHT - THEME_MENU_HEIGHT, 284, THEME_MENU_HEIGHT)
local themeButton = make("TextButton", {
	Position = themeMenuPosition,
	Size = themeMenuSize,
	BackgroundColor3 = Theme.white,
	AutoButtonColor = false,
	Text = "",
	Parent = game_,
}, { Ui.corner(7) })
label({
	Position = UDim2.fromOffset(12, 5),
	Size = UDim2.new(1, -24, 0, 20),
	Text = "YOUR THEME",
	TextScaled = false,
	TextSize = 15,
	FontFace = Theme.mono,
	TextColor3 = Theme.muted,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = themeButton,
})
local themeButtonText = label({
	Position = UDim2.fromOffset(12, 26),
	Size = UDim2.new(1, -52, 0, 30),
	Text = "",
	TextScaled = false,
	TextSize = 22,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = themeButton,
})
-- The arrow, drawn from two bars because the font has no arrow glyph. The list
-- opens upwards, so it points up while closed and down (to close) while open.
local themeArrow = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -26, 0, 41),
	Size = UDim2.fromOffset(18, 18),
	Rotation = 180,
	BackgroundTransparency = 1,
	Parent = themeButton,
})
for _, side in { -1, 1 } do
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, side * 4, 0.5, 0),
		Size = UDim2.fromOffset(12, 4),
		Rotation = side * -45,
		BackgroundColor3 = Theme.text,
		Parent = themeArrow,
	}, { Ui.corner(2) })
end
Ui.hoverable(themeButton)

local themeList = Ui.panel({
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromOffset(0, MAIN_TOP + CANVAS_HEIGHT - THEME_MENU_HEIGHT - 8),
	Size = UDim2.fromOffset(330, 16 + #Themes.list * 58),
	Visible = false,
	ZIndex = 20,
	Parent = game_,
}, {
	Ui.border(2, Theme.border),
	Ui.pad(8),
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})

local myTheme = Config.DEFAULT_THEME
local themeOptions: { [string]: TextLabel } = {}

local function showMyTheme()
	local theme = Themes.byId[myTheme] or Themes.byId.general
	themeButtonText.Text = `{theme.emoji} {theme.name}`
	for id, tick in themeOptions do
		tick.Text = if id == myTheme then "✓" else ""
	end
end

for order, theme in Themes.list do
	local option = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = Theme.rowAlt,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = themeList,
	}, { Ui.corner(8) })
	make("Frame", { -- a swatch of the theme's background colour
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = theme.background,
		Parent = option,
	}, { Ui.corner(8), Ui.border(2, theme.doodles) })
	label({
		Position = UDim2.fromOffset(54, 0),
		Size = UDim2.new(1, -94, 1, 0),
		Text = `{theme.emoji} {theme.name}`,
		TextScaled = false,
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = option,
	})
	themeOptions[theme.id] = label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		Text = "",
		TextColor3 = Theme.green,
		FontFace = Theme.heavy,
		Parent = option,
	})
	option.MouseEnter:Connect(function()
		option.BackgroundColor3 = Theme.border
	end)
	option.MouseLeave:Connect(function()
		option.BackgroundColor3 = Theme.rowAlt
	end)
	option.Activated:Connect(function()
		myTheme = theme.id
		showMyTheme()
		ThemeEvent:FireServer(theme.id)
		Sounds.play("click")
		themeList.Visible = false
	end)
end
showMyTheme()

themeList:GetPropertyChangedSignal("Visible"):Connect(function()
	Ui.tween(themeArrow, 0.15, { Rotation = if themeList.Visible then 0 else 180 })
end)

themeButton.Activated:Connect(function()
	Sounds.play("click", 0.5)
	themeList.Visible = not themeList.Visible
	if themeList.Visible then
		Ui.pop(themeList, 0.7, 0.25)
	end
end)

-- Centre: canvas and toolbar ------------------------------------------------------------------

local canvasPosition, canvasSize = box(293, MAIN_TOP, 1141, CANVAS_HEIGHT)
local canvasArea = make("Frame", {
	Position = canvasPosition,
	Size = canvasSize,
	BackgroundTransparency = 1,
	Parent = game_,
})

-- Every layer over the canvas shares the same centred 4:3 box.
local function canvasLayer(className: string, props: { [string]: any }, children: { Instance }?): any
	local list = children or {}
	table.insert(list, make("UIAspectRatioConstraint", { AspectRatio = Config.CANVAS_ASPECT }))
	local defaults = {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = canvasArea,
	}
	for key, value in props do
		defaults[key] = value
	end
	return make(className, defaults, list)
end

-- A CanvasGroup clips rotated children, which a plain Frame with ClipsDescendants doesn't.
local canvas = canvasLayer("CanvasGroup", {
	Name = "Canvas",
	BackgroundColor3 = Config.BACKGROUND_COLOR,
	BackgroundTransparency = 0,
	Active = true,
	ZIndex = 1,
}, { Ui.corner(4) })

-- Replaces the mouse pointer over the canvas: a dot the size and colour of the brush,
-- centred exactly where the line will be drawn. It sits on its own layer so moving
-- it doesn't make the CanvasGroup re-render every stroke.
local cursorLayer = canvasLayer("Frame", { ClipsDescendants = true, ZIndex = 2 })

local cursorDot = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	BorderSizePixel = 0,
	Visible = false,
	Parent = cursorLayer,
}, {
	Ui.round(),
	make("UIStroke", { Color = Color3.fromRGB(90, 90, 90), Thickness = 1 }),
	make("UISizeConstraint", { MinSize = Vector2.new(5, 5) }),
})

local renderer = CanvasRenderer.new(canvas)

-- The dark overlay on the canvas for waiting / choosing / reveal / winners. Its
-- content slides down from the top, as on skribbl.io.
local overlay = canvasLayer("Frame", {
	Name = "Overlay",
	BackgroundColor3 = Theme.overlay, -- replaced by a darker shade of the theme colour
	BackgroundTransparency = Theme.overlayTransparency,
	ClipsDescendants = true,
	ZIndex = 3,
}, { Ui.corner(4) })

applyThemeToOverlay = function(theme)
	Ui.tween(overlay, 0.8, { BackgroundColor3 = theme.background:Lerp(Color3.new(0, 0, 0), 0.45) })
end

local overlayContent = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = overlay,
}, { Ui.pad(20) })

local overlayTitle = title({
	Position = UDim2.fromScale(0, 0.06),
	Size = UDim2.fromScale(1, 0.13),
	Text = "",
	Parent = overlayContent,
}, { Ui.maxText(46) })

local overlaySubtitle = label({
	Position = UDim2.fromScale(0, 0.2),
	Size = UDim2.fromScale(1, 0.07),
	Text = "",
	TextColor3 = Theme.overlayText,
	Parent = overlayContent,
}, { Ui.maxText(24) })

local overlayBody = make("Frame", {
	Position = UDim2.fromScale(0, 0.32),
	Size = UDim2.fromScale(1, 0.66),
	BackgroundTransparency = 1,
	Parent = overlayContent,
})

-- Below the canvas: the drawing tools, shown only to the drawer.
local toolbarPosition, toolbarSize = box(293, MAIN_TOP + CANVAS_HEIGHT + 10, 1141, 64)
local toolbar = make("Frame", {
	Position = toolbarPosition,
	Size = toolbarSize,
	BackgroundTransparency = 1,
	Visible = false,
	Parent = game_,
}, {
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

-- Like skribbl.io, guessers get a thumbs up and a thumbs down in the canvas's
-- top-right corner, one vote per drawing.
local rateBar = make("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 8),
	Size = UDim2.fromOffset(176, 82),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = canvasLayer("Frame", { Name = "Rating", ZIndex = 4 }),
}, {
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local ratedThisTurn = false
local render: () -> () -- defined further down
local RATINGS = {
	{ kind = "like", image = Config.THUMBS_UP_IMAGE, icon = "👍" },
	{ kind = "dislike", image = Config.THUMBS_DOWN_IMAGE, icon = "👎" },
}
for order, vote in RATINGS do
	local button = if vote.image ~= ""
		then make("ImageButton", {
			Size = UDim2.fromOffset(82, 82),
			BackgroundTransparency = 1,
			Image = vote.image,
			ScaleType = Enum.ScaleType.Fit,
			LayoutOrder = order,
			Parent = rateBar,
		})
		else make("TextButton", {
			Size = UDim2.fromOffset(82, 82),
			BackgroundTransparency = 1,
			Text = vote.icon,
			TextScaled = true,
			LayoutOrder = order,
			Parent = rateBar,
		}, { Ui.pad(6) })
	Ui.hoverable(button)
	button.Activated:Connect(function()
		if ratedThisTurn then
			return
		end
		ratedThisTurn = true
		VoteEvent:FireServer(vote.kind)
		render()
	end)
end

-- The Robux shop under the canvas, for everyone but the drawer.
local shopBar = make("Frame", {
	Position = toolbarPosition,
	Size = toolbarSize,
	BackgroundTransparency = 1,
	Visible = false,
	Parent = game_,
}, {
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 22),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local SHOP_ITEMS = {
	{ item = "nuke", title = "NUKE DRAWING!", icon = "💣", color = Color3.fromRGB(235, 85, 85) },
	{ item = "steal", title = "STEAL DRAWING!", icon = "🦹", color = Color3.fromRGB(80, 140, 235) },
	{ item = "instaGuess", title = "INSTA GUESS!", icon = "🏆", color = Color3.fromRGB(245, 160, 40) },
}
local shopPriceLabels: { [string]: TextLabel } = {}

for order, entry in SHOP_ITEMS do
	local button = make("TextButton", {
		Size = UDim2.new(0, 330, 1, 0),
		BackgroundColor3 = Theme.white,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = shopBar,
	}, {
		Ui.corner(16),
		Ui.border(3, entry.color:Lerp(Theme.outline, 0.4)),
		make("UIGradient", { Color = ColorSequence.new(Theme.white:Lerp(entry.color, 0.25), entry.color), Rotation = 90 }),
	})
	label({ -- big icon poking out on the left
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -14, 0.5, 0),
		Size = UDim2.fromOffset(84, 84),
		Text = entry.icon,
		Rotation = -10,
		Parent = button,
	})
	shopPriceLabels[entry.item] = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 2),
		Size = UDim2.new(0.5, 0, 0.36, 0),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.heavy,
		TextColor3 = Theme.white,
		Parent = button,
	}, { Ui.textOutline(2) })
	label({
		Position = UDim2.new(0, 70, 0.34, 0),
		Size = UDim2.new(1, -82, 0.62, 0),
		Text = entry.title,
		FontFace = Theme.heavy,
		TextColor3 = Theme.white,
		Parent = button,
	}, { Ui.textOutline(2.5) })
	Ui.hoverable(button)
	button.Activated:Connect(function()
		Sounds.play("click")
		ShopEvent:FireServer(entry.item)
	end)
end

-- Right: chat ----------------------------------------------------------------------------------

local chatPosition, chatSize = box(1442, MAIN_TOP, 428, CANVAS_HEIGHT)
local chatPanel = Ui.panel({ Position = chatPosition, Size = chatSize, Parent = game_ })

local chatLog = make("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -64),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	Parent = chatPanel,
})
-- New messages stack up from the bottom, like skribbl.io.
local chatLayout = make("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Parent = chatLog,
})
-- Keep the newest message in view as the log grows.
sizeToContent(chatLayout, chatLog, 0, function(height)
	chatLog.CanvasPosition = Vector2.new(0, math.max(0, height - chatLog.AbsoluteWindowSize.Y / gameScale.Scale))
end)

local guessBorder = Ui.border(1, Theme.border)
local guessBox = make("TextBox", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 6, 1, -6),
	Size = UDim2.new(1, -12, 0, 50),
	BackgroundColor3 = Theme.white,
	TextColor3 = Theme.text,
	PlaceholderText = "Type your guess here...",
	PlaceholderColor3 = Theme.muted,
	Text = "",
	FontFace = Theme.regular,
	TextSize = 23,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	Parent = chatPanel,
}, { Ui.corner(4), Ui.pad(8, 4), guessBorder })

guessBox.Focused:Connect(function()
	guessBorder.Color = Theme.you
	guessBorder.Thickness = 2
end)

-- Game state ----------------------------------------------------------------------------------

local snapshot: any = nil
local wordChoices: { string }? = nil
local chosenWord: string? = nil
local customForm = false -- the drawer opened the password-protected custom word form
local customError: TextLabel? = nil

local selectedColor: Color3 = Config.COLORS[1].color
local selectedSize = Config.DEFAULT_BRUSH_SIZE
local tool = "pen" -- "pen", "eraser" or "fill"

-- Chat -------------------------------------------------------------------------------------------

local chatOrder = 0
local MAX_CHAT_LINES = 120

-- skribbl.io's chat colours: green for good news, orange for leaving, blue for turns.
local CHAT_STYLES = {
	chat = { text = Theme.text },
	insider = { text = Theme.green },
	system = { text = Theme.blue, bold = true },
	reveal = { text = Theme.green, bold = true },
	join = { text = Theme.green, bold = true },
	leave = { text = Theme.orange, bold = true },
	correct = { text = Theme.green, bg = Theme.greenBg, bold = true },
	close = { text = Theme.closeText, bg = Theme.closeBg, bold = true },
	like = { text = Theme.green, bold = true },
	dislike = { text = Theme.orange, bold = true },
	kick = { text = Theme.orange, bold = true },
	power = { text = Theme.selected, bold = true },
}

local function addChatLine(message)
	chatOrder += 1
	local style = CHAT_STYLES[message.kind] or CHAT_STYLES.chat
	local body = escapeRichText(message.text)
	local text = if message.name then `<b>{escapeRichText(message.name)}:</b> {body}` else body

	local line = label({
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		RichText = true,
		Text = text,
		TextScaled = false,
		TextSize = 24,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = if style.bold then Theme.bold else Theme.regular,
		TextColor3 = style.text,
		TextTransparency = 1,
		BackgroundColor3 = style.bg or (if chatOrder % 2 == 0 then Theme.rowAlt else Theme.white),
		BackgroundTransparency = 0,
		LayoutOrder = chatOrder,
		Parent = chatLog,
	}, { Ui.pad(7, 9) })
	Ui.tween(line, 0.2, { TextTransparency = 0 })

	if message.kind == "close" then
		Sounds.play("tick")
	elseif message.kind == "like" or message.kind == "dislike" then
		-- A thumb pops up over the bottom of the canvas for everyone.
		local x = canvas.AbsolutePosition.X + canvas.AbsoluteSize.X * (0.3 + math.random() * 0.4)
		local y = canvas.AbsolutePosition.Y + canvas.AbsoluteSize.Y * 0.85
		Effects.floatText(if message.kind == "like" then "👍" else "👎", Theme.white, Vector2.new(x, y), 48)
		Sounds.play("click", 0.5)
	end

	local lines = {}
	for _, child in chatLog:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(lines, child)
		end
	end
	if #lines > MAX_CHAT_LINES then
		table.sort(lines, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #lines - MAX_CHAT_LINES do
			lines[i]:Destroy()
		end
	end

end

ChatEvent.OnClientEvent:Connect(addChatLine)

guessBox.FocusLost:Connect(function(enterPressed)
	guessBorder.Color = Theme.border
	guessBorder.Thickness = 1
	if not enterPressed then
		return
	end
	local text = guessBox.Text
	guessBox.Text = ""
	if string.match(text, "%S") then
		GuessEvent:FireServer(text)
	end
	task.defer(function()
		guessBox:CaptureFocus()
	end)
end)

-- Toolbar ----------------------------------------------------------------------------------------

-- The colour being painted with: the eraser paints the canvas background.
local function paintColor(): Color3
	return if tool == "eraser" then Config.BACKGROUND_COLOR else selectedColor
end

local refreshToolbar: () -> ()

-- The colour wheel pops up just above the toolbar, from the current-colour square.
local pickerPosition, pickerSize = box(293, MAIN_TOP + CANVAS_HEIGHT - 400, 310, 390)
local picker = ColorPicker.new({ Position = pickerPosition, Size = pickerSize, Parent = game_ }, function(color)
	selectedColor = color
	if tool == "eraser" then
		tool = "pen"
	end
	refreshToolbar()
end)

-- Shows the current colour; click it to open the colour wheel.
local currentColor = Ui.toolButton({ LayoutOrder = 1, Parent = toolbar })
Ui.border(3, Theme.white).Parent = currentColor
label({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.fromScale(1.15, 1.15),
	Size = UDim2.fromScale(0.55, 0.55),
	Text = "🎨",
	Parent = currentColor,
})
currentColor.Activated:Connect(function()
	if picker:isOpen() then
		picker:close()
	else
		picker:open(selectedColor)
	end
end)

-- 7 x 2 palette squares packed edge to edge.
local palette = make("Frame", {
	Size = UDim2.fromScale(7 * 32 / 1141, 1),
	BackgroundTransparency = 1,
	LayoutOrder = 2,
	Parent = toolbar,
}, {
	make("UIGridLayout", {
		CellSize = UDim2.fromScale(1 / 7, 0.5),
		CellPadding = UDim2.new(),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local swatchMarks: { [number]: Frame } = {}
for index, entry in Config.COLORS do
	local swatch = make("TextButton", {
		Name = entry.name,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = entry.color,
		BorderSizePixel = 0,
		LayoutOrder = index,
		Parent = palette,
	})
	-- A ring marking the selected colour: dark on light colours, white on dark ones.
	local _, saturation, value = entry.color:ToHSV()
	local light = value > 0.8 and saturation < 0.5
	swatchMarks[index] = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = swatch,
	}, { Ui.square(), Ui.round(), Ui.border(2, if light then Theme.outline else Theme.white) })
	swatch.MouseEnter:Connect(function()
		swatch.BackgroundColor3 = entry.color:Lerp(Theme.white, 0.25)
	end)
	swatch.MouseLeave:Connect(function()
		swatch.BackgroundColor3 = entry.color
	end)
	swatch.Activated:Connect(function()
		selectedColor = entry.color
		if tool == "eraser" then
			tool = "pen"
		end
		picker:close()
		Sounds.play("click", 0.5)
		refreshToolbar()
	end)
end

local sizeButtons: { [number]: TextButton } = {}
for index, size in Config.BRUSH_SIZES do
	local sizeButton = Ui.toolButton({ LayoutOrder = 2 + index, Parent = toolbar })
	local dotScale = math.clamp(size / Config.BRUSH_SIZES[#Config.BRUSH_SIZES], 0.12, 0.7)
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(dotScale, dotScale),
		BackgroundColor3 = Theme.outline,
		Parent = sizeButton,
	}, { Ui.round() })
	sizeButtons[index] = sizeButton
	sizeButton.Activated:Connect(function()
		selectedSize = index
		refreshToolbar()
	end)
end

local function iconButton(icon: string, order: number): TextButton
	local button = Ui.toolButton({ LayoutOrder = 10 + order, Parent = toolbar })
	label({ Size = UDim2.fromScale(1, 1), Text = icon, Parent = button }, { Ui.pad(9) })
	return button
end

local toolButtons: { [string]: TextButton } = {
	pen = iconButton("✏️", 1),
	eraser = iconButton("🧽", 2),
	fill = iconButton("🪣", 3),
}
for name, button in toolButtons do
	button.Activated:Connect(function()
		tool = name
		refreshToolbar()
	end)
end
iconButton("↩️", 4).Activated:Connect(function()
	CanvasEvent:FireServer("undo")
end)
iconButton("🗑️", 5).Activated:Connect(function()
	CanvasEvent:FireServer("clear")
end)

function refreshToolbar()
	currentColor.BackgroundColor3 = paintColor()
	for index, mark in swatchMarks do
		mark.Visible = tool ~= "eraser" and Config.COLORS[index].color == selectedColor
	end
	for index, sizeButton in sizeButtons do
		sizeButton.BackgroundColor3 = if index == selectedSize then Theme.selected else Theme.white
	end
	for name, button in toolButtons do
		button.BackgroundColor3 = if tool == name then Theme.selected else Theme.white
	end
end

refreshToolbar()

-- Drawing input -----------------------------------------------------------------------------------

-- Starts at a random point so that after someone steals the drawing, their stroke
-- IDs don't clash with the previous drawer's.
local strokeCounter = math.random(1, 2 ^ 20) * 1024
local activeStroke: { id: number, c: number, s: number, lastX: number, lastY: number }? = nil
local activeInput: InputObject? = nil
local pending: { number } = {}
local sendTimer = 0
-- Slightly slower than the server allows, so a fill it would reject is never sent.
local FILL_INTERVAL = Config.MIN_FILL_INTERVAL + 0.05
local lastFillAt = -math.huge

local function canDraw(): boolean
	return snapshot ~= nil and snapshot.canDraw == true
end

-- Returns the point as canvas fractions (clamped to the canvas) and whether it is inside it.
local function toCanvas(position: Vector2): (number, number, boolean)
	local relative = (position - canvas.AbsolutePosition) / canvas.AbsoluteSize
	local inside = relative.X >= 0 and relative.X <= 1 and relative.Y >= 0 and relative.Y <= 1
	return math.clamp(relative.X, 0, 1), math.clamp(relative.Y, 0, 1), inside
end

local function flush()
	local stroke = activeStroke
	if stroke and #pending > 0 then
		DrawEvent:FireServer({ id = stroke.id, c = stroke.c, s = stroke.s, p = pending })
		pending = {}
	end
	sendTimer = 0
end

local function addPoint(x: number, y: number)
	local stroke = activeStroke
	if not stroke then
		return
	end
	table.insert(pending, x)
	table.insert(pending, y)
	renderer:addPoints(stroke.id, stroke.c, stroke.s, { x, y })
	stroke.lastX, stroke.lastY = x, y
	if #pending >= Config.MAX_NUMBERS_PER_PACKET then
		flush()
	end
end

local function endStroke()
	flush()
	activeStroke = nil
	activeInput = nil
end

-- Listening on UserInputService (not the canvas) means the layers on top of the
-- canvas can never swallow the press.
UserInputService.InputBegan:Connect(function(input)
	if activeStroke or not canDraw() or not Ui.isPress(input) then
		return
	end
	local point = Ui.pointerPosition(input)
	if picker:contains(point) then
		return
	end
	local x, y, inside = toCanvas(point)
	if not inside then
		return
	end
	picker:close()
	local colorInt = CanvasRenderer.toInt(paintColor())

	if tool == "fill" then
		local now = os.clock()
		if now - lastFillAt < FILL_INTERVAL then
			return
		end
		lastFillAt = now
		strokeCounter += 1
		renderer:fill(strokeCounter, colorInt, x, y)
		DrawEvent:FireServer({ id = strokeCounter, c = colorInt, f = { x, y } })
		Sounds.play("click", 0.5)
		return
	end

	strokeCounter += 1
	activeInput = input
	activeStroke = { id = strokeCounter, c = colorInt, s = selectedSize, lastX = x, lastY = y }
	pending = {}
	addPoint(x, y)
end)

UserInputService.InputChanged:Connect(function(input)
	local stroke = activeStroke
	if not stroke then
		return
	end
	local isMouseDrag = input.UserInputType == Enum.UserInputType.MouseMovement
		and (activeInput :: InputObject).UserInputType == Enum.UserInputType.MouseButton1
	if not isMouseDrag and input ~= activeInput then
		return
	end

	local x, y = toCanvas(Ui.pointerPosition(input))
	local dx = x - stroke.lastX
	local dy = (y - stroke.lastY) / Config.CANVAS_ASPECT
	if dx * dx + dy * dy >= Config.MIN_POINT_DISTANCE * Config.MIN_POINT_DISTANCE then
		addPoint(x, y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local stroke = activeStroke
	if not stroke or not (input.UserInputType == Enum.UserInputType.MouseButton1 or input == activeInput) then
		return
	end
	-- Finish exactly where the pointer was released.
	local x, y = toCanvas(Ui.pointerPosition(input))
	if x ~= stroke.lastX or y ~= stroke.lastY then
		addPoint(x, y)
	end
	endStroke()
end)

-- With the bucket, a paint-bucket icon sits next to the dot.
local cursorBucket = label({
	AnchorPoint = Vector2.new(0, 1),
	Size = UDim2.fromOffset(30, 30),
	Text = "🪣",
	Visible = false,
	Parent = cursorLayer,
})

local BUCKET_DOT = 0.008 -- canvas widths
local mouseHidden = false

RunService.RenderStepped:Connect(function()
	local point = Ui.pointerPosition()
	local x, y, inside = toCanvas(point)
	local overCanvas = canDraw()
		and UserInputService.MouseEnabled
		and (inside or activeStroke ~= nil)
		and not picker:contains(point)

	if overCanvas ~= mouseHidden then
		mouseHidden = overCanvas
		UserInputService.MouseIconEnabled = not overCanvas
	end
	cursorDot.Visible = overCanvas
	cursorBucket.Visible = overCanvas and tool == "fill"
	if overCanvas then
		local size = if tool == "fill" then BUCKET_DOT else Config.BRUSH_SIZES[selectedSize]
		cursorDot.Position = UDim2.fromScale(x, y)
		cursorDot.Size = UDim2.fromScale(size, size * Config.CANVAS_ASPECT)
		cursorDot.BackgroundColor3 = paintColor()
		cursorBucket.Position = UDim2.new(x, 4, y, -2)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if activeStroke then
		sendTimer += dt
		if sendTimer >= Config.SEND_INTERVAL then
			flush()
		end
	end
end)

-- Canvas updates from the server ----------------------------------------------------------------

DrawEvent.OnClientEvent:Connect(function(packet)
	if packet.f then
		renderer:fill(packet.id, packet.c, packet.f[1], packet.f[2])
	else
		renderer:addPoints(packet.id, packet.c, packet.s, packet.p)
	end
end)

CanvasEvent.OnClientEvent:Connect(function(action, id)
	if action == "clear" then
		renderer:clear()
	elseif action == "undo" then
		renderer:remove(id)
	end
end)

-- Players list ------------------------------------------------------------------------------------

-- Clicking someone in the player list opens this little menu to vote to kick them.
local kickMenu = Ui.panel({
	Size = UDim2.fromOffset(270, 120),
	Visible = false,
	ZIndex = 20,
	Parent = game_,
}, { Ui.border(2, Theme.border) })
local kickMenuName = label({
	Position = UDim2.fromOffset(12, 10),
	Size = UDim2.new(1, -56, 0, 30),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextScaled = false,
	TextSize = 22,
	Text = "",
	Parent = kickMenu,
})
local kickMenuClose = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -8, 0, 8),
	Size = UDim2.fromOffset(32, 32),
	BackgroundTransparency = 1,
	Text = "✕",
	TextScaled = true,
	FontFace = Theme.heavy,
	TextColor3 = Theme.muted,
	Parent = kickMenu,
}, { Ui.pad(6) })
local kickButton = make("TextButton", {
	Position = UDim2.fromOffset(12, 56),
	Size = UDim2.new(1, -24, 0, 50),
	BackgroundColor3 = Theme.red,
	AutoButtonColor = false,
	Text = "👢 Vote to kick",
	TextScaled = true,
	FontFace = Theme.heavy,
	TextColor3 = Theme.white,
	Parent = kickMenu,
}, { Ui.corner(8), Ui.pad(10, 8) })
Ui.hoverable(kickButton)
local kickTarget: number? = nil

local function closeKickMenu()
	kickMenu.Visible = false
	kickTarget = nil
end

local function openKickMenu(userId: number, name: string, row: GuiObject)
	if kickTarget == userId then
		closeKickMenu()
		return
	end
	kickTarget = userId
	kickMenuName.Text = name
	-- Beside the player's row, in the game area's own (unzoomed) units.
	local y = (row.AbsolutePosition.Y - game_.AbsolutePosition.Y) / gameScale.Scale
	kickMenu.Position = UDim2.fromOffset(292, math.clamp(y, 0, DESIGN.Y - 130))
	kickMenu.Visible = true
	Ui.pop(kickMenu, 0.6, 0.25)
end

kickMenuClose.Activated:Connect(closeKickMenu)
-- The Report button: pick a player, then a reason. Reports are saved for the
-- game's owner; for anything serious, Roblox's own menu (☰ → Report) is the way.
local REPORT_REASONS = { "Inappropriate drawing", "Bad language", "Cheating or spamming", "Being mean" }
local reportMenu = Ui.panel({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromOffset(DESIGN.X - 70, 146),
	Size = UDim2.fromOffset(380, 100),
	Visible = false,
	ZIndex = 20,
	Parent = game_,
}, { Ui.border(2, Theme.border), Ui.pad(12) })
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = reportMenu })

local function closeReportMenu()
	reportMenu.Visible = false
end

local function reportOption(text: string, order: number, color: Color3?): TextButton
	local option = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = color or Theme.rowAlt,
		AutoButtonColor = false,
		Text = text,
		TextScaled = true,
		FontFace = Theme.bold,
		TextColor3 = if color then Theme.white else Theme.text,
		LayoutOrder = order,
		Parent = reportMenu,
	}, { Ui.corner(8), Ui.pad(10, 9) })
	option.MouseEnter:Connect(function()
		option.BackgroundTransparency = 0.25
	end)
	option.MouseLeave:Connect(function()
		option.BackgroundTransparency = 0
	end)
	return option
end

local function fillReportMenu(title: string, options: { { text: string, color: Color3?, pick: () -> () } })
	clearChildren(reportMenu)
	label({ Size = UDim2.new(1, 0, 0, 30), Text = title, TextScaled = false, TextSize = 22, LayoutOrder = 0, Parent = reportMenu })
	for i, option in options do
		reportOption(option.text, i, option.color).Activated:Connect(option.pick)
	end
	reportMenu.Size = UDim2.fromOffset(380, 24 + 30 + #options * 52)
end

local function openReportMenu()
	local s = snapshot
	if reportMenu.Visible or not s then
		closeReportMenu()
		return
	end
	local options = {}
	for _, entry in s.players do
		if entry.userId ~= player.UserId then
			table.insert(options, {
				text = entry.name,
				pick = function()
					local reasons = {}
					for _, reason in REPORT_REASONS do
						table.insert(reasons, {
							text = reason,
							pick = function()
								VoteEvent:FireServer("report", entry.userId, reason)
								Sounds.play("click")
								closeReportMenu()
							end,
						})
					end
					table.insert(reasons, { text = "Cancel", color = Theme.muted, pick = closeReportMenu })
					fillReportMenu(`Why report {entry.name}?`, reasons)
				end,
			})
		end
	end
	if #options == 0 then
		table.insert(options, { text = "Nobody else is here yet", pick = closeReportMenu })
	end
	table.insert(options, { text = "Cancel", color = Theme.muted, pick = closeReportMenu })
	fillReportMenu("Report a player", options)
	reportMenu.Visible = true
	Ui.pop(reportMenu, 0.7, 0.25)
end

reportButton.Activated:Connect(function()
	Sounds.play("click")
	openReportMenu()
end)

voteKickButton.Activated:Connect(function()
	local s = snapshot
	if s and s.drawerUserId and not s.isDrawer and not s.votedOnDrawer then
		Sounds.play("click")
		VoteEvent:FireServer("kick", s.drawerUserId)
	end
end)

kickButton.Activated:Connect(function()
	if kickTarget then
		VoteEvent:FireServer("kick", kickTarget)
		Sounds.play("click")
	end
	closeKickMenu()
end)

type Row = {
	frame: Frame,
	rank: TextLabel,
	name: TextLabel,
	score: TextLabel,
	pencil: Frame,
	entry: any, -- the latest player info, for the kick menu
}

local rows: { [number]: Row } = {}

-- A skribbl.io player row: rank top-left, name and points centred, avatar on the right.
local function createRow(entry): Row
	local frame = make("Frame", {
		Size = UDim2.new(1, 0, 0, 68),
		BackgroundColor3 = Theme.white,
		BorderSizePixel = 0,
		Parent = playersList,
	})
	local rank = label({
		Position = UDim2.fromOffset(9, 6),
		Size = UDim2.fromOffset(44, 26),
		TextScaled = false,
		TextSize = 23,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = frame,
	})
	-- Name and points are centred in the space between the rank and the avatar.
	local name = label({
		Position = UDim2.new(0, 44, 0, 9),
		Size = UDim2.new(1, -118, 0, 26),
		TextScaled = false,
		TextSize = 23,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = true,
		Text = "",
		Parent = frame,
	})
	local score = label({
		Position = UDim2.new(0, 44, 0, 35),
		Size = UDim2.new(1, -118, 0, 22),
		TextScaled = false,
		TextSize = 20,
		FontFace = Theme.regular,
		Text = "",
		Parent = frame,
	})
	Ui.avatar(entry.userId, entry.name, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -2, 0.5, 0),
		Size = UDim2.fromOffset(66, 66),
		Parent = frame,
	})
	-- skribbl.io's pencil leans against the drawer's avatar.
	local pencil = Ui.pencil({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -68, 0.5, 2),
		Size = UDim2.fromOffset(17, 58),
		Visible = false,
		Parent = frame,
	})
	Ui.pop(frame, 0.7, 0.3)
	local row = { frame = frame, rank = rank, name = name, score = score, pencil = pencil, entry = entry }
	-- Click anyone else's row to vote to kick them.
	local clickArea = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
		Parent = frame,
	})
	clickArea.Activated:Connect(function()
		local current = row.entry
		if current.userId ~= player.UserId then
			Sounds.play("click", 0.5)
			openKickMenu(current.userId, current.name, frame)
		end
	end)
	return row
end

local function renderPlayers(list)
	local seen = {}
	for position, entry in list do
		seen[entry.userId] = true
		local row = rows[entry.userId] or createRow(entry)
		rows[entry.userId] = row
		row.entry = entry
		local isMe = entry.userId == player.UserId
		row.frame.LayoutOrder = position
		row.rank.Text = `#{position}`
		-- A small crown and the player's all-time match wins sit right after the name.
		local crowns = if (entry.wins or 0) > 0
			then ` <font size="17" color="#{Theme.crownText:ToHex()}">👑{entry.wins}</font>`
			else ""
		row.name.Text = escapeRichText(entry.name) .. (if isMe then " (You)" else "") .. crowns
		row.name.TextColor3 = if isMe then Theme.you else Theme.text
		row.score.Text = `{entry.score} points`
		row.pencil.Visible = entry.isDrawer
		local bg = if entry.guessed
			then Theme.guessedRow
			elseif entry.isDrawer then Theme.drawerRow
			elseif position % 2 == 0 then Theme.rowAlt
			else Theme.white
		if row.frame.BackgroundColor3 ~= bg then
			Ui.tween(row.frame, 0.3, { BackgroundColor3 = bg })
		end
	end
	for userId, row in rows do
		if not seen[userId] then
			row.frame:Destroy()
			rows[userId] = nil
		end
	end
end

-- Overlay screens -----------------------------------------------------------------------------------

local countdownLabel: TextLabel? = nil

local function overlayHeader(titleText: string, subtitleText: string?)
	overlayTitle.Text = titleText
	overlaySubtitle.Text = subtitleText or ""
end

-- Shows `gui` after `delay` seconds with a springy pop.
local function popLater(gui: GuiObject, delay: number, from: number?)
	Ui.scaleOf(gui).Scale = 0
	task.delay(delay, function()
		if gui.Parent then
			Ui.pop(gui, from or 0.3)
		end
	end)
end

local function wobblingEmoji(emoji: string)
	local icon = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.5, 0.55),
		Text = emoji,
		Rotation = -12,
		Parent = overlayBody,
	}, { Ui.maxText(96) })
	Ui.loop(icon, 0.9, { Rotation = 12 })
end

local function renderWordChoices()
	local choices = wordChoices
	if not choices then
		return
	end
	local row = make("Frame", {
		Position = UDim2.fromScale(0, 0.12),
		Size = UDim2.fromScale(1, 0.22),
		BackgroundTransparency = 1,
		Parent = overlayBody,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0.03, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for index, word in choices do
		local choice = Ui.overlayButton({
			Text = word,
			Size = UDim2.fromScale(0.24, 1),
			LayoutOrder = index,
			Parent = row,
		})
		popLater(choice, (index - 1) * 0.1)
		choice.Activated:Connect(function()
			WordChoiceEvent:FireServer(index)
			wordChoices = nil
			chosenWord = word
			clearChildren(overlayBody)
			overlayHeader("Get ready to draw!", word)
			wobblingEmoji("✏️")
		end)
	end

	-- A small lock to the side: pay to draw any word you type.
	local lock = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.23),
		Size = UDim2.fromScale(0.08, 0.2),
		BackgroundColor3 = Theme.white,
		BackgroundTransparency = 1,
		Text = "🔒",
		TextScaled = true,
		AutoButtonColor = false,
		Parent = overlayBody,
	}, { Ui.square(), Ui.round(), Ui.border(2, Theme.white), Ui.pad(6) })
	label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 4),
		Size = UDim2.fromScale(1.6, 0.4),
		Text = `{ROBUX}{priceOf("customWord")} Custom`,
		TextColor3 = Theme.overlayText,
		Parent = lock,
	})
	popLater(lock, #choices * 0.1)
	Ui.hoverable(lock)
	lock.Activated:Connect(function()
		Sounds.play("click")
		-- The server asks for the Robux; the form opens once it's paid.
		ShopEvent:FireServer("customWord")
	end)
end

local function textField(placeholder: string, y: number): TextBox
	return make("TextBox", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, y),
		Size = UDim2.fromScale(0.5, 0.17),
		BackgroundColor3 = Theme.white,
		TextColor3 = Theme.text,
		PlaceholderText = placeholder,
		PlaceholderColor3 = Theme.muted,
		Text = "",
		FontFace = Theme.bold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = overlayBody,
	}, { Ui.corner(6), Ui.pad(10, 6), Ui.maxText(24) })
end

-- Once paid for, the drawer can type any word. The server checks it's allowed.
local function renderCustomForm()
	local word = textField("Type any word to draw", 0.06)

	local errorLabel = label({
		Position = UDim2.fromScale(0, 0.3),
		Size = UDim2.fromScale(1, 0.12),
		Text = "",
		TextColor3 = Theme.yellow,
		Parent = overlayBody,
	}, { Ui.maxText(22) })
	customError = errorLabel

	local use = Ui.overlayButton({
		Text = "Use word",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromScale(0.3, 0.2),
		Parent = overlayBody,
	})
	local back = Ui.overlayButton({
		Text = "Back",
		Position = UDim2.fromScale(0, 0.52),
		Size = UDim2.fromScale(0.16, 0.14),
		Parent = overlayBody,
	})

	local function submit()
		if string.match(word.Text, "%a") == nil then
			errorLabel.Text = "Type a word first."
			return
		end
		errorLabel.Text = "Checking..."
		WordChoiceEvent:FireServer({ word = word.Text })
	end
	use.Activated:Connect(submit)
	word.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
		end
	end)
	back.Activated:Connect(function()
		customForm = false
		render()
	end)
	task.defer(function()
		word:CaptureFocus()
	end)
end

local function renderTurnResults(lastTurn)
	local list = make("Frame", {
		Position = UDim2.fromScale(0.2, 0),
		Size = UDim2.fromScale(0.6, 1),
		BackgroundTransparency = 1,
		Parent = overlayBody,
	}, {
		make("UIListLayout", {
			Padding = UDim.new(0.02, 0),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	if #lastTurn.results == 0 then
		local nobody = title({ Size = UDim2.fromScale(1, 0.14), Text = "Nobody guessed it!", TextColor3 = Theme.overlayText, Parent = list }, { Ui.maxText(26) })
		popLater(nobody, 0.3)
		return
	end
	for i, result in lastTurn.results do
		if i > 7 then
			break
		end
		local resultRow = make("Frame", {
			Size = UDim2.fromScale(1, 0.12),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Parent = list,
		})
		title({
			Size = UDim2.fromScale(0.7, 1),
			Text = result.name .. (if result.isDrawer then " ✏️" else ""),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = resultRow,
		}, { Ui.maxText(24) })
		title({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.3, 1),
			Text = `+{result.points}`,
			TextColor3 = Theme.yellow,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = resultRow,
		}, { Ui.maxText(24) })
		popLater(resultRow, 0.2 + i * 0.08)
	end
end

local PODIUM = {
	{ place = 2, height = 0.42, color = Theme.silver, delay = 0.4 },
	{ place = 1, height = 0.58, color = Theme.gold, delay = 0.8 },
	{ place = 3, height = 0.3, color = Theme.bronze, delay = 0 },
}

local function renderPodium(winners)
	local row = make("Frame", {
		Position = UDim2.fromScale(0.1, 0),
		Size = UDim2.fromScale(0.8, 1),
		BackgroundTransparency = 1,
		Parent = overlayBody,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0.03, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for order, slot in PODIUM do
		local names, score, userId = {}, 0, nil
		for _, winner in winners do
			if winner.place == slot.place then
				table.insert(names, winner.name)
				score = winner.score
				userId = userId or winner.userId
			end
		end
		local column = make("Frame", {
			Size = UDim2.fromScale(0.3, 1),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = row,
		})
		if #names > 0 then
			-- The block grows up from the floor, carrying the winner's avatar and name on top.
			local block = make("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.fromScale(1, 0),
				BackgroundColor3 = slot.color,
				Parent = column,
			}, { Ui.corner(6) })
			title({
				Size = UDim2.fromScale(1, 0.6),
				Text = `#{slot.place}`,
				TextColor3 = Theme.outline,
				Parent = block,
			}, { Ui.maxText(40), Ui.pad(6) })
			label({
				Position = UDim2.fromScale(0, 0.55),
				Size = UDim2.fromScale(1, 0.3),
				Text = `{score} points`,
				TextColor3 = Theme.outline,
				Parent = block,
			}, { Ui.maxText(20), Ui.pad(4) })

			local plate = make("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -4),
				Size = UDim2.fromScale(1, 0.4),
				BackgroundTransparency = 1,
				Parent = column,
			})
			local avatar = Ui.avatar(userId, names[1], {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.1),
				Size = UDim2.fromScale(0.62, 0.6),
				Parent = plate,
			})
			Ui.square().Parent = avatar
			title({
				Position = UDim2.fromScale(0, 0.72),
				Size = UDim2.fromScale(1, 0.26),
				Text = (if slot.place == 1 then "👑 " else "") .. table.concat(names, " & "),
				Parent = plate,
			}, { Ui.maxText(22) })

			task.delay(slot.delay, function()
				Ui.tween(block, 0.6, { Size = UDim2.fromScale(1, slot.height) }, Enum.EasingStyle.Back)
				Ui.tween(plate, 0.6, { Position = UDim2.new(0.5, 0, 1 - slot.height, -4) }, Enum.EasingStyle.Back)
				if slot.place == 1 then
					task.delay(0.6, function()
						Ui.pulse(avatar, 1.3)
					end)
				end
			end)
		end
	end
end

-- Once Roblox tells us the real prices, redraw the price labels.
table.insert(priceListeners, function()
	if snapshot then
		render()
	end
end)

local overlayKey: string? = nil
local overlayPhase: string? = nil
local overlayShown = true

local function setOverlayShown(show: boolean)
	if show == overlayShown then
		return
	end
	overlayShown = show
	if show then
		overlay.Visible = true
		overlay.BackgroundTransparency = 1
		Ui.tween(overlay, 0.25, { BackgroundTransparency = Theme.overlayTransparency })
	else
		Ui.tween(overlay, 0.25, { BackgroundTransparency = 1 })
		Ui.tween(overlayContent, 0.25, { Position = UDim2.fromScale(0, -1) }, Enum.EasingStyle.Back, Enum.EasingDirection.In).Completed:Connect(
			function()
				if not overlayShown then
					overlay.Visible = false
				end
			end
		)
	end
end

local function buildOverlay(s)
	local key = if s.phase == "Waiting"
		then `Waiting{#s.players}`
		elseif s.phase == "Choosing" then `Choosing{s.drawerUserId}{if wordChoices then "pick" else ""}{if customForm then "custom" else ""}{chosenWord or ""}`
		else `{s.phase}{s.phaseEndsAt}`
	if key == overlayKey then
		return
	end
	overlayKey = key
	local newPhase = s.phase ~= overlayPhase
	overlayPhase = s.phase

	setOverlayShown(s.phase ~= "Drawing")
	if s.phase == "Drawing" then
		return
	end

	clearChildren(overlayBody)
	countdownLabel = nil
	if s.phase == "Waiting" then
		overlayHeader("Waiting for players...", `{#s.players}/{s.minPlayers} players - invite a friend!`)
		wobblingEmoji("✏️")
	elseif s.phase == "Starting" then
		overlayHeader("Get ready!", `{s.totalRounds} rounds - everyone draws once per round`)
		countdownLabel = title({
			Size = UDim2.fromScale(1, 0.8),
			Text = "",
			TextColor3 = Theme.yellow,
			Parent = overlayBody,
		}, { Ui.maxText(140) })
	elseif s.phase == "Choosing" then
		if s.isDrawer and wordChoices and customForm then
			overlayHeader("Custom word", "Draw anything you like - keep it family friendly!")
			renderCustomForm()
		elseif s.isDrawer and wordChoices then
			overlayHeader("Choose a word", "")
			renderWordChoices()
		elseif s.isDrawer then
			overlayHeader("Get ready to draw!", chosenWord or "")
			wobblingEmoji("✏️")
		else
			overlayHeader(`{s.drawerName} is choosing a word!`, "")
			local avatar = Ui.avatar(s.drawerUserId, s.drawerName, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.3),
				Size = UDim2.fromScale(0.4, 0.55),
				Rotation = -6,
				Parent = overlayBody,
			})
			Ui.square().Parent = avatar
			Ui.loop(avatar, 0.8, { Rotation = 6 })
		end
	elseif s.phase == "TurnEnd" and s.lastTurn then
		overlayTitle.RichText = true
		overlayHeader(`The word was {colorTag(Theme.yellow, `'{escapeRichText(s.lastTurn.word or "")}'`)}`, s.lastTurn.reason)
		renderTurnResults(s.lastTurn)
	elseif s.phase == "MatchEnd" and s.winners then
		overlayHeader("Results", "")
		renderPodium(s.winners)
	end
	if s.phase ~= "TurnEnd" then
		overlayTitle.RichText = false
	end

	if newPhase then
		overlayContent.Position = UDim2.fromScale(0, -0.6)
		Ui.tween(overlayContent, 0.45, { Position = UDim2.new() }, Enum.EasingStyle.Back)
	else
		overlayContent.Position = UDim2.new()
	end
end

-- Rendering the game state --------------------------------------------------------------------------

local TIMED_PHASES = { Starting = true, Choosing = true, Drawing = true, TurnEnd = true, MatchEnd = true }
local toolbarShown = false

function render()
	local s = snapshot
	if not s then
		return
	end

	roundLabel.Text = if s.round > 0 then `Round {s.round} of {s.totalRounds}` else "Waiting"
	-- This turn's word theme: shown in the top bar and on everyone's background.
	local theme = Themes.byId[s.theme] or Themes.byId.general
	themeLabel.Text = `{theme.emoji} {theme.name} words`
	applyTheme(theme.id)
	if s.myTheme and s.myTheme ~= myTheme then
		myTheme = s.myTheme
		showMyTheme()
	end
	if s.word and s.isDrawer then
		wordCaption.Text = "DRAW THIS"
		setWord(s.word, false, Theme.text)
	elseif s.word and s.wordIsFull then
		wordCaption.Text = if s.phase == "TurnEnd" then "THE WORD WAS" else "YOU GOT IT!"
		setWord(s.word, false, Theme.green)
	elseif s.word then
		wordCaption.Text = "GUESS THIS"
		setWord(s.word, true, Theme.text)
	else
		wordCaption.Text = "WAITING"
		setWord(nil, false, Theme.text)
	end

	renderPlayers(s.players)

	local canShop = s.phase == "Drawing" and not s.isDrawer
	if canShop ~= shopBar.Visible then
		shopBar.Visible = canShop
		if canShop then
			Ui.pop(shopBar, 0.8, 0.3)
		end
	end
	for item, priceLabel in shopPriceLabels do
		local owned = s.credits and s.credits[item] or 0
		priceLabel.Text = if owned > 0 then `Use ({owned})` else `{ROBUX}{priceOf(item)}`
	end

	-- "Vote Kick: 1/3" votes against whoever is drawing; greyed out when it can't be used.
	local canVoteKick = s.drawerUserId ~= nil and not s.isDrawer and not s.votedOnDrawer
	voteKickButton.Text = `Vote Kick: {s.drawerKickVotes or 0}/{s.kickVotesNeeded or 2}`
	voteKickButton.BackgroundColor3 = if canVoteKick then Color3.fromRGB(255, 150, 30) else Color3.fromRGB(200, 190, 175)

	local canRate = s.phase == "Drawing" and not s.isDrawer and not ratedThisTurn
	if canRate ~= rateBar.Visible then
		rateBar.Visible = canRate
		if canRate then
			Ui.pop(rateBar, 0.7, 0.3)
		end
	end
	if kickTarget and not rows[kickTarget] then
		closeKickMenu() -- they left
	end

	if s.canDraw ~= toolbarShown then
		toolbarShown = s.canDraw
		toolbar.Visible = s.canDraw
		if s.canDraw then
			Ui.pop(toolbar, 0.7, 0.3)
		end
	end
	if not s.canDraw then
		picker:close()
		if activeStroke then
			endStroke()
		end
	end
	guessBox.PlaceholderText = if s.phase == "Drawing" and (s.isDrawer or s.wordIsFull)
		then "Chat (only players who guessed see this)"
		else "Type your guess here..."

	buildOverlay(s)
end

local function countHidden(word: string?): number
	local _, count = string.gsub(word or "", "_", "")
	return count
end

-- Sounds and effects for whatever changed between two snapshots.
local function celebrate(old, new)
	if not old then
		return
	end

	local sameTurn = old.phase == new.phase and old.drawerUserId == new.drawerUserId
	if new.phase ~= old.phase then
		if new.phase == "Drawing" then
			Sounds.play("click")
			Effects.floatText(if new.isDrawer then "Draw!" else "Guess!", Theme.yellow, Effects.centreOf(canvas), 72)
		elseif new.phase == "TurnEnd" then
			Sounds.play(if new.lastTurn and new.lastTurn.everyoneGuessed then "correct" else "timeUp")
		elseif new.phase == "MatchEnd" then
			Sounds.play("victory")
			Effects.confetti(110)
			task.delay(0.8, Effects.confetti, 70)
		elseif new.phase == "Starting" then
			Sounds.play("yourTurn", 0.6)
		end
	end

	-- A hint letter appeared.
	if sameTurn and new.phase == "Drawing" and not new.wordIsFull and countHidden(new.word) < countHidden(old.word) then
		Ui.pulse(wordRow, 1.3)
		Sounds.play("click")
	end

	local before = {}
	for _, entry in old.players do
		before[entry.userId] = entry
	end
	for _, entry in new.players do
		local previous = before[entry.userId]
		local row = rows[entry.userId]
		if previous and row then
			local gained = entry.score - previous.score
			if gained > 0 then
				Ui.pulse(row.frame, 1.05)
				Effects.floatText(`+{gained}`, Theme.green, Effects.centreOf(row.frame), 28)
			end
			if entry.guessed and not previous.guessed then
				if entry.userId == player.UserId then
					Sounds.play("correct")
					Ui.pulse(wordArea, 1.2)
					Effects.floatText(`Nice! +{gained}`, Theme.green, Effects.centreOf(canvas), 56)
				else
					Sounds.play("correct", 0.4)
				end
			end
		end
	end
end

StateEvent.OnClientEvent:Connect(function(newSnapshot)
	local previous = snapshot
	snapshot = newSnapshot
	if newSnapshot.phase ~= "Choosing" then
		wordChoices = nil
		chosenWord = nil
		customForm = false
	end
	if newSnapshot.phase ~= "Drawing" then
		ratedThisTurn = false
	end
	render()
	-- Wait a frame so freshly reordered rows have their final positions.
	task.defer(celebrate, previous, newSnapshot)
end)

WordChoiceEvent.OnClientEvent:Connect(function(options)
	-- A custom word was paid for (or unlocked): show the form.
	if typeof(options) == "table" and options.custom then
		customForm = true
		Sounds.play("yourTurn", 0.6)
		render()
		return
	end
	-- The server turned down a custom word.
	if typeof(options) == "table" and options.error then
		local errorLabel = customError
		if errorLabel and errorLabel.Parent then
			errorLabel.Text = options.error
			Ui.shake(errorLabel, 4)
		end
		Sounds.play("tick")
		return
	end
	wordChoices = options
	if options then
		Sounds.play("yourTurn")
	end
	render()
end)

-- Someone bought a nuke: a flash, a shake and a big boom over the canvas.
ShopEvent.OnClientEvent:Connect(function(effect)
	if effect ~= "nuke" then
		return
	end
	local flash = canvasLayer("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 230, 150),
		BackgroundTransparency = 0,
		ZIndex = 6,
	}, { Ui.corner(4) })
	Ui.tween(flash, 0.8, { BackgroundTransparency = 1 })
	task.delay(0.9, function()
		flash:Destroy()
	end)
	Ui.shake(canvasArea, 4)
	Effects.floatText("💥", Theme.white, Effects.centreOf(canvas), 140)
	Sounds.play("timeUp", 0.7)
end)

-- Timer ------------------------------------------------------------------------------------------------

local lastSecond: number? = nil

RunService.RenderStepped:Connect(function()
	local s = snapshot
	if not (s and TIMED_PHASES[s.phase]) then
		timerLabel.Text = ""
		lastSecond = nil
		return
	end
	local remaining = math.max(0, math.ceil(s.phaseEndsAt - workspace:GetServerTimeNow()))
	if remaining == lastSecond then
		return
	end
	lastSecond = remaining
	timerLabel.Text = tostring(remaining)

	local hurry = s.phase == "Drawing" and remaining <= 10 and remaining > 0
	timerLabel.TextColor3 = if hurry then Theme.red else Theme.text
	if hurry then
		Sounds.play("tick")
		Ui.pulse(clock, 1.15)
		Ui.shake(clock, 12)
	end

	local countdown = countdownLabel
	if s.phase == "Starting" and countdown and remaining > 0 then
		countdown.Text = tostring(remaining)
		Ui.pop(countdown, 1.8, 0.3)
		Sounds.play("tick")
	end
end)

-- Entrance -----------------------------------------------------------------------------------------------

local function slideIn(gui: GuiObject, from: UDim2, delay: number)
	local target = gui.Position
	gui.Position = target + from
	task.delay(delay, function()
		Ui.tween(gui, 0.6, { Position = target }, Enum.EasingStyle.Back)
	end)
end

slideIn(logo, UDim2.fromScale(0, -0.15), 0)
slideIn(topBar, UDim2.fromScale(0, -0.25), 0.05)
slideIn(playersScroller, UDim2.fromScale(-0.25, 0), 0.12)
slideIn(chatPanel, UDim2.fromScale(0.3, 0), 0.18)
popLater(canvasArea, 0.25, 0.6)

-- Everything is wired up; ask the server for the current state and drawing.
CanvasEvent:FireServer("ready")
