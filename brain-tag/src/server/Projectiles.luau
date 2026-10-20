-- Everything that flies: potatoes, pebbles, snowballs, bubbles and rubber
-- ducks. Simulated on the server with sphere casts so hits are decided in
-- one place. Shots pass through bushes and stop at the first person (zombie
-- or human, never the shooter), wall or piece of furniture, then apply their
-- effect (shove, freeze, bubble trap or explosion).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Announcer = require(script.Parent.Announcer)
local CharacterService = require(script.Parent.CharacterService)
local Combat = require(script.Parent.Combat)
local FurnitureService = require(script.Parent.FurnitureService)
local Items = require(ReplicatedStorage.Shared.Items)
local Parts = require(ReplicatedStorage.Shared.Parts)
local Participants = require(script.Parent.Participants)
local Util = require(ReplicatedStorage.Shared.Util)

type Participant = Participants.Participant

local Projectiles = {}

type Shot = {
	model: Model,
	position: Vector3,
	direction: Vector3,
	traveled: number,
	item: Items.Item,
	params: RaycastParams,
	ignored: { Instance },
}

local shots: { Shot } = {}
local folder: Folder

local function ball(model: Model, diameter: number, offset: Vector3, color: string, transparency: number?)
	local part = Parts.make({
		name = "Ball",
		shape = Enum.PartType.Ball,
		size = Vector3.one * diameter,
		cframe = CFrame.new(offset),
		color = color,
		transparency = transparency,
		canCollide = false,
		canQuery = false,
		parent = model,
	})
	if not model.PrimaryPart then
		model.PrimaryPart = part
	end
end

-- The flying object, built at the origin facing -Z.
local function buildLook(item: Items.Item): Model
	local model = Instance.new("Model")
	model.Name = item.projectile or "Potato"
	local d = (item.projectileRadius or 0.6) * 2
	local look = item.projectile
	if look == "Pebble" then
		ball(model, d, Vector3.zero, "8C8C8C")
	elseif look == "Snowball" then
		ball(model, d, Vector3.zero, "FFFFFF")
		ball(model, d * 0.5, Vector3.new(0.2, 0.25, -0.1), "E8F6FF")
	elseif look == "Bubble" then
		ball(model, d, Vector3.zero, "BFE9FF", 0.55)
		ball(model, d * 0.25, Vector3.new(-d * 0.2, d * 0.3, -d * 0.15), "FFFFFF", 0.2) -- shine
	elseif look == "Duck" then
		ball(model, d, Vector3.zero, "FFD93B")
		ball(model, d * 0.6, Vector3.new(0, d * 0.35, -d * 0.35), "FFD93B")
		Parts.make({
			name = "Beak",
			size = Vector3.new(0.35, 0.15, 0.4) * d,
			cframe = CFrame.new(0, d * 0.32, -d * 0.7),
			color = "F28C1C",
			canCollide = false,
			canQuery = false,
			parent = model,
		})
	elseif look == "Ice" then
		ball(model, d, Vector3.zero, "BFF0FF", 0.15)
		local shard = Parts.make({
			name = "Shard",
			size = Vector3.new(0.45, 0.45, 1.2) * d,
			cframe = CFrame.Angles(0, 0, math.rad(45)),
			color = "E8FBFF",
			material = Enum.Material.Neon,
			canCollide = false,
			canQuery = false,
			parent = model,
		})
		shard.Transparency = 0.2
	elseif look == "Bullet" then
		local bullet = Parts.make({
			name = "Bullet",
			size = Vector3.new(0.5, 0.5, 1.4) * d,
			cframe = CFrame.identity,
			color = "D4A84B",
			canCollide = false,
			canQuery = false,
			parent = model,
		})
		model.PrimaryPart = bullet
	elseif look == "Arrow" then
		local shaft = Parts.make({
			name = "Shaft",
			size = Vector3.new(0.14, 0.14, 2.6),
			cframe = CFrame.identity,
			color = "D9C29A",
			canCollide = false,
			canQuery = false,
			parent = model,
		})
		model.PrimaryPart = shaft
		Parts.make({
			name = "Tip",
			size = Vector3.new(0.35, 0.12, 0.35),
			cframe = CFrame.new(0, 0, -1.35) * CFrame.Angles(0, math.rad(45), 0),
			color = "9AA3AD",
			canCollide = false,
			canQuery = false,
			parent = model,
		})
		Parts.make({
			name = "Fletching",
			size = Vector3.new(0.5, 0.06, 0.5),
			cframe = CFrame.new(0, 0, 1.15),
			color = "8E44AD",
			canCollide = false,
			canQuery = false,
			parent = model,
		})
	elseif look == "Dynamite" then
		local stick = Parts.make({
			name = "Stick",
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(1.8, 0.55, 0.55),
			cframe = CFrame.Angles(0, math.rad(90), 0),
			color = "C0392B",
			canCollide = false,
			canQuery = false,
			parent = model,
		})
		model.PrimaryPart = stick
		Parts.make({
			name = "Spark",
			shape = Enum.PartType.Ball,
			size = Vector3.one * 0.35,
			cframe = CFrame.new(0, 0, 1.15),
			color = "FFC21A",
			material = Enum.Material.Neon,
			canCollide = false,
			canQuery = false,
			parent = model,
		})
	elseif look == "Grenade" then
		ball(model, d, Vector3.zero, "4E6B3A")
		ball(model, d * 0.35, Vector3.new(0, d * 0.45, 0), "5A5A5A")
	else
		ball(model, d, Vector3.zero, if item.isRare then "B98A4E" else "C9A66B")
		ball(model, d * 0.25, Vector3.new(d * 0.2, d * 0.3, 0), "8B6A43")
	end
	return model
end

local function impact(shot: Shot, at: Vector3, target: Participant?, hitPart: Instance)
	local item = shot.item
	local dir = shot.direction
	if item.effect == "Explode" then
		Combat.explode(at, item.radius or 10, item.knockback or 100, item.stun or 0.5)
		for _, body in
			FurnitureService.findInBox(
				CFrame.new(at),
				Vector3.new(1, 0, 1) * (item.radius or 10) * 1.6 + Vector3.yAxis * 6
			)
		do
			local away = Util.flatUnit(body.Position - at) or dir
			FurnitureService.shove(body, away * 18, 0.35)
		end
		Announcer.fx("Boom", { position = at, look = item.projectile, radius = item.radius })
		return
	end
	if target then
		if item.knockback and item.knockback > 0 then
			Combat.knockback(target, dir * item.knockback, item.stun or 0.3)
		else
			Combat.knockback(target, Vector3.zero, item.stun or 0.3)
		end
		if item.effect == "Freeze" then
			CharacterService.speedEffect(target, item.slowFactor or 0.4, item.effectSeconds or 2.5)
			Announcer.fx("Frozen", { character = target.character, seconds = item.effectSeconds or 2.5 })
		elseif item.effect == "Bubble" then
			Announcer.fx("Bubbled", { character = target.character, seconds = item.effectSeconds or 2 })
		end
	elseif hitPart:IsA("BasePart") then
		local weight = FurnitureService.weightOf(hitPart)
		if weight == "Light" or (weight == "Medium" and (item.knockback or 0) >= 80) then
			FurnitureService.shove(hitPart, dir * 12, 0.25)
		end
	end
	Announcer.fx("Splat", { position = at, look = item.projectile })
end

local function finish(shot: Shot)
	shot.model:Destroy()
	local index = table.find(shots, shot)
	if index then
		table.remove(shots, index)
	end
end

local function step(dt: number)
	for i = #shots, 1, -1 do
		local shot = shots[i]
		local item = shot.item
		local distance = (item.projectileSpeed or 90) * dt
		local radius = item.projectileRadius or 0.6
		local done = false
		-- A Spherecast ignores parts already overlapping its starting sphere,
		-- so each cast starts a little behind the shot. Otherwise a zombie
		-- walking into it between frames would be missed.
		local back = radius + 1
		local origin = shot.position - shot.direction * back
		for _ = 1, 4 do
			local result =
				workspace:Spherecast(origin, radius, shot.direction * (distance + back), shot.params)
			if not result then
				break
			end
			local target = Participants.fromPart(result.Instance)
			impact(shot, result.Position, target, result.Instance)
			finish(shot)
			done = true
			break
		end
		if not done then
			shot.position += shot.direction * distance
			shot.traveled += distance
			if shot.traveled >= (item.projectileRange or 100) then
				if item.effect == "Explode" then
					impact(shot, shot.position, nil, workspace) -- ducks go off at the end of their flight
				end
				finish(shot)
			else
				-- Ducks and potatoes tumble a little as they fly; arrows,
				-- bullets and ice bolts fly straight.
				local look = item.projectile
				local straight = look == "Arrow" or look == "Bullet" or look == "Ice"
				local spin = if straight then CFrame.identity else CFrame.Angles(0, shot.traveled * 0.15, 0)
				shot.model:PivotTo(CFrame.lookAt(shot.position, shot.position + shot.direction) * spin)
			end
		end
	end
end

function Projectiles.fire(shooter: Participant, item: Items.Item, aim: Vector3)
	local root = Participants.body(shooter)
	if not root or not shooter.character then
		return
	end
	local radius = item.projectileRadius or 0.6
	local origin = root.Position + aim * (root.Size.X / 2 + radius + 0.4)
	local model = buildLook(item)
	model:PivotTo(CFrame.lookAt(origin, origin + aim))
	model.Parent = folder
	local ignored: { Instance } = {
		shooter.character,
		folder,
		workspace:WaitForChild("GroundItems"),
		workspace:WaitForChild("Traps"),
		workspace:WaitForChild("Effects"),
	}
	local map = workspace:WaitForChild("Map")
	-- Shots stop at the boundary wall, but fly over the ground, under roofs
	-- and through non-solid scenery.
	for _, name in { "Ground", "Road", "Floors", "Roofs", "Custom" } do
		local child = map:FindFirstChild(name)
		if child then
			table.insert(ignored, child)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignored
	table.insert(shots, {
		model = model,
		position = origin,
		direction = aim,
		traveled = 0,
		item = item,
		params = params,
		ignored = ignored,
	})
end

function Projectiles.clear()
	for i = #shots, 1, -1 do
		finish(shots[i])
	end
end

function Projectiles.init()
	folder = workspace:WaitForChild("Projectiles") :: Folder
	RunService.Heartbeat:Connect(step)
end

return Projectiles
