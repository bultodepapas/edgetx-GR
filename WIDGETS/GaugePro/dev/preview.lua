-- GaugePro design preview: renders the real widget code against the mock
-- environment and writes the resulting LVGL object tree out as SVG, so the
-- visual design can be reviewed in a browser without flashing a radio.
--
--   lua5.3 dev/preview.lua <widget-dir> [out.html]
--
-- What you see is exactly what the widget asked LVGL to draw: the same
-- objects, coordinates, angles, fonts and theme roles.

local widgetDir = arg[1] or "./"
local outPath = arg[2] or (widgetDir .. "dev/preview.html")

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

-- ---- theme palettes (the radio's COLOR_THEME_* roles, both themes) --------

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

local FONT_PX = {
  [0x000] = 16, [0x200] = 11, [0x300] = 13, [0x400] = 24,
  [0x500] = 32, [0x600] = 48, [0x700] = 40,
}

local function colorOf(palette, flags, fallback)
  if flags == nil then return fallback or "none" end
  local c = palette[flags]
  if c then return c end
  -- lcd.RGB() values from the gradient mode: 0x100000 + r<<16 + g<<8 + b
  if flags > 0x100000 then
    local v = flags - 0x100000
    return string.format("#%02x%02x%02x", (v >> 16) & 0xff, (v >> 8) & 0xff,
                         v & 0xff)
  end
  return fallback or "#ff00ff"
end

-- ---- SVG emitters --------------------------------------------------------

local function polar(cx, cy, r, deg)
  local a = deg * math.pi / 180
  return cx + r * math.cos(a), cy + r * math.sin(a)
end

local function arcPath(cx, cy, r, a1, a2)
  local sweep = a2 - a1
  if sweep <= 0 then return nil end
  if sweep >= 359.9 then
    -- a closed ring: two half arcs
    local x1, y1 = polar(cx, cy, r, a1)
    local x2, y2 = polar(cx, cy, r, a1 + 180)
    return string.format("M %.2f %.2f A %.2f %.2f 0 1 1 %.2f %.2f " ..
                         "A %.2f %.2f 0 1 1 %.2f %.2f",
                         x1, y1, r, r, x2, y2, r, r, x1, y1)
  end
  local x1, y1 = polar(cx, cy, r, a1)
  local x2, y2 = polar(cx, cy, r, a2)
  return string.format("M %.2f %.2f A %.2f %.2f 0 %d 1 %.2f %.2f",
                       x1, y1, r, r, (sweep > 180) and 1 or 0, x2, y2)
end

local function esc(s)
  s = tostring(s or "")
  s = string.gsub(s, "&", "&amp;")
  s = string.gsub(s, "<", "&lt;")
  s = string.gsub(s, ">", "&gt;")
  return s
end

local function emit(out, obj, pal)
  local p = obj.props
  local opa = (p.opacity or 255) / 255
  if obj.kind == "arc" then
    local bgOpa = (p.bgOpacity or 0) / 255
    if bgOpa > 0 and p.bgStartAngle then
      local d = arcPath(p.x, p.y, p.radius, p.bgStartAngle, p.bgEndAngle)
      if d then
        out[#out + 1] = string.format(
          '<path d="%s" fill="none" stroke="%s" stroke-width="%d" ' ..
          'stroke-opacity="%.2f" stroke-linecap="%s"/>',
          d, colorOf(pal, p.bgColor or p.color), p.thickness or 2, bgOpa,
          (p.rounded == 1) and "round" or "butt")
      end
    end
    if opa > 0 and p.startAngle then
      local d = arcPath(p.x, p.y, p.radius, p.startAngle, p.endAngle)
      if d then
        out[#out + 1] = string.format(
          '<path d="%s" fill="none" stroke="%s" stroke-width="%d" ' ..
          'stroke-opacity="%.2f" stroke-linecap="%s"/>',
          d, colorOf(pal, p.color), p.thickness or 2, opa,
          (p.rounded == 1) and "round" or "butt")
      end
    end
  elseif obj.kind == "line" then
    local pts = {}
    for _, pt in ipairs(p.pts or {}) do
      pts[#pts + 1] = string.format("%.1f,%.1f", pt[1], pt[2])
    end
    out[#out + 1] = string.format(
      '<polyline points="%s" fill="none" stroke="%s" stroke-width="%d" ' ..
      'stroke-opacity="%.2f" stroke-linecap="%s"/>',
      table.concat(pts, " "), colorOf(pal, p.color), p.thickness or 1, opa,
      (p.rounded == 1) and "round" or "butt")
  elseif obj.kind == "triangle" then
    local pts = {}
    for _, pt in ipairs(p.pts or {}) do
      pts[#pts + 1] = string.format("%.1f,%.1f", pt[1], pt[2])
    end
    out[#out + 1] = string.format(
      '<polygon points="%s" fill="%s" fill-opacity="%.2f"/>',
      table.concat(pts, " "), colorOf(pal, p.color), opa)
  elseif obj.kind == "circle" then
    out[#out + 1] = string.format(
      '<circle cx="%d" cy="%d" r="%d" fill="%s" fill-opacity="%.2f"/>',
      p.x, p.y, p.radius, colorOf(pal, p.color), opa)
  elseif obj.kind == "rectangle" then
    out[#out + 1] = string.format(
      '<rect x="%d" y="%d" width="%d" height="%d" rx="%d" fill="%s" ' ..
      'fill-opacity="%.2f"/>',
      p.x, p.y, p.w or 0, p.h or 0, p.rounded or 0, colorOf(pal, p.color), opa)
  elseif obj.kind == "label" then
    local size = FONT_PX[p.font or 0] or 16
    local anchor, x = "start", p.x
    if p.align == CENTER then
      anchor, x = "middle", p.x + (p.w or 0) / 2
    elseif p.align == RIGHT then
      anchor, x = "end", p.x + (p.w or 0)
    end
    out[#out + 1] = string.format(
      '<text x="%.1f" y="%.1f" font-size="%d" fill="%s" text-anchor="%s" ' ..
      'font-family="DejaVu Sans, Verdana, sans-serif" fill-opacity="%.2f">' ..
      '%s</text>',
      x, p.y + size * 0.78, size, colorOf(pal, p.color), anchor, opa,
      esc(p.text))
  end
end

local function renderSvg(zone, theme, scale)
  local pal = PALETTES[theme]
  local out = {}
  out[#out + 1] = string.format(
    '<svg viewBox="0 0 %d %d" width="%d" height="%d" ' ..
    'xmlns="http://www.w3.org/2000/svg">', zone.w, zone.h,
    math.floor(zone.w * scale), math.floor(zone.h * scale))
  out[#out + 1] = string.format(
    '<rect width="%d" height="%d" fill="%s"/>', zone.w, zone.h, pal.bg)
  for _, obj in ipairs(mock.objects()) do
    if obj.visible then emit(out, obj, pal) end
  end
  out[#out + 1] = "</svg>"
  return table.concat(out, "\n")
end

-- ---- scenarios -----------------------------------------------------------

local ID_RSSI, ID_MIN, ID_MAX = 3072, 3073, 3074

local function build(zone, overrides, value, history)
  mock.reset()
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0 }
  mock.addField(ID_RSSI, "RSSI", 17)
  mock.addField(ID_MIN, "RSSI-", 17)
  mock.addField(ID_MAX, "RSSI+", 17)
  mock.sim.sensors[0] = { name = "RSSI", prec = 0, unit = 17 }
  mock.setValue(ID_RSSI, value)
  if history then
    mock.setValue(ID_MIN, history[1])
    mock.setValue(ID_MAX, history[2])
  end
  local mod = dofile(widgetDir .. "main.lua")
  local o = { Source = ID_RSSI }
  for k, v in pairs(overrides) do o[k] = v end
  local opts = mock.makeOptions(mod.defs, o)
  local w = mod.create(zone, opts, widgetDir)
  mod.update(w, opts)
  for _ = 1, 30 do            -- let the needle settle
    mock.advance(50)
    mod.refresh(w)
  end
  return w
end

local CASES = {
  { "Normal, rail mode", { w = 200, h = 160 }, {}, 78, { 31, 92 } },
  { "Warning", { w = 200, h = 160 }, {}, 47, { 31, 92 } },
  { "Critical", { w = 200, h = 160 }, {}, 22, { 18, 92 } },
  { "Threshold mode", { w = 200, h = 160 }, { ColorMode = "Threshold" }, 78 },
  { "Sections mode", { w = 200, h = 160 }, { ColorMode = "Sections" }, 78 },
  { "Gradient mode", { w = 200, h = 160 }, { ColorMode = "Gradient" }, 62 },
  { "Static mode", { w = 200, h = 160 }, { ColorMode = "Static" }, 78 },
  { "Large, min/max text", { w = 260, h = 220 },
    { ShowMinMax = "Markers + text" }, 78, { 31, 92 } },
  { "Horizontal", { w = 300, h = 150 }, {}, 78, { 31, 92 } },
  { "Vertical", { w = 120, h = 220 }, {}, 78, { 31, 92 } },
  { "Compact", { w = 100, h = 100 }, {}, 78 },
  { "Micro", { w = 60, h = 60 }, {}, 78 },
  { "Bar (auto, wide strip)", { w = 300, h = 60 }, {}, 78, { 31, 92 } },
  { "Bar, critical", { w = 300, h = 60 }, {}, 18, { 18, 92 } },
  { "Arc only", { w = 200, h = 160 }, { Style = "Arc" }, 78 },
  { "180 degree sweep", { w = 220, h = 140 }, { Sweep = "180 deg" }, 78 },
  { "360 degree sweep", { w = 200, h = 200 }, { Sweep = "360 deg" }, 78 },
  { "Custom label and unit", { w = 200, h = 160 },
    { Label = "PACK", Suffix = "V" }, 78 },
  { "Fullscreen", { w = 480, h = 272 }, { ShowMinMax = "Markers + text" },
    78, { 31, 92 } },
}

local html = {
  "<!doctype html><meta charset='utf-8'><title>GaugePro preview</title>",
  "<style>",
  "body{font:14px system-ui,sans-serif;background:#22262b;color:#e6e6e6;",
  "margin:24px}",
  "h1{font-size:18px;font-weight:600}",
  ".grid{display:flex;flex-wrap:wrap;gap:18px}",
  ".card{background:#2c3138;border-radius:10px;padding:12px}",
  ".card h2{font-size:12px;font-weight:600;margin:0 0 8px;color:#a8b2bd}",
  ".pair{display:flex;gap:10px;align-items:flex-start}",
  "svg{border-radius:6px;display:block}",
  "</style>",
  "<h1>GaugePro &mdash; rendered from the real object tree (dark / light)</h1>",
  "<div class='grid'>",
}

for _, case in ipairs(CASES) do
  local title, zone, overrides, value, history = case[1], case[2], case[3],
                                                 case[4], case[5]
  local z = { x = 0, y = 0, w = zone.w, h = zone.h }
  local scale = (zone.w < 130) and 2 or 1.4
  build(z, overrides, value, history)
  mock.setThemeColors(svgkit.themeColors("stock"))
  build(z, overrides, value, history)
  local dark = renderSvg(z, "stock", scale)
  mock.setThemeColors(svgkit.themeColors("dark"))
  build(z, overrides, value, history)
  local light = renderSvg(z, "dark", scale)
  html[#html + 1] = string.format(
    "<div class='card'><h2>%s &nbsp;<span style='color:#6f7b87'>%dx%d</span>" ..
    "</h2><div class='pair'>%s%s</div></div>", esc(title), zone.w, zone.h,
    dark, light)
end

html[#html + 1] = "</div>"

local f = assert(io.open(outPath, "w"))
f:write(table.concat(html, "\n"))
f:close()
print("wrote " .. outPath .. " (" .. #CASES .. " cases)")
