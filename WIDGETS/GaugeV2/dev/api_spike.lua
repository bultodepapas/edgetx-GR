---- #########################################################################
---- #                                                                       #
---- # Gauge V2 - LVGL API feasibility spike                                 #
---- #                                                                       #
---- # Verifies, on real firmware, the binding behaviors that Gauge V2       #
---- # depends on. Drop this folder on the SD card and add the widget to a   #
---- # color radio layout in Companion, or run on hardware.                  #
---- #                                                                       #
---- # The script exercises each API and writes PASS/FAIL lines into a       #
---- # label that replaces the widget content.                               #
---- #                                                                       #
---- # Findings verified statically in radio/src/lua/ (see PLAN.md):         #
---- #   - arc: absolute angles, 405 auto-normalizes to 45                   #
---- #   - line: pts table or function; hash-compared on lvgl.set            #
---- #   - label: text/color/font/pos; font = index << 8                     #
---- #   - no scale widget, no rotation, no arc "value" property             #
---- #   - controls (button etc.) only when fullscreen                       #
---- #########################################################################

local checks = {}

local function check(name, ok, detail)
  checks[#checks + 1] = (ok and "PASS" or "FAIL") .. " " .. name
    .. (detail and (" (" .. tostring(detail) .. ")") or "")
end

local function create(zone, options)
  if not lvgl then
    error("lvgl missing - requires EdgeTX 2.11+")
  end
  return { zone = zone, ui = {}, step = 0 }
end

local function update(spike, options)
  spike.step = (spike.step + 1) % 4
end

local function refresh(spike, event, touch)
  local zone = spike.zone
  local cx, cy = math.floor(zone.w / 2), math.floor(zone.h / 2)
  local r = math.min(zone.w, zone.h) / 2 - 10

  if spike.step == 0 then
    checks = {}
    -- 1) arc with 405 deg end angle + per-frame endAngle update
    spike.ui.arc = lvgl.arc{
      x = cx, y = cy, radius = r,
      startAngle = 135, endAngle = 405,
      bgStartAngle = 135, bgEndAngle = 405,
      color = COLOR_THEME_ACTIVE, bgColor = COLOR_THEME_SECONDARY2,
      bgOpacity = 255, opacity = 0, thickness = 6, rounded = 1,
    }
    spike.ui.arc2 = lvgl.arc{
      x = cx, y = cy, radius = r,
      startAngle = 135, endAngle = 135,
      bgStartAngle = 135, bgEndAngle = 405,
      bgOpacity = 0, color = RED, thickness = 4, rounded = 1,
    }
    spike.ui.needle = lvgl.line{
      pts = { { x = cx, y = cy }, { x = cx + r - 6, y = cy } },
      thickness = 2, rounded = 1, color = COLOR_THEME_PRIMARY1,
    }
    spike.ui.pivot = lvgl.circle{
      x = cx, y = cy, radius = 5,
      color = COLOR_THEME_PRIMARY1, bgColor = COLOR_THEME_PRIMARY1,
      bgOpacity = 255, thickness = 0,
    }
    spike.ui.lbl = lvgl.label{
      x = cx - 60, y = cy - 20, w = 120, h = 16,
      text = "spike", font = 0x100, color = COLOR_THEME_PRIMARY1,
    }
  elseif spike.step == 1 then
    -- 2) set() partial updates: endAngle, line pts, label text
    local a = 135 + (math.floor(getTime() / 40) % 271)
    lvgl.set(spike.ui.arc2, { endAngle = a })
    local rad = a * math.pi / 180
    lvgl.set(spike.ui.needle,
      { pts = { { x = cx, y = cy },
                { x = cx + (r - 6) * math.cos(rad), y = cy + (r - 6) * math.sin(rad) } } })
    lvgl.set(spike.ui.lbl, { text = "a=" .. a })
  elseif spike.step == 2 then
    -- 3) hide/show round trip
    lvgl.hide(spike.ui.needle)
  else
    lvgl.show(spike.ui.needle)
    -- 4) constants and helpers used by the widget
    local w, h = lcd.sizeText("88.8", 0x500)
    check("sizeText", type(w) == "number" and type(h) == "number" and h > 0, tostring(w) .. "x" .. tostring(h))
    check("LCD_SCALE", type(lvgl.LCD_SCALE) == "number", tostring(lvgl.LCD_SCALE))
    check("theme colors", type(COLOR_THEME_WARNING) == "number")
    local text = ""
    for i = 1, #checks do
      text = text .. checks[i] .. " | "
    end
    lvgl.set(spike.ui.lbl, { text = text })
  end
end

return {
  name = "GaugeV2Spike",
  options = {},
  create = create,
  update = update,
  refresh = refresh,
  useLvgl = true,
}
