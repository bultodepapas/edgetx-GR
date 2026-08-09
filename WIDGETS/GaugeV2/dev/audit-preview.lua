-- GaugeV2 audit preview: like dev/preview.lua, but the SVG emitter models the
-- firmware/LVGL semantics that dev/preview.lua glosses over:
--
--   * arc angles are normalised the way lv_arc_set_*_angle does
--     (`if (a > 360) a -= 360`, ONCE), and a zero-length arc is skipped the way
--     lv_draw_arc does (`if (start_angle == end_angle) return;`).
--   * labels wrap at their declared width and are clipped at their declared
--     height, the way etx_label_create + LV_LABEL_LONG_WRAP behaves.
--   * overflowing labels are outlined so the clipping is visible.
--
--   lua5.3 dev/audit-preview.lua <widget-dir> [out.html]
--
-- Use this one, not dev/preview.lua, when reviewing anything angle- or
-- text-fit related: dev/preview.lua draws the angles the widget *asked* for,
-- which is not always what LVGL renders.

local widgetDir = arg[1] or "./"
local outPath = arg[2] or (widgetDir .. "dev/audit-preview.html")

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

-- Palettes come from dev/svgkit.lua - the SAME tables the gallery and the
-- shot tool paint with, and the same ones the widget's own lcd.getColor is
-- pointed at before each build. This file used to carry a third invented
-- palette of its own (a green COLOR_THEME_ACTIVE, an amber
-- COLOR_THEME_WARNING, a near-black background); EdgeTX's stock theme has a
-- yellow ACTIVE, a RED WARNING and a near-WHITE background, so the picture
-- was of a radio that does not exist. Four review rounds missed a 1.13:1
-- normal state because of exactly this (Tanda 8 F7).
local svgkit = dofile(widgetDir .. "dev/svgkit.lua")
local PALETTES = {
  stock = svgkit.palette("stock"),
  dark = svgkit.palette("dark"),
}

-- mock lcd.sizeText heights, so the emitter measures exactly what layout did
local FONT_PX = { [0x000]=16, [0x200]=11, [0x300]=13, [0x400]=24,
                  [0x500]=32, [0x600]=48, [0x700]=48 }

local warnings = {}
local function warn(fmt, ...) warnings[#warnings+1] = string.format(fmt, ...) end

local function colorOf(pal, flags, fallback)
  if flags == nil then return fallback or "none" end
  local c = pal[flags]
  if c then return c end
  if flags > 0x100000 then
    local v = flags - 0x100000
    return string.format("#%02x%02x%02x", (v>>16)&0xff, (v>>8)&0xff, v&0xff)
  end
  return fallback or "#ff00ff"
end

local function polar(cx, cy, r, deg)
  local a = deg * math.pi / 180
  return cx + r * math.cos(a), cy + r * math.sin(a)
end

-- lv_arc_set_start_angle / lv_arc_set_end_angle: subtract 360 ONCE
local function lvNorm(a)
  a = math.floor(a + 0.5)
  if a > 360 then a = a - 360 end
  return a
end

-- Returns start, sweep in LVGL terms, or nil when nothing is drawn.
local function lvArcSpan(a1, a2)
  local s, e = lvNorm(a1), lvNorm(a2)
  if s == e then return nil end            -- lv_draw_arc early-out
  local sweep = e - s
  if sweep < 0 then sweep = sweep + 360 end
  return s, sweep
end

local function arcPath(cx, cy, r, a1, a2)
  local s, sweep = lvArcSpan(a1, a2)
  if not s then return nil end
  if sweep >= 359.5 then
    local x1, y1 = polar(cx, cy, r, s)
    local x2, y2 = polar(cx, cy, r, s + 180)
    return string.format("M %.2f %.2f A %.2f %.2f 0 1 1 %.2f %.2f"
      .. " A %.2f %.2f 0 1 1 %.2f %.2f",
      x1, y1, r, r, x2, y2, r, r, x1, y1)
  end
  local x1, y1 = polar(cx, cy, r, s)
  local x2, y2 = polar(cx, cy, r, s + sweep)
  return string.format("M %.2f %.2f A %.2f %.2f 0 %d 1 %.2f %.2f",
    x1, y1, r, r, (sweep > 180) and 1 or 0, x2, y2)
end

local function esc(s)
  s = tostring(s or "")
  s = string.gsub(s, "&", "&amp;")
  s = string.gsub(s, "<", "&lt;")
  return (string.gsub(s, ">", "&gt;"))
end

-- Exactly the mock's lcd.sizeText width, so "does it fit" matches what
-- layout.lua measured when it sized the box.
local function textW(text, size) return math.floor(#text * (size * 0.55)) end

-- LV_LABEL_LONG_WRAP: greedy wrap at the box width, clip at the box height.
local function wrapLines(text, w, size)
  if textW(text, size) <= w then return { text }, false end
  local maxChars = math.max(1, math.floor(w / (size * 0.55)))
  local lines, i = {}, 1
  while i <= #text do
    lines[#lines+1] = string.sub(text, i, i + maxChars - 1)
    i = i + maxChars
  end
  return lines, true
end

local nextClip = 0

local function emit(out, obj, pal, label)
  local p = obj.props
  local opa = (p.opacity or 255) / 255
  if obj.kind == "arc" then
    local bgOpa = (p.bgOpacity or 0) / 255
    if bgOpa > 0 and p.bgStartAngle then
      local d = arcPath(p.x, p.y, p.radius, p.bgStartAngle, p.bgEndAngle)
      if d then
        out[#out+1] = string.format(
          '<path d="%s" fill="none" stroke="%s" stroke-width="%d"'
            .. ' stroke-opacity="%.2f" stroke-linecap="%s"/>',
          d, colorOf(pal, p.bgColor or p.color), p.thickness or 2, bgOpa,
          (p.rounded == 1) and "round" or "butt")
      else
        warn("%s: arc background start==end after LVGL normalisation"
          .. " (%d..%d) -> NOT DRAWN",
             label, p.bgStartAngle, p.bgEndAngle)
      end
    end
    if opa > 0 and p.startAngle then
      local d = arcPath(p.x, p.y, p.radius, p.startAngle, p.endAngle)
      if d then
        out[#out+1] = string.format(
          '<path d="%s" fill="none" stroke="%s" stroke-width="%d"'
            .. ' stroke-opacity="%.2f" stroke-linecap="%s"/>',
          d, colorOf(pal, p.color), p.thickness or 2, opa,
          (p.rounded == 1) and "round" or "butt")
      end
    end
  elseif obj.kind == "line" then
    local pts = {}
    for _, pt in ipairs(p.pts or {}) do
      pts[#pts+1] = string.format("%.1f,%.1f", pt[1], pt[2])
    end
    out[#out+1] = string.format(
      '<polyline points="%s" fill="none" stroke="%s" stroke-width="%d"'
        .. ' stroke-opacity="%.2f" stroke-linecap="%s"/>',
      table.concat(pts, " "), colorOf(pal, p.color), p.thickness or 1, opa,
      (p.rounded == 1) and "round" or "butt")
  elseif obj.kind == "triangle" then
    local pts = {}
    for _, pt in ipairs(p.pts or {}) do
      pts[#pts+1] = string.format("%.1f,%.1f", pt[1], pt[2])
    end
    out[#out+1] = string.format('<polygon points="%s" fill="%s" fill-opacity="%.2f"/>',
      table.concat(pts, " "), colorOf(pal, p.color), opa)
  elseif obj.kind == "circle" then
    out[#out+1] = string.format(
      '<circle cx="%d" cy="%d" r="%d" fill="%s" fill-opacity="%.2f"/>',
      p.x, p.y, p.radius, colorOf(pal, p.color), opa)
  elseif obj.kind == "rectangle" then
    out[#out+1] = string.format(
      '<rect x="%d" y="%d" width="%d" height="%d" rx="%d"'
        .. ' fill="%s" fill-opacity="%.2f"/>',
      p.x, p.y, p.w or 0, p.h or 0, p.rounded or 0, colorOf(pal, p.color), opa)
  elseif obj.kind == "label" then
    local text = tostring(p.text or "")
    if text == "" then return end
    local size = FONT_PX[p.font or 0] or 16
    local bw, bh = p.w or 0, p.h or 0
    local lines, wrapped = wrapLines(text, bw, size)
    local lineH = size
    local fits = math.max(1, math.floor(bh / lineH))
    if wrapped then
      warn("%s: label %q needs %d px in a %d px box -> wraps to %d lines, %d visible",
           label, text, textW(text, size), bw, #lines, math.min(fits, #lines))
    end
    nextClip = nextClip + 1
    local cid = "c" .. nextClip
    out[#out+1] = string.format(
      '<clipPath id="%s"><rect x="%d" y="%d" width="%d" height="%d"/>'
        .. '</clipPath>',
      cid, p.x, p.y, bw, bh)
    out[#out+1] = string.format('<g clip-path="url(#%s)">', cid)
    local anchor, x = "start", p.x
    if p.align == CENTER then anchor, x = "middle", p.x + bw/2
    elseif p.align == RIGHT then anchor, x = "end", p.x + bw end
    for i = 1, #lines do
      out[#out+1] = string.format(
        '<text x="%.1f" y="%.1f" font-size="%d" fill="%s"'
        .. ' text-anchor="%s"'
        .. ' font-family="DejaVu Sans, Verdana, sans-serif"'
        .. ' fill-opacity="%.2f">%s</text>',
        x, p.y + (i-1)*lineH + size*0.78, size, colorOf(pal, p.color),
        anchor, opa, esc(lines[i]))
    end
    out[#out+1] = "</g>"
    if wrapped then
      out[#out+1] = string.format(
        '<rect x="%d" y="%d" width="%d" height="%d" fill="none"'
          .. ' stroke="#ff3b30" stroke-width="1" stroke-dasharray="3 2"/>',
        p.x, p.y, bw, bh)
    end
  end
end

local function renderSvg(zone, theme, scale, label)
  local pal = PALETTES[theme]
  local out = {}
  out[#out+1] = string.format(
    '<svg viewBox="0 0 %d %d" width="%d" height="%d"'
      .. ' xmlns="http://www.w3.org/2000/svg">',
    zone.w, zone.h, math.floor(zone.w*scale), math.floor(zone.h*scale))
  out[#out+1] = string.format('<rect width="%d" height="%d" fill="%s"/>',
    zone.w, zone.h, pal.bg)
  for _, obj in ipairs(mock.objects()) do
    if obj.visible then emit(out, obj, pal, label) end
  end
  out[#out+1] = "</svg>"
  return table.concat(out, "\n")
end

-- ---- simulated radio -----------------------------------------------------

local ID_RSSI, ID_MIN, ID_MAX = 3072, 3073, 3074
local ID_RXBT, ID_RXBT_MIN, ID_RXBT_MAX = 3081, 3082, 3083
local ID_TIMER, ID_STICK, ID_TEMP = 200, 100, 3078

local function build(zone, overrides, value, history, frames, post)
  mock.reset()
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0 }
  mock.addField(ID_RSSI, "RSSI", 17)
  mock.addField(ID_MIN, "RSSI-", 17)
  mock.addField(ID_MAX, "RSSI+", 17)
  mock.addField(ID_RXBT, "RxBt", 1)
  mock.addField(ID_RXBT_MIN, "RxBt-", 1)
  mock.addField(ID_RXBT_MAX, "RxBt+", 1)
  mock.addField(ID_TIMER, "timer1")
  mock.addField(ID_TEMP, "T1", 11)
  mock.addField(ID_STICK, "Thr")
  mock.addField(3075, "Cels", 1)
  mock.sim.sensors[0] = { name = "RSSI", prec = 0, unit = 17 }
  mock.sim.sensors[1] = { name = "RxBt", prec = 2, unit = 1 }
  local src = overrides.__src or ID_RSSI
  mock.setValue(src, value)
  if history then
    mock.setValue(overrides.__hmin or ID_MIN, history[1])
    mock.setValue(overrides.__hmax or ID_MAX, history[2])
  end
  local mod = dofile(widgetDir .. "main.lua")
  local o = { Source = src }
  for k, v in pairs(overrides) do
    if string.sub(k, 1, 2) ~= "__" then o[k] = v end
  end
  local opts = mock.makeOptions(mod.defs, o)
  local w = mod.create(zone, opts, widgetDir)
  mod.update(w, opts)
  for _ = 1, (frames or 30) do
    mock.advance(50)
    mod.refresh(w)
  end
  if post then post(w, mod, opts, src) end
  return w
end

-- ---- page ----------------------------------------------------------------

local html = {
  "<!doctype html><meta charset='utf-8'><title>GaugeV2 audit preview</title>",
  "<style>",
  "body{font:13px system-ui,sans-serif;background:#22262b;color:#e6e6e6;margin:20px}",
  "h1{font-size:17px}h2{font-size:15px;margin:26px 0 10px;color:#ffd479;",
  "border-bottom:1px solid #3a4048;padding-bottom:5px}",
  ".grid{display:flex;flex-wrap:wrap;gap:14px}",
  ".card{background:#2c3138;border-radius:9px;padding:10px}",
  ".card h3{font-size:11px;font-weight:600;margin:0 0 6px;color:#a8b2bd}",
  ".pair{display:flex;gap:8px;align-items:flex-start}",
  "svg{border-radius:5px;display:block}",
  ".note{color:#8b949e;font-size:12px;margin:4px 0 10px}",
  "</style>",
  "<h1>GaugeV2 &mdash; audit preview"
  .. " (LVGL angle normalisation + label clipping modelled)</h1>",
}

local function section(title, note)
  html[#html+1] = "<h2>" .. esc(title) .. "</h2>"
  if note then html[#html+1] = "<div class='note'>" .. note .. "</div>" end
  html[#html+1] = "<div class='grid'>"
end
local function endsection() html[#html+1] = "</div>" end

local function card(title, zone, overrides, value, history, frames, post, both)
  local z = { x = 0, y = 0, w = zone[1], h = zone[2] }
  local scale = (zone[1] < 110) and 2.2 or ((zone[1] < 210) and 1.5 or 1.15)
  build(z, overrides, value, history, frames, post)
  mock.setThemeColors(svgkit.themeColors("stock"))
  build(z, overrides, value, history, frames, post)
  local dark = renderSvg(z, "stock", scale, title)
  local light = ""
  if both ~= false then
    mock.setThemeColors(svgkit.themeColors("dark"))
    build(z, overrides, value, history, frames, post)
    light = renderSvg(z, "dark", scale, title)
  end
  html[#html+1] = string.format(
    "<div class='card'><h3>%s <span style='color:#6f7b87'>%dx%d</span>"
    .. "</h3><div class='pair'>%s%s</div></div>",
    esc(title), zone[1], zone[2], dark, light)
end

-- 1. value sweep --------------------------------------------------------
section("1 &middot; Value sweep, default dial (RSSI 0..100, crit 35, warn 55, Rail)",
  "Same widget, nine values. Watch the arc length, needle angle, colour"
  .. " band and state chip.")
for _, v in ipairs({ 0, 5, 20, 34, 36, 54, 56, 78, 100 }) do
  card("value = " .. v, { 200, 160 }, {}, v, nil, 40, nil, false)
end
endsection()

-- 2. sweeps ------------------------------------------------------------
section("2 &middot; Dial sweep option (LVGL-normalised)",
  "270&deg; / 180&deg; / 360&deg; at low, mid and high value.")
for _, s in ipairs({ "270 deg", "180 deg", "360 deg" }) do
  for _, v in ipairs({ 10, 55, 95 }) do
    card(s .. "  @" .. v, { 200, 200 }, { Sweep = s }, v, nil, 40, nil, false)
  end
end
endsection()

-- 3. colour modes -------------------------------------------------------
section("3 &middot; Colour modes, identical value and zone",
  "All five modes at value 78 (normal band) and value 22 (critical band).")
for _, m in ipairs({ "Static", "Threshold", "Rail", "Gradient", "Sections" }) do
  card(m .. " @78", { 200, 160 }, { ColorMode = m }, 78, nil, 40, nil, false)
end
for _, m in ipairs({ "Static", "Threshold", "Rail", "Gradient", "Sections" }) do
  card(m .. " @22", { 200, 160 }, { ColorMode = m }, 22, nil, 40, nil, false)
end
endsection()

-- 4. zone matrix --------------------------------------------------------
section("4 &middot; Zone matrix",
  "Widget zones seen in real EdgeTX layouts, plus awkward aspect ratios.")
local ZONES = {
  { 60, 60 }, { 80, 60 }, { 100, 100 }, { 128, 96 }, { 160, 160 },
  { 200, 160 }, { 200, 200 }, { 260, 220 }, { 300, 150 }, { 120, 220 },
  { 100, 260 }, { 300, 60 }, { 200, 50 }, { 480, 130 }, { 480, 272 },
}
for _, z in ipairs(ZONES) do
  card(z[1] .. "x" .. z[2], z, { ShowMinMax = "Markers + text" }, 78,
    { 31, 92 }, 40, nil, false)
end
endsection()

-- 5. availability -------------------------------------------------------
section("5 &middot; Availability states",
  "valid / stale / link down / no source, and the critical pulse trough.")
card("valid", { 220, 170 }, {}, 78, { 31, 92 })
card("stale", { 220, 170 }, {}, 78, { 31, 92 }, 30,
  function(w, mod, _opts, src)
  mock.sim.current[src] = false
  mock.advance(50); mod.refresh(w)
end)
card("link down", { 220, 170 }, {}, 78, { 31, 92 }, 30,
  function(w, mod, _opts, src)
  mock.setValue(src, nil); mock.sim.rssi = 0
  mock.advance(50); mod.refresh(w)
end)
card("critical -> link down (pulse bug)", { 220, 170 },
  { ColorMode = "Threshold" }, 5, nil, 40,
  function(w, mod, _opts, src)
    while not w.frame.pulse do mock.advance(50); mod.refresh(w) end
    mock.setValue(src, nil); mock.sim.rssi = 0
    mock.advance(50); mod.refresh(w)
  end)
card("no source", { 220, 170 }, { __src = 0 }, nil)
endsection()

-- 6. defect scenarios ---------------------------------------------------
section("6 &middot; Defect scenarios from the audit",
  "Each of these is a finding in AUDIT.md, rendered.")

card("P0-3 inverted scale (Min 100, Max 0)", { 200, 200 },
  { __src = ID_STICK, Scale = "Manual", Min = 100, Max = 0,
    ColorMode = "Sections" }, 25)
card("P0-3 reference: same, ascending", { 200, 200 },
  { __src = ID_STICK, Scale = "Manual", Min = 0, Max = 100,
    ColorMode = "Sections" }, 25)

card("P0-2 stale sections after 4S latch", { 200, 200 },
  { __src = ID_RXBT, ColorMode = "Sections", __hmin = ID_RXBT_MIN,
    __hmax = ID_RXBT_MAX }, 16.4)
card("P0-2 reference: same scale, fresh build", { 200, 200 },
  { __src = ID_STICK, Scale = "Manual", Min = 13, Max = 17, Warn = 15, Crit = 14,
    ColorMode = "Sections", Precision = "1" }, 16.4)

card("P0-4 360 deg track (LVGL-normalised)", { 200, 200 }, { Sweep = "360 deg" }, 78)

card("P0-7 battery %, history in volts", { 260, 220 },
  { __src = ID_RXBT, Battery = "Li-Po", ShowMinMax = "Markers + text",
    __hmin = ID_RXBT_MIN, __hmax = ID_RXBT_MAX }, 16.4, { 14.8, 16.8 })

card("P1-2 bar h=50, state text h=0", { 300, 50 }, { Style = "Bar" }, 22)
card("P1-2 reference: bar h=70", { 300, 70 }, { Style = "Bar" }, 22)

card("P1-3 elapsed timer overflows box", { 200, 160 }, { __src = ID_TIMER }, -3725)
card("P1-3 reference: positive timer", { 200, 160 }, { __src = ID_TIMER }, 3725)

card("P1-4 out-of-range value overflows", { 200, 160 },
  { __src = ID_STICK, Scale = "Manual", Min = 0, Max = 100 }, 1500)

card("P1-5 gradient with warn == crit", { 200, 160 },
  { __src = ID_STICK, ColorMode = "Gradient", Scale = "Manual",
    Min = 0, Max = 100, Warn = 50, Crit = 50 }, 90)

card("P1-6 Cels pack scale, Cells=Lowest", { 200, 200 },
  { __src = 3075, Cells = "Lowest", Precision = "2" },
  { 4.10, 4.05, 4.00, 3.95 }, nil, 30, nil)
card("P1-6 reference: Cells=Total", { 200, 200 },
  { __src = 3075, Cells = "Total", Precision = "2" },
  { 4.10, 4.05, 4.00, 3.95 }, nil, 30, nil)

card("P1-11 bar marks, low-is-good (T1)", { 300, 70 },
  { __src = ID_TEMP, Style = "Bar" }, 95)
card("P1-11 reference: dial rails, same sensor", { 200, 200 },
  { __src = ID_TEMP, ColorMode = "Rail" }, 95)
endsection()

-- 7. text-heavy scales --------------------------------------------------
section("7 &middot; Wide value strings",
  "How the auto-fit font copes as the widest sample grows.")
card("0..100", { 200, 160 },
  { __src = ID_STICK, Scale = "Manual", Min = 0, Max = 100 }, 78)
card("0..1024", { 200, 160 },
  { __src = ID_STICK, Scale = "Manual", Min = 0, Max = 1024 }, 780)
card("0..20000", { 200, 160 },
  { __src = ID_STICK, Scale = "Manual", Min = 0, Max = 20000 }, 15400)
card("-120..0 dBm", { 200, 160 },
  { __src = ID_STICK, Scale = "Manual", Min = -120, Max = 0 }, -76)
card("2 decimals 0..100", { 200, 160 },
  { __src = ID_STICK, Scale = "Manual", Min = 0, Max = 100, Precision = "2" }, 78)
card("2 decimals, micro", { 60, 60 },
  { __src = ID_STICK, Scale = "Manual", Min = 0, Max = 100, Precision = "2" }, 78)
card("scale labels: 0..20000, 2 decimals", { 220, 220 },
  { __src = ID_STICK, Scale = "Manual", Min = 0, Max = 20000, Precision = "2" }, 15400)
card("scale labels: -120..0", { 220, 220 },
  { __src = ID_STICK, Scale = "Manual", Min = -120, Max = 0 }, -76)
endsection()

html[#html+1] = "<h2>Emitter warnings</h2><pre style='color:#ffa198;font-size:12px'>"
local seen = {}
for _, w in ipairs(warnings) do
  if not seen[w] then seen[w] = true; html[#html+1] = esc(w) end
end
html[#html+1] = "</pre>"

local f = assert(io.open(outPath, "w"))
f:write(table.concat(html, "\n"))
f:close()
print("wrote " .. outPath)
print("-- distinct emitter warnings --")
local seen2 = {}
for _, w in ipairs(warnings) do
  if not seen2[w] then seen2[w] = true; print(w) end
end
