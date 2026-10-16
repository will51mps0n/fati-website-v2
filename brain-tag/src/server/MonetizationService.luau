-- Robux purchases: game passes (permanent perks) and developer products
-- (one-off items, boosts and skins). Ids live in Config.MONETIZATION; any id
-- left at 0 is simply ignored.
--
-- ProcessReceipt follows Roblox's recommended pattern: a purchase is granted
-- once, recorded in the buyer's saved profile by its PurchaseId, and only
-- reported as granted after that profile is saved. If anything fails, Roblox
-- retries later and the receipt log prevents a double grant.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Announcer = require(script.Parent.Announcer)
local CharacterService = require(script.Parent.CharacterService)
local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local ItemService = require(script.Parent.ItemService)
local Participants = require(script.Parent.Participants)
local Skins = require(ReplicatedStorage.Shared.Skins)
local ShopService = require(script.Parent.ShopService)

type Participant = Participants.Participant

local MonetizationService = {}

local money = Config.MONETIZATION

local function keyFor(map: { [string]: number }, id: number): string?
	for key, value in map do
		if value ~= 0 and value == id then
			return key
		end
	end
	return nil
end

-- Game passes ----------------------------------------------------------------------

-- Which configured passes this player owns (yields; call before spawning).
function MonetizationService.ownedPasses(player: Player): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	for key, id in money.GamePasses do
		if id ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			if ok and has then
				owned[key :: string] = true
			end
		end
	end
	return owned
end

local function applyPasses(p: Participant)
	-- Pass skins unlock automatically.
	for _, skin in Skins.list do
		if skin.pass and p.passes[skin.pass] then
			ShopService.grantSkin(p, skin.id)
		end
	end
	Participants.publish(p)
	CharacterService.refreshNameTag(p)
end

function MonetizationService.applyPasses(p: Participant)
	applyPasses(p)
end

-- Developer products -----------------------------------------------------------------

local function giveOrQueue(p: Participant, itemId: string)
	if p.team == "Human" and Participants.body(p) then
		ItemService.give(p, itemId)
		if p.player then
			Announcer.toast(p.player, "Delivered! Check your hand.", Config.COLORS.Good)
		end
	elseif p.profile then
		table.insert(p.profile.PendingItems, itemId)
		if p.player then
			Announcer.toast(p.player, "Saved for you: you'll get it next round.", Config.COLORS.Good)
		end
	end
end

type Handler = (p: Participant) -> ()

local HANDLERS: { [string]: Handler } = {
	InstantBat = function(p)
		giveOrQueue(p, "Bat")
	end,
	InstantSpear = function(p)
		giveOrQueue(p, "Spear")
	end,
	InstantShotgun = function(p)
		giveOrQueue(p, "Shotgun")
	end,
	ImmunityShot = function(p)
		Participants.setImmunity(p, p.immunity + money.IMMUNITY_SHOT_AMOUNT)
		if p.player then
			Announcer.toast(p.player, "Immunity boosted!", Config.COLORS.Good)
		end
	end,
	ScoreBoost30 = function(p)
		local now = os.time()
		p.boostEndsAt = math.max(now, p.boostEndsAt) + money.SCORE_BOOST_SECONDS
		if p.profile then
			p.profile.BoostEndsAt = p.boostEndsAt
		end
		p.state:SetAttribute("BoostEndsAt", p.boostEndsAt)
		if p.player then
			Announcer.toast(p.player, "2x score is active!", Config.COLORS.Good)
		end
	end,
}

-- Every skin sold as a product gets a handler that unlocks and equips it.
for _, skin in Skins.list do
	if skin.product then
		HANDLERS[skin.product] = function(p)
			ShopService.grantSkin(p, skin.id)
			ShopService.equipSkin(p, skin)
			if p.player then
				Announcer.toast(p.player, "Unlocked " .. skin.name .. "!", Config.COLORS.Good)
			end
		end
	end
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retried when they rejoin
	end
	local p = Participants.fromPlayer(player)
	local profile = DataService.get(player)
	if not p or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = keyFor(money.Products, receipt.ProductId)
	local handler = key and HANDLERS[key]
	if not handler then
		warn(
			"[Shop] Unknown product id "
				.. tostring(receipt.ProductId)
				.. "; add it to Config.MONETIZATION.Products"
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receiptId = tostring(receipt.PurchaseId)
	if not profile.Receipts[receiptId] then
		local ok, err = pcall(function()
			(handler :: Handler)(p)
			return true
		end)
		if not ok then
			warn("[Shop] Grant failed: " .. tostring(err))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		profile.Receipts[receiptId] = os.time()
	end

	if DataService.isSaved(player) then
		if DataService.save(player) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Studio test purchases are free; with saving off, grant for this session.
	if RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationService.init()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local key = keyFor(money.GamePasses, passId)
		local p = Participants.fromPlayer(player)
		if key and p then
			p.passes[key] = true
			applyPasses(p)
			Announcer.toast(player, "Thanks! Your pass is active.", Config.COLORS.Good)
		end
	end)
end

return MonetizationService
