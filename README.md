![Sunfish logo](https://raw.github.com/borko17/sunfish-lua/master/docs/logo/sunfish01.jpeg)

# sunfish.lua

A Lua port of [Sunfish](https://github.com/thomasahle/sunfish), a compact chess engine originally written in Python by [Thomas Ahle](https://github.com/thomasahle), adapted to run on Android inside [Yantra Launcher Pro](https://github.com/coderGtm/yantra-app-launcher) (Luaj-jse 3.0.1).

Originally based on the Lua port by [Soumith Chintala](https://github.com/soumith), this version has been substantially extended and adapted for the Android/Luaj-jse environment.

## Origin

- **Original algorithm & Python implementation:** [Thomas Ahle](https://github.com/thomasahle) — [thomasahle/sunfish](https://github.com/thomasahle/sunfish) (also documented at [chessprogramming.org/Sunfish](https://www.chessprogramming.org/Sunfish))
- **Initial Lua transpilation/port:** [Soumith Chintala](https://github.com/soumith) — [soumith/sunfish.lua](https://github.com/soumith/sunfish.lua)
- **Android / Yantra Launcher Pro adaptation and extensions:** [Borko Danilović](https://github.com/borko17), with help from Claude AI

Sunfish itself draws heavily on [Micro-Max by Geert Muller](http://home.hccnet.nl/h.g.muller/max-src2.html) and [PyChess](http://pychess.org).

## What this version changes

The engine's search and evaluation logic was adapted to run well in a constrained mobile Lua environment (Luaj-jse 3.0.1):

- **Node-budget search** instead of a wall-clock timer
- Configurable search strength through `nN`
- **Smaller, budget-scaled transposition table**, sized according to the selected node budget
- Reduced memory requirements for mobile execution
- **Zugzwang guard** on null-move pruning
- **Endgame king-centralization table**, used in bare-king endgames to improve convergence
- **Depth-scaled quiescence threshold** for improved tactical search at the same node budget
- Search statistics and node-count reporting
- Mate-score handling and mate detection
- Adjustments for the limitations of Luaj-jse on Android

## Chess features

The application layer adds functionality beyond the original compact engine:

- Full legal-move validation
- Check detection
- Checkmate detection
- Stalemate detection
- Threefold-repetition detection
- Fifty-move rule detection
- Insufficient-material detection
- Move history
- Last-move tracking
- Captured-piece tracking for both sides
- Pawn promotion with choice of **Queen, Rook, Bishop, or Knight**
- Unicode chess-piece display
- Plain-letter display
- Runtime Unicode/letter display toggle
- Board annotations
- Position snapshots
- Compact text-based save/load
- Compatibility with multiple save/position formats
- Mate-in-1 puzzle mode
- Random Mate-in-1 puzzle generation
- Progressive puzzle hints
- Puzzle save/load
- In-app Help (`h`)
- In-app About (`?`)
- Online update checker (`u`)

## Save / Load formats

The `l` command can load saved positions in several formats.

### Normal game mode

Three formats are supported.

### 1. Full game save

The complete format contains game state, history, counters, captures, starting position and current board:

```text
c:11|bc:11|ep:0|last:e7e6|ucap:-|ecap:-|wm:1|bm:1|hc:0|next:w|hist:a2a4,e7e6|start:rnbqkbnr;pppppppp;8;8;8;8;PPPPPPPP;RNBQKBNR|board:rnbqkbnr;pppp1ppp;4p3;8;P7;8;1PPPPPPP;RNBQKBNR