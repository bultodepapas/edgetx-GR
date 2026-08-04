---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - known-sensor presets                                       #
---- #                                                                       #
---- # Pure Lua. Matching order (per PLAN.md): exact source name, then       #
---- # unit fallback for telemetry sources. Presets only initialize values   #
---- # while the user range options still hold their global defaults.        #
---- #                                                                       #
---- # Range table expanded from GaugeRotary's DEFAULT_MIN_MAX plus the      #
---- # TxBat alias for the built-in tx-voltage source.                       #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local M = {}

-- Units use the EdgeTX TelemetryUnit enum values (dataconstants.h):
-- 1=V, 2=A, 3=mA, 11=degC, 12=degF, 13=%, 14=mAh, 15=W, 17=dB, 18=rpm, 29=dBm
local PRESETS = {
  {
    names = { "RSSI", "RSSI1", "RSSI2", "RSSI3" },
    units = { 17, 29 },
    minimum = 0, maximum = 100, warning = 55, critical = 35, highIsGood = true,
  },
  {
    names = { "1RSS", "2RSS" },
    units = { 29 },
    minimum = -120, maximum = 0, warning = -80, critical = -95,
    highIsGood = true,
  },
  {
    names = { "RQly", "RQly%", "VFR%", "VFR" },
    units = { 13 },
    minimum = 0, maximum = 100, warning = 55, critical = 35, highIsGood = true,
  },
  {
    names = { "RxBt", "RxBatt", "Batt" },
    units = { 1 },
    minimum = 0, maximum = 8.4, warning = 3.7, critical = 3.5, highIsGood = true,
  },
  {
    names = { "TxBat", "TxBatt", "Battery", "tx-voltage" },
    units = { 1 },
    minimum = 0, maximum = 8.4, warning = 6.8, critical = 6.4, highIsGood = true,
  },
  {
    names = { "Cell", "Cells", "Cels" },
    units = { 1 },
    minimum = 3.5, maximum = 4.2, warning = 3.7, critical = 3.5,
    highIsGood = true,
  },
  {
    names = { "Tmp", "Temp", "T1", "T2", "Temperature", "Tmp1", "Tmp2" },
    units = { 11, 12 },
    minimum = 0, maximum = 120, warning = 70, critical = 90, highIsGood = false,
  },
  {
    names = { "RPM", "RPMs", "Turbine" },
    units = { 18 },
    minimum = 0, maximum = 20000, warning = 16000, critical = 18000,
    highIsGood = false,
  },
  {
    names = { "Fuel" },
    units = { 13 },
    minimum = 0, maximum = 100, warning = 30, critical = 15, highIsGood = true,
  },
  {
    names = { "Vibr", "Vibration" },
    units = { 13 },
    minimum = 0, maximum = 100, warning = 40, critical = 60, highIsGood = false,
  },
}

local function normName(s)
  if type(s) ~= "string" then return "" end
  -- string methods (s:lower()) are unavailable on EdgeTX Lua builds without
  -- LUA_ENABLE_STRLIB_MT, so use the string library functions explicitly
  return (string.gsub(string.lower(s), "[^%w]", ""))
end

-- Find a preset for a resolved source { name=..., unit=... }.
-- Returns the preset table or nil.
function M.find(source)
  if not source or not source.name then return nil end
  local name = normName(source.name)
  if name == "" then return nil end
  for i = 1, #PRESETS do
    local p = PRESETS[i]
    for j = 1, #p.names do
      if normName(p.names[j]) == name then return p end
    end
  end
  if source.unit then
    for i = 1, #PRESETS do
      local p = PRESETS[i]
      if p.units then
        for j = 1, #p.units do
          if p.units[j] == source.unit then return p end
        end
      end
    end
  end
  return nil
end

return M
