-- GaugeV2 per-frame allocation probe (Tanda 6 F-11 / response Phase 5.1).
--
-- Reproduces the review's methodology ("basura generada por frame, con la
-- instrumentación del harness desactivada"): full gc -> measure -> N frames
-- with a sweeping value -> full gc -> delta. Also counts geometry.linePoints
-- calls per frame (3 tables per call) and the moving-refresh instruction
-- count from the 0.9 probe.
--
-- Usage: lua5.3 dev/measure_frames.lua <widget-dir>
--
-- Phase 5.1 target (revert criterion): the needle's share (~511 B/frame of
-- the 814) must drop demonstrably; the change is reverted if it cannot be
-- shown. Run BEFORE and AFTER the change and compare.
local widgetDir = arg[1] or "./"
if string.sub(widgetDir, -1) ~= "/" then widgetDir = widgetDir .. "/" end

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local ID_RSSI = 3072

local function build(zone, ov)
  mock.reset()
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0 }
  mock.addField(ID_RSSI, "RSSI", 17)
  mock.addField(3073, "RSSI-", 17)
  mock.addField(3074, "RSSI+", 17)
  mock.sim.sensors[0] = { name = "RSSI", prec = 0, unit = 17 }
  mock.setValue(ID_RSSI, 70)
  mock.setValue(3073, 31)
  mock.setValue(3074, 92)
  local mod = dofile(widgetDir .. "main.lua")
  local o = { Source = ID_RSSI }
  for k, v in pairs(ov) do o[k] = v end
  local opts = mock.makeOptions(mod.defs, o)
  local w = mod.create(zone, opts, widgetDir)
  w.mod = mod
  mod.update(w, opts)
  return w, mod
end

local function refresh(widget, times)
  for _ = 1, (times or 1) do
    mock.advance(50)
    widget.mod.refresh(widget)
  end
end

-- ---- per-scene measurement --------------------------------------------------

local function measure(w, mod, frames)
  refresh(w, 5)                       -- warm: caches and history settle
  collectgarbage("collect")
  local c1 = collectgarbage("count")
  for i = 1, frames do
    mock.setValue(ID_RSSI, (i % 2 == 0) and 10 or 90)   -- angle moves each frame
    mock.advance(50)
    mod.refresh(w)
  end
  collectgarbage("collect")
  local c2 = collectgarbage("count")
  return (c2 - c1) * 1024 / frames    -- bytes per frame (garbage + deltas)
end

local function countLinePointsCalls(w, mod, frames)
  local geom = w.mods.geometry
  local real = geom.linePoints
  local calls = 0
  geom.linePoints = function(...) calls = calls + 1 return real(...) end
  for i = 1, frames do
    mock.setValue(ID_RSSI, (i % 2 == 0) and 10 or 90)
    mock.advance(50)
    mod.refresh(w)
  end
  geom.linePoints = real
  return calls / frames
end

local function countInstructions(w, mod, frames)
  local fires = 0
  local function hook() fires = fires + 1 end
  debug.sethook(hook, "", 200)
  for i = 1, frames do
    mock.setValue(ID_RSSI, (i % 2 == 0) and 10 or 90)
    mock.advance(50)
    mod.refresh(w)
  end
  debug.sethook()
  return fires / frames               -- 1 fire = 200 VM instructions
end

local SCENES = {
  { name = "dial 200x200 needle", zone = { x = 0, y = 0, w = 200, h = 200 },
    ov = { Style = 2, ColorMode = 2, ShowMinMax = 3, Precision = 4 } },
  { name = "dial 200x200 arc",    zone = { x = 0, y = 0, w = 200, h = 200 },
    ov = { Style = 3, ColorMode = 2, ShowMinMax = 3, Precision = 4 } },
  { name = "bar 300x60",          zone = { x = 0, y = 0, w = 300, h = 60 },
    ov = { Style = 4, ColorMode = 2, Precision = 4 } },
}

local FRAMES = 100

print("GaugeV2 per-frame allocation probe  (gc-delta method, " .. FRAMES
  .. " moving frames)")
print("")
print(string.format("%-22s %12s %14s %12s",
  "scene", "B/frame", "linePoints/f", "instr/f"))
print(string.rep("-", 64))
local totals = { needle = nil, arc = nil, bar = nil }
for _, sc in ipairs(SCENES) do
  local w, mod = build(sc.zone, sc.ov)
  local bytes = measure(w, mod, FRAMES)
  local calls = countLinePointsCalls(w, mod, FRAMES)
  local fires = countInstructions(w, mod, FRAMES)
  if string.find(sc.name, "needle") then totals.needle = bytes
  elseif string.find(sc.name, "arc") then totals.arc = bytes
  else totals.bar = bytes end
  print(string.format("%-22s %10.0f B %12.2f %10.1f",
    sc.name, bytes, calls, fires))
end
print(string.rep("-", 64))
local needleShare = totals.needle - totals.arc
print(string.format("needle share: %.0f B/frame (%.0f - %.0f)",
  needleShare, totals.needle, totals.arc))
print(string.format("Phase 5 target: needle from 511 B/frame to as close to"
  .. " 0 as measurable"))
