-- Score shop (B), the wizard's shop, skins and the first-join tutorial flag.
-- Clients only ask; every price, distance and balance is checked here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Announcer = require(script.Parent.Announcer)
local CharacterService = require(script.Parent.CharacterService)
local Config = require(ReplicatedStorage.Shared.Config)
local ItemService = require(script.Parent.ItemService)
local Items = require(ReplicatedStorage.Shared.Items)
local Participants = require(script.Parent.Participants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Util = require(ReplicatedStorage.Shared.Util)
local Wizard = require(script.Parent.Wizard)

type Participant = Participants.Participant

local ShopService = {}

local rng = Random.new()

function ShopService.rareChance(p: Participant): number
	if p.passes.Lucky then
		return Config.MONETIZATION.LUCKY_RARE_CHANCE
	end
	return Config.RARE_CHANCE
end

local function buyItem(player: Player, itemId: unknown, fromWizard: unknown): (boolean, string)
	if typeof(itemId) ~= "string" then
		return false, "Unknown item"
	end
	local p = Participants.fromPlayer(player)
	local item = Items.get(itemId)
	if not p or not item then
		return false, "Unknown item"
	end
	if p.team ~= "Human" then
		return false, "Zombies can't shop!"
	end
	local root = Participants.body(p)
	if not root then
		return false, "Wait until you spawn"
	end

	local price: number
	if fromWizard == true then
		if not item.wizardPrice then
			return false, "The wizard doesn't sell that"
		end
		if not Wizard.isNear(root.Position) then
			return false, "Walk closer to the wizard"
		end
		price = item.wizardPrice
	else
		if not item.price then
			return false, "That isn't sold here"
		end
		price = item.price
	end
	if p.score < price then
		return false, "You need " .. Util.commas(price) .. " score"
	end

	Participants.addScore(p, -price)
	CharacterService.refreshSpeed(p)

	local finalId = item.id
	if item.rare and rng:NextNumber() < ShopService.rareChance(p) then
		finalId = item.rare
	end
	ItemService.give(p, finalId)
	local final = Items.get(finalId) :: Items.Item
	if finalId ~= item.id then
		Announcer.chat(string.format("* %s rolled a %s! *", p.name, final.name), "F5C542")
		return true, "RARE! You got a " .. final.name .. "!"
	end
	return true, "Bought " .. final.name
end

-- Marks a skin owned (in the session and the saved profile).
function ShopService.grantSkin(p: Participant, skinId: string)
	p.ownedSkins[skinId] = true
	if p.profile then
		p.profile.OwnedSkins[skinId] = true
	end
	Participants.publish(p)
end

function ShopService.equipSkin(p: Participant, skin: Skins.Skin)
	if skin.team == "Zombie" then
		p.zombieSkin = skin.id
		if p.profile then
			p.profile.ZombieSkin = skin.id
		end
	else
		p.humanSkin = skin.id
		if p.profile then
			p.profile.HumanSkin = skin.id
		end
	end
	Participants.publish(p)
	if p.team == skin.team then
		CharacterService.applyLook(p)
		ItemService.refreshHand(p)
	end
end

-- Returns a status the client acts on:
--   "equipped" | "bought" | "prompt" (Robux product) | "promptPass" | "error"
local function buySkin(player: Player, skinId: unknown): (string, string)
	if typeof(skinId) ~= "string" then
		return "error", "Unknown skin"
	end
	local p = Participants.fromPlayer(player)
	local skin = Skins.get(skinId)
	if not p or not skin then
		return "error", "Unknown skin"
	end
	if skin.pass and p.passes[skin.pass] then
		ShopService.grantSkin(p, skin.id)
	end
	if p.ownedSkins[skin.id] then
		ShopService.equipSkin(p, skin)
		return "equipped", skin.name .. " equipped"
	end
	if skin.scorePrice then
		if p.score < skin.scorePrice then
			return "error", "You need " .. Util.commas(skin.scorePrice) .. " score"
		end
		Participants.addScore(p, -skin.scorePrice)
		CharacterService.refreshSpeed(p)
		ShopService.grantSkin(p, skin.id)
		ShopService.equipSkin(p, skin)
		return "bought", "Unlocked " .. skin.name .. "!"
	end
	if skin.product then
		return "prompt", skin.product
	end
	if skin.pass then
		return "promptPass", skin.pass
	end
	return "error", "Not available"
end

function ShopService.init()
	Remotes.func("BuyItem").OnServerInvoke = buyItem
	Remotes.func("BuySkin").OnServerInvoke = buySkin
	Remotes.event("TutorialDone").OnServerEvent:Connect(function(player)
		local p = Participants.fromPlayer(player)
		if p and p.profile then
			p.profile.SeenTutorial = true
			p.state:SetAttribute("SeenTutorial", true)
		end
	end)
end

return ShopService
