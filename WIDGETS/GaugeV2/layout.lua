---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - responsive layout                                          #
---- #                                                                       #
---- # Classifies the zone (mode + orientation), computes dial geometry,     #
---- # typography, tick density and element visibility. All coordinates are  #
---- # zone-relative and rounded for LVGL. Physical sizes use LCD_SCALE.     #
---- #                                                                       #
---- # Fonts are passed as LcdFlags with the font index in bits 8-11         #
---- # (radio/src/gui/colorlcd/fonts.h FONT_INDEX); no Lua constants exist,  #
---- # so they are defined here.                                             #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local floor, min, max = math.floor, math.min, math.max

-- Font flags come from the firmware's etcxcst Lua constants
-- (radio/src/lua/api_general.cpp): STDSIZE/BOLD/TINSIZE/SMLSIZE/MIDSIZE/
-- DBLSIZE/XXLSIZE/XLSIZE map to font index << 8.
local FONTS = {
  STD = STDSIZE, BOLD = BOLD, XXS = TINSIZE, XS = SMLSIZE,
  L = MIDSIZE, XL = DBLSIZE, XXL = XXLSIZE, LXL = XLSIZE,
}
M.FONTS = FONTS

local START_ANGLE = 135
local SWEEP = 270
M.START_ANGLE = START_ANGLE
M.SWEEP = SWEEP

local function px(value)
  return max(1, floor(value * lvgl.LCD_SCALE + 0.5))
end

local function fontHeight(font)
  local _, h = lcd.sizeText("8", font)
  if type(h) == "number" and h > 0 then return h end
  return 16
end

-- mode: micro (<64), compact (<105), normal (<180), large (>=180)
-- orientation: horizontal (>1.4), vertical (<0.8), balanced
-- Thresholds scale with LCD_SCALE so modes represent physical size
-- (BattAnalog pattern: zone thresholds multiplied by lvgl.LCD_SCALE).
function M.classify(w, h)
  local scale = lvgl.LCD_SCALE or 1
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

local function clamp(v, lo, hi)
  return max(lo, min(hi, v))
end

-- Compute the full layout for the current zone + configuration.
-- cfg: { style=0|1|2, colorMode=0|1|2, showMinMax=bool }
function M.calculate(widget, cfg)
  local w, h = widget.zone.w, widget.zone.h
  local mode, orientation = M.classify(w, h)
  local side = min(w, h)
  local L = { mode = mode, orientation = orientation }
  local pad = px(6)

  -- fixed typography
  L.unitFont = (mode == "compact") and FONTS.XXS or FONTS.XS
  L.nameFont = FONTS.XS
  L.stateFont = FONTS.XS
  L.minMaxFont = FONTS.XXS

  local uh = fontHeight(L.unitFont)
  local nh = fontHeight(L.nameFont)
  local sh = fontHeight(L.stateFont)
  L.unitH, L.nameH, L.stateH = uh, nh, sh

  -- visibility
  L.showName = (mode == "normal" or mode == "large")
  L.showUnit = mode ~= "micro"
  L.showStateText = mode ~= "micro"
  L.showMarkers = cfg.showMinMax and mode ~= "micro"
  L.showMinMaxText = cfg.showMinMax and mode == "large"

  -- dial geometry (balanced dials leave room for the name row)
  local nameSpace = 0
  if L.showName then nameSpace = nh + pad end
  local radius
  local cx, cy
  if orientation == "horizontal" then
    local d = min(w * 0.42, h - pad * 2)
    radius = max(d / 2 - px(2), px(10))
    cx = pad + radius
    cy = floor(h / 2)
  elseif orientation == "vertical" then
    radius = max(min(w / 2 - pad, h * 0.34), px(10))
    cx = floor(w / 2)
    cy = pad + radius
  else
    radius = max(min(w, h - nameSpace) / 2 - pad - px(1), px(10))
    cx = floor(w / 2)
    cy = floor(h / 2) - px(1)
  end
  L.cx, L.cy, L.radius = floor(cx), floor(cy), floor(radius)

  -- value font: the largest candidate that fits the value area
  -- (SpiderFI pattern: pick the biggest font that fits the available space)
  local vcands
  local fit
  if orientation == "horizontal" then
    vcands = { FONTS.XXL, FONTS.XL, FONTS.L, FONTS.XS }
    fit = h * 0.38
  elseif orientation == "vertical" then
    vcands = { FONTS.XXL, FONTS.XL, FONTS.L, FONTS.XS }
    fit = h - (L.cy + L.radius + px(4))
  else
    if mode == "micro" then vcands = { FONTS.XS, FONTS.XXS }
    elseif mode == "large" then vcands = { FONTS.XXL, FONTS.XL, FONTS.L, FONTS.XS }
    else vcands = { FONTS.XL, FONTS.L, FONTS.XS } end
    fit = h - (L.cy + floor(L.radius * 0.45))
  end
  local vf = vcands[#vcands]
  for i = 1, #vcands do
    if fontHeight(vcands[i]) <= fit then
      vf = vcands[i]
      break
    end
  end
  L.valueFont = vf
  local vh = fontHeight(vf)
  L.valueH = vh

  L.trackThickness = clamp(floor(side / 16), px(2), px(10))
  L.arcThickness = clamp(floor(side / 14), px(2), px(12))

  -- ticks (outside the track)
  L.tickCount = mode == "micro" and 3 or (mode == "large" and 7 or 5)
  L.tickThickness = clamp(floor(side / 90), 1, px(3))
  L.tickInner = L.radius + px(1)
  L.tickOuter = L.tickInner + clamp(floor(side / 40), px(2), px(6))

  -- needle / pivot
  L.showNeedle = (cfg.style == 1) or (cfg.style == 0 and mode ~= "micro")
  if L.showNeedle then
    L.needleInner = clamp(floor(L.radius * 0.18), px(4), 24)
    L.needleOuter = L.tickInner - px(2)
    L.needleThickness = clamp(floor(side / 60), 1, px(4))
    L.pivotRadius = clamp(floor(L.radius * 0.05), 2, px(6))
  end

  -- text placement (x/y are the top-left of each text; centered layouts set
  -- x in the renderer from the measured text width)
  if orientation == "horizontal" then
    local vx = L.cx + L.radius + px(8)
    L.valueX = vx
    L.valueY = max(floor(h / 2) - vh - sh - px(4), pad)
    L.nameX = vx
    L.nameY = h - nh - pad
    L.stateX = vx
    L.stateY = L.valueY + vh + px(2)
    L.minMaxY = L.stateY + sh + px(2)
  elseif orientation == "vertical" then
    L.valueX = 0  -- centered by renderer
    L.valueY = L.cy + L.radius + px(4)
    L.unitX = 0
    L.unitY = L.valueY + vh
    L.nameX = 0
    L.nameY = h - nh - pad
    L.stateX = 0
    L.stateY = max(L.cy - L.radius - sh - px(2), pad)
    L.minMaxY = L.valueY + vh + px(6)
  else
    L.valueX = 0  -- centered by renderer
    L.valueY = L.cy + floor(L.radius * 0.45)
    L.unitX = 0
    L.unitY = L.valueY + vh
    L.nameX = 0
    L.nameY = L.cy + L.radius + px(2)
    L.stateX = 0
    L.stateY = max(L.cy - L.radius + px(2), pad)
    L.minMaxY = L.valueY + vh + px(6)
  end

  return L
end

return M
