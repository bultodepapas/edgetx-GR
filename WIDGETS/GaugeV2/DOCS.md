# Gauge V2 — User & Technical Reference

**Version:** 1.0 (matches widget code on branch `feat/gauge-v2`)
**Target:** EdgeTX 2.11+ color radios (LVGL), developed against EdgeTX 3.0
**Language:** Lua (LVGL rendering path, no legacy `lcd` renderer)
**License:** GPLv2

---

## 1. Overview

Gauge V2 is a responsive analog-digital telemetry instrument for EdgeTX
color-LCD radios. It renders a 270-degree dial with an active progress arc,
an optional line needle and pivot, adaptive tick marks, semantic
normal/warning/critical coloring, and a value readout. It is a modern,
documented, tested successor to the community `GaugeRotary` widget.

The widget is written entirely in Lua against the LVGL Lua binding and works
with any numeric telemetry source, timers, and numeric sources in general
(sticks, channels, gvars, TX battery). The same folder tree that lives in
this repository is the folder that goes on the SD card — there is no build
step.

## 2. Requirements

- EdgeTX **2.11 or later** (the LVGL Lua API). On older firmware the widget
  raises an error during creation instead of failing silently.
- A color-LCD radio or the Companion Simulator.
- No dependencies besides the firmware's standard Lua API.

## 3. Installation

1. Copy the `GaugeV2` folder (containing `main.lua` and the companion
   modules) to the SD card's `WIDGETS/` directory, so the radio sees
   `/WIDGETS/GaugeV2/main.lua`.
2. In Companion: place the folder inside the SD-card content structure
   (model settings → SD card, `WIDGETS/GaugeV2`), or enable a real SD card
   and copy the folder onto it.
3. Power the radio (or restart the Simulator) so the widget list refreshes.
4. On a main screen: **long-press** an empty widget slot → **Widgets** →
   add a widget → pick **GaugeV2** → configure it.

## 4. Usage

### 4.1 Options

The widget exposes ten options (the maximum the 2.11+ widget settings UI is
designed for; the firmware data structure allows up to 50).

| Option | Type | Default | Range / Choices | Meaning |
|---|---|---|---|---|
| **Source** | Source | *auto* | any radio source | Telemetry sensor, timer, or local source. Default resolves to the first available of RSSI, RQly, RxBt, Cels, TxBt (firmware-resolved). |
| **Minimum** | Integer | 0 | −10000 … 10000 | Dial scale minimum. |
| **Maximum** | Integer | 100 | −10000 … 10000 | Dial scale maximum. |
| **Warning** | Integer | 55 | −10000 … 10000 | Warning threshold. |
| **Critical** | Integer | 35 | −10000 … 10000 | Critical threshold. |
| **High is good** | Bool | On | On / Off | Direction: higher = better (Off inverts the state bands). |
| **Style** | Choice | Auto | Auto, Needle, Arc | Needle visibility (see 4.3). |
| **Colors** | Choice | Threshold | Static, Threshold, Sections | Color behavior (see 4.4). |
| **Precision** | Choice | Auto | Auto, 0, 1, 2 | Decimals. Auto follows the sensor's precision (see 6.5). |
| **Show min/max** | Bool | On | On / Off | Flight history markers; large mode also shows MIN/MAX text. |

Notes:

- Option names shown in the settings dialog are the friendly names above
  (provided through the `translate` callback).
- **Warning/Critical are clamped into [Minimum, Maximum]**; if they are
  equal, the warning band collapses to zero width and the scale shows only
  normal and critical bands.
- If **Minimum > Maximum**, the two are swapped automatically (the scale is
  always ascending). Full mirroring of inverted ranges is planned (see 9).
- Setting any range option away from its default permanently disables
  presets for that source until the ranges are restored to defaults.

### 4.2 Source presets

When the **Source** changes and the four range options (Min/Max/Warn/Crit)
still hold their global defaults, the widget applies a known-sensor profile.
Explicitly customized ranges are never overridden.

| Sensor name(s) | Unit | Min | Max | Warn | Crit | Direction |
|---|---|---|---|---|---|---|
| RSSI, RSSI1–3 | dB / dBm | 0 | 100 | 55 | 35 | high-good |
| 1RSS, 2RSS | dBm | −120 | 0 | −80 | −95 | high-good |
| RQly, RQly%, VFR, VFR% | % | 0 | 100 | 55 | 35 | high-good |
| RxBt, RxBatt, Batt | V | 0 | 8.4 | 3.7 | 3.5 | high-good |
| TxBat, TxBatt, Battery, tx-voltage | V | 0 | 8.4 | 6.8 | 6.4 | high-good |
| Cell, Cells, Cels | V | 3.5 | 4.2 | 3.7 | 3.5 | high-good |
| Tmp, Temp, T1, T2, Temperature, Tmp1, Tmp2 | °C / °F | 0 | 120 | 70 | 90 | low-good |
| RPM, RPMs, Turbine | rpm | 0 | 20000 | 16000 | 18000 | low-good |
| Fuel | % | 0 | 100 | 30 | 15 | high-good |
| Vibr, Vibration | % | 0 | 100 | 40 | 60 | low-good |

Matching is by normalized sensor name first (case- and punctuation-
insensitive), then by unit as a fallback for telemetry sources. Preset values
are kept across later updates (resize, fullscreen, settings visits) so they
never revert to the global defaults mid-flight.

### 4.3 Style (needle)

- **Auto** — a needle is drawn in compact, normal, and large zones; micro
  zones use the progress arc only (no needle, no pivot).
- **Needle** — always draw the needle and pivot.
- **Arc** — never draw the needle; the active progress arc alone indicates
  the value.

### 4.4 Color modes

- **Static** — the dial, arc, needle, and value text always use the theme
  primary color; state bands are ignored for coloring.
- **Threshold** (default) — colors reflect the semantic state (see 4.6).
- **Sections** — the track is drawn as three separate arcs colored by the
  state bands (normal/warning/critical); the needle/value colors still
  reflect the current state.

### 4.5 Responsive layouts

The widget classifies the widget zone by size and aspect ratio (thresholds
are multiplied by `lvgl.LCD_SCALE`, so "micro" always means the same physical
size on every screen):

| Mode | Zone side (min(w,h)) | Behavior |
|---|---|---|
| micro | < 64 px | Dial + value only. No needle, unit, state text, name, or markers. |
| compact | < 105 px | Adds unit. Value font is fit to the available space. |
| normal | < 180 px | Adds source name and state text. |
| large | ≥ 180 px | Adds MIN/MAX text row. More ticks (7 vs 5 vs 3). |

Orientation by aspect ratio: **horizontal** (w/h > 1.4) places the dial left
and the text block right; **vertical** (w/h < 0.8) places the dial on top and
the text below; **balanced** centers the dial with the name below the dial
and the value inside the lower part of the dial circle.

### 4.6 States and colors

A value is mapped onto the configured bands:

- **NORMAL** — theme primary color.
- **WARN** — `COLOR_THEME_WARNING`; text label "WARN".
- **CRIT** — fixed high-contrast red (`RED`); text label "CRIT".
- **NO DATA** — `COLOR_THEME_DISABLED` at reduced opacity; text label
  "NO DATA"; the needle hides; the last known value stays on screen.

Boundary comparison is first-match-wins over the ordered bands
(normal/warning/critical or the inverted order for low-is-good sources),
which is deliberately conservative. Values outside [Min, Max] take the state
of the nearest boundary band.

### 4.7 Special sources

- **Timers** (sources named `timer1`…`timer3`, `T1`–`T3`) and **tx-time**
  display as `hh:mm:ss`; a negative value (an elapsed countdown timer) is
  prefixed with `-` and colors the whole gauge **warning** (matching the
  official EdgeTX Value widget).
- **tx-voltage** shows the unit **V** and forces one decimal.
- **Table sources** such as `CELLS` are aggregated by averaging their
  numeric entries; non-numeric tables (e.g. GPS, date/time) show NO DATA.
- **Local sources** (sticks, channels, gvars, TX battery) are always
  current and keep working without telemetry enabled.

### 4.8 No-data behavior

The widget distinguishes:

| Availability | Meaning | Value display |
|---|---|---|
| `unset` | no source configured | `-` |
| `invalid` | source id does not resolve | last known, else `-` |
| `valid` | fresh, current data | live value |
| `stale` | sensor reported but no longer current (link alive) | last known |
| `disconnected` | telemetry link down (`getRSSI() == 0`) | last known |
| `unavailable` | no value at all (link alive) | last known |

The last known value is retained across `stale` / `disconnected` /
`unavailable` frames and is cleared when the source or the ranges change, so
a new source never shows old data. After reconnection the needle snaps to
the current value instead of animating from zero.

## 5. Technical reference

### 5.1 Architecture

The widget is split into small modules so that geometry, state, and layout
math are pure Lua and testable off-radio; only `main.lua` and `renderer.lua`
touch firmware APIs.

| File | Responsibility |
|---|---|
| `main.lua` | Registration, options, `translate`, lifecycle (`create`/`update`/`refresh`), module loading, config/ranges/layout signatures. |
| `geometry.lua` | Clamp/normalize, value→angle, point-on-circle, line/tick point builders. Pure Lua. |
| `ranges.lua` | Band ordering and state detection. Pure Lua. |
| `presets.lua` | Known-sensor profiles and matching. Pure Lua. |
| `telemetry.lua` | Source metadata cache, value reading, table aggregation, availability model, flight history. |
| `layout.lua` | Mode/aspect classification, dial geometry, typography, element visibility. |
| `renderer.lua` | Retained LVGL object tree; per-frame property-only updates. |
| `dev/api_spike.lua` | LVGL API feasibility widget for Companion/hardware. |
| `dev/RESEARCH.md` | Web/ecosystem research notes behind the design decisions. |
| `tests/` | Headless test suites (see 7). |

Modules are loaded with `loadScript(widget.path .. name .. ".lua", "bt")` —
the officially documented pattern for widget-folder modules; each module
returns a table. `renderer.lua` receives the geometry module through an
explicit `setup()` call.

### 5.2 Lifecycle

The widget registers `{ name, options, translate, create, update, refresh,
useLvgl = true }`.

- **`create(zone, options, path)`** — validates `lvgl` availability, builds
  the state tables (source, data, history, smoothing, ranges, config,
  layout, UI object refs, per-frame cache), and loads all modules. Errors on
  missing modules instead of failing silently.
- **`update(widget, options)`** — runs on every options or size change:
  1. Parse options into `config` (choice strings are mapped to indices via
     the official `etxcst` constants).
  2. Resolve the source (cached metadata, see 6.4) and apply presets if the
     ranges are still at defaults.
  3. Resolve precision (Auto → sensor precision).
  4. Build the semantic ranges; if the range signature changed, reset
     history and smoothing.
  5. Compute the layout; if the layout signature changed (mode,
     orientation, needle visibility, color mode, markers), clear LVGL and
     rebuild the whole object tree; if only the source changed, update the
     source/unit labels in place.
- **`refresh(widget, event, touch)`** — per frame: read telemetry, then
  update only the LVGL properties that changed. Returns immediately when the
  UI has not been built.
- **`background()` is intentionally not provided.** The firmware only calls
  `background()` while the widget is **off-screen**, so flight history and
  data maintenance run in `refresh()` (see 6.6).

### 5.3 Rendering model

`renderer.lua` uses **retained objects**: `build()` creates every LVGL
object once via individual constructor calls (`lvgl.arc{…}`, `lvgl.line{…}`,
`lvgl.circle{…}`, `lvgl.label{…}` — deliberately not `lvgl.build()` tables,
to avoid luac nesting pitfalls), and `update()` mutates only properties that
actually changed, guarded by a per-frame cache (`widget.frame`). This keeps
per-frame work minimal and well inside the firmware's instruction budget.

Object tree per zone:

| Object | Count | Created when |
|---|---|---|
| Track arc (or 3 section arcs) | 1 (3) | always |
| Tick lines | 3 / 5 / 7 | always |
| Value arc | 1 | always |
| Needle line + pivot circle | 2 | layout shows needle |
| Min/max marker lines | 2 | Show min/max and mode ≥ compact |
| Value label | 1 | always |
| Unit label | 1 | mode ≥ compact |
| Name label | 1 | mode ≥ normal |
| State label | 1 | mode ≥ compact |
| Min/max text labels | 2 | Show min/max and mode = large |

Per-frame changes: arc `endAngle`, needle `pts` (only when the angle
changed), object `color`/`opacity`, label `text`/`x`/`w`/`h` (only when the
string changed), and hide/show for the needle on data loss.

### 5.4 Dial geometry

- Angle convention matches LVGL: **0° = 3 o'clock, angles increase
  clockwise** (screen y points down).
- The dial spans **135° to 405°** (a 270° sweep starting at 7:30 through
  12:00 to 1:30). The binding auto-normalizes 405° to 45°; the code uses the
  absolute form so intermediate values stay exact.
- Value → angle: `135 + clamp((v − min) / (max − min), 0, 1) * 270`,
  rounded to the nearest integer degree (minimum == maximum maps to 0).
- Tick angles are distributed evenly across the sweep; tick count is 3
  (micro), 5 (compact/normal), or 7 (large), including both ends.
- Lines are described by `{x, y}` point-pair arrays — the exact format the
  EdgeTX binding reads (`rawgeti(pt, 1)` / `rawgeti(pt, 2)`); named
  `{x = …}` points fail on the radio.
- All physical sizes are multiplied by `lvgl.LCD_SCALE` (0.8 on 320 px-wide
  screens, 1.0 on 480 px, 1.375 on 800 px) via `px()`, so the gauge looks
  proportionally identical across radio classes.

### 5.5 Typography

Fonts are `LcdFlags` with the font index in bits 8–11 — the same convention
the firmware itself uses (`getFont(index << 8)` in the official widgets):

| Alias | LcdFlag | Used for |
|---|---|---|
| STD | `STDSIZE` (0) | — |
| BOLD | `BOLD` (0x100) | — |
| XXS | `TINSIZE` | unit (compact), min/max text |
| XS | `SMLSIZE` | unit (≥ compact), name, state, value (micro) |
| L | `MIDSIZE` | value candidates |
| XL | `DBLSIZE` | value candidates |
| XXL | `XXLSIZE` | value candidates |
| LXL | `XLSIZE` | — |

The value font is **auto-fit**: the renderer picks the largest candidate
whose measured height fits the value area for the current orientation and
mode. Text is horizontally centered with `lcd.sizeText()` measurements
(cached per change).

### 5.6 Range and state math (`ranges.lua`)

`build(min, max, warn, crit, highGood)` returns three ordered bands with
thresholds clamped into [min, max]:

- high-is-good: `critical [min…lo]`, `warning [lo…hi]`, `normal [hi…max]`
- low-is-good: `normal [min…lo]`, `warning [lo…hi]`, `critical [hi…max]`

where `lo = min(warn, crit)` and `hi = max(warn, crit)`.
`determineState(value, bands)` returns the first band containing the value,
else the nearest boundary band.

### 5.7 Telemetry engine (`telemetry.lua`)

**Source resolution** (cached, runs only when the source id changes):

- `getFieldInfo(id)` → name (cleaned of leading invalid bytes), unit,
  telemetry flag; timer flag from the name.
- Unit display strings come from a table covering the common
  `TelemetryUnit` values (V, A, mA, kts, m/s, ft/s, km/h, mph, m, ft, C, F,
  %, mAh, W, mW, dB, rpm, g, deg, rad, ml, floz, ml/min, Hz, ms, us, km,
  dBm); unknown units display no unit text.
- Sensor precision (`prec`) is not exposed by `getFieldInfo`; it is looked
  up once through `model.getSensor(i)` (sensors 0–31) and cached.

**Value reading** per frame:

- `getSourceValue(id)` → number, table, or nil.
- Tables: numeric entries are averaged (CELLS-style aggregation);
  non-numeric tables yield NO DATA.
- `current == false` with a telemetry source ⇒ `stale`.
- `value == nil` ⇒ `disconnected` if `getRSSI() == 0`, else `unavailable`.

**Flight history** — `min`/`max` of the displayed value since the last
source/range change, maintained in `refresh()` because `background()` only
runs while the widget is off-screen.

**Smoothing** — the needle is smoothed with an exponential filter
(`factor = 1 − exp(−dt/140 ms)`, `getTime()` converted from 10 ms ticks to
milliseconds, dt clamped to 1–1000 ms) so it glides while the digital value
updates instantly. The smoothed value is reset on source/range change and
snapped on reconnection.

### 5.8 Performance discipline

- Per-callback instruction budget: **20,000 instructions** (firmware
  `MAX_INSTRUCTIONS`, `lua_widget_factory.cpp`).
- `refresh()` never creates objects, never allocates per-frame tables, and
  skips `lvgl.set` calls when the cached value/string/angle is unchanged.
- `update()` rebuilds the object tree only when the layout signature
  changes; label-only changes are applied in place.
- The whole large-mode object tree stays well under 60 LVGL objects.

### 5.9 Binding compatibility notes

Facts verified against `radio/src/lua` (this fork, EdgeTX 3.0):

- `lvgl.arc` accepts absolute `startAngle`/`endAngle` plus
  `bgStartAngle`/`bgEndAngle`, `color`/`bgColor`, `bgOpacity`/`opacity`,
  `thickness`, `rounded`; angle 405 auto-normalizes to 45.
- `lvgl.line` re-applies `pts` via `lvgl.set`; points must be `{x, y}`
  pairs (see 5.4).
- `lvgl.circle` does **not** accept `bgColor`/`bgOpacity`; the pivot uses
  `filled = 1` with `color`.
- `lvgl.label` accepts `text`, `color`, `font` (index `<< 8`), `x`, `y`,
  `w`, `h`.
- **String methods are unavailable** (`s:lower()` fails on builds without
  the string metatable); the code always uses `string.lower()`,
  `string.gsub()`, etc.
- `getTime()` returns **10 ms ticks**; all time math converts explicitly.
- Option types use the official constants (`SOURCE`, `VALUE`, `BOOL`,
  `CHOICE`); `CHOICE` is **10** in `WidgetOption::Type` (9 is Slider).
- A **table as the Source option default** (name list) is resolved natively
  by the firmware as "first available" (`lua_widget_factory.cpp`
  `sourceValue()`).
- Colors are theme roles (`COLOR_THEME_PRIMARY1`, `COLOR_THEME_WARNING`,
  `COLOR_THEME_DISABLED`, `COLOR_THEME_SECONDARY1..3`, `RED`), so the gauge
  follows dark/light/high-contrast themes automatically.

## 6. Data flow (per frame)

```
refresh()
 └─ telemetry.refresh(widget)
 │    └─ getSourceValue(source) → value / table / nil
 │    └─ availability model (valid/stale/disconnected/unavailable/unset)
 │    └─ determineState(value, ranges) → normal|warning|critical
 │    └─ flight history min/max update
 └─ renderer.update(widget)
      └─ color key (muted|static|normal|warning|critical, timers < 0 ⇒ warning)
      └─ applyColors only when the key changed
      └─ value label (hms for timers, precision for numbers) when changed
      └─ state label ("WARN"/"CRIT"/"NO DATA") when changed
      └─ needle angle (smoothed) when changed; hide/show on data loss
      └─ min/max markers when their angles changed
      └─ MIN/MAX text row when changed (large mode)
```

## 7. Testing

Headless suites run with stock Lua 5.3 (the version EdgeTX embeds) — no
firmware or simulator needed:

```sh
lua5.3 tests/run_tests.lua  <widget-dir>/   # geometry + ranges unit tests (14)
lua5.3 tests/smoke_test.lua <widget-dir>/   # full lifecycle vs mock lvgl (29)
```

The smoke suite drives the real widget code through create/update/refresh
against a mock EdgeTX environment that enforces the real binding's property
allow-lists, `{x, y}` point arrays, the missing string metatable, and 10 ms
`getTime()` ticks. Coverage: rendering, state colors, no-data, table
aggregation, precision, all layout modes, resize, presets, custom-range
defeat, history markers, smoothing, fullscreen, timer formatting, link-state
detection, elapsed-timer warning color, and tx-voltage/tx-time handling.

## 8. Distribution

- The widget ships from this repository; the folder is the SD-card payload.
- To list it in the official EdgeTX gallery (edgetx.org/lua-scripts), open
  an "Add a Lua App or Widget to the Gallery" issue at
  https://github.com/EdgeTX/lua-scripts with a description and screenshots.
- A patch to the `EdgeTX/edgetx-sdcard` repository (`dev/WIDGETS/GaugeV2/`)
  is the ecosystem path for firmware-adjacent Lua widgets.

## 9. Known limitations and roadmap

- "Sensor lost" staleness relies on `getSourceValue()`'s `current` flag; the
  exact timeout is firmware-defined.
- Threshold boundary coloring is first-match-wins (conservative).
- Unit text covers the common TelemetryUnit values; unknown units show none.
- The 10-option settings-UI limit is reached; new options must replace an
  existing one.
- Inverted ranges swap min/max but do not mirror the value (the official
  gauge's mirror transform is degenerate for asymmetric ranges; proper
  mirroring is planned).
- Optional label shadows and alignment options (present in the official
  Value widget) are not implemented — shadows are not exposed by the Lua
  binding, and alignment would need an option slot.
- Planned: trend/peak hold, selectable needle shapes, segmented arc,
  neutral-value fill, interactive min/max reset, inverted-range mirroring
  (see `PLAN.md`).

## 10. License

GPLv2 — see the header of each file.
