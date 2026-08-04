# Gauge V2 — EdgeTX responsive analog-digital telemetry widget

> **Full user & technical reference: [`DOCS.md`](DOCS.md)**

A modern successor to the community `GaugeRotary` widget: a responsive
analog-digital instrument for EdgeTX color radios (LVGL, EdgeTX 2.11+,
developed against EdgeTX 3.0).

`WIDGETS/GaugeV2/` mirrors the SD-card layout — copy the folder to the radio's
`WIDGETS/` directory (or into the Companion simulator SD content) and add the
widget to a color-LCD screen.

## Features

- Configurable telemetry source (numeric and battery-cell `CELLS` tables)
- Auto source discovery: defaults to the first available of RSSI/RQly/RxBt/Cels/TxBt
- Manual minimum, maximum, warning and critical values
- High-is-good / low-is-good direction
- 270-degree dial: track, active progress arc, line needle, pivot, adaptive ticks
- Semantic states: `NORMAL` / `WARN` / `CRIT` with color + text redundancy
- Color modes: Static, Threshold (default), Sections
- Styles: Auto, Needle, Arc
- Responsive layouts: micro, compact, normal, large + square, horizontal, vertical, fullscreen
- Historical minimum/maximum markers and (large mode) text
- Precision: Auto (sensor precision) or 0/1/2 decimals
- Timer sources display as hh:mm:ss; elapsed countdown timers color the
  gauge warning (official Value widget behavior); tx-voltage shows "V"
- Source-aware availability: local sources keep working without telemetry;
  distinguishes link-down (`disconnected`), sensor-lost (`stale`),
  missing sensor (`unavailable`), and retains the last known value
- Frame-independent needle smoothing (digital value updates instantly)
- Known-sensor presets (RSSI, 1RSS/2RSS, RQly, RxBatt, TxBatt, cell, temperature,
  RPM, fuel, vibration)
- Theme integration: colors derive from `COLOR_THEME_*` roles

## Options

| Option | Type | Default | Notes |
|---|---|---|---|
| Source | source | auto | first available of RSSI/RQly/RxBt/Cels/TxBt (firmware-resolved) |
| Min / Max | integer | 0 / 100 | |
| Warn / Crit | integer | 55 / 35 | |
| HighGood | bool | on | higher is better |
| Style | choice | Auto | Auto: needle ≥ compact size, arc in micro |
| ColorMode | choice | Threshold | Static / Threshold / Sections |
| Precision | choice | Auto | Auto = sensor precision, or 0/1/2 decimals |
| ShowMinMax | bool | on | history markers; text in large mode |

Option display names in the settings dialog are localized via the
`translate` callback. The Source default is a name list resolved by the
firmware ("first available", the official mechanism).

Presets initialize ranges only when the source changes and the range options
are still at their defaults; explicit user values are never overridden.

## Compatibility

- Requires EdgeTX 2.11 or later (LVGL Lua API). On older firmware the widget
  reports an error instead of failing silently.
- No legacy `lcd` renderer is provided.
- Developed against EdgeTX 3.0 on this fork (`radio/src/lua`).

## Architecture

| File | Responsibility |
|---|---|
| `main.lua` | registration, options, lifecycle, module loading, config/ranges/layout signatures |
| `geometry.lua` | clamp/normalize, value-to-angle, circle points, tick/line points (pure Lua) |
| `ranges.lua` | threshold ordering and state detection (pure Lua) |
| `presets.lua` | known-sensor profiles (pure Lua) |
| `telemetry.lua` | source metadata cache, value reading, table aggregation, availability model, flight history |
| `layout.lua` | responsive mode/aspect classification, geometry, typography, visibility |
| `renderer.lua` | retained LVGL objects, per-frame property-only updates |
| `dev/api_spike.lua` | LVGL API feasibility widget for Companion/hardware |
| `dev/RESEARCH.md` | web/ecosystem research notes behind the design decisions |

Modules are loaded with `loadScript()` from the widget folder (the officially
documented memory pattern). The renderer creates objects once in `update()` and
changes only properties that actually changed in `refresh()`.

## Distribution

The widget lives in this repo; to list it in the official EdgeTX gallery
(edgetx.org/lua-scripts), open an "Add a Lua App or Widget to the Gallery"
issue at https://github.com/EdgeTX/lua-scripts with a description and
screenshots (same process used for the Recovery QR widget).

## Testing

Headless tests run with stock Lua 5.3 (the same version EdgeTX embeds) —
no firmware needed:

```sh
lua5.3 tests/run_tests.lua  <widget-dir>/     # geometry + ranges unit tests
lua5.3 tests/smoke_test.lua <widget-dir>/     # full lifecycle vs mock lvgl
```

The smoke test drives the real widget code through `create`/`update`/
`refresh` against a mock EdgeTX environment that enforces the real binding's
property allow-lists, `{x,y}` point arrays, missing string metatable, and
10 ms `getTime()` ticks: build, states, no-data, table aggregation, presets,
history, resize, smoothing, fullscreen, timers, link-state detection.

## Known limitations

- "Sensor lost" window handling: `getSourceValue()`'s `isCurrent` flag decides
  staleness; the exact timeout is firmware-defined.
- Threshold boundary coloring is first-match-wins (conservative).
- Unit display covers the common TelemetryUnit values; unknown units show none.
- Widget options are at the 2.11+ limit of 10; new options must replace one.
- Trend, peak hold, selectable needle shapes, segmented arc, neutral-value
  fill and interactive min/max reset are planned for later versions
  (see `PLAN.md`).

## License

GPLv2 — see the header of each file.
