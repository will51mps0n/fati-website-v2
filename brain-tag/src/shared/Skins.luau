--!strict
-- Cosmetic skins. Each one recolors the shirt, hair and face and can add a "hat"
-- (built from parts by CharacterLook). Unlock with score, Robux (developer
-- product key in Config.MONETIZATION.Products) or a game pass.

export type Team = "Human" | "Zombie"

export type Skin = {
	id: string,
	name: string,
	team: Team,
	shirt: string, -- body (hex color)
	hair: string, -- top of the head
	skin: string, -- the face crescent (and zombie arms)
	hat: string?, -- costume extras (CharacterLook STYLES or HATS)
	accent: string?, -- extra color some costumes use (ears, beak, plume...)
	scorePrice: number?,
	product: string?,
	pass: string?,
	default: boolean?,
	special: boolean?, -- given by the game (the alpha zombie), never sold or picked
	arms: string?, -- zombie forearms and hands (defaults to `skin`)
}

type Extra = {
	hat: string?,
	accent: string?,
	scorePrice: number?,
	product: string?,
	pass: string?,
	default: boolean?,
	special: boolean?,
	arms: string?,
}

local function skin(
	id: string,
	name: string,
	team: Team,
	shirt: string,
	hair: string,
	face: string,
	extra: Extra?
): Skin
	local e: Extra = extra or {}
	return {
		id = id,
		name = name,
		team = team,
		shirt = shirt,
		hair = hair,
		skin = face,
		hat = e.hat,
		accent = e.accent,
		scorePrice = e.scorePrice,
		product = e.product,
		pass = e.pass,
		default = e.default,
		special = e.special,
		arms = e.arms,
	}
end

local list: { Skin } = {
	-- Humans (Classic matches the original: tan shirt, brown hair, peach face)
	skin("Classic", "Classic", "Human", "C98B52", "A8743F", "F6C79A", { default = true }),
	skin("Chef", "Chef", "Human", "F2F2F2", "A8743F", "F6C79A", { hat = "ChefHat", scorePrice = 3000 }),
	skin("Ninja", "Ninja", "Human", "2E2E34", "1C1C20", "F6C79A", { hat = "Headband", scorePrice = 6000 }),
	skin("Pumpkin", "Pumpkin", "Human", "3F7F3A", "F08A24", "FFC36B", { hat = "Stem", scorePrice = 12000 }),
	skin("Duck", "Duck", "Human", "FFD93B", "FFE36A", "FFF3B0", { hat = "Bill", product = "SkinDuck" }),
	skin(
		"Astronaut",
		"Astronaut",
		"Human",
		"E8ECF2",
		"F7F9FC",
		"9FD8F5",
		{ hat = "Visor", product = "SkinAstronaut" }
	),
	skin("Royal", "Royal", "Human", "7B2CBF", "A8743F", "F6C79A", { hat = "Crown", pass = "VIP" }),
	skin(
		"Dog",
		"Dog",
		"Human",
		"C8955A",
		"B07A45",
		"E8C9A0",
		{ hat = "Dog", accent = "6B4226", product = "SkinDog" }
	),
	skin(
		"Cat",
		"Cat",
		"Human",
		"8E8E93",
		"A5A5AA",
		"F2F2F2",
		{ hat = "Cat", accent = "6E6E73", scorePrice = 8000 }
	),
	skin(
		"Bunny",
		"Bunny",
		"Human",
		"F4F4F4",
		"FFFFFF",
		"FFD6E0",
		{ hat = "Bunny", accent = "FFB3C7", scorePrice = 10000 }
	),
	skin(
		"Bear",
		"Bear",
		"Human",
		"8B5A2B",
		"7A4A22",
		"C8955A",
		{ hat = "Bear", accent = "5A3518", scorePrice = 7000 }
	),
	skin(
		"Panda",
		"Panda",
		"Human",
		"F4F4F4",
		"F4F4F4",
		"F4F4F4",
		{ hat = "Panda", accent = "1C1C1C", product = "SkinPanda" }
	),
	skin(
		"Frog",
		"Frog",
		"Human",
		"4CAF50",
		"5BBF5E",
		"A5D6A7",
		{ hat = "Frog", accent = "2E7D32", scorePrice = 9000 }
	),
	skin(
		"Penguin",
		"Penguin",
		"Human",
		"1C1C24",
		"1C1C24",
		"F4F4F4",
		{ hat = "Penguin", accent = "F39C12", scorePrice = 11000 }
	),
	skin(
		"Robot",
		"Robot",
		"Human",
		"95A5A6",
		"B0BEC5",
		"CFD8DC",
		{ hat = "Robot", accent = "00E5FF", product = "SkinRobot" }
	),
	skin("Pirate", "Pirate", "Human", "C0392B", "5A3A22", "F6C79A", { hat = "Pirate", scorePrice = 15000 }),
	skin(
		"Cowboy",
		"Cowboy",
		"Human",
		"D35400",
		"6B4226",
		"F6C79A",
		{ hat = "Cowboy", accent = "8B5A2B", scorePrice = 14000 }
	),
	skin(
		"Alien",
		"Alien",
		"Human",
		"7F8C8D",
		"8BC34A",
		"AED581",
		{ hat = "Alien", accent = "1C1C1C", product = "SkinAlien" }
	),
	skin(
		"Knight",
		"Knight",
		"Human",
		"7F8C8D",
		"BDC3C7",
		"F6C79A",
		{ hat = "Knight", accent = "C0392B", scorePrice = 20000 }
	),
	skin(
		"Shark",
		"Shark",
		"Human",
		"5D7B93",
		"6E8CA5",
		"F4F4F4",
		{ hat = "Shark", accent = "4A6378", product = "SkinShark" }
	),
	skin(
		"Hotdog",
		"Hot Dog",
		"Human",
		"E0A458",
		"C0532B",
		"F6C79A",
		{ hat = "Hotdog", accent = "F7DC6F", product = "SkinHotdog" }
	),

	skin(
		"Donkey",
		"Donkey",
		"Human",
		"6E625A",
		"5E534C",
		"8C8079",
		{ hat = "Donkey", accent = "3F3631", scorePrice = 9500 }
	),

	-- Zombies: everyone looks the same, except the alpha.
	skin("ClassicZombie", "Classic", "Zombie", "6B8F5A", "4C6B33", "9CCB5A", { default = true }),
	-- The first zombies of each round: orange with red blotches, a gray head
	-- and red arms.
	skin("Alpha", "Alpha Zombie", "Zombie", "E39B4F", "5E5E63", "8A8A90", {
		hat = "Alpha",
		accent = "B8323A",
		arms = "C0453F",
		special = true,
	}),
}

local byId: { [string]: Skin } = {}
for _, skin in list do
	byId[skin.id] = skin
end

local Skins = {
	list = list,
	DEFAULT_HUMAN = "Classic",
	DEFAULT_ZOMBIE = "ClassicZombie",
}

function Skins.get(id: string?): Skin?
	if id == nil then
		return nil
	end
	return byId[id]
end

-- The skin to show for a team, falling back to the default when the chosen
-- one is missing or belongs to the other team.
function Skins.resolve(id: string?, team: Team): Skin
	local skin = Skins.get(id)
	if skin and skin.team == team then
		return skin
	end
	return byId[if team == "Zombie" then Skins.DEFAULT_ZOMBIE else Skins.DEFAULT_HUMAN]
end

function Skins.forTeam(team: Team): { Skin }
	local result = {}
	for _, skin in list do
		if skin.team == team and not skin.special then
			table.insert(result, skin)
		end
	end
	return result
end

return Skins
