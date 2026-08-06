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
---- # MEASURING CONTRACT (Tanda 6 F-4): M.textWidth is memoized and         #
---- # therefore BOUNDED - it may only be called from layout/build paths,    #
---- # over the fixed set of strings one configuration can produce. The      #
---- # renderers must never measure a LIVE string through it: at high        #
---- # precision the value string changes every frame, and each new string   #
---- # would become a permanent entry in a cache shared by every gauge on    #
---- # the card. M.measureWidth is the renderers' entry: exact, deliberately #
---- # NOT memoized, one lcd.sizeText call per call.                         #
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
-- STDSIZE is deliberately IN the ramp: the old M(24) -> XS(13) jump skipped
-- the 16 px step, so a chord that barely missed 24 px threw the value down to
-- 13 px (AUDIT.md P3-4; P0-2's value clearance narrows the chord at 200x160).
--
-- Built by FILTERING, not by literal indexing: a firmware that does not
-- define one of these constants (e.g. XXLSIZE on a target that has no
-- double-size fonts) must degrade to a shorter ramp, never leave a HOLE.
-- #RAMP keeps reporting the full length otherwise, so fitFont walks into
-- fontHeight(nil) -> heightCache[nil] = h raises `table index is nil`
-- (Tanda 6 F-10): a crash on the first layout pass, and the widget
-- permanently disables itself.
local RAMP_ORDER = { "XXL", "XL", "L", "M", "S", "XS", "XXS" }
M.RAMP = {}
for i = 1, #RAMP_ORDER do
  local f = M.FONTS[RAMP_ORDER[i]]
  if f ~= nil then M.RAMP[#M.RAMP + 1] = f end
end
assert(#M.RAMP > 0, "GaugeV2: firmware exposes no usable font constants")

M.color = {
  -- Green: the conventional "all clear" colour a gauge should default to
  -- (owner request, Tanda 5). This is also Static mode's fixed colour and
  -- the fallback wherever `widget.accent` is nil - but on 2.12+ firmware
  -- the Accent OPTION itself always carries a real colour (its own default,
  -- main.lua), never nil, so that default must point at this same role too
  -- (main.lua's Accent default = COLOR_THEME_ACTIVE) or the option's
  -- default silently shadows this fallback and 2.12+ radios never see it.
  accent  = COLOR_THEME_ACTIVE,
  needle  = COLOR_THEME_PRIMARY1,    -- the needle NEVER follows the state
                                     -- colour (owner request): a fixed,
                                     -- always-legible tone against every
                                     -- band colour, including the green
                                     -- normal state above, and both themes
  warn    = COLOR_THEME_WARNING,
  crit    = RED,                     -- no theme role exists for critical
  rail    = COLOR_THEME_SECONDARY1,  -- track + rail base (used with opacity)
  tick    = COLOR_THEME_SECONDARY1,  -- scale ticks: the LIGHTER role, so 1 px
                                     -- marks read on dark themes (review P-C)
  label   = COLOR_THEME_SECONDARY1,
  muted   = COLOR_THEME_DISABLED,
  history = COLOR_THEME_SECONDARY1,
  chip    = COLOR_THEME_SECONDARY2,
}

M.opacity = {
  full     = 255,
  rail     = 90,    -- inactive track: ~35% - a crisper silhouette that still
                    -- never competes with the value arc (review P2-9)
  railBand = 200,   -- reference rail bands (Rail mode): drawn at reduced
                    -- opacity so the value arc - and with it the critical
                    -- red - stays the foreground (review P-E)
  railBandCrit = 160, -- one step dimmer, applied ONLY while the state is
                    -- critical (renderer.applyColors): at 200 the passive
                    -- amber band was the highest-luminance element on the
                    -- ring, competing with the full-red arc/text it is
                    -- supposed to sit behind (Tanda 5 review 3.6)
  ghost    = 110,   -- peak-hold segment
  muted    = 120,   -- whole gauge when data is not live
  pulse    = 150,   -- critical pulse trough
}

-- Logical spacing steps; always passed through px().
M.space = { xs = 2, sm = 4, md = 6, lg = 10 }

M.ratio = {
  unitToValue     = 0.55,  -- unit font relative to the value font
  trackToRadius   = 0.14,
  railToTrack     = 0.34,
  needleWidth     = 0.06,  -- half-width of the needle base, relative to radius
  -- Three-part taper (owner request, Tanda 5): two steps (thick body ->
  -- thin tip, review P-A) read as a paddle with a toothpick glued to the
  -- end - the width more than halves in one jump with almost no blend.
  -- A middle segment splits that single big step into two smaller ones.
  needleBodyReach = 0.38,  -- base ends here (fraction of the inner->outer
                           -- reach) - shorter than before, closest to the
                           -- hub, to leave room for the mid segment
  needleMidReach  = 0.72,  -- mid ends here; the tip carries the rest
  -- 0.62 looked right on paper but `floor(needleHalf * ratio)` collapses
  -- mid onto the tip's width at the canonical 200x160 base (needleHalf=3:
  -- floor(3*0.62)=1, same as the tip) - the 3rd step silently disappeared
  -- at the most common size. 0.7 clears that floor (floor(3*0.7)=2).
  needleMidToHalf = 0.7,   -- mid half-width relative to the BASE half-width
  needleTipToHalf = 0.35,  -- tip half-width relative to the base half-width
                           -- (unchanged - already the minimum legible 2 px)
  pivotRadius     = 0.09,
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

-- Width of a string, memoized per (font, text). BOUNDED by contract: only
-- called from layout / build paths over the fixed string set one
-- configuration produces (see the header). NEVER call this with a live
-- value string - that is what M.measureWidth is for.
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

-- Exact width of a string, deliberately NOT memoized: one lcd.sizeText call
-- per call, no cache write. The renderers' entry for the LIVE value string
-- (anchorUnit): exact like textWidth but incapable of growing the shared
-- cache one entry per frame (Tanda 6 F-4).
function M.measureWidth(text, font)
  return lcd.sizeText(text, font) or 0
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
-- The unit never lands on STDSIZE: a 24 px value keeps its 13 px unit (the
-- ~0.55 ratio of the Tanda-4 design), even though STDSIZE is a valid VALUE
-- font in the ramp (P0-2 / AUDIT P3-4).
function M.smallerFont(font, steps)
  steps = steps or 1
  for i = 1, #M.RAMP do
    if M.RAMP[i] == font then
      local j = i + steps
      while j <= #M.RAMP and M.RAMP[j] == M.FONTS.S do j = j + 1 end
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
