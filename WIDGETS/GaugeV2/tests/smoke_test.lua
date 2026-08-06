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

test("P2-2: a state transition batches one lvgl.set per object", function()
  -- Every lvgl.set is a full C++ getParams + refresh(); the audit measured
  -- 14 of them in a single normal -> critical transition, over 6 objects,
  -- because each property was sent separately. Dirty properties are now
  -- queued per object and flushed in one call (AUDIT.md P2-2).
  local w = newWidget({ x = 0, y = 0, w = 200, h = 160 },
    { Source = ID_RSSI, Damping = 0 })
  refresh(w, 2)
  -- the value arc changes colour, opacity AND angle in the same frame
  local before = w.ui.valueArc.setCount
  mock.setValue(ID_RSSI, 10)          -- critical: colour + opacity + angle
  refresh(w)
  assertEq(w.ui.valueArc.setCount - before, 1,
    "colour+opacity+endAngle must go out in ONE lvgl.set, not three")
end)

test("P2-3: the module table is shared between instances", function()
  -- main.lua is evaluated once per radio and its upvalues are shared; every
  -- instance used to load app.lua + 12 modules itself (13 loadScript calls
  -- each). The app and its module table are now memoized (AUDIT.md P2-3).
  setupRadio()
  local realLoad = loadScript
  local calls = 0
  loadScript = function(path) calls = calls + 1 return realLoad(path) end
  local ok, err = pcall(function()
    local mod = dofile(widgetDir .. "main.lua")
    local opts = mock.makeOptions(mod.defs, { Source = ID_RSSI })
    local zone = { x = 0, y = 0, w = 200, h = 160 }
    local w1 = mod.create(zone, opts, widgetDir)
    mod.update(w1, opts)
    local afterFirst = calls
    assertTrue(afterFirst > 0, "the first instance loads the chunks")
    local w2 = mod.create(zone, opts, widgetDir)
    mod.update(w2, opts)
    assertEq(calls - afterFirst, 0,
      "a second instance must not reload any chunk, got "
      .. (calls - afterFirst))
    assertTrue(w1.mods == w2.mods, "instances share the module table")
  end)
  loadScript = realLoad
  if not ok then error(err) end
end)

test("P2-4: re-resolving a sensor name hits the precision cache", function()
  -- findSensor() used to scan all MAX_SENSORS on every source resolution,
  -- building a fresh table per model.getSensor call (AUDIT.md P2-4). Hits
  -- are now memoized and the modules are shared, so a second instance
  -- resolving the same sensor must not rescan.
  setupRadio()
  local mod = dofile(widgetDir .. "main.lua")
  local real = model.getSensor
  local scans = 0
  model.getSensor = function(i) scans = scans + 1 return real(i) end
  local ok, err = pcall(function()
    local opts = mock.makeOptions(mod.defs, { Source = ID_RSSI })
    local zone = { x = 0, y = 0, w = 200, h = 160 }
    local w1 = mod.create(zone, opts, widgetDir)
    mod.update(w1, opts)
    local afterFirst = scans
    assertTrue(afterFirst > 0, "the first resolution scans the sensor table")
    local w2 = mod.create(zone, opts, widgetDir)
    mod.update(w2, opts)
    assertEq(scans, afterFirst,
      "re-resolving the same sensor must hit the cache, rescan="
      .. (scans - afterFirst))
  end)
  model.getSensor = real
  if not ok then error(err) end
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

test("the normal state defaults to green, not the accent colour", function()
  local w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Threshold" })
  mock.setValue(ID_RSSI, 70); refresh(w)
  assertEq(w.frame.colorKey, "normal")
  assertEq(w.ui.valueArc.props.color, COLOR_THEME_ACTIVE,
    "normal state is green by default (owner request, Tanda 5)")

  local w2 = newWidget(nil, { Source = ID_RSSI, ColorMode = "Threshold",
                              Accent = COLOR_THEME_FOCUS })
  mock.setValue(ID_RSSI, 70); refresh(w2)
  assertEq(w2.ui.valueArc.props.color, COLOR_THEME_FOCUS,
    "an explicit Accent still overrides the green default")
end)

test("the needle keeps a fixed colour across every state", function()
  local w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Threshold" })
  local needleColor = w.mods.theme.color.needle
  mock.setValue(ID_RSSI, 70); refresh(w)
  assertEq(w.ui.needle.props.color, needleColor, "normal")
  mock.setValue(ID_RSSI, 45); refresh(w, 2)
  assertEq(w.frame.colorKey, "warning")
  assertEq(w.ui.needle.props.color, needleColor,
    "needle stays fixed in WARN, does not turn amber")
  mock.setValue(ID_RSSI, 10); refresh(w, 2)
  assertEq(w.frame.colorKey, "critical")
  assertEq(w.ui.needle.props.color, needleColor,
    "needle stays fixed in CRIT, does not turn red")
  assertEq(w.ui.needleTip.props.color, needleColor, "tip matches the body")
end)

test("style choice controls the needle", function()
  local w = newWidget(nil, { Source = ID_RSSI, Style = "Arc" })
  assertEq(w.ui.needle, nil, "arc style has no needle")
  w = newWidget(nil, { Source = ID_RSSI, Style = "Needle" })
  assertTrue(w.ui.needle ~= nil, "needle style draws one")
  -- A line, not a triangle: LvglWidgetTriangle::refresh frees and rebuilds
  -- the canvas on every angle change (~24 KB/frame of heap churn under
  -- damping), while LvglWidgetLine::refresh only rewrites the points
  -- (AUDIT.md P2-1).
  assertEq(w.ui.needle.kind, "line", "needle must be a line, not a triangle")
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

test("P1-5: gradient with Warn == Crit follows the state, not the red end", function()
  -- Equal thresholds give the gradient ramp a zero span, so normalize() used
  -- to pin EVERY value to the red end (grad0) - even one deep in the normal
  -- band. A warn == crit configuration is a sharp cliff: the band colour
  -- says which side the value is on.
  local w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Gradient",
                             Scale = "Manual", Warn = 50, Crit = 50 })
  mock.setValue(ID_RSSI, 10); refresh(w, 2)
  assertEq(w.frame.colorKey, "critical", "below the 50/50 cliff is critical")
  mock.setValue(ID_RSSI, 90); refresh(w, 2)
  assertEq(w.frame.colorKey, "normal", "above the 50/50 cliff is normal")
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

test("G-4: out-of-range thresholds do not leave the dial born critical", function()
  -- Manual -120..0 dBm scale (the RSSI-in-dBm range the presets define) with
  -- the 0..100 defaults Warn=55/Crit=35: both thresholds sit above Max=0, so
  -- the old clamp collapsed them onto 0 and the whole dial was one critical
  -- band with zero-width warning/normal bands.
  local w = newWidget(nil, { Source = ID_STICK, Scale = "Manual",
                             Min = -120, Max = 0, ColorMode = "Threshold" })
  assertTrue(w.config.warn < 0 and w.config.crit < 0,
    "thresholds derived into the range, got warn=" .. w.config.warn ..
    " crit=" .. w.config.crit)
  assertTrue(w.config.crit < w.config.warn,
    "critical must stay below warning, got " .. w.config.crit .. "/" ..
    w.config.warn)
  assertTrue(w.ranges[1].from < w.ranges[1].to,
    "the critical band has real width")

  mock.setValue(ID_STICK, -20)      -- mid-normal on the derived scale
  refresh(w, 2)
  assertEq(w.frame.colorKey, "normal", "-20 dBm must not be critical")
  mock.setValue(ID_STICK, -110)     -- deep in the noise floor
  refresh(w, 2)
  assertEq(w.frame.colorKey, "critical", "-110 dBm is critical")
end)

test("G-6: the value and unit stay inside the ring in balanced zones", function()
  -- The value text lives inside the dial circle, whose clear interior at the
  -- text band's height is a CHORD of the ring - narrower than the dial box.
  -- Centring the value+unit group against the box width used to push the
  -- unit (and wide values) onto the ring (AUDIT.md G-6).
  local zones = {
    { 60, 60 }, { 80, 60 }, { 100, 100 }, { 128, 96 }, { 160, 160 },
    { 200, 160 }, { 200, 200 }, { 260, 220 },
  }
  for _, z in ipairs(zones) do
    local zone = { x = 0, y = 0, w = z[1], h = z[2] }
    local w = newWidget(zone, { Source = ID_RSSI })
    refresh(w)
    local L = w.layout
    if L.orientation == "balanced" then
      local clearR = L.radius - math.floor(L.trackThickness / 2)
      local labels = { w.ui.valueLabel, w.ui.unitLabel }
      for _, label in ipairs(labels) do
        if label then
          local p = label.props
          local x1, y1 = p.x, p.y
          local x2, y2 = x1 + (p.w or 0), y1 + (p.h or 0)
          for _, c in ipairs({ { x1, y1 }, { x2, y1 }, { x1, y2 }, { x2, y2 } }) do
            local dx, dy = c[1] - L.cx, c[2] - L.cy
            assertTrue(dx * dx + dy * dy <= clearR * clearR,
              string.format("%dx%d %q corner (%d,%d) outside the r=%d ring",
                z[1], z[2], tostring(p.text), c[1], c[2], clearR))
          end
        end
      end
    end
  end
end)

test("P1-1: the visible value + unit group stays centred at any digit count", function()
  -- The value box is reserved at the widest sample's width and the ink is
  -- CENTRED inside it, with the unit re-anchored to the ink's real edge on
  -- every value change (layout.placeValue / renderer.anchorUnit) - so the
  -- visible group must land on the same centre whether the value is "7" or
  -- "78", not just the RESERVED box (Tanda 5 review 3.4).
  local w = newWidget(nil, { Source = ID_RSSI })
  local theme = w.mods.theme
  local function groupCenter()
    local L = w.layout
    local vp = w.ui.valueLabel.props
    local vw = theme.textWidth(vp.text, vp.font)
    local vLeft = L.valueBox.x + math.floor((L.valueBox.w - vw) / 2)
    local right = vLeft + vw
    if w.ui.unitLabel then
      local up = w.ui.unitLabel.props
      right = up.x + theme.textWidth(up.text, up.font)
    end
    return (vLeft + right) / 2
  end
  mock.setValue(ID_RSSI, 7)
  refresh(w)
  local c1 = groupCenter()
  mock.setValue(ID_RSSI, 78)
  refresh(w)
  local c2 = groupCenter()
  assertTrue(math.abs(c1 - c2) <= 2,
    string.format("group centre moved %.1f px between digit counts",
      math.abs(c1 - c2)))
end)

test("G-7: the min/max row stays inside the ring and off the scale labels", function()
  -- In large balanced zones the min/max row hangs below the value INSIDE the
  -- dial circle, competing for the same lower band as the scale end labels
  -- and the history marks (AUDIT.md G-7). The row is clipped to the ring's
  -- chord at its depth, so it must neither cross the ring nor touch the
  -- "0"/"100" labels at the arc ends.
  local zone = { x = 0, y = 0, w = 200, h = 200 }   -- large: scale labels on
  local w = newWidget(zone, { Source = ID_RSSI, ShowMinMax = "Markers + text" })
  mock.setValue(ID_RSSI_MIN, 31)
  mock.setValue(ID_RSSI_MAX, 92)
  refresh(w)
  assertTrue(w.ui.minText ~= nil, "large zone shows the min/max text")
  assertTrue(w.ui.scaleMin ~= nil, "scale end labels built")

  local L = w.layout
  local clearR = L.radius - math.floor(L.trackThickness / 2)
  local function boxInside(label)
    local p = label.props
    local x1, y1 = p.x, p.y
    local x2, y2 = x1 + (p.w or 0), y1 + (p.h or 0)
    for _, c in ipairs({ { x1, y1 }, { x2, y1 }, { x1, y2 }, { x2, y2 } }) do
      local dx, dy = c[1] - L.cx, c[2] - L.cy
      assertTrue(dx * dx + dy * dy <= clearR * clearR,
        string.format("%q corner (%d,%d) outside the r=%d ring",
          tostring(p.text), c[1], c[2], clearR))
    end
  end
  boxInside(w.ui.minText)
  boxInside(w.ui.maxText)

  local theme = w.mods.theme
  local function ink(label)
    local p = label.props
    local tw = theme.textWidth(p.text or "", p.font)
    local x = p.x
    if p.align == CENTER then x = p.x + math.floor((p.w - tw) / 2)
    elseif p.align == RIGHT then x = p.x + p.w - tw end
    return { x1 = x, y1 = p.y, x2 = x + tw, y2 = p.y + (p.h or 0) }
  end
  local function overlap(a, b)
    local ix = math.min(a.x2, b.x2) - math.max(a.x1, b.x1)
    local iy = math.min(a.y2, b.y2) - math.max(a.y1, b.y1)
    return ix > 0 and iy > 0
  end
  assertTrue(not overlap(ink(w.ui.minText), ink(w.ui.scaleMin)),
    "min text must not overlap the lower scale label")
  assertTrue(not overlap(ink(w.ui.maxText), ink(w.ui.scaleMax)),
    "max text must not overlap the upper scale label")
end)

test("G-8: the scale end labels sit clear of their end ticks", function()
  -- The old placement centred a fixed 30 px box on the point just past the
  -- end tick, so the label's inner half retreated over the tick ("100" read
  -- as "f00", AUDIT.md G-8). The box is now pushed outward along the radial
  -- until its nearest corner sits past the tick's outer radius: every corner
  -- of the label must therefore be farther from the dial centre than the
  -- tick's outermost point.
  local zone = { x = 0, y = 0, w = 200, h = 200 }   -- large, 270 deg default
  local w = newWidget(zone, {})
  refresh(w)
  assertTrue(w.ui.scaleMin ~= nil, "scale end labels shown on large zones")
  local L = w.layout
  local function clearsTick(label)
    local p = label.props
    local minD2 = math.huge
    local corners = {
      { p.x, p.y }, { p.x + p.w, p.y },
      { p.x, p.y + p.h }, { p.x + p.w, p.y + p.h },
    }
    for _, c in ipairs(corners) do
      local d2 = (c[1] - L.cx) ^ 2 + (c[2] - L.cy) ^ 2
      if d2 < minD2 then minD2 = d2 end
    end
    assertTrue(minD2 >= L.tickOuter ^ 2,
      string.format("%q label must clear the end tick", tostring(p.text)))
  end
  clearsTick(w.ui.scaleMin)
  clearsTick(w.ui.scaleMax)
end)

test("G-9: scale labels size their box to the text, not a fixed width", function()
  -- The scale label box used a hard-coded 30 px width regardless of the
  -- string, so "20000.00" was clipped to "2000" (AUDIT.md G-9). The box must
  -- be exactly as wide as its measured text.
  local w = newWidget({ x = 0, y = 0, w = 200, h = 200 },
    { Scale = "Manual", Min = 0, Max = 20000, Precision = "2" })
  refresh(w)
  assertEq(w.ui.scaleMax.props.text, "20000.00",
    "precision 2 must render both decimals on the label")
  local maxP = w.ui.scaleMax.props
  local expect = w.mods.theme.textWidth(maxP.text, maxP.font)
  assertEq(maxP.w, expect,
    "the max label box must be as wide as its text, not a fixed 30 px")
  assertTrue(maxP.w > w.ui.scaleMin.props.w,
    "a longer label gets a wider box")
end)

test("P1-2: a short bar keeps a real-height state row", function()
  -- The state row below the bar used to be sized from the NAME font, which
  -- the short-bar paths zeroed, so STALE/NO LINK/WARN/CRIT vanished from
  -- exactly the zones where they matter most (AUDIT.md P1-2). The row must
  -- be as tall as the state font in every short bar that can physically
  -- hold it, and no visible label may have a degenerate box.
  local heights = { 40, 44, 46, 50, 55, 60 }
  for _, h in ipairs(heights) do
    local w = newWidget({ x = 0, y = 0, w = 300, h = h },
      { Source = ID_RSSI, Style = "Bar" })
    local L = w.layout
    assertEq(L.style, "bar", "a 300-wide strip is a bar")
    assertTrue(not L.showState or L.stateBox.h > 0,
      string.format("h=%d: a shown state must have height > 0, got %d",
        h, L.stateBox.h))
    if h >= 44 then
      assertTrue(L.showState,
        string.format("h=%d: the state must stay visible in a short bar", h))
    end
    for _, o in ipairs(mock.objects()) do
      if o.visible and o.kind == "label" then
        assertTrue(o.props.h > 0 and o.props.w > 0,
          string.format("h=%d: visible label %q has a degenerate box",
            h, tostring(o.props.text)))
      end
    end
  end

  -- the semantic payload: a critical value renders CRIT in a 44 px bar
  local w = newWidget({ x = 0, y = 0, w = 300, h = 44 },
    { Source = ID_RSSI, Style = "Bar" })
  assertTrue(w.ui.stateLabel ~= nil, "state label built at h=44")
  mock.setValue(ID_RSSI, 10)
  refresh(w, 2)
  assertEq(w.frame.stateStr, "CRIT",
    "the critical state must render in a 44 px bar")
end)

test("P1-11: low-is-good bars mark the warning boundary too", function()
  -- On a low-is-good scale (normal -> warning -> critical) the warning
  -- threshold is the `to` of the NORMAL band, which the old condition
  -- skipped; a temperature bar drew 1 mark where the dial draws 2 rails
  -- (AUDIT.md P1-11).
  local w = newWidget({ x = 0, y = 0, w = 300, h = 70 },
    { Source = ID_TEMP_T1, Style = "Bar", ColorMode = "Threshold" })
  local marks = w.ui.marks
  assertTrue(marks ~= nil, "threshold marks built")
  assertEq(#marks, 2,
    "low-is-good bar must mark the warning AND critical boundaries, got "
    .. tostring(marks and #marks or 0) .. " mark(s)")
  local L, cfg = w.layout, w.config
  local function xAt(v)
    local t = (v - cfg.min) / (cfg.max - cfg.min)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return L.bar.x + math.floor(L.bar.w * t + 0.5)
  end
  local xs = {}
  for _, m in ipairs(marks) do xs[#xs + 1] = math.floor(m.props.pts[1][1]) end
  assertTrue(xs[1] == xAt(cfg.warn) or xs[2] == xAt(cfg.warn),
    "one mark must sit at the warning boundary")
  assertTrue(xs[1] == xAt(cfg.crit) or xs[2] == xAt(cfg.crit),
    "one mark must sit at the critical boundary")
end)

test("P1-10: the bar chips and pulses its state like the dial", function()
  -- A bar used to signal critical only by the fill colour: no state chip and
  -- no ~1 Hz pulse (AUDIT.md P1-10). Both are the dial's signalling and must
  -- behave identically in bar zones.
  local w = newWidget({ x = 0, y = 0, w = 300, h = 70 },
    { Source = ID_RSSI, Style = "Bar" })
  assertTrue(w.ui.chip ~= nil, "the bar builds a state chip")
  assertTrue(objIndex(w.ui.stateLabel) > objIndex(w.ui.chip),
    "the state text must paint on top of the chip")
  mock.setValue(ID_RSSI, 10)          -- critical (crit=35)
  refresh(w)
  assertEq(w.frame.stateStr, "CRIT")
  assertTrue(w.frame.chipShown, "the chip shows for CRIT")
  local L = w.layout
  assertEq(w.ui.chip.props.w,
    w.mods.theme.textWidth("CRIT", L.stateFont) + L.chipPad * 2,
    "the chip hugs the CRIT text")
  assertEq(w.ui.chip.props.x + w.ui.chip.props.w,
    L.stateBox.x + L.stateBox.w, "the chip is right-aligned to the state box")

  -- pulse: the fill alternates pulse/full at ~1 Hz (50 * 10 ms ticks)
  refresh(w, 10)     -- 500 ms: first toggle is due
  assertTrue(w.frame.pulse, "critical pulses after 500 ms")
  assertEq(w.ui.fill.props.opacity, w.mods.theme.opacity.pulse,
    "the pulse trough dims the fill")
  refresh(w, 10)     -- another 500 ms: back to full
  assertEq(w.frame.pulse, false)
  assertEq(w.ui.fill.props.opacity, w.mods.theme.opacity.full)
end)

-- ---- designer review repair plan (dev/design-review-response.md) --------

test("P-A: the needle is a tapered three-line blade with a solid hub", function()
  local w = newWidget(nil, { Source = ID_RSSI, Style = "Needle" })
  refresh(w)
  assertTrue(w.ui.needle ~= nil and w.ui.needleMid ~= nil
    and w.ui.needleTip ~= nil, "base, mid and tip all built")
  assertEq(w.ui.tail, nil, "the counterweight/tail is gone (P0-1)")
  assertEq(w.ui.needle.kind, "line", "needle base stays a line (P2-1)")
  assertEq(w.ui.needleMid.kind, "line", "needle mid stays a line (P2-1)")
  assertEq(w.ui.needleTip.kind, "line", "needle tip stays a line (P2-1)")
  assertEq(w.ui.needle.props.rounded, 1, "rounded caps blend the seams")
  assertEq(w.ui.needleMid.props.rounded, 1, "rounded caps blend the seams")
  assertEq(w.ui.needleTip.props.rounded, 1, "rounded caps blend the seams")
  local L = w.layout
  assertTrue(L.needleInner < L.needleBodyOuter
    and L.needleBodyOuter < L.needleMidOuter
    and L.needleMidOuter < L.needleOuter,
    "base, mid and tip divide the reach in order")
  -- three DECREASING widths, not two (Tanda 5, owner feedback: two steps
  -- read as a paddle with a toothpick glued to the end)
  assertTrue(w.ui.needle.props.thickness > w.ui.needleMid.props.thickness,
    "mid is thinner than the base")
  assertTrue(w.ui.needleMid.props.thickness > w.ui.needleTip.props.thickness
    or w.ui.needleMid.props.thickness == w.ui.needleTip.props.thickness,
    "tip is no thicker than mid (may collapse to equal at micro sizes)")
  assertTrue(w.ui.needleTip.props.thickness >= w.mods.theme.px(2)
    and w.ui.needleTip.props.thickness <= w.mods.theme.px(4),
    "tip thickness in the 2-4 px band")
  local p = w.ui.needleTip.props.pts[2]
  local d = math.sqrt((p[1] - L.cx) ^ 2 + (p[2] - L.cy) ^ 2)
  assertTrue(math.abs(d - L.needleOuter) <= 1.5, "the tip reaches the scale")
  assertEq(w.ui.pivotDot, nil, "no accent dot remains on the pivot")
  assertEq(w.ui.pivotRing.kind, "circle", "the hub is a single circle")
  assertEq(w.ui.pivotRing.props.filled, 1, "the hub is solid")
  assertEq(w.ui.pivotRing.props.color, COLOR_THEME_SECONDARY1,
    "the hub uses the neutral rail role")
  assertTrue(objIndex(w.ui.pivotRing) > objIndex(w.ui.needle),
    "the hub paints on top of the needle")
end)

test("P-A: the tip sweeps with the body on every angle change", function()
  local w = newWidget(nil, { Source = ID_RSSI, Style = "Needle" })
  mock.setValue(ID_RSSI, 20)
  refresh(w, 2)               -- angle moves to ~the 20% position
  local L = w.layout
  local a = w.frame.angle
  local function endRadius(line)
    local pt = line.props.pts[2]
    return math.sqrt((pt[1] - L.cx) ^ 2 + (pt[2] - L.cy) ^ 2)
  end
  assertTrue(math.abs(endRadius(w.ui.needleTip) - L.needleOuter) <= 1.5,
    "tip points at the scale at angle " .. tostring(a))
  assertTrue(w.ui.needleTip.visible, "the tip shows with the needle")
  assertTrue(w.ui.needleMid.visible, "the mid segment shows with the needle")
  assertTrue(math.abs(endRadius(w.ui.needleMid) - L.needleMidOuter) <= 1.5,
    "mid segment sweeps to its own radius at angle " .. tostring(a))
end)

test("P0-2: the value cell clears the hub and the needle at critical angles", function()
  local w = newWidget({ x = 0, y = 0, w = 200, h = 160 }, { Source = ID_RSSI })
  mock.setValue(ID_RSSI, 22)          -- critical: the needle sweeps up-left
  refresh(w)
  local L = w.layout
  -- the cell used to start inside the pivot's vertical span (measured 6 px
  -- of overlap at 200x160); it must now start at or below the hub's lower edge
  assertTrue(L.valueBox.y >= L.cy + L.pivotRadius,
    "value cell top clears the hub (P0-2)")
  local cell = { x1 = L.valueBox.x, y1 = L.valueBox.y,
                 x2 = L.valueBox.x + L.valueBox.w, y2 = L.valueBox.y + L.valueBox.h }
  local function distToCell(x, y)
    local cx = math.max(cell.x1, math.min(x, cell.x2))
    local cy = math.max(cell.y1, math.min(y, cell.y2))
    return math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
  end
  local function segGap(pts)
    local best = math.huge
    for i = 0, 60 do
      local t = i / 60
      local x = pts[1][1] + (pts[2][1] - pts[1][1]) * t
      local y = pts[1][2] + (pts[2][2] - pts[1][2]) * t
      best = math.min(best, distToCell(x, y))
    end
    return best
  end
  assertTrue(segGap(w.ui.needle.props.pts) >= 2,
    "needle body keeps >= 2 px from the value cell at the critical angle")
  assertTrue(segGap(w.ui.needleMid.props.pts) >= 2,
    "needle mid keeps >= 2 px from the value cell at the critical angle")
  assertTrue(segGap(w.ui.needleTip.props.pts) >= 2,
    "needle tip keeps >= 2 px from the value cell at the critical angle")
end)

test("P0-4: the needle stops short of the state chip instead of crossing it", function()
  local w = newWidget(ZONE, { Source = ID_RSSI, ColorMode = "Rail" })
  mock.setValue(ID_RSSI, 50)   -- default Rail sweep: needle points straight up, WARN
  refresh(w, 40)
  assertTrue(w.frame.chipShown, "WARN chip is shown at this value")
  local box = w.frame.chipBox
  assertTrue(box ~= nil, "the chip's footprint is recorded for the clamp")
  local function insideBox(x, y)
    return x >= box.x and x <= box.x + box.w and y >= box.y and y <= box.y + box.h
  end
  local function crossesChip(pts)
    for i = 0, 40 do
      local t = i / 40
      local x = pts[1][1] + (pts[2][1] - pts[1][1]) * t
      local y = pts[1][2] + (pts[2][2] - pts[1][2]) * t
      if insideBox(x, y) then return true end
    end
    return false
  end
  assertTrue(not crossesChip(w.ui.needle.props.pts),
    "needle body stays clear of the chip (Tanda 5 review 3.12)")
  assertTrue(not crossesChip(w.ui.needleMid.props.pts),
    "needle mid stays clear of the chip (Tanda 5 review 3.12)")
  assertTrue(not crossesChip(w.ui.needleTip.props.pts),
    "needle tip stays clear of the chip (Tanda 5 review 3.12)")
end)

test("P-B: the state chip gains padding, vertical centring and an edge", function()
  local w = newWidget(nil, { Source = ID_RSSI })
  mock.setValue(ID_RSSI, 10)   -- critical -> CRIT chip
  refresh(w)
  local L = w.layout
  local theme = w.mods.theme
  assertEq(L.chipPad, theme.px(7), "side padding 4 -> 7 px")
  assertEq(L.chipHeight, theme.fontHeight(L.stateFont) + theme.px(6),
    "pill height stateH + 6")
  local off = math.floor((L.chipHeight - theme.fontHeight(L.stateFont)) / 2)
  assertEq(w.ui.chip.props.y, L.stateBox.y - off,
    "the pill is vertically centred on the state text")
  assertTrue(w.ui.chipEdge ~= nil, "the pill has a 1 px outline")
  local edge = w.ui.chipEdge.props
  assertEq(edge.x, w.ui.chip.props.x - 1, "edge hugs the pill left")
  assertEq(edge.y, w.ui.chip.props.y - 1, "edge hugs the pill top")
  assertEq(edge.w, w.ui.chip.props.w + 2, "edge hugs the pill right")
  assertEq(edge.h, w.ui.chip.props.h + 2, "edge hugs the pill bottom")
  assertEq(edge.color, COLOR_THEME_SECONDARY1, "edge in the lighter label role")
  assertTrue(objIndex(w.ui.chipEdge) < objIndex(w.ui.chip)
    and objIndex(w.ui.chip) < objIndex(w.ui.stateLabel),
    "paint order: edge, pill, text")
end)

test("P-B: the bar chip gets the same padding, centring and edge", function()
  local w = newWidget({ x = 0, y = 0, w = 300, h = 70 },
    { Source = ID_RSSI, Style = "Bar" })
  mock.setValue(ID_RSSI, 10)
  refresh(w)
  local L = w.layout
  assertEq(L.chipPad, w.mods.theme.px(7), "bar chipPad matches the dial")
  assertTrue(w.ui.chipEdge ~= nil, "bar pill has the 1 px outline")
  local off = math.floor((L.chipHeight - w.mods.theme.fontHeight(L.stateFont)) / 2)
  assertEq(w.ui.chip.props.y, L.stateBox.y - off, "bar pill is centred")
end)

test("ShowChip=Off hides the state pill even when critical", function()
  local w = newWidget(nil, { Source = ID_RSSI, ShowChip = false })
  mock.setValue(ID_RSSI, 5)
  refresh(w)
  assertEq(w.data.state, "critical")
  assertEq(w.ui.chip, nil, "chip never built when ShowChip is off")
  assertEq(w.ui.chipEdge, nil)
  assertEq(w.ui.stateLabel, nil)
end)

test("ShowChip defaults to on", function()
  local w = newWidget(nil, { Source = ID_RSSI })
  mock.setValue(ID_RSSI, 5)
  refresh(w)
  assertEq(w.data.state, "critical")
  assertTrue(w.ui.chip ~= nil, "chip built by default")
  assertEq(w.frame.stateStr, "CRIT")
end)

test("P-C: ticks are at least 2 px and use the lighter role", function()
  for _, z in ipairs({ { 60, 60 }, { 100, 100 }, { 200, 200 } }) do
    local w = newWidget({ x = 0, y = 0, w = z[1], h = z[2] }, {})
    refresh(w)
    assertTrue(w.layout.tickThickness >= 2,
      string.format("%dx%d ticks must be >= 2 px", z[1], z[2]))
  end
  local w = newWidget(nil, {})
  refresh(w)
  assertEq(w.ui.ticks[1].props.color, COLOR_THEME_SECONDARY1,
    "tick colour remapped to the lighter role")
  assertEq(w.ui.ticks[1].props.thickness, w.layout.tickThickness,
    "major ticks draw at the layout thickness")
end)

test("P-D: the unit sits one ramp step below the value where space allows", function()
  local w = newWidget(nil, { Source = ID_RSSI })
  refresh(w)
  assertEq(w.layout.unitFont, w.mods.theme.smallerFont(w.layout.valueFont, 1),
    "the unit font is exactly one ramp step below the value font")
end)

test("P-E: rail bands dim behind the value arc and clear it by the rail gap", function()
  local w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Rail",
                             Scale = "Manual", Min = 0, Max = 100,
                             Warn = 60, Crit = 30 })
  refresh(w)
  assertTrue(w.ui.rails ~= nil, "rail bands built in Rail mode")
  assertTrue(#w.ui.rails >= 2, "warning and critical bands present")
  for _, r in ipairs(w.ui.rails) do
    assertEq(r.props.bgOpacity, w.mods.theme.opacity.railBand,
      "rail bands draw at reduced opacity")
  end
  local L = w.layout
  assertEq(L.railRadius, L.radius + math.floor(L.trackThickness / 2)
    + L.railThickness + w.mods.theme.px(1),
    "the rail band radius clears the value arc by the gap")
end)

test("P1-3: the passive rail bands dim further only while critical", function()
  local w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Rail",
                             Scale = "Manual", Min = 0, Max = 100,
                             Warn = 60, Crit = 30 })
  mock.setValue(ID_RSSI, 70)   -- normal: reference opacity, same as P-E
  refresh(w)
  for _, r in ipairs(w.ui.rails) do
    assertEq(r.props.bgOpacity, w.mods.theme.opacity.railBand,
      "rail bands stay at the reference opacity outside critical")
  end
  mock.setValue(ID_RSSI, 10)   -- critical: dim one step further
  refresh(w)
  assertEq(w.data.state, "critical", "value 10 is below Crit=30")
  for _, r in ipairs(w.ui.rails) do
    assertEq(r.props.bgOpacity, w.mods.theme.opacity.railBandCrit,
      "rail bands dim further once critical (Tanda 5 review 3.6)")
  end
end)

test("P2-9: the neutral track sits at ~35% opacity", function()
  local w = newWidget(nil, { Source = ID_RSSI })
  assertEq(w.mods.theme.opacity.rail, 90, "track opacity 25% -> ~35%")
end)

test("P2-10: the name label drops to the smallest font", function()
  local w = newWidget(nil, { Source = ID_RSSI })
  assertEq(w.layout.nameFont, w.mods.theme.FONTS.XXS,
    "name uses the smallest font")
end)

test("P1-3: an elapsed timer fits its value box", function()
  -- widestSample used to reserve "00:00:00" (8 chars); an elapsed timer
  -- prints "-00:01:05" (9 chars) and wrapped inside the box, clipping the
  -- leading digit (AUDIT.md P1-3). The sample now reserves the signed
  -- width, so the box must hold the rendered string at the value font.
  local w = newWidget({ x = 0, y = 0, w = 200, h = 200 }, { Source = ID_TIMER1 })
  mock.setValue(ID_TIMER1, -65)
  refresh(w)
  local L = w.layout
  assertEq(w.frame.valueStr, "-00:01:05")
  local tw = w.mods.theme.textWidth(w.frame.valueStr, L.valueFont)
  assertTrue(L.valueBox.w >= tw,
    string.format("timer box %d must hold %d px of text", L.valueBox.w, tw))
end)

test("P1-4: an out-of-scale value fits its value box", function()
  -- The value is deliberately not clamped to the scale, so it can be one
  -- character wider than the range's widest string; the sample now reserves
  -- that slack and the box must hold the rendered text (AUDIT.md P1-4).
  local w = newWidget({ x = 0, y = 0, w = 200, h = 200 },
    { Source = ID_RSSI, Scale = "Manual", Min = 0, Max = 100 })
  mock.setValue(ID_RSSI, 1500)
  refresh(w)
  local L = w.layout
  assertEq(w.frame.valueStr, "1500")
  local tw = w.mods.theme.textWidth(w.frame.valueStr, L.valueFont)
  assertTrue(L.valueBox.w >= tw,
    string.format("value box %d must hold %d px of text", L.valueBox.w, tw))
end)

test("G-10: at 360 degrees the name stays inside the ring and off the value", function()
  -- The 360 deg branch hangs the name under the value inside the circle; the
  -- G-6 band repositioning lifted that pair clear of the ring, where the
  -- name used to cross it (AUDIT.md G-10). Both must stay inside the clear
  -- radius and not overlap each other.
  local zone = { x = 0, y = 0, w = 200, h = 200 }
  local w = newWidget(zone, { Source = ID_RSSI, Sweep = "360 deg" })
  refresh(w)
  local L = w.layout
  assertTrue(w.ui.nameLabel ~= nil, "the name shows at 360 degrees")
  assertTrue(not L.showScale, "no scale labels on a closed ring")
  local clearR = L.radius - math.floor(L.trackThickness / 2)
  local theme = w.mods.theme
  local function ink(label)
    local p = label.props
    local tw = theme.textWidth(p.text or "", p.font)
    local x = p.x
    if p.align == CENTER then x = p.x + math.floor((p.w - tw) / 2)
    elseif p.align == RIGHT then x = p.x + p.w - tw end
    return { x1 = x, y1 = p.y, x2 = x + tw, y2 = p.y + (p.h or 0) }
  end
  local function inside(ib)
    for _, c in ipairs({ { ib.x1, ib.y1 }, { ib.x2, ib.y1 },
                         { ib.x1, ib.y2 }, { ib.x2, ib.y2 } }) do
      local d2 = (c[1] - L.cx) ^ 2 + (c[2] - L.cy) ^ 2
      assertTrue(d2 <= clearR ^ 2,
        string.format("text corner (%d,%d) outside the r=%d ring",
          c[1], c[2], clearR))
    end
  end
  inside(ink(w.ui.valueLabel))
  inside(ink(w.ui.nameLabel))
  local vi, ni = ink(w.ui.valueLabel), ink(w.ui.nameLabel)
  assertTrue(not (math.min(vi.x2, ni.x2) > math.max(vi.x1, ni.x1)
    and math.min(vi.y2, ni.y2) > math.max(vi.y1, ni.y1)),
    "name and value must not overlap at 360 degrees")
end)

test("G-13: a wide horizontal zone grows the dial to the full height", function()
  -- The horizontal branch used to cap the dial at half the zone width
  -- (`min(w*0.5, h)`), stranding up to ~73 % of a 480x272 zone empty; the
  -- dial now takes the full height and leaves the text column only the
  -- width it needs (AUDIT.md G-13).
  local zone = { x = 0, y = 0, w = 480, h = 272 }
  local w = newWidget(zone, { Source = ID_RSSI })
  local L = w.layout
  assertEq(L.orientation, "horizontal")
  local ringD = (L.radius + math.floor(L.trackThickness / 2)) * 2
  assertTrue(ringD > math.floor(math.min(zone.w, zone.h) * 0.8),
    string.format("the ring (%d) must use most of the short side (272)", ringD))
  local theme = w.mods.theme
  local p = w.ui.valueLabel.props
  assertTrue(theme.textWidth(tostring(p.text), p.font) <= p.w,
    "the value must fit the (narrower) text column")
end)

test("G-11: at 180 degrees both scale labels clear their end ticks", function()
  -- The 180 deg arc ends at 9/3 o'clock, exactly at the extreme marks; on a
  -- zone just wide enough for the dial, the zone clamp used to pull the max
  -- label back over its tick ("100" crossed by a line). The label now slides
  -- along the tangent to clear it (AUDIT.md G-11).
  local w = newWidget({ x = 0, y = 0, w = 200, h = 200 },
    { Source = ID_RSSI, Sweep = "180 deg" })
  refresh(w)
  local theme = w.mods.theme
  local function ink(label)
    local p = label.props
    local tw = theme.textWidth(p.text or "", p.font)
    local x = p.x
    if p.align == CENTER then x = p.x + math.floor((p.w - tw) / 2)
    elseif p.align == RIGHT then x = p.x + p.w - tw end
    return { x1 = x, y1 = p.y, x2 = x + tw, y2 = p.y + (p.h or 0) }
  end
  local function tickCrossesLabel(tick, lb)
    local pts = tick.props.pts
    for t = 0, 1, 0.05 do
      local x = pts[1][1] + (pts[2][1] - pts[1][1]) * t
      local y = pts[1][2] + (pts[2][2] - pts[1][2]) * t
      if x >= lb.x1 and x <= lb.x2 and y >= lb.y1 and y <= lb.y2 then
        return true
      end
    end
    return false
  end
  local ticks = w.ui.ticks
  assertTrue(not tickCrossesLabel(ticks[1], ink(w.ui.scaleMin)),
    "the min scale label must clear its end tick at 180 deg")
  assertTrue(not tickCrossesLabel(ticks[#ticks], ink(w.ui.scaleMax)),
    "the max scale label must clear its end tick at 180 deg")
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

test("G-3: an elapsed timer says WARN, not CRIT in warning colour", function()
  -- A negative timer value is below the 0..100 default scale, so data.state
  -- is "critical" - but colorKey classifies an elapsed countdown as warning
  -- (the official Value widget behaviour). stateText must follow colorKey:
  -- a CRIT chip painted amber is the worst of both worlds.
  local w = newWidget(nil, { Source = ID_TIMER1 })
  mock.setValue(ID_TIMER1, -12)
  refresh(w)
  assertEq(w.data.state, "critical", "the raw state is critical (below scale min)")
  assertEq(w.frame.stateStr, "WARN", "the chip says what the arc paints")
  assertEq(w.ui.stateLabel.props.color, COLOR_THEME_WARNING)
  assertEq(w.ui.chip.visible, true, "the chip is shown for the warning")
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

test("P1-1: losing the link mid-pulse leaves the gauge muted, not at full", function()
  -- The pulse toggles the arc between pulse (150) and full (255). Losing the
  -- link while the pulse is in its TROUGH used to make updatePulse() restore
  -- T.opacity.full over the muted 120 that applyColors() had just set - a
  -- dimmed gauge stuck at full opacity until the next colour change.
  local w = newWidget(nil, { Source = ID_RSSI, ColorMode = "Threshold" })
  mock.setValue(ID_RSSI, 10)          -- critical band
  refresh(w)
  mock.advance(6000)                  -- >= 500 ticks: pulse enters its trough
  w.mod.refresh(w)
  assertTrue(w.frame.pulse, "in the pulse trough")
  assertEq(w.ui.valueArc.props.opacity, w.mods.theme.opacity.pulse)

  mock.setValue(ID_RSSI, nil)
  mock.sim.rssi = 0                   -- link down while the pulse is low
  refresh(w)
  assertEq(w.frame.colorKey, "muted")
  assertEq(w.ui.valueArc.props.opacity, w.mods.theme.opacity.muted,
    "the muted gauge must stay dim, not snap to full opacity")
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
