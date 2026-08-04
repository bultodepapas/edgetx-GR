---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - LVGL dial renderer                                         #
---- #                                                                       #
---- # Retained objects: build() creates the tree once, update() changes     #
---- # only properties that actually changed (guarded by a per-object cache) #
---- # and never allocates a property table.                                 #
---- #                                                                       #
---- # Anatomy, outside in:                                                  #
---- #   ticks           major (solid) + minor (dashed) marks                #
---- #   rail            thin arc marking the warning / critical zones       #
---- #   track           full sweep at low opacity - the scale               #
---- #   ghost           peak-hold segment at reduced opacity                #
---- #   value arc       thick, rounded, semantic colour                     #
---- #   needle          tapered triangle + counterweight + pivot ring       #
---- #   text            value + unit (baseline aligned), name, state chip   #
---- #                                                                       #
---- # Verified binding facts (radio/src/lua/lua_lvgl_widget.cpp):           #
---- #   * arc: absolute start/end angles plus bgStartAngle/bgEndAngle;      #
---- #     thickness and rounded are BUILD TIME only (no setter).            #
---- #   * line / triangle: pts are {x, y} pairs; triangles need 3 points.   #
---- #   * circle: no bgColor/bgOpacity - filled = 1 fills with `color`.     #
---- #   * label: text/color/font/x/y/w/h/align; align does the centring.    #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local floor, max = math.floor, math.max

local T, G, F  -- theme, geometry, format

function M.setup(theme, geometry, format)
  T, G, F = theme, geometry, format
end

M.COLOR_STATIC, M.COLOR_THRESHOLD, M.COLOR_RAIL, M.COLOR_GRADIENT,
  M.COLOR_SECTIONS = 1, 2, 3, 4, 5

-- One scratch table for every lvgl.set call: the binding reads it
-- immediately, so reusing it keeps refresh() allocation free.
local scratch = {}

local function setProp(widget, obj, key, value)
  if not obj then return end
  local props = widget.frame.props
  local cache = props[obj]
  if not cache then
    cache = {}
    props[obj] = cache
  end
  if cache[key] == value then return end
  cache[key] = value
  scratch[key] = value
  lvgl.set(obj, scratch)
  scratch[key] = nil
end
M.setProp = setProp

-- ---------------------------------------------------------------- angles --

local function angleOf(widget, value)
  local cfg, L = widget.config, widget.layout
  local a = G.valueToAngle(value, cfg.min, cfg.max, L.startAngle, L.sweep)
  a = floor(a + 0.5)
  -- a full ring must never close onto its own start angle (zero length arc)
  local limit = L.startAngle + L.sweep - ((L.sweep >= 360) and 1 or 0)
  if a > limit then a = limit end
  if a < L.startAngle then a = L.startAngle end
  return a
end
M.angleOf = angleOf

-- ----------------------------------------------------------------- build --

local function buildTrack(widget)
  local ui, L, cfg = widget.ui, widget.layout, widget.config
  local endA = L.startAngle + L.sweep
  if cfg.colorMode == M.COLOR_SECTIONS then
    ui.sections = {}
    for i = 1, #widget.ranges do
      local r = widget.ranges[i]
      local a1, a2 = angleOf(widget, r.from), angleOf(widget, r.to)
      if a2 > a1 then
        local c = T.stateColor(r.role, widget.accent)
        ui.sections[#ui.sections + 1] = lvgl.arc{
          x = L.cx, y = L.cy, radius = L.radius,
          startAngle = a1, endAngle = a2,
          bgStartAngle = a1, bgEndAngle = a2,
          color = c, bgColor = c, bgOpacity = T.opacity.rail, opacity = 0,
          thickness = L.trackThickness, rounded = 0,
        }
      end
    end
  else
    ui.track = lvgl.arc{
      x = L.cx, y = L.cy, radius = L.radius,
      startAngle = L.startAngle, endAngle = endA,
      bgStartAngle = L.startAngle, bgEndAngle = endA,
      color = T.color.rail, bgColor = T.color.rail,
      bgOpacity = T.opacity.rail, opacity = 0,
      thickness = L.trackThickness, rounded = 1,
    }
  end

  -- threshold rail: a thin permanent reminder of where the bands are, drawn
  -- outside the track so the value arc keeps the foreground to itself.
  if cfg.colorMode == M.COLOR_RAIL then
    ui.rails = {}
    for i = 1, #widget.ranges do
      local r = widget.ranges[i]
      if r.role ~= "normal" then
        local a1, a2 = angleOf(widget, r.from), angleOf(widget, r.to)
        if a2 > a1 then
          local c = T.stateColor(r.role, widget.accent)
          ui.rails[#ui.rails + 1] = lvgl.arc{
            x = L.cx, y = L.cy, radius = L.railRadius,
            startAngle = a1, endAngle = a2,
            bgStartAngle = a1, bgEndAngle = a2,
            color = c, bgColor = c, bgOpacity = 255, opacity = 0,
            thickness = L.railThickness, rounded = 0,
          }
        end
      end
    end
  end
end

local function buildTicks(widget)
  local ui, L = widget.ui, widget.layout
  ui.ticks = {}
  local count = L.tickCount
  for i = 1, count do
    local a = L.startAngle + ((i - 1) / (count - 1)) * L.sweep
    ui.ticks[i] = lvgl.line{
      pts = G.linePoints(L.cx, L.cy, L.tickInner, L.tickOuter, a),
      thickness = L.tickThickness, color = T.color.tick,
    }
  end
  -- Minor ticks are shorter, thinner and dimmer rather than dashed:
  -- dashGap/dashWidth exist on hline/vline only (LvglWidgetLineBase), not on
  -- the free-angle line class (LvglWidgetLine).
  if L.minorTicks and L.minorTicks > 0 then
    ui.minors = {}
    local inner = L.tickInner
    local outer = L.tickInner + floor((L.tickOuter - L.tickInner) * 0.55)
    for i = 1, L.minorTicks do
      local a = L.startAngle + ((i - 0.5) / (count - 1)) * L.sweep
      ui.minors[i] = lvgl.line{
        pts = G.linePoints(L.cx, L.cy, inner, outer, a),
        thickness = 1, color = T.color.tick, opacity = T.opacity.ghost,
      }
    end
  end
end

local function buildNeedle(widget)
  local ui, L = widget.ui, widget.layout
  local a = L.startAngle
  -- lvgl.triangle takes ONLY pts plus the base object params (it is a
  -- LvglSimpleWidgetObject - no filled/thickness/rounded); it always fills.
  ui.needle = lvgl.triangle{
    pts = G.trianglePoints(L.cx, L.cy, L.needleInner, L.needleOuter,
                           L.needleHalf, a),
    color = T.color.accent,
  }
  ui.tail = lvgl.triangle{
    pts = G.trianglePoints(L.cx, L.cy, L.needleInner, L.tailOuter,
                           max(1, floor(L.needleHalf * 0.7)), a + 180),
    color = T.color.accent,
  }
  ui.pivotRing = lvgl.circle{
    x = L.cx, y = L.cy, radius = L.pivotRadius,
    filled = 1, color = T.color.rail,
  }
  ui.pivotDot = lvgl.circle{
    x = L.cx, y = L.cy, radius = max(1, floor(L.pivotRadius * 0.45)),
    filled = 1, color = T.color.accent,
  }
end

local function label(box, font, color, align, text)
  return lvgl.label{
    x = box.x, y = box.y, w = box.w, h = box.h,
    text = text or "", font = font, color = color, align = align or LEFT,
  }
end
M.label = label

function M.build(widget)
  local L, ui, cfg = widget.layout, widget.ui, widget.config

  buildTrack(widget)
  buildTicks(widget)

  if L.showGhost then
    ui.ghost = lvgl.arc{
      x = L.cx, y = L.cy, radius = L.radius,
      startAngle = L.startAngle, endAngle = L.startAngle,
      bgStartAngle = L.startAngle, bgEndAngle = L.startAngle,
      bgOpacity = 0, opacity = T.opacity.ghost,
      color = T.color.rail,
      thickness = L.ghostThickness, rounded = 1,
    }
    lvgl.hide(ui.ghost)
  end

  ui.valueArc = lvgl.arc{
    x = L.cx, y = L.cy, radius = L.radius,
    startAngle = L.startAngle, endAngle = L.startAngle,
    bgStartAngle = L.startAngle, bgEndAngle = L.startAngle + L.sweep,
    bgOpacity = 0, color = T.color.accent,
    thickness = L.arcThickness, rounded = 1,
  }

  if L.showNeedle then buildNeedle(widget) end

  if L.showMarkers then
    local inner = L.radius - floor(L.trackThickness / 2) - T.px(1)
    local outer = L.railRadius + T.px(1)
    ui.minMark = lvgl.line{
      pts = G.linePoints(L.cx, L.cy, inner, outer, L.startAngle),
      thickness = max(1, L.tickThickness), color = T.color.history,
    }
    ui.maxMark = lvgl.line{
      pts = G.linePoints(L.cx, L.cy, inner, outer, L.startAngle),
      thickness = max(1, L.tickThickness), color = T.color.history,
    }
    lvgl.hide(ui.minMark)
    lvgl.hide(ui.maxMark)
  end

  ui.valueLabel = label(L.valueBox, L.valueFont, T.color.accent, L.valueAlign,
                        F.NO_VALUE)
  if L.showUnit and widget.unitText ~= "" then
    ui.unitLabel = label(L.unitBox, L.unitFont, T.color.label, L.unitAlign,
                         widget.unitText)
  end
  if L.showName then
    ui.nameLabel = label(L.nameBox, L.nameFont, T.color.label, L.nameAlign,
                         widget.nameText)
  end
  if L.showState then
    ui.chip = lvgl.rectangle{
      x = L.stateBox.x, y = L.stateBox.y - T.px(1),
      w = L.stateBox.w, h = L.chipHeight,
      color = T.color.chip, filled = 1, rounded = floor(L.chipHeight / 2),
    }
    lvgl.hide(ui.chip)
    ui.stateLabel = label(L.stateBox, L.stateFont, T.color.label, L.stateAlign)
  end
  if L.showMinMaxText then
    ui.minText = label(L.minTextBox, L.minMaxFont, T.color.history, LEFT)
    ui.maxText = label(L.maxTextBox, L.minMaxFont, T.color.history, RIGHT)
  end
  if L.showScale then
    ui.scaleMin = label(L.scaleMinBox, L.scaleFont, T.color.label, CENTER,
                        F.display(widget, widget.config.min))
    ui.scaleMax = label(L.scaleMaxBox, L.scaleFont, T.color.label, CENTER,
                        F.display(widget, widget.config.max))
  end

  widget.frame = {
    props = {},
    angle = -1, ghostAngle = -1, minAngle = -1, maxAngle = -1,
    needleShown = true, markersShown = false, chipShown = false,
    colorKey = "", valueStr = "", stateStr = "", minStr = "", maxStr = "",
    prevAvail = "unset", pulse = false, pulseAt = 0,
  }
  ui.built = true
end

-- ---------------------------------------------------------------- colours --

-- Semantic key for the current frame. Gradient mode quantises the ramp so a
-- slowly drifting value does not repaint on every frame.
function M.colorKey(widget)
  local data, cfg = widget.data, widget.config
  if data.availability ~= "valid" or data.displayValue == nil then
    return "muted"
  end
  if widget.source.isTimer and data.value and data.value < 0 then
    return "warning"  -- elapsed countdown, as the official Value widget does
  end
  if cfg.colorMode == M.COLOR_STATIC then return "static" end
  if cfg.colorMode == M.COLOR_GRADIENT then
    -- ramp across the THRESHOLDS, not the whole scale: red at the critical
    -- boundary, green once the value is in the normal band (GaugeRotary's
    -- getRangeColor semantics). A gradient over min..max would show green
    -- while the value sits just above the warning line.
    local lo, hi = cfg.crit, cfg.warn
    if lo > hi then lo, hi = hi, lo end
    local t = G.normalize(data.displayValue, lo, hi)
    if not cfg.highGood then t = 1 - t end
    return "grad" .. floor(t * 20)
  end
  return data.state or "normal"
end

local function resolveColor(widget, key)
  if key == "static" then return widget.accent or T.color.accent end
  if string.sub(key, 1, 4) == "grad" then
    local step = tonumber(string.sub(key, 5)) or 0
    return T.gradientColor(step / 20)
  end
  return T.stateColor(key, widget.accent)
end

local function applyColors(widget, key)
  local ui = widget.ui
  local c = resolveColor(widget, key)
  local opa = (key == "muted") and T.opacity.muted or T.opacity.full
  setProp(widget, ui.valueArc, "color", c)
  setProp(widget, ui.valueArc, "opacity", opa)
  setProp(widget, ui.valueLabel, "color", c)
  setProp(widget, ui.needle, "color", c)
  setProp(widget, ui.tail, "color", c)
  setProp(widget, ui.pivotDot, "color", c)
  if ui.stateLabel then
    local sc = T.color.label
    if key == "warning" then sc = T.color.warn
    elseif key == "critical" then sc = T.color.crit end
    setProp(widget, ui.stateLabel, "color", sc)
  end
end

-- ---------------------------------------------------------------- updates --

local function stateText(widget)
  local data = widget.data
  local a = data.availability
  if a == "unset" then return "NO SOURCE" end
  if a == "disconnected" then return "NO LINK" end
  if a == "stale" then return "STALE" end
  if a ~= "valid" then return "NO DATA" end
  if data.state == "warning" then return "WARN" end
  if data.state == "critical" then return "CRIT" end
  return ""
end
M.stateText = stateText

local function updateText(widget)
  local ui, frame = widget.ui, widget.frame
  local data = widget.data

  local str
  if data.availability == "unset" then
    str = F.NO_VALUE
  else
    str = F.display(widget, data.displayValue)
  end
  if str ~= frame.valueStr then
    frame.valueStr = str
    setProp(widget, ui.valueLabel, "text", str)
  end

  if ui.stateLabel then
    local s = stateText(widget)
    if s ~= frame.stateStr then
      frame.stateStr = s
      setProp(widget, ui.stateLabel, "text", s)
      local show = (s ~= "")
      if ui.chip then
        if show then
          -- the chip hugs its text: measured here because the state string
          -- changes rarely (never per frame), unlike the value
          local L = widget.layout
          local w = T.textWidth(s, L.stateFont) + L.chipPad * 2
          local x = L.stateBox.x
          if L.stateAlign == CENTER then
            x = L.stateBox.x + floor((L.stateBox.w - w) / 2)
          elseif L.stateAlign == RIGHT then
            x = L.stateBox.x + L.stateBox.w - w
          end
          setProp(widget, ui.chip, "x", x)
          setProp(widget, ui.chip, "w", w)
          lvgl.show(ui.chip)
        else
          lvgl.hide(ui.chip)
        end
        frame.chipShown = show
      end
    end
  end

  if ui.minText then
    local h = widget.history
    local mn = h.min and F.display(widget, h.min) or ""
    local mx = h.max and F.display(widget, h.max) or ""
    if mn ~= frame.minStr then
      frame.minStr = mn
      setProp(widget, ui.minText, "text", (mn ~= "") and ("min " .. mn) or "")
    end
    if mx ~= frame.maxStr then
      frame.maxStr = mx
      setProp(widget, ui.maxText, "text", (mx ~= "") and ("max " .. mx) or "")
    end
  end
end

local function updateArc(widget)
  local ui, L, frame = widget.ui, widget.layout, widget.frame
  local data = widget.data

  if data.availability ~= "valid" or data.displayValue == nil then
    widget.smooth.value = nil
    if frame.needleShown then
      frame.needleShown = false
      if ui.needle then lvgl.hide(ui.needle) end
      if ui.tail then lvgl.hide(ui.tail) end
      if ui.pivotDot then lvgl.hide(ui.pivotDot) end
    end
    return
  end

  if frame.prevAvail ~= "valid" then
    widget.smooth.value = nil  -- snap on reconnect instead of sweeping up
  end
  local sv = widget.mods.smoothing.step(widget, data.displayValue)
  local a = angleOf(widget, sv)
  if a ~= frame.angle then
    frame.angle = a
    setProp(widget, ui.valueArc, "endAngle", a)
    if ui.needle then
      lvgl.set(ui.needle, { pts = G.trianglePoints(L.cx, L.cy, L.needleInner,
        L.needleOuter, L.needleHalf, a) })
      lvgl.set(ui.tail, { pts = G.trianglePoints(L.cx, L.cy, L.needleInner,
        L.tailOuter, max(1, floor(L.needleHalf * 0.7)), a + 180) })
    end
  end
  if not frame.needleShown then
    frame.needleShown = true
    if ui.needle then lvgl.show(ui.needle) end
    if ui.tail then lvgl.show(ui.tail) end
    if ui.pivotDot then lvgl.show(ui.pivotDot) end
  end
end

local function updateHistory(widget)
  local ui, L, frame = widget.ui, widget.layout, widget.frame
  local h = widget.history
  if not ui.minMark then return end

  local shown = (h.min ~= nil and h.max ~= nil)
  if shown ~= frame.markersShown then
    frame.markersShown = shown
    if shown then
      lvgl.show(ui.minMark)
      lvgl.show(ui.maxMark)
    else
      lvgl.hide(ui.minMark)
      lvgl.hide(ui.maxMark)
    end
  end
  if not shown then return end

  local inner = L.radius - floor(L.trackThickness / 2) - T.px(1)
  local outer = L.railRadius + T.px(1)
  local a = angleOf(widget, h.min)
  if a ~= frame.minAngle then
    frame.minAngle = a
    lvgl.set(ui.minMark, { pts = G.linePoints(L.cx, L.cy, inner, outer, a) })
  end
  a = angleOf(widget, h.max)
  if a ~= frame.maxAngle then
    frame.maxAngle = a
    lvgl.set(ui.maxMark, { pts = G.linePoints(L.cx, L.cy, inner, outer, a) })
  end

  -- peak-hold ghost: from the start of the scale to the highest value seen
  if ui.ghost then
    if a ~= frame.ghostAngle then
      frame.ghostAngle = a
      setProp(widget, ui.ghost, "endAngle", a)
      setProp(widget, ui.ghost, "bgEndAngle", a)
      lvgl.show(ui.ghost)
    end
  end
end

-- Critical state pulses at ~1 Hz: attention without colour, so it survives
-- greyscale and colour-blind viewing. Two property writes per second.
local function updatePulse(widget, key)
  local ui, frame = widget.ui, widget.frame
  if key ~= "critical" then
    if frame.pulse then
      frame.pulse = false
      setProp(widget, ui.valueArc, "opacity", T.opacity.full)
    end
    return
  end
  local now = getTime()
  if now - frame.pulseAt >= 50 then  -- 50 * 10 ms
    frame.pulseAt = now
    frame.pulse = not frame.pulse
    setProp(widget, ui.valueArc, "opacity",
            frame.pulse and T.opacity.pulse or T.opacity.full)
  end
end

function M.updateSourceLabels(widget)
  local ui = widget.ui
  if ui.unitLabel then
    setProp(widget, ui.unitLabel, "text", widget.unitText or "")
  end
  if ui.nameLabel then
    setProp(widget, ui.nameLabel, "text", widget.nameText or "")
  end
  if ui.scaleMin then
    setProp(widget, ui.scaleMin, "text", F.display(widget, widget.config.min))
    setProp(widget, ui.scaleMax, "text", F.display(widget, widget.config.max))
  end
end

function M.update(widget)
  local ui = widget.ui
  if not ui.built then return end
  local frame = widget.frame

  local key = M.colorKey(widget)
  if key ~= frame.colorKey then
    frame.colorKey = key
    applyColors(widget, key)
  end

  updateText(widget)
  updateArc(widget)
  updateHistory(widget)
  updatePulse(widget, key)

  frame.prevAvail = widget.data.availability
end

return M
