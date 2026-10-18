-- Client entry point.

local Client = script.Parent

require(Client.ChatSetup).start()
require(Client.CameraController).start()
require(Client.MovementController).start()
require(Client.InputController).start()
require(Client.FurnitureController).start()
require(Client.BushController).start()
require(Client.DarknessController).start()
require(Client.RoofController).start()
require(Client.Effects).start()
require(Client.SoundController).start()
require(Client.UI.Hud).start()
