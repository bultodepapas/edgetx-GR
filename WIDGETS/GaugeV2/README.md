# Gauge V2 — EdgeTX responsive telemetry instrument

> **Full user & technical reference: [`DOCS.md`](DOCS.md)**
> **Design & engineering plan: [`IMPROVEMENT_PLAN.md`](IMPROVEMENT_PLAN.md)**

A modern successor to the community `GaugeRotary`: a responsive
analog-digital instrument for EdgeTX color radios (LVGL, EdgeTX 2.11+,
developed against EdgeTX 3.0).

`WIDGETS/GaugeV2/` mirrors the SD-card layout — copy the folder to the radio's
`WIDGETS/` directory (or into the Companion simulator SD content) and add the
widget to a color-LCD screen.

It is the only EdgeTX widget that draws with the **LVGL retained-object API**
(`lvgl.arc`, `lvgl.triangle`, `lvgl.line`) rather than the legacy `lcd`
renderer, so one folder serves every screen size with no per-resolution
assets.

## Features

- Any numeric source: telemetry sensors, timers, sticks, channels, gvars, TX
  battery — with auto-discovery of the first available of RSSI/RQly/RxBt/
  Cels/TxBt
- Dial with threshold rail, progress arc, **tapered triangle needle**, pivot
  ring, adaptive major/minor ticks, scale end labels
- **Linear bar style** for wide/short zones, chosen automatically where a dial
  cannot work
- Colour modes: Static, Threshold, **Rail** (default), **Gradient**, Sections
- Sweeps: 270°, 180°, 360°
- Semantic states with **hysteresis** (no flicker on a threshold), a state
  chip, and a critical pulse that survives greyscale
- **Peak-hold ghost** plus min/max markers, sourced from the radio's own
  `<sensor>-` / `<sensor>+` sensors where they exist
- **Battery intelligence**: cell-count detection, per-cell / total / average
  cell readings, and Li-Po/Li-Ion state-of-charge percentage
- **Alerts**: tone and haptic on state transitions, gated by a switch, a
  startup delay and a rate limit
- Reset min/max from a switch, in flight
- Accent colour, custom name and unit, needle damping
- Responsive: micro / compact / normal / large × horizontal / vertical /
  balanced / fullscreen
- Availability model: distinguishes no source, stale sensor, link down and
  missing data; keeps the last known value; snaps the needle on reconnect
- Theme integration: colours are `COLOR_THEME_*` roles

## Options

Ten options on EdgeTX 2.11 (the firmware limit there, in both the radio and
Companion), and 23 on 2.12+. The core ten keep fixed positions on every
firmware, so a model can move between versions without its settings shifting.
See [`DOCS.md` §4.1](DOCS.md).

## Architecture

`main.lua` is boot-weight only — it is executed at radio startup for every
widget on the card, used or not. Everything else loads on first use:

| File | Responsibility |
|---|---|
| `main.lua` | option declarations, version gate, `lvgl` guard |
| `app.lua` | lifecycle, config → ranges → layout, rebuild decisions |
| `options.lua` | the option wire format (integers, 1-based choices, capacity) |
| `theme.lua` | design tokens and memoized text metrics |
| `geometry.lua`, `ranges.lua`, `presets.lua`, `format.lua`, `smoothing.lua` | pure Lua domain logic |
| `telemetry.lua` | sources, values, availability, history |
| `layout.lua` | classification, geometry, typography, regions |
| `renderer.lua`, `bar.lua` | retained LVGL trees, property-only updates |
| `alerts.lua` | transition alerts |

## Testing

Stock Lua 5.3, no radio needed:

```sh
lua5.3 tests/run_tests.lua  ./     # pure modules        (38 tests)
lua5.3 tests/smoke_test.lua ./     # lifecycle          (129 tests)
lua5.3 dev/collide.lua      ./     # geometric collision audit
lua5.3 dev/gallery.lua      ./     # visual contract sheet + manifest
```

The mock enforces the firmware's real contract — property allow-lists per
object type, `{x, y}` point arrays, the missing string metatable, 10 ms
`getTime()` ticks, and the **integer option wire format with 1-based
choices**.

`dev/gallery.lua` renders every scene in the catalogue (`dev/scenes.lua`) into
one self-contained SVG in both the dark and light palettes, plus a
deterministic manifest of what each scene resolved to — layout mode,
availability, colour key, scale, object census. It also reports which widget
options no scene ever varies. Use `--baseline <manifest>` to get a field-level
diff of what a change moved. See **DOCS.md §7.1–7.2** for the workflow and for
how to add a scene, a source or an option.

`dev/shots.lua` writes the same scenes as individual SVGs for close-up review;
`dev/preview.lua` is the older single-page preview (`dev/preview.html` is
generated — regenerate it rather than editing it).

## Compatibility

- EdgeTX 2.11+ (LVGL Lua API). On older firmware the widget registers and
  shows a compatibility message instead of vanishing from the model.
- No legacy `lcd` renderer.
- `destroy` is not a widget callback in EdgeTX and is not used.

## License

GPLv2 — see the header of each file.
