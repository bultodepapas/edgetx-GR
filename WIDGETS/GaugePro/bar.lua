---- #########################################################################
---- #                                                                       #
---- # Gauge Pro - linear (bar) renderer                                      #
---- #                                                                       #
---- # Same data model, state colours and history as the dial; used when a   #
---- # rotary dial cannot work: very wide/short zones, or Style = Bar.       #
---- # A 40 px dial in a 200x50 slot is decoration, not an instrument.       #
---- #                                                                       #
---- # Retained rectangles, lines and chamfer triangles stay under the       #
---- # Continuous face's measured object/instruction ceilings.               #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local floor, max = math.floor, math.max

local T, G, F, R, Faces  -- shared helpers + retained face registry

function M.setup(theme, geometry, format, renderer, faces)
  T, G, F, R, Faces = theme, geometry, format, renderer, faces
  -- Source-edit text path: shared with the dial (Tanda 6 F-15). The bar has
  -- no scale labels, so the shared helper's guarded fields no-op here. The
  -- alias is assigned HERE - R is nil until setup runs.
  M.updateSourceLabels = R.updateSourceLabels
end

local function markPosition(widget, value)
  local cfg, axis = widget.config, widget.layout.axis
  local normalized = G.normalize(value, cfg.min, cfg.max)
  return axis.start + axis.growth * floor(axis.length * normalized + 0.5)
end

local function axisLine(axis, position, cross1, cross2, thickness, color,
                        opacity)
  local pts
  if axis.orientation == "vertical" then
    pts = { { cross1, position }, { cross2, position } }
  else
    pts = { { position, cross1 }, { position, cross2 } }
  end
  return lvgl.line{
    pts = pts, thickness = thickness, color = color,
    opacity = opacity or T.opacity.full,
  }
end

-- A vertical mark that MOVES: its pts buffer and its { pts = ... } wrapper
-- are created once and reused forever, the needle's Phase 5.1/5.2 contract
-- applied to the two marks Phase 5 left behind. luaLvglSet parses the params
-- table at call time and keeps no reference to it, and LvglWidgetLine::getPts
-- copies the coordinates out, so mutating both in place is legal.
-- NEVER route these through R.setProp: its cache compares tables by identity
-- and would drop every write after the first (5.1/5.2 TRAP 2).
-- The static threshold marks keep plain vline() above - they never move.
local function movingMark(ui, key, axis, position, cross1, cross2, thickness,
                          color, opacity)
  local pts
  if axis.orientation == "vertical" then
    pts = { { cross1, position }, { cross2, position } }
  else
    pts = { { position, cross1 }, { position, cross2 } }
  end
  ui[key .. "Pts"] = pts
  ui[key .. "Set"] = { pts = pts }
  ui[key] = lvgl.line{
    pts = pts, thickness = thickness, color = color,
    opacity = opacity or T.opacity.full,
  }
  lvgl.hide(ui[key])
end

local function moveMark(ui, key, axis, position)
  local pts = ui[key .. "Pts"]
  local coordinate = (axis.orientation == "vertical") and 2 or 1
  pts[1][coordinate], pts[2][coordinate] = position, position
  lvgl.set(ui[key], ui[key .. "Set"])
  lvgl.show(ui[key])
end

function M.build(widget)
  local L, ui, cfg = widget.layout, widget.ui, widget.config
  local b = L.bar
  local visual = widget.barVisual or {
    face = "continuous", profile = {}, segments = 10,
  }
  local face, fallback = Faces.select(visual.face, visual.profile, visual)
  widget.barFace = face
  widget.barFaceName = face.name
  visual.faceFallback = fallback
  if fallback then visual.downgrades[#visual.downgrades + 1] = fallback end
  assert(face.build(widget, b, visual), "GaugePro: bar face build failed")

  -- threshold marks on the track, the linear equivalent of the dial's rail.
  -- Compare the NORMALISED position, not the raw value against cfg.min/max:
  -- on a descending scale (Min > Max) `r.to > cfg.min and r.to < cfg.max` is
  -- never true, so every mark silently vanished (AUDIT.md P0-3). And mark the
  -- BOUNDARY of EVERY band whose end falls strictly inside the scale, not
  -- just the non-normal ones: on a low-is-good scale (normal -> warning ->
  -- critical) the warning threshold is the `to` of the NORMAL band, so the
  -- old condition drew only one mark where the dial draws two rails
  -- (AUDIT.md P1-11).
  local marksMode = visual.marks or "auto"
  local showThresholds = marksMode == "thresholds" or marksMode == "full"
    or (marksMode == "auto" and cfg.colorMode ~= R.COLOR_STATIC)
  local showEnds = marksMode == "ends" or marksMode == "full"
  if showThresholds then
    ui.marks = {}
    for i = 1, #widget.ranges do
      local r = widget.ranges[i]
      local t = G.normalize(r.to, cfg.min, cfg.max)
      if t > 0 and t < 1 then
        local body, axis = L.barOuter or b, L.axis
        local cross1 = (axis.orientation == "vertical") and body.x or body.y
        local cross2 = cross1
          + ((axis.orientation == "vertical") and body.w or body.h)
        local m = axisLine(axis, markPosition(widget, r.to), cross1, cross2,
          L.markThickness, T.stateColor(r.role, widget.accent,
                                       widget.barPalette))
        -- role rides on the object so an accent edit can recolor the
        -- normal-boundary mark without pairing by index (Tanda 6 F-5)
        m.role = r.role
        ui.marks[#ui.marks + 1] = m
      end
    end
  end

  if showEnds then
    ui.endMarks = {}
    local body, axis = L.barOuter or b, L.axis
    local cross1 = (axis.orientation == "vertical") and body.x or body.y
    local cross2 = cross1
      + ((axis.orientation == "vertical") and body.w or body.h)
    for i = 1, 2 do
      ui.endMarks[i] = axisLine(axis,
        G.axisPoint(axis, (i == 1) and 0 or 1), cross1, cross2,
        L.markThickness,
        (widget.barPalette and widget.barPalette.label) or T.color.label,
        T.opacity.railBand)
    end
  end

  -- markOverhang comes from the layout, which RESERVED it in the vertical
  -- budget: restating it here as px(2)/px(4) is what let the markers hang
  -- past the bottom of a row-less short bar. It also fixes an asymmetry -
  -- px(4) is not 2 * px(2) at LCD_SCALE 0.8, so the old line stuck out 2 px
  -- above and only 1 px below on a 320 px screen.
  local over = L.markOverhang
  local body = L.barOuter or b
  local axis = L.axis
  local crossStart = (axis.orientation == "vertical")
    and (body.x - over) or (body.y - over)
  local crossEnd = (axis.orientation == "vertical")
    and (body.x + body.w + over) or (body.y + body.h + over)
  local crossMid = (axis.orientation == "vertical")
    and (body.x + floor(body.w / 2)) or (body.y + floor(body.h / 2))
  if L.showGhost then
    movingMark(ui, "ghost", axis, axis.start, crossStart, crossEnd,
               L.markThickness,
               (widget.barPalette and widget.barPalette.history)
                 or T.color.history, T.opacity.ghost)
  end
  if L.showMarkers then
    -- Min and max are independent authored readings. Split their ticks around
    -- the rail centre so coincident extrema remain distinguishable without
    -- inventing a color meaning.
    movingMark(ui, "minMark", axis, axis.start, crossStart, crossMid,
               L.markThickness,
               (widget.barPalette and widget.barPalette.history)
                 or T.color.history)
    movingMark(ui, "maxMark", axis, axis.start, crossMid, crossEnd,
               L.markThickness,
               (widget.barPalette and widget.barPalette.history)
                 or T.color.history)
  end

  if visual.origin == "zero" then
    movingMark(ui, "zeroMark", axis, axis.originCoord, crossStart, crossEnd,
      max(L.markThickness, T.px(2)),
      (widget.barPalette and widget.barPalette.label) or T.color.label,
      T.opacity.full)
    lvgl.show(ui.zeroMark)
  end

  assert(face.buildOverlay(widget, b, visual) ~= false,
         "GaugePro: bar face overlay build failed")

  -- DATA text takes the theme's ink role, not the status colour (Tanda 8
  -- §3.2) - see renderer.valueColor.
  local palette = widget.barPalette
  if L.showValue ~= false then
    ui.valueLabel = R.label(L.valueBox, L.valueFont,
                            (palette and palette.value) or T.color.value,
                            L.valueAlign, F.NO_VALUE)
  end
  if L.showUnit and widget.unitText ~= "" then
    ui.unitLabel = R.label(L.unitBox, L.unitFont,
                           (palette and palette.label) or T.color.label,
                           L.unitAlign,
                           widget.unitText)
  end
  if L.showName then
    ui.nameLabel = R.label(L.nameBox, L.nameFont,
                           (palette and palette.label) or T.color.label,
                           L.nameAlign,
                           widget.nameText)
  end
  if L.showState then
    -- the state chip: same pill as the dial, so WARN/CRIT/STALE signal
    -- identically in bar zones (AUDIT.md P1-10). Text vertically centred and
    -- a 1 px outline in the lighter label role (review P-B). The centring
    -- offset is LAYOUT data (L.chipOff) - see renderer.build (Tanda 6 F-1).
    local edge = L.chipOutline
    ui.chipEdge = lvgl.rectangle{
      x = L.stateBox.x - edge, y = L.stateBox.y - L.chipOff - edge,
      w = L.stateBox.w + edge * 2, h = L.chipHeight + edge * 2,
      color = (palette and palette.label) or T.color.label, filled = 1,
      rounded = floor((L.chipHeight + edge * 2) / 2),
    }
    -- built muted, shown coloured: R.updateChip owns the fill and the ink
    ui.chip = lvgl.rectangle{
      x = L.stateBox.x, y = L.stateBox.y - L.chipOff,
      w = L.stateBox.w, h = L.chipHeight,
      color = (palette and palette.muted) or T.color.muted,
      filled = 1, rounded = floor(L.chipHeight / 2),
    }
    lvgl.hide(ui.chipEdge)
    lvgl.hide(ui.chip)
    local muted = (palette and palette.muted) or T.color.muted
    ui.stateLabel = R.label(L.stateBox, L.stateFont, T.labelOn(muted, palette),
                            L.stateAlign)
    lvgl.hide(ui.stateLabel)
  end

  local initialPaletteSig = palette and palette.signature
  if ui.gradientSlices then initialPaletteSig = nil end
  widget.frame = {
    props = {},
    dirty = {},
    fillW = -1, fillStart = -1, fillLength = -1,
    fillShown = false, headX = -1, headPos = -1, headShown = false,
    gradientWhole = -1,
    ghostX = -1, minX = -1, maxX = -1,
    ghostPos = -1, minPos = -1, maxPos = -1,
    needleShown = true, markersShown = false, chipShown = false,
    colorKey = "", accentKey = nil, paletteSig = initialPaletteSig,
    valueStr = "", stateStr = "",
    minStr = "", maxStr = "",
    prevAvail = "unset", pulse = false, pulseAt = 0,
  }
  Faces.buildRenderState(widget)
  ui.built = true
end

local function updateHistory(widget)
  local ui, frame = widget.ui, widget.frame
  local h = widget.history
  -- Both marks LEAVE when the history is cleared (the reset switch, a source
  -- change, a range edit). They used to stay behind pointing at a peak that
  -- no longer existed, and only corrected themselves on the next valid
  -- reading - indefinitely, if the reset happened during a dropout. markX()
  -- always returns at least L.bar.x (>= pad >= 1), so -1 is no real position
  -- and doubles as the build-time "never placed" sentinel.
  if ui.ghost then
    if h.min and h.max then
      -- peak-hold marker: the extreme of the SWEEP, which is h.min on a
      -- descending scale (Min > Max) - h.max maps back onto the start there
      -- and the ghost marked the tract never visited (Tanda 6 F-3). Both
      -- bounds are required: readHistorySiblings can populate one alone, and
      -- the descending peak picks either one (Tanda 6 F-8 hardens the guard).
      local peak = (widget.config.max >= widget.config.min) and h.max or h.min
      local position = markPosition(widget, peak)
      if position ~= frame.ghostPos then
        frame.ghostPos, frame.ghostX = position, position
        moveMark(ui, "ghost", widget.layout.axis, position)
      end
    elseif frame.ghostX ~= -1 then
      frame.ghostX, frame.ghostPos = -1, -1
      lvgl.hide(ui.ghost)
    end
  end
  if ui.minMark then
    if h.min then
      local position = markPosition(widget, h.min)
      if position ~= frame.minPos then
        frame.minPos, frame.minX = position, position
        moveMark(ui, "minMark", widget.layout.axis, position)
      end
    elseif frame.minX ~= -1 then
      frame.minX, frame.minPos = -1, -1
      lvgl.hide(ui.minMark)
    end
  end
  if ui.maxMark then
    if h.max then
      local position = markPosition(widget, h.max)
      if position ~= frame.maxPos then
        frame.maxPos, frame.maxX = position, position
        moveMark(ui, "maxMark", widget.layout.axis, position)
      end
    elseif frame.maxX ~= -1 then
      frame.maxX, frame.maxPos = -1, -1
      lvgl.hide(ui.maxMark)
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

  local state = Faces.updateRenderState(widget)
  local key = state.colorKey
  local palette = widget.barPalette
  local paletteSig = palette and palette.signature
  local paletteChanged = paletteSig ~= frame.paletteSig
  state.paletteChanged = paletteChanged
  -- the accent is an input to the colour: see renderer.update (Tanda 6 F-5)
  if key ~= frame.colorKey or widget.accent ~= frame.accentKey
     or paletteChanged then
    frame.colorKey = key
    frame.accentKey = widget.accent
    frame.paletteSig = paletteSig
    widget.barFace.applyPalette(widget, ui, palette, state)
    if ui.marks then
      -- threshold marks were painted at build time; the normal-boundary
      -- mark carries the accent and must follow an accent edit (F-5).
      -- F2: and they follow the fill into the muted state, so a bar with no
      -- data does not keep three fully saturated threshold marks on it.
      for _, m in ipairs(ui.marks) do
        R.setProp(widget, m, "color",
                  T.stateColor(m.role, widget.accent, palette))
        R.setProp(widget, m, "opacity", state.opacity)
        local assist = palette and palette.assist
        local thickness = widget.layout.markThickness
          + ((assist == "strong") and T.px(1) or 0)
        R.setProp(widget, m, "thickness", thickness)
      end
    end
    if ui.endMarks then
      for i = 1, #ui.endMarks do
        R.setProp(widget, ui.endMarks[i], "color", palette.label)
        R.setProp(widget, ui.endMarks[i], "opacity",
                  (state.colorKey == "muted") and T.opacity.muted
                    or T.opacity.railBand)
      end
    end
    if ui.zeroMark then
      R.setProp(widget, ui.zeroMark, "color", palette.label)
      R.setProp(widget, ui.zeroMark, "opacity", T.opacity.full)
    end
    local historyColor = (palette and palette.history) or T.color.history
    if ui.ghost then R.setProp(widget, ui.ghost, "color", historyColor) end
    if ui.minMark then R.setProp(widget, ui.minMark, "color", historyColor) end
    if ui.maxMark then R.setProp(widget, ui.maxMark, "color", historyColor) end
    -- the badge's fill and ink belong to R.updateChip: see renderer.applyColors
  end

  R.applyStateInk(widget, palette)

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
      R.updateChip(widget, s, palette)
    end
  end

  -- A palette/theme edit can recolor a visible badge without changing its
  -- text, so its color gate cannot be the state string alone.
  if paletteChanged and ui.stateLabel and frame.stateStr ~= "" then
    R.updateChip(widget, frame.stateStr, palette)
  end

  widget.barFace.update(widget, ui, state)
  updateHistory(widget)
  R.updatePulse(widget, key, ui.pulseTargets or ui.fill)

  R.flush(widget)
  frame.prevAvail = widget.data.availability
end

return M
