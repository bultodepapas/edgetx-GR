-- Luacheck configuration for the GaugePro widget.
--
-- Lua 5.3 is not a preference: it is the interpreter EdgeTX embeds
-- (radio/src/thirdparty/Lua/src/lua.h -> LUA_RELEASE "Lua 5.3.6").
--
-- The EdgeTX API is declared READ-ONLY on purpose. Every Lua widget on the
-- radio shares a single lua_State (`lsWidgets`, radio/src/lua/widgets.cpp),
-- so an accidental global assignment here leaks into every other widget on
-- the SD card. Keeping these read-only turns that class of bug into a
-- luacheck error instead of a field report.

std = "lua53"
max_line_length = 88

read_globals = {
  -- ---- API functions -----------------------------------------------------
  "getFieldInfo", "getRSSI", "getSourceIndex", "getSourceValue",
  "getSwitchValue", "getTime", "getVersion", "loadScript",
  "playHaptic", "playTone",
  "lcd", "lvgl", "model",

  -- ---- limits ------------------------------------------------------------
  "MAX_SENSORS",

  -- ---- widget option types (main.lua option declarations) -----------------
  "BOOL", "CHOICE", "COLOR", "SLIDER", "SOURCE", "STRING", "SWITCH", "VALUE",

  -- ---- font size constants (theme.lua M.FONTS / M.RAMP) -------------------
  -- NB: these are exactly the constants F-10 is about - if the firmware does
  -- not define one, M.RAMP silently gets a hole. Declared here so luacheck
  -- cannot mask that by treating a typo as an undefined global.
  "TINSIZE", "SMLSIZE", "STDSIZE", "MIDSIZE", "DBLSIZE", "XLSIZE", "XXLSIZE",

  -- ---- alignment ---------------------------------------------------------
  "LEFT", "CENTER", "RIGHT",

  -- ---- colours -----------------------------------------------------------
  "BLACK", "WHITE", "RED",
  "COLOR_THEME_ACTIVE", "COLOR_THEME_DISABLED", "COLOR_THEME_EDIT",
  "COLOR_THEME_FOCUS", "COLOR_THEME_PRIMARY1", "COLOR_THEME_PRIMARY2",
  "COLOR_THEME_PRIMARY3", "COLOR_THEME_SECONDARY1", "COLOR_THEME_SECONDARY2",
  "COLOR_THEME_SECONDARY3", "COLOR_THEME_WARNING",
}

files["tests/"] = {
  -- The harness deliberately installs fakes over the firmware API.
  globals = { "loadScript", "model", "lcd", "lvgl" },
}

files["dev/"] = {
  -- Probes and render tools do the same, plus they print.
  globals = { "loadScript", "model", "lcd", "lvgl" },
}
