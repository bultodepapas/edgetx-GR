---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - telemetry engine                                           #
---- #                                                                       #
---- # Source resolution with metadata caching, value reading with table     #
---- # aggregation, and the availability model:                              #
---- #   unset        - no source configured                                 #
---- #   invalid      - source id does not resolve                           #
---- #   valid        - fresh/current data                                   #
---- #   stale        - value present but sensor not current (link alive)    #
---- #   disconnected - telemetry link down (getRSSI() == 0)                 #
---- #   unavailable  - no value at all                                      #
---- #                                                                       #
---- # Local sources (sticks, channels, gvars, ...) are always current, so   #
---- # they keep working without telemetry (PLAN.md 3.7).                    #
---- #                                                                       #
---- # Flight history (min/max) is tracked here, in refresh(): the firmware  #
---- # only calls background() while the widget is OFF-SCREEN, so history    #
---- # must update while the widget is visible.                              #
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

-- Timers report seconds; the renderer formats them as hh:mm:ss.
local function isTimerName(name)
  if type(name) ~= "string" then return false end
  if string.sub(name, 1, 5) == "timer" then return true end
  return name == "T1" or name == "T2" or name == "T3"
end

function M.unitName(unit)
  return UNIT_NAMES[unit] or ""
end

-- getFieldInfo can return names starting with an invalid character on some
-- firmware versions (see GaugeRotary lib_widget_tools cleanInvalidChar).
local function cleanName(name)
  local n = string.byte(name, 1)
  while n and n > 127 do
    name = string.sub(name, 2)
    n = string.byte(name, 1)
  end
  return name
end

-- Resolve and cache source metadata. Only does work when the source id
-- changed. Returns the source table: { id, name, unit, unitName, isTelemetry,
-- isTimer, prec }.
function M.resolveSource(widget)
  local id = widget.options.Source or 0
  local s = widget.source
  if s.id == id and s.resolved then return s end
  s.id = id
  s.name = ""
  s.unit = nil
  s.unitName = ""
  s.isTelemetry = false
  s.isTimer = false
  s.prec = nil
  s.resolved = true
  if id and id > 0 then
    local info = getFieldInfo(id)
    if info then
      s.name = cleanName(info.name or "")
      s.unit = info.unit
      s.unitName = M.unitName(info.unit)
      s.isTelemetry = (info.unit ~= nil)
      s.isTimer = isTimerName(s.name)
      -- sensor precision is not in getFieldInfo; look it up once via the
      -- model sensor table (cached: this only runs on source change)
      if s.isTelemetry then
        for i = 0, 31 do
          local sn = model.getSensor(i)
          if sn and sn.name == s.name then
            s.prec = sn.prec
            break
          end
        end
      end
    end
  end
  return s
end

-- Read the source and update widget.data:
--   availability, value (raw), displayValue (raw or last known), state
-- State comes from the range table built in main.lua (widget.ranges).
-- Also maintains the flight min/max history.
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
    if src.isTelemetry and getRSSI() == 0 then
      data.availability = "disconnected"
    else
      data.availability = "unavailable"
    end
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

  -- flight history (background() does not run while the widget is visible)
  local h = widget.history
  if h.min == nil then
    h.min = value
    h.max = value
  else
    if value < h.min then h.min = value end
    if value > h.max then h.max = value end
  end
end

return M
