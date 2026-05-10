local kkc = require("kkc")

local ENCRYPTION_RAND_SEED = 9338638
local ENCRYPTION_STRING = "My\x01\xde\x04Jibzle"
local MAX_ASSET_FILE_LEN = 100
local MAX_DATA_FILE_LEN = 50
local V10_LIB_FILE_LEN = 20
local V10_ASSET_FILE_LEN = 25
local SINGLE_FILE_PSW_LEN = 13

local function le16(data, pos)
    local b1, b2 = data:byte(pos, pos + 1)
    assert(b1 and b2, "unexpected end of AGS archive")
    return b1 | (b2 << 8)
end

local function le32(data, pos)
    local b1, b2, b3, b4 = data:byte(pos, pos + 3)
    assert(b1 and b2 and b3 and b4, "unexpected end of AGS archive")
    return b1 | (b2 << 8) | (b3 << 16) | (b4 << 24)
end

local function le64(data, pos)
    local lo = le32(data, pos)
    local hi = le32(data, pos + 4)
    return lo | (hi << 32)
end

local function sanitize_path(path)
    path = path:gsub("\\", "/")
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part ~= "" and part ~= "." and part ~= ".." then
            table.insert(parts, (part:gsub("[:%z]", "_")))
        end
    end
    if #parts == 0 then
        return "unnamed"
    end
    return table.concat(parts, "/")
end

local function base_name(path)
    local normalized = path:gsub("\\", "/")
    return normalized:match("([^/]+)$") or normalized
end

local function dir_name(path)
    local normalized = path:gsub("\\", "/")
    return normalized:match("^(.*)/[^/]*$") or "."
end

local function read_c_string(data, pos)
    local end_pos = data:find("\0", pos, true)
    assert(end_pos, "unterminated AGS string")
    return data:sub(pos, end_pos - 1), end_pos + 1
end

local function read_fixed_string(data, pos, len)
    local text = data:sub(pos, pos + len - 1)
    local nul = text:find("\0", 1, true)
    if nul then
        text = text:sub(1, nul - 1)
    end
    return text, pos + len
end

local function decrypt_text(text)
    local bytes = { text:byte(1, #text) }
    local key_len = #ENCRYPTION_STRING
    for idx = 1, #bytes do
        bytes[idx] = (bytes[idx] - ENCRYPTION_STRING:byte(((idx - 1) % key_len) + 1)) & 0xff
        if bytes[idx] == 0 then
            break
        end
    end
    return string.char(table.unpack(bytes)):match("^[^\0]*") or ""
end

local function next_pseudo_rand(rand_val)
    rand_val = (rand_val * 214013 + 2531011) & 0xffffffff
    return (((rand_val >> 16) & 0x7fff)), rand_val
end

local function read_enc_bytes(data, pos, count, rand_val)
    local out = {}
    for idx = 1, count do
        local byte = data:byte(pos)
        assert(byte, "unexpected end of encoded AGS archive")
        local rnd
        rnd, rand_val = next_pseudo_rand(rand_val)
        out[idx] = (byte - rnd) & 0xff
        pos = pos + 1
    end
    return out, pos, rand_val
end

local function read_enc_int8(data, pos, rand_val)
    local bytes
    bytes, pos, rand_val = read_enc_bytes(data, pos, 1, rand_val)
    local value = bytes[1]
    if value >= 0x80 then
        value = value - 0x100
    end
    return value, pos, rand_val
end

local function read_enc_int32(data, pos, rand_val)
    local bytes
    bytes, pos, rand_val = read_enc_bytes(data, pos, 4, rand_val)
    local value = bytes[1] | (bytes[2] << 8) | (bytes[3] << 16) | (bytes[4] << 24)
    if value >= 0x80000000 then
        value = value - 0x100000000
    end
    return value, pos, rand_val
end

local function read_enc_string(data, pos, max_len, rand_val)
    local out = {}
    local idx = 1
    while idx < max_len do
        local byte = data:byte(pos)
        assert(byte, "unexpected end of encoded AGS string")
        local rnd
        rnd, rand_val = next_pseudo_rand(rand_val)
        local value = (byte - rnd) & 0xff
        pos = pos + 1
        if value == 0 then
            break
        end
        out[idx] = string.char(value)
        idx = idx + 1
    end
    return table.concat(out), pos, rand_val
end

local function open_binary(path)
    local file = assert(io.open(path, "rb"))
    return file
end

local function read_all(path)
    local file = open_binary(path)
    local data = assert(file:read("*all"))
    file:close()
    return data
end

local function parse_single_lib(data, pos)
    local passwmodifier = data:byte(pos)
    assert(passwmodifier, "truncated AGS header")
    pos = pos + 2 -- modifier + unused byte
    local asset_count = le16(data, pos)
    pos = pos + 2
    pos = pos + SINGLE_FILE_PSW_LEN

    local assets = {}
    for _ = 1, asset_count do
        local name_data = data:sub(pos, pos + SINGLE_FILE_PSW_LEN - 1)
        pos = pos + SINGLE_FILE_PSW_LEN
        local bytes = { name_data:byte(1, #name_data) }
        for idx = 1, #bytes do
            if bytes[idx] == 0 then
                break
            end
            bytes[idx] = (bytes[idx] - passwmodifier) & 0xff
        end
        table.insert(assets, {
            name = sanitize_path((string.char(table.unpack(bytes)):match("^[^\0]*") or "")),
            libuid = 0,
        })
    end
    for idx = 1, asset_count do
        assets[idx].size = le32(data, pos)
        pos = pos + 4
    end
    pos = pos + (2 * asset_count)
    local offset = pos - 1
    for idx = 1, asset_count do
        assets[idx].offset = offset
        offset = offset + assets[idx].size
    end
    return { lib_files = {}, assets = assets }
end

local function parse_v10(data, pos, version)
    local lib_count = le32(data, pos)
    pos = pos + 4
    local lib_files = {}
    for idx = 1, lib_count do
        lib_files[idx], pos = read_fixed_string(data, pos, V10_LIB_FILE_LEN)
    end
    local asset_count = le32(data, pos)
    pos = pos + 4
    local assets = {}
    for idx = 1, asset_count do
        local name
        name, pos = read_fixed_string(data, pos, V10_ASSET_FILE_LEN)
        if version >= 11 then
            name = decrypt_text(name)
        end
        assets[idx] = { name = sanitize_path(name) }
    end
    for idx = 1, asset_count do
        assets[idx].offset = le32(data, pos)
        pos = pos + 4
    end
    for idx = 1, asset_count do
        assets[idx].size = le32(data, pos)
        pos = pos + 4
    end
    for idx = 1, asset_count do
        assets[idx].libuid = data:byte(pos) or 0
        pos = pos + 1
    end
    return { lib_files = lib_files, assets = assets }
end

local function parse_v20(data, pos)
    local lib_count = le32(data, pos)
    pos = pos + 4
    local lib_files = {}
    for idx = 1, lib_count do
        lib_files[idx], pos = read_fixed_string(data, pos, MAX_DATA_FILE_LEN)
    end
    local asset_count = le32(data, pos)
    pos = pos + 4
    local assets = {}
    for idx = 1, asset_count do
        local len = le16(data, pos)
        pos = pos + 2
        len = math.floor(len / 5)
        local name = data:sub(pos, pos + len - 1)
        pos = pos + len
        assets[idx] = { name = sanitize_path(decrypt_text(name)) }
    end
    for idx = 1, asset_count do
        assets[idx].offset = le32(data, pos)
        pos = pos + 4
    end
    for idx = 1, asset_count do
        assets[idx].size = le32(data, pos)
        pos = pos + 4
    end
    for idx = 1, asset_count do
        assets[idx].libuid = data:byte(pos) or 0
        pos = pos + 1
    end
    return { lib_files = lib_files, assets = assets }
end

local function parse_v21(data, pos)
    local rand_val = (le32(data, pos) + ENCRYPTION_RAND_SEED) & 0xffffffff
    pos = pos + 4
    local lib_count
    lib_count, pos, rand_val = read_enc_int32(data, pos, rand_val)
    local lib_files = {}
    for idx = 1, lib_count do
        lib_files[idx], pos, rand_val = read_enc_string(data, pos, MAX_DATA_FILE_LEN, rand_val)
    end
    local asset_count
    asset_count, pos, rand_val = read_enc_int32(data, pos, rand_val)
    local assets = {}
    for idx = 1, asset_count do
        local name
        name, pos, rand_val = read_enc_string(data, pos, MAX_ASSET_FILE_LEN, rand_val)
        assets[idx] = { name = sanitize_path(name) }
    end
    for idx = 1, asset_count do
        local value
        value, pos, rand_val = read_enc_int32(data, pos, rand_val)
        assets[idx].offset = value & 0xffffffff
    end
    for idx = 1, asset_count do
        local value
        value, pos, rand_val = read_enc_int32(data, pos, rand_val)
        assets[idx].size = value & 0xffffffff
    end
    for idx = 1, asset_count do
        local value
        value, pos, rand_val = read_enc_int8(data, pos, rand_val)
        assets[idx].libuid = value & 0xff
    end
    return { lib_files = lib_files, assets = assets }
end

local function parse_v30(data, pos)
    pos = pos + 4 -- reserved flags
    local lib_count = le32(data, pos)
    pos = pos + 4
    local lib_files = {}
    for idx = 1, lib_count do
        lib_files[idx], pos = read_c_string(data, pos)
    end
    local asset_count = le32(data, pos)
    pos = pos + 4
    local assets = {}
    for idx = 1, asset_count do
        local name
        name, pos = read_c_string(data, pos)
        local libuid = data:byte(pos)
        assert(libuid, "truncated AGS asset record")
        pos = pos + 1
        local offset = le64(data, pos)
        pos = pos + 8
        local size = le64(data, pos)
        pos = pos + 8
        assets[idx] = {
            name = sanitize_path(name),
            libuid = libuid,
            offset = offset,
            size = size,
        }
    end
    return { lib_files = lib_files, assets = assets }
end

local function parse_archive(path)
    local data = read_all(path)
    assert(data:sub(1, 5) == "CLIB\x1a", "unsupported AGS archive signature")

    local version = data:byte(6)
    assert(version, "missing AGS archive version")
    local pos = 7

    local parsed
    if version >= 10 then
        local lib_index = data:byte(pos)
        assert(lib_index == 0, "not the base AGS archive part")
        pos = pos + 1
        if version >= 30 then
            parsed = parse_v30(data, pos)
        elseif version >= 21 then
            parsed = parse_v21(data, pos)
        elseif version == 20 then
            parsed = parse_v20(data, pos)
        else
            parsed = parse_v10(data, pos, version)
        end
    else
        parsed = parse_single_lib(data, pos)
    end

    parsed.version = version
    parsed.lib_files[1] = base_name(path)
    return parsed
end

local function load_library_parts(path, lib_files)
    local base_dir = dir_name(path)
    local parts = {}
    for idx, lib_file in ipairs(lib_files) do
        local resolved = idx == 1 and path or kkc.path_join(base_dir, lib_file)
        parts[idx - 1] = read_all(resolved)
    end
    return parts
end

local function extract_ags_archive(path, destination)
    local archive = parse_archive(path)
    local parts = load_library_parts(path, archive.lib_files)

    for _, asset in ipairs(archive.assets) do
        local lib_data = parts[asset.libuid]
        assert(lib_data, "missing AGS library part " .. tostring(asset.libuid))
        local start_pos = asset.offset + 1
        local end_pos = start_pos + asset.size - 1
        assert(end_pos <= #lib_data, "AGS asset exceeds library boundaries: " .. asset.name)
        local output_path = kkc.path_join(destination, asset.name)
        kkc.write_file(output_path, lib_data:sub(start_pos, end_pos))
    end

    return true
end

kkc.register_archive_plugin({
    extract = extract_ags_archive,
})