# sunfish-lua
Lua port of the Sunfish chess engine for Android/Yantra Launcher

# sunfish.lua

A Lua port of [Sunfish](https://github.com/thomasahle/sunfish), a compact chess engine originally written in Python by Thomas Ahle, adapted to run on Android inside [Yantra Launcher](https://github.com/coderGtm/yantra-app-launcher) (Luaj-jse 3.0.1).

## Origin

- **Original algorithm & Python implementation:** [Thomas Ahle](https://github.com/thomasahle) — [thomasahle/sunfish](https://github.com/thomasahle/sunfish)
- **Initial Lua transpilation:** attributed to Soumith Chintala
- **Android / Yantra Launcher adaptation:** [borko17](https://github.com/borko17), with help from Claude AI

## What this port changes

The engine's search and evaluation logic was adapted to run well on a mobile Lua environment (Luaj-jse 3.0.1):

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

## Display modes

**Unicode symbols:**

```
  ╔══════════════════════════╗
8 ║  ♜  ♞  ♝  ♛  ♚  ♝  ♞  ♜  ║
7 ║  ♟  ♟  ♟  ♟  ♟  ♟  ♟  ♟  ║
6 ║  •  ◦  •  ◦  •  ◦  •  ◦  ║
5 ║  ◦  •  ◦  •  ◦  •  ◦  •  ║
4 ║  •  ◦  •  ◦  •  ◦  •  ◦  ║
3 ║  ◦  •  ◦  •  ◦  •  ◦  •  ║
2 ║  ♙  ♙  ♙  ♙  ♙  ♙  ♙  ♙  ║
1 ║  ♖  ♘  ♗  ♕  ♔  ♗  ♘  ♖  ║
  ╚══════════════════════════╝
     a  b  c  d  e  f  g  h
```

**Letter symbols:**

```
  +--------------------------+
8 |  r  n  b  q  k  b  n  r  |
7 |  p  p  p  p  p  p  p  p  |
6 |  :  .  :  .  :  .  :  .  |
5 |  .  :  .  :  .  :  .  :  |
4 |  :  .  :  .  :  .  :  .  |
3 |  .  :  .  :  .  :  .  :  |
2 |  P  P  P  P  P  P  P  P  |
1 |  R  N  B  Q  K  B  N  R  |
  +--------------------------+
     a  b  c  d  e  f  g  h
```



- [Yantra Launcher](https://github.com/coderGtm/yantra-app-launcher) (Luaj-jse 3.0.1)
- A monospaced font is recommended for board alignment; for Unicode piece mode, a font with good chess-symbol coverage (DejaVu Sans Mono, Julia Mono, Everson Mono, or GNU Unifont) is recommended.

## License

This project is a derivative of Sunfish and is distributed under **GNU GPL v3**, as required by the original project's license. See [`LICENSE.md`](./LICENSE.md) for the full text.
