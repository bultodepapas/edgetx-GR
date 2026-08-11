# Gauge Pro Bar v2 — Phase 5 report

> **Histórico:** evidencia pre-split de Bar, hoy `GaugeBarPro`/`BarPro`. Consulte
> [`DOCUMENTATION.md`](DOCUMENTATION.md) para la arquitectura vigente.

**Completed:** 2026-08-09  
**Scope:** Orientation-neutral bar axes, production vertical rendering,
numeric-zero origin, asymmetric signed Dual Rail, conservative RC Center Auto
mapping, and advanced presentation slots 40–44. Temporal Motion behavior
remains the explicit Phase 6 scope.

## Outcome

Gauge Pro's bar is now a first-class instrument in tall layouts and for signed
RC controls. Horizontal and vertical are no longer separate approximations:
one axis descriptor maps the track, active fill, gradient slices, segmented
cells, thresholds, exact head, zero notch and all history markers. This removes
the geometry drift that normally appears when each overlay implements its own
percentage math.

The implementation keeps the project's three non-negotiables together:

- **Useful:** the numeric value, thresholds, history, state badge and exact
  position remain primary; signed controls never imply a false midpoint.
- **Beautiful:** vertical hierarchy, side information lanes, retained heads,
  scale marks, theme surfaces and custom palettes remain clean in stock, dark
  and high-contrast HTX themes.
- **Customizable:** every face works in both orientations; users choose origin,
  head, marks, value/name placement, thickness, surface and exact colors.

## What shipped

### One truthful axis

- `geometry.makeAxis()` describes orientation, start, length, growth direction,
  cross-axis geometry, numeric-zero position, clamped origin and exact pixel
  coordinates.
- Horizontal grows left-to-right. Vertical grows bottom-to-top; a descending
  authored scale reverses the semantic direction without swapping saved ends.
- `axisPoint`, `axisSpan` and `axisOriginSpan` give every face and overlay the
  same mapping.
- Tall Auto zones resolve vertically; explicit Horizontal/Vertical overrides
  remain deterministic.

### Numeric zero and Dual Rail

- Zero origin fills between the value and the real normalized zero coordinate,
  including asymmetric ranges such as `-30..100`.
- A permanent zero notch remains visible through data loss and recovery.
- If zero lies outside a one-sided scale, the resolver reports a clamp instead
  of pretending that an interior center exists.
- Dual Rail has two retained direction tracks split at numeric zero. Negative
  and positive active spans grow independently left/right or down/up.
- Custom Two preserves exact endpoints, demonstrated by the purple/yellow
  production fixtures.
- A one-sided Dual Rail request uses an explicit Continuous fallback.

### RC Center semantics

- Auto Source recognizes Aileron/Elevator/Rudder, channels, trims and GVars as
  centered controls only when the effective range strictly crosses zero.
- Throttle is deliberately classified separately and never gains a fake
  center merely because a manual scale is signed.
- Explicit user face/preset/origin choices still win; resolver data never
  mutates the saved option table.

### Advanced presentation

- Slots 40–44 append `Motion`, `Position head`, `Scale marks`, `Value position`
  and `Name position`; slots 45–50 remain reserved.
- The existing Damping row is relabeled **Gauge damping** without changing its
  position, key, type, default or `0..9` wire range.
- Position heads are materially distinct retained objects: None, Cap, Dot,
  Line and Needle.
- Scale overlays independently select Off, Thresholds, Ends or Full.
- Vertical Inside/End text uses a side information lane, not an overlay through
  the rail. Below name and safety-badge rows stack independently.
- Value and unit always move as one baseline-aligned group; long custom names
  stay single-line in every audited tall presentation.
- Motion's append-only option and preset resolution are present, but Off /
  Essential / Refined / Expressive temporal effects remain Phase 6.

## Performance correction found by the hard gates

The first production pass was functionally correct but failed the existing
`<2,000` ordinary-frame criterion: signed gradients rescanned every slice and
zero-origin Blocks rescanned every cell. The hard gate measured up to 3,934
instructions.

Phase 5 now caches the old active interval. Ordinary signed motion updates only
crossed cells plus the old/new partial boundaries; a full walk occurs only on
first paint or a real sign crossing. No gate was loosened.

| Moving path | Instructions/frame | Allocation |
|---|---:|---:|
| Vertical Continuous Gradient | **1,694–1,764** | **33 B** |
| Vertical Blocks 24 | **1,964–1,968** | **32 B** |
| Vertical true Hex 10 | **1,986–1,988** | **32 B** |
| Vertical Fine Ticks 24 | **1,888–1,890** | **32 B** |
| Vertical Signal Steps 10 | **1,466–1,470** | **32 B** |
| Zero-origin Gradient | **1,594–1,784** | **32 B** |
| Zero-origin Blocks 24 | **1,502–1,738** | **55 B** |
| Horizontal Dual Rail | **1,226–1,358** | **32 B** |
| Vertical Dual Rail | **1,246–1,378** | **32 B** |

The instruction ranges show the strict radio-style scenario and the independent
100-frame allocation probe. Every line remains below 10% of the firmware's
20,000-instruction callback limit on ordinary motion.

## Visual review findings and corrections

The 71-scene focused Phase 5 matrix and the complete 222-scene catalogue were
rendered in stock, dark and high-contrast palettes, then rasterized for image
inspection. That review found and corrected:

1. Inside value text crossed vertical ticks/heads. A side information lane now
   reserves separate rail and text geometry.
2. Long `AILERON` labels wrapped in Below/Inside layouts. Tall footer rows now
   stack, and the side lane is wide enough for the audited override.
3. A moved value could leave its unit on the old baseline. Unit geometry now
   follows every value placement and respects Left/Center/Right ink anchoring.
4. `Name = Above` overlapped the default Auto value row. Above rows now share
   one explicit stack.

## Measured gates

| Gate | Phase 5 result |
|---|---:|
| Pure Lua tests | **63 / 63** |
| Lifecycle / firmware-contract tests | **192 / 192** |
| Production catalogue | **222 scenes per theme, 0 failed** |
| Rendered theme-scene combinations | **666** |
| Gallery warnings | **0** |
| Visual option coverage | **complete** |
| Collision audit | **all cases clean** |
| Vertical Gradient + Full marks | **36 retained objects** |
| Vertical zero-origin Blocks 24 | **37 retained objects** |
| Horizontal / vertical Dual Rail | **16 retained objects** |
| Worst ordinary Phase 5 frame | **1,988 instructions** |
| Worst Phase 5 sign/state transition | **5,400 instructions** |
| Worst Phase 5 structural callback | **9,000 / 20,000** |
| Structural headroom | **55%** |

The instruction probe fails automatically at `2,000` ordinary, `6,000`
transition, `10,000` structural or `20,000` absolute callback instructions.
The allocation probe disables harness tracking, stops GC, and measures 100
changing frames. The collision audit covers vertical presentation variants,
zero origin and Dual Rail in addition to the existing dial/face matrices.

## Visual evidence

- `docs/phase5/full-validation/gallery-stock.svg` / `.png`
- `docs/phase5/full-validation/gallery-dark.svg` / `.png`
- `docs/phase5/high-contrast/gallery-highcontrast.svg` / `.png`
- `docs/gauge-pro-options.svg` / `.png`
- `docs/gauge-pro-options-dark.svg` / `.png`
- `docs/gauge-pro-options-highcontrast.svg` / `.png`

All images are emitted from the real production LVGL object tree. The Phase 5
PNG evidence is `1292×16056`; the official English option sheets are
`1232×18204`. They were full-page rasterized and dimension-verified after SVG
generation.

## Explicit deferral

Phase 6 owns temporal Motion behavior: bounded color transitions, activation
settle, stale/no-data fades and refined critical pulse. Phase 5 intentionally
does not add a second speed control; the existing Gauge damping slider remains
the frame-rate-independent position control.
