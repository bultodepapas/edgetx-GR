---- ##########################################################################
---- TeleInject - Gauge Pro visual kit companion widget.
----
---- Not part of Gauge Pro. Registers real telemetry sensors from a
---- driver-generated data file (/SCRIPTS/gpvk_telemetry.lua) so Gauge Pro
---- instances elsewhere on the same screen read them through the real
---- sensor registry (getValue/getFieldInfo/CELLS), exactly as on-radio -
---- see myplans/gaugepro-visual-kit-plan.md Sec 6.
----
---- Draws nothing. Placed in a topbar zone so it never overlaps a capture.
---- License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html
---- ##########################################################################

local DATA_PATH = "/SCRIPTS/gpvk_telemetry.lua"
local appliedGeneration = -1

local function apply()
  local chunk = loadScript(DATA_PATH, "t")
  if not chunk then return end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return end
  if data.generation == appliedGeneration then return end

  for i = 1, #data.sensors do
    local s = data.sensors[i]
    -- First call registers the sensor (its value is ignored on that call
    -- per the setTelemetryValue contract); call again immediately so the
    -- value takes effect the same frame instead of one generation late.
    local justAdded = setTelemetryValue(s.id, s.subId or 0, s.instance or 0,
      s.value, s.unit or 0, s.prec or 0, s.name)
    if justAdded then
      setTelemetryValue(s.id, s.subId or 0, s.instance or 0, s.value,
        s.unit or 0, s.prec or 0)
    end
  end
  appliedGeneration = data.generation
end

local function create(zone)
  apply()
  return { zone = zone }
end

local function update(widget, opts)
  apply()
end

local function refresh(widget, event, touch)
  apply()
end

return {
  name = "TeleInject",
  options = {},
  create = create,
  update = update,
  refresh = refresh,
}
