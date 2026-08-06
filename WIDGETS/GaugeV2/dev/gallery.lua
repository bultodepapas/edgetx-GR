-- GaugeV2 - hoja de contraste visual (visual contract sheet).
--
--   lua5.3 dev/gallery.lua <widget-dir> [opciones]
--
-- Compone TODAS las escenas de dev/scenes.lua en un unico SVG autocontenido y
-- escribe un manifiesto con los hechos de cada escena. Sin navegador, sin
-- Python, sin PIL: sale de Lua directo, igual que el resto del utillaje.
--
-- Por que un SVG y no un PNG:
--   * vectorial - se puede hacer zoom sobre la aguja sin pixelar,
--   * texto real - se puede buscar "CRIT" en la hoja,
--   * es texto plano - dos versiones se pueden diferenciar con git diff,
--   * cero dependencias - se abre en cualquier navegador.
-- (--png sigue disponible si hace falta una imagen plana; usa el primer
-- rasterizador que encuentre y avisa si no hay ninguno.)
--
-- Por que un manifiesto ademas de la imagen: mirar la hoja verifica lo que se
-- ve; el manifiesto verifica lo que NO se ve (modo de layout, disponibilidad,
-- clave de color, censo de objetos) y permite comparar dos ejecuciones sin
-- ojo humano. `--baseline` hace exactamente eso.
--
-- Opciones:
--   --out DIR         destino (por defecto <widget>/dev/shots/gallery/)
--   --theme T         dark | light | both        (por defecto both)
--   --only PATRON     filtra por nombre de escena o clave de seccion
--   --tag NOMBRE      guarda ademas una copia versionada -NOMBRE
--   --baseline FILE   compara el manifiesto nuevo contra ese y lista cambios
--   --list            imprime el catalogo y sale
--   --png             intenta rasterizar el SVG resultante
--   --strict          codigo de salida != 0 si hay avisos de render
--   --help

local args = { ... }
local widgetDir = nil
local opt = { theme = "both", out = nil, only = nil, tag = nil,
              baseline = nil, list = false, png = false, strict = false }

do
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--help" or a == "-h" then
      print((string.gsub([[
uso: lua5.3 dev/gallery.lua <widget-dir> [opciones]
  --out DIR        destino (por defecto <widget>/dev/shots/gallery/)
  --theme T        dark | light | both       (por defecto both)
  --only PATRON    filtra por nombre de escena o clave de seccion
  --tag NOMBRE     guarda ademas una copia versionada -NOMBRE
  --baseline FILE  compara contra un manifiesto anterior
  --list           imprime el catalogo y sale
  --png            intenta rasterizar el SVG resultante
  --strict         salida != 0 si hay avisos de render
]], "^%s+", "")))
      os.exit(0)
    elseif a == "--list" then opt.list = true
    elseif a == "--png" then opt.png = true
    elseif a == "--strict" then opt.strict = true
    elseif a == "--out" then i = i + 1; opt.out = args[i]
    elseif a == "--theme" then i = i + 1; opt.theme = args[i]
    elseif a == "--only" then i = i + 1; opt.only = args[i]
    elseif a == "--tag" then i = i + 1; opt.tag = args[i]
    elseif a == "--baseline" then i = i + 1; opt.baseline = args[i]
    elseif string.sub(a, 1, 2) == "--" then
      io.stderr:write("gallery: opcion desconocida " .. a .. "\n")
      os.exit(2)
    elseif not widgetDir then widgetDir = a end
    i = i + 1
  end
end
widgetDir = widgetDir or "./"
if string.sub(widgetDir, -1) ~= "/" then widgetDir = widgetDir .. "/" end
local outDir = opt.out or (widgetDir .. "dev/shots/gallery/")
if string.sub(outDir, -1) ~= "/" then outDir = outDir .. "/" end

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)
local svgkit = dofile(widgetDir .. "dev/svgkit.lua")
local scenes = dofile(widgetDir .. "dev/scenes.lua")

local fmt = string.format
local floor, max, min = math.floor, math.max, math.min

-- ------------------------------------------------------------------ utils --

local function sh(cmd)
  local ok, f = pcall(io.popen, cmd .. " 2>/dev/null")
  if not ok or not f then return nil end
  local s = f:read("*a")
  f:close()
  if not s or s == "" then return nil end
  return (string.gsub(s, "%s+$", ""))
end

local function ensureDir(path)
  -- mkdir -p works under WSL/msys; on failure the io.open below reports it.
  os.execute(fmt('mkdir -p "%s" 2>/dev/null || mkdir "%s" 2>nul', path, path))
end

local function writeFile(path, text)
  local f, err = io.open(path, "w")
  if not f then error("gallery: no se pudo escribir " .. path .. ": "
    .. tostring(err)) end
  f:write(text)
  f:close()
end

local function copyFile(from, to)
  local a = io.open(from, "rb"); if not a then return false end
  local data = a:read("*a"); a:close()
  local b = io.open(to, "wb"); if not b then return false end
  b:write(data); b:close()
  return true
end

-- Deterministic key order: numbers first, then strings, both ascending. A
-- manifest that reorders itself between runs is useless for diffing.
local function sortedKeys(t)
  local nums, strs = {}, {}
  for k in pairs(t) do
    if type(k) == "number" then nums[#nums + 1] = k else strs[#strs + 1] = k end
  end
  table.sort(nums)
  table.sort(strs, function(a, b) return tostring(a) < tostring(b) end)
  for _, s in ipairs(strs) do nums[#nums + 1] = s end
  return nums
end

-- ------------------------------------------------------- version stamping --

local function versionInfo()
  local v = {
    date = os.date("!%Y-%m-%d %H:%M UTC"),
    lua = _VERSION,
    sha = sh("git -C \"" .. widgetDir .. "\" rev-parse --short HEAD")
          or "sin-git",
    branch = sh("git -C \"" .. widgetDir .. "\" rev-parse --abbrev-ref HEAD")
          or "?",
  }
  local dirty = sh("git -C \"" .. widgetDir
    .. "\" status --porcelain -- . | head -c 1")
  v.dirty = (dirty ~= nil and dirty ~= "")
  return v
end

-- ----------------------------------------------------------- manifest I/O --

-- Texto canonico de un escalar. Serializacion y comparacion DEBEN usar el
-- mismo, o el viaje de ida y vuelta no es estable: serialize() escribe el
-- float -78.0 como "-78", dofile() lo relee como entero, y un diff ingenuo
-- reporta "-78 -> -78.0" en cada ejecucion. Un diferenciador que grita sin
-- que haya cambiado nada no lo usa nadie.
local function scalarText(v)
  if type(v) == "number" then
    if v == floor(v) and math.abs(v) < 2 ^ 53 then return fmt("%d", v) end
    return fmt("%.6g", v)
  end
  return tostring(v)
end

local function serialize(v, indent, buf)
  local pad = string.rep("  ", indent)
  if type(v) == "table" then
    buf[#buf + 1] = "{\n"
    for _, k in ipairs(sortedKeys(v)) do
      local kv = v[k]
      if type(k) == "number" then
        buf[#buf + 1] = pad .. "  "
      else
        buf[#buf + 1] = fmt("%s  [%q] = ", pad, k)
      end
      serialize(kv, indent + 1, buf)
      buf[#buf + 1] = ",\n"
    end
    buf[#buf + 1] = pad .. "}"
  elseif type(v) == "string" then
    buf[#buf + 1] = fmt("%q", v)
  else
    buf[#buf + 1] = scalarText(v)
  end
end

local function manifestText(manifest)
  local buf = { "-- GaugeV2 gallery manifest - generado por dev/gallery.lua\n",
                "-- No editar a mano. Comparar con:\n",
                "--   lua5.3 dev/gallery.lua . --baseline <este fichero>\n",
                "return " }
  serialize(manifest, 0, buf)
  buf[#buf + 1] = "\n"
  return table.concat(buf)
end

-- Flatten to "a.b.c" = value, so a diff can name exactly what moved.
local function flatten(t, prefix, out)
  out = out or {}
  prefix = prefix or ""
  for _, k in ipairs(sortedKeys(t)) do
    local v = t[k]
    local key = (prefix == "") and tostring(k) or (prefix .. "." .. tostring(k))
    if type(v) == "table" then flatten(v, key, out) else out[key] = v end
  end
  return out
end

local function diffManifests(oldM, newM)
  local changes = { added = {}, removed = {}, changed = {} }
  local oldC = oldM.cases or {}
  local newC = newM.cases or {}
  for name in pairs(newC) do
    if not oldC[name] then changes.added[#changes.added + 1] = name end
  end
  for name in pairs(oldC) do
    if not newC[name] then changes.removed[#changes.removed + 1] = name end
  end
  table.sort(changes.added); table.sort(changes.removed)
  local names = {}
  for name in pairs(newC) do if oldC[name] then names[#names + 1] = name end end
  table.sort(names)
  for _, name in ipairs(names) do
    local a, b = flatten(oldC[name]), flatten(newC[name])
    local keys, seen = {}, {}
    for k in pairs(a) do if not seen[k] then seen[k] = true; keys[#keys+1] = k end end
    for k in pairs(b) do if not seen[k] then seen[k] = true; keys[#keys+1] = k end end
    table.sort(keys)
    local fields = {}
    for _, k in ipairs(keys) do
      local av, bv = scalarText(a[k]), scalarText(b[k])
      if av ~= bv then
        fields[#fields + 1] = fmt("%s: %s -> %s", k, av, bv)
      end
    end
    if #fields > 0 then
      changes.changed[#changes.changed + 1] = { name = name, fields = fields }
    end
  end
  return changes
end

-- ------------------------------------------------------ option coverage ----

-- Cross-check the catalogue against main.lua's DEFS: an option that no scene
-- ever varies is an option the sheet does not actually verify. This is what
-- stops the gallery from silently going stale when option 25 gets appended.
local function coverage(defs, cases)
  local seen = {}
  for _, c in ipairs(cases) do
    for k, v in pairs(c.opts or {}) do
      seen[k] = seen[k] or {}
      seen[k][tostring(v)] = true
    end
  end
  local rows = {}
  for _, d in ipairs(defs) do
    if d.key ~= "Source" then
      local vals, n = {}, 0
      for v in pairs(seen[d.key] or {}) do vals[#vals + 1] = v; n = n + 1 end
      table.sort(vals)
      local total = d.choices and #d.choices or nil
      rows[#rows + 1] = {
        key = d.key, label = d.label, values = vals, count = n,
        total = total, nonVisual = scenes.NON_VISUAL[d.key],
        covered = (n > 0),
      }
    end
  end
  return rows
end

-- ----------------------------------------------------------- sheet layout --

local PAD, GAP, COLGAP = 26, 18, 16
local CONTENT_W = 1240
local TILE_MIN_W = 200   -- ancho de columna, no de imagen: una escena estrecha
                         -- (120x220) necesita mas sitio para su pie que para
                         -- su dibujo, o el pie sale truncado
local CAP_LEAD, CAP_SIZE = 13, 10.5

local function tileScale(zw, zh)
  local s = min(304 / zw, 214 / zh)
  if s > 2.4 then s = 2.4 end
  if s < 0.5 then s = 0.5 end
  return s
end

local function shorten(s, n)
  s = tostring(s or "")
  if #s <= n then return s end
  return string.sub(s, 1, n - 1) .. "\u{2026}"
end

-- Two or three caption lines of dense facts, plus the case note when it has
-- one. Deliberately terse: the tile is the evidence, the caption is the index.
local function captionLines(case, f)
  local l = {}
  l[#l + 1] = { text = case.title or case.name, weight = "600", tone = "ink" }
  l[#l + 1] = { text = fmt("%dx%d  %s/%s  %s  %d obj",
    case.zone[1], case.zone[2], tostring(f.mode), tostring(f.orientation),
    tostring(f.style), (f.objects and f.objects.total) or 0), tone = "dim" }
  local val = f.value or "-"
  if f.unit and f.unit ~= "" then val = val .. " " .. f.unit end
  l[#l + 1] = { text = fmt("%s  %s%s", val,
    tostring(f.state or f.availability),
    (f.chip and f.chip ~= "") and ("  [" .. f.chip .. "]") or ""),
    tone = "dim" }
  if case.note then
    l[#l + 1] = { text = shorten(case.note, 44), tone = "note" }
  end
  return l
end

local function renderSheet(theme, cases, results, version, cov)
  local cv = svgkit.newCanvas(theme)
  local pal = cv.pal
  local body = {}          -- content is emitted first, height known after
  local function put(s) body[#body + 1] = s end

  local function text(x, y, s, size, fill, weight, anchor)
    put(fmt('<text x="%.1f" y="%.1f" font-size="%.1f" fill="%s"'
      .. ' font-weight="%s" text-anchor="%s"'
      .. ' font-family="DejaVu Sans, Verdana, sans-serif">%s</text>',
      x, y, size, fill, weight or "400", anchor or "start", svgkit.esc(s)))
  end

  local y = PAD

  -- ---- header -------------------------------------------------------------
  put(fmt('<rect x="%d" y="%d" width="%d" height="78" rx="10" fill="%s"'
    .. ' stroke="%s"/>', PAD, y, CONTENT_W, pal.panel, pal.rule))
  text(PAD + 20, y + 30, "GaugeV2 - hoja de contraste visual", 21, pal.ink,
       "700")
  text(PAD + 20, y + 51, fmt(
    "%d escenas  -  tema %s  -  %s@%s%s  -  %s  -  %s",
    #cases, theme, version.branch, version.sha,
    version.dirty and " (arbol sucio)" or "", version.date, version.lua),
    11.5, pal.dim)
  text(PAD + 20, y + 68, "Las cajas de texto que desbordan se marcan con un"
    .. " recuadro rojo discontinuo; las escenas con avisos llevan un punto"
    .. " rojo arriba a la derecha.", 10.5, pal.dim)
  y = y + 78 + GAP + 6

  -- ---- sections -----------------------------------------------------------
  local bySection = {}
  for _, r in ipairs(results) do
    bySection[r.case.section] = bySection[r.case.section] or {}
    local t = bySection[r.case.section]
    t[#t + 1] = r
  end

  for _, sec in ipairs(scenes.sections) do
    local rows = bySection[sec.key]
    if rows and #rows > 0 then
      put(fmt('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s"/>',
        PAD, y, PAD + CONTENT_W, y, pal.rule))
      text(PAD, y + 20, sec.title, 15, pal.ink, "700")
      text(PAD, y + 36, sec.note, 10.5, pal.dim)
      y = y + 48

      -- pack tiles into rows
      local rowItems, rowW, rowH = {}, 0, 0
      local function flushRow()
        if #rowItems == 0 then return end
        local x = PAD
        for _, it in ipairs(rowItems) do
          local r = it.r
          -- frame + scene
          put(fmt('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="4"'
            .. ' fill="%s" stroke="%s"/>',
            x - 1, y - 1, it.imgW + 2, it.imgH + 2, pal.bg, pal.rule))
          cv.out = body
          cv:scene(r.objects, r.zone, x, y, it.scale, r.case.name)
          if #r.warnings > 0 then
            put(fmt('<circle cx="%.1f" cy="%.1f" r="4.5" fill="#ff3b30"/>',
              x + it.imgW - 6, y + 6))
          end
          -- caption
          local ty = y + it.imgH + 14
          for _, line in ipairs(it.lines) do
            local fill = (line.tone == "ink") and pal.ink
              or ((line.tone == "note") and pal.accent or pal.dim)
            text(x, ty, shorten(line.text, floor(it.colW / 5.4)),
                 (line.tone == "ink") and 12 or CAP_SIZE, fill,
                 line.weight or "400")
            ty = ty + CAP_LEAD
          end
          x = x + it.colW + COLGAP
        end
        y = y + rowH + GAP
        rowItems, rowW, rowH = {}, 0, 0
      end

      for _, r in ipairs(rows) do
        local zw, zh = r.case.zone[1], r.case.zone[2]
        local scale = tileScale(zw, zh)
        local imgW, imgH = zw * scale, zh * scale
        local lines = captionLines(r.case, r.facts)
        local colW = max(imgW, TILE_MIN_W)
        local h = imgH + 14 + #lines * CAP_LEAD
        if rowW > 0 and rowW + colW > CONTENT_W then flushRow() end
        rowItems[#rowItems + 1] = { r = r, scale = scale, imgW = imgW,
          imgH = imgH, colW = colW, lines = lines }
        rowW = rowW + colW + COLGAP
        rowH = max(rowH, h)
      end
      flushRow()
      y = y + 10
    end
  end

  -- ---- coverage panel -----------------------------------------------------
  local panelTop = y
  put(fmt('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s"/>',
    PAD, y, PAD + CONTENT_W, y, pal.rule))
  text(PAD, y + 20, "Cobertura de opciones", 15, pal.ink, "700")
  text(PAD, y + 36, "Que opciones varia realmente esta hoja. Una opcion que"
    .. " ninguna escena cambia es una opcion que la hoja NO verifica.",
    10.5, pal.dim)
  y = y + 52
  local colX = { PAD, PAD + 190, PAD + 300 }
  text(colX[1], y, "OPCION", 10, pal.dim, "700")
  text(colX[2], y, "VARIANTES", 10, pal.dim, "700")
  text(colX[3], y, "VALORES USADOS", 10, pal.dim, "700")
  y = y + 6
  put(fmt('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s"/>',
    PAD, y, PAD + CONTENT_W, y, pal.rule))
  y = y + 15
  for _, row in ipairs(cov) do
    local mark, tone
    if row.nonVisual then mark, tone = "n/a", pal.dim
    elseif not row.covered then mark, tone = "SIN COBERTURA", "#ff3b30"
    elseif row.total and row.count < row.total then
      mark, tone = fmt("%d/%d", row.count, row.total), pal.ink
    else
      mark, tone = fmt("%d", row.count), pal.ink
    end
    text(colX[1], y, row.label or row.key, 11, pal.ink)
    text(colX[2], y, mark, 11, tone, row.covered and "400" or "700")
    local vals = row.nonVisual or table.concat(row.values, ", ")
    text(colX[3], y, shorten(vals, 150), 11, pal.dim)
    y = y + 15
  end
  y = y + 10
  put(fmt('<rect x="%d" y="%.1f" width="%d" height="0.6" fill="%s"/>',
    PAD, panelTop, CONTENT_W, pal.rule))

  local totalH = y + PAD
  local totalW = CONTENT_W + PAD * 2
  local head = fmt('<svg viewBox="0 0 %d %.0f" width="%d" height="%.0f"'
    .. ' xmlns="http://www.w3.org/2000/svg">\n'
    .. '<rect width="%d" height="%.0f" fill="%s"/>',
    totalW, totalH, totalW, totalH, totalW, totalH, pal.bg)
  return head .. "\n" .. table.concat(body, "\n") .. "\n</svg>", cv
end

-- ------------------------------------------------------------ rasterising --

-- A Windows interpreter reached from WSL needs Windows paths; wslpath is the
-- only reliable translator (a hand-rolled /mnt/c -> C: rewrite breaks on UNC
-- mounts and on a plain Linux box where wslpath does not exist at all).
local function nativePath(p, forWindows)
  if not forWindows then return p end
  return sh(fmt('wslpath -w "%s"', p)) or p
end

local function rasterise(svgPath, pngPath, width)
  if sh("rsvg-convert --version") then
    os.execute(fmt('rsvg-convert -w %d -o "%s" "%s"', width, pngPath, svgPath))
    return "rsvg-convert"
  end
  if sh("inkscape --version") then
    os.execute(fmt('inkscape --export-type=png --export-width=%d'
      .. ' --export-filename="%s" "%s" >/dev/null 2>&1',
      width, pngPath, svgPath))
    return "inkscape"
  end
  -- Last resort: a headless browser via the python playwright package. The
  -- .exe candidates matter under WSL, where the Linux python usually has no
  -- playwright but the Windows one does.
  local helper = outDir .. "_rasterise.py"
  writeFile(helper, table.concat({
    "import sys, pathlib",
    "from playwright.sync_api import sync_playwright",
    "src, dst, w = sys.argv[1], sys.argv[2], int(sys.argv[3])",
    "url = pathlib.Path(src).resolve().as_uri()",
    "with sync_playwright() as p:",
    "    b = p.chromium.launch()",
    "    pg = b.new_page(viewport={'width': w, 'height': 1200})",
    "    pg.goto(url)",
    "    pg.wait_for_timeout(250)",
    "    el = pg.query_selector('svg')",
    "    el.screenshot(path=dst)",
    "    b.close()",
  }, "\n"))
  local probe = [[ -c 'import playwright;print("ok")']]
  for _, py in ipairs({ "python3", "python", "python.exe", "py.exe" }) do
    if sh(py .. probe) then
      local win = (string.sub(py, -4) == ".exe")
      local rc = os.execute(fmt('%s "%s" "%s" "%s" %d >/dev/null 2>&1', py,
        nativePath(helper, win), nativePath(svgPath, win),
        nativePath(pngPath, win), width))
      if rc == true or rc == 0 then
        os.remove(helper)
        return py .. " + playwright"
      end
    end
  end
  os.remove(helper)
  return nil
end

-- ------------------------------------------------------------------- main --

local mod = dofile(widgetDir .. "main.lua")
local defs = mod.defs

local allCases = scenes.allCases()
local cases = {}
for _, c in ipairs(allCases) do
  if not opt.only or string.find(c.name, opt.only)
     or string.find(c.section, opt.only) then
    cases[#cases + 1] = c
  end
end

if opt.list then
  print(fmt("catalogo: %d escenas en %d secciones", #allCases,
    #scenes.sections))
  for _, sec in ipairs(scenes.sections) do
    print("\n" .. sec.title)
    for _, c in ipairs(sec.cases) do
      print(fmt("  %-18s %-28s %dx%d", c.name, c.title or "",
        c.zone[1], c.zone[2]))
    end
  end
  os.exit(0)
end

if #cases == 0 then
  io.stderr:write("gallery: ninguna escena coincide con --only "
    .. tostring(opt.only) .. "\n")
  os.exit(2)
end

ensureDir(outDir)
local version = versionInfo()

-- Un run filtrado NO puede pisar la hoja completa ni, sobre todo, el
-- manifiesto: sobrescribir la baseline con 7 de 77 escenas convierte el
-- siguiente --baseline en un "-70 escenas eliminadas" sin que nadie haya roto
-- nada. Los parciales escriben con su propio sufijo.
local slug = ""
if opt.only then
  slug = "-only-" .. (string.gsub(opt.only, "[^%w]+", "_"))
end

-- Render every scene ONCE; both themes reuse the captured object trees.
-- (The mock is global state, so each scene must be captured before the next
-- one resets it.)
local results, failures = {}, {}
for _, c in ipairs(cases) do
  local ok, ctx = pcall(scenes.build, mock, widgetDir, c)
  if not ok then
    failures[#failures + 1] = fmt("%s: %s", c.name, tostring(ctx))
  else
    local snapshot = {}
    for _, o in ipairs(mock.objects()) do
      if o.visible then snapshot[#snapshot + 1] = o end
    end
    results[#results + 1] = {
      case = c, zone = ctx.zone, objects = snapshot,
      facts = scenes.facts(ctx), warnings = {},
    }
  end
end

if #failures > 0 then
  io.stderr:write("gallery: " .. #failures .. " escena(s) fallaron:\n")
  for _, f in ipairs(failures) do io.stderr:write("  " .. f .. "\n") end
end

local cov = coverage(defs, cases)

local themes = (opt.theme == "both") and { "dark", "light" } or { opt.theme }
local written, allWarnings = {}, {}
for _, theme in ipairs(themes) do
  -- clear any warnings the previous theme collected on the same scenes
  for _, r in ipairs(results) do r.warnings = {} end
  local cv = svgkit.newCanvas(theme)
  -- first pass populates per-scene warnings so the badges are right
  for _, r in ipairs(results) do
    local probe = svgkit.newCanvas(theme)
    local _, warns = probe:scene(r.objects, r.zone, 0, 0, 1, r.case.name)
    r.warnings = warns
    for _, wmsg in ipairs(warns) do allWarnings[#allWarnings + 1] = wmsg end
  end
  local svg = renderSheet(theme, cases, results, version, cov)
  local path = fmt("%sgallery-%s%s.svg", outDir, theme, slug)
  writeFile(path, svg)
  written[#written + 1] = path
  if opt.tag then
    copyFile(path, fmt("%sgallery-%s%s-%s.svg", outDir, theme, slug, opt.tag))
  end
  if opt.png then
    local png = (string.gsub(path, "%.svg$", ".png"))
    local how = rasterise(path, png, 1292)
    if how then
      print("PNG via " .. how .. ": " .. png)
    else
      io.stderr:write("gallery: sin rasterizador (rsvg-convert / inkscape /"
        .. " python+playwright); el SVG si se escribio\n")
    end
  end
  cv = nil
end

-- ---- manifest --------------------------------------------------------------

local manifest = {
  generated = version.date, sha = version.sha, branch = version.branch,
  dirty = version.dirty, sceneCount = #results, cases = {},
  coverage = {},
}
for _, r in ipairs(results) do
  local rec = r.facts
  rec.section = r.case.section
  rec.zone = fmt("%dx%d", r.case.zone[1], r.case.zone[2])
  rec.warnings = #r.warnings
  local o = {}
  for k, v in pairs(scenes.resolveOpts(r.case.opts) or {}) do
    o[k] = tostring(v)
  end
  rec.options = o
  manifest.cases[r.case.name] = rec
end
for _, row in ipairs(cov) do
  manifest.coverage[row.key] = row.nonVisual and "n/a"
    or (row.covered and table.concat(row.values, ",") or "SIN COBERTURA")
end

manifest.filter = opt.only or false
local manifestPath = fmt("%smanifest%s.lua", outDir, slug)
writeFile(manifestPath, manifestText(manifest))
if opt.tag then
  copyFile(manifestPath, fmt("%smanifest%s-%s.lua", outDir, slug, opt.tag))
end

-- ---- report ----------------------------------------------------------------

print(fmt("escenas: %d renderizadas, %d fallidas", #results, #failures))
for _, p in ipairs(written) do print("  " .. p) end
print("  " .. manifestPath)

local seen, uniq = {}, {}
for _, wmsg in ipairs(allWarnings) do
  if not seen[wmsg] then seen[wmsg] = true; uniq[#uniq + 1] = wmsg end
end
if #uniq > 0 then
  print(fmt("\navisos de render: %d", #uniq))
  for _, wmsg in ipairs(uniq) do print("  ! " .. wmsg) end
else
  print("\navisos de render: ninguno")
end

local gaps = {}
for _, row in ipairs(cov) do
  if not row.covered and not row.nonVisual then gaps[#gaps + 1] = row.key end
end
if #gaps > 0 then
  print("\nopciones SIN COBERTURA: " .. table.concat(gaps, ", "))
else
  print("cobertura de opciones: todas las visuales tienen al menos una variante")
end

if opt.baseline then
  local ok, oldM = pcall(dofile, opt.baseline)
  if not ok or type(oldM) ~= "table" then
    io.stderr:write("gallery: no se pudo leer la baseline "
      .. tostring(opt.baseline) .. "\n")
    os.exit(2)
  end
  local d = diffManifests(oldM, manifest)
  print(fmt("\ndiff contra %s", opt.baseline))
  if #d.added == 0 and #d.removed == 0 and #d.changed == 0 then
    print("  sin cambios")
  else
    for _, n in ipairs(d.added) do print("  + escena nueva: " .. n) end
    for _, n in ipairs(d.removed) do print("  - escena eliminada: " .. n) end
    for _, c in ipairs(d.changed) do
      print("  ~ " .. c.name)
      for _, f in ipairs(c.fields) do print("      " .. f) end
    end
  end
end

if #failures > 0 then os.exit(1) end
if opt.strict and #uniq > 0 then os.exit(1) end
