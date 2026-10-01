--[[
  LUCKY SPIN - a CC:Tweaked wheel slot for the casino
  Same multi-station setup as Buffalo Bonus / Huff N' Puff: one Computer
  runs a fully independent game on EVERY monitor wall it can see.

  LAYOUT (made for a 6-wide x 3-tall Advanced Monitor wall)
   - The top quarter of the screen is a giant prize wheel. Only its
     bottom arc is on screen -- the rest hangs off the top edge -- with
     a pointer under it. Rim bulbs chase all the time.
   - Below it: 5 reels x 3 rows, 20 fixed paylines, and a jackpot panel.

  BASE GAME
   - WILD (star) lands on reels 2-4 and substitutes for everything that
     pays. WHEEL symbols land on reels 2, 3 and 4 only.
   - WHEEL on reels 2 AND 3 -> reel 4 keeps spinning with a heartbeat,
     rising notes and a flashing frame.
   - 3 WHEELS (reels 2-3-4) -> SPIN THE WHEEL. Touch the screen to spin
     (it auto-spins after 15 seconds).
   - RANDOM SPIN: any spin can also trigger the wheel on its own. The
     odds get better with the bet (RANDOM_WHEEL_ODDS).

  THE WHEEL (20 wedges)
   - CASH wedges pay a multiple of the total bet (shown in $ on the wheel).
   - FREE GAMES wedges start 7 / 10 / 15 free games.
   - SUPER WHEEL wedges swap in the red-and-gold SUPER WHEEL and you spin
     again: bigger cash plus MINI / MINOR / MAJOR / GRAND jackpots.

  FREE GAMES
   - Every win pays x2, reels carry extra WILDs, and each game has a
     chance to turn a whole reel (2, 3 or 4) WILD.
   - 3 WHEELS during free games spin the wheel again: cash is added to
     the free games total, FREE wedges add more games (cap 50).

  SETUP
   1. Build the monitor wall(s) out of Advanced Monitors (6x3 works best,
      but the layout scales to any size).
   2. Attach them + an optional Speaker to one COMMAND Computer (a normal
      Advanced Computer works too, but only for practice credits).
   3. Put casino_slot.lua, casino_bank.lua and casino_net.lua next to it
      (plus a wireless/ender modem so the main computer sees it).
   4. wget the raw URL of this file and run it.
   5. Enter the PIN on the computer, type 'calibrate', stand where a
      player stands at each station and tap its screen.

  REAL MONEY (casino_slot.lua): on a Command Computer every station plays
  for EconomyCraft money. Whoever stands closest to a station is the
  player; bets come out of their balance, wins (incl. bonus) go back in.
  Total bets are whole dollars ($1 - $1,000 with the denoms below).
--]]

local slot = require("casino_slot")
local c = colors
math.randomseed(os.epoch and os.epoch("utc") or os.time())
local atan2 = math.atan2 or math.atan
local TWO_PI = math.pi * 2

-- ============================= TUNING =============================
local REELS, ROWS = 5, 3

-- Line pays are multiples of the LINE bet (total bet / 20 lines).
local PAYS = {
  R7   = { [3] = 25, [4] = 100, [5] = 500 },
  B7   = { [3] = 15, [4] = 60,  [5] = 250 },
  BAR3 = { [3] = 10, [4] = 40,  [5] = 150 },
  BAR2 = { [3] = 8,  [4] = 25,  [5] = 100 },
  BAR1 = { [3] = 5,  [4] = 15,  [5] = 60  },
  BELL = { [3] = 4,  [4] = 12,  [5] = 40  },
  CHRY = { [3] = 3,  [4] = 10,  [5] = 30  },
}
local PAY_SCALE = 2.25 -- global multiplier on PAYS (sim-tuned)

-- symbol weights on the reel strips (WILD only appears on WILD_REELS)
local BASE_WEIGHTS = { WILD = 2, R7 = 3, B7 = 4, BAR3 = 5, BAR2 = 6, BAR1 = 7, BELL = 8, CHRY = 9 }
local FREE_WEIGHTS = { WILD = 5, R7 = 4, B7 = 5, BAR3 = 5, BAR2 = 6, BAR1 = 7, BELL = 7, CHRY = 8 }
local WILD_REELS  = { [2] = true, [3] = true, [4] = true }
local WHEEL_REELS = { [2] = true, [3] = true, [4] = true }
local WHEEL_CHANCE = 0.23        -- chance each wheel reel shows one WHEEL

-- RANDOM SPIN: any spin WITHOUT 3 wheels can still trigger the wheel.
local RANDOM_WHEEL_ODDS = { [50] = 1400, [100] = 1000, [150] = 800, [250] = 650, [500] = 500 }

-- free games
local FREE_MULT = 2              -- every free-game win is multiplied by this
local WILD_REEL_CHANCE = 0.18    -- per free game: one of reels 2-4 goes fully WILD
local MAX_FREE_GAMES = 50

-- The wheel. m = multiple of TOTAL bet, w = weight (chance to land).
-- Order = the order the wedges sit around the wheel.
local BASE_WHEEL = {
  { t = "cash",  m = 8,  w = 10,  col = c.red },
  { t = "cash",  m = 15, w = 6,   col = c.blue },
  { t = "free",  n = 7,  w = 7,   col = c.lime, fg = c.black },
  { t = "cash",  m = 6,  w = 10,  col = c.orange },
  { t = "cash",  m = 20, w = 4,   col = c.purple },
  { t = "cash",  m = 10, w = 9,   col = c.cyan, fg = c.black },
  { t = "super",         w = 3,   col = c.yellow, fg = c.red },
  { t = "cash",  m = 12, w = 8,   col = c.red },
  { t = "cash",  m = 5,  w = 11,  col = c.blue },
  { t = "free",  n = 10, w = 5,   col = c.lime, fg = c.black },
  { t = "cash",  m = 30, w = 3,   col = c.magenta },
  { t = "cash",  m = 8,  w = 10,  col = c.orange },
  { t = "cash",  m = 15, w = 5,   col = c.purple },
  { t = "cash",  m = 6,  w = 10,  col = c.cyan, fg = c.black },
  { t = "free",  n = 15, w = 2.5, col = c.lime, fg = c.black },
  { t = "cash",  m = 40, w = 2,   col = c.red },
  { t = "cash",  m = 10, w = 9,   col = c.blue },
  { t = "super",         w = 3,   col = c.yellow, fg = c.red },
  { t = "cash",  m = 15, w = 6,   col = c.orange },
  { t = "cash",  m = 75, w = 1,   col = c.magenta },
}

local JACKPOT_X = { MINI = 40, MINOR = 100, MAJOR = 400, GRAND = 2000 }
local JP_COL = { MINI = c.lightBlue, MINOR = c.lime, MAJOR = c.magenta, GRAND = c.yellow }
local JP_FG  = { MINI = c.black, MINOR = c.black, MAJOR = c.white, GRAND = c.red }

local SUPER_WHEEL = {
  { t = "cash", m = 20,  w = 14,   col = c.red },
  { t = "cash", tag = "MINI",  w = 6,    },
  { t = "cash", m = 30,  w = 10,   col = c.purple },
  { t = "cash", m = 75,  w = 3,    col = c.red },
  { t = "cash", tag = "MINOR", w = 2.5,  },
  { t = "cash", m = 25,  w = 12,   col = c.purple },
  { t = "cash", m = 50,  w = 5,    col = c.red },
  { t = "cash", tag = "GRAND", w = 0.15, },
  { t = "cash", m = 20,  w = 14,   col = c.purple },
  { t = "cash", tag = "MINI",  w = 6,    },
  { t = "cash", m = 35,  w = 9,    col = c.red },
  { t = "cash", tag = "MAJOR", w = 0.6,  },
  { t = "cash", m = 25,  w = 12,   col = c.purple },
  { t = "cash", m = 60,  w = 4,    col = c.red },
  { t = "cash", tag = "MINOR", w = 2.5,  },
  { t = "cash", m = 150, w = 1.5,  col = c.purple },
}
for _, wd in ipairs(SUPER_WHEEL) do
  if wd.tag then wd.m, wd.col, wd.fg = JACKPOT_X[wd.tag], JP_COL[wd.tag], JP_FG[wd.tag] end
end

local DENOMS = { 0.02, 0.10, 0.20, 1.00, 2.00 }   -- x BET_CREDITS = whole-dollar bets
local BET_CREDITS = { 50, 100, 150, 250, 500 }
local START_CREDITS = 1000 -- practice mode only
local BIG_WIN_X = 15    -- "BIG WIN" banner when a win is >= this x total bet
local TEASE_FRAMES = 36 -- extra frames reel 4 spins on a tease
local WHEEL_AUTO_SPIN = 15 -- seconds before the wheel spins by itself

-- ============================= SYMBOLS / ART =============================
local ART_PAL = {
  k = c.black, w = c.white, p = c.pink, m = c.magenta, g = c.gray,
  l = c.lightGray, y = c.yellow, o = c.orange, n = c.brown, r = c.red,
  e = c.green, i = c.lime, b = c.blue, s = c.lightBlue, c = c.cyan, u = c.purple,
}

-- 5 rows tall so they stay crisp on a 6x3 wall (they scale up on bigger ones)
local ART = {
  R7 = {
    "rrrrrrrrr",
    "......rr.",
    "....rrr..",
    "...rr....",
    "..rr.....",
  },
  B7 = {
    "bbbbbbbbb",
    "......bb.",
    "....bbb..",
    "...bb....",
    "..bb.....",
  },
  BAR3 = {
    "kkkkkkkkk",
    ".........",
    "kkkkkkkkk",
    ".........",
    "kkkkkkkkk",
  },
  BAR2 = {
    ".........",
    "kkkkkkkkk",
    ".........",
    "kkkkkkkkk",
    ".........",
  },
  BAR1 = {
    ".........",
    ".........",
    "kkkkkkkkk",
    ".........",
    ".........",
  },
  BELL = {
    "...yyy...",
    "..yyyyy..",
    "..yyyyy..",
    ".yyyyyyy.",
    "....n....",
  },
  CHRY = {
    ".....ee..",
    "....e.e..",
    "...e...e.",
    ".rr...rr.",
    ".rr...rr.",
  },
  WILD = {
    "....y....",
    "...yyy...",
    "yyyyyyyyy",
    "..yyyyy..",
    ".yy...yy.",
  },
  WHEEL = {
    "..rryuu..",
    ".rrryuuu.",
    "yyyywyyyy",
    ".eeeybbb.",
    "..eeybb..",
  },
}

local SYM = {
  WILD  = { label = "WILD",  fg = c.yellow, bg = c.purple, wild = true, art = "WILD" },
  WHEEL = { label = "BONUS", fg = c.yellow, bg = c.black, scatter = true, art = "WHEEL" },
  R7    = { label = "RED 7",  fg = c.red,   bg = c.white,     art = "R7" },
  B7    = { label = "BLUE 7", fg = c.blue,  bg = c.white,     art = "B7" },
  BAR3  = { label = "3BAR",   fg = c.black, bg = c.orange,    art = "BAR3" },
  BAR2  = { label = "2BAR",   fg = c.black, bg = c.yellow,    art = "BAR2" },
  BAR1  = { label = "BAR",    fg = c.black, bg = c.lightBlue, art = "BAR1" },
  BELL  = { label = "BELL",   fg = c.yellow, bg = c.blue,     art = "BELL" },
  CHRY  = { label = "CHERRY", fg = c.red,   bg = c.lightGray, art = "CHRY" },
}
for k, p in pairs(PAYS) do SYM[k].pay = p end

-- 20 fixed paylines (row per reel, 1 = top)
local LINES = {
  {2,2,2,2,2}, {1,1,1,1,1}, {3,3,3,3,3}, {1,2,3,2,1}, {3,2,1,2,3},
  {1,1,2,1,1}, {3,3,2,3,3}, {2,3,3,3,2}, {2,1,1,1,2}, {2,2,1,2,2},
  {2,2,3,2,2}, {1,2,2,2,1}, {3,2,2,2,3}, {1,2,1,2,1}, {3,2,3,2,3},
  {2,1,2,1,2}, {2,3,2,3,2}, {1,1,3,1,1}, {3,3,1,3,3}, {1,3,1,3,1},
}

-- ============================= PURE GAME LOGIC =============================
-- No drawing in this section -- the simulator loads just this part.

local function money(v) return string.format("%.2f", v) end

local function weightedPick(list, weightOf)
  local total = 0
  for _, e in ipairs(list) do total = total + weightOf(e) end
  local roll = math.random() * total
  for i, e in ipairs(list) do
    roll = roll - weightOf(e)
    if roll <= 0 then return e, i end
  end
  return list[#list], #list
end

local function buildStrips(weights)
  local out = {}
  for r = 1, REELS do
    local strip = {}
    for key, n in pairs(weights) do
      if key ~= "WILD" or WILD_REELS[r] then
        for _ = 1, n do strip[#strip + 1] = key end
      end
    end
    table.sort(strip) -- deterministic order (pairs() order isn't)
    out[r] = strip
  end
  return out
end
local STRIPS = buildStrips(BASE_WEIGHTS)
local FREE_STRIPS = buildStrips(FREE_WEIGHTS)

-- returns grid, wildReel (wildReel only in free games)
local function genGrid(free)
  local strips = free and FREE_STRIPS or STRIPS
  local g = {}
  for r = 1, REELS do
    g[r] = {}
    local strip = strips[r]
    for row = 1, ROWS do g[r][row] = strip[math.random(#strip)] end
    if WHEEL_REELS[r] and math.random() < WHEEL_CHANCE then
      g[r][math.random(ROWS)] = "WHEEL"
    end
  end
  local wildReel
  if free and math.random() < WILD_REEL_CHANCE then
    wildReel = math.random(2, 4)
    for row = 1, ROWS do
      if g[wildReel][row] ~= "WHEEL" then g[wildReel][row] = "WILD" end
    end
  end
  return g, wildReel
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

-- WHEEL symbols in reels [r1..r2] -> list of {r, row}
local function findWheels(grid, r1, r2)
  local out = {}
  for r = r1 or 1, r2 or REELS do
    for row = 1, ROWS do
      if grid[r][row] == "WHEEL" then out[#out + 1] = { r = r, row = row } end
    end
  end
  return out
end

local function randomWheelHit(betCredits)
  local odds = RANDOM_WHEEL_ODDS[betCredits]
  return odds ~= nil and math.random() < 1 / odds
end

local function wedgesFor(tier) return tier == "super" and SUPER_WHEEL or BASE_WHEEL end

-- returns the wedge table and its index on the wheel
local function pickWedge(tier)
  return weightedPick(wedgesFor(tier), function(e) return e.w end)
end

-- simulator hook: `LUCKY_SIM = true; local api = dofile("Lucky_Spin.lua")`
if LUCKY_SIM then
  return {
    genGrid = genGrid, evaluateLines = evaluateLines, findWheels = findWheels,
    randomWheelHit = randomWheelHit, pickWedge = pickWedge, LINES = LINES,
    BET_CREDITS = BET_CREDITS, FREE_MULT = FREE_MULT, MAX_FREE_GAMES = MAX_FREE_GAMES,
    BASE_WHEEL = BASE_WHEEL, SUPER_WHEEL = SUPER_WHEEL,
    setPayScale = function(v) PAY_SCALE = v end,
    setWheelChance = function(v) WHEEL_CHANCE = v end,
  }
end

-- ============================= DRAWING HELPERS =============================
local HEX = {}
for i = 0, 15 do HEX[2 ^ i] = string.format("%x", i) end
local function hx(col) return HEX[col] or "f" end

local FONT = {
  L = {"10000","10000","10000","10000","10000","10000","11111"},
  U = {"10001","10001","10001","10001","10001","10001","01110"},
  C = {"01111","10000","10000","10000","10000","10000","01111"},
  K = {"10001","10010","10100","11000","10100","10010","10001"},
  Y = {"10001","10001","01010","00100","00100","00100","00100"},
  S = {"01111","10000","10000","01110","00001","00001","11110"},
  P = {"11110","10001","10001","11110","10000","10000","10000"},
  I = {"11111","00100","00100","00100","00100","00100","11111"},
  N = {"10001","11001","10101","10101","10011","10001","10001"},
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
  local seat = slot.seat(monName)

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

  -- chasing marquee bulbs around a rectangle's edge
  local function drawMarquee(x, y, wd, ht, step, c1, c2, base)
    local idx = 0
    local function bulb(bx, by)
      idx = idx + 1
      local col
      if idx % 2 == 0 then col = base
      else col = (math.floor(idx / 2) + step) % 3 == 0 and c1 or c2 end
      fillRect(bx, by, 1, 1, col)
    end
    for xx = x, x + wd - 1 do bulb(xx, y) end
    for yy = y + 1, y + ht - 1 do bulb(x + wd - 1, yy) end
    for xx = x + wd - 2, x, -1 do bulb(xx, y + ht - 1) end
    for yy = y + ht - 2, y + 1, -1 do bulb(x, yy) end
  end

  -- ---- money ----
  local denomIdx, betIdx = 2, 1
  local function totalBet() return math.floor(DENOMS[denomIdx] * BET_CREDITS[betIdx] * 100 + 0.5) / 100 end

  -- ============================= THE WHEEL =============================
  -- A huge circle whose centre sits far above the screen; only the bottom
  -- arc shows in the top quarter. Each monitor cell's angle/radius is
  -- worked out once, so a frame is just a table lookup per cell.
  local WB = math.max(5, math.floor(h / 4)) -- wheel band = rows 1..WB
  local ASPECT = 1.5                         -- CC characters are 1.5x taller than wide
  local pcx = math.floor(w / 2) + 1          -- pointer column
  local wheelR = math.max(w * 0.42, WB * ASPECT * 2.2)
  local wcx = pcx
  local wcy = WB + 0.5 - wheelR / ASPECT     -- centre row (negative = off screen)
  local RIM, NBULB = 1.8, 56
  local BG_COL = c.black
  local cellA, cellR, starMap = {}, {}, {}
  for y = 1, WB do
    cellA[y], cellR[y], starMap[y] = {}, {}, {}
    for x = 1, w do
      local dx, dy = x - wcx, (y - wcy) * ASPECT
      cellR[y][x] = math.sqrt(dx * dx + dy * dy)
      cellA[y][x] = atan2(dx, dy) -- 0 = straight down (at the pointer)
      starMap[y][x] = math.random() < 0.05
    end
  end

  local wheelTier = "base"
  local wheelRot = math.random() * TWO_PI
  local chase = 0
  local freeMode = false

  local function pointerWedge(rot, n)
    local t = (-rot) / (TWO_PI / n)
    return math.floor(t) % n + 1
  end

  local function wedgeLabel(wd, maxW)
    if wd.t == "free" then return "FREE", wd.n .. " GAMES" end
    if wd.t == "super" then return "SUPER", "WHEEL" end
    local amt = compactMoney(wd.m * totalBet(), maxW)
    if wd.tag then return wd.tag, amt end
    return amt, nil
  end

  -- hi = wedge index to flash white (optional)
  local function drawWheel(hi)
    local wds = wedgesFor(wheelTier)
    local N = #wds
    local wa = TWO_PI / N
    local rot = wheelRot
    local blank = string.rep(" ", w)
    local rimIn = wheelR - RIM
    local sep = 0.55
    for y = 1, WB do
      local t = {}
      local rowA, rowR, rowS = cellA[y], cellR[y], starMap[y]
      for x = 1, w do
        local r = rowR[x]
        local col
        if r > wheelR then
          if rowS[x] then
            col = ((x * 7 + y * 3 + chase) % 6 == 0) and c.white or c.gray
          else
            col = BG_COL
          end
        else
          local a = rowA[x] - rot
          if r > rimIn then
            local u = a / TWO_PI * NBULB
            local fu = u - math.floor(u)
            if fu > 0.25 and fu < 0.75 then
              col = ((math.floor(u) + chase) % 3 == 0) and c.white or c.yellow
            else
              col = wheelTier == "super" and c.red or c.orange
            end
          else
            local tt = a / wa
            local fl = math.floor(tt)
            local fr = tt - fl
            if math.min(fr, 1 - fr) * wa * r < sep then
              col = wheelTier == "super" and c.yellow or c.lightGray
            else
              local i = fl % N + 1
              col = (hi == i) and c.white or wds[i].col
            end
          end
        end
        t[x] = hx(col)
      end
      local row = table.concat(t)
      mon.setCursorPos(1, y)
      mon.blit(blank, row, row)
    end
    -- labels on the wedges that are on screen
    local rl = wheelR - RIM - 3.5
    for i = 1, N do
      local ca = (i - 0.5) * wa + rot
      ca = (ca + math.pi) % TWO_PI - math.pi
      if math.abs(ca) < 1.2 then
        local chord = math.max(2, math.floor(2 * rl * math.sin(wa / 2)) - 1)
        local l1, l2 = wedgeLabel(wds[i], chord)
        local bg = (hi == i) and c.white or wds[i].col
        local fg = (hi == i) and c.black or (wds[i].fg or c.white)
        local function put(str, rad)
          local px = wcx + rad * math.sin(ca)
          local py = math.floor(wcy + rad * math.cos(ca) / ASPECT + 0.5)
          if py >= 1 and py <= WB then
            str = str:sub(1, chord)
            local x0 = math.floor(px - #str / 2 + 0.5)
            if x0 >= 1 and x0 + #str - 1 <= w then text(x0, py, str, fg, bg) end
          end
        end
        if l2 then put(l1, rl - ASPECT); put(l2, rl) else put(l1, rl) end
      end
    end
    -- title in the top-left corner if the wheel leaves room there
    local title = wheelTier == "super" and "SUPER WHEEL" or (freeMode and "FREE GAMES" or "LUCKY SPIN")
    if cellR[1][#title + 2] and cellR[1][#title + 2] > wheelR then
      text(2, 1, title, c.yellow, BG_COL)
      if cellR[2] and cellR[2][#title + 2] > wheelR then
        text(2, 2, "station " .. stationId, c.gray, BG_COL)
      end
    end
    -- pointer tip (the base is drawn under the wheel band)
    fillRect(pcx, WB - 1, 1, 1, c.white)
    fillRect(pcx - 1, WB, 3, 1, c.white)
  end

  -- ============================= BASE GAME LAYOUT =============================
  local hudY = h - 4       -- credits / bet line
  local msgY = h - 3       -- message line
  local btnY = h - 2       -- buttons (3 rows tall: h-2 .. h)
  local sidePanel = w >= 90
  local panelW = sidePanel and 22 or 0
  local areaX0, areaY0 = 2, WB + 3
  local areaW = w - panelW - 3
  local areaH = (hudY - 2) - areaY0 + 1
  local cellW = math.max(4, math.min(22, math.floor(areaW / REELS)))
  local cellH = math.max(3, math.min(12, math.floor(areaH / ROWS)))
  local gridW, gridH = cellW * REELS, cellH * ROWS
  local gridX0 = areaX0 + math.floor((areaW - gridW) / 2) + 1
  local gridY0 = areaY0 + math.floor((areaH - gridH) / 2) + 1
  local FRAME_COL = c.yellow

  local function cellPos(r, row)
    return gridX0 + (r - 1) * cellW, gridY0 + (row - 1) * cellH
  end

  local function drawSymbol(r, row, key, invert)
    local x, y = cellPos(r, row)
    local cw, ch = cellW - 1, cellH - 1
    local s = SYM[key]
    if invert then
      fillRect(x, y, cw, ch, c.white)
      centerIn(x, y + math.floor(ch / 2), cw, s.label, c.black, c.white)
      return
    end
    local artH = ch >= 6 and ch - 1 or ch
    drawBitmap(x, y, cw, artH, ART[s.art], s.bg)
    if artH < ch then
      fillRect(x, y + artH, cw, 1, s.bg)
      centerIn(x, y + artH, cw, s.label, s.fg, s.bg)
    end
  end

  local function drawReelFrame(col)
    fillRect(gridX0 - 1, gridY0 - 1, gridW + 1, gridH + 1, col or FRAME_COL)
  end

  local function drawReelBorder(r, col)
    local x = gridX0 + (r - 1) * cellW - 1
    fillRect(x, gridY0 - 1, cellW + 1, 1, col)
    fillRect(x, gridY0 + gridH - 1, cellW + 1, 1, col)
    fillRect(x, gridY0 - 1, 1, gridH + 1, col)
    fillRect(x + cellW, gridY0 - 1, 1, gridH + 1, col)
  end

  -- ---- side panel: jackpot ladder + feature info ----
  local freeLeft, freePlayed, freeTotal = 0, 0, 0

  local function drawPanel()
    if not sidePanel then return end
    local px, top, bottom = w - panelW + 1, areaY0, hudY - 2
    local pw = panelW - 1
    fillRect(px, top, pw, bottom - top + 1, c.black)
    local y = top
    centerIn(px, y, pw, "SUPER WHEEL", c.yellow, c.black)
    y = y + 1
    for _, tag in ipairs({ "GRAND", "MAJOR", "MINOR", "MINI" }) do
      if y + 1 > bottom then return end
      fillRect(px, y, pw, 2, JP_COL[tag])
      centerIn(px, y, pw, tag, JP_FG[tag], JP_COL[tag])
      centerIn(px, y + 1, pw, compactMoney(JACKPOT_X[tag] * totalBet(), pw), JP_FG[tag], JP_COL[tag])
      y = y + 3
    end
    local lines
    if freeMode then
      lines = {
        { "FREE GAMES", c.lime }, { freeLeft .. " LEFT", c.white },
        { "WINS x" .. FREE_MULT, c.yellow }, { "WON $" .. money(freeTotal), c.lime },
      }
    else
      lines = {
        { "3 WHEELS ON", c.white }, { "REELS 2-3-4", c.white },
        { "= SPIN THE", c.yellow }, { "WHEEL!", c.yellow },
      }
    end
    for _, ln in ipairs(lines) do
      if y > bottom then return end
      centerIn(px, y, pw, ln[1], ln[2], c.black)
      y = y + 1
    end
  end

  -- ---- HUD / buttons ----
  local buttons = {}
  local message, messageCol = "TOUCH SPIN TO PLAY", c.lightGray

  local function drawHud()
    fillRect(1, hudY, w, 2, c.black)
    local vol = volume <= 0 and "MUTE" or string.format("%.1f", volume)
    text(2, hudY, seat:hud() .. "   DENOM $" .. money(DENOMS[denomIdx])
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
    local col = freeMode and c.gray or c.lime
    fillRect(sx, btnY, sw, 3, col)
    centerIn(sx, btnY + 1, sw, freeMode and "FREE" or "SPIN!", c.black, col)
    buttons[#buttons + 1] = { label = "SPIN!", x1 = sx, x2 = sx + sw - 1, y1 = btnY, y2 = btnY + 2 }
  end

  local currentGrid = genGrid(false)

  local function drawBackground()
    -- 16-bit carpet: diagonal diamond lattice under the wheel
    local line = freeMode and c.green or c.purple
    local blank = string.rep(" ", w)
    local hl, hb = hx(line), hx(c.black)
    for y = WB + 1, h do
      local t = {}
      for x = 1, w do
        t[x] = (((x + y * 2) % 10 == 0) or ((x - y * 2) % 10 == 0)) and hl or hb
      end
      local row = table.concat(t)
      mon.setCursorPos(1, y)
      mon.blit(blank, row, row)
    end
    fillRect(pcx - 2, WB + 1, 5, 1, c.yellow) -- pointer base
    fillRect(pcx - 3, WB + 2, 7, 1, c.orange)
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
    drawWheel()
    drawReelFrame()
    drawGrid(currentGrid)
    drawPanel()
    drawHud()
    drawButtons()
  end

  -- banner across the reels, with chasing bulbs
  local function banner(str, col, hold, sub)
    local bh = 7
    local by = gridY0 + math.floor((gridH - bh) / 2)
    local bx, bw = 3, w - 4
    for i = 1, 6 do
      fillRect(bx, by, bw, bh, col)
      drawMarquee(bx, by, bw, bh, i, c.white, c.yellow, col)
      fillRect(bx + 2, by + 2, bw - 4, 3, c.black)
      centerIn(bx + 2, by + 3, bw - 4, str, i % 2 == 1 and c.white or col, c.black)
      if sub then centerIn(bx + 2, by + 4, bw - 4, sub, c.lightGray, c.black) end
      sleep(0.12)
    end
    sleep(hold or 1)
  end

  -- ============================= OPENING =============================
  local function showStartScreen()
    fillRect(1, 1, w, h, c.black)
    local topY = math.floor(h / 2) - 5
    local fanfare = { 6, 10, 13, 18, 13, 18, 22, 18, 22, 24 }
    for i = 1, #fanfare + 8 do
      drawMarquee(1, 1, w, h, i, c.white, c.yellow, c.orange)
      drawMarquee(3, 3, w - 4, h - 4, i + 1, c.red, c.magenta, c.black)
      local col = (i % 2 == 0) and c.yellow or c.orange
      if not drawBigText("LUCKY SPIN", topY, col, c.black) then
        centerIn(1, topY + 3, w, "LUCKY SPIN", col, c.black)
      end
      if fanfare[i] then
        note("bell", 1.5, fanfare[i])
        note("bass", 1, fanfare[i] - 6 >= 0 and fanfare[i] - 6 or fanfare[i])
      elseif i == #fanfare + 1 then
        sfx("ui.toast.challenge_complete", 1, 1)
      end
      if i > #fanfare then
        centerIn(1, topY + 9, w, "station " .. stationId .. "  -  3 WHEELS = SPIN THE WHEEL", c.lightGray, c.black)
      end
      sleep(0.14)
    end
    sleep(0.6)
  end

  -- one showy turn of the wheel after the title (no prize)
  local function demoSpin()
    local n = #wedgesFor(wheelTier)
    local rot0 = wheelRot
    local last = pointerWedge(rot0, n)
    for f = 1, 40 do
      local p = f / 40
      wheelRot = rot0 + TWO_PI * (1 - (1 - p) ^ 3)
      chase = chase + 1
      drawWheel()
      local pw = pointerWedge(wheelRot, n)
      if pw ~= last then last = pw; note("hat", 1, 20) end
      sleep(0.05)
    end
  end

  -- ============================= SPIN ANIMATION =============================
  local function randomVisual(r, free)
    if WHEEL_REELS[r] and math.random() < 0.1 then return "WHEEL" end
    local strip = (free and FREE_STRIPS or STRIPS)[r]
    return strip[math.random(#strip)]
  end

  local function animateSpin(grid, wildReel)
    local FRAME = 0.07
    local stopAt, stopped = {}, {}
    for r = 1, REELS do stopAt[r] = 8 + (r - 1) * 4 end
    local frame, teasing, teaseReel = 0, false, 4
    local wheelsSeen = 0
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
              if grid[r][row] == "WHEEL" then
                wheelsSeen = wheelsSeen + 1
                note("chime", 1.5, 8 + wheelsSeen * 5)
                sfx("block.amethyst_block.chime", 1.5, 0.8 + wheelsSeen * 0.2)
              end
            end
            if r == wildReel then
              -- WILD REEL: sweep the reel gold, top to bottom
              for row = 1, ROWS do
                local x, y = cellPos(r, row)
                fillRect(x, y, cellW - 1, cellH - 1, c.yellow)
                note("pling", 1.5, 12 + row * 4)
                sleep(0.08)
                drawSymbol(r, row, grid[r][row])
              end
              sfx("entity.player.levelup", 1, 1.5)
              setMessage("WILD REEL!", c.yellow)
            end
            -- TEASE: WHEEL on reels 2 and 3 -> reel 4 hangs on
            if r == 3 and #findWheels(grid, 2, 2) > 0 and #findWheels(grid, 3, 3) > 0 then
              teasing = true
              stopAt[teaseReel] = frame + TEASE_FRAMES
              stopAt[5] = math.max(stopAt[5], stopAt[teaseReel] + 4)
              setMessage("2 WHEELS... ONE MORE!", c.yellow)
            end
            if r == teaseReel and teasing then
              drawReelFrame()
              drawGrid(grid)
            end
          else
            allDone = false
            for row = 1, ROWS do drawSymbol(r, row, randomVisual(r, freeMode)) end
          end
        end
      end
      if teasing and not stopped[teaseReel] then
        local t = frame % 4
        drawReelBorder(teaseReel, (t < 2) and c.yellow or c.red)
        if t == 0 then note("basedrum", 2, 4) end -- heartbeat
        if t == 2 then note("basedrum", 1.3, 6) end
        local left = stopAt[teaseReel] - frame
        note("pling", 0.8, math.min(24, math.floor((TEASE_FRAMES - left) * 24 / TEASE_FRAMES)))
        -- the wheel's bulbs race while you wait
        chase = chase + 1
        if t == 1 then drawWheel() end
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

  local function flashCells(grid, cells, col, times)
    for i = 1, times do
      for _, s in ipairs(cells) do
        local x, y = cellPos(s.r, s.row)
        fillRect(x, y, cellW - 1, cellH - 1, i % 2 == 1 and col or c.black)
      end
      sleep(0.12)
      for _, s in ipairs(cells) do drawSymbol(s.r, s.row, grid[s.r][s.row]) end
      sleep(0.1)
    end
  end

  -- ============================= WHEEL BONUS =============================
  -- waits for a touch on this monitor (or the timeout); bulbs keep chasing
  local function waitTouch(timeout)
    local deadline = os.clock() + timeout
    local tid = os.startTimer(0.15)
    local blink = 0
    while true do
      local ev, a = os.pullEvent()
      if ev == "monitor_touch" and a == monName then return true end
      if ev == "timer" and a == tid then
        if os.clock() >= deadline then return false end
        chase = chase + 1
        blink = blink + 1
        drawWheel()
        fillRect(pcx - 2, WB + 1, 5, 1, blink % 4 < 2 and c.yellow or c.white)
        if blink % 8 == 0 then note("pling", 0.6, 18) end
        tid = os.startTimer(0.15)
      end
    end
  end

  -- spins so wedge `idx` ends up under the pointer
  -- edge: nil = land anywhere in the wedge, +1/-1 = hug that side (near miss)
  local function spinWheelTo(idx, edge)
    local n = #wedgesFor(wheelTier)
    local wa = TWO_PI / n
    local j = edge and (edge * 0.38) or ((math.random() - 0.5) * 0.6)
    local want = (-((idx - 0.5 + j) * wa)) % TWO_PI
    local base = wheelRot + TWO_PI * (3 + math.random())
    local target = base + ((want - base) % TWO_PI)
    local rot0, D = wheelRot, target - wheelRot
    local frames = 110
    local last = pointerWedge(rot0, n)
    sfx("entity.player.attack.sweep", 1.5, 0.6)
    for f = 1, frames do
      local p = f / frames
      wheelRot = rot0 + D * (1 - (1 - p) ^ 3)
      chase = chase + 1
      drawWheel()
      local pw = pointerWedge(wheelRot, n)
      if pw ~= last then
        last = pw
        note("hat", 1.3, 16 + math.floor(p * 8))   -- the clicker
        if p > 0.6 then note("snare", 0.4, 10) end
      end
      if p > 0.72 and f % 2 == 0 then note("snare", 0.3 + p * 0.6, 4 + math.floor(p * 10)) end -- drumroll
      sleep(0.05)
    end
    wheelRot = target
  end

  local function flashWedge(idx, times)
    for i = 1, times do
      drawWheel(idx)
      sleep(0.12)
      drawWheel()
      sleep(0.1)
    end
    drawWheel(idx)
  end

  local function nearMissEdge(tier, idx)
    local wds = wedgesFor(tier)
    local n = #wds
    local nxt, prv = wds[idx % n + 1], wds[(idx - 2) % n + 1]
    local function juicy(wd) return wd.t == "super" or wd.tag == "GRAND" or wd.tag == "MAJOR" end
    if juicy(wds[idx]) or math.random() < 0.4 then return nil end
    if juicy(nxt) then return 1 end
    if juicy(prv) then return -1 end
    return nil
  end

  -- returns cash won, free games won
  local function runWheel()
    local tier = "base"
    local bet = totalBet()
    while true do
      wheelTier = tier
      drawWheel()
      drawPanel()
      setMessage(tier == "super" and "SUPER WHEEL! TOUCH THE SCREEN TO SPIN!" or "TOUCH THE SCREEN TO SPIN THE WHEEL!", c.yellow)
      waitTouch(WHEEL_AUTO_SPIN)
      setMessage("GOOD LUCK!", c.white)
      local wd, idx = pickWedge(tier)
      spinWheelTo(idx, nearMissEdge(tier, idx))
      if wd.t == "super" then
        sfx("entity.firework_rocket.launch", 2, 1)
        flashWedge(idx, 4)
        sfx("entity.firework_rocket.twinkle", 2, 1)
        banner("SUPER WHEEL!", c.red, 1, "jackpots are in play - spin again!")
        drawFrame()
        tier = "super"
      elseif wd.t == "free" then
        sfx("entity.player.levelup", 1.5, 1)
        flashWedge(idx, 4)
        wheelTier = "base"
        return 0, wd.n
      else
        local amt = wd.m * bet
        if wd.tag then
          for i = 1, (wd.tag == "GRAND" or wd.tag == "MAJOR") and 6 or 3 do
            sfx("entity.firework_rocket.blast", 2, 0.8 + i * 0.1)
            flashWedge(idx, 1)
          end
          sfx("ui.toast.challenge_complete", 1, 1)
          banner(wd.tag .. " JACKPOT!  $" .. money(amt), JP_COL[wd.tag], 2)
        else
          sfx("entity.player.levelup", 1, 1.2)
          flashWedge(idx, 4)
          banner("WHEEL PAYS $" .. money(amt), c.orange, 1.2)
        end
        wheelTier = "base"
        drawFrame()
        return amt, 0
      end
    end
  end

  -- the build-up before the wheel spins
  local function wheelIntro(grid, wheels, random)
    if random then
      setMessage("WAIT... THE WHEEL WANTS TO SPIN!", c.orange)
      for i = 1, 8 do
        drawReelFrame(i % 2 == 1 and c.red or FRAME_COL)
        drawGrid(grid)
        note("basedrum", 2, 4 + i)
        chase = chase + 2
        drawWheel()
        sleep(0.15)
      end
    else
      flashCells(grid, wheels, c.yellow, 3)
    end
    local rise = { 6, 8, 10, 12, 13, 15, 17, 18, 20, 22, 24 }
    for i, p in ipairs(rise) do
      chase = chase + 1
      drawWheel()
      note("bell", 1.5, p)
      note("harp", 1, p)
      sleep(0.08)
    end
    sfx("ui.toast.challenge_complete", 1, 1.2)
    banner("SPIN THE WHEEL!", c.orange, 0.8)
    drawFrame()
  end

  -- ============================= FREE GAMES =============================
  local function runFreeGames(n)
    local bet = totalBet()
    freeMode, freeLeft, freePlayed, freeTotal = true, n, 0, 0
    sfx("entity.player.levelup", 1.5, 0.8)
    banner(n .. " FREE GAMES!", c.lime, 1.2, "all wins x" .. FREE_MULT .. "  -  extra wilds  -  wild reels")
    drawFrame()
    while freeLeft > 0 do
      freeLeft = freeLeft - 1
      freePlayed = freePlayed + 1
      drawPanel()
      setMessage("FREE GAME " .. freePlayed .. "  -  " .. freeLeft .. " LEFT  -  WON $" .. money(freeTotal), c.lime)
      sleep(0.5)
      local grid, wildReel = genGrid(true)
      currentGrid = grid
      animateSpin(grid, wildReel)
      local win, hits = evaluateLines(grid, bet / #LINES)
      win = win * FREE_MULT
      if win > 0 then
        freeTotal = freeTotal + win
        flashWin(grid, hits)
        if win >= bet * BIG_WIN_X then
          sfx("ui.toast.challenge_complete", 1, 1)
          banner("BIG WIN!  $" .. money(win), c.yellow, 1.2)
          drawFrame()
          drawGrid(grid, hits)
        end
        setMessage("FREE GAME WIN $" .. money(win) .. " (x" .. FREE_MULT .. ")", c.lime)
      end
      local wheels = findWheels(grid)
      if #wheels >= 3 then
        sleep(0.5)
        wheelIntro(grid, wheels, false)
        local cash, more = runWheel()
        freeTotal = freeTotal + cash
        if more > 0 then
          more = math.min(more, MAX_FREE_GAMES - (freePlayed + freeLeft))
          if more > 0 then
            freeLeft = freeLeft + more
            banner("+" .. more .. " FREE GAMES!", c.lime, 1)
          end
        end
        drawFrame()
      end
      drawPanel()
      sleep(0.6)
    end
    freeMode = false
    seat:win(freeTotal)
    sfx("ui.toast.challenge_complete", 1, 1)
    banner("FREE GAMES WIN $" .. money(freeTotal), c.lime, 2.2, freePlayed .. " games played")
    drawFrame()
    return freeTotal
  end

  -- ============================= MAIN SPIN =============================
  local busy = false

  local function doSpin()
    if busy then return end
    local bet = totalBet()
    busy = true
    local ok, why, kind = seat:begin(bet)
    if not ok then
      busy = false
      setMessage(why, kind == "welcome" and c.lime or c.red)
      return
    end
    message = nil
    drawHud()
    fillRect(1, msgY, w, 1, c.black)

    local grid = genGrid(false)
    currentGrid = grid
    animateSpin(grid)

    local wheels = findWheels(grid)
    local win, hits = evaluateLines(grid, bet / #LINES)
    if win > 0 then
      seat:win(win)
      flashWin(grid, hits)
      if win >= bet * BIG_WIN_X then
        sfx("ui.toast.challenge_complete", 1, 1)
        banner("BIG WIN!  $" .. money(win), c.yellow, 1.5)
        drawFrame()
        drawGrid(grid, hits)
      end
      setMessage("YOU WIN $" .. money(win) .. "!", c.lime)
    else
      setMessage(#wheels == 2 and "SO CLOSE! 2 WHEELS" or "NO WIN - TRY AGAIN", c.red)
    end

    local randomHit = #wheels < 3 and randomWheelHit(BET_CREDITS[betIdx])
    if #wheels >= 3 or randomHit then
      sleep(0.8)
      wheelIntro(grid, wheels, randomHit)
      local cash, free = runWheel()
      local paid = cash
      seat:win(cash)
      if free > 0 then paid = paid + runFreeGames(free) end
      currentGrid = grid
      drawFrame()
      setMessage("BONUS PAID $" .. money(paid) .. "!", c.lime)
    end

    local problem = seat:finish()
    if problem then setMessage(problem, c.red) else drawHud() end
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
    if label == "DENOM" or label == "-BET" or label == "+BET" then
      drawWheel()  -- wheel $ values follow the bet
      drawPanel()
    end
  end

  local lastTouch, lastTouchTime = nil, 0
  local function inputLoop()
    while true do
      local ev, side, x, y = os.pullEvent("monitor_touch")
      local used, usedMsg = false, nil
      if side == monName and not busy then used, usedMsg = seat:touch() end
      if used then
        setMessage(usedMsg, c.yellow)
      elseif side == monName and not busy then
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

  -- idle: the wheel drifts and its bulbs chase
  local function animationLoop()
    while true do
      sleep(0.2)
      if not busy then
        chase = chase + 1
        wheelRot = wheelRot + 0.004
        drawWheel()
      end
    end
  end

  seat:onChange(function() if not busy then drawHud() end end)

  local function run()
    showStartScreen()
    drawFrame()
    demoSpin()
    parallel.waitForAll(inputLoop, animationLoop)
  end

  return { run = run, monName = monName, stationId = stationId }
end

-- ============================= DISCOVER STATIONS =============================
slot.setup{ game = "luckyspin", kind = "Lucky Spin", practiceCredits = START_CREDITS }

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
print("Lucky Spin: " .. #monitors .. " station(s), " .. #speakers .. " speaker(s). Running.")

slot.run(table.unpack(runFns))
