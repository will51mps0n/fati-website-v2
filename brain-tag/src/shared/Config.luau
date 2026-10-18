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
Config.MAP_ROTATION =
	{ "Neighborhood", "Haunted", "Mansion", "PumpkinFarm", "ChristmasTown", "SpookyVillage", "WitchWoods" }
Config.ROUNDS_PER_MAP = 2

-- Movement and size ------------------------------------------------------------

Config.BASE_WALKSPEED = 16
Config.ZOMBIE_SPEED_FACTOR = 1.15 -- zombies are faster than humans of the same size
Config.SPEED_MULTIPLIER_CAP = 1.6 -- keeps very high scores from becoming uncatchable

-- 1 + score / 30000, fitted to the two screenshots (500 -> 1.02, 6729 -> 1.22).
function Config.SPEED_MULTIPLIER(score: number): number
	return math.min(Config.SPEED_MULTIPLIER_CAP, 1 + math.max(0, score) / 30000)
end

-- Size also grows with score, much faster than speed: in the original the top
-- player (12,855 points) was about 2.7x the size of a newcomer, and you keep
-- growing after that. Only the collision box stops growing
-- (CHARACTER.MaxRootWidth), so even giants fit through doors.
Config.MAX_SCALE = 8
function Config.SIZE_MULTIPLIER(score: number): number
	return math.min(Config.MAX_SCALE, 1 + math.max(0, score) / 8000)
end

-- Width of the collision box at a size: grows with you up to MaxRootWidth.
function Config.rootWidth(scale: number): number
	return math.min(Config.CHARACTER.RootWidth * scale, Config.CHARACTER.MaxRootWidth)
end

-- How far furniture is kept from your center (the bumper, BumperDiameter at
-- size 1). It follows the collision box, so a giant's bumper never reaches
-- through a wall into the next room.
function Config.bumperRadius(scale: number): number
	local C = Config.CHARACTER
	return Config.rootWidth(scale) / 2 + (C.BumperDiameter - C.RootWidth) / 2 * math.min(scale, 1.5)
end

-- Rewards (score) --------------------------------------------------------------

Config.SURVIVOR_WIN_REWARD = 500
-- Staying alive pays as you go: every human gets this much every few
-- seconds of the outbreak (a "+10" floats up on their screen).
Config.SURVIVAL_POINTS = 10
Config.SURVIVAL_POINTS_SECONDS = 5
-- Being a zombie costs you: on the same beat, every zombie loses this share
-- of its points (at least ZOMBIE_DECAY_MIN), so they shrink unless they eat.
Config.ZOMBIE_DECAY_FRACTION = 0.02
Config.ZOMBIE_DECAY_MIN = 5
Config.INFECT_REWARD = 50 -- flat bonus for any infection, on top of the points eaten
Config.ZOMBIE_WIN_REWARD = 250
-- Getting eaten costs you this share of your points, and the zombie that
-- ate you gets them (so zombies grow as they feed).
Config.INFECT_STEAL_FRACTION = 0.75 -- getting eaten costs most of your points

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
	MaxRootWidth = 5.5, -- never wider than this, however big you grow (doors are 6+)
	RootHeight = 2,
	HipHeight = 1,
	BodyWidth = 3.6, -- shoulders, side to side
	BodyDepth = 2.1, -- front to back
	HeadDiameter = 2.3,
	-- Characters bump into each other with an invisible cylinder this wide
	-- (only other characters collide with it, so doors still fit).
	ShellDiameter = 3,
	-- Furniture keeps a little space from you: only furniture collides with
	-- this wider invisible cylinder, so you never end up right on top of
	-- what you push.
	BumperDiameter = 4.4,
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
-- pool table or piano only creeps; at size 2 both move easily. Pushers team
-- up, and a line of people walking into each other's backs adds up too.
Config.FURNITURE_MASS = { Light = 0.15, Medium = 0.45, Heavy = 0.68, Massive = 0.9 }
Config.PUSH_MAX_FRACTION = 0.9
-- Each person behind the one touching a piece lends this share of their
-- (already compounded) strength, so five zombies in a queue shove like ~3.7.
Config.PUSH_CHAIN_SHARE = 0.85
-- Zombies are stronger than humans of the same size: furniture, a weapon held
-- out at them, a barricade standoff.
Config.ZOMBIE_STRENGTH = 1.5
Config.FURNITURE_DENSITY = { Light = 0.4, Medium = 0.9, Heavy = 1.8, Massive = 3 }
Config.FURNITURE_MAX_SPEED = 22
Config.FURNITURE_RELEASE_SECONDS = 0.6 -- your client stops driving a piece this long after you stop pushing
Config.FURNITURE_SPIN = 0.035 -- how much off-center pushes rotate a piece
-- A piece starts moving this far (studs, at size 1) before it reaches your
-- bumper, so you push it from a little way off instead of walking into it.
Config.PUSH_REACH = 1.4

-- Bushes ------------------------------------------------------------------------------------
-- Walk into a bush to hide: it covers you from above, your name tag
-- disappears for everyone outside it, and bots can't find you unless they
-- come this close.
Config.BUSH_HEIGHT = 9 -- canopy top, taller than the biggest character
Config.BUSH_REVEAL_DISTANCE = 9
Config.BUSH_SEE_THROUGH = 0.55 -- the bush you're in fades this much on your screen

-- Items -----------------------------------------------------------------------------------

Config.PICKUP_RADIUS = 6
Config.INVENTORY_SLOTS = 3 -- items you can carry; keys 1-3 switch which one is in your hand
Config.GROUND_ITEMS_MIN = 1 -- items are rare: mostly you buy them
Config.GROUND_ITEMS_MAX = 2
Config.RARE_CHANCE = 0.05
Config.KNOCKBACK_SECONDS = 0.3 -- how long a shove lasts (stun is per item)
-- Held melee weapons are solid but not bouncy: someone pressing on the
-- shaft is held off it and pushes the holder back, shared by size squared
-- (times the weapon's firmness). This is how fast an overlap is undone.
Config.SHAFT_SOFTNESS = 12
Config.SHAFT_FURNITURE_FACTOR = 0.8 -- push speed while standing still / turning, as a share of walk speed
-- Soft force fields you feel on your own screen (client ForceField): how
-- fast people / weapons push you apart per stud of overlap, and the caps.
Config.FIELD_BODY = 10
Config.FIELD_BODY_MAX = 14
Config.FIELD_WEAPON = 14
Config.FIELD_WEAPON_MAX = 24
Config.FIELD_RECOIL = 14 -- someone pressing on your weapon pushes you back this hard (by their share)
-- Furniture is solid to weapons: a piece pressed into your weapon (or your
-- weapon pressed into one that can't give) pushes you back this hard per
-- stud, so the weapon bounces off instead of sinking in.
Config.FIELD_FURNITURE = 30

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
Config.LEADERBOARD_STORE_NAME = "BrainTag_BestScores_v1" -- best single visit
Config.AUTOSAVE_SECONDS = 90
Config.TOP_SCORES_REFRESH_SECONDS = 120

-- Test bots (Studio only) ---------------------------------------------------------------------

-- Bots join every server, live games included (see BotService for their
-- names and difficulty levels; Mario Robles is the hardest).
Config.BOTS = true
Config.BOTS_MIN = 10 -- each round picks a bot count in this range
Config.BOTS_MAX = 14
Config.MAX_PARTICIPANTS = 40 -- bots make room as real players join
Config.BOTS_WITH_SKINS = 3 -- how many bots wear special skins; the rest look classic
Config.BOT_WEAPON_CHANCE = 0.2 -- chance a bot starts a round with a (cheap) weapon
Config.BOT_MAX_ITEM_PRICE = 1000 -- bots only pick up common items up to this score price

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
		InstantAncientSpear = 0, -- the super rare spear: Robux only, the one weapon that strikes
		ImmunityShot = 0, -- +50 immunity right now
		ScoreBoost30 = 0, -- 2x score for 30 minutes (stacks time)
		SkinDuck = 0,
		SkinAstronaut = 0,
		SkinDog = 0,
		SkinPanda = 0,
		SkinRobot = 0,
		SkinAlien = 0,
		SkinShark = 0,
		SkinAwesome = 0,
	},
	VIP_SCORE_BONUS = 0.2,
	DOUBLE_SCORE_BONUS = 1,
	BOOST_SCORE_BONUS = 1,
	SCORE_BOOST_SECONDS = 30 * 60,
	LUCKY_RARE_CHANCE = 0.15,
	IMMUNITY_SHOT_AMOUNT = 50,
}

-- Ids saved in the place itself win over the zeros above: attributes on
-- ReplicatedStorage named "Pass_<key>" or "Product_<key>" (for example
-- Product_InstantBat = 1234567890). Updates to the game's code never touch
-- them. See README "Setting up Robux items".
do
	local function load(storage: Instance, prefix: string, ids: { [string]: number })
		for key in ids do
			local saved = storage:GetAttribute(prefix .. key)
			if typeof(saved) == "number" and saved > 0 then
				ids[key] = saved
			end
		end
	end
	-- Outside Roblox (tests, tools) there is no place to read, so skip quietly.
	pcall(function()
		local storage = game:GetService("ReplicatedStorage")
		load(storage, "Pass_", Config.MONETIZATION.GamePasses :: any)
		load(storage, "Product_", Config.MONETIZATION.Products :: any)
	end)
end

return Config
