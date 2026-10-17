--!strict
-- Item definitions. Prices are in score. Weapons never kill: they shove
-- (knockback, studs per second at the start of the shove) and briefly stun.

export type ItemKind = "Melee" | "Projectile" | "Blast" | "Consumable" | "Passive"

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

-- Display order in the shops.
local SHOP_ORDER = { "Stick", "Pill", "Bat", "Drumstick", "PotatoGun", "Swordfish", "Spear", "Shotgun" }
local WIZARD_ORDER = { "GoldenDrumstick", "RarePotatoGun", "AncientSpear" }

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
