-- Server -> client messages: yellow system lines in chat, short on-screen
-- toasts, and visual/sound effects that every client plays locally.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Announcer = {}

local announce = Remotes.event("Announce")
local toast = Remotes.event("Toast")
local fx = Remotes.event("Fx")

function Announcer.chat(text: string, hex: string?)
	announce:FireAllClients(text, hex or Config.COLORS.SystemMessage)
end

function Announcer.toast(player: Player?, text: string, hex: string?)
	if player then
		toast:FireClient(player, text, hex)
	else
		toast:FireAllClients(text, hex)
	end
end

function Announcer.fx(kind: string, data: { [string]: any })
	fx:FireAllClients(kind, data)
end

return Announcer
