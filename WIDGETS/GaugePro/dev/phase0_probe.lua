-- GaugePro Phase 0 feasibility and known-gap probe.
--
-- This is deliberately not a production renderer. It exercises the exact
-- Lua/LVGL binding exposed by the checked-out firmware and turns the risky
-- visual ideas into measured object/instruction budgets before Phase 1 owns
-- any new option or Phase 2 owns any new bar face.
--
-- Usage: lua dev/phase0_probe.lua ./

local widgetDir = arg[1] or "./"
if string.sub(widgetDir, -1) ~= "/" and string.sub(widgetDir, -1) ~= "\\" then
  widgetDir = widgetDir .. "/"
end

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local function assertTrue(value, message)
  if not value then error(message or "assertion failed", 2) end
end

local function countVisible()
  local n = 0
  for _, obj in ipairs(mock.objects()) do
    if obj.visible then n = n + 1 end
  end
  return n
end

local hookFires = 0
local function hook() hookFires = hookFires + 1 end
local function measured(fn)
  hookFires = 0
  debug.sethook(hook, "", 200)
  local ok, err = pcall(fn)
  debug.sethook()
  if not ok then error(err, 2) end
  return hookFires, hookFires * 200
end

local function setupSource()
  mock.reset()
  lvgl.LCD_SCALE = 1.0
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0, "edgetx" }
  mock.addField(3072, "RSSI", 17)
  mock.addField(3073, "RSSI-", 17)
  mock.addField(3074, "RSSI+", 17)
  mock.sim.sensors[0] = { name = "RSSI", prec = 0, unit = 17 }
  mock.setValue(3072, 22)
  mock.setValue(3073, 18)
  mock.setValue(3074, 92)
end

local function buildBar(overrides)
  setupSource()
  local mod = dofile(widgetDir .. "main.lua")
  local readable = { Source = 3072, Style = "Bar" }
  for k, v in pairs(overrides or {}) do readable[k] = v end
  local opts = mock.makeOptions(mod.defs, readable)
  local widget = mod.create({ x = 0, y = 0, w = 300, h = 70 }, opts, widgetDir)
  widget.mod = mod
  mod.update(widget, opts)
  for _ = 1, 3 do mock.advance(50); mod.refresh(widget) end
  return widget
end

print("GaugePro Phase 0 feasibility probe")
print("")

-- ---------------------------------------------------------------- binding --

local bindingPath = widgetDir .. "../../radio/src/lua/lua_lvgl_widget.cpp"
local f = assert(io.open(bindingPath, "rb"))
local binding = f:read("*a"); f:close()
local a = assert(string.find(binding, "void LvglWidgetRectangle::parseParam", 1, true))
local b = assert(string.find(binding, "void LvglWidgetRectangle::build", a, true))
local rectangleParser = string.sub(binding, a, b - 1)
assertTrue(not string.find(string.lower(rectangleParser), "grad", 1, true),
  "rectangle binding unexpectedly exposes a gradient; revisit the decision")
print("[binding] rectangle exposes retained fill/outline/radius only;"
  .. " native gradient: NO")
print("[decision] portable spatial gradients use bounded, gapless rectangles")

-- -------------------------------------------------------------- baseline --

buildBar({ ColorMode = "Sections",
  ShowMinMax = "Markers + text" })
local currentVisible = countVisible()
local sharedReserve = currentVisible - 2 -- replace today's track + fill
assertTrue(sharedReserve > 0 and sharedReserve < 20,
  "unexpected current shared-object reserve")
print(string.format("[baseline] worst current 300x70 bar: %d visible objects;"
  .. " shared reserve after replacing track/fill: %d",
  currentVisible, sharedReserve))

-- ------------------------------------------------------------- gradients --

local function gradientSlices(count, width, height)
  local last = 0
  for i = 1, count do
    local x0 = math.floor((i - 1) * width / count)
    local x1 = math.floor(i * width / count)
    assertTrue(x0 == last and x1 > x0, "gradient partition has a gap")
    lvgl.rectangle({ x = x0, y = 0, w = x1 - x0, h = height,
      color = lcd.RGB(32 + math.floor(180 * i / count),
                      144 - math.floor(100 * i / count), 88),
      filled = 1, rounded = 0 })
    last = x1
  end
  assertTrue(last == width, "gradient partition does not reach its end")
end

print("")
print("Gradient slice construction (build-time; 1 fire = 200 VM instructions)")
print(string.format("%-8s %8s %12s %12s %9s", "slices", "objects",
  "instructions", "+ shared", "budget"))
for _, count in ipairs({ 12, 20, 24, 32 }) do
  local worstInstructions = 0
  for _, width in ipairs({ 120, 300, 800 }) do
    mock.reset()
    local _, instructions = measured(function()
      gradientSlices(count, width, 24)
    end)
    worstInstructions = math.max(worstInstructions, instructions)
    assertTrue(mock.objectCount() == count, "slice count drift")
  end
  local total = count + sharedReserve
  print(string.format("%-8d %8d %12d %12d %9s", count, count,
    worstInstructions, total, total <= 40 and "PASS" or "REJECT"))
end

-- ------------------------------------------------------------------- hex --

local function buildHexes(scale, count)
  lvgl.LCD_SCALE = scale
  local width = math.floor(300 * scale + 0.5)
  local height = math.max(12, math.floor(24 * scale + 0.5))
  local gap = math.max(1, math.floor(2 * scale + 0.5))
  local usable = width - gap * (count - 1)
  local cursor = 0
  for i = 1, count do
    local nextCursor = math.floor(i * usable / count) + gap * (i - 1)
    local cellW = nextCursor - cursor
    if i < count then cellW = cellW - gap end
    assertTrue(cellW >= 6, "hex cell too narrow")
    local tip = math.max(1, math.floor(cellW * 0.22))
    local right = cursor + cellW
    local color = lcd.RGB(32, 144, 88)
    lvgl.triangle({ pts = { { cursor + tip, 0 }, { cursor, math.floor(height / 2) },
      { cursor + tip, height } }, color = color })
    lvgl.rectangle({ x = cursor + tip, y = 0, w = cellW - tip * 2,
      h = height, color = color, filled = 1 })
    lvgl.triangle({ pts = { { right - tip, 0 }, { right, math.floor(height / 2) },
      { right - tip, height } }, color = color })
    cursor = right + gap
  end
  return width, height
end

print("")
print("True hex construction (10 cells × 3 retained primitives)")
for _, scale in ipairs({ 0.8, 1.0, 1.375 }) do
  mock.reset()
  local width, height
  local _, instructions = measured(function()
    width, height = buildHexes(scale, 10)
  end)
  assertTrue(mock.objectCount() == 30, "hex primitive count drift")
  print(string.format("  scale %.3f: %dx%d, 30 objects, %d build instructions",
    scale, width, height, instructions))
end
lvgl.LCD_SCALE = 1.0

local maxHex = math.floor((40 - sharedReserve) / 3)
assertTrue(maxHex >= 6, "hex compact fallback is not feasible")
print(string.format("[decision] hex cap: %d cells with current shared reserve"
  .. " (compact floor: 6)",
  maxHex))

-- --------------------------------------------------------------- vertical --

local function axisPosition(value, low, high, y, height)
  local t = (high == low) and 0 or (value - low) / (high - low)
  t = math.max(0, math.min(1, t))
  return y + height - 1 - math.floor(t * (height - 1) + 0.5)
end

assertTrue(axisPosition(0, 0, 100, 10, 101) == 110, "vertical min is bottom")
assertTrue(axisPosition(100, 0, 100, 10, 101) == 10, "vertical max is top")
assertTrue(axisPosition(100, 100, 0, 10, 101) == 110,
  "descending authored start remains bottom")
assertTrue(axisPosition(0, 100, 0, 10, 101) == 10,
  "descending authored end remains top")
assertTrue(axisPosition(0, -100, 100, 10, 101) == 60,
  "zero origin maps to the midpoint")

print("")
print("Vertical value/body/name feasibility")
for _, case in ipairs({
  { scale = 0.8, w = 80, h = 208 },
  { scale = 1.0, w = 100, h = 260 },
  { scale = 1.0, w = 120, h = 220 },
  { scale = 1.375, w = 138, h = 358 },
}) do
  lvgl.LCD_SCALE = case.scale
  local pad = math.max(2, math.floor(6 * case.scale + 0.5))
  local _, valueH = lcd.sizeText("88.88", XLSIZE)
  local _, nameH = lcd.sizeText("RSSI", SMLSIZE)
  local bodyTop = pad + valueH + pad
  local bodyBottom = case.h - pad - nameH - pad
  local bodyH = bodyBottom - bodyTop
  assertTrue(bodyH >= math.floor(64 * case.scale),
    "vertical body cannot preserve current position")
  assertTrue(bodyTop > valueH and bodyBottom + pad <= case.h - nameH,
    "vertical regions overlap")
  print(string.format("  %.3f %dx%d: value %d, body %d, name %d -> PASS",
    case.scale, case.w, case.h, valueH, bodyH, nameH))
end
lvgl.LCD_SCALE = 1.0

-- ----------------------------------------------------------- theme/wallpaper --

mock.setThemeColors(nil)
local theme = dofile(widgetDir .. "theme.lua")
local fill = theme.color.accent
local before = theme.labelOn(fill)
mock.setThemeColors({
  [COLOR_THEME_PRIMARY1] = { 128, 128, 128 },
  [COLOR_THEME_PRIMARY2] = { 255, 255, 255 },
})
local after = theme.labelOn(fill)
assertTrue(before ~= after, "theme switch did not invalidate badge ink")
mock.setThemeColors(nil)
print("")
print("[theme] live ink-role switch invalidates cached badge contrast: PASS")
print("[wallpaper] decision: badges are self-grounded; Auto text/marks"
  .. " require a controlled theme panel")

-- ------------------------------------------------------------- known gap --

local descending = buildBar({ Scale = "Manual", Min = 100, Max = 0,
  Warn = 55, Crit = 35, ShowMinMax = "Markers + text" })
assertTrue(descending.ui.ghost and descending.ui.minMark,
  "descending history fixtures were not constructed")
assertTrue(descending.ui.maxMark == nil,
  "Phase 2 known gap unexpectedly disappeared; replace this probe with a regression")
assertTrue(descending.frame.ghostX == descending.frame.minX,
  "descending failure is no longer reproduced as documented")
print("")
print(string.format("[known gap] descending scale: ghostX=%d, minX=%d,"
  .. " max marker absent -> REPRODUCED",
  descending.frame.ghostX, descending.frame.minX))
print("[scope] independent min/max markers remain Phase 2 correctness work")

-- ------------------------------------------------------------ face budgets --

local budgets = {
  { "Continuous", 4, 24, "track + active + head + highlight" },
  { "Gradient", 24, 38, "maximum portable slice pool" },
  { "Blocks", 16, 38, "bounded block pool" },
  { "Hex", maxHex * 3, 40, tostring(maxHex) .. " true hex cells" },
  { "Ticks", 24, 40, "bounded tick pool" },
  { "Steps", 10, 32, "ten increasing rectangles" },
  { "Dual Rail", 8, 36, "two tracks/fills + zero + heads" },
}
print("")
print("Proposed face object budgets (face ceilings from the approved plan)")
for _, row in ipairs(budgets) do
  local total = row[2] + sharedReserve
  assertTrue(total <= row[3], row[1] .. " exceeds object ceiling")
  print(string.format("  %-10s body %2d + shared %2d = %2d / %2d  PASS  (%s)",
    row[1], row[2], sharedReserve, total, row[3], row[4]))
end

print("")
print("PHASE 0 PROBE: PASS")
