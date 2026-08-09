-- sunfish.lua
-- Chess engine, Lua port chain:
--   1. Original algorithm: Sunfish (Python) by Thomas Ahle
--  https://github.com/thomasahle/sunfish - BSD license
--  2. Initial Lua transpilation attributed to Soumith Chintala
--  3. Extended for Yantra Launcher Pro / Android (Luaj-jse 3.0.1), with UI, save/load, puzzle mode, and search tuning, by borko17 (https://github.com/borko17/sunfish-lua), with help from Claude AI.

-------------------------------------------------------------------------------
-- CONFIG: Options at the top
-------------------------------------------------------------------------------
-- Show pieces as Unicode symbols (true) or as letters KQBRN (false)
local USE_UNICODE_PIECES = false
-- Toggle for ( ) ? ! annotation markers
local SHOW_ANNOTATIONS = true

-- Node budget per search. Higher values search deeper but take longer per
-- move on-device; 5000 is a reasonable ceiling before per-move wait times
-- and transposition-table churn start to matter (see TABLE_SIZE below).
local NODES_SEARCHED = 4000

-- Max entries in the transposition table. Reduced from 1e6: Luaj-jse runs
-- interpreted on the JVM, and a 1e6-entry table is heavy on a phone.
-- Scaled off NODES_SEARCHED (x25) so the table doesn't thrash (fill and
-- evict via tp_popitem) when the node budget is raised - a table sized for
-- 500 nodes gains little from a cache that's already full mid-search once
-- the budget is 5000+.
local TABLE_SIZE = NODES_SEARCHED * 25

-- Mate value must exceed 8*queen + 2*(rook+knight+bishop). King value is
-- set to twice this so that being up 8 queens still loses to losing the king.
local MATE_VALUE = 30000

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
local SCRIPT_VERSION = "2.608090722"
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/borko17/sunfish-lua/main/sunfish.lua"

-- What's new in the currently running version. Used as a fallback when
-- the remote GitHub file can't be reached or parsed (see checkForUpdate).
local CHANGELOG = {
   "50-move-rule draw detection",
   "halfmove clock now saved/loaded with game codes",
   "in-app GitHub version check ('u')",
   "'m' shows the full move history",
   "'sN' saves the position as of move N",
   "loaded games now correctly resume with the right side to move",
}

-- Parses a Lua "local CHANGELOG = { \"a\", \"b\", ... }" block out of raw
-- script text and returns it as a Lua array of strings. Used to read the
-- changelog straight out of the remote file fetched from GitHub, not the
-- copy running locally, so 'u' always shows what's new in the latest
-- version rather than the version currently installed.
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

local function checkForUpdate()
   print("")
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
      print("Showing changelog for your installed version instead:")
      printChangelog(CHANGELOG, SCRIPT_VERSION)
      return
   end

   local remoteVersion = result:match('SCRIPT_VERSION%s*=%s*"([%d%.]+)"')
   if not remoteVersion then
      print("Could not find a version number in the GitHub file.")
      print("Showing changelog for your installed version instead:")
      printChangelog(CHANGELOG, SCRIPT_VERSION)
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
      print("Showing changelog for your installed version instead:")
      printChangelog(CHANGELOG, SCRIPT_VERSION)
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

-- Endgame king table ("mop-up"): once one side is down to a bare king, the
-- midgame table above gives search no progress signal - every king shuffle
-- scores the same and won K+R vs K / K+Q vs K endings drift toward the
-- 50-move horizon instead of converging. This table instead rewards
-- centralization: value falls the further a square is from the center.
-- Formula: 60000 + 70 - 10*(|2*rank-7| + |2*file-7|), rank/file in 0..7.
-- Because the board is shared (via rotate) between both sides, the same
-- table simultaneously drives a bare king toward the edge and our own
-- king toward the center - the two halves of classical mop-up technique.
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

-- Keep the original midgame king table around so we can swap back.
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

-- Position "class" via a metatable (__index) instead of copying every method
-- into every instance - that copy loop runs on every Position created during
-- search (thousands of times per move), and setmetatable is O(1) on Luaj-jse.
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
            local limit = (i+d) + (10000) * d -- fake limit
            for j=i+d, limit, d do
               local q = self.board:sub(j + __1, j + __1)
               if isspace(self.board:sub(j + __1, j + __1)) then break; end
               if i == A1 and q == 'K' and self.wc[0 + __1] then
                  table.insert(moves,  {j, j-2})
               end
               if i == H1 and q == 'K' and self.wc[1 + __1] then
                  table.insert(moves,  {j, j+2})
               end
               if isupper(q) then break; end
               if p == 'P' and (d == N+W or d == N+E) and q == '.' and j ~= self.ep and j ~= self.kp then
                  break;
               end
               if p == 'P' and (d == N or d == 2*N) and q ~= '.' then
                  break;
               end
               if p == 'P' and d == 2*N and (i < A1+N or self.board:sub(i+N + __1, i+N + __1) ~= '.') then
                  break;
               end
               table.insert(moves, {i, j})
               if p == 'P' or p == 'N' or p == 'K' then break; end
               if islower(q) then break; end
            end
         end
      end
   end
   return moves
end

function Position:rotate()
   return self.new(
      swapcase(self.board:reverse()), -self.score,
      self.bc, self.wc, 119-self.ep, 119-self.kp)
end

function Position:move(move)
   assert(move)
   local i, j = move[0 + __1], move[1 + __1]
   local p, q = self.board:sub(i + __1, i + __1), self.board:sub(j + __1, j + __1)
   local function put(board, i, p)
      return board:sub(1, i-1) .. p .. board:sub(i+1)
   end
   local board = self.board
   local wc, bc, ep, kp = self.wc, self.bc, 0, 0
   local score = self.score + self:value(move)
   board = put(board, j + __1, board:sub(i + __1, i + __1))
   board = put(board, i + __1, '.')
   if i == A1 then wc = {false, wc[0 + __1]}; end
   if i == H1 then wc = {wc[0 + __1], false}; end
   if j == A8 then bc = {bc[0 + __1], false}; end
   if j == H8 then bc = {false, bc[1 + __1]}; end
   if p == 'K' then
      wc = {false, false}
      if math.abs(j-i) == 2 then
         kp = math.floor((i+j)/2)
         board = put(board, j < i and A1 + __1 or H1 + __1 , '.')
         board = put(board, kp + __1, 'R')
      end
   end
   if p == 'P' then
      if A8 <= j and j <= H8 then
         board = put(board, j + __1, 'Q')
      end
      if j - i == 2*N then
         ep = i + N
      end
      if ((j - i) == N+W or (j - i) == N+E) and q == '.' then
         board = put(board, j+S + __1, '.')
      end
   end
   return self.new(board, score, wc, bc, ep, kp):rotate()
end

function Position:value(move)
   local i, j = move[0 + __1], move[1 + __1]
   local p, q = self.board:sub(i + __1, i + __1), self.board:sub(j + __1, j + __1)
   local score = pst[p][j + __1] - pst[p][i + __1]
   if islower(q) then
      score = score + pst[q:upper()][j + __1]
   end
   if math.abs(j-self.kp) < 2 then
      score = score + pst['K'][j + __1]
   end
   if p == 'K' and math.abs(i-j) == 2 then
      score = score + pst['R'][math.floor((i+j)/2) + __1]
      score = score - pst['R'][j < i and A1 + __1 or H1 + __1]
   end
   if p == 'P' then
      if A8 <= j and j <= H8 then
         score = score + pst['Q'][j + __1] - pst['P'][j + __1]
      end
      if j == self.ep then
         score = score + pst['P'][j+S + __1]
      end
   end
   return score
end

-- Bare-king check for endgame PST swap: true once either side has only
-- its king left (no other uppercase/lowercase piece letters on the board).
-- Cheap single pass, done once per search() call - not per node.
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
local tp_index = {}
local tp_count = 0

local function tp_set(pos, val)
   local b1 = pos.bc[1] and 'true' or 'false'
   local b2 = pos.bc[2] and 'true' or 'false'
   local w1 = pos.bc[1] and 'true' or 'false'
   local w2 = pos.bc[2] and 'true' or 'false'
   local hash = pos.board .. ';' .. pos.score .. ';' .. w1 .. ';' .. w2 .. ';'
      .. b1 .. ';' .. b2 .. ';' .. pos.ep .. ';' .. pos.kp
   tp[hash] = val
   tp_index[#tp_index + 1] = hash
   tp_count = tp_count + 1
end

local function tp_get(pos)
   local b1 = pos.bc[1] and 'true' or 'false'
   local b2 = pos.bc[2] and 'true' or 'false'
   local w1 = pos.bc[1] and 'true' or 'false'
   local w2 = pos.bc[2] and 'true' or 'false'
   local hash = pos.board .. ';' .. pos.score .. ';' .. w1 .. ';' .. w2 .. ';'
      .. b1 .. ';' .. b2 .. ';' .. pos.ep .. ';' .. pos.kp
   return tp[hash]
end

local function tp_popitem()
   tp[tp_index[#tp_index]] = nil
   tp_index[#tp_index] = nil
   tp_count = tp_count - 1
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

local nodes = 0

-- Quiescence value floor. Was a flat 150; now depth-scaled like upstream
-- sunfish's QS/QS_A (val_lower = QS - depth*QS_A), so deeper quiescence
-- nodes admit slightly weaker-looking captures/threats before cutting off,
-- giving marginally better tactics without extra node budget.
local QS = 40
local QS_A = 140

local function bound(pos, gamma, depth)
    nodes = nodes + 1

    local entry = tp_get(pos)
    assert(depth)
    if entry ~= nil and entry.depth >= depth and (
            entry.score < entry.gamma and entry.score < gamma or
            entry.score >= entry.gamma and entry.score >= gamma) then
        return entry.score
    end

    if math.abs(pos.score) >= MATE_VALUE then
        return pos.score
    end

    -- Zugzwang guard: only try the null move (skip a turn) when there's
    -- search depth left AND the position isn't close to an endgame swing
    -- (|score| < 500). Without this guard, "passing" can look artificially
    -- good in low-material / near-mate positions where the side to move
    -- actually MUST move (classic zugzwang), leading to blunders in those
    -- endgames. This mirrors upstream sunfish's null-move condition.
    local nullscore
    if depth > 2 and math.abs(pos.score) < 500 then
        nullscore = -bound(pos:rotate(), 1-gamma, depth-3)
    else
        nullscore = pos.score
    end
    if nullscore >= gamma then
        return nullscore
    end

    local best, bmove = -3*MATE_VALUE, nil
    local moves = pos:genMoves()
    -- Enhanced move ordering with check bonus
    -- Faster sorter - without pos:move()
    local function sorter(a, b)
       local va = pos:value(a)
       local vb = pos:value(b)

       -- Quick check: is it a capture (value > 150)?
       -- These are usually checks and good moves
       if va ~= vb then
          return va > vb
       else
          if a[1] == b[1] then
             return a[2] > b[2]
          else
             return a[1] < b[1]
          end
       end
    end

    table.sort(moves, sorter)
    -- Depth-scaled quiescence floor (see QS/QS_A above) instead of a flat 150.
    local val_lower = QS - depth * QS_A
    for _,move in ipairs(moves) do
       if depth <= 0 and pos:value(move) < val_lower then
          break
       end
       local score = -bound(pos:move(move), 1-gamma, depth-1)
        if score > best then
           best = score
           bmove = move
        end
        if score >= gamma then
           break
        end
    end

    if depth <= 0 and best < nullscore then
       return nullscore
    end
    if depth > 0 and (best <= -MATE_VALUE) and nullscore > -MATE_VALUE then
       best = 0
    end

    if entry == nil or depth >= entry.depth and best >= gamma then
       tp_set(pos, {depth = depth, score = best, gamma = gamma, move = bmove})
       if tp_count > TABLE_SIZE then
          tp_popitem()
       end
    end
    return best
end

local function search(pos, maxn)
   maxn = maxn or NODES_SEARCHED
   nodes = 0
   local score

   -- Endgame PST swap: once either side is down to a bare king, switch the
   -- king table to the centralizing "mop-up" version for this whole search
   -- so the engine actually makes progress driving a lone king to the edge
   -- (or its own king to the center) instead of shuffling forever. Done
   -- once per search() call - a single O(board) scan, not per node - so it
   -- costs nothing noticeable on top of the existing node budget.
   if isBareKingBoard(pos.board) then
      pst.K = pst_K_endgame
   else
      pst.K = pst_K_midgame
   end

   for depth=1,98 do
      local lower, upper = -3*MATE_VALUE, 3*MATE_VALUE
      while lower < upper - 3 do
         local gamma = math.floor((lower+upper+1)/2)
         score = bound(pos, gamma, depth)
         assert(score)
         if score >= gamma then
            lower = score
         end
         if score < gamma then
            upper = score
         end
      end
      assert(score)

      if nodes >= maxn or math.abs(score) >= MATE_VALUE then
         break
      end
   end

   local entry = tp_get(pos)
   if entry ~= nil then
      return entry.move, score
   end
   return nil, score
end

-------------------------------------------------------------------------------
-- Display symbols
-------------------------------------------------------------------------------

-- Empty square symbols
local emptySquareSymbols_unicode = {
   dark = '\xe2\x80\xa2',
   light = '\xe2\x97\xa6'
}
local emptySquareSymbols_letters = {
   dark = ':',
   light = '.'
}

-- Unicode symbols for pieces
local whiteSymbols_unicode = {
   K = '\xe2\x99\x94', Q = '\xe2\x99\x95', R = '\xe2\x99\x96',
   B = '\xe2\x99\x97', N = '\xe2\x99\x98', P = '\xe2\x99\x99',
}
local blackSymbols_unicode = {
   K = '\xe2\x99\x9a', Q = '\xe2\x99\x9b', R = '\xe2\x99\x9c',
   B = '\xe2\x99\x9d', N = '\xe2\x99\x9e', P = '\xe2\x99\x9f',
}

-- Letter symbols for pieces
local whiteSymbols_letters = {
   K = 'K', Q = 'Q', R = 'R', B = 'B', N = 'N', P = 'P',
}
local blackSymbols_letters = {
   K = 'k', Q = 'q', R = 'r', B = 'b', N = 'n', P = 'p',
}

-- Current symbols (will be updated by updateDisplayMode)
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
   if not k then return false end
   for _,v in ipairs(t) do
      if k[1] == v[1] and k[2] == v[2] then
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

-- Board rendering
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

-- True if the piece moving from move[1] is a pawn. Used to reset the
-- 50-move-rule halfmove clock, alongside captures (see capturedAt above).
local function isPawnMove(pos, move)
   local i = move[0 + __1]
   local p = pos.board:sub(i + __1, i + __1)
   return p == 'P'
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

local function saveGame(pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, nextToMove)
   local pieces = {}
   for i = 21, 98 do
      local c = pos.board:sub(i + __1, i + __1)
      if not isspace(c) then
         table.insert(pieces, c)
      end
   end
   local boardStr = table.concat(pieces)

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

   -- "b" = Sunfish moves next (the normal case: 's' saves the position
   -- right after your move, before Sunfish replies). "w" = you move next
   -- (used by 'sN' snapshots, where Sunfish's reply to move N was already
   -- played and recorded before the snapshot was taken).
   local nextStr = (nextToMove == "w") and "w" or "b"

   local code = boardStr .. '|' .. wcStr .. '|' .. bcStr .. '|' .. epStr .. '|' .. 
                lastMoveStr .. '|' .. userCapStr .. '|' .. engineCapStr .. '|' .. 
                whiteMoves .. '|' .. blackMoves .. '|' .. (halfmoveClock or 0) .. '|' .. nextStr

   return code
end

local function loadGame(code)
   local parts = {}
   for part in code:gmatch('[^|]+') do
      table.insert(parts, part)
   end

   if #parts < 9 then
      print("Invalid code! Expected at least 9 parts, got " .. #parts)
      return nil
   end

   local boardStr = parts[1]
   local wcStr = parts[2]
   local bcStr = parts[3]
   local epStr = parts[4]
   local lastMoveStr = parts[5]
   local userCapStr = parts[6]
   local engineCapStr = parts[7]
   local whiteMoves = tonumber(parts[8]) or 0
   local blackMoves = tonumber(parts[9]) or 0
   local halfmoveClock = tonumber(parts[10]) or 0
   local nextToMove = parts[11] or "b"  -- old codes (no 11th field) always meant Sunfish's turn next

   if #boardStr ~= 64 then
      print("Invalid board! Expected 64 characters, got " .. #boardStr)
      return nil
   end

   local fullBoard = '         \n         \n '
   for i = 1, 64 do
      fullBoard = fullBoard .. boardStr:sub(i, i)
      if i % 8 == 0 and i < 64 then
         fullBoard = fullBoard .. '\n '
      end
   end
   fullBoard = fullBoard .. '\n         \n          '

   local wc1 = wcStr:sub(1,1) == '1'
   local wc2 = wcStr:sub(2,2) == '1'
   local bc1 = bcStr:sub(1,1) == '1'
   local bc2 = bcStr:sub(2,2) == '1'

   local ep = tonumber(epStr) or 0

   local pos = Position.new(fullBoard, 0, {wc1, wc2}, {bc1, bc2}, ep, 0)

   local capturedByUser = {}
   if userCapStr ~= '-' then
      for i = 1, #userCapStr do
         table.insert(capturedByUser, userCapStr:sub(i,i))
      end
   end

   local capturedByEngine = {}
   if engineCapStr ~= '-' then
      for i = 1, #engineCapStr do
         table.insert(capturedByEngine, engineCapStr:sub(i,i))
      end
   end

   local lastMove = nil
   if lastMoveStr ~= '--' and #lastMoveStr == 4 then
      lastMove = {parse(lastMoveStr:sub(1,2)), parse(lastMoveStr:sub(3,4))}
   end

   return pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, nextToMove
end

local function displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   local checkers = findCheckers(pos)
   local guards = findKingGuards(pos, checkers)
   if next(checkers) then
      print("Check!")
   end
   printboard(pos.board, lastMove, checkers, guards)
   print(renderCaptured(capturedByUser, whiteSymbols))
   print(renderCaptured(capturedByEngine, blackSymbols))
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
   print("'d' - Toggle display mode:")
   print("(Unicode symbols <-> Letters)")
   print("'a' - Toggle annotations")
   print("(show/hide board markers)")
   print("'s' - Save game (generate code)")
   print("'sN' - Save position as of move N")
   print("(e.g. 's15' saves after move 15,")
   print("even if you've played further)")
   print("'l' - Load saved game")
   print("'m' - Show move history")
   print("'r' - Resign current game")
   print("'n' - Start a new game")
   print("'u' - Check sunfish.lua update")
   print("'q' - Quit chess.lua")
   print("")
   print("Note: draws are auto-declared under")
   print("the 50-move-no-progress rule (no")
   print("capture or pawn move in 50 moves)")
   print("")
   print("COMMANDS FOR PUZZLE MODE:")
   print("-------------")
   print("'m1' - Enter Mate-in-1 puzzle mode")
   print("'h' - for hint in puzzles")
   print("'s' - Save puzzle")
   print("'l' - Load saved puzzle")
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
   print("• Unifont / GNU Unifont")
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
   print("Adapted for Yantra Launcher Pro") 
   print("on Android (Luaj-jse 3.0.1)")
   print("by borko17 (github.com/borko17),")
   print("with help from Claude AI.")
   print("")
   print("Original Python code license: BSD")
   print("")
   print("KEY CHANGES FOR PHONE USE:")
   print("-------------")
   print("• Node-budget search instead of a timer")
   print("• Smaller, budget-scaled transposition table")
   print("• Zugzwang guard on null-move pruning")
   print("• Endgame king-centralization table")
   print("• Depth-scaled quiescence threshold")
   print("")
   print("EXTRA FEATURES:")
   print("-------------")
   print("• Full legal-move / check / stalemate detection")
   print("• 50-move-rule draw detection")
   print("• Save & Load games via text codes")
   print("• Move history ('m') and per-move save ('sN')")
   print("• Unicode or letter piece display")
   print("• Check / guard / last-move board markers")
   print("• Captured-piece tracking")
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

         -- If a specific color is requested, check it
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

         -- White pieces
         for _ = 1, numWhiteExtra do
            local pc = pickCappedPieceType(aiWhitePool, whiteCounts)
            if not pc then break end

            -- Determine color for bishops first
            local forcedColor = nil
            if pc == 'B' then
               if not whiteBishopColor then
                  whiteBishopColor = math.random(0, 1)
                  forcedColor = whiteBishopColor
               else
                  forcedColor = 1 - whiteBishopColor
               end
            end

            -- Then use it in randomFreeSquare
            local idx = randomFreeSquare(occupied, pc == "P", forcedColor)
            if not idx then ok = false; break end
            occupied[idx] = true
            board = aiPut(board, idx + __1, pc)
            whiteCounts[pc] = (whiteCounts[pc] or 0) + 1
         end

         -- Black pieces
         if ok then
            for _ = 1, numBlackExtra do
               local pc = pickCappedPieceType(aiBlackPool, blackCounts)
               if not pc then break end

               -- Same for black bishops
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

local function attemptAiPuzzle(board)
   local curPos = Position.new(board, 0, {false,false}, {false,false}, 0, 0)
   printboard(curPos.board)
   print("Find mate in 1 move: ")
   local crdn = input()
   if not crdn then
      print("No input (EOF). Ending puzzle mode.")
      return false, true
   end
   if crdn == 'q' then
      print("")
      print("Leaving puzzle mode.")
      return false, true
   end
   if crdn == 'd' then
   USE_UNICODE_PIECES = not USE_UNICODE_PIECES
   updateDisplayMode()
   print("")
   print("Mode: " .. (USE_UNICODE_PIECES and "Unicode" or "Letters"))
   return false, false
end

-- Save puzzle
if crdn == 's' then
   local pieces = {}
   for i = 21, 98 do
      local c = curPos.board:sub(i + __1, i + __1)
      if not isspace(c) then
         table.insert(pieces, c)
      end
   end
   local boardStr = table.concat(pieces)
   print("")
   print("=== PUZZLE CODE ===\n" .. boardStr .. "\n==================")
   return false, false
end

-- Load puzzle
if crdn == 'l' then
   print("")
   print("Paste puzzle code:")
   local code = input()
   if code and code ~= '' and #code == 64 then
      local fullBoard = '         \n         \n '
      for i = 1, 64 do
         fullBoard = fullBoard .. code:sub(i, i)
         if i % 8 == 0 and i < 64 then
            fullBoard = fullBoard .. '\n '
         end
      end
      fullBoard = fullBoard .. '\n         \n          '
      board = fullBoard
      print("Puzzle loaded!")
      return false, false
   else
      print("Invalid code!")
      return false, false
   end
end

local move = {parse(crdn:sub(1,2)), parse(crdn:sub(3,4))}
   if crdn == 'h' then
      local mv = findMateIn1Move(curPos)
      if mv then
          print("")
         print("Solution: " .. render(mv[0 + __1]) .. render(mv[1 + __1]) .. " (mate)")
      else
          print("")
         print("Couldn't find a solution (shouldn't happen).")
      end
      return false, false
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
         return true, false
      else
         print(crdn .. " - Not mate. Try again.")
      end
   end
   return false, false
end

local function aipuzMate1()
    print("")
   print("=== Puzzle mode: mate in 1. ===")
   print("")
   print("• 'h' for hint")
   print("• 'q' to quit.")
   print("")
   print("Generating puzzle, please wait...")
   local board = genAiMateIn1()
   if not board then
       print("")
      print("Couldn't generate a puzzle, try again.")
      return
   end
   while true do
      local solved, quit = attemptAiPuzzle(board)
      if quit then return end
      if solved then
          print("")
         print("Generating new puzzle...")
         board = genAiMateIn1()
         if not board then
             print("")
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
   -- Full move history, in order, one entry per ply. Each entry is a table
   -- {notation = "e2e4", by = "you"/"sunfish"}. Used by the 'm' command
   -- (move list) and by 's<N>' (save the position as of move N).
   local moveHistory = {}
   -- Snapshot of every full state after each of your moves, keyed by move
   -- number (1-based, matching what's shown as "Your N. move"). Lets
   -- 's<N>' save the position as it was after move N even if you've since
   -- played further. Stored only after your (White's) moves, since that's
   -- the natural "move number" a player thinks in.
   local moveSnapshots = {}
   
   print("")
   print("=== sunfish.lua v" .. SCRIPT_VERSION .." ===")
   print("")
   print("• 'h' for help")
   print("• 'q' to quit.")

   while true do
      local checkers = findCheckers(pos)
      local guards = findKingGuards(pos, checkers)
      if next(checkers) then
         print("Check!")
      end
      printboard(pos.board, lastMove, checkers, guards)
      print(renderCaptured(capturedByUser, whiteSymbols))

      local usermove = nil
while true do
    print("Your ".. (whiteMoves + 1) ..". move: ")  -- display +1 without incrementing
   local crdn = input()
   if not crdn then
      print("\nNo input from terminal (EOF). Ending game.")
      return
   end
   if crdn == 'q' then
      print("")
      print("Quitting game.")
      return
      elseif crdn == 'u' then
   checkForUpdate()
   displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
      elseif crdn == 'a' then
   SHOW_ANNOTATIONS = not SHOW_ANNOTATIONS
   print("")
   print("Annotations: " .. (SHOW_ANNOTATIONS and "ON" or "OFF"))
   displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn == 'd' then
      USE_UNICODE_PIECES = not USE_UNICODE_PIECES
      updateDisplayMode()
      print("")
      print("Display mode: " .. (USE_UNICODE_PIECES and "Unicode" or "Letters"))
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn == 's' then
      local code = saveGame(pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, "w")
      print("")
      print("=== GAME CODE ===")
      print(code)
      print("================")
      print("")
      print("Current position:")
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn:match('^s%d+$') then
      local n = tonumber(crdn:match('^s(%d+)$'))
      local snap = moveSnapshots[n]
      if not snap then
         print("No snapshot for move " .. n .. ". You've played " .. whiteMoves .. " move(s) so far.")
      else
         local code = saveGame(snap.pos, snap.lastMove, snap.capturedByUser, snap.capturedByEngine,
                                snap.whiteMoves, snap.blackMoves, snap.halfmoveClock, "b")
         print("")
         print("=== GAME CODE (as of move " .. n .. ") ===")
         print(code)
         print("================")
      end
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn == 'm' then
      if #moveHistory == 0 then
         print("")
         print("No moves played yet.")
      else
         print("")
         print("=== MOVE LIST ===")
         local i = 1
         while i <= #moveHistory do
            local w = moveHistory[i]
            local bEntry = moveHistory[i + 1]
            local moveNum = math.floor((i + 1) / 2)
            local line = moveNum .. ". " .. w.notation
            if bEntry then
               line = line .. "  " .. bEntry.notation
            end
            print(line)
            i = i + 2
         end
         print("================")
      end
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn == 'l' then
   print("")
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
         moveHistory = {}
         moveSnapshots = {}
         print("")
         print("=== GAME CODE ===")
         print(code)
         print("================")
         print("Game loaded!\n")

         if nextToMove == "b" then
            -- It's Sunfish's turn: show your move that was saved (lastMove
            -- holds it in this case), then play Sunfish's reply now, same
            -- as it would have happened right after your move in a live
            -- game, so control correctly returns to you afterward.
            if lastMove then
               print("Your move: \n" .. render(lastMove[1]) .. render(lastMove[2]))
               print(renderCaptured(capturedByUser, whiteSymbols))
               local checkersAfterYourMove = findCheckers(pos)
               local guardsAfterYourMove = findKingGuards(pos, checkersAfterYourMove)
               if next(checkersAfterYourMove) then
                  print("Check!")
               end
               printboard(pos.board, lastMove, checkersAfterYourMove, guardsAfterYourMove)
            end
            local rotated = pos:rotate()
            print("Sunfish is thinking...")
            local enginemove, score = search(rotated)
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
               print("Sunfish move: \n" .. engineMoveNotation)
               print(renderCaptured(capturedByEngine, blackSymbols))
               table.insert(moveHistory, {notation = engineMoveNotation, by = "sunfish"})
               pos = rotated:move(enginemove)
               blackMoves = blackMoves + 1
               pos.score = 0
               lastMove = {119 - enginemove[1], 119 - enginemove[2]}
            else
               print("Sunfish has no legal move (checkmate or stalemate).")
            end
         end

         -- Show engine's move (which is saved in lastMove)
         if lastMove and nextToMove ~= "b" then
            print("Sunfish move: \n" .. render(lastMove[1]) .. render(lastMove[2]))
            print(renderCaptured(capturedByEngine, blackSymbols))
         end

         -- Show board and your pieces
         local checkers = findCheckers(pos)
         local guards = findKingGuards(pos, checkers)
         if next(checkers) then
            print("Check!")
         end
         printboard(pos.board, lastMove, checkers, guards)
         print(renderCaptured(capturedByUser, whiteSymbols))
      else
         print("Invalid code. Game continues.")
      end
   end
   elseif crdn == 'r' then
      print("You resigned. Black wins!")
      return
   elseif crdn == 'n' then
      print("")
      print("Starting new game...")
      return main()
   elseif crdn == 'h' then
      showHelp()
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine)
   elseif crdn == '?' then
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
          whiteMoves = whiteMoves + 1
         break
      end
   end
end


      local userCap = capturedAt(pos, usermove)
      local userPawnMove = isPawnMove(pos, usermove)
      if userCap or userPawnMove then
         halfmoveClock = 0
      else
         halfmoveClock = halfmoveClock + 1
      end
      if userCap then table.insert(capturedByUser, userCap) end
      table.insert(moveHistory, {
         notation = render(usermove[1]) .. render(usermove[2]),
         by = "you"
      })
      pos = pos:move(usermove)

      -- Snapshot the position as of this move number, for 's<N>' later.
      -- pos is in Black's (rotated) view here, since Position:move()
      -- rotates internally - store the White-view rotation instead, to
      -- match what saveGame()/loadGame() expect (the same orientation
      -- used right after Sunfish's replies elsewhere in this loop).
      moveSnapshots[whiteMoves] = {
         pos = pos:rotate(),
         lastMove = {usermove[1], usermove[2]},
         capturedByUser = {table.unpack(capturedByUser)},
         capturedByEngine = {table.unpack(capturedByEngine)},
         whiteMoves = whiteMoves,
         blackMoves = blackMoves,
         halfmoveClock = halfmoveClock,
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

      print("Sunfish is thinking...")
      local enginemove, score = search(pos)
      assert(score)

      if score <= -MATE_VALUE then
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
print("Sunfish ".. (blackMoves + 1) ..". move: \n" .. engineMoveNotation)
print(renderCaptured(capturedByEngine, blackSymbols))
table.insert(moveHistory, {notation = engineMoveNotation, by = "sunfish"})
pos = pos:move(enginemove)
blackMoves = blackMoves + 1
-- Reset score
pos.score = 0  -- CRITICAL!
      lastMove = {119 - enginemove[1], 119 - enginemove[2]}

      if halfmoveClock >= 100 then
         printboard(pos.board, lastMove, {}, {})
         print("Draw by 50-move rule!")
         break
      end

      if score >= MATE_VALUE then
   -- First check if it's actually mate, not just what score says
   local matingCheckers = findCheckers(pos)
   local matingGuards = findKingGuards(pos, matingCheckers)

   -- If there IS check and NO legal moves - it's mate
   if next(matingCheckers) and not hasLegalMove(pos) then
      printboard(pos.board, lastMove, matingCheckers, matingGuards, true)
      print("Checkmate!")
      print("You lost")
      break
   else
      -- Score is WRONG - play the move and continue
      print("Evaluation error detected. Continuing game...")
   end
end
   end
end

math.randomseed(os.time())

main()
