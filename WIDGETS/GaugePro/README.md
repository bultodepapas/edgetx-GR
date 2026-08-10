# Gauge Pro — EdgeTX responsive telemetry instrument

> **Full user & technical reference: [`DOCS.md`](DOCS.md)**
> **Every option, in one image: [`docs/gauge-pro-options.png`](docs/gauge-pro-options.png)**
> **Design & engineering plan: [`IMPROVEMENT_PLAN.md`](IMPROVEMENT_PLAN.md)**
> **Bar experience roadmap: [`BAR_STYLE_IMPROVEMENT_PLAN.md`](BAR_STYLE_IMPROVEMENT_PLAN.md)**

A modern successor to the community `GaugeRotary`: a responsive
analog-digital instrument for EdgeTX color radios (LVGL, EdgeTX 2.11+,
developed against EdgeTX 3.0).

*(Developed under the name `GaugeV2`; the folder, the widget name and the
option defaults all moved to `GaugePro` before release, so no model config
carries the old name.)*

`WIDGETS/GaugePro/` mirrors the SD-card layout — copy the folder to the radio's
`WIDGETS/` directory (or into the Companion simulator SD content) and add the
widget to a color-LCD screen.

It is the only EdgeTX widget that draws with the **LVGL retained-object API**
(`lvgl.arc`, `lvgl.triangle`, `lvgl.line`) rather than the legacy `lcd`
renderer, so one folder serves every screen size with no per-resolution
assets.

## Every option, in one image

[![Gauge Pro — every option and every state](docs/gauge-pro-options.png)](docs/gauge-pro-options.png)

**[`docs/gauge-pro-options.png`](docs/gauge-pro-options.png)** — 222 scenes
covering every option, every state, every colour mode and every zone size an
EdgeTX layout can hand out, on EdgeTX's **stock theme**.
[`docs/gauge-pro-options-dark.png`](docs/gauge-pro-options-dark.png) is the same
sheet on a dark theme, and
[`docs/gauge-pro-options-highcontrast.png`](docs/gauge-pro-options-highcontrast.png)
is the explicit high-contrast fixture. All three are also committed as SVG
([stock](docs/gauge-pro-options.svg), [dark](docs/gauge-pro-options-dark.svg),
[high contrast](docs/gauge-pro-options-highcontrast.svg))
if you want to zoom in without artefacts.

Nothing in those images is a mock-up: every tile is the widget's own LVGL
object tree, built by the real code from the real option values and emitted as
SVG. Regenerate with `lua5.3 dev/collage.lua ./ docs/`.

Phase 6's ordered motion evidence is
[`docs/phase6/motion/motion-filmstrip-stock.png`](docs/phase6/motion/motion-filmstrip-stock.png),
with matching [dark](docs/phase6/motion/motion-filmstrip-dark.png) and
[high-contrast](docs/phase6/motion/motion-filmstrip-highcontrast.png) sheets.
They are deterministic frames from the same production object tree, not an
animation mock-up.

## Features

- Any numeric source: telemetry sensors, timers, sticks, channels, gvars, TX
  battery — with auto-discovery of the first available of RSSI/RQly/RxBt/
  Cels/TxBt
- Dial with threshold rail, progress arc, **three-segment tapered needle**,
  pivot ring, adaptive major/minor ticks, scale end labels
- **Continuous Precision Rail bar** for wide/short zones: self-grounding casing,
  permanent severity context, exact position head, independent min/max/ghost
  history, and the same value hierarchy and safety badge as the dial
- Bar personalization: nine purposeful appearance presets, four real thickness
  levels, round/square/true-chamfer ends, transparent/theme/custom panels,
  Classic, Theme Adaptive, Custom Three and Custom Two palettes, and exact
  authored colors
- A real **spatial Gradient bar** built from 8–24 budget-aware, gapless,
  retained slices; it keeps explicit thresholds, an exact partial slice and
  the exact position head on ascending, descending and low-is-good scales
- Four production segmented reading models: truthful partial **Blocks**,
  three-primitive **Hex** cells, threshold-aligned major/minor **Fine Ticks**,
  and increasing-height **Signal Steps**. All retain the exact position head,
  every colour mode, live HTX themes, compact fallbacks and hard object caps
- A first-class orientation-neutral bar axis: every production face runs
  horizontally or vertically, including gradients, thresholds, exact head,
  zero notch and all three history markers
- Truthful **Zero origin** on signed and asymmetric scales, plus production
  **Dual Rail** for sticks/channels/trims/GVars: negative and positive spans
  grow independently around numeric zero instead of inventing a midpoint
- Configurable Position Head (None/Cap/Dot/Line/Needle), scale marks
  (Off/Thresholds/Ends/Full), value placement and name placement; tall Inside
  layouts reserve a separate information lane so text never crosses the rail
- Source-aware Auto appearance: RSSI/RQly-style links choose Steps, other
  signal metrics choose Ticks, battery sources choose Hex, and capacity-style
  sources choose Blocks; explicit user overrides always win
- Live HTX theme switching: theme candidates, track, panel, text, history,
  badge ink and gradient caches re-resolve in place without rebuilding
- Contrast assist Off / Auto / Strong: CVD-aware analysis strengthens casing,
  head and threshold structure while never modifying a saved custom color
- Four bounded Motion profiles: Off, Essential, Refined (default) and
  Expressive. Raw WARN/CRIT and badges are immediate; Refined adds a short
  exact-endpoint colour transition, truthful dropout fade, segment settle and
  a calm four-phase critical breath. Expressive adds a rearmable one-shot head
  emphasis and automatically reduces to Refined in micro/short zones
- Colour modes: Static, Threshold, **Rail** (default), **Gradient**, Sections
- Sweeps: 270°, 180°, 360°
- Semantic states with **hysteresis** (no flicker on a threshold), a filled
  state badge, and a critical pulse that survives greyscale
- A **status / data colour split**: the arc and badge carry the state, the
  numbers stay on the theme's own text role. The three state colours are fixed
  and measured to clear 3 : 1 on both a light and a dark background — see
  [`DOCS.md` §4.3](DOCS.md)
- **Peak-hold ghost** plus min/max markers, sourced from the radio's own
  `<sensor>-` / `<sensor>+` sensors where they exist
- **Battery intelligence**: cell-count detection, per-cell / total / average
  cell readings, and Li-Po/Li-Ion state-of-charge percentage
- **Alerts**: tone and haptic on state transitions, gated by a switch, a
  startup delay and a rate limit
- Reset min/max from a switch, in flight
- Normal-state colour, custom name and unit, shared gauge damping
- Responsive: micro / compact / normal / large × horizontal / vertical /
  balanced / fullscreen
- Availability model: distinguishes no source, stale sensor, link down and
  missing data; keeps the last known value; snaps the needle on reconnect
- Theme integration: semantic chrome/ink sources remain `COLOR_THEME_*` roles
  and re-resolve to the active HTX RGB values at runtime; exact custom colors
  remain authored values, and badges independently choose the better current
  theme ink

## Options

Ten options on EdgeTX 2.11 (the firmware limit there, in both the radio and
Companion), and all 44 on 2.12+. The original 24, Phase 1's 25–39 tail and
Phase 5's 40–44 presentation tail are independently frozen append-only
contracts; slots 45–50 remain reserved. The core ten keep fixed positions on every
firmware, so a model can move between versions without its settings shifting.

The labels are written for the radio's settings screen, where a label gets
about half the dialog width and wraps rather than clips. Names that used to
answer for each other — *Minimum* / *Maximum* against *Min / max* — now say
which is the **scale** and which is the **recorded peaks**, and *State chip*
became *Info badges*, because since the colour work it can no longer hide a
WARN or CRIT. See [`DOCS.md` §4.1](DOCS.md).

## Architecture

`main.lua` is boot-weight only — it is executed at radio startup for every
widget on the card, used or not. Everything else loads on first use:

| File | Responsibility |
|---|---|
| `main.lua` | option declarations, version gate, `lvgl` guard |
| `app.lua` | lifecycle, config → ranges → layout, rebuild decisions |
| `options.lua` | the option wire format (integers, 1-based choices, capacity) |
| `theme.lua` | design tokens and memoized text metrics |
| `bar_style.lua` | appearance presets, Auto/override resolution, palettes and signatures |
| `motion.lua` | retained motion profiles, bounded transitions, hidden-resume and responsive effect caps |
| `bar_faces.lua` | retained face interface, Continuous, Blocks, Hex, Fine Ticks, Steps and Dual Rail; horizontal/vertical/zero spans, gradients, responsive fallbacks and object ceilings |
| `geometry.lua`, `ranges.lua`, `presets.lua`, `format.lua`, `smoothing.lua` | pure Lua domain logic |
| `telemetry.lua` | sources, values, availability, history |
| `layout.lua` | classification, geometry, typography, regions |
| `renderer.lua`, `bar.lua` | retained LVGL trees, property-only updates |
| `alerts.lua` | transition alerts |

## Testing

Stock Lua 5.3, no radio needed:

```sh
lua5.3 tests/run_tests.lua  ./          # pure modules         (70 tests)
lua5.3 tests/smoke_test.lua ./          # lifecycle           (200 tests)
lua5.3 dev/collide.lua      ./          # geometric collision audit
lua5.3 dev/instructions.lua ./          # firmware callback budgets
lua5.3 dev/measure_frames.lua ./        # stopped-GC allocation probe
lua5.3 dev/motion_sequences.lua ./      # 48 temporal resource cases
lua5.3 dev/motion_filmstrip.lua ./ docs/phase6/motion/
lua5.3 dev/gallery.lua      ./ --out /tmp/g   # visual contract sheet + manifest
lua5.3 dev/collage.lua      ./ docs/    # the official option sheet (committed)
```

The mock enforces the firmware's real contract — property allow-lists per
object type, `{x, y}` point arrays, the missing string metatable, 10 ms
`getTime()` ticks, and the **integer option wire format with 1-based
choices**.

Three tools share one catalogue (`dev/scenes.lua`) and one emitter
(`dev/svgkit.lua`), so they cannot disagree about what the widget draws:

| Tool | Audience | Output |
|---|---|---|
| `dev/collage.lua` | users | the committed sheet in `docs/`, English, no diagnostics |
| `dev/gallery.lua` | review | contract sheet + manifest, overflow boxes, warning dots, option-coverage audit |
| `dev/shots.lua` | close-up | one SVG per scene |

The gallery renders every scene in stock and dark palettes plus a deterministic manifest;
the Phase 6 evidence also renders the explicit high-contrast palette
of what each scene resolved to — layout mode, availability, colour key, scale,
object census — and reports which widget options no scene ever varies. Use
`--baseline <manifest>` for a field-level diff of what a change moved. See
**DOCS.md §7.1–7.2** for the workflow and for how to add a scene, a source or
an option.

The palettes are EdgeTX's **real** ones: `stock` is `colors.cpp`'s
`defaultColors` byte for byte; dark and high-contrast fixtures exercise theme
role inversion and maximum separation. That matters more than it sounds — the tools
used to paint an invented palette, and it hid a normal state rendering at
1.13 : 1 on a stock radio for four review rounds.

`dev/preview.lua` is the older single-page preview (`dev/preview.html` is
generated — regenerate it rather than editing it).

## Compatibility

- EdgeTX 2.11+ (LVGL Lua API). On older firmware the widget registers and
  shows a compatibility message instead of vanishing from the model.
- No legacy `lcd` renderer.
- `destroy` is not a widget callback in EdgeTX and is not used.

## License

GPLv2 — see the header of each file.
