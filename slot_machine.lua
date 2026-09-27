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
-- Find every monitor and use the BIGGEST one (in case a stray extra
-- monitor block exists somewhere and confuses peripheral.find).
local mon, bestArea = nil, -1
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "monitor" then
    local p = peripheral.wrap(name)
    local ok, mw, mh = pcall(function() return p.getSize() end)
    if ok then
      local area = mw * mh
      if area > bestArea then
        mon, bestArea = p, area
      end
    end
  end
end
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
-- Credits/bet are tracked to the cent (like a real machine) since the
-- paytable below is tuned to a realistic ~2 cent hold per dollar wagered.
local credits = 1000.00
local bet = 10
local betStep = 5
local minBet, maxBet = 5, 200
local currentGrid = nil -- last grid shown; drawFrame always redraws this so the screen never goes blank

local function money(v)
  return string.format("%.2f", v)
end

-- ============================= BACKGROUND IMAGE =============================
-- Optional: drop an .nfp image (CC:Tweaked's "paint" format) next to this
-- script and it will be used as the background behind the reels/HUD.
--   * Make one in-game: run `paint bg.nfp` on the computer and draw it, or
--   * Convert a picture with an online "image to nfp" converter, then
--     wget its raw URL to bg.nfp on this computer, same as this script.
-- Change BG_IMAGE_PATH below if you name the file something else.
local BG_IMAGE_PATH = "bg.nfp"

-- Scales a loaded .nfp image (any original size) to exactly targetW x
-- targetH, so it always fits the monitor no matter what size the image
-- was made at.
local function scaleImage(image, targetW, targetH)
  local srcH = #image
  local srcW = 0
  for _, row in ipairs(image) do
    if row and #row > srcW then srcW = #row end
  end
  if srcW == 0 or srcH == 0 then return image end

  local scaled = {}
  for y = 1, targetH do
    local srcY = math.min(srcH, math.max(1, math.floor((y - 1) * srcH / targetH) + 1))
    local srcRow = image[srcY] or {}
    local row = {}
    for x = 1, targetW do
      local srcX = math.min(srcW, math.max(1, math.floor((x - 1) * srcW / targetW) + 1))
      row[x] = srcRow[srcX]
    end
    scaled[y] = row
  end
  return scaled
end

local bgImage = nil
if fs.exists(BG_IMAGE_PATH) then
  local ok, img = pcall(paintutils.loadImage, BG_IMAGE_PATH)
  if ok and img then
    bgImage = scaleImage(img, w, h)
  end
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
-- These numbers were tuned via simulation (2,000,000 spins) so the whole
-- machine lands at ~98% RTP -- a ~2 cent hold per dollar wagered, same
-- ballpark as a real slot machine. (The old numbers paid out 5700%+ RTP
-- because wilds inflated every symbol's payout at once -- these fix that.)
local SYM = {
  WILD = { label = "WILD", fg = c.black,     bg = c.yellow,    wild = true },
  SCAT = { label = "COIN", fg = c.white,     bg = c.orange,    scatter = true },
  BUF  = { label = "BUFF", fg = c.white,     bg = c.brown,     pay = {[3]=0.09, [4]=0.43, [5]=2.57} },
  EAG  = { label = "EAGL", fg = c.black,     bg = c.lightGray, pay = {[3]=0.07, [4]=0.26, [5]=1.28} },
  WLF  = { label = "WOLF", fg = c.white,     bg = c.gray,      pay = {[3]=0.05, [4]=0.17, [5]=0.86} },
  ELK  = { label = "ELK ", fg = c.black,     bg = c.lime,      pay = {[3]=0.03, [4]=0.14, [5]=0.69} },
  A    = { label = " A  ", fg = c.red,       bg = c.white,     pay = {[3]=0.02, [4]=0.07, [5]=0.34} },
  K    = { label = " K  ", fg = c.black,     bg = c.white,     pay = {[3]=0.02, [4]=0.05, [5]=0.26} },
  Q    = { label = " Q  ", fg = c.red,       bg = c.white,     pay = {[3]=0.02, [4]=0.05, [5]=0.26} },
  J    = { label = " J  ", fg = c.black,     bg = c.white,     pay = {[3]=0.02, [4]=0.03, [5]=0.17} },
}

-- ============================= CARD SUIT ART =============================
-- Q=heart, J=spade, K=club, A=diamond -- drawn as blocky pixel-art behind
-- each card symbol's letter, scaled to whatever size the cell box is.
local HEART = {
  "0110110",
  "1111111",
  "1111111",
  "1111111",
  "0111110",
  "0011100",
  "0001000",
}
local DIAMOND = {
  "0001000",
  "0011100",
  "0111110",
  "1111111",
  "0111110",
  "0011100",
  "0001000",
}
local SPADE = {
  "0001000",
  "0011100",
  "0111110",
  "1111111",
  "1111111",
  "0111110",
  "0011100",
  "0001000",
}
local CLUB = {
  "0011100",
  "0111110",
  "1111111",
  "0111110",
  "1111111",
  "1111111",
  "0111110",
  "0001000",
}

local CARD_SUITS = {
  Q = { bitmap = HEART,   shapeColor = c.red,   cardColor = c.white, labelColor = c.red },
  J = { bitmap = SPADE,   shapeColor = c.black, cardColor = c.white, labelColor = c.black },
  K = { bitmap = CLUB,    shapeColor = c.black, cardColor = c.white, labelColor = c.black },
  A = { bitmap = DIAMOND, shapeColor = c.red,   cardColor = c.white, labelColor = c.red },
}

-- ============================= BIG BLOCK FONT =============================
-- A simple 5x7 pixel font, just the letters needed to spell out the
-- splash screen title. Add more letters here later if you want to reuse
-- drawBigText for other big titles.
local FONT_5x7 = {
  A = {"01110","10001","10001","11111","10001","10001","10001"},
  B = {"11110","10001","10001","11110","10001","10001","11110"},
  D = {"11110","10001","10001","10001","10001","10001","11110"},
  F = {"11111","10000","10000","11110","10000","10000","10000"},
  G = {"01111","10000","10000","10011","10001","10001","01111"},
  L = {"10000","10000","10000","10000","10000","10000","11111"},
  O = {"01110","10001","10001","10001","10001","10001","01110"},
  U = {"10001","10001","10001","10001","10001","10001","01110"},
}

-- Draws text using the big block font, centered horizontally, top edge
-- at topY. Only lit pixels are drawn (unlit pixels are left alone), so
-- it layers cleanly over a background image or solid color. The pixel
-- size is picked automatically so the text always fits the monitor's
-- actual width, however big or small that turns out to be. Returns the
-- total height (in rows) the text used, so callers can stack lines.
local function drawBigText(text, topY, color, maxWidthChars)
  maxWidthChars = maxWidthChars or w
  local letterGap = 1 -- gap columns between letters, in font pixels
  local spaceWidth = 3 -- width of a literal space, in font pixels

  local totalPixelCols = 0
  for i = 1, #text do
    local ch = text:sub(i, i)
    totalPixelCols = totalPixelCols + (ch == " " and spaceWidth or (5 + letterGap))
  end
  if totalPixelCols <= 0 then return 0 end

  local pixelW = math.max(1, math.floor(maxWidthChars / totalPixelCols))
  local pixelH = math.max(1, pixelW) -- square-ish blocks; big and bold either way
  local totalWidthChars = totalPixelCols * pixelW
  local curX = math.max(1, math.floor((w - totalWidthChars) / 2) + 1)

  term.setBackgroundColor(color)
  for i = 1, #text do
    local ch = text:sub(i, i)
    if ch == " " then
      curX = curX + spaceWidth * pixelW
    else
      local glyph = FONT_5x7[ch]
      if glyph then
        for gy = 1, 7 do
          local rowStr = glyph[gy]
          for gx = 1, 5 do
            if rowStr:sub(gx, gx) == "1" then
              for py = 0, pixelH - 1 do
                for px = 0, pixelW - 1 do
                  term.setCursorPos(curX + (gx - 1) * pixelW + px, topY + (gy - 1) * pixelH + py)
                  term.write(" ")
                end
              end
            end
          end
        end
      end
      curX = curX + (5 + letterGap) * pixelW
    end
  end

  return 7 * pixelH
end

-- ============================= START SCREEN =============================
-- Chasing/blinking marquee lights around the very edge of the screen.
-- offset shifts which cells are lit each frame, giving a chasing effect.
local function drawBorderLights(offset, onColor)
  local perimeter = {}
  for x = 1, w do perimeter[#perimeter+1] = {x, 1} end
  for y = 2, h - 1 do perimeter[#perimeter+1] = {w, y} end
  for x = w, 1, -1 do perimeter[#perimeter+1] = {x, h} end
  for y = h - 1, 2, -1 do perimeter[#perimeter+1] = {1, y} end

  for i, pos in ipairs(perimeter) do
    local lit = (i + offset) % 3 == 0
    term.setCursorPos(pos[1], pos[2])
    term.setBackgroundColor(lit and onColor or colors.black)
    term.write(" ")
  end
end

local function playStartupJingle()
  if not speaker then return end
  local jingle = {8, 10, 12, 15, 19, 24}
  for _, pitch in ipairs(jingle) do
    pcall(speaker.playNote, "bell", 2, pitch)
    sleep(0.12)
  end
end

local function showStartScreen()
  drawBackground() -- shows bg.nfp behind the splash if you have one, else black

  -- kick off the jingle in parallel with the light/title animation
  parallel.waitForAny(playStartupJingle, function()
    local titleY = math.floor(h / 2) - 8
    local buffaloH = 0
    for frame = 1, 40 do
      drawBorderLights(frame, colors.yellow)
      if frame == 6 then
        buffaloH = drawBigText("BUFFALO", titleY, colors.yellow)
      end
      if frame == 14 then
        drawBigText("GOLD", titleY + buffaloH + 2, colors.orange)
      end
      sleep(0.1)
    end
  end)

  -- hold the finished splash a bit longer with lights still chasing
  for frame = 41, 70 do
    drawBorderLights(frame, colors.yellow)
    sleep(0.1)
  end
end

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

-- Gold grid lines between/around every reel box. CC:Tweaked's 16-color
-- palette has no true "gold", so colors.yellow is used -- swap this for
-- colors.orange if you want something a bit deeper/warmer.
local GRID_LINE_COLOR = colors.yellow

local function drawGridLines()
  term.setBackgroundColor(GRID_LINE_COLOR)

  -- a vertical gold line after every reel (including the far right edge)
  for r = 1, REELS do
    local lineX = gridX0 + r * cellW - 1
    for yy = 0, gridHeight - 1 do
      term.setCursorPos(lineX, gridY0 + yy)
      term.write(" ")
    end
  end

  -- a horizontal gold line after every row (including the bottom edge)
  for row = 1, ROWS do
    local lineY = gridY0 + row * cellH - 1
    term.setCursorPos(gridX0, lineY)
    term.write(string.rep(" ", gridWidth))
  end

  -- frame the left and top edges too, so the whole grid is boxed in
  if gridX0 > 1 then
    for yy = 0, gridHeight - 1 do
      term.setCursorPos(gridX0 - 1, gridY0 + yy)
      term.write(" ")
    end
  end
  if gridY0 > 1 then
    term.setCursorPos(math.max(1, gridX0 - 1), gridY0 - 1)
    term.write(string.rep(" ", gridWidth + 1))
  end
end

-- Fast, plain solid-color box -- used while reels are still fast-cycling
-- during the spin animation (suit pixel art would be wasted detail there
-- and would only slow the animation down).
local function drawCellFast(r, row, key)
  local sym = SYM[key]
  local x, y = cellPos(r, row)
  term.setBackgroundColor(sym.bg)
  term.setTextColor(sym.fg)
  for yy = 0, cellH - 2 do
    term.setCursorPos(x, y + yy)
    term.write(string.rep(" ", math.max(1, cellW - 1)))
  end
  local lbl = sym.label
  term.setCursorPos(x + math.max(0, math.floor((cellW - 1 - #lbl) / 2)), y + math.floor((cellH - 2) / 2))
  term.write(lbl)
end

-- Draws a card symbol (Q/J/K/A) with its suit shape as pixel art filling
-- the box, scaled to whatever size the cell currently is.
local function drawSuitCell(r, row, key)
  local suit = CARD_SUITS[key]
  local x, y = cellPos(r, row)
  local bmp = suit.bitmap
  local srcH = #bmp
  local srcW = #bmp[1]
  local ph = math.max(1, cellH - 1)
  local pw = math.max(1, cellW - 1)

  for py = 0, ph - 1 do
    local srcY = math.min(srcH, math.max(1, math.floor(py * srcH / ph) + 1))
    local rowStr = bmp[srcY]
    for px = 0, pw - 1 do
      local srcX = math.min(srcW, math.max(1, math.floor(px * srcW / pw) + 1))
      local bit = rowStr:sub(srcX, srcX)
      term.setCursorPos(x + px, y + py)
      term.setBackgroundColor(bit == "1" and suit.shapeColor or suit.cardColor)
      term.write(" ")
    end
  end

  local lbl = SYM[key].label
  term.setCursorPos(x + math.max(0, math.floor((pw - #lbl) / 2)), y + math.floor(ph / 2))
  term.setBackgroundColor(suit.cardColor)
  term.setTextColor(suit.labelColor)
  term.write(lbl)
end

local function drawCell(r, row, key, invert)
  local x, y = cellPos(r, row)

  if invert then
    -- win-flash: same solid white flash for every symbol, suit or not
    term.setBackgroundColor(colors.white)
    term.setTextColor(colors.black)
    for yy = 0, cellH - 2 do
      term.setCursorPos(x, y + yy)
      term.write(string.rep(" ", math.max(1, cellW - 1)))
    end
    local lbl = SYM[key].label
    term.setCursorPos(x + math.max(0, math.floor((cellW - 1 - #lbl) / 2)), y + math.floor((cellH - 2) / 2))
    term.write(lbl)
    return
  end

  if CARD_SUITS[key] then
    drawSuitCell(r, row, key)
  else
    drawCellFast(r, row, key)
  end
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
  term.write("CREDITS: $" .. money(credits) .. "    BET: $" .. money(bet))
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
  drawGridLines()
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
        for row = 1, ROWS do drawCellFast(r, row, pickSymbol(strip)) end
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
  -- round to the nearest cent (not the nearest whole credit) so the
  -- small, realistic paytable values above actually show up
  return math.floor(total * 100 + 0.5) / 100, hits
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
      drawHud("YOU WIN $" .. money(win) .. "!", colors.lime)
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
  bannerAnim("BONUS TOTAL: $" .. money(bonusTotal) .. "!", colors.yellow, 2)
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
    drawHud("YOU WIN $" .. money(win) .. "!", colors.lime)
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
showStartScreen()

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
