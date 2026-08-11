-- Gauge Pro visual kit: dump both split frontends' DEFS tables as JSON.
--
-- Loads the REAL GaugeDialPro/main.lua and GaugeBarPro/main.lua under the mock
-- tests/smoke_test.lua and dev/scenes.lua already use (tests/mock_env.lua),
-- so both option tables are read from the widgets' own source, never
-- hand-duplicated. This is the direct fix for the drift risk main.lua's own
-- header already warns about (Tanda 6 F-14: "options.lua's builder and
-- translator were deleted after verifying both byte-identical ... this
-- inline build is the ONLY builder").
--
-- Usage: lua defs_dump.lua <gaugecore-source-dir> <repo-root> <out.json>

local coreDir = arg[1] or "./"
local repoRoot = arg[2] or "../../"
local outPath = arg[3] or "defs.json"
local toolDir = (arg[0] or "defs_dump.lua"):gsub("defs_dump%.lua$", "")

if string.sub(coreDir, -1) ~= "/" and string.sub(coreDir, -1) ~= "\\" then
  coreDir = coreDir .. "/"
end
if string.sub(repoRoot, -1) ~= "/" and string.sub(repoRoot, -1) ~= "\\" then
  repoRoot = repoRoot .. "/"
end

local mock = dofile(coreDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local json = dofile(toolDir .. "json_lite.lua")

-- Captured AFTER install() so the widget-option-type globals exist.
local TYPE_NAMES = {
  [VALUE] = "VALUE", [SOURCE] = "SOURCE", [BOOL] = "BOOL",
  [STRING] = "STRING", [TEXT_SIZE] = "TEXT_SIZE", [TIMER] = "TIMER",
  [SWITCH] = "SWITCH", [COLOR] = "COLOR", [ALIGNMENT] = "ALIGNMENT",
  [SLIDER] = "SLIDER", [CHOICE] = "CHOICE", [FILE] = "FILE",
}

local function dumpFront(folder, expectedFamily)
  local mod = dofile(repoRoot .. "WIDGETS/" .. folder .. "/main.lua")
  local defs = mod.defs
  if not defs or mod.family ~= expectedFamily then
    error("defs_dump: invalid " .. folder .. " frontend contract")
  end

  local rows = {}
  for i = 1, #defs do
    local d = defs[i]
    rows[i] = {
      index = i - 1,
      key = d.key,
      label = d.label,
      type = TYPE_NAMES[d.type] or tostring(d.type),
      since = d.since,
      default = d.default,
      choices = d.choices,
      min = d.min,
      max = d.max,
      field = d.field,
    }
  end
  return {
    folder = folder,
    family = mod.family,
    name = mod.name,
    coreApi = mod.coreApi,
    options = rows,
  }
end

local fronts = {
  dial = dumpFront("GaugeDialPro", "dial"),
  bar = dumpFront("GaugeBarPro", "bar"),
}

json.writeFile(outPath, { schema = 2, fronts = fronts })

print(string.format("defs_dump: wrote DialPro=%d BarPro=%d options -> %s",
  #fronts.dial.options, #fronts.bar.options, outPath))
