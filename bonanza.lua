--[[
  BONANZA  -  Megaways gold-mine slot for CC:Tweaked
  ---------------------------------------------------
  Setup:  computer + monitor wall 3 wide x 6 tall (57 x 81 at text scale 0.5).
          Speakers optional - every attached / networked speaker plays.
  Run:    bonanza
  Terminal commands while running:
          add <n> | set <n> | credits | demo free | demo cascade | exit

  Rules:
  * MEGAWAYS: 6 reels. Reels 1 and 6 show 2-7 symbols, reels 2-5 show 2-6
    plus one more from the TOP REEL above them. Ways = symbols on each reel
    multiplied together, up to 117,649.
  * Pays left to right on 3+ adjacent reels, any position.
  * DYNAMITE WILD only lands on the top reel and subs for all pay symbols.
  * CASCADES: winning symbols explode, everything above falls down, new
    symbols drop in (top reel slides in from the right). Repeats while wins
    keep landing.
  * FREE SPINS: 4 GOLD scatters anywhere (spells G-O-L-D) = 12 free spins,
    +5 for each extra. WIN MULTIPLIER starts at x1, goes up +1 after every
    cascade and never resets during the feature. 3+ scatters in free spins
    = +5 spins (+5 per extra).
  * Max win 5,000x bet. Designed return ~94.7% (1.5M-spin simulation,
    see sim_bonanza.lua).
]]

------------------------------------------------------------------ CONFIG
local CONFIG = {
  textScale     = 0.5,
  creditFile    = "bonanza_credits.txt",
  startCredits  = 5000,                  -- practice bankroll
  practiceMode  = true,                  -- refill to startCredits when you run dry
  betLevels     = {20, 40, 60, 100, 200, 400},
  freeSpins     = 12,                    -- for 4 GOLD scatters
  extraSpins    = 5,                     -- per extra scatter (and per retrigger step)
  maxWinX       = 5000,                  -- max win per spin/feature, x bet
  spinDelay     = 0.05,
}

------------------------------------------------------------------ MATH
-- pays are in thousandths of total bet, per way (3 / 4 / 5 / 6 of a kind)
local PAY = {
  RG = {320, 650, 1600, 3200},
  GG = {260, 520,  970, 1950},
  BG = {190, 390,  650, 1300},
  PG = {130, 260,  520,  970},
  A  = { 65, 130,  260,  520},
  K  = { 65, 130,  260,  520},
  Q  = { 65, 100,  190,  390},
  J  = { 32, 100,  160,  320},
  T  = { 32,  65,  130,  260},
  N  = { 32,  65,  130,  260},
}
local PAYING = {"RG", "GG", "BG", "PG", "A", "K", "Q", "J", "T", "N"}
local NAMES = { RG = "RED GEM", GG = "GREEN GEM", BG = "BLUE GEM", PG = "PURPLE GEM",
                A = "ACE", K = "KING", Q = "QUEEN", J = "JACK", T = "TEN", N = "NINE",
                WL = "DYNAMITE", SC = "GOLD" }

-- symbol weights per cell
local W_MAIN = { RG=4, GG=5, BG=6, PG=7, A=9, K=9, Q=10, J=10, T=11, N=11, SC=1.6 }
local W_TOP  = { RG=4, GG=5, BG=6, PG=7, A=9, K=9, Q=10, J=10, T=11, N=11, WL=4 }
local W_FREE = { RG=6, GG=7, BG=6, PG=7, A=9, K=9, Q=10, J=10, T=10, N=10, SC=1.2 }
local W_FTOP = { RG=6, GG=7, BG=6, PG=7, A=9, K=9, Q=10, J=10, T=10, N=10, WL=5 }
-- reel heights: reels 1 & 6 show 2-7, reels 2-5 show 2-6 (+1 from the top reel)
local H_OUTER = { [2]=1, [3]=2, [4]=3, [5]=3, [6]=2, [7]=1 }
local H_INNER = { [2]=1, [3]=2, [4]=3, [5]=3, [6]=2 }

local function picker(w)
  local list, total = {}, 0
  for _, k in ipairs({"RG","GG","BG","PG","A","K","Q","J","T","N","WL","SC"}) do
    if w[k] then total = total + w[k]; list[#list + 1] = {k, w[k]} end
  end
  return function(rand)
    local x = rand() * total
    for _, e in ipairs(list) do x = x - e[2]; if x < 0 then return e[1] end end
    return list[#list][1]
  end
end
local PICK = { main = picker(W_MAIN), top = picker(W_TOP), fmain = picker(W_FREE), ftop = picker(W_FTOP) }
local function pickH(t, rand)
  local total = 0
  for _, v in pairs(t) do total = total + v end
  local x = rand() * total
  for h = 2, 7 do if t[h] then x = x - t[h]; if x < 0 then return h end end end
  return 4
end

-- board: cols[r] = {sym,...} top->bottom, top[r] (r=2..5) = sym on the horizontal reel
local function newBoard(free, rand)
  local pm, pt = free and PICK.fmain or PICK.main, free and PICK.ftop or PICK.top
  local b = { cols = {}, top = {}, free = free }
  for r = 1, 6 do
    local h = pickH((r == 1 or r == 6) and H_OUTER or H_INNER, rand)
    b.cols[r] = {}
    for i = 1, h do b.cols[r][i] = pm(rand) end
  end
  for r = 2, 5 do b.top[r] = pt(rand) end
  return b
end

local function ways(b)
  local w = 1
  for r = 1, 6 do w = w * (#b.cols[r] + ((r >= 2 and r <= 5) and 1 or 0)) end
  return w
end

-- returns { units = sum in 1/1000 bet, wins = {...}, rem = set of "r:i" (i=0 top reel) }
local function evaluate(b)
  local res = { units = 0, wins = {}, rem = {} }
  for _, s in ipairs(PAYING) do
    local w, n, cells = 1, 0, {}
    for r = 1, 6 do
      local c = 0
      if r >= 2 and r <= 5 then
        local t = b.top[r]
        if t == s or t == "WL" then c = c + 1; cells[#cells + 1] = {r, 0} end
      end
      for i, sym in ipairs(b.cols[r]) do
        if sym == s then c = c + 1; cells[#cells + 1] = {r, i} end
      end
      if c == 0 then break end
      w, n = w * c, r
    end
    if n >= 3 then
      local keep = {}
      for _, c in ipairs(cells) do
        if c[1] <= n then keep[#keep + 1] = c; res.rem[c[1] .. ":" .. c[2]] = true end
      end
      local u = PAY[s][n - 2] * w
      res.wins[#res.wins + 1] = { sym = s, n = n, ways = w, units = u, cells = keep }
      res.units = res.units + u
    end
  end
  table.sort(res.wins, function(a, c) return a.units > c.units end)
  return res
end

-- remove winners: main reels drop down with new symbols from above,
-- the top reel slides left with new symbols entering from the right.
-- returns drop info per reel: list of {newIndex = oldIndex or nil}
local function cascade(b, rem, rand)
  local pm, pt = b.free and PICK.fmain or PICK.main, b.free and PICK.ftop or PICK.top
  local moves = {}
  for r = 1, 6 do
    local keep, from = {}, {}
    for i, s in ipairs(b.cols[r]) do
      if not rem[r .. ":" .. i] then keep[#keep + 1] = s; from[#from + 1] = i end
    end
    local k = #b.cols[r] - #keep
    local col, mv = {}, {}
    for i = 1, k do col[i] = pm(rand); mv[i] = false end
    for i, s in ipairs(keep) do col[k + i] = s; mv[k + i] = from[i] end
    b.cols[r] = col
    moves[r] = { new = k, from = mv }
  end
  local tk, tfrom = {}, {}
  for r = 2, 5 do if not rem[r .. ":0"] then tk[#tk + 1] = b.top[r]; tfrom[#tfrom + 1] = r end end
  local tmv = {}
  for i = 1, 4 do
    local r = i + 1
    if tk[i] then b.top[r] = tk[i]; tmv[r] = tfrom[i] else b.top[r] = pt(rand); tmv[r] = false end
  end
  moves.top = tmv
  return moves
end

local function scatters(b)
  local n, cells = 0, {}
  for r = 1, 6 do for i, s in ipairs(b.cols[r]) do
    if s == "SC" then n = n + 1; cells[#cells + 1] = {r, i} end
  end end
  return n, cells
end

local function spinsFor(sc, free)
  if free then return sc >= 3 and CONFIG.extraSpins * (sc - 2) or 0 end
  return sc >= 4 and CONFIG.freeSpins + CONFIG.extraSpins * (sc - 4) or 0
end

-- plays one full spin (all cascades) without graphics; used by the simulator.
-- returns the win in 1/1000 bet units
local function playSpin(free, mult, rand)
  local b = newBoard(free, rand)
  local total = 0
  while true do
    local res = evaluate(b)
    if #res.wins == 0 then break end
    total = total + res.units * mult
    if free then mult = mult + 1 end
    cascade(b, res.rem, rand)
  end
  local sc = scatters(b)
  return total, mult, sc
end

-- exported for testing outside Minecraft
if not term or not peripheral then
  return { CONFIG = CONFIG, playSpin = playSpin, spinsFor = spinsFor, newBoard = newBoard,
           evaluate = evaluate, cascade = cascade, ways = ways, scatters = scatters }
end

------------------------------------------------------------------ PERIPHERALS
local mon = peripheral.find("monitor")
if not mon then error("No monitor found - attach the monitor wall (3 wide x 6 tall)", 0) end
local speakers = { peripheral.find("speaker") }
math.randomseed(os.epoch("utc"))

local function note(inst, pitch, vol)
  for _, s in ipairs(speakers) do pcall(s.playNote, inst, vol or 1, pitch) end
end
local function sfx(name, vol, pitch)
  for _, s in ipairs(speakers) do pcall(s.playSound, name, vol or 1, pitch or 1) end
end
-- G major pentatonic-ish on note blocks, banjo for the gold-rush feel
local SCALE = {1, 3, 5, 8, 10, 13, 15, 17, 20, 22, 24}
local function tune(inst, seq, dt)
  for i, p in ipairs(seq) do note(inst, p, 1); if i < #seq then sleep(dt or 0.08) end end
end

------------------------------------------------------------------ STATE
local state = {
  credits = CONFIG.startCredits, betIdx = 1, lastWin = 0, carry = 0,
  msg = "TAP SPIN TO PLAY", mode = "base",
  board = nil, off = {}, vel = {}, delay = {}, topOff = {}, topVel = {}, topDelay = 0,
  spinning = {}, topSpinning = false, fake = {}, phase = 0,
  hlSet = nil, boom = nil, anticip = nil, landed = {},
  shownWays = 0, mult = 1, multFlash = 0,
  free = 0, freeTotal = 0, freeWin = 0, spinWin = 0,
  info = 0, tick = 0, force = nil,
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
local function curBet() return CONFIG.betLevels[state.betIdx] end

-- converts a win in 1/1000-bet units to whole credits, carrying the fraction
local function unitsToCredits(units)
  local total = units * curBet() + state.carry
  local c = math.floor(total / 1000)
  state.carry = total - c * 1000
  return c
end

local function fmt(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return out
end

------------------------------------------------------------------ SCREEN BUFFER
local W, H
local bt, bf, bb = {}, {}, {}
local CLIP = nil   -- {x, y, w, h} or nil

local function clear(bg)
  for y = 1, H do
    bt[y], bf[y], bb[y] = {}, {}, {}
    for x = 1, W do bt[y][x] = " "; bf[y][x] = "0"; bb[y][x] = bg end
  end
end
local function put(x, y, ch, fg, bg)
  if x < 1 or x > W or y < 1 or y > H then return end
  if CLIP and (x < CLIP[1] or x >= CLIP[1] + CLIP[3] or y < CLIP[2] or y >= CLIP[2] + CLIP[4]) then return end
  bt[y][x] = ch
  if fg then bf[y][x] = fg end
  if bg then bb[y][x] = bg end
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
  [","]={"...","...","...",".X.","X.."}, ["+"]={"...",".X.","XXX",".X.","..."},
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
  Lay.bigTitle = H >= 60 and W >= bigW("BONANZA", 2) + 2
  Lay.titleH = Lay.bigTitle and 7 or 3
  Lay.infoY  = Lay.titleH + 1
  Lay.infoH  = Lay.bigTitle and 6 or 2
  Lay.panelH = 8
  Lay.panelY = H - Lay.panelH + 1
  Lay.frameY = Lay.infoY + Lay.infoH
  Lay.frameH = Lay.panelY - 1 - Lay.frameY
  Lay.cellW  = math.max(5, math.floor((W - 2 - 2 - 5) / 6))
  Lay.frameW = 6 * Lay.cellW + 5 + 2
  Lay.frameX = math.floor((W - Lay.frameW) / 2) + 1
  Lay.innerY = Lay.frameY + 1
  Lay.innerH = Lay.frameH - 2
  Lay.topH   = math.max(5, math.min(9, math.floor(Lay.innerH / 8)))
  Lay.mainY  = Lay.innerY + Lay.topH + 1
  Lay.mainH  = Lay.innerH - Lay.topH - 1
end
local function colX(r) return Lay.frameX + 1 + (r - 1) * (Lay.cellW + 1) end
local function colArea(r)
  if r == 1 or r == 6 then return colX(r), Lay.innerY, Lay.innerH end
  return colX(r), Lay.mainY, Lay.mainH
end
-- split a column of height A into n cells with 1-row gaps: {dy, h}
local function colCells(A, n)
  local avail = A - (n - 1)
  local base = math.floor(avail / n)
  local extra = avail - base * n
  local t, y = {}, 0
  for i = 1, n do
    local h = base + (i <= extra and 1 or 0)
    t[i] = {y, h}
    y = y + h + 1
  end
  return t
end

------------------------------------------------------------------ SYMBOL ART (8x5)
local ART = {
  RG = { ".e0eeee.", "eeeeeeee", ".eeeeee.", "..eeee..", "...ee..." },
  GG = { ".dddddd.", "d5dddddd", "dddddddd", "dddddddd", ".dddddd." },
  BG = { "..bbbb..", ".b3bbbb.", "bbbbbbbb", ".bbbbbb.", "..bbbb.." },
  PG = { "...aa...", "..a2aa..", ".aaaaaa.", "aaaaaaaa", ".aaaaaa." },
  WL = { ".....4.1", "....8.4.", "eeeeee..", "e0000e..", "eeeeee.." },
  SC = { "..4444..", ".444444.", "44444444", ".444444.", "..4444.." },
}
local ROYAL = { A = {"A", "1"}, K = {"K", "3"}, Q = {"Q", "6"}, J = {"J", "5"}, T = {"10", "9"}, N = {"9", "8"} }
local SHORT = { RG = "RED", GG = "GRN", BG = "BLU", PG = "PUR", WL = "TNT", SC = "GOLD",
                A = "A", K = "K", Q = "Q", J = "J", T = "10", N = "9" }
local SYMCOL = { RG = "e", GG = "d", BG = "b", PG = "a", WL = "e", SC = "4",
                 A = "1", K = "3", Q = "6", J = "5", T = "9", N = "8" }
local BOOM = { "4", "1", "e", "0", "1" }

local function drawArt(art, ox, oy, pw, ph, dim)
  for ry = 1, #art do
    local line = art[ry]
    for rx = 1, #line do
      local c = line:sub(rx, rx)
      if c ~= "." then
        if dim then c = "7" end
        fill(ox + (rx - 1) * pw, oy + (ry - 1) * ph, pw, ph, c)
      end
    end
  end
end

-- draws one symbol in the rect (clipping is handled by CLIP)
local function drawSym(sym, x, y, w, h, dim, letter, boom)
  if boom then
    for yy = y, y + h - 1 do for xx = x, x + w - 1 do
      local c = BOOM[math.random(#BOOM)]
      put(xx, yy, math.random() < 0.3 and "*" or " ", "0", c)
    end end
    return
  end
  fill(x, y, w, h, "f")
  if not sym then return end
  if h < 5 or w < 7 then
    ctext(x, y + math.floor(h / 2), w, SHORT[sym], dim and "7" or SYMCOL[sym], "f")
    return
  end
  if ROYAL[sym] then
    local s, col = ROYAL[sym][1], ROYAL[sym][2]
    local pw = math.max(1, math.floor((w - 1) / bigW(s, 1)))
    if pw > 2 then pw = 2 end
    local ph = (h >= 12) and 2 or 1
    local tx = x + math.floor((w - bigW(s, pw)) / 2)
    local ty = y + math.floor((h - 5 * ph) / 2)
    if not dim then bigText(tx + 1, ty, s, "7", pw, ph) end
    bigText(tx, ty, s, dim and "7" or col, pw, ph)
    return
  end
  local art = ART[sym]
  local pw = math.max(1, math.floor(w / 8))
  local ph = (h >= 12) and 2 or 1
  local label = (sym == "WL" and h >= 5 * ph + 2) and "WILD" or nil
  local ah = 5 * ph + (label and 1 or 0)
  local ox = x + math.floor((w - 8 * pw) / 2)
  local oy = y + math.floor((h - ah) / 2)
  drawArt(art, ox, oy, pw, ph, dim)
  if label then ctext(x, oy + 5 * ph, w, label, dim and "7" or "4", "f") end
  if sym == "SC" and letter then
    ctext(x, oy + 2 * ph, w, letter, "f", dim and "7" or "4")
  end
end

------------------------------------------------------------------ DRAW
local function drawTitle()
  fill(1, 1, W, Lay.titleH, "c")
  for x = 1, W do
    local r = math.random()
    put(x, 1, " ", nil, r < 0.12 and "4" or (r < 0.2 and "1" or "7"))
    if Lay.titleH > 3 then
      r = math.random()
      put(x, Lay.titleH, " ", nil, r < 0.12 and "4" or (r < 0.2 and "1" or "7"))
    end
  end
  local t = state.mode == "free" and "FREE SPINS" or "BONANZA"
  if Lay.bigTitle then
    local pw = bigW(t, 2) <= W - 2 and 2 or 1
    bigCenter(1, 2, W, t, "4", "f", pw, 1)
  else
    ctext(1, 2, W, "$ " .. t .. " $", "4", "c")
  end
end

local function drawInfo()
  local y, h = Lay.infoY, Lay.infoH
  fill(1, y, W, h, "f")
  local ways = fmt(state.shownWays)
  if Lay.bigTitle then
    local half = math.floor(W / 2)
    if state.mode == "free" then
      ctext(1, y, half, "WAYS", "8", "f")
      bigCenter(1, y + 1, half, ways, "4", nil)
      local mc = (state.multFlash > 0 and state.tick % 2 == 0) and "0" or "1"
      ctext(half + 1, y, W - half, "WIN MULTIPLIER", "8", "f")
      bigCenter(half + 1, y + 1, W - half, "X" .. state.mult, mc, nil)
    else
      ctext(1, y, W, "MEGAWAYS", "8", "f")
      bigCenter(1, y + 1, W, ways, "4", "c")
    end
  else
    local s = ways .. " WAYS"
    if state.mode == "free" then s = s .. "   MULTIPLIER X" .. state.mult end
    ctext(1, y, W, s, "4", "f")
  end
end

local function scatterLetters()
  local map, k = {}, 0
  if not state.board then return map end
  for r = 1, 6 do for i, s in ipairs(state.board.cols[r]) do
    if s == "SC" then
      k = k + 1
      map[r .. ":" .. i] = k <= 4 and ("GOLD"):sub(k, k) or "+"
    end
  end end
  return map
end

local function drawSpinCol(x, y0, w, A, r)
  local hs = math.max(5, math.floor((A - 3) / 4))
  local step = hs + 1
  local fake = state.fake[r]
  local shift = math.floor(state.phase / step)
  local sub = state.phase % step
  for i = 0, math.floor(A / step) + 1 do
    local sym = fake[((i - shift) % #fake) + 1]
    drawSym(sym, x, y0 + (i - 1) * step + sub, w, hs, false)
  end
end

local function drawReels()
  local fc = state.mode == "free" and "4" or "7"
  fill(Lay.frameX, Lay.frameY, Lay.frameW, Lay.frameH, fc)
  fill(Lay.frameX + 1, Lay.innerY, Lay.frameW - 2, Lay.innerH, "c")
  local b = state.board
  local letters = scatterLetters()
  local w = Lay.cellW
  for r = 1, 6 do
    local x, y0, A = colArea(r)
    CLIP = { x, y0, w, A }
    if state.spinning[r] or not b then
      drawSpinCol(x, y0, w, A, r)
    else
      local cells = colCells(A, #b.cols[r])
      for i, s in ipairs(b.cols[r]) do
        local key = r .. ":" .. i
        local off = (state.off[r] and state.off[r][i]) or 0
        local dim = state.hlSet and not state.hlSet[key]
        drawSym(s, x, y0 + cells[i][1] + off, w, cells[i][2], dim, letters[key], state.boom and state.boom[key])
      end
    end
    CLIP = nil
  end
  -- horizontal top reel above reels 2-5 (moves right to left)
  local tx0 = colX(2)
  local tw = 4 * w + 3
  fill(tx0 - 1, Lay.innerY, tw + 2, Lay.topH, "8")
  CLIP = { tx0, Lay.innerY, tw, Lay.topH }
  for r = 2, 5 do
    if state.topSpinning or not b then
      local sym = state.fake[r][((r + math.floor(state.phase / 3)) % #state.fake[r]) + 1]
      drawSym(sym, colX(r) - (state.phase % (w + 1)), Lay.innerY, w, Lay.topH, false)
      drawSym(state.fake[r][1], colX(r) - (state.phase % (w + 1)) + w + 1, Lay.innerY, w, Lay.topH, false)
    else
      local key = r .. ":0"
      local dim = state.hlSet and not state.hlSet[key]
      drawSym(b.top[r], colX(r) + (state.topOff[r] or 0), Lay.innerY, w, Lay.topH, dim, nil,
              state.boom and state.boom[key])
    end
  end
  CLIP = nil
  -- anticipation: flashing border around the next reel to land
  if state.anticip then
    local x, y0, A = colArea(state.anticip)
    local col = ({"4", "1", "e", "0"})[(state.tick % 4) + 1]
    for yy = y0, y0 + A - 1 do put(x - 1, yy, " ", nil, col); put(x + w, yy, " ", nil, col) end
  end
end

local function drawPanel()
  local y = Lay.panelY
  fill(1, y - 1, W, Lay.panelH + 1, "f")
  local bet = curBet()
  local boxes
  if state.mode == "free" then
    boxes = { {"CREDITS", fmt(state.credits), "4"}, {"SPINS LEFT", tostring(state.free), "b"},
              {"FREE WIN", fmt(state.freeWin), "5"} }
  else
    boxes = { {"CREDITS", fmt(state.credits), "4"}, {"BET", fmt(bet), "0"},
              {"WIN", fmt(state.lastWin), "5"} }
  end
  local bw = math.floor(W / #boxes)
  for i, bx in ipairs(boxes) do
    local x = 1 + (i - 1) * bw
    ctext(x, y, bw, bx[1], "8", "f")
    ctext(x, y + 1, bw, bx[2], bx[3], "f")
  end
  ctext(1, y + 2, W, state.msg or "", state.mode ~= "base" and "4" or "0", "f")
  local busy = state.busy or state.mode ~= "base"
  local btns = {
    {"info", "INFO", "7", 1}, {"minus", "BET-", "b", 1}, {"plus", "BET+", "b", 1},
    {"max", "MAX", "a", 1}, {"spin", busy and "..." or "SPIN", busy and "7" or "d", 2},
  }
  local total = 0
  for _, b in ipairs(btns) do total = total + b[4] end
  local unit = (W - 2 - (#btns - 1)) / total
  local x = 2
  Lay.buttons = {}
  for i, b in ipairs(btns) do
    local bw2 = (i == #btns) and (W - x) or math.floor(unit * b[4])
    local c = (busy and b[1] ~= "spin") and "7" or b[3]
    fill(x, y + 4, bw2, 3, c)
    ctext(x, y + 5, bw2, b[2], "0", c)
    Lay.buttons[#Lay.buttons + 1] = { id = b[1], x = x, y = y + 4, w = bw2, h = 3 }
    x = x + bw2 + 1
  end
end

local INFO_PAGES
local function drawInfoPage()
  clear("f")
  local lines = INFO_PAGES[state.info]()
  local y0 = math.max(1, math.floor((H - #lines) / 2))
  for i, l in ipairs(lines) do ctext(1, y0 + i - 1, W, l[1], l[2], "f") end
  flush()
end

local function render()
  clear("c")
  drawTitle()
  drawInfo()
  drawReels()
  drawPanel()
end
local function draw()
  if state.info > 0 then return drawInfoPage() end
  render(); flush()
end

local function payStr(units)
  local v = units * curBet() / 1000
  if v >= 10 or v == math.floor(v) then return fmt(v) end
  return string.format("%.1f", v)
end

INFO_PAGES = {
  function()
    local t = {
      {"PAYS AT BET " .. curBet() .. " (PER WAY)", "4"}, {"", "0"},
      {string.format("%-10s%6s%6s%6s%6s", "", "3", "4", "5", "6"), "8"},
    }
    for _, s in ipairs(PAYING) do
      local p = PAY[s]
      t[#t + 1] = { string.format("%-10s%6s%6s%6s%6s", NAMES[s], payStr(p[1]), payStr(p[2]),
                    payStr(p[3]), payStr(p[4])), SYMCOL[s] }
    end
    t[#t + 1] = {"", "0"}
    t[#t + 1] = {"Wins x ways: 2 on reel 1 x 3 on", "8"}
    t[#t + 1] = {"reel 2 x 1 on reel 3 = 6 ways", "8"}
    t[#t + 1] = {"", "0"}
    t[#t + 1] = {"- TAP FOR PAGE 2 -", "8"}
    return t
  end,
  function()
    return {
      {"MEGAWAYS & CASCADES", "4"}, {"", "0"},
      {"Reels 1 and 6 show 2-7 symbols", "0"},
      {"Reels 2-5 show 2-6, plus 1 more", "0"},
      {"from the TOP REEL above them", "0"},
      {"Up to 117,649 ways to win!", "4"},
      {"", "0"},
      {"Pays left to right, 3+ adjacent reels", "0"},
      {"DYNAMITE WILD lands on the top reel", "e"},
      {"and subs for every pay symbol", "e"},
      {"", "0"},
      {"CASCADES: winning symbols blow up,", "1"},
      {"the rest fall and new ones drop in.", "1"},
      {"Keeps going while you keep winning.", "1"},
      {"", "0"},
      {"- TAP FOR PAGE 3 -", "8"},
    }
  end,
  function()
    return {
      {"FREE SPINS", "4"}, {"", "0"},
      {"Land G-O-L-D: 4 gold scatters", "4"},
      {"anywhere = " .. CONFIG.freeSpins .. " FREE SPINS", "4"},
      {"+" .. CONFIG.extraSpins .. " spins for each extra scatter", "0"},
      {"", "0"},
      {"WIN MULTIPLIER starts at X1", "1"},
      {"+1 after EVERY cascade", "1"},
      {"and it NEVER resets during", "1"},
      {"the free spins!", "1"},
      {"", "0"},
      {"3 scatters in free spins = +" .. CONFIG.extraSpins, "0"},
      {"(+" .. CONFIG.extraSpins .. " more for each extra)", "0"},
      {"", "0"},
      {"Max win " .. fmt(CONFIG.maxWinX) .. "x bet", "8"},
      {"", "0"},
      {"- TAP TO RETURN -", "8"},
    }
  end,
}

------------------------------------------------------------------ ANIMATION
local function waitTap(t)
  local tm = os.startTimer(t)
  while true do
    local e, a = os.pullEvent()
    if e == "timer" and a == tm then return false end
    if e == "monitor_touch" then return true end
  end
end

local function newFake()
  local syms = {"RG","GG","BG","PG","A","K","Q","J","T","N","SC"}
  for r = 1, 6 do
    state.fake[r] = {}
    for i = 1, 12 do state.fake[r][i] = syms[math.random(#syms)] end
  end
end

-- gravity: moves every offset toward 0; handles delays (reels still spinning).
-- onLand(r) fires once when a reel's cells all settle.
local function settle(onLand, topDelay)
  local topPending = topDelay ~= nil
  local topWait = topDelay or 0
  local landedTop = false
  while true do
    local busy = false
    for r = 1, 6 do
      if state.delay[r] and state.delay[r] > 0 then
        state.delay[r] = state.delay[r] - 1
        busy = true
        if state.delay[r] == 0 then state.spinning[r] = false end
      else
        local moving = false
        for i, o in pairs(state.off[r] or {}) do
          if o < 0 then
            state.vel[r][i] = (state.vel[r][i] or 0) + 2
            local n = o + state.vel[r][i]
            if n >= 0 then n = 0; state.vel[r][i] = 0 end
            state.off[r][i] = n
            if n < 0 then moving = true end
          end
        end
        if moving then busy = true
        elseif state.landing and state.landing[r] then
          state.landing[r] = nil
          if onLand then onLand(r) end
        end
      end
    end
    if topPending then
      if topWait > 0 then topWait = topWait - 1; busy = true
      else
        state.topSpinning = false
        local mv = false
        for r = 2, 5 do
          local o = state.topOff[r] or 0
          if o > 0 then
            state.topVel[r] = (state.topVel[r] or 0) + 2
            local n = o - state.topVel[r]
            if n <= 0 then n = 0; state.topVel[r] = 0 end
            state.topOff[r] = n
            if n > 0 then mv = true end
          end
        end
        if mv then busy = true elseif not landedTop then
          landedTop = true
          if onLand then onLand(0) end
        end
      end
    end
    -- the next reel still spinning gets the anticipation frame
    if state.anticipOn then
      state.anticip = nil
      for r = 1, 6 do if state.spinning[r] then state.anticip = r; break end end
      if state.anticip and state.tick % 2 == 0 then note("bass", 2 + (state.tick % 8), 0.8) end
    end
    state.phase = state.phase + 3
    state.tick = state.tick + 1
    draw()
    if not busy then break end
    if state.anticip then note("hat", 18, 0.3) elseif state.tick % 3 == 0 then note("hat", 12, 0.25) end
    sleep(CONFIG.spinDelay)
  end
  state.anticip, state.anticipOn = nil, false
end

-- all cells of reel r start just above the window
local function dropIn(r)
  local _, _, A = colArea(r)
  state.off[r], state.vel[r] = {}, {}
  for i = 1, #state.board.cols[r] do state.off[r][i] = -(A + 1); state.vel[r][i] = 0 end
end

-- ways number rolls toward the real value
local function tickWays(target)
  local start = state.shownWays
  for i = 1, 8 do
    state.shownWays = math.floor(start + (target - start) * i / 8)
    if i % 2 == 0 then note("bit", 8 + i, 0.5) end
    draw(); sleep(0.03)
  end
  state.shownWays = target
end

local function explode(rem, chain)
  state.boom = rem
  sfx("minecraft:entity.generic.explode", 0.45, 1.1 + math.min(chain, 8) * 0.05)
  for _ = 1, 4 do state.tick = state.tick + 1; draw(); sleep(0.06) end
  state.boom = nil
end

-- winners blow up, survivors fall, new symbols tumble in from above / the right
local function cascadeAnim(res)
  local b = state.board
  local old = {}
  for r = 1, 6 do old[r] = #b.cols[r] end
  local moves = cascade(b, res.rem, math.random)
  for r = 1, 6 do
    local _, _, A = colArea(r)
    local cells = colCells(A, #b.cols[r])
    local mv = moves[r]
    state.off[r], state.vel[r] = {}, {}
    local newBlock = mv.new > 0 and (cells[mv.new][1] + cells[mv.new][2] + 1) or 0
    for i = 1, #b.cols[r] do
      local from = mv.from[i]
      if from then
        state.off[r][i] = cells[from][1] - cells[i][1]
      else
        state.off[r][i] = -newBlock - 1
      end
      state.vel[r][i] = 0
    end
  end
  local k = 0
  for r = 2, 5 do
    local from = moves.top[r]
    if from then state.topOff[r] = (from - r) * (Lay.cellW + 1)
    else k = k + 1; state.topOff[r] = (6 - r + k) * (Lay.cellW + 1) end
    state.topVel[r] = 0
  end
  sfx("minecraft:block.gravel.fall", 0.8, 0.9)
  settle(nil, 0)
  note("basedrum", 4, 1)
end

-- coin/gold shower with rolling number
local function bigWinShow(amount, bet)
  local x = amount / bet
  if x < 10 then return end
  local tier = (x >= 100 and "EPIC WIN") or (x >= 50 and "MEGA WIN") or (x >= 25 and "HUGE WIN") or "BIG WIN"
  local fx, fy, fw, fh = Lay.frameX, Lay.frameY, Lay.frameW, Lay.frameH
  local coins = {}
  local frames = (x >= 50 and 90) or (x >= 25 and 70) or 50
  local skipped = false
  sfx("minecraft:ui.toast.challenge_complete", 1, 1)
  for f = 1, frames do
    for _ = 1, 3 do coins[#coins + 1] = { x = fx + math.random(0, fw - 2), y = fy, v = math.random(1, 2), s = math.random(0, 1) } end
    state.tick = state.tick + 1
    render()
    for i = #coins, 1, -1 do
      local c = coins[i]
      c.y = c.y + c.v; c.s = 1 - c.s
      if c.y >= fy + fh then table.remove(coins, i)
      else put(c.x, c.y, " ", nil, c.s == 0 and "4" or "1"); put(c.x + 1, c.y, " ", nil, c.s == 0 and "1" or "4") end
    end
    local shown = skipped and amount or math.floor(amount * math.min(1, f / (frames * 0.7)))
    local pw = (bigW(tier, 2) <= fw - 4) and 2 or 1
    local cy = fy + math.floor(fh / 2) - 7
    fill(fx + 1, cy - 2, fw - 2, 17, (f % 4 < 2) and "4" or "1")
    fill(fx + 2, cy - 1, fw - 4, 15, "f")
    bigCenter(fx, cy, fw, tier, (f % 4 < 2) and "4" or "0", "c", pw, 1)
    local num = fmt(shown)
    if bigW(num, 1) <= fw - 4 then bigCenter(fx, cy + 7, fw, num, "0", "7", 1, 1)
    else ctext(fx, cy + 8, fw, num, "0", "f") end
    state.msg = tier .. "!  " .. fmt(shown)
    flush()
    if not skipped and f % 2 == 0 then sfx("minecraft:entity.experience_orb.pickup", 0.6, 0.6 + (f % 20) / 20) end
    if f % 4 == 0 then note("banjo", SCALE[((f / 4) % #SCALE) + 1], 1) end
    if waitTap(0.05) then if skipped then break end; skipped = true end
  end
  sfx("minecraft:entity.player.levelup", 1, 1)
end

-- "FREE SPINS" gold-rush banner
local function goldShow(title, sub, frames)
  local fx, fy, fw, fh = Lay.frameX, Lay.frameY, Lay.frameW, Lay.frameH
  local nuggets = {}
  sfx("minecraft:ui.toast.challenge_complete", 1, 1)
  for f = 1, frames do
    for _ = 1, 4 do nuggets[#nuggets + 1] = { x = fx + math.random(0, fw - 3), y = fy, v = math.random(1, 3) } end
    state.tick = state.tick + 1
    render()
    for i = #nuggets, 1, -1 do
      local n = nuggets[i]; n.y = n.y + n.v
      if n.y >= fy + fh then table.remove(nuggets, i)
      else fill(n.x, n.y, 2, 1, "4"); put(n.x + 2, n.y, " ", nil, "1") end
    end
    local cy = fy + math.floor(fh / 2) - 7
    fill(fx + 1, cy - 2, fw - 2, 17, (f % 4 < 2) and "4" or "1")
    fill(fx + 2, cy - 1, fw - 4, 15, "c")
    local pw = (bigW(title, 2) <= fw - 6) and 2 or 1
    bigCenter(fx, cy, fw, title, "4", "f", pw, 1)
    if bigW(sub, 1) <= fw - 4 then bigCenter(fx, cy + 7, fw, sub, "0", "f", 1, 1)
    else ctext(fx, cy + 8, fw, sub, "0", "c") end
    flush()
    if f % 3 == 0 then note("banjo", SCALE[((f / 3) % #SCALE) + 1], 1) end
    if f % 8 == 1 then sfx("minecraft:block.amethyst_block.chime", 1, 0.8 + (f % 16) / 20) end
    sleep(0.05)
  end
end

local function rollUp(field, target)
  local start = state[field]
  local steps = math.min(16, math.max(1, math.floor(target / 5)))
  for i = 1, steps do
    state[field] = start + math.floor(target * i / steps)
    if i % 2 == 0 then note("bit", 10 + (i % 12), 0.6) end
    draw()
    if waitTap(0.03) then state[field] = start + target; draw(); return end
  end
end

------------------------------------------------------------------ SPIN
local function findForced(want)
  for i = 1, 100000 do
    if i % 2000 == 0 then os.queueEvent("bonanza_yield"); os.pullEvent("bonanza_yield") end
    local b = newBoard(false, math.random)
    if want == "free" and scatters(b) >= 4 then return b end
    if want == "cascade" then
      local res = evaluate(b)
      if res.units >= 2000 then return b end
    end
  end
end

local function describe(w)
  return NAMES[w.sym] .. " x" .. w.n .. "  " .. fmt(w.ways) .. " WAY" .. (w.ways > 1 and "S" or "")
end

-- one paid or free spin, including every cascade
local function doSpin(isFree)
  local bet = curBet()
  if not isFree then
    if state.credits < bet and CONFIG.practiceMode then
      state.credits = CONFIG.startCredits; saveCredits()
      state.msg = "PRACTICE MODE - REFILLED TO " .. fmt(CONFIG.startCredits)
      sfx("minecraft:entity.villager.yes", 1, 1); draw(); return
    elseif state.credits < bet then
      state.msg = "NOT ENOUGH CREDITS - SEE ATTENDANT"
      sfx("minecraft:entity.villager.no", 1, 1); draw(); return
    end
    state.credits = state.credits - bet; saveCredits()
    state.lastWin = 0
  end
  state.busy = true
  state.hlSet = nil
  state.spinWin = 0
  state.msg = isFree and ("FREE SPIN " .. (state.freeTotal - state.free) .. " OF " .. state.freeTotal) or "GOOD LUCK!"

  -- pick the result first, then animate toward it
  local b
  if state.force and not isFree then b = findForced(state.force); state.force = nil end
  b = b or newBoard(isFree, math.random)
  newFake()
  -- old symbols fall out the bottom
  if state.board then
    for r = 1, 6 do
      state.off[r], state.vel[r] = {}, {}
      for i = 1, #state.board.cols[r] do state.off[r][i] = 0; state.vel[r][i] = 0 end
    end
    for f = 1, 5 do
      for r = 1, 6 do
        for i in pairs(state.off[r]) do state.off[r][i] = state.off[r][i] + f * 3 end
      end
      state.phase = state.phase + 3; draw(); sleep(0.05)
    end
  end
  sfx("minecraft:block.piston.extend", 0.6, 1.2)
  state.board = b
  state.shownWays = 0
  state.landing, state.topSpinning = {}, true
  local scLanded, extended = 0, false
  for r = 1, 6 do
    state.spinning[r] = true
    state.delay[r] = 6 + (r - 1) * 4
    state.landing[r] = true
    dropIn(r)
  end
  for r = 2, 5 do state.topOff[r] = (7 - r) * (Lay.cellW + 1); state.topVel[r] = 0 end
  local waysSoFar = 1
  settle(function(r)
    if r == 0 then
      sfx("minecraft:block.chain.place", 0.8, 1)
      for rr = 2, 5 do
        if b.top[rr] == "WL" then sfx("minecraft:entity.tnt.primed", 0.6, 1.2) end
      end
      state.shownWays = ways(b)
      return
    end
    note("basedrum", 5, 1)
    sfx("minecraft:block.stone.place", 0.7, 0.8 + r * 0.06)
    local n = 0
    for _, s in ipairs(b.cols[r]) do if s == "SC" then n = n + 1 end end
    if n > 0 then
      scLanded = scLanded + n
      sfx("minecraft:block.amethyst_block.chime", 1, 0.8 + scLanded * 0.15)
      note("bell", SCALE[math.min(#SCALE, 4 + scLanded)], 1)
    end
    waysSoFar = waysSoFar * (#b.cols[r] + ((r >= 2 and r <= 5) and 1 or 0))
    state.shownWays = waysSoFar
    -- 3 gold showing with reels still to land: slow the rest down
    if not extended and scLanded >= (isFree and 2 or 3) and r < 6 then
      extended = true
      state.anticipOn = true
      local add = 0
      for rr = r + 1, 6 do add = add + 12; state.delay[rr] = state.delay[rr] + add end
      sfx("minecraft:block.bell.resonate", 0.7, 1)
    end
  end, 6 + 4 * 4)
  tickWays(ways(b))
  if ways(b) >= 50000 then
    state.msg = fmt(ways(b)) .. " WAYS!"
    tune("pling", {13, 17, 20, 24}, 0.06)
  end

  -- cascades
  local chain = 0
  local capC = CONFIG.maxWinX * bet
  while true do
    local res = evaluate(b)
    if #res.wins == 0 then break end
    chain = chain + 1
    local mult = isFree and state.mult or 1
    local credits = unitsToCredits(res.units * mult)
    local room = capC - (isFree and state.freeWin or state.spinWin)
    if credits >= room then credits = math.max(0, room) end
    state.spinWin = state.spinWin + credits
    state.credits = state.credits + credits; saveCredits()
    if isFree then state.freeWin = state.freeWin + credits else state.lastWin = state.spinWin end

    -- show the win
    state.hlSet = res.rem
    local best = res.wins[1]
    state.msg = (#res.wins == 1 and describe(best) or (#res.wins .. " WINS")) ..
                "  +" .. fmt(credits) .. (mult > 1 and ("  (X" .. mult .. ")") or "")
    tune("banjo", chain == 1 and {13, 17, 20} or {17, 20, 24}, 0.06)
    for f = 1, 6 do
      state.tick = state.tick + 1
      state.hlSet = (f % 2 == 1) and res.rem or {}
      draw()
      if waitTap(0.12) then break end
    end
    state.hlSet = nil
    explode(res.rem, chain)
    cascadeAnim(res)
    if isFree then
      state.mult = state.mult + 1
      state.multFlash = 6
      note("pling", SCALE[math.min(#SCALE, 3 + (state.mult % 8))], 1)
      sfx("minecraft:entity.experience_orb.pickup", 1, 1.5)
      state.msg = "MULTIPLIER UP!  X" .. state.mult
      for _ = 1, 6 do state.tick = state.tick + 1; state.multFlash = state.multFlash - 1; draw(); sleep(0.05) end
    else
      state.msg = "CASCADE " .. chain .. "  -  WIN " .. fmt(state.spinWin)
    end
    state.shownWays = ways(b)
    draw()
    if (isFree and state.freeWin or state.spinWin) >= capC then state.msg = "MAX WIN REACHED!"; break end
  end

  if state.spinWin > 0 then
    state.msg = (chain > 1 and (chain .. " CASCADES  -  ") or "") .. "WIN " .. fmt(state.spinWin) .. "!"
    if not isFree and state.spinWin >= bet * 10 then bigWinShow(state.spinWin, bet)
    else tune("bell", {13, 17, 20, 25 - 1}, 0.06) end
    state.msg = (chain > 1 and (chain .. " CASCADES  -  ") or "") .. "WIN " .. fmt(state.spinWin) .. "!"
  elseif not isFree then
    state.msg = "TAP SPIN TO PLAY"
  end

  -- G-O-L-D scatters
  local sc, cells = scatters(b)
  local award = spinsFor(sc, isFree)
  if award > 0 then
    state.hlSet = {}
    for _, c in ipairs(cells) do state.hlSet[c[1] .. ":" .. c[2]] = true end
    for i = 1, 8 do
      state.tick = state.tick + 1; draw()
      note("bell", SCALE[math.min(#SCALE, i + 2)], 1)
      if i % 2 == 0 then sfx("minecraft:block.amethyst_block.chime", 1, 1 + i * 0.05) end
      sleep(0.1)
    end
    state.hlSet = nil
    if isFree then
      state.free = state.free + award
      state.freeTotal = state.freeTotal + award
      state.msg = "RETRIGGER! +" .. award .. " FREE SPINS"
      sfx("minecraft:entity.player.levelup", 1, 1.2)
      goldShow("+" .. award, "FREE SPINS", 30)
    else
      state.free, state.freeTotal, state.freeWin, state.mult = award, award, 0, 1
      state.msg = award .. " FREE SPINS!"
    end
  end
  state.busy = false
  draw()
end

local function runFreeSpins()
  local bet = curBet()
  state.mode = "free"
  state.mult = 1
  goldShow("GOLD RUSH", state.free .. " FREE SPINS", 45)
  state.msg = "MULTIPLIER GROWS WITH EVERY CASCADE!"
  draw()
  tune("banjo", {1, 5, 8, 13, 8, 13, 17, 20}, 0.09)
  while state.free > 0 do
    sleep(0.7)
    state.free = state.free - 1
    doSpin(true)
    if state.freeWin >= CONFIG.maxWinX * bet then state.free = 0 end
  end
  sleep(0.8)
  local won = state.freeWin
  state.mode = "base"
  state.lastWin = won
  state.msg = "FREE SPINS PAID " .. fmt(won) .. "!"
  draw()
  if won >= bet * 10 then bigWinShow(won, bet) else tune("bell", {13, 17, 20}, 0.08) end
  state.msg = "FREE SPINS PAID " .. fmt(won) .. "  (FINAL X" .. state.mult .. ")"
  state.freeWin, state.freeTotal, state.mult = 0, 0, 1
  draw()
end

------------------------------------------------------------------ INPUT
local function hit(x, y)
  for _, b in ipairs(Lay.buttons or {}) do
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b.id end
  end
end

local function onTouch(x, y)
  if state.info > 0 then
    state.info = state.info + 1
    if state.info > #INFO_PAGES then state.info = 0 end
    sfx("minecraft:item.book.page_turn", 1, 1); draw(); return
  end
  local id = hit(x, y)
  if not id then
    if y >= Lay.frameY and y < Lay.frameY + Lay.frameH then id = "spin" else return end
  end
  note("hat", 16, 0.5)
  if id == "info" then state.info = 1; sfx("minecraft:item.book.page_turn", 1, 1)
  elseif id == "minus" or id == "plus" or id == "max" then
    if id == "minus" then state.betIdx = math.max(1, state.betIdx - 1)
    elseif id == "plus" then state.betIdx = math.min(#CONFIG.betLevels, state.betIdx + 1)
    else state.betIdx = #CONFIG.betLevels end
    note("bit", 6 + state.betIdx * 2, 0.8)
    state.msg = "BET " .. fmt(curBet())
  elseif id == "spin" then
    doSpin(false)
    if state.free > 0 then runFreeSpins() end
    return
  end
  draw()
end

------------------------------------------------------------------ LOOPS
local function gameLoop()
  layout()
  if W < 36 or H < 40 then error("Monitor too small - build it 3 wide x 6 tall", 0) end
  state.board = newBoard(false, math.random)
  state.shownWays = ways(state.board)
  newFake()
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
      tmr = os.startTimer(0.5)
    elseif e == "monitor_resize" or e == "peripheral" then
      layout(); draw()
    elseif e == "credits_changed" then
      draw()
    end
  end
end

local function adminLoop()
  term.clear(); term.setCursorPos(1, 1)
  print("BONANZA running on monitor")
  print("add <n> | set <n> | credits")
  print("demo free | demo cascade | exit")
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
    elseif cmd == "demo" and (arg == "free" or arg == "cascade") then
      state.force = arg
      print("Next paid spin will " .. (arg == "free" and "trigger FREE SPINS" or "land a big win"))
    elseif cmd == "exit" then
      return
    elseif cmd ~= "" then
      print("?  add <n> | set <n> | credits | demo free|cascade | exit")
    end
  end
end

loadCredits()
parallel.waitForAny(gameLoop, adminLoop)
mon.setBackgroundColor(colors.black); mon.clear()
print("Bonanza stopped.")
