local kkc = require("kkc")
local gfx = require("kkc-graphics")
local key = require("kkc-key")
local mouse = require("kkc-mouse")
local rand = require("kkc-rand")
local fs = require("kkc-fs")
local audio = require("kkc-audio")

local app = {}
local ticks = 0
local message = "Hello from Lua App"
local last_mouse = "none"

function app.init(ctx)
    -- ctx contains id/name/version/description/width/height/args
    local marker = fs.join(".", "last-run.txt")
    fs.write_text(marker, "started at " .. tostring(kkc.time()))
    rand.seed(os.time())
end

function app.update(dt)
    ticks = ticks + 1
    if ticks % 120 == 0 then
        local n = rand.int(1, 9)
        message = "Random value: " .. tostring(n)
    end
end

function app.keypressed(k)
    if k == key.ESC then
        kkc.quit()
        return
    end
    if k == "char:b" then
        audio.beep()
    end
end

function app.mousepressed(button, x, y)
    last_mouse = string.format("%s @ %d,%d", button, x, y)
    if button == mouse.LEFT then
        audio.beep()
    end
end

function app.draw()
    local w, h = gfx.size()
    gfx.clear(" ")
    gfx.text(2, 2, "KKC Lua App Starter")
    gfx.text(2, 4, message)
    gfx.text(2, 6, "Screen: " .. tostring(w) .. "x" .. tostring(h))
    gfx.text(2, 7, "Time: " .. string.format("%.2f", kkc.time()))
    gfx.text(2, 8, "Mouse: " .. last_mouse)
    gfx.text(2, 9, "Press B to beep, Esc to quit")
end

return app
