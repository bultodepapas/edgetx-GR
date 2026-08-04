---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - responsive layout                                          #
---- #                                                                       #
---- # Classifies the zone (mode + orientation + style), computes dial       #
---- # geometry and typography, and places every text into a REGION with an  #
---- # alignment. The renderer never measures text at runtime: LVGL aligns   #
---- # inside the region (lvgl.label supports align + w), so a changing      #
---- # value cannot shift its neighbours.                                    #
---- #                                                                       #
---- # The value area is sized from the widest string the configured scale   #
---- # can produce, so digits keep their position as the value moves.       #
---- #                                                                       #
---- # All physical sizes go through theme.px() (LCD_SCALE), so a "micro"    #
---- # zone means the same physical size on every radio.                     #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local floor, min, max = math.floor, math.min, math.max

local T, G, F  -- theme, geometry, format

function M.setup(theme, geometry, format)
  T, G, F = theme, geometry, format
end

M.STYLE_AUTO, M.STYLE_NEEDLE, M.STYLE_ARC, M.STYLE_BAR = 1, 2, 3, 4
M.SWEEP_270, M.SWEEP_180, M.SWEEP_360 = 1, 2, 3

-- Sweep option -> { startAngle, sweep }. LVGL angles: 0 = 3 o'clock, clockwise.
local SWEEPS = {
  [M.SWEEP_270] = { 135, 270 },
  [M.SWEEP_180] = { 180, 180 },
  [M.SWEEP_360] = { 270, 360 },
}

local function clamp(v, lo, hi)
  return max(lo, min(hi, v))
end

local function box(x, y, w, h)
  return { x = floor(x), y = floor(y), w = floor(w), h = floor(h or 0) }
end

-- mode: micro (<64), compact (<105), normal (<180), large (>=180)
-- orientation: horizontal (>1.4), vertical (<0.8), balanced
function M.classify(w, h)
  local scale = (lvgl and lvgl.LCD_SCALE) or 1
  local side = min(w, h)
  local mode
  if side < 64 * scale then mode = "micro"
  elseif side < 105 * scale then mode = "compact"
  elseif side < 180 * scale then mode = "normal"
  else mode = "large" end
  local ratio = w / h
  local orientation
  if ratio > 1.4 then orientation = "horizontal"
  elseif ratio < 0.8 then orientation = "vertical"
  else orientation = "balanced" end
  return mode, orientation
end

-- A rotary dial needs area; in a long thin zone a linear bar is the honest
-- instrument (GaugeRotary prints "too small" here, which helps nobody).
function M.pickStyle(cfg, w, h)
  if cfg.style == M.STYLE_BAR then return "bar" end
  if cfg.style == M.STYLE_AUTO and (w / h) > 2.6 then return "bar" end
  return "dial"
end

-- Largest font whose text fits both the width and the height available.
local function pickValueFont(sample, unitText, maxW, maxH, cap)
  local ramp = T.RAMP
  local gap = T.px(T.space.sm)
  local started = (cap == nil)
  for i = 1, #ramp do
    local font = ramp[i]
    if not started and font == cap then started = true end
    if started then
      if T.fontHeight(font) <= maxH then
        local unitFont = T.smallerFont(font, 2)
        local w = T.textWidth(sample, font)
        local uw = 0
        if unitText and unitText ~= "" then
          uw = T.textWidth(unitText, unitFont) + gap
        end
        if w + uw <= maxW then
          return font, unitFont, w, uw
        end
      end
    end
  end
  local font = ramp[#ramp]
  local unitFont = font
  local uw = 0
  if unitText and unitText ~= "" then
    uw = T.textWidth(unitText, unitFont) + gap
  end
  return font, unitFont, T.textWidth(sample, font), uw
end

-- Place the value + unit pair centred as a group inside `region`.
local function placeValue(L, region, sample, unitText, cap)
  local valueFont, unitFont, vw, uw =
    pickValueFont(sample, unitText, region.w, region.h, cap)
  L.valueFont = valueFont
  L.unitFont = unitFont
  local vh = T.fontHeight(valueFont)
  local uh = T.fontHeight(unitFont)
  local groupW = vw + uw
  local x0 = region.x + floor((region.w - groupW) / 2)
  local y0 = region.y + floor((region.h - vh) / 2)
  if y0 < region.y then y0 = region.y end
  L.valueBox = box(x0, y0, vw, vh)
  L.valueAlign = RIGHT
  -- unit sits on the value baseline, one step down in the type ramp
  L.unitBox = box(x0 + vw + T.px(T.space.sm), y0 + (vh - uh) - T.px(1), uw, uh)
  L.unitAlign = LEFT
end

-- ------------------------------------------------------------------ dial --

local function dialLayout(widget, cfg, L, w, h)
  local pad = T.px(T.space.md)
  local sweep = SWEEPS[cfg.sweep or M.SWEEP_270] or SWEEPS[M.SWEEP_270]
  L.startAngle, L.sweep = sweep[1], sweep[2]

  local mode, orientation = L.mode, L.orientation
  local side = min(w, h)

  L.showUnit = mode ~= "micro"
  L.showName = (mode == "normal" or mode == "large")
  L.showState = mode ~= "micro"
  L.showMarkers = (cfg.showMinMax or 1) > 1 and mode ~= "micro"
  L.showMinMaxText = (cfg.showMinMax or 1) > 2 and mode == "large"
  -- a full ring starts and ends at the same point: two scale labels would sit
  -- on top of each other
  L.showScale = (mode == "large") and (L.sweep < 360)
  L.showGhost = (mode ~= "micro")

  L.nameFont = T.FONTS.XS
  L.stateFont = T.FONTS.XS
  L.minMaxFont = T.FONTS.XXS
  L.scaleFont = T.FONTS.XXS
  local nameH = T.fontHeight(L.nameFont)
  local stateH = T.fontHeight(L.stateFont)
  local minMaxH = T.fontHeight(L.minMaxFont)

  -- dial box and text region per orientation
  local dial, textRegion, valueRegion
  if orientation == "horizontal" then
    local dialSide = min(w * 0.5, h)
    dial = box(pad, pad, dialSide - pad * 2, h - pad * 2)
    local tx = dial.x + dial.w + T.px(T.space.md)
    textRegion = box(tx, pad, w - tx - pad, h - pad * 2)
    local rows = (L.showName and nameH or 0) + (L.showState and stateH or 0)
      + (L.showMinMaxText and minMaxH or 0)
    valueRegion = box(textRegion.x, textRegion.y,
                      textRegion.w, max(textRegion.h - rows, T.px(12)))
  elseif orientation == "vertical" then
    local dialSide = min(w, h * 0.62)
    dial = box(floor((w - dialSide) / 2) + pad, pad,
               dialSide - pad * 2, dialSide - pad * 2)
    local ty = dial.y + dial.h + T.px(T.space.sm)
    textRegion = box(pad, ty, w - pad * 2, h - ty - pad)
    local rows = (L.showName and nameH or 0) + (L.showMinMaxText and minMaxH or 0)
    valueRegion = box(textRegion.x, textRegion.y,
                      textRegion.w, max(textRegion.h - rows, T.px(12)))
  else
    local nameSpace = L.showName and (nameH + T.px(T.space.xs)) or 0
    local d = min(w, h - nameSpace)
    dial = box(floor((w - d) / 2) + pad, pad, d - pad * 2, d - pad * 2)
    textRegion = dial
    -- value lives inside the lower half of the dial circle
    valueRegion = box(dial.x, dial.y + floor(dial.h * 0.52),
                      dial.w, floor(dial.h * 0.30))
  end

  L.cx = dial.x + floor(dial.w / 2)
  L.cy = dial.y + floor(dial.h / 2)

  -- Ring metrics depend on the zone, not on the radius, so they are computed
  -- first; the radius is then whatever is left after reserving room for
  -- everything drawn OUTSIDE the track (rail, gap, ticks). Deriving the
  -- radius from the box alone pushes the ticks past the zone edge.
  L.trackThickness = clamp(floor(side * T.ratio.trackToRadius / 2),
                           T.px(3), T.px(12))
  L.arcThickness = L.trackThickness
  L.railThickness = max(T.px(2), floor(L.trackThickness * T.ratio.railToTrack))
  L.ghostThickness = max(T.px(2), floor(L.trackThickness * 0.45))
  L.tickCount = (mode == "micro") and 3 or ((mode == "large") and 7 or 5)
  L.tickThickness = clamp(floor(side / 90), 1, T.px(3))
  L.minorTicks = (mode == "large") and (L.tickCount - 1) or 0

  local tickLength = clamp(floor(side / 40), T.px(2), T.px(6))
  local outerReserve = floor(L.trackThickness / 2) + L.railThickness
    + T.px(T.space.xs) + tickLength + 1
  local half = floor(min(dial.w, dial.h) / 2)
  L.radius = max(half - outerReserve, T.px(8))
  L.railRadius = L.radius + floor(L.trackThickness / 2) + L.railThickness
  L.tickInner = L.railRadius + T.px(T.space.xs)
  L.tickOuter = L.tickInner + tickLength

  -- needle
  L.showNeedle = (cfg.style == M.STYLE_NEEDLE)
    or (cfg.style == M.STYLE_AUTO and mode ~= "micro")
  if L.showNeedle then
    L.needleInner = clamp(floor(L.radius * 0.16), T.px(3), T.px(20))
    L.needleOuter = L.radius - floor(L.trackThickness / 2) - T.px(1)
    L.needleHalf = clamp(floor(L.radius * T.ratio.needleWidth), T.px(2), T.px(7))
    L.tailOuter = floor(L.needleOuter * T.ratio.tailLength)
    L.pivotRadius = clamp(floor(L.radius * T.ratio.pivotRadius),
                          T.px(3), T.px(9))
  end

  -- typography and text regions
  local cap = (mode == "micro") and T.FONTS.XS
    or ((mode == "compact") and T.FONTS.L or nil)
  placeValue(L, valueRegion, F.widestSample(widget), widget.unitText, cap)

  local align = (orientation == "horizontal") and LEFT or CENTER
  if orientation == "horizontal" then
    local y = L.valueBox.y + L.valueBox.h + T.px(T.space.xs)
    L.stateBox = box(textRegion.x, y, textRegion.w, stateH)
    y = y + (L.showState and stateH + T.px(T.space.xs) or 0)
    L.minMaxBox = box(textRegion.x, y, textRegion.w, minMaxH)
    L.nameBox = box(textRegion.x, textRegion.y + textRegion.h - nameH,
                    textRegion.w, nameH)
  elseif orientation == "vertical" then
    local y = L.valueBox.y + L.valueBox.h + T.px(T.space.xs)
    L.minMaxBox = box(textRegion.x, y, textRegion.w, minMaxH)
    L.nameBox = box(textRegion.x, textRegion.y + textRegion.h - nameH,
                    textRegion.w, nameH)
    L.stateBox = box(dial.x, dial.y + floor(dial.h * 0.24), dial.w, stateH)
  else
    L.stateBox = box(dial.x, dial.y + floor(dial.h * 0.26), dial.w, stateH)
    L.minMaxBox = box(dial.x, L.valueBox.y + L.valueBox.h + T.px(T.space.xs),
                      dial.w, minMaxH)
    if L.sweep >= 360 then
      -- a closed ring has no gap at the bottom to hang the name in: keep it
      -- inside, under the value
      L.nameBox = box(dial.x, L.valueBox.y + L.valueBox.h + T.px(T.space.xs),
                      dial.w, nameH)
      L.showMinMaxText = false
    else
      L.nameBox = box(0, dial.y + dial.h - nameH, w, nameH)
    end
  end
  L.textAlign = align
  L.nameAlign = align
  L.stateAlign = align

  -- min / max text share the min-max row
  local halfW = floor(L.minMaxBox.w / 2)
  L.minTextBox = box(L.minMaxBox.x, L.minMaxBox.y, halfW, minMaxH)
  L.maxTextBox = box(L.minMaxBox.x + halfW, L.minMaxBox.y, halfW, minMaxH)

  -- scale end labels, centred on the arc ends
  if L.showScale then
    local r = L.tickOuter + T.px(T.space.sm)
    local sw = T.px(30)
    local x1, y1 = G.pointOnCircle(L.cx, L.cy, r, L.startAngle)
    local x2, y2 = G.pointOnCircle(L.cx, L.cy, r, L.startAngle + L.sweep)
    local sh = T.fontHeight(L.scaleFont)
    L.scaleMinBox = box(x1 - sw / 2, y1 - sh / 2, sw, sh)
    L.scaleMaxBox = box(x2 - sw / 2, y2 - sh / 2, sw, sh)
    -- do not let the labels leave the zone
    if L.scaleMinBox.x < 0 then L.scaleMinBox.x = 0 end
    if L.scaleMaxBox.x + sw > w then L.scaleMaxBox.x = w - sw end
    if L.scaleMinBox.y + sh > h then L.showScale = false end
  end

  -- chip behind the state text
  L.chipPad = T.px(T.space.sm)
  L.chipHeight = stateH + T.px(2)
end

-- ------------------------------------------------------------------- bar --

local function barLayout(widget, cfg, L, w, h)
  local pad = T.px(T.space.sm)
  L.showUnit = true
  L.showName = h >= T.px(46)
  L.showState = w >= T.px(120)
  L.showMarkers = (cfg.showMinMax or 1) > 1
  L.showMinMaxText = false
  L.showScale = false
  L.showGhost = true
  L.showNeedle = false

  L.nameFont = T.FONTS.XS
  L.stateFont = T.FONTS.XS
  L.minMaxFont = T.FONTS.XXS
  local nameH = L.showName and T.fontHeight(L.nameFont) or 0

  local barH = clamp(floor(h * 0.34), T.px(8), T.px(26))
  local textH = h - barH - nameH - pad * 3
  if textH < T.px(12) then
    textH = max(h - barH - pad * 2, T.px(12))
    L.showName = false
    nameH = 0
  end

  local valueRegion = box(pad, pad, w - pad * 2, textH)
  placeValue(L, valueRegion, F.widestSample(widget), widget.unitText,
             (h < T.px(60)) and T.FONTS.M or nil)

  L.bar = box(pad, pad + textH + pad, w - pad * 2, barH)
  L.barRadius = floor(barH / 2)
  L.nameBox = box(pad, L.bar.y + barH + pad, floor((w - pad * 2) / 2), nameH)
  L.stateBox = box(pad + floor((w - pad * 2) / 2), L.bar.y + barH + pad,
                   floor((w - pad * 2) / 2), nameH)
  L.nameAlign = LEFT
  L.stateAlign = RIGHT
  L.textAlign = LEFT
  L.chipPad = T.px(T.space.xs)
  L.chipHeight = nameH
  L.markThickness = max(1, T.px(2))
end

-- --------------------------------------------------------------- entry ----

function M.calculate(widget, cfg)
  local w, h = widget.zone.w, widget.zone.h
  local mode, orientation = M.classify(w, h)
  local L = { mode = mode, orientation = orientation, w = w, h = h }
  L.style = M.pickStyle(cfg, w, h)
  if L.style == "bar" then
    barLayout(widget, cfg, L, w, h)
  else
    dialLayout(widget, cfg, L, w, h)
  end
  return L
end

-- Structural signature: a change here means the object tree must be rebuilt.
-- Anything that only moves or recolours an existing object stays out of it.
function M.signature(L, cfg)
  return table.concat({
    L.style, L.mode, L.orientation,
    L.showNeedle and 1 or 0, L.showUnit and 1 or 0, L.showName and 1 or 0,
    L.showState and 1 or 0, L.showMarkers and 1 or 0,
    L.showMinMaxText and 1 or 0, L.showScale and 1 or 0,
    cfg.colorMode, cfg.sweep or 1, L.valueFont, L.radius or 0,
    L.w, L.h,
  }, ":")
end

return M
