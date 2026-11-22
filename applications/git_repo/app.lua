local kkc = require("kkc")
local g = require("kkc-graphics")
local key = require("kkc-key")
local shell = require("kkc-shell")

local app = {}

local repo_cwd = "."
local branch = "?"
local cursor = 1
local files = {}
local info_line = ""
local output_line = ""
local commit_mode = false
local commit_input = ""
local focus = "list" -- "list" | "diff"
local show_diff = true
local diff_staged = false
local diff_lines = {}
local diff_scroll = 1

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_lines(text)
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        out[#out + 1] = line
    end
    return out
end

local function first_non_empty_line(text)
    for _, line in ipairs(split_lines(text or "")) do
        local t = trim(line)
        if t ~= "" then
            return t
        end
    end
    return ""
end

local function truncate(s, w)
    if #s <= w then
        return s
    end
    if w <= 3 then
        return s:sub(1, w)
    end
    return s:sub(1, w - 3) .. "..."
end

local function git(args)
    return shell.run("git", args, repo_cwd)
end

local function clamp(v, lo, hi)
    if v < lo then
        return lo
    end
    if v > hi then
        return hi
    end
    return v
end

local function set_output(res)
    local line = first_non_empty_line(res.stdout)
    if line == "" then
        line = first_non_empty_line(res.stderr)
    end
    if line == "" then
        line = string.format("exit code %d", res.code or -1)
    end
    output_line = line
end

local function parse_status(stdout)
    local out = {}
    local lines = split_lines(stdout or "")
    for _, line in ipairs(lines) do
        if line ~= "" and line:sub(1, 2) ~= "##" and #line >= 4 then
            local xy = line:sub(1, 2)
            local path = line:sub(4)
            local arrow = path:find(" -> ", 1, true)
            if arrow then
                path = path:sub(arrow + 4)
            end
            out[#out + 1] = { xy = xy, path = path }
        end
    end
    return out
end

local function selected_file()
    if #files == 0 then
        return nil
    end
    return files[cursor]
end

local function refresh_diff()
    if not show_diff then
        diff_lines = {}
        diff_scroll = 1
        return
    end

    local f = selected_file()
    if not f then
        diff_lines = { "No file selected" }
        diff_scroll = 1
        return
    end

    local args
    if diff_staged then
        args = { "diff", "--staged", "--", f.path }
    else
        args = { "diff", "--", f.path }
    end

    local res = git(args)
    if not res.ok then
        local msg = first_non_empty_line(res.stderr)
        if msg == "" then
            msg = "Cannot compute diff"
        end
        diff_lines = { msg }
        diff_scroll = 1
        return
    end

    local lines = split_lines(res.stdout)
    local kept = {}
    for _, line in ipairs(lines) do
        if line ~= "" then
            kept[#kept + 1] = line
        end
    end

    if #kept == 0 then
        if diff_staged then
            kept = { "No staged diff for selected file" }
        else
            kept = { "No working-tree diff for selected file" }
        end
    end

    diff_lines = kept
    diff_scroll = clamp(diff_scroll, 1, math.max(1, #diff_lines))
end

local function refresh_status()
    local head = git({ "rev-parse", "--abbrev-ref", "HEAD" })
    if head.ok then
        branch = trim(head.stdout)
    else
        branch = "(not a git repo)"
    end

    local st = git({ "status", "--porcelain", "--branch" })
    if not st.ok then
        files = {}
        cursor = 1
        info_line = "No git repository at current panel path"
        set_output(st)
        refresh_diff()
        return
    end

    files = parse_status(st.stdout)
    if #files == 0 then
        info_line = "Working tree clean"
    else
        info_line = string.format("%d changed/untracked file(s)", #files)
    end

    if cursor < 1 then
        cursor = 1
    end
    if cursor > math.max(1, #files) then
        cursor = math.max(1, #files)
    end
    set_output(st)
    refresh_diff()
end

local function stage_selected()
    local f = selected_file()
    if not f then
        return
    end
    local res = git({ "add", "--", f.path })
    set_output(res)
    refresh_status()
end

local function unstage_selected()
    local f = selected_file()
    if not f then
        return
    end

    local res = git({ "restore", "--staged", "--", f.path })
    if not res.ok then
        res = git({ "reset", "HEAD", "--", f.path })
    end
    set_output(res)
    refresh_status()
end

local function has_staged_changes()
    for _, f in ipairs(files) do
        local idx_state = f.xy:sub(1, 1)
        if idx_state ~= " " and idx_state ~= "?" then
            return true
        end
    end
    return false
end

local function stage_all()
    local res = git({ "add", "-A" })
    set_output(res)
    refresh_status()
end

local function unstage_all()
    local res = git({ "restore", "--staged", "." })
    if not res.ok then
        res = git({ "reset", "HEAD", "--", "." })
    end
    set_output(res)
    refresh_status()
end

local function toggle_selected()
    local f = selected_file()
    if not f then
        return
    end

    local index_state = f.xy:sub(1, 1)
    if index_state == " " or index_state == "?" then
        stage_selected()
    else
        unstage_selected()
    end
end

local function toggle_all()
    if has_staged_changes() then
        unstage_all()
    else
        stage_all()
    end
end

local function git_pull()
    local res = git({ "pull", "--rebase", "--autostash" })
    set_output(res)
    refresh_status()
end

local function git_push()
    local res = git({ "push" })
    set_output(res)
    refresh_status()
end

local function git_commit(msg)
    local text = trim(msg or "")
    -- Keep a single-line subject for now to match the app input model.
    text = text:gsub("\n", " ")
    if text == "" then
        output_line = "Commit subject is empty"
        return
    end
    local res = git({ "commit", "--no-gpg-sign", "--no-verify", "-m", text })
    set_output(res)
    refresh_status()
end

function app.shortcuts()
    if commit_mode then
        return {
            "Enter:Commit",
            "F7:Commit",
            "Bksp:Delete",
            "Esc:Cancel",
        }
    end
    return {
        "F2:Toggle",
        "F3:ToggleAll",
        "F4:DiffMode",
        "F5:Refresh",
        "F6:Diff",
        "F7:Commit",
        "F8:Pull",
        "F9:Push"
    }
end

function app.init()
    repo_cwd = "."
    if type(kkc.get_cwd) == "function" then
        repo_cwd = kkc.get_cwd()
    elseif type(kkc.cwd) == "string" and kkc.cwd ~= "" then
        repo_cwd = kkc.cwd
    end
    refresh_status()
end

function app.draw()
    local w, h = g.size()
    g.clear(" ")
    g.reset()

    g.color(0xFFFFFF, 0x000000)
    g.text(1, 1, truncate("Path: " .. repo_cwd, w))
    local diff_mode_label = diff_staged and "staged" or "worktree"
    g.text(1, 2, truncate("Branch: " .. branch .. " | Focus: " .. focus .. " | Diff: " .. diff_mode_label, w))
    if commit_mode then
        g.color(0x99FFCC, 0x000000)
        g.text(1, 3, truncate("Commit subject: " .. commit_input .. "_", w))
        g.color(0x666666, 0x000000)
        g.text(1, 4, string.rep("-", math.max(1, w)))
    else
        g.color(0x666666, 0x000000)
        g.text(1, 3, string.rep("-", math.max(1, w)))
    end

    local list_top = commit_mode and 5 or 4
    local content_bottom = h - 4
    local content_h = math.max(1, content_bottom - list_top + 1)
    local split = show_diff and w >= 70
    local list_w = split and math.max(28, math.floor(w * 0.42)) or w
    local diff_x = list_w + 2
    local diff_w = math.max(1, w - diff_x + 1)

    local start = 1
    local list_rows = math.max(1, content_h - 1)
    if cursor > list_rows then
        start = cursor - list_rows + 1
    end

    g.color(0x99CCFF, 0x000000)
    g.text(1, list_top, truncate((focus == "list" and "> " or "  ") .. "Files", list_w))

    if #files == 0 then
        g.color(0xCCCCCC, 0x000000)
        g.text(1, list_top + 1, truncate("No changes to show", list_w))
    else
        for row = 0, list_rows - 1 do
            local idx = start + row
            if idx > #files then
                break
            end
            local y = list_top + 1 + row
            local f = files[idx]
            local marker = (idx == cursor) and ">" or " "
            local line = string.format("%s [%s] %s", marker, f.xy, f.path)
            if idx == cursor then
                g.color(0xFFE082, 0x000000)
            else
                g.color(0xFFFFFF, 0x000000)
            end
            g.text(1, y, truncate(line, list_w))
        end
    end

    if split then
        g.color(0x666666, 0x000000)
        for y = list_top, content_bottom do
            g.text(list_w + 1, y, "│")
        end

        local title = (focus == "diff" and "> " or "  ") .. "Diff"
        g.color(0x99FFCC, 0x000000)
        g.text(diff_x, list_top, truncate(title, diff_w))

        local visible_diff_rows = math.max(1, content_h - 1)
        local max_scroll = math.max(1, #diff_lines - visible_diff_rows + 1)
        diff_scroll = clamp(diff_scroll, 1, max_scroll)

        g.color(0xDDDDDD, 0x000000)
        for row = 0, visible_diff_rows - 1 do
            local idx = diff_scroll + row
            if idx > #diff_lines then
                break
            end
            local line = diff_lines[idx]
            local fg = 0xDDDDDD
            if line:sub(1, 1) == "+" and line:sub(1, 3) ~= "+++" then
                fg = 0x7CFC9A
            elseif line:sub(1, 1) == "-" and line:sub(1, 3) ~= "---" then
                fg = 0xFF8A80
            elseif line:sub(1, 2) == "@@" then
                fg = 0x82B1FF
            end
            g.color(fg, 0x000000)
            g.text(diff_x, list_top + 1 + row, truncate(line, diff_w))
        end
    end

    g.color(0x666666, 0x000000)
    g.text(1, h - 3, string.rep("-", math.max(1, w)))
    g.color(0xFFFF99, 0x000000)
    g.text(1, h - 2, truncate("Info: " .. info_line, w))
    g.text(1, h - 1, truncate("Last: " .. output_line, w))

    g.reset()
end

function app.keypressed(k)
    if commit_mode then
        if k == key.ESC then
            commit_mode = false
            commit_input = ""
            output_line = "Commit canceled"
            return
        elseif k == key.ENTER or k == "f7" then
            git_commit(commit_input)
            commit_mode = false
            commit_input = ""
            return
        elseif k == "backspace" then
            commit_input = commit_input:sub(1, math.max(0, #commit_input - 1))
            return
        elseif k == key.SPACE then
            commit_input = commit_input .. " "
            return
        else
            local ch = k:match("^char:(.)$")
            if ch then
                commit_input = commit_input .. ch
            end
            return
        end
    end

    if k == key.ESC then
        kkc.quit()
    elseif k == "tab" then
        if show_diff then
            if focus == "list" then
                focus = "diff"
            else
                focus = "list"
            end
        end
    elseif k == key.UP then
        if focus == "diff" and show_diff then
            diff_scroll = math.max(1, diff_scroll - 1)
        else
            if #files > 0 then
                cursor = math.max(1, cursor - 1)
                refresh_diff()
            end
        end
    elseif k == key.DOWN then
        if focus == "diff" and show_diff then
            diff_scroll = diff_scroll + 1
        else
            if #files > 0 then
                cursor = math.min(#files, cursor + 1)
                refresh_diff()
            end
        end
    elseif k == "pageup" then
        diff_scroll = math.max(1, diff_scroll - 10)
    elseif k == "pagedown" then
        diff_scroll = diff_scroll + 10
    elseif k == key.SPACE or k == key.ENTER or k == "f2" then
        toggle_selected()
    elseif k == "char:a" or k == "f3" then
        toggle_all()
    elseif k == "f4" then
        diff_staged = not diff_staged
        refresh_diff()
    elseif k == "char:c" or k == "f7" then
        commit_mode = true
        commit_input = ""
        output_line = "Type commit subject, then Enter"
    elseif k == "char:p" or k == "f9" then
        git_push()
    elseif k == "char:l" or k == "f8" then
        git_pull()
    elseif k == "char:r" or k == "f5" then
        refresh_status()
    elseif k == "char:d" then
        diff_staged = not diff_staged
        refresh_diff()
    elseif k == "f6" then
        show_diff = not show_diff
        if not show_diff then
            focus = "list"
        end
        refresh_diff()
    end
end

return app
