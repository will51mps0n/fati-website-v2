-- Builds the whole HUD in code and keeps it up to date.
--   left side: buttons       top-center: countdown      top-right: counts + leaderboard
--   bottom-left: points      bottom-center: item slot   bottom-right: chat
--   center: win text, toasts, shop / settings / trophy / quick start windows
--   over your character: "+10" when your points change

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local AdminPanel = require(script.Parent.AdminPanel)
local Banner = require(script.Parent.Banner)
local BottomCenter = require(script.Parent.BottomCenter)
local BottomLeft = require(script.Parent.BottomLeft)
local Center = require(script.Parent.Center)
local ChatSetup = require(script.Parent.Parent.ChatSetup)
local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local InputController = require(script.Parent.Parent.InputController)
local MobileButtons = require(script.Parent.MobileButtons)
local QuickStart = require(script.Parent.QuickStart)
local ScorePopups = require(script.Parent.ScorePopups)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopPanel = require(script.Parent.ShopPanel)
local SidePanels = require(script.Parent.SidePanels)
local TopLeft = require(script.Parent.TopLeft)
local TopRight = require(script.Parent.TopRight)
local UIKit = require(script.Parent.UIKit)

local Hud = {}

local player = Players.LocalPlayer

local function hideDefaultGui()
	for _, kind in { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health } do
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(kind, false)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end
end

function Hud.start()
	task.spawn(hideDefaultGui)

	local gui = UIKit.new("ScreenGui", {
		Name = "BrainTagHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local uiScale = UIKit.new("UIScale", { Parent = gui })
	local function rescale()
		local camera = workspace.CurrentCamera
		if camera then
			uiScale.Scale = math.clamp(camera.ViewportSize.Y / 760, 0.62, 1)
		end
	end
	rescale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	local touchMode = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

	local toast = Center.buildToasts(gui)
	ScorePopups.start()
	ShopPanel.build(gui, toast)
	local openQuick, quickOpen = QuickStart.build(gui, touchMode, function()
		Remotes.event("TutorialDone"):FireServer()
	end)
	local settings = SidePanels.buildSettings(gui, openQuick)
	local trophy = SidePanels.buildTrophy(gui)
	local admin = AdminPanel.build(gui, toast)

	local function closeAll()
		ShopPanel.close()
		settings.close()
		trophy.close()
		admin.close()
	end

	local function toggleShop()
		if ShopPanel.isOpen() then
			ShopPanel.close()
			return
		end
		if ClientState.isZombie() then
			toast("Zombies can't shop!", Config.COLORS.ZombieText)
			return
		end
		closeAll()
		local _, root = ClientState.myCharacter()
		local atWizard = root ~= nil and BottomCenter.wizardNear(root.Position)
		ShopPanel.open(if atWizard then "Wizard" else "Items")
	end

	TopLeft.build(gui, {
		menu = function()
			closeAll()
			openQuick()
		end,
		shop = toggleShop,
		settings = function()
			local wasOpen = settings.isOpen()
			closeAll()
			if not wasOpen then
				settings.open()
			end
		end,
		trophy = function()
			local wasOpen = trophy.isOpen()
			closeAll()
			if not wasOpen then
				trophy.open()
			end
		end,
		chat = function()
			ChatSetup.setVisible(not ChatSetup.isVisible())
		end,
	})

	local updaters = {
		Banner.build(gui),
		TopRight.build(gui),
		BottomCenter.build(gui, touchMode),
		BottomLeft.build(gui),
		Center.buildWinText(gui),
	}
	if touchMode then
		table.insert(updaters, MobileButtons.build(gui))
	end

	InputController.onShop = toggleShop
	InputController.isMenuOpen = function()
		return ShopPanel.isOpen() or settings.isOpen() or trophy.isOpen() or quickOpen() or admin.isOpen()
	end

	Remotes.event("Toast").OnClientEvent:Connect(function(text: string, hex: string?)
		if typeof(text) == "string" then
			toast(text, hex)
		end
	end)

	-- First visit: show the quick start once the server has loaded our data.
	task.spawn(function()
		local me = ClientState.participants:WaitForChild(ClientState.myId(), 60)
		if me and me:GetAttribute("SeenTutorial") ~= true then
			openQuick()
		end
	end)

	task.spawn(function()
		while true do
			for _, update in updaters do
				local ok, err = pcall(function()
					update()
					return true
				end)
				if not ok then
					warn("[Hud] " .. tostring(err))
				end
			end
			ShopPanel.update()
			trophy.update()
			admin.update()

			-- Close the shop if you turned into a zombie or walked away from the wizard.
			if ShopPanel.isOpen() then
				local _, root = ClientState.myCharacter()
				if ClientState.isZombie() then
					ShopPanel.close()
				elseif
					ShopPanel.mode() == "Wizard" and (not root or not BottomCenter.wizardNear(root.Position))
				then
					ShopPanel.close()
				end
			end

			-- Your own name tag is lime green (only on your screen).
			local character = player.Character
			local head = character and character:FindFirstChild("Head")
			local tag = head and head:FindFirstChild("NameTag")
			local label = tag and tag:FindFirstChild("Label") :: TextLabel?
			if label then
				label.TextColor3 = UIKit.LIME
			end

			task.wait(0.1)
		end
	end)
end

return Hud
