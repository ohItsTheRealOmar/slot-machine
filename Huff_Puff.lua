--[[
  HUFF N' PUFF - a CC:Tweaked slot machine for the casino
  Same multi-station setup as Buffalo Bonus: one Computer runs a fully
  independent game on EVERY monitor wall it can see.

  BASE GAME
   - 5 reels x 3 rows, 10 fixed paylines (all always active).
   - WOLF is wild (reels 2-4 only).
   - BRICK scatters land on reels 1, 3 and 5 only -- RED, BLUE or YELLOW.
   - When 3 bricks trigger the bonus, each one drops into its color's
     PIG METER (0-3, side panel). Meters carry over between bonuses, so
     pigs build up over several triggers -- and 3 same-color bricks fill
     that pig in one go. A full meter shows READY!
   - Bricks on reels 1 AND 3 -> reel 5 keeps spinning longer with a
     heartbeat/rising-note suspense sound and a flashing frame.
   - 3 bricks (one on each of reels 1, 3, 5) -> the wolf huffs and puffs
     and the bonus starts.

  THE POP (which power-ups you get)
   - Every READY (3/3) pig pops for sure.
   - Every other pig gets a random chance to pop (better the fuller it is).
   - At least one pig always pops. Popped meters reset to 0; un-popped
     meters keep their progress for next time.
   - That gives 7 bonus flavors: RED, BLUE, YELLOW, RED+BLUE, RED+YELLOW,
     BLUE+YELLOW, and TRIPLE (all 3 + a shot at the GRAND).

  THE BONUS (same board every time -- power-ups change how it plays)
   - Four 4x3 grids. Grid 1 starts open with a few coins already on it.
   - 3 free spins. Any new coin resets spins back to 3 (never above 3).
   - Coins carry a cash value (a multiple of the total bet) or a
     MINI / MINOR / MAJOR jackpot. GRAND coins only exist in TRIPLE.
   - 5 coins total opens grid 2, 15 total opens grid 3, 23 total opens
     grid 4 (i.e. 5, then 10 more, then 8 more).
   - RED    : every spin, random empty tiles glow red -- a coin landing
              there is worth x2.
   - YELLOW : some coins land as SUPER coins -- each one turns a
              neighboring empty tile (same grid) into a coin too.
   - BLUE   : some coins land as COLLECTOR coins -- they add the value
              of every coin currently on the board to their own.
   - Power-ups stack; resolution order each spin is
              land -> red x2 -> yellow spreads -> blue collects.

  SETUP
   1. Build the monitor wall(s) out of Advanced Monitors (made for a
      6-wide x 3-tall wall, but the layout scales to any size).
   2. Attach them + an optional Speaker to one Advanced Computer.
   3. wget the raw URL of this file and run it.

  Money is practice credits per station for now -- the real player
  balance hookup (and the progressive GRAND) come later.
--]]

local c = colors
math.randomseed(os.epoch and os.epoch("utc") or os.time())

-- ============================= TUNING =============================
-- All the math knobs live here. Numbers were tuned by simulating a few
-- million spins (see sim_huff_puff.lua in the repo) to land ~95% RTP.

local REELS, ROWS = 5, 3

-- Line pays are multiples of the LINE bet (total bet / 10 lines).
local PAYS = {
  PIG  = { [3] = 12,  [4] = 45,  [5] = 180 },
  STIK = { [3] = 9,   [4] = 30,  [5] = 120 },
  STRW = { [3] = 7,   [4] = 24,  [5] = 90  },
  A    = { [3] = 4,   [4] = 12,  [5] = 45  },
  K    = { [3] = 4,   [4] = 10,  [5] = 40  },
  Q    = { [3] = 3,   [4] = 9,   [5] = 32  },
  J    = { [3] = 3,   [4] = 8,   [5] = 28  },
}
local PAY_SCALE = 2.1 -- global multiplier on PAYS (sim-tuned)

-- symbol weights on the reel strips (WOLF only appears on WILD_REELS)
local BASE_WEIGHTS = { WOLF = 3, PIG = 4, STIK = 5, STRW = 6, A = 8, K = 8, Q = 9, J = 9 }
local WILD_REELS  = { [2] = true, [3] = true, [4] = true }
local BRICK_REELS = { [1] = true, [3] = true, [5] = true }
local BRICK_CHANCE = 0.215       -- chance each brick reel shows one brick
local BRICK_COLOR_WEIGHTS = { R = 1, B = 1, Y = 1 }

-- pig popping
local RANDOM_POP_BASE = 0.15      -- chance an un-full pig pops anyway...
local RANDOM_POP_PER_LEVEL = 0.15 -- ...plus this per brick already in it

-- bonus board
local MAX_SPINS = 3
local START_COINS = 3             -- coins already on grid 1 when it opens
local COIN_CHANCE = 0.049          -- per empty open tile, per spin
local UNLOCK_AT = { [2] = 5, [3] = 15, [4] = 23 } -- total coins needed
local RED_TILES = 4               -- red x2 tiles picked each spin
local SUPER_CHANCE = 0.40         -- (yellow) chance a new coin is SUPER
local COLLECT_CHANCE = 0.05       -- (blue) chance a new coin is a COLLECTOR

-- coin values: m = multiple of TOTAL bet
local COIN_TABLE = {
  { m = 0.5,  w = 30 },
  { m = 1,    w = 30 },
  { m = 2,    w = 18 },
  { m = 3,    w = 10 },
  { m = 5,    w = 6 },
  { m = 8,    w = 3 },
  { m = 10,   w = 2.5,  tag = "MINI" },
  { m = 25,   w = 0.6,  tag = "MINOR" },
  { m = 100,  w = 0.08, tag = "MAJOR" },
  { m = 1000, w = 0.03, tag = "GRAND", tripleOnly = true }, -- progressive later
}

local DENOMS = { 0.01, 0.05, 0.10, 0.25, 1.00, 5.00 }
local BET_CREDITS = { 50, 100, 150, 250, 500 }
local START_CREDITS = 1000
local BIG_WIN_X = 15 -- "BIG WIN" banner when a win is >= this x total bet
local TEASE_FRAMES = 36 -- how many extra frames reel 5 spins on a tease

-- ============================= SYMBOLS / ART =============================
-- Art is tiny pixel bitmaps, scaled to whatever the cell size is.
-- '.' = the cell's background color, other letters map through ART_PAL.
local ART_PAL = {
  k = c.black, w = c.white, p = c.pink, m = c.magenta, g = c.gray,
  l = c.lightGray, y = c.yellow, o = c.orange, n = c.brown, r = c.red,
  e = c.green, i = c.lime, b = c.blue, s = c.lightBlue, c = c.cyan, u = c.purple,
}

local ART = {
  PIG = {
    "m.......m",
    "mmpppppmm",
    "ppkpppkpp",
    "ppppppppp",
    "ppmmmmmpp",
    "ppmkmkmpp",
    ".ppmmmpp.",
    "..ppppp..",
  },
  WOLF = {
    "g.......g",
    "gg.....gg",
    "ggggggggg",
    "gyggggygg",
    "gggwwwggg",
    ".ggwkwgg.",
    "..gwwwg..",
    "...www...",
  },
  STRW = { -- straw house
    "....y....",
    "...yyy...",
    "..yyoyy..",
    ".yyyyyyy.",
    "yyyoyyyyy",
    ".ooooooo.",
    ".oonnnoo.",
    ".oonnnoo.",
  },
  STIK = { -- stick house
    "....n....",
    "...nnn...",
    "..nnnnn..",
    ".nnnnnnn.",
    "nnnnnnnnn",
    ".n.n.n.n.",
    ".nnnnnnn.",
    ".nnkkknn.",
  },
}

local SYM = {
  WOLF = { label = "WILD", fg = c.white, bg = c.purple, wild = true, art = "WOLF" },
  PIG  = { label = "PIG",  fg = c.black, bg = c.lightBlue, art = "PIG" },
  STIK = { label = "STIX", fg = c.white, bg = c.green,     art = "STIK" },
  STRW = { label = "HAY",  fg = c.black, bg = c.lightBlue, art = "STRW" },
  A    = { label = "A", fg = c.black, bg = c.cyan },
  K    = { label = "K", fg = c.white, bg = c.magenta },
  Q    = { label = "Q", fg = c.black, bg = c.lime },
  J    = { label = "J", fg = c.black, bg = c.lightGray },
  BRK_R = { brick = true, color = "R" },
  BRK_B = { brick = true, color = "B" },
  BRK_Y = { brick = true, color = "Y" },
}
for k, p in pairs(PAYS) do SYM[k].pay = p end

local COLOR_ORDER = { "R", "B", "Y" }
local COLOR_INFO = {
  R = { name = "RED",    col = c.red,    mortar = c.lightGray, text = c.red },
  B = { name = "BLUE",   col = c.blue,   mortar = c.lightGray, text = c.lightBlue },
  Y = { name = "YELLOW", col = c.yellow, mortar = c.brown,     text = c.yellow },
}
local BRICK_KEY = { R = "BRK_R", B = "BRK_B", Y = "BRK_Y" }

-- 10 fixed paylines (row per reel, 1 = top)
local LINES = {
  {2,2,2,2,2}, {1,1,1,1,1}, {3,3,3,3,3}, {1,2,3,2,1}, {3,2,1,2,3},
  {1,1,2,3,3}, {3,3,2,1,1}, {2,1,1,1,2}, {2,3,3,3,2}, {2,1,2,3,2},
}

-- ============================= PURE GAME LOGIC =============================
-- No drawing in this section -- the simulator loads just this part.

local function money(v) return string.format("%.2f", v) end

local function weightedPick(list, weightOf)
  local total = 0
  for _, e in ipairs(list) do total = total + weightOf(e) end
  local roll = math.random() * total
  for _, e in ipairs(list) do
    roll = roll - weightOf(e)
    if roll <= 0 then return e end
  end
  return list[#list]
end

local STRIPS = {}
for r = 1, REELS do
  local strip = {}
  for key, n in pairs(BASE_WEIGHTS) do
    if key ~= "WOLF" or WILD_REELS[r] then
      for _ = 1, n do strip[#strip + 1] = key end
    end
  end
  table.sort(strip) -- deterministic order (pairs() order isn't)
  STRIPS[r] = strip
end

local function pickBrickColor()
  return weightedPick(COLOR_ORDER, function(k) return BRICK_COLOR_WEIGHTS[k] end)
end

local function genBaseGrid()
  local g = {}
  for r = 1, REELS do
    g[r] = {}
    local strip = STRIPS[r]
    for row = 1, ROWS do g[r][row] = strip[math.random(#strip)] end
    if BRICK_REELS[r] and math.random() < BRICK_CHANCE then
      g[r][math.random(ROWS)] = BRICK_KEY[pickBrickColor()]
    end
  end
  return g
end

local function evaluateLines(grid, lineBet)
  local total, hits, wins = 0, {}, {}
  for li, pat in ipairs(LINES) do
    local first = grid[1][pat[1]]
    local sym = SYM[first]
    if sym.pay then
      local n = 1
      for r = 2, REELS do
        local k = grid[r][pat[r]]
        if k == first or SYM[k].wild then n = n + 1 else break end
      end
      local p = sym.pay[n]
      if p then
        local amt = p * PAY_SCALE * lineBet
        total = total + amt
        wins[#wins + 1] = { line = li, count = n, amount = amt, sym = first }
        for r = 1, n do
          hits[r] = hits[r] or {}
          hits[r][pat[r]] = true
        end
      end
    end
  end
  return total, hits, wins
end

-- bricks in reels [r1..r2] -> list of {r, row, color}
local function findBricks(grid, r1, r2)
  local out = {}
  for r = r1 or 1, r2 or REELS do
    for row = 1, ROWS do
      local s = SYM[grid[r][row]]
      if s.brick then out[#out + 1] = { r = r, row = row, color = s.color } end
    end
  end
  return out
end

-- decides which pigs pop; resets popped meters; returns powers set
local function popPigs(meters)
  local powers, any = {}, false
  for _, k in ipairs(COLOR_ORDER) do
    local lvl = meters[k]
    if lvl >= 3 or math.random() < RANDOM_POP_BASE + RANDOM_POP_PER_LEVEL * lvl then
      powers[k] = true
      any = true
    end
  end
  if not any then
    local k = weightedPick(COLOR_ORDER, function(key) return meters[key] + 1 end)
    powers[k] = true
  end
  for k in pairs(powers) do meters[k] = 0 end
  return powers
end

local function comboName(powers)
  if powers.R and powers.B and powers.Y then return "TRIPLE RUSH" end
  local parts = {}
  for _, k in ipairs(COLOR_ORDER) do
    if powers[k] then parts[#parts + 1] = COLOR_INFO[k].name end
  end
  return table.concat(parts, " + ") .. " RUSH"
end

local function comboId(powers)
  local s = ""
  for _, k in ipairs(COLOR_ORDER) do if powers[k] then s = s .. k end end
  return s
end

-- ---- bonus board ----
local NGRID, GCOLS, GROWS = 4, 4, 3

local function cellKey(g, col, row) return g * 100 + col * 10 + row end

local function newBonusState(powers, totalBet)
  local st = {
    powers = powers, bet = totalBet, spins = MAX_SPINS,
    cells = {}, unlocked = { true, false, false, false },
    count = 0, red = {},
    triple = (powers.R and powers.B and powers.Y) and true or false,
  }
  for g = 1, NGRID do
    st.cells[g] = {}
    for col = 1, GCOLS do st.cells[g][col] = {} end
  end
  return st
end

local function emptyCells(st)
  local out = {}
  for g = 1, NGRID do
    if st.unlocked[g] then
      for col = 1, GCOLS do
        for row = 1, GROWS do
          if not st.cells[g][col][row] then out[#out + 1] = { g = g, col = col, row = row } end
        end
      end
    end
  end
  return out
end

local function rollCoin(st, allowSpecial)
  local e = weightedPick(COIN_TABLE, function(x)
    if x.tripleOnly and not st.triple then return 0 end
    return x.w
  end)
  local coin = { value = e.m * st.bet, tag = e.tag, kind = "coin" }
  if allowSpecial then
    if st.powers.B and math.random() < COLLECT_CHANCE then
      coin.kind = "collect"
    elseif st.powers.Y and math.random() < SUPER_CHANCE then
      coin.kind = "super"
    end
  end
  return coin
end

local function placeCoin(st, g, col, row, coin)
  if st.red[cellKey(g, col, row)] then
    coin.value = coin.value * 2
    coin.doubled = true
  end
  st.cells[g][col][row] = coin
  st.count = st.count + 1
end

local function checkUnlocks(st, events)
  for g = 2, NGRID do
    if not st.unlocked[g] and st.unlocked[g - 1] and st.count >= UNLOCK_AT[g] then
      st.unlocked[g] = true
      events[#events + 1] = { type = "unlock", g = g }
    end
  end
end

local function seedBonus(st)
  local events = {}
  local spots = emptyCells(st)
  for _ = 1, math.min(START_COINS, #spots) do
    local i = math.random(#spots)
    local s = table.remove(spots, i)
    placeCoin(st, s.g, s.col, s.row, rollCoin(st, false))
    events[#events + 1] = { type = "land", g = s.g, col = s.col, row = s.row }
  end
  checkUnlocks(st, events)
  return events
end

-- call before each spin: uses a spin and (red) picks the x2 tiles
local function prepareSpin(st)
  st.spins = st.spins - 1
  st.red = {}
  local picked = {}
  if st.powers.R then
    local spots = emptyCells(st)
    for _ = 1, math.min(RED_TILES, #spots) do
      local s = table.remove(spots, math.random(#spots))
      st.red[cellKey(s.g, s.col, s.row)] = true
      picked[#picked + 1] = s
    end
  end
  return picked
end

-- resolves one spin; returns an event list for the screen to animate
local function resolveSpin(st)
  local events, newCoins = {}, {}
  for _, s in ipairs(emptyCells(st)) do
    if math.random() < COIN_CHANCE then
      local coin = rollCoin(st, true)
      placeCoin(st, s.g, s.col, s.row, coin)
      newCoins[#newCoins + 1] = { g = s.g, col = s.col, row = s.row, coin = coin }
      events[#events + 1] = { type = "land", g = s.g, col = s.col, row = s.row }
    end
  end
  -- YELLOW: super coins spread to one empty neighbor in the same grid
  local spawned = 0
  for _, nc in ipairs(newCoins) do
    if nc.coin.kind == "super" then
      local opts = {}
      for _, d in ipairs({ {1,0}, {-1,0}, {0,1}, {0,-1} }) do
        local cc, rr = nc.col + d[1], nc.row + d[2]
        if cc >= 1 and cc <= GCOLS and rr >= 1 and rr <= GROWS and not st.cells[nc.g][cc][rr] then
          opts[#opts + 1] = { cc, rr }
        end
      end
      if #opts > 0 then
        local o = opts[math.random(#opts)]
        placeCoin(st, nc.g, o[1], o[2], rollCoin(st, false))
        spawned = spawned + 1
        events[#events + 1] = { type = "spread", g = nc.g, fromCol = nc.col, fromRow = nc.row, col = o[1], row = o[2] }
      end
    end
  end
  -- BLUE: collectors add up everything else on the board
  for _, nc in ipairs(newCoins) do
    if nc.coin.kind == "collect" then
      local sum = 0
      for g = 1, NGRID do
        for col = 1, GCOLS do
          for row = 1, GROWS do
            local k = st.cells[g][col][row]
            if k and k ~= nc.coin then sum = sum + k.value end
          end
        end
      end
      nc.coin.value = nc.coin.value + sum
      events[#events + 1] = { type = "collect", g = nc.g, col = nc.col, row = nc.row, amount = sum }
    end
  end
  if #newCoins + spawned > 0 then
    st.spins = MAX_SPINS
    events[#events + 1] = { type = "reset" }
  end
  checkUnlocks(st, events)
  return events
end

local function bonusOver(st)
  return st.spins <= 0 or #emptyCells(st) == 0
end

local function bonusTotal(st)
  local t = 0
  for g = 1, NGRID do
    for col = 1, GCOLS do
      for row = 1, GROWS do
        local k = st.cells[g][col][row]
        if k then t = t + k.value end
      end
    end
  end
  return t
end

-- simulator hook: `HUFF_SIM = true; local api = dofile("huff_puff.lua")`
if HUFF_SIM then
  return {
    genBaseGrid = genBaseGrid, evaluateLines = evaluateLines, findBricks = findBricks,
    popPigs = popPigs, comboId = comboId, newBonusState = newBonusState,
    seedBonus = seedBonus, prepareSpin = prepareSpin, resolveSpin = resolveSpin,
    bonusOver = bonusOver, bonusTotal = bonusTotal,
    setPayScale = function(v) PAY_SCALE = v end,
    setCoinChance = function(v) COIN_CHANCE = v end,
    setBrickChance = function(v) BRICK_CHANCE = v end,
  }
end

-- ============================= DRAWING HELPERS =============================
local HEX = {}
for i = 0, 15 do HEX[2 ^ i] = string.format("%x", i) end
local function hx(col) return HEX[col] or "f" end

local FONT = {
  H = {"10001","10001","10001","11111","10001","10001","10001"},
  U = {"10001","10001","10001","10001","10001","10001","01110"},
  F = {"11111","10000","10000","11110","10000","10000","10000"},
  N = {"10001","11001","10101","10101","10011","10001","10001"},
  P = {"11110","10001","10001","11110","10000","10000","10000"},
  ["'"] = {"00100","00100","01000","00000","00000","00000","00000"},
  [" "] = {"00000","00000","00000","00000","00000","00000","00000"},
}

local function compactMoney(v, maxW)
  local s = "$" .. money(v)
  if #s <= maxW then return s end
  s = "$" .. string.format("%.0f", v)
  if #s <= maxW then return s end
  if v >= 1e6 then s = string.format("$%.1fM", v / 1e6) else s = string.format("$%.1fK", v / 1e3) end
  if #s <= maxW then return s end
  return s:sub(2, maxW + 1)
end

-- ============================= MACHINE FACTORY =============================
local function newMachine(mon, speaker, stationId)
  mon.setTextScale(0.5)
  local w, h = mon.getSize()
  local monName = peripheral.getName(mon)

  -- ---- sound ----
  local volume = 1.0
  local function sfx(name, vol, pitch)
    if speaker and volume > 0 then pcall(speaker.playSound, name, math.min(3, (vol or 1) * volume), pitch or 1) end
  end
  local function note(inst, vol, pitch)
    if speaker and volume > 0 then pcall(speaker.playNote, inst, math.min(3, (vol or 1) * volume), pitch or 12) end
  end

  -- ---- primitive drawing ----
  local function fillRect(x, y, wd, ht, col)
    if wd <= 0 or ht <= 0 then return end
    local s, b = string.rep(" ", wd), string.rep(hx(col), wd)
    for yy = 0, ht - 1 do
      mon.setCursorPos(x, y + yy)
      mon.blit(s, b, b)
    end
  end

  local function text(x, y, str, fg, bg)
    if y < 1 or y > h then return end
    if x < 1 then str = str:sub(2 - x); x = 1 end
    if x + #str - 1 > w then str = str:sub(1, w - x + 1) end
    if #str == 0 then return end
    mon.setCursorPos(x, y)
    mon.setTextColor(fg or c.white)
    mon.setBackgroundColor(bg or c.black)
    mon.write(str)
  end

  local function centerIn(x, y, wd, str, fg, bg)
    if #str > wd then str = str:sub(1, wd) end
    text(x + math.floor((wd - #str) / 2), y, str, fg, bg)
  end

  -- brick pattern: 5-wide bricks, 1-char mortar, rows offset every other course
  local function drawBricks(x, y, wd, ht, brickCol, mortarCol, xOff)
    if wd <= 0 or ht <= 0 then return end
    local s = string.rep(" ", wd)
    local bh, mh = hx(brickCol), hx(mortarCol)
    local mortarRow = string.rep(mh, wd)
    for yy = 0, ht - 1 do
      local row
      if yy % 2 == 1 then
        row = mortarRow
      else
        local off = (math.floor(yy / 2) % 2) * 3 + (xOff or 0)
        local t = {}
        for xx = 0, wd - 1 do t[xx + 1] = ((xx + off) % 6 == 5) and mh or bh end
        row = table.concat(t)
      end
      mon.setCursorPos(x, y + yy)
      mon.blit(s, row, row)
    end
  end

  local function drawBitmap(x, y, wd, ht, bmp, bgCol)
    if wd <= 0 or ht <= 0 then return end
    local srcH, srcW = #bmp, #bmp[1]
    local s = string.rep(" ", wd)
    local bgh = hx(bgCol)
    for py = 0, ht - 1 do
      local line = bmp[math.min(srcH, math.floor(py * srcH / ht) + 1)]
      local t = {}
      for px = 0, wd - 1 do
        local sx = math.min(srcW, math.floor(px * srcW / wd) + 1)
        local ch = line:sub(sx, sx)
        t[px + 1] = (ch == ".") and bgh or hx(ART_PAL[ch])
      end
      local row = table.concat(t)
      mon.setCursorPos(x, y + py)
      mon.blit(s, row, row)
    end
  end

  local function drawBigText(str, topY, col, bgCol)
    local cw = 6
    local totalW = #str * cw - 1
    if totalW > w - 2 then return false end
    local x0 = math.floor((w - totalW) / 2) + 1
    for i = 1, #str do
      local glyph = FONT[str:sub(i, i)] or FONT[" "]
      for gy = 1, 7 do
        local t = {}
        for gx = 1, 5 do t[gx] = glyph[gy]:sub(gx, gx) == "1" and hx(col) or hx(bgCol) end
        local row = table.concat(t)
        mon.setCursorPos(x0 + (i - 1) * cw, topY + gy - 1)
        mon.blit("     ", row, row)
      end
    end
    return true
  end

  -- ============================= BASE GAME LAYOUT =============================
  local hudY = h - 4       -- credits / bet line
  local msgY = h - 3       -- message line
  local btnY = h - 2       -- buttons (3 rows tall: h-2 .. h)
  local sidePanel = w >= 90
  local panelW = sidePanel and 22 or 0
  local topBand = sidePanel and 0 or 7
  local areaX0, areaY0 = 2, 3 + topBand
  local areaW = w - panelW - 3
  local areaH = (hudY - 2) - areaY0 + 1
  local cellW = math.max(4, math.min(22, math.floor(areaW / REELS)))
  local cellH = math.max(3, math.min(12, math.floor(areaH / ROWS)))
  local gridW, gridH = cellW * REELS, cellH * ROWS
  local gridX0 = areaX0 + math.floor((areaW - gridW) / 2) + 1
  local gridY0 = areaY0 + math.floor((areaH - gridH) / 2) + 1
  local FRAME_COL = c.orange

  local function cellPos(r, row)
    return gridX0 + (r - 1) * cellW, gridY0 + (row - 1) * cellH
  end

  local function drawSymbol(r, row, key, invert)
    local x, y = cellPos(r, row)
    local cw, ch = cellW - 1, cellH - 1
    local s = SYM[key]
    if invert then
      fillRect(x, y, cw, ch, c.white)
      centerIn(x, y + math.floor(ch / 2), cw, s.brick and "BRICK" or s.label, c.black, c.white)
      return
    end
    if s.brick then
      local info = COLOR_INFO[s.color]
      drawBricks(x, y, cw, ch, info.col, info.mortar, 0)
    elseif s.art then
      local artH = ch >= 6 and ch - 1 or ch
      drawBitmap(x, y, cw, artH, ART[s.art], s.bg)
      if artH < ch then
        fillRect(x, y + artH, cw, 1, s.bg)
        centerIn(x, y + artH, cw, s.label, s.fg, s.bg)
      end
    else
      fillRect(x, y, cw, ch, s.bg)
      centerIn(x, y + math.floor((ch - 1) / 2), cw, s.label, s.fg, s.bg)
    end
  end

  local function drawReelFrame(col)
    fillRect(gridX0 - 1, gridY0 - 1, gridW + 1, gridH + 1, col or FRAME_COL)
  end

  -- border around one reel (used for the tease flash)
  local function drawReelBorder(r, col)
    local x = gridX0 + (r - 1) * cellW - 1
    fillRect(x, gridY0 - 1, cellW + 1, 1, col)
    fillRect(x, gridY0 + gridH - 1, cellW + 1, 1, col)
    fillRect(x, gridY0 - 1, 1, gridH + 1, col)
    fillRect(x + cellW, gridY0 - 1, 1, gridH + 1, col)
  end

  -- ---- pig meters ----
  local meters = { R = 0, B = 0, Y = 0 }
  local blinkOn = false

  local function meterRect(i)
    if sidePanel then
      local px = w - panelW + 1
      local top, bottom = 3, hudY - 2
      local bh = math.floor((bottom - top + 1 - 2) / 3)
      return px, top + (i - 1) * (bh + 1), panelW - 1, bh
    else
      local bw = math.floor((w - 4) / 3)
      return 2 + (i - 1) * (bw + 1), 3, bw, topBand - 1
    end
  end

  -- state: nil = normal, "pop" = popping flash, "dim" = didn't pop
  local function drawMeter(i, state)
    local k = COLOR_ORDER[i]
    local info = COLOR_INFO[k]
    local x, y, bw, bh = meterRect(i)
    fillRect(x, y, bw, bh, c.black)
    if state == "pop" then
      fillRect(x, y, bw, bh, c.white)
      centerIn(x, y + math.floor(bh / 2), bw, "POP!", info.col, c.white)
      return
    end
    local brick = state == "dim" and c.gray or info.col
    local mortar = state == "dim" and c.black or info.mortar
    centerIn(x, y, bw, info.name .. " PIG", state == "dim" and c.gray or info.text, c.black)
    local houseH = math.max(1, bh - 2)
    drawBricks(x, y + 1, bw, houseH, brick, mortar, 0)
    -- pips
    local pipY = y + 1 + math.floor(houseH / 2)
    local pipStr = ""
    local px0 = x + math.floor((bw - 11) / 2)
    for p = 1, 3 do
      local filled = meters[k] >= p
      text(px0 + (p - 1) * 4, pipY, "   ", c.black, filled and c.white or c.black)
    end
    local status
    if state == "dim" then status = "no pop"
    elseif meters[k] >= 3 then status = blinkOn and "READY!" or ""
    else status = meters[k] .. "/3" end
    fillRect(x, y + bh - 1, bw, 1, c.black)
    centerIn(x, y + bh - 1, bw, status, meters[k] >= 3 and c.lime or c.lightGray, c.black)
  end

  local function drawMeters()
    for i = 1, 3 do drawMeter(i) end
  end

  -- ---- money / buttons / HUD ----
  local credits = START_CREDITS
  local denomIdx, betIdx = 3, 2
  local function totalBet() return DENOMS[denomIdx] * BET_CREDITS[betIdx] end

  local buttons = {}
  local message, messageCol = "TOUCH SPIN TO PLAY", c.lightGray

  local function drawHud()
    fillRect(1, hudY, w, 2, c.black)
    local vol = volume <= 0 and "MUTE" or string.format("%.1f", volume)
    text(2, hudY, "CREDITS $" .. money(credits) .. "   DENOM $" .. money(DENOMS[denomIdx])
      .. " x " .. BET_CREDITS[betIdx] .. " = BET $" .. money(totalBet()) .. "   VOL " .. vol, c.white, c.black)
    if message then text(2, msgY, message, messageCol or c.yellow, c.black) end
  end

  local function setMessage(msg, col)
    message, messageCol = msg, col
    drawHud()
  end

  local function drawButtons()
    buttons = {}
    fillRect(1, btnY, w, 3, c.black)
    local specs = { "DENOM", "-BET", "+BET", "VOL-", "VOL+" }
    local shorts = { DENOM = "$", ["-BET"] = "-B", ["+BET"] = "+B", ["VOL-"] = "V-", ["VOL+"] = "V+" }
    local x, pad = 2, 4
    if w < 66 then pad = 2 end
    if w < 50 then specs = { "$", "-B", "+B", "V-", "V+" } end
    for _, label in ipairs(specs) do
      local bw = #label + pad
      if x + bw - 1 > w - 12 then break end
      fillRect(x, btnY, bw, 3, c.lightBlue)
      centerIn(x, btnY + 1, bw, label, c.black, c.lightBlue)
      local action = label
      for long, short in pairs(shorts) do if short == label then action = long end end
      buttons[#buttons + 1] = { label = action, x1 = x, x2 = x + bw - 1, y1 = btnY, y2 = btnY + 2 }
      x = x + bw + 1
    end
    local sw = w < 50 and 7 or 11
    local sx = w - sw
    fillRect(sx, btnY, sw, 3, c.lime)
    centerIn(sx, btnY + 1, sw, "SPIN!", c.black, c.lime)
    buttons[#buttons + 1] = { label = "SPIN!", x1 = sx, x2 = sx + sw - 1, y1 = btnY, y2 = btnY + 2 }
  end

  local currentGrid = genBaseGrid()

  local function drawBackground()
    drawBricks(1, 1, w, h, c.gray, c.black, 0)
    fillRect(1, 1, w, 1, c.black)
    centerIn(1, 1, w, "~ H U F F   N '   P U F F ~", c.orange, c.black)
  end

  local function drawGrid(grid, highlights)
    for r = 1, REELS do
      for row = 1, ROWS do
        drawSymbol(r, row, grid[r][row], highlights and highlights[r] and highlights[r][row])
      end
    end
  end

  local function drawFrame()
    drawBackground()
    drawReelFrame()
    drawGrid(currentGrid)
    drawMeters()
    drawHud()
    drawButtons()
  end

  local function banner(str, col, hold, sub)
    local bh = 7
    local by = math.floor((h - bh) / 2)
    for i = 1, 3 do
      drawBricks(1, by, w, bh, col, c.black, i)
      fillRect(3, by + 2, w - 4, 3, c.black)
      centerIn(3, by + 3, w - 4, str, i % 2 == 1 and c.white or col, c.black)
      if sub then centerIn(3, by + 4, w - 4, sub, c.lightGray, c.black) end
      sleep(0.2)
    end
    sleep(hold or 1)
  end

  local function showStartScreen()
    drawBricks(1, 1, w, h, c.red, c.lightGray, 0)
    local topY = math.floor(h / 2) - 5
    fillRect(1, topY - 1, w, 10, c.black)
    if not drawBigText("HUFF N' PUFF", topY, c.yellow, c.black) then
      centerIn(1, topY + 3, w, "HUFF N' PUFF", c.yellow, c.black)
    end
    centerIn(1, topY + 8, w, "station " .. stationId .. "  -  3 bricks = BONUS", c.lightGray, c.black)
    for _, p in ipairs({ 6, 10, 13, 18 }) do note("bell", 1.5, p); sleep(0.15) end
    sleep(1.2)
  end

  -- ============================= SPIN ANIMATION =============================
  local function randomVisual(r)
    if BRICK_REELS[r] and math.random() < 0.12 then
      return BRICK_KEY[COLOR_ORDER[math.random(3)]]
    end
    local strip = STRIPS[r]
    return strip[math.random(#strip)]
  end

  local function animateSpin(grid)
    local FRAME = 0.07
    local stopAt, stopped = {}, {}
    for r = 1, REELS do stopAt[r] = 8 + (r - 1) * 4 end
    local frame, teasing = 0, false
    while true do
      frame = frame + 1
      local allDone = true
      for r = 1, REELS do
        if not stopped[r] then
          if frame >= stopAt[r] then
            stopped[r] = true
            for row = 1, ROWS do drawSymbol(r, row, grid[r][row]) end
            note("hat", 0.7, 12)
            for row = 1, ROWS do
              if SYM[grid[r][row]].brick then
                sfx("block.stone.place", 1, 1)
                note("chime", 1.2, 18)
              end
            end
            -- TEASE: 2 bricks already showing and only the last reel left
            if r == REELS - 1 and BRICK_REELS[REELS] and #findBricks(grid, 1, REELS - 1) >= 2 then
              teasing = true
              stopAt[REELS] = frame + TEASE_FRAMES
              setMessage("2 BRICKS...!", c.yellow)
            end
            if r == REELS and teasing then
              drawReelFrame()
              drawGrid(grid)
            end
          else
            allDone = false
            for row = 1, ROWS do drawSymbol(r, row, randomVisual(r)) end
          end
        end
      end
      if teasing and not stopped[REELS] then
        local t = frame % 4
        drawReelBorder(REELS, (t < 2) and c.yellow or c.red)
        if t == 0 then note("basedrum", 2, 4) end         -- heartbeat
        if t == 2 then note("basedrum", 1.3, 6) end
        local left = stopAt[REELS] - frame
        note("pling", 0.8, math.min(24, math.floor((TEASE_FRAMES - left) * 24 / TEASE_FRAMES)))
      end
      if allDone then break end
      sleep(teasing and FRAME * 1.2 or FRAME)
    end
  end

  local function flashWin(grid, hits)
    for i = 1, 3 do
      drawGrid(grid, hits)
      note("bell", 1, 12 + i * 3)
      sleep(0.18)
      drawGrid(grid)
      sleep(0.14)
    end
    drawGrid(grid, hits)
  end

  -- ============================= BONUS SCREEN =============================
  local bTop, bBottom, bGap = 4, h - 2, 2
  local bcw = math.max(4, math.floor((w - 2 - bGap) / 8))
  local bch = math.max(3, math.floor((bBottom - bTop + 1 - bGap) / 6))
  local bTotalW, bTotalH = bcw * 8 + bGap, bch * 6 + bGap
  local bx0 = math.floor((w - bTotalW) / 2) + 1
  local by0 = bTop + math.floor(((bBottom - bTop + 1) - bTotalH) / 2) + 1

  local function gridOrigin(g)
    local gx, gy = (g - 1) % 2, math.floor((g - 1) / 2)
    return bx0 + gx * (bcw * 4 + bGap), by0 + gy * (bch * 3 + bGap)
  end
  local function bCell(g, col, row)
    local ox, oy = gridOrigin(g)
    return ox + (col - 1) * bcw, oy + (row - 1) * bch, bcw - 1, bch - 1
  end

  local function drawCoin(x, y, cw, ch, coin)
    local bg, fg, name = c.yellow, c.black, nil
    if coin.kind == "collect" then bg, fg, name = c.blue, c.white, "COLLECT"
    elseif coin.kind == "super" then bg, fg, name = c.yellow, c.black, "SUPER" end
    fillRect(x, y, cw, ch, bg)
    if coin.kind == "super" and ch >= 3 then
      fillRect(x, y, cw, 1, c.orange)
      fillRect(x, y + ch - 1, cw, 1, c.orange)
    end
    local lines = {}
    if coin.tag then lines[#lines + 1] = { coin.tag, coin.tag == "GRAND" and c.red or c.purple } end
    if name and #lines < ch - 1 then lines[#lines + 1] = { name, fg } end
    lines[#lines + 1] = { compactMoney(coin.value, cw), fg }
    if coin.doubled then lines[#lines + 1] = { "x2", c.red } end
    while #lines > ch do table.remove(lines, 1) end
    local y0 = y + math.floor((ch - #lines) / 2)
    for i, ln in ipairs(lines) do
      local lineBg = bg
      if coin.kind == "super" and ch >= 3 and (y0 + i - 1 == y or y0 + i - 1 == y + ch - 1) then lineBg = c.orange end
      centerIn(x, y0 + i - 1, cw, ln[1], ln[2], lineBg)
    end
  end

  local function drawBonusCell(st, g, col, row, flashCol)
    local x, y, cw, ch = bCell(g, col, row)
    if flashCol then fillRect(x, y, cw, ch, flashCol); return end
    local coin = st.cells[g][col][row]
    if coin then
      drawCoin(x, y, cw, ch, coin)
    elseif st.red[cellKey(g, col, row)] then
      fillRect(x, y, cw, ch, c.red)
      centerIn(x, y + math.floor((ch - 1) / 2), cw, "x2", c.white, c.red)
    else
      fillRect(x, y, cw, ch, c.black)
    end
  end

  local function drawBonusGrid(st, g)
    local ox, oy = gridOrigin(g)
    local gw, gh = bcw * 4, bch * 3
    if not st.unlocked[g] then
      fillRect(ox - 1, oy - 1, gw + 1, gh + 1, c.brown)
      drawBricks(ox, oy, gw - 1, gh - 1, c.lightGray, c.gray, 0)
      local midY = oy + math.floor(gh / 2) - 1
      fillRect(ox + 2, midY, gw - 4, 3, c.black)
      centerIn(ox + 2, midY, gw - 4, "LOCKED", c.lightGray, c.black)
      centerIn(ox + 2, midY + 1, gw - 4, "OPENS AT " .. UNLOCK_AT[g] .. " COINS", c.yellow, c.black)
      return
    end
    fillRect(ox - 1, oy - 1, gw + 1, gh + 1, c.brown)
    for col = 1, GCOLS do
      for row = 1, GROWS do drawBonusCell(st, g, col, row) end
    end
  end

  local function nextUnlock(st)
    for g = 2, NGRID do if not st.unlocked[g] then return UNLOCK_AT[g] end end
    return nil
  end

  local function drawBonusStatus(st)
    fillRect(1, 1, w, 3, c.black)
    centerIn(1, 1, w, "HUFF N' PUFF BONUS  -  " .. comboName(st.powers), c.orange, c.black)
    -- row 2: spins + coins + win
    local x = 2
    text(x, 2, "SPINS ", c.white, c.black)
    x = x + 6
    for i = 1, MAX_SPINS do
      text(x, 2, "  ", c.black, i <= st.spins and c.lime or c.gray)
      x = x + 3
    end
    local nu = nextUnlock(st)
    local info = "  COINS " .. st.count .. (nu and ("  NEXT GRID AT " .. nu) or "  ALL GRIDS OPEN")
      .. "  WIN $" .. money(bonusTotal(st))
    text(x, 2, info, c.white, c.black)
    -- row 3: active power-up legend
    x = 2
    local legend = { R = " RED: x2 TILES ", Y = " YELLOW: SUPER COINS ", B = " BLUE: COLLECTORS " }
    for _, k in ipairs(COLOR_ORDER) do
      if st.powers[k] then
        local info2 = COLOR_INFO[k]
        text(x, 3, legend[k], k == "Y" and c.black or c.white, info2.col)
        x = x + #legend[k] + 1
      end
    end
    if st.triple then text(x, 3, " GRAND IN PLAY! ", c.white, c.purple) end
  end

  local function drawBonusScreen(st)
    drawBricks(1, 1, w, h, c.gray, c.black, 0)
    for g = 1, NGRID do drawBonusGrid(st, g) end
    drawBonusStatus(st)
    fillRect(1, h, w, 1, c.black)
  end

  local function bonusMsg(str, col)
    fillRect(1, h, w, 1, c.black)
    centerIn(1, h, w, str, col or c.yellow, c.black)
  end

  local function shimmer(st)
    local empties = emptyCells(st)
    for f = 1, 7 do
      local lit = {}
      for _ = 1, math.min(#empties, 4) do
        local s = empties[math.random(#empties)]
        lit[#lit + 1] = s
        drawBonusCell(st, s.g, s.col, s.row, c.gray)
      end
      note("hat", 0.5, 8 + f)
      sleep(0.09)
      for _, s in ipairs(lit) do drawBonusCell(st, s.g, s.col, s.row) end
    end
  end

  local function playEvents(st, events)
    for _, ev in ipairs(events) do
      if ev.type == "land" then
        drawBonusCell(st, ev.g, ev.col, ev.row, c.white)
        sfx("entity.experience_orb.pickup", 1, 0.8 + math.random() * 0.6)
        sleep(0.1)
        drawBonusCell(st, ev.g, ev.col, ev.row)
        local coin = st.cells[ev.g][ev.col][ev.row]
        if coin.doubled then note("bell", 1.5, 20) end
        if coin.tag then sfx("entity.player.levelup", 1, 1.2) end
        drawBonusStatus(st)
        sleep(0.25)
      elseif ev.type == "spread" then
        for i = 1, 2 do
          drawBonusCell(st, ev.g, ev.fromCol, ev.fromRow, c.orange)
          drawBonusCell(st, ev.g, ev.col, ev.row, c.yellow)
          sleep(0.1)
          drawBonusCell(st, ev.g, ev.fromCol, ev.fromRow)
          drawBonusCell(st, ev.g, ev.col, ev.row, c.black)
          sleep(0.08)
        end
        drawBonusCell(st, ev.g, ev.col, ev.row)
        sfx("block.amethyst_block.chime", 2, 1.2)
        bonusMsg("SUPER COIN SPREADS!", c.yellow)
        drawBonusStatus(st)
        sleep(0.3)
      elseif ev.type == "collect" then
        bonusMsg("COLLECTOR GRABS $" .. money(ev.amount) .. "!", c.lightBlue)
        -- flash every other coin blue, then the collector
        for i = 1, 2 do
          for g = 1, NGRID do
            for col = 1, GCOLS do
              for row = 1, GROWS do
                local k = st.cells[g][col][row]
                if k and not (g == ev.g and col == ev.col and row == ev.row) then
                  drawBonusCell(st, g, col, row, i == 1 and c.lightBlue or nil)
                end
              end
            end
          end
          note("pling", 1.5, 10 + i * 6)
          sleep(0.2)
        end
        drawBonusCell(st, ev.g, ev.col, ev.row, c.white)
        sfx("entity.player.levelup", 1, 1)
        sleep(0.15)
        drawBonusCell(st, ev.g, ev.col, ev.row)
        drawBonusStatus(st)
        sleep(0.4)
      elseif ev.type == "unlock" then
        sfx("block.chest.open", 1.5, 1)
        for i = 1, 3 do
          local ox, oy = gridOrigin(ev.g)
          fillRect(ox - 1, oy - 1, bcw * 4 + 1, bch * 3 + 1, i % 2 == 1 and c.yellow or c.orange)
          note("bell", 2, 12 + i * 4)
          sleep(0.15)
        end
        drawBonusGrid(st, ev.g)
        bonusMsg("GRID " .. ev.g .. " UNLOCKED!", c.lime)
        drawBonusStatus(st)
        sleep(0.6)
      elseif ev.type == "reset" then
        drawBonusStatus(st)
        note("pling", 1, 18)
      end
    end
  end

  local function runBonus(bricks)
    -- the wolf blows, the pigs pop
    sfx("entity.wolf.howl", 2, 1)
    banner("THE WOLF HUFFS AND PUFFS...", c.orange, 1.2)
    drawFrame()
    -- each triggering brick drops into its own color's pig
    for _, b in ipairs(bricks) do
      meters[b.color] = math.min(3, meters[b.color] + 1)
      drawMeters()
      sfx("block.stone.place", 1.5, 1.2)
      note("chime", 1.5, 12 + meters[b.color] * 4)
      sleep(0.4)
    end
    sleep(0.4)
    local before = { R = meters.R, B = meters.B, Y = meters.Y }
    local powers = popPigs(meters)
    for i, k in ipairs(COLOR_ORDER) do
      if powers[k] then
        for f = 1, 3 do
          meters[k] = before[k]
          drawMeter(i, "pop")
          sfx("entity.firework_rocket.blast", 1.5, 0.8 + f * 0.2)
          sleep(0.15)
          drawMeter(i)
          sleep(0.1)
        end
        drawMeter(i, "pop")
        sleep(0.35)
      end
    end
    meters.R, meters.B, meters.Y = before.R, before.B, before.Y
    for i, k in ipairs(COLOR_ORDER) do if not powers[k] then drawMeter(i, "dim") end end
    for k in pairs(powers) do meters[k] = 0 end
    sleep(0.8)
    local bannerCol = c.purple
    for _, k in ipairs(COLOR_ORDER) do if powers[k] and not (powers.R and powers.B and powers.Y) then bannerCol = COLOR_INFO[k].col; break end end
    banner(comboName(powers) .. "!", bannerCol, 1.2,
      "collect gold coins - every coin resets your spins to " .. MAX_SPINS)

    local st = newBonusState(powers, totalBet())
    drawBonusScreen(st)
    bonusMsg("THE PIGS DROP " .. START_COINS .. " COINS!", c.yellow)
    sleep(0.6)
    playEvents(st, seedBonus(st))
    sleep(0.6)

    while not bonusOver(st) do
      local red = prepareSpin(st)
      drawBonusStatus(st)
      bonusMsg("SPINNING...", c.lightGray)
      for _, s in ipairs(red) do drawBonusCell(st, s.g, s.col, s.row) end
      if #red > 0 then note("bit", 1, 6) end
      shimmer(st)
      local events = resolveSpin(st)
      if #events == 0 then bonusMsg("no coins...", c.gray) end
      playEvents(st, events)
      -- clear leftover red tiles
      local oldRed = st.red
      st.red = {}
      for key in pairs(oldRed) do
        local g, col, row = math.floor(key / 100), math.floor(key / 10) % 10, key % 10
        drawBonusCell(st, g, col, row)
      end
      sleep(0.35)
    end

    -- tally
    local total = bonusTotal(st)
    bonusMsg("BONUS COMPLETE!", c.lime)
    for g = 1, NGRID do
      for col = 1, GCOLS do
        for row = 1, GROWS do
          if st.cells[g][col][row] then
            drawBonusCell(st, g, col, row, c.white)
            note("xylophone", 1, math.random(10, 22))
            sleep(0.04)
            drawBonusCell(st, g, col, row)
          end
        end
      end
    end
    credits = credits + total
    sfx("ui.toast.challenge_complete", 1, 1)
    banner("BONUS WIN $" .. money(total), c.yellow, 2.2, st.count .. " coins  -  " .. comboName(powers))
    return total
  end

  -- ============================= MAIN SPIN =============================
  local busy = false

  local function doSpin()
    if busy then return end
    local bet = totalBet()
    if credits < bet then
      setMessage("NOT ENOUGH CREDITS", c.red)
      return
    end
    busy = true
    credits = credits - bet
    message = nil
    drawHud()
    fillRect(1, msgY, w, 1, c.black)

    local grid = genBaseGrid()
    currentGrid = grid
    animateSpin(grid)

    -- the 3 bricks of a trigger feed their pigs (drawn during the bonus intro)
    local bricks = findBricks(grid)

    local win, hits = evaluateLines(grid, bet / #LINES)
    if win > 0 then
      credits = credits + win
      flashWin(grid, hits)
      if win >= bet * BIG_WIN_X then
        sfx("ui.toast.challenge_complete", 1, 1)
        banner("BIG WIN!  $" .. money(win), c.yellow, 1.5)
        drawFrame()
        drawGrid(grid, hits)
      end
      setMessage("YOU WIN $" .. money(win) .. "!", c.lime)
    else
      setMessage(#bricks == 2 and "SO CLOSE! 2 BRICKS" or "NO WIN - TRY AGAIN", c.red)
    end

    if #bricks >= 3 then
      sleep(0.8)
      local bonusWin = runBonus(bricks)
      drawFrame()
      setMessage("BONUS PAID $" .. money(bonusWin) .. "!", c.lime)
    end

    drawHud()
    busy = false
  end

  -- ============================= INPUT =============================
  local function handleButton(label)
    if label == "SPIN!" then doSpin(); return end
    if label == "DENOM" then denomIdx = denomIdx % #DENOMS + 1
    elseif label == "-BET" then betIdx = math.max(1, betIdx - 1)
    elseif label == "+BET" then betIdx = math.min(#BET_CREDITS, betIdx + 1)
    elseif label == "VOL-" then volume = math.max(0, volume - 0.5)
    elseif label == "VOL+" then volume = math.min(3, volume + 0.5); note("bell", 1, 12)
    end
    drawHud()
  end

  local lastTouch, lastTouchTime = nil, 0
  local function inputLoop()
    while true do
      local ev, side, x, y = os.pullEvent("monitor_touch")
      if side == monName and not busy then
        for _, b in ipairs(buttons) do
          if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
            local now = os.epoch("utc")
            if b.label ~= lastTouch or now - lastTouchTime > 250 then
              lastTouch, lastTouchTime = b.label, now
              handleButton(b.label)
            end
            break
          end
        end
      end
    end
  end

  local function animationLoop()
    while true do
      sleep(0.4)
      if not busy then
        blinkOn = not blinkOn
        for i, k in ipairs(COLOR_ORDER) do
          if meters[k] >= 3 then drawMeter(i) end
        end
      end
    end
  end

  local function run()
    showStartScreen()
    drawFrame()
    parallel.waitForAll(inputLoop, animationLoop)
  end

  return { run = run, monName = monName, stationId = stationId }
end

-- ============================= DISCOVER STATIONS =============================
local monitors = { peripheral.find("monitor") }
if #monitors == 0 then
  error("No monitors found! Attach at least one monitor (wall) to this computer.")
end
local speakers = { peripheral.find("speaker") }

local runFns = {}
for i, mon in ipairs(monitors) do
  local spk = #speakers > 0 and speakers[((i - 1) % #speakers) + 1] or nil
  local m = newMachine(mon, spk, i)
  runFns[i] = m.run
  print("  station " .. i .. " -> " .. m.monName)
end
print("Huff N' Puff: " .. #monitors .. " station(s), " .. #speakers .. " speaker(s). Running.")

parallel.waitForAll(table.unpack(runFns))
