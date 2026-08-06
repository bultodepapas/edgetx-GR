-- GaugeV2 per-frame allocation probe (Tanda 6 F-11 / response Phase 5.1+5.2).
--
-- Reproduces the review's methodology: "basura generada por frame, con la
-- instrumentación del harness desactivada". Two things make the number
-- honest:
--   1. mock.tracking(false): the harness's obj.sets retention is UNBOUNDED
--      by design (it is the suite's audit trail) - it must be off, or the
--      probe measures the harness, not the widget.
--   2. collectgarbage("stop") around the frames: nothing is freed during
--      the run, so the count delta is the TRUE allocation rate (tables,
--      strings, wrappers), not the live-memory growth a normal gc shows.
--
-- Usage: lua5.3 dev/measure_frames.lua <widget-dir>
--
-- Phase 5.1+5.2 target (revert criterion): the needle's share must drop
-- demonstrably against the Tanda baseline (814 B/frame dial-with-needle,
-- ~511 B/frame of it the needle). Run BEFORE and AFTER and compare.
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
  refresh(w, 5)                       -- warm: caches, history, strings settle
  collectgarbage("collect")
  collectgarbage("stop")              -- nothing freed during the run
  local c1 = collectgarbage("count")
  for i = 1, frames do
    mock.setValue(ID_RSSI, (i % 2 == 0) and 10 or 90)   -- angle moves each frame
    mock.advance(50)
    mod.refresh(w)
  end
  local c2 = collectgarbage("count")
  collectgarbage("restart")
  collectgarbage("collect")
  return (c2 - c1) * 1024 / frames    -- bytes allocated per frame
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
  -- Damping = 0: the value snaps, so the formatted string alternates
  -- between two interned strings and the measurement is the needle/arc
  -- machinery, not per-frame string churn (an exponentially-smoothed
  -- value would mint a distinct permanent string every frame).
  { name = "dial 200x200 needle", zone = { x = 0, y = 0, w = 200, h = 200 },
    ov = { Style = 2, ColorMode = 2, ShowMinMax = 3, Precision = 4,
           Damping = 0 } },
  { name = "dial 200x200 arc",    zone = { x = 0, y = 0, w = 200, h = 200 },
    ov = { Style = 3, ColorMode = 2, ShowMinMax = 3, Precision = 4,
           Damping = 0 } },
  { name = "bar 300x60",          zone = { x = 0, y = 0, w = 300, h = 60 },
    ov = { Style = 4, ColorMode = 2, Precision = 4, Damping = 0 } },
}

local FRAMES = 100

mock.tracking(false)                -- measure the widget, not the harness
print("GaugeV2 per-frame allocation probe  (gc stopped, harness tracking off,"
  .. " " .. FRAMES .. " moving frames)")
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
print(string.format("Tanda baseline: 814 B/frame needle scene, ~511 B/frame"
  .. " needle share"))
mock.tracking(true)
