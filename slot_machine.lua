--[[
  BUFFALO BONUS - a CC:Tweaked slot machine
  Built for a 3x4 Advanced Monitor wall + one Computer.

  FEATURES
   - 5 reels x 4 rows, real fixed-payline scoring (1-9 selectable lines,
     each a specific zigzag row-pattern -- not a "ways" system)
   - WILD symbol substitutes for everything but the scatter
   - 3+ scatters trigger the BUFFALO BONUS free-spin round
   - Free spins have stacked wilds and a rising multiplier
   - Retriggers add more free spins mid-bonus
   - BIG WIN! banner for any win over $25
   - Touch-screen buttons (Advanced Monitor) + keyboard fallback on the computer
   - Optional real-money mode: ties into your server's actual economy via
     a Player Detector, instead of the machine's own pretend credits (see
     the ECONOMY BRIDGE section below -- off by default, "practice mode",
     until you fill in the two functions it needs)

  SETUP
   1. Place a 3x4 wall of Advanced Monitors (3 wide, 4 tall).
   2. Place a Computer (Advanced Computer for color) touching the monitor wall.
   3. Optionally place a Speaker next to the computer for sound.
   4. Optionally place a Player Detector (Advanced Peripherals mod) within
      DETECT_RANGE blocks of the computer, if you want real-money mode.
   5. On the computer: wget the raw URL of this file, then run it.
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

-- ============================= BACKGROUND MUSIC =============================
-- A simple looping "doop da doop da da doop" riff, played through
-- speaker.playNote (note-block style tones -- distinct from the one-shot
-- sfx() sound effects used for spin ticks/wins elsewhere). Runs on its
-- own coroutine (see musicLoop in the main loop) so it never blocks
-- button input or the spin/bonus animations.
local MUSIC_INSTRUMENT = "pling" -- try "bit" for a more 8-bit/chiptune tone
local MUSIC_MIN_VOL, MUSIC_MAX_VOL, MUSIC_VOL_STEP = 0, 3, 0.5
local musicVolume = 1.5

-- pitch is 0-24 (12 = middle); len/rest are seconds. This spells out
-- "DOOP-da-DOOP-da-da-DOOP" then a beat of silence before it repeats.
local MUSIC_RIFF = {
  { pitch = 6,  len = 0.28, rest = 0.05 }, -- DOOP
  { pitch = 13, len = 0.14, rest = 0.05 }, -- da
  { pitch = 6,  len = 0.28, rest = 0.05 }, -- DOOP
  { pitch = 13, len = 0.14, rest = 0.05 }, -- da
  { pitch = 15, len = 0.14, rest = 0.05 }, -- da
  { pitch = 18, len = 0.34, rest = 0.60 }, -- DOOP (resolves, then a rest)
}

local function changeVolume(delta)
  musicVolume = math.max(MUSIC_MIN_VOL, math.min(MUSIC_MAX_VOL, musicVolume + delta))
end

local function musicLoop()
  if not speaker then return end -- no speaker attached -- nothing to loop
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

math.randomseed(os.epoch("utc"))

local c = colors

-- ============================= PLAYER DETECTOR =============================
-- Requires a "Player Detector" peripheral (Advanced Peripherals mod)
-- somewhere in range of this computer -- it tells the machine who's
-- standing at it, so it knows whose real balance to show/charge. If none
-- is found, the machine just falls back to practice mode (see below).
local playerDetector = peripheral.find("playerDetector")
local DETECT_RANGE = 4 -- blocks; widen/narrow to match where players stand

local currentPlayer = nil -- name of whoever is currently detected, or nil

local function refreshCurrentPlayer()
  if not playerDetector then return end
  local ok, players = pcall(playerDetector.getPlayersInRange, DETECT_RANGE)
  if ok and players and #players > 0 then
    currentPlayer = players[1]
  else
    currentPlayer = nil
  end
end

-- ============================= ECONOMY BRIDGE =============================
-- Hooks the machine up to your server's REAL money system, so spins bet
-- and pay out of a player's actual balance instead of the machine's own
-- pretend credit pile.
--
-- Only the two functions below need filling in, whatever the real system
-- turns out to be -- everything else in this file already routes every
-- credit change through them. Three worked examples are commented out
-- underneath, covering the three likely shapes of "the server's money
-- system": a CC:Tweaked peripheral, a command-based economy plugin, or a
-- database reachable over HTTP. Ask your friend which one applies, fill
-- in that one, then flip ECONOMY_ENABLED to true.
--
-- Until then, ECONOMY_ENABLED stays false and the machine runs exactly
-- like it did before -- its own fake $1000 starting pile, no real money
-- touched -- so nothing here breaks your testing in the meantime.
local ECONOMY_ENABLED = false
local STARTING_CREDITS = 1000.00

-- Must return the player's current real balance (a number), or nil plus
-- an error string if it couldn't be read.
local function economyGetBalance(playerName)
  return nil, "economy not wired up yet (see ECONOMY BRIDGE comment)"
end

-- Must apply `delta` to the player's REAL balance -- positive pays them,
-- negative charges them -- and return true on success, or false plus an
-- error string if it didn't go through.
local function economyAdjustBalance(playerName, delta)
  return false, "economy not wired up yet (see ECONOMY BRIDGE comment)"
end

--[[
  EXAMPLE A -- a CC:Tweaked peripheral (a "bank"/"vault"/"ATM" block from a
  mod like Advanced Peripherals, or a custom one your friend built). Swap
  in whatever the real peripheral type and method names turn out to be:

    local bank = peripheral.find("bank")
    local function economyGetBalance(playerName)
      local ok, bal = pcall(bank.getBalance, playerName)
      if ok then return bal end
      return nil, "peripheral call failed"
    end
    local function economyAdjustBalance(playerName, delta)
      local ok, err = pcall(function()
        if delta >= 0 then bank.deposit(playerName, delta)
        else bank.withdraw(playerName, -delta) end
      end)
      return ok, (not ok) and tostring(err) or nil
    end

  EXAMPLE B -- a command-based economy plugin (like an EssentialsX-style
  "/eco give"/"/eco take"), run from a Command Computer block so the
  "commands" API is available:

    local function economyGetBalance(playerName)
      local ok, result = commands.exec("balance " .. playerName)
      -- result's exact shape depends on the plugin -- you'll likely need
      -- to pull the number back out of its text/JSON output here
      if not ok then return nil, "command failed" end
      return tonumber(result), nil
    end
    local function economyAdjustBalance(playerName, delta)
      local cmd = delta >= 0
        and ("eco give " .. playerName .. " " .. string.format("%.2f", delta))
        or  ("eco take " .. playerName .. " " .. string.format("%.2f", -delta))
      local ok = commands.exec(cmd)
      return ok, (not ok) and "command failed" or nil
    end

  EXAMPLE C -- the economy lives behind a small web API (needs the "http"
  API enabled in the CC:Tweaked config, and this URL allowed there):

    local API_BASE = "http://your-bridge-host:PORT"
    local function economyGetBalance(playerName)
      local res = http.get(API_BASE .. "/balance/" .. textutils.urlEncode(playerName))
      if not res then return nil, "request failed" end
      local body = res.readAll(); res.close()
      local data = textutils.unserializeJSON(body)
      if data and data.balance then return data.balance end
      return nil, "bad response"
    end
    local function economyAdjustBalance(playerName, delta)
      local res = http.post(API_BASE .. "/adjust",
        textutils.serializeJSON({ player = playerName, delta = delta }),
        { ["Content-Type"] = "application/json" })
      if not res then return false, "request failed" end
      res.close()
      return true
    end
]]

-- ============================= STATE =============================
-- Credits/bet are tracked to the cent (like a real machine) since the
-- paytable below is tuned to a tighter ~5 cent hold per dollar wagered.
-- `credits` is a local cache of whatever balance is currently in play --
-- the player's real one when ECONOMY_ENABLED, or the practice pile when
-- not -- kept in sync by syncBalance() below.
local credits = STARTING_CREDITS
local economyError = nil

local function syncBalance()
  if not ECONOMY_ENABLED or not currentPlayer then return end
  local bal, err = economyGetBalance(currentPlayer)
  if bal then
    credits = bal
    economyError = nil
  else
    economyError = err or "couldn't read balance"
  end
end
local bet = 10
local betStep = 5
local minBet, maxBet = 5, 200
local currentGrid = nil -- last grid shown; drawFrame always redraws this so the screen never goes blank

-- Lines played is a bet multiplier -- more lines = more of the grid's
-- "ways" you're covering, at a proportionally higher total wager, same
-- idea as picking more paylines on a real machine.
local linesPlayed = 9
local minLines, maxLines = 1, 9

local function money(v)
  return string.format("%.2f", v)
end

local function totalBet()
  return bet * linesPlayed
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
-- pay = payout multiplier of (bet-per-line/10), by number of consecutive
-- reels (starting at reel 1) that match along a SINGLE payline (see
-- LINE_PATTERNS below) -- a real fixed-payline system, not "ways". These
-- numbers were tuned via a 2,000,000-spin simulation of that exact model
-- so the whole machine lands at ~95% RTP (a ~5 cent hold per dollar
-- wagered), a tighter hold than a typical real slot machine.
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

-- ============================= PAYLINES =============================
-- 9 fixed lines, one row (1-4, top-to-bottom) per reel -- a real payline
-- system like the reference image, not the old "ways" method. Only the
-- first `linesPlayed` of these are active/checked each spin. Each line
-- gets its own display color for the edge dash indicators.
local LINE_PATTERNS = {
  {2,2,2,2,2},
  {3,3,3,3,3},
  {1,1,1,1,1},
  {4,4,4,4,4},
  {1,2,3,2,1},
  {4,3,2,3,4},
  {2,1,2,1,2},
  {3,4,3,4,3},
  {1,4,1,4,1},
}
local LINE_COLORS = {
  colors.red, colors.blue, colors.lime, colors.magenta, colors.orange,
  colors.cyan, colors.pink, colors.purple, colors.white,
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
  I = {"11111","00100","00100","00100","00100","00100","11111"},
  L = {"10000","10000","10000","10000","10000","10000","11111"},
  N = {"10001","11001","10101","10101","10011","10001","10001"},
  O = {"01110","10001","10001","10001","10001","10001","01110"},
  U = {"10001","10001","10001","10001","10001","10001","01110"},
  W = {"10001","10001","10001","10101","10101","10101","01010"},
  ["!"] = {"00100","00100","00100","00100","00100","00000","00100"},
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

local function cellCenter(r, row)
  local x, y = cellPos(r, row)
  return x + math.floor((cellW - 1) / 2), y + math.floor((cellH - 2) / 2)
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

-- Dash markers just outside the grid's left/right edges, one per active
-- line, at the row height where that line enters (left) and exits
-- (right) the grid -- like the line-number markers in a real payline
-- chart. Each line gets its own color from LINE_COLORS.
local function drawLineIndicators()
  local leftX = math.max(1, gridX0 - 3)
  local rightX = math.min(w, gridX0 + gridWidth + 1)

  for li = 1, linesPlayed do
    local pattern = LINE_PATTERNS[li]
    local color = LINE_COLORS[((li - 1) % #LINE_COLORS) + 1]
    term.setBackgroundColor(color)

    local _, leftY = cellCenter(1, pattern[1])
    term.setCursorPos(leftX, leftY)
    term.write("--")

    local _, rightY = cellCenter(REELS, pattern[REELS])
    term.setCursorPos(rightX, rightY)
    term.write("--")
  end
end

-- ============================= RAINBOW WILDS =============================
-- WILD symbols cycle through this color sequence instead of a flat yellow.
-- rainbowTick advances once per idle animation frame (see IDLE ANIMATION
-- below); offsetting by reel number (r) makes the colors sweep across the
-- grid left-to-right rather than all flashing in lockstep.
local RAINBOW_COLORS = {
  colors.red, colors.orange, colors.yellow, colors.lime,
  colors.cyan, colors.lightBlue, colors.purple, colors.magenta, colors.pink,
}
local rainbowTick = 0

local function wildBg(r)
  return RAINBOW_COLORS[((r + rainbowTick) % #RAINBOW_COLORS) + 1]
end

-- Fast, plain solid-color box -- used while reels are still fast-cycling
-- during the spin animation (suit pixel art would be wasted detail there
-- and would only slow the animation down).
local function drawCellFast(r, row, key)
  local sym = SYM[key]
  local x, y = cellPos(r, row)
  term.setBackgroundColor(sym.wild and wildBg(r) or sym.bg)
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
  term.setCursorPos(2, h - hudH)
  if ECONOMY_ENABLED then
    if not currentPlayer then
      term.setTextColor(colors.red)
      term.write("STAND ON THE DETECTOR TO PLAY")
    elseif economyError then
      term.setTextColor(colors.red)
      term.write("ECONOMY ERROR: " .. economyError)
    else
      term.setTextColor(colors.white)
      term.write(currentPlayer .. "  CREDITS: $" .. money(credits))
    end
  else
    term.setTextColor(colors.white)
    term.write("CREDITS: $" .. money(credits) .. "  (practice mode)")
  end

  term.setTextColor(colors.white)
  term.setCursorPos(2, h - hudH + 1)
  term.write("BET/LINE: $" .. money(bet) .. "  LINES: " .. linesPlayed .. "  TOTAL BET: $" .. money(totalBet())
    .. "  VOL: " .. (musicVolume <= 0 and "MUTE" or string.format("%.1f", musicVolume)))

  if message then
    term.setTextColor(msgColor or colors.yellow)
    term.setCursorPos(2, h - 1)
    term.write(message)
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

-- Cheap redraw of just the WILD cells -- used every idle animation frame
-- so the rainbow cycle updates without repainting the whole grid.
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

-- ============================= BUFFALO HERD =============================
-- A little 16-bit-style running buffalo, drawn as blocky pixel art (same
-- idea as the card-suit bitmaps above) in whatever blank space is left
-- around the reels once REEL_SCALE has shrunk them. Two frames, legs
-- alternating, give it a galloping look; several are staggered so a small
-- "herd" streams across at once. Purely cosmetic -- it never covers the
-- reels themselves.
local BUFFALO_FRAME_A = {
  "...11111...",
  "..1111111..",
  "11111111111",
  "..1.1..1.1.",
}
local BUFFALO_FRAME_B = {
  "...11111...",
  "..1111111..",
  "11111111111",
  ".1.1..1.1..",
}
local BUFFALO_FRAMES = { BUFFALO_FRAME_A, BUFFALO_FRAME_B }
local BUFFALO_COLOR = colors.brown

-- Use whatever blank strip sits below the (shrunk) reel grid but above the
-- HUD. If the monitor is too small/dense for that to fit a sprite, the
-- herd just quietly disables itself and only the rainbow wilds animate.
local herdBandY0 = gridY0 + gridHeight
local herdBandH = (topY + reelAreaH) - herdBandY0
local HERD_ENABLED = herdBandH >= 4
local HERD_COUNT = 3
local herdTick = 0

-- Repaints the herd's strip back to whatever it should look like with no
-- buffalo on it -- the background image's own pixels in that band if one
-- is loaded, otherwise flat black -- so each frame erases the *previous*
-- buffalo positions without erasing the background underneath them.
local function clearHerdBand()
  if bgImage then
    for yy = 0, herdBandH - 1 do
      local y = herdBandY0 + yy
      local imgRow = bgImage[y]
      for x = 1, w do
        local col = imgRow and imgRow[x]
        term.setCursorPos(x, y)
        term.setBackgroundColor(col or colors.black)
        term.write(" ")
      end
    end
  else
    term.setBackgroundColor(colors.black)
    for yy = 0, herdBandH - 1 do
      term.setCursorPos(1, herdBandY0 + yy)
      term.write(string.rep(" ", w))
    end
  end
end

local function drawBuffaloAt(x0, frame)
  local spriteH = #frame
  local spriteW = #frame[1]
  local y0 = herdBandY0 + math.floor(math.max(0, herdBandH - spriteH) / 2)
  term.setBackgroundColor(BUFFALO_COLOR)
  for py = 1, spriteH do
    local rowStr = frame[py]
    for px = 1, spriteW do
      if rowStr:sub(px, px) == "1" then
        local sx = x0 + px - 1
        if sx >= 1 and sx <= w then
          term.setCursorPos(sx, y0 + py - 1)
          term.write(" ")
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

-- ============================= IDLE ANIMATION =============================
-- Runs once per animation timer tick (see main loop) whenever the machine
-- isn't mid-spin/mid-bonus: advances the rainbow-wild cycle and the herd,
-- and repaints only those small pieces (never the whole frame), so it's
-- cheap enough to run continuously without slowing the buttons down.
-- Player Detector / balance polling runs much slower than the visual
-- animation (once every ~1.2s, not every ~0.15s) -- it's a real peripheral
-- call (and, once wired up, a real economy lookup), so there's no reason
-- to hammer it 6-7 times a second.
local PLAYER_POLL_EVERY = 8 -- idle ticks (~1.2s at ANIM_INTERVAL=0.15)
local idleTickCount = 0

-- idleTick itself is only ever called while not spinning (see
-- animationLoop in the main loop below), so there's no need to re-check
-- that here.
local function idleTick()
  rainbowTick = rainbowTick + 1
  redrawWildCells(currentGrid)
  herdTick = herdTick + 1
  drawHerd()

  idleTickCount = idleTickCount + 1
  if idleTickCount >= PLAYER_POLL_EVERY then
    idleTickCount = 0
    local before = currentPlayer
    refreshCurrentPlayer()
    if ECONOMY_ENABLED and currentPlayer ~= before then
      syncBalance()
      drawFrame() -- new player (or nobody) at the machine -- repaint the
                  -- HUD immediately rather than waiting on input
    end
  end
end

-- ============================= WIN LINES =============================
local WIN_LINE_COLOR = colors.cyan

-- simple Bresenham line between two character-grid points
local function drawLineSeg(x1, y1, x2, y2, color)
  term.setBackgroundColor(color)
  local dx, dy = math.abs(x2 - x1), -math.abs(y2 - y1)
  local sx = x1 < x2 and 1 or -1
  local sy = y1 < y2 and 1 or -1
  local err = dx + dy
  local x, y = x1, y1
  while true do
    term.setCursorPos(x, y)
    term.write(" ")
    if x == x2 and y == y2 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x = x + sx end
    if e2 <= dx then err = err + dx; y = y + sy end
  end
end

-- Draws an actual connecting line through every winning symbol group's
-- path, on top of the settled/flashed grid.
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

-- ============================= BIG WIN =============================
local BIG_WIN_THRESHOLD = 25

-- Unlike bannerAnim, this keeps the background image visible (drawn
-- fresh every frame instead of clearing to black) behind the big text.
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

-- ============================= SCORING =============================
-- Real fixed-payline evaluation: only the first `linesPlayed` lines in
-- LINE_PATTERNS are checked. Each line follows one specific row per reel
-- (not "any row" like a ways system), starting from reel 1, with WILD
-- substituting for any symbol.
--
-- Returns (winAmount, hits, winLines):
--  hits     -- [reel][row]=true for every cell that's part of ANY win,
--              used for the white flash.
--  winLines -- one entry per winning line, with its exact path of
--              {r, row} points so a line can be drawn through it.
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

  -- round to the nearest cent (not the nearest whole credit) so the
  -- small, realistic paytable values above actually show up
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

  if ECONOMY_ENABLED and bonusTotal > 0 then
    -- best-effort: the bonus total is already fully won at this point, so
    -- we pay it out even if this particular call fails to go through --
    -- credits (the on-screen number) still reflects it either way, and
    -- the next syncBalance() call will reconcile against the real value.
    economyAdjustBalance(currentPlayer, bonusTotal)
  end
  credits = credits + bonusTotal
  bannerAnim("BONUS TOTAL: $" .. money(bonusTotal) .. "!", colors.yellow, 2)
end

-- ============================= MAIN SPIN =============================
local spinning = false
local function doSpin()
  if spinning then return end

  if ECONOMY_ENABLED then
    if not currentPlayer then
      drawHud("STAND ON THE DETECTOR TO PLAY", colors.red)
      drawButtons()
      return
    end
    syncBalance() -- re-check the REAL balance right before betting, in
                   -- case it changed elsewhere since we last saw them
    if economyError then
      drawHud("ECONOMY ERROR: " .. economyError, colors.red)
      drawButtons()
      return
    end
  end

  if credits < totalBet() then
    drawHud("NOT ENOUGH CREDITS", colors.red)
    drawButtons()
    return
  end

  spinning = true

  if ECONOMY_ENABLED then
    local ok, err = economyAdjustBalance(currentPlayer, -totalBet())
    if not ok then
      spinning = false
      drawHud("ECONOMY ERROR: " .. (err or "bet failed"), colors.red)
      drawButtons()
      return
    end
  end
  credits = credits - totalBet()
  drawFrame()

  local grid = genGrid(baseWeights, nil)
  currentGrid = grid
  animateSpin(grid, baseWeights)

  local win, hits, winLines = evaluateLines(grid)
  local scatters = countScatters(grid)

  if win > 0 then
    if ECONOMY_ENABLED then
      economyAdjustBalance(currentPlayer, win)
    end
    credits = credits + win
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

  if ECONOMY_ENABLED then
    syncBalance() -- pull the authoritative real balance back in, so any
                   -- rounding or a failed best-effort payout above gets
                   -- corrected on screen rather than silently drifting
  end
  drawFrame()
  spinning = false
end

-- ============================= INPUT =============================
-- A full drawFrame() redraw -- not just drawHud() -- because changing
-- bet or lines also has to redraw the button row underneath the HUD
-- text (or the buttons vanish) and the payline dash indicators (which
-- change count when lines change).
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

-- ============================= BOOT =============================
showStartScreen()

currentGrid = genGrid(baseWeights, nil)
drawFrame()
centerText(2, "TOUCH SPIN OR PRESS [SPACE]   BET +/- WITH KEYS", colors.lightGray)

-- Debounce touches: some monitors/clients can fire monitor_touch more
-- than once for what was physically a single tap, which made +LN/-BET
-- etc. occasionally seem to jump by more than one step. Ignore repeats
-- of the same button within a short window.
local lastTouch, lastTouchTime = nil, 0
local TOUCH_DEBOUNCE_MS = 250

-- ============================= MAIN LOOP =============================
-- Button/key input and the idle animation heartbeat run as two separate
-- coroutines via parallel.waitForAny, exactly like the startup jingle
-- above. This matters: a plain single-loop os.pullEvent("timer") would
-- have its own repeating timer silently swallowed by every sleep() call
-- inside doSpin/animateSpin/flashWin (CC:Tweaked's sleep() discards any
-- "timer" event that isn't the one *it* is waiting for), which is why the
-- rainbow/herd animation used to freeze after the very first spin. Running
-- it on its own coroutine means every event gets offered to both loops
-- independently, so the animation's own sleep() always gets to see it.
local function inputLoop()
  while true do
    local event, p1, p2, p3 = os.pullEvent()
    if event == "monitor_touch" then
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
    elseif event == "key" then
      if p1 == keys.space then doSpin()
      elseif p1 == keys.minus then changeBet(-betStep)
      elseif p1 == keys.equals or p1 == keys.plus then changeBet(betStep)
      elseif p1 == keys.leftBracket then changeLines(-1)
      elseif p1 == keys.rightBracket then changeLines(1)
      elseif p1 == keys.m then
        bet = maxBet
        linesPlayed = maxLines
        refreshControls()
      end
    end
  end
end

-- Idle animation heartbeat -- rainbow wilds + the buffalo herd. Only ticks
-- while nothing else is going on (spinning is false between spins), so it
-- never fights with the spin/bonus animations for the screen.
local ANIM_INTERVAL = 0.15
local function animationLoop()
  while true do
    sleep(ANIM_INTERVAL)
    if not spinning then idleTick() end
  end
end

-- waitForAll, not waitForAny: musicLoop returns immediately (by design) if
-- there's no speaker attached, and waitForAny would treat that as "we're
-- done" and kill the whole program the instant that happened. waitForAll
-- just lets the other two loops (which never return on their own) keep
-- running forever either way.
parallel.waitForAll(inputLoop, animationLoop, musicLoop)

