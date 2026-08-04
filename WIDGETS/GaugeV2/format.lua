---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - value formatting                                           #
---- #                                                                       #
---- # Shared by layout (to size the value area from the widest string the   #
---- # scale can produce) and by the renderers (to print the live value).    #
---- # Pure Lua apart from string.format.                                    #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local floor, abs = math.floor, math.abs

M.NO_VALUE = "-"

function M.number(v, precision)
  if type(v) ~= "number" or v ~= v then return M.NO_VALUE end
  if precision == 1 then return string.format("%.1f", v) end
  if precision == 2 then return string.format("%.2f", v) end
  return string.format("%.0f", v)
end

-- Timers report seconds; display hh:mm:ss. A negative value is an elapsed
-- countdown timer (official Value widget behaviour).
function M.hms(v)
  if type(v) ~= "number" or v ~= v then return "--:--:--" end
  local n = abs(v)
  local sign = (v < 0) and "-" or ""
  return sign .. string.format("%02d:%02d:%02d", floor(n / 3600),
    floor((n % 3600) / 60), floor(n % 60))
end

-- Live value string for the current source.
function M.display(widget, v)
  if v == nil then return M.NO_VALUE end
  if widget.source.isTimer then return M.hms(v) end
  return M.number(v, widget.config.precision)
end

-- Widest string the configured scale can produce. Used once per layout pass
-- to reserve the value area, so the digits never move as the value changes
-- (an instrument keeps its ones digit in place).
function M.widestSample(widget)
  local cfg = widget.config
  if widget.source.isTimer then return "00:00:00" end
  local a = M.display(widget, cfg.min)
  local b = M.display(widget, cfg.max)
  if #b >= #a then return b end
  return a
end

return M
