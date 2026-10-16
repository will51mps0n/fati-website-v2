-- Everyone taking part in rounds: real players and Studio test bots, behind
-- one interface. Each participant is mirrored into a Configuration under
-- ReplicatedStorage.BrainTagState.Participants so every client's HUD can read
-- teams, scores and held items.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skins = require(ReplicatedStorage.Shared.Skins)

export type Team = "Human" | "Zombie"

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
	sessionWins: number,
	heldItem: string?,
	humanSkin: string,
	zombieSkin: string,
	ownedSkins: { [string]: boolean },
	passes: { [string]: boolean },
	boostEndsAt: number,
	-- runtime only
	itemReadyAt: number,
	returnReadyAt: number,
	stunUntil: number,
	dragging: boolean,
	spawning: boolean,
	aim: Vector3,
	profile: any?, -- saved data table for players (DataService)
	state: Configuration,
}

local Participants = {}

local byId: { [string]: Participant } = {}
local order: { Participant } = {}
local added = Instance.new("BindableEvent")
local removing = Instance.new("BindableEvent")
Participants.Added = added.Event
Participants.Removing = removing.Event

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
		score = if profile then profile.Score or 0 else 0,
		immunity = 0,
		scale = 1,
		sessionWins = 0,
		heldItem = nil,
		humanSkin = if profile then profile.HumanSkin or Skins.DEFAULT_HUMAN else Skins.DEFAULT_HUMAN,
		zombieSkin = if profile then profile.ZombieSkin or Skins.DEFAULT_ZOMBIE else Skins.DEFAULT_ZOMBIE,
		ownedSkins = owned,
		passes = info.passes or {},
		boostEndsAt = if profile then profile.BoostEndsAt or 0 else 0,
		itemReadyAt = 0,
		returnReadyAt = 0,
		stunUntil = 0,
		dragging = false,
		spawning = false,
		aim = Vector3.new(0, 0, -1),
		profile = profile,
		state = state,
	}
	byId[p.id] = p
	table.insert(order, p)
	Participants.publish(p)
	state.Parent = stateFolder()
	added:Fire(p)
	return p
end

function Participants.remove(p: Participant)
	if byId[p.id] ~= p then
		return
	end
	removing:Fire(p)
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
