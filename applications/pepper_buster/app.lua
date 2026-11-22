local kkc = require("kkc")
local key = require("kkc-key")
local fs = require("kkc-fs")
local audio = require("kkc-audio")
local Game = require("game")
local View = require("view")

local app = {}
local bonus_names = {
    [0] = "NONE", "HIDDEN WALLS", "SPEEDY PAC", "FRIGHTENED GHOSTS",
    "INVERTED CONTROLS", "HUNGRY GHOSTS", "EXTRA LIFE",
}
local game = Game.new()
local mode, previous_mode, timer = "menu", "play", 0
local width, height, elapsed, accumulator = 78, 22, 0, 0
local selected_level, selected_lives = 0, 3
local highscore, sound = 0, false
local turbo_latch, turbo_toggled = false, false
local held, popup = {}, nil
local banner, banner_time = "", 0
local STEP = 1 / 50

local function beep()
    if sound then pcall(audio.beep) end
end
local function save_score()
    local score = game.score * 10
    if score > highscore then
        highscore = score
        -- Browsers may keep this only for the current imported Kapsule session.
        pcall(fs.write_text, "state/highscore.txt", tostring(highscore))
    end
end
local function read_score()
    local ok, text = pcall(fs.read_text, "state/highscore.txt")
    if ok then highscore = math.max(0, math.floor(tonumber(text) or 0)) end
end
local function ready()
    mode, timer, accumulator = "ready", 1.35, 0
    turbo_latch, turbo_toggled, held = false, false, {}
    game.turbo = 16
end
local function start_game()
    game = Game.new(selected_lives, selected_level)
    banner, banner_time, popup = "", 0, nil
    ready()
end
local function menu()
    save_score()
    mode, game = "menu", Game.new(selected_lives, selected_level)
    turbo_latch, turbo_toggled, held, accumulator = false, false, {}, 0
end
local function direction(k)
    if k == "up" or k == "char:w" or k == "char:W" or k == "char:z" then return Game.UP end
    if k == "down" or k == "char:s" or k == "char:S" then return Game.DOWN end
    if k == "left" or k == "char:a" or k == "char:A" or k == "char:q" then return Game.LEFT end
    if k == "right" or k == "char:d" or k == "char:D" then return Game.RIGHT end
end
local function turbo_down()
    return turbo_toggled or turbo_latch and (key.is_down(key.SPACE) or held.space ~= nil)
end
function app.init()
    read_score()
end
function app.resize(w, h)
    width, height = w, h
end
function app.keypressed(k)
    local d = direction(k)
    if d and (mode == "play" or mode == "ready" or mode == "popup") then
        game.pac.pending = game.bonus == Game.INVERT and ({2, 1, 4, 3})[d] or d
    end
    -- Release-capable hosts report held space precisely; others expire repeats.
    if k == "space" and mode == "play" then
        turbo_latch, held.space = true, elapsed
    end
end
function app.keydown(k)
    if k == "char:m" or k == "char:M" then sound = not sound; return end
    if k == "esc" then
        if mode == "menu" then save_score(); kkc.quit()
        elseif mode == "paused" then mode = previous_mode
        else previous_mode, mode = mode, "paused" end
        return
    end
    if k == "char:p" or k == "char:P" then
        if mode == "paused" then mode = previous_mode
        elseif mode ~= "menu" and mode ~= "over" then previous_mode, mode = mode, "paused" end
        return
    end
    if mode == "menu" then
        local d = direction(k)
        if d == Game.LEFT then selected_level = (selected_level + 7) % 8
        elseif d == Game.RIGHT then selected_level = (selected_level + 1) % 8
        elseif d == Game.UP then selected_lives = math.min(5, selected_lives + 1)
        elseif d == Game.DOWN then selected_lives = math.max(1, selected_lives - 1)
        elseif k == "enter" or k == "space" then start_game(); return end
        game = Game.new(selected_lives, selected_level)
    elseif mode == "paused" then
        if k == "enter" or k == "space" then mode = previous_mode
        elseif k == "char:r" or k == "char:R" then start_game()
        elseif k == "char:q" or k == "char:Q" then menu() end
    elseif mode == "over" then
        if k == "enter" or k == "space" then start_game()
        elseif k == "char:q" or k == "char:Q" then menu() end
    elseif mode == "play" then
        if k == "char:t" or k == "char:T" then turbo_toggled = not turbo_toggled end
    end
end
function app.keyup(k)
    if k == "space" then turbo_latch, held.space = false, nil end
end
function app.focuslost()
    turbo_latch, turbo_toggled, held = false, false, {}
    if mode ~= "menu" and mode ~= "over" and mode ~= "paused" then previous_mode, mode = mode, "paused" end
end
local function simulation_step()
    game:step(turbo_down() and 16 or 0)
    if game.events & 4 ~= 0 then
        banner, banner_time = bonus_names[game.last_bonus or game.bonus], 2.3
        if game.last_bonus == Game.QUICK then banner = "SPEEDY PAC - TURBO REFILLED" end
        beep()
    end
    if game.events & 16 ~= 0 then banner, banner_time = "A MYSTERY BONUS HAS APPEARED", 2.3 end
    if game.state == Game.CAUGHT then
        mode, timer, turbo_latch, turbo_toggled = "caught", 1.1, false, false
        save_score()
        beep()
    elseif game.state == Game.CLEAR then
        mode, timer = "clear", 1.5
        save_score()
    elseif game.events & 8 ~= 0 then
        popup = {value = 50 * 2 ^ game.eaten_value, ghost = game.eaten_ghost}
        mode, timer = "popup", 0.45
        beep()
    end
end
function app.update(dt)
    elapsed = elapsed + dt
    if held.space and not key.HAS_RELEASE_EVENTS and elapsed - held.space > 0.2 then held.space = nil end
    if mode == "menu" or mode == "paused" or mode == "over" then return end
    if width < 30 or height < 12 then return end
    banner_time = math.max(0, banner_time - dt)
    if mode ~= "play" then
        timer = timer - dt
        if timer <= 0 then
            if mode == "ready" or mode == "popup" then mode, popup = "play", nil
            elseif mode == "clear" then game:start(game.level + 1); ready()
            elseif mode == "caught" then
                game.lives = game.lives - 1
                if game.lives <= 0 then mode = "over"; save_score()
                else game:restart_positions(); ready() end
            end
        end
        accumulator = 0
        return
    end
    -- Fixed simulation tick, bounded catch-up after a terminal stall.
    accumulator = math.min(accumulator + dt, STEP * 5)
    while accumulator >= STEP and mode == "play" do
        accumulator = accumulator - STEP
        simulation_step()
    end
end
function app.draw()
    local status = "EAT EVERY SMALL PILL - WATCH THE GHOSTS"
    if game.bonus ~= Game.NONE and game.bonus_time > 0 then
        status = bonus_names[game.bonus] .. string.format("  %.1fs", game.bonus_time / 50)
    end
    if banner_time > 0 then status = banner end
    View.draw(game, {
        width = width, height = height, mode = mode, elapsed = elapsed,
        highscore = highscore, selected_level = selected_level, selected_lives = selected_lives,
        sound = sound, turbo = turbo_down(), popup = popup, status = status,
    })
end
function app.shortcuts()
    if mode == "menu" then return {"Enter:Start", "Arrows:Setup", "M:Sound", "Esc:Quit"} end
    if mode == "paused" then return {"Enter:Resume", "R:Restart", "Q:Menu"} end
    if mode == "over" then return {"Enter:Retry", "Q:Menu", "Esc:Pause"} end
    return {"Arrows:Steer", "Space:Turbo", "T:Toggle", "P:Pause", "F5:Zoom"}
end
return app
