--[[
  casino_slot.lua  -  real-money layer shared by every slot machine
  ---------------------------------------------------------------
  Goes next to the slot program, together with casino_bank.lua and
  casino_net.lua.

  On a COMMAND COMPUTER the slots play for REAL EconomyCraft money:
    * whoever stands closest to a machine is the player - tapping SPIN
      the first time says "WELCOME <name>", the next tap spins
    * every spin takes the bet from the player's balance (player -> house)
    * every win (line wins, bonuses, free games, jackpots) is paid back in
      one go when the spin / feature is over (house -> player)
    * every spin goes into the ledger and is sent to the main computer,
      which can OPEN / CLOSE the machine and change MIN / MAX bet
    * a spin that was cut off (server restart, chunk unloaded) is paid out
      the next time the machine starts - nothing is ever lost

  On a normal computer it falls back to PRACTICE credits (no money moves).

  Owner console on the computer itself (PIN): limits, open/close,
  calibrate machine spots, stats.  Type 'help' after the PIN.

  Game side:
    local slot = require("casino_slot")
    slot.setup{ game = "buffalo", kind = "Buffalo Bonus", practiceCredits = 1000 }
    local seat = slot.seat(monitorName)
    seat:begin(bet)   -> true | false, message, "welcome"?  (start of a PAID spin)
    seat:win(amount)                                (any win, any time in the round)
    seat:finish()     -> nil | message              (spin + features all done)
    seat:credits(), seat:name(), seat:touch()
    slot.run(stationFn1, stationFn2, ...)
]]

local slot = {}

local CONFIG = {
  joinRange    = 3,      -- blocks from a machine's spot a player can be to play it
  noSpotRange  = 5,      -- same, while a machine still uses the computer's own spot
  leaveRange   = 10,     -- players further away than this are logged off the machine
  crowdMargin  = 0.75,   -- two players this close to equally near = "too crowded"
  idleCheck    = 15,     -- seconds between "is the player still here?" checks
  houseCache   = 30,     -- seconds a house balance read is trusted
}

local LIVE = commands ~= nil
slot.LIVE = LIVE

local bank = LIVE and require("casino_bank") or nil
local net  = LIVE and require("casino_net") or nil

local G = { game = "slot", kind = "Slot", practiceCredits = 1000 }

---------------------------------------------------------------------
-- owner settings
---------------------------------------------------------------------
local S = {
  house     = "",
  pin       = "",
  minBet    = 1,
  maxBet    = 500,
  cover     = 20,      -- house must hold bet x this to allow a spin (0 = off)
  open      = true,
  ecoPrefix = "eco",
  balCmd    = "bal",
  spots     = {},      -- [monitor name] = { x, y, z } where a player stands
}

local function loadT(file)
  if not fs.exists(file) then return nil end
  local f = fs.open(file, "r")
  local t = textutils.unserialize(f.readAll())
  f.close()
  return type(t) == "table" and t or nil
end

local function saveT(file, t)
  local f = fs.open(file, "w")
  f.write(textutils.serialize(t))
  f.close()
end

local function cfgFile() return G.game .. ".cfg" end
local function roundsFile() return G.game .. "_rounds.dat" end

local function loadSettings()
  local t = loadT(cfgFile())
  if t then for k, v in pairs(t) do S[k] = v end end
  S.spots = S.spots or {}
end
local function saveSettings() saveT(cfgFile(), S) end

local function applyBankConfig()
  bank.config({ house = S.house, prefix = S.ecoPrefix, balCmd = S.balCmd })
end

local function commas(n)
  local s = tostring(math.floor(math.abs(n)))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return out
end
local function dollars(n) return (n < 0 and "-$" or "$") .. commas(n) end
slot.dollars = dollars

---------------------------------------------------------------------
-- limits (shared by the console and the main computer)
---------------------------------------------------------------------
local LIMIT_KEYS = { minBet = true, maxBet = true, cover = true }

local function setLimit(key, val)
  if not LIMIT_KEYS[key] then return false, "unknown setting" end
  if not val or val ~= math.floor(val) then return false, "must be a whole number" end
  if key ~= "cover" and val < 1 then return false, "must be 1 or more" end
  if key == "cover" and val < 0 then return false, "must be 0 or more" end
  local old = S[key]
  S[key] = val
  if S.minBet > S.maxBet then
    S[key] = old
    return false, "min bet can't be above max bet"
  end
  saveSettings()
  return true
end

local function setOpen(open)
  S.open = open and true or false
  saveSettings()
end

function slot.limits() return S.minBet, S.maxBet end
function slot.isOpen() return S.open end

---------------------------------------------------------------------
-- rounds that are still open (kept on disk so a crash can't lose a win)
---------------------------------------------------------------------
local pending = {}   -- [seat id] = { player, bet, won, t, paid }

local function savePending() saveT(roundsFile(), pending) end

-- pay (if not paid yet) + ledger + main computer. Returns an error message or nil
local function settle(id, r)
  local pay = math.floor((r.won or 0) + 0.5)
  local problem
  if pay > 0 and not r.paid then
    local ok, err = bank.pay(r.player, pay)
    if not ok then
      bank.owe(G.game, r.player, pay, err)
      problem = "PAYOUT FAILED - IOU LOGGED, SEE THE OWNER"
    end
    r.paid = true
    savePending()                 -- never pay the same round twice
  end
  bank.record(G.game, r.player, r.bet, pay)
  net.report(r.player, r.bet, pay)
  pending[id] = nil
  savePending()
  return problem, pay
end

---------------------------------------------------------------------
-- house balance (cached so every spin doesn't ask the server)
---------------------------------------------------------------------
local hb, hbTime = nil, 0
local function houseBalance(fresh)
  local now = os.epoch("utc")
  if fresh or not hb or now - hbTime > CONFIG.houseCache * 1000 then
    local v = bank.balance(S.house)
    if v then hb, hbTime = v, now end
    return v
  end
  return hb
end
local function houseAdjust(d) if hb then hb = hb + d end end

---------------------------------------------------------------------
-- where players stand
---------------------------------------------------------------------
local computerSpot
local function spotOf(id)
  if S.spots[id] then return S.spots[id], CONFIG.joinRange end
  if not computerSpot and LIVE then
    local x, y, z = commands.getBlockPosition()
    computerSpot = { x = x + 0.5, y = y, z = z + 0.5 }
  end
  return computerSpot, CONFIG.noSpotRange
end

local function nearestPlayer(id)
  local p, range = spotOf(id)
  local list = bank.playersNear(p, range, { limit = 2 })
  if #list == 0 then return nil, "STAND IN FRONT OF THE MACHINE TO PLAY" end
  if #list > 1 and list[2].d - list[1].d < CONFIG.crowdMargin then
    return nil, "TOO CROWDED - ONE PLAYER PER MACHINE"
  end
  return list[1].name
end

local function stillNear(id, name)
  local p, range = spotOf(id)
  local list = bank.playersNear(p, math.max(range, CONFIG.leaveRange), { name = name, limit = 1 })
  return #list > 0
end

---------------------------------------------------------------------
-- seats (one per monitor wall)
---------------------------------------------------------------------
local calibrating = false
local seatList, seats = {}, {}
local Seat = {}
Seat.__index = Seat

function slot.seat(id)
  if seats[id] then return seats[id] end
  local s = setmetatable({ id = id, player = nil, bal = nil, round = nil,
    practice = G.practiceCredits, lastActive = 0 }, Seat)
  if pending[id] then s.round = pending[id]; s.player = s.round.player end
  seats[id] = s
  seatList[#seatList + 1] = s
  return s
end

-- name shown on the machine (nil = nobody)
function Seat:name()
  if not LIVE then return "PRACTICE" end
  return self.player
end

-- number for the CREDITS / BALANCE display
function Seat:credits()
  if not LIVE then return self.practice end
  return (self.bal or 0) + (self.round and self.round.won or 0)
end

-- short HUD text, e.g. "im_coming $1,250"
function Seat:hud()
  if not LIVE then return "PRACTICE " .. dollars(self.practice) end
  if not self.player then return "TAP SPIN TO PLAY" end
  return self.player .. " " .. dollars(self:credits())
end

-- call first on every touch; true = the touch was used (show msg)
function Seat:touch()
  if not LIVE or not calibrating then return false end
  local p, err = bank.playerPos(S.house)
  if not p then return true, "CAN'T FIND " .. S.house .. ": " .. tostring(err) end
  S.spots[self.id] = { x = p.x, y = p.y, z = p.z }
  saveSettings()
  print(("Spot set for %s at %d, %d, %d"):format(self.id, math.floor(p.x), math.floor(p.y), math.floor(p.z)))
  return true, "SPOT SET FOR THIS MACHINE"
end

-- start of a PAID spin. Returns true, or false + a message for the screen
function Seat:begin(bet)
  if not LIVE then
    if self.practice < bet then
      self.practice = G.practiceCredits
      return false, "PRACTICE MODE - REFILLED TO " .. dollars(G.practiceCredits), "welcome"
    end
    self.practice = self.practice - bet
    return true
  end

  if self.round then self:finish() end
  if calibrating then return false, "OWNER IS SETTING UP - TRY AGAIN SOON" end
  if not S.open then return false, "MACHINE CLOSED" end
  if bet ~= math.floor(bet) then return false, "BET MUST BE WHOLE DOLLARS - CHANGE THE DENOM" end
  if bet < S.minBet or bet > S.maxBet then
    return false, ("BET LIMITS ON THIS MACHINE: %s - %s"):format(dollars(S.minBet), dollars(S.maxBet))
  end

  local name, why = nearestPlayer(self.id)
  if not name then
    self.player, self.bal = nil, nil
    return false, why
  end
  if name ~= self.player then
    self.player = name
    self.bal = bank.balance(name)
    self.lastActive = os.epoch("utc")
    return false, ("WELCOME %s!  BALANCE %s - TAP SPIN"):format(name, self.bal and dollars(self.bal) or "?"), "welcome"
  end

  if S.cover > 0 then
    local h = houseBalance()
    if not h then return false, "CAN'T READ THE HOUSE BALANCE - SEE THE OWNER" end
    if h < bet * S.cover then
      h = houseBalance(true)
      if not h or h < bet * S.cover then return false, "MACHINE NEEDS A REFILL - SEE THE OWNER" end
    end
  end

  local ok, err = bank.take(name, bet)
  if not ok then
    self.bal = bank.balance(name) or self.bal
    if err == "not enough money" then
      return false, "NOT ENOUGH MONEY - BALANCE " .. dollars(self.bal or 0)
    end
    return false, "PAYMENT FAILED: " .. tostring(err)
  end
  houseAdjust(bet)
  self.bal = math.max(0, (self.bal or bet) - bet)
  self.round = { player = name, bet = bet, won = 0, t = os.epoch("utc") }
  pending[self.id] = self.round
  savePending()
  self.lastActive = os.epoch("utc")
  return true
end

-- add a win to this round (paid when finish() is called)
function Seat:win(amount)
  if not amount or amount <= 0 then return end
  if not LIVE then self.practice = self.practice + amount; return end
  if not self.round then return end
  self.round.won = self.round.won + amount
  savePending()
end

-- the spin and every feature it started are over: pay + record
function Seat:finish()
  if not LIVE or not self.round then return nil end
  local r = self.round
  local problem, pay = settle(self.id, r)
  houseAdjust(-(pay or 0))
  self.round = nil
  self.bal = bank.balance(r.player) or self.bal
  self.lastActive = os.epoch("utc")
  return problem
end

-- the game can register a redraw for when the player walks off
function Seat:onChange(fn) self.changed = fn end

---------------------------------------------------------------------
-- background: log off players who walked away
---------------------------------------------------------------------
local function watcher()
  while true do
    sleep(CONFIG.idleCheck)
    for _, s in ipairs(seatList) do
      if s.player and not s.round and not stillNear(s.id, s.player) then
        s.player, s.bal = nil, nil
        if s.changed then pcall(s.changed) end
      end
    end
  end
end

---------------------------------------------------------------------
-- owner console
---------------------------------------------------------------------
local HELP = {
  "show              current settings",
  "set min <n>       minimum total bet per spin",
  "set max <n>       maximum total bet per spin",
  "set cover <n>     house must hold bet x n to spin (0 = off)",
  "open / close      allow or stop new spins",
  "stations          machines on this computer + who's playing",
  "calibrate         set where players stand (on/off)",
  "who <station>     test who's standing at a machine",
  "house <name>      account that backs the machines",
  "prefix <eco|none> admin command prefix",
  "bal <name>        test a balance read",
  "stats             handle, hold, swing",
  "owed              unpaid IOUs",
  "pin / netpass     change PIN / network password",
  "lock / quit",
}

local function toggleCalibrate()
  calibrating = not calibrating
  if calibrating then
    print("CALIBRATE ON. Stand where a player stands at")
    print("each machine and tap that machine's screen.")
    print("Type 'calibrate' again when you're done.")
  else
    local n = 0
    for _, s in ipairs(seatList) do if S.spots[s.id] then n = n + 1 end end
    print(("Calibrate OFF. %d of %d machine spot(s) set."):format(n, #seatList))
  end
end

local function printStations()
  for i, s in ipairs(seatList) do
    print(("%d  %s  spot %s  %s"):format(i, s.id, S.spots[s.id] and "SET" or "not set",
      s.player and ("player " .. s.player) or "free"))
  end
end

local function whoAt(n)
  local s = seatList[tonumber(n) or 0]
  if not s then print("Usage: who <station number>  (see 'stations')"); return end
  local p, range = spotOf(s.id)
  local list, raw = bank.playersNear(p, range, { limit = 3 })
  if #list == 0 then print("Nobody within " .. range .. " blocks of station " .. n) end
  for _, e in ipairs(list) do print(("%s  %.1f blocks"):format(e.name, e.d)) end
  if #list == 0 and #raw > 0 then print("Raw: " .. table.concat(raw, " | ")) end
end

local function printOwed()
  if not fs.exists("casino_owed.log") then print("No IOUs. Nice."); return end
  local f = fs.open("casino_owed.log", "r")
  local n = 0
  while true do
    local l = f.readLine()
    if not l then break end
    if l:find(G.game, 1, true) then print(l); n = n + 1 end
  end
  f.close()
  if n == 0 then print("No IOUs for this game.") end
end

local function console()
  term.clear(); term.setCursorPos(1, 1)
  term.setTextColor(colors.yellow); print(G.kind .. " - REAL MONEY"); term.setTextColor(colors.white)
  print(("House: %s   Bets %s - %s   %s"):format(S.house, dollars(S.minBet), dollars(S.maxBet), S.open and "OPEN" or "CLOSED"))
  local missing = 0
  for _, s in ipairs(seatList) do if not S.spots[s.id] then missing = missing + 1 end end
  if missing > 0 then
    term.setTextColor(colors.orange)
    print(missing .. " machine(s) have no player spot yet. Enter PIN, then 'calibrate'.")
    term.setTextColor(colors.white)
  end
  print("Enter PIN to manage the machines.")
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
        print(("Bets %s - %s   Cover x%d   %s"):format(dollars(S.minBet), dollars(S.maxBet), S.cover, S.open and "OPEN" or "CLOSED"))
        print("House: " .. S.house .. "  |  prefix: " .. (S.ecoPrefix ~= "" and S.ecoPrefix or "none"))
        printStations()
      elseif cmd == "set" then
        local keyMap = { min = "minBet", max = "maxBet", cover = "cover" }
        local key, val = keyMap[(wds[2] or ""):lower()], tonumber(wds[3])
        if not key then print("Usage: set min|max|cover <whole number>")
        else
          local ok, err = setLimit(key, val)
          if ok then net.pushStatus(); print(wds[2] .. " = " .. val)
          else print("Rejected: " .. tostring(err)) end
        end
      elseif cmd == "open" or cmd == "close" then
        setOpen(cmd == "open"); net.pushStatus()
        print("Machines " .. (S.open and "OPEN" or "CLOSED"))
      elseif cmd == "stations" then
        printStations()
      elseif cmd == "calibrate" then
        toggleCalibrate()
      elseif cmd == "who" then
        whoAt(wds[2])
      elseif cmd == "house" then
        if bank.validName(wds[2]) then
          S.house = wds[2]; saveSettings(); applyBankConfig(); hb = nil
          print("House account: " .. S.house)
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
        local g = bank.stats(G.game)
        if not g then print("No spins recorded yet.")
        else
          local hold = g.handle > 0 and (g.net / g.handle * 100) or 0
          print(("Spins %d   Handle $%d   Paid $%d"):format(g.rounds, g.handle, g.paid))
          print(("House net %s$%d   Hold %.1f%%"):format(g.net >= 0 and "+" or "-", math.abs(g.net), hold))
          print(("Swing: high +$%d / low -$%d"):format(g.peak, -g.trough))
          print(("Biggest spin: house won $%d / lost $%d"):format(g.bigWin, -g.bigLoss))
        end
      elseif cmd == "owed" then
        printOwed()
      elseif cmd == "pin" then
        write("New PIN: "); local p = read("*")
        if p and #p >= 3 then S.pin = p; saveSettings(); print("PIN changed.") else print("Too short.") end
      elseif cmd == "netpass" then
        write("Casino network password (same on every computer): ")
        local p = read("*")
        if p and #p >= 4 then net.setPassword(p); net.pushStatus(); print("Saved.") else print("Too short (4+).") end
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

local function practiceConsole()
  term.clear(); term.setCursorPos(1, 1)
  term.setTextColor(colors.orange); print(G.kind .. " - PRACTICE MODE"); term.setTextColor(colors.white)
  print("This is not a Command Computer, so no real money moves.")
  print("Put it on a Command Computer for real EconomyCraft money.")
  print("Type 'quit' to stop.")
  while true do
    write("> ")
    if (read() or "") == "quit" then return end
  end
end

---------------------------------------------------------------------
-- startup
---------------------------------------------------------------------
function slot.setup(opts)
  for k, v in pairs(opts or {}) do G[k] = v end
  if not LIVE then return end

  loadSettings()
  pending = loadT(roundsFile()) or {}

  if not bank.validName(S.house) then
    term.clear(); term.setCursorPos(1, 1)
    print(G.kind .. " - first-time setup")
    repeat
      write("House account (username whose balance backs the machine): ")
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
  saveSettings()
  applyBankConfig()

  local h, raw = houseBalance(true)
  if not h then
    print("WARNING: couldn't read the house balance.")
    print("Reply was: " .. tostring(raw))
    print("Check the account name / prefix. Press any key.")
    os.pullEvent("key")
  end

  net.setupGame({
    kind = G.kind,
    status = function()
      return {
        open = S.open,
        limits = {
          { k = "minBet", label = "MIN BET", v = S.minBet },
          { k = "maxBet", label = "MAX BET", v = S.maxBet },
        },
      }
    end,
    set = setLimit,
    setOpen = setOpen,
  })

  -- pay out anything a crash or restart cut off
  local ids = {}
  for id in pairs(pending) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do
    local r = pending[id]
    if type(r) == "table" and bank.validName(r.player) and type(r.bet) == "number" then
      local problem, pay = settle(id, r)
      print(("Settled an unfinished spin: %s bet $%d, paid $%d%s"):format(r.player, r.bet, pay or 0,
        problem and " (FAILED - IOU logged)" or ""))
    else
      pending[id] = nil
      savePending()
    end
  end

  if not net.openModem() then
    print("Note: no wireless/ender modem - the main computer won't see this machine.")
    print("Spins are saved and sent once a modem is added.")
    sleep(2)
  end
end

-- runs every station plus the console, network and walk-away checks
function slot.run(...)
  local fns = { ... }
  local function stations() parallel.waitForAll(table.unpack(fns)) end
  if LIVE then
    parallel.waitForAny(stations, console, net.runGame, watcher)
  else
    parallel.waitForAny(stations, practiceConsole)
  end
end

return slot
