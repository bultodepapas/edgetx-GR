---- #########################################################################
---- #                                                                       #
---- # Gauge Pro - responsive analog-digital telemetry widget                 #
---- #                                                                       #
---- # LVGL-only Lua widget for EdgeTX 2.11+ (developed against 3.0).        #
---- #                                                                       #
---- # main.lua is executed at radio startup for EVERY widget on the SD      #
---- # card, used or not, so it stays data-only: the option declarations,    #
---- # a compatibility guard, and a loadScript of app.lua on first use.      #
---- #                                                                       #
---- # OPTION CONTRACT (details and firmware references in options.lua):     #
---- #   * CHOICE values are integers, stored 1-BASED - never strings.       #
---- #   * Option slots are positional; options may only be APPENDED.        #
---- #   * 2.11 provides ten slots, 2.12+ provides fifty. The first ten      #
---- #     declarations below are therefore the ones that must matter, and   #
---- #     the rest are only declared when the firmware can store them.      #
---- #                                                                       #
---- # License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html               #
---- #########################################################################

local NAME = "GaugePro"
local DEFAULT_PATH = "/WIDGETS/GaugePro/"

-- Compatibility guard (rotorflight RfStats pattern): a widget that cannot
-- draw must still register, or it vanishes from the model with no
-- explanation. Raising an error here would show a firmware error box.
if lvgl == nil then
  return {
    name = NAME,
    options = {},
    create = function(zone) return { zone = zone } end,
    update = function() end,
    refresh = function()
      lcd.drawText(3, 3, "GaugePro needs EdgeTX 2.11+", SMLSIZE)
    end,
  }
end

-- Option declarations. `since` 212 marks options that only exist where the
-- firmware has more than ten slots. `field` is the name the parsed config
-- uses; entries without one are not consumed by the widget code.
local DEFS = {
  -- ---- core ten: identical positions to 1.0, available on 2.11 ----------
  { key = "Source", label = "Source", type = SOURCE, field = "source",
    since = 211, default = { "RSSI", "RQly", "RxBt", "Cels", "TxBt" } },
  { key = "Min", label = "Minimum", type = VALUE, field = "min",
    since = 211, default = 0, min = -10000, max = 10000 },
  { key = "Max", label = "Maximum", type = VALUE, field = "max",
    since = 211, default = 100, min = -10000, max = 10000 },
  { key = "Warn", label = "Warning", type = VALUE, field = "warn",
    since = 211, default = 55, min = -10000, max = 10000 },
  { key = "Crit", label = "Critical", type = VALUE, field = "crit",
    since = 211, default = 35, min = -10000, max = 10000 },
  { key = "HighGood", label = "High is good", type = BOOL, field = "highGood",
    since = 211, default = 1 },
  { key = "Style", label = "Style", type = CHOICE, field = "style",
    since = 211, default = 1, choices = { "Auto", "Needle", "Arc", "Bar" } },
  { key = "ColorMode", label = "Colours", type = CHOICE, field = "colorMode",
    since = 211, default = 3,
    choices = { "Static", "Threshold", "Rail", "Gradient", "Sections" } },
  { key = "Precision", label = "Decimals", type = CHOICE, field = "precision",
    since = 211, default = 1, choices = { "Auto", "0", "1", "2" } },
  { key = "ShowMinMax", label = "Min / max", type = CHOICE,
    field = "showMinMax", since = 211, default = 2,
    choices = { "Off", "Markers", "Markers + text" } },

  -- ---- appended: 2.12+ only (fifty slots) -------------------------------
  -- On 2.12+ this option is always populated (COLOR options have no
  -- "unedited" sentinel the way choices do), so its default IS the
  -- normal-state colour everyone sees until they pick their own - it must
  -- match theme.lua's M.color.accent or the option silently shadows the
  -- fallback and 2.12+ radios never see it (pinned by a test).
  --
  -- It used to be COLOR_THEME_ACTIVE, a CHECKED-control background role that
  -- is #ffde00 on the stock theme: 1.13:1 against the stock screen, i.e. an
  -- invisible "all clear" (Tanda 8 F0). The literal here is duplicated from
  -- theme.lua deliberately - main.lua stays data-only, because it is read at
  -- boot for every widget on the card, used or not.
  { key = "Accent", label = "Accent colour", type = COLOR, field = "accent",
    since = 212, default = lcd.RGB(0x20, 0x90, 0x58) },
  { key = "Label", label = "Name override", type = STRING, field = "label",
    since = 212, default = "" },
  { key = "Suffix", label = "Unit override", type = STRING, field = "suffix",
    since = 212, default = "" },
  { key = "Scale", label = "Scale", type = CHOICE, field = "scale",
    since = 212, default = 1, choices = { "Auto", "Manual" } },
  { key = "Sweep", label = "Dial sweep", type = CHOICE, field = "sweep",
    since = 212, default = 1, choices = { "270 deg", "180 deg", "360 deg" } },
  { key = "Damping", label = "Needle damping", type = SLIDER,
    field = "damping", since = 212, default = 4, min = 0, max = 9 },
  { key = "Cells", label = "Cell reading", type = CHOICE, field = "cells",
    since = 212, default = 1, choices = { "Lowest", "Total", "Average" } },
  { key = "Battery", label = "Battery percent", type = CHOICE,
    field = "battery", since = 212, default = 1,
    choices = { "Off", "Li-Po", "Li-Ion" } },
  { key = "Alerts", label = "Alerts", type = CHOICE, field = "alerts",
    since = 212, default = 1,
    choices = { "Off", "Critical", "Warning + critical" } },
  { key = "AlertSw", label = "  Alert switch", type = SWITCH,
    field = "alertSw", since = 212, default = 0 },
  { key = "Delay", label = "  Startup delay (s)", type = VALUE,
    field = "delay", since = 212, default = 4, min = 0, max = 30 },
  { key = "Vibrate", label = "  Vibrate", type = BOOL, field = "vibrate",
    since = 212, default = 0 },
  { key = "ResetSw", label = "Reset min/max", type = SWITCH,
    field = "resetSw", since = 212, default = 0 },
  { key = "ShowChip", label = "State chip", type = BOOL, field = "showChip",
    since = 212, default = 1 },
}

-- Firmware option array. Built inline (rather than in options.lua) so boot
-- costs exactly one file read per widget - main.lua runs at startup for
-- every widget on the card, used or not. DELIBERATE duplication (Tanda 6
-- F-14/6.1): options.lua's builder and translator were deleted after
-- verifying both byte-identical (dev/boot_cost.lua), so this inline build
-- is the ONLY builder - the two can never drift. options.lua owns the rest
-- (capacity, parse) and loads once per radio on first use (P2-3 cache).
local CORE, EXTENDED = 10, 50
local capacity = CORE
if type(getVersion) == "function" then
  local _, _, maj, minor = getVersion()
  maj, minor = tonumber(maj), tonumber(minor)
  if maj and (maj > 2 or (maj == 2 and (minor or 0) >= 12)) then
    capacity = EXTENDED
  end
end

local options = {}
local labels = { [NAME] = "Gauge Pro" }
for i = 1, #DEFS do
  local d = DEFS[i]
  labels[d.key] = d.label
  local needs = (d.since == 212) and EXTENDED or CORE
  if needs <= capacity and #options < capacity then
    if d.type == CHOICE then
      options[#options + 1] = { d.key, d.type, d.default, d.choices }
    elseif d.type == VALUE or d.type == SLIDER then
      options[#options + 1] = { d.key, d.type, d.default, d.min, d.max }
    else
      options[#options + 1] = { d.key, d.type, d.default }
    end
  end
end

local function translate(name)
  return labels[name]
end

-- app.lua is loaded once per RADIO, not once per widget instance: main.lua
-- itself is evaluated once and its upvalues are shared by every instance
-- (luaLoadWidgetCallback), so a memoized app - whose own module table is
-- likewise shared, see app.lua - cuts 13 loadScript calls per instance
-- (AUDIT.md P2-3: four gauges on one screen used to load 52 chunks).
local sharedApp

local function create(zone, opts, path)
  path = path or DEFAULT_PATH
  if not sharedApp then
    local chunk, err = loadScript(path .. "app.lua", "bt")
    if not chunk then
      error("GaugePro: cannot load app.lua (" .. tostring(err) .. ")")
    end
    sharedApp = chunk(DEFS)
  end
  local widget = sharedApp.create(zone, opts, path)
  widget.app = sharedApp
  return widget
end

local function update(widget, opts)
  if widget.app then widget.app.update(widget, opts) end
end

local function refresh(widget, event, touch)
  if widget.app then widget.app.refresh(widget, event, touch) end
end

return {
  name = NAME,
  options = options,
  translate = translate,
  create = create,
  update = update,
  refresh = refresh,
  useLvgl = true,
  -- exposed for the headless contract tests; the firmware ignores extra keys
  defs = DEFS,
}
