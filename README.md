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

#### 1. Full game save

The complete format contains game state, history, counters, captures, starting position and current board:

```text
c:11|bc:11|ep:0|last:e7e6|ucap:-|ecap:-|wm:1|bm:1|hc:0|next:w|hist:a2a4,e7e6|start:rnbqkbnr;pppppppp;8;8;8;8;PPPPPPPP;RNBQKBNR|board:rnbqkbnr;pppp1ppp;4p3;8;P7;8;1PPPPPPP;RNBQKBNR
```

This is the preferred format when the complete game state needs to be restored. It can preserve information such as:

- Current board
- Starting position
- Move history
- Side to move
- Last move
- Half-move counter
- Captured pieces
- En-passant state
- Move counters

#### 2. Board-only format

A position can be saved as only the encoded board:

```text
board:rnbqkbnr;pppp1ppp;4p3;8;P7;8;1PPPPPPP;RNBQKBNR
```

This restores the board position without the complete game history and associated state.

#### 3. Plain 8×8 board

A position can also be entered as eight lines containing eight characters each:

```text
....k...
........
........
........
........
........
........
R...K..R
```

This is useful for entering arbitrary positions manually. The plain board format is interpreted as a position rather than a complete game save.

### Puzzle mode save / load

Mate-in-1 puzzle mode uses the position-oriented formats:

**Board-only format**

```text
board:rnbqkbnr;pppp1ppp;4p3;8;P7;8;1PPPPPPP;RNBQKBNR
```

**Plain 8×8 board**

```text
....k...
........
........
........
........
........
........
R...K..R
```

The full game-state save format is intended for normal games, while puzzle mode only needs the board position.

### Position snapshots

The `sN` command saves a previous position from the current move history. For example:

```text
s15
```

saves the position corresponding to history entry 15. This allows a position from an ongoing game to be extracted without manually reconstructing it.

### What the save formats mean

The compact board representation consists of eight ranks separated by semicolons:

```text
rank8;rank7;rank6;rank5;rank4;rank3;rank2;rank1
```

Numbers represent consecutive empty squares. For example:

```text
rnbqkbnr;pppppppp;8;8;8;8;PPPPPPPP;RNBQKBNR
```

represents the normal starting position. The full save format wraps this board representation together with additional game-state fields.

### Draw detection

The application recognizes:

- Threefold repetition
- Fifty-move rule
- Insufficient material
- Stalemate

Threefold repetition is tracked using the position history.

## Mate-in-1 puzzle mode

Enter:

```text
m1
```

to start the Mate-in-1 puzzle generator. The program generates a position where the side to move has a legal mate in one and verifies the generated position before presenting it.

### Puzzle features

- Random Mate-in-1 generation
- Legal-position validation
- Mate verification
- Progressive hints
- Full-solution hint
- Unicode/letter display toggle
- Puzzle save/load
- New puzzle generation

### Puzzle hints

Hints can progressively reveal:

- Which piece type delivers mate
- Which square the mating piece moves from
- Which square it moves to
- The complete solution

## Usage

Load `sunfish.lua` as a script in Yantra Launcher Pro.

### Normal game commands

| Key | Action |
|---|---|
| `e2e4` (etc.) | Enter a move in coordinate notation |
| `h` | Show help |
| `?` | Show About / project information |
| `d` | Toggle display mode (Unicode ↔ letters) |
| `a` | Toggle board annotations |
| `s` | Save the current game |
| `sN` | Save position as of history entry N (e.g. `s15`) |
| `l` | Load a saved game or position |
| `nN` | Change engine node budget in the range 1000–50000 |
| `r` | Resign |
| `n` | Start a new game |
| `u` | Check for a sunfish.lua update |
| `m1` | Enter Mate-in-1 puzzle mode |
| `q` | Quit |

### Engine strength

The `nN` command controls the engine's node budget. For example:

```text
n4000
```

uses a 4000-node search budget. In general:

- Lower N = faster / weaker
- Higher N = slower / stronger

The available range is `n1000` to `n50000`. Actual playing strength depends on the position and device performance.

### Mate-in-1 puzzle mode commands

| Key | Action |
|---|---|
| `h` | Show puzzle help and hints |
| `d` | Toggle display mode (Unicode ↔ letters) |
| `s` | Save current puzzle |
| `l` | Load puzzle |
| `n` | Generate a new puzzle |
| `q` | Exit puzzle mode and return to normal game |

## Display configuration

Display mode and board annotations can be configured at the top of the script:

```lua
local USE_UNICODE_PIECES = false
local SHOW_ANNOTATIONS = true
local NODES_SEARCHED = 2000
```

### Unicode mode

Uses Unicode chess symbols:

```text
♔ ♕ ♖ ♗ ♘ ♙
♚ ♛ ♜ ♝ ♞ ♟
```

### Letter mode

Uses ordinary ASCII letters:

```text
K Q R B N P
k q r b n p
```

Letter mode is useful when the terminal font does not provide reliable chess-symbol support.

### Board annotations

When enabled, annotations can display additional board information such as:

- Last move
- Check/guard information
- Move-related markers

Annotations can be toggled during a game with `a`.

## Promotion

When a pawn reaches the last rank, the player can select:

- `Q` — Queen
- `R` — Rook
- `B` — Bishop
- `N` — Knight

Underpromotion is therefore supported instead of automatically promoting every pawn to a queen.

## Update checker

The command `u` checks for a newer version of sunfish.lua. This allows the script to check the project's remote repository from within the Yantra Launcher Pro environment.

## Screenshots

Letters mode:

![letters](https://github.com/borko17/sunfish.lua/blob/main/docs%2Fscreenshots%2Fscreenshot01.jpg)

Unicode mode:

![unicode](https://github.com/borko17/sunfish.lua/blob/main/docs%2Fscreenshots%2Fscreenshot02.jpg)


## Requirements

- Yantra Launcher Pro (Luaj-jse 3.0.1)
- Android device capable of running Yantra Launcher Pro
- A monospaced font is recommended for board alignment
- For Unicode piece mode, a font with good chess-symbol coverage is recommended

Recommended fonts include:

- DejaVu Sans Mono
- Julia Mono
- Everson Mono
- Unifont

If Unicode rendering is unreliable, use letter mode with `d`, or set:

```lua
local USE_UNICODE_PIECES = false
```

## Architecture

The project can broadly be divided into two layers.

### Engine layer

Derived from the Sunfish engine architecture:

- 120-square padded board representation
- Move generation
- Position evaluation
- Piece-square tables
- MTD-bi search
- Quiescence search
- Null-move pruning
- Transposition table
- Move ordering
- Mate scoring

### Application layer

Added and extended for the Android/Lua environment:

- Interactive command interface
- Legal-move validation
- Check/checkmate/stalemate handling
- Draw detection
- Move history
- Save/load
- Position snapshots
- Unicode rendering
- Board annotations
- Captured-piece display
- Promotion selection
- Mate-in-1 puzzle generator
- Puzzle hints
- Puzzle save/load
- Update checker
- Help and About screens

## Attribution

**Thomas Ahle**
Original Sunfish engine and Python implementation:
https://github.com/thomasahle/sunfish

**Soumith Chintala**
Initial Lua port/transpilation:
https://github.com/soumith/sunfish.lua

**Borko Danilović**
Android / Yantra Launcher Pro adaptation and extensions:
https://github.com/borko17/sunfish-lua

The current version includes substantial modifications to the original Lua port, including the Android adaptation, node-budget search configuration, legal chess-game handling, save/load system, display system, puzzle system, draw detection, annotations, promotion handling, and other application features.

### AI assistance

Parts of the adaptation, debugging, refactoring, documentation, and development process were performed with assistance from Claude AI. AI assistance does not replace or alter attribution to the original Sunfish authors and upstream projects.

## License

This project is distributed under GNU GPL v3, following the licensing of the current original Sunfish project. See `LICENSE.md` for the full license text.

The project also contains historical code lineage from the Lua port by Soumith Chintala. The original [soumith/sunfish.lua](https://github.com/soumith/sunfish.lua) repository contains its own attribution and licensing information.

For upstream attribution and licensing information, see:

- [Thomas Ahle / Sunfish](https://github.com/thomasahle/sunfish)
- [Soumith Chintala / sunfish.lua](https://github.com/soumith/sunfish.lua)

## Status

This is a lightweight, self-contained chess engine and terminal chess application for Android (Yantra Launcher Pro / Luaj-jse 3.0.1), built for:

- Terminal-based chess
- Chess-engine experimentation
- Compact text-based position storage
- Mate-in-1 puzzle generation

It is not intended to compete with modern high-performance chess engines such as Stockfish. The goal is a compact, modifiable and self-contained chess engine that can run directly on Android through Lua, while retaining the small and elegant spirit of the original Sunfish.
