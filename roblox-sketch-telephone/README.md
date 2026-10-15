# Sketch Telephone (Roblox)

A Telestrations-style drawing telephone game for Roblox: draw → guess → draw → guess, then a page-by-page reveal of every sketchbook.

## Setup in Roblox Studio

1. Create a new **Baseplate** place.
2. In **ReplicatedStorage**, add two **ModuleScripts**:
   - `Config` → paste `Config.lua`
   - `DrawingRenderer` → paste `DrawingRenderer.lua`
3. In **ServerScriptService**, add a **Script** named `GameServer` → paste `GameServer.server.lua`
4. In **StarterPlayer → StarterPlayerScripts**, add a **LocalScript** named `GameClient` → paste `GameClient.client.lua`

The names must match exactly. You don't build any GUI by hand, because the LocalScript creates the whole screen in code.

## Testing

- Use **Test → Clients and Servers**, pick 2–4 players and press **Start**. Each window is a separate player.
- Text filtering only works properly in a published game. In Studio, guesses may come through unchanged or as `####`.

## Publishing

- **File → Publish to Roblox**, then in **Game Settings → Places** set max players to about 8.
- The game sends every guess through Roblox's text filter (this is required).
- Drawings can't be filtered automatically, so consider adding a report or vote-kick button before the game gets big.

## Tuning

Everything is in `Config`: timers, minimum players, max rounds, colors, brush sizes and the word list.
