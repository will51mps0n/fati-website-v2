-- The shop window. Tabs: Items (spend score), Skins (score, Robux or VIP) and
-- Robux (game passes and developer products). Opened next to the wizard, it
-- shows his rare stock instead. The server validates every purchase.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterLook = require(ReplicatedStorage.Shared.CharacterLook)
local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local ItemModels = require(ReplicatedStorage.Shared.ItemModels)
local Items = require(ReplicatedStorage.Shared.Items)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Sounds = require(script.Parent.Parent.Sounds)
local UIKit = require(script.Parent.UIKit)
local Util = require(ReplicatedStorage.Shared.Util)

type Mode = "Items" | "Wizard" | "Skins" | "Robux"

-- Filled in by build().
local ShopPanel = {
	open = function(_mode: Mode) end,
	close = function() end,
	isOpen = function(): boolean
		return false
	end,
	update = function() end,
	mode = function(): Mode
		return "Items"
	end,
}

local player = Players.LocalPlayer
local money = Config.MONETIZATION
local buyItemRemote = Remotes.func("BuyItem")
local buySkinRemote = Remotes.func("BuySkin")

local PASSES = {
	{
		key = "VIP",
		name = "VIP",
		description = "Gold name and [VIP] chat tag, +20% score, VIP skins.",
		preview = "skin:Royal",
	},
	{
		key = "DoubleScore",
		name = "Double Score",
		description = "+100% score from every reward. Forever.",
		preview = "item:GoldenDrumstick",
	},
	{
		key = "StarterKit",
		name = "Starter Kit",
		description = "Start every round holding a Bat.",
		preview = "item:Bat",
	},
	{
		key = "Lucky",
		name = "Lucky",
		description = "Rare roll chance 5% -> 15% on every purchase.",
		preview = "item:RarePotatoGun",
	},
}

local PRODUCTS = {
	{
		key = "InstantAncientSpear",
		name = "Ancient Spear",
		description = "Super rare. The only weapon that strikes.",
		preview = "item:AncientSpear",
	},
	{
		key = "InstantBat",
		name = "Instant Bat",
		description = "A Bat in your hand right now.",
		preview = "item:Bat",
	},
	{
		key = "InstantSpear",
		name = "Instant Spear",
		description = "A Spear in your hand right now.",
		preview = "item:Spear",
	},
	{
		key = "InstantShotgun",
		name = "Instant Shotgun",
		description = "The big one. Right now.",
		preview = "item:Shotgun",
	},
	{
		key = "ImmunityShot",
		name = "Immunity Shot",
		description = "+50 immunity right now.",
		preview = "item:Pill",
	},
	{
		key = "ScoreBoost30",
		name = "2x Score, 30 min",
		description = "Double every reward for 30 minutes. Stacks.",
		preview = "item:Drumstick",
	},
}

local prices: { [string]: number } = {}

local function fetchPrice(kind: "Product" | "GamePass", id: number, onDone: () -> ())
	local cacheKey = kind .. id
	if prices[cacheKey] or id == 0 then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(
				id,
				if kind == "GamePass" then Enum.InfoType.GamePass else Enum.InfoType.Product
			)
		end)
		if ok and info and typeof(info.PriceInRobux) == "number" then
			prices[cacheKey] = info.PriceInRobux
			onDone()
		end
	end)
end

local function priceText(kind: "Product" | "GamePass", id: number): string
	local price = prices[kind .. id]
	return if price then "R$ " .. price else "Robux"
end

local function buildPreview(spec: string): Model?
	local kind, id = string.match(spec, "^(%a+):(%w+)$")
	if kind == "item" and id then
		return ItemModels.build(id)
	elseif kind == "skin" and id then
		local skin = Skins.get(id)
		if skin then
			return CharacterLook.preview(skin.id, skin.team)
		end
	end
	return nil
end

function ShopPanel.build(parent: Instance, toast: (string, string?) -> ())
	local mode: Mode = "Items"
	local render: () -> ()

	local window, content, heading = UIKit.modal(parent, "Shop", 780, 520, function()
		ShopPanel.close()
	end)

	local scoreLabel = UIKit.label({
		Name = "Score",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -54, 0, 12),
		Size = UDim2.fromOffset(220, 28),
		TextSize = 18,
		TextColor3 = UIKit.GOLD,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 22,
		Parent = window,
	})

	local tabBar = UIKit.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 21,
		Parent = content,
	}, { UIKit.list(Enum.FillDirection.Horizontal, 8) })

	local body = UIKit.new("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 1, -42),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 21,
		Parent = content,
	})

	local tabButtons: { [string]: TextButton } = {}
	local function tab(name: string, order: number, onClick: () -> ()): TextButton
		local button = UIKit.button({
			Name = name,
			Text = name,
			LayoutOrder = order,
			Size = UDim2.fromOffset(104, 32),
			TextSize = 17,
			ZIndex = 22,
			Parent = tabBar,
		}, onClick)
		tabButtons[name] = button
		return button
	end
	for i, name in { "Items", "Skins", "Robux" } do
		tab(name, i, function()
			mode = name :: Mode
			render()
		end)
	end

	local function clearBody()
		for _, child in body:GetChildren() do
			child:Destroy()
		end
		UIKit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(168, 222),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = body,
		})
	end

	type CardSpec = {
		order: number,
		title: string,
		price: string,
		priceColor: Color3?,
		description: string,
		preview: Model?,
		button: string,
		buttonColor: Color3?,
		enabled: boolean,
		onClick: (() -> ())?,
	}

	local function card(spec: CardSpec)
		local frame = UIKit.new("Frame", {
			LayoutOrder = spec.order,
			BackgroundColor3 = Color3.fromRGB(44, 46, 52),
			BorderSizePixel = 0,
			ZIndex = 22,
			Parent = body,
		}, { UIKit.corner(10) })
		local previewBox = UIKit.new("Frame", {
			Name = "Preview",
			BackgroundColor3 = Color3.fromRGB(60, 63, 70),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 0, 86),
			ZIndex = 22,
			Parent = frame,
		}, { UIKit.corner(8) })
		if spec.preview then
			-- Skins (CharacterLook previews) are shown from above, like in game.
			UIKit.viewport(previewBox, spec.preview, { ZIndex = 23 }, spec.preview.Name == "Preview")
		end
		UIKit.label({
			Position = UDim2.fromOffset(10, 98),
			Size = UDim2.new(1, -20, 0, 20),
			Text = spec.title,
			TextSize = 17,
			Font = UIKit.HEAVY,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 23,
			Parent = frame,
		})
		UIKit.label({
			Position = UDim2.fromOffset(10, 118),
			Size = UDim2.new(1, -20, 0, 16),
			Text = spec.price,
			TextSize = 15,
			TextColor3 = spec.priceColor or UIKit.GOLD,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 23,
			Parent = frame,
		})
		UIKit.label({
			Position = UDim2.fromOffset(10, 136),
			Size = UDim2.new(1, -20, 0, 42),
			Text = spec.description,
			TextSize = 13,
			Font = UIKit.FONT,
			TextColor3 = UIKit.MUTED,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 23,
			Parent = frame,
		})
		UIKit.button({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -16, 0, 32),
			Text = spec.button,
			TextSize = 16,
			BackgroundColor3 = if spec.enabled
				then (spec.buttonColor or UIKit.GOOD)
				else Color3.fromRGB(80, 82, 88),
			AutoButtonColor = spec.enabled,
			ZIndex = 23,
			Parent = frame,
		}, function()
			if spec.enabled and spec.onClick then
				spec.onClick()
			end
		end)
	end

	local function renderItems(fromWizard: boolean)
		local score = ClientState.my("Score") or 0
		local order: { string } = if fromWizard then Items.wizardOrder else Items.shopOrder
		for i, id in order do
			local item = Items.get(id) :: Items.Item
			local price = (if fromWizard then item.wizardPrice else item.price) or 0
			local affordable = score >= price
			card({
				order = i,
				title = item.name,
				price = Util.commas(price) .. " score",
				priceColor = if affordable then UIKit.GOLD else UIKit.RED,
				description = item.description .. (if item.rare then "  (5% chance: rare!)" else ""),
				preview = ItemModels.build(id),
				button = "Buy",
				enabled = affordable,
				onClick = function()
					local ok, okResult, message = pcall(function()
						return buyItemRemote:InvokeServer(id, fromWizard)
					end)
					if ok then
						Sounds.play(if okResult then "Buy" else "Error")
						toast(
							tostring(message),
							if okResult then Config.COLORS.Good else Config.COLORS.ZombieText
						)
					end
					task.delay(0.2, render)
				end,
			})
		end
	end

	local function prompt(kind: "Product" | "GamePass", key: string)
		local id = if kind == "GamePass" then money.GamePasses[key] else money.Products[key]
		if not id or id == 0 then
			toast("Not set up yet: add its id to Config.MONETIZATION", Config.COLORS.ZombieText)
			return
		end
		if kind == "GamePass" then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end

	local function renderSkins()
		local equipped = ClientState.my("HumanSkin")
		local score = ClientState.my("Score") or 0
		for i, skin in Skins.forTeam("Human") do
			local owned = ClientState.owns("OwnedSkins", skin.id)
				or skin.default == true
				or (skin.pass ~= nil and ClientState.owns("Passes", skin.pass))
			local price, button, enabled = "", "", true
			if equipped == skin.id then
				price, button, enabled = "Owned", "Equipped", false
			elseif owned then
				price, button = "Owned", "Equip"
			elseif skin.scorePrice then
				price = Util.commas(skin.scorePrice) .. " score"
				button = "Unlock"
				enabled = score >= skin.scorePrice
			elseif skin.product then
				local id = money.Products[skin.product] or 0
				fetchPrice("Product", id, render)
				price, button = priceText("Product", id), "Buy"
			elseif skin.pass then
				price, button = "VIP pass", "Get VIP"
			end
			card({
				order = i,
				title = skin.name,
				price = price,
				priceColor = if owned then UIKit.LIME else UIKit.GOLD,
				description = if skin.team == "Zombie" then "Zombie skin" else "Human skin",
				preview = CharacterLook.preview(skin.id, skin.team),
				button = button,
				buttonColor = if skin.product or skin.pass then UIKit.ACCENT else UIKit.GOOD,
				enabled = enabled,
				onClick = function()
					local ok, status, message = pcall(function()
						return buySkinRemote:InvokeServer(skin.id)
					end)
					if not ok then
						return
					end
					if status == "prompt" then
						prompt("Product", message)
					elseif status == "promptPass" then
						prompt("GamePass", message)
					else
						Sounds.play(if status == "error" then "Error" else "Buy")
						toast(
							tostring(message),
							if status == "error" then Config.COLORS.ZombieText else Config.COLORS.Good
						)
					end
					task.delay(0.3, render)
				end,
			})
		end
	end

	local function renderRobux()
		local shown = 0
		local studio = RunService:IsStudio()
		local order = 0
		local function addCard(
			kind: "Product" | "GamePass",
			entry: { key: string, name: string, description: string, preview: string }
		)
			local id = (if kind == "GamePass" then money.GamePasses[entry.key] else money.Products[entry.key])
				or 0
			if id == 0 and not studio then
				return
			end
			order += 1
			shown += 1
			local owned = kind == "GamePass" and ClientState.owns("Passes", entry.key)
			fetchPrice(kind, id, render)
			card({
				order = order,
				title = entry.name,
				price = if owned then "Owned" elseif id == 0 then "Not set up" else priceText(kind, id),
				priceColor = if owned then UIKit.LIME else UIKit.GOLD,
				description = entry.description .. (if kind == "GamePass" then "  (permanent)" else ""),
				preview = buildPreview(entry.preview),
				button = if owned then "Owned" elseif id == 0 then "Needs an id (README)" else "Buy",
				buttonColor = UIKit.ACCENT,
				enabled = not owned and id ~= 0,
				onClick = function()
					prompt(kind, entry.key)
				end,
			})
		end
		for _, entry in PASSES do
			addCard("GamePass", entry)
		end
		for _, entry in PRODUCTS do
			addCard("Product", entry)
		end
		if shown == 0 then
			UIKit.label({
				Text = "Coming soon!",
				TextSize = 22,
				Size = UDim2.fromOffset(168, 222),
				ZIndex = 22,
				Parent = body,
			})
		end
	end

	render = function()
		if not window.Visible then
			return
		end
		clearBody()
		local wizard = mode == "Wizard"
		heading.Text = if wizard then "Wizard's Wares" else "Shop"
		tabBar.Visible = not wizard
		body.Position = UDim2.fromOffset(0, if wizard then 0 else 42)
		body.Size = UDim2.new(1, 0, 1, if wizard then 0 else -42)
		for name, button in tabButtons do
			local selected = name == mode
			button.BackgroundColor3 = if selected then UIKit.ACCENT else Color3.fromRGB(70, 72, 78)
		end
		if mode == "Items" then
			renderItems(false)
		elseif mode == "Wizard" then
			renderItems(true)
		elseif mode == "Skins" then
			renderSkins()
		else
			renderRobux()
		end
	end

	local lastScore = -1
	ShopPanel.update = function()
		if not window.Visible then
			return
		end
		local score = ClientState.my("Score") or 0
		scoreLabel.Text = "Score: " .. Util.commas(score)
		if score ~= lastScore then
			lastScore = score
			render()
		end
	end

	ShopPanel.open = function(newMode: Mode)
		mode = newMode
		window.Visible = true
		lastScore = -1
		render()
	end

	ShopPanel.close = function()
		window.Visible = false
	end

	ShopPanel.isOpen = function(): boolean
		return window.Visible
	end

	ShopPanel.mode = function(): Mode
		return mode
	end

	MarketplaceService.PromptProductPurchaseFinished:Connect(function()
		task.delay(1, render)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function()
		task.delay(1, render)
	end)
end

return ShopPanel
