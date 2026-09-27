-- show_bg.lua
-- Displays only the background image (bg.nfp) on the monitor wall,
-- with nothing else running. Useful for previewing/checking the image
-- without starting the slot machine game.

local mon = peripheral.find("monitor")
if not mon then
  error("No monitor found! Attach the monitor wall to this computer.")
end

mon.setTextScale(0.5)

local IMG_PATH = "bg.nfp"
if not fs.exists(IMG_PATH) then
  error("Couldn't find " .. IMG_PATH .. " in this folder.")
end

local ok, img = pcall(paintutils.loadImage, IMG_PATH)
if not ok or not img then
  error("Failed to load " .. IMG_PATH .. " as an image.")
end

mon.setBackgroundColor(colors.black)
mon.clear()
paintutils.drawImage(img, 1, 1, mon)

print("Background image is now showing on the monitor.")
print("Run slot_machine to go back to the game.")
