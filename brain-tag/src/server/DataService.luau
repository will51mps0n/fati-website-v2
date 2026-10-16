-- Saves each player's score, stats, skins and purchases with DataStoreService.
--
-- Safety rules:
--  * Every DataStore call is wrapped in pcall and retried with backoff.
--  * If a player's data fails to load, the session uses defaults and is NEVER
--    saved, so a hiccup can't overwrite real progress with zeros.
--  * In Studio without "Enable Studio Access to API Services" (Game Settings >
--    Security), saving is off for the session and a single warning explains why.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Skins = require(ReplicatedStorage.Shared.Skins)

local DataService = {}

local VERSION = 1
local MAX_RECEIPTS = 100

export type Profile = {
	Version: number,
	Score: number,
	Wins: number,
	Infections: number,
	RoundsPlayed: number,
	OwnedSkins: { [string]: boolean },
	HumanSkin: string,
	ZombieSkin: string,
	SeenTutorial: boolean,
	BoostEndsAt: number,
	PendingItems: { string },
	Receipts: { [string]: number },
}

type Session = {
	data: Profile,
	loaded: boolean, -- false = defaults after a failed load; never saved
	saving: boolean,
}

local sessions: { [Player]: Session } = {}
local store: DataStore? = nil
local orderedStore: OrderedDataStore? = nil
local available = false
local warned = false

local function defaults(): Profile
	return {
		Version = VERSION,
		Score = 0,
		Wins = 0,
		Infections = 0,
		RoundsPlayed = 0,
		OwnedSkins = { [Skins.DEFAULT_HUMAN] = true, [Skins.DEFAULT_ZOMBIE] = true },
		HumanSkin = Skins.DEFAULT_HUMAN,
		ZombieSkin = Skins.DEFAULT_ZOMBIE,
		SeenTutorial = false,
		BoostEndsAt = 0,
		PendingItems = {},
		Receipts = {},
	}
end

-- Fills in any fields added after a player's data was first saved.
local function reconcile(saved: any): Profile
	local data = defaults()
	if type(saved) ~= "table" then
		return data
	end
	for key, value in saved do
		if (data :: any)[key] ~= nil and type(value) == type((data :: any)[key]) then
			(data :: any)[key] = value
		end
	end
	data.OwnedSkins[Skins.DEFAULT_HUMAN] = true
	data.OwnedSkins[Skins.DEFAULT_ZOMBIE] = true
	return data
end

local function warnOnce(message: string)
	if not warned then
		warned = true
		warn("[Data] " .. message)
	end
end

local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	local lastError
	for attempt = 1, 4 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		task.wait(attempt * 1.5)
	end
	warn(string.format("[Data] %s failed: %s", label, tostring(lastError)))
	return false, nil
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

function DataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		store = result
		local okOrdered, ordered = pcall(function()
			return DataStoreService:GetOrderedDataStore(Config.LEADERBOARD_STORE_NAME)
		end)
		if okOrdered then
			orderedStore = ordered
		end
		-- A cheap read tells us whether DataStores actually work here.
		local probe = pcall(function()
			(store :: DataStore):GetAsync("__probe")
		end)
		available = probe
	end
	if not available then
		if RunService:IsStudio() then
			warnOnce(
				"Saving is OFF in this test. To save in Studio: publish the place (File > Publish to Roblox), then Game Settings > Security > Enable Studio Access to API Services."
			)
		else
			warnOnce("DataStores are unavailable right now; this server will not save.")
		end
	end

	game:BindToClose(function()
		local threads = {}
		for player in sessions do
			table.insert(
				threads,
				task.spawn(function()
					DataService.save(player)
				end)
			)
		end
		-- Give saves time to finish (BindToClose allows about 30 seconds).
		local deadline = os.clock() + 25
		while os.clock() < deadline do
			local busy = false
			for _, session in sessions do
				if session.saving then
					busy = true
				end
			end
			if not busy then
				break
			end
			task.wait(0.25)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_SECONDS)
			for player in sessions do
				task.spawn(DataService.save, player)
			end
		end
	end)
end

function DataService.isAvailable(): boolean
	return available
end

-- Loads (yields). Always returns a profile; check `isSaved` to know whether
-- it came from the DataStore.
function DataService.load(player: Player): Profile
	local session: Session = { data = defaults(), loaded = false, saving = false }
	if available and store then
		local ok, saved = retry("load " .. player.UserId, function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if ok then
			session.data = reconcile(saved)
			session.loaded = true
		end
	end
	sessions[player] = session
	return session.data
end

function DataService.get(player: Player): Profile?
	local session = sessions[player]
	return session and session.data
end

function DataService.isSaved(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.loaded
end

-- Keeps the receipt log small: drops the oldest entries past MAX_RECEIPTS.
local function trimReceipts(data: Profile)
	local list = {}
	for id, at in data.Receipts do
		table.insert(list, { id = id, at = at })
	end
	if #list <= MAX_RECEIPTS then
		return
	end
	table.sort(list, function(a, b)
		return a.at > b.at
	end)
	for i = MAX_RECEIPTS + 1, #list do
		data.Receipts[list[i].id] = nil
	end
end

-- Writes the player's profile. Returns true when it reached the DataStore.
function DataService.save(player: Player): boolean
	local session = sessions[player]
	if not session or not session.loaded or not available or not store then
		return false
	end
	while session.saving do
		task.wait(0.1)
	end
	session.saving = true
	trimReceipts(session.data)
	local snapshot = table.clone(session.data)
	local ok = retry("save " .. player.UserId, function()
		(store :: DataStore):UpdateAsync(key(player), function()
			return snapshot
		end)
		return true
	end)
	if ok and orderedStore then
		pcall(function()
			(orderedStore :: OrderedDataStore):SetAsync(tostring(player.UserId), math.floor(snapshot.Score))
		end)
	end
	session.saving = false
	return ok
end

function DataService.release(player: Player)
	DataService.save(player)
	sessions[player] = nil
end

-- Top scores across all servers, best first: { { userId, score } }.
function DataService.topScores(count: number): { { userId: number, score: number } }
	local result = {}
	if not available or not orderedStore then
		return result
	end
	local ok, page = pcall(function()
		return (orderedStore :: OrderedDataStore):GetSortedAsync(false, count):GetCurrentPage()
	end)
	if ok and page then
		for _, entry in page do
			local id = tonumber(entry.key)
			if id then
				table.insert(result, { userId = id, score = entry.value })
			end
		end
	end
	return result
end

Players.PlayerRemoving:Connect(function(player)
	if sessions[player] then
		DataService.release(player)
	end
end)

return DataService
