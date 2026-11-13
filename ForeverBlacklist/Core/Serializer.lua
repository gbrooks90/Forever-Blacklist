-- Forever Blacklist: tiny, dependency-free serializer + base64 codec.
-- Output never contains NUL, "|" or control characters, so it is safe for
-- addon messages, chat and edit boxes.
local _, FBL = ...

local S = {}
FBL.Serializer = S

local tostring, tonumber, type, pairs = tostring, tonumber, type, pairs
local format, byte, char, gsub, sub = string.format, string.byte, string.char, string.gsub, string.sub
local floor, concat = math.floor, table.concat

local function escapeChar(c)
    return format("~%02X", byte(c))
end

local function escape(s)
    return (gsub(s, "[%c%^~|\127]", escapeChar))
end

local function unescape(s)
    return (gsub(s, "~(%x%x)", function(h) return char(tonumber(h, 16)) end))
end

local function serializeValue(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "^S" .. escape(v)
    elseif t == "number" then
        if v == floor(v) and v > -1e15 and v < 1e15 then
            out[#out + 1] = format("^N%d", v)
        else
            -- small fractions (map coords) need few digits; anything large keeps full precision
            out[#out + 1] = "^N" .. format((v > -1000 and v < 1000) and "%.6g" or "%.17g", v)
        end
    elseif t == "boolean" then
        out[#out + 1] = v and "^B" or "^b"
    elseif t == "table" then
        out[#out + 1] = "^T"
        for k, val in pairs(v) do
            local kt, vt = type(k), type(val)
            if (kt == "string" or kt == "number") and vt ~= "function" and vt ~= "userdata" and vt ~= "thread" then
                serializeValue(k, out)
                serializeValue(val, out)
            end
        end
        out[#out + 1] = "^t"
    end
end

function S.Serialize(v)
    local out = {}
    serializeValue(v, out)
    return concat(out)
end

function S.Deserialize(str)
    if type(str) ~= "string" or str == "" then return nil, "empty" end
    local tokens, n = {}, 0
    for tag, body in str:gmatch("%^(.)([^%^]*)") do
        n = n + 1
        tokens[n] = { tag, body }
    end
    local pos = 1

    local function read()
        local tok = tokens[pos]
        if not tok then error("truncated", 0) end
        pos = pos + 1
        local tag, body = tok[1], tok[2]
        if tag == "S" then return unescape(body)
        elseif tag == "N" then
            local num = tonumber(body)
            if not num then error("bad number", 0) end
            return num
        elseif tag == "B" then return true
        elseif tag == "b" then return false
        elseif tag == "T" then
            local t = {}
            while true do
                local nxt = tokens[pos]
                if not nxt then error("unterminated table", 0) end
                if nxt[1] == "t" then pos = pos + 1; return t end
                local k = read()
                local val = read()
                t[k] = val
            end
        else
            error("bad tag " .. tostring(tag), 0)
        end
    end

    local ok, result = pcall(read)
    if not ok then return nil, result end
    return result
end

---------------------------------------------------------------------------
-- Base64 (pure Lua 5.1, no bit library needed)
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64DEC = {}
for i = 1, 64 do B64DEC[byte(B64, i)] = i - 1 end

function S.EncodeBase64(data)
    local out, n = {}, 0
    local len = #data
    for i = 1, len, 3 do
        local a, b, c = byte(data, i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = floor(v / 262144) % 64
        local c2 = floor(v / 4096) % 64
        local c3 = floor(v / 64) % 64
        local c4 = v % 64
        n = n + 1
        out[n] = sub(B64, c1 + 1, c1 + 1) .. sub(B64, c2 + 1, c2 + 1)
            .. (b and sub(B64, c3 + 1, c3 + 1) or "=")
            .. (c and sub(B64, c4 + 1, c4 + 1) or "=")
    end
    return concat(out)
end

function S.DecodeBase64(data)
    data = gsub(data, "[^%w%+/=]", "")
    local out, n = {}, 0
    for i = 1, #data, 4 do
        local q1, q2, q3, q4 = byte(data, i, i + 3)
        local d1, d2 = B64DEC[q1], B64DEC[q2]
        if not d1 or not d2 then break end
        local d3 = q3 and B64DEC[q3]
        local d4 = q4 and B64DEC[q4]
        local v = d1 * 262144 + d2 * 4096 + (d3 or 0) * 64 + (d4 or 0)
        n = n + 1
        out[n] = char(floor(v / 65536) % 256)
        if d3 then n = n + 1; out[n] = char(floor(v / 256) % 256) end
        if d4 then n = n + 1; out[n] = char(v % 256) end
    end
    return concat(out)
end

---------------------------------------------------------------------------
-- Compression via the game's C_EncodingUtil when present (Mainline 11.1.5+)
---------------------------------------------------------------------------
local function compress(s)
    local EU = _G.C_EncodingUtil
    if not (EU and EU.CompressString and Enum and Enum.CompressionMethod) then return nil end
    local ok, res = pcall(EU.CompressString, s, Enum.CompressionMethod.Deflate)
    if ok and type(res) == "string" then return res end
end

local function decompress(s)
    local EU = _G.C_EncodingUtil
    if not (EU and EU.DecompressString and Enum and Enum.CompressionMethod) then return nil end
    local ok, res = pcall(EU.DecompressString, s, Enum.CompressionMethod.Deflate)
    if ok and type(res) == "string" then return res end
end

--- Packs a value for the wire: "Z" + base64(deflate) when that is smaller, else "R" + raw.
function S.Pack(v)
    local raw = S.Serialize(v)
    if #raw > 120 then
        local z = compress(raw)
        if z then
            local enc = S.EncodeBase64(z)
            if #enc + 1 < #raw then return "Z" .. enc end
        end
    end
    return "R" .. raw
end

function S.Unpack(s)
    if type(s) ~= "string" then return nil end
    local mode, body = sub(s, 1, 1), sub(s, 2)
    if mode == "Z" then
        local raw = decompress(S.DecodeBase64(body))
        if not raw then return nil, "decompress failed" end
        return S.Deserialize(raw)
    elseif mode == "R" then
        return S.Deserialize(body)
    end
    return nil, "unknown mode"
end

--- Human-shareable export string.
function S.Export(v)
    return "FBL1:" .. S.EncodeBase64(S.Pack(v))
end

function S.Import(str)
    str = (str or ""):gsub("%s", "")
    local body = str:match("^FBL1:(.+)$")
    if not body then return nil, "Not a Forever Blacklist export string" end
    return S.Unpack(S.DecodeBase64(body))
end
