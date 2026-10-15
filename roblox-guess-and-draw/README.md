# Guess & Draw (Roblox)

A multiplayer drawing and guessing game. One player draws a secret word and everyone else races to guess it in chat. The others watch the drawing appear live, stroke by stroke.

## How a match plays

- **Match:** a batch of `ROUNDS_PER_MATCH` rounds (3 by default). It starts once `MIN_PLAYERS` (2) are in the server.
- **Round:** every player gets one turn as the drawer.
- **Turn:**
  1. **Choosing (15s):** the drawer picks one of 3 words. If they don't pick, one is chosen at random.
  2. **Drawing (80s):** guessers type in the chat box. The word shows as blanks (`_ _ _ _ _ (5)`), and letters are revealed as hints at 50% and 75% of the time.
     - A correct guess earns 50–300 points; the faster you guess, the more you get. The first correct guess earns a +50 bonus.
     - The drawer earns 50 points for each correct guess.
     - A guess one letter off gets a private "is close!" message.
     - Correct guesses are never shown to other players. Once you've guessed, you can only chat with the drawer and the other players who guessed, so nobody can leak the answer.
     - The turn ends early when everyone has guessed or the drawer leaves.
  3. **Reveal (6s):** shows the word and the points everyone earned that turn.
- **Match end:** a podium shows 1st, 2nd and 3rd place (tied players share a place). Each 1st-place winner gets +1 `Wins` on the leaderboard. A new match then starts automatically.

Players who join partway through a round can start guessing straight away and get their first turn to draw in the next round. If the server drops below 2 players, the match is cancelled and the game goes back to waiting.

## Drawing tools

- 14 basic colours
- 4 brush sizes
- Pen, eraser, undo (removes the last stroke) and clear
- A brush-size preview that follows the cursor

The drawer's strokes stream to the server every 0.05s, and the server relays them to everyone else. Anyone who joins mid-turn receives the whole drawing so far.

## Running it

**Quickest:** open `GuessAndDraw.rbxl` in Roblox Studio. To try a full match, go to the **Test** tab, set **Clients and Servers** to 2 players, and click **Start**.

**With Rojo (for editing the code):**

```sh
rojo serve          # then connect from the Rojo plugin in Studio
rojo build default.project.json -o GuessAndDraw.rbxl   # rebuild the place file
```

## Files

| Path | Ends up in | What it does |
| --- | --- | --- |
| `src/shared/Config.luau` | ReplicatedStorage.Shared | All tunable settings: timings, rounds, scoring, colours, brush sizes, limits |
| `src/shared/Words.luau` | ReplicatedStorage.Shared | The word list |
| `src/server/GameServer.server.luau` | ServerScriptService.Server | Game loop, scoring, guess checking, text filtering, stroke relay and validation |
| `src/client/Main.client.luau` | StarterPlayerScripts.Client | The whole UI, drawing input and live canvas updates |
| `src/client/CanvasRenderer.luau` | StarterPlayerScripts.Client | Turns stroke points into on-screen line segments |

## Notes

- The game is UI-only: `Config.SPAWN_CHARACTERS = false` means nobody gets an avatar. Set it to `true` if you add a lobby world.
- Roblox's built-in chat is hidden, so guesses can't be typed where everyone would see them. All chat goes through `TextService` filtering, as Roblox requires. In Studio, filtering doesn't change the text.
- The server only accepts drawing from the current drawer and checks every packet (colour and size ranges, point counts, rate limits, a total size cap).
- Possible next steps: a fill bucket, saving `Wins` with DataStores, custom word packs, and a vote to skip a drawer.
