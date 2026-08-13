# Gauge Pro — EdgeTX responsive telemetry instrument

> **Full user & technical reference: [`DOCS.md`](DOCS.md)**
> **Every option, in one image: [`docs/gauge-pro-options.png`](docs/gauge-pro-options.png)**
> **Design & engineering plan: [`IMPROVEMENT_PLAN.md`](IMPROVEMENT_PLAN.md)**
> **Bar experience roadmap: [`BAR_STYLE_IMPROVEMENT_PLAN.md`](BAR_STYLE_IMPROVEMENT_PLAN.md)**
> **Dial/Bar migration: [`MIGRATION.md`](MIGRATION.md)**
> **Development guardrails: [`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md)**
> **Current vs historical docs: [`DOCUMENTATION.md`](DOCUMENTATION.md)**
> **2026-08-13 beta/pre-PR review: [`docs/PRE-PR-BETA-REVIEW-2026-08-13.md`](docs/PRE-PR-BETA-REVIEW-2026-08-13.md)**

A modern successor to the community `GaugeRotary`: a responsive
analog-digital instrument for EdgeTX color radios (LVGL, EdgeTX 2.11+,
developed against EdgeTX 3.0).

*(Developed under the name `GaugeV2`; the folder, the widget name and the
option defaults all moved to `GaugePro` before release, so no model config
carries the old name.)*

## Public beta status

Gauge Dial Pro and Gauge Bar Pro are proposed as an explicit first public beta
in [EdgeTX/edgetx-sdcard PR #289](https://github.com/EdgeTX/edgetx-sdcard/pull/289).
They are not a final release. Back up the radio SD card and model configuration
before installing them, and do not use a widget as the only warning for a
flight-critical condition. Keep the radio's normal alarms and telemetry
failsafes enabled.

Beta testing is welcome on different color radios, EdgeTX versions, layouts,
themes and telemetry sources. Bug reports and requests for new features,
options or visual improvements should include:

- radio model and exact EdgeTX version;
- widget family (`DialPro` or `BarPro`), source and layout/zone;
- theme and non-default widget options;
- expected and actual behavior; and
- a screenshot or simulator log when available.

The current readiness verdict and remaining beta gates are recorded in the
[`2026-08-13 review`](docs/PRE-PR-BETA-REVIEW-2026-08-13.md).

The product now appears as two widgets: **Gauge Dial Pro** and **Gauge Bar Pro**.
Their EdgeTX registration IDs are `DialPro` and `BarPro` (the firmware limit is
10 characters), while their SD folders are `GaugeDialPro` and `GaugeBarPro`. Both
load the same versioned runtime from `/SCRIPTS/TOOLS/GaugeCore/`; they are not
forks. Install the exact SD layout with:

```powershell
pwsh dev/sync-sd.ps1 -Destination E:\                 # installs 2 new widgets
pwsh dev/sync-sd.ps1 -Destination E:\ -IncludeLegacy  # + GaugePro transition
```

See [`MIGRATION.md`](MIGRATION.md) before removing a legacy GaugePro folder.

The renderer uses EdgeTX's **LVGL retained-object API** (`lvgl.arc`,
`lvgl.triangle`, `lvgl.line`) rather than the legacy `lcd` renderer, so one
shared core serves every screen size with no per-resolution assets.

## Every option, in one image

[![Gauge Pro — every option and every state](docs/gauge-pro-options.png)](docs/gauge-pro-options.png)

**[`docs/gauge-pro-options.png`](docs/gauge-pro-options.png)** — 229 scenes
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

EdgeTX 2.11 exposes ten meaningful slots in each new widget. On 2.12+,
GaugeDialPro exposes 24 options and GaugeBarPro 42. Their shared slots 1–9 are
identical; slot 10 is `DialStyle` or `BarPreset`. Family-only controls never
appear in the other settings screen. All published contracts are append-only.

GaugePro legacy retains its historical 44-option contract during migration.
On an SD that already contains `/WIDGETS/GaugePro`, the default installer leaves
that folder untouched and emits a warning. Therefore the radio may temporarily
show three widgets until migration is complete and the legacy folder is removed
manually.

The labels are written for the radio's settings screen, where a label gets
about half the dialog width and wraps rather than clips. Names that used to
answer for each other — *Minimum* / *Maximum* against *Min / max* — now say
which is the **scale** and which is the **recorded peaks**, and *State chip*
became *Info badges*, because since the colour work it can no longer hide a
WARN or CRIT. See [`DOCS.md` §4.1](DOCS.md).

## Architecture

Development of the split Dial/Bar product is governed by
[`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md): user-visible widgets stay separate while shared
telemetry, state, colour, history, alerts and LVGL infrastructure remain a single core with
cross-family parity gates.

`main.lua` is boot-weight only — it is executed at radio startup for every
widget on the card, used or not. Everything else loads on first use:

| File | Responsibility |
|---|---|
| `GaugeDialPro/main.lua`, `GaugeBarPro/main.lua` | registration IDs `DialPro`/`BarPro`, visible labels, family options, `coreApi` and fixed core path |
| `app.lua` | lifecycle, config → ranges → layout, rebuild decisions |
| `options.lua` | the option wire format (integers, 1-based choices, capacity) |
| `theme.lua` | design tokens and memoized text metrics |
| `bar_style.lua` | appearance presets, Auto/override resolution, palettes and signatures |
| `motion.lua` | retained motion profiles, bounded transitions, hidden-resume and responsive effect caps |
| `bar_faces.lua` | retained face interface, Continuous, Blocks, Hex, Fine Ticks, Steps and Dual Rail; horizontal/vertical/zero spans, gradients, responsive fallbacks and object ceilings |
| `geometry.lua`, `ranges.lua`, `presets.lua`, `format.lua`, `smoothing.lua` | pure Lua domain logic |
| `telemetry.lua` | sources, values, availability, history |
| `layout_common.lua`, `ui_core.lua` | shared classification, typography, semantic UI and retained-property batching |
| `dial_layout.lua`, `dial_renderer.lua` | radial geometry and retained dial tree |
| `bar_layout.lua`, `bar.lua` | linear geometry and retained bar tree |
| `alerts.lua` | transition alerts |

`app.lua` loads `common + family`: GaugeDialPro never loads Bar modules, and
GaugeBarPro never loads Dial layout/renderer modules. GaugePro legacy composes
both during the transition.

## Testing

Stock Lua 5.3, no radio needed:

```sh
lua5.3 tests/run_tests.lua  ./          # pure modules         (72 tests)
lua5.3 tests/smoke_test.lua ./          # legacy lifecycle    (220 tests)
lua5.3 tests/widgets_test.lua ./        # split contracts      (17 tests)
lua5.3 dev/split_resources.lua ./       # chunks/RAM/callback gates
lua5.3 dev/collide.lua      ./          # geometric collision audit
lua5.3 dev/instructions.lua ./          # firmware callback budgets
lua5.3 dev/measure_frames.lua ./        # stopped-GC allocation probe
lua5.3 dev/motion_sequences.lua ./      # 48 temporal resource cases
lua5.3 dev/motion_filmstrip.lua ./ docs/phase6/motion/
lua5.3 dev/gallery.lua      ./ --out /tmp/g   # visual contract sheet + manifest
lua5.3 dev/collage.lua      ./ docs/    # the official option sheet (committed)
```

Real-firmware visual validation (from `tools/gaugepro-visual-kit/`):

```sh
python run.py check                   # contracts + split model YAML, no simu
python run.py capture --track2-only   # 8 real-firmware Dial/Bar layouts
python run.py all                     # 277 fresh captures + generated report
python verify_dupes.py                # expected/identical-frame audit
python settings_probe.py              # open/scroll the real Bar settings form
```

The 2026-08-13 review passed all **309 Lua tests**, static analysis, resource
budgets, collision checks, motion checks, package installation and the C++
simulator build. A later 277-screen simulator rerun ended with no runtime
failures, but its duplicate-frame audit found two unexpected groups caused by
dropped gallery navigation events. Those stale frames were not promoted over
the last clean committed visual-kit evidence. The runtime is a beta candidate;
the evidence rerun and a physical-radio smoke test remain open. See the
[`pre-PR review`](docs/PRE-PR-BETA-REVIEW-2026-08-13.md) for exact evidence.

The independent, opt-in Widget Studio automation hooks used during development
are proposed separately in
[EdgeTX/edgetx PR #7646](https://github.com/EdgeTX/edgetx/pull/7646). The widgets
do not depend on those hooks at runtime.

The native visual track declares real model telemetry sensors and feeds scalar
RSSI, RxBt, and T1 samples through the simulator's firmware telemetry path. It
also controls link state and post-boot value transitions, so Auto source
selection, NO LINK/NO DATA/STALE, history, low-is-good behavior, and Damping
0/9 are screenshots of runtime behavior rather than painted fixtures. The
current catalog declares 229 option cases: 221 native captures and eight
explicit rich-source skips (CELLS tables, timer, and one descending-history
sequence). It also includes eight layout galleries and 48 theme captures. See
[`docs/visual-kit/RUN_SUMMARY.md`](docs/visual-kit/RUN_SUMMARY.md) and the
[real settings evidence](docs/visual-kit/settings/S02-settings-top.png).

The mock enforces the firmware's real contract — property allow-lists per
object type, `{x, y}` point arrays, the missing string metatable, 10 ms
`getTime()` ticks, and the **integer option wire format with 1-based
choices**.

Three tools share one catalogue (`dev/scenes.lua`) and one emitter
(`dev/svgkit.lua`), so they cannot disagree about what the widget draws:

`dev/scenes.lua` retains the audited legacy `Style` vocabulary as input, but
selects `DialPro` or `BarPro` before building and rejects cross-family options.

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
