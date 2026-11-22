-- Nokia-style Snake
local g   = require("kkc-graphics")

-- ─── Grid ─────────────────────────────────────────────────────────────────────
local GRID_W = 24
local GRID_H = 18
local CELL   = 2   -- chars per cell horizontally (e.g. "[]")

-- Terminal area (updated on resize)
local W, H = 60, 28

-- ─── State ────────────────────────────────────────────────────────────────────
local snake       -- list of {x,y}, head first
local dir         -- {dx,dy}
local next_dir    -- queued direction change
local food        -- {x,y}
local score
local high_score  = 0
local alive
local tick_acc    -- accumulator for speed throttle
local level_speed = 1.0  -- multiplier, increases with score

local function new_food()
    local occupied = {}
    for _, seg in ipairs(snake) do
        occupied[seg.x .. "," .. seg.y] = true
    end
    local free = {}
    for x = 1, GRID_W do
        for y = 1, GRID_H do
            if not occupied[x .. "," .. y] then
                free[#free + 1] = {x = x, y = y}
            end
        end
    end
    if #free == 0 then return nil end
    return free[math.random(#free)]
end

local function reset()
    local cx = math.floor(GRID_W / 2)
    local cy = math.floor(GRID_H / 2)
    snake     = {{x=cx,y=cy},{x=cx-1,y=cy},{x=cx-2,y=cy}}
    dir       = {dx=1, dy=0}
    next_dir  = {dx=1, dy=0}
    food      = new_food()
    score     = 0
    alive     = true
    tick_acc  = 0
    level_speed = 1.0
end

-- ─── Drawing ─────────────────────────────────────────────────────────────────
local function grid_origin()
    local gfx_w = GRID_W * CELL + 2
    local gfx_h = GRID_H + 2
    local ox = math.max(1, math.floor((W - gfx_w) / 2) + 1)
    local oy = math.max(1, math.floor((H - gfx_h - 2) / 2) + 2)
    return ox, oy
end

local app = {}

function app.init(ctx)
    W = ctx.width; H = ctx.height
    math.randomseed(os.time())
    reset()
end

function app.resize(w, h) W = w; H = h end

function app.draw()
    g.clear()

    local ox, oy = grid_origin()

    -- Header
    local title = " SNAKE "
    local htc = math.max(1, math.floor((W - #title) / 2) + 1)
    g.print(1, htc, title)
    g.print(1, 1, string.format("Score:%d", score))
    g.print(1, W - 9, string.format("Best:%d", high_score))

    -- Border
    g.print(oy, ox, "+" .. string.rep("-", GRID_W * CELL) .. "+")
    for row = 1, GRID_H do
        g.print(oy + row, ox, "|")
        g.print(oy + row, ox + GRID_W * CELL + 1, "|")
    end
    g.print(oy + GRID_H + 1, ox, "+" .. string.rep("-", GRID_W * CELL) .. "+")

    if not alive then
        local msg1 = "  GAME OVER  "
        local msg2 = string.format("  Score: %d  ", score)
        local msg3 = "  R = Restart  "
        local mid_y = oy + math.floor(GRID_H / 2)
        local mid_x = ox + 1 + math.floor((GRID_W * CELL - #msg1) / 2)
        g.print(mid_y - 1, mid_x, msg1)
        g.print(mid_y,     mid_x, msg2)
        g.print(mid_y + 1, ox + 1 + math.floor((GRID_W*CELL - #msg3)/2), msg3)
        return
    end

    -- Food
    if food then
        local fx = ox + 1 + (food.x - 1) * CELL
        local fy = oy + food.y
        g.print(fy, fx, "<>")
    end

    -- Snake
    for i, seg in ipairs(snake) do
        local sx = ox + 1 + (seg.x - 1) * CELL
        local sy = oy + seg.y
        if i == 1 then
            g.print(sy, sx, "@@")
        else
            g.print(sy, sx, "##")
        end
    end

    -- Bottom hint
    g.print(oy + GRID_H + 2, ox, "Arrows=steer  Esc=quit  R=restart")
end

function app.update(dt)
    if not alive then return end

    tick_acc = tick_acc + dt * level_speed

    if tick_acc < 1.0 then return end
    tick_acc = tick_acc - 1.0

    -- Apply queued direction (prevent reversing)
    if not (next_dir.dx == -dir.dx and next_dir.dy == -dir.dy) then
        dir = next_dir
    end

    -- New head position
    local head = snake[1]
    local nx = head.x + dir.dx
    local ny = head.y + dir.dy

    -- Wall collision
    if nx < 1 or nx > GRID_W or ny < 1 or ny > GRID_H then
        alive = false
        if score > high_score then high_score = score end
        return
    end

    -- Self collision
    for _, seg in ipairs(snake) do
        if seg.x == nx and seg.y == ny then
            alive = false
            if score > high_score then high_score = score end
            return
        end
    end

    -- Move
    table.insert(snake, 1, {x = nx, y = ny})

    -- Eat food?
    if food and nx == food.x and ny == food.y then
        score = score + 10
        level_speed = 1.0 + math.floor(score / 50) * 0.2
        food = new_food()
        -- Don't remove tail (snake grows)
    else
        table.remove(snake)
    end
end

function app.keypressed(key)
    -- key_name() sends lowercase for nav keys, "char:x" for characters
    if key == "up"    and dir.dy ~= 1  then next_dir = {dx=0,  dy=-1} end
    if key == "down"  and dir.dy ~= -1 then next_dir = {dx=0,  dy=1}  end
    if key == "left"  and dir.dx ~= 1  then next_dir = {dx=-1, dy=0}  end
    if key == "right" and dir.dx ~= -1 then next_dir = {dx=1,  dy=0}  end
    if key == "char:r" then reset() end
end

return app
