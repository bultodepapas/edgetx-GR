-- Mock EdgeTX firmware environment for headless GaugeV2 testing.
-- Provides lvgl/lcd/telemetry/script globals as plain Lua (Lua 5.3).

local M = {}

local objects = {}
local objectCount = 0

local function makeObject(kind, params)
  objectCount = objectCount + 1
  local props = {}
  for k, v in pairs(params or {}) do props[k] = v end
  local obj = {
    kind = kind,
    params = params or {},
    props = props,
    sets = {},
    visible = true,
    hiddenByMe = false,
  }
  objects[objectCount] = obj
  return obj
end

local function recordSet(obj, params)
  local entry = {}
  for k, v in pairs(params) do
    entry[k] = v
    obj.props[k] = v
  end
  obj.sets[#obj.sets + 1] = entry
end

local lvgl = {
  LCD_SCALE = 1.0,
  _objects = objects,
  _count = function() return objectCount end,
  arc = function(p) return makeObject("arc", p) end,
  line = function(p) return makeObject("line", p) end,
  circle = function(p) return makeObject("circle", p) end,
  label = function(p) return makeObject("label", p) end,
  box = function(p) return makeObject("box", p) end,
  rectangle = function(p) return makeObject("rectangle", p) end,
  triangle = function(p) return makeObject("triangle", p) end,
  set = function(obj, params) recordSet(obj, params) end,
  show = function(obj) obj.visible = true; obj.hiddenByMe = false end,
  hide = function(obj) obj.visible = false; obj.hiddenByMe = true end,
  clear = function(obj)
    if obj then
      obj.props = {}
    else
      objects = {}
      objectCount = 0
      lvgl._objects = objects
      lvgl._count = function() return objectCount end
    end
  end,
}

local lcd = {
  sizeText = function(text, flags)
    local n = #tostring(text)
    local h = 16
    if flags and flags >= 0x400 then h = 22 end
    if flags and flags >= 0x500 then h = 32 end
    if flags and flags >= 0x600 then h = 48 end
    return n * (h / 2), h
  end,
  RGB = function(r, g, b) return 0x10000 + r * 0x10000 + g * 0x100 + b end,
}

local function install(env)
  env.lvgl = lvgl
  env.lcd = lcd
  env.RED = 0x2000
  env.GREEN = 0x4000
  env.COLOR_THEME_PRIMARY1 = 0x1001
  env.COLOR_THEME_PRIMARY2 = 0x1002
  env.COLOR_THEME_PRIMARY3 = 0x1003
  env.COLOR_THEME_SECONDARY1 = 0x2001
  env.COLOR_THEME_SECONDARY2 = 0x2002
  env.COLOR_THEME_SECONDARY3 = 0x2003
  env.COLOR_THEME_FOCUS = 0x3001
  env.COLOR_THEME_EDIT = 0x3002
  env.COLOR_THEME_ACTIVE = 0x3003
  env.COLOR_THEME_WARNING = 0x4001
  env.COLOR_THEME_DISABLED = 0x5001
  -- Simulate EdgeTX Lua: the string metatable is NOT installed (the firmware
  -- only builds it with LUA_ENABLE_STRLIB_MT), so "s:method()" must fail
  -- exactly like it does on the radio.
  if debug and debug.setmetatable then
    debug.setmetatable("", nil)
  end
end

M.lvgl = lvgl
M.lcd = lcd
M.install = install
M.makeObject = makeObject

return M
