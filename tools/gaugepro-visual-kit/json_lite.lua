-- Minimal JSON encoder shared by defs_dump.lua and scenes_dump.lua. No
-- external dependency (EdgeTX's embedded Lua ships no JSON library, and
-- this only ever needs to go ONE way: Lua table -> JSON text).
--
-- Uses string.* functions throughout, never the s:method() sugar:
-- tests/mock_env.lua's install() strips the string metatable to match the
-- firmware (EdgeTX Lua builds without LUA_ENABLE_STRLIB_MT), so both
-- callers load this AFTER mock.install() has already done that.

local M = {}

local function jsonStr(s)
  local out = { '"' }
  for i = 1, string.len(s) do
    local c = string.sub(s, i, i)
    local b = string.byte(c)
    if c == '"' then out[#out + 1] = '\\"'
    elseif c == '\\' then out[#out + 1] = '\\\\'
    elseif b < 0x20 then out[#out + 1] = string.format('\\u%04x', b)
    else out[#out + 1] = c end
  end
  out[#out + 1] = '"'
  return table.concat(out)
end

local jsonValue

local function jsonArray(t, n)
  local parts = {}
  for i = 1, n do parts[i] = jsonValue(t[i]) end
  return "[" .. table.concat(parts, ",") .. "]"
end

local function jsonObject(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for i = 1, #keys do
    local k = keys[i]
    parts[i] = jsonStr(tostring(k)) .. ":" .. jsonValue(t[k])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- `skip(v)` (optional): return true to encode a value as null instead of
-- erroring - used to drop non-serializable fields (e.g. scenes.lua's `post`
-- closures) without the caller having to strip them beforehand.
local skipFn

jsonValue = function(v)
  if v == nil then return "null" end
  if skipFn and skipFn(v) then return "null" end
  local t = type(v)
  if t == "number" then return tostring(v) end
  if t == "string" then return jsonStr(v) end
  if t == "boolean" then return v and "true" or "false" end
  if t == "table" then
    local n = #v
    local isArray = (n > 0)
    for k in pairs(v) do
      if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
        isArray = false
        break
      end
    end
    if isArray then return jsonArray(v, n) end
    if next(v) == nil then return "{}" end
    return jsonObject(v)
  end
  return "null"  -- functions, userdata, threads: silently null unless
                 -- skip() was meant to catch them (see encode()'s doc)
end

-- encode(value [, skip]): `skip(v)` lets the caller flag values (e.g.
-- `type(v) == "function"`) to encode as null explicitly, documenting the
-- omission instead of relying on the fallback above.
function M.encode(value, skip)
  skipFn = skip
  local ok, result = pcall(jsonValue, value)
  skipFn = nil
  if not ok then error(result, 0) end
  return result
end

function M.writeFile(path, value, skip)
  local text = M.encode(value, skip)
  local f, err = io.open(path, "wb")
  if not f then error("json_lite: cannot write " .. path .. ": " .. tostring(err)) end
  f:write(text)
  f:write("\n")
  f:close()
end

return M
