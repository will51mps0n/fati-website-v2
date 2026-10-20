-- Everyone taking part in rounds: real players and Studio test bots, behind
-- one interface. Each participant is mirrored into a Configuration under
-- ReplicatedStorage.BrainTagState.Participants so every client's HUD can read
-- teams, scores and held items.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Skins = require(ReplicatedStorage.Shared.Skins)

export type Team = "Human" | "Zombie"

export type Slot = { id: string, charges: number? }

export type Participant = {
	id: string,
	name: string,
	player: Player?,
	isBot: boolean,
	character: Model?,
	team: Team,
	score: number,
	immunity: number,
	scale: number,
	heldItem: string?, -- the item in the active slot (in your hand)
	slots: { [number]: Slot }, -- inventory: slot number -> item (missing = empty)
	slot: number, -- active slot
	humanSkin: string,
	zombieSkin: string,
	ownedSkins: { [string]: boolean },
	passes: { [string]: boolean },
	boostEndsAt: number,
	-- runtime only
	itemReadyAt: number,
	returnReadyAt: number,
	stunUntil: number,
	streaming: boolean, -- holding the button with a water gun / leaf blower
	nextStreamTick: number,
	heldCharges: number?, -- uses left (banana peels)
	boostUntil: number, -- energy drink
	boostFactor: number,
	slowUntil: number, -- snowball freeze
	adminSpeed: number, -- speed multiplier set from the admin panel (1 = normal)
	alpha: boolean, -- one of this round's first zombies (special look)
	turning: boolean, -- picked to be a first zombie: red name, slowed, until the outbreak
	knockedUntil: number, -- a real hit's shove lasts until then (see Combat.knockback)
	pressedUntil: number, -- bots: being held off someone's weapon (ItemService.shaftStep)
	slowFactor: number,
	spawning: boolean,
	aim: Vector3,
	profile: any?, -- saved data table for players (DataService)
	state: Configuration,
}

local Participants = {}

local byId: { [string]: Participant } = {}
local order: { Participant } = {}
-- Plain callback lists, not BindableEvents: a BindableEvent hands listeners a
-- COPY of any table it carries, and every service must share the same
-- participant table.
local addedCallbacks: { (Participant) -> () } = {}
local removingCallbacks: { (Participant) -> () } = {}

-- Runs `callback(p)` in its own thread for every participant added from now on.
function Participants.onAdded(callback: (Participant) -> ())
	table.insert(addedCallbacks, callback)
end

-- Runs `callback(p)` just before a participant is removed.
function Participants.onRemoving(callback: (Participant) -> ())
	table.insert(removingCallbacks, callback)
end

local function stateFolder(): Folder
	return ReplicatedStorage:WaitForChild("BrainTagState"):WaitForChild("Participants") :: Folder
end

local function csv(set: { [string]: boolean }): string
	local list = {}
	for key, on in set do
		if on then
			table.insert(list, key)
		end
	end
	table.sort(list)
	return table.concat(list, ",")
end

-- Writes every replicated field. Cheap enough to call after any change.
function Participants.publish(p: Participant)
	local s = p.state
	s:SetAttribute("DisplayName", p.name)
	s:SetAttribute("UserId", if p.player then p.player.UserId else 0)
	s:SetAttribute("IsBot", p.isBot)
	s:SetAttribute("Team", p.team)
	s:SetAttribute("Score", math.floor(p.score))
	s:SetAttribute("Immunity", p.immunity)
	s:SetAttribute("Scale", p.scale)
	s:SetAttribute("HeldItem", p.heldItem or "")
	s:SetAttribute("HeldCharges", p.heldCharges or 0)
	s:SetAttribute("HumanSkin", p.humanSkin)
	s:SetAttribute("ZombieSkin", p.zombieSkin)
	s:SetAttribute("OwnedSkins", csv(p.ownedSkins))
	s:SetAttribute("Passes", csv(p.passes))
	s:SetAttribute("VIP", p.passes.VIP == true)
	s:SetAttribute("BoostEndsAt", p.boostEndsAt)
	if p.profile then
		s:SetAttribute("Wins", p.profile.Wins or 0)
		s:SetAttribute("Infections", p.profile.Infections or 0)
		s:SetAttribute("RoundsPlayed", p.profile.RoundsPlayed or 0)
		s:SetAttribute("BestScore", p.profile.BestScore or 0)
		s:SetAttribute("SeenTutorial", p.profile.SeenTutorial == true)
	end
end

export type NewParticipant = {
	id: string,
	name: string,
	player: Player?,
	isBot: boolean,
	profile: any?,
	passes: { [string]: boolean }?,
}

function Participants.add(info: NewParticipant): Participant
	local state = Instance.new("Configuration")
	state.Name = info.id
	local profile = info.profile
	local owned = {}
	if profile and profile.OwnedSkins then
		for id, on in profile.OwnedSkins do
			owned[id] = on == true
		end
	end
	owned[Skins.DEFAULT_HUMAN] = true
	owned[Skins.DEFAULT_ZOMBIE] = true

	local p: Participant = {
		id = info.id,
		name = info.name,
		player = info.player,
		isBot = info.isBot,
		character = nil,
		team = "Human",
		-- Saved points, minus a little for having left.
		score = if profile then math.floor((profile.Score or 0) * Config.REJOIN_KEEP) else 0,
		immunity = 0,
		scale = 1,
		heldItem = nil,
		slots = {},
		slot = 1,
		humanSkin = if profile then profile.HumanSkin or Skins.DEFAULT_HUMAN else Skins.DEFAULT_HUMAN,
		zombieSkin = if profile then profile.ZombieSkin or Skins.DEFAULT_ZOMBIE else Skins.DEFAULT_ZOMBIE,
		ownedSkins = owned,
		passes = info.passes or {},
		boostEndsAt = if profile then profile.BoostEndsAt or 0 else 0,
		itemReadyAt = 0,
		returnReadyAt = 0,
		stunUntil = 0,
		streaming = false,
		nextStreamTick = 0,
		heldCharges = nil,
		boostUntil = 0,
		boostFactor = 1,
		slowUntil = 0,
		adminSpeed = 1,
		alpha = false,
		turning = false,
		knockedUntil = 0,
		pressedUntil = 0,
		slowFactor = 1,
		spawning = false,
		aim = Vector3.new(0, 0, -1),
		profile = profile,
		state = state,
	}
	byId[p.id] = p
	table.insert(order, p)
	Participants.publish(p)
	state.Parent = stateFolder()
	for _, callback in addedCallbacks do
		task.spawn(callback, p)
	end
	return p
end

function Participants.remove(p: Participant)
	if byId[p.id] ~= p then
		return
	end
	for _, callback in removingCallbacks do
		task.spawn(callback, p)
	end
	byId[p.id] = nil
	local index = table.find(order, p)
	if index then
		table.remove(order, index)
	end
	p.state:Destroy()
end

function Participants.get(id: string): Participant?
	return byId[id]
end

function Participants.playerId(player: Player): string
	return "P" .. player.UserId
end

function Participants.fromPlayer(player: Player): Participant?
	return byId[Participants.playerId(player)]
end

function Participants.fromCharacter(model: Instance?): Participant?
	if not model then
		return nil
	end
	local id = model:GetAttribute("ParticipantId")
	if typeof(id) == "string" then
		return byId[id]
	end
	return nil
end

-- Finds the participant whose character contains `part`.
function Participants.fromPart(part: Instance): Participant?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local p = Participants.fromCharacter(model)
		if p then
			return p
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function Participants.all(): { Participant }
	return table.clone(order)
end

function Participants.count(): number
	return #order
end

function Participants.onTeam(team: Team): { Participant }
	local list = {}
	for _, p in order do
		if p.team == team then
			table.insert(list, p)
		end
	end
	return list
end

-- Root and humanoid of a participant whose character is alive, else nil.
function Participants.body(p: Participant): (BasePart?, Humanoid?)
	local character = p.character
	if not character or character.Parent == nil then
		return nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

function Participants.setScore(p: Participant, value: number)
	p.score = math.max(0, math.floor(value))
	if p.profile then
		p.profile.Score = p.score
		if p.score > p.profile.BestScore then
			p.profile.BestScore = p.score
			p.state:SetAttribute("BestScore", p.score)
		end
	end
	p.state:SetAttribute("Score", p.score)
end

function Participants.addScore(p: Participant, amount: number)
	Participants.setScore(p, p.score + amount)
end

function Participants.setImmunity(p: Participant, value: number)
	p.immunity = math.clamp(value, 0, 100)
	p.state:SetAttribute("Immunity", p.immunity)
end

return Participants
