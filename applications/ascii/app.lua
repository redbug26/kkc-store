-- ASCII Table
local g = require("kkc-graphics")

-- Layout: 8 columns, rows of entries, 2 pages (0-127, 128-255)
local W, H = 60, 30
local page = 0         -- 0 = 0..127, 1 = 128..255
local highlight = 0x20 -- highlighted code point

local COLS = 8

local CTRL_NAMES = {
    [0] = "NUL",
    [1] = "SOH",
    [2] = "STX",
    [3] = "ETX",
    [4] = "EOT",
    [5] = "ENQ",
    [6] = "ACK",
    [7] = "BEL",
    [8] = "BS ",
    [9] = "TAB",
    [10] = "LF ",
    [11] = "VT ",
    [12] = "FF ",
    [13] = "CR ",
    [14] = "SO ",
    [15] = "SI ",
    [16] = "DLE",
    [17] = "DC1",
    [18] = "DC2",
    [19] = "DC3",
    [20] = "DC4",
    [21] = "NAK",
    [22] = "SYN",
    [23] = "ETB",
    [24] = "CAN",
    [25] = "EM ",
    [26] = "SUB",
    [27] = "ESC",
    [28] = "FS ",
    [29] = "GS ",
    [30] = "RS ",
    [31] = "US ",
    [127] = "DEL",
}

local function char_label(n)
    if CTRL_NAMES[n] then return CTRL_NAMES[n] end
    if n >= 32 and n <= 126 then return " " .. string.char(n) .. " " end
    return string.format("%3d", n)
end

local app = {}

function app.init(ctx)
    W = ctx.width; H = ctx.height
end

function app.resize(w, h)
    W = w; H = h
end

function app.draw()
    g.clear()

    -- Title
    local title = string.format(" ASCII Table  Page %d/2 (0x%02X..0x%02X) ", page + 1, page * 128, page * 128 + 127)
    local tc = math.max(1, math.floor((W - #title) / 2) + 1)
    g.print(1, tc, title)
    g.print(2, 1, string.rep("─", W))

    local CELL = 9 -- " FF .   " padded to 9
    local cols = math.min(COLS, math.floor((W - 4) / CELL))
    if cols < 1 then cols = 1 end

    -- Column header
    local hdr = "     "
    for c = 0, cols - 1 do
        hdr = hdr .. string.format("  +%-5s", c)
    end
    g.print(3, 1, hdr)
    g.print(4, 1, string.rep("─", W))

    local start_offset = page * 128
    local rows = math.ceil(128 / cols)
    local r = 5
    for row = 0, rows - 1 do
        if r > H - 2 then break end
        local base = start_offset + row * cols
        local line = string.format("%02X   ", base)
        for c = 0, cols - 1 do
            local code = base + c
            if code > start_offset + 127 then
                line = line .. string.rep(" ", CELL)
            else
                local hl_l = (code == highlight) and "[" or " "
                local hl_r = (code == highlight) and "]" or " "
                local ch = char_label(code)
                line = line .. string.format("%s%02X %s%s", hl_l, code, ch, hl_r)
            end
        end
        g.print(r, 1, line)
        r = r + 1
    end

    g.print(H - 1, 1, string.rep("─", W))
    local info = string.format(
        " Dec:%-3d Hex:%02X Oct:%03o Char:%s | Arrows=move PgUp/Dn=page",
        highlight, highlight, highlight, char_label(highlight))
    g.print(H, 1, info:sub(1, W))
end

function app.keypressed(key)
    local page_size = 128
    if key == "right" then
        highlight = math.min(0xFF, highlight + 1)
        if highlight >= (page + 1) * page_size then page = page + 1 end
    elseif key == "left" then
        highlight = math.max(0, highlight - 1)
        if highlight < page * page_size then page = math.max(0, page - 1) end
    elseif key == "down" then
        highlight = math.min(0xFF, highlight + COLS)
        if highlight >= (page + 1) * page_size then page = page + 1 end
    elseif key == "up" then
        highlight = math.max(0, highlight - COLS)
        if highlight < page * page_size then page = math.max(0, page - 1) end
    elseif key == "pagedown" then
        page = math.min(1, page + 1)
        highlight = page * page_size
    elseif key == "pageup" then
        page = math.max(0, page - 1)
        highlight = page * page_size
    end
end

return app
