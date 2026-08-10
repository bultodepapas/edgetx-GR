---- #########################################################################
---- #                                                                       #
---- # Gauge Pro - lifecycle                                                  #
---- #                                                                       #
---- # Loaded by main.lua on first use (the official Value2 pattern), so a   #
---- # radio that never places this widget pays only for main.lua at boot.   #
---- #                                                                       #
---- # create()  - state tables + module loading                             #
---- # update()  - options -> config -> ranges -> layout; rebuilds the LVGL  #
---- #             tree only when the structural signature changed           #
---- # refresh() - read telemetry, run alerts, update properties             #
---- #                                                                       #
---- # background() is deliberately absent: the firmware only calls it while #
---- # the widget is OFF screen, so all data maintenance lives in refresh(). #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local DEFS = ...

local M = {}

local MODULES = {
  "theme", "geometry", "format", "options", "ranges", "presets",
  "smoothing", "telemetry", "layout", "renderer", "bar_style",
  "bar_faces", "bar", "alerts",
}

local SCALE_AUTO = 1
local BATTERY_OFF = 1

-- The module table is SHARED by every widget instance: the modules are pure
-- (all per-widget state lives in the `widget` table), the setup() calls are
-- idempotent, and theme's metric caches are exactly what should be shared
-- across instances. main.lua also memoizes app.lua itself, so one screen
-- with four gauges loads 15 chunks once instead of 60 (AUDIT.md P2-3).
-- Keyed by path so two differently-located copies of the widget stay
-- independent.
local MODS_BY_PATH = {}

local function loadModules(path)
  local mods = MODS_BY_PATH[path]
  if mods then return mods end
  mods = {}
  MODS_BY_PATH[path] = mods
  for i = 1, #MODULES do
    local name = MODULES[i]
    local chunk, err = loadScript(path .. name .. ".lua", "bt")
    if not chunk then
      error("GaugePro: cannot load " .. name .. " (" .. tostring(err) .. ")")
    end
    local ok, mod = pcall(chunk)
    if not ok or type(mod) ~= "table" then
      error("GaugePro: bad module " .. name .. " (" .. tostring(mod) .. ")")
    end
    mods[name] = mod
  end
  mods.layout.setup(mods.theme, mods.geometry, mods.format)
  mods.renderer.setup(mods.theme, mods.geometry, mods.format)
  mods.bar_style.setup(mods.theme, mods.presets)
  mods.bar_faces.setup(mods.theme, mods.geometry, mods.renderer)
  mods.bar.setup(mods.theme, mods.geometry, mods.format, mods.renderer,
                 mods.bar_faces)
  return mods
end

function M.create(zone, options, path)
  local widget = {
    zone = zone,
    options = options,
    path = path or "/WIDGETS/GaugePro/",
    defs = DEFS,
    mods = loadModules(path or "/WIDGETS/GaugePro/"),
    -- `gen` counts REAL resolutions of the source (telemetry.resolveSource);
    -- configure() stamps widget.sourceGen with it so refresh() can spot a
    -- source that resolved after the last configure.
    source = { id = -1, resolved = false, name = "", unitName = "", gen = 0 },
    data = { availability = "unset" },
    history = {},
    smooth = {},
    alert = {},
    ui = {},
    frame = { props = {} },
    unitText = "",
    nameText = "",
  }
  return widget
end

-- Which renderer draws this layout.
local function painter(widget)
  return (widget.layout.style == "bar") and widget.mods.bar
      or widget.mods.renderer
end
M.painter = painter

-- Ranges, derived text and layout. Called from update(), and from refresh()
-- through the two one-shot latches there: the frame a battery pack's cell
-- count becomes known, and the frame a late-arriving sensor finally resolves.
local function configure(widget)
  local m, cfg, src = widget.mods, widget.config, widget.source

  -- Everything below is DERIVED from `src`. Record which resolution of the
  -- source it was derived from, so refresh() can tell when a late-resolving
  -- sensor has left it stale (telemetry.resolveSource bumps src.gen).
  widget.sourceGen = src.gen

  -- scale: Auto uses a known-sensor preset, Manual always uses the user
  -- values. On firmware without the Scale option (2.11, ten slots) Auto keeps
  -- the original behaviour: presets apply only while the ranges are untouched.
  local auto
  if widget.hasScaleOption then
    auto = (cfg.scale == SCALE_AUTO)
  else
    auto = (cfg.rawMin == 0 and cfg.rawMax == 100 and cfg.rawWarn == 55
            and cfg.rawCrit == 35)
  end

  local minimum, maximum = cfg.rawMin, cfg.rawMax
  local warning, critical = cfg.rawWarn, cfg.rawCrit
  local highGood = cfg.highGood
  local precision = cfg.precision

  -- F-12: autoCells is auto-branch state and must default FALSE - the old
  -- code only wrote it inside the auto branch, so switching Auto -> Manual
  -- (or -> Battery) left a stale latch lying around (Tanda 6 F-12).
  widget.autoCells = false

  if cfg.battery ~= BATTERY_OFF then
    -- state of charge: the scale is always a percentage
    minimum, maximum, warning, critical, highGood = 0, 100, 30, 15, true
    precision = 0
  elseif auto then
    local preset = m.presets.find(src)
    widget.autoCells = (preset ~= nil) and preset.battery or false
    if preset then
      minimum, maximum = preset.minimum, preset.maximum
      warning, critical = preset.warning, preset.critical
      highGood = preset.highIsGood
      -- a pack voltage scale only means something once the cell count is
      -- known; until then keep the single-cell preset. And only for a
      -- reading that IS the pack total: a `cellsTable` source (Cels) showing
      -- Lowest or Average is still single-cell magnitude no matter how many
      -- cells were detected - rescaling it to the pack range would clamp it
      -- permanently near the bottom of the dial (AUDIT.md P1-6).
      local wantsPackRange = not preset.cellsTable
        or cfg.cells == m.telemetry.CELLS_TOTAL
      if preset.battery and src.cells and src.cells > 1 and wantsPackRange then
        local pack = m.presets.packRange(src.cells, "lipo")
        minimum, maximum = pack.minimum, pack.maximum
        warning, critical = pack.warning, pack.critical
        highGood = pack.highIsGood
      end
    end
  end

  -- When BOTH thresholds are out of the effective range on the same side,
  -- building the bands from them would turn the whole dial critical with
  -- zero-width warning/normal bands (e.g. a manual -120..0 dBm scale with
  -- the 0..100 defaults). Derive them at the presets' proportions instead
  -- (AUDIT.md G-4).
  warning, critical = m.ranges.saneThresholds(minimum, maximum, warning,
                                              critical, highGood)
  cfg.min, cfg.max, cfg.warn, cfg.crit = minimum, maximum, warning, critical
  cfg.highGood = highGood

  -- precision: Auto (1) follows the sensor, else the chosen decimal count
  if cfg.precisionChoice > 1 then
    precision = cfg.precisionChoice - 2
  elseif cfg.battery == BATTERY_OFF then
    precision = src.prec or 0
    if src.name == "tx-voltage" then precision = 1 end
  end
  cfg.precision = precision

  -- displayed strings
  if cfg.suffix and cfg.suffix ~= "" then
    widget.unitText = cfg.suffix
  elseif cfg.battery ~= BATTERY_OFF then
    widget.unitText = "%"
  else
    widget.unitText = src.unitName or ""
  end
  widget.nameText = (cfg.label and cfg.label ~= "") and cfg.label
                    or (src.name or "")

  widget.ranges = m.ranges.build(cfg.min, cfg.max, cfg.warn, cfg.crit,
                                 cfg.highGood)
  widget.deadband = m.ranges.deadband(cfg.min, cfg.max)

  local rangeSig = table.concat({ cfg.min, cfg.max, cfg.warn, cfg.crit,
                                  cfg.highGood and 1 or 0, cfg.precision }, ":")
  -- Battery mode and the Cells aggregation mode change which UNIT the
  -- displayed value is in without necessarily changing cfg.min/max (e.g.
  -- Lowest -> Total on a Cels source keeps the same pack-range scale), so
  -- rangeSig alone would miss it and leave stale per-cell-volt history mixed
  -- with pack-total readings (AUDIT.md P0-7).
  local historySig = tostring(cfg.battery) .. ":" .. tostring(cfg.cells)
  if rangeSig ~= widget.rangeSig or historySig ~= widget.historySig then
    widget.rangeSig = rangeSig
    widget.historySig = historySig
    m.telemetry.resetHistory(widget)
    m.smoothing.reset(widget)
  end

  local L = m.layout.calculate(widget, cfg)
  -- Resolve bar appearance from immutable stored config only when the active
  -- layout can consume it. A dial ignores every bar-only option, so it should
  -- not pay RGB analysis/cache-signature cost during configure either.
  if L.style == "bar" then
    widget.barVisual, widget.barPalette = m.bar_style.resolve(widget, cfg)
    m.layout.applyBarVisual(L, widget.barVisual, cfg)
  else
    widget.barVisual, widget.barPalette = nil, nil
  end
  widget.layout = L
  -- rangeSig is included so a range edit (min/max/warn/crit/precision, or the
  -- battery cell latch) rebuilds everything derived from it at BUILD time:
  -- section/rail arcs, bar threshold marks, scale end labels (AUDIT.md P0-2).
  local sig = m.layout.signature(L, cfg) .. ":" .. widget.unitText
    .. ":" .. widget.rangeSig
  if L.style == "bar" then
    sig = sig .. ":" .. widget.barVisual.structuralSig
  end
  if sig ~= widget.layoutSig then
    widget.layoutSig = sig
    widget.layoutRebuilt = true
    lvgl.clear()
    widget.ui = {}
    widget.frame = { props = {}, dirty = {} }
    painter(widget).build(widget)
  end
end
M.configure = configure

-- configure() PLUS the cheap delta path for text a rebuild did not repaint.
-- Every caller needs both halves: a signature change rebuilds the tree and
-- paints the current strings itself, but a config change that leaves the
-- signature alone - a Name/Suffix edit, or a source whose unit is empty -
-- only reaches the screen through updateSourceLabels (AUDIT.md P0-6).
-- Splitting the two across call sites is what let the late-resolution path
-- draw an unnamed, unitless gauge.
local function apply(widget)
  widget.layoutRebuilt = false
  configure(widget)
  -- setProp() no-ops when the string is unchanged, so this is free on the
  -- common "nothing moved" call.
  if not widget.layoutRebuilt then
    painter(widget).updateSourceLabels(widget)
  end
end
M.apply = apply

function M.update(widget, options)
  if not widget.mods then return end
  widget.options = options
  local m = widget.mods

  widget.hasScaleOption = (options.Scale ~= nil)
  local cfg = m.options.parse(DEFS, options)
  -- keep the authored values: configure() writes the *effective* scale into
  -- cfg.min/max, and the Auto heuristic must keep seeing what the user set
  cfg.rawMin, cfg.rawMax = cfg.min, cfg.max
  cfg.rawWarn, cfg.rawCrit = cfg.warn, cfg.crit
  cfg.precisionChoice = cfg.precision
  cfg.tau = m.smoothing.tau(cfg.damping)
  widget.config = cfg
  widget.accent = (cfg.accent and cfg.accent ~= 0) and cfg.accent or nil

  local prevId = widget.source.id
  local src = m.telemetry.resolveSource(widget)
  if src.id ~= prevId then
    widget.data.lastValue = nil   -- never show a new source's old data
    widget.data.state = nil
    src.cells = nil
    widget.cellsApplied = nil   -- let the NEW source's cell count re-latch
    m.telemetry.resetHistory(widget)
    m.smoothing.reset(widget)
    m.alerts.reset(widget)
  end

  apply(widget)
end

-- A SWITCH option is a swsrc_t, read with getSwitchValue() (AUDIT.md P0-1),
-- never getValue(). Unlike the alert switch, a misread here must NOT trigger
-- a reset, so any failure to read leaves resetArmed unchanged (no edge).
local function checkResetSwitch(widget)
  local sw = widget.config.resetSw
  if not sw or sw == 0 then return end
  if type(getSwitchValue) ~= "function" then return end
  local ok, value = pcall(getSwitchValue, sw)
  if not ok then return end
  local active = (value == true)
  if active and not widget.resetArmed then
    local idx = widget.source.sensorIndex
    if idx and type(model) == "table" and type(model.resetSensor) == "function" then
      -- For a real telemetry sensor, resetHistory() alone is undone within
      -- THIS SAME refresh(): telemetry.refresh() calls readHistorySiblings()
      -- right after, which reads the radio's own <name>-/<name>+ sources
      -- straight back, unreset (AUDIT.md P1-8). model.resetSensor() is the
      -- same primitive the official "Reset telemetry" action uses.
      model.resetSensor(idx)
    end
    widget.mods.telemetry.resetHistory(widget)
  end
  widget.resetArmed = active
end

function M.refresh(widget, _event, _touch)
  if not widget.mods or not widget.ui.built then return end
  local m = widget.mods
  checkResetSwitch(widget)
  m.telemetry.refresh(widget)

  -- Two things can invalidate the derived config from inside a frame. At most
  -- ONE of them is applied per refresh: apply() costs a full configure (~8k
  -- VM instructions on a large dial) against a 20000-instruction per-callback
  -- budget (lua_widget.cpp MAX_INSTRUCTIONS), and doing both in one frame
  -- would put two rebuilds in a single callback. Whichever does not fire this
  -- frame fires on the next one - both are one-shot latches.
  if widget.source.gen ~= widget.sourceGen then
    -- The source resolved LATE: it was absent when the widget was created (a
    -- fresh model, after "delete all sensors", a new RX) and the throttled
    -- retry in telemetry.refresh has just found it. resolveSource fills
    -- widget.source, but everything DERIVED from it - unit text, name, the
    -- Auto preset scale, precision, the layout - comes from configure(),
    -- which otherwise only runs from update(). The firmware calls update()
    -- "when the widget options have changed" (widget.h:109), not on a timer,
    -- so without this an RPM sensor discovered a second after boot kept
    -- drawing on the default 0..100 scale, nameless and unitless, until the
    -- user happened to edit an option.
    apply(widget)
  elseif widget.config.battery == BATTERY_OFF and widget.source.cells
         and not widget.cellsApplied then
    -- a battery pack's cell count is only known after the first reading; when
    -- it lands, the scale is rebuilt once
    widget.cellsApplied = true
    apply(widget)
  end

  -- EdgeTX/HTX does not guarantee widget.update() for a live theme switch.
  -- The resolver therefore probes the small resolved-role signature at most
  -- once per second and swaps only the palette table. bar.update() detects its
  -- signature and recolors the existing tree in this same refresh.
  if widget.layout.style == "bar" then
    m.bar_style.refreshPalette(widget, widget.config)
  end

  m.alerts.update(widget)
  painter(widget).update(widget)
end

return M
