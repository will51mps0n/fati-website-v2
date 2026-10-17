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

-- Maps take turns. Each name is a layout in MapLayout.luau.
Config.MAP_ROTATION = { "Neighborhood", "Mansion" }
Config.ROUNDS_PER_MAP = 2

-- Movement and size ------------------------------------------------------------

Config.BASE_WALKSPEED = 16
Config.ZOMBIE_SPEED_FACTOR = 1.05
Config.SPEED_MULTIPLIER_CAP = 1.6 -- keeps very high scores from becoming uncatchable

-- 1 + score / 30000, fitted to the two screenshots (500 -> 1.02, 6729 -> 1.22).
function Config.SPEED_MULTIPLIER(score: number): number
	return math.min(Config.SPEED_MULTIPLIER_CAP, 1 + math.max(0, score) / 30000)
end

-- Size also grows with score, much faster than speed: in the original the top
-- player (12,855 points) was about 2.7x the size of a newcomer.
Config.MAX_SCALE = 2.5
function Config.SIZE_MULTIPLIER(score: number): number
	return math.min(Config.MAX_SCALE, 1 + math.max(0, score) / 8000)
end

-- Rewards (score) --------------------------------------------------------------

Config.SURVIVOR_WIN_REWARD = 500
Config.INFECT_REWARD = 50 -- flat bonus for any infection, on top of the points eaten
Config.ZOMBIE_WIN_REWARD = 250
-- Getting eaten costs you this share of your points, and the zombie that
-- ate you gets them (so zombies grow as they feed).
Config.INFECT_STEAL_FRACTION = 0.25 -- eat a big player, gain a lot

-- Infection ----------------------------------------------------------------------

Config.INFECT_DISTANCE = 4 -- studs between body centers at scale 1 (scales with size); must stay above ShellDiameter

-- Immunity (pills) ----------------------------------------------------------------

Config.IMMUNITY_MAX = 100
Config.IMMUNITY_WEIGHT = 0.8 -- pick weight = 1 - immunity/100 * this

-- Camera ---------------------------------------------------------------------------

Config.CAMERA_HEIGHT = 175
Config.CAMERA_FOV = 20 -- narrow field of view = near-orthographic flat 2D look
Config.CAMERA_SMOOTHING = 0 -- 0 = locked to you like the original; e.g. 12 for a soft follow
Config.CAMERA_ZOOMS = { Close = 140, Normal = 175, Far = 220 }
Config.CAMERA_GROWTH = 0.35 -- the camera rises this much per extra unit of your size

-- Character look (studs, at scale 1) -------------------------------------------------

Config.CHARACTER = {
	-- The collision box is narrower than the drawn body so even the biggest
	-- players (MAX_SCALE) still fit through a 7-stud doorway.
	RootWidth = 2.2,
	RootHeight = 2,
	HipHeight = 1,
	BodyWidth = 3.6, -- shoulders, side to side
	BodyDepth = 2.1, -- front to back
	HeadDiameter = 2.3,
	-- Characters bump into each other with an invisible cylinder this wide
	-- (only other characters collide with it, so doors still fit).
	ShellDiameter = 3,
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

-- How hard each weight class is to move. Pushers add their strength (size
-- squared), and a piece moves at walk speed * (1 - mass / strength), capped
-- at PUSH_MAX_FRACTION. At size 1 a couch moves at a third of your speed and a
-- piano not at all; at size 2 both move easily. Two players can team up.
Config.FURNITURE_MASS = { Light = 0.15, Medium = 0.45, Heavy = 0.68, Massive = 1.15 }
Config.PUSH_MAX_FRACTION = 0.9
Config.FURNITURE_DENSITY = { Light = 0.4, Medium = 0.9, Heavy = 1.8, Massive = 3 }
Config.FURNITURE_MAX_SPEED = 22
Config.FURNITURE_RELEASE_SECONDS = 0.6 -- your client stops driving a piece this long after you stop pushing
Config.FURNITURE_SPIN = 0.035 -- how much off-center pushes rotate a piece
Config.PUSH_PROBE_DEPTH = 2.2 -- how far in front of a mover we look for furniture

-- Bushes ------------------------------------------------------------------------------------
-- Walk into a bush to hide: it covers you from above, your name tag
-- disappears for everyone outside it, and bots can't find you unless they
-- come this close.
Config.BUSH_HEIGHT = 9 -- canopy top, taller than the biggest character
Config.BUSH_REVEAL_DISTANCE = 9
Config.BUSH_SEE_THROUGH = 0.55 -- the bush you're in fades this much on your screen

-- Items -----------------------------------------------------------------------------------

Config.PICKUP_RADIUS = 6
Config.GROUND_ITEMS_MIN = 2
Config.GROUND_ITEMS_MAX = 3
Config.RARE_CHANCE = 0.05
Config.KNOCKBACK_SECONDS = 0.3 -- how long a shove lasts (stun is per item)
-- Held melee weapons are solid: zombies touching the shaft are shoved off it
-- (this fast, in short pulses), and furniture it overlaps is pushed aside.
Config.SHAFT_ZOMBIE_PUSH = 22
Config.SHAFT_PULSE_SHARE = 0.75 -- share of each push tick a firm weapon pushes; the rest the zombie can steer
Config.SHAFT_FURNITURE_FACTOR = 0.8 -- push speed while standing still / turning, as a share of walk speed

-- Wizard ------------------------------------------------------------------------------------

Config.WIZARD_SHOP_RADIUS = 10
Config.WIZARD_ARRIVE_MIN = 8 -- seconds into the prep phase
Config.WIZARD_ARRIVE_MAX = 40

-- Admins ------------------------------------------------------------------------------------
-- The admin panel (F2, or the ADMIN button) is open to: everyone while testing
-- in Studio, the experience's owner (or rank 254+ in the owning group), and
-- these UserIds.
Config.ADMIN_USER_IDS = {} :: { number }

-- Saving ------------------------------------------------------------------------------------

Config.DATASTORE_NAME = "BrainTag_v1"
Config.LEADERBOARD_STORE_NAME = "BrainTag_TopScores_v1"
Config.AUTOSAVE_SECONDS = 90
Config.TOP_SCORES_REFRESH_SECONDS = 120

-- Test bots (Studio only) ---------------------------------------------------------------------

-- Bots join every server, live games included (see BotService for their
-- names and difficulty levels; Mario Robles is the hardest).
Config.BOTS = true
Config.BOTS_MIN = 20 -- each round picks a bot count in this range
Config.BOTS_MAX = 30
Config.MAX_PARTICIPANTS = 40 -- bots make room as real players join
Config.BOTS_WITH_SKINS = 3 -- how many bots wear special skins; the rest look classic

-- Characters bump into each other (human/human, zombie/zombie and
-- zombie/human). Set false to let everyone walk through each other.
Config.PLAYERS_COLLIDE = true

-- Sounds ---------------------------------------------------------------------------------------
-- Every sound is built from files that ship with Roblox (see the client's
-- SoundBank). To swap one for an audio asset you own, paste its id here by
-- name, e.g. Squeak = "rbxassetid://1234567890". Names: Whoosh, Lunge, Swish,
-- Hit, Clang, Squeak, Boing, Pop, Twang, Gulp, Slip, Shoot, Shotgun, Boom,
-- Splat, Plunge, Freeze, Bubble, WallBreak, Bump, Infect, Groan, Pickup, Drop,
-- Eat, Warp, Outbreak, RoundWin, RoundLose, Tick, TickFinal, UiClick, Buy,
-- Error, Wizard, Spray, Blower, Scrape, Footsteps.

Config.SOUND_OVERRIDES = {} :: { [string]: string }

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
		SkinDog = 0,
		SkinPanda = 0,
		SkinRobot = 0,
		SkinAlien = 0,
		SkinShark = 0,
		SkinHotdog = 0,
		SkinGhost = 0,
		SkinVampire = 0,
	},
	VIP_SCORE_BONUS = 0.2,
	DOUBLE_SCORE_BONUS = 1,
	BOOST_SCORE_BONUS = 1,
	SCORE_BOOST_SECONDS = 30 * 60,
	LUCKY_RARE_CHANCE = 0.15,
	IMMUNITY_SHOT_AMOUNT = 50,
}

return Config
