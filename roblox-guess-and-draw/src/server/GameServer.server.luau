-- Runs the guess-and-draw game: matches of rounds, turns, scoring, guess checking,
-- and relaying the drawer's strokes to everyone else live.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("GuessAndDraw")
local Config = require(Shared:WaitForChild("Config"))
local Words = require(Shared:WaitForChild("Words"))
local Themes = require(Shared:WaitForChild("Themes"))

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
local VoteEvent = makeRemote("Vote") -- C->S: "like", "dislike", "kick" + user ID, or "report" + user ID + reason
local ThemeEvent = makeRemote("Theme") -- C->S: the player picked a word theme
local ShopEvent = makeRemote("Shop") -- C->S: buy or use an item; S->C: "nuke" effect
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
	customUnlocked = nil :: string?, -- "credit" or "free" once the drawer has paid for a custom word
	revealed = {} :: { [number]: boolean },
	turnStartedAt = 0,
	guessed = {} :: { [Player]: boolean },
	guessCount = 0,
	turnPoints = {} :: { [Player]: number },
	skipped = false, -- an admin skipped this turn
	lastTurn = nil :: any,
	winners = nil :: any,
}

-- The secret: typed into the chat on your turn to pick a word, it unlocks a free
-- custom word. It's never shown in chat, and server scripts never reach players'
-- computers, so nobody can read it out of the game.
local CUSTOM_WORD_PASSWORD = "poop123"

local scores: { [Player]: number } = {}
-- Robux items bought but not used yet, per player: credits[player][item] = count.
local credits: { [Player]: { [string]: number } } = {}
-- kickVotes[target][voter] = true.
local kickVotes: { [Player]: { [Player]: boolean } } = {}
-- Players kicked from this server, by user ID, and when (os.time) they may come
-- back; math.huge for a ban that lasts as long as the server.
local bans: { [number]: { untilTime: number, name: string } } = {}
local admins: { [Player]: boolean } = {}
local allTimeWins: { [Player]: number } = {} -- matches won, ever, saved in a DataStore

local usedWords: { [string]: boolean } = {}
-- Each player's chosen word theme; the drawer's sets the words and the background.
local playerThemes: { [Player]: string } = {}
local currentTheme = Config.DEFAULT_THEME
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

local function pickWords(count: number, theme: string): { string }
	local lists = Words[theme] or Words.general
	local picks = {}
	for i = 1, count do
		local list = lists[TIERS[(i - 1) % #TIERS + 1]]
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

	local drawerVotes = 0
	local votedOnDrawer = false
	if state.drawer and kickVotes[state.drawer] then
		for voter in kickVotes[state.drawer] do
			if voter.Parent == Players then
				drawerVotes += 1
			end
		end
		votedOnDrawer = kickVotes[state.drawer][forPlayer] == true
	end

	return {
		phase = state.phase,
		round = state.round,
		theme = currentTheme,
		myTheme = playerThemes[forPlayer] or Config.DEFAULT_THEME,
		credits = credits[forPlayer] or {},
		drawerKickVotes = drawerVotes,
		votedOnDrawer = votedOnDrawer,
		kickVotesNeeded = math.max(Config.VOTE_KICK_MIN, math.ceil((#Players:GetPlayers() - 1) * Config.VOTE_KICK_SHARE)),
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

-- Scores a correct guess (typed, or bought with Insta Guess).
local function awardGuess(player: Player)
	state.guessed[player] = true
	state.guessCount += 1
	local timeLeft = math.clamp((state.phaseEndsAt - now()) / Config.DRAW_TIME, 0, 1)
	local points = math.floor(Config.MIN_GUESS_POINTS + (Config.MAX_GUESS_POINTS - Config.MIN_GUESS_POINTS) * timeLeft)
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
end

-- Admins and kicks ------------------------------------------------------------------------

local function checkAdmin(player: Player): boolean
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	for _, admin in Config.ADMINS do
		if admin == player.UserId or (typeof(admin) == "string" and string.lower(admin) == string.lower(player.Name)) then
			return true
		end
	end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		return ok and rank == 255 -- the group's owner
	end
	return false
end

-- When a kicked user may come back, as a sentence, or nil once they may.
local function rejoinNote(userId: number): string?
	local ban = bans[userId]
	if not ban then
		return nil
	end
	if ban.untilTime == math.huge then
		return "You can't rejoin this server - try another one!"
	end
	local secondsLeft = ban.untilTime - os.time()
	if secondsLeft <= 0 then
		bans[userId] = nil
		return nil
	end
	local minutes = math.ceil(secondsLeft / 60)
	return `You can rejoin this server in {minutes} minute{if minutes == 1 then "" else "s"}, or try another server now.`
end

-- Kicks a player and keeps them out of this server for `minutes` (math.huge: for
-- good; 0: they can come straight back).
local function banFromServer(player: Player, minutes: number, reason: string)
	if minutes > 0 then
		bans[player.UserId] = {
			untilTime = if minutes == math.huge then math.huge else os.time() + minutes * 60,
			name = player.Name,
		}
	end
	local note = rejoinNote(player.UserId)
	player:Kick(if note then `{reason} {note}` else reason)
end

-- A player by (the start of) their username or display name.
local function findPlayer(query: string): (Player?, string?)
	query = string.lower(query)
	local matches = {}
	for _, player in Players:GetPlayers() do
		local name, display = string.lower(player.Name), string.lower(player.DisplayName)
		if name == query or display == query then
			return player
		end
		if string.sub(name, 1, #query) == query or string.sub(display, 1, #query) == query then
			table.insert(matches, player)
		end
	end
	if #matches == 1 then
		return matches[1]
	end
	return nil, if #matches == 0 then `Nobody here is called "{query}".` else `"{query}" matches more than one player - type more of the name.`
end

local ADMIN_HELP = {
	"Admin commands:",
	"/kick name [minutes] - kick someone (default " .. Config.VOTE_KICK_BAN_MINUTES .. " min before they can rejoin; 0 lets them straight back)",
	"/ban name - kick someone until this server closes",
	"/unban name - let a kicked player back in (/unban all for everyone)",
	"/skip - end this turn and move on",
	"/clear - wipe the drawing",
	"/announce message - post a message to everyone",
}

local function runAdminCommand(admin: Player, text: string)
	local command, rest = string.match(text, "^[/:](%a+)%s*(.*)$")
	command = string.lower(command or "")
	local function reply(message: string)
		systemMessage(message, "system", { admin })
	end

	if command == "kick" or command == "ban" then
		local query, minutesText = string.match(rest, "^(%S+)%s*(%S*)")
		if not query then
			reply(`Usage: /{command} name`)
			return
		end
		local target, problem = findPlayer(query)
		if not target then
			reply(problem :: string)
			return
		end
		if admins[target] then
			reply(`{target.DisplayName} is an admin.`)
			return
		end
		local minutes = if command == "ban" then math.huge else tonumber(minutesText) or Config.VOTE_KICK_BAN_MINUTES
		minutes = math.max(0, minutes)
		banFromServer(target, minutes, "You were kicked by an admin.")
		systemMessage(`{target.DisplayName} was kicked by an admin.`, "kick")
	elseif command == "unban" then
		if string.lower(rest) == "all" then
			table.clear(bans)
			reply("Everyone kicked from this server can rejoin now.")
			return
		end
		local query = string.lower(rest)
		for userId, ban in bans do
			if string.lower(ban.name) == query or tostring(userId) == query then
				bans[userId] = nil
				reply(`{ban.name} can rejoin now.`)
				return
			end
		end
		reply(if query == "" then "Usage: /unban name" else `Nobody called "{rest}" is kicked from this server.`)
	elseif command == "skip" then
		if state.phase == "Choosing" or state.phase == "Drawing" then
			state.skipped = true
			systemMessage("An admin skipped this turn.", "system")
		else
			state.phaseEndsAt = now() -- hurry along the countdown or the results screen
		end
	elseif command == "clear" then
		if state.phase == "Drawing" then
			clearCanvas()
			systemMessage("An admin cleared the drawing.", "system")
		else
			reply("There's no drawing to clear right now.")
		end
	elseif command == "announce" then
		local message = if rest ~= "" then filterForBroadcast(rest, admin) else nil
		if message then
			systemMessage(`📢 {message}`, "reveal")
		else
			reply("Usage: /announce message")
		end
	else
		for _, line in ADMIN_HELP do
			reply(line)
		end
	end
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

	-- Admin commands, like /kick or /skip. Never shown in chat.
	if admins[player] and string.match(text, "^[/:]%a") then
		runAdminCommand(player, text)
		return
	end

	-- The secret password, typed by the drawer while picking a word: a free custom
	-- word. Swallowed here, so nobody else ever sees it.
	if text == CUSTOM_WORD_PASSWORD and player == state.drawer and state.phase == "Choosing" and not state.word then
		state.customUnlocked = "free"
		if not state.customTimeGiven then
			state.customTimeGiven = true
			state.phaseEndsAt = math.max(state.phaseEndsAt, now() + Config.CUSTOM_WORD_TIME)
			broadcastState()
		end
		WordChoiceEvent:FireClient(player, { custom = true })
		return
	end

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
			awardGuess(player)
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

-- Words never allowed as custom words, on top of Roblox's own filter (which lets
-- everything through while testing in Studio). Short ones only match whole words,
-- so "class" or "grass" are fine; longer ones match anywhere in the word.
local BLOCKED_WORDS = {
	"anal", "anus", "arse", "ass", "butt", "cock", "crap", "cum", "damn", "dick", "fag", "hoe", "kkk", "kms",
	"kys", "nig", "rape", "sex", "tit", "wtf",
}
local BLOCKED_ANYWHERE = {
	"bastard", "bitch", "boner", "boob", "clit", "cunt", "dildo", "dyke", "fuck", "fuk", "hentai", "hitler",
	"horny", "jizz", "killyourself", "molest", "naked", "nazi", "nigg", "nipple", "nude", "orgasm", "penis",
	"piss", "porn", "pussy", "retard", "semen", "sexy", "shit", "slut", "sperm", "suicide", "testicle", "twat",
	"vagina", "wank", "whore", "xxx",
}

local function isBlockedWord(word: string): boolean
	local squashed = string.gsub(word, "[^%a]", "")
	for _, bad in BLOCKED_ANYWHERE do
		if string.find(squashed, bad, 1, true) then
			return true
		end
	end
	for piece in string.gmatch(word, "%a+") do
		if table.find(BLOCKED_WORDS, piece) then
			return true
		end
	end
	return false
end

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

	-- A custom word, once the drawer has paid for it (see the shop below).
	if typeof(choice) == "table" then
		local function reject(message: string)
			WordChoiceEvent:FireClient(player, { error = message })
		end
		if not state.customUnlocked then
			return
		end
		local word = if typeof(choice.word) == "string" then cleanCustomWord(choice.word) else nil
		if not word then
			reject("Use 2-30 letters (spaces, - and ' are OK).")
			return
		end
		if isBlockedWord(word) then
			reject("That word isn't allowed - keep it family friendly!")
			return
		end
		-- Everyone sees the word at the end of the turn, so it must pass Roblox's filter.
		local filtered = filterForBroadcast(word, player)
		if not stillChoosing() then
			return
		end
		if filtered ~= word then
			reject("That word isn't allowed - keep it family friendly!")
			return
		end
		-- The paid credit is only used up once a word is accepted.
		if state.customUnlocked == "credit" then
			local mine = credits[player]
			if not mine or (mine.customWord or 0) < 1 then
				return
			end
			mine.customWord -= 1
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
	state.customUnlocked = nil
	state.rated = {}
	state.revealed = {}
	state.guessed = {}
	state.guessCount = 0
	state.turnPoints = {}
	state.skipped = false
	state.lastTurn = nil
	clearCanvas()

	-- Choosing
	-- state.drawer, not `drawer`: someone may steal the drawing mid-turn.
	local drawerGone = function()
		return not isPresent(state.drawer) or not enoughPlayers() or state.skipped
	end
	state.phase = "Choosing"
	-- The drawer's theme picks the words and colours everyone's background.
	currentTheme = playerThemes[drawer] or Config.DEFAULT_THEME
	state.wordOptions = pickWords(Config.WORD_CHOICES, currentTheme)
	WordChoiceEvent:FireClient(drawer, state.wordOptions)
	waitPhase(Config.CHOOSE_TIME, function()
		return state.word ~= nil or drawerGone()
	end)
	if drawerGone() then
		state.wordOptions = nil
		if isPresent(drawer) then
			WordChoiceEvent:FireClient(drawer, nil) -- skipped: close their word choices
		end
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
	local theme = Themes.byId[currentTheme]
	systemMessage(`{drawer.DisplayName} is drawing now! ({theme.emoji} {theme.name})`)
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
		reason = if state.skipped
			then "An admin skipped the turn."
			elseif not isPresent(drawer) then "The drawer left."
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

local function kickVotesNeeded(): number
	local others = #Players:GetPlayers() - 1
	return math.max(Config.VOTE_KICK_MIN, math.ceil(others * Config.VOTE_KICK_SHARE))
end

local REPORT_REASONS = { "Inappropriate drawing", "Bad language", "Cheating or spamming", "Being mean" }
local lastReportAt: { [Player]: number } = {}
local reportStore: DataStore? = nil
pcall(function()
	reportStore = DataStoreService:GetDataStore("GuessAndDrawReports")
end)

VoteEvent.OnServerEvent:Connect(function(player, kind, targetUserId, reason)
	-- Reports are saved so the game's owner can review them (Creator Hub → your game →
	-- Data Stores → GuessAndDrawReports) and printed in the server's output.
	if kind == "report" then
		local target = if typeof(targetUserId) == "number" then Players:GetPlayerByUserId(targetUserId) else nil
		if not target or target == player or not table.find(REPORT_REASONS, reason) then
			return
		end
		local t = os.clock()
		if lastReportAt[player] and t - lastReportAt[player] < 20 then
			systemMessage("Please wait a moment before sending another report.", "system", { player })
			return
		end
		lastReportAt[player] = t
		local report = {
			reporter = player.UserId,
			reporterName = player.Name,
			reported = target.UserId,
			reportedName = target.Name,
			reason = reason,
			time = os.time(),
		}
		warn(`[Report] {player.Name} reported {target.Name}: {reason}`)
		local store = reportStore
		if store then
			task.spawn(pcall, function()
				store:SetAsync(`{os.time()}_{player.UserId}`, report)
			end)
		end
		systemMessage(
			"Thanks - your report was sent. For anything serious, also report them in Roblox's menu (☰ → Report).",
			"system",
			{ player }
		)
		return
	end

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
		if admins[target] then
			systemMessage(`{target.DisplayName} is an admin and can't be vote-kicked.`, "system", { player })
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
			banFromServer(target, Config.VOTE_KICK_BAN_MINUTES, "You were vote-kicked from this server.")
			systemMessage(`{target.DisplayName} was kicked!`, "kick")
		end
	end
end)

-- Word themes --------------------------------------------------------------------------

ThemeEvent.OnServerEvent:Connect(function(player, themeId)
	if typeof(themeId) ~= "string" or not Themes.byId[themeId] then
		return
	end
	playerThemes[player] = themeId
	StateEvent:FireClient(player, buildSnapshot(player))
end)

-- Robux shop --------------------------------------------------------------------------

-- Buying an item gives the player a credit, which is used straight away if it can
-- be. If not (say the turn ended while they were paying), it's kept for later in
-- this server, so nobody pays for nothing.

local PRODUCT_ITEMS: { [number]: string } = {}
for item, product in Config.PRODUCTS do
	if product.id ~= 0 then
		PRODUCT_ITEMS[product.id] = item
	end
end

local function notify(player: Player, text: string)
	systemMessage(text, "system", { player })
end

local function addCredit(player: Player, item: string)
	local mine = credits[player] or {}
	credits[player] = mine
	mine[item] = (mine[item] or 0) + 1
end

-- Can `item` be used by `player` right now? If not, says why.
local function canUse(player: Player, item: string): (boolean, string?)
	if item == "customWord" then
		if player ~= state.drawer or state.phase ~= "Choosing" or state.word then
			return false, "Custom words can be bought when it's your turn to pick a word."
		end
		return true
	end
	if state.phase ~= "Drawing" or not isPresent(state.drawer) then
		return false, "Use that while someone is drawing."
	end
	if player == state.drawer then
		return false, "You can't use that on your own drawing."
	end
	if item == "instaGuess" and state.guessed[player] then
		return false, "You already guessed this one."
	end
	return true
end

-- Gives the drawer extra time to buy and type a custom word (once per turn).
local function giveCustomWordTime()
	if not state.customTimeGiven then
		state.customTimeGiven = true
		state.phaseEndsAt = math.max(state.phaseEndsAt, now() + Config.CUSTOM_WORD_TIME)
		broadcastState()
	end
end

-- Uses one of the player's credits for `item`. Returns whether it was used and,
-- if not, why.
local function useItem(player: Player, item: string): (boolean, string?)
	local mine = credits[player]
	if not mine or (mine[item] or 0) < 1 then
		return false
	end
	local usable, why = canUse(player, item)
	if not usable then
		return false, `{why} It's saved for later.`
	end

	if item == "customWord" then
		-- The credit is spent once a word is accepted; for now, open the form.
		state.customUnlocked = "credit"
		giveCustomWordTime()
		WordChoiceEvent:FireClient(player, { custom = true })
		return true
	end

	mine[item] -= 1
	if item == "instaGuess" then
		systemMessage(`⚡ {player.DisplayName} used Insta Guess!`, "power")
		awardGuess(player)
	elseif item == "nuke" then
		clearCanvas()
		ShopEvent:FireAllClients("nuke")
		systemMessage(`💥 {player.DisplayName} nuked the drawing!`, "power")
	elseif item == "steal" then
		local victim = state.drawer :: Player
		state.drawer = player
		state.guessed[player] = nil
		state.guessed[victim] = true -- they know the word, so now they just watch and chat
		systemMessage(`🦹 {player.DisplayName} stole the drawing from {victim.DisplayName}!`, "power")
	end
	broadcastState()
	return true
end

ShopEvent.OnServerEvent:Connect(function(player, item)
	local product = if typeof(item) == "string" then Config.PRODUCTS[item] else nil
	if not product then
		return
	end
	-- Already paid for a custom word this turn: just reopen the form.
	if item == "customWord" and state.customUnlocked and player == state.drawer and state.phase == "Choosing" then
		WordChoiceEvent:FireClient(player, { custom = true })
		return
	end
	-- Has one saved? Use it instead of buying another.
	if credits[player] and (credits[player][item] or 0) > 0 then
		local used, why = useItem(player, item)
		if not used and why then
			notify(player, why)
		end
		return
	end
	-- Don't charge for something that can't be used right now.
	local usable, why = canUse(player, item)
	if not usable then
		notify(player, why :: string)
		return
	end
	if item == "customWord" then
		giveCustomWordTime() -- the purchase window takes a few seconds
	end
	if product.id == 0 then
		if RunService:IsStudio() then
			-- Not set up yet: free while testing in Studio.
			addCredit(player, item)
			useItem(player, item)
		else
			notify(player, "That isn't for sale yet.")
		end
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.id)
end)

-- Roblox calls this once a purchase is paid for (again, if the server didn't confirm).
local processedPurchases: { [string]: boolean } = {}
MarketplaceService.ProcessReceipt = function(receipt)
	if processedPurchases[receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local item = PRODUCT_ITEMS[receipt.ProductId]
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not item or not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- try again when they're back
	end
	processedPurchases[receipt.PurchaseId] = true
	addCredit(player, item)
	local used, why = useItem(player, item)
	if not used then
		notify(player, why or "Saved for later!")
	end
	broadcastState()
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Players ----------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	admins[player] = checkAdmin(player)
	local note = if admins[player] then nil else rejoinNote(player.UserId)
	if note then
		player:Kick(`You were kicked from this server. {note}`)
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
		admins[player] = nil
		return -- turned away on joining (kicked earlier), so never really joined
	end
	admins[player] = nil
	systemMessage(`{player.DisplayName} left the room!`, "leave")
	scores[player] = nil
	allTimeWins[player] = nil
	readyPlayers[player] = nil
	drawRate[player] = nil
	lastFillAt[player] = nil
	credits[player] = nil
	playerThemes[player] = nil
	lastReportAt[player] = nil
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
