---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - geometry helpers (pure Lua, no firmware dependencies)      #
---- #                                                                       #
---- # Angle convention matches LVGL: 0 deg = 3 o'clock, angles increase     #
---- # clockwise (screen y points down).                                     #
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

function M.normalize(value, minimum, maximum)
  if maximum == minimum then return 0 end
  return M.clamp((value - minimum) / (maximum - minimum), 0, 1)
end

function M.valueToAngle(value, minimum, maximum, startAngle, sweepAngle)
  return startAngle + M.normalize(value, minimum, maximum) * sweepAngle
end

function M.pointOnCircle(cx, cy, radius, angle)
  local a = angle * rad
  return cx + radius * cos(a), cy + radius * sin(a)
end

function M.linePoints(cx, cy, r1, r2, angle)
  local x1, y1 = M.pointOnCircle(cx, cy, r1, angle)
  local x2, y2 = M.pointOnCircle(cx, cy, r2, angle)
  return { { x = x1, y = y1 }, { x = x2, y = y2 } }
end

function M.tickPoints(cx, cy, r1, r2, angle)
  return M.linePoints(cx, cy, r1, r2, angle)
end

function M.round(n)
  return floor(n + 0.5)
end

return M
