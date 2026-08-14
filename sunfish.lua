-- sunfish.lua Chess engine, Lua port chain: 1. Original algorithm: Sunfish (Python) by Thomas Ahle https://github.com/thomasahle/sunfish - BSD license 2. Initial Lua transpilation attributed to Soumith Chintala 3. Extended for Yantra Launcher / Android (Luaj-jse 3.0.1), with UI, save/load, puzzle mode, and search tuning, by borko17 (https://github.com/borko17/sunfish-lua) (with help from Claude AI).

-------------------------------------------------------------------------------
-- CONFIG: Options at the top
-------------------------------------------------------------------------------
local USE_UNICODE_PIECES = false
local SHOW_ANNOTATIONS = true

-- Node budget per search; higher = deeper but slower. ~5000 is a reasonable ceiling (see TABLE_SIZE).

-- NODES_SEARCHED is a soft limit: checked only between depths, not mid-depth, so overshoot of 50-100% is normal at deeper searches.
local NODES_SEARCHED = 2000

-- Transposition table size, scaled off NODES_SEARCHED (x25) so it doesn't thrash as the node budget grows. Reduced from upstream's 1e6, too heavy for Luaj-jse on a phone.
local TABLE_SIZE = NODES_SEARCHED * 25

-- Mate value exceeds 8*queen + 2*(rook+knight+bishop); king value is double this, so losing the king outweighs any material lead.
local MATE_VALUE = 30000

-- search() scores mate around MATE_UPPER, not MATE_VALUE. Callers comparing its return score must use the same threshold or mate detection misfires.
local MATE_UPPER = 60000 + (10 * 2529)

-- Board is a 120-char padded string; the padding makes off-board detection cheap.
local A1, H1, A8, H8 = 91, 98, 21, 28
local initial =
    '         \n' .. --   0 -  9
    '         \n' .. --  10 - 19
    ' rnbqkbnr\n' .. --  20 - 29
    ' pppppppp\n' .. --  30 - 39
    ' ........\n' .. --  40 - 49
    ' ........\n' .. --  50 - 59
    ' ........\n' .. --  60 - 69
    ' ........\n' .. --  70 - 79
    ' PPPPPPPP\n' .. --  80 - 89
    ' RNBQKBNR\n' .. --  90 - 99
    '         \n' .. -- 100 -109
    '          '     -- 110 -119

local __1 = 1 -- 1-index correction

-------------------------------------------------------------------------------
-- Update
-------------------------------------------------------------------------------
local SCRIPT_VERSION = "2.608140951"
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/borko17/sunfish.lua/main/sunfish.lua"

-- Fallback changelog used when the remote GitHub file can't be reached/parsed (see checkForUpdate).
local CHANGELOG = {
   "engine core rewritten to align with upstream sunfish.py (2026): plays noticeably stronger and more accurately",
   "pawns can now promote to knight, bishop, or rook, not just queen",
   "fixed: castling no longer allowed through occupied squares between king and rook",
   "fixed: pieces sliding onto the back rank no longer miss checks or checkmates delivered there",
   "fixed: better check detection when capturing pieces",
   "fixed checkmate and stalemate detection, now consistent throughout the game",
   "repeated positions are now recognized and treated as a draw while the engine is thinking",
   "threefold repetition now automatically ends the game as a draw",
   "puzzle save/load codes now use the same board format as game save/load codes",
   "fixed: endgame position evaluation no longer interferes with midgame evaluation, including puzzle generation and move selection",
   "captured pieces display now shows a 'Captured: ' label before the piece list",
   "move time is now shown next to each move",
   "engine search info is now shown in the format '(depth X, Y/N nodes)'",
   "save/load codes now preserve full move history, so threefold-repetition detection works correctly across a save/load",
   "fixed: underpromotions (to knight, bishop, or rook) are now recorded in the move list and survive save/load correctly, instead of being silently replayed as a queen promotion",
   "move list ('m') is now printed as a single block, so it's easier to select and copy",
   "a new option to input 'n' in puzzle mode has been added for a new puzzle."
}

-- Extracts the CHANGELOG table from raw script text, so 'u' shows what's new in the latest remote version, not the local one.
local function parseChangelog(text)
   local body = text:match('CHANGELOG%s*=%s*{(.-)}')
   if not body then return nil end
   local list = {}
   for entry in body:gmatch('"(.-)"') do
      table.insert(list, entry)
   end
   if #list == 0 then return nil end
   return list
end

local function printChangelog(list, versionLabel)
   print("")
   print("What's new in v" .. versionLabel .. ":")
   for _, line in ipairs(list) do
      print("• " .. line)
   end
end

local function fallbackToLocalChangelog()
   print("Showing changelog for your installed version instead:")
   printChangelog(CHANGELOG, SCRIPT_VERSION)
end

local function checkForUpdate()
   print("Checking version on GitHub...")

   local ok, result = pcall(function()
      local URL = luajava.bindClass("java.net.URL")
      local url = URL.new(GITHUB_RAW_URL)
      local conn = url:openConnection()
      conn:setConnectTimeout(8000)
      conn:setReadTimeout(8000)
      conn:setRequestMethod("GET")

      local BufferedReader = luajava.bindClass("java.io.BufferedReader")
      local InputStreamReader = luajava.bindClass("java.io.InputStreamReader")
      local reader = BufferedReader.new(InputStreamReader.new(conn:getInputStream()))

      local sb = {}
      local line = reader:readLine()
      while line ~= nil do
         table.insert(sb, line)
         line = reader:readLine()
      end
      reader:close()
      return table.concat(sb, "\n")
   end)

   if not ok or not result or result == '' then
      print("No response from GitHub. Check your connection.")
      fallbackToLocalChangelog()
      return
   end

   local remoteVersion = result:match('SCRIPT_VERSION%s*=%s*"([%d%.]+)"')
   if not remoteVersion then
      print("Could not find a version number in the GitHub file.")
      fallbackToLocalChangelog()
      return
   end

   if remoteVersion == SCRIPT_VERSION then
      print("You have the latest version: " .. SCRIPT_VERSION)
   else
      print("New version available: " .. remoteVersion .. " (current: " .. SCRIPT_VERSION .. ")")
      print("Download at: https://github.com/borko17/sunfish-lua/blob/main/sunfish.lua")
   end

   local remoteChangelog = parseChangelog(result)
   if remoteChangelog then
      printChangelog(remoteChangelog, remoteVersion)
   else
      fallbackToLocalChangelog()
   end
end


-------------------------------------------------------------------------------
-- Move and evaluation tables
-------------------------------------------------------------------------------
local N, E, S, W = -10, 1, 10, -1
local directions = {
    P = {N, 2*N, N+W, N+E},
    N = {2*N+E, N+2*E, S+2*E, 2*S+E, 2*S+W, S+2*W, N+2*W, 2*N+W},
    B = {N+E, S+E, S+W, N+W},
    R = {N, E, S, W},
    Q = {N, E, S, W, N+E, S+E, S+W, N+W},
    K = {N, E, S, W, N+E, S+E, S+W, N+W}
}

local pst = {
    P = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 198, 198, 198, 198, 198, 198, 198, 198, 0,
        0, 178, 198, 198, 198, 198, 198, 198, 178, 0,
        0, 178, 198, 198, 198, 198, 198, 198, 178, 0,
        0, 178, 198, 208, 218, 218, 208, 198, 178, 0,
        0, 178, 198, 218, 238, 238, 218, 198, 178, 0,
        0, 178, 198, 208, 218, 218, 208, 198, 178, 0,
        0, 178, 198, 198, 198, 198, 198, 198, 178, 0,
        0, 198, 198, 198, 198, 198, 198, 198, 198, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    B = {
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 797, 824, 817, 808, 808, 817, 824, 797, 0,
        0, 814, 841, 834, 825, 825, 834, 841, 814, 0,
        0, 818, 845, 838, 829, 829, 838, 845, 818, 0,
        0, 824, 851, 844, 835, 835, 844, 851, 824, 0,
        0, 827, 854, 847, 838, 838, 847, 854, 827, 0,
        0, 826, 853, 846, 837, 837, 846, 853, 826, 0,
        0, 817, 844, 837, 828, 828, 837, 844, 817, 0,
        0, 792, 819, 812, 803, 803, 812, 819, 792, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    N = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 627, 762, 786, 798, 798, 786, 762, 627, 0,
        0, 763, 798, 822, 834, 834, 822, 798, 763, 0,
        0, 817, 852, 876, 888, 888, 876, 852, 817, 0,
        0, 797, 832, 856, 868, 868, 856, 832, 797, 0,
        0, 799, 834, 858, 870, 870, 858, 834, 799, 0,
        0, 758, 793, 817, 829, 829, 817, 793, 758, 0,
        0, 739, 774, 798, 810, 810, 798, 774, 739, 0,
        0, 683, 718, 742, 754, 754, 742, 718, 683, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    R = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    Q = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    K = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 60098, 60132, 60073, 60025, 60025, 60073, 60132, 60098, 0,
        0, 60119, 60153, 60094, 60046, 60046, 60094, 60153, 60119, 0,
        0, 60146, 60180, 60121, 60073, 60073, 60121, 60180, 60146, 0,
        0, 60173, 60207, 60148, 60100, 60100, 60148, 60207, 60173, 0,
        0, 60196, 60230, 60171, 60123, 60123, 60171, 60230, 60196, 0,
        0, 60224, 60258, 60199, 60151, 60151, 60199, 60258, 60224, 0,
        0, 60287, 60321, 60262, 60214, 60214, 60262, 60321, 60287, 0,
        0, 60298, 60332, 60273, 60225, 60225, 60273, 60332, 60298, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
}

-- Endgame "mop-up" king table: rewards centralization once one side has a bare king, so won K+R/K+Q vs K endings converge instead of drifting to the 50-move limit. Formula: 60000 + 70 - 10*(|2*rank-7| + |2*file-7|).
local pst_K_endgame = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 59930, 59940, 59950, 59960, 59960, 59950, 59940, 59930, 0,
    0, 59940, 59950, 59960, 59970, 59970, 59960, 59950, 59940, 0,
    0, 59950, 59960, 59970, 59980, 59980, 59970, 59960, 59950, 0,
    0, 59960, 59970, 59980, 59990, 59990, 59980, 59970, 59960, 0,
    0, 59960, 59970, 59980, 59990, 59990, 59980, 59970, 59960, 0,
    0, 59950, 59960, 59970, 59980, 59980, 59970, 59960, 59950, 0,
    0, 59940, 59950, 59960, 59970, 59970, 59960, 59950, 59940, 0,
    0, 59930, 59940, 59950, 59960, 59960, 59950, 59940, 59930, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

local pst_K_midgame = pst.K

-------------------------------------------------------------------------------
-- Chess logic
-------------------------------------------------------------------------------
local function isspace(s)
   if s == ' ' or s == '\n' then
      return true
   else
      return false
   end
end

local special = '. \n'

local function isupper(s)
   if special:find(s) then return false end
   return s:upper() == s
end

local function islower(s)
   if special:find(s) then return false end
   return s:lower() == s
end

local function swapcase(s)
   local s2 = ''
   for i=1,#s do
      local c = s:sub(i, i)
      if islower(c) then
         s2 = s2 .. c:upper()
      else
         s2 = s2 .. c:lower()
      end
   end
   return s2
end

-- Position uses a metatable (__index) instead of copying methods per instance - cheaper since thousands of Positions are created per move during search.
local Position = {}
Position.__index = Position

function Position.new(board, score, wc, bc, ep, kp)
   local self = setmetatable({}, Position)
   self.board = board
   self.score = score
   self.wc = wc
   self.bc = bc
   self.ep = ep
   self.kp = kp
   return self
end

function Position:genMoves()
   local moves = {}

   for i = 1 - __1, #self.board - __1 do
      local p = self.board:sub(i + __1, i + __1)

      if isupper(p) and directions[p] then
         for _, d in ipairs(directions[p]) do
            local j = i + d

            while true do
               local q = self.board:sub(j + __1, j + __1)

               if isspace(q) or isupper(q) then
                  break
               end

               if p == 'P' then
                  if (d == N or d == 2*N) and q ~= '.' then
                     break
                  end

                  if d == 2*N and
                     (i < A1 + N or
                      self.board:sub(i + N + __1, i + N + __1) ~= '.') then
                     break
                  end

                  if (d == N+W or d == N+E) and
                     q == '.' and
                     j ~= self.ep and
                     math.abs(j - self.kp) > 1 then
                     break
                  end
               end

-- Pawn-only promotion check: A8..H8 is also a normal landing zone for other pieces, so breaking here unconditionally would block their moves onto rank 8.
               if p == 'P' and A8 <= j and j <= H8 then
                  for _, prom in ipairs({"N", "B", "R", "Q"}) do
                     table.insert(moves, {i, j, prom})
                  end
                  break
               end

               table.insert(moves, {i, j, ""})

               if p == 'P' or p == 'N' or p == 'K' then
                  break
               end

               if islower(q) then
                  break
               end

               j = j + d
            end
         end
      end
   end

-- Castling: requires rook on its home square, the right still available, and all squares between king and rook empty.
   local kingIdx = nil
   for i = 1 - __1, #self.board - __1 do
      if self.board:sub(i + __1, i + __1) == 'K' then
         kingIdx = i
         break
      end
   end

   if kingIdx then
      if self.wc[1] and self.board:sub(A1 + __1, A1 + __1) == 'R' then
         local empty = true
         for sq = A1 + E, kingIdx - E, E do
            if self.board:sub(sq + __1, sq + __1) ~= '.' then
               empty = false
               break
            end
         end
         if empty then
            table.insert(moves, {kingIdx, kingIdx + 2*W, ""})
         end
      end

      if self.wc[2] and self.board:sub(H1 + __1, H1 + __1) == 'R' then
         local empty = true
         for sq = kingIdx + E, H1 - E, E do
            if self.board:sub(sq + __1, sq + __1) ~= '.' then
               empty = false
               break
            end
         end
         if empty then
            table.insert(moves, {kingIdx, kingIdx + 2*E, ""})
         end
      end
   end

   return moves
end

function Position:rotate(nullmove)
   nullmove = nullmove or false

   local ep = 0
   local kp = 0

   if not nullmove then
      if self.ep and self.ep ~= 0 then
         ep = 119 - self.ep
      end

      if self.kp and self.kp ~= 0 then
         kp = 119 - self.kp
      end
   end

   return self.new(
      swapcase(self.board:reverse()),
      -self.score,
      self.bc,
      self.wc,
      ep,
      kp
   )
end

function Position:move(move)
   assert(move)

   local i = move[1]
   local j = move[2]
   local prom = move[3] or ""

   local p = self.board:sub(i + __1, i + __1)
   local q = self.board:sub(j + __1, j + __1)

   local function put(board, idx, piece)
      return board:sub(1, idx - 1) .. piece .. board:sub(idx + 1)
   end

   local board = self.board
   local wc = self.wc
   local bc = self.bc
   local ep = 0
   local kp = 0

   local score = self.score + self:value(move)

   board = put(board, j + __1, p)
   board = put(board, i + __1, '.')

   if i == A1 then
      wc = {false, wc[2]}
   elseif i == H1 then
      wc = {wc[1], false}
   end

   if j == H8 then
      bc = {bc[1], false}
   elseif j == A8 then
      bc = {false, bc[2]}
   end

   if p == 'K' then
      wc = {false, false}

      if math.abs(j - i) == 2 then
         kp = math.floor((i + j) / 2)

         local rookSquare = (j < i) and A1 or H1

         board = put(board, rookSquare + __1, '.')
         board = put(board, kp + __1, 'R')
      end
   end

   if p == 'P' then
      if A8 <= j and j <= H8 then
         -- Old UI sends no promotion field, so default to queen.
         if prom == '' then
            prom = 'Q'
         end

         board = put(board, j + __1, prom)
      end

      if j - i == 2 * N then
         ep = i + N
      end

      if j == self.ep then
         board = put(board, j + S + __1, '.')
      end
   end

   return self.new(board, score, wc, bc, ep, kp):rotate()
end

function Position:value(move)
   local i = move[1]
   local j = move[2]
   local prom = move[3] or ""

   local p = self.board:sub(i + __1, i + __1)
   local q = self.board:sub(j + __1, j + __1)

   local score = pst[p][j + __1] - pst[p][i + __1]

-- Capture: PST is already oriented for the side to move (via rotate()), so square j is read directly, no re-rotation needed.
   if islower(q) then
      score = score + pst[q:upper()][j + __1]
   end

   if math.abs(j - self.kp) < 2 then
      score = score + pst['K'][j + __1]
   end

   if p == 'K' and math.abs(i - j) == 2 then
      score = score + pst['R'][math.floor((i + j) / 2) + __1]
      score = score - pst['R'][
         (j < i) and (A1 + __1) or (H1 + __1)
      ]
   end

   if p == 'P' then
      if A8 <= j and j <= H8 then
         if prom == '' then
            prom = 'Q'
         end

         score = score
            + pst[prom][j + __1]
            - pst['P'][j + __1]
      end

      if j == self.ep then
         score = score + pst['P'][j + S + __1]
      end
   end

   return score
end

-- Returns a move capturing the opponent king, if any exists among pseudo-legal moves; used by null-move pruning and mate detection as proof a position is actually won/lost.
-- The `abs(j - self.kp) < 2` check is intentional: self.kp is the square passed through during a recent castle, and landing adjacent to it counts as check since castling through/into check is illegal. Mirrors upstream Sunfish's king-passant handling.
function Position:kingCapture()
   for _, move in ipairs(self:genMoves()) do
      local j = move[2]
      local target = self.board:sub(j + __1, j + __1)

      if target == 'k' or math.abs(j - self.kp) < 2 then
         return move
      end
   end

   return nil
end

-- True once either side has only a king left; used for the endgame PST swap. Single pass, done once per search() call, not per node.
local function isBareKingBoard(board)
   local upperCount, lowerCount = 0, 0
   for i = 1, #board do
      local c = board:sub(i, i)
      if isupper(c) then
         upperCount = upperCount + 1
      elseif islower(c) then
         lowerCount = lowerCount + 1
      end
   end
   return upperCount == 1 or lowerCount == 1
end

local tp = {}
-- Ring buffer of hashes, pre-sized to TABLE_SIZE. tp_head points at the next
-- slot to write; when the buffer is full, writing there evicts whatever hash
-- was previously stored at that slot (the oldest entry), in O(1) -- no scan,
-- no table.remove/shift.
local tp_index = {}
local tp_count = 0
local tp_head = 1        -- next slot to write (1-indexed)
local tp_capacity = 0    -- number of slots currently allocated in tp_index

-- Forward-declared: tp_set() calls tp_popitem() before it's defined below.
local tp_popitem

local function tpKey(pos)
   local w1 = pos.wc[1] and '1' or '0'
   local w2 = pos.wc[2] and '1' or '0'
   local b1 = pos.bc[1] and '1' or '0'
   local b2 = pos.bc[2] and '1' or '0'

   return pos.board
      .. ';' .. tostring(pos.score)
      .. ';' .. w1 .. w2
      .. ';' .. b1 .. b2
      .. ';' .. tostring(pos.ep or 0)
      .. ';' .. tostring(pos.kp or 0)
end

local function tp_set(pos, depth, canNull, lower, upper, move)
   local hash = tpKey(pos)

   local entry = tp[hash]

   if not entry then
      entry = {
         bounds = {},
         move = nil
      }

      tp[hash] = entry

      if tp_count < TABLE_SIZE then
         -- Buffer still has room: append normally.
         tp_capacity = tp_capacity + 1
         tp_index[tp_capacity] = hash
         tp_count = tp_count + 1
      else
         -- Buffer full: evict in O(1) by overwriting the oldest slot (tp_head).
         local evicted = tp_index[tp_head]
         if evicted and evicted ~= hash then
            tp[evicted] = nil
         end
         tp_index[tp_head] = hash
         tp_head = tp_head % TABLE_SIZE + 1
         -- tp_count stays at TABLE_SIZE (one entry replaced another).
      end
   end

   if depth ~= nil and lower ~= nil and upper ~= nil then
-- Only write bounds when both lower and upper are supplied, so killer-only calls (tp_set(p, depth, true, nil, nil, move)) don't stomp an existing {lower, upper} pair with nils.
      local boundKey = tostring(depth) .. ":" ..
         (canNull and "1" or "0")

      entry.bounds[boundKey] = {
         lower = lower,
         upper = upper
      }
   end

   if move ~= nil then
      entry.move = move
   end

   -- (eviction now handled inline above via the ring buffer; tp_popitem is
   -- kept only as a fallback no-op export for compatibility.)
end


local function tp_get(pos, depth, canNull)
   local hash = tpKey(pos)
   local entry = tp[hash]

   if not entry then
      return nil, nil, nil
   end

   local bound = nil

   if depth ~= nil then
      local boundKey = tostring(depth) .. ":" ..
         (canNull and "1" or "0")

      bound = entry.bounds[boundKey]
   end

   return entry, bound, entry.move
end

tp_popitem = function(protectedHash)
   -- No-op: eviction is now handled inline (O(1)) inside tp_set via the ring buffer.
end

local function findCheckers(p)
   local kingIdx = nil
   for i = 1 - __1, #p.board - __1 do
      if p.board:sub(i + __1, i + __1) == 'K' then
         kingIdx = i
         break
      end
   end
   if not kingIdx then return {} end

   local rp = p:rotate()
   local targetJ = 119 - kingIdx
   local checkers = {}
   for _, move in ipairs(rp:genMoves()) do
      if move[1 + __1] == targetJ then
         checkers[119 - move[0 + __1]] = true
      end
   end
   return checkers
end

-------------------------------------------------------------------------------
-- Search logic
-------------------------------------------------------------------------------

-- Node counter for the current search() call; module-scoped so search()'s loop and the inner bound() closure share it.
local nodes = 0

-- Quiescence value floor: deeper quiescence nodes admit slightly weaker captures/threats before cutting off.
local QS = 40
local QS_A = 140

local function search(pos, maxn, history)
   maxn = maxn or NODES_SEARCHED
   history = history or {}

   nodes = 0

   local startTime = os.clock()
   local reachedDepth = 0
   local finalScore = 0

   local MATE_LOWER = 60000 - (13 * 2529)
   local MATE_UPPER = 60000 + (10 * 2529)

   local EVAL_ROUGHNESS = 15

-- Switches to the endgame king table once queens are off, so KRK/KQK converge. pst.K is restored after search() since pst is shared/global and would otherwise leak into calls outside search() (puzzle generation, fallback move sorting).
   local prevPstK = pst.K

   local hasWhiteQueen = pos.board:find('Q', 1, true) ~= nil
   local hasBlackQueen = pos.board:find('q', 1, true) ~= nil

   if hasWhiteQueen and hasBlackQueen then
      pst.K = pst_K_midgame
   else
      pst.K = pst_K_endgame
   end

-- Fresh TT for every root search, as in upstream Sunfish.
   tp = {}
   tp_index = {}
   tp_count = 0
   tp_head = 1
   tp_capacity = 0

   local function bound(p, gamma, depth, root)
      nodes = nodes + 1

      if depth < 0 then
         depth = 0
      end

      if p.score <= -MATE_LOWER then
         return -MATE_UPPER
      end

      local entry, storedBound, killer = tp_get(
         p,
         depth,
         true
      )

      -- Root probes intentionally don't consume a stored score bound.
      if not root and storedBound then
         if storedBound.lower >= gamma then
            return storedBound.lower
         end

         if storedBound.upper < gamma then
            return storedBound.upper
         end
      end

-- Repetition detection: a position seen earlier this game scores as a draw (0). Skipped at root and at depth 0 (quiescence), matching upstream Sunfish.
      if not root and depth > 0 and history[tpKey(p)] then
         return 0
      end

      local best = -MATE_UPPER
      local bestMove = nil
      local live = false

-- Null-move pruning conditions: not at root, depth > 2, eval near equality, at least one major/minor piece remains.
      if not root
         and depth > 2
         and math.abs(p.score) < 500
         and (
            p.board:find('R', 1, true) ~= nil
            or p.board:find('B', 1, true) ~= nil
            or p.board:find('N', 1, true) ~= nil
            or p.board:find('Q', 1, true) ~= nil
         ) then

         local nullScore = math.min(
            p.score + EVAL_ROUGHNESS,
            -bound(
               p:rotate(true),
               1 - gamma,
               depth - 3,
               false
            )
         )

         best = nullScore

         if nullScore >= gamma then
            local proof = killer or p:kingCapture()

            if proof and p:value(proof) >= MATE_LOWER then
               best = MATE_UPPER
               bestMove = proof
            else
               return best
            end
         end
      end

      if depth == 0 then
         if p.score > best then
            best = p.score
         end
      end

      if killer == nil and depth > 2 then
         bound(p, gamma, depth - 3, true)

         local _, _, iidMove = tp_get(
            p,
            depth,
            true
         )

         killer = iidMove
      end

      local valLower = QS - depth * QS_A

      if killer and p:value(killer) >= valLower then
         local childScore = -bound(
            p:move(killer),
            1 - gamma,
            depth - 1,
            false
         )

         if childScore > best then
            best = childScore
            bestMove = killer
         end

         if childScore > -MATE_UPPER then
            live = true
         end

         if best >= gamma then
            if depth > 0 then
               tp_set(
                  p,
                  depth,
                  true,
                  best,
                  storedBound and storedBound.upper or MATE_UPPER,
                  killer
               )
            end

            return best
         end
      end

      local ordered = {}

      for _, move in ipairs(p:genMoves()) do
         local val = p:value(move)

         if val >= valLower then
            table.insert(ordered, {
               value = val,
               move = move
            })
         end
      end

      table.sort(ordered, function(a, b)
         return a.value > b.value
      end)

      for _, item in ipairs(ordered) do
         local move = item.move
         local val = item.value

         if depth <= 1 and p.score + val < gamma then
            local futilityScore

            if val >= MATE_LOWER then
               futilityScore = MATE_UPPER
            else
               futilityScore = p.score + val
            end

            if futilityScore > best then
               best = futilityScore
            end

            -- Ordered by value, so nothing later can improve it.
            break
         end

         local childScore = -bound(
            p:move(move),
            1 - gamma,
            depth - 1,
            false
         )

         if childScore > best then
            best = childScore
            bestMove = move
         end

         if childScore > -MATE_UPPER then
            live = true
         end

         if best >= gamma then
            break
         end
      end

      if depth > 0 and not live then
         local moves = p:genMoves()
         local noLegalMove = true

         for _, move in ipairs(moves) do
            local child = p:move(move)

            if not child:kingCapture() then
               noLegalMove = false
               break
            end
         end

         if noLegalMove then
            if p:rotate(true):kingCapture() then
               best = -MATE_LOWER
            else
               best = 0
            end

            bestMove = nil
         end
      end

      if best >= gamma and bestMove ~= nil and depth > 0 then
         tp_set(
            p,
            depth,
            true,
            nil,
            nil,
            bestMove
         )
      end

      -- Root move is needed by search() after the depth finishes.
      if root and best >= gamma and bestMove ~= nil then
         tp_set(
            p,
            nil,
            nil,
            nil,
            nil,
            bestMove
         )
      end

      -- Store lower/upper bound for non-root searches.
      if not root then
         local oldLower = storedBound and
            storedBound.lower or -MATE_UPPER

         local oldUpper = storedBound and
            storedBound.upper or MATE_UPPER

         if best >= gamma then
            oldLower = best
         else
            oldUpper = best
         end

         tp_set(
            p,
            depth,
            true,
            oldLower,
            oldUpper,
            nil
         )
      end

      return best
   end

   -- Iterative deepening MTD-bi.
   for depth = 1, 98 do
      local lower = 1 - MATE_UPPER
      local upper = MATE_UPPER
      local gamma = 0
      local score = 0

      while lower < upper - EVAL_ROUGHNESS do
         score = bound(pos, gamma, depth, true)

         if score >= gamma then
            lower = score
         else
            upper = score
         end

         gamma = math.floor((lower + upper + 1) / 2)
      end

      finalScore = score
      reachedDepth = depth

      if nodes >= maxn or
         math.abs(score) >= MATE_UPPER then
         break
      end
   end

   local _, _, rootMove = tp_get(pos, nil, nil)

   local elapsed = os.clock() - startTime

-- Restore pst.K so code outside search() isn't silently affected by whichever king table this search picked.
   pst.K = prevPstK

   return rootMove,
      finalScore,
      reachedDepth,
      nodes,
      elapsed
end

-------------------------------------------------------------------------------
-- Display symbols
-------------------------------------------------------------------------------

local emptySquareSymbols_unicode = {
   dark = '\xe2\x80\xa2',
   light = '\xe2\x97\xa6'
}
local emptySquareSymbols_letters = {
   dark = ':',
   light = '.'
}

local whiteSymbols_unicode = {
   K = '\xe2\x99\x9a', Q = '\xe2\x99\x9b', R = '\xe2\x99\x9c',
   B = '\xe2\x99\x9d', N = '\xe2\x99\x9e', P = '\xe2\x99\x9f',
}
local blackSymbols_unicode = {
   K = '\xe2\x99\x94', Q = '\xe2\x99\x95', R = '\xe2\x99\x96',
   B = '\xe2\x99\x97', N = '\xe2\x99\x98', P = '\xe2\x99\x99',
}

local whiteSymbols_letters = {
   K = 'K', Q = 'Q', R = 'R', B = 'B', N = 'N', P = 'P',
}
local blackSymbols_letters = {
   K = 'k', Q = 'q', R = 'r', B = 'b', N = 'n', P = 'p',
}

local whiteSymbols = USE_UNICODE_PIECES and whiteSymbols_unicode or whiteSymbols_letters
local blackSymbols = USE_UNICODE_PIECES and blackSymbols_unicode or blackSymbols_letters
local emptySquareSymbols = USE_UNICODE_PIECES and emptySquareSymbols_unicode or emptySquareSymbols_letters

local function updateDisplayMode()
   whiteSymbols = USE_UNICODE_PIECES and whiteSymbols_unicode or whiteSymbols_letters
   blackSymbols = USE_UNICODE_PIECES and blackSymbols_unicode or blackSymbols_letters
   emptySquareSymbols = USE_UNICODE_PIECES and emptySquareSymbols_unicode or emptySquareSymbols_letters
end

-------------------------------------------------------------------------------
-- User interface
-------------------------------------------------------------------------------

local function parse(c)
   if not c then return nil end
   local p, v = c:sub(1,1), c:sub(2,2)
   if not (p and v and tonumber(v)) then return nil end

   local fil, rank = string.byte(p) - string.byte('a'), tonumber(v) - 1
   return A1 + fil - 10*rank
end

local function render(i)
   local rank, fil = math.floor((i - A1) / 10), (i - A1) % 10
   return string.char(fil + string.byte('a')) .. tostring(-rank + 1)
end

local function ttfind(t, k)
   assert(t)

   if not k or not k[1] or not k[2] then
      return false
   end

   for _, v in ipairs(t) do
      if k[1] == v[1] and k[2] == v[2] then
-- Existing UI sends no promotion character; default to queen.
         if v[3] and v[3] ~= '' and
            (k[3] == nil or k[3] == '') then
            k[3] = v[3]

            -- Prefer queen when several promotion moves share i/j.
            if v[3] ~= 'Q' then
               for _, candidate in ipairs(t) do
                  if candidate[1] == k[1]
                     and candidate[2] == k[2]
                     and candidate[3] == 'Q' then
                     k[3] = 'Q'
                     break
                  end
               end
            end
         end

         return true
      end
   end

   return false
end

local strsplit = function(a)
   local out = {}
   while true do
      local pos, _ = a:find('\n')
      if pos then
         out[#out+1] = a:sub(1, pos-1)
         a = a:sub(pos+1)
      else
         out[#out+1] = a
         break
      end
   end
   return out
end

local function printboard(board, lastMove, checkers, guards, isMate)
   checkers = checkers or {}
   guards = guards or {}
   local highlight = {}
   if lastMove then
      highlight[lastMove[1]] = true
      highlight[lastMove[2]] = true
   end

   local l = strsplit(board, '\n')
   print("")
   local topBorder, sideBorder, bottomBorder
   if USE_UNICODE_PIECES then
      topBorder = "  \xe2\x95\x94\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x97"
      sideBorder = "\xe2\x95\x91"
      bottomBorder = "  \xe2\x95\x9a\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x90\xe2\x95\x9d"
   else
      topBorder = "  +" .. string.rep("-", 26) .. "+"
      sideBorder = "|"
      bottomBorder = "  +" .. string.rep("-", 26) .. "+"
   end

   print(topBorder)
   for k = 3, 10 do
      local rank = 11 - k
      local v = l[k]
      local line = {}
      table.insert(line, tostring(rank) .. " " .. sideBorder .. "  ")
      for i = 2, 9 do
         local c = v:sub(i, i)
         local file = i - 1
         local idx = (k - 1) * 10 + (i - 1)
         local sym
         if c == '.' then
            if (file + rank) % 2 == 0 then
               sym = emptySquareSymbols.light
            else
               sym = emptySquareSymbols.dark
            end
         elseif USE_UNICODE_PIECES then
            if c == 'K' then sym = '\xe2\x99\x9a'
            elseif c == 'Q' then sym = '\xe2\x99\x9b'
            elseif c == 'R' then sym = '\xe2\x99\x9c'
            elseif c == 'B' then sym = '\xe2\x99\x9d'
            elseif c == 'N' then sym = '\xe2\x99\x9e'
            elseif c == 'P' then sym = '\xe2\x99\x9f'
            elseif c == 'k' then sym = '\xe2\x99\x94'
            elseif c == 'q' then sym = '\xe2\x99\x95'
            elseif c == 'r' then sym = '\xe2\x99\x96'
            elseif c == 'b' then sym = '\xe2\x99\x97'
            elseif c == 'n' then sym = '\xe2\x99\x98'
            elseif c == 'p' then sym = '\xe2\x99\x99'
            else sym = c
            end
         else
            sym = c
         end

         if checkers[idx] then
   if #line > 0 then
      line[#line] = line[#line]:gsub(" $", "")
   end
   if SHOW_ANNOTATIONS then
      local openChar = isMate and "!" or (highlight[idx] and "(" or " ")
      table.insert(line, openChar .. sym .. "! ")
   else
      table.insert(line, " " .. sym .. "  ")
   end
elseif guards[idx] then
   if #line > 0 then
      line[#line] = line[#line]:gsub(" $", "")
   end
   if SHOW_ANNOTATIONS then
      local openChar = highlight[idx] and "(" or " "
      table.insert(line, openChar .. sym .. "? ")
   else
      table.insert(line, " " .. sym .. "  ")
   end
elseif highlight[idx] then
   if #line > 0 then
      line[#line] = line[#line]:gsub(" $", "")
   end
   if SHOW_ANNOTATIONS then
      table.insert(line, "(" .. sym .. ") ")
   else
      table.insert(line, " " .. sym .. "  ")
   end
else
   table.insert(line, sym .. "  ")
end
      end
      table.insert(line, sideBorder)
      print(table.concat(line))
   end
   print(bottomBorder)
   print("     a  b  c  d  e  f  g  h")
   print("")
end

local function renderCaptured(list, symbols)
   local out = {}
   for _, piece in ipairs(list) do
      table.insert(out, symbols[piece] or piece)
   end
   return table.concat(out)
end

local function capturedAt(pos, move)
   local i, j = move[0 + __1], move[1 + __1]
   local p, q = pos.board:sub(i + __1, i + __1), pos.board:sub(j + __1, j + __1)
   if islower(q) then
      return q:upper()
   end
   if p == 'P' and (j - i == N+W or j - i == N+E) and q == '.' and j == pos.ep then
      return 'P'
   end
   return nil
end

-- True if the piece at move[1] is a pawn; used with captures to reset the 50-move-rule clock.
local function isPawnMove(pos, move)
   local i = move[0 + __1]
   local p = pos.board:sub(i + __1, i + __1)
   return p == 'P'
end

-- True if a pawn lands on rank 8 (White's orientation); used to prompt for promotion choice instead of defaulting to queen.
local function isPromotionMove(pos, move)
   local i = move[0 + __1]
   local j = move[1 + __1]
   local p = pos.board:sub(i + __1, i + __1)
   return p == 'P' and A8 <= j and j <= H8
end


local function findKingGuards(p, checkers)
   checkers = checkers or {}
   local kingIdx = nil
   for i = 1 - __1, #p.board - __1 do
      if p.board:sub(i + __1, i + __1) == 'K' then
         kingIdx = i
         break
      end
   end
   if not kingIdx then return {} end

   local function attacks(board, from, ptype, target)
      if ptype == 'P' then
         return target == from + S + W or target == from + S + E
      elseif ptype == 'N' or ptype == 'K' then
         local offs = (ptype == 'N') and directions.N or directions.K
         for _, d in ipairs(offs) do
            if from + d == target then return true end
         end
         return false
      else
         local offs = directions[ptype]
         for _, d in ipairs(offs) do
            local j = from + d
            while true do
               local c = board:sub(j + __1, j + __1)
               if isspace(c) then break end
               if j == target then return true end
               if c ~= '.' then break end
               j = j + d
            end
         end
         return false
      end
   end

   local guards = {}
   for _, d in ipairs(directions.K) do
      local sq = kingIdx + d
      local c = p.board:sub(sq + __1, sq + __1)
      if not isspace(c) and not isupper(c) then
         for i = 1 - __1, #p.board - __1 do
            local pc = p.board:sub(i + __1, i + __1)
            if islower(pc) and not checkers[i] then
               if attacks(p.board, i, pc:upper(), sq) then
                  guards[i] = true
               end
            end
         end
      end
   end
   return guards
end

local function isLegalMove(pos, move)
   local afterOwn = pos:move(move):rotate()
   return not next(findCheckers(afterOwn))
end

local function hasLegalMove(pos)
   for _, move in ipairs(pos:genMoves()) do
      if isLegalMove(pos, move) then
         return true
      end
   end
   return false
end

local function legalMovesOf(pos)
   local out = {}
   for _, move in ipairs(pos:genMoves()) do
      if isLegalMove(pos, move) then
         table.insert(out, move)
      end
   end
   return out
end

-------------------------------------------------------------------------------
-- Save/Load game functions
-------------------------------------------------------------------------------

local function saveGame(pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, nextToMove, moveHistory)
   local boardLines = {}
   for rank = 8, 1, -1 do
      local line = {}
      for file = 0, 7 do
         local idx = A1 + file - 10*(rank-1)
         local c = pos.board:sub(idx + __1, idx + __1)
         if isspace(c) then
            table.insert(line, '.')
         else
            table.insert(line, c)
         end
      end
      table.insert(boardLines, table.concat(line))
   end
   local boardStr = table.concat(boardLines, '\n')
   
   local wcStr = (pos.wc[1] and '1' or '0') .. (pos.wc[2] and '1' or '0')
   local bcStr = (pos.bc[1] and '1' or '0') .. (pos.bc[2] and '1' or '0')
   
   local userCapStr = table.concat(capturedByUser, '')
   local engineCapStr = table.concat(capturedByEngine, '')
   if userCapStr == '' then userCapStr = '-' end
   if engineCapStr == '' then engineCapStr = '-' end
   
   local epStr = tostring(pos.ep or 0)
   
   local lastMoveStr = '--'
   if lastMove then
      lastMoveStr = render(lastMove[1]) .. render(lastMove[2])
   end
   
   local nextStr = (nextToMove == "w") and "w" or "b"

-- Full move notation history (UCI, e.g. "e2e4"), comma-separated. Lets
-- loadGame() replay from `initial` to rebuild gameHistory/positionCounts,
-- so threefold-repetition detection stays correct across a save/load.
-- '-' means no moves played yet.
   local histStr = '-'
   if moveHistory and #moveHistory > 0 then
      local parts = {}
      for _, entry in ipairs(moveHistory) do
         table.insert(parts, entry.notation)
      end
      histStr = table.concat(parts, ',')
   end
   
   -- Format: metadata line then board
   local code = "wc:" .. wcStr .. "|bc:" .. bcStr .. "|ep:" .. epStr .. 
                "|last:" .. lastMoveStr .. "|ucap:" .. userCapStr .. "|ecap:" .. engineCapStr .. 
                "|wm:" .. whiteMoves .. "|bm:" .. blackMoves .. "|hc:" .. (halfmoveClock or 0) .. 
                "|next:" .. nextStr .. "|hist:" .. histStr .. "\n" .. boardStr
   
   return code
end

local function loadGame(code)
   -- Check if code has metadata line (contains '|')
   if code:find('|') then
      -- Full format with metadata
      local metadata, boardStr = code:match("(.-)\n(.*)")
      if not metadata or not boardStr then
         print("Invalid code format! Expected metadata line then board.")
         return nil
      end
      
      local parts = {}
      for part in metadata:gmatch('[^|]+') do
         local key, value = part:match("([^:]+):(.*)")
         if key and value then
            parts[key] = value
         end
      end
      
      if not parts.wc or not parts.bc or not parts.ep or not parts.last or 
         not parts.ucap or not parts.ecap or not parts.wm or not parts.bm or 
         not parts.hc or not parts.next then
         print("Invalid metadata! Missing required fields.")
         return nil
      end
      -- parts.hist is optional: older save codes won't have it. loadGame()
      -- callers must handle a nil histStr (falls back to no-history seeding).
      
      local boardLines = {}
      for line in boardStr:gmatch("[^\n]+") do
         table.insert(boardLines, line)
      end
      
      if #boardLines ~= 8 then
         print("Invalid board! Expected 8 ranks, got " .. #boardLines)
         return nil
      end
      
      local fullBoard = '         \n         \n '
      for rank = 1, 8 do
         local line = boardLines[rank]
         if #line ~= 8 then
            print("Invalid rank! Expected 8 files, got " .. #line)
            return nil
         end
         fullBoard = fullBoard .. line
         if rank < 8 then
            fullBoard = fullBoard .. '\n '
         end
      end
      fullBoard = fullBoard .. '\n         \n          '
      
      local wc1 = parts.wc:sub(1,1) == '1'
      local wc2 = parts.wc:sub(2,2) == '1'
      local bc1 = parts.bc:sub(1,1) == '1'
      local bc2 = parts.bc:sub(2,2) == '1'
      
      local ep = tonumber(parts.ep) or 0
      local whiteMoves = tonumber(parts.wm) or 0
      local blackMoves = tonumber(parts.bm) or 0
      local halfmoveClock = tonumber(parts.hc) or 0
      local nextToMove = parts.next or "b"
      
      local pos = Position.new(fullBoard, 0, {wc1, wc2}, {bc1, bc2}, ep, 0)
      
      local capturedByUser = {}
      if parts.ucap ~= '-' then
         for i = 1, #parts.ucap do
            table.insert(capturedByUser, parts.ucap:sub(i,i))
         end
      end
      
      local capturedByEngine = {}
      if parts.ecap ~= '-' then
         for i = 1, #parts.ecap do
            table.insert(capturedByEngine, parts.ecap:sub(i,i))
         end
      end
      
      local lastMove = nil
      if parts.last ~= '--' and #parts.last == 4 then
         lastMove = {parse(parts.last:sub(1,2)), parse(parts.last:sub(3,4))}
      end

      -- May be nil (old save codes without the field) or "-" (no moves yet).
      local histStr = parts.hist
      
      return pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, nextToMove, histStr
      
   else
-- Simple format (board only, 8x8): resets everything else to initial state.
      local boardLines = {}
      for line in code:gmatch("[^\n]+") do
         table.insert(boardLines, line)
      end
      
      if #boardLines ~= 8 then
         print("Invalid board! Expected 8 ranks, got " .. #boardLines)
         return nil
      end
      
      local fullBoard = '         \n         \n '
      for rank = 1, 8 do
         local line = boardLines[rank]
         if #line ~= 8 then
            print("Invalid rank! Expected 8 files, got " .. #line)
            return nil
         end
         fullBoard = fullBoard .. line
         if rank < 8 then
            fullBoard = fullBoard .. '\n '
         end
      end
      fullBoard = fullBoard .. '\n         \n          '
      
      local pos = Position.new(fullBoard, 0, {true, true}, {true, true}, 0, 0)
      local lastMove = nil
      local capturedByUser = {}
      local capturedByEngine = {}
      local whiteMoves = 0
      local blackMoves = 0
      local halfmoveClock = 0
      local nextToMove = "w"  -- White (human) to move
      
      return pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, nextToMove, nil
   end
end

-- Replays a comma-separated UCI move history (e.g. "e2e4,e7e5,...") from the
-- initial position to rebuild gameHistory/positionCounts, so threefold-
-- repetition detection stays correct across a save/load. If histStr is nil
-- (old save code without the field), empty, "-", or replay fails for any
-- reason (corrupted/hand-edited code, illegal move), falls back to seeding
-- only fallbackPos, same behavior as before this feature existed.
local function rebuildHistoryFromMoves(histStr, fallbackPos)
   local gameHistory = {}
   local positionCounts = {}

   local function seedFallback()
      gameHistory = { [tpKey(fallbackPos)] = true }
      positionCounts = { [tpKey(fallbackPos)] = 1 }
   end

   if not histStr or histStr == '-' or histStr == '' then
      seedFallback()
      return gameHistory, positionCounts
   end

   local ok, err = pcall(function()
      local replayPos = Position.new(initial, 0, {true,true}, {true,true}, 0, 0)
      gameHistory[tpKey(replayPos)] = true
      positionCounts[tpKey(replayPos)] = 1

      local ply = 0
      for notation in histStr:gmatch('[^,]+') do
         if #notation < 4 or #notation > 5 then
            error("bad notation length: " .. notation)
         end

         local from = parse(notation:sub(1,2))
         local to = parse(notation:sub(3,4))
         if not from or not to then
            error("unparseable move: " .. notation)
         end

-- 5th character, if present, is a promotion suffix (n/b/r/q) recorded only
-- when the player/engine promoted to something other than the Queen
-- default; see the notation-building sites in main().
         local promo = nil
         if #notation == 5 then
            promo = notation:sub(5,5):upper()
            if promo ~= 'N' and promo ~= 'B' and promo ~= 'R' and promo ~= 'Q' then
               error("bad promotion suffix: " .. notation)
            end
         end

-- moveHistory notation is always recorded in absolute board coordinates
-- (see main()'s render(usermove[1])/render(119-enginemove[...]) calls), but
-- replayPos alternates perspective after every ply (rotate() inside
-- Position:move()). On odd plies (White to move) replayPos is already in
-- White's un-rotated view, so the move applies as-is; on even plies (Black
-- to move) replayPos is in Black's rotated view, so coordinates must be
-- mirrored the same way main() does for the engine's own moves (119 - x).
         ply = ply + 1
         local localFrom, localTo
         if ply % 2 == 1 then
            localFrom, localTo = from, to
         else
            localFrom, localTo = 119 - from, 119 - to
         end

         local move = {localFrom, localTo, promo}
         if not ttfind(replayPos:genMoves(), move) then
            error("illegal move during replay: " .. notation)
         end

         replayPos = replayPos:move(move)
         replayPos.score = 0

         local key = tpKey(replayPos)
         gameHistory[key] = true
         positionCounts[key] = (positionCounts[key] or 0) + 1
      end
   end)

   if not ok then
      print("Warning: could not replay move history (" .. tostring(err) .. "). Repetition tracking resets from this position.")
      seedFallback()
   end

   return gameHistory, positionCounts
end


local function displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   if lastMove then
      print("Sunfish move: \n" .. render(lastMove[1]) .. render(lastMove[2]))
      print("Captured: " .. renderCaptured(capturedByEngine, whiteSymbols))
   end
   local checkers = findCheckers(pos)
   local guards = findKingGuards(pos, checkers)
   if next(checkers) then
      print("Check!")
   end
   printboard(pos.board, lastMove, checkers, guards)
   print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
end

-------------------------------------------------------------------------------
-- Help
-------------------------------------------------------------------------------

local function showHelp()
   print("")
   print("=== CHESS.LUA HELP ===")
   print("")
   print("COMMANDS FOR CHESS:")
   print("-------------")
   print("moves - Enter moves in format 'e2e4'")
   print("'h' - Show this help screen")
   print("'?' - Show About screen")
   print("'d' - Toggle display mode")
   print("    • Unicode symbols <-> Letters.")
   print("'a' - Toggle annotations")
   print("    • show/hide board markers.")
   print("'s' - Save game (generate code)")
   print("'sN' - Save position as of move N")
   print("     • e.g. 's15' saves")
   print("       after move 15,")
   print("       even if you've") 
   print("       played further.")
   print("'l' - Load saved game")
   print("'nN' - Change engine strength")
   print("     • e.g. 'n4000'")
   print("     • higher N = harder/slower")
   print("     • lower N = easier/faster.")
   print("     • default: n2000")
   print("'m' - Show move history")
   print("'r' - Resign current game")
   print("'n' - Start a new game")
   print("'u' - Check sunfish.lua update")
   print("'q' - Quit chess.lua")
   print("")
   print("COMMANDS FOR PUZZLE MODE:")
   print("-------------")
   print("'m1' - Enter Mate-in-1 puzzle mode")
   print("'h' - for hint in puzzles")
   print("'s' - Save puzzle")
   print("'l' - Load saved puzzle")
   print("'n' - Start a new puzzle")
   print("'d' - Toggle display mode:")
   print("'q' - to leave puzzles")
   print("")
   print("DISPLAY MODES:")
   print("-------------")
   print("Unicode mode:")
   print("• Your pieces:    ♚ ♛ ♜ ♝ ♞ ♟")  
   print("• Sunfish pieces: ♔ ♕ ♖ ♗ ♘ ♙")
   print("• Empty squares:  • light ◦ dark")
   print("")
   print("Letter mode:")
   print("• Your pieces:    K Q R B N P")
   print("• Sunfish pieces: k q r b n p")
   print("• Empty squares:  : light . dark")
   print("")
   print("Default mode can be changed in CONFIG - section at top of LUA script:")
   print("-------------")
   print("USE_UNICODE_PIECES = true/false")
   print("SHOW_ANNOTATIONS = true/false")
   print("local NODES_SEARCHED = 2000")
   print("")
   print("PIECE SYMBOLS:")
   print("-------------")
   print("K = King   Q = Queen  R = Rook")
   print("B = Bishop N = Knight P = Pawn")
   print("")
   print("uppercase = Your pieces,")
   print("lowercase = Sunfish.")
   print("")
   print("BOARD MARKERS")
   print("(what symbols mean):")
   print("-------------")
   print(" sym! - piece is giving CHECK")
   print("!sym! - piece delivers CHECKMATE")
   print(" sym? - piece GUARDS escape square")
   print("(sym) - piece just moved here")
   print("")
   print("Combined markers:")
   print("(sym! - piece moved AND gives check")
   print("(sym? - piece moved AND guards escape")
   print("")
   print("Note: ( ) shows last move")
   print("       !  shows check/checkmate")
   print("       ?  shows guard")
   print("")
   print("RECOMMENDED FONTS:")
   print("-------------")
   print("For Unicode symbols:")
   print("• DejaVu Sans Mono")
   print("• Julia Mono")
   print("• Everson Mono")
   print("• Unifont")
   print("")
   print("For letter mode:")
   print("• Any monospaced font")
   print("")
   print("")
   print("↑↑↑ CHESS.LUA HELP ↑↑↑")
end

-------------------------------------------------------------------------------
-- About
-------------------------------------------------------------------------------

local function showAbout()
   print("")
   print("=== ABOUT SUNFISH.LUA ===")
   print("")
   print("Lua port of Sunfish,")
   print("a compact chess engine")
   print("originally written in Python") 
   print("by Thomas Ahle")
   print("(github.com/thomasahle/sunfish).")
   print("")
   print("An initial bare-bones Lua") 
   print("transpilation is attributed")
   print("to Soumith Chintala.")
   print("")
   print("Adapted for Yantra Launcher") 
   print("on Android (Luaj-jse 3.0.1)")
   print("by borko17 (github.com/borko17),")
   print("with help from Claude AI.")
   print("")
   print("Original Python code license: GNU GPL v3")
   print("")
   print("KEY CHANGES FOR PHONE USE:")
   print("-------------")
   print("• Node-budget search instead of a timer")
   print("• Adjustable engine strength ('nN')")
   print("• Smaller, budget-scaled transposition table")
   print("• Zugzwang guard on null-move pruning")
   print("• Endgame king-centralization table")
   print("• Depth-scaled quiescence threshold")
   print("")
   print("EXTRA FEATURES:")
   print("-------------")
   print("• Full legal-move / check / stalemate detection")
   print("• 50-move-rule draw detection")
   print("Note: draws are auto-declared under the 50-move-no-progress rule (no capture or pawn move in 50 moves)")
   print("• Save & Load games via text codes")
   print("• Move history ('m') and per-move save ('sN')")
   print("• Unicode or letter piece display")
   print("• Check / guard / last-move board markers")
   print("• Captured-piece tracking")
   print("• Search depth/nodes/time shown after each move")
   print("• Mate-in-1 puzzle mode ('m1') with hints")
   print("")
   print("")
   print("↑↑↑ ABOUT SUNFISH.LUA ↑↑↑")
end

-------------------------------------------------------------------------------
-- AI puzzle mode ("m1")
-------------------------------------------------------------------------------

local emptyBoard =
    '         \n' ..
    '         \n' ..
    ' ........\n' ..
    ' ........\n' ..
    ' ........\n' ..
    ' ........\n' ..
    ' ........\n' ..
    ' ........\n' ..
    ' ........\n' ..
    ' ........\n' ..
    '         \n' ..
    '          '

local aiWhitePool = {"Q","R","B","N","P"}
local aiBlackPool = {"q","r","b","n","p"}
local aiPieceCaps = {Q = 1, R = 2, B = 2, N = 2, P = 8}
local AI_MATE1_ATTEMPTS = 600

local function pickCappedPieceType(pool, counts)
   local candidates = {}
   for _, pc in ipairs(pool) do
      local base = pc:upper()
      if (counts[base] or 0) < (aiPieceCaps[base] or 0) then
         table.insert(candidates, pc)
      end
   end
   if #candidates == 0 then return nil end
   return candidates[math.random(#candidates)]
end

local function aiPut(board, i, ch)
   return board:sub(1, i-1) .. ch .. board:sub(i+1)
end

local function randomFreeSquare(occupied, avoidBackRanks, forcedColor)
   for _ = 1, 40 do
      local f, r = math.random(0,7), math.random(0,7)
      if not (avoidBackRanks and (r == 0 or r == 7)) then
         local idx = A1 + f - 10*r
         local fieldColor = (f + r) % 2  -- 0=white, 1=black

         if forcedColor and fieldColor ~= forcedColor then
            goto continue
         end

         if not occupied[idx] then
            return idx
         end
      end
      ::continue::
   end
   return nil
end

local function findMateIn1Move(pos)
   for _, mv in ipairs(pos:genMoves()) do
      if isLegalMove(pos, mv) then
         local newPos = pos:move(mv)
         local checkers = findCheckers(newPos)
         if next(checkers) and not hasLegalMove(newPos) then
            return mv
         end
      end
   end
   return nil
end

local function genAiMateIn1(maxAttempts)
   maxAttempts = maxAttempts or AI_MATE1_ATTEMPTS

   for _ = 1, maxAttempts do
      local bkFile, bkRank = math.random(0,7), math.random(0,7)
      local bkIdx = A1 + bkFile - 10*bkRank

      local wkIdx = nil
      for _ = 1, 30 do
         local f, r = math.random(0,7), math.random(0,7)
         local idx = A1 + f - 10*r
         if idx ~= bkIdx and math.max(math.abs(f-bkFile), math.abs(r-bkRank)) > 1 then
            wkIdx = idx
            break
         end
      end

      if wkIdx then
         local occupied = {[bkIdx]=true, [wkIdx]=true}
         local board, ok = emptyBoard, true
         board = aiPut(board, bkIdx + __1, 'k')
         board = aiPut(board, wkIdx + __1, 'K')

         local numWhiteExtra = math.random(2,10)
         local numBlackExtra = math.random(1,10)
         local whiteCounts = {}
         local blackCounts = {}
         local whiteBishopColor = nil
         local blackBishopColor = nil

         for _ = 1, numWhiteExtra do
            local pc = pickCappedPieceType(aiWhitePool, whiteCounts)
            if not pc then break end

            local forcedColor = nil
            if pc == 'B' then
               if not whiteBishopColor then
                  whiteBishopColor = math.random(0, 1)
                  forcedColor = whiteBishopColor
               else
                  forcedColor = 1 - whiteBishopColor
               end
            end

            local idx = randomFreeSquare(occupied, pc == "P", forcedColor)
            if not idx then ok = false; break end
            occupied[idx] = true
            board = aiPut(board, idx + __1, pc)
            whiteCounts[pc] = (whiteCounts[pc] or 0) + 1
         end

         if ok then
            for _ = 1, numBlackExtra do
               local pc = pickCappedPieceType(aiBlackPool, blackCounts)
               if not pc then break end

               local forcedColor = nil
               if pc == 'b' then
                  if not blackBishopColor then
                     blackBishopColor = math.random(0, 1)
                     forcedColor = blackBishopColor
                  else
                     forcedColor = 1 - blackBishopColor
                  end
               end

               local idx = randomFreeSquare(occupied, pc == "p", forcedColor)
               if not idx then ok = false; break end
               occupied[idx] = true
               board = aiPut(board, idx + __1, pc)
               blackCounts[pc:upper()] = (blackCounts[pc:upper()] or 0) + 1
            end
         end

         if ok then
            local pos = Position.new(board, 0, {false,false}, {false,false}, 0, 0)
            local blackPos = pos:rotate()
            if not next(findCheckers(blackPos)) then
               if findMateIn1Move(pos) then
                  return board
               end
            end
         end
      end
   end
   return nil
end

-- Returns (solved, quit, newBoard). newBoard lets callers pick up a board
-- loaded via 'l' — previously a reassignment of `board` inside this function
-- was lost once the function returned, since only two values came back.
local function attemptAiPuzzle(board)
   local curPos = Position.new(board, 0, {false,false}, {false,false}, 0, 0)
   printboard(curPos.board)
   print("Find mate in 1 move: ")
   local crdn = input()
   if not crdn then
      print("\nNo input (EOF). Ending puzzle mode.")
      return false, true, board
   end
   if crdn == 'q' then
       print("----")
      print("Leaving puzzle mode.")
      return false, true, board
   end
   if crdn == 'n' then
       print("----")
      print("Generating new puzzle...")
   local board = genAiMateIn1()
   return false, false, board
   end
   if crdn == 'd' then
   USE_UNICODE_PIECES = not USE_UNICODE_PIECES
   updateDisplayMode()
   print("----")
   print("Mode: " .. (USE_UNICODE_PIECES and "Unicode" or "Letters"))
   return false, false, board
end

if crdn == 's' then
   local boardLines = {}
   for rank = 8, 1, -1 do
      local line = {}
      for file = 0, 7 do
         local idx = A1 + file - 10*(rank-1)
         local c = curPos.board:sub(idx + __1, idx + __1)
         if isspace(c) then
            table.insert(line, '.')
         else
            table.insert(line, c)
         end
      end
      table.insert(boardLines, table.concat(line))
   end
   local boardStr = table.concat(boardLines, '\n')
   print("----")
   print("=== PUZZLE CODE ===")
   print(boardStr)
   prin7t("==================")
   return false, false, board
end

if crdn == 'l' then
    print("----")
   print("Paste puzzle code:")
   local code = input()
   if code and code ~= '' then
      local boardLines = {}
      for line in code:gmatch("[^\n]+") do
         table.insert(boardLines, line)
      end

      if #boardLines ~= 8 then
         print("Invalid code! Expected 8 ranks, got " .. #boardLines)
         return false, false, board
      end

      local fullBoard = '         \n         \n '
      local valid = true
      for rank = 1, 8 do
         local line = boardLines[rank]
         if #line ~= 8 then
            print("Invalid code! Rank " .. rank .. " has " .. #line .. " squares, expected 8.")
            valid = false
            break
         end
         fullBoard = fullBoard .. line
         if rank < 8 then
            fullBoard = fullBoard .. '\n '
         end
      end

      if not valid then
         return false, false, board
      end

      fullBoard = fullBoard .. '\n         \n          '
      board = fullBoard
      local boardStr = table.concat(boardLines, '\n')
   print("=== PUZZLE CODE ===")
   print(boardStr)
   print("==================")
      print("Puzzle loaded!")
      return false, false, board
   else
      print("Invalid code!")
      return false, false, board
   end
end

   if crdn == 'h' then
      local mv = findMateIn1Move(curPos)
      if mv then
          print("----")
         print("Solution: " .. render(mv[0 + __1]) .. render(mv[1 + __1]) .. " (mate)")
      else
         print("Couldn't find a solution \n(shouldn't happen).")
        
      print("Generating puzzle, please wait...")
   local board = genAiMateIn1()
   return false, false, board
      end
      return false, false, board
   end

   local move = {parse(crdn:sub(1,2)), parse(crdn:sub(3,4))}
   local from = move[1]
   if not (from and move[2]) then
      print(crdn .. " - Invalid format. Enter a move like 'd2d4'")
   elseif not isupper(curPos.board:sub(from + __1, from + __1)) then
      print(crdn .. " - There's no piece of yours on that square.")
   elseif not ttfind(curPos:genMoves(), move) then
      print(crdn .. " - That move is not allowed.")
   elseif not isLegalMove(curPos, move) then
      print(crdn .. " - That move leaves your king in check.")
   else
      local newPos = curPos:move(move)
      local checkers = findCheckers(newPos)
      if next(checkers) and not hasLegalMove(newPos) then
         print(crdn .. " - Checkmate!")
         print("")
         return true, false, board
      else
         print(crdn .. " - Not mate. Try again.")
      end
   end
   return false, false, board
end

local function aipuzMate1()
   print("")
   print("=== PUZZLE MODE: MATE IN 1 ===")
   print("• 'h' for hint")
   print("• 'q' to quit.")
   print("")
   print("Generating puzzle, please wait...")
   local board = genAiMateIn1()
   if not board then
      print("Couldn't generate a puzzle, try again.")
      return
   end
   while true do
      local solved, quit, newBoard = attemptAiPuzzle(board)
      board = newBoard
      if quit then return end
      if solved then
         print("Generating new puzzle...")
         board = genAiMateIn1()
         if not board then
            print("Couldn't generate a new puzzle, try again.")
            return
         end
      end
   end
end

-------------------------------------------------------------------------------
-- Main game loop
-------------------------------------------------------------------------------

local function main()
   local pos = Position.new(initial, 0, {true,true}, {true,true}, 0, 0)
   local capturedByUser = {}
   local capturedByEngine = {}
   local lastMove = nil
   local whiteMoves = 0
   local blackMoves = 0
   local halfmoveClock = 0  -- resets on capture or pawn move; draw at 100 (50 full moves)
-- Position hashes seen this game; lets search() score repeats as a draw. Seeded with the starting position.
   local gameHistory = { [tpKey(pos)] = true }
-- Same keys as gameHistory but counts occurrences, to detect actual threefold repetition and end the game.
   local positionCounts = { [tpKey(pos)] = 1 }
-- Full move history, one entry per ply: {notation, by}. Used by 'm' (move list) and 's<N>' (save as of move N).
   local moveHistory = {}
-- Snapshot of full state after each of your moves, keyed by move number; lets 's<N>' save as of move N even after playing further.
   local moveSnapshots = {}

   print("")
   print("=== sunfish.lua v" .. SCRIPT_VERSION .." ===")
   print("• 'h' for help")
   print("• 'q' to quit.")

   while true do
      local checkers = findCheckers(pos)
      local guards = findKingGuards(pos, checkers)
      if next(checkers) then
         print("Check!")
      end
      printboard(pos.board, lastMove, checkers, guards)
print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))

            local usermove = nil
while true do
    print("Your ".. (whiteMoves + 1) ..". move: ")
   local startInputTime = os.clock()  -- Počni mjerenje vremena
   local crdn = input()
   local inputElapsed = os.clock() - startInputTime  -- Izračunaj proteklo vrijeme
   if not crdn then
      print("\nNo input from terminal (EOF). Ending game.")
      return
   end
   if crdn == '' then
      print("----")
      goto continue
   end
   if crdn == 'q' then
       print("----")
      print("Quitting game.")
      return
   elseif crdn == 'u' then
      print("----")
   checkForUpdate()
   displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
      elseif crdn == 'a' then
   SHOW_ANNOTATIONS = not SHOW_ANNOTATIONS
   print("----")
   print("Annotations: " .. (SHOW_ANNOTATIONS and "ON" or "OFF"))
   displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn == 'd' then
      USE_UNICODE_PIECES = not USE_UNICODE_PIECES
      updateDisplayMode()
      print("----")
      print("Display mode: " .. (USE_UNICODE_PIECES and "Unicode" or "Letters"))
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
      elseif crdn:match('^n%d+$') then
   local n = tonumber(crdn:match('^n(%d+)$'))
   if n and n >= 100 and n <= 50000 then
      NODES_SEARCHED = n
      TABLE_SIZE = NODES_SEARCHED * 25
      print("----")
      print("Node budget set to " .. NODES_SEARCHED)
      print("(table size " .. TABLE_SIZE .. ")")
   else
      print("----")
      print("Enter a number between 100 and 50000, e.g. 'n2000'")
   end
   print("")
   displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn == 's' then
      local code = saveGame(pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, "w", moveHistory)
      print("----")
      print("=== GAME CODE ===")
      print(code)
      print("================")
      print("")
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn:match('^s%d+$') then
      local n = tonumber(crdn:match('^s(%d+)$'))
      local snap = moveSnapshots[n]
      if not snap then
          print("----")
         print("No snapshot for move " .. n .. ". You've played " .. whiteMoves .. " move(s) so far.")
         print("")
      else
         local code = saveGame(snap.pos, snap.lastMove, snap.capturedByUser, snap.capturedByEngine,
                                snap.whiteMoves, snap.blackMoves, snap.halfmoveClock, "b", snap.moveHistory)
        print("----")
         print("=== GAME CODE (as of move " .. n .. ") ===")
         print(code)
         print("================")
         print("")
      end
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn == 'm' then
      if #moveHistory == 0 then
          print("----")
         print("No moves played yet.")
      else
          print("----")
         local out = {"=== MOVE LIST ==="}
         local i = 1
         while i <= #moveHistory do
            local w = moveHistory[i]
            local bEntry = moveHistory[i + 1]
            local moveNum = math.floor((i + 1) / 2)
            local line = moveNum .. ". " .. w.notation
            if bEntry then
               line = line .. "  " .. bEntry.notation
            end
            table.insert(out, line)
            i = i + 2
         end
         table.insert(out, "================")
         table.insert(out, "")
-- Single print() call so the whole move list can be copied in one go, instead of one print() per line.
         print(table.concat(out, "\n"))
      end
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn == 'l' then
       print("----")
   print("Paste game code:")
   local code = input()
   if code and code ~= '' then
      local result = {loadGame(code)}
      if result[1] then
         pos = result[1]
         lastMove = result[2]
         capturedByUser = result[3]
         capturedByEngine = result[4]
         whiteMoves = result[5]
         blackMoves = result[6]
         halfmoveClock = result[7] or 0
         local nextToMove = result[8] or "b"
         local histStr = result[9]
         moveSnapshots = {}

-- Rebuild gameHistory/positionCounts by replaying the saved move list from
-- the initial position, so threefold-repetition detection stays correct
-- across this save/load (falls back to seeding just the loaded position if
-- histStr is missing/unparseable, e.g. an older or hand-edited save code).
         gameHistory, positionCounts = rebuildHistoryFromMoves(histStr, pos)

-- Reconstruct the notation-only moveHistory (for the 'm' command) from the
-- same string, so it lines up with the replayed gameHistory/positionCounts.
         moveHistory = {}
         if histStr and histStr ~= '-' and histStr ~= '' then
            local i = 0
            for notation in histStr:gmatch('[^,]+') do
               i = i + 1
               moveHistory[i] = { notation = notation, by = (i % 2 == 1) and "you" or "sunfish" }
            end
         end

         local code = saveGame(pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, "w", moveHistory)
      print("----")
      print("=== GAME CODE ===")
      print(code)
      print("================")
         print("Game loaded!")
         print("")
         
         if nextToMove == "b" then
-- Sunfish's turn: show the saved lastMove, then play its reply as it would in a live game.
            if lastMove then
   print("Your move: \n" .. render(lastMove[1]) .. render(lastMove[2]))
   print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
               local checkersAfterYourMove = findCheckers(pos)
               local guardsAfterYourMove = findKingGuards(pos, checkersAfterYourMove)
               if next(checkersAfterYourMove) then
                  print("Check!")
               end
               printboard(pos.board, lastMove, checkersAfterYourMove, guardsAfterYourMove)
            end
            local rotated = pos:rotate()
            print("")
            print("Sunfish is thinking...")
local enginemove, score, reachedDepth, usedNodes, elapsed = search(pos, NODES_SEARCHED, gameHistory)
assert(score)
print(string.format("(depth %d, %d/%d nodes)", reachedDepth, usedNodes, NODES_SEARCHED))
            if enginemove and not isLegalMove(rotated, enginemove) then
               enginemove = nil
            end
            if not enginemove then
               local legal = legalMovesOf(rotated)
               if #legal > 0 then
                  table.sort(legal, function(a, b) return rotated:value(a) > rotated:value(b) end)
                  enginemove = legal[1]
               end
            end
            if enginemove then
               local engineCap = capturedAt(rotated, enginemove)
               local enginePawnMove = isPawnMove(rotated, enginemove)
               if engineCap or enginePawnMove then
                  halfmoveClock = 0
               else
                  halfmoveClock = halfmoveClock + 1
               end
               if engineCap then table.insert(capturedByEngine, engineCap) end
               local engineMoveNotation = render(119-enginemove[0 + __1]) .. render(119-enginemove[1 + __1])
               if enginemove[3] and enginemove[3] ~= '' and enginemove[3] ~= 'Q' then
                  engineMoveNotation = engineMoveNotation .. enginemove[3]:lower()
               end
               print("Sunfish move: \n" .. engineMoveNotation .. " (" .. math.floor(elapsed + 0.5) .. "s)")
               print("Captured: " .. renderCaptured(capturedByEngine, whiteSymbols))
               table.insert(moveHistory, {notation = engineMoveNotation, by = "sunfish"})
               pos = rotated:move(enginemove)
               blackMoves = blackMoves + 1
               pos.score = 0
               gameHistory[tpKey(pos)] = true
               positionCounts[tpKey(pos)] = (positionCounts[tpKey(pos)] or 0) + 1
               lastMove = {119 - enginemove[1], 119 - enginemove[2]}
            else
               print("Sunfish has no legal move (checkmate or stalemate).")
            end
         end

         if lastMove and nextToMove ~= "b" then
            print("Sunfish move: \n" .. render(lastMove[1]) .. render(lastMove[2]))
            print("Captured: " .. renderCaptured(capturedByEngine, whiteSymbols))
         end

         local checkers = findCheckers(pos)
         local guards = findKingGuards(pos, checkers)
         if next(checkers) then
            print("Check!")
         end
         printboard(pos.board, lastMove, checkers, guards)
print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
      else
         print("Invalid code. Game continues.")
         print("")
      end
   end
   elseif crdn == 'r' then
       print("----")
      print("You resigned. Black wins!")
      return
   elseif crdn == 'n' then
       print("----")
      print("Starting new game...")
      return main()
   elseif crdn == 'h' then
       print("----")
      showHelp()
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn == '?' then
       print("----")
      showAbout()
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn == 'm1' then
      aipuzMate1()
      print("Resuming the game.")
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   else
      usermove = {parse(crdn:sub(1,2)), parse(crdn:sub(3,4))}
      local from = usermove[1]
      if not (from and usermove[2]) then
         print(crdn.. " - Invalid format. Enter a move like 'a1a5'")
      elseif not isupper(pos.board:sub(from + __1, from + __1)) then
         print(crdn.. " - There's no piece of yours on that square.")
      elseif not ttfind(pos:genMoves(), usermove) then
         print(crdn.. " - That move is not allowed.")
      elseif not isLegalMove(pos, usermove) then
         print(crdn.. " - That move leaves your king in check.")
      else
         if isPromotionMove(pos, usermove) then
            print("Promote to (Q/R/B/N)? [default: Q]")
            local promoInput = input()
            local promoChar = promoInput and promoInput:upper():sub(1,1) or "Q"
            if promoChar ~= "Q" and promoChar ~= "R" and promoChar ~= "B" and promoChar ~= "N" then
               print("Invalid choice, defaulting to Queen.")
               promoChar = "Q"
            end
            usermove[3] = promoChar
-- ttfind() already auto-filled usermove[3] with 'Q'; overwrite with the player's actual promotion choice.
         end
 whiteMoves = whiteMoves + 1
print(crdn .. " (" .. math.floor(inputElapsed + 0.5) .. "s)")
break
      end
   end
   ::continue::
end


      local userCap = capturedAt(pos, usermove)
      local userPawnMove = isPawnMove(pos, usermove)
      if userCap or userPawnMove then
         halfmoveClock = 0
      else
         halfmoveClock = halfmoveClock + 1
      end
      if userCap then table.insert(capturedByUser, userCap) end
-- Promotion suffix (e.g. "a7a8n") is appended when the player promoted to
-- anything other than the default Queen, so 'm' displays it correctly and
-- rebuildHistoryFromMoves() can replay the exact resulting position.
      local userNotation = render(usermove[1]) .. render(usermove[2])
      if usermove[3] and usermove[3] ~= '' and usermove[3] ~= 'Q' then
         userNotation = userNotation .. usermove[3]:lower()
      end
      table.insert(moveHistory, {
         notation = userNotation,
         by = "you"
      })
      pos = pos:move(usermove)
pos.score = 0
gameHistory[tpKey(pos)] = true
positionCounts[tpKey(pos)] = (positionCounts[tpKey(pos)] or 0) + 1

-- Snapshot for 's<N>'; pos is in Black's rotated view here, so store the White-view rotation to match saveGame()/loadGame().
      moveSnapshots[whiteMoves] = {
         pos = pos:rotate(),
         lastMove = {usermove[1], usermove[2]},
         capturedByUser = {table.unpack(capturedByUser)},
         capturedByEngine = {table.unpack(capturedByEngine)},
         whiteMoves = whiteMoves,
         blackMoves = blackMoves,
         halfmoveClock = halfmoveClock,
         moveHistory = {table.unpack(moveHistory)},
      }

      local checkersAfterUser = findCheckers(pos)
      local guardsAfterUser = findKingGuards(pos, checkersAfterUser)
      local engineHasMove = hasLegalMove(pos)
      local isMateNow = next(checkersAfterUser) ~= nil and not engineHasMove
      local displayCheckers = {}
      local displayGuards = {}
      for idx in pairs(checkersAfterUser) do
         displayCheckers[119 - idx] = true
      end
      for idx in pairs(guardsAfterUser) do
         displayGuards[119 - idx] = true
      end
      if next(displayCheckers) then
         print("Check!")
      end
      printboard(pos:rotate().board, {usermove[1], usermove[2]}, displayCheckers, displayGuards, isMateNow)

      if isMateNow then
         print("Checkmate in " .. whiteMoves .. " moves for White!")
         print("You won")
         break
      end
      if not engineHasMove then
         print("Stalemate - draw!")
         break
      end
      if halfmoveClock >= 100 then
         print("Draw by 50-move rule!")
         break
      end
      if positionCounts[tpKey(pos)] >= 3 then
         print("Draw by threefold repetition!")
         break
      end
      print("Sunfish is thinking...")
local enginemove, score, reachedDepth, usedNodes, elapsed = search(pos, NODES_SEARCHED, gameHistory)
assert(score)
print(string.format("(depth %d, %d/%d nodes)", reachedDepth, usedNodes, NODES_SEARCHED))

      if score <= -MATE_UPPER then
         print("Checkmate in " .. whiteMoves .. " moves for White!")
         print("You won")
         break
      end

      if enginemove and not isLegalMove(pos, enginemove) then
         enginemove = nil
      end

      if not enginemove then
         local legal = legalMovesOf(pos)
         if #legal == 0 then
            if next(findCheckers(pos)) then
               print("Checkmate in " .. whiteMoves .. " moves for White!")
               print("You won")
            else
               print("Stalemate - draw!")
            end
            break
         else
            table.sort(legal, function(a, b) return pos:value(a) > pos:value(b) end)
            enginemove = legal[1]
         end
      end

      local engineCap = capturedAt(pos, enginemove)
      local enginePawnMove = isPawnMove(pos, enginemove)
      if engineCap or enginePawnMove then
         halfmoveClock = 0
      else
         halfmoveClock = halfmoveClock + 1
      end
      if engineCap then table.insert(capturedByEngine, engineCap) end

      local engineMoveNotation = render(119-enginemove[0 + __1]) .. render(119-enginemove[1 + __1])
      if enginemove[3] and enginemove[3] ~= '' and enginemove[3] ~= 'Q' then
         engineMoveNotation = engineMoveNotation .. enginemove[3]:lower()
      end
print("Sunfish ".. (blackMoves + 1) ..". move: \n" .. engineMoveNotation .. " (" .. math.floor(elapsed + 0.5) .. "s)")
print("Captured: " .. renderCaptured(capturedByEngine, whiteSymbols))
table.insert(moveHistory, {notation = engineMoveNotation, by = "sunfish"})
pos = pos:move(enginemove)
blackMoves = blackMoves + 1
pos.score = 0  -- CRITICAL!
gameHistory[tpKey(pos)] = true
positionCounts[tpKey(pos)] = (positionCounts[tpKey(pos)] or 0) + 1
      lastMove = {119 - enginemove[1], 119 - enginemove[2]}

      if halfmoveClock >= 100 then
         printboard(pos.board, lastMove, {}, {})
         print("Draw by 50-move rule!")
         break
      end
      if positionCounts[tpKey(pos)] >= 3 then
         printboard(pos.board, lastMove, {}, {})
         print("Draw by threefold repetition!")
         break
      end
      if score >= MATE_UPPER then
   -- Confirm actual mate rather than trusting the score alone.
   local matingCheckers = findCheckers(pos)
   local matingGuards = findKingGuards(pos, matingCheckers)

   -- Check + no legal moves = mate.
   if next(matingCheckers) and not hasLegalMove(pos) then
      printboard(pos.board, lastMove, matingCheckers, matingGuards, true)
      print("Checkmate!")
      print("You lost")
      break
   else
      -- Score was wrong; play the move and continue.
      print("Evaluation error detected. Continuing game...")
   end
end
   end
end

math.randomseed(os.time())

main()
