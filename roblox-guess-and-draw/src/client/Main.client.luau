-- Builds the game screen, lets the drawer draw (streaming strokes to the server),
-- shows everyone else the drawing live, and handles guessing/chat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CanvasRenderer = require(script.Parent:WaitForChild("CanvasRenderer"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
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

-- Theme ------------------------------------------------------------------------

local Theme = {
	background = Color3.fromRGB(46, 78, 168),
	panel = Color3.fromRGB(255, 255, 255),
	panelAlt = Color3.fromRGB(240, 243, 250),
	text = Color3.fromRGB(28, 30, 42),
	muted = Color3.fromRGB(110, 116, 135),
	accent = Color3.fromRGB(255, 196, 0),
	correct = Color3.fromRGB(30, 160, 80),
	correctBg = Color3.fromRGB(214, 245, 222),
	close = Color3.fromRGB(205, 140, 0),
	drawerBg = Color3.fromRGB(255, 243, 205),
	insider = Color3.fromRGB(40, 130, 90),
	reveal = Color3.fromRGB(46, 78, 168),
	headingFont = Enum.Font.FredokaOne,
	bodyFont = Enum.Font.GothamMedium,
	boldFont = Enum.Font.GothamBold,
}

-- UI helpers ---------------------------------------------------------------------

local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

local function corner(radius: number?): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

local function pad(pixels: number): UIPadding
	local p = UDim.new(0, pixels)
	return make("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p })
end

local function maxText(size: number): UITextSizeConstraint
	return make("UITextSizeConstraint", { MaxTextSize = size })
end

local function label(props: { [string]: any }, children: { Instance }?): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = Theme.text,
		Font = Theme.bodyFont,
		TextScaled = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	return make("TextLabel", defaults, children)
end

local function button(props: { [string]: any }, children: { Instance }?): TextButton
	local defaults = {
		BackgroundColor3 = Theme.panelAlt,
		TextColor3 = Theme.text,
		Font = Theme.boldFont,
		TextScaled = true,
		AutoButtonColor = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	local list = children or {}
	table.insert(list, corner(8))
	return make("TextButton", defaults, list)
end

-- Screen layout ---------------------------------------------------------------------

local screen = make("ScreenGui", {
	Name = "GuessAndDraw",
	ResetOnSpawn = false,
	IgnoreGuiInset = false, -- keeps InputObject.Position and AbsolutePosition in the same space
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

local root = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Theme.background,
	BorderSizePixel = 0,
	Parent = screen,
})

-- Top bar: round, word, timer
local topBar = make("Frame", {
	Position = UDim2.fromScale(0.01, 0.015),
	Size = UDim2.fromScale(0.98, 0.09),
	BackgroundColor3 = Theme.panel,
	Parent = root,
}, { corner(12), pad(6) })

local roundLabel = label({
	Size = UDim2.fromScale(0.2, 1),
	Text = "",
	Font = Theme.headingFont,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = topBar,
}, { maxText(26) })

local wordLabel = label({
	Position = UDim2.fromScale(0.2, 0),
	Size = UDim2.fromScale(0.6, 1),
	Text = "",
	Font = Theme.headingFont,
	Parent = topBar,
}, { maxText(36) })

local timerLabel = label({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromScale(0.2, 1),
	Text = "",
	Font = Theme.headingFont,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = topBar,
}, { maxText(32) })

-- Left: players
local playersPanel = make("Frame", {
	Position = UDim2.fromScale(0.01, 0.12),
	Size = UDim2.fromScale(0.18, 0.865),
	BackgroundColor3 = Theme.panel,
	Parent = root,
}, { corner(12), pad(8) })

local playersList = make("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = playersPanel,
}, {
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})

-- Centre: canvas and toolbar
local centre = make("Frame", {
	Position = UDim2.fromScale(0.2, 0.12),
	Size = UDim2.fromScale(0.56, 0.865),
	BackgroundTransparency = 1,
	Parent = root,
})

local canvasArea = make("Frame", {
	Size = UDim2.fromScale(1, 0.83),
	BackgroundTransparency = 1,
	Parent = centre,
})

-- A CanvasGroup clips rotated children, which a plain Frame with ClipsDescendants doesn't.
local canvas = make("CanvasGroup", {
	Name = "Canvas",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Config.BACKGROUND_COLOR,
	Active = true,
	Parent = canvasArea,
}, {
	make("UIAspectRatioConstraint", { AspectRatio = Config.CANVAS_ASPECT }),
	corner(12),
})

local brushPreview = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 100000,
	Parent = canvas,
}, {
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
	make("UIStroke", { Color = Theme.muted, Thickness = 1 }),
})

local renderer = CanvasRenderer.new(canvas)

-- Overlay over the canvas for waiting / choosing / reveal / winners.
local overlay = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(20, 28, 60),
	BackgroundTransparency = 0.15,
	ZIndex = 10,
	Parent = canvasArea,
}, {
	make("UIAspectRatioConstraint", { AspectRatio = Config.CANVAS_ASPECT }),
	corner(12),
	pad(16),
})

local overlayTitle = label({
	Size = UDim2.fromScale(1, 0.2),
	Position = UDim2.fromScale(0, 0.06),
	TextColor3 = Color3.new(1, 1, 1),
	Font = Theme.headingFont,
	ZIndex = 11,
	Parent = overlay,
}, { maxText(44) })

local overlaySubtitle = label({
	Size = UDim2.fromScale(1, 0.1),
	Position = UDim2.fromScale(0, 0.27),
	TextColor3 = Color3.fromRGB(205, 215, 245),
	ZIndex = 11,
	Parent = overlay,
}, { maxText(24) })

local overlayBody = make("Frame", {
	Size = UDim2.fromScale(1, 0.55),
	Position = UDim2.fromScale(0, 0.42),
	BackgroundTransparency = 1,
	ZIndex = 11,
	Parent = overlay,
})

-- Below the canvas: drawing tools (drawer only) or a hint (guessers).
local toolbar = make("Frame", {
	Position = UDim2.fromScale(0, 0.85),
	Size = UDim2.fromScale(1, 0.15),
	BackgroundColor3 = Theme.panel,
	Visible = false,
	Parent = centre,
}, {
	corner(12),
	pad(6),
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0.015, 0),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local guessHint = label({
	Position = UDim2.fromScale(0, 0.85),
	Size = UDim2.fromScale(1, 0.15),
	Text = "",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Theme.headingFont,
	Parent = centre,
}, { maxText(26) })

-- Right: chat
local chatPanel = make("Frame", {
	Position = UDim2.fromScale(0.77, 0.12),
	Size = UDim2.fromScale(0.22, 0.865),
	BackgroundColor3 = Theme.panel,
	Parent = root,
}, { corner(12), pad(8) })

local chatLog = make("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -50),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = chatPanel,
}, {
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
})

local guessBox = make("TextBox", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 42),
	BackgroundColor3 = Theme.panelAlt,
	TextColor3 = Theme.text,
	PlaceholderText = "Type your guess here...",
	PlaceholderColor3 = Theme.muted,
	Text = "",
	Font = Theme.bodyFont,
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	Parent = chatPanel,
}, { corner(8), pad(8) })

-- Game state ----------------------------------------------------------------------

local snapshot: any = nil
local wordChoices: { string }? = nil
local chosenWord: string? = nil

local selectedColor = 1
local selectedSize = Config.DEFAULT_BRUSH_SIZE
local erasing = false

-- Chat ---------------------------------------------------------------------------------

local chatOrder = 0
local MAX_CHAT_LINES = 120

local chatColors = {
	system = Theme.muted,
	correct = Theme.correct,
	close = Theme.close,
	insider = Theme.insider,
	reveal = Theme.reveal,
}

local function addChatLine(message)
	chatOrder += 1
	local text = if message.name then `{message.name}: {message.text}` else message.text
	local isPlain = message.kind == "chat"
	label({
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextScaled = false,
		TextSize = 16,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = chatColors[message.kind] or Theme.text,
		Font = if isPlain then Theme.bodyFont else Theme.boldFont,
		LayoutOrder = chatOrder,
		Parent = chatLog,
	})

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

-- Toolbar --------------------------------------------------------------------------------

local colorButtons: { [number]: TextButton } = {}
local sizeButtons: { [number]: TextButton } = {}
local penButton: TextButton
local eraserButton: TextButton

local function highlight(target: GuiObject, on: boolean)
	local stroke = target:FindFirstChild("Selected") :: UIStroke?
	if stroke then
		stroke.Enabled = on
	end
end

local function selectionStroke(): UIStroke
	return make("UIStroke", {
		Name = "Selected",
		Color = Theme.accent,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Enabled = false,
	})
end

local function refreshToolbar()
	for index, colorButton in colorButtons do
		highlight(colorButton, not erasing and index == selectedColor)
	end
	for index, sizeButton in sizeButtons do
		highlight(sizeButton, index == selectedSize)
	end
	highlight(penButton, not erasing)
	highlight(eraserButton, erasing)
end

local colorGrid = make("Frame", {
	Size = UDim2.fromScale(0.4, 1),
	BackgroundTransparency = 1,
	LayoutOrder = 1,
	Parent = toolbar,
}, {
	make("UIGridLayout", {
		CellSize = UDim2.new(1 / 7, -4, 0.5, -4),
		CellPadding = UDim2.fromOffset(4, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

for index, entry in Config.COLORS do
	local colorButton = button({
		Name = entry.name,
		Text = "",
		BackgroundColor3 = entry.color,
		LayoutOrder = index,
		Parent = colorGrid,
	}, {
		make("UIStroke", { Color = Color3.fromRGB(190, 195, 210), Thickness = 1 }),
	})
	selectionStroke().Parent = colorButton
	colorButtons[index] = colorButton
	colorButton.Activated:Connect(function()
		selectedColor = index
		erasing = false
		refreshToolbar()
	end)
end

local sizeRow = make("Frame", {
	Size = UDim2.fromScale(0.22, 1),
	BackgroundTransparency = 1,
	LayoutOrder = 2,
	Parent = toolbar,
}, {
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}),
})

for index, size in Config.BRUSH_SIZES do
	local sizeButton = button({
		Text = "",
		Size = UDim2.new(1 / #Config.BRUSH_SIZES, -4, 1, 0),
		LayoutOrder = index,
		Parent = sizeRow,
	})
	local dotScale = math.clamp(size / Config.BRUSH_SIZES[#Config.BRUSH_SIZES], 0.15, 0.8)
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(dotScale, dotScale),
		BackgroundColor3 = Theme.text,
		Parent = sizeButton,
	}, {
		make("UIAspectRatioConstraint", { AspectRatio = 1 }),
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
	})
	selectionStroke().Parent = sizeButton
	sizeButtons[index] = sizeButton
	sizeButton.Activated:Connect(function()
		selectedSize = index
		refreshToolbar()
	end)
end

local toolRow = make("Frame", {
	Size = UDim2.fromScale(0.35, 1),
	BackgroundTransparency = 1,
	LayoutOrder = 3,
	Parent = toolbar,
}, {
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local function toolButton(text: string, order: number): TextButton
	local toolButtonInstance = button({
		Text = text,
		Size = UDim2.new(0.25, -4, 1, 0),
		LayoutOrder = order,
		Parent = toolRow,
	}, { maxText(18), pad(4) })
	selectionStroke().Parent = toolButtonInstance
	return toolButtonInstance
end

penButton = toolButton("✏️ Pen", 1)
eraserButton = toolButton("🧽 Eraser", 2)
local undoButton = toolButton("↩️ Undo", 3)
local clearButton = toolButton("🗑️ Clear", 4)

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

refreshToolbar()

-- Drawing input ----------------------------------------------------------------------------

local strokeCounter = 0
local activeStroke: { id: number, c: number, s: number, lastX: number, lastY: number }? = nil
local activeInput: InputObject? = nil
local pending: { number } = {}
local sendTimer = 0

local function canDraw(): boolean
	return snapshot ~= nil and snapshot.canDraw == true
end

local function toCanvas(position: Vector3): (number, number)
	local relative = (Vector2.new(position.X, position.Y) - canvas.AbsolutePosition) / canvas.AbsoluteSize
	return math.clamp(relative.X, 0, 1), math.clamp(relative.Y, 0, 1)
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

canvas.InputBegan:Connect(function(input)
	if activeStroke or not canDraw() or not isPress(input) then
		return
	end
	strokeCounter += 1
	activeInput = input
	activeStroke = {
		id = strokeCounter,
		c = if erasing then 0 else selectedColor,
		s = selectedSize,
		lastX = 0,
		lastY = 0,
	}
	pending = {}
	local x, y = toCanvas(input.Position)
	addPoint(x, y)
end)

UserInputService.InputChanged:Connect(function(input)
	local isMove = input.UserInputType == Enum.UserInputType.MouseMovement
		or (input.UserInputType == Enum.UserInputType.Touch and input == activeInput)
	if not isMove then
		return
	end

	local x, y = toCanvas(input.Position)
	if canDraw() then
		local size = Config.BRUSH_SIZES[selectedSize]
		brushPreview.Position = UDim2.fromScale(x, y)
		brushPreview.Size = UDim2.fromScale(size, size * Config.CANVAS_ASPECT)
	end

	local stroke = activeStroke
	if not stroke then
		return
	end
	local dx = x - stroke.lastX
	local dy = (y - stroke.lastY) / Config.CANVAS_ASPECT
	if dx * dx + dy * dy >= Config.MIN_POINT_DISTANCE * Config.MIN_POINT_DISTANCE then
		addPoint(x, y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not activeStroke then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input == activeInput then
		endStroke()
	end
end)

canvas.MouseEnter:Connect(function()
	brushPreview.Visible = canDraw()
end)
canvas.MouseLeave:Connect(function()
	brushPreview.Visible = false
end)

RunService.Heartbeat:Connect(function(dt)
	if activeStroke then
		sendTimer += dt
		if sendTimer >= Config.SEND_INTERVAL then
			flush()
		end
	end
end)

-- Canvas updates from the server --------------------------------------------------------------

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

-- Rendering the game state ------------------------------------------------------------------

local function formatWord(word: string, full: boolean): string
	if full then
		return string.upper(word)
	end
	local chars = {}
	local lengths = {}
	local current = 0
	for i = 1, #word do
		local char = string.sub(word, i, i)
		if char == " " then
			table.insert(chars, "  ")
			table.insert(lengths, current)
			current = 0
		else
			table.insert(chars, string.upper(char))
			current += 1
		end
	end
	table.insert(lengths, current)
	return `{table.concat(chars, " ")}   ({table.concat(lengths, ", ")})`
end

local function clearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function renderPlayers(list)
	clearChildren(playersList)
	for rank, entry in list do
		local isMe = entry.userId == player.UserId
		local row = make("Frame", {
			Size = UDim2.new(1, -6, 0, 46),
			BackgroundColor3 = if entry.isDrawer
				then Theme.drawerBg
				elseif entry.guessed then Theme.correctBg
				else Theme.panelAlt,
			LayoutOrder = rank,
			Parent = playersList,
		}, { corner(8), pad(6) })
		label({
			Size = UDim2.fromScale(0.2, 1),
			Text = `#{rank}`,
			Font = Theme.headingFont,
			TextColor3 = Theme.muted,
			Parent = row,
		}, { maxText(18) })
		label({
			Position = UDim2.fromScale(0.22, 0),
			Size = UDim2.fromScale(0.62, 0.55),
			Text = entry.name .. (if isMe then " (you)" else ""),
			Font = Theme.boldFont,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		}, { maxText(16) })
		label({
			Position = UDim2.fromScale(0.22, 0.55),
			Size = UDim2.fromScale(0.62, 0.45),
			Text = `{entry.score} pts`,
			TextColor3 = Theme.muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		}, { maxText(14) })
		label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.16, 1),
			Text = if entry.isDrawer then "✏️" elseif entry.guessed then "✅" else "",
			Parent = row,
		}, { maxText(20) })
	end
end

local function overlayText(title: string, subtitle: string?)
	overlayTitle.Text = title
	overlaySubtitle.Text = subtitle or ""
end

local function renderWordChoices()
	local choices = wordChoices
	if not choices then
		return
	end
	local row = make("Frame", {
		Size = UDim2.fromScale(1, 0.4),
		BackgroundTransparency = 1,
		Parent = overlayBody,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0.03, 0),
		}),
	})
	for index, word in choices do
		local choice = button({
			Text = word,
			Size = UDim2.fromScale(0.28, 1),
			BackgroundColor3 = Theme.accent,
			Font = Theme.headingFont,
			ZIndex = 12,
			Parent = row,
		}, { maxText(28), pad(8) })
		choice.Activated:Connect(function()
			WordChoiceEvent:FireServer(index)
			wordChoices = nil
			chosenWord = word
			clearChildren(overlayBody)
			overlayText("Get ready to draw!", word)
		end)
	end
end

local function renderTurnResults(lastTurn)
	local lines = {}
	for _, result in lastTurn.results do
		table.insert(lines, `{result.name}{if result.isDrawer then " ✏️" else ""}   +{result.points}`)
	end
	if #lines == 0 then
		table.insert(lines, "Nobody guessed it!")
	end
	label({
		Size = UDim2.fromScale(1, 1),
		Text = table.concat(lines, "\n"),
		TextColor3 = Color3.new(1, 1, 1),
		Font = Theme.boldFont,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 12,
		Parent = overlayBody,
	}, { maxText(22) })
end

local PODIUM = {
	{ place = 2, height = 0.55, medal = "🥈", color = Color3.fromRGB(190, 200, 215) },
	{ place = 1, height = 0.8, medal = "🥇", color = Theme.accent },
	{ place = 3, height = 0.4, medal = "🥉", color = Color3.fromRGB(215, 145, 90) },
}

local function renderPodium(winners)
	local row = make("Frame", {
		Size = UDim2.fromScale(0.8, 1),
		Position = UDim2.fromScale(0.1, 0),
		BackgroundTransparency = 1,
		Parent = overlayBody,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0.02, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for order, slot in PODIUM do
		local names, score = {}, 0
		for _, winner in winners do
			if winner.place == slot.place then
				table.insert(names, winner.name)
				score = winner.score
			end
		end
		local column = make("Frame", {
			Size = UDim2.fromScale(0.3, 1),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = row,
		})
		if #names > 0 then
			label({
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1 - slot.height),
				Size = UDim2.fromScale(1, 0.2),
				Text = table.concat(names, " & "),
				TextColor3 = Color3.new(1, 1, 1),
				Font = Theme.headingFont,
				ZIndex = 12,
				Parent = column,
			}, { maxText(24) })
			make("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.fromScale(1, slot.height),
				BackgroundColor3 = slot.color,
				ZIndex = 12,
				Parent = column,
			}, {
				corner(8),
				label({
					Size = UDim2.fromScale(1, 1),
					Text = `{slot.medal}\n{score} pts`,
					Font = Theme.headingFont,
					ZIndex = 13,
				}, { maxText(26), pad(6) }),
			})
		end
	end
end

local TIMED_PHASES = { Starting = true, Choosing = true, Drawing = true, TurnEnd = true, MatchEnd = true }

local function render()
	local s = snapshot
	if not s then
		return
	end

	roundLabel.Text = if s.round > 0 then `Round {s.round} of {s.totalRounds}` else "Guess & Draw"
	if s.word then
		wordLabel.Text = if s.isDrawer then `Draw: {string.upper(s.word)}` else formatWord(s.word, s.wordIsFull)
	elseif s.phase == "Choosing" then
		wordLabel.Text = if s.isDrawer then "Pick a word!" else `{s.drawerName} is choosing...`
	else
		wordLabel.Text = ""
	end

	renderPlayers(s.players)

	local drawing = s.phase == "Drawing"
	toolbar.Visible = s.canDraw
	brushPreview.Visible = brushPreview.Visible and s.canDraw
	if not s.canDraw and activeStroke then
		endStroke()
	end
	if drawing and not s.isDrawer then
		guessHint.Text = if s.wordIsFull then "You got it! Chat with others who guessed." else "Type your guess in the chat →"
	else
		guessHint.Text = ""
	end
	guessBox.PlaceholderText = if drawing and (s.isDrawer or s.wordIsFull)
		then "Chat (only players who guessed see this)"
		else "Type your guess here..."

	overlay.Visible = not drawing
	clearChildren(overlayBody)
	if s.phase == "Waiting" then
		overlayText("Waiting for players", `{#s.players}/{s.minPlayers} players - invite a friend!`)
	elseif s.phase == "Starting" then
		overlayText("Get ready!", `A new match of {s.totalRounds} rounds is starting`)
	elseif s.phase == "Choosing" then
		if s.isDrawer and wordChoices then
			overlayText("Your turn to draw!", "Choose a word")
			renderWordChoices()
		elseif s.isDrawer then
			overlayText("Get ready to draw!", chosenWord or "")
		else
			overlayText(`{s.drawerName} is choosing a word`, "Get ready to guess!")
		end
	elseif s.phase == "TurnEnd" and s.lastTurn then
		overlayText(`The word was "{s.lastTurn.word}"`, s.lastTurn.reason)
		renderTurnResults(s.lastTurn)
	elseif s.phase == "MatchEnd" and s.winners then
		overlayText("🏆 Match over! 🏆", "Final standings")
		renderPodium(s.winners)
	end
end

StateEvent.OnClientEvent:Connect(function(newSnapshot)
	snapshot = newSnapshot
	if newSnapshot.phase ~= "Choosing" then
		wordChoices = nil
		chosenWord = nil
	end
	render()
end)

WordChoiceEvent.OnClientEvent:Connect(function(options)
	wordChoices = options
	render()
end)

RunService.RenderStepped:Connect(function()
	local s = snapshot
	if s and TIMED_PHASES[s.phase] then
		local remaining = math.max(0, math.ceil(s.phaseEndsAt - workspace:GetServerTimeNow()))
		timerLabel.Text = `⏱ {remaining}`
		timerLabel.TextColor3 = if s.phase == "Drawing" and remaining <= 10 then Color3.fromRGB(220, 50, 50) else Theme.text
	else
		timerLabel.Text = ""
	end
end)

-- Everything is wired up; ask the server for the current state and drawing.
CanvasEvent:FireServer("ready")
