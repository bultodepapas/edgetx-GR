-- Gauge Pro dev tooling: the OFFICIAL option collage.
--
-- One image showing every option and every state the widget can be in, drawn
-- from the same catalogue (dev/scenes.lua) and the same emitter
-- (dev/svgkit.lua) as the contract sheet and the individual shots. Three tools,
-- one source of truth: they cannot disagree about what the widget draws.
--
-- This is NOT dev/gallery.lua. The gallery is a working instrument - Spanish,
-- object censuses, overflow boxes, warning dots, an option-coverage audit - and
-- it exists to fail a review. This one is the picture in the README: English,
-- no diagnostics, nothing on it that only means something to someone who has
-- read the audit. Two audiences, two sheets, one catalogue.
--
--   lua5.3 dev/collage.lua ./ docs/            both themes, SVG + PNG
--   lua5.3 dev/collage.lua ./ docs/ --theme stock
--
-- Output is COMMITTED (docs/ is not gitignored, unlike dev/shots/): the README
-- links it, so it has to survive a clone.

local args = { ... }
local widgetDir, outDir, only = nil, nil, nil
do
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--theme" then i = i + 1; only = args[i]
    elseif string.sub(a, 1, 2) == "--" then
      io.stderr:write("collage: unknown option " .. a .. "\n"); os.exit(2)
    elseif not widgetDir then widgetDir = a
    elseif not outDir then outDir = a end
    i = i + 1
  end
end
widgetDir = widgetDir or "./"
if string.sub(widgetDir, -1) ~= "/" then widgetDir = widgetDir .. "/" end
outDir = outDir or (widgetDir .. "docs/")
if string.sub(outDir, -1) ~= "/" then outDir = outDir .. "/" end

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)
local svgkit = dofile(widgetDir .. "dev/svgkit.lua")
local scenes = dofile(widgetDir .. "dev/scenes.lua")

local fmt, floor, max = string.format, math.floor, math.max

-- ------------------------------------------------------------- English text --
--
-- The catalogue is written in the owner's language; this sheet is the one the
-- README points at, so it is English throughout. Keyed by the scene NAME
-- rather than by its title: names are the catalogue's stable identifier (they
-- are the SVG file names too), titles are prose and may be reworded.
--
-- A missing entry falls back to the catalogue title and is REPORTED, so a
-- scene added later cannot quietly put a Spanish caption on the official image.
local EN_SECTION = {
  ["estado"]  = { "State and availability",
    "The badge and the arc colour are the state signal. Every availability"
    .. " row must say something different, and true." },
  ["color"]   = { "Colour modes",
    "Each mode at both ends of its range. Rail and Sections keep showing"
    .. " their reference bands while critical." },
  ["escala"]  = { "Scales and thresholds",
    "Ranges that are not 0..100. A DESCENDING scale (Min > Max) is"
    .. " supported on purpose." },
  ["dial"]    = { "Dial options",
    "Every structural option, on and off, over the same base scene." },
  ["aguja"]   = { "Needle and damping",
    "The three-segment needle at both stops and at centre, and the effect"
    .. " of damping three frames after a step." },
  ["texto"]   = { "Value, unit and name",
    "Auto-fitted typography, decimals, and the strings most likely to"
    .. " overflow their box." },
  ["bateria"] = { "Battery and cells",
    "Aggregation of the CELLS table and state-of-charge percentage." },
  ["acento"]  = { "Accent colour",
    "The accent replaces the normal state's green. Each scene here is a"
    .. " fresh build." },
  ["barra"]   = { "Bar style",
    "The bar signals state exactly as the dial does: same badge, same"
    .. " pulse, same threshold marks." },
  ["zonas"]   = { "Zone matrix",
    "The same configuration in every zone size an EdgeTX layout can hand"
    .. " out. No text may overflow or cross the ring." },
}

local EN_TITLE = {
  ["st-nolink"] = "no link", ["st-nodata"] = "no data",
  ["st-nosource"] = "no source",
  ["sc-descending"] = "descending 100..0",
  ["sc-outofrange"] = "value off the scale",
  ["op-style-arc"] = "Style Arc (no needle)",
  ["op-chip-on"] = "State chip ON (no link)",
  ["op-chip-off"] = "State chip OFF (no link)",
  ["op-chip-off-crit"] = "State chip OFF, but CRIT",
  ["op-mm-text"] = "Min/max + text",
  ["ne-pos0"] = "low stop", ["ne-pos50"] = "centre",
  ["ne-pos100"] = "high stop",
  ["tx-prec0"] = "Decimals 0", ["tx-prec1"] = "Decimals 1",
  ["tx-prec2"] = "Decimals 2",
  ["tx-timer"] = "countdown timer elapsed",
  ["tx-scalelabels"] = "scale end labels",
  ["ba-rxbt"] = "RxBt, 4S latched",
  ["ac-default"] = "default (green)", ["ac-focus"] = "blue accent",
  ["ac-edit"] = "orange accent",
  ["color-static-crit"] = "Static - critical",
  ["color-threshold-crit"] = "Threshold - critical",
  ["color-rail-crit"] = "Rail - critical",
  ["color-gradient-crit"] = "Gradient - critical",
  ["color-sections-crit"] = "Sections - critical",
  ["color-static-ok"] = "Static - normal",
  ["color-threshold-ok"] = "Threshold - normal",
  ["color-rail-ok"] = "Rail - normal",
  ["color-gradient-ok"] = "Gradient - normal",
  ["color-sections-ok"] = "Sections - normal",
  ["br-crit"] = "critical",
  ["br-short"] = "160 x 44 (badge at its minimum)",
  ["br-nochip"] = "chip Off: CRIT still shows",
  ["br-auto"] = "Auto -> bar (ratio > 2.6)",
}

local missingEn = {}
local function titleOf(case)
  local t = EN_TITLE[case.name]
  if t then return t end
  -- Anything with a non-ASCII byte, or a known Spanish word, is a catalogue
  -- title that has not been translated yet.
  local raw = case.title or case.name
  if string.find(raw, "[\128-\255]")
    or string.find(raw, "sin ") or string.find(raw, "critico")
    or string.find(raw, "por defecto") or string.find(raw, "acento") then
    missingEn[#missingEn + 1] = case.name
  end
  return raw
end

-- ------------------------------------------------------------------ layout --

local PAD, CONTENT_W, GAP, COLGAP = 26, 1180, 22, 16
local TILE_MIN_W, CAP_LEAD = 150, 14

-- Small zones are enlarged so a 60 px dial is actually inspectable; large ones
-- are shrunk so a 480x272 tile does not own a whole row by itself.
local function tileScale(zw, zh)
  local s
  if zw < 110 then s = 2.0
  elseif zw < 210 then s = 1.4
  elseif zw < 320 then s = 1.15
  else s = 0.95 end
  if zh * s > 300 then s = 300 / zh end
  return s
end

local function shorten(s, n)
  s = tostring(s)
  if #s <= n then return s end
  return string.sub(s, 1, max(n - 1, 1)) .. "\u{2026}"
end

-- The options this scene actually changes - the point of the whole sheet.
local function optionLine(case)
  local opts = case.opts or {}
  local keys = {}
  for k in pairs(opts) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = opts[k]
    if type(v) == "boolean" then v = v and "on" or "off" end
    parts[#parts + 1] = k .. " " .. tostring(v)
  end
  if case.source then
    table.insert(parts, 1, "source " .. case.source)
  end
  if #parts == 0 then return "defaults" end
  return table.concat(parts, ", ")
end

local function versionInfo()
  local function sh(cmd)
    local f = io.popen(cmd .. " 2>&1")
    if not f then return nil end
    local out = f:read("*a") or ""
    f:close()
    return (string.gsub(out, "%s+$", ""))
  end
  local sha = sh("git rev-parse --short HEAD") or "?"
  local branch = sh("git rev-parse --abbrev-ref HEAD") or "?"
  return sha, branch, os.date("!%Y-%m-%d")
end

-- ------------------------------------------------------------------ render --

local function renderCollage(theme, results)
  local cv = svgkit.newCanvas(theme)
  local pal = cv.pal
  local body = {}
  local function put(s) body[#body + 1] = s end
  local function text(x, y, s, size, fill, weight, anchor)
    put(fmt('<text x="%.1f" y="%.1f" font-size="%.1f" fill="%s"'
      .. ' font-weight="%s" text-anchor="%s"'
      .. ' font-family="DejaVu Sans, Verdana, sans-serif">%s</text>',
      x, y, size, fill, weight or "400", anchor or "start", svgkit.esc(s)))
  end

  local sha, branch, date = versionInfo()
  local y = PAD

  -- ---- header -------------------------------------------------------------
  put(fmt('<rect x="%d" y="%d" width="%d" height="96" rx="12" fill="%s"'
    .. ' stroke="%s"/>', PAD, y, CONTENT_W, pal.panel, pal.rule))
  text(PAD + 24, y + 36, "Gauge Pro", 27, pal.ink, "700")
  text(PAD + 24, y + 60,
    "Every option and every state, drawn by the widget itself.", 13, pal.dim)
  text(PAD + 24, y + 82, fmt(
    "%d scenes  \u{00b7}  %s theme  \u{00b7}  %s@%s  \u{00b7}  %s",
    #results, theme, branch, sha, date), 11, pal.dim)
  y = y + 96 + GAP

  -- ---- sections -----------------------------------------------------------
  local bySection = {}
  for _, r in ipairs(results) do
    local t = bySection[r.case.section]
    if not t then t = {}; bySection[r.case.section] = t end
    t[#t + 1] = r
  end

  for _, sec in ipairs(scenes.sections) do
    local rows = bySection[sec.key]
    if rows and #rows > 0 then
      local en = EN_SECTION[sec.key]
      put(fmt('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s"/>',
        PAD, y, PAD + CONTENT_W, y, pal.rule))
      text(PAD, y + 22, en and en[1] or sec.title, 17, pal.ink, "700")
      text(PAD, y + 39, en and en[2] or sec.note, 11, pal.dim)
      y = y + 52

      -- Captions align on ONE baseline per row, taken from the tallest tile
      -- in it. Hanging each caption off its own image left a row of mixed
      -- zone sizes looking like a broken table.
      local rowItems, rowW, rowH, rowImgH = {}, 0, 0, 0
      local function flushRow()
        if #rowItems == 0 then return end
        local x = PAD
        for _, it in ipairs(rowItems) do
          put(fmt('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="5"'
            .. ' fill="%s" stroke="%s"/>',
            x - 1, y - 1, it.imgW + 2, it.imgH + 2, pal.bg, pal.rule))
          cv.out = body
          cv:scene(it.r.objects, it.r.zone, x, y, it.scale, it.r.case.name)
          local ty = y + rowImgH + 15
          text(x, ty, shorten(it.title, floor(it.colW / 5.6)), 12.5, pal.ink,
               "700")
          ty = ty + CAP_LEAD
          -- The zone-matrix scenes are TITLED by their zone, so printing it
          -- again underneath just reads as a stutter.
          local zoneStr = fmt("%d x %d", it.r.zone.w, it.r.zone.h)
          if it.title ~= zoneStr then
            text(x, ty, zoneStr, 10.5, pal.dim)
            ty = ty + CAP_LEAD
          end
          text(x, ty, shorten(it.opts, floor(it.colW / 4.7)), 10.5, pal.dim)
          x = x + it.colW + COLGAP
        end
        y = y + rowH + GAP
        rowItems, rowW, rowH, rowImgH = {}, 0, 0, 0
      end

      for _, r in ipairs(rows) do
        local zw, zh = r.case.zone[1], r.case.zone[2]
        local scale = tileScale(zw, zh)
        local imgW, imgH = zw * scale, zh * scale
        local colW = max(imgW, TILE_MIN_W)
        if rowW > 0 and rowW + colW > CONTENT_W then flushRow() end
        local h = max(rowImgH, imgH) + 15 + CAP_LEAD * 3
        rowItems[#rowItems + 1] = { r = r, scale = scale, imgW = imgW,
          imgH = imgH, colW = colW, title = titleOf(r.case),
          opts = optionLine(r.case) }
        rowW = rowW + colW + COLGAP
        rowImgH = max(rowImgH, imgH)
        rowH = max(rowH, h)
      end
      flushRow()
      y = y + 8
    end
  end

  -- ---- footer -------------------------------------------------------------
  put(fmt('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s"/>',
    PAD, y, PAD + CONTENT_W, y, pal.rule))
  y = y + 20
  text(PAD, y, "Generated by dev/collage.lua from dev/scenes.lua - regenerate,"
    .. " do not edit. Full reference: DOCS.md", 11, pal.dim)
  y = y + PAD

  local totalW = CONTENT_W + PAD * 2
  local head = fmt('<svg viewBox="0 0 %d %.0f" width="%d" height="%.0f"'
    .. ' xmlns="http://www.w3.org/2000/svg">\n'
    .. '<rect width="%d" height="%.0f" fill="%s"/>',
    totalW, y, totalW, y, totalW, y, pal.bg)
  return head .. "\n" .. table.concat(body, "\n") .. "\n</svg>"
end

-- -------------------------------------------------------------------- main --

local cases = scenes.allCases()

local function buildAll()
  local out = {}
  for _, c in ipairs(cases) do
    local ok, ctx = pcall(scenes.build, mock, widgetDir, c)
    if not ok then
      io.stderr:write(fmt("collage: %s failed: %s\n", c.name, tostring(ctx)))
    else
      local snapshot = {}
      for _, o in ipairs(mock.objects()) do
        if o.visible then snapshot[#snapshot + 1] = o end
      end
      out[#out + 1] = { case = c, zone = ctx.zone, objects = snapshot }
    end
  end
  return out
end

local function writeFile(path, text)
  local f, err = io.open(path, "w")
  if not f then
    io.stderr:write("collage: cannot write " .. path .. "\n  "
      .. tostring(err) .. "\n  (create the directory first)\n")
    os.exit(2)
  end
  f:write(text)
  f:close()
end

local themes = only and { only } or svgkit.paletteNames()
local written = {}
for _, theme in ipairs(themes) do
  -- The widget READS its theme (theme.labelOn picks the badge ink by measuring
  -- the fill against the theme's text roles), so the mock's colour table has to
  -- be this palette's before anything is built - otherwise the sheet shows an
  -- ink the radio would not have chosen.
  mock.setThemeColors(svgkit.themeColors(theme))
  local results = buildAll()
  local name = (theme == "stock") and "gauge-pro-options"
    or ("gauge-pro-options-" .. theme)
  local path = outDir .. name .. ".svg"
  writeFile(path, renderCollage(theme, results))
  written[#written + 1] = path
end

for _, p in ipairs(written) do print("wrote " .. p) end
if #missingEn > 0 then
  local seen, uniq = {}, {}
  for _, n in ipairs(missingEn) do
    if not seen[n] then seen[n] = true; uniq[#uniq + 1] = n end
  end
  io.stderr:write("collage: " .. #uniq .. " scene(s) have no English caption"
    .. " (add them to EN_TITLE): " .. table.concat(uniq, ", ") .. "\n")
end
