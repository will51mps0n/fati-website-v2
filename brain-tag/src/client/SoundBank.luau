-- Every sound in the game, built from the few sound files that ship inside
-- the Roblox client (so they always load, in any experience, with no
-- uploads). Each recipe picks a file and shapes it: pitch, volume, a slice of
-- the file, audio effects, or a short sequence of notes.
--
-- To use your own uploaded sound instead, put its id in
-- Config.SOUND_OVERRIDES, e.g. Squeak = "rbxassetid://1234567890".

export type Note = {
	file: string, -- key of FILES
	pitch: number?,
	volume: number?,
	from: number?, -- play only this slice of the file (seconds)
	to: number?,
	effects: { string }?, -- Echo, Distort, Tremolo, Flange, Reverb, Muffle, Thin
	delay: number?, -- seconds after the first note (sequences)
}

export type Recipe = { Note }

local FILES: { [string]: string } = {
	Fall = "rbxasset://sounds/action_falling.ogg", -- rushing air
	Steps = "rbxasset://sounds/action_footsteps_plastic.mp3",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3", -- thud
	Swim = "rbxasset://sounds/action_swim.mp3",
	Explosion = "rbxasset://sounds/impact_explosion_03.mp3",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Oof = "rbxasset://sounds/oof.ogg",
	Ouch = "rbxasset://sounds/ouch.ogg",
	Click = "rbxasset://sounds/volume_slider.ogg",
}

local function note(file: string, pitch: number, volume: number, extra: { [string]: any }?): Note
	local n: Note = { file = file, pitch = pitch, volume = volume }
	if extra then
		n.from = extra.from
		n.to = extra.to
		n.effects = extra.effects
		n.delay = extra.delay
	end
	return n
end

local function chime(pitches: { number }, gap: number, volume: number, effects: { string }?): Recipe
	local notes = {}
	for i, pitch in pitches do
		table.insert(notes, note("Click", pitch, volume, { delay = (i - 1) * gap, effects = effects }))
	end
	return notes
end

local RECIPES: { [string]: Recipe } = {
	-- Weapons
	Whoosh = { note("Fall", 2.4, 0.35, { from = 0.2, to = 0.5 }) },
	Lunge = { note("Jump", 1.6, 0.45) },
	Swish = { note("Fall", 1.6, 0.35, { from = 0.1, to = 0.45, effects = { "Flange" } }) },
	Hit = { note("Land", 1.5, 0.7) },
	Clang = {
		note("Land", 2.6, 0.75, { effects = { "Echo", "Thin" } }),
		note("Click", 0.7, 0.5, { effects = { "Echo" } }),
	},
	Squeak = { note("Oof", 2.4, 0.55) },
	Boing = { note("Jump", 0.55, 0.7, { effects = { "Tremolo", "Flange" } }) },
	Pop = { note("Click", 0.55, 1) },
	Twang = { note("Jump", 2.2, 0.5, { effects = { "Tremolo" } }) },
	Gulp = { note("Splash", 2.2, 0.45, { to = 0.35 }) },
	Slip = { note("Fall", 1.8, 0.4, { to = 0.4 }), note("Oof", 1.4, 0.6, { delay = 0.25 }) },
	Shoot = { note("Explosion", 2.8, 0.25, { to = 0.25 }) },
	Shotgun = { note("Explosion", 1.5, 0.55, { to = 0.6 }) },
	Boom = { note("Explosion", 1, 0.7), note("Oof", 2.4, 0.4, { delay = 0.1 }) },
	Splat = { note("Splash", 1.6, 0.35, { to = 0.3 }), note("Land", 1.2, 0.3) },
	Plunge = { note("Land", 0.8, 0.6), note("Splash", 2.5, 0.35, { to = 0.2 }) },
	Freeze = {
		note("Splash", 0.6, 0.35, { to = 0.5, effects = { "Echo" } }),
		note("Click", 2.8, 0.5, { delay = 0.05 }),
	},
	Bubble = { note("Swim", 2, 0.35, { to = 0.4 }) },
	WallBreak = { note("Explosion", 1.2, 0.6, { to = 0.8 }), note("Land", 0.7, 0.7) },

	-- People
	Bump = { note("Land", 1.9, 0.3) },
	Infect = { note("Oof", 1, 0.9) }, -- the classic
	Groan = { note("Ouch", 0.5, 0.55, { effects = { "Distort", "Reverb" } }) },
	Pickup = { note("GetUp", 1.7, 0.45), note("Click", 1.6, 0.4, { delay = 0.06 }) },
	Drop = { note("Land", 1.1, 0.35) },
	Eat = { note("Click", 1.2, 0.5), note("GetUp", 2, 0.4, { delay = 0.05 }) },
	Warp = { note("Fall", 0.8, 0.45, { to = 0.6, effects = { "Reverb" } }) },

	-- Round and UI
	Outbreak = {
		note("Explosion", 0.45, 0.6),
		note("Ouch", 0.45, 0.6, { delay = 0.2, effects = { "Distort", "Reverb" } }),
	},
	RoundWin = chime({ 1, 1.26, 1.5, 2 }, 0.12, 0.7, { "Reverb" }),
	RoundLose = {
		note("Ouch", 0.45, 0.6, { effects = { "Distort" } }),
		note("Click", 1, 0.6, { delay = 0.15 }),
		note("Click", 0.84, 0.6, { delay = 0.3 }),
		note("Click", 0.7, 0.6, { delay = 0.45 }),
		note("Click", 0.5, 0.6, { delay = 0.6 }),
	},
	Tick = { note("Click", 1.3, 0.5) },
	TickFinal = { note("Click", 1.9, 0.75) },
	UiClick = { note("Click", 1.5, 0.35) },
	Buy = chime({ 2, 2.6 }, 0.09, 0.6),
	Error = chime({ 0.6, 0.5 }, 0.1, 0.5),
	Wizard = chime({ 1.5, 2, 2.5, 3 }, 0.07, 0.5, { "Echo" }),

	-- Loops (started and stopped by SoundController)
	Spray = { note("Swim", 1.5, 0.3) },
	Blower = { note("Fall", 1.3, 0.3) },
	Scrape = { note("Steps", 0.45, 0.25, { effects = { "Muffle" } }) },
	Footsteps = { note("Steps", 1.1, 0.18) },
}

return {
	FILES = FILES,
	RECIPES = RECIPES,
}
