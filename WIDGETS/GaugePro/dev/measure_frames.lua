-- GaugePro per-frame allocation probe (Tanda 6 F-11 / response Phase 5.1+5.2,
-- acceptance measurement Phase 5.3).
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
-- The FEED matters as much as the methodology (response A.3):
--   * plateau (60/90): the acceptance feed. The value oscillates INSIDE the
--     normal state band - steady flight, one state, needle moving. A feed
--     crossing the threshold every frame churns the chip and applyColors,
--     a probe artifact of the same class as the ramp.
--   * crossing (10/90): documents that artifact - the chip/state churn.
--   * ramp (RSSI+ rising): the history genuinely advancing. This was once
--     dismissed as "a few seconds after power-up", which undersold it - the
--     historical maximum advances for every second of a climb. The marks got
--     the needle's persistent-buffer treatment as a result (F-16), so
--     linePoints/f is 0 here too and what is left is the min/max READOUT
--     re-formatting a number that really did change.
--
-- Usage: lua5.3 dev/measure_frames.lua <widget-dir>
--
-- Phase 5 target (revert criterion): the needle's share must drop
-- demonstrably against the Tanda baseline (~511 B/frame needle share).
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

local FRAMES = 100

-- ---- feed modes -------------------------------------------------------------
-- plateau: value oscillates INSIDE the normal band (steady flight, one state)
local function feedPlateau(i)
  mock.setValue(ID_RSSI, (i % 2 == 0) and 60 or 90)
  mock.advance(50)
end
-- crossing: value crosses the critical threshold every frame (chip churn)
local function feedCrossing(i)
  mock.setValue(ID_RSSI, (i % 2 == 0) and 10 or 90)
  mock.advance(50)
end

-- ---- measurement -------------------------------------------------------------

local function measureWith(w, mod, frames, feed)
  refresh(w, 5)                       -- warm: caches, history, strings settle
  collectgarbage("collect")
  collectgarbage("stop")              -- nothing freed during the run
  local c1 = collectgarbage("count")
  for i = 1, frames do
    feed(i)
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
    feedPlateau(i)
    mod.refresh(w)
  end
  geom.linePoints = real
  return calls / frames
end

-- VM instructions per frame. The hook fires once per HOOK_STEP instructions,
-- so the count has to be multiplied back out: reporting the raw fire count
-- under a column called "instr/f" understated the real figure by a factor of
-- HOOK_STEP, which against EdgeTX's 20000-instruction budget is the
-- difference between "0.04% of budget" and "7%".
local HOOK_STEP = 200
local function countInstructions(w, mod, frames)
  local fires = 0
  local function hook() fires = fires + 1 end
  debug.sethook(hook, "", HOOK_STEP)
  for i = 1, frames do
    feedPlateau(i)
    mod.refresh(w)
  end
  debug.sethook()
  return fires * HOOK_STEP / frames
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

-- ---- main --------------------------------------------------------------------

mock.tracking(false)                -- measure the widget, not the harness
print("GaugePro per-frame allocation probe  (gc stopped, harness tracking off,"
  .. " " .. FRAMES .. " frames)")
print("")
print(string.format("%-24s %12s %14s %12s",
  "scene", "B/frame", "linePoints/f", "instr/f (of 20000)"))
print(string.rep("-", 66))
local totals = { needle = nil, arc = nil, bar = nil }
for _, sc in ipairs(SCENES) do
  local w, mod = build(sc.zone, sc.ov)
  local bytes = measureWith(w, mod, FRAMES, feedPlateau)
  local calls = countLinePointsCalls(w, mod, FRAMES)
  local instr = countInstructions(w, mod, FRAMES)
  if string.find(sc.name, "needle") then totals.needle = bytes
  elseif string.find(sc.name, "arc") then totals.arc = bytes
  else totals.bar = bytes end
  print(string.format("%-24s %10.0f B %12.2f %8.0f (%.0f%%)",
    sc.name, bytes, calls, instr, instr / 20000 * 100))
end
print(string.rep("-", 66))
local needleShare = totals.needle - totals.arc
print(string.format("needle share (steady state): %.0f B/frame (%.0f - %.0f)",
  needleShare, totals.needle, totals.arc))
print(string.format("Tanda baseline: 814 B/frame needle scene, ~511 B/frame"
  .. " needle share"))
print("")

-- ---- threshold-crossing row (documented probe artifact) ----------------------
-- A feed that crosses the state threshold every frame churns the state
-- string and applyColors. frame.chipBox is no longer part of it: it used to
-- be a fresh table per chip show (~186 B), and is now allocated once and
-- mutated (F-16). What remains is per TRANSITION, ~0 in steady flight.
local wc, modc = build(SCENES[1].zone, SCENES[1].ov)
local crossBytes = measureWith(wc, modc, FRAMES, feedCrossing)
print(string.format("-- threshold-crossing feed (10/90): %.0f B/frame - the"
  .. " chip/state churn, %.0f B/f above steady state",
  crossBytes, crossBytes - totals.needle))
print("")

-- ---- A.3 check: ramp vs plateau ---------------------------------------------
-- The DROPPED original-5.3 target chased "ghost 1.00 sets/frame, maxMark
-- 1.00 sets/frame" from a monotonically rising sweep probe. In steady
-- flight the historical maximum advances for a few seconds at power-up and
-- never again (response A.3). Verify with data: the same needle scene under
-- a RAMP feed (the RSSI+ sibling rises every frame, so the history max -
-- and with it the maxMark - genuinely advances), vs the plateau above.
local function feedRamp(i)
  mock.setValue(ID_RSSI, (i % 10) * 11)   -- value oscillates: 10 interned strings
  mock.setValue(3074, i)                  -- RSSI+ rises: history max advances
  mock.advance(50)
end

local function countLinePointsRamp(w, mod, frames)
  local geom = w.mods.geometry
  local real = geom.linePoints
  local calls = 0
  geom.linePoints = function(...) calls = calls + 1 return real(...) end
  for i = 1, frames do
    feedRamp(i)
    mod.refresh(w)
  end
  geom.linePoints = real
  return calls / frames
end

print("-- A.3 check: the same scene under a RAMP (history max advancing)")
local wr, modr = build(SCENES[1].zone, SCENES[1].ov)
local rampBytes = measureWith(wr, modr, FRAMES, feedRamp)
local rampCalls = countLinePointsRamp(wr, modr, FRAMES)
print(string.format("dial 200x200 needle (ramp): %10.0f B/f  linePoints %5.2f/f",
  rampBytes, rampCalls))
print(string.format("marker/ghost cost of the ramp: %.0f B/frame"
  .. " (%.0f - %.0f) - exists ONLY while history advances",
  rampBytes - totals.needle, rampBytes, totals.needle))
print("in steady flight (plateau) the historical max is static: cost 0")
print("")
mock.tracking(true)
