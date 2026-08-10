-- Geometric collision audit: for every zone/config, test the real object tree
-- for label/label, label/ring, label/tick overlaps and degenerate boxes.
--
-- The layout tests only assert that objects stay inside the zone; nothing
-- asserts that they stay off each other. This is that missing check, run as a
-- report rather than as assertions.
--
--   lua5.3 dev/collide.lua <widget-dir>
local widgetDir = arg[1] or "./"
local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)
local svgkit = dofile(widgetDir .. "dev/svgkit.lua")
local FONT_PX = svgkit.FONT_PX

local ID_RSSI, ID_MIN, ID_MAX, ID_STICK = 3072, 3073, 3074, 100

local function build(zone, ov, value, history)
  mock.reset()
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0 }
  mock.addField(ID_RSSI, "RSSI", 17)
  mock.addField(ID_MIN, "RSSI-", 17)
  mock.addField(ID_MAX, "RSSI+", 17)
  mock.addField(ID_STICK, "Thr")
  mock.sim.sensors[0] = { name = "RSSI", prec = 0, unit = 17 }
  mock.setValue(ID_RSSI, value)
  if history then
    mock.setValue(ID_MIN, history[1]); mock.setValue(ID_MAX, history[2])
  end
  local mod = dofile(widgetDir .. "main.lua")
  local o = { Source = ID_RSSI }
  for k, v in pairs(ov) do o[k] = v end
  local opts = mock.makeOptions(mod.defs, o)
  local w = mod.create(zone, opts, widgetDir)
  mod.update(w, opts)
  for _ = 1, 40 do mock.advance(50); mod.refresh(w) end
  return w
end

-- ink box of a label: LVGL aligns inside [x, x+w]; the glyphs occupy
-- `textW` px placed by the alignment.
local function labelInk(p)
  local size = FONT_PX[p.font or 0] or FONT_PX[0]
  local text = tostring(p.text or "")
  if text == "" then return nil end
  local tw = math.floor(#text * (size * 0.55))
  if tw > (p.w or 0) then tw = p.w or 0 end
  local x = p.x
  if p.align == CENTER then x = p.x + ((p.w or 0) - tw) / 2
  elseif p.align == RIGHT then x = p.x + (p.w or 0) - tw end
  return { x1 = x, y1 = p.y, x2 = x + tw, y2 = p.y + math.min(p.h or size, size),
           text = text }
end

local function overlap(a, b)
  local ix = math.min(a.x2, b.x2) - math.max(a.x1, b.x1)
  local iy = math.min(a.y2, b.y2) - math.max(a.y1, b.y1)
  if ix > 0 and iy > 0 then return ix, iy end
  return nil
end

local function inBox(box, x, y)
  return x >= box.x1 and x <= box.x2 and y >= box.y1 and y <= box.y2
end

local collisionCases = 0
local function report(name, w, zone)
  local hits = {}
  local labels, arcs, lines = {}, {}, {}
  -- The needle (and its counterweight) sweeps UNDER the dial face by design:
  -- the labels are created after it and LVGL paints them on top, so a needle
  -- crossing the value/chip text is not a defect. Since P2-1 the needle is a
  -- `line`, so the geometric check below would flag it as if it were a tick
  -- or a threshold mark (which MUST not cross text).
  local sweep = {}
  if w.ui.needle then sweep[w.ui.needle] = true end
  if w.ui.needleMid then sweep[w.ui.needleMid] = true end
  if w.ui.needleTip then sweep[w.ui.needleTip] = true end
  for _, o in ipairs(mock.objects()) do
    if not o.visible then goto cont end
    if o.kind == "label" then
      local ink = labelInk(o.props)
      if ink then labels[#labels+1] = ink end
    elseif o.kind == "arc" then
      arcs[#arcs+1] = o.props
    elseif o.kind == "line" and not sweep[o] then
      lines[#lines+1] = o.props
    end
    ::cont::
  end

  -- label vs label
  for i = 1, #labels do
    for j = i+1, #labels do
      local ix, iy = overlap(labels[i], labels[j])
      if ix then
        hits[#hits+1] = string.format("LABEL/LABEL  %q x %q  overlap %.0fx%.0f px",
          labels[i].text, labels[j].text, ix, iy)
      end
    end
  end

  -- label vs arc band (sample the drawn span)
  for _, a in ipairs(arcs) do
    local vis = ((a.bgOpacity or 0) > 0) or ((a.opacity or 255) > 0)
    if vis and a.radius and a.startAngle then
      local s = math.min(a.startAngle, a.bgStartAngle or a.startAngle)
      local e = math.max(a.endAngle or s, a.bgEndAngle or s)
      local th = (a.thickness or 2) / 2
      for _, lb in ipairs(labels) do
        local hit = false
        local ang = s
        while ang <= e and not hit do
          for _, rr in ipairs({ a.radius - th, a.radius, a.radius + th }) do
            local x = a.x + rr * math.cos(ang * math.pi / 180)
            local y = a.y + rr * math.sin(ang * math.pi / 180)
            if inBox(lb, x, y) then hit = true break end
          end
          ang = ang + 1
        end
        if hit then
          hits[#hits+1] = string.format("LABEL/RING   %q crosses an arc (r=%d, th=%d)",
            lb.text, a.radius, a.thickness or 2)
        end
      end
    end
  end

  -- label vs line (ticks, markers)
  for _, l in ipairs(lines) do
    local pts = l.pts or {}
    if #pts >= 2 then
      for _, lb in ipairs(labels) do
        local hit = false
        for t = 0, 1, 0.05 do
          local x = pts[1][1] + (pts[2][1] - pts[1][1]) * t
          local y = pts[1][2] + (pts[2][2] - pts[1][2]) * t
          if inBox(lb, x, y) then hit = true break end
        end
        if hit then
          hits[#hits+1] = string.format("LABEL/TICK   %q crossed by a line", lb.text)
        end
      end
    end
  end

  -- zero-height / zero-width visible boxes
  for _, o in ipairs(mock.objects()) do
    if o.visible and o.kind == "label" then
      local p = o.props
      if (p.h or 0) <= 0 or (p.w or 0) <= 0 then
        hits[#hits+1] = string.format("DEGENERATE   label %q box %dx%d",
          tostring(p.text), p.w or 0, p.h or 0)
      end
    end
  end

  -- dedupe
  local seen, out = {}, {}
  for _, h in ipairs(hits) do
    if not seen[h] then seen[h] = true; out[#out+1] = h end
  end
  if #out > 0 then
    collisionCases = collisionCases + 1
    print("\n## " .. name .. "  (" .. zone.w .. "x" .. zone.h .. ")")
    for _, h in ipairs(out) do print("   " .. h) end
  else
    print("\n## " .. name .. "  (" .. zone.w .. "x" .. zone.h .. ")   clean")
  end
end

local ZONES = {
  { 60, 60 }, { 80, 60 }, { 100, 100 }, { 128, 96 }, { 160, 160 },
  { 200, 160 }, { 200, 200 }, { 260, 220 }, { 300, 150 }, { 120, 220 },
  { 100, 260 }, { 480, 272 },
}
print("=== zone matrix, ShowMinMax = Markers + text, value 78 ===")
for _, z in ipairs(ZONES) do
  local zone = { x = 0, y = 0, w = z[1], h = z[2] }
  local w = build(zone, { ShowMinMax = "Markers + text" }, 78, { 31, 92 })
  report(z[1] .. "x" .. z[2], w, zone)
end

print("\n\n=== value extremes on 200x200 (large: scale labels on) ===")
for _, v in ipairs({ 0, 50, 100 }) do
  local zone = { x = 0, y = 0, w = 200, h = 200 }
  local w = build(zone, {}, v, nil)
  report("value " .. v, w, zone)
end

print("\n\n=== sweeps on 200x200 ===")
for _, s in ipairs({ "270 deg", "180 deg", "360 deg" }) do
  local zone = { x = 0, y = 0, w = 200, h = 200 }
  local w = build(zone, { Sweep = s }, 78, nil)
  report(s, w, zone)
end

print("\n\n=== Phase 4 faces / compact, standard and rich bars ===")
for _, face in ipairs({ "Blocks", "Hex", "Ticks", "Steps" }) do
  for _, z in ipairs({ { 160, 44 }, { 300, 70 }, { 480, 120 } }) do
    local zone = { x = 0, y = 0, w = z[1], h = z[2] }
    local w = build(zone, {
      Style = "Bar", BarFace = face, Segments = "24",
      ColorMode = "Sections", Surface = "Theme panel", Damping = 0,
    }, 40, { 31, 92 })
    report(face .. " " .. z[1] .. "x" .. z[2], w, zone)
  end
end

print("\n\n=== Phase 5 vertical / zero-origin / Dual Rail / presentation ===")
local P5_CASES = {
  { "vertical continuous", { 100, 260 }, {
      Style = "Bar", BarDir = "Vertical", ColorMode = "Gradient",
      ScaleMarks = "Full", ShowMinMax = "Markers + text", Damping = 0,
    }, 45 },
  { "vertical blocks zero", { 120, 300 }, {
      Style = "Bar", BarDir = "Vertical", BarFace = "Blocks",
      Segments = "24", BarOrigin = "Zero", ScaleMarks = "Thresholds",
      Scale = "Manual", Min = -100, Max = 100, Damping = 0,
    }, -65 },
  { "vertical hex zero", { 120, 300 }, {
      Style = "Bar", BarDir = "Vertical", BarFace = "Hex",
      Segments = "10", BarOrigin = "Zero", BarHead = "Needle",
      Scale = "Manual", Min = -100, Max = 100, Damping = 0,
    }, 65 },
  { "vertical ticks", { 100, 260 }, {
      Style = "Bar", BarDir = "Vertical", BarFace = "Ticks",
      Segments = "24", ValuePos = "Inside", LabelPos = "Below", Damping = 0,
    }, 45 },
  { "vertical steps", { 120, 300 }, {
      Style = "Bar", BarDir = "Vertical", BarFace = "Steps",
      Segments = "10", ValuePos = "End", LabelPos = "Inside", Damping = 0,
    }, 78 },
  { "horizontal zero gradient", { 420, 110 }, {
      Style = "Bar", BarOrigin = "Zero", ColorMode = "Gradient",
      BarHead = "Dot", ScaleMarks = "Full", Scale = "Manual",
      Min = -100, Max = 100, Damping = 0,
    }, -65 },
  { "horizontal dual rail", { 420, 110 }, {
      Style = "Bar", BarFace = "Dual rail", BarOrigin = "Zero",
      BarHead = "Cap", ScaleMarks = "Ends", Scale = "Manual",
      Min = -30, Max = 100, Damping = 0,
    }, -20 },
  { "vertical dual rail", { 120, 300 }, {
      Style = "Bar", BarDir = "Vertical", BarFace = "Dual rail",
      BarOrigin = "Zero", BarHead = "Line", ScaleMarks = "Full",
      Scale = "Manual", Min = -100, Max = 100, Damping = 0,
    }, 65 },
}
for _, c in ipairs(P5_CASES) do
  local zone = { x = 0, y = 0, w = c[2][1], h = c[2][2] }
  local w = build(zone, c[3], c[4], { -82, 91 })
  report(c[1], w, zone)
end

if collisionCases > 0 then
  io.stderr:write(string.format("collision audit: %d dirty case(s)\n",
    collisionCases))
  os.exit(1)
end
print("\ncollision audit: all cases clean")
