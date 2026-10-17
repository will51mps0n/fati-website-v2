--!strict
-- Item definitions. Prices are in score. Weapons never kill: they shove
-- (knockback, studs per second at the start of the shove) and briefly stun.

export type ItemKind =
	"Melee" -- click to swing
	| "Projectile" -- click to fire one shot
	| "Blast" -- click for a cone blast
	| "Stream" -- hold to spray (water gun, leaf blower)
	| "Trap" -- click to drop a trap at your feet
	| "Consumable" -- click to use up
	| "Passive" -- just hold it

export type Item = {
	id: string,
	name: string,
	kind: ItemKind,
	description: string,
	price: number?, -- sold in the main shop (B) for this much score
	wizardPrice: number?, -- sold by the wizard for this much score
	robuxProduct: string?, -- Config.MONETIZATION.Products key that grants it
	rare: string?, -- id rolled instead on purchase (Config.RARE_CHANCE)
	isRare: boolean?,
	groundWeight: number?, -- relative chance to be scattered on the map
	reach: number?,
	arc: number?, -- degrees
	knockback: number?,
	stun: number?,
	cooldown: number?,
	straight: boolean?, -- shove along the aim line instead of away from you
	dragsFurniture: boolean?,
	breaksWalls: boolean?,
	projectileSpeed: number?,
	projectileRange: number?,
	projectileRadius: number?,
	immunity: number?,
	rewardBonus: number?,
	-- Fun extras (see ItemService and the client's Effects):
	sound: string?, -- sound style played on use
	fx: string?, -- little visual on hit or use
	effect: string?, -- "Freeze" | "Bubble" | "Explode" | "Plunge" | "Slip"
	projectile: string?, -- projectile look: "Potato" | "Pebble" | "Snowball" | "Bubble" | "Duck"
	slowFactor: number?, -- Freeze: speed multiplier while frozen
	effectSeconds: number?, -- how long Freeze/Bubble/Plunge lasts
	radius: number?, -- Explode: blast radius
	tick: number?, -- Stream: seconds between pushes while held
	charges: number?, -- Trap: how many you can drop
	speedBoost: number?, -- Consumable: speed multiplier
	boostSeconds: number?,
}

local Items: { [string]: Item } = {}

local function add(item: Item)
	Items[item.id] = item
end

add({
	id = "Stick",
	name = "Stick",
	kind = "Melee",
	description = "Cheap and short. Shoves zombies a little. Push furniture with it, or hold click to hook and drag.",
	price = 100,
	groundWeight = 40,
	reach = 5,
	arc = 110,
	knockback = 40,
	stun = 0.25,
	cooldown = 0.6,
})

add({
	id = "Bat",
	name = "Bat",
	kind = "Melee",
	description = "The classic. A short swing with solid knockback.",
	price = 750,
	robuxProduct = "InstantBat",
	groundWeight = 25,
	reach = 6,
	arc = 100,
	knockback = 60,
	stun = 0.4,
	cooldown = 0.8,
})

add({
	id = "Swordfish",
	name = "Swordfish",
	kind = "Melee",
	description = "Long reach. Hooks and drags furniture harder than any other weapon (hold click).",
	price = 2500,
	groundWeight = 4,
	reach = 8,
	arc = 60,
	knockback = 80,
	stun = 0.6,
	cooldown = 0.9,
	dragsFurniture = true,
})

add({
	id = "Spear",
	name = "Spear",
	kind = "Melee",
	description = "Longest reach. Pushes zombies straight away from you.",
	price = 3500,
	robuxProduct = "InstantSpear",
	rare = "AncientSpear",
	reach = 10,
	arc = 30,
	knockback = 90,
	stun = 0.5,
	cooldown = 1.0,
	straight = true,
})

add({
	id = "AncientSpear",
	name = "Rare Ancient Spear",
	kind = "Melee",
	description = "A golden spear. A little longer and a little stronger.",
	wizardPrice = 7000,
	isRare = true,
	reach = 11,
	arc = 32,
	knockback = 110,
	stun = 0.6,
	cooldown = 0.95,
	straight = true,
})

add({
	id = "PotatoGun",
	name = "Potato Gun",
	kind = "Projectile",
	description = "Fires potatoes that knock zombies back.",
	price = 1500,
	rare = "RarePotatoGun",
	groundWeight = 10,
	knockback = 55,
	stun = 0.3,
	cooldown = 1.0,
	projectileSpeed = 90,
	projectileRange = 110,
	projectileRadius = 0.6,
	projectile = "Potato",
})

add({
	id = "RarePotatoGun",
	name = "Rare Potato Gun",
	kind = "Projectile",
	description = "The old, stronger potatoes. Bigger and meaner.",
	wizardPrice = 4000,
	isRare = true,
	knockback = 85,
	stun = 0.45,
	cooldown = 0.9,
	projectileSpeed = 100,
	projectileRange = 120,
	projectileRadius = 0.9,
	projectile = "Potato",
})

add({
	id = "Shotgun",
	name = "Shotgun",
	kind = "Blast",
	description = "Huge cone blast. Also blows a hole in the wall in front of you.",
	price = 10000,
	robuxProduct = "InstantShotgun",
	reach = 14,
	arc = 50,
	knockback = 130,
	stun = 0.8,
	cooldown = 3,
	breaksWalls = true,
})

add({
	id = "Pill",
	name = "Pill",
	kind = "Consumable",
	description = "Click to swallow: +25 immunity, so you are less likely to start as a zombie.",
	price = 300,
	groundWeight = 15,
	immunity = 25,
	cooldown = 0.5,
})

add({
	id = "Drumstick",
	name = "Drumstick",
	kind = "Passive",
	description = "Hold it when the round ends for +40% score.",
	price = 1000,
	rare = "GoldenDrumstick",
	groundWeight = 6,
	rewardBonus = 0.4,
})

add({
	id = "GoldenDrumstick",
	name = "Golden Drumstick",
	kind = "Passive",
	description = "Hold it when the round ends for +80% score.",
	wizardPrice = 3000,
	isRare = true,
	rewardBonus = 0.8,
})

-- Funny weapons ----------------------------------------------------------------------

add({
	id = "RubberChicken",
	name = "Rubber Chicken",
	kind = "Melee",
	description = "SQUEAK. Barely pushes, but zombies are dazed for ages.",
	price = 400,
	groundWeight = 12,
	reach = 5,
	arc = 120,
	knockback = 30,
	stun = 0.9,
	cooldown = 0.5,
	sound = "Squeak",
	fx = "Feathers",
})

add({
	id = "PoolNoodle",
	name = "Pool Noodle",
	kind = "Melee",
	description = "Huge, floppy and fast. Swats everything in front of you.",
	price = 600,
	groundWeight = 10,
	reach = 7,
	arc = 160,
	knockback = 35,
	stun = 0.2,
	cooldown = 0.35,
	sound = "Swish",
})

add({
	id = "Baguette",
	name = "Baguette",
	kind = "Melee",
	description = "Long, crusty, surprisingly effective. Leaves crumbs.",
	price = 900,
	groundWeight = 10,
	reach = 6.5,
	arc = 90,
	knockback = 55,
	stun = 0.35,
	cooldown = 0.7,
	fx = "Crumbs",
})

add({
	id = "FryingPan",
	name = "Frying Pan",
	kind = "Melee",
	description = "CLANG! Big knockback and a good long daze. Egg included.",
	price = 1200,
	rare = "GoldenPan",
	groundWeight = 6,
	reach = 5,
	arc = 110,
	knockback = 75,
	stun = 0.7,
	cooldown = 0.9,
	sound = "Clang",
	fx = "Stars",
})

add({
	id = "GoldenPan",
	name = "Golden Frying Pan",
	kind = "Melee",
	description = "The legendary pan. CLANG, but louder.",
	wizardPrice = 5000,
	isRare = true,
	reach = 5.5,
	arc = 120,
	knockback = 115,
	stun = 0.9,
	cooldown = 0.8,
	sound = "Clang",
	fx = "Stars",
})

add({
	id = "Crowbar",
	name = "Crowbar",
	kind = "Melee",
	description = "Pries furniture loose: hooks and drags it harder than anything.",
	price = 1600,
	reach = 6,
	arc = 80,
	knockback = 60,
	stun = 0.4,
	cooldown = 0.7,
	dragsFurniture = true,
})

add({
	id = "Plunger",
	name = "Plunger",
	kind = "Melee",
	description = "Thwop! Sticks to a zombie's face and freezes them in place.",
	price = 1800,
	reach = 7,
	arc = 45,
	knockback = 15,
	stun = 1.5,
	cooldown = 1.3,
	effect = "Plunge",
	effectSeconds = 1.5,
	sound = "Pop",
})

add({
	id = "Lollipop",
	name = "Giant Lollipop",
	kind = "Melee",
	description = "A sweet, wide swing with real weight behind it.",
	price = 2000,
	reach = 7,
	arc = 120,
	knockback = 70,
	stun = 0.4,
	cooldown = 0.8,
	fx = "Sparkle",
})

add({
	id = "Katana",
	name = "Katana",
	kind = "Melee",
	description = "Lightning-fast swings with a long reach.",
	price = 4000,
	reach = 8,
	arc = 70,
	knockback = 70,
	stun = 0.3,
	cooldown = 0.4,
})

add({
	id = "InflatableHammer",
	name = "Inflatable Hammer",
	kind = "Melee",
	description = "BOING! Sends zombies flying across the room.",
	wizardPrice = 6000,
	isRare = true,
	reach = 7,
	arc = 120,
	knockback = 160,
	stun = 0.6,
	cooldown = 1.4,
	sound = "Boing",
	fx = "Stars",
})

add({
	id = "Slingshot",
	name = "Slingshot",
	kind = "Projectile",
	description = "Fast little pebbles. Quick to reload.",
	price = 800,
	groundWeight = 6,
	knockback = 40,
	stun = 0.25,
	cooldown = 0.6,
	projectile = "Pebble",
	projectileSpeed = 140,
	projectileRange = 100,
	projectileRadius = 0.4,
	sound = "Twang",
})

add({
	id = "WaterGun",
	name = "Water Gun",
	kind = "Stream",
	description = "Hold to spray. Keeps zombies pushed back while you have water.",
	price = 1200,
	groundWeight = 5,
	reach = 16,
	arc = 24,
	knockback = 16,
	stun = 0.1,
	tick = 0.12,
	fx = "Water",
})

add({
	id = "SnowballLauncher",
	name = "Snowball Launcher",
	kind = "Projectile",
	description = "Snowballs freeze zombies: they slow to a crawl for a few seconds.",
	price = 3000,
	knockback = 20,
	stun = 0.2,
	cooldown = 1.1,
	projectile = "Snowball",
	projectileSpeed = 85,
	projectileRange = 110,
	projectileRadius = 0.8,
	effect = "Freeze",
	slowFactor = 0.4,
	effectSeconds = 2.5,
})

add({
	id = "BubbleGun",
	name = "Bubble Gun",
	kind = "Projectile",
	description = "Traps a zombie in a giant bubble. They can't move until it pops.",
	price = 5000,
	knockback = 0,
	stun = 2,
	cooldown = 2.2,
	projectile = "Bubble",
	projectileSpeed = 45,
	projectileRange = 70,
	projectileRadius = 1.2,
	effect = "Bubble",
	effectSeconds = 2,
	sound = "Pop",
})

add({
	id = "ConfettiCannon",
	name = "Confetti Cannon",
	kind = "Blast",
	description = "A party in a tube. Blasts zombies back in a shower of confetti.",
	price = 4500,
	reach = 12,
	arc = 70,
	knockback = 95,
	stun = 0.5,
	cooldown = 2.2,
	fx = "Confetti",
	sound = "Pop",
})

add({
	id = "LeafBlower",
	name = "Leaf Blower",
	kind = "Stream",
	description = "Hold to blow zombies (and light furniture) away in a wide cone.",
	price = 7000,
	reach = 14,
	arc = 40,
	knockback = 24,
	stun = 0.1,
	tick = 0.1,
	fx = "Leaves",
})

add({
	id = "DuckLauncher",
	name = "Duck Launcher",
	kind = "Projectile",
	description = "Fires a rubber duck that explodes and knocks back every zombie nearby.",
	price = 9000,
	knockback = 110,
	stun = 0.6,
	cooldown = 3.5,
	projectile = "Duck",
	projectileSpeed = 70,
	projectileRange = 90,
	projectileRadius = 0.9,
	effect = "Explode",
	radius = 10,
	sound = "Squeak",
})

add({
	id = "BananaPeel",
	name = "Banana Peels",
	kind = "Trap",
	description = "Click to drop a peel. Zombies that step on it slip and spin out. 3 peels.",
	price = 700,
	groundWeight = 6,
	cooldown = 0.6,
	charges = 3,
	knockback = 45,
	stun = 1.2,
	effect = "Slip",
})

add({
	id = "EnergyDrink",
	name = "Energy Drink",
	kind = "Consumable",
	description = "Click to chug: 35% faster for 8 seconds.",
	price = 500,
	groundWeight = 8,
	cooldown = 0.5,
	speedBoost = 1.35,
	boostSeconds = 8,
})

-- Display order in the shops.
local SHOP_ORDER = {
	"Stick",
	"Pill",
	"RubberChicken",
	"EnergyDrink",
	"PoolNoodle",
	"BananaPeel",
	"Bat",
	"Slingshot",
	"Baguette",
	"Drumstick",
	"FryingPan",
	"WaterGun",
	"PotatoGun",
	"Crowbar",
	"Plunger",
	"Lollipop",
	"Swordfish",
	"SnowballLauncher",
	"Spear",
	"Katana",
	"ConfettiCannon",
	"BubbleGun",
	"LeafBlower",
	"DuckLauncher",
	"Shotgun",
}
local WIZARD_ORDER = { "GoldenDrumstick", "RarePotatoGun", "GoldenPan", "AncientSpear", "InflatableHammer" }

local module = {
	all = Items,
	shopOrder = SHOP_ORDER,
	wizardOrder = WIZARD_ORDER,
}

function module.get(id: string?): Item?
	if id == nil then
		return nil
	end
	return Items[id]
end

-- Items that can be scattered on the ground, as { id, weight } pairs.
function module.groundTable(): { { id: string, weight: number } }
	local list = {}
	for id, item in Items do
		if item.groundWeight and item.groundWeight > 0 then
			table.insert(list, { id = id, weight = item.groundWeight })
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

return module
