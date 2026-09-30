--[[
  DOUBLE ZERO ROULETTE  -  American roulette table for CC:Tweaked
  ---------------------------------------------------------------
  Setup:  computer + monitor wall laid FLAT ON THE FLOOR, screen facing up.
          Built for 8 wide x 5 deep (164 x 66 at text scale 0.5).
          8 x 6 also works (bigger betting cells); 6 x 4 is the minimum.
          Speakers optional - every attached / networked speaker plays.
  Run:    roulette
  Terminal commands while running:
          add <seat> <n> | set <seat> <n> | credits | next <num> | exit

  How to play (players stand on the table and right-click the screen):
  * Tap a SEAT button to pick who is betting (monitors can't tell players
    apart, so each player uses their own seat colour).
  * Tap a CHIP value, then tap the layout to place chips.
      - middle of a number ............ straight up   35 to 1
      - line between two numbers ...... split         17 to 1
      - bottom line of a column ....... street        11 to 1
      - where 4 numbers meet .......... corner         8 to 1
      - bottom line between 2 columns . six line       5 to 1
      - line where 0/00 meet 1-2-3 .... trio 0-1-2 / 00-2-3  11 to 1
      - bottom corner of 0 and 1 ...... 0-00-1-2-3     6 to 1
      - dozens / 2 TO 1 columns ....... 2 to 1
      - 1-18, 19-36, RED, BLACK, ODD, EVEN ....... 1 to 1
  * SPIN when everyone's in. UNDO / CLEAR / REBET / X2 work per seat.
]]

------------------------------------------------------------------ CONFIG
local CONFIG = {
  textScale     = 0.5,
  creditFile    = "roulette_credits.txt",
  startCredits  = 5000,                 -- practice bankroll per seat
  practiceMode  = true,                 -- refill a seat that runs dry
  chips         = {1, 5, 25, 100, 500},
  maxSpot       = 5000,                 -- max chips on one spot (all seats together)
  edgeMargin    = 1,                    -- chars inside a cell that count as the line
  spinTime      = 6,                    -- seconds until the ball drops in
  customPalette = true,                 -- casino felt green + dark wood
  seats = {
    { name = "BLUE",   color = "b", text = "0" },
    { name = "ORANGE", color = "1", text = "f" },
    { name = "PURPLE", color = "a", text = "0" },
    { name = "CYAN",   color = "9", text = "f" },
  },
}

------------------------------------------------------------------ MATH
local DZ = 37                                   -- "00" is stored as 37
local WHEEL = { 0, 28, 9, 26, 30, 11, 7, 20, 32, 17, 5, 22, 34, 15, 3, 24, 36, 13, 1,
                DZ, 27, 10, 25, 29, 12, 8, 19, 31, 18, 6, 21, 33, 16, 4, 23, 35, 14, 2 }
local RED = {}
for _, n in ipairs({1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36}) do RED[n] = true end
local POCKET = {}
for i, n in ipairs(WHEEL) do POCKET[n] = i end

local PAYS = { straight = 35, split = 17, street = 11, trio = 11, corner = 8,
               basket = 6, sixline = 5, dozen = 2, column = 2, even = 1 }

local function numColor(n)
  if n == 0 or n == DZ then return "5" end
  return RED[n] and "e" or "f"
end
local function numStr(n) return n == DZ and "00" or tostring(n) end
local function colorName(n)
  if n == 0 or n == DZ then return "GREEN" end
  return RED[n] and "RED" or "BLACK"
end

local BETS = {}                                 -- key -> bet definition
local function regBet(kind, nums, ax, ay, label)
  local s = {}
  for i, n in ipairs(nums) do s[i] = n end
  table.sort(s)
  local parts = {}
  for i, n in ipairs(s) do parts[i] = numStr(n) end
  local key = kind .. ":" .. table.concat(parts, ",")
  if not BETS[key] then
    local set = {}
    for _, n in ipairs(s) do set[n] = true end
    BETS[key] = { key = key, kind = kind, nums = s, set = set, pay = PAYS[kind], ax = ax, ay = ay,
                  label = label or (kind == "straight" and parts[1])
                          or (kind:upper() .. " " .. table.concat(parts, "-")) }
  end
  return BETS[key]
end

local function numsWhere(f)
  local t = {}
  for n = 1, 36 do if f(n) then t[#t + 1] = n end end
  return t
end

local OUTSIDE = {
  { "1 TO 18",  function(n) return n <= 18 end },
  { "EVEN",     function(n) return n % 2 == 0 end },
  { "RED",      function(n) return RED[n] end },
  { "BLACK",    function(n) return not RED[n] end },
  { "ODD",      function(n) return n % 2 == 1 end },
  { "19 TO 36", function(n) return n >= 19 end },
}

------------------------------------------------------------------ PERIPHERALS
local mon = peripheral.find("monitor")
if not mon then error("No monitor found - attach the floor monitor (8 wide x 5 deep)", 0) end
local speakers = { peripheral.find("speaker") }
math.randomseed(os.epoch("utc"))

local function note(inst, pitch, vol)
  for _, s in ipairs(speakers) do pcall(s.playNote, inst, vol or 1, pitch) end
end
local function sfx(name, vol, pitch)
  for _, s in ipairs(speakers) do pcall(s.playSound, name, vol or 1, pitch or 1) end
end
local function tune(inst, seq, dt)
  for i, p in ipairs(seq) do note(inst, p, 1); if i < #seq then sleep(dt or 0.08) end end
end

local PALETTE = { [colors.green] = 0x0b5a2c, [colors.lime] = 0x19a347, [colors.brown] = 0x5a3216 }
local function applyPalette()
  if not CONFIG.customPalette or not mon.setPaletteColour then return end
  for c, v in pairs(PALETTE) do mon.setPaletteColour(c, v) end
end
local function restorePalette()
  if not mon.setPaletteColour then return end
  for c in pairs(PALETTE) do mon.setPaletteColour(c, term.nativePaletteColour(c)) end
end

------------------------------------------------------------------ STATE
local NSEATS = #CONFIG.seats
local state = {
  credits = {}, seat = 1, chip = 2,
  bets = {},              -- key -> { [seat] = amount }
  undo = {},              -- seat -> list of {key, amt}
  lastBets = {},          -- seat -> list of {key, amt} from the previous spin
  phase = "bet",          -- bet | spin | result
  rot = 0, ball = nil, result = nil, winKeys = nil,
  history = {}, msg = "PLACE YOUR BETS", info = false, tick = 0, force = nil,
}
for i = 1, NSEATS do state.credits[i] = CONFIG.startCredits; state.undo[i] = {}; state.lastBets[i] = {} end

local function saveCredits()
  local h = fs.open(CONFIG.creditFile, "w")
  h.write(textutils.serialize(state.credits)); h.close()
end
local function loadCredits()
  if not fs.exists(CONFIG.creditFile) then return end
  local h = fs.open(CONFIG.creditFile, "r")
  local t = textutils.unserialize(h.readAll()); h.close()
  if type(t) == "table" then
    for i = 1, NSEATS do if tonumber(t[i]) then state.credits[i] = tonumber(t[i]) end end
  end
end

local function fmt(n)
  local s = tostring(math.floor(n))
  local neg = s:sub(1, 1) == "-"
  if neg then s = s:sub(2) end
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return (neg and "-" or "") .. out
end
local function short(n)
  if n < 1000 then return tostring(math.floor(n)) end
  if n < 10000 and n % 1000 ~= 0 then return string.format("%.1fK", n / 1000) end
  return tostring(math.floor(n / 1000)) .. "K"
end

local function seatOnTable(seat)
  local t = 0
  for _, b in pairs(state.bets) do t = t + (b[seat] or 0) end
  return t
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

------------------------------------------------------------------ BIG 3x5 FONT
local FONT = {
  ["0"]={"XXX","X.X","X.X","X.X","XXX"}, ["1"]={".X.","XX.",".X.",".X.","XXX"},
  ["2"]={"XX.","..X",".X.","X..","XXX"}, ["3"]={"XX.","..X",".X.","..X","XX."},
  ["4"]={"X.X","X.X","XXX","..X","..X"}, ["5"]={"XXX","X..","XX.","..X","XX."},
  ["6"]={".XX","X..","XXX","X.X","XXX"}, ["7"]={"XXX","..X",".X.",".X.",".X."},
  ["8"]={"XXX","X.X","XXX","X.X","XXX"}, ["9"]={"XXX","X.X","XXX","..X","XX."},
  [" "]={"...","...","...","...","..."},
}
local function bigW(s) return #s * 4 - 1 end
local function bigText(x, y, s, fg)
  for i = 1, #s do
    local g = FONT[s:sub(i, i)] or FONT[" "]
    for ry = 1, 5 do
      for rx = 1, 3 do
        if g[ry]:sub(rx, rx) == "X" then put(x + (i - 1) * 4 + rx - 1, y + ry - 1, " ", nil, fg) end
      end
    end
  end
end

------------------------------------------------------------------ WHEEL (teletext sub-pixels)
-- Each character cell is 2x3 square sub-pixels, so the wheel is a true circle.
local TWO_PI = 2 * math.pi
local SEG = TWO_PI / 38
local atan2 = math.atan2 or math.atan
local FELT = "d"
local Wh = {}
local R_TRACK, R_POCKET, R_LABEL = 0.885, 0.63, 0.72

-- colour for a sub-pixel that never changes as the wheel turns (false = rotates)
local function staticColor(r)
  if r > 1 then return FELT end
  if r > 0.955 then return "4" end          -- gold rim
  if r > 0.815 then return "c" end          -- ball track
  if r > 0.80 then return "4" end           -- pocket wall
  if r > 0.585 then return false end        -- numbered pockets
  if r > 0.555 then return "4" end
  if r > 0.42 then return "c" end           -- cone
  return false                              -- turret
end

local function dynColor(r, a, rot)
  local rel = (a - rot) % TWO_PI
  if r > 0.5 then
    local f = rel / SEG
    local p = math.floor(f)
    local fr = f - p
    if p >= 38 then p = 0 end
    if math.min(fr, 1 - fr) * SEG * r * Wh.R < 0.55 then return "4" end
    return numColor(WHEEL[p + 1])
  end
  if state.result and r < 0.40 then return numColor(state.result) end
  if r < 0.07 then return "4" end
  local q = rel % (math.pi / 2)
  local d = math.min(q, math.pi / 2 - q) * r * Wh.R
  if r < 0.36 and d < 1.1 then return "4" end
  if r > 0.32 and r < 0.40 and d < 2.4 then return "4" end
  return "c"
end

-- six sub-pixel colours -> teletext char, fg, bg
local function reduce(c)
  local cnt, a, b = {}, nil, nil
  for i = 1, 6 do cnt[c[i]] = (cnt[c[i]] or 0) + 1 end
  for k, v in pairs(cnt) do
    if not a or v > cnt[a] then b = a; a = k
    elseif not b or v > cnt[b] then b = k end
  end
  if not b then return " ", "0", a end
  local m = {}
  for i = 1, 6 do m[i] = (c[i] == a or c[i] == b) and c[i] or a end
  local bg = m[6]
  local fg = (bg == a) and b or a
  local bits = 0
  for i = 1, 5 do if m[i] ~= bg then bits = bits + 2 ^ (i - 1) end end
  return string.char(128 + bits), fg, bg
end

local function wheelLayout(x, y, wc, hc)
  local R = math.floor(math.min(wc * 2, hc * 3) / 2) - 1
  local cw, ch = R + 1, math.ceil((2 * R + 2) / 3)
  Wh.R, Wh.cw, Wh.ch = R, cw, ch
  Wh.x = x + math.floor((wc - cw) / 2)
  Wh.y = y + math.floor((hc - ch) / 2)
  Wh.SW = cw * 2
  Wh.cx, Wh.cy = cw, ch * 1.5
  Wh.r, Wh.a, Wh.st, Wh.static = {}, {}, {}, {}
  for py = 0, ch * 3 - 1 do
    for px = 0, Wh.SW - 1 do
      local dx, dy = px + 0.5 - Wh.cx, py + 0.5 - Wh.cy
      local i = py * Wh.SW + px + 1
      Wh.r[i] = math.sqrt(dx * dx + dy * dy) / R
      Wh.a[i] = atan2(dy, dx)
      Wh.st[i] = staticColor(Wh.r[i])
    end
  end
  -- cells made only of fixed sub-pixels are reduced once
  local c = {}
  for cy = 0, ch - 1 do
    for cx = 0, cw - 1 do
      local ok = true
      for k = 0, 5 do
        local i = (cy * 3 + math.floor(k / 2)) * Wh.SW + cx * 2 + (k % 2) + 1
        c[k + 1] = Wh.st[i]
        if not c[k + 1] then ok = false end
      end
      if ok then
        local chr, fg, bg = reduce(c)
        Wh.static[cy * cw + cx + 1] = { chr, fg, bg }
      end
    end
  end
end

local function drawWheel()
  local rot, ball = state.rot, state.ball
  local bx, by
  if ball then
    bx = Wh.cx + math.cos(ball.a) * ball.r * Wh.R
    by = Wh.cy + math.sin(ball.a) * ball.r * Wh.R
  end
  local c = {}
  for cy = 0, Wh.ch - 1 do
    for cx = 0, Wh.cw - 1 do
      local st = Wh.static[cy * Wh.cw + cx + 1]
      local nearBall = bx and math.abs(cx * 2 + 1 - bx) < 3 and math.abs(cy * 3 + 1.5 - by) < 3.5
      if st and not nearBall then
        put(Wh.x + cx, Wh.y + cy, st[1], st[2], st[3])
      else
        for k = 0, 5 do
          local px, py = cx * 2 + (k % 2), cy * 3 + math.floor(k / 2)
          local i = py * Wh.SW + px + 1
          local col = Wh.st[i] or dynColor(Wh.r[i], Wh.a[i], rot)
          if nearBall then
            local dx, dy = px + 0.5 - bx, py + 0.5 - by
            if dx * dx + dy * dy <= 2.7 then col = "0" end
          end
          c[k + 1] = col
        end
        local chr, fg, bg = reduce(c)
        put(Wh.x + cx, Wh.y + cy, chr, fg, bg)
      end
    end
  end
  -- pocket numbers ride around with the wheel
  local flash = state.result and state.tick % 2 == 0
  for p = 1, 38 do
    local n = WHEEL[p]
    local ang = rot + (p - 0.5) * SEG
    local sx = Wh.cx + math.cos(ang) * R_LABEL * Wh.R
    local sy = Wh.cy + math.sin(ang) * R_LABEL * Wh.R
    local s = numStr(n)
    local tx = Wh.x + math.floor(sx / 2 - #s / 2 + 0.5)
    local ty = Wh.y + math.floor(sy / 3)
    local hit = flash and n == state.result
    text(tx, ty, s, hit and "f" or "0", hit and "4" or numColor(n))
  end
  -- winning number in the middle of the wheel
  if state.result then
    local s = numStr(state.result)
    local ccx, ccy = Wh.x + math.floor(Wh.cx / 2), Wh.y + math.floor(Wh.cy / 3)
    if Wh.R >= 48 then
      bigText(ccx - math.floor(bigW(s) / 2), ccy - 2, s, "0")
    else
      ctext(ccx - 2, ccy, 5, s, "0", numColor(state.result))
    end
  end
end

------------------------------------------------------------------ TABLE LAYOUT
local Lay, T = {}, {}
local function colStart(c) return T.x + 1 + c * (T.cw + 1) end
local function rowStart(r) return T.y + 1 + (r - 1) * (T.rh + 1) end
local function colCenter(c) return colStart(c) + math.floor((T.cw - 1) / 2) end
local function rowCenter(r) return rowStart(r) + math.floor((T.rh - 1) / 2) end
local function vLine(c) return colStart(c) + T.cw end        -- line right of column c
local function hLine(r) return rowStart(r) + T.rh end        -- line under row r
local function N(c, r) return 3 * c - (r - 1) end            -- row 1 = top (3,6,9..)
local function zeroMid() return rowStart(1) + math.floor((3 * T.rh + 2) / 2) end
local function dozY() return hLine(3) + 1 end
local function outY() return dozY() + T.dh + 1 end

-- x -> "c", col  |  "e", c (the line between column c and c+1)
local function classX(x)
  local m = CONFIG.edgeMargin
  for c = 0, 13 do
    local s = colStart(c)
    if x >= s and x < s + T.cw then
      local dx = x - s
      if dx < m and c > 0 then return "e", c - 1 end
      if dx >= T.cw - m and c < 13 then return "e", c end
      return "c", c
    elseif x == s + T.cw and c < 13 then
      return "e", c
    end
  end
end
-- y -> "c", row  |  "e", r (the line under row r; r = 3 is the street line)
local function classY(y)
  local m = CONFIG.edgeMargin
  for r = 1, 3 do
    local s = rowStart(r)
    if y >= s and y < s + T.rh then
      local dy = y - s
      if dy < m and r > 1 then return "e", r - 1 end
      if dy >= T.rh - m then return "e", r end
      return "c", r
    elseif y == s + T.rh then
      return "e", r
    end
  end
end

-- which bet does a tap at (x, y) make?
local function classify(x, y)
  if x < T.x or x >= T.x + T.w or y < T.y or y >= T.y + T.h then return nil end
  local kx, cx = classX(x)
  if not kx then return nil end
  if kx == "e" and cx == 12 then kx, cx = "c", (x < colStart(13)) and 12 or 13 end
  local ky, ry = classY(y)

  if not ky then                                    -- dozens / outside boxes
    local c = math.floor((x - colStart(1)) / (T.cw + 1)) + 1
    if x < colStart(1) - 1 or c > 12 then return nil end
    c = math.max(1, c)
    if y >= dozY() and y < dozY() + T.dh then
      local d = math.floor((c - 1) / 4) + 1
      local lo = (d - 1) * 12
      return regBet("dozen", numsWhere(function(n) return n > lo and n <= lo + 12 end),
        colStart((d - 1) * 4 + 1) + 2 * T.cw + 1, dozY() + math.floor(T.dh / 2),
        ({"1ST 12", "2ND 12", "3RD 12"})[d])
    elseif y >= outY() and y < outY() + T.dh then
      local o = math.floor((c - 1) / 2) + 1
      return regBet("even", numsWhere(OUTSIDE[o][2]), vLine((o - 1) * 2 + 1),
        outY() + math.floor(T.dh / 2), OUTSIDE[o][1])
    end
    return nil
  end

  if kx == "c" and cx == 0 then                     -- 0 / 00
    local mid = zeroMid()
    if math.abs(y - mid) <= CONFIG.edgeMargin then
      return regBet("split", {0, DZ}, colCenter(0), mid)
    end
    if y < mid then return regBet("straight", {DZ}, colCenter(0), rowStart(1) + math.floor((mid - rowStart(1)) / 2)) end
    return regBet("straight", {0}, colCenter(0), mid + math.floor((hLine(3) - mid) / 2))
  end

  if kx == "c" and cx == 13 then                    -- 2 TO 1 columns
    local r = ry
    local want = (4 - r) % 3
    return regBet("column", numsWhere(function(n) return n % 3 == want end),
      colCenter(13), rowCenter(r), "COLUMN " .. (4 - r))
  end

  if kx == "c" then
    if ky == "c" then return regBet("straight", {N(cx, ry)}, colCenter(cx), rowCenter(ry)) end
    if ry < 3 then return regBet("split", {N(cx, ry), N(cx, ry + 1)}, colCenter(cx), hLine(ry)) end
    return regBet("street", {N(cx, 1), N(cx, 2), N(cx, 3)}, colCenter(cx), hLine(3))
  end

  if cx >= 1 then                                   -- line between two number columns
    if ky == "c" then return regBet("split", {N(cx, ry), N(cx + 1, ry)}, vLine(cx), rowCenter(ry)) end
    if ry < 3 then
      return regBet("corner", {N(cx, ry), N(cx, ry + 1), N(cx + 1, ry), N(cx + 1, ry + 1)}, vLine(cx), hLine(ry))
    end
    local t = {}
    for c = cx, cx + 1 do for r = 1, 3 do t[#t + 1] = N(c, r) end end
    return regBet("sixline", t, vLine(cx), hLine(3))
  end

  -- line between the zeros and 1-2-3
  local vx = vLine(0)
  if ky == "c" then
    if ry == 1 then return regBet("split", {DZ, 3}, vx, rowCenter(1)) end
    if ry == 3 then return regBet("split", {0, 1}, vx, rowCenter(3)) end
    if y < zeroMid() then return regBet("split", {DZ, 2}, vx, rowStart(2) + 1) end
    return regBet("split", {0, 2}, vx, rowStart(2) + T.rh - 2)
  end
  if ry == 1 then return regBet("trio", {DZ, 2, 3}, vx, hLine(1)) end
  if ry == 2 then return regBet("trio", {0, 1, 2}, vx, hLine(2)) end
  return regBet("basket", {0, DZ, 1, 2, 3}, vx, hLine(3), "0-00-1-2-3")
end

local function layout()
  mon.setTextScale(CONFIG.textScale)
  W, H = mon.getSize()
  Lay.titleH = 3
  Lay.panelH = 14
  Lay.panelY = H - Lay.panelH + 1
  Lay.mainY  = Lay.titleH + 2
  Lay.mainH  = Lay.panelY - 1 - Lay.mainY
  for cw = 7, 4, -1 do
    T.cw = cw
    T.w = 1 + 14 * (cw + 1)
    if W - T.w - 4 >= W * 0.35 then break end
  end
  T.dh = math.max(3, math.min(5, math.floor(Lay.mainH / 9)))
  T.rh = math.floor((Lay.mainH - 1 - 2 * (T.dh + 1)) / 3) - 1
  T.h  = 1 + 3 * (T.rh + 1) + 2 * (T.dh + 1)
  T.x  = W - T.w
  T.y  = Lay.mainY + math.floor((Lay.mainH - T.h) / 2)
  Lay.histH = 5
  Lay.wheelX, Lay.wheelW = 2, T.x - 3
  Lay.histY = Lay.mainY + Lay.mainH - Lay.histH
  wheelLayout(Lay.wheelX, Lay.mainY, Lay.wheelW, Lay.mainH - Lay.histH - 1)
  if T.rh < 4 or Wh.R < 36 then
    error("Monitor too small - build it at least 6 wide x 4 deep (8 x 5 recommended)", 0)
  end
  BETS = {}
  Lay.hit = {}
  for y = T.y, T.y + T.h - 1 do
    Lay.hit[y] = {}
    for x = T.x, T.x + T.w - 1 do
      local b = classify(x, y)
      Lay.hit[y][x] = b and b.key
    end
  end
end

------------------------------------------------------------------ DRAW
local function drawTitle()
  fill(1, 1, W, Lay.titleH, "c")
  for x = 1, W do
    local on = (x + state.tick) % 4 == 0
    put(x, 1, "\7", on and "4" or "1", "c")
    put(x, Lay.titleH, "\7", on and "1" or "4", "c")
  end
  ctext(1, 2, W, "\4  DOUBLE ZERO ROULETTE  \4", "4", "c")
end

local function numberCell(n)
  if n == DZ then return colStart(0), rowStart(1), T.cw, zeroMid() - rowStart(1) end
  if n == 0 then return colStart(0), zeroMid() + 1, T.cw, hLine(3) - zeroMid() - 1 end
  local c = math.floor((n - 1) / 3) + 1
  local r = 3 - ((n - 1) % 3)
  return colStart(c), rowStart(r), T.cw, T.rh
end

local function drawTable()
  local flash = state.tick % 2 == 0
  local win = state.result
  fill(T.x, T.y, T.w, hLine(3) - T.y + 1, "0")                   -- white lines
  fill(colStart(1) - 1, dozY(), 12 * (T.cw + 1) + 1, T.h - (dozY() - T.y), "0")
  -- numbers
  for n = 0, DZ do
    local x, y, w, h = numberCell(n)
    local bg, fg = numColor(n), "0"
    if win == n and flash then bg, fg = "4", "f" end
    fill(x, y, w, h, bg)
    ctext(x, y + math.floor((h - 1) / 2), w, numStr(n), fg, bg)
  end
  -- 2 TO 1
  for r = 1, 3 do
    fill(colStart(13), rowStart(r), T.cw, T.rh, FELT)
    local s = T.cw >= 6 and "2 TO 1" or "2:1"
    ctext(colStart(13), rowCenter(r), T.cw, s, "0", FELT)
  end
  -- dozens and even-money boxes
  local function box(x, y, w, h, label, bg, key)
    local won = state.winKeys and state.winKeys[key] and flash
    fill(x, y, w, h, won and "4" or bg)
    ctext(x, y + math.floor((h - 1) / 2), w, label, won and "f" or (bg == FELT and "4" or "0"), won and "4" or bg)
  end
  for d = 1, 3 do
    local c = (d - 1) * 4 + 1
    local def = BETS[Lay.hit[dozY()][colStart(c)]]
    box(colStart(c), dozY(), 4 * T.cw + 3, T.dh, def.label, FELT, def.key)
  end
  for o = 1, 6 do
    local c = (o - 1) * 2 + 1
    local def = BETS[Lay.hit[outY()][colStart(c)]]
    local bg = (o == 3 and "e") or (o == 4 and "f") or FELT
    box(colStart(c), outY(), 2 * T.cw + 1, T.dh, def.label, bg, def.key)
  end
  -- column bet highlights
  if state.winKeys and flash then
    for r = 1, 3 do
      local def = BETS[Lay.hit[rowCenter(r)][colCenter(13)]]
      if state.winKeys[def.key] then
        fill(colStart(13), rowStart(r), T.cw, T.rh, "4")
        ctext(colStart(13), rowCenter(r), T.cw, T.cw >= 6 and "2 TO 1" or "2:1", "f", "4")
      end
    end
  end
  -- chips
  for key, seats in pairs(state.bets) do
    local def = BETS[key]
    local list = {}
    for s = 1, NSEATS do if seats[s] and seats[s] > 0 then list[#list + 1] = s end end
    local y0 = def.ay - math.floor((#list - 1) / 2)
    for i, s in ipairs(list) do
      local seat = CONFIG.seats[s]
      local t = " " .. short(seats[s]) .. " "
      local won = state.winKeys and state.winKeys[key]
      local bg = (won and flash) and "0" or seat.color
      text(def.ax - math.floor((#t - 1) / 2), y0 + i - 1, t, (won and flash) and "f" or seat.text, bg)
    end
  end
end

local function drawHistory()
  local y = Lay.histY
  ctext(Lay.wheelX, y, Lay.wheelW, "LAST NUMBERS", "8", FELT)
  local n = math.min(#state.history, math.floor((Lay.wheelW + 1) / 5))
  local total = n * 5 - 1
  local x = Lay.wheelX + math.floor((Lay.wheelW - total) / 2)
  for i = 1, n do
    local v = state.history[i]
    local bg = numColor(v)
    fill(x, y + 1, 4, 3, bg)
    ctext(x, y + 2, 4, numStr(v), (i == 1 and state.tick % 2 == 0 and state.phase == "result") and "4" or "0", bg)
    x = x + 5
  end
end

local function drawPanel()
  local y = Lay.panelY
  fill(1, y, W, Lay.panelH, "f")
  ctext(1, y, W, state.msg or "", state.phase == "bet" and "0" or "4", "f")
  Lay.buttons = {}
  local function button(id, x, by, w, h, label, bg, fg, sub, subfg)
    fill(x, by, w, h, bg)
    if sub then
      ctext(x, by, w, label, fg, bg)
      ctext(x, by + 1, w, sub, subfg or fg, bg)
      if h > 2 then ctext(x, by + 2, w, "", fg, bg) end
    else
      ctext(x, by + math.floor((h - 1) / 2), w, label, fg, bg)
    end
    Lay.buttons[#Lay.buttons + 1] = { id = id, x = x, y = by, w = w, h = h }
  end
  local busy = state.phase ~= "bet"
  -- seats
  local gap = 1
  local sw = math.floor((W - 2 - gap * (NSEATS - 1)) / NSEATS)
  for i, s in ipairs(CONFIG.seats) do
    local x = 2 + (i - 1) * (sw + gap)
    local active = i == state.seat
    local bg = active and s.color or "7"
    local fg = active and s.text or s.color
    local onT = seatOnTable(i)
    local mark = active and "\16 " or ""
    button("seat" .. i, x, y + 2, sw, 3, mark .. s.name, bg, fg,
      fmt(state.credits[i]) .. (onT > 0 and ("  BET " .. fmt(onT)) or ""), active and s.text or "0")
  end
  -- chips + info
  local items = #CONFIG.chips + 1
  local cw = math.floor((W - 2 - gap * (items - 1)) / items)
  local CHIPCOL = { "0", "e", "5", "f", "a", "b", "1" }
  for i, v in ipairs(CONFIG.chips) do
    local x = 2 + (i - 1) * (cw + gap)
    local bg = CHIPCOL[i] or "7"
    local fg = (bg == "0") and "f" or "0"
    local sel = i == state.chip
    button("chip" .. i, x, y + 6, cw, 3, sel and ("\16 " .. fmt(v) .. " \17") or fmt(v), sel and "4" or bg, sel and "f" or fg)
    if not sel then
      for xx = x, x + cw - 1 do put(xx, y + 6, "\131", "7", bg); put(xx, y + 8, "\143", bg, "7") end
      ctext(x, y + 7, cw, fmt(v), fg, bg)
    end
  end
  button("info", 2 + #CONFIG.chips * (cw + gap), y + 6, W - 1 - (2 + #CONFIG.chips * (cw + gap)) + 1, 3, "INFO", "7", "0")
  -- actions
  local acts = {
    {"undo", "UNDO", "b", 1}, {"clear", "CLEAR", "e", 1}, {"rebet", "REBET", "a", 1},
    {"double", "X2", "3", 1}, {"spin", busy and "..." or "SPIN", busy and "7" or "4", 2},
  }
  local units = 0
  for _, a in ipairs(acts) do units = units + a[4] end
  local unit = (W - 2 - gap * (#acts - 1)) / units
  local x = 2
  for i, a in ipairs(acts) do
    local w = (i == #acts) and (W - x) or math.floor(unit * a[4])
    local bg = (busy and a[1] ~= "spin") and "7" or a[3]
    button(a[1], x, y + 10, w, 3, a[2], bg, a[1] == "spin" and "f" or "0")
    x = x + w + gap
  end
end

local INFO = {
  {"DOUBLE ZERO ROULETTE - PAYOUTS", "4"}, {"", "0"},
  {"STRAIGHT UP  (1 number) ........ 35 TO 1", "0"},
  {"SPLIT        (2 numbers) ....... 17 TO 1", "0"},
  {"STREET       (3 numbers) ....... 11 TO 1", "0"},
  {"TRIO         (0-1-2 / 00-2-3) .. 11 TO 1", "0"},
  {"CORNER       (4 numbers) ........ 8 TO 1", "0"},
  {"TOP LINE     (0-00-1-2-3) ....... 6 TO 1", "0"},
  {"SIX LINE     (6 numbers) ........ 5 TO 1", "0"},
  {"DOZEN / COLUMN ................. 2 TO 1", "0"},
  {"RED BLACK ODD EVEN 1-18 19-36 ... 1 TO 1", "0"},
  {"", "0"},
  {"HOW TO BET", "4"},
  {"Tap your SEAT, pick a CHIP, then tap the layout", "0"},
  {"Middle of a number = straight up", "8"},
  {"On the line between numbers = split / corner", "8"},
  {"On the bottom line of a column = street / six line", "8"},
  {"0 and 00 lose every outside bet", "e"},
  {"", "0"},
  {"- TAP ANYWHERE TO RETURN -", "8"},
}

local function draw()
  if state.info then
    clear("f")
    local y0 = math.max(1, math.floor((H - #INFO) / 2))
    for i, l in ipairs(INFO) do ctext(1, y0 + i - 1, W, l[1], l[2], "f") end
    flush(); return
  end
  clear(FELT)
  drawTitle()
  drawWheel()
  drawHistory()
  drawTable()
  drawPanel()
  flush()
end

------------------------------------------------------------------ BETTING
local function seatName(s) return CONFIG.seats[s].name end

local function addChips(seat, key, amt, quiet)
  local def = BETS[key]
  if not def then return false end
  if state.credits[seat] < amt then
    if not quiet then state.msg = seatName(seat) .. ": NOT ENOUGH CREDITS" end
    return false
  end
  local spot = 0
  for _, v in pairs(state.bets[key] or {}) do spot = spot + v end
  if spot + amt > CONFIG.maxSpot then
    if not quiet then state.msg = "TABLE LIMIT " .. fmt(CONFIG.maxSpot) .. " ON " .. def.label end
    return false
  end
  state.credits[seat] = state.credits[seat] - amt
  state.bets[key] = state.bets[key] or {}
  state.bets[key][seat] = (state.bets[key][seat] or 0) + amt
  local u = state.undo[seat]
  u[#u + 1] = { key, amt }
  return true
end

local function placeBet(key)
  local seat = state.seat
  local amt = CONFIG.chips[state.chip]
  if CONFIG.practiceMode and state.credits[seat] < amt and seatOnTable(seat) == 0 then
    state.credits[seat] = CONFIG.startCredits
    state.msg = seatName(seat) .. " REFILLED TO " .. fmt(CONFIG.startCredits) .. " (PRACTICE)"
    saveCredits(); sfx("minecraft:entity.villager.yes", 1, 1)
    return
  end
  if addChips(seat, key, amt) then
    local def = BETS[key]
    state.msg = seatName(seat) .. "  " .. fmt(amt) .. " ON " .. def.label ..
                "  (" .. def.pay .. " TO 1)"
    sfx("minecraft:block.stone_button.click_on", 0.7, 1.6)
    note("hat", 18, 0.6)
    saveCredits()
  else
    note("didgeridoo", 4, 0.8)
  end
end

local function removeAll(seat)
  local back = 0
  for key, b in pairs(state.bets) do
    if b[seat] then
      back = back + b[seat]; b[seat] = nil
      if next(b) == nil then state.bets[key] = nil end
    end
  end
  state.credits[seat] = state.credits[seat] + back
  state.undo[seat] = {}
  return back
end

local function doAction(id)
  local seat = state.seat
  if id == "undo" then
    local u = state.undo[seat]
    local last = table.remove(u)
    if last then
      local b = state.bets[last[1]]
      if b and b[seat] then
        local back = math.min(b[seat], last[2])
        b[seat] = b[seat] - back
        if b[seat] <= 0 then b[seat] = nil end
        if next(b) == nil then state.bets[last[1]] = nil end
        state.credits[seat] = state.credits[seat] + back
        state.msg = seatName(seat) .. " TOOK BACK " .. fmt(back)
      end
    else
      state.msg = seatName(seat) .. " HAS NOTHING TO UNDO"
    end
  elseif id == "clear" then
    local back = removeAll(seat)
    state.msg = back > 0 and (seatName(seat) .. " CLEARED " .. fmt(back)) or (seatName(seat) .. " HAS NO BETS")
  elseif id == "rebet" then
    local placed, n = 0, 0
    for _, b in ipairs(state.lastBets[seat]) do
      n = n + 1
      if addChips(seat, b[1], b[2], true) then placed = placed + b[2] end
    end
    state.msg = n == 0 and (seatName(seat) .. " HAS NO LAST BET")
                or (seatName(seat) .. " REBET " .. fmt(placed))
  elseif id == "double" then
    local cur = {}
    for key, b in pairs(state.bets) do if b[seat] then cur[#cur + 1] = { key, b[seat] } end end
    local added = 0
    for _, b in ipairs(cur) do if addChips(seat, b[1], b[2], true) then added = added + b[2] end end
    state.msg = added > 0 and (seatName(seat) .. " DOUBLED  +" .. fmt(added)) or (seatName(seat) .. " CAN'T DOUBLE")
  end
  saveCredits()
end

------------------------------------------------------------------ SPIN
local function spinAnim(result)
  local dt = 0.05
  local Td = CONFIG.spinTime
  local frames = math.floor(Td / dt)
  local w0 = state.rot
  local omega = 1.3
  local rel0 = math.random() * TWO_PI
  local relF = (POCKET[result] - 0.5) * SEG
  local D = ((relF - rel0) % TWO_PI) - TWO_PI * 5          -- ball runs the other way
  local lastP
  sfx("minecraft:block.grindstone.use", 0.5, 1.6)
  for f = 1, frames + 34 do
    local t = f * dt
    state.rot = w0 + omega * (t - t * t / (4 * (Td + 1.7)))
    local rel, rb
    if f <= frames then
      local u = f / frames
      rel = rel0 + D * (1 - (1 - u) ^ 2)
      if u > 0.62 then
        rel = rel + SEG * 1.4 * math.sin(u * 48) * (1 - u) / 0.38
        local s = math.min(1, (u - 0.62) / 0.2)
        s = s * s * (3 - 2 * s)
        rb = R_TRACK - (R_TRACK - R_POCKET) * s + 0.09 * math.abs(math.sin(u * 37)) * (1 - u) / 0.38
      else
        rb = R_TRACK
      end
      -- sound: rolling on the track, then clacking over the frets
      if u <= 0.62 then
        if f % 3 == 0 then note("hat", math.max(0, math.floor(20 - u * 20)), 0.35) end
      else
        local p = math.floor((rel % TWO_PI) / SEG)
        if p ~= lastP then note("snare", 12 + (p % 5), 0.6); lastP = p end
      end
      if f == frames then note("basedrum", 5, 1); sfx("minecraft:block.wood.place", 1, 1.4) end
    else
      rel, rb = relF, R_POCKET
    end
    state.ball = { a = state.rot + rel, r = rb }
    state.tick = state.tick + ((f % 6 == 0) and 1 or 0)
    draw()
    sleep(dt)
  end
  state.rot = state.rot % TWO_PI
end

local function resolve(result)
  state.result = result
  table.insert(state.history, 1, result)
  while #state.history > 16 do table.remove(state.history) end
  state.winKeys = {}
  for key, def in pairs(BETS) do if def.set[result] then state.winKeys[key] = true end end
  state.msg = numStr(result) .. " " .. colorName(result) ..
              ((result ~= 0 and result ~= DZ) and ("  " .. (result % 2 == 0 and "EVEN" or "ODD")) or "")
  -- announce
  local bigHit = false
  for key, seats in pairs(state.bets) do
    if BETS[key].set[result] and BETS[key].pay >= 17 then bigHit = true end
  end
  tune("bell", RED[result] and {12, 16, 19} or {7, 12, 16}, 0.1)
  for _ = 1, 8 do state.tick = state.tick + 1; draw(); sleep(0.2) end

  -- sweep the losers
  local stake, won = {}, {}
  for s = 1, NSEATS do stake[s], won[s] = 0, 0 end
  local losers = {}
  for key, seats in pairs(state.bets) do
    for s, amt in pairs(seats) do
      stake[s] = stake[s] + amt
      if BETS[key].set[result] then won[s] = won[s] + amt * (BETS[key].pay + 1) end
    end
    if not BETS[key].set[result] then losers[#losers + 1] = key end
  end
  for i, key in ipairs(losers) do
    state.bets[key] = nil
    if i % 3 == 0 or i == #losers then
      sfx("minecraft:block.wool.break", 0.5, 1.2); draw(); sleep(0.06)
    end
  end
  -- pay the winners
  local parts = {}
  local anyWin = false
  for s = 1, NSEATS do
    if stake[s] > 0 then
      state.credits[s] = state.credits[s] + won[s]
      local net = won[s] - stake[s]
      parts[#parts + 1] = seatName(s) .. " " .. (net >= 0 and "+" or "") .. fmt(net)
      if won[s] > 0 then anyWin = true end
    end
  end
  saveCredits()
  if #parts > 0 then state.msg = numStr(result) .. " " .. colorName(result) .. "   " .. table.concat(parts, "   ") end
  if bigHit then
    sfx("minecraft:ui.toast.challenge_complete", 1, 1)
    tune("pling", {12, 16, 19, 24, 19, 24}, 0.08)
  elseif anyWin then
    for _ = 1, 6 do sfx("minecraft:entity.experience_orb.pickup", 0.7, 0.8 + math.random() * 0.6); sleep(0.07) end
  end
  for _ = 1, 14 do state.tick = state.tick + 1; draw(); sleep(0.2) end
end

local function doSpin()
  local any = false
  for s = 1, NSEATS do
    state.lastBets[s] = {}
    state.undo[s] = {}
  end
  for key, seats in pairs(state.bets) do
    for s, amt in pairs(seats) do
      any = true
      local l = state.lastBets[s]
      l[#l + 1] = { key, amt }
    end
  end
  if not any then
    state.msg = "NO BETS ON THE TABLE - PLACE YOUR BETS"
    note("didgeridoo", 4, 0.8); draw(); return
  end
  state.phase = "spin"
  state.result, state.winKeys = nil, nil
  state.msg = "NO MORE BETS!"
  sfx("minecraft:block.bell.use", 0.8, 1.4)
  draw(); sleep(0.6)
  local result = state.force or WHEEL[math.random(38)]
  state.force = nil
  spinAnim(result)
  state.phase = "result"
  resolve(result)
  -- clear the layout
  state.bets, state.winKeys, state.result, state.ball = {}, nil, nil, nil
  state.phase = "bet"
  state.msg = "PLACE YOUR BETS"
  draw()
end

------------------------------------------------------------------ INPUT
local function onTouch(x, y)
  if state.info then state.info = false; draw(); return end
  if state.phase ~= "bet" then return end
  for _, b in ipairs(Lay.buttons or {}) do
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
      local id = b.id
      note("hat", 16, 0.5)
      if id:sub(1, 4) == "seat" then
        state.seat = tonumber(id:sub(5))
        state.msg = seatName(state.seat) .. " IS BETTING  -  " .. fmt(state.credits[state.seat]) .. " CREDITS"
      elseif id:sub(1, 4) == "chip" then
        state.chip = tonumber(id:sub(5))
        state.msg = "CHIP " .. fmt(CONFIG.chips[state.chip])
      elseif id == "info" then
        state.info = true
      elseif id == "spin" then
        doSpin(); return
      else
        doAction(id)
      end
      draw(); return
    end
  end
  local key = Lay.hit[y] and Lay.hit[y][x]
  if key then placeBet(key); draw() end
end

------------------------------------------------------------------ LOOPS
local function gameLoop()
  applyPalette()
  layout()
  draw()
  local tmr = os.startTimer(0.2)
  while true do
    local e, a, b, c = os.pullEvent()
    if e == "timer" and a == tmr then
      state.rot = (state.rot + 0.02) % TWO_PI       -- wheel idles slowly
      if state.phase == "bet" and not state.info then
        state.tick = state.tick + 1
        draw()
      end
      tmr = os.startTimer(0.2)
    elseif e == "monitor_touch" then
      onTouch(b, c)
      tmr = os.startTimer(0.2)
    elseif e == "monitor_resize" or e == "peripheral" then
      layout(); draw()
    elseif e == "credits_changed" then
      draw()
    end
  end
end

local function adminLoop()
  term.clear(); term.setCursorPos(1, 1)
  print("DOUBLE ZERO ROULETTE running on monitor")
  print("add <seat> <n> | set <seat> <n> | credits")
  print("next <num> | exit      (seats 1-" .. NSEATS .. ")")
  while true do
    write("> ")
    local line = read() or ""
    local cmd, a1, a2 = line:match("^(%S*)%s*(%S*)%s*(%S*)")
    local s, n = tonumber(a1), tonumber(a2)
    if (cmd == "add" or cmd == "set") and s and n and state.credits[s] then
      state.credits[s] = (cmd == "add" and state.credits[s] or 0) + n
      saveCredits(); os.queueEvent("credits_changed")
      print(seatName(s) .. ": " .. state.credits[s])
    elseif cmd == "credits" then
      for i = 1, NSEATS do print(i .. " " .. seatName(i) .. ": " .. state.credits[i]) end
    elseif cmd == "next" and (a1 == "00" or (s and s >= 0 and s <= 36)) then
      state.force = (a1 == "00") and DZ or s
      print("Next spin lands on " .. a1)
    elseif cmd == "exit" then
      return
    elseif cmd ~= "" then
      print("?  add <seat> <n> | set <seat> <n> | credits | next <num> | exit")
    end
  end
end

if _ROULETTE_TEST then
  _ROULETTE_TEST({ layout = layout, draw = draw, BETS = function() return BETS end, Lay = Lay, T = T,
                   state = state, onTouch = onTouch, doSpin = doSpin, WHEEL = WHEEL, RED = RED,
                   PAYS = PAYS, placeBet = placeBet, numberCell = numberCell })
  return
end

loadCredits()
parallel.waitForAny(gameLoop, adminLoop)
restorePalette()
mon.setBackgroundColor(colors.black); mon.clear()
print("Roulette stopped.")
