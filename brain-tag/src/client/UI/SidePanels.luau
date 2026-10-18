-- The settings window (sound, camera height, ping/fps line) and the trophy
-- window (your stats and the all-time top 10).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraController = require(script.Parent.Parent.CameraController)
local ClientState = require(script.Parent.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local Sounds = require(script.Parent.Parent.Sounds)
local TopRight = require(script.Parent.TopRight)
local UIKit = require(script.Parent.UIKit)
local Util = require(ReplicatedStorage.Shared.Util)

local SidePanels = {}

export type Panel = { open: () -> (), close: () -> (), isOpen: () -> boolean, update: () -> () }

local function row(parent: Instance, order: number, title: string): Frame
	local frame = UIKit.new("Frame", {
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 21,
		Parent = parent,
	})
	UIKit.label({
		Text = title,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.45, 0, 1, 0),
		ZIndex = 22,
		Parent = frame,
	})
	local options = UIKit.new("Frame", {
		Name = "Options",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.55, 0, 1, 0),
		ZIndex = 22,
		Parent = frame,
	}, {
		UIKit.list(
			Enum.FillDirection.Horizontal,
			6,
			Enum.HorizontalAlignment.Right,
			Enum.VerticalAlignment.Center
		),
	})
	return options
end

-- A row of mutually exclusive choices.
local function choices(parent: Instance, labels: { string }, current: () -> string, pick: (string) -> ())
	local buttons: { [string]: TextButton } = {}
	local function refresh()
		for label, button in buttons do
			button.BackgroundColor3 = if label == current() then UIKit.ACCENT else Color3.fromRGB(70, 72, 78)
		end
	end
	for i, label in labels do
		buttons[label] = UIKit.button({
			Text = label,
			LayoutOrder = i,
			Size = UDim2.fromOffset(78, 32),
			TextSize = 15,
			ZIndex = 23,
			Parent = parent,
		}, function()
			pick(label)
			refresh()
		end)
	end
	refresh()
end

function SidePanels.buildSettings(parent: Instance, openHelp: () -> ()): Panel
	local panel: Panel
	local window, content = UIKit.modal(parent, "Settings", 440, 330, function()
		panel.close()
	end)
	UIKit.list(Enum.FillDirection.Vertical, 8).Parent = content

	choices(row(content, 1, "Sound effects"), { "On", "Off" }, function()
		return if Sounds.enabled() then "On" else "Off"
	end, function(choice)
		Sounds.setEnabled(choice == "On")
	end)

	choices(row(content, 2, "Camera"), { "Close", "Normal", "Far" }, function()
		for name, height in Config.CAMERA_ZOOMS do
			if height == CameraController.height() then
				return name :: string
			end
		end
		return "Normal"
	end, function(choice)
		CameraController.setHeight((Config.CAMERA_ZOOMS :: { [string]: number })[choice])
	end)

	choices(row(content, 3, "Ping / FPS"), { "On", "Off" }, function()
		return if TopRight.statsVisible() then "On" else "Off"
	end, function(choice)
		TopRight.setStatsVisible(choice == "On")
	end)

	UIKit.button({
		LayoutOrder = 4,
		Text = "How to play",
		Size = UDim2.fromOffset(160, 36),
		ZIndex = 22,
		Parent = content,
	}, function()
		panel.close()
		openHelp()
	end)

	panel = {
		open = function()
			window.Visible = true
		end,
		close = function()
			window.Visible = false
		end,
		isOpen = function()
			return window.Visible
		end,
		update = function() end,
	}
	return panel
end

function SidePanels.buildTrophy(parent: Instance): Panel
	local panel: Panel
	local window, content = UIKit.modal(parent, "Trophies", 520, 500, function()
		panel.close()
	end)
	UIKit.list(Enum.FillDirection.Vertical, 6).Parent = content

	local stats = UIKit.label({
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 18,
		RichText = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		Parent = content,
	})
	UIKit.label({
		LayoutOrder = 2,
		Text = "All-time best scores",
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 22,
		Font = UIKit.HEAVY,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		Parent = content,
	})
	local board = UIKit.label({
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 17,
		Font = UIKit.FONT,
		RichText = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 22,
		Parent = content,
	})

	panel = {
		open = function()
			window.Visible = true
		end,
		close = function()
			window.Visible = false
		end,
		isOpen = function()
			return window.Visible
		end,
		update = function()
			if not window.Visible then
				return
			end
			stats.Text = string.format(
				"Best <b>%s</b>     Wins <b>%d</b>     Infections <b>%d</b>     Rounds <b>%d</b>",
				Util.commas(ClientState.my("BestScore") or 0),
				ClientState.my("Wins") or 0,
				ClientState.my("Infections") or 0,
				ClientState.my("RoundsPlayed") or 0
			)
			local ok, rows = pcall(function()
				return HttpService:JSONDecode(ClientState.attr("TopScores") or "[]")
			end)
			if ok and typeof(rows) == "table" and #rows > 0 then
				local lines = {}
				for i, entry in rows do
					table.insert(
						lines,
						string.format(
							"%d.  %s  <b>%s</b>",
							i,
							tostring(entry.name),
							Util.commas(tonumber(entry.score) or 0)
						)
					)
				end
				board.Text = table.concat(lines, "\n")
			else
				board.Text = "No best scores saved yet. (Saving needs a published place with API access.)"
			end
		end,
	}
	return panel
end

return SidePanels
