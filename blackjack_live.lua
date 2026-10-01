--[[
  blackjack.lua  -  CC:Tweaked blackjack table, REAL MONEY (EconomyCraft)
  ---------------------------------------------------------------
  * Runs on a COMMAND COMPUTER (needed to move EconomyCraft money)
  * Needs casino_bank.lua in the same folder
  * Floor-mounted ADVANCED monitor (facing up) that players walk on
  * One Advanced Peripherals PLAYER DETECTOR per seat, all on wired modems
      - right-click your seat's detector to SIT
      - place chips, right-click again to lock in (READY)
      - with no bet placed, right-click to LEAVE
  * All bets go to the HOUSE account (the owner's balance); all wins come out of it
  * Dealer HITS soft 17, STANDS on hard 17; BJ pays 3:2; double; split to 4 hands
  * Side bets: TRILUX and BLAZING 7s
  * Owner console on the computer itself (PIN protected): limits, seats, open/close, stats

  Recommended monitor: 8 wide x 4 deep (or bigger) at text scale 0.5.
]]

local bank = require("casino_bank")
local net  = require("casino_net")

local CONFIG = {
  textScale   = 0.5,
  decks       = 6,
  penetration = 0.75,   -- reshuffle after 75% of the shoe is dealt
  bjPays      = 1.5,    -- 3:2
  maxHands    = 4,      -- split up to 4 hands
  dealerPeek  = true,   -- dealer checks for blackjack under A / 10
  dealDelay   = 0.35,
  turnTimeout = 45,     -- seconds before an idle player auto-stands
  resultWait  = 30,     -- seconds before the next hand starts on its own

  -- Payouts are "X to 1". Change these to match your casino's paytable.
  trilux = {            -- player's first 2 cards + dealer up card
    suitedTrips   = 100,
    straightFlush = 40,
    trips         = 30,
    straight      = 10,
    flush         = 5,
  },
  blazing7s = {         -- number of 7s in player's first 2 cards + dealer up card
    suited3 = 1000,     -- three 7s, all same suit
    three   = 100,
    two     = 10,
    one     = 2,
  },
}

local CHIPS = {
  { v = 1,    l = "1",   bg = colors.white,  fg = colors.black },
  { v = 5,    l = "5",   bg = colors.red,    fg = colors.white },
  { v = 25,   l = "25",  bg = colors.lime,   fg = colors.black },
  { v = 100,  l = "100", bg = colors.black,  fg = colors.white },
  { v = 1000, l = "1K",  bg = colors.purple, fg = colors.white },
}

---------------------------------------------------------------------
-- owner settings (saved on this computer, changed from the console)
---------------------------------------------------------------------
local SETTINGS_FILE = "blackjack.cfg"
local S = {
  house     = "",      -- EconomyCraft account that backs the table
  pin       = "",
  seats     = 4,
  mainMin   = 1,
  mainMax   = 1000,
  sideMin   = 25,
  sideMax   = 100,
  open      = true,
  ecoPrefix = "eco",
  balCmd    = "bal",
  detectors = {},      -- [peripheral name] = seat number
}

local function loadSettings()
  if not fs.exists(SETTINGS_FILE) then return end
  local f = fs.open(SETTINGS_FILE, "r")
  local t = textutils.unserialize(f.readAll())
  f.close()
  if type(t) == "table" then for k, v in pairs(t) do S[k] = v end end
end

local function saveSettings()
  local f = fs.open(SETTINGS_FILE, "w")
  f.write(textutils.serialize(S))
  f.close()
end

local function applyBankConfig()
  bank.config({ house = S.house, prefix = S.ecoPrefix, balCmd = S.balCmd })
end

-- shared by the console and the main computer
local LIMIT_KEYS = { mainMin = true, mainMax = true, sideMin = true, sideMax = true, seats = true }
local function setLimit(key, val)
  if not LIMIT_KEYS[key] then return false, "unknown setting" end
  if not val or val < 1 or val ~= math.floor(val) then return false, "must be a whole number 1 or more" end
  local old = S[key]
  S[key] = val
  if S.mainMin > S.mainMax or S.sideMin > S.sideMax or S.seats > 6 then
    S[key] = old
    return false, "min can't be above max (seats 1-6)"
  end
  saveSettings()
  os.queueEvent("casino_settings")
  return true
end

local function setOpen(open)
  S.open = open and true or false
  saveSettings()
  os.queueEvent("casino_settings")
end

net.setupGame({
  kind = "Blackjack",
  status = function()
    return {
      open = S.open,
      limits = {
        { k = "mainMin", label = "MIN",      v = S.mainMin },
        { k = "mainMax", label = "MAX",      v = S.mainMax },
        { k = "sideMin", label = "SIDE MIN", v = S.sideMin },
        { k = "sideMax", label = "SIDE MAX", v = S.sideMax },
      },
    }
  end,
  set = setLimit,
  setOpen = setOpen,
})

local function topMult(t) local m = 0; for _, v in pairs(t) do m = math.max(m, v) end; return m end
local TRI_TOP, B7_TOP = topMult(CONFIG.trilux), topMult(CONFIG.blazing7s)

---------------------------------------------------------------------
-- peripherals
---------------------------------------------------------------------
local mon = peripheral.find("monitor")
if not mon then error("No monitor found. Attach an advanced monitor.", 0) end
if not mon.isColor() then error("Needs an ADVANCED (gold) monitor for touch + colour.", 0) end
mon.setTextScale(CONFIG.textScale)
local monName = peripheral.getName(mon)
local W, H = mon.getSize()
if W < 64 or H < 20 then
  error(("Monitor too small (%dx%d). Build it at least 8 wide x 4 deep."):format(W, H), 0)
end
local scr = window.create(mon, 1, 1, W, H, true)
local spk = peripheral.find("speaker")
math.randomseed(os.epoch("utc"))

local function snd(inst, pitch)
  if spk then pcall(spk.playNote, inst or "hat", 0.7, pitch or 12) end
end

local mapping = false   -- true while the owner is re-mapping detectors

---------------------------------------------------------------------
-- drawing helpers
---------------------------------------------------------------------
local FELT = colors.green
local SEATCOL = { colors.red, colors.blue, colors.orange, colors.purple, colors.cyan, colors.magenta }

local buttons = {}
local function addHit(x1, y1, x2, y2, action) buttons[#buttons + 1] = { x1, y1, x2, y2, action } end

local function trim(s, w) if #s > w then return s:sub(1, math.max(0, w)) end return s end

local function fill(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  scr.setBackgroundColor(bg)
  local s = string.rep(" ", w)
  for yy = y, y + h - 1 do scr.setCursorPos(x, yy); scr.write(s) end
end

local function txt(x, y, s, fg, bg)
  scr.setCursorPos(x, y)
  scr.setTextColor(fg or colors.white)
  scr.setBackgroundColor(bg or FELT)
  scr.write(s)
end

local function ctxt(x, w, y, s, fg, bg)
  s = trim(s, w)
  txt(x + math.floor((w - #s) / 2), y, s, fg, bg)
end

-- small 1-row button; hit box grows `padUp` rows upward so it's easier to tap on the floor
local function button(x, y, label, fg, bg, action, padUp)
  local w = #label + 2
  fill(x, y, w, 1, bg)
  txt(x + 1, y, label, fg, bg)
  if action then addHit(x, y - (padUp or 0), x + w - 1, y, action) end
  return w
end

local function bigButton(x, y, w, h, label, fg, bg, action)
  fill(x, y, w, h, bg)
  label = trim(label, w)
  txt(x + math.floor((w - #label) / 2), y + math.floor((h - 1) / 2), label, fg, bg)
  if action then addHit(x, y, x + w - 1, y + h - 1, action) end
end

-- 3x5 block font for the dealer total (each pixel is 2 characters wide)
local BIG = {
  ["0"] = { "###", "# #", "# #", "# #", "###" },
  ["1"] = { " # ", "## ", " # ", " # ", "###" },
  ["2"] = { "###", "  #", "###", "#  ", "###" },
  ["3"] = { "###", "  #", " ##", "  #", "###" },
  ["4"] = { "# #", "# #", "###", "  #", "  #" },
  ["5"] = { "###", "#  ", "###", "  #", "###" },
  ["6"] = { "###", "#  ", "###", "# #", "###" },
  ["7"] = { "###", "  #", "  #", "  #", "  #" },
  ["8"] = { "###", "# #", "###", "# #", "###" },
  ["9"] = { "###", "# #", "###", "  #", "###" },
  ["B"] = { "## ", "# #", "## ", "# #", "## " },
  ["J"] = { "  #", "  #", "  #", "# #", "###" },
}
local function bigWidth(s) return #s * 8 - 2 end
local function drawBig(x, y, s, col)
  for i = 1, #s do
    local g = BIG[s:sub(i, i)]
    if g then
      for r = 1, 5 do
        for c = 1, 3 do
          if g[r]:sub(c, c) == "#" then fill(x + (i - 1) * 8 + (c - 1) * 2, y + r - 1, 2, 1, col) end
        end
      end
    end
  end
end

---------------------------------------------------------------------
-- cards / shoe
---------------------------------------------------------------------
local RANK = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
local SUIT = { "\3", "\4", "\5", "\6" }   -- hearts, diamonds, clubs, spades
local TIERS = {
  { w = 4,  h = 3 },
  { w = 5,  h = 4 },
  { w = 7,  h = 5 },
  { w = 9,  h = 7 },
  { w = 11, h = 8 },
  { w = 13, h = 10 },
}
local PIPS = {
  [2]  = { {1,0},{1,4} },
  [3]  = { {1,0},{1,2},{1,4} },
  [4]  = { {0,0},{2,0},{0,4},{2,4} },
  [5]  = { {0,0},{2,0},{1,2},{0,4},{2,4} },
  [6]  = { {0,0},{2,0},{0,2},{2,2},{0,4},{2,4} },
  [7]  = { {0,0},{2,0},{1,1},{0,2},{2,2},{0,4},{2,4} },
  [8]  = { {0,0},{2,0},{1,1},{0,2},{2,2},{1,3},{0,4},{2,4} },
  [9]  = { {0,0},{2,0},{0,1},{2,1},{1,2},{0,3},{2,3},{0,4},{2,4} },
  [10] = { {0,0},{2,0},{0,1},{2,1},{1,1},{1,3},{0,3},{2,3},{0,4},{2,4} },
}

local shoe, cutAt = {}, 0
local function newShoe()
  shoe = {}
  for _ = 1, CONFIG.decks do
    for s = 1, 4 do for r = 1, 13 do shoe[#shoe + 1] = { r = r, s = s } end end
  end
  for i = #shoe, 2, -1 do
    local j = math.random(i)
    shoe[i], shoe[j] = shoe[j], shoe[i]
  end
  cutAt = math.floor(#shoe * (1 - CONFIG.penetration))
end
local function drawCard()
  if #shoe == 0 then newShoe() end
  return table.remove(shoe)
end

local function cardVal(c)
  if c.r == 1 then return 1 elseif c.r >= 10 then return 10 end
  return c.r
end

local function handValue(cards)
  local t, ace = 0, false
  for _, c in ipairs(cards) do
    t = t + cardVal(c)
    if c.r == 1 then ace = true end
  end
  if ace and t + 10 <= 21 then return t + 10, true end
  return t, false
end

local function isBJ(cards) return #cards == 2 and handValue(cards) == 21 end

local function valueStr(cards, natural)
  local v, soft = handValue(cards)
  if natural and isBJ(cards) then return "BJ" end
  if v > 21 then return "BUST " .. v end
  if soft and v < 21 then return (v - 10) .. "/" .. v end
  return tostring(v)
end

local function paintCard(x, y, c, faceDown, T)
  local cw, ch = T.w, T.h
  if faceDown then
    fill(x, y, cw, ch, colors.blue)
    local pat = string.rep("\127", cw - 2)
    for r = 1, math.max(1, ch - 2) do txt(x + 1, y + r, pat, colors.lightBlue, colors.blue) end
    return
  end
  local fg = (c.s <= 2) and colors.red or colors.black
  local W_ = colors.white
  local r, su = RANK[c.r], SUIT[c.s]
  fill(x, y, cw, ch, W_)
  txt(x, y, r, fg, W_)
  txt(x, y + 1, su, fg, W_)
  txt(x + cw - #r, y + ch - 1, r, fg, W_)
  if ch >= 4 then txt(x + cw - 1, y + ch - 2, su, fg, W_) end

  local mx, my = x + math.floor(cw / 2), y + math.floor(ch / 2)
  local big = cw >= 9 and ch >= 7
  if c.r >= 2 and c.r <= 10 and big then
    local iw, ih = cw - 4, ch - 2
    for _, p in ipairs(PIPS[c.r]) do
      txt(x + 2 + math.floor(p[1] * (iw - 1) / 2), y + 1 + math.floor(p[2] * (ih - 1) / 4), su, fg, W_)
    end
  elseif c.r >= 11 and cw >= 7 then
    local fx, fy, fw, fh = x + 2, y + 1, cw - 4, ch - 2
    local panel = c.r == 13 and colors.yellow or (c.r == 12 and colors.pink or colors.lightBlue)
    fill(fx, fy, fw, fh, panel)
    txt(mx - 1, my, su .. r .. su, fg, panel)
  elseif c.r == 1 and big then
    txt(mx - 1, my - 1, " " .. su .. " ", fg, W_)
    txt(mx - 1, my, su .. su .. su, fg, W_)
    txt(mx - 1, my + 1, " " .. su .. " ", fg, W_)
  elseif cw >= 5 and ch >= 4 then
    txt(mx, my, su, fg, W_)
  end
end

local function paintHand(x, y, maxW, cards, hideSecond, T)
  local n = #cards
  local step = T.w + 1
  if n > 1 and (n - 1) * step + T.w > maxW then
    step = math.max(2, math.floor((maxW - T.w) / (n - 1)))
  end
  for i, c in ipairs(cards) do paintCard(x + (i - 1) * step, y, c, hideSecond and i == 2, T) end
end

---------------------------------------------------------------------
-- side bet evaluation
---------------------------------------------------------------------
local function evalTrilux(cs)
  local r = { cs[1].r, cs[2].r, cs[3].r }
  table.sort(r)
  local flush = cs[1].s == cs[2].s and cs[2].s == cs[3].s
  local trips = r[1] == r[3]
  local straight = (r[1] + 1 == r[2] and r[2] + 1 == r[3]) or (r[1] == 1 and r[2] == 12 and r[3] == 13)
  local P = CONFIG.trilux
  if trips and flush then return "Suit Trips", P.suitedTrips end
  if straight and flush then return "St Flush", P.straightFlush end
  if trips then return "Trips", P.trips end
  if straight then return "Straight", P.straight end
  if flush then return "Flush", P.flush end
end

local function evalBlazing(cs)
  local n, suit, same = 0, nil, true
  for _, c in ipairs(cs) do
    if c.r == 7 then
      n = n + 1
      if suit and suit ~= c.s then same = false end
      suit = c.s
    end
  end
  local P = CONFIG.blazing7s
  if n == 3 and same then return "Suited 777", P.suited3 end
  if n == 3 then return "777", P.three end
  if n == 2 then return "Two 7s", P.two end
  if n == 1 then return "One 7", P.one end
end

---------------------------------------------------------------------
-- table state
---------------------------------------------------------------------
local nSeats, PW, OFF = 0, 0, 0
local SEAT_TOP, CY, HAND_AREA = 14, 0, 0
local SEAT_T, DEALER_T = 1, 1
local seats = {}
local dealer, hideHole = {}, true
local msg, phase = "", "bet"
local turnSeat, turnHand = 0, 0

-- Rows above the seats: header, "DEALER", dealer cards, gap,
-- 5-row band (big dealer total + buttons), message line, rules line, gap.
local function computeLayout(n)
  local pw = math.min(44, math.floor(W / n))
  local w = pw - 1
  if w < 23 then return nil end
  local st = 1
  for t = #TIERS, 1, -1 do
    if 3 * TIERS[t].w + 3 <= w then st = t; break end
  end
  local dt = math.min(#TIERS, st + 2)
  local cy = H - 6
  while true do
    local top = TIERS[dt].h + 12
    local area = cy - (top + 3)
    if area >= TIERS[st].h + 1 then
      return { pw = pw, off = math.floor((W - pw * n) / 2), st = st, dt = dt, top = top, cy = cy, area = area }
    end
    if dt > st then dt = dt - 1
    elseif st > 1 then st = st - 1; dt = st
    else return nil end
  end
end
local function fits(n) return computeLayout(n) ~= nil end
local function seatX(i) return OFF + 1 + (i - 1) * PW end

local function tierForHands(k)
  for t = SEAT_T, 1, -1 do
    if k * (TIERS[t].h + 1) <= HAND_AREA then return t end
  end
end

local function newSeat()
  return { name = nil, bal = 0, main = 0, tri = 0, b7 = 0, hands = {}, side = {},
           playing = false, ready = false, wagered = 0, returned = 0, owed = 0 }
end

local function setupSeats(n)
  n = math.max(1, math.min(6, n))
  while n > 1 and not fits(n) do n = n - 1 end
  local L = computeLayout(n)
  nSeats = n
  PW, OFF = L.pw, L.off
  SEAT_T, DEALER_T = L.st, L.dt
  SEAT_TOP, CY, HAND_AREA = L.top, L.cy, L.area
  local old = seats
  seats = {}
  for i = 1, n do seats[i] = old[i] or newSeat() end
end

local function clearSeat(s)
  local fresh = newSeat()
  for k in pairs(s) do s[k] = nil end
  for k, v in pairs(fresh) do s[k] = v end
end

local function seatForDetector(dev)
  local i = S.detectors[dev]
  if i and i <= nSeats then return i end
end

---------------------------------------------------------------------
-- money helpers
---------------------------------------------------------------------
local function refreshBal(s)
  if s.name then s.bal = bank.balance(s.name) or s.bal end
end

-- player -> house mid-hand (double / split)
local function takeFrom(s, amt)
  local ok, err = bank.take(s.name, amt)
  if ok then s.wagered = s.wagered + amt end
  refreshBal(s)
  return ok, err
end

-- house -> player
local function payOut(s, amt)
  amt = math.floor(amt)
  if amt <= 0 then return end
  local ok, err = bank.pay(s.name, amt)
  if ok then
    s.returned = s.returned + amt
  else
    s.owed = s.owed + amt
    bank.owe("blackjack", s.name, amt, err)
    msg = "PAYOUT FAILED for " .. s.name .. " - IOU logged"
  end
end

-- worst case the house could lose to this seat in one round
local function exposure(s)
  return s.main * 8 + s.tri * TRI_TOP + s.b7 * B7_TOP
end

---------------------------------------------------------------------
-- rendering
---------------------------------------------------------------------
local function dealerTotal()
  if hideHole then
    return tostring((handValue({ dealer[1] }))), "SHOWING", colors.yellow
  end
  local v, soft = handValue(dealer)
  if isBJ(dealer) then return "BJ", "BLACKJACK", colors.yellow end
  if v > 21 then return tostring(v), "BUST", colors.red end
  return tostring(v), soft and "SOFT" or "DEALER", colors.yellow
end

local function drawDealerArea()
  local DT = TIERS[DEALER_T]
  fill(1, 1, W, 1, colors.gray)
  txt(2, 1, "BLACKJACK", colors.yellow, colors.gray)
  if not S.open then txt(13, 1, " TABLE CLOSED ", colors.white, colors.red) end
  local info = ("Bets $%d-$%d   Shoe %d "):format(S.mainMin, S.mainMax, #shoe)
  txt(W - #info, 1, info, colors.lightGray, colors.gray)

  ctxt(1, W, 2, "DEALER", colors.white, FELT)
  if #dealer > 0 then
    local width = #dealer * (DT.w + 1) - 1
    paintHand(math.max(1, math.floor((W - width) / 2) + 1), 3, W - 2, dealer, hideHole, DT)
  end

  -- the band between the dealer and the players
  local band = 4 + DT.h
  local ctrls
  if phase == "bet" then
    ctrls = { { "DEAL", 16, colors.black, colors.lime, { t = "deal" } } }
  elseif phase == "result" then
    ctrls = { { "NEXT HAND", 17, colors.black, colors.lime, { t = "next" } } }
  end
  local leftOfButtons = W
  if ctrls then
    local total = -2
    for _, c in ipairs(ctrls) do total = total + c[2] + 2 end
    local x = (#dealer > 0) and (W - total - 1) or (math.floor((W - total) / 2) + 1)
    leftOfButtons = x - 2
    for _, c in ipairs(ctrls) do
      bigButton(x, band + 1, c[2], 3, c[1], c[3], c[4], c[5])
      x = x + c[2] + 2
    end
  end

  if #dealer > 0 then
    local str, label, col = dealerTotal()
    local nw = bigWidth(str)
    local nx = math.floor((leftOfButtons - nw) / 2) + 1
    drawBig(nx, band, str, col)
    txt(math.max(1, nx - #label - 3), band + 2, label, colors.white, FELT)
  end

  ctxt(1, W, band + 5, msg, colors.white, FELT)
  ctxt(1, W, band + 6, ("BJ PAYS 3:2 - DEALER HITS SOFT 17 - SIDE BETS $%d-$%d"):format(S.sideMin, S.sideMax),
    colors.lime, FELT)
end

local function drawSeat(i)
  local s = seats[i]
  local x, w = seatX(i), PW - 1
  local active = (phase == "play" and turnSeat == i)

  -- header
  local hbg = active and colors.yellow or (s.name and SEATCOL[i] or colors.gray)
  local hfg = active and colors.black or colors.white
  fill(x, SEAT_TOP, w, 1, hbg)
  local b = s.name and ("$" .. s.bal .. " ") or ""
  local title = s.name and (s.name .. (active and " \16 TURN" or "")) or ("SEAT " .. i .. " - OPEN")
  txt(x + 1, SEAT_TOP, trim(title, w - #b - 2), hfg, hbg)
  if #b > 0 then txt(x + w - #b, SEAT_TOP, b, hfg, hbg) end

  -- side bet results
  for k = 1, 2 do
    local line = s.side[k]
    if line then txt(x, SEAT_TOP + k, trim(line[1], w), line[2] and colors.yellow or colors.lightGray, FELT) end
  end

  -- hands
  local cy = CY
  if #s.hands > 0 then
    local T = TIERS[tierForHands(#s.hands) or 1]
    local hh = T.h + 1
    local hy = cy - #s.hands * hh
    for h, hand in ipairs(s.hands) do
      local y = hy + (h - 1) * hh
      if active and turnHand == h then
        txt(x, y + math.floor(T.h / 2), "\16", colors.yellow, FELT)
      end
      paintHand(x + 1, y, w - 1, hand.cards, false, T)
      local label = valueStr(hand.cards, not hand.fromSplit) .. " $" .. hand.bet
      local fg = colors.white
      if hand.result then
        label = label .. " " .. hand.result
        if hand.result:find("WIN") or hand.result:find("BJ") then fg = colors.yellow
        elseif hand.result == "PUSH" then fg = colors.lightGray
        else fg = colors.red end
      end
      txt(x + 1, y + T.h, trim(label, w - 1), fg, FELT)
    end
  end

  -- controls
  if not s.name then
    txt(x, cy, "OPEN SEAT", colors.lightGray, FELT)
    txt(x, cy + 2, trim("Right-click the player", w), colors.white, FELT)
    txt(x, cy + 3, trim("detector to sit down", w), colors.white, FELT)
  elseif phase == "bet" then
    local function betLine(y, label, key)
      txt(x, y, trim(label .. " $" .. s[key], w), colors.white, FELT)
      local bx = x
      for _, c in ipairs(CHIPS) do
        local cw = #c.l + 2
        if bx + cw > x + w - 4 then break end
        if s.ready then button(bx, y + 1, c.l, colors.gray, colors.lightGray, nil)
        else button(bx, y + 1, c.l, c.fg, c.bg, { t = "bet", seat = i, k = key, amt = c.v }, 1) end
        bx = bx + cw
      end
      if not s.ready then button(bx + 1, y + 1, "X", colors.white, colors.red, { t = "clr", seat = i, k = key }, 1) end
    end
    betLine(cy, "MAIN", "main")
    betLine(cy + 2, "TRILUX", "tri")
    betLine(cy + 4, "BLAZING 7s", "b7")
    if s.ready then txt(x, cy + 6, trim("\4 READY - bet locked", w), colors.lime, FELT)
    elseif s.main > 0 then txt(x, cy + 6, trim("Right-click detector: READY", w), colors.yellow, FELT)
    else txt(x, cy + 6, trim("Right-click detector: LEAVE", w), colors.lightGray, FELT) end
  elseif active then
    local hand = s.hands[turnHand]
    local c = hand.cards
    local canDouble = #c == 2 and s.bal >= hand.bet and not hand.splitAce
    local canSplit = #c == 2 and cardVal(c[1]) == cardVal(c[2]) and #s.hands < CONFIG.maxHands and s.bal >= hand.bet
      and tierForHands(#s.hands + 1) ~= nil
    local bw = math.floor((w - 1) / 2)
    bigButton(x, cy, bw, 3, "HIT", colors.black, colors.lime, { t = "hit" })
    bigButton(x + bw + 1, cy, bw, 3, "STAND", colors.white, colors.red, { t = "stand" })
    bigButton(x, cy + 4, bw, 3, "DOUBLE", canDouble and colors.black or colors.gray,
      canDouble and colors.orange or colors.lightGray, canDouble and { t = "double" } or nil)
    bigButton(x + bw + 1, cy + 4, bw, 3, "SPLIT", canSplit and colors.black or colors.gray,
      canSplit and colors.lightBlue or colors.lightGray, canSplit and { t = "split" } or nil)
  elseif not s.playing then
    txt(x, cy, "Sitting out", colors.lightGray, FELT)
  else
    txt(x, cy, trim("Main $" .. s.main, w), colors.white, FELT)
    txt(x, cy + 1, trim("Trilux $" .. s.tri, w), colors.white, FELT)
    txt(x, cy + 2, trim("Blazing 7s $" .. s.b7, w), colors.white, FELT)
    if phase == "result" then
      local net = s.returned + s.owed - s.wagered
      local ns = net > 0 and ("Round +$" .. net) or (net < 0 and ("Round -$" .. -net) or "Round even")
      txt(x, cy + 4, ns, net > 0 and colors.yellow or (net < 0 and colors.red or colors.lightGray), FELT)
    end
  end
end

local function render()
  buttons = {}
  scr.setVisible(false)
  scr.setBackgroundColor(FELT)
  scr.clear()
  drawDealerArea()
  for i = 1, nSeats do drawSeat(i) end
  scr.setVisible(true)
end

local function pause(t) render(); sleep(t or CONFIG.dealDelay) end

---------------------------------------------------------------------
-- input
---------------------------------------------------------------------
local function waitAction(timeout)
  local timer = timeout and os.startTimer(timeout)
  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "monitor_touch" and a == monName then
      for i = #buttons, 1, -1 do
        local bt = buttons[i]
        if b >= bt[1] and b <= bt[3] and c >= bt[2] and c <= bt[4] then return bt[5] end
      end
    elseif ev == "playerClick" and not mapping then
      local seat = seatForDetector(b)
      if seat then return { t = "detector", seat = seat, name = a } end
    elseif ev == "timer" and a == timer then
      return { t = "timeout" }
    elseif ev == "casino_settings" then
      return { t = "refresh" }
    end
  end
end

-- sit / ready / leave, driven by right-clicking a seat's player detector
local function handleDetector(a)
  local s = seats[a.seat]
  if not s or not bank.validName(a.name) then return end
  local name = a.name
  if not s.name then
    for j, o in ipairs(seats) do
      if o.name == name then
        if o.playing then msg = name .. " is still in a hand at seat " .. j; return end
        clearSeat(o)
      end
    end
    s.name = name
    refreshBal(s)
    msg = name .. " sits at seat " .. a.seat
    snd("pling", 16)
  elseif s.name ~= name then
    msg = "Seat " .. a.seat .. " belongs to " .. s.name
  elseif s.playing then
    msg = name .. ": finish your hand first"
  elseif phase == "bet" and s.ready then
    s.ready = false
    msg = name .. " unlocked their bet"
  elseif phase == "bet" and s.main > 0 then
    refreshBal(s)
    local tot = s.main + s.tri + s.b7
    if s.main < S.mainMin or s.main > S.mainMax then
      msg = ("%s: main bet must be $%d-$%d"):format(name, S.mainMin, S.mainMax)
    elseif tot > s.bal then
      msg = name .. ": not enough money ($" .. s.bal .. ")"
    else
      s.ready = true
      msg = name .. " is READY"
      snd("bell", 14)
    end
  else
    clearSeat(s)
    msg = name .. " left the table"
  end
end

---------------------------------------------------------------------
-- round phases
---------------------------------------------------------------------
local function clampBet(v, lo, hi)
  if v <= 0 then return 0 end
  return math.max(lo, math.min(hi, v))
end

local function bettingPhase(keepMsg)
  phase, dealer, hideHole, turnSeat = "bet", {}, true, 0
  if S.seats ~= nSeats then setupSeats(S.seats) end
  for _, s in ipairs(seats) do
    s.hands, s.side, s.playing, s.ready = {}, {}, false, false
    s.wagered, s.returned, s.owed = 0, 0, 0
    s.main = clampBet(s.main, S.mainMin, S.mainMax)
    s.tri  = clampBet(s.tri, S.sideMin, S.sideMax)
    s.b7   = clampBet(s.b7, S.sideMin, S.sideMax)
    refreshBal(s)
    if s.main + s.tri + s.b7 > s.bal then s.main, s.tri, s.b7 = 0, 0, 0 end
  end
  if #shoe <= cutAt then newShoe(); msg = "New shoe shuffled - place your bets"
  elseif keepMsg then msg = keepMsg
  else msg = "Place bets, then right-click your detector to lock in" end

  while true do
    render()
    local a = waitAction()
    local s = a.seat and seats[a.seat]
    if a.t == "refresh" then
      if S.seats ~= nSeats then setupSeats(S.seats) end
    elseif a.t == "detector" then
      handleDetector(a)
    elseif a.t == "bet" and s and s.name and not s.ready then
      local cur = s[a.k]
      local isMain = a.k == "main"
      local minB = isMain and S.mainMin or S.sideMin
      local maxB = isMain and S.mainMax or S.sideMax
      local target = math.max(minB, math.min(maxB, cur + a.amt))
      local free = s.bal - (s.main + s.tri + s.b7)
      if target == cur then msg = s.name .. ": table max is $" .. maxB
      elseif target - cur > free then msg = s.name .. ": not enough money"
      else s[a.k] = target; snd("hat", 14) end
    elseif a.t == "clr" and s and not s.ready then
      s[a.k] = 0
      if a.k == "main" then s.tri, s.b7 = 0, 0 end
    elseif a.t == "deal" then
      if not S.open then
        msg = "Table is closed"
      else
        local any, bad = false, nil
        for _, st in ipairs(seats) do
          if st.ready then
            if st.main <= 0 and st.tri + st.b7 > 0 then bad = st.name else any = true end
          end
        end
        if bad then msg = bad .. ": side bets need a main bet"
        elseif not any then msg = "Nobody is READY - right-click your detector to lock in"
        else return "deal" end
      end
    end
  end
end

local function dealRound()
  phase = "deal"
  local ready = {}
  for i, s in ipairs(seats) do
    if s.ready and s.name and s.main >= S.mainMin and s.main <= S.mainMax then ready[#ready + 1] = i end
  end
  if #ready == 0 then return nil, "Nobody is ready" end

  local hb = bank.balance(S.house)
  if not hb then return nil, "Can't read the house balance - tell the owner" end
  local need = 0
  for _, i in ipairs(ready) do need = need + exposure(seats[i]) end
  if need > hb then
    return nil, "House can't cover these bets right now - lower the side bets"
  end

  msg = "Collecting bets..."
  render()
  local active = {}
  for _, i in ipairs(ready) do
    local s = seats[i]
    local tot = s.main + s.tri + s.b7
    local ok, err = bank.take(s.name, tot)
    if ok then
      s.playing, s.wagered = true, tot
      s.hands = { { cards = {}, bet = s.main } }
      active[#active + 1] = i
    else
      s.ready = false
      msg = s.name .. ": " .. tostring(err)
    end
    refreshBal(s)
  end
  if #active == 0 then return nil, msg end

  msg = "Dealing..."
  for _ = 1, 2 do
    for _, i in ipairs(active) do
      table.insert(seats[i].hands[1].cards, drawCard()); snd("hat", 10); pause()
    end
    table.insert(dealer, drawCard()); snd("hat", 8); pause()
  end
  return active
end

local function settleSides(active)
  local up = dealer[1]
  local anySide = false
  for _, i in ipairs(active) do
    local s = seats[i]
    local c = s.hands[1].cards
    local three = { c[1], c[2], up }
    local pay = 0
    if s.tri > 0 then
      anySide = true
      local name, mult = evalTrilux(three)
      if name then
        local win = s.tri * mult
        pay = pay + s.tri + win
        s.side[1] = { "TRI " .. name .. " +" .. win, true }
        snd("bell", 18)
      else s.side[1] = { "TRI no win", false } end
    end
    if s.b7 > 0 then
      anySide = true
      local name, mult = evalBlazing(three)
      if name then
        local win = s.b7 * mult
        pay = pay + s.b7 + win
        s.side[2] = { "B7 " .. name .. " +" .. win, true }
        snd("bell", 20)
      else s.side[2] = { "B7 no win", false } end
    end
    if pay > 0 then payOut(s, pay); refreshBal(s) end
  end
  if anySide then msg = "Side bets paid"; pause(1.2) end
end

local function playTurns(active)
  phase = "play"
  for _, i in ipairs(active) do
    local s = seats[i]
    local h = 1
    while h <= #s.hands do
      local hand = s.hands[h]
      turnSeat, turnHand = i, h
      if #hand.cards == 1 then
        table.insert(hand.cards, drawCard()); snd("hat", 10); pause()
      end
      if hand.splitAce then hand.done = true end
      if isBJ(hand.cards) and not hand.fromSplit then
        msg = s.name .. " has BLACKJACK!"; snd("bell", 16); pause(0.9)
        hand.done = true
      elseif handValue(hand.cards) == 21 then
        hand.done = true
      end

      while not hand.done do
        msg = s.name .. (#s.hands > 1 and (" - hand " .. h) or "") .. ": hit or stand?"
        render()
        local a = waitAction(CONFIG.turnTimeout)
        if a.t == "timeout" then
          hand.done = true
          msg = s.name .. " took too long - stands"; pause(0.8)
        elseif a.t == "detector" then
          handleDetector(a)
        elseif a.t == "hit" then
          table.insert(hand.cards, drawCard()); snd("hat", 12)
          local v = handValue(hand.cards)
          if v > 21 then hand.done = true; hand.result = "BUST"; msg = s.name .. " busts"; snd("bass", 4); pause(0.7)
          elseif v == 21 then hand.done = true; pause() end
        elseif a.t == "stand" then
          hand.done = true
        elseif a.t == "double" and #hand.cards == 2 and not hand.splitAce then
          local ok, err = takeFrom(s, hand.bet)
          if not ok then
            msg = s.name .. ": " .. tostring(err); pause(1)
          else
            hand.bet = hand.bet * 2
            table.insert(hand.cards, drawCard()); snd("hat", 12)
            hand.done = true
            if handValue(hand.cards) > 21 then hand.result = "BUST"; snd("bass", 4) end
            msg = s.name .. " doubles"; pause(0.8)
          end
        elseif a.t == "split" and #hand.cards == 2 and cardVal(hand.cards[1]) == cardVal(hand.cards[2])
          and #s.hands < CONFIG.maxHands and tierForHands(#s.hands + 1) then
          local ok, err = takeFrom(s, hand.bet)
          if not ok then
            msg = s.name .. ": " .. tostring(err); pause(1)
          else
            local moved = table.remove(hand.cards, 2)
            local aces = moved.r == 1
            hand.fromSplit, hand.splitAce = true, aces
            table.insert(s.hands, h + 1, { cards = { moved }, bet = hand.bet, fromSplit = true, splitAce = aces })
            table.insert(hand.cards, drawCard()); snd("hat", 12); pause()
            if aces or handValue(hand.cards) == 21 then hand.done = true end
          end
        end
      end
      h = h + 1
    end
  end
  turnSeat, turnHand = 0, 0
end

local function dealerPlay(active)
  phase = "dealer"
  hideHole = false
  msg = "Dealer reveals"; snd("hat", 8); pause(0.9)

  local needDraw = false
  for _, i in ipairs(active) do
    for _, hand in ipairs(seats[i].hands) do
      local natural = isBJ(hand.cards) and not hand.fromSplit
      if handValue(hand.cards) <= 21 and not natural then needDraw = true end
    end
  end
  if not needDraw then return end

  while true do
    local v, soft = handValue(dealer)
    if v < 17 or (v == 17 and soft) then
      msg = (v == 17) and "Soft 17 - dealer hits" or "Dealer hits"
      table.insert(dealer, drawCard()); snd("hat", 8); pause(0.7)
    else
      break
    end
  end
end

local function settle(active)
  local dv = handValue(dealer)
  local dBJ = isBJ(dealer)
  local dBust = dv > 21
  for _, i in ipairs(active) do
    local s = seats[i]
    local pay = 0
    for _, hand in ipairs(s.hands) do
      local v = handValue(hand.cards)
      local natural = isBJ(hand.cards) and not hand.fromSplit
      if dBJ then
        if natural then pay = pay + hand.bet; hand.result = "PUSH" else hand.result = "LOSE" end
      elseif v > 21 then
        hand.result = "BUST"
      elseif natural then
        local win = math.floor(hand.bet * CONFIG.bjPays)
        pay = pay + hand.bet + win; hand.result = "BJ +" .. win
      elseif dBust or v > dv then
        pay = pay + hand.bet * 2; hand.result = "WIN +" .. hand.bet
      elseif v == dv then
        pay = pay + hand.bet; hand.result = "PUSH"
      else
        hand.result = "LOSE"
      end
    end
    payOut(s, pay)
    refreshBal(s)
    bank.record("blackjack", s.name, s.wagered, s.returned + s.owed)
    net.report(s.name, s.wagered, s.returned + s.owed)
  end
end

local carryMsg
local function playRound()
  bettingPhase(carryMsg)
  carryMsg = nil

  local active, why = dealRound()
  if not active then carryMsg = why; return end
  settleSides(active)

  local up = cardVal(dealer[1])
  local dealerBJ = false
  if CONFIG.dealerPeek and (up == 1 or up == 10) then
    msg = "Dealer checks for Blackjack..."; pause(1.0)
    if isBJ(dealer) then
      dealerBJ, hideHole = true, false
      msg = "Dealer has Blackjack!"; snd("bass", 2); pause(1.4)
    end
  end

  if not dealerBJ then
    playTurns(active)
    dealerPlay(active)
  end

  hideHole = false
  local before = msg
  settle(active)
  phase = "result"
  if msg == before or not msg:find("FAILED") then msg = "Tap NEXT HAND (or wait " .. CONFIG.resultWait .. "s)" end
  snd("pling", 12)

  while true do
    render()
    local a = waitAction(CONFIG.resultWait)
    if a.t == "next" or a.t == "timeout" then return end
    if a.t == "detector" then handleDetector(a) end
  end
end

---------------------------------------------------------------------
-- owner console (on the computer's own screen)
---------------------------------------------------------------------
local function mapDetectors()
  mapping = true
  local map, seat, done = {}, 1, false
  print("Right-click each seat's detector in order,")
  print("starting with seat 1. Press ENTER when done.")
  while seat <= 6 and not done do
    print("Seat " .. seat .. "...")
    while true do
      local e, a, b = os.pullEvent()
      if e == "playerClick" then
        if map[b] then print("  already seat " .. map[b])
        else map[b] = seat; print("  " .. b .. " -> seat " .. seat); seat = seat + 1; break end
      elseif e == "key" and a == keys.enter then
        done = true; break
      end
    end
  end
  mapping = false
  if next(map) then
    S.detectors = map; saveSettings(); os.queueEvent("casino_settings"); print("Saved.")
  else
    print("No change.")
  end
end

local HELP = {
  "show              current settings",
  "set min <n>       main bet minimum",
  "set max <n>       main bet maximum",
  "set sidemin <n>   side bet minimum",
  "set sidemax <n>   side bet maximum",
  "set seats <1-6>   number of seats",
  "open / close      allow or stop new deals",
  "house <name>      account that backs the table",
  "prefix <eco|none> admin command prefix",
  "bal <name>        test a balance read",
  "stats             handle, hold, swing",
  "map               re-map seat detectors",
  "pin               change PIN",
  "netpass           casino network password",
  "lock / quit",
}

local function console()
  term.clear(); term.setCursorPos(1, 1)
  term.setTextColor(colors.yellow); print("Blackjack table running"); term.setTextColor(colors.white)
  print("House account: " .. S.house)
  print("Enter PIN to manage the table.")
  local unlocked = false
  while true do
    term.setTextColor(colors.yellow)
    write(unlocked and "admin> " or "PIN> ")
    term.setTextColor(colors.white)
    local line = read(not unlocked and "*" or nil) or ""
    if not unlocked then
      if line == S.pin then unlocked = true; print("Unlocked. Type 'help'.") else print("Wrong PIN.") end
    else
      local wds = {}
      for wd in line:gmatch("%S+") do wds[#wds + 1] = wd end
      local cmd = (wds[1] or ""):lower()
      if cmd == "help" then
        for _, l in ipairs(HELP) do print(l) end
      elseif cmd == "show" then
        print(("Main bet $%d - $%d"):format(S.mainMin, S.mainMax))
        print(("Side bets $%d - $%d"):format(S.sideMin, S.sideMax))
        print(("Seats %d  |  Table %s"):format(S.seats, S.open and "OPEN" or "CLOSED"))
        print("House: " .. S.house .. "  |  prefix: " .. (S.ecoPrefix ~= "" and S.ecoPrefix or "none"))
        local n = 0; for _ in pairs(S.detectors) do n = n + 1 end
        print(n .. " detector(s) mapped")
      elseif cmd == "set" then
        local keyMap = { min = "mainMin", max = "mainMax", sidemin = "sideMin", sidemax = "sideMax", seats = "seats" }
        local key, val = keyMap[(wds[2] or ""):lower()], tonumber(wds[3])
        if not key then
          print("Usage: set min|max|sidemin|sidemax|seats <whole number>")
        else
          local ok, err = setLimit(key, val)
          if ok then
            net.pushStatus()
            print(wds[2] .. " = " .. val .. " (applies from the next betting round)")
          else
            print("Rejected: " .. tostring(err))
          end
        end
      elseif cmd == "open" or cmd == "close" then
        setOpen(cmd == "open"); net.pushStatus()
        print("Table " .. (S.open and "OPEN" or "CLOSED"))
      elseif cmd == "netpass" then
        write("Casino network password (same on every computer): ")
        local p = read("*")
        if p and #p >= 4 then net.setPassword(p); net.pushStatus(); print("Saved.") else print("Too short (4+).") end
      elseif cmd == "house" then
        if bank.validName(wds[2]) then
          S.house = wds[2]; saveSettings(); applyBankConfig(); print("House account: " .. S.house)
        else print("Usage: house <username>") end
      elseif cmd == "prefix" then
        local p = wds[2]
        if p then S.ecoPrefix = (p == "none") and "" or p; saveSettings(); applyBankConfig(); print("OK")
        else print("Usage: prefix eco | prefix none") end
      elseif cmd == "bal" then
        local who = wds[2] or S.house
        local v, raw = bank.balance(who)
        print("Raw reply: " .. tostring(raw))
        print("Read as:   " .. tostring(v))
      elseif cmd == "stats" then
        local g = bank.stats("blackjack")
        if not g then print("No rounds recorded yet.")
        else
          local hold = g.handle > 0 and (g.net / g.handle * 100) or 0
          print(("Rounds %d   Handle $%d   Paid $%d"):format(g.rounds, g.handle, g.paid))
          print(("House net %s$%d   Hold %.1f%%"):format(g.net >= 0 and "+" or "-", math.abs(g.net), hold))
          print(("Swing: high +$%d / low -$%d"):format(g.peak, -g.trough))
          print(("Biggest round: won $%d / lost $%d"):format(g.bigWin, -g.bigLoss))
        end
      elseif cmd == "map" then
        mapDetectors()
      elseif cmd == "pin" then
        write("New PIN: "); local p = read("*")
        if p and #p >= 3 then S.pin = p; saveSettings(); print("PIN changed.") else print("Too short.") end
      elseif cmd == "lock" then
        unlocked = false; print("Locked.")
      elseif cmd == "quit" then
        return
      elseif cmd ~= "" then
        print("Unknown command. Type 'help'.")
      end
    end
  end
end

---------------------------------------------------------------------
-- startup
---------------------------------------------------------------------
loadSettings()

if not bank.validName(S.house) then
  term.clear(); term.setCursorPos(1, 1)
  print("First-time setup")
  repeat
    write("House account (username whose balance backs the table): ")
    S.house = read()
  until bank.validName(S.house)
end
if S.pin == "" then
  repeat write("Choose an admin PIN (3+ chars): "); S.pin = read("*") until #S.pin >= 3
end
if not net.hasPassword() then
  write("Casino network password (same on every computer, blank to skip): ")
  local p = read("*")
  if #p >= 4 then net.setPassword(p) elseif #p > 0 then print("Too short - skipped. Use 'netpass' later.") end
end

-- auto-assign detectors (sorted by name) the first time
if not next(S.detectors) then
  local names = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "playerDetector" then names[#names + 1] = n end
  end
  table.sort(names)
  for i, n in ipairs(names) do if i <= 6 then S.detectors[n] = i end end
end
saveSettings()
applyBankConfig()

local hb, raw = bank.balance(S.house)
if not hb then
  print("WARNING: couldn't read the house balance.")
  print("Reply was: " .. tostring(raw))
  print("Check the account name / prefix. Press any key.")
  os.pullEvent("key")
end
if not next(S.detectors) then
  print("WARNING: no player detectors found - nobody can sit. Press any key.")
  os.pullEvent("key")
end

if not net.openModem() then
  print("Note: no wireless/ender modem - the main computer won't see this table.")
  print("Rounds are saved and sent once a modem is added.")
  sleep(2)
end

local function game()
  newShoe()
  setupSeats(S.seats)
  while true do playRound() end
end

parallel.waitForAny(game, console, net.runGame)

scr.setVisible(true)
mon.setBackgroundColor(colors.black)
mon.clear()
term.clear(); term.setCursorPos(1, 1)
print("Blackjack closed.")
