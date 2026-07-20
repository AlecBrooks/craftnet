local width, height = term.getSize()
local message = "CraftNet Gateway v0.1"

local x = math.floor((width - #message) / 2) + 1
local y = 2

term.setBackgroundColor(colors.blue)
term.setTextColor(colors.white)
term.clear()

term.setCursorPos(x, y)
term.setBackgroundColor(colors.magenta)
term.write(message)

term.setBackgroundColor(colors.blue)
term.setTextColor(colors.white)

term.setCursorPos(2, 4)
print("Gateway starting...")
print("hello world??")