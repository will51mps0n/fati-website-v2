-- Runs the guess-and-draw game: matches of rounds, turns, scoring, guess checking,
-- and relaying the drawer's strokes to everyone else live.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("GuessAndDraw")
local Config = require(Shared:WaitForChild("Config"))
local Words = require(Shared:WaitForChild("Words"))

Players.CharacterAutoLoads = Config.SPAWN_CHARACTERS

-- Remotes ----------------------------------------------------------------------

local remotes = Instance.new("Folder")
remotes.Name = "GuessAndDrawRemotes"

local function makeRemote(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local StateEvent = makeRemote("State") -- S->C: game snapshot
local DrawEvent = makeRemote("Draw") -- C->S: drawer's points and fills; S->C: relayed to everyone
local CanvasEvent = makeRemote("Canvas") -- C->S: undo/clear/ready; S->C: undo/clear
local ChatEvent = makeRemote("Chat") -- S->C: chat and system lines
local GuessEvent = makeRemote("Guess") -- C->S: a guess or chat message
local WordChoiceEvent = makeRemote("WordChoice") -- S->C: options or an error; C->S: index, "custom" or a custom word
local VoteEvent = makeRemote("Vote") -- C->S: "like", "dislike", or "kick" plus a user ID
remotes.Parent = ReplicatedStorage

-- State ------------------------------------------------------------------------

local state = {
	phase = "Waiting", -- Waiting, Starting, Choosing, Drawing, TurnEnd, MatchEnd
	round = 0,
	phaseEndsAt = 0,
	drawer = nil :: Player?,
	word = nil :: string?,
	wordOptions = nil :: { string }?,
	customTimeGiven = false, -- the drawer already got extra time for a custom word
	rated = {} :: { [Player]: boolean }, -- who already gave this drawing a thumbs up or down
	revealed = {} :: { [number]: boolean },
	turnStartedAt = 0,
	guessed = {} :: { [Player]: boolean },
	guessCount = 0,
	turnPoints = {} :: { [Player]: number },
	lastTurn = nil :: any,
	winners = nil :: any,
}

-- The password for drawing a custom word. Server scripts never reach players'
-- computers, so nobody can read it out of the game.
local CUSTOM_WORD_PASSWORD = "poop123"
local MAX_PASSWORD_TRIES = 5

local scores: { [Player]: number } = {}
local allTimeWins: { [Player]: number } = {} -- matches won, ever, saved in a DataStore
local passwordFailures: { [Player]: number } = {}
local usedWords: { [string]: boolean } = {}
local readyPlayers: { [Player]: boolean } = {}

-- Everything drawn this turn, in order, kept so late joiners see the whole drawing.
-- A stroke has points `p`; a bucket fill has its start point `f`. Colours `c` are
-- 0xRRGGBB numbers, so the colour wheel can pick any colour.
local strokes: { { id: number, c: number, s: number?, p: { number }, f: { number }? } } = {}
local strokesById: { [number]: any } = {}
local totalNumbers = 0
local drawRate: { [Player]: { windowStart: number, count: number } } = {}
local lastFillAt: { [Player]: number } = {}
local lastGuessAt: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isPresent(player: Player?): boolean
	return player ~= nil and player.Parent == Players
end

-- Words --------------------------------------------------------------------------

local function normalize(text: string): string
	return (string.gsub(string.lower(text), "[^%w]", ""))
end

local function isLetter(char: string): boolean
	return string.match(char, "%w") ~= nil
end

local function maskedWord(): string
	local word = state.word or ""
	local out = table.create(#word)
	for i = 1, #word do
		local char = string.sub(word, i, i)
		out[i] = if isLetter(char) and not state.revealed[i] then "_" else char
	end
	return table.concat(out)
end

local function revealRandomLetter()
	local word = state.word
	if not word then
		return
	end
	local hidden = {}
	for i = 1, #word do
		if isLetter(string.sub(word, i, i)) and not state.revealed[i] then
			table.insert(hidden, i)
		end
	end
	-- Always leave at least two letters hidden so the hint never gives it away.
	if #hidden > 2 then
		state.revealed[hidden[math.random(#hidden)]] = true
	end
end

-- One word from each list in turn, so the choices run easy, medium, hard. Words
-- aren't repeated within a match until a list runs out.
local TIERS = { "easy", "medium", "hard" }

local function pickWords(count: number): { string }
	local picks = {}
	for i = 1, count do
		local list = Words[TIERS[(i - 1) % #TIERS + 1]]
		local pool = {}
		for _, word in list do
			if not usedWords[word] and not table.find(picks, word) then
				table.insert(pool, word)
			end
		end
		if #pool == 0 then
			-- This list is used up: allow its words again.
			for _, word in list do
				usedWords[word] = nil
				if not table.find(picks, word) then
					table.insert(pool, word)
				end
			end
		end
		local word = pool[math.random(#pool)]
		usedWords[word] = true
		table.insert(picks, word)
	end
	return picks
end

-- Levenshtein distance, used to tell a guesser they are close.
local function editDistance(a: string, b: string): number
	if math.abs(#a - #b) > 2 then
		return 99
	end
	local prev = {}
	for j = 0, #b do
		prev[j] = j
	end
	for i = 1, #a do
		local cur = { [0] = i }
		for j = 1, #b do
			local cost = if string.byte(a, i) == string.byte(b, j) then 0 else 1
			cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
		end
		prev = cur
	end
	return prev[#b]
end

-- Scores ---------------------------------------------------------------------------

local function setLeaderstat(player: Player, name: string, value: number)
	local stats = player:FindFirstChild("leaderstats")
	local stat = stats and stats:FindFirstChild(name)
	if stat then
		(stat :: IntValue).Value = value
	end
end

local function addScore(player: Player, points: number)
	scores[player] = (scores[player] or 0) + points
	state.turnPoints[player] = (state.turnPoints[player] or 0) + points
	setLeaderstat(player, "Score", scores[player])
end

-- Broadcasting --------------------------------------------------------------------

local function buildSnapshot(forPlayer: Player)
	local list = {}
	for _, player in Players:GetPlayers() do
		table.insert(list, {
			userId = player.UserId,
			name = player.DisplayName,
			score = scores[player] or 0,
			wins = allTimeWins[player] or 0,
			guessed = state.guessed[player] == true,
			isDrawer = player == state.drawer,
		})
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.name < b.name
	end)

	local seesWord = forPlayer == state.drawer or state.guessed[forPlayer] or state.phase == "TurnEnd"
	local wordDisplay = nil
	if state.word and (state.phase == "Drawing" or state.phase == "TurnEnd") then
		wordDisplay = if seesWord then state.word else maskedWord()
	end

	return {
		phase = state.phase,
		round = state.round,
		totalRounds = Config.ROUNDS_PER_MATCH,
		phaseEndsAt = state.phaseEndsAt,
		drawerUserId = state.drawer and state.drawer.UserId,
		drawerName = state.drawer and state.drawer.DisplayName,
		isDrawer = forPlayer == state.drawer,
		canDraw = forPlayer == state.drawer and state.phase == "Drawing",
		word = wordDisplay,
		wordIsFull = seesWord == true,
		players = list,
		minPlayers = Config.MIN_PLAYERS,
		lastTurn = state.lastTurn,
		winners = state.winners,
	}
end

local function broadcastState()
	for player in readyPlayers do
		if isPresent(player) then
			StateEvent:FireClient(player, buildSnapshot(player))
		end
	end
end

local function systemMessage(text: string, kind: string?, recipients: { Player }?)
	local message = { kind = kind or "system", text = text }
	if recipients then
		for _, player in recipients do
			ChatEvent:FireClient(player, message)
		end
	else
		ChatEvent:FireAllClients(message)
	end
end

local function filterForBroadcast(text: string, from: Player): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, from.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		return result
	end
	warn("Text filtering failed:", result)
	return nil
end

-- All-time wins -----------------------------------------------------------------------

-- Saved between servers and sessions. A DataStore only works in a published game
-- (and in Studio only with "Enable Studio Access to API Services" switched on);
-- without one, wins simply count for this server.
local winsStore: DataStore? = nil
pcall(function()
	winsStore = DataStoreService:GetDataStore("GuessAndDrawWins")
end)

local function loadWins(player: Player)
	local store = winsStore
	if not store then
		return
	end
	local ok, saved = pcall(function()
		return store:GetAsync(tostring(player.UserId))
	end)
	if ok and typeof(saved) == "number" and player.Parent == Players then
		allTimeWins[player] = math.max(allTimeWins[player] or 0, saved)
		setLeaderstat(player, "Wins", allTimeWins[player])
		broadcastState()
	elseif not ok then
		warn("Couldn't load wins:", saved)
	end
end

local function addWin(player: Player)
	allTimeWins[player] = (allTimeWins[player] or 0) + 1
	setLeaderstat(player, "Wins", allTimeWins[player])
	local store = winsStore
	if not store then
		return
	end
	task.spawn(function()
		local ok, total = pcall(function()
			return store:UpdateAsync(tostring(player.UserId), function(old)
				return (if typeof(old) == "number" then old else 0) + 1
			end)
		end)
		if ok and typeof(total) == "number" and player.Parent == Players then
			-- The saved total is the true count (the player may have won elsewhere too).
			allTimeWins[player] = total
			setLeaderstat(player, "Wins", total)
			broadcastState()
		elseif not ok then
			warn("Couldn't save a win:", total)
		end
	end)
end

-- Canvas ---------------------------------------------------------------------------

local function clearCanvas()
	table.clear(strokes)
	table.clear(strokesById)
	totalNumbers = 0
	CanvasEvent:FireAllClients("clear")
end

local function sendCanvasTo(player: Player)
	CanvasEvent:FireClient(player, "clear")
	local chunk = Config.MAX_NUMBERS_PER_PACKET
	for _, stroke in strokes do
		if stroke.f then
			DrawEvent:FireClient(player, { id = stroke.id, c = stroke.c, f = stroke.f })
			continue
		end
		for start = 1, math.max(#stroke.p, 1), chunk do
			local points = table.move(stroke.p, start, math.min(start + chunk - 1, #stroke.p), 1, {})
			DrawEvent:FireClient(player, { id = stroke.id, c = stroke.c, s = stroke.s, p = points })
		end
	end
end

local function isInteger(value: any, min: number, max: number): boolean
	return typeof(value) == "number" and value == value and value % 1 == 0 and value >= min and value <= max
end

DrawEvent.OnServerEvent:Connect(function(player, packet)
	if player ~= state.drawer or state.phase ~= "Drawing" or typeof(packet) ~= "table" then
		return
	end

	local rate = drawRate[player]
	local t = os.clock()
	if not rate or t - rate.windowStart >= 1 then
		rate = { windowStart = t, count = 0 }
		drawRate[player] = rate
	end
	rate.count += 1
	if rate.count > Config.MAX_PACKETS_PER_SECOND then
		return
	end

	local id, c, s, p = packet.id, packet.c, packet.s, packet.p
	if not isInteger(id, 1, 2 ^ 31) or not isInteger(c, 0, 0xFFFFFF) then
		return
	end

	local function relay(message)
		for _, other in Players:GetPlayers() do
			if other ~= player and readyPlayers[other] then
				DrawEvent:FireClient(other, message)
			end
		end
	end

	-- Bucket fill: everyone floods the same spot on their own copy of the canvas.
	local f = packet.f
	if f ~= nil then
		if typeof(f) ~= "table" or strokesById[id] then
			return
		end
		-- Every client floods the whole grid for each fill, so keep them spaced out.
		local tooSoon = lastFillAt[player] ~= nil and t - lastFillAt[player] < Config.MIN_FILL_INTERVAL
		if tooSoon or #strokes >= Config.MAX_STROKES then
			-- The drawer already filled on their own screen; take it back there.
			CanvasEvent:FireClient(player, "undo", id)
			return
		end
		lastFillAt[player] = t
		local x, y = f[1], f[2]
		if typeof(x) ~= "number" or typeof(y) ~= "number" or x ~= x or y ~= y then
			return
		end
		local fill = { id = id, c = c, p = {}, f = { math.clamp(x, 0, 1), math.clamp(y, 0, 1) } }
		strokesById[id] = fill
		table.insert(strokes, fill)
		relay({ id = id, c = c, f = fill.f })
		return
	end

	if not isInteger(s, 1, #Config.BRUSH_SIZES) then
		return
	end
	if typeof(p) ~= "table" or #p == 0 or #p % 2 ~= 0 or #p > Config.MAX_NUMBERS_PER_PACKET then
		return
	end
	if totalNumbers + #p > Config.MAX_TOTAL_NUMBERS then
		return
	end

	local points = table.create(#p)
	for i = 1, #p do
		local n = p[i]
		if typeof(n) ~= "number" or n ~= n then
			return
		end
		points[i] = math.clamp(n, 0, 1)
	end

	local stroke = strokesById[id]
	if stroke and stroke.f then
		return
	end
	if not stroke then
		if #strokes >= Config.MAX_STROKES then
			return
		end
		stroke = { id = id, c = c, s = s, p = {} }
		strokesById[id] = stroke
		table.insert(strokes, stroke)
	end
	table.move(points, 1, #points, #stroke.p + 1, stroke.p)
	totalNumbers += #points

	relay({ id = id, c = stroke.c, s = stroke.s, p = points })
end)

CanvasEvent.OnServerEvent:Connect(function(player, action)
	if action == "ready" then
		if readyPlayers[player] then
			return
		end
		readyPlayers[player] = true
		StateEvent:FireClient(player, buildSnapshot(player))
		sendCanvasTo(player)
		return
	end

	if player ~= state.drawer or state.phase ~= "Drawing" then
		return
	end
	if action == "undo" then
		local stroke = table.remove(strokes)
		if stroke then
			strokesById[stroke.id] = nil
			totalNumbers -= #stroke.p
			CanvasEvent:FireAllClients("undo", stroke.id)
		end
	elseif action == "clear" then
		clearCanvas()
	end
end)

-- Guesses & chat -------------------------------------------------------------------

local function insiders(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player == state.drawer or state.guessed[player] then
			table.insert(list, player)
		end
	end
	return list
end

GuessEvent.OnServerEvent:Connect(function(player, text)
	if typeof(text) ~= "string" then
		return
	end
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if #text == 0 or #text > 100 then
		return
	end
	local t = os.clock()
	if lastGuessAt[player] and t - lastGuessAt[player] < 0.4 then
		return
	end
	lastGuessAt[player] = t

	local word = state.word
	if state.phase == "Drawing" and word then
		-- The drawer and anyone who already guessed may only talk among themselves,
		-- so they can't leak the answer.
		if player == state.drawer or state.guessed[player] then
			local filtered = filterForBroadcast(text, player)
			if filtered then
				local message = { kind = "insider", name = player.DisplayName, text = filtered }
				for _, insider in insiders() do
					ChatEvent:FireClient(insider, message)
				end
			end
			return
		end

		local guess, answer = normalize(text), normalize(word)
		if guess == answer then
			state.guessed[player] = true
			state.guessCount += 1
			local timeLeft = math.clamp((state.phaseEndsAt - now()) / Config.DRAW_TIME, 0, 1)
			local points = math.floor(
				Config.MIN_GUESS_POINTS + (Config.MAX_GUESS_POINTS - Config.MIN_GUESS_POINTS) * timeLeft
			)
			if state.guessCount == 1 then
				points += Config.FIRST_GUESS_BONUS
			end
			addScore(player, points)
			if isPresent(state.drawer) then
				addScore(state.drawer :: Player, Config.DRAWER_POINTS_PER_GUESS)
			end
			systemMessage(player.DisplayName .. " guessed the word!", "correct")
			systemMessage(`You guessed it! +{points} points`, "correct", { player })
			broadcastState()
			return
		end

		local filtered = filterForBroadcast(text, player)
		if filtered then
			ChatEvent:FireAllClients({ kind = "chat", name = player.DisplayName, text = filtered })
		end
		if #answer >= 4 and editDistance(guess, answer) == 1 then
			systemMessage(`'{filtered or text}' is close!`, "close", { player })
		end
		return
	end

	local filtered = filterForBroadcast(text, player)
	if filtered then
		ChatEvent:FireAllClients({ kind = "chat", name = player.DisplayName, text = filtered })
	end
end)

-- Tidies a typed custom word, or returns nil if it isn't a drawable word.
local function cleanCustomWord(text: string): string?
	text = string.lower(text)
	text = string.gsub(text, "%s+", " ")
	text = string.gsub(text, "^ ", "")
	text = string.gsub(text, " $", "")
	if #text < 2 or #text > 30 or not string.match(text, "^%a[%a %-']*$") then
		return nil
	end
	return text
end

WordChoiceEvent.OnServerEvent:Connect(function(player, choice)
	local function stillChoosing()
		return player == state.drawer and state.phase == "Choosing" and state.word == nil
	end
	if not stillChoosing() then
		return
	end

	-- The drawer opened the custom word form: give them time to type (once per turn).
	if choice == "custom" then
		if not state.customTimeGiven then
			state.customTimeGiven = true
			state.phaseEndsAt = math.max(state.phaseEndsAt, now() + Config.CUSTOM_WORD_TIME)
			broadcastState()
		end
		return
	end

	if typeof(choice) == "table" then
		local function reject(message: string)
			WordChoiceEvent:FireClient(player, { error = message })
		end
		if (passwordFailures[player] or 0) >= MAX_PASSWORD_TRIES then
			reject("Too many wrong passwords - pick a word instead.")
			return
		end
		if choice.password ~= CUSTOM_WORD_PASSWORD then
			passwordFailures[player] = (passwordFailures[player] or 0) + 1
			reject("Wrong password!")
			return
		end
		local word = if typeof(choice.word) == "string" then cleanCustomWord(choice.word) else nil
		if not word then
			reject("Use 2-30 letters (spaces, - and ' are OK).")
			return
		end
		-- Everyone sees the word at the end of the turn, so it must pass Roblox's filter.
		local filtered = filterForBroadcast(word, player)
		if not stillChoosing() then
			return
		end
		if filtered ~= word then
			reject("That word isn't allowed.")
			return
		end
		state.word = word
		return
	end

	local options = state.wordOptions
	if options and isInteger(choice, 1, #options) then
		state.word = options[choice]
	end
end)

-- Game loop ------------------------------------------------------------------------

local function enoughPlayers(): boolean
	return #Players:GetPlayers() >= Config.MIN_PLAYERS
end

-- Waits until the phase timer runs out, or until `stopEarly` returns true.
local function waitPhase(duration: number, stopEarly: (() -> boolean)?)
	state.phaseEndsAt = now() + duration
	broadcastState()
	while now() < state.phaseEndsAt do
		if stopEarly and stopEarly() then
			return
		end
		task.wait(0.1)
	end
end

local function everyoneGuessed(): boolean
	local guessers = 0
	for _, player in Players:GetPlayers() do
		if player ~= state.drawer then
			guessers += 1
			if not state.guessed[player] then
				return false
			end
		end
	end
	return guessers > 0
end

local function runTurn(drawer: Player)
	state.drawer = drawer
	state.word = nil
	state.customTimeGiven = false
	state.rated = {}
	state.revealed = {}
	state.guessed = {}
	state.guessCount = 0
	state.turnPoints = {}
	state.lastTurn = nil
	clearCanvas()

	-- Choosing
	local drawerGone = function()
		return not isPresent(drawer) or not enoughPlayers()
	end
	state.phase = "Choosing"
	state.wordOptions = pickWords(Config.WORD_CHOICES)
	WordChoiceEvent:FireClient(drawer, state.wordOptions)
	waitPhase(Config.CHOOSE_TIME, function()
		return state.word ~= nil or drawerGone()
	end)
	if drawerGone() then
		state.wordOptions = nil
		return
	end
	if not state.word then
		local options = state.wordOptions :: { string }
		state.word = options[math.random(#options)]
	end
	state.wordOptions = nil
	WordChoiceEvent:FireClient(drawer, nil)

	-- Drawing
	state.phase = "Drawing"
	state.turnStartedAt = now()
	systemMessage(drawer.DisplayName .. " is drawing now!")
	local hintsGiven = 0
	waitPhase(Config.DRAW_TIME, function()
		local elapsed = (now() - state.turnStartedAt) / Config.DRAW_TIME
		local nextHint = Config.HINT_FRACTIONS[hintsGiven + 1]
		if nextHint and elapsed >= nextHint then
			hintsGiven += 1
			revealRandomLetter()
			broadcastState()
		end
		return drawerGone() or everyoneGuessed()
	end)

	-- Turn end
	local results = {}
	for player, points in state.turnPoints do
		if isPresent(player) then
			table.insert(results, {
				userId = player.UserId,
				name = player.DisplayName,
				points = points,
				isDrawer = player == drawer,
			})
		end
	end
	table.sort(results, function(a, b)
		return a.points > b.points
	end)
	local allGuessed = isPresent(drawer) and everyoneGuessed()
	state.lastTurn = {
		word = state.word,
		drawerName = drawer.DisplayName,
		everyoneGuessed = allGuessed,
		reason = if not isPresent(drawer)
			then "The drawer left."
			elseif allGuessed then "Everyone guessed it!"
			else "Time's up!",
		results = results,
	}
	state.phase = "TurnEnd"
	systemMessage(`The word was '{state.word}'`, "reveal")
	waitPhase(Config.TURN_END_TIME)
	state.drawer = nil
	state.word = nil
end

local function finishMatch()
	local ranking = {}
	for _, player in Players:GetPlayers() do
		table.insert(ranking, { player = player, score = scores[player] or 0 })
	end
	table.sort(ranking, function(a, b)
		return a.score > b.score
	end)

	-- Ties share a place; the podium shows places 1-3.
	local winners = {}
	local place = 0
	local lastScore = nil
	for i, entry in ranking do
		if entry.score ~= lastScore then
			place = i
			lastScore = entry.score
		end
		if place > 3 then
			break
		end
		table.insert(winners, {
			place = place,
			userId = entry.player.UserId,
			name = entry.player.DisplayName,
			score = entry.score,
		})
		if place == 1 then
			addWin(entry.player)
		end
	end
	state.winners = winners

	local champions = {}
	for _, winner in winners do
		if winner.place == 1 then
			table.insert(champions, winner.name)
		end
	end
	systemMessage(`{table.concat(champions, " & ")} won the match!`, "correct")

	state.phase = "MatchEnd"
	waitPhase(Config.MATCH_END_TIME)
	state.winners = nil
end

-- Returns true when every round was played, false if the match was cut short.
local function runMatch(): boolean
	table.clear(scores)
	table.clear(usedWords)
	for _, player in Players:GetPlayers() do
		scores[player] = 0
		setLeaderstat(player, "Score", 0)
	end

	for round = 1, Config.ROUNDS_PER_MATCH do
		state.round = round
		systemMessage(`Round {round} of {Config.ROUNDS_PER_MATCH}`)
		-- Players who join mid-round guess now and draw from the next round on.
		for _, drawer in Players:GetPlayers() do
			if not enoughPlayers() then
				return false
			end
			if isPresent(drawer) then
				runTurn(drawer)
			end
		end
	end
	return enoughPlayers()
end

local function resetToWaiting()
	state.phase = "Waiting"
	state.round = 0
	state.drawer = nil
	state.word = nil
	state.guessed = {}
	state.lastTurn = nil
	state.winners = nil
	state.phaseEndsAt = 0
	broadcastState()
end

task.spawn(function()
	while true do
		resetToWaiting()
		while not enoughPlayers() do
			task.wait(0.5)
		end

		state.phase = "Starting"
		waitPhase(Config.STARTING_TIME, function()
			return not enoughPlayers()
		end)
		if enoughPlayers() then
			clearCanvas()
			if runMatch() then
				finishMatch()
			else
				systemMessage("Not enough players - the match was cancelled.")
			end
		end
	end
end)

-- Thumbs up / down and vote kick ------------------------------------------------------

-- kickVotes[target][voter] = true. Kicked players can't come back to this server.
local kickVotes: { [Player]: { [Player]: boolean } } = {}
local kickedUserIds: { [number]: boolean } = {}

local function kickVotesNeeded(): number
	local others = #Players:GetPlayers() - 1
	return math.max(Config.VOTE_KICK_MIN, math.ceil(others * Config.VOTE_KICK_SHARE))
end

VoteEvent.OnServerEvent:Connect(function(player, kind, targetUserId)
	if kind == "like" or kind == "dislike" then
		-- Everyone but the drawer can rate each drawing once.
		if state.phase ~= "Drawing" or player == state.drawer or state.rated[player] then
			return
		end
		state.rated[player] = true
		systemMessage(
			if kind == "like" then `{player.DisplayName} liked the drawing!` else `{player.DisplayName} disliked the drawing!`,
			kind
		)
		return
	end

	if kind == "kick" and typeof(targetUserId) == "number" then
		local target = Players:GetPlayerByUserId(targetUserId)
		if not target or target == player then
			return
		end
		local votes = kickVotes[target] or {}
		kickVotes[target] = votes
		if votes[player] then
			return
		end
		votes[player] = true
		local count = 0
		for voter in votes do
			if voter.Parent == Players then
				count += 1
			end
		end
		local needed = kickVotesNeeded()
		systemMessage(`{player.DisplayName} is voting to kick {target.DisplayName} ({count}/{needed})`, "kick")
		if count >= needed then
			kickedUserIds[target.UserId] = true
			systemMessage(`{target.DisplayName} was kicked!`, "kick")
			target:Kick("You were vote-kicked from this server.")
		end
	end
end)

-- Players ----------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if kickedUserIds[player.UserId] then
		player:Kick("You were vote-kicked from this server.")
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local score = Instance.new("IntValue")
	score.Name = "Score"
	score.Parent = stats
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = stats
	stats.Parent = player

	scores[player] = 0
	allTimeWins[player] = 0
	systemMessage(`{player.DisplayName} joined the room!`, "join")
	broadcastState()
	task.spawn(loadWins, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	if scores[player] == nil then
		return -- turned away on joining (vote-kicked earlier), so never really joined
	end
	systemMessage(`{player.DisplayName} left the room!`, "leave")
	scores[player] = nil
	allTimeWins[player] = nil
	readyPlayers[player] = nil
	drawRate[player] = nil
	lastFillAt[player] = nil
	passwordFailures[player] = nil
	state.rated[player] = nil
	-- Votes against or by a player who leaves no longer count.
	kickVotes[player] = nil
	for _, votes in kickVotes do
		votes[player] = nil
	end
	lastGuessAt[player] = nil
	state.guessed[player] = nil
	state.turnPoints[player] = nil
	task.defer(broadcastState)
end)
