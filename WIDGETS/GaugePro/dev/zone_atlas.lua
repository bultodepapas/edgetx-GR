-- GaugePro Phase 0: source-derived EdgeTX widget-zone atlas.
--
-- Usage (from WIDGETS/GaugePro):
--   lua dev/zone_atlas.lua ./
--   lua dev/zone_atlas.lua ./ --check
--
-- The layout maps are parsed from radio/src/gui/colorlcd/layouts instead of
-- being copied into this tool. Decoration geometry mirrors
-- ViewMainDecoration::getWidgetsZone and enumerates every meaningful boolean
-- branch; equivalent root rectangles are deduplicated. The resulting Markdown
-- is both the human review artifact and deterministic test data.

local widgetDir = arg[1] or "./"
if string.sub(widgetDir, -1) ~= "/" and string.sub(widgetDir, -1) ~= "\\" then
  widgetDir = widgetDir .. "/"
end
local checkOnly = arg[2] == "--check"
local outPath = checkOnly and (widgetDir .. "PHASE0_ZONE_ATLAS.md")
  or (arg[2] or (widgetDir .. "PHASE0_ZONE_ATLAS.md"))
local layoutDir = widgetDir .. "../../radio/src/gui/colorlcd/layouts/"

local LAYOUT_FILES = {
  "layout1+2.cpp", "layout1+3.cpp", "layout1+4.cpp", "layout1x1.cpp",
  "layout1x1AppMode.cpp", "layout1x2.cpp", "layout1x3.cpp", "layout1x4.cpp",
  "layout1x6.cpp", "layout2+1.cpp", "layout2+3.cpp", "layout2x1.cpp",
  "layout2x2.cpp", "layout2x3.cpp", "layout2x4.cpp", "layout4+2.cpp",
  "layout4+2b.cpp",
}

local MAP = {
  LAYOUT_MAP_0 = 0, LAYOUT_MAP_1SIXTH = 10, LAYOUT_MAP_1FIFTH = 12,
  LAYOUT_MAP_1QTR = 15, LAYOUT_MAP_2FIFTH = 24,
  LAYOUT_MAP_1THIRD = 20, LAYOUT_MAP_HALF = 30,
  LAYOUT_MAP_3FIFTH = 36, LAYOUT_MAP_2THIRD = 40,
  LAYOUT_MAP_3QTR = 45, LAYOUT_MAP_4FIFTH = 48,
  LAYOUT_MAP_5SIXTH = 50, LAYOUT_MAP_FULL = 60,
}

local TARGETS = {
  { key = "sml", label = "320x240", w = 320, h = 240, scale = 0.8 },
  { key = "std", label = "480x272", w = 480, h = 272, scale = 1.0 },
  { key = "lrg", label = "800x480", w = 800, h = 480, scale = 1.375 },
}

local function readFile(path)
  local f, err = io.open(path, "rb")
  if not f then error("zone_atlas: cannot read " .. path .. ": " .. tostring(err)) end
  local s = f:read("*a")
  f:close()
  return s
end

local function writeFile(path, data)
  local f, err = io.open(path, "wb")
  if not f then error("zone_atlas: cannot write " .. path .. ": " .. tostring(err)) end
  f:write(data)
  f:close()
end

local function edgeScale(target, value)
  if target.w == 320 then return math.floor((value * 8 + 5) / 10) end
  if target.w == 800 then return math.floor((value * 11 + 4) / 8) end
  return value
end

local function oddScale(target, value)
  local n = edgeScale(target, value)
  return (n & 0xFFFE) + 1
end

local layouts = {}
for _, file in ipairs(LAYOUT_FILES) do
  local source = readFile(layoutDir .. file)
  local body = source:match("static%s+const%s+uint8_t%s+zmap%[%]%s*=%s*{(.-)};")
  if not body then error("zone_atlas: zmap not found in " .. file) end
  local values, tokens = {}, {}
  for token in body:gmatch("LAYOUT_MAP_[A-Z0-9]+") do
    local value = MAP[token]
    if value == nil then error("zone_atlas: unknown map token " .. token) end
    values[#values + 1], tokens[#tokens + 1] = value, token
  end
  if #values == 0 or #values % 4 ~= 0 then
    error("zone_atlas: invalid zmap in " .. file)
  end
  layouts[#layouts + 1] = {
    file = file, name = file:gsub("%.cpp$", ""), values = values,
    tokens = tokens, zones = #values / 4,
    app = file == "layout1x1AppMode.cpp",
  }
end

-- Exact geometry from ViewMainDecoration::getWidgetsZone(). We enumerate the
-- structural switches plus the radio-dependent branches (vertical sliders,
-- visible vertical/horizontal trims, and a six-position switch). Inputs that
-- do not affect a disabled decoration are normalized, then identical roots
-- are collapsed while retaining the number of source permutations.
local function widgetRoot(target, p)
  local menu = edgeScale(target, 45)
  local stdFont = edgeScale(target, 21)
  local pad = edgeScale(target, 8)
  local slider = oddScale(target, 15) + 2
  local x, y, w, h, bh = 0, 0, target.w, target.h, 0

  if p.topbar then y, bh = menu, menu end
  if p.sliders then
    if p.verticalSliders then x, w = x + slider, w - 2 * slider end
    bh = bh + slider
  end
  if p.trims then
    if p.trimLV then x, w = x + slider, w - slider end
    if p.trimRV then w = w - slider end
    if p.fm and (p.has6pos or not p.sliders) then
      bh = bh + stdFont
    elseif p.trimH then
      bh = bh + slider
    end
  elseif p.fm then
    bh = bh + stdFont
    if not p.has6pos and p.sliders then bh = bh - slider end
  end
  if p.sliders or p.trims or p.fm then
    x, y, w, bh = x + pad, y + pad, w - 2 * pad, bh + 2 * pad
  end
  return { x = x, y = y, w = w, h = h - bh }
end

local function bools()
  return { false, true }
end

local function decorationRoots(target)
  local byKey, permutations = {}, 0
  for _, topbar in ipairs(bools()) do
    for _, fm in ipairs(bools()) do
      for _, sliders in ipairs(bools()) do
        for _, verticalSliders in ipairs(bools()) do
          for _, trims in ipairs(bools()) do
            for _, trimLV in ipairs(bools()) do
              for _, trimRV in ipairs(bools()) do
                for _, trimH in ipairs(bools()) do
                  for _, has6pos in ipairs(bools()) do
                    -- Normalize irrelevant hardware switches so the input set
                    -- represents meaningful permutations rather than 512
                    -- aliases of the same disabled controls.
                    if (sliders or not verticalSliders)
                       and (trims or (not trimLV and not trimRV and not trimH))
                       and (fm or not has6pos) then
                      permutations = permutations + 1
                      local root = widgetRoot(target, {
                        topbar = topbar, fm = fm, sliders = sliders,
                        verticalSliders = verticalSliders, trims = trims,
                        trimLV = trimLV, trimRV = trimRV, trimH = trimH,
                        has6pos = has6pos,
                      })
                      local key = string.format("%d,%d,%d,%d",
                        root.x, root.y, root.w, root.h)
                      local rec = byKey[key]
                      if rec then rec.variants = rec.variants + 1
                      else
                        root.key, root.variants = key, 1
                        byKey[key] = root
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  local roots = {}
  for _, root in pairs(byKey) do roots[#roots + 1] = root end
  table.sort(roots, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if a.x ~= b.x then return a.x < b.x end
    if a.w ~= b.w then return a.w < b.w end
    return a.h < b.h
  end)
  return roots, permutations
end

local function resolveZone(root, values, i)
  local at = (i - 1) * 4
  local xo = math.floor(root.w * values[at + 1] / 60)
  local yo = math.floor(root.h * values[at + 2] / 60)
  local w = math.floor(root.w * values[at + 3] / 60)
  local h = math.floor(root.h * values[at + 4] / 60)
  return { x = root.x + xo, y = root.y + yo, w = w, h = h }
end

local function family(target, rect, topbar)
  if topbar then return "topbar-micro" end
  local logicalMin = math.min(rect.w, rect.h) / target.scale
  local size
  if logicalMin < 64 then size = "micro"
  elseif logicalMin < 105 then size = "compact"
  elseif logicalMin < 180 then size = "normal"
  else size = "large" end
  local ratio = rect.w / math.max(1, rect.h)
  if ratio > 2.6 then return size .. "/short-strip" end
  if ratio < 0.8 then return size .. "/tall" end
  return size .. "/balanced"
end

local function topbarData(target)
  local left = edgeScale(target, 47)
  local padTiny = edgeScale(target, 2)
  local padThree = edgeScale(target, 3)
  local menu = edgeScale(target, 45)
  local base = edgeScale(target, target.w >= 800 and 74 or 70)
  local maxSlots = math.floor((target.w - left - 1 + base / 2) / base)
  local out = {}
  for span = 1, maxSlots do
    local w = (span - 1) * (base + padTiny) + base
    if left + 1 + w > target.w then w = target.w - left - 1 end
    out[#out + 1] = { span = span, x = left + 1, y = padThree,
      w = w, h = menu - 2 * padThree }
  end
  return out
end

local function add(lines, s)
  lines[#lines + 1] = s or ""
end

local lines = {}
add(lines, "# Gauge Pro Phase 0 — EdgeTX zone atlas")
add(lines)
add(lines, "> Generated by `dev/zone_atlas.lua` from the checked-out EdgeTX "
  .. "layout maps and decoration formula. Do not hand-edit.")
add(lines)
add(lines, "## Contract")
add(lines)
add(lines, "- 16 standard layouts plus the separate app-mode layout are parsed"
  .. " from `radio/src/gui/colorlcd/layouts`.")
add(lines, "- The 320×240, 480×272, and 800×480 shipped LCD scales use the"
  .. " firmware's integer scaling rules.")
add(lines, "- Top bar, flight mode, sliders, trims, vertical hardware, and"
  .. " six-position-switch branches are enumerated and deduplicated.")
add(lines, "- Responsive families retain the existing 64/105/180"
  .. " logical-pixel thresholds, with `short-strip`, `tall`, and"
  .. " `topbar-micro` subprofiles.")
add(lines)
add(lines, "## Source layout maps")
add(lines)
add(lines, "| Layout source | Kind | Zones | Normalized `(x,y,w,h)` over 60 |")
add(lines, "|---|---:|---:|---|")
for _, layout in ipairs(layouts) do
  local tuples = {}
  for i = 1, layout.zones do
    local at = (i - 1) * 4
    tuples[#tuples + 1] = string.format("(%d,%d,%d,%d)",
      layout.values[at + 1], layout.values[at + 2],
      layout.values[at + 3], layout.values[at + 4])
  end
  add(lines, string.format("| `%s` | %s | %d | `%s` |", layout.file,
    layout.app and "app" or "standard", layout.zones, table.concat(tuples, " ")))
end

local grandZones, grandRoots = 0, 0
for _, target in ipairs(TARGETS) do
  local roots, permutations = decorationRoots(target)
  grandRoots = grandRoots + #roots
  add(lines)
  add(lines, "## " .. target.label .. " (`LCD_SCALE=" .. target.scale .. "`)")
  add(lines)
  add(lines, string.format("Decoration enumeration: **%d meaningful inputs"
    .. " → %d unique widget roots**.",
    permutations, #roots))
  add(lines)
  add(lines, "<details><summary>Exact deduplicated widget roots</summary>")
  add(lines)
  add(lines, "| Root `(x,y,w,h)` | Equivalent inputs |")
  add(lines, "|---|---:|")
  for _, root in ipairs(roots) do
    add(lines, string.format("| `%s` | %d |", root.key, root.variants))
  end
  add(lines)
  add(lines, "</details>")
  add(lines)

  local topbar = topbarData(target)
  add(lines, "Top-bar zones:")
  add(lines)
  add(lines, "| Slot span | Rectangle `(x,y,w,h)` | Family |")
  add(lines, "|---:|---|---|")
  for _, z in ipairs(topbar) do
    add(lines, string.format("| %d | `%d,%d,%d,%d` | topbar-micro |",
      z.span, z.x, z.y, z.w, z.h))
  end

  local exact, familyCounts = {}, {}
  for _, layout in ipairs(layouts) do
    if layout.app then
      local root = { x = 0, y = 0, w = target.w, h = target.h }
      local z = resolveZone(root, layout.values, 1)
      local key = string.format("%d,%d,%d,%d", z.x, z.y, z.w, z.h)
      exact[key] = exact[key] or { rect = z, sources = 0 }
      exact[key].sources = exact[key].sources + 1
    else
      for _, root in ipairs(roots) do
        for i = 1, layout.zones do
          local z = resolveZone(root, layout.values, i)
          local key = string.format("%d,%d,%d,%d", z.x, z.y, z.w, z.h)
          exact[key] = exact[key] or { rect = z, sources = 0 }
          exact[key].sources = exact[key].sources + 1
        end
      end
    end
  end
  for _, z in ipairs(topbar) do
    local key = string.format("%d,%d,%d,%d", z.x, z.y, z.w, z.h)
    exact[key] = exact[key] or { rect = z, sources = 0, topbar = true }
    exact[key].sources = exact[key].sources + 1
    exact[key].topbar = true
  end

  local exactList = {}
  for key, rec in pairs(exact) do
    rec.key = key
    exactList[#exactList + 1] = rec
    local f = family(target, rec.rect, rec.topbar)
    familyCounts[f] = (familyCounts[f] or 0) + 1
  end
  table.sort(exactList, function(a, b)
    if a.rect.w ~= b.rect.w then return a.rect.w < b.rect.w end
    if a.rect.h ~= b.rect.h then return a.rect.h < b.rect.h end
    if a.rect.x ~= b.rect.x then return a.rect.x < b.rect.x end
    return a.rect.y < b.rect.y
  end)
  grandZones = grandZones + #exactList

  add(lines)
  add(lines, string.format("Resolved atlas: **%d exact unique rectangles**.",
    #exactList))
  add(lines)
  add(lines, "| Responsive family | Unique rectangles |")
  add(lines, "|---|---:|")
  local familyNames = {}
  for name in pairs(familyCounts) do familyNames[#familyNames + 1] = name end
  table.sort(familyNames)
  for _, name in ipairs(familyNames) do
    add(lines, string.format("| %s | %d |", name, familyCounts[name]))
  end
  add(lines)
  add(lines, "<details><summary>All exact rectangles (machine-reviewable)</summary>")
  add(lines)
  add(lines, "Each entry is `x,y,w,h × source-occurrences` after EdgeTX"
    .. " integer truncation.")
  add(lines)
  local row = {}
  for i, rec in ipairs(exactList) do
    row[#row + 1] = string.format("`%s`×%d", rec.key, rec.sources)
    if #row == 6 or i == #exactList then
      add(lines, table.concat(row, " · "))
      add(lines)
      row = {}
    end
  end
  add(lines, "</details>")
end

add(lines)
add(lines, "## Atlas gate")
add(lines)
add(lines, string.format("The generator parsed **%d layouts**, produced **%d"
  .. " unique decoration roots** across targets, and classified **%d exact"
  .. " zone rectangles**. Every rectangle has a size family and an"
  .. " orientation subprofile; Phase 1/2 tests can consume the same generator"
  .. " rather than maintain a second handwritten matrix.",
  #layouts, grandRoots, grandZones))
add(lines)
add(lines, "The atlas deliberately preserves current dial breakpoints. It"
  .. " does not authorize changing Auto from dial to bar; it only adds"
  .. " `topbar-micro`, `short-strip`, and `tall` bar subprofiles within an"
  .. " already selected Bar style.")
add(lines)

local output = table.concat(lines, "\n")
if checkOnly then
  local old = readFile(outPath)
  if old ~= output then
    io.stderr:write("zone_atlas: generated atlas differs from " .. outPath .. "\n")
    os.exit(1)
  end
  print("zone_atlas: current (" .. #layouts .. " layouts)")
else
  writeFile(outPath, output)
  print(string.format("zone_atlas: %d layouts, %d roots, %d exact rectangles -> %s",
    #layouts, grandRoots, grandZones, outPath))
end
