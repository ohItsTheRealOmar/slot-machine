-- show_bg.lua
-- Displays only the background image (bg.nfp) on the monitor wall,
-- auto-scaled to fit whatever size the monitor actually is.
-- Nothing else runs -- no game, no buttons.

-- Find every monitor and use the BIGGEST one (in case a stray extra
-- monitor block exists somewhere and confuses peripheral.find).
local bestMon, bestArea = nil, -1
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "monitor" then
    local p = peripheral.wrap(name)
    local ok, w, h = pcall(function() return p.getSize() end)
    if ok then
      local area = w * h
      if area > bestArea then
        bestMon, bestArea = p, area
      end
    end
  end
end

if not bestMon then
  error("No monitor found! Attach the monitor wall to this computer.")
end

local mon = bestMon
mon.setTextScale(0.5)
local monW, monH = mon.getSize()

-- ---- CHANGE THIS to resize the image ----
-- 1.0   = fills the whole monitor (default)
-- 0.5   = half size, centered, black around it
-- 1.5   = 150% size, centered, edges get cropped off-screen
local IMG_SCALE = .10

local IMG_PATH = "bg.nfp"
if not fs.exists(IMG_PATH) then
  error("Couldn't find " .. IMG_PATH .. " in this folder.")
end

local ok, img = pcall(paintutils.loadImage, IMG_PATH)
if not ok or not img then
  error("Failed to load " .. IMG_PATH .. " as an image.")
end

-- ---- auto-scale the loaded image to exactly fill the monitor ----
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

local drawW = math.max(1, math.floor(monW * IMG_SCALE))
local drawH = math.max(1, math.floor(monH * IMG_SCALE))
local finalImg = scaleImage(img, drawW, drawH)

-- center it on the monitor (if smaller, black shows around it;
-- if bigger, the excess just draws off-screen and gets clipped)
local drawX = math.floor((monW - drawW) / 2) + 1
local drawY = math.floor((monH - drawH) / 2) + 1

mon.setBackgroundColor(colors.black)
mon.clear()
paintutils.drawImage(finalImg, drawX, drawY, mon)

print("Background image is now showing on the monitor (" .. drawW .. "x" .. drawH .. " at scale " .. IMG_SCALE .. ").")
print("Run slot_machine to go back to the game.")
