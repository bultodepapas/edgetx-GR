---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - design tokens and text metrics                             #
---- #                                                                       #
---- # Single source of truth for colour, opacity, spacing and typography.   #
---- # renderer.lua and bar.lua never name a raw constant; they ask here.    #
---- #                                                                       #
---- # Colours are theme roles (api_colorlcd.cpp COLOR_THEME_*) so the gauge #
---- # follows dark / light / high-contrast themes. The only literal is RED: #
---- # the firmware exposes no "critical" theme role.                        #
---- #                                                                       #
---- # Text metrics: lcd.sizeText() reports the font cell (including         #
---- # leading), not the ink box, and the numbers differ per screen scale.   #
---- # Rather than hard-coding per-font correction tables (which are         #
---- # resolution specific), we                                              #
---- #   * memoize the measurement (it never changes at runtime), and        #
---- #   * let LVGL align text horizontally inside a label of known width    #
---- #     (align = CENTER / RIGHT) instead of positioning by measured width.#
---- # The reported height is >= the ink height, so using it for fitting is  #
---- # conservative - text never overflows its region.                       #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local floor, max = math.floor, math.max

-- Font flags: the firmware's etcxcst constants are the font index << 8
-- (radio/src/gui/colorlcd/fonts.h FONT_INDEX). Ordered small -> large.
M.FONTS = {
  XXS = TINSIZE,
  XS  = SMLSIZE,
  S   = STDSIZE,
  M   = MIDSIZE,
  L   = DBLSIZE,
  XL  = XLSIZE,
  XXL = XXLSIZE,
}

-- Ordered candidate ramp used by the auto-fit search (largest first).
M.RAMP = { M.FONTS.XXL, M.FONTS.XL, M.FONTS.L, M.FONTS.M, M.FONTS.XS,
           M.FONTS.XXS }

M.color = {
  accent  = COLOR_THEME_PRIMARY1,    -- normal state / static mode
  warn    = COLOR_THEME_WARNING,
  crit    = RED,                     -- no theme role exists for critical
  rail    = COLOR_THEME_SECONDARY1,  -- track + rail base (used with opacity)
  tick    = COLOR_THEME_SECONDARY2,
  label   = COLOR_THEME_SECONDARY1,
  muted   = COLOR_THEME_DISABLED,
  history = COLOR_THEME_SECONDARY1,
  chip    = COLOR_THEME_SECONDARY2,
}

M.opacity = {
  full  = 255,
  rail  = 64,    -- inactive track: visible, never competing with the value
  ghost = 110,   -- peak-hold segment
  muted = 120,   -- whole gauge when data is not live
  pulse = 150,   -- critical pulse trough
}

-- Logical spacing steps; always passed through px().
M.space = { xs = 2, sm = 4, md = 6, lg = 10 }

M.ratio = {
  unitToValue   = 0.55,  -- unit font relative to the value font
  trackToRadius = 0.14,
  railToTrack   = 0.34,
  needleWidth   = 0.06,  -- half-width of the needle base, relative to radius
  tailLength    = 0.20,  -- counterweight length, relative to needle length
  pivotRadius   = 0.09,
}

-- Physical size helper: LCD_SCALE is 0.8 / 1.0 / 1.375 for 320 / 480 / 800 px
-- wide screens (etx_lv_theme.h), so px() keeps proportions identical.
function M.px(value)
  return max(1, floor(value * (lvgl.LCD_SCALE or 1) + 0.5))
end

-- ---------------------------------------------------------------- metrics --

local widthCache = {}
local heightCache = {}

-- Height of a font, measured once. Used for fitting and row heights.
function M.fontHeight(font)
  local h = heightCache[font]
  if h then return h end
  local _, measured = lcd.sizeText("8", font)
  h = (type(measured) == "number" and measured > 0) and measured or 16
  heightCache[font] = h
  return h
end

-- Width of a string, memoized per (font, text). Only called from layout /
-- build paths - never per frame (labels are aligned by LVGL, not by us).
function M.textWidth(text, font)
  local byFont = widthCache[font]
  if not byFont then
    byFont = {}
    widthCache[font] = byFont
  end
  local w = byFont[text]
  if not w then
    w = lcd.sizeText(text, font) or 0
    byFont[text] = w
  end
  return w
end

-- Largest font from `candidates` whose height fits `available`.
-- Falls back to the smallest candidate.
function M.fitFont(candidates, available)
  for i = 1, #candidates do
    if M.fontHeight(candidates[i]) <= available then return candidates[i] end
  end
  return candidates[#candidates]
end

-- Font one step smaller in the ramp (used for the unit next to the value).
function M.smallerFont(font, steps)
  steps = steps or 1
  for i = 1, #M.RAMP do
    if M.RAMP[i] == font then
      local j = i + steps
      if j > #M.RAMP then j = #M.RAMP end
      return M.RAMP[j]
    end
  end
  return font
end

-- ----------------------------------------------------------------- states --

-- Colour for a semantic state key. `accent` overrides the normal colour when
-- the user picked one (Accent option); nil keeps the theme role.
function M.stateColor(key, accent)
  if key == "warning" then return M.color.warn end
  if key == "critical" then return M.color.crit end
  if key == "muted" then return M.color.muted end
  return accent or M.color.accent
end

-- Continuous green -> amber -> red ramp (Gradient colour mode). Mirrors
-- GaugeRotary's getRangeColor, expressed on the normalized 0..1 position
-- between the critical end (0) and the good end (1).
function M.gradientColor(t)
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local g = floor(0xdf * t)
  local r = 0xdf - g
  return lcd.RGB(r, g, 0)
end

return M
