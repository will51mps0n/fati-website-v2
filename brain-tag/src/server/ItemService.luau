-- Held items and items lying on the ground. Each human holds at most one
-- item (shown in their right hand). E picks up the nearest ground item, G
-- drops, left click uses. Becoming a zombie drops whatever you held.
-- Every use is validated and resolved here on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Announcer = require(script.Parent.Announcer)
local CharacterService = require(script.Parent.CharacterService)
local CharacterLook = require(ReplicatedStorage.Shared.CharacterLook)
local Combat = require(script.Parent.Combat)
local Config = require(ReplicatedStorage.Shared.Config)
local FurnitureService = require(script.Parent.FurnitureService)
local ItemModels = require(ReplicatedStorage.Shared.ItemModels)
local Items = require(ReplicatedStorage.Shared.Items)
local MapBuilder = require(script.Parent.MapBuilder)
local MapLayout = require(ReplicatedStorage.Shared.MapLayout)
local Parts = require(ReplicatedStorage.Shared.Parts)
local Participants = require(script.Parent.Participants)
local Projectiles = require(script.Parent.Projectiles)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Traps = require(script.Parent.Traps)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local Util = require(ReplicatedStorage.Shared.Util)

type Participant = Participants.Participant

local ItemService = {}

local groundFolder: Folder
local rng = Random.new()

-- Hand models -------------------------------------------------------------------

local function attachHeld(p: Participant)
	local character = p.character
	if not character then
		return
	end
	local old = character:FindFirstChild("HeldItem")
	if old then
		old:Destroy()
	end
	if not p.heldItem or p.team ~= "Human" then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local model = ItemModels.build(p.heldItem)
	model.Name = "HeldItem"
	local handle = model.PrimaryPart :: BasePart
	local s = p.scale
	local grip = CharacterLook.grip(s)
	model:PivotTo(root.CFrame * grip)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			Parts.makeVisual(part)
		end
	end
	local weld = Instance.new("Weld")
	weld.Name = "GripWeld"
	weld.Part0 = root
	weld.Part1 = handle
	weld.C0 = grip
	weld.Parent = handle
	model.Parent = character
end

function ItemService.refreshHand(p: Participant)
	attachHeld(p)
end

local function setStreaming(p: Participant, itemId: string?)
	p.streaming = itemId ~= nil
	if p.character then
		p.character:SetAttribute("Spraying", itemId) -- clients draw the spray
	end
end

local function setHeld(p: Participant, itemId: string?, charges: number?)
	p.heldItem = itemId
	local item = Items.get(itemId)
	p.heldCharges = charges or (item and item.charges)
	setStreaming(p, nil)
	p.state:SetAttribute("HeldItem", itemId or "")
	p.state:SetAttribute("HeldCharges", p.heldCharges or 0)
	attachHeld(p)
end

-- Ground items -----------------------------------------------------------------------

function ItemService.spawnGround(itemId: string, position: Vector3, charges: number?): Model
	local model = ItemModels.build(itemId)
	model.Name = itemId
	-- Built at the origin, so the bounding box center is the offset to undo.
	local center = model:GetBoundingBox().Position
	local y = MapLayout.HEIGHTS.Floor + 0.55
	local spin = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	model:PivotTo(CFrame.new(position.X, y, position.Z) * spin * CFrame.new(-center.X, 0, -center.Z))
	local ring = Parts.disc(
		"Ring",
		Vector3.new(position.X, MapLayout.HEIGHTS.Floor + 0.05, position.Z),
		4,
		0.06,
		"FFFFFF",
		model
	)
	ring.Transparency = 0.55
	ring.CanCollide = false
	ring.CanQuery = false
	model:SetAttribute("ItemId", itemId)
	model:SetAttribute("Charges", charges)
	model:SetAttribute("SpotX", position.X)
	model:SetAttribute("SpotZ", position.Z)
	model.Parent = groundFolder
	return model
end

local function groundSpot(model: Model): Vector3
	return Vector3.new(model:GetAttribute("SpotX") :: number, 0, model:GetAttribute("SpotZ") :: number)
end

function ItemService.clearGround()
	groundFolder:ClearAllChildren()
end

function ItemService.scatter()
	local count = rng:NextInteger(Config.GROUND_ITEMS_MIN, Config.GROUND_ITEMS_MAX)
	local spots = table.clone(MapLayout.current().itemSpots)
	local pool = Items.groundTable()
	local total = 0
	for _, entry in pool do
		total += entry.weight
	end
	for _ = 1, math.min(count, #spots) do
		local spot = table.remove(spots, rng:NextInteger(1, #spots)) :: MapLayout.Point
		local roll = rng:NextNumber() * total
		local chosen = pool[#pool].id
		for _, entry in pool do
			roll -= entry.weight
			if roll < 0 then
				chosen = entry.id
				break
			end
		end
		ItemService.spawnGround(chosen, Vector3.new(spot.x, 0, spot.z))
	end
end

-- Holding ----------------------------------------------------------------------------

-- Puts an item in the participant's hand, dropping what they held before.
function ItemService.give(p: Participant, itemId: string, charges: number?)
	if p.heldItem then
		ItemService.drop(p)
	end
	setHeld(p, itemId, charges)
end

function ItemService.drop(p: Participant)
	local itemId = p.heldItem
	if not itemId then
		return
	end
	local root = Participants.body(p)
	if root then
		local spot = root.Position + p.aim * (root.Size.X / 2 + 2)
		ItemService.spawnGround(itemId, spot, p.heldCharges)
	end
	setHeld(p, nil)
end

function ItemService.take(p: Participant)
	setHeld(p, nil)
end

function ItemService.pickUp(p: Participant)
	if p.team ~= "Human" then
		return
	end
	local root = Participants.body(p)
	if not root then
		return
	end
	local best: Model? = nil
	local bestDistance = Config.PICKUP_RADIUS * math.max(1, p.scale)
	for _, model in groundFolder:GetChildren() do
		if model:IsA("Model") then
			local d = Util.flatDistance(groundSpot(model), root.Position)
			if d <= bestDistance then
				best, bestDistance = model, d
			end
		end
	end
	if not best then
		return
	end
	local itemId = best:GetAttribute("ItemId") :: string
	local charges = best:GetAttribute("Charges")
	best:Destroy()
	ItemService.give(p, itemId, if typeof(charges) == "number" then charges else nil)
	Announcer.fx("Pickup", { position = root.Position })
end

function ItemService.onInfected(p: Participant)
	if p.heldItem then
		ItemService.drop(p)
	end
end

-- Using ----------------------------------------------------------------------------

local function breakWallAhead(p: Participant, aim: Vector3, reach: number): boolean
	local root = Participants.body(p)
	if not root then
		return false
	end
	for _, angle in { 0, 0.18, -0.18 } do
		local direction = (CFrame.Angles(0, angle, 0) * aim) * reach
		local result = workspace:Raycast(root.Position, direction, Combat.wallParams())
		if result then
			local segment = MapBuilder.segmentOf(result.Instance)
			if segment and MapBuilder.breakSegment(segment) then
				local wall = segment.PrimaryPart
				if wall then
					Announcer.fx("WallBreak", { cframe = wall.CFrame, size = wall.Size })
				end
				return true
			end
		end
	end
	return false
end

local function use(p: Participant, item: Items.Item, aim: Vector3)
	local root = Participants.body(p)
	if not root then
		return
	end
	local kind = item.kind
	if kind == "Melee" or kind == "Blast" then
		local reach = (item.reach or 5) * math.max(1, p.scale * 0.9)
		for _, hit in Combat.zombiesInCone(p, aim, reach, item.arc or 90) do
			local direction = if item.straight then aim else hit.direction
			Combat.knockback(hit.target, direction * (item.knockback or 50), item.stun or 0.3)
			local zRoot = Participants.body(hit.target)
			if zRoot and item.fx then
				Announcer.fx("Hit", { position = zRoot.Position, fx = item.fx })
			end
			if item.effect == "Plunge" then
				Announcer.fx(
					"Plunged",
					{ character = hit.target.character, seconds = item.effectSeconds or 1.5 }
				)
			end
		end
		if kind == "Blast" then
			Announcer.fx("Blast", { origin = root.Position, direction = aim, reach = reach, item = item.id })
			if item.breaksWalls then
				breakWallAhead(p, aim, reach)
			end
			-- The blast also throws furniture around (heavier pieces less).
			local center = root.Position + aim * (reach / 2)
			for _, body in
				FurnitureService.findInBox(
					CFrame.lookAt(center, center + aim),
					Vector3.new(reach * 0.9, 4, reach)
				)
			do
				local away = Util.flatUnit(body.Position - root.Position) or aim
				local mass = (Config.FURNITURE_MASS :: { [string]: number })[FurnitureService.weightOf(body) or "Medium"]
					or 0.45
				FurnitureService.shove(body, away * 28 * math.clamp(1 - mass / 1.6, 0.15, 1), 0.35)
			end
		else
			Announcer.fx("Swing", { character = p.character, item = item.id })
		end
	elseif kind == "Projectile" then
		Projectiles.fire(p, item, aim)
		Announcer.fx("Shoot", { character = p.character, item = item.id })
	elseif kind == "Trap" then
		Traps.place(root.Position - aim * (root.Size.X / 2 + 0.6), item)
		Announcer.fx("Drop", { position = root.Position })
		p.heldCharges = (p.heldCharges or 1) - 1
		p.state:SetAttribute("HeldCharges", p.heldCharges)
		if p.heldCharges <= 0 then
			ItemService.take(p)
		end
	elseif kind == "Consumable" and item.speedBoost then
		CharacterService.speedEffect(p, item.speedBoost, item.boostSeconds or 8)
		ItemService.take(p)
		Announcer.fx("Gulp", { position = root.Position, character = p.character })
		if p.player then
			Announcer.toast(
				p.player,
				"Zoom! Faster for " .. (item.boostSeconds or 8) .. " seconds",
				Config.COLORS.Good
			)
		end
	elseif kind == "Consumable" then
		local before = p.immunity
		Participants.setImmunity(p, p.immunity + (item.immunity or 0))
		ItemService.take(p)
		Announcer.fx("Eat", { position = root.Position })
		if p.player then
			Announcer.toast(
				p.player,
				string.format("Immunity %d -> %d / %d", before, p.immunity, Config.IMMUNITY_MAX),
				Config.COLORS.Good
			)
		end
	elseif kind == "Passive" then
		if p.player then
			Announcer.toast(
				p.player,
				string.format("Hold this when the round ends: +%d%% score", (item.rewardBonus or 0) * 100)
			)
		end
	end
end

local function onUse(player: Player, action: unknown, aim: unknown)
	local p = Participants.fromPlayer(player)
	if not p or typeof(aim) ~= "Vector3" then
		return
	end
	local direction = Util.flatUnit(aim :: Vector3)
	if not direction then
		return
	end
	p.aim = direction
	if action == "stop" then
		setStreaming(p, nil)
		return
	end
	if action ~= "start" or p.team ~= "Human" then
		return
	end
	local item = Items.get(p.heldItem)
	if not item then
		return
	end
	if item.kind == "Stream" then
		setStreaming(p, item.id) -- sprays until "stop" (see streamStep)
		return
	end
	local now = os.clock()
	if now < p.itemReadyAt then
		return
	end
	p.itemReadyAt = now + (item.cooldown or 0.5)
	use(p, item, direction)
end

-- Bots use their held item with the same rules and cooldowns as players
-- (they never hook furniture; streams spray for a moment).
function ItemService.botUse(p: Participant, aim: Vector3)
	local direction = Util.flatUnit(aim)
	local item = Items.get(p.heldItem)
	if not direction or not item or p.team ~= "Human" then
		return
	end
	p.aim = direction
	if item.kind == "Stream" then
		setStreaming(p, item.id)
		task.delay(0.6, function()
			if p.heldItem == item.id then
				setStreaming(p, nil)
			end
		end)
		return
	end
	local now = os.clock()
	if now < p.itemReadyAt then
		return
	end
	p.itemReadyAt = now + (item.cooldown or 0.5)
	use(p, item, direction)
end

-- Held melee weapons are solid to zombies too: a zombie touching the shaft
-- (within the item's `guard`) is shoved off it in short pulses, so a stick
-- held across a doorway keeps zombies out. Firm weapons (bat, pan) hold
-- them completely; soft ones (pool noodle) give, so zombies squeeze past.
-- A bigger holder holds harder, a bigger zombie pushes through easier.
local SHAFT_INTERVAL = 1 / 15
local nextShaftStep = 0

local function shaftStep()
	local now = os.clock()
	if now < nextShaftStep then
		return
	end
	nextShaftStep = now + SHAFT_INTERVAL
	local zombies = Participants.onTeam("Zombie")
	if #zombies == 0 then
		return
	end
	for _, p in Participants.onTeam("Human") do
		local item = Items.get(p.heldItem)
		local root = Participants.body(p)
		if not item or item.kind ~= "Melee" or not root then
			continue
		end
		local reach = (item.reach or 5) * math.max(1, p.scale * 0.9)
		local guard = item.guard or 0.5
		local hand = (root.CFrame * CharacterLook.grip(p.scale)).Position
		local start = Vector3.new(hand.X, 0, hand.Z)
		for _, zombie in zombies do
			local zRoot = Participants.body(zombie)
			if zRoot then
				local z = Vector3.new(zRoot.Position.X, 0, zRoot.Position.Z)
				local along = math.clamp((z - start):Dot(p.aim), 0, reach)
				local offset = z - (start + p.aim * along)
				local radius = Config.CHARACTER.ShellDiameter / 2 * zombie.scale
				if
					offset.Magnitude < radius + guard and Combat.lineOfSight(root.Position, zRoot.Position)
				then
					local firmness = (item.firmness or 1) * math.clamp(p.scale / zombie.scale, 0.5, 2)
					local away = Util.flatUnit(offset) or p.aim
					-- Each pulse covers part of the tick: soft weapons leave long gaps
					-- the zombie walks through, firm ones short gaps to steer around.
					local seconds = SHAFT_INTERVAL * Config.SHAFT_PULSE_SHARE * math.min(1, firmness)
					local speed = Config.SHAFT_ZOMBIE_PUSH * math.min(firmness, 1.5)
					Combat.knockback(zombie, away * speed, 0, seconds, true)
				end
			end
		end
	end
end

-- Water gun and leaf blower: while held, push every zombie in the cone a
-- little, many times a second. The leaf blower also blows light furniture.
local function streamStep()
	local now = os.clock()
	for _, p in Participants.onTeam("Human") do
		if not p.streaming then
			continue
		end
		local item = Items.get(p.heldItem)
		local root = Participants.body(p)
		if not item or item.kind ~= "Stream" or not root then
			setStreaming(p, nil)
			continue
		end
		if now < p.nextStreamTick then
			continue
		end
		p.nextStreamTick = now + (item.tick or 0.12)
		if item.charges then
			p.heldCharges = (p.heldCharges or 1) - 1
			p.state:SetAttribute("HeldCharges", p.heldCharges)
			if p.heldCharges <= 0 then
				ItemService.take(p) -- out of water
			end
		end
		local reach = (item.reach or 14) * math.max(1, p.scale * 0.9)
		for _, hit in Combat.zombiesInCone(p, p.aim, reach, item.arc or 30) do
			local falloff = 1 - hit.distance / (reach * 1.5)
			Combat.knockback(hit.target, p.aim * (item.knockback or 15) * falloff, item.stun or 0.1)
		end
		if item.fx == "Leaves" then
			local center = root.Position + p.aim * (reach / 2)
			local box = CFrame.lookAt(center, center + p.aim)
			for _, body in FurnitureService.findInBox(box, Vector3.new(reach * 0.6, 4, reach)) do
				local weight = FurnitureService.weightOf(body)
				if weight == "Light" or weight == "Medium" then
					FurnitureService.shove(body, p.aim * (if weight == "Light" then 12 else 6), 0.18)
				end
			end
		end
	end
end

function ItemService.init()
	groundFolder = workspace:WaitForChild("GroundItems") :: Folder
	CharacterService.onResized = attachHeld -- the grip moves with your size

	Remotes.event("UseItem").OnServerEvent:Connect(onUse)
	Remotes.unreliable("Aim").OnServerEvent:Connect(function(player, aim)
		local p = Participants.fromPlayer(player)
		local direction = if p and typeof(aim) == "Vector3" then Util.flatUnit(aim) else nil
		if p and direction then
			p.aim = direction
		end
	end)

	local lastAction: { [Player]: number } = {}
	local function throttled(player: Player): boolean
		local now = os.clock()
		if lastAction[player] and now - lastAction[player] < 0.2 then
			return true
		end
		lastAction[player] = now
		return false
	end

	Remotes.event("PickUp").OnServerEvent:Connect(function(player)
		local p = Participants.fromPlayer(player)
		if p and not throttled(player) then
			ItemService.pickUp(p)
		end
	end)
	Remotes.event("DropItem").OnServerEvent:Connect(function(player)
		local p = Participants.fromPlayer(player)
		if p and p.team == "Human" and not throttled(player) then
			ItemService.drop(p)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)

	RunService.Heartbeat:Connect(shaftStep)
	RunService.Heartbeat:Connect(streamStep)
end

return ItemService
