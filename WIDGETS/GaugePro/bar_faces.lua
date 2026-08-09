---- #########################################################################
---- #                                                                       #
---- # Gauge Pro - retained bar face contract                                #
---- #                                                                       #
---- # Face code receives normalized render state. It never reads sensors,   #
---- # classifies alerts, owns labels/badges/history, or creates objects in  #
---- # update(). Phase 1 ships the Continuous adapter; later faces already   #
---- # have explicit capability and budget contracts and fall back safely.   #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

local T, G, R
local max = math.max

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

local function continuousEstimate()
  return 2
end

local function continuousBuild(widget, _geometry, _style)
  local L, ui = widget.layout, widget.ui
  local b = L.bar
  local palette = widget.barPalette
  ui.track = lvgl.rectangle{
    x = b.x, y = b.y, w = b.w, h = b.h,
    color = (palette and palette.track) or T.color.rail,
    filled = 1, rounded = L.barRadius, opacity = T.opacity.rail,
  }
  -- The fill is deliberately second. Shared threshold/history overlays are
  -- created by bar.lua afterwards and therefore stay above it.
  ui.fill = lvgl.rectangle{
    x = b.x, y = b.y, w = 1, h = b.h,
    color = (palette and palette.normal) or T.color.accent,
    filled = 1, rounded = L.barRadius,
  }
  return true
end

local function continuousUpdate(widget, objects, state)
  local frame = widget.frame
  if not state.valid then
    if frame.fillW ~= 0 then
      frame.fillW = 0
      R.setProp(widget, objects.fill, "w", 1)
    end
    return
  end
  local w = max(G.barFill(widget.layout.bar.w, state.smoothValue,
                          widget.config.min, widget.config.max), 1)
  if w ~= frame.fillW then
    frame.fillW = w
    R.setProp(widget, objects.fill, "w", w)
  end
end

local function continuousPalette(widget, objects, palette, state)
  if state.paletteChanged then
    R.setProp(widget, objects.track, "color", palette.track)
  end
  R.setProp(widget, objects.fill, "color",
            R.resolveColor(widget, state.colorKey, palette))
  R.setProp(widget, objects.fill, "opacity", state.opacity)
end

local function continuousVisible(objects, visible)
  local fn = visible and lvgl.show or lvgl.hide
  fn(objects.track)
  fn(objects.fill)
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
    update = unavailableUpdate,
    applyPalette = unavailablePalette,
    setVisible = unavailableVisible,
    ownsAlerts = false,
  }
end

local REGISTRY = {
  continuous = descriptor("continuous", 12, 18, 24, continuousEstimate),
  blocks = descriptor("blocks", 16, 32, 38,
    function(_profile, config) return (config.segments or 10) + 8 end),
  hex = descriptor("hex", 22, 35, 40,
    function(_profile, config) return (config.segments or 8) * 3 + 8 end),
  ticks = descriptor("ticks", 18, 34, 40,
    function(_profile, config) return (config.segments or 16) + 8 end),
  steps = descriptor("steps", 12, 24, 32,
    function(_profile, config) return (config.segments or 8) + 8 end),
  ["dual-rail"] = descriptor("dual-rail", 16, 28, 36,
    function() return 18 end),
}

local continuous = REGISTRY.continuous
continuous.implemented = true
continuous.supports = continuousSupports
continuous.build = continuousBuild
continuous.update = continuousUpdate
continuous.applyPalette = continuousPalette
continuous.setVisible = continuousVisible

M.REGISTRY = REGISTRY
M.ORDER = { "continuous", "blocks", "hex", "ticks", "steps", "dual-rail" }

-- Selecting a Phase-2+ face during this architecture milestone is safe and
-- explicit: the requested face remains in barVisual/signatures, while the
-- retained Continuous adapter draws the production fallback.
function M.select(name, profile, config)
  local requested = REGISTRY[name]
  if requested and requested.supports(profile, config) then
    return requested, nil
  end
  if name == "continuous" and config and config.direction
     and config.direction ~= "horizontal" then
    return continuous, "orientation-phase-pending:" .. tostring(config.direction)
  end
  if name == "continuous" and config and config.origin
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
