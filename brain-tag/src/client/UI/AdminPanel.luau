-- The admin panel (F2, or the ADMIN button on the left). Only shown to
-- admins; the server checks every request again (see AdminService).
--   Target: one player or everyone
--   Items:  give any item (or drop it in front of you)
--   Speed, points, immunity, team, bring / go to / respawn
--   Round:  skip phase, add time, next map, reset furniture, clear items

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local Items = require(ReplicatedStorage.Shared.Items)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Skins = require(ReplicatedStorage.Shared.Skins)
local UIKit = require(script.Parent.UIKit)

local AdminPanel = {}

local GRAY = Color3.fromRGB(70, 72, 78)
local ADMIN_RED = Color3.fromRGB(196, 54, 54)

export type Panel = {
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	update: () -> (),
}

-- Every item: the shop's order, then the wizard's, then anything else.
local function itemIds(): { string }
	local list, seen = {}, {}
	for _, group in { Items.shopOrder, Items.wizardOrder } do
		for _, id in group do
			if not seen[id] and Items.get(id) then
				seen[id] = true
				table.insert(list, id)
			end
		end
	end
	local rest = {}
	for id in Items.all do
		if not seen[id] then
			table.insert(rest, id)
		end
	end
	table.sort(rest)
	for _, id in rest do
		table.insert(list, id)
	end
	return list
end

function AdminPanel.build(parent: Instance, toast: (string, string?) -> ()): Panel
	local remote = Remotes.func("Admin")
	local window, content = UIKit.modal(parent, "Admin", 660, 600, function() end)

	local scroll = UIKit.new("ScrollingFrame", {
		Name = "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -28),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ZIndex = 21,
		Parent = content,
	}, { UIKit.list(Enum.FillDirection.Vertical, 6) })
	local status = UIKit.label({
		Name = "Status",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 16,
		TextColor3 = UIKit.MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Pick a target, then a command.",
		ZIndex = 21,
		Parent = content,
	})

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function heading(text: string)
		UIKit.label({
			Text = text,
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, 22),
			TextSize = 18,
			Font = UIKit.HEAVY,
			TextColor3 = UIKit.GOLD,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 21,
			Parent = scroll,
		})
	end

	-- A wrapping row of buttons.
	local function row(height: number?): Frame
		return UIKit.new("Frame", {
			LayoutOrder = nextOrder(),
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 21,
			Parent = scroll,
		}, {
			UIKit.new("UIGridLayout", {
				CellSize = UDim2.fromOffset(118, height or 32),
				CellPadding = UDim2.fromOffset(6, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end

	local function button(parentRow: Frame, text: string, color: Color3?, onClick: () -> ()): TextButton
		return UIKit.button({
			Text = text,
			TextSize = 15,
			TextWrapped = true,
			BackgroundColor3 = color or UIKit.ACCENT,
			ZIndex = 22,
			Parent = parentRow,
		}, onClick)
	end

	-- Target picker --------------------------------------------------------------------------
	local target = ClientState.myId()
	local targetRow: Frame
	local function send(action: string, data: { [string]: any }?)
		local args: { [string]: any } = data or {}
		args.target = target
		status.Text = "..."
		task.spawn(function()
			local ok, success, message = pcall(function()
				return remote:InvokeServer(action, args)
			end)
			local text = if ok then tostring(message) else "Couldn't reach the server"
			status.Text = text
			status.TextColor3 = if ok and success then UIKit.GOOD else UIKit.RED
			if ok and success then
				toast(text)
			end
		end)
	end

	heading("Target")
	targetRow = row(30)
	local function refreshTargets()
		for _, child in targetRow:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		local entries = { { id = "*", name = "Everyone" } }
		for _, r in ClientState.rows() do
			table.insert(entries, { id = r.id, name = (if r.isMe then "Me: " else "") .. r.name })
		end
		local stillThere = false
		for _, entry in entries do
			stillThere = stillThere or entry.id == target
		end
		if not stillThere then
			target = ClientState.myId()
		end
		for i, entry in entries do
			local b = button(
				targetRow,
				entry.name,
				if entry.id == target then UIKit.GOOD else GRAY,
				function()
					target = entry.id
					refreshTargets()
				end
			)
			b.LayoutOrder = i
		end
	end

	-- Items -------------------------------------------------------------------------------
	heading("Give item (click)")
	local toGround = false
	local modeRow = row(30)
	local modeButton: TextButton
	modeButton = button(modeRow, "To: their hand", GRAY, function()
		toGround = not toGround
		modeButton.Text = if toGround then "To: ground near me" else "To: their hand"
	end)
	local itemRow = row(30)
	for i, id in itemIds() do
		local item = Items.get(id)
		if item then
			local b = button(itemRow, item.name, nil, function()
				send("give", { item = id, ground = toGround })
			end)
			b.LayoutOrder = i
		end
	end

	-- Skins ---------------------------------------------------------------------------------
	heading("Give skin (they keep it, and wear it now)")
	local skinRow = row(30)
	for i, skin in Skins.list do
		local label = skin.name .. (if skin.team == "Zombie" then " (Z)" else "")
		local b = button(
			skinRow,
			label,
			if skin.team == "Zombie" then Color3.fromRGB(70, 120, 60) else nil,
			function()
				send("skin", { skin = skin.id })
			end
		)
		b.LayoutOrder = i
	end

	-- Speed ---------------------------------------------------------------------------------
	heading("Speed")
	local speedRow = row()
	for _, factor in { 0, 0.25, 0.5, 1, 1.5, 2, 3 } do
		local label = if factor == 0 then "Freeze" elseif factor == 1 then "Normal (1x)" else factor .. "x"
		button(speedRow, label, if factor < 1 then GRAY else nil, function()
			send("speed", { factor = factor })
		end)
	end

	-- Points --------------------------------------------------------------------------------
	heading("Points (size and speed follow points)")
	local pointsRow = row()
	for _, amount in { 1000, 10000, 100000, -1000 } do
		button(pointsRow, string.format("%+d", amount), if amount < 0 then GRAY else nil, function()
			send("points", { add = amount })
		end)
	end
	button(pointsRow, "Set to 0", ADMIN_RED, function()
		send("points", { set = 0 })
	end)

	-- Player --------------------------------------------------------------------------------
	heading("Player")
	local playerRow = row()
	button(playerRow, "Make human", nil, function()
		send("team", { team = "Human" })
	end)
	button(playerRow, "Make zombie", ADMIN_RED, function()
		send("team", { team = "Zombie" })
	end)
	button(playerRow, "Immunity 100", nil, function()
		send("immunity", { value = 100 })
	end)
	button(playerRow, "Bring to me", nil, function()
		send("bring")
	end)
	button(playerRow, "Go to", nil, function()
		send("goTo")
	end)
	button(playerRow, "Respawn", GRAY, function()
		send("respawn")
	end)

	-- Round ---------------------------------------------------------------------------------
	heading("Round")
	local roundRow = row()
	button(roundRow, "Skip phase", nil, function()
		send("skip")
	end)
	button(roundRow, "+60 seconds", nil, function()
		send("time", { seconds = 60 })
	end)
	button(roundRow, "-30 seconds", GRAY, function()
		send("time", { seconds = -30 })
	end)
	button(roundRow, "Next map (next round)", nil, function()
		send("nextMap")
	end)
	button(roundRow, "Reset furniture", GRAY, function()
		send("resetFurniture")
	end)
	button(roundRow, "Clear ground items", GRAY, function()
		send("clearItems")
	end)

	-- Open button (admins only) ----------------------------------------------------------------
	local openButton = UIKit.button({
		Name = "AdminButton",
		Text = "ADMIN\n(F2)",
		TextSize = 13,
		-- Under the left side bar's buttons.
		Position = UDim2.fromOffset(12, 10 + 5 * (66 + 8)),
		Size = UDim2.fromOffset(66, 46),
		BackgroundColor3 = ADMIN_RED,
		Visible = false,
		Parent = parent,
	})

	local function isAdmin(): boolean
		return ClientState.my("Admin") == true
	end

	local lastCount = -1
	local panel: Panel = {
		open = function()
			if isAdmin() then
				lastCount = #ClientState.rows()
				refreshTargets()
				window.Visible = true
			end
		end,
		close = function()
			window.Visible = false
		end,
		isOpen = function()
			return window.Visible
		end,
		update = function()
			openButton.Visible = isAdmin()
			if window.Visible then
				local count = #ClientState.rows()
				if count ~= lastCount then
					lastCount = count
					refreshTargets()
				end
			end
		end,
	}
	local function toggle()
		if window.Visible then
			panel.close()
		else
			panel.open()
		end
	end
	openButton.Activated:Connect(toggle)
	local close = window:FindFirstChild("Close")
	if close and close:IsA("TextButton") then
		close.Activated:Connect(panel.close)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F2 then
			toggle()
		end
	end)
	return panel
end

return AdminPanel
