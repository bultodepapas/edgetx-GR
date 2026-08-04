---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - telemetry engine                                           #
---- #                                                                       #
---- # Source resolution with metadata caching, value reading with table     #
---- # aggregation, and the availability model:                              #
---- #   unset       - no source configured                                  #
---- #   invalid     - source id does not resolve                            #
---- #   valid       - fresh/current data                                    #
---- #   stale       - value present but telemetry not current               #
---- #   unavailable - no value at all                                       #
---- #                                                                       #
---- # Local sources (sticks, channels, gvars, ...) are always current, so   #
---- # they keep working without telemetry (PLAN.md 3.7).                    #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

-- TelemetryUnit enum -> display text (subset; see dataconstants.h)
local UNIT_NAMES = {
  [1] = "V", [2] = "A", [3] = "mA", [4] = "kts", [5] = "m/s", [6] = "ft/s",
  [7] = "km/h", [8] = "mph", [9] = "m", [10] = "ft", [11] = "C", [12] = "F",
  [13] = "%", [14] = "mAh", [15] = "W", [16] = "mW", [17] = "dB", [18] = "rpm",
  [19] = "g", [20] = "deg", [21] = "rad", [22] = "ml", [23] = "floz",
  [24] = "ml/min", [25] = "Hz", [26] = "ms", [27] = "us", [28] = "km",
  [29] = "dBm",
}

function M.unitName(unit)
  return UNIT_NAMES[unit] or ""
end

-- Resolve and cache source metadata. Only does work when the source id
-- changed. Returns the source table: { id, name, unit, isTelemetry }.
function M.resolveSource(widget)
  local id = widget.options.Source or 0
  local s = widget.source
  if s.id == id and s.resolved then return s end
  s.id = id
  s.name = ""
  s.unit = nil
  s.unitName = ""
  s.isTelemetry = false
  s.resolved = true
  if id and id > 0 then
    local info = getFieldInfo(id)
    if info then
      s.name = info.name or ""
      s.unit = info.unit
      s.unitName = M.unitName(info.unit)
      s.isTelemetry = (info.unit ~= nil)
    end
  end
  return s
end

-- Read the source and update widget.data:
--   availability, value (raw), displayValue (raw or last known), state
-- State comes from the range table built in main.lua (widget.ranges).
function M.refresh(widget)
  local data = widget.data
  local src = widget.source

  if not src.id or src.id == 0 then
    data.availability = "unset"
    data.value = nil
    data.displayValue = nil
    data.state = nil
    return
  end

  local value, current = getSourceValue(src.id)

  if value == nil then
    data.availability = "unavailable"
    data.value = nil
    data.displayValue = data.lastValue
    data.state = nil
    return
  end

  if type(value) == "table" then
    local total = 0
    local count = 0
    for i = 1, #value do
      if type(value[i]) == "number" then
        total = total + value[i]
        count = count + 1
      end
    end
    if count == 0 then
      -- non-array tables (GPS, date/time) are not numeric readings
      data.availability = "unavailable"
      data.value = nil
      data.displayValue = data.lastValue
      data.state = nil
      return
    end
    value = total
  end

  if type(value) ~= "number" then
    data.availability = "unavailable"
    data.value = nil
    data.displayValue = data.lastValue
    data.state = nil
    return
  end

  if src.isTelemetry and not current then
    data.availability = "stale"
    data.value = nil
    data.displayValue = data.lastValue
    data.state = nil
    return
  end

  data.availability = "valid"
  data.value = value
  data.displayValue = value
  data.lastValue = value
  if widget.mods and widget.mods.ranges and widget.ranges then
    data.state = widget.mods.ranges.determineState(value, widget.ranges)
  else
    data.state = nil
  end
end

return M
