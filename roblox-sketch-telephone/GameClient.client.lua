--[[
	GameClient  (LocalScript)
	Put in: StarterPlayer > StarterPlayerScripts

	Builds the entire UI in code (you don't need to make any GUI by hand),
	and handles drawing, guessing, spectating and the reveal.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Renderer = require(ReplicatedStorage:WaitForChild("DrawingRenderer"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local StateEvent = remotes:WaitForChild("State")
local TaskEvent = remotes:WaitForChild("Task")
local RevealEvent = remotes:WaitForChild("Reveal")
local StrokeEvent = remotes:WaitForChild("Stroke")
local GuessEvent = remotes:WaitForChild("Guess")
local DoneEvent = remotes:WaitForChild("Done")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local FONT = Enum.Font.FredokaOne
local THEME = {
	bg = Color3.fromRGB(44, 62, 140),
	text = Color3.fromRGB(255, 255, 255),
	soft = Color3.fromRGB(205, 215, 255),
	accent = Color3.fromRGB(255, 205, 60),
	dark = Color3.fromRGB(30, 30, 40),
	green = Color3.fromRGB(60, 180, 90),
	red = Color3.fromRGB(220, 75, 75),
	gray = Color3.fromRGB(105, 112, 150),
}
local MIN_POINT_DISTANCE = 5 -- in 0..1000 canvas units; fewer points = less lag
local HOW_TO = "How to play: Everyone gets a secret word and draws it. Your sketchbook is passed on, "
	.. "and the next person guesses what you drew. Then the next person draws that guess... "
	.. "At the end, watch how each word changed along the way!"

---------------------------------------------------------------- UI helpers
local layoutCounter = 0

local function new(className, props, children)
	local inst = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(0, 8) })
end

local function label(parent, pos, size, str, maxSize)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Position = pos,
		Size = size,
		Text = str or "",
		Font = FONT,
		TextColor3 = THEME.text,
		TextScaled = true,
		Parent = parent,
	}, { new("UITextSizeConstraint", { MaxTextSize = maxSize or 36 }) })
end

local function button(parent, size, str, color)
	layoutCounter += 1
	return new("TextButton", {
		Size = size,
		BackgroundColor3 = color,
		Text = str,
		Font = FONT,
		TextColor3 = THEME.text,
		TextScaled = true,
		LayoutOrder = layoutCounter,
		Parent = parent,
	}, {
		corner(),
		new("UITextSizeConstraint", { MaxTextSize = 28 }),
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
		}),
	})
end

local function row(parent, pos, size)
	return new("Frame", { BackgroundTransparency = 1, Position = pos, Size = size, Parent = parent }, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

local function makeCanvas(parent, pos, size)
	local holder = new("Frame", { BackgroundTransparency = 1, Position = pos, Size = size, Parent = parent })
	return new("Frame", {
		Name = "Canvas",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = holder,
	}, {
		new("UIAspectRatioConstraint", { AspectRatio = Config.CANVAS_ASPECT }),
		new("UIStroke", { Thickness = 4, Color = THEME.dark }),
	})
end

---------------------------------------------------------------- Build the screen
local inset = GuiService:GetGuiInset() -- height of Roblox's top bar

local gui = new("ScreenGui", {
	Name = "SketchTelephone",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})
new("Frame", {
	Name = "Background",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.bg,
	BorderSizePixel = 0,
	ZIndex = 0,
	Parent = gui,
})
local content = new("Frame", {
	Name = "Content",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, inset.Y + 6),
	Size = UDim2.new(1, -24, 1, -(inset.Y + 18)),
	Parent = gui,
})

-- Top bar: status | done counter | timer
local statusLabel = label(content, UDim2.fromScale(0, 0), UDim2.fromScale(0.6, 0.07), "", 30)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
local counterLabel = label(content, UDim2.fromScale(0.6, 0), UDim2.fromScale(0.25, 0.07), "", 26)
counterLabel.TextColor3 = THEME.soft
local timerLabel = label(content, UDim2.fromScale(0.85, 0), UDim2.fromScale(0.15, 0.07), "", 40)
timerLabel.TextXAlignment = Enum.TextXAlignment.Right

local panels = {}
local function panel(name)
	local frame = new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.08),
		Size = UDim2.fromScale(1, 0.92),
		Visible = false,
		Parent = content,
	})
	panels[name] = frame
	return frame
end

local function showPanel(name)
	for panelName, frame in panels do
		frame.Visible = panelName == name
	end
end

-- Lobby
local lobbyPanel = panel("Lobby")
local titleLabel = label(lobbyPanel, UDim2.fromScale(0, 0.04), UDim2.fromScale(1, 0.2), "Sketch Telephone", 90)
titleLabel.TextColor3 = THEME.accent
local lobbyMessage = label(lobbyPanel, UDim2.fromScale(0, 0.27), UDim2.fromScale(1, 0.08), "", 36)
local lobbyTimer = label(lobbyPanel, UDim2.fromScale(0, 0.37), UDim2.fromScale(1, 0.18), "", 100)
local howToLabel = label(lobbyPanel, UDim2.fromScale(0.1, 0.6), UDim2.fromScale(0.8, 0.3), HOW_TO, 26)
howToLabel.TextWrapped = true
howToLabel.TextColor3 = THEME.soft

-- Draw
local drawPanel = panel("Draw")
local drawPrompt = label(drawPanel, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.1), "", 44)
drawPrompt.TextColor3 = THEME.accent
local drawCanvas = makeCanvas(drawPanel, UDim2.fromScale(0, 0.11), UDim2.fromScale(1, 0.64))
local colorRow = row(drawPanel, UDim2.fromScale(0, 0.77), UDim2.fromScale(1, 0.1))
local toolRow = row(drawPanel, UDim2.fromScale(0, 0.89), UDim2.fromScale(1, 0.11))

-- Guess
local guessPanel = panel("Guess")
local guessTitle = label(guessPanel, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.1), "What is this drawing?", 44)
guessTitle.TextColor3 = THEME.accent
local guessCanvas = makeCanvas(guessPanel, UDim2.fromScale(0, 0.11), UDim2.fromScale(1, 0.66))
local guessRow = row(guessPanel, UDim2.fromScale(0, 0.81), UDim2.fromScale(1, 0.13))
layoutCounter += 1
local guessBox = new("TextBox", {
	Size = UDim2.fromScale(0.55, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	TextColor3 = THEME.dark,
	PlaceholderText = "Type your guess...",
	PlaceholderColor3 = Color3.fromRGB(150, 150, 160),
	Text = "",
	ClearTextOnFocus = false,
	Font = FONT,
	TextScaled = true,
	LayoutOrder = layoutCounter,
	Parent = guessRow,
}, {
	corner(),
	new("UITextSizeConstraint", { MaxTextSize = 32 }),
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
})
local guessDoneButton = button(guessRow, UDim2.fromScale(0.18, 1), "Done!", THEME.green)

-- Waiting / spectating
local waitPanel = panel("Wait")
local waitLabel = label(waitPanel, UDim2.fromScale(0.1, 0.3), UDim2.fromScale(0.8, 0.3), "", 50)
waitLabel.TextWrapped = true

-- Reveal
local revealPanel = panel("Reveal")
local revealHeader = label(revealPanel, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.08), "", 44)
revealHeader.TextColor3 = THEME.accent
local revealPrompt = label(revealPanel, UDim2.fromScale(0, 0.09), UDim2.fromScale(1, 0.07), "", 34)
local revealCanvas = makeCanvas(revealPanel, UDim2.fromScale(0, 0.17), UDim2.fromScale(1, 0.57))
local revealAuthor = label(revealPanel, UDim2.fromScale(0, 0.75), UDim2.fromScale(1, 0.07), "", 30)
revealAuthor.TextColor3 = THEME.soft
local revealGuess = label(revealPanel, UDim2.fromScale(0, 0.83), UDim2.fromScale(1, 0.13), "", 50)
revealGuess.TextColor3 = THEME.accent

---------------------------------------------------------------- Game state
local state = { phase = "Lobby", endsAt = 0, message = "", playing = false, done = 0, total = 0 }
local currentTask = nil -- what the server asked us to do this round
local submitted = false

local selectedColor, selectedSize = 1, 2
local strokeGroups = {} -- finished strokes this round: { group = Frame, count = points }
local totalPoints = 0
local activeStroke = nil -- the stroke being drawn right now

local function timeLeft()
	if state.endsAt == 0 then
		return 0
	end
	return math.max(0, state.endsAt - workspace:GetServerTimeNow())
end

local function canDraw()
	return currentTask ~= nil
		and currentTask.kind == "draw"
		and not submitted
		and state.phase == "Playing"
		and timeLeft() > 0
end

local function limitText(text, max)
	local length = utf8.len(text)
	if length and length > max then
		return text:sub(1, utf8.offset(text, max + 1) - 1)
	end
	return text
end

---------------------------------------------------------------- Drawing
local function screenToCanvas(screenPos)
	local origin, size = drawCanvas.AbsolutePosition, drawCanvas.AbsoluteSize
	local x = math.clamp((screenPos.X - origin.X) / size.X, 0, 1)
	local y = math.clamp((screenPos.Y - origin.Y) / size.Y, 0, 1)
	return math.round(x * 1000), math.round(y * 1000)
end

-- Gets the pointer position in the same coordinates as the GUI (which ignores the top bar inset).
local function pointerPosition(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
	end
	return UserInputService:GetMouseLocation()
end

local function beginStroke(x, y)
	if not canDraw() or #strokeGroups >= Config.MAX_STROKES or totalPoints >= Config.MAX_POINTS_PER_DRAWING then
		return
	end
	local group = Renderer.newGroup(drawCanvas)
	activeStroke = {
		points = { x, y },
		group = group,
		color = selectedColor,
		size = selectedSize,
		lastX = x,
		lastY = y,
	}
	Renderer.segment(group, x, y, x, y, Config.COLORS[selectedColor], Config.BRUSH_SIZES[selectedSize])
end

local function finishStroke()
	local stroke = activeStroke
	if not stroke then
		return
	end
	activeStroke = nil

	-- Pack points into a buffer: 2 bytes x + 2 bytes y per point.
	local count = #stroke.points // 2
	local data = buffer.create(count * 4)
	for i = 1, count do
		buffer.writeu16(data, (i - 1) * 4, stroke.points[i * 2 - 1])
		buffer.writeu16(data, (i - 1) * 4 + 2, stroke.points[i * 2])
	end
	totalPoints += count
	table.insert(strokeGroups, { group = stroke.group, count = count })
	StrokeEvent:FireServer(currentTask.stepId, "Add", stroke.color, stroke.size, data)
end

local function extendStroke(screenPos)
	local stroke = activeStroke
	if not stroke then
		return
	end
	if not canDraw() then
		finishStroke()
		return
	end

	local x, y = screenToCanvas(screenPos)
	local dx, dy = x - stroke.lastX, y - stroke.lastY
	if dx * dx + dy * dy < MIN_POINT_DISTANCE * MIN_POINT_DISTANCE then
		return
	end

	local count = #stroke.points // 2
	if totalPoints + count >= Config.MAX_POINTS_PER_DRAWING then
		finishStroke() -- out of ink
		return
	end
	if count >= Config.MAX_POINTS_PER_STROKE then
		-- Long stroke: send it and keep drawing as a new stroke from the same spot.
		local lastX, lastY = stroke.lastX, stroke.lastY
		finishStroke()
		beginStroke(lastX, lastY)
		stroke = activeStroke
		if not stroke then
			return
		end
	end

	Renderer.segment(
		stroke.group,
		stroke.lastX,
		stroke.lastY,
		x,
		y,
		Config.COLORS[stroke.color],
		Config.BRUSH_SIZES[stroke.size]
	)
	table.insert(stroke.points, x)
	table.insert(stroke.points, y)
	stroke.lastX, stroke.lastY = x, y
end

local function resetDrawing()
	for _, stroke in strokeGroups do
		stroke.group:Destroy()
	end
	strokeGroups = {}
	totalPoints = 0
	if activeStroke then
		activeStroke.group:Destroy()
		activeStroke = nil
	end
end

local function undo()
	if not canDraw() or activeStroke then
		return
	end
	local last = table.remove(strokeGroups)
	if last then
		last.group:Destroy()
		totalPoints -= last.count
		StrokeEvent:FireServer(currentTask.stepId, "Undo")
	end
end

local function clearAll()
	if not canDraw() then
		return
	end
	resetDrawing()
	StrokeEvent:FireServer(currentTask.stepId, "Clear")
end

drawCanvas.InputBegan:Connect(function(input)
	local kind = input.UserInputType
	if (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) and not activeStroke then
		beginStroke(screenToCanvas(pointerPosition(input)))
	end
end)

UserInputService.InputChanged:Connect(function(input)
	local kind = input.UserInputType
	if activeStroke and (kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch) then
		extendStroke(pointerPosition(input))
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
		finishStroke()
	end
end)

---------------------------------------------------------------- Toolbar
local swatches = {}
for i, color in Config.COLORS do
	swatches[i] = new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = i,
		Parent = colorRow,
	}, {
		new("UIAspectRatioConstraint", { AspectRatio = 1 }),
		corner(UDim.new(0.5, 0)),
		new("UIStroke", { Thickness = 2, Color = THEME.dark, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
end

local sizeButtons = {}
local DOT_SCALES = { 0.25, 0.45, 0.75 }
for i in Config.BRUSH_SIZES do
	layoutCounter += 1
	local sizeButton = new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.gray,
		Text = "",
		LayoutOrder = layoutCounter,
		Parent = toolRow,
	}, {
		new("UIAspectRatioConstraint", { AspectRatio = 1 }),
		corner(),
	})
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(DOT_SCALES[i] or 0.5, DOT_SCALES[i] or 0.5),
		BackgroundColor3 = THEME.text,
		Parent = sizeButton,
	}, { corner(UDim.new(0.5, 0)) })
	sizeButtons[i] = sizeButton
end

local undoButton = button(toolRow, UDim2.fromScale(0.13, 1), "Undo", THEME.gray)
local clearButton = button(toolRow, UDim2.fromScale(0.13, 1), "Clear", THEME.red)
local drawDoneButton = button(toolRow, UDim2.fromScale(0.2, 1), "Done!", THEME.green)

local function refreshTools()
	for i, swatch in swatches do
		local outline = swatch:FindFirstChildOfClass("UIStroke")
		outline.Color = if i == selectedColor then THEME.accent else THEME.dark
		outline.Thickness = if i == selectedColor then 4 else 2
	end
	for i, sizeButton in sizeButtons do
		sizeButton.BackgroundColor3 = if i == selectedSize then THEME.accent else THEME.gray
	end
end

for i, swatch in swatches do
	swatch.Activated:Connect(function()
		selectedColor = i
		refreshTools()
	end)
end
for i, sizeButton in sizeButtons do
	sizeButton.Activated:Connect(function()
		selectedSize = i
		refreshTools()
	end)
end
refreshTools()

---------------------------------------------------------------- Submitting
local function flash(textLabel, message)
	local original = textLabel.Text
	textLabel.Text = message
	textLabel.TextColor3 = THEME.red
	task.delay(1.2, function()
		if textLabel.Text == message then
			textLabel.Text = original
			textLabel.TextColor3 = THEME.accent
		end
	end)
end

local function submit()
	if not currentTask or submitted or state.phase ~= "Playing" then
		return
	end
	finishStroke()
	if currentTask.kind == "draw" then
		if #strokeGroups == 0 then
			flash(drawPrompt, "Draw something first!")
			return
		end
	else
		local guess = guessBox.Text:match("^%s*(.-)%s*$")
		if guess == "" then
			flash(guessTitle, "Type a guess first!")
			return
		end
		GuessEvent:FireServer(currentTask.stepId, guessBox.Text)
	end
	submitted = true
	DoneEvent:FireServer(currentTask.stepId)
	waitLabel.Text = "Nice! Waiting for everyone else..."
	showPanel("Wait")
end

undoButton.Activated:Connect(undo)
clearButton.Activated:Connect(clearAll)
drawDoneButton.Activated:Connect(submit)
guessDoneButton.Activated:Connect(submit)

-- Send the guess to the server as you type, so it's saved even if time runs out.
local guessDirty = false
guessBox:GetPropertyChangedSignal("Text"):Connect(function()
	local limited = limitText(guessBox.Text, Config.MAX_GUESS_LENGTH)
	if limited ~= guessBox.Text then
		guessBox.Text = limited
		return
	end
	guessDirty = true
end)
guessBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		submit()
	end
end)
task.spawn(function()
	while true do
		task.wait(0.4)
		if guessDirty and currentTask and currentTask.kind == "guess" and not submitted then
			guessDirty = false
			GuessEvent:FireServer(currentTask.stepId, guessBox.Text)
		end
	end
end)

---------------------------------------------------------------- Server events
TaskEvent.OnClientEvent:Connect(function(newTask)
	currentTask = newTask
	submitted = false
	resetDrawing()
	if newTask.kind == "draw" then
		drawPrompt.Text = string.format('Draw: "%s"', newTask.prompt)
		drawPrompt.TextColor3 = THEME.accent
		showPanel("Draw")
	else
		Renderer.render(guessCanvas, newTask.strokes)
		guessBox.Text = ""
		guessDirty = false
		guessTitle.Text = "What is this drawing?"
		guessTitle.TextColor3 = THEME.accent
		showPanel("Guess")
	end
end)

StateEvent.OnClientEvent:Connect(function(newState)
	state = newState
	statusLabel.Text = newState.message
	counterLabel.Text = if newState.phase == "Playing" and newState.total > 0
		then string.format("%d/%d done", newState.done, newState.total)
		else ""

	if newState.phase == "Lobby" or newState.phase == "Intermission" then
		currentTask = nil
		resetDrawing()
		lobbyMessage.Text = newState.message
		showPanel("Lobby")
	elseif newState.phase == "Playing" then
		if not newState.playing then
			waitLabel.Text = "A game is in progress — you're spectating!\nYou'll join next round. Stick around for the reveal."
			showPanel("Wait")
		end
	elseif newState.phase == "Reveal" then
		currentTask = nil
		resetDrawing()
		showPanel("Reveal")
	end
end)

local lastRevealText = ""
RevealEvent.OnClientEvent:Connect(function(reveal)
	showPanel("Reveal")
	if reveal.type == "book" then
		revealHeader.Text = string.format("%s's sketchbook (%d/%d)", reveal.owner, reveal.index, reveal.total)
		revealPrompt.Text = string.format('The starting word was: "%s"', reveal.word)
		Renderer.clear(revealCanvas)
		revealAuthor.Text = ""
		revealGuess.Text = ""
		lastRevealText = reveal.word
	elseif reveal.type == "page" then
		if reveal.kind == "draw" then
			revealPrompt.Text = string.format('Drawing of: "%s"', lastRevealText)
			Renderer.render(revealCanvas, reveal.strokes)
			revealAuthor.Text = "Drawn by " .. reveal.author
			revealGuess.Text = ""
		else
			revealGuess.Text = string.format('%s guessed: "%s"', reveal.author, reveal.text)
			lastRevealText = reveal.text
		end
	elseif reveal.type == "summary" then
		local same = reveal.word:lower():gsub("%s", "") == reveal.final:lower():gsub("%s", "")
		revealAuthor.Text = ""
		revealGuess.Text = if same
			then string.format('"%s" made it all the way around!', reveal.word)
			else string.format('"%s" turned into "%s"!', reveal.word, reveal.final)
	end
end)

---------------------------------------------------------------- Timer
RunService.RenderStepped:Connect(function()
	local left = timeLeft()
	local timerText = if state.endsAt > 0 then tostring(math.ceil(left)) else ""
	timerLabel.Text = timerText
	timerLabel.TextColor3 = if state.phase == "Playing" and left <= 10 then THEME.red else THEME.text
	lobbyTimer.Text = if state.phase == "Intermission" then timerText else ""

	if activeStroke and not canDraw() then
		finishStroke() -- time's up mid-stroke
	end
end)

showPanel("Lobby")
