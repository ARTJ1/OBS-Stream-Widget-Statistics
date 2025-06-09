--
-- json.lua
--
-- Copyright (c) 2020 rxi
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

local json = { _version = "0.1.2" }

-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

local encode

local escape_char_map = {
  [ "\\" ] = "\\\\",
  [ "\"" ] = "\\\"",
  [ "\b" ] = "\\b",
  [ "\f" ] = "\\f",
  [ "\n" ] = "\\n",
  [ "\r" ] = "\\r",
  [ "\t" ] = "\\t",
}

local function escape_char(c)
  return escape_char_map[c] or string.format("\\u%04x", c:byte())
end

local function encode_string(str)
  return '"' .. str:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function encode_array(arr)
  local buf = { "[" }
  for i, v in ipairs(arr) do
    buf[#buf + 1] = encode(v)
    buf[#buf + 1] = ","
  end
  if #buf > 1 then
    buf[#buf] = nil
  end
  buf[#buf + 1] = "]"
  return table.concat(buf)
end

local function encode_table(tbl)
  local buf = { "{" }
  for k, v in pairs(tbl) do
    if type(k) ~= "string" then
      error("table keys must be strings")
    end
    buf[#buf + 1] = encode_string(k)
    buf[#buf + 1] = ":"
    buf[#buf + 1] = encode(v)
    buf[#buf + 1] = ","
  end
  if #buf > 1 then
    buf[#buf] = nil
  end
  buf[#buf + 1] = "}"
  return table.concat(buf)
end

function encode(val)
  local typ = type(val)
  if typ == "string" then
    return encode_string(val)
  elseif typ == "number" then
    return tostring(val)
  elseif typ == "boolean" then
    return val and "true" or "false"
  elseif typ == "table" then
    if rawget(val, 1) ~= nil then
      return encode_array(val)
    else
      return encode_table(val)
    end
  elseif typ == "nil" then
    return "null"
  else
    error("unsupported type: " .. typ)
  end
end

function json.encode(val)
  return encode(val)
end

-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local decode
local max_depth = 512
local table_mt = { __index = {} }
local array_mt = { __index = {} }

local space_chars = {
  [" "] = true, ["\t"] = true, ["\r"] = true, ["\n"] = true
}

local function next_char(str, i, char_set, err_if_eof)
  while i <= #str and char_set[str:sub(i, i)] do
    i = i + 1
  end
  if err_if_eof and i > #str then
    error("unexpected EOF")
  end
  return i
end

local function decode_error(str, i, msg)
  local line = 1
  local col = 1
  for j = 1, i - 1 do
    if str:sub(j, j) == "\n" then
      line = line + 1
      col = 1
    else
      col = col + 1
    end
  end
  error(string.format("%s at line %d col %d", msg, line, col))
end

local function parse_string(str, i)
  local chr = str:sub(i, i)
  if chr ~= '"' then
    decode_error(str, i, "expected '\"'")
  end
  local j = i + 1
  local res = { }
  while j <= #str do
    chr = str:sub(j, j)
    if chr == '"' then
      j = j + 1
      break
    elseif chr == '\\' then
      local escaped = str:sub(j + 1, j + 1)
      if escaped == 'b' then
        res[#res + 1] = '\b'
      elseif escaped == 'f' then
        res[#res + 1] = '\f'
      elseif escaped == 'n' then
        res[#res + 1] = '\n'
      elseif escaped == 'r' then
        res[#res + 1] = '\r'
      elseif escaped == 't' then
        res[#res + 1] = '\t'
      elseif escaped == 'u' then
        local hex = str:sub(j + 2, j + 5)
        local c = tonumber(hex, 16)
        if not c then
          decode_error(str, j, "invalid unicode escape")
        end
        res[#res + 1] = string.char(c)
        j = j + 4
      else
        res[#res + 1] = escaped
      end
      j = j + 2
    else
      res[#res + 1] = chr
      j = j + 1
    end
  end
  return table.concat(res), j
end

local function parse_number(str, i)
  local j = i
  while j <= #str do
    local chr = str:sub(j, j)
    if not (chr:find("[0-9%.Ee%-+]")) then
      break
    end
    j = j + 1
  end
  local num = tonumber(str:sub(i, j - 1))
  if not num then
    decode_error(str, i, "invalid number")
  end
  return num, j
end

local function parse_literal(str, i)
  local literals = {
    ["true"] = true,
    ["false"] = false,
    ["null"] = nil
  }
  for k, v in pairs(literals) do
    if str:sub(i, i + #k - 1) == k then
      return v, i + #k
    end
  end
  decode_error(str, i, "invalid literal")
end

local function parse_array(str, i, depth)
  if depth > max_depth then
    error("max depth exceeded")
  end
  local chr = str:sub(i, i)
  if chr ~= "[" then
    decode_error(str, i, "expected '['")
  end
  local res = setmetatable({}, array_mt)
  i = next_char(str, i + 1, space_chars, true)
  if str:sub(i, i) == "]" then
    return res, i + 1
  end
  while true do
    local val, ni = decode(str, i, depth + 1)
    res[#res + 1] = val
    i = next_char(str, ni, space_chars, true)
    local chr2 = str:sub(i, i)
    i = i + 1
    if chr2 == "]" then break end
    if chr2 ~= "," then decode_error(str, i, "expected ']' or ','") end
  end
  return res, i
end

local function parse_table(str, i, depth)
  if depth > max_depth then
    error("max depth exceeded")
  end
  local chr = str:sub(i, i)
  if chr ~= "{" then
    decode_error(str, i, "expected '{'")
  end
  local res = setmetatable({}, table_mt)
  i = next_char(str, i + 1, space_chars, true)
  if str:sub(i, i) == "}" then
    return res, i + 1
  end
  while true do
    -- Read key
    local key, ni = parse_string(str, i)
    i = next_char(str, ni, space_chars, true)
    -- Check for ':'
    local chr2 = str:sub(i, i)
    if chr2 ~= ":" then
      decode_error(str, i, "expected ':' after key")
    end
    i = next_char(str, i + 1, space_chars, true)
    -- Read value
    local val, nni = decode(str, i, depth + 1)
    -- Set
    res[key] = val
    -- Next token
    i = next_char(str, nni, space_chars, true)
    local chr3 = str:sub(i, i)
    i = i + 1
    if chr3 == "}" then break end
    if chr3 ~= "," then decode_error(str, i, "expected '}' or ','") end
  end
  return res, i
end

local char_func_map = {
  [ '"' ] = parse_string,
  [ "0" ] = parse_number,
  [ "1" ] = parse_number,
  [ "2" ] = parse_number,
  [ "3" ] = parse_number,
  [ "4" ] = parse_number,
  [ "5" ] = parse_number,
  [ "6" ] = parse_number,
  [ "7" ] = parse_number,
  [ "8" ] = parse_number,
  [ "9" ] = parse_number,
  [ "-" ] = parse_number,
  [ "t" ] = parse_literal,
  [ "f" ] = parse_literal,
  [ "n" ] = parse_literal,
  [ "[" ] = parse_array,
  [ "{" ] = parse_table,
}

function decode(str, i, depth)
  depth = depth or 0
  i = next_char(str, i or 1, space_chars, true)
  local chr = str:sub(i, i)
  local func = char_func_map[chr]
  if not func then
    decode_error(str, i, "unexpected character '" .. chr .. "'")
  end
  return func(str, i, depth)
end

function json.decode(str)
  return decode(str)
end

return json