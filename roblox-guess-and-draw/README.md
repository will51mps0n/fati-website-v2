# Guess & Draw (Roblox)

A multiplayer drawing and guessing game. One player draws a secret word and everyone else races to guess it in chat. The others watch the drawing appear live, stroke by stroke.

## How a match plays

- **Match:** a batch of `ROUNDS_PER_MATCH` rounds (6 by default). It starts once `MIN_PLAYERS` (2) are in the server.
- **Round:** every player gets one turn as the drawer.
- **Turn:**
  1. **Choosing (15s):** the drawer picks one of 3 words: one easy, one medium and one hard, in that order. If they don't pick, one is chosen at random.
     - `src/shared/Words.luau` has the three lists: 200 easy words, 170 medium (including characters like Mario, SpongeBob, Pikachu and Bluey) and 180 hard (Harry Potter, Darth Vader, the Bob's Burgers family, other cartoon characters, landmarks, ideas and sayings). Words don't repeat within a match until a list runs out.
     - The small 🔒 **⏣10 Custom** button beside the choices lets the drawer buy a custom word and type any word they like. Clicking it gives them at least 30s (`CUSTOM_WORD_TIME`).
     - **Secret free custom word:** on your turn to pick, type the password (`CUSTOM_WORD_PASSWORD` at the top of `src/server/GameServer.server.luau`) into the chat. It's never shown to anyone and opens the custom word box for free. It lives only on the server, so players can't dig it out of the game.
     - Custom words must be 2-30 letters (spaces, `-` and `'` allowed). They're checked against a blocklist of rude words (whole words for short ones, so "class" or "grapes" are fine) and must pass Roblox's text filter.
  2. **Drawing (80s):** guessers type in the chat box. The word shows as blanks (`_ _ _ _ _ (5)`), and letters are revealed as hints at 50% and 75% of the time.
     - A correct guess earns 50–300 points; the faster you guess, the more you get. The first correct guess earns a +50 bonus.
     - The drawer earns 50 points for each correct guess.
     - A guess one letter off gets a private "is close!" message.
     - Correct guesses are never shown to other players. Once you've guessed, you can only chat with the drawer and the other players who guessed, so nobody can leak the answer.
     - The turn ends early when everyone has guessed or the drawer leaves.
  3. **Reveal (6s):** shows the word and the points everyone earned that turn.
- **Match end:** a podium shows 1st, 2nd and 3rd place (tied players share a place). Each 1st-place winner gets +1 win. A new match then starts automatically.
- **All-time wins:** wins are saved in a DataStore (`GuessAndDrawWins`), so they carry over between servers and visits. Each player's total shows as a small 👑 and number after their name in the player list, and as `Wins` on the Roblox leaderboard.
  - DataStores only work in a published game. To test them in Studio, switch on **Game Settings → Security → Enable Studio Access to API Services**.
  - Without a DataStore, wins only count for the current server.

**Thumbs up / down:** while someone draws, everyone else gets a thumbs up and a thumbs down in the canvas's top-right corner, like skribbl.io, one vote per drawing. The pixel-art thumbs are `assets/thumbs-up.png` and `assets/thumbs-down.png` (set in `Config.THUMBS_UP_IMAGE` / `THUMBS_DOWN_IMAGE`); until they're uploaded, emoji stand in. Chat shows "X liked the drawing!" or "X disliked the drawing!", and a thumb floats up over the canvas.

**Robux shop:** while someone draws, everyone else sees three buttons under the canvas:
- **💣 Nuke drawing (⏣99):** wipes the drawing for everyone, with a flash and a boom.
- **🦹 Steal drawing (⏣50):** you become the drawer for the rest of the turn and keep the drawing so far. The old drawer now just watches, because they know the word.
- **🏆 Insta guess (⏣25):** counts as a correct guess right away.

Each item is a **Developer Product**, set up on the Creator Hub (your game → Monetization → Developer Products), with its ID in `Config.PRODUCTS`:

| Item | Product ID |
| --- | --- |
| Custom Word | 3718880573 |
| Nuke Drawing | 3718880654 |
| Steal Drawing | 3718880703 |
| Insta Guess | 3718880747 |

The buttons show each product's live price from Roblox. With Managed pricing on, Roblox can change prices (Steal Drawing is currently 49 and Custom Word 9), and the game always shows what players will actually pay.
- Until an ID is set, that item is free when testing in Studio and unavailable in the published game.
- A purchase that can't be used at that moment (for example, the turn ended while the player was paying) is saved as a credit. The button then shows "Use (1)". Credits last until the player leaves the server.

**Report:** the orange Report button in the top bar lets you pick a player and a reason. Reports are printed in the server output and saved in the `GuessAndDrawReports` DataStore. Roblox doesn't let games open its own report form, so the game also points players to Roblox's menu (☰ → Report) for anything serious.

**Vote to kick:** the orange **Vote Kick: x/n** button in the top bar votes to kick whoever is drawing. You can also click any other player in the list and choose **👢 Vote to kick**. Chat shows "X is voting to kick Y (1/2)".
- The kick happens once 60% of the other players have voted (`VOTE_KICK_SHARE`), with at least 2 votes (`VOTE_KICK_MIN`), so 2 players can't kick each other.
- A kicked player can't rejoin that server for 10 minutes (`VOTE_KICK_BAN_MINUTES`); they can join a different server straight away. Admins can't be vote-kicked.

**Admins:** the game's owner (for a group game, the group's owner) and anyone in `Config.ADMINS` (usernames or user IDs). Admins type these in the game's chat box; nobody else sees them:

| Command | What it does |
| --- | --- |
| `/help` | Lists the commands |
| `/kick name [minutes]` | Kicks someone; they can't rejoin this server for 10 minutes, or the minutes given (0 lets them straight back) |
| `/ban name` | Kicks someone until this server closes |
| `/unban name` / `/unban all` | Lets kicked players back in |
| `/skip` | Ends the current turn (or hurries a countdown) |
| `/clear` | Wipes the drawing |
| `/announce message` | Posts a message to everyone |

Names can be a username or display name, or just the start of one. Commands also work with `:` instead of `/`.
- Votes from or against someone who leaves stop counting.

**Word themes:** the **YOUR THEME ▾** menu under the player list sets which words you get when it's your turn to draw. When you draw, everyone's background changes to your theme's colours. The top bar shows the theme under the round, and chat says "X is drawing now! (🎃 Halloween)".

| Theme | Colours | Words |
| --- | --- | --- |
| 🎃 Halloween (default) | orange, darker orange doodles | 273 |
| 🌍 General | your original green background, unchanged | 554 |
| 🐉 Fantasy | purple | 267 |
| 🌿 Plants & Animals (pets, wild animals, fish, birds, bugs, plants, microbes, germs…) | teal | 371 |
| 🏙️ People, Places & Things | blue | 216 |
| 🍔 Food (fast food places, candy, drinks, dishes from around the world…) | red | 308 |

- Themes and their colours are in `src/shared/Themes.luau`. The words are in `src/shared/Words.luau`, by theme and then easy / medium / hard. The default theme is `Config.DEFAULT_THEME`. Easy is one simple thing a kid could draw (pumpkin, bat, cherry); medium takes more drawing (werewolf, haunted mansion, swordfish); hard is a well-known character, scene or harder-to-draw thing (Jack Skellington, platypus), never an obscure word.
- The background doodles are one image, `assets/background-doodles.png` (white lines on see-through, made by `tools/make_doodle_mask.py`). Each theme except General tints the lines and colours the screen behind them; General shows the original green tile (`Config.BACKGROUND_TILE`) exactly as before.
- `Config.BACKGROUND_DOODLES` holds that image's ID. If it's emptied, the other themes show plain colour.

Players who join partway through a round can start guessing straight away and get their first turn to draw in the next round. If the server drops below 2 players, the match is cancelled and the game goes back to waiting.

## Look & feel

The layout copies skribbl.io's, using the pixel measurements from a skribbl.io screenshot (1870 px wide: a 284 px player list, a 1141 px canvas and a 428 px chat, with 68 px player rows). The game is pinned to the top and zoomed to fill the window. The clock (grey bells, thick ring, little legs) and the pencils are drawn from shapes, and the logo flickers between two drawings like skribbl's. The logo sits above a centred game area. Below it is a flat white top bar with an alarm-clock timer, "Round X of Y" and "GUESS THIS _ _ _ _⁵". The player list shows each player's rank, name, points and avatar. Chat rows alternate in colour, with green for correct guesses and people joining, and orange for people leaving. The canvas has a deep green overlay for choosing a word, the word reveal and the winners podium. Text uses Nunito (skribbl's font), and the word uses Roboto Mono.

Animations include:
- panels sliding in when you join
- the overlay sliding down
- word choices popping in
- the timer shaking during the last 10 seconds
- "+points" floating up from players who score
- a "Guess!" / "Draw!" pop when a turn starts
- a podium that rises up
- confetti for the winners

Sounds play for:
- your turn to draw
- correct guesses
- each second of the countdown and the last 10 seconds of a turn
- the time running out
- the winner fanfare

The 🔊 button in the top bar mutes them.

## Drawing tools

- 14 basic colours, plus a large square showing the current colour
- A colour wheel for any other colour: click the 🎨 current-colour square. Drag on the wheel to pick the colour, and use the slider below it for brightness.
- 4 brush sizes
- Pen, eraser, paint bucket 🪣, undo (removes the last stroke or fill) and clear
- Over the canvas, the mouse pointer becomes a dot the size and colour of the brush, centred exactly where the line is drawn

The drawer's strokes stream to the server every 0.05s, and the server relays them to everyone else. Anyone who joins mid-turn receives the whole drawing so far.

**How the bucket works:** lines are drawn as Roblox Frames, which have no pixels to fill. So each player's game also keeps a 320×240 grid (`FILL_GRID_WIDTH`) of which colour covers each spot.
- A fill floods the matching area on that grid and draws it as rectangles.
- The rectangles sit underneath the lines and reach slightly under them, so they meet the lines with no white gaps.
- Every player builds the same grid from the same history, so a fill comes out the same on every screen.
- Eraser marks inside a filled area take the fill colour.
- Fills are limited to one every 0.25s (`MIN_FILL_INTERVAL`).

## Installing it

1. In Roblox Studio, open a place (a new Baseplate is fine) and turn on the command bar with **View → Command Bar**.
2. Open `CommandBar.lua`, copy the whole thing (it's one long line), paste it into the command bar and press **Enter**. The Output window prints `Guess & Draw installed!`.
3. To try a full match, go to the **Test** tab, set **Clients and Servers** to 2 players, and click **Start**.

The command creates three folders, all named `GuessAndDraw`: one in ReplicatedStorage, one in ServerScriptService and one in StarterPlayer → StarterPlayerScripts. Running it again replaces those folders with a fresh copy and leaves the rest of the place alone.

After editing anything in `src/`, rebuild the command with `python3 tools/make_command_bar.py`.

To change only the words, paste the much shorter `WordsCommand.lua` instead. It replaces the word list in a game that's already installed and leaves everything else alone.

### Background and sounds

Scripts can only use images and sounds that have been uploaded to Roblox, by their asset ID.

- **Background:** `assets/background-tile.png` is a seamless square cut from your `background.jpeg`. It's uploaded and set in `Config.BACKGROUND_TILE`, so it repeats across the screen at 500 px per tile (`BACKGROUND_TILE_SIZE`), which gives small, detailed doodles like skribbl.io's. It slides slowly (`BACKGROUND_SCROLL_SPEED`, 0 to keep it still; a theme can opt out with `still = true` in `Themes.luau`). Each theme's doodles are a darker shade of its own colour: high contrast, like black on orange, looks jerky when it slides.
  - If `BACKGROUND_TILE` is emptied, the full `background.jpeg` (`rbxassetid://107099391291442`) is stretched to cover the screen instead. That makes the doodles look big and a bit soft, because Roblox shrinks uploads to at most 1024 pixels wide.
- **Sounds:** the six effects in `assets/sounds/` were made for this game (`tools/make_sounds.py`). They're uploaded and their IDs are set in `Config.SOUNDS`.
  - To swap one, upload a new file (**Window → Asset Manager → Import**), right-click it → **Copy ID**, and replace that line in `src/shared/Config.luau`, then rebuild the command.
  - You can also edit ReplicatedStorage → GuessAndDraw → Config in Studio, but re-running the command overwrites edits made there.

## Files

| Path | Ends up in | What it does |
| --- | --- | --- |
| `CommandBar.lua` | — | The generated install command (don't edit by hand) |
| `WordsCommand.lua` | — | The generated words-only update command |
| `tools/make_command_bar.py` | — | Rebuilds `CommandBar.lua` from `src/` |
| `tools/make_sounds.py` | — | Synthesises the sound effects into `assets/sounds/` |
| `assets/` | Upload to Roblox | The seamless background tile, the thumbs and the sound effects |
| `src/shared/Config.luau` | ReplicatedStorage.GuessAndDraw | All tunable settings: timings, rounds, scoring, colours, brush sizes, limits |
| `src/shared/Words.luau` | ReplicatedStorage.GuessAndDraw | The word list |
| `src/server/GameServer.server.luau` | ServerScriptService.GuessAndDraw | Game loop, scoring, guess checking, text filtering, stroke relay and validation |
| `src/client/Main.client.luau` | StarterPlayerScripts.GuessAndDraw | Screen layout, drawing input, live canvas, chat and game-state screens |
| `src/client/CanvasRenderer.luau` | StarterPlayerScripts.GuessAndDraw | Draws strokes and bucket fills, and keeps the fill grid |
| `src/client/Theme.luau` | StarterPlayerScripts.GuessAndDraw | Colours and fonts |
| `src/client/Ui.luau` | StarterPlayerScripts.GuessAndDraw | Panels, buttons, avatars and the tween animations |
| `src/client/Sounds.luau` | StarterPlayerScripts.GuessAndDraw | Plays the sound effects; handles mute |
| `src/client/Effects.luau` | StarterPlayerScripts.GuessAndDraw | Confetti and floating "+points" text |
| `src/client/ColorPicker.luau` | StarterPlayerScripts.GuessAndDraw | The colour wheel popup |

## Notes

- The game is UI-only: `Config.SPAWN_CHARACTERS = false` means nobody gets an avatar. Set it to `true` if you add a lobby world.
- Roblox's built-in chat is hidden, so guesses can't be typed where everyone would see them. All chat goes through `TextService` filtering, as Roblox requires. In Studio, filtering doesn't change the text.
- The server only accepts drawing from the current drawer and checks every packet (colour and size ranges, point counts, rate limits, a total size cap).
- The whole game area is designed at 1870×1086 and zoomed as one piece to fit the window below Roblox's topbar, so it keeps skribbl.io's proportions and spacing on any screen.
- Possible next steps: saving `Wins` with DataStores, custom word packs, and a vote to skip a drawer.
