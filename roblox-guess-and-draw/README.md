# Guess & Draw (Roblox)

A multiplayer drawing and guessing game. One player draws a secret word and everyone else races to guess it in chat. The others watch the drawing appear live, stroke by stroke.

## How a match plays

- **Match:** a batch of `ROUNDS_PER_MATCH` rounds (3 by default). It starts once `MIN_PLAYERS` (2) are in the server.
- **Round:** every player gets one turn as the drawer.
- **Turn:**
  1. **Choosing (15s):** the drawer picks one of 3 words. If they don't pick, one is chosen at random.
     - The small 🔒 **Custom** button beside the choices lets the drawer type any word they like after entering a password. Opening it gives them at least 25s (`CUSTOM_WORD_TIME`).
     - The password is `CUSTOM_WORD_PASSWORD` at the top of `src/server/GameServer.server.luau`. It stays on the server, so players can't read it, and 5 wrong tries lock that player out of the form.
     - Custom words must be 2-30 letters (spaces, `-` and `'` allowed) and pass Roblox's text filter.
  2. **Drawing (80s):** guessers type in the chat box. The word shows as blanks (`_ _ _ _ _ (5)`), and letters are revealed as hints at 50% and 75% of the time.
     - A correct guess earns 50–300 points; the faster you guess, the more you get. The first correct guess earns a +50 bonus.
     - The drawer earns 50 points for each correct guess.
     - A guess one letter off gets a private "is close!" message.
     - Correct guesses are never shown to other players. Once you've guessed, you can only chat with the drawer and the other players who guessed, so nobody can leak the answer.
     - The turn ends early when everyone has guessed or the drawer leaves.
  3. **Reveal (6s):** shows the word and the points everyone earned that turn.
- **Match end:** a podium shows 1st, 2nd and 3rd place (tied players share a place). Each 1st-place winner gets +1 `Wins` on the leaderboard. A new match then starts automatically.

Players who join partway through a round can start guessing straight away and get their first turn to draw in the next round. If the server drops below 2 players, the match is cancelled and the game goes back to waiting.

## Look & feel

The layout copies skribbl.io's. The logo sits above a centred game area. Below it is a flat white top bar with an alarm-clock timer, "Round X of Y" and "GUESS THIS _ _ _ _⁵". The player list shows each player's rank, name, points and avatar. Chat rows alternate in colour, with green for correct guesses and people joining, and orange for people leaving. The canvas has a deep green overlay for choosing a word, the word reveal and the winners podium. Text uses Nunito (skribbl's font), and the word uses Roboto Mono.

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

### Background and sounds

Scripts can only use images and sounds that have been uploaded to Roblox, by their asset ID.

- **Background:** `assets/background-tile.png` is a seamless square cut from your `background.jpeg`. It's uploaded and set in `Config.BACKGROUND_TILE`, so it repeats across the screen at 500 px per tile (`BACKGROUND_TILE_SIZE`) and drifts slowly, which gives small, detailed doodles like skribbl.io's.
  - If `BACKGROUND_TILE` is emptied, the full `background.jpeg` (`rbxassetid://107099391291442`) is stretched to cover the screen instead. That makes the doodles look big and a bit soft, because Roblox shrinks uploads to at most 1024 pixels wide.
- **Sounds:** the six effects in `assets/sounds/` were made for this game (`tools/make_sounds.py`). They're uploaded and their IDs are set in `Config.SOUNDS`.
  - To swap one, upload a new file (**Window → Asset Manager → Import**), right-click it → **Copy ID**, and replace that line in `src/shared/Config.luau`, then rebuild the command.
  - You can also edit ReplicatedStorage → GuessAndDraw → Config in Studio, but re-running the command overwrites edits made there.

## Files

| Path | Ends up in | What it does |
| --- | --- | --- |
| `CommandBar.lua` | — | The generated install command (don't edit by hand) |
| `tools/make_command_bar.py` | — | Rebuilds `CommandBar.lua` from `src/` |
| `tools/make_sounds.py` | — | Synthesises the sound effects into `assets/sounds/` |
| `assets/` | Upload to Roblox | The seamless background tile and the sound effects |
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
- The whole game area is designed at 1500×889 and zoomed out as one piece to fit the window below Roblox's topbar, so it keeps skribbl.io's proportions on any screen.
- Possible next steps: saving `Wins` with DataStores, custom word packs, and a vote to skip a drawer.
