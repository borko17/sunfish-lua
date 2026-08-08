# sunfish-lua
Lua port of the Sunfish chess engine for Android/Yantra Launcher

# sunfish.lua

A Lua port of [Sunfish](https://github.com/thomasahle/sunfish), a compact chess engine originally written in Python by Thomas Ahle, adapted to run on Android inside [Yantra Launcher](https://github.com/darkxsystem/yantra) (Luaj-jse 3.0.1).

## Origin

- **Original algorithm & Python implementation:** [Thomas Ahle](https://github.com/thomasahle) — [thomasahle/sunfish](https://github.com/thomasahle/sunfish)
- **Initial Lua transpilation:** attributed to Soumith Chintala
- **Android / Yantra Launcher adaptation:** [borko17](https://github.com/borko17), with help from Claude (Anthropic)

This project is a derivative work of the original Sunfish engine and is distributed under the same BSD-2-Clause license (see [`LICENSE`](./LICENSE)).

## What this port changes

Yantra Launcher's Lua environment (Luaj-jse 3.0.1 on Android) has constraints the original engine wasn't written for — no timers to budget search by, a much smaller heap than a desktop Python process, and (on newer Android versions) SELinux blocking shell-out calls like `io.popen`. The core search and evaluation logic changes to fit that:

- **Node-budget search** instead of a wall-clock timer
- **Smaller, budget-scaled transposition table**, sized off the node budget so it doesn't thrash mid-search
- **Zugzwang guard** on null-move pruning, so passing isn't assumed safe near mate/endgame material swings
- **Endgame king-centralization table**, swapped in once either side is down to a bare king, so won K+R/K+Q endings actually converge instead of shuffling forever
- **Depth-scaled quiescence threshold** for slightly better tactics at the same node budget

## Extra features on top of the engine

- Full legal-move, check, and stalemate detection
- Save & load games via compact text codes
- Unicode chess symbols or plain-letter display, toggleable
- Check / guard / last-move markers on the board
- Captured-piece tracking for both sides
- Mate-in-1 puzzle mode (`m1`) with a random puzzle generator and hints
- In-app help (`h`) and about (`?`) screens

## Usage

Load `sunfish.lua` as a script in Yantra Launcher. In-game commands:

| Key | Action |
|-----|--------|
| `e2e4` (etc.) | Enter a move in coordinate notation |
| `h` | Show help |
| `?` | Show about screen |
| `d` | Toggle display mode (Unicode ↔ letters) |
| `a` | Toggle board annotations |
| `s` | Save game (generates a code) |
| `l` | Load a saved game |
| `r` | Resign |
| `n` | Start a new game |
| `m1` | Enter mate-in-1 puzzle mode |
| `q` | Quit |

Display mode and annotation defaults can be set at the top of the script:

```lua
local USE_UNICODE_PIECES = false
local SHOW_ANNOTATIONS = true
```

## Requirements

- [Yantra Launcher](https://github.com/darkxsystem/yantra) (Luaj-jse 3.0.1)
- A monospaced font is recommended for board alignment; for Unicode piece mode, a font with good chess-symbol coverage (DejaVu Sans Mono, Julia Mono, Everson Mono, or GNU Unifont) is recommended.

## License

This project is a derivative of Sunfish and is distributed under the **BSD-2-Clause license**, with the original copyright retained. See [`LICENSE`](./LICENSE) for the full text.
