-- Gauge Pro visual kit: dump main.lua's DEFS table as JSON.
--
-- Loads the REAL WIDGETS/GaugePro/main.lua under the same mock environment
-- tests/smoke_test.lua and dev/scenes.lua already use (tests/mock_env.lua),
-- so the option table is read from the widget's own source, never
-- hand-duplicated. This is the direct fix for the drift risk main.lua's own
-- header already warns about (Tanda 6 F-14: "options.lua's builder and
-- translator were deleted after verifying both byte-identical ... this
-- inline build is the ONLY builder").
--
-- Usage: lua defs_dump.lua <gaugepro-widget-dir> <out.json>

local widgetDir = arg[1] or "./"
local outPath = arg[2] or "defs.json"
local toolDir = (arg[0] or "defs_dump.lua"):gsub("defs_dump%.lua$", "")

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local json = dofile(toolDir .. "json_lite.lua")

-- Captured AFTER install() so the widget-option-type globals exist.
local TYPE_NAMES = {
  [VALUE] = "VALUE", [SOURCE] = "SOURCE", [BOOL] = "BOOL",
  [STRING] = "STRING", [TEXT_SIZE] = "TEXT_SIZE", [TIMER] = "TIMER",
  [SWITCH] = "SWITCH", [COLOR] = "COLOR", [ALIGNMENT] = "ALIGNMENT",
  [SLIDER] = "SLIDER", [CHOICE] = "CHOICE", [FILE] = "FILE",
}

local mod = dofile(widgetDir .. "main.lua")
local defs = mod.defs
if not defs then
  error("defs_dump: main.lua did not return a .defs table (needed for the "
    .. "visual kit; see WIDGETS/GaugePro/main.lua's returned table)")
end

-- One explicit row per option, in wire (0-based) order. Field names are
-- fixed/documented here, not whatever main.lua's DEFS happens to be named,
-- so downstream tooling (modelgen.py) has a stable schema to depend on.
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

json.writeFile(outPath, rows)

print(string.format("defs_dump: wrote %d options -> %s", #rows, outPath))
