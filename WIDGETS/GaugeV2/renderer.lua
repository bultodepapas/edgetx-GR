---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - LVGL renderer                                              #
---- #                                                                       #
---- # Retained-object rendering: build() creates the object tree once,      #
---- # update() changes only properties that actually changed. Objects are   #
---- # created individually (no lvgl.build tables) to avoid luac nesting     #
---- # pitfalls and to keep per-frame work minimal.                          #
---- #                                                                       #
---- # Verified binding (radio/src/lua):                                     #
---- #   - arc: absolute start/end angles, 405 auto-normalizes to 45         #
---- #   - line: pts table re-applied via lvgl.set when points change        #
---- #   - circle: radius + bgColor fill (pivot)                             #
---- #   - label: text/color/font/pos, font = index << 8                     #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local G = nil
function M.setup(geometryModule)
  G = geometryModule
end

local floor = math.floor
local max = math.max

local STATE_COLORS = {
  normal   = COLOR_THEME_PRIMARY1,
  warning  = COLOR_THEME_WARNING,
  critical = RED,
  static   = COLOR_THEME_PRIMARY1,
  muted    = COLOR_THEME_DISABLED,
}

local SECTION_COLORS = {
  normal   = COLOR_THEME_PRIMARY2,
  warning  = COLOR_THEME_WARNING,
  critical = RED,
}

local TRACK_COLOR = COLOR_THEME_SECONDARY3
local TICK_COLOR = COLOR_THEME_SECONDARY2
local TEXT_SOFT = COLOR_THEME_SECONDARY1
local MARK_MIN_COLOR = COLOR_THEME_DISABLED
local MARK_MAX_COLOR = COLOR_THEME_PRIMARY2

local function px(value)
  return max(1, floor(value * lvgl.LCD_SCALE + 0.5))
end

local function formatValue(v, precision)
  if type(v) ~= "number" or v ~= v then return "-" end
  if precision == 0 then return string.format("%.0f", v) end
  if precision == 1 then return string.format("%.1f", v) end
  return string.format("%.2f", v)
end
M.formatValue = formatValue

local function angleOf(widget, value)
  local cfg = widget.config
  return floor(G.valueToAngle(value, cfg.min, cfg.max, 135, 270) + 0.5)
end

local function smoothedValue(widget, target)
  local sm = widget.smooth
  if target == nil then
    sm.value = nil
    return nil
  end
  if sm.value == nil then
    sm.value = target
    sm.time = getTime()
    return target
  end
  local now = getTime()
  local dt = now - sm.time
  if dt <= 0 then dt = 1 elseif dt > 1000 then dt = 1000 end
  sm.time = now
  local factor = 1 - math.exp(-dt / 140)
  sm.value = sm.value + (target - sm.value) * factor
  return sm.value
end

-- Position the source-name label (static text, measured once per change).
local function positionNameLabel(widget)
  local ui, L = widget.ui, widget.layout
  if not ui.nameLabel then return end
  local src = widget.source
  local w = lcd.sizeText(src.name or "", L.nameFont)
  local x = (L.nameX and L.nameX > 0) and L.nameX or (L.cx - floor(w / 2))
  lvgl.set(ui.nameLabel, { x = x, y = L.nameY })
end

-- Called when the source changed but the layout did not.
function M.updateSourceLabels(widget)
  local ui, L, src = widget.ui, widget.layout, widget.source
  if ui.unitLabel then
    lvgl.set(ui.unitLabel, { text = src.unitName or "" })
  end
  if ui.nameLabel then
    lvgl.set(ui.nameLabel, { text = src.name or "" })
    positionNameLabel(widget)
  end
end

local function buildTrack(widget)
  local ui, L = widget.ui, widget.layout
  local cfg = widget.config
  if cfg.colorMode == 2 then
    ui.track = {}
    for i = 1, #widget.ranges do
      local r = widget.ranges[i]
      local a1 = angleOf(widget, r.from)
      local a2 = angleOf(widget, r.to)
      local c = SECTION_COLORS[r.role]
      ui.track[i] = lvgl.arc{
        x = L.cx, y = L.cy, radius = L.radius,
        startAngle = a1, endAngle = a2,
        bgStartAngle = a1, bgEndAngle = a2,
        color = c, bgColor = c,
        bgOpacity = 255, opacity = 0,
        thickness = L.trackThickness, rounded = 0,
      }
    end
  else
    ui.track = lvgl.arc{
      x = L.cx, y = L.cy, radius = L.radius,
      startAngle = 135, endAngle = 405,
      bgStartAngle = 135, bgEndAngle = 405,
      color = TRACK_COLOR, bgColor = TRACK_COLOR,
      bgOpacity = 255, opacity = 0,
      thickness = L.trackThickness, rounded = 1,
    }
  end
end

local function buildTicks(widget)
  local ui, L = widget.ui, widget.layout
  ui.ticks = {}
  local count = L.tickCount
  for i = 1, count do
    local a = 135 + ((i - 1) / (count - 1)) * 270
    ui.ticks[i] = lvgl.line{
      pts = G.tickPoints(L.cx, L.cy, L.tickInner, L.tickOuter, a),
      thickness = L.tickThickness, color = TICK_COLOR,
    }
  end
end

-- Create (or recreate) the whole object tree. Called from update() only
-- when the layout signature changed.
function M.build(widget)
  local L, ui = widget.layout, widget.ui
  local cfg = widget.config
  local src = widget.source

  buildTrack(widget)
  buildTicks(widget)

  ui.valueArc = lvgl.arc{
    x = L.cx, y = L.cy, radius = L.radius,
    startAngle = 135, endAngle = 135,
    bgStartAngle = 135, bgEndAngle = 405,
    bgOpacity = 0,
    color = STATE_COLORS.normal,
    thickness = L.arcThickness, rounded = 1,
  }

  if L.showNeedle then
    ui.needle = lvgl.line{
      pts = G.linePoints(L.cx, L.cy, L.needleInner, L.needleOuter, 135),
      thickness = L.needleThickness, rounded = 1,
      color = STATE_COLORS.normal,
    }
    -- circle accepts only x/y/w/h/color/opacity/radius/thickness/filled
    -- (no bgColor/bgOpacity); filled=1 makes `color` fill the circle
    ui.pivot = lvgl.circle{
      x = L.cx, y = L.cy, radius = L.pivotRadius,
      filled = 1, color = STATE_COLORS.normal,
    }
  end

  if L.showMarkers then
    local inner = L.radius - L.trackThickness - px(1)
    local outer = L.radius + px(1)
    ui.minMark = lvgl.line{
      pts = G.linePoints(L.cx, L.cy, inner, outer, 135),
      thickness = max(1, L.tickThickness), color = MARK_MIN_COLOR,
    }
    ui.maxMark = lvgl.line{
      pts = G.linePoints(L.cx, L.cy, inner, outer, 135),
      thickness = max(1, L.tickThickness), color = MARK_MAX_COLOR,
    }
  end

  ui.valueLabel = lvgl.label{
    x = 0, y = L.valueY, text = "-", font = L.valueFont,
    color = STATE_COLORS.normal,
  }
  if L.showUnit then
    ui.unitLabel = lvgl.label{
      x = 0, y = L.unitY, text = src.unitName or "", font = L.unitFont,
      color = TEXT_SOFT,
    }
  end
  if L.showName then
    ui.nameLabel = lvgl.label{
      x = 0, y = L.nameY, text = src.name or "", font = L.nameFont,
      color = TEXT_SOFT,
    }
    positionNameLabel(widget)
  end
  if L.showStateText then
    ui.stateLabel = lvgl.label{
      x = 0, y = L.stateY, text = "", font = L.stateFont,
      color = TEXT_SOFT,
    }
  end
  if L.showMinMaxText then
    ui.minText = lvgl.label{
      x = 0, y = L.minMaxY, text = "", font = L.minMaxFont,
      color = MARK_MIN_COLOR,
    }
    ui.maxText = lvgl.label{
      x = 0, y = L.minMaxY, text = "", font = L.minMaxFont,
      color = MARK_MAX_COLOR,
    }
  end

  widget.frame = {
    angle = -1, minAngle = -1, maxAngle = -1,
    needleVisible = true,
    colorKey = "",
    valueStr = "", stateStr = "", minStr = "", maxStr = "",
    prevAvail = "unset",
  }
  widget.ui.built = true
end

local function applyColors(widget, key)
  local ui, L = widget.ui, widget.layout
  local c = STATE_COLORS[key] or STATE_COLORS.normal
  local opa = (key == "muted") and 96 or 255
  lvgl.set(ui.valueArc, { color = c, opacity = opa })
  if ui.needle then lvgl.set(ui.needle, { color = c }) end
  if ui.pivot then lvgl.set(ui.pivot, { color = c }) end
  lvgl.set(ui.valueLabel, { color = c })
  if ui.stateLabel then
    local sc = TEXT_SOFT
    if key == "warning" then sc = COLOR_THEME_WARNING
    elseif key == "critical" then sc = RED end
    lvgl.set(ui.stateLabel, { color = sc })
  end
end

local function updateValueLabel(widget)
  local ui, L = widget.ui, widget.layout
  local frame = widget.frame
  local data = widget.data
  local p = widget.config.precision

  local str
  if data.availability == "unset" then
    str = "-"
  elseif data.displayValue ~= nil then
    str = formatValue(data.displayValue, p)
  else
    str = "-"
  end

  if str == frame.valueStr then return end
  frame.valueStr = str

  local vw = lcd.sizeText(str, L.valueFont)
  local vh = L.valueH
  local vx = (L.valueX and L.valueX > 0) and L.valueX or (L.cx - floor(vw / 2))
  lvgl.set(ui.valueLabel, { x = vx, y = L.valueY, w = vw, h = vh, text = str })

  if ui.unitLabel then
    local ux = vx + vw + px(4)
    local uy = L.valueY + floor((vh - L.unitH) / 2)
    lvgl.set(ui.unitLabel, { x = ux, y = uy })
  end
end

local function updateStateLabel(widget)
  local ui, L = widget.ui, widget.layout
  if not ui.stateLabel then return end
  local frame = widget.frame
  local data = widget.data

  local str = ""
  if data.availability == "unset" or data.availability == "invalid" then
    str = "NO DATA"
  elseif data.availability ~= "valid" then
    str = "NO DATA"
  elseif data.state == "warning" then
    str = "WARN"
  elseif data.state == "critical" then
    str = "CRIT"
  end

  if str == frame.stateStr then return end
  frame.stateStr = str
  local w = lcd.sizeText(str, L.stateFont)
  local x = (L.stateX and L.stateX > 0) and L.stateX or (L.cx - floor(w / 2))
  lvgl.set(ui.stateLabel, { x = x, y = L.stateY, text = str })
end

local function updateArcAndNeedle(widget)
  local ui, L = widget.ui, widget.layout
  local frame = widget.frame
  local data = widget.data

  if data.availability ~= "valid" or data.displayValue == nil then
    smoothedValue(widget, nil)
    if frame.needleVisible then
      frame.needleVisible = false
      if ui.needle then lvgl.hide(ui.needle) end
      if ui.pivot then lvgl.hide(ui.pivot) end
    end
    return
  end

  -- snap the needle after reconnection instead of animating from zero
  if frame.prevAvail ~= "valid" then
    widget.smooth.value = nil
  end
  local sv = smoothedValue(widget, data.displayValue)
  local a = angleOf(widget, sv)
  if a ~= frame.angle then
    frame.angle = a
    lvgl.set(ui.valueArc, { endAngle = a })
    if ui.needle then
      lvgl.set(ui.needle,
        { pts = G.linePoints(L.cx, L.cy, L.needleInner, L.needleOuter, a) })
    end
  end
  if not frame.needleVisible then
    frame.needleVisible = true
    if ui.needle then lvgl.show(ui.needle) end
    if ui.pivot then lvgl.show(ui.pivot) end
  end
end

local function updateMarkers(widget)
  local ui, L = widget.ui, widget.layout
  if not ui.minMark then return end
  local frame = widget.frame
  local h = widget.history
  local inner = L.radius - L.trackThickness - px(1)
  local outer = L.radius + px(1)

  local a = h.min and angleOf(widget, h.min) or -1
  if a ~= frame.minAngle then
    frame.minAngle = a
    if a >= 0 then
      lvgl.set(ui.minMark, { pts = G.linePoints(L.cx, L.cy, inner, outer, a) })
    end
  end
  a = h.max and angleOf(widget, h.max) or -1
  if a ~= frame.maxAngle then
    frame.maxAngle = a
    if a >= 0 then
      lvgl.set(ui.maxMark, { pts = G.linePoints(L.cx, L.cy, inner, outer, a) })
    end
  end
end

local function updateMinMaxText(widget)
  local ui, L = widget.ui, widget.layout
  if not ui.minText then return end
  local frame = widget.frame
  local h = widget.history
  local p = widget.config.precision

  local minStr = h.min and ("MIN " .. formatValue(h.min, p)) or ""
  local maxStr = h.max and ("MAX " .. formatValue(h.max, p)) or ""
  if minStr == frame.minStr and maxStr == frame.maxStr then return end
  frame.minStr, frame.maxStr = minStr, maxStr

  local mw = lcd.sizeText(minStr, L.minMaxFont)
  local xw = lcd.sizeText(maxStr, L.minMaxFont)
  local total = mw + xw + px(8)
  local base = (L.valueX and L.valueX > 0) and L.valueX or (L.cx - floor(total / 2))
  lvgl.set(ui.minText, { x = base, text = minStr })
  lvgl.set(ui.maxText, { x = base + mw + px(8), text = maxStr })
end

-- Per-frame update. Called from refresh(); changes properties only.
function M.update(widget)
  local ui, L = widget.ui, widget.layout
  if not ui.built then return end
  local frame = widget.frame
  local data = widget.data

  local key
  if data.availability == "unset" or data.availability == "invalid" then
    key = "muted"
  elseif data.availability ~= "valid" then
    key = "muted"
  elseif widget.config.colorMode == 0 then
    key = "static"
  else
    key = data.state or "normal"
  end
  if key ~= frame.colorKey then
    frame.colorKey = key
    applyColors(widget, key)
  end

  updateValueLabel(widget)
  updateStateLabel(widget)
  updateArcAndNeedle(widget)
  updateMarkers(widget)
  updateMinMaxText(widget)

  frame.prevAvail = data.availability
end

return M
