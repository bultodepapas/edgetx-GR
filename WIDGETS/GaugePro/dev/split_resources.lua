-- Resource evidence for the split frontends.
-- Usage: lua5.3 dev/split_resources.lua <GaugeCore-source-dir>

local coreDir = arg[1] or "./"
if string.sub(coreDir, -1) ~= "/" then coreDir = coreDir .. "/" end
local repoRoot = coreDir .. "../../"
local mock = dofile(coreDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local ID_RSSI = 3072
local ZONES = {
  Dial = { x = 0, y = 0, w = 200, h = 160 },
  Bar = { x = 0, y = 0, w = 300, h = 70 },
}

local function setupRadio()
  mock.reset()
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0, "edgetx" }
  mock.addField(ID_RSSI, "RSSI", 17)
  mock.addField(3073, "RSSI-", 17)
  mock.addField(3074, "RSSI+", 17)
  mock.sim.sensors[0] = { name = "RSSI", prec = 0, unit = 17 }
  mock.setValue(ID_RSSI, 70)
end

local function loadFront(family)
  local chunk = assert(loadfile(repoRoot .. "WIDGETS/Gauge" .. family
    .. "Pro/main.lua", "bt", _ENV or _G))
  return chunk({ corePath = coreDir })
end

local function countCall(fn)
  local fires = 0
  local function hook() fires = fires + 1 end
  debug.sethook(hook, "", 200)
  local ok, err = pcall(fn)
  debug.sethook()
  assert(ok, err)
  return fires * 200
end

local function measureFamily(family)
  setupRadio()
  collectgarbage("collect")
  local beforeKb = collectgarbage("count")
  local original, paths = loadScript, {}
  loadScript = function(path, mode)
    paths[#paths + 1] = path
    return original(path, mode)
  end

  local front = loadFront(family)
  local opts = mock.makeOptions(front.defs, { Source = ID_RSSI })
  local widget = front.create(ZONES[family], opts,
    "/WIDGETS/Gauge" .. family .. "Pro/")
  local structural = countCall(function() front.update(widget, opts) end)
  local firstLoads = #paths
  local second = front.create(ZONES[family], opts,
    "/WIDGETS/Gauge" .. family .. "Pro/")
  assert(second.mods == widget.mods, family .. " module cache is not shared")
  assert(#paths == firstLoads, family .. " second instance reloaded chunks")
  loadScript = original

  local firstRefresh = countCall(function()
    mock.advance(50)
    front.refresh(widget)
  end)
  -- First ordinary refresh resolves the initial sample/history. It is a
  -- transition, not the idle steady-state callback measured below.
  mock.advance(50)
  front.refresh(widget)
  local stable = countCall(function()
    mock.advance(50)
    front.refresh(widget)
  end)
  local moving = countCall(function()
    mock.setValue(ID_RSSI, 80)
    mock.advance(50)
    front.refresh(widget)
  end)
  local retainedKb = collectgarbage("count") - beforeKb

  local names = {}
  for _, path in ipairs(paths) do
    names[#names + 1] = string.match(path, "([^/\\]+)%.lua$") or path
  end
  print(string.format(
    "%s: %d chunks, %.1f KB retained, update ~%d, build ~%d, "
      .. "stable ~%d, moving ~%d instructions",
    family, firstLoads, retainedKb, structural, firstRefresh, stable, moving))
  print("  " .. table.concat(names, ", "))
  assert(structural < 10000, family .. " structural update exceeds guardrail")
  assert(firstRefresh < 10000,
    family .. " structural build exceeds guardrail")
  assert(stable < 2000, family .. " stable callback exceeds guardrail")
  assert(moving < 6000, family .. " moving callback exceeds guardrail")
  return retainedKb
end

local dialKb = measureFamily("Dial")
local barKb = measureFamily("Bar")
print(string.format("mixed retained estimate: %.1f KB (Dial %.1f + Bar %.1f)",
  dialKb + barKb, dialKb, barKb))
