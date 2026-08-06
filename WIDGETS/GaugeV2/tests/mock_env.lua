-- Mock EdgeTX firmware environment for headless GaugeV2 testing (Lua 5.3).
--
-- Fidelity rules enforced here, each verified against radio/src:
--
--  * Per-object property allow-lists exactly as the C++ parseParam chains
--    accept them (lua_lvgl_widget.cpp / .h). In particular:
--      - lvgl.triangle takes ONLY pts + base params (LvglSimpleWidgetObject);
--        no filled / thickness / rounded.
--      - dashGap / dashWidth live on LvglWidgetLineBase (hline, vline), NOT
--        on the free-angle LvglWidgetLine.
--      - lvgl.circle has no bgColor / bgOpacity.
--  * pts must be arrays of {x, y} pairs (getPt reads rawgeti 1 and 2);
--    a triangle must carry exactly three points.
--  * The string metatable is absent (the firmware builds without
--    LUA_ENABLE_STRLIB_MT), so "s:lower()" must fail here too.
--  * getTime() counts 10 ms ticks; getSourceValue() returns three values.
--  * Widget options reach Lua as NUMBERS (lua_widget.cpp updateWithoutRefresh)
--    and CHOICE values are 1-based (widget_settings.cpp). makeOptions()
--    below converts readable test input into that wire format, so tests stay
--    legible without lying about the contract.

local M = {}

local objects = {}
local objectCount = 0

local BASE_KEYS = {
  x = true, y = true, w = true, h = true, color = true, opacity = true,
  visible = true, size = true, pos = true, floating = true,
  children = true, type = true, name = true,
}

local KEYS = {
  -- LvglWidgetArc : RoundObject (radius, thickness, filled) + Rounded
  arc = { startAngle = true, endAngle = true, bgStartAngle = true,
          bgEndAngle = true, bgColor = true, bgOpacity = true,
          radius = true, thickness = true, filled = true, rounded = true },
  -- LvglWidgetLine : Rounded + Thickness (no dash params)
  line = { pts = true, thickness = true, rounded = true },
  -- LvglWidgetLineBase : Rounded + dash params
  hline = { thickness = true, rounded = true, dashGap = true,
            dashWidth = true },
  vline = { thickness = true, rounded = true, dashGap = true,
            dashWidth = true },
  -- LvglWidgetTriangle : LvglSimpleWidgetObject + pts only
  triangle = { pts = true },
  circle = { radius = true, thickness = true, filled = true },
  rectangle = { rounded = true, thickness = true, filled = true },
  label = { text = true, font = true, align = true },
  box = { align = true, flexFlow = true, flexPad = true, borderPad = true,
          active = true },
}

-- Memoized per kind: checkParams runs on EVERY lvgl.set, so a fresh table
-- per call would make the harness the dominant per-frame allocator in the
-- byte probes (dev/measure_frames.lua) - the widget would measure fine but
-- the mock would drown it. The result is read-only.
local allowedCache = {}
local function allowedKeys(kind)
  local t = allowedCache[kind]
  if t then return t end
  t = {}
  for k in pairs(BASE_KEYS) do t[k] = true end
  for k in pairs(KEYS[kind] or {}) do t[k] = true end
  allowedCache[kind] = t
  return t
end

local function checkPts(kind, pts)
  local n = #pts
  if kind == "triangle" then
    if n ~= 3 then
      error("mock: triangle needs exactly 3 points, got " .. n, 4)
    end
  elseif n < 2 then
    error("mock: pts must have at least 2 points", 4)
  end
  for i = 1, n do
    local pt = pts[i]
    if type(pt) ~= "table" or #pt < 2
       or type(pt[1]) ~= "number" or type(pt[2]) ~= "number" then
      error(string.format("mock: pts[%d] must be {x, y}", i), 4)
    end
    -- Binding fidelity: LvglWidgetLine::getPt reads the coordinates with
    -- luaL_checkunsigned (lua_lvgl_widget.cpp:1001,1004), so a negative
    -- coordinate raises a Lua error ON THE RADIO - the widget disables
    -- itself (Tanda 6 F-1, third door; 5.1 TRAP 1). The mock enforces it
    -- so the harness can never hide that class of bug.
    if pt[1] < 0 or pt[2] < 0 then
      error(string.format("mock: pts[%d] negative coordinate (%d,%d)"
        .. " - luaL_checkunsigned raises on the radio", i, pt[1], pt[2]), 4)
    end
  end
end

local function checkParams(kind, params)
  local allowed = allowedKeys(kind)
  for k in pairs(params) do
    if not allowed[k] then
      error(string.format("mock: invalid property '%s' for %s", k, kind), 3)
    end
  end
  if params.pts then checkPts(kind, params.pts) end
end

local function makeObject(kind, params)
  objectCount = objectCount + 1
  checkParams(kind, params)
  local props = {}
  for k, v in pairs(params or {}) do props[k] = v end
  local obj = {
    kind = kind,
    params = params or {},
    props = props,
    sets = {},
    setCount = 0,
    visible = true,
  }
  objects[objectCount] = obj
  return obj
end

-- Retain every lvgl.set params copy in obj.sets (the suite's audit trail:
-- P2-2 batching tests, the set-count ratchets, the gallery census all read
-- it). The retention is UNBOUNDED by design - it is harness instrumentation,
-- not widget state - so allocation probes turn it off to measure the widget
-- alone (dev/measure_frames.lua, the Tanda 6 F-11 methodology).
local tracking = true

local function recordSet(obj, params)
  checkParams(obj.kind, params)
  for k, v in pairs(params) do
    obj.props[k] = v
  end
  if tracking then
    local entry = {}
    for k, v in pairs(params) do
      entry[k] = v
    end
    obj.sets[#obj.sets + 1] = entry
    obj.setCount = obj.setCount + 1
  end
end

local lvgl = {
  LCD_SCALE = 1.0,
  FLOW_ROW = 0, FLOW_COLUMN = 1,
  _objects = objects,
  arc = function(p) return makeObject("arc", p) end,
  line = function(p) return makeObject("line", p) end,
  hline = function(p) return makeObject("hline", p) end,
  vline = function(p) return makeObject("vline", p) end,
  triangle = function(p) return makeObject("triangle", p) end,
  circle = function(p) return makeObject("circle", p) end,
  rectangle = function(p) return makeObject("rectangle", p) end,
  label = function(p) return makeObject("label", p) end,
  box = function(p) return makeObject("box", p) end,
  set = function(obj, params) recordSet(obj, params) end,
  show = function(obj) obj.visible = true end,
  hide = function(obj) obj.visible = false end,
  isFullScreen = function() return false end,
  clear = function(obj)
    if obj then
      obj.props = {}
    else
      for i = 1, objectCount do objects[i] = nil end
      objectCount = 0
    end
  end,
}

function M.objectCount() return objectCount end

function M.objects() return objects end

-- All objects of a kind, in creation order.
function M.byKind(kind)
  local out = {}
  for i = 1, objectCount do
    if objects[i] and objects[i].kind == kind then out[#out + 1] = objects[i] end
  end
  return out
end

function M.totalSets()
  local n = 0
  for i = 1, objectCount do
    if objects[i] then n = n + objects[i].setCount end
  end
  return n
end

local lcd = {
  -- Rough but monotonic metrics: width scales with the font height, which is
  -- what the layout code reasons about.
  sizeText = function(text, flags)
    local h = 16
    if flags then
      if flags >= 0x600 then h = 48
      elseif flags >= 0x500 then h = 32
      elseif flags >= 0x400 then h = 24
      elseif flags >= 0x300 then h = 13
      elseif flags >= 0x200 then h = 11
      end
    end
    return math.floor(#tostring(text) * (h * 0.55)), h
  end,
  RGB = function(r, g, b) return 0x100000 + r * 0x10000 + g * 0x100 + b end,
  drawText = function() end,
}

-- ---- simulated radio state ----------------------------------------------

local sim = {
  ticks = 0,                 -- getTime(), 10 ms ticks
  rssi = 100,
  version = { "3.0.0", "sim", 3, 0, 0, "edgetx" },
  values = {},               -- source id -> number | table | nil
  current = {},              -- source id -> bool
  fresh = {},
  fields = {},               -- id -> { id, name, unit }
  byName = {},               -- name -> id
  sensors = {},              -- index -> { name, prec, unit }
  switches = {},             -- swsrc_t -> boolean, distinct from `values`
  sensorResets = {},         -- model.resetSensor(i) call log
  tones = {},
  haptics = {},
}
M.sim = sim

function M.reset()
  lvgl.clear()
  sim.ticks = 0
  sim.rssi = 100
  sim.values = {}
  sim.current = {}
  sim.fresh = {}
  sim.fields = {}
  sim.byName = {}
  sim.sensors = {}
  sim.switches = {}
  sim.sensorResets = {}
  sim.tones = {}
  sim.haptics = {}
end

-- Set a SWITCH option's simulated state. Deliberately a separate store from
-- setValue()/sim.values: getSwitchValue() and getValue() read different id
-- spaces on real firmware (a swsrc_t vs a MIXSRC id), and code that confuses
-- the two (AUDIT.md P0-1) must fail here too.
function M.setSwitch(id, active)
  sim.switches[id] = active and true or false
end

-- Register a source in the simulated radio.
function M.addField(id, name, unit)
  sim.fields[id] = { id = id, name = name, unit = unit }
  sim.byName[name] = id
  return id
end

function M.setValue(id, value, current, fresh)
  sim.values[id] = value
  sim.current[id] = (current == nil) and true or current
  sim.fresh[id] = fresh
end

function M.advance(ms)
  sim.ticks = sim.ticks + math.floor(ms / 10)
end

-- ---- option wire format --------------------------------------------------

-- Convert readable overrides into the integer wire format the firmware uses.
--   makeOptions(defs, { Style = "Needle", Min = 0 })
-- Choice values may be given as a label or as a 1-based index.
function M.makeOptions(defs, overrides)
  overrides = overrides or {}
  local out = {}
  for i = 1, #defs do
    local d = defs[i]
    local given = overrides[d.key]
    if d.type == CHOICE then
      local v = d.default
      if type(given) == "string" then
        for j = 1, #d.choices do
          if d.choices[j] == given then v = j end
        end
      elseif given ~= nil then
        v = given
      end
      out[d.key] = v
    elseif d.type == STRING then
      out[d.key] = (given ~= nil) and given or (d.default or "")
    elseif d.type == SOURCE then
      out[d.key] = tonumber(given) or 0
    elseif d.type == BOOL then
      if given == nil then out[d.key] = d.default
      elseif given == true then out[d.key] = 1
      elseif given == false then out[d.key] = 0
      else out[d.key] = given end
    else
      out[d.key] = (given ~= nil) and given or d.default
    end
  end
  return out
end

-- Only the options a given firmware capacity would deliver.
function M.limitOptions(defs, options, capacity)
  local out, n = {}, 0
  for i = 1, #defs do
    local d = defs[i]
    local needs = (d.since == 212) and 50 or 10
    if needs <= capacity and n < capacity then
      n = n + 1
      out[d.key] = options[d.key]
    end
  end
  return out
end

-- ---- installation --------------------------------------------------------

local function install(env)
  env.lvgl = lvgl
  env.lcd = lcd

  -- colours (api_colorlcd.cpp COLOR2FLAGS values; only identity matters here)
  env.RED = 0x2000
  env.GREEN = 0x4000
  env.WHITE = 0x5000
  env.BLACK = 0x5001
  env.YELLOW = 0x5002
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

  -- font flags (etcxcst): font index << 8
  env.STDSIZE = 0x000
  env.BOLD = 0x100
  env.TINSIZE = 0x200
  env.SMLSIZE = 0x300
  env.MIDSIZE = 0x400
  env.DBLSIZE = 0x500
  env.XXLSIZE = 0x600
  env.XLSIZE = 0x700

  -- widget option types (widget.h WidgetOption::Type)
  env.VALUE = 0
  env.SOURCE = 1
  env.BOOL = 2
  env.STRING = 3
  env.TEXT_SIZE = 4
  env.TIMER = 5
  env.SWITCH = 6
  env.COLOR = 7
  env.ALIGNMENT = 8
  env.SLIDER = 9
  env.CHOICE = 10
  env.FILE = 11

  -- alignment flags
  env.LEFT = 0
  env.CENTER = 0x0002
  env.RIGHT = 0x0004
  env.VCENTER = 0x0008
  env.MAX_SENSORS = 60

  env.getTime = function() return sim.ticks end
  env.getRSSI = function() return sim.rssi end
  env.getVersion = function() return table.unpack(sim.version) end

  env.getSourceValue = function(id)
    local v = sim.values[id]
    if v == nil then return nil end
    local cur = sim.current[id]
    if cur == nil then cur = true end
    local fr = sim.fresh[id]
    if fr == nil then fr = cur end
    return v, cur, fr
  end
  env.getValue = function(id) return sim.values[id] end
  -- Distinct id space and store from getValue()/sim.values, deliberately:
  -- see the M.setSwitch comment.
  env.getSwitchValue = function(id) return sim.switches[id] or false end

  env.getFieldInfo = function(idOrName)
    if type(idOrName) == "string" then
      local id = sim.byName[idOrName]
      return id and sim.fields[id] or nil
    end
    return sim.fields[idOrName]
  end
  env.getSourceIndex = function(name) return sim.byName[name] end
  env.getSourceName = function(id)
    local f = sim.fields[id]
    return f and f.name or nil
  end

  env.model = {
    getSensor = function(i) return sim.sensors[i] end,
    -- Records the call (assertable via sim.sensorResets) and mirrors
    -- TelemetryItem::clear() (telemetry_sensors.h): the sensor and its
    -- -/+ siblings read back unavailable until the next sample lands.
    resetSensor = function(i)
      sim.sensorResets[#sim.sensorResets + 1] = i
      local sn = sim.sensors[i]
      if not sn then return end
      for id, f in pairs(sim.fields) do
        if f.name == sn.name or f.name == sn.name .. "-"
           or f.name == sn.name .. "+" then
          sim.values[id] = nil
        end
      end
    end,
  }

  env.playTone = function(f, len, pause)
    sim.tones[#sim.tones + 1] = { f, len, pause }
  end
  env.playHaptic = function(len, pause)
    sim.haptics[#sim.haptics + 1] = { len, pause }
  end
  env.playNumber = function() end
  env.playFile = function() end
  env.getUsage = function() return 5 end

  env.loadScript = function(path) return loadfile(path) end

  -- EdgeTX Lua has no string metatable: "s:lower()" must fail here too.
  if debug and debug.setmetatable then
    debug.setmetatable("", nil)
  end
end

M.lvgl = lvgl
M.lcd = lcd
M.install = install
M.makeObject = makeObject
M.tracking = function(on) tracking = on end

return M
