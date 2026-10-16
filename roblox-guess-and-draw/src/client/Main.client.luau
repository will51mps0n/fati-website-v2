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
local CanvasRenderer = require(script.Parent:WaitForChild("CanvasRenderer"))
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
	-- Lay out in full-window pixels, the same space as GetMouseLocation(), so the
	-- pointer maps onto the canvas with no topbar offset.
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

local tiled = Config.BACKGROUND_TILE ~= ""
if tiled or Config.BACKGROUND_IMAGE ~= "" then
	local tile = Config.BACKGROUND_TILE_SIZE
	local image = make("ImageLabel", {
		-- A tiled image is one tile larger than the screen so it can scroll seamlessly.
		Size = if tiled then UDim2.new(1, tile, 1, tile) else UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = if tiled then Config.BACKGROUND_TILE else Config.BACKGROUND_IMAGE,
		ScaleType = if tiled then Enum.ScaleType.Tile else Enum.ScaleType.Crop,
		TileSize = UDim2.fromOffset(tile, tile),
		Parent = background,
	})
	if tiled and Config.BACKGROUND_SCROLL_SPEED > 0 then
		RunService.RenderStepped:Connect(function()
			local offset = (os.clock() * Config.BACKGROUND_SCROLL_SPEED) % tile
			image.Position = UDim2.fromOffset(-offset, -offset)
		end)
	end
end

local root = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 1,
	Parent = screen,
}, {
	-- Keep the game clear of Roblox's topbar buttons.
	make("UIPadding", { PaddingTop = UDim.new(0, GuiService:GetGuiInset().Y) }),
})

local effectsLayer = make("Frame", {
	Name = "Effects",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 10,
	Parent = screen,
})
Effects.init(effectsLayer)

-- Like skribbl.io's fixed-width page, the whole game sits in one centred box. It is
-- designed at 1500x889 pixels and shrinks to fit smaller screens; `box` turns
-- design-pixel rectangles into positions and sizes inside it.
local DESIGN = Vector2.new(1500, 889)

local game_ = make("Frame", {
	Name = "Game",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -24, 1, -16),
	BackgroundTransparency = 1,
	Parent = root,
}, {
	make("UIAspectRatioConstraint", { AspectRatio = DESIGN.X / DESIGN.Y }),
	make("UISizeConstraint", { MaxSize = DESIGN }),
})

local function box(x: number, y: number, width: number, height: number): (UDim2, UDim2)
	return UDim2.fromScale(x / DESIGN.X, y / DESIGN.Y), UDim2.fromScale(width / DESIGN.X, height / DESIGN.Y)
end

-- Logo -----------------------------------------------------------------------------------

local LOGO_TEXT = "Guess & Draw"
local logoPosition, logoSize = box(4, 0, 470, 72)
local logo = make("Frame", {
	Position = logoPosition,
	Size = logoSize,
	BackgroundTransparency = 1,
	Parent = game_,
})
-- A dark copy behind the letters gives the chunky drop shadow.
label({
	Position = UDim2.fromOffset(3, 4),
	Size = UDim2.fromScale(0.86, 1),
	Text = LOGO_TEXT,
	FontFace = Theme.logo,
	TextColor3 = Theme.outline,
	TextTransparency = 0.35,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = logo,
}, { Ui.textOutline(3, Theme.outline) })
label({
	Size = UDim2.fromScale(0.86, 1),
	RichText = true,
	Text = rainbowText(LOGO_TEXT),
	FontFace = Theme.logo,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = logo,
}, { Ui.textOutline(3, Theme.outline) })
local logoPencil = label({
	Position = UDim2.fromScale(0.86, 0),
	Size = UDim2.fromScale(0.14, 1),
	Text = "✏️",
	Rotation = 10,
	Parent = logo,
})
Ui.loop(logoPencil, 1.2, { Rotation = -10 })

-- Top bar: alarm clock, round, word, sound toggle ----------------------------------------

local topPosition, topSize = box(0, 80, 1500, 54)
local topBar = Ui.panel({ Position = topPosition, Size = topSize, Parent = game_ })

-- A little alarm clock drawn from circles, bigger than the bar like skribbl.io's.
local clock = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 4, 0.5, 0),
	Size = UDim2.fromScale(1, 1.35),
	BackgroundTransparency = 1,
	Parent = topBar,
}, { Ui.square() })

for _, side in { -1, 1 } do
	make("Frame", { -- bell
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + side * 0.32, 0.14),
		Size = UDim2.fromScale(0.32, 0.32),
		BackgroundColor3 = Theme.white,
		ZIndex = 1,
		Parent = clock,
	}, { Ui.round(), Ui.border(3, Theme.outline) })
	make("Frame", { -- leg
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + side * 0.26, 0.92),
		Size = UDim2.fromScale(0.07, 0.2),
		Rotation = side * -35,
		BackgroundColor3 = Theme.outline,
		ZIndex = 1,
		Parent = clock,
	}, { Ui.round() })
end

local clockFace = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.54),
	Size = UDim2.fromScale(0.84, 0.84),
	BackgroundColor3 = Theme.white,
	ZIndex = 2,
	Parent = clock,
}, { Ui.round(), Ui.border(3, Theme.outline) })

local timerLabel = label({
	Size = UDim2.fromScale(1, 1),
	FontFace = Theme.heavy,
	Text = "",
	Parent = clockFace,
}, { Ui.pad(7) })

local roundLabel = label({
	Position = UDim2.fromScale(0.06, 0.2),
	Size = UDim2.fromScale(0.22, 0.6),
	FontFace = Theme.bold,
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = topBar,
}, { Ui.maxText(24) })

local wordArea = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromScale(0.44, 1),
	BackgroundTransparency = 1,
	Parent = topBar,
})

local wordCaption = label({
	Position = UDim2.fromScale(0, 0.1),
	Size = UDim2.fromScale(1, 0.3),
	FontFace = Theme.mono,
	Text = "",
	Parent = wordArea,
}, { Ui.maxText(15) })

local wordLabel = label({
	Position = UDim2.fromScale(0, 0.38),
	Size = UDim2.fromScale(1, 0.56),
	FontFace = Theme.monoBold,
	Text = "",
	Parent = wordArea,
}, { Ui.maxText(28) })

-- Where skribbl.io has its settings gear: a sound on/off switch.
local soundButton = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.fromScale(1, 0.8),
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

-- Left: players ----------------------------------------------------------------------------

local MAIN_TOP = 142
local CANVAS_HEIGHT = 675

local playersPosition, playersSize = box(0, MAIN_TOP, 230, CANVAS_HEIGHT)
local playersList = make("ScrollingFrame", {
	Position = playersPosition,
	Size = playersSize,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = game_,
}, {
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
})

-- Centre: canvas and toolbar ------------------------------------------------------------------

local canvasPosition, canvasSize = box(238, MAIN_TOP, 900, CANVAS_HEIGHT)
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
	BackgroundColor3 = Theme.overlay,
	BackgroundTransparency = 0.2,
	ClipsDescendants = true,
	ZIndex = 3,
}, { Ui.corner(4) })

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
local toolbarPosition, toolbarSize = box(238, MAIN_TOP + CANVAS_HEIGHT + 8, 900, 64)
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
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

-- Right: chat ----------------------------------------------------------------------------------

local chatPosition, chatSize = box(1146, MAIN_TOP, 354, CANVAS_HEIGHT)
local chatPanel = Ui.panel({ Position = chatPosition, Size = chatSize, Parent = game_ })

local chatLog = make("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -50),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = chatPanel,
}, {
	-- New messages stack up from the bottom, like skribbl.io.
	make("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
	}),
})

local guessBorder = Ui.border(1, Theme.border)
local guessBox = make("TextBox", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 6, 1, -6),
	Size = UDim2.new(1, -12, 0, 36),
	BackgroundColor3 = Theme.white,
	TextColor3 = Theme.text,
	PlaceholderText = "Type your guess here...",
	PlaceholderColor3 = Theme.muted,
	Text = "",
	FontFace = Theme.regular,
	TextSize = 17,
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

local selectedColor = 1
local selectedSize = Config.DEFAULT_BRUSH_SIZE
local erasing = false

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
		TextSize = 17,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = if style.bold then Theme.bold else Theme.regular,
		TextColor3 = style.text,
		TextTransparency = 1,
		BackgroundColor3 = style.bg or (if chatOrder % 2 == 0 then Theme.rowAlt else Theme.white),
		BackgroundTransparency = 0,
		LayoutOrder = chatOrder,
		Parent = chatLog,
	}, { Ui.pad(6, 5) })
	Ui.tween(line, 0.2, { TextTransparency = 0 })

	if message.kind == "close" then
		Sounds.play("tick")
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

	task.defer(function()
		chatLog.CanvasPosition = Vector2.new(0, chatLog.AbsoluteCanvasSize.Y)
	end)
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

local currentColor = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	LayoutOrder = 1,
	Parent = toolbar,
}, { Ui.square(), Ui.corner(6), Ui.border(3, Theme.white) })

-- 7 x 2 palette squares packed edge to edge.
local palette = make("Frame", {
	Size = UDim2.fromScale(7 * 32 / 900, 1),
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

local refreshToolbar: () -> ()

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
		selectedColor = index
		erasing = false
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
	label({ Size = UDim2.fromScale(1, 1), Text = icon, Parent = button }, { Ui.pad(10) })
	return button
end

local penButton = iconButton("✏️", 1)
local eraserButton = iconButton("🧽", 2)
local undoButton = iconButton("↩️", 3)
local clearButton = iconButton("🗑️", 4)

penButton.Activated:Connect(function()
	erasing = false
	refreshToolbar()
end)
eraserButton.Activated:Connect(function()
	erasing = true
	refreshToolbar()
end)
undoButton.Activated:Connect(function()
	CanvasEvent:FireServer("undo")
end)
clearButton.Activated:Connect(function()
	CanvasEvent:FireServer("clear")
end)

function refreshToolbar()
	currentColor.BackgroundColor3 = if erasing then Config.BACKGROUND_COLOR else Config.COLORS[selectedColor].color
	for index, mark in swatchMarks do
		mark.Visible = not erasing and index == selectedColor
	end
	for index, sizeButton in sizeButtons do
		sizeButton.BackgroundColor3 = if index == selectedSize then Theme.selected else Theme.white
	end
	penButton.BackgroundColor3 = if erasing then Theme.white else Theme.selected
	eraserButton.BackgroundColor3 = if erasing then Theme.selected else Theme.white
end

refreshToolbar()

-- Drawing input -----------------------------------------------------------------------------------

local strokeCounter = 0
local activeStroke: { id: number, c: number, s: number, lastX: number, lastY: number }? = nil
local activeInput: InputObject? = nil
local pending: { number } = {}
local sendTimer = 0

local function canDraw(): boolean
	return snapshot ~= nil and snapshot.canDraw == true
end

-- Pointer position in full-window pixels, the space the ScreenGui is laid out in.
local function pointerPosition(input: InputObject?): Vector2
	if input and input.UserInputType == Enum.UserInputType.Touch then
		-- Touch positions are measured from below the topbar; shift them into window space.
		return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
	end
	return UserInputService:GetMouseLocation()
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

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Listening on UserInputService (not the canvas) means the layers on top of the
-- canvas can never swallow the press.
UserInputService.InputBegan:Connect(function(input)
	if activeStroke or not canDraw() or not isPress(input) then
		return
	end
	local x, y, inside = toCanvas(pointerPosition(input))
	if not inside then
		return
	end
	strokeCounter += 1
	activeInput = input
	activeStroke = {
		id = strokeCounter,
		c = if erasing then 0 else selectedColor,
		s = selectedSize,
		lastX = x,
		lastY = y,
	}
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

	local x, y = toCanvas(pointerPosition(input))
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
	local x, y = toCanvas(pointerPosition(input))
	if x ~= stroke.lastX or y ~= stroke.lastY then
		addPoint(x, y)
	end
	endStroke()
end)

local mouseHidden = false

RunService.RenderStepped:Connect(function()
	local x, y, inside = toCanvas(UserInputService:GetMouseLocation())
	local showDot = canDraw() and UserInputService.MouseEnabled and (inside or activeStroke ~= nil)

	if showDot ~= mouseHidden then
		mouseHidden = showDot
		UserInputService.MouseIconEnabled = not showDot
	end
	cursorDot.Visible = showDot
	if showDot then
		local size = Config.BRUSH_SIZES[selectedSize]
		cursorDot.Position = UDim2.fromScale(x, y)
		cursorDot.Size = UDim2.fromScale(size, size * Config.CANVAS_ASPECT)
		cursorDot.BackgroundColor3 = if erasing then Config.BACKGROUND_COLOR else Config.COLORS[selectedColor].color
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
	renderer:addPoints(packet.id, packet.c, packet.s, packet.p)
end)

CanvasEvent.OnClientEvent:Connect(function(action, id)
	if action == "clear" then
		renderer:clear()
	elseif action == "undo" then
		renderer:removeStroke(id)
	end
end)

-- Players list ------------------------------------------------------------------------------------

type Row = {
	frame: Frame,
	rank: TextLabel,
	name: TextLabel,
	score: TextLabel,
	pencil: TextLabel,
}

local rows: { [number]: Row } = {}

-- A skribbl.io player row: rank top-left, name and points centred, avatar on the right.
local function createRow(entry): Row
	local frame = make("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = Theme.white,
		BorderSizePixel = 0,
		Parent = playersList,
	})
	local rank = label({
		Position = UDim2.fromOffset(7, 5),
		Size = UDim2.fromOffset(40, 20),
		TextScaled = false,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = frame,
	})
	local name = label({
		Position = UDim2.new(0, 34, 0, 8),
		Size = UDim2.new(1, -94, 0, 20),
		TextScaled = false,
		TextSize = 16,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Parent = frame,
	})
	local score = label({
		Position = UDim2.new(0, 34, 0, 28),
		Size = UDim2.new(1, -94, 0, 18),
		TextScaled = false,
		TextSize = 14,
		FontFace = Theme.regular,
		Text = "",
		Parent = frame,
	})
	Ui.avatar(entry.userId, entry.name, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(50, 50),
		Parent = frame,
	})
	local pencil = label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -54, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		Text = "✏️",
		Visible = false,
		Parent = frame,
	})
	Ui.pop(frame, 0.7, 0.3)
	return { frame = frame, rank = rank, name = name, score = score, pencil = pencil }
end

local function renderPlayers(list)
	local seen = {}
	for position, entry in list do
		seen[entry.userId] = true
		local row = rows[entry.userId] or createRow(entry)
		rows[entry.userId] = row
		local isMe = entry.userId == player.UserId
		row.frame.LayoutOrder = position
		row.rank.Text = `#{position}`
		row.name.Text = entry.name .. (if isMe then " (You)" else "")
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
			Size = UDim2.fromScale(0.26, 1),
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
		local nobody = title({ Size = UDim2.fromScale(1, 0.14), Text = "Nobody guessed it!", TextColor3 = Theme.red, Parent = list }, { Ui.maxText(26) })
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
			TextColor3 = Theme.green,
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
			if slot.place == 1 then
				label({
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.08),
					Size = UDim2.fromScale(0.4, 0.25),
					Text = "👑",
					Rotation = -10,
					Parent = plate,
				})
			end
			title({
				Position = UDim2.fromScale(0, 0.72),
				Size = UDim2.fromScale(1, 0.26),
				Text = table.concat(names, " & "),
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
		Ui.tween(overlay, 0.25, { BackgroundTransparency = 0.2 })
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
		elseif s.phase == "Choosing" then `Choosing{s.drawerUserId}{if wordChoices then "pick" else ""}{chosenWord or ""}`
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
		if s.isDrawer and wordChoices then
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

local SUPERSCRIPT = { "⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹" }

local function superscript(n: number): string
	return (string.gsub(tostring(n), "%d", function(digit)
		return SUPERSCRIPT[tonumber(digit) + 1]
	end))
end

-- "_ _ p _ e" followed by the letter count of each word, like skribbl.io's "Mac³".
local function formatWord(word: string, spaced: boolean): string
	local chars = {}
	local lengths = {}
	local current = 0
	for i = 1, #word do
		local char = string.sub(word, i, i)
		if char == " " then
			table.insert(chars, if spaced then "  " else " ")
			table.insert(lengths, superscript(current))
			current = 0
		else
			table.insert(chars, char)
			current += 1
		end
	end
	table.insert(lengths, superscript(current))
	return table.concat(chars, if spaced then " " else "") .. table.concat(lengths, " ")
end

local TIMED_PHASES = { Starting = true, Choosing = true, Drawing = true, TurnEnd = true, MatchEnd = true }
local toolbarShown = false

local function render()
	local s = snapshot
	if not s then
		return
	end

	roundLabel.Text = if s.round > 0 then `Round {s.round} of {s.totalRounds}` else "Waiting"
	wordLabel.TextColor3 = Theme.text
	if s.word and s.isDrawer then
		wordCaption.Text = "DRAW THIS"
		wordLabel.Text = formatWord(s.word, false)
	elseif s.word and s.wordIsFull then
		wordCaption.Text = if s.phase == "TurnEnd" then "THE WORD WAS" else "YOU GOT IT!"
		wordLabel.Text = formatWord(s.word, false)
		wordLabel.TextColor3 = Theme.green
	elseif s.word then
		wordCaption.Text = "GUESS THIS"
		wordLabel.Text = formatWord(s.word, true)
	else
		wordCaption.Text = "WAITING"
		wordLabel.Text = ""
	end

	renderPlayers(s.players)

	if s.canDraw ~= toolbarShown then
		toolbarShown = s.canDraw
		toolbar.Visible = s.canDraw
		if s.canDraw then
			Ui.pop(toolbar, 0.7, 0.3)
		end
	end
	if not s.canDraw and activeStroke then
		endStroke()
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
		Ui.pulse(wordLabel, 1.3)
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
	end
	render()
	-- Wait a frame so freshly reordered rows have their final positions.
	task.defer(celebrate, previous, newSnapshot)
end)

WordChoiceEvent.OnClientEvent:Connect(function(options)
	wordChoices = options
	if options then
		Sounds.play("yourTurn")
	end
	render()
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
slideIn(playersList, UDim2.fromScale(-0.25, 0), 0.12)
slideIn(chatPanel, UDim2.fromScale(0.3, 0), 0.18)
popLater(canvasArea, 0.25, 0.6)

-- Everything is wired up; ask the server for the current state and drawing.
CanvasEvent:FireServer("ready")
