--[[
  TRIPLE 7 JACKPOT  -  classic 3-reel slot for CC:Tweaked
  --------------------------------------------------------
  Setup:  computer + monitor wall (built for 3x4, auto-fits any size)
          optional speaker anywhere on the computer / network
  Run:    triple7
  Terminal commands while running:  add <n> | set <n> | credits | exit

  Rules:
  * 3 reels, 3 rows visible, up to 9 paylines.
  * Lines follow the bet automatically:
      bet 1 -> 1 line | 3 -> 3 lines | 5 -> 5 lines | 9+ -> all 9 lines
    (bets above 9 raise the per-line bet: 18 = 9 lines x 2, 90 = 9 x 10)
  * RED 7 is WILD: substitutes for every symbol except BONUS and
    doubles the win for each one used (x2, x4). Three RED 7s = JACKPOT.
  * 2 BONUS stars anywhere pay 2x total bet.
  * 3 BONUS stars anywhere = 8 FREE SPINS, all wins x3, can retrigger.
  * Designed return ~95% (verified by full reel enumeration).
]]

------------------------------------------------------------------ CONFIG
local CONFIG = {
  textScale     = 0.5,                 -- 0.5 = sharpest; raise if it looks cramped
  creditFile    = "triple7_credits.txt",
  startCredits  = 1000,                -- practice bankroll
  practiceMode  = true,                -- refill to startCredits when you run dry
  betLevels     = {1, 3, 5, 9, 18, 27, 45, 90},
  freeSpins     = 8,
  freeSpinMult  = 3,
  scatterPay2   = 2,                   -- x total bet for 2 BONUS
  spinDelay     = 0.05,                -- seconds per reel step
}

------------------------------------------------------------------ MATH
local PAY = { R7 = 1000, B7 = 100, P7 = 60, A7 = 20,
              B3 = 50, B2 = 25, B1 = 10, AB = 6 }
local CHERRY = { 2, 4, 10 }
local NAMES = { R7 = "RED 7s", B7 = "BLUE 7s", P7 = "PURPLE 7s",
                B3 = "TRIPLE BARS", B2 = "DOUBLE BARS", B1 = "SINGLE BARS" }

local function build(list)
  local s = {}
  for _, v in ipairs(list) do s[#s + 1] = v; s[#s + 1] = "--" end
  return s
end

-- "--" = blank. Every symbol is followed by a blank, like a real reel.
local STRIPS = {
  build{"R7","B1","CH","B2","B7","B1","SC","B3","B1","P7","CH","B2","B1","B7","SC","B3","B1","CH","B2","P7","B1"},
  build{"R7","B1","CH","B2","B7","B1","SC","B3","B1","P7","B2","B1","B7","SC","B3","B1","CH","B2","P7","B1","B2"},
  build{"R7","B1","B2","B7","B1","SC","B3","B1","P7","CH","B2","B1","B7","SC","B3","B1","B2","P7","B1","B2","B1"},
}

-- rows: 1 = top, 2 = middle, 3 = bottom (per reel)
local LINES = {
  {2,2,2}, {1,1,1}, {3,3,3}, {1,2,3}, {3,2,1},
  {1,2,1}, {3,2,3}, {2,1,2}, {2,3,2},
}
local LINE_COLORS = {"e","b","5","1","a","9","2","4","3"}

local function isSeven(s) return s == "R7" or s == "B7" or s == "P7" end
local function isBar(s)   return s == "B1" or s == "B2" or s == "B3" end

-- returns pay (x line bet) and a description
local function evalLine(a, b, c)
  local l = {a, b, c}
  local w, ch = 0, 0
  for i = 1, 3 do
    if l[i] == "R7" then w = w + 1 elseif l[i] == "CH" then ch = ch + 1 end
  end
  if w == 3 then return PAY.R7, "TRIPLE 7 JACKPOT!" end
  local mult = ({1, 2, 4})[w + 1]
  local tag = w > 0 and (" (WILD x" .. mult .. ")") or ""
  local best, name = 0, nil

  -- three of a kind (wilds fill in)
  local other, same = nil, true
  for i = 1, 3 do
    local s = l[i]
    if s ~= "R7" then
      if other == nil then other = s elseif other ~= s then same = false end
    end
  end
  if same and other and PAY[other] then
    best, name = PAY[other] * mult, "3 " .. NAMES[other] .. tag
  end
  -- any mix of sevens
  if isSeven(a) and isSeven(b) and isSeven(c) and PAY.A7 * mult > best then
    best, name = PAY.A7 * mult, "ANY 3 SEVENS" .. tag
  end
  -- any mix of bars
  local allBar = true
  for i = 1, 3 do if not (isBar(l[i]) or l[i] == "R7") then allBar = false end end
  if allBar and PAY.AB * mult > best then
    best, name = PAY.AB * mult, "ANY 3 BARS" .. tag
  end
  -- cherries
  if ch > 0 then
    if ch + w == 3 then
      if CHERRY[3] * mult > best then best, name = CHERRY[3] * mult, "3 CHERRIES" .. tag end
    elseif CHERRY[ch] > best then
      best, name = CHERRY[ch], ch .. (ch == 1 and " CHERRY" or " CHERRIES")
    end
  end
  return best, name
end

local function linesFor(bet)
  for _, n in ipairs({9, 5, 3, 1}) do
    if bet >= n and bet % n == 0 then return n end
  end
  return 1
end

local function symAt(r, p)
  local s = STRIPS[r]
  return s[((p - 1) % #s) + 1]
end

local function window(stops)
  local g = {}
  for r = 1, 3 do
    g[r] = {}
    for row = 1, 3 do g[r][row] = symAt(r, stops[r] + row - 2) end
  end
  return g
end

-- full result of a spin: line wins, scatter, totals (in credits)
local function evaluate(stops, bet, mult)
  local lines = linesFor(bet)
  local lb = math.floor(bet / lines)
  local g = window(stops)
  local res = { wins = {}, total = 0, scatters = 0, jackpot = false }
  for k = 1, lines do
    local L = LINES[k]
    local p, name = evalLine(g[1][L[1]], g[2][L[2]], g[3][L[3]])
    if p > 0 then
      local amt = p * lb * mult
      res.wins[#res.wins + 1] = { line = k, pay = amt, name = name,
        cells = {{1, L[1]}, {2, L[2]}, {3, L[3]}}, color = LINE_COLORS[k] }
      res.total = res.total + amt
      if p == PAY.R7 then res.jackpot = true end
    end
  end
  local sc = {}
  for r = 1, 3 do for row = 1, 3 do
    if g[r][row] == "SC" then sc[#sc + 1] = {r, row} end
  end end
  res.scatters = #sc
  if #sc == 2 then
    local amt = CONFIG.scatterPay2 * bet * mult
    res.wins[#res.wins + 1] = { pay = amt, name = "2 BONUS STARS", cells = sc, color = "6" }
    res.total = res.total + amt
  elseif #sc >= 3 then
    res.wins[#res.wins + 1] = { pay = 0, name = CONFIG.freeSpins .. " FREE SPINS!", cells = sc, color = "6" }
  end
  return res
end

-- exported for testing outside Minecraft
if not term or not peripheral then
  return { evaluate = evaluate, evalLine = evalLine, STRIPS = STRIPS,
           LINES = LINES, linesFor = linesFor, CONFIG = CONFIG }
end

------------------------------------------------------------------ PERIPHERALS
local mon = peripheral.find("monitor")
if not mon then error("No monitor found - attach the 3x4 monitor wall", 0) end
local speaker = peripheral.find("speaker")
math.randomseed(os.epoch("utc"))

local function note(inst, pitch, vol)
  if speaker then pcall(speaker.playNote, inst, vol or 1, pitch) end
end

------------------------------------------------------------------ STATE
local state = {
  credits = CONFIG.startCredits, betIdx = 1, lastWin = 0,
  msg = "TAP SPIN TO PLAY", stops = {1, 7, 13}, spinning = false,
  hl = {}, free = 0, freeTotal = 0, freeWin = 0, info = false, tick = 0,
  flash = nil,
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

------------------------------------------------------------------ LAYOUT
local Lay = {}
local function layout()
  mon.setTextScale(CONFIG.textScale)
  W, H = mon.getSize()
  Lay.titleH = 3
  Lay.panelH = 8
  Lay.tabW   = 3
  Lay.panelY = H - Lay.panelH + 1
  local roomy = H >= 45
  Lay.frameY = Lay.titleH + (roomy and 2 or 1)
  local innerTop = Lay.frameY + 1
  Lay.cellH = math.max(3, math.floor((Lay.panelY - (roomy and 2 or 1) - innerTop) / 3))
  local innerW = W - 2 * Lay.tabW - 2 - 2
  Lay.cellW = math.max(5, math.floor((innerW - 2) / 3))
  local totalW = 2 * Lay.tabW + 2 + 3 * Lay.cellW + 2
  Lay.left = math.floor((W - totalW) / 2) + 1
  Lay.frameX = Lay.left + Lay.tabW
  Lay.cellX0 = Lay.frameX + 1
  Lay.cellY0 = innerTop
  Lay.frameW = 3 * Lay.cellW + 4
  Lay.frameH = 3 * Lay.cellH + 2
  Lay.rightTab = Lay.frameX + Lay.frameW
end
local function cellPos(r, row)
  return Lay.cellX0 + (r - 1) * (Lay.cellW + 1), Lay.cellY0 + (row - 1) * Lay.cellH
end

------------------------------------------------------------------ SYMBOL ART (7x7)
local SEVEN = {
  "XXXXXXX", "XXXXXXX", ".....XX", "....XX.", "...XX..", "..XX...", "..XX...",
}
local ART = {
  CH = { "...dd..", "..d..d.", ".d...d.", ".d...d.", "eee.eee", "eee.eee", ".e...e." },
  SC = { "...1...", "..111..", "1111111", ".11111.", "..111..", ".11.11.", "1.....1" },
}
local SEVEN_COLOR = { R7 = "e", B7 = "b", P7 = "a" }
local LABEL = { R7 = {"WILD", "e"}, SC = {"BONUS", "1"} }
local BAR_ROWS = { B1 = {3}, B2 = {2, 4}, B3 = {1, 3, 5} }

local function drawSymbol(sym, x, y, w, h)
  fill(x, y, w, h, "0")
  if sym == "--" then return end
  local label = LABEL[sym]
  local lab = label and 1 or 0
  local ph = math.floor((h - 2 - lab) / 7)            -- padded, with label
  if ph < 1 then ph = math.floor((h - lab) / 7) end    -- no padding
  if ph < 1 and label then label, lab = nil, 0; ph = math.floor(h / 7) end
  if ph < 1 then
    -- tiny cell fallback: text only
    local t = ({R7="7",B7="7",P7="7",B1="BAR",B2="=BAR=",B3="BAR3",CH="CHRY",SC="BONUS"})[sym]
    local fg = SEVEN_COLOR[sym] or (sym == "CH" and "e") or (sym == "SC" and "1") or "f"
    ctext(x, y + math.floor(h / 2), w, t, fg, "0")
    return
  end
  local pw = math.max(1, math.min(math.floor((w - 2) / 7), ph * 2))
  local aw, ah = pw * 7, ph * 7
  local totalH = ah + (label and 1 or 0)
  local ox = x + math.floor((w - aw) / 2)
  local oy = y + math.floor((h - totalH) / 2)

  if BAR_ROWS[sym] then
    for _, rr in ipairs(BAR_ROWS[sym]) do
      local by = oy + rr * ph
      fill(ox, by, aw, ph, "f")
      ctext(ox, by + math.floor((ph - 1) / 2), aw, "BAR", "0", "f")
    end
  else
    local art = ART[sym]
    local col = SEVEN_COLOR[sym]
    if col then art = SEVEN end
    for ry = 1, 7 do
      local line = art[ry]
      for rx = 1, 7 do
        local c = line:sub(rx, rx)
        if c ~= "." then
          if c == "X" then c = col end
          fill(ox + (rx - 1) * pw, oy + (ry - 1) * ph, pw, ph, c)
        end
      end
    end
  end
  if label then ctext(x, oy + ah, w, label[1], label[2], "0") end
end

local function frameCell(r, row, color)
  local x, y = cellPos(r, row)
  local w, h = Lay.cellW, Lay.cellH
  for xx = x, x + w - 1 do put(xx, y, " ", nil, color); put(xx, y + h - 1, " ", nil, color) end
  for yy = y, y + h - 1 do put(x, yy, " ", nil, color); put(x + w - 1, yy, " ", nil, color) end
end

------------------------------------------------------------------ DRAW
local LEFT_TABS  = { {4, 2, 6}, {8, 1, 9}, {5, 3, 7} }
local RIGHT_TABS = { {5, 2, 6}, {8, 1, 9}, {4, 3, 7} }

local function drawTabs(x, tabs, activeLines)
  for row = 1, 3 do
    local _, cy = cellPos(1, row)
    local mid = cy + math.floor(Lay.cellH / 2)
    local step = Lay.cellH >= 5 and 2 or 1
    local ys = { mid - step, mid, mid + step }
    for i, k in ipairs(tabs[row]) do
      local on = k <= activeLines
      local bg = on and LINE_COLORS[k] or "7"
      local fg = on and ((k == 3 or k == 4 or k == 8 or k == 9) and "f" or "0") or "8"
      text(x, ys[i], " " .. k .. " ", fg, bg)
    end
  end
end

local function drawTitle()
  local bg = state.flash or "e"
  fill(1, 1, W, Lay.titleH, bg)
  for x = 1, W do
    local on = ((x + state.tick) % 2 == 0)
    put(x, 1, "\7", on and "4" or "0", bg)
    put(x, Lay.titleH, "\7", on and "0" or "4", bg)
  end
  local t = W >= 30 and " \7 TRIPLE 7 JACKPOT \7 " or "TRIPLE 7"
  ctext(1, 2, W, t, "4", bg)
end

local function drawPanel()
  local y = Lay.panelY
  local bet = CONFIG.betLevels[state.betIdx]
  local boxes = {
    {"CREDITS", tostring(state.credits), "4"},
    {"BET", tostring(bet), "0"},
    {"LINES", linesFor(bet) .. "x" .. (math.floor(bet / linesFor(bet))), "0"},
    {state.free > 0 and "FREE WIN" or "WIN",
     tostring(state.free > 0 and state.freeWin or state.lastWin), "5"},
  }
  local bw = math.floor(W / 4)
  for i, b in ipairs(boxes) do
    local bx = 1 + (i - 1) * bw
    ctext(bx, y, bw, b[1], "8", "f")
    ctext(bx, y + 1, bw, b[2], b[3], "f")
  end
  ctext(1, y + 2, W, state.msg or "", state.free > 0 and "4" or "0", "f")

  -- buttons
  local spinLabel = state.spinning and "..." or (state.free > 0 and "FREE" or "SPIN")
  local btns = {
    {"info", "INFO", "7", 1}, {"minus", "BET-", "b", 1}, {"plus", "BET+", "b", 1},
    {"max", "MAX", "a", 1}, {"spin", spinLabel, state.spinning and "7" or "d", 2},
  }
  local total = 0
  for _, b in ipairs(btns) do total = total + b[4] end
  local gap = 1
  local avail = W - 2 - gap * (#btns - 1)
  local unit = avail / total
  local x = 2
  local by, bh = y + 4, 3
  Lay.buttons = {}
  for i, b in ipairs(btns) do
    local bw2 = (i == #btns) and (W - 1 - x + 1) or math.floor(unit * b[4])
    fill(x, by, bw2, bh, b[3])
    ctext(x, by + 1, bw2, b[2], "0", b[3])
    Lay.buttons[#Lay.buttons + 1] = { id = b[1], x = x, y = by, w = bw2, h = bh }
    x = x + bw2 + gap
  end
end

local function drawInfo()
  clear("f")
  local lines = {
    {"TRIPLE 7 JACKPOT - PAYS x LINE BET", "4"},
    {"", "0"},
    {"3 RED 7  (WILD) ......... 1000  JACKPOT", "e"},
    {"3 BLUE 7 ................. 100", "b"},
    {"3 PURPLE 7 ................ 60", "a"},
    {"3 TRIPLE BAR .............. 50", "0"},
    {"3 DOUBLE BAR .............. 25", "0"},
    {"ANY 3 SEVENS .............. 20", "0"},
    {"3 SINGLE BAR .............. 10", "0"},
    {"3 CHERRIES ................ 10", "e"},
    {"ANY 3 BARS ................. 6", "0"},
    {"2 CHERRIES ................. 4", "e"},
    {"1 CHERRY ................... 2", "e"},
    {"", "0"},
    {"RED 7 is WILD - subs for all but BONUS", "e"},
    {"Each wild in a win doubles it (x2 / x4)", "0"},
    {"2 BONUS anywhere pays 2x total bet", "1"},
    {"3 BONUS = " .. CONFIG.freeSpins .. " FREE SPINS, wins x" .. CONFIG.freeSpinMult, "1"},
    {"", "0"},
    {"BET 1=1 line  3=3  5=5  9+=all 9 lines", "5"},
    {"", "0"},
    {"- TAP ANYWHERE TO RETURN -", "8"},
  }
  local y0 = math.max(1, math.floor((H - #lines) / 2))
  for i, l in ipairs(lines) do ctext(1, y0 + i - 1, W, l[1], l[2], "f") end
  flush()
end

local function draw()
  if state.info then return drawInfo() end
  clear("f")
  drawTitle()
  -- gold frame + black gaps
  fill(Lay.frameX, Lay.frameY, Lay.frameW, Lay.frameH, "4")
  fill(Lay.frameX + 1, Lay.frameY + 1, Lay.frameW - 2, Lay.frameH - 2, "f")
  for r = 1, 3 do
    for row = 1, 3 do
      local x, y = cellPos(r, row)
      drawSymbol(symAt(r, state.stops[r] + row - 2), x, y, Lay.cellW, Lay.cellH)
    end
  end
  for _, win in ipairs(state.hl) do
    for _, c in ipairs(win.cells) do frameCell(c[1], c[2], win.color) end
  end
  local lines = linesFor(CONFIG.betLevels[state.betIdx])
  drawTabs(Lay.left, LEFT_TABS, lines)
  drawTabs(Lay.rightTab, RIGHT_TABS, lines)
  drawPanel()
  flush()
end

------------------------------------------------------------------ GAMEPLAY
local function winSound(big)
  local seq = big and {6, 10, 13, 18, 22, 18, 22} or {12, 16, 19}
  for _, p in ipairs(seq) do note("bell", p, 1); sleep(0.08) end
end

local function jackpotShow(amount)
  state.msg = "*** TRIPLE 7 JACKPOT  " .. amount .. " ***"
  local cols = {"e", "4", "1", "4"}
  for i = 1, 16 do
    state.flash = cols[(i % #cols) + 1]
    state.tick = state.tick + 1
    draw()
    note("pling", (i * 3) % 24, 1)
    sleep(0.15)
  end
  state.flash = nil
end

local function rollUp(target, big)
  local start = state.free > 0 and state.freeWin or state.lastWin
  local steps = math.min(25, math.max(1, target))
  for i = 1, steps do
    local v = start + math.floor(target * i / steps)
    if state.free > 0 then state.freeWin = v else state.lastWin = v end
    if i % 2 == 0 then note("bit", 10 + (i % 12), 0.6) end
    draw(); sleep(0.04)
  end
end

local function doSpin(isFree)
  local bet = CONFIG.betLevels[state.betIdx]
  if not isFree then
    if state.credits < bet and CONFIG.practiceMode then
      state.credits = CONFIG.startCredits
      saveCredits()
      state.msg = "PRACTICE MODE - REFILLED TO " .. CONFIG.startCredits
      note("chime", 12); draw(); return
    elseif state.credits < bet then
      state.msg = "NOT ENOUGH CREDITS - SEE ATTENDANT"
      note("didgeridoo", 4); draw(); return
    end
    state.credits = state.credits - bet
    saveCredits()
    state.lastWin = 0
  end
  state.hl = {}
  state.spinning = true
  state.msg = isFree and ("FREE SPIN " .. (state.freeTotal - state.free + 1) .. " OF " .. state.freeTotal)
                      or "GOOD LUCK!"

  local final = {}
  for r = 1, 3 do final[r] = math.random(#STRIPS[r]) end
  local rem = { 14 + math.random(0, 4), 22 + math.random(0, 4), 30 + math.random(0, 4) }
  local moving = true
  while moving do
    moving = false
    for r = 1, 3 do
      if rem[r] > 0 then
        rem[r] = rem[r] - 1
        state.stops[r] = final[r] + rem[r]      -- counting down = reel rolls downward
        if rem[r] == 0 then note("basedrum", 6, 1) else moving = true end
      end
    end
    draw()
    sleep(CONFIG.spinDelay)
  end
  for r = 1, 3 do state.stops[r] = final[r] end
  state.spinning = false

  local mult = isFree and CONFIG.freeSpinMult or 1
  local res = evaluate(state.stops, bet, mult)
  state.hl = res.wins

  if res.total > 0 then
    if not isFree then state.credits = state.credits + res.total; saveCredits() end
    state.msg = "WIN " .. res.total .. "!"
    if res.jackpot then jackpotShow(res.total) else winSound(res.total >= bet * 10) end
    rollUp(res.total, res.total >= bet * 10)
    -- walk through each winning line
    if #res.wins > 1 then
      for _, w in ipairs(res.wins) do
        state.hl = { w }
        state.msg = (w.line and ("LINE " .. w.line .. ": ") or "") .. w.name ..
                    (w.pay > 0 and ("  = " .. w.pay) or "")
        draw(); sleep(0.9)
      end
      state.hl = res.wins
    else
      local w = res.wins[1]
      state.msg = (w.line and ("LINE " .. w.line .. ": ") or "") .. w.name ..
                  (w.pay > 0 and ("  = " .. w.pay) or "")
    end
  elseif not isFree then
    state.msg = "TAP SPIN TO PLAY"
  end

  if res.scatters >= 3 then
    if state.free > 0 then
      state.free = state.free + CONFIG.freeSpins
      state.freeTotal = state.freeTotal + CONFIG.freeSpins
      state.msg = "RETRIGGER! +" .. CONFIG.freeSpins .. " FREE SPINS"
    else
      state.free = CONFIG.freeSpins
      state.freeTotal = CONFIG.freeSpins
      state.freeWin = 0
      state.msg = CONFIG.freeSpins .. " FREE SPINS!  ALL WINS x" .. CONFIG.freeSpinMult
    end
    winSound(true)
  end
  draw()
end

local function runFreeSpins()
  sleep(1.5)
  while state.free > 0 do
    doSpin(true)
    state.free = state.free - 1
    sleep(1.2)
  end
  local won = state.freeWin
  state.credits = state.credits + won
  saveCredits()
  state.lastWin = won
  state.freeWin, state.freeTotal = 0, 0
  state.msg = "FREE SPINS PAID " .. won .. "!"
  if won > 0 then winSound(true) end
  draw()
end

local function hit(x, y)
  for _, b in ipairs(Lay.buttons or {}) do
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b.id end
  end
end

local function onTouch(x, y)
  if state.info then state.info = false; draw(); return end
  local id = hit(x, y)
  if not id then
    -- tapping the reels also spins, like hitting the machine's button
    if y >= Lay.frameY and y < Lay.frameY + Lay.frameH then id = "spin" else return end
  end
  note("hat", 16, 0.5)
  if id == "info" then state.info = true
  elseif id == "minus" then state.betIdx = math.max(1, state.betIdx - 1); state.hl = {}
  elseif id == "plus" then state.betIdx = math.min(#CONFIG.betLevels, state.betIdx + 1); state.hl = {}
  elseif id == "max" then state.betIdx = #CONFIG.betLevels; state.hl = {}
  elseif id == "spin" then
    doSpin(false)
    if state.free > 0 then runFreeSpins() end
    return
  end
  local bet = CONFIG.betLevels[state.betIdx]
  state.msg = "BET " .. bet .. "  -  " .. linesFor(bet) .. " LINE" ..
              (linesFor(bet) > 1 and "S" or "") .. " x " .. (math.floor(bet / linesFor(bet)))
  draw()
end

------------------------------------------------------------------ LOOPS
local function gameLoop()
  layout(); draw()
  local tmr = os.startTimer(0.5)
  while true do
    local e, a, b, c = os.pullEvent()
    if e == "timer" and a == tmr then
      state.tick = state.tick + 1
      if not state.info then draw() end
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
  print("TRIPLE 7 JACKPOT running on monitor")
  print("Commands: add <n> | set <n> | credits | exit")
  while true do
    write("> ")
    local cmd, n = (read() or ""):match("^(%S*)%s*(%-?%d*)")
    n = tonumber(n)
    if cmd == "add" and n then
      state.credits = state.credits + n; saveCredits()
      print("Credits: " .. state.credits); os.queueEvent("credits_changed")
    elseif cmd == "set" and n then
      state.credits = n; saveCredits()
      print("Credits: " .. state.credits); os.queueEvent("credits_changed")
    elseif cmd == "credits" then
      print("Credits: " .. state.credits)
    elseif cmd == "exit" then
      return
    elseif cmd ~= "" then
      print("?  add <n> | set <n> | credits | exit")
    end
  end
end

loadCredits()
parallel.waitForAny(gameLoop, adminLoop)
mon.setBackgroundColor(colors.black); mon.clear()
print("Triple 7 stopped.")
