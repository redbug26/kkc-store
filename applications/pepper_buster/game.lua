-- Pepper Buster rules, adapted from GX4000 src/game.c by Miguel Vanhove.
-- No host APIs: the simulation can be tested independently of rendering.
local levels = require("levels")
local Game = {}
Game.__index = Game
Game.W, Game.H = 25, 15
Game.UP, Game.DOWN, Game.LEFT, Game.RIGHT = 1, 2, 3, 4
Game.NONE, Game.HIDE, Game.QUICK, Game.AFRAID = 0, 1, 2, 3
Game.INVERT, Game.BAD, Game.LIFE = 4, 5, 6
Game.WAIT, Game.ACTIVE, Game.EYES = 0, 1, 2
Game.PLAY, Game.CLEAR, Game.CAUGHT = 0, 1, 2
Game.EMPTY, Game.PILL, Game.POWER, Game.BONUS = 16, 17, 18, 19

local function opposite(d)
    return ({2, 1, 4, 3})[d] or 0
end
local function centered(a)
    return a.phase_x == 6 and a.phase_y == 12
end
local function actor(x, y)
    return {x = x, y = y, tile_x = x // 12, tile_y = y // 24,
        phase_x = x % 12, phase_y = y % 24, dir = 0, pending = 0}
end
function Game:place(a, x, y)
    a.x, a.y = x, y
    a.tile_x, a.tile_y = x // 12, y // 24
    a.phase_x, a.phase_y = x % 12, y % 24
end
function Game:at(x, y)
    if x < 0 or y < 0 or x >= self.W or y >= self.H then return 0 end
    return self.field[y * self.W + x + 1]
end
function Game:random()
    self.seed = (self.seed * 17 + 29) % 256
    return self.seed
end
function Game:random_max(maximum)
    return (self:random() * maximum) // 256
end
function Game:next_cell(a, dir)
    local x, y = a.tile_x, a.tile_y
    if dir == self.UP then y = y - 1
    elseif dir == self.DOWN then y = y + 1
    elseif dir == self.LEFT then
        x = x - 1
        if x < 0 and y > 0 and y < self.H - 1 then x = self.W - 2 end
    elseif dir == self.RIGHT then
        x = x + 1
        if x == self.W and y > 0 and y < self.H - 1 then x = 1 end
    else return nil end
    if self:at(x, y) < self.EMPTY then return nil end
    -- Preserve the original asymmetric side-tunnel convention.
    if dir == self.RIGHT and a.tile_x == self.W - 2 then x = 0 end
    return x, y
end
function Game:can_turn(a, dir)
    return centered(a) and self:next_cell(a, dir) ~= nil
end
function Game:move(a)
    if a.dir == self.UP then
        a.y = a.y - 2
        if a.phase_y < 2 then
            a.phase_y, a.tile_y = a.phase_y + 22, a.tile_y - 1
        else a.phase_y = a.phase_y - 2 end
    elseif a.dir == self.DOWN then
        a.y, a.phase_y = a.y + 2, a.phase_y + 2
        if a.phase_y >= 24 then a.phase_y, a.tile_y = a.phase_y - 24, a.tile_y + 1 end
    elseif a.dir == self.LEFT then
        a.x = a.x - 1
        if a.phase_x == 0 then a.phase_x, a.tile_x = 11, a.tile_x - 1
        else a.phase_x = a.phase_x - 1 end
    elseif a.dir == self.RIGHT then
        a.x, a.phase_x = a.x + 1, a.phase_x + 1
        if a.phase_x == 12 then a.phase_x, a.tile_x = 0, a.tile_x + 1 end
    end
    if a.x < 6 then a.x, a.phase_x, a.tile_x = (self.W - 2) * 12 + 6, 6, self.W - 2 end
    if a.x > (self.W - 2) * 12 + 6 then a.x, a.phase_x, a.tile_x = 6, 6, 0 end
end
function Game:clear_bonus()
    if self.bonus ~= self.HIDE then self.wall_flash = 16 end
    self.bonus, self.bonus_time = self.NONE, 0
end
function Game:switch_bonus(b)
    local old = self.bonus
    self.last_bonus = b
    if b ~= self.HIDE then self.wall_flash = 16 end
    if old ~= self.NONE then self:clear_bonus() end
    self.bonus, self.bonus_time = b, 500
    if b == self.HIDE then self.wall_flicker = 20
    elseif b == self.QUICK then
        self.turbo, self.bonus, self.bonus_time = 16, self.NONE, 0
    elseif b == self.AFRAID then
        for _, ghost in ipairs(self.ghosts) do
            if ghost.mode == self.ACTIVE then ghost.dir = opposite(ghost.dir) end
        end
        if old ~= self.AFRAID then self.killed = 0 end
    elseif b == self.LIFE then self.lives = math.min(5, self.lives + 1) end
end
function Game:restart_positions()
    self.pac = actor(self.start_x * 12 + 6, self.start_y * 24 + 12)
    self.ghosts = {}
    for i = 1, 4 do
        local ghost = actor(self.ghost_x * 12 + 6, self.ghost_y * 24 + 12)
        ghost.mode = i == 1 and self.ACTIVE or self.WAIT
        ghost.wait, ghost.speed = (i - 1) * 130, 0
        self.ghosts[i] = ghost
    end
    if self.bonus ~= self.NONE then self:clear_bonus() end
    self.wall_flash, self.wall_flicker = 0, 0
    self.turbo, self.turbo_use, self.fast = 0, 0, false
    self.killed, self.events, self.state = 0, 0, self.PLAY
end
function Game:start(level)
    self.level, self.seed = level, (37 + level * 29) % 256
    self.field, self.remaining = {}, 0
    self.bonus_x, self.bonus_y = 0, 0
    local rows = levels[level % #levels + 1]
    for y = 0, self.H - 1 do
        for x = 0, self.W - 1 do
            local char = rows[y + 1]:sub(x + 1, x + 1)
            local value = self.EMPTY
            if char == "#" then value = 0
            elseif char == "." then value, self.remaining = self.PILL, self.remaining + 1
            elseif char == "o" then value = self.POWER
            elseif char == "S" then self.start_x, self.start_y = x, y
            elseif char == "G" then self.ghost_x, self.ghost_y = x, y
            elseif char == "?" then self.bonus_x, self.bonus_y = x, y end
            self.field[y * self.W + x + 1] = value
        end
    end
    -- Original wall connection mask (up/right/down/left).
    for y = 0, self.H - 1 do
        for x = 0, self.W - 1 do
            if self:at(x, y) < self.EMPTY then
                local mask = 0
                if y > 0 and self:at(x, y - 1) < self.EMPTY then mask = mask | 1 end
                if x + 1 < self.W and self:at(x + 1, y) < self.EMPTY then mask = mask | 2 end
                if y + 1 < self.H and self:at(x, y + 1) < self.EMPTY then mask = mask | 4 end
                if x > 0 and self:at(x - 1, y) < self.EMPTY then mask = mask | 8 end
                self.field[y * self.W + x + 1] = mask
            end
        end
    end
    -- Reverse graph BFS: shortest directed route to home, including tunnels.
    local reverse = {}
    for i = 1, self.W * self.H do reverse[i] = {} end
    for y = 0, self.H - 1 do
        for x = 0, self.W - 1 do
            if self:at(x, y) >= self.EMPTY then
                local a = actor(x * 12 + 6, y * 24 + 12)
                for dir = 1, 4 do
                    local nx, ny = self:next_cell(a, dir)
                    if nx then
                        local edges = reverse[ny * self.W + nx + 1]
                        edges[#edges + 1] = y * self.W + x + 1
                    end
                end
            end
        end
    end
    self.home_dist = {}
    for i = 1, self.W * self.H do self.home_dist[i] = 255 end
    local home = self.ghost_y * self.W + self.ghost_x + 1
    local queue = {home}
    self.home_dist[home] = 0
    local cursor = 1
    while cursor <= #queue do
        local cell = queue[cursor]
        cursor = cursor + 1
        for _, neighbor in ipairs(reverse[cell]) do
            if self.home_dist[neighbor] == 255 then
                self.home_dist[neighbor] = self.home_dist[cell] + 1
                queue[#queue + 1] = neighbor
            end
        end
    end
    self.bonus_timer = 400 + self:random() * 2
    self:restart_positions()
end
function Game.new(lives, level)
    local self = setmetatable({score = 0, lives = lives or 3, bonus = 0, bonus_time = 0, tick = 0}, Game)
    self:start(level or 0)
    return self
end
local function toward(from, to, more, less)
    return from < to and more or less
end
function Game:ghost_ai(index)
    local ghost = self.ghosts[index]
    local choices, available = {}, {}
    local back, best_dir, best = opposite(ghost.dir), 0, 255
    for dir = 1, 4 do
        if dir ~= back then
            local x, y = self:next_cell(ghost, dir)
            if x then
                choices[#choices + 1], available[dir] = dir, true
                if ghost.mode == self.EYES then
                    local distance = self.home_dist[y * self.W + x + 1]
                    if distance < best then best, best_dir = distance, dir end
                end
            end
        end
    end
    if #choices == 0 then return back end
    if #choices == 1 then return choices[1] end
    if ghost.mode == self.EYES and best_dir ~= 0 then return best_dir end
    local kind = index - 1
    if ghost.mode == self.EYES then kind = 3
    elseif self.bonus == self.AFRAID then kind = 4
    elseif self.bonus == self.BAD then kind = 0 end
    local px, py = self.pac.tile_x, self.pac.tile_y
    local tx, ty = px, py
    if kind == 1 then
        tx, ty = (px + self.ghosts[1].tile_x) // 2, (py + self.ghosts[1].tile_y) // 2
    elseif kind == 2 then
        if self.pac.dir == self.LEFT then tx = math.max(0, tx - 3)
        elseif self.pac.dir == self.RIGHT then tx = tx + 3
        elseif self.pac.dir == self.UP then ty = math.max(0, ty - 3)
        elseif self.pac.dir == self.DOWN then ty = ty + 3 end
    elseif kind == 3 then return choices[self:random_max(#choices) + 1] end
    local vertical, horizontal
    if kind == 4 then
        vertical = toward(py, ghost.tile_y, self.DOWN, self.UP)
        horizontal = toward(px, ghost.tile_x, self.RIGHT, self.LEFT)
    else
        vertical = toward(ghost.tile_y, ty, self.DOWN, self.UP)
        horizontal = toward(ghost.tile_x, tx, self.RIGHT, self.LEFT)
    end
    if kind == 0 and available[vertical] and available[horizontal] then
        return math.abs(ghost.tile_y - py) > math.abs(ghost.tile_x - px) and vertical or horizontal
    end
    if available[vertical] then return vertical end
    if available[horizontal] then return horizontal end
    return choices[self:random_max(#choices) + 1]
end
function Game:ghost_move(index)
    local ghost = self.ghosts[index]
    if centered(ghost) then
        if ghost.mode == self.EYES and ghost.tile_x == self.ghost_x and ghost.tile_y == self.ghost_y then
            ghost.mode = self.ACTIVE
        end
        ghost.dir = self:ghost_ai(index)
        if not self:can_turn(ghost, ghost.dir) then return end
    end
    self:move(ghost)
end
function Game:collide(index)
    local ghost = self.ghosts[index]
    if ghost.mode ~= self.ACTIVE or self.state ~= self.PLAY or self.events & 8 ~= 0 then return end
    if math.abs(ghost.x - self.pac.x) > 6 or math.abs(ghost.y - self.pac.y) > 12 then return end
    if self.bonus == self.AFRAID then
        ghost.mode, self.eaten_ghost, self.eaten_value = self.EYES, index, self.killed
        self.score = self.score + (5 << self.killed)
        self.killed = (self.killed + 1) % 4
        self.events = self.events | 8
    else self.state = self.CAUGHT end
end
function Game:pac_motion()
    local pac = self.pac
    if self:can_turn(pac, pac.pending) then pac.dir, pac.pending = pac.pending, 0 end
    if pac.dir ~= 0 and (self:can_turn(pac, pac.dir) or not centered(pac)) then self:move(pac) end
    if not centered(pac) then return end
    local index = pac.tile_y * self.W + pac.tile_x + 1
    local cell = self.field[index]
    if cell < self.PILL then return end
    self.field[index], self.eat_x, self.eat_y = self.EMPTY, pac.tile_x, pac.tile_y
    self.events = self.events | 1
    if cell == self.PILL then
        self.score, self.remaining, self.events = self.score + 1, self.remaining - 1, self.events | 2
        if self.remaining == 0 then self.state = self.CLEAR end
    else
        self.score, self.events = self.score + 5, self.events | 4
        self:switch_bonus(cell == self.POWER and self.AFRAID or self:random_max(7))
    end
end
-- controls: 1 up, 2 down, 4 left, 8 right, 16 turbo; fixed 50 Hz.
function Game:step(controls)
    self.events = 0
    if self.state ~= self.PLAY then return end
    self.tick = (self.tick + 1) % 256
    if self.wall_flash > 0 then self.wall_flash = self.wall_flash - 1 end
    if self.wall_flicker > 0 then self.wall_flicker = self.wall_flicker - 1 end
    if self.bonus_x ~= 0 then
        self.bonus_timer = self.bonus_timer - 1
        if self.bonus_timer == 0 then
            self.bonus_timer = 400 + self:random() * 2
            self.field[self.bonus_y * self.W + self.bonus_x + 1] = self.BONUS
            self.events = self.events | 16
        end
    end
    if self.bonus_time > 0 then
        self.bonus_time = self.bonus_time - 1
        if self.bonus_time == 0 then self:clear_bonus() end
    end
    local want = 0
    if controls & 1 ~= 0 then want = self.UP
    elseif controls & 2 ~= 0 then want = self.DOWN
    elseif controls & 4 ~= 0 then want = self.LEFT
    elseif controls & 8 ~= 0 then want = self.RIGHT end
    if want ~= 0 then
        self.pac.pending = self.bonus == self.INVERT and opposite(want) or want
    end
    self.fast = controls & 16 ~= 0 and self.turbo > 0
    if self.fast then
        self.turbo_use = self.turbo_use + 4
        if self.turbo_use >= 32 then self.turbo_use, self.turbo = 0, self.turbo - 1 end
    end
    for _ = 1, self.fast and 4 or 2 do
        self:pac_motion()
        if self.state ~= self.PLAY then return end
    end
    for index = 1, 4 do self:collide(index) end
    for index, ghost in ipairs(self.ghosts) do
        if ghost.mode == self.WAIT then
            ghost.wait = ghost.wait - 1
            if ghost.wait == 0 then ghost.mode = self.ACTIVE end
        else
            local boost = math.min(24, self.level & 0xf8)
            ghost.speed = ghost.speed + (ghost.mode == self.EYES and 32 or 16) + boost
            while ghost.speed >= 16 do
                ghost.speed = ghost.speed - 16
                self:ghost_move(index)
                self:collide(index)
            end
            if self.state ~= self.PLAY or self.events & 8 ~= 0 then return end
        end
    end
end
function Game:wall_mode()
    if self.wall_flicker > 0 then return self.wall_flicker & 1 end
    if self.bonus == self.HIDE then return 1 end
    if self.wall_flash > 0 then return self.wall_flash & 3 ~= 0 and 2 or 0 end
    return 0
end
return Game
