-- Headless smoke test for the GaugeV2 widget.
-- Runs the full create/update/refresh/background lifecycle against a mock
-- EdgeTX environment. Requires the mock firmware globals defined below.
--
-- Usage: lua5.3 smoke_test.lua <widget-dir> [scenario]

local widgetDir = arg[1] or "./"

local mock = dofile(widgetDir .. "tests/mock_env.lua")

-- ---- controllable firmware state -------------------------------------

local sim = {
  timeMs = 0,             -- getTime() returns 10 ms ticks on the radio
  rssi = 0,               -- getRSSI()
  sourceValues = {},      -- id -> value | table | nil
  sourceCurrent = {},     -- id -> isCurrent
  fieldInfo = {},         -- id -> {name=, unit=}
  sensors = {},           -- model.getSensor(i) -> {name=, prec=, unit=}
}

local function getTime()
  return sim.timeMs
end

local function getRSSI()
  return sim.rssi
end

local function getSourceValue(id)
  local v = sim.sourceValues[id]
  local current = sim.sourceCurrent[id]
  if v == nil then return nil end
  if current == nil then current = true end
  return v, current, current
end

local function getFieldInfo(id)
  if type(id) == "string" then
    for _, info in pairs(sim.fieldInfo) do
      if info.name == id then return info end
    end
    return nil
  end
  return sim.fieldInfo[id]
end

local model = {
  getSensor = function(i)
    return sim.sensors[i]
  end,
}

-- module loader: loadScript(path, mode) contract
local function loadScript(path)
  return loadfile(path)
end

-- install mocks + firmware globals into the current chunk's environment
local env = _ENV or _G
mock.install(env)
env.getTime = getTime
env.getRSSI = getRSSI
env.getSourceValue = getSourceValue
env.getFieldInfo = getFieldInfo
env.model = model
env.loadScript = loadScript

-- ---- test harness -----------------------------------------------------

local passed, failed = 0, 0

local function assertEq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label or "assertEq",
      tostring(expected), tostring(actual)), 2)
  end
end

local function assertTrue(cond, label)
  if not cond then
    error((label or "assertTrue") .. " failed", 2)
  end
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("PASS " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end

-- ---- scenarios ---------------------------------------------------------

local function newWidget(zone, options, path)
  local mod = dofile(widgetDir .. "main.lua")
  local widget = mod.create(zone, options, path)
  widget.mod = mod
  return widget
end

local TELEM_RSSI = 3072          -- telemetry id (any >= 3072 works in sim)
local LOCAL_STICK = 100          -- non-telemetry id

local function baseOptions(overrides)
  local o = {
    Source = TELEM_RSSI, Min = 0, Max = 100, Warn = 55, Crit = 35,
    HighGood = 1, Style = "Auto", ColorMode = "Threshold",
    Precision = "0", ShowMinMax = 1,
  }
  for k, v in pairs(overrides or {}) do o[k] = v end
  return o
end

local function setupSim()
  sim.timeMs = 0
  sim.rssi = 100
  sim.sourceValues = {}
  sim.sourceCurrent = {}
  sim.sensors = {}
  sim.fieldInfo = {
    [TELEM_RSSI] = { id = TELEM_RSSI, name = "RSSI", unit = 17 },
    [LOCAL_STICK] = { id = LOCAL_STICK, name = "Thr" },
  }
  sim.sourceValues[TELEM_RSSI] = 70
  sim.sourceCurrent[TELEM_RSSI] = true
end

-- 1. build + valid telemetry value
test("build and render valid value", function()
  setupSim()
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  assertTrue(widget.ui.built, "ui built")
  assertTrue(widget.ui.valueArc ~= nil, "valueArc exists")
  assertTrue(widget.ui.needle ~= nil, "needle exists in normal mode")
  assertEq(#widget.ui.ticks, 7, "large mode tick count")  -- 480x272 is large
  widget.mod.refresh(widget, nil, nil)
  local arc = widget.ui.valueArc
  assertEq(arc.props.endAngle, 324, "endAngle for value 70")  -- 135+0.7*270
  assertEq(widget.ui.valueLabel.props.text, "70", "value text")
  assertEq(widget.ui.nameLabel.props.text, "RSSI", "name text")
  assertEq(widget.ui.unitLabel.props.text, "dB", "unit text")
  assertEq(widget.ui.stateLabel.props.text, "", "no state label")
end)

-- 2. threshold state colors
test("critical state colors", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 30
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.data.state, "critical", "state")
  assertEq(widget.ui.valueArc.props.color, env.RED, "arc color")
  assertEq(widget.ui.stateLabel.props.text, "CRIT", "state text")
  assertEq(widget.ui.valueLabel.props.text, "30", "value text")
end)

-- 3. no-data behavior
test("no-data keeps last value, hides needle, dims arc", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 60
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)          -- valid: 60 recorded
  sim.sourceCurrent[TELEM_RSSI] = false        -- telemetry dies
  sim.timeMs = sim.timeMs + 100
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.data.availability, "stale", "availability")
  assertEq(widget.ui.valueLabel.props.text, "60", "retains last value")
  assertEq(widget.ui.stateLabel.props.text, "NO DATA", "state text")
  assertEq(widget.ui.needle.visible, false, "needle hidden")
  assertEq(widget.ui.valueArc.props.opacity, 96, "arc dimmed")
end)

-- 4. unavailable (no value at all)
test("unavailable source shows dash and no data", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = nil
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.data.availability, "unavailable", "availability")
  assertEq(widget.ui.valueLabel.props.text, "-", "dash")
  assertEq(widget.ui.stateLabel.props.text, "NO DATA", "state text")
end)

-- 5. unset source
test("unset source", function()
  setupSim()
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 },
    baseOptions({ Source = 0 }), widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.data.availability, "unset", "availability")
  assertEq(widget.ui.valueLabel.props.text, "-", "dash")
end)

-- 6. local source works without telemetry
test("local source valid without telemetry", function()
  setupSim()
  sim.sourceValues[LOCAL_STICK] = 50
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 },
    baseOptions({ Source = LOCAL_STICK, Min = -100, Max = 100 }),
    widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.data.availability, "valid", "local source stays valid")
  assertEq(widget.ui.valueLabel.props.text, "50", "value text")
end)

-- 7. table values aggregate (battery cells)
test("table value aggregation", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = { 3.7, 3.8, 3.9 }
  sim.fieldInfo[TELEM_RSSI] = { name = "Cels", unit = 1 }
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 },
    baseOptions({ Source = TELEM_RSSI, Min = 0, Max = 15, Warn = 12, Crit = 10 }),
    widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.data.value, 11.4, "aggregated total")
  assertEq(widget.ui.valueLabel.props.text, "11", "formatted total")
end)

-- 8. precision
test("precision formatting", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 70
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 },
    baseOptions({ Precision = "1" }), widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.ui.valueLabel.props.text, "70.0", "one decimal")
end)

-- 9. micro mode: arc-only, no needle, 3 ticks
test("micro mode layout", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 50
  local widget = newWidget({ x = 0, y = 0, w = 48, h = 48 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  assertEq(widget.layout.mode, "micro", "mode")
  assertEq(widget.ui.needle, nil, "no needle in micro")
  assertEq(widget.ui.unitLabel, nil, "no unit in micro")
  assertEq(#widget.ui.ticks, 3, "three ticks")
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.ui.valueArc.props.endAngle, 270, "half-scale angle")
end)

-- 10. resize rebuilds the UI
test("resize rebuilds", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 50
  local zone = { x = 0, y = 0, w = 480, h = 272 }
  local widget = newWidget(zone, baseOptions(), widgetDir)
  widget.mod.update(widget, widget.options)
  local firstArc = widget.ui.valueArc
  zone.w, zone.h = 120, 120
  widget.mod.update(widget, widget.options)
  assertTrue(widget.ui.valueArc ~= firstArc, "new arc object after resize")
  assertEq(widget.layout.mode, "normal", "mode after resize")
end)

-- 11. sections color mode builds three track arcs
test("sections mode track arcs", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 70
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 },
    baseOptions({ ColorMode = "Sections" }), widgetDir)
  widget.mod.update(widget, widget.options)
  assertEq(#widget.ui.track, 3, "three section arcs")
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.ui.valueArc.props.color, env.COLOR_THEME_PRIMARY1,
    "normal state color")
end)

-- 12. arc style never shows a needle
test("arc style has no needle", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 70
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 },
    baseOptions({ Style = "Arc" }), widgetDir)
  widget.mod.update(widget, widget.options)
  assertEq(widget.ui.needle, nil, "no needle in arc style")
end)

-- 13. preset defaults applied on source change
test("preset applies defaults", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 45
  sim.fieldInfo[TELEM_RSSI] = { name = "Temp", unit = 11 }
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  -- Temp preset: 0..120, warn 70, crit 90, low-is-good
  assertEq(widget.config.min, 0, "preset min")
  assertEq(widget.config.max, 120, "preset max")
  assertEq(widget.config.highGood, false, "preset direction")
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.data.state, "normal", "45 of 120 is normal")
end)

-- 14. user-customized ranges defeat the preset
test("custom ranges defeat preset", function()
  setupSim()
  sim.fieldInfo[TELEM_RSSI] = { name = "Temp", unit = 11 }
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 },
    baseOptions({ Min = 10 }), widgetDir)
  widget.mod.update(widget, widget.options)
  assertEq(widget.config.min, 10, "user min kept")
  assertEq(widget.config.max, 100, "user max kept")
end)

-- 15. history min/max markers (history is tracked in refresh, since
-- background() does not run while the widget is visible)
test("history markers update", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 60
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)         -- data = 60, history = 60
  sim.sourceValues[TELEM_RSSI] = 20
  sim.timeMs = sim.timeMs + 100
  widget.mod.refresh(widget, nil, nil)         -- data = 20, history = 20..60
  widget.mod.refresh(widget, nil, nil)         -- markers rendered
  assertEq(widget.history.min, 20, "min history")
  assertEq(widget.history.max, 60, "max history")
  assertEq(widget.ui.minMark.props.pts ~= nil, true, "min marker set")
  assertEq(widget.ui.maxMark.props.pts ~= nil, true, "max marker set")
end)

-- 16. vertical layout
test("vertical layout", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 50
  local widget = newWidget({ x = 0, y = 0, w = 240, h = 480 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  assertEq(widget.layout.orientation, "vertical", "orientation")
  assertEq(widget.layout.mode, "large", "mode")
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.ui.valueLabel.props.text, "50", "value text")
end)

-- 17. no object churn when value unchanged
test("no redundant sets for unchanged value", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 50
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)
  local setsBefore = #widget.ui.valueLabel.sets
  sim.timeMs = sim.timeMs + 100
  widget.mod.refresh(widget, nil, nil)   -- same value, same state
  assertEq(#widget.ui.valueLabel.sets, setsBefore, "no new label sets")
end)

-- 18. smoothing converges toward the target
test("smoothing converges", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 50
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)          -- snaps to 50
  sim.sourceValues[TELEM_RSSI] = 100
  sim.timeMs = sim.timeMs + 3000
  widget.mod.refresh(widget, nil, nil)          -- long frame: converge
  assertTrue(widget.smooth.value > 99, "smoothed value converged")
  assertEq(widget.ui.valueArc.props.endAngle, 405, "arc at max")
end)

-- 19. fullscreen-sized zone (800x480)
test("fullscreen size composition", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 50
  local widget = newWidget({ x = 0, y = 0, w = 800, h = 480 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  assertEq(widget.layout.mode, "large", "large mode")
  assertEq(widget.layout.orientation, "horizontal", "horizontal")
  assertTrue(widget.ui.minText ~= nil, "min/max text labels")
  widget.mod.refresh(widget, nil, nil)
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.ui.minText.props.text, "MIN 50", "min text")
  assertEq(widget.ui.maxText.props.text, "MAX 50", "max text")
end)

-- 20. preset values survive a resize (regression: applied presets reverted)
test("preset survives resize", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 45
  sim.fieldInfo[TELEM_RSSI] = { name = "Temp", unit = 11 }
  local zone = { x = 0, y = 0, w = 480, h = 272 }
  local widget = newWidget(zone, baseOptions(), widgetDir)
  widget.mod.update(widget, widget.options)
  assertEq(widget.config.max, 120, "preset applied")
  zone.w, zone.h = 200, 200          -- resize -> update without option change
  widget.mod.update(widget, widget.options)
  assertEq(widget.config.max, 120, "preset kept after resize")
  assertEq(widget.config.crit, 90, "preset crit kept")
end)

-- 21. user changes defeat the preset permanently
test("user option change clears preset", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 45
  sim.fieldInfo[TELEM_RSSI] = { name = "Temp", unit = 11 }
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  assertEq(widget.config.max, 120, "preset applied")
  widget.mod.update(widget, baseOptions({ Warn = 60 }))
  assertEq(widget.config.max, 100, "preset cleared after user change")
  assertEq(widget.config.warn, 60, "user warn kept")
end)

-- 22. balanced normal zone keeps the name label inside the zone
test("balanced layout fits name label", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 50
  local widget = newWidget({ x = 0, y = 0, w = 150, h = 150 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  assertEq(widget.layout.orientation, "balanced", "orientation")
  assertEq(widget.layout.mode, "normal", "mode")
  assertTrue(widget.layout.nameY + widget.layout.nameH <= 150,
    "name label inside zone")
  assertTrue(widget.layout.stateY >= 0, "state label inside zone")
end)

-- 23. default source uses the firmware's native table default
-- (lua_widget_factory sourceValue(): first available source wins)
test("default source discovery", function()
  setupSim()
  local mod = dofile(widgetDir .. "main.lua")
  local names = mod.options[1][3]
  assertEq(type(names), "table", "source default is a name list")
  local found = 0
  for i = 1, #names do
    local info = getFieldInfo(names[i])
    if info then
      found = info.id
      break
    end
  end
  assertEq(found, TELEM_RSSI, "first available source resolved")
end)

-- 24. option types use the official WidgetOption enum values
-- (regression: Choice is 10, not 9 - Slider would break the settings UI)
test("option types are official constants", function()
  setupSim()
  local mod = dofile(widgetDir .. "main.lua")
  assertEq(mod.options[1][2], SOURCE, "Source type")
  assertEq(mod.options[2][2], VALUE, "Min type")
  assertEq(mod.options[6][2], BOOL, "HighGood type")
  assertEq(mod.options[7][2], CHOICE, "Style type")
  assertEq(mod.options[9][2], CHOICE, "Precision type")
  assertEq(type(mod.translate), "function", "translate callback present")
end)

-- 24. Auto precision follows the sensor precision
test("auto precision from sensor", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = 70
  sim.sensors[0] = { name = "RSSI", prec = 1, unit = 17 }
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 },
    baseOptions({ Precision = "Auto" }), widgetDir)
  widget.mod.update(widget, widget.options)
  assertEq(widget.config.precision, 1, "auto precision")
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.ui.valueLabel.props.text, "70.0", "one decimal")
end)

-- 25. timers display as hh:mm:ss
test("timer source formatting", function()
  setupSim()
  local TIMER = 500
  sim.fieldInfo[TIMER] = { name = "timer1" }
  sim.sourceValues[TIMER] = 3661
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 },
    baseOptions({ Source = TIMER }), widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.ui.valueLabel.props.text, "01:01:01", "hms format")
  assertEq(widget.ui.unitLabel.props.text, "", "no unit for timers")
end)

-- 26. telemetry link state: disconnected vs unavailable
test("telemetry link state detection", function()
  setupSim()
  sim.sourceValues[TELEM_RSSI] = nil
  sim.rssi = 0
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 }, baseOptions(),
    widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.data.availability, "disconnected", "link down")

  sim.rssi = 100
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.data.availability, "unavailable", "sensor missing, link up")
end)

-- 27. elapsed countdown timer shows the warning color (official Value widget)
test("elapsed timer warning color", function()
  setupSim()
  local TIMER = 600
  sim.fieldInfo[TIMER] = { id = TIMER, name = "timer1" }
  sim.sourceValues[TIMER] = -5
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 },
    baseOptions({ Source = TIMER, ColorMode = "Threshold" }), widgetDir)
  widget.mod.update(widget, widget.options)
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.ui.valueArc.props.color, env.COLOR_THEME_WARNING,
    "warning color for elapsed timer")
  assertEq(widget.ui.valueLabel.props.text, "-00:00:05", "negative hms")
end)

-- 28. tx-voltage shows a V unit and tx-time formats hh:mm:ss
test("tx-voltage unit and tx-time format", function()
  setupSim()
  local TXV = 700
  sim.fieldInfo[TXV] = { id = TXV, name = "tx-voltage" }
  sim.sourceValues[TXV] = 8.2
  local widget = newWidget({ x = 0, y = 0, w = 480, h = 272 },
    baseOptions({ Source = TXV }), widgetDir)
  widget.mod.update(widget, widget.options)
  assertEq(widget.source.unitName, "V", "tx-voltage unit")
  widget.mod.refresh(widget, nil, nil)
  assertEq(widget.ui.unitLabel.props.text, "V", "unit label text")

  local TXT = 710
  sim.fieldInfo[TXT] = { id = TXT, name = "tx-time" }
  sim.sourceValues[TXT] = 3661
  local w2 = newWidget({ x = 0, y = 0, w = 480, h = 272 },
    baseOptions({ Source = TXT }), widgetDir)
  w2.mod.update(w2, w2.options)
  w2.mod.refresh(w2, nil, nil)
  assertEq(w2.ui.valueLabel.props.text, "01:01:01", "tx-time hms")
end)

print(string.format("-- %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
