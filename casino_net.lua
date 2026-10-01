--[[
  casino_net.lua  -  wireless link between the games and the main computer
  ---------------------------------------------------------------
  Goes on EVERY casino computer (each game + the main computer).
  Needs a WIRELESS or ENDER modem on the computer.

  Every message is signed with the casino network password, so a random
  player's computer can't close your tables, change your limits or fake
  ledger entries. Money never travels over the network - each game moves
  its own money with casino_bank.lua.

  Game side:
    net.setupGame{ kind = "Blackjack", status = fn, set = fn(key, value), setOpen = fn(bool) }
    net.report(player, wagered, returned)   -- after every round
    net.pushStatus()                        -- after a local settings change
    parallel.waitForAny(yourGame, net.runGame)
]]

local net = {}
local PROTO = "casino"
net.PROTO = PROTO
local CFG_FILE    = "casino_net.cfg"
local OUTBOX_FILE = "casino_outbox.dat"

---------------------------------------------------------------------
-- small file helpers
---------------------------------------------------------------------
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
net.loadT, net.saveT = loadT, saveT

---------------------------------------------------------------------
-- SHA-256 (used to sign messages)
---------------------------------------------------------------------
local band, bor, bxor, bnot = bit32.band, bit32.bor, bit32.bxor, bit32.bnot
local rshift, lshift, rrotate = bit32.rshift, bit32.lshift, bit32.rrotate
local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}
local function sha256(msg)
  local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
  local ml = #msg
  local bits = ml * 8
  msg = msg .. "\128" .. string.rep("\0", (55 - ml) % 64) .. "\0\0\0\0" ..
    string.char(band(rshift(bits, 24), 255), band(rshift(bits, 16), 255), band(rshift(bits, 8), 255), band(bits, 255))
  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do
      local a, b, c, d = msg:byte(chunk + i * 4, chunk + i * 4 + 3)
      w[i] = bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d)
    end
    for i = 16, 63 do
      local s0 = bxor(rrotate(w[i - 15], 7), rrotate(w[i - 15], 18), rshift(w[i - 15], 3))
      local s1 = bxor(rrotate(w[i - 2], 17), rrotate(w[i - 2], 19), rshift(w[i - 2], 10))
      w[i] = band(w[i - 16] + s0 + w[i - 7] + s1, 0xffffffff)
    end
    local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for i = 0, 63 do
      local S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local t1 = h + S1 + ch + K[i + 1] + w[i]
      local S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
      local maj = bxor(band(a, b), band(a, c), band(b, c))
      h, g, f, e = g, f, e, band(d + t1, 0xffffffff)
      d, c, b, a = c, b, a, band(t1 + S0 + maj, 0xffffffff)
    end
    H[1] = band(H[1] + a, 0xffffffff); H[2] = band(H[2] + b, 0xffffffff)
    H[3] = band(H[3] + c, 0xffffffff); H[4] = band(H[4] + d, 0xffffffff)
    H[5] = band(H[5] + e, 0xffffffff); H[6] = band(H[6] + f, 0xffffffff)
    H[7] = band(H[7] + g, 0xffffffff); H[8] = band(H[8] + h, 0xffffffff)
  end
  local out = {}
  for i = 1, 8 do out[i] = string.format("%08x", H[i]) end
  return table.concat(out)
end
net.sha256 = sha256

---------------------------------------------------------------------
-- password + signed messages
---------------------------------------------------------------------
local cfg = loadT(CFG_FILE) or { secret = "" }
function net.hasPassword() return type(cfg.secret) == "string" and cfg.secret ~= "" end
function net.setPassword(p) cfg.secret = p or ""; saveT(CFG_FILE, cfg) end

function net.openModem()
  local m = peripheral.find("modem", function(_, p) return p.isWireless and p.isWireless() end)
  if not m then return false end
  local name = peripheral.getName(m)
  if not rednet.isOpen(name) then rednet.open(name) end
  return true
end

local seen, seenCount = {}, 0

function net.wrap(body)
  local p = textutils.serialize(body)
  local t = os.epoch("utc")
  local n = math.random(1, 1073741824)
  return { p = p, t = t, n = n, sig = sha256(cfg.secret .. "|" .. p .. "|" .. t .. "|" .. n) }
end

-- returns the message body if the signature is good and it isn't a replay, else nil
function net.unwrap(msg)
  if not net.hasPassword() then return nil end
  if type(msg) ~= "table" or type(msg.p) ~= "string" or type(msg.sig) ~= "string" then return nil end
  if type(msg.t) ~= "number" or type(msg.n) ~= "number" then return nil end
  local now = os.epoch("utc")
  if math.abs(now - msg.t) > 60000 then return nil end
  local key = msg.t .. ":" .. msg.n
  if seen[key] then return nil end
  if sha256(cfg.secret .. "|" .. msg.p .. "|" .. msg.t .. "|" .. msg.n) ~= msg.sig then return nil end
  seen[key] = msg.t
  seenCount = seenCount + 1
  if seenCount > 300 then
    seenCount = 0
    for k, t in pairs(seen) do
      if now - t > 120000 then seen[k] = nil else seenCount = seenCount + 1 end
    end
  end
  local body = textutils.unserialize(msg.p)
  if type(body) ~= "table" then return nil end
  return body
end

function net.send(id, body)
  if net.hasPassword() and net.openModem() then rednet.send(id, net.wrap(body), PROTO) end
end
function net.broadcast(body)
  if net.hasPassword() and net.openModem() then rednet.broadcast(net.wrap(body), PROTO) end
end

---------------------------------------------------------------------
-- GAME SIDE
---------------------------------------------------------------------
local G
local myId = os.getComputerID()
local outbox = loadT(OUTBOX_FILE) or {}
local MAX_OUTBOX = 1000

function net.setupGame(g) G = g end

local function gameName()
  return os.getComputerLabel() or (G.kind .. " #" .. myId)
end

local function statusMsg()
  local s = G.status()
  s.type, s.id, s.kind, s.name = "status", myId, G.kind, gameName()
  local n = 0
  for _ in pairs(outbox) do n = n + 1 end
  s.pending = n
  return s
end

function net.pushStatus() os.queueEvent("casino_net_push") end

-- one call per player per round; kept on disk until the main computer confirms it
function net.report(player, wagered, returned)
  if not G or wagered <= 0 then return end
  local t = os.epoch("utc")
  local rid = myId .. "-" .. t .. "-" .. math.random(1, 999999)
  outbox[rid] = { rid = rid, player = player, wagered = wagered, returned = returned, t = t }
  local list = {}
  for k, r in pairs(outbox) do list[#list + 1] = r end
  if #list > MAX_OUTBOX then
    table.sort(list, function(x, y) return x.t < y.t end)
    for i = 1, #list - MAX_OUTBOX do outbox[list[i].rid] = nil end
  end
  saveT(OUTBOX_FILE, outbox)
  os.queueEvent("casino_net_flush")
end

local function sendReports()
  local list = {}
  for _, r in pairs(outbox) do list[#list + 1] = r end
  if #list == 0 then return end
  table.sort(list, function(x, y) return x.t < y.t end)
  local batch = {}
  for i = 1, math.min(20, #list) do batch[i] = list[i] end
  net.broadcast({ type = "reports", id = myId, kind = G.kind, name = gameName(), reports = batch })
end

function net.runGame()
  if not G then error("net.setupGame was never called", 0) end
  local timer = os.startTimer(1)
  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "timer" and a == timer then
      net.broadcast(statusMsg())
      sendReports()
      timer = os.startTimer(20)
    elseif ev == "casino_net_push" then
      net.broadcast(statusMsg())
    elseif ev == "casino_net_flush" then
      sendReports()
    elseif ev == "rednet_message" and c == PROTO then
      local body = net.unwrap(b)
      if body then
        if body.type == "ping" then
          net.broadcast(statusMsg())
          sendReports()
        elseif body.type == "ack" and body.to == myId then
          for _, rid in ipairs(body.rids or {}) do outbox[rid] = nil end
          saveT(OUTBOX_FILE, outbox)
          if next(outbox) then sendReports() end
        elseif body.type == "cmd" and body.to == myId then
          local ok, err = true, nil
          if body.cmd == "open" then G.setOpen(true)
          elseif body.cmd == "close" then G.setOpen(false)
          elseif body.cmd == "set" then ok, err = G.set(body.key, tonumber(body.value))
          else ok, err = false, "unknown command" end
          net.send(a, { type = "result", to = a, from = myId, ok = ok, err = err })
          net.broadcast(statusMsg())
        end
      end
    end
  end
end

return net
