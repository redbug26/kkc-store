-- Responsive character-cell renderer. One maze tile is 2 x 1 terminal cells
-- at x1; integral scaling preserves the terminal's approximate 1:2 aspect.
local gfx = require("kkc-graphics")
local Game = require("game")
local View = {}
local C = {
    bg = 0x080D1C, panel = 0x111D35, floor = 0x0B1226, text = 0xE9F0FF,
    muted = 0x8297BE, blue = 0x4C86FF, yellow = 0xFFE264, cyan = 0x64E2E8,
    pink = 0xFF95CA, red = 0xFF686F, orange = 0xFFB76B,
}
local ghosts = {C.red, C.pink, C.cyan, C.orange}
local font = {
    P = {"11110", "10001", "11110", "10000", "10000"},
    E = {"11111", "10000", "11110", "10000", "11111"},
    R = {"11110", "10001", "11110", "10010", "10001"},
    B = {"11110", "10001", "11110", "10001", "11110"},
    U = {"10001", "10001", "10001", "10001", "01110"},
    S = {"01111", "10000", "01110", "00001", "11110"},
    T = {"11111", "00100", "00100", "00100", "00100"},
}
local function text(x, y, value, color, background)
    gfx.color(color or C.text, background or C.bg)
    gfx.text(math.floor(x), math.floor(y), value)
end
local function center(w, y, value, color, background)
    text(math.max(1, (w - #value) // 2 + 1), y, value, color, background)
end
local function fill(x, y, w, h, color, char, fg)
    gfx.color(fg or color, color)
    gfx.box(x, y, w, h, char or " ")
end
local function frame(x, y, w, h, color, background)
    if w < 2 or h < 2 then return end
    fill(x, y, w, h, background or C.bg)
    text(x, y, "+" .. string.rep("-", w - 2) .. "+", color, background)
    text(x, y + h - 1, "+" .. string.rep("-", w - 2) .. "+", color, background)
    for row = y + 1, y + h - 2 do
        text(x, row, "|", color, background)
        text(x + w - 1, row, "|", color, background)
    end
end
function View.layout(w, h, pac)
    local available_w, available_h = math.max(2, w - 2), math.max(1, h - 6)
    local zoom = math.max(1, math.min(available_w // (Game.W * 2), available_h // Game.H))
    local tw, th = 2 * zoom, zoom
    local columns = math.min(Game.W, math.max(1, available_w // tw))
    local rows = math.min(Game.H, math.max(1, available_h // th))
    return {
        zoom = zoom, tw = tw, th = th, columns = columns, rows = rows,
        left = (w - columns * tw) // 2 + 1,
        top = 4 + (available_h - rows * th) // 2,
        cx = math.max(0, math.min(Game.W - columns, pac.tile_x - columns // 2)),
        cy = math.max(0, math.min(Game.H - rows, pac.tile_y - rows // 2)),
    }
end
local function logo(w, h)
    if w < 77 and h < 29 then
        center(w, 6, "P E P P E R   B U S T E R", C.yellow)
        return 7
    end
    local word = "PEPPERBUSTER"
    local logical_w = #word * 6 - 1
    local zoom = math.max(1, math.min((w - 8) // logical_w, math.max(1, (h - 16) // 5)))
    local y = math.max(5, math.floor(h * 0.16))
    if logical_w > w - 6 then
        word, logical_w = "PEPPER", 35
        zoom = math.max(1, math.min((w - 6) // logical_w, (h - 16) // 10))
        y = 5
    end
    local function line(value, row, color)
        local x = (w - (#value * 6 - 1) * zoom) // 2 + 1
        for index = 1, #value do
            local glyph = font[value:sub(index, index)]
            if glyph then
                for gy, pixels in ipairs(glyph) do
                    for gx = 1, 5 do
                        if pixels:sub(gx, gx) == "1" then
                            fill(x + (index - 1) * 6 * zoom + (gx - 1) * zoom,
                                row + (gy - 1) * zoom, zoom, zoom, C.bg, "█", color)
                        end
                    end
                end
            end
        end
    end
    line(word, y, C.yellow)
    if word == "PEPPER" then line("BUSTER", y + 6 * zoom, C.orange); return y + 11 * zoom end
    return y + 5 * zoom
end
function View.menu(ui)
    local w, h = ui.width, ui.height
    frame(1, 1, w, h - 1, C.blue, C.bg)
    if w < 54 or h < 22 then
        center(w, 2, "PEPPER BUSTER", C.yellow)
        center(w, 4, string.format("Maze %d/8  Lives %d/5", ui.selected_level + 1, ui.selected_lives), C.cyan)
        center(w, 6, "Enter: Start Esc: Quit", C.text)
        center(w, 7, "Arrows: Setup", C.muted)
        center(w, 8, "Space / T: Turbo", C.muted)
        center(w, h - 2, string.format("BEST %06d", ui.highscore), C.yellow)
        return
    end
    center(w, 3, "THE KAPSULE EDITION", C.cyan)
    local bottom = logo(w, h)
    local setup_y = math.max(bottom + 3, math.floor(h * 0.57))
    -- Keep room for start button and two rows of controls on shorter terminals.
    setup_y = math.min(setup_y, h - 10)
    local margin = math.max(3, w // 12)
    local panel_w = (w - margin * 2 - 2) // 2
    frame(margin, setup_y, panel_w, 3, C.blue, C.panel)
    frame(margin + panel_w + 2, setup_y, panel_w, 3, C.blue, C.panel)
    local maze = string.format("<  MAZE %02d / 08  >", ui.selected_level + 1)
    local lives = string.format("^  LIVES %d / 5  v", ui.selected_lives)
    text(margin + (panel_w - #maze) // 2, setup_y + 1, maze, C.cyan, C.panel)
    text(margin + panel_w + 2 + (panel_w - #lives) // 2, setup_y + 1, lives, C.pink, C.panel)
    local button_y = math.max(setup_y + 4, h - 6)
    if setup_y - bottom >= 8 then
        -- The extra area on larger screens becomes a ghost parade, not a gap.
        local scale = math.min(5, math.max(2, (setup_y - bottom - 3) // 2))
        local names = {"CHASE", "AMBUSH", "AHEAD", "WANDER"}
        for index, color in ipairs(ghosts) do
            local cx = math.floor(w * (index - 0.5) / 4)
            local x, y = cx - scale, bottom + 2
            for row = 0, scale - 1 do
                for col = 0, scale * 2 - 1 do
                    if (row > 0 or col > 0 and col < scale * 2 - 1) and (row ~= scale - 1 or col % 2 == 0) then
                        text(x + col, y + row, "█", color)
                    end
                end
            end
            text(x + scale - 1, y + math.max(0, scale // 2 - 1), "o o", C.text)
            text(cx - #names[index] // 2, y + scale + 1, names[index], color)
        end
    end
    if button_y - setup_y >= 11 then
        center(w, setup_y + 5, "MYSTERY BONUSES", C.cyan)
        local names = {"HIDE WALLS", "TURBO REFILL", "FRIGHTEN GHOSTS", "INVERT CONTROLS", "HUNGRY GHOSTS", "EXTRA LIFE"}
        local colors = {C.blue, C.yellow, C.cyan, C.pink, C.red, C.orange}
        local column_w = (w - margin * 2) // 3
        for index, name in ipairs(names) do
            local col, row = (index - 1) % 3, (index - 1) // 3
            local x = margin + col * column_w
            text(x + 1, setup_y + 7 + row * 2, "?", colors[index])
            text(x + 4, setup_y + 7 + row * 2, name, C.muted)
        end
    end
    local button_w = w - margin * 2 + 1
    fill(margin, button_y, button_w, 2, C.yellow)
    center(w, button_y, "ENTER / SPACE   -   START PLAYING", C.bg, C.yellow)
    center(w, h - 3, "ARROWS/WASD: Steer   SPACE: Turbo   T: Toggle", C.text)
    center(w, h - 2, string.format("BEST %06d   M: Sound %s   ESC: Quit", ui.highscore, ui.sound and "ON" or "OFF"), C.muted)
end
local function sprite(game, a, index, layout, ui)
    local z, tw, th = layout.zoom, layout.tw, layout.th
    local x = layout.left + math.floor((a.x - 6) * tw / 12 + 0.5) - layout.cx * tw
    local y = layout.top + math.floor((a.y - 12) * th / 24 + 0.5) - layout.cy * th
    local function pixel(col, row, color, ch)
        local sx, sy = x + col, y + row
        if sx >= layout.left and sx < layout.left + layout.columns * tw and sy >= layout.top and sy < layout.top + layout.rows * th then
            text(sx, sy, ch or "█", color, C.floor)
        end
    end
    if z == 1 then
        if index then
            local color, shape = ghosts[index], "╭╮"
            if a.mode == Game.WAIT then color = 0x45536E
            elseif a.mode == Game.EYES then color, shape = C.text, "°°"
            elseif game.bonus == Game.AFRAID then color, shape = C.cyan, "^^" end
            if game.bonus == Game.AFRAID and game.bonus_time < 100 and math.floor(ui.elapsed * 8) % 2 == 0 then color = C.text end
            if x >= layout.left and x + 1 < layout.left + layout.columns * tw and y >= layout.top and y < layout.top + layout.rows then text(x, y, shape, color, C.floor) end
        else
            local shape = "●"
            if math.floor(ui.elapsed * 12) % 2 == 0 then shape = ({"v", "^", ">", "<"})[a.dir] or "C" end
            pixel(0, 0, C.yellow, shape)
        end
        return x, y
    end
    local frightened = index and a.mode == Game.ACTIVE and game.bonus == Game.AFRAID
    local color = index and ghosts[index] or C.yellow
    if index and a.mode == Game.WAIT then color = 0x45536E end
    if frightened then color = game.bonus_time < 100 and math.floor(ui.elapsed * 8) % 2 == 0 and C.text or C.cyan end
    for row = 0, th - 1 do
        for col = 0, tw - 1 do
            local nx, ny = (col + 0.5 - tw / 2) / (tw / 2), (row + 0.5 - th / 2) / (th / 2)
            if index then
                if a.mode ~= Game.EYES and (row > 0 or math.abs(nx) < 0.7) then
                    if row ~= th - 1 or col % 2 == 0 then pixel(col, row, color) end
                end
            elseif nx * nx + ny * ny <= 1 then
                local mouth = false
                if math.floor(ui.elapsed * 12) % 2 == 0 then
                    if a.dir == Game.RIGHT then mouth = nx > 0 and math.abs(ny) < nx
                    elseif a.dir == Game.LEFT then mouth = nx < 0 and math.abs(ny) < -nx
                    elseif a.dir == Game.UP then mouth = ny < 0 and math.abs(nx) < -ny
                    elseif a.dir == Game.DOWN then mouth = ny > 0 and math.abs(nx) < ny end
                end
                if not mouth then pixel(col, row, color) end
            end
        end
    end
    if index then
        local row = math.max(0, th // 2 - 1)
        pixel(math.max(0, z - 1), row, C.text, frightened and "x" or "o")
        pixel(math.min(tw - 1, z + 1), row, C.text, frightened and "x" or "o")
    end
    return x, y
end
local function maze(game, ui, dimmed)
    local l = View.layout(ui.width, ui.height, game.pac)
    local wall_mode = game:wall_mode()
    if ui.mode == "clear" then wall_mode = math.floor(ui.elapsed * 8) % 2 == 0 and 2 or 0 end
    local wall = dimmed and 0x203154 or (wall_mode == 2 and C.text or C.blue)
    for y = l.cy, l.cy + l.rows - 1 do
        for x = l.cx, l.cx + l.columns - 1 do
            local value = game:at(x, y)
            local sx, sy = l.left + (x - l.cx) * l.tw, l.top + (y - l.cy) * l.th
            if value < Game.EMPTY and wall_mode ~= 1 then
                fill(sx, sy, l.tw, l.th, dimmed and C.bg or 0x142849, "▓", wall)
            else
                fill(sx, sy, l.tw, l.th, C.floor)
                local px, py = sx + l.tw // 2 - 1, sy + (l.th - 1) // 2
                if value == Game.PILL then
                    local color = dimmed and 0x364359 or 0xFFE3B0
                    if l.zoom > 1 then fill(px, py, math.max(1, l.zoom - 1), math.max(1, l.zoom // 3), color)
                    else text(px, py, "·", color, C.floor) end
                elseif value == Game.POWER and math.floor(ui.elapsed * 4) % 2 == 0 then
                    if l.zoom > 1 then fill(px, py, math.max(2, l.zoom), math.max(1, l.zoom // 2), C.yellow)
                    else text(px, py, "●", C.yellow, C.floor) end
                elseif value == Game.BONUS then text(px, py, "?", C.pink, C.floor) end
            end
        end
    end
    if dimmed then return l end
    for index, ghost in ipairs(game.ghosts) do sprite(game, ghost, index, l, ui) end
    if ui.mode ~= "caught" or math.floor(ui.elapsed * 12) % 2 == 0 then sprite(game, game.pac, nil, l, ui) end
    if ui.popup then
        local a = game.ghosts[ui.popup.ghost]
        local x = l.left + (a.tile_x - l.cx) * l.tw
        local y = l.top + (a.tile_y - l.cy) * l.th
        text(x, y, tostring(ui.popup.value), C.yellow, C.floor)
    end
    return l
end
local function card(ui, title, lines, accent)
    local w, h = math.min(52, ui.width - 4), #lines + 4
    local x, y = (ui.width - w) // 2 + 1, math.max(2, (ui.height - h) // 2 + 1)
    frame(x, y, w, h, C.blue, C.panel)
    text(x + (w - #title) // 2, y + 1, title, accent or C.yellow, C.panel)
    for i, line in ipairs(lines) do text(x + 2, y + i + 2, line:sub(1, w - 4), C.text, C.panel) end
end
function View.draw(game, ui)
    fill(1, 1, ui.width, ui.height, C.bg)
    local w, h = ui.width, ui.height
    if w < 30 or h < 12 then
        center(w, 2, "PEPPER BUSTER", C.yellow)
        center(w, 4, "Enlarge window to 30 x 12", C.muted)
        return
    end
    if ui.mode == "menu" then View.menu(ui); return end
    local score = string.format("%06d", game.score * 10)
    text(2, 1, "PEPPER BUSTER", C.yellow)
    if w >= 58 then text(w - 28, 1, string.format("BEST %06d  SCORE %s", math.max(ui.highscore, game.score * 10), score))
    else text(w - 13, 1, "SCORE " .. score) end
    text(2, 2, string.format("LEVEL %02d  LIVES %d  PILLS %03d", game.level + 1, game.lives, game.remaining), C.muted)
    if w >= 58 then
        text(w - 22, 2, "TURBO ", C.muted)
        text(w - 16, 2, string.rep("|", game.turbo) .. string.rep(".", 16 - game.turbo), ui.turbo and C.yellow or C.cyan)
    end
    local l = maze(game, ui, ui.mode == "paused" or ui.mode == "over")
    local status = ui.status:sub(1, w - 2)
    center(w, h - 2, status, C.cyan)
    if w > 60 then text(w - 9, h - 1, "ZOOM x" .. l.zoom, C.muted) end
    if ui.mode == "paused" then
        card(ui, "PAUSED", { "", "  ENTER / P / ESC   Resume", "  R                 Restart", "  Q                 Main menu", "" }, C.cyan)
    elseif ui.mode == "ready" then
        card(ui, "READY!", {"  Arrows to steer - Space for turbo", "  Small pills clear the maze."})
    elseif ui.mode == "over" then
        card(ui, "GAME OVER", {"", "  SCORE   " .. score, string.format("  BEST    %06d", ui.highscore), "", "  ENTER: Try again   Q: Main menu"}, C.red)
    elseif ui.mode == "clear" then center(w, h - 3, "MAZE CLEAR!", C.yellow) end
end
return View
