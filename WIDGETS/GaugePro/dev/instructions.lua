-- Lua VM instruction budget probe for GaugePro.
--
-- The firmware gives every widget callback a hard budget of 20 000 Lua VM
-- instructions per call: radio/src/lua/widgets.cpp defines
-- MAX_INSTRUCTIONS (20000/100), luaHook() fires every 200 instructions and
-- luaL_error(L, "CPU limit") past 100 fires - the same setErrorMessage()
-- path that traces "Widget disabled", dead until the model reloads.
--
-- Two things made this probe necessary (dev/code-review-tanda6-response.md
-- §A.1 / §C.5):
--   * DEBUG builds DISABLE the limit (it only traces the running maximum),
--     so a widget that dies on a production radio can be perfectly healthy
--     in the simulator;
--   * the headless harness has no instruction budget at all, so neither
--     do the test suites. Nothing measured the one resource that silently
--     kills the widget.
--
-- Usage: lua5.3 dev/instructions.lua <widget-dir>
--
-- Phase 0: establishes the number (acceptance: produces numbers).
-- Phase 5: becomes the acceptance criterion for the optimisation work.
-- 100 fires = the kill limit; report the headroom below it.
local widgetDir = arg[1] or "./"
if string.sub(widgetDir, -1) ~= "/" then widgetDir = widgetDir .. "/" end

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local ID_RSSI, ID_MIN, ID_MAX = 3072, 3073, 3074

local function build(zone, ov)
  mock.reset()
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0 }
  mock.addField(ID_RSSI, "RSSI", 17)
  mock.addField(ID_MIN, "RSSI-", 17)
  mock.addField(ID_MAX, "RSSI+", 17)
  mock.sim.sensors[0] = { name = "RSSI", prec = 0, unit = 17 }
  mock.setValue(ID_RSSI, 70)
  mock.setValue(ID_MIN, 31)
  mock.setValue(ID_MAX, 92)
  local mod = dofile(widgetDir .. "main.lua")
  local o = { Source = ID_RSSI }
  for k, v in pairs(ov) do o[k] = v end
  local opts = mock.makeOptions(mod.defs, o)
  local w = mod.create(zone, opts, widgetDir)
  w.mod = mod
  mod.update(w, opts)
  return w, mod, opts
end

local function refresh(widget, times)
  for _ = 1, (times or 1) do
    mock.advance(50)
    widget.mod.refresh(widget)
  end
end

-- ---- counting ---------------------------------------------------------------

local fires = 0
local function hook() fires = fires + 1 end

-- Instructions executed by `fn` in units of 200 (the hook period the
-- firmware uses). The count includes the pcall and counting overhead on
-- both sides, so it slightly OVERestimates - safe for a headroom probe.
local function countCall(fn)
  fires = 0
  debug.sethook(hook, "", 200)
  local ok, err = pcall(fn)
  debug.sethook()
  return fires, ok, err
end

-- ---- scenes -----------------------------------------------------------------

-- The heaviest scene the widget can produce: the largest zone with the
-- needle, Sections colouring, scale labels and min/max text on. The rest of
-- the matrix brackets it so the worst case is measured, not assumed.
local SCENES = {
  { name = "480x272 needle sections markers+text",
    zone = { x = 0, y = 0, w = 480, h = 272 },
    ov = { Style = 2, ColorMode = 5, ShowMinMax = 3, Precision = 4 } },
  { name = "480x272 needle threshold markers+text",
    zone = { x = 0, y = 0, w = 480, h = 272 },
    ov = { Style = 2, ColorMode = 2, ShowMinMax = 3, Precision = 4 } },
  { name = "200x200 needle sections markers+text",
    zone = { x = 0, y = 0, w = 200, h = 200 },
    ov = { Style = 2, ColorMode = 5, ShowMinMax = 3, Precision = 4 } },
  { name = "200x200 arc sections markers",
    zone = { x = 0, y = 0, w = 200, h = 200 },
    ov = { Style = 3, ColorMode = 5, ShowMinMax = 2, Precision = 4 } },
  { name = "200x200 needle sections 360deg",
    zone = { x = 0, y = 0, w = 200, h = 200 },
    ov = { Style = 2, ColorMode = 5, Sweep = 3, ShowMinMax = 3,
           Precision = 4 } },
  { name = "300x60 bar threshold",
    zone = { x = 0, y = 0, w = 300, h = 60 },
    ov = { Style = 4, ColorMode = 2, Precision = 4 } },
}

local fmt = string.format

print("GaugePro instruction budget probe  (1 fire = 200 VM instructions;")
print("100 fires = 20000 = the firmware kill limit per callback)")
print("")

local function probeScene(sc)
  local w, mod, opts = build(sc.zone, sc.ov)
  local o2 = {}
  for k, v in pairs(opts) do o2[k] = v end

  -- update() with identical options: the settings-exit / Cancel path
  local updNoop = countCall(function() mod.update(w, opts) end)

  -- update() with a structural change: the full rebuild path
  local updBuild
  do
    o2.Sweep = (o2.Sweep or 1) == 1 and 3 or 1
    updBuild = countCall(function() mod.update(w, o2) end)
    o2.Sweep = (o2.Sweep or 1) == 1 and 3 or 1
    countCall(function() mod.update(w, o2) end)
  end

  -- refresh() with a static value: the common idle frame
  refresh(w, 2)
  local refIdle = countCall(function() refresh(w, 1) end)

  -- refresh() with the value moving every frame: angle/needle/history churn
  local refChg = 0
  mock.setValue(ID_RSSI, 90)
  for _ = 1, 5 do
    mock.setValue(ID_RSSI, (mock.sim.values[ID_RSSI] == 90) and 10 or 90)
    local n = countCall(function() refresh(w, 1) end)
    if n > refChg then refChg = n end
  end

  local worst = math.max(updNoop, updBuild, refIdle, refChg)
  return {
    name = sc.name,
    updNoop = updNoop, updBuild = updBuild,
    refIdle = refIdle, refChg = refChg,
    worst = worst, worstCall = refChg,
  }
end

local rows = {}
local overall = { worst = 0 }
for _, sc in ipairs(SCENES) do
  local r = probeScene(sc)
  rows[#rows + 1] = r
  if r.worst > overall.worst then overall = r end
end

print(fmt("%-38s %8s %8s %8s %8s %10s %9s",
  "scene", "upd-noop", "upd-bld", "ref-idle", "ref-chg",
  "instr/call", "headroom"))
print(string.rep("-", 96))
for _, r in ipairs(rows) do
  print(fmt("%-38s %8d %8d %8d %8d %10d %8d fires",
    r.name, r.updNoop, r.updBuild, r.refIdle, r.refChg,
    r.worst * 200, 100 - r.worst))
end
print(string.rep("-", 96))
print(fmt("worst scene: %s", overall.name))
print(fmt("worst callback: %d fires = %d instructions (limit 100 / 20000)",
  overall.worst, overall.worst * 200))
print(fmt("headroom: %d fires (%d%%) before the CPU-limit kill switch",
  100 - overall.worst, math.floor((100 - overall.worst) / 100 * 100)))
print("")

if overall.worst >= 100 then
  io.stderr:write("PROBE FAILURE: a callback is at the firmware kill limit\n")
  os.exit(1)
end
if overall.worst >= 50 then
  io.stderr:write("WARNING: a callback is within 2x of the firmware kill "
    .. "limit - investigate before optimising anything else\n")
end
