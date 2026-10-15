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
