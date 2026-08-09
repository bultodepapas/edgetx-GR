---- #########################################################################
---- #                                                                       #
---- # Gauge Pro - LVGL dial renderer                                         #
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
---- #   needle          two-line tapered blade + hub                        #
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

-- Property writes are QUEUED per object and flushed in one lvgl.set call at
-- the end of the frame: each lvgl.set is a full C++ getParams + refresh(), so
-- a state transition that touches six objects with two keys each used to
-- emit 14 refreshes when 6 would do (AUDIT.md P2-2). The cache still filters
-- unchanged keys, and it is updated immediately, so later reads in the same
-- frame see the new value.
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
  local dirty = widget.frame.dirty
  if not dirty then
    dirty = {}
    widget.frame.dirty = dirty
  end
  local t = dirty[obj]
  if not t then
    t = {}
    dirty[obj] = t
  end
  t[key] = value
end
M.setProp = setProp

-- Send every queued property for each object in a single lvgl.set call.
-- Called once at the end of each update frame (renderer and bar).
function M.flush(widget)
  local dirty = widget.frame.dirty
  if not dirty then return end
  widget.frame.dirty = nil
  for obj, t in pairs(dirty) do
    lvgl.set(obj, t)
  end
end

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

-- Ordered (lo, hi) angle span for a band. Bands are always ascending in
-- VALUE space (ranges.build), but a descending scale (Min > Max) mirrors the
-- value->angle mapping (geometry.normalize), so angleOf(r.from) can come out
-- above angleOf(r.to). Sorting here, rather than assuming a2 > a1, is what
-- keeps sections/rails/marks visible on a descending scale (AUDIT.md P0-3).
local function bandSpan(widget, r)
  local a1, a2 = angleOf(widget, r.from), angleOf(widget, r.to)
  if a1 > a2 then a1, a2 = a2, a1 end
  return a1, a2
end
M.bandSpan = bandSpan

-- ----------------------------------------------------------------- build --

local function buildTrack(widget)
  local ui, L, cfg = widget.ui, widget.layout, widget.config
  -- Same clamp as angleOf(): lv_arc_set_bg_end_angle only subtracts 360 once
  -- (270 + 360 = 630 -> 270, equal to bgStartAngle), and LVGL skips drawing a
  -- zero-length arc entirely, so a full ring's background track never
  -- rendered without this (AUDIT.md P0-4).
  local endA = L.startAngle + L.sweep - ((L.sweep >= 360) and 1 or 0)
  ui.track = lvgl.arc{
    x = L.cx, y = L.cy, radius = L.radius,
    startAngle = L.startAngle, endAngle = endA,
    bgStartAngle = L.startAngle, bgEndAngle = endA,
    color = T.color.rail, bgColor = T.color.rail,
    bgOpacity = T.opacity.rail, opacity = 0,
    thickness = L.trackThickness, rounded = 1,
  }

  -- Sections: the whole scale as three coloured bands on the OUTER ring -
  -- the same position/opacity model as the Rail mode below - so the bands
  -- stay clearly visible regardless of where the value arc currently sits.
  -- Drawing them at the value arc's own radius/thickness put them directly
  -- underneath it at 25% opacity, which made Sections pixel-identical to
  -- Static at any value inside the normal band (AUDIT.md G-2).
  if cfg.colorMode == M.COLOR_SECTIONS then
    ui.sections = {}
    for i = 1, #widget.ranges do
      local r = widget.ranges[i]
      local a1, a2 = bandSpan(widget, r)
      if a2 > a1 then
        local c = T.stateColor(r.role, widget.accent)
        local sec = lvgl.arc{
          x = L.cx, y = L.cy, radius = L.railRadius,
          startAngle = a1, endAngle = a2,
          bgStartAngle = a1, bgEndAngle = a2,
          color = c, bgColor = c, bgOpacity = 255, opacity = 0,
          thickness = L.railThickness, rounded = 0,
        }
        -- role rides on the object so the repaint path can recolor the
        -- accent-bearing normal band without pairing by index (degenerate
        -- bands are skipped at build, so sections[i] is not ranges[i])
        sec.role = r.role
        ui.sections[#ui.sections + 1] = sec
      end
    end
  end

  -- threshold rail: a thin permanent reminder of where the bands are, drawn
  -- outside the track so the value arc keeps the foreground to itself. The
  -- bands draw at reduced opacity (railBand) so they read as the reference
  -- behind the value arc: in a critical state, the red of the arc dominates
  -- the red of the band instead of merging into one bevelled blob
  -- (review P-E).
  if cfg.colorMode == M.COLOR_RAIL then
    ui.rails = {}
    for i = 1, #widget.ranges do
      local r = widget.ranges[i]
      if r.role ~= "normal" then
        local a1, a2 = bandSpan(widget, r)
        if a2 > a1 then
          local c = T.stateColor(r.role, widget.accent)
          ui.rails[#ui.rails + 1] = lvgl.arc{
            x = L.cx, y = L.cy, radius = L.railRadius,
            startAngle = a1, endAngle = a2,
            bgStartAngle = a1, bgEndAngle = a2,
            color = c, bgColor = c, bgOpacity = T.opacity.railBand, opacity = 0,
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
  -- A needle of LINES, not triangles: on the radio LvglWidgetTriangle::refresh
  -- frees the canvas and rebuilds it on every angle change - under needle
  -- damping the smoothed value moves almost every frame, so the audit
  -- measured ~46 canvas rebuilds in 20 frames and ~24 KB of heap churn per
  -- frame on a 200x200 zone (AUDIT.md P2-1). LvglWidgetLine::refresh only
  -- rewrites the points: no allocation churn at all.
  --
  -- The taper lost by P2-1 is restored with three lines, not two (review
  -- P-A, revised Tanda 5 on owner feedback): base -> mid -> tip. Two steps
  -- (thick body straight to a 2 px tip) read as a paddle with a toothpick
  -- glued to the end - the width more than halved in one jump. A middle
  -- segment splits that into two smaller steps, and `rounded = 1` on all
  -- three softens both the hub end and the two seams so they blend instead
  -- of showing a hard edge.
  -- Fixed colour, set once here and never touched by applyColors: the
  -- needle must stay legible against every band colour (green/amber/red)
  -- and the dark/light theme alike, so it does not follow the state colour
  -- the way the arc and value do (owner request, Tanda 5 review).
  -- The pts BUFFERS are persistent per segment (Phase 5.1): the binding
  -- copies the coordinates out on every set and keeps no reference, so
  -- updateArc can mutate them in place - the needle no longer allocates
  -- nine tables per angle change (Tanda 6 F-11). The { pts = ... } WRAPPER
  -- passed to lvgl.set is hoisted to a per-segment persistent table too
  -- (Phase 5.2): luaLvglSet parses the params table at CALL TIME
  -- (getParams -> parseParam, api_colorlcd_lvgl.cpp:116, lua_lvgl_widget.cpp
  -- :763) and retains no reference, so the same wrapper can be passed
  -- forever - its pts field points at the persistent buffer, whose fresh
  -- contents are read on every set. Both buffers and wrappers must NEVER
  -- go through setProp: its cache compares tables by identity and would
  -- drop every write after the first (5.1/5.2 TRAP 2) - the needle stays
  -- on direct lvgl.set.
  ui.needlePts = { { 0, 0 }, { 0, 0 } }
  ui.needleMidPts = { { 0, 0 }, { 0, 0 } }
  ui.needleTipPts = { { 0, 0 }, { 0, 0 } }
  ui.needleSet = { pts = ui.needlePts }
  ui.needleMidSet = { pts = ui.needleMidPts }
  ui.needleTipSet = { pts = ui.needleTipPts }
  ui.needle = lvgl.line{
    pts = G.linePointsInto(ui.needlePts, L.cx, L.cy, L.needleInner,
                           L.needleBodyOuter, a),
    thickness = max(1, L.needleHalf * 2), rounded = 1, color = T.color.needle,
  }
  ui.needleMid = lvgl.line{
    pts = G.linePointsInto(ui.needleMidPts, L.cx, L.cy, L.needleMidInner,
                           L.needleMidOuter, a),
    thickness = max(1, L.needleMidHalf * 2), rounded = 1, color = T.color.needle,
  }
  ui.needleTip = lvgl.line{
    pts = G.linePointsInto(ui.needleTipPts, L.cx, L.cy, L.needleTipInner,
                           L.needleOuter, a),
    thickness = L.needleTipThickness, rounded = 1, color = T.color.needle,
  }
  -- Solid hub: ONE filled circle in the neutral rail role, created after the
  -- needle so it covers the blade's inner end. The old ring+accent-dot pair
  -- read as pixel noise where needle, value and pivot meet; a clean solid
  -- circle reads as a deliberate centre (review P-A). The hub keeps the
  -- neutral tone in every state - it is the pivot, not a state indicator.
  ui.pivotRing = lvgl.circle{
    x = L.cx, y = L.cy, radius = L.pivotRadius,
    filled = 1, color = T.color.rail,
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
  local L, ui = widget.layout, widget.ui

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
    -- Persistent pts buffers and persistent { pts = ... } wrappers, exactly
    -- like the needle (Phase 5.1 + 5.2): the binding copies the coordinates
    -- out on every set and retains no reference to either table, so both can
    -- be mutated in place forever. The marks were left out of Phase 5 and
    -- stayed the last per-frame allocator on the dial - 870 B/frame for the
    -- whole time the history is advancing, which is every second of a climb,
    -- not the "few seconds after power-up" the original note assumed.
    -- NEVER route these through setProp: its cache compares tables by
    -- identity and would drop every write after the first (5.1/5.2 TRAP 2).
    ui.minMarkPts = { { 0, 0 }, { 0, 0 } }
    ui.maxMarkPts = { { 0, 0 }, { 0, 0 } }
    ui.minMarkSet = { pts = ui.minMarkPts }
    ui.maxMarkSet = { pts = ui.maxMarkPts }
    ui.minMark = lvgl.line{
      pts = G.linePointsInto(ui.minMarkPts, L.cx, L.cy, L.markInner,
                             L.markOuter, L.startAngle),
      thickness = max(1, L.tickThickness), color = T.color.history,
    }
    ui.maxMark = lvgl.line{
      pts = G.linePointsInto(ui.maxMarkPts, L.cx, L.cy, L.markInner,
                             L.markOuter, L.startAngle),
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
    -- The pill is taller than the state text and centred on it, so the
    -- letters sit in the middle of the pill, not 1 px from its top edge
    -- (review P-B). The centring offset is LAYOUT data (L.chipOff): it must
    -- survive a no-op update(), which replaces the layout table but only
    -- rebuilds on a signature change - a renderer-written field was lost
    -- and the next chip render crashed on nil (Tanda 6 F-1).
    -- 1 px outline in the label role, behind the pill, so the badge keeps a
    -- defined edge instead of reading as "a piece of the rail behind the
    -- text" (review P-B). It matters more now that the fill is a status
    -- colour: the outline is what separates the badge from a theme whose
    -- background happens to sit near the same luminance, or from a
    -- background.png photograph.
    local edge = L.chipOutline
    ui.chipEdge = lvgl.rectangle{
      x = L.stateBox.x - edge, y = L.stateBox.y - L.chipOff - edge,
      w = L.stateBox.w + edge * 2, h = L.chipHeight + edge * 2,
      color = T.color.label, filled = 1,
      rounded = floor((L.chipHeight + edge * 2) / 2),
    }
    -- Built muted, shown coloured: the badge is hidden here and updateChip
    -- sets its fill and its ink from the state before it is ever shown.
    ui.chip = lvgl.rectangle{
      x = L.stateBox.x, y = L.stateBox.y - L.chipOff,
      w = L.stateBox.w, h = L.chipHeight,
      color = T.color.muted, filled = 1, rounded = floor(L.chipHeight / 2),
    }
    lvgl.hide(ui.chipEdge)
    lvgl.hide(ui.chip)
    -- hidden at build like the pill it belongs to: the three are one object
    -- as far as visibility is concerned (see updateChip)
    ui.stateLabel = label(L.stateBox, L.stateFont, T.labelOn(T.color.muted),
                          L.stateAlign)
    lvgl.hide(ui.stateLabel)
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
    dirty = {},
    angle = -1, ghostAngle = -1, minAngle = -1, maxAngle = -1,
    needleShown = true, markersShown = false, chipShown = false,
    colorKey = "", accentKey = nil, valueStr = "", stateStr = "",
    minStr = "", maxStr = "",
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
    -- Equal thresholds give the ramp a zero span, so normalize() pins every
    -- value to the red end (AUDIT.md P1-5). Fall back to the band colour: a
    -- warn == crit configuration is a sharp cliff, and the state already says
    -- which side of it the value is on.
    if lo == hi then return data.state or "normal" end
    local t = G.normalize(data.displayValue, lo, hi)
    if not cfg.highGood then t = 1 - t end
    return "grad" .. floor(t * 20)
  end
  return data.state or "normal"
end

-- The colour for a semantic key: accent in Static mode, the gradient ramp
-- for gradN, the theme role otherwise. Shared with the bar (Tanda 6 F-15:
-- bar.lua used to carry its own copy of this).
local function resolveColor(widget, key)
  if key == "static" then return widget.accent or T.color.accent end
  if string.sub(key, 1, 4) == "grad" then
    local step = tonumber(string.sub(key, 5)) or 0
    return T.gradientColor(step / 20)
  end
  return T.stateColor(key, widget.accent)
end
M.resolveColor = resolveColor

-- The colour for the VALUE text. Shared with the bar (bar.lua calls it), so
-- both orientations obey the same rule.
--
-- The status colour used to drive this directly, which is how a UI-background
-- role ended up as the primary readout's ink. The value is DATA, so it takes
-- the theme's own text role and stays legible whatever the state (Tanda 8
-- §3.2). Two exceptions, both deliberate:
--   * CRITICAL - alarm outranks neutral legibility, it is the universal
--     convention, and the fixed red clears 3:1 on both reference backgrounds.
--   * MUTED - a gauge with no data must RECEDE; leaving the value at full
--     theme ink would make a stale reading look like a live one.
-- Takes the STATE key, never the frame's colour key: in Static mode colorKey
-- is permanently "static" and in Gradient mode "grad0".."grad20", so a value
-- coloured from there would never have turned red in two of the five modes.
function M.valueColor(key)
  if key == "critical" then return T.color.crit end
  if key == "muted" then return T.color.muted end
  return T.color.value
end

-- The value's ink follows the STATE, and the state moves independently of the
-- colour key, so it needs a gate of its own. Shared with the bar.
function M.applyStateInk(widget)
  local frame = widget.frame
  -- through the module table: stateKey is declared further down the file
  local skey = M.stateKey(widget)
  if skey ~= frame.stateKey then
    frame.stateKey = skey
    local ink = M.valueColor(skey)
    setProp(widget, widget.ui.valueLabel, "color", ink)
    -- The unit goes with it in the two EXCEPTION states, and only there.
    -- "22" in red beside "dB" in the label role read as two different things
    -- when they are one token; the same split made a stale "78" grey next to
    -- a live-looking blue "dB". In the ordinary states the unit keeps its
    -- quieter role on purpose - that hierarchy (big dark number, small quiet
    -- unit) is what makes the number the thing you see first.
    if widget.ui.unitLabel then
      setProp(widget, widget.ui.unitLabel, "color",
              (ink == T.color.value) and T.color.label or ink)
    end
  end
end

local function applyColors(widget, key)
  local ui = widget.ui
  local c = resolveColor(widget, key)
  local opa = (key == "muted") and T.opacity.muted or T.opacity.full
  setProp(widget, ui.valueArc, "color", c)
  setProp(widget, ui.valueArc, "opacity", opa)
  -- the VALUE's ink is not set here: it follows the state, which moves on its
  -- own gate (M.applyStateInk)
  -- the needle is intentionally NOT touched here: it keeps T.color.needle,
  -- set once at build time (buildNeedle)
  --
  -- Neither is the badge: its fill and label are set by updateChip, which runs
  -- on a change of the state STRING. That is the correct gate - in Static mode
  -- colorKey never leaves "static", so a normal -> warning transition does not
  -- reach this function at all, and a badge coloured from here would have kept
  -- saying WARN in the all-clear colour.
  if ui.sections then
    -- The NORMAL band carries the accent and was painted at build time; an
    -- Accent edit repaints here without a rebuild, so it must be recolored
    -- in place (Tanda 6 F-5). The warn/crit bands are fixed colours and
    -- resolve to the same colour as before - setProp filters the no-ops.
    for _, sec in ipairs(ui.sections) do
      setProp(widget, sec, "color", T.stateColor(sec.role, widget.accent))
      -- F2: the reference bands used to keep full opacity while the gauge
      -- itself was muted, so a widget announcing NO LINK still had three
      -- fully saturated bands on it - one of them red - and they were the
      -- brightest thing on the dial. Whatever the value arc does, the passive
      -- reference behind it does too.
      setProp(widget, sec, "bgOpacity", opa)
    end
  end
  if ui.rails then
    -- P1-3 (Tanda 5 review 3.6): only while critical, drop every passive
    -- band one step further so the full-red arc/text stay the brightest
    -- thing on the ring. WARN keeps the normal reference opacity - there
    -- the amber band IS the active state, not a competing one.
    -- Muted overrides both: see the note on sections above.
    local railOpa = T.opacity.railBand
    if key == "muted" then railOpa = T.opacity.muted
    elseif key == "critical" then railOpa = T.opacity.railBandCrit end
    for _, rail in ipairs(ui.rails) do
      setProp(widget, rail, "bgOpacity", railOpa)
    end
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
  -- An elapsed countdown timer is classified WARNING by colorKey (the arc is
  -- amber); its raw state is critical because a negative value sits below the
  -- scale minimum. The chip must say what the instrument paints - a CRIT
  -- word in warning colour is the worst of both worlds (AUDIT.md G-3).
  if widget.source.isTimer and data.value and data.value < 0 then
    return "WARN"
  end
  if data.state == "warning" then return "WARN" end
  if data.state == "critical" then return "CRIT" end
  return ""
end
M.stateText = stateText

-- The semantic key BEHIND the chip's text, which is not always the frame's
-- colour key: in Static mode colorKey is permanently "static", and in Gradient
-- mode it is "grad0".."grad20". Colouring the badge from those would have
-- printed CRIT on an all-clear fill in two of the five colour modes.
local function stateKey(widget)
  local data = widget.data
  if data.availability ~= "valid" then return "muted" end
  if widget.source.isTimer and data.value and data.value < 0 then
    return "warning"
  end
  return data.state or "normal"
end
M.stateKey = stateKey

-- Show or hide the state chip, hugging its text. Shared by the dial and the
-- bar so both signal state identically: the bar used to have no chip at all,
-- leaving WARN/CRIT as bare text in bar zones while dial zones got the full
-- pill (AUDIT.md P1-10).
function M.updateChip(widget, s)
  local ui, frame = widget.ui, widget.frame
  if not ui.chip then return end
  local show = (s ~= "")
  -- F9: `State chip = Off` is an appearance preference, and it used to
  -- suppress the pill in EVERY state - including WARN and CRIT. That left the
  -- normal/warning distinction resting on hue alone, which is precisely the
  -- discrimination ~8 % of a heavily male audience cannot make; the measured
  -- deuteranopia distance between this widget's warning and critical colours
  -- is 25.6, well inside the ~60 confusion threshold. The option now hides the
  -- INFORMATIONAL chips (NO LINK, STALE, NO DATA, NO SOURCE) and leaves the
  -- two that carry a safety signal alone. In the normal state it never had
  -- anything to hide: stateText returns "" there.
  if show and widget.config.showChip == false then
    local k = stateKey(widget)
    show = (k == "warning" or k == "critical")
  end
  if show then
    -- the chip hugs its text: measured here because the state string changes
    -- rarely (never per frame), unlike the value
    local L = widget.layout
    local w = T.textWidth(s, L.stateFont) + L.chipPad * 2
    local x = L.stateBox.x
    if L.stateAlign == CENTER then
      x = L.stateBox.x + floor((L.stateBox.w - w) / 2)
    elseif L.stateAlign == RIGHT then
      x = L.stateBox.x + L.stateBox.w - w
    end
    -- The pill HUGS its text, so it can come out wider than the box it was
    -- aligned in - a narrow text column in a horizontal zone is exactly that
    -- case - and the outline then adds chipOutline beyond it on each side.
    -- Measured at 80x56 (LCD_SCALE 0.8): the CRIT outline ended 1 px past the
    -- right edge of the zone. Clamp the pill, outline included, into the zone
    -- so the widget never paints outside itself.
    local edge = L.chipOutline
    local maxW = max(L.w - edge * 2, 1)
    if w > maxW then w = maxW end
    if x + w + edge > L.w then x = L.w - w - edge end
    if x < edge then x = edge end
    setProp(widget, ui.chip, "x", x)
    setProp(widget, ui.chip, "w", w)
    if ui.chipEdge then
      setProp(widget, ui.chipEdge, "x", x - L.chipOutline)
      setProp(widget, ui.chipEdge, "w", w + L.chipOutline * 2)
    end
    -- Centre the text INSIDE the pill it now hugs. The label was placed
    -- against stateBox, and for a RIGHT-aligned state row - the bar's - the
    -- pill's right edge coincides with stateBox's, so the word came out
    -- flush against the pill's right side with the whole 2 * chipPad sitting
    -- on the left. Re-anchoring the label to the PILL makes the padding
    -- symmetric for every alignment; for the dial's CENTER row both are
    -- already concentric, so this changes nothing there.
    if ui.stateLabel then
      setProp(widget, ui.stateLabel, "x", x)
      setProp(widget, ui.stateLabel, "w", w)
      setProp(widget, ui.stateLabel, "align", CENTER)
    end
    -- F8: the pill is a BADGE - the status colour is its GROUND, not its ink.
    --
    -- It used to be a COLOR_THEME_SECONDARY2 fill (a "label/button background"
    -- role) carrying the status colour as text. On the stock theme that is a
    -- #b6e0f2 fill at 1.19:1 against the screen - an invisible pill, read only
    -- through its 1 px outline - with CRIT printed on it at 2.91:1, under the
    -- 3:1 floor. So the most glanceable element in the widget, the one that
    -- says CRIT, was its weakest: a hairline outline around thin coloured text,
    -- seen for ~200 ms in sunlight with the pilot's eyes on the model.
    --
    -- Inverted, the badge is self-grounding and measures 5.2:1 (critical),
    -- 5.6:1 (warning), 5.4:1 (normal) and 6.4:1 (muted), on any theme, because
    -- both the fill and the ink are ours (theme.labelOn).
    local fill = T.stateColor(stateKey(widget), widget.accent)
    local ink = T.labelOn(fill)
    setProp(widget, ui.chip, "color", fill)
    if ui.stateLabel then
      setProp(widget, ui.stateLabel, "color", ink)
    end
    -- The outline takes the badge's OWN ink, not the label role. Under a
    -- SECONDARY2 fill an outline in the label role was the only thing making
    -- the pill visible, so a contrasting chrome colour made sense; over a
    -- coloured fill it reads as a third colour stapled on - a blue hairline
    -- around an amber badge. Ink-coloured, the badge is two colours that
    -- belong together, and the outline still does its remaining job: holding
    -- the shape apart from a theme background at a similar luminance, or from
    -- a background.png photograph.
    if ui.chipEdge then setProp(widget, ui.chipEdge, "color", ink) end
    lvgl.show(ui.chipEdge)
    lvgl.show(ui.chip)
    -- The LABEL travels with the pill. Before F9 this was implicit: the chip
    -- objects only existed when the option was on, so hiding "the chip" hid
    -- everything. Now the objects always exist and only their visibility
    -- moves - and a hidden pill with a visible label left "NO LINK" floating
    -- bare on the dial, which is the very defect the pill was added to fix
    -- (AUDIT.md P1-10, the bar's chipless WARN/CRIT text).
    if ui.stateLabel then lvgl.show(ui.stateLabel) end
    -- frame.chipBox used to be maintained here: the pill's footprint, read by
    -- needleReach() to stop the needle short of it. Both are gone with Tanda 7
    -- A - the pill is opaque and painted after the needle, so it occludes the
    -- blade without anyone having to measure it (see updateArc).
  else
    lvgl.hide(ui.chipEdge)
    lvgl.hide(ui.chip)
    if ui.stateLabel then lvgl.hide(ui.stateLabel) end
  end
  frame.chipShown = show
end

-- The value is CENTRED in a box reserved at the widest sample's width
-- (layout.placeValue, P1-1), so its own ink is always centred on the box
-- regardless of how many digits it actually has - but the unit was placed
-- once, at layout time, against the box's right edge. Re-anchor it to the
-- ink's REAL right edge whenever the text changes: shared by the dial and
-- the bar (bar.lua calls this too) so both keep the visible "value + unit"
-- group centred at any digit count, not just at the widest sample.
-- The live value string is measured through theme.measureWidth - EXACT but
-- deliberately NOT memoized. Measuring it through textWidth would add one
-- permanent entry to the shared width cache per frame at high precision
-- (Tanda 6 F-4).
function M.anchorUnit(widget, str)
  local ui, L = widget.ui, widget.layout
  if not ui.unitLabel then return end
  local actualW = T.measureWidth(str, L.valueFont)
  local inkRight = L.valueBox.x + floor((L.valueBox.w + actualW) / 2)
  local x = inkRight + T.px(T.space.md)
  -- Never anchor the unit outside the zone. In a region too small for the
  -- value+unit group, pickValueFont's last-resort branch clamps the RESERVED
  -- value width below the ink's real width, so ink centred in that box
  -- overhangs to the right and drags the unit with it (measured at 24x24:
  -- the unit label ended 2 px outside the widget). The clamp only ever bites
  -- in that degenerate case - at any size where the group actually fits,
  -- actualW <= valueBox.w and this x is already inside.
  local limit = L.w - L.unitBox.w
  if x > limit then x = limit end
  if x < 0 then x = 0 end
  setProp(widget, ui.unitLabel, "x", x)
end

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
    M.anchorUnit(widget, str)
  end

  if ui.stateLabel then
    local s = stateText(widget)
    if s ~= frame.stateStr then
      frame.stateStr = s
      setProp(widget, ui.stateLabel, "text", s)
      M.updateChip(widget, s)
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

-- NEEDLE LENGTH IS CONSTANT (Tanda 7 A, replacing Tanda 5 review 3.12/P0-4).
--
-- P0-4 used to shorten the blade whenever the current angle's ray entered the
-- state chip, so it would not be "drawn through a solid pill". The paint
-- order already guarantees that: renderer.build creates the needle (objects
-- 11-13 on a 200x160 dial) BEFORE the chip (20-21), the chip is `filled = 1`
-- with no opacity - fully opaque - and LVGL paints children in creation
-- order. The blade behind the pill was never visible in the first place.
--
-- What the truncation did cost was the needle itself. Measured at 200x160,
-- Sweep 270, chip shown: 41 % of the blade left at value 30, 28 % at 34,
-- 18 % at 40, and 13 % - 5 of 38 px - at value 50. It bit on 25 % of the
-- scale at 270 deg, 35 % at 180 and 16 % at 360, and ONLY while a chip was
-- up: that is WARN / CRIT / STALE / NO LINK / NO DATA, the states the pilot
-- actually looks at. A needle that changes length as it sweeps reads as a
-- rendering fault, because no real instrument does it.
--
-- So the needle now runs its full reach at every angle and passes BEHIND the
-- badge, the way a pointer passes behind a label on a real gauge. This is the
-- same creation-order contract the value and name labels already rely on to
-- paint over the arcs (Tanda 5 review 3.1) - not a new assumption. It is
-- pinned by "A: the chip occludes the needle by paint order" in the suite, so
-- if the order or the chip's opacity ever changes, that test fails first and
-- says why.

local function updateArc(widget)
  local ui, L, frame = widget.ui, widget.layout, widget.frame
  local data = widget.data

  if data.availability ~= "valid" or data.displayValue == nil then
    widget.smooth.value = nil
    if frame.needleShown then
      frame.needleShown = false
      if ui.needle then lvgl.hide(ui.needle) end
      if ui.needleMid then lvgl.hide(ui.needleMid) end
      if ui.needleTip then lvgl.hide(ui.needleTip) end
    end
    return
  end

  if frame.prevAvail ~= "valid" then
    widget.smooth.value = nil  -- snap on reconnect instead of sweeping up
  end
  local sv = widget.mods.smoothing.step(widget, data.displayValue)
  local a = angleOf(widget, sv)
  -- The old `or frame.chipShown ~= frame.needleClampChip` term went with
  -- needleReach: it existed only to re-cut the blade when the chip appeared
  -- or vanished, and a blade of constant length has nothing to re-cut. One
  -- fewer comparison per frame, and one fewer needle rewrite per state change.
  if a ~= frame.angle then
    frame.angle = a
    setProp(widget, ui.valueArc, "endAngle", a)
    if ui.needle then
      -- three line segments, all rewritten with the same guarded pts path
      -- as before: base + mid + tip sweep together (P2-1). The pts tables
      -- are the PERSISTENT buffers from buildNeedle, mutated in place by
      -- linePointsInto, and the wrappers are the PERSISTENT { pts = ... }
      -- tables too - zero allocation per frame (Phase 5.1 + 5.2). Direct
      -- lvgl.set, NEVER setProp (identity cache would freeze both, TRAP 2).
      G.linePointsInto(ui.needlePts, L.cx, L.cy, L.needleInner,
                       L.needleBodyOuter, a)
      lvgl.set(ui.needle, ui.needleSet)
      G.linePointsInto(ui.needleMidPts, L.cx, L.cy, L.needleMidInner,
                       L.needleMidOuter, a)
      lvgl.set(ui.needleMid, ui.needleMidSet)
      G.linePointsInto(ui.needleTipPts, L.cx, L.cy, L.needleTipInner,
                       L.needleOuter, a)
      lvgl.set(ui.needleTip, ui.needleTipSet)
    end
  end
  if not frame.needleShown then
    frame.needleShown = true
    if ui.needle then lvgl.show(ui.needle) end
    if ui.needleMid then lvgl.show(ui.needleMid) end
    if ui.needleTip then lvgl.show(ui.needleTip) end
  end
end

local function updateHistory(widget)
  local ui, L, frame = widget.ui, widget.layout, widget.frame
  local h = widget.history

  -- peak-hold ghost: INDEPENDENT of the markers option (firmware idiom
  -- C.3 - always created, visibility driven by DATA). The dial used to
  -- early-return on ui.minMark, so with Min/max = Off the ghost existed
  -- but could never show, while the bar's ghost worked (Tanda 6 F-8).
  -- Both h.min and h.max are required: readHistorySiblings can populate
  -- them independently, and the descending-scale peak picks either one.
  if ui.ghost then
    if h.min and h.max then
      local peak = (widget.config.max >= widget.config.min) and h.max or h.min
      local ga = angleOf(widget, peak)
      if ga ~= frame.ghostAngle then
        frame.ghostAngle = ga
        setProp(widget, ui.ghost, "endAngle", ga)
        setProp(widget, ui.ghost, "bgEndAngle", ga)
        lvgl.show(ui.ghost)
      end
    elseif frame.ghostAngle ~= -1 then
      -- The history was CLEARED - the reset switch, a source change, a range
      -- edit. The markers below already leave on the same event; the ghost
      -- used to stay behind, still marking a peak that no longer exists, and
      -- only corrected itself on the next valid reading. In a dropout, or
      -- straight after a reset on a disconnected model, that is indefinite.
      -- -1 is the build-time sentinel and no real angle (angleOf never
      -- returns below startAngle), so restoring it also re-arms the show.
      frame.ghostAngle = -1
      lvgl.hide(ui.ghost)
    end
  end

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

  -- in-place into the build-time buffers, direct lvgl.set, never setProp
  local a = angleOf(widget, h.min)
  if a ~= frame.minAngle then
    frame.minAngle = a
    G.linePointsInto(ui.minMarkPts, L.cx, L.cy, L.markInner, L.markOuter, a)
    lvgl.set(ui.minMark, ui.minMarkSet)
  end
  a = angleOf(widget, h.max)
  if a ~= frame.maxAngle then
    frame.maxAngle = a
    G.linePointsInto(ui.maxMarkPts, L.cx, L.cy, L.markInner, L.markOuter, a)
    lvgl.set(ui.maxMark, ui.maxMarkSet)
  end
end

-- Critical state pulses at ~1 Hz: attention without colour, so it survives
-- greyscale and colour-blind viewing. Two property writes per second.
-- Shared with the bar (Tanda 6 F-15): `obj` is the pulse target - the value
-- arc for the dial, the fill for the bar.
function M.updatePulse(widget, key, obj)
  local frame = widget.frame
  if key ~= "critical" then
    if frame.pulse then
      frame.pulse = false
      -- Restore the opacity the NEW key calls for, not the full one: losing
      -- the link while the pulse is in its trough must leave the gauge dim
      -- (muted 120), not stuck at 255 until the next colour change
      -- (AUDIT.md P1-1).
      setProp(widget, obj, "opacity",
              (key == "muted") and T.opacity.muted or T.opacity.full)
    end
    return
  end
  local now = getTime()
  if now - frame.pulseAt >= 50 then  -- 50 * 10 ms
    frame.pulseAt = now
    frame.pulse = not frame.pulse
    setProp(widget, obj, "opacity",
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
  -- This runs from app.update(), OUTSIDE the frame's refresh: flush the
  -- queued writes here so a Name/Suffix edit reaches LVGL before the next
  -- refresh (the cheap delta path of AUDIT.md P0-6).
  M.flush(widget)
end

function M.update(widget)
  local ui = widget.ui
  if not ui.built then return end
  local frame = widget.frame

  local key = M.colorKey(widget)
  -- The accent is an INPUT to the colour (normal band, Static mode), so an
  -- Accent edit must repaint even when the semantic key did not change
  -- (Tanda 6 F-5; cf. radio_info.cpp re-reading its colour options in
  -- update()). frame.colorKey stays the SEMANTIC key - tests and the
  -- gallery read it as the state label - the accent rides on its own gate.
  if key ~= frame.colorKey or widget.accent ~= frame.accentKey then
    frame.colorKey = key
    frame.accentKey = widget.accent
    applyColors(widget, key)
  end

  M.applyStateInk(widget)
  updateText(widget)
  updateArc(widget)
  updateHistory(widget)
  M.updatePulse(widget, key, ui.valueArc)

  M.flush(widget)
  frame.prevAvail = widget.data.availability
end

return M
