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
	hat: string?,
	scorePrice: number?,
	product: string?,
	pass: string?,
	default: boolean?,
}

type Extra = { hat: string?, scorePrice: number?, product: string?, pass: string?, default: boolean? }

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
		scorePrice = e.scorePrice,
		product = e.product,
		pass = e.pass,
		default = e.default,
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

	-- Zombies
	skin("ClassicZombie", "Classic", "Zombie", "6B8F5A", "4C6B33", "9CCB5A", { default = true }),
	skin("Toxic", "Toxic", "Zombie", "4C7A1F", "6FCF1F", "B6FF3B", { hat = "Spots", scorePrice = 5000 }),
	skin("Frost", "Frost", "Zombie", "3D6F86", "DFF7FF", "8FE3D6", { hat = "Frost", product = "SkinFrost" }),
	skin(
		"Mummy",
		"Mummy",
		"Zombie",
		"CDBF96",
		"E6DCC0",
		"D9CBA3",
		{ hat = "Bandage", product = "SkinMummy" }
	),
	skin("GoldenZombie", "Golden", "Zombie", "8A7A20", "C9A227", "C9D94A", { hat = "Crown", pass = "VIP" }),
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
