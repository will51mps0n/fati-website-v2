-- Shared settings for the server and every client. Tweak the game here.

local Config = {}

-- Match structure ----------------------------------------------------------

-- A match is a batch of rounds. In each round every player draws once.
Config.ROUNDS_PER_MATCH = 6
Config.MIN_PLAYERS = 2

-- Phase lengths, in seconds.
Config.STARTING_TIME = 8 -- countdown before a match begins
Config.CHOOSE_TIME = 15 -- drawer picks a word
Config.DRAW_TIME = 80 -- everyone else guesses
Config.TURN_END_TIME = 6 -- word reveal between turns
Config.MATCH_END_TIME = 12 -- winners screen

Config.WORD_CHOICES = 3

-- The theme everyone starts with (an id from Themes.luau). Players can switch theirs
-- with the "Your theme" menu.
Config.DEFAULT_THEME = "halloween"

-- Opening the custom word form gives the drawer at least this many seconds to buy
-- and type (once per turn).
Config.CUSTOM_WORD_TIME = 30

-- Robux shop. Each item is a Developer Product: create it on the Creator Hub (your
-- game → Monetization → Developer Products) with this price, then paste its ID here.
-- The game shows each product's live price from Roblox (which can change with
-- "Managed pricing"); `price` is only shown if that can't be looked up. Until an ID
-- is filled in, the item is free while testing in Studio and unavailable in the
-- published game.
Config.PRODUCTS = {
	customWord = { id = 3718880573, price = 9 }, -- draw any word you type
	nuke = { id = 3718880654, price = 99 }, -- wipe the current drawing
	steal = { id = 3718880703, price = 49 }, -- take over drawing for the rest of the turn
	instaGuess = { id = 3718880747, price = 25 }, -- guess the word instantly
}

-- Vote to kick: a player is kicked once this share of the other players vote for
-- it (and never with fewer than VOTE_KICK_MIN votes, so 2 players can't kick each other).
Config.VOTE_KICK_SHARE = 0.6
Config.VOTE_KICK_MIN = 2

-- A letter of the word is revealed once this fraction of the draw time has passed.
Config.HINT_FRACTIONS = { 0.5, 0.75 }

-- Scoring --------------------------------------------------------------------

Config.MAX_GUESS_POINTS = 300 -- guessing instantly
Config.MIN_GUESS_POINTS = 50 -- guessing in the last second
Config.FIRST_GUESS_BONUS = 50
Config.DRAWER_POINTS_PER_GUESS = 50

-- When false the game is UI-only: nobody gets an avatar in the 3D world.
Config.SPAWN_CHARACTERS = false

-- Look & sound -------------------------------------------------------------------

-- Upload the files in the assets folder (see the README), then paste each asset ID
-- between the quotes, like "rbxassetid://1234567890". Empty ones are skipped: no
-- background picture (just the green), or no sound.

-- The seamless square (assets/background-tile.png), repeated across the screen at
-- BACKGROUND_TILE_SIZE so the doodles look small and detailed. When it's empty,
-- BACKGROUND_IMAGE is shown once, stretched to cover the screen.
Config.BACKGROUND_TILE = "rbxassetid://123267927775699" -- assets/background-tile.png
Config.BACKGROUND_IMAGE = "rbxassetid://107099391291442" -- your background.jpeg

-- Just the doodle lines, white on see-through (assets/background-doodles.png). Each
-- theme tints them and colours the screen behind them. Until this is set, the green
-- tile above is used for the General theme and the others show plain colour.
Config.BACKGROUND_DOODLES = "rbxassetid://110219448107097" -- assets/background-doodles.png

-- The thumbs in the canvas's top-right corner. Until these are set, emoji stand in.
Config.THUMBS_UP_IMAGE = "rbxassetid://132536788217807" -- assets/thumbs-up.png
Config.THUMBS_DOWN_IMAGE = "rbxassetid://108441151233215" -- assets/thumbs-down.png

Config.SOUNDS = {
	click = "rbxassetid://117439492244306", -- assets/sounds/click.ogg
	tick = "rbxassetid://130785928873648", -- assets/sounds/tick.ogg
	correct = "rbxassetid://76162664841053", -- assets/sounds/correct.ogg
	yourTurn = "rbxassetid://84068102723904", -- assets/sounds/your-turn.ogg
	timeUp = "rbxassetid://105977925187605", -- assets/sounds/time-up.ogg
	victory = "rbxassetid://119138221086024", -- assets/sounds/victory.ogg
}

Config.BACKGROUND_TILE_SIZE = 500 -- on-screen size of one tile in pixels; smaller = tinier doodles
-- How fast the background slides, in pixels per second; 0 keeps it still. It moves
-- in 1-pixel hops on an even beat; faster speeds hop more often and look smoother
-- (60 = one hop every frame on a 60 fps screen).
Config.BACKGROUND_SCROLL_SPEED = 0
Config.SOUND_VOLUME = 0.5

-- Canvas ---------------------------------------------------------------------

Config.CANVAS_ASPECT = 4 / 3 -- width / height
Config.BACKGROUND_COLOR = Color3.fromRGB(255, 255, 255)

-- Colour index 0 is the eraser (paints the background colour).
Config.COLORS = {
	{ name = "Black", color = Color3.fromRGB(20, 20, 20) },
	{ name = "Gray", color = Color3.fromRGB(128, 128, 128) },
	{ name = "Red", color = Color3.fromRGB(230, 41, 41) },
	{ name = "Orange", color = Color3.fromRGB(255, 140, 0) },
	{ name = "Yellow", color = Color3.fromRGB(255, 221, 0) },
	{ name = "Green", color = Color3.fromRGB(0, 160, 60) },
	{ name = "Blue", color = Color3.fromRGB(30, 90, 230) },
	{ name = "White", color = Color3.fromRGB(255, 255, 255) },
	{ name = "Light gray", color = Color3.fromRGB(200, 200, 200) },
	{ name = "Brown", color = Color3.fromRGB(130, 80, 40) },
	{ name = "Pink", color = Color3.fromRGB(255, 130, 190) },
	{ name = "Lime", color = Color3.fromRGB(120, 230, 60) },
	{ name = "Sky blue", color = Color3.fromRGB(80, 200, 255) },
	{ name = "Purple", color = Color3.fromRGB(140, 60, 200) },
}

-- The bucket fills on a grid this many cells wide (and tall to match the canvas).
-- Finer grids hug lines more closely but make each fill slower and heavier.
Config.FILL_GRID_WIDTH = 320
Config.MIN_FILL_INTERVAL = 0.25 -- seconds between bucket fills

-- Brush diameters as a fraction of the canvas width.
Config.BRUSH_SIZES = { 0.006, 0.012, 0.024, 0.045 }
Config.DEFAULT_BRUSH_SIZE = 2

-- Networking -------------------------------------------------------------------

Config.SEND_INTERVAL = 0.05 -- how often the drawer streams new points
Config.MIN_POINT_DISTANCE = 0.002 -- skip points closer than this (canvas widths)
Config.MAX_NUMBERS_PER_PACKET = 600 -- x,y pairs count as two numbers
Config.MAX_PACKETS_PER_SECOND = 40
Config.MAX_STROKES = 3000
Config.MAX_TOTAL_NUMBERS = 80000

return Config
