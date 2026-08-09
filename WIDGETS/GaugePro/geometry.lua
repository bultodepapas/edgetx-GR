---- #########################################################################
---- #                                                                       #
---- # Gauge Pro - geometry helpers (pure Lua, no firmware dependencies)      #
---- #                                                                       #
---- # Angle convention matches LVGL: 0 deg = 3 o'clock, angles increase     #
---- # clockwise (screen y points down).                                     #
---- #                                                                       #
---- # Point tables are {x, y} pairs - the exact format the EdgeTX binding   #
---- # reads (LvglWidgetLine::getPt uses rawgeti(pt,1)/rawgeti(pt,2)); named  #
---- # {x = ...} points fail on the radio.                                   #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local floor = math.floor
local cos = math.cos
local sin = math.sin
local rad = math.pi / 180

function M.clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

-- Position of `value` inside [minimum, maximum] as 0..1.
-- Inverted ranges (minimum > maximum) are mirrored rather than swapped, so a
-- descending scale (e.g. 0 at the right) maps correctly - the official C++
-- gauge's "value - min - max" transform is degenerate for asymmetric ranges.
function M.normalize(value, minimum, maximum)
  if maximum == minimum then return 0 end
  local t = (value - minimum) / (maximum - minimum)
  -- NaN survives clamp() untouched - neither `t < 0` nor `t > 1` is true of
  -- it - and every angle and bar width on the widget is derived from this
  -- one function, so a single NaN here reaches lvgl.set as a non-integer
  -- and raises on the radio. telemetry.refresh rejects non-finite READINGS
  -- at the gate; this catches a NaN arriving from anywhere else (a degenerate
  -- min/max pair, a caller passing a computed bound).
  if t ~= t then return 0 end
  return M.clamp(t, 0, 1)
end

function M.valueToAngle(value, minimum, maximum, startAngle, sweepAngle)
  return startAngle + M.normalize(value, minimum, maximum) * sweepAngle
end

function M.pointOnCircle(cx, cy, radius, angle)
  local a = angle * rad
  return cx + radius * cos(a), cy + radius * sin(a)
end

-- Radial line from r1 to r2 at `angle`.
function M.linePoints(cx, cy, r1, r2, angle)
  local x1, y1 = M.pointOnCircle(cx, cy, r1, angle)
  local x2, y2 = M.pointOnCircle(cx, cy, r2, angle)
  return { { x1, y1 }, { x2, y2 } }
end

-- Same line, written INTO a caller-owned buffer instead of allocating:
-- the binding copies the values out on every set (LvglWidgetLine::getPts,
-- lua_lvgl_widget.cpp:1008-1029) and retains no reference to the Lua table,
-- so mutating a reused buffer is legal and removes the per-frame allocation
-- the needle's three segments made (Tanda 6 F-11 / Phase 5.1). The buffer
-- must keep #buf == 2 (lua_rawlen drives getPts).
function M.linePointsInto(buf, cx, cy, r1, r2, angle)
  local x1, y1 = M.pointOnCircle(cx, cy, r1, angle)
  local x2, y2 = M.pointOnCircle(cx, cy, r2, angle)
  buf[1][1], buf[1][2] = x1, y1
  buf[2][1], buf[2][2] = x2, y2
  return buf
end

M.tickPoints = M.linePoints

-- Horizontal bar fill width for the linear (Bar) style.
function M.barFill(width, value, minimum, maximum)
  return floor(width * M.normalize(value, minimum, maximum) + 0.5)
end

function M.round(n)
  return floor(n + 0.5)
end

-- M.rayBoxEntry (slab-method ray/box intersection) lived here until Tanda 7.
-- Its only caller was renderer.needleReach, which shortened the needle so it
-- would not be drawn through the state chip - work the paint order already
-- does, since the chip is opaque and created after the needle. Both went
-- together; see the comment above updateArc in renderer.lua.

return M
