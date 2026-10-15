-- Sketch Telephone installer: paste this whole thing into the Studio command bar (in edit mode, not while playing) and press Enter.
local function parentFor(where)
	if where == "StarterPlayerScripts" then return game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts") end
	return game:GetService(where)
end
local function install(name, className, where, source)
	local parent = parentFor(where)
	local old = parent:FindFirstChild(name)
	if old then old:Destroy() end
	local s = Instance.new(className)
	s.Name = name
	s.Source = source
	s.Parent = parent
	print("[SketchTelephone] Installed " .. className .. " " .. name .. " in " .. where)
end
install("Config", "ModuleScript", "ReplicatedStorage", [=====[
--[[
	Config  (ModuleScript)
	Put in: ReplicatedStorage   — name it exactly "Config"

	All the game's settings live here. Change these numbers to tune the game.
]]

local Config = {}

-- Players needed before a game starts. Telestrations is best with 4+,
-- but 2 lets you test with a friend (or with Studio's local server).
Config.MIN_PLAYERS = 2

-- Max number of pages per sketchbook. With N players each book gets
-- min(N, MAX_STEPS) pages, so everyone touches every book once (up to this cap).
Config.MAX_STEPS = 10

-- Timers (seconds)
Config.INTERMISSION_TIME = 20 -- lobby countdown once enough players are in
Config.DRAW_TIME = 60
Config.GUESS_TIME = 25
Config.REVEAL_PAGE_TIME = 5 -- how long each drawing / guess stays up in the reveal
Config.REVEAL_SUMMARY_TIME = 4 -- "CAT became DOG!" at the end of each book
Config.RESULTS_TIME = 8 -- "Thanks for playing" before going back to the lobby

-- Guess length limit (characters)
Config.MAX_GUESS_LENGTH = 50

-- Drawing limits (keeps network traffic small and stops abuse)
Config.MAX_POINTS_PER_STROKE = 400
Config.MAX_POINTS_PER_DRAWING = 4000
Config.MAX_STROKES = 300

-- Canvas shape (width / height)
Config.CANVAS_ASPECT = 4 / 3

-- Palette. White doubles as an eraser.
Config.COLORS = {
	Color3.fromRGB(20, 20, 20), -- black
	Color3.fromRGB(255, 255, 255), -- white / eraser
	Color3.fromRGB(130, 130, 130), -- gray
	Color3.fromRGB(225, 50, 50), -- red
	Color3.fromRGB(255, 140, 30), -- orange
	Color3.fromRGB(255, 215, 0), -- yellow
	Color3.fromRGB(60, 180, 75), -- green
	Color3.fromRGB(40, 110, 230), -- blue
	Color3.fromRGB(140, 70, 200), -- purple
	Color3.fromRGB(255, 120, 190), -- pink
	Color3.fromRGB(130, 80, 40), -- brown
}

-- Brush thickness, in thousandths of the canvas width (small, medium, large)
Config.BRUSH_SIZES = { 5, 12, 28 }

-- Starting words. Add as many as you like!
Config.WORDS = {
	"Cat", "Dog", "Pizza", "Rocket", "Dinosaur", "Snowman", "Castle", "Robot",
	"Volcano", "Mermaid", "Ghost", "Rainbow", "Spaghetti", "Octopus", "Vampire",
	"Sandcastle", "Hot Air Balloon", "Penguin", "Treasure Map", "Dragon",
	"Haunted House", "Unicorn", "Lighthouse", "Cupcake", "Alien", "Pirate",
	"Tornado", "Skateboard", "Waterfall", "Wizard", "Jellyfish", "Banana",
	"Campfire", "Superhero", "Roller Coaster", "Igloo", "Cactus", "Ninja",
	"Shark", "Birthday Cake", "Snail", "Bee", "Mummy", "Telescope", "Pyramid",
	"Giraffe", "Popcorn", "Scarecrow", "Fireworks", "Moon", "Sunflower",
	"Spider Web", "Toaster", "Bathtub", "Zombie", "Kangaroo", "Hamburger",
	"Ice Cream", "Bicycle", "Clown", "Butterfly", "Train", "Owl",
	"Tooth Fairy", "Bowling", "Treehouse", "Sneeze", "Sleepwalking", "Magnet",
	"Sea Monster", "Lawn Mower", "Pillow Fight", "Cowboy", "Ladder", "Frog",
	"Hammock", "Traffic Jam", "Lemonade", "Snowball Fight", "Crown", "Bat",
}

return Config
]=====])
install("DrawingRenderer", "ModuleScript", "ReplicatedStorage", [=====[
--[[
	DrawingRenderer  (ModuleScript)
	Put in: ReplicatedStorage   — name it exactly "DrawingRenderer"

	Draws lines on a GUI "canvas" Frame. Each line segment is a thin, rotated,
	rounded Frame. Coordinates are 0..1000 on both axes so drawings look the
	same on every screen size.

	A stroke is { c = colorIndex, s = sizeIndex, p = buffer } where the buffer
	holds pairs of uint16 (x, y), 4 bytes per point.
]]

local Config = require(script.Parent:WaitForChild("Config"))

local Renderer = {}

local ASPECT = Config.CANVAS_ASPECT
local zCounter = 0

-- A container for one stroke, so a stroke can be removed in one go (undo).
function Renderer.newGroup(canvas)
	zCounter += 1
	local group = Instance.new("Frame")
	group.Name = "Stroke"
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromScale(1, 1)
	group.ZIndex = zCounter -- later strokes always draw on top
	group.Parent = canvas
	return group
end

-- One line from (x1, y1) to (x2, y2). thickness is in thousandths of canvas width.
function Renderer.segment(parent, x1, y1, x2, y2, color, thickness)
	-- Work in "canvas widths" so rotation is correct even though the canvas isn't square.
	local dx = (x2 - x1) / 1000
	local dy = (y2 - y1) / 1000 / ASPECT
	local length = math.sqrt(dx * dx + dy * dy)
	local t = thickness / 1000

	local line = Instance.new("Frame")
	line.BorderSizePixel = 0
	line.BackgroundColor3 = color
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale((x1 + x2) / 2000, (y1 + y2) / 2000)
	-- Width is relative to canvas width; height is relative to canvas height, hence * ASPECT.
	line.Size = UDim2.fromScale(length + t, t * ASPECT)
	line.Rotation = math.deg(math.atan2(dy, dx))

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0) -- pill shape = round brush tips
	corner.Parent = line

	line.Parent = parent
	return line
end

function Renderer.drawStroke(canvas, stroke)
	local group = Renderer.newGroup(canvas)
	local color = Config.COLORS[stroke.c] or Config.COLORS[1]
	local size = Config.BRUSH_SIZES[stroke.s] or Config.BRUSH_SIZES[1]
	local points = stroke.p
	local count = buffer.len(points) // 4
	if count == 0 then
		return group
	end

	local px, py = buffer.readu16(points, 0), buffer.readu16(points, 2)
	if count == 1 then
		Renderer.segment(group, px, py, px, py, color, size) -- a single dot
	end
	for i = 1, count - 1 do
		local x, y = buffer.readu16(points, i * 4), buffer.readu16(points, i * 4 + 2)
		Renderer.segment(group, px, py, x, y, color, size)
		px, py = x, y
	end
	return group
end

function Renderer.clear(canvas)
	for _, child in canvas:GetChildren() do
		if child.Name == "Stroke" then
			child:Destroy()
		end
	end
end

function Renderer.render(canvas, strokes)
	Renderer.clear(canvas)
	for _, stroke in strokes or {} do
		Renderer.drawStroke(canvas, stroke)
	end
end

return Renderer
]=====])
install("GameServer", "Script", "ServerScriptService", [=====[
--[[
	GameServer  (Script)
	Put in: ServerScriptService

	Runs the whole game: lobby -> rounds of draw/guess -> reveal -> lobby.

	How the sketchbooks move (just like Telestrations):
	  - Every player owns one sketchbook with a secret starting word.
	  - Round 1: everyone draws their OWN word.
	  - Each round, every book is passed to the next player.
	  - A book's next page is a GUESS if its last page was a drawing,
	    and a DRAWING if its last page was a word/guess.
	  - After min(players, MAX_STEPS) rounds, every book is revealed page by page.
	If someone leaves (or submits nothing), their page is just skipped and the
	next player works from the last real page, so the chain never breaks.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

-- No avatars: this is a one-screen game.
Players.CharacterAutoLoads = false
print("[SketchTelephone] GameServer started")

local function findModule(name)
	local module = ReplicatedStorage:WaitForChild(name, 5)
	if not module then
		error("[SketchTelephone] Missing ModuleScript '" .. name .. "' in ReplicatedStorage (check the spelling)")
	end
	return require(module)
end

local Config = findModule("Config")

---------------------------------------------------------------- Remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function newRemote(name)
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local StateEvent = newRemote("State") -- server -> client: phase, timer, status text
local TaskEvent = newRemote("Task") -- server -> client: "draw this" / "guess this"
local RevealEvent = newRemote("Reveal") -- server -> client: reveal pages
local StrokeEvent = newRemote("Stroke") -- client -> server: add / undo / clear a stroke
local GuessEvent = newRemote("Guess") -- client -> server: current guess text
local DoneEvent = newRemote("Done") -- client -> server: "I'm finished"

---------------------------------------------------------------- State
local state = { phase = "Lobby", endsAt = 0, message = "Waiting for players..." }
local isParticipant = {} -- [Player] = true for people in the current game
local jobs = {} -- [Player] = what they're doing this round
local stepId = 0 -- increases every round so late messages from last round are ignored

local function now()
	return workspace:GetServerTimeNow()
end

local function inGame(player)
	return player.Parent == Players
end

local function trim(text)
	return (text:match("^%s*(.-)%s*$"))
end

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function countDone()
	local done, total = 0, 0
	for player, job in jobs do
		if inGame(player) then
			total += 1
			if job.done then
				done += 1
			end
		end
	end
	return done, total
end

local function sendState(player)
	local done, total = countDone()
	StateEvent:FireClient(player, {
		phase = state.phase,
		endsAt = state.endsAt,
		message = state.message,
		playing = isParticipant[player] == true,
		done = done,
		total = total,
	})
end

local function broadcastState()
	for _, player in Players:GetPlayers() do
		sendState(player)
	end
end

local function setState(phase, duration, message)
	state.phase = phase
	state.endsAt = if duration > 0 then now() + duration else 0
	state.message = message
	broadcastState()
end

-- Roblox requires filtering any text a player typed before showing it to others.
local function filterText(text, userId)
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		return result
	end
	warn("Text filter failed:", result)
	return nil
end

---------------------------------------------------------------- Input from players
local function validStroke(colorIndex, sizeIndex, points)
	if typeof(colorIndex) ~= "number" or Config.COLORS[colorIndex] == nil then
		return false
	end
	if typeof(sizeIndex) ~= "number" or Config.BRUSH_SIZES[sizeIndex] == nil then
		return false
	end
	if typeof(points) ~= "buffer" then
		return false
	end
	local len = buffer.len(points)
	if len == 0 or len % 4 ~= 0 or len // 4 > Config.MAX_POINTS_PER_STROKE then
		return false
	end
	for offset = 0, len - 2, 2 do
		if buffer.readu16(points, offset) > 1000 then
			return false
		end
	end
	return true
end

StrokeEvent.OnServerEvent:Connect(function(player, id, action, colorIndex, sizeIndex, points)
	local job = jobs[player]
	if not job or job.done or job.kind ~= "draw" or job.stepId ~= id then
		return
	end

	if action == "Add" then
		if #job.strokes >= Config.MAX_STROKES or not validStroke(colorIndex, sizeIndex, points) then
			return
		end
		local count = buffer.len(points) // 4
		if job.points + count > Config.MAX_POINTS_PER_DRAWING then
			return
		end
		job.points += count
		table.insert(job.strokes, { c = colorIndex, s = sizeIndex, p = points })
	elseif action == "Undo" then
		local stroke = table.remove(job.strokes)
		if stroke then
			job.points -= buffer.len(stroke.p) // 4
		end
	elseif action == "Clear" then
		job.strokes = {}
		job.points = 0
	end
end)

GuessEvent.OnServerEvent:Connect(function(player, id, text)
	local job = jobs[player]
	if not job or job.done or job.kind ~= "guess" or job.stepId ~= id then
		return
	end
	if typeof(text) ~= "string" or utf8.len(text) == nil then
		return
	end
	text = text:gsub("[\r\n\t]", " ")
	if utf8.len(text) > Config.MAX_GUESS_LENGTH then
		text = text:sub(1, utf8.offset(text, Config.MAX_GUESS_LENGTH + 1) - 1)
	end
	job.guess = text
end)

DoneEvent.OnServerEvent:Connect(function(player, id)
	local job = jobs[player]
	if job and not job.done and job.stepId == id then
		job.done = true
		broadcastState() -- updates the "3/5 done" counter
	end
end)

---------------------------------------------------------------- Game flow
local function runLobby()
	while true do
		local count = #Players:GetPlayers()
		if count < Config.MIN_PLAYERS then
			local message = string.format("Waiting for players... (%d/%d)", count, Config.MIN_PLAYERS)
			if state.phase ~= "Lobby" or state.message ~= message then
				setState("Lobby", 0, message)
			end
			task.wait(1)
		else
			setState("Intermission", Config.INTERMISSION_TIME, "Game starting soon!")
			local cancelled = false
			while now() < state.endsAt do
				task.wait(0.5)
				if #Players:GetPlayers() < Config.MIN_PLAYERS then
					cancelled = true
					break
				end
			end
			if not cancelled then
				return
			end
		end
	end
end

local function runRounds(participants, books)
	local n = #participants
	local steps = math.min(n, Config.MAX_STEPS)

	for step = 0, steps - 1 do
		local connected = 0
		for _, player in participants do
			if inGame(player) then
				connected += 1
			end
		end
		if connected < 2 then
			break -- not enough people left to keep passing books; go to the reveal
		end

		-- Hand out this round's jobs. Book b goes to player (b + step).
		stepId += 1
		jobs = {}
		local anyDraw = false
		for b, book in books do
			local player = participants[(b - 1 + step) % n + 1]
			if inGame(player) then
				local last = book.pages[#book.pages]
				local job = { book = book, stepId = stepId, done = false, strokes = {}, points = 0, guess = "" }
				local payload = { stepId = stepId }
				if last == nil or last.kind == "guess" then
					job.kind = "draw"
					payload.kind = "draw"
					payload.prompt = if last then last.text else book.word
					anyDraw = true
				else
					job.kind = "guess"
					payload.kind = "guess"
					payload.strokes = last.strokes
				end
				jobs[player] = job
				TaskEvent:FireClient(player, payload)
			end
		end

		local duration = if anyDraw then Config.DRAW_TIME else Config.GUESS_TIME
		setState("Playing", duration, string.format("Round %d of %d", step + 1, steps))

		-- Wait for the timer, or until everyone pressed Done.
		while now() < state.endsAt do
			local done, total = countDone()
			if total == 0 or done >= total then
				break
			end
			task.wait(0.25)
		end
		task.wait(0.5) -- let any last-second strokes/guesses arrive

		-- Collect pages. Empty drawings/guesses are skipped.
		local finished = jobs
		jobs = {}
		setState("Playing", 0, "Passing the sketchbooks...")
		for player, job in finished do
			if job.kind == "draw" then
				if #job.strokes > 0 then
					table.insert(job.book.pages, { kind = "draw", author = player.DisplayName, strokes = job.strokes })
				end
			else
				local text = trim(job.guess)
				if text ~= "" then
					local filtered = filterText(text, player.UserId)
					if filtered and trim(filtered) ~= "" then
						table.insert(job.book.pages, { kind = "guess", author = player.DisplayName, text = filtered })
					end
				end
			end
		end
	end
end

local function runReveal(books)
	setState("Reveal", 0, "Reveal time!")
	task.wait(2)

	for index, book in books do
		if #book.pages > 0 then
			setState("Reveal", 0, book.owner .. "'s sketchbook")
			RevealEvent:FireAllClients({
				type = "book",
				owner = book.owner,
				word = book.word,
				index = index,
				total = #books,
			})
			task.wait(Config.REVEAL_PAGE_TIME)

			for _, page in book.pages do
				RevealEvent:FireAllClients({
					type = "page",
					kind = page.kind,
					author = page.author,
					strokes = page.strokes,
					text = page.text,
				})
				task.wait(Config.REVEAL_PAGE_TIME)
			end

			local last = book.pages[#book.pages]
			if last.kind == "guess" then
				RevealEvent:FireAllClients({ type = "summary", word = book.word, final = last.text })
				task.wait(Config.REVEAL_SUMMARY_TIME)
			end
		end
	end
end

local function runGame()
	local participants = shuffle(Players:GetPlayers())
	isParticipant = {}
	for _, player in participants do
		isParticipant[player] = true
	end

	local words = shuffle(table.clone(Config.WORDS))
	local books = {}
	for i, player in participants do
		books[i] = { owner = player.DisplayName, word = words[(i - 1) % #words + 1], pages = {} }
	end

	runRounds(participants, books)
	jobs = {}
	isParticipant = {}

	if #Players:GetPlayers() > 0 then
		runReveal(books)
		setState("Lobby", Config.RESULTS_TIME, "Thanks for playing!")
		task.wait(Config.RESULTS_TIME)
	end
end

---------------------------------------------------------------- Start
Players.PlayerAdded:Connect(sendState) -- late joiners see the current phase (and spectate)
for _, player in Players:GetPlayers() do
	sendState(player)
end
Players.PlayerRemoving:Connect(function()
	if state.phase == "Playing" then
		task.defer(broadcastState) -- refresh the "done" counter
	end
end)

print("[SketchTelephone] Server ready, waiting for players")
while true do
	runLobby()
	runGame()
end
]=====])
install("GameClient", "LocalScript", "StarterPlayerScripts", [=====[
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

print("[SketchTelephone] GameClient started")

local function waitFor(name, hint)
	local child = ReplicatedStorage:WaitForChild(name, 10)
	if not child then
		error("[SketchTelephone] Can't find '" .. name .. "' in ReplicatedStorage. " .. hint)
	end
	return child
end

local Config = require(waitFor("Config", "Add the Config ModuleScript."))
local Renderer = require(waitFor("DrawingRenderer", "Add the DrawingRenderer ModuleScript."))
local remotes = waitFor("Remotes", "The GameServer Script in ServerScriptService isn't running.")
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
print("[SketchTelephone] UI ready")
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
print("[SketchTelephone] UI ready")
]=====])
print("[SketchTelephone] All done! Now set players to 2+ and press Start.")
