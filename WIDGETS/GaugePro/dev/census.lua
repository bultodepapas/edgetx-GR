-- GaugePro object census probe (Tanda 6 6.4 / F-16).
--
-- The DOCS.md §5.4 object table must be reproducible: this probe renders
-- the worst-case dial scene and the bar, and prints the per-kind census.
-- Usage: lua5.3 dev/census.lua <widget-dir>
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
  mock.setValue(ID_RSSI, 78)
  mock.setValue(3073, 31)
  mock.setValue(3074, 92)
  local mod = dofile(widgetDir .. "main.lua")
  local o = { Source = ID_RSSI }
  for k, v in pairs(ov) do o[k] = v end
  local opts = mock.makeOptions(mod.defs, o)
  local w = mod.create(zone, opts, widgetDir)
  w.mod = mod
  mod.update(w, opts)
  for _ = 1, 2 do mock.advance(50); mod.refresh(w) end
  return w, mod
end

local function census(_w, label)
  local counts = {}
  local total, retained = 0, 0
  for _, o in ipairs(mock.objects()) do
    retained = retained + 1
    if o.visible then
      counts[o.kind] = (counts[o.kind] or 0) + 1
      total = total + 1
    end
  end
  local order = { "arc", "circle", "label", "line", "rectangle", "triangle" }
  local parts = {}
  for _, k in ipairs(order) do
    if counts[k] then parts[#parts + 1] = k .. " " .. counts[k] end
  end
  print(string.format("%-44s visible %2d  retained %2d  %s", label, total,
    retained, table.concat(parts, ", ")))
end

print("GaugePro object census  (visible objects by kind)")
print("")
-- worst case: every feature ON - needle, Sections bands, scale labels
-- (270 deg), min/max markers+text, and a CRITICAL value so the state chip
-- and its label are visible (they hide in the normal state).
local w1 = build({ x = 0, y = 0, w = 200, h = 200 },
  { Style = 2, ColorMode = 5, Sweep = 1, ShowMinMax = 3, ShowChip = 1 })
mock.setValue(ID_RSSI, 22)              -- critical: chip + state label show
mock.advance(50); w1.mod.refresh(w1)
census(w1, "dial 200x200 needle/Sections/270/markers+text CRIT")
local w2 = build({ x = 0, y = 0, w = 200, h = 160 },
  { Style = 2, ColorMode = 2 })
census(w2, "dial 200x200x160 needle/Threshold")
local w3 = build({ x = 0, y = 0, w = 300, h = 70 }, { Style = 4 })
census(w3, "bar 300x70")
local w4 = build({ x = 0, y = 0, w = 60, h = 60 }, {})
census(w4, "dial 60x60 micro")
local w5 = build({ x = 0, y = 0, w = 300, h = 70 },
  { Style = 4, ColorMode = 5, ShowMinMax = 3 })
mock.setValue(ID_RSSI, 22)
mock.advance(50); w5.mod.refresh(w5)
census(w5, "bar 300x70 Sections/markers+text CRIT")
local w6 = build({ x = 0, y = 0, w = 300, h = 70 },
  { Style = 4, ColorMode = 4, Damping = 0 })
census(w6, "bar 300x70 spatial gradient")
local w7 = build({ x = 0, y = 0, w = 480, h = 120 },
  { Style = 4, ColorMode = 4, Surface = 3, BarEnds = 4,
    ShowMinMax = 3, Damping = 0 })
mock.setValue(ID_RSSI, 22)
mock.advance(50); w7.mod.refresh(w7)
census(w7, "bar 480x120 gradient/panel/chamfer/markers")
local faceRows = {
  { "Blocks", "24", "blocks 24" },
  { "Hex", "10", "true hex 10" },
  { "Ticks", "24", "fine ticks 24" },
  { "Steps", "10", "signal steps 10" },
}
for _, row in ipairs(faceRows) do
  local wf = build({ x = 0, y = 0, w = 480, h = 120 }, {
    Style = "Bar", BarFace = row[1], Segments = row[2],
    ColorMode = "Sections", Surface = "Theme panel", Damping = 0,
  })
  census(wf, "bar 480x120 " .. row[3] .. "/Sections/panel")
end
local wh = build({ x = 0, y = 0, w = 160, h = 44 }, {
  Style = "Bar", BarFace = "Hex", Segments = "10", Damping = 0,
})
census(wh, "bar 160x44 hex compact block fallback")
print("")
print("DOCS.md 5.4 uses the first row (worst case); the counts above are")
print("the reproducible source for the table.")
