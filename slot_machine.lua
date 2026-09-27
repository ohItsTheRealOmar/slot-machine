--[[
  BUFFALO BONUS - a CC:Tweaked slot machine
  Built for a 3x4 Advanced Monitor wall + one Computer.

  FEATURES
   - 5 reels x 4 rows, "ways to win" scoring (like real reel-slot cabinets)
   - WILD symbol substitutes for everything but the scatter
   - 3+ scatters trigger the BUFFALO BONUS free-spin round
   - Free spins have stacked wilds and a rising multiplier
   - Retriggers add more free spins mid-bonus
   - Touch-screen buttons (Advanced Monitor) + keyboard fallback on the computer

  SETUP
   1. Place a 3x4 wall of Advanced Monitors (3 wide, 4 tall).
   2. Place a Computer (Advanced Computer for color) touching the monitor wall.
   3. Optionally place a Speaker next to the computer for sound.
   4. On the computer: wget the raw URL of this file, then run it.
--]]

-- ============================= SETUP =============================
local mon = peripheral.find("monitor")
if not mon then
  error("No monitor found! Attach the 3x4 monitor wall to this computer.")
end
mon.setTextScale(0.5)
term.redirect(mon)
local w, h = term.getSize()

local speaker = peripheral.find("speaker")
local function sfx(name, vol, pitch)
  if speaker then pcall(speaker.playSound, name, vol or 1, pitch or 1) end
end

math.randomseed(os.epoch("utc"))

local c = colors

-- ============================= STATE =============================
local credits = 1000
local bet = 10
local betStep = 5
local minBet, maxBet = 5, 200
local currentGrid = nil -- last grid shown; drawFrame always redraws this so the screen never goes blank

-- ============================= BACKGROUND IMAGE =============================
-- Optional: drop an .nfp image (CC:Tweaked's "paint" format) next to this
-- script and it will be used as the background behind the reels/HUD.
--   * Make one in-game: run `paint bg.nfp` on the computer and draw it, or
--   * Convert a picture with an online "image to nfp" converter, then
--     wget its raw URL to bg.nfp on this computer, same as this script.
-- Change BG_IMAGE_PATH below if you name the file something else.
local BG_IMAGE_PATH = "bg.nfp"
local bgImage = nil
if fs.exists(BG_IMAGE_PATH) then
  local ok, img = pcall(paintutils.loadImage, BG_IMAGE_PATH)
  if ok then bgImage = img end
end

local function drawBackground()
  term.setBackgroundColor(colors.black)
  term.clear()
  if bgImage then
    pcall(paintutils.drawImage, bgImage, 1, 1)
  end
end

-- ============================= SYMBOLS =============================
-- pay = payout multiplier of (bet/10) per "way", by number of consecutive
-- reels (starting at reel 1) that contain the symbol (or a WILD).
local SYM = {
  WILD = { label = "WILD", fg = c.black,     bg = c.yellow,    wild = true },
  SCAT = { label = "COIN", fg = c.white,     bg = c.orange,    scatter = true },
  BUF  = { label = "BUFF", fg = c.white,     bg = c.brown,     pay = {[3]=5, [4]=25, [5]=150} },
  EAG  = { label = "EAGL", fg = c.black,     bg = c.lightGray, pay = {[3]=4, [4]=15, [5]=75} },
  WLF  = { label = "WOLF", fg = c.white,     bg = c.gray,      pay = {[3]=3, [4]=10, [5]=50} },
  ELK  = { label = "ELK ", fg = c.black,     bg = c.lime,      pay = {[3]=2, [4]=8,  [5]=40} },
  A    = { label = " A  ", fg = c.white,     bg = c.red,       pay = {[3]=1, [4]=4,  [5]=20} },
  K    = { label = " K  ", fg = c.white,     bg = c.blue,      pay = {[3]=1, [4]=3,  [5]=15} },
  Q    = { label = " Q  ", fg = c.white,     bg = c.purple,    pay = {[3]=1, [4]=3,  [5]=15} },
  J    = { label = " J  ", fg = c.black,     bg = c.green,     pay = {[3]=1, [4]=2,  [5]=10} },
}

local baseWeights  = { WILD=2, SCAT=2, BUF=4, EAG=5, WLF=6, ELK=7, A=9, K=9, Q=9, J=9 }
local bonusWeights = { WILD=6, SCAT=1, BUF=5, EAG=5, WLF=6, ELK=6, A=8, K=8, Q=8, J=8 }
local scatterSpins = { [3]=8, [4]=15, [5]=20 }

local REELS, ROWS = 5, 4

local function buildStrip(weights)
  local strip = {}
  for key, count in pairs(weights) do
    for _ = 1, count do strip[#strip+1] = key end
  end
  return strip
end

local function pickSymbol(strip)
  return strip[math.random(#strip)]
end

local function genGrid(weights, stackChance)
  local strip = buildStrip(weights)
  local grid = {}
  for r = 1, REELS do
    grid[r] = {}
    local forceWild = stackChance and math.random(1, 100) <= stackChance
    for row = 1, ROWS do
      grid[r][row] = forceWild and "WILD" or pickSymbol(strip)
    end
  end
  return grid
end

-- ============================= LAYOUT =============================
local marginX, topY = 2, 3
local hudH = 3
local reelAreaW = w - marginX * 2
local reelAreaH = h - topY - hudH - 1

-- Shrink the reel squares so more of the background image shows through
-- around and between them, then center the whole grid in the screen.
local REEL_SCALE = 0.75
local cellW = math.max(4, math.floor((reelAreaW / REELS) * REEL_SCALE))
local cellH = math.max(3, math.floor((reelAreaH / ROWS) * REEL_SCALE))
local gridWidth = cellW * REELS
local gridHeight = cellH * ROWS
local gridX0 = math.floor((w - gridWidth) / 2) + 1
local gridY0 = topY + math.floor(math.max(0, reelAreaH - gridHeight) / 2)

local function cellPos(r, row)
  return gridX0 + (r - 1) * cellW, gridY0 + (row - 1) * cellH
end

local function drawCell(r, row, key, invert)
  local sym = SYM[key]
  local x, y = cellPos(r, row)
  term.setBackgroundColor(invert and colors.white or sym.bg)
  term.setTextColor(invert and colors.black or sym.fg)
  for yy = 0, cellH - 2 do
    term.setCursorPos(x, y + yy)
    term.write(string.rep(" ", math.max(1, cellW - 1)))
  end
  local lbl = sym.label
  term.setCursorPos(x + math.max(0, math.floor((cellW - 1 - #lbl) / 2)), y + math.floor((cellH - 2) / 2))
  term.write(lbl)
end

local function centerText(y, text, fg)
  term.setTextColor(fg or colors.white)
  term.setBackgroundColor(colors.black)
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  term.setCursorPos(x, y)
  term.write(text)
end

local buttons = {}
local function addButton(label, x1, y1, x2, action)
  table.insert(buttons, { label = label, x1 = x1, y1 = y1, x2 = x2, y2 = y1, action = action })
end

local function drawHud(message, msgColor)
  term.setBackgroundColor(colors.black)
  for yy = h - hudH, h do
    term.setCursorPos(1, yy)
    term.write(string.rep(" ", w))
  end
  term.setTextColor(colors.white)
  term.setCursorPos(2, h - hudH)
  term.write("CREDITS: " .. credits .. "    BET: " .. bet)
  if message then
    term.setTextColor(msgColor or colors.yellow)
    term.setCursorPos(2, h - hudH + 1)
    term.write(message)
  end
end

local function drawButtons()
  buttons = {}
  local by = h
  local specs = {
    { "-BET", 2 },
    { "+BET", 9 },
    { "MAXBET", 16 },
    { "SPIN!", w - 8 },
  }
  for _, s in ipairs(specs) do
    local label, x = s[1], s[2]
    term.setBackgroundColor(colors.lightBlue)
    term.setTextColor(colors.black)
    term.setCursorPos(x, by)
    term.write(" " .. label .. " ")
    addButton(label, x, by, x + #label + 1, label)
  end
  term.setBackgroundColor(colors.black)
end

local function drawFrame(message, msgColor)
  drawBackground()
  centerText(1, "== B U F F A L O   B O N U S ==", colors.orange)
  drawHud(message, msgColor)
  drawButtons()
  if currentGrid then
    for r = 1, REELS do
      for row = 1, ROWS do
        drawCell(r, row, currentGrid[r][row])
      end
    end
  end
end

local function drawGrid(grid, highlights)
  highlights = highlights or {}
  for r = 1, REELS do
    for row = 1, ROWS do
      local hl = highlights[r] and highlights[r][row]
      drawCell(r, row, grid[r][row], hl)
    end
  end
end

-- ============================= ANIMATION =============================
local function animateSpin(finalGrid, weights)
  local strip = buildStrip(weights)
  local totalFrames = 22
  for frame = 1, totalFrames do
    for r = 1, REELS do
      local stopFrame = totalFrames - (REELS - r) * 3
      if frame < stopFrame then
        for row = 1, ROWS do drawCell(r, row, pickSymbol(strip)) end
      else
        for row = 1, ROWS do drawCell(r, row, finalGrid[r][row]) end
      end
    end
    sfx("minecraft:block.note_block.hat", 1, 1 + frame * 0.03)
    sleep(0.05)
  end
  drawGrid(finalGrid)
end

local function flashWin(grid, hitReels)
  for i = 1, 4 do
    drawGrid(grid, hitReels)
    sfx("minecraft:entity.experience_orb.pickup", 1, 1)
    sleep(0.18)
    drawGrid(grid)
    sleep(0.12)
  end
  drawGrid(grid, hitReels)
end

local function bannerAnim(text, col, holdTime)
  for i = 1, 3 do
    term.setBackgroundColor(colors.black)
    for yy = gridY0, gridY0 + ROWS * cellH do
      term.setCursorPos(1, yy); term.write(string.rep(" ", w))
    end
    if i % 2 == 1 then
      centerText(math.floor(h / 2), text, col)
    end
    sfx("minecraft:entity.player.levelup", 1, 1 + i * 0.1)
    sleep(0.3)
  end
  centerText(math.floor(h / 2), text, col)
  sleep(holdTime or 1)
end

-- ============================= SCORING =============================
local function evaluateWays(grid)
  local total, hits = 0, {}
  for key, sym in pairs(SYM) do
    if sym.pay then
      local consecutive, waysMult = 0, 1
      for r = 1, REELS do
        local count = 0
        for row = 1, ROWS do
          local s = grid[r][row]
          if s == key or SYM[s].wild then count = count + 1 end
        end
        if count > 0 then
          consecutive = consecutive + 1
          waysMult = waysMult * count
        else
          break
        end
      end
      if consecutive >= 3 and sym.pay[consecutive] then
        local amount = sym.pay[consecutive] * waysMult * (bet / 10)
        total = total + amount
        for r = 1, consecutive do
          hits[r] = hits[r] or {}
          for row = 1, ROWS do
            local s = grid[r][row]
            if s == key or SYM[s].wild then hits[r][row] = true end
          end
        end
      end
    end
  end
  return math.floor(total + 0.5), hits
end

local function countScatters(grid)
  local n = 0
  for r = 1, REELS do
    for row = 1, ROWS do
      if grid[r][row] == "SCAT" then n = n + 1 end
    end
  end
  return n
end

-- ============================= BONUS ROUND =============================
local function runBonus(triggerScatters)
  local freeSpins = scatterSpins[math.min(triggerScatters, 5)] or 8
  local multiplier = 1
  local bonusTotal = 0

  bannerAnim("BUFFALO BONUS TRIGGERED!", colors.orange, 1.5)

  while freeSpins > 0 do
    freeSpins = freeSpins - 1
    drawFrame()
    centerText(2, "FREE SPINS LEFT: " .. (freeSpins + 1) .. "   MULT x" .. multiplier, colors.lime)

    local grid = genGrid(bonusWeights, 20) -- 20% chance any reel is fully wild
    currentGrid = grid
    animateSpin(grid, bonusWeights)

    local win, hits = evaluateWays(grid)
    win = win * multiplier
    if win > 0 then
      bonusTotal = bonusTotal + win
      flashWin(grid, hits)
      drawHud("YOU WIN " .. win .. "!", colors.lime)
    else
      drawHud("NO WIN THIS FREE SPIN", colors.red)
    end
    sleep(1.2)

    local sc = countScatters(grid)
    if sc >= 3 then
      local add = scatterSpins[math.min(sc, 5)] or 5
      freeSpins = freeSpins + add
      multiplier = multiplier + 1
      bannerAnim("RETRIGGER! +" .. add .. " SPINS", colors.magenta, 1.2)
    end
  end

  credits = credits + bonusTotal
  bannerAnim("BONUS TOTAL: " .. bonusTotal .. "!", colors.yellow, 2)
end

-- ============================= MAIN SPIN =============================
local spinning = false
local function doSpin()
  if spinning then return end
  if credits < bet then
    drawHud("NOT ENOUGH CREDITS")
    return
  end
  spinning = true
  credits = credits - bet
  drawFrame()

  local grid = genGrid(baseWeights, nil)
  currentGrid = grid
  animateSpin(grid, baseWeights)

  local win, hits = evaluateWays(grid)
  local scatters = countScatters(grid)

  if win > 0 then
    credits = credits + win
    flashWin(grid, hits)
    drawHud("YOU WIN " .. win .. "!", colors.lime)
  else
    drawHud("NO WIN - TRY AGAIN", colors.red)
  end
  sleep(1.5)

  if scatters >= 3 then
    runBonus(scatters)
  end

  drawFrame()
  spinning = false
end

-- ============================= INPUT =============================
local function changeBet(delta)
  bet = math.max(minBet, math.min(maxBet, bet + delta))
  drawHud()
end

local function handleButton(label)
  if label == "SPIN!" then doSpin()
  elseif label == "-BET" then changeBet(-betStep)
  elseif label == "+BET" then changeBet(betStep)
  elseif label == "MAXBET" then bet = math.min(maxBet, credits); drawHud()
  end
end

local function pointInButton(x, y, b)
  return x >= b.x1 and x <= b.x2 and y == b.y1
end

-- ============================= BOOT =============================
currentGrid = genGrid(baseWeights, nil)
drawFrame()
centerText(2, "TOUCH SPIN OR PRESS [SPACE]   BET +/- WITH KEYS", colors.lightGray)

while true do
  local event, p1, p2, p3 = os.pullEvent()
  if event == "monitor_touch" then
    local x, y = p2, p3
    for _, b in ipairs(buttons) do
      if pointInButton(x, y, b) then
        handleButton(b.action)
        break
      end
    end
  elseif event == "key" then
    if p1 == keys.space then doSpin()
    elseif p1 == keys.minus then changeBet(-betStep)
    elseif p1 == keys.equals or p1 == keys.plus then changeBet(betStep)
    elseif p1 == keys.m then bet = math.min(maxBet, credits); drawHud()
    end
  end
end
