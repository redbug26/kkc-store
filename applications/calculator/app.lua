-- RPN Calculator
-- Keys: key_name() sends "up"/"down"/etc, "backspace","enter","space"
--       and "char:x" for printable characters
local g = require("kkc-graphics")

-- ─── State ───────────────────────────────────────────────────────────────────
local stack = {}
local entry = ""
local status = ""
local error_msg = nil

local MAX_STACK = 8

-- ─── Helpers ─────────────────────────────────────────────────────────────────
local function fmt(n)
    if n == nil then return "nil" end
    if n ~= n then return "NaN" end
    if n == math.huge then return "+Inf" end
    if n == -math.huge then return "-Inf" end
    if math.type(n) == "float" and n == math.floor(n) and math.abs(n) < 1e12 then
        return string.format("%d", n)
    end
    return string.format("%.10g", n)
end

local function push(n) stack[#stack + 1] = n end

local function pop()
    if #stack == 0 then error("stack empty") end
    local v = stack[#stack]
    stack[#stack] = nil
    return v
end

local function apply_op(op)
    error_msg = nil
    local ok, err = pcall(function()
        if op == "+" or op == "-" or op == "*" or op == "/" then
            if #stack < 2 then error("need 2 operands") end
            local b = pop(); local a = pop()
            if op == "+" then push(a + b)
            elseif op == "-" then push(a - b)
            elseif op == "*" then push(a * b)
            elseif op == "/" then
                if b == 0 then error("div by 0") end
                push(a / b)
            end
            status = string.format("%s %s %s", fmt(a), op, fmt(b))
        elseif op == "%" then
            if #stack < 2 then error("need 2 operands") end
            local b = pop(); local a = pop()
            if b == 0 then error("mod by 0") end
            push(a % b); status = string.format("%s %% %s", fmt(a), fmt(b))
        elseif op == "sqrt" then
            if #stack < 1 then error("need 1 operand") end
            local a = pop()
            if a < 0 then error("sqrt of negative") end
            push(math.sqrt(a)); status = "sqrt"
        elseif op == "neg" then
            if #stack < 1 then error("need 1 operand") end
            push(-pop()); status = "negate"
        elseif op == "1/x" then
            if #stack < 1 then error("need 1 operand") end
            local a = pop()
            if a == 0 then error("1/0") end
            push(1/a); status = "1/x"
        elseif op == "x^y" then
            if #stack < 2 then error("need 2 operands") end
            local y = pop(); local x = pop()
            push(x ^ y); status = string.format("x^%s", fmt(y))
        elseif op == "swap" then
            if #stack < 2 then error("need 2 operands") end
            local b = pop(); local a = pop()
            push(b); push(a); status = "swap"
        elseif op == "drop" then
            pop(); status = "drop"
        elseif op == "dup" then
            if #stack < 1 then error("need 1 operand") end
            push(stack[#stack]); status = "dup"
        end
    end)
    if not ok then error_msg = tostring(err) end
end

local function enter_value()
    error_msg = nil
    if entry == "" or entry == "." or entry == "-" then
        if #stack > 0 then push(stack[#stack]); status = "dup" end
        return
    end
    local n = tonumber(entry)
    if n == nil then error_msg = "bad number"; return end
    push(n)
    entry = ""
    status = ""
end

-- ─── Layout ──────────────────────────────────────────────────────────────────
local W, H = 40, 24

local KEYS = {
    { "7",    "8",    "9",    "/",   "sqrt" },
    { "4",    "5",    "6",    "*",   "x^y"  },
    { "1",    "2",    "3",    "-",   "1/x"  },
    { "0",    ".",    "neg",  "+",   "="    },
    { "drop", "dup",  "swap", "%",   "clr"  },
}

-- ─── App ─────────────────────────────────────────────────────────────────────
local app = {}

function app.init(ctx) W = ctx.width; H = ctx.height end
function app.resize(w, h) W = w; H = h end

function app.draw()
    g.clear()
    local row = 1

    local title = " RPN Calculator "
    g.print(row, 1, string.rep("─", W))
    g.print(row, math.floor((W - #title) / 2) + 1, title)
    row = row + 1

    -- Stack
    local stack_rows = math.min(#stack, MAX_STACK)
    local stack_start = #stack - stack_rows + 1
    for i = 0, MAX_STACK - 1 do
        local label = string.format("%2d: ", MAX_STACK - i)
        local idx = stack_start + (stack_rows - MAX_STACK + i)
        local val = ""
        if idx >= 1 and idx <= #stack then val = fmt(stack[idx]) end
        g.print(row + i, 1, label .. string.rep(" ", W - #label - #val - 2) .. val)
    end
    row = row + MAX_STACK

    g.print(row, 1, string.rep("─", W)); row = row + 1
    local entry_disp = "ENT> " .. entry .. "█"
    g.print(row, 1, entry_disp); row = row + 1
    g.print(row, 1, string.rep("─", W)); row = row + 1

    if error_msg then
        g.print(row, 1, "ERR: " .. error_msg)
    elseif status ~= "" then
        g.print(row, 1, "     " .. status)
    else
        g.print(row, 1, "")
    end
    row = row + 1
    g.print(row, 1, string.rep("─", W)); row = row + 1

    local cell_w = 7
    for r, krow in ipairs(KEYS) do
        local line = ""
        for _, k in ipairs(krow) do
            local label = "[" .. k .. "]"
            label = label .. string.rep(" ", cell_w - #label)
            line = line .. label
        end
        g.print(row + r - 1, 1, line)
    end
    row = row + #KEYS + 1

    g.print(row, 1, " Enter=push  Bksp=del  Esc=quit")
    g.print(row + 1, 1, " s=sqrt n=neg d=dup x=swap c=clear")
end

function app.keypressed(key)
    -- Backspace / delete
    if key == "backspace" then
        if #entry > 0 then
            entry = string.sub(entry, 1, #entry - 1)
        elseif #stack > 0 then
            apply_op("drop")
        end
        return
    end

    -- Enter: push current entry onto stack
    if key == "enter" then
        enter_value()
        return
    end

    -- Digit: key arrives as "char:5"
    local digit = key:match("^char:([0-9])$")
    if digit then
        entry = entry .. digit
        return
    end

    -- Decimal point
    if key == "char:." then
        if not entry:find("%.") then entry = entry .. "." end
        return
    end

    -- Arithmetic operators
    local ops = {
        ["char:+"] = "+",
        ["char:-"] = "-",
        ["char:*"] = "*",
        ["char:/"] = "/",
        ["char:%"] = "%",
    }
    if ops[key] then
        if entry ~= "" then enter_value() end
        apply_op(ops[key])
        return
    end

    -- Named shortcuts
    if key == "char:s" then if entry ~= "" then enter_value() end; apply_op("sqrt"); return end
    if key == "char:n" then if entry ~= "" then enter_value() end; apply_op("neg");  return end
    if key == "char:d" then if entry ~= "" then enter_value() end; apply_op("dup");  return end
    if key == "char:x" then if entry ~= "" then enter_value() end; apply_op("swap"); return end
    if key == "char:r" then if entry ~= "" then enter_value() end; apply_op("drop"); return end
    if key == "char:p" then if entry ~= "" then enter_value() end; apply_op("x^y");  return end
    if key == "char:i" then if entry ~= "" then enter_value() end; apply_op("1/x");  return end
    if key == "char:c" then entry = ""; stack = {}; status = ""; error_msg = nil; return end
end

return app
