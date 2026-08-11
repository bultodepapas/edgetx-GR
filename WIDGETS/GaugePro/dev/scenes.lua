-- GaugePro dev tooling: the scene catalogue.
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
--
-- =========================================================================
-- ADDING A SCENE
-- =========================================================================
--
-- Append one table to the `cases` list of the right section in M.sections:
--
--   { name    = "ba-pct-low",       -- REQUIRED, unique. Used as the SVG file
--                                   -- name, the manifest key and the label in
--                                   -- render warnings. Keep the section's
--                                   -- prefix (st- / color- / sc- / op- / ...).
--     title   = "Li-Po % / Lowest", -- caption heading; falls back to `name`
--     zone    = { 200, 160 },       -- REQUIRED, { width, height } in px
--     source  = "Cels",             -- key into M.SOURCES below; default "RSSI"
--     opts    = { Battery = "Li-Po", Cells = "Lowest" },
--                                   -- widget options in READABLE form: CHOICE
--                                   -- by label, BOOL as true/false, numbers as
--                                   -- numbers. mock.makeOptions() converts to
--                                   -- the integer wire format. A colour may be
--                                   -- written "@COLOR_THEME_FOCUS" and is
--                                   -- resolved late by M.resolveOpts().
--     value   = { 3.85, 3.84 },     -- what the source reads. A TABLE simulates
--                                   -- a CELLS sensor (one entry per cell).
--     history = { 31, 92 },         -- optional; only lands if the source
--                                   -- declares minId/maxId siblings
--     frames  = 30,                 -- refresh() calls before capture (def. 30).
--                                   -- Lower it to catch the needle mid-glide.
--     noSource = true,              -- optional; forces Source = 0
--     note    = "deberia ser ~55 %",-- optional caption line, drawn in accent
--     alias   = "mode-Rail-crit",   -- optional extra file name for shots.lua,
--                                   -- for scenes older documents cite
--     post    = function(ctx) ... end,
--                                   -- optional: mutate the radio AFTER the
--                                   -- initial frames, then refresh again.
--                                   -- ctx = { mock, mod, widget, opts, srcId,
--                                   --         zone, case }. This is how the
--                                   --   stale / no-link / damping scenes work.
--   }
--
-- `section` and `sectionTitle` are injected by M.allCases(); do not set them.
--
-- A new SOURCE goes in M.SOURCES: { id, unit, prec, minId, maxId, sensor }.
-- `unit` is the TelemetryUnit enum (telemetry.lua UNIT_NAMES), `sensor` is the
-- 0-based index model.getSensor() reports - needed for precision lookup and
-- for model.resetSensor(). Omit `unit` for a non-telemetry source (a stick,
-- a timer): telemetry.lua keys isTelemetry off its presence.
--
-- A new OPTION in main.lua needs a scene here, or gallery.lua's coverage panel
-- will list it as SIN COBERTURA. If it genuinely cannot be seen in a still
-- frame, add it to M.NON_VISUAL below with the reason instead.
--
-- =========================================================================
-- TRAPS (all of these have bitten; they are properties of the harness)
-- =========================================================================
--
--  * tests/mock_env.lua strips the string metatable on purpose, because EdgeTX
--    builds without LUA_ENABLE_STRLIB_MT. So `("%d"):format(n)` raises here
--    exactly as it would on the radio - write string.format(...) instead.
--  * The mock is GLOBAL state: mock.reset() wipes the object list, so a scene's
--    objects must be snapshotted before the next M.build() call. gallery.lua
--    captures each scene immediately; anything new must do the same.
--  * `value` reaches getSourceValue() untouched, so a nil value is a legitimate
--    scene (no data) - set it inside `post`, not as the field, or the initial
--    frames render nothing to look at.

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
  Ail   = { id = 101 },
  CH1   = { id = 102, name = "CH1" },
}

-- Options that cannot be shown in a still frame. Listed explicitly so the
-- coverage report states WHY they are uncovered instead of nagging forever.
M.NON_VISUAL = {
  Alerts  = "sonido/haptic, no pintan nada",
  AlertSw = "compuerta de alertas",
  Delay   = "retardo de arranque de alertas",
  Vibrate = "haptic",
  ResetSw = "accion, no estado",
  Motion  = "perfil temporal; se verifica con secuencias, no en un fotograma",
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

local function loadFront(widgetDir, folder)
  local path = widgetDir .. "../../WIDGETS/" .. folder .. "/main.lua"
  local chunk, err = loadfile(path, "bt", _ENV or _G)
  if not chunk then error("scenes: cannot load " .. path .. ": " .. tostring(err)) end
  return chunk({ corePath = widgetDir })
end

function M.frontContracts(widgetDir)
  return {
    dial = loadFront(widgetDir, "GaugeDialPro"),
    bar = loadFront(widgetDir, "GaugeBarPro"),
  }
end

local function splitCase(widgetDir, case)
  local fronts = M.frontContracts(widgetDir)
  local opts = M.resolveOpts(case.opts) or {}
  local style = opts.Style
  opts.Style = nil

  local dialKeys, barKeys = {}, {}
  for _, d in ipairs(fronts.dial.defs) do dialKeys[d.key] = true end
  for _, d in ipairs(fronts.bar.defs) do barKeys[d.key] = true end
  local hasDial, hasBar = false, false
  for key in pairs(opts) do
    if dialKeys[key] and not barKeys[key] then hasDial = true end
    if barKeys[key] and not dialKeys[key] then hasBar = true end
  end
  if hasDial and hasBar then
    error("scenes: " .. case.name .. " mixes DialPro and BarPro options")
  end

  local family
  if style == "Bar" or hasBar then
    family = "bar"
  elseif style == "Needle" or style == "Arc" or hasDial then
    family = "dial"
  elseif style == nil or style == "Auto" then
    family = (case.zone[1] / math.max(case.zone[2], 1) > 2.6) and "bar" or "dial"
  else
    error("scenes: " .. case.name .. " has unknown Style " .. tostring(style))
  end
  if family == "dial" and
     (style == "Auto" or style == "Needle" or style == "Arc") then
    opts.DialStyle = style
  end

  local allowed = (family == "dial") and dialKeys or barKeys
  for key in pairs(opts) do
    if not allowed[key] then
      error("scenes: " .. case.name .. " option " .. key
        .. " is not valid for " .. family)
    end
  end
  return fronts[family], family, opts
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

  local mod, family, authored = splitCase(widgetDir, case)
  local o = { Source = case.noSource and 0 or src.id }
  for k, v in pairs(authored) do o[k] = v end
  local opts = mock.makeOptions(mod.defs, o)

  local zone = { x = 0, y = 0, w = case.zone[1], h = case.zone[2] }
  local w = mod.create(zone, opts, widgetDir)
  mod.update(w, opts)
  for _ = 1, (case.frames or 30) do
    mock.advance(50)
    mod.refresh(w)
  end

  local ctx = { mock = mock, mod = mod, widget = w, opts = opts,
                family = family, frontend = mod.name,
                srcId = src.id, zone = zone, case = case }
  if case.post then case.post(ctx) end

  -- F6: settle the critical pulse on its CREST before anyone renders this.
  --
  -- The pulse flips every 500 ms and a scene advances exactly 500 ms per
  -- frame, so the phase a render caught was decided by the PARITY of the
  -- frame count - and `post` adds frames to some scenes and not others. Two
  -- catalogue images of the same critical state therefore came out visibly
  -- different reds, one at full opacity and one at the trough's 150, and
  -- nothing in the picture said which was which.
  --
  -- The crest is the right choice for a still: it is the state the eye reads
  -- as "the" colour. Reached by running ordinary frames at the catalogue's own
  -- 50 ms cadence - not by jumping the clock 500 ms, which would also age the
  -- staleness and history timers this scene may be posing with. The pulse gate
  -- is 50 ticks and a frame is 5, so eleven frames always cross it.
  for _ = 1, 11 do
    if not (w.frame and w.frame.pulse) then break end
    mock.advance(50)
    mod.refresh(w)
  end
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
    family = ctx.family, frontend = ctx.frontend,
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
    barFamily = w.barVisual and w.barVisual.profile.family,
    barFace = w.barFaceName,
    barFaceVariant = w.barVisual and w.barVisual.faceVariant,
    barSegments = w.barVisual and w.barVisual.renderedSegments,
    barPreset = w.barVisual and w.barVisual.preset,
    barDirection = w.barVisual and w.barVisual.direction,
    barOrigin = w.barVisual and w.barVisual.origin,
    barThickness = w.barVisual and w.barVisual.thickness,
    barEnds = w.barVisual and w.barVisual.ends,
    barSurface = w.barVisual and w.barVisual.surface,
    barPalette = w.barPalette and w.barPalette.mode,
    barAssist = w.barPalette and w.barPalette.assist,
    barMotion = w.barVisual and w.barVisual.motion,
    barHead = w.barVisual and w.barVisual.head,
    barMarks = w.barVisual and w.barVisual.marks,
    barValuePosition = w.barVisual and w.barVisual.valuePos,
    barLabelPosition = w.barVisual and w.barVisual.labelPos,
    barDowngrades = w.barVisual and w.barVisual.downgrades,
    gradientSlices = w.ui and w.ui.gradientSlices and #w.ui.gradientSlices,
    barBody = L.barOuter and { L.barOuter.w, L.barOuter.h } or nil,
    barAxisOrientation = L.axis and L.axis.orientation,
    barAxisGrowth = L.axis and L.axis.growth,
    barZeroPosition = L.axis and L.axis.zeroT,
    barZeroInside = L.axis and L.axis.zeroInside,
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

-- Phase 4 is deliberately a matrix, not a beauty shot. Every production
-- segmented face must keep a distinct reading model in every colour mode.
-- Extra edge cases then exercise compact degradation, authored density and
-- source-aware preset selection.
local function phase4FaceMatrix()
  local out = {}
  local faces = { "Blocks", "Hex", "Ticks", "Steps" }
  local modes = { "Static", "Threshold", "Rail", "Gradient", "Sections" }
  for _, face in ipairs(faces) do
    for _, mode in ipairs(modes) do
      out[#out + 1] = {
        name = "f4-" .. string.lower(face) .. "-" .. string.lower(mode),
        title = face .. " / " .. mode,
        zone = { 360, 100 }, source = "Thr", opts = {
          Style = "Bar", BarFace = face, ColorMode = mode,
          Scale = "Manual", Min = 0, Max = 100, Warn = 55, Crit = 35,
          Damping = 0,
        }, value = 40,
      }
    end
  end

  local edges = {
    { name = "f4-blocks-soft", title = "Blocks / soft / 6 wide",
      zone = { 300, 86 }, opts = {
        Style = "Bar", BarFace = "Blocks", BarEnds = "Round",
        Segments = "6", SegGap = "Wide",
      }, value = 67 },
    { name = "f4-blocks-dense", title = "Blocks / 24 / partial cell",
      zone = { 480, 110 }, source = "Thr", opts = {
        Style = "Bar", BarFace = "Blocks", BarEnds = "Square",
        Segments = "24", SegGap = "Tight", Scale = "Manual",
        Min = 0, Max = 100, Damping = 0,
      }, value = 52 },
    { name = "f4-hex-rich", title = "True hex / authored seams",
      zone = { 420, 110 }, opts = {
        Style = "Bar", BarFace = "Hex", Segments = "10",
        SegGap = "Normal", Surface = "Theme panel",
      }, value = 73 },
    { name = "f4-hex-compact", title = "Hex / honest compact fallback",
      zone = { 160, 44 }, opts = {
        Style = "Bar", BarFace = "Hex", Segments = "10",
        SegGap = "Tight",
      }, value = 73 },
    { name = "f4-ticks-compact", title = "Ticks / compact 8",
      zone = { 160, 44 }, opts = {
        Style = "Bar", BarFace = "Ticks", Segments = "8",
      }, value = 45 },
    { name = "f4-ticks-dense", title = "Ticks / 24 / exact thresholds",
      zone = { 480, 110 }, opts = {
        Style = "Bar", BarFace = "Ticks", Segments = "24",
        SegGap = "Tight", ColorMode = "Threshold",
      }, value = 45 },
    { name = "f4-steps-compact", title = "Steps / compact 5",
      zone = { 160, 52 }, opts = {
        Style = "Bar", BarFace = "Steps", Segments = "6",
      }, value = 45 },
    { name = "f4-steps-signal", title = "Steps / RSSI glance pattern",
      zone = { 360, 100 }, opts = {
        Style = "Bar", BarFace = "Steps", Segments = "10",
        SegGap = "Normal", ColorMode = "Sections",
      }, value = 78 },
    { name = "f4-preset-hex", title = "Preset Hex Tech",
      zone = { 360, 100 }, opts = {
        Style = "Bar", BarPreset = "Hex",
      }, value = 78 },
    { name = "f4-preset-blocks", title = "Preset Blocks Soft",
      zone = { 360, 100 }, opts = {
        Style = "Bar", BarPreset = "Blocks",
      }, value = 45 },
    { name = "f4-preset-ticks", title = "Preset Signal Ticks",
      zone = { 360, 100 }, opts = {
        Style = "Bar", BarPreset = "Ticks",
      }, value = 78 },
    { name = "f4-auto-rssi", title = "Auto Source / RSSI -> Steps",
      zone = { 360, 100 }, opts = {
        Style = "Bar", BarPreset = "Auto",
      }, value = 78 },
  }
  for _, c in ipairs(edges) do out[#out + 1] = c end
  return out
end

-- Phase 5 is an axis-and-semantics matrix, not a handful of hero images.
-- It proves every retained reading model vertically, every signed face on both
-- sides of a numeric zero, Dual Rail's asymmetric/descending truth, and each
-- presentation control as a materially distinct authored result.
local function phase5AxisMatrix()
  local out = {}
  local faces = { "Continuous", "Blocks", "Hex", "Ticks", "Steps" }
  local modes = { "Static", "Threshold", "Rail", "Gradient", "Sections" }

  for _, face in ipairs(faces) do
    for _, mode in ipairs(modes) do
      out[#out + 1] = {
        name = "f5-v-" .. string.lower(face) .. "-" .. string.lower(mode),
        title = "Vertical " .. face .. " / " .. mode,
        zone = { 120, 300 }, source = "Thr", opts = {
          Style = "Bar", BarDir = "Vertical", BarFace = face,
          ColorMode = mode, Scale = "Manual", Min = 0, Max = 100,
          Warn = 55, Crit = 35, Damping = 0,
        }, value = 45,
      }
    end
  end

  for _, face in ipairs(faces) do
    for _, value in ipairs({ -65, 65 }) do
      local side = (value < 0) and "negative" or "positive"
      out[#out + 1] = {
        name = "f5-zero-h-" .. string.lower(face) .. "-" .. side,
        title = face .. " / zero / " .. side,
        zone = { 420, 110 }, source = "Ail", opts = {
          Style = "Bar", BarDir = "Horizontal", BarFace = face,
          BarOrigin = "Zero", ColorMode = (face == "Continuous")
            and "Gradient" or "Sections",
          Scale = "Manual", Min = -100, Max = 100,
          Warn = -30, Crit = -60, Damping = 0,
        }, value = value,
      }
    end
    out[#out + 1] = {
      name = "f5-zero-v-" .. string.lower(face),
      title = "Vertical " .. face .. " / zero",
      zone = { 120, 300 }, source = "Ail", opts = {
        Style = "Bar", BarDir = "Vertical", BarFace = face,
        BarOrigin = "Zero", ColorMode = (face == "Continuous")
          and "Gradient" or "Sections",
        Scale = "Manual", Min = -100, Max = 100,
        Warn = -30, Crit = -60, Damping = 0,
      }, value = -65,
    }
  end

  local duals = {
    { "f5-dual-h-neg", "Dual Rail H / negative", { 420, 110 },
      "Horizontal", -20, -30, 100 },
    { "f5-dual-h-zero", "Dual Rail H / zero", { 420, 110 },
      "Horizontal", 0, -30, 100 },
    { "f5-dual-h-pos", "Dual Rail H / positive", { 420, 110 },
      "Horizontal", 80, -30, 100 },
    { "f5-dual-v-neg", "Dual Rail V / negative", { 120, 300 },
      "Vertical", -65, -100, 100 },
    { "f5-dual-v-zero", "Dual Rail V / zero", { 120, 300 },
      "Vertical", 0, -100, 100 },
    { "f5-dual-v-pos", "Dual Rail V / positive", { 120, 300 },
      "Vertical", 65, -100, 100 },
  }
  for _, d in ipairs(duals) do
    out[#out + 1] = {
      name = d[1], title = d[2], zone = d[3], source = "Ail", opts = {
        Style = "Bar", BarDir = d[4], BarFace = "Dual rail",
        BarOrigin = "Zero", Scale = "Manual", Min = d[6], Max = d[7],
        Damping = 0,
      }, value = d[5],
    }
  end
  out[#out + 1] = {
    name = "f5-dual-custom-neg", title = "Dual / purple-yellow / negative",
    zone = { 420, 110 }, source = "Ail", opts = {
      Style = "Bar", BarFace = "Dual rail", BarOrigin = "Zero",
      Palette = "Custom 2", Accent = lcd.RGB(0xf0, 0xd8, 0x18),
      CritClr = lcd.RGB(0x88, 0x28, 0xd8), Scale = "Manual",
      Min = -30, Max = 100, Damping = 0,
    }, value = -20,
  }
  out[#out + 1] = {
    name = "f5-dual-custom-pos", title = "Dual / purple-yellow / positive",
    zone = { 420, 110 }, source = "Ail", opts = {
      Style = "Bar", BarFace = "Dual rail", BarOrigin = "Zero",
      Palette = "Custom 2", Accent = lcd.RGB(0xf0, 0xd8, 0x18),
      CritClr = lcd.RGB(0x88, 0x28, 0xd8), Scale = "Manual",
      Min = -30, Max = 100, Damping = 0,
    }, value = 80,
  }
  out[#out + 1] = {
    name = "f5-dual-desc", title = "Dual / descending +100..-30",
    zone = { 420, 110 }, source = "Ail", opts = {
      Style = "Bar", BarFace = "Dual rail", BarOrigin = "Zero",
      Scale = "Manual", Min = 100, Max = -30, Damping = 0,
    }, value = -20,
  }
  out[#out + 1] = {
    name = "f5-dual-fallback", title = "Dual / one-sided honest fallback",
    zone = { 420, 110 }, source = "Thr", opts = {
      Style = "Bar", BarFace = "Dual rail", Scale = "Manual",
      Min = 0, Max = 100, Damping = 0,
    }, value = 65,
    note = "sin cero interior: Continuous y downgrade explicito",
  }

  for _, head in ipairs({ "None", "Cap", "Dot", "Line", "Needle" }) do
    out[#out + 1] = {
      name = "f5-head-" .. string.lower(head), title = "Head / " .. head,
      zone = { 360, 100 }, opts = {
        Style = "Bar", BarHead = head, BarSize = "Thick", Damping = 0,
      }, value = 67,
    }
  end
  for _, marks in ipairs({ "Off", "Thresholds", "Ends", "Full" }) do
    out[#out + 1] = {
      name = "f5-marks-" .. string.lower(marks),
      title = "Scale marks / " .. marks, zone = { 360, 100 }, opts = {
        Style = "Bar", ScaleMarks = marks, ColorMode = "Static", Damping = 0,
      }, value = 67,
    }
  end

  for _, position in ipairs({ "Above", "Inside", "End", "Off" }) do
    out[#out + 1] = {
      name = "f5-value-v-" .. string.lower(position),
      title = "Vertical value / " .. position, zone = { 120, 300 }, opts = {
        Style = "Bar", BarDir = "Vertical", ValuePos = position,
        BarFace = "Ticks", ScaleMarks = "Full", Damping = 0,
      }, value = 67,
    }
  end
  for _, position in ipairs({ "Above", "Below", "Inside", "Off" }) do
    out[#out + 1] = {
      name = "f5-label-v-" .. string.lower(position),
      title = "Vertical name / " .. position, zone = { 120, 300 }, opts = {
        Style = "Bar", BarDir = "Vertical", LabelPos = position,
        BarFace = "Steps", Label = "AILERON", Damping = 0,
      }, value = 67,
    }
  end

  local autoSources = {
    { "f5-auto-ail", "Auto Source / Ail -> RC Center", "Ail", -65, -100, 100 },
    { "f5-auto-ch1", "Auto Source / CH1 -> RC Center", "CH1", 65, -100, 100 },
    { "f5-auto-thr", "Auto Source / Thr stays throttle", "Thr", 65, -100, 100 },
    { "f5-auto-ail-one", "Auto Ail / one-sided fallback", "Ail", 65, 0, 100 },
  }
  for _, a in ipairs(autoSources) do
    out[#out + 1] = {
      name = a[1], title = a[2], zone = { 420, 110 }, source = a[3], opts = {
        Style = "Bar", BarPreset = "Auto", Scale = "Manual",
        Min = a[5], Max = a[6], Damping = 0,
      }, value = a[4],
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
        -- `alias`: nombre historico con el que dev/shots.lua venia escribiendo
        -- esta escena. dev/design-review-tanda5.md cita esos ficheros, asi que
        -- se siguen emitiendo ademas del nombre nuevo.
        out[#out + 1] = { name = "color-" .. string.lower(m) .. "-ok",
          title = m .. " - normal", zone = { 200, 160 },
          alias = (m == "Rail") and "mode-Rail-normal" or nil,
          opts = { ColorMode = m }, value = 78 }
        out[#out + 1] = { name = "color-" .. string.lower(m) .. "-crit",
          title = m .. " - critico", zone = { 200, 160 },
          alias = (m == "Rail") and "mode-Rail-crit" or nil,
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
      { name = "sc-lowgood", title = "low-is-good (preset T1)",
        zone = { 220, 200 }, source = "T1", opts = { Scale = "Auto" },
        value = 95 },
      -- El preset de T1 trae highIsGood=false por su cuenta; estos dos fijan
      -- la OPCION explicitamente sobre la misma escala, que es lo unico que
      -- verifica de verdad el interruptor (lo pidio el informe de cobertura).
      { name = "sc-highgood-on", title = "High is good = On",
        zone = { 220, 200 }, source = "Thr",
        opts = { Scale = "Manual", Min = 0, Max = 100, Warn = 55, Crit = 35,
                 HighGood = true, ColorMode = "Sections" }, value = 45 },
      { name = "sc-highgood-off", title = "High is good = Off",
        zone = { 220, 200 }, source = "Thr",
        opts = { Scale = "Manual", Min = 0, Max = 100, Warn = 55, Crit = 35,
                 HighGood = false, ColorMode = "Sections" }, value = 45 },
      { name = "sc-descending", title = "descendente 100..0",
        zone = { 220, 200 }, source = "Thr",
        opts = { Scale = "Manual", Min = 100, Max = 0, Warn = 55, Crit = 35 },
        value = 40,
        note = "valor 40 queda en WARNING tambien con escala descendente" },
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
      -- The pair has to pose a MUTED state, not a critical one: since Tanda 8
      -- F9 the option only suppresses the informational badges, so two
      -- critical scenes now render identically and the card would show a
      -- difference that no longer exists. What the option really costs the
      -- user is the NO LINK pill; what it may never cost them is CRIT.
      { name = "op-chip-on", title = "State chip ON (sin enlace)",
        zone = { 200, 160 }, opts = { ColorMode = "Rail", ShowChip = true },
        value = 78, post = function(c)
          c.mock.setValue(c.srcId, nil); c.mock.sim.rssi = 0
          for _ = 1, 3 do c.mock.advance(50); c.mod.refresh(c.widget) end
        end },
      { name = "op-chip-off", title = "State chip OFF (sin enlace)",
        zone = { 200, 160 }, alias = "mode-Rail-nochip",
        opts = { ColorMode = "Rail", ShowChip = false },
        value = 78, post = function(c)
          c.mock.setValue(c.srcId, nil); c.mock.sim.rssi = 0
          for _ = 1, 3 do c.mock.advance(50); c.mod.refresh(c.widget) end
        end },
      { name = "op-chip-off-crit", title = "State chip OFF, pero CRIT",
        zone = { 200, 160 },
        opts = { ColorMode = "Rail", ShowChip = false }, value = 22,
        note = "F9: el badge de seguridad sobrevive a la opcion" },
      { name = "op-mm-off", title = "Min/max Off", zone = { 220, 200 },
        opts = { ShowMinMax = "Off" }, value = 78, history = { 31, 92 },
        note = "el ghost permanece: no depende de las marcas min/max" },
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
        alias = "mode-Rail-pos1", opts = { ColorMode = "Rail" }, value = 0 },
      { name = "ne-pos50", title = "centro", zone = { 200, 160 },
        alias = "mode-Rail-pos2", opts = { ColorMode = "Rail" }, value = 50 },
      { name = "ne-pos100", title = "tope final", zone = { 200, 160 },
        alias = "mode-Rail-pos3", opts = { ColorMode = "Rail" }, value = 100 },
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
      { name = "tx-prec2-micro", title = "Decimales 2 / micro",
        zone = { 60, 60 }, source = "RxBt",
        opts = { Precision = "2", Scale = "Manual", Min = 0, Max = 20 },
        value = 16.62 },
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
      .. " Average conservan correctamente el valor por celda.",
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
        note = "regresion: 3.85 V/celda permanece cerca de 55 %" },
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
    note = "El acento sustituye el verde del estado normal. Estas escenas"
      .. " comparan construcciones; el repintado en caliente queda cubierto"
      .. " por la regresion automatizada.",
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
    key = "paleta",
    title = "9 - Personalizacion de paleta",
    note = "Phase 3: Classic conserva severidad universal; Theme sigue HTX;"
      .. " Custom 3/2 preservan colores exactos y Auto suma estructura.",
    cases = {
      { name = "pal-classic", title = "Classic / warning",
        zone = { 300, 70 }, opts = { Style = "Bar", Palette = "Classic" },
        value = 45 },
      { name = "pal-theme", title = "Theme adaptive / warning",
        zone = { 300, 70 },
        opts = { Style = "Bar", Palette = "Theme adaptive" }, value = 45 },
      { name = "pal-preset-theme", title = "Preset Theme / Auto palette",
        zone = { 300, 70 },
        opts = { Style = "Bar", BarPreset = "Theme", Palette = "Auto" },
        value = 78 },
      { name = "pal-preset-auto", title = "Auto Source / RSSI",
        zone = { 300, 70 },
        opts = { Style = "Bar", BarPreset = "Auto" }, value = 78,
        note = "RSSI selecciona Steps: lectura instantanea tipo enlace RC" },
      { name = "pal-custom3-normal", title = "Custom 3 / purple normal",
        zone = { 300, 70 }, opts = {
          Style = "Bar", Palette = "Custom 3",
          Accent = lcd.RGB(0x78, 0x20, 0xc0),
          WarnClr = lcd.RGB(0xf0, 0xd8, 0x18),
          CritClr = lcd.RGB(0x08, 0xb8, 0xe0),
        }, value = 78 },
      { name = "pal-custom3-warn", title = "Custom 3 / yellow warning",
        zone = { 300, 70 }, opts = {
          Style = "Bar", Palette = "Custom 3",
          Accent = lcd.RGB(0x78, 0x20, 0xc0),
          WarnClr = lcd.RGB(0xf0, 0xd8, 0x18),
          CritClr = lcd.RGB(0x08, 0xb8, 0xe0),
        }, value = 45 },
      { name = "pal-custom3-crit", title = "Custom 3 / cyan critical",
        zone = { 300, 70 }, opts = {
          Style = "Bar", Palette = "Custom 3",
          Accent = lcd.RGB(0x78, 0x20, 0xc0),
          WarnClr = lcd.RGB(0xf0, 0xd8, 0x18),
          CritClr = lcd.RGB(0x08, 0xb8, 0xe0),
        }, value = 22 },
      { name = "pal-custom2", title = "Custom 2 / derived midpoint",
        zone = { 300, 70 }, opts = {
          Style = "Bar", Palette = "Custom 2",
          Accent = lcd.RGB(0x78, 0x20, 0xc0),
          CritClr = lcd.RGB(0xf0, 0xd8, 0x18),
        }, value = 45 },
      { name = "pal-custom-track", title = "Custom surface / track",
        zone = { 300, 70 }, opts = {
          Style = "Bar", Surface = "Custom colors",
          TrackClr = lcd.RGB(0x50, 0x18, 0x70),
        }, value = 78 },
      { name = "pal-blue-orange", title = "Blue / orange / red gradient",
        zone = { 320, 90 }, opts = {
          Style = "Bar", ColorMode = "Gradient", Palette = "Custom 3",
          Accent = lcd.RGB(0x18, 0x70, 0xe0),
          WarnClr = lcd.RGB(0xf8, 0x80, 0x10),
          CritClr = lcd.RGB(0xe0, 0x20, 0x20),
        }, value = 78 },
      { name = "pal-pastel", title = "Pastel authored gradient",
        zone = { 320, 90 }, opts = {
          Style = "Bar", ColorMode = "Gradient", Palette = "Custom 3",
          Accent = lcd.RGB(0x98, 0xd0, 0xb8),
          WarnClr = lcd.RGB(0xf0, 0xd0, 0x98),
          CritClr = lcd.RGB(0xe0, 0xa0, 0xb0),
        }, value = 78 },
      { name = "pal-saturated", title = "High-saturation gradient",
        zone = { 320, 90 }, opts = {
          Style = "Bar", ColorMode = "Gradient", Palette = "Custom 3",
          Accent = lcd.RGB(0x00, 0xff, 0x70),
          WarnClr = lcd.RGB(0xff, 0xe0, 0x00),
          CritClr = lcd.RGB(0xff, 0x00, 0x80),
        }, value = 78 },
      { name = "pal-mono-auto", title = "Monochrome / Auto assist",
        zone = { 320, 90 }, opts = {
          Style = "Bar", Palette = "Custom 3", Surface = "Custom colors",
          Accent = lcd.RGB(0x80, 0x80, 0x80),
          WarnClr = lcd.RGB(0x80, 0x80, 0x80),
          CritClr = lcd.RGB(0x80, 0x80, 0x80),
          TrackClr = lcd.RGB(0x80, 0x80, 0x80),
          PanelClr = lcd.RGB(0x80, 0x80, 0x80), Contrast = "Auto",
        }, value = 45 },
      { name = "pal-mono-off", title = "Monochrome / assist Off",
        zone = { 320, 90 }, opts = {
          Style = "Bar", Palette = "Custom 3", Surface = "Custom colors",
          Accent = lcd.RGB(0x80, 0x80, 0x80),
          WarnClr = lcd.RGB(0x80, 0x80, 0x80),
          CritClr = lcd.RGB(0x80, 0x80, 0x80),
          TrackClr = lcd.RGB(0x80, 0x80, 0x80),
          PanelClr = lcd.RGB(0x80, 0x80, 0x80), Contrast = "Off",
        }, value = 45 },
      { name = "pal-mono-strong", title = "Monochrome / Strong assist",
        zone = { 320, 90 }, opts = {
          Style = "Bar", Palette = "Custom 3", Surface = "Custom colors",
          Accent = lcd.RGB(0x80, 0x80, 0x80),
          WarnClr = lcd.RGB(0x80, 0x80, 0x80),
          CritClr = lcd.RGB(0x80, 0x80, 0x80),
          TrackClr = lcd.RGB(0x80, 0x80, 0x80),
          PanelClr = lcd.RGB(0x80, 0x80, 0x80), Contrast = "Strong",
        }, value = 22 },
    },
  },
  {
    key = "barra",
    title = "10 - Estilo barra",
    note = "Phase 2: Precision Rail conserva la verdad del dial y suma cabeza"
      .. " exacta, tres historias, grosores, extremos y superficies reales.",
    cases = {
      { name = "br-normal", title = "normal", zone = { 300, 70 },
        opts = { Style = "Bar" }, value = 78 },
      { name = "br-warn", title = "warning", zone = { 300, 70 },
        opts = { Style = "Bar" }, value = 45 },
      { name = "br-crit", title = "critico", zone = { 300, 70 },
        opts = { Style = "Bar" }, value = 22 },
      { name = "br-narrow", title = "300 x 44", zone = { 300, 44 },
        opts = { Style = "Bar" }, value = 22 },
      -- El chip SI sale aqui: showState solo depende del ANCHO (>= px(120)),
      -- y el presupuesto vertical tiene un peldano de pill desnudo para que
      -- una barra de 44 px no pierda WARN/CRIT (P1-2). El titulo decia "sin
      -- chip" y llevaba tiempo contradiciendo a su propio render.
      { name = "br-short", title = "160 x 44 (pill al minimo)",
        zone = { 160, 44 }, opts = { Style = "Bar" }, value = 22 },
      { name = "br-lowgood", title = "low-is-good (T1)", zone = { 300, 70 },
        source = "T1", opts = { Style = "Bar" }, value = 95 },
      { name = "br-nochip", title = "chip Off: CRIT sigue visible",
        zone = { 300, 70 },
        opts = { Style = "Bar", ShowChip = false }, value = 22 },
      { name = "br-auto", title = "Auto -> barra (ratio > 2.6)",
        zone = { 300, 60 }, opts = { Style = "Auto" }, value = 78 },
      { name = "br-thin", title = "Thin / precision line",
        zone = { 320, 90 }, opts = { Style = "Bar", BarSize = "Thin" },
        value = 78 },
      { name = "br-medium", title = "Medium / default",
        zone = { 320, 90 }, opts = { Style = "Bar", BarSize = "Medium" },
        value = 78 },
      { name = "br-thick", title = "Thick / glanceable",
        zone = { 320, 90 }, opts = { Style = "Bar", BarSize = "Thick" },
        value = 45 },
      { name = "br-maximum", title = "Maximum / bold",
        zone = { 320, 90 }, opts = { Style = "Bar", BarSize = "Maximum" },
        value = 22 },
      { name = "br-end-round", title = "Round ends",
        zone = { 320, 90 }, opts = { Style = "Bar", BarEnds = "Round" },
        value = 78 },
      { name = "br-end-square", title = "Square ends",
        zone = { 320, 90 }, opts = { Style = "Bar", BarEnds = "Square" },
        value = 78 },
      { name = "br-end-chamfer", title = "Chamfer / real triangle tips",
        zone = { 320, 90 }, opts = { Style = "Bar", BarEnds = "Chamfer" },
        value = 78 },
      { name = "br-surface-clear", title = "Transparent surface",
        zone = { 320, 90 },
        opts = { Style = "Bar", Surface = "Transparent" }, value = 45 },
      { name = "br-surface-theme", title = "Theme panel",
        zone = { 320, 90 },
        opts = { Style = "Bar", Surface = "Theme panel" }, value = 45 },
      { name = "br-surface-custom", title = "Custom aubergine panel",
        zone = { 320, 90 }, opts = {
          Style = "Bar", Surface = "Custom colors",
          PanelClr = lcd.RGB(0x38, 0x18, 0x50),
          TrackClr = lcd.RGB(0x78, 0x48, 0x90),
        }, value = 45 },
      { name = "br-mode-static", title = "Static / clean active",
        zone = { 320, 90 },
        opts = { Style = "Bar", ColorMode = "Static" }, value = 45 },
      { name = "br-mode-threshold", title = "Threshold / exact marks",
        zone = { 320, 90 },
        opts = { Style = "Bar", ColorMode = "Threshold" }, value = 45 },
      { name = "br-mode-rail", title = "Rail / permanent context",
        zone = { 320, 90 },
        opts = { Style = "Bar", ColorMode = "Rail" }, value = 45 },
      { name = "br-mode-gradient", title = "Gradient / spatial severity",
        zone = { 320, 90 },
        opts = { Style = "Bar", ColorMode = "Gradient" }, value = 50 },
      { name = "br-gradient-lowgood", title = "Gradient / low-is-good",
        zone = { 320, 90 }, source = "T1",
        opts = { Style = "Bar", ColorMode = "Gradient" }, value = 65 },
      { name = "br-gradient-desc", title = "Gradient / descending scale",
        zone = { 320, 90 }, source = "Thr", opts = {
          Style = "Bar", ColorMode = "Gradient", Scale = "Manual",
          Min = 100, Max = 0, Warn = 55, Crit = 35, Damping = 0,
        }, value = 50 },
      { name = "br-gradient-compact", title = "Gradient / compact 160 x 44",
        zone = { 160, 44 },
        opts = { Style = "Bar", ColorMode = "Gradient" }, value = 50 },
      { name = "br-gradient-large", title = "Gradient / large 480 x 120",
        zone = { 480, 120 }, opts = {
          Style = "Bar", ColorMode = "Gradient", BarSize = "Thick",
          Surface = "Theme panel",
        }, value = 78 },
      { name = "br-mode-sections", title = "Sections / full reference",
        zone = { 320, 90 },
        opts = { Style = "Bar", ColorMode = "Sections" }, value = 45 },
      { name = "br-preset-minimal", title = "Preset Minimal Line",
        zone = { 320, 90 },
        opts = { Style = "Bar", BarPreset = "Minimal" }, value = 78 },
      { name = "br-preset-bold", title = "Preset Bold Data",
        zone = { 320, 90 },
        opts = { Style = "Bar", BarPreset = "Bold data" }, value = 22 },
      { name = "br-zero-cross", title = "-100 .. +100 / zero midpoint",
        zone = { 320, 90 }, source = "Thr", opts = {
          Style = "Bar", Scale = "Manual", Min = -100, Max = 100,
          Warn = -30, Crit = -60, Damping = 0,
        }, value = 0 },
      -- Slot 6's third choice on the BAR. The catalogue had no bar case that
      -- exercised ShowMinMax at all, which is part of why "Markers + text"
      -- could be hard-wired off on this family and go unnoticed.
      { name = "br-minmax-text", title = "Markers + text (shared slot 6)",
        zone = { 360, 100 }, source = "Thr", opts = {
          Style = "Bar", Scale = "Manual", Min = -100, Max = 100,
          ShowMinMax = "Markers + text", Damping = 0,
        }, value = 40, post = function(ctx)
          ctx.mock.setValue(ctx.srcId, -60)
          ctx.mock.advance(50)
          ctx.mod.refresh(ctx.widget)
          ctx.mock.setValue(ctx.srcId, 75)
          ctx.mock.advance(50)
          ctx.mod.refresh(ctx.widget)
        end },
      { name = "br-desc-history", title = "descending / min max ghost",
        zone = { 320, 90 }, source = "Thr", opts = {
          Style = "Bar", Scale = "Manual", Min = 100, Max = 0,
          ShowMinMax = "Markers", Damping = 0,
        }, value = 90, post = function(ctx)
          ctx.mock.setValue(ctx.srcId, 10)
          ctx.mock.advance(50)
          ctx.mod.refresh(ctx.widget)
        end },
      { name = "br-tall", title = "Tall family / explicit H fallback",
        zone = { 100, 220 },
        opts = { Style = "Bar", BarDir = "Horizontal" }, value = 78 },
      { name = "br-large", title = "Large family / 480 x 160",
        zone = { 480, 160 }, opts = { Style = "Bar" }, value = 45,
        history = { 22, 91 } },
    },
  },
  {
    key = "caras4",
    title = "11 - Caras segmentadas Phase 4",
    note = "Blocks, Hex, Ticks y Steps son caras de produccion. La matriz"
      .. " cruza cada lectura con los cinco modos de color y luego fuerza"
      .. " densidad, huecos, compactacion y presets Auto.",
    cases = phase4FaceMatrix(),
  },
  {
    key = "ejes5",
    title = "12 - Ejes, cero y presentacion Phase 5",
    note = "Matriz exhaustiva: todas las caras verticales, origen numerico cero"
      .. ", Dual Rail asimetrico, fuentes RC y cada control de presentacion.",
    cases = phase5AxisMatrix(),
  },
  {
    key = "zonas",
    title = "13 - Matriz de zonas",
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
