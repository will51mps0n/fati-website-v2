-- TextChatService setup: chat window at the bottom-right (bottom-left and
-- hidden until opened on phones) with channel tabs,
-- yellow system announcements from the server, and a gold [VIP] tag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.ClientState)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ChatSetup = {}

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

function ChatSetup.setVisible(visible: boolean)
	local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	local input = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	if window then
		window.Enabled = visible
	end
	if input then
		input.Enabled = visible
	end
end

function ChatSetup.isVisible(): boolean
	local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	return window == nil or window.Enabled
end

function ChatSetup.start()
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	task.spawn(function()
		local window = TextChatService:WaitForChild("ChatWindowConfiguration", 10) :: ChatWindowConfiguration?
		if window then
			-- Desktop: bottom-right (points sit bottom-left). Phones keep the
			-- touch buttons bottom-right, so chat stays left and starts hidden
			-- (the chat button top-left shows it).
			window.HorizontalAlignment = if touch
				then Enum.HorizontalAlignment.Left
				else Enum.HorizontalAlignment.Right
			window.VerticalAlignment = Enum.VerticalAlignment.Bottom
			if touch then
				ChatSetup.setVisible(false)
			end
		end
		local tabs = TextChatService:FindFirstChildOfClass("ChannelTabsConfiguration")
		if tabs then
			tabs.Enabled = true
		end
	end)

	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source then
			local entry = ClientState.participants:FindFirstChild("P" .. source.UserId)
			if entry and entry:GetAttribute("VIP") then
				properties.PrefixText = string.format(
					'<font color="#%s">[VIP]</font> %s',
					Config.COLORS.VipName,
					message.PrefixText
				)
			end
		end
		return properties
	end

	local general: TextChannel? = nil
	task.spawn(function()
		local channels = TextChatService:WaitForChild("TextChannels", 20)
		general = channels and channels:WaitForChild("RBXGeneral", 20) :: TextChannel?
	end)

	Remotes.event("Announce").OnClientEvent:Connect(function(text: string, hex: string?)
		if typeof(text) ~= "string" then
			return
		end
		local channel = general
		if channel then
			channel:DisplaySystemMessage(
				string.format('<font color="#%s">%s</font>', hex or Config.COLORS.SystemMessage, escape(text))
			)
		end
	end)
end

return ChatSetup
