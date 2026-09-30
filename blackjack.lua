--[[
  blackjack.lua  -  CC:Tweaked practice blackjack table
  ---------------------------------------------------------------
  * Floor-mounted ADVANCED monitor (facing up) that players walk on
  * Start menu: pick 1-6 players (tap the monitor or press 1-6 on the computer)
  * Dealer HITS soft 17, STANDS on hard 17
  * Blackjack pays 3:2, double on any first two cards, split up to 4 hands
  * Side bets: TRILUX and BLAZING 7s  ($25 minimum)
  * Practice money only - every seat starts with CONFIG.startBank

  Recommended monitor: 8 wide x 4 deep (or bigger) at text scale 0.5.
  Place the monitors while looking DOWN at the floor. The edge you were
  standing on is the player rail; the dealer is drawn at the far edge.
  Press Q on the computer to quit.
]]

local CONFIG = {
  textScale   = 0.5,
  decks       = 6,
  penetration = 0.75,   -- reshuffle after 75% of the shoe is dealt
  startBank   = 1000,   -- practice bankroll per seat
  mainMin     = 10,
  mainMax     = 1000,
  sideMin     = 25,     -- Trilux + Blazing 7s minimum
  sideMax     = 500,
  bjPays      = 1.5,    -- 3:2
  maxHands    = 4,      -- split up to 4 hands
  dealerPeek  = true,   -- dealer checks for blackjack under A / 10
  dealDelay   = 0.35,

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

---------------------------------------------------------------------
-- drawing helpers
---------------------------------------------------------------------
local FELT = colors.green
local SEATCOL = { colors.red, colors.blue, colors.orange, colors.purple, colors.cyan, colors.magenta }

local buttons = {}
local function addHit(x1, y1, x2, y2, action) buttons[#buttons + 1] = { x1, y1, x2, y2, action } end

local function trim(s, w) if #s > w then return s:sub(1, w) end return s end

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

---------------------------------------------------------------------
-- cards / shoe
---------------------------------------------------------------------
local RANK = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
local SUIT = { "\3", "\4", "\5", "\6" }   -- hearts, diamonds, clubs, spades
local CW, CH = 4, 3

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

local function paintCard(x, y, c, faceDown)
  if faceDown then
    fill(x, y, CW, CH, colors.blue)
    txt(x + 1, y + 1, "\127\127", colors.lightBlue, colors.blue)
    return
  end
  local fg = (c.s <= 2) and colors.red or colors.black
  local r = RANK[c.r]
  fill(x, y, CW, CH, colors.white)
  txt(x, y, r, fg, colors.white)
  txt(x + 1, y + 1, SUIT[c.s], fg, colors.white)
  txt(x + CW - #r, y + 2, r, fg, colors.white)
end

local function paintHand(x, y, maxW, cards, hideSecond)
  local n = #cards
  local step = CW + 1
  if n > 1 and (n - 1) * step + CW > maxW then
    step = math.max(2, math.floor((maxW - CW) / (n - 1)))
  end
  for i, c in ipairs(cards) do paintCard(x + (i - 1) * step, y, c, hideSecond and i == 2) end
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
local SEAT_TOP = 14
local nSeats, PW, OFF = 0, 0, 0
local seats = {}
local dealer, hideHole = {}, true
local msg, phase = "", "bet"
local turnSeat, turnHand = 0, 0

local function layoutFor(n)
  local pw = math.min(40, math.floor(W / n))
  return pw, math.floor((W - pw * n) / 2)
end
local function fits(n)
  local pw = layoutFor(n)
  return pw >= 22 and H >= SEAT_TOP + 27
end
local function seatX(i) return OFF + 1 + (i - 1) * PW end

local function setupSeats(n)
  nSeats = n
  PW, OFF = layoutFor(n)
  seats = {}
  for i = 1, n do
    seats[i] = { bal = CONFIG.startBank, main = 0, tri = 0, b7 = 0, hands = {}, side = {}, playing = false, roundStart = 0 }
  end
end

---------------------------------------------------------------------
-- rendering
---------------------------------------------------------------------
local function drawDealerArea()
  fill(1, 1, W, 1, colors.gray)
  txt(2, 1, "BLACKJACK  -  PRACTICE TABLE", colors.yellow, colors.gray)
  local info = "Shoe: " .. #shoe .. " cards "
  txt(W - #info, 1, info, colors.lightGray, colors.gray)

  ctxt(1, W, 2, "DEALER", colors.white, FELT)
  if #dealer > 0 then
    local width = #dealer * (CW + 1) - 1
    paintHand(math.floor((W - width) / 2) + 1, 3, W - 2, dealer, hideHole)
    local s
    if hideHole then s = "Showing " .. valueStr({ dealer[1] }) else s = valueStr(dealer, true) end
    ctxt(1, W, 7, s, colors.yellow, FELT)
  end
  ctxt(1, W, 8, msg, colors.white, FELT)

  -- control buttons (rows 9-11)
  local ctrls
  if phase == "bet" then
    ctrls = { { "DEAL", 14, colors.black, colors.lime, { t = "deal" } }, { "MENU", 10, colors.white, colors.gray, { t = "menu" } } }
  elseif phase == "result" then
    ctrls = { { "NEXT HAND", 15, colors.black, colors.lime, { t = "next" } }, { "MENU", 10, colors.white, colors.gray, { t = "menu" } } }
  end
  if ctrls then
    local total = -2
    for _, c in ipairs(ctrls) do total = total + c[2] + 2 end
    local x = math.floor((W - total) / 2) + 1
    for _, c in ipairs(ctrls) do
      bigButton(x, 9, c[2], 3, c[1], c[3], c[4], c[5])
      x = x + c[2] + 2
    end
  end

  ctxt(1, W, 12, "BLACKJACK PAYS 3 TO 2 - DEALER HITS SOFT 17, STANDS ON HARD 17 - SIDE BETS $"
    .. CONFIG.sideMin .. " MIN", colors.lime, FELT)
end

local function drawSeat(i)
  local s = seats[i]
  local x, w = seatX(i), PW - 1
  local col = SEATCOL[i]
  local active = (phase == "play" and turnSeat == i)

  -- header
  fill(x, SEAT_TOP, w, 1, active and colors.yellow or col)
  local hfg = active and colors.black or colors.white
  txt(x + 1, SEAT_TOP, "P" .. i .. (active and " \16 YOUR TURN" or ""), hfg, active and colors.yellow or col)
  local b = "$" .. s.bal .. " "
  txt(x + w - #b, SEAT_TOP, b, hfg, active and colors.yellow or col)

  -- hands
  local hy = SEAT_TOP + 2
  for h, hand in ipairs(s.hands) do
    local y = hy + (h - 1) * 4
    if active and turnHand == h then txt(x, y + 1, "\16", colors.yellow, FELT) end
    paintHand(x + 1, y, w - 1, hand.cards, false)
    local label = valueStr(hand.cards, not hand.fromSplit) .. " $" .. hand.bet
    local fg = colors.white
    if hand.result then
      label = label .. " " .. hand.result
      if hand.result:find("WIN") or hand.result:find("BJ") then fg = colors.yellow
      elseif hand.result == "PUSH" then fg = colors.lightGray
      else fg = colors.red end
    end
    txt(x + 1, y + 3, trim(label, w - 1), fg, FELT)
  end

  -- side bet results
  local sy = hy + CONFIG.maxHands * 4
  for k = 1, 2 do
    local line = s.side[k]
    if line then txt(x, sy + k - 1, trim(line[1], w), line[2] and colors.yellow or colors.lightGray, FELT) end
  end

  -- controls
  local cy = sy + 3
  if phase == "bet" then
    local function betLine(y, label, key, chips)
      txt(x, y, trim(label .. " $" .. s[key], w), colors.white, FELT)
      local bx = x
      for _, c in ipairs(chips) do
        bx = bx + button(bx, y + 1, "+" .. c, colors.black, colors.yellow, { t = "bet", seat = i, k = key, amt = c }, 1) + 1
      end
      button(bx, y + 1, "X", colors.white, colors.red, { t = "clr", seat = i, k = key }, 1)
    end
    betLine(cy, "MAIN", "main", { 5, 25, 100 })
    betLine(cy + 2, "TRILUX", "tri", { 25, 100 })
    betLine(cy + 4, "BLAZING 7s", "b7", { 25, 100 })
    if s.bal < CONFIG.mainMin then
      button(x, cy + 6, "REFILL $" .. CONFIG.startBank, colors.white, colors.gray, { t = "refill", seat = i })
    end
  elseif active then
    local hand = s.hands[turnHand]
    local c = hand.cards
    local canDouble = #c == 2 and s.bal >= hand.bet and not hand.splitAce
    local canSplit = #c == 2 and cardVal(c[1]) == cardVal(c[2]) and #s.hands < CONFIG.maxHands and s.bal >= hand.bet
    local bw = math.floor((w - 1) / 2)
    bigButton(x, cy, bw, 3, "HIT", colors.black, colors.lime, { t = "hit" })
    bigButton(x + bw + 1, cy, bw, 3, "STAND", colors.white, colors.red, { t = "stand" })
    bigButton(x, cy + 4, bw, 3, "DOUBLE", canDouble and colors.black or colors.gray,
      canDouble and colors.orange or colors.lightGray, canDouble and { t = "double" } or nil)
    bigButton(x + bw + 1, cy + 4, bw, 3, "SPLIT", canSplit and colors.black or colors.gray,
      canSplit and colors.lightBlue or colors.lightGray, canSplit and { t = "split" } or nil)
  elseif not s.playing then
    txt(x, cy, "Sitting out", colors.lightGray, FELT)
    if phase == "result" and s.bal < CONFIG.mainMin then
      button(x, cy + 2, "REFILL $" .. CONFIG.startBank, colors.white, colors.gray, { t = "refill", seat = i })
    end
  else
    txt(x, cy, trim("Main $" .. s.main, w), colors.white, FELT)
    txt(x, cy + 1, trim("Trilux $" .. s.tri, w), colors.white, FELT)
    txt(x, cy + 2, trim("Blazing 7s $" .. s.b7, w), colors.white, FELT)
    if phase == "result" then
      local net = s.bal - s.roundStart
      local ns = net > 0 and ("Round +$" .. net) or (net < 0 and ("Round -$" .. -net) or "Round even")
      txt(x, cy + 4, ns, net > 0 and colors.yellow or (net < 0 and colors.red or colors.lightGray), FELT)
      if s.bal < CONFIG.mainMin then
        button(x, cy + 6, "REFILL $" .. CONFIG.startBank, colors.white, colors.gray, { t = "refill", seat = i })
      end
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
local function waitAction(numKeys)
  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "monitor_touch" and a == monName then
      for i = #buttons, 1, -1 do
        local bt = buttons[i]
        if b >= bt[1] and b <= bt[3] and c >= bt[2] and c <= bt[4] then return bt[5] end
      end
    elseif ev == "char" then
      if a == "q" then return { t = "quit" } end
      if numKeys and a:match("^[1-6]$") and fits(tonumber(a)) then return { t = "players", n = tonumber(a) } end
    end
  end
end

---------------------------------------------------------------------
-- start menu
---------------------------------------------------------------------
local function menu()
  nSeats = 0
  buttons = {}
  scr.setVisible(false)
  scr.setBackgroundColor(FELT)
  scr.clear()
  ctxt(1, W, 3, "BLACKJACK PRACTICE TABLE", colors.yellow, FELT)
  ctxt(1, W, 5, "Dealer hits soft 17  -  Trilux & Blazing 7s side bets ($" .. CONFIG.sideMin .. " min)", colors.white, FELT)
  ctxt(1, W, 8, "HOW MANY PLAYERS?", colors.white, FELT)
  local bw, gap = 9, 2
  local x0 = math.floor((W - (6 * bw + 5 * gap)) / 2) + 1
  for n = 1, 6 do
    local ok = fits(n)
    bigButton(x0 + (n - 1) * (bw + gap), 10, bw, 5, tostring(n),
      ok and colors.black or colors.gray, ok and colors.yellow or colors.lightGray,
      ok and { t = "players", n = n } or nil)
  end
  ctxt(1, W, 17, "Tap a number, or press 1-6 on the computer", colors.lightGray, FELT)
  if not fits(1) then
    ctxt(1, W, 19, ("Monitor is %dx%d - need 41+ rows. Make it 4+ blocks deep."):format(W, H), colors.red, FELT)
  end
  scr.setVisible(true)
  local a = waitAction(true)
  if a.t == "quit" then return "quit" end
  return a.n
end

---------------------------------------------------------------------
-- round phases
---------------------------------------------------------------------
local function bettingPhase()
  phase, dealer, hideHole, turnSeat = "bet", {}, true, 0
  for _, s in ipairs(seats) do
    s.hands, s.side, s.playing = {}, {}, false
    if s.main + s.tri + s.b7 > s.bal then s.main, s.tri, s.b7 = 0, 0, 0 end
  end
  if #shoe <= cutAt then newShoe(); msg = "New shoe shuffled - place your bets"
  else msg = "Place your bets, then tap DEAL" end

  while true do
    render()
    local a = waitAction()
    if a.t == "quit" or a.t == "menu" then return a.t end
    local s = a.seat and seats[a.seat]
    if a.t == "bet" then
      local cur = s[a.k]
      local isMain = a.k == "main"
      local target = cur + a.amt
      local minB = isMain and CONFIG.mainMin or CONFIG.sideMin
      local maxB = isMain and CONFIG.mainMax or CONFIG.sideMax
      if target < minB then target = minB end
      if target > maxB then target = maxB end
      local free = s.bal - (s.main + s.tri + s.b7)
      if target == cur then msg = "P" .. a.seat .. ": table max is $" .. maxB
      elseif target - cur > free then msg = "P" .. a.seat .. ": not enough money"
      else s[a.k] = target; snd("hat", 14) end
    elseif a.t == "clr" then
      s[a.k] = 0
      if a.k == "main" then s.tri, s.b7 = 0, 0 end
    elseif a.t == "refill" then
      s.bal = CONFIG.startBank
    elseif a.t == "deal" then
      local any, bad = false, nil
      for i, st in ipairs(seats) do
        if st.main > 0 then any = true elseif st.tri + st.b7 > 0 then bad = i end
      end
      if bad then msg = "P" .. bad .. ": side bets need a main bet"
      elseif not any then msg = "Nobody has bet yet"
      else return "deal" end
    end
  end
end

local function dealRound()
  phase, msg = "deal", "Dealing..."
  local active = {}
  for i, s in ipairs(seats) do
    s.playing = s.main > 0
    s.roundStart = s.bal
    if s.playing then
      s.bal = s.bal - (s.main + s.tri + s.b7)
      s.hands = { { cards = {}, bet = s.main } }
      active[#active + 1] = i
    end
  end
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
    if s.tri > 0 then
      anySide = true
      local name, mult = evalTrilux(three)
      if name then
        local win = s.tri * mult
        s.bal = s.bal + s.tri + win
        s.side[1] = { "TRI " .. name .. " +" .. win, true }
        snd("bell", 18)
      else s.side[1] = { "TRI no win", false } end
    end
    if s.b7 > 0 then
      anySide = true
      local name, mult = evalBlazing(three)
      if name then
        local win = s.b7 * mult
        s.bal = s.bal + s.b7 + win
        s.side[2] = { "B7 " .. name .. " +" .. win, true }
        snd("bell", 20)
      else s.side[2] = { "B7 no win", false } end
    end
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
      if #hand.cards == 1 then        -- second card for a split hand
        table.insert(hand.cards, drawCard()); snd("hat", 10); pause()
      end
      if hand.splitAce then hand.done = true end
      if isBJ(hand.cards) and not hand.fromSplit then
        msg = "P" .. i .. " has BLACKJACK!"; snd("bell", 16); pause(0.9)
        hand.done = true
      elseif handValue(hand.cards) == 21 then
        hand.done = true
      end

      while not hand.done do
        msg = "Player " .. i .. (#s.hands > 1 and (" - hand " .. h) or "") .. ": hit or stand?"
        render()
        local a = waitAction()
        if a.t == "quit" then return "quit" end
        if a.t == "hit" then
          table.insert(hand.cards, drawCard()); snd("hat", 12)
          local v = handValue(hand.cards)
          if v > 21 then hand.done = true; hand.result = "BUST"; msg = "P" .. i .. " busts"; snd("bass", 4); pause(0.7)
          elseif v == 21 then hand.done = true; pause() end
        elseif a.t == "stand" then
          hand.done = true
        elseif a.t == "double" and #hand.cards == 2 and s.bal >= hand.bet then
          s.bal = s.bal - hand.bet
          hand.bet = hand.bet * 2
          table.insert(hand.cards, drawCard()); snd("hat", 12)
          hand.done = true
          if handValue(hand.cards) > 21 then hand.result = "BUST"; snd("bass", 4) end
          msg = "P" .. i .. " doubles"; pause(0.8)
        elseif a.t == "split" and #hand.cards == 2 and s.bal >= hand.bet and #s.hands < CONFIG.maxHands then
          s.bal = s.bal - hand.bet
          local moved = table.remove(hand.cards, 2)
          local aces = moved.r == 1
          hand.fromSplit, hand.splitAce = true, aces
          table.insert(s.hands, h + 1, { cards = { moved }, bet = hand.bet, fromSplit = true, splitAce = aces })
          table.insert(hand.cards, drawCard()); snd("hat", 12); pause()
          if aces or handValue(hand.cards) == 21 then hand.done = true end
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
      break                                    -- stands on hard 17+ and soft 18+
    end
  end
end

local function settle(active)
  local dv = handValue(dealer)
  local dBJ = isBJ(dealer)
  local dBust = dv > 21
  for _, i in ipairs(active) do
    local s = seats[i]
    for _, hand in ipairs(s.hands) do
      local v = handValue(hand.cards)
      local natural = isBJ(hand.cards) and not hand.fromSplit
      if dBJ then
        if natural then s.bal = s.bal + hand.bet; hand.result = "PUSH" else hand.result = "LOSE" end
      elseif v > 21 then
        hand.result = "BUST"
      elseif natural then
        local win = math.floor(hand.bet * CONFIG.bjPays)
        s.bal = s.bal + hand.bet + win; hand.result = "BJ +" .. win
      elseif dBust or v > dv then
        s.bal = s.bal + hand.bet * 2; hand.result = "WIN +" .. hand.bet
      elseif v == dv then
        s.bal = s.bal + hand.bet; hand.result = "PUSH"
      else
        hand.result = "LOSE"
      end
    end
  end
end

local function playRound()
  local r = bettingPhase()
  if r ~= "deal" then return r end

  local active = dealRound()
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
    if playTurns(active) == "quit" then return "quit" end
    dealerPlay(active)
  end

  hideHole = false
  settle(active)
  phase = "result"
  msg = "Dealer " .. valueStr(dealer, true) .. "  -  tap NEXT HAND"
  snd("pling", 12)

  while true do
    render()
    local a = waitAction()
    if a.t == "next" then return nil end
    if a.t == "menu" or a.t == "quit" then return a.t end
    if a.t == "refill" then seats[a.seat].bal = CONFIG.startBank end
  end
end

---------------------------------------------------------------------
-- main
---------------------------------------------------------------------
term.clear(); term.setCursorPos(1, 1)
print("Blackjack running on monitor " .. monName .. " (" .. W .. "x" .. H .. ")")
print("Speaker: " .. (spk and "yes" or "none"))
print("Press Q here to quit.")

newShoe()
local running = true
while running do
  local n = menu()
  if n == "quit" then break end
  setupSeats(n)
  while true do
    local r = playRound()
    if r == "quit" then running = false; break end
    if r == "menu" then break end
  end
end

scr.setVisible(true)
mon.setBackgroundColor(colors.black)
mon.clear()
term.clear(); term.setCursorPos(1, 1)
print("Blackjack closed.")
