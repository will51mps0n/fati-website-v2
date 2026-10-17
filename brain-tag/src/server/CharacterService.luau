-- Spawns and dresses characters. Every player and bot uses the same custom
-- rig: an invisible collision box (HumanoidRootPart) with a Humanoid, wearing
-- the flat blob look from CharacterLook. Avatars, clothes and accessories are
-- never loaded.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local CharacterLook = require(ReplicatedStorage.Shared.CharacterLook)
local Config = require(ReplicatedStorage.Shared.Config)
local Parts = require(ReplicatedStorage.Shared.Parts)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local Participants = require(script.Parent.Participants)

local C = Config.CHARACTER

local CharacterService = {}

type Participant = Participants.Participant

-- Called when a character died or vanished and needs a new one. RoundManager
-- sets this so it can choose the right spawn for the current phase.
CharacterService.onNeedRespawn = function(_p: Participant) end

local template: Model

function CharacterService.buildTemplate()
	local existing = StarterPlayer:FindFirstChild("StarterCharacter")
	if existing then
		existing:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "StarterCharacter"

	local root = Parts.make({
		name = "HumanoidRootPart",
		size = Vector3.new(C.RootWidth, C.RootHeight, C.RootWidth),
		cframe = CFrame.new(0, 5, 0),
		color = "FFFFFF",
		transparency = 1,
		anchored = false,
		parent = model,
	})
	root.CanQuery = true -- the hitbox for potatoes and line-of-sight checks
	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = C.HipHeight
	humanoid.WalkSpeed = Config.BASE_WALKSPEED
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model

	CharacterLook.apply(model, root, nil, "Human", 1)
	model.Parent = StarterPlayer
	template = model
end

local function nameColor(p: Participant): Color3
	if p.passes.VIP then
		return Color3.fromHex(Config.COLORS.VipName)
	end
	return Color3.fromHex(Config.COLORS.OtherName)
end

local function updateNameTag(p: Participant)
	local character = p.character
	if not character then
		return
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local tag = head:FindFirstChild("NameTag") :: BillboardGui?
	if not tag then
		local gui = Instance.new("BillboardGui")
		gui.Name = "NameTag"
		gui.Size = UDim2.fromOffset(220, 24)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 1000
		gui.ResetOnSpawn = false
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.BuilderSansBold
		label.TextSize = 16
		label.TextStrokeTransparency = 0.35
		label.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
		label.Parent = gui
		gui.Parent = head
		tag = gui
	end
	assert(tag, "tag")
	tag.Adornee = head
	-- World offset toward -Z = "up" on the top-down screen.
	tag.StudsOffsetWorldSpace = Vector3.new(0, 1, -(C.BodyWidth * 0.5 + 0.7) * p.scale)
	tag:SetAttribute("ParticipantId", p.id)
	local label = tag:FindFirstChild("Label") :: TextLabel
	label.Text = (if p.passes.VIP then "[VIP] " else "") .. p.name
	label.TextColor3 = nameColor(p)
end

function CharacterService.skinFor(p: Participant): string
	return if p.team == "Zombie" then p.zombieSkin else p.humanSkin
end

-- Rebuilds the look for the participant's team, skin and size.
function CharacterService.applyLook(p: Participant)
	local character = p.character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	root.Size = Vector3.new(C.RootWidth, C.RootHeight, C.RootWidth) * p.scale
	humanoid.HipHeight = C.HipHeight * p.scale
	CharacterLook.apply(character, root, CharacterService.skinFor(p), p.team, p.scale)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Characters"
		end
	end
	character:SetAttribute("Team", p.team)
	updateNameTag(p)
end

function CharacterService.refreshNameTag(p: Participant)
	updateNameTag(p)
end

function CharacterService.refreshSpeed(p: Participant)
	local _, humanoid = Participants.body(p)
	if not humanoid then
		return
	end
	if os.clock() < p.stunUntil then
		humanoid.WalkSpeed = 0
	else
		humanoid.WalkSpeed = RoundRules.walkSpeed(p.score, p.team == "Zombie")
	end
end

local function setup(p: Participant, character: Model)
	p.character = character
	character:SetAttribute("ParticipantId", p.id)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "character has no Humanoid")
	humanoid.AutoRotate = p.isBot -- players face the mouse from their client
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	CharacterService.applyLook(p)
	CharacterService.refreshSpeed(p)
	humanoid.Died:Connect(function()
		task.delay(2, function()
			if Participants.get(p.id) == p and p.character == character then
				CharacterService.onNeedRespawn(p)
			end
		end)
	end)
end

local function spawnBot(p: Participant, at: CFrame): Model
	local character = template:Clone()
	character.Name = p.name
	character:PivotTo(at)
	character.Parent = workspace:WaitForChild("Bots")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	setup(p, character)
	return character
end

local function spawnPlayer(p: Participant, at: CFrame): Model?
	local player = p.player
	if not player or player.Parent ~= Players then
		return nil
	end
	player:LoadCharacter()
	local character = player.Character
	if not character or Participants.get(p.id) ~= p then
		return nil
	end
	setup(p, character)
	character:PivotTo(at)
	return character
end

-- Gives the participant a fresh character standing at `at`.
function CharacterService.spawn(p: Participant, at: CFrame): Model?
	if p.spawning then
		return nil -- a spawn is already in progress (LoadCharacter yields)
	end
	p.spawning = true
	local ok, result = pcall(function(): Model?
		if p.isBot then
			if p.character then
				p.character:Destroy()
			end
			return spawnBot(p, at)
		end
		return spawnPlayer(p, at)
	end)
	p.spawning = false
	if not ok then
		warn("[Characters] spawn failed for " .. p.name .. ": " .. tostring(result))
		return nil
	end
	return result
end

-- Moves an existing living character, or spawns one if there is none.
function CharacterService.place(p: Participant, at: CFrame)
	if p.spawning then
		return
	end
	local root = Participants.body(p)
	if not root or not p.character then
		CharacterService.spawn(p, at)
		return
	end
	p.character:PivotTo(at)
	root.AssemblyLinearVelocity = Vector3.zero
end

function CharacterService.init()
	Players.PlayerAdded:Connect(function(player)
		player.CanLoadCharacterAppearance = false
	end)
	for _, player in Players:GetPlayers() do
		player.CanLoadCharacterAppearance = false
	end
end

return CharacterService
