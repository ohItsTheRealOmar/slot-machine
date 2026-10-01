--[[
  casino_bank.lua  -  shared money layer for every casino game
  ---------------------------------------------------------------
  Talks to EconomyCraft through server commands, so it MUST run on a
  COMMAND COMPUTER. Every transfer is player <-> house account, where
  the house account is the owner's own EconomyCraft balance.

  Also keeps a simple ledger on this computer:
    casino_ledger.log  - one line per player per round
    casino_stats.dat   - running totals per game (handle, paid, hold, swing)
    casino_owed.log    - any payout that failed (pay these by hand)

  Usage:  local bank = require("casino_bank")
          bank.config({ house = "Spit" })
          bank.take(player, 50)   -- player -> house
          bank.pay(player, 120)   -- house  -> player
]]

local bank = {}

local cfg = {
  house      = "",
  prefix     = "eco",      -- admin command prefix ("" if standalone_admin_commands is on)
  balCmd     = "bal",      -- balance command
  ledgerFile = "casino_ledger.log",
  statsFile  = "casino_stats.dat",
  owedFile   = "casino_owed.log",
}

function bank.config(t) for k, v in pairs(t) do cfg[k] = v end end

if not commands then
  error("casino_bank needs a COMMAND COMPUTER (it runs /eco commands).", 0)
end

function bank.validName(n)
  return type(n) == "string" and #n >= 1 and #n <= 16 and n:match("^[%w_]+$") ~= nil
end

local function run(cmd)
  local ok, out = commands.exec(cmd)
  return ok, table.concat(out or {}, " ")
end

local function eco(sub)
  if cfg.prefix and cfg.prefix ~= "" then return cfg.prefix .. " " .. sub end
  return sub
end

-- pulls the first money amount out of the /bal reply ("$1,234", "1 234", "1234.50" ...)
local function parseAmount(text)
  local tok = text:match("%d[%d,%.' ]*")
  if not tok then return nil end
  tok = tok:gsub("[^%d]+$", "")        -- trailing separators / spaces
  tok = tok:gsub("[%.,]%d%d?$", "")     -- drop cents
  return tonumber((tok:gsub("%D", "")))
end

-- returns balance (number) and the raw command output, or nil + error text
function bank.balance(name)
  if not bank.validName(name) then return nil, "bad name" end
  local ok, out = run(cfg.balCmd .. " " .. name)
  if not ok then return nil, out end
  local v = parseAmount((out:gsub(name, " ")))   -- strip the name so digits in it don't confuse us
  if not v then return nil, out end
  return v, out
end

local function move(from, to, amt)
  amt = math.floor(amt)
  if amt <= 0 then return true end
  if not bank.validName(from) or not bank.validName(to) then return false, "bad account name" end
  local bal = bank.balance(from)
  if not bal then return false, "balance check failed" end
  if bal < amt then
    return false, (from == cfg.house) and "house is short on money" or "not enough money"
  end
  local ok, out = run(eco(("removemoney %s %d"):format(from, amt)))
  if not ok then return false, "withdraw failed: " .. out end
  local ok2, out2 = run(eco(("addmoney %s %d"):format(to, amt)))
  if not ok2 then
    run(eco(("addmoney %s %d"):format(from, amt)))   -- put it back
    return false, "deposit failed: " .. out2
  end
  return true
end

function bank.take(player, amt) return move(player, cfg.house, amt) end
function bank.pay(player, amt)  return move(cfg.house, player, amt) end

---------------------------------------------------------------------
-- ledger
---------------------------------------------------------------------
local function stamp() return os.date("%Y-%m-%d %H:%M:%S") end

local function appendLine(file, line)
  local f = fs.open(file, "a")
  if f then f.writeLine(line); f.close() end
end

local function loadStats()
  if not fs.exists(cfg.statsFile) then return {} end
  local f = fs.open(cfg.statsFile, "r")
  local t = textutils.unserialize(f.readAll())
  f.close()
  return type(t) == "table" and t or {}
end

local function saveStats(t)
  local f = fs.open(cfg.statsFile, "w")
  f.write(textutils.serialize(t))
  f.close()
end

-- one call per player per round. wagered = everything they put in, returned = everything paid back
function bank.record(game, player, wagered, returned)
  if wagered <= 0 then return end
  local net = wagered - returned                  -- positive = house won
  appendLine(cfg.ledgerFile, ("%s\t%s\t%s\tbet %d\tpaid %d\thouse %+d"):format(stamp(), game, player, wagered, returned, net))
  local all = loadStats()
  local g = all[game] or { rounds = 0, handle = 0, paid = 0, net = 0, peak = 0, trough = 0, bigWin = 0, bigLoss = 0 }
  g.rounds  = g.rounds + 1
  g.handle  = g.handle + wagered
  g.paid    = g.paid + returned
  g.net     = g.net + net
  g.peak    = math.max(g.peak, g.net)
  g.trough  = math.min(g.trough, g.net)
  g.bigWin  = math.max(g.bigWin, net)
  g.bigLoss = math.min(g.bigLoss, net)
  all[game] = g
  saveStats(all)
end

function bank.stats(game) return loadStats()[game] end

function bank.owe(game, player, amt, why)
  appendLine(cfg.owedFile, ("%s\t%s\t%s\tOWED %d\t%s"):format(stamp(), game, player, amt, tostring(why)))
end

return bank
