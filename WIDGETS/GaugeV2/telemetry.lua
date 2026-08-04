---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - telemetry engine                                           #
---- #                                                                       #
---- # Source resolution with metadata caching, value reading with cell      #
---- # aggregation, battery state-of-charge, and the availability model:     #
---- #   unset        - no source configured                                 #
---- #   invalid      - source id does not resolve                           #
---- #   valid        - fresh/current data                                   #
---- #   stale        - value present but sensor not current (link alive)    #
---- #   disconnected - telemetry link down (getRSSI() == 0)                 #
---- #   unavailable  - no value at all                                      #
---- #                                                                       #
---- # getSourceValue() returns THREE values: value, current, fresh          #
---- # (api_general.cpp:837). Telemetry values are already scaled by the     #
---- # sensor precision, so `prec` is only needed for formatting.            #
---- #                                                                       #
---- # History comes from the radio's own <name>- / <name>+ sensors when     #
---- # they exist (the same source the rest of the UI shows, and the one     #
---- # the standard telemetry reset clears); the in-Lua tracker is the       #
---- # fallback for sticks, channels and gvars.                             #
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

M.CELLS_LOWEST, M.CELLS_TOTAL, M.CELLS_AVERAGE = 1, 2, 3
M.BATTERY_OFF, M.BATTERY_LIPO, M.BATTERY_LIION = 1, 2, 3

function M.unitName(unit)
  return UNIT_NAMES[unit] or ""
end

-- getFieldInfo can return names starting with an invalid character on some
-- firmware versions (GaugeRotary lib_widget_tools cleanInvalidChar).
local function cleanName(name)
  local n = string.byte(name, 1)
  while n and n > 127 do
    name = string.sub(name, 2)
    n = string.byte(name, 1)
  end
  return name
end
M.cleanName = cleanName

-- Timer sources are the contiguous "timer" family (api_general.cpp:415).
-- Detect them by id, never by name: T1/T2/T3 are common TEMPERATURE sensor
-- labels, and telemetry sensors always carry a unit while timers do not.
local timerBase = nil
local function resolveTimerBase()
  if timerBase ~= nil then return timerBase end
  if type(getSourceIndex) == "function" then
    timerBase = getSourceIndex("timer1") or false
  else
    timerBase = false
  end
  return timerBase
end

local function isTimerSource(id, name, isTelemetry)
  if isTelemetry then return false end
  local base = resolveTimerBase()
  if base and id >= base and id <= base + 2 then return true end
  if type(name) ~= "string" then return false end
  return string.sub(name, 1, 5) == "timer" or name == "tx-time"
end

-- Sensor precision is not exposed by getFieldInfo; look it up once through
-- the model sensor table. MAX_SENSORS is exposed to Lua (40/60/99 depending
-- on the target) - scanning a hard-coded 32 misses sensors on big radios.
local function sensorPrecision(name)
  if type(model) ~= "table" or type(model.getSensor) ~= "function" then
    return nil
  end
  local count = tonumber(MAX_SENSORS) or 60
  for i = 0, count - 1 do
    local sn = model.getSensor(i)
    if sn and sn.name == name then return sn.prec end
  end
  return nil
end

-- Resolve and cache source metadata. Only does work when the source changed.
function M.resolveSource(widget)
  local id = (widget.config and widget.config.source) or 0
  local s = widget.source
  if s.id == id and s.resolved then return s end
  s.id = id
  s.name = ""
  s.unit = nil
  s.unitName = ""
  s.isTelemetry = false
  s.isTimer = false
  s.prec = nil
  s.minId = nil
  s.maxId = nil
  s.cells = nil
  s.resolved = true
  if id and id > 0 then
    local info = getFieldInfo(id)
    if info then
      s.name = cleanName(info.name or "")
      s.unit = info.unit
      s.unitName = M.unitName(info.unit)
      -- tx-voltage is not a telemetry source, but the official Value widget
      -- appends "V" to it (value.cpp MIXSRC_TX_VOLTAGE case)
      if s.name == "tx-voltage" then s.unitName = "V" end
      s.isTelemetry = (info.unit ~= nil)
      s.isTimer = isTimerSource(id, s.name, s.isTelemetry)
      if s.isTelemetry then
        s.prec = sensorPrecision(s.name)
        -- the radio already tracks per-sensor min/max as sibling sources
        local lo = getFieldInfo(s.name .. "-")
        local hi = getFieldInfo(s.name .. "+")
        s.minId = lo and lo.id or nil
        s.maxId = hi and hi.id or nil
      end
    end
  end
  return s
end

-- --------------------------------------------------------------- reading --

local function setNoData(data, availability)
  data.availability = availability
  data.value = nil
  data.displayValue = data.lastValue
  data.state = nil
  data.fresh = false
end

-- Aggregate a CELLS table according to the configured mode.
-- getSourceValue returns one entry per cell, already in volts
-- (api_general.cpp luaPushCells: values[i] * 0.01).
local function aggregateCells(t, mode)
  local total, count, lowest = 0, 0, nil
  for i = 1, #t do
    local v = t[i]
    if type(v) == "number" then
      total = total + v
      count = count + 1
      if lowest == nil or v < lowest then lowest = v end
    end
  end
  if count == 0 then return nil, 0 end
  if mode == M.CELLS_TOTAL then return total, count end
  if mode == M.CELLS_AVERAGE then return total / count, count end
  return lowest, count
end
M.aggregateCells = aggregateCells

-- Latch the cell count on the first valid reading: a pack sags under load, so
-- re-deriving it later would step the scale down mid-flight.
local function latchCells(widget, value)
  local s = widget.source
  if s.cells then return s.cells end
  local chem = (widget.config.battery == M.BATTERY_LIION) and "liion" or "lipo"
  s.cells = widget.mods.presets.cellCount(value, chem)
  return s.cells
end
M.latchCells = latchCells

local function readHistorySiblings(widget)
  local s, h = widget.source, widget.history
  if not s.minId and not s.maxId then return false end
  local lo = s.minId and getSourceValue(s.minId) or nil
  local hi = s.maxId and getSourceValue(s.maxId) or nil
  if type(lo) == "number" then h.min = lo end
  if type(hi) == "number" then h.max = hi end
  return true
end

-- Fallback tracker: only reached when the source has no sibling sensors.
local function trackHistory(widget, value)
  local h = widget.history
  if h.min == nil then
    h.min, h.max = value, value
  else
    if value < h.min then h.min = value end
    if value > h.max then h.max = value end
  end
end

-- Read the source and update widget.data.
function M.refresh(widget)
  local data = widget.data
  local src = widget.source
  local cfg = widget.config

  if not src.id or src.id == 0 then
    data.availability = "unset"
    data.value = nil
    data.displayValue = nil
    data.state = nil
    data.fresh = false
    return
  end

  local value, current, fresh = getSourceValue(src.id)

  if value == nil then
    if src.isTelemetry and getRSSI() == 0 then
      setNoData(data, "disconnected")
    else
      setNoData(data, "unavailable")
    end
    return
  end

  if type(value) == "table" then
    local aggregate, count = aggregateCells(value, cfg.cells or M.CELLS_LOWEST)
    if aggregate == nil then
      -- non-numeric tables (GPS, date/time) are not gauge readings
      setNoData(data, "unavailable")
      return
    end
    value = aggregate
    if count > 0 then src.cells = src.cells or count end
  end

  if type(value) ~= "number" then
    setNoData(data, "unavailable")
    return
  end

  if src.isTelemetry and not current then
    setNoData(data, "stale")
    return
  end

  -- A pack voltage only tells you something once you know how many cells it
  -- has; latch the count from the first reading (see latchCells).
  if widget.autoCells and not src.cells then
    latchCells(widget, value)
  end

  -- Battery mode: show state of charge instead of raw volts.
  if cfg.battery and cfg.battery ~= M.BATTERY_OFF then
    local chem = (cfg.battery == M.BATTERY_LIION) and "liion" or "lipo"
    local cells = latchCells(widget, value)
    local perCell = (cells > 0) and (value / cells) or value
    local percent = widget.mods.presets.percentFromCell(perCell, chem)
    if percent then
      data.raw = value
      data.perCell = perCell
      value = percent
    end
  end

  data.availability = "valid"
  data.value = value
  data.displayValue = value
  data.lastValue = value
  data.fresh = (fresh == true)

  local prev = data.state
  data.state = widget.mods.ranges.determineState(value, widget.ranges, prev,
                                                 widget.deadband)

  if not readHistorySiblings(widget) then
    trackHistory(widget, value)
  end
end

-- Clear the tracked history (source/range change, or the reset switch).
function M.resetHistory(widget)
  widget.history.min = nil
  widget.history.max = nil
  widget.history.fromSensor = (widget.source.minId ~= nil)
end

return M
