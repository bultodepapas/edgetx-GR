-- GaugeV2 dev tooling: the LVGL -> SVG emitter, as a reusable module.
--
-- Extracted from dev/shots.lua so the single-shot tool and the gallery share
-- ONE emitter. Two emitters drifting apart is exactly the class of defect the
-- Tanda 6 review flagged in the widget itself (F-15); the dev tools do not get
-- an exemption.
--
-- What it models, and why it is not just "draw the objects":
--   * arc angles are normalised the way lv_arc_set_*_angle does (subtract 360
--     once), and a span that collapses to zero length is NOT drawn - that is
--     the exact failure mode of AUDIT.md P0-4, so the preview has to reproduce
--     it rather than paper over it.
--   * labels wrap and clip like LV_LABEL_LONG_WRAP inside their box; text that
--     does not fit is reported AND outlined, because a preview that silently
--     shrinks text to fit would hide the bug it exists to catch.
--   * font metrics come from the same table tests/mock_env.lua uses, so the
--     picture measures what layout.lua actually measured.
--
-- Palettes are per THEME: every colour the widget uses is a theme role, so a
-- second palette is a real test of that contract (and the only way to check
-- that the fixed needle colour contrasts in light mode too).

local M = {}

local floor = math.floor
local fmt = string.format

-- Font flag -> pixel height. Mirrors tests/mock_env.lua's lcd.sizeText.
M.FONT_PX = { [0x000] = 16, [0x200] = 11, [0x300] = 13, [0x400] = 24,
              [0x500] = 32, [0x600] = 48, [0x700] = 48 }

-- Same 0.55 advance ratio the mock uses, so measurement here and measurement
-- inside the widget agree.
function M.textWidth(text, size)
  return floor(#tostring(text) * (size * 0.55))
end

-- --------------------------------------------------------------- palettes --

-- Built lazily: the COLOR_THEME_* globals only exist once mock.install() has
-- run, so a palette captured at require time would key everything on nil.
local palettes = nil

local function buildPalettes()
  return {
    dark = {
      name = "dark",
      bg = "#12161c", panel = "#171c24", ink = "#e8ecf1", dim = "#8fa0b3",
      rule = "#273140", accent = "#2f81f7",
      [COLOR_THEME_PRIMARY1] = "#e8ecf1", [COLOR_THEME_PRIMARY2] = "#9fb2c6",
      [COLOR_THEME_PRIMARY3] = "#5b6b7c", [COLOR_THEME_SECONDARY1] = "#8fa0b3",
      [COLOR_THEME_SECONDARY2] = "#48586a", [COLOR_THEME_SECONDARY3] = "#1c2430",
      [COLOR_THEME_FOCUS] = "#2f81f7", [COLOR_THEME_EDIT] = "#f0883e",
      [COLOR_THEME_ACTIVE] = "#3fb950", [COLOR_THEME_WARNING] = "#e3b341",
      [COLOR_THEME_DISABLED] = "#6b7684",
      [RED] = "#f85149", [WHITE] = "#ffffff", [BLACK] = "#000000",
    },
    -- EdgeTX's light theme inverts the PRIMARY ramp: PRIMARY1 becomes the dark
    -- ink colour. The needle is PRIMARY1 (theme.lua), so this palette is what
    -- proves the "needle always contrasts" rule holds in BOTH themes and not
    -- just against the dark background it was designed on.
    light = {
      name = "light",
      bg = "#eef1f5", panel = "#f7f9fb", ink = "#12161c", dim = "#5b6b7c",
      rule = "#c9d1da", accent = "#0969da",
      [COLOR_THEME_PRIMARY1] = "#12161c", [COLOR_THEME_PRIMARY2] = "#3d4b5c",
      [COLOR_THEME_PRIMARY3] = "#8fa0b3", [COLOR_THEME_SECONDARY1] = "#5b6b7c",
      [COLOR_THEME_SECONDARY2] = "#c3ccd6", [COLOR_THEME_SECONDARY3] = "#ffffff",
      [COLOR_THEME_FOCUS] = "#0969da", [COLOR_THEME_EDIT] = "#bc4c00",
      [COLOR_THEME_ACTIVE] = "#1a7f37", [COLOR_THEME_WARNING] = "#9a6700",
      [COLOR_THEME_DISABLED] = "#9aa4b0",
      [RED] = "#cf222e", [WHITE] = "#ffffff", [BLACK] = "#000000",
    },
  }
end

function M.palette(name)
  if not palettes then palettes = buildPalettes() end
  return palettes[name or "dark"] or palettes.dark
end

function M.paletteNames() return { "dark", "light" } end

-- ------------------------------------------------------------------ escape --

function M.esc(s)
  s = tostring(s == nil and "" or s)
  s = string.gsub(s, "&", "&amp;")
  s = string.gsub(s, "<", "&lt;")
  s = string.gsub(s, ">", "&gt;")
  s = string.gsub(s, '"', "&quot;")
  return s
end
local esc = M.esc

-- ---------------------------------------------------------------- geometry --

local function polar(cx, cy, r, deg)
  local a = deg * math.pi / 180
  return cx + r * math.cos(a), cy + r * math.sin(a)
end

local function lvNorm(a)
  a = floor(a + 0.5)
  if a > 360 then a = a - 360 end
  return a
end

-- Returns nil when LVGL would draw nothing (start == end after normalisation).
local function lvArcSpan(a1, a2)
  local s, e = lvNorm(a1), lvNorm(a2)
  if s == e then return nil end
  local sweep = e - s
  if sweep < 0 then sweep = sweep + 360 end
  return s, sweep
end
M.lvArcSpan = lvArcSpan

local function arcPath(cx, cy, r, a1, a2)
  local s, sweep = lvArcSpan(a1, a2)
  if not s then return nil end
  if sweep >= 359.5 then
    local x1, y1 = polar(cx, cy, r, s)
    local x2, y2 = polar(cx, cy, r, s + 180)
    return fmt("M %.2f %.2f A %.2f %.2f 0 1 1 %.2f %.2f A %.2f %.2f 0 1 1 %.2f %.2f",
      x1, y1, r, r, x2, y2, r, r, x1, y1)
  end
  local x1, y1 = polar(cx, cy, r, s)
  local x2, y2 = polar(cx, cy, r, s + sweep)
  return fmt("M %.2f %.2f A %.2f %.2f 0 %d 1 %.2f %.2f",
    x1, y1, r, r, (sweep > 180) and 1 or 0, x2, y2)
end

local function wrapLines(text, w, size)
  if M.textWidth(text, size) <= w then return { text }, false end
  local maxChars = math.max(1, floor(w / (size * 0.55)))
  local lines, i = {}, 1
  while i <= #text do
    lines[#lines + 1] = string.sub(text, i, i + maxChars - 1)
    i = i + maxChars
  end
  return lines, true
end

-- ------------------------------------------------------------------ canvas --

local Canvas = {}
Canvas.__index = Canvas

-- A canvas owns the output buffer, the palette and a document-unique clip-id
-- counter. One canvas per OUTPUT FILE, not per scene: ids must not collide
-- when many scenes are composed into one sheet.
function M.newCanvas(theme)
  return setmetatable({
    out = {}, pal = M.palette(theme), clipSeq = 0, warnings = {},
  }, Canvas)
end

function Canvas:emit(s) self.out[#self.out + 1] = s end

function Canvas:warn(f, ...)
  self.warnings[#self.warnings + 1] = fmt(f, ...)
end

function Canvas:color(flags, fallback)
  if flags == nil then return fallback or "none" end
  local c = self.pal[flags]
  if c then return c end
  -- lcd.RGB() results (Gradient mode) are packed literals, not theme roles.
  if flags > 0x100000 then
    local v = flags - 0x100000
    return fmt("#%02x%02x%02x", (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff)
  end
  return fallback or "#ff00ff"   -- magenta: an unmapped colour must be loud
end

-- Painted extent of an object, in zone coordinates. Line thickness counts on
-- both axes: that over-states the ends of an axis-aligned line (butt caps do
-- not extend along the path), which is the safe direction for a containment
-- check.
local function paintedBox(obj)
  local p = obj.props
  if p.pts then
    local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
    for _, pt in ipairs(p.pts) do
      if pt[1] < x1 then x1 = pt[1] end
      if pt[1] > x2 then x2 = pt[1] end
      if pt[2] < y1 then y1 = pt[2] end
      if pt[2] > y2 then y2 = pt[2] end
    end
    local t = (p.thickness or 1) / 2
    return x1 - t, y1 - t, x2 + t, y2 + t
  end
  if p.radius then
    local r = p.radius + ((obj.kind == "arc") and (p.thickness or 0) / 2 or 0)
    return p.x - r, p.y - r, p.x + r, p.y + r
  end
  if not p.x then return nil end
  return p.x, p.y, p.x + (p.w or 0), p.y + (p.h or 0)
end

-- Draw one mock object. `label` only names the scene in warnings.
function Canvas:object(obj, label)
  local p = obj.props
  local opa = (p.opacity or 255) / 255
  local kind = obj.kind

  if kind == "arc" then
    local bgOpa = (p.bgOpacity or 0) / 255
    if bgOpa > 0 and p.bgStartAngle then
      local d = arcPath(p.x, p.y, p.radius, p.bgStartAngle, p.bgEndAngle)
      if d then
        self:emit(fmt('<path d="%s" fill="none" stroke="%s" stroke-width="%d"'
          .. ' stroke-opacity="%.2f" stroke-linecap="%s"/>',
          d, self:color(p.bgColor or p.color), p.thickness or 2, bgOpa,
          (p.rounded == 1) and "round" or "butt"))
      else
        self:warn("%s: arc background start==end after LVGL normalisation"
          .. " (%d..%d) -> NOT DRAWN", label, p.bgStartAngle, p.bgEndAngle)
      end
    end
    if opa > 0 and p.startAngle then
      local d = arcPath(p.x, p.y, p.radius, p.startAngle, p.endAngle)
      if d then
        self:emit(fmt('<path d="%s" fill="none" stroke="%s" stroke-width="%d"'
          .. ' stroke-opacity="%.2f" stroke-linecap="%s"/>',
          d, self:color(p.color), p.thickness or 2, opa,
          (p.rounded == 1) and "round" or "butt"))
      end
    end

  elseif kind == "line" then
    local pts = {}
    for _, pt in ipairs(p.pts or {}) do
      pts[#pts + 1] = fmt("%.1f,%.1f", pt[1], pt[2])
    end
    self:emit(fmt('<polyline points="%s" fill="none" stroke="%s"'
      .. ' stroke-width="%d" stroke-opacity="%.2f" stroke-linecap="%s"/>',
      table.concat(pts, " "), self:color(p.color), p.thickness or 1, opa,
      (p.rounded == 1) and "round" or "butt"))

  elseif kind == "triangle" then
    -- P2-1 forbids triangles in the needle; if one ever reappears the preview
    -- should still draw it, and the caller's object census will show it.
    local pts = {}
    for _, pt in ipairs(p.pts or {}) do
      pts[#pts + 1] = fmt("%.1f,%.1f", pt[1], pt[2])
    end
    self:emit(fmt('<polygon points="%s" fill="%s" fill-opacity="%.2f"/>',
      table.concat(pts, " "), self:color(p.color), opa))

  elseif kind == "circle" then
    self:emit(fmt('<circle cx="%d" cy="%d" r="%d" fill="%s"'
      .. ' fill-opacity="%.2f"/>',
      p.x, p.y, p.radius, self:color(p.color), opa))

  elseif kind == "rectangle" then
    self:emit(fmt('<rect x="%d" y="%d" width="%d" height="%d" rx="%d"'
      .. ' fill="%s" fill-opacity="%.2f"/>',
      p.x, p.y, p.w or 0, p.h or 0, p.rounded or 0, self:color(p.color), opa))

  elseif kind == "label" then
    local text = tostring(p.text or "")
    if text == "" then return end
    local size = M.FONT_PX[p.font or 0] or 16
    local bw, bh = p.w or 0, p.h or 0
    local lines, wrapped = wrapLines(text, bw, size)
    local fits = math.max(1, floor(bh / size))
    if wrapped then
      self:warn("%s: label %q needs %d px in a %d px box -> wraps to %d lines,"
        .. " %d visible", label, text, M.textWidth(text, size), bw, #lines,
        math.min(fits, #lines))
    end
    self.clipSeq = self.clipSeq + 1
    local cid = "clip" .. self.clipSeq
    self:emit(fmt('<clipPath id="%s"><rect x="%d" y="%d" width="%d"'
      .. ' height="%d"/></clipPath>', cid, p.x, p.y, bw, bh))
    self:emit(fmt('<g clip-path="url(#%s)">', cid))
    local anchor, x = "start", p.x
    if p.align == CENTER then anchor, x = "middle", p.x + bw / 2
    elseif p.align == RIGHT then anchor, x = "end", p.x + bw end
    for i = 1, #lines do
      -- textLength pins the glyph run to the width the LAYOUT believed the
      -- string was (M.textWidth, the same metric lcd.sizeText feeds the
      -- widget). Without it the browser laid the text out in DejaVu Sans at
      -- its own advances - about 10% wider than the metric - so every render
      -- showed text spilling out of boxes that fit perfectly well on the
      -- radio: "dB" came out clipped to "dE", and the gap between a value
      -- and its unit vanished. Renders were inventing clipping bugs, which
      -- is worse than missing them, because it teaches reviewers to ignore
      -- the clip. Now a clip in the picture means a clip on the radio.
      self:emit(fmt('<text x="%.1f" y="%.1f" font-size="%d" fill="%s"'
        .. ' text-anchor="%s" font-family="DejaVu Sans, Verdana, sans-serif"'
        .. ' textLength="%.1f" lengthAdjust="spacingAndGlyphs"'
        .. ' fill-opacity="%.2f">%s</text>',
        x, p.y + (i - 1) * size + size * 0.78, size, self:color(p.color),
        anchor, M.textWidth(lines[i], size), opa, esc(lines[i])))
    end
    self:emit("</g>")
    if wrapped then
      self:emit(fmt('<rect x="%d" y="%d" width="%d" height="%d" fill="none"'
        .. ' stroke="#ff3b30" stroke-width="1" stroke-dasharray="3 2"/>',
        p.x, p.y, bw, bh))
    end
  end
end

-- Draw a whole scene (every visible object in the mock) into a rect at
-- (x, y), scaled. Returns the number of objects drawn and any warnings the
-- scene produced, so the caller can badge the tile.
function Canvas:scene(objects, zone, x, y, scale, label)
  local before = #self.warnings
  self:emit(fmt('<g transform="translate(%.2f,%.2f) scale(%.4f)">',
    x, y, scale))
  self:emit(fmt('<rect width="%d" height="%d" fill="%s"/>',
    zone.w, zone.h, self.pal.bg))
  local n = 0
  for _, obj in ipairs(objects) do
    if obj.visible then
      self:object(obj, label)
      -- Containment. The SVG viewBox IS the zone, so anything drawn outside
      -- is simply clipped away here - exactly as LVGL clips children to the
      -- widget zone on the radio. That is why a 1-2 px overflow could live
      -- in the bar's state pill through every visual review: the picture
      -- never showed it. Say it in words instead.
      local x1, y1, x2, y2 = paintedBox(obj)
      if x1 and (x1 < 0 or y1 < 0 or x2 > zone.w or y2 > zone.h) then
        self:warn("%s: %s painted outside the %dx%d zone"
          .. " (%.0f,%.0f..%.0f,%.0f) -> clipped by LVGL on the radio",
          label, obj.kind, zone.w, zone.h, x1, y1, x2, y2)
      end
      n = n + 1
    end
  end
  self:emit("</g>")
  local mine = {}
  for i = before + 1, #self.warnings do mine[#mine + 1] = self.warnings[i] end
  return n, mine
end

-- Standalone single-scene document (what dev/shots.lua writes).
function Canvas:document(zone, scale)
  local head = fmt('<svg viewBox="0 0 %d %d" width="%d" height="%d"'
    .. ' xmlns="http://www.w3.org/2000/svg">', zone.w, zone.h,
    floor(zone.w * scale), floor(zone.h * scale))
  return head .. "\n" .. table.concat(self.out, "\n") .. "\n</svg>"
end

function Canvas:uniqueWarnings()
  local seen, out = {}, {}
  for _, w in ipairs(self.warnings) do
    if not seen[w] then seen[w] = true; out[#out + 1] = w end
  end
  return out
end

return M
