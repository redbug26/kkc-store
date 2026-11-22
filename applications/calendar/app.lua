local kkc = require("kkc")
local g = require("kkc-graphics")
local key = require("kkc-key")

local app = {}
local month = 1
local year = 2026

local month_names = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
}

local function is_leap(y)
    return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

local function days_in_month(m, y)
    if m == 2 then
        return is_leap(y) and 29 or 28
    end
    if m == 4 or m == 6 or m == 9 or m == 11 then
        return 30
    end
    return 31
end

-- Sakamoto weekday: 0=Sunday..6=Saturday
local function weekday(d, m, y)
    local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    if m < 3 then
        y = y - 1
    end
    return (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + t[m] + d) % 7
end

local function next_month()
    month = month + 1
    if month > 12 then
        month = 1
        year = year + 1
    end
end

local function prev_month()
    month = month - 1
    if month < 1 then
        month = 12
        year = year - 1
    end
end

function app.init()
    month = 5
    year = 2026
end

function app.keypressed(k)
    if k == key.ESC then
        kkc.quit()
    elseif k == key.LEFT or k == "char:p" then
        prev_month()
    elseif k == key.RIGHT or k == "char:n" then
        next_month()
    elseif k == key.UP then
        year = year + 1
    elseif k == key.DOWN then
        year = year - 1
    end
end

function app.draw()
    g.clear(" ")
    local title = month_names[month] .. " " .. tostring(year)
    g.text(2, 2, "Calendar")
    g.text(2, 3, title)
    g.text(2, 5, "Su Mo Tu We Th Fr Sa")

    local first = weekday(1, month, year)
    local days = days_in_month(month, year)
    local col = first
    local row = 0
    for day = 1, days do
        local x = 2 + col * 3
        local y = 7 + row
        g.text(x, y, string.format("%2d", day))
        col = col + 1
        if col >= 7 then
            col = 0
            row = row + 1
        end
    end

    g.text(2, 16, "Left/Right or P/N: month")
    g.text(2, 17, "Up/Down: year")
    g.text(2, 18, "Esc: quit")
end

return app
