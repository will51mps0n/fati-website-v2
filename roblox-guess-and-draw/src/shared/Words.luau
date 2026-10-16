-- Words the drawer can be offered, in three lists. Each turn offers one word from
-- each list, so the choices run easy, medium, hard. Add or remove freely; keep
-- them lowercase (letters, spaces, - and ' only).

return {
	-- Simple things anyone can draw in a few lines.
	easy = {
		"apple", "banana", "pizza", "burger", "ice cream", "cake", "cookie", "donut", "carrot", "cheese",
		"egg", "grapes", "watermelon", "pineapple", "popcorn", "sandwich", "taco", "hot dog", "cupcake", "lemon",
		"cherry", "strawberry", "pear", "corn", "bread", "candy", "lollipop", "pie", "milk", "juice",
		"cat", "dog", "fish", "bird", "horse", "cow", "pig", "sheep", "rabbit", "turtle",
		"snake", "frog", "elephant", "giraffe", "lion", "monkey", "penguin", "shark", "octopus", "spider",
		"butterfly", "bee", "snail", "owl", "duck", "dinosaur", "whale", "crab", "mouse", "ant",
		"house", "castle", "bridge", "tower", "tent", "igloo", "school", "pyramid", "fence", "door",
		"car", "bus", "train", "airplane", "rocket", "boat", "bicycle", "helicopter", "tractor", "truck",
		"sun", "moon", "star", "cloud", "rain", "rainbow", "snowman", "tree", "flower", "mountain",
		"volcano", "island", "beach", "river", "cactus", "mushroom", "leaf", "fire", "lightning", "snowflake",
		"phone", "computer", "television", "camera", "clock", "lamp", "key", "lock", "window", "box",
		"chair", "table", "bed", "toothbrush", "umbrella", "glasses", "hat", "shoe", "sock", "shirt",
		"crown", "ring", "backpack", "scissors", "pencil", "book", "envelope", "gift", "balloon", "kite",
		"guitar", "drum", "piano", "trumpet", "robot", "ghost", "alien", "pirate", "king", "queen",
		"football", "basketball", "baseball", "skateboard", "trophy", "medal", "sword", "shield", "bow", "arrow",
		"heart", "eye", "nose", "hand", "foot", "tooth", "smile", "ear", "mouth", "hair",
		"candle", "bell", "anchor", "map", "treasure", "flag", "ladder", "hammer", "magnet", "bucket",
		"broom", "spoon", "fork", "knife", "cup", "teapot", "bottle", "basket", "bone", "planet",
		"earth", "campfire", "spider web", "snowball", "pumpkin", "bat", "nest", "jellyfish", "ball", "cookie jar",
		"circle", "square", "triangle", "smiley face", "sad face", "dice", "button", "zipper", "pillow", "worm",
	},

	-- Trickier things, actions and famous characters that are fun to draw.
	medium = {
		"lighthouse", "submarine", "astronaut", "mermaid", "unicorn", "dragon", "wizard", "witch", "ninja", "vampire",
		"zombie", "superhero", "clown", "princess", "skeleton", "scarecrow", "snowboard", "surfboard", "roller coaster", "ferris wheel",
		"hot air balloon", "parachute", "windmill", "waterfall", "tornado", "earthquake", "avalanche", "sunset", "fireworks", "thunderstorm",
		"swimming pool", "playground", "slide", "swing", "trampoline", "sandcastle", "treehouse", "haunted house", "spaceship", "ufo",
		"microphone", "headphones", "video game", "remote control", "light bulb", "battery", "toilet", "bathtub", "shower", "fridge",
		"microwave", "washing machine", "vacuum", "calculator", "keyboard", "mailbox", "traffic light", "fire truck", "ambulance", "police car",
		"motorcycle", "skateboarder", "scooter", "canoe", "pirate ship", "train track", "gas station", "parking lot", "bus stop", "zebra crossing",
		"kangaroo", "koala", "panda", "sloth", "hedgehog", "peacock", "flamingo", "seahorse", "starfish", "lobster",
		"hamster", "parrot", "squirrel", "camel", "crocodile", "chameleon", "caterpillar", "ladybug", "dolphin", "polar bear",
		"birthday cake", "spaghetti", "sushi", "pancakes", "french fries", "milkshake", "popsicle", "gingerbread man", "candy cane", "chocolate",
		"juggling", "fishing", "sleeping", "dancing", "swimming", "running", "cooking", "painting", "singing", "sneezing",
		"birthday", "christmas tree", "easter egg", "halloween", "valentine", "graduation", "wedding", "camping", "picnic", "sleepover",
		"mario", "luigi", "pikachu", "spongebob", "patrick star", "minion", "pac-man", "sonic", "kirby", "shrek",
		"olaf", "elsa", "nemo", "mickey mouse", "batman", "spiderman", "superman", "hulk", "iron man", "santa claus",
		"easter bunny", "tooth fairy", "peppa pig", "garfield", "among us", "noob", "creeper", "steve", "yoshi", "dory",
		"crown jewels", "magic wand", "crystal ball", "treasure chest", "message in a bottle", "paper airplane", "sticky note", "piggy bank", "hourglass", "compass",
	},

	-- Hard to draw or hard to guess: ideas, places, films and characters.
	hard = {
		"harry potter", "hermione", "hogwarts", "darth vader", "yoda", "lightsaber", "baby yoda", "stormtrooper", "gandalf", "frodo",
		"sherlock holmes", "dracula", "frankenstein", "mona lisa", "statue of liberty", "eiffel tower", "big ben", "great wall of china", "leaning tower of pisa", "stonehenge",
		"homer simpson", "bart simpson", "scooby-doo", "winnie the pooh", "buzz lightyear", "woody", "lightning mcqueen", "wall-e", "shrek's swamp", "squidward",
		"mr krabs", "plankton", "bowser", "princess peach", "donkey kong", "link", "master chief", "lara croft", "godzilla", "king kong",
		"captain america", "thor", "black panther", "wonder woman", "the joker", "catwoman", "deadpool", "thanos", "groot", "venom",
		"cinderella", "snow white", "rapunzel", "ariel", "simba", "stitch", "pinocchio", "peter pan", "tinker bell", "dumbo",
		"jack-o'-lantern", "bigfoot", "loch ness monster", "grim reaper", "medusa", "cyclops", "minotaur", "phoenix", "kraken", "werewolf",
		"time travel", "gravity", "electricity", "dream", "nightmare", "imagination", "invisible", "echo", "shadow", "reflection",
		"jealousy", "happiness", "boredom", "confusion", "friendship", "homework", "deadline", "wifi", "password", "lag",
		"black hole", "solar system", "northern lights", "eclipse", "meteor shower", "constellation", "galaxy", "astronaut on the moon", "alien invasion", "rocket launch",
		"photosynthesis", "evolution", "volcano eruption", "tsunami", "food chain", "recycling", "global warming", "fossil", "dna", "microscope",
		"rubik's cube", "jigsaw puzzle", "domino effect", "house of cards", "chess", "hopscotch", "tug of war", "hide and seek", "musical chairs", "rock paper scissors",
		"traffic jam", "rush hour", "airport security", "lost luggage", "elevator music", "dentist", "barber", "lifeguard", "zookeeper", "magician",
		"selfie", "photobomb", "influencer", "livestream", "podcast", "emoji", "meme", "screenshot", "voice chat", "loading screen",
		"brain freeze", "sugar rush", "food coma", "bad hair day", "cold feet", "butterflies in stomach", "piece of cake", "raining cats and dogs", "couch potato", "night owl",
	},
}
