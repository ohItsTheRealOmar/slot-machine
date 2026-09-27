-- ===============================================
--  CC: Tweaked Slot Machine
--  3x3 grid slot machine with denominations,
--  paylines, and per-symbol multipliers.
-- ===============================================

local BALANCE_FILE = "slot_balance.txt"

local SYMBOLS = {
  { name = "SEVEN",   weight = 3,  mult = 50, color = colors.red },
  { name = "DIAMOND", weight = 7,  mult = 25, color = colors.lightBlue },
  { name = "BELL",    weight = 15, mult = 15, color = colors.yellow },
  { name = "BAR",     weight = 20, mult = 10, color = colors.orange },
  { name = "CLOVER",  weight = 25, mult = 5,  color = colors.green },
  { name = "CHERRY",  weight = 30, mult = 3,  color = colors.pink },
}

local DENOMS = { 0.01, 0.05, 0.10, 0.25, 0.50, 1.00 }

-- Paylines: each is a list of {row, col} across the 3x3 grid
local PAYLINES = {
  { name = "Top Row",     cells = {{1,1},{1,2},{1,3}} },
  { name = "Middle Row",  cells = {{2,1},{2,2},{2,3}} },
  { name = "Bottom Row",  cells = {{3,1},{3,2},{3,3}} },
  { name = "Diagonal \\", cells = {{1,1},{2,2},{3,3}} },
  { name = "Diagonal /",  cells = {{3,1},{2,2},{1,3}} },
}

local state = {
  balance = 100.00,
  denomIndex = 1,
  lines = 1,
  grid = {},       -- 3x3 of symbol tables
  results = {},    -- list of strings from last spin
  lastWin = 0,
}

-- ---------- persistence ----------

local function loadBalance()
  if fs.exists(BALANCE_FILE) then
    local f = fs.open(BALANCE_FILE, "r")
    local v = tonumber(f.readAll())
    f.close()
    if v then state.balance = v end
  end
end

local function saveBalance()
  local f = fs.open(BALANCE_FILE, "w")
  f.write(tostring(state.balance))
  f.close()
end

-- ---------- game logic ----------

local function totalWeight()
  local t = 0
  for _, s in ipairs(SYMBOLS) do t = t + s.weight end
  return t
end

local function pickSymbol()
  local r = math.random(1, totalWeight())
  local cum = 0
  for _, s in ipairs(SYMBOLS) do
    cum = cum + s.weight
    if r <= cum then return s end
  end
  return SYMBOLS[#SYMBOLS]
end

local function spinGrid()
  local g = {}
  for row = 1, 3 do
    g[row] = {}
    for col = 1, 3 do
      g[row][col] = pickSymbol()
    end
  end
  return g
end

local function denom()
  return DENOMS[state.denomIndex]
end

local function totalBet()
  return denom() * state.lines
end

local function evaluateSpin()
  local results = {}
  local totalWin = 0
  for i = 1, state.lines do
    local line = PAYLINES[i]
    local s1 = state.grid[line.cells[1][1]][line.cells[1][2]]
    local s2 = state.grid[line.cells[2][1]][line.cells[2][2]]
    local s3 = state.grid[line.cells[3][1]][line.cells[3][2]]
    if s1.name == s2.name and s2.name == s3.name then
      local win = denom() * s1.mult
      totalWin = totalWin + win
      table.insert(results, string.format(
        "%s: %s x3 -> WIN %.2f (x%d)", line.name, s1.name, win, s1.mult))
    end
  end
  return results, totalWin
end

-- ---------- monitor setup ----------

-- If a monitor is attached (directly adjacent, or via wired modem), draw the
-- game on it instead of the computer's own screen. You still control the
-- game by typing on the computer itself; the monitor just mirrors the display.
local monitor = peripheral.find("monitor")
if monitor then
  monitor.setTextScale(0.5) -- finer resolution so a multi-block monitor has room for the grid + buttons; try 1 for bigger, chunkier text
  term.redirect(monitor)
end

-- ---------- rendering ----------

local W, H = term.getSize()

local function centerText(y, text, color)
  term.setCursorPos(math.floor((W - #text) / 2) + 1, y)
  term.setTextColor(color or colors.white)
  term.write(text)
end

local CELL_W, CELL_H = 9, 3
local GRID_X = math.floor((W - (CELL_W * 3 + 2)) / 2) + 1
local GRID_Y = 5

local function drawCell(x, y, symbol)
  term.setBackgroundColor(symbol.color)
  term.setTextColor(colors.black)
  for row = 0, CELL_H - 1 do
    term.setCursorPos(x, y + row)
    if row == 1 then
      local text = symbol.name
      if #text > CELL_W then text = text:sub(1, CELL_W) end
      local pad = math.floor((CELL_W - #text) / 2)
      term.write(string.rep(" ", pad) .. text .. string.rep(" ", CELL_W - pad - #text))
    else
      term.write(string.rep(" ", CELL_W))
    end
  end
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
end

local function drawGrid()
  for row = 1, 3 do
    for col = 1, 3 do
      local x = GRID_X + (col - 1) * (CELL_W + 1)
      local y = GRID_Y + (row - 1) * (CELL_H + 1)
      drawCell(x, y, state.grid[row][col])
    end
  end
end

-- ---------- touch buttons ----------
-- Buttons are hit-tested against monitor_touch x/y (character-cell coords,
-- same coordinate space as term.setCursorPos on the redirected monitor).

local buttons = {}

local function setupButtons()
  local btnH = 3
  local y1 = H - btnH + 1
  local y2 = H

  buttons = {
    { label = "DENOM -", x1 = 2,      x2 = 10,     action = "denomDown" },
    { label = "DENOM +", x1 = 12,     x2 = 20,     action = "denomUp" },
    { label = "LINES -", x1 = W - 19, x2 = W - 11, action = "linesDown" },
    { label = "LINES +", x1 = W - 9,  x2 = W - 1,  action = "linesUp" },
  }

  local spinW = 14
  local spinX1 = math.floor((W - spinW) / 2) + 1
  table.insert(buttons, { label = "SPIN", x1 = spinX1, x2 = spinX1 + spinW - 1, action = "spin" })

  for _, b in ipairs(buttons) do
    b.y1 = y1
    b.y2 = y2
  end
end

local function drawButtons()
  for _, b in ipairs(buttons) do
    local bg = (b.action == "spin") and colors.lime or colors.gray
    term.setBackgroundColor(bg)
    term.setTextColor(colors.black)
    local w = b.x2 - b.x1 + 1
    for y = b.y1, b.y2 do
      term.setCursorPos(b.x1, y)
      if y == math.floor((b.y1 + b.y2) / 2) then
        local pad = math.floor((w - #b.label) / 2)
        term.write(string.rep(" ", pad) .. b.label .. string.rep(" ", w - pad - #b.label))
      else
        term.write(string.rep(" ", w))
      end
    end
  end
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
end

local function hitTest(x, y)
  for _, b in ipairs(buttons) do
    if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
      return b.action
    end
  end
  return nil
end

local function draw()
  term.setBackgroundColor(colors.black)
  term.clear()
  centerText(1, "=== SLOT MACHINE ===", colors.lime)
  centerText(2, string.format("Balance: %.2f", state.balance), colors.white)
  centerText(3, string.format("Denomination: %.2f   Lines: %d/%d   Bet: %.2f",
    denom(), state.lines, #PAYLINES, totalBet()), colors.lightGray)

  drawGrid()

  local resultY = GRID_Y + 3 * (CELL_H + 1) + 1
  if #state.results == 0 then
    term.setCursorPos(2, resultY)
    term.setTextColor(colors.gray)
    term.write("Tap SPIN to play")
  else
    for i, line in ipairs(state.results) do
      term.setCursorPos(2, resultY + i - 1)
      term.setTextColor(colors.yellow)
      term.write(line)
    end
    term.setCursorPos(2, resultY + #state.results + 1)
    if state.lastWin > 0 then
      term.setTextColor(colors.lime)
      term.write(string.format("Total win: %.2f", state.lastWin))
    else
      term.setTextColor(colors.red)
      term.write("No win this spin.")
    end
  end

  drawButtons()
end

-- ---------- input / main loop ----------

local function changeDenom(dir)
  state.denomIndex = state.denomIndex + dir
  if state.denomIndex < 1 then state.denomIndex = 1 end
  if state.denomIndex > #DENOMS then state.denomIndex = #DENOMS end
end

local function changeLines(dir)
  state.lines = state.lines + dir
  if state.lines < 1 then state.lines = 1 end
  if state.lines > #PAYLINES then state.lines = #PAYLINES end
end

local function doSpin()
  local bet = totalBet()
  if state.balance < bet then
    state.results = { "Not enough balance for this bet!" }
    state.lastWin = 0
    return
  end
  state.balance = state.balance - bet
  state.grid = spinGrid()
  local results, win = evaluateSpin()
  state.balance = state.balance + win
  state.results = results
  state.lastWin = win
  saveBalance()
end

local function handleAction(action)
  if action == "spin" then
    doSpin()
  elseif action == "denomUp" then
    changeDenom(1)
  elseif action == "denomDown" then
    changeDenom(-1)
  elseif action == "linesUp" then
    changeLines(1)
  elseif action == "linesDown" then
    changeLines(-1)
  end
end

local function main()
  math.randomseed(os.epoch("utc"))
  loadBalance()
  state.grid = spinGrid()
  setupButtons()

  while true do
    draw()
    local event, a, b, c = os.pullEvent()

    if event == "monitor_touch" then
      -- a = side, b = x, c = y
      handleAction(hitTest(b, c))

    elseif event == "key" then
      local key = a
      if key == keys.left then
        changeDenom(-1)
      elseif key == keys.right then
        changeDenom(1)
      elseif key == keys.up then
        changeLines(1)
      elseif key == keys.down then
        changeLines(-1)
      elseif key == keys.space or key == keys.enter then
        doSpin()
      elseif key == keys.q then
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(1, 1)
        saveBalance()
        print("Thanks for playing! Balance saved: " .. string.format("%.2f", state.balance))
        return
      end
    end
  end
end

main()
