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

-- Clip a box to the dial circle's clear CHORD at the box's BOTTOM edge,
-- centred on the dial centre. The ring is closest to the text at the bottom
-- of its box, so this guarantees every corner of the text stays inside the
-- ring (the audit's LABEL/RING collisions: G-6 for the value, G-7 for the
-- min/max row). One px of safety, because a box exactly as wide as the
-- floored chord puts its corners on the ring and rounding can push them a
-- hair outside. Returns the box (or nil) for convenience.
local function clipToChord(L, b)
  if not b then return b end
  local dy = (b.y + b.h) - L.cy
  local clearR = L.radius - floor(L.trackThickness / 2)
  local chord = 0
  if clearR > 0 and math.abs(dy) < clearR then
    chord = 2 * math.sqrt(clearR * clearR - dy * dy)
  end
  if chord > 0 and chord < b.w then
    b.w = floor(chord) - T.px(1)
    b.x = L.cx - floor(b.w / 2)
  end
  return b
end

-- Pixels the state pill hangs BELOW the state text box, outline included.
--
-- The pill is `extra` px taller than its text and vertically centred on it
-- (chipOff = floor(extra / 2) above), so what hangs below is the half that
-- floor() did NOT take - plus the chipEdge outline the renderers draw around
-- the pill (renderer.build / bar.build).
--
-- `outline` is passed in, not restated, because that is the whole lesson of
-- this function. The budget used to guess the overhang as floor(extra / 2),
-- forgetting the outline entirely, and the pill left the bottom of every bar
-- zone. The first repair hard-coded T.px(1) here - and px() is not linear:
-- at LCD_SCALE 1.375 the renderers' `+ T.px(2)` on the outline box is 3, not
-- 2 * T.px(1) = 2, so the pill went right back outside on 800 px radios.
-- One value, defined once in the layout (L.chipOutline), used by the budget
-- AND by both renderers.
local function chipOverhang(shown, extra, outline)
  if not shown then return 0 end
  return extra - floor(extra / 2) + outline
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
  local gap = T.px(T.space.md)
  local started = (cap == nil)
  for i = 1, #ramp do
    local font = ramp[i]
    if not started and font == cap then started = true end
    if started then
      if T.fontHeight(font) <= maxH then
        -- The unit is one ramp step below the value (review P-D): two steps
        -- shrank the `B` of `dB` to where it blurred into an `E` at small
        -- sizes; one step keeps it secondary and legible where the width
        -- allows (the fit check below is the arbiter).
        local unitFont = T.smallerFont(font, 1)
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
  -- Nothing fits the region: use the smallest font, but never let the
  -- reserved box exceed the region. The region was chord-clipped to stay
  -- inside the ring (AUDIT.md G-6), so an oversized box - possible once the
  -- sample carries a slack character (P1-3/P1-4) - would push its corners
  -- onto the ring. The value itself is always narrower than the sample.
  local font = ramp[#ramp]
  local unitFont = font
  local uw = 0
  if unitText and unitText ~= "" then
    uw = T.textWidth(unitText, unitFont) + gap
  end
  local w = min(T.textWidth(sample, font), max(maxW - uw, 0))
  return font, unitFont, w, uw
end

-- Place the value + unit pair centred as a group inside `region`.
local function placeValue(L, region, sample, unitText, cap)
  local valueFont, unitFont, vw, uw =
    pickValueFont(sample, unitText, region.w, region.h, cap)
  L.valueFont = valueFont
  L.unitFont = unitFont
  local vh = T.fontHeight(valueFont)
  local uh = T.fontHeight(unitFont)
  local gap = T.px(T.space.md)
  local groupW = vw + uw
  -- A trailing unit adds visual weight on the right of the group, so centre
  -- it ~1 px left of the geometric centre when a unit is shown (review
  -- P1-8). Only when there is room: never let the box leave the region, so
  -- the G-6 chord guarantee holds.
  local optical = 0
  if unitText ~= "" and groupW + T.px(1) <= region.w then
    optical = T.px(1)
  end
  local x0 = region.x + floor((region.w - groupW - optical) / 2)
  local y0 = region.y + floor((region.h - vh) / 2)
  if y0 < region.y then y0 = region.y end
  -- The type ramp has a FLOOR (theme.RAMP's smallest font), so a region
  -- shorter than that font still gets a box taller than itself - and in a
  -- micro dial the region is already the zone's last few pixels, so the box
  -- hung off the bottom edge of the widget (measured at 24x20, LCD_SCALE
  -- 1.375: the value label ended 1 px outside). The region is the
  -- preference; the zone is the hard limit. Only ever bites where the font
  -- could not shrink far enough, so every zone with room is untouched.
  if y0 + vh > L.h then y0 = max(L.h - vh, 0) end
  if x0 < 0 then x0 = 0 end
  L.valueBox = box(x0, y0, vw, vh)
  -- P1-1 (Tanda 5 review 3.4): the box is reserved at the widest sample's
  -- width so digits never shift the group, but RIGHT-aligning the actual
  -- ink inside it flushed short values against the unit, leaving the empty
  -- reserve entirely on the left - the visible "22 dB" sat well right of
  -- the dial's centre even though the RESERVED group was centred there.
  -- Centring the ink instead, with the unit re-anchored to its real edge
  -- every time the value text changes (renderer.anchorUnit/bar.lua), keeps
  -- the VISIBLE group centred on the same point for any digit count: with
  -- the ink centred in a box of width vw, its own centre is always at
  -- vw/2 regardless of actualW, so attaching the unit right after the ink
  -- reproduces exactly the reserved group's centre, not an approximation.
  L.valueAlign = CENTER
  -- unit sits on the value baseline, one step down in the type ramp. `uw`
  -- from pickValueFont already includes the gap, so the box must not add it
  -- again: the reserved group is then exactly `groupW` and the fit check in
  -- pickValueFont (w + uw <= maxW) is honest (AUDIT.md G-6).
  L.unitBox = box(x0 + vw + gap, y0 + (vh - uh) - T.px(1), max(uw - gap, 1), uh)
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
  -- ShowChip (owner request, Tanda 5): the WARN/CRIT/no-data pill is opt-out,
  -- not mandatory - `~= false` so it defaults on for callers/tests that never
  -- set the field, matching the option's declared BOOL default of 1.
  L.showState = mode ~= "micro" and cfg.showChip ~= false
  L.showMarkers = (cfg.showMinMax or 1) > 1 and mode ~= "micro"
  L.showMinMaxText = (cfg.showMinMax or 1) > 2 and mode == "large"
  -- a full ring starts and ends at the same point: two scale labels would sit
  -- on top of each other
  L.showScale = (mode == "large") and (L.sweep < 360)
  L.showGhost = (mode ~= "micro")

  -- The name is the least important text on the dial: the smallest font keeps
  -- the hierarchy value -> unit -> name clean (review P2-10). The state text
  -- stays one step larger because WARN/CRIT carry the severity.
  L.nameFont = T.FONTS.XXS
  L.stateFont = T.FONTS.XS
  L.minMaxFont = T.FONTS.XXS
  L.scaleFont = T.FONTS.XXS
  local nameH = T.fontHeight(L.nameFont)
  local stateH = T.fontHeight(L.stateFont)
  local minMaxH = T.fontHeight(L.minMaxFont)

  -- dial box and text region per orientation
  local dial, textRegion, valueRegion
  if orientation == "horizontal" then
    -- The dial takes the full zone HEIGHT and the text column keeps only the
    -- width it needs. `min(w*0.5, h)` strangled the dial to half the zone
    -- even when there was height to spare, wasting up to ~73 % of the area
    -- (AUDIT.md G-13: 480x272 used 27 %). The column floor - the value at its
    -- smallest font plus the longest label row - keeps the text legible, and
    -- the max() with the old half-width rule means a narrow horizontal zone
    -- never loses dial size.
    local textMin = max(T.px(120), floor(w * 0.28))
    local dialSide = max(min(w - textMin, h), min(w * 0.5, h))
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
    -- value lives inside the dial circle. A micro dial draws no state chip
    -- and no needle, so its value can sit in the MIDDLE of the circle, where
    -- the clear chord is widest; larger modes must clear the state chip.
    -- P0-2: the normal/large value region is dropped `valueDrop` px so the
    -- text cell clears the pivot and the needle blade at critical angles
    -- (measured: the cell used to start 6 px inside the pivot's vertical
    -- span at 200x160). The min/max row below is chord-clipped further down,
    -- and the region's own chord clip keeps the fit honest.
    local valueDrop = T.px(7)
    if mode == "micro" then
      -- centred exactly on the dial centre: the clear chord is widest there,
      -- and a micro dial's value is only a few px wide (no unit, no state)
      valueRegion = box(dial.x, dial.y + floor(dial.h / 2)
                        - floor(dial.h * 0.15),
                        dial.w, floor(dial.h * 0.30))
    elseif mode == "compact" then
      valueRegion = box(dial.x, dial.y + floor(dial.h * 0.50),
                        dial.w, floor(dial.h * 0.26))
    else
      valueRegion = box(dial.x, dial.y + floor(dial.h * 0.45) + valueDrop,
                        dial.w, floor(dial.h * 0.26))
    end
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
  -- Minimum 2 px: at 1 px the scale marks vanished into the background on
  -- dark themes (~2.5:1 contrast, review P-C). The max is the same as before.
  L.tickThickness = clamp(floor(side / 90), T.px(2), T.px(3))
  L.minorTicks = (mode == "large") and (L.tickCount - 1) or 0

  local tickLength = clamp(floor(side / 40), T.px(2), T.px(6))
  local outerReserve = floor(L.trackThickness / 2) + L.railThickness
    + T.px(T.space.xs) + tickLength + 1
  local half = floor(min(dial.w, dial.h) / 2)
  L.radius = max(half - outerReserve, T.px(8))
  -- The rail band radius clears the value arc's outer edge by `railGap`: when
  -- the value is critical both layers are red at adjacent radii, and touching
  -- them read as one bevelled blob (review P-E). The 1 px band gap keeps the
  -- red->amber transition a clean range boundary.
  L.railGap = T.px(1)

  -- CONTAINMENT. `radius` above has a px(8) FLOOR, so in a zone smaller than
  -- the ring's own outer furniture the subtraction goes negative, the floor
  -- wins, and everything derived from the radius is then pushed OUTSIDE the
  -- zone - the ticks first, since they are the outermost thing on the dial.
  --
  -- That is not a cosmetic overflow. Ticks and history marks are LINES, and
  -- LvglWidgetLine::getPt reads their coordinates with luaL_checkunsigned
  -- (lua_lvgl_widget.cpp:1001,1004): a negative one RAISES on the radio, so
  -- the widget dies on its first build and disables itself for the session -
  -- the failure mode tests/mock_env.lua:checkPts exists to catch. Measured
  -- before this clamp: every zone below ~32x32 at LCD_SCALE 1.0 (46x46 at
  -- 1.375) built negative tick coordinates.
  --
  -- So give up the outer FURNITURE rather than the widget, in ascending order
  -- of importance: the ticks first (a 30 px dial cannot resolve them anyway),
  -- then the ring shrinks onto whatever is left. `edgeReach` is the clearance
  -- from the dial centre to the nearest zone edge - the real budget, which
  -- the dial BOX alone does not capture once the box has been centred.
  local edgeReach = min(L.cx, L.cy, w - L.cx, h - L.cy) - 1
  local railOut = floor(L.trackThickness / 2) + L.railThickness + L.railGap
  if L.radius + railOut + T.px(T.space.xs) + tickLength > edgeReach then
    local r = edgeReach - railOut - T.px(T.space.xs) - tickLength
    if r >= T.px(8) then
      L.radius = r                       -- ticks still fit: just shrink
    else
      L.tickCount, L.minorTicks, tickLength = 0, 0, 0
      L.radius = max(edgeReach - railOut - T.px(1), T.px(3))
    end
  end

  L.railRadius = L.radius + floor(L.trackThickness / 2) + L.railThickness
    + L.railGap
  L.tickInner = L.railRadius + T.px(T.space.xs)
  L.tickOuter = L.tickInner + tickLength
  -- Radial span of the min/max history marks. LAYOUT data, like the bar's
  -- markOverhang: renderer.build and renderer.updateHistory both need it and
  -- used to compute the same two expressions independently - the exact shape
  -- of drift that put the state pill outside its zone.
  -- Both ends are clamped for the same luaL_checkunsigned reason as above:
  -- `edgeReach` caps the outer end in the degenerate zones the branch above
  -- lands in, and 0 caps the inner one, which goes negative once the ring is
  -- thicker than the radius it was squeezed onto.
  L.markInner = max(L.radius - floor(L.trackThickness / 2) - T.px(1), 0)
  L.markOuter = min(L.railRadius + T.px(1), max(edgeReach, 0))

  -- In a balanced zone the value text hangs inside the dial circle, and the
  -- circle's clear interior at that height is a CHORD of the ring - narrower
  -- than the dial box. Centering the value+unit group against the full box
  -- width pushes the unit (and wide values) onto the ring, exactly the
  -- LABEL/RING collisions the audit measured (AUDIT.md G-6). Horizontal/
  -- vertical zones place the value outside the dial and do not need it.
  if orientation == "balanced" then
    clipToChord(L, valueRegion)
  end

  -- needle
  L.showNeedle = (cfg.style == M.STYLE_NEEDLE)
    or (cfg.style == M.STYLE_AUTO and mode ~= "micro")
  if L.showNeedle then
    L.needleInner = clamp(floor(L.radius * 0.16), T.px(3), T.px(20))
    L.needleOuter = L.radius - floor(L.trackThickness / 2) - T.px(1)
    L.needleHalf = clamp(floor(L.radius * T.ratio.needleWidth), T.px(2), T.px(7))
    -- Tapered blade from three LINES (P2-1 keeps the needle a line family):
    -- base -> mid -> tip, each a bit thinner than the last, so the width
    -- steps down gradually instead of jumping straight from the thick base
    -- to the 2 px tip in one cut (Tanda 4's two-part P-A read as a paddle
    -- with a toothpick glued on at anything above micro sizes; owner
    -- request, Tanda 5). Each segment overlaps the previous by 75% of its
    -- OWN thickness so the rounded caps (renderer.buildNeedle) blend into
    -- one another instead of leaving a visible seam.
    local reach = L.needleOuter - L.needleInner
    L.needleBodyOuter = L.needleInner + floor(reach * T.ratio.needleBodyReach)
    L.needleMidOuter = L.needleInner + floor(reach * T.ratio.needleMidReach)
    L.needleMidHalf = clamp(floor(L.needleHalf * T.ratio.needleMidToHalf),
                            1, L.needleHalf)
    L.needleTipHalf = clamp(floor(L.needleHalf * T.ratio.needleTipToHalf),
                            1, L.needleMidHalf)
    L.needleTipThickness = max(T.px(2), L.needleTipHalf * 2)
    L.needleMidInner = max(L.needleInner,
                           L.needleBodyOuter - floor(L.needleMidHalf * 2 * 0.75))
    L.needleTipInner = max(L.needleMidInner,
                           L.needleMidOuter - floor(L.needleTipThickness * 0.75))
    L.pivotRadius = clamp(floor(L.radius * T.ratio.pivotRadius),
                          T.px(3), T.px(9))
  end

  -- typography and text regions
  local cap = (mode == "micro") and T.FONTS.XS
    or ((mode == "compact") and T.FONTS.L or nil)
  -- a unit that will not be drawn (micro zones) must not reserve width in the
  -- value group: the chord a micro dial leaves for text is only a few px
  -- (AUDIT.md G-6)
  placeValue(L, valueRegion, F.widestSample(widget),
             L.showUnit and widget.unitText or "", cap)

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
      -- The name used to hang from the dial's bottom edge regardless of how
      -- tall the value/min-max block actually rendered, leaving dead air
      -- between them whenever the value was short (Tanda 5 review 3.15).
      -- Pull it up toward the real content bottom; the old bottom-anchored
      -- spot - below the ring's open wedge, always clear of the arc - stays
      -- as the floor, so this never pushes the name lower than before.
      local closeY = L.minMaxBox.y + L.minMaxBox.h + T.px(T.space.xs)
      local farY = dial.y + dial.h - nameH
      L.nameBox = box(0, min(closeY, farY), w, nameH)
    end
  end
  L.textAlign = align
  L.nameAlign = align
  L.stateAlign = align

  -- the min/max row hangs below the value INSIDE the dial circle: constrain
  -- it to the chord at its depth so it neither crosses the ring nor the
  -- history marks that point into the same lower band (AUDIT.md G-7). The
  -- minTextBox/maxTextBox split below then inherit the clipped width.
  if orientation == "balanced" then
    clipToChord(L, L.minMaxBox)
  end

  -- min / max text share the min-max row
  local halfW = floor(L.minMaxBox.w / 2)
  L.minTextBox = box(L.minMaxBox.x, L.minMaxBox.y, halfW, minMaxH)
  L.maxTextBox = box(L.minMaxBox.x + halfW, L.minMaxBox.y, halfW, minMaxH)

  -- scale end labels, one at each arc end, sitting just OUTSIDE the end
  -- ticks. The old code centred a fixed 30 px box on the point at
  -- tickOuter + px(sm): its inner half retreated over the end tick ("100"
  -- read as "f00", AUDIT.md G-8), and the fixed width clipped long strings
  -- like 20000.00 (AUDIT.md G-9). Each label is now sized with its own text
  -- width and pushed outward along the radial until its NEAREST corner sits
  -- at r0 - so every point of the box is at distance >= r0 from the centre,
  -- and no point of the tick (which ends inside r0) can touch it.
  if L.showScale then
    local sh = T.fontHeight(L.scaleFont)
    local r0 = L.tickOuter + T.px(T.space.sm)
    local function placeScaleLabel(angle, text)
      local sw = T.textWidth(text, L.scaleFont)
      local a, b = sw / 2, sh / 2
      local ux, uy = G.pointOnCircle(0, 0, 1, angle)
      local sx = (ux >= 0) and a or -a
      local sy = (uy >= 0) and b or -b
      local dot = ux * sx + uy * sy
      local r = dot + math.sqrt(math.max(dot * dot + r0 * r0 - a * a - b * b, 0))
      local cx, cy = G.pointOnCircle(L.cx, L.cy, r, angle)
      return box(cx - a, cy - b, sw, sh)
    end
    -- A label that the zone edge forced back over its own end tick slides
    -- along the TANGENT until it clears the tick: the radial placement above
    -- clears it by construction, only the zone clamp can pull it back in. A
    -- 180 deg arc ends at 9/3 o'clock, right at the extreme marks, so on a
    -- zone just wide enough for the dial the clamp does exactly that
    -- (AUDIT.md G-11).
    local function clearEndTick(angle, b)
      local ux, uy = G.pointOnCircle(0, 0, 1, angle)
      local px, py = -uy, ux            -- tangent unit vector
      local halfTh = max(1, L.tickThickness / 2)
      local tMin, tMax, pMin, pMax = math.huge, -math.huge, math.huge, -math.huge
      for i = 1, 4 do
        local cx0 = b.x + ((i % 2 == 1) and 0 or b.w)
        local cy0 = b.y + (i <= 2 and 0 or b.h)
        local dx, dy = cx0 - L.cx, cy0 - L.cy
        local t = dx * ux + dy * uy
        local pt = dx * px + dy * py
        if t < tMin then tMin = t end
        if t > tMax then tMax = t end
        if pt < pMin then pMin = pt end
        if pt > pMax then pMax = pt end
      end
      -- clear when the radial span or the perpendicular band misses the tick
      if tMax <= L.tickInner or tMin >= L.tickOuter
        or pMax <= -halfTh or pMin >= halfTh then
        return b
      end
      local gap = 1
      local function shifted(s)
        return box(b.x + px * s, b.y + py * s, b.w, b.h)
      end
      local function inZone(bb)
        return bb.x >= 0 and bb.y >= 0
          and bb.x + bb.w <= w and bb.y + bb.h <= h
      end
      local d = shifted(halfTh + gap - pMin)          -- slide along +tangent
      if inZone(d) then return d end
      local u = shifted(-halfTh - gap - pMax)         -- or along -tangent
      if inZone(u) then return u end
      return b  -- no room either way: keep the clamped position
    end
    L.scaleMinBox = placeScaleLabel(L.startAngle,
      F.display(widget, widget.config.min))
    L.scaleMaxBox = placeScaleLabel(L.startAngle + L.sweep,
      F.display(widget, widget.config.max))
    -- do not let the labels leave the zone
    if L.scaleMinBox.x < 0 then L.scaleMinBox.x = 0 end
    if L.scaleMaxBox.x + L.scaleMaxBox.w > w then
      L.scaleMaxBox.x = w - L.scaleMaxBox.w
    end
    L.scaleMinBox = clearEndTick(L.startAngle, L.scaleMinBox)
    L.scaleMaxBox = clearEndTick(L.startAngle + L.sweep, L.scaleMaxBox)
    if L.scaleMinBox.y + sh > h then L.showScale = false end
  end

  -- chip behind the state text. 7 px side padding and stateH + 6 height give
  -- the C/T letters breathing room, and the text is centred in the pill by
  -- (chipHeight - stateH) / 2 (review P-B). chipOff lives in LAYOUT, not in
  -- the renderer: configure() replaces widget.layout on every update() but
  -- only rebuilds on a signature change, so a field the renderer wrote at
  -- build time was lost by the next no-op update() and the chip render
  -- crashed on nil - the widget disabled itself (Tanda 6 F-1).
  L.chipPad = T.px(7)
  L.chipHeight = stateH + T.px(6)
  L.chipOff = floor((L.chipHeight - stateH) / 2)
  -- see barLayout: the outline is ONE value both renderers inset by and grow
  -- by twice, because T.px(2) is not 2 * T.px(1) at every LCD_SCALE
  L.chipOutline = T.px(1)
end

-- ------------------------------------------------------------------- bar --

local function barLayout(widget, cfg, L, w, h)
  -- The layout stacks value / bar / state row with `pad` between and around
  -- them: three gaps, 12 px at the normal step. In a 44 px zone that is more
  -- than a quarter of the height, competing directly with the value font
  -- floor (P1-4) and the state row (P1-2) - and it was exactly the 2 px the
  -- old budget had to under-reserve to keep both, which is what pushed the
  -- pill out of the zone. Short bars (the same breakpoint that drops the
  -- name) buy the room back from the padding instead, honestly.
  local pad = (h < T.px(46)) and T.px(T.space.xs) or T.px(T.space.sm)
  L.showUnit = true
  L.showName = h >= T.px(46)
  L.showState = w >= T.px(120) and cfg.showChip ~= false
  L.showMarkers = (cfg.showMinMax or 1) > 1
  L.showMinMaxText = false
  L.showScale = false
  L.showGhost = true
  L.showNeedle = false

  L.nameFont = T.FONTS.XS
  L.stateFont = T.FONTS.XS
  L.minMaxFont = T.FONTS.XXS
  local nameH = T.fontHeight(L.nameFont)
  local stateH = T.fontHeight(L.stateFont)
  -- the smallest font the value can use: the value region must never drop
  -- under this, or the auto-fit would overflow the box (AUDIT.md P1-4)
  local minText = T.fontHeight(T.FONTS.XXS)

  -- The min/max marker and the peak-hold ghost stick out this far above AND
  -- below the bar, so they read as ticks against it rather than as part of
  -- the fill. It is LAYOUT data because it is part of the bar's real
  -- footprint and the budget below has to reserve it: bar.lua reads it back
  -- instead of restating px(2)/px(4), which is what kept the two in sync
  -- once the pill taught the same lesson.
  L.markOverhang = T.px(2)

  -- Width of the chipEdge outline drawn around the state pill, on EACH side.
  -- Both renderers must inset by this and grow by twice it - never by
  -- T.px(2), which is not 2 * T.px(1) at every LCD_SCALE (see chipOverhang).
  L.chipOutline = T.px(1)

  -- The row below the bar carries the state text (right) and, when there is
  -- height for it, the name (left). Its height is the STATE font's, never
  -- the name's: sizing it from nameH meant the short-bar paths zeroed nameH
  -- and collapsed STALE/NO LINK/WARN/CRIT out of exactly the zones where
  -- they matter most (AUDIT.md P1-2). Both fonts are XS here, so the two
  -- readings coincide today - naming the state font keeps it that way if
  -- either font is ever re-tuned.
  --
  -- VERTICAL BUDGET. The zone has to hold, top to bottom: the value area,
  -- the bar, and the state/name row - and the state PILL is taller than its
  -- text and centred on it (review P-B), so the row must also reserve what
  -- the pill hangs below that text (chipOverhang, outline included).
  --
  -- When it does not all fit, relax in this order, giving up the least
  -- important thing left each time:
  --
  --   1. full pill, preferred bar height     (the intended look)
  --   2. full pill, bar trimmed to its floor
  --   3. minimal pill (stateH + 2)
  --   4. bare pill (stateH + 0): no vertical padding, outline only
  --   5. no state row at all
  --
  -- Rungs 1-4 all keep WARN / CRIT / NO LINK on screen, which is what P1-2
  -- guarantees; rung 4 exists precisely so that a 44 px bar reaches it
  -- instead of falling to rung 5. Every rung sizes the row from the pill it
  -- actually paints, which is what keeps the pill inside the zone: the old
  -- nested version reserved floor(chipExtra / 2) - forgetting the 1 px
  -- outline - and reserved nothing at all on the minimal-pill rung, so the
  -- pill left the bottom of EVERY bar zone by 1 px, and a short one by 2.
  local chipExtra, rowH, barH, textH

  -- One rung: the tallest bar this pill size allows, else the bar trimmed to
  -- its floor. Returns true when the value area still fits.
  local function fits(extra)
    chipExtra = extra
    rowH = (L.showState or L.showName)
      and (stateH + chipOverhang(L.showState, extra, L.chipOutline)) or 0
    -- What has to fit UNDER the bar. With no row down there, the bottom pad
    -- is all that separates the bar from the zone edge, and the markers
    -- already stick markOverhang px past it - so the marker, not the row,
    -- sets the floor. A real row is always taller than the overhang, so this
    -- only ever bites on the row-less short bar it was written for.
    local below = max(rowH, L.markOverhang)
    barH = clamp(floor(h * 0.34), T.px(8), T.px(26))
    textH = h - barH - below - pad * 3
    if textH >= minText then return true end
    barH = max(h - minText - below - pad * 3, T.px(8))
    textH = h - barH - below - pad * 3
    return textH >= minText
  end

  if not L.showState then
    fits(0)
  elseif not (fits(T.px(6)) or fits(T.px(2)) or fits(0)) then
    L.showState = false                 -- rung 5: last resort
    fits(0)
  end
  -- A zone too short for even the smallest value font keeps the font's
  -- height anyway; the value box is what the auto-fit needs (AUDIT.md P1-4).
  --
  -- But raising textH back up does not create pixels. The bar was sized from
  -- the budget that did NOT fit, so unless it gives the room back the track
  -- is drawn past the bottom edge of the zone - measured at 200x20: the bar
  -- ended 3 px outside, taking the min/max marks (markOverhang) with it.
  -- LVGL clips it to the parent, so this is a silently truncated instrument
  -- rather than a crash, which is precisely why it survived this long.
  -- The bar is the element that degrades most gracefully here: a 2 px bar
  -- still reads as a bar, a bar outside the widget reads as nothing.
  if textH < minText then
    textH = minText
    barH = max(h - textH - max(rowH, L.markOverhang) - pad * 3, T.px(2))
  end

  local valueRegion = box(pad, pad, w - pad * 2, textH)
  placeValue(L, valueRegion, F.widestSample(widget),
             L.showUnit and widget.unitText or "",
             (h < T.px(60)) and T.FONTS.M or nil)

  L.bar = box(pad, pad + textH + pad, w - pad * 2, barH)
  -- Below roughly 24 px of zone height nothing fits honestly any more: textH
  -- has already been floored at the smallest font in the ramp (P1-4) and barH
  -- at px(2), and the two plus the padding still exceed the zone. Slide the
  -- bar up rather than let it - and the min/max marks that overhang it by
  -- markOverhang - be drawn past the bottom edge. The value then overlaps the
  -- bar, which is the honest picture at that size; painting outside the
  -- widget is not, and LVGL would clip it away unseen.
  local barLimit = h - L.markOverhang
  if L.bar.y + L.bar.h > barLimit then
    L.bar.y = max(barLimit - L.bar.h, L.markOverhang)
    if L.bar.y + L.bar.h > h then L.bar.h = max(h - L.bar.y, 1) end
    barH = L.bar.h
  end
  L.barRadius = floor(barH / 2)
  L.nameBox = box(pad, L.bar.y + barH + pad, floor((w - pad * 2) / 2), nameH)
  L.stateBox = box(pad + floor((w - pad * 2) / 2), L.bar.y + barH + pad,
                   floor((w - pad * 2) / 2), stateH)
  L.nameAlign = LEFT
  L.stateAlign = RIGHT
  L.textAlign = LEFT
  -- same pill as the dial (review P-B), sized to what the zone could reserve
  L.chipPad = T.px(7)
  L.chipHeight = stateH + chipExtra
  -- see the dial branch: chipOff must come from the layout, or a no-op
  -- update() loses it and the next chip render crashes (Tanda 6 F-1)
  L.chipOff = floor((L.chipHeight - stateH) / 2)
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
