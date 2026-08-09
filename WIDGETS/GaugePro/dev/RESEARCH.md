# Gauge Pro — Research Notes

Findings from the web/ecosystem investigations that shaped the widget, with the
firmware-verified facts behind each improvement (2026-08-04).

## 1. Official EdgeTX docs — Lua LVGL API

Source: https://luadoc.edgetx.org (Lua Reference Guide, AI queryable)

- Widget lifecycle reality: **`background()` runs only while the widget is
  OFF-SCREEN; `refresh()` runs only while visible** (`widgets_container.cpp`
  `refreshWidgets()`). Consequence: flight history must be tracked in
  `refresh()` — GaugePro does that now.
- **Widget options are capped at 10** (2.11+), option names ≤ 10 chars,
  widget name ≤ 10 chars. GaugePro has exactly 10 options; any future option
  must replace one.
- Fullscreen: zone becomes LCD_W×LCD_H; `lvgl.isFullScreen()` /
  `lvgl.exitFullScreen()` exist.
- The documented memory-saving pattern (lazy `loadScript` modules from
  `main.lua`) matches GaugePro's architecture.

## 2. Official constants — etcxcst

Verified in `radio/src/lua/api_general.cpp` (LROT_BEGIN(etxcst)):

- `SMLSIZE`=FONT(XS), `MIDSIZE`=FONT(L), `DBLSIZE`=FONT(XL), `TINSIZE`,
  `STDSIZE`, `BOLD`, `XXLSIZE`, `XLSIZE` — real Lua globals. GaugePro now uses
  them instead of hardcoded `index << 8` values.
- `SOURCE` and `VALUE` are the official option-type constants.
- `getRSSI()` and `getSourceName()` are available in Lua.

## 3. Lua string methods are unavailable

EdgeTX's Lua (LROT build) only installs the string metatable when
`LUA_ENABLE_STRLIB_MT` is defined — it is not. `s:lower()` fails on the radio
with "attempt to index a string value". Use `string.lower(s)` etc. The test
mock strips the string metatable to enforce this.

## 4. `getTime()` returns 10 ms ticks

`radio/src/lua/api_general.cpp` `luaGetTime` → `get_tmr10ms()`. GaugePro's
smoothing multiplies by 10 for a correct milliseconds time constant.

## 5. `getFieldInfo()` quirks

- Does **not** return `prec`; sensor precision must come from
  `model.getSensor(i).prec` (cached on source change).
- Names can start with an invalid character on some firmware (workaround from
  GaugeRotary's `lib_widget_tools.lua`).

## 6. GaugeRotary reference implementation

Source: https://github.com/offer-shmuely/edgetx-x10-widgets (WIDGETS/GaugeRotary)

- **Auto source discovery**: pick the first existing sensor from a priority
  list as the Source default (`findSourceId`). GaugePro now defaults to
  RSSI/RQly/RxBt/Cels/TxBt.
- Extended preset table (1RSS/2RSS −120..0, RQly, cell 3.5–4.2, Fuel, Vibr,
  Tmp1/Tmp2) — merged into GaugePro presets.
- Telemetry availability via `getRSSI() > 0` — GaugePro now distinguishes
  `disconnected` (link down) from `unavailable` (sensor missing, link up).
- `Min=-1/Max=-1` sentinel for auto ranges — GaugePro uses explicit defaults +
  persistent presets instead (no sentinel ambiguity).

## 7. Contest-winning LVGL widget (EdgeTX Lua LVGL contest #8/#9)

Source: https://github.com/agnauck/EdgeTX-Widgets (WIDGETS/Dashboard)

- Dynamic label `text` closures are the documented idiom (re-evaluated by
  `callRefs` each frame). GaugePro keeps explicit string-compare + `lvgl.set`
  for lower per-frame cost.
- **Timer sources display as hh:mm:ss** — adopted.
- Deeply nested `children` build trees work in practice; GaugePro keeps flat
  object creation for readability and instruction economy.
- "Keep the last known value on telemetry loss" — already GaugePro behavior.

## 8. Distribution: EdgeTX/lua-scripts gallery

Source: https://github.com/EdgeTX/lua-scripts

- The official home for community Lua apps/widgets is the **gallery repo**
  (`scripts.json` manifest); widgets stay in their own repos and are listed
  via an issue template ("Add a Lua App or Widget to the Gallery").
- EdgeTX-sdcard `dev/WIDGETS` also exists but is for dev examples.
- GaugePro will be distributed from the fork repo + listed in the gallery.

## 9. Grafana gauge design semantics

Source: Grafana docs (Gauge visualization)

- Min/max define the arc; null shows "-" (GaugePro matches).
- "Neutral value" (fill from 0 instead of min) — useful for bipolar ranges;
  candidate for a future option.
- Segmented arcs + segment spacing — future "Segmented" style candidate.
- Endpoint markers (needle/point) — GaugePro's line needle covers this.

## 10. LVGL 8.4 (vendored)

- `radio/src/thirdparty/lvgl` is LVGL 8.4.1.
- Arc angles are normalized mod 360 (`if (start > 360) start -= 360`), so the
  135..405 range is safe.
- Native LVGL scale widgets exist in 8.x but are **not** exposed by EdgeTX's
  Lua binding — GaugePro builds ticks from `lvgl.line` objects.

## 11. W3C accessibility (applied)

- Color is never the only indicator: WARN/CRIT/NO DATA text + markers + color.
- Contrast: state colors derive from theme roles; critical uses RED.
- No blinking (GaugeRotary blinks "Disconnected..."; GaugePro does not).

## 12. Ecosystem survey

Source: https://edgetx.org/lua-scripts (gallery manifest)

- No dedicated analog telemetry gauge exists in the official gallery —
  GaugePro fills a gap.
- WidgetTx (widgettx.com) and EdgeTX-Goodies are additional distribution
  channels worth listing later.

## 13. Firmware call-site verification

- `widgets_container.cpp:refreshWidgets()` — foreground/background split
  confirmed.
- `luaGetSourceValue` returns (value, isCurrent, isFresh); telemetry sources
  return no value when the sensor is unavailable — the availability model is
  built on that.

## 14. Widget review — mahRe2 (fdm225)

Source: https://github.com/fdm225/mahRe2

- Legacy lcd-drawn widget; battery domain logic: voltage->percent lookup
  tables, per-zone-size refresh tiers (Tiny..XLarge), sensor-derived `+`/`-`
  min/max values (`getValue("Cels+")`), GV read/write, `playFile` sound
  announcements, graduated green->red color. Ideas banked for V2.1:
  optional WARN/CRIT sound alerts, GV export of min/max, sensor min/max
  markers (`<name>+`/`<name>-`).

## 15. Widget review — ExpressLRS ELRS Telem (ExpressLRS/ElrsTelemWidget)

Source: https://github.com/ExpressLRS/ElrsTelemWidget

- **Simulator detection**: `getVersion()` revision ends with "-simu" —
  used to fake telemetry in the simulator (useful for screenshots).
- **Fullscreen detection**: in `refresh`, `event ~= nil` means fullscreen —
  no need for `lvgl.isFullScreen()`.
- **Value ID cache with 0 sentinel**: never re-look-up a missing source.
- Background = data maintenance (GPS kept after link loss); refresh displays.
- Theme-consistent `COLOR_THEME_*` usage; background overlay with a
  Transparency option.

## 16. Widget review — BattAnalog (offer-shmuely)

Source: https://github.com/offer-shmuely/edgetx-x10-widgets

- **Official SOURCE table default**: `{ "sensor", SOURCE, {name1, name2, ...} }`
  — the firmware resolves the first available source natively
  (`lua_widget_factory.cpp` `sourceValue()`). GaugePro's default source now
  uses this instead of a hand-rolled lookup.
- **`translate(name)` callback** — option display names in the settings UI.
- Dynamic LVGL properties as functions (`color/pos/size/visible/text =
  function()`), evaluated per callRefs — the documented idiom; GaugePro keeps
  explicit sets for instruction economy.
- Zone thresholds multiplied by `lvgl.LCD_SCALE` — GaugePro mode thresholds
  are now scale-aware.
- `package.searchers` polyfill to enable `require()`; `setTelemetryValue`
  sensor emulation.
- Battery chemistry percent curves (LiPo/HV/LiIon/LiFePO4) — future preset
  knowledge.

## 17. Widget review — SpiderFI TXBatt / MicroValues (offer-shmuely)

- **Font auto-fit** (SpiderFI): pick the largest font whose measured height
  fits the available area — GaugePro's value font now fits the value area
  instead of a fixed per-mode choice.
- MicroValues confirms `translate()` and table defaults as standard practice.

## 18. Option-type constant bug found by the review

`widget.h` `WidgetOption::Type`: Integer=0, Source=1, Bool=2, String=3,
TextSize=4, Timer=5, Switch=6, Color=7, Align=8, Slider=9, **Choice=10**,
File=11. GaugePro previously used `9` for Choice options (that is Slider) —
the settings UI would have rendered sliders. All option types now use the
official constants (SOURCE/VALUE/BOOL/CHOICE), with a regression test.

## 19. Official firmware widgets review

Sources: `radio/src/gui/colorlcd/widgets/` (gauge.cpp, value.cpp, text.cpp,
timer.cpp, outputs.cpp, radio_info.cpp, modelbmp.cpp)

**Official Gauge (gauge.cpp)** — the built-in bar gauge:
- Inverted ranges (`min > max`) swap AND mirror the value
  (`value = value - min - max`) — a reversed-scale feature; GaugePro swaps
  only (mirroring is a V2.1 candidate, the official transform is degenerate
  for asymmetric ranges).
- `divRoundClosest(100*(v-min), max-min)` — nearest rounding (GaugePro uses
  floor(x+0.5), equivalent).
- `limit(min, v, max)` clamping, label via `getSourceString()`.
- `foreground()` updates only when the value changed (GaugePro's frame
  compare is the same discipline).
- `LAYOUT_VAL_SCALED` constants — GaugePro's `px()` is the equivalent.
- Options: source, min (-RESX), max (RESX), color — no thresholds/states;
  GaugePro's state model goes beyond the official widget.

**Official Value (value.cpp)** — applied to GaugePro:
- **Elapsed countdown timer → WARNING color** (`ETX_STATE_TIMER_ELAPSED`) —
  implemented: a negative timer value colors the gauge warning.
- **tx-voltage appends "V"** — implemented as a unit-name fallback.
- **tx-time formats hh:mm:ss** — implemented (`isTimerName` + hms).
- Stale telemetry = `!isAvailable() || isOld()` → `COLOR_THEME_DISABLED` —
  GaugePro's `isCurrent`/`getRSSI` model is equivalent.
- Optional shadow labels at (+1,+1) — not exposed by the Lua binding.
- ALIGN options and per-source font selection — candidates if GaugePro ever
  gets option slots.

**Official Text (text.cpp)** — confirmed the font convention:
`getFont(index << 8)` — GaugePro's font flags (STDSIZE..XLSIZE = index << 8)
match the official mechanism exactly.

**Widget base class (widget.cpp)** — `setFullScreen()` calls
`updateWithoutRefresh()`; the zone is resized to the full screen. GaugePro's
layout signature rebuild handles this.

## 20. Official widget conventions checklist (GaugePro status)

- change-only redraws: DONE (frame compares)
- theme role colors everywhere: DONE
- scaled layout constants (LCD_SCALE): DONE
- inverted-range mirroring: TODO V2.1 (documented)
- optional shadows: n/a (binding limitation)
- alignment options: TODO if option slots free up
- sensor-dependent font sizing: n/a (gauge context)
