local kkc = require("kkc")

local EXTENSIONS = {
    "wbc",
    "wb1",
    "wbz",
    "wbd",
    "wbp",
}

local function lower_ext(path)
    local ext = path:match("%.([^%.\\/]+)$")
    return ext and ext:lower() or ""
end

local function can_handle(path)
    local ext = lower_ext(path)
    for _, candidate in ipairs(EXTENSIONS) do
        if ext == candidate then
            return true
        end
    end
    return false
end

local function read_all(path)
    local f, err = io.open(path, "rb")
    if not f then
        error("Cannot open file: " .. tostring(err), 0)
    end
    local data = f:read("*a")
    f:close()
    return data
end

local function basename_no_ext(path)
    local normalized = (path or ""):gsub("\\", "/")
    local base = normalized:match("([^/]+)$") or normalized
    return (base:gsub("%.[^%.]+$", ""))
end

local function trim(text)
    return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function fixed_text(data, start_pos, length)
    local raw = data:sub(start_pos, start_pos + length - 1)
    local nul = raw:find("\0", 1, true)
    if nul then
        raw = raw:sub(1, nul - 1)
    end
    raw = raw:gsub("[%c]", " ")
    raw = trim(raw:gsub("%s+", " "))
    if raw == "" then
        return nil
    end
    return raw
end

local function sanitize_filename(name)
    local value = trim((name or ""):gsub("[%c%z]", " "))
    value = value:gsub("[\\/:*?\"<>|]", "_")
    value = value:gsub("%s+", " ")
    value = trim(value)
    if value == "" then
        return "image"
    end
    return value
end

local function unique_name(used, stem, ext)
    local idx = 1
    while true do
        local name = string.format("%s_%03d.%s", stem, idx, ext)
        if not used[name] then
            used[name] = true
            return name
        end
        idx = idx + 1
    end
end

local function unique_filename(used, base, ext)
    base = sanitize_filename(base)
    ext = (ext or "png"):lower():gsub("^%.", "")
    local idx = 0
    while true do
        local name
        if idx == 0 then
            name = string.format("%s.%s", base, ext)
        else
            name = string.format("%s (%d).%s", base, idx, ext)
        end
        if not used[name] then
            used[name] = true
            return name
        end
        idx = idx + 1
    end
end

local function save_blob(destination, used, stem, ext, blob)
    local name = unique_name(used, stem, ext)
    local out_path = kkc.path_join(destination, name)
    kkc.write_file(out_path, blob)
    return name
end

local function save_named_blob(destination, used, base, ext, blob)
    local name = unique_filename(used, base, ext)
    local out_path = kkc.path_join(destination, name)
    kkc.write_file(out_path, blob)
    return name
end

local function safe_exec(program, args, cwd)
    local ok, result = pcall(kkc.exec, program, args, cwd)
    if not ok or not result then
        return { success = false, status = -1, stdout = "", stderr = tostring(result) }
    end
    return result
end

local function count_files_glob(destination, pattern)
    local result = safe_exec(
        "find",
        { destination, "-maxdepth", "1", "-type", "f", "-name", pattern },
        nil
    )
    if not result or not result.success then
        return 0
    end
    local count = 0
    for line in (result.stdout or ""):gmatch("[^\r\n]+") do
        if line ~= "" then
            count = count + 1
        end
    end
    return count
end

local function try_nconvert(path, destination, stem)
    -- Dexvert uses: nconvert[format:wbc]
    local out_multi = kkc.path_join(destination, stem .. "_%04d.png")
    local out_single = kkc.path_join(destination, "webshots.png")
    local attempts = {
        {
            "nconvert",
            { "-quiet", "-out", "png", "-o", out_multi, path },
            stem .. "_*.png",
        },
        {
            "nconvert",
            { "-out", "png", "-o", out_multi, path },
            stem .. "_*.png",
        },
        {
            "nconvert",
            { "-quiet", "-out", "png", "-o", out_single, path },
            "webshots*.png",
        },
        {
            "nconvert",
            { "-out", "png", "-o", out_single, path },
            "webshots*.png",
        },
    }

    for _, attempt in ipairs(attempts) do
        local result = safe_exec(attempt[1], attempt[2], nil)
        if result and result.success then
            local generated = count_files_glob(destination, attempt[3])
            if generated > 0 then
                return true, generated
            end
        end
    end

    return false, 0
end

local function le32(data, pos)
    local b1, b2, b3, b4 = data:byte(pos, pos + 3)
    return (b1 or 0) | ((b2 or 0) << 8) | ((b3 or 0) << 16) | ((b4 or 0) << 24)
end

local function detect_image_ext(blob)
    if blob:sub(1, 8) == "\137PNG\r\n\026\n" then
        return "png"
    end
    if blob:sub(1, 3) == "\255\216\255" then
        return "jpg"
    end
    if blob:sub(1, 2) == "BM" then
        return "bmp"
    end
    return "bin"
end

local function decrypt_webshots_jpeg(blob)
    -- WBC encrypted JPEG marker documented by Setaou:
    -- WWBB0000 (key A4) or WWBB1111 (key F2), then A[100], B[100], payload...
    -- Decrypted header is B' where B'[n] = B[n] XOR (NOT A[n]) XOR key.
    local tag = blob:sub(1, 8)
    local key
    if tag == "WWBB0000" then
        key = 0xA4
    elseif tag == "WWBB1111" then
        key = 0xF2
    else
        return blob, false
    end

    if #blob < 208 then
        return blob, false
    end

    local a = { blob:byte(9, 108) }
    local b = { blob:byte(109, 208) }
    local out = {}
    for i = 1, 100 do
        local av = a[i] or 0
        local bv = b[i] or 0
        local dec = (bv ~ ((~av) & 0xFF) ~ key) & 0xFF
        out[i] = string.char(dec)
    end
    local decoded = table.concat(out) .. blob:sub(209)
    return decoded, true
end

local function extract_wbc_units(data, destination, used, stem)
    -- File header
    if #data < 2200 or data:sub(1, 4) ~= "\171\022\250\149" then
        return 0
    end

    local index_offset = 2197 -- 0x894 + 1
    local unit_count = le32(data, index_offset)
    if unit_count <= 0 or unit_count > 100000 then
        return 0
    end

    local count = 0
    local item_size = 40 -- 4+4+4+4+24
    local first_item = index_offset + 4

    for i = 0, unit_count - 1 do
        local item_pos = first_item + i * item_size
        if item_pos + 11 > #data then
            break
        end

        local unit_offset = le32(data, item_pos) + 1
        local unit_size = le32(data, item_pos + 4)
        if unit_offset < 1 or unit_offset + 12 > #data or unit_size <= 0 then
            goto continue
        end

        -- Unit header tag E2 CD 71 F0
        if data:sub(unit_offset, unit_offset + 3) ~= "\226\205q\240" then
            goto continue
        end

        local unit_header_size = le32(data, unit_offset + 4)
        local picture_size = le32(data, unit_offset + 916)
        local thumb_size = le32(data, unit_offset + 920)
        if unit_header_size < 2088 or picture_size <= 0 then
            goto continue
        end

        local filename = fixed_text(data, unit_offset + 12, 256)
        local title = fixed_text(data, unit_offset + 268, 128)
        local ext = fixed_text(data, unit_offset + 908, 8)
        if ext then
            ext = ext:lower():gsub("^%.", "")
        end

        local base_name = title or filename or string.format("%s_%03d", stem, i + 1)
        local pic_start = unit_offset + unit_header_size
        local pic_end = pic_start + picture_size - 1
        if pic_start < 1 or pic_end > #data then
            goto continue
        end

        local picture = data:sub(pic_start, pic_end)
        local decrypted
        picture, decrypted = decrypt_webshots_jpeg(picture)
        local out_ext = ext
        if not out_ext or out_ext == "" then
            out_ext = detect_image_ext(picture)
        end
        save_named_blob(destination, used, base_name, out_ext, picture)
        count = count + 1

        if thumb_size and thumb_size > 0 then
            local t_start = pic_end + 1
            local t_end = t_start + thumb_size - 1
            if t_end <= #data then
                local thumb = data:sub(t_start, t_end)
                thumb = (decrypt_webshots_jpeg(thumb))
                local thumb_ext = detect_image_ext(thumb)
                save_named_blob(destination, used, base_name .. "_thumb", thumb_ext, thumb)
            end
        end

        ::continue::
    end

    return count
end

local function extract_png_blobs(data, destination, used, stem)
    local count = 0
    local pos = 1
    local sig = "\137PNG\r\n\026\n"
    while true do
        local s = data:find(sig, pos, true)
        if not s then
            break
        end
        local e = data:find("IEND\174B`\130", s + #sig, true)
        if not e then
            break
        end
        local blob = data:sub(s, e + 7)
        save_blob(destination, used, stem, "png", blob)
        count = count + 1
        pos = e + 8
    end
    return count
end

local function extract_jpeg_blobs(data, destination, used, stem)
    local count = 0
    local pos = 1
    while true do
        local s = data:find("\255\216\255", pos)
        if not s then
            break
        end
        local e = data:find("\255\217", s + 3)
        if not e then
            break
        end
        local blob = data:sub(s, e + 1)
        save_blob(destination, used, stem, "jpg", blob)
        count = count + 1
        pos = e + 2
    end
    return count
end

local function extract_bmp_blobs(data, destination, used, stem)
    local count = 0
    local pos = 1
    while true do
        local s = data:find("BM", pos, true)
        if not s then
            break
        end
        if s + 5 > #data then
            break
        end
        local size = le32(data, s + 2)
        if size > 54 and s + size - 1 <= #data then
            local blob = data:sub(s, s + size - 1)
            save_blob(destination, used, stem, "bmp", blob)
            count = count + 1
            pos = s + size
        else
            pos = s + 2
        end
    end
    return count
end

local function write_readme(destination, source_path, count, note)
    local lines = {
        "Webshots extraction",
        "",
        "Source: " .. source_path,
        "Extracted images: " .. tostring(count),
        "Method: " .. note,
        "",
        "If no image is extracted, install NConvert and reopen the file.",
    }
    kkc.write_file(kkc.path_join(destination, "README.txt"), table.concat(lines, "\n") .. "\n")
end

local function extract_webshots(path, destination)
    if not can_handle(path) then
        return false
    end

    local stem = basename_no_ext(path)

    local data = read_all(path)
    local used = {}

    local structured_count = extract_wbc_units(data, destination, used, stem)

    local ok, nconvert_count = try_nconvert(path, destination, stem)

    local fallback_count = 0
    if structured_count == 0 and ((not ok) or nconvert_count <= 1) then
        fallback_count = fallback_count + extract_png_blobs(data, destination, used, stem)
        fallback_count = fallback_count + extract_jpeg_blobs(data, destination, used, stem)
        fallback_count = fallback_count + extract_bmp_blobs(data, destination, used, stem)
    end

    local count = structured_count + nconvert_count + fallback_count

    local method
    if structured_count > 0 and ok then
        method = "wbc structured parser + nconvert"
    elseif structured_count > 0 then
        method = "wbc structured parser"
    elseif ok and fallback_count > 0 then
        method = "nconvert + embedded image scan"
    elseif ok then
        method = "nconvert"
    else
        method = "embedded image scan fallback"
    end

    write_readme(destination, path, count, method)

    if count == 0 then
        kkc.write_file(
            kkc.path_join(destination, "raw.wbc"),
            data
        )
    end

    return true
end

kkc.register_archive_plugin({
    name = "wbc_webshots",
    version = "1.0.0",
    description = "Open Webshots Picture/Collection files",
    mime_types = {
        "image/x-webshots",
        "application/x-webshots",
    },
    extensions = { ".wbc", ".wb1", ".wbz", ".wbd", ".wbp" },
    can_handle = can_handle,
    extract = extract_webshots,
})
