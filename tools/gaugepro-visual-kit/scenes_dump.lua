-- Gauge Pro visual kit: dump dev/scenes.lua's scenario catalog as JSON.
--
-- Same zero-duplication discipline as defs_dump.lua: dev/scenes.lua is a
-- mature, audited ~150-case catalog (13 sections) already used by the SVG
-- mock loop. Hand-transcribing it into Python would risk exactly the kind
-- of drift/typo that main.lua's DEFS builder already got burned by once
-- (see defs_dump.lua's header) -- so this loads the real file and dumps
-- M.allCases() + M.SOURCES directly.
--
-- `post` fields are Lua closures (mutate-after-settle for stale/no-link/
-- damping-step cases) and cannot be serialized; they are dropped here and
-- re-expressed for the real firmware explicitly in catalog.py, keyed by
-- case name (a short, audited list -- see catalog.py's POST_ACTIONS).
--
-- Usage: lua scenes_dump.lua <gaugepro-widget-dir> <out.json>

local widgetDir = arg[1] or "./"
local outPath = arg[2] or "scenes.json"
local toolDir = (arg[0] or "scenes_dump.lua"):gsub("scenes_dump%.lua$", "")

local mock = dofile(widgetDir .. "tests/mock_env.lua")
mock.install(_ENV or _G)

local json = dofile(toolDir .. "json_lite.lua")

local scenes = dofile(widgetDir .. "dev/scenes.lua")
local allCases = scenes.allCases()

-- Strip non-serializable fields (post closures) and resolve "@COLOR_THEME_X"
-- option values to their literal 0xRRGGBB now, while the real theme colour
-- flags are in scope -- catalog.py then only ever deals in plain numbers.
local function resolveOptValue(v)
  if type(v) == "string" and string.sub(v, 1, 1) == "@" then
    local flag = _G[string.sub(v, 2)]
    if type(flag) == "number" then
      local ok, resolved = pcall(lcd.getColor, flag)
      if ok and type(resolved) == "number" then
        -- resolved is (rgb565 << 16) | 0x8000, same packing decode.py
        -- expects from defs.json's COLOR defaults.
        return resolved
      end
    end
  end
  return v
end

local function cleanOpts(opts)
  if not opts then return nil end
  local out = {}
  for k, v in pairs(opts) do out[k] = resolveOptValue(v) end
  return out
end

local rows = {}
for i = 1, #allCases do
  local c = allCases[i]
  local hasPost = (c.post ~= nil)
  rows[i] = {
    name = c.name,
    title = c.title,
    section = c.section,
    sectionTitle = c.sectionTitle,
    zone = c.zone,
    source = c.source,
    opts = cleanOpts(c.opts),
    value = c.value,
    history = c.history,
    frames = c.frames,
    noSource = c.noSource and true or nil,
    note = c.note,
    alias = c.alias,
    hasPost = hasPost or nil,
  }
end

-- Source registry, verbatim (id/unit/prec/minId/maxId/sensor/name).
local sources = {}
for name, s in pairs(scenes.SOURCES) do
  sources[name] = {
    id = s.id, name = s.name, unit = s.unit, prec = s.prec,
    minId = s.minId, maxId = s.maxId, sensor = s.sensor,
  }
end

local nonVisual = {}
for k, v in pairs(scenes.NON_VISUAL) do nonVisual[k] = v end

json.writeFile(outPath, { cases = rows, sources = sources,
                           nonVisual = nonVisual })

print(string.format("scenes_dump: wrote %d cases -> %s", #rows, outPath))
