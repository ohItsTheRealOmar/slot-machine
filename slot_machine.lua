--[[
  BUFFALO BONUS - a CC:Tweaked slot machine
  MULTI-MONITOR EDITION: one Computer runs a fully independent, separate
  game on EVERY monitor wall/cluster it finds -- own credits, own grid,
  own spin state, own touch buttons -- all off a single Computer.

  FEATURES (per station)
   - 5 reels x 4 rows, real fixed-payline scoring (1-9 selectable lines,
     each a specific zigzag row-pattern -- not a "ways" system)
   - WILD symbol substitutes for everything but the scatter, and cycles
     through a rainbow of colors while idle
   - A little pixel-art buffalo herd runs across the blank space around
     the reels (works over an optional bg.nfp background image too)
   - 3+ scatters trigger the BUFFALO BONUS free-spin round
   - Free spins have stacked wilds and a rising multiplier
   - Retriggers add more free spins mid-bonus
   - BIG WIN! banner for any win over $25
   - Touch-screen buttons, including VOL-/VOL+ for the background music
   - A looping background riff through a Speaker (if one's nearby)

  MULTI-MONITOR NOTES
   - A group of touching Advanced Monitors, all on the same network and
     the same orientation/scale, automatically merges into ONE peripheral
     in CC:Tweaked -- that's what "a station" means here. Build as many
     separate walls/clusters as you want stations (a single monitor block
     on its own also counts as its own tiny station).
   - Every station this computer can see is auto-detected and started --
     nothing to configure per station.
   - REAL MONEY: on a Command Computer every station plays for the
     server's EconomyCraft money through casino_slot.lua. Whoever stands
     closest to a station is the player; bets come out of their balance
     and wins go back in. On a normal computer it's practice credits.
   - If you have fewer Speakers than stations, they're shared round-robin
     across stations (station 1 gets speaker 1, station 2 gets speaker 2,
     and once speakers run out it wraps back to speaker 1, etc). Zero
     speakers found just means silent stations.
   - Touch-screen only in this version -- with multiple simultaneous
     games on one computer there's no unambiguous way to route a single
     shared keyboard to "the right" station, so keyboard shortcuts have
     been dropped. Every station is still fully playable by touch.

  SETUP
   1. Build one or more monitor walls (each becomes its own station).
   2. Wire/attach all of them to ONE Command Computer (a normal
      Advanced Computer works too, but only for practice credits).
   3. Optionally place one or more Speakers anywhere in range.
   4. Optionally drop a bg.nfp image next to this script -- every station
      uses the same one, each scaled to its own monitor's size.
   5. Put casino_slot.lua, casino_bank.lua and casino_net.lua next to it
      (plus a wireless/ender modem so the main computer sees it).
   6. On the computer: wget the raw URL of this file, then run it.
   7. Enter the PIN on the computer, type 'calibrate', stand where a
      player stands at each station and tap its screen.
--]]

local slot = require("casino_slot")

local c = colors
math.randomseed(os.epoch("utc"))

-- ============================= SHARED DATA =============================
-- Everything in this section is identical across every station -- pure
-- data and screen-agnostic logic, so it's kept as ordinary top-level
-- locals instead of being duplicated inside each station's closure.

-- pay = payout multiplier of (bet-per-line/10), by number of consecutive
-- reels (starting at reel 1) that match along a SINGLE payline (see
-- LINE_PATTERNS below) -- a real fixed-payline system, not "ways". These
-- numbers were tuned via multi-million-spin simulation so the whole
-- machine lands at ~95% RTP (a ~5 cent hold per dollar wagered).
local SYM = {
  WILD = { label = "WILD", fg = c.black,     bg = c.yellow,    wild = true },
  SCAT = { label = "COIN", fg = c.white,     bg = c.orange,    scatter = true },
  BUF  = { label = "BUFF", fg = c.white,     bg = c.brown,     pay = {[3]=78.66,  [4]=393.32, [5]=2359.89} },
  EAG  = { label = "EAGL", fg = c.black,     bg = c.lightGray, pay = {[3]=62.93,  [4]=235.99, [5]=1179.94} },
  WLF  = { label = "WOLF", fg = c.white,     bg = c.gray,      pay = {[3]=47.20,  [4]=157.33, [5]=786.62} },
  ELK  = { label = "ELK ", fg = c.black,     bg = c.lime,      pay = {[3]=31.47,  [4]=125.86, [5]=629.30} },
  A    = { label = " A  ", fg = c.red,       bg = c.white,     pay = {[3]=15.73,  [4]=62.93,  [5]=314.65} },
  K    = { label = " K  ", fg = c.black,     bg = c.white,     pay = {[3]=15.73,  [4]=47.20,  [5]=235.99} },
  Q    = { label = " Q  ", fg = c.red,       bg = c.white,     pay = {[3]=15.73,  [4]=47.20,  [5]=235.99} },
  J    = { label = " J  ", fg = c.black,     bg = c.white,     pay = {[3]=15.73,  [4]=31.47,  [5]=157.33} },
}

-- 9 fixed lines, one row (1-4, top-to-bottom) per reel -- a real payline
-- system, not "ways". Only the first `linesPlayed` of these are active.
local LINE_PATTERNS = {
  {2,2,2,2,2}, {3,3,3,3,3}, {1,1,1,1,1}, {4,4,4,4,4},
  {1,2,3,2,1}, {4,3,2,3,4}, {2,1,2,1,2}, {3,4,3,4,3}, {1,4,1,4,1},
}
local LINE_COLORS = {
  colors.red, colors.blue, colors.lime, colors.magenta, colors.orange,
  colors.cyan, colors.pink, colors.purple, colors.white,
}

-- Q=heart, J=spade, K=club, A=diamond -- blocky pixel-art behind each
-- card symbol's letter, scaled to whatever size the cell box is.
local HEART = {
  "0110110", "1111111", "1111111", "1111111", "0111110", "0011100", "0001000",
}
local DIAMOND = {
  "0001000", "0011100", "0111110", "1111111", "0111110", "0011100", "0001000",
}
local SPADE = {
  "0001000", "0011100", "0111110", "1111111", "1111111", "0111110", "0011100", "0001000",
}
local CLUB = {
  "0011100", "0111110", "1111111", "0111110", "1111111", "1111111", "0111110", "0001000",
}
local CARD_SUITS = {
  Q = { bitmap = HEART,   shapeColor = c.red,   cardColor = c.white, labelColor = c.red },
  J = { bitmap = SPADE,   shapeColor = c.black, cardColor = c.white, labelColor = c.black },
  K = { bitmap = CLUB,    shapeColor = c.black, cardColor = c.white, labelColor = c.black },
  A = { bitmap = DIAMOND, shapeColor = c.red,   cardColor = c.white, labelColor = c.red },
}

-- A simple 5x7 pixel font, just the letters needed for the splash title.
local FONT_5x7 = {
  A = {"01110","10001","10001","11111","10001","10001","10001"},
  B = {"11110","10001","10001","11110","10001","10001","11110"},
  D = {"11110","10001","10001","10001","10001","10001","11110"},
  F = {"11111","10000","10000","11110","10000","10000","10000"},
  G = {"01111","10000","10000","10011","10001","10001","01111"},
  I = {"11111","00100","00100","00100","00100","00100","11111"},
  L = {"10000","10000","10000","10000","10000","10000","11111"},
  N = {"10001","11001","10101","10101","10011","10001","10001"},
  O = {"01110","10001","10001","10001","10001","10001","01110"},
  U = {"10001","10001","10001","10001","10001","10001","01110"},
  W = {"10001","10001","10001","10101","10101","10101","01010"},
  ["!"] = {"00100","00100","00100","00100","00100","00000","00100"},
}

-- WILD symbols cycle through this rainbow sequence instead of flat yellow.
local RAINBOW_COLORS = {
  colors.red, colors.orange, colors.yellow, colors.lime,
  colors.cyan, colors.lightBlue, colors.purple, colors.magenta, colors.pink,
}

-- A little 16-bit-style running buffalo -- two frames, legs alternating.
local BUFFALO_FRAME_A = {
  "...11111...", "..1111111..", "11111111111", "..1.1..1.1.",
}
local BUFFALO_FRAME_B = {
  "...11111...", "..1111111..", "11111111111", ".1.1..1.1..",
}
local BUFFALO_FRAMES = { BUFFALO_FRAME_A, BUFFALO_FRAME_B }
local BUFFALO_COLOR = colors.brown

-- Background music -- a looping "doop da doop da da doop" riff played as
-- note-block-style tones (speaker.playNote), separate from the one-shot
-- sfx() sounds used for spin ticks/wins.
local MUSIC_INSTRUMENT = "pling" -- try "bit" for a more 8-bit/chiptune tone
local MUSIC_MIN_VOL, MUSIC_MAX_VOL, MUSIC_VOL_STEP = 0, 3, 0.1
local MUSIC_RIFF = {
  { pitch = 6,  len = 0.28, rest = 0.05 }, -- DOOP
  { pitch = 13, len = 0.14, rest = 0.05 }, -- da
  { pitch = 6,  len = 0.28, rest = 0.05 }, -- DOOP
  { pitch = 13, len = 0.14, rest = 0.05 }, -- da
  { pitch = 15, len = 0.14, rest = 0.05 }, -- da
  { pitch = 18, len = 0.34, rest = 0.60 }, -- DOOP (resolves, then a rest)
}

local baseWeights  = { WILD=2, SCAT=2, BUF=4, EAG=5, WLF=6, ELK=7, A=9, K=9, Q=9, J=9 }
local bonusWeights = { WILD=6, SCAT=1, BUF=5, EAG=5, WLF=6, ELK=6, A=8, K=8, Q=8, J=8 }
local scatterSpins = { [3]=8, [4]=15, [5]=20 }

local REELS, ROWS = 5, 4
local BIG_WIN_THRESHOLD = 25
local BG_IMAGE_PATH = "bg.nfp"

local function money(v)
  return string.format("%.2f", v)
end

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

-- Scales a loaded .nfp image (any original size) to exactly targetW x
-- targetH, so it always fits whatever monitor it's shown on.
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

-- ============================= MACHINE FACTORY =============================
-- Builds one fully independent game bound to a specific monitor (and an
-- optional speaker). Every draw/state function that used to be a
-- top-level global in the single-monitor version now lives inside this
-- closure instead, using `mon` (that station's own monitor peripheral)
-- directly rather than a globally-redirected `term` -- so N stations can
-- run at once without touching each other's screen or state at all.
local function newMachine(mon, speaker, stationId)
  mon.setTextScale(0.5)
  local w, h = mon.getSize()
  local monName = peripheral.getName(mon)
  local seat = slot.seat(monName)

  local function sfx(name, vol, pitch)
    if speaker then pcall(speaker.playSound, name, vol or 1, pitch or 1) end
  end

  -- ---- background music ----
  -- Starts muted: with several stations booting at once off one computer,
  -- defaulting to audible would mean every speaker blasting the riff
  -- simultaneously the moment the game starts. Turn a station up with its
  -- own VOL+ button once it's running.
  local musicVolume = 0
  local function changeVolume(delta)
    musicVolume = math.max(MUSIC_MIN_VOL, math.min(MUSIC_MAX_VOL, musicVolume + delta))
  end
  local function musicLoop()
    if not speaker then return end -- no speaker for this station -- nothing to loop
    while true do
      for _, note in ipairs(MUSIC_RIFF) do
        if musicVolume > 0 then
          pcall(speaker.playNote, MUSIC_INSTRUMENT, musicVolume, note.pitch)
        end
        sleep(note.len)
        if note.rest and note.rest > 0 then sleep(note.rest) end
      end
    end
  end

  -- ---- background image (this station's own copy, scaled to its size) ----
  local bgImage = nil
  if fs.exists(BG_IMAGE_PATH) then
    local ok, img = pcall(paintutils.loadImage, BG_IMAGE_PATH)
    if ok and img then
      bgImage = scaleImage(img, w, h)
    end
  end

  -- paintutils.drawImage always draws to the global `term` internally --
  -- it has no way to target a specific monitor -- which is exactly wrong
  -- here (it would draw onto the computer's own tiny screen instead of
  -- this station's monitor). So the image is drawn by hand, one pixel per
  -- mon.write call, same technique clearHerdBand() below already uses.
  local function drawBackground()
    mon.setBackgroundColor(colors.black)
    mon.clear()
    if bgImage then
      for y = 1, h do
        local imgRow = bgImage[y]
        if imgRow then
          for x = 1, w do
            local col = imgRow[x]
            if col then
              mon.setCursorPos(x, y)
              mon.setBackgroundColor(col)
              mon.write(" ")
            end
          end
        end
      end
      mon.setBackgroundColor(colors.black)
    end
  end

  -- ---- big block font ----
  local function drawBigText(text, topY, color, maxWidthChars)
    maxWidthChars = maxWidthChars or w
    local letterGap = 1
    local spaceWidth = 3

    local totalPixelCols = 0
    for i = 1, #text do
      local ch = text:sub(i, i)
      totalPixelCols = totalPixelCols + (ch == " " and spaceWidth or (5 + letterGap))
    end
    if totalPixelCols <= 0 then return 0 end

    local pixelW = math.max(1, math.floor(maxWidthChars / totalPixelCols))
    local pixelH = math.max(1, pixelW)
    local totalWidthChars = totalPixelCols * pixelW
    local curX = math.max(1, math.floor((w - totalWidthChars) / 2) + 1)

    mon.setBackgroundColor(color)
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
                    mon.setCursorPos(curX + (gx - 1) * pixelW + px, topY + (gy - 1) * pixelH + py)
                    mon.write(" ")
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

  -- ---- start screen ----
  local function drawBorderLights(offset, onColor)
    local perimeter = {}
    for x = 1, w do perimeter[#perimeter+1] = {x, 1} end
    for y = 2, h - 1 do perimeter[#perimeter+1] = {w, y} end
    for x = w, 1, -1 do perimeter[#perimeter+1] = {x, h} end
    for y = h - 1, 2, -1 do perimeter[#perimeter+1] = {1, y} end

    for i, pos in ipairs(perimeter) do
      local lit = (i + offset) % 3 == 0
      mon.setCursorPos(pos[1], pos[2])
      mon.setBackgroundColor(lit and onColor or colors.black)
      mon.write(" ")
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

  local function centerText(y, text, fg)
    mon.setTextColor(fg or colors.white)
    mon.setBackgroundColor(colors.black)
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    mon.setCursorPos(x, y)
    mon.write(text)
  end

  local function showStartScreen()
    drawBackground()
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
    for frame = 41, 70 do
      drawBorderLights(frame, colors.yellow)
      sleep(0.1)
    end
  end

  -- ---- layout (computed from THIS station's own monitor size) ----
  local marginX, topY = 2, 3
  local hudH = 3
  local reelAreaW = w - marginX * 2
  local reelAreaH = h - topY - hudH - 1

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
  local function cellCenter(r, row)
    local x, y = cellPos(r, row)
    return x + math.floor((cellW - 1) / 2), y + math.floor((cellH - 2) / 2)
  end

  local GRID_LINE_COLOR = colors.yellow
  local function drawGridLines()
    mon.setBackgroundColor(GRID_LINE_COLOR)
    for r = 1, REELS do
      local lineX = gridX0 + r * cellW - 1
      for yy = 0, gridHeight - 1 do
        mon.setCursorPos(lineX, gridY0 + yy)
        mon.write(" ")
      end
    end
    for row = 1, ROWS do
      local lineY = gridY0 + row * cellH - 1
      mon.setCursorPos(gridX0, lineY)
      mon.write(string.rep(" ", gridWidth))
    end
    if gridX0 > 1 then
      for yy = 0, gridHeight - 1 do
        mon.setCursorPos(gridX0 - 1, gridY0 + yy)
        mon.write(" ")
      end
    end
    if gridY0 > 1 then
      mon.setCursorPos(math.max(1, gridX0 - 1), gridY0 - 1)
      mon.write(string.rep(" ", gridWidth + 1))
    end
  end

  local linesPlayed = 9
  local minLines, maxLines = 1, 9

  local function drawLineIndicators()
    local leftX = math.max(1, gridX0 - 3)
    local rightX = math.min(w, gridX0 + gridWidth + 1)
    for li = 1, linesPlayed do
      local pattern = LINE_PATTERNS[li]
      local color = LINE_COLORS[((li - 1) % #LINE_COLORS) + 1]
      mon.setBackgroundColor(color)
      local _, leftY = cellCenter(1, pattern[1])
      mon.setCursorPos(leftX, leftY)
      mon.write("--")
      local _, rightY = cellCenter(REELS, pattern[REELS])
      mon.setCursorPos(rightX, rightY)
      mon.write("--")
    end
  end

  -- ---- rainbow wilds ----
  local rainbowTick = 0
  local function wildBg(r)
    return RAINBOW_COLORS[((r + rainbowTick) % #RAINBOW_COLORS) + 1]
  end

  local function drawCellFast(r, row, key)
    local sym = SYM[key]
    local x, y = cellPos(r, row)
    mon.setBackgroundColor(sym.wild and wildBg(r) or sym.bg)
    mon.setTextColor(sym.fg)
    for yy = 0, cellH - 2 do
      mon.setCursorPos(x, y + yy)
      mon.write(string.rep(" ", math.max(1, cellW - 1)))
    end
    local lbl = sym.label
    mon.setCursorPos(x + math.max(0, math.floor((cellW - 1 - #lbl) / 2)), y + math.floor((cellH - 2) / 2))
    mon.write(lbl)
  end

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
        mon.setCursorPos(x + px, y + py)
        mon.setBackgroundColor(bit == "1" and suit.shapeColor or suit.cardColor)
        mon.write(" ")
      end
    end

    local lbl = SYM[key].label
    mon.setCursorPos(x + math.max(0, math.floor((pw - #lbl) / 2)), y + math.floor(ph / 2))
    mon.setBackgroundColor(suit.cardColor)
    mon.setTextColor(suit.labelColor)
    mon.write(lbl)
  end

  local function drawCell(r, row, key, invert)
    local x, y = cellPos(r, row)
    if invert then
      mon.setBackgroundColor(colors.white)
      mon.setTextColor(colors.black)
      for yy = 0, cellH - 2 do
        mon.setCursorPos(x, y + yy)
        mon.write(string.rep(" ", math.max(1, cellW - 1)))
      end
      local lbl = SYM[key].label
      mon.setCursorPos(x + math.max(0, math.floor((cellW - 1 - #lbl) / 2)), y + math.floor((cellH - 2) / 2))
      mon.write(lbl)
      return
    end
    if CARD_SUITS[key] then
      drawSuitCell(r, row, key)
    else
      drawCellFast(r, row, key)
    end
  end

  -- ---- state ----
  local buttons = {}
  local function addButton(label, x1, y1, x2, action)
    table.insert(buttons, { label = label, x1 = x1, y1 = y1, x2 = x2, y2 = y1, action = action })
  end

  local bet = 10
  local betStep = 5
  local minBet, maxBet = 5, 200
  local currentGrid = nil

  local function totalBet()
    return bet * linesPlayed
  end

  local function drawHud(message, msgColor)
    mon.setBackgroundColor(colors.black)
    for yy = h - hudH, h do
      mon.setCursorPos(1, yy)
      mon.write(string.rep(" ", w))
    end
    mon.setTextColor(colors.white)
    mon.setCursorPos(2, h - hudH)
    mon.write(seat:hud())

    mon.setCursorPos(2, h - hudH + 1)
    mon.write("BET/LINE: $" .. money(bet) .. "  LINES: " .. linesPlayed .. "  TOTAL BET: $" .. money(totalBet())
      .. "  VOL: " .. (musicVolume <= 0 and "MUTE" or string.format("%.1f", musicVolume)))

    if message then
      mon.setTextColor(msgColor or colors.yellow)
      mon.setCursorPos(2, h - 1)
      mon.write(message)
    end
  end

  local function drawButtons()
    buttons = {}
    local by = h
    local specs = {
      { "-BET", 2 },
      { "+BET", 9 },
      { "-LN", 16 },
      { "+LN", 22 },
      { "MAXBET", 28 },
      { "VOL-", 37 },
      { "VOL+", 44 },
      { "SPIN!", w - 8 },
    }
    for _, s in ipairs(specs) do
      local label, x = s[1], s[2]
      mon.setBackgroundColor(colors.lightBlue)
      mon.setTextColor(colors.black)
      mon.setCursorPos(x, by)
      mon.write(" " .. label .. " ")
      addButton(label, x, by, x + #label + 1, label)
    end
    mon.setBackgroundColor(colors.black)
  end

  local function drawFrame(message, msgColor)
    drawBackground()
    centerText(1, "== B U F F A L O   B O N U S ==", colors.orange)
    drawHud(message, msgColor)
    drawButtons()
    drawGridLines()
    drawLineIndicators()
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

  local function redrawWildCells(grid)
    if not grid then return end
    for r = 1, REELS do
      for row = 1, ROWS do
        if grid[r][row] == "WILD" then
          drawCellFast(r, row, "WILD")
        end
      end
    end
  end

  -- ---- buffalo herd ----
  local herdBandY0 = gridY0 + gridHeight
  local herdBandH = (topY + reelAreaH) - herdBandY0
  local HERD_ENABLED = herdBandH >= 4
  local HERD_COUNT = 3
  local herdTick = 0

  local function clearHerdBand()
    if bgImage then
      for yy = 0, herdBandH - 1 do
        local y = herdBandY0 + yy
        local imgRow = bgImage[y]
        for x = 1, w do
          local col = imgRow and imgRow[x]
          mon.setCursorPos(x, y)
          mon.setBackgroundColor(col or colors.black)
          mon.write(" ")
        end
      end
    else
      mon.setBackgroundColor(colors.black)
      for yy = 0, herdBandH - 1 do
        mon.setCursorPos(1, herdBandY0 + yy)
        mon.write(string.rep(" ", w))
      end
    end
  end

  local function drawBuffaloAt(x0, frame)
    local spriteH = #frame
    local spriteW = #frame[1]
    local y0 = herdBandY0 + math.floor(math.max(0, herdBandH - spriteH) / 2)
    mon.setBackgroundColor(BUFFALO_COLOR)
    for py = 1, spriteH do
      local rowStr = frame[py]
      for px = 1, spriteW do
        if rowStr:sub(px, px) == "1" then
          local sx = x0 + px - 1
          if sx >= 1 and sx <= w then
            mon.setCursorPos(sx, y0 + py - 1)
            mon.write(" ")
          end
        end
      end
    end
  end

  local function drawHerd()
    if not HERD_ENABLED then return end
    clearHerdBand()
    local frame = BUFFALO_FRAMES[(math.floor(herdTick / 3) % #BUFFALO_FRAMES) + 1]
    local spriteW = #frame[1]
    local spacing = spriteW + 16
    for i = 0, HERD_COUNT - 1 do
      local x = ((herdTick + i * spacing) % (w + spriteW)) - spriteW
      drawBuffaloAt(x, frame)
    end
  end

  local function idleTick()
    rainbowTick = rainbowTick + 1
    redrawWildCells(currentGrid)
    herdTick = herdTick + 1
    drawHerd()
  end

  -- ---- win lines ----
  local WIN_LINE_COLOR = colors.cyan
  local function drawLineSeg(x1, y1, x2, y2, color)
    mon.setBackgroundColor(color)
    local dx, dy = math.abs(x2 - x1), -math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx + dy
    local x, y = x1, y1
    while true do
      mon.setCursorPos(x, y)
      mon.write(" ")
      if x == x2 and y == y2 then break end
      local e2 = 2 * err
      if e2 >= dy then err = err + dy; x = x + sx end
      if e2 <= dx then err = err + dx; y = y + sy end
    end
  end

  local function drawWinLines(winLines)
    for _, wl in ipairs(winLines) do
      for i = 1, #wl.path - 1 do
        local p1, p2 = wl.path[i], wl.path[i + 1]
        local x1, y1 = cellCenter(p1.r, p1.row)
        local x2, y2 = cellCenter(p2.r, p2.row)
        drawLineSeg(x1, y1, x2, y2, WIN_LINE_COLOR)
      end
    end
  end

  -- ---- animation ----
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
      mon.setBackgroundColor(colors.black)
      for yy = gridY0, gridY0 + ROWS * cellH do
        mon.setCursorPos(1, yy); mon.write(string.rep(" ", w))
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

  local function showBigWinBanner()
    local titleY = math.floor(h / 2) - 4
    for frame = 1, 20 do
      drawBackground()
      drawBorderLights(frame, colors.yellow)
      if frame >= 3 then
        drawBigText("BIG WIN!", titleY, colors.orange)
      end
      sfx("minecraft:entity.player.levelup", 1, 1 + frame * 0.05)
      sleep(0.1)
    end
  end

  -- ---- scoring ----
  local function evaluateLines(grid)
    local total, hits, winLines = 0, {}, {}
    for li = 1, linesPlayed do
      local pattern = LINE_PATTERNS[li]
      local path = {}
      local key = nil
      local consecutive = 0
      for r = 1, REELS do
        local row = pattern[r]
        path[#path + 1] = { r = r, row = row }
        local s = grid[r][row]
        if not key and s ~= "WILD" then key = s end
        if s == key or s == "WILD" then
          consecutive = consecutive + 1
        else
          break
        end
      end
      if key and consecutive >= 3 then
        local sym = SYM[key]
        if sym and sym.pay and sym.pay[consecutive] then
          local amount = sym.pay[consecutive] * (bet / 10)
          total = total + amount
          for i = 1, consecutive do
            local p = path[i]
            hits[p.r] = hits[p.r] or {}
            hits[p.r][p.row] = true
          end
          winLines[#winLines + 1] = { line = li, symbol = key, path = { table.unpack(path, 1, consecutive) } }
        end
      end
    end
    return math.floor(total * 100 + 0.5) / 100, hits, winLines
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

  -- ---- bonus round ----
  local function runBonus(triggerScatters)
    local freeSpins = scatterSpins[math.min(triggerScatters, 5)] or 8
    local multiplier = 1
    local bonusTotal = 0

    bannerAnim("BUFFALO BONUS TRIGGERED!", colors.orange, 1.5)

    while freeSpins > 0 do
      freeSpins = freeSpins - 1
      drawFrame()
      centerText(2, "FREE SPINS LEFT: " .. (freeSpins + 1) .. "   MULT x" .. multiplier, colors.lime)

      local grid = genGrid(bonusWeights, 20)
      currentGrid = grid
      animateSpin(grid, bonusWeights)

      local win, hits, winLines = evaluateLines(grid)
      win = win * multiplier
      if win > 0 then
        bonusTotal = bonusTotal + win
        flashWin(grid, hits)
        drawWinLines(winLines)
        if win > BIG_WIN_THRESHOLD then
          showBigWinBanner()
          drawFrame()
          drawGrid(grid, hits)
          drawWinLines(winLines)
        end
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

    seat:win(bonusTotal)
    bannerAnim("BONUS TOTAL: $" .. money(bonusTotal) .. "!", colors.yellow, 2)
  end

  -- ---- main spin ----
  local spinning = false
  local function doSpin()
    if spinning then return end
    spinning = true
    local ok, why, kind = seat:begin(totalBet())
    if not ok then
      spinning = false
      drawHud(why, kind == "welcome" and colors.lime or colors.red)
      drawButtons()
      return
    end
    drawFrame()

    local grid = genGrid(baseWeights, nil)
    currentGrid = grid
    animateSpin(grid, baseWeights)

    local win, hits, winLines = evaluateLines(grid)
    local scatters = countScatters(grid)

    if win > 0 then
      seat:win(win)
      flashWin(grid, hits)
      drawWinLines(winLines)
      if win > BIG_WIN_THRESHOLD then
        showBigWinBanner()
        drawFrame()
        drawGrid(grid, hits)
        drawWinLines(winLines)
      end
      drawHud("YOU WIN $" .. money(win) .. "!", colors.lime)
    else
      drawHud("NO WIN - TRY AGAIN", colors.red)
    end
    sleep(1.5)

    if scatters >= 3 then
      runBonus(scatters)
    end

    local problem = seat:finish()
    drawFrame(problem, colors.red)
    spinning = false
  end

  -- ---- input ----
  local function refreshControls()
    drawFrame()
  end

  local function changeBet(delta)
    bet = math.max(minBet, math.min(maxBet, bet + delta))
    refreshControls()
  end

  local function changeLines(delta)
    linesPlayed = math.max(minLines, math.min(maxLines, linesPlayed + delta))
    refreshControls()
  end

  local function handleButton(label)
    if label == "SPIN!" then doSpin()
    elseif label == "-BET" then changeBet(-betStep)
    elseif label == "+BET" then changeBet(betStep)
    elseif label == "-LN" then changeLines(-1)
    elseif label == "+LN" then changeLines(1)
    elseif label == "MAXBET" then
      bet = maxBet
      linesPlayed = maxLines
      refreshControls()
    elseif label == "VOL-" then
      changeVolume(-MUSIC_VOL_STEP)
      refreshControls()
    elseif label == "VOL+" then
      changeVolume(MUSIC_VOL_STEP)
      refreshControls()
    end
  end

  local function pointInButton(x, y, b)
    return x >= b.x1 and x <= b.x2 and y == b.y1
  end

  local lastTouch, lastTouchTime = nil, 0
  local TOUCH_DEBOUNCE_MS = 250

  -- Only reacts to touches on THIS station's own monitor (monitor_touch's
  -- first parameter is the peripheral name of the monitor that was
  -- touched) -- this is what keeps stations from stepping on each other
  -- even though every event is broadcast to every station's coroutine.
  local function inputLoop()
    while true do
      local event, p1, p2, p3 = os.pullEvent()
      local used, usedMsg = false, nil
      if event == "monitor_touch" and p1 == monName then used, usedMsg = seat:touch() end
      if used then
        drawHud(usedMsg, colors.yellow)
        drawButtons()
      elseif event == "monitor_touch" and p1 == monName then
        local x, y = p2, p3
        for _, b in ipairs(buttons) do
          if pointInButton(x, y, b) then
            local now = os.epoch("utc")
            if b.action ~= lastTouch or (now - lastTouchTime) > TOUCH_DEBOUNCE_MS then
              lastTouch, lastTouchTime = b.action, now
              handleButton(b.action)
            end
            break
          end
        end
      end
    end
  end

  -- Idle animation heartbeat -- rainbow wilds + buffalo herd. Runs on its
  -- own coroutine (see run() below) so a repeating sleep()-based timer
  -- can't get silently swallowed by sleep() calls elsewhere in THIS
  -- station's own spin/bonus code.
  local ANIM_INTERVAL = 0.15
  local function animationLoop()
    while true do
      sleep(ANIM_INTERVAL)
      if not spinning then idleTick() end
    end
  end

  seat:onChange(function()
    if not spinning then drawHud(); drawButtons() end
  end)

  local function run()
    showStartScreen()
    currentGrid = genGrid(baseWeights, nil)
    drawFrame()
    centerText(2, "TOUCH SPIN TO PLAY", colors.lightGray)
    -- waitForAll, not waitForAny: musicLoop returns immediately (by
    -- design) when this station has no speaker, and waitForAny would
    -- treat that as "done" and kill this whole station's coroutine set
    -- the instant that happened.
    parallel.waitForAll(inputLoop, animationLoop, musicLoop)
  end

  return { run = run, monName = monName, stationId = stationId }
end

-- ============================= DISCOVER STATIONS =============================
-- Each entry peripheral.find("monitor") returns is already a whole
-- merged wall/cluster (CC:Tweaked auto-merges adjacent same-network,
-- same-scale monitor blocks into one peripheral), so one entry = one
-- station, with no manual grouping needed.
slot.setup{ game = "buffalo", kind = "Buffalo Bonus", practiceCredits = 1000 }

local monitors = { peripheral.find("monitor") }
if #monitors == 0 then
  error("No monitors found! Attach at least one monitor (wall) to this computer.")
end
local speakers = { peripheral.find("speaker") }

local machines = {}
for i, mon in ipairs(monitors) do
  local spk = #speakers > 0 and speakers[((i - 1) % #speakers) + 1] or nil
  machines[i] = newMachine(mon, spk, i)
end

print("Buffalo Bonus: found " .. #monitors .. " station(s), " .. #speakers .. " speaker(s). Starting all stations...")

local runFns = {}
for i, m in ipairs(machines) do
  runFns[i] = m.run
  print("  station " .. i .. " -> " .. m.monName)
end

slot.run(table.unpack(runFns))
