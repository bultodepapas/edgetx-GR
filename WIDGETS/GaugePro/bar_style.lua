---- #########################################################################
---- #                                                                       #
---- # Gauge Pro - bar personalization resolver                              #
---- #                                                                       #
---- # Stored options are inputs, never working state. This module resolves  #
---- # preset -> explicit override -> responsive compact variant into a      #
---- # per-widget visual contract and a runtime theme-aware palette.         #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local T, SENSOR_PRESETS
local min, max = math.min, math.max

function M.setup(theme, presets)
  T, SENSOR_PRESETS = theme, presets
end

-- Appearance presets are deliberately data, not branches scattered through
-- renderers. `compact` documents the predictable small-zone downgrade.
local PRESETS = {
  [1] = {
    key = "auto-source", label = "Auto Source", sourceAware = true,
    face = "continuous", palette = "classic", direction = "auto",
    origin = "scale-low", thickness = "medium", ends = "round",
    segments = 10, gap = "normal", surface = "transparent",
    contrast = "auto", motion = "refined",
    compact = "source face with reduced detail",
  },
  [2] = {
    key = "classic-rail", label = "Classic Rail",
    face = "continuous", palette = "classic", direction = "auto",
    origin = "scale-low", thickness = "medium", ends = "round",
    segments = 10, gap = "normal", surface = "transparent",
    contrast = "auto", motion = "refined",
    compact = "continuous medium rail",
  },
  [3] = {
    key = "theme-clean", label = "Theme Clean",
    face = "continuous", palette = "theme", direction = "auto",
    origin = "scale-low", thickness = "thin", ends = "round",
    segments = 10, gap = "tight", surface = "theme-panel",
    contrast = "auto", motion = "essential",
    compact = "thin continuous line without panel",
  },
  [4] = {
    key = "hex-telemetry", label = "Hex Telemetry",
    face = "hex", palette = "classic", direction = "auto",
    origin = "scale-low", thickness = "medium", ends = "chamfer",
    segments = 8, gap = "normal", surface = "theme-panel",
    contrast = "auto", motion = "refined",
    compact = "six chamfered cells",
  },
  [5] = {
    key = "status-blocks", label = "Status Blocks",
    face = "blocks", palette = "classic", direction = "auto",
    origin = "scale-low", thickness = "medium", ends = "square",
    segments = 10, gap = "normal", surface = "transparent",
    contrast = "auto", motion = "essential",
    compact = "six square blocks",
  },
  [6] = {
    key = "signal-ticks", label = "Signal Ticks",
    face = "ticks", palette = "theme", direction = "auto",
    origin = "scale-low", thickness = "medium", ends = "square",
    segments = 24, gap = "tight", surface = "transparent",
    contrast = "auto", motion = "refined",
    compact = "ten high-contrast ticks",
  },
  [7] = {
    key = "rc-center", label = "RC Center",
    face = "dual-rail", palette = "custom-two", direction = "auto",
    origin = "zero", thickness = "medium", ends = "round",
    segments = 10, gap = "normal", surface = "transparent",
    contrast = "auto", motion = "refined",
    compact = "zero-notch dual rail",
  },
  [8] = {
    key = "minimal-line", label = "Minimal Line",
    face = "continuous", palette = "theme", direction = "auto",
    origin = "scale-low", thickness = "thin", ends = "round",
    segments = 8, gap = "tight", surface = "transparent",
    contrast = "off", motion = "essential",
    compact = "one-pixel-equivalent theme line",
  },
  [9] = {
    key = "bold-data", label = "Bold Data",
    face = "continuous", palette = "classic", direction = "auto",
    origin = "scale-low", thickness = "thick", ends = "round",
    segments = 12, gap = "normal", surface = "theme-panel",
    contrast = "auto", motion = "refined",
    compact = "medium rail with external value",
  },
}
M.PRESETS = PRESETS

local FACE = { [2] = "continuous", [3] = "blocks", [4] = "hex",
               [5] = "ticks", [6] = "steps", [7] = "dual-rail" }
local DIRECTION = { [2] = "horizontal", [3] = "vertical" }
local ORIGIN = { [2] = "scale-low", [3] = "zero" }
local THICKNESS = { [2] = "thin", [3] = "medium", [4] = "thick",
                    [5] = "maximum" }
local ENDS = { [2] = "round", [3] = "square", [4] = "chamfer" }
local SEGMENTS = { [2] = 6, [3] = 8, [4] = 10, [5] = 12,
                   [6] = 16, [7] = 24 }
local GAP = { [2] = "tight", [3] = "normal", [4] = "wide" }
local PALETTE = { [2] = "classic", [3] = "theme", [4] = "custom-three",
                  [5] = "custom-two" }
local SURFACE = { [2] = "transparent", [3] = "theme-panel",
                  [4] = "custom" }
local CONTRAST = { [2] = "off", [3] = "strong" }

local function pick(index, values, inherited)
  return values[index] or inherited
end

local function zoneProfile(zone)
  local w = max(1, tonumber(zone and zone.w) or 1)
  local h = max(1, tonumber(zone and zone.h) or 1)
  local short = min(w, h)
  local family = "full"
  if h <= 45 or w <= 74 then family = "micro"
  elseif short <= 70 or w * h < 10000 then family = "compact" end
  return {
    w = w, h = h, ratio = w / h, family = family,
    compact = family ~= "full",
  }
end
M.zoneProfile = zoneProfile

local function autoDirection(profile)
  return (profile.ratio < 0.8) and "vertical" or "horizontal"
end

local function sourcePreset(kind)
  if kind == "signal" then return PRESETS[6] end
  if kind == "battery" or kind == "capacity" then return PRESETS[4] end
  if kind == "control" then return PRESETS[7] end
  return PRESETS[2]
end

local function compactCount(face, count, profile)
  if not profile.compact then return count end
  local cap = (profile.family == "micro") and 6 or 10
  if face == "ticks" then cap = (profile.family == "micro") and 10 or 16 end
  return min(count, cap)
end

local function signature(parts)
  for i = 1, #parts do parts[i] = tostring(parts[i]) end
  return table.concat(parts, ":")
end

function M.configSignature(cfg)
  return signature{
    cfg.barPreset, cfg.barFace, cfg.barDir, cfg.barOrigin, cfg.barSize,
    cfg.barEnds, cfg.segments, cfg.segGap, cfg.palette, cfg.warnClr,
    cfg.critClr, cfg.trackClr, cfg.surface, cfg.panelClr, cfg.contrast,
  }
end

local function paletteFor(cfg, visual)
  local normal = cfg.accent or T.color.accent
  local warning, critical = T.color.warn, T.color.crit
  local mode = visual.palette

  if mode == "theme" then
    normal, warning = COLOR_THEME_ACTIVE, COLOR_THEME_WARNING
  elseif mode == "custom-three" then
    warning = cfg.warnClr or T.color.warn
    critical = cfg.critClr or T.color.crit
  elseif mode == "custom-two" then
    critical = cfg.critClr or T.color.crit
    warning = T.mixColor(critical, normal, 0.5)
  end

  local customSurface = visual.surface == "custom"
  local track = customSurface and (cfg.trackClr or T.color.rail) or T.color.rail
  local panel = customSurface and (cfg.panelClr or COLOR_THEME_SECONDARY3)
                or COLOR_THEME_SECONDARY3
  local palette = {
    mode = mode,
    normal = normal, warning = warning, critical = critical,
    track = track, panel = panel, border = COLOR_THEME_SECONDARY1,
    history = T.color.history, muted = T.color.muted,
    value = T.color.value, label = T.color.label,
    inkDark = T.color.inkDark, inkLite = T.color.inkLite,
  }
  palette.calibrated = mode == "classic" and normal == T.color.accent
    and warning == T.color.warn and critical == T.color.crit
  palette.signature = mode .. ":" .. T.colorSignature{
    normal, warning, critical, track, panel, palette.border,
    palette.history, palette.muted, palette.value, palette.label,
    palette.inkDark, palette.inkLite,
  }

  local nw = T.colorDistance(normal, warning)
  local wc = T.colorDistance(warning, critical)
  local nt = T.contrastRatio(normal, track)
  local wt = T.contrastRatio(warning, track)
  local ct = T.contrastRatio(critical, track)
  palette.analysis = {
    normalWarningDistance = nw,
    warningCriticalDistance = wc,
    normalTrackContrast = nt,
    warningTrackContrast = wt,
    criticalTrackContrast = ct,
  }
  palette.needsAssist = (nw and nw < 60) or (wc and wc < 60)
    or (nt and nt < 3) or (wt and wt < 3) or (ct and ct < 3) or false
  palette.assist = (visual.contrast == "strong") and "strong"
    or (visual.contrast == "off") and "off"
    or (palette.needsAssist and "needed" or "none")
  return palette
end

-- Resolve without writing to cfg or widget.options. The caller owns the two
-- returned per-instance tables; PRESETS and shared module state stay read-only.
function M.resolve(widget, cfg)
  assert(T, "GaugePro: bar_style.setup was not called")
  cfg = cfg or {}
  local profile = zoneProfile(widget and widget.zone)
  local selected = PRESETS[cfg.barPreset] or PRESETS[2]
  local hint = (SENSOR_PRESETS and SENSOR_PRESETS.kind)
    and SENSOR_PRESETS.kind(widget and widget.source) or "generic"
  local inherited = selected.sourceAware and sourcePreset(hint) or selected

  local visual = {
    preset = selected.key,
    inheritedPreset = inherited.key,
    sourceHint = hint,
    requestedFace = pick(cfg.barFace, FACE, inherited.face),
    direction = pick(cfg.barDir, DIRECTION, inherited.direction),
    origin = pick(cfg.barOrigin, ORIGIN, inherited.origin),
    thickness = pick(cfg.barSize, THICKNESS, inherited.thickness),
    ends = pick(cfg.barEnds, ENDS, inherited.ends),
    segments = pick(cfg.segments, SEGMENTS, inherited.segments),
    gap = pick(cfg.segGap, GAP, inherited.gap),
    palette = pick(cfg.palette, PALETTE, inherited.palette),
    surface = pick(cfg.surface, SURFACE, inherited.surface),
    contrast = pick(cfg.contrast, CONTRAST, inherited.contrast),
    motion = inherited.motion,
    compactDescription = inherited.compact,
    profile = profile,
    downgrades = {},
  }
  visual.face = visual.requestedFace
  if visual.direction == "auto" then visual.direction = autoDirection(profile) end

  if visual.face == "hex" and visual.segments > 10 then
    visual.segments = 10
    visual.downgrades[#visual.downgrades + 1] = "segments-object-budget"
  end
  local requestedCount = visual.segments
  visual.segments = compactCount(visual.face, visual.segments, profile)
  if visual.segments ~= requestedCount then
    visual.downgrades[#visual.downgrades + 1] = "segments-responsive"
  end
  if profile.family == "micro" and visual.surface ~= "transparent" then
    visual.surface = "transparent"
    visual.downgrades[#visual.downgrades + 1] = "surface-compact"
  end

  visual.configSig = M.configSignature(cfg)
  visual.structuralSig = signature{
    visual.face, visual.direction, visual.origin, visual.thickness,
    visual.ends, visual.segments, visual.gap, visual.surface, profile.family,
  }
  local palette = paletteFor(cfg, visual)
  visual.paletteSig = palette.signature
  return visual, palette
end

return M
