-- Lua VM instruction budget probe for GaugePro.
--
-- The firmware gives every widget callback a hard budget of 20 000 Lua VM
-- instructions per call: radio/src/lua/widgets.cpp defines
-- MAX_INSTRUCTIONS (20000/100), luaHook() fires every 200 instructions and
-- luaL_error(L, "CPU limit") past 100 fires - the same setErrorMessage()
-- path that traces "Widget disabled", dead until the model reloads.
--
-- Two things made this probe necessary (dev/code-review-tanda6-response.md
-- §A.1 / §C.5):
--   * DEBUG builds DISABLE the limit (it only traces the running maximum),
--     so a widget that dies on a production radio can be perfectly healthy
--     in the simulator;
--   * the headless harness has no instruction budget at all, so neither
--     do the test suites. Nothing measured the one resource that silently
--     kills the widget.
--
-- Usage: lua5.3 dev/instructions.lua <widget-dir>
--
-- Phase 0: establishes the number (acceptance: produces numbers).
-- Phase 5: becomes the acceptance criterion for the optimisation work.
-- 100 fires = the kill limit; report the headroom below it.
local widgetDir = arg[1] or "./"
if string.sub(widgetDir, -1) ~= "/" then widgetDir = widgetDir .. "/" end

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local ID_RSSI, ID_MIN, ID_MAX, ID_AIL = 3072, 3073, 3074, 101

local function build(zone, ov, sourceId)
  mock.reset()
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0 }
  mock.addField(ID_RSSI, "RSSI", 17)
  mock.addField(ID_MIN, "RSSI-", 17)
  mock.addField(ID_MAX, "RSSI+", 17)
  mock.addField(ID_AIL, "Ail")
  mock.sim.sensors[0] = { name = "RSSI", prec = 0, unit = 17 }
  mock.setValue(ID_RSSI, 70)
  mock.setValue(ID_MIN, 31)
  mock.setValue(ID_MAX, 92)
  mock.setValue(ID_AIL, 0)
  local mod = dofile(widgetDir .. "main.lua")
  local o = { Source = sourceId or ID_RSSI }
  for k, v in pairs(ov) do o[k] = v end
  local opts = mock.makeOptions(mod.defs, o)
  local w = mod.create(zone, opts, widgetDir)
  w.mod = mod
  mod.update(w, opts)
  return w, mod, opts
end

local function refresh(widget, times)
  for _ = 1, (times or 1) do
    mock.advance(50)
    widget.mod.refresh(widget)
  end
end

-- ---- counting ---------------------------------------------------------------

local fires = 0
local function hook() fires = fires + 1 end

-- Instructions executed by `fn` in units of 200 (the hook period the
-- firmware uses). The count includes the pcall and counting overhead on
-- both sides, so it slightly OVERestimates - safe for a headroom probe.
local function countCall(fn)
  fires = 0
  debug.sethook(hook, "", 200)
  local ok, err = pcall(fn)
  debug.sethook()
  return fires, ok, err
end

local function countMoving(widget, frames, sourceId, a, b)
  -- The harness's audit trail is Lua code; firmware lvgl.set is C++ and its
  -- internals are outside the Lua VM hook. Disable only that instrumentation
  -- for the ordinary-frame gate, matching dev/measure_frames.lua.
  mock.tracking(false)
  fires = 0
  debug.sethook(hook, "", 200)
  for i = 1, frames do
    mock.setValue(sourceId, (i % 2 == 0) and a or b)
    mock.advance(50)
    widget.mod.refresh(widget)
  end
  debug.sethook()
  mock.tracking(true)
  return fires * 200 / frames
end

-- ---- scenes -----------------------------------------------------------------

-- The heaviest scene the widget can produce: the largest zone with the
-- needle, Sections colouring, scale labels and min/max text on. The rest of
-- the matrix brackets it so the worst case is measured, not assumed.
local SCENES = {
  { name = "480x272 needle sections markers+text",
    zone = { x = 0, y = 0, w = 480, h = 272 },
    ov = { Style = 2, ColorMode = 5, ShowMinMax = 3, Precision = 4 } },
  { name = "480x272 needle threshold markers+text",
    zone = { x = 0, y = 0, w = 480, h = 272 },
    ov = { Style = 2, ColorMode = 2, ShowMinMax = 3, Precision = 4 } },
  { name = "200x200 needle sections markers+text",
    zone = { x = 0, y = 0, w = 200, h = 200 },
    ov = { Style = 2, ColorMode = 5, ShowMinMax = 3, Precision = 4 } },
  { name = "200x200 arc sections markers",
    zone = { x = 0, y = 0, w = 200, h = 200 },
    ov = { Style = 3, ColorMode = 5, ShowMinMax = 2, Precision = 4 } },
  { name = "200x200 needle sections 360deg",
    zone = { x = 0, y = 0, w = 200, h = 200 },
    ov = { Style = 2, ColorMode = 5, Sweep = 3, ShowMinMax = 3,
           Precision = 4 } },
  { name = "300x60 bar threshold",
    zone = { x = 0, y = 0, w = 300, h = 60 },
    ov = { Style = 4, ColorMode = 2, Precision = 4 } },
  { name = "300x60 bar spatial gradient",
    zone = { x = 0, y = 0, w = 300, h = 60 },
    ov = { Style = 4, ColorMode = 4, Precision = 4, Damping = 0 } },
  { name = "480x120 gradient panel/chamfer/markers",
    zone = { x = 0, y = 0, w = 480, h = 120 },
    ov = { Style = 4, ColorMode = 4, Precision = 4, Damping = 0,
           Surface = 3, BarEnds = 4, ShowMinMax = 3 } },
  { name = "480x120 blocks-24 sections/panel",
    zone = { x = 0, y = 0, w = 480, h = 120 },
    ov = { Style = "Bar", BarFace = "Blocks", Segments = "24",
           ColorMode = "Sections", Surface = "Theme panel", Damping = 0 } },
  { name = "480x120 true-hex-10 sections/panel",
    zone = { x = 0, y = 0, w = 480, h = 120 },
    ov = { Style = "Bar", BarFace = "Hex", Segments = "10",
           ColorMode = "Sections", Surface = "Theme panel", Damping = 0 } },
  { name = "480x120 ticks-24 sections/panel",
    zone = { x = 0, y = 0, w = 480, h = 120 },
    ov = { Style = "Bar", BarFace = "Ticks", Segments = "24",
           ColorMode = "Sections", Surface = "Theme panel", Damping = 0 } },
  { name = "480x120 steps-10 sections/panel",
    zone = { x = 0, y = 0, w = 480, h = 120 },
    ov = { Style = "Bar", BarFace = "Steps", Segments = "10",
           ColorMode = "Sections", Surface = "Theme panel", Damping = 0 } },
  { name = "160x44 hex compact fallback",
    zone = { x = 0, y = 0, w = 160, h = 44 },
    ov = { Style = "Bar", BarFace = "Hex", Segments = "10",
            ColorMode = "Gradient", Damping = 0 } },
  { name = "120x300 vertical gradient/full marks",
    zone = { x = 0, y = 0, w = 120, h = 300 },
    ov = { Style = "Bar", BarDir = "Vertical", ColorMode = "Gradient",
           ScaleMarks = "Full", BarHead = "Dot", Damping = 0 } },
  { name = "120x300 vertical blocks-24",
    zone = { x = 0, y = 0, w = 120, h = 300 },
    ov = { Style = "Bar", BarDir = "Vertical", BarFace = "Blocks",
           Segments = "24", ColorMode = "Sections", Damping = 0 } },
  { name = "120x300 vertical true-hex-10",
    zone = { x = 0, y = 0, w = 120, h = 300 },
    ov = { Style = "Bar", BarDir = "Vertical", BarFace = "Hex",
           Segments = "10", ColorMode = "Sections", Damping = 0 } },
  { name = "120x300 vertical ticks-24",
    zone = { x = 0, y = 0, w = 120, h = 300 },
    ov = { Style = "Bar", BarDir = "Vertical", BarFace = "Ticks",
           Segments = "24", ColorMode = "Sections", Damping = 0 } },
  { name = "120x300 vertical steps-10",
    zone = { x = 0, y = 0, w = 120, h = 300 },
    ov = { Style = "Bar", BarDir = "Vertical", BarFace = "Steps",
           Segments = "10", ColorMode = "Sections", Damping = 0 } },
  { name = "420x110 zero-origin gradient",
    zone = { x = 0, y = 0, w = 420, h = 110 }, sourceId = ID_AIL,
    plateau = { 60, 80 }, transition = { -95, 95 },
    ov = { Style = "Bar", BarOrigin = "Zero", ColorMode = "Gradient",
           Scale = "Manual", Min = -100, Max = 100, Damping = 0 } },
  { name = "120x300 vertical zero blocks-24",
    zone = { x = 0, y = 0, w = 120, h = 300 }, sourceId = ID_AIL,
    plateau = { 60, 80 }, transition = { -95, 95 },
    ov = { Style = "Bar", BarDir = "Vertical", BarOrigin = "Zero",
           BarFace = "Blocks", Segments = "24", ColorMode = "Sections",
           Scale = "Manual", Min = -100, Max = 100, Damping = 0 } },
  { name = "420x110 asymmetric dual rail",
    zone = { x = 0, y = 0, w = 420, h = 110 }, sourceId = ID_AIL,
    plateau = { 60, 80 }, transition = { -30, 100 },
    ov = { Style = "Bar", BarFace = "Dual rail", BarOrigin = "Zero",
           Palette = "Custom 2", Scale = "Manual", Min = -30, Max = 100,
           Damping = 0 } },
  { name = "120x300 vertical dual rail",
    zone = { x = 0, y = 0, w = 120, h = 300 }, sourceId = ID_AIL,
    plateau = { 60, 80 }, transition = { -100, 100 },
    ov = { Style = "Bar", BarDir = "Vertical", BarFace = "Dual rail",
           BarOrigin = "Zero", Scale = "Manual", Min = -100, Max = 100,
           Damping = 0 } },
}

local fmt = string.format

print("GaugePro instruction budget probe  (1 fire = 200 VM instructions;")
print("100 fires = 20000 = the firmware kill limit per callback)")
print("")

local function probeScene(sc)
  local sourceId = sc.sourceId or ID_RSSI
  local plateau = sc.plateau or { 60, 90 }
  local transition = sc.transition or { 10, 90 }
  local w, mod, opts = build(sc.zone, sc.ov, sourceId)
  local o2 = {}
  for k, v in pairs(opts) do o2[k] = v end

  -- update() with identical options: the settings-exit / Cancel path
  local updNoop = countCall(function() mod.update(w, opts) end)

  -- update() with a structural change: the full rebuild path
  local updBuild, refFirst
  do
    local key = (w.layout.style == "bar") and "BarEnds" or "Sweep"
    local original = o2[key] or 1
    o2[key] = (original == 3) and 2 or 3
    updBuild = countCall(function() mod.update(w, o2) end)
    refFirst = countCall(function() refresh(w, 1) end)
    o2[key] = original
    countCall(function() mod.update(w, o2) end)
  end

  -- refresh() with a static value: the common idle frame
  refresh(w, 2)
  local refIdle = countCall(function() refresh(w, 1) end)

  -- Ordinary motion stays inside NORMAL. A separate feed crosses NORMAL and
  -- CRITICAL so palette/badge transition work cannot hide in the average.
  local refMove = 0
  for _ = 1, 5 do
    mock.setValue(sourceId,
      (mock.sim.values[sourceId] == plateau[2]) and plateau[1] or plateau[2])
    local n = countCall(function() refresh(w, 1) end)
    if n > refMove then refMove = n end
  end
  countMoving(w, 20, sourceId, plateau[1], plateau[2])
  local moveAverage = countMoving(w, 100, sourceId, plateau[1], plateau[2])

  local refTransition = 0
  for _ = 1, 5 do
    mock.setValue(sourceId,
      (mock.sim.values[sourceId] == transition[2]) and transition[1]
       or transition[2])
    local n = countCall(function() refresh(w, 1) end)
    if n > refTransition then refTransition = n end
  end

  local worst = math.max(updNoop, updBuild, refFirst, refIdle, refMove,
                         refTransition)
  return {
    name = sc.name,
    updNoop = updNoop, updBuild = updBuild,
    refFirst = refFirst, refIdle = refIdle, refMove = refMove,
    moveAverage = moveAverage, refTransition = refTransition,
    isBar = w.layout.style == "bar",
    worst = worst,
  }
end

local rows = {}
local overall = { worst = 0 }
for _, sc in ipairs(SCENES) do
  local r = probeScene(sc)
  rows[#rows + 1] = r
  if r.worst > overall.worst then overall = r end
end

print(fmt("%-38s %8s %8s %9s %8s %8s %8s %10s %9s",
  "scene", "upd-noop", "upd-bld", "ref-1st", "ref-idle", "move/f",
  "ref-x",
  "instr/call", "headroom"))
print(string.rep("-", 115))
for _, r in ipairs(rows) do
  print(fmt("%-38s %8d %8d %9d %8d %8.0f %8d %10d %8d fires",
    r.name, r.updNoop, r.updBuild, r.refFirst, r.refIdle, r.moveAverage,
    r.refTransition,
    r.worst * 200, 100 - r.worst))
end
print(string.rep("-", 115))
print(fmt("worst scene: %s", overall.name))
print(fmt("worst callback: %d fires = %d instructions (limit 100 / 20000)",
  overall.worst, overall.worst * 200))
print(fmt("headroom: %d fires (%d%%) before the CPU-limit kill switch",
  100 - overall.worst, math.floor((100 - overall.worst) / 100 * 100)))
print("")

local failures = {}
for _, r in ipairs(rows) do
  if r.worst >= 100 then
    failures[#failures + 1] = r.name .. ": callback >= 20000"
  end
  if r.isBar then
    if math.max(r.refIdle * 200, r.moveAverage) >= 2000 then
      failures[#failures + 1] = r.name .. ": ordinary refresh >= 2000"
    end
    if r.refTransition * 200 >= 6000 then
      failures[#failures + 1] = r.name .. ": transition >= 6000"
    end
    if math.max(r.updBuild, r.refFirst) * 200 >= 10000 then
      failures[#failures + 1] = r.name .. ": structural frame >= 10000"
    end
  end
end
if #failures > 0 then
  for _, failure in ipairs(failures) do
    io.stderr:write("PROBE FAILURE: " .. failure .. "\n")
  end
  os.exit(1)
end
print("bar gates: ordinary <2000, transition <6000, structural <10000: PASS")
