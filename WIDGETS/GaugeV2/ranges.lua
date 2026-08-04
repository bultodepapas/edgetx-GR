---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - semantic ranges and state detection                        #
---- #                                                                       #
---- # Builds the ordered normal/warning/critical ranges from user options   #
---- # and maps a value to its operational state. Handles high-is-good and   #
---- # low-is-good directions. Pure Lua, no firmware dependencies.           #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Build ascending ranges from minimum to maximum.
-- Returns { { role=..., from=..., to=... }, ... } (3 entries).
-- Warning/critical values are clamped into [minimum, maximum].
function M.build(minimum, maximum, warning, critical, highIsGood)
  if maximum < minimum then
    minimum, maximum = maximum, minimum
  end
  local lo = clamp(math.min(warning, critical), minimum, maximum)
  local hi = clamp(math.max(warning, critical), minimum, maximum)
  local ranges
  if highIsGood then
    ranges = {
      { role = "critical", from = minimum, to = lo },
      { role = "warning",  from = lo,       to = hi },
      { role = "normal",   from = hi,       to = maximum },
    }
  else
    ranges = {
      { role = "normal",   from = minimum, to = lo },
      { role = "warning",  from = lo,       to = hi },
      { role = "critical", from = hi,       to = maximum },
    }
  end
  return ranges
end

-- Determine the state of a value. Values outside [min, max] take the state
-- of the nearest boundary range (below min -> first range, above max -> last).
function M.determineState(value, ranges)
  for i = 1, #ranges do
    local r = ranges[i]
    if value >= r.from and value <= r.to then
      return r.role
    end
  end
  if value < ranges[1].from then return ranges[1].role end
  return ranges[#ranges].role
end

return M
