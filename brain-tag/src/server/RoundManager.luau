-- The round loop: Waiting -> Prep -> Outbreak -> Infection -> End -> (reset) -> Prep.
--
-- Prep: everyone is human; the banner counts down "Outbreak happening in N
-- seconds"; humans shop and barricade. Outbreak: first zombies are picked,
-- weighted by immunity. Infection: a zombie touching a human converts them.
-- Zombies win when no humans remain; survivors win if anyone lasts the timer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Announcer = require(script.Parent.Announcer)
local CharacterLook = require(ReplicatedStorage.Shared.CharacterLook)
local CharacterService = require(script.Parent.CharacterService)
local Combat = require(script.Parent.Combat)
local Config = require(ReplicatedStorage.Shared.Config)
local FurnitureService = require(script.Parent.FurnitureService)
local ItemService = require(script.Parent.ItemService)
local Items = require(ReplicatedStorage.Shared.Items)
local MapBuilder = require(script.Parent.MapBuilder)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Participants = require(script.Parent.Participants)
local Projectiles = require(script.Parent.Projectiles)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Traps = require(script.Parent.Traps)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local Util = require(ReplicatedStorage.Shared.Util)
local Wizard = require(script.Parent.Wizard)

type Participant = Participants.Participant
type Phase = "Waiting" | "Prep" | "Infection" | "End"
type Winner = RoundRules.Winner

local RoundManager = {}

local state: Folder
local phase: Phase = "Waiting"
local rng = Random.new()

-- Spawning ---------------------------------------------------------------------------

local function spawnFrame(team: string, scale: number): CFrame
	local layout = MapLayout.current()
	local list = if team == "Zombie" then layout.zombieSpawns else layout.humanSpawns
	local spot = list[rng:NextInteger(1, #list)]
	local jitter = if team == "Zombie" then 3 else 5
	local x = spot.x + rng:NextNumber(-jitter, jitter)
	local z = spot.z + rng:NextNumber(-jitter, jitter)
	local y = MapLayout.HEIGHTS.Floor
		+ Config.CHARACTER.HipHeight
		+ Config.CHARACTER.RootHeight / 2 * scale
		+ 0.3
	return CFrame.new(x, y, z)
end

-- Every human starts the round at the map's start spot, packed into a
-- little crowd around it (a sunflower spiral, so nobody lands on anyone).
local crowd = 0

local function startFrame(scale: number): CFrame
	local spot = MapLayout.current().start
	crowd += 1
	local radius = 2.4 * math.sqrt(crowd - 1) * math.max(1, scale)
	local angle = crowd * 2.39996
	local y = MapLayout.HEIGHTS.Floor
		+ Config.CHARACTER.HipHeight
		+ Config.CHARACTER.RootHeight / 2 * scale
		+ 0.3
	return CFrame.new(spot.x + math.cos(angle) * radius, y, spot.z + math.sin(angle) * radius)
end

local function recount()
	state:SetAttribute("Survivors", #Participants.onTeam("Human"))
	state:SetAttribute("Zombies", #Participants.onTeam("Zombie"))
end

function RoundManager.phase(): Phase
	return phase
end

local function setPhase(name: Phase, seconds: number)
	phase = name
	state:SetAttribute("Phase", name)
	state:SetAttribute("PhaseEndsAt", workspace:GetServerTimeNow() + seconds)
end

local function secondsLeft(): number
	return (state:GetAttribute("PhaseEndsAt") :: number) - workspace:GetServerTimeNow()
end

function RoundManager.secondsLeft(): number
	return secondsLeft()
end

-- Teams --------------------------------------------------------------------------------

function RoundManager.setTeam(p: Participant, team: Participants.Team)
	if p.team == team then
		return
	end
	p.team = team
	p.state:SetAttribute("Team", team)
	p.boostUntil, p.slowUntil = 0, 0 -- drinks and freezes don't carry across teams
	if team == "Human" then
		p.alpha = false
	end
	if team == "Zombie" then
		ItemService.onInfected(p)
	end
	CharacterService.applyLook(p)
	CharacterService.refreshSpeed(p)
	ItemService.refreshHand(p)
	recount()
end

local function bonusesFor(p: Participant, includeDrumstick: boolean): RoundRules.RewardBonuses
	-- A drumstick anywhere in your inventory counts (the best one).
	local drumstick: number? = nil
	for _, slot in p.slots do
		local item = Items.get(slot.id)
		if item and item.kind == "Passive" and item.rewardBonus then
			drumstick = math.max(drumstick or 0, item.rewardBonus)
		end
	end
	return {
		drumstick = if includeDrumstick then drumstick else nil,
		vip = p.passes.VIP == true,
		doubleScore = p.passes.DoubleScore == true,
		boosted = os.time() < p.boostEndsAt,
	}
end

local function award(p: Participant, base: number, includeDrumstick: boolean, reason: string)
	local amount = RoundRules.reward(base, bonusesFor(p, includeDrumstick))
	Participants.addScore(p, amount)
	CharacterService.refreshSize(p)
	CharacterService.refreshSpeed(p)
	if p.player then
		Announcer.toast(
			p.player,
			string.format("+%s score  %s", Util.commas(amount), reason),
			Config.COLORS.Good
		)
	end
end

-- Every few seconds of the outbreak: a little score for every human still
-- standing, and every zombie loses a little (it has to eat to stay big).
local function payStanding()
	for _, p in Participants.all() do
		if not Participants.body(p) then
			continue
		end
		if p.team == "Human" then
			Participants.addScore(p, RoundRules.reward(Config.SURVIVAL_POINTS, bonusesFor(p, false)))
		elseif p.score > 0 then
			local loss = math.max(Config.ZOMBIE_DECAY_MIN, math.floor(p.score * Config.ZOMBIE_DECAY_FRACTION))
			Participants.addScore(p, -loss)
		end
		CharacterService.refreshSize(p)
		CharacterService.refreshSpeed(p)
	end
end

local function infect(zombie: Participant, human: Participant)
	local root = Participants.body(human)
	-- The zombie eats a share of the human's points: the human shrinks and
	-- slows, the zombie grows and speeds up.
	local stolen = math.floor(human.score * Config.INFECT_STEAL_FRACTION)
	if stolen > 0 then
		Participants.addScore(human, -stolen)
		Participants.addScore(zombie, stolen)
		human.scale = RoundRules.scaleForScore(human.score)
		human.state:SetAttribute("Scale", human.scale)
		if human.player then
			Announcer.toast(
				human.player,
				string.format("-%s points: %s ate them!", Util.commas(stolen), zombie.name),
				Config.COLORS.ZombieText
			)
		end
		if zombie.player then
			Announcer.toast(
				zombie.player,
				string.format("+%s points eaten from %s", Util.commas(stolen), human.name),
				Config.COLORS.Good
			)
		end
	end
	RoundManager.setTeam(human, "Zombie") -- rebuilds the look at the new size
	CharacterService.refreshSpeed(human)
	award(zombie, Config.INFECT_REWARD, false, "infection")
	if zombie.profile then
		zombie.profile.Infections = (zombie.profile.Infections or 0) + 1
		zombie.state:SetAttribute("Infections", zombie.profile.Infections)
	end
	if root then
		Announcer.fx("Infect", { position = root.Position })
	end
	Announcer.chat(string.format("%s infected %s!", zombie.name, human.name), "9BE22D")
end

-- Does any part of the zombie touch the human? Its body, or the arms
-- reaching out in front of it (the box they sweep, in the zombie's own
-- frame), against the human's body circle.
local ARM_REACH = CharacterLook.ZOMBIE_ARM_REACH
local ARM_SPAN = CharacterLook.ZOMBIE_ARM_SPAN

local function touching(zRoot: BasePart, zScale: number, hRoot: BasePart, hScale: number): boolean
	local shell = Config.CHARACTER.ShellDiameter / 2
	local hr = shell * hScale + 0.25
	local offset = Util.flat(hRoot.Position - zRoot.Position)
	if offset.Magnitude <= hr + shell * zScale then
		return true
	end
	if offset.Magnitude > hr + (ARM_REACH + ARM_SPAN) * zScale then
		return false
	end
	local rel = zRoot.CFrame:VectorToObjectSpace(offset)
	local x = math.clamp(rel.X, -ARM_SPAN * zScale, ARM_SPAN * zScale)
	local z = math.clamp(rel.Z, -ARM_REACH * zScale, 0)
	local dx, dz = rel.X - x, rel.Z - z
	return dx * dx + dz * dz <= hr * hr
end

-- Every frame of the infection phase: a single touch from any part of a
-- zombie (with no wall or furniture between them) converts the human.
local function infectionStep()
	if phase ~= "Infection" then
		return
	end
	local zombies = Participants.onTeam("Zombie")
	local humans = Participants.onTeam("Human")
	for _, human in humans do
		local hRoot = Participants.body(human)
		if hRoot and human.team == "Human" then
			for _, zombie in zombies do
				local zRoot = Participants.body(zombie)
				if zRoot and zombie.team == "Zombie" then
					if
						touching(zRoot, zombie.scale, hRoot, human.scale)
						and Combat.clearPath(zRoot.Position, hRoot.Position)
					then
						infect(zombie, human)
						break
					end
				end
			end
		end
	end
end

-- World reset ---------------------------------------------------------------------------

local function grantRoundStartItems(p: Participant)
	if not ItemService.hasFreeSlot(p) then
		return
	end
	local profile = p.profile
	if profile and profile.PendingItems and #profile.PendingItems > 0 then
		local itemId = table.remove(profile.PendingItems, 1)
		if typeof(itemId) == "string" and Items.get(itemId) then
			ItemService.give(p, itemId)
			if p.player then
				Announcer.toast(
					p.player,
					"Your " .. (Items.get(itemId) :: Items.Item).name .. " is ready!",
					Config.COLORS.Good
				)
			end
			return
		end
	end
	if p.passes.StarterKit and not ItemService.carries(p, "Bat") then
		ItemService.give(p, "Bat")
	end
end

-- Everyone back to human at a yard spawn, furniture and walls restored.
local function resetWorld()
	Wizard.leave()
	Projectiles.clear()
	Traps.clear()
	ItemService.clearGround()
	FurnitureService.resetAll()
	MapBuilder.restoreWalls()
	crowd = 0
	for _, p in Participants.all() do
		p.team = "Human"
		p.stunUntil = 0
		p.boostUntil, p.slowUntil = 0, 0
		p.alpha = false
		p.scale = RoundRules.scaleForScore(p.score) -- you grow as your score grows
		p.state:SetAttribute("Team", "Human")
		p.state:SetAttribute("Scale", p.scale)
		CharacterService.place(p, startFrame(p.scale))
		CharacterService.applyLook(p)
		CharacterService.refreshSpeed(p)
		grantRoundStartItems(p)
		ItemService.refreshHand(p)
	end
	recount()
end

-- Phases ----------------------------------------------------------------------------------

local function enoughPlayers(): boolean
	return Participants.count() >= Config.MIN_PLAYERS
end

local function waitForPlayers()
	if enoughPlayers() then
		return
	end
	setPhase("Waiting", 0)
	resetWorld()
	while not enoughPlayers() do
		state:SetAttribute("Needed", Config.MIN_PLAYERS)
		task.wait(1)
	end
end

-- Waits until the phase timer ends. Returns false if players dropped below
-- the minimum (round aborted).
-- An admin ended the round: it stops with no winner and the next one starts.
local endRequested = false

local function waitPhase(): boolean
	while secondsLeft() > 0 do
		if not enoughPlayers() or endRequested then
			return false
		end
		task.wait(0.2)
	end
	return not endRequested
end

local function pickFirstZombies(): { Participant }
	local candidates = {}
	for _, p in Participants.onTeam("Human") do
		if Participants.body(p) then
			table.insert(candidates, p)
		end
	end
	local count = RoundRules.firstZombieCount(#candidates)
	return RoundRules.weightedPick(
		candidates,
		function(p: Participant)
			return RoundRules.zombieWeight(p.immunity)
		end,
		count,
		function()
			return rng:NextNumber()
		end
	)
end

local function turnFirstZombie(p: Participant)
	p.alpha = true -- the alpha look (see Skins "Alpha")
	RoundManager.setTeam(p, "Zombie")
	Participants.setImmunity(p, 0)
	if Config.FIRST_ZOMBIES_TO_SPAWN then
		CharacterService.place(p, spawnFrame("Zombie", p.scale))
	end
	p.returnReadyAt = os.clock() + 1
end

local function outbreak()
	Wizard.leave()
	local picked = pickFirstZombies()
	local names = {}
	for _, p in picked do
		turnFirstZombie(p)
		table.insert(names, p.name)
	end
	Announcer.chat(
		"* OUTBREAK! "
			.. table.concat(names, ", ")
			.. (if #names == 1 then " is" else " are")
			.. " a zombie! *",
		"E0303A"
	)
	Announcer.fx("Outbreak", {})
end

local function finishRound(winner: Winner)
	setPhase("End", Config.END_SCREEN_SECONDS)
	state:SetAttribute("Winner", winner)
	for _, p in Participants.all() do
		if p.profile then
			p.profile.RoundsPlayed = (p.profile.RoundsPlayed or 0) + 1
			p.state:SetAttribute("RoundsPlayed", p.profile.RoundsPlayed)
		end
		if winner == "Survivors" and p.team == "Human" then
			award(p, Config.SURVIVOR_WIN_REWARD, true, "survived!")
			if p.profile then
				p.profile.Wins = (p.profile.Wins or 0) + 1
				p.state:SetAttribute("Wins", p.profile.Wins)
			end
		elseif winner == "Zombies" and p.team == "Zombie" then
			award(p, Config.ZOMBIE_WIN_REWARD, false, "zombies win")
		end
	end
	Announcer.chat(if winner == "Survivors" then "Survivors Win!!!" else "Zombies Win!!!")
	Announcer.fx("RoundEnd", { winner = winner })
	task.wait(Config.END_SCREEN_SECONDS)
	state:SetAttribute("Winner", "")
end

local function runInfection(): Winner?
	setPhase("Infection", Config.ROUND_SECONDS)
	local nextPay = os.clock() + Config.SURVIVAL_POINTS_SECONDS
	while true do
		task.wait(0.1)
		if endRequested then
			return nil
		end
		if os.clock() >= nextPay then
			nextPay += Config.SURVIVAL_POINTS_SECONDS
			payStanding()
		end
		local humans = Participants.onTeam("Human")
		local zombies = Participants.onTeam("Zombie")
		local result = RoundRules.outcome(#humans, secondsLeft())
		if result then
			return result :: Winner
		end
		if #zombies == 0 then
			-- Every zombie left the game: pick a new one, or let the humans win.
			if #humans >= 2 then
				local replacement = pickFirstZombies()[1]
				if replacement then
					turnFirstZombie(replacement)
					Announcer.chat("* The zombies fled... " .. replacement.name .. " turned! *", "E0303A")
				end
			else
				return "Survivors" :: Winner
			end
		end
	end
end

-- Map rotation ------------------------------------------------------------------------------

local rotation: { string } = {} -- built-in maps plus yours (MapLayout.rotation)
local mapIndex = 1
local roundsOnMap = 0
local pendingMap: string? = nil -- an admin picked the next map

local function loadMap(name: string)
	local layout = MapLayout.use(name)
	ItemService.clearGround()
	MapBuilder.build(layout)
	FurnitureService.build(layout)
	state:SetAttribute("Map", layout.title)
	Announcer.chat("* Next map: " .. layout.title .. " *")
end

local function nextMapIfDue()
	local picked = pendingMap
	if picked then
		pendingMap = nil
		roundsOnMap = 0
		mapIndex = table.find(rotation, picked) or mapIndex
		loadMap(picked)
	elseif roundsOnMap >= Config.ROUNDS_PER_MAP and #rotation > 1 then
		roundsOnMap = 0
		mapIndex = mapIndex % #rotation + 1
		loadMap(rotation[mapIndex])
	end
	roundsOnMap += 1
end

local function runRound()
	endRequested = false
	waitForPlayers()

	nextMapIfDue()
	resetWorld()
	local round = state:GetAttribute("Round")
	state:SetAttribute("Round", (if typeof(round) == "number" then round else 0) + 1)
	ItemService.scatter()
	setPhase("Prep", Config.PREP_SECONDS)
	Wizard.schedule()
	Announcer.chat(
		MapLayout.current().title
			.. ": outbreak in "
			.. Config.PREP_SECONDS
			.. " seconds. Barricade a room and grab items!"
	)
	if waitPhase() then
		outbreak()
		local winner = runInfection()
		if winner then
			finishRound(winner :: Winner)
		end
	end
end

local function loop()
	while true do
		local ok, err = pcall(function()
			runRound()
			return true
		end)
		if not ok then
			warn("[Rounds] round failed, starting a new one: " .. tostring(err))
			state:SetAttribute("Winner", "")
			task.wait(2)
		end
	end
end

-- Joining, leaving, respawning ----------------------------------------------------------------

local function spawnNew(p: Participant)
	p.scale = RoundRules.scaleForScore(p.score)
	p.state:SetAttribute("Scale", p.scale)
	-- Late joiners become zombies once the outbreak has happened.
	if phase == "Infection" then
		p.team = "Zombie"
		p.state:SetAttribute("Team", "Zombie")
	end
	-- Humans joining before the outbreak start with everyone else.
	CharacterService.spawn(p, if p.team == "Human" then startFrame(p.scale) else spawnFrame(p.team, p.scale))
	if p.team == "Human" then
		grantRoundStartItems(p)
	end
	ItemService.refreshHand(p)
	recount()
end

-- "Z": back to the zombie spawn, with a whoosh where you left.
local function warp(p: Participant)
	local root = Participants.body(p)
	if root then
		Announcer.fx("Warp", { position = root.Position })
	end
	CharacterService.place(p, spawnFrame("Zombie", p.scale))
end

local function onZombieReturn(player: Player)
	local p = Participants.fromPlayer(player)
	if not p or p.team ~= "Zombie" or phase ~= "Infection" then
		return
	end
	local now = os.clock()
	if now < p.returnReadyAt then
		return
	end
	p.returnReadyAt = now + Config.ZOMBIE_RETURN_COOLDOWN
	warp(p)
end

function RoundManager.roundNumber(): number
	local round = state:GetAttribute("Round")
	return if typeof(round) == "number" then round else 0
end

-- Admin controls -------------------------------------------------------------------------------

-- Ends the current phase now (prep -> outbreak, infection -> survivors win).
function RoundManager.skipPhase(): boolean
	if phase == "Waiting" or phase == "End" then
		return false
	end
	state:SetAttribute("PhaseEndsAt", workspace:GetServerTimeNow())
	return true
end

-- Ends the whole round now (no winner, no rewards); the next round starts
-- right away, on the map an admin queued if any.
function RoundManager.endRound(): boolean
	if phase == "Waiting" then
		return false
	end
	endRequested = true
	Announcer.chat("* An admin ended the round *")
	return true
end

-- The maps in the rotation, in order (built-in and Studio-made).
function RoundManager.mapNames(): { string }
	return rotation
end

function RoundManager.addTime(seconds: number): boolean
	local endsAt = state:GetAttribute("PhaseEndsAt")
	if typeof(endsAt) ~= "number" or phase == "Waiting" or phase == "End" then
		return false
	end
	state:SetAttribute("PhaseEndsAt", endsAt + seconds)
	return true
end

-- The next round starts on the next map in the rotation.
function RoundManager.queueNextMap(): boolean
	if #rotation < 2 then
		return false
	end
	pendingMap = nil
	roundsOnMap = Config.ROUNDS_PER_MAP
	return true
end

-- The next round starts on this map.
function RoundManager.queueMap(name: string): boolean
	if not MapLayout.get(name) then
		return false
	end
	pendingMap = name
	return true
end

function RoundManager.respawn(p: Participant)
	CharacterService.spawn(p, spawnFrame(p.team, p.scale))
	ItemService.refreshHand(p)
end

-- Lets bots press Z too.
function RoundManager.zombieReturn(p: Participant)
	if p.team == "Zombie" and phase == "Infection" and os.clock() >= p.returnReadyAt then
		p.returnReadyAt = os.clock() + Config.ZOMBIE_RETURN_COOLDOWN
		warp(p)
	end
end

function RoundManager.start()
	state = ReplicatedStorage:WaitForChild("BrainTagState") :: Folder
	state:SetAttribute("Map", MapLayout.current().title)
	rotation = MapLayout.rotation(Config.MAP_ROTATION)
	mapIndex = table.find(rotation, MapLayout.current().name) or 1
	state:SetAttribute("Maps", table.concat(rotation, "|")) -- for the admin panel

	CharacterService.onNeedRespawn = function(p)
		CharacterService.spawn(p, spawnFrame(p.team, p.scale))
		ItemService.refreshHand(p)
	end

	Participants.onAdded(spawnNew)
	Participants.onRemoving(function(p)
		if p.isBot and p.character then
			p.character:Destroy()
		end
		task.defer(recount)
	end)

	Remotes.event("ZombieReturn").OnServerEvent:Connect(onZombieReturn)
	RunService.Heartbeat:Connect(infectionStep)
	task.spawn(loop)
end

return RoundManager
