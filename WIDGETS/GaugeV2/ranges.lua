---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - semantic ranges and state detection                        #
---- #                                                                       #
---- # Builds the ordered normal/warning/critical bands from user options    #
---- # and maps a value to its operational state, with hysteresis.           #
---- #                                                                       #
---- # Hysteresis rule: a worse state is adopted immediately (safety first), #
---- # a better state only once the value has left the previous band by the  #
---- # deadband. Without it a value resting on a threshold chatters between  #
---- # two states on sensor noise - visible as colour flicker and audible as #
---- # repeated alerts.                                                      #
---- #                                                                       #
---- # Pure Lua, no firmware dependencies.                                   #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local SEVERITY = { normal = 1, warning = 2, critical = 3 }
M.SEVERITY = SEVERITY

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Build ascending bands from minimum to maximum.
-- Returns { { role=..., from=..., to=... }, ... } (3 entries).
-- Bands are always ascending in value space even when the scale is drawn
-- inverted (geometry.normalize handles the drawing direction), and the
-- warning/critical values are clamped into the range.
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
      { role = "warning",  from = lo,      to = hi },
      { role = "normal",   from = hi,      to = maximum },
    }
  else
    ranges = {
      { role = "normal",   from = minimum, to = lo },
      { role = "warning",  from = lo,      to = hi },
      { role = "critical", from = hi,      to = maximum },
    }
  end
  return ranges
end

-- Deadband width for a range, as a fraction of the span (default 2%).
function M.deadband(minimum, maximum, fraction)
  local span = math.abs(maximum - minimum)
  if span == 0 then return 0 end
  return span * (fraction or 0.02)
end

local function rawState(value, ranges)
  for i = 1, #ranges do
    local r = ranges[i]
    if value >= r.from and value <= r.to then
      return r.role
    end
  end
  -- outside the configured range: take the nearest boundary band
  if value < ranges[1].from then return ranges[1].role end
  return ranges[#ranges].role
end

local function bandOf(ranges, role)
  for i = 1, #ranges do
    if ranges[i].role == role then return ranges[i] end
  end
  return nil
end

-- Determine the state of a value.
-- `previous` and `deadband` are optional; when both are given the result is
-- hysteretic (see the header).
function M.determineState(value, ranges, previous, deadband)
  local raw = rawState(value, ranges)
  if not previous or raw == previous then return raw end
  if not deadband or deadband <= 0 then return raw end
  if (SEVERITY[raw] or 0) > (SEVERITY[previous] or 0) then
    return raw  -- degrading: react at once
  end
  local band = bandOf(ranges, previous)
  if band and value >= band.from - deadband and value <= band.to + deadband then
    return previous  -- still inside the widened previous band: hold
  end
  return raw
end

return M
