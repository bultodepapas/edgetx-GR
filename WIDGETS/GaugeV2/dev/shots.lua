-- GaugeV2 render shots: one standalone SVG per scenario, for visual review.
-- Complements dev/audit-preview.lua (which renders the full gallery); use
-- this when you want individual images (open an SVG, or rasterise with a
-- headless browser / rsvg-convert).
--
--   lua5.3 dev/shots.lua <widget-dir> [out-dir]
--
-- The SVG emitter models the same LVGL semantics as audit-preview.lua:
-- arc angles normalised like lv_arc_set_*_angle (subtract 360 once, skip a
-- zero-length arc) and labels wrapped/clipped like LV_LABEL_LONG_WRAP, with
-- overflowing labels outlined in red.

local widgetDir = arg[1] or "./"
local outDir = arg[2] or (widgetDir .. "dev/shots/")

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local PALETTE = {
  bg = "#12161c",
  [COLOR_THEME_PRIMARY1] = "#e8ecf1", [COLOR_THEME_PRIMARY2] = "#9fb2c6",
  [COLOR_THEME_PRIMARY3] = "#5b6b7c", [COLOR_THEME_SECONDARY1] = "#8fa0b3",
  [COLOR_THEME_SECONDARY2] = "#48586a", [COLOR_THEME_SECONDARY3] = "#1c2430",
  [COLOR_THEME_FOCUS] = "#2f81f7", [COLOR_THEME_EDIT] = "#f0883e",
  [COLOR_THEME_ACTIVE] = "#3fb950", [COLOR_THEME_WARNING] = "#e3b341",
  [COLOR_THEME_DISABLED] = "#6b7684",
  [RED] = "#f85149", [WHITE] = "#ffffff", [BLACK] = "#000000",
}

-- mock lcd.sizeText heights, so the emitter measures exactly what layout did
local FONT_PX = { [0x000]=16, [0x200]=11, [0x300]=13, [0x400]=24,
                  [0x500]=32, [0x600]=48, [0x700]=48 }

local warnings = {}
local function warn(fmt, ...) warnings[#warnings+1] = string.format(fmt, ...) end

local function colorOf(flags, fallback)
  if flags == nil then return fallback or "none" end
  local c = PALETTE[flags]
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

local function lvNorm(a)
  a = math.floor(a + 0.5)
  if a > 360 then a = a - 360 end
  return a
end

local function lvArcSpan(a1, a2)
  local s, e = lvNorm(a1), lvNorm(a2)
  if s == e then return nil end
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
    return string.format("M %.2f %.2f A %.2f %.2f 0 1 1 %.2f %.2f A %.2f %.2f 0 1 1 %.2f %.2f",
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

local function textW(text, size) return math.floor(#text * (size * 0.55)) end

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

local function emit(out, obj, label)
  local p = obj.props
  local opa = (p.opacity or 255) / 255
  if obj.kind == "arc" then
    local bgOpa = (p.bgOpacity or 0) / 255
    if bgOpa > 0 and p.bgStartAngle then
      local d = arcPath(p.x, p.y, p.radius, p.bgStartAngle, p.bgEndAngle)
      if d then
        out[#out+1] = string.format(
          '<path d="%s" fill="none" stroke="%s" stroke-width="%d" stroke-opacity="%.2f" stroke-linecap="%s"/>',
          d, colorOf(p.bgColor or p.color), p.thickness or 2, bgOpa,
          (p.rounded == 1) and "round" or "butt")
      else
        warn("%s: arc background start==end after LVGL normalisation (%d..%d) -> NOT DRAWN",
             label, p.bgStartAngle, p.bgEndAngle)
      end
    end
    if opa > 0 and p.startAngle then
      local d = arcPath(p.x, p.y, p.radius, p.startAngle, p.endAngle)
      if d then
        out[#out+1] = string.format(
          '<path d="%s" fill="none" stroke="%s" stroke-width="%d" stroke-opacity="%.2f" stroke-linecap="%s"/>',
          d, colorOf(p.color), p.thickness or 2, opa,
          (p.rounded == 1) and "round" or "butt")
      end
    end
  elseif obj.kind == "line" then
    local pts = {}
    for _, pt in ipairs(p.pts or {}) do pts[#pts+1] = string.format("%.1f,%.1f", pt[1], pt[2]) end
    out[#out+1] = string.format(
      '<polyline points="%s" fill="none" stroke="%s" stroke-width="%d" stroke-opacity="%.2f" stroke-linecap="%s"/>',
      table.concat(pts, " "), colorOf(p.color), p.thickness or 1, opa,
      (p.rounded == 1) and "round" or "butt")
  elseif obj.kind == "triangle" then
    local pts = {}
    for _, pt in ipairs(p.pts or {}) do pts[#pts+1] = string.format("%.1f,%.1f", pt[1], pt[2]) end
    out[#out+1] = string.format('<polygon points="%s" fill="%s" fill-opacity="%.2f"/>',
      table.concat(pts, " "), colorOf(p.color), opa)
  elseif obj.kind == "circle" then
    out[#out+1] = string.format('<circle cx="%d" cy="%d" r="%d" fill="%s" fill-opacity="%.2f"/>',
      p.x, p.y, p.radius, colorOf(p.color), opa)
  elseif obj.kind == "rectangle" then
    out[#out+1] = string.format(
      '<rect x="%d" y="%d" width="%d" height="%d" rx="%d" fill="%s" fill-opacity="%.2f"/>',
      p.x, p.y, p.w or 0, p.h or 0, p.rounded or 0, colorOf(p.color), opa)
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
    out[#out+1] = string.format('<clipPath id="%s"><rect x="%d" y="%d" width="%d" height="%d"/></clipPath>',
      cid, p.x, p.y, bw, bh)
    out[#out+1] = string.format('<g clip-path="url(#%s)">', cid)
    local anchor, x = "start", p.x
    if p.align == CENTER then anchor, x = "middle", p.x + bw/2
    elseif p.align == RIGHT then anchor, x = "end", p.x + bw end
    for i = 1, #lines do
      out[#out+1] = string.format(
        '<text x="%.1f" y="%.1f" font-size="%d" fill="%s" text-anchor="%s" font-family="DejaVu Sans, Verdana, sans-serif" fill-opacity="%.2f">%s</text>',
        x, p.y + (i-1)*lineH + size*0.78, size, colorOf(p.color), anchor, opa, esc(lines[i]))
    end
    out[#out+1] = "</g>"
    if wrapped then
      out[#out+1] = string.format(
        '<rect x="%d" y="%d" width="%d" height="%d" fill="none" stroke="#ff3b30" stroke-width="1" stroke-dasharray="3 2"/>',
        p.x, p.y, bw, bh)
    end
  end
end

local function renderSvg(zone, scale, label)
  local out = {}
  out[#out+1] = string.format('<svg viewBox="0 0 %d %d" width="%d" height="%d" xmlns="http://www.w3.org/2000/svg">',
    zone.w, zone.h, math.floor(zone.w*scale), math.floor(zone.h*scale))
  out[#out+1] = string.format('<rect width="%d" height="%d" fill="%s"/>', zone.w, zone.h, PALETTE.bg)
  for _, obj in ipairs(mock.objects()) do
    if obj.visible then emit(out, obj, label) end
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

-- ---- shots ---------------------------------------------------------------

local shots = {}
local function shot(name, zone, overrides, value, history, frames, post)
  shots[#shots+1] = name
  local z = { x = 0, y = 0, w = zone[1], h = zone[2] }
  local scale = (zone[1] < 110) and 2.2 or ((zone[1] < 210) and 1.5 or 1.15)
  build(z, overrides, value, history, frames, post)
  local svg = renderSvg(z, scale, name)
  local f = assert(io.open(outDir .. name .. ".svg", "w"))
  f:write(svg)
  f:close()
end

-- zone matrix (value 78, history markers + text)
local ZONES = {
  { 60, 60 }, { 80, 60 }, { 100, 100 }, { 128, 96 }, { 160, 160 },
  { 200, 160 }, { 200, 200 }, { 260, 220 }, { 300, 150 }, { 120, 220 },
  { 100, 260 }, { 480, 272 },
}
for _, z in ipairs(ZONES) do
  shot(string.format("zone-%dx%d", z[1], z[2]), z, { ShowMinMax = "Markers + text" }, 78, { 31, 92 })
end

-- value sweep on the default dial
for _, v in ipairs({ 0, 34, 36, 56, 78, 100 }) do
  shot("value-" .. v, { 200, 160 }, {}, v)
end

-- dial sweeps at mid value
for _, s in ipairs({ "270 deg", "180 deg", "360 deg" }) do
  shot("sweep-" .. string.gsub(s, " ", ""), { 200, 200 }, { Sweep = s }, 55)
end

-- colour modes, normal and critical
for _, m in ipairs({ "Static", "Threshold", "Rail", "Gradient", "Sections" }) do
  shot("mode-" .. m .. "-normal", { 200, 160 }, { ColorMode = m }, 78)
  shot("mode-" .. m .. "-crit", { 200, 160 }, { ColorMode = m }, 22)
end

-- Rail mode needle positions (P0-2 review): the same dial with the needle at
-- the start cap, the top and the end cap, to check the blade at three angles.
shot("mode-Rail-pos1", { 200, 160 }, { ColorMode = "Rail" }, 0)
shot("mode-Rail-pos2", { 200, 160 }, { ColorMode = "Rail" }, 50)
shot("mode-Rail-pos3", { 200, 160 }, { ColorMode = "Rail" }, 100)

-- ShowChip off (owner request): same critical frame as mode-Rail-crit, pill
-- hidden - confirms the option actually removes the chip, not just its text.
shot("mode-Rail-nochip", { 200, 160 }, { ColorMode = "Rail", ShowChip = false }, 22)

-- bar
shot("bar-300x70-crit", { 300, 70 }, { Style = "Bar" }, 95)
shot("bar-300x44", { 300, 44 }, { Style = "Bar" }, 95)
shot("bar-300x70-lowgood", { 300, 70 }, { __src = ID_TEMP, Style = "Bar" }, 95)

-- specials
shot("timer-elapsed", { 200, 160 }, { __src = ID_TIMER }, -3725)
shot("out-of-range-1500", { 200, 160 },
  { __src = ID_STICK, Scale = "Manual", Min = 0, Max = 100 }, 1500)
shot("rxbt-16.4-latched", { 200, 200 },
  { __src = ID_RXBT, ColorMode = "Sections", __hmin = ID_RXBT_MIN,
    __hmax = ID_RXBT_MAX }, 16.4, { 14.8, 16.8 })
shot("scale-labels-20000", { 220, 220 },
  { __src = ID_STICK, Scale = "Manual", Min = 0, Max = 20000, Precision = "2" }, 15400)
shot("scale-labels-dbm", { 220, 220 },
  { __src = ID_STICK, Scale = "Manual", Min = -120, Max = 0 }, -76)
shot("gradient-warn-crit", { 200, 160 },
  { __src = ID_STICK, ColorMode = "Gradient", Scale = "Manual",
    Min = 0, Max = 100, Warn = 50, Crit = 50 }, 90)
shot("stale", { 220, 170 }, {}, 78, { 31, 92 }, 30, function(w, mod, opts, src)
  mock.sim.current[src] = false
  mock.advance(50); mod.refresh(w)
end)
shot("link-down", { 220, 170 }, {}, 78, { 31, 92 }, 30, function(w, mod, opts, src)
  mock.setValue(src, nil); mock.sim.rssi = 0
  mock.advance(50); mod.refresh(w)
end)

print("wrote " .. #shots .. " SVG shots to " .. outDir)
local seen = {}
for _, w in ipairs(warnings) do
  if not seen[w] then seen[w] = true; print("WARN: " .. w) end
end
