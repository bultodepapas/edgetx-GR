---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - responsive analog-digital telemetry widget                 #
---- #                                                                       #
---- # LVGL-only Lua widget for EdgeTX 2.11+ (developed against 3.0).        #
---- # Modules are loaded from the widget folder with loadScript().          #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local options = {
  { "Source", 1, 0 },
  { "Min", 0, 0, -10000, 10000 },
  { "Max", 0, 100, -10000, 10000 },
  { "Warn", 0, 55, -10000, 10000 },
  { "Crit", 0, 35, -10000, 10000 },
  { "HighGood", 2, 1 },
  { "Style", 9, 0, { "Auto", "Needle", "Arc" } },
  { "ColorMode", 9, 1, { "Static", "Threshold", "Sections" } },
  { "Precision", 9, 0, { "0", "1", "2" } },
  { "ShowMinMax", 2, 1 },
}

local STYLE_CHOICES = { "Auto", "Needle", "Arc" }
local COLOR_CHOICES = { "Static", "Threshold", "Sections" }

local function choiceIndex(value, choices)
  for i = 1, #choices do
    if choices[i] == value then return i - 1 end
  end
  return 0
end

local function isDefaultConfig(cfg)
  return cfg.min == 0 and cfg.max == 100 and cfg.warn == 55 and cfg.crit == 35
end

local function loadModule(widget, name)
  local chunk, err = loadScript(widget.path .. name .. ".lua", "bt")
  if not chunk then
    error("GaugeV2: cannot load " .. name .. " (" .. tostring(err) .. ")")
  end
  local ok, mod = pcall(chunk)
  if not ok or type(mod) ~= "table" then
    error("GaugeV2: bad module " .. name)
  end
  return mod
end

local function create(zone, options, path)
  if not lvgl then
    error("GaugeV2 requires EdgeTX 2.11+ (LVGL)")
  end
  local widget = {
    zone = zone,
    options = options,
    path = path or "/WIDGETS/GaugeV2/",
    mods = {},
    source = { id = -1, name = "", unit = nil, unitName = "",
               isTelemetry = false, resolved = false },
    data = { availability = "unset", value = nil, displayValue = nil,
             lastValue = nil, state = nil },
    history = { min = nil, max = nil },
    smooth = { value = nil, time = 0 },
    ranges = nil,
    rangeSig = nil,
    config = nil,
    layout = nil,
    layoutSig = nil,
    ui = {},
    frame = {},
  }
  widget.mods.geometry = loadModule(widget, "geometry")
  widget.mods.ranges = loadModule(widget, "ranges")
  widget.mods.presets = loadModule(widget, "presets")
  widget.mods.telemetry = loadModule(widget, "telemetry")
  widget.mods.layout = loadModule(widget, "layout")
  widget.mods.renderer = loadModule(widget, "renderer")
  widget.mods.renderer.setup(widget.mods.geometry)
  return widget
end

local function update(widget, options)
  if not widget.mods then return end
  widget.options = options
  local mods = widget.mods

  local cfg = {
    min = options.Min,
    max = options.Max,
    warn = options.Warn,
    crit = options.Crit,
    highGood = options.HighGood == 1,
    style = choiceIndex(options.Style, STYLE_CHOICES),
    colorMode = choiceIndex(options.ColorMode, COLOR_CHOICES),
    precision = tonumber(options.Precision) or 0,
    showMinMax = options.ShowMinMax == 1,
  }

  -- Source resolution is cached in telemetry.resolveSource. Presets apply
  -- when the source changed and the range options still hold their global
  -- defaults; the applied values are kept so later updates (resize,
  -- fullscreen, settings screen visits) do not revert to the defaults.
  local prevId = widget.source.id
  local src = mods.telemetry.resolveSource(widget)
  if isDefaultConfig(cfg) then
    if widget.preset and widget.presetSourceId == src.id then
      local p = widget.preset
      cfg.min = p.minimum
      cfg.max = p.maximum
      cfg.warn = p.warning
      cfg.crit = p.critical
      cfg.highGood = p.highIsGood
    elseif src.id ~= prevId then
      local p = mods.presets.find(src)
      if p then
        widget.preset = { minimum = p.minimum, maximum = p.maximum,
                          warning = p.warning, critical = p.critical,
                          highIsGood = p.highIsGood }
        widget.presetSourceId = src.id
        cfg.min = p.minimum
        cfg.max = p.maximum
        cfg.warn = p.warning
        cfg.crit = p.critical
        cfg.highGood = p.highIsGood
      end
    end
  else
    -- user customized the ranges: no preset may interfere
    widget.preset = nil
    widget.presetSourceId = nil
  end
  if src.id ~= prevId then
    widget.smooth.value = nil
    widget.history.min = nil
    widget.history.max = nil
    widget.data.lastValue = nil  -- never show old source data with a new source
  end
  widget.config = cfg
  widget.ranges = mods.ranges.build(cfg.min, cfg.max, cfg.warn, cfg.crit,
                                    cfg.highGood)

  local rangeSig = table.concat(
    { cfg.min, cfg.max, cfg.warn, cfg.crit, cfg.highGood and 1 or 0 }, ":")
  if rangeSig ~= widget.rangeSig then
    widget.rangeSig = rangeSig
    widget.history.min = nil
    widget.history.max = nil
    widget.smooth.value = nil
  end

  -- Rebuild only when the layout structure actually changed.
  local L = mods.layout.calculate(widget, cfg)
  widget.layout = L
  local sig = table.concat(
    { L.mode, L.orientation, L.showNeedle and 1 or 0, cfg.colorMode,
      cfg.showMinMax and 1 or 0 }, ":")
  if sig ~= widget.layoutSig then
    widget.layoutSig = sig
    lvgl.clear()
    widget.ui = {}
    mods.renderer.build(widget)
  elseif src.id ~= prevId then
    mods.renderer.updateSourceLabels(widget)
  end
end

local function refresh(widget, event, touch)
  if not widget.mods or not widget.ui.built then return end
  widget.mods.telemetry.refresh(widget)
  widget.mods.renderer.update(widget)
end

local function background(widget)
  if not widget.mods then return end
  local data = widget.data
  if data.availability == "valid" and data.value ~= nil then
    local h = widget.history
    if h.min == nil then
      h.min = data.value
      h.max = data.value
    else
      if data.value < h.min then h.min = data.value end
      if data.value > h.max then h.max = data.value end
    end
  end
end

return {
  name = "GaugeV2",
  options = options,
  create = create,
  update = update,
  refresh = refresh,
  background = background,
  useLvgl = true,
}
