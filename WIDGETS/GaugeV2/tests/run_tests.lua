-- Unit tests for the pure GaugeV2 modules (geometry, ranges, presets,
-- options, format, smoothing). Stock Lua 5.3, no firmware needed.
--
-- Usage: lua5.3 tests/run_tests.lua <widget-dir>

local widgetDir = arg[1] or "./"

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local function load(name)
  return assert(loadfile(widgetDir .. name .. ".lua"))()
end

local geometry = load("geometry")
local ranges = load("ranges")
local presets = load("presets")
local options = load("options")
local format = load("format")
local smoothing = load("smoothing")

local passed, failed = 0, 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("PASS " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end

local function assertEq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label or "assertEq",
      tostring(expected), tostring(actual)), 2)
  end
end

local function assertNear(actual, expected, tol, label)
  if math.abs(actual - expected) > (tol or 0.001) then
    error(string.format("%s: expected ~%s, got %s", label or "assertNear",
      tostring(expected), tostring(actual)), 2)
  end
end

local function assertTrue(cond, label)
  if not cond then error((label or "assertTrue") .. " failed", 2) end
end

-- ---- geometry ------------------------------------------------------------

test("clamp bounds", function()
  assertEq(geometry.clamp(5, 0, 10), 5)
  assertEq(geometry.clamp(-1, 0, 10), 0)
  assertEq(geometry.clamp(11, 0, 10), 10)
end)

test("normalize spans and clamps", function()
  assertNear(geometry.normalize(50, 0, 100), 0.5)
  assertNear(geometry.normalize(-10, 0, 100), 0)
  assertNear(geometry.normalize(150, 0, 100), 1)
  assertEq(geometry.normalize(5, 5, 5), 0, "degenerate range")
end)

test("normalize mirrors an inverted range", function()
  -- descending scale: min 100 -> max 0 means 100 sits at t = 0
  assertNear(geometry.normalize(100, 100, 0), 0)
  assertNear(geometry.normalize(0, 100, 0), 1)
  assertNear(geometry.normalize(75, 100, 0), 0.25)
end)

test("valueToAngle across the sweep", function()
  assertNear(geometry.valueToAngle(0, 0, 100, 135, 270), 135)
  assertNear(geometry.valueToAngle(100, 0, 100, 135, 270), 405)
  assertNear(geometry.valueToAngle(50, 0, 100, 135, 270), 270)
end)

test("pointOnCircle uses LVGL angles", function()
  local x, y = geometry.pointOnCircle(100, 100, 10, 0)
  assertNear(x, 110); assertNear(y, 100)
  x, y = geometry.pointOnCircle(100, 100, 10, 90)
  assertNear(x, 100); assertNear(y, 110)   -- 90 deg is DOWN (y grows down)
end)

test("linePoints returns {x,y} pairs", function()
  local pts = geometry.linePoints(50, 50, 10, 20, 0)
  assertEq(#pts, 2)
  assertEq(#pts[1], 2)
  assertEq(type(pts[2][1]), "number")
end)

test("trianglePoints returns three distinct points", function()
  local pts = geometry.trianglePoints(50, 50, 5, 25, 4, 0)
  assertEq(#pts, 3, "point count")
  for i = 1, 3 do assertEq(#pts[i], 2, "pair " .. i) end
  assertTrue(pts[1][1] > pts[2][1], "tip beyond base")
  assertTrue(pts[2][2] ~= pts[3][2], "base points straddle the axis")
end)

test("barFill maps value to width", function()
  assertEq(geometry.barFill(200, 50, 0, 100), 100)
  assertEq(geometry.barFill(200, 0, 0, 100), 0)
  assertEq(geometry.barFill(200, 999, 0, 100), 200)
end)

-- ---- ranges --------------------------------------------------------------

test("ranges high-is-good ordering", function()
  local r = ranges.build(0, 100, 55, 35, true)
  assertEq(r[1].role, "critical"); assertEq(r[1].to, 35)
  assertEq(r[2].role, "warning")
  assertEq(r[3].role, "normal"); assertEq(r[3].from, 55)
end)

test("ranges low-is-good ordering", function()
  local r = ranges.build(0, 120, 70, 90, false)
  assertEq(r[1].role, "normal")
  assertEq(r[3].role, "critical"); assertEq(r[3].from, 90)
end)

test("ranges clamp thresholds into the span", function()
  local r = ranges.build(0, 100, 500, -500, true)
  assertEq(r[1].from, 0); assertEq(r[3].to, 100)
end)

test("ranges warn == crit collapses the warning band", function()
  local r = ranges.build(0, 100, 50, 50, true)
  assertEq(r[2].from, r[2].to)
end)

test("G-4: both thresholds out of range derive at the presets' proportions", function()
  -- Manual -120..0 dBm scale with the 0..100 defaults (55/35): clamping would
  -- collapse both onto Max and make the whole dial one critical band. The
  -- helper must derive them at 35 % / 55 % of the span instead.
  local w, c = ranges.saneThresholds(-120, 0, 55, 35, true)
  assertNear(c, -78, 0.01, "critical at 35 % of the span")
  assertNear(w, -54, 0.01, "warning at 55 % of the span")

  -- low-is-good mirrors the bands against the top of the scale
  w, c = ranges.saneThresholds(-120, 0, 55, 35, false)
  assertNear(w, -66, 0.01, "low-is-good warning")
  assertNear(c, -42, 0.01, "low-is-good critical")

  -- in-range thresholds pass through untouched
  local a, b = ranges.saneThresholds(0, 100, 55, 35, true)
  assertEq(a, 55); assertEq(b, 35)

  -- an equal pair INSIDE the range is a deliberate sharp cliff, not a mistake
  a, b = ranges.saneThresholds(0, 100, 50, 50, true)
  assertEq(a, 50); assertEq(b, 50)

  -- one threshold on each side is still the old clamp's job
  a, b = ranges.saneThresholds(0, 100, 500, -500, true)
  assertEq(a, 500); assertEq(b, -500)
end)

test("determineState inside and outside", function()
  local r = ranges.build(0, 100, 55, 35, true)
  assertEq(ranges.determineState(80, r), "normal")
  assertEq(ranges.determineState(45, r), "warning")
  assertEq(ranges.determineState(10, r), "critical")
  assertEq(ranges.determineState(-50, r), "critical", "below min")
  assertEq(ranges.determineState(200, r), "normal", "above max")
end)

test("hysteresis holds an improving state", function()
  local r = ranges.build(0, 100, 55, 35, true)
  local db = ranges.deadband(0, 100)      -- 2 units
  assertEq(ranges.determineState(56, r, "warning", db), "warning")
  assertEq(ranges.determineState(58, r, "warning", db), "normal")
end)

test("hysteresis never delays a degrading state", function()
  local r = ranges.build(0, 100, 55, 35, true)
  local db = ranges.deadband(0, 100)
  assertEq(ranges.determineState(54, r, "normal", db), "warning")
  assertEq(ranges.determineState(34, r, "warning", db), "critical")
end)

test("hysteresis does not oscillate on a noisy ramp", function()
  local r = ranges.build(0, 100, 55, 35, true)
  local db = ranges.deadband(0, 100)
  local state, flips = "normal", 0
  local noise = { 0.4, -0.5, 0.3, -0.4, 0.5, -0.3 }
  for i = 0, 30 do
    local v = 56 - i * 0.1 + noise[(i % 6) + 1]
    local new = ranges.determineState(v, r, state, db)
    if new ~= state then flips = flips + 1 end
    state = new
  end
  assertTrue(flips <= 1, "flips = " .. flips)
end)

-- ---- presets -------------------------------------------------------------

test("preset match by name is punctuation insensitive", function()
  assertEq(presets.find({ name = "RQly%" }).maximum, 100)
  assertEq(presets.find({ name = "rssi" }).warning, 55)
end)

test("preset falls back to the unit", function()
  local p = presets.find({ name = "Zork", unit = 11 })
  assertEq(p.highIsGood, false, "temperature is low-is-good")
end)

test("P1-7: an unknown voltage sensor does not inherit battery detection", function()
  -- Only an exact NAME match (RxBt, Cels, ...) is trustworthy evidence that
  -- a sensor IS a battery; matching by unit alone just means "some voltage
  -- source", e.g. a BEC or servo rail sensor with a name the widget has
  -- never seen.
  local p = presets.find({ name = "VBEC", unit = 1 })
  assertTrue(p ~= nil, "unit fallback still finds a preset")
  assertEq(p.battery, nil, "must not inherit battery detection from RxBt")
  assertEq(p.cellsTable, nil, "must not inherit cell-table detection either")

  -- The real RxBt preset (exact name match) keeps its battery flag.
  local named = presets.find({ name = "RxBt", unit = 1 })
  assertEq(named.battery, true, "exact name match keeps battery detection")

  -- find() must not have mutated the shared preset table as a side effect.
  local again = presets.find({ name = "VBEC", unit = 1 })
  assertEq(again.battery, nil, "repeated lookups stay clean")
  assertEq(presets.find({ name = "RxBt", unit = 1 }).battery, true,
    "the named preset itself was not corrupted by the unit-fallback copy")
end)

test("preset misses stay nil", function()
  assertEq(presets.find({ name = "Zork" }), nil)
  assertEq(presets.find(nil), nil)
end)

test("cell count detection", function()
  assertEq(presets.cellCount(16.4), 4)
  assertEq(presets.cellCount(4.1), 1)
  assertEq(presets.cellCount(25.0), 6)
end)

test("state of charge follows the discharge curve", function()
  assertEq(presets.percentFromCell(4.2), 100)
  assertEq(presets.percentFromCell(3.3), 0)
  assertTrue(presets.percentFromCell(3.8) > 40, "mid pack")
  assertTrue(presets.percentFromCell(3.0, "liion") > 0, "li-ion floor lower")
end)

test("pack range scales with the cell count", function()
  local p = presets.packRange(4)
  assertNear(p.maximum, 16.8, 0.01)
  assertNear(p.warning, 14.8, 0.01)
end)

-- ---- options (the wire format) -------------------------------------------

local DEFS = {
  { key = "Src", type = SOURCE, field = "source", since = 211, default = 0 },
  { key = "Min", type = VALUE, field = "min", since = 211, default = 0,
    min = -10, max = 10 },
  { key = "Flag", type = BOOL, field = "flag", since = 211, default = 1 },
  { key = "Pick", type = CHOICE, field = "pick", since = 211, default = 2,
    choices = { "a", "b", "c" } },
  { key = "Extra", type = CHOICE, field = "extra", since = 212, default = 1,
    choices = { "x", "y" } },
}

test("choice values are 1-based integers", function()
  assertEq(options.parse(DEFS, { Pick = 3 }).pick, 3)
end)

test("a stored zero choice falls back to the default", function()
  assertEq(options.parse(DEFS, { Pick = 0 }).pick, 2)
end)

test("choice labels never map to a valid index (the 1.0 bug)", function()
  -- the firmware cannot deliver a string here; if one ever did, it must fall
  -- back to the default rather than silently selecting the first entry
  assertEq(options.parse(DEFS, { Pick = "c" }).pick, 2)
end)

test("bool and value conversion", function()
  local cfg = options.parse(DEFS, { Flag = 0, Min = -7 })
  assertEq(cfg.flag, false)
  assertEq(cfg.min, -7)
end)

test("missing options fall back to declared defaults", function()
  local cfg = options.parse(DEFS, {})
  assertEq(cfg.pick, 2)
  assertEq(cfg.flag, true)
  assertEq(cfg.extra, 1, "a 2.12-only option still has a value on 2.11")
end)

test("build honours the capacity", function()
  assertEq(#options.build(DEFS, 10), 4, "2.11 sees only core options")
  local ext = options.build(DEFS, 50)
  assertEq(#ext, 5)
  assertEq(ext[5][1], "Extra")
end)

test("build emits the firmware declaration shape", function()
  local decl = options.build(DEFS, 50)
  assertEq(decl[2][2], VALUE)
  assertEq(decl[2][4], -10, "VALUE carries min/max")
  assertEq(type(decl[4][4]), "table", "CHOICE carries the choices table")
end)

test("capacity follows the firmware version", function()
  mock.sim.version = { "2.11.0", "sim", 2, 11, 0 }
  assertEq(options.capacity(), 10)
  mock.sim.version = { "2.12.0", "sim", 2, 12, 0 }
  assertEq(options.capacity(), 50)
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0 }
  assertEq(options.capacity(), 50)
end)

-- ---- format --------------------------------------------------------------

test("number formatting honours precision", function()
  assertEq(format.number(3.14159, 0), "3")
  assertEq(format.number(3.14159, 1), "3.1")
  assertEq(format.number(3.14159, 2), "3.14")
  assertEq(format.number(nil, 0), "-")
end)

test("timers format as hh:mm:ss with a sign", function()
  assertEq(format.hms(3661), "01:01:01")
  assertEq(format.hms(-65), "-00:01:05")
end)

test("widest sample covers the scale plus one character of slack", function()
  local widget = {
    config = { min = 0, max = 100, precision = 1 },
    source = { isTimer = false },
  }
  assertEq(format.widestSample(widget), "-100.0")
  widget.source.isTimer = true
  assertEq(format.widestSample(widget), "-00:00:00")
end)

-- ---- smoothing -----------------------------------------------------------

test("damping maps to a time constant", function()
  assertEq(smoothing.tau(0), 0, "0 disables the filter")
  assertEq(smoothing.tau(4), 160)
  assertEq(smoothing.tau(99), 360, "clamped")
end)

test("smoothing is frame-rate independent", function()
  local widget = { config = { tau = 160 }, smooth = {} }
  mock.sim.ticks = 0
  assertEq(smoothing.step(widget, 10), 10, "first sample snaps")
  for _ = 1, 10 do
    mock.advance(20)
    smoothing.step(widget, 0)
  end
  local fast = widget.smooth.value
  widget.smooth = {}
  mock.sim.ticks = 0
  smoothing.step(widget, 10)
  mock.advance(200)
  smoothing.step(widget, 0)
  assertNear(widget.smooth.value, fast, 0.5, "same elapsed time, same result")
end)

test("smoothing uses a millisecond time base", function()
  -- getTime() counts 10 ms ticks: 100 ticks is 1 s, which at tau = 160 ms
  -- must be essentially converged (1.0 mixed ticks and ms here)
  local widget = { config = { tau = 160 }, smooth = {} }
  mock.sim.ticks = 0
  smoothing.step(widget, 100)
  mock.advance(1000)
  smoothing.step(widget, 0)
  assertTrue(widget.smooth.value < 1, "converged, got " ..
             tostring(widget.smooth.value))
end)

print(string.format("-- %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
