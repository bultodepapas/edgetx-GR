---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - linear (bar) renderer                                      #
---- #                                                                       #
---- # Same data model, state colours and history as the dial; used when a   #
---- # rotary dial cannot work: very wide/short zones, or Style = Bar.       #
---- # A 40 px dial in a 200x50 slot is decoration, not an instrument.       #
---- #                                                                       #
---- # Only rectangles and lines, so it stays cheap (about ten objects).     #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local floor, max = math.floor, math.max

local T, G, F, R  -- theme, geometry, format, renderer (shared helpers)

function M.setup(theme, geometry, format, renderer)
  T, G, F, R = theme, geometry, format, renderer
  -- Source-edit text path: shared with the dial (Tanda 6 F-15). The bar has
  -- no scale labels, so the shared helper's guarded fields no-op here. The
  -- alias is assigned HERE - R is nil until setup runs.
  M.updateSourceLabels = R.updateSourceLabels
end

local function markX(widget, value)
  local L, cfg = widget.layout, widget.config
  local t = G.normalize(value, cfg.min, cfg.max)
  return L.bar.x + floor(L.bar.w * t + 0.5)
end

local function vline(x, y, h, thickness, color)
  return lvgl.line{
    pts = { { x, y }, { x, y + h } },
    thickness = thickness, color = color,
  }
end

function M.build(widget)
  local L, ui, cfg = widget.layout, widget.ui, widget.config
  local b = L.bar

  ui.track = lvgl.rectangle{
    x = b.x, y = b.y, w = b.w, h = b.h,
    color = T.color.rail, filled = 1, rounded = L.barRadius,
    opacity = T.opacity.rail,
  }

  -- The fill is created BEFORE the threshold marks so the marks paint on top
  -- of it, not under it: a mark sitting inside the filled portion of the bar
  -- must stay visible there too (AUDIT.md G-12) - that is exactly the
  -- moment a value approaching a threshold most needs the reference line.
  ui.fill = lvgl.rectangle{
    x = b.x, y = b.y, w = 1, h = b.h,
    color = T.color.accent, filled = 1, rounded = L.barRadius,
  }

  -- threshold marks on the track, the linear equivalent of the dial's rail.
  -- Compare the NORMALISED position, not the raw value against cfg.min/max:
  -- on a descending scale (Min > Max) `r.to > cfg.min and r.to < cfg.max` is
  -- never true, so every mark silently vanished (AUDIT.md P0-3). And mark the
  -- BOUNDARY of EVERY band whose end falls strictly inside the scale, not
  -- just the non-normal ones: on a low-is-good scale (normal -> warning ->
  -- critical) the warning threshold is the `to` of the NORMAL band, so the
  -- old condition drew only one mark where the dial draws two rails
  -- (AUDIT.md P1-11).
  if cfg.colorMode ~= R.COLOR_STATIC then
    ui.marks = {}
    for i = 1, #widget.ranges do
      local r = widget.ranges[i]
      local t = G.normalize(r.to, cfg.min, cfg.max)
      if t > 0 and t < 1 then
        local m = vline(markX(widget, r.to), b.y, b.h,
          L.markThickness, T.stateColor(r.role, widget.accent))
        -- role rides on the object so an accent edit can recolor the
        -- normal-boundary mark without pairing by index (Tanda 6 F-5)
        m.role = r.role
        ui.marks[#ui.marks + 1] = m
      end
    end
  end

  if L.showGhost then
    ui.ghost = vline(b.x, b.y - T.px(2), b.h + T.px(4), L.markThickness,
                     T.color.history)
    lvgl.hide(ui.ghost)
  end
  if L.showMarkers then
    ui.minMark = vline(b.x, b.y - T.px(2), b.h + T.px(4), L.markThickness,
                       T.color.history)
    lvgl.hide(ui.minMark)
  end

  ui.valueLabel = R.label(L.valueBox, L.valueFont, T.color.accent,
                          L.valueAlign, F.NO_VALUE)
  if L.showUnit and widget.unitText ~= "" then
    ui.unitLabel = R.label(L.unitBox, L.unitFont, T.color.label, L.unitAlign,
                           widget.unitText)
  end
  if L.showName then
    ui.nameLabel = R.label(L.nameBox, L.nameFont, T.color.label, L.nameAlign,
                           widget.nameText)
  end
  if L.showState then
    -- the state chip: same pill as the dial, so WARN/CRIT/STALE signal
    -- identically in bar zones (AUDIT.md P1-10). Text vertically centred and
    -- a 1 px outline in the lighter label role (review P-B). The centring
    -- offset is LAYOUT data (L.chipOff) - see renderer.build (Tanda 6 F-1).
    ui.chipEdge = lvgl.rectangle{
      x = L.stateBox.x - T.px(1), y = L.stateBox.y - L.chipOff - T.px(1),
      w = L.stateBox.w + T.px(2), h = L.chipHeight + T.px(2),
      color = T.color.label, filled = 1,
      rounded = floor((L.chipHeight + T.px(2)) / 2),
    }
    ui.chip = lvgl.rectangle{
      x = L.stateBox.x, y = L.stateBox.y - L.chipOff,
      w = L.stateBox.w, h = L.chipHeight,
      color = T.color.chip, filled = 1, rounded = floor(L.chipHeight / 2),
    }
    lvgl.hide(ui.chipEdge)
    lvgl.hide(ui.chip)
    ui.stateLabel = R.label(L.stateBox, L.stateFont, T.color.label,
                            L.stateAlign)
  end

  widget.frame = {
    props = {},
    dirty = {},
    fillW = -1, ghostX = -1, minX = -1,
    needleShown = true, markersShown = false, chipShown = false,
    colorKey = "", accentKey = nil, valueStr = "", stateStr = "",
    minStr = "", maxStr = "",
    prevAvail = "unset", pulse = false, pulseAt = 0,
  }
  ui.built = true
end

local function updateFill(widget)
  local ui, L, frame = widget.ui, widget.layout, widget.frame
  local data = widget.data
  if data.availability ~= "valid" or data.displayValue == nil then
    widget.smooth.value = nil
    if frame.fillW ~= 0 then
      frame.fillW = 0
      R.setProp(widget, ui.fill, "w", 1)
    end
    return
  end
  if frame.prevAvail ~= "valid" then widget.smooth.value = nil end
  local sv = widget.mods.smoothing.step(widget, data.displayValue)
  local w = max(G.barFill(L.bar.w, sv, widget.config.min, widget.config.max), 1)
  if w ~= frame.fillW then
    frame.fillW = w
    R.setProp(widget, ui.fill, "w", w)
  end
end

local function updateHistory(widget)
  local ui, L, frame = widget.ui, widget.layout, widget.frame
  local h = widget.history
  if ui.ghost and h.min and h.max then
    -- peak-hold marker: the extreme of the SWEEP, which is h.min on a
    -- descending scale (Min > Max) - h.max maps back onto the start there
    -- and the ghost marked the tract never visited (Tanda 6 F-3). Both
    -- bounds are required: readHistorySiblings can populate one alone, and
    -- the descending peak picks either one (Tanda 6 F-8 hardens the guard).
    local peak = (widget.config.max >= widget.config.min) and h.max or h.min
    local x = markX(widget, peak)
    if x ~= frame.ghostX then
      frame.ghostX = x
      lvgl.set(ui.ghost, { pts = { { x, L.bar.y - T.px(2) },
                                   { x, L.bar.y + L.bar.h + T.px(2) } } })
      lvgl.show(ui.ghost)
    end
  end
  if ui.minMark and h.min then
    local x = markX(widget, h.min)
    if x ~= frame.minX then
      frame.minX = x
      lvgl.set(ui.minMark, { pts = { { x, L.bar.y - T.px(2) },
                                     { x, L.bar.y + L.bar.h + T.px(2) } } })
      lvgl.show(ui.minMark)
    end
  end
end

-- Critical state pulses the fill at ~1 Hz, exactly as the dial pulses its
-- arc, so a bar communicates severity the same way a dial does
-- (AUDIT.md P1-10). Shared helper (Tanda 6 F-15): the dial pulses
-- ui.valueArc, the bar pulses ui.fill.

function M.update(widget)
  local ui, frame = widget.ui, widget.frame
  if not ui.built then return end

  local key = R.colorKey(widget)
  -- the accent is an input to the colour: see renderer.update (Tanda 6 F-5)
  if key ~= frame.colorKey or widget.accent ~= frame.accentKey then
    frame.colorKey = key
    frame.accentKey = widget.accent
    local c = R.resolveColor(widget, key)
    R.setProp(widget, ui.fill, "color", c)
    R.setProp(widget, ui.fill, "opacity",
              (key == "muted") and T.opacity.muted or T.opacity.full)
    R.setProp(widget, ui.valueLabel, "color", c)
    if ui.marks then
      -- threshold marks were painted at build time; the normal-boundary
      -- mark carries the accent and must follow an accent edit (F-5)
      for _, m in ipairs(ui.marks) do
        R.setProp(widget, m, "color", T.stateColor(m.role, widget.accent))
      end
    end
    if ui.stateLabel then
      local sc = T.color.label
      if key == "warning" then sc = T.color.warn
      elseif key == "critical" then sc = T.color.crit end
      R.setProp(widget, ui.stateLabel, "color", sc)
    end
  end

  local str = (widget.data.availability == "unset") and F.NO_VALUE
    or F.display(widget, widget.data.displayValue)
  if str ~= frame.valueStr then
    frame.valueStr = str
    R.setProp(widget, ui.valueLabel, "text", str)
    R.anchorUnit(widget, str)
  end
  if ui.stateLabel then
    local s = R.stateText(widget)
    if s ~= frame.stateStr then
      frame.stateStr = s
      R.setProp(widget, ui.stateLabel, "text", s)
      R.updateChip(widget, s)
    end
  end

  updateFill(widget)
  updateHistory(widget)
  R.updatePulse(widget, key, ui.fill)

  R.flush(widget)
  frame.prevAvail = widget.data.availability
end

return M
