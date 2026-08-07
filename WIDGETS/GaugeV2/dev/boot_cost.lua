-- GaugeV2 boot-cost measurement for F-14 (response 6.1).
--
-- main.lua executes at radio startup for EVERY widget on the SD card, used
-- or not, and the option declarations are built INLINE so boot costs exactly
-- one file read per widget. options.lua owns everything else and loads on
-- first use (inside app.lua's shared module cache - once per radio, not per
-- widget).
--
-- This probe measures the cost the inline duplication avoids: loading and
-- executing options.lua once, and the equivalence of the two builders (the
-- F-14 sonda M: "inline=24 options.build=24 differences: 0").
--
-- Usage: lua5.3 dev/boot_cost.lua <widget-dir>
local widgetDir = arg[1] or "./"
if string.sub(widgetDir, -1) ~= "/" then widgetDir = widgetDir .. "/" end

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

-- 1. cost of ONE options.lua load (what main.lua would pay per widget at
--    boot if it used the module instead of inlining)
-- The hook step is the measurement's granularity. The firmware's own step is
-- 200 (lua_widget.cpp MAX_INSTRUCTIONS = 20000/100), but using it here just
-- reported "0 fires" for anything cheaper than one whole step - which is the
-- entire point of this probe. Measure fine, compare against the coarse
-- budget.
local HOOK_STEP = 10

local function loadCost(path)
  local chunk = assert(loadfile(path))
  collectgarbage("collect")
  collectgarbage("stop")
  local c1 = collectgarbage("count")
  local fires = 0
  local function hook() fires = fires + 1 end
  debug.sethook(hook, "", HOOK_STEP)
  chunk()
  debug.sethook()
  local c2 = collectgarbage("count")
  collectgarbage("restart")
  collectgarbage("collect")
  return (c2 - c1) * 1024, fires * HOOK_STEP
end

local bytes, instr = loadCost(widgetDir .. "options.lua")
print("options.lua load cost:")
print(string.format("  %6d bytes allocated, ~%d VM instructions"
  .. " (%.1f%% of one 20000-instruction callback budget)",
  bytes, instr, instr / 20000 * 100))
print("")

-- 2. the F-14 invariant: there is exactly ONE builder.
--
-- This used to compare main.lua's inline declarations against
-- options.build(). That comparison is gone because its subject is gone:
-- having proved the two byte-identical, Tanda 6 DELETED options.build() so
-- they could never drift. The probe kept calling it and had been crashing on
-- `attempt to call a nil value (field 'build')` ever since - a check that
-- cannot run is worse than no check, because the file still claims to
-- perform one.
--
-- What is worth asserting now is the invariant that replaced it: options.lua
-- must NOT grow a second builder. If one ever comes back, the drift this
-- duplication was accepted to avoid becomes possible again.
local mod = dofile(widgetDir .. "main.lua")
local options = dofile(widgetDir .. "options.lua")
local rebuilt = 0
for _, name in ipairs({ "build", "declare", "translate" }) do
  if options[name] ~= nil then
    print(string.format("!! options.%s exists again - main.lua's inline"
      .. " builder is no longer the only one (F-14)", name))
    rebuilt = rebuilt + 1
  end
end
print(string.format("inline declarations: %d   rival builders in options.lua:"
  .. " %d %s", #mod.options, rebuilt,
  (rebuilt == 0) and "(F-14 invariant holds)" or "<- FIX THIS"))
print("")

-- 3. the per-widget boot saving on a card with N widgets
print("main.lua runs once per widget at boot; options.lua loads once per")
print("radio on first use (module cache, P2-3). Inlining saves one")
print("options.lua load per WIDGET on the card - the number above, times")
print("the number of widgets under /WIDGETS/.")
