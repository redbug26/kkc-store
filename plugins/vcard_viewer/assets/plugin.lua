local kkc = require("kkc")

local function span(text, fg, bold)
    return { text = text or "", fg = fg or "white", bg = "black", bold = bold or false }
end

local function line(...)
    return { ... }
end

local function read_all(path)
    local file, err = io.open(path, "rb")
    if not file then
        return nil, err
    end
    local data = file:read("*a")
    file:close()
    return data
end

local function is_vcard_path(path)
    local ext = path:match("%.([^%.\\/]+)$")
    return ext and ext:lower() == "vcf"
end

local function unfold_lines(text)
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    for raw in (text .. "\n"):gmatch("(.-)\n") do
        if raw:match("^[ \t]") and #lines > 0 then
            lines[#lines] = lines[#lines] .. raw:sub(2)
        else
            table.insert(lines, raw)
        end
    end
    return lines
end

local function decode_value(value)
    value = value or ""
    value = value:gsub("\\n", "\n"):gsub("\\N", "\n")
    value = value:gsub("\\,", ","):gsub("\\;", ";"):gsub("\\\\", "\\")
    return value
end

local function split_semicolon(value)
    local parts = {}
    local current = {}
    local escaped = false
    for i = 1, #value do
        local ch = value:sub(i, i)
        if escaped then
            table.insert(current, ch)
            escaped = false
        elseif ch == "\\" then
            table.insert(current, ch)
            escaped = true
        elseif ch == ";" then
            table.insert(parts, decode_value(table.concat(current)))
            current = {}
        else
            table.insert(current, ch)
        end
    end
    table.insert(parts, decode_value(table.concat(current)))
    return parts
end

local function parse_property(raw)
    local head, value = raw:match("^([^:]-):(.*)$")
    if not head then
        return nil
    end
    local tokens = {}
    for token in head:gmatch("[^;]+") do
        table.insert(tokens, token)
    end
    local name = (tokens[1] or ""):upper()
    local params = {}
    for i = 2, #tokens do
        local key, val = tokens[i]:match("^([^=]+)=(.*)$")
        if key then
            params[key:upper()] = val
        else
            table.insert(params, tokens[i])
        end
    end
    return name, decode_value(value), params
end

local function add_multi(contact, key, value, params)
    if not value or value == "" then
        return
    end
    contact[key] = contact[key] or {}
    table.insert(contact[key], { value = value, params = params or {} })
end

local function parse_vcards(text)
    local cards = {}
    local current = nil
    for _, raw in ipairs(unfold_lines(text)) do
        local upper = raw:upper()
        if upper == "BEGIN:VCARD" then
            current = { tel = {}, email = {}, adr = {}, url = {}, note = {} }
        elseif upper == "END:VCARD" then
            if current then
                table.insert(cards, current)
            end
            current = nil
        elseif current then
            local name, value, params = parse_property(raw)
            if name == "FN" then
                current.fn = value
            elseif name == "N" then
                local parts = split_semicolon(value)
                local display = {}
                if parts[4] and parts[4] ~= "" then table.insert(display, parts[4]) end
                if parts[2] and parts[2] ~= "" then table.insert(display, parts[2]) end
                if parts[3] and parts[3] ~= "" then table.insert(display, parts[3]) end
                if parts[1] and parts[1] ~= "" then table.insert(display, parts[1]) end
                if parts[5] and parts[5] ~= "" then table.insert(display, parts[5]) end
                current.name = table.concat(display, " ")
            elseif name == "ORG" then
                current.org = table.concat(split_semicolon(value), " / ")
            elseif name == "TITLE" then
                current.title = value
            elseif name == "TEL" then
                add_multi(current, "tel", value, params)
            elseif name == "EMAIL" then
                add_multi(current, "email", value, params)
            elseif name == "ADR" then
                local parts = split_semicolon(value)
                local display = {}
                for _, idx in ipairs({ 3, 4, 5, 6, 7 }) do
                    if parts[idx] and parts[idx] ~= "" then
                        table.insert(display, parts[idx])
                    end
                end
                add_multi(current, "adr", table.concat(display, ", "), params)
            elseif name == "URL" then
                add_multi(current, "url", value, params)
            elseif name == "NOTE" then
                add_multi(current, "note", value, params)
            elseif name == "BDAY" then
                current.bday = value
            end
        end
    end
    return cards
end

local function type_label(item)
    local params = item.params or {}
    local t = params.TYPE or params[1] or ""
    if t == "" then
        return ""
    end
    return " [" .. t:gsub(",", "/") .. "]"
end

local function push_items(lines, label, items)
    for _, item in ipairs(items or {}) do
        table.insert(lines, line(
            span("  " .. label .. type_label(item) .. ": ", "gray"),
            span(item.value, "white")
        ))
    end
end

local function render_vcard(path, mode)
    if mode ~= "text" or not is_vcard_path(path) then
        return nil
    end
    local data, err = read_all(path)
    if not data then
        return { line(span("Error: " .. tostring(err), "red", true)) }
    end

    local cards = parse_vcards(data)
    local filename = path:match("([^\\/]+)$") or path
    local lines = {
        line(span("vCard contacts", "yellow", true), span("  " .. filename, "gray")),
        line(span("Cards: ", "gray"), span(tostring(#cards), "cyan")),
        line(span("")),
    }

    if #cards == 0 then
        table.insert(lines, line(span("No vCard entry found", "gray")))
        return lines
    end

    for idx, card in ipairs(cards) do
        local name = card.fn or card.name or "(unnamed)"
        table.insert(lines, line(span(string.format("%d. ", idx), "gray"), span(name, "lightcyan", true)))
        if card.title and card.title ~= "" then
            table.insert(lines, line(span("  Title: ", "gray"), span(card.title, "white")))
        end
        if card.org and card.org ~= "" then
            table.insert(lines, line(span("  Org: ", "gray"), span(card.org, "white")))
        end
        if card.bday and card.bday ~= "" then
            table.insert(lines, line(span("  Birthday: ", "gray"), span(card.bday, "white")))
        end
        push_items(lines, "Email", card.email)
        push_items(lines, "Phone", card.tel)
        push_items(lines, "Address", card.adr)
        push_items(lines, "URL", card.url)
        push_items(lines, "Note", card.note)
        table.insert(lines, line(span("")))
    end

    return lines
end

kkc.register_viewer_plugin({
    name = "vcard_viewer",
    version = "1.0.4",
    description = "vCard contact viewer",
    modes = { "text" },
    mime_types = { "text/vcard" },
    render = render_vcard,
})
