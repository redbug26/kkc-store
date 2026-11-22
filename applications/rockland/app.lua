local kkc = require("kkc")
local g = require("kkc-graphics")
local key = require("kkc-key")
local rand = require("kkc-rand")
local audio = require("kkc-audio")
local levels = require("levels")

local app = {}

local W = 96
local H = 32

local CAVE_W = 40
local CAVE_H = 22
local STEPMAX = 5
local TICK = 0.02
local LEVEL_INCREASE = 4
local GAME_OVER_DELAY = 1.5
local SPRITE_W = 4
local SPRITE_H = 3
local CAM_DEADZONE_X = 5
local CAM_DEADZONE_Y = 2
local PLAYER_ACTION_INTERVAL = 0.08
local MOVEMENT_USES_POLLING = key.HAS_RELEASE_EVENTS == true

local OBJ = {
    SPACE = 0,
    DIRT = 1,
    WALL = 2,
    MAGICALWALL = 3,
    EXIT = 4,
    EXIT_OPEN = 5,
    TITANIUMWALL = 7,
    FIREFLY_DOWN = 8,
    FIREFLY_LEFT = 9,
    FIREFLY_UP = 10,
    FIREFLY_RIGHT = 11,
    BOULDER = 16,
    BOULDER_FALLING = 18,
    DIAMOND = 20,
    DIAMOND_FALLING = 22,
    EXPLOSION_1 = 27,
    EXPLOSION_2 = 28,
    EXPLOSION_3 = 29,
    EXPLOSION_4 = 30,
    EXPLOSION_5 = 31,
    DIAMOND_STAGES_1 = 32,
    DIAMOND_STAGES_2 = 33,
    DIAMOND_STAGES_3 = 34,
    DIAMOND_STAGES_4 = 35,
    DIAMOND_STAGES_5 = 36,
    DIAMOND_STAGES_6 = 37,
    INBOX = 38,
    ROCKFORD = 56,
    AMOEBA = 58,
    BUTTERFLY_DOWN = 48,
    BUTTERFLY_LEFT = 49,
    BUTTERFLY_UP = 50,
    BUTTERFLY_RIGHT = 51,
    NOTSET = 0x7F,
}

-- C level blobs (level.c) encode Rockford spawn with legacy marker 0x25.
local LEGACY_INBOX = 0x25

local state = "menu"
local map = {}
local processed = {}

local current_level = 1
local intermission = false
local difficulty = 0
local cave_number = 1
local lives = 3
local extra_score = 500
local menu_level = 1
local menu_difficulty = 0

local rx, ry = 2, 2
local exit_x, exit_y = 2, 2

local step = 0
local tick_acc = 0
local sec_acc = 0
local cam_cx = 1 -- camera position in character coords (1-based)
local cam_cy = 1

local timer_s = 0
local required_diamonds = 0
local nb_diamonds = 0
local dpoints = 0
local dextra = 0
local score = 0

local message = ""
local dead_reason = ""
local hero_face = false
local hero_dir = "stand"
local level_clear_acc = 0
local level_clear_wait = 0
local level_clear_started = false
local game_over_timer = 0
local intro_acc = 0
local reveal_index = 1
local reveal_order = {}
local reveal_mask = {}
local motion_dx = {}
local motion_dy = {}
local anim_frame = 0
local sparkle_frame = 0
local sfx_cooldown = 0
local blink_ticks = 0
local player_action_cooldown = 0

local magic_willing_time = 0
local magic_time = 0
local magic_active = false

local amoeba_size = 0
local amoeba_enclosed = true
local amoeba_dead = OBJ.NOTSET
local amoeba_max = 200
local amoeba_slow = 0

local function new_grid(value)
    local out = {}
    for y = 1, CAVE_H do
        out[y] = {}
        for x = 1, CAVE_W do
            out[y][x] = value
        end
    end
    return out
end

local function new_grid_bool(value)
    local out = {}
    for y = 1, CAVE_H do
        out[y] = {}
        for x = 1, CAVE_W do
            out[y][x] = value
        end
    end
    return out
end

local function in_bounds(x, y)
    return x >= 1 and x <= CAVE_W and y >= 1 and y <= CAVE_H
end

local function cell(x, y)
    if not in_bounds(x, y) then
        return OBJ.TITANIUMWALL
    end
    return map[y][x]
end

local function set_cell(x, y, v)
    if in_bounds(x, y) then
        map[y][x] = v
    end
end

local function set_motion(x, y, dx, dy)
    if in_bounds(x, y) then
        motion_dx[y][x] = dx
        motion_dy[y][x] = dy
    end
end

local function clear_motion(x, y)
    if in_bounds(x, y) then
        motion_dx[y][x] = 0
        motion_dy[y][x] = 0
    end
end

local function maybe_beep()
    if sfx_cooldown <= 0 then
        audio.beep()
        sfx_cooldown = 3
    end
end

local function set_processed(x, y)
    if in_bounds(x, y) then
        processed[y][x] = true
    end
end

local function is_processed(x, y)
    if not in_bounds(x, y) then
        return true
    end
    return processed[y][x]
end

local function reset_processed()
    for y = 1, CAVE_H do
        for x = 1, CAVE_W do
            processed[y][x] = false
        end
    end
end

local function tick_motion_offsets()
    for y = 1, CAVE_H do
        for x = 1, CAVE_W do
            local dx = motion_dx[y][x]
            local dy = motion_dy[y][x]
            if dx > 0 then
                motion_dx[y][x] = dx - 1
            elseif dx < 0 then
                motion_dx[y][x] = dx + 1
            end
            if dy > 0 then
                motion_dy[y][x] = dy - 1
            elseif dy < 0 then
                motion_dy[y][x] = dy + 1
            end
        end
    end
end

local function is_butterfly(c)
    return c == OBJ.BUTTERFLY_DOWN or c == OBJ.BUTTERFLY_LEFT or c == OBJ.BUTTERFLY_UP or c == OBJ.BUTTERFLY_RIGHT
end

local function is_firefly(c)
    return c == OBJ.FIREFLY_DOWN or c == OBJ.FIREFLY_LEFT or c == OBJ.FIREFLY_UP or c == OBJ.FIREFLY_RIGHT
end

local function is_round(c)
    return c == OBJ.DIAMOND or c == OBJ.BOULDER or c == OBJ.WALL
end

local function is_magic(c)
    return c == OBJ.MAGICALWALL
end

local function is_explodable(c)
    return is_firefly(c) or is_butterfly(c) or c == OBJ.ROCKFORD
end

local function rotate_left(d)
    return (d + 3) % 4
end

local function rotate_right(d)
    return (d + 1) % 4
end

local function rotate_x(x, d)
    if d == 1 then return x - 1 end
    if d == 3 then return x + 1 end
    return x
end

local function rotate_y(y, d)
    if d == 0 then return y + 1 end
    if d == 2 then return y - 1 end
    return y
end

local function random_byte()
    return math.floor(rand.float() * 256) & 0xFF
end

local function random_direction()
    return math.floor(rand.float() * 4)
end

local function next_random(seed1, seed2)
    local temp1 = (seed1 & 0x0001) * 0x0080
    local temp2 = (seed2 >> 1) & 0x007F

    local result = seed2 + ((seed2 & 0x0001) * 0x0080)
    local carry = result > 0x00FF and 1 or 0
    result = result & 0x00FF

    result = result + carry + 0x13
    carry = result > 0x00FF and 1 or 0
    seed2 = result & 0x00FF

    result = seed1 + carry + temp1
    carry = result > 0x00FF and 1 or 0
    result = result & 0x00FF

    result = result + carry + temp2
    seed1 = result & 0x00FF

    return seed1, seed2
end

local function map_set0(col0, row0, object)
    local x = col0 + 1
    local y = row0 + 1
    if in_bounds(x, y) then
        map[y][x] = object
    end
end

local function place_object_line(object, row0, col0, length, direction)
    local ldx = { 0, 1, 1, 1, 0, -1, -1, -1 }
    local ldy = { -1, -1, 0, 1, 1, 1, 0, -1 }
    local dx = ldx[direction + 1] or 0
    local dy = ldy[direction + 1] or 0

    for i = 0, length - 1 do
        map_set0(col0 + i * dx, row0 + i * dy, object)
    end
end

local function place_object_rect(object, row0, col0, width, height)
    for i = 0, width - 1 do
        map_set0(col0 + i, row0, object)
        map_set0(col0 + i, row0 + height - 1, object)
    end
    for i = 0, height - 1 do
        map_set0(col0, row0 + i, object)
        map_set0(col0 + width - 1, row0 + i, object)
    end
end

local function place_object_filled_rect(object, row0, col0, width, height, fill)
    for yy = 0, height - 1 do
        for xx = 0, width - 1 do
            if yy == 0 or yy == height - 1 or xx == 0 or xx == width - 1 then
                map_set0(col0 + xx, row0 + yy, object)
            else
                map_set0(col0 + xx, row0 + yy, fill)
            end
        end
    end
end

local function decode_cave(level_data, diff)
    map = new_grid(OBJ.TITANIUMWALL)
    processed = new_grid(false)
    motion_dx = new_grid(0)
    motion_dy = new_grid(0)
    reveal_mask = new_grid_bool(false)
    reveal_order = {}

    local cave = level_data
    cave_number = cave[1] or 1

    local randomiser_seed = { cave[5], cave[6], cave[7], cave[8], cave[9] }
    local diamonds_needed = { cave[10], cave[11], cave[12], cave[13], cave[14] }
    local cave_time = { cave[15], cave[16], cave[17], cave[18], cave[19] }
    local random_object = { cave[25], cave[26], cave[27], cave[28] }
    local object_probability = { cave[29], cave[30], cave[31], cave[32] }

    local dindex = math.max(1, math.min(5, diff + 1))

    local seed1 = 0
    local seed2 = randomiser_seed[dindex] or 0

    for row = 1, CAVE_H - 1 do
        for col = 0, CAVE_W - 1 do
            local obj = OBJ.DIRT
            seed1, seed2 = next_random(seed1, seed2)
            for i = 1, 4 do
                if seed1 < (object_probability[i] or 0) then
                    obj = random_object[i] or OBJ.DIRT
                end
            end
            map_set0(col, row, obj)
        end
    end

    place_object_rect(OBJ.TITANIUMWALL, 0, 0, CAVE_W, CAVE_H)

    local i = 33
    local useless_top_border_height = 2

    while i <= #cave and cave[i] ~= 0xFF do
        local descriptor = cave[i]
        local object = descriptor & 0x3F
        local kind = (descriptor >> 6) & 0x03

        if kind == 0 then
            local col = cave[i + 1] or 0
            local row = (cave[i + 2] or 0) - useless_top_border_height

            if object == OBJ.INBOX or object == LEGACY_INBOX then
                rx = col + 1
                ry = row + 1
                object = OBJ.ROCKFORD
            end

            if object == OBJ.EXIT then
                exit_x = col + 1
                exit_y = row + 1
            end

            if object >= OBJ.FIREFLY_DOWN and object <= OBJ.FIREFLY_RIGHT then
                object = OBJ.FIREFLY_DOWN + ((object - OBJ.FIREFLY_DOWN + 1) % 4)
            end
            if object >= OBJ.BUTTERFLY_DOWN and object <= OBJ.BUTTERFLY_RIGHT then
                object = OBJ.BUTTERFLY_DOWN + ((object - OBJ.BUTTERFLY_DOWN + 1) % 4)
            end

            map_set0(col, row, object)
            i = i + 3
        elseif kind == 1 then
            local col = cave[i + 1] or 0
            local row = (cave[i + 2] or 0) - useless_top_border_height
            local length = cave[i + 3] or 0
            local direction = cave[i + 4] or 0
            place_object_line(object, row, col, length, direction)
            i = i + 5
        elseif kind == 2 then
            local col = cave[i + 1] or 0
            local row = (cave[i + 2] or 0) - useless_top_border_height
            local width = cave[i + 3] or 0
            local height = cave[i + 4] or 0
            local fill = cave[i + 5] or OBJ.SPACE
            place_object_filled_rect(object, row, col, width, height, fill)
            i = i + 6
        else
            local col = cave[i + 1] or 0
            local row = (cave[i + 2] or 0) - useless_top_border_height
            local width = cave[i + 3] or 0
            local height = cave[i + 4] or 0
            place_object_rect(object, row, col, width, height)
            i = i + 5
        end
    end

    timer_s = cave_time[dindex] or 150
    dpoints = cave[3] or 10
    dextra = cave[4] or dpoints
    required_diamonds = diamonds_needed[dindex] or 8
    magic_willing_time = cave[2] or 20

    nb_diamonds = 0
    magic_time = magic_willing_time * (50 / STEPMAX)
    magic_active = false
    amoeba_dead = OBJ.NOTSET
    amoeba_max = 200
    amoeba_slow = magic_willing_time * (50 / STEPMAX)
    blink_ticks = 0

    score = score or 0
    message = "Collect diamonds"
    dead_reason = ""
    state = "level_intro"
    intro_acc = 0
    reveal_index = 1
    hero_face = false
    hero_dir = "stand"
    player_action_cooldown = 0

    -- Reveal spawn area first so Rockford start position is immediately readable.
    local early = {}
    local used = {}
    for yy = ry - 1, ry + 1 do
        for xx = rx - 1, rx + 1 do
            if in_bounds(xx, yy) then
                local k = yy .. ":" .. xx
                if not used[k] then
                    used[k] = true
                    early[#early + 1] = { x = xx, y = yy }
                end
            end
        end
    end
    for y = 1, CAVE_H do
        for x = 1, CAVE_W do
            local k = y .. ":" .. x
            if not used[k] then
                reveal_order[#reveal_order + 1] = { x = x, y = y }
            end
        end
    end
    for i = #reveal_order, 2, -1 do
        local j = rand.int(1, i)
        reveal_order[i], reveal_order[j] = reveal_order[j], reveal_order[i]
    end
    for i = #early, 1, -1 do
        table.insert(reveal_order, 1, early[i])
    end
    cam_cx = (rx - 1) * SPRITE_W + 1
    cam_cy = (ry - 1) * SPRITE_H + 1
end

local function current_cave_index()
    if not intermission then
        return math.max(1, math.min(16, current_level))
    end
    local idx = math.floor((current_level - 1) / 4) + 16
    return math.max(17, math.min(20, idx))
end

local function cave_letter(level_index)
    local idx = math.max(1, math.min(16, level_index or 1))
    return string.char(string.byte("A") + (idx - 1))
end

local function start_current_cave()
    local idx = current_cave_index()
    decode_cave(levels[idx].data, difficulty)
end

local function advance_progression_after_win()
    if not intermission then
        current_level = current_level + 1
        if ((current_level - 1) % 4) == 0 then
            intermission = true
        end
    else
        intermission = false
        if current_level == 17 then
            current_level = 1
            difficulty = math.min(4, difficulty + 1)
        end
    end
end

local function begin_level_clear()
    state = "level_clear"
    level_clear_acc = 0
    level_clear_wait = 0
    level_clear_started = false
    message = "Level clear"
end

local function add_score(v)
    score = score + v
    while score >= extra_score do
        extra_score = extra_score + 500
        lives = lives + 1
        message = "Extra life"
        audio.beep()
    end
end

local function increase_diamond()
    nb_diamonds = nb_diamonds + 1
    if nb_diamonds > required_diamonds then
        add_score(dextra)
    else
        add_score(dpoints)
    end

    if nb_diamonds == required_diamonds then
        blink_ticks = 10
        set_cell(exit_x, exit_y, OBJ.EXIT_OPEN)
        message = "Exit opened"
        audio.beep()
    end
end

local function kill_player(reason)
    state = "dead"
    dead_reason = reason or "Exploded"
    message = dead_reason
    audio.beep()
end

local function return_to_menu_after_game_over()
    state = "menu"
    message = "Choose level and difficulty"
    dead_reason = ""
    current_level = menu_level
    intermission = false
    difficulty = menu_difficulty
    score = 0
    extra_score = 500
    lives = 3
    game_over_timer = 0
end

local function begin_game_over()
    state = "game_over"
    message = "Game over"
    dead_reason = ""
    game_over_timer = 0
    audio.beep()
end

local function restart_after_death()
    lives = lives - 1
    if lives <= 0 then
        begin_game_over()
        return
    end
    start_current_cave()
    message = "Life lost"
end

local function update_piece(x, y, obj)
    set_cell(x, y, obj)
    clear_motion(x, y)
    set_processed(x, y)
end

local function update_piece_dxy(x, y, obj, dx, dy)
    set_cell(x, y, obj)
    set_motion(x, y, dx, dy)
    set_processed(x, y)
end

local function explode(x, y)
    local center = cell(x, y)
    local object = is_butterfly(center) and OBJ.DIAMOND_STAGES_1 or OBJ.EXPLOSION_1

    for yy = y - 1, y + 1 do
        for xx = x - 1, x + 1 do
            local c = cell(xx, yy)
            if c == OBJ.ROCKFORD then
                update_piece(xx, yy, object)
                kill_player("Exploded")
            elseif c ~= OBJ.TITANIUMWALL then
                update_piece(xx, yy, object)
            end
        end
    end
end

local function do_magic(x, y, object)
    if magic_time > 0 then
        magic_active = true
        update_piece(x, y, OBJ.SPACE)
        if cell(x, y + 2) == OBJ.SPACE then
            update_piece(x, y + 2, object)
        end
    end
end

local function update_boulder(x, y)
    if cell(x, y + 1) == OBJ.SPACE then
        update_piece(x, y, OBJ.BOULDER_FALLING)
        maybe_beep()
    elseif is_round(cell(x, y + 1)) then
        if cell(x - 1, y) == OBJ.SPACE and cell(x - 1, y + 1) == OBJ.SPACE then
            update_piece(x - 1, y, OBJ.BOULDER_FALLING)
            update_piece(x, y, OBJ.SPACE)
        elseif cell(x + 1, y) == OBJ.SPACE and cell(x + 1, y + 1) == OBJ.SPACE then
            update_piece(x + 1, y, OBJ.BOULDER_FALLING)
            update_piece(x, y, OBJ.SPACE)
        end
    end
end

local function update_boulder_falling(x, y)
    local below = cell(x, y + 1)
    if below == OBJ.SPACE then
        update_piece_dxy(x, y + 1, OBJ.BOULDER_FALLING, 0, -1)
        update_piece(x, y, OBJ.SPACE)
    elseif is_explodable(below) then
        explode(x, y + 1)
    elseif is_magic(below) then
        do_magic(x, y, OBJ.DIAMOND)
    elseif is_round(below) and cell(x - 1, y) == OBJ.SPACE and cell(x - 1, y + 1) == OBJ.SPACE then
        update_piece_dxy(x - 1, y, OBJ.BOULDER_FALLING, 1, 0)
        update_piece(x, y, OBJ.SPACE)
    elseif is_round(below) and cell(x + 1, y) == OBJ.SPACE and cell(x + 1, y + 1) == OBJ.SPACE then
        update_piece_dxy(x + 1, y, OBJ.BOULDER_FALLING, -1, 0)
        update_piece(x, y, OBJ.SPACE)
    else
        maybe_beep()
        update_piece(x, y, OBJ.BOULDER)
    end
end

local function update_diamond(x, y)
    if cell(x, y + 1) == OBJ.SPACE then
        update_piece(x, y, OBJ.DIAMOND_FALLING)
    elseif is_round(cell(x, y + 1)) then
        if cell(x - 1, y) == OBJ.SPACE and cell(x - 1, y + 1) == OBJ.SPACE then
            update_piece(x - 1, y, OBJ.DIAMOND_FALLING)
            update_piece(x, y, OBJ.SPACE)
        elseif cell(x + 1, y) == OBJ.SPACE and cell(x + 1, y + 1) == OBJ.SPACE then
            update_piece(x + 1, y, OBJ.DIAMOND_FALLING)
            update_piece(x, y, OBJ.SPACE)
        end
    end
end

local function update_diamond_falling(x, y)
    local below = cell(x, y + 1)
    if below == OBJ.SPACE then
        update_piece_dxy(x, y + 1, OBJ.DIAMOND_FALLING, 0, -1)
        update_piece(x, y, OBJ.SPACE)
    elseif is_explodable(below) then
        explode(x, y + 1)
    elseif is_magic(below) then
        do_magic(x, y, OBJ.BOULDER)
    elseif is_round(below) and cell(x - 1, y) == OBJ.SPACE and cell(x - 1, y + 1) == OBJ.SPACE then
        update_piece_dxy(x - 1, y, OBJ.DIAMOND_FALLING, 1, 0)
        update_piece(x, y, OBJ.SPACE)
    elseif is_round(below) and cell(x + 1, y) == OBJ.SPACE and cell(x + 1, y + 1) == OBJ.SPACE then
        update_piece_dxy(x + 1, y, OBJ.DIAMOND_FALLING, -1, 0)
        update_piece(x, y, OBJ.SPACE)
    else
        update_piece(x, y, OBJ.DIAMOND)
    end
end

local function update_monster(x, y, base_obj, direction, turn_left_first)
    if cell(x, y + 1) == OBJ.ROCKFORD or cell(x, y - 1) == OBJ.ROCKFORD or cell(x + 1, y) == OBJ.ROCKFORD or cell(x - 1, y) == OBJ.ROCKFORD then
        explode(x, y)
        return
    end

    if cell(x, y + 1) == OBJ.AMOEBA or cell(x, y - 1) == OBJ.AMOEBA or cell(x + 1, y) == OBJ.AMOEBA or cell(x - 1, y) == OBJ.AMOEBA then
        explode(x, y)
        return
    end

    local turn = turn_left_first and rotate_left or rotate_right
    local turn2 = turn_left_first and rotate_right or rotate_left

    local new_dir = turn(direction)
    local nx = rotate_x(x, new_dir)
    local ny = rotate_y(y, new_dir)

    if cell(nx, ny) == OBJ.SPACE then
        update_piece(nx, ny, base_obj + new_dir)
        update_piece(x, y, OBJ.SPACE)
        return
    end

    nx = rotate_x(x, direction)
    ny = rotate_y(y, direction)
    if cell(nx, ny) == OBJ.SPACE then
        update_piece(nx, ny, base_obj + direction)
        update_piece(x, y, OBJ.SPACE)
        return
    end

    update_piece(x, y, base_obj + turn2(direction))
end

local function update_amoeba(x, y)
    amoeba_size = amoeba_size + 1

    if amoeba_dead ~= OBJ.NOTSET then
        update_piece(x, y, amoeba_dead)
        return
    end

    if cell(x, y + 1) == OBJ.SPACE or cell(x, y + 1) == OBJ.DIRT
        or cell(x + 1, y) == OBJ.SPACE or cell(x + 1, y) == OBJ.DIRT
        or cell(x, y - 1) == OBJ.SPACE or cell(x, y - 1) == OBJ.DIRT
        or cell(x - 1, y) == OBJ.SPACE or cell(x - 1, y) == OBJ.DIRT then
        amoeba_enclosed = false

        local chance_mask = amoeba_slow ~= 0 and 31 or 3
        if (random_byte() & chance_mask) == 0 then
            local d = random_direction()
            local xx = rotate_x(x, d)
            local yy = rotate_y(y, d)
            local t = cell(xx, yy)
            if t == OBJ.SPACE or t == OBJ.DIRT then
                update_piece(xx, yy, OBJ.AMOEBA)
            end
        end
    end
end

local function update_object(x, y)
    local c = cell(x, y)
    if c == OBJ.BOULDER then
        update_boulder(x, y)
    elseif c == OBJ.BOULDER_FALLING then
        update_boulder_falling(x, y)
    elseif c == OBJ.DIAMOND then
        update_diamond(x, y)
    elseif c == OBJ.DIAMOND_FALLING then
        update_diamond_falling(x, y)
    elseif c == OBJ.AMOEBA then
        update_amoeba(x, y)
    elseif c >= OBJ.BUTTERFLY_DOWN and c <= OBJ.BUTTERFLY_RIGHT then
        update_monster(x, y, OBJ.BUTTERFLY_DOWN, c - OBJ.BUTTERFLY_DOWN, false)
    elseif c >= OBJ.FIREFLY_DOWN and c <= OBJ.FIREFLY_RIGHT then
        update_monster(x, y, OBJ.FIREFLY_DOWN, c - OBJ.FIREFLY_DOWN, true)
    elseif c == OBJ.EXPLOSION_1 then
        update_piece(x, y, OBJ.EXPLOSION_2)
    elseif c == OBJ.EXPLOSION_2 then
        update_piece(x, y, OBJ.EXPLOSION_3)
    elseif c == OBJ.EXPLOSION_3 then
        update_piece(x, y, OBJ.EXPLOSION_4)
    elseif c == OBJ.EXPLOSION_4 then
        update_piece(x, y, OBJ.EXPLOSION_5)
    elseif c == OBJ.EXPLOSION_5 then
        update_piece(x, y, OBJ.SPACE)
    elseif c == OBJ.DIAMOND_STAGES_1 then
        update_piece(x, y, OBJ.DIAMOND_STAGES_2)
    elseif c == OBJ.DIAMOND_STAGES_2 then
        update_piece(x, y, OBJ.DIAMOND_STAGES_3)
    elseif c == OBJ.DIAMOND_STAGES_3 then
        update_piece(x, y, OBJ.DIAMOND_STAGES_4)
    elseif c == OBJ.DIAMOND_STAGES_4 then
        update_piece(x, y, OBJ.DIAMOND_STAGES_5)
    elseif c == OBJ.DIAMOND_STAGES_5 then
        update_piece(x, y, OBJ.DIAMOND_STAGES_6)
    elseif c == OBJ.DIAMOND_STAGES_6 then
        update_piece(x, y, OBJ.DIAMOND)
    end
end

local function update_world()
    reset_processed()
    amoeba_size = 0
    amoeba_enclosed = true

    for y = 2, CAVE_H - 1 do
        for x = 2, CAVE_W - 1 do
            if not is_processed(x, y) then
                update_object(x, y)
            end
        end
    end

    if amoeba_dead == OBJ.NOTSET then
        if amoeba_enclosed then
            amoeba_dead = OBJ.DIAMOND
        elseif amoeba_size > amoeba_max then
            amoeba_dead = OBJ.BOULDER
        elseif amoeba_slow > 0 then
            amoeba_slow = amoeba_slow - 1
        end
    end

    if magic_active then
        if magic_time > 0 then
            magic_time = magic_time - 1
        else
            magic_active = false
        end
    end
end

local function could_move(x, y)
    local c = cell(x, y)
    return c == OBJ.DIAMOND or c == OBJ.SPACE or c == OBJ.DIRT or c == OBJ.EXIT_OPEN
end

local function move_player(dx, dy)
    if state ~= "playing" then
        return
    end

    local tx, ty = rx + dx, ry + dy
    local target = cell(tx, ty)

    if dx < 0 then
        hero_dir = "left"
    elseif dx > 0 then
        hero_dir = "right"
    elseif dy < 0 then
        hero_dir = "up"
    elseif dy > 0 then
        hero_dir = "down"
    end

    if target == OBJ.EXIT_OPEN then
        begin_level_clear()
        return true
    end

    if target == OBJ.BOULDER and dy == 0 and cell(tx + dx, ty) == OBJ.SPACE then
        if (rand.int(0, 255) & 7) == 1 then
            update_piece_dxy(tx + dx, ty, OBJ.BOULDER, -1 * dx, 0)
            update_piece(tx, ty, OBJ.SPACE)
            maybe_beep()
        else
            return false
        end
    elseif not could_move(tx, ty) then
        return false
    end

    set_cell(rx, ry, OBJ.SPACE)

    if target == OBJ.DIAMOND then
        increase_diamond()
    elseif target == OBJ.DIRT then
        add_score(1)
    end

    rx, ry = tx, ty
    set_cell(rx, ry, OBJ.ROCKFORD)
    set_motion(rx, ry, -1 * dx, -1 * dy)
    return true
end

local function dig_only(dx, dy)
    if state ~= "playing" then
        return
    end

    local tx, ty = rx + dx, ry + dy
    local target = cell(tx, ty)

    if dx < 0 then
        hero_dir = "left"
    elseif dx > 0 then
        hero_dir = "right"
    elseif dy < 0 then
        hero_dir = "up"
    elseif dy > 0 then
        hero_dir = "down"
    end

    if target == OBJ.DIRT then
        set_cell(tx, ty, OBJ.SPACE)
        add_score(1)
        message = "Dig"
        return true
    elseif target == OBJ.DIAMOND then
        set_cell(tx, ty, OBJ.SPACE)
        increase_diamond()
        message = "Grab"
        return true
    end
    return false
end

local function tile_symbol(c)
    if c == OBJ.SPACE then return " " end
    if c == OBJ.DIRT then return "·" end
    if c == OBJ.WALL then return "▒" end
    if c == OBJ.TITANIUMWALL then return "█" end
    if c == OBJ.MAGICALWALL then return "≋" end
    if c == OBJ.EXIT then return "▣" end
    if c == OBJ.EXIT_OPEN then return "▢" end
    if c == OBJ.BOULDER or c == OBJ.BOULDER_FALLING then return "●" end
    if c == OBJ.DIAMOND or c == OBJ.DIAMOND_FALLING then return "◆" end
    if c == OBJ.AMOEBA then return "◉" end
    if c == OBJ.ROCKFORD then return hero_face and "☺" or "☻" end
    if is_firefly(c) then return "✶" end
    if is_butterfly(c) then return "✷" end
    if c >= OBJ.EXPLOSION_1 and c <= OBJ.EXPLOSION_5 then return "✹" end
    if c >= OBJ.DIAMOND_STAGES_1 and c <= OBJ.DIAMOND_STAGES_6 then return "◇" end
    return "?"
end

local function tile_color(c)
    if c == OBJ.DIRT then return 0x8D6E63 end
    if c == OBJ.WALL then return 0x78909C end
    if c == OBJ.TITANIUMWALL then return 0x90CAF9 end
    if c == OBJ.MAGICALWALL then return 0x7E57C2 end
    if c == OBJ.EXIT then return 0xEF5350 end
    if c == OBJ.EXIT_OPEN then return 0x66BB6A end
    if c == OBJ.BOULDER or c == OBJ.BOULDER_FALLING then return 0x8D6E63 end
    if c == OBJ.DIAMOND or c == OBJ.DIAMOND_FALLING then return 0xFFFFFF end
    if c == OBJ.AMOEBA then return 0xAED581 end
    if c == OBJ.ROCKFORD then return 0xFDD835 end
    if is_firefly(c) then return 0xFFA726 end
    if is_butterfly(c) then return 0xFFEE58 end
    if c >= OBJ.EXPLOSION_1 and c <= OBJ.EXPLOSION_5 then return 0xFF7043 end
    if c >= OBJ.DIAMOND_STAGES_1 and c <= OBJ.DIAMOND_STAGES_6 then return 0x80DEEA end
    return 0xCFD8DC
end

local function tile_bg(c)
    if c == OBJ.ROCKFORD then return 0x0D1B4D end
    return 0x000000
end

local function anim_phase(c, x, y)
    if c == OBJ.DIAMOND or c == OBJ.DIAMOND_FALLING then
        return (anim_frame + x + y) % 4
    end
    if is_firefly(c) or is_butterfly(c) then
        return (anim_frame + x + y) % 4
    end
    if c == OBJ.AMOEBA or c == OBJ.MAGICALWALL then
        return anim_frame % 4
    end
    return anim_frame % 4
end

local function diamond_sparkles(x, y)
    return ((x * 17 + y * 31 + sparkle_frame) % 97) == 0
end

local function tile_sprite(c, x, y)
    local hero = hero_face and "☺" or "☻"
    x = x or 1
    y = y or 1
    local p = anim_phase(c, x, y)

    if c == OBJ.SPACE then return { "    ", "    ", "    " } end
    if c == OBJ.DIRT then
        return { " .. ", "....", " .. " }
    end
    if c == OBJ.WALL then return { "####", "#::#", "####" } end
    if c == OBJ.TITANIUMWALL then return { "====", "=##=", "====" } end
    if c == OBJ.MAGICALWALL then
        if not magic_active then return { "++++", "+::+", "++++" } end
        if p == 0 then return { "~~~~", "=~~=", "~~~~" } end
        if p == 1 then return { "=~~=", "~~~~", "=~~=" } end
        if p == 2 then return { "~==~", "=++=", "~==~" } end
        return { "~=~ ", "=++=", " ~=~" }
    end
    if c == OBJ.EXIT then return { "/==\\", "|XX|", "\\==/" } end
    if c == OBJ.EXIT_OPEN then return { "/  \\", "|  |", "\\__/" } end
    if c == OBJ.BOULDER then return { " __ ", "/@@\\", "\\@@/" } end
    if c == OBJ.BOULDER_FALLING then return { " __ ", "/vv\\", "\\__/" } end
    if c == OBJ.DIAMOND then
        if diamond_sparkles(x, y) then
            return { " /\\ ", "/+*\\", "\\__/" }
        end
        return { " /\\ ", "/**\\", "\\__/" }
    end
    if c == OBJ.DIAMOND_FALLING then
        if diamond_sparkles(x, y) then
            return { " vv ", "<+*>", "\\__/" }
        end
        return { " vv ", "<**>", "\\__/" }
    end
    if c == OBJ.AMOEBA then
        if p == 0 then return { "(oo)", "oOOo", "(oo)" } end
        if p == 1 then return { "(oO)", "OOoO", "(Oo)" } end
        if p == 2 then return { "(OO)", "oOOo", "(OO)" } end
        return { "(Oo)", "OOOO", "(oO)" }
    end
    if c == OBJ.ROCKFORD then
        if hero_dir == "stand" then return { "/--\\", "| " .. hero .. "|", "\\--/" } end
        if hero_dir == "left" then return { "/--\\", "<" .. hero .. " |", "\\--/" } end
        if hero_dir == "up" then return { "/^^\\", "|" .. hero .. " |", "\\--/" } end
        if hero_dir == "down" then return { "/--\\", "|" .. hero .. " |", "\\vv/" } end
        return { "/--\\", "| " .. hero .. ">", "\\--/" }
    end
    if is_firefly(c) then
        local d = c - OBJ.FIREFLY_DOWN
        if d == 0 then
            if p % 2 == 0 then return { " \\|/", "-vv-", " /|\\" } end
            return { " /|\\", "-vv-", " \\|/" }
        elseif d == 1 then
            if p % 2 == 0 then return { " -- ", "<FF-", " -- " } end
            return { "-\\- ", "<FF-", "-/--" }
        elseif d == 2 then
            if p % 2 == 0 then return { " /|\\", "-^^-", " \\|/" } end
            return { " \\|/", "-^^-", " /|\\" }
        end
        if p % 2 == 0 then return { " -- ", "-FF>", " -- " } end
        return { "--\\ ", "-FF>", "---/" }
    end
    if is_butterfly(c) then
        local d = c - OBJ.BUTTERFLY_DOWN
        if d == 0 then
            if p % 2 == 0 then return { "\\/\\/", " vv ", "/\\/\\" } end
            return { " /\\ ", " vv ", " \\/ " }
        elseif d == 1 then
            if p % 2 == 0 then return { "<\\< ", "<BB-", "</< " } end
            return { "</< ", "<BB-", "<\\< " }
        elseif d == 2 then
            if p % 2 == 0 then return { "/\\/\\", " ^^ ", "\\/\\/" } end
            return { " \\/ ", " ^^ ", " /\\ " }
        end
        if p % 2 == 0 then return { " >\\ ", "-BB>", " >/-" } end
        return { " >/--", "-BB>", " >\\ " }
    end
    if c >= OBJ.EXPLOSION_1 and c <= OBJ.EXPLOSION_5 then
        if p % 2 == 0 then return { "\\|//", "-**-", "//|\\" } end
        return { " ** ", "****", " ** " }
    end
    if c >= OBJ.DIAMOND_STAGES_1 and c <= OBJ.DIAMOND_STAGES_6 then
        if p % 2 == 0 then return { " .. ", ".**.", " .. " } end
        return { " .. ", " ** ", " .. " }
    end
    local s = tile_symbol(c)
    return { " " .. s .. "  ", " " .. s .. "  ", " " .. s .. "  " }
end

-- Camera position is in character coords (1-based).
-- Dead zones are in chars: CAM_DEADZONE_* tiles × SPRITE size.
local function update_camera(view_chars_w, view_chars_h)
    local map_chars_w = CAVE_W * SPRITE_W
    local map_chars_h = CAVE_H * SPRITE_H
    local min_cx = 1
    local min_cy = 1
    local max_cx = math.max(1, map_chars_w - view_chars_w + 1)
    local max_cy = math.max(1, map_chars_h - view_chars_h + 1)

    cam_cx = math.max(min_cx, math.min(max_cx, cam_cx))
    cam_cy = math.max(min_cy, math.min(max_cy, cam_cy))

    local pmx = 0
    local pmy = 0
    if state == "playing" and in_bounds(rx, ry) then
        pmx = math.max(-1, math.min(1, motion_dx[ry][rx]))
        pmy = math.max(-1, math.min(1, motion_dy[ry][rx]))
    end
    local player_cx   = (rx - 1) * SPRITE_W + 1 + pmx
    local player_cy   = (ry - 1) * SPRITE_H + 1 + pmy

    local dzx         = CAM_DEADZONE_X * SPRITE_W
    local dzy         = CAM_DEADZONE_Y * SPRITE_H

    local left_bound  = cam_cx + dzx
    local right_bound = cam_cx + view_chars_w - dzx - 1
    local top_bound   = cam_cy + dzy
    local bot_bound   = cam_cy + view_chars_h - dzy - 1

    -- Calculate target camera position based on dead zone
    local target_cx   = cam_cx
    local target_cy   = cam_cy
    if player_cx < left_bound then
        target_cx = player_cx - dzx
    elseif player_cx > right_bound then
        target_cx = player_cx - (view_chars_w - dzx - 1)
    end
    if player_cy < top_bound then
        target_cy = player_cy - dzy
    elseif player_cy > bot_bound then
        target_cy = player_cy - (view_chars_h - dzy - 1)
    end

    -- Ease camera toward target (max 1 char per frame) for smooth scrolling
    if target_cx > cam_cx then
        cam_cx = math.min(target_cx, cam_cx + 1)
    elseif target_cx < cam_cx then
        cam_cx = math.max(target_cx, cam_cx - 1)
    end
    if target_cy > cam_cy then
        cam_cy = math.min(target_cy, cam_cy + 1)
    elseif target_cy < cam_cy then
        cam_cy = math.max(target_cy, cam_cy - 1)
    end

    cam_cx = math.max(min_cx, math.min(max_cx, cam_cx))
    cam_cy = math.max(min_cy, math.min(max_cy, cam_cy))
end

-- Draw a sprite with per-row vertical clipping to stay within [clip_top, clip_bot].
-- Horizontal spillover is handled by the graphics buffer edge clipping and the
-- border-last overdraw in draw_map.
local function draw_sprite_in_box(px, py, sprite, clip_top, clip_bot, ox, oy)
    local x = px + ox
    local y = py + oy
    for row = 0, SPRITE_H - 1 do
        local sy = y + row
        if sy >= clip_top and sy <= clip_bot then
            g.text(x, sy, sprite[row + 1])
        end
    end
end

local function draw_hud()
    g.color(0xFFF59D, 0x000000)
    g.text(2, 1, "⛏ ROCKLAND")
    g.color(0xCFD8DC, 0x000000)
    g.text(15, 1, string.format("Cave %02d", cave_number))
    g.text(26, 1, string.format("Lv %02d", current_level))
    g.text(34, 1, string.format("D%d", difficulty + 1))
    g.text(39, 1, string.format("♥ %d", lives))
    g.text(46, 1, string.format("◆ %d/%d", nb_diamonds, required_diamonds))
    g.text(62, 1, string.format("⏱ %03d", timer_s))
    g.text(74, 1, string.format("★ %d", score))

    g.color(0xB0BEC5, 0x000000)
    local mode = intermission and "Intermission" or "Normal"
    g.text(2, 2, mode .. "  " .. message)
    if magic_active then
        g.color(0xCE93D8, 0x000000)
        g.text(56, 2, string.format("Magic %d", math.floor(magic_time)))
    end
end

local function draw_map()
    local top = 3
    local avail_w = math.max(6, W - 2)
    local avail_h = math.max(6, H - top - 1)

    local view_tiles_w = math.max(5, math.min(CAVE_W, math.floor(avail_w / SPRITE_W)))
    local view_tiles_h = math.max(4, math.min(CAVE_H, math.floor(avail_h / SPRITE_H)))

    local view_chars_w = view_tiles_w * SPRITE_W
    local view_chars_h = view_tiles_h * SPRITE_H

    local left = math.max(1, math.floor((W - (view_chars_w + 2)) / 2) + 1)
    local field_blink = blink_ticks > 0 and (blink_ticks & 2) ~= 0

    update_camera(view_chars_w, view_chars_h)

    -- Sub-tile character offset into the first visible tile (0..SPRITE-1)
    local sub_x = (cam_cx - 1) % SPRITE_W
    local sub_y = (cam_cy - 1) % SPRITE_H

    -- First tile to draw in map coordinates (1-based)
    local first_tx = math.floor((cam_cx - 1) / SPRITE_W) + 1
    local first_ty = math.floor((cam_cy - 1) / SPRITE_H) + 1

    -- Extra tile column/row when sub-offset > 0 (partial tile at left/top edge)
    local draw_cols = view_tiles_w + (sub_x > 0 and 1 or 0)
    local draw_rows = view_tiles_h + (sub_y > 0 and 1 or 0)

    -- Vertical clip bounds: tile rows must stay within the box interior
    local clip_top = top + 1
    local clip_bot = top + view_chars_h

    -- Pre-clear interior so no ghost chars appear between frames
    g.color(0x000000, 0x000000)
    g["box"](left + 1, clip_top, view_chars_w, view_chars_h, " ")

    -- Draw tiles; horizontal spillover is masked by the border drawn below
    for vy = 1, draw_rows do
        for vx = 1, draw_cols do
            local mx = first_tx + vx - 1
            local my = first_ty + vy - 1
            local c = cell(mx, my)
            if state == "level_intro" and in_bounds(mx, my) and not reveal_mask[my][mx] then
                c = OBJ.TITANIUMWALL
            end
            local sprite = tile_sprite(c, mx, my)
            local px = left + 1 + (vx - 1) * SPRITE_W - sub_x
            local py = top + 1 + (vy - 1) * SPRITE_H - sub_y
            local bg = field_blink and 0xE3F2FD or tile_bg(c)
            local fg = field_blink and 0x000000 or tile_color(c)
            if not field_blink and (c == OBJ.DIAMOND or c == OBJ.DIAMOND_FALLING) and diamond_sparkles(mx, my) then
                fg = 0xFFFFFF
            end
            g.color(fg, bg)
            local ox = 0
            local oy = 0
            if state == "playing" and in_bounds(mx, my) then
                ox = math.max(-1, math.min(1, motion_dx[my][mx]))
                oy = math.max(-1, math.min(1, motion_dy[my][mx]))
            end
            draw_sprite_in_box(px, py, sprite, clip_top, clip_bot, ox, oy)
        end
    end

    -- Clear horizontal spillover outside the box to hide partial tiles leaking there
    local spill = SPRITE_W + 1
    g.color(0x000000, 0x000000)
    for row = clip_top, clip_bot do
        for col = math.max(1, left - spill + 1), left - 1 do
            g.put(col, row, " ")
        end
        for col = left + view_chars_w + 2, math.min(W, left + view_chars_w + spill) do
            g.put(col, row, " ")
        end
    end

    -- Draw border LAST so it overwrites tile chars that bled onto border columns
    if field_blink then
        g.color(0x000000, 0xE3F2FD)
    else
        g.color(0xECEFF1, 0x000000)
    end
    g.text(left, top, "┌" .. string.rep("─", view_chars_w) .. "┐")
    for row = 1, view_chars_h do
        g.text(left, top + row, "│")
        g.text(left + view_chars_w + 1, top + row, "│")
    end
    g.text(left, top + view_chars_h + 1, "└" .. string.rep("─", view_chars_w) .. "┘")

    if state == "dead" then
        local msg = lives <= 1 and "GAME OVER" or "You loose"
        local hint = dead_reason ~= "" and dead_reason or "Press R"
        local cx = left + 1 + math.floor((view_chars_w - #msg) / 2)
        local cy = top + 1 + math.floor(view_chars_h / 2)
        g.color(0xEF9A9A, 0x000000)
        g.text(cx, cy, msg)
        g.color(0xCFD8DC, 0x000000)
        g.text(left + 1 + math.floor((view_chars_w - #hint) / 2), cy + 1, hint)
    end
end

function app.init(ctx)
    if ctx then
        W = ctx.width or W
        H = ctx.height or H
    end
    rand.seed(os.time())
    current_level = 1
    intermission = false
    difficulty = 0
    score = 0
    extra_score = 500
    lives = 3
    menu_level = 1
    menu_difficulty = 0
    state = "menu"
    message = "Choose level and difficulty"
    dead_reason = ""
    hero_dir = "stand"
    cam_cx = 1
    cam_cy = 1
    player_action_cooldown = 0
    game_over_timer = 0
    map = new_grid(OBJ.TITANIUMWALL)
    processed = new_grid(false)
end

function app.resize(w, h)
    W = w
    H = h
end

function app.shortcuts()
    if state == "menu" then
        return { "←/→:Level", "↑/↓:Difficulty", "Enter:Start", "Esc:Quit" }
    end
    if state == "playing" then
        return { "Arrows:Move", "HJKL:Dig", "R:Restart Cave", "N:Next Cave", "Esc:Lose Life" }
    end
    if state == "level_intro" then
        return { "Preparing cave..." }
    end
    if state == "level_clear" then
        return { "Converting time bonus..." }
    end
    if state == "game_over" then
        return { "Game over" }
    end
    if state == "dead" then
        return { "Enter:Continue", "R:Retry", "N:Skip", "Esc:Quit" }
    end
    return { "R:Replay", "Esc:Quit" }
end

function app.update(dt)
    if state == "game_over" then
        game_over_timer = game_over_timer + dt
        if game_over_timer >= GAME_OVER_DELAY then
            return_to_menu_after_game_over()
        end
        return
    end

    if state == "level_intro" then
        intro_acc = intro_acc + dt
        while intro_acc >= 0.01 and reveal_index <= #reveal_order do
            intro_acc = intro_acc - 0.01
            for _ = 1, 10 do
                if reveal_index > #reveal_order then
                    break
                end
                local p = reveal_order[reveal_index]
                reveal_mask[p.y][p.x] = true
                reveal_index = reveal_index + 1
            end
        end
        if reveal_index > #reveal_order then
            state = "playing"
            message = "Collect diamonds"
        end
        return
    end

    if state == "level_clear" then
        if not level_clear_started then
            level_clear_started = true
            audio.beep()
        end

        level_clear_acc = level_clear_acc + dt
        while timer_s > 0 and level_clear_acc >= 0.02 do
            level_clear_acc = level_clear_acc - 0.02
            timer_s = timer_s - 1
            add_score(1)
        end

        if timer_s <= 0 then
            level_clear_wait = level_clear_wait + dt
            if level_clear_wait >= 0.30 then
                advance_progression_after_win()
                start_current_cave()
            end
        end
        return
    end

    if state ~= "playing" then
        return
    end

    tick_acc = tick_acc + dt
    sec_acc = sec_acc + dt
    if player_action_cooldown > 0 then
        player_action_cooldown = math.max(0, player_action_cooldown - dt)
    end

    if MOVEMENT_USES_POLLING and player_action_cooldown <= 0 then
        local acted = false
        if key.is_down(key.LEFT) then
            acted = move_player(-1, 0)
        elseif key.is_down(key.RIGHT) then
            acted = move_player(1, 0)
        elseif key.is_down(key.UP) then
            acted = move_player(0, -1)
        elseif key.is_down(key.DOWN) then
            acted = move_player(0, 1)
        end
        if acted then
            player_action_cooldown = PLAYER_ACTION_INTERVAL
        end
    end

    if sec_acc >= 1.0 then
        sec_acc = sec_acc - 1.0
        if timer_s > 0 then
            timer_s = timer_s - 1
            if timer_s < 10 then
                audio.beep()
            end
        else
            kill_player("Out of time")
            return
        end
    end

    while tick_acc >= TICK do
        tick_acc = tick_acc - TICK
        tick_motion_offsets()
        if sfx_cooldown > 0 then
            sfx_cooldown = sfx_cooldown - 1
        end
        if blink_ticks > 0 then
            blink_ticks = blink_ticks - 1
        end
        if step == 3 then
            anim_frame = (anim_frame + 1) % 4
            hero_face = not hero_face
        end
        if step == 3 then
            sparkle_frame = (sparkle_frame + 1) % 97
        end
        if step == 1 then
            update_world()
            if state ~= "playing" then
                return
            end
        elseif step == 2 then
            reset_processed()
        end
        step = (step + 1) % STEPMAX
    end
end

-- keypressed: fires on initial press and on terminal repeat.
-- Keep directional movement here so both Terminal.app and Ghostty behave consistently.
function app.keypressed(k)
    if MOVEMENT_USES_POLLING or state ~= "playing" or player_action_cooldown > 0 then
        return
    end

    local acted = false
    if k == key.LEFT then
        acted = move_player(-1, 0)
    elseif k == key.RIGHT then
        acted = move_player(1, 0)
    elseif k == key.UP then
        acted = move_player(0, -1)
    elseif k == key.DOWN then
        acted = move_player(0, 1)
    end

    if acted then
        player_action_cooldown = PLAYER_ACTION_INTERVAL
    end
end

-- keydown: fires exactly once per physical key press (new press, not OS repeat).
-- Used for instantaneous discrete actions: menu nav, restart, dig-in-place.
function app.keydown(k)
    if k == key.ESC then
        if state == "playing" then
            restart_after_death()
            return
        end
        if state == "menu" then
            kkc.quit()
        end
        return
    end

    if state == "menu" then
        if k == key.LEFT then
            menu_level = math.max(1, menu_level - LEVEL_INCREASE)
            current_level = menu_level
            difficulty = menu_difficulty
            message = string.format("Start cave %s", cave_letter(menu_level))
            return
        elseif k == key.RIGHT then
            menu_level = math.min(13, menu_level + LEVEL_INCREASE)
            current_level = menu_level
            difficulty = menu_difficulty
            message = string.format("Start cave %s", cave_letter(menu_level))
            return
        elseif k == key.UP then
            menu_difficulty = math.min(2, menu_difficulty + 1)
            current_level = menu_level
            difficulty = menu_difficulty
            message = string.format("Difficulty %d", menu_difficulty + 1)
            return
        elseif k == key.DOWN then
            menu_difficulty = math.max(0, menu_difficulty - 1)
            current_level = menu_level
            difficulty = menu_difficulty
            message = string.format("Difficulty %d", menu_difficulty + 1)
            return
        end
        if k == key.ENTER then
            current_level = menu_level
            difficulty = menu_difficulty
            intermission = false
            score = 0
            extra_score = 500
            lives = 3
            player_action_cooldown = 0
            start_current_cave()
        end
        return
    end

    if state == "level_intro" then
        return
    end

    if state == "level_clear" then
        return
    end

    if state == "dead" then
        if k == key.ENTER or k == key.SPACE then
            restart_after_death()
        elseif k == "char:r" or k == "char:R" then
            start_current_cave()
        elseif k == "char:n" or k == "char:N" then
            advance_progression_after_win()
            start_current_cave()
        end
        return
    end

    if state == "game_over" then
        if k == key.ENTER or k == key.SPACE then
            return_to_menu_after_game_over()
        end
        return
    end

    if k == "char:r" or k == "char:R" then
        start_current_cave()
        return
    end

    if k == "char:n" or k == "char:N" then
        advance_progression_after_win()
        start_current_cave()
        return
    end

    if state ~= "playing" then
        return
    end

    -- Dig-in-place actions (vi-style keys): discrete press, one action per keydown.
    if player_action_cooldown <= 0 then
        local acted = false
        if k == "char:h" or k == "char:H" then
            acted = dig_only(-1, 0)
        elseif k == "char:l" or k == "char:L" then
            acted = dig_only(1, 0)
        elseif k == "char:k" or k == "char:K" then
            acted = dig_only(0, -1)
        elseif k == "char:j" or k == "char:J" then
            acted = dig_only(0, 1)
        end
        if acted then
            player_action_cooldown = PLAYER_ACTION_INTERVAL
        end
    end
end

function app.draw()
    local tw, th = g.size()
    if tw then W = tw end
    if th then H = th end

    g.clear(" ")
    g.reset()

    if state == "menu" then
        local function menu_line(left, right)
            left = left or ""
            right = right or ""
            local gap = math.max(1, 78 - #left - #right)
            return left .. string.rep(" ", gap) .. right
        end

        local cave_name = string.format("CAVE %s", cave_letter(menu_level))


        local lines = {
            "                                                                              ",
            "                                                                              ",
            "                     ██████╗  ██████╗  ██████╗██╗  ██╗                       ",
            "                     ██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝                       ",
            "                     ██████╔╝██║   ██║██║     █████╔╝                        ",
            "                     ██╔══██╗██║   ██║██║     ██╔═██╗                        ",
            "                     ██║  ██║╚██████╔╝╚██████╗██║  ██╗                       ",
            "                     ╚═╝  ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝                       ",
            "                                                                              ",
            "                     ██╗      █████╗ ███╗   ██╗██████╗                      ",
            "                     ██║     ██╔══██╗████╗  ██║██╔══██╗                     ",
            "                     ██║     ███████║██╔██╗ ██║██║  ██║                     ",
            "                     ██║     ██╔══██║██║╚██╗██║██║  ██║                     ",
            "                     ███████╗██║  ██║██║ ╚████║██████╔╝                     ",
            "                     ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝                      ",
            "                                                                              ",
            "                         .--.      _.-._      .--.                              ",
            "                       .'_\\/_'.   /_   _\\   .'_\\/_'.                            ",
            "                       '. /\\ .'   \\_) (_/   '. /\\ .'                            ",
            "                         '--'       `-'       '--'                              ",
            "══════════════════════════════════════════════════════════════════════════════",
            menu_line(string.format("  CAVE : %02d - %s", menu_level, cave_name), "   "),
            menu_line(string.format("  LEVEL: %03d     LIVES: %02d     SCORE: %06d", menu_difficulty + 1, lives, score),
                "PRESS [ENTER] TO START"),
        }

        local left = math.max(1, math.floor((W - 80) / 2) + 1)
        local top = math.max(1, math.floor((H - #lines) / 2) + 1)
        for i, line in ipairs(lines) do
            if i == 1 or i == 21 or i == #lines then
                g.color(0x78909C, 0x000000)
            elseif i >= 3 and i <= 8 then
                g.color(0xFFEE58, 0x000000)
            elseif i >= 10 and i <= 15 then
                g.color(0x4FC3F7, 0x000000)
            elseif i >= 17 and i <= 20 then
                g.color(0xA5D6A7, 0x000000)
            elseif i >= 22 and i <= 23 then
                g.color(0xFFFFFF, 0x000000)
            else
                g.color(0x455A64, 0x000000)
            end
            g.text(left, top + i - 1, line)
        end
        return
    end

    if state == "game_over" then
        g.color(0xEF9A9A, 0x000000)
        g.text(math.max(2, math.floor((W - 9) / 2)), math.max(4, math.floor(H / 2)), "GAME OVER")
        return
    end

    if state == "done" then
        g.color(0xA5D6A7, 0x000000)
        g.text(math.max(2, math.floor((W - 20) / 2)), 8, "Campaign complete")
        g.color(0xFFF59D, 0x000000)
        g.text(math.max(2, math.floor((W - 26) / 2)), 10, string.format("Final score %d", score))
        g.color(0xCFD8DC, 0x000000)
        g.text(math.max(2, math.floor((W - 24) / 2)), 12, "Press R to replay")
        return
    end

    draw_hud()
    draw_map()
end

return app
