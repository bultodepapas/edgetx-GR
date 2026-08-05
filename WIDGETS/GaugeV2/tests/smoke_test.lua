-- Lifecycle tests for the GaugeV2 widget: drives the real widget code
-- through create / update / refresh against the mock EdgeTX environment,
-- which enforces the firmware's property allow-lists and option wire format.
--
-- Usage: lua5.3 tests/smoke_test.lua <widget-dir>

local widgetDir = arg[1] or "./"

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local passed, failed = 0, 0

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

local function assertEq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label or "assertEq",
      tostring(expected), tostring(actual)), 2)
  end
end

local function assertTrue(cond, label)
  if not cond then error((label or "assertTrue") .. " failed", 2) end
end

-- ---- simulated radio -----------------------------------------------------

local ID_RSSI, ID_CELLS, ID_TEMP_T1, ID_TIMER1, ID_STICK, ID_RXBT =
  3072, 3075, 3078, 200, 100, 3081
local ID_RSSI_MIN, ID_RSSI_MAX = 3073, 3074
local ID_RXBT_MIN, ID_RXBT_MAX = 3082, 3083

local function setupRadio()
  mock.reset()
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0, "edgetx" }
  mock.addField(ID_RSSI, "RSSI", 17)
  mock.addField(ID_RSSI_MIN, "RSSI-", 17)
  mock.addField(ID_RSSI_MAX, "RSSI+", 17)
  mock.addField(ID_CELLS, "Cels", 1)
  mock.addField(ID_TEMP_T1, "T1", 11)
  mock.addField(ID_RXBT, "RxBt", 1)
  mock.addField(ID_RXBT_MIN, "RxBt-", 1)
  mock.addField(ID_RXBT_MAX, "RxBt+", 1)
  mock.addField(ID_TIMER1, "timer1")     -- no unit: not a telemetry source
  mock.addField(ID_STICK, "Thr")
  mock.sim.sensors[0] = { name = "RSSI", prec = 0, unit = 17 }
  mock.sim.sensors[1] = { name = "RxBt", prec = 2, unit = 1 }
  mock.setValue(ID_RSSI, 70)
  mock.setValue(ID_STICK, 512)
end

local ZONE = { x = 0, y = 0, w = 200, h = 160 }

local function newWidget(zone, overrides, capacity, keepRadio)
  if not keepRadio then setupRadio() end
  if capacity == 10 then mock.sim.version = { "2.11.0", "sim", 2, 11, 0 } end
  local mod = dofile(widgetDir .. "main.lua")
  local opts = mock.makeOptions(mod.defs, overrides)
  if capacity then opts = mock.limitOptions(mod.defs, opts, capacity) end
  local widget = mod.create(zone or ZONE, opts, widgetDir)
  widget.mod = mod
  mod.update(widget, opts)
  return widget, mod, opts
end

local function refresh(widget, times)
  for _ = 1, (times or 1) do
    mock.advance(50)
    widget.mod.refresh(widget)
  end
end

-- Creation order of an object, matching LVGL's paint order (later = on top).
local function objIndex(obj)
  for i, o in ipairs(mock.objects()) do
    if o == obj then return i end
  end
  return nil
end

-- ---- option contract -----------------------------------------------------

local CORE_ORDER = {
  "Source", "Min", "Max", "Warn", "Crit", "HighGood", "Style", "ColorMode",
  "Precision", "ShowMinMax",
}

test("contract: the core ten keep their positions", function()
  local mod = dofile(widgetDir .. "main.lua")
  for i = 1, #CORE_ORDER do
    assertEq(mod.defs[i].key, CORE_ORDER[i], "slot " .. i)
    assertEq(mod.defs[i].since, 211, CORE_ORDER[i] .. " must exist on 2.11")
  end
end)

test("contract: option and widget names fit the ten character limit", function()
  local mod = dofile(widgetDir .. "main.lua")
  assertTrue(#mod.name <= 10, "widget name")
  for _, d in ipairs(mod.defs) do
    assertTrue(#d.key <= 10, d.key .. " too long")
    assertTrue(not string.find(d.key, " "), d.key .. " has a space")
  end
end)

test("contract: choice defaults are 1-based and in range", function()
  local mod = dofile(widgetDir .. "main.lua")
  for _, d in ipairs(mod.defs) do
    if d.type == CHOICE then
      assertTrue(d.default >= 1 and d.default <= #d.choices,
                 d.key .. " default " .. tostring(d.default))
    end
  end
end)

test("contract: 2.11 declares exactly ten options", function()
  mock.reset()
  mock.sim.version = { "2.11.0", "sim", 2, 11, 0 }
  local mod = dofile(widgetDir .. "main.lua")
  assertEq(#mod.options, 10)
  assertEq(mod.options[1][1], "Source")
end)

test("contract: 2.12 declares the full set", function()
  mock.reset()
  mock.sim.version = { "2.12.0", "sim", 2, 12, 0 }
  local mod = dofile(widgetDir .. "main.lua")
  assertTrue(#mod.options > 10, "extended set")
  for i = 1, #CORE_ORDER do
    assertEq(mod.options[i][1], CORE_ORDER[i], "position " .. i)
  end
end)

test("contract: translate covers every option and the widget", function()
  local mod = dofile(widgetDir .. "main.lua")
  assertEq(mod.translate("GaugeV2"), "Gauge V2")
  for _, d in ipairs(mod.defs) do
    assertTrue(mod.translate(d.key) ~= nil, "no label for " .. d.key)
  end
end)

test("contract: registration exposes only supported callbacks", function()
  local mod = dofile(widgetDir .. "main.lua")
  assertEq(mod.useLvgl, true)
  assertEq(type(mod.create), "function")
  assertEq(type(mod.refresh), "function")
  assertEq(mod.destroy, nil, "destroy is never called by the firmware")
end)

-- ---- build ---------------------------------------------------------------

test("builds an object tree and renders a value", function()
  local w = newWidget(nil, { Source = ID_RSSI })
  assertTrue(w.ui.built, "built")
  refresh(w)
  assertEq(w.data.availability, "valid")
  assertEq(w.frame.valueStr, "70")
  assertTrue(mock.objectCount() > 5, "objects created")
end)

test("object count stays inside the budget", function()
  local w = newWidget({ x = 0, y = 0, w = 400, h = 240 },
                      { Source = ID_RSSI, ShowMinMax = "Markers + text" })
  refresh(w)
  assertTrue(mock.objectCount() <= 40,
             "object count " .. mock.objectCount())
end)

test("refresh creates no objects and writes nothing when idle", function()
  local w = newWidget(nil, { Source = ID_RSSI })
  refresh(w, 3)
  local objects = mock.objectCount()
  local before = mock.totalSets()
  refresh(w, 3)                        -- value unchanged
  assertEq(mock.objectCount(), objects, "no new objects")
  assertEq(mock.totalSets(), before, "no property writes")
end)

test("a changed value writes only what changed", function()
  local w = newWidget(nil, { Source = ID_RSSI, Damping = 0 })
  refresh(w, 2)
  local before = mock.totalSets()
  mock.setValue(ID_RSSI, 40)
  refresh(w)
  local writes = mock.totalSets() - before
  assertTrue(writes > 0, "something changed")
  assertTrue(writes < 20, "only deltas, got " .. writes)
end)

-- ---- the option contract in action ---------------------------------------

test("colour mode is honoured (1.0 compared choices to strings)", function()
  local w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Sections" })
  assertEq(w.config.colorMode, 5, "Sections index")
  assertTrue(w.ui.sections ~= nil, "section arcs built")
  assertTrue(#w.ui.sections >= 2, "one arc per band")

  w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Rail" })
  assertTrue(w.ui.rails ~= nil and #w.ui.rails == 2,
             "rail marks the warning and critical bands")
end)

test("G-2: Sections bands sit outside the value arc, at full opacity", function()
  -- Sharing the value arc's own radius/thickness at 25% opacity put the
  -- bands directly underneath it, invisible at any value inside the normal
  -- band - pixel-identical to Static. They must use the outer (rail) radius
  -- and paint at full opacity, the same model as the working Rail mode.
  local w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Sections" })
  assertTrue(w.ui.track ~= nil, "a plain background track is still built")
  for _, s in ipairs(w.ui.sections) do
    assertEq(s.props.radius, w.layout.railRadius, "sections use the rail radius")
    assertTrue(s.props.radius ~= w.ui.track.props.radius,
      "sections must not share the value arc's own radius")
    assertEq(s.props.bgOpacity, 255, "sections must be fully opaque")
  end
end)

test("P0-3: a descending scale still draws sections, rails and bar marks", function()
  -- Min > Max mirrors the value->angle mapping (geometry.normalize), so the
  -- angle of a band's `from` can land above the angle of its `to`; comparing
  -- angleOf(from) < angleOf(to), or the raw value against cfg.min/max on the
  -- bar, silently drops every band on a descending scale.
  local w = newWidget(nil, { Source = ID_STICK, Scale = "Manual",
                             Min = 100, Max = 0, ColorMode = "Sections" })
  assertTrue(w.ui.sections ~= nil and #w.ui.sections >= 2,
             "descending scale must still build section arcs")

  w = newWidget(nil, { Source = ID_STICK, Scale = "Manual",
                       Min = 100, Max = 0, ColorMode = "Rail" })
  assertTrue(w.ui.rails ~= nil and #w.ui.rails >= 1,
             "descending scale must still build rail arcs")

  w = newWidget({ x = 0, y = 0, w = 300, h = 70 },
                { Source = ID_STICK, Scale = "Manual", Min = 100, Max = 0,
                  Style = "Bar", ColorMode = "Threshold" })
  assertTrue(w.ui.marks ~= nil and #w.ui.marks >= 1,
             "descending scale must still build bar threshold marks")
end)

test("threshold colouring reaches the objects", function()
  local w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Threshold" })
  mock.setValue(ID_RSSI, 70); refresh(w)
  assertEq(w.frame.colorKey, "normal")
  mock.setValue(ID_RSSI, 45); refresh(w, 2)
  assertEq(w.frame.colorKey, "warning")
  assertEq(w.ui.valueArc.props.color, COLOR_THEME_WARNING)
  mock.setValue(ID_RSSI, 10); refresh(w, 2)
  assertEq(w.frame.colorKey, "critical")
  assertEq(w.ui.valueLabel.props.color, RED)
end)

test("style choice controls the needle", function()
  local w = newWidget(nil, { Source = ID_RSSI, Style = "Arc" })
  assertEq(w.ui.needle, nil, "arc style has no needle")
  w = newWidget(nil, { Source = ID_RSSI, Style = "Needle" })
  assertTrue(w.ui.needle ~= nil, "needle style draws one")
  assertEq(w.ui.needle.kind, "triangle", "tapered needle")
end)

test("precision choice selects the decimals", function()
  local w = newWidget(nil, { Source = ID_RSSI, Precision = "2",
                             Scale = "Manual" })
  mock.setValue(ID_RSSI, 70)
  refresh(w)
  assertEq(w.frame.valueStr, "70.00")
end)

test("precision Auto follows the sensor", function()
  local w = newWidget(nil, { Source = ID_RXBT, Precision = "Auto" })
  assertEq(w.config.precision, 2, "RxBt sensor declares prec 2")
end)

test("gradient mode produces a continuous colour", function()
  local w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Gradient" })
  mock.setValue(ID_RSSI, 80); refresh(w)
  local high = w.ui.valueArc.props.color
  mock.setValue(ID_RSSI, 20); refresh(w, 2)
  assertTrue(w.ui.valueArc.props.color ~= high, "colour tracks the value")
end)

-- ---- 2.11 compatibility --------------------------------------------------

test("2.11 build works with ten options and default behaviour", function()
  local w = newWidget(nil, { Source = ID_RSSI }, 10)
  assertEq(w.options.Accent, nil, "no extended options delivered")
  assertEq(w.config.damping, 4, "declared default still applies")
  refresh(w)
  assertEq(w.data.availability, "valid")
  assertEq(w.frame.valueStr, "70")
end)

test("2.11 keeps the preset heuristic (no Scale option)", function()
  local w = newWidget(nil, { Source = ID_RXBT }, 10)
  assertEq(w.hasScaleOption, false)
  assertEq(w.config.max, 8.4, "RxBt preset applied at defaults")
  -- a user who edits a range gets their own values
  w = newWidget(nil, { Source = ID_RXBT, Max = 25 }, 10)
  assertEq(w.config.max, 25, "custom range wins")
end)

test("Scale = Manual defeats presets on 2.12", function()
  local w = newWidget(nil, { Source = ID_RXBT, Scale = "Manual", Max = 25 })
  assertEq(w.config.max, 25)
  w = newWidget(nil, { Source = ID_RXBT, Scale = "Auto", Max = 25 })
  assertEq(w.config.max, 8.4, "Auto prefers the preset")
end)

-- ---- telemetry -----------------------------------------------------------

test("T1 is a temperature sensor, not a timer", function()
  local w = newWidget(nil, { Source = ID_TEMP_T1 })
  assertEq(w.source.isTimer, false, "T1 must not be read as a timer")
  mock.setValue(ID_TEMP_T1, 65)
  refresh(w)
  assertEq(w.frame.valueStr, "65")
  assertEq(w.config.highGood, false, "temperature preset is low-is-good")
end)

test("timer sources format as hh:mm:ss", function()
  local w = newWidget(nil, { Source = ID_TIMER1 })
  assertEq(w.source.isTimer, true)
  mock.setValue(ID_TIMER1, 3661)
  refresh(w)
  assertEq(w.frame.valueStr, "01:01:01")
end)

test("an elapsed timer colours the gauge warning", function()
  local w = newWidget(nil, { Source = ID_TIMER1 })
  mock.setValue(ID_TIMER1, -12)
  refresh(w)
  assertEq(w.frame.valueStr, "-00:00:12")
  assertEq(w.frame.colorKey, "warning")
end)

test("cell tables aggregate by the chosen mode", function()
  local cells = { 4.10, 3.95, 4.05, 3.80 }
  local w = newWidget(nil, { Source = ID_CELLS, Cells = "Lowest",
                             Scale = "Manual", Min = 0, Max = 5,
                             Precision = "2" })
  mock.setValue(ID_CELLS, cells)
  refresh(w)
  assertEq(w.frame.valueStr, "3.80", "lowest cell")

  w = newWidget(nil, { Source = ID_CELLS, Cells = "Total", Scale = "Manual",
                       Min = 0, Max = 20, Precision = "2" })
  mock.setValue(ID_CELLS, cells)
  refresh(w)
  assertEq(w.frame.valueStr, "15.90", "pack total")

  w = newWidget(nil, { Source = ID_CELLS, Cells = "Average", Scale = "Manual",
                       Min = 0, Max = 5, Precision = "2" })
  mock.setValue(ID_CELLS, cells)
  refresh(w)
  assertEq(w.frame.valueStr, "3.98", "average cell")
end)

test("P1-6: only Cells=Total switches a Cels source to the pack-range scale", function()
  local cells = { 4.10, 4.05, 4.00, 3.95 }   -- a 4S pack, all in Auto/default

  local wLowest = newWidget(nil, { Source = ID_CELLS, Cells = "Lowest" })
  mock.setValue(ID_CELLS, cells); refresh(wLowest, 2)
  assertEq(wLowest.source.cells, 4, "cell count still detected")
  assertTrue(wLowest.config.max < 5,
    "Lowest must stay on the single-cell preset scale, got max=" ..
    tostring(wLowest.config.max))
  assertTrue(tonumber(wLowest.frame.valueStr) > wLowest.config.min,
    "the lowest cell (3.95) must not be clamped to the bottom of the dial")

  local wAvg = newWidget(nil, { Source = ID_CELLS, Cells = "Average" })
  mock.setValue(ID_CELLS, cells); refresh(wAvg, 2)
  assertTrue(wAvg.config.max < 5, "Average must also stay single-cell scale")

  local wTotal = newWidget(nil, { Source = ID_CELLS, Cells = "Total" })
  mock.setValue(ID_CELLS, cells); refresh(wTotal, 2)
  assertTrue(wTotal.config.max > 10,
    "Total must switch to the pack-range scale, got max=" ..
    tostring(wTotal.config.max))
end)

test("a 4S pack on a voltage source scales the dial", function()
  local w = newWidget(nil, { Source = ID_RXBT })
  assertEq(w.config.max, 8.4, "single cell preset before any reading")
  mock.setValue(ID_RXBT, 16.4)
  refresh(w)
  assertEq(w.source.cells, 4, "cell count latched")
  assertTrue(w.config.max > 16, "scale rebuilt for the pack, got " ..
             tostring(w.config.max))
end)

test("P0-2: the cell latch rebuilds sections, rails and scale labels", function()
  local zone = { x = 0, y = 0, w = 260, h = 220 }   -- large: scale labels shown
  local w = newWidget(zone, { Source = ID_RXBT, ColorMode = "Sections" })
  local before = {}
  for i, s in ipairs(w.ui.sections) do
    before[i] = s.props.startAngle .. "-" .. s.props.endAngle
  end
  local scaleMaxBefore = w.ui.scaleMax.props.text

  mock.setValue(ID_RXBT, 16.4)
  refresh(w, 2)
  assertTrue(w.config.max > 16, "scale rebuilt for the pack")

  local moved = false
  for i, s in ipairs(w.ui.sections) do
    if before[i] ~= (s.props.startAngle .. "-" .. s.props.endAngle) then
      moved = true
    end
  end
  assertTrue(moved, "section angles must follow the new scale, not the old one")
  assertTrue(w.ui.scaleMax.props.text ~= scaleMaxBefore,
    "scale label must reprint for the new max, got " .. w.ui.scaleMax.props.text)
  assertEq(w.ui.scaleMax.props.text, "16.80", "4S pack max at RxBt's precision (2)")

  -- rail mode: same story
  local wr = newWidget(zone, { Source = ID_RXBT, ColorMode = "Rail" })
  local railBefore = wr.ui.rails[1].props.startAngle .. "-" .. wr.ui.rails[1].props.endAngle
  mock.setValue(ID_RXBT, 16.4)
  refresh(wr, 2)
  local railAfter = wr.ui.rails[1].props.startAngle .. "-" .. wr.ui.rails[1].props.endAngle
  assertTrue(railBefore ~= railAfter, "rail angles must follow the new scale")

  -- bar mode: threshold marks must follow too
  local wb = newWidget({ x = 0, y = 0, w = 300, h = 70 },
                       { Source = ID_RXBT, Style = "Bar", ColorMode = "Threshold" })
  local markBefore = wb.ui.marks[1].props.pts[1][1]
  mock.setValue(ID_RXBT, 16.4)
  refresh(wb, 2)
  local markAfter = wb.ui.marks[1].props.pts[1][1]
  assertTrue(markBefore ~= markAfter, "bar threshold marks must follow the new scale")
end)

test("P0-5: cellsApplied resets on a source change", function()
  local w, mod, opts = newWidget(nil, { Source = ID_RXBT })
  mock.setValue(ID_RXBT, 16.4)
  refresh(w, 2)
  assertTrue(w.cellsApplied, "first source's cell count latched")

  opts.Source = ID_CELLS
  mod.update(w, opts)
  assertEq(w.cellsApplied, nil, "cellsApplied must clear so the new source can latch")

  mock.setValue(ID_CELLS, { 4.10, 4.05, 4.00 })
  refresh(w, 2)
  assertEq(w.source.cells, 3, "the new source's own cell count was latched")
end)

test("battery percent turns volts into state of charge", function()
  local w = newWidget(nil, { Source = ID_RXBT, Battery = "Li-Po" })
  mock.setValue(ID_RXBT, 16.4)          -- 4S at 4.10 V/cell
  refresh(w)
  assertEq(w.config.max, 100, "percentage scale")
  assertEq(w.unitText, "%")
  local pct = tonumber(w.frame.valueStr)
  assertTrue(pct > 85 and pct <= 100, "got " .. w.frame.valueStr)
end)

test("history comes from the radio's own min/max sensors", function()
  local w = newWidget(nil, { Source = ID_RSSI })
  mock.setValue(ID_RSSI_MIN, 31)
  mock.setValue(ID_RSSI_MAX, 92)
  refresh(w)
  assertEq(w.history.min, 31)
  assertEq(w.history.max, 92)
end)

test("history falls back to tracking for local sources", function()
  local w = newWidget(nil, { Source = ID_STICK, Scale = "Manual",
                             Min = 0, Max = 1024 })
  mock.setValue(ID_STICK, 400); refresh(w)
  mock.setValue(ID_STICK, 900); refresh(w)
  mock.setValue(ID_STICK, 600); refresh(w)
  assertEq(w.history.min, 400)
  assertEq(w.history.max, 900)
end)

test("P1-9: the fallback tracker still runs while siblings resolve but read nil", function()
  -- RSSI-/RSSI+ are registered fields (minId/maxId resolve) but never given a
  -- value: a sensor that just appeared has no samples yet. Treating a nil
  -- reading as "the radio has it covered" would disable the fallback tracker
  -- forever, leaving history stuck at nil even while the value itself works.
  local w = newWidget(nil, { Source = ID_RSSI })
  mock.setValue(ID_RSSI, 70); refresh(w)
  mock.setValue(ID_RSSI, 55); refresh(w)
  mock.setValue(ID_RSSI, 80); refresh(w)
  assertEq(w.history.min, 55, "fallback tracker ran despite unread siblings")
  assertEq(w.history.max, 80)
end)

test("P0-7: battery percent history is tracked in percent, not raw sibling volts", function()
  local w = newWidget(nil, { Source = ID_RXBT, Battery = "Li-Po",
                             ShowMinMax = "Markers + text" })
  mock.setValue(ID_RXBT_MIN, 14.8)
  mock.setValue(ID_RXBT_MAX, 16.8)
  mock.setValue(ID_RXBT, 16.0); refresh(w)
  mock.setValue(ID_RXBT, 16.4); refresh(w)
  assertTrue(w.history.max <= 100,
    "history must be a percent, got " .. tostring(w.history.max))
  assertTrue(w.history.min >= 0 and w.history.min <= 100)
end)

test("P0-7: Cells=Total history is tracked in pack volts, not per-cell siblings", function()
  local w = newWidget(nil, { Source = ID_CELLS, Cells = "Total",
                             Scale = "Manual", Min = 0, Max = 20 })
  -- Cels-/Cels+ (a real firmware pair) report a single CELL's extreme, which
  -- would be far below a pack total if trusted here.
  mock.addField(3076, "Cels-", 1)
  mock.addField(3077, "Cels+", 1)
  mock.setValue(3076, 3.80)
  mock.setValue(3077, 4.10)
  mock.setValue(ID_CELLS, { 4.10, 4.05, 4.00, 3.95 }); refresh(w)
  mock.setValue(ID_CELLS, { 3.90, 3.85, 3.80, 3.75 }); refresh(w)
  assertTrue(w.history.max > 10,
    "pack total history, got " .. tostring(w.history.max) .. " (looks per-cell)")
end)

test("P1-8: the reset switch resets a real telemetry sensor at the radio", function()
  local SWITCH = 160
  local w = newWidget(nil, { Source = ID_RSSI, ResetSw = SWITCH })
  mock.setValue(ID_RSSI, 70); refresh(w)
  mock.setValue(ID_RSSI_MIN, 31)
  mock.setValue(ID_RSSI_MAX, 92)
  refresh(w)
  assertEq(w.history.min, 31)
  assertEq(w.history.max, 92)

  mock.setSwitch(SWITCH, true)   -- rising edge
  refresh(w)
  assertEq(#mock.sim.sensorResets, 1, "model.resetSensor must be called once")
  assertEq(mock.sim.sensorResets[1], 0, "RSSI is sensor index 0 in this radio")
  assertEq(w.history.min, nil, "history cleared by the reset, not re-fed stale siblings")
  assertEq(w.history.max, nil)
end)

test("markers stay hidden until history exists", function()
  local w = newWidget(nil, { Source = ID_STICK, ShowMinMax = "Markers" })
  assertTrue(w.ui.minMark ~= nil, "marker objects exist")
  assertEq(w.ui.minMark.visible, false, "hidden before any sample")
  mock.setValue(ID_STICK, 400); refresh(w)
  assertEq(w.ui.minMark.visible, true, "shown once data arrives")
end)

-- ---- availability --------------------------------------------------------

test("no data states are distinguished", function()
  local w = newWidget(nil, { Source = ID_RSSI })
  refresh(w)
  assertEq(w.data.availability, "valid")

  mock.sim.current[ID_RSSI] = false
  refresh(w)
  assertEq(w.data.availability, "stale")
  assertEq(w.frame.stateStr, "STALE")
  assertEq(w.frame.valueStr, "70", "last known value stays on screen")

  mock.setValue(ID_RSSI, nil)
  mock.sim.rssi = 0
  refresh(w)
  assertEq(w.data.availability, "disconnected")
  assertEq(w.frame.stateStr, "NO LINK")
  assertEq(w.frame.colorKey, "muted")
end)

test("the needle hides and snaps back on reconnect", function()
  local w = newWidget(nil, { Source = ID_RSSI, Style = "Needle" })
  refresh(w)
  assertEq(w.ui.needle.visible, true)
  mock.setValue(ID_RSSI, nil); mock.sim.rssi = 0
  refresh(w)
  assertEq(w.ui.needle.visible, false, "hidden with no data")
  mock.sim.rssi = 100
  mock.setValue(ID_RSSI, 20)
  refresh(w)
  assertEq(w.ui.needle.visible, true)
  assertEq(w.smooth.value, 20, "snaps instead of sweeping from the old value")
end)

test("changing the source clears the previous reading", function()
  local w, mod, opts = newWidget(nil, { Source = ID_RSSI })
  refresh(w)
  assertEq(w.frame.valueStr, "70")
  opts.Source = ID_STICK
  opts.Scale = 2       -- Manual
  opts.Min, opts.Max = 0, 1024
  mod.update(w, opts)
  assertEq(w.data.lastValue, nil, "no stale value from the old source")
  assertEq(w.history.min, nil, "history reset")
end)

-- ---- layout --------------------------------------------------------------

local ZONES = {
  { 60, 60, "micro" }, { 100, 100, "compact" }, { 160, 160, "normal" },
  { 200, 200, "large" }, { 320, 100, "wide" }, { 100, 200, "tall" },
  { 480, 272, "fullscreen" }, { 200, 60, "strip" },
}

test("every layout keeps its objects inside the zone", function()
  for _, z in ipairs(ZONES) do
    local zone = { x = 0, y = 0, w = z[1], h = z[2] }
    local w = newWidget(zone, { Source = ID_RSSI })
    refresh(w)
    for _, obj in ipairs(mock.objects()) do
      local p = obj.props
      local x1, y1, x2, y2
      if p.pts then
        x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
        for _, pt in ipairs(p.pts) do
          x1 = math.min(x1, pt[1]); x2 = math.max(x2, pt[1])
          y1 = math.min(y1, pt[2]); y2 = math.max(y2, pt[2])
        end
      elseif p.radius then
        x1, y1 = p.x - p.radius, p.y - p.radius
        x2, y2 = p.x + p.radius, p.y + p.radius
      else
        x1, y1 = p.x or 0, p.y or 0
        x2, y2 = x1 + (p.w or 0), y1 + (p.h or 0)
      end
      local slack = 2
      assertTrue(x1 >= -slack and y1 >= -slack and x2 <= zone.w + slack
                 and y2 <= zone.h + slack,
        string.format("%s %s out of %dx%d: %.0f,%.0f..%.0f,%.0f", z[3],
                      obj.kind, zone.w, zone.h, x1, y1, x2, y2))
    end
  end
end)

test("layout modes and orientations classify as documented", function()
  local w = newWidget({ x = 0, y = 0, w = 60, h = 60 }, { Source = ID_RSSI })
  assertEq(w.layout.mode, "micro")
  assertEq(w.layout.showNeedle, false, "micro has no needle")
  w = newWidget({ x = 0, y = 0, w = 200, h = 200 }, { Source = ID_RSSI })
  assertEq(w.layout.mode, "large")
  assertEq(w.layout.orientation, "balanced")
  w = newWidget({ x = 0, y = 0, w = 300, h = 150 }, { Source = ID_RSSI })
  assertEq(w.layout.orientation, "horizontal")
end)

test("a long thin zone becomes a bar", function()
  local w = newWidget({ x = 0, y = 0, w = 300, h = 60 }, { Source = ID_RSSI })
  assertEq(w.layout.style, "bar")
  assertTrue(w.ui.fill ~= nil, "bar fill built")
  refresh(w)
  assertTrue(w.frame.fillW > 0, "fill tracks the value")
  assertEq(w.frame.valueStr, "70")
end)

test("Style = Bar forces the linear style anywhere", function()
  local w = newWidget({ x = 0, y = 0, w = 200, h = 200 },
                      { Source = ID_RSSI, Style = "Bar" })
  assertEq(w.layout.style, "bar")
end)

test("G-12: bar threshold marks paint on top of the fill, not under it", function()
  local w = newWidget({ x = 0, y = 0, w = 300, h = 70 },
                      { Source = ID_RSSI, ColorMode = "Threshold" })
  assertTrue(w.ui.marks ~= nil and #w.ui.marks >= 1, "marks built")
  local fillIdx = objIndex(w.ui.fill)
  assertTrue(fillIdx ~= nil, "fill object found")
  for i, m in ipairs(w.ui.marks) do
    assertTrue(objIndex(m) > fillIdx,
      "mark " .. i .. " created before the fill would be painted under it "..
      "and vanish once the value's fill reaches it")
  end
end)

test("resize rebuilds only when the structure changes", function()
  local w, mod, opts = newWidget(nil, { Source = ID_RSSI })
  refresh(w)
  local sig = w.layoutSig
  w.zone.w = w.zone.w + 1
  mod.update(w, opts)
  assertTrue(w.layoutSig ~= sig, "a size change is structural")
  local sig2 = w.layoutSig
  mod.update(w, opts)
  assertEq(w.layoutSig, sig2, "no change, no rebuild")
end)

test("sweep option changes the arc geometry", function()
  local w = newWidget(nil, { Source = ID_RSSI, Sweep = "180 deg" })
  assertEq(w.layout.startAngle, 180)
  assertEq(w.layout.sweep, 180)
  w = newWidget(nil, { Source = ID_RSSI, Sweep = "360 deg" })
  refresh(w)
  mock.setValue(ID_RSSI, 100); refresh(w, 5)
  assertTrue(w.frame.angle < 270 + 360, "full ring never closes on itself")
end)

test("P0-4: a 360 degree sweep still draws the background track", function()
  -- LVGL normalises a > 360 angle by subtracting 360 exactly once
  -- (270 + 360 = 630 -> 270), which without the fix collapses the track's
  -- bgStartAngle/bgEndAngle onto the same point - a zero-length arc LVGL
  -- skips drawing entirely.
  local w = newWidget(nil, { Source = ID_RSSI, Sweep = "360 deg" })
  assertTrue(w.ui.track ~= nil, "default colour mode builds a track arc")
  local p = w.ui.track.props
  local function lvNorm(a) return (a > 360) and (a - 360) or a end
  assertTrue(lvNorm(p.bgStartAngle) ~= lvNorm(p.bgEndAngle),
    "track background must not collapse to a zero-length arc")
end)

-- ---- text ----------------------------------------------------------------

test("labels are aligned by LVGL, not by measuring", function()
  local w = newWidget(nil, { Source = ID_RSSI })
  local labels = mock.byKind("label")
  assertTrue(#labels > 0)
  for _, l in ipairs(labels) do
    assertTrue(l.props.w ~= nil and l.props.w > 0, "label has a width")
    assertTrue(l.props.align ~= nil, "label has an alignment")
  end
  -- the value label never moves when the value width changes
  local x = w.ui.valueLabel.props.x
  mock.setValue(ID_RSSI, 7); refresh(w)
  mock.setValue(ID_RSSI, 100); refresh(w)
  assertEq(w.ui.valueLabel.props.x, x, "value box is fixed")
end)

test("name and unit overrides win over the sensor", function()
  local w = newWidget(nil, { Source = ID_RSSI, Label = "LINK",
                             Suffix = "dBm" })
  assertEq(w.nameText, "LINK")
  assertEq(w.unitText, "dBm")
  assertEq(w.ui.nameLabel.props.text, "LINK")
end)

test("P0-6: editing the Name override updates the label without a rebuild", function()
  local w, mod, opts = newWidget(nil, { Source = ID_RSSI })
  refresh(w)
  assertEq(w.ui.nameLabel.props.text, "RSSI")
  local sig = w.layoutSig
  opts.Label = "LINK"
  mod.update(w, opts)
  assertEq(w.layoutSig, sig, "a name edit is not a structural change")
  assertEq(w.nameText, "LINK")
  assertEq(w.ui.nameLabel.props.text, "LINK", "label text updated on the cheap path")
end)

-- ---- alerts and switches -------------------------------------------------

test("alerts fire once on entering a state, after the startup delay", function()
  local w = newWidget(nil, { Source = ID_RSSI, Alerts = "Critical",
                             Delay = 0, Vibrate = true })
  mock.setValue(ID_RSSI, 70)
  refresh(w)
  assertEq(#mock.sim.tones, 0, "silent while normal")
  mock.setValue(ID_RSSI, 10)
  refresh(w, 3)
  assertTrue(#mock.sim.tones > 0, "alert on critical")
  assertTrue(#mock.sim.haptics > 0, "vibrate on critical")
  local count = #mock.sim.tones
  refresh(w, 3)
  assertEq(#mock.sim.tones, count, "no repeat while the state holds")
end)

test("the startup delay suppresses power-on alerts", function()
  local w = newWidget(nil, { Source = ID_RSSI, Alerts = "Critical",
                             Delay = 10 })
  mock.setValue(ID_RSSI, 5)
  refresh(w, 5)
  assertEq(#mock.sim.tones, 0, "quiet during the delay")
end)

test("the reset switch clears the tracked history", function()
  local SWITCH = 150
  local w = newWidget(nil, { Source = ID_STICK, ResetSw = SWITCH,
                             Scale = "Manual", Min = 0, Max = 1024 })
  mock.setSwitch(SWITCH, false)
  mock.setValue(ID_STICK, 200); refresh(w)
  mock.setValue(ID_STICK, 900); refresh(w)
  assertEq(w.history.max, 900)
  mock.setValue(ID_STICK, 300)
  mock.setSwitch(SWITCH, true)   -- rising edge
  refresh(w)
  assertEq(w.history.max, 300, "history restarted from the current value")
  assertEq(w.history.min, 300)
end)

test("P0-1: switch options are read with getSwitchValue, not getValue", function()
  -- getValue()/sim.values and getSwitchValue()/sim.switches are deliberately
  -- separate stores in the mock (see mock_env.lua M.setSwitch): a widget that
  -- reads a SWITCH option through getValue() must see nothing here, exactly
  -- as it would misread an unrelated MIXSRC on real firmware.
  local SWITCH = 151
  local w = newWidget(nil, { Source = ID_STICK, ResetSw = SWITCH,
                             Scale = "Manual", Min = 0, Max = 1024 })
  mock.setValue(ID_STICK, 200); refresh(w)
  mock.setValue(ID_STICK, 900); refresh(w)
  assertEq(w.history.max, 900)

  mock.setValue(SWITCH, 1024)    -- wrong API's store: must have no effect
  refresh(w)
  assertEq(w.history.max, 900, "a getValue()-based read would already have reset")

  mock.setValue(ID_STICK, 50)
  mock.setSwitch(SWITCH, true)   -- right API's store, rising edge: must reset
  refresh(w)
  assertEq(w.history.max, 50, "reset switch fired via getSwitchValue")
end)

test("P0-1: a switch mis-read as a value does not silence alerts", function()
  local SWITCH = 152
  local w = newWidget(nil, { Source = ID_RSSI, Alerts = "Critical",
                             AlertSw = SWITCH, Delay = 0 })
  mock.setValue(SWITCH, 0)       -- wrong API's store would read "off"
  mock.setSwitch(SWITCH, true)   -- right API's store: armed
  mock.setValue(ID_RSSI, 10)
  refresh(w, 2)
  assertTrue(#mock.sim.tones > 0, "alert must fire: the switch is armed via getSwitchValue")
end)

-- ---- scenarios -----------------------------------------------------------

local function runScenario(w, samples, id)
  for _, v in ipairs(samples) do
    mock.setValue(id, v)
    refresh(w)
  end
end

test("scenario: noisy ramp does not flicker the state", function()
  local w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Threshold" })
  local samples, flips, last = {}, 0, nil
  for i = 0, 40 do
    samples[#samples + 1] = 60 - i * 0.3 + ((i % 2 == 0) and 0.6 or -0.6)
  end
  for _, v in ipairs(samples) do
    mock.setValue(ID_RSSI, v)
    refresh(w)
    if last and w.data.state ~= last then flips = flips + 1 end
    last = w.data.state
  end
  assertTrue(flips <= 2, "state flips: " .. flips)
end)

test("scenario: dropout and recovery", function()
  local w = newWidget(nil, { Source = ID_RSSI })
  runScenario(w, { 80, 75, 70 }, ID_RSSI)
  assertEq(w.data.availability, "valid")
  mock.setValue(ID_RSSI, nil); mock.sim.rssi = 0
  refresh(w, 4)
  assertEq(w.data.availability, "disconnected")
  assertEq(w.frame.valueStr, "70", "last known value held")
  mock.sim.rssi = 100
  runScenario(w, { 65, 60 }, ID_RSSI)
  assertEq(w.data.availability, "valid")
  assertEq(w.frame.valueStr, "60")
end)

test("scenario: a full flight keeps the object tree stable", function()
  local w = newWidget(nil, { Source = ID_RSSI })
  refresh(w)
  local objects = mock.objectCount()
  for i = 1, 200 do
    mock.setValue(ID_RSSI, 30 + (i % 60))
    refresh(w)
  end
  assertEq(mock.objectCount(), objects, "no object churn in flight")
end)

print(string.format("-- %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
