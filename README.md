sunfish.lua

"Sunfish logo" (https://raw.github.com/borko17/sunfish-lua/master/docs/logo/sunfish01.jpeg)

A compact Lua chess engine and terminal chess application for Android, based on "Sunfish" (https://github.com/thomasahle/sunfish), the minimalist chess engine originally written in Python by "Thomas Ahle" (https://github.com/thomasahle).

This version is adapted and extended to run on Android inside "Yantra Launcher Pro" (https://github.com/coderGtm/yantra-app-launcher), using Luaj-jse 3.0.1.

It started as a Lua port of Sunfish and has evolved into a substantially extended standalone chess application with legal-move handling, game-state management, save/load support, Unicode display, annotations, draw detection, and a Mate-in-1 puzzle system.

---

Origin and lineage

The project has three main stages of development:

- Original engine and Python implementation: "Thomas Ahle" (https://github.com/thomasahle) — "thomasahle/sunfish" (https://github.com/thomasahle/sunfish)
- Initial Lua port/transpilation: "Soumith Chintala" (https://github.com/soumith) — "soumith/sunfish.lua" (https://github.com/soumith/sunfish.lua)
- Android / Yantra Launcher Pro adaptation and extensions: "Borko Danilović" (https://github.com/borko17), with assistance from Claude AI

The original Sunfish project describes itself as a small Python chess engine and currently uses GNU GPL v3. The original Soumith Lua repository identifies itself as a Lua port of Sunfish. See the respective upstream repositories for their original attribution and licensing information.

Sunfish's algorithmic heritage also includes ideas and inspiration from:

- "Micro-Max by Geert Muller" (http://home.hccnet.nl/h.g.muller/max-src2.html)
- "PyChess" (http://pychess.org)
- "Chessprogramming.org — Sunfish" (https://www.chessprogramming.org/Sunfish)

---

What this version changes

The original Sunfish search model was adapted for a constrained mobile Lua runtime.

Search and engine adaptations

- Node-budget search instead of a wall-clock timer
- Configurable engine strength through "nN"
- Budget-scaled transposition table, allowing the table size to adapt to the selected search budget
- Reduced memory requirements suitable for Luaj-jse on Android
- Zugzwang guard around null-move pruning
- Endgame king-centralization evaluation
- Depth-scaled quiescence threshold
- Move ordering and search adjustments for mobile execution
- Search statistics and node-count reporting
- Mate detection and mate-score handling

The engine therefore retains the compact Sunfish philosophy while using a search configuration better suited to an Android scripting environment.

---

Chess functionality

The application provides substantially more than the original minimal engine interface.

Board and move handling

- Coordinate move input such as "e2e4"
- Legal-move validation
- Check detection
- Checkmate detection
- Stalemate detection
- Captured-piece tracking
- Last-move tracking
- Board annotations
- Unicode chess-piece display
- Plain-letter board display
- Runtime switching between Unicode and letter display
- Configurable default display mode
- Configurable board annotations

Pawn promotion

When a pawn reaches the final rank, promotion can be selected from:

- Queen
- Rook
- Bishop
- Knight

This allows underpromotion instead of automatically forcing a queen.

---

Draw detection

The application recognizes several draw conditions:

- Threefold repetition
- Fifty-move rule
- Insufficient material
- Stalemate

Threefold repetition is tracked from the position history rather than relying only on the current board.

---

Save and load

Games and positions can be represented as compact text strings.

The loader accepts three different formats in normal game mode.

1. Full game save

A complete save contains game-state information together with the board:

c:11|bc:11|ep:0|last:e7e6|ucap:-|ecap:-|wm:1|bm:1|hc:0|next:w|hist:a2a4,e7e6|start:rnbqkbnr;pppppppp;8;8;8;8;PPPPPPPP;RNBQKBNR|board:rnbqkbnr;pppp1ppp;4p3;8;P7;8;1PPPPPPP;RNBQKBNR

This is the most complete format.

It can preserve information such as:

- current board
- starting position
- move history
- side to move
- last move
- half-move counter
- captured pieces
- en-passant information
- move counters

2. Board-only save

A save can contain only the encoded board:

board:rnbqkbnr;pppp1ppp;4p3;8;P7;8;1PPPPPPP;RNBQKBNR

This restores the board position without the additional game history.

3. Plain 8×8 board

A position can also be loaded directly as eight board rows:

....k...
........
........
........
........
........
........
R...K..R

This is useful for quickly entering arbitrary positions.

Important

The full save format preserves considerably more game state than the board-only and plain-board formats.

Board-only and plain-board loading should therefore be considered position loading, rather than a complete restoration of an entire game.

---

Position snapshots

The "sN" command allows a previous position from the current game history to be saved.

For example:

s15

saves the position corresponding to history entry 15.

This is useful for extracting a position from an ongoing game without starting a new game or manually reconstructing the position.

---

Mate-in-1 puzzles

The application includes a dedicated Mate-in-1 puzzle mode.

Enter:

m1

The program generates a position in which the side to move has a mate in one.

The generator verifies the tactical condition rather than simply producing a random board.

Puzzle features

- Random Mate-in-1 generation
- Legal position checking
- Automatic mate-in-1 verification
- Hint system
- Unicode/letter display switching
- Puzzle save/load
- New puzzle generation
- Full solution display

Puzzle hints

The hint system can progressively reveal:

- which piece type delivers mate
- which square the mating piece moves from
- which square it moves to
- the complete solution

The hints are designed to reveal progressively more information rather than immediately giving away the answer.

---

Save/load in puzzle mode

Puzzle mode accepts the two position-oriented formats:

Board-only format

board:rnbqkbnr;pppp1ppp;4p3;8;P7;8;1PPPPPPP;RNBQKBNR

Plain 8×8 board

....k...
........
........
........
........
........
........
R...K..R

The full normal-game save format is intended for restoring complete game state and is not required for puzzle positions.

---

Commands

Normal game

Command| Action
"e2e4"| Enter a chess move in coordinate notation
"h"| Show help
"?"| Show About / project information
"d"| Toggle Unicode ↔ letter display
"a"| Toggle board annotations
"s"| Save the current game
"sN"| Save position from history entry "N"
"l"| Load a saved game or position
"nN"| Set engine node budget, from 100 to 50000
"r"| Resign
"n"| Start a new game
"u"| Check for a newer "sunfish.lua" version
"m1"| Enter Mate-in-1 puzzle mode
"q"| Quit

Engine strength

For example:

n4000

sets a search budget of 4000 nodes.

In general:

- lower "N" = faster / weaker
- higher "N" = slower / stronger

The available range is:

n100

through:

n50000

The exact playing strength depends on the position and device performance.

---

Mate-in-1 puzzle commands

Command| Action
"h"| Show puzzle help / hints
"d"| Toggle Unicode ↔ letter display
"s"| Save the current puzzle
"l"| Load a puzzle position
"n"| Generate a new puzzle
"q"| Exit puzzle mode

---

Display configuration

The default display mode can be configured near the beginning of the script:

local USE_UNICODE_PIECES = false
local SHOW_ANNOTATIONS = true

Unicode mode

Uses Unicode chess symbols such as:

♔ ♕ ♖ ♗ ♘ ♙
♚ ♛ ♜ ♝ ♞ ♟

Letter mode

Uses ordinary ASCII letters:

K Q R B N P
k q r b n p

Letter mode is useful on terminals or fonts that do not provide reliable chess-symbol support.

---

Board annotations

When annotations are enabled, the board can show additional information such as:

- last move
- check/guard information
- move-related markers

Annotations can be toggled during the game with:

a

---

Update checker

The command:

u

checks whether a newer version of "sunfish.lua" is available.

This is intended for the Yantra Launcher Pro environment and allows the script to check the project's remote source without requiring the user to manually inspect the repository.

---

Why this version exists

The original Sunfish is intentionally small and educational. Its compact design makes it an interesting base for experimentation.

This project takes that compact engine and adapts it to a very different environment:

Python → Lua → Luaj-jse → Android → Yantra Launcher Pro

The result is not intended to be a replacement for large modern chess engines. Instead, it is a lightweight, self-contained chess engine and chess application that can run directly inside an Android launcher/script environment with very few dependencies.

---

Architecture

At a high level, the project can be divided into two layers.

Engine layer

Derived from the Sunfish search architecture:

- board representation
- move generation
- position evaluation
- piece-square tables
- search
- quiescence search
- null-move pruning
- transposition table
- mate scoring
- move ordering

Application layer

Added and extended for the Android/Lua environment:

- interactive command interface
- legal-move validation
- check/checkmate/stalemate handling
- draw detection
- move history
- save/load
- position snapshots
- Unicode rendering
- board annotations
- captured-piece display
- promotion selection
- Mate-in-1 puzzles
- puzzle hints
- update checking
- in-app Help and About

This separation makes it possible to experiment with the engine without losing the usability of the complete terminal chess application.

---

File and save format philosophy

The save format is deliberately text-based.

This makes saved positions:

- human-readable
- easy to copy
- easy to store in text files
- easy to transfer between devices
- suitable for terminal-based workflows
- independent of a binary serialization format

The compact board representation uses semicolon-separated ranks:

rank8;rank7;rank6;rank5;rank4;rank3;rank2;rank1

For example:

rnbqkbnr;pppppppp;8;8;8;8;PPPPPPPP;RNBQKBNR

A number represents consecutive empty squares in the same rank.

---

Requirements

- "Yantra Launcher Pro" (https://github.com/coderGtm/yantra-app-launcher)
- Luaj-jse 3.0.1
- Android device capable of running Yantra Launcher Pro
- A monospaced terminal font is recommended for correct board alignment

For Unicode chess pieces, a font with good chess-symbol coverage is recommended.

Examples include:

- "DejaVu Sans Mono" (https://github.com/dejavu-fonts/dejavu-fonts/releases)
- "Julia Mono" (https://github.com/cormullion/juliamono/releases)
- "Everson Mono" (https://www.evertype.com/emono/)
- "Unifont" (https://github.com/multitheftauto/unifont/releases)

If Unicode rendering is unreliable, switch to letter mode with:

d

or set:

local USE_UNICODE_PIECES = false

---

Screenshots

Letters mode

"Letters mode" (docs/screenshots/screenshot01.jpg)

Unicode mode

"Unicode mode" (docs/screenshots/screenshot02.jpg)

---

Project structure

A typical repository layout is:

sunfish-lua/
├── sunfish.lua
├── README.md
├── LICENSE.md
└── docs/
    ├── logo/
    │   └── sunfish01.jpeg
    └── screenshots/
        ├── screenshot01.jpg
        └── screenshot02.jpg

The main executable script is:

sunfish.lua

It is designed to be loaded directly by Yantra Launcher Pro.

---

Attribution

This project retains the lineage of the original Sunfish engine.

Thomas Ahle

Original Sunfish engine and Python implementation:

https://github.com/thomasahle/sunfish

Soumith Chintala

Initial Lua port:

https://github.com/soumith/sunfish.lua

Borko Danilović

Android / Yantra Launcher Pro adaptation, extensions, application layer, save/load system, puzzle system, display system, and additional chess functionality:

https://github.com/borko17/sunfish-lua

AI assistance

Parts of the adaptation, debugging, refactoring, documentation, and development process were performed with assistance from Claude AI.

AI assistance does not replace the attribution of the original Sunfish authors or the upstream projects.

---

License

The current Sunfish project by Thomas Ahle is distributed under GNU GPL v3.

This project is distributed under GNU GPL v3; see ""LICENSE.md"" (./LICENSE.md) for the applicable license text.

The project also contains historical code lineage from the Lua port by Soumith Chintala. The original "soumith/sunfish.lua" repository contains its own licensing/attribution information, which should be retained and respected when redistributing code derived from that source.

See the upstream projects for their original copyright and license notices:

- "Thomas Ahle / Sunfish" (https://github.com/thomasahle/sunfish)
- "Soumith Chintala / sunfish.lua" (https://github.com/soumith/sunfish.lua)

---

Status

This is a lightweight experimental chess engine/application intended primarily for:

- Android
- Yantra Launcher Pro
- Luaj-jse
- terminal-based chess
- experimentation with chess-engine code
- compact saveable chess positions
- Mate-in-1 puzzle generation

It is deliberately small compared with modern high-performance engines such as Stockfish.

The goal is not maximum playing strength, but a compact, modifiable, self-contained chess engine that can run directly on Android through Lua.