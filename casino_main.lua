--[[
  casino_main.lua  -  MAIN CONTROL COMPUTER for the casino
  ---------------------------------------------------------------
  * Can be a normal ADVANCED computer (it never touches money)
  * Needs casino_net.lua in the same folder
  * Needs a WIRELESS or ENDER modem and an ADVANCED monitor
    (4 wide x 3 tall or bigger is comfortable)

  What it does
    - lists every casino game on the network, online/offline
    - OPEN / CLOSE any game (or all of them)
    - change each game's min / max bets
    - master ledger: every round from every game
        today + all-time handle, house net, hold %, swing (high / low)
        biggest house win / loss, per-player totals
    - files: main_ledger.log (every round), main_stats.dat (totals)

  The monitor only accepts changes while UNLOCKED. Type 'unlock' and
  your PIN on this computer to unlock it for 10 minutes.
]]

local net = require("casino_net")

local CONFIG = {
  textScale     = 0.5,
  unlockMinutes = 10,
  offlineAfter  = 70,      -- seconds without a heartbeat = OFFLINE
  keepDays      = 31,
}
local STEPS = { 1, 5, 25, 100, 1000 }
local STEP_LABELS = { "1", "5", "25", "100", "1K" }

local MAIN_FILE   = "casino_main.cfg"
local GAMES_FILE  = "main_games.dat"
local STATS_FILE  = "main_stats.dat"
local LEDGER_FILE = "main_ledger.log"

---------------------------------------------------------------------
-- saved data
---------------------------------------------------------------------
local M = net.loadT(MAIN_FILE) or { pin = "" }
local games = net.loadT(GAMES_FILE) or {}            -- [tostring(id)] = { id, name, kind, open, limits, lastSeen }

local function newStat()
  return { rounds = 0, handle = 0, paid = 0, net = 0, peak = 0, trough = 0, bigWin = 0, bigLoss = 0 }
end
local stats = net.loadT(STATS_FILE) or {}
stats.all     = stats.all or {}                       -- [game key] = stat
stats.total   = stats.total or newStat()
stats.days    = stats.days or {}                      -- [day] = { total = stat, games = { [key] = stat } }
stats.players = stats.players or {}                   -- [name] = { rounds, handle, paid }
stats.seen    = stats.seen or {}                      -- report ids already counted
stats.seenList = stats.seenList or {}

local function addStat(st, wagered, returned)
  local n = wagered - returned
  st.rounds  = st.rounds + 1
  st.handle  = st.handle + wagered
  st.paid    = st.paid + returned
  st.net     = st.net + n
  st.peak    = math.max(st.peak, st.net)
  st.trough  = math.min(st.trough, st.net)
  st.bigWin  = math.max(st.bigWin, n)
  st.bigLoss = math.min(st.bigLoss, n)
end

local function today() return os.date("%Y-%m-%d") end

local function pruneDays()
  local keys = {}
  for k in pairs(stats.days) do keys[#keys + 1] = k end
  table.sort(keys)
  for i = 1, #keys - CONFIG.keepDays do stats.days[keys[i]] = nil end
end

---------------------------------------------------------------------
-- monitor
---------------------------------------------------------------------
local mon = peripheral.find("monitor")
if not mon then error("No monitor found. Attach an advanced monitor.", 0) end
if not mon.isColor() then error("Needs an ADVANCED (gold) monitor.", 0) end
mon.setTextScale(CONFIG.textScale)
local monName = peripheral.getName(mon)
local W, H = mon.getSize()
if W < 54 or H < 24 then
  error(("Monitor too small (%dx%d). Build it at least 3 wide x 3 tall."):format(W, H), 0)
end
local scr = window.create(mon, 1, 1, W, H, true)

local BG = colors.black
local buttons = {}
local function addHit(x1, y1, x2, y2, act) buttons[#buttons + 1] = { x1, y1, x2, y2, act } end
local function trim(s, w) s = tostring(s); if #s > w then return s:sub(1, math.max(0, w)) end return s end
local function fill(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  scr.setBackgroundColor(bg)
  local s = string.rep(" ", w)
  for yy = y, y + h - 1 do scr.setCursorPos(x, yy); scr.write(s) end
end
local function txt(x, y, s, fg, bg)
  if y < 1 or y > H then return end
  scr.setCursorPos(x, y)
  scr.setTextColor(fg or colors.white)
  scr.setBackgroundColor(bg or BG)
  scr.write(s)
end
local function button(x, y, label, fg, bg, act)
  local w = #label + 2
  fill(x, y, w, 1, bg)
  txt(x + 1, y, label, fg, bg)
  if act then addHit(x, y, x + w - 1, y, act) end
  return w
end

local function commas(n)
  local s = tostring(math.floor(math.abs(n)))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return out
end
local function money(n) return (n < 0 and "-$" or "$") .. commas(n) end
local function smoney(n) return (n > 0 and "+$" or (n < 0 and "-$" or "$")) .. commas(n) end
local function netCol(n) return n > 0 and colors.lime or (n < 0 and colors.red or colors.lightGray) end
local function holdStr(st) if not st or st.handle <= 0 then return "-" end return ("%.1f%%"):format(st.net / st.handle * 100) end

---------------------------------------------------------------------
-- state
---------------------------------------------------------------------
local unlockedUntil = 0
local selected, stepIdx = nil, 2
local msg = "Waiting for games..."
local recent = {}          -- last rounds received (newest first)

local function isUnlocked() return os.epoch("utc") < unlockedUntil end
local function isOnline(g) return g.lastSeen and (os.epoch("utc") - g.lastSeen) < CONFIG.offlineAfter * 1000 end

local function sortedKeys()
  local keys = {}
  for k in pairs(games) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local na, nb = (games[a].name or a):lower(), (games[b].name or b):lower()
    if na == nb then return a < b end
    return na < nb
  end)
  return keys
end

local function redraw() os.queueEvent("main_redraw") end

---------------------------------------------------------------------
-- network handling
---------------------------------------------------------------------
local function handleStatus(b)
  local key = tostring(b.id)
  local g = games[key] or {}
  g.id, g.name, g.kind = b.id, b.name, b.kind
  g.open, g.limits, g.pending = b.open, b.limits, b.pending
  g.lastSeen = os.epoch("utc")
  games[key] = g
  if not selected then selected = key end
  net.saveT(GAMES_FILE, games)
end

local function handleReports(sender, b)
  local key = tostring(b.id)
  if games[key] then games[key].lastSeen = os.epoch("utc") end
  local acks = {}
  local changed = false
  local f = fs.open(LEDGER_FILE, "a")
  for _, r in ipairs(b.reports or {}) do
    if type(r) == "table" and type(r.rid) == "string" then
      acks[#acks + 1] = r.rid
      local w, ret = tonumber(r.wagered) or 0, tonumber(r.returned) or 0
      if not stats.seen[r.rid] and w > 0 then
        stats.seen[r.rid] = true
        stats.seenList[#stats.seenList + 1] = r.rid
        local day = os.date("%Y-%m-%d", math.floor((r.t or os.epoch("utc")) / 1000))
        stats.all[key] = stats.all[key] or newStat()
        addStat(stats.all[key], w, ret)
        addStat(stats.total, w, ret)
        local d = stats.days[day] or { total = newStat(), games = {} }
        d.games[key] = d.games[key] or newStat()
        addStat(d.games[key], w, ret)
        addStat(d.total, w, ret)
        stats.days[day] = d
        local pk = tostring(r.player)
        local p = stats.players[pk] or { rounds = 0, handle = 0, paid = 0 }
        p.rounds, p.handle, p.paid = p.rounds + 1, p.handle + w, p.paid + ret
        stats.players[pk] = p
        if f then
          f.writeLine(("%s\t%s\t%s\tbet %d\tpaid %d\thouse %+d"):format(
            os.date("%Y-%m-%d %H:%M:%S", math.floor((r.t or 0) / 1000)), b.name or key, tostring(r.player), w, ret, w - ret))
        end
        table.insert(recent, 1, { name = b.name or key, player = tostring(r.player), w = w, r = ret })
        if #recent > 40 then recent[#recent] = nil end
        changed = true
      end
    end
  end
  if f then f.close() end
  while #stats.seenList > 3000 do
    stats.seen[table.remove(stats.seenList, 1)] = nil
  end
  if changed then pruneDays(); net.saveT(STATS_FILE, stats) end
  if #acks > 0 then net.send(sender, { type = "ack", to = sender, rids = acks }) end
end

local function sendCmd(key, cmd, k, v)
  local g = games[key]
  if not g then return end
  if not isOnline(g) then msg = (g.name or key) .. " is offline"; return end
  net.send(g.id, { type = "cmd", to = g.id, cmd = cmd, key = k, value = v })
  msg = "Sent to " .. (g.name or key) .. "..."
end

---------------------------------------------------------------------
-- drawing
---------------------------------------------------------------------
local function render()
  buttons = {}
  scr.setVisible(false)
  scr.setBackgroundColor(BG)
  scr.clear()

  -- header
  fill(1, 1, W, 1, colors.gray)
  txt(2, 1, "CASINO CONTROL", colors.yellow, colors.gray)
  local lockLabel = isUnlocked()
    and ("UNLOCKED " .. math.ceil((unlockedUntil - os.epoch("utc")) / 60000) .. "m")
    or "LOCKED"
  local right = os.date("%H:%M") .. " "
  txt(W - #right, 1, right, colors.lightGray, colors.gray)
  local lx = W - #right - #lockLabel - 3
  fill(lx, 1, #lockLabel + 2, 1, isUnlocked() and colors.lime or colors.red)
  txt(lx + 1, 1, lockLabel, isUnlocked() and colors.black or colors.white, isUnlocked() and colors.lime or colors.red)
  if isUnlocked() then addHit(lx, 1, lx + #lockLabel + 1, 1, { t = "lock" }) end

  -- totals
  local td = (stats.days[today()] or {}).total or newStat()
  local at = stats.total
  txt(2, 3, "TODAY", colors.yellow)
  txt(12, 3, "handle " .. money(td.handle), colors.white)
  local s = "house " .. smoney(td.net)
  txt(32, 3, s, netCol(td.net))
  txt(34 + #s, 3, "hold " .. holdStr(td), colors.lightGray)
  txt(2, 4, "ALL TIME", colors.yellow)
  txt(12, 4, "handle " .. money(at.handle), colors.white)
  s = "house " .. smoney(at.net)
  txt(32, 4, s, netCol(at.net))
  txt(34 + #s, 4, "hold " .. holdStr(at), colors.lightGray)
  txt(2, 5, ("swing  high +$%s  low -$%s   biggest house win $%s / loss $%s"):format(
    commas(at.peak), commas(-at.trough), commas(at.bigWin), commas(-at.bigLoss)), colors.lightGray)

  -- game list
  local nameW = math.max(6, W - 49)
  local cName, cStat, cToday, cAll, cHold, cBtn = 2, 3 + nameW, 12 + nameW, 23 + nameW, 34 + nameW, W - 8
  local y = 7
  fill(1, y, W, 1, colors.gray)
  txt(cName, y, "GAME", colors.white, colors.gray)
  txt(cStat, y, "STATUS", colors.white, colors.gray)
  txt(cToday, y, "TODAY", colors.white, colors.gray)
  txt(cAll, y, "ALL TIME", colors.white, colors.gray)
  txt(cHold, y, "HOLD", colors.white, colors.gray)

  local keys = sortedKeys()
  local maxRows = math.max(3, math.floor((H - 8) / 2) - 2)
  y = 8
  if #keys == 0 then
    txt(2, y, "No games yet. Each game needs casino_net + a wireless modem + the same password.", colors.lightGray)
    y = y + 1
  end
  for i, key in ipairs(keys) do
    if i > maxRows then txt(2, y, "+" .. (#keys - maxRows) .. " more...", colors.lightGray); y = y + 1; break end
    local g = games[key]
    local online = isOnline(g)
    local rowBg = (key == selected) and colors.blue or BG
    fill(1, y, W, 1, rowBg)
    addHit(1, y, cBtn - 2, y, { t = "select", key = key })
    txt(cName, y, trim(g.name or key, nameW), online and colors.white or colors.lightGray, rowBg)
    if not online then txt(cStat, y, "OFFLINE", colors.gray, rowBg)
    elseif g.open then txt(cStat, y, "OPEN", colors.lime, rowBg)
    else txt(cStat, y, "CLOSED", colors.red, rowBg) end
    local dg = ((stats.days[today()] or {}).games or {})[key]
    local ag = stats.all[key]
    local dn, an = dg and dg.net or 0, ag and ag.net or 0
    txt(cToday, y, trim(smoney(dn), 10), netCol(dn), rowBg)
    txt(cAll, y, trim(smoney(an), 10), netCol(an), rowBg)
    txt(cHold, y, holdStr(ag), colors.lightGray, rowBg)
    if online then
      if g.open then button(cBtn, y, "CLOSE ", colors.white, colors.red, { t = "toggle", key = key })
      else button(cBtn, y, " OPEN ", colors.black, colors.lime, { t = "toggle", key = key }) end
    end
    y = y + 1
  end

  -- all-game buttons
  y = y + 1
  local bx = 2
  bx = bx + button(bx, y, "OPEN ALL", colors.black, colors.lime, { t = "all", open = true }) + 2
  bx = bx + button(bx, y, "CLOSE ALL", colors.white, colors.red, { t = "all", open = false }) + 2
  button(bx, y, "REFRESH", colors.white, colors.gray, { t = "ping" })

  -- selected game panel
  y = y + 2
  local g = selected and games[selected]
  if g then
    fill(1, y, W, 1, colors.gray)
    txt(2, y, trim((g.name or selected) .. "  (" .. tostring(g.kind) .. ", computer #" .. tostring(g.id) .. ")", W - 4),
      colors.yellow, colors.gray)
    y = y + 1
    -- step chips
    txt(2, y, "STEP", colors.lightGray)
    local sx = 7
    for i in ipairs(STEPS) do
      local lab = STEP_LABELS[i]
      local on = i == stepIdx
      sx = sx + button(sx, y, lab, on and colors.black or colors.white, on and colors.yellow or colors.gray, { t = "step", i = i }) + 1
    end
    y = y + 2
    -- limits
    local lx2 = 2
    for _, L in ipairs(g.limits or {}) do
      local label = trim(L.label or L.k, 10) .. " " .. money(L.v or 0)
      local need = #label + 10
      if lx2 + need > W then lx2 = 2; y = y + 2 end
      txt(lx2, y, label, colors.white)
      local px = lx2 + #label + 1
      px = px + button(px, y, "-", colors.white, colors.red, { t = "limit", k = L.k, v = L.v, dir = -1 }) + 1
      button(px, y, "+", colors.black, colors.lime, { t = "limit", k = L.k, v = L.v, dir = 1 })
      lx2 = lx2 + need + 2
    end
    y = y + 2
    local ag = stats.all[selected] or newStat()
    local dg = ((stats.days[today()] or {}).games or {})[selected] or newStat()
    txt(2, y, ("Today:    %d rounds  handle %s  house %s  hold %s"):format(dg.rounds, money(dg.handle), smoney(dg.net), holdStr(dg)), colors.white)
    txt(2, y + 1, ("All time: %d rounds  handle %s  house %s  hold %s"):format(ag.rounds, money(ag.handle), smoney(ag.net), holdStr(ag)), colors.white)
    txt(2, y + 2, ("Swing: high +$%s / low -$%s   biggest round: won $%s / lost $%s"):format(
      commas(ag.peak), commas(-ag.trough), commas(ag.bigWin), commas(-ag.bigLoss)), colors.lightGray)
    if (g.pending or 0) > 0 then txt(2, y + 3, g.pending .. " round(s) waiting to be sent from this game", colors.orange) end
    y = y + 5
  end

  -- recent rounds
  if y < H - 1 then
    fill(1, y, W, 1, colors.gray)
    txt(2, y, "RECENT ROUNDS", colors.white, colors.gray)
    y = y + 1
    for _, r in ipairs(recent) do
      if y >= H then break end
      local n = r.w - r.r
      txt(2, y, trim(r.name, 18), colors.lightGray)
      txt(21, y, trim(r.player, 16), colors.white)
      txt(38, y, trim("bet " .. money(r.w), 13), colors.white)
      txt(52, y, trim("house " .. smoney(n), W - 52), netCol(n))
      y = y + 1
    end
  end

  -- message line
  fill(1, H, W, 1, colors.gray)
  txt(2, H, trim(msg, W - 2), colors.white, colors.gray)
  scr.setVisible(true)
end

---------------------------------------------------------------------
-- touch actions
---------------------------------------------------------------------
local function doAction(a)
  if a.t == "select" then selected = a.key; return end
  if a.t == "step" then stepIdx = a.i; return end
  if a.t == "ping" then net.broadcast({ type = "ping" }); msg = "Asking all games to check in..."; return end
  if not isUnlocked() then msg = "LOCKED - type 'unlock' on the main computer"; return end
  if a.t == "lock" then unlockedUntil = 0; msg = "Locked"
  elseif a.t == "toggle" then
    local g = games[a.key]
    if g then sendCmd(a.key, g.open and "close" or "open") end
  elseif a.t == "all" then
    local n = 0
    for key, g in pairs(games) do
      if isOnline(g) then net.send(g.id, { type = "cmd", to = g.id, cmd = a.open and "open" or "close" }); n = n + 1 end
    end
    msg = (a.open and "Opening " or "Closing ") .. n .. " game(s)"
  elseif a.t == "limit" then
    local nv = math.max(1, (a.v or 0) + a.dir * STEPS[stepIdx])
    sendCmd(selected, "set", a.k, nv)
  end
end

local function ui()
  net.broadcast({ type = "ping" })
  local tick = os.startTimer(2)
  local pingT = os.startTimer(60)
  while true do
    render()
    local ev, a, b, c = os.pullEvent()
    if ev == "monitor_touch" and a == monName then
      for i = #buttons, 1, -1 do
        local bt = buttons[i]
        if b >= bt[1] and b <= bt[3] and c >= bt[2] and c <= bt[4] then doAction(bt[5]); break end
      end
    elseif ev == "rednet_message" and c == net.PROTO then
      local body = net.unwrap(b)
      if body then
        if body.type == "status" then handleStatus(body)
        elseif body.type == "reports" then handleReports(a, body)
        elseif body.type == "result" and body.to == os.getComputerID() then
          local g = games[tostring(body.from)]
          local nm = g and g.name or ("#" .. tostring(body.from))
          msg = body.ok and (nm .. ": done") or (nm .. ": " .. tostring(body.err))
        end
      end
    elseif ev == "timer" and a == tick then
      tick = os.startTimer(2)
    elseif ev == "timer" and a == pingT then
      net.broadcast({ type = "ping" })
      pingT = os.startTimer(60)
    end
  end
end

---------------------------------------------------------------------
-- console on the computer screen
---------------------------------------------------------------------
local HELP = {
  "unlock         unlock the monitor for " .. CONFIG.unlockMinutes .. " min",
  "lock           lock the monitor now",
  "games          list games and their computer IDs",
  "players        top players by house result",
  "forget <id>    remove a game you tore down",
  "pin / netpass  change PIN / network password",
  "quit",
}

local function console()
  term.clear(); term.setCursorPos(1, 1)
  term.setTextColor(colors.yellow); print("Casino main computer"); term.setTextColor(colors.white)
  print("Type 'unlock' to unlock the monitor. 'help' for commands.")
  while true do
    term.setTextColor(colors.yellow); write("main> "); term.setTextColor(colors.white)
    local line = read() or ""
    local wds = {}
    for wd in line:gmatch("%S+") do wds[#wds + 1] = wd end
    local cmd = (wds[1] or ""):lower()
    if cmd == "unlock" then
      write("PIN: ")
      if read("*") == M.pin then
        unlockedUntil = os.epoch("utc") + CONFIG.unlockMinutes * 60000
        print("Monitor unlocked for " .. CONFIG.unlockMinutes .. " minutes.")
        redraw()
      else print("Wrong PIN.") end
    elseif cmd == "help" then
      for _, l in ipairs(HELP) do print(l) end
    elseif cmd == "lock" then
      unlockedUntil = 0; print("Locked."); redraw()
    elseif cmd == "games" then
      for _, k in ipairs(sortedKeys()) do
        local g = games[k]
        print(("#%s  %s  %s"):format(k, tostring(g.name), isOnline(g) and (g.open and "OPEN" or "CLOSED") or "OFFLINE"))
      end
    elseif cmd == "players" then
      local list = {}
      for name, p in pairs(stats.players) do list[#list + 1] = { name = name, p = p } end
      table.sort(list, function(x, y) return (x.p.paid - x.p.handle) > (y.p.paid - y.p.handle) end)
      if #list == 0 then print("No rounds yet.") end
      for i = 1, math.min(10, #list) do
        local e = list[i]
        local pn = e.p.paid - e.p.handle
        print(("%-16s %4d rounds  bet %s  player %s"):format(e.name, e.p.rounds, money(e.p.handle), smoney(pn)))
      end
    elseif cmd == "forget" then
      if wds[2] and games[wds[2]] then
        games[wds[2]] = nil; net.saveT(GAMES_FILE, games)
        if selected == wds[2] then selected = nil end
        print("Removed."); redraw()
      else print("Usage: forget <computer id>  (see 'games')") end
    elseif cmd == "pin" then
      write("Current PIN: ")
      if read("*") == M.pin then
        write("New PIN: "); local p = read("*")
        if p and #p >= 3 then M.pin = p; net.saveT(MAIN_FILE, M); print("PIN changed.") else print("Too short.") end
      else print("Wrong PIN.") end
    elseif cmd == "netpass" then
      write("Current PIN: ")
      if read("*") == M.pin then
        write("New network password (must match every game): "); local p = read("*")
        if p and #p >= 4 then net.setPassword(p); print("Saved.") else print("Too short.") end
      else print("Wrong PIN.") end
    elseif cmd == "quit" then
      return
    elseif cmd ~= "" then
      print("Unknown. Type 'help'.")
    end
  end
end

---------------------------------------------------------------------
-- startup
---------------------------------------------------------------------
math.randomseed(os.epoch("utc"))
if M.pin == "" then
  term.clear(); term.setCursorPos(1, 1)
  print("First-time setup")
  repeat write("Choose a PIN for this computer (3+ chars): "); M.pin = read("*") until #M.pin >= 3
  net.saveT(MAIN_FILE, M)
end
if not net.hasPassword() then
  local p
  repeat
    write("Casino network password (4+ chars, use the SAME one on every game): ")
    p = read("*")
  until #p >= 4
  net.setPassword(p)
end
if not net.openModem() then
  print("WARNING: no wireless/ender modem found. Attach one, then restart.")
  print("Press any key.")
  os.pullEvent("key")
end

parallel.waitForAny(ui, console)

scr.setVisible(true)
mon.setBackgroundColor(colors.black)
mon.clear()
term.clear(); term.setCursorPos(1, 1)
print("Casino main closed.")
