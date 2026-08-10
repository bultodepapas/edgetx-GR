-- GaugePro Phase 6 motion sequence and resource-budget gate.
--
-- Unlike dev/instructions.lua, which protects the complete widget matrix,
-- this probe deliberately exercises the temporal branches. Every production
-- face is run horizontally and vertically under every authored motion profile
-- through stable telemetry, same-band movement, warning/critical entry,
-- dropout, recovery and hidden resume.
--
-- Usage: lua5.3 dev/motion_sequences.lua <widget-dir>

local widgetDir = arg[1] or "./"
if string.sub(widgetDir, -1) ~= "/" then widgetDir = widgetDir .. "/" end

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local ID_SOURCE = 101
local HOOK_STEP = 200 -- EdgeTX release-firmware hook period
local ORDINARY_LIMIT = 2000
local TRANSITION_LIMIT = 6000
local ALLOCATION_LIMIT = 96
local SAMPLE_FRAMES = 120

local FACES = {
  { name = "Continuous", options = {} },
  { name = "Blocks", options = { BarFace = "Blocks", Segments = "10" } },
  { name = "Hex", options = { BarFace = "Hex", Segments = "10" } },
  { name = "Ticks", options = { BarFace = "Ticks", Segments = "24" } },
  { name = "Steps", options = { BarFace = "Steps", Segments = "10" } },
  { name = "Dual rail", options = {
      BarFace = "Dual rail", BarOrigin = "Zero", Min = -100, Max = 100,
    } },
}

local DIRECTIONS = {
  { name = "H", value = "Horizontal", zone = { x = 0, y = 0, w = 420, h = 110 } },
  { name = "V", value = "Vertical", zone = { x = 0, y = 0, w = 120, h = 300 } },
}

local PROFILES = { "Off", "Essential", "Refined", "Expressive" }

local function tableSize(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

local function build(face, direction, profile)
  mock.reset()
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0 }
  mock.addField(ID_SOURCE, "Ail")
  mock.setValue(ID_SOURCE, 80)
  local mod = dofile(widgetDir .. "main.lua")
  local authored = {
    Source = ID_SOURCE, Style = "Bar", BarDir = direction.value,
    Scale = "Manual", Min = 0, Max = 100, Warn = 55, Crit = 35,
    ColorMode = "Sections", Motion = profile, Damping = 0,
  }
  for k, v in pairs(face.options) do authored[k] = v end
  local opts = mock.makeOptions(mod.defs, authored)
  local w = mod.create(direction.zone, opts, widgetDir)
  w.mod = mod
  mod.update(w, opts)
  for _ = 1, 3 do
    mock.advance(50)
    mod.refresh(w)
  end
  return w, mod
end

local fires = 0
local function hook() fires = fires + 1 end

local function countCall(fn)
  fires = 0
  debug.sethook(hook, "", HOOK_STEP)
  local ok, err = pcall(fn)
  debug.sethook()
  if not ok then error(err, 0) end
  return fires * HOOK_STEP
end

local function step(w, mod, value, ms)
  mock.setValue(ID_SOURCE, value)
  mock.advance(ms or 50)
  return countCall(function() mod.refresh(w) end)
end

local function countOrdinary(w, mod)
  fires = 0
  debug.sethook(hook, "", HOOK_STEP)
  for i = 1, SAMPLE_FRAMES do
    mock.setValue(ID_SOURCE, (i % 2 == 0) and 68 or 88)
    mock.advance(50)
    mod.refresh(w)
  end
  debug.sethook()
  return fires * HOOK_STEP / SAMPLE_FRAMES
end

local function allocationRate(w, mod)
  collectgarbage("collect")
  collectgarbage("stop")
  local before = collectgarbage("count")
  for i = 1, SAMPLE_FRAMES do
    mock.setValue(ID_SOURCE, (i % 2 == 0) and 68 or 88)
    mock.advance(50)
    mod.refresh(w)
  end
  local after = collectgarbage("count")
  collectgarbage("restart")
  collectgarbage("collect")
  return (after - before) * 1024 / SAMPLE_FRAMES
end

local failures, rows = {}, {}
local function fail(name, message)
  failures[#failures + 1] = name .. ": " .. message
end

mock.tracking(false) -- lvgl.set is C++ on radio; exclude harness audit tables

for _, face in ipairs(FACES) do
  for _, direction in ipairs(DIRECTIONS) do
    for _, profile in ipairs(PROFILES) do
      local label = face.name .. " " .. direction.name .. " / " .. profile
      local w, mod = build(face, direction, profile)
      local retainedMotion, retainedFrame = w.motionState, w.frame
      local retainedKeys = tableSize(retainedMotion)
      local retainedObjects = mock.objectCount()

      mock.advance(50)
      local stable = countCall(function() mod.refresh(w) end)
      local ordinary = countOrdinary(w, mod)
      local bytes = allocationRate(w, mod)

      -- Return to a known normal sample before measuring semantic branches.
      step(w, mod, 80, 250)
      local warning = step(w, mod, 45, 0)
      local warningMid = step(w, mod, 45, 50)
      local warningEnd = step(w, mod, 45, 200)
      local critical = step(w, mod, 20, 0)
      local dropout = step(w, mod, nil, 0)
      local dropoutMid = step(w, mod, nil, 100)
      local recovery = step(w, mod, 80, 200)

      -- Time passes without callbacks: optional motion must land, not replay.
      mock.advance(1000)
      mock.setValue(ID_SOURCE, 45)
      local resume = countCall(function() mod.refresh(w) end)

      local transition = math.max(warning, warningMid, warningEnd, critical,
        dropout, dropoutMid, recovery, resume)
      rows[#rows + 1] = {
        label = label, stable = stable, ordinary = ordinary,
        transition = transition, bytes = bytes,
      }

      if ordinary >= ORDINARY_LIMIT then
        fail(label, string.format("ordinary %.0f >= %d instructions",
          ordinary, ORDINARY_LIMIT))
      end
      if transition >= TRANSITION_LIMIT then
        fail(label, string.format("transition %d >= %d instructions",
          transition, TRANSITION_LIMIT))
      end
      if bytes > ALLOCATION_LIMIT then
        fail(label, string.format("allocation %.0f > %d B/frame",
          bytes, ALLOCATION_LIMIT))
      end
      if w.motionState ~= retainedMotion or w.frame ~= retainedFrame then
        fail(label, "retained motion/frame table identity changed")
      end
      if tableSize(w.motionState) ~= retainedKeys then
        fail(label, string.format("motion scalar key count grew %d -> %d",
          retainedKeys, tableSize(w.motionState)))
      end
      if mock.objectCount() ~= retainedObjects then
        fail(label, string.format("LVGL object count changed %d -> %d",
          retainedObjects, mock.objectCount()))
      end
      if not w.barRenderState or w.barRenderState.state ~= "warning" then
        fail(label, "hidden resume did not expose raw WARNING immediately")
      end
      if not w.barRenderState.motionPaused
         or w.barRenderState.motionActive then
        fail(label, "hidden resume replayed optional motion")
      end
    end
  end
end

mock.tracking(true)

print("GaugePro Phase 6 motion sequence gate")
print(string.format("%d faces x %d orientations x %d profiles = %d cases",
  #FACES, #DIRECTIONS, #PROFILES, #rows))
print("")
print(string.format("%-34s %8s %10s %10s %10s", "case", "stable",
  "ordinary", "transition", "B/frame"))
print(string.rep("-", 80))
for _, r in ipairs(rows) do
  print(string.format("%-34s %8d %10.0f %10d %9.0f B", r.label,
    r.stable, r.ordinary, r.transition, r.bytes))
end
print(string.rep("-", 80))

if #failures > 0 then
  for _, message in ipairs(failures) do
    io.stderr:write("MOTION GATE FAILURE: " .. message .. "\n")
  end
  os.exit(1)
end

print(string.format("PASS: ordinary <%d, transitions <%d, allocations <=%d B/f",
  ORDINARY_LIMIT, TRANSITION_LIMIT, ALLOCATION_LIMIT))
print("PASS: retained object/table identity, fixed motion scalar footprint")
