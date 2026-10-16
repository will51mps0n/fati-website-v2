-- The round loop: Waiting -> Prep -> Outbreak -> Infection -> End -> (reset) -> Prep.
--
-- Prep: everyone is human; the banner counts down "Outbreak happening in N
-- seconds"; humans shop and barricade. Outbreak: first zombies are picked,
-- weighted by immunity. Infection: a zombie touching a human converts them.
-- Zombies win when no humans remain; survivors win if anyone lasts the timer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Announcer = require(script.Parent.Announcer)
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
	local list = if team == "Zombie" then MapLayout.zombieSpawns else MapLayout.humanSpawns
	local spot = list[rng:NextInteger(1, #list)]
	local jitter = if team == "Zombie" then 3 else 5
	local x = spot.x + rng:NextNumber(-jitter, jitter)
	local z = spot.z + rng:NextNumber(-jitter, jitter)
	local y = MapLayout.HEIGHTS.Floor
		+ (Config.CHARACTER.HipHeight + Config.CHARACTER.RootHeight / 2) * scale
		+ 0.3
	return CFrame.new(x, y, z)
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

-- Teams --------------------------------------------------------------------------------

function RoundManager.setTeam(p: Participant, team: Participants.Team)
	if p.team == team then
		return
	end
	p.team = team
	p.state:SetAttribute("Team", team)
	if team == "Zombie" then
		ItemService.onInfected(p)
	end
	CharacterService.applyLook(p)
	CharacterService.refreshSpeed(p)
	ItemService.refreshHand(p)
	recount()
end

local function bonusesFor(p: Participant, includeDrumstick: boolean): RoundRules.RewardBonuses
	local held = Items.get(p.heldItem)
	return {
		drumstick = if includeDrumstick and held and held.kind == "Passive" then held.rewardBonus else nil,
		vip = p.passes.VIP == true,
		doubleScore = p.passes.DoubleScore == true,
		boosted = os.time() < p.boostEndsAt,
	}
end

local function award(p: Participant, base: number, includeDrumstick: boolean, reason: string)
	local amount = RoundRules.reward(base, bonusesFor(p, includeDrumstick))
	Participants.addScore(p, amount)
	CharacterService.refreshSpeed(p)
	if p.player then
		Announcer.toast(
			p.player,
			string.format("+%s score  %s", Util.commas(amount), reason),
			Config.COLORS.Good
		)
	end
end

local function infect(zombie: Participant, human: Participant)
	local root = Participants.body(human)
	RoundManager.setTeam(human, "Zombie")
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

-- Every frame of the infection phase: any zombie close enough to a human,
-- with no wall between them, converts that human.
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
					local reach = RoundRules.infectDistance(zombie.scale, human.scale)
					if
						Util.flatDistance(zRoot.Position, hRoot.Position) < reach
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
	if p.heldItem then
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
	if p.passes.StarterKit then
		ItemService.give(p, "Bat")
	end
end

-- Everyone back to human at a yard spawn, furniture and walls restored.
local function resetWorld()
	Wizard.leave()
	Projectiles.clear()
	ItemService.clearGround()
	FurnitureService.resetAll()
	MapBuilder.restoreWalls()
	for _, p in Participants.all() do
		p.team = "Human"
		p.stunUntil = 0
		p.dragging = false
		p.scale = RoundRules.scaleForWins(p.sessionWins)
		p.state:SetAttribute("Team", "Human")
		p.state:SetAttribute("Scale", p.scale)
		CharacterService.place(p, spawnFrame("Human", p.scale))
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
local function waitPhase(): boolean
	while secondsLeft() > 0 do
		if not enoughPlayers() then
			return false
		end
		task.wait(0.2)
	end
	return true
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
			p.sessionWins += 1
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
	while true do
		task.wait(0.1)
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

local function runRound()
	waitForPlayers()

	resetWorld()
	local round = state:GetAttribute("Round")
	state:SetAttribute("Round", (if typeof(round) == "number" then round else 0) + 1)
	ItemService.scatter()
	setPhase("Prep", Config.PREP_SECONDS)
	Wizard.schedule()
	Announcer.chat("Outbreak in " .. Config.PREP_SECONDS .. " seconds. Barricade a room and grab items!")
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
	-- Late joiners become zombies once the outbreak has happened.
	if phase == "Infection" then
		p.team = "Zombie"
		p.state:SetAttribute("Team", "Zombie")
	end
	CharacterService.spawn(p, spawnFrame(p.team, p.scale))
	if p.team == "Human" then
		grantRoundStartItems(p)
	end
	ItemService.refreshHand(p)
	recount()
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
	CharacterService.place(p, spawnFrame("Zombie", p.scale))
end

-- Lets bots press Z too.
function RoundManager.zombieReturn(p: Participant)
	if p.team == "Zombie" and phase == "Infection" and os.clock() >= p.returnReadyAt then
		p.returnReadyAt = os.clock() + Config.ZOMBIE_RETURN_COOLDOWN
		CharacterService.place(p, spawnFrame("Zombie", p.scale))
	end
end

function RoundManager.start()
	state = ReplicatedStorage:WaitForChild("BrainTagState") :: Folder

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
