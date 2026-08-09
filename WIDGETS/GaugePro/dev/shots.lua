-- GaugePro render shots: un SVG independiente por escena.
--
--   lua5.3 dev/shots.lua <widget-dir> [out-dir] [opciones]
--     --only PATRON   filtra por nombre de escena o clave de seccion
--     --theme T       dark | light            (por defecto dark)
--     --list          imprime el catalogo (con sus alias) y sale
--
-- Usa esto cuando quieras UNA imagen para mirarla de cerca (o rasterizarla).
-- Para la hoja completa con pies, metadatos y cobertura de opciones, usa
-- dev/gallery.lua - las dos herramientas leen el MISMO catalogo
-- (dev/scenes.lua) y el MISMO emisor (dev/svgkit.lua), asi que no pueden
-- discrepar sobre lo que dibujan.

local args = { ... }
local widgetDir, outDir
local only, theme, listOnly = nil, "stock", false
do
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--only" then i = i + 1; only = args[i]
    elseif a == "--theme" then i = i + 1; theme = args[i]
    elseif a == "--list" then listOnly = true
    elseif string.sub(a, 1, 2) == "--" then
      io.stderr:write("shots: opcion desconocida " .. a .. "\n"); os.exit(2)
    elseif not widgetDir then widgetDir = a
    elseif not outDir then outDir = a end
    i = i + 1
  end
end
widgetDir = widgetDir or "./"
if string.sub(widgetDir, -1) ~= "/" then widgetDir = widgetDir .. "/" end
outDir = outDir or (widgetDir .. "dev/shots/")
if string.sub(outDir, -1) ~= "/" then outDir = outDir .. "/" end

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)
local svgkit = dofile(widgetDir .. "dev/svgkit.lua")
local scenes = dofile(widgetDir .. "dev/scenes.lua")

local cases = {}
for _, c in ipairs(scenes.allCases()) do
  if not only or string.find(c.name, only) or string.find(c.section, only) then
    cases[#cases + 1] = c
  end
end

if listOnly then
  for _, c in ipairs(cases) do
    print(string.format("%-18s %-30s %dx%d%s", c.name, c.title or "",
      c.zone[1], c.zone[2], c.alias and ("  (alias " .. c.alias .. ")") or ""))
  end
  os.exit(0)
end

-- Escenas pequenas ampliadas: un dial de 60 px hay que poder mirarlo.
local function shotScale(w)
  if w < 110 then return 2.2 end
  if w < 210 then return 1.5 end
  return 1.15
end

local function write(path, text)
  local f, err = io.open(path, "w")
  if not f then
    -- A bare assert here produced a stack traceback for the ordinary mistake
    -- of naming an output directory that does not exist yet - Lua cannot
    -- create one portably, so say so plainly instead.
    io.stderr:write("shots: cannot write " .. path .. "\n  " .. tostring(err)
      .. "\n  (create the directory first - this tool does not)\n")
    os.exit(2)
  end
  f:write(text)
  f:close()
end

-- Let the widget SEE the theme it is being rendered in: theme.labelOn reads
-- the theme's text roles through lcd.getColor to pick the badge ink, so the
-- mock's colour table has to be the palette's before any scene is built (see
-- dev/gallery.lua for the measured consequence of not doing this).
mock.setThemeColors(svgkit.themeColors(theme))

local written, warned, failed = 0, {}, {}
-- Every file this run produced. dev/shots/ is gitignored and accumulates
-- renders from older versions of the catalogue, which are indistinguishable
-- from current ones once they are sitting side by side in a directory - and
-- the design-review notes cite some of those names. The index makes "was
-- this picture produced by the code as it stands?" answerable.
local index = {}
for _, case in ipairs(cases) do
  local ok, ctx = pcall(scenes.build, mock, widgetDir, case)
  if not ok then
    failed[#failed + 1] = case.name .. ": " .. tostring(ctx)
  else
    local cv = svgkit.newCanvas(theme)
    local objs = {}
    for _, o in ipairs(mock.objects()) do
      if o.visible then objs[#objs + 1] = o end
    end
    local _, warns = cv:scene(objs, ctx.zone, 0, 0, 1, case.name)
    local svg = cv:document(ctx.zone, shotScale(case.zone[1]))
    write(outDir .. case.name .. ".svg", svg)
    index[#index + 1] = case.name .. ".svg"
    written = written + 1
    -- Nombre historico: dev/design-review-tanda5.md cita estos ficheros.
    if case.alias then
      write(outDir .. case.alias .. ".svg", svg)
      index[#index + 1] = case.alias .. ".svg  (alias de " .. case.name .. ")"
      written = written + 1
    end
    for _, w in ipairs(warns) do warned[#warned + 1] = w end
  end
end

if not only then
  table.sort(index)
  write(outDir .. "_index.txt",
    "-- Ficheros escritos por dev/shots.lua (tema " .. theme .. ").\n"
    .. "-- Cualquier .svg de este directorio que NO este aqui sobra: es de\n"
    .. "-- una version anterior del catalogo (dev/shots/ esta gitignored).\n"
    .. table.concat(index, "\n") .. "\n")
end

print(string.format("escritos %d SVG (tema %s) en %s", written, theme, outDir))
if not only then print("  indice: " .. outDir .. "_index.txt") end
local seen = {}
for _, w in ipairs(warned) do
  if not seen[w] then seen[w] = true; print("AVISO: " .. w) end
end
for _, f in ipairs(failed) do io.stderr:write("FALLO: " .. f .. "\n") end
if #failed > 0 then os.exit(1) end
