-- GaugePro Phase 6 deterministic motion filmstrips.
--
-- This is not a hand-drawn mock-up. Every frame is the actual retained LVGL
-- object tree after a real create/update/refresh sequence, serialized by the
-- same svgkit used by the complete visual gallery.
--
-- Usage: lua5.3 dev/motion_filmstrip.lua <widget-dir> [output-dir]

local widgetDir = arg[1] or "./"
if string.sub(widgetDir, -1) ~= "/" then widgetDir = widgetDir .. "/" end
local outDir = arg[2] or (widgetDir .. "docs/phase6/motion/")
if string.sub(outDir, -1) ~= "/" then outDir = outDir .. "/" end

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)
local svgkit = dofile(widgetDir .. "dev/svgkit.lua")

local ID_SOURCE = 101
local PAGE_W, PAD, GAP = 1460, 32, 14
local THEMES = { "stock", "dark", "highcontrast" }

local function ensureDir(path)
  os.execute(string.format('mkdir "%s" 2>nul', path))
end

local function writeFile(path, value)
  local f, err = io.open(path, "w")
  if not f then error("motion filmstrip: " .. tostring(err)) end
  f:write(value)
  f:close()
end

local function esc(s) return svgkit.esc(tostring(s or "")) end

local function registerRadio()
  mock.reset()
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0 }
  mock.addField(ID_SOURCE, "Ail")
end

local purple = lcd.RGB(112, 24, 184)
local yellow = lcd.RGB(248, 216, 24)
local cyan = lcd.RGB(16, 184, 232)

local BASE = {
  Source = ID_SOURCE, Style = "Bar", Scale = "Manual",
  Min = 0, Max = 100, Warn = 55, Crit = 35, Damping = 0,
  Palette = "Custom 3", Accent = purple, WarnClr = yellow, CritClr = cyan,
  ColorMode = "Sections", Surface = "Theme panel", ShowMinMax = "Off",
  ScaleMarks = "Thresholds", ValuePos = "Inside", LabelPos = "Above",
}

local function options(extra)
  local out = {}
  for k, v in pairs(BASE) do out[k] = v end
  for k, v in pairs(extra or {}) do out[k] = v end
  return out
end

local CASES = {
  {
    title = "Refined / semantic colour transition",
    note = "WARN text and badge are raw-immediate; only the fill colour travels to the exact authored yellow endpoint.",
    zone = { w = 320, h = 90 }, scale = 0.78, initial = 78,
    options = options{ Motion = "Refined", BarHead = "Line" },
    steps = {
      { ms = 0, value = 45, label = "WARN enters" },
      { ms = 50, value = 45, label = "25% colour" },
      { ms = 50, value = 45, label = "50% colour" },
      { ms = 50, value = 45, label = "75% colour" },
      { ms = 50, value = 45, label = "exact endpoint" },
    },
  },
  {
    title = "Expressive / rearmable one-shot head",
    note = "A material same-band move gets one short positional emphasis; it cannot become permanent shimmer on noisy telemetry.",
    zone = { w = 320, h = 90 }, scale = 0.78, initial = 68,
    options = options{ Motion = "Expressive", BarHead = "Cap" },
    steps = {
      { ms = 0, value = 90, label = "move detected" },
      { ms = 50, value = 68, label = "one-shot holds" },
      { ms = 50, value = 90, label = "no retrigger" },
      { ms = 100, value = 68, label = "settling" },
      { ms = 100, value = 90, label = "quiet endpoint" },
    },
  },
  {
    title = "Refined Blocks / segment activation settle",
    note = "The exact position head briefly emphasizes the newly activated cell; cell colour and telemetry position remain truthful.",
    zone = { w = 320, h = 90 }, scale = 0.78, initial = 68,
    options = options{
      Motion = "Refined", BarFace = "Blocks", Segments = "10",
      BarHead = "Line",
    },
    steps = {
      { ms = 0, value = 92, label = "cell activates" },
      { ms = 50, value = 92, label = "strong settle" },
      { ms = 50, value = 92, label = "soft settle" },
      { ms = 60, value = 92, label = "exact head" },
      { ms = 60, value = 92, label = "stable" },
    },
  },
  {
    title = "Essential / truthful dropout fade",
    note = "Availability changes immediately while the last valid geometry leaves over 180 ms; no invented position is shown.",
    zone = { w = 320, h = 90 }, scale = 0.78, initial = 72,
    options = options{ Motion = "Essential", BarHead = "Dot" },
    steps = {
      { ms = 0, available = false, label = "NO DATA now" },
      { ms = 50, available = false, label = "fade 25%" },
      { ms = 50, available = false, label = "fade 50%" },
      { ms = 50, available = false, label = "fade 75%" },
      { ms = 50, available = false, label = "geometry gone" },
    },
  },
  {
    title = "Refined / immediate CRIT and calm 1 Hz breath",
    note = "Critical colour never tweens. The retained fill uses a four-phase pulse and returns exactly to full opacity each second.",
    zone = { w = 320, h = 90 }, scale = 0.78, initial = 72,
    options = options{ Motion = "Refined", BarHead = "Needle" },
    steps = {
      { ms = 0, value = 20, label = "CRIT immediate" },
      { ms = 250, value = 20, label = "breath midpoint" },
      { ms = 250, value = 20, label = "calm trough" },
      { ms = 250, value = 20, label = "breath midpoint" },
      { ms = 250, value = 20, label = "exact full" },
    },
  },
  {
    title = "Vertical Steps / the same motion grammar",
    note = "Orientation changes geometry, not semantics: bottom-up steps retain the same exact head, state and bounded settle contract.",
    zone = { w = 120, h = 260 }, scale = 0.68, initial = 68,
    options = options{
      Motion = "Refined", BarDir = "Vertical", BarFace = "Steps",
      Segments = "10", BarHead = "Line", ValuePos = "Above",
    },
    steps = {
      { ms = 0, value = 92, label = "step activates" },
      { ms = 50, value = 92, label = "strong settle" },
      { ms = 50, value = 92, label = "soft settle" },
      { ms = 60, value = 92, label = "exact head" },
      { ms = 60, value = 92, label = "stable" },
    },
  },
  {
    title = "Micro / Expressive automatically reduces to Refined",
    note = "The user's choice is preserved, but optional head spectacle is removed when it would compete with the value and state.",
    zone = { w = 160, h = 44 }, scale = 1.20, initial = 68,
    options = options{
      Motion = "Expressive", Surface = "Transparent", BarHead = "Cap",
      ScaleMarks = "Off", ValuePos = "Inside", LabelPos = "Off",
    },
    steps = {
      { ms = 0, value = 90, label = "reduced profile" },
      { ms = 50, value = 68, label = "exact position" },
      { ms = 50, value = 90, label = "no head boost" },
      { ms = 100, value = 68, label = "calm" },
      { ms = 100, value = 90, label = "stable" },
    },
  },
}

local function build(case)
  registerRadio()
  mock.setValue(ID_SOURCE, case.initial)
  local mod = dofile(widgetDir .. "main.lua")
  local opts = mock.makeOptions(mod.defs, case.options)
  local zone = { x = 0, y = 0, w = case.zone.w, h = case.zone.h }
  local w = mod.create(zone, opts, widgetDir)
  mod.update(w, opts)
  for _ = 1, 3 do
    mock.advance(50)
    mod.refresh(w)
  end
  return w, mod, zone
end

local function caption(w, step, elapsed)
  local s = w.barRenderState or {}
  local availability = w.data and w.data.availability or "unknown"
  local pulseTarget = w.ui and (w.ui.pulseTargets or w.ui.fill)
  if pulseTarget and pulseTarget[1] then pulseTarget = pulseTarget[1] end
  local paintedOpacity = pulseTarget and pulseTarget.props
    and pulseTarget.props.opacity or s.opacity
  local effects = {}
  if s.colorTransition then effects[#effects + 1] = "colour tween" end
  if (s.headBoost or 0) > 0 then
    effects[#effects + 1] = "head +" .. tostring(s.headBoost)
  end
  if (s.settleLevel or 0) > 0 then
    effects[#effects + 1] = "settle " .. tostring(s.settleLevel)
  end
  if s.motionReduced then effects[#effects + 1] = "auto-reduced" end
  if #effects == 0 then effects[1] = "retained / exact" end
  return string.format("+%d ms  %s", elapsed, step.label),
    string.format("raw %s / %s  ·  %s  ·  opa %s",
      tostring(s.state), tostring(availability), table.concat(effects, " + "),
      tostring(paintedOpacity or "-"))
end

local function emitText(cv, x, y, value, size, color, weight, anchor)
  cv:emit(string.format('<text x="%.1f" y="%.1f" font-size="%.1f" fill="%s" font-weight="%s" text-anchor="%s" font-family="DejaVu Sans, Verdana, sans-serif">%s</text>',
    x, y, size, color, weight or "400", anchor or "start", esc(value)))
end

local function render(theme)
  mock.setThemeColors(svgkit.themeColors(theme))
  local cv = svgkit.newCanvas(theme)
  local pal = cv.pal
  local y = PAD

  emitText(cv, PAD, y + 22, "GaugePro Bar v2 · Phase 6 motion language", 24,
    pal.ink, "700")
  emitText(cv, PAD, y + 46,
    "Actual retained widget frames · " .. theme
      .. " theme · purple / yellow / cyan custom severity",
    12, pal.dim)
  y = y + 74

  local records = {}
  for _, case in ipairs(CASES) do
    local w, mod, zone = build(case)
    emitText(cv, PAD, y + 18, case.title, 17, pal.ink, "700")
    emitText(cv, PAD, y + 38, case.note, 11, pal.dim)
    y = y + 52

    local tileW = zone.w * case.scale
    local tileH = zone.h * case.scale
    -- Narrow vertical/micro widgets still need a readable evidence caption.
    -- Give each frame a minimum cell without enlarging the widget itself.
    local cellW = math.max(tileW, 240)
    local rowW = #case.steps * cellW + (#case.steps - 1) * GAP
    local cellX = PAD + math.max(0, (PAGE_W - PAD * 2 - rowW) / 2)
    local elapsed = 0
    for _, step in ipairs(case.steps) do
      local x = cellX + (cellW - tileW) / 2
      elapsed = elapsed + (step.ms or 0)
      if step.available == false then
        mock.setValue(ID_SOURCE, nil)
      else
        mock.setValue(ID_SOURCE, step.value)
      end
      mock.advance(step.ms or 0)
      mod.refresh(w)
      cv:emit(string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="6" fill="%s" stroke="%s"/>',
        x - 1, y - 1, tileW + 2, tileH + 2, pal.bg, pal.rule))
      cv:scene(mock.objects(), zone, x, y, case.scale,
        case.title .. " / " .. step.label)
      local line1, line2 = caption(w, step, elapsed)
      emitText(cv, cellX + cellW / 2, y + tileH + 17, line1, 10.5,
        pal.ink, "600", "middle")
      emitText(cv, cellX + cellW / 2, y + tileH + 33, line2, 9.5,
        pal.dim, "400", "middle")
      records[#records + 1] = string.format(
        "%s|%s|%d|%s|%s|%s|%s|%s", theme, case.title, elapsed,
        tostring(w.barRenderState.state),
        tostring(w.data and w.data.availability),
        tostring(w.barRenderState.motionProfile),
        tostring(w.barRenderState.headBoost),
        tostring(w.barRenderState.settleLevel))
      cellX = cellX + cellW + GAP
    end
    y = y + tileH + 58
    cv:emit(string.format('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s"/>',
      PAD, y - 17, PAGE_W - PAD, y - 17, pal.rule))
  end

  local height = y + PAD
  local head = string.format('<svg viewBox="0 0 %d %.0f" width="%d" height="%.0f" xmlns="http://www.w3.org/2000/svg"><rect width="%d" height="%.0f" fill="%s"/>',
    PAGE_W, height, PAGE_W, height, PAGE_W, height, pal.bg)
  return head .. "\n" .. table.concat(cv.out, "\n") .. "\n</svg>",
    cv:uniqueWarnings(), records
end

ensureDir(outDir)
local allRecords, failures = {}, {}
for _, theme in ipairs(THEMES) do
  local svg, warnings, records = render(theme)
  local path = outDir .. "motion-filmstrip-" .. theme .. ".svg"
  writeFile(path, svg)
  print(path)
  for _, record in ipairs(records) do allRecords[#allRecords + 1] = record end
  for _, warning in ipairs(warnings) do
    failures[#failures + 1] = theme .. ": " .. warning
  end
end
writeFile(outDir .. "motion-filmstrip-manifest.txt",
  table.concat(allRecords, "\n") .. "\n")

if #failures > 0 then
  for _, failure in ipairs(failures) do
    io.stderr:write("FILMSTRIP FAILURE: " .. failure .. "\n")
  end
  os.exit(1)
end
print(string.format("PASS: %d deterministic production frames, no render warnings",
  #allRecords))
