-- Round rules, config formulas, item and skin data.
local Config = require(script.Parent.Config)
local RoundRules = require(script.Parent.RoundRules)
local Items = require(script.Parent.Items)
local Skins = require(script.Parent.Skins)

local function twoDecimals(x: number): string
	return string.format("%.2f", x)
end

test("speed multiplier matches the screenshots", function()
	expectEq(twoDecimals(Config.SPEED_MULTIPLIER(500)), "1.02", "score 500")
	expectEq(twoDecimals(Config.SPEED_MULTIPLIER(6729)), "1.22", "score 6729")
	expectEq(Config.SPEED_MULTIPLIER(0), 1, "score 0")
	expectEq(Config.SPEED_MULTIPLIER(-50), 1, "negative score")
	expectEq(Config.SPEED_MULTIPLIER(10 ^ 9), Config.SPEED_MULTIPLIER_CAP, "capped")
end)

test("first zombie count", function()
	expectEq(RoundRules.firstZombieCount(1), 0, "1 player")
	expectEq(RoundRules.firstZombieCount(2), 1, "2 players")
	expectEq(RoundRules.firstZombieCount(5), 1, "5 players")
	expectEq(RoundRules.firstZombieCount(10), 2, "10 players")
	expectEq(RoundRules.firstZombieCount(30), 6, "30 players")
	for n = 2, 60 do
		local k = RoundRules.firstZombieCount(n)
		expect(k >= 1 and k <= n - 1, "always leaves a human at n=" .. n)
	end
end)

test("immunity lowers but never removes the chance", function()
	expectEq(RoundRules.zombieWeight(0), 1, "no immunity")
	expect(math.abs(RoundRules.zombieWeight(100) - 0.2) < 1e-9, "full immunity weight 0.2")
	expectEq(RoundRules.zombieWeight(500), RoundRules.zombieWeight(100), "clamped")
end)

test("weighted pick respects weights and count", function()
	local seed = 12345
	local function random()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local people = {
		{ name = "pill", immunity = 100 },
		{ name = "a", immunity = 0 },
		{ name = "b", immunity = 0 },
		{ name = "c", immunity = 0 },
	}
	local counts = { pill = 0, a = 0, b = 0, c = 0 }
	for _ = 1, 20000 do
		local picked = RoundRules.weightedPick(people, function(p)
			return RoundRules.zombieWeight(p.immunity)
		end, 1, random)
		expectEq(#picked, 1, "picked one")
		counts[picked[1].name] += 1
	end
	-- Expected share for the pill-taker: 0.2 / 3.2 = 6.25%.
	local share = counts.pill / 20000
	expect(share > 0.045 and share < 0.08, "pill share " .. share)
	-- Each non-immune player should land near 31%, five times the pill-taker.
	expect(counts.a > counts.pill * 3, "non-immune picked far more often")

	local many = RoundRules.weightedPick(people, function()
		return 0
	end, 10, random)
	expectEq(#many, 4, "never more than the pool, even with zero weights")
	local seen = {}
	for _, p in many do
		expect(not seen[p.name], "no duplicates")
		seen[p.name] = true
	end
end)

test("round outcome", function()
	expectEq(RoundRules.outcome(0, 100), "Zombies", "everyone infected")
	expectEq(RoundRules.outcome(3, 0), "Survivors", "timer ran out")
	expectEq(RoundRules.outcome(0, 0), "Zombies", "last human tagged on the buzzer")
	expectEq(RoundRules.outcome(2, 50), nil, "still going")
end)

test("rewards stack additively", function()
	expectEq(RoundRules.reward(500, {}), 500, "plain")
	expectEq(RoundRules.reward(500, { drumstick = 0.4 }), 700, "drumstick")
	expectEq(RoundRules.reward(500, { drumstick = 0.8 }), 900, "golden drumstick")
	expectEq(RoundRules.reward(500, { vip = true }), 600, "vip")
	expectEq(RoundRules.reward(500, { doubleScore = true }), 1000, "double")
	expectEq(
		RoundRules.reward(100, { drumstick = 0.4, vip = true, doubleScore = true, boosted = true }),
		360,
		"all"
	)
end)

test("size grows with score and is capped", function()
	expectEq(RoundRules.scaleForScore(0), 1, "start size")
	expect(RoundRules.scaleForScore(6340) > 1.6, "6,340 points is clearly bigger")
	expect(RoundRules.scaleForScore(12855) >= 2.4, "top player is much bigger")
	expectEq(RoundRules.scaleForScore(10 ^ 9), Config.MAX_SCALE, "cap")
end)

test("bigger players push heavier furniture", function()
	local mass = Config.FURNITURE_MASS
	local small = RoundRules.pushStrength(1)
	local big = RoundRules.pushStrength(2)
	expect(RoundRules.pushFraction(mass.Light, small) > 0.8, "light moves fast")
	expect(RoundRules.pushFraction(mass.Heavy, small) > 0.25, "a newcomer can still move a couch")
	local alone = RoundRules.pushFraction(mass.Massive, small)
	expect(alone > 0 and alone < 0.2, "a newcomer only creeps a pool table")
	expect(RoundRules.pushFraction(mass.Massive, big) > 0.6, "a big player can")
	expect(RoundRules.pushFraction(mass.Massive, small + small) > 0.4, "two newcomers together can")
	-- A queue of five newcomers, each leaning on the one ahead.
	local queue, share = 0, 1
	for _ = 1, 5 do
		queue += small * share
		share *= Config.PUSH_CHAIN_SHARE
	end
	expect(RoundRules.pushFraction(mass.Massive, queue) > 0.7, "a queue shoves it easily")
	expect(
		RoundRules.pushFraction(mass.Heavy, big) > RoundRules.pushFraction(mass.Heavy, small),
		"size helps"
	)
	expect(RoundRules.pushFraction(mass.Light, 100) <= Config.PUSH_MAX_FRACTION, "capped")
end)

test("zombies are faster and stronger", function()
	expect(RoundRules.walkSpeed(0, true) > RoundRules.walkSpeed(0, false), "zombie faster")
	expect(RoundRules.pushStrength(1, true) > RoundRules.pushStrength(1), "zombie stronger")
	local mass = Config.FURNITURE_MASS
	expect(
		RoundRules.pushFraction(mass.Heavy, RoundRules.pushStrength(1, true)) > 0.5,
		"a zombie shoves a couch at over half speed"
	)
	expectEq(RoundRules.walkSpeed(0, false), Config.BASE_WALKSPEED, "base speed")
end)

test("item data is consistent", function()
	for id, item in Items.all do
		expectEq(item.id, id, "id matches key")
		if item.rare then
			local rare = Items.get(item.rare)
			expect(rare ~= nil, id .. " rare variant exists")
			expect(rare and rare.isRare, id .. " rare variant is flagged rare")
			expect(rare and rare.kind == item.kind, id .. " rare variant has the same kind")
		end
		if item.kind == "Melee" or item.kind == "Blast" then
			expect(
				item.reach and item.arc and item.knockback and item.stun and item.cooldown,
				id .. " melee stats"
			)
		elseif item.kind == "Projectile" then
			expect(
				item.projectileSpeed and item.projectileRange and item.knockback and item.cooldown,
				id .. " gun stats"
			)
		elseif item.kind == "Consumable" then
			expect(item.immunity or (item.speedBoost and item.boostSeconds), id .. " consumable stats")
		elseif item.kind == "Passive" then
			expect(item.rewardBonus, id .. " drumstick stats")
		elseif item.kind == "Stream" then
			expect(item.reach and item.arc and item.knockback and item.tick, id .. " stream stats")
		elseif item.kind == "Trap" then
			expect(item.charges and item.knockback and item.stun, id .. " trap stats")
		end
		if item.kind == "Projectile" then
			expect(item.projectile ~= nil, id .. " has a projectile look")
		end
		if item.kind == "Melee" then
			expect(item.firmness and item.guard, id .. " melee solidity (firmness, guard)")
		end
		if item.effect == "Explode" then
			expect(item.radius, id .. " blast radius")
		end
		if item.kind == "Consumable" then
			expect(item.immunity or item.speedBoost, id .. " does something")
		end
		if item.robuxProduct then
			expect(Config.MONETIZATION.Products[item.robuxProduct] ~= nil, id .. " product key exists")
		end
	end
	for _, id in Items.shopOrder do
		local item = Items.get(id)
		expect(item and item.price and item.price > 0, id .. " sold in the shop")
	end
	for _, id in Items.wizardOrder do
		local item = Items.get(id)
		expect(item and item.wizardPrice and item.wizardPrice > 0, id .. " sold by the wizard")
	end
	expectEq(Items.get("Bat").price, 750, "bat price from the wiki")
	expectEq(Items.get("Swordfish").price, 2500, "swordfish price from the wiki")
	expectEq(Items.get("Spear").price, 3500, "spear price from the wiki")
	expectEq(Items.get("Shotgun").price, 10000, "shotgun price from the wiki")
	expect(#Items.groundTable() >= 1, "something can lie around the map")
	local count = 0
	for _ in Items.all do
		count += 1
	end
	expect(count >= 25, "lots of items: " .. count)
	local listed = {}
	for _, id in Items.shopOrder do
		expect(not listed[id], id .. " listed once")
		listed[id] = true
	end
end)

test("skin data is consistent", function()
	local seen = {}
	local defaults = { Human = 0, Zombie = 0 }
	for _, skin in Skins.list do
		expect(not seen[skin.id], "unique skin id " .. skin.id)
		seen[skin.id] = true
		if skin.default then
			defaults[skin.team] += 1
		end
		if skin.product then
			expect(Config.MONETIZATION.Products[skin.product] ~= nil, skin.id .. " product key exists")
		end
		if skin.pass then
			expect(Config.MONETIZATION.GamePasses[skin.pass] ~= nil, skin.id .. " pass key exists")
		end
		local unlocks = (if skin.default then 1 else 0)
			+ (if skin.scorePrice then 1 else 0)
			+ (if skin.product then 1 else 0)
			+ (if skin.pass then 1 else 0)
			+ (if skin.special then 1 else 0)
		expectEq(unlocks, 1, skin.id .. " has exactly one way to unlock")
		expect(#skin.shirt == 6 and #skin.hair == 6 and #skin.skin == 6, skin.id .. " colors are hex")
	end
	expectEq(defaults.Human, 1, "one default human skin")
	expectEq(defaults.Zombie, 1, "one default zombie skin")
	expectEq(Skins.resolve("Duck", "Zombie").id, Skins.DEFAULT_ZOMBIE, "wrong team falls back")
	expectEq(Skins.resolve("nope", "Human").id, Skins.DEFAULT_HUMAN, "unknown falls back")
	expectEq(Skins.resolve("Duck", "Human").id, "Duck", "valid skin kept")
end)
