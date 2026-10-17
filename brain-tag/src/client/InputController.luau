-- Keyboard, mouse and gamepad actions. Touch buttons call the same functions.
--   Left click / R2: use item (hold to keep spraying)
--   E / X: pick up      G / B: drop      B / Y: shop      Z / L1: zombie return
--   1 2 3 / D-pad: switch inventory slot

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MovementController = require(script.Parent.MovementController)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local InputController = {}

local useRemote = Remotes.event("UseItem")
local pickRemote = Remotes.event("PickUp")
local dropRemote = Remotes.event("DropItem")
local returnRemote = Remotes.event("ZombieReturn")
local slotRemote = Remotes.event("SelectSlot")

-- Set by the HUD.
InputController.onShop = function() end
InputController.isMenuOpen = function(): boolean
	return false
end

local using = false

function InputController.useStart()
	using = true
	useRemote:FireServer("start", MovementController.aim())
end

-- True while the use button is held (hooking furniture with a weapon).
function InputController.isUsing(): boolean
	return using
end

function InputController.useStop()
	if using then
		using = false
		useRemote:FireServer("stop", MovementController.aim())
	end
end

function InputController.pickUp()
	pickRemote:FireServer()
end

function InputController.drop()
	dropRemote:FireServer()
end

function InputController.selectSlot(slot: number)
	slotRemote:FireServer(slot)
end

function InputController.zombieReturn()
	returnRemote:FireServer()
end

function InputController.shop()
	InputController.onShop()
end

local BEGIN: { [Enum.KeyCode]: () -> () } = {
	[Enum.KeyCode.E] = InputController.pickUp,
	[Enum.KeyCode.G] = InputController.drop,
	[Enum.KeyCode.B] = InputController.shop,
	[Enum.KeyCode.Z] = InputController.zombieReturn,
	[Enum.KeyCode.ButtonX] = InputController.pickUp,
	[Enum.KeyCode.ButtonB] = InputController.drop,
	[Enum.KeyCode.ButtonY] = InputController.shop,
	[Enum.KeyCode.ButtonL1] = InputController.zombieReturn,
	[Enum.KeyCode.ButtonR2] = InputController.useStart,
	[Enum.KeyCode.One] = function()
		InputController.selectSlot(1)
	end,
	[Enum.KeyCode.Two] = function()
		InputController.selectSlot(2)
	end,
	[Enum.KeyCode.Three] = function()
		InputController.selectSlot(3)
	end,
	[Enum.KeyCode.DPadLeft] = function()
		InputController.selectSlot(1)
	end,
	[Enum.KeyCode.DPadUp] = function()
		InputController.selectSlot(2)
	end,
	[Enum.KeyCode.DPadRight] = function()
		InputController.selectSlot(3)
	end,
}

function InputController.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if not InputController.isMenuOpen() then
				InputController.useStart()
			end
			return
		end
		local action = BEGIN[input.KeyCode]
		if action then
			action()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.KeyCode == Enum.KeyCode.ButtonR2
		then
			InputController.useStop()
		end
	end)
end

return InputController
