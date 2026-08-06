-- GaugeV2 dev tooling: the scene catalogue.
--
-- ONE declarative list of everything worth looking at, shared by dev/shots.lua
-- (individual SVGs) and dev/gallery.lua (the composed contract sheet). Adding
-- a case is one table entry; nothing else has to change.
--
-- The catalogue is organised so that each section answers a question you can
-- actually fail: "does every colour mode read correctly at both ends", "does
-- every availability state say the right thing", "does every option visibly do
-- something". dev/gallery.lua cross-checks the catalogue against main.lua's
-- option declarations and reports which options no scene ever varies - so the
-- sheet cannot quietly stop covering an option someone added later.

local M = {}

-- ---------------------------------------------------------------- sources --

-- Simulated radio sources. `prec`/`unit` mirror what a real model carries;
-- min/max ids are the radio's own <name>- / <name>+ history siblings.
M.SOURCES = {
  RSSI  = { id = 3072, unit = 17, prec = 0, minId = 3073, maxId = 3074,
            sensor = 0 },
  RxBt  = { id = 3081, unit = 1,  prec = 2, minId = 3082, maxId = 3083,
            sensor = 1 },
  Cels  = { id = 3075, unit = 1,  prec = 2, sensor = 2 },
  T1    = { id = 3078, unit = 11, prec = 0, sensor = 3 },
  timer = { id = 200,  name = "timer1" },
  Thr   = { id = 100 },
}

-- Options that cannot be shown in a still frame. Listed explicitly so the
-- coverage report states WHY they are uncovered instead of nagging forever.
M.NON_VISUAL = {
  Alerts  = "sonido/haptic, no pintan nada",
  AlertSw = "compuerta de alertas",
  Delay   = "retardo de arranque de alertas",
  Vibrate = "haptic",
  ResetSw = "accion, no estado",
}

-- ---------------------------------------------------------------- harness --

local function registerRadio(mock)
  mock.reset()
  mock.sim.version = { "3.0.0", "sim", 3, 0, 0 }
  for name, s in pairs(M.SOURCES) do
    mock.addField(s.id, s.name or name, s.unit)
    if s.minId then mock.addField(s.minId, (s.name or name) .. "-", s.unit) end
    if s.maxId then mock.addField(s.maxId, (s.name or name) .. "+", s.unit) end
    if s.sensor then
      mock.sim.sensors[s.sensor] =
        { name = s.name or name, prec = s.prec, unit = s.unit }
    end
  end
end

-- Build one scene. Returns a context table with the widget and the facts the
-- gallery captions and the manifest record.
function M.build(mock, widgetDir, case)
  registerRadio(mock)
  local srcName = case.source or "RSSI"
  local src = M.SOURCES[srcName]
  if not src then error("scenes: unknown source " .. tostring(srcName)) end

  mock.setValue(src.id, case.value)
  if case.history then
    if src.minId then mock.setValue(src.minId, case.history[1]) end
    if src.maxId then mock.setValue(src.maxId, case.history[2]) end
  end

  local mod = dofile(widgetDir .. "main.lua")
  local o = { Source = case.noSource and 0 or src.id }
  for k, v in pairs(case.opts or {}) do o[k] = v end
  local opts = mock.makeOptions(mod.defs, o)

  local zone = { x = 0, y = 0, w = case.zone[1], h = case.zone[2] }
  local w = mod.create(zone, opts, widgetDir)
  mod.update(w, opts)
  for _ = 1, (case.frames or 30) do
    mock.advance(50)
    mod.refresh(w)
  end

  local ctx = { mock = mock, mod = mod, widget = w, opts = opts,
                srcId = src.id, zone = zone, case = case }
  if case.post then case.post(ctx) end
  return ctx
end

-- Everything the manifest needs to know about a rendered scene. Kept here (not
-- in gallery.lua) so any future tool records the SAME facts.
function M.facts(ctx)
  local w = ctx.widget
  local L, f = w.layout or {}, w.frame or {}
  local census, total = {}, 0
  for _, obj in ipairs(ctx.mock.objects()) do
    if obj.visible then
      census[obj.kind] = (census[obj.kind] or 0) + 1
      total = total + 1
    end
  end
  census.total = total
  return {
    mode = L.mode, orientation = L.orientation, style = L.style,
    sweep = L.sweep, radius = L.radius, valueFont = L.valueFont,
    showNeedle = L.showNeedle and true or false,
    showState = L.showState and true or false,
    showScale = L.showScale and true or false,
    availability = w.data and w.data.availability,
    state = w.data and w.data.state,
    colorKey = f.colorKey,
    value = f.valueStr, unit = w.unitText, name = w.nameText,
    chip = f.stateStr,
    displayValue = w.data and w.data.displayValue,
    cells = w.source and w.source.cells,
    scaleMin = w.config and w.config.min, scaleMax = w.config and w.config.max,
    warn = w.config and w.config.warn, crit = w.config and w.config.crit,
    objects = census,
  }
end

-- ------------------------------------------------------------------ scenes --

local function zoneMatrix()
  local out = {}
  local ZONES = {
    { 60, 60 }, { 80, 60 }, { 100, 100 }, { 128, 96 }, { 160, 160 },
    { 200, 160 }, { 200, 200 }, { 260, 220 }, { 300, 150 }, { 120, 220 },
    { 100, 260 }, { 480, 272 },
  }
  for _, z in ipairs(ZONES) do
    out[#out + 1] = {
      name = string.format("zone-%dx%d", z[1], z[2]),
      title = string.format("%d x %d", z[1], z[2]),
      zone = z, opts = { ShowMinMax = "Markers + text" },
      value = 78, history = { 31, 92 },
    }
  end
  return out
end

M.sections = {
  {
    key = "estado",
    title = "1 - Estado y disponibilidad",
    note = "El chip y el color son la unica senal de estado. Cada fila de"
      .. " availability debe decir algo distinto y correcto.",
    cases = {
      { name = "st-normal", title = "normal", zone = { 200, 160 }, value = 78 },
      { name = "st-warn", title = "warning", zone = { 200, 160 }, value = 45 },
      { name = "st-crit", title = "critical", zone = { 200, 160 }, value = 22 },
      { name = "st-stale", title = "stale", zone = { 220, 170 }, value = 78,
        history = { 31, 92 }, note = "sensor no current",
        post = function(c)
          c.mock.sim.current[c.srcId] = false
          c.mock.advance(50); c.mod.refresh(c.widget)
        end },
      { name = "st-nolink", title = "sin enlace", zone = { 220, 170 },
        value = 78, history = { 31, 92 }, note = "getRSSI() == 0",
        post = function(c)
          c.mock.setValue(c.srcId, nil); c.mock.sim.rssi = 0
          c.mock.advance(50); c.mod.refresh(c.widget)
        end },
      { name = "st-nodata", title = "sin dato", zone = { 220, 170 },
        value = 78, note = "valor nil, enlace vivo",
        post = function(c)
          c.mock.setValue(c.srcId, nil)
          c.mock.advance(50); c.mod.refresh(c.widget)
        end },
      { name = "st-nosource", title = "sin fuente", zone = { 220, 170 },
        value = 78, noSource = true },
    },
  },
  {
    key = "color",
    title = "2 - Modos de color",
    note = "Cada modo en su estado normal y en critico. Rail y Sections deben"
      .. " seguir mostrando las bandas de referencia en critico.",
    cases = (function()
      local out = {}
      for _, m in ipairs({ "Static", "Threshold", "Rail", "Gradient",
                           "Sections" }) do
        out[#out + 1] = { name = "color-" .. string.lower(m) .. "-ok",
          title = m .. " - normal", zone = { 200, 160 },
          opts = { ColorMode = m }, value = 78 }
        out[#out + 1] = { name = "color-" .. string.lower(m) .. "-crit",
          title = m .. " - critico", zone = { 200, 160 },
          opts = { ColorMode = m }, value = 22 }
      end
      return out
    end)(),
  },
  {
    key = "escala",
    title = "3 - Escalas y umbrales",
    note = "Rangos que no son 0..100. La escala DESCENDENTE (Min > Max) es un"
      .. " caso soportado a proposito por ranges/geometry.",
    cases = {
      { name = "sc-preset", title = "Auto (preset RSSI)", zone = { 220, 200 },
        opts = { Scale = "Auto", ShowMinMax = "Markers + text" }, value = 78,
        history = { 31, 92 } },
      { name = "sc-dbm", title = "Manual -120..0 dBm", zone = { 220, 220 },
        source = "Thr", opts = { Scale = "Manual", Min = -120, Max = 0 },
        value = -76 },
      { name = "sc-20000", title = "Manual 0..20000, 2 dec",
        zone = { 220, 220 }, source = "Thr",
        opts = { Scale = "Manual", Min = 0, Max = 20000, Precision = "2" },
        value = 15400 },
      { name = "sc-lowgood", title = "low-is-good (T1)", zone = { 220, 200 },
        source = "T1", opts = { Scale = "Auto" }, value = 95 },
      { name = "sc-descending", title = "descendente 100..0",
        zone = { 220, 200 }, source = "Thr",
        opts = { Scale = "Manual", Min = 100, Max = 0, Warn = 55, Crit = 35 },
        value = 40,
        note = "valor 40 deberia ser WARNING - ver Tanda 6 F-3" },
      { name = "sc-cliff", title = "warn == crit", zone = { 220, 200 },
        source = "Thr",
        opts = { Scale = "Manual", Min = 0, Max = 100, Warn = 50, Crit = 50,
                 ColorMode = "Gradient" }, value = 90 },
      { name = "sc-outofrange", title = "valor fuera de escala",
        zone = { 200, 160 }, source = "Thr",
        opts = { Scale = "Manual", Min = 0, Max = 100 }, value = 1500 },
    },
  },
  {
    key = "dial",
    title = "4 - Opciones del dial",
    note = "Cada opcion estructural, encendida y apagada, sobre la misma"
      .. " escena base.",
    cases = {
      { name = "op-sweep270", title = "Sweep 270", zone = { 200, 200 },
        opts = { Sweep = "270 deg" }, value = 55 },
      { name = "op-sweep180", title = "Sweep 180", zone = { 200, 200 },
        opts = { Sweep = "180 deg" }, value = 55 },
      { name = "op-sweep360", title = "Sweep 360", zone = { 200, 200 },
        opts = { Sweep = "360 deg" }, value = 55 },
      { name = "op-style-needle", title = "Style Needle", zone = { 200, 160 },
        opts = { Style = "Needle" }, value = 78 },
      { name = "op-style-arc", title = "Style Arc (sin aguja)",
        zone = { 200, 160 }, opts = { Style = "Arc" }, value = 78 },
      { name = "op-chip-on", title = "State chip ON", zone = { 200, 160 },
        opts = { ColorMode = "Rail", ShowChip = true }, value = 22 },
      { name = "op-chip-off", title = "State chip OFF", zone = { 200, 160 },
        opts = { ColorMode = "Rail", ShowChip = false }, value = 22 },
      { name = "op-mm-off", title = "Min/max Off", zone = { 220, 200 },
        opts = { ShowMinMax = "Off" }, value = 78, history = { 31, 92 },
        note = "el ghost no aparece - ver Tanda 6 F-8" },
      { name = "op-mm-mark", title = "Min/max Markers", zone = { 220, 200 },
        opts = { ShowMinMax = "Markers" }, value = 78, history = { 31, 92 } },
      { name = "op-mm-text", title = "Min/max + texto", zone = { 220, 200 },
        opts = { ShowMinMax = "Markers + text" }, value = 78,
        history = { 31, 92 } },
    },
  },
  {
    key = "aguja",
    title = "5 - Aguja y amortiguacion",
    note = "La aguja de 3 tramos en los dos topes y en el centro, y el efecto"
      .. " del damping 3 frames despues de un escalon.",
    cases = {
      { name = "ne-pos0", title = "tope inicial", zone = { 200, 160 },
        opts = { ColorMode = "Rail" }, value = 0 },
      { name = "ne-pos50", title = "centro", zone = { 200, 160 },
        opts = { ColorMode = "Rail" }, value = 50 },
      { name = "ne-pos100", title = "tope final", zone = { 200, 160 },
        opts = { ColorMode = "Rail" }, value = 100 },
      { name = "ne-damp0", title = "Damping 0 (3 frames)", zone = { 200, 160 },
        opts = { Damping = 0 }, value = 10, frames = 30,
        post = function(c)
          c.mock.setValue(c.srcId, 90)
          for _ = 1, 3 do c.mock.advance(50); c.mod.refresh(c.widget) end
        end },
      { name = "ne-damp9", title = "Damping 9 (3 frames)", zone = { 200, 160 },
        opts = { Damping = 9 }, value = 10, frames = 30,
        post = function(c)
          c.mock.setValue(c.srcId, 90)
          for _ = 1, 3 do c.mock.advance(50); c.mod.refresh(c.widget) end
        end },
    },
  },
  {
    key = "texto",
    title = "6 - Valor, unidad y nombre",
    note = "Tipografia auto-ajustada, decimales, y las cadenas que mas"
      .. " facilmente desbordan su caja.",
    cases = {
      { name = "tx-prec0", title = "Decimales 0", zone = { 200, 160 },
        source = "RxBt", opts = { Precision = "0", Scale = "Manual",
          Min = 0, Max = 20 }, value = 16.62 },
      { name = "tx-prec1", title = "Decimales 1", zone = { 200, 160 },
        source = "RxBt", opts = { Precision = "1", Scale = "Manual",
          Min = 0, Max = 20 }, value = 16.62 },
      { name = "tx-prec2", title = "Decimales 2", zone = { 200, 160 },
        source = "RxBt", opts = { Precision = "2", Scale = "Manual",
          Min = 0, Max = 20 }, value = 16.62 },
      { name = "tx-override", title = "Name + Unit override",
        zone = { 220, 200 }, opts = { Label = "PACK", Suffix = "volt" },
        value = 78 },
      { name = "tx-timer", title = "timer descontado", zone = { 200, 160 },
        source = "timer", value = -3725 },
      { name = "tx-scalelabels", title = "etiquetas de escala",
        zone = { 240, 240 }, opts = { ShowMinMax = "Markers + text" },
        value = 78, history = { 31, 92 } },
    },
  },
  {
    key = "bateria",
    title = "7 - Bateria y celdas",
    note = "Agregacion de la tabla CELLS y porcentaje de carga. Lowest y"
      .. " Average con Battery ON estan rotos - ver Tanda 6 F-2.",
    cases = {
      { name = "ba-cels-low", title = "Cels - Lowest (V)", zone = { 200, 160 },
        source = "Cels", opts = { Cells = "Lowest" },
        value = { 3.85, 3.84, 3.86, 3.85 } },
      { name = "ba-cels-tot", title = "Cels - Total (V)", zone = { 200, 160 },
        source = "Cels", opts = { Cells = "Total" },
        value = { 3.85, 3.84, 3.86, 3.85 } },
      { name = "ba-cels-avg", title = "Cels - Average (V)",
        zone = { 200, 160 }, source = "Cels", opts = { Cells = "Average" },
        value = { 3.85, 3.84, 3.86, 3.85 } },
      { name = "ba-pct-low", title = "Li-Po % / Lowest", zone = { 200, 160 },
        source = "Cels", opts = { Battery = "Li-Po", Cells = "Lowest" },
        value = { 3.85, 3.84, 3.86, 3.85 },
        note = "deberia ser ~55 % - F-2" },
      { name = "ba-pct-tot", title = "Li-Po % / Total", zone = { 200, 160 },
        source = "Cels", opts = { Battery = "Li-Po", Cells = "Total" },
        value = { 3.85, 3.84, 3.86, 3.85 } },
      { name = "ba-liion", title = "Li-Ion % / Total", zone = { 200, 160 },
        source = "Cels", opts = { Battery = "Li-Ion", Cells = "Total" },
        value = { 3.85, 3.84, 3.86, 3.85 } },
      { name = "ba-rxbt", title = "RxBt 4S latcheado", zone = { 220, 200 },
        source = "RxBt", opts = { ColorMode = "Sections" }, value = 16.4,
        history = { 14.8, 16.8 } },
    },
  },
  {
    key = "acento",
    title = "8 - Color de acento",
    note = "El acento sustituye el verde del estado normal. Ojo: aqui cada"
      .. " escena es una construccion nueva; cambiarlo EN CALIENTE no repinta"
      .. " nada - Tanda 6 F-5.",
    cases = {
      { name = "ac-default", title = "por defecto (verde)",
        zone = { 200, 160 }, opts = { ColorMode = "Sections" }, value = 78 },
      { name = "ac-focus", title = "acento azul", zone = { 200, 160 },
        opts = { ColorMode = "Sections", Accent = "@COLOR_THEME_FOCUS" },
        value = 78 },
      { name = "ac-edit", title = "acento naranja", zone = { 200, 160 },
        opts = { ColorMode = "Sections", Accent = "@COLOR_THEME_EDIT" },
        value = 78 },
    },
  },
  {
    key = "barra",
    title = "9 - Estilo barra",
    note = "La barra debe senalar el estado igual que el dial: mismo chip,"
      .. " mismo pulso, mismas marcas de umbral.",
    cases = {
      { name = "br-normal", title = "normal", zone = { 300, 70 },
        opts = { Style = "Bar" }, value = 78 },
      { name = "br-warn", title = "warning", zone = { 300, 70 },
        opts = { Style = "Bar" }, value = 45 },
      { name = "br-crit", title = "critico", zone = { 300, 70 },
        opts = { Style = "Bar" }, value = 22 },
      { name = "br-narrow", title = "300 x 44", zone = { 300, 44 },
        opts = { Style = "Bar" }, value = 22 },
      { name = "br-short", title = "160 x 44 (sin chip)", zone = { 160, 44 },
        opts = { Style = "Bar" }, value = 22 },
      { name = "br-lowgood", title = "low-is-good (T1)", zone = { 300, 70 },
        source = "T1", opts = { Style = "Bar" }, value = 95 },
      { name = "br-nochip", title = "chip desactivado", zone = { 300, 70 },
        opts = { Style = "Bar", ShowChip = false }, value = 22 },
      { name = "br-auto", title = "Auto -> barra (ratio > 2.6)",
        zone = { 300, 60 }, opts = { Style = "Auto" }, value = 78 },
    },
  },
  {
    key = "zonas",
    title = "10 - Matriz de zonas",
    note = "La misma configuracion en cada tamano de hueco que un layout de"
      .. " EdgeTX puede dar. Ningun texto puede desbordar ni cruzar el aro.",
    cases = zoneMatrix(),
  },
}

-- Accent options are declared as COLOR and reach Lua as an integer, but the
-- catalogue wants to name theme roles readably. Resolve "@NAME" late, once the
-- firmware constants exist.
function M.resolveOpts(opts)
  if not opts then return nil end
  local out = {}
  for k, v in pairs(opts) do
    if type(v) == "string" and string.sub(v, 1, 1) == "@" then
      out[k] = _G[string.sub(v, 2)]
    else
      out[k] = v
    end
  end
  return out
end

-- Flat list of every case, with its section attached.
function M.allCases()
  local out = {}
  for _, sec in ipairs(M.sections) do
    for _, c in ipairs(sec.cases) do
      c.section = sec.key
      c.sectionTitle = sec.title
      out[#out + 1] = c
    end
  end
  return out
end

return M
