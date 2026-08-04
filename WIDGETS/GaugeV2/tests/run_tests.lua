-- Gauge V2 unit tests for geometry.lua and ranges.lua.
-- Run with stock Lua 5.3:  lua5.3 run_tests.lua [path-to-widget-dir]
-- Defaults to the directory of this script's parent.

local scriptDir = arg and arg[0] and arg[0]:match("^(.*[/\\])") or "./"
local widgetDir = arg and arg[1] or (scriptDir .. "../")

local passed = 0
local failed = 0

local function assertNear(actual, expected, epsilon)
  epsilon = epsilon or 0.0001
  if math.abs(actual - expected) > epsilon then
    error(string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
  end
end

local function assertEq(actual, expected)
  if actual ~= expected then
    error(string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
  end
end

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

local geometry = dofile(widgetDir .. "geometry.lua")
local ranges = dofile(widgetDir .. "ranges.lua")

test("clamp basic", function()
  assertEq(geometry.clamp(5, 0, 10), 5)
  assertEq(geometry.clamp(-1, 0, 10), 0)
  assertEq(geometry.clamp(11, 0, 10), 10)
end)

test("normalize", function()
  assertNear(geometry.normalize(0, 0, 100), 0)
  assertNear(geometry.normalize(50, 0, 100), 0.5)
  assertNear(geometry.normalize(100, 0, 100), 1)
  assertNear(geometry.normalize(150, 0, 100), 1)
  assertNear(geometry.normalize(-10, 0, 100), 0)
  assertNear(geometry.normalize(30, 30, 30), 0)
  assertNear(geometry.normalize(-20, -10, 10), 0)
  assertNear(geometry.normalize(0, -10, 10), 0.5)
end)

test("valueToAngle", function()
  assertNear(geometry.valueToAngle(0, 0, 100, 135, 270), 135)
  assertNear(geometry.valueToAngle(50, 0, 100, 135, 270), 270)
  assertNear(geometry.valueToAngle(100, 0, 100, 135, 270), 405)
  assertNear(geometry.valueToAngle(75, 0, 100, 135, 270), 337.5)
end)

test("pointOnCircle clockwise convention", function()
  local x, y = geometry.pointOnCircle(100, 100, 50, 0)
  assertNear(x, 150)          -- 3 o'clock
  assertNear(y, 100)
  x, y = geometry.pointOnCircle(100, 100, 50, 90)
  assertNear(x, 100)          -- 6 o'clock (y down)
  assertNear(y, 150)
  x, y = geometry.pointOnCircle(100, 100, 50, 270)
  assertNear(x, 100)          -- 12 o'clock
  assertNear(y, 50)
  x, y = geometry.pointOnCircle(100, 100, 50, 135)
  assertNear(x, 100 - 50 * math.sqrt(2) / 2)   -- bottom-left
  assertNear(y, 100 + 50 * math.sqrt(2) / 2)
end)

test("linePoints endpoints", function()
  local pts = geometry.linePoints(50, 50, 10, 40, 0)
  assertEq(#pts, 2)
  assertNear(pts[1].x, 60)
  assertNear(pts[1].y, 50)
  assertNear(pts[2].x, 90)
  assertNear(pts[2].y, 50)
end)

test("tickPoints matches linePoints", function()
  local a = geometry.tickPoints(0, 0, 5, 9, 200)
  local b = geometry.linePoints(0, 0, 5, 9, 200)
  assertEq(a[1].x, b[1].x)
  assertEq(a[2].y, b[2].y)
end)

test("round", function()
  assertEq(geometry.round(1.4), 1)
  assertEq(geometry.round(1.5), 2)
  assertEq(geometry.round(-1.5), -1)
end)

test("ranges high-is-good", function()
  local r = ranges.build(0, 100, 55, 35, true)
  assertEq(r[1].role, "critical")
  assertEq(r[1].from, 0)
  assertEq(r[1].to, 35)
  assertEq(r[2].role, "warning")
  assertEq(r[2].from, 35)
  assertEq(r[2].to, 55)
  assertEq(r[3].role, "normal")
  assertEq(r[3].from, 55)
  assertEq(r[3].to, 100)
end)

test("ranges low-is-good", function()
  local r = ranges.build(20, 120, 70, 90, false)
  assertEq(r[1].role, "normal")
  assertEq(r[1].from, 20)
  assertEq(r[1].to, 70)
  assertEq(r[2].role, "warning")
  assertEq(r[2].from, 70)
  assertEq(r[2].to, 90)
  assertEq(r[3].role, "critical")
  assertEq(r[3].from, 90)
  assertEq(r[3].to, 120)
end)

test("ranges inverted min/max swapped", function()
  local r = ranges.build(100, 0, 30, 60, true)
  assertEq(r[1].from, 0)
  assertEq(r[3].to, 100)
end)

test("ranges thresholds clamped into range", function()
  local r = ranges.build(0, 10, 200, -5, true)
  assertEq(r[1].to, 0)
  assertEq(r[3].from, 10)
end)

test("ranges warn == crit collapses warning band", function()
  local r = ranges.build(0, 100, 50, 50, true)
  assertEq(r[2].from, 50)
  assertEq(r[2].to, 50)
end)

test("determineState inside bands", function()
  local r = ranges.build(0, 100, 55, 35, true)
  assertEq(ranges.determineState(10, r), "critical")
  assertEq(ranges.determineState(40, r), "warning")
  assertEq(ranges.determineState(80, r), "normal")
  -- shared boundaries: first matching range wins (conservative)
  assertEq(ranges.determineState(35, r), "critical")  -- upper boundary of critical
  assertEq(ranges.determineState(55, r), "warning")   -- upper boundary of warning
end)

test("determineState outside range", function()
  local r = ranges.build(0, 100, 55, 35, true)
  assertEq(ranges.determineState(-5, r), "critical")  -- below min
  assertEq(ranges.determineState(150, r), "normal")   -- above max
  local r2 = ranges.build(0, 100, 55, 35, false)
  assertEq(ranges.determineState(-5, r2), "normal")
  assertEq(ranges.determineState(150, r2), "critical")
end)

print(string.format("-- %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
