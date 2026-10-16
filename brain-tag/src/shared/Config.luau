--!strict
-- Every tunable number in Brain Tag lives here. Change a value, rebuild, test.
-- Colors are hex strings so this file has no Roblox dependencies (the logic
-- tests in tests/ load it outside Roblox).

local Config = {}

-- Rounds ---------------------------------------------------------------------

Config.MIN_PLAYERS = 2 -- people (or test bots) needed before a round starts
Config.PREP_SECONDS = 60 -- "Outbreak happening in N seconds"
Config.ROUND_SECONDS = 180 -- survival timer after the outbreak (undocumented in the original)
Config.END_SCREEN_SECONDS = 6
Config.ZOMBIE_RATIO = 0.2 -- first zombies = max(1, floor(players * ratio))
Config.FIRST_ZOMBIES_TO_SPAWN = true -- teleport first zombies to the zombie spawn at outbreak
Config.ZOMBIE_RETURN_COOLDOWN = 5 -- seconds between Z presses

-- Movement and size ------------------------------------------------------------

Config.BASE_WALKSPEED = 16
Config.ZOMBIE_SPEED_FACTOR = 1.05
Config.SPEED_MULTIPLIER_CAP = 1.6 -- keeps very high scores from becoming uncatchable

-- 1 + score / 30000, fitted to the two screenshots (500 -> 1.02, 6729 -> 1.22).
function Config.SPEED_MULTIPLIER(score: number): number
	return math.min(Config.SPEED_MULTIPLIER_CAP, 1 + math.max(0, score) / 30000)
end

Config.GROWTH_PER_WIN = 0.04 -- size gained per survived round (this session)
Config.MAX_SCALE = 1.6

-- Rewards (score) --------------------------------------------------------------

Config.SURVIVOR_WIN_REWARD = 500
Config.INFECT_REWARD = 100
Config.ZOMBIE_WIN_REWARD = 250

-- Infection ----------------------------------------------------------------------

Config.INFECT_DISTANCE = 4 -- studs between body centers at scale 1 (scales with size)

-- Immunity (pills) ----------------------------------------------------------------

Config.IMMUNITY_MAX = 100
Config.IMMUNITY_WEIGHT = 0.8 -- pick weight = 1 - immunity/100 * this

-- Camera ---------------------------------------------------------------------------

Config.CAMERA_HEIGHT = 150
Config.CAMERA_FOV = 20 -- narrow field of view = near-orthographic flat 2D look
Config.CAMERA_SMOOTHING = 12 -- higher follows tighter
Config.CAMERA_ZOOMS = { Close = 120, Normal = 150, Far = 195 }

-- Character look (studs, at scale 1) -------------------------------------------------

Config.CHARACTER = {
	RootWidth = 2.6,
	RootHeight = 2,
	HipHeight = 1,
	HeadDiameter = 3,
	HeadThickness = 1,
	FistDiameter = 1.1,
}

Config.COLORS = {
	SelfName = "9BE22D", -- your own name tag (lime)
	OtherName = "FFFFFF",
	VipName = "F5C542",
	ZombieText = "E0303A",
	Panel = "1E1E1E",
	SystemMessage = "FFD54A",
	Accent = "3B82F6",
	Good = "4CC35A",
}

-- Furniture physics ---------------------------------------------------------------------

Config.FURNITURE_DENSITY = { Light = 0.4, Medium = 0.9, Heavy = 1.8 }
-- Fraction of the pusher's walk speed a piece moves at while being pushed.
Config.FURNITURE_PUSH_FACTOR = { Light = 0.85, Medium = 0.55, Heavy = 0.32 }
Config.FURNITURE_DRAG = 0.85 -- horizontal velocity kept per 1/60 s when nobody pushes
Config.FURNITURE_ANGULAR_DRAG = 0.8
Config.FURNITURE_MAX_SPEED = 14
Config.FURNITURE_SPIN = 0.035 -- how much off-center pushes rotate a piece
Config.PUSH_PROBE_DEPTH = 2.2 -- how far in front of a mover we look for furniture

-- Items -----------------------------------------------------------------------------------

Config.PICKUP_RADIUS = 6
Config.GROUND_ITEMS_MIN = 4
Config.GROUND_ITEMS_MAX = 6
Config.RARE_CHANCE = 0.05
Config.KNOCKBACK_SECONDS = 0.3 -- how long a shove lasts (stun is per item)

-- Wizard ------------------------------------------------------------------------------------

Config.WIZARD_SHOP_RADIUS = 10
Config.WIZARD_ARRIVE_MIN = 8 -- seconds into the prep phase
Config.WIZARD_ARRIVE_MAX = 40

-- Saving ------------------------------------------------------------------------------------

Config.DATASTORE_NAME = "BrainTag_v1"
Config.LEADERBOARD_STORE_NAME = "BrainTag_TopScores_v1"
Config.AUTOSAVE_SECONDS = 90
Config.TOP_SCORES_REFRESH_SECONDS = 120

-- Test bots (Studio only) ---------------------------------------------------------------------

Config.DEBUG_BOTS = true -- only ever active inside Roblox Studio
Config.DEBUG_BOT_COUNT = 4

-- Players walk through each other (furniture and walls still block). The
-- original felt this way, and it stops humans from body-blocking doorways.
Config.PLAYERS_COLLIDE = false

-- Sounds ---------------------------------------------------------------------------------------
-- Paths are sounds that ship inside the Roblox client. Leave a value "" to skip
-- that sound, or paste an audio asset id ("rbxassetid://123") you own.

Config.SOUNDS = {
	Whoosh = "rbxasset://sounds/swordslash.wav",
	Lunge = "rbxasset://sounds/swordlunge.wav",
	Groan = "rbxasset://sounds/uuhhh.mp3",
	RoundEnd = "rbxasset://sounds/electronicpingshort.wav",
	Pickup = "rbxasset://sounds/unsheath.wav",
	Potato = "",
	Shotgun = "",
	Scrape = "", -- loop while furniture slides; add your own id
}

-- Monetization ------------------------------------------------------------------------------------
-- Create these on create.roblox.com > your experience > Monetization, then paste
-- the ids here. A 0 means "not set up yet": the Robux shop hides it in live
-- servers and shows a "set up in Config" card in Studio. Suggested prices are
-- in README.md.

Config.MONETIZATION = {
	GamePasses = {
		VIP = 0, -- gold name, [VIP] chat tag, +20% score, VIP skins
		DoubleScore = 0, -- +100% score from every reward
		StarterKit = 0, -- start every round holding a Bat
		Lucky = 0, -- rare roll chance 5% -> 15%
	},
	Products = {
		InstantBat = 0,
		InstantSpear = 0,
		InstantShotgun = 0,
		ImmunityShot = 0, -- +50 immunity right now
		ScoreBoost30 = 0, -- 2x score for 30 minutes (stacks time)
		SkinDuck = 0,
		SkinAstronaut = 0,
		SkinFrost = 0,
		SkinMummy = 0,
	},
	VIP_SCORE_BONUS = 0.2,
	DOUBLE_SCORE_BONUS = 1,
	BOOST_SCORE_BONUS = 1,
	SCORE_BOOST_SECONDS = 30 * 60,
	LUCKY_RARE_CHANCE = 0.15,
	IMMUNITY_SHOT_AMOUNT = 50,
}

return Config
