-- Client entry point.

local Client = script.Parent

require(Client.ChatSetup).start()
require(Client.CameraController).start()
require(Client.MovementController).start()
require(Client.InputController).start()
require(Client.Effects).start()
require(Client.UI.Hud).start()
