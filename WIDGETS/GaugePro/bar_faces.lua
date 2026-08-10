---- #########################################################################
---- #                                                                       #
---- # Gauge Pro - retained bar face contract                                #
---- #                                                                       #
---- # Face code receives normalized render state. It never reads sensors,   #
---- # classifies alerts, owns labels/badges/history, or creates objects in  #
---- # update(). Continuous, Blocks, Hex, Ticks, and Steps are production     #
---- # faces. Signed Dual Rail remains explicit Phase 5 work.                 #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local T, G, R
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

local GRADIENT_CEILING = 38
local GRADIENT_SHARED_RESERVE = 11

function M.setup(theme, geometry, renderer)
  T, G, R = theme, geometry, renderer
end

local function unavailableSupports()
  return false
end

local function unavailableBuild()
  return false
end

local function unavailableUpdate() end
local function unavailablePalette() end
local function unavailableVisible() end

local function continuousSupports(_profile, config)
  return (not config or not config.direction or config.direction == "horizontal")
    and (not config or not config.origin or config.origin == "scale-low")
end

function M.gradientSliceCount(length, available)
  local target = ceil(max(1, tonumber(length) or 1) / T.px(12))
  target = max(8, min(24, target))
  return max(1, min(target, floor(tonumber(available) or 24)))
end

-- Map a physical position on the authored scale into the semantic gradient:
-- critical=0, warning=.5, normal=1. Descending scales and low-is-good both
-- fall out of the same value mapping instead of swapping face-local bands.
function M.gradientPosition(cfg, axisPosition)
  axisPosition = max(0, min(1, tonumber(axisPosition) or 0))
  local value = cfg.min + (cfg.max - cfg.min) * axisPosition
  local lo, hi = cfg.crit, cfg.warn
  if lo > hi then lo, hi = hi, lo end
  if lo == hi then
    if cfg.highGood then return (value >= hi) and 1 or 0 end
    return (value <= lo) and 1 or 0
  end
  local t = G.normalize(value, lo, hi)
  if not cfg.highGood then t = 1 - t end
  return t
end

local function gradientFixedObjects(config, layout)
  local count = 1 -- exact position head
  if config and config.surface and config.surface ~= "transparent" then
    count = count + 1
  end
  if config and config.ends == "chamfer" then
    count = count + 4 -- three-piece track + authored-start tip
  else
    count = count + 1 -- one-piece track
    -- The current one-pixel casing is a centre rectangle plus two bevel tips.
    -- With no concrete layout (the estimator), reserve it conservatively.
    if not layout or (layout.barEdge or 0) > 0 then count = count + 3 end
  end
  return count
end

local function gradientSharedObjects(widget)
  local L, cfg = widget.layout, widget.config
  local count = 1 -- value label
  if L.showUnit and widget.unitText ~= "" then count = count + 1 end
  if L.showName then count = count + 1 end
  if L.showState then count = count + 3 end -- edge + fill + label
  if L.showGhost then count = count + 1 end
  if L.showMarkers then count = count + 2 end
  if cfg.colorMode ~= R.COLOR_STATIC then
    for i = 1, #widget.ranges do
      local t = G.normalize(widget.ranges[i].to, cfg.min, cfg.max)
      if t > 0 and t < 1 then count = count + 1 end
    end
  end
  return count
end

local function continuousEstimate(profile, config)
  if config and config.colorMode == R.COLOR_GRADIENT then
    local fixed = gradientFixedObjects(config)
    local available = GRADIENT_CEILING - GRADIENT_SHARED_RESERVE - fixed
    local length = (profile and profile.w) or 300
    return GRADIENT_SHARED_RESERVE + fixed
      + M.gradientSliceCount(length, available)
  end
  local count = 7 -- casing + track + fill + exact head + three bands
  if config and config.surface and config.surface ~= "transparent" then
    count = count + 1
  end
  if config and config.ends == "chamfer" then count = count + 2 end
  return count
end

local function shape(ui, key, rect, color, opacity, radius, bevel)
  bevel = min(bevel or 0, floor((rect.w - 1) / 2), floor(rect.h / 2))
  if bevel > 0 then
    ui[key] = lvgl.rectangle{
      x = rect.x + bevel, y = rect.y,
      w = max(1, rect.w - bevel * 2), h = rect.h,
      color = color, opacity = opacity, filled = 1, rounded = 0,
    }
    ui[key .. "Caps"] = {
      lvgl.triangle{
        pts = {
          { rect.x + bevel, rect.y },
          { rect.x + bevel, rect.y + rect.h },
          { rect.x, rect.y + floor(rect.h / 2) },
        },
        color = color, opacity = opacity,
      },
      lvgl.triangle{
        pts = {
          { rect.x + rect.w - bevel, rect.y },
          { rect.x + rect.w, rect.y + floor(rect.h / 2) },
          { rect.x + rect.w - bevel, rect.y + rect.h },
        },
        color = color, opacity = opacity,
      },
    }
  else
    ui[key] = lvgl.rectangle{
      x = rect.x, y = rect.y, w = rect.w, h = rect.h,
      color = color, opacity = opacity, filled = 1, rounded = radius or 0,
    }
  end
end

local function setShapeProp(widget, ui, key, prop, value)
  R.setProp(widget, ui[key], prop, value)
  local caps = ui[key .. "Caps"]
  if caps then
    for i = 1, #caps do R.setProp(widget, caps[i], prop, value) end
  end
end

local function showShape(ui, key, visible)
  local fn = visible and lvgl.show or lvgl.hide
  if ui[key] then fn(ui[key]) end
  local caps = ui[key .. "Caps"]
  if caps then for i = 1, #caps do fn(caps[i]) end end
end

local function bandSpan(axis, range, cfg)
  local t1 = G.normalize(range.from, cfg.min, cfg.max)
  local t2 = G.normalize(range.to, cfg.min, cfg.max)
  if t1 > t2 then t1, t2 = t2, t1 end
  local x1 = axis.x + floor(axis.w * t1 + 0.5)
  local x2 = axis.x + floor(axis.w * t2 + 0.5)
  return x1, max(0, x2 - x1)
end

local function buildReferenceBands(widget, axis)
  local ui, cfg, palette = widget.ui, widget.config, widget.barPalette
  if cfg.colorMode ~= R.COLOR_RAIL and cfg.colorMode ~= R.COLOR_SECTIONS then
    return
  end
  ui.rails = {}
  local railH = max(1, min(T.px(3), floor(axis.h * 0.3)))
  local railY = axis.y + axis.h - railH
  for i = 1, #widget.ranges do
    local range = widget.ranges[i]
    if cfg.colorMode == R.COLOR_SECTIONS or range.role ~= "normal" then
      local x, w = bandSpan(axis, range, cfg)
      if w > 0 then
        local opacity = (cfg.colorMode == R.COLOR_SECTIONS)
          and T.opacity.ghost or T.opacity.railBand
        local band = lvgl.rectangle{
          x = x, y = railY, w = w, h = railH,
          color = T.stateColor(range.role, widget.accent, palette),
          opacity = opacity, filled = 1, rounded = 0,
        }
        band.role, band.baseOpacity = range.role, opacity
        ui.rails[#ui.rails + 1] = band
      end
    end
  end
end

local function continuousBuild(widget, _geometry, style)
  local L, ui = widget.layout, widget.ui
  local b, outer = L.bar, L.barOuter or L.bar
  local palette = widget.barPalette
  local track = (palette and palette.track) or T.color.rail
  local border = (palette and palette.border) or T.color.label
  local bevel = (style.ends == "chamfer") and L.barChamfer or 0

  -- Surface is intentionally first: every instrument object and every shared
  -- label is created after it, so a theme/custom panel can ground the complete
  -- widget without changing text geometry.
  if style.surface ~= "transparent" then
    ui.panel = lvgl.rectangle{
      x = 0, y = 0, w = L.w, h = L.h,
      color = (palette and palette.panel) or COLOR_THEME_SECONDARY3,
      opacity = T.opacity.full, filled = 1,
      rounded = min(T.px(8), floor(min(L.w, L.h) / 8)),
    }
  end

  -- Round/square bodies use a separate one-pixel casing. A true chamfer
  -- already needs three retained track primitives; omitting its redundant
  -- second three-piece silhouette keeps the worst surface+sections variant
  -- inside the approved 24-object Continuous budget.
  if (L.barEdge or 0) > 0 and bevel == 0 then
    shape(ui, "casing", outer, border, T.opacity.railBand,
          L.barOuterRadius, bevel + L.barEdge)
  end
  shape(ui, "track", b, track, T.opacity.rail, L.barRadius, bevel)

  -- Chamfer tips are casing, not authored scale. Keeping the data axis in the
  -- central body prevents a one-pixel fill from leaking into transparent
  -- corners and makes threshold/head/history positions share one exact map.
  local axis = L.barAxis or b
  local active = L.activeBar or axis
  buildReferenceBands(widget, axis)

  -- Shared threshold/history overlays are built after this body. The head is
  -- built even later by continuousBuildOverlay, so the paint stack is always
  -- body -> thresholds/history -> exact position head -> text/badge.
  if widget.config.colorMode == R.COLOR_GRADIENT then
    local fixed = gradientFixedObjects(style, L)
    local available = GRADIENT_CEILING - gradientSharedObjects(widget) - fixed
    local count = M.gradientSliceCount(axis.w, available)
    ui.gradientSlices = {}
    style.gradientSlices = count
    for i = 1, count do
      local x1 = floor(axis.w * (i - 1) / count)
      local x2 = floor(axis.w * i / count)
      local slice = lvgl.rectangle{
        x = active.x + x1, y = active.y,
        w = max(1, x2 - x1), h = active.h,
        -- The first refresh paints the complete signature-keyed ramp. Keeping
        -- build colour constant splits interpolation work out of the already
        -- expensive structural callback without ever showing a wrong slice:
        -- every slice remains hidden until that refresh sets its span.
        color = (palette and palette.critical) or T.color.crit,
        filled = 1, rounded = 0,
      }
      slice.startOffset, slice.endOffset = x1, x2
      slice.baseW = max(1, x2 - x1)
      slice.barShown = false
      lvgl.hide(slice)
      ui.gradientSlices[i] = slice
    end
    -- Shared code and diagnostics continue to have one canonical fill handle;
    -- the pulse target below owns the complete slice pool.
    ui.fill = ui.gradientSlices[1]
  else
    ui.fill = lvgl.rectangle{
      x = active.x, y = active.y, w = 1, h = active.h,
      color = (palette and palette.normal) or T.color.accent,
      filled = 1,
      rounded = (style.ends == "round") and floor(active.h / 2) or 0,
    }
    lvgl.hide(ui.fill)
  end
  if bevel > 0 then
    local capColor = ui.gradientSlices
      and ((palette and palette.critical) or T.color.crit)
      or (palette and palette.normal) or T.color.accent
    ui.fillCap = lvgl.triangle{
      pts = {
        { active.x, active.y },
        { active.x, active.y + active.h },
        { b.x, active.y + floor(active.h / 2) },
      },
      color = capColor,
    }
    lvgl.hide(ui.fillCap)
  end
  if ui.gradientSlices then
    ui.pulseTargets = {}
    for i = 1, #ui.gradientSlices do
      ui.pulseTargets[i] = ui.gradientSlices[i]
    end
    if ui.fillCap then
      ui.pulseTargets[#ui.pulseTargets + 1] = ui.fillCap
    end
  else
    ui.pulseTargets = { ui.fill }
    if ui.fillCap then ui.pulseTargets[2] = ui.fillCap end
  end
  return true
end

local function movingHead(ui, key, x, y1, y2, thickness, color, opacity)
  local pts = { { x, y1 }, { x, y2 } }
  ui[key .. "Pts"] = pts
  ui[key .. "Set"] = { pts = pts }
  ui[key] = lvgl.line{
    pts = pts, thickness = thickness, color = color, opacity = opacity,
    rounded = 1,
  }
  lvgl.hide(ui[key])
end

local function continuousBuildOverlay(widget)
  local L, ui = widget.layout, widget.ui
  local axis, outer = L.barAxis or L.bar, L.barOuter or L.bar
  local x = axis.x
  movingHead(ui, "head", x, outer.y - T.px(1),
             outer.y + outer.h + T.px(1), L.markThickness,
             T.labelOn((widget.barPalette and widget.barPalette.normal)
                         or T.color.accent, widget.barPalette), T.opacity.full)
end

local function moveHead(ui, key, x)
  local pts = ui[key .. "Pts"]
  pts[1][1], pts[2][1] = x, x
  lvgl.set(ui[key], ui[key .. "Set"])
  lvgl.show(ui[key])
end

local function showSlice(slice, shown)
  if slice.barShown == shown then return end
  slice.barShown = shown
  if shown then lvgl.show(slice) else lvgl.hide(slice) end
end

local function hideGradient(objects)
  for i = 1, #objects.gradientSlices do
    showSlice(objects.gradientSlices[i], false)
  end
end

-- Only a crossed boundary touches the whole pool. While the value moves
-- inside one slice, exactly one retained width changes.
local function updateGradient(widget, objects, rawW)
  local slices, frame = objects.gradientSlices, widget.frame
  local count, axisW = #slices, (widget.layout.barAxis or widget.layout.bar).w
  local whole, partial = 0, 0
  if rawW >= axisW then
    whole = count
  elseif rawW > 0 then
    local current = min(count, floor(rawW * count / axisW) + 1)
    while current > 1 and rawW < slices[current].startOffset do
      current = current - 1
    end
    while current <= count and rawW >= slices[current].endOffset do
      current = current + 1
    end
    whole = current - 1
    if current <= count then partial = rawW - slices[current].startOffset end
  end

  if whole ~= frame.gradientWhole then
    frame.gradientWhole = whole
    for i = 1, count do
      local slice = slices[i]
      if i <= whole then
        R.setProp(widget, slice, "w", slice.baseW)
        showSlice(slice, true)
      elseif i == whole + 1 and partial > 0 then
        R.setProp(widget, slice, "w", partial)
        showSlice(slice, true)
      else
        showSlice(slice, false)
      end
    end
  elseif whole < count then
    local slice = slices[whole + 1]
    if partial > 0 then
      R.setProp(widget, slice, "w", partial)
      showSlice(slice, true)
    else
      showSlice(slice, false)
    end
  end
end

local function continuousUpdate(widget, objects, state)
  local frame = widget.frame
  if not state.valid then
    if frame.fillShown then
      frame.fillShown = false
      if objects.gradientSlices then
        hideGradient(objects)
        frame.gradientWhole = -1
      else
        lvgl.hide(objects.fill)
      end
      if objects.fillCap then lvgl.hide(objects.fillCap) end
    end
    if frame.headShown then
      frame.headShown = false
      lvgl.hide(objects.head)
    end
    return
  end
  local axis = widget.layout.barAxis or widget.layout.bar
  local rawW = G.barFill(axis.w, state.smoothValue,
                         widget.config.min, widget.config.max)
  local shown = rawW > 0
  if shown ~= frame.fillShown then
    frame.fillShown = shown
    if shown then
      if not objects.gradientSlices then lvgl.show(objects.fill) end
      if objects.fillCap then lvgl.show(objects.fillCap) end
    else
      if objects.gradientSlices then
        hideGradient(objects)
        frame.gradientWhole = -1
      else
        lvgl.hide(objects.fill)
      end
      if objects.fillCap then lvgl.hide(objects.fillCap) end
    end
  end
  if objects.gradientSlices then
    updateGradient(widget, objects, rawW)
    frame.fillW = rawW
  else
    local w = max(rawW, 1)
    if w ~= frame.fillW then
      frame.fillW = w
      R.setProp(widget, objects.fill, "w", w)
    end
  end
  local x = axis.x + rawW
  if x ~= frame.headX then
    frame.headX = x
    moveHead(objects, "head", x)
    frame.headShown = true
  elseif not frame.headShown then
    frame.headShown = true
    lvgl.show(objects.head)
  end
end

local function continuousPalette(widget, objects, palette, state)
  if state.paletteChanged then
    if objects.panel then R.setProp(widget, objects.panel, "color", palette.panel) end
    setShapeProp(widget, objects, "casing", "color", palette.border)
    setShapeProp(widget, objects, "track", "color", palette.track)
  end
  local assist = palette.assist
  local assisted = assist == "needed" or assist == "strong"
  local casingOpacity = assisted and T.opacity.full or T.opacity.railBand
  local trackOpacity = (assist == "strong") and T.opacity.railBand
    or assisted and min(T.opacity.full, T.opacity.rail + 60) or T.opacity.rail
  setShapeProp(widget, objects, "casing", "opacity", casingOpacity)
  setShapeProp(widget, objects, "track", "opacity", trackOpacity)
  if objects.rails then
    for i = 1, #objects.rails do
      local rail = objects.rails[i]
      R.setProp(widget, rail, "color",
                T.stateColor(rail.role, widget.accent, palette))
      R.setProp(widget, rail, "opacity",
                (state.colorKey == "muted") and T.opacity.muted
                  or rail.baseOpacity)
    end
  end
  local fill = R.resolveColor(widget, state.colorKey, palette)
  if objects.gradientSlices then
    if state.paletteChanged then
      local axisW = (widget.layout.barAxis or widget.layout.bar).w
      local sliceCount = #objects.gradientSlices
      for i = 1, #objects.gradientSlices do
        local slice = objects.gradientSlices[i]
        if slice.gradientT == nil then
          local sample = (i == 1) and 0
            or (i == sliceCount) and 1
            or ((slice.startOffset + slice.endOffset) * 0.5
                / axisW)
          slice.gradientT = M.gradientPosition(widget.config, sample)
        end
        local sliceColor
        if slice.gradientT <= 0 then sliceColor = palette.critical
        elseif slice.gradientT >= 1 then sliceColor = palette.normal
        elseif slice.gradientT == 0.5 then sliceColor = palette.warning
        else sliceColor = T.paletteColor(palette, slice.gradientT, 24) end
        R.setProp(widget, slice, "color",
                  sliceColor)
      end
    end
  else
    R.setProp(widget, objects.fill, "color", fill)
  end
  if state.opacity ~= widget.frame.faceOpacity then
    widget.frame.faceOpacity = state.opacity
    if objects.gradientSlices then
      for i = 1, #objects.gradientSlices do
        R.setProp(widget, objects.gradientSlices[i], "opacity", state.opacity)
      end
    else
      R.setProp(widget, objects.fill, "opacity", state.opacity)
    end
  end
  if objects.fillCap then
    local capColor = objects.gradientSlices
      and palette.critical
      or fill
    R.setProp(widget, objects.fillCap, "color", capColor)
    if state.opacity ~= widget.frame.fillCapOpacity then
      widget.frame.fillCapOpacity = state.opacity
      R.setProp(widget, objects.fillCap, "opacity", state.opacity)
    end
  end
  R.setProp(widget, objects.head, "color", T.labelOn(fill, palette))
  R.setProp(widget, objects.head, "opacity", state.opacity)
  local headThickness = widget.layout.markThickness
    + ((assist == "strong") and T.px(2) or assisted and T.px(1) or 0)
  R.setProp(widget, objects.head, "thickness", headThickness)
end

local function continuousVisible(objects, visible)
  local fn = visible and lvgl.show or lvgl.hide
  if objects.panel then fn(objects.panel) end
  showShape(objects, "casing", visible)
  showShape(objects, "track", visible)
  if objects.rails then for i = 1, #objects.rails do fn(objects.rails[i]) end end
  if objects.gradientSlices then
    if not visible then hideGradient(objects) end
  else
    fn(objects.fill)
  end
  if objects.fillCap then fn(objects.fillCap) end
  fn(objects.head)
end

-- ------------------------------------------------------- segmented faces --

local function segmentedSupports(_profile, config)
  return (not config or not config.direction or config.direction == "horizontal")
    and (not config or not config.origin or config.origin == "scale-low")
end

-- Whole segments plus the truthful fraction of the current segment. Ticks
-- and Steps pass partial=false and use the exact retained head for precision.
function M.segmentProgress(count, normalized, partial)
  count = max(1, floor(tonumber(count) or 1))
  normalized = max(0, min(1, tonumber(normalized) or 0))
  if normalized >= 1 then return count, 0 end
  local scaled = normalized * count
  local whole = floor(scaled)
  return whole, partial and (scaled - whole) or 0
end

local function addDowngrade(style, reason)
  if not style or not style.downgrades then return end
  for i = 1, #style.downgrades do
    if style.downgrades[i] == reason then return end
  end
  style.downgrades[#style.downgrades + 1] = reason
end

local function buildPanel(widget, style)
  if style.surface == "transparent" then return end
  local L, palette = widget.layout, widget.barPalette
  widget.ui.panel = lvgl.rectangle{
    x = 0, y = 0, w = L.w, h = L.h,
    color = (palette and palette.panel) or COLOR_THEME_SECONDARY3,
    opacity = T.opacity.full, filled = 1,
    rounded = min(T.px(8), floor(min(L.w, L.h) / 8)),
  }
end

local function gapPixels(style)
  if style.gap == "wide" then return T.px(5) end
  if style.gap == "tight" then return T.px(2) end
  return T.px(3)
end

local function budgetedCount(widget, style, ceiling, perCell,
                              minimum, maximum, geometryCap)
  local fixed = 1 -- exact retained head
  if style.surface ~= "transparent" then fixed = fixed + 1 end
  local available = ceiling - gradientSharedObjects(widget) - fixed
  local budgetCap = max(1, floor(available / perCell))
  local requested = max(minimum, min(maximum, style.segments or minimum))
  local count = min(requested, budgetCap, geometryCap or maximum)
  count = max(1, count)
  if count < requested then addDowngrade(style, "segments-whole-tree-budget") end
  style.renderedSegments = count
  return count
end

local function slotGeometry(axis, index, count, gap)
  local x1 = floor(axis.w * (index - 1) / count)
  local x2 = floor(axis.w * index / count)
  local trailing = (index < count) and min(gap, max(0, x2 - x1 - 1)) or 0
  return axis.x + x1, max(1, x2 - x1 - trailing), x1, x2
end

local function roleBands(widget)
  local bands = {}
  for i = 1, #widget.ranges do
    local range = widget.ranges[i]
    local a = G.normalize(range.from, widget.config.min, widget.config.max)
    local b = G.normalize(range.to, widget.config.min, widget.config.max)
    if a > b then a, b = b, a end
    local n = #bands
    bands[n + 1], bands[n + 2], bands[n + 3] = a, b, range.role
  end
  return bands
end

local function roleAt(bands, position)
  for i = 1, #bands, 3 do
    if position >= bands[i]
       and (position < bands[i + 1] or i == #bands - 2) then
      return bands[i + 2]
    end
  end
  return "normal"
end

local function spatialColor(widget, palette, position)
  local t = M.gradientPosition(widget.config, position)
  if t <= 0 then return palette.critical end
  if t >= 1 then return palette.normal end
  if t == 0.5 then return palette.warning end
  return T.paletteColor(palette, t, 24)
end

local function paintCell(cell, stateOpacity)
  local fraction = cell.fraction
  local active = fraction > 0
  local color = active and cell.activeColor or cell.referenceColor
  local base = cell.baseOpacity
  local opacity
  if stateOpacity == T.opacity.full and fraction == 1 then
    opacity = T.opacity.full
  elseif stateOpacity == T.opacity.full and fraction == 0 then
    opacity = base
  else
    local logical = base + floor((T.opacity.full - base) * fraction + 0.5)
    opacity = floor(logical * stateOpacity / T.opacity.full + 0.5)
  end
  if cell.paintColor == color and cell.paintOpacity == opacity then return end
  cell.paintColor, cell.paintOpacity = color, opacity
  local props = cell.paintProps
  props.color, props.opacity = color, opacity
  -- Cell parts always change color and opacity together. Their retained
  -- two-key table avoids two renderer-cache walks per part and allocates
  -- nothing while a fast telemetry source moves.
  for i = 1, #cell.parts do lvgl.set(cell.parts[i], props) end
end

local function setCellFraction(cell, fraction, stateOpacity, force)
  if not force and cell.fraction == fraction then return end
  cell.fraction = fraction
  paintCell(cell, stateOpacity)
end

local function baseOpacity(widget, cell, palette)
  local mode = widget.config.colorMode
  local opacity
  if mode == R.COLOR_RAIL and cell.role ~= "normal" then
    opacity = (cell.role == "critical")
      and T.opacity.railBandCrit or T.opacity.railBand
  elseif mode == R.COLOR_SECTIONS or mode == R.COLOR_GRADIENT then
    opacity = T.opacity.ghost
  else
    opacity = T.opacity.rail
  end
  if palette.assist == "strong" then
    opacity = max(28, floor(opacity * 0.55))
  elseif palette.assist == "needed" then
    opacity = max(36, floor(opacity * 0.75))
  end
  return opacity
end

local function colorsForCell(widget, cell, palette, fill)
  local mode = widget.config.colorMode
  local semantic = T.stateColor(cell.role, widget.accent, palette)
  if mode == R.COLOR_GRADIENT then
    local spatial = spatialColor(widget, palette, cell.position)
    return spatial, spatial
  elseif mode == R.COLOR_SECTIONS then
    return semantic, semantic
  elseif mode == R.COLOR_RAIL and cell.role ~= "normal" then
    return semantic, fill
  end
  return palette.track, fill
end

local function segmentedPalette(widget, objects, palette, state)
  local paletteChanged = objects.segmentPaletteSig ~= palette.signature
  local colorChanged = objects.segmentColorKey ~= state.colorKey
  objects.segmentPaletteSig = palette.signature
  objects.segmentColorKey = state.colorKey
  if objects.panel and paletteChanged then
    R.setProp(widget, objects.panel, "color", palette.panel)
  end
  local fill = R.resolveColor(widget, state.colorKey, palette)
  local stateColored = widget.config.colorMode ~= R.COLOR_GRADIENT
    and widget.config.colorMode ~= R.COLOR_SECTIONS
  for i = 1, #objects.faceCells do
    local cell = objects.faceCells[i]
    if paletteChanged then
      cell.referenceColor, cell.activeColor = colorsForCell(
        widget, cell, palette, fill)
      cell.baseOpacity = baseOpacity(widget, cell, palette)
    elseif colorChanged and stateColored then
      cell.activeColor = fill
    end
  end
  objects.repaintAll = paletteChanged
  objects.repaintActive = colorChanged and stateColored and not paletteChanged
  R.setProp(widget, objects.head, "color", T.labelOn(fill, palette))
  R.setProp(widget, objects.head, "opacity", state.opacity)
  local assisted = palette.assist == "needed" or palette.assist == "strong"
  local headThickness = widget.layout.markThickness
    + ((palette.assist == "strong") and T.px(2)
       or assisted and T.px(1) or 0)
  R.setProp(widget, objects.head, "thickness", headThickness)
end

local function segmentedBuildOverlay(widget)
  local L, ui = widget.layout, widget.ui
  local axis, outer = L.barAxis or L.bar, L.barOuter or L.bar
  movingHead(ui, "head", axis.x, outer.y - T.px(1),
             outer.y + outer.h + T.px(1), L.markThickness,
             T.labelOn((widget.barPalette and widget.barPalette.normal)
                         or T.color.accent, widget.barPalette), T.opacity.full)
  -- Segments remain visible to provide their reference scale, so pulsing their
  -- opacity would destroy partial-cell and inactive-state truth. The exact
  -- head is the retained, color-independent critical pulse target.
  ui.pulseTargets = { ui.head }
  return true
end

local function updatePartialCells(widget, objects, normalized, stateOpacity)
  local cells, frame = objects.faceCells, widget.frame
  local scaled = normalized * #cells
  local whole = (normalized >= 1) and #cells or floor(scaled)
  local partial = (whole < #cells) and (scaled - whole) or 0
  local oldWhole = frame.segmentWhole
  if oldWhole == nil then
    for i = 1, #cells do
      local fraction = (i <= whole) and 1
        or (i == whole + 1) and partial or 0
      setCellFraction(cells[i], fraction, stateOpacity)
    end
  elseif whole > oldWhole then
    for i = oldWhole + 1, whole do
      setCellFraction(cells[i], 1, stateOpacity)
    end
  elseif whole < oldWhole then
    local last = oldWhole + 1
    if last > #cells then last = #cells end
    for i = whole + 2, last do
      setCellFraction(cells[i], 0, stateOpacity)
    end
  end
  if whole < #cells then
    setCellFraction(cells[whole + 1], partial, stateOpacity)
  end
  frame.segmentWhole = whole
end

local function updatePointCells(widget, objects, normalized, stateOpacity)
  local cells, frame = objects.faceCells, widget.frame
  local active = frame.segmentActive or 0
  while active < #cells and normalized >= cells[active + 1].position do
    active = active + 1
    setCellFraction(cells[active], 1, stateOpacity)
  end
  while active > 0 and normalized < cells[active].position do
    setCellFraction(cells[active], 0, stateOpacity)
    active = active - 1
  end
  frame.segmentActive = active
end

local function updateWholeCells(widget, objects, normalized, stateOpacity)
  local cells, frame = objects.faceCells, widget.frame
  local whole = (normalized >= 1) and #cells or floor(normalized * #cells)
  local oldWhole = frame.segmentWhole or 0
  if whole > oldWhole then
    for i = oldWhole + 1, whole do
      setCellFraction(cells[i], 1, stateOpacity)
    end
  elseif whole < oldWhole then
    for i = oldWhole, whole + 1, -1 do
      setCellFraction(cells[i], 0, stateOpacity)
    end
  end
  frame.segmentWhole = whole
end

local function segmentedUpdate(widget, objects, state)
  local cells, frame = objects.faceCells, widget.frame
  local opacityChanged = frame.segmentOpacity ~= state.opacity
  frame.segmentOpacity = state.opacity
  if not state.valid then
    for i = 1, #cells do
      setCellFraction(cells[i], 0, state.opacity)
    end
    if objects.repaintAll or opacityChanged then
      for i = 1, #cells do paintCell(cells[i], state.opacity) end
    end
    objects.repaintAll, objects.repaintActive = false, false
    frame.segmentWhole, frame.segmentActive = 0, 0
    if frame.headShown then
      frame.headShown = false
      lvgl.hide(objects.head)
    end
    return
  end

  local normalized = state.smoothNormalized
  if objects.activation == "partial" then
    updatePartialCells(widget, objects, normalized, state.opacity)
  elseif objects.activation == "points" then
    updatePointCells(widget, objects, normalized, state.opacity)
  else -- whole increasing steps
    updateWholeCells(widget, objects, normalized, state.opacity)
  end

  if objects.repaintAll or opacityChanged then
    for i = 1, #cells do paintCell(cells[i], state.opacity) end
  elseif objects.repaintActive then
    for i = 1, #cells do
      if (cells[i].fraction or 0) > 0 then
        paintCell(cells[i], state.opacity)
      end
    end
  end
  objects.repaintAll, objects.repaintActive = false, false

  local axis = widget.layout.barAxis or widget.layout.bar
  local rawW = floor(axis.w * normalized + 0.5)
  local x = axis.x + rawW
  if x ~= frame.headX then
    frame.headX = x
    moveHead(objects, "head", x)
    frame.headShown = true
  elseif not frame.headShown then
    frame.headShown = true
    lvgl.show(objects.head)
  end
end

local function segmentedVisible(objects, visible)
  local fn = visible and lvgl.show or lvgl.hide
  if objects.panel then fn(objects.panel) end
  for i = 1, #objects.faceCells do
    local parts = objects.faceCells[i].parts
    for j = 1, #parts do fn(parts[j]) end
  end
  fn(objects.head)
end

local function beginSegmented(widget, style, kind)
  buildPanel(widget, style)
  local ui = widget.ui
  ui.faceKind = kind
  ui.faceCells = {}
  ui.faceRoleBands = roleBands(widget)
  return widget.layout.barAxis or widget.layout.bar, ui.faceCells,
    ui.faceRoleBands
end

local function appendCell(cells, primary, parts, position, role, variant)
  local cell = {
    primary = primary, parts = parts, position = position, role = role,
    fraction = 0, baseOpacity = T.opacity.rail,
    referenceColor = T.color.rail, activeColor = T.color.accent,
    variant = variant, paintProps = {},
  }
  cells[#cells + 1] = cell
  return cell
end

local function blocksBuild(widget, _geometry, style)
  local axis, cells, bands = beginSegmented(widget, style, "blocks")
  local gap = gapPixels(style)
  local minCell = T.px(3)
  local geometryCap = max(6, floor((axis.w + gap) / (minCell + gap)))
  local count = budgetedCount(widget, style, 38, 1, 6, 24, geometryCap)
  local radius = (style.ends == "round") and min(T.px(3), floor(axis.h / 3)) or 0
  local variant = (radius > 0) and "soft" or "square"
  for i = 1, count do
    local x, w = slotGeometry(axis, i, count, gap)
    local rect = lvgl.rectangle{
      x = x, y = axis.y, w = w, h = axis.h,
      color = widget.barPalette.track, opacity = T.opacity.rail,
      filled = 1, rounded = radius,
    }
    local position = (i - 0.5) / count
    appendCell(cells, rect, { rect }, position,
               roleAt(bands, position), variant)
  end
  widget.ui.fill = cells[1] and cells[1].primary or nil
  widget.ui.activation = "partial"
  return true
end

local function hexBuild(widget, _geometry, style)
  local axis, cells, bands = beginSegmented(widget, style, "hex")
  local gap = gapPixels(style)
  local tip = min(floor(axis.h / 2), T.px(6))
  local compactBlock = tip < T.px(2) or axis.h < T.px(5)
  local perCell = compactBlock and 1 or 3
  local minimumWidth = compactBlock and T.px(3) or (tip * 2 + T.px(2))
  local geometryCap = max(6, floor((axis.w + gap) / (minimumWidth + gap)))
  local count = budgetedCount(widget, style, 40, perCell, 6, 10, geometryCap)
  if compactBlock then
    style.faceVariant = "blocks-compact"
    addDowngrade(style, "hex-compact-blocks")
  else
    style.faceVariant = "true-hex"
  end
  for i = 1, count do
    local x, w = slotGeometry(axis, i, count, gap)
    local position = (i - 0.5) / count
    if compactBlock or w < tip * 2 + 1 then
      local rect = lvgl.rectangle{
        x = x, y = axis.y, w = w, h = axis.h,
        color = widget.barPalette.track, opacity = T.opacity.rail,
        filled = 1, rounded = 0,
      }
      appendCell(cells, rect, { rect }, position,
                 roleAt(bands, position), "block")
      style.faceVariant = "blocks-compact"
    else
      local localTip = min(tip, floor((w - 1) / 2))
      local centerX = x + localTip
      local centerW = max(1, w - localTip * 2)
      local center = lvgl.rectangle{
        x = centerX, y = axis.y, w = centerW, h = axis.h,
        color = widget.barPalette.track, opacity = T.opacity.rail,
        filled = 1, rounded = 0,
      }
      local midY = axis.y + floor(axis.h / 2)
      local left = lvgl.triangle{
        pts = {
          { centerX, axis.y }, { centerX, axis.y + axis.h }, { x, midY },
        },
        color = widget.barPalette.track, opacity = T.opacity.rail,
      }
      local rightX = centerX + centerW
      local right = lvgl.triangle{
        pts = {
          { rightX, axis.y }, { x + w, midY },
          { rightX, axis.y + axis.h },
        },
        color = widget.barPalette.track, opacity = T.opacity.rail,
      }
      appendCell(cells, center, { center, left, right }, position,
                 roleAt(bands, position), "hex")
    end
  end
  widget.ui.fill = cells[1] and cells[1].primary or nil
  widget.ui.activation = "partial"
  return true
end

local function thresholdTicks(widget, count)
  local forced = {}
  for i = 1, #widget.ranges do
    local range = widget.ranges[i]
    local position = G.normalize(range.to, widget.config.min, widget.config.max)
    if position > 0 and position < 1 then
      local index = floor(position * (count - 1) + 1.5)
      index = max(2, min(count - 1, index))
      forced[index] = { position = position, role = range.role }
    end
  end
  return forced
end

local function ticksBuild(widget, _geometry, style)
  local axis, cells, bands = beginSegmented(widget, style, "ticks")
  local geometryCap = max(8, floor(axis.w / T.px(4)) + 1)
  local count = budgetedCount(widget, style, 40, 1, 8, 28, geometryCap)
  local forced = thresholdTicks(widget, count)
  local thickness = max(1, T.px(1))
  for i = 1, count do
    local info = forced[i]
    local position = info and info.position or ((i - 1) / (count - 1))
    local major = info ~= nil or i == 1 or i == count or ((i - 1) % 5 == 0)
    local h = major and axis.h or max(1, floor(axis.h * 0.55))
    local centerX = axis.x + floor(axis.w * position + 0.5)
    local x = max(axis.x, min(axis.x + axis.w - thickness,
                              centerX - floor(thickness / 2)))
    local rect = lvgl.rectangle{
      x = x, y = axis.y + axis.h - h, w = thickness, h = h,
      color = widget.barPalette.track, opacity = T.opacity.rail,
      filled = 1, rounded = major and 1 or 0,
    }
    local cell = appendCell(cells, rect, { rect }, position,
      roleAt(bands, position), major and "major" or "minor")
    cell.major, cell.centerX = major, centerX
    cell.thresholdRole = info and info.role or nil
  end
  widget.ui.fill = cells[1] and cells[1].primary or nil
  widget.ui.activation = "points"
  return true
end

local function stepsBuild(widget, _geometry, style)
  local axis, cells, bands = beginSegmented(widget, style, "steps")
  local gap = gapPixels(style)
  local geometryCap = max(5, floor((axis.w + gap) / (T.px(4) + gap)))
  local count = budgetedCount(widget, style, 32, 1, 5, 10, geometryCap)
  local bottom = axis.y + axis.h
  for i = 1, count do
    local x, w = slotGeometry(axis, i, count, gap)
    local h = floor((axis.h - 1) * (i - 1) / max(1, count - 1)) + 1
    local position = (i - 0.5) / count
    local rect = lvgl.rectangle{
      x = x, y = bottom - h, w = w, h = h,
      color = widget.barPalette.track, opacity = T.opacity.rail,
      filled = 1, rounded = min(T.px(2), floor(w / 3)),
    }
    appendCell(cells, rect, { rect }, position,
               roleAt(bands, position), "step")
  end
  widget.ui.fill = cells[1] and cells[1].primary or nil
  widget.ui.activation = "steps"
  return true
end

local function descriptor(name, targetLow, targetHigh, hardCeiling, estimate)
  return {
    name = name,
    implemented = false,
    targetObjects = { targetLow, targetHigh },
    hardCeiling = hardCeiling,
    supports = unavailableSupports,
    estimateObjects = estimate,
    build = unavailableBuild,
    buildOverlay = unavailableBuild,
    update = unavailableUpdate,
    applyPalette = unavailablePalette,
    setVisible = unavailableVisible,
    ownsAlerts = false,
  }
end

local REGISTRY = {
  continuous = descriptor("continuous", 12, 38, 38, continuousEstimate),
  blocks = descriptor("blocks", 16, 32, 38,
    function(_profile, config) return min(config.segments or 10, 24) + 12 end),
  hex = descriptor("hex", 22, 35, 40,
    function(_profile, config) return min(config.segments or 8, 10) * 3 + 10 end),
  ticks = descriptor("ticks", 18, 34, 40,
    function(_profile, config) return min(config.segments or 20, 28) + 12 end),
  steps = descriptor("steps", 12, 24, 32,
    function(_profile, config) return min(config.segments or 8, 10) + 12 end),
  ["dual-rail"] = descriptor("dual-rail", 16, 28, 36,
    function() return 18 end),
}

local continuous = REGISTRY.continuous
continuous.variantCeilings = { solid = 24, gradient = 38 }
continuous.implemented = true
continuous.supports = continuousSupports
continuous.build = continuousBuild
continuous.buildOverlay = continuousBuildOverlay
continuous.update = continuousUpdate
continuous.applyPalette = continuousPalette
continuous.setVisible = continuousVisible

local function installSegmented(face, build)
  face.implemented = true
  face.supports = segmentedSupports
  face.build = build
  face.buildOverlay = segmentedBuildOverlay
  face.update = segmentedUpdate
  face.applyPalette = segmentedPalette
  face.setVisible = segmentedVisible
end

installSegmented(REGISTRY.blocks, blocksBuild)
installSegmented(REGISTRY.hex, hexBuild)
installSegmented(REGISTRY.ticks, ticksBuild)
installSegmented(REGISTRY.steps, stepsBuild)

M.REGISTRY = REGISTRY
M.ORDER = { "continuous", "blocks", "hex", "ticks", "steps", "dual-rail" }

-- Selecting a later-phase face during this milestone is safe and
-- explicit: the requested face remains in barVisual/signatures, while the
-- retained Continuous adapter draws the production fallback.
function M.select(name, profile, config)
  local requested = REGISTRY[name]
  if requested and requested.supports(profile, config) then
    return requested, nil
  end
  if requested and requested.implemented and config and config.direction
     and config.direction ~= "horizontal" then
    return continuous, "orientation-phase-pending:" .. tostring(config.direction)
  end
  if requested and requested.implemented and config and config.origin
     and config.origin ~= "scale-low" then
    return continuous, "origin-phase-pending:" .. tostring(config.origin)
  end
  return continuous, "face-phase-pending:" .. tostring(name or "unknown")
end

-- Allocate the shared face input once at build. Ordinary refresh only edits
-- scalar fields and the existing threshold array.
function M.buildRenderState(widget)
  local state = {
    valid = false, availability = "unset", state = "muted",
    rawValue = nil, smoothValue = nil, rawNormalized = 0,
    smoothNormalized = 0, minNormalized = nil, maxNormalized = nil,
    colorKey = "muted", opacity = T.opacity.muted, thresholds = {},
  }
  for i = 1, #widget.ranges do
    local range = widget.ranges[i]
    state.thresholds[i] = {
      role = range.role,
      fromPosition = G.normalize(range.from, widget.config.min,
                                 widget.config.max),
      toPosition = G.normalize(range.to, widget.config.min, widget.config.max),
      position = G.normalize(range.to, widget.config.min, widget.config.max),
    }
  end
  widget.barRenderState = state
  return state
end

function M.updateRenderState(widget)
  local state = widget.barRenderState
  local data, cfg, frame = widget.data, widget.config, widget.frame
  state.availability = data.availability
  state.state = R.stateKey(widget)
  state.colorKey = R.colorKey(widget)
  state.opacity = (state.colorKey == "muted") and T.opacity.muted
                  or T.opacity.full
  state.rawValue = data.displayValue
  state.valid = data.availability == "valid" and data.displayValue ~= nil
  if not state.valid then
    widget.smooth.value = nil
    state.smoothValue = nil
    state.rawNormalized, state.smoothNormalized = 0, 0
  else
    if frame.prevAvail ~= "valid" then widget.smooth.value = nil end
    state.smoothValue = widget.mods.smoothing.step(widget, data.displayValue)
    state.rawNormalized = G.normalize(data.displayValue, cfg.min, cfg.max)
    state.smoothNormalized = G.normalize(state.smoothValue, cfg.min, cfg.max)
  end
  local history = widget.history
  state.minNormalized = history.min
    and G.normalize(history.min, cfg.min, cfg.max) or nil
  state.maxNormalized = history.max
    and G.normalize(history.max, cfg.min, cfg.max) or nil
  return state
end

return M
