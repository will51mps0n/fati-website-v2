--!strict
-- Cosmetic skins. Each one recolors the head and fists and can add a "hat"
-- (built from parts by CharacterLook). Unlock with score, Robux (developer
-- product key in Config.MONETIZATION.Products) or a game pass.

export type Team = "Human" | "Zombie"

export type Skin = {
	id: string,
	name: string,
	team: Team,
	head: string, -- hex color
	fist: string,
	hat: string?,
	scorePrice: number?,
	product: string?,
	pass: string?,
	default: boolean?,
}

local list: { Skin } = {
	-- Humans
	{ id = "Classic", name = "Classic", team = "Human", head = "F2C79A", fist = "E0AE7E", default = true },
	{
		id = "Chef",
		name = "Chef",
		team = "Human",
		head = "F2C79A",
		fist = "FFFFFF",
		hat = "ChefHat",
		scorePrice = 3000,
	},
	{
		id = "Ninja",
		name = "Ninja",
		team = "Human",
		head = "2B2B30",
		fist = "1C1C20",
		hat = "Headband",
		scorePrice = 6000,
	},
	{
		id = "Pumpkin",
		name = "Pumpkin",
		team = "Human",
		head = "F08A24",
		fist = "D9731A",
		hat = "Stem",
		scorePrice = 12000,
	},
	{
		id = "Duck",
		name = "Duck",
		team = "Human",
		head = "FFD93B",
		fist = "FFC21A",
		hat = "Bill",
		product = "SkinDuck",
	},
	{
		id = "Astronaut",
		name = "Astronaut",
		team = "Human",
		head = "F4F6FA",
		fist = "D6DBE4",
		hat = "Visor",
		product = "SkinAstronaut",
	},
	{
		id = "Royal",
		name = "Royal",
		team = "Human",
		head = "F2C79A",
		fist = "E0AE7E",
		hat = "Crown",
		pass = "VIP",
	},

	-- Zombies
	{
		id = "ClassicZombie",
		name = "Classic",
		team = "Zombie",
		head = "7BC043",
		fist = "4F8A2B",
		default = true,
	},
	{
		id = "Toxic",
		name = "Toxic",
		team = "Zombie",
		head = "B6FF3B",
		fist = "6FCF1F",
		hat = "Spots",
		scorePrice = 5000,
	},
	{
		id = "Frost",
		name = "Frost",
		team = "Zombie",
		head = "8FE3D6",
		fist = "4FB3A8",
		hat = "Frost",
		product = "SkinFrost",
	},
	{
		id = "Mummy",
		name = "Mummy",
		team = "Zombie",
		head = "D9CBA3",
		fist = "B8A77C",
		hat = "Bandage",
		product = "SkinMummy",
	},
	{
		id = "GoldenZombie",
		name = "Golden",
		team = "Zombie",
		head = "C9D94A",
		fist = "A3B336",
		hat = "Crown",
		pass = "VIP",
	},
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
		if skin.team == team then
			table.insert(result, skin)
		end
	end
	return result
end

return Skins
