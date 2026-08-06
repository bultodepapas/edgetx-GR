---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - geometry helpers (pure Lua, no firmware dependencies)      #
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
local huge, mmax = math.huge, math.max

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

-- Tapered needle: tip at radius r2, base of width 2*halfWidth at radius r1,
-- perpendicular to the needle axis. Three points, as the binding requires
-- ("There must be three points" - LvglWidgetTriangle).
function M.trianglePoints(cx, cy, r1, r2, halfWidth, angle)
  local tipX, tipY = M.pointOnCircle(cx, cy, r2, angle)
  local baseX, baseY = M.pointOnCircle(cx, cy, r1, angle)
  local a = angle * rad
  -- unit vector perpendicular to the needle axis
  local px, py = -sin(a), cos(a)
  return {
    { floor(tipX + 0.5), floor(tipY + 0.5) },
    { floor(baseX + px * halfWidth + 0.5), floor(baseY + py * halfWidth + 0.5) },
    { floor(baseX - px * halfWidth + 0.5), floor(baseY - py * halfWidth + 0.5) },
  }
end

-- Horizontal bar fill width for the linear (Bar) style.
function M.barFill(width, value, minimum, maximum)
  return floor(width * M.normalize(value, minimum, maximum) + 0.5)
end

function M.round(n)
  return floor(n + 0.5)
end

-- Distance along the ray from (cx, cy) at `angle` (deg, LVGL convention) to
-- where it first enters the axis-aligned `box` ({x, y, w, h}). nil if the
-- ray never enters the box ahead of the origin (slab method). Used to keep
-- the needle from being drawn through solid UI (the state chip pill) at
-- angles where its straight-line reach would cross it (Tanda 5 review 3.12).
function M.rayBoxEntry(cx, cy, angle, box)
  local a = angle * rad
  local dx, dy = cos(a), sin(a)
  local tMin, tMax = -huge, huge
  if dx == 0 then
    if cx < box.x or cx > box.x + box.w then return nil end
  else
    local t1, t2 = (box.x - cx) / dx, (box.x + box.w - cx) / dx
    if t1 > t2 then t1, t2 = t2, t1 end
    if t1 > tMin then tMin = t1 end
    if t2 < tMax then tMax = t2 end
  end
  if dy == 0 then
    if cy < box.y or cy > box.y + box.h then return nil end
  else
    local t1, t2 = (box.y - cy) / dy, (box.y + box.h - cy) / dy
    if t1 > t2 then t1, t2 = t2, t1 end
    if t1 > tMin then tMin = t1 end
    if t2 < tMax then tMax = t2 end
  end
  if tMin > tMax or tMax < 0 then return nil end
  return mmax(tMin, 0)
end

return M
