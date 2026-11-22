local kkc = require("kkc")
local g = require("kkc-graphics")
local key = require("kkc-key")

local app = {}

local board_w = 10
local board_h = 20
local board = {}
local active = nil
local next_piece = nil
local drop_timer = 0
local base_drop_delay = 0.55
local drop_delay = base_drop_delay
local score = 0
local lines_cleared = 0
local level = 1
local game_over = false

local piece_styles = {
    I = "██",
    O = "▓▓",
    T = "▒▒",
    S = "██",
    Z = "▓▓",
    J = "▒▒",
    L = "██",
}

local piece_colors = {
    I = 0x29B6F6,
    O = 0xFFD54F,
    T = 0xBA68C8,
    S = 0x81C784,
    Z = 0xEF5350,
    J = 0x64B5F6,
    L = 0xFFB74D,
}

local pieces = {
    {
        kind = "I",
        rotations = {
            { "....", "####", "....", "...." },
            { "..#.", "..#.", "..#.", "..#." },
            { "....", "....", "####", "...." },
            { ".#..", ".#..", ".#..", ".#.." },
        },
    },
    {
        kind = "O",
        rotations = {
            { "....", ".##.", ".##.", "...." },
            { "....", ".##.", ".##.", "...." },
            { "....", ".##.", ".##.", "...." },
            { "....", ".##.", ".##.", "...." },
        },
    },
    {
        kind = "T",
        rotations = {
            { "....", ".###", "..#.", "...." },
            { "..#.", ".##.", "..#.", "...." },
            { "..#.", ".###", "....", "...." },
            { ".#..", ".##.", ".#..", "...." },
        },
    },
    {
        kind = "S",
        rotations = {
            { "....", "..##", ".##.", "...." },
            { ".#..", ".##.", "..#.", "...." },
            { "....", "..##", ".##.", "...." },
            { ".#..", ".##.", "..#.", "...." },
        },
    },
    {
        kind = "Z",
        rotations = {
            { "....", ".##.", "..##", "...." },
            { "..#.", ".##.", ".#..", "...." },
            { "....", ".##.", "..##", "...." },
            { "..#.", ".##.", ".#..", "...." },
        },
    },
    {
        kind = "J",
        rotations = {
            { "....", ".###", "...#", "...." },
            { "..#.", "..#.", ".##.", "...." },
            { ".#..", ".###", "....", "...." },
            { ".##.", ".#..", ".#..", "...." },
        },
    },
    {
        kind = "L",
        rotations = {
            { "....", ".###", ".#..", "...." },
            { ".##.", "..#.", "..#.", "...." },
            { "...#", ".###", "....", "...." },
            { ".#..", ".#..", ".##.", "...." },
        },
    },
}

local function reset_board()
    board = {}
    for y = 1, board_h do
        board[y] = {}
        for x = 1, board_w do
            board[y][x] = nil
        end
    end
end

local function make_piece(template)
    return {
        kind = template.kind,
        rotations = template.rotations,
        tile = piece_styles[template.kind] or "[]",
        rot = 1,
        x = math.floor(board_w / 2) - 1,
        y = 0,
    }
end

local function random_piece()
    local template = pieces[math.random(#pieces)]
    return make_piece(template)
end

local function piece_cells(piece, test_rot, test_x, test_y)
    local cells = {}
    local rot = test_rot or piece.rot
    local px = test_x or piece.x
    local py = test_y or piece.y
    local mask = piece.rotations[rot]
    for y = 1, 4 do
        local row = mask[y]
        for x = 1, 4 do
            if row:sub(x, x) == "#" then
                table.insert(cells, { x = px + x - 1, y = py + y - 1 })
            end
        end
    end
    return cells
end

local function collides(piece, rot, px, py)
    local cells = piece_cells(piece, rot, px, py)
    for _, c in ipairs(cells) do
        if c.x < 1 or c.x > board_w or c.y > board_h then
            return true
        end
        if c.y >= 1 and board[c.y][c.x] ~= nil then
            return true
        end
    end
    return false
end

local function lock_piece()
    for _, c in ipairs(piece_cells(active)) do
        if c.y >= 1 and c.y <= board_h and c.x >= 1 and c.x <= board_w then
            board[c.y][c.x] = active.kind
        end
    end
end

local function clear_lines()
    local kept = {}
    local removed = 0
    for y = 1, board_h do
        local full = true
        for x = 1, board_w do
            if board[y][x] == nil then
                full = false
                break
            end
        end
        if full then
            removed = removed + 1
        else
            table.insert(kept, board[y])
        end
    end
    while #kept < board_h do
        local row = {}
        for x = 1, board_w do
            row[x] = nil
        end
        table.insert(kept, 1, row)
    end
    board = kept

    if removed > 0 then
        local line_points = { 0, 100, 300, 500, 800 }
        score = score + (line_points[removed + 1] or 0) * level
        lines_cleared = lines_cleared + removed
        level = math.floor(lines_cleared / 10) + 1
        drop_delay = math.max(0.08, base_drop_delay - (level - 1) * 0.04)
    end
end

local function spawn_piece()
    active = next_piece or random_piece()
    active.rot = 1
    active.x = math.floor(board_w / 2) - 1
    active.y = 0
    next_piece = random_piece()
    if collides(active, active.rot, active.x, active.y) then
        game_over = true
    end
end

local function try_move(dx, dy)
    if not active then
        return false
    end
    local nx = active.x + dx
    local ny = active.y + dy
    if collides(active, active.rot, nx, ny) then
        return false
    end
    active.x = nx
    active.y = ny
    return true
end

local function try_rotate()
    if not active then
        return
    end
    local next_rot = active.rot + 1
    if next_rot > #active.rotations then
        next_rot = 1
    end

    local kicks = { 0, -1, 1, -2, 2 }
    for _, dx in ipairs(kicks) do
        if not collides(active, next_rot, active.x + dx, active.y) then
            active.rot = next_rot
            active.x = active.x + dx
            return
        end
    end
end

local function ghost_y(piece)
    local y = piece.y
    while not collides(piece, piece.rot, piece.x, y + 1) do
        y = y + 1
    end
    return y
end

function app.init()
    math.randomseed(os.time())
    reset_board()
    score = 0
    lines_cleared = 0
    level = 1
    drop_delay = base_drop_delay
    game_over = false
    drop_timer = 0
    next_piece = random_piece()
    spawn_piece()
end

function app.update(dt)
    if game_over then
        return
    end
    drop_timer = drop_timer + dt
    if drop_timer >= drop_delay then
        drop_timer = 0
        if not try_move(0, 1) then
            lock_piece()
            clear_lines()
            spawn_piece()
        end
    end
end

function app.keypressed(k)
    if k == key.ESC then
        kkc.quit()
        return
    end

    if game_over and (k == "char:r" or k == "char:R") then
        app.init()
        return
    end

    if game_over then
        return
    end

    if k == key.LEFT then
        try_move(-1, 0)
    elseif k == key.RIGHT then
        try_move(1, 0)
    elseif k == key.DOWN then
        if not try_move(0, 1) then
            lock_piece()
            clear_lines()
            spawn_piece()
        end
    elseif k == key.UP then
        try_rotate()
    elseif k == key.SPACE then
        while try_move(0, 1) do
        end
        lock_piece()
        clear_lines()
        spawn_piece()
    end
end

function app.draw()
    local term_w, term_h = g.size()
    local play_w = board_w * 2
    local total_w = play_w + 2 + 20
    local origin_x = math.max(2, math.floor((term_w - total_w) / 2))
    local origin_y = math.max(2, math.floor((term_h - 24) / 2))
    local side_x = origin_x + play_w + 4

    g.clear(" ")
    g.reset()

    -- Arena frame (Unicode box drawing)
    g.color(0xE0E0E0, 0x000000)
    g.text(origin_x, origin_y, "╔════════════════════╗")
    for y = 1, board_h do
        g.text(origin_x, origin_y + y, "║                    ║")
    end
    g.text(origin_x, origin_y + board_h + 1, "╚════════════════════╝")

    -- Draw placed tiles per-piece color
    for y = 1, board_h do
        for x = 1, board_w do
            local kind = board[y][x]
            if kind ~= nil then
                local px = origin_x + 1 + (x - 1) * 2
                g.color(piece_colors[kind] or 0x90CAF9, 0x000000)
                local tile = piece_styles[kind] or "██"
                g.text(px, origin_y + y, tile)
            end
        end
    end

    -- Draw ghost piece in dim dots
    g.color(0x505050, 0x000000)
    if active then
        local gy = ghost_y(active)
        for _, c in ipairs(piece_cells(active, active.rot, active.x, gy)) do
            if c.y >= 1 and c.y <= board_h then
                local px = origin_x + 1 + (c.x - 1) * 2
                local py = origin_y + c.y
                if board[c.y][c.x] == nil then
                    g.text(px, py, "··")
                end
            end
        end

        -- Draw active piece with its own color
        g.color(piece_colors[active.kind] or 0x00FF00, 0x000000)
        for _, c in ipairs(piece_cells(active)) do
            if c.y >= 1 and c.y <= board_h then
                local px = origin_x + 1 + (c.x - 1) * 2
                local py = origin_y + c.y
                g.text(px, py, active.tile)
            end
        end
    end

    -- Side panel title (UTF-8, terminal-width safe)
    g.color(0xFFE082, 0x000000)
    g.text(side_x, origin_y + 1, "╭────────────────╮")
    g.text(side_x, origin_y + 2, "│     TETRIS     │")
    g.text(side_x, origin_y + 3, "╰────────────────╯")

    -- Stats
    g.color(0xFFF176, 0x000000)
    g.text(side_x, origin_y + 5, "★ Score " .. tostring(score))
    g.text(side_x, origin_y + 6, "■ Lines " .. tostring(lines_cleared))
    g.text(side_x, origin_y + 7, "▲ Level " .. tostring(level))

    -- Next piece preview
    g.color(0xB0BEC5, 0x000000)
    g.text(side_x, origin_y + 9, "Next piece")
    g.text(side_x, origin_y + 10, "╭──────────╮")
    g.text(side_x, origin_y + 14, "╰──────────╯")

    if next_piece then
        g.color(piece_colors[next_piece.kind] or 0x4DD0E1, 0x000000)
        for _, c in ipairs(piece_cells(next_piece, 1, 0, 0)) do
            local px = side_x + 2 + c.x * 2
            local py = origin_y + 10 + c.y
            g.text(px, py, next_piece.tile)
        end
    end

    -- Controls
    g.color(0x80DEEA, 0x000000)
    g.text(side_x, origin_y + 16, "← → Move")
    g.text(side_x, origin_y + 17, "↑ Rotate")
    g.text(side_x, origin_y + 18, "↓ Soft drop")
    g.text(side_x, origin_y + 19, "Space Hard drop")
    g.text(side_x, origin_y + 20, "Esc Quit")

    -- Game over banner
    if game_over then
        g.color(0xF06292, 0x000000)
        g.text(origin_x + 2, origin_y + 10, "╔══════════════════╗")
        g.text(origin_x + 2, origin_y + 11, "║    GAME OVER     ║")
        g.text(origin_x + 2, origin_y + 12, "╚══════════════════╝")
        g.text(origin_x + 2, origin_y + 14, "Press R to restart")
    end

    g.reset()
end

return app
