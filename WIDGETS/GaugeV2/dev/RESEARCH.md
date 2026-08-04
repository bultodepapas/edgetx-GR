# Gauge V2 — Research Notes

Findings from the web/ecosystem investigations that shaped the widget, with the
firmware-verified facts behind each improvement (2026-08-04).

## 1. Official EdgeTX docs — Lua LVGL API

Source: https://luadoc.edgetx.org (Lua Reference Guide, AI queryable)

- Widget lifecycle reality: **`background()` runs only while the widget is
  OFF-SCREEN; `refresh()` runs only while visible** (`widgets_container.cpp`
  `refreshWidgets()`). Consequence: flight history must be tracked in
  `refresh()` — GaugeV2 does that now.
- **Widget options are capped at 10** (2.11+), option names ≤ 10 chars,
  widget name ≤ 10 chars. GaugeV2 has exactly 10 options; any future option
  must replace one.
- Fullscreen: zone becomes LCD_W×LCD_H; `lvgl.isFullScreen()` /
  `lvgl.exitFullScreen()` exist.
- The documented memory-saving pattern (lazy `loadScript` modules from
  `main.lua`) matches GaugeV2's architecture.

## 2. Official constants — etcxcst

Verified in `radio/src/lua/api_general.cpp` (LROT_BEGIN(etxcst)):

- `SMLSIZE`=FONT(XS), `MIDSIZE`=FONT(L), `DBLSIZE`=FONT(XL), `TINSIZE`,
  `STDSIZE`, `BOLD`, `XXLSIZE`, `XLSIZE` — real Lua globals. GaugeV2 now uses
  them instead of hardcoded `index << 8` values.
- `SOURCE` and `VALUE` are the official option-type constants.
- `getRSSI()` and `getSourceName()` are available in Lua.

## 3. Lua string methods are unavailable

EdgeTX's Lua (LROT build) only installs the string metatable when
`LUA_ENABLE_STRLIB_MT` is defined — it is not. `s:lower()` fails on the radio
with "attempt to index a string value". Use `string.lower(s)` etc. The test
mock strips the string metatable to enforce this.

## 4. `getTime()` returns 10 ms ticks

`radio/src/lua/api_general.cpp` `luaGetTime` → `get_tmr10ms()`. GaugeV2's
smoothing multiplies by 10 for a correct milliseconds time constant.

## 5. `getFieldInfo()` quirks

- Does **not** return `prec`; sensor precision must come from
  `model.getSensor(i).prec` (cached on source change).
- Names can start with an invalid character on some firmware (workaround from
  GaugeRotary's `lib_widget_tools.lua`).

## 6. GaugeRotary reference implementation

Source: https://github.com/offer-shmuely/edgetx-x10-widgets (WIDGETS/GaugeRotary)

- **Auto source discovery**: pick the first existing sensor from a priority
  list as the Source default (`findSourceId`). GaugeV2 now defaults to
  RSSI/RQly/RxBt/Cels/TxBt.
- Extended preset table (1RSS/2RSS −120..0, RQly, cell 3.5–4.2, Fuel, Vibr,
  Tmp1/Tmp2) — merged into GaugeV2 presets.
- Telemetry availability via `getRSSI() > 0` — GaugeV2 now distinguishes
  `disconnected` (link down) from `unavailable` (sensor missing, link up).
- `Min=-1/Max=-1` sentinel for auto ranges — GaugeV2 uses explicit defaults +
  persistent presets instead (no sentinel ambiguity).

## 7. Contest-winning LVGL widget (EdgeTX Lua LVGL contest #8/#9)

Source: https://github.com/agnauck/EdgeTX-Widgets (WIDGETS/Dashboard)

- Dynamic label `text` closures are the documented idiom (re-evaluated by
  `callRefs` each frame). GaugeV2 keeps explicit string-compare + `lvgl.set`
  for lower per-frame cost.
- **Timer sources display as hh:mm:ss** — adopted.
- Deeply nested `children` build trees work in practice; GaugeV2 keeps flat
  object creation for readability and instruction economy.
- "Keep the last known value on telemetry loss" — already GaugeV2 behavior.

## 8. Distribution: EdgeTX/lua-scripts gallery

Source: https://github.com/EdgeTX/lua-scripts

- The official home for community Lua apps/widgets is the **gallery repo**
  (`scripts.json` manifest); widgets stay in their own repos and are listed
  via an issue template ("Add a Lua App or Widget to the Gallery").
- EdgeTX-sdcard `dev/WIDGETS` also exists but is for dev examples.
- GaugeV2 will be distributed from the fork repo + listed in the gallery.

## 9. Grafana gauge design semantics

Source: Grafana docs (Gauge visualization)

- Min/max define the arc; null shows "-" (GaugeV2 matches).
- "Neutral value" (fill from 0 instead of min) — useful for bipolar ranges;
  candidate for a future option.
- Segmented arcs + segment spacing — future "Segmented" style candidate.
- Endpoint markers (needle/point) — GaugeV2's line needle covers this.

## 10. LVGL 8.4 (vendored)

- `radio/src/thirdparty/lvgl` is LVGL 8.4.1.
- Arc angles are normalized mod 360 (`if (start > 360) start -= 360`), so the
  135..405 range is safe.
- Native LVGL scale widgets exist in 8.x but are **not** exposed by EdgeTX's
  Lua binding — GaugeV2 builds ticks from `lvgl.line` objects.

## 11. W3C accessibility (applied)

- Color is never the only indicator: WARN/CRIT/NO DATA text + markers + color.
- Contrast: state colors derive from theme roles; critical uses RED.
- No blinking (GaugeRotary blinks "Disconnected..."; GaugeV2 does not).

## 12. Ecosystem survey

Source: https://edgetx.org/lua-scripts (gallery manifest)

- No dedicated analog telemetry gauge exists in the official gallery —
  GaugeV2 fills a gap.
- WidgetTx (widgettx.com) and EdgeTX-Goodies are additional distribution
  channels worth listing later.

## 13. Firmware call-site verification

- `widgets_container.cpp:refreshWidgets()` — foreground/background split
  confirmed.
- `luaGetSourceValue` returns (value, isCurrent, isFresh); telemetry sources
  return no value when the sensor is unavailable — the availability model is
  built on that.
