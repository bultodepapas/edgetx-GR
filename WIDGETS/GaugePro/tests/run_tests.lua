-- Unit tests for the pure GaugePro modules (geometry, ranges, presets,
-- options, format, smoothing). Stock Lua 5.3, no firmware needed.
--
-- Usage: lua5.3 tests/run_tests.lua <widget-dir>

local widgetDir = arg[1] or "./"

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local function load(name)
  return assert(loadfile(widgetDir .. name .. ".lua"))()
end

local geometry = load("geometry")
local ranges = load("ranges")
local presets = load("presets")
local options = load("options")
local format = load("format")
local smoothing = load("smoothing")
local theme = load("theme")
local barStyle = load("bar_style")
local barFaces = load("bar_faces")
barStyle.setup(theme, presets)

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

local function assertNear(actual, expected, tol, label)
  if math.abs(actual - expected) > (tol or 0.001) then
    error(string.format("%s: expected ~%s, got %s", label or "assertNear",
      tostring(expected), tostring(actual)), 2)
  end
end

local function assertTrue(cond, label)
  if not cond then error((label or "assertTrue") .. " failed", 2) end
end

-- ---- geometry ------------------------------------------------------------

test("clamp bounds", function()
  assertEq(geometry.clamp(5, 0, 10), 5)
  assertEq(geometry.clamp(-1, 0, 10), 0)
  assertEq(geometry.clamp(11, 0, 10), 10)
end)

test("normalize spans and clamps", function()
  assertNear(geometry.normalize(50, 0, 100), 0.5)
  assertNear(geometry.normalize(-10, 0, 100), 0)
  assertNear(geometry.normalize(150, 0, 100), 1)
  assertEq(geometry.normalize(5, 5, 5), 0, "degenerate range")
end)

test("normalize mirrors an inverted range", function()
  -- descending scale: min 100 -> max 0 means 100 sits at t = 0
  assertNear(geometry.normalize(100, 100, 0), 0)
  assertNear(geometry.normalize(0, 100, 0), 1)
  assertNear(geometry.normalize(75, 100, 0), 0.25)
end)

test("valueToAngle across the sweep", function()
  assertNear(geometry.valueToAngle(0, 0, 100, 135, 270), 135)
  assertNear(geometry.valueToAngle(100, 0, 100, 135, 270), 405)
  assertNear(geometry.valueToAngle(50, 0, 100, 135, 270), 270)
end)

test("pointOnCircle uses LVGL angles", function()
  local x, y = geometry.pointOnCircle(100, 100, 10, 0)
  assertNear(x, 110); assertNear(y, 100)
  x, y = geometry.pointOnCircle(100, 100, 10, 90)
  assertNear(x, 100); assertNear(y, 110)   -- 90 deg is DOWN (y grows down)
end)

test("linePoints returns {x,y} pairs", function()
  local pts = geometry.linePoints(50, 50, 10, 20, 0)
  assertEq(#pts, 2)
  assertEq(#pts[1], 2)
  assertEq(type(pts[2][1]), "number")
end)

test("F-11: linePointsInto mutates a persistent buffer in place", function()
  -- Phase 5.1: the needle writes into a reused buffer instead of
  -- allocating a fresh pts table per frame. The binding copies the values
  -- out on every set and retains no reference (LvglWidgetLine::getPts), so
  -- in-place mutation is safe - but the buffer must keep its shape: #buf
  -- stays 2 (lua_rawlen drives getPts) and every value matches linePoints.
  local buf = { { 0, 0 }, { 0, 0 } }
  local pts = geometry.linePoints(50, 50, 10, 20, 37)
  local ret = geometry.linePointsInto(buf, 50, 50, 10, 20, 37)
  assertTrue(ret == buf, "returns the caller's buffer")
  assertEq(#buf, 2, "the point count never grows")
  for i = 1, 2 do
    assertNear(buf[i][1], pts[i][1], 0.001, "x" .. i)
    assertNear(buf[i][2], pts[i][2], 0.001, "y" .. i)
  end
  -- a second write overwrites the same slots, no growth, same result
  geometry.linePointsInto(buf, 50, 50, 10, 20, 100)
  assertEq(#buf, 2, "still two points after a second write")
  local pts2 = geometry.linePoints(50, 50, 10, 20, 100)
  assertNear(buf[1][1], pts2[1][1], 0.001, "overwritten x1")
  assertNear(buf[2][2], pts2[2][2], 0.001, "overwritten y2")
end)

test("barFill maps value to width", function()
  assertEq(geometry.barFill(200, 50, 0, 100), 100)
  assertEq(geometry.barFill(200, 0, 0, 100), 0)
  assertEq(geometry.barFill(200, 999, 0, 100), 200)
end)

-- ---- ranges --------------------------------------------------------------

test("ranges high-is-good ordering", function()
  local r = ranges.build(0, 100, 55, 35, true)
  assertEq(r[1].role, "critical"); assertEq(r[1].to, 35)
  assertEq(r[2].role, "warning")
  assertEq(r[3].role, "normal"); assertEq(r[3].from, 55)
end)

test("ranges low-is-good ordering", function()
  local r = ranges.build(0, 120, 70, 90, false)
  assertEq(r[1].role, "normal")
  assertEq(r[3].role, "critical"); assertEq(r[3].from, 90)
end)

test("ranges clamp thresholds into the span", function()
  local r = ranges.build(0, 100, 500, -500, true)
  assertEq(r[1].from, 0); assertEq(r[3].to, 100)
end)

test("ranges warn == crit collapses the warning band", function()
  local r = ranges.build(0, 100, 50, 50, true)
  assertEq(r[2].from, r[2].to)
end)

test("G-4: both thresholds out of range derive at the presets' proportions", function()
  -- Manual -120..0 dBm scale with the 0..100 defaults (55/35): clamping would
  -- collapse both onto Max and make the whole dial one critical band. The
  -- helper must derive them at 35 % / 55 % of the span instead.
  local w, c = ranges.saneThresholds(-120, 0, 55, 35, true)
  assertNear(c, -78, 0.01, "critical at 35 % of the span")
  assertNear(w, -54, 0.01, "warning at 55 % of the span")

  -- low-is-good mirrors the bands against the top of the scale
  w, c = ranges.saneThresholds(-120, 0, 55, 35, false)
  assertNear(w, -66, 0.01, "low-is-good warning")
  assertNear(c, -42, 0.01, "low-is-good critical")

  -- in-range thresholds pass through untouched
  local a, b = ranges.saneThresholds(0, 100, 55, 35, true)
  assertEq(a, 55); assertEq(b, 35)

  -- an equal pair INSIDE the range is a deliberate sharp cliff, not a mistake
  a, b = ranges.saneThresholds(0, 100, 50, 50, true)
  assertEq(a, 50); assertEq(b, 50)

  -- one threshold on each side is still the old clamp's job
  a, b = ranges.saneThresholds(0, 100, 500, -500, true)
  assertEq(a, 500); assertEq(b, -500)
end)

test("F-3: saneThresholds normalises min/max order", function()
  -- build() normalises a descending scale (Min > Max); saneThresholds does
  -- not, so the guard fires on perfectly valid thresholds and derives them
  -- over a NEGATIVE span - warn/crit inverted, a warning value rendered
  -- red and firing the critical tone (Tanda 6 F-3).
  local aw, ac = ranges.saneThresholds(0, 100, 55, 35, true)
  assertEq(aw, 55, "ascending warn untouched")
  assertEq(ac, 35, "ascending crit untouched")
  local dw, dc = ranges.saneThresholds(100, 0, 55, 35, true)
  assertEq(dw, 55, "descending warn untouched")
  assertEq(dc, 35, "descending crit untouched")
  -- low-is-good mirror: the same normalisation, mirrored bands
  local lw, lc = ranges.saneThresholds(100, 0, 55, 35, false)
  assertEq(lw, 55, "descending low-is-good warn")
  assertEq(lc, 35, "descending low-is-good crit")
end)

test("determineState inside and outside", function()
  local r = ranges.build(0, 100, 55, 35, true)
  assertEq(ranges.determineState(80, r), "normal")
  assertEq(ranges.determineState(45, r), "warning")
  assertEq(ranges.determineState(10, r), "critical")
  assertEq(ranges.determineState(-50, r), "critical", "below min")
  assertEq(ranges.determineState(200, r), "normal", "above max")
end)

test("hysteresis holds an improving state", function()
  local r = ranges.build(0, 100, 55, 35, true)
  local db = ranges.deadband(0, 100)      -- 2 units
  assertEq(ranges.determineState(56, r, "warning", db), "warning")
  assertEq(ranges.determineState(58, r, "warning", db), "normal")
end)

test("hysteresis never delays a degrading state", function()
  local r = ranges.build(0, 100, 55, 35, true)
  local db = ranges.deadband(0, 100)
  assertEq(ranges.determineState(54, r, "normal", db), "warning")
  assertEq(ranges.determineState(34, r, "warning", db), "critical")
end)

test("hysteresis does not oscillate on a noisy ramp", function()
  local r = ranges.build(0, 100, 55, 35, true)
  local db = ranges.deadband(0, 100)
  local state, flips = "normal", 0
  local noise = { 0.4, -0.5, 0.3, -0.4, 0.5, -0.3 }
  for i = 0, 30 do
    local v = 56 - i * 0.1 + noise[(i % 6) + 1]
    local new = ranges.determineState(v, r, state, db)
    if new ~= state then flips = flips + 1 end
    state = new
  end
  assertTrue(flips <= 1, "flips = " .. flips)
end)

-- ---- presets -------------------------------------------------------------

test("preset match by name is punctuation insensitive", function()
  assertEq(presets.find({ name = "RQly%" }).maximum, 100)
  assertEq(presets.find({ name = "rssi" }).warning, 55)
end)

test("preset falls back to the unit", function()
  local p = presets.find({ name = "Zork", unit = 11 })
  assertEq(p.highIsGood, false, "temperature is low-is-good")
end)

test("P1-7: an unknown voltage sensor does not inherit battery detection", function()
  -- Only an exact NAME match (RxBt, Cels, ...) is trustworthy evidence that
  -- a sensor IS a battery; matching by unit alone just means "some voltage
  -- source", e.g. a BEC or servo rail sensor with a name the widget has
  -- never seen.
  local p = presets.find({ name = "VBEC", unit = 1 })
  assertTrue(p ~= nil, "unit fallback still finds a preset")
  assertEq(p.battery, nil, "must not inherit battery detection from RxBt")
  assertEq(p.cellsTable, nil, "must not inherit cell-table detection either")

  -- The real RxBt preset (exact name match) keeps its battery flag.
  local named = presets.find({ name = "RxBt", unit = 1 })
  assertEq(named.battery, true, "exact name match keeps battery detection")

  -- find() must not have mutated the shared preset table as a side effect.
  local again = presets.find({ name = "VBEC", unit = 1 })
  assertEq(again.battery, nil, "repeated lookups stay clean")
  assertEq(presets.find({ name = "RxBt", unit = 1 }).battery, true,
    "the named preset itself was not corrupted by the unit-fallback copy")
end)

test("preset misses stay nil", function()
  assertEq(presets.find({ name = "Zork" }), nil)
  assertEq(presets.find(nil), nil)
end)

test("cell count detection", function()
  assertEq(presets.cellCount(16.4), 4)
  assertEq(presets.cellCount(4.1), 1)
  assertEq(presets.cellCount(25.0), 6)
end)

test("state of charge follows the discharge curve", function()
  assertEq(presets.percentFromCell(4.2), 100)
  assertEq(presets.percentFromCell(3.3), 0)
  assertTrue(presets.percentFromCell(3.8) > 40, "mid pack")
  assertTrue(presets.percentFromCell(3.0, "liion") > 0, "li-ion floor lower")
end)

test("pack range scales with the cell count", function()
  local p = presets.packRange(4)
  assertNear(p.maximum, 16.8, 0.01)
  assertNear(p.warning, 14.8, 0.01)
end)

-- ---- options (the wire format) -------------------------------------------

local DEFS = {
  { key = "Src", type = SOURCE, field = "source", since = 211, default = 0 },
  { key = "Min", type = VALUE, field = "min", since = 211, default = 0,
    min = -10, max = 10 },
  { key = "Flag", type = BOOL, field = "flag", since = 211, default = 1 },
  { key = "Pick", type = CHOICE, field = "pick", since = 211, default = 2,
    choices = { "a", "b", "c" } },
  { key = "Extra", type = CHOICE, field = "extra", since = 212, default = 1,
    choices = { "x", "y" } },
}

test("choice values are 1-based integers", function()
  assertEq(options.parse(DEFS, { Pick = 3 }).pick, 3)
end)

test("a stored zero choice falls back to the default", function()
  assertEq(options.parse(DEFS, { Pick = 0 }).pick, 2)
end)

test("choice labels never map to a valid index (the 1.0 bug)", function()
  -- the firmware cannot deliver a string here; if one ever did, it must fall
  -- back to the default rather than silently selecting the first entry
  assertEq(options.parse(DEFS, { Pick = "c" }).pick, 2)
end)

test("bool and value conversion", function()
  local cfg = options.parse(DEFS, { Flag = 0, Min = -7 })
  assertEq(cfg.flag, false)
  assertEq(cfg.min, -7)
end)

test("missing options fall back to declared defaults", function()
  local cfg = options.parse(DEFS, {})
  assertEq(cfg.pick, 2)
  assertEq(cfg.flag, true)
  assertEq(cfg.extra, 1, "a 2.12-only option still has a value on 2.11")
end)

test("capacity follows the firmware version", function()
  mock.sim.version = { "2.11.0", "sim", 2, 11, 0 }
  assertEq(options.capacity(), 10)
  mock.sim.version = { "2.12.0", "sim", 2, 12, 0 }
  assertEq(options.capacity(), 50)
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0 }
  assertEq(options.capacity(), 50)
end)

-- ---- bar personalization contracts --------------------------------------

local function visualConfig(overrides)
  local cfg = {
    barPreset = 2, barFace = 1, barDir = 1, barOrigin = 1,
    barSize = 1, barEnds = 1, segments = 1, segGap = 1,
    palette = 1, warnClr = theme.color.warn, critClr = theme.color.crit,
    trackClr = COLOR_THEME_SECONDARY1, surface = 1,
    panelClr = COLOR_THEME_SECONDARY3, contrast = 1,
    accent = theme.color.accent,
  }
  for k, v in pairs(overrides or {}) do cfg[k] = v end
  return cfg
end

local function visualWidget(name, zone)
  return { source = { name = name or "Unknown", unit = nil },
           zone = zone or { w = 300, h = 70 } }
end

test("bar preset default resolves the pixel-compatible Classic Rail", function()
  local visual, palette = barStyle.resolve(visualWidget("RSSI"), visualConfig())
  assertEq(visual.preset, "classic-rail")
  assertEq(visual.face, "continuous")
  assertEq(visual.direction, "horizontal")
  assertEq(visual.thickness, "medium")
  assertEq(visual.ends, "round")
  assertEq(visual.surface, "transparent")
  assertEq(palette.mode, "classic")
  assertEq(palette.normal, theme.color.accent)
  assertEq(palette.warning, theme.color.warn)
  assertEq(palette.critical, theme.color.crit)
  assertTrue(palette.calibrated, "default classic ramp remains calibrated")
end)

test("explicit bar overrides win without mutating stored config", function()
  local cfg = visualConfig{
    barPreset = 4, barFace = 3, barDir = 3, barSize = 2,
    segments = 7, segGap = 4, surface = 2,
  }
  local before = {}
  for k, v in pairs(cfg) do before[k] = v end
  local visual = barStyle.resolve(visualWidget("Cels", { w = 400, h = 120 }), cfg)
  assertEq(visual.face, "blocks")
  assertEq(visual.direction, "vertical")
  assertEq(visual.thickness, "thin")
  assertEq(visual.segments, 24)
  assertEq(visual.gap, "wide")
  assertEq(visual.surface, "transparent")
  for k, v in pairs(before) do assertEq(cfg[k], v, "config mutated at " .. k) end
end)

test("Auto Source uses stable semantic hints only for appearance", function()
  local signal = barStyle.resolve(visualWidget("RSSI"),
                                  visualConfig{ barPreset = 1 })
  local battery = barStyle.resolve(visualWidget("Cels"),
                                   visualConfig{ barPreset = 1 })
  local control = barStyle.resolve(visualWidget("Thr"),
                                   visualConfig{ barPreset = 1 })
  assertEq(signal.face, "ticks")
  assertEq(signal.sourceHint, "signal")
  assertEq(battery.face, "hex")
  assertEq(battery.sourceHint, "battery")
  assertEq(control.face, "dual-rail")
  assertEq(control.origin, "zero")
  -- The sensor preset remains the owner of range truth.
  assertEq(presets.find({ name = "RSSI" }).minimum, 0)
  assertEq(presets.find({ name = "RSSI" }).maximum, 100)
end)

test("compact variants cap detail and report the downgrade", function()
  local visual = barStyle.resolve(visualWidget("RSSI", { w = 74, h = 30 }),
    visualConfig{ barPreset = 6, segments = 7, surface = 3 })
  assertEq(visual.profile.family, "micro")
  assertEq(visual.face, "ticks")
  assertEq(visual.segments, 10)
  assertEq(visual.surface, "transparent")
  assertTrue(#visual.downgrades >= 2, "segment and surface downgrades reported")
  assertTrue(visual.compactDescription ~= "", "preset compact form documented")
end)

test("hex requests are capped by the 40-object face budget", function()
  local visual = barStyle.resolve(visualWidget("Cels", { w = 600, h = 180 }),
    visualConfig{ barPreset = 4, segments = 7 })
  assertEq(visual.face, "hex")
  assertEq(visual.segments, 10)
  assertEq(visual.downgrades[1], "segments-object-budget")
end)

test("bar configuration signatures are stable and complete", function()
  local a = visualConfig()
  local b = visualConfig()
  assertEq(barStyle.configSignature(a), barStyle.configSignature(b))
  b.barEnds = 3
  assertTrue(barStyle.configSignature(a) ~= barStyle.configSignature(b),
             "end shape participates")
  b = visualConfig(); b.panelClr = lcd.RGB(1, 2, 3)
  assertTrue(barStyle.configSignature(a) ~= barStyle.configSignature(b),
             "custom panel participates")
end)

test("Theme Adaptive preserves authored roles and analyzes separation", function()
  mock.setThemeColors()
  local _, palette = barStyle.resolve(visualWidget(), visualConfig{ palette = 3 })
  assertEq(palette.normal, COLOR_THEME_ACTIVE)
  assertEq(palette.warning, COLOR_THEME_WARNING)
  assertEq(palette.critical, theme.color.crit)
  assertTrue(type(palette.analysis.normalWarningDistance) == "number")
  assertTrue(type(palette.analysis.normalTrackContrast) == "number")
end)

test("palette signatures invalidate when runtime theme inks change", function()
  mock.setThemeColors()
  local _, before = barStyle.resolve(visualWidget(), visualConfig())
  mock.setThemeColors({
    [COLOR_THEME_PRIMARY1] = { 240, 240, 240 },
    [COLOR_THEME_PRIMARY2] = { 12, 12, 12 },
    [COLOR_THEME_SECONDARY1] = { 80, 20, 120 },
  })
  local _, after = barStyle.resolve(visualWidget(), visualConfig())
  assertTrue(before.signature ~= after.signature,
             "resolved theme roles participate in the signature")
  mock.setThemeColors()
end)

test("Custom Three preserves all user severity anchors exactly", function()
  local normal = lcd.RGB(110, 20, 180)
  local warning = lcd.RGB(245, 220, 20)
  local critical = lcd.RGB(10, 180, 230)
  local _, p = barStyle.resolve(visualWidget(), visualConfig{
    palette = 4, accent = normal, warnClr = warning, critClr = critical,
  })
  assertEq(p.normal, normal)
  assertEq(p.warning, warning)
  assertEq(p.critical, critical)
  assertEq(theme.paletteColor(p, 0, 20), critical)
  assertEq(theme.paletteColor(p, 1, 20), normal)
end)

test("Custom Two preserves endpoints and derives a luminance-aware midpoint", function()
  local normal = lcd.RGB(120, 20, 190)
  local critical = lcd.RGB(250, 220, 20)
  local _, p = barStyle.resolve(visualWidget(), visualConfig{
    palette = 5, accent = normal, critClr = critical,
  })
  assertEq(p.normal, normal)
  assertEq(p.critical, critical)
  assertEq(p.warning, theme.mixColor(critical, normal, 0.5))
  assertTrue(p.warning ~= normal and p.warning ~= critical)
end)

test("palette interpolation cache is quantized and bounded", function()
  theme.clearPaletteCache()
  for i = 1, 30 do
    local p = {
      normal = lcd.RGB(i, 140, 80), warning = theme.color.warn,
      critical = theme.color.crit, signature = "test-" .. i,
    }
    for step = 0, 100 do theme.paletteColor(p, step / 100, 24) end
  end
  local stats = theme.paletteCacheStats()
  assertTrue(stats.signatures <= stats.maximum, "signature cache bounded")
  assertTrue(stats.entries <= stats.maximum * 25, "step cache bounded")
end)

test("badge ink cache stays bounded across custom palette edits", function()
  for i = 1, 80 do
    local fill = lcd.RGB(i * 3 % 255, i * 7 % 255, i * 11 % 255)
    theme.labelOn(fill, {
      inkDark = COLOR_THEME_PRIMARY1, inkLite = COLOR_THEME_PRIMARY2,
      signature = "ink-edit-" .. i,
    })
  end
  local stats = theme.inkCacheStats()
  assertTrue(stats.entries <= stats.maximum)
end)

test("color analysis utilities resolve RGB and theme flags", function()
  -- RGB flags are RGB565, so nominal white resolves to 248/252/248.
  assertNear(theme.contrastRatio(lcd.RGB(0, 0, 0), lcd.RGB(255, 255, 255)),
             20.27, 0.1)
  assertNear(theme.colorDistance(lcd.RGB(10, 10, 10), lcd.RGB(10, 10, 10)),
             0, 0.001)
  assertTrue(theme.colorDistance(COLOR_THEME_ACTIVE, COLOR_THEME_WARNING) > 0)
end)

test("every bar face exposes the retained interface and a hard ceiling", function()
  local methods = { "supports", "estimateObjects", "build", "update",
                    "applyPalette", "setVisible" }
  for _, name in ipairs(barFaces.ORDER) do
    local face = barFaces.REGISTRY[name]
    assertEq(face.name, name)
    assertTrue(face.hardCeiling <= 40, name .. " object ceiling")
    assertEq(face.ownsAlerts, false, name .. " may not own alerts")
    for _, method in ipairs(methods) do
      assertEq(type(face[method]), "function", name .. "." .. method)
    end
    local maximumEffective = (name == "hex") and 10 or 24
    assertTrue(face.estimateObjects({}, { segments = maximumEffective })
                 <= face.hardCeiling,
               name .. " estimate exceeds its hard ceiling")
  end
end)

test("pending faces select the explicit Continuous production fallback", function()
  local face, reason = barFaces.select("hex", {}, { segments = 8 })
  assertEq(face.name, "continuous")
  assertTrue(string.find(reason, "face%-phase%-pending") ~= nil)
  local ready, noReason = barFaces.select("continuous", {}, {})
  assertEq(ready.name, "continuous")
  assertEq(noReason, nil)
  local vertical, verticalReason = barFaces.select("continuous", {}, {
    direction = "vertical", origin = "scale-low",
  })
  assertEq(vertical.name, "continuous")
  assertTrue(string.find(verticalReason, "orientation%-phase%-pending") ~= nil)
end)

-- ---- format --------------------------------------------------------------

test("number formatting honours precision", function()
  assertEq(format.number(3.14159, 0), "3")
  assertEq(format.number(3.14159, 1), "3.1")
  assertEq(format.number(3.14159, 2), "3.14")
  assertEq(format.number(nil, 0), "-")
end)

test("timers format as hh:mm:ss with a sign", function()
  assertEq(format.hms(3661), "01:01:01")
  assertEq(format.hms(-65), "-00:01:05")
end)

test("widest sample covers the scale plus one character of slack", function()
  local widget = {
    config = { min = 0, max = 100, precision = 1 },
    source = { isTimer = false },
  }
  assertEq(format.widestSample(widget), "-100.0")
  widget.source.isTimer = true
  assertEq(format.widestSample(widget), "-00:00:00")
end)

test("F-10: RAMP degrades without a hole when a font constant is missing", function()
  -- A firmware that lacks XXLSIZE must yield a six-font ramp with NO nil
  -- entry: #RAMP used to report the full length regardless, so fitFont
  -- indexed fontHeight(nil) and heightCache[nil] = h raised `table index
  -- is nil` on the first layout pass (Tanda 6 F-10). theme.lua is loaded
  -- in an isolated environment without XXLSIZE.
  local env = {}
  for k, v in pairs(_ENV or _G) do env[k] = v end
  env.XXLSIZE = nil
  local chunk = assert(loadfile(widgetDir .. "theme.lua", "t", env))
  local isolatedTheme = chunk()
  assertEq(#isolatedTheme.RAMP, 6, "XXLSIZE missing -> 6 usable fonts")
  assertEq(isolatedTheme.RAMP[1], isolatedTheme.FONTS.XL,
    "the ramp starts at the largest font that actually exists")
  for i = 1, #isolatedTheme.RAMP do
    assertTrue(isolatedTheme.RAMP[i] ~= nil,
               "RAMP[" .. i .. "] must not be a hole")
  end
end)

-- ---- smoothing -----------------------------------------------------------

test("damping maps to a time constant", function()
  assertEq(smoothing.tau(0), 0, "0 disables the filter")
  assertEq(smoothing.tau(4), 160)
  assertEq(smoothing.tau(99), 360, "clamped")
end)

test("smoothing is frame-rate independent", function()
  local widget = { config = { tau = 160 }, smooth = {} }
  mock.sim.ticks = 0
  assertEq(smoothing.step(widget, 10), 10, "first sample snaps")
  for _ = 1, 10 do
    mock.advance(20)
    smoothing.step(widget, 0)
  end
  local fast = widget.smooth.value
  widget.smooth = {}
  mock.sim.ticks = 0
  smoothing.step(widget, 10)
  mock.advance(200)
  smoothing.step(widget, 0)
  assertNear(widget.smooth.value, fast, 0.5, "same elapsed time, same result")
end)

test("smoothing uses a millisecond time base", function()
  -- getTime() counts 10 ms ticks: 100 ticks is 1 s, which at tau = 160 ms
  -- must be essentially converged (1.0 mixed ticks and ms here)
  local widget = { config = { tau = 160 }, smooth = {} }
  mock.sim.ticks = 0
  smoothing.step(widget, 100)
  mock.advance(1000)
  smoothing.step(widget, 0)
  assertTrue(widget.smooth.value < 1, "converged, got " ..
             tostring(widget.smooth.value))
end)

print(string.format("-- %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
