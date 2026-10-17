--!strict
-- Pure round rules: who becomes a zombie, who won, and how much score a reward
-- is worth. No Roblox APIs, so tests/ can run this outside Studio.

local Config = require(script.Parent.Config)

local RoundRules = {}

-- How many first zombies to pick from `count` humans. Always leaves at least
-- one human so a round can't start already lost.
function RoundRules.firstZombieCount(count: number): number
	if count < 2 then
		return 0
	end
	local wanted = math.max(1, math.floor(count * Config.ZOMBIE_RATIO))
	return math.min(wanted, count - 1)
end

-- Weight for being picked as a first zombie. Never zero, so when everyone is
-- immune, pill-takers can still be chosen.
function RoundRules.zombieWeight(immunity: number): number
	local clamped = math.clamp(immunity, 0, Config.IMMUNITY_MAX)
	return 1 - clamped / Config.IMMUNITY_MAX * Config.IMMUNITY_WEIGHT
end

-- Weighted pick of `count` entries without replacement. `random` returns a
-- number in [0, 1).
function RoundRules.weightedPick<T>(
	entries: { T },
	weightOf: (T) -> number,
	count: number,
	random: () -> number
): { T }
	local pool = table.clone(entries)
	local picked = {}
	for _ = 1, math.min(count, #pool) do
		local total = 0
		for _, entry in pool do
			total += math.max(0, weightOf(entry))
		end
		local index = #pool
		if total <= 0 then
			index = math.clamp(math.floor(random() * #pool) + 1, 1, #pool)
		else
			local roll = random() * total
			for i, entry in pool do
				roll -= math.max(0, weightOf(entry))
				if roll < 0 then
					index = i
					break
				end
			end
		end
		table.insert(picked, table.remove(pool, index) :: T)
	end
	return picked
end

export type Winner = "Survivors" | "Zombies"

-- "Zombies" when no humans remain, "Survivors" when the timer ran out with any
-- human standing, otherwise nil (round continues).
function RoundRules.outcome(humans: number, secondsLeft: number): Winner?
	if humans <= 0 then
		return "Zombies"
	end
	if secondsLeft <= 0 then
		return "Survivors"
	end
	return nil
end

export type RewardBonuses = {
	drumstick: number?, -- 0.4 or 0.8 while holding one
	vip: boolean?,
	doubleScore: boolean?,
	boosted: boolean?,
}

-- Bonuses add together: a VIP holding a drumstick earns 1 + 0.4 + 0.2 = 1.6x.
function RoundRules.rewardMultiplier(bonuses: RewardBonuses): number
	local m = 1 + (bonuses.drumstick or 0)
	local money = Config.MONETIZATION
	if bonuses.vip then
		m += money.VIP_SCORE_BONUS
	end
	if bonuses.doubleScore then
		m += money.DOUBLE_SCORE_BONUS
	end
	if bonuses.boosted then
		m += money.BOOST_SCORE_BONUS
	end
	return m
end

function RoundRules.reward(base: number, bonuses: RewardBonuses): number
	return math.floor(base * RoundRules.rewardMultiplier(bonuses) + 0.5)
end

function RoundRules.scaleForScore(score: number): number
	return Config.SIZE_MULTIPLIER(score)
end

-- Pushing strength of one player: grows with the square of their size.
function RoundRules.pushStrength(scale: number): number
	return scale * scale
end

-- Fraction of walk speed a piece of `mass` moves at under `strength` (the
-- summed strength of everyone pushing it). 0 means it won't budge.
function RoundRules.pushFraction(mass: number, strength: number): number
	if strength <= 0 then
		return 0
	end
	return math.clamp(1 - mass / strength, 0, Config.PUSH_MAX_FRACTION)
end

function RoundRules.walkSpeed(score: number, isZombie: boolean): number
	local speed = Config.BASE_WALKSPEED * Config.SPEED_MULTIPLIER(score)
	if isZombie then
		speed *= Config.ZOMBIE_SPEED_FACTOR
	end
	return speed
end

-- Infection reach between two bodies of the given scales.
function RoundRules.infectDistance(scaleA: number, scaleB: number): number
	return Config.INFECT_DISTANCE * (scaleA + scaleB) / 2
end

return RoundRules
