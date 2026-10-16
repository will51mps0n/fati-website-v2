-- Shared settings for the server and every client. Tweak the game here.

local Config = {}

-- Match structure ----------------------------------------------------------

-- A match is a batch of rounds. In each round every player draws once.
Config.ROUNDS_PER_MATCH = 3
Config.MIN_PLAYERS = 2

-- Phase lengths, in seconds.
Config.STARTING_TIME = 8 -- countdown before a match begins
Config.CHOOSE_TIME = 15 -- drawer picks a word
Config.DRAW_TIME = 80 -- everyone else guesses
Config.TURN_END_TIME = 6 -- word reveal between turns
Config.MATCH_END_TIME = 12 -- winners screen

Config.WORD_CHOICES = 3

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
Config.BACKGROUND_IMAGE = "rbxassetid://107099391291442" -- your background.jpeg

-- "Fill" shows the picture once, covering the whole screen.
-- "Tile" repeats it and slowly scrolls it. Only use "Tile" with an image that
-- repeats seamlessly, like assets/background-tile.png.
Config.BACKGROUND_STYLE = "Fill"

Config.SOUNDS = {
	click = "", -- assets/sounds/click.ogg
	tick = "", -- assets/sounds/tick.ogg
	correct = "", -- assets/sounds/correct.ogg
	yourTurn = "", -- assets/sounds/your-turn.ogg
	timeUp = "", -- assets/sounds/time-up.ogg
	victory = "", -- assets/sounds/victory.ogg
}

Config.BACKGROUND_TILE_SIZE = 420 -- "Tile" only: on-screen size of one tile, in pixels
Config.BACKGROUND_SCROLL_SPEED = 12 -- "Tile" only: pixels per second; 0 keeps it still
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
