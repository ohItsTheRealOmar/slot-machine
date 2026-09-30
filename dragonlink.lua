--[[
  DRAGON LINK  -  Hold & Spin slot for CC:Tweaked
  -----------------------------------------------
  Setup:  computer + monitor wall (built for 5 wide x 4 tall, auto-fits
          anything from 3x3 up). Speakers optional - every speaker on the
          computer / wired network plays.
  Run:    dragonlink
  Terminal commands while running:
          add <n> | set <n> | credits | jackpots | resetjp | demo hold | demo free | exit

  Rules:
  * 5 reels x 3 rows, 243 WAYS - symbols pay left to right on adjacent reels,
    any row. WILD (gold coin) on reels 2-5 subs for every picture/royal.
  * HOLD & SPIN: 6 or more FIREBALLS anywhere triggers the feature.
      - Every fireball locks in place with a credit prize or a jackpot
        (MINI / MINOR / MAJOR) and you get 3 respins.
      - Only the empty spots spin. Every new fireball locks and RESETS the
        respins back to 3.
      - Feature ends when respins run out or all 15 spots are full.
      - Fill all 15 spots = GRAND jackpot, on top of every prize.
  * FREE GAMES: a GOLD INGOT on reels 2, 3 and 4 = 6 free games played on
    reels loaded with extra wilds and dragons. Hold & Spin can trigger inside
    free games. Three more ingots = +6 games.
  * MINI 10x bet, MINOR 25x bet. MAJOR (100x) and GRAND (1000x) are
    progressive per bet level - a slice of every bet grows them.
  * Designed return ~94% at seed jackpots, ~94.6% counting progressive
    growth (3M-spin simulation, see sim_dragonlink.lua).
]]

------------------------------------------------------------------ CONFIG
local CONFIG = {
  textScale     = 0.5,                   -- 0.5 = sharpest
  creditFile    = "dragonlink_credits.txt",
  jackpotFile   = "dragonlink_jackpots.txt",
  startCredits  = 5000,                  -- practice bankroll
  practiceMode  = true,                  -- refill to startCredits when you run dry
  betLevels     = {25, 50, 75, 100, 150, 250, 500},  -- keep these multiples of 25
  triggerCount  = 6,                     -- fireballs needed for Hold & Spin
  respins       = 3,
  respinChance  = 0.05,                  -- chance an empty spot lands a fireball per respin
  freeGames     = 6,
  progressive   = true,                  -- grow MAJOR / GRAND from every bet
  majorRate     = 0.004,                 -- share of each bet added to MAJOR
  grandRate     = 0.002,                 -- share of each bet added to GRAND
  spinDelay     = 0.05,                  -- seconds per reel step
  customPalette = true,                  -- turns brown into a deep crimson backdrop
}

------------------------------------------------------------------ MATH
local UNIT = 25                          -- pays below are credits at a 25 bet
local PAYING = {"DR", "TG", "KO", "LN", "A", "K", "Q", "J", "T"}
local PAY = {               -- 3 / 4 / 5 of a kind, per way
  DR = {40, 160, 600},
  TG = {30, 100, 350},
  KO = {25,  80, 250},
  LN = {20,  70, 200},
  A  = {15,  40, 150},
  K  = {15,  35, 120},
  Q  = {10,  30, 100},
  J  = { 5,  25,  75},
  T  = { 5,  25,  75},
}
local NAMES = { DR = "DRAGON", TG = "TIGER", KO = "KOI", LN = "LANTERN",
                A = "ACE", K = "KING", Q = "QUEEN", J = "JACK", T = "TEN" }

-- fireball prizes: number = x total bet, string = jackpot
local ORB = {
  {1, 40}, {2, 30}, {3, 20}, {5, 12}, {8, 6}, {10, 4}, {15, 2},
  {"MINI", 4}, {"MINOR", 1.5}, {"MAJOR", 0.15},
}
local JP_MULT  = { MINI = 10, MINOR = 25, MAJOR = 100, GRAND = 1000 }
local JP_ORDER = { "GRAND", "MAJOR", "MINOR", "MINI" }

local ORB_TOTAL = 0
for _, o in ipairs(ORB) do ORB_TOTAL = ORB_TOTAL + o[2] end

local function rollOrb(rand)
  local x = rand() * ORB_TOTAL
  for _, o in ipairs(ORB) do
    x = x - o[2]
    if x < 0 then
      if type(o[1]) == "string" then return { jp = o[1] } end
      return { mult = o[1] }
    end
  end
  return { mult = 1 }
end

-- deterministic shuffle (Park-Miller) so every computer builds identical reels
local function makeStrip(counts, seed)
  local s = {}
  for _, c in ipairs(counts) do for _ = 1, c[2] do s[#s + 1] = c[1] end end
  local x = seed
  for i = #s, 2, -1 do
    x = (x * 16807) % 2147483647
    local j = x % i + 1
    s[i], s[j] = s[j], s[i]
  end
  return s
end

local function counts(t)
  local c = {}
  for _, k in ipairs({"DR","TG","KO","LN","A","K","Q","J","T","WL","SC","FB"}) do
    if t[k] and t[k] > 0 then c[#c + 1] = {k, t[k]} end
  end
  return c
end

local BASE = {
  counts{DR=3, TG=4, KO=4, LN=5, A=6, K=6, Q=6, J=7, T=7,             FB=8},
  counts{DR=3, TG=4, KO=4, LN=5, A=5, K=6, Q=6, J=6, T=7, WL=2, SC=3, FB=9},
  counts{DR=3, TG=4, KO=4, LN=5, A=5, K=6, Q=6, J=6, T=7, WL=2, SC=3, FB=9},
  counts{DR=3, TG=4, KO=4, LN=5, A=5, K=6, Q=6, J=6, T=7, WL=2, SC=3, FB=9},
  counts{DR=3, TG=4, KO=4, LN=5, A=5, K=6, Q=6, J=6, T=7, WL=2,       FB=8},
}
local FREE = {
  counts{DR=8, TG=5, KO=4, LN=5, A=5, K=5, Q=5, J=6, T=6,             FB=7},
  counts{DR=8, TG=5, KO=4, LN=5, A=5, K=5, Q=5, J=5, T=5, WL=7, SC=2, FB=7},
  counts{DR=8, TG=5, KO=4, LN=5, A=5, K=5, Q=5, J=5, T=5, WL=7, SC=2, FB=7},
  counts{DR=8, TG=5, KO=4, LN=5, A=5, K=5, Q=5, J=5, T=5, WL=7, SC=2, FB=7},
  counts{DR=8, TG=5, KO=4, LN=5, A=5, K=5, Q=5, J=5, T=5, WL=7,       FB=7},
}
local STRIPS, FSTRIPS = {}, {}
for r = 1, 5 do
  STRIPS[r]  = makeStrip(BASE[r], 1234 + r * 7919)
  FSTRIPS[r] = makeStrip(FREE[r], 4321 + r * 104729)
end

local function wrap(strip, p) return ((p - 1) % #strip) + 1 end
local function symAt(strips, r, p) local s = strips[r]; return s[wrap(s, p)] end

-- grid[r][row], row 1 = top; stop = strip index shown in the middle row
local function window(strips, stops)
  local g = {}
  for r = 1, 5 do
    g[r] = {}
    for row = 1, 3 do g[r][row] = symAt(strips, r, stops[r] + row - 2) end
  end
  return g
end

-- 243-ways evaluation. Returns wins (credits), fireball + scatter counts.
local function evaluate(grid, bet)
  local res = { wins = {}, total = 0, fb = 0, sc = 0 }
  for _, s in ipairs(PAYING) do
    local ways, n, cells = 1, 0, {}
    for r = 1, 5 do
      local c = 0
      for row = 1, 3 do
        local g = grid[r][row]
        if g == s or (g == "WL" and r > 1) then c = c + 1; cells[#cells + 1] = {r, row} end
      end
      if c == 0 then break end
      ways, n = ways * c, r
    end
    if n >= 3 then
      -- drop cells from reels past the win
      local keep = {}
      for _, c in ipairs(cells) do if c[1] <= n then keep[#keep + 1] = c end end
      local amt = math.floor(PAY[s][n - 2] * ways * bet / UNIT)
      res.wins[#res.wins + 1] = { sym = s, n = n, ways = ways, pay = amt, cells = keep }
      res.total = res.total + amt
    end
  end
  table.sort(res.wins, function(a, b) return a.pay > b.pay end)
  for r = 1, 5 do
    local hasSc = false
    for row = 1, 3 do
      if grid[r][row] == "FB" then res.fb = res.fb + 1 end
      if grid[r][row] == "SC" then hasSc = true end
    end
    if hasSc and r >= 2 and r <= 4 then res.sc = res.sc + 1 end
  end
  return res
end

-- Hold & Spin state: cells[r][row] = orb or false
local function newHold(grid, orbs)
  local hs = { cells = {}, count = 0, spins = CONFIG.respins }
  for r = 1, 5 do
    hs.cells[r] = {}
    for row = 1, 3 do
      if grid[r][row] == "FB" then
        hs.cells[r][row] = orbs[r][row]
        hs.count = hs.count + 1
      else
        hs.cells[r][row] = false
      end
    end
  end
  return hs
end

-- one respin; returns list of newly landed {r,row}
local function holdStep(hs, rand)
  local new = {}
  for r = 1, 5 do for row = 1, 3 do
    if not hs.cells[r][row] and rand() < CONFIG.respinChance then
      hs.cells[r][row] = rollOrb(rand)
      new[#new + 1] = {r, row}
    end
  end end
  hs.count = hs.count + #new
  if #new > 0 then hs.spins = CONFIG.respins else hs.spins = hs.spins - 1 end
  return new
end

local function holdDone(hs) return hs.spins <= 0 or hs.count >= 15 end

local function orbCredits(orb, bet, jpv)
  if orb.jp then return jpv[orb.jp] end
  return orb.mult * bet
end

-- exported for testing outside Minecraft
if not term or not peripheral then
  return { CONFIG = CONFIG, STRIPS = STRIPS, FSTRIPS = FSTRIPS, window = window,
           evaluate = evaluate, newHold = newHold, holdStep = holdStep,
           holdDone = holdDone, rollOrb = rollOrb, orbCredits = orbCredits,
           JP_MULT = JP_MULT, PAY = PAY }
end

------------------------------------------------------------------ PERIPHERALS
local mon = peripheral.find("monitor")
if not mon then error("No monitor found - attach the monitor wall (5 wide x 4 tall)", 0) end
local speakers = { peripheral.find("speaker") }
math.randomseed(os.epoch("utc"))

local function note(inst, pitch, vol)
  for _, s in ipairs(speakers) do pcall(s.playNote, inst, vol or 1, pitch) end
end
local function sfx(name, vol, pitch)
  for _, s in ipairs(speakers) do pcall(s.playSound, name, vol or 1, pitch or 1) end
end
-- F# major pentatonic: sounds "eastern" on note blocks
local PENTA = {0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24}

local PALETTE = { [colors.brown] = 0x4a0808 }
local function applyPalette()
  if not CONFIG.customPalette or not mon.setPaletteColour then return end
  for c, v in pairs(PALETTE) do mon.setPaletteColour(c, v) end
end
local function restorePalette()
  if not mon.setPaletteColour then return end
  for c in pairs(PALETTE) do mon.setPaletteColour(c, term.nativePaletteColour(c)) end
end

------------------------------------------------------------------ STATE
local state = {
  credits = CONFIG.startCredits, betIdx = 1, lastWin = 0,
  msg = "TAP SPIN TO PLAY", stops = {3, 9, 15, 21, 27}, vals = {},
  strips = STRIPS, spinning = false, mode = "base",
  hl = {}, dim = false, anticip = nil,
  hold = nil, holdWin = 0,
  free = 0, freeTotal = 0, freeWin = 0,
  info = 0, tick = 0, flash = nil, jpFlash = nil, force = nil,
  jp = { major = {}, grand = {} },
}

local function loadCredits()
  if fs.exists(CONFIG.creditFile) then
    local h = fs.open(CONFIG.creditFile, "r")
    local v = tonumber(h.readAll()); h.close()
    state.credits = v or 0
  end
end
local function saveCredits()
  local h = fs.open(CONFIG.creditFile, "w")
  h.write(tostring(state.credits)); h.close()
end
local function loadJP()
  if fs.exists(CONFIG.jackpotFile) then
    local h = fs.open(CONFIG.jackpotFile, "r")
    local t = textutils.unserialize(h.readAll()); h.close()
    if type(t) == "table" and t.major and t.grand then state.jp = t end
  end
end
local function saveJP()
  local h = fs.open(CONFIG.jackpotFile, "w")
  h.write(textutils.serialize(state.jp)); h.close()
end

local function curBet() return CONFIG.betLevels[state.betIdx] end
local function jpValues(idx)
  idx = idx or state.betIdx
  local bet = CONFIG.betLevels[idx]
  return {
    MINI  = JP_MULT.MINI * bet,
    MINOR = JP_MULT.MINOR * bet,
    MAJOR = math.floor(JP_MULT.MAJOR * bet + (state.jp.major[idx] or 0)),
    GRAND = math.floor(JP_MULT.GRAND * bet + (state.jp.grand[idx] or 0)),
  }
end
local function contribute(bet)
  if not CONFIG.progressive then return end
  local i = state.betIdx
  state.jp.major[i] = (state.jp.major[i] or 0) + bet * CONFIG.majorRate
  state.jp.grand[i] = (state.jp.grand[i] or 0) + bet * CONFIG.grandRate
  saveJP()
end

local function fmt(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return out
end

-- fireball values live on strip positions so they scroll with the reel
local function rerollVals()
  for r = 1, 5 do
    state.vals[r] = {}
    local st = state.strips[r]
    for p = 1, #st do
      if st[p] == "FB" then state.vals[r][p] = rollOrb(math.random) end
    end
  end
end
local function valAt(r, p) return state.vals[r] and state.vals[r][wrap(state.strips[r], p)] end

------------------------------------------------------------------ SCREEN BUFFER
local W, H
local bt, bf, bb = {}, {}, {}

local function clear(bg)
  for y = 1, H do
    bt[y], bf[y], bb[y] = {}, {}, {}
    for x = 1, W do bt[y][x] = " "; bf[y][x] = "0"; bb[y][x] = bg end
  end
end
local function put(x, y, ch, fg, bg)
  if x >= 1 and x <= W and y >= 1 and y <= H then
    bt[y][x] = ch
    if fg then bf[y][x] = fg end
    if bg then bb[y][x] = bg end
  end
end
local function fill(x, y, w, h, bg)
  for yy = y, y + h - 1 do for xx = x, x + w - 1 do put(xx, yy, " ", "0", bg) end end
end
local function text(x, y, s, fg, bg)
  for i = 1, #s do put(x + i - 1, y, s:sub(i, i), fg, bg) end
end
local function ctext(x, y, w, s, fg, bg)
  if #s > w then s = s:sub(1, w) end
  text(x + math.floor((w - #s) / 2), y, s, fg, bg)
end
local function flush()
  for y = 1, H do
    mon.setCursorPos(1, y)
    mon.blit(table.concat(bt[y]), table.concat(bf[y]), table.concat(bb[y]))
  end
end

------------------------------------------------------------------ BIG 3x5 FONT
local FONT = {
  A={".X.","X.X","XXX","X.X","X.X"}, B={"XX.","X.X","XX.","X.X","XX."},
  C={".XX","X..","X..","X..",".XX"}, D={"XX.","X.X","X.X","X.X","XX."},
  E={"XXX","X..","XX.","X..","XXX"}, F={"XXX","X..","XX.","X..","X.."},
  G={".XX","X..","X.X","X.X",".XX"}, H={"X.X","X.X","XXX","X.X","X.X"},
  I={"XXX",".X.",".X.",".X.","XXX"}, J={"..X","..X","..X","X.X",".X."},
  K={"X.X","X.X","XX.","X.X","X.X"}, L={"X..","X..","X..","X..","XXX"},
  M={"X.X","XXX","XXX","X.X","X.X"}, N={"XX.","X.X","X.X","X.X","X.X"},
  O={".X.","X.X","X.X","X.X",".X."}, P={"XX.","X.X","XX.","X..","X.."},
  Q={".X.","X.X","X.X","XX.",".XX"}, R={"XX.","X.X","XX.","X.X","X.X"},
  S={".XX","X..",".X.","..X","XX."}, T={"XXX",".X.",".X.",".X.",".X."},
  U={"X.X","X.X","X.X","X.X","XXX"}, V={"X.X","X.X","X.X","X.X",".X."},
  W={"X.X","X.X","XXX","XXX","X.X"}, X={"X.X","X.X",".X.","X.X","X.X"},
  Y={"X.X","X.X",".X.",".X.",".X."}, Z={"XXX","..X",".X.","X..","XXX"},
  ["0"]={"XXX","X.X","X.X","X.X","XXX"}, ["1"]={".X.","XX.",".X.",".X.","XXX"},
  ["2"]={"XX.","..X",".X.","X..","XXX"}, ["3"]={"XX.","..X",".X.","..X","XX."},
  ["4"]={"X.X","X.X","XXX","..X","..X"}, ["5"]={"XXX","X..","XX.","..X","XX."},
  ["6"]={".XX","X..","XXX","X.X","XXX"}, ["7"]={"XXX","..X",".X.",".X.",".X."},
  ["8"]={"XXX","X.X","XXX","X.X","XXX"}, ["9"]={"XXX","X.X","XXX","..X","XX."},
  ["&"]={".X.","X.X",".X.","X.X",".XX"}, ["!"]={".X.",".X.",".X.","...",".X."},
  [","]={"...","...","...",".X.","X.."}, ["/"]={"..X","..X",".X.","X..","X.."},
  [" "]={"...","...","...","...","..."},
}
local function bigW(s, pw) pw = pw or 1; return #s * 4 * pw - pw end
local function bigText(x, y, s, fg, pw, ph)
  pw, ph = pw or 1, ph or 1
  for i = 1, #s do
    local g = FONT[s:sub(i, i)] or FONT[" "]
    for ry = 1, 5 do
      local line = g[ry]
      for rx = 1, 3 do
        if line:sub(rx, rx) == "X" then
          fill(x + ((i - 1) * 4 + rx - 1) * pw, y + (ry - 1) * ph, pw, ph, fg)
        end
      end
    end
  end
end
-- big text with a 1px drop shadow, centred in a box
local function bigCenter(x, y, w, s, fg, shadow, pw, ph)
  pw, ph = pw or 1, ph or 1
  local tx = x + math.floor((w - bigW(s, pw)) / 2)
  if shadow then bigText(tx + 1, y + 1, s, shadow, pw, ph) end
  bigText(tx, y, s, fg, pw, ph)
end

------------------------------------------------------------------ LAYOUT
local Lay = {}
local function layout()
  mon.setTextScale(CONFIG.textScale)
  W, H = mon.getSize()
  Lay.bigTitle = H >= 40 and W >= bigW("DRAGON LINK", 1) + 4
  Lay.titleH = Lay.bigTitle and 7 or 3
  Lay.jpY    = Lay.titleH + 1
  Lay.jpH    = 3
  Lay.panelH = 8
  Lay.panelY = H - Lay.panelH + 1
  Lay.frameY = Lay.jpY + Lay.jpH
  local availH = Lay.panelY - 1 - Lay.frameY
  Lay.cellH  = math.max(3, math.floor((availH - 4) / 3))
  Lay.cellW  = math.max(5, math.floor((W - 2 - 6) / 5))
  Lay.frameW = 5 * Lay.cellW + 6
  Lay.frameH = 3 * Lay.cellH + 4
  Lay.frameX = math.floor((W - Lay.frameW) / 2) + 1
  Lay.cellX0 = Lay.frameX + 1
  Lay.cellY0 = Lay.frameY + 1
end
local function cellPos(r, row)
  return Lay.cellX0 + (r - 1) * (Lay.cellW + 1), Lay.cellY0 + (row - 1) * (Lay.cellH + 1)
end

------------------------------------------------------------------ SYMBOL ART (7x7)
local ART = {
  DR = { "11.....", ".1eee..", "eee4eee", "eeeeeee", "ee0.0.0", "eeeeee.", ".e.e..." },
  TG = { "11...11", "1f1f1f1", "1111111", "1f111f1", "1110111", ".11f11.", "..000.." },
  KO = { "..11...", ".1111.1", "1f10111", "1110011", ".1111.1", "..11...", "......." },
  LN = { "...4...", ".44444.", "eeeeeee", "e4eee4e", "eeeeeee", ".44444.", "..4.4.." },
  WL = { "..444..", ".41114.", "441f144", "41fff14", "441f144", ".41114.", "..444.." },
  SC = { ".......", "4.....4", "44.1.44", "4444444", ".44444.", "..444..", "......." },
  FB = { "..eee..", ".e111e.", "e11411e", "e14441e", "e11411e", ".e111e.", "..eee.." },
}
local ROYAL = { A = {"A", "e"}, K = {"K", "b"}, Q = {"Q", "a"}, J = {"J", "d"}, T = {"10", "9"} }
local LABEL = { DR = {"DRAGON", "d"}, TG = {"TIGER", "1"}, KO = {"KOI", "1"},
                LN = {"LANTERN", "e"}, WL = {"WILD", "4"}, SC = {"FREE GAMES", "4"} }
local JP_COLORS = { GRAND = "e", MAJOR = "a", MINOR = "b", MINI = "d" }
local GLOW = { e = "1", ["1"] = "4", ["4"] = "0" }
local DIM  = function() return "7" end
local GHOST = { e = "7", ["1"] = "8", ["4"] = "8" }

local function orbLabel(orb, bet)
  if orb.jp then return orb.jp, JP_COLORS[orb.jp] end
  return fmt(orb.mult * bet), "4"
end

-- draws 7x7 art clipped to the rect (cx,cy,cw,ch); map recolors pixels
local function drawArt(art, ox, oy, pw, ph, map, cx, cy, cw, ch)
  for ry = 1, 7 do
    local line = art[ry]
    for rx = 1, 7 do
      local c = line:sub(rx, rx)
      if c ~= "." then
        if type(map) == "function" then c = map(c)
        elseif map and map[c] then c = map[c] end
        for yy = oy + (ry - 1) * ph, oy + ry * ph - 1 do
          if yy >= cy and yy < cy + ch then
            for xx = ox + (rx - 1) * pw, ox + rx * pw - 1 do
              if xx >= cx and xx < cx + cw then put(xx, yy, " ", nil, c) end
            end
          end
        end
      end
    end
  end
end

local SHORT = { DR = "DRAGN", TG = "TIGER", KO = "KOI", LN = "LNTRN", A = "A", K = "K",
                Q = "Q", J = "J", T = "10", WL = "WILD", SC = "FREE", FB = "FIRE" }

local function drawSymbol(sym, x, y, w, h, orb, dim, glow)
  fill(x, y, w, h, "f")
  if not sym or sym == "--" then return end
  local bet = curBet()
  if ROYAL[sym] then
    local s, col = ROYAL[sym][1], ROYAL[sym][2]
    local gw = bigW(s, 1)
    if gw + 2 > w or h < 6 then
      ctext(x, y + math.floor(h / 2), w, s, dim and "7" or col, "f"); return
    end
    local pw = math.max(1, math.min(3, math.floor((w - 2) / gw)))
    local ph = math.max(1, math.min(math.floor((h - 1) / 5), math.floor(pw * 2 / 3 + 0.5)))
    local tx = x + math.floor((w - gw * pw) / 2)
    local ty = y + math.floor((h - 5 * ph) / 2)
    if not dim then bigText(tx + 1, ty, s, "7", pw, ph) end
    bigText(tx, ty, s, dim and "7" or col, pw, ph)
    return
  end
  local art = ART[sym]
  local label
  if sym == "FB" and orb then label = { orbLabel(orb, bet) } else label = LABEL[sym] end
  local lab = label and 1 or 0
  local ph = math.floor((h - 2 - lab) / 7)
  if ph < 1 then ph = math.floor((h - lab) / 7) end
  if ph < 1 and label and sym ~= "FB" then label, lab = nil, 0; ph = math.floor(h / 7) end
  if ph < 1 then
    local t = (sym == "FB" and orb) and label[1] or SHORT[sym]
    local fg = dim and "7" or ((sym == "FB") and "1" or (label and label[2]) or "0")
    if sym == "FB" and not dim then fg = "f" end
    if sym == "FB" and not dim then fill(x, y, w, h, glow and "1" or "e") end
    ctext(x, y + math.floor(h / 2), w, t, fg, (sym == "FB" and not dim) and (glow and "1" or "e") or "f")
    return
  end
  local pw = math.max(1, math.min(math.floor((w - 2) / 7), ph * 2))
  local aw, ah = pw * 7, ph * 7
  local ox = x + math.floor((w - aw) / 2)
  local oy = y + math.floor((h - ah - lab) / 2)
  local map = dim and DIM or (glow and GLOW) or nil
  drawArt(art, ox, oy, pw, ph, map, x, y, w, h)
  if label then ctext(x, oy + ah, w, label[1], dim and "7" or label[2], "f") end
end

-- Hold & Spin: a locked fireball
local function drawOrbCell(x, y, w, h, orb, bet, glow, flashWhite)
  if flashWhite then fill(x, y, w, h, "0"); return end
  local c = orb.jp and JP_COLORS[orb.jp] or "e"
  fill(x, y, w, h, glow and "4" or "1")
  fill(x + 1, y + 1, w - 2, h - 2, c)
  local t = orb.jp or fmt(orb.mult * bet):gsub(",", "")
  local fg = orb.jp and "0" or "4"
  if bigW(t) <= w - 2 and h >= 7 then
    bigCenter(x + 1, y + math.floor((h - 5) / 2), w - 2, t, fg, orb.jp and "f" or "c")
  else
    ctext(x + 1, y + math.floor(h / 2), w - 2, orb.jp or fmt(orb.mult * bet), fg, c)
  end
end

-- Hold & Spin: an empty spot (spinning = scrolling ghost fireballs)
local function drawEmptyCell(x, y, w, h, spinning, phase)
  fill(x, y, w, h, "f")
  if spinning then
    local ph = math.max(1, math.floor((h - 1) / 7))
    local pw = math.max(1, math.min(math.floor((w - 2) / 7), ph * 2))
    local period = h + 2
    local oy = y + ((phase % period) - 7 * ph)
    local ox = x + math.floor((w - 7 * pw) / 2)
    drawArt(ART.FB, ox, oy, pw, ph, GHOST, x, y, w, h)
    drawArt(ART.FB, ox, oy + period, pw, ph, GHOST, x, y, w, h)
  else
    for xx = x, x + w - 1 do put(xx, y, " ", nil, "7"); put(xx, y + h - 1, " ", nil, "7") end
    for yy = y, y + h - 1 do put(x, yy, " ", nil, "7"); put(x + w - 1, yy, " ", nil, "7") end
  end
end

local function frameCell(r, row, color)
  local x, y = cellPos(r, row)
  local w, h = Lay.cellW, Lay.cellH
  for xx = x - 1, x + w do put(xx, y - 1, " ", nil, color); put(xx, y + h, " ", nil, color) end
  for yy = y - 1, y + h do put(x - 1, yy, " ", nil, color); put(x + w, yy, " ", nil, color) end
end

------------------------------------------------------------------ DRAW
local function flame()
  local r = math.random()
  if r < 0.35 then return "e" elseif r < 0.65 then return "1" elseif r < 0.8 then return "4" end
  return "c"
end

local function drawTitle()
  local bg = state.flash or "c"
  fill(1, 1, W, Lay.titleH, bg)
  for x = 1, W do
    put(x, 1, " ", nil, flame())
    if Lay.titleH > 3 then put(x, Lay.titleH, " ", nil, flame()) end
  end
  local t = "DRAGON LINK"
  if state.mode == "hold" then t = "HOLD & SPIN"
  elseif state.mode == "free" then t = "FREE GAMES" end
  if Lay.bigTitle then
    local pw = (bigW(t, 2) <= W - 4) and 2 or 1
    bigCenter(1, 2, W, t, "4", "f", pw, 1)
  else
    ctext(1, 2, W, "\4 " .. t .. " \4", "4", bg)
  end
end

local function drawJackpots()
  local v = jpValues()
  local gap = 1
  local bw = math.floor((W - 2 - gap * 3) / 4)
  local x0 = math.floor((W - (bw * 4 + gap * 3)) / 2) + 1
  for i, k in ipairs(JP_ORDER) do
    local bx = x0 + (i - 1) * (bw + gap)
    local c, fg = JP_COLORS[k], "0"
    if state.jpFlash == k and state.tick % 2 == 0 then c, fg = "4", "f" end
    fill(bx, Lay.jpY, bw, 2, c)
    ctext(bx, Lay.jpY, bw, k, fg == "0" and "4" or fg, c)
    ctext(bx, Lay.jpY + 1, bw, fmt(v[k]), fg, c)
  end
end

local function drawReels()
  local fc = "4"
  if state.mode == "hold" then fc = (state.tick % 2 == 0) and "e" or "1" end
  if state.mode == "free" then fc = "b" end
  fill(Lay.frameX, Lay.frameY, Lay.frameW, Lay.frameH, fc)
  fill(Lay.frameX + 1, Lay.frameY + 1, Lay.frameW - 2, Lay.frameH - 2, "c")
  local hlSet = {}
  for _, w in ipairs(state.hl) do
    for _, c in ipairs(w.cells) do hlSet[c[1] * 10 + c[2]] = true end
  end
  local bet = curBet()
  local glow = state.tick % 2 == 0
  for r = 1, 5 do
    for row = 1, 3 do
      local x, y = cellPos(r, row)
      if state.mode == "hold" and state.hold then
        local hs = state.hold
        local key = r * 10 + row
        local orb = hs.cells[r][row]
        if orb and not hs.hidden[key] then
          drawOrbCell(x, y, Lay.cellW, Lay.cellH, orb, bet, glow, hs.flash[key])
        else
          drawEmptyCell(x, y, Lay.cellW, Lay.cellH, hs.spinning[key], hs.phase + r * 3 + row * 5)
        end
      else
        local p = state.stops[r] + row - 2
        local sym = symAt(state.strips, r, p)
        local dim = state.dim and not hlSet[r * 10 + row]
        drawSymbol(sym, x, y, Lay.cellW, Lay.cellH, sym == "FB" and valAt(r, p), dim,
                   sym == "FB" and glow)
      end
    end
  end
  for _, w in ipairs(state.hl) do
    for _, c in ipairs(w.cells) do frameCell(c[1], c[2], w.color or "4") end
  end
  -- anticipation: flashing border around the reel that is still spinning
  if state.anticip then
    local r = state.anticip
    local x, y = cellPos(r, 1)
    local col = ({"e", "1", "4", "0"})[(state.tick % 4) + 1]
    local h = 3 * Lay.cellH + 2
    for yy = y - 1, y + h do put(x - 1, yy, " ", nil, col); put(x + Lay.cellW, yy, " ", nil, col) end
    for xx = x - 1, x + Lay.cellW do put(xx, y - 1, " ", nil, col); put(xx, y + h, " ", nil, col) end
  end
end

local function drawPanel()
  local y = Lay.panelY
  fill(1, y - 1, W, Lay.panelH + 1, "f")
  local bet = curBet()
  local boxes
  if state.mode == "hold" and state.hold then
    local hs = state.hold
    local lamps = ""
    for i = 1, CONFIG.respins do lamps = lamps .. (i <= hs.shown and "\7 " or "- ") end
    boxes = {
      {"CREDITS", fmt(state.credits), "4"}, {"BET", fmt(bet), "0"},
      {"RESPINS", lamps, hs.shown > 0 and "e" or "8"}, {"HOLD WIN", fmt(state.holdWin), "5"},
    }
  elseif state.mode == "free" then
    boxes = {
      {"CREDITS", fmt(state.credits), "4"}, {"BET", fmt(bet), "0"},
      {"FREE GAME", (state.freeTotal - state.free) .. " / " .. state.freeTotal, "b"},
      {"FREE WIN", fmt(state.freeWin), "5"},
    }
  else
    boxes = {
      {"CREDITS", fmt(state.credits), "4"}, {"BET", fmt(bet), "0"},
      {"WAYS", "243", "0"}, {"WIN", fmt(state.lastWin), "5"},
    }
  end
  local bw = math.floor(W / 4)
  for i, b in ipairs(boxes) do
    local bx = 1 + (i - 1) * bw
    ctext(bx, y, bw, b[1], "8", "f")
    ctext(bx, y + 1, bw, b[2], b[3], "f")
  end
  ctext(1, y + 2, W, state.msg or "", state.mode ~= "base" and "4" or "0", "f")

  local busy = state.spinning or state.mode ~= "base"
  local spinLabel = busy and "..." or "SPIN"
  local btns = {
    {"info", "INFO", "7", 1}, {"minus", "BET-", "b", 1}, {"plus", "BET+", "b", 1},
    {"max", "MAX", "a", 1}, {"spin", spinLabel, busy and "7" or "d", 2},
  }
  local total = 0
  for _, b in ipairs(btns) do total = total + b[4] end
  local gap = 1
  local unit = (W - 2 - gap * (#btns - 1)) / total
  local x = 2
  local by, bh = y + 4, 3
  Lay.buttons = {}
  for i, b in ipairs(btns) do
    local bw2 = (i == #btns) and (W - 1 - x + 1) or math.floor(unit * b[4])
    local c = b[3]
    if busy and b[1] ~= "spin" then c = "7" end
    fill(x, by, bw2, bh, c)
    ctext(x, by + 1, bw2, b[2], "0", c)
    Lay.buttons[#Lay.buttons + 1] = { id = b[1], x = x, y = by, w = bw2, h = bh }
    x = x + bw2 + gap
  end
end

local INFO_PAGES
local function drawInfo()
  clear("f")
  local lines = INFO_PAGES[state.info]()
  local y0 = math.max(1, math.floor((H - #lines) / 2))
  for i, l in ipairs(lines) do ctext(1, y0 + i - 1, W, l[1], l[2], "f") end
  flush()
end

local function render()
  clear("c")
  drawTitle()
  drawJackpots()
  drawReels()
  drawPanel()
end

local function draw()
  if state.info > 0 then return drawInfo() end
  render(); flush()
end

INFO_PAGES = {
  function()
    local bet = curBet()
    local t = {
      {"DRAGON LINK - PAYS AT BET " .. bet .. " (PER WAY)", "4"}, {"", "0"},
      {string.format("%-9s %7s %7s %7s", "SYMBOL", "3", "4", "5"), "8"},
    }
    local col = { DR = "d", TG = "1", KO = "1", LN = "e", A = "e", K = "b", Q = "a", J = "d", T = "9" }
    for _, s in ipairs(PAYING) do
      local p = PAY[s]
      t[#t + 1] = { string.format("%-9s %7s %7s %7s", NAMES[s],
        fmt(p[1] * bet / UNIT), fmt(p[2] * bet / UNIT), fmt(p[3] * bet / UNIT)), col[s] }
    end
    t[#t + 1] = {"", "0"}
    t[#t + 1] = {"243 WAYS: pays left to right, any row", "0"}
    t[#t + 1] = {"WILD coin on reels 2-5 subs for all pays", "4"}
    t[#t + 1] = {"Ways multiply: 2 on reel 1 x 2 on reel 2 = 4 ways", "8"}
    t[#t + 1] = {"", "0"}
    t[#t + 1] = {"- TAP FOR PAGE 2 -", "8"}
    return t
  end,
  function()
    local bet = curBet()
    return {
      {"HOLD & SPIN", "e"}, {"", "0"},
      {"6 or more FIREBALLS anywhere triggers it", "1"},
      {"Fireballs lock with a prize and you get 3 RESPINS", "0"},
      {"Only empty spots spin", "0"},
      {"Every new fireball locks & RESETS respins to 3", "4"},
      {"Ends when respins run out or all 15 spots fill", "0"},
      {"", "0"},
      {"FIREBALL PRIZES: " .. fmt(bet) .. " to " .. fmt(15 * bet) .. " or a jackpot", "4"},
      {"MINI  / MINOR / MAJOR can land on any fireball", "0"},
      {"FILL ALL 15 SPOTS = GRAND JACKPOT!", "e"},
      {"", "0"},
      {"- TAP FOR PAGE 3 -", "8"},
    }
  end,
  function()
    local v = jpValues()
    return {
      {"FREE GAMES & JACKPOTS", "b"}, {"", "0"},
      {"GOLD INGOT on reels 2, 3 and 4 = " .. CONFIG.freeGames .. " FREE GAMES", "4"},
      {"Free reels carry extra WILDS and DRAGONS", "0"},
      {"Hold & Spin can trigger during free games", "0"},
      {"3 more ingots = +" .. CONFIG.freeGames .. " games", "0"},
      {"", "0"},
      {"GRAND  " .. fmt(v.GRAND) .. (CONFIG.progressive and "  (progressive)" or ""), "e"},
      {"MAJOR  " .. fmt(v.MAJOR) .. (CONFIG.progressive and "  (progressive)" or ""), "a"},
      {"MINOR  " .. fmt(v.MINOR), "b"},
      {"MINI   " .. fmt(v.MINI), "d"},
      {"Jackpots scale with your bet", "8"},
      {"", "0"},
      {"- TAP TO RETURN -", "8"},
    }
  end,
}

------------------------------------------------------------------ ANIMATION HELPERS
-- waits t seconds; returns true early if the screen is tapped
local function waitTap(t)
  local tm = os.startTimer(t)
  while true do
    local e, a = os.pullEvent()
    if e == "timer" and a == tm then return false end
    if e == "monitor_touch" then return true end
  end
end

-- classic "doom fire" over the reel window with a big banner
local function fireShow(title, frames)
  local fx, fy, fw, fh = Lay.frameX, Lay.frameY, Lay.frameW, Lay.frameH
  local heat = {}
  for y = 1, fh do heat[y] = {}; for x = 1, fw do heat[y][x] = 0 end end
  local FIRE = { "c", "e", "e", "1", "1", "4", "4", "0" }
  sfx("minecraft:entity.ender_dragon.growl", 1, 1)
  for f = 1, frames do
    local src = (f < frames - 10) and 7 or 0
    for x = 1, fw do heat[fh][x] = (src > 0) and math.random(4, 7) or 0 end
    for y = 1, fh - 1 do
      local row, below = heat[y], heat[y + 1]
      for x = 1, fw do
        local sx = math.max(1, math.min(fw, x + math.random(-1, 1)))
        local v = below[sx] - ((math.random() < 0.3) and 1 or 0)
        row[x] = v > 0 and v or 0
      end
    end
    state.tick = state.tick + 1
    render()
    for y = 1, fh do
      for x = 1, fw do
        local v = heat[y][x]
        if v > 0 then put(fx + x - 1, fy + y - 1, " ", nil, FIRE[math.min(8, v)]) end
      end
    end
    if f > 4 then
      local pw = (bigW(title, 2) <= fw - 4) and 2 or 1
      local ph = (fh >= 18) and 2 or 1
      bigCenter(fx, fy + math.floor((fh - 5 * ph) / 2), fw, title,
                (f % 4 < 2) and "4" or "0", "f", pw, ph)
    end
    flush()
    if f % 3 == 0 then note("basedrum", 4 + (f % 6), 1) end
    if f % 6 == 0 then sfx("minecraft:item.firecharge.use", 0.8, 0.8 + (f % 12) / 20) end
    if f > 4 and f % 2 == 0 and f / 2 <= #PENTA + 2 then
      note("pling", PENTA[math.min(#PENTA, f / 2 - 1)] or 12, 1)
    end
    sleep(0.05)
  end
end

-- coin shower + rolling total for big wins
local function bigWinShow(amount, bet)
  local x = amount / bet
  if x < 10 then return end
  local tier = (x >= 50 and "EPIC WIN") or (x >= 25 and "MEGA WIN") or "BIG WIN"
  local fx, fy, fw, fh = Lay.frameX, Lay.frameY, Lay.frameW, Lay.frameH
  local coins = {}
  local frames = (x >= 50 and 90) or (x >= 25 and 70) or 50
  local skipped = false
  sfx("minecraft:ui.toast.challenge_complete", 1, 1)
  for f = 1, frames do
    for _ = 1, 3 do
      coins[#coins + 1] = { x = fx + math.random(0, fw - 2), y = fy, v = math.random(1, 2), s = math.random(0, 1) }
    end
    state.tick = state.tick + 1
    render()
    for i = #coins, 1, -1 do
      local c = coins[i]
      c.y = c.y + c.v; c.s = 1 - c.s
      if c.y >= fy + fh then table.remove(coins, i)
      else
        put(c.x, c.y, " ", nil, c.s == 0 and "4" or "1")
        put(c.x + 1, c.y, " ", nil, c.s == 0 and "1" or "4")
      end
    end
    local shown = skipped and amount or math.floor(amount * math.min(1, f / (frames * 0.7)))
    local pw = (bigW(tier, 2) <= fw - 4) and 2 or 1
    local cy = fy + math.floor(fh / 2) - 6
    fill(fx + 2, cy - 2, fw - 4, 17, (f % 4 < 2) and "4" or "1")
    fill(fx + 3, cy - 1, fw - 6, 15, "f")
    bigCenter(fx, cy, fw, tier, (f % 4 < 2) and "4" or "0", "e", pw, 1)
    local num = fmt(shown)
    if bigW(num, pw) <= fw - 4 then
      bigCenter(fx, cy + 7, fw, num, "0", "f", pw, 1)
    else
      ctext(fx, cy + 8, fw, num, "0", "f")
    end
    state.msg = tier .. "!  " .. fmt(shown)
    flush()
    if not skipped and f % 2 == 0 then sfx("minecraft:entity.experience_orb.pickup", 0.6, 0.6 + (f % 20) / 20) end
    if f % 4 == 0 then note("bell", PENTA[((f / 4) % #PENTA) + 1], 1) end
    if waitTap(0.05) then
      if skipped then break end
      skipped = true
    end
  end
  sfx("minecraft:entity.player.levelup", 1, 1)
end

local function jackpotShow(kind, amount)
  state.jpFlash = kind
  local fx, fy, fw, fh = Lay.frameX, Lay.frameY, Lay.frameW, Lay.frameH
  local c = JP_COLORS[kind]
  local frames = kind == "GRAND" and 60 or (kind == "MAJOR" and 40 or 24)
  if kind == "GRAND" or kind == "MAJOR" then sfx("minecraft:ui.toast.challenge_complete", 1, 1) end
  local sparks = {}
  for f = 1, frames do
    state.tick = state.tick + 1
    render()
    local bh = math.min(fh - 2, 15)
    local by = fy + math.floor((fh - bh) / 2)
    fill(fx + 2, by, fw - 4, bh, (f % 4 < 2) and c or "4")
    fill(fx + 3, by + 1, fw - 6, bh - 2, c)
    for _ = 1, 4 do sparks[#sparks + 1] = { x = fx + math.random(2, fw - 3), y = by + math.random(0, bh - 1), t = 3 } end
    for i = #sparks, 1, -1 do
      local s = sparks[i]; s.t = s.t - 1
      if s.t <= 0 then table.remove(sparks, i) else put(s.x, s.y, "*", "0", nil) end
    end
    local pw = (bigW(kind, 2) <= fw - 8) and 2 or 1
    bigCenter(fx, by + 2, fw, kind, "0", "f", pw, 1)
    ctext(fx, by + 9, fw, "JACKPOT", "4", c)
    ctext(fx, by + 11, fw, fmt(amount) .. " CREDITS", "0", c)
    state.msg = "*** " .. kind .. " JACKPOT  " .. fmt(amount) .. " ***"
    flush()
    if f % 5 == 1 then sfx("minecraft:entity.firework_rocket.blast", 1, 1) end
    if f % 5 == 3 then sfx("minecraft:entity.firework_rocket.twinkle", 1, 1) end
    note("pling", PENTA[(f % #PENTA) + 1], 1)
    sleep(0.1)
  end
  state.jpFlash = nil
end

-- count a number up in the WIN box
local function rollUp(field, target)
  local start = state[field]
  local steps = math.min(20, math.max(1, math.floor(target / 5)))
  for i = 1, steps do
    state[field] = start + math.floor(target * i / steps)
    if i % 2 == 0 then note("bit", 10 + (i % 12), 0.6) end
    state.tick = state.tick + 1
    draw()
    if waitTap(0.04) then state[field] = start + target; draw(); return end
  end
end

------------------------------------------------------------------ HOLD & SPIN
local function holdAndSpin(grid, orbs, bet)
  local prevMode = state.mode
  local jpv = jpValues()
  local hs = newHold(grid, orbs)
  hs.hidden, hs.spinning, hs.flash, hs.phase, hs.shown = {}, {}, {}, 0, CONFIG.respins
  state.msg = hs.count .. " FIREBALLS - HOLD & SPIN!"
  state.hl, state.dim = {}, false
  fireShow("HOLD & SPIN", 45)

  -- lock the triggering fireballs one by one
  state.hold, state.mode, state.holdWin = hs, "hold", 0
  for r = 1, 5 do for row = 1, 3 do
    if hs.cells[r][row] then hs.hidden[r * 10 + row] = true end
  end end
  draw(); sleep(0.3)
  local n = 0
  for r = 1, 5 do for row = 1, 3 do
    local key = r * 10 + row
    if hs.hidden[key] then
      n = n + 1
      hs.hidden[key] = nil; hs.flash[key] = true
      draw()
      sfx("minecraft:entity.blaze.shoot", 0.8, 1 + n * 0.05)
      note("chime", PENTA[math.min(#PENTA, n)], 1)
      sleep(0.1)
      hs.flash[key] = nil
    end
  end end
  state.msg = "3 RESPINS - EVERY FIREBALL RESETS THEM!"
  draw(); sleep(1)

  while not holdDone(hs) do
    local before = hs.spins
    local new = holdStep(hs, math.random)
    local newSet = {}
    for _, c in ipairs(new) do newSet[c[1] * 10 + c[2]] = true; hs.hidden[c[1] * 10 + c[2]] = true end
    hs.shown = before - 1
    state.msg = "SPINNING..."
    local order = {}
    for r = 1, 5 do for row = 1, 3 do
      local key = r * 10 + row
      if not hs.cells[r][row] or newSet[key] then hs.spinning[key] = true; order[#order + 1] = key end
    end end
    note("bass", 6, 1)
    for f = 1, 12 do
      hs.phase = hs.phase + 2; state.tick = state.tick + 1
      draw()
      if f % 2 == 0 then note("hat", 14 + (f % 6), 0.5) end
      sleep(0.05)
    end
    -- stop spots one at a time, top-left to bottom-right, still scrolling
    for _, key in ipairs(order) do
      hs.spinning[key] = nil
      if newSet[key] then
        hs.hidden[key] = nil; hs.flash[key] = true
        draw()
        sfx("minecraft:entity.blaze.shoot", 1, 1)
        note("chime", 19, 1)
        sleep(0.15)
        hs.flash[key] = nil
        state.msg = "FIREBALL!  " .. hs.count .. " / 15"
      else
        note("hat", 8, 0.4)
      end
      hs.phase = hs.phase + 2; state.tick = state.tick + 1
      draw()
      sleep(0.05)
    end
    if #new > 0 then
      hs.shown = CONFIG.respins
      state.msg = (#new > 1 and (#new .. " NEW FIREBALLS") or "NEW FIREBALL") .. " - RESPINS RESET TO 3!"
      for i, p in ipairs({12, 16, 19, 24}) do note("pling", p, 1); if i < 4 then sleep(0.06) end end
    else
      hs.shown = hs.spins
      state.msg = hs.spins > 0 and (hs.spins .. " RESPIN" .. (hs.spins > 1 and "S" or "") .. " LEFT") or "LAST SPIN DONE"
      note("bass", 3 + hs.spins * 3, 1)
    end
    draw(); sleep(0.7)
  end

  -- collect every prize
  local grand = hs.count >= 15
  state.msg = grand and "ALL 15 FILLED!!!" or "COLLECTING PRIZES..."
  draw(); sleep(grand and 1.2 or 0.6)
  local total, won = 0, {}
  local k = 0
  for r = 1, 5 do for row = 1, 3 do
    local orb = hs.cells[r][row]
    if orb then
      k = k + 1
      local key = r * 10 + row
      local v = orbCredits(orb, bet, jpv)
      hs.flash[key] = true; draw()
      if orb.jp then
        hs.flash[key] = nil
        jackpotShow(orb.jp, v)
        won[orb.jp] = true
      else
        sfx("minecraft:entity.experience_orb.pickup", 1, 0.8 + math.min(k, 15) * 0.05)
        note("xylophone", PENTA[((k - 1) % #PENTA) + 1], 1)
        sleep(0.12)
      end
      hs.flash[key] = nil
      total = total + v
      state.holdWin = total
      state.msg = "COLLECT " .. fmt(v) .. "  -  TOTAL " .. fmt(total)
      hs.cells[r][row] = false   -- collected spots go dark
      draw(); sleep(0.08)
    end
  end end
  if grand then
    total = total + jpv.GRAND
    state.holdWin = total
    jackpotShow("GRAND", jpv.GRAND)
    won.GRAND = true
  end
  if won.MAJOR then state.jp.major[state.betIdx] = 0 end
  if won.GRAND then state.jp.grand[state.betIdx] = 0 end
  if won.MAJOR or won.GRAND then saveJP() end

  state.msg = "HOLD & SPIN WON " .. fmt(total) .. "!"
  draw(); sleep(1)
  state.mode, state.hold = prevMode, nil
  return total
end

------------------------------------------------------------------ SPIN
local function findForced(strips, want)
  for _ = 1, 200000 do
    local st = {}
    for r = 1, 5 do st[r] = math.random(#strips[r]) end
    local res = evaluate(window(strips, st), CONFIG.betLevels[1])
    if (want == "hold" and res.fb >= CONFIG.triggerCount) or (want == "free" and res.sc >= 3) then
      return st
    end
  end
end

local function showWins(res)
  local colors_ = {"4", "5", "3", "6", "9", "1"}
  for i, w in ipairs(res.wins) do w.color = colors_[((i - 1) % #colors_) + 1] end
  state.hl, state.dim = res.wins, true
  local function describe(w)
    return NAMES[w.sym] .. " x" .. w.n .. (w.ways > 1 and ("  " .. w.ways .. " WAYS") or "") .. "  = " .. fmt(w.pay)
  end
  state.msg = (#res.wins == 1) and describe(res.wins[1]) or ("WIN " .. fmt(res.total) .. "!")
  draw()
  if #res.wins > 1 then
    for _, w in ipairs(res.wins) do
      state.hl = { w }; state.msg = describe(w)
      state.tick = state.tick + 1
      draw()
      if waitTap(0.8) then break end
    end
    state.hl = res.wins
    state.msg = "WIN " .. fmt(res.total) .. "!"
    draw()
  end
end

local runFreeGames

local function doSpin(isFree)
  local bet = curBet()
  if not isFree then
    if state.credits < bet and CONFIG.practiceMode then
      state.credits = CONFIG.startCredits; saveCredits()
      state.msg = "PRACTICE MODE - REFILLED TO " .. fmt(CONFIG.startCredits)
      note("chime", 12); draw(); return
    elseif state.credits < bet then
      state.msg = "NOT ENOUGH CREDITS - SEE ATTENDANT"
      note("didgeridoo", 4); draw(); return
    end
    state.credits = state.credits - bet
    saveCredits()
    contribute(bet)
    state.lastWin = 0
  end
  state.strips = isFree and FSTRIPS or STRIPS
  state.hl, state.dim = {}, false
  state.spinning = true
  state.msg = isFree and ("FREE GAME " .. (state.freeTotal - state.free + 1) .. " OF " .. state.freeTotal) or "GOOD LUCK!"

  local final
  if state.force and not isFree then final = findForced(state.strips, state.force); state.force = nil end
  if not final then
    final = {}
    for r = 1, 5 do final[r] = math.random(#state.strips[r]) end
  end
  rerollVals()
  local rem = {}
  for r = 1, 5 do rem[r] = 8 + r * 5 + math.random(0, 2) end
  local stopped = {}
  local fbSeen, scSeen, extended = 0, 0, false
  local moving = true
  sfx("minecraft:block.lever.click", 0.6, 1.2)
  while moving do
    moving = false
    for r = 1, 5 do
      if rem[r] > 0 then
        rem[r] = rem[r] - 1
        state.stops[r] = final[r] + rem[r]      -- counting down = reel rolls downward
        if rem[r] == 0 then
          stopped[r] = true
          note("basedrum", 6, 1)
          local fbHere, scHere = 0, false
          for row = 1, 3 do
            local s = symAt(state.strips, r, final[r] + row - 2)
            if s == "FB" then fbHere = fbHere + 1 end
            if s == "SC" and r >= 2 and r <= 4 then scHere = true end
          end
          if fbHere > 0 then
            fbSeen = fbSeen + fbHere
            sfx("minecraft:item.firecharge.use", 0.7, 0.9 + fbSeen * 0.08)
            note("chime", PENTA[math.min(#PENTA, fbSeen + 2)], 1)
          end
          if scHere then
            scSeen = scSeen + 1
            note("bell", 12 + scSeen * 5, 1)
          end
          -- anticipation: close to a trigger with reels still turning
          if not extended and r < 5 and
             (fbSeen >= CONFIG.triggerCount - 2 or
              (scSeen == 2 and r == 3)) then
            extended = true
            local add = 0
            for rr = r + 1, 5 do
              if rem[rr] > 0 then add = add + 14; rem[rr] = rem[rr] + add end
            end
          end
        else
          moving = true
        end
      end
    end
    state.anticip = nil
    if extended then
      for r = 1, 5 do if rem[r] > 0 then state.anticip = r; break end end
      if state.anticip then note("bass", 2 + (state.tick % 4) * 2, 0.8) end
    end
    state.tick = state.tick + 1
    draw()
    sleep(state.anticip and CONFIG.spinDelay * 1.5 or CONFIG.spinDelay)
  end
  state.anticip = nil
  for r = 1, 5 do state.stops[r] = final[r] end
  state.spinning = false

  local grid = window(state.strips, state.stops)
  local res = evaluate(grid, bet)
  local spinWin = 0

  if res.total > 0 then
    spinWin = res.total
    state.credits = state.credits + res.total; saveCredits()
    if isFree then state.freeWin = state.freeWin + res.total else state.lastWin = 0 end
    for i, p in ipairs(res.total >= bet * 5 and {7, 12, 16, 19, 24} or {12, 16, 19}) do note("bell", p, 1); if i < 5 then sleep(0.06) end end
    if not isFree then rollUp("lastWin", res.total) else draw() end
    showWins(res)
    if res.total >= bet * 10 and res.fb < CONFIG.triggerCount then bigWinShow(res.total, bet) end
  elseif not isFree then
    state.msg = "TAP SPIN TO PLAY"
  end

  if res.fb >= CONFIG.triggerCount then
    local orbs = {}
    for r = 1, 5 do
      orbs[r] = {}
      for row = 1, 3 do orbs[r][row] = valAt(r, state.stops[r] + row - 2) or { mult = 1 } end
    end
    sleep(0.5)
    local won = holdAndSpin(grid, orbs, bet)
    spinWin = spinWin + won
    state.credits = state.credits + won; saveCredits()
    if isFree then state.freeWin = state.freeWin + won else state.lastWin = spinWin end
    state.hl, state.dim = {}, false
    draw()
    bigWinShow(won, bet)
    state.msg = "HOLD & SPIN PAID " .. fmt(won) .. "!"
    draw()
  end

  if res.sc >= 3 then
    local sc = {}
    for r = 2, 4 do for row = 1, 3 do if grid[r][row] == "SC" then sc[#sc + 1] = {r, row} end end end
    state.hl, state.dim = { { cells = sc, color = "4" } }, true
    for i = 1, 6 do
      state.tick = state.tick + 1; draw()
      note("bell", PENTA[i + 3], 1); sleep(0.12)
    end
    if isFree then
      state.free = state.free + CONFIG.freeGames
      state.freeTotal = state.freeTotal + CONFIG.freeGames
      state.msg = "RETRIGGER! +" .. CONFIG.freeGames .. " FREE GAMES"
      sfx("minecraft:entity.player.levelup", 1, 1.2)
      draw(); sleep(1.2)
    else
      state.free, state.freeTotal, state.freeWin = CONFIG.freeGames, CONFIG.freeGames, 0
    end
  end
  draw()
end

runFreeGames = function()
  local bet = curBet()
  state.mode = "free"
  state.msg = CONFIG.freeGames .. " FREE GAMES - EXTRA WILDS & DRAGONS!"
  fireShow("FREE GAMES", 40)
  for i, p in ipairs({0, 4, 7, 12, 16, 19, 24}) do note("flute", p, 1); sleep(0.08) end
  while state.free > 0 do
    sleep(0.8)
    doSpin(true)
    state.free = state.free - 1
    draw()
  end
  sleep(0.8)
  local won = state.freeWin
  state.strips = STRIPS
  state.mode = "base"
  state.lastWin = won
  state.hl, state.dim = {}, false
  state.msg = "FREE GAMES PAID " .. fmt(won) .. "!"
  draw()
  if won >= bet * 10 then bigWinShow(won, bet) else
    for _, p in ipairs({12, 16, 19}) do note("bell", p, 1); sleep(0.08) end
  end
  state.freeWin, state.freeTotal = 0, 0
  state.msg = "FREE GAMES PAID " .. fmt(won) .. "!"
  draw()
end

------------------------------------------------------------------ INPUT
local function hit(x, y)
  for _, b in ipairs(Lay.buttons or {}) do
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b.id end
  end
end

local function betMsg()
  local bet = curBet()
  local v = jpValues()
  state.msg = "BET " .. fmt(bet) .. "  -  243 WAYS  -  GRAND " .. fmt(v.GRAND)
end

local function onTouch(x, y)
  if state.info > 0 then
    state.info = state.info + 1
    if state.info > #INFO_PAGES then state.info = 0 end
    note("hat", 16, 0.5); draw(); return
  end
  local id = hit(x, y)
  if not id then
    if y >= Lay.frameY and y < Lay.frameY + Lay.frameH then id = "spin" else return end
  end
  note("hat", 16, 0.5)
  if id == "info" then state.info = 1
  elseif id == "minus" then state.betIdx = math.max(1, state.betIdx - 1); state.hl = {}; state.dim = false; betMsg()
  elseif id == "plus" then state.betIdx = math.min(#CONFIG.betLevels, state.betIdx + 1); state.hl = {}; state.dim = false; betMsg()
  elseif id == "max" then state.betIdx = #CONFIG.betLevels; state.hl = {}; state.dim = false; betMsg()
  elseif id == "spin" then
    doSpin(false)
    if state.free > 0 then runFreeGames() end
    return
  end
  draw()
end

------------------------------------------------------------------ LOOPS
local function gameLoop()
  applyPalette()
  layout()
  if W < 40 or H < 28 then error("Monitor too small - use at least 3 wide x 3 tall (5x4 recommended)", 0) end
  rerollVals()
  draw()
  local tmr = os.startTimer(0.5)
  while true do
    local e, a, b, c = os.pullEvent()
    if e == "timer" and a == tmr then
      state.tick = state.tick + 1
      if state.info == 0 then draw() end
      tmr = os.startTimer(0.5)
    elseif e == "monitor_touch" then
      onTouch(b, c)
      tmr = os.startTimer(0.5)        -- sleeps inside a spin eat the old timer
    elseif e == "monitor_resize" or e == "peripheral" then
      layout(); draw()
    elseif e == "credits_changed" then
      draw()
    end
  end
end

local function adminLoop()
  term.clear(); term.setCursorPos(1, 1)
  print("DRAGON LINK running on monitor")
  print("add <n> | set <n> | credits | jackpots | resetjp")
  print("demo hold | demo free | exit")
  while true do
    write("> ")
    local line = read() or ""
    local cmd, arg = line:match("^(%S*)%s*(%S*)")
    local n = tonumber(arg)
    if cmd == "add" and n then
      state.credits = state.credits + n; saveCredits()
      print("Credits: " .. state.credits); os.queueEvent("credits_changed")
    elseif cmd == "set" and n then
      state.credits = n; saveCredits()
      print("Credits: " .. state.credits); os.queueEvent("credits_changed")
    elseif cmd == "credits" then
      print("Credits: " .. state.credits)
    elseif cmd == "jackpots" then
      for i, bet in ipairs(CONFIG.betLevels) do
        local v = jpValues(i)
        print(("bet %d: MAJOR %s  GRAND %s"):format(bet, fmt(v.MAJOR), fmt(v.GRAND)))
      end
    elseif cmd == "resetjp" then
      state.jp = { major = {}, grand = {} }; saveJP()
      print("Progressive jackpots reset to seed"); os.queueEvent("credits_changed")
    elseif cmd == "demo" and (arg == "hold" or arg == "free") then
      state.force = arg
      print("Next paid spin will trigger " .. (arg == "hold" and "HOLD & SPIN" or "FREE GAMES"))
    elseif cmd == "exit" then
      return
    elseif cmd ~= "" then
      print("?  add <n> | set <n> | credits | jackpots | resetjp | demo hold|free | exit")
    end
  end
end

loadCredits()
loadJP()
parallel.waitForAny(gameLoop, adminLoop)
restorePalette()
mon.setBackgroundColor(colors.black); mon.clear()
print("Dragon Link stopped.")
