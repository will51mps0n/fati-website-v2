--[[
	Config  (ModuleScript)
	Put in: ReplicatedStorage   — name it exactly "Config"

	All the game's settings live here. Change these numbers to tune the game.
]]

local Config = {}

-- Players needed before a game starts. Telestrations is best with 4+,
-- but 2 lets you test with a friend (or with Studio's local server).
Config.MIN_PLAYERS = 2

-- Max number of pages per sketchbook. With N players each book gets
-- min(N, MAX_STEPS) pages, so everyone touches every book once (up to this cap).
Config.MAX_STEPS = 10

-- Timers (seconds)
Config.INTERMISSION_TIME = 20 -- lobby countdown once enough players are in
Config.DRAW_TIME = 60
Config.GUESS_TIME = 25
Config.REVEAL_PAGE_TIME = 5 -- how long each drawing / guess stays up in the reveal
Config.REVEAL_SUMMARY_TIME = 4 -- "CAT became DOG!" at the end of each book
Config.RESULTS_TIME = 8 -- "Thanks for playing" before going back to the lobby

-- Guess length limit (characters)
Config.MAX_GUESS_LENGTH = 50

-- Drawing limits (keeps network traffic small and stops abuse)
Config.MAX_POINTS_PER_STROKE = 400
Config.MAX_POINTS_PER_DRAWING = 4000
Config.MAX_STROKES = 300

-- Canvas shape (width / height)
Config.CANVAS_ASPECT = 4 / 3

-- Palette. White doubles as an eraser.
Config.COLORS = {
	Color3.fromRGB(20, 20, 20), -- black
	Color3.fromRGB(255, 255, 255), -- white / eraser
	Color3.fromRGB(130, 130, 130), -- gray
	Color3.fromRGB(225, 50, 50), -- red
	Color3.fromRGB(255, 140, 30), -- orange
	Color3.fromRGB(255, 215, 0), -- yellow
	Color3.fromRGB(60, 180, 75), -- green
	Color3.fromRGB(40, 110, 230), -- blue
	Color3.fromRGB(140, 70, 200), -- purple
	Color3.fromRGB(255, 120, 190), -- pink
	Color3.fromRGB(130, 80, 40), -- brown
}

-- Brush thickness, in thousandths of the canvas width (small, medium, large)
Config.BRUSH_SIZES = { 5, 12, 28 }

-- Starting words. Add as many as you like!
Config.WORDS = {
	"Cat", "Dog", "Pizza", "Rocket", "Dinosaur", "Snowman", "Castle", "Robot",
	"Volcano", "Mermaid", "Ghost", "Rainbow", "Spaghetti", "Octopus", "Vampire",
	"Sandcastle", "Hot Air Balloon", "Penguin", "Treasure Map", "Dragon",
	"Haunted House", "Unicorn", "Lighthouse", "Cupcake", "Alien", "Pirate",
	"Tornado", "Skateboard", "Waterfall", "Wizard", "Jellyfish", "Banana",
	"Campfire", "Superhero", "Roller Coaster", "Igloo", "Cactus", "Ninja",
	"Shark", "Birthday Cake", "Snail", "Bee", "Mummy", "Telescope", "Pyramid",
	"Giraffe", "Popcorn", "Scarecrow", "Fireworks", "Moon", "Sunflower",
	"Spider Web", "Toaster", "Bathtub", "Zombie", "Kangaroo", "Hamburger",
	"Ice Cream", "Bicycle", "Clown", "Butterfly", "Train", "Owl",
	"Tooth Fairy", "Bowling", "Treehouse", "Sneeze", "Sleepwalking", "Magnet",
	"Sea Monster", "Lawn Mower", "Pillow Fight", "Cowboy", "Ladder", "Frog",
	"Hammock", "Traffic Jam", "Lemonade", "Snowball Fight", "Crown", "Bat",
}

return Config
