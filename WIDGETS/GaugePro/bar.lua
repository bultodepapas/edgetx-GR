---- #########################################################################
---- #                                                                       #
---- # Gauge Pro - linear (bar) renderer                                      #
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

local floor = math.floor

local T, G, F, R, Faces  -- shared helpers + retained face registry

function M.setup(theme, geometry, format, renderer, faces)
  T, G, F, R, Faces = theme, geometry, format, renderer, faces
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

-- A vertical mark that MOVES: its pts buffer and its { pts = ... } wrapper
-- are created once and reused forever, the needle's Phase 5.1/5.2 contract
-- applied to the two marks Phase 5 left behind. luaLvglSet parses the params
-- table at call time and keeps no reference to it, and LvglWidgetLine::getPts
-- copies the coordinates out, so mutating both in place is legal.
-- NEVER route these through R.setProp: its cache compares tables by identity
-- and would drop every write after the first (5.1/5.2 TRAP 2).
-- The static threshold marks keep plain vline() above - they never move.
local function movingMark(ui, key, x, y1, y2, thickness, color)
  local pts = { { x, y1 }, { x, y2 } }
  ui[key .. "Pts"] = pts
  ui[key .. "Set"] = { pts = pts }
  ui[key] = lvgl.line{ pts = pts, thickness = thickness, color = color }
  lvgl.hide(ui[key])
end

local function moveMark(ui, key, x)
  local pts = ui[key .. "Pts"]
  pts[1][1], pts[2][1] = x, x
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
  if cfg.colorMode ~= R.COLOR_STATIC then
    ui.marks = {}
    for i = 1, #widget.ranges do
      local r = widget.ranges[i]
      local t = G.normalize(r.to, cfg.min, cfg.max)
      if t > 0 and t < 1 then
        local m = vline(markX(widget, r.to), b.y, b.h,
          L.markThickness,
          T.stateColor(r.role, widget.accent, widget.barPalette))
        -- role rides on the object so an accent edit can recolor the
        -- normal-boundary mark without pairing by index (Tanda 6 F-5)
        m.role = r.role
        ui.marks[#ui.marks + 1] = m
      end
    end
  end

  -- markOverhang comes from the layout, which RESERVED it in the vertical
  -- budget: restating it here as px(2)/px(4) is what let the markers hang
  -- past the bottom of a row-less short bar. It also fixes an asymmetry -
  -- px(4) is not 2 * px(2) at LCD_SCALE 0.8, so the old line stuck out 2 px
  -- above and only 1 px below on a 320 px screen.
  local over = L.markOverhang
  local markTop, markBottom = b.y - over, b.y + b.h + over
  if L.showGhost then
    movingMark(ui, "ghost", b.x, markTop, markBottom, L.markThickness,
               (widget.barPalette and widget.barPalette.history)
                 or T.color.history)
  end
  if L.showMarkers then
    movingMark(ui, "minMark", b.x, markTop, markBottom, L.markThickness,
               (widget.barPalette and widget.barPalette.history)
                 or T.color.history)
  end

  -- DATA text takes the theme's ink role, not the status colour (Tanda 8
  -- §3.2) - see renderer.valueColor.
  local palette = widget.barPalette
  ui.valueLabel = R.label(L.valueBox, L.valueFont,
                          (palette and palette.value) or T.color.value,
                          L.valueAlign, F.NO_VALUE)
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

  widget.frame = {
    props = {},
    dirty = {},
    fillW = -1, ghostX = -1, minX = -1,
    needleShown = true, markersShown = false, chipShown = false,
    colorKey = "", accentKey = nil, paletteSig = palette and palette.signature,
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
      local x = markX(widget, peak)
      if x ~= frame.ghostX then
        frame.ghostX = x
        moveMark(ui, "ghost", x)
      end
    elseif frame.ghostX ~= -1 then
      frame.ghostX = -1
      lvgl.hide(ui.ghost)
    end
  end
  if ui.minMark then
    if h.min then
      local x = markX(widget, h.min)
      if x ~= frame.minX then
        frame.minX = x
        moveMark(ui, "minMark", x)
      end
    elseif frame.minX ~= -1 then
      frame.minX = -1
      lvgl.hide(ui.minMark)
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
      end
    end
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
  R.updatePulse(widget, key, ui.fill)

  R.flush(widget)
  frame.prevAvail = widget.data.availability
end

return M
