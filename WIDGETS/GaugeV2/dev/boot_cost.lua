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
local function loadCost(path)
  local chunk = assert(loadfile(path))
  collectgarbage("collect")
  collectgarbage("stop")
  local c1 = collectgarbage("count")
  local fires = 0
  local function hook() fires = fires + 1 end
  debug.sethook(hook, "", 200)
  chunk()
  debug.sethook()
  local c2 = collectgarbage("count")
  collectgarbage("restart")
  collectgarbage("collect")
  return (c2 - c1) * 1024, fires
end

local bytes, fires = loadCost(widgetDir .. "options.lua")
print("options.lua load cost:")
print(string.format("  %6d bytes allocated, %d fires = %d VM instructions",
  bytes, fires, fires * 200))
print("")

-- 2. equivalence of the two builders (sonda M, re-verified today)
local mod = dofile(widgetDir .. "main.lua")
local options = dofile(widgetDir .. "options.lua")
local decl = options.build(mod.defs, 50)
local diffs = 0
for i = 1, #mod.options do
  local a, b = mod.options[i], decl[i]
  for k = 1, #a do
    if type(a[k]) == "table" then
      for j = 1, #a[k] do
        if a[k][j] ~= b[k][j] then diffs = diffs + 1 end
      end
    elseif a[k] ~= b[k] then
      diffs = diffs + 1
    end
  end
end
print(string.format("inline=%d  options.build=%d  differences: %d",
  #mod.options, #decl, diffs))
print("")

-- 3. the per-widget boot saving on a card with N widgets
print("main.lua runs once per widget at boot; options.lua loads once per")
print("radio on first use (module cache, P2-3). Inlining saves one")
print("options.lua load per WIDGET on the card - the number above, times")
print("the number of widgets under /WIDGETS/.")
