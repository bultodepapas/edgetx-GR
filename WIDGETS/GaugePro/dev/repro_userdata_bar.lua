-- Radio-fidelity regression check for GaugePro bar faces: runs the real
-- bar_faces.lua against EdgeTX-faithful LVGL objects (full userdata whose
-- metatable has __index/__gc but NO __newindex). Any widget code that writes
-- a field onto an lvgl object raises "attempt to index a userdata value"
-- here, exactly as on the radio.
--
-- The unit harness (tests/mock_env.lua) returns plain tables and enforces
-- the same rule through its __newindex guard; this file additionally checks
-- the userdata-identity paths: objects as table keys (renderer.setProp),
-- lvgl.set/show/hide accepting userdata, and the retained tree surviving a
-- frame.
--
-- Usage: lua5.3 dev/repro_userdata_bar.lua

local widgetDir = arg[1] or "./"

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local function load(name)
  return assert(loadfile(widgetDir .. name .. ".lua"))()
end

local geometry = load("geometry")
local ranges = load("ranges")
local theme = load("theme")
local renderer = load("renderer")
local barFaces = load("bar_faces")
renderer.setup(theme, geometry, nil)
barFaces.setup(theme, geometry, renderer)

-- ---- EdgeTX-faithful lvgl: objects are full userdata ----------------------
-- io.stdout/stderr/stdin are FILE* full userdata: metatable has __index and
-- __gc only, no __newindex. lvgl.set/show/hide must accept them like the C
-- binding does.
local pool = { io.stdout, io.stderr, io.stdin }
local poolN = 0
local function makeObject()
  poolN = poolN + 1
  if poolN > 3 then poolN = 1 end
  return pool[poolN]
end

local function record() end
local envLvgl = {
  LCD_SCALE = 1.0,
  rectangle = function() return makeObject() end,
  triangle = function() return makeObject() end,
  line = function() return makeObject() end,
  circle = function() return makeObject() end,
  label = function() return makeObject() end,
  set = record, show = record, hide = record,
}
_G.lvgl = envLvgl
_G._G.lvgl = envLvgl

-- ---- minimal but realistic bar widget -------------------------------------

local function newWidget(colorMode, origin)
  local axis = geometry.makeAxis({ x = 10, y = 10, w = 180, h = 20 },
    "horizontal", -30, 100, origin or "scale-low")
  return {
    ui = {},
    frame = { props = {} },
    accent = theme.color.accent,
    config = {
      colorMode = colorMode,
      min = -30, max = 100, warn = 55, crit = 35, highGood = true,
    },
    ranges = ranges.build(-30, 100, 55, 35, true),
    barPalette = {
      track = theme.color.rail, border = theme.color.label, panel = 0,
      critical = theme.color.crit, normal = theme.color.accent,
      warning = theme.color.warn,
    },
    barVisual = { head = "line" },
    layout = {
      w = 200, h = 40,
      bar = { x = 10, y = 10, w = 180, h = 20 },
      barEdge = 0, barRadius = 0, markThickness = 2,
      axis = axis,
    },
  }
end

local style = { surface = "transparent", ends = "round", origin = "scale-low" }

local function renderState(normalized)
  return {
    visualValid = true,
    smoothNormalized = normalized or 0.6,
    smoothValue = 50,
    colorKey = "normal",
  }
end

local passed, failed = 0, 0
local function check(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("PASS " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end

for _, colorMode in ipairs{
  { name = "RAIL", value = renderer.COLOR_RAIL },
  { name = "SECTIONS", value = renderer.COLOR_SECTIONS },
  { name = "GRADIENT", value = renderer.COLOR_GRADIENT },
} do
  check("continuous build + overlay + update (" .. colorMode.name .. ")",
    function()
      local w = newWidget(colorMode.value)
      local face = barFaces.REGISTRY.continuous
      assert(face.build(w, nil, style))
      assert(face.buildOverlay(w))
      face.update(w, w.ui, renderState())
    end)
end

check("dual-rail build + overlay + update", function()
  local w = newWidget(renderer.COLOR_RAIL, "zero")
  local face = barFaces.REGISTRY["dual-rail"]
  assert(face.build(w, nil, style))
  assert(face.buildOverlay(w))
  face.update(w, w.ui, renderState())
end)

print(string.format("-- %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
