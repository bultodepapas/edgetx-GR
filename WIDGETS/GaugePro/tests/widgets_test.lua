-- Split-widget contracts for GaugeDialPro and GaugeBarPro.
-- Usage: lua5.3 tests/widgets_test.lua <GaugeCore-source-dir>

local coreDir = arg[1] or "./"
if string.sub(coreDir, -1) ~= "/" then coreDir = coreDir .. "/" end
local repoRoot = coreDir .. "../../"

local mock = dofile(coreDir .. "tests/mock_env.lua")
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

local function assertTrue(value, label)
  if not value then error((label or "assertTrue") .. " failed", 2) end
end

local function loadFront(family, version, injectedCore)
  mock.sim.version = version or { "3.0.0", "sim", 3, 0, 0, "edgetx" }
  local path = repoRoot .. "WIDGETS/Gauge" .. family .. "Pro/main.lua"
  local chunk = assert(loadfile(path, "bt", _ENV or _G))
  return chunk({ corePath = injectedCore or coreDir })
end

local function setupRadio()
  mock.reset()
  mock.addField(3072, "RSSI", 17)
  mock.addField(3073, "RSSI-", 17)
  mock.addField(3074, "RSSI+", 17)
  mock.sim.sensors[0] = { name = "RSSI", prec = 0, unit = 17 }
  mock.setValue(3072, 70)
end

local function optionsFor(front, overrides)
  overrides = overrides or {}
  if overrides.Source == nil then overrides.Source = 3072 end
  return mock.makeOptions(front.defs, overrides)
end

local function createUpdated(front, zone, overrides, widgetPath)
  setupRadio()
  local opts = optionsFor(front, overrides)
  local widget = front.create(zone, opts, widgetPath or "/WIDGETS/PathTrap/")
  front.update(widget, opts)
  return widget, opts
end

local function sameValue(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not sameValue(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function assertDefEqual(a, b, slot)
  for _, key in ipairs({ "key", "type", "field", "since", "default",
                          "min", "max", "choices" }) do
    assertTrue(sameValue(a[key], b[key]),
      string.format("shared slot %d differs at %s", slot, key))
  end
end

test("front names and core contract are stable", function()
  local dial, bar = loadFront("Dial"), loadFront("Bar")
  assertEq(dial.name, "DialPro")
  assertEq(bar.name, "BarPro")
  assertEq(dial.translate(dial.name), "Gauge Dial Pro")
  assertEq(bar.translate(bar.name), "Gauge Bar Pro")
  assertEq(dial.family, "dial")
  assertEq(bar.family, "bar")
  assertEq(dial.coreApi, 1)
  assertEq(bar.coreApi, 1)
end)

test("2.12 contracts contain 24 Dial and 42 Bar slots", function()
  local dial, bar = loadFront("Dial"), loadFront("Bar")
  assertEq(#dial.defs, 24, "GaugeDialPro defs")
  assertEq(#bar.defs, 42, "GaugeBarPro defs")
  assertEq(#dial.options, 24, "GaugeDialPro options")
  assertEq(#bar.options, 42, "GaugeBarPro options")
end)

test("2.11 exposes exactly ten meaningful slots", function()
  local v211 = { "2.11.0", "sim", 2, 11, 0, "edgetx" }
  local dial, bar = loadFront("Dial", v211), loadFront("Bar", v211)
  assertEq(#dial.options, 10, "GaugeDialPro 2.11 options")
  assertEq(#bar.options, 10, "GaugeBarPro 2.11 options")
  assertEq(dial.options[10][1], "DialStyle")
  assertEq(bar.options[10][1], "BarPreset")
end)

test("shared slots 1-9 are identical", function()
  local dial, bar = loadFront("Dial"), loadFront("Bar")
  for i = 1, 9 do assertDefEqual(dial.defs[i], bar.defs[i], i) end
end)

test("complete option goldens and translations are frozen", function()
  local dial, bar = loadFront("Dial"), loadFront("Bar")
  local dialKeys = {
    "Source", "Min", "Max", "Warn", "Crit", "HighGood", "ColorMode",
    "Precision", "ShowMinMax", "DialStyle", "Sweep", "Accent", "Label",
    "Suffix", "Scale", "Damping", "Cells", "Battery", "Alerts", "AlertSw",
    "Delay", "Vibrate", "ResetSw", "ShowChip",
  }
  local barKeys = {
    "Source", "Min", "Max", "Warn", "Crit", "HighGood", "ColorMode",
    "Precision", "ShowMinMax", "BarPreset", "Accent", "Label", "Suffix",
    "Scale", "Damping", "Cells", "Battery", "Alerts", "AlertSw", "Delay",
    "Vibrate", "ResetSw", "ShowChip", "BarFace", "BarDir", "BarOrigin",
    "BarSize", "BarEnds", "Segments", "SegGap", "Palette", "WarnClr",
    "CritClr", "TrackClr", "Surface", "PanelClr", "Contrast", "Motion",
    "BarHead", "ScaleMarks", "ValuePos", "LabelPos",
  }
  for i, key in ipairs(dialKeys) do
    assertEq(dial.defs[i].key, key, "Dial slot " .. i)
  end
  for i, key in ipairs(barKeys) do
    assertEq(bar.defs[i].key, key, "Bar slot " .. i)
  end
  for _, front in ipairs({ dial, bar }) do
    assertTrue(#front.name <= 10, front.name .. " name length")
    assertTrue(front.translate(front.name) ~= nil, front.name .. " translation")
    for i, def in ipairs(front.defs) do
      assertTrue(#def.key <= 10, front.name .. " key too long at " .. i)
      assertTrue(front.translate(def.key) ~= nil,
        front.name .. " missing translation for " .. def.key)
      if def.type == CHOICE then
        assertTrue(type(def.default) == "number" and def.default >= 1
          and def.default <= #def.choices,
          front.name .. " invalid 1-based default for " .. def.key)
      end
    end
  end
end)

test("family-only options do not leak", function()
  local dial, bar = loadFront("Dial"), loadFront("Bar")
  local dialKeys, barKeys = {}, {}
  for _, d in ipairs(dial.defs) do dialKeys[d.key] = true end
  for _, d in ipairs(bar.defs) do barKeys[d.key] = true end
  assertTrue(dialKeys.DialStyle and dialKeys.Sweep)
  assertTrue(not dialKeys.BarPreset and not dialKeys.BarFace
    and not dialKeys.Motion)
  assertTrue(barKeys.BarPreset and barKeys.BarFace and barKeys.Motion)
  assertTrue(not barKeys.DialStyle and not barKeys.Sweep)
end)

test("firmware widgetPath never redirects GaugeCore", function()
  local original, loaded = loadScript, {}
  loadScript = function(path, mode)
    loaded[#loaded + 1] = path
    return original(path, mode)
  end
  local ok, err = pcall(function()
    local dial = loadFront("Dial")
    createUpdated(dial, { x = 0, y = 0, w = 200, h = 160 }, nil,
      "/WIDGETS/GaugeDialPro/")
  end)
  loadScript = original
  if not ok then error(err, 0) end
  assertTrue(#loaded > 1, "core and modules were loaded")
  for _, path in ipairs(loaded) do
    assertEq(string.sub(path, 1, #coreDir), coreDir,
      "load escaped injected core")
  end
end)

test("Dial skips every Bar-only runtime module", function()
  local original, loaded = loadScript, {}
  loadScript = function(path, mode)
    loaded[path] = true
    return original(path, mode)
  end
  local ok, err = pcall(function()
    local dial = loadFront("Dial")
    createUpdated(dial, { x = 0, y = 0, w = 200, h = 160 })
  end)
  loadScript = original
  if not ok then error(err, 0) end
  for _, name in ipairs({ "motion", "bar_style", "bar_faces", "bar" }) do
    assertTrue(not loaded[coreDir .. name .. ".lua"],
      "GaugeDialPro loaded " .. name)
  end
  assertTrue(loaded[coreDir .. "telemetry.lua"], "common telemetry loaded")
  assertTrue(loaded[coreDir .. "ui_core.lua"], "shared UI core loaded")
  assertTrue(loaded[coreDir .. "dial_layout.lua"], "dial layout loaded")
  assertTrue(loaded[coreDir .. "dial_renderer.lua"], "dial renderer loaded")
  assertTrue(not loaded[coreDir .. "bar_layout.lua"],
    "GaugeDialPro loaded bar layout")
end)

test("Bar loads its presentation stack", function()
  local original, loaded = loadScript, {}
  loadScript = function(path, mode)
    loaded[path] = true
    return original(path, mode)
  end
  local ok, err = pcall(function()
    local bar = loadFront("Bar")
    createUpdated(bar, { x = 0, y = 0, w = 200, h = 160 })
  end)
  loadScript = original
  if not ok then error(err, 0) end
  for _, name in ipairs({ "motion", "bar_style", "bar_faces", "bar" }) do
    assertTrue(loaded[coreDir .. name .. ".lua"],
      "GaugeBarPro skipped " .. name)
  end
  assertTrue(loaded[coreDir .. "bar_layout.lua"], "bar layout loaded")
  assertTrue(loaded[coreDir .. "ui_core.lua"], "shared UI core loaded")
  assertTrue(not loaded[coreDir .. "dial_layout.lua"],
    "GaugeBarPro loaded dial layout")
  assertTrue(not loaded[coreDir .. "dial_renderer.lua"],
    "GaugeBarPro loaded dial renderer")
end)

test("missing core error identifies frontend and path", function()
  local missing = coreDir .. "does-not-exist/"
  local dial = loadFront("Dial", nil, missing)
  local ok, err = pcall(dial.create, { x = 0, y = 0, w = 200, h = 160 }, {},
    "/WIDGETS/GaugeDialPro/")
  assertTrue(not ok, "missing core must fail on first create")
  assertTrue(string.find(tostring(err), "DialPro", 1, true) ~= nil)
  assertTrue(string.find(tostring(err), missing, 1, true) ~= nil)
end)

test("GaugeCore rejects incompatible API and invalid family", function()
  local appChunk = assert(loadfile(coreDir .. "app.lua", "bt", _ENV or _G))
  local ok, err = pcall(appChunk, {
    name = "DialPro", family = "dial", coreApi = 999, defs = {},
  })
  assertTrue(not ok, "coreApi mismatch must fail")
  assertTrue(string.find(tostring(err), "expected 999, found 1", 1, true)
    ~= nil, "coreApi diagnostic includes both versions")

  ok, err = pcall(appChunk, {
    name = "DialPro", family = "clock", coreApi = 1, defs = {},
  })
  assertTrue(not ok, "unknown family must fail")
  assertTrue(string.find(tostring(err), "invalid GaugeCore family", 1, true)
    ~= nil, "family diagnostic")
end)

test("GaugeDialPro stays dial in a wide bar-shaped zone", function()
  local dial = loadFront("Dial")
  local widget = createUpdated(dial, { x = 0, y = 0, w = 400, h = 80 })
  assertEq(widget.family, "dial")
  assertEq(widget.layout.style, "dial")
  assertEq(widget.config.barPreset, nil)
end)

test("GaugeBarPro stays bar in a portrait dial-shaped zone", function()
  local bar = loadFront("Bar")
  local widget = createUpdated(bar, { x = 0, y = 0, w = 200, h = 160 })
  assertEq(widget.family, "bar")
  assertEq(widget.layout.style, "bar")
  assertEq(widget.config.sweep, nil)
end)

test("DialStyle preserves Auto Needle Arc anatomy", function()
  for style, expected in pairs({ Needle = true, Arc = false }) do
    local dial = loadFront("Dial")
    local widget = createUpdated(dial, { x = 0, y = 0, w = 200, h = 160 },
      { DialStyle = style })
    assertEq(widget.layout.showNeedle, expected, style)
  end
  local dial = loadFront("Dial")
  local widget = createUpdated(dial, { x = 0, y = 0, w = 200, h = 160 },
    { DialStyle = "Auto" })
  assertEq(widget.layout.style, "dial")
end)

test("instances of one frontend share app and module tables", function()
  setupRadio()
  local dial = loadFront("Dial")
  local opts = optionsFor(dial)
  local a = dial.create({ x = 0, y = 0, w = 200, h = 160 }, opts,
    "/WIDGETS/GaugeDialPro/")
  local b = dial.create({ x = 0, y = 0, w = 200, h = 160 }, opts,
    "/WIDGETS/GaugeDialPro/")
  assertTrue(a.app == b.app, "sharedApp identity")
  assertTrue(a.mods == b.mods, "module table identity")
end)

test("shared telemetry and state semantics stay equal", function()
  local function sample(family)
    local front = loadFront(family)
    local widget = createUpdated(front, { x = 0, y = 0, w = 220, h = 160 },
      { Min = 0, Max = 100, Warn = 55, Crit = 35, HighGood = true })
    mock.setValue(3072, 25)
    for _ = 1, 2 do
      mock.advance(50)
      front.refresh(widget)
    end
    return {
      availability = widget.data.availability,
      value = widget.data.displayValue,
      state = widget.data.state,
      unit = widget.unitText,
      minimum = widget.config.min,
      maximum = widget.config.max,
    }
  end
  local dial, bar = sample("Dial"), sample("Bar")
  assertTrue(sameValue(dial, bar), "Dial/Bar shared semantics diverged")
end)

test("both frontends retain their object tree for 200 stable frames", function()
  for _, family in ipairs({ "Dial", "Bar" }) do
    local front = loadFront(family)
    local widget = createUpdated(front,
      (family == "Dial") and { x = 0, y = 0, w = 200, h = 160 }
        or { x = 0, y = 0, w = 300, h = 70 })
    assertTrue(widget.rebuildPending, family .. " initial build was not staged")
    front.refresh(widget)
    local count = mock.objectCount()
    for i = 1, 200 do
      mock.setValue(3072, (i % 2 == 0) and 70 or 80)
      mock.advance(50)
      front.refresh(widget)
      assertEq(mock.objectCount(), count,
        family .. " created objects at frame " .. i)
    end
  end
end)

print(string.format("-- %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
